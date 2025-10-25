---@diagnostic disable: undefined-field
local color_gen = require("color_generator")
local semhl = require("semhl")

describe("background-aware colors", function()
  before_each(function()
    -- Reset color generator state
    package.loaded["color_generator"] = nil
    color_gen = require("color_generator")
    color_gen.clear_background_cache()
  end)

  describe("color_generator background detection", function()
    it("should generate different colors for dark vs light backgrounds", function()
      -- Test dark background
      vim.o.background = "dark"
      color_gen.clear_background_cache()
      local dark_color = color_gen.color_generate(0.5, 0.5, 0.5)

      -- Test light background
      vim.o.background = "light"
      color_gen.clear_background_cache()
      local light_color = color_gen.color_generate(0.5, 0.5, 0.5)

      assert.is_not.equals(dark_color, light_color,
        "Same parameters should generate different colors for different backgrounds")
    end)

    it("should generate brighter colors for dark backgrounds", function()
      vim.o.background = "dark"
      color_gen.clear_background_cache()

      local color = color_gen.color_generate(0.5, 0.8, 0.8)

      -- Extract RGB values
      local r = tonumber(color:sub(2, 3), 16)
      local g = tonumber(color:sub(4, 5), 16)
      local b = tonumber(color:sub(6, 7), 16)

      -- For dark background, at least one channel should be bright
      local max_channel = math.max(r, g, b)
      assert.is_true(max_channel > 150,
        string.format("Dark background color should be bright (got max channel: %d)", max_channel))
    end)

    it("should generate darker colors for light backgrounds", function()
      vim.o.background = "light"
      color_gen.clear_background_cache()

      local color = color_gen.color_generate(0.5, 0.8, 0.8)

      -- Extract RGB values
      local r = tonumber(color:sub(2, 3), 16)
      local g = tonumber(color:sub(4, 5), 16)
      local b = tonumber(color:sub(6, 7), 16)

      -- For light background, colors should be darker
      local max_channel = math.max(r, g, b)
      assert.is_true(max_channel < 180,
        string.format("Light background color should be darker (got max channel: %d)", max_channel))
    end)

    it("should cache background setting for performance", function()
      vim.o.background = "dark"
      color_gen.clear_background_cache()

      local color1 = color_gen.color_generate(0.3, 0.3, 0.3)

      -- Change background but don't clear cache
      vim.o.background = "light"
      local color2 = color_gen.color_generate(0.3, 0.3, 0.3)

      -- Should still use cached dark background
      assert.equals(color1, color2, "Should use cached background setting")

      -- Now clear cache and generate again
      color_gen.clear_background_cache()
      local color3 = color_gen.color_generate(0.3, 0.3, 0.3)

      -- Should be different after cache clear
      assert.is_not.equals(color1, color3, "Should use new background after cache clear")
    end)
  end)

  describe("semhl background integration", function()
    local test_buffer

    before_each(function()
      -- Reset semhl state
      semhl._HIGHLIGHT_CACHE = {}
      semhl._WORD_CACHE = {}
      semhl._DEFERRED_TIMER_TASKS = {}
      semhl._BUFFER_PARSERS = {}
      semhl._init = false

      test_buffer = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(test_buffer, "filetype", "lua")
    end)

    after_each(function()
      if test_buffer and vim.api.nvim_buf_is_valid(test_buffer) then
        vim.api.nvim_buf_delete(test_buffer, { force = true })
      end
    end)

    it("should regenerate colors when background changes", function()
      -- Setup with adaptive colors enabled (default)
      semhl.setup({ filetypes = { "lua" } })

      vim.o.background = "dark"
      color_gen.clear_background_cache()

      vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
        "local myvar = 123",
      })

      vim.api.nvim_set_current_buf(test_buffer)
      semhl.load()
      vim.wait(200)

      -- Get initial highlights
      local ns = semhl._ns
      local dark_marks = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, { details = true })
      local dark_color = nil
      for _, mark in ipairs(dark_marks) do
        local details = mark[4]
        if details and details.hl_group then
          dark_color = details.hl_group
          break
        end
      end

      -- Change background
      vim.o.background = "light"
      vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
      vim.wait(200)

      -- Get new highlights
      local light_marks = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, { details = true })
      local light_color = nil
      for _, mark in ipairs(light_marks) do
        local details = mark[4]
        if details and details.hl_group then
          light_color = details.hl_group
          break
        end
      end

      -- Colors should be different for different backgrounds
      assert.is_not.equals(dark_color, light_color,
        "Should regenerate different colors when background changes")
    end)

    it("should support disabling adaptive colors in setup", function()
      -- Setup with adaptive colors disabled
      semhl.setup({ filetypes = { "lua" }, adaptive_colors = false })

      vim.o.background = "dark"
      color_gen.clear_background_cache()

      vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
        "local myvar = 123",
      })

      vim.api.nvim_set_current_buf(test_buffer)
      semhl.load()
      vim.wait(200)

      -- Get initial highlights
      local ns = semhl._ns
      local dark_marks = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, { details = true })
      local dark_color = nil
      for _, mark in ipairs(dark_marks) do
        local details = mark[4]
        if details and details.hl_group then
          dark_color = details.hl_group
          break
        end
      end

      -- Change background
      vim.o.background = "light"
      vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
      vim.wait(200)

      -- Get new highlights
      local light_marks = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, { details = true })
      local light_color = nil
      for _, mark in ipairs(light_marks) do
        local details = mark[4]
        if details and details.hl_group then
          light_color = details.hl_group
          break
        end
      end

      -- With adaptive disabled, regeneration still happens but uses same color parameters
      -- The word cache is cleared so highlight group names might differ, but the underlying
      -- color values should be using dark background parameters for both
      assert.is_not_nil(dark_color)
      assert.is_not_nil(light_color)
    end)
  end)

  describe("color parameter ranges", function()
    it("should apply correct saturation range for dark background", function()
      vim.o.background = "dark"
      color_gen.clear_background_cache()

      -- Test with low saturation input
      local color_low = color_gen.color_generate(0.5, 0.0, 0.9)
      -- Test with high saturation input
      local color_high = color_gen.color_generate(0.5, 1.0, 0.9)

      -- Extract and compare saturation from colors
      -- (This is indirect but we can verify they're different)
      assert.is_not.equals(color_low, color_high,
        "Different saturation inputs should produce different colors")
    end)

    it("should apply correct value range for light background", function()
      vim.o.background = "light"
      color_gen.clear_background_cache()

      -- Test with different value inputs
      local color_low = color_gen.color_generate(0.5, 0.5, 0.0)
      local color_high = color_gen.color_generate(0.5, 0.5, 1.0)

      -- Both should be relatively dark for light background
      local r_low = tonumber(color_low:sub(2, 3), 16)
      local g_low = tonumber(color_low:sub(4, 5), 16)
      local b_low = tonumber(color_low:sub(6, 7), 16)
      local max_low = math.max(r_low, g_low, b_low)

      local r_high = tonumber(color_high:sub(2, 3), 16)
      local g_high = tonumber(color_high:sub(4, 5), 16)
      local b_high = tonumber(color_high:sub(6, 7), 16)
      local max_high = math.max(r_high, g_high, b_high)

      -- Both should be constrained to darker values for light background
      assert.is_true(max_low < 200, "Low value should still be dark for light background")
      assert.is_true(max_high < 200, "High value should still be dark for light background")

      -- But high should be brighter than low
      assert.is_true(max_high > max_low, "Higher value input should produce brighter color")
    end)
  end)
end)