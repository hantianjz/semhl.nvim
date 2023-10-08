local M = {}

local GOLDEN_RATIO_CONJUGATE = 0.618033988749895

local function hsv_to_rgb(h, s, v)
  local h_i = math.floor(h * 6)
  local f = h * 6 - h_i
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local t = v * (1 - (1 - f) * s)
  local r = 0
  local g = 0
  local b = 0
  if h_i == 0 then
    r, g, b = v, t, p
  end
  if h_i == 1 then
    r, g, b = q, v, p
  end
  if h_i == 2 then
    r, g, b = p, v, t
  end
  if h_i == 3 then
    r, g, b = p, q, v
  end
  if h_i == 4 then
    r, g, b = t, p, v
  end
  if h_i == 5 then
    r, g, b = v, p, q
  end
  local r_hex = string.format("%02X", math.floor(r * 256))
  local g_hex = string.format("%02X", math.floor(g * 256))
  local b_hex = string.format("%02X", math.floor(b * 256))
  return "#" .. r_hex .. g_hex .. b_hex
end

M.current_h = 0

M.color_generate = function()
  M.current_h = (M.current_h + GOLDEN_RATIO_CONJUGATE) % 1
  return hsv_to_rgb(M.current_h, 0.9, 0.97)
end

return M
