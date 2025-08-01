#!/bin/bash

# DNS Provider Setup Script
# Helps configure DNS credentials for different providers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DNS_CREDS_DIR="$PROJECT_DIR/dns-credentials"

# Available DNS providers
SUPPORTED_PROVIDERS=(
    "cloudflare"
    "route53"
    "digitalocean"
    "google"
    "ovh"
    "godaddy"
)

# Function to display usage
usage() {
    echo "Usage: $0 <provider>"
    echo ""
    echo "Supported providers:"
    for provider in "${SUPPORTED_PROVIDERS[@]}"; do
        echo "  - $provider"
    done
    echo ""
    echo "Examples:"
    echo "  $0 cloudflare"
    echo "  $0 route53"
    exit 1
}

# Function to setup Cloudflare
setup_cloudflare() {
    echo "Setting up Cloudflare DNS provider..."
    
    local creds_file="$DNS_CREDS_DIR/cloudflare.ini"
    local example_file="$DNS_CREDS_DIR/cloudflare.ini.example"
    
    if [[ -f "$creds_file" ]]; then
        echo "Cloudflare credentials file already exists: $creds_file"
        read -p "Do you want to overwrite it? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Keeping existing credentials file."
            return 0
        fi
    fi
    
    echo "Creating Cloudflare credentials file..."
    cp "$example_file" "$creds_file"
    chmod 600 "$creds_file"
    
    echo ""
    echo "Please edit $creds_file and add your Cloudflare API token."
    echo "You can get your API token from: https://dash.cloudflare.com/profile/api-tokens"
    echo ""
    echo "Required permissions for the token:"
    echo "  - Zone:Zone:Read"
    echo "  - Zone:DNS:Edit"
    echo ""
}

# Function to setup Route53
setup_route53() {
    echo "Setting up AWS Route53 DNS provider..."
    
    local creds_file="$DNS_CREDS_DIR/route53.ini"
    local example_file="$DNS_CREDS_DIR/route53.ini.example"
    
    if [[ -f "$creds_file" ]]; then
        echo "Route53 credentials file already exists: $creds_file"
        read -p "Do you want to overwrite it? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Keeping existing credentials file."
            return 0
        fi
    fi
    
    echo "Creating Route53 credentials file..."
    cp "$example_file" "$creds_file"
    chmod 600 "$creds_file"
    
    echo ""
    echo "Please edit $creds_file and add your AWS credentials."
    echo "You can get your credentials from AWS IAM console."
    echo ""
    echo "Required IAM permissions:"
    echo "  - route53:GetChange"
    echo "  - route53:ChangeResourceRecordSets"
    echo "  - route53:ListHostedZonesByName"
    echo ""
}

# Function to setup GoDaddy
setup_godaddy() {
    echo "Setting up GoDaddy DNS provider..."
    
    local creds_file="$DNS_CREDS_DIR/godaddy.ini"
    local example_file="$DNS_CREDS_DIR/godaddy.ini.example"
    
    if [[ -f "$creds_file" ]]; then
        echo "GoDaddy credentials file already exists: $creds_file"
        read -p "Do you want to overwrite it? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Keeping existing credentials file."
            return 0
        fi
    fi
    
    echo "Creating GoDaddy credentials file..."
    cp "$example_file" "$creds_file"
    chmod 600 "$creds_file"
    
    echo ""
    echo "Please edit $creds_file and add your GoDaddy API credentials."
    echo "You can get your API key and secret from: https://developer.godaddy.com/keys"
    echo ""
    echo "Required steps:"
    echo "  1. Go to https://developer.godaddy.com/keys"
    echo "  2. Create a new API key with Domain permissions"
    echo "  3. Copy the Key and Secret to the credentials file"
    echo "  4. Ensure the file has correct permissions: chmod 600 $creds_file"
    echo ""
    echo "Note: GoDaddy DNS challenges may take longer than other providers."
    echo "The system will automatically wait for DNS propagation."
    echo ""
}

