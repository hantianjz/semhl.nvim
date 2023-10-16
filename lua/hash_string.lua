local M = {}

local md5 = require("md5")

M.hash = function(in_str)
  return md5.sum(in_str)
end

M.normalized_hash = function(in_str)
  local val = 0
  local h = M.hash(in_str)
  for i=1, #h do
    val = (val + string.byte(h:sub(i,i))) % 256
  end
  return val / 256
end

M.hash_hsv = function(in_str)
  local hash_val = M.hash(in_str)
  local h = string.byte(hash_val:sub(1,1)) / 256
  local s = string.byte(hash_val:sub(2,2)) / 256
  local v = string.byte(hash_val:sub(3,3)) / 256
  return {h, s, v}
end


return M
