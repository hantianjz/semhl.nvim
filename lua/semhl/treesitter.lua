---@diagnostic disable: undefined-field
local M = {}

local PLUGIN_NAME = "semhl"
local BYTE_CHANGE_DELAY_MS = 50

-- Cache parsed queries per language
M._QUERY_CACHE = {}
M._DEFAULT_QUERY = "(identifier) @id"
M._TS_QUERY = {
  ["rust"] = "((identifier) @sym) ((field_identifier) @sym)"
}

M._BUFFER_PARSERS = {} -- Track parsers for cleanup
M._DEFERRED_TIMER_TASKS = {} -- { [buffer] = timer_handle }
M._PENDING_RANGES = {} -- Batch multiple ranges for processing

local LOGGER = require("plenary.log").new({
  plugin = PLUGIN_NAME,
  level = "warn",
})

-- Setup with user-provided query overrides
M.setup = function(queries)
  if queries then
    for lang, query_str in pairs(queries) do
      M._TS_QUERY[lang] = query_str
      LOGGER.debug("Override query for language: " .. lang)
    end
  end
end

-- Check if a node is inside a comment by walking up the tree
local function is_inside_comment(node)
  local parent = node:parent()
  while parent do
    local node_type = parent:type()
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

local function get_or_create_query(lang)
  if M._QUERY_CACHE[lang] then
    return M._QUERY_CACHE[lang]
  end

  local query_str = M._TS_QUERY[lang] or M._DEFAULT_QUERY

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
local function safe_parse(parser, error_context)
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

-- Merge two ranges into a single encompassing range
local function merge_ranges(range1, range2)
  if not range1 then return range2 end
  if not range2 then return range1 end

  local srow1, scol1, erow1, ecol1 = unpack(range1)
  local srow2, scol2, erow2, ecol2 = unpack(range2)

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
local function ranges_overlap_or_adjacent(range1, range2)
  local srow1, _, erow1, _ = unpack(range1)
  local srow2, _, erow2, _ = unpack(range2)

  return (srow1 <= erow2 + 1 and erow1 >= srow2 - 1)
end

-- Batch and merge pending ranges for a buffer
local function get_batched_ranges(buffer)
  local ranges = M._PENDING_RANGES[buffer]
  if not ranges or #ranges == 0 then
    return nil
  end

  table.sort(ranges, function(a, b)
    return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
  end)

  local merged = {}
  local current = ranges[1]

  for i = 2, #ranges do
    if ranges_overlap_or_adjacent(current, ranges[i]) then
      current = merge_ranges(current, ranges[i])
    else
      table.insert(merged, current)
      current = ranges[i]
    end
  end
  table.insert(merged, current)

  M._PENDING_RANGES[buffer] = {}

  return merged
end

local function process_range(parser, tree, buffer, ns, highlight_node_fn, del_extmarks_fn, create_new, range)
  local query = get_or_create_query(parser:lang())
  if not query then
    return
  end

  local erow = nil
  range = range or {}
  if range[3] then
    erow = range[3] + 1
  end
  if range and next(range) then
    del_extmarks_fn(buffer, range)
  end

  local ok_iter, iter_result = pcall(function()
    for _, node in query:iter_captures(tree:root(), buffer, range[1], erow) do
      if is_inside_comment(node) then
        goto continue
      end
      local node_text = vim.treesitter.get_node_text(node, buffer)
      local should_highlight = create_new or (range and next(range))
      if should_highlight then
        highlight_node_fn(buffer, node_text, { node:range() }, create_new)
      end
      ::continue::
    end
  end)

  if not ok_iter then
    LOGGER.warn("Failed to iterate Tree-sitter captures: " .. tostring(iter_result))
  end
end

