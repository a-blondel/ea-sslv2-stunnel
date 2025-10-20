FROM alpine:3.16.5

# Install required dependencies
# Only install what's needed for OpenSSL and stunnel compilation
RUN apk --update --no-cache add \
    build-base \
    linux-headers \
    curl \
    perl \
    && rm -rf /var/cache/apk/*

# Create application directory
RUN mkdir -p /opt/eatunnel/certs /app

# Copy scripts
COPY scripts /opt/eatunnel/scripts
WORKDIR /opt/eatunnel

# Make scripts executable
RUN chmod -R +x scripts

# Build OpenSSL with SSLv2 support and stunnel
RUN scripts/provision.sh /opt/eatunnel

# Clean up build dependencies to reduce image size
RUN apk del build-base linux-headers perl && \
    rm -rf /opt/eatunnel/openssl-* \
           /opt/eatunnel/stunnel-* \
           /opt/eatunnel/*.tar.gz \
           /var/cache/apk/*

# Environment variables with defaults
ENV CERT_DIR=/opt/eatunnel/certs \
    STUNNEL_CONF=/app/stunnel.conf \
    REDIRECT_IP=127.0.0.1 \
    OPENSSL_BIN=/opt/openssl/bin/openssl

# SSL_SERVICES must be provided at runtime
# Format: service1:port1,port2;service2:port3,port4
# Multiple ports per service separated by commas
# Multiple services separated by semicolons
# Example: SSL_SERVICES=pspnfs06:30980,30990;pspnba06:30190

CMD ["/opt/eatunnel/scripts/bootstrap.sh", "-d"]
