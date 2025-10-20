#!/bin/sh
# Bootstrap script - initializes and starts the stunnel service

set -e

echo "================================================"
echo "EA SSLv2 Stunnel Container Starting..."
echo "================================================"

# Configuration
CERT_DIR="${CERT_DIR:-/opt/eatunnel/certs}"
SSL_SERVICES="${SSL_SERVICES}"
REDIRECT_IP="${REDIRECT_IP:-127.0.0.1}"

# Validate environment variables
if [ -z "$SSL_SERVICES" ]; then
    echo "Error: SSL_SERVICES environment variable is required"
    echo "Format: service1:port1,port2;service2:port3,port4"
    echo "Example: pspnfs06:30980,30990;pspnba06:30190"
    exit 1
fi

echo "Configuration:"
echo "  Services: $SSL_SERVICES"
echo "  Redirect IP: $REDIRECT_IP"
echo "  Certificate Directory: $CERT_DIR"
echo ""

# Extract service names from SSL_SERVICES (format: service:port1,port2;service2:port3)
echo "Step 1: Extracting service names..."
SERVICE_NAMES=""
IFS=';'
for service_block in $SSL_SERVICES; do
    service_name=$(echo "$service_block" | cut -d':' -f1 | tr -d ' ')
    if [ -n "$service_name" ]; then
        # Check if not already in list (avoid duplicates)
        case " $SERVICE_NAMES " in
            *" $service_name "*) ;;
            *) SERVICE_NAMES="$SERVICE_NAMES $service_name" ;;
        esac
    fi
done

echo "Services to configure: $SERVICE_NAMES"
echo ""

# Generate certificates (one at a time to avoid issues)
echo "Step 2: Generating SSL certificates..."
cd /opt/eatunnel/scripts

# Call generate_certificates.sh with each service as separate argument
for service in $SERVICE_NAMES; do
    echo "Generating certificate for: $service"
done

# Pass all service names as separate arguments (not as a single string)
./generate_certificates.sh $SERVICE_NAMES

if [ $? -ne 0 ]; then
    echo "Error: Certificate generation failed"
    exit 1
fi
echo ""

# Configure stunnel
echo "Step 3: Configuring stunnel..."
./configure_stunnel.sh

if [ $? -ne 0 ]; then
    echo "Error: Stunnel configuration failed"
    exit 1
fi
echo ""

# Start stunnel
echo "Step 4: Starting stunnel..."
./start.sh

if [ $? -ne 0 ]; then
    echo "Error: Failed to start stunnel"
    exit 1
fi

echo ""
echo "================================================"
echo "Stunnel started successfully!"
echo "================================================"
echo "Services running:"
IFS=';'
for service_block in $SSL_SERVICES; do
    service_name=$(echo "$service_block" | cut -d':' -f1 | tr -d ' ')
    ports_list=$(echo "$service_block" | cut -d':' -f2 | tr -d ' ')
    echo "  $service_name:"
    IFS=','
    for redirect_port in $ports_list; do
        redirect_port=$(echo "$redirect_port" | tr -d ' ')
        listen_port=$((redirect_port + 1))
        echo "    - 0.0.0.0:$listen_port -> ${REDIRECT_IP}:${redirect_port}"
    done
    IFS=';'
done
echo "================================================"

# Check if stunnel started successfully
sleep 2
if ! pgrep stunnel > /dev/null; then
    echo ""
    echo "ERROR: Stunnel failed to start!"
    echo "Check the configuration above for errors."
    echo ""
    echo "Debugging information:"
    echo "- Certificates in $CERT_DIR:"
    ls -la "$CERT_DIR"
    echo ""
    echo "- Stunnel configuration:"
    cat /app/stunnel.conf
    exit 1
fi

# Keep container running
if [[ $1 == "-d" ]] || [ -z "$1" ]; then
  echo "Container running in daemon mode. Press Ctrl+C to stop."
  while true; do sleep 1000; done
fi

if [[ $1 == "-bash" ]]; then
  /bin/bash
fi
