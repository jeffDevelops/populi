import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    exclude: [], // All tests now run as integration tests with mocks
    setupFiles: ['tests/setup.ts'],
    testTimeout: 30000, // 30 seconds timeout for integration tests
    // Run tests sequentially to avoid resource conflicts
    pool: 'forks',
    poolOptions: {
      forks: {
        singleFork: true,
        isolate: false // Prevent worker isolation issues with long-running E2E tests
      }
    },
    maxConcurrency: 1,
    reporters: [['default', { summary: false }]], // Use default reporter without summary for cleaner output
    silent: false, // Keep test output visible but reduce noise
    logHeapUsage: false // Disable heap usage logging
  }
});
