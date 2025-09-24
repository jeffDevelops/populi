#!/usr/bin/env bun

import { watch } from 'fs'
import { existsSync, statSync } from 'fs'
import { join } from 'path'

interface DiagnosticOptions {
  projectRoot: string
  instanceId?: number
}

function parseArgs(): DiagnosticOptions {
  const args = process.argv.slice(2)
  const options: Partial<DiagnosticOptions> = {}

  for (let i = 0; i < args.length; i += 2) {
    const flag = args[i]
    const value = args[i + 1]

    switch (flag) {
      case '--projectRoot':
        options.projectRoot = value
        break
      case '--instance':
        options.instanceId = parseInt(value)
        break
    }
  }

  return {
    projectRoot: options.projectRoot || process.cwd(),
    instanceId: options.instanceId,
  }
}

function checkViteConfig(instanceDir: string) {
  const viteConfigPath = join(instanceDir, 'vite.config.ts')

  if (!existsSync(viteConfigPath)) {
    console.log(`❌ No vite.config.ts found in ${instanceDir}`)
    return false
  }

  console.log(`✅ Found vite.config.ts in ${instanceDir}`)

  // Check if the config has proper HMR settings
  try {
    const fs = require('fs')
    const config = fs.readFileSync(viteConfigPath, 'utf8')

    console.log('\n📄 Vite config preview:')
    console.log(config.split('\n').slice(0, 20).join('\n'))

    if (config.includes('hmr')) {
      console.log('✅ HMR configuration found in vite.config.ts')
    } else {
      console.log('⚠️  No explicit HMR configuration found')
    }

    return true
  } catch (error) {
    console.error(`❌ Error reading vite.config.ts: ${error}`)
    return false
  }
}

function checkFileWatching(sourcePath: string, targetPath: string) {
  console.log(`\n🔍 Testing file watching between:`)
  console.log(`  Source: ${sourcePath}`)
  console.log(`  Target: ${targetPath}`)

  if (!existsSync(sourcePath) || !existsSync(targetPath)) {
    console.log(`❌ One or both paths don't exist`)
    return
  }

  // Watch the target directory (where Vite should be watching)
  const targetWatcher = watch(
    targetPath,
    { recursive: true },
    (eventType, filename) => {
      if (filename) {
        const fullPath = join(targetPath, filename)
        const stats = existsSync(fullPath) ? statSync(fullPath) : null
        console.log(`🎯 TARGET CHANGE: ${eventType} - ${filename}`)
        console.log(`   Full path: ${fullPath}`)
        console.log(`   Exists: ${existsSync(fullPath)}`)
        console.log(`   Size: ${stats ? stats.size : 'N/A'} bytes`)
        console.log(`   Modified: ${stats ? stats.mtime.toISOString() : 'N/A'}`)
      }
    },
  )

  // Watch the source directory (original src)
  const sourceWatcher = watch(
    sourcePath,
    { recursive: true },
    (eventType, filename) => {
      if (filename) {
        console.log(`📁 SOURCE CHANGE: ${eventType} - ${filename}`)
      }
    },
  )

  console.log(
    '👁️  Watching both directories. Make a change to a file in the source directory...',
  )
  console.log('Press Ctrl+C to stop')

  const cleanup = () => {
    console.log('\n🛑 Stopping watchers...')
    targetWatcher.close()
    sourceWatcher.close()
    process.exit(0)
  }

  process.on('SIGINT', cleanup)
  process.on('SIGTERM', cleanup)
}

