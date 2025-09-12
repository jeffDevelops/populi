#!/bin/bash

# Script to run a Tauri app on an iOS simulator with dynamic port configuration
# Usage: ./run-ios-simulator.sh --instance 1 --simulator "iPhone 15" --boot true
# Supports both named parameters and positional arguments for backward compatibility

# Enable verbose output
set -x

# Default values
INSTANCE_ID=1
SIMULATOR_NAME=""
BOOT_SIMULATOR=true

# Parse named parameters
while [[ $# -gt 0 ]]; do
  case $1 in
    --instance|--InstanceId)
      INSTANCE_ID="$2"
      shift 2
      ;;
    --simulator|--SimulatorName)
      SIMULATOR_NAME="$2"
      shift 2
      ;;
    --boot|--BootSimulator)
      BOOT_SIMULATOR="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      # Handle positional arguments for backward compatibility
      if [[ -z "$INSTANCE_SET" ]]; then
        INSTANCE_ID="$1"
        INSTANCE_SET=true
      elif [[ -z "$SIMULATOR_SET" ]]; then
        SIMULATOR_NAME="$1"
        SIMULATOR_SET=true
      elif [[ -z "$BOOT_SET" ]]; then
        BOOT_SIMULATOR="$1"
        BOOT_SET=true
      fi
      shift
      ;;
  esac
done

# Print initial status immediately
echo "Starting Tauri iOS simulator instance $INSTANCE_ID with:"
echo "  - Simulator: $SIMULATOR_NAME"
echo "  - Boot Simulator: $BOOT_SIMULATOR"

# Use higher base ports to avoid common conflicts
BASE_SERVER_PORT=5000
BASE_HMR_PORT=6000

# Calculate ports for this instance with wider spacing
SERVER_PORT=$((BASE_SERVER_PORT + (INSTANCE_ID-1)*20))
HMR_PORT=$((BASE_HMR_PORT + (INSTANCE_ID-1)*20))

# Function to check if a port is available
is_port_available() {
  local port=$1
  local timeout=1  # Set a short timeout (1 second)
  
  echo "$(date +"%T") - Checking if port $port is available..."
  
  # Try lsof first (faster and more reliable)
  if command -v lsof &> /dev/null; then
    lsof -i:$port -sTCP:LISTEN -t &> /dev/null
    if [ $? -eq 0 ]; then
      echo "$(date +"%T") - Port $port is in use (lsof)"
      return 1  # Port is in use
    else
      echo "$(date +"%T") - Port $port is available (lsof)"
      return 0  # Port is available
    fi
  # Try netstat next
  elif command -v netstat &> /dev/null; then
    netstat -an | grep LISTEN | grep -q ":$port "
    if [ $? -eq 0 ]; then
      echo "$(date +"%T") - Port $port is in use (netstat)"
      return 1  # Port is in use
    else
      echo "$(date +"%T") - Port $port is available (netstat)"
      return 0  # Port is available
    fi
  # Use nc with timeout as last resort
  elif command -v nc &> /dev/null; then
    # Try with timeout if available
    if command -v timeout &> /dev/null; then
      timeout $timeout nc -z localhost $port &> /dev/null
    elif command -v gtimeout &> /dev/null; then
      gtimeout $timeout nc -z localhost $port &> /dev/null
    else
      # Use built-in bash timeout with background process
      ( nc -z -w $timeout localhost $port ) &> /dev/null & 
      local nc_pid=$!
      # Wait for a short time then kill if still running
      ( sleep $timeout && kill -9 $nc_pid &> /dev/null ) &
      wait $nc_pid &> /dev/null
    fi
    
    if [ $? -eq 0 ]; then
      echo "$(date +"%T") - Port $port is in use (nc)"
      return 1  # Port is in use
    else
      echo "$(date +"%T") - Port $port is available (nc)"
      return 0  # Port is available
    fi
  else
    # Fallback with minimal timeout using /dev/tcp
    ( bash -c "echo > /dev/tcp/localhost/$port" ) & 
    local tcp_pid=$!
    sleep $timeout
    kill -9 $tcp_pid &> /dev/null
    
    if [ $? -eq 0 ]; then
      echo "$(date +"%T") - Port $port is in use (tcp)"
      return 1  # Port is in use
    else
      echo "$(date +"%T") - Port $port is available (tcp)"
      return 0  # Port is available
    fi
  fi
}

