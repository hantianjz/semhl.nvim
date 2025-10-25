---@diagnostic disable: undefined-field
local semhl = require("semhl")

describe("semhl buffer lifecycle", function()
  local test_buffer

  before_each(function()
    -- Reset the plugin state before each test
    semhl._HIGHLIGHT_CACHE = {}
    semhl._WORD_CACHE = {}
    semhl._DEFERRED_TIMER_TASKS = {}
    semhl._BUFFER_PARSERS = {}
    semhl._init = false

    -- Create a test buffer
    test_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(test_buffer, "filetype", "lua")
  end)

  after_each(function()
    -- Clean up test buffer if it still exists
    if test_buffer and vim.api.nvim_buf_is_valid(test_buffer) then
      vim.api.nvim_buf_delete(test_buffer, { force = true })
    end
    test_buffer = nil
  end)

  it("should attach to a buffer when entering", function()
    semhl.setup({ filetypes = { "lua" } })

    -- Simulate buffer enter
    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
      "local test = 123",
      "local another = test + 1",
    })

    -- Load semhl for the buffer
    vim.api.nvim_set_current_buf(test_buffer)
    semhl.load()

    -- Check that parser was registered
    assert.is_not_nil(semhl._BUFFER_PARSERS[test_buffer])
  end)

  it("should clean up resources when buffer is deleted", function()
    semhl.setup({ filetypes = { "lua" } })

    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
      "local test = 123",
    })

    vim.api.nvim_set_current_buf(test_buffer)
    semhl.load()

    -- Verify parser is tracked
    assert.is_not_nil(semhl._BUFFER_PARSERS[test_buffer])

    -- Delete the buffer
    vim.api.nvim_buf_delete(test_buffer, { force = true })

    -- Give time for cleanup
    vim.wait(100)

    -- Verify cleanup
    assert.is_nil(semhl._BUFFER_PARSERS[test_buffer])
  end)

  it("should handle multiple buffers independently", function()
    semhl.setup({ filetypes = { "lua" } })

    local buffer2 = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buffer2, "filetype", "lua")

    -- Load semhl for both buffers
    vim.api.nvim_set_current_buf(test_buffer)
    semhl.load()

    vim.api.nvim_set_current_buf(buffer2)
    semhl.load()

    -- Both should have parsers
    assert.is_not_nil(semhl._BUFFER_PARSERS[test_buffer])
    assert.is_not_nil(semhl._BUFFER_PARSERS[buffer2])

    -- Delete first buffer
    vim.api.nvim_buf_delete(test_buffer, { force = true })
    vim.wait(100)

    -- Only first buffer should be cleaned
    assert.is_nil(semhl._BUFFER_PARSERS[test_buffer])
    assert.is_not_nil(semhl._BUFFER_PARSERS[buffer2])

    -- Clean up
    vim.api.nvim_buf_delete(buffer2, { force = true })
  end)

  it("should unload highlights properly", function()
    semhl.setup({ filetypes = { "lua" } })

    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
      "local test = 123",
      "local another = test",
    })

    vim.api.nvim_set_current_buf(test_buffer)
    semhl.load()

    -- Wait for highlights to be applied
    vim.wait(100)

    -- Get namespace
    local ns = semhl._ns
    local extmarks_before = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, {})
    assert.is_true(#extmarks_before > 0, "Should have extmarks after loading")

    -- Unload
    semhl.unload()

    -- Check extmarks are cleared
    local extmarks_after = vim.api.nvim_buf_get_extmarks(test_buffer, ns, 0, -1, {})
    assert.equals(0, #extmarks_after, "Should have no extmarks after unloading")
  end)

  it("should handle buffer wipeout gracefully", function()
    semhl.setup({ filetypes = { "lua" } })

    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
      "local test = 123",
    })

    vim.api.nvim_set_current_buf(test_buffer)
    semhl.load()

    -- Wipe the buffer (more aggressive than delete)
    vim.cmd("bwipeout! " .. test_buffer)
    test_buffer = nil  -- Mark as cleaned

    -- Should not error
    vim.wait(100)

    -- Verify cleanup happened (buffer no longer exists to check)
    assert.has_no_errors(function()
      -- Try to run a command that would fail if state is corrupt
      local new_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(new_buf)
      semhl.load()
      vim.api.nvim_buf_delete(new_buf, { force = true })
    end)
  end)

  it("should stop timers when buffer is unloaded", function()
    semhl.setup({ filetypes = { "lua" } })

    vim.api.nvim_buf_set_lines(test_buffer, 0, -1, false, {
      "local test = 123",
    })

    vim.api.nvim_set_current_buf(test_buffer)
    semhl.load()

    -- Trigger a change to create a deferred timer
    vim.api.nvim_buf_set_lines(test_buffer, 0, 1, false, {
      "local test = 456",
    })

    -- Timer should be pending
    local has_timers = false
    for _, _ in pairs(semhl._DEFERRED_TIMER_TASKS) do
      has_timers = true
      break
    end
    assert.is_true(has_timers, "Should have pending timers after edit")

    -- Unload the buffer
    semhl.unload()

    -- Timers should be cleared
    has_timers = false
    for _, _ in pairs(semhl._DEFERRED_TIMER_TASKS) do
      has_timers = true
      break
    end
    assert.is_false(has_timers, "Should have no pending timers after unload")
  end)
end)