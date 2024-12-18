local ts = vim.treesitter

local ts = vim.

local bufn = 0

local query = ts.query.parse("lua", "(type_identifier) @name")
local parser = ts.get_parser(bufn)
local trees = parser:parse()
local r = trees[1]:root()

for pattern, match, metadata in query:iter_matches(r, bufn, 0, -1) do
  P(match)
  for id, node in pairs(match) do
    local name = query.captures[id]
    local node_text = vim.treesitter.get_node_text(node, bufn)
    P(node_text)
    local srow, scol, erow, ecol = vim.treesitter.get_node_range(node)
    print(srow, scol, erow, ecol)
  end
end
