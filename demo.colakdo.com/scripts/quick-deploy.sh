#!/bin/bash
"""
Quick Deployment Script for HAProxy Wildcard SSL
Automates the deployment process with interactive prompts
"""

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# Function to prompt for user input
prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local var_name="$3"
    
    if [[ -n "$default" ]]; then
        read -p "$prompt [$default]: " input
        input="${input:-$default}"
    else
        read -p "$prompt: " input
    fi
    
    eval "$var_name='$input'"
}

# Function to prompt for password
prompt_password() {
    local prompt="$1"
    local var_name="$2"
    
    read -s -p "$prompt: " input
    echo
    eval "$var_name='$input'"
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if running on Linux
    if [[ "$(uname)" != "Linux" ]]; then
        log "ERROR" "This script must be run on Linux"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        log "ERROR" "Docker is not installed. Please install Docker first."
        echo "Run: curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh"
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        log "ERROR" "Docker Compose is not installed or not accessible"
        exit 1
    fi
    
    # Check if user can run Docker
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Cannot access Docker. Make sure your user is in the docker group."
        echo "Run: sudo usermod -aG docker \$USER && logout && login"
        exit 1
    fi
    
    log "SUCCESS" "Prerequisites check passed"
}

# Collect configuration
collect_configuration() {
    log "INFO" "Collecting configuration information..."
    echo
    echo "Please provide the following information:"
    echo
    
    # Domain configuration
    prompt_input "Enter your domain name (e.g., colakdo.com)" "" DOMAIN
    prompt_input "Enter your email for Let's Encrypt notifications" "" LETSENCRYPT_EMAIL
    
    # GoDaddy API credentials
    echo
    log "INFO" "GoDaddy API credentials are required for DNS-01 challenge"
    log "INFO" "Get them from: https://developer.godaddy.com/keys"
    prompt_input "Enter your GoDaddy API Key" "" GODADDY_KEY
    prompt_password "Enter your GoDaddy API Secret" GODADDY_SECRET
    
    # Security configuration
    echo
    prompt_password "Enter a secure password for HAProxy stats interface" STATS_PASSWORD
    
    # Optional configuration
    echo
    prompt_input "Enter alert email (optional, press Enter to skip)" "" ALERT_EMAIL
    prompt_input "Enter webhook URL for notifications (optional, press Enter to skip)" "" WEBHOOK_URL
    
    log "SUCCESS" "Configuration collected"
}

# Create environment file
create_environment_file() {
    log "INFO" "Creating environment configuration..."
    
    # Copy template
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    
    # Update configuration
    sed -i "s/LETSENCRYPT_EMAIL=.*/LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL/" "$PROJECT_DIR/.env"
    sed -i "s/DOMAIN=.*/DOMAIN=$DOMAIN/" "$PROJECT_DIR/.env"
    sed -i "s/DNS_PLUGIN=.*/DNS_PLUGIN=dns-godaddy/" "$PROJECT_DIR/.env"
    sed -i "s/CERTBOT_IMAGE=.*/CERTBOT_IMAGE=haproxy-certbot-godaddy:latest/" "$PROJECT_DIR/.env"
    sed -i "s/STATS_PASSWORD=.*/STATS_PASSWORD=$STATS_PASSWORD/" "$PROJECT_DIR/.env"
    
    if [[ -n "$ALERT_EMAIL" ]]; then
        sed -i "s/ALERT_EMAIL=.*/ALERT_EMAIL=$ALERT_EMAIL/" "$PROJECT_DIR/.env"
    fi
    
    if [[ -n "$WEBHOOK_URL" ]]; then
        sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=$WEBHOOK_URL|" "$PROJECT_DIR/.env"
    fi
    
    # Set secure permissions
    chmod 600 "$PROJECT_DIR/.env"
    
    log "SUCCESS" "Environment file created"
}

# Create DNS credentials
create_dns_credentials() {
    log "INFO" "Creating GoDaddy DNS credentials..."
    
    # Create credentials directory
    mkdir -p "$PROJECT_DIR/dns-credentials"
    
    # Create GoDaddy credentials file
    cat > "$PROJECT_DIR/dns-credentials/godaddy.ini" << EOF
# GoDaddy DNS credentials for DNS-01 challenge
dns_godaddy_key = $GODADDY_KEY
dns_godaddy_secret = $GODADDY_SECRET
EOF
    
    # Set secure permissions
    chmod 600 "$PROJECT_DIR/dns-credentials/godaddy.ini"
    
    log "SUCCESS" "DNS credentials created"
}

# Build custom Certbot image
build_certbot_image() {
    log "INFO" "Building custom Certbot image with GoDaddy support..."
    
    # Create Dockerfile if it doesn't exist
    mkdir -p "$PROJECT_DIR/docker/certbot-godaddy"
    
    if [[ ! -f "$PROJECT_DIR/docker/certbot-godaddy/Dockerfile" ]]; then
        cat > "$PROJECT_DIR/docker/certbot-godaddy/Dockerfile" << 'EOF'
FROM certbot/certbot:latest
RUN pip install certbot-dns-godaddy
WORKDIR /opt/certbot
CMD ["certbot"]
EOF
    fi
    
    # Build the image
    cd "$PROJECT_DIR"
    docker build -t haproxy-certbot-godaddy:latest -f docker/certbot-godaddy/Dockerfile .
    
    log "SUCCESS" "Custom Certbot image built"
}