-- Attach to a buffer
-- @param buffer number: Buffer number
-- @param ns number: Namespace for highlights
-- @param highlight_node_fn function: Function to highlight a node (buffer, text, range, create_new)
-- @param del_extmarks_fn function: Function to delete extmarks in range (buffer, range)
-- @param augroup number: Autogroup for autocmds
M.attach = function(buffer, ns, highlight_node_fn, del_extmarks_fn, augroup)
  local ok, parser = pcall(vim.treesitter.get_parser, buffer, nil)
  if not ok then
    LOGGER.warn("Failed to get Tree-sitter parser for buffer " .. buffer .. ": " .. tostring(parser))
    return false
  end

  local function on_bytes(bufno, tick, srow, scol, _, _, _, _, nerow, necol, _)
    if not vim.api.nvim_buf_is_loaded(buffer) then
      LOGGER.debug("on_bytes: callback on unloaded buffer: " .. buffer)
      return
    end

    M._PENDING_RANGES[bufno] = M._PENDING_RANGES[bufno] or {}
    table.insert(M._PENDING_RANGES[bufno], { srow, scol, srow + nerow, necol })

    local function do_batched_process()
      LOGGER.debug("on_bytes: Processing batched ranges for buffer " .. bufno)

      M._DEFERRED_TIMER_TASKS[bufno] = nil

      if not vim.api.nvim_buf_is_valid(bufno) then
        return
      end

      local ranges = get_batched_ranges(bufno)
      if not ranges or #ranges == 0 then
        return
      end

      local tree = safe_parse(parser, "in on_bytes")
      if not tree then
        return
      end

      for _, range in ipairs(ranges) do
        LOGGER.debug(string.format("Processing range: %d:%d-%d:%d", unpack(range)))
        process_range(parser, tree, bufno, ns, highlight_node_fn, del_extmarks_fn, false, range)
      end
    end

    if M._DEFERRED_TIMER_TASKS[bufno] then
      vim.loop.timer_stop(M._DEFERRED_TIMER_TASKS[bufno])
    end

    local defer_time = vim.defer_fn(do_batched_process, BYTE_CHANGE_DELAY_MS)
    M._DEFERRED_TIMER_TASKS[bufno] = defer_time
  end

  local function on_tree_change(ranges, tree)
    if not vim.api.nvim_buf_is_loaded(buffer) then
      LOGGER.debug("on_tree_change: callback on unloaded buffer: " .. buffer)
      return
    end

    if ranges and next(ranges) then
      if M._DEFERRED_TIMER_TASKS[buffer] then
        vim.loop.timer_stop(M._DEFERRED_TIMER_TASKS[buffer])
        M._DEFERRED_TIMER_TASKS[buffer] = nil
      end
      M._PENDING_RANGES[buffer] = {}

      for _, range in pairs(ranges) do
        local srow, scol, _, erow, ecol, _ = unpack(range)
        LOGGER.debug("on_tree_change" .. string.format("-- %d:%d-%d:%d", srow, scol, erow, ecol))
        process_range(parser, tree, buffer, ns, highlight_node_fn, del_extmarks_fn, false, { srow, scol, erow, ecol })
      end
    end
  end

  M._BUFFER_PARSERS[buffer] = parser

  parser:register_cbs({
    on_bytes = on_bytes,
    on_changedtree = on_tree_change,
    on_detach = function(bufno)
      LOGGER.debug("Parser detached for buffer: " .. bufno)
      M.detach(bufno)
    end,
  }, true)

  -- Register autocmds for re-rendering on save and buffer leave
  vim.api.nvim_create_autocmd({ "BufWritePost", "BufLeave" }, {
    buffer = buffer,
    callback = function()
      M.refresh(buffer, ns, highlight_node_fn, del_extmarks_fn)
    end,
    group = augroup,
  })

  -- Process entire buffer initially
  local tree = safe_parse(parser, "for buffer " .. buffer)
  if tree then
    process_range(parser, tree, buffer, ns, highlight_node_fn, del_extmarks_fn, true)
  end

  return true
end

-- Detach from a buffer
M.detach = function(buffer)
  if M._DEFERRED_TIMER_TASKS[buffer] then
    vim.loop.timer_stop(M._DEFERRED_TIMER_TASKS[buffer])
    M._DEFERRED_TIMER_TASKS[buffer] = nil
  end

  M._BUFFER_PARSERS[buffer] = nil
  M._PENDING_RANGES[buffer] = nil

  LOGGER.debug("Detached from buffer: " .. buffer)
end

-- Refresh highlights for a buffer
M.refresh = function(buffer, ns, highlight_node_fn, del_extmarks_fn)
  if not vim.api.nvim_buf_is_valid(buffer) or not M._BUFFER_PARSERS[buffer] then
    return
  end
  LOGGER.debug("Refreshing highlights for buffer: " .. buffer)

  local parser = M._BUFFER_PARSERS[buffer]
  if parser then
    local fresh_tree = safe_parse(parser, "refresh for buffer " .. buffer)
    if fresh_tree then
      process_range(parser, fresh_tree, buffer, ns, highlight_node_fn, del_extmarks_fn, true)
    end
  end
end

-- Check if buffer has an active parser
M.is_attached = function(buffer)
  return M._BUFFER_PARSERS[buffer] ~= nil
end

return M
