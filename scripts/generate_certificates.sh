#!/bin/sh
# Script to generate SSL certificates for SSLv2 compatibility
# Automatically patches certificates to work with old EA clients

set -e

CERT_DIR="${CERT_DIR:-/opt/eatunnel/certs}"
CA_NAME="OTG3"
OPENSSL_BIN="${OPENSSL_BIN:-/opt/openssl/bin/openssl}"

# Function to patch certificate DER file
# The certificate has 3 algorithm OIDs in this order:
# 1st: Issuer's signature algorithm (in TBSCertificate) - should be md5WithRSAEncryption
# 2nd: Public key algorithm (rsaEncryption) - always stays rsaEncryption
# 3rd: Certificate signature algorithm (at the end) - should be rsaEncryption (patched)
#
# OpenSSL with -md5 generates: md5, rsa, md5
# We need: md5, rsa, rsa (so replace the 3rd md5 with rsa)
#
# In hex: 2a864886f70d010104 = md5WithRSAEncryption
#         2a864886f70d010101 = rsaEncryption
patch_certificate_der() {
    local der_file=$1
    echo "Patching certificate: $der_file"
    
    # Convert DER to hex
    local hex_content=$(xxd -p "$der_file" | tr -d '\n')
    
    # Count occurrences of each OID
    local md5_count=$(echo "$hex_content" | grep -o "2a864886f70d010104" | wc -l)
    local rsa_count=$(echo "$hex_content" | grep -o "2a864886f70d010101" | wc -l)
    echo "Found $md5_count md5WithRSAEncryption and $rsa_count rsaEncryption OIDs"
    
    if [ "$md5_count" -lt 2 ]; then
        echo "Warning: Expected at least 2 md5WithRSAEncryption, found $md5_count"
        echo "Certificate may not be compatible with EA clients"
        return 0
    fi
    
    # Replace LAST occurrence of md5WithRSAEncryption with rsaEncryption
    # This affects the certificate signature algorithm at the end, not the issuer algorithm
    # We use a more robust approach: replace all, then restore the first one
    local temp_marker="XXXFIRSTXXX"
    local patched_hex=$(echo "$hex_content" | sed "s/2a864886f70d010104/$temp_marker/1; s/2a864886f70d010104/2a864886f70d010101/g; s/$temp_marker/2a864886f70d010104/1")
    
    # Convert back to DER
    echo "$patched_hex" | xxd -r -p > "${der_file}.tmp"
    mv "${der_file}.tmp" "$der_file"
    
    echo "Certificate patched: kept 1st md5WithRSAEncryption, replaced remaining with rsaEncryption"
}

# Function to configure OpenSSL for compatibility
configure_openssl() {
    local openssl_cnf="/opt/openssl/openssl.cnf"
    
    if [ -f "$openssl_cnf" ]; then
        echo "Configuring OpenSSL for SSLv2 compatibility..."
        # Change string_mask from utf8only to default
        sed -i 's/string_mask = utf8only/string_mask = default/g' "$openssl_cnf" || true
        sed -i 's/string_mask=utf8only/string_mask=default/g' "$openssl_cnf" || true
    fi
}

# Function to generate certificate for a service
generate_certificate() {
    local service_name=$1
    local cn="${service_name}.ea.com"
    
    echo "=========================================="
    echo "Generating certificate for: $service_name"
    echo "=========================================="
    
    cd "$CERT_DIR"
    
    # Create Certificate Authority if it doesn't exist
    if [ ! -f "${CA_NAME}.key.pem" ] || [ ! -f "${CA_NAME}.crt" ]; then
        echo "Creating Certificate Authority: $CA_NAME"
        
        # Create private key for CA
        $OPENSSL_BIN genrsa -aes128 -out "${CA_NAME}.key.pem" -passout pass:123456 1024
        $OPENSSL_BIN rsa -in "${CA_NAME}.key.pem" -out "${CA_NAME}.key.pem" -passin pass:123456
        
        # Create CA certificate with 1 day validity to ensure UTCTime format (pre-2050)
        # Client ignores certificate expiration, only date format matters
        CA_SERIAL=$(date +%s)
        $OPENSSL_BIN req -new -md5 -x509 -days 1 -key "${CA_NAME}.key.pem" -out "${CA_NAME}.crt" \
            -subj "/C=US/ST=California/L=Redwood City/O=Electronic Arts, Inc./OU=Online Technology Group/CN=OTG3 Certificate Authority" \
            -set_serial $CA_SERIAL
        
        echo "Certificate Authority created successfully"
    else
        echo "Using existing Certificate Authority: $CA_NAME"
    fi
    
    # Generate certificate for the service
    echo "Generating certificate for service: $service_name"
    
    # Create private key
    $OPENSSL_BIN genrsa -aes128 -out "${service_name}.key.pem" -passout pass:123456 1024
    $OPENSSL_BIN rsa -in "${service_name}.key.pem" -out "${service_name}.key.pem" -passin pass:123456
    
    # Create certificate signing request
    $OPENSSL_BIN req -new -key "${service_name}.key.pem" -out "${service_name}.csr" \
        -subj "/C=US/ST=California/O=Electronic Arts, Inc./OU=Global Online Studio/CN=$cn"
    
    # Generate random serial number (timestamp-based)
    CERT_SERIAL=$(date +%s%N 2>/dev/null || date +%s)
    
    # Create the certificate with 1 day validity to ensure UTCTime format (pre-2050)
    # Client ignores certificate expiration, only date format matters
    $OPENSSL_BIN x509 -req -md5 -in "${service_name}.csr" -CA "${CA_NAME}.crt" -CAkey "${CA_NAME}.key.pem" \
        -CAcreateserial -out "${service_name}.crt" -days 1 \
        -set_serial $CERT_SERIAL
    
    # Export to DER format for patching
    $OPENSSL_BIN x509 -outform der -in "${service_name}.crt" -out "${service_name}.der"
    
    # Patch the algorithm OIDs
    patch_certificate_der "${service_name}.der"

    # Convert patched DER back to PEM
    $OPENSSL_BIN x509 -inform der -in "${service_name}.der" -out "${service_name}.cert.pem"
    
    # Create combined PEM file (cert + key) for stunnel
    cat "${service_name}.cert.pem" "${service_name}.key.pem" > "${service_name}.pem"
    
    # Cleanup temporary files
    rm -f "${service_name}.csr" "${service_name}.der" "${service_name}.crt" "${service_name}.cert.pem"
    
    echo "Certificate generated successfully: ${service_name}.pem"
    echo ""
}

# Main execution
main() {
    echo "================================================"
    echo "SSL Certificate Generator for EA SSLv2 Services"
    echo "================================================"
    
    # Create certificate directory
    mkdir -p "$CERT_DIR"
    
    # Configure OpenSSL
    configure_openssl
    
    # Check if services are provided
    if [ -z "$1" ]; then
        echo "Error: No service names provided"
        echo "Usage: $0 service1 service2 service3 ..."
        exit 1
    fi
    
    # Generate certificate for each service (handle each argument separately)
    for service in $@; do
        # Trim whitespace
        service=$(echo "$service" | tr -d ' ')
        if [ -n "$service" ]; then
            generate_certificate "$service"
        fi
    done
    
    echo "================================================"
    echo "All certificates generated successfully!"
    echo "Location: $CERT_DIR"
    echo "================================================"
}

main $@
