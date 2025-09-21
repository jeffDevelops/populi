import { defineConfig } from 'vite'
import { sveltekit } from '@sveltejs/kit/vite'
import type { LogLevel } from 'vite'

const host = process.env.TAURI_DEV_HOST

// Get port configuration from environment variables or use defaults
const serverPort = parseInt(
  process.env.VITE_INSTANCE_DEV_SERVER_PORT || '1420',
  10,
)
const hmrPort = parseInt(process.env.VITE_INSTANCE_DEV_HMR_PORT || '1421', 10)

// https://vite.dev/config/
export default defineConfig({
  plugins: [sveltekit()],

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent Vite from obscuring rust errors
  clearScreen: false,
  // 2. configure port dynamically based on environment variables
  server: {
    port: serverPort,
    strictPort: true,
    host: '0.0.0.0', // Always bind to all interfaces for multi-instance support
    hmr: host
      ? {
          protocol: 'ws',
          host,
          port: hmrPort,
        }
      : {
          protocol: 'ws',
          host: '0.0.0.0', // Use 0.0.0.0 for Windows when no TAURI_DEV_HOST is set
          port: hmrPort,
        },
    watch: {
      // 3. tell Vite to ignore watching `src-tauri`
      ignored: ['**/src-tauri/**'],

      // 4. AGGRESSIVE file watching for external sync processes
      usePolling: true,
      interval: 100, // Poll every 100ms (more aggressive)

      // Additional options for better file watching
      followSymlinks: true,
      depth: 99,

      // Force watching of all files in src
      // include: ['src/**/*'],

      // Specific chokidar options for better external file sync detection
      awaitWriteFinish: {
        stabilityThreshold: 100,
        pollInterval: 50,
      },

      // Enable atomic writes detection
      atomic: true,
    },

    // Force full page reload for any changes (fallback if HMR fails)
    middlewareMode: false,
  },

  // Environment prefix for Vite
  envPrefix: ['VITE_', 'TAURI_'],

  // Build configuration
  build: {
    // Tauri supports es2021
    target: process.env.TAURI_PLATFORM == 'windows' ? 'chrome105' : 'safari13',

    // Don't minify for debug builds
    minify: !process.env.TAURI_DEBUG ? 'esbuild' : false,

    // Produce sourcemaps for debug builds
    sourcemap: !!process.env.TAURI_DEBUG,
  },

  // Dependency optimization for better HMR
  optimizeDeps: {
    // Force Vite to re-bundle dependencies when they change
    force: true,

    // Include SvelteKit dependencies that might cause HMR issues
    include: ['@sveltejs/kit', 'svelte', 'svelte/store'],
  },

  // CSS configuration
  css: {
    // Enable CSS source maps for better debugging
    devSourcemap: true,
  },

  // Enhanced logging for HMR debugging - use proper LogLevel type
  logLevel: 'info' as LogLevel,

  // Define environment variables for better debugging
  define: {
    'process.env.VITE_INSTANCE_ID': JSON.stringify(
      process.env.VITE_INSTANCE_ID || '0',
    ),
  },

  // Enable experimental features that might help with HMR
  experimental: {
    hmrPartialAccept: false, // Force full reload instead of partial HMR
  },
})
