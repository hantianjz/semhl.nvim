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
M._USE_ON_BYTES = true
M._DEFERRED_TIMER_TASKS = {} -- { [buffer] = timer_handle }
M._BUFFER_PARSERS = {} -- Track parsers for cleanup

-- Cache parsed queries per language
M._QUERY_CACHE = {}
M._DEFAULT_QUERY = "(identifier) @id"
M._TS_QUERY = {
  ["rust"] = "((identifier) @sym) ((field_identifier) @sym)"
}

M._PENDING_RANGES = {} -- Batch multiple ranges for processing

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

local function semhl_create_highlight(rgb_hex)
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
  -- Define groups in global namespace so they remain visible if other plugins
  -- change active highlight namespaces/window-local hl state.
  vim.api.nvim_set_hl(0, highlight_name, { fg = "#" .. rgb_hex })
  M._HIGHLIGHT_CACHE[cache_key] = highlight_name
  return highlight_name
end

local function semhl_del_extmarks_in_range(buffer, range)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  local srow, scol, erow, ecol = unpack(range)
  local ok, existing_extmark = pcall(vim.api.nvim_buf_get_extmarks, buffer, M._ns, { srow, scol }, { erow, ecol }, {
    overlap = true,
  })
  if not ok then
    LOGGER.debug("Failed to get extmarks: " .. tostring(existing_extmark))
    return
  end
  for _, mark in pairs(existing_extmark) do
    local id = unpack(mark)
    ---@diagnostic disable-next-line: param-type-mismatch
    local del_ok, del_err = pcall(vim.api.nvim_buf_del_extmark, buffer, M._ns, id)
    if not del_ok then
      LOGGER.debug("Failed to delete extmark " .. id .. ": " .. tostring(del_err))
    end
  end
end

local function semhl_highlight_node(buffer, node_text, range, create_new)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end

  local hlname = M._WORD_CACHE[node_text]

  semhl_del_extmarks_in_range(buffer, range)

  -- If no highlight name cached, try to get/generate one
  if hlname == nil then
    local color_gen = require("color_generator")

    -- Check persistent cache first
    local cached = color_gen.get_cached_color(node_text)

    local c
    if cached then
      -- Use cached color
      c = cached
    elseif create_new then
      -- Generate new color only if create_new is true
      c = color_gen.color_generate()
      color_gen.cache_color(node_text, c)
    end

    -- Create highlight if we got a color
    if c then
      hlname = semhl_create_highlight(string.sub(c, 2))
    end
  end

  if hlname then
    local srow, scol, erow, ecol = unpack(range)
    local ok, ext_id = pcall(vim.api.nvim_buf_set_extmark, buffer, M._ns, srow, scol,
      {
        end_row = erow,
        end_col = ecol,
        hl_group = hlname,
        end_right_gravity = true,
        right_gravity = true,
        invalidate = false,
        undo_restore = true,
        priority = HL_PRIORITY,
      })

    if ok then
      LOGGER.debug("ADDED: " .. ext_id .. " : " ..
        buffer .. " - " .. node_text .. "[" .. srow .. "," .. scol .. "," .. ecol .. "] " .. hlname)
      M._WORD_CACHE[node_text] = hlname
    else
      LOGGER.debug("Failed to set extmark: " .. tostring(ext_id))
    end
  end
end

-- Merge two ranges into a single encompassing range
local function semhl_merge_ranges(range1, range2)
  if not range1 then return range2 end
  if not range2 then return range1 end

  local srow1, scol1, erow1, ecol1 = unpack(range1)
  local srow2, scol2, erow2, ecol2 = unpack(range2)

  -- Calculate the encompassing range
  local srow, scol, erow, ecol

  if srow1 < srow2 or (srow1 == srow2 and scol1 < scol2) then
    srow, scol = srow1, scol1
  else
    srow, scol = srow2, scol2
  end

  if erow1 > erow2 or (erow1 == erow2 and ecol1 > ecol2) then
    erow, ecol = erow1, ecol1
  else
    erow, ecol = erow2, ecol2
  end

  return { srow, scol, erow, ecol }
end

-- Check if ranges are adjacent or overlapping
local function semhl_ranges_overlap_or_adjacent(range1, range2)
  local srow1, _, erow1, _ = unpack(range1)
  local srow2, _, erow2, _ = unpack(range2)

  -- Check if ranges overlap or are within 1 line of each other
  return (srow1 <= erow2 + 1 and erow1 >= srow2 - 1)
end

local function semhl_relative_end_col(start_col, row_delta, rel_col)
  if row_delta == 0 then
    return start_col + rel_col
  end
  return rel_col
end

