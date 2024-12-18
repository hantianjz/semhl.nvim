local M = {}

local PLUGIN_NAME = "semhl"

M._HIGHLIGHT_CACHE = {}
M._WORD_CACHE = {}

function ts_diff(start_ts, end_ts)
  local sec = end_ts.sec - start_ts.sec
  local nsec = end_ts.nsec - start_ts.nsec
  if nsec < 0 then
    nsec = 1000000000 + nsec
    sec = sec - 1
  end
  pad = string.rep("0", 9 - string.len("" .. nsec))

  return sec .. "." .. pad .. nsec
end

local LOGGER = require("plenary.log").new({
  plugin = PLUGIN_NAME,
  level = "debug",
  outfile = "semhl.log",
})

local function create_highlight(ns, rgb_hex)
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

local function highlight_node(buffer, node_text, srow, scol, erow, ecol, create_new)
  local hlname = M._WORD_CACHE[node_text]

  -- if not create_new then
  --   LOGGER.info("processing: " .. node_text .. "[" .. srow .. "," .. erow .. "] ")
  -- end

  -- Only create new highlight if create_new is true
  if hlname == nil and create_new then
    local random_range = 1000;
    local hsv = { math.random(0, random_range) / random_range, math.random(0, random_range) / random_range, math
    .random(0, random_range) / random_range }
    local c = require("color_generator").color_generate(hsv[1], hsv[2], hsv[3])
    hlname = create_highlight(M._ns, string.sub(c, 2))
  end

  if hlname then
    -- Find NS for diag and make sure there isn't extmark exist for the same range already
    -- local diag_idx = next(vim.diagnostic.get_namespaces())
    -- local existing_extmark = nil
    -- if diag_idx then
    --   local diag_ns = vim.diagnostic.get_namespaces()[diag_idx].user_data.underline_ns
    --   if diag_ns then
    --     existing_extmark = vim.api.nvim_buf_get_extmarks(buffer, diag_ns, { srow, scol }, { erow, ecol }, {})
    --   end
    -- end
    local existing_extmark = vim.api.nvim_buf_get_extmarks(buffer, M._ns, { srow, scol }, { erow, ecol }, {})

    if existing_extmark == nil or next(existing_extmark) == nil then
      if not create_new then
        LOGGER.info("ADDING: " ..
        buffer .. " - " .. node_text .. "[" .. srow .. "," .. scol .. "," .. ecol .. "] " .. hlname)
      end
      vim.api.nvim_buf_set_extmark(buffer, M._ns, srow, scol, { end_col = ecol, hl_group = hlname })
    end

    M._WORD_CACHE[node_text] = hlname
  end
end

local function process_range(start_row, end_row, parser, tree, buffer, create_new)
  local query = vim.treesitter.query.parse(parser:lang(), "(identifier) @id")
  for _, node in query:iter_captures(tree:root(), buffer, start_row, end_row) do
    local row1, col1, row2, col2 = node:range() -- range of the capture
    local node_text = vim.treesitter.get_node_text(node, buffer)
    highlight_node(buffer, node_text, row1, col1, row2, col2, create_new)
  end
end

local function _new_on_buffer_enter(buffer)
  LOGGER.info("Buffer enter")
  local parser = vim.treesitter.get_parser(buffer, nil)

  local function on_bytes(bufno, tick, srow, scol, sbyte, oerow, oecol, oebyte, nerow, necol, nebyte)
    local tree = parser:parse()[1]
    local start_ts = vim.uv.clock_gettime("realtime")

    process_range(srow, srow + oerow, parser, tree, bufno, false)

    local end_ts = vim.uv.clock_gettime("realtime")
    LOGGER.debug("Diff run took " .. ts_diff(start_ts, end_ts) .. " sec")
  end

  local tree = parser:parse()[1]
  parser:register_cbs({ on_bytes = on_bytes }, true)
  process_range(nil, nil, parser, tree, buffer, true)
  vim.api.nvim_set_hl_ns(M._ns)
end

local function _autoload(ev)
  LOGGER.debug("func: _autoload");
  local autocommands = vim.api.nvim_get_autocmds({
    group = M._semhl_augup,
    buffer = ev.buf,
    event = { "BufEnter" }
  })

  if autocommands == nil or next(autocommands) == nil then
    LOGGER.debug("!!!!Create autocommands for " .. ev.buf .. " !!!!")
    vim.api.nvim_create_autocmd(
      { "BufEnter" },
      { buffer = ev.buf, callback = function(env) _new_on_buffer_enter(env.buf) end, group = M._semhl_augup })
    -- vim.api.nvim_create_autocmd(
    --   { "BufHidden" },
    --   { buffer = ev.buf, callback = function(env) _on_buffer_hide(env.buf) end, group = M._semhl_augup })
    -- vim.api.nvim_create_autocmd(
    --   { "TextChanged", "TextChangedP" },
    --   { buffer = ev.buf, callback = function(env) _on_text_change(env.buf) end, group = M._semhl_augup })
  end

  -- TODO: Figure out how to add highlight incrementally
  -- vim.api.nvim_buf_attach(ev.buf, false, {
  --   on_lines = function(event_type, buf, changed_tick, firstline, lastline, new_lastline)
  --     vim.schedule(function()
  --       print(event_type, buf, changed_tick, firstline, lastline, new_lastline)
  --     end)
  --   end,
  --   on_detach = function()
  --   end,
  -- })
end

M.setup = function(filetypes)
  LOGGER.debug("func: setup");
  if M._init then
    return
  end

  vim.api.nvim_create_user_command("SemhlLoad", M.load, {})
  vim.api.nvim_create_user_command("SemhlUnload", M.unload, {})

  M._ns = vim.api.nvim_create_namespace(PLUGIN_NAME)
  M._semhl_augup = vim.api.nvim_create_augroup(PLUGIN_NAME, { clear = true })

  vim.api.nvim_create_autocmd({ "FileType" },
    { pattern = filetypes, callback = _autoload, group = M._semhl_augup })
  M._init = true
end

M.load = function()
  LOGGER.debug("func: load");
  local buffer = vim.api.nvim_get_current_buf()
  _autoload({ buf = buffer })
end

M.unload = function()
  LOGGER.debug("func: unload");
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(buffer, M._ns, 0, -1)

  local autocommands = vim.api.nvim_get_autocmds({
    group = M._semhl_augup,
    buffer = buffer
  })

  for _, cmd in pairs(autocommands) do
    vim.api.nvim_del_autocmd(cmd.id)
  end
end

return M
