#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Get current user and group IDs
USER_ID=$(id -u)
GROUP_ID=$(id -g)

# Create necessary directories with correct permissions
mkdir -p config/openvpn/otp
mkdir -p config/openvpn/clients
mkdir -p data/openvpn

# Set ownership to current user
chown -R $USER_ID:$GROUP_ID config/openvpn
chown -R $USER_ID:$GROUP_ID data/openvpn

# Set correct permissions
chmod 700 config/openvpn
chmod 700 data/openvpn
chmod 600 config/openvpn/otp
chmod 600 config/openvpn/clients

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
sysctl -p /etc/sysctl.d/99-openvpn.conf

# Add current user to docker group if not already added
if ! groups $USER | grep -q docker; then
    usermod -aG docker $USER
    echo "Added user to docker group. Please log out and back in for changes to take effect."
fi

echo "Permissions set up complete. You can now run docker compose as a non-root user."
echo "Note: If you were added to the docker group, please log out and back in." 