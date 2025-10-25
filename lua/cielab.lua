-- CIELAB Color Space Module
-- Provides conversions between RGB and CIELAB color spaces,
-- Delta-E calculation, and perceptually uniform color generation.

local M = {}

-- D65 illuminant reference white
local XN = 0.95047
local YN = 1.0
local ZN = 1.08883

-- CIE LAB constants
local LAB_EPSILON = 216 / 24389 -- 0.008856
local LAB_KAPPA = 24389 / 27    -- 903.3

-- sRGB to linear RGB gamma correction
local function srgb_to_linear(c)
  if c <= 0.04045 then
    return c / 12.92
  else
    return math.pow((c + 0.055) / 1.055, 2.4)
  end
end

-- Linear RGB to sRGB gamma correction
local function linear_to_srgb(c)
  if c <= 0.0031308 then
    return 12.92 * c
  else
    return 1.055 * math.pow(c, 1 / 2.4) - 0.055
  end
end

-- RGB [0-255] to XYZ conversion
local function rgb_to_xyz(r, g, b)
  -- Normalize to [0, 1]
  r = r / 255.0
  g = g / 255.0
  b = b / 255.0

  -- Convert to linear RGB
  r = srgb_to_linear(r)
  g = srgb_to_linear(g)
  b = srgb_to_linear(b)

  -- Convert to XYZ using sRGB matrix
  local x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
  local y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750
  local z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041

  return x, y, z
end

-- XYZ to CIELAB conversion
local function xyz_to_lab(x, y, z)
  -- Normalize by reference white
  x = x / XN
  y = y / YN
  z = z / ZN

  -- Apply f(t) function
  local function f(t)
    if t > LAB_EPSILON then
      return math.pow(t, 1 / 3)
    else
      return (LAB_KAPPA * t + 16) / 116
    end
  end

  local fx = f(x)
  local fy = f(y)
  local fz = f(z)

  -- Calculate LAB values
  local L = 116 * fy - 16
  local a = 500 * (fx - fy)
  local b = 200 * (fy - fz)

  return L, a, b
end

-- RGB [0-255] to CIELAB conversion
function M.rgb_to_lab(r, g, b)
  local x, y, z = rgb_to_xyz(r, g, b)
  local L, a, b_val = xyz_to_lab(x, y, z)
  return { L = L, a = a, b = b_val }
end

-- Hex string "#RRGGBB" to CIELAB conversion
function M.hex_to_lab(hex)
  -- Remove # if present
  hex = hex:gsub("#", "")

  -- Parse hex values
  local r = tonumber(hex:sub(1, 2), 16)
  local g = tonumber(hex:sub(3, 4), 16)
  local b = tonumber(hex:sub(5, 6), 16)

  return M.rgb_to_lab(r, g, b)
end

-- CIELAB to XYZ conversion
local function lab_to_xyz(L, a, b)
  local fy = (L + 16) / 116
  local fx = a / 500 + fy
  local fz = fy - b / 200

  -- Apply inverse f(t) function
  local function f_inv(t)
    local t3 = t * t * t
    if t3 > LAB_EPSILON then
      return t3
    else
      return (116 * t - 16) / LAB_KAPPA
    end
  end

  local x = XN * f_inv(fx)
  local y = YN * f_inv(fy)
  local z = ZN * f_inv(fz)

  return x, y, z
end

-- XYZ to RGB [0-255] conversion
local function xyz_to_rgb(x, y, z)
  -- Convert XYZ to linear sRGB
  local r = x * 3.2404542 + y * -1.5371385 + z * -0.4985314
  local g = x * -0.9692660 + y * 1.8760108 + z * 0.0415560
  local b = x * 0.0556434 + y * -0.2040259 + z * 1.0572252

  -- Apply gamma correction
  r = linear_to_srgb(r)
  g = linear_to_srgb(g)
  b = linear_to_srgb(b)

  -- Clamp to [0, 1] and convert to [0, 255]
  r = math.max(0, math.min(1, r)) * 255
  g = math.max(0, math.min(1, g)) * 255
  b = math.max(0, math.min(1, b)) * 255

  return r, g, b
end