# Function to create additional provider examples
create_additional_examples() {
    echo "Creating additional DNS provider examples..."
    
    # DigitalOcean
    cat > "$DNS_CREDS_DIR/digitalocean.ini.example" << 'EOF'
# DigitalOcean DNS credentials for DNS-01 challenge
# Copy this file to digitalocean.ini and fill in your credentials

# DigitalOcean API Token
dns_digitalocean_token = your-digitalocean-api-token

# File permissions should be 600 (read/write for owner only)
# chmod 600 dns-credentials/digitalocean.ini
EOF

    # Google Cloud DNS
    cat > "$DNS_CREDS_DIR/google.ini.example" << 'EOF'
# Google Cloud DNS credentials for DNS-01 challenge
# Copy this file to google.ini and fill in your credentials

# Path to Google Cloud service account JSON key file
dns_google_credentials = /path/to/your/service-account-key.json

# File permissions should be 600 (read/write for owner only)
# chmod 600 dns-credentials/google.ini
EOF

    # OVH
    cat > "$DNS_CREDS_DIR/ovh.ini.example" << 'EOF'
# OVH DNS credentials for DNS-01 challenge
# Copy this file to ovh.ini and fill in your credentials

# OVH API credentials
dns_ovh_endpoint = ovh-eu
dns_ovh_application_key = your-application-key
dns_ovh_application_secret = your-application-secret
dns_ovh_consumer_key = your-consumer-key

# File permissions should be 600 (read/write for owner only)
# chmod 600 dns-credentials/ovh.ini
EOF

    echo "Additional DNS provider examples created."
}

# Function to update environment file
update_env_file() {
    local provider="$1"
    local env_file="$PROJECT_DIR/.env"
    
    if [[ ! -f "$env_file" ]]; then
        echo "Creating .env file from template..."
        cp "$PROJECT_DIR/.env.example" "$env_file"
    fi
    
    # Update DNS_PLUGIN in .env file
    if grep -q "^DNS_PLUGIN=" "$env_file"; then
        sed -i.bak "s/^DNS_PLUGIN=.*/DNS_PLUGIN=dns-$provider/" "$env_file"
        rm -f "$env_file.bak"
    else
        echo "DNS_PLUGIN=dns-$provider" >> "$env_file"
    fi
    
    echo "Updated DNS_PLUGIN in .env file to: dns-$provider"
}

# Main execution
main() {
    if [[ $# -ne 1 ]]; then
        usage
    fi
    
    local provider="$1"
    
    # Check if provider is supported
    if [[ ! " ${SUPPORTED_PROVIDERS[*]} " =~ " ${provider} " ]]; then
        echo "Error: Unsupported DNS provider: $provider"
        usage
    fi
    
    echo "Setting up DNS provider: $provider"
    echo "Project directory: $PROJECT_DIR"
    echo "DNS credentials directory: $DNS_CREDS_DIR"
    echo ""
    
    # Create DNS credentials directory if it doesn't exist
    mkdir -p "$DNS_CREDS_DIR"
    
    # Create additional examples if they don't exist
    create_additional_examples
    
    # Setup specific provider
    case "$provider" in
        "cloudflare")
            setup_cloudflare
            ;;
        "route53")
            setup_route53
            ;;
        "godaddy")
            setup_godaddy
            ;;
        *)
            echo "Provider $provider is supported but setup function not implemented yet."
            echo "Please manually copy and configure: $DNS_CREDS_DIR/${provider}.ini.example"
            ;;
    esac
    
    # Update environment file
    update_env_file "$provider"
    
    echo ""
    echo "DNS provider setup completed!"
    echo "Next steps:"
    echo "1. Edit the credentials file: $DNS_CREDS_DIR/${provider}.ini"
    echo "2. Ensure the file has correct permissions: chmod 600 $DNS_CREDS_DIR/${provider}.ini"
    echo "3. Update your .env file with the correct LETSENCRYPT_EMAIL"
    echo "4. Run: docker-compose up -d"
}

# Execute main function
main "$@"