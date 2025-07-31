# HAProxy Backend Health Checks and Management

This document explains the enhanced health check and backend management features implemented for the HAProxy wildcard SSL setup.

## Overview

The system now includes comprehensive health checks, backend service discovery, load balancing algorithms, and graceful failover mechanisms to ensure high availability and reliability.

## Features

### 1. Enhanced Health Checks

Each backend is configured with sophisticated health checks that include:

- **Multiple validation points**: HTTP status codes and response content validation
- **Configurable intervals**: Different check frequencies for normal, fast, and down states
- **Rise/fall thresholds**: Configurable number of successful/failed checks before state change
- **Custom health check paths**: Service-specific health endpoints

#### Health Check Configuration by Backend:

- **Root/WWW backends**: `GET /health` expecting "healthy" response
- **API backend**: `GET /api/health` expecting JSON with `"status": "ok"`
- **App backend**: `GET /app/health` expecting "application_ready" response
- **Admin backend**: `GET /admin/health` expecting "admin_healthy" response
- **Demo backend**: `GET /demo/health` with standard health check

### 2. Load Balancing Algorithms

Different backends use optimized load balancing algorithms:

- **Root backend**: `roundrobin` - Equal distribution
- **WWW backend**: `leastconn` - Route to server with fewest connections
- **API backend**: `source` - Session persistence based on client IP
- **App backend**: `uri whole` - URI-based routing for better caching
- **Admin backend**: `first` - Prefer first available server for consistency
- **Demo backend**: `roundrobin` - Standard round-robin distribution

### 3. Graceful Failover

The system implements several failover mechanisms:

- **Backup servers**: Each backend can have backup servers that activate when primary servers fail
- **Maintenance mode**: Automatic fallback to maintenance server when all backends are unavailable
- **Retry logic**: Configurable retry attempts with exponential backoff
- **Health-based routing**: Automatic removal of unhealthy servers from rotation

### 4. Backend Service Discovery

Automatic discovery of services within the `proxy-network`:

- **Container detection**: Automatically discovers containers joined to proxy-network
- **Service mapping**: Maps container names to appropriate backends
- **Dynamic configuration**: Updates HAProxy configuration without manual intervention
- **Port detection**: Intelligent port detection based on service type

## Configuration Files

### HAProxy Configuration

The main configuration includes enhanced backend definitions with:

```haproxy
backend api_backend
    mode http
    balance source
    option redispatch
    retries 3
    
    # API-specific health checks
    option httpchk GET /api/health HTTP/1.1\r\nHost:\ api.colakdo.com\r\nUser-Agent:\ HAProxy-Health-Check
    http-check expect status 200
    http-check expect rstring "\"status\":\s*\"ok\""
    
    # Health check configuration
    default-server check inter 5s fastinter 1s downinter 3s rise 3 fall 2
    default-server maxconn 200 maxqueue 100
    
    # Backend servers (discovered automatically)
    # server api1 api-service:8080 check weight 100
```

### Environment Variables

Configure the system using these environment variables:

```bash
# Backend Discovery
BACKEND_DISCOVERY_ENABLED=true
BACKEND_DISCOVERY_INTERVAL=60

# Health Check Monitoring
HAPROXY_STATS_URL=http://localhost:8404/stats
ALERT_EMAIL=admin@colakdo.com
WEBHOOK_URL=https://hooks.slack.com/your-webhook

# Certificate Monitoring
CERT_WARNING_DAYS=30
CERT_CRITICAL_DAYS=7
```

## Scripts and Tools

### 1. Backend Discovery Script (`backend-discovery.sh`)

Automatically discovers and configures backend services:

```bash
# Run manual discovery
./scripts/backend-discovery.sh

# Discover services only (no config update)
./scripts/backend-discovery.sh --discover-only

# Validate configuration only
./scripts/backend-discovery.sh --validate-only
```

### 2. HAProxy Monitor Script (`haproxy-monitor.sh`)

Monitors backend health and provides alerts:

