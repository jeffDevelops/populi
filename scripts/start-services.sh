#!/bin/bash

# Script to start signaling and CoTURN services with visible logs
# Usage: ./start-services.sh

# Get the host machine's IP address (works on macOS)
get_host_ip() {
  # Try to get IP address that can be reached from iOS simulators
  # First try en0 (typically WiFi)
  local ip=$(ipconfig getifaddr en0 2>/dev/null)
  
  # If en0 failed, try en1 (typically Ethernet)
  if [ -z "$ip" ]; then
    ip=$(ipconfig getifaddr en1 2>/dev/null)
  fi
  
  # If both failed, try to get IP from route to 8.8.8.8 (Google DNS)
  if [ -z "$ip" ]; then
    ip=$(route -n get 8.8.8.8 2>/dev/null | grep 'interface' | awk '{print $2}' | xargs ipconfig getifaddr 2>/dev/null)
  fi
  
  # If all else fails, use localhost (though this won't work from simulators)
  if [ -z "$ip" ]; then
    ip="127.0.0.1"
    echo "Warning: Could not determine host IP address. Using localhost, which won't work from simulators."
  fi
  
  echo "$ip"
}

# Get the host IP address
HOST_IP=$(get_host_ip)
echo "Host IP address: $HOST_IP"

# Update turnserver.conf with the host IP if it exists
if [ -f "./turnserver.conf" ]; then
  echo "Updating turnserver.conf with host IP: $HOST_IP"
  sed -i.bak "s/^external-ip=.*/external-ip=$HOST_IP/" ./turnserver.conf
  sed -i.bak "s/^realm=.*/realm=$HOST_IP/" ./turnserver.conf
  rm -f ./turnserver.conf.bak
else
  echo "Creating turnserver.conf with host IP: $HOST_IP"
  cat > ./turnserver.conf << EOF
listening-port=3478
external-ip=$HOST_IP
realm=$HOST_IP
user=riftuser:riftpass
min-port=49152
max-port=65535
verbose
no-loopback-peers
EOF
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
  echo "Error: docker-compose is not installed. Please install Docker Desktop or docker-compose."
  exit 1
fi

# Change to the directory containing docker-compose.yml
echo "Changing to project root directory..."
cd "$(dirname "$0")/.." || exit 1

# Start all services with Docker Compose
echo "Starting all services with Docker Compose..."
echo "To run the iOS simulators, open another terminal and run:"
echo "  ./launch-multi-ios.sh [num_instances] [boot_simulators] [sequential] false"
echo ""
echo "Starting services in 3 seconds..."
sleep 3

# Option to run in background or foreground
if [ "$1" == "-d" ] || [ "$1" == "--detach" ]; then
  echo "Starting services in detached mode..."
  docker-compose up -d
  echo "Services started in the background."
  echo "To view logs: docker-compose logs -f"
  echo "To stop services: docker-compose down"
else
  echo "Starting services in foreground mode..."
  echo "Press Ctrl+C to stop all services."
  docker-compose up
fi
