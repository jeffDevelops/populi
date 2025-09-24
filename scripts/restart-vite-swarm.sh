#!/bin/bash
# Script to restart Vite for all instances in the iOS swarm
# without rebuilding the Rust components

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

# Function to switch to a specific desktop
switch_to_desktop() {
  local target_desktop=$1
  
  echo "Switching to desktop $target_desktop..."
  
  # Open Mission Control
  osascript -e 'tell application "System Events" to key code 126 using control down'
  sleep 0.5
  
  # Move to the target desktop
  osascript -e "tell application \"System Events\" to key code 123 using control down" # Go to first desktop
  sleep 0.5
  
  # Move right to target desktop
  for ((j=1; j<$target_desktop; j++)); do
    osascript -e 'tell application "System Events" to key code 124 using control down'
    sleep 0.2
  done
  
  sleep 0.5
}

# Track which desktop we're on
current_desktop_num=1

# Loop through all instances and restart Vite
for ((i=0; i<$NUM_INSTANCES; i++)); do
  INSTANCE_DIR="$SWARM_DIR/instance-$i"
  
  # Check if this instance should be on a new desktop
  if [ $((i % 3)) -eq 0 ] && [ $i -gt 0 ]; then
    current_desktop_num=$((current_desktop_num + 1))
    switch_to_desktop $current_desktop_num
  fi
  
  echo "Restarting Vite for instance $i..."
  
  # Calculate ports for this instance
  CLIENT_PORT_START=1420
  PORT=$((CLIENT_PORT_START + (i * 10)))
  HMR_PORT=$((PORT + 1))
  
  # Calculate the position for this instance's Terminal window
  DESKTOP_WIDTH=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')
  DESKTOP_HEIGHT=$(osascript -e 'tell application "Finder" to get item 4 of (get bounds of window of desktop)')
  DESKTOP_THIRD_WIDTH=$(($DESKTOP_WIDTH / 3))
  DESKTOP_SIXTH_WIDTH=$(($DESKTOP_WIDTH / 6))
  
  TERMINAL_HEIGHT=400
  POSITION_IN_ROW=$(($i % 3))
  TERMINAL_X_POS=$(($POSITION_IN_ROW * $DESKTOP_THIRD_WIDTH))
  TERMINAL_Y_POS=$(($DESKTOP_HEIGHT - $TERMINAL_HEIGHT))
  TERMINAL_WIDTH=$(($DESKTOP_SIXTH_WIDTH))
  
  # Create a temporary script to run Vite
  cat > "$INSTANCE_DIR/restart-vite-temp.sh" << EOF
#!/bin/bash
cd "$INSTANCE_DIR"

# Start Vite
echo "Starting Vite on port $PORT with HMR on port $HMR_PORT..."
export VITE_PORT=$PORT
export VITE_TAURI_PORT=$PORT
export VITE_TAURI_RELOAD_PORT=$HMR_PORT

# Create a temporary Vite config to set the HMR port
cat > vite.config.js << 'VITECONFIG'
import { defineConfig } from 'vite';
import { sveltekit } from '@sveltejs/kit/vite';

export default defineConfig({
  plugins: [sveltekit()],
  server: {
    port: parseInt(process.env.VITE_PORT || '1420'),
    strictPort: true,
    hmr: {
      port: parseInt(process.env.VITE_TAURI_RELOAD_PORT || '1421'),
      protocol: 'ws',
    },
  },
});
VITECONFIG

bun run vite --port $PORT --strictPort --clearScreen false
EOF
  
  chmod +x "$INSTANCE_DIR/restart-vite-temp.sh"
  
  # Find and kill the Vite process for this instance
  echo "Finding Vite process for instance $i..."
  
  # Kill Vite on main port
  VITE_PID=$(lsof -ti:$PORT 2>/dev/null)
  if [ -n "$VITE_PID" ]; then
    echo "Killing Vite process $VITE_PID on port $PORT"
    kill -TERM "$VITE_PID" 2>/dev/null || kill -KILL "$VITE_PID" 2>/dev/null
  else
    echo "No Vite process found on port $PORT"
  fi
  
  # Kill Vite on HMR port
  HMR_PID=$(lsof -ti:$HMR_PORT 2>/dev/null)
  if [ -n "$HMR_PID" ]; then
    echo "Killing Vite HMR process $HMR_PID on port $HMR_PORT"
    kill -TERM "$HMR_PID" 2>/dev/null || kill -KILL "$HMR_PID" 2>/dev/null
  else
    echo "No Vite HMR process found on port $HMR_PORT"
  fi
  
  # Open a new terminal window to run Vite
  open -a Terminal "$INSTANCE_DIR/restart-vite-temp.sh"
  
  # Wait a moment for Terminal to open
  sleep 0.1
  
  # Position the terminal window
  osascript \
    -e 'tell application "Terminal"' \
    -e "set position of front window to {$TERMINAL_X_POS, $TERMINAL_Y_POS}" \
    -e "set size of front window to {$TERMINAL_WIDTH, $TERMINAL_HEIGHT}" \
    -e 'end tell'
  
  echo "Vite server for instance $i restarted on port $PORT"
  
  # Add a small delay between instances
  sleep 1
done

echo "All Vite servers have been restarted"
echo "Make sure the ios:swarm script is still running for file synchronization"
