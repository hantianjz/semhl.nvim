---@diagnostic disable: undefined-field
local semhl = require("semhl")

describe("semhl integration tests", function()
  before_each(function()
    -- Reset plugin state
    semhl._HIGHLIGHT_CACHE = {}
    semhl._WORD_CACHE = {}
    semhl._DEFERRED_TIMER_TASKS = {}
    semhl._BUFFER_PARSERS = {}
    semhl._QUERY_CACHE = {}
    semhl._PENDING_RANGES = {}
    semhl._init = false
  end)

  describe("real-world scenarios", function()
    it("should handle multiple file types correctly", function()
      semhl.setup({ filetypes = { "lua", "python", "javascript" } })

      -- Test Lua file
      local lua_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(lua_buf, "filetype", "lua")
      vim.api.nvim_buf_set_lines(lua_buf, 0, -1, false, {
        "local function test()",
        "  local var = 123",
        "  return var * 2",
        "end",
      })
      vim.api.nvim_set_current_buf(lua_buf)
      semhl.load()
      vim.wait(200)

      local ns = semhl._ns
      local lua_marks = vim.api.nvim_buf_get_extmarks(lua_buf, ns, 0, -1, {})
      assert.is_true(#lua_marks > 0, "Lua buffer should have highlights")

      -- Test Python file (if parser available)
      local python_ok, _ = pcall(vim.treesitter.get_parser, 0, "python")
      if python_ok then
        local py_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(py_buf, "filetype", "python")
        vim.api.nvim_buf_set_lines(py_buf, 0, -1, false, {
          "def calculate(x, y):",
          "    result = x + y",
          "    return result",
        })
        vim.api.nvim_set_current_buf(py_buf)
        semhl.load()
        vim.wait(200)

        local py_marks = vim.api.nvim_buf_get_extmarks(py_buf, ns, 0, -1, {})
        assert.is_true(#py_marks > 0, "Python buffer should have highlights")

        -- Clean up
        vim.api.nvim_buf_delete(py_buf, { force = true })
      end

      -- Clean up
      vim.api.nvim_buf_delete(lua_buf, { force = true })
    end)

    it("should handle copy-paste operations", function()
      semhl.setup({ filetypes = { "lua" } })

      local buffer = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(buffer, "filetype", "lua")
      vim.api.nvim_set_current_buf(buffer)

      -- Initial content
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
        "local original = 1",
        "local another = 2",
      })

      semhl.load()
      vim.wait(200)

      -- Simulate copy-paste by duplicating lines
      vim.api.nvim_buf_set_lines(buffer, 2, 2, false, {
        "local original = 1",
        "local another = 2",
      })
      vim.wait(200)

      -- Check that identifiers maintain consistent colors
      local ns = semhl._ns
      local marks = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, { details = true })

      local colors = {}
      for _, mark in ipairs(marks) do
        local details = mark[4]
        if details and details.hl_group then
          local text = vim.api.nvim_buf_get_text(buffer,
            mark[2], mark[3],
            details.end_row or mark[2], details.end_col, {})
          local identifier = table.concat(text)

          if colors[identifier] then
            assert.equals(colors[identifier], details.hl_group,
              "Identifier '" .. identifier .. "' should have consistent color after copy-paste")
          else
            colors[identifier] = details.hl_group
          end
        end
      end

      vim.api.nvim_buf_delete(buffer, { force = true })
    end)

    it("should handle rapid file switching", function()
      semhl.setup({ filetypes = { "lua" } })

      -- Create multiple buffers
      local buffers = {}
      for i = 1, 3 do
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(buf, "filetype", "lua")
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          "local buf" .. i .. "_var = " .. i,
          "print(buf" .. i .. "_var)",
        })
        table.insert(buffers, buf)
      end

      -- Rapidly switch between buffers
      for _ = 1, 3 do
        for _, buf in ipairs(buffers) do
          vim.api.nvim_set_current_buf(buf)
          semhl.load()
          vim.wait(50)
        end
      end

      -- All buffers should have highlights
      local ns = semhl._ns
      for i, buf in ipairs(buffers) do
        local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
        assert.is_true(#marks > 0, "Buffer " .. i .. " should have highlights after rapid switching")
      end

      -- Clean up
      for _, buf in ipairs(buffers) do
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end)

    it("should handle undo/redo operations", function()
      semhl.setup({ filetypes = { "lua" } })

      local buffer = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(buffer, "filetype", "lua")
      vim.api.nvim_set_current_buf(buffer)

      -- Initial content
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
        "local initial = 1",
      })

      semhl.load()
      vim.wait(200)

      -- Add more content
      vim.api.nvim_buf_set_lines(buffer, 1, 1, false, {
        "local added = 2",
      })
      vim.wait(200)

      -- Check highlights exist
      local ns = semhl._ns
      local marks_after_add = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, {})
      assert.is_true(#marks_after_add > 2, "Should have highlights for both lines")

      -- Simulate undo (remove the added line)
      vim.api.nvim_buf_set_lines(buffer, 1, 2, false, {})
      vim.wait(200)

      local marks_after_undo = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, {})
      assert.is_true(#marks_after_undo < #marks_after_add, "Should have fewer highlights after undo")

      -- Simulate redo (add the line back)
      vim.api.nvim_buf_set_lines(buffer, 1, 1, false, {
        "local added = 2",
      })
      vim.wait(200)

      local marks_after_redo = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, {})
      assert.is_true(#marks_after_redo > #marks_after_undo, "Should restore highlights after redo")

      vim.api.nvim_buf_delete(buffer, { force = true })
    end)

    it("should handle large code blocks efficiently", function()
      semhl.setup({ filetypes = { "lua" } })

      local buffer = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(buffer, "filetype", "lua")
      vim.api.nvim_set_current_buf(buffer)

      -- Generate a moderately large code block
      local lines = {}
      for i = 1, 100 do
        table.insert(lines, "local var" .. i .. " = " .. i)
        if i % 10 == 0 then
          table.insert(lines, "print(var" .. i .. ")")
        end
      end

      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
      semhl.load()

      -- Measure highlighting time
      local start_time = vim.loop.hrtime()
      vim.wait(500) -- Wait for highlighting to complete
      local elapsed = (vim.loop.hrtime() - start_time) / 1000000 -- Convert to ms

      -- Should complete reasonably quickly
      assert.is_true(elapsed < 1000, "Highlighting 100+ lines should complete within 1 second")

      -- Verify highlights were applied
      local ns = semhl._ns
      local marks = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, {})
      assert.is_true(#marks > 100, "Should have many highlights for large code block")

      vim.api.nvim_buf_delete(buffer, { force = true })
    end)

    it("should maintain performance with multiple active buffers", function()
      semhl.setup({ filetypes = { "lua" } })

      -- Create multiple buffers with content
      local buffers = {}
      for i = 1, 5 do
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(buf, "filetype", "lua")

        local lines = {}
        for j = 1, 20 do
          table.insert(lines, "local buf" .. i .. "_var" .. j .. " = " .. j)
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

        vim.api.nvim_set_current_buf(buf)
        semhl.load()
        vim.wait(100)

        table.insert(buffers, buf)
      end

      -- All buffers should be tracked
      local tracked_count = 0
      for _, _ in pairs(semhl._BUFFER_PARSERS) do
        tracked_count = tracked_count + 1
      end
      assert.equals(5, tracked_count, "Should track all 5 buffers")

      -- Make changes to all buffers
      for i, buf in ipairs(buffers) do
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, {
          "local modified" .. i .. " = 999",
        })
      end
      vim.wait(300)

      -- All buffers should still have highlights
      local ns = semhl._ns
      for i, buf in ipairs(buffers) do
        local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
        assert.is_true(#marks > 0, "Buffer " .. i .. " should still have highlights")
      end

      -- Clean up
      for _, buf in ipairs(buffers) do
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end)

    it("should handle background change with multiple buffers", function()
      semhl.setup({ filetypes = { "lua" }, adaptive_colors = true })

      -- Create multiple buffers
      local buffers = {}
      for i = 1, 2 do
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(buf, "filetype", "lua")
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          "local test" .. i .. " = " .. i,
        })
        vim.api.nvim_set_current_buf(buf)
        semhl.load()
        vim.wait(100)
        table.insert(buffers, buf)
      end

      -- Set dark background
      vim.o.background = "dark"
      require("color_generator").clear_background_cache()
      vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
      vim.wait(200)

      -- Get colors for dark background
      local ns = semhl._ns
      local dark_colors = {}
      for i, buf in ipairs(buffers) do
        local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
        for _, mark in ipairs(marks) do
          local details = mark[4]
          if details and details.hl_group then
            dark_colors[i] = details.hl_group
            break
          end
        end
      end

      -- Switch to light background
      vim.o.background = "light"
      vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
      vim.wait(200)

      -- Get colors for light background
      local light_colors = {}
      for i, buf in ipairs(buffers) do
        local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
        for _, mark in ipairs(marks) do
          local details = mark[4]
          if details and details.hl_group then
            light_colors[i] = details.hl_group
            break
          end
        end
      end

      -- Colors should change for all buffers
      for i = 1, 2 do
        assert.is_not.equals(dark_colors[i], light_colors[i],
          "Buffer " .. i .. " should have different colors after background change")
      end

      -- Clean up
      for _, buf in ipairs(buffers) do
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end)
  end)

  describe("edge cases", function()
    it("should handle empty files", function()
      semhl.setup({ filetypes = { "lua" } })

      local buffer = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(buffer, "filetype", "lua")
      vim.api.nvim_set_current_buf(buffer)

      -- Empty buffer
      semhl.load()
      vim.wait(100)

      -- Should not error and should have no highlights
      local ns = semhl._ns
      local marks = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, {})
      assert.equals(0, #marks, "Empty buffer should have no highlights")

      vim.api.nvim_buf_delete(buffer, { force = true })
    end)

    it("should handle files with only comments", function()
      semhl.setup({ filetypes = { "lua" } })

      local buffer = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(buffer, "filetype", "lua")
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
        "-- This is a comment",
        "-- Another comment",
        "--[[ Block comment",
        "     spanning multiple lines",
        "--]]",
      })

      vim.api.nvim_set_current_buf(buffer)
      semhl.load()
      vim.wait(200)

      -- Should have no highlights (comments don't contain identifiers)
      local ns = semhl._ns
      local marks = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, {})
      assert.equals(0, #marks, "File with only comments should have no identifier highlights")

      vim.api.nvim_buf_delete(buffer, { force = true })
    end)

    it("should recover from parser errors gracefully", function()
      semhl.setup({ filetypes = { "lua" } })

      local buffer = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(buffer, "filetype", "lua")
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
        "local valid = 1",
        "this is invalid syntax !@#$%",
        "local another_valid = 2",
      })

      vim.api.nvim_set_current_buf(buffer)

      -- Should not crash despite syntax errors
      assert.has_no.errors(function()
        semhl.load()
        vim.wait(200)
      end)

      -- Should still highlight valid identifiers
      local ns = semhl._ns
      local marks = vim.api.nvim_buf_get_extmarks(buffer, ns, 0, -1, {})
      assert.is_true(#marks > 0, "Should still highlight valid identifiers despite syntax errors")

      vim.api.nvim_buf_delete(buffer, { force = true })
    end)
  end)
end)