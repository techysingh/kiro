#!/bin/bash
"""
Test Deployment Script for demo.colakdo.com
Tests the deployed HAProxy stack functionality
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

# Test Docker containers
test_containers() {
    log "INFO" "Testing Docker containers..."
    
    local containers=("haproxy-proxy" "certbot-ssl" "haproxy-syslog" "haproxy-monitor" "haproxy-maintenance")
    
    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            log "SUCCESS" "Container running: $container"
        else
            log "ERROR" "Container not running: $container"
        fi
    done
}

# Test HAProxy health
test_haproxy_health() {
    log "INFO" "Testing HAProxy health..."
    
    if curl -f -s http://localhost:8404/health >/dev/null 2>&1; then
        log "SUCCESS" "HAProxy health endpoint responding"
    else
        log "ERROR" "HAProxy health endpoint not responding"
    fi
    
    if curl -f -s http://localhost:8404/stats >/dev/null 2>&1; then
        log "SUCCESS" "HAProxy stats endpoint accessible"
    else
        log "WARNING" "HAProxy stats endpoint not accessible (may require authentication)"
    fi
}

# Test certificate status
test_certificates() {
    log "INFO" "Testing certificate status..."
    
    if [[ -f "certs/live/colakdo.com/fullchain.pem" ]]; then
        log "SUCCESS" "Certificate file exists"
        
        # Check certificate validity
        if openssl x509 -in certs/live/colakdo.com/fullchain.pem -noout -checkend 86400 >/dev/null 2>&1; then
            log "SUCCESS" "Certificate is valid"
        else
            log "WARNING" "Certificate may be expired or invalid"
        fi
    else
        log "WARNING" "Certificate not yet generated (this is normal for new deployments)"
    fi
}

# Test network connectivity
test_network() {
    log "INFO" "Testing network configuration..."
    
    if docker network ls | grep -q proxy-network; then
        log "SUCCESS" "Proxy network exists"
    else
        log "ERROR" "Proxy network not found"
    fi
    
    # Test port accessibility
    local ports=(80 443 8404)
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log "SUCCESS" "Port $port is bound"
        else
            log "WARNING" "Port $port may not be accessible"
        fi
    done
}

# Test logs
test_logs() {
    log "INFO" "Testing log files..."
    
    local log_files=("logs/haproxy.log" "logs/access.log" "logs/error.log")
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            log "SUCCESS" "Log file exists: $log_file"
        else
            log "WARNING" "Log file not found: $log_file (may be created after first requests)"
        fi
    done
}

# Show service status
show_service_status() {
    echo
    log "INFO" "Current service status:"
    docker compose ps
    
    echo
    log "INFO" "Recent logs (last 10 lines):"
    docker compose logs --tail=10
}

# Main test execution
main() {
    echo "HAProxy Deployment Test"
    echo "======================"
    echo
    
    test_containers
    test_haproxy_health
    test_certificates
    test_network
    test_logs
    show_service_status
    
    echo
    log "INFO" "Test completed. Check results above."
    echo
    echo "Next steps:"
    echo "1. Configure DNS records in GoDaddy"
    echo "2. Wait for certificate generation (5-10 minutes)"
    echo "3. Test HTTPS endpoints"
    echo "4. Deploy backend services if needed"
}

main "$@"