function checkProcesses(instanceId: number) {
  console.log(`\n🔍 Checking processes for instance ${instanceId}...`)

  // Use child_process to run lsof and ps commands
  const { spawn } = require('child_process')

  // Check for Vite processes
  const checkVite = spawn('ps', ['aux'], { stdio: 'pipe' })

  checkVite.stdout.on('data', (data: Buffer) => {
    const output = data.toString()
    const viteLines = output
      .split('\n')
      .filter(
        (line) =>
          line.includes('vite') ||
          line.includes('tauri') ||
          line.includes(`instance-${instanceId}`),
      )

    if (viteLines.length > 0) {
      console.log('🏃 Found relevant processes:')
      viteLines.forEach((line) => console.log(`  ${line}`))
    } else {
      console.log('❌ No Vite/Tauri processes found for this instance')
    }
  })

  // Check what's listening on the expected ports
  const expectedPort = 1420 + instanceId * 10
  const hmrPort = expectedPort + 1

  console.log(`🔌 Expected ports: ${expectedPort} (main), ${hmrPort} (HMR)`)

  const checkPorts = spawn('lsof', ['-i', `tcp:${expectedPort}`], {
    stdio: 'pipe',
  })

  checkPorts.stdout.on('data', (data: Buffer) => {
    console.log(`✅ Port ${expectedPort} is in use:`)
    console.log(data.toString())
  })

  checkPorts.stderr.on('data', () => {
    console.log(`❌ Nothing listening on port ${expectedPort}`)
  })

  const checkHMRPorts = spawn('lsof', ['-i', `tcp:${hmrPort}`], {
    stdio: 'pipe',
  })

  checkHMRPorts.stdout.on('data', (data: Buffer) => {
    console.log(`✅ HMR port ${hmrPort} is in use:`)
    console.log(data.toString())
  })

  checkHMRPorts.stderr.on('data', () => {
    console.log(`❌ Nothing listening on HMR port ${hmrPort}`)
  })
}

function main() {
  const options = parseArgs()

  console.log('🔧 HMR Diagnostic Tool')
  console.log('=====================================')
  console.log(`Project root: ${options.projectRoot}`)

  const sourcePath = join(options.projectRoot, 'apps/tauri/src')
  const swarmDir = join(options.projectRoot, 'swarm/ios')

  if (!existsSync(sourcePath)) {
    console.error(`❌ Source directory not found: ${sourcePath}`)
    process.exit(1)
  }

  if (!existsSync(swarmDir)) {
    console.error(`❌ Swarm directory not found: ${swarmDir}`)
    process.exit(1)
  }

  console.log('\n1️⃣ Checking swarm instance directories...')

  const instances = []
  for (let i = 0; i < 10; i++) {
    const instanceDir = join(swarmDir, `instance-${i}`)
    if (existsSync(instanceDir)) {
      instances.push(i)
      console.log(`✅ Found instance-${i}`)

      const instanceSrcDir = join(instanceDir, 'src')
      if (existsSync(instanceSrcDir)) {
        console.log(`   ✅ Has src directory`)

        // Check if files are actually there
        const { readdirSync } = require('fs')
        try {
          const files = readdirSync(instanceSrcDir)
          console.log(`   📁 Contains ${files.length} files/directories`)
        } catch (error) {
          console.log(`   ❌ Error reading src directory: ${error}`)
        }
      } else {
        console.log(`   ❌ Missing src directory`)
      }

      // Check Vite config
      checkViteConfig(instanceDir)
    }
  }

  if (instances.length === 0) {
    console.error('❌ No swarm instances found')
    process.exit(1)
  }

  if (options.instanceId !== undefined) {
    if (instances.includes(options.instanceId)) {
      console.log(`\n2️⃣ Detailed check for instance ${options.instanceId}`)
      checkProcesses(options.instanceId)

      const targetPath = join(swarmDir, `instance-${options.instanceId}/src`)
      console.log(
        `\n3️⃣ Testing file watching for instance ${options.instanceId}`,
      )
      checkFileWatching(sourcePath, targetPath)
    } else {
      console.error(`❌ Instance ${options.instanceId} not found`)
      process.exit(1)
    }
  } else {
    console.log(
      `\n💡 Found ${instances.length} instances: ${instances.join(', ')}`,
    )
    console.log('Run with --instance <number> to test a specific instance')
    console.log('Example: bun diagnostic.ts --instance 0')
  }
}

main()
