#!/bin/sh
# Provision script - downloads and compiles OpenSSL with SSLv2 and stunnel
set -e

app_home=$1
cd $app_home

echo "================================================"
echo "Building OpenSSL with SSLv2 support"
echo "================================================"

# Download and extract OpenSSL
# 1.0.2u is the last PUBLIC 1.0.2 release (Dec 2019); later 1.0.2z* versions are
# only available under OpenSSL's paid premium support.
wget -q https://github.com/openssl/openssl/releases/download/OpenSSL_1_0_2u/openssl-1.0.2u.tar.gz
tar -xf openssl-1.0.2u.tar.gz
openssldir=openssl-1.0.2u
cd $openssldir

echo "Configuring OpenSSL..."
# no-ec is required so a modern stunnel can initialize an SSLv2 context: without
# it stunnel tries to apply an ECDH groups list that an SSLv2 context rejects
# ("Invalid groups list in 'curves'" -> "Failed to initialize TLS context").
./config --prefix=/opt/openssl --openssldir=/opt/openssl enable-ssl2 enable-ssl3 enable-weak-ssl-ciphers no-ec no-shared

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
# Latest stunnel (self-reports as 5.78; source is the 5.79 archive). Works with
# SSLv2 thanks to the no-ec OpenSSL build above.
wget -q https://www.stunnel.org/archive/5.x/stunnel-5.79.tar.gz
tar xzf stunnel-5.79.tar.gz
cd stunnel-5.79/

echo "Configuring stunnel..."
./configure --with-ssl=/opt/openssl CPPFLAGS="-I/opt/openssl/include" LDFLAGS="-L/opt/openssl/lib"

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

