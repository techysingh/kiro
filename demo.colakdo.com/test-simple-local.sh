#!/bin/bash
"""
Simple Local Docker Test for HAProxy
Tests basic HAProxy functionality locally
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

# Setup function
setup() {
    log "INFO" "Setting up local test environment..."
    
    # Create required directories
    mkdir -p logs certs config errors
    
    # Create proxy network if it doesn't exist
    if ! docker network ls | grep -q proxy-network; then
        docker network create proxy-network
        log "INFO" "Created proxy-network"
    fi
    
    log "SUCCESS" "Setup completed"
}

# Start the stack
start_stack() {
    log "INFO" "Starting HAProxy local test stack..."
    
    if docker compose -f docker-compose.local.yml up -d; then
        log "SUCCESS" "Stack started successfully"
        
        # Wait for services to be ready
        log "INFO" "Waiting for services to be ready..."
        sleep 15
        
        return 0
    else
        log "ERROR" "Failed to start stack"
        return 1
    fi
}

# Test the deployment
test_deployment() {
    log "INFO" "Testing HAProxy deployment..."
    
    # Check container status
    log "INFO" "Container status:"
    docker compose -f docker-compose.local.yml ps
    
    # Test HAProxy health
    log "INFO" "Testing HAProxy health endpoint..."
    local attempts=0
    while [[ $attempts -lt 10 ]]; do
        if curl -f -s http://localhost:8404/health >/dev/null 2>&1; then
            log "SUCCESS" "HAProxy health endpoint responding"
            break
        fi
        sleep 2
        ((attempts++))
    done
    
    if [[ $attempts -eq 10 ]]; then
        log "ERROR" "HAProxy health endpoint not responding"
        return 1
    fi
    
    # Test HAProxy stats
    log "INFO" "Testing HAProxy stats..."
    if curl -f -s http://localhost:8404/stats >/dev/null 2>&1; then
        log "SUCCESS" "HAProxy stats accessible"
    else
        log "WARNING" "HAProxy stats not accessible"
    fi
    
    # Test main HTTP endpoint
    log "INFO" "Testing main HTTP endpoint..."
    if curl -f -s http://localhost:8080/ >/dev/null 2>&1; then
        log "SUCCESS" "Main HTTP endpoint responding"
    else
        log "ERROR" "Main HTTP endpoint not responding"
        return 1
    fi
    
    # Test with different host headers
    local hosts=("colakdo.local" "www.colakdo.local" "api.colakdo.local")
    
    for host in "${hosts[@]}"; do
        log "INFO" "Testing host: $host"
        local response
        response=$(curl -s -H "Host: $host" http://localhost:8080/ | head -1)
        if [[ -n "$response" ]]; then
            log "SUCCESS" "Host $host responding: ${response:0:50}..."
        else
            log "WARNING" "Host $host not responding"
        fi
    done
    
    return 0
}

# Show results
show_results() {
    echo
    echo "=================================="
    echo "LOCAL HAPROXY TEST RESULTS"
    echo "=================================="
    echo
    
    log "INFO" "Container Status:"
    docker compose -f docker-compose.local.yml ps
    
    echo
    log "INFO" "Access URLs:"
    echo "   • Main site: http://localhost:8080/"
    echo "   • HAProxy stats: http://localhost:8404/stats"
    echo "   • Health check: http://localhost:8404/health"
    
    echo
    log "INFO" "Test Commands:"
    echo "   curl http://localhost:8080/"
    echo "   curl -H 'Host: api.colakdo.local' http://localhost:8080/"
    echo "   curl http://localhost:8404/stats"
    
    echo
    log "INFO" "Management Commands:"
    echo "   • View logs: docker compose -f docker-compose.local.yml logs -f"
    echo "   • Stop: docker compose -f docker-compose.local.yml down"
    echo "   • Restart: docker compose -f docker-compose.local.yml restart"
    
    echo
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up..."
    docker compose -f docker-compose.local.yml down 2>/dev/null || true
    log "SUCCESS" "Cleanup completed"
}

# Main function
main() {
    echo "HAProxy Simple Local Test"
    echo "========================"
    echo
    
    # Setup trap for cleanup on exit
    trap cleanup EXIT
    
    setup
    
    if start_stack && test_deployment; then
        show_results
        log "SUCCESS" "Local test completed successfully!"
        
        echo
        echo "Press Ctrl+C to stop and cleanup, or run:"
        echo "docker compose -f docker-compose.local.yml down"
        
        # Keep running until interrupted
        while true; do
            sleep 10
        done
    else
        log "ERROR" "Local test failed"
        exit 1
    fi
}

# Handle arguments
case "${1:-}" in
    --cleanup)
        cleanup
        exit 0
        ;;
    --help|-h)
        echo "Simple HAProxy Local Test"
        echo "Usage: $0 [--cleanup|--help]"
        echo
        echo "This script tests HAProxy locally using Docker"
        exit 0
        ;;
    *)
        main
        ;;
esac