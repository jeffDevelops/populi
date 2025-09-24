#!/bin/bash
# iOS Simulator Swarm Script
# This script launches multiple iOS simulator instances with configurable ports and locations

# Default values
NUM_INSTANCES=3
CLIENT_PORT_START=1420
COTURN_PORT=3478
SKIP_BUILD=false
DEFAULT_LAT=39.66753456235311
DEFAULT_LON=-104.99328715234329

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --instances|--Instances)
      NUM_INSTANCES="$2"
      shift 2
      ;;
    --client-port-start|--Client-Port-Start)
      CLIENT_PORT_START="$2"
      shift 2
      ;;
    --coturn-port|--Coturn-Port)
      COTURN_PORT="$2"
      shift 2
      ;;
    --skip-build|--Skip-Build)
      SKIP_BUILD=true
      shift
      ;;
    *)
      echo "Unknown option $1"
      echo "Usage: $0 [--instances N] [--client-port-start PORT] [--coturn-port PORT] [--skip-build]"
      exit 1
      ;;
  esac
done

PROJECT_ROOT=$(pwd)

# Create swarm directory if it doesn't exist
SWARM_DIR="$PROJECT_ROOT/swarm/ios"
if [ -d "$SWARM_DIR" ]; then
  echo "Directory '$SWARM_DIR' exists."
else
  echo "Directory '$SWARM_DIR' does not exist. Creating..."
  mkdir -p "$SWARM_DIR"
fi

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_PROJECT_ROOT="$(dirname "$SCRIPT_DIR")/apps/tauri"

# Get current machine's IP address
IP_ADDRESS=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
if [ -z "$IP_ADDRESS" ]; then
  echo "Could not determine IP address"
  exit 1
fi

# Create DEV_INSTANCE_PORTS array
declare -a DEV_INSTANCE_PORTS
for ((i=0; i<$NUM_INSTANCES; i++)); do
  DEV_INSTANCE_PORTS[$i]=$((CLIENT_PORT_START + (i * 10)))
done

# Read location data from .env.base or use defaults
declare -a LAT_ARRAY
declare -a LON_ARRAY
if [ -f "$CLIENT_PROJECT_ROOT/.env.base" ]; then
  source "$CLIENT_PROJECT_ROOT/.env.base"
  
  # Set up location arrays dynamically for any number of instances
  for ((i=0; i<$NUM_INSTANCES; i++)); do
    # Use variable indirection to get the latitude and longitude for each instance
    lat_var="INSTANCE_${i}_LATITUDE"
    lon_var="INSTANCE_${i}_LONGITUDE"
    
    # Use parameter expansion to get the value or default
    LAT_ARRAY[$i]=${!lat_var:-$DEFAULT_LAT}
    LON_ARRAY[$i]=${!lon_var:-$DEFAULT_LON}
  done
  
  for ((i=0; i<$NUM_INSTANCES; i++)); do
    LAT_ARRAY[$i]=$DEFAULT_LAT
    LON_ARRAY[$i]=$DEFAULT_LON
  done
fi

# Wrangle simulators to pre-boot them in individual scripts
SIMULATOR_LIST=$(xcrun simctl list devices available -j)

