#!/bin/bash
# Script to restart iOS simulators and Vite servers without rebuilding Rust binaries
# This script will:
# 1. Close all running iOS simulators
# 2. Reboot the simulators used in the swarm
# 3. Restart Vite for all instances in the same loop

# Parse command line arguments
FORCE_CLEAN_INSTALL=false
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --clean)
      FORCE_CLEAN_INSTALL=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SWARM_DIR="$PROJECT_ROOT/swarm/ios"

# Check if the swarm directory exists
if [ ! -d "$SWARM_DIR" ]; then
  echo "Error: Swarm directory not found: $SWARM_DIR"
  echo "Make sure you've run the ios:swarm script first"
  exit 1
fi

# Count the number of instances
NUM_INSTANCES=$(ls -d "$SWARM_DIR/instance-"* 2>/dev/null | wc -l)
if [ "$NUM_INSTANCES" -eq 0 ]; then
  echo "Error: No instances found in $SWARM_DIR"
  echo "Make sure you've run the ios:swarm script first"
  exit 1
fi

echo "Found $NUM_INSTANCES instances in $SWARM_DIR"

# Step 1: Close all running iOS simulators
echo "Closing all running iOS simulators..."
osascript -e 'tell application "Simulator" to quit' 2>/dev/null || true
sleep 2

# Step 2: Collect simulator UDIDs from instance directories
declare -a SIMULATOR_UDIDS
declare -a SIMULATOR_NAMES

# First check if we can find the simulator information in the dev-script.sh files
SIMULATOR_INFO_FOUND=true

for ((i=0; i<$NUM_INSTANCES; i++)); do
  INSTANCE_DIR="$SWARM_DIR/instance-$i"
  DEV_SCRIPT="$INSTANCE_DIR/dev-script.sh"
  
  if [ -f "$DEV_SCRIPT" ]; then
    # Extract simulator UDID from dev-script.sh
    UDID=$(grep -o '"[0-9A-F]\{8\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{12\}"' "$DEV_SCRIPT" | head -1 | tr -d '"')
    NAME=$(grep -o '"iPhone[^"]*"' "$DEV_SCRIPT" | head -1 | tr -d '"' || echo "iPhone")
    
    if [ -n "$UDID" ]; then
      SIMULATOR_UDIDS[$i]="$UDID"
      SIMULATOR_NAMES[$i]="$NAME"
      echo "Found simulator for instance $i: $NAME ($UDID)"
    else
      echo "Warning: Could not find simulator UDID for instance $i"
      SIMULATOR_INFO_FOUND=false
    fi
  else
    echo "Warning: No dev-script.sh found for instance $i"
    SIMULATOR_INFO_FOUND=false
  fi
done