-- CIELAB to RGB hex string conversion
function M.lab_to_rgb(L, a, b)
  local x, y, z = lab_to_xyz(L, a, b)
  local r, g, b_val = xyz_to_rgb(x, y, z)

  -- Convert to hex
  local r_hex = string.format("%02X", math.floor(r + 0.5))
  local g_hex = string.format("%02X", math.floor(g + 0.5))
  local b_hex = string.format("%02X", math.floor(b_val + 0.5))

  return "#" .. r_hex .. g_hex .. b_hex
end

-- Calculate Delta-E (CIE76 formula) between two LAB colors
function M.calculate_delta_e(lab1, lab2)
  local dL = lab1.L - lab2.L
  local da = lab1.a - lab2.a
  local db = lab1.b - lab2.b
  return math.sqrt(dL * dL + da * da + db * db)
end

-- Clamp LAB values to valid ranges
-- Optional L_min and L_max to constrain lightness
function M.clamp_lab(lab, L_min, L_max)
  L_min = L_min or 0
  L_max = L_max or 100

  return {
    L = math.max(L_min, math.min(L_max, lab.L)),
    a = math.max(-128, math.min(127, lab.a)),
    b = math.max(-128, math.min(127, lab.b))
  }
end

-- Generate a new LAB color at a specific Delta-E distance from base color
-- Optional L_min and L_max to constrain lightness range
function M.generate_lab_at_distance(base_lab, target_distance, L_min, L_max)
  L_min = L_min or 0
  L_max = L_max or 100

  -- Strategy: Generate L uniformly, generate good a/b variation,
  -- then ensure minimum Delta-E is met

  -- Generate target L uniformly in the valid range
  local target_L = L_min + math.random() * (L_max - L_min)

  -- Generate random angle for a/b plane
  local theta = math.random() * 2 * math.pi

  -- Use a substantial portion of target_distance for a/b variation
  -- This ensures good color diversity even when L is constrained
  -- Use 70% of target_distance for a/b to guarantee color variety
  local ab_distance = target_distance * 0.7

  -- Generate variation in a/b plane
  local da = ab_distance * math.cos(theta)
  local db = ab_distance * math.sin(theta)

  local new_lab = {
    L = target_L,
    a = base_lab.a + da,
    b = base_lab.b + db
  }

  -- Clamp to valid LAB ranges
  new_lab = M.clamp_lab(new_lab, L_min, L_max)

  -- After clamping, check actual Delta-E and scale a/b if too small
  local actual_delta_e = M.calculate_delta_e(new_lab, base_lab)

  -- If Delta-E is too small (less than 50% of target), scale up a/b variation
  local min_acceptable = target_distance * 0.5
  if actual_delta_e < min_acceptable and actual_delta_e > 0 then
    local scale_factor = min_acceptable / actual_delta_e
    new_lab.a = base_lab.a + (new_lab.a - base_lab.a) * scale_factor
    new_lab.b = base_lab.b + (new_lab.b - base_lab.b) * scale_factor

    -- Clamp again after scaling
    new_lab = M.clamp_lab(new_lab, L_min, L_max)
  end

  return new_lab
end

-- Predefined safe colors in LAB space that work on any background
-- These are carefully selected to be well-distributed in LAB space
M.SAFE_COLORS_LAB = {
  { L = 70, a = 50,  b = 50 },  -- Red-orange
  { L = 60, a = -50, b = 40 },  -- Green
  { L = 65, a = 20,  b = -60 }, -- Blue
  { L = 75, a = 60,  b = -10 }, -- Magenta
  { L = 80, a = -30, b = 70 },  -- Yellow
  { L = 55, a = -20, b = -50 }, -- Cyan
  { L = 50, a = 40,  b = 20 },  -- Orange-brown
  { L = 70, a = -60, b = -10 }, -- Teal
  { L = 85, a = 30,  b = 30 },  -- Pink
  { L = 45, a = 10,  b = -40 }, -- Dark blue
}

-- Get a safe color by index (with wrapping)
function M.get_safe_color(index)
  local idx = ((index - 1) % #M.SAFE_COLORS_LAB) + 1
  return M.SAFE_COLORS_LAB[idx]
end

return M
