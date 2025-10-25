# Test Suite for semhl.nvim

## Running Tests

Use the test runner from the project root:

```bash
./run_tests.sh
```

## Test Files

### Unit Tests (Fast)
- **`semhl_spec.lua`** - Basic module loading and color generation tests
  - Can run in headless mode
  - Tests core color generation logic
  - Tests module API

### Integration Tests (Require Full Neovim)
The following tests require a full Neovim instance with UI capabilities and are currently **NOT suitable for headless testing**:

- **`buffer_lifecycle_spec.lua`** - Buffer lifecycle and cleanup tests
- **`highlighting_spec.lua`** - Core highlighting functionality tests
- **`background_colors_spec.lua`** - Background-aware color generation tests
- **`integration_spec.lua`** - Real-world usage scenarios

These tests perform operations like:
- Creating and manipulating buffers
- Setting extmarks
- Triggering autocommands
- Waiting for async operations

## Running Integration Tests Manually

To test integration features, you'll need to:

1. Start Neovim normally (not headless)
2. Install the plugin locally
3. Use `:source test/integration_spec.lua` or similar

Or use a tool like [vusted](https://github.com/notomo/vusted) which provides better support for testing Neovim plugins with UI operations.

## Current Status

✅ **Unit tests** (`semhl_spec.lua`) - **WORKING** (12/12 passing)
  - ✅ Module loading (semhl, color_generator)
  - ✅ API function existence checks
  - ✅ Color generation (HSV to RGB)
  - ✅ Color validation (hex format, RGB ranges)
  - ✅ Color uniqueness
  - ✅ Hue ceiling handling
  - ✅ Parameter handling (nil values)
  - ✅ Setup functions
  - ✅ Background cache functions

⚠️  **Integration tests** (`test/manual/`) - **For manual testing only**
  - Tests exist but may have timing issues in headless mode
  - Most tests pass (~35/37) but some have race conditions
  - Use `./run_tests.sh --all` to run them
  - Best tested in a real Neovim instance

## Contributing

When adding new tests:
- Add unit tests to `semhl_spec.lua` for testable logic
- Integration tests are kept for documentation but may not run automatically
- Consider using mocks for Neovim APIs when possible
