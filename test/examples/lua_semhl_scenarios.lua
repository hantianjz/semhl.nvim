-- semhl.nvim troubleshooting scenarios (Lua)
--
-- Use this file to reproduce semantic-highlighting behavior while editing.
-- Suggested actions:
-- 1) Move a block (`dd`, `p`) and verify identifier colors move correctly.
-- 2) Comment/uncomment lines and verify identifiers inside comments are not highlighted.
-- 3) Rename identifiers and verify old highlights are removed.

local total_count = 0
local current_item = "apple"

local function update_count(step)
  total_count = total_count + step
  return total_count
end

local function print_item(item)
  print("item:", item)
end

for i = 1, 3 do
  total_count = update_count(i)
  print_item(current_item)
end

-- Scenario A: comment/uncomment this block and inspect highlights.
-- current_item = "orange"
-- print_item(current_item)

-- Scenario B: rename `total_count` to `aggregate_total` and verify stale highlights do not remain.
-- Scenario C: move function `print_item` below the loop and verify all extmarks stay accurate.
