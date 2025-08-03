#!/bin/bash
"""
Local Docker Testing Script for HAProxy Setup
Tests the HAProxy stack locally without real DNS/certificates
"""

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    case "$level" in
        "INFO") echo -e "${BLUE}[INFO]${NC} $*" ;;
        "SUCCESS") echo -e "${GREEN}[✓]${NC} $*" ;;
        "WARNING") echo -e "${YELLOW}[!]${NC} $*" ;;
        "ERROR") echo -e "${RED}[✗]${NC} $*" ;;
    esac
}

# Setup local testing environment
setup_local_env() {
    log "INFO" "Setting up local testing environment..."
    
    # Use local testing environment
    cp .env.local .env
    
    # Create a dummy GoDaddy credentials file (won't be used)
    mkdir -p dns-credentials
    cat > dns-credentials/godaddy.ini << 'EOF'
# Dummy credentials for local testing
dns_godaddy_key = dummy_key_for_local_testing
dns_godaddy_secret = dummy_secret_for_local_testing
EOF
    chmod 600 dns-credentials/godaddy.ini
    
    log "SUCCESS" "Local environment configured"
}

# Create local HAProxy config without SSL
create_local_haproxy_config() {
    log "INFO" "Creating local HAProxy configuration..."
    
    # Backup original config
    if [[ -f "config/haproxy.cfg" ]]; then
        cp config/haproxy.cfg config/haproxy.cfg.backup
    fi
    
    # Create simplified config for local testing
    cat > config/haproxy.cfg << 'EOF'
# HAProxy Configuration for Local Testing
# Simplified version without SSL for local Docker testing

global
    daemon
    user haproxy
    group haproxy
    log 127.0.0.1:514 local0 info
    log-tag haproxy

defaults
    mode http
    log global
    option httplog
    option dontlognull
    option forwardfor except 127.0.0.0/8
    option redispatch
    
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    timeout http-request 10s
    timeout http-keep-alive 2s
    timeout check 10s
    
    errorfile 400 /usr/local/etc/haproxy/errors/400.http
    errorfile 403 /usr/local/etc/haproxy/errors/403.http
    errorfile 408 /usr/local/etc/haproxy/errors/408.http
    errorfile 500 /usr/local/etc/haproxy/errors/500.http
    errorfile 502 /usr/local/etc/haproxy/errors/502.http
    errorfile 503 /usr/local/etc/haproxy/errors/503.http
    errorfile 504 /usr/local/etc/haproxy/errors/504.http

# Frontend - HTTP only for local testing
frontend http_frontend
    bind *:80
    mode http
    
    # Add some basic security headers
    http-response set-header X-Content-Type-Options "nosniff"
    http-response set-header X-Frame-Options "SAMEORIGIN"
    http-response set-header X-XSS-Protection "1; mode=block"
    
    # Capture headers for logging
    capture request header Host len 64
    capture request header User-Agent len 128
    
    # Simple routing based on Host header
    acl is_root_domain hdr(host) -i colakdo.local
    acl is_www_domain hdr(host) -i www.colakdo.local
    acl is_api_domain hdr(host) -i api.colakdo.local
    acl is_app_domain hdr(host) -i app.colakdo.local
    acl is_admin_domain hdr(host) -i admin.colakdo.local
    acl is_demo_domain hdr(host) -i demo.colakdo.local
    
    # Route to backends
    use_backend root_backend if is_root_domain
    use_backend www_backend if is_www_domain
    use_backend api_backend if is_api_domain
    use_backend app_backend if is_app_domain
    use_backend admin_backend if is_admin_domain
    use_backend demo_backend if is_demo_domain
    
    # Default backend
    default_backend maintenance_backend

# Stats Frontend
frontend stats_frontend
    bind *:8404
    mode http
    
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE
    stats show-legends
    stats show-node
    stats show-desc "HAProxy Load Balancer - Local Testing"
    
    # Health check endpoint
    monitor-uri /health
    
    # Basic security headers
    http-response set-header X-Content-Type-Options "nosniff"
    http-response set-header X-Frame-Options "DENY"

# Backend Definitions
backend root_backend
    mode http
    balance roundrobin
    option redispatch
    retries 3
    
    # Health check
    option httpchk GET /health
    http-check expect status 200
    
    default-server check inter 10s rise 2 fall 3
    server maintenance 127.0.0.1:8080 check

backend www_backend
    mode http
    balance leastconn
    option redispatch
    retries 3
    
    option httpchk GET /health
    http-check expect status 200
    
    default-server check inter 10s rise 2 fall 3
    server maintenance 127.0.0.1:8080 check

backend api_backend
    mode http
    balance source
    option redispatch
    retries 3
    
    option httpchk GET /api/health
    http-check expect status 200
    
    default-server check inter 5s rise 3 fall 2
    server maintenance 127.0.0.1:8080 check

backend app_backend
    mode http
    balance uri whole
    option redispatch
    retries 3
    
    option httpchk GET /app/health
    http-check expect status 200
    
    default-server check inter 15s rise 2 fall 3
    server maintenance 127.0.0.1:8080 check

backend admin_backend
    mode http
    balance first
    option redispatch
    retries 2
    
    option httpchk GET /admin/health
    http-check expect status 200
    
    default-server check inter 20s rise 3 fall 2
    server maintenance 127.0.0.1:8080 check

backend demo_backend
    mode http
    balance roundrobin
    option redispatch
    retries 3
    
    option httpchk GET /demo/health
    http-check expect status 200
    
    default-server check inter 10s rise 2 fall 3
    server maintenance 127.0.0.1:8080 check

backend maintenance_backend
    mode http
    server maintenance 127.0.0.1:8080 check
EOF
    
    log "SUCCESS" "Local HAProxy configuration created"
}

