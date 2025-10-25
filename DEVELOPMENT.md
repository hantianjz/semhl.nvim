# Development Guide for semhl.nvim

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Running Tests](#running-tests)
- [Configuration Parameters](#configuration-parameters)
- [Event Flow Diagrams](#event-flow-diagrams)
- [Code Structure](#code-structure)
- [Debugging](#debugging)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         semhl.nvim                                   │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │   semhl.lua  │───▶│color_generator│───▶│   cielab.lua │          │
│  │   (Main)     │    │     .lua      │    │ (LAB Colors) │          │
│  └──────┬───────┘    └───────┬───────┘    └──────────────┘          │
│         │                    │                                        │
│         │                    ▼                                        │
│         │            ┌──────────────┐    ┌──────────────┐           │
│         │            │cache_manager │    │ plenary.log  │           │
│         │            │     .lua      │    │  (Logging)   │           │
│         │            └──────────────┘    └──────────────┘           │
│         ▼                                                             │
│  ┌──────────────────────────────────────────────────┐               │
│  │            Neovim Core Components                 │               │
│  ├────────────────────────────────────────────────────┤              │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐ │               │
│  │  │Tree-sitter │  │  Extmarks  │  │ Autocommands│ │               │
│  │  │  Parser    │  │    API     │  │    API      │ │               │
│  │  └────────────┘  └────────────┘  └────────────┘ │               │
│  └──────────────────────────────────────────────────┘               │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘

Key Components:
- semhl.lua: Main plugin logic, buffer management, event handling
- color_generator.lua: LAB-based color generation with Delta-E validation
- cielab.lua: CIELAB color space conversions (RGB ↔ LAB, Delta-E calculation)
- cache_manager.lua: Persistent cache I/O for identifier → color mappings
- Tree-sitter: Parses code to identify identifiers
- Extmarks: Applies highlighting to buffer ranges
- Autocommands: Triggers on FileType, BufEnter, OptionSet events
```

## Running Tests

### Quick Start
```bash
# From plugin root directory, run with default nvim
./run_tests.sh

# Or specify a custom Neovim binary
./run_tests.sh /usr/local/bin/nvim
./run_tests.sh ~/neovim/build/bin/nvim
```

### Test Runner Details

The `run_tests.sh` script:
- Automatically installs plenary.nvim if needed (in `/tmp/semhl-test/`)
- Sets up the proper Neovim environment
- Runs all tests in the `test/` directory
- Reports pass/fail status with exit codes

**Usage:**
```bash
./run_tests.sh [nvim_path]
```

**Arguments:**
- `nvim_path` (optional): Path to Neovim binary. Default: `nvim`

**Examples:**
```bash
# Use system nvim
./run_tests.sh

# Use custom build
./run_tests.sh ~/builds/neovim/bin/nvim

# Use specific version
./run_tests.sh /opt/nvim-0.10/bin/nvim
```

### Manual Test Execution

If you need more control, you can run tests manually with Neovim:

```bash
# Run all tests
nvim --headless --noplugin -u test/minimal_init.lua \
  -c "PlenaryBustedDirectory test/"

# Run specific test file
nvim --headless --noplugin -u test/minimal_init.lua \
  -c "PlenaryBustedFile test/semhl_spec.lua"
```

### Test Files

**Unit Tests** (run automatically):
- `test/semhl_spec.lua` - Basic module loading and color generation tests (12 tests)

**Manual/Integration Tests** (require `--all` flag):
- `test/manual/buffer_lifecycle_spec.lua` - Buffer lifecycle and cleanup tests
- `test/manual/highlighting_spec.lua` - Core highlighting functionality tests
- `test/manual/background_colors_spec.lua` - Background-aware color generation tests
- `test/manual/integration_spec.lua` - Real-world usage scenarios and edge cases

**Note:** Manual tests perform buffer operations and may have timing issues in headless mode. They are kept for documentation and manual testing purposes.

### Writing New Tests
```lua
-- test/example_spec.lua
describe("feature name", function()
  before_each(function()
    -- Setup code
  end)

  after_each(function()
    -- Cleanup code
  end)

  it("should do something", function()
    -- Test assertions
    assert.is_true(condition)
    assert.equals(expected, actual)
    assert.has_no.errors(function()
      -- code that should not error
    end)
  end)
end)
```

## Configuration Parameters

### Parameter Reference Table

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `filetypes` | table | `{}` | File types to enable highlighting for |
| `min_delta_e` | number | `5` | Minimum perceptual color difference from background |
| `target_delta_e` | number | `15` | Target Delta-E distance for color generation |
| `L_min` | number | `nil` (auto) | Minimum lightness (0-100, auto-detected based on background) |
| `L_max` | number | `nil` (auto) | Maximum lightness (0-100, auto-detected based on background) |
| `max_file_size` | number | `100*1024` | Maximum file size in bytes to process |
| `disable` | function | `semhl_check_file_size` | Custom disable check function |

### Configuration Flow
```
setup(opt)
    │
    ├─▶ opt.filetypes ──────▶ Creates FileType autocommands
    │
    ├─▶ opt.min_delta_e ────▶ color_generator.setup()
    │                          └─▶ Minimum Delta-E threshold
    │
    ├─▶ opt.target_delta_e ─▶ color_generator.setup()
    │                          └─▶ Target Delta-E for generation
    │
    ├─▶ opt.L_min ──────────▶ color_generator.setup()
    │                          └─▶ Minimum lightness constraint
    │
    ├─▶ opt.L_max ──────────▶ color_generator.setup()
    │                          └─▶ Maximum lightness constraint
    │
    ├─▶ opt.max_file_size ───▶ M._MAX_FILE_SIZE
    │                          └─▶ Checked in semhl_check_file_size()
    │
    └─▶ opt.disable ─────────▶ M._DISABLE_CHECK_FUNC
                               └─▶ Called in semhl_on_buffer_enter()
```

### Parameter Details

#### `filetypes` (semhl.lua:355-358)
```lua
-- Creates autocommands for specified file types
if opt.filetypes and next(opt.filetypes) then
  vim.api.nvim_create_autocmd({ "FileType" },
    { pattern = opt.filetypes, callback = semhl_autoload, group = M._semhl_augup })
end
```

#### `adaptive_colors` (color_generator.lua:71-130)
```lua
-- Determines color generation parameters based on background
if M._adaptive_colors then
  if is_dark then
    -- Use bright colors for dark backgrounds
    saturate_floor = _DARK_SATURATE_FLOOR  -- 0.75
    value_floor = _DARK_VALUE_FLOOR        -- 0.75
  else
    -- Use darker colors for light backgrounds
    saturate_floor = _LIGHT_SATURATE_FLOOR  -- 0.35
    value_floor = _LIGHT_VALUE_FLOOR        -- 0.25
  end
end
```

#### `max_file_size` (semhl.lua:22-31)
```lua
-- Prevents processing of large files
local function semhl_check_file_size(buffer)
  local ok, stats = pcall(vim.loop.fs_stat, buffer_name)
  if ok and stats and stats.size > M._MAX_FILE_SIZE then
    return true  -- Skip this file
  end
  return false
end
```

## Event Flow Diagrams

### 1. Plugin Initialization Flow
```
User calls setup()
        │
        ▼
┌──────────────────┐
│   M.setup()      │
└──────┬───────────┘
       │
       ├─▶ Create namespace (M._ns)
       │
       ├─▶ Create augroup (M._semhl_augup)
       │
       ├─▶ Register user commands
       │   ├─▶ SemhlLoad
       │   └─▶ SemhlUnload
       │
       ├─▶ Setup color generator
       │   └─▶ color_gen.setup(min_delta_e, target_delta_e, L_min, L_max)
       │
       ├─▶ Create OptionSet autocmd
       │   └─▶ Watches "background" changes
       │
       └─▶ Create FileType autocmd
           └─▶ For each filetype in config
```

### 2. Buffer Load Event Flow
```
FileType event triggered
        │
        ▼
┌──────────────────┐
│ semhl_autoload() │
└──────┬───────────┘
       │
       ▼
┌──────────────────────┐
│ Create BufEnter      │
│ autocmd for buffer   │
└──────┬───────────────┘
       │
       ▼
BufEnter event triggered
        │
        ▼
┌─────────────────────────┐
│ semhl_on_buffer_enter() │
└──────┬──────────────────┘
       │
       ├─▶ Check disable function
       │   └─▶ Return if disabled
       │
       ├─▶ Get Tree-sitter parser
       │   └─▶ Error handling with pcall
       │
       ├─▶ Register parser callbacks
       │   ├─▶ on_bytes (text changes)
       │   ├─▶ on_changedtree (parse tree changes)
       │   └─▶ on_detach (cleanup)
       │
       ├─▶ Track parser in M._BUFFER_PARSERS
       │
       └─▶ Process initial content
           └─▶ semhl_process_range()
               └─▶ Apply initial highlights
```

### 3. Text Change Event Flow (on_bytes)
```
User types/edits text
        │
        ▼
┌──────────────────┐
│ on_bytes callback│
└──────┬───────────┘
       │
       ├─▶ Check buffer is loaded
       │
       ├─▶ Add range to M._PENDING_RANGES
       │
       ├─▶ Cancel existing timer (if any)
       │
       └─▶ Start new deferred timer (50ms)
           │
           ▼ (after delay)
┌────────────────────────────┐
│ semhl_do_batched_process() │
└──────┬─────────────────────┘
       │
       ├─▶ Get batched ranges
       │   └─▶ Merge adjacent/overlapping
       │
       ├─▶ Parse tree (with error handling)
       │
       └─▶ For each range:
           └─▶ semhl_process_range()
               ├─▶ Get/create cached query
               ├─▶ Clear old extmarks
               └─▶ Apply new highlights
```

### 4. Tree Change Event Flow (on_changedtree)
```
Tree-sitter detects syntax change
        │
        ▼
┌─────────────────────┐
│ on_changedtree      │
│ callback            │
└──────┬──────────────┘
       │
       ├─▶ Check buffer is loaded
       │
       ├─▶ Stop all pending timers
       │   └─▶ Immediate processing
       │
       └─▶ For each changed range:
           └─▶ semhl_process_range()
               └─▶ Update highlights
```

### 5. Background Change Event Flow
```
User changes vim.o.background
        │
        ▼
┌─────────────────────────┐
│ OptionSet autocmd fires │
└──────┬──────────────────┘
       │
       ▼
┌──────────────────────────────┐
│ semhl_on_background_change() │
└──────┬───────────────────────┘
       │
       ├─▶ Clear color cache
       │   └─▶ color_generator.clear_background_cache()
       │
       ├─▶ Clear word cache
       │   └─▶ M._WORD_CACHE = {}
       │
       └─▶ For each active buffer:
           ├─▶ Clear existing highlights
           └─▶ Reprocess with new colors
               └─▶ semhl_process_range()
```

### 6. Highlight Processing Flow
```
semhl_process_range(parser, tree, buffer, create_new, range)
        │
        ▼
┌──────────────────────┐
│ Get/create TS query  │
│ from cache           │
└──────┬───────────────┘
       │
       ├─▶ Clear extmarks in range
       │
       └─▶ For each identifier in range:
           │
           ▼
    ┌──────────────────┐
    │ Get identifier   │
    │ text from node   │
    └──────┬───────────┘
           │
           ├─▶ Check M._WORD_CACHE
           │   ├─▶ Found: Use existing color
           │   └─▶ Not found: Generate new (if create_new)
           │
           └─▶ semhl_highlight_node()
               ├─▶ Generate color if needed
               │   └─▶ color_generator.color_generate()
               │       └─▶ HSV to RGB conversion
               │
               ├─▶ Create highlight group
               │   └─▶ Cache in M._HIGHLIGHT_CACHE
               │
               └─▶ Apply extmark
                   └─▶ nvim_buf_set_extmark()
```

## Code Structure

### Main Module Files
```
lua/
├── semhl.lua           # Main plugin logic
│   ├── Setup & configuration
│   ├── Buffer lifecycle management
│   ├── Tree-sitter integration
│   ├── Event callbacks
│   └── Caching mechanisms
│
└── color_generator.lua # Color generation
    ├── HSV to RGB conversion
    ├── Background detection
    ├── Adaptive color parameters
    └── Color collision detection (TODO)
```

### Cache Structures
```lua
-- semhl.lua global caches
M._HIGHLIGHT_CACHE = {}    -- Maps color to highlight group name
M._WORD_CACHE = {}         -- Maps identifier to color
M._BUFFER_PARSERS = {}     -- Maps buffer to parser
M._QUERY_CACHE = {}        -- Maps language to TS query
M._PENDING_RANGES = {}     -- Maps buffer to pending edit ranges
M._DEFERRED_TIMER_TASKS = {} -- Maps tick to timer handle
```

### Key Functions Reference

| Function | File | Line | Purpose |
|----------|------|------|---------|
| `setup()` | semhl.lua | 319-360 | Initialize plugin |
| `semhl_on_buffer_enter()` | semhl.lua | 269-290 | Handle buffer entry |
| `semhl_process_range()` | semhl.lua | 211-242 | Apply highlights to range |
| `semhl_on_bytes()` | semhl.lua | 282-337 | Handle text changes |
| `semhl_on_tree_change()` | semhl.lua | 339-361 | Handle parse tree changes |
| `color_generate()` | color_generator.lua | 71-130 | Generate color from HSV |
| `semhl_cleanup_buffer()` | semhl.lua | 244-263 | Clean up buffer resources |

## Debugging

### Enable Debug Logging
```lua
-- In your config
require('semhl').setup({
  -- your config
})

-- Set log level to debug
require('semhl')._LOG_LEVEL = "debug"
```

### View Logs
```vim
" Check plenary log location
:echo stdpath('cache') . '/plenary/semhl.log'

" Open log file
:edit ~/.cache/nvim/plenary/semhl.log
```

### Common Debug Points

1. **Check active buffers:**
```lua
:lua vim.print(require('semhl')._BUFFER_PARSERS)
```

2. **Check word cache:**
```lua
:lua vim.print(require('semhl')._WORD_CACHE)
```

3. **Check pending ranges:**
```lua
:lua vim.print(require('semhl')._PENDING_RANGES)
```

4. **Check query cache:**
```lua
:lua vim.print(require('semhl')._QUERY_CACHE)
```

5. **Force background change:**
```lua
:lua require('color_generator').clear_background_cache()
:set background=light
:set background=dark
```

### Performance Profiling
```lua
-- Add timing to process_range
local start = vim.loop.hrtime()
semhl_process_range(...)
local elapsed = (vim.loop.hrtime() - start) / 1000000
print(string.format("Processing took %.2fms", elapsed))
```

## Contributing

### Code Style
- Use snake_case for functions and variables
- Prefix module-local functions with `semhl_`
- Add diagnostic disable comments where needed
- Document complex logic with comments

### Testing Checklist
- [ ] Run all existing tests
- [ ] Add tests for new features
- [ ] Test with multiple file types
- [ ] Test with large files (>100KB)
- [ ] Test background switching
- [ ] Test rapid editing
- [ ] Test buffer lifecycle

### Submitting Changes
1. Fork the repository
2. Create a feature branch
3. Add tests for your changes
4. Ensure all tests pass
5. Update documentation
6. Submit a pull request

## Performance Considerations

### Optimization Strategies
1. **Query Caching** - TS queries cached per language
2. **Range Batching** - Multiple edits processed together
3. **Debouncing** - 50ms delay for rapid changes
4. **Incremental Processing** - Only changed ranges updated
5. **Early Returns** - Skip processing when possible

### Memory Management
- Buffers cleaned up on deletion/wipe
- Timers properly stopped
- Caches cleared when appropriate
- Parser references released

### Benchmarks
```lua
-- Typical processing times (100 lines of code)
Initial load: ~20-50ms
Incremental update: ~5-10ms
Background change: ~30-60ms
Large file (1000 lines): ~100-200ms
```

---

*For more information, see the main [README.md](README.md) or open an issue on GitHub.*