import fs from 'fs'
import path from 'path'
import type {
  MockDevice,
  MockAVD,
  MockSimulator,
  TestEnvironment,
} from '../types/script-types'

/**
 * Mock implementations of external tools for testing
 */

export class MockADB {
  private mockDevices: MockDevice[] = [
    { id: 'emulator-5554', name: 'Pixel_7_API_34', state: 'online' },
    { id: 'emulator-5556', name: 'Pixel_6_API_34', state: 'online' },
  ]

  devices(): string {
    return this.mockDevices.map((device) => `${device.id}\tdevice`).join('\n')
  }

  killServer(): string {
    return 'killed adb server'
  }

  startServer(): string {
    return 'started adb server'
  }

  addDevice(deviceId: string, name: string): void {
    if (!this.mockDevices.find((d) => d.id === deviceId)) {
      this.mockDevices.push({ id: deviceId, name, state: 'online' })
    }
  }

  removeDevice(deviceId: string): void {
    this.mockDevices = this.mockDevices.filter((d) => d.id !== deviceId)
  }

  getDevices(): MockDevice[] {
    return [...this.mockDevices]
  }
}

export class MockEmulator {
  private availableAVDs: MockAVD[] = [
    { name: 'Pixel_7_API_34', target: 'android-34', path: '/path/to/pixel7' },
    { name: 'Pixel_6_API_34', target: 'android-34', path: '/path/to/pixel6' },
    { name: 'Pixel_5_API_34', target: 'android-34', path: '/path/to/pixel5' },
    { name: 'Pixel_4_API_34', target: 'android-34', path: '/path/to/pixel4' },
  ]

  private runningEmulators = new Map<number, string>()

  listAvd(): string {
    return this.availableAVDs.map((avd) => `Name: ${avd.name}`).join('\n')
  }

  boot(avdName: string, port: number = 5554): string {
    const avd = this.availableAVDs.find((a) => a.name === avdName)
    if (!avd) {
      throw new Error(`AVD ${avdName} not found`)
    }

    this.runningEmulators.set(port, avdName)
    return `Emulator ${avdName} starting on port ${port}`
  }

  kill(port: number): string {
    this.runningEmulators.delete(port)
    return `Emulator on port ${port} killed`
  }

  isRunning(port: number): boolean {
    return this.runningEmulators.has(port)
  }

  getAvailableAVDs(): MockAVD[] {
    return [...this.availableAVDs]
  }

  addAVD(avd: MockAVD): void {
    if (!this.availableAVDs.find((a) => a.name === avd.name)) {
      this.availableAVDs.push(avd)
    }
  }
}

export class MockXcrun {
  private availableSimulators: MockSimulator[] = [
    {
      name: 'iPhone 15',
      udid: 'ABC123',
      state: 'Shutdown',
      runtime: 'iOS 17.0',
    },
    {
      name: 'iPhone 14',
      udid: 'DEF456',
      state: 'Shutdown',
      runtime: 'iOS 17.0',
    },
    {
      name: 'iPad Pro',
      udid: 'GHI789',
      state: 'Shutdown',
      runtime: 'iOS 17.0',
    },
  ]

  listDevices(): string {
    return this.availableSimulators
      .map((sim) => `${sim.name} (${sim.udid}) (${sim.state})`)
      .join('\n')
  }

  boot(udid: string): string {
    const sim = this.availableSimulators.find((s) => s.udid === udid)
    if (!sim) {
      throw new Error(`Simulator ${udid} not found`)
    }
    sim.state = 'Booted'
    return `Simulator ${sim.name} booted`
  }

  shutdown(udid: string): string {
    const sim = this.availableSimulators.find((s) => s.udid === udid)
    if (sim) {
      sim.state = 'Shutdown'
    }
    return `Simulator shutdown`
  }

  getAvailableSimulators(): MockSimulator[] {
    return [...this.availableSimulators]
  }

  addSimulator(simulator: MockSimulator): void {
    if (!this.availableSimulators.find((s) => s.udid === simulator.udid)) {
      this.availableSimulators.push(simulator)
    }
  }
}

/**
 * Creates mock binaries in a temporary directory for testing
 */
