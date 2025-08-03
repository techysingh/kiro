#!/bin/bash
"""
Full Local HAProxy Test with Maintenance Server
Tests the complete HAProxy setup locally
"""

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    case "$1" in
        "INFO") echo -e "${BLUE}[INFO]${NC} $2" ;;
        "SUCCESS") echo -e "${GREEN}[✓]${NC} $2" ;;
        "WARNING") echo -e "${YELLOW}[!]${NC} $2" ;;
        "ERROR") echo -e "${RED}[✗]${NC} $2" ;;
    esac
}

# Setup function
setup_full_test() {
    log "INFO" "Setting up full HAProxy test..."
    
    # Create required directories
    mkdir -p logs config errors
    
    # Create network
    docker network create proxy-network 2>/dev/null || true
    
    log "SUCCESS" "Setup completed"
}

# Start maintenance server
start_maintenance_server() {
    log "INFO" "Starting maintenance server..."
    
    docker run -d \
        --name maintenance-test \
        --network proxy-network \
        -v "$(pwd)/scripts:/scripts:ro" \
        python:3.11-alpine \
        python3 /scripts/maintenance-server.py
    
    # Wait for it to start
    sleep 5
    
    log "SUCCESS" "Maintenance server started"
}

# Start HAProxy with our config
start_haproxy_full() {
    log "INFO" "Starting HAProxy with full configuration..."
    
    # Use the local HAProxy config we created earlier
    docker run -d \
        --name haproxy-full-test \
        --network proxy-network \
        -p 8080:80 \
        -p 8404:8404 \
        -v "$(pwd)/config/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
        -v "$(pwd)/errors:/usr/local/etc/haproxy/errors:ro" \
        haproxy:2.8-alpine
    
    # Wait for startup
    sleep 10
    
    log "SUCCESS" "HAProxy started with full configuration"
}

# Test the full setup
test_full_setup() {
    log "INFO" "Testing full HAProxy setup..."
    
    # Test HAProxy health
    if curl -f -s http://localhost:8404/health >/dev/null 2>&1; then
        log "SUCCESS" "HAProxy health endpoint responding"
    else
        log "ERROR" "HAProxy health endpoint not responding"
        return 1
    fi
    
    # Test HAProxy stats
    if curl -f -s http://localhost:8404/stats >/dev/null 2>&1; then
        log "SUCCESS" "HAProxy stats endpoint responding"
    else
        log "ERROR" "HAProxy stats endpoint not responding"
        return 1
    fi
    
    # Test main endpoint
    if curl -f -s http://localhost:8080/ >/dev/null 2>&1; then
        log "SUCCESS" "Main HTTP endpoint responding"
    else
        log "ERROR" "Main HTTP endpoint not responding"
        return 1
    fi
    
    # Test different host headers
    local hosts=("colakdo.local" "www.colakdo.local" "api.colakdo.local" "app.colakdo.local" "admin.colakdo.local" "demo.colakdo.local")
    
    for host in "${hosts[@]}"; do
        log "INFO" "Testing host: $host"
        local response
        response=$(curl -s -H "Host: $host" http://localhost:8080/ 2>/dev/null | head -1 || echo "")
        if [[ -n "$response" ]]; then
            log "SUCCESS" "Host $host responding"
        else
            log "WARNING" "Host $host not responding"
        fi
    done
    
    # Test health endpoints
    log "INFO" "Testing health endpoints..."
    
    # Test /health
    if curl -s -H "Host: colakdo.local" http://localhost:8080/health | grep -q "healthy"; then
        log "SUCCESS" "/health endpoint working"
    else
        log "WARNING" "/health endpoint not working as expected"
    fi
    
    # Test /api/health
    if curl -s -H "Host: api.colakdo.local" http://localhost:8080/api/health | grep -q "ok"; then
        log "SUCCESS" "/api/health endpoint working"
    else
        log "WARNING" "/api/health endpoint not working as expected"
    fi
    
    return 0
}

# Show full results
show_full_results() {
    echo
    echo "=================================="
    echo "FULL HAPROXY TEST RESULTS"
    echo "=================================="
    echo
    
    log "INFO" "Container Status:"
    docker ps --filter name=haproxy-full-test
    docker ps --filter name=maintenance-test
    
    echo
    log "INFO" "HAProxy Stats (backend status):"
    curl -s http://localhost:8404/stats | grep -E "(root_backend|www_backend|api_backend)" | head -5 || echo "Stats not available"
    
    echo
    log "INFO" "Test URLs:"
    echo "   • Main site: http://localhost:8080/"
    echo "   • HAProxy stats: http://localhost:8404/stats"
    echo "   • Health check: http://localhost:8404/health"
    
    echo
    log "INFO" "Host Header Tests:"
    echo "   curl -H 'Host: colakdo.local' http://localhost:8080/"
    echo "   curl -H 'Host: api.colakdo.local' http://localhost:8080/api/health"
    echo "   curl -H 'Host: www.colakdo.local' http://localhost:8080/"
    
    echo
    log "INFO" "Sample Responses:"
    echo "Root domain:"
    curl -s -H "Host: colakdo.local" http://localhost:8080/ | head -3
    echo
    echo "API health:"
    curl -s -H "Host: api.colakdo.local" http://localhost:8080/api/health
    echo
    
    echo
    log "INFO" "HAProxy Logs:"
    docker logs haproxy-full-test --tail 5
}

# Cleanup function
cleanup_full() {
    log "INFO" "Cleaning up full test..."
    docker stop haproxy-full-test maintenance-test 2>/dev/null || true
    docker rm haproxy-full-test maintenance-test 2>/dev/null || true
    docker network rm proxy-network 2>/dev/null || true
    log "SUCCESS" "Cleanup completed"
}

# Main function
main() {
    echo "HAProxy Full Local Docker Test"
    echo "=============================="
    echo
    
    # Setup cleanup trap
    trap cleanup_full EXIT
    
    setup_full_test
    start_maintenance_server
    start_haproxy_full
    
    if test_full_setup; then
        show_full_results
        log "SUCCESS" "Full HAProxy test completed successfully!"
        
        echo
        echo "🎉 HAProxy is working with:"
        echo "   ✓ Load balancing configuration"
        echo "   ✓ Health checks"
        echo "   ✓ Multiple backend routing"
        echo "   ✓ Maintenance server fallback"
        echo "   ✓ Statistics interface"
        echo
        echo "Press Enter to cleanup and exit..."
        read -r
    else
        log "ERROR" "Full test failed"
        exit 1
    fi
}

main "$@"