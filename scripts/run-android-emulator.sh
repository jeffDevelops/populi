#!/bin/bash

# Script to run a single instance of the Tauri app in an Android emulator
# Usage: ./run-android-emulator.sh --instance 1 --emulator "Pixel_7_API_34"
# Supports both named parameters and positional arguments for backward compatibility

# Default values
INSTANCE_ID=1
EMULATOR_NAME=""
CLEAN=true

# Parse named parameters
while [[ $# -gt 0 ]]; do
  case $1 in
    --instance|--InstanceId)
      INSTANCE_ID="$2"
      shift 2
      ;;
    --emulator|--EmulatorName)
      EMULATOR_NAME="$2"
      shift 2
      ;;
    --clean|--Clean)
      CLEAN="$2"
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
      elif [[ -z "$EMULATOR_SET" ]]; then
        EMULATOR_NAME="$1"
        EMULATOR_SET=true
      elif [[ -z "$CLEAN_SET" ]]; then
        CLEAN="$1"
        CLEAN_SET=true
      fi
      shift
      ;;
  esac
done

# Default emulator name if not specified
EMULATOR_NAME=${EMULATOR_NAME:-"Pixel_8_API_34"}

# Print initial status immediately
echo "Starting Tauri Android emulator instance $INSTANCE_ID with:"
echo "  - Emulator: $EMULATOR_NAME"
echo "  - Clean existing: $CLEAN"

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
  
  # Try lsof first (faster and more reliable on macOS/Linux)
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

echo "Starting Tauri Android emulator instance $INSTANCE_ID with:"
echo "  - Emulator: $EMULATOR_NAME"
echo "  - Server Port: $SERVER_PORT"
echo "  - HMR Port: $HMR_PORT"

# Get the host machine's IP address (cross-platform)
get_host_ip() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    # Try to get IP address that can be reached from Android emulators
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
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    # Try to get the default route interface IP
    local ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+')
    
    # Fallback to hostname -I
    if [ -z "$ip" ]; then
      ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
  elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    # Windows (WSL/MSYS/Cygwin)
    # Try to get IP from ipconfig
    local ip=$(ipconfig.exe | grep -A 1 "Wireless LAN adapter Wi-Fi" | grep "IPv4 Address" | awk -F': ' '{print $2}' | tr -d '\r')
    
    # Fallback to wsl hostname
    if [ -z "$ip" ]; then
      ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
  fi
  
  # If all else fails, use localhost (though this won't work from emulators)
  if [ -z "$ip" ]; then
    ip="127.0.0.1"
    echo "Warning: Could not determine host IP address. Using localhost, which won't work from emulators."
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

# Change to the apps/tauri directory
cd "$(dirname "$0")/../apps/tauri" || exit 1

# Create a completely separate project directory for this instance
PROJECT_DIR="/tmp/tauri-android-project-$INSTANCE_ID"
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

# Use rsync for efficient copying with exclusions
rsync -a --exclude="node_modules" --exclude="target" --exclude=".git" --exclude=".vite" --exclude="dist" --exclude="build" --exclude=".svelte-kit" . "$PROJECT_DIR/"
echo "$(date +"%T") - Project files copied successfully."

# Create a dynamic .env file for this instance
echo "$(date +"%T") - Creating dynamic .env file with host IP and ports..."

# First, check if a base .env file exists in the project root
BASE_ENV_FILE="$(dirname "$0")/.env.base"
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

# Create target directory symlink to share Cargo cache
echo "$(date +"%T") - Creating symlink for target directory to share Cargo cache..."
mkdir -p "$PROJECT_DIR/src-tauri"
ln -sf "$(pwd)/src-tauri/target" "$PROJECT_DIR/src-tauri/target"
echo "$(date +"%T") - Target directory symlink created."

# Create a custom vite.config.js for this instance
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

# Check if Android SDK is available
if ! command -v adb &> /dev/null; then
  echo "$(date +"%T") - Error: Android SDK (adb) is not installed or not in PATH."
  echo "Please install Android Studio and add the SDK tools to your PATH."
  exit 1
fi

if ! command -v emulator &> /dev/null; then
  echo "$(date +"%T") - Error: Android emulator command is not installed or not in PATH."
  echo "Please install Android Studio and add the emulator tools to your PATH."
  exit 1
fi

# Get list of available AVDs
echo "$(date +"%T") - Checking available Android Virtual Devices (AVDs)..."
AVAILABLE_AVDS=$(emulator -list-avds 2>/dev/null)

