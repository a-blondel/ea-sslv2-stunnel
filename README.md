# EA SSLv2 Stunnel - Automated Certificate Generation & SSL Proxy

**Automated solution to support SSLv2 for legacy EA clients**

This project provides a Docker container that automatically configures stunnel with SSLv2 support to redirect SSL traffic to backend servers. Certificates are automatically generated and patched at container startup.

## Features

- Automatic SSL certificate generation exploiting the [Old ProtoSSL Bug](https://github.com/Aim4kill/Bug_OldProtoSSL)
- Dynamic configuration via environment variables
- Multi-service support: multiple certificates and redirections in a single container

## Quick Start

### 1. Configuration

Edit the `docker-compose.yml` file and configure your services:

```yaml
environment:
  # List of services with their redirect ports
  # Format: service1:port1,port2;service2:port3,port4
  # Multiple ports per service separated by commas
  # Multiple services separated by semicolons
  SSL_SERVICES: "pspnfs06:30980,30990;pspnba06:30190"
  
  # Backend server IP address
  REDIRECT_IP: "127.0.0.1"
```

**Important**: 
- The **SSL listen port** will be automatically calculated as `redirect_port + 1`
- **One certificate** is generated per service, even with multiple ports
- Example: `pspnfs06:30980,30990` generates 1 certificate and creates 2 stunnel services:
  - Service 1: listens on **30981** → redirects to **127.0.0.1:30980**
  - Service 2: listens on **30991** → redirects to **127.0.0.1:30990**

### 2. Expose Ports

Configure exposed ports in `docker-compose.yml`:

```yaml
ports:
  - "30981:30981"  # pspnfs06 port 1 (30980 + 1)
  - "30991:30991"  # pspnfs06 port 2 (30990 + 1)
  - "30191:30191"  # pspnba06 (30190 + 1)
```

### 3. Launch

```bash
docker-compose build
docker-compose up -d
```

### 4. Verification

```bash
# View logs
docker-compose logs -f

# Verify stunnel is running
docker exec ea-sslv2-stunnel ps aux | grep stunnel

# Check generated certificates
docker exec ea-sslv2-stunnel ls -la /opt/eatunnel/certs/

# Copy certificates to host
docker cp ea-sslv2-stunnel:/opt/eatunnel/certs/ ./certs/

# Inspect a certificate
openssl asn1parse -in mycert.pem

# Check listening ports
netstat -tulpn | grep 30191

# Test connection from outside the container (replace PORT with the SSL listen port)
openssl s_client -connect localhost:PORT -ssl2
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SSL_SERVICES` | Yes | - | List of services and redirect ports<br/>Format: `service1:port1,port2;service2:port3`<br/>Multiple ports separated by `,` / Services by `;` |
| `REDIRECT_IP` | Yes | `127.0.0.1` | Backend server IP address |
| `CERT_DIR` | No | `/opt/eatunnel/certs` | Certificate directory |
| `STUNNEL_CONF` | No | `/app/stunnel.conf` | Stunnel configuration file path |
| `OPENSSL_BIN` | No | `/opt/openssl/bin/openssl` | OpenSSL executable path |

## Project Structure

```
.
├── Dockerfile                          # Docker image
├── docker-compose.yml                  # Docker Compose configuration
└── scripts/
    ├── bootstrap.sh                    # Main startup script
    ├── provision.sh                    # OpenSSL + stunnel compilation
    ├── generate_certificates.sh        # Certificate generation and patching
    ├── configure_stunnel.sh            # Dynamic stunnel configuration
    └── start.sh                        # Stunnel startup
```

## How It Works

### 1. Certificate Generation (generate_certificates.sh)

At startup, the script:
1. Modifies `openssl.cnf` to set `string_mask = default`
2. Generates a Certificate Authority (CA) if it doesn't exist
3. For each service in `SSL_SERVICES`:
   - Generates a 1024-bit RSA private key
   - Creates a certificate signed by the CA
   - Exports the certificate to DER format
   - Automatically patches the certificate
   - Converts back to PEM format
   - Combines certificate + key into a `.pem` file

### 2. Stunnel Configuration (configure_stunnel.sh)

The script dynamically generates `stunnel.conf` with:
- Global SSLv2 configuration
- One section per service with:
  - Listen port: `redirect_port + 1`
  - Redirect to: `REDIRECT_IP:redirect_port`
  - Associated certificate and key

### 3. Startup (bootstrap.sh)

Complete orchestration:
1. Environment variable validation
2. Service name extraction
3. Certificate generation
4. Stunnel configuration
5. Stunnel startup
6. Display active services summary

## Usage Examples

### Example 1: Simple Service (Single Port)

```yaml
environment:
  SSL_SERVICES: "pspnba06:30190"
  REDIRECT_IP: "127.0.0.1"
ports:
  - "30191:30191"
```

Result:
- Listens on `0.0.0.0:30191` (SSLv2)
- Redirects to `127.0.0.1:30190` (non-SSL)
- 1 certificate generated for `pspnba06.ea.com`

### Example 2: Service with Multiple Ports (Same Certificate)

```yaml
environment:
  SSL_SERVICES: "pspnfs06:30980,30990,31000"
  REDIRECT_IP: "127.0.0.1"
ports:
  - "30981:30981"
  - "30991:30991"
  - "31001:31001"
```

Result:
- **1 certificate** for `pspnfs06.ea.com`
- 3 stunnel services created:
  - `30981` → `127.0.0.1:30980`
  - `30991` → `127.0.0.1:30990`
  - `31001` → `127.0.0.1:31000`

### Example 3: Multiple Services with Multiple Ports Each

```yaml
environment:
  SSL_SERVICES: "pspnfs06:30980,30990;pspnba06:30190,30195;psptest01:40100"
  REDIRECT_IP: "10.0.1.50"
ports:
  - "30981:30981"
  - "30991:30991"
  - "30191:30191"
  - "30196:30196"
  - "40101:40101"
```

Result:
- 3 certificates generated (pspnfs06, pspnba06, psptest01)
- 5 stunnel services total
- 1 single Docker container

### Example 4: Certificate Persistence

```yaml
environment:
  SSL_SERVICES: "pspnfs06:30980,30990;pspnba06:30190"
  REDIRECT_IP: "127.0.0.1"
volumes:
  - ./certs:/opt/eatunnel/certs
```

Certificates will be preserved between container restarts.

## Credits

- Stunnel implementation inspired from https://gitlab.com/gh0stl1ne/eaps
- Old ProtoSSL Bug from https://github.com/Aim4kill/Bug_OldProtoSSL
