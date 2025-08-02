#!/bin/bash
"""
Complete Build and Deployment Script for demo.colakdo.com
Builds custom images and deploys the HAProxy stack
"""

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
}

# Check Docker is running
check_docker() {
    log "INFO" "Checking Docker status..."
    
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    log "SUCCESS" "Docker is running"
}

# Build custom Certbot image
build_certbot_image() {
    log "INFO" "Building custom Certbot image with GoDaddy support..."
    
    if docker build -t haproxy-certbot-godaddy:latest -f docker/certbot-godaddy/Dockerfile .; then
        log "SUCCESS" "Custom Certbot image built successfully"
    else
        log "ERROR" "Failed to build Certbot image"
        exit 1
    fi
}

# Create required directories
create_directories() {
    log "INFO" "Creating required directories..."
    
    mkdir -p logs certs config errors
    chmod 755 logs certs config errors
    
    log "SUCCESS" "Directories created"
}

# Validate configuration
validate_config() {
    log "INFO" "Validating configuration..."
    
    # Check .env file
    if [[ ! -f ".env" ]]; then
        log "ERROR" ".env file not found"
        exit 1
    fi
    
    # Check GoDaddy credentials
    if [[ ! -f "dns-credentials/godaddy.ini" ]]; then
        log "ERROR" "GoDaddy credentials file not found"
        exit 1
    fi
    
    # Check if credentials are configured
    if grep -q "YOUR_GODADDY_API_KEY_HERE" dns-credentials/godaddy.ini; then
        log "ERROR" "Please configure your GoDaddy API credentials in dns-credentials/godaddy.ini"
        exit 1
    fi
    
    log "SUCCESS" "Configuration validation passed"
}

# Deploy the stack
deploy_stack() {
    log "INFO" "Deploying HAProxy stack..."
    
    # Create proxy network if it doesn't exist
    if ! docker network ls | grep -q proxy-network; then
        docker network create proxy-network
        log "INFO" "Created proxy-network"
    fi
    
    # Start the stack
    if docker compose up -d; then
        log "SUCCESS" "HAProxy stack deployed successfully"
    else
        log "ERROR" "Failed to deploy HAProxy stack"
        exit 1
    fi
}

# Monitor deployment
monitor_deployment() {
    log "INFO" "Monitoring deployment status..."
    
    # Wait for services to start
    sleep 10
    
    # Check container status
    log "INFO" "Container status:"
    docker compose ps
    
    # Check HAProxy health
    local attempts=0
    while [[ $attempts -lt 12 ]]; do
        if curl -f -s http://localhost:8404/health >/dev/null 2>&1; then
            log "SUCCESS" "HAProxy is healthy and responding"
            break
        fi
        sleep 5
        ((attempts++))
    done
    
    if [[ $attempts -eq 12 ]]; then
        log "WARNING" "HAProxy health check timeout - check logs"
    fi
}

# Show deployment information
show_deployment_info() {
    echo
    echo "=================================="
    echo "DEPLOYMENT COMPLETED"
    echo "=================================="
    echo
    echo "🌐 Your HAProxy Wildcard SSL is now running!"
    echo
    echo "📋 Important URLs:"
    echo "   • Main site: https://colakdo.com"
    echo "   • WWW site: https://www.colakdo.com"
    echo "   • API endpoint: https://api.colakdo.com"
    echo "   • App: https://app.colakdo.com"
    echo "   • Admin: https://admin.colakdo.com"
    echo "   • Demo: https://demo.colakdo.com"
    echo "   • HAProxy Stats: https://colakdo.com:8404/stats"
    echo
    echo "🔐 HAProxy Stats Login:"
    echo "   • Username: admin"
    echo "   • Password: SecureHAProxyPassword2024!"
    echo
    echo "📊 Useful Commands:"
    echo "   • View logs: docker compose logs -f"
    echo "   • Check status: docker compose ps"
    echo "   • Monitor certificates: docker compose logs -f certbot-ssl"
    echo "   • Run health check: ./scripts/test-error-recovery.sh"
    echo
    echo "⚠️  DNS Configuration Required:"
    echo "   Add these A records in GoDaddy DNS pointing to your server IP:"
    echo "   • @ (root domain)"
    echo "   • * (wildcard for all subdomains)"
    echo "   • www, api, app, admin, demo (specific subdomains)"
    echo
    echo "🔄 Certificate Generation:"
    echo "   • Certificates are being generated automatically"
    echo "   • This may take 5-10 minutes for first-time setup"
    echo "   • Monitor progress: docker compose logs -f certbot-ssl"
    echo
}

# Main execution
main() {
    echo "HAProxy Wildcard SSL - Build and Deploy"
    echo "======================================"
    echo
    
    check_docker
    validate_config
    build_certbot_image
    create_directories
    deploy_stack
    monitor_deployment
    show_deployment_info
    
    log "SUCCESS" "Deployment completed successfully!"
}

# Execute main function
main "$@"