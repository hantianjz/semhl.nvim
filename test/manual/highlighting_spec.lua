---@diagnostic disable: undefined-field
local semhl = require("semhl")

describe("semhl highlighting", function()
  local test_buffer
  local ns

  before_each(function()
    -- Reset the plugin state
    semhl._HIGHLIGHT_CACHE = {}
    semhl._WORD_CACHE = {}
    semhl._DEFERRED_TIMER_TASKS = {}
    semhl._BUFFER_PARSERS = {}
    semhl._init = false

    -- Setup and get namespace
    semhl.setup({ filetypes = { "lua" } })
    ns = semhl._ns

    -- Create test buffer
    test_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(test_buffer, "filetype", "lua")
    vim.api.nvim_set_current_buf(test_buffer)
  end)

  after_each(function()
    if test_buffer and vim.api.nvim_buf_is_valid(test_buffer) then
      vim.api.nvim_buf_delete(test_buffer, { force = true })
    end
  end)

  it("should highlight identifiers with unique colors", function()
    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
      "local variable1 = 123",
      "local variable2 = 456",
      "print(variable1 + variable2)",
    })

    semhl.load()
    vim.wait(200) -- Wait for highlighting

    -- Check that identifiers got highlighted
    local extmarks = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, { details = true })
    assert.is_true(#extmarks > 0, "Should have extmarks")

    -- Check that each unique identifier has a consistent color
    local colors = {}
    for _, mark in ipairs(extmarks) do
      local details = mark[4]
      if details and details.hl_group then
        local text = vim.api.nvim_buf_get_text(test_buffer, mark[2], mark[3], details.end_row or mark[2], details.end_col, {})
        local identifier = table.concat(text)

        if colors[identifier] then
          -- Same identifier should have same color
          assert.equals(colors[identifier], details.hl_group,
            "Identifier '" .. identifier .. "' should have consistent color")
        else
          colors[identifier] = details.hl_group
        end
      end
    end

    -- Different identifiers should have different colors
    assert.is_not.equals(colors["variable1"], colors["variable2"],
      "Different identifiers should have different colors")
  end)

  it("should maintain color consistency across edits", function()
    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
      "local myvar = 123",
    })

    semhl.load()
    vim.wait(200)

    -- Get initial color for 'myvar'
    local extmarks1 = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, { details = true })
    local initial_color = nil
    for _, mark in ipairs(extmarks1) do
      local details = mark[4]
      if details and details.hl_group then
        initial_color = details.hl_group
        break
      end
    end
    assert.is_not_nil(initial_color)

    -- Edit the buffer
    vim.api.nvim_buf_set_lines(test_buffer, 1, 1, false, {
      "print(myvar)",
    })
    vim.wait(200)

    -- Check that 'myvar' still has the same color
    local extmarks2 = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 1, 2, { details = true })
    local found_same_color = false
    for _, mark in ipairs(extmarks2) do
      local details = mark[4]
      if details and details.hl_group == initial_color then
        found_same_color = true
        break
      end
    end
    assert.is_true(found_same_color, "Identifier should maintain same color after edit")
  end)

  it("should handle incremental updates correctly", function()
    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
      "local var1 = 1",
      "local var2 = 2",
      "local var3 = 3",
    })

    semhl.load()
    vim.wait(200)

    -- Count initial extmarks
    local initial_marks = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, {})
    local initial_count = #initial_marks

    -- Edit middle line only
    vim.api.nvim_buf_set_lines(test_buffer, 1, 2, false, {
      "local changed = 999",
    })
    vim.wait(200)

    -- Should still have highlights
    local after_marks = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, {})
    assert.is_true(#after_marks > 0, "Should still have highlights after edit")

    -- Check that line 0 and 2 still have their marks
    local line0_marks = vim.api.nvim_buf_get_extmarks(test_buffer, ns, {0, 0}, {0, -1}, {})
    local line2_marks = vim.api.nvim_buf_get_extmarks(test_buffer, ns, {2, 0}, {2, -1}, {})
    assert.is_true(#line0_marks > 0, "Line 0 should still have marks")
    assert.is_true(#line2_marks > 0, "Line 2 should still have marks")
  end)

  it("should clear highlights when unloading", function()
    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
      "local test = 123",
      "print(test)",
    })

    semhl.load()
    vim.wait(200)

    -- Verify highlights exist
    local marks_before = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, {})
    assert.is_true(#marks_before > 0, "Should have marks before unload")

    -- Unload
    semhl.unload()

    -- Verify highlights are cleared
    local marks_after = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, {})
    assert.equals(0, #marks_after, "Should have no marks after unload")
  end)

  it("should skip files larger than max_file_size", function()
    -- Create a buffer with mock large file
    local large_buffer = vim.api.nvim_create_buf(false, false)
    local temp_file = vim.fn.tempname() .. ".lua"

    -- Write a large file
    local large_content = {}
    for i = 1, 5000 do
      table.insert(large_content, "local var" .. i .. " = " .. i)
    end
    vim.fn.writefile(large_content, temp_file)

    -- Setup with small max file size
    semhl._init = false
    semhl.setup({ filetypes = { "lua" }, max_file_size = 100 })

    -- Load the file
    vim.cmd("edit " .. temp_file)
    local loaded_buffer = vim.api.nvim_get_current_buf()

    semhl.load()
    vim.wait(100)

    -- Should not have any highlights due to file size
    local marks = vim.api.nvim_buf_get_extmarks(loaded_buffer, ns, 0, -1, {})
    assert.equals(0, #marks, "Large file should not be highlighted")

    -- Cleanup
    vim.api.nvim_buf_delete(loaded_buffer, { force = true })
    vim.fn.delete(temp_file)
  end)

  it("should handle buffers with no tree-sitter parser", function()
    local plain_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(plain_buffer, "filetype", "txt")
    vim.api.nvim_set_current_buf(plain_buffer)

    vim.api.nvim_buf_set_lines(plain_buffer, 0, -1, false, {
      "This is plain text",
      "No tree-sitter parser here",
    })

    -- Should not error when loading
    assert.has_no.errors(function()
      semhl.load()
    end)

    -- Should have no highlights
    local marks = vim.api.nvim_buf_get_extmarks(plain_buffer, ns, 0, -1, {})
    assert.equals(0, #marks, "Buffer without parser should have no highlights")

    vim.api.nvim_buf_delete(plain_buffer, { force = true })
  end)

  it("should handle rapid buffer changes without errors", function()
    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
      "local test = 1",
    })

    semhl.load()

    -- Rapidly change buffer content
    for i = 1, 10 do
      vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
        "local test = " .. i,
        "local another = " .. (i * 2),
      })
      vim.wait(10)
    end

    -- Should not error and should still have highlights
    vim.wait(100)
    local marks = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, {})
    assert.is_true(#marks > 0, "Should still have highlights after rapid changes")
  end)

  it("should not highlight keywords as identifiers", function()
    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
      "local function test()",
      "  if true then",
      "    return nil",
      "  end",
      "end",
    })

    semhl.load()
    vim.wait(200)

    -- Get all highlighted text
    local extmarks = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, { details = true })
    local highlighted_words = {}

    for _, mark in ipairs(extmarks) do
      local details = mark[4]
      if details then
        local text = vim.api.nvim_buf_get_text(test_buffer,
          mark[2], mark[3],
          details.end_row or mark[2], details.end_col, {})
        highlighted_words[table.concat(text)] = true
      end
    end

    -- Keywords should not be highlighted
    assert.is_nil(highlighted_words["local"], "Keyword 'local' should not be highlighted")
    assert.is_nil(highlighted_words["function"], "Keyword 'function' should not be highlighted")
    assert.is_nil(highlighted_words["if"], "Keyword 'if' should not be highlighted")
    assert.is_nil(highlighted_words["then"], "Keyword 'then' should not be highlighted")
    assert.is_nil(highlighted_words["return"], "Keyword 'return' should not be highlighted")
    assert.is_nil(highlighted_words["end"], "Keyword 'end' should not be highlighted")

    -- Only 'test' should be highlighted as it's an identifier
    assert.is_true(highlighted_words["test"] == true, "Identifier 'test' should be highlighted")
  end)
end)