-- Batch and merge pending ranges for a buffer
local function semhl_get_batched_ranges(buffer)
  local ranges = M._PENDING_RANGES[buffer]
  if not ranges or #ranges == 0 then
    return nil
  end

  -- Sort ranges by start row
  table.sort(ranges, function(a, b)
    return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
  end)

  -- Merge overlapping or adjacent ranges
  local merged = {}
  local current = ranges[1]

  for i = 2, #ranges do
    if semhl_ranges_overlap_or_adjacent(current, ranges[i]) then
      current = semhl_merge_ranges(current, ranges[i])
    else
      table.insert(merged, current)
      current = ranges[i]
    end
  end
  table.insert(merged, current)

  -- Clear pending ranges
  M._PENDING_RANGES[buffer] = {}

  return merged
end

-- Check if a node is inside a comment by walking up the tree
local function semhl_is_inside_comment(node)
  local parent = node:parent()
  while parent do
    local node_type = parent:type()
    -- Check for common comment node types across languages
    if node_type == "comment"
        or node_type == "line_comment"
        or node_type == "block_comment"
        or node_type == "multiline_comment"
        or node_type:match("^comment") then
      return true
    end
    parent = parent:parent()
  end
  return false
end

local function semhl_get_or_create_query(lang)
  -- Check if we have a cached query for this language
  if M._QUERY_CACHE[lang] then
    return M._QUERY_CACHE[lang]
  end

  local query_str = M._TS_QUERY[lang] or M._DEFAULT_QUERY

  -- Parse and cache the query
  local ok, query = pcall(vim.treesitter.query.parse, lang, query_str)
  if ok then
    M._QUERY_CACHE[lang] = query
    LOGGER.debug("Cached query for language: " .. lang)
    return query
  else
    LOGGER.warn("Failed to parse Tree-sitter query for " .. lang .. ": " .. tostring(query))
    return nil
  end
end

-- Helper function to safely parse tree from parser
local function semhl_safe_parse(parser, error_context)
  local ok, parse_result = pcall(function() return parser:parse() end)
  if not ok then
    LOGGER.warn("Failed to parse tree " .. error_context .. ": " .. tostring(parse_result))
    return nil
  end

  local tree = parse_result[1]
  if not tree then
    LOGGER.warn("No tree returned from parser " .. error_context)
    return nil
  end

  return tree
end

local function semhl_process_range(parser, tree, buffer, create_new, range)
  -- Get or create cached query for this language
  local query = semhl_get_or_create_query(parser:lang())
  if not query then
    return
  end

  local erow = nil
  range = range or {}
  if range[3] then
    erow = range[3] + 1
  end
  if range and next(range) then
    semhl_del_extmarks_in_range(buffer, range)
  end

  -- Safely iterate captures with error handling
  local ok_iter, iter_result = pcall(function()
    for _, node in query:iter_captures(tree:root(), buffer, range[1], erow) do
      -- Skip identifiers inside comments
      if semhl_is_inside_comment(node) then
        goto continue
      end
      local node_text = vim.treesitter.get_node_text(node, buffer)
      -- If processing a range (edit), always re-highlight since we deleted all extmarks in range
      -- If initial load (create_new), highlight everything
      local should_highlight = create_new or (range and next(range))
      if should_highlight then
        semhl_highlight_node(buffer, node_text, { node:range() }, create_new)
      end
      ::continue::
    end
  end)

  if not ok_iter then
    LOGGER.warn("Failed to iterate Tree-sitter captures: " .. tostring(iter_result))
  end
end

local function semhl_cleanup_buffer(buffer)
  -- Clean up all resources for a buffer

  -- Stop and clear pending timer for THIS buffer only
  if M._DEFERRED_TIMER_TASKS[buffer] then
    vim.loop.timer_stop(M._DEFERRED_TIMER_TASKS[buffer])
    M._DEFERRED_TIMER_TASKS[buffer] = nil
  end

  -- Clear the parser reference
  M._BUFFER_PARSERS[buffer] = nil

  -- Clear any pending ranges
  M._PENDING_RANGES[buffer] = nil

  -- Clear highlights
  if vim.api.nvim_buf_is_valid(buffer) then
    pcall(vim.api.nvim_buf_clear_namespace, buffer, M._ns, 0, -1)
  end

  LOGGER.debug("Cleaned up buffer: " .. buffer)
end

local function semhl_unload(buffer)
  semhl_cleanup_buffer(buffer)
end

