#!/bin/bash
# Script to restart only the Vite server for a specific iOS simulator instance
# without rebuilding the Rust components

# Check if instance number is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <instance-number>"
  echo "Example: $0 1 (for instance-1 directory)"
  echo "Note: Use the same number as in the directory name (instance-0, instance-1, etc.)"
  exit 1
fi

# Convert to 0-based index if needed
INSTANCE_NUM=$1
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
INSTANCE_DIR="$PROJECT_ROOT/swarm/ios/instance-$INSTANCE_NUM"

# Verify that the instance directory exists
if [ ! -d "$INSTANCE_DIR" ]; then
  echo "Error: Instance directory not found: $INSTANCE_DIR"
  echo "Available instances:"
  ls -d "$PROJECT_ROOT/swarm/ios/instance-"* 2>/dev/null | xargs -n1 basename
  exit 1
fi


# Find and kill the Vite process for this instance
echo "Finding Vite process for instance $INSTANCE_NUM..."

# Calculate port using the same logic as ios-swarm.sh
# Instance numbers are already 0-based in the directory name (instance-0, instance-1, etc.)
CLIENT_PORT_START=1420
PORT=$((CLIENT_PORT_START + (INSTANCE_NUM * 10)))
HMR_PORT=$((PORT + 1))

echo "Using port $PORT for Vite and port $HMR_PORT for HMR"

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

# Start Vite directly
echo "Starting Vite for instance $INSTANCE_NUM..."
cd "$INSTANCE_DIR"

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

# Calculate the position for this instance's Terminal window
DESKTOP_WIDTH=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')
DESKTOP_HEIGHT=$(osascript -e 'tell application "Finder" to get item 4 of (get bounds of window of desktop)')
DESKTOP_THIRD_WIDTH=$(($DESKTOP_WIDTH / 3))
DESKTOP_SIXTH_WIDTH=$(($DESKTOP_WIDTH / 6))

TERMINAL_HEIGHT=400
POSITION_IN_ROW=$(($INSTANCE_NUM % 3))
TERMINAL_X_POS=$(($POSITION_IN_ROW * $DESKTOP_THIRD_WIDTH))
TERMINAL_Y_POS=$(($DESKTOP_HEIGHT - $TERMINAL_HEIGHT))
TERMINAL_WIDTH=$(($DESKTOP_SIXTH_WIDTH))

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

echo "Vite server for instance $INSTANCE_NUM is restarting on port $PORT"
echo "Your app should reload automatically once Vite is running"
echo "Make sure the ios:swarm script is still running for file synchronization"
