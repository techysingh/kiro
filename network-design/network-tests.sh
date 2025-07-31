#!/bin/bash
set -e

# Test container definition
cat > test-compose.yaml <<EOF
version: '3.8'
services:
  tester:
    image: alpine
    command: tail -f /dev/null
    networks:
      - vpnnet
      - appnet2
      - appnet3
      - dbnet

networks:
  vpnnet:
    external: true
  appnet2:
    external: true
  appnet3:
    external: true
  dbnet:
    external: true
EOF

# Start test container
docker compose -f test-compose.yaml up -d
tester_id=$(docker compose -f test-compose.yaml ps -q tester)

# Test functions
test_network() {
  local network=$1
  local ip=$2
  local expect_internet=$3

  echo "Testing $network..."

  # Connect container to network
  docker network connect $network $tester_id

  # Test internet access
  if docker exec $tester_id ping -c 1 1.1.1.1 &>/dev/null; then
    if [ "$expect_internet" = false ]; then
      echo "FAIL: $network has unexpected internet access"
      exit 1
    fi
  else
    if [ "$expect_internet" = true ]; then
      echo "FAIL: $network missing expected internet access"
      exit 1
    fi
  fi

  # Test 192.0.0.0/8 blocking
  if docker exec $tester_id ping -c 1 192.0.0.1 &>/dev/null; then
    echo "FAIL: $network can reach 192.0.0.0/8"
    exit 1
  fi

  # Test intra-network communication for vpnnet
  if [ "$network" = "vpnnet" ]; then
    local container_ip=$(docker inspect -f "{{.NetworkSettings.Networks.$network.IPAddress}}" $tester_id)
    if docker exec $tester_id ping -c 1 $container_ip &>/dev/null; then
      echo "FAIL: vpnnet allows intra-network communication"
      exit 1
    fi
  fi

  echo "PASS: $network tests"
}

# Run tests
test_network vpnnet 172.16.0.2 true
test_network appnet2 172.17.0.2 true
test_network appnet3 172.16.0.2 false
test_network dbnet 172.18.0.2 false

# Clean up
docker compose -f test-compose.yaml down
echo "All network tests passed successfully"