# Prepare directories
prepare_directories() {
    log "INFO" "Preparing required directories..."
    
    cd "$PROJECT_DIR"
    mkdir -p logs certs config errors
    
    # Set proper permissions
    chmod 755 logs certs config errors
    
    log "SUCCESS" "Directories prepared"
}

# Run deployment readiness check
run_readiness_check() {
    log "INFO" "Running deployment readiness check..."
    
    cd "$PROJECT_DIR"
    if ./scripts/deployment-readiness-check.sh; then
        log "SUCCESS" "Readiness check passed"
        return 0
    else
        log "ERROR" "Readiness check failed"
        return 1
    fi
}

# Deploy the stack
deploy_stack() {
    log "INFO" "Deploying HAProxy stack..."
    
    cd "$PROJECT_DIR"
    
    # Start the stack
    docker compose up -d
    
    log "SUCCESS" "Stack deployed"
    
    # Wait a moment for services to start
    sleep 10
    
    # Check container status
    log "INFO" "Checking container status..."
    docker compose ps
}

# Verify deployment
verify_deployment() {
    log "INFO" "Verifying deployment..."
    
    cd "$PROJECT_DIR"
    
    # Check HAProxy health
    local attempts=0
    while [[ $attempts -lt 12 ]]; do  # Wait up to 60 seconds
        if curl -f -s http://localhost:8404/health >/dev/null 2>&1; then
            log "SUCCESS" "HAProxy is healthy"
            break
        fi
        sleep 5
        ((attempts++))
    done
    
    if [[ $attempts -eq 12 ]]; then
        log "WARNING" "HAProxy health check timeout"
    fi
    
    # Check certificate generation (this may take several minutes)
    log "INFO" "Certificate generation may take 5-10 minutes..."
    log "INFO" "Monitor progress with: docker compose logs -f certbot-ssl"
}

# Display post-deployment information
show_post_deployment_info() {
    echo
    echo "=================================="
    echo "DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=================================="
    echo
    echo "Your HAProxy Wildcard SSL solution is now running!"
    echo
    echo "Important URLs:"
    echo "  - Main site: https://$DOMAIN"
    echo "  - WWW site: https://www.$DOMAIN"
    echo "  - API endpoint: https://api.$DOMAIN"
    echo "  - HAProxy stats: https://$DOMAIN:8404/stats"
    echo
    echo "HAProxy Stats Login:"
    echo "  - Username: admin"
    echo "  - Password: $STATS_PASSWORD"
    echo
    echo "Useful Commands:"
    echo "  - View logs: docker compose logs -f"
    echo "  - Check status: docker compose ps"
    echo "  - Run tests: ./scripts/test-error-recovery.sh"
    echo "  - Monitor certificates: docker compose logs -f certbot-ssl"
    echo
    echo "DNS Configuration Required:"
    echo "  Add these A records in GoDaddy DNS:"
    echo "    @ -> $(curl -s ifconfig.me)"
    echo "    * -> $(curl -s ifconfig.me)"
    echo
    echo "Certificate generation is in progress..."
    echo "Monitor with: docker compose logs -f certbot-ssl"
    echo
    echo "For troubleshooting, see: DEPLOYMENT_GUIDE.md"
    echo
}

# Main deployment function
main() {
    echo "HAProxy Wildcard SSL - Quick Deployment"
    echo "======================================"
    echo
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Run deployment steps
    check_prerequisites
    collect_configuration
    create_environment_file
    create_dns_credentials
    build_certbot_image
    prepare_directories
    
    echo
    log "INFO" "Running final readiness check..."
    if ! run_readiness_check; then
        log "ERROR" "Deployment readiness check failed. Please fix issues and try again."
        exit 1
    fi
    
    echo
    log "INFO" "Starting deployment..."
    deploy_stack
    verify_deployment
    show_post_deployment_info
    
    log "SUCCESS" "Quick deployment completed!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "HAProxy Wildcard SSL Quick Deployment Script"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo
        echo "This script will:"
        echo "1. Check prerequisites (Docker, Docker Compose)"
        echo "2. Collect configuration (domain, email, API credentials)"
        echo "3. Create environment and credentials files"
        echo "4. Build custom Certbot image with GoDaddy support"
        echo "5. Deploy the HAProxy stack"
        echo "6. Verify deployment"
        echo
        echo "Prerequisites:"
        echo "- Ubuntu/Debian server with Docker installed"
        echo "- User in docker group"
        echo "- GoDaddy API credentials"
        echo "- Domain pointing to server IP"
        echo
        ;;
    *)
        main
        ;;
esac