if [ -z "$AVAILABLE_AVDS" ]; then
  echo "$(date +"%T") - Error: No Android Virtual Devices (AVDs) found."
  echo "Please create AVDs using Android Studio's AVD Manager."
  exit 1
fi

echo "Available AVDs:"
echo "$AVAILABLE_AVDS"

# Check if the specified emulator exists
if ! echo "$AVAILABLE_AVDS" | grep -q "^$EMULATOR_NAME$"; then
  echo "$(date +"%T") - Warning: Specified emulator '$EMULATOR_NAME' not found."
  # Use the first available AVD as fallback
  EMULATOR_NAME=$(echo "$AVAILABLE_AVDS" | head -1)
  echo "$(date +"%T") - Using fallback emulator: $EMULATOR_NAME"
fi

# Function to check if emulator is running
check_emulator_running() {
  local emulator_name=$1
  adb devices | grep -q "emulator.*device"
  return $?
}

# Function to boot emulator with retries
boot_emulator_with_retry() {
  local emulator_name=$1
  local max_attempts=3
  local attempt=1
  
  while [ $attempt -le $max_attempts ]; do
    echo "$(date +"%T") - Boot attempt $attempt of $max_attempts for $emulator_name..."
    
    # Start emulator in background
    emulator -avd "$emulator_name" -no-snapshot-save -wipe-data &
    local emulator_pid=$!
    
    # Wait for emulator to boot (up to 2 minutes)
    local wait_time=0
    local max_wait=120
    
    while [ $wait_time -lt $max_wait ]; do
      if adb devices | grep -q "emulator.*device"; then
        echo "$(date +"%T") - Emulator $emulator_name successfully booted on attempt $attempt."
        return 0
      fi
      sleep 5
      wait_time=$((wait_time + 5))
      echo "$(date +"%T") - Waiting for emulator to boot... ($wait_time/$max_wait seconds)"
    done
    
    echo "$(date +"%T") - Emulator boot attempt $attempt timed out."
    kill $emulator_pid 2>/dev/null || true
    attempt=$((attempt + 1))
    sleep 10
  done
  
  echo "$(date +"%T") - Failed to boot emulator $emulator_name after $max_attempts attempts."
  return 1
}

# Always boot emulator (will connect to existing if already running)
echo "$(date +"%T") - Booting emulator $EMULATOR_NAME..."
boot_emulator_with_retry "$EMULATOR_NAME"
if [ $? -ne 0 ]; then
  echo "$(date +"%T") - Error: Failed to boot emulator after multiple attempts."
  exit 1
fi

echo "$(date +"%T") - Emulator is now booted and ready."

# Change to the isolated project directory
echo "$(date +"%T") - Changing to isolated project directory: $PROJECT_DIR"
cd "$PROJECT_DIR"
echo "$(date +"%T") - Current directory: $(pwd)"

# Display environment variables being used
echo "$(date +"%T") - Using the following environment variables:"
echo "  - VITE_INSTANCE_ID: $INSTANCE_ID"
echo "  - VITE_SERVER_PORT: $SERVER_PORT"
echo "  - VITE_HMR_PORT: $HMR_PORT"
echo "  - VITE_HOST_IP: $HOST_IP"
echo "  - VITE_SIGNALING_URL: ws://$HOST_IP:3000"
echo "  - VITE_TURN_SERVER: $HOST_IP:3478"

# Run the Tauri app on Android emulator
echo "$(date +"%T") - Deploying app to Android emulator: $EMULATOR_NAME"
echo "$(date +"%T") - This may take several minutes for the first run as it builds the app..."

# Use the tauri CLI to run directly on the emulator
echo "$(date +"%T") - Running app on emulator $EMULATOR_NAME using Tauri CLI..."

# Check if we have the original project's node_modules available
ORIGINAL_PROJECT_PATH="$(dirname "$0")/../apps/tauri"
if [ -f "$ORIGINAL_PROJECT_PATH/node_modules/.bin/tauri" ]; then
  echo "$(date +"%T") - Using Tauri CLI from original project"
  "$ORIGINAL_PROJECT_PATH/node_modules/.bin/tauri" android dev
else
  # Fallback to bun/npm commands
  if [ -f "bun.lockb" ]; then
    echo "$(date +"%T") - Using bun to run Tauri Android dev..."
    bun run tauri android dev
  elif [ -f "package-lock.json" ]; then
    echo "$(date +"%T") - Using npm to run Tauri Android dev..."
    npm run tauri android dev
  else
    echo "$(date +"%T") - Defaulting to bun to run Tauri Android dev..."
    bun run tauri android dev
  fi
fi