# Pre-check if our signaling server is using port 3000
if [ $SERVER_PORT -eq 3000 ]; then
  echo "$(date +"%T") - Port 3000 is reserved for signaling server, skipping"
  SERVER_PORT=3010
fi

# Find available server port with timeout and max attempts
MAX_ATTEMPTS=5
ATTEMPTS=0
echo "$(date +"%T") - Finding available server port starting from $SERVER_PORT..."
while ! is_port_available $SERVER_PORT && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  ATTEMPTS=$((ATTEMPTS + 1))
  echo "$(date +"%T") - Attempt $ATTEMPTS: Port $SERVER_PORT is in use, trying next port"
  SERVER_PORT=$((SERVER_PORT + 2))
done

# Find available HMR port with timeout and max attempts
ATTEMPTS=0
echo "$(date +"%T") - Finding available HMR port starting from $HMR_PORT..."
while ! is_port_available $HMR_PORT && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  ATTEMPTS=$((ATTEMPTS + 1))
  echo "$(date +"%T") - Attempt $ATTEMPTS: Port $HMR_PORT is in use, trying next port"
  HMR_PORT=$((HMR_PORT + 2))
done

echo "$(date +"%T") - Using ports: SERVER=$SERVER_PORT, HMR=$HMR_PORT"

echo "Starting Tauri iOS simulator instance $INSTANCE_ID with:"
echo "  - Simulator: $SIMULATOR_NAME"
echo "  - Server Port: $SERVER_PORT"
echo "  - HMR Port: $HMR_PORT"

# Path to the Tauri config file
TAURI_CONFIG_PATH="$(dirname "$0")/rift/src-tauri/tauri.conf.json"
TAURI_CONFIG_BACKUP="${TAURI_CONFIG_PATH}.backup-ios-${INSTANCE_ID}"

# Create a backup of the original config if it doesn't exist
if [ ! -f "$TAURI_CONFIG_BACKUP" ]; then
  echo "Creating backup of original Tauri config at $TAURI_CONFIG_BACKUP"
  cp "$TAURI_CONFIG_PATH" "$TAURI_CONFIG_BACKUP"
fi

# Update the Tauri config with the correct port
echo "Updating Tauri config with devUrl: http://localhost:$SERVER_PORT"
sed -i.tmp "s|\"devUrl\": \"http://localhost:[0-9]*\"|\"devUrl\": \"http://localhost:$SERVER_PORT\"|g" "$TAURI_CONFIG_PATH"
rm "${TAURI_CONFIG_PATH}.tmp"

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
echo "$(date +"%T") - Host IP address: $HOST_IP"

# Export environment variables for Vite
export VITE_INSTANCE_ID=$INSTANCE_ID
export VITE_SERVER_PORT=$SERVER_PORT
export VITE_HMR_PORT=$HMR_PORT
export VITE_HOST_IP=$HOST_IP
export VITE_SIGNALING_URL="ws://$HOST_IP:3000"
export VITE_TURN_SERVER="$HOST_IP:3478"

# Change to the rift directory
cd "$(dirname "$0")/rift" || exit 1

# Create a completely separate project directory for this instance
PROJECT_DIR="/tmp/tauri-ios-project-$INSTANCE_ID"
echo "$(date +"%T") - Creating separate project directory for instance $INSTANCE_ID at $PROJECT_DIR"

# Remove any existing directory but handle potential Vite dependency errors
if [ -d "$PROJECT_DIR" ]; then
  echo "$(date +"%T") - Cleaning existing project directory..."
  # First remove the .vite directory if it exists to prevent dependency errors
  if [ -d "$PROJECT_DIR/node_modules/.vite" ]; then
    echo "$(date +"%T") - Removing .vite directory to prevent dependency errors..."
    rm -rf "$PROJECT_DIR/node_modules/.vite"
  fi
  # Then remove the entire directory
  echo "$(date +"%T") - Removing old project directory..."
  rm -rf "$PROJECT_DIR"
