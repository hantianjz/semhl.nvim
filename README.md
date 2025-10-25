# semhl.nvim

Semantic highlighting for Neovim using Tree-sitter. A re-implementation of <a href="https://github.com/jaxbot/semantic-highlight.vim">semantic-highlight.vim</a> in Lua targeting Neovim.

Every identifier is a different color, an idea popularized by <a href="https://medium.com/@evnbr/coding-in-color-3a6db2743a1e">Evan Brooks'</a> blog post.

![image](https://github.com/user-attachments/assets/c30a22eb-186a-4805-9589-a2091335d207)

## Features

- **Unique colors for every identifier** - Each variable gets its own consistent color throughout the file
- **Perceptually uniform colors** - Uses CIELAB color space for scientifically accurate color distinction
- **Persistent color cache** - Colors persist across sessions for consistent highlighting
- **Guaranteed visual distinction** - Delta-E threshold ensures all colors are perceptually distinct from background
- **Configurable lightness range** - Control whether colors should be lighter or darker
- **Background-aware generation** - Automatically adjusts color ranges for dark and light themes
- **High performance** - Uses incremental processing, caching, and batching for smooth editing
- **Robust error handling** - Gracefully handles Tree-sitter failures and edge cases
- **Tree-sitter powered** - Works with any language that has a Tree-sitter parser

## Setup

### Using Lazy.nvim

```lua
{
  'hantianjz/semhl.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  opts = {
    filetypes = { "c", "cpp", "h", "python", "lua", "typescript", "java" },
    max_file_size = 100 * 1024,  -- Skip files larger than 100KB (default)

    -- Optional: Customize color generation (defaults shown)
    min_delta_e = 5,      -- Minimum color distinction from background
    target_delta_e = 15,  -- Target color generation distance
    -- L_min = 50,        -- Minimum lightness (auto-detected by default)
    -- L_max = 100,       -- Maximum lightness (auto-detected by default)
  }
}
```

### Using Packer.nvim

```lua
use {
  'hantianjz/semhl.nvim',
  requires = 'nvim-lua/plenary.nvim',
  config = function()
    require('semhl').setup({
      filetypes = { "c", "cpp", "h", "python", "lua", "typescript", "java" },
      max_file_size = 100 * 1024,
    })
  end
}
```

## Configuration Options

```lua
require('semhl').setup({
  -- File types to enable semantic highlighting for
  filetypes = { 'lua', 'python', 'javascript', 'typescript', 'go', 'rust' },

  -- Maximum file size in bytes to process
  max_file_size = 100 * 1024,  -- default: 100KB

  -- Color generation settings (CIELAB-based)
  min_delta_e = 5,      -- Minimum perceptual color difference from background (default: 5)
                        -- Higher values = more distinct colors, less variety
                        -- Typical ranges: 2-10 (noticeable), >10 (clearly different)

  target_delta_e = 15,  -- Target color generation distance (default: 15)
                        -- Higher values = more vibrant/saturated colors

  L_min = nil,          -- Minimum lightness (0-100, nil = auto-detect)
                        -- Auto: 50 for dark bg, 0 for light bg
                        -- Manual example: L_min = 60 (avoid dark colors)

  L_max = nil,          -- Maximum lightness (0-100, nil = auto-detect)
                        -- Auto: 100 for dark bg, 50 for light bg
                        -- Manual example: L_max = 85 (avoid very bright colors)

  -- Custom disable function (optional)
  disable = function(bufnr)
    -- Return true to disable highlighting for a buffer
    local filename = vim.api.nvim_buf_get_name(bufnr)
    return filename:match('%.min%.js$') ~= nil
  end,
})
```

### Color Cache

Colors are automatically cached to `~/.cache/nvim/semhl/color_cache.lua` and persist across sessions. The cache is automatically invalidated when color settings change (background, delta-e thresholds, or lightness ranges).

## Commands

- `:SemhlLoad` - Manually load semantic highlighting for current buffer
- `:SemhlUnload` - Unload semantic highlighting for current buffer

## Requirements

- Neovim 0.5+ with Tree-sitter support
- plenary.nvim (for logging)
- Tree-sitter parsers for your languages

## Testing

Run the test suite:
```bash
./run_tests.sh              # Run unit tests
./run_tests.sh --all        # Run all tests (including manual tests)
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for more details on testing and development.
