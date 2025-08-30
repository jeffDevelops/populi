#!/bin/bash

# Script to launch multiple instances of the Tauri app in separate iOS simulators
# Usage: ./launch-multi-ios.sh [number_of_instances] [boot_simulators] [sequential] [start_services]
# If sequential is set to true, will run one instance at a time instead of in parallel
# If start_services is set to true, will start Docker Compose services before launching simulators

# Default to 2 instances if not specified
NUM_INSTANCES=${1:-2}

# Default to booting simulators, but allow skipping if already booted
BOOT_SIMULATORS=${2:-true}

# Default to parallel execution, but allow sequential if specified
SEQUENTIAL=${3:-false}

# Default to NOT starting Docker Compose services (so user can run them separately to see logs)
START_SERVICES=${4:-false}

# Set to true to preserve existing simulators (don't shut them down)
PRESERVE_EXISTING_SIMULATORS=true

# List of iOS simulator devices to use
# These are specific simulators that are available on your system
SIMULATORS=(
  "iPhone 15 Pro Max"
  "iPhone 15 Pro"
  "iPhone 15"
  "iPhone 16"
  "iPhone 16 Pro"
  "iPhone 16 Pro Max"
  "iPhone SE (3rd generation)"
  "iPad Pro (12.9-inch) (6th generation)"
  "iPad Air (5th generation)"
)

echo "Launching $NUM_INSTANCES Tauri iOS simulator instances in separate terminal windows..."

# Detect terminal application
if command -v osascript &> /dev/null; then
  # macOS with AppleScript support
  TERMINAL_APP="osascript"
  
  # Check if iTerm2 is installed
  if osascript -e 'tell application "System Events" to exists process "iTerm2"' &> /dev/null; then
    USE_ITERM=true
    echo "Using iTerm2 for terminal windows"
  else
    USE_ITERM=false
    echo "Using Terminal.app for terminal windows"
  fi
else
  echo "Error: This script requires macOS with AppleScript support."
  exit 1
fi

# Function to generate a unique title for each terminal window
get_window_title() {
  local instance_id=$1
  local simulator_name=$2
  echo "Tauri iOS Simulator #$instance_id ($simulator_name)"
}

# Function to launch a terminal window with the iOS simulator
launch_terminal_window() {
  local instance_id=$1
  local simulator_name=$2
  local title=$(get_window_title "$instance_id" "$simulator_name")
  local script_path="$(cd "$(dirname "$0")" && pwd)/run-ios-simulator.sh"
  
  if [ "$USE_ITERM" = true ]; then
    # Launch with iTerm2
    osascript <<EOF
tell application "iTerm"
  create window with default profile
  tell current window
    tell current session
      set name to "$title"
      write text "cd '$(pwd)' && '$script_path' $instance_id '$simulator_name' $BOOT_SIMULATORS"
    end tell
  end tell
end tell
EOF
  else
    # Launch with Terminal.app
    osascript <<EOF
tell application "Terminal"
  do script "cd '$(pwd)' && '$script_path' $instance_id '$simulator_name' $BOOT_SIMULATORS"
  tell window 1
    set custom title to "$title"
  end tell
end tell
EOF
  fi
}

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

# Main script execution starts here
echo "Starting $NUM_INSTANCES iOS simulator instances..."
echo "Boot simulators: $BOOT_SIMULATORS"
echo "Sequential mode: $SEQUENTIAL"
echo "Start services: $START_SERVICES"
echo "Host IP address: $HOST_IP"

# Start Docker Compose services if requested
if [ "$START_SERVICES" = true ]; then
  echo "Starting Docker Compose services (signaling server and CoTURN)..."
  
  # Check if docker-compose is installed
  if ! command -v docker-compose &> /dev/null; then
    echo "Error: docker-compose is not installed. Please install Docker Desktop or docker-compose."
    exit 1
  fi
  
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
EOF
  fi
  
  # Start Docker Compose services
  docker-compose up -d
  
  # Wait for services to start
  echo "Waiting for services to start..."
  sleep 5
fi

# First, build the app once to cache dependencies
echo "Building app once first to cache dependencies..."
cd "$(dirname "$0")/rift" || exit 1

# Clean Vite cache to prevent dependency errors
echo "Cleaning Vite cache to prevent dependency errors..."
if [ -d "node_modules/.vite" ]; then
  rm -rf node_modules/.vite
  echo "Vite cache cleaned."
fi

# Build the app
npm run tauri build -- --target aarch64-apple-ios-sim
cd - || exit 1
echo "Initial build completed. Now launching instances..."