local function semhl_on_buffer_enter(buffer)
  -- If disable function check returns true, bail out and do nothing for this file
  if M._DISABLE_CHECK_FUNC and M._DISABLE_CHECK_FUNC(buffer) then
    M.unload()
    return
  end

  -- Avoid duplicate callback/autocmd registration when re-entering a buffer.
  -- Multiple registrations can cause racey or inconsistent highlight updates.
  if M._BUFFER_PARSERS[buffer] then
    LOGGER.debug("Buffer already attached, skipping duplicate setup: " .. buffer)
    return
  end

  pcall(vim.api.nvim_buf_clear_namespace, buffer, M._ns, 0, -1)

  -- Safely get parser with error handling
  local ok, parser = pcall(vim.treesitter.get_parser, buffer, nil)
  if not ok then
    LOGGER.warn("Failed to get Tree-sitter parser for buffer " .. buffer .. ": " .. tostring(parser))
    return
  end

  local function semhl_on_bytes(bufno, tick, srow, scol, _, oerow, oecol, _, nerow, necol, _)
    if not vim.api.nvim_buf_is_loaded(buffer) then
      LOGGER.debug("SEMHL_ON_BYTES: callback on unloaded buffer: " .. buffer)
      return
    end

    -- Build dirty range as the union of old and new spans.
    -- This prevents stale extmarks after delete/replace/move operations.
    local old_range = { srow, scol, srow + oerow, semhl_relative_end_col(scol, oerow, oecol) }
    local new_range = { srow, scol, srow + nerow, semhl_relative_end_col(scol, nerow, necol) }
    local dirty_range = semhl_merge_ranges(old_range, new_range)

    -- Add range to pending list for batching
    M._PENDING_RANGES[bufno] = M._PENDING_RANGES[bufno] or {}
    table.insert(M._PENDING_RANGES[bufno], dirty_range)

    local function semhl_do_batched_process()
      LOGGER.debug("SEMHL_ON_BYTES: Processing batched ranges for buffer " .. bufno)

      -- Clear timer reference for this buffer
      M._DEFERRED_TIMER_TASKS[bufno] = nil

      -- Check buffer is still valid
      if not vim.api.nvim_buf_is_valid(bufno) then
        return
      end

      -- Get batched ranges
      local ranges = semhl_get_batched_ranges(bufno)
      if not ranges or #ranges == 0 then
        return
      end

      -- Safely parse with error handling
      local tree = semhl_safe_parse(parser, "in on_bytes")
      if not tree then
        return
      end

      local start_ts = vim.uv.clock_gettime("realtime")

      -- Process each batched range
      for _, range in ipairs(ranges) do
        LOGGER.debug(string.format("Processing range: %d:%d-%d:%d", unpack(range)))
        semhl_process_range(parser, tree, bufno, false, range)
      end

      local end_ts = vim.uv.clock_gettime("realtime")
      LOGGER.debug("SEMHL_ON_BYTES batch processing took " .. semhl_ts_diff(start_ts, end_ts) .. " sec")
    end

    -- Cancel any existing timer for this buffer
    if M._DEFERRED_TIMER_TASKS[bufno] then
      vim.loop.timer_stop(M._DEFERRED_TIMER_TASKS[bufno])
    end

    local defer_time = vim.defer_fn(semhl_do_batched_process, BYTE_CHANGE_DELAY_MS)
    M._DEFERRED_TIMER_TASKS[bufno] = defer_time
  end

  local function semhl_on_tree_change(ranges, tree)
    if not vim.api.nvim_buf_is_loaded(buffer) then
      LOGGER.debug("SEMHL_ON_TREE_CHANGE: callback on unloaded buffer: " .. buffer)
      return
    end

    local start_ts = vim.uv.clock_gettime("realtime")
    if ranges and next(ranges) then
      -- Stop pending timer for THIS buffer only (tree change supersedes pending byte changes)
      if M._DEFERRED_TIMER_TASKS[buffer] then
        vim.loop.timer_stop(M._DEFERRED_TIMER_TASKS[buffer])
        M._DEFERRED_TIMER_TASKS[buffer] = nil
      end
      -- Clear pending ranges for this buffer since tree change handles them
      M._PENDING_RANGES[buffer] = {}

      for _, range in pairs(ranges) do
        local srow, scol, _, erow, ecol, _ = unpack(range)
        LOGGER.debug("SEMHL_ON_TREE_CHANGE" .. string.format("-- %d:%d-%d:%d", srow, scol, erow, ecol))
        semhl_process_range(parser, tree, buffer, false, { srow, scol, erow, ecol })
      end
      local end_ts = vim.uv.clock_gettime("realtime")
      LOGGER.debug("SEMHL_ON_TREE_CHANGE run took " .. semhl_ts_diff(start_ts, end_ts) .. " sec")
    end
  end

  -- Track parser for cleanup
  M._BUFFER_PARSERS[buffer] = parser

  local parser_callbacks = {
    on_changedtree = semhl_on_tree_change,
    on_detach = function(bufno)
      LOGGER.debug("Parser detached for buffer: " .. bufno)
      semhl_cleanup_buffer(bufno)
    end,
  }

  if M._USE_ON_BYTES then
    parser_callbacks.on_bytes = semhl_on_bytes
  end

  parser:register_cbs(parser_callbacks, true)

  -- Function to refresh all highlights in the buffer
  local function semhl_refresh_buffer()
    if not vim.api.nvim_buf_is_valid(buffer) or not M._BUFFER_PARSERS[buffer] then
      return
    end
    LOGGER.debug("Refreshing highlights for buffer: " .. buffer)

    -- Full-buffer refresh must clear stale extmarks first.
    pcall(vim.api.nvim_buf_clear_namespace, buffer, M._ns, 0, -1)

    -- Re-parse and process entire buffer
    local fresh_tree = semhl_safe_parse(parser, "refresh for buffer " .. buffer)
    if fresh_tree then
      semhl_process_range(parser, fresh_tree, buffer, true)
    end
  end

  -- Register autocmd for re-rendering on save.
  -- Avoid BufLeave refresh to reduce unnecessary churn and racey updates.
  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    buffer = buffer,
    callback = semhl_refresh_buffer,
    group = M._semhl_augup,
  })

  -- Safely parse and process initial content
  local tree = semhl_safe_parse(parser, "for buffer " .. buffer)
  if tree then
    semhl_process_range(parser, tree, buffer, true)
  end
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

