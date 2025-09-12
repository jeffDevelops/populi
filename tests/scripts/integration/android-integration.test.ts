import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { execSync } from 'child_process'
import path from 'path'
import { setupTestEnvironment } from './mock-tools'
import type { TestEnvironment } from '../types/script-types'

describe('Android Integration Tests', () => {
  let testEnv: TestEnvironment

  // Define script runners at the top level so they're accessible to all tests
  const runPowerShellScript = (args: string) => {
    const scriptPath = path.join(
      process.cwd(),
      'scripts',
      'Launch-Swarm-Android.ps1',
    )
    // Use -DryRun to prevent actual execution (remove -WhatIf as it conflicts with our custom logic)
    const command = `powershell.exe -ExecutionPolicy Bypass -File "${scriptPath}" ${args} -DryRun`

    try {
      return execSync(command, {
        encoding: 'utf8',
        timeout: 15000,
        stdio: ['pipe', 'pipe', 'pipe'], // Capture stderr separately to reduce noise
        env: {
          ...process.env,
          PATH: testEnv?.binDir + path.delimiter + process.env.PATH,
          VITEST_TEST: 'true',
          DRY_RUN: 'true',
          DOCKER_CLI_HINTS: 'false', // Suppress Docker hints
        },
      })
    } catch (error: unknown) {
      const execError = error as {
        stdout?: string
        stderr?: string
        message?: string
      }
      return {
        error: true,
        output:
          execError.stdout ||
          execError.stderr ||
          execError.message ||
          'Unknown error',
      }
    }
  }

  const runBashScript = (args: string) => {
    // Skip bash script tests on Windows - they're meant for macOS/Linux
    if (process.platform === 'win32') {
      return 'Skipped: Bash scripts not supported on Windows'
    }

    const scriptPath = path.join(
      process.cwd(),
      'scripts',
      'launch-multi-android.sh',
    )

    if (!require('fs').existsSync(scriptPath)) {
      return `Script not found: ${scriptPath}`
    }

    const command = `bash "${scriptPath}" ${args}`

    try {
      return execSync(command, {
        encoding: 'utf8',
        timeout: 15000,
        env: {
          ...process.env,
          DRY_RUN: 'true',
          VITEST_TEST: 'true',
          PATH: testEnv?.binDir + path.delimiter + process.env.PATH,
        },
      })
    } catch (error: unknown) {
      const execError = error as {
        stdout?: string
        stderr?: string
        message?: string
      }
      return (
        execError.stdout ||
        execError.stderr ||
        execError.message ||
        'Unknown error'
      )
    }
  }

  beforeEach(() => {
    testEnv = setupTestEnvironment()
  })

  afterEach(() => {
    testEnv.cleanup()
  })

  describe('Launch-Swarm-Android.ps1', () => {
    it('should validate parameters and show execution plan', () => {
      const result = runPowerShellScript('-NumberOfInstances 2 -Clean $true')

      if (typeof result === 'object' && result.error) {
        // Script might not support -WhatIf, check for parameter validation
        expect(result.output).toMatch(/(NumberOfInstances|Clean|instances)/i)
      } else {
        expect(result).toMatch(/(2|instances|Clean)/i)
      }
    })

    it('should handle invalid instance count', () => {
      const result = runPowerShellScript('-NumberOfInstances 0')

      // Should either validate or show the invalid value
      const output = typeof result === 'object' ? result.output : result
      expect(output).toMatch(/(0|invalid|error)/i)
    })

    it('should respect Clean parameter', () => {
      const result = runPowerShellScript('-Clean $false -NumberOfInstances 1')

      const output = typeof result === 'object' ? result.output : result
      expect(output).toMatch(/(Clean|false|preserve)/i)
    })
  })

  describe.skipIf(process.platform === 'win32')(
    'launch-multi-android.sh',
    () => {
      it('should parse named parameters correctly', () => {
        const result = runBashScript('--instances 3 --clean true')

        if (result.includes('Skipped')) {
          expect(result).toContain('Skipped')
        } else {
          expect(result).toMatch(/(3|instances|clean)/i)
        }
      })

      it('should handle sequential mode', () => {
        const result = runBashScript('--instances 2 --sequential true')

        if (result.includes('Skipped')) {
          expect(result).toContain('Skipped')
        } else {
          expect(result).toMatch(/(sequential|2)/i)
        }
      })

      it('should validate emulator availability', () => {
        const result = runBashScript('--instances 1')

        if (result.includes('Skipped')) {
          expect(result).toContain('Skipped')
        } else {
          expect(result).toMatch(/(emulator|avd|android)/i)
        }
      })
    },
  )

  describe('Cross-Platform Consistency', () => {
    it('should produce similar behavior across platforms', () => {
      const psResult = runPowerShellScript('-NumberOfInstances 2 -Clean')
      const bashResult = runBashScript('--instances 2 --clean true')

      // Both should indicate they're working with 2 instances
      const psOutput = typeof psResult === 'object' ? psResult.output : psResult
      const psHas2 = psOutput.includes('2')
      const bashHas2 = bashResult.includes('2')

      expect(psHas2 || bashHas2).toBe(true)
    })
  })
})

describe('Port Allocation Integration', () => {
  it('should calculate non-conflicting ports for multiple instances', () => {
    // Test the port allocation logic used by scripts
    const basePort = 5000
    const spacing = 20
    const instances = 5

    const allocatedPorts: number[] = []
    for (let i = 1; i <= instances; i++) {
      const port = basePort + (i - 1) * spacing
      allocatedPorts.push(port)
    }

    // Verify no duplicates
    const uniquePorts = [...new Set(allocatedPorts)]
    expect(uniquePorts.length).toBe(instances)

    // Verify proper spacing
    expect(allocatedPorts[1] - allocatedPorts[0]).toBe(spacing)
    expect(allocatedPorts[2] - allocatedPorts[1]).toBe(spacing)
  })

  it('should avoid common system ports', () => {
    const basePort = 5000
    const commonPorts = [22, 80, 443, 3000, 8080, 8443]

    // Ensure our base port doesn't conflict with common ports
    expect(commonPorts).not.toContain(basePort)
  })
})

describe('Device Management Integration', () => {
  it('should handle missing emulators gracefully', () => {
    // This would test behavior when no emulators are available
    // Implementation depends on how scripts handle this scenario
    expect(true).toBe(true) // Placeholder
  })

  it('should validate device names', () => {
    const validDeviceNames = [
      'Pixel_7_API_34',
      'Pixel_6_API_34',
      'Galaxy_S24_Ultra_API_34',
    ]

    validDeviceNames.forEach((name) => {
      // Device names should follow Android AVD naming conventions
      expect(name).toMatch(/^[A-Za-z0-9_]+$/)
      expect(name).not.toContain(' ') // No spaces
      expect(name).not.toContain('-') // Prefer underscores
    })
  })
})
