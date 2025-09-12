/**
 * Type definitions for script parameters and configurations
 */

// PowerShell script parameters
export interface PowerShellAndroidParams {
  NumberOfInstances?: number;
  Clean?: boolean;
  Sequential?: boolean;
  StartServices?: boolean;
}

export interface PowerShellSingleAndroidParams {
  InstanceId?: number;
  EmulatorName?: string;
  Clean?: boolean;
}

// Bash script parameters
export interface BashAndroidParams {
  instances?: number;
  clean?: boolean;
  sequential?: boolean;
  services?: boolean;
}

export interface BashSingleAndroidParams {
  instance?: number;
  emulator?: string;
  clean?: boolean;
}

export interface BashIOSParams {
  instances?: number;
  clean?: boolean;
  sequential?: boolean;
  services?: boolean;
}

export interface BashSingleIOSParams {
  instance?: number;
  simulator?: string;
  boot?: boolean;
}

// Mock tool interfaces
export interface MockDevice {
  id: string;
  name: string;
  state: 'online' | 'offline' | 'booted' | 'shutdown';
}

export interface MockAVD {
  name: string;
  target: string;
  path: string;
}

export interface MockSimulator {
  name: string;
  udid: string;
  state: 'Shutdown' | 'Booted' | 'Booting';
  runtime: string;
}

// Test result types
export interface ScriptTestResult {
  success: boolean;
  output: string;
  error?: string;
  exitCode?: number;
}

export interface PortAllocation {
  instance: number;
  serverPort: number;
  hmrPort: number;
}

// Environment setup types
export interface TestEnvironment {
  tempDir: string;
  binDir: string;
  cleanup: () => void;
}

// Script execution options
export interface ScriptExecutionOptions {
  timeout?: number;
  env?: Record<string, string>;
  cwd?: string;
  dryRun?: boolean;
}
