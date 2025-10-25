local M = {}
local cielab = require("cielab")
local cache_manager = require("cache_manager")

-- Configuration
M._min_delta_e = 5     -- Minimum acceptable Delta-E from background
M._target_delta_e = 15 -- Target Delta-E distance for generation
M._L_min = nil         -- Minimum lightness (0-100), nil for auto
M._L_max = nil         -- Maximum lightness (0-100), nil for auto

-- Cache
M._background_lab = nil  -- Cached background color in LAB space
M._safe_color_index = 1  -- Index for fallback safe colors
M._color_cache = {}      -- Persistent cache: identifier → RGB hex
M._settings_hash = nil   -- Hash of current color settings
M._save_timer = nil      -- Debounced save timer

-- Maximum attempts to generate a valid color before falling back
local MAX_GENERATION_ATTEMPTS = 10

-- Default L ranges based on background
local DEFAULT_DARK_L_MIN = 50 -- For dark backgrounds, prefer lighter colors
local DEFAULT_DARK_L_MAX = 100
local DEFAULT_LIGHT_L_MIN = 0 -- For light backgrounds, prefer darker colors
local DEFAULT_LIGHT_L_MAX = 50

-- Get the background color from Neovim and convert to LAB
local function get_background_lab()
  if M._background_lab then
    return M._background_lab
  end

  -- Get Normal highlight background color
  local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal" })
  local bg_color = normal_hl.bg

  if not bg_color or bg_color == 0 then
    -- No background color set, use default based on background setting
    local bg_setting = vim.o.background
    if bg_setting == "light" then
      -- Default light background (white)
      M._background_lab = cielab.rgb_to_lab(255, 255, 255)
    else
      -- Default dark background (black)
      M._background_lab = cielab.rgb_to_lab(0, 0, 0)
    end
  else
    -- Convert numeric color to hex
    local hex = string.format("#%06x", bg_color)
    M._background_lab = cielab.hex_to_lab(hex)
  end

  return M._background_lab
end

-- Compute hash of current settings for cache invalidation
local function compute_settings_hash()
  local bg = vim.o.background or "dark"
  local L_min = M._L_min or (bg == "light" and DEFAULT_LIGHT_L_MIN or DEFAULT_DARK_L_MIN)
  local L_max = M._L_max or (bg == "light" and DEFAULT_LIGHT_L_MAX or DEFAULT_DARK_L_MAX)

  return string.format("bg=%s,de=%d/%d,L=%d/%d",
    bg, M._min_delta_e, M._target_delta_e, L_min, L_max)
end

-- Clear background cache when it might have changed
M.clear_background_cache = function()
  M._background_lab = nil
  M._color_cache = {}
  cache_manager.clear_cache_file()
  M._settings_hash = compute_settings_hash()
end

-- Schedule a debounced save of the cache
local function schedule_cache_save()
  if M._save_timer then
    vim.loop.timer_stop(M._save_timer)
    M._save_timer = nil
  end

  M._save_timer = vim.defer_fn(function()
    cache_manager.save_cache({
      settings_hash = M._settings_hash,
      colors = M._color_cache
    })
    M._save_timer = nil
  end, 5000) -- 5 second debounce
end

-- Load persistent cache from disk
local function load_persistent_cache()
  local cache_data = cache_manager.load_cache()
  local current_hash = compute_settings_hash()

  -- Check if cached settings match current settings
  if cache_data.settings_hash == current_hash then
    M._color_cache = cache_data.colors or {}
    M._settings_hash = current_hash
  else
    -- Settings changed, start fresh
    M._color_cache = {}
    M._settings_hash = current_hash
  end
end

-- Get cached color for identifier
M.get_cached_color = function(identifier)
  return M._color_cache[identifier]
end

-- Cache a color for identifier
M.cache_color = function(identifier, rgb_hex)
  M._color_cache[identifier] = rgb_hex
  schedule_cache_save()
end

-- Get the effective L range based on configuration or background
local function get_L_range()
  -- If user specified explicit range, use that
  if M._L_min and M._L_max then
    return M._L_min, M._L_max
  end

  -- Otherwise, use smart defaults based on background
  local bg_setting = vim.o.background
  if bg_setting == "light" then
    return M._L_min or DEFAULT_LIGHT_L_MIN, M._L_max or DEFAULT_LIGHT_L_MAX
  else
    return M._L_min or DEFAULT_DARK_L_MIN, M._L_max or DEFAULT_DARK_L_MAX
  end
end

-- Generate a new color that is perceptually distinct from the background
-- Returns RGB hex string like "#RRGGBB"
M.color_generate = function()
  local bg_lab = get_background_lab()
  local L_min, L_max = get_L_range()
  local attempts = 0

  -- Try to generate a valid color
  while attempts < MAX_GENERATION_ATTEMPTS do
    attempts = attempts + 1

    -- Generate a color at target Delta-E distance from background with L constraints
    local new_lab = cielab.generate_lab_at_distance(bg_lab, M._target_delta_e, L_min, L_max)

    -- Verify the actual Delta-E
    local delta_e = cielab.calculate_delta_e(new_lab, bg_lab)

    -- If it meets our minimum threshold, use it
    if delta_e >= M._min_delta_e then
      return cielab.lab_to_rgb(new_lab.L, new_lab.a, new_lab.b)
    end
  end

  -- Failed to generate valid color, fall back to safe color palette
  local safe_lab = cielab.get_safe_color(M._safe_color_index)
  M._safe_color_index = M._safe_color_index + 1

  -- Clamp safe color to L range
  safe_lab = cielab.clamp_lab(safe_lab, L_min, L_max)

  -- Verify safe color is valid, otherwise adjust it
  local safe_delta_e = cielab.calculate_delta_e(safe_lab, bg_lab)
  if safe_delta_e < M._min_delta_e then
    -- Safe color is too close, try to adjust it away from background
    local adjustment = M._min_delta_e - safe_delta_e + 5
    safe_lab = cielab.generate_lab_at_distance(safe_lab, adjustment, L_min, L_max)
  end

  return cielab.lab_to_rgb(safe_lab.L, safe_lab.a, safe_lab.b)
end

-- Check if two colors are too similar (collision detection)
-- Expects RGB hex strings like "#RRGGBB"
M.is_color_collision = function(rgb_a, rgb_b, threshold)
  threshold = threshold or M._min_delta_e

  local lab_a = cielab.hex_to_lab(rgb_a)
  local lab_b = cielab.hex_to_lab(rgb_b)

  local delta_e = cielab.calculate_delta_e(lab_a, lab_b)
  return delta_e < threshold
end

-- Setup color generator with optional parameters
M.setup = function(saturate, value, min_delta_e, target_delta_e, L_min, L_max)
  -- Legacy parameters (saturate, value) are ignored for backwards compatibility
  -- They were used for HSV generation

  if min_delta_e ~= nil then
    M._min_delta_e = min_delta_e
  end

  if target_delta_e ~= nil then
    M._target_delta_e = target_delta_e
  end

  if L_min ~= nil then
    M._L_min = L_min
  end

  if L_max ~= nil then
    M._L_max = L_max
  end

  -- Initialize background LAB cache
  get_background_lab()

  -- Load persistent color cache
  load_persistent_cache()
end

return M