# Function to check if simulator is booted
check_simulator_booted() {
  local udid=$1
  xcrun simctl list devices | grep "$udid" | grep -q "(Booted)"
  return $?
}

# Function to boot simulator with retries
boot_simulator_with_retry() {
  local udid=$1
  local name=$2
  local max_attempts=3
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    echo "Boot attempt $attempt of $max_attempts for $name..."
    xcrun simctl boot "$udid" 2>/dev/null || true
    
    # Wait a moment for boot to start
    sleep 5
    
    # Check if booted
    if check_simulator_booted "$udid"; then
      echo "Simulator $name successfully booted on attempt $attempt."
      return 0
    fi
    
    echo "Simulator not yet booted, retrying..."
    attempt=$((attempt + 1))
    sleep 5
  done
  
  echo "Failed to boot simulator $name after $max_attempts attempts."
  return 1
}

# If running in parallel mode, pre-boot all the simulators we'll need
if [ "$SEQUENTIAL" = false ] && [ "$BOOT_SIMULATORS" = true ]; then
  echo "Pre-booting all required simulators for parallel execution..."
  
  # First, check for any existing running simulators if we want to preserve them
  if [ "$PRESERVE_EXISTING_SIMULATORS" = true ]; then
    echo "Checking for existing running simulators to preserve them..."
    RUNNING_SIMULATORS=$(xcrun simctl list devices | grep "(Booted)" | sed -E 's/.*\(([A-Z0-9-]+)\).*/\1/')
    if [ -n "$RUNNING_SIMULATORS" ]; then
      echo "Found running simulators that will be preserved:"
      xcrun simctl list devices | grep "(Booted)"
    fi
  fi
  
  # Open Simulator.app first to ensure the simulator system is ready
  echo "Opening Simulator.app to initialize the simulator system..."
  open -a Simulator
  sleep 5
  
  # Create an array to store successfully booted simulators
  BOOTED_SIMULATOR_UDIDS=()
  BOOTED_SIMULATOR_NAMES=()
  
  # Try to boot each required simulator
  for i in $(seq 1 $NUM_INSTANCES); do
    simulator_index=$(( (i-1) % ${#SIMULATORS[@]} ))
    simulator_name="${SIMULATORS[$simulator_index]}"
    echo "Pre-booting simulator $i of $NUM_INSTANCES: $simulator_name"
    
    # Get the UDID and boot the simulator
    SIMULATOR_UDID=$(xcrun simctl list devices | grep "$simulator_name" | grep -v "unavailable" | head -1 | sed -E 's/.*\(([A-Z0-9-]+)\).*/\1/')
    if [ -n "$SIMULATOR_UDID" ]; then
      # Check if simulator is already booted
      if check_simulator_booted "$SIMULATOR_UDID"; then
        echo "Simulator $simulator_name is already booted."
        BOOTED_SIMULATOR_UDIDS+=($SIMULATOR_UDID)
        BOOTED_SIMULATOR_NAMES+=("$simulator_name")
      else
        echo "Booting simulator $simulator_name..."
        if boot_simulator_with_retry "$SIMULATOR_UDID" "$simulator_name"; then
          BOOTED_SIMULATOR_UDIDS+=($SIMULATOR_UDID)
          BOOTED_SIMULATOR_NAMES+=("$simulator_name")
        else
          echo "Warning: Failed to boot simulator $simulator_name. Will try to find an alternative."
          
          # Try to find another available simulator as fallback
          echo "Looking for another available simulator..."
          AVAILABLE_SIMULATOR_UDID=$(xcrun simctl list devices | grep -v "$SIMULATOR_UDID" | grep "iPhone" | grep -v "unavailable" | grep -v "(Shutdown)" | head -1 | sed -E 's/.*\(([A-Z0-9-]+)\).*/\1/')
          
          if [ -n "$AVAILABLE_SIMULATOR_UDID" ]; then
            ALT_SIMULATOR_NAME=$(xcrun simctl list devices | grep "$AVAILABLE_SIMULATOR_UDID" | sed -E 's/^[[:space:]]*([^[:space:]]+.*)[[:space:]]*\([A-Z0-9-]+\).*/\1/')
            echo "Found alternative simulator: $ALT_SIMULATOR_NAME"
            
            if boot_simulator_with_retry "$AVAILABLE_SIMULATOR_UDID" "$ALT_SIMULATOR_NAME"; then
              BOOTED_SIMULATOR_UDIDS+=($AVAILABLE_SIMULATOR_UDID)
              BOOTED_SIMULATOR_NAMES+=("$ALT_SIMULATOR_NAME")
            else
              echo "Warning: Failed to boot alternative simulator as well. Will continue with fewer instances."
            fi
          else
            echo "No alternative simulators available. Will continue with fewer instances."
          fi
        fi
      fi
    else
      echo "Warning: Could not find simulator with name '$simulator_name'. Will try to find an alternative."
      
      # Try to find another available simulator
      AVAILABLE_SIMULATOR_UDID=$(xcrun simctl list devices | grep "iPhone" | grep -v "unavailable" | head -1 | sed -E 's/.*\(([A-Z0-9-]+)\).*/\1/')
      if [ -n "$AVAILABLE_SIMULATOR_UDID" ]; then
        ALT_SIMULATOR_NAME=$(xcrun simctl list devices | grep "$AVAILABLE_SIMULATOR_UDID" | sed -E 's/^[[:space:]]*([^[:space:]]+.*)[[:space:]]*\([A-Z0-9-]+\).*/\1/')
        echo "Found alternative simulator: $ALT_SIMULATOR_NAME"
        
        if boot_simulator_with_retry "$AVAILABLE_SIMULATOR_UDID" "$ALT_SIMULATOR_NAME"; then
          BOOTED_SIMULATOR_UDIDS+=($AVAILABLE_SIMULATOR_UDID)
          BOOTED_SIMULATOR_NAMES+=("$ALT_SIMULATOR_NAME")
        fi
      fi
    fi
  done
  
  # Update NUM_INSTANCES based on how many simulators we actually managed to boot
  ACTUAL_BOOTED_COUNT=${#BOOTED_SIMULATOR_UDIDS[@]}
  if [ $ACTUAL_BOOTED_COUNT -lt $NUM_INSTANCES ]; then
    echo "Warning: Only managed to boot $ACTUAL_BOOTED_COUNT simulators out of requested $NUM_INSTANCES."
    NUM_INSTANCES=$ACTUAL_BOOTED_COUNT
  fi
  
  # Wait for all simulators to fully initialize
  echo "Waiting for all simulators to fully initialize..."
  sleep 15
  
  # Verify all simulators are still booted
  echo "Verifying all simulators are still booted:"
  for i in $(seq 0 $(($NUM_INSTANCES-1))); do
    if check_simulator_booted "${BOOTED_SIMULATOR_UDIDS[$i]}"; then
      echo "✅ ${BOOTED_SIMULATOR_NAMES[$i]} is booted and ready."
    else
      echo "❌ Warning: ${BOOTED_SIMULATOR_NAMES[$i]} is not showing as booted."
    fi
  done
fi

# Launch each instance with a different simulator
for i in $(seq 1 $NUM_INSTANCES); do
  if [ "$SEQUENTIAL" = true ]; then
    # For sequential mode, use the original simulator selection logic
    simulator_index=$(( (i-1) % ${#SIMULATORS[@]} ))
    simulator_name="${SIMULATORS[$simulator_index]}"
    
    echo "Launching instance $i with simulator: $simulator_name"
    echo "Running instance $i directly (sequential mode)..."
    "$(cd "$(dirname "$0")" && pwd)/run-ios-simulator.sh" "$i" "$simulator_name" "$BOOT_SIMULATORS"
    
    echo "Instance $i completed. Moving to next instance..."
  else
    # For parallel mode, use the pre-booted simulators if available
    if [ "$BOOT_SIMULATORS" = true ] && [ -n "${BOOTED_SIMULATOR_NAMES[$i-1]}" ]; then
      # Use the pre-booted simulator
      simulator_name="${BOOTED_SIMULATOR_NAMES[$i-1]}"
      echo "Launching instance $i with pre-booted simulator: $simulator_name"
    else
      # Fall back to the original selection logic
      simulator_index=$(( (i-1) % ${#SIMULATORS[@]} ))
      simulator_name="${SIMULATORS[$simulator_index]}"
      echo "Launching instance $i with simulator: $simulator_name"
    fi
    
    # Launch in a new terminal
    launch_terminal_window "$i" "$simulator_name"
    
    # Add a short delay between instances to prevent resource contention
    if [ "$BOOT_SIMULATORS" = true ]; then
      # Since we're pre-booting simulators now, we only need a short delay
      # for the Tauri/Vite processes to initialize
      echo "Waiting for 10 seconds before launching the next instance..."
      sleep 10
    else
      # Even shorter delay if simulators are already booted
      echo "Waiting for 5 seconds before launching the next instance..."
      sleep 5
    fi
  fi
done

echo "All $NUM_INSTANCES iOS simulator instances have been launched."
echo "Each window runs an independent Tauri iOS simulator."
echo "You can close individual windows to stop specific instances."