```bash
# Run single monitoring check
./scripts/haproxy-monitor.sh --once

# Run continuous monitoring
./scripts/haproxy-monitor.sh --continuous

# Show backend status only
./scripts/haproxy-monitor.sh --status-only
```

### 3. Maintenance Server (`maintenance-server.py`)

Provides fallback responses when backends are unavailable:

- Serves health check responses for all backend types
- Provides user-friendly maintenance pages
- Logs all requests for monitoring

## Adding New Backend Services

### 1. Container Naming Convention

Name your containers to match the intended backend:

- `*root*` or `*main*` → routes to `root_backend`
- `*www*` → routes to `www_backend`
- `*api*` → routes to `api_backend`
- `*app*` → routes to `app_backend`
- `*admin*` → routes to `admin_backend`
- `*demo*` → routes to `demo_backend`

### 2. Join the Proxy Network

Add your service to the proxy network:

```yaml
services:
  my-api-service:
    image: my-api:latest
    container_name: api-service-1
    networks:
      - proxy-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  proxy-network:
    external: true
```

### 3. Implement Health Endpoints

Ensure your service implements the expected health check endpoints:

```javascript
// Example Node.js health endpoint
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    service: 'my-api-service'
  });
});
```

### 4. Configure Service Ports

Use standard ports or configure detection:

- **Web services**: Port 80
- **API services**: Port 8080
- **Applications**: Port 3000
- **Admin services**: Port 8443 (SSL)

## Monitoring and Alerts

### Health Check Monitoring

The system continuously monitors:

- Backend server availability
- Response times and error rates
- Certificate expiration dates
- HAProxy process health

### Alert Conditions

Alerts are triggered for:

- **High severity**: Multiple backends down, certificate expiring soon
- **Medium severity**: Backup servers active, single backend issues
- **Critical severity**: No healthy backends, certificate expired

### Accessing Statistics

HAProxy statistics are available at:

- **Web interface**: `https://colakdo.com:8404/stats`
- **Health endpoint**: `https://colakdo.com:8404/health`
- **CSV data**: `https://colakdo.com:8404/stats;csv`

## Troubleshooting

### Common Issues

1. **Backend not discovered**:
   - Check container is in proxy-network
   - Verify container naming convention
   - Check backend-discovery logs

2. **Health checks failing**:
   - Verify health endpoint implementation
   - Check expected response format
   - Review HAProxy logs

3. **Load balancing not working**:
   - Confirm multiple backend servers
   - Check server weights and status
   - Verify load balancing algorithm

### Log Files

Monitor these log files for issues:

- `/var/log/haproxy/haproxy.log` - General HAProxy logs
- `/var/log/haproxy/access.log` - Access logs
- `/var/log/haproxy/error.log` - Error logs
- `/var/log/haproxy/monitor.log` - Health monitoring logs
- `/var/log/haproxy/backend-discovery.log` - Service discovery logs

### Manual Backend Configuration

If automatic discovery doesn't work, manually configure backends:

1. Edit `demo.colakdo.com/config/haproxy.cfg`
2. Uncomment and modify server lines in the appropriate backend section
3. Reload configuration: `docker exec haproxy-proxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg`

## Performance Tuning

### Connection Limits

Adjust per-backend connection limits:

```haproxy
default-server maxconn 200 maxqueue 100
```

### Health Check Intervals

Tune health check frequency:

```haproxy
# Fast checks: every 5s, fast recovery in 1s, down detection in 3s
default-server check inter 5s fastinter 1s downinter 3s rise 3 fall 2
```

### Load Balancing Weights

Adjust server weights for capacity differences:

```haproxy
server api1 api-service-1:8080 check weight 100
server api2 api-service-2:8080 check weight 150  # 50% more capacity
```

## Security Considerations

- Health check endpoints should not expose sensitive information
- Use HTTPS for admin backend health checks
- Implement rate limiting on health check endpoints
- Monitor for unusual health check patterns
- Secure HAProxy statistics interface with authentication