local function semhl_on_background_change()
  LOGGER.debug("Background changed, clearing caches")
  -- Clear color generator's background cache
  require("color_generator").clear_background_cache()

  -- Clear word cache to regenerate colors
  M._WORD_CACHE = {}

  -- Refresh all active buffers (copy keys to avoid iteration issues)
  local buffers = {}
  for buffer, _ in pairs(M._BUFFER_PARSERS) do
    table.insert(buffers, buffer)
  end

  for _, buffer in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buffer) then
      -- Clear existing highlights
      pcall(vim.api.nvim_buf_clear_namespace, buffer, M._ns, 0, -1)

      -- Re-process the buffer with new colors
      local parser = M._BUFFER_PARSERS[buffer]
      if parser then
        local tree = semhl_safe_parse(parser, "on background change for buffer " .. buffer)
        if tree then
          semhl_process_range(parser, tree, buffer, true)
        end
      end
    end
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
  M._USE_ON_BYTES = opt.use_on_bytes ~= false

  -- Override default queries with user-provided queries
  if opt.queries then
    for lang, query_str in pairs(opt.queries) do
      M._TS_QUERY[lang] = query_str
      LOGGER.debug("Override query for language: " .. lang)
    end
  end

  -- Setup color generator with Delta-E thresholds and L range
  local color_gen = require("color_generator")
  local min_delta_e = opt.min_delta_e or 5
  local target_delta_e = opt.target_delta_e or 15
  local L_min = opt.L_min -- nil means auto-detect based on background
  local L_max = opt.L_max -- nil means auto-detect based on background
  color_gen.setup(nil, nil, min_delta_e, target_delta_e, L_min, L_max)

  -- Log background color on startup
  local background = vim.o.background
  local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal" })
  local bg_color = normal_hl.bg or "none"
  if type(bg_color) == "number" then
    bg_color = string.format("#%06x", bg_color)
  end

  local L_range_str = "auto"
  if L_min or L_max then
    L_range_str = string.format("[%s-%s]", tostring(L_min or L_range_str), tostring(L_max or L_range_str))
  end

  LOGGER.info(string.format("[semhl] Startup: background=%s (rgb=%s), min_delta_e=%d, target_delta_e=%d, L_range=%s",
    background, bg_color, min_delta_e, target_delta_e, L_range_str))

  vim.api.nvim_create_user_command("SemhlLoad", M.load, {})
  vim.api.nvim_create_user_command("SemhlUnload", M.unload, {})
  vim.api.nvim_create_user_command("SemhlToggle", M.toggle, {})

  M._ns = vim.api.nvim_create_namespace(PLUGIN_NAME)
  M._semhl_augup = vim.api.nvim_create_augroup(PLUGIN_NAME, { clear = true })

  -- Watch for background changes
  vim.api.nvim_create_autocmd("OptionSet", {
    pattern = "background",
    callback = semhl_on_background_change,
    group = M._semhl_augup
  })

  if opt.filetypes and next(opt.filetypes) then
    vim.api.nvim_create_autocmd({ "FileType" },
      { pattern = opt.filetypes, callback = semhl_autoload, group = M._semhl_augup })
  end
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

M.toggle = function()
  LOGGER.debug("func: toggle");
  local buffer = vim.api.nvim_get_current_buf()
  if M._BUFFER_PARSERS[buffer] then
    semhl_unload(buffer)
  else
    semhl_on_buffer_enter(buffer)
  end
end

return M
