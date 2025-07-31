# HAProxy Wildcard SSL Deployment Guide

This guide provides comprehensive instructions for deploying and managing the HAProxy wildcard SSL proxy system.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Detailed Setup](#detailed-setup)
4. [Configuration](#configuration)
5. [Deployment](#deployment)
6. [Post-Deployment](#post-deployment)
7. [Backend Integration](#backend-integration)
8. [Monitoring](#monitoring)
9. [Maintenance](#maintenance)
10. [Troubleshooting](#troubleshooting)
11. [Security Considerations](#security-considerations)

## Prerequisites

### System Requirements

- **Operating System**: Linux (Ubuntu 20.04+ recommended)
- **Docker**: Version 20.10 or later
- **Docker Compose**: Version 2.0 or later
- **Memory**: Minimum 2GB RAM (4GB+ recommended)
- **Storage**: Minimum 10GB free space
- **Network**: Internet connectivity for certificate generation

### Domain Requirements

- **Domain Ownership**: You must own the domain for certificate generation
- **DNS Access**: API access to your DNS provider (Cloudflare, Route53, etc.)
- **DNS Configuration**: Ability to create DNS records

### Access Requirements

- **Root/Sudo Access**: Required for Docker installation and port binding
- **Firewall Configuration**: Ports 80 and 443 must be accessible from the internet

## Quick Start

For experienced users who want to get started quickly:

```bash
# 1. Clone or download the project
cd demo.colakdo.com

# 2. Configure environment
cp .env.example .env
# Edit .env with your settings

# 3. Configure DNS credentials
cp dns-credentials/cloudflare.ini.example dns-credentials/cloudflare.ini
# Edit with your DNS provider credentials
chmod 600 dns-credentials/cloudflare.ini

# 4. Deploy
./scripts/deploy.sh

# 5. Verify
curl -k https://your-domain.com
```

## Detailed Setup

### Step 1: Environment Preparation

#### Install Docker and Docker Compose

**Ubuntu/Debian:**
```bash
# Update package index
sudo apt update

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo apt install docker-compose-plugin
```

**CentOS/RHEL:**
```bash
# Install Docker
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

#### Verify Installation

```bash
# Check Docker
docker --version
docker run hello-world

# Check Docker Compose
docker compose version
```

### Step 2: Project Setup

#### Download Project Files

```bash
# If using git
git clone <repository-url>
cd demo.colakdo.com

# Or download and extract archive
wget <archive-url>
tar -xzf haproxy-wildcard-ssl.tar.gz
cd demo.colakdo.com
```

#### Set File Permissions

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Set secure permissions for sensitive files
chmod 700 dns-credentials/
chmod 600 .env.example
```

### Step 3: Configuration

#### Environment Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit configuration
nano .env
```

**Required Settings:**
```bash
# Your email for Let's Encrypt
LETSENCRYPT_EMAIL=admin@yourdomain.com

# Your domain
DOMAIN=yourdomain.com

# DNS provider
DNS_PLUGIN=dns-cloudflare

# Secure password for HAProxy stats
STATS_PASSWORD=your-secure-password-here
```

#### DNS Provider Setup

Choose your DNS provider and configure credentials:

**Cloudflare:**
```bash
cp dns-credentials/cloudflare.ini.example dns-credentials/cloudflare.ini
nano dns-credentials/cloudflare.ini
```

Add your Cloudflare API token:
```ini
dns_cloudflare_api_token = your-api-token-here
```

**Route53:**
```bash
cp dns-credentials/route53.ini.example dns-credentials/route53.ini
nano dns-credentials/route53.ini
```

Add your AWS credentials:
```ini
dns_route53_access_key_id = your-access-key
dns_route53_secret_access_key = your-secret-key
```

**Set Secure Permissions:**
```bash
chmod 600 dns-credentials/*.ini
```

### Step 4: Pre-Deployment Validation

#### Validate Configuration

```bash
# Check environment configuration
./scripts/deploy.sh --dry-run

# Validate DNS credentials
./scripts/setup-dns-provider.sh validate
```

#### Test DNS Access

```bash
# Test DNS API access (Cloudflare example)
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
     -H "Authorization: Bearer your-api-token" \
     -H "Content-Type: application/json"
```

## Deployment

### Automated Deployment

The recommended deployment method uses the automated deployment script:

```bash
# Full deployment with health checks
./scripts/deploy.sh

# Quick deployment without waiting for health checks
./scripts/deploy.sh --no-wait

# Deployment with verbose logging
./scripts/deploy.sh --verbose
```

### Manual Deployment

For more control over the deployment process:

```bash
# 1. Create Docker network
docker network create proxy-network --driver bridge --attachable

# 2. Start services in order
docker-compose up -d syslog
docker-compose up -d certbot
docker-compose up -d maintenance-server
docker-compose up -d haproxy
docker-compose up -d log-rotator monitor backend-discovery config-watcher

# 3. Verify services
docker-compose ps
```

### Deployment Verification

#### Check Service Status

```bash
# View service status
./scripts/startup.sh status

# Check service health
./scripts/startup.sh health

# View logs
docker-compose logs -f
```

#### Verify Certificate Generation

```bash
# Check certificate status
ls -la certs/live/yourdomain.com/

# View certificate details
openssl x509 -in certs/live/yourdomain.com/fullchain.pem -text -noout
```

#### Test HAProxy

```bash
# Check HAProxy health
curl http://localhost:8404/health

# View HAProxy stats
curl http://admin:your-password@localhost:8404/stats

# Test HTTPS endpoint
curl -k https://yourdomain.com
```

## Post-Deployment

### DNS Configuration

Configure your DNS to point to your server:

```bash
# A records for your domain
yourdomain.com.     A    your-server-ip
*.yourdomain.com.   A    your-server-ip

# Or CNAME records if using a subdomain
*.yourdomain.com.   CNAME   your-server.example.com.
```

### Firewall Configuration

Ensure required ports are open:

```bash
# UFW (Ubuntu)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8404/tcp  # HAProxy stats (optional, restrict to admin IPs)

# iptables
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8404 -j ACCEPT
```

### Initial Testing

```bash
# Test HTTP redirect (should return 403 or redirect to HTTPS)
curl -I http://yourdomain.com

# Test HTTPS
curl -I https://yourdomain.com

# Test wildcard certificate
curl -I https://test.yourdomain.com
curl -I https://api.yourdomain.com
```

## Backend Integration

### Adding Backend Services

#### Method 1: Automatic Discovery

Create a service with proper labels:

```yaml
services:
  my-app:
    image: my-app:latest
    networks:
      - proxy-network
    environment:
      - SERVICE_NAME=my-app
      - SERVICE_TYPE=app
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]

networks:
  proxy-network:
    external: true
```

#### Method 2: Manual Configuration

Edit `config/haproxy.cfg` and add backend configuration:

```haproxy
backend my-app-backend
    balance roundrobin
    option httpchk GET /health
    server my-app-1 my-app:8080 check
```

### Service Examples

Use the provided examples:

```bash
# Start example services
cd examples
docker-compose -f example-backend-service.yml up -d

# Test services
curl -k https://www.yourdomain.com
curl -k https://api.yourdomain.com/api/health
```

## Monitoring

### Built-in Monitoring

#### HAProxy Statistics

Access HAProxy stats at: `http://your-server:8404/stats`

- Username: `admin`
- Password: (from STATS_PASSWORD in .env)

#### Health Checks

```bash
# Check all services
./scripts/startup.sh health

# Monitor services continuously
./scripts/startup.sh monitor

# Check certificate status
./scripts/certificate-expiration-monitor.sh status
```

#### Log Monitoring

```bash
# View real-time logs
tail -f logs/haproxy.log

# View access logs
tail -f logs/access.log

# View error logs
tail -f logs/error.log

# Use log management script
./scripts/manage-logs.sh tail all
```

### External Monitoring

#### Prometheus Integration

Add Prometheus monitoring (optional):

```yaml
# Add to docker-compose.yml
prometheus:
  image: prom/prometheus
  ports:
    - "9090:9090"
  volumes:
    - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
```

#### Log Aggregation

Configure log shipping to external systems:

```bash
# Example: Ship logs to ELK stack
# Configure in docker-compose.yml or use log drivers
```

## Maintenance

### Certificate Renewal

Certificates are automatically renewed, but you can manage them manually:

```bash
# Check renewal status
./scripts/renewal-monitor.sh status

# Force renewal
./scripts/certificate-renewal.sh --force

# Test renewal system
./scripts/renewal-monitor.sh test
```

### Configuration Updates

#### HAProxy Configuration

```bash
# Edit configuration
nano config/haproxy.cfg

# Validate configuration
./scripts/validate-haproxy-config.sh

# Reload configuration
docker kill -s HUP haproxy-proxy
```

#### Environment Updates

```bash
# Edit environment
nano .env

# Restart services to apply changes
./scripts/startup.sh restart
```

### Backup and Restore

#### Backup

```bash
# Create backup script
cat > backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/haproxy-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup certificates
cp -r certs/ "$BACKUP_DIR/"

# Backup configuration
cp -r config/ "$BACKUP_DIR/"

# Backup environment
cp .env "$BACKUP_DIR/"

# Backup logs (optional)
cp -r logs/ "$BACKUP_DIR/"

echo "Backup created: $BACKUP_DIR"
EOF

chmod +x backup.sh
./backup.sh
```

#### Restore

```bash
# Restore from backup
BACKUP_DIR="/backup/haproxy-20231201-120000"

# Stop services
./scripts/startup.sh stop

# Restore files
cp -r "$BACKUP_DIR/certs/" ./
cp -r "$BACKUP_DIR/config/" ./
cp "$BACKUP_DIR/.env" ./

# Start services
./scripts/startup.sh start
```

### Updates and Upgrades

#### Update Docker Images

```bash
# Pull latest images
docker-compose pull

# Restart services with new images
docker-compose up -d --force-recreate
```

#### Update Scripts

```bash
# Download updated scripts
# Replace scripts/ directory with new versions

# Make executable
chmod +x scripts/*.sh

# Test deployment
./scripts/deploy.sh --dry-run
```

## Troubleshooting

### Common Issues

#### Certificate Generation Fails

**Symptoms:**
- No certificate files in `certs/live/`
- Certbot container exits with errors

**Solutions:**
```bash
# Check DNS credentials
cat dns-credentials/cloudflare.ini

# Test DNS API access
./scripts/setup-dns-provider.sh validate

# Check Certbot logs
docker-compose logs certbot

# Try manual certificate generation
docker-compose exec certbot certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/dns-credentials/cloudflare.ini \
  -d "*.yourdomain.com" -d "yourdomain.com"
```

#### HAProxy Won't Start

**Symptoms:**
- HAProxy container exits immediately
- Configuration validation errors

**Solutions:**
```bash
# Validate HAProxy configuration
./scripts/validate-haproxy-config.sh

# Check HAProxy logs
docker-compose logs haproxy

# Test configuration manually
docker run --rm -v $(pwd)/config:/usr/local/etc/haproxy:ro \
  haproxy:2.8-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

#### Backend Services Not Accessible

**Symptoms:**
- 503 Service Unavailable errors
- Backend shows as down in stats

**Solutions:**
```bash
# Check if service is on proxy-network
docker network inspect proxy-network

# Test backend health directly
docker exec backend-container curl http://localhost:8080/health

# Check HAProxy backend status
curl http://admin:password@localhost:8404/stats

# Review backend discovery logs
docker-compose logs backend-discovery
```

#### SSL Certificate Issues

**Symptoms:**
- SSL certificate warnings in browser
- Certificate not trusted

**Solutions:**
```bash
# Check certificate validity
openssl x509 -in certs/live/yourdomain.com/fullchain.pem -text -noout

# Verify certificate chain
openssl verify -CAfile certs/live/yourdomain.com/chain.pem \
  certs/live/yourdomain.com/cert.pem

# Test SSL configuration
curl -vvI https://yourdomain.com
```

### Performance Issues

#### High CPU Usage

```bash
# Check container resource usage
docker stats

# Review HAProxy configuration for optimization
# Increase maxconn, adjust timeouts

# Monitor connection patterns
curl http://admin:password@localhost:8404/stats
```

#### High Memory Usage

```bash
# Set memory limits in docker-compose.yml
deploy:
  resources:
    limits:
      memory: 512M

# Monitor memory usage
docker stats --format "table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

#### Slow Response Times

```bash
# Check backend response times in HAProxy stats
curl http://admin:password@localhost:8404/stats

# Monitor logs for slow requests
grep "slow" logs/haproxy.log

# Optimize backend services
# Add more backend instances
# Implement caching
```

### Log Analysis

#### Common Log Patterns

```bash
# Find error patterns
grep "ERROR" logs/haproxy.log

# Analyze response codes
awk '{print $9}' logs/access.log | sort | uniq -c | sort -nr

# Find slow requests
awk '$NF > 1000 {print}' logs/access.log

# Monitor certificate renewal
grep "renewal" logs/*.log
```

#### Log Rotation Issues

```bash
# Check log rotation configuration
cat config/logrotate.conf

# Test log rotation
./scripts/manage-logs.sh rotate

# Check disk space
df -h logs/
```

## Security Considerations

### Access Control

#### Restrict HAProxy Stats

```bash
# Edit haproxy.cfg to restrict stats access
stats http-request allow if { src 192.168.1.0/24 }
stats http-request deny
```

#### Firewall Configuration

```bash
# Restrict stats port to admin IPs only
sudo ufw allow from 192.168.1.0/24 to any port 8404
sudo ufw deny 8404
```

### Certificate Security

#### Secure Certificate Storage

```bash
# Set proper permissions
chmod 700 certs/
chmod 600 certs/live/*/privkey.pem
```

#### Certificate Monitoring

```bash
# Set up certificate expiration alerts
./scripts/certificate-expiration-monitor.sh monitor

# Configure email alerts
echo "ALERT_EMAIL=admin@yourdomain.com" >> .env
```

### Network Security

#### SSL/TLS Configuration

Review and update SSL configuration in `config/haproxy.cfg`:

```haproxy
# Use strong cipher suites
ssl-default-bind-ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
```

#### Security Headers

Ensure security headers are configured:

```haproxy
# Add security headers
http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
http-response set-header X-Content-Type-Options nosniff
http-response set-header X-Frame-Options SAMEORIGIN
```

### Monitoring and Alerting

#### Security Monitoring

```bash
# Monitor failed authentication attempts
grep "401\|403" logs/access.log

# Check for suspicious patterns
grep -E "(sql|script|eval)" logs/access.log

# Monitor certificate status
./scripts/certificate-expiration-monitor.sh health
```

#### Automated Alerts

Configure automated alerts for:
- Certificate expiration
- Service failures
- Security events
- Performance issues

```bash
# Set up email alerts
ALERT_EMAIL=security@yourdomain.com

# Configure webhook alerts (Slack, Discord, etc.)
WEBHOOK_URL=https://hooks.slack.com/services/...
```

## Support and Resources

### Documentation

- [HAProxy Documentation](http://www.haproxy.org/download/2.8/doc/configuration.txt)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

### Community Resources

- [HAProxy Community](https://www.haproxy.com/community/)
- [Let's Encrypt Community](https://community.letsencrypt.org/)
- [Docker Community](https://www.docker.com/community/)

### Professional Support

For production deployments, consider:
- Professional HAProxy support
- Managed certificate services
- Infrastructure monitoring solutions
- Security auditing services

---

This deployment guide provides comprehensive instructions for setting up and managing the HAProxy wildcard SSL proxy system. Follow the steps carefully and refer to the troubleshooting section for common issues.