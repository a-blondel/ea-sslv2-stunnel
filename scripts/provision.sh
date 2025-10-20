#!/bin/sh
# Provision script - downloads and compiles OpenSSL with SSLv2 and stunnel
set -e

app_home=$1
cd $app_home

echo "================================================"
echo "Building OpenSSL with SSLv2 support"
echo "================================================"

# Download and extract OpenSSL
wget -q https://www.openssl.org/source/openssl-1.0.2k.tar.gz
tar -xf openssl-1.0.2k.tar.gz
openssldir=openssl-1.0.2k
cd $openssldir

echo "Configuring OpenSSL..."
./config --prefix=/opt/openssl --openssldir=/opt/openssl enable-ssl2 enable-ssl3 enable-weak-ssl-ciphers no-shared

echo "Building OpenSSL (this may take a few minutes)..."
make depend
make -j$(nproc)
make install

if [ $? -eq 0 ]; then
   echo "OpenSSL installed successfully at /opt/openssl"
else
   echo "Error: OpenSSL installation failed"
   exit 1
fi

# Modify openssl.cnf for compatibility
echo "Configuring OpenSSL for SSLv2 compatibility..."
if [ -f "/opt/openssl/openssl.cnf" ]; then
    sed -i 's/string_mask = utf8only/string_mask = default/g' /opt/openssl/openssl.cnf || true
    sed -i 's/string_mask=utf8only/string_mask=default/g' /opt/openssl/openssl.cnf || true
    echo "OpenSSL configuration updated (string_mask = default)"
fi

echo ""
echo "================================================"
echo "Building stunnel"
echo "================================================"

cd $app_home
wget -q https://www.stunnel.org/archive/5.x/stunnel-5.58.tar.gz
tar xzf stunnel-5.58.tar.gz
cd stunnel-5.58/

echo "Configuring stunnel..."
./configure CPPFLAGS="-I/opt/openssl/include" LDFLAGS="-L/opt/openssl/lib"

echo "Building stunnel..."
make -j$(nproc)
make install

if [ $? -eq 0 ]; then
   echo "stunnel installed successfully at /usr/local/bin/stunnel"
else
   echo "Error: stunnel installation failed"
   exit 1
fi

echo ""
echo "================================================"
echo "Provisioning completed successfully!"
echo "================================================"
echo "OpenSSL: /opt/openssl/bin/openssl"
echo "stunnel: /usr/local/bin/stunnel"
echo "================================================"