# Replace your simulator selection with this deduplication logic:
deduplicate_simulators() {
    local unique_names=()
    local unique_udids=()
    local seen_names=()
    
    for ((i=0; i<${#SIMULATOR_NAMES_ARRAY[@]}; i++)); do
        local name="${SIMULATOR_NAMES_ARRAY[$i]}"
        local udid="${SIMULATOR_UDIDS_ARRAY[$i]}"
        local already_seen=false
        
        # Check if we've already seen this device name
        for seen in "${seen_names[@]}"; do
            if [[ "$seen" == "$name" ]]; then
                already_seen=true
                break
            fi
        done
        
        # If this is the first time seeing this name, add it
        if [[ "$already_seen" == false ]]; then
            seen_names+=("$name")
            unique_names+=("$name")
            unique_udids+=("$udid")
        fi
    done
    
    # Replace the original arrays with deduplicated ones
    SIMULATOR_NAMES_ARRAY=("${unique_names[@]}")
    SIMULATOR_UDIDS_ARRAY=("${unique_udids[@]}")
}

# Call this after building your initial arrays but before selection:
SIMULATOR_NAMES=$(echo "$SIMULATOR_LIST" | grep -o '"name" : "[^"]*"' | sed 's/"name" : "\(.*\)"/\1/')
SIMULATOR_UDIDS=$(echo "$SIMULATOR_LIST" | grep -o '"udid" : "[^"]*"' | sed 's/"udid" : "\(.*\)"/\1/')

# Build arrays as you do now...
SIMULATOR_NAMES_ARRAY=()
SIMULATOR_UDIDS_ARRAY=()
OLDIFS="$IFS"
IFS=$'\n'
for name in $SIMULATOR_NAMES; do
    SIMULATOR_NAMES_ARRAY+=("$name")
done
for udid in $SIMULATOR_UDIDS; do
    SIMULATOR_UDIDS_ARRAY+=("$udid")
done
IFS="$OLDIFS"

# Add deduplication here:
deduplicate_simulators

# Now proceed with your swarm selection:
declare -a SWARM_SIMULATOR_NAMES
declare -a SWARM_SIMULATOR_UDIDS
for ((i=0; i<$NUM_INSTANCES; i++)); do
    if [ $i -lt ${#SIMULATOR_NAMES_ARRAY[@]} ]; then
        SWARM_SIMULATOR_NAMES[$i]="${SIMULATOR_NAMES_ARRAY[$i]}"
        SWARM_SIMULATOR_UDIDS[$i]="${SIMULATOR_UDIDS_ARRAY[$i]}"
    else
        echo "Not enough unique simulators available for the swarm."
        echo "Requested: $NUM_INSTANCES, Available unique: ${#SIMULATOR_NAMES_ARRAY[@]}"
        exit 1
    fi
done

# Create signaling hosts string (JSON array)
SIGNALING_PORT=3000  # Default signaling server port
SIGNALING_HOSTS="[\"$IP_ADDRESS:$SIGNALING_PORT\"]"

echo "Script directory: $SCRIPT_DIR"
echo "Project root: $PROJECT_ROOT"
echo "Client project root: $CLIENT_PROJECT_ROOT"
echo "Current machine IP address: $IP_ADDRESS"
echo "Tauri dev instance ports: ${DEV_INSTANCE_PORTS[*]}"
echo "Signaling hosts: $SIGNALING_HOSTS"
echo "Selected simulators for swarm: ${SWARM_SIMULATOR_NAMES[*]}"
echo "Geolocation latitudes: ${LAT_ARRAY[*]}"
echo "Geolocation longitudes: ${LON_ARRAY[*]}"

update_tauri_config() {
  local instance_dir=$1
  local port=$2
  local instance_id=$3
  local tauri_config="$instance_dir/src-tauri/tauri.conf.json"
  
  echo "Updating tauri.conf.json for instance with port $port"
  
  # Make sure the file exists
  if [ ! -f "$tauri_config" ]; then
    echo "Error: tauri.conf.json not found at $tauri_config"
    return 1
  fi
  
  # Update the devUrl in tauri.conf.json
  sed -i.tmp "s|\"devUrl\": \"http://localhost:[0-9]*\"|\"devUrl\": \"http://localhost:$port\"|g" "$tauri_config"
  rm -f "${tauri_config}.tmp"
  
  # Make sure the bundle identifier is set correctly
  BUNDLE_ID="com.antarcticbloom.propopulo${instance_id}"
  echo "Setting bundle identifier to $BUNDLE_ID"
  sed -i.tmp "s|\"identifier\": \"[^\"]*\"|\"identifier\": \"$BUNDLE_ID\"|g" "$tauri_config"

  # Make sure the productName is set correctly
  PRODUCT_NAME="ProPopulo${instance_id}"
  echo "Setting product name to $PRODUCT_NAME"
  sed -i.tmp "s|\"productName\": \"[^\"]*\"|\"productName\": \"$PRODUCT_NAME\"|g" "$tauri_config"

  rm -f "${tauri_config}.tmp"
}

echo "Copying ${CLIENT_PROJECT_ROOT}/ to swarm instances..."
rsync_pids=()

# Create a temporary exclude file for better performance
EXCLUDE_FILE=$(mktemp)
cat > "$EXCLUDE_FILE" << 'EOL' 2>/dev/null
node_modules/
.vite/
bun.lockb
.DS_Store
*.log
# Build artifacts and caches
dist/
coverage/
# OS files
Thumbs.db
.Trash-*
# Logs and temp files
logs/
*.tgz
*.tar.gz
tmp/
temp/
# SvelteKit Build Artifacts
build/
# iOS specific build artifacts
ios/build/
ios/DerivedData/
ios/*.xcworkspace/xcuserdata/
ios/*.xcodeproj/xcuserdata/
ios/*.xcodeproj/project.xcworkspace/xcuserdata/
# Rust build artifacts (CRITICAL: prevent hard-link conflicts)
**/target/
**/.cargo/
Cargo.lock
# Exclude any compiled artifacts that could conflict
**/*.rlib
**/*.rmeta
**/*.a
**/*.so
**/*.dylib
EOL

# Use standard rsync for all instances (fast enough with good exclusions)
for ((i=0; i<$NUM_INSTANCES; i++)); do
  INSTANCE_DIR="$SWARM_DIR/instance-$i"
  mkdir -p "$INSTANCE_DIR"
  
  rsync -a \
      --delete \
      --exclude-from="$EXCLUDE_FILE" \
      --compress \
      "${CLIENT_PROJECT_ROOT}/" "${INSTANCE_DIR}/" &
      rsync_pids+=($!)
done

# Wait for copies to finish
echo "Waiting for rsync operations to complete..."
for i in "${!rsync_pids[@]}"; do
  if wait "${rsync_pids[$i]}"; then
    echo "Instance $i copy completed"
  else
    echo "Instance $i copy failed"
  fi
done

# Clean up temporary exclude file
rm -f "$EXCLUDE_FILE"

# Get screen dimensions for positioning
DESKTOP_WIDTH=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')
DESKTOP_HEIGHT=$(osascript -e 'tell application "Finder" to get item 4 of (get bounds of window of desktop)')
DESKTOP_THIRD_WIDTH=$(($DESKTOP_WIDTH / 3))
DESKTOP_SIXTH_WIDTH=$(($DESKTOP_WIDTH / 6))

# Function to create a new desktop - more reliable version
create_new_desktop() {
    echo "Creating new desktop..."
    osascript << 'EOF'
tell application "System Events"
    key code 126 using control down  -- Control+Up to open Mission Control
    delay 1.5
    
    -- Move to the rightmost desktop first
    repeat 5 times
        key code 124  -- Right arrow
        delay 0.1
    end repeat
    
    -- Try to add desktop with + key or mouse click
    key code 24  -- Plus key
    delay 0.5
    
    key code 53  -- Escape to close Mission Control
    delay 0.5
end tell
EOF
}

# Function to get current desktop number
get_current_desktop() {
    osascript << 'EOF'
tell application "System Events"
    tell process "Dock"
        try
            -- This might work on some systems
            return value of attribute "AXSelectedChildren" of list 1 of group 1
        on error
            -- Fallback: just return 1
            return 1
        end try
    end tell
end tell
EOF
}

# Function to switch to a specific desktop - optimized
switch_to_desktop() {
    local target_desktop=$1
    local current_desktop=$(get_current_desktop)
    
    if [ "$current_desktop" = "$target_desktop" ]; then
        echo "Already on desktop $target_desktop"
        return
    fi
    
    echo "Moving from desktop $current_desktop to desktop $target_desktop..."
    
    if [ "$target_desktop" -gt "$current_desktop" ]; then
        local moves=$(( target_desktop - current_desktop ))
        for ((j=0; j<moves; j++)); do
            osascript -e 'tell application "System Events" to key code 124 using control down'  # Control+Right
            sleep 0.2  # Reduced from 0.5
        done
    else
        local moves=$(( current_desktop - target_desktop ))
        for ((j=0; j<moves; j++)); do
            osascript -e 'tell application "System Events" to key code 123 using control down'  # Control+Left
            sleep 0.2
        done
    fi
    
    sleep 0.5  # Reduced from 2 seconds
}
echo "Starting swarm with keyboard-based desktop switching..."

# Track which desktop we're on
current_desktop_num=1
last_switched_desktop=1

# MAIN SWARM LOOP
for ((i=0; i<$NUM_INSTANCES; i++)); do

    if [ $((i % 3)) -eq 0 ] && [ $i -gt 0 ]; then
        echo "DEBUG: Instance $i should create new desktop (i%3=$((i % 3)), i>0=$([[ $i -gt 0 ]] && echo true || echo false))"
        echo "DEBUG: Current desktop number before creation: $current_desktop_num"
        create_new_desktop
        current_desktop_num=$((current_desktop_num + 1))
        echo "DEBUG: Current desktop number after creation: $current_desktop_num"
    fi

    INSTANCE_DIR="$SWARM_DIR/instance-$i"

    # Create empty build directory for Tauri validation
    mkdir -p "$INSTANCE_DIR/build"
    
    # Clean development caches
    rm -rf "$INSTANCE_DIR/.svelte-kit"
    rm -rf "$INSTANCE_DIR/.vite"

    update_tauri_config "$INSTANCE_DIR" "${DEV_INSTANCE_PORTS[i]}" "$i"

    # Create .env file for this instance
    echo "Creating .env file for instance $i..."
    cat > "$INSTANCE_DIR/.env" << EOF
PUBLIC_INSTANCE_ID=$i
PUBLIC_INSTANCE_DEV_SERVER_HOST=$IP_ADDRESS
PUBLIC_INSTANCE_DEV_SERVER_PORT=${DEV_INSTANCE_PORTS[i]}
PUBLIC_INSTANCE_DEV_HMR_PORT=$(( $(echo "${DEV_INSTANCE_PORTS[i]}" | bc) + 1 ))
PUBLIC_COTURN_HOST=$IP_ADDRESS
PUBLIC_COTURN_PORT=$COTURN_PORT
PUBLIC_SIGNALING_HOSTS=$SIGNALING_HOSTS
PUBLIC_LOCATION_LAT=${LAT_ARRAY[i]}
PUBLIC_LOCATION_LONG=${LON_ARRAY[i]}
EOF

    # Function to escape device name for command line
    escape_device_name() {
        local name="$1"
        # Escape spaces and parentheses
        echo "$name" | sed 's/ /\\ /g; s/(/\\(/g; s/)/\\)/g'
    }

    # Only switch desktop if it's different from last time
    if [ "$current_desktop_num" != "$last_switched_desktop" ]; then
        echo "Switching to desktop $current_desktop_num for instance $i..."
        switch_to_desktop $current_desktop_num
        last_switched_desktop=$current_desktop_num
        sleep 0.5  # Only sleep when we actually switch
    fi

    sleep 0.2

    # Write the dev script for this instance
    echo "Creating dev script for instance $i..."

    simulator_name="${SWARM_SIMULATOR_NAMES[$i]}"
    simulator_name_escaped="$(escape_device_name "$simulator_name")"
    simulator_udid="${SWARM_SIMULATOR_UDIDS[$i]}"
    lat="${LAT_ARRAY[$i]}"
    lon="${LON_ARRAY[$i]}"
    main_port="${DEV_INSTANCE_PORTS[$i]}"
    hmr_port=$((main_port + 1))

    POSITION_IN_ROW=$(($i % 3))

    # Calculate the position for this instance's Terminal window
    TERMINAL_HEIGHT=400
    TERMINAL_X_POS=$(($POSITION_IN_ROW * $DESKTOP_THIRD_WIDTH))
    TERMINAL_Y_POS=$(($DESKTOP_HEIGHT - $TERMINAL_HEIGHT))
    TERMINAL_WIDTH=$(($DESKTOP_SIXTH_WIDTH))

    # Create the dev script content with proper variable substitution
cat > "$INSTANCE_DIR/dev-script.sh" << EOF
#!/bin/bash
# This script was generated by advanced-swarm-ios.sh

# Variables from parent script
INSTANCE_NUM=$i
TOTAL_INSTANCES=$NUM_INSTANCES

# Set a trap to ensure ports are freed if the script exits or is interrupted
echo -ne "\033]0;Instance $i\007"
cleanup_port() {
    echo "Cleaning up processes on ports $main_port and $hmr_port..."
    
    # Clean up main port
    local pid=\$(lsof -ti:$main_port 2>/dev/null)
    if [ -n "\$pid" ]; then
        echo "Killing process \$pid on port $main_port"
        kill -TERM "\$pid" 2>/dev/null || kill -KILL "\$pid" 2>/dev/null
    else
        echo "No process found on port $main_port"
    fi
    
    # Clean up HMR port
    local hmr_pid=\$(lsof -ti:$hmr_port 2>/dev/null)
    if [ -n "\$hmr_pid" ]; then
        echo "Killing process \$hmr_pid on HMR port $hmr_port"
        kill -TERM "\$hmr_pid" 2>/dev/null || kill -KILL "\$hmr_pid" 2>/dev/null
    else
        echo "No process found on HMR port $hmr_port"
    fi
}

trap cleanup_port EXIT INT TERM

# Ensure variables were passed
if [ -z "$simulator_name_escaped" ]; then
  echo "Error: Could not find simulator with name $simulator_name"
  exit 1
fi

if [ -z "$simulator_udid" ]; then
  echo "Error: Could not find simulator with udid $simulator_udid"
  exit 1
fi

# Function to wait for simulator with exponential backoff
wait_for_simulator_ready() {
    local udid="\$1"
    local max_attempts=8
    local attempt=1
    local delay=0.2
    
    echo "Waiting for simulator to be ready..."
    
    while [ \$attempt -le \$max_attempts ]; do
        if xcrun simctl list devices | grep "\$udid" | grep -q "Booted"; then
            if xcrun simctl getenv "\$udid" HOME >/dev/null 2>&1; then
                echo "Simulator is ready after \$attempt attempts"
                return 0
            fi
        fi
        
        echo "Attempt \$attempt/\$max_attempts: Simulator not ready, waiting \${delay}s..."
        sleep \$delay
        delay=\$((delay * 2))
        attempt=\$((attempt + 1))
    done
    
    echo "Timeout: Simulator failed to become ready"
    return 1
}

# Boot simulator if needed
device_line="\$(xcrun simctl list devices | grep "$simulator_udid")"
DEVICE_STATE="\$(echo "\$device_line" | awk '{print \$NF}' | tr -d '()')"

case "\$DEVICE_STATE" in
    "Shutdown")
        echo "Booting simulator..."
        sleep 0.75
        xcrun simctl boot "$simulator_udid"
        ;;
    "Booted")
        echo "Simulator already booted"
        ;;
esac

# Wait for simulator to be ready with exponential backoff
if ! wait_for_simulator_ready "$simulator_udid"; then
    echo "Failed to prepare simulator"
    exit 1
fi

cd "$INSTANCE_DIR"
bun install
bun run tauri ios init

# Set location for this simulator
echo "Setting location for simulator to $lat, $lon"
xcrun simctl location "$simulator_udid" set $lat,$lon

remaining_instances=\$((TOTAL_INSTANCES - INSTANCE_NUM))
stagger_delay=\$((remaining_instances * 5))
echo "Waiting \${stagger_delay}s before launch (\${remaining_instances} instances remaining)"
sleep \$stagger_delay

# Run the project
bun --env-file=.env run tauri ios dev "$simulator_name_escaped"
EOF

    chmod +x "$INSTANCE_DIR/dev-script.sh"

    cd "$INSTANCE_DIR"

    # Open terminal
    open -a Terminal "$INSTANCE_DIR/dev-script.sh"

    # Wait a moment for Terminal to open
    sleep 0.1

    osascript \
      -e 'tell application "Terminal"' \
      -e 'set position of front window to {'$TERMINAL_X_POS', '$TERMINAL_Y_POS'}' \
      -e 'set size of front window to {'$TERMINAL_WIDTH', '$TERMINAL_HEIGHT'}' \
      -e 'end tell'

    # Wait for this instance's simulator window to appear, then position it
    echo "Waiting for simulator window to appear for instance $i..."
    
    # Get the current count of simulator windows before this iteration
    initial_count=$(osascript -e 'tell application "System Events" to tell process "Simulator" to count (every window whose name contains "iPhone" or name contains "iPad")' 2>/dev/null || echo "0")
    
    # Wait up to 30 seconds for a NEW simulator window to appear
    for attempt in {1..30}; do
        current_count=$(osascript -e 'tell application "System Events" to tell process "Simulator" to count (every window whose name contains "iPhone" or name contains "iPad")' 2>/dev/null || echo "0")
        
        if [ "$current_count" -gt "$initial_count" ]; then
            echo "New simulator window appeared, positioning..."
            # Position the frontmost simulator window (most recently created)

            sleep 0.01

            osascript \
              -e 'tell application "System Events"' \
              -e 'tell process "Simulator"' \
              -e 'set simulator_windows to (every window whose name contains "iPhone" or name contains "iPad")' \
              -e 'if (count of simulator_windows) > 0 then' \
              -e 'set position of item 1 of simulator_windows to {'$TERMINAL_X_POS', 0}' \
              -e 'end if' \
              -e 'end tell' \
              -e 'end tell'
            break
        fi
    done
done


echo "All simulators launched. Setting up Safari dev tools windows..."

cd "$PROJECT_ROOT"
echo "Starting src directory mirroring..."
cd "$PROJECT_ROOT"

bun scripts/sync-swarm.ts \
    --targetOS iOS \
    --hostOS macOS \
    --instances "$NUM_INSTANCES" \
    --projectRoot "$PROJECT_ROOT" &

SRC_MIRROR_PID=$!

cleanup_all() {
    echo "Cleaning up swarm processes..."
    
    if [ -n "$SRC_MIRROR_PID" ] && kill -0 "$SRC_MIRROR_PID" 2>/dev/null; then
        echo "Stopping src mirroring process..."
        kill "$SRC_MIRROR_PID"
    fi
    
    echo "Cleanup complete"
}

# Set trap for exit, interrupt, and termination
trap cleanup_all EXIT INT TERM

echo "Mirroring src directory to swarm instances...Press Ctrl+C to stop."
wait $SRC_MIRROR_PID