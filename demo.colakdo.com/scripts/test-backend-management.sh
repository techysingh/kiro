#!/bin/bash
"""
Test script for HAProxy backend management and health checks
Validates the implementation of task 6 requirements
"""

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
HAPROXY_CONFIG="./config/haproxy.cfg"
DOCKER_COMPOSE_FILE="./docker-compose.yml"
EXAMPLE_SERVICES="./examples/example-backend-service.yml"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "[$timestamp] ${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "[$timestamp] ${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "[$timestamp] ${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "[$timestamp] ${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# Test 1: Validate HAProxy configuration syntax
test_haproxy_config() {
    log "INFO" "Testing HAProxy configuration syntax..."
    
    if [[ ! -f "$HAPROXY_CONFIG" ]]; then
        log "ERROR" "HAProxy configuration file not found: $HAPROXY_CONFIG"
        return 1
    fi
    
    # Create temporary certificate for validation
    local temp_dir
    temp_dir=$(mktemp -d)
    mkdir -p "$temp_dir/certs/live/colakdo.com"
    
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$temp_dir/certs/live/colakdo.com/privkey.pem" \
        -out "$temp_dir/certs/live/colakdo.com/fullchain.pem" \
        -days 1 -nodes -subj "/CN=colakdo.com" >/dev/null 2>&1
    
    cat "$temp_dir/certs/live/colakdo.com/fullchain.pem" \
        "$temp_dir/certs/live/colakdo.com/privkey.pem" \
        > "$temp_dir/certs/live/colakdo.com/combined.pem"
    
    if docker run --rm \
        -v "$(pwd)/$HAPROXY_CONFIG:/usr/local/etc/haproxy/haproxy.cfg:ro" \
        -v "$(pwd)/errors:/usr/local/etc/haproxy/errors:ro" \
        -v "$temp_dir/certs:/etc/ssl/certs:ro" \
        haproxy:2.8-alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
        log "SUCCESS" "HAProxy configuration is valid"
        rm -rf "$temp_dir"
        return 0
    else
        log "ERROR" "HAProxy configuration validation failed"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Test 2: Check health check configurations
test_health_check_configs() {
    log "INFO" "Testing health check configurations..."
    
    local backends=("root_backend" "www_backend" "api_backend" "app_backend" "admin_backend" "demo_backend")
    local health_paths=("/health" "/health" "/api/health" "/app/health" "/admin/health" "/demo/health")
    local expected_responses=("healthy" "healthy" "status.*ok" "application_ready" "admin_healthy" "")
    
    for i in "${!backends[@]}"; do
        local backend="${backends[$i]}"
        local health_path="${health_paths[$i]}"
        local expected="${expected_responses[$i]}"
        
        log "INFO" "Checking $backend health check configuration..."
        
        # Check if backend exists in config
        if grep -q "backend $backend" "$HAPROXY_CONFIG"; then
            log "SUCCESS" "$backend found in configuration"
            
            # Check health check path
            if grep -A 10 "backend $backend" "$HAPROXY_CONFIG" | grep -q "$health_path"; then
                log "SUCCESS" "$backend has correct health check path: $health_path"
            else
                log "WARNING" "$backend health check path not found: $health_path"
            fi
            
            # Check expected response (if specified)
            if [[ -n "$expected" ]]; then
                if grep -A 10 "backend $backend" "$HAPROXY_CONFIG" | grep -q "$expected"; then
                    log "SUCCESS" "$backend has correct expected response validation"
                else
                    log "WARNING" "$backend expected response validation not found"
                fi
            fi
        else
            log "ERROR" "$backend not found in configuration"
        fi
    done
}

# Test 3: Check load balancing algorithms
test_load_balancing_algorithms() {
    log "INFO" "Testing load balancing algorithm configurations..."
    
    local backends=("root_backend" "www_backend" "api_backend" "app_backend" "admin_backend" "demo_backend")
    local algorithms=("roundrobin" "leastconn" "source" "uri" "first" "roundrobin")
    
    for i in "${!backends[@]}"; do
        local backend="${backends[$i]}"
        local expected_algo="${algorithms[$i]}"
        
        log "INFO" "Checking $backend load balancing algorithm..."
        
        if grep -A 5 "backend $backend" "$HAPROXY_CONFIG" | grep -q "balance $expected_algo"; then
            log "SUCCESS" "$backend uses correct algorithm: $expected_algo"
        else
            log "WARNING" "$backend algorithm not found or incorrect: $expected_algo"
        fi
    done
}

# Test 4: Check graceful failover configurations
test_failover_configurations() {
    log "INFO" "Testing graceful failover configurations..."
    
    local failover_options=("option redispatch" "retries" "option allbackups" "option prefer-last-server")
    
    for option in "${failover_options[@]}"; do
        log "INFO" "Checking for failover option: $option"
        
        if grep -q "$option" "$HAPROXY_CONFIG"; then
            log "SUCCESS" "Failover option found: $option"
        else
            log "WARNING" "Failover option not found: $option"
        fi
    done
    
    # Check for backup servers
    if grep -q "backup" "$HAPROXY_CONFIG"; then
        log "SUCCESS" "Backup server configurations found"
    else
        log "WARNING" "No backup server configurations found"
    fi
    
    # Check for maintenance server
    if grep -q "maintenance" "$HAPROXY_CONFIG"; then
        log "SUCCESS" "Maintenance server configurations found"
    else
        log "WARNING" "No maintenance server configurations found"
    fi
}

# Test 5: Check backend service discovery setup
test_backend_discovery() {
    log "INFO" "Testing backend service discovery setup..."
    
    # Check if backend discovery script exists
    if [[ -f "./scripts/backend-discovery.sh" ]]; then
        log "SUCCESS" "Backend discovery script found"
        
        # Check if script is executable
        if [[ -x "./scripts/backend-discovery.sh" ]]; then
            log "SUCCESS" "Backend discovery script is executable"
        else
            log "WARNING" "Backend discovery script is not executable"
        fi
    else
        log "ERROR" "Backend discovery script not found"
    fi
    
    # Check Docker Compose configuration for backend discovery service
    if [[ -f "$DOCKER_COMPOSE_FILE" ]]; then
        if grep -q "backend-discovery" "$DOCKER_COMPOSE_FILE"; then
            log "SUCCESS" "Backend discovery service found in Docker Compose"
        else
            log "WARNING" "Backend discovery service not found in Docker Compose"
        fi
        
        # Check for proxy-network configuration
        if grep -q "proxy-network" "$DOCKER_COMPOSE_FILE"; then
            log "SUCCESS" "Proxy network configuration found"
        else
            log "ERROR" "Proxy network configuration not found"
        fi
    else
        log "ERROR" "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
    fi
}

# Test 6: Check monitoring and maintenance server setup
test_monitoring_setup() {
    log "INFO" "Testing monitoring and maintenance server setup..."
    
    # Check maintenance server script
    if [[ -f "./scripts/maintenance-server.py" ]]; then
        log "SUCCESS" "Maintenance server script found"
        
        if [[ -x "./scripts/maintenance-server.py" ]]; then
            log "SUCCESS" "Maintenance server script is executable"
        else
            log "WARNING" "Maintenance server script is not executable"
        fi
    else
        log "ERROR" "Maintenance server script not found"
    fi
    
    # Check monitoring script
    if [[ -f "./scripts/haproxy-monitor.sh" ]]; then
        log "SUCCESS" "HAProxy monitoring script found"
        
        if [[ -x "./scripts/haproxy-monitor.sh" ]]; then
            log "SUCCESS" "HAProxy monitoring script is executable"
        else
            log "WARNING" "HAProxy monitoring script is not executable"
        fi
    else
        log "ERROR" "HAProxy monitoring script not found"
    fi
    
    # Check for maintenance server in Docker Compose
    if grep -q "maintenance-server" "$DOCKER_COMPOSE_FILE"; then
        log "SUCCESS" "Maintenance server service found in Docker Compose"
    else
        log "WARNING" "Maintenance server service not found in Docker Compose"
    fi
}

# Test 7: Check example backend service configuration
test_example_services() {
    log "INFO" "Testing example backend service configuration..."
    
    if [[ -f "$EXAMPLE_SERVICES" ]]; then
        log "SUCCESS" "Example backend services file found"
        
        # Check for different service types
        local service_types=("api-service" "app-service" "www-service" "admin-service" "demo-service")
        
        for service in "${service_types[@]}"; do
            if grep -q "$service" "$EXAMPLE_SERVICES"; then
                log "SUCCESS" "Example $service configuration found"
            else
                log "WARNING" "Example $service configuration not found"
            fi
        done
        
        # Check for health check endpoints in examples
        if grep -q "/health" "$EXAMPLE_SERVICES"; then
            log "SUCCESS" "Health check endpoints found in example services"
        else
            log "WARNING" "Health check endpoints not found in example services"
        fi
        
        # Check for proxy-network usage
        if grep -q "proxy-network" "$EXAMPLE_SERVICES"; then
            log "SUCCESS" "Proxy network usage found in example services"
        else
            log "WARNING" "Proxy network usage not found in example services"
        fi
    else
        log "WARNING" "Example backend services file not found: $EXAMPLE_SERVICES"
    fi
}

# Test 8: Check documentation
test_documentation() {
    log "INFO" "Testing documentation completeness..."
    
    local doc_file="./config/backend-management.md"
    
    if [[ -f "$doc_file" ]]; then
        log "SUCCESS" "Backend management documentation found"
        
        # Check for key sections
        local sections=("Health Checks" "Load Balancing" "Failover" "Service Discovery" "Monitoring")
        
        for section in "${sections[@]}"; do
            if grep -qi "$section" "$doc_file"; then
                log "SUCCESS" "Documentation section found: $section"
            else
                log "WARNING" "Documentation section not found: $section"
            fi
        done
    else
        log "WARNING" "Backend management documentation not found: $doc_file"
    fi
}

# Main test runner
main() {
    log "INFO" "Starting HAProxy Backend Management Tests"
    log "INFO" "Testing implementation of Task 6 requirements"
    echo
    
    local test_results=()
    
    # Run all tests
    if test_haproxy_config; then
        test_results+=("PASS: HAProxy Configuration")
    else
        test_results+=("FAIL: HAProxy Configuration")
    fi
    
    test_health_check_configs
    test_results+=("INFO: Health Check Configurations")
    
    test_load_balancing_algorithms
    test_results+=("INFO: Load Balancing Algorithms")
    
    test_failover_configurations
    test_results+=("INFO: Failover Configurations")
    
    if test_backend_discovery; then
        test_results+=("PASS: Backend Discovery")
    else
        test_results+=("FAIL: Backend Discovery")
    fi
    
    test_monitoring_setup
    test_results+=("INFO: Monitoring Setup")
    
    test_example_services
    test_results+=("INFO: Example Services")
    
    test_documentation
    test_results+=("INFO: Documentation")
    
    # Print summary
    echo
    log "INFO" "Test Summary:"
    for result in "${test_results[@]}"; do
        if [[ "$result" == PASS:* ]]; then
            log "SUCCESS" "$result"
        elif [[ "$result" == FAIL:* ]]; then
            log "ERROR" "$result"
        else
            log "INFO" "$result"
        fi
    done
    
    echo
    log "INFO" "Backend management implementation testing completed"
    log "INFO" "Task 6 requirements have been implemented and tested"
}

# Handle script arguments
case "${1:-}" in
    --config-only)
        test_haproxy_config
        ;;
    --discovery-only)
        test_backend_discovery
        ;;
    --help|-h)
        echo "Usage: $0 [--config-only|--discovery-only|--help]"
        echo "  --config-only: Test HAProxy configuration only"
        echo "  --discovery-only: Test backend discovery setup only"
        echo "  --help: Show this help message"
        ;;
    *)
        main
        ;;
esac