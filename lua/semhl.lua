---@diagnostic disable: undefined-field
local M = {}

local PLUGIN_NAME = "semhl"
local MAX_FILE_SIZE = 100 * 1024
local HL_PRIORITY = 130
local BYTE_CHANGE_DELAY_MS = 50

M._HIGHLIGHT_CACHE = {}
M._WORD_CACHE = {}
M._LOG_LEVEL = "warn"
M._DISABLE_CHECK_FUNC = nil
M._MAX_FILE_SIZE = 0
M._DEFERED_TIMER_TASKS = {}

local LOGGER = require("plenary.log").new({
  plugin = PLUGIN_NAME,
  level = M._LOG_LEVEL,
})


local function semhl_check_file_size(buffer)
  local buffer_name = vim.api.nvim_buf_get_name(buffer)
  local ok, stats = pcall(vim.loop.fs_stat, buffer_name)
  if ok and stats and stats.size > M._MAX_FILE_SIZE then
    LOGGER.warn(string.format("File %s is %d bytes larger than MAX_FILE_SIZE of %d bytes, skipping!", buffer_name,
      stats.size, M._MAX_FILE_SIZE))
    return true
  end
  return false
end

local function semhl_ts_diff(start_ts, end_ts)
  local sec = end_ts.sec - start_ts.sec
  local nsec = end_ts.nsec - start_ts.nsec
  if nsec < 0 then
    nsec = 1000000000 + nsec
    sec = sec - 1
  end
  local pad = string.rep("0", 9 - string.len("" .. nsec))

  return sec .. "." .. pad .. nsec
end

local function semhl_create_highlight(ns, rgb_hex)
  rgb_hex = rgb_hex:lower()
  local cache_key = table.concat({ "sfg", rgb_hex }, "_")
  local highlight_name = M._HIGHLIGHT_CACHE[cache_key]

  -- Look up in our cache.
  if highlight_name then
    local hl_id = vim.api.nvim_get_hl_id_by_name(highlight_name)
    if hl_id then
      return highlight_name
    end
  end

  -- Create the highlight
  highlight_name = table.concat({ "sfg", rgb_hex }, "_")
  vim.api.nvim_set_hl(ns, highlight_name, { fg = "#" .. rgb_hex })
  M._HIGHLIGHT_CACHE[cache_key] = highlight_name
  return highlight_name
end

local function semhl_del_extmarks_in_range(buffer, range)
  local srow, scol, erow, ecol = unpack(range)
  local existing_extmark = vim.api.nvim_buf_get_extmarks(buffer, M._ns, { srow, scol }, { erow, ecol }, {})
  for _, mark in pairs(existing_extmark) do
    local id = unpack(mark)
    vim.api.nvim_buf_del_extmark(buffer, M._ns, id)
  end
end

local function semhl_highlight_node(buffer, node_text, range, create_new)
  local hlname = M._WORD_CACHE[node_text]

  semhl_del_extmarks_in_range(buffer, range)

  -- Only create new highlight if create_new is true
  if hlname == nil and create_new then
    local random_range = 1000;
    local hsv = { math.random(0, random_range) / random_range, math.random(0, random_range) / random_range, math
    .random(0, random_range) / random_range }
    local c = require("color_generator").color_generate(hsv[1], hsv[2], hsv[3])
    hlname = semhl_create_highlight(M._ns, string.sub(c, 2))
  end

  if hlname then
    local srow, scol, erow, ecol = unpack(range)
    local ext_id = vim.api.nvim_buf_set_extmark(buffer, M._ns, srow, scol,
      {
        end_row = erow,
        end_col = ecol,
        hl_group = hlname,
        end_right_gravity = true,
        right_gravity = true,
        invalidate = true,
        undo_restore = false,
        priority = HL_PRIORITY,
      })

    LOGGER.debug("ADDED: " .. ext_id .. " : " ..
      buffer .. " - " .. node_text .. "[" .. srow .. "," .. scol .. "," .. ecol .. "] " .. hlname)

    M._WORD_CACHE[node_text] = hlname
  end
end

local function semhl_is_pos_overlap_range(row, col, range)
  local srow, scol, erow, ecol = unpack(range)
  return (srow < row and row < erow) or (srow == row and scol <= col) or (erow == row and col <= ecol)
end

local function semhl_is_node_overlap_range(node, range)
  if range == nil or next(range) == nil then
    return true
  end

  local row1, col1, row2, col2 = node:range()
  return semhl_is_pos_overlap_range(row1, col1, range) or semhl_is_pos_overlap_range(row2, col2, range)
end

local function semhl_process_range(parser, tree, buffer, create_new, range)
  local query = vim.treesitter.query.parse(parser:lang(), "(identifier) @id")
  local erow = nil
  range = range or {}
  if range[3] then
    erow = range[3] + 1
  end
  if range and next(range) then
    semhl_del_extmarks_in_range(buffer, range)
  end
  for _, node in query:iter_captures(tree:root(), buffer, range[1], erow) do
    local node_text = vim.treesitter.get_node_text(node, buffer)
    local overlap = semhl_is_node_overlap_range(node, range)
    if create_new or overlap then
      semhl_highlight_node(buffer, node_text, { node:range() }, create_new)
    end
  end
