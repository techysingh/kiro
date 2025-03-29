#!/bin/bash
# Rootless Docker verification script
# Checks and verifies an existing rootless Docker installation

set -euo pipefail

echo "=== Rootless Docker Verification ==="

# Check if Docker is already installed and rootless
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed"
    exit 1
fi

if ! docker info | grep -q "rootless"; then
    echo "Error: Docker is not running in rootless mode"
    exit 1
fi

echo "Docker rootless installation detected and verified"

echo -e "\n=== Verification Steps ==="
echo "Docker version:"
docker --version

echo -e "\nDocker rootless status:"
docker info | grep -i rootless

echo -e "\nTesting with hello-world:"
docker run --rm hello-world

echo -e "\n=== Verification Complete ==="
echo "Rootless Docker is working correctly"
