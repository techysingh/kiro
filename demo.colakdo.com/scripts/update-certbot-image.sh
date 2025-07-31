#!/bin/bash

# Script to update CERTBOT_IMAGE in .env based on DNS_PLUGIN

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

# DNS Provider to Docker image mapping
declare -A CERTBOT_IMAGES=(
    ["dns-cloudflare"]="certbot/dns-cloudflare:latest"
    ["dns-route53"]="certbot/dns-route53:latest"
    ["dns-digitalocean"]="certbot/dns-digitalocean:latest"
    ["dns-google"]="certbot/dns-google:latest"
    ["dns-ovh"]="certbot/dns-ovh:latest"
)

# Function to get DNS plugin from .env file
get_dns_plugin() {
    if [[ -f "$ENV_FILE" ]]; then
        grep "^DNS_PLUGIN=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' || echo "dns-cloudflare"
    else
        echo "dns-cloudflare"
    fi
}

# Function to update or add CERTBOT_IMAGE in .env file
update_certbot_image() {
    local dns_plugin="$1"
    local certbot_image="${CERTBOT_IMAGES[$dns_plugin]:-certbot/dns-cloudflare:latest}"
    
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "Creating .env file from template..."
        cp "$PROJECT_DIR/.env.example" "$ENV_FILE"
    fi
    
    # Update or add CERTBOT_IMAGE
    if grep -q "^CERTBOT_IMAGE=" "$ENV_FILE"; then
        # Update existing line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s|^CERTBOT_IMAGE=.*|CERTBOT_IMAGE=$certbot_image|" "$ENV_FILE"
        else
            # Linux
            sed -i "s|^CERTBOT_IMAGE=.*|CERTBOT_IMAGE=$certbot_image|" "$ENV_FILE"
        fi
    else
        # Add new line
        echo "CERTBOT_IMAGE=$certbot_image" >> "$ENV_FILE"
    fi
    
    echo "Updated CERTBOT_IMAGE to: $certbot_image"
}

# Main execution
main() {
    local dns_plugin
    dns_plugin=$(get_dns_plugin)
    
    echo "Current DNS plugin: $dns_plugin"
    
    if [[ -z "${CERTBOT_IMAGES[$dns_plugin]:-}" ]]; then
        echo "Warning: Unknown DNS plugin '$dns_plugin', using default Cloudflare image"
        dns_plugin="dns-cloudflare"
    fi
    
    update_certbot_image "$dns_plugin"
    
    echo "Certbot image configuration updated successfully!"
    echo "You can now run: docker-compose up -d --force-recreate certbot"
}

# Execute main function
main "$@"