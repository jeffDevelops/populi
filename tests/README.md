# Populi Test Framework

This directory contains the comprehensive test suite for the Populi multi-instance launch scripts and related functionality.

## Test Structure

```
tests/
├── scripts/                    # Script-specific tests
│   ├── unit/                  # Unit tests for individual functions
│   ├── integration/           # Integration tests for script workflows
│   ├── e2e/                   # End-to-end tests (require real devices)
│   └── types/                 # TypeScript type definitions
├── setup.ts                   # Global test setup
└── simple.test.ts             # Basic functionality verification
```

The test suite is organized into three main categories:

### Unit Tests (`tests/scripts/unit/`)

- **Parameter parsing and validation**
- **Port allocation algorithms**
- **Device selection logic**
- **Configuration file handling**

### Integration Tests (`tests/scripts/integration/`)

- **Script execution with mocked tools**
- **Cross-platform behavior verification**
- **Error handling and edge cases**
- **Environment variable processing**

### Script Integration Tests (`tests/scripts/e2e/`)

- **Android/iOS script logic testing with mocked SDKs**
- **Multi-instance parameter validation**
- **Port allocation verification**
- **Error scenario handling**
- **Fast execution (no real emulators launched)**
- **Environment compatibility**

## Running Tests

### All Tests

```bash
bun run test
```

### Script Tests Only

```bash
bun run test:scripts
```

### Specific Test Categories

```bash
# Unit tests
bun run test:scripts:unit

# Integration tests
bun run test:scripts:integration

# Coverage report
bun run test:scripts:coverage

# Watch mode
bun run test:scripts:watch
```

### End-to-End Tests

E2E tests require real Android SDK and/or iOS development tools:

```bash
# Enable E2E tests
RUN_E2E_TESTS=true bun run test:scripts

# Or in CI
CI=true bun run test:scripts
```

## Test Configuration

### Environment Variables

- `RUN_E2E_TESTS=true` - Enable end-to-end tests
- `CI=true` - Enable CI-specific test behavior
- `VITEST=true` - Automatically set during test runs

### Dependencies

- **vitest** - Test framework
- **@vitest/coverage-v8** - Coverage reporting
- **typescript** - TypeScript support
- **@types/node** - Node.js type definitions

## Mock Tools

The test framework includes comprehensive mocking for external tools:

### Android Tools

- **adb** - Android Debug Bridge
- **emulator** - Android Emulator CLI
- **avdmanager** - AVD management

### iOS Tools (macOS only)

- **xcrun** - Xcode command line tools
- **simctl** - iOS Simulator control

### Mock Features

- Realistic command output simulation
- Device state management
- Error condition testing
- Cross-platform compatibility

## Writing Tests

### Basic Test Structure

```typescript
import { describe, it, expect } from 'vitest'

describe('Feature Name', () => {
  it('should test specific behavior', () => {
    // Test implementation
    expect(actualValue).toBe(expectedValue)
  })
})
```

### Using Mock Tools

```typescript
import { setupTestEnvironment } from './integration/mock-tools'

describe('Script Integration', () => {
  let testEnv: TestEnvironment

  beforeEach(() => {
    testEnv = setupTestEnvironment()
  })

  afterEach(() => {
    testEnv.cleanup()
  })

  it('should execute script with mocked tools', () => {
    // Test with mocked adb, emulator, etc.
  })
})
```

### Testing Scripts

```typescript
const result = testPowerShellScript(
  'Launch-Swarm-Android.ps1',
  '-NumberOfInstances 3 -Clean $true'
);

expect(result.success).toBe(true);
expect(result.output).toContain('3');
{{ ... }}
```

## Test Data

### Valid Test Cases

- **Emulator Names**: `Pixel_7_API_34`, `Galaxy_S24_Ultra_API_34`
- **Simulator Names**: `iPhone 15`, `iPad Pro (12.9-inch)`
- **Port Ranges**: 5000-6000 (base: 5000, spacing: 20)
- **Instance Counts**: 1-10 instances

### Invalid Test Cases

- **Invalid Names**: Names with spaces, special characters
- **Invalid Ports**: System ports, out-of-range values
- **Invalid Parameters**: Non-numeric instance counts

## Continuous Integration

### Pre-commit Hooks

Tests run automatically before commits via Husky:

```bash
# .husky/pre-commit
bun run test:scripts:unit
```

### Pre-push Hooks

Full test suite runs before pushes:

```bash
# .husky/pre-push
bun run test:scripts
```

### CI Pipeline

The test framework integrates with CI/CD systems:

- Automatic test execution on pull requests
- Coverage reporting and thresholds
- Cross-platform test validation

## Troubleshooting

### Common Issues

#### Vitest Configuration Errors

- Ensure `vitest.config.ts` is properly configured
- Check for conflicting dependencies
- Verify TypeScript configuration

#### Mock Tool Failures

- Ensure mock binaries have correct permissions
- Check PATH environment variable setup
- Verify temporary directory cleanup

#### E2E Test Failures

- Confirm Android SDK installation
- Verify iOS development tools (macOS)
- Check device/emulator availability

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
DEBUG=true bun run test:scripts
```

## Performance Considerations

### Test Execution Time

- **Unit Tests**: < 5 seconds
- **Integration Tests**: < 30 seconds
- **E2E Tests**: 2-5 minutes per test

### Resource Usage

- Mock tools minimize system resource usage
- Parallel test execution where safe
- Automatic cleanup of temporary files

### Optimization Tips

- Use `--reporter=dot` for faster CI runs
- Skip E2E tests in development with `--exclude tests/e2e`
- Use `--watch` mode for active development

## Contributing

### Adding New Tests

1. Choose appropriate test category (unit/integration/e2e)
2. Follow existing naming conventions
3. Include both positive and negative test cases
4. Add proper cleanup in `afterEach` hooks
5. Update this documentation if needed

### Test Guidelines

- Write descriptive test names
- Test edge cases and error conditions
- Use appropriate assertions (`toBe`, `toContain`, `toMatch`)
- Mock external dependencies appropriately
- Ensure tests are deterministic and repeatable

### Code Coverage

Maintain minimum coverage thresholds:

- **Branches**: 60%
- **Functions**: 60%
- **Lines**: 60%
- **Statements**: 60%

## Related Documentation

- [Script Documentation](../scripts/README.md)
- [Project Setup](../README.md)
- [Development Guidelines](../.windsurf/rules/project-rules.md)