fi

# Create the project directory
echo "$(date +"%T") - Creating fresh project directory..."
mkdir -p "$PROJECT_DIR"

# Copy the entire project to the temporary location
echo "$(date +"%T") - Copying project files to temporary location..."
echo "$(date +"%T") - This may take a minute, please wait..."

# Use a faster copy method with fewer files and less verbose output
rsync -a --exclude="node_modules" --exclude="target" --exclude=".git" --exclude=".vite" --exclude="dist" --exclude="build" . "$PROJECT_DIR/"
echo "$(date +"%T") - Project files copied successfully."

# Create a dynamic .env file for this instance
echo "$(date +"%T") - Creating dynamic .env file with host IP and ports..."

# First, check if a base .env file exists in the project root
BASE_ENV_FILE="$(dirname "$0")/rift/.env.base"
if [ -f "$BASE_ENV_FILE" ]; then
  echo "$(date +"%T") - Found base .env file, using it as a template"
  # Copy the base .env file first
  cp "$BASE_ENV_FILE" "$PROJECT_DIR/.env"
  
  # Then append the dynamic variables
  cat >> "$PROJECT_DIR/.env" << EOF

# Dynamically generated variables for instance $INSTANCE_ID
VITE_INSTANCE_ID=$INSTANCE_ID
VITE_SERVER_PORT=$SERVER_PORT
VITE_HMR_PORT=$HMR_PORT
VITE_HOST_IP=$HOST_IP
VITE_SIGNALING_URL=ws://$HOST_IP:3000
VITE_TURN_SERVER=$HOST_IP:3478
VITE_TURN_USERNAME=riftuser
VITE_TURN_CREDENTIAL=riftpass
EOF
else
  # No base .env file found, create a new one with just the dynamic variables
  cat > "$PROJECT_DIR/.env" << EOF
# Dynamically generated .env file for instance $INSTANCE_ID
VITE_INSTANCE_ID=$INSTANCE_ID
VITE_SERVER_PORT=$SERVER_PORT
VITE_HMR_PORT=$HMR_PORT
VITE_HOST_IP=$HOST_IP
VITE_SIGNALING_URL=ws://$HOST_IP:3000
VITE_TURN_SERVER=$HOST_IP:3478
VITE_TURN_USERNAME=riftuser
VITE_TURN_CREDENTIAL=riftpass
EOF
fi

echo "$(date +"%T") - .env file created successfully."

# Create node_modules symlink to save space and time
echo "$(date +"%T") - Creating symlink for node_modules..."
ln -s "$(pwd)/node_modules" "$PROJECT_DIR/node_modules"
echo "$(date +"%T") - node_modules symlink created."

# Create target directory and symlink to the original target directory to share build cache
echo "$(date +"%T") - Creating symlink for target directory to share Cargo cache..."
mkdir -p "$PROJECT_DIR/src-tauri/target"
ln -sf "$(pwd)/src-tauri/target" "$PROJECT_DIR/src-tauri/target"
echo "$(date +"%T") - Target directory symlink created."

# Ensure we have network connectivity before proceeding
echo "Checking network connectivity..."
if ! ping -c 1 github.com &> /dev/null; then
  echo "Warning: Cannot reach github.com. Build may fail if dependencies need to be downloaded."
  echo "Checking if we have a local cache that might help..."
  if [ -d "$(pwd)/src-tauri/target" ]; then
    echo "Found local target directory, will try to use cached dependencies."
  else
    echo "No local cache found. Build will likely fail without network connectivity."
  fi
else
  echo "Network connectivity to GitHub confirmed."
fi

# Create a custom vite.config.js for this instance to fix allow list issues
echo "$(date +"%T") - Creating custom Vite config for this instance..."
cat > "$PROJECT_DIR/vite.config.js" << 'EOF'
import { defineConfig } from "vite";
import { sveltekit } from "@sveltejs/kit/vite";

const host = process.env.TAURI_DEV_HOST;

