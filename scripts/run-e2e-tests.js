#!/usr/bin/env node

/**
 * Cross-platform E2E test runner
 * Handles platform-specific environment variable setting and test execution
 */

const { spawn } = require('child_process');
const process = require('process');

function runCommand(command, args, env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: 'inherit',
      env: { ...process.env, ...env },
      shell: true
    });

    child.on('close', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`Command failed with exit code ${code}`));
      }
    });

    child.on('error', (error) => {
      reject(error);
    });
  });
}

async function runE2ETests() {
  console.log('Running comprehensive test suite with E2E tests...');
  
  try {
    // Set environment variable and run tests
    await runCommand('bun', ['run', 'test'], {
      RUN_E2E_TESTS: 'true'
    });
    
    console.log('All tests passed! ✅');
  } catch (error) {
    console.error('Tests failed! ❌');
    console.error(error.message);
    process.exit(1);
  }
}

// Run the tests
runE2ETests();
