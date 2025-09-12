#!/bin/bash

# Script to launch a swarm of Android emulator instances of the Tauri app in separate Android emulators
# Usage: ./launch-swarm-android.sh [instances] [boot_emulators] [sequential] [start_services] true
# Supports both named parameters and positional arguments for backward compatibility

# Default values
NUM_INSTANCES=2
CLEAN=true
SEQUENTIAL=false
START_SERVICES=false

# Parse named parameters
while [[ $# -gt 0 ]]; do
  case $1 in
    --instances|--NumberOfInstances)
      NUM_INSTANCES="$2"
      shift 2
      ;;
    --clean|--Clean)
      CLEAN="$2"
      shift 2
      ;;
    --sequential|--Sequential)
      SEQUENTIAL="$2"
      shift 2
      ;;
    --services|--StartServices)
      START_SERVICES="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      # Handle positional arguments for backward compatibility
      if [[ -z "$INSTANCES_SET" ]]; then
        NUM_INSTANCES="$1"
        INSTANCES_SET=true
      elif [[ -z "$CLEAN_SET" ]]; then
        CLEAN="$1"
        CLEAN_SET=true
      elif [[ -z "$SEQUENTIAL_SET" ]]; then
        SEQUENTIAL="$1"
        SEQUENTIAL_SET=true
      elif [[ -z "$SERVICES_SET" ]]; then
        START_SERVICES="$1"
        SERVICES_SET=true
      fi
      shift
      ;;
  esac
done

# Set to true to preserve existing emulators (don't shut them down)
PRESERVE_EXISTING_EMULATORS=true

# List of Android emulator devices to use
# These are predefined Android Virtual Devices (AVDs) that should be available
EMULATORS=(
  "Pixel_8_API_34"
  "Pixel_8_Pro_API_34"
  "Pixel_7_API_34"
  "Pixel_7_Pro_API_34"
  "Pixel_6_API_34"
  "Pixel_6_Pro_API_34"
  "Pixel_5_API_34"
  "Pixel_4_API_34"
  "Pixel_3a_API_34"
)

echo "Launching $NUM_INSTANCES Tauri Android emulator instances in separate terminal windows..."

# Detect terminal application and OS
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  if command -v osascript &> /dev/null; then
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
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux
  if command -v gnome-terminal &> /dev/null; then
    TERMINAL_APP="gnome-terminal"
    echo "Using gnome-terminal for terminal windows"
  elif command -v xterm &> /dev/null; then
    TERMINAL_APP="xterm"
    echo "Using xterm for terminal windows"
  else
    echo "Error: No supported terminal application found. Please install gnome-terminal or xterm."
    exit 1
  fi
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
  # Windows (WSL/MSYS/Cygwin)
  TERMINAL_APP="wsl"
  echo "Using Windows Terminal/WSL for terminal windows"
else
  echo "Error: Unsupported operating system: $OSTYPE"
  exit 1
fi

# Function to generate a unique title for each terminal window
get_window_title() {
  local instance_id=$1
  local emulator_name=$2
  echo "Tauri Android Emulator #$instance_id ($emulator_name)"
}

