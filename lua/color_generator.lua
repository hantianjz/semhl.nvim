local M = {}

M._saturate = 0.90
M._value = 0.99

-- Limit values for saturate and value levels
-- For dark background
local _SATURATE_FLOOR = 0.80
local _VALUE_FLOOR = 0.80

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

M.color_generate = function(hue, sat, val)
  if hue >= 1 then
    hue = 0.8
  end

  if sat == nil then
    sat = M._saturate
  else
    sat = _SATURATE_FLOOR + (sat * (1 - _SATURATE_FLOOR))
  end

  if val == nil then
    val = M._value
  else
    val = _VALUE_FLOOR + (val * (1 - _VALUE_FLOOR))
  end
  return hsv_to_rgb(hue, sat, val)
end

M.is_color_collision = function(rbg_a, rbg_b)
  -- TODO: check if 2 colors are too close and should be considered collision
  return false
end


M.setup = function(saturate, value)
  M._saturate = saturate
  M._value = value
end

return M
