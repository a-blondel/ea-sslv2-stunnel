#!/bin/sh
# Script to configure stunnel based on environment variables
# Generates stunnel.conf dynamically for multiple services

set -e

STUNNEL_CONF="${STUNNEL_CONF:-/app/stunnel.conf}"
CERT_DIR="${CERT_DIR:-/opt/eatunnel/certs}"
SSL_SERVICES="${SSL_SERVICES}"
REDIRECT_IP="${REDIRECT_IP:-127.0.0.1}"

# Function to generate stunnel configuration
generate_stunnel_config() {
    echo "Generating stunnel configuration..."
    
    # Create base configuration
    cat > "$STUNNEL_CONF" <<EOF
; Stunnel configuration for EA SSLv2 services
; Auto-generated configuration

; Global options
foreground = no
sslVersion = SSLv2
ciphers = SSLv2

; Debug level
; debug = 7

EOF

    # Check if SSL_SERVICES is provided
    if [ -z "$SSL_SERVICES" ]; then
        echo "Error: SSL_SERVICES environment variable is not set"
        echo "Expected format: service1:port1,port2;service2:port3,port4"
        echo "Example: pspnfs06:30980,30990;pspnba06:30190"
        exit 1
    fi
    
    echo "Configuring services from SSL_SERVICES: $SSL_SERVICES"
    
    # Parse SSL_SERVICES: format is service:port1,port2;service2:port3
    # First split by ';' to get each service
    IFS=';'
    for service_block in $SSL_SERVICES; do
        # Parse service:ports
        service_name=$(echo "$service_block" | cut -d':' -f1 | tr -d ' ')
        ports_list=$(echo "$service_block" | cut -d':' -f2 | tr -d ' ')
        
        if [ -z "$service_name" ] || [ -z "$ports_list" ]; then
            echo "Warning: Invalid service block: $service_block (skipping)"
            continue
        fi
        
        # Certificate paths (one certificate per service)
        cert_file="${CERT_DIR}/${service_name}.pem"
        key_file="${CERT_DIR}/${service_name}.key.pem"
        
        # Check if certificate exists
        if [ ! -f "$cert_file" ]; then
            echo "Warning: Certificate not found for $service_name at $cert_file"
            echo "Skipping service: $service_name"
            continue
        fi
        
        echo "Configuring service: $service_name with ports: $ports_list"
        
        # Now parse each port for this service
        port_index=1
        IFS=','
        for redirect_port in $ports_list; do
            redirect_port=$(echo "$redirect_port" | tr -d ' ')
            
            if [ -z "$redirect_port" ]; then
                continue
            fi
            
            # Calculate listen port (redirect_port + 1)
            listen_port=$((redirect_port + 1))
            
            echo "  - Port $port_index: listen $listen_port -> redirect ${REDIRECT_IP}:${redirect_port}"
            
            # Add service section to stunnel config
            # Use unique section name if multiple ports for same service
            if [ $port_index -eq 1 ]; then
                section_name="${service_name}"
            else
                section_name="${service_name}-port${port_index}"
            fi
            
            cat >> "$STUNNEL_CONF" <<EOF
; Service: $service_name (port $port_index)
[${section_name}]
accept = 0.0.0.0:${listen_port}
connect = ${REDIRECT_IP}:${redirect_port}
cert = ${cert_file}
key = ${key_file}

EOF
            port_index=$((port_index + 1))
        done
        
        # Reset IFS for next service block
        IFS=';'
    done
    
    echo "Stunnel configuration generated successfully: $STUNNEL_CONF"
    echo ""
    echo "Configuration preview:"
    echo "----------------------------------------"
    cat "$STUNNEL_CONF"
    echo "----------------------------------------"
}

# Main execution
main() {
    echo "================================================"
    echo "Stunnel Configuration Generator"
    echo "================================================"
    echo "Redirect IP: $REDIRECT_IP"
    echo "Services: $SSL_SERVICES"
    echo "Certificate Directory: $CERT_DIR"
    echo "================================================"
    echo ""
    
    generate_stunnel_config
    
    echo ""
    echo "Configuration completed successfully!"
}

main
