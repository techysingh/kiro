# HAProxy Wildcard SSL - Production Deployment Guide

## Overview

This guide will walk you through deploying the HAProxy Wildcard SSL solution on your Ubuntu server with Docker. The deployment includes automated SSL certificate management, health monitoring, error recovery, and comprehensive logging.

## Prerequisites

### System Requirements
- **OS**: Ubuntu 20.04+ or Debian 11+ (recommended)
- **RAM**: 1GB minimum, 2GB recommended
- **Disk**: 5GB minimum, 10GB recommended
- **CPU**: 1 core minimum, 2+ cores recommended
- **Network**: Public IP with ports 80, 443, and 8404 accessible

### Required Information
- **Domain**: Your domain name (e.g., `colakdo.com`)
- **Email**: Valid email for Let's Encrypt notifications
- **GoDaddy API Credentials**: API Key and Secret from GoDaddy Developer Portal

## Step-by-Step Deployment

### Step 1: Server Preparation

#### 1.1 Update System
```bash
sudo apt update && sudo apt upgrade -y
```

#### 1.2 Install Docker and Docker Compose
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to docker group (replace 'username' with your username)
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install docker-compose-plugin -y

# Verify installation
docker --version
docker compose version
```

#### 1.3 Configure Firewall (Optional but Recommended)
```bash
# Install UFW if not already installed
sudo apt install ufw -y

# Configure firewall rules
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8404/tcp  # HAProxy stats (optional, can be restricted to specific IPs)

# Enable firewall
sudo ufw enable
```

#### 1.4 Logout and Login Again
```bash
# This is required for docker group membership to take effect
exit
# SSH back into your server
```

### Step 2: Deploy the HAProxy Stack

#### 2.1 Download/Upload the Project Files
```bash
# Create project directory
mkdir -p ~/haproxy-ssl
cd ~/haproxy-ssl

# If you have the files locally, upload them using scp:
# scp -r /path/to/demo.colakdo.com/* username@your-server-ip:~/haproxy-ssl/

# Or clone from repository if available:
# git clone <repository-url> .
```

#### 2.2 Run Deployment Readiness Check
```bash
# Make the script executable
chmod +x scripts/deployment-readiness-check.sh

# Run the readiness check
./scripts/deployment-readiness-check.sh
```

#### 2.3 Configure Environment Variables
```bash
# Copy the environment template
cp .env.example .env

# Edit the environment file
nano .env
```

**Required Configuration in .env:**
```bash
# Core Configuration
LETSENCRYPT_EMAIL=your-email@example.com
DOMAIN=colakdo.com  # Replace with your domain

# DNS Configuration for GoDaddy
DNS_PLUGIN=dns-godaddy
CERTBOT_IMAGE=haproxy-certbot-godaddy:latest

# Security
STATS_PASSWORD=your-secure-password-here

# Monitoring and Alerts
ALERT_EMAIL=your-email@example.com
WEBHOOK_URL=  # Optional: Slack/Discord webhook URL

# Optional: Advanced Configuration
CERT_WARNING_DAYS=30
CERT_CRITICAL_DAYS=7
BACKEND_DISCOVERY_ENABLED=true
```

#### 2.4 Configure GoDaddy DNS Credentials
```bash
# Set up GoDaddy DNS provider
./scripts/setup-dns-provider.sh godaddy

# Edit the credentials file
nano dns-credentials/godaddy.ini
```

**Add your GoDaddy API credentials:**
```ini
# GoDaddy DNS credentials for DNS-01 challenge
dns_godaddy_key = your-godaddy-api-key
dns_godaddy_secret = your-godaddy-api-secret
```

**To get GoDaddy API credentials:**
1. Go to https://developer.godaddy.com/keys
2. Create a new API key with "Domain" permissions
3. Copy the Key and Secret to the credentials file

#### 2.5 Set Proper File Permissions
```bash
# Set secure permissions for credentials
chmod 600 dns-credentials/godaddy.ini
chmod 600 .env