# If we couldn't find simulator info in dev scripts, try to get it from the ios-swarm.sh script
if [ "$SIMULATOR_INFO_FOUND" = false ]; then
  echo "Attempting to get simulator information from ios-swarm.sh..."
  
  # Get the list of available simulators
  SIMULATOR_LIST=$(xcrun simctl list devices available -j)
  
  # Extract names and UDIDs
  AVAILABLE_NAMES=$(echo "$SIMULATOR_LIST" | grep -o '"name" : "[^"]*"' | sed 's/"name" : "\(.*\)"/\1/')
  AVAILABLE_UDIDS=$(echo "$SIMULATOR_LIST" | grep -o '"udid" : "[^"]*"' | sed 's/"udid" : "\(.*\)"/\1/')
  
  # Convert to arrays
  OLDIFS="$IFS"
  IFS=$'\n'
  AVAILABLE_NAMES_ARRAY=()
  AVAILABLE_UDIDS_ARRAY=()
  
  for name in $AVAILABLE_NAMES; do
    AVAILABLE_NAMES_ARRAY+=("$name")
  done
  
  for udid in $AVAILABLE_UDIDS; do
    AVAILABLE_UDIDS_ARRAY+=("$udid")
  done
  IFS="$OLDIFS"
  
  # Function to deduplicate simulators
  deduplicate_simulators() {
    declare -a UNIQUE_NAMES
    declare -a UNIQUE_UDIDS
    declare -a SEEN_NAMES
    
    for ((i=0; i<${#AVAILABLE_NAMES_ARRAY[@]}; i++)); do
      local name="${AVAILABLE_NAMES_ARRAY[$i]}"
      local udid="${AVAILABLE_UDIDS_ARRAY[$i]}"
      local already_seen=false
      
      # Check if we've already seen this device name
      for seen in "${SEEN_NAMES[@]}"; do
        if [[ "$seen" == "$name" ]]; then
          already_seen=true
          break
        fi
      done
      
      # If this is the first time seeing this name, add it
      if [[ "$already_seen" == false ]]; then
        SEEN_NAMES+=("$name")
        UNIQUE_NAMES+=("$name")
        UNIQUE_UDIDS+=("$udid")
      fi
    done
    
    # Return the results
    AVAILABLE_NAMES_ARRAY=("${UNIQUE_NAMES[@]}")
    AVAILABLE_UDIDS_ARRAY=("${UNIQUE_UDIDS[@]}")
  }
  
  # Call the function to deduplicate simulators
  deduplicate_simulators
  
  # Use the first NUM_INSTANCES simulators
  for ((i=0; i<$NUM_INSTANCES; i++)); do
    if [ $i -lt ${#AVAILABLE_NAMES_ARRAY[@]} ]; then
      SIMULATOR_NAMES[$i]="${AVAILABLE_NAMES_ARRAY[$i]}"
      SIMULATOR_UDIDS[$i]="${AVAILABLE_UDIDS_ARRAY[$i]}"
      echo "Using simulator for instance $i: ${SIMULATOR_NAMES[$i]} (${SIMULATOR_UDIDS[$i]})"
    else
      echo "Error: Not enough unique simulators available"
      exit 1
    fi
  done
fi

# Function to wait for simulator to be ready
wait_for_simulator_ready() {
  local udid="$1"
  local max_attempts=8
  local attempt=1
  local delay=0.2
  
  echo "Waiting for simulator to be ready..."
  
  while [ $attempt -le $max_attempts ]; do
    if xcrun simctl list devices | grep "$udid" | grep -q "Booted"; then
      if xcrun simctl getenv "$udid" HOME >/dev/null 2>&1; then
        echo "Simulator is ready after $attempt attempts"
        return 0
      fi
    fi
    
    echo "Attempt $attempt/$max_attempts: Simulator not ready, waiting ${delay}s..."
    sleep $delay
    delay=$(echo "$delay * 2" | bc)
    attempt=$((attempt + 1))
  done
  
  echo "Timeout: Simulator failed to become ready"
  return 1
}

# Function to switch to a specific desktop - copied directly from ios-swarm.sh
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

# Function to create a new desktop - copied directly from ios-swarm.sh
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

# Function to get current desktop number - copied directly from ios-swarm.sh
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

# Function to ensure node_modules is properly set up
ensure_node_modules() {
    local instance_dir=$1
    local source_dir="$PROJECT_ROOT/apps/tauri"
    
    echo "Ensuring node_modules is properly set up for $(basename "$instance_dir")..."
    
    # Check if there's a package.json file in the instance directory
    if [ -f "$instance_dir/package.json" ]; then
        # Force a clean install if we're having dependency issues
        if [ "$FORCE_CLEAN_INSTALL" = "true" ]; then
            echo "Forcing clean install of dependencies..."
            rm -rf "$instance_dir/node_modules" 2>/dev/null
            cd "$instance_dir"
            bun install
            return
        fi
        
        # Check if node_modules exists in the instance directory
        if [ ! -d "$instance_dir/node_modules" ] || [ -L "$instance_dir/node_modules" ]; then
            # Remove any existing symlink
            rm -rf "$instance_dir/node_modules" 2>/dev/null
            
            # Try to create a symlink to the original node_modules
            if [ -d "$source_dir/node_modules" ]; then
                echo "Creating symlink to original node_modules..."
                ln -sf "$source_dir/node_modules" "$instance_dir/node_modules"
            else
                echo "Original node_modules not found, installing dependencies..."
                cd "$instance_dir"
                bun install
            fi
        else
            echo "node_modules directory already exists"
        fi
    else
        echo "No package.json found in $instance_dir"
    fi
}

# Get screen dimensions for positioning
DESKTOP_WIDTH=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')
DESKTOP_HEIGHT=$(osascript -e 'tell application "Finder" to get item 4 of (get bounds of window of desktop)')
DESKTOP_THIRD_WIDTH=$(($DESKTOP_WIDTH / 3))
DESKTOP_SIXTH_WIDTH=$(($DESKTOP_WIDTH / 6))

# Track which desktop we're on
current_desktop_num=1
last_switched_desktop=1

# Open Simulator.app
echo "Opening Simulator.app..."
open -a Simulator
sleep 2

# Process one simulator at a time, just like ios-swarm.sh
echo "Processing simulators one by one..."

for ((i=0; i<$NUM_INSTANCES; i++)); do
  if [ -n "${SIMULATOR_UDIDS[$i]}" ]; then
    INSTANCE_DIR="$SWARM_DIR/instance-$i"
    
    # Create new desktop if needed (every 3 instances)
    if [ $((i % 3)) -eq 0 ] && [ $i -gt 0 ]; then
      echo "DEBUG: Instance $i should create new desktop (i%3=$((i % 3)), i>0=$([[ $i -gt 0 ]] && echo true || echo false))"
      echo "DEBUG: Current desktop number before creation: $current_desktop_num"
      create_new_desktop
      current_desktop_num=$((current_desktop_num + 1))
      echo "DEBUG: Current desktop number after creation: $current_desktop_num"
    fi

    # Only switch desktop if it's different from last time
    if [ "$current_desktop_num" != "$last_switched_desktop" ]; then
      echo "Switching to desktop $current_desktop_num for instance $i..."
      switch_to_desktop $current_desktop_num
      last_switched_desktop=$current_desktop_num
      sleep 0.5  # Only sleep when we actually switch
    fi

    sleep 0.2

    # Boot this simulator
    echo "Booting simulator for instance $i: ${SIMULATOR_NAMES[$i]} (${SIMULATOR_UDIDS[$i]})"
    xcrun simctl boot "${SIMULATOR_UDIDS[$i]}"
    sleep 1

    # Wait for simulator to be ready
    echo "Waiting for simulator ${SIMULATOR_NAMES[$i]} (${SIMULATOR_UDIDS[$i]}) to be ready..."
    wait_for_simulator_ready "${SIMULATOR_UDIDS[$i]}"
    
    # Set location for this simulator
    ENV_FILE="$INSTANCE_DIR/.env"
    if [ -f "$ENV_FILE" ]; then
      LAT=$(grep "VITE_LOCATION_LAT" "$ENV_FILE" | cut -d'=' -f2)
      LON=$(grep "VITE_LOCATION_LONG" "$ENV_FILE" | cut -d'=' -f2)
      if [ -n "$LAT" ] && [ -n "$LON" ]; then
        echo "Setting location for simulator to $LAT, $LON"
        xcrun simctl location "${SIMULATOR_UDIDS[$i]}" set $LAT,$LON
      fi
    fi

    # Calculate position for this instance's Terminal window
    POSITION_IN_ROW=$(($i % 3))
    TERMINAL_HEIGHT=400
    TERMINAL_X_POS=$(($POSITION_IN_ROW * $DESKTOP_THIRD_WIDTH))
    TERMINAL_Y_POS=$(($DESKTOP_HEIGHT - $TERMINAL_HEIGHT))
    TERMINAL_WIDTH=$(($DESKTOP_SIXTH_WIDTH))

    # Wait for this instance's simulator window to appear, then position it
    echo "Waiting for simulator window to appear for instance $i..."
    
    # Force focus on Simulator.app to ensure windows are visible
    osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
    sleep 2
    
    # Try to position the simulator window using multiple approaches
    echo "Positioning simulator window for instance $i..."
    
    # Extract a clean version of the simulator name
    SIMULATOR_NAME_SIMPLE=$(echo "${SIMULATOR_NAMES[$i]}" | sed 's/\\//g')
    echo "Looking for window containing: $SIMULATOR_NAME_SIMPLE"
    
    # Approach 1: Try to find window by name
    osascript << EOF
tell application "System Events"
  tell process "Simulator"
    set allWindows to every window
    set foundWindow to false
    repeat with aWindow in allWindows
      try
        set winName to name of aWindow
        if winName contains "$SIMULATOR_NAME_SIMPLE" or winName contains "iPhone" or winName contains "iPad" then
          set position of aWindow to {$TERMINAL_X_POS, 0}
          set foundWindow to true
          exit repeat
        end if
      end try
    end repeat
    return foundWindow
  end tell
end tell
EOF
    
    # Approach 2: Just position the frontmost window
    osascript -e 'tell application "Simulator" to activate' \
      -e 'delay 0.5' \
      -e 'tell application "System Events"' \
      -e 'tell process "Simulator"' \
      -e 'if (count of windows) > 0 then' \
      -e "set position of window 1 to {$TERMINAL_X_POS, 0}" \
      -e 'end if' \
      -e 'end tell' \
      -e 'end tell'
    
    # Check if the Tauri app is installed
    BUNDLE_ID="com.antarcticbloom.propopulo$i"
    APP_INSTALLED=$(xcrun simctl listapps ${SIMULATOR_UDIDS[$i]} | grep -c "$BUNDLE_ID")
    
    if [ "$APP_INSTALLED" -eq 0 ]; then
      echo "Tauri app not found on simulator ${SIMULATOR_NAMES[$i]} for instance $i"
      echo "Running tauri ios init to prepare the environment..."
      
      # Run tauri ios init to prepare the environment
      cd "$INSTANCE_DIR"
      bun run tauri ios init
      
      # Copy the iOS simulator binary to the expected location if needed
      echo "Checking for iOS simulator binary..."
      SOURCE_BINARY="$INSTANCE_DIR/src-tauri/target/aarch64-apple-ios-sim/debug/propopulo"
      TARGET_DIR="$INSTANCE_DIR/src-tauri/target/debug"
      TARGET_BINARY="$TARGET_DIR/propopulo"
      
      if [ -f "$SOURCE_BINARY" ] && [ ! -f "$TARGET_BINARY" ]; then
        echo "Copying iOS simulator binary to expected location..."
        mkdir -p "$TARGET_DIR"
        cp "$SOURCE_BINARY" "$TARGET_BINARY"
      fi
      
      echo "Installing Tauri app on simulator ${SIMULATOR_NAMES[$i]}..."
      cd "$INSTANCE_DIR"
      bun run tauri ios dev "${SIMULATOR_NAMES[$i]}" &
      
      # Wait a bit for the app to install, then kill the process
      sleep 10
      pkill -f "tauri ios dev"
    else
      echo "Tauri app already installed on simulator ${SIMULATOR_NAMES[$i]} for instance $i"
    fi
    
    # Create a Vite config file for this instance
    echo "Creating Vite config for instance $i..."
    cat > "$INSTANCE_DIR/vite.config.ts" << VITECONFIG
import { defineConfig } from 'vite';
import type { PluginOption } from 'vite';
import tailwindcss from '@tailwindcss/vite';
import { sveltekit } from '@sveltejs/kit/vite';

export default defineConfig({
  plugins: [sveltekit(), tailwindcss()] as PluginOption[],
  server: {
    port: $((1420 + (i * 10))),
    strictPort: true,
    hmr: {
      port: $((1421 + (i * 10))),
      protocol: 'ws',
    },
  },
});
VITECONFIG
    
    # Remove any existing vite.config.js file to avoid conflicts
    rm -f "$INSTANCE_DIR/vite.config.js" 2>/dev/null

    # Return to the instance directory
    cd "$INSTANCE_DIR"
    
    # Make sure .svelte-kit directory exists for TypeScript configuration
    if [ -d "$PROJECT_ROOT/apps/tauri/.svelte-kit" ]; then
      echo "Copying .svelte-kit directory for TypeScript support..."
      mkdir -p "$INSTANCE_DIR/.svelte-kit"
      cp -R "$PROJECT_ROOT/apps/tauri/.svelte-kit/tsconfig.json" "$INSTANCE_DIR/.svelte-kit/" 2>/dev/null || true
      cp -R "$PROJECT_ROOT/apps/tauri/.svelte-kit/ambient.d.ts" "$INSTANCE_DIR/.svelte-kit/" 2>/dev/null || true
    fi
    
    # Copy configuration files from the original project
    echo "Copying configuration files from original project to instance $i..."
    cp "$PROJECT_ROOT/apps/tauri/package.json" "$INSTANCE_DIR/package.json"
    cp "$PROJECT_ROOT/apps/tauri/tsconfig.json" "$INSTANCE_DIR/tsconfig.json" 2>/dev/null || true
    cp "$PROJECT_ROOT/apps/tauri/postcss.config.js" "$INSTANCE_DIR/postcss.config.js" 2>/dev/null || true
    cp "$PROJECT_ROOT/apps/tauri/components.json" "$INSTANCE_DIR/components.json" 2>/dev/null || true
    cp "$PROJECT_ROOT/apps/tauri/tailwind.config.ts" "$INSTANCE_DIR/tailwind.config.ts" 2>/dev/null || true
    
    # Copy the original svelte.config.js file
    echo "Copying svelte.config.js file..."
    cp "$PROJECT_ROOT/apps/tauri/svelte.config.js" "$INSTANCE_DIR/svelte.config.js"
    
    # Ensure node_modules is properly set up
    ensure_node_modules "$INSTANCE_DIR"
    
    # Return to the instance directory
    cd "$INSTANCE_DIR"
    
    # Create a script to start Vite
    echo "Creating Vite startup script for instance $i..."
    cat > "$INSTANCE_DIR/start-vite.sh" << EOF
#!/bin/bash

# Set terminal window title to match ios:swarm script
echo -ne "\033]0;Instance $i\007"

cd "$INSTANCE_DIR"
export VITE_PORT=$((1420 + (i * 10)))
export VITE_TAURI_PORT=$((1420 + (i * 10)))
export VITE_TAURI_RELOAD_PORT=$((1421 + (i * 10)))

# Add port cleanup trap like in the original script
cleanup_port() {
    echo "Cleaning up processes on ports $((1420 + (i * 10))) and $((1421 + (i * 10)))..."
    
    # Clean up main port
    local pid=\$(lsof -ti:$((1420 + (i * 10))) 2>/dev/null)
    if [ -n "\$pid" ]; then
        echo "Killing process \$pid on port $((1420 + (i * 10)))"
        kill -TERM "\$pid" 2>/dev/null || kill -KILL "\$pid" 2>/dev/null
    else
        echo "No process found on port $((1420 + (i * 10)))"
    fi
    
    # Clean up HMR port
    local hmr_pid=\$(lsof -ti:$((1421 + (i * 10))) 2>/dev/null)
    if [ -n "\$hmr_pid" ]; then
        echo "Killing process \$hmr_pid on HMR port $((1421 + (i * 10)))"
        kill -TERM "\$hmr_pid" 2>/dev/null || kill -KILL "\$hmr_pid" 2>/dev/null
    else
        echo "No process found on HMR port $((1421 + (i * 10)))"
    fi
}

trap cleanup_port EXIT INT TERM

# Install dependencies to ensure all packages are up to date
echo "Installing dependencies for instance $i..."
bun install

# Check sveltekit code, especially generate environment variable types
bun run check

# Start Vite with TypeScript support
echo "Starting Vite server for instance $i..."
bun run vite --config vite.config.ts --port $((1420 + (i * 10))) --strictPort --clearScreen false
EOF
    chmod +x "$INSTANCE_DIR/start-vite.sh"
    
    # Start Vite in a new terminal window
    echo "Starting Vite for instance $i..."
    open -a Terminal "$INSTANCE_DIR/start-vite.sh"
    
    # Wait a moment for Terminal to open
    sleep 0.1
    
    # Position the terminal window
    osascript \
      -e 'tell application "Terminal"' \
      -e "set position of front window to {$TERMINAL_X_POS, $TERMINAL_Y_POS}" \
      -e "set size of front window to {$TERMINAL_WIDTH, $TERMINAL_HEIGHT}" \
      -e 'end tell'
    
    # Wait a bit before moving to the next instance
    sleep 1
  fi
done

echo "All simulators and Vite servers have been restarted"
echo "You can continue development without rebuilding Rust binaries"
