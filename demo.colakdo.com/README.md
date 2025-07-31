# HAProxy Wildcard SSL Proxy for *.colakdo.com

This project provides a complete HAProxy reverse proxy solution with automated Let's Encrypt wildcard SSL certificate management for `*.colakdo.com`.

## Features

- 🔒 Automated wildcard SSL certificates via Let's Encrypt
- 🚀 HAProxy reverse proxy with SSL termination
- 🔄 Automatic certificate renewal
- 📊 Externalized logging with rotation
- 🌐 Shared Docker network for backend services
- 📈 Built-in monitoring and health checks
- 🛡️ **Security hardening with strong SSL/TLS configuration**
- 🔍 **Certificate expiration monitoring and alerting**
- 📊 **HAProxy statistics and performance monitoring**
- 🚨 **Automated security alerts via email and webhooks**

## Quick Start

1. **Clone and setup**:
   ```bash
   cd demo.colakdo.com
   cp .env.example .env
   cp dns-credentials/cloudflare.ini.example dns-credentials/cloudflare.ini
   ```

2. **Configure environment**:
   - Edit `.env` with your email and domain settings
   - Edit `dns-credentials/cloudflare.ini` with your Cloudflare API credentials
   - Set proper permissions: `chmod 600 dns-credentials/cloudflare.ini`

3. **Deploy the stack**:
   ```bash
   ./scripts/deploy.sh
   ```

For detailed deployment instructions, see [DEPLOYMENT.md](DEPLOYMENT.md).

## Directory Structure

```
demo.colakdo.com/
├── docker-compose.yml          # Main orchestration file
├── .env.example               # Environment variables template
├── config/                    # HAProxy configuration
├── certs/                     # SSL certificates (auto-generated)
├── logs/                      # HAProxy logs
├── dns-credentials/           # DNS provider credentials
├── scripts/                   # Certificate management scripts
└── errors/                    # Custom error pages
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

- `LETSENCRYPT_EMAIL`: Your email for Let's Encrypt registration
- `DOMAIN`: Your domain (colakdo.com)
- `DNS_PLUGIN`: DNS provider plugin (dns-cloudflare)

### DNS Credentials

Configure your DNS provider credentials in `dns-credentials/`:

- For Cloudflare: Copy `cloudflare.ini.example` to `cloudflare.ini`
- Add your API token or global API key
- Set permissions: `chmod 600 dns-credentials/cloudflare.ini`

## Adding Backend Services

To route traffic to your services:

1. **Use the simple template**:
   ```bash
   cp examples/simple-backend-template.yml my-service.yml
   # Edit my-service.yml with your service details
   docker-compose -f my-service.yml up -d
   ```

2. **Or connect manually to the network**:
   ```yaml
   services:
     your-app:
       # ... your service config
       networks:
         - proxy-network
       environment:
         - SERVICE_NAME=your-app
         - SERVICE_TYPE=app
   
   networks:
     proxy-network:
       external: true
   ```

For detailed backend integration instructions, see [examples/README.md](examples/README.md).

## Logging

The system implements externalized logging with automatic rotation:

### Log Files

- `logs/haproxy.log` - General HAProxy logs
- `logs/access.log` - HTTP access logs
- `logs/error.log` - Error-level logs

### Log Management

Use the log management script for common operations:

```bash
# Show log statistics
./scripts/manage-logs.sh stats

# Tail logs (access, error, general, or all)
./scripts/manage-logs.sh tail access

# Search logs
./scripts/manage-logs.sh search "ERROR" error

# Manually rotate logs
./scripts/manage-logs.sh rotate

# Clean old logs (older than 30 days)
./scripts/manage-logs.sh clean 30
```

### Log Rotation

- **Frequency**: Daily rotation
- **Retention**: 30 days (configurable)
- **Compression**: Automatic compression of rotated logs
- **Configuration**: `config/logrotate.conf`

## Certificate Renewal System

The system includes an advanced automated certificate renewal system with comprehensive monitoring and retry logic.

### Renewal Features

- ✅ **Automated Scheduling**: Cron-based renewal every 12 hours
- ✅ **Retry Logic**: Exponential backoff with up to 5 retry attempts
- ✅ **HAProxy Integration**: Automatic configuration reload after renewal
- ✅ **Comprehensive Logging**: Detailed logs for all renewal attempts
- ✅ **Health Monitoring**: Built-in certificate and system health checks

### Renewal Configuration

The renewal system can be configured via environment variables:

```bash
# Custom renewal schedule (default: every 12 hours)
RENEWAL_CRON_SCHEDULE="0 */6 * * *"  # Every 6 hours

# Renewal thresholds
RENEWAL_THRESHOLD_DAYS=30  # Renew if expires within 30 days
FORCE_RENEWAL_DAYS=7       # Force renewal if expires within 7 days
```

### Manual Renewal Operations

```bash
# Check certificate status
./scripts/renewal-monitor.sh status

# Force certificate renewal
./scripts/certificate-renewal.sh --force

# Check renewal system health
./scripts/renewal-monitor.sh health

# View recent renewal logs
./scripts/renewal-monitor.sh logs --lines 50

# Generate comprehensive report
./scripts/renewal-monitor.sh report --output /tmp/renewal-report.txt

# Test renewal system
./scripts/renewal-monitor.sh test
```

### Renewal Logs

The system maintains detailed logs for monitoring and troubleshooting:

- `logs/renewal.log` - Main renewal activity log
- `logs/renewal-errors.log` - Error-specific log entries
- `logs/renewal-history.log` - Historical renewal attempts
- `logs/cron.log` - Cron job execution log

### Monitoring and Alerts

Monitor certificate renewal status:

```bash
# Quick status check
./scripts/renewal-monitor.sh status

