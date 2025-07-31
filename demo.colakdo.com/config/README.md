# HAProxy Configuration

This directory contains the HAProxy configuration for *.colakdo.com with SSL termination.

## Configuration Overview

The `haproxy.cfg` file implements:

### SSL Termination
- Wildcard SSL certificate support for *.colakdo.com
- Strong cipher suites and TLS 1.2+ enforcement
- HTTP/2 and HTTP/1.1 support via ALPN

### Security Features
- HTTP traffic rejection (403 Forbidden) with security headers
- HSTS headers for HTTPS enforcement
- Security headers (X-Content-Type-Options, X-Frame-Options, etc.)
- Content Security Policy headers

### SNI-Based Routing
The configuration supports routing to different backends based on subdomain:

- `colakdo.com` → `root_backend`
- `www.colakdo.com` → `www_backend`
- `api.colakdo.com` → `api_backend`
- `app.colakdo.com` → `app_backend`
- `admin.colakdo.com` → `admin_backend`
- `demo.colakdo.com` → `demo_backend`

### Backend Configuration
Each backend is configured with:
- Round-robin load balancing
- Health checks on `/health` endpoint
- Graceful handling of unavailable servers
- Custom error pages

### Monitoring
- HAProxy statistics available at `:8404/stats`
- Comprehensive logging with request capture
- Health check monitoring

## Adding New Backends

To add a new subdomain:

1. Add an ACL for the subdomain:
   ```
   acl is_newapp_domain hdr(host) -i newapp.colakdo.com
   ```

2. Add routing rule:
   ```
   use_backend newapp_backend if is_newapp_domain
   ```

3. Define the backend:
   ```
   backend newapp_backend
       mode http
       balance roundrobin
       option httpchk GET /health
       server newapp1 newapp-service:80 check
   ```

## Certificate Requirements

The configuration expects the SSL certificate to be available at:
`/etc/ssl/certs/live/colakdo.com/combined.pem`

This file should contain the full certificate chain and private key combined.
The `combine-certs.sh` script handles this automatically.

## Validation

Use the validation script to check configuration syntax:
```bash
./scripts/validate-haproxy-config.sh config/haproxy.cfg
```

For full validation with HAProxy:
```bash
haproxy -c -f config/haproxy.cfg
```