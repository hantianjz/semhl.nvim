local M = {}

M._HIGHLIGHT_CACHE = {}
M._WORD_CACHE = {}


local function create_highlight(ns, rgb_hex)
  rgb_hex = rgb_hex:lower()
  local cache_key = table.concat({ "sfg", rgb_hex }, "_")
  local highlight_name = M._HIGHLIGHT_CACHE[cache_key]

  -- Look up in our cache.
  if highlight_name then
    return highlight_name
  end

  -- Create the highlight
  highlight_name = table.concat({ "sfg", rgb_hex }, "_")
  vim.api.nvim_set_hl(ns, highlight_name, { fg = "#" .. rgb_hex })
  M._HIGHLIGHT_CACHE[cache_key] = highlight_name
  return highlight_name
end

local function recursive_child_iter(node, table_to_insert, desired_types)
  if node:iter_children() then
    for child in node:iter_children() do
      if desired_types then
        if vim.tbl_contains(desired_types, child:type()) then
          table.insert(table_to_insert, child)
        end
      else
        table.insert(table_to_insert, child)
      end

      recursive_child_iter(child, table_to_insert, desired_types)
    end
  end
end

local function get_nodes_in_array(buffer) --{{{
  local ts = vim.treesitter

  -- Yanked from https://github.com/nvim-treesitter/nvim-treesitter/blob/32e364ea3c99aafcce2ce735fe091618f623d889/lua/nvim-treesitter/parsers.lua#L4-L21
  local filetype_to_parsername = {
    arduino = "cpp",
    javascriptreact = "javascript",
    ecma = "javascript",
    jsx = "javascript",
    PKGBUILD = "bash",
    html_tags = "html",
    typescriptreact = "tsx",
    ["typescript.tsx"] = "tsx",
    terraform = "hcl",
    ["html.handlebars"] = "glimmer",
    systemverilog = "verilog",
    cls = "latex",
    sty = "latex",
    OpenFOAM = "foam",
    pandoc = "markdown",
    rmd = "markdown",
    cs = "c_sharp",
  }

  local ok, parser = pcall(ts.get_parser, buffer)
  if not ok then
    local cur_buf_filetype = vim.bo[buffer].ft
    parser = ts.get_parser(0, filetype_to_parsername[cur_buf_filetype])
  end

  if not parser then
    return nil
  end

  local trees = parser:parse()
  return trees[1]:root()
end --}}}

local function _load(buffer)
  vim.api.nvim_buf_clear_namespace(buffer, M._ns, 0, -1)

  local root = get_nodes_in_array(buffer)
  if not root then
    return
  end

  local children = {}
  recursive_child_iter(root, children, { "identifier", "type_identifier", "field_identifier" })


  for _, nn in ipairs(children) do
    local node_text = vim.treesitter.get_node_text(nn, buffer)
    if node_text then
      local hlname = M._WORD_CACHE[node_text]
      if hlname == nil then
        local c = require("color_generator").color_generate()
        hlname = create_highlight(M._ns, string.sub(c, 2))
      end

      local srow, scol, erow, ecol = vim.treesitter.get_node_range(nn)

      -- Find NS for diag and make sure there isn't extmark exist for the same range already
      local diag_idx = next(vim.diagnostic.get_namespaces())
      local existing_extmark = nil
      if diag_idx then
        local diag_ns = vim.diagnostic.get_namespaces()[diag_idx].user_data.underline_ns
        if diag_ns then
          existing_extmark = vim.api.nvim_buf_get_extmarks(buffer, diag_ns, { srow, scol }, { erow, ecol }, {})
        end
      end


      if existing_extmark == nil or next(existing_extmark) == nil then
        vim.api.nvim_buf_add_highlight(buffer, M._ns, hlname, srow, scol, ecol)
      end


      M._WORD_CACHE[node_text] = hlname
    end
  end

  vim.api.nvim_set_hl_ns_fast(M._ns)
end

local function _autoload(ev)
  local autocommands = vim.api.nvim_get_autocmds({
    group = M._semhl_augup,
    buffer = ev.buf,
    event = { "BufEnter" }
  })

  if autocommands == nil or next(autocommands) == nil then
    vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "BufWritePost", "BufEnter", "VimResized", "TextChangedI", "TextChangedP", "WinScrolled" },
      { buffer = ev.buf, callback = _autoload, group = M._semhl_augup })
  end

  _load(ev.buf)
end

M.setup = function(filetypes)
  if M._init then
    return
  end

  vim.api.nvim_create_user_command("SemhlLoad", M.load, {})
  vim.api.nvim_create_user_command("SemhlUnload", M.unload, {})

  M._ns = vim.api.nvim_create_namespace("semhl")
  M._semhl_augup = vim.api.nvim_create_augroup("semhl", { clear = true })

  vim.api.nvim_create_autocmd({ "FileType" },
    { pattern = filetypes, callback = _autoload, group = M._semhl_augup })
  M._init = true
end

M.load = function()
  local buffer = vim.api.nvim_get_current_buf()
  _autoload({ buf = buffer })
end

M.unload = function()
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