# Make scripts executable
chmod +x scripts/*.sh
chmod +x scripts/*.py
```

### Step 3: Build Custom Certbot Image (for GoDaddy)

#### 3.1 Build the GoDaddy-enabled Certbot Image
```bash
# Build the custom Certbot image with GoDaddy support
docker build -t haproxy-certbot-godaddy:latest -f docker/certbot-godaddy/Dockerfile .
```

### Step 4: Deploy the Stack

#### 4.1 Create Required Directories
```bash
# Create necessary directories
mkdir -p logs certs config errors
```

#### 4.2 Run Final Readiness Check
```bash
./scripts/deployment-readiness-check.sh
```

#### 4.3 Deploy the Stack
```bash
# Start the HAProxy stack
docker compose up -d

# Monitor the deployment
docker compose logs -f
```

#### 4.4 Verify Deployment
```bash
# Check container status
docker compose ps

# Check HAProxy stats
curl -s http://localhost:8404/health

# Check certificate generation (may take a few minutes)
docker compose logs certbot-ssl

# Run comprehensive tests
./scripts/test-error-recovery.sh
```

### Step 5: DNS Configuration

#### 5.1 Configure DNS Records
In your GoDaddy DNS management, create these A records pointing to your server's IP:

```
Type    Name    Value               TTL
A       @       your-server-ip      600
A       *       your-server-ip      600
A       www     your-server-ip      600
A       api     your-server-ip      600
A       app     your-server-ip      600
A       admin   your-server-ip      600
A       demo    your-server-ip      600
```

#### 5.2 Verify DNS Propagation
```bash
# Check if your domain resolves to your server
nslookup colakdo.com
nslookup www.colakdo.com
nslookup api.colakdo.com

# Check from external DNS
dig @8.8.8.8 colakdo.com
```

### Step 6: SSL Certificate Verification

#### 6.1 Monitor Certificate Generation
```bash
# Watch certificate generation process
docker compose logs -f certbot-ssl

# Check certificate files
ls -la certs/live/colakdo.com/

# Verify certificate details
openssl x509 -in certs/live/colakdo.com/fullchain.pem -text -noout
```

#### 6.2 Test SSL Configuration
```bash
# Test SSL certificate
curl -I https://colakdo.com
curl -I https://www.colakdo.com
curl -I https://api.colakdo.com

# Check SSL rating (optional)
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=colakdo.com
```

### Step 7: Add Backend Services (Optional)

#### 7.1 Deploy Example Backend Services
```bash
# Deploy example services for testing
docker compose -f examples/example-backend-service.yml up -d

# Check backend discovery
docker compose logs backend-discovery
```

#### 7.2 Verify Load Balancing
```bash
# Test different subdomains
curl https://www.colakdo.com
curl https://api.colakdo.com/api/
curl https://app.colakdo.com
curl https://demo.colakdo.com
```

### Step 8: Monitoring and Maintenance

#### 8.1 Access HAProxy Statistics
- **URL**: `https://colakdo.com:8404/stats`
- **Username**: `admin`
- **Password**: (value from STATS_PASSWORD in .env)

#### 8.2 Monitor Logs
```bash
# View all logs
docker compose logs -f

# View specific service logs
docker compose logs -f haproxy
docker compose logs -f certbot-ssl
docker compose logs -f error-recovery

# View log files
tail -f logs/haproxy.log
tail -f logs/error-recovery.log
```

#### 8.3 Health Checks
```bash
# Run comprehensive health check
./scripts/test-error-recovery.sh

# Check individual services
./scripts/service-health-checker.sh haproxy
./scripts/service-health-checker.sh certbot

# Check certificate status
./scripts/certificate-fallback-manager.sh status
```

## Troubleshooting

### Common Issues

#### 1. Certificate Generation Fails
```bash
# Check DNS credentials
cat dns-credentials/godaddy.ini

# Test DNS API access
docker compose exec certbot-ssl certbot plugins

# Check DNS propagation
nslookup _acme-challenge.colakdo.com

# View detailed logs
docker compose logs certbot-ssl
```

#### 2. HAProxy Won't Start
```bash
# Check configuration syntax
docker compose exec haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Check port conflicts
netstat -tuln | grep -E ':(80|443|8404)'

# View HAProxy logs
docker compose logs haproxy
```

#### 3. Backend Services Not Discovered
```bash
# Check proxy network
docker network ls | grep proxy-network

# Check backend discovery logs
docker compose logs backend-discovery

# Manually trigger discovery
docker compose exec backend-discovery /scripts/backend-discovery.sh
```

#### 4. Error Recovery Issues
```bash
# Check error recovery status
./scripts/error-recovery-manager.sh --status

# Force recovery
./scripts/error-recovery-manager.sh --force

# View recovery logs
tail -f logs/error-recovery.log
```

### Log Locations

- **HAProxy Logs**: `logs/haproxy.log`, `logs/access.log`, `logs/error.log`
- **Certificate Logs**: `logs/certbot.log`
- **Error Recovery**: `logs/error-recovery.log`
- **Monitoring**: `logs/monitor.log`
- **Backend Discovery**: `logs/backend-discovery.log`

### Useful Commands

```bash
# Restart specific service
docker compose restart haproxy

# Update configuration and reload
docker compose exec haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
docker compose restart haproxy

# Force certificate renewal
docker compose exec certbot-ssl certbot renew --force-renewal

# View container resource usage
docker stats

# Clean up old containers and images
docker system prune -f
```

## Security Considerations

### 1. Firewall Configuration
- Only expose necessary ports (80, 443, 8404)
- Consider restricting 8404 (stats) to specific IP addresses
- Use fail2ban for additional protection

### 2. Access Control
- Change default STATS_PASSWORD
- Use strong passwords for all credentials
- Regularly rotate API keys and passwords

### 3. Monitoring
- Set up proper alerting (email, Slack, etc.)
- Monitor certificate expiration
- Review logs regularly for suspicious activity

### 4. Updates
- Keep Docker images updated
- Monitor security advisories for HAProxy and Certbot
- Test updates in staging environment first

## Performance Optimization

### 1. Resource Limits
Adjust container resource limits in docker-compose.yml:
```yaml
deploy:
  resources:
    limits:
      memory: 512M
      cpus: '1.0'
```

### 2. HAProxy Tuning
Modify HAProxy configuration for your traffic patterns:
- Adjust connection limits
- Tune timeout values
- Configure appropriate load balancing algorithms

### 3. Log Management
- Configure log rotation
- Set appropriate retention periods
- Consider centralized logging for multiple servers

## Backup and Recovery

### 1. Important Files to Backup
- `.env` file
- `dns-credentials/` directory
- `certs/` directory (certificates)
- `config/` directory (configurations)
- `logs/` directory (for compliance/debugging)

### 2. Backup Script Example
```bash
#!/bin/bash
BACKUP_DIR="/backup/haproxy-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r .env dns-credentials/ certs/ config/ "$BACKUP_DIR/"
tar -czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"
rm -rf "$BACKUP_DIR"
```

### 3. Recovery Process
1. Restore files from backup
2. Verify file permissions
3. Run deployment readiness check
4. Start services with `docker compose up -d`

## Support and Maintenance

### Regular Maintenance Tasks
- **Weekly**: Review logs and alerts
- **Monthly**: Check certificate expiration dates
- **Quarterly**: Update Docker images and review security settings
- **Annually**: Rotate API keys and passwords

### Getting Help
- Check logs first: `docker compose logs`
- Run health checks: `./scripts/test-error-recovery.sh`
- Review this guide and troubleshooting section
- Check HAProxy and Certbot documentation

---

**Congratulations!** Your HAProxy Wildcard SSL solution is now deployed and ready for production use. The system includes automatic certificate management, health monitoring, error recovery, and comprehensive logging to ensure high availability and reliability.