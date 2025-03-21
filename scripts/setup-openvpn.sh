#!/bin/bash

# Initialize OpenVPN and generate configs
docker-compose run --rm openvpn ovpn_genconfig -u udp://vpn.irvh.bawas.com
docker-compose run --rm openvpn ovpn_initpki

# Generate client certificates for users
users=("psingh" "hsingh" "ishpreet")

for user in "${users[@]}"; do
    # Generate client certificate
    docker-compose run --rm openvpn easyrsa build-client-full "$user" nopass
    
    # Generate client config with embedded certificates
    docker-compose run --rm openvpn ovpn_getclient "$user" > "./config/openvpn/${user}.ovpn"
    
    # Generate Google Authenticator secret for each user
    docker-compose run --rm openvpn google-authenticator --time-based --disallow-reuse --force --rate-limit=3 --rate-time=30 --window-size=3 -l "${user}@irvh.bawas.com" > "./config/openvpn/${user}.google_authenticator"
    
    # Modify client config to include Google Authenticator
    echo "auth-user-pass" >> "./config/openvpn/${user}.ovpn"
    echo "static-challenge \"Enter Google Authenticator Code\" 1" >> "./config/openvpn/${user}.ovpn"
done

# Configure OpenVPN to use Google Authenticator
cat << EOF > ./config/openvpn/auth-config
plugin /usr/lib/openvpn/plugins/openvpn-plugin-auth-pam.so openvpn
client-cert-not-required
username-as-common-name
reneg-sec 0
EOF

# Copy the auth config to the container
docker cp ./config/openvpn/auth-config openvpn:/etc/openvpn/

# Set proper permissions
chmod 755 ./config/openvpn
chmod 600 ./config/openvpn/*.google_authenticator 