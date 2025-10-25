-- Minimal init file for running semhl.nvim tests
-- This file is loaded when running tests

-- Get plugin directory (parent of test directory)
local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h:h')

-- Add plugin to runtimepath
vim.opt.runtimepath:prepend(plugin_dir)

-- Add lua directory to package path
package.path = plugin_dir .. '/lua/?.lua;' .. plugin_dir .. '/lua/?/init.lua;' .. package.path

-- Add plenary to runtimepath if available
local plenary_dir = '/tmp/semhl-test/plenary.nvim'
if vim.fn.isdirectory(plenary_dir) == 1 then
  vim.opt.runtimepath:prepend(plenary_dir)
end

-- Basic settings for tests
vim.o.swapfile = false
vim.o.hidden = true
vim.o.background = 'dark'

-- Disable some features for faster testing
vim.g.loaded_python_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0
