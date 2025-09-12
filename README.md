# Populi - A metaframework for decentralized applicationsEX

Populi is a metaframework for decentralized applications. It is not open source. Here's why:

Traditional open source assumes good faith and shared values. Some actors, however, have fundamentally hostile interests we believe actively must be excluded. We are open to participation, but have mechanisms to exclude bad-faith actors who would destroy the system from within.

## Table of Contents

- [Populi - A metaframework for decentralized applicationsEX](#populi---a-metaframework-for-decentralized-applicationsex)
  - [Table of Contents](#table-of-contents)
  - [Philosophy: Big Tech's Open Source Playbook](#philosophy-big-techs-open-source-playbook)
    - [Embrace, Extend, Extinguish](#embrace-extend-extinguish)
      - [Embrace](#embrace)
      - [Extend](#extend)
      - [Extinguish](#extinguish)
    - [Vendor Lock-in Patterns](#vendor-lock-in-patterns)
    - [Other potential Big Tech attack vectors](#other-potential-big-tech-attack-vectors)
      - [Infrastructure Capture](#infrastructure-capture)
      - [Superior Engineering Resources](#superior-engineering-resources)
  - [Development](#development)
    - [Getting Started](#getting-started)
    - [Script Naming Convention](#script-naming-convention)
    - [Multi-Instance Testing](#swarm-testing)
      - [Windows](#windows)
      - [macOS](#macos)
      - [Android](#android)
        - [Initial Setup](#initial-setup)
        - [Multi-Instance Launching](#swarm-launching)

## Philosophy: Big Tech's Open Source Playbook

### Embrace, Extend, Extinguish

FAANG (Facebook, Amazon, Apple, Netflix, Google), or now MANGA (Meta / Microsoft, Amazon, Netflix, Google, Apple) have used open source to fragment networks and kill alternatives.

Historical examples of this playbook include XMPP, RSS, and email. Google embraced and extended XMPP with Google Talk, then abandoned the project, fragmenting the network. Facebook and Twitter killed adoption of RSS by providing "better" proprietary alternatives. Email still uses open protocols but is increasingly controlled by Gmail/Outlook oligopoly.

#### Embrace

FAANG: "Sure! We support open standards! We'll build clients that work with your protocol. We'll even contribute to development and provide infrastructure, if you allow us to gain influence in governance."

#### Extend

FAANG then add proprietary features that only work with their clients. "We provide an enhanced experience when connecting to other \[FAANG\] users." This gradually makes the underlying protocol inferior and less interoperable with other protocols.

#### Extinguish

FAANG achieves a critical mass of users dependent on the proprietary experience. They break compatibility with implementations that use the "pure" open standard, and use colorful language like "legacy" to describe those implementations to portray them as inferior. They then force users to choose between losing the features they provide, or switch to the corporate version with the subscription plan.

### Vendor Lock-in Patterns

- Tech companies offer "free" services that are often critical dependencies, such as authentication, database hosting, etc., and build their business models off the idea that many of these free tier accounts will upgrade to paid accounts once usership grows. Sure, these companies need to make money, but the price gouge that comes with consumers' broaching the paid tier is often prohibitive to the point where the fledgling service either needs the resources to spend a development cycle on migrating to an in-house replacement, or be forced to shutter the service entirely.

### Other potential Big Tech attack vectors

#### Infrastructure Capture

- In exchange for governance influence, FAANG could offer "free" high-performing signaling, STUN, and TURN servers that increasingly become dependencies.
- Storage: FAANG could offer "free" cloud storage in OneDrive, Google Drive, iCloud, or S3, or bundle such services with their proprietary clients.

#### Superior Engineering Resources

- FAANG has access to some of the best engineers in the world, and can use their influence to recruit top talent. This gives them a significant advantage in development speed and quality.

## Development

### Getting Started

The project uses Bun as the package manager and can be started with:

```bash
bun run dev
```

This runs `turbo dev` and starts Docker Compose services including the signaling server and CoTURN server for NAT traversal.

### Script Naming Convention

All development scripts follow the pattern: `[host-os]:[target-os]:[action]`

- **host-os**: The operating system where the script runs (windows, macos, linux)
- **target-os**: The platform being targeted (android, ios, windows, web, system)
- **action**: What the script does (multi, single, setup-avds, setup-env, etc.)

**Examples:**

- `windows:android:multi` - Run multiple Android instances from Windows
- `macos:ios:single` - Run single iOS instance from macOS
- `windows:system:enable-dev-mode` - Configure Windows system settings

This convention provides clear separation between host environment and target platform, making cross-platform development intuitive and reducing cognitive overhead.

### Multi-Instance Testing

For testing peer-to-peer functionality, you can launch multiple instances of the Tauri app:

#### Windows

**Available Commands:**

```bash
# Windows Development
bun run windows:windows:multi          # Multiple Windows instances
bun run windows:windows:single         # Single Windows instance

# Android from Windows
bun run windows:android:swarm          # Multiple Android emulators
bun run windows:android:single         # Single Android emulator
bun run windows:android:setup-avds     # Create Android Virtual Devices
bun run windows:android:setup-env      # Setup Android environment

# System Configuration
bun run windows:system:enable-dev-mode # Enable Windows Developer Mode

# Services
bun run dev:services                   # Start Docker services
```

**Named Parameters:**

```bash
# Examples with PowerShell named parameters
bun run windows:windows:multi -- -NumberOfInstances 3 -Sequential $true
bun run windows:android:swarm -- -StartServices $true -NumberOfInstances 4
bun run windows:android:single -- -InstanceId 2 -EmulatorName "Pixel_7_API_34"
```

#### macOS

**Available Commands:**

```bash
# iOS Development
bun run macos:ios:swarm            # Multiple iOS simulators
bun run macos:ios:single           # Single iOS simulator

# Android from macOS
bun run macos:android:swarm        # Multiple Android emulators
bun run macos:android:single       # Single Android emulator

# Services
bun run dev:services               # Start Docker services
```

#### Android

##### Initial Setup

Before launching Launch-Swarm-Android.ps1 instances, you need to set up your development environment:

**Prerequisites:**

1. **Android Studio** - Download from https://developer.android.com/studio
2. **Java JDK 17+** - Required for Android SDK tools
3. **Android NDK** - Install via Android Studio SDK Manager

**Environment Variables:**

- `JAVA_HOME` - Path to your Java installation
- `NDK_HOME` - Path to Android NDK (e.g., `C:\Users\{username}\AppData\Local\Android\Sdk\ndk\{version}`)
- `PATH` - Must include Android SDK platform-tools and emulator directories

**Automated AVD Setup:**
Use the provided script to create multiple Android Virtual Devices for testing:

```bash
# Setup Android environment and AVDs
bun run windows:android:setup-env      # Configure environment variables
bun run windows:android:setup-avds     # Create test devices
```

This script will:

- Automatically find your Android SDK installation
- Install required system images (API 34, 33)
- Create multiple Pixel device AVDs:
  - Pixel 7 API 34
  - Pixel 6 API 34
  - Pixel 5 API 34
  - Pixel 4 API 34
  - Pixel 3a API 34
  - Pixel 2 API 34

##### Multi-Instance Launching

**Available Commands:**

```bash
# Android Development (Windows host)
bun run windows:android:swarm          # Multiple Android emulators
bun run windows:android:single         # Single Android emulator

# Android Development (macOS host)
bun run macos:android:swarm            # Multiple Android emulators
bun run macos:android:single           # Single Android emulator
```

**Named Parameters:**

```bash
# Windows (PowerShell style with single dash)
bun run windows:android:swarm -- -NumberOfInstances 3 -Sequential $true
bun run windows:android:swarm -- -StartServices $true -NumberOfInstances 4
bun run windows:android:single -- -InstanceId 2 -EmulatorName "Pixel_7_API_34"

# macOS (bash style with double dash)
bun run macos:android:swarm -- --instances 3 --sequential true --services false
bun run macos:ios:swarm -- --instances 2 --sequential false
bun run macos:android:single -- --instance 1 --emulator "Pixel_7_API_34"
bun run macos:ios:single -- --instance 1 --simulator "iPhone 15"
```

**Available Parameters:**

- **Multi-instance scripts**: `instances/NumberOfInstances`, `sequential/Sequential`, `services/StartServices`
- **Single instance scripts**: `instance/InstanceId`, `emulator|simulator/EmulatorName|SimulatorName`

## Testing

The project includes a comprehensive test suite for validating swarm launch scripts across platforms.

### Running Tests

```bash
# Run all tests
bun run test

# Run specific test categories
bun run test:scripts              # All script tests
bun run test:scripts:unit         # Unit tests only
bun run test:scripts:integration  # Integration tests only
bun run test:scripts:e2e          # End-to-end tests (requires appropriate SDKs)

# Run with coverage
bun run test:scripts:coverage
```

### Test Categories

**Unit Tests** (`tests/scripts/unit/`)

- Parameter parsing validation for PowerShell and bash scripts
- Cross-platform parameter consistency checks
- Input validation and error handling

**Integration Tests** (`tests/scripts/integration/`)

- Script execution with mocked Android/iOS tools
- Multi-instance launch orchestration
- Port allocation and device management

**End-to-End Tests** (`tests/scripts/e2e/`)

- Real emulator/simulator launching (disabled by default)
- Requires appropriate SDKs (Android SDK on all platforms, Xcode on macOS)
- Enable with `RUN_E2E_TESTS=true` or `CI=true`

### Platform-Specific Behavior

- **Windows**: PowerShell tests run, bash tests skipped
- **macOS/Linux**: Both PowerShell and bash tests run
- **Test Mode**: All scripts run in dry-run mode to prevent actual emulator launches
- **Mock Tools**: Fake `adb`, `emulator`, and `xcrun` commands for safe testing

### Test Configuration

Tests use sequential execution to prevent resource conflicts and include:

- 30-second timeout for PowerShell script execution
- Automatic test environment setup and cleanup
- Suppressed Docker warnings and external tool noise
- Clean output with minimal logging