# Function to launch a terminal window with the Android emulator
launch_terminal_window() {
  local instance_id=$1
  local emulator_name=$2
  local title=$(get_window_title "$instance_id" "$emulator_name")
  local script_path="$(cd "$(dirname "$0")" && pwd)/run-android-emulator.sh"
  
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    if [ "$USE_ITERM" = true ]; then
      # Launch with iTerm2
      osascript <<EOF
tell application "iTerm"
  create window with default profile
  tell current window
    tell current session
      set name to "$title"
      write text "cd '$(pwd)' && '$script_path' --instance $instance_id --emulator '$emulator_name' --clean $CLEAN"
    end tell
  end tell
end tell
EOF
    else
      # Launch with Terminal.app
      osascript <<EOF
tell application "Terminal"
  do script "cd '$(pwd)' && '$script_path' --instance $instance_id --emulator '$emulator_name' --clean $CLEAN"
  tell window 1
    set custom title to "$title"
  end tell
end tell
EOF
    fi
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    if [ "$TERMINAL_APP" = "gnome-terminal" ]; then
      gnome-terminal --title="$title" -- bash -c "cd '$(pwd)' && '$script_path' --instance $instance_id --emulator '$emulator_name' --clean $CLEAN; exec bash"
    elif [ "$TERMINAL_APP" = "xterm" ]; then
      xterm -title "$title" -e "cd '$(pwd)' && '$script_path' --instance $instance_id --emulator '$emulator_name' --clean $CLEAN; exec bash" &
    fi
  elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    # Windows (WSL/MSYS/Cygwin)
    cmd.exe /c start "wt.exe" new-tab --title "$title" -- bash -c "cd '$(pwd)' && '$script_path' --instance $instance_id --emulator '$emulator_name' --clean $CLEAN"
  fi
}

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

# Main script execution starts here
echo "Starting $NUM_INSTANCES Android emulator instances..."
echo "Clean existing: $CLEAN"
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
  cd "$(dirname "$0")/.." || exit 1
  docker-compose up -d
  cd - > /dev/null
  
  # Wait for services to start
  echo "Waiting for services to start..."
  sleep 5
fi

# Check if Android SDK is available
if ! command -v adb &> /dev/null; then
  echo "Error: Android SDK (adb) is not installed or not in PATH."
  echo "Please install Android Studio and add the SDK tools to your PATH."
  exit 1
fi

if ! command -v emulator &> /dev/null; then
  echo "Error: Android emulator command is not installed or not in PATH."
  echo "Please install Android Studio and add the emulator tools to your PATH."
  exit 1
fi

# Get list of available AVDs
echo "Checking available Android Virtual Devices (AVDs)..."
AVAILABLE_AVDS=$(emulator -list-avds 2>/dev/null)

if [ -z "$AVAILABLE_AVDS" ]; then
  echo "Error: No Android Virtual Devices (AVDs) found."
  echo "Please create AVDs using Android Studio's AVD Manager."
  exit 1
fi

echo "Available AVDs:"
echo "$AVAILABLE_AVDS"

# Launch each instance
for ((i=1; i<=NUM_INSTANCES; i++)); do
  # Select emulator for this instance (cycle through available ones)
  EMULATOR_INDEX=$(((i-1) % ${#EMULATORS[@]}))
  SELECTED_EMULATOR=${EMULATORS[$EMULATOR_INDEX]}
  
  # Check if the selected emulator exists in available AVDs
  if ! echo "$AVAILABLE_AVDS" | grep -q "^$SELECTED_EMULATOR$"; then
    # If not found, use the first available AVD
    SELECTED_EMULATOR=$(echo "$AVAILABLE_AVDS" | head -1)
    echo "Warning: Predefined emulator ${EMULATORS[$EMULATOR_INDEX]} not found. Using $SELECTED_EMULATOR instead."
  fi
  
  if [ "$SEQUENTIAL" = true ]; then
    echo "Launching instance $i directly (sequential mode) with emulator: $SELECTED_EMULATOR..."
    ./run-android-emulator.sh --instance $i --emulator "$SELECTED_EMULATOR" --clean $CLEAN
    echo "Instance $i completed. Moving to next instance..."
  else
    echo "Launching instance $i in new terminal window with emulator: $SELECTED_EMULATOR..."
    launch_terminal_window $i "$SELECTED_EMULATOR"
    
    # Add a short delay between instances to prevent resource contention
    echo "Waiting for 5 seconds before launching the next instance..."
    sleep 5
  fi
done

echo "All $NUM_INSTANCES Android emulator instances have been launched."
echo "Each window runs an independent Tauri Android instance."
echo "You can close individual windows to stop specific instances."