# Create local Docker Compose override
create_local_compose_override() {
    log "INFO" "Creating Docker Compose override for local testing..."
    
    cat > docker-compose.override.yml << 'EOF'
# Docker Compose override for local testing
version: '3.8'

services:
  haproxy:
    ports:
      - "8080:80"      # Map to 8080 to avoid conflicts
      - "8404:8404"    # Stats port
    environment:
      - DOMAIN=colakdo.local
    volumes:
      - ./config/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro

  # Disable certbot for local testing
  certbot:
    command: ["sh", "-c", "echo 'Certbot disabled for local testing' && sleep infinity"]
    healthcheck:
      test: ["CMD", "echo", "healthy"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Simplified maintenance server
  maintenance-server:
    environment:
      - MAINTENANCE_PORT=8080
    command: ["python3", "/scripts/maintenance-server.py"]

  # Disable error recovery for local testing
  error-recovery:
    command: ["sh", "-c", "echo 'Error recovery disabled for local testing' && sleep infinity"]
EOF
    
    log "SUCCESS" "Docker Compose override created"
}

# Build and start the stack
start_local_stack() {
    log "INFO" "Starting local HAProxy stack..."
    
    # Create required directories
    mkdir -p logs certs config errors
    
    # Create proxy network if it doesn't exist
    if ! docker network ls | grep -q proxy-network; then
        docker network create proxy-network
        log "INFO" "Created proxy-network"
    fi
    
    # Start the stack
    if docker compose up -d; then
        log "SUCCESS" "Local HAProxy stack started"
    else
        log "ERROR" "Failed to start local stack"
        return 1
    fi
    
    # Wait for services to start
    sleep 10
}

# Test the local deployment
test_local_deployment() {
    log "INFO" "Testing local HAProxy deployment..."
    
    # Test container status
    log "INFO" "Checking container status..."
    docker compose ps
    
    # Test HAProxy health endpoint
    log "INFO" "Testing HAProxy health endpoint..."
    if curl -f -s http://localhost:8404/health >/dev/null 2>&1; then
        log "SUCCESS" "HAProxy health endpoint responding"
    else
        log "ERROR" "HAProxy health endpoint not responding"
    fi
    
    # Test HAProxy stats
    log "INFO" "Testing HAProxy stats endpoint..."
    if curl -f -s http://localhost:8404/stats >/dev/null 2>&1; then
        log "SUCCESS" "HAProxy stats endpoint accessible"
    else
        log "WARNING" "HAProxy stats endpoint not accessible"
    fi
    
    # Test main HTTP endpoint
    log "INFO" "Testing main HTTP endpoint..."
    if curl -f -s http://localhost:8080/ >/dev/null 2>&1; then
        log "SUCCESS" "Main HTTP endpoint responding"
    else
        log "ERROR" "Main HTTP endpoint not responding"
    fi
    
    # Test different host headers
    local hosts=("colakdo.local" "www.colakdo.local" "api.colakdo.local" "app.colakdo.local")
    
    for host in "${hosts[@]}"; do
        log "INFO" "Testing host: $host"
        if curl -f -s -H "Host: $host" http://localhost:8080/ >/dev/null 2>&1; then
            log "SUCCESS" "Host $host responding"
        else
            log "WARNING" "Host $host not responding properly"
        fi
    done
}

# Show test results and access information
show_test_results() {
    echo
    echo "=================================="
    echo "LOCAL DOCKER TEST RESULTS"
    echo "=================================="
    echo
    echo "🐳 Docker Containers:"
    docker compose ps
    echo
    echo "🌐 Test URLs (add to /etc/hosts for full testing):"
    echo "   • Main site: http://localhost:8080/"
    echo "   • HAProxy stats: http://localhost:8404/stats"
    echo "   • Health check: http://localhost:8404/health"
    echo
    echo "🔧 Host Header Testing:"
    echo "   curl -H 'Host: colakdo.local' http://localhost:8080/"
    echo "   curl -H 'Host: api.colakdo.local' http://localhost:8080/"
    echo "   curl -H 'Host: www.colakdo.local' http://localhost:8080/"
    echo
    echo "📊 Useful Commands:"
    echo "   • View logs: docker compose logs -f"
    echo "   • Stop stack: docker compose down"
    echo "   • Restart: docker compose restart haproxy"
    echo
    echo "📝 Add to /etc/hosts for domain testing:"
    echo "   127.0.0.1 colakdo.local"
    echo "   127.0.0.1 www.colakdo.local"
    echo "   127.0.0.1 api.colakdo.local"
    echo "   127.0.0.1 app.colakdo.local"
    echo "   127.0.0.1 admin.colakdo.local"
    echo "   127.0.0.1 demo.colakdo.local"
    echo
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up local test environment..."
    
    # Stop containers
    docker compose down 2>/dev/null || true
    
    # Restore original config if it exists
    if [[ -f "config/haproxy.cfg.backup" ]]; then
        mv config/haproxy.cfg.backup config/haproxy.cfg
    fi
    
    # Remove override file
    rm -f docker-compose.override.yml
    
    log "SUCCESS" "Cleanup completed"
}

# Main execution
main() {
    echo "HAProxy Local Docker Testing"
    echo "============================"
    echo
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    setup_local_env
    create_local_haproxy_config
    create_local_compose_override
    start_local_stack
    test_local_deployment
    show_test_results
    
    log "SUCCESS" "Local Docker testing completed!"
    echo
    echo "Press Ctrl+C to stop the test environment and cleanup."
    echo "Or run 'docker compose down' to stop manually."
}

# Handle script arguments
case "${1:-}" in
    --cleanup)
        cleanup
        exit 0
        ;;
    --help|-h)
        echo "HAProxy Local Docker Testing Script"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --cleanup     Clean up test environment"
        echo "  --help, -h    Show this help message"
        echo
        echo "This script will:"
        echo "1. Set up local testing environment"
        echo "2. Create simplified HAProxy config (HTTP only)"
        echo "3. Start Docker stack with overrides"
        echo "4. Test all endpoints and functionality"
        echo "5. Show access URLs and testing commands"
        echo
        ;;
    *)
        main
        ;;
esac