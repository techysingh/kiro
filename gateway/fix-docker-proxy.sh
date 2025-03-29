#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Check if docker-proxy exists in /usr/sbin
if [ ! -f "/usr/sbin/docker-proxy" ]; then
    echo "docker-proxy not found in /usr/sbin. Installing..."
    
    # Install docker.io package which includes docker-proxy
    apt-get update
    apt-get install -y docker.io
    
    # Verify installation
    if [ ! -f "/usr/sbin/docker-proxy" ]; then
        echo "Failed to install docker-proxy. Please check your Docker installation."
        exit 1
    fi
fi

# Create symbolic link for docker-proxy
echo "Creating symbolic link for docker-proxy..."
ln -sf /usr/sbin/docker-proxy /usr/bin/docker-proxy

# Verify the link was created
if [ ! -L "/usr/bin/docker-proxy" ]; then
    echo "Failed to create symbolic link."
    exit 1
fi

# Restart Docker service
echo "Restarting Docker service..."
systemctl restart docker

# Wait for Docker to be ready
echo "Waiting for Docker to be ready..."
sleep 5

# Verify Docker is running
if ! systemctl is-active --quiet docker; then
    echo "Docker service failed to start. Please check the logs."
    journalctl -u docker -n 50
    exit 1
fi

echo "Docker proxy fixed. Please try running your containers again." 