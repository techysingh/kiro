#!/bin/bash
"""
Deployment Readiness Check Script
Verifies all components are ready for production deployment
"""

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "PASS")
            echo -e "${GREEN}[✓]${NC} $message"
            ((CHECKS_PASSED++))
            ;;
        "FAIL")
            echo -e "${RED}[✗]${NC} $message"
            ((CHECKS_FAILED++))
            ;;
        "WARN")
            echo -e "${YELLOW}[!]${NC} $message"
            ((CHECKS_WARNING++))
            ;;
        "INFO")
            echo -e "${BLUE}[i]${NC} $message"
            ;;
    esac
}

# Check if running on Ubuntu/Debian
check_os() {
    log "INFO" "Checking operating system..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]] || [[ "$ID" == "debian" ]]; then
            log "PASS" "Running on $PRETTY_NAME"
        else
            log "WARN" "Running on $PRETTY_NAME (Ubuntu/Debian recommended)"
        fi
    else
        log "WARN" "Cannot determine OS version"
    fi
}

# Check Docker installation
check_docker() {
    log "INFO" "Checking Docker installation..."
    
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        log "PASS" "Docker installed: $docker_version"
        
        # Check if Docker daemon is running
        if docker info >/dev/null 2>&1; then
            log "PASS" "Docker daemon is running"
        else
            log "FAIL" "Docker daemon is not running"
        fi
        
        # Check Docker Compose
        if docker compose version >/dev/null 2>&1; then
            local compose_version
            compose_version=$(docker compose version --short)
            log "PASS" "Docker Compose installed: $compose_version"
        else
            log "FAIL" "Docker Compose not installed or not accessible"
        fi
    else
        log "FAIL" "Docker is not installed"
    fi
}

# Check required files
check_required_files() {
    log "INFO" "Checking required configuration files..."
    
    local required_files=(
        "docker-compose.yml"
        "config/haproxy.cfg"
        "scripts/certbot-manager.sh"
        "scripts/haproxy-monitor.sh"
        "scripts/error-recovery-manager.sh"
        ".env.example"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "PASS" "Required file exists: $file"
        else
            log "FAIL" "Required file missing: $file"
        fi
    done
}

# Check environment configuration
check_environment_config() {
    log "INFO" "Checking environment configuration..."
    
    if [[ -f ".env" ]]; then
        log "PASS" "Environment file (.env) exists"
        
        # Check required variables
        local required_vars=("LETSENCRYPT_EMAIL" "DOMAIN" "DNS_PLUGIN")
        
        for var in "${required_vars[@]}"; do
            if grep -q "^${var}=" .env && ! grep -q "^${var}=$" .env; then
                log "PASS" "Environment variable set: $var"
            else
                log "FAIL" "Environment variable missing or empty: $var"
            fi
        done
        
        # Check DNS plugin
        local dns_plugin
        dns_plugin=$(grep "^DNS_PLUGIN=" .env | cut -d'=' -f2 || echo "")
        if [[ -n "$dns_plugin" ]]; then
            local creds_file="dns-credentials/${dns_plugin#dns-}.ini"
            if [[ -f "$creds_file" ]]; then
                log "PASS" "DNS credentials file exists: $creds_file"
                
                # Check file permissions
                local perms
                perms=$(stat -c "%a" "$creds_file")
                if [[ "$perms" == "600" ]]; then
                    log "PASS" "DNS credentials file has correct permissions (600)"
                else
                    log "WARN" "DNS credentials file permissions should be 600 (currently: $perms)"
                fi
            else
                log "FAIL" "DNS credentials file missing: $creds_file"
            fi
        fi
    else
        log "FAIL" "Environment file (.env) not found - copy from .env.example"
    fi
}

# Check network requirements
check_network() {
    log "INFO" "Checking network requirements..."
    
    # Check if ports are available
    local required_ports=(80 443 8404)
    
    for port in "${required_ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log "WARN" "Port $port is already in use"
        else
            log "PASS" "Port $port is available"
        fi
    done
    
    # Check internet connectivity
    if curl -s --max-time 5 https://api.letsencrypt.org/directory >/dev/null 2>&1; then
        log "PASS" "Internet connectivity to Let's Encrypt API"
    else
        log "FAIL" "Cannot reach Let's Encrypt API"
    fi
}

# Check system resources
check_system_resources() {
    log "INFO" "Checking system resources..."
    
    # Check available memory
    local mem_total
    mem_total=$(free -m | awk 'NR==2{print $2}')
    if [[ $mem_total -ge 1024 ]]; then
        log "PASS" "Sufficient memory: ${mem_total}MB"
    else
        log "WARN" "Low memory: ${mem_total}MB (recommended: 1GB+)"
    fi
    
    # Check available disk space
    local disk_avail
    disk_avail=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ $disk_avail -ge 5 ]]; then
        log "PASS" "Sufficient disk space: ${disk_avail}GB available"
    else
        log "WARN" "Low disk space: ${disk_avail}GB (recommended: 5GB+)"
    fi
    
    # Check CPU cores
    local cpu_cores
    cpu_cores=$(nproc)
    if [[ $cpu_cores -ge 2 ]]; then
        log "PASS" "Sufficient CPU cores: $cpu_cores"
    else
        log "WARN" "Limited CPU cores: $cpu_cores (recommended: 2+)"
    fi
}

