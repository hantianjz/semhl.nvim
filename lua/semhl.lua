---@diagnostic disable: undefined-field
local M = {}

local PLUGIN_NAME = "semhl"
local MAX_FILE_SIZE = 100 * 1024
local HL_PRIORITY = 130

M._HIGHLIGHT_CACHE = {}
M._WORD_CACHE = {}
M._LOG_LEVEL = "warn"
M._DISABLE_CHECK_FUNC = nil
M._MAX_FILE_SIZE = 0
M._BUFFER_SOURCES = {} -- Track which source is active per buffer

-- Source configuration: "treesitter" or "lsp"
M._source = "treesitter"

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
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  local srow, scol, erow, ecol = unpack(range)
  local ok, existing_extmark = pcall(vim.api.nvim_buf_get_extmarks, buffer, M._ns, { srow, scol }, { erow, ecol }, {})
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
      hlname = semhl_create_highlight(M._ns, string.sub(c, 2))
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

local function semhl_cleanup_buffer(buffer)
  -- Clean up source module
  local source = M._BUFFER_SOURCES[buffer]
  if source == "treesitter" then
    require("semhl.treesitter").detach(buffer)
  elseif source == "lsp" then
    require("semhl.lsp").detach(buffer)
  end

  M._BUFFER_SOURCES[buffer] = nil

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

  pcall(vim.api.nvim_buf_clear_namespace, buffer, M._ns, 0, -1)

  -- Delegate to appropriate source module
  local attached = false
  if M._source == "lsp" then
    attached = require("semhl.lsp").attach(
      buffer, M._ns, semhl_highlight_node, semhl_del_extmarks_in_range, M._semhl_augup
    )
    if attached then
      M._BUFFER_SOURCES[buffer] = "lsp"
    end
  else
    attached = require("semhl.treesitter").attach(
      buffer, M._ns, semhl_highlight_node, semhl_del_extmarks_in_range, M._semhl_augup
    )
    if attached then
      M._BUFFER_SOURCES[buffer] = "treesitter"
    end
  end

  if not attached then
    LOGGER.debug("Failed to attach source '" .. M._source .. "' for buffer " .. buffer)
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
  for buffer, _ in pairs(M._BUFFER_SOURCES) do
    table.insert(buffers, buffer)
  end

  for _, buffer in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buffer) then
      -- Clear existing highlights
      pcall(vim.api.nvim_buf_clear_namespace, buffer, M._ns, 0, -1)

      -- Refresh using the appropriate source module
      local source = M._BUFFER_SOURCES[buffer]
      if source == "treesitter" then
        require("semhl.treesitter").refresh(buffer, M._ns, semhl_highlight_node, semhl_del_extmarks_in_range)
      elseif source == "lsp" then
        require("semhl.lsp").refresh(buffer, M._ns, semhl_highlight_node, semhl_del_extmarks_in_range)
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

  -- Set highlight source
  M._source = opt.source or "treesitter"
  if M._source ~= "treesitter" and M._source ~= "lsp" then
    LOGGER.warn("Invalid source '" .. tostring(M._source) .. "', defaulting to 'treesitter'")
    M._source = "treesitter"
  end

  M._DISABLE_CHECK_FUNC = opt.disable or semhl_check_file_size
  M._MAX_FILE_SIZE = opt.max_file_size or MAX_FILE_SIZE

  -- Setup source modules
  if M._source == "treesitter" then
    require("semhl.treesitter").setup(opt.queries)
  else
    require("semhl.lsp").setup()
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

  LOGGER.info(string.format("[semhl] Startup: source=%s, background=%s (rgb=%s), min_delta_e=%d, target_delta_e=%d, L_range=%s",
    M._source, background, bg_color, min_delta_e, target_delta_e, L_range_str))

  vim.api.nvim_create_user_command("SemhlLoad", M.load, {})
  vim.api.nvim_create_user_command("SemhlUnload", M.unload, {})
  vim.api.nvim_create_user_command("SemhlToggle", M.toggle, {})

  M._ns = vim.api.nvim_create_namespace(PLUGIN_NAME)
  vim.api.nvim_set_hl_ns(M._ns) -- Set namespace once during setup
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
  if M._BUFFER_SOURCES[buffer] then
    semhl_unload(buffer)
  else
    semhl_on_buffer_enter(buffer)
  end
end

return M
