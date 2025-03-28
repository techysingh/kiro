#!/bin/bash

# Default values
KEY_SIZE=4096
KEY_TYPE="rsa"
KEY_NAME="id_rsa"
KEY_DIR="$HOME/.ssh"
KEY_COMMENT="$(whoami)@$(hostname)"

# Create .ssh directory if it doesn't exist
mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

# Generate the key pair
echo "Generating RSA key pair..."
ssh-keygen -t $KEY_TYPE \
    -b $KEY_SIZE \
    -f "$KEY_DIR/$KEY_NAME" \
    -C "$KEY_COMMENT" \
    -N "" \
    -o -a 100

# Set correct permissions
chmod 600 "$KEY_DIR/$KEY_NAME"
chmod 644 "$KEY_DIR/$KEY_NAME.pub"

# Display the public key
echo -e "\nPublic key (to be added to remote server):"
cat "$KEY_DIR/$KEY_NAME.pub"

echo -e "\nPrivate key location: $KEY_DIR/$KEY_NAME"
echo -e "Public key location: $KEY_DIR/$KEY_NAME.pub"
echo -e "\nTo use this key for remote login:"
echo "1. Copy the public key to the remote server's authorized_keys file:"
echo "   ssh-copy-id -i $KEY_DIR/$KEY_NAME.pub user@remote-server"
echo "2. Or manually add the public key to ~/.ssh/authorized_keys on the remote server" 