end

local function semhl_unload(buffer)
  vim.api.nvim_buf_clear_namespace(buffer, M._ns, 0, -1)
end

local function semhl_on_buffer_enter(buffer)
  -- If disable function check returns true, bail out and do nothing for this file
  if M._DISABLE_CHECK_FUNC(buffer) then
    M.unload()
    return
  end

  vim.api.nvim_buf_clear_namespace(buffer, M._ns, 0, -1)
  local parser = vim.treesitter.get_parser(buffer, nil)

  local function semhl_on_bytes(bufno, tick, srow, scol, _, _, _, _, nerow, necol, _)
    local function semhl_do_incremental_process()
      LOGGER.debug("SEMHL_ON_BYTES:" .. string.format("(%d) - %d:%d-%d:%d", tick, srow, scol, srow + nerow, necol))
      local tree = parser:parse()[1]
      local start_ts = vim.uv.clock_gettime("realtime")
      semhl_process_range(parser, tree, bufno, false, { srow, scol, srow + nerow, necol })
      local end_ts = vim.uv.clock_gettime("realtime")
      LOGGER.debug("SEMHL_ON_BYTES run took " .. semhl_ts_diff(start_ts, end_ts) .. " sec")
      M._DEFERED_TIMER_TASKS[tick] = nil
      LOGGER.debug(vim.inspect(M._DEFERED_TIMER_TASKS))
    end

    local defer_time = vim.defer_fn(semhl_do_incremental_process, BYTE_CHANGE_DELAY_MS)
    M._DEFERED_TIMER_TASKS[tick] = defer_time
  end

  local function semhl_on_tree_change(ranges, tree)
    local start_ts = vim.uv.clock_gettime("realtime")
    if ranges and next(ranges) then
      for tick, timer in pairs(M._DEFERED_TIMER_TASKS) do
        vim.uv.timer_stop(timer)
        M._DEFERED_TIMER_TASKS[tick] = nil
      end

      for _, range in pairs(ranges) do
        local srow, scol, _, erow, ecol, _ = unpack(range)
        LOGGER.debug("SEMHL_ON_TREE_CHANGE" .. string.format("-- %d:%d-%d:%d", srow, scol, erow, ecol))
        semhl_process_range(parser, tree, buffer, false, { srow, scol, erow, ecol })
      end
      local end_ts = vim.uv.clock_gettime("realtime")
      LOGGER.debug("SEMHL_ON_TREE_CHANGE run took " .. semhl_ts_diff(start_ts, end_ts) .. " sec")
    end
  end

  local tree = parser:parse()[1]
  parser:register_cbs({
    on_bytes = semhl_on_bytes,
    on_changedtree = semhl_on_tree_change,
    on_detach = function() semhl_unload(buffer) end,
  }, true)
  semhl_process_range(parser, tree, buffer, true)
  vim.api.nvim_set_hl_ns(M._ns)
end

local function semhl_autoload(ev)
  LOGGER.debug("func: _autoload");
  local autocommands = vim.api.nvim_get_autocmds({
    group = M._semhl_augup,
    buffer = ev.buf,
    event = { "BufEnter" }
  })

  if autocommands == nil or next(autocommands) == nil then
    vim.api.nvim_create_autocmd(
      { "BufEnter" },
      { buffer = ev.buf, callback = function(env) semhl_on_buffer_enter(env.buf) end, group = M._semhl_augup })
  end
end

M.setup = function(opt)
  opt = opt or {}

  LOGGER.debug("func: setup");
  if M._init then
    return
  end

  if opt.filetypes == nil then
    opt.filetypes = {}
  end

  M._DISABLE_CHECK_FUNC = opt.disable or semhl_check_file_size
  M._MAX_FILE_SIZE = opt.max_file_size or MAX_FILE_SIZE

  vim.api.nvim_create_user_command("SemhlLoad", M.load, {})
  vim.api.nvim_create_user_command("SemhlUnload", M.unload, {})

  M._ns = vim.api.nvim_create_namespace(PLUGIN_NAME)
  M._semhl_augup = vim.api.nvim_create_augroup(PLUGIN_NAME, { clear = true })

  vim.api.nvim_create_autocmd({ "FileType" },
    { pattern = opt.filetypes, callback = semhl_autoload, group = M._semhl_augup })
  M._init = true
end

M.load = function()
  LOGGER.debug("func: load");
  local buffer = vim.api.nvim_get_current_buf()
  semhl_on_buffer_enter(buffer)
end

M.unload = function()
  LOGGER.debug("func: unload");
  local buffer = vim.api.nvim_get_current_buf()
  semhl_unload(buffer)
end

return M
