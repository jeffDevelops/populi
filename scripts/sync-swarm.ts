#!/usr/bin/env bun

import { watch } from 'fs'
import { spawn } from 'child_process'
import { existsSync, mkdirSync } from 'fs'
import { join } from 'path'

interface SyncOptions {
  targetOS: 'macOS' | 'iOS' | 'Android' | 'Windows'
  hostOS: 'macOS' | 'Windows'
  numInstances: number
  projectRoot: string
}

function parseArgs(): SyncOptions {
  const args = process.argv.slice(2)
  const options: Partial<SyncOptions> = {}

  for (let i = 0; i < args.length; i += 2) {
    const flag = args[i]
    const value = args[i + 1]

    switch (flag) {
      case '--targetOS':
        options.targetOS = value as SyncOptions['targetOS']
        break
      case '--hostOS':
        options.hostOS = value as SyncOptions['hostOS']
        break
      case '--instances':
        options.numInstances = parseInt(value)
        break
      case '--projectRoot':
        options.projectRoot = value
        break
    }
  }

  if (!options.targetOS || !options.hostOS) {
    console.error('Required: --targetOS and --hostOS')
    process.exit(1)
  }

  return {
    targetOS: options.targetOS,
    hostOS: options.hostOS,
    numInstances: options.numInstances || 3,
    projectRoot: options.projectRoot || process.cwd(),
  }
}

// Add debouncing to prevent excessive syncing
let syncTimeout: NodeJS.Timeout | null = null
const SYNC_DEBOUNCE_MS = 500

function debouncedSync(options: SyncOptions) {
  if (syncTimeout) {
    clearTimeout(syncTimeout)
  }

  syncTimeout = setTimeout(() => {
    syncToInstances(options)
  }, SYNC_DEBOUNCE_MS)
}

async function syncToInstances(options: SyncOptions): Promise<void> {
  const sourcePath = join(options.projectRoot, 'apps/tauri/src')
  const swarmDir = join(
    options.projectRoot,
    'swarm',
    options.targetOS.toLowerCase(),
  )

  console.log(
    `\n🔄 Syncing src/ changes to ${options.numInstances} instances...`,
  )
  console.log(`Source: ${sourcePath}`)
  console.log(`Target: ${swarmDir}`)

  if (!existsSync(sourcePath)) {
    console.error(`❌ Source directory doesn't exist: ${sourcePath}`)
    return
  }

  if (!existsSync(swarmDir)) {
    console.error(`❌ Swarm directory doesn't exist: ${swarmDir}`)
    return
  }

  const syncPromises: Promise<{
    instance: number
    success: boolean
    error?: string
  }>[] = []

  for (let i = 0; i < options.numInstances; i++) {
    const instanceDir = join(swarmDir, `instance-${i}`)
    const instanceSrcDir = join(instanceDir, 'src')

    if (!existsSync(instanceDir)) {
      console.log(`⚠️  Instance ${i} directory doesn't exist, skipping...`)
      continue
    }

    // Ensure the src directory exists in the instance
    if (!existsSync(instanceSrcDir)) {
      console.log(`📁 Creating src directory for instance-${i}`)
      mkdirSync(instanceSrcDir, { recursive: true })
    }

    const syncPromise = new Promise<{
      instance: number
      success: boolean
      error?: string
    }>((resolve) => {
      const command = options.hostOS === 'Windows' ? 'robocopy' : 'rsync'
      const args =
        options.hostOS === 'Windows'
          ? [
              sourcePath,
              instanceSrcDir,
              '/MIR',
              '/NFL',
              '/NDL',
              '/NJH',
              '/NJS',
              '/R:1',
              '/W:1',
            ]
          : [
              '-av',
              '--delete',
              '--timeout=30',
              '--exclude=node_modules/',
              '--exclude=.DS_Store',
              '--exclude=*.log',
              '--exclude=.vite/',
              '--exclude=dist/',
              `${sourcePath}/`,
              `${instanceSrcDir}/`,
            ]

      console.log(`🚀 Starting sync for instance-${i}`)
      console.log(`Command: ${command} ${args.join(' ')}`)

      const syncProcess = spawn(command, args, {
        stdio: ['ignore', 'pipe', 'pipe'],
        timeout: 30000, // 30 second timeout
      })

      let stdout = ''
      let stderr = ''

      syncProcess.stdout?.on('data', (data) => {
        stdout += data.toString()
      })

      syncProcess.stderr?.on('data', (data) => {
        stderr += data.toString()
      })

      syncProcess.on('close', (code, signal) => {
        const success =
          options.hostOS === 'Windows'
            ? code === 0 || code === 1 // robocopy codes 0-1 are success
            : code === 0

        if (success) {
          console.log(`✅ Successfully synced to instance-${i}`)
          resolve({ instance: i, success: true })
        } else {
          const error = `Exit code: ${code}, Signal: ${signal}\nSTDOUT: ${stdout}\nSTDERR: ${stderr}`
          console.error(`❌ Failed to sync to instance-${i}`)
          console.error(`   Error details: ${error}`)
          resolve({ instance: i, success: false, error })
        }
      })

      syncProcess.on('error', (error) => {
        console.error(`❌ Process error for instance-${i}: ${error.message}`)
        resolve({ instance: i, success: false, error: error.message })
      })

      // Handle timeout
      syncProcess.on('spawn', () => {
        setTimeout(() => {
          if (!syncProcess.killed) {
            console.warn(`⏱️  Timeout: Killing sync process for instance-${i}`)
            syncProcess.kill('SIGKILL')
            resolve({ instance: i, success: false, error: 'Timeout' })
          }
        }, 30000)
      })
    })

    syncPromises.push(syncPromise)
  }

  // Wait for all syncs to complete
  const results = await Promise.all(syncPromises)

  const successful = results.filter((r) => r.success).length
  const failed = results.filter((r) => !r.success).length

  console.log(`\n📊 Sync Summary: ${successful} successful, ${failed} failed`)

  if (failed > 0) {
    console.log('Failed instances:')
    results
      .filter((r) => !r.success)
      .forEach((r) => {
        console.log(`  - Instance ${r.instance}: ${r.error || 'Unknown error'}`)
      })
  }
}