// Get port configuration from environment variables or use defaults
const serverPort = parseInt(process.env.VITE_SERVER_PORT || "1420", 10);
const hmrPort = parseInt(process.env.VITE_HMR_PORT || "1421", 10);
const instanceId = process.env.VITE_INSTANCE_ID || "1";

console.log(
  `Starting Vite instance ${instanceId} on server port: ${serverPort}, HMR port: ${hmrPort}`
);

// https://vite.dev/config/
export default defineConfig(async () => ({
  plugins: [sveltekit()],

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent Vite from obscuring rust errors
  clearScreen: false,
  // 2. configure port dynamically based on environment variables
  server: {
    port: serverPort,
    strictPort: true,
    host: host || false,
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: hmrPort,
        }
      : {
          port: hmrPort,
        },
    watch: {
      // 3. tell Vite to ignore watching `src-tauri`
      ignored: ["**/src-tauri/**"],
    },
    fs: {
      // Allow serving files from one level up (the project root) and from the original node_modules
      allow: [
        "PROJECT_DIR_PLACEHOLDER",
        "PROJECT_DIR_PLACEHOLDER/..",
        "PROJECT_DIR_PLACEHOLDER/src",
        "PROJECT_DIR_PLACEHOLDER/src/lib",
        "PROJECT_DIR_PLACEHOLDER/src/routes",
        "PROJECT_DIR_PLACEHOLDER/.svelte-kit",
        "PROJECT_DIR_PLACEHOLDER/node_modules",
        "ORIGINAL_DIR_PLACEHOLDER/node_modules",
        "ORIGINAL_DIR_PLACEHOLDER"
      ],
    },
  },
}));
EOF

# Replace placeholders with actual paths
echo "$(date +"%T") - Updating Vite config with correct paths..."
sed -i.tmp "s|PROJECT_DIR_PLACEHOLDER|$PROJECT_DIR|g" "$PROJECT_DIR/vite.config.js"
sed -i.tmp "s|ORIGINAL_DIR_PLACEHOLDER|$(pwd)|g" "$PROJECT_DIR/vite.config.js"
rm "${PROJECT_DIR}/vite.config.js.tmp"
echo "$(date +"%T") - Vite config updated successfully."

# Update the config in the temporary location
INSTANCE_CONFIG_PATH="$PROJECT_DIR/src-tauri/tauri.conf.json"
echo "$(date +"%T") - Updating Tauri config with devUrl: http://localhost:$SERVER_PORT in $INSTANCE_CONFIG_PATH"
sed -i.tmp "s|\"devUrl\": \"http://localhost:[0-9]*\"|\"devUrl\": \"http://localhost:$SERVER_PORT\"|g" "$INSTANCE_CONFIG_PATH"
rm "${INSTANCE_CONFIG_PATH}.tmp"
echo "$(date +"%T") - Tauri config updated successfully."

# Trap to clean up when the script exits
trap 'echo "Cleaning up temporary files"; rm -rf "$PROJECT_DIR"; echo "Cleanup complete"; exit' INT TERM EXIT

# Get a list of available simulators that match our name
echo "Finding iOS simulators matching: $SIMULATOR_NAME"

# First, make sure we're only looking at iOS simulators, not physical devices
echo "$(date +"%T") - Listing all available iOS simulators..."

# Cache the simulator list to avoid multiple slow calls to xcrun
SIMULATOR_LIST=$(xcrun simctl list devices)

# Get the UDID of the simulator
echo "$(date +"%T") - Finding simulator UDID for $SIMULATOR_NAME..."
SIMULATOR_UDID=$(echo "$SIMULATOR_LIST" | grep "$SIMULATOR_NAME" | grep -v "unavailable" | head -1 | sed -E 's/.*\(([A-Z0-9-]+)\).*/\1/')

if [ -z "$SIMULATOR_UDID" ]; then
  echo "$(date +"%T") - Error: Could not find simulator with name $SIMULATOR_NAME"
  echo "Available simulators:"
  echo "$SIMULATOR_LIST" | grep -v "unavailable" | grep -v "^--" | grep -v "^$"
  exit 1
fi

echo "$(date +"%T") - Found simulator UDID: $SIMULATOR_UDID"