# Comprehensive health check
./scripts/renewal-monitor.sh health

# Analyze renewal patterns
./scripts/renewal-monitor.sh analyze
```

### Troubleshooting Renewal Issues

1. **Check system health**:
   ```bash
   ./scripts/renewal-monitor.sh health
   ```

2. **Review error logs**:
   ```bash
   ./scripts/renewal-monitor.sh logs
   ```

3. **Test renewal manually**:
   ```bash
   ./scripts/certificate-renewal.sh --verbose
   ```

4. **Verify DNS credentials**:
   ```bash
   ls -la dns-credentials/
   ```

5. **Check cron configuration**:
   ```bash
   docker exec certbot-ssl crontab -l
   ```

## Monitoring

- **HAProxy Stats**: http://localhost:8404/stats
- **Certificate Status**: `./scripts/renewal-monitor.sh status`
- **Logs**: Available in `./logs/` directory with rotation
- **Health Checks**: Built-in Docker health checks

## Security Hardening & Monitoring

This implementation includes comprehensive security hardening and monitoring features:

### 🛡️ SSL/TLS Security

**Strong Cipher Suites**:
- ECDHE-ECDSA-AES256-GCM-SHA384 (primary)
- ECDHE-RSA-AES256-GCM-SHA384
- ECDHE-ECDSA-CHACHA20-POLY1305
- TLS 1.3 cipher suites supported

**Security Options**:
- Minimum TLS version: 1.2
- Disabled: SSLv3, TLS 1.0, TLS 1.1
- No TLS session tickets
- Server cipher preference enforced
- 2048-bit DH parameters

### 🔒 Security Headers

**HTTP Strict Transport Security (HSTS)**:
```
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
```

**Content Security Policy (CSP)**:
```
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; ...
```

**Additional Headers**:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: SAMEORIGIN`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy` (restricts dangerous browser features)
- Cross-Origin security headers

### 🚫 HTTP Traffic Handling

- **Default**: All HTTP traffic returns 403 Forbidden
- **Security headers** applied to HTTP responses
- **HSTS header** forces future HTTPS connections
- **Comprehensive logging** of HTTP attempts

### 📊 Monitoring & Statistics

**HAProxy Statistics Interface**:
- URL: `http://localhost:8404/stats`
- Features: Real-time metrics, server status, performance data
- Security: Rate limiting (20 req/10s per IP)
- Health endpoint: `http://localhost:8404/health`

**Certificate Monitoring**:
```bash
# Check certificate status
./scripts/certificate-expiration-monitor.sh info

# Get JSON status
./scripts/certificate-expiration-monitor.sh json

# Health check
./scripts/certificate-expiration-monitor.sh health
```

**HAProxy Monitoring**:
```bash
# Check HAProxy health
./scripts/haproxy-monitor.sh health

# Get performance metrics
./scripts/haproxy-monitor.sh metrics

# Generate monitoring report
./scripts/haproxy-monitor.sh report json
```

### 🚨 Alerting System

**Certificate Expiration Alerts**:
- Warning: 30 days before expiration
- Critical: 7 days before expiration
- Supports email and webhook notifications

**HAProxy Health Alerts**:
- Service availability monitoring
- Performance threshold alerts
- Error rate monitoring

**Configuration**:
```bash
# Set alert email
ALERT_EMAIL=admin@example.com

# Set webhook URL (Slack, Discord, etc.)
WEBHOOK_URL=https://hooks.slack.com/services/...
```

### 🧪 Security Testing

Run comprehensive security tests:
```bash
./scripts/test-security-hardening.sh
```

**Tests Include**:
- HTTP rejection verification
- Security headers validation
- SSL/TLS configuration testing
- Certificate monitoring functionality
- HAProxy statistics security
- Rate limiting verification

### 📋 Security Compliance

This configuration addresses:
- **PCI DSS**: Strong cryptography requirements
- **GDPR**: Privacy headers and data protection
- **OWASP Top 10**: Web application security risks
- **NIST Cybersecurity Framework**: Security controls

### 🔧 Security Configuration

**Environment Variables**:
```bash
# Statistics password (change this!)
STATS_PASSWORD=secure_password_change_me

# Certificate monitoring thresholds
CERT_WARNING_DAYS=30
CERT_CRITICAL_DAYS=7

# Alert configuration
ALERT_EMAIL=admin@example.com
WEBHOOK_URL=https://your-webhook-url
```

**Advanced Configuration**:
See `config/security-hardening.md` for detailed security documentation.

## Troubleshooting

- **Certificate generation fails**: Check DNS credentials and domain ownership
- **HAProxy won't start**: Verify configuration syntax
- **Backend unreachable**: Ensure services are on proxy-network

## Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Comprehensive deployment guide
- **[examples/README.md](examples/README.md)** - Backend service integration guide
- **[config/README.md](config/README.md)** - Configuration documentation
- **[scripts/README.md](scripts/README.md)** - Script usage documentation

## Deployment Scripts

- **`./scripts/deploy.sh`** - Automated deployment script
- **`./scripts/startup.sh`** - Service orchestration and management
- **`./scripts/manage-logs.sh`** - Log management utilities

## Next Steps

After deployment:
1. Configure your DNS to point *.yourdomain.com to this server
2. Add backend services using the provided templates
3. Monitor certificate renewal and service health
4. Review security settings and customize as needed