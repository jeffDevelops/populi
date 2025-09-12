import { beforeAll, afterAll } from 'vitest'
import fs from 'fs'
import path from 'path'

// Global test setup
beforeAll(() => {
  // Ensure test directories exist
  const testDirs = ['tests/temp', 'tests/fixtures', 'tests/coverage']

  testDirs.forEach((dir) => {
    const fullPath = path.join(process.cwd(), dir)
    if (!fs.existsSync(fullPath)) {
      fs.mkdirSync(fullPath, { recursive: true })
    }
  })

  // Set test environment variables
  process.env.NODE_ENV = 'test'
  process.env.VITEST = 'true'

  console.log('Test environment initialized')
})

// Global test cleanup
afterAll(() => {
  // Clean up temporary test files
  const tempDir = path.join(process.cwd(), 'tests', 'temp')
  if (fs.existsSync(tempDir)) {
    fs.rmSync(tempDir, { recursive: true, force: true })
  }

  console.log('Test environment cleaned up')
})