# Get the full name of the simulator (including iOS version)
SIMULATOR_FULL_NAME=$(echo "$SIMULATOR_LIST" | grep "$SIMULATOR_UDID" | sed -E 's/^[[:space:]]*([^[:space:]]+.*)[[:space:]]*\([A-Z0-9-]+\).*/\1/')
echo "$(date +"%T") - Full simulator name: $SIMULATOR_FULL_NAME"

# No need for fallback if we already found the simulator
echo "$(date +"%T") - Found simulator: $SIMULATOR_FULL_NAME with UDID: $SIMULATOR_UDID"

# Don't shut down other simulators, just make sure our target simulator is booted
echo "Ensuring target simulator is booted without affecting other simulators..."

# List currently running simulators for reference
echo "Currently running simulators (these will be preserved):"
xcrun simctl list devices | grep "(Booted)"

# Boot the selected simulator with improved verification and retry logic
echo "Booting simulator $SIMULATOR_FULL_NAME..."

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
  local max_attempts=5
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

# Only boot simulator if BOOT_SIMULATOR is true
if [ "$BOOT_SIMULATOR" = true ]; then
  echo "$(date +"%T") - BOOT_SIMULATOR is true, proceeding with simulator boot..."
  
  # Open the Simulator.app first to ensure the simulator system is ready
  echo "$(date +"%T") - Opening Simulator.app..."
  open -a Simulator
  sleep 5

  # Boot the simulator with retry logic
  echo "$(date +"%T") - Booting simulator $SIMULATOR_FULL_NAME..."
  boot_simulator_with_retry "$SIMULATOR_UDID" "$SIMULATOR_FULL_NAME"
  if [ $? -ne 0 ]; then
    echo "$(date +"%T") - Error: Failed to boot simulator after multiple attempts."
    echo "Current simulator states:"
    xcrun simctl list devices | grep -v "^--" | grep -v "^$"
    
    # Try to find another available simulator as fallback
    echo "$(date +"%T") - Looking for another available simulator..."
    AVAILABLE_SIMULATOR_UDID=$(xcrun simctl list devices | grep -v "$SIMULATOR_UDID" | grep "iPhone" | grep -v "unavailable" | grep -v "(Shutdown)" | head -1 | sed -E 's/.*\(([A-Z0-9-]+)\).*/\1/')
    
    if [ -n "$AVAILABLE_SIMULATOR_UDID" ]; then
      SIMULATOR_FULL_NAME=$(xcrun simctl list devices | grep "$AVAILABLE_SIMULATOR_UDID" | sed -E 's/^[[:space:]]*([^[:space:]]+.*)[[:space:]]*\([A-Z0-9-]+\).*/\1/')
      SIMULATOR_UDID=$AVAILABLE_SIMULATOR_UDID
      echo "$(date +"%T") - Switching to alternative simulator: $SIMULATOR_FULL_NAME"
      boot_simulator_with_retry "$SIMULATOR_UDID" "$SIMULATOR_FULL_NAME"
      if [ $? -ne 0 ]; then
        echo "$(date +"%T") - Error: Failed to boot alternative simulator as well."
        exit 1
      fi
    else
      echo "$(date +"%T") - No alternative simulators available."
      exit 1
    fi
  fi

  # Double-check that the simulator is definitely booted
  if ! check_simulator_booted "$SIMULATOR_UDID"; then
    echo "$(date +"%T") - Error: Simulator still not in booted state despite boot attempts."
    exit 1
  fi

  # Wait a bit longer to ensure the simulator is fully initialized
  echo "$(date +"%T") - Simulator is booted. Waiting for it to fully initialize..."
  sleep 15

  echo "$(date +"%T") - Simulator is now booted and ready."
else
  echo "$(date +"%T") - BOOT_SIMULATOR is false, skipping simulator boot process."
  echo "$(date +"%T") - Using existing simulator: $SIMULATOR_FULL_NAME"
fi

# Run the Tauri app on iOS simulator
echo "Deploying app to iOS simulator: $SIMULATOR_FULL_NAME"

# Store the original directory path
ORIGINAL_DIR=$(pwd)

