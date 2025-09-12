# Populi Development Scripts

This directory contains all automation scripts for the Populi project. These scripts help with swarm testing, environment setup, and development workflows.

## Quick Start

All scripts can be run using `bun run` commands from the project root:

```bash
# Android Development
bun run android:multi          # Launch multiple Android instances
bun run android:single         # Launch single Android instance
bun run android:setup-avds     # Create Android Virtual Devices
bun run android:setup-env      # Setup Android development environment

# Windows Development
bun run windows:multi          # Launch multiple Windows instances
bun run windows:single         # Launch single Windows instance

# Services & System
bun run dev:services           # Start Docker services (signaling, TURN)
bun run system:enable-dev-mode # Enable Windows Developer Mode
```

## Script Categories

### 🤖 Android Scripts

#### `Launch-Swarm-Android.ps1`

**Command:** `bun run android:multi`

Launches multiple Android emulator instances for P2P testing.

**When to use:**

- Testing P2P connectivity between multiple Android devices
- Validating swarm port isolation
- Simulating real-world multi-user scenarios

**Features:**

- Automatic port allocation (1420, 1450, 1480...)
- Different AVD selection per instance
- Emulator cleanup and fresh start
- Docker services integration

**Parameters:**

```powershell
# Launch 3 instances with services
bun run android:multi -- -NumberOfInstances 3 -StartServices $true

# Sequential mode (one at a time)
bun run android:multi -- -Sequential $true
```

#### `Run-Android-Emulator.ps1`

**Command:** `bun run android:single`

Runs a single Android emulator instance with dynamic configuration.

**When to use:**

- Single device testing and debugging
- Development and iteration
- Testing specific AVD configurations

**Features:**

- Dynamic port allocation
- Automatic AVD detection
- Environment variable setup
- Isolated project directories

**Parameters:**

```powershell
# Run instance 2 with specific emulator
bun run android:single -- -InstanceId 2 -EmulatorName "Pixel_7_API_34"
```

#### `Setup-Android-AVDs.ps1`

**Command:** `bun run android:setup-avds`

Creates multiple Android Virtual Devices for testing.

**When to use:**

- Initial project setup
- Adding new test devices
- Recreating corrupted AVDs

**Features:**

- Creates multiple device types (phones, tablets)
- Different Android API levels
- Optimized configurations for development

#### `setup-android-env.ps1`

**Command:** `bun run android:setup-env`

Sets up Android development environment variables.

**When to use:**

- First-time setup on new machines
- Fixing environment variable issues
- After Android SDK updates

**Features:**

- Sets ANDROID_HOME, ANDROID_SDK_ROOT
- Updates PATH with SDK tools
- Validates installation

### 🪟 Windows Scripts

#### `Launch-Swarm-Windows.ps1`

**Command:** `bun run windows:multi`

Launches multiple Windows instances for P2P testing.

**When to use:**

- Testing P2P on Windows desktop
- Multi-instance Windows development
- Cross-platform P2P validation

#### `Run-Windows-Instance.ps1`

**Command:** `bun run windows:single`

Runs a single Windows instance with port configuration.

**When to use:**

- Windows desktop development
- Single instance testing
- Debugging Windows-specific issues

### 🔧 System & Services Scripts

#### `start-services.sh`

**Command:** `bun run dev:services`

Starts Docker Compose services (signaling server, CoTURN).

**When to use:**

- Before any P2P testing
- Development environment setup
- Service debugging

**Services started:**

- Signaling server (WebSocket) on port 3000
- CoTURN server (NAT traversal) on port 3478

#### `enable-developer-mode.ps1`

**Command:** `bun run system:enable-dev-mode`

Enables Windows Developer Mode for advanced development features.

**When to use:**

- Initial Windows development setup
- Enabling symlink creation
- Advanced debugging features

### 📱 Cross-Platform Scripts (Unix/Linux/macOS)

#### `launch-swarm-ios.sh`

**Command:** `bun run dev:multi`

Launches multiple iOS simulator instances.

**When to use:**

- iOS P2P testing on macOS
- Cross-platform development
- iOS-specific feature testing

#### `run-ios-simulator.sh`

Runs individual iOS simulator instances.

#### `launch-swarm-android.sh`

Unix/Linux version of Android swarm launcher.

#### `run-android-emulator.sh`

Unix/Linux version of Android single instance runner.

## Port Allocation Strategy

The scripts use a systematic port allocation to avoid conflicts:

- **Base ports:** 1420 (Vite server), 1421 (HMR)
- **Instance spacing:** 30 ports per instance
- **Instance 1:** 1420, 1421
- **Instance 2:** 1450, 1451
- **Instance 3:** 1480, 1481
- **Reserved:** Port 3000 (signaling server)

## Environment Variables

Scripts automatically set these environment variables per instance:

```bash
VITE_INSTANCE_ID=1
VITE_SERVER_PORT=1420
VITE_HMR_PORT=1421
VITE_HOST_IP=192.168.1.100
VITE_SIGNALING_URL=ws://192.168.1.100:3000
VITE_TURN_SERVER=192.168.1.100:3478
```

## Parameter Usage

### Windows (PowerShell)

Windows scripts use PowerShell-style named parameters with single dashes:

```powershell
# Launch 3 Android instances with cleanup and services
bun run windows:android:multi -- -NumberOfInstances 3 -Clean $true -StartServices $true

# Launch single Android instance without cleanup
bun run windows:android:single -- -InstanceId 1 -EmulatorName "Pixel_7_API_34" -Clean $false
```

### macOS/Linux (Bash)

macOS and Linux scripts use bash-style named parameters with double dashes:

```bash
# Launch 3 Android instances with cleanup and services
bun run macos:android:multi -- --instances 3 --clean true --services true

# Launch single Android instance without cleanup
bun run macos:android:single -- --instance 1 --emulator "Pixel_7_API_34" --clean false
```

## Parameter Descriptions

### Common Parameters

- **`--clean` / `-Clean`**: Controls whether existing emulators/simulators are terminated before launching new instances
  - `true` (default): Kill existing emulators/simulators and start fresh
  - `false`: Preserve existing emulators/simulators and connect to them if possible
- **`--instances` / `-NumberOfInstances`**: Number of instances to launch (default: 2)

- **`--sequential` / `-Sequential`**: Launch mode
  - `false` (default): Launch instances in parallel using separate terminal windows
  - `true`: Launch instances one at a time in the current terminal

- **`--services` / `-StartServices`**: Whether to start Docker Compose services
  - `false` (default): Don't start services
  - `true`: Start signaling server and CoTURN services before launching instances

### Android-Specific Parameters

- **`--emulator` / `-EmulatorName`**: Specific Android Virtual Device (AVD) name to use

### iOS-Specific Parameters

- **`--simulator` / `-SimulatorName`**: Specific iOS simulator device to use

## Troubleshooting

### Common Issues

**Port conflicts:**

```bash
# Clean up existing processes
bun run android:single -- -InstanceId 1  # Includes cleanup
```

**AVD not found:**

```bash
# Create new AVDs
bun run android:setup-avds
```

**Environment issues:**

```bash
# Reset Android environment
bun run android:setup-env
```

**Permission errors:**

```bash
# Enable developer mode
bun run system:enable-dev-mode
```

### Script Dependencies

**Required for Android:**

- Android Studio with SDK
- Android SDK Build Tools
- Android Emulator
- Node.js (for Tauri CLI NAPI compatibility)

**Required for Windows:**

- PowerShell 5.1+
- Windows Developer Mode (for symlinks)

**Required for Services:**

- Docker Desktop
- Docker Compose

## Development Workflow

### Typical P2P Testing Session

1. **Start services:**

   ```bash
   bun run dev:services
   ```

2. **Launch multiple instances:**

   ```bash
   # Android
   bun run android:multi -- -NumberOfInstances 2 -StartServices $false

   # Or Windows
   bun run windows:multi -- -NumberOfInstances 2
   ```

3. **Test P2P connectivity between instances**

4. **Debug individual instances if needed:**
   ```bash
   bun run android:single -- -InstanceId 1
   ```

### First-Time Setup

1. **Enable developer mode:**

   ```bash
   bun run system:enable-dev-mode
   ```

2. **Setup Android environment:**

   ```bash
   bun run android:setup-env
   ```

3. **Create AVDs:**

   ```bash
   bun run android:setup-avds
   ```

4. **Test single instance:**

   ```bash
   bun run android:single
   ```

5. **Test swarm:**
   ```bash
   bun run android:multi
   ```

## Contributing

When adding new scripts:

1. Place them in the `scripts/` directory
2. Add corresponding `bun run` commands to `package.json`
3. Update this README with usage documentation
4. Follow the existing naming conventions:
   - `platform:action` for platform-specific scripts
   - `category:action` for general scripts