# Check DNS configuration
check_dns_config() {
    log "INFO" "Checking DNS configuration..."
    
    if [[ -f ".env" ]]; then
        local domain
        domain=$(grep "^DOMAIN=" .env | cut -d'=' -f2 || echo "")
        
        if [[ -n "$domain" ]]; then
            # Check if domain resolves
            if nslookup "$domain" >/dev/null 2>&1; then
                log "PASS" "Domain resolves: $domain"
                
                # Check if domain points to this server
                local domain_ip
                local server_ip
                domain_ip=$(dig +short "$domain" | tail -1)
                server_ip=$(curl -s --max-time 5 ifconfig.me || echo "unknown")
                
                if [[ "$domain_ip" == "$server_ip" ]]; then
                    log "PASS" "Domain points to this server"
                else
                    log "WARN" "Domain IP ($domain_ip) differs from server IP ($server_ip)"
                fi
            else
                log "WARN" "Domain does not resolve: $domain"
            fi
        fi
    fi
}

# Check security settings
check_security() {
    log "INFO" "Checking security settings..."
    
    # Check if UFW is installed and configured
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status
        ufw_status=$(ufw status | head -1)
        if [[ "$ufw_status" == *"active"* ]]; then
            log "PASS" "UFW firewall is active"
        else
            log "WARN" "UFW firewall is not active"
        fi
    else
        log "WARN" "UFW firewall not installed"
    fi
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log "WARN" "Running as root (consider using non-root user with Docker group)"
    else
        log "PASS" "Running as non-root user"
        
        # Check if user is in docker group
        if groups | grep -q docker; then
            log "PASS" "User is in docker group"
        else
            log "FAIL" "User is not in docker group"
        fi
    fi
}

# Generate deployment report
generate_deployment_report() {
    echo
    echo "=================================="
    echo "DEPLOYMENT READINESS SUMMARY"
    echo "=================================="
    echo "Checks Passed:  $CHECKS_PASSED"
    echo "Checks Failed:  $CHECKS_FAILED"
    echo "Warnings:       $CHECKS_WARNING"
    echo "Total Checks:   $((CHECKS_PASSED + CHECKS_FAILED + CHECKS_WARNING))"
    echo
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ READY FOR DEPLOYMENT${NC}"
        echo
        echo "Next steps:"
        echo "1. Review any warnings above"
        echo "2. Run: docker compose up -d"
        echo "3. Monitor logs: docker compose logs -f"
        echo "4. Check status: ./scripts/test-error-recovery.sh"
        return 0
    else
        echo -e "${RED}✗ NOT READY FOR DEPLOYMENT${NC}"
        echo
        echo "Please fix the failed checks above before deploying."
        return 1
    fi
}

# Main execution
main() {
    echo "HAProxy Wildcard SSL - Deployment Readiness Check"
    echo "================================================="
    echo
    
    check_os
    check_docker
    check_required_files
    check_environment_config
    check_network
    check_system_resources
    check_dns_config
    check_security
    
    generate_deployment_report
}

main "$@"