export function createMockBinaries(tempDir: string): string {
  const binDir = path.join(tempDir, 'bin')
  fs.mkdirSync(binDir, { recursive: true })

  const isWindows = process.platform === 'win32'

  // Mock adb
  const adbScript = isWindows
    ? `@echo off
if "%1"=="devices" (
  echo List of devices attached
  echo emulator-5554	device
  echo emulator-5556	device
) else if "%1"=="kill-server" (
  echo killed adb server
) else if "%1"=="start-server" (
  echo started adb server
)`
    : `#!/bin/bash
case "$1" in
  "devices")
    echo "List of devices attached"
    echo "emulator-5554	device"
    echo "emulator-5556	device"
    ;;
  "kill-server")
    echo "killed adb server"
    ;;
  "start-server")
    echo "started adb server"
    ;;
esac`

  const adbPath = path.join(binDir, isWindows ? 'adb.bat' : 'adb')
  fs.writeFileSync(adbPath, adbScript)
  if (!isWindows) {
    fs.chmodSync(adbPath, '755')
  }

  // Mock emulator
  const emulatorScript = isWindows
    ? `@echo off
if "%1"=="-list-avds" (
  echo Pixel_7_API_34
  echo Pixel_6_API_34
  echo Pixel_5_API_34
) else (
  echo Starting emulator %*
)`
    : `#!/bin/bash
if [ "$1" = "-list-avds" ]; then
  echo "Pixel_7_API_34"
  echo "Pixel_6_API_34" 
  echo "Pixel_5_API_34"
else
  echo "Starting emulator $*"
fi`

  const emulatorPath = path.join(
    binDir,
    isWindows ? 'emulator.bat' : 'emulator',
  )
  fs.writeFileSync(emulatorPath, emulatorScript)
  if (!isWindows) {
    fs.chmodSync(emulatorPath, '755')
  }

  // Mock xcrun (macOS only)
  if (process.platform === 'darwin') {
    const xcrunScript = `#!/bin/bash
if [ "$1" = "simctl" ] && [ "$2" = "list" ] && [ "$3" = "devices" ]; then
  echo "== Devices =="
  echo "-- iOS 17.0 --"
  echo "iPhone 15 (ABC123) (Shutdown)"
  echo "iPhone 14 (DEF456) (Shutdown)"
  echo "iPad Pro (GHI789) (Shutdown)"
elif [ "$1" = "simctl" ] && [ "$2" = "boot" ]; then
  echo "Simulator booted: $3"
fi`

    const xcrunPath = path.join(binDir, 'xcrun')
    fs.writeFileSync(xcrunPath, xcrunScript)
    fs.chmodSync(xcrunPath, '755')
  }

  return binDir
}

/**
 * Test environment setup helper with proper TypeScript typing
 */
export function setupTestEnvironment(): TestEnvironment {
  const tempDir = fs.mkdtempSync(path.join(process.cwd(), 'temp-test-'))
  const binDir = createMockBinaries(tempDir)

  // Add mock binaries to PATH for this test
  const originalPath = process.env.PATH
  process.env.PATH = `${binDir}${path.delimiter}${originalPath}`

  return {
    tempDir,
    binDir,
    cleanup: () => {
      process.env.PATH = originalPath
      fs.rmSync(tempDir, { recursive: true, force: true })
    },
  }
}

/**
 * Utility functions for test assertions
 */
export class TestUtils {
  static isValidPort(port: number): boolean {
    return port >= 1024 && port <= 65535
  }

  static isValidEmulatorName(name: string): boolean {
    return /^[A-Za-z0-9_]+$/.test(name) && name.length > 0
  }

  static isValidSimulatorName(name: string): boolean {
    return typeof name === 'string' && name.length > 0
  }

  static parsePortFromOutput(output: string): number | null {
    const portMatch = output.match(/port[:\s]+(\d+)/i)
    return portMatch ? parseInt(portMatch[1], 10) : null
  }

  static extractInstanceIdFromOutput(output: string): number | null {
    const instanceMatch = output.match(/instance[:\s]+(\d+)/i)
    return instanceMatch ? parseInt(instanceMatch[1], 10) : null
  }
}