# Change to the temporary project directory
echo "$(date +"%T") - Changing to temporary project directory: $PROJECT_DIR"
cd "$PROJECT_DIR"
echo "$(date +"%T") - Current directory: $(pwd)"

# Use the correct syntax for running on iOS simulator
echo "Running tauri for simulator: $SIMULATOR_FULL_NAME"

# Ensure the simulator is definitely booted and ready for app installation
echo "Ensuring simulator is ready for app installation..."
if ! xcrun simctl list devices | grep "$SIMULATOR_UDID" | grep -q "(Booted)"; then
  echo "Warning: Simulator not showing as booted. Attempting to boot again..."
  xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
  sleep 10
  
  # Final verification
  if ! xcrun simctl list devices | grep "$SIMULATOR_UDID" | grep -q "(Booted)"; then
    echo "Error: Simulator still not booted. Cannot proceed with app installation."
    exit 1
  fi
fi

# Verify simulator is responsive by running a simple command
echo "Verifying simulator is responsive..."
xcrun simctl list apps "$SIMULATOR_UDID" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Warning: Simulator may not be fully responsive yet. Waiting longer..."
  sleep 15
fi

# Don't shut down other simulators - allow multiple simulators to run in parallel
echo "Ensuring simulator $SIMULATOR_FULL_NAME is booted without affecting other simulators..."

# Check all running simulators again to confirm we're preserving them
echo "Verifying all running simulators (should include our target and any pre-existing ones):"
xcrun simctl list devices | grep "(Booted)"

# Make sure the simulator is ready and selected in Xcode
echo "$(date +"%T") - Setting simulator as the default destination in Xcode..."
xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true

# Display environment variables being used
echo "$(date +"%T") - Using the following environment variables:"
echo "  - VITE_INSTANCE_ID: $INSTANCE_ID"
echo "  - VITE_SERVER_PORT: $SERVER_PORT"
echo "  - VITE_HMR_PORT: $HMR_PORT"
echo "  - VITE_HOST_IP: $HOST_IP"
echo "  - VITE_SIGNALING_URL: ws://$HOST_IP:3000"
echo "  - VITE_TURN_SERVER: $HOST_IP:3478"

# Use the tauri CLI to run directly on the simulator
echo "$(date +"%T") - Running app on simulator $SIMULATOR_FULL_NAME using Tauri CLI..."
echo "$(date +"%T") - This may take several minutes for the first run as it builds the app..."

# First try with the simulator name (which is the recommended approach for Tauri CLI)
echo "$(date +"%T") - Attempting to run with simulator name: $SIMULATOR_FULL_NAME"
echo "$(date +"%T") - Running: $ORIGINAL_DIR/node_modules/.bin/tauri ios dev $SIMULATOR_FULL_NAME"
"$ORIGINAL_DIR/node_modules/.bin/tauri" ios dev "$SIMULATOR_FULL_NAME" || {
  echo "Failed to run with simulator name. Checking available simulators..."
  
  # List available simulators for debugging
  echo "Available simulators:"
  xcrun simctl list devices | grep -v "unavailable" | grep -v "^--" | grep -v "^$"
  
  # Try to find a definitely booted simulator
  BOOTED_SIMULATOR_INFO=$(xcrun simctl list devices | grep "(Booted)" | head -1)
  BOOTED_SIMULATOR_NAME=$(echo "$BOOTED_SIMULATOR_INFO" | sed -E 's/^[[:space:]]*([^[:space:]]+.*)[[:space:]]*\([A-Z0-9-]+\).*/\1/')
  
  if [ -n "$BOOTED_SIMULATOR_NAME" ]; then
    echo "Found a definitely booted simulator: $BOOTED_SIMULATOR_NAME, trying to use it..."
    "$ORIGINAL_DIR/node_modules/.bin/tauri" ios dev "$BOOTED_SIMULATOR_NAME" || {
      echo "Failed with booted simulator too, falling back to any available simulator..."
      "$ORIGINAL_DIR/node_modules/.bin/tauri" ios dev
    }
  else
    echo "No booted simulators found, falling back to any available simulator..."
    "$ORIGINAL_DIR/node_modules/.bin/tauri" ios dev
  fi
}
