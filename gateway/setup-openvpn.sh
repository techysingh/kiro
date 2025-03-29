#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Check if docker compose is available
if ! docker compose version &> /dev/null; then
    echo "docker compose is not available. Please install Docker with compose support."
    exit 1
fi

# Install required packages
echo "Installing required packages..."
apt-get update
apt-get install -y openvpn libpam-google-authenticator

# Create necessary directories
echo "Creating necessary directories..."
mkdir -p config/openvpn/otp
mkdir -p config/openvpn/clients

# Initialize OpenVPN
echo "Starting OpenVPN container..."
docker compose up -d openvpn

# Wait for OpenVPN to be ready
echo "Waiting for OpenVPN Access Server to initialize..."
sleep 60

# Check if OpenVPN container is running
if ! docker compose ps openvpn | grep -q "Up"; then
    echo "Error: OpenVPN container failed to start"
    docker compose logs openvpn
    exit 1
fi

# Wait for the OpenVPN Access Server to be fully initialized
echo "Waiting for OpenVPN Access Server to be fully initialized..."
while ! docker compose exec openvpn /usr/local/openvpn_as/scripts/sacli --user admin --new_pass "admin" UserPropPut &>/dev/null; do
    echo "Waiting for OpenVPN Access Server to be ready..."
    sleep 10
done

# Create users and generate Google Authenticator secrets
for user in psingh hsingh ishpreet; do
    echo "Setting up user: $user"
    
    # Generate Google Authenticator secret
    google-authenticator -t -d -f -r -R -w 3 -q -Q UTF8 -i "OpenVPN-$user"
    
    # Store the secret
    cat /root/.google_authenticator > config/openvpn/otp/$user.secret
    
    # Create user in OpenVPN Access Server
    docker compose exec openvpn /usr/local/openvpn_as/scripts/sacli --user $user --new_pass "temporary_password" UserPropPut
    docker compose exec openvpn /usr/local/openvpn_as/scripts/sacli --user $user --value "true" UserPropPut --prop_2fa_enabled
    
    # Generate client config
    docker compose exec openvpn /usr/local/openvpn_as/scripts/sacli --user $user GetUserlogin > config/openvpn/clients/$user.ovpn
    
    echo "User $user setup complete"
done

# Configure PAM for Google Authenticator
echo "Configuring PAM for Google Authenticator..."
cat > /etc/pam.d/openvpn << EOF
auth required pam_google_authenticator.so secret=/config/openvpn/otp/\${PAM_USER}.secret
account required pam_permit.so
password required pam_permit.so
session required pam_permit.so
EOF

echo "OpenVPN Access Server setup with Google Authenticator 2FA is complete!"
echo "Please distribute the .ovpn files to the respective users."
echo "Users will need to scan the QR code with Google Authenticator app."
echo "Access the OpenVPN Access Server web interface at https://192.168.0.178:1943"
echo "Default credentials: admin / admin"
echo "Please change the admin password after first login!" 