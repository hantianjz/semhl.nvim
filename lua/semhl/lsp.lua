---@diagnostic disable: undefined-field
local M = {}

local PLUGIN_NAME = "semhl"

M._BUFFER_STATE = {} -- Track LSP state per buffer { client_id, autocmd_id }

local LOGGER = require("plenary.log").new({
  plugin = PLUGIN_NAME,
  level = "warn",
})

-- Token types that represent identifiers (we want to colorize these)
local IDENTIFIER_TOKEN_TYPES = {
  "variable",
  "parameter",
  "property",
  "function",
  "method",
  "namespace",
  "type",
  "class",
  "interface",
  "struct",
  "enum",
  "enumMember",
  "typeParameter",
}

local function is_identifier_token(token_type)
  for _, t in ipairs(IDENTIFIER_TOKEN_TYPES) do
    if token_type == t then
      return true
    end
  end
  return false
end

-- Setup module (no-op for now, but keeps consistent API with treesitter module)
M.setup = function()
  LOGGER.debug("LSP module setup")
end

-- Process semantic tokens for a buffer
local function process_tokens(buffer, ns, highlight_node_fn, del_extmarks_fn)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end

  -- Clear existing highlights
  pcall(vim.api.nvim_buf_clear_namespace, buffer, ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(buffer)

  -- Iterate through each line and column to find tokens
  for line = 0, line_count - 1 do
    local line_text = vim.api.nvim_buf_get_lines(buffer, line, line + 1, false)[1]
    if line_text then
      local col = 0
      while col < #line_text do
        local token = vim.lsp.semantic_tokens.get_at_pos(buffer, line, col)
        if token then
          local token_type = token.type
          if is_identifier_token(token_type) then
            -- Get the token text
            local start_col = token.col or col
            local end_col = token.end_col or (start_col + 1)
            local token_text = line_text:sub(start_col + 1, end_col)

            if token_text and #token_text > 0 then
              local range = { line, start_col, line, end_col }
              highlight_node_fn(buffer, token_text, range, true)
            end

            -- Skip to end of this token
            col = end_col
          else
            col = col + 1
          end
        else
          col = col + 1
        end
      end
    end
  end
end

-- Attach to a buffer
-- @param buffer number: Buffer number
-- @param ns number: Namespace for highlights
-- @param highlight_node_fn function: Function to highlight a node (buffer, text, range, create_new)
-- @param del_extmarks_fn function: Function to delete extmarks in range (buffer, range)
-- @param augroup number: Autogroup for autocmds
M.attach = function(buffer, ns, highlight_node_fn, del_extmarks_fn, augroup)
  -- Check for LSP client with semantic tokens support
  local clients = vim.lsp.get_clients({ bufnr = buffer })
  local found_client = nil

  for _, client in ipairs(clients) do
    if client.server_capabilities.semanticTokensProvider then
      found_client = client
      break
    end
  end

  if not found_client then
    LOGGER.debug("No LSP client with semantic tokens support for buffer " .. buffer)
    return false
  end

  LOGGER.debug("Found LSP client with semantic tokens: " .. found_client.name)

  -- Start semantic tokens for this buffer
  vim.lsp.semantic_tokens.start(buffer, found_client.id)

  -- Listen for token updates
  local autocmd_id = vim.api.nvim_create_autocmd("LspTokenUpdate", {
    buffer = buffer,
    callback = function(args)
      if args.buf == buffer then
        LOGGER.debug("LspTokenUpdate for buffer " .. buffer)
        vim.schedule(function()
          process_tokens(buffer, ns, highlight_node_fn, del_extmarks_fn)
        end)
      end
    end,
    group = augroup,
  })

  M._BUFFER_STATE[buffer] = {
    client_id = found_client.id,
    autocmd_id = autocmd_id,
  }

  -- Also handle LspAttach for late-attaching clients
  vim.api.nvim_create_autocmd("LspAttach", {
    buffer = buffer,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.server_capabilities.semanticTokensProvider then
        if not M._BUFFER_STATE[buffer] then
          LOGGER.debug("Late LspAttach with semantic tokens for buffer " .. buffer)
          vim.lsp.semantic_tokens.start(buffer, client.id)
          M._BUFFER_STATE[buffer] = {
            client_id = client.id,
            autocmd_id = autocmd_id,
          }
        end
      end
    end,
    group = augroup,
  })

  -- Process initial tokens after a short delay (give LSP time to respond)
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buffer) and M._BUFFER_STATE[buffer] then
      process_tokens(buffer, ns, highlight_node_fn, del_extmarks_fn)
    end
  end, 500)

  return true
end

-- Detach from a buffer
M.detach = function(buffer)
  local state = M._BUFFER_STATE[buffer]
  if state then
    -- Stop semantic tokens
    if state.client_id then
      pcall(vim.lsp.semantic_tokens.stop, buffer, state.client_id)
    end
    M._BUFFER_STATE[buffer] = nil
  end

  LOGGER.debug("Detached from buffer: " .. buffer)
end

-- Refresh highlights for a buffer
M.refresh = function(buffer, ns, highlight_node_fn, del_extmarks_fn)
  if not vim.api.nvim_buf_is_valid(buffer) or not M._BUFFER_STATE[buffer] then
    return
  end
  LOGGER.debug("Refreshing highlights for buffer: " .. buffer)
  process_tokens(buffer, ns, highlight_node_fn, del_extmarks_fn)
end

-- Check if buffer has active LSP semantic tokens
M.is_attached = function(buffer)
  return M._BUFFER_STATE[buffer] ~= nil
end

return M
