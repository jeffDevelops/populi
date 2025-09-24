# Advanced iOS Simulator Swarm

This script provides an enhanced way to launch multiple iOS simulator instances for testing the Propopulo app in a swarm configuration.

## Features

- Configurable number of instances (default: 3)
- Configurable client port start (default: 1420)
- Configurable CoTURN port (default: 3478)
- Option to skip the build step (--skip-build)
- Automatic IP address detection
- Dynamic port allocation to avoid collisions
- Automatic simulator selection from available devices
- Location setting for each simulator instance
- Reads location data from .env.base file
- Creates isolated project copies for each instance
- Uses rsync with --ignore-errors to handle permission issues

## Usage

```bash
# Run with default settings (3 instances)
bun run ios:swarm:advanced

# Run with custom number of instances
bun run ios:swarm:advanced -- --instances 5

# Run with custom client port start
bun run ios:swarm:advanced -- --client-port-start 2000

# Run with custom CoTURN port
bun run ios:swarm:advanced -- --coturn-port 4000

# Run with multiple custom settings
bun run ios:swarm:advanced -- --instances 4 --client-port-start 3000 --coturn-port 5000

# Skip the build step (useful if you've already built the app)
bun run ios:swarm:advanced -- --skip-build

# Use agvtool for versioning (by default, agvtool is bypassed to avoid errors)
bun run ios:swarm:advanced -- --use-agvtool
```

## How It Works

1. Reads command line arguments for number of instances, client port start, and CoTURN port
2. Detects the current machine's IP address using `ifconfig`
3. Creates an array of ports for each instance, incrementing by 10 to avoid collisions
4. Checks if the iOS binary exists and builds it if needed (unless --skip-build is specified)
5. Gets a list of available iOS simulators
6. Reads location data from .env.base file or uses defaults
7. Builds the first instance (unless --skip-build is specified)
8. Creates version files to bypass agvtool (unless --use-agvtool is specified)
9. For each instance:
   - Creates an isolated project copy in `$PROJECT_ROOT/swarm/ios/instance-<instance_id>`
   - Installs essential dependencies directly in the instance directory
   - Creates symlinks to .cargo and .rustup directories
   - Initializes the Cargo iOS environment with `tauri ios init`
   - Creates version files to bypass agvtool (unless --use-agvtool is specified)
   - Creates a custom .env file with instance-specific settings
   - Updates the tauri.conf.json file with the correct devUrl
   - Copies the iOS binary to the correct locations
   - Creates a custom vite.config.js with instance-specific settings
   - Boots the simulator and sets its location
   - Launches the Tauri app on the simulator
10. Cleans up instance directories when the script exits

## Environment Variables

Each instance gets its own .env file with the following variables:

```
VITE_INSTANCE_ID=<instance_id>
VITE_DEV_SERVER_HOST=<ip_address>
VITE_DEV_SERVER_PORT=<port>
VITE_COTURN_HOST=<ip_address>
VITE_COTURN_PORT=<coturn_port>
VITE_SIGNALING_HOSTS=<signaling_hosts_json_array>
VITE_LOCATION_LAT=<latitude>
VITE_LOCATION_LONG=<longitude>
```

## Troubleshooting

- If simulators fail to boot, try running `xcrun simctl erase all` to reset all simulators
- If the app fails to build, make sure you have the latest Xcode and iOS SDK installed
- If ports are already in use, try specifying a different client port start
- If you encounter file lock issues, increase the sleep time between instance launches
- If you see "Cannot find package 'vite'" errors, check that Bun is properly installed and working
- If the iOS binary is not found, the script will attempt to build it automatically
- The script includes debug output that will show the contents of key directories when running each instance
- If an instance fails to launch, check the terminal window for that instance for error messages
- Make sure your Xcode command-line tools are properly installed with `xcode-select --install`
- If you see Cargo build errors, ensure you have the iOS target installed with `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`
- If you encounter issues with the Rust environment, try running `tauri ios init` manually in the project root first
- Make sure your Rust toolchain is up to date with `rustup update`