function main() {
  const options = parseArgs()
  const sourcePath = join(options.projectRoot, 'apps/tauri/src')

  console.log('🔍 Validating configuration...')
  console.log(`Project root: ${options.projectRoot}`)
  console.log(`Source path: ${sourcePath}`)
  console.log(`Target OS: ${options.targetOS}`)
  console.log(`Host OS: ${options.hostOS}`)
  console.log(`Instances: ${options.numInstances}`)

  if (!existsSync(sourcePath)) {
    console.error(`❌ Source directory doesn't exist: ${sourcePath}`)
    process.exit(1)
  }

  const swarmDir = join(
    options.projectRoot,
    'swarm',
    options.targetOS.toLowerCase(),
  )
  if (!existsSync(swarmDir)) {
    console.error(`❌ Swarm directory doesn't exist: ${swarmDir}`)
    console.error(`   Make sure you've run the iOS swarm script first`)
    process.exit(1)
  }

  console.log(`\n👁️  Watching ${sourcePath} for changes...`)

  // Initial sync
  console.log('🚀 Performing initial sync...')
  syncToInstances(options)

  // Watch for changes with better filtering
  const watcher = watch(
    sourcePath,
    { recursive: true },
    (eventType, filename) => {
      if (filename) {
        // Filter out irrelevant files
        const ignoredExtensions = ['.log', '.tmp', '.swp', '.DS_Store']
        const ignoredDirs = ['node_modules', '.git', '.vite', 'dist']

        const shouldIgnore =
          ignoredExtensions.some((ext) => filename.endsWith(ext)) ||
          ignoredDirs.some((dir) => filename.includes(dir))

        if (!shouldIgnore) {
          console.log(`📝 File changed: ${filename} (${eventType})`)
          debouncedSync(options)
        }
      }
    },
  )

  // Enhanced cleanup
  const cleanup = () => {
    console.log('\n🛑 Stopping file watcher...')
    if (syncTimeout) {
      clearTimeout(syncTimeout)
    }
    watcher.close()
    console.log('✅ Cleanup complete')
    process.exit(0)
  }

  process.on('SIGINT', cleanup)
  process.on('SIGTERM', cleanup)
  process.on('uncaughtException', (error) => {
    console.error('💥 Uncaught exception:', error)
    cleanup()
  })

  process.on('unhandledRejection', (reason, promise) => {
    console.error('💥 Unhandled rejection at:', promise, 'reason:', reason)
    cleanup()
  })

  console.log('✅ File watcher started. Press Ctrl+C to stop.')
}

main()
