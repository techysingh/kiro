#!/bin/bash
"""
Minimal HAProxy Docker Test
Tests just HAProxy with a simple backend
"""

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    case "$1" in
        "INFO") echo -e "${BLUE}[INFO]${NC} $2" ;;
        "SUCCESS") echo -e "${GREEN}[✓]${NC} $2" ;;
        "ERROR") echo -e "${RED}[✗]${NC} $2" ;;
    esac
}

# Create minimal HAProxy config
create_minimal_config() {
    log "INFO" "Creating minimal HAProxy configuration..."
    
    mkdir -p config
    cat > config/haproxy-minimal.cfg << 'EOF'
global
    daemon
    user haproxy
    group haproxy

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend http_frontend
    bind *:80
    default_backend test_backend

frontend stats_frontend
    bind *:8404
    stats enable
    stats uri /stats
    monitor-uri /health

backend test_backend
    mode http
    balance roundrobin
    server test1 httpbin.org:80 check
EOF
    
    log "SUCCESS" "Minimal configuration created"
}

# Start minimal test
start_minimal_test() {
    log "INFO" "Starting minimal HAProxy test..."
    
    # Create network
    docker network create test-network 2>/dev/null || true
    
    # Start HAProxy container
    docker run -d \
        --name haproxy-minimal-test \
        --network test-network \
        -p 8080:80 \
        -p 8404:8404 \
        -v "$(pwd)/config/haproxy-minimal.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
        haproxy:2.8-alpine
    
    log "SUCCESS" "HAProxy container started"
    
    # Wait for startup
    sleep 10
}

# Test the setup
test_minimal() {
    log "INFO" "Testing minimal HAProxy setup..."
    
    # Test health endpoint
    if curl -f -s http://localhost:8404/health >/dev/null 2>&1; then
        log "SUCCESS" "Health endpoint responding"
    else
        log "ERROR" "Health endpoint not responding"
        return 1
    fi
    
    # Test stats endpoint
    if curl -f -s http://localhost:8404/stats >/dev/null 2>&1; then
        log "SUCCESS" "Stats endpoint responding"
    else
        log "ERROR" "Stats endpoint not responding"
        return 1
    fi
    
    # Test main endpoint
    if curl -f -s http://localhost:8080/ >/dev/null 2>&1; then
        log "SUCCESS" "Main endpoint responding"
    else
        log "ERROR" "Main endpoint not responding"
        return 1
    fi
    
    return 0
}

# Show results
show_minimal_results() {
    echo
    echo "=================================="
    echo "MINIMAL HAPROXY TEST RESULTS"
    echo "=================================="
    echo
    
    log "INFO" "Container Status:"
    docker ps --filter name=haproxy-minimal-test
    
    echo
    log "INFO" "Test URLs:"
    echo "   • Main site: http://localhost:8080/"
    echo "   • HAProxy stats: http://localhost:8404/stats"
    echo "   • Health check: http://localhost:8404/health"
    
    echo
    log "INFO" "Test Commands:"
    echo "   curl http://localhost:8080/"
    echo "   curl http://localhost:8404/stats"
    echo "   curl http://localhost:8404/health"
    
    echo
    log "INFO" "Container logs:"
    docker logs haproxy-minimal-test --tail 10
}

# Cleanup
cleanup_minimal() {
    log "INFO" "Cleaning up minimal test..."
    docker stop haproxy-minimal-test 2>/dev/null || true
    docker rm haproxy-minimal-test 2>/dev/null || true
    docker network rm test-network 2>/dev/null || true
    rm -f config/haproxy-minimal.cfg
    log "SUCCESS" "Cleanup completed"
}

# Main function
main() {
    echo "HAProxy Minimal Docker Test"
    echo "=========================="
    echo
    
    # Setup cleanup trap
    trap cleanup_minimal EXIT
    
    create_minimal_config
    start_minimal_test
    
    if test_minimal; then
        show_minimal_results
        log "SUCCESS" "Minimal test completed successfully!"
        
        echo
        echo "HAProxy is working! Press Enter to cleanup and exit..."
        read -r
    else
        log "ERROR" "Minimal test failed"
        exit 1
    fi
}

main "$@"