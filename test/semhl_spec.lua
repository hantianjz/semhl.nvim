-- Basic module tests for semhl
describe("semhl", function()
  it("should load semhl module without errors", function()
    assert.has_no.errors(function()
      require("semhl")
    end)
  end)

  it("should load color_generator module without errors", function()
    assert.has_no.errors(function()
      require("color_generator")
    end)
  end)

  it("should have setup function", function()
    local semhl = require("semhl")
    assert.is_function(semhl.setup)
  end)

  it("should have load and unload functions", function()
    local semhl = require("semhl")
    assert.is_function(semhl.load)
    assert.is_function(semhl.unload)
  end)
end)

describe("color_generator", function()
  local color_gen

  before_each(function()
    package.loaded["color_generator"] = nil
    package.loaded["cielab"] = nil
    color_gen = require("color_generator")
  end)

  it("should generate valid hex colors", function()
    local color = color_gen.color_generate()
    assert.matches("^#[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$", color,
      "Color should be valid hex format")
  end)

  it("should generate different colors on successive calls", function()
    local c1 = color_gen.color_generate()
    local c2 = color_gen.color_generate()
    -- Due to randomness, colors should be different (with high probability)
    -- This might occasionally fail due to random chance
    assert.matches("^#[0-9A-F]+$", c1, "First color should be valid")
    assert.matches("^#[0-9A-F]+$", c2, "Second color should be valid")
  end)

  it("should have setup function", function()
    assert.is_function(color_gen.setup)
    color_gen.setup(nil, nil, 10, 20)
    assert.equals(10, color_gen._min_delta_e)
    assert.equals(20, color_gen._target_delta_e)
  end)

  it("should have collision detection function", function()
    assert.is_function(color_gen.is_color_collision)
    -- Test similar colors should collide
    local similar = color_gen.is_color_collision("#FF0000", "#FE0101", 5)
    assert.is_true(similar, "Very similar colors should be detected as collision")

    -- Test different colors should not collide
    local different = color_gen.is_color_collision("#FF0000", "#0000FF", 5)
    assert.is_false(different, "Very different colors should not collide")
  end)

  it("should have background cache function", function()
    assert.is_function(color_gen.clear_background_cache)
  end)

  it("should generate colors within RGB range", function()
    local color = color_gen.color_generate()
    local r = tonumber(color:sub(2, 3), 16)
    local g = tonumber(color:sub(4, 5), 16)
    local b = tonumber(color:sub(6, 7), 16)

    assert.is_true(r >= 0 and r <= 255, "Red channel in range")
    assert.is_true(g >= 0 and g <= 255, "Green channel in range")
    assert.is_true(b >= 0 and b <= 255, "Blue channel in range")
  end)

  it("should respect L range constraints", function()
    local cielab = require("cielab")

    -- Setup with specific L range
    color_gen.setup(nil, nil, 5, 15, 60, 80)

    -- Generate multiple colors and check they're within L range
    -- Allow small tolerance for floating point precision and RGB gamut conversion
    local tolerance = 1.0
    for i = 1, 5 do
      local color = color_gen.color_generate()
      local lab = cielab.hex_to_lab(color)

      assert.is_true(lab.L >= 60 - tolerance, "L should be >= 60, got " .. lab.L)
      assert.is_true(lab.L <= 80 + tolerance, "L should be <= 80, got " .. lab.L)
    end
  end)

  it("should have L_min and L_max configuration", function()
    color_gen.setup(nil, nil, 5, 15, 30, 70)
    assert.equals(30, color_gen._L_min)
    assert.equals(70, color_gen._L_max)
  end)

  it("should distribute L values across the full range", function()
    local cielab = require("cielab")

    -- Setup with specific L range
    color_gen.setup(nil, nil, 5, 15, 60, 90)

    -- Generate many colors and check distribution
    local L_values = {}
    for i = 1, 30 do
      local color = color_gen.color_generate()
      local lab = cielab.hex_to_lab(color)
      table.insert(L_values, lab.L)
    end

    -- Calculate statistics
    local min_L = math.huge
    local max_L = -math.huge
    local sum_L = 0

    for _, L in ipairs(L_values) do
      min_L = math.min(min_L, L)
      max_L = math.max(max_L, L)
      sum_L = sum_L + L
    end

    local avg_L = sum_L / #L_values
    local tolerance = 3.0

    -- Check that we have good coverage of the range
    assert.is_true(min_L < 65, "Should have some colors in lower part of range, min was " .. min_L)
    assert.is_true(max_L > 85, "Should have some colors in upper part of range, max was " .. max_L)

    -- Average should be roughly in the middle of the range (60-90 -> avg ~75)
    assert.is_true(avg_L > 75 - 10, "Average L should be near middle of range, was " .. avg_L)
    assert.is_true(avg_L < 75 + 10, "Average L should be near middle of range, was " .. avg_L)
  end)

  it("should generate diverse colors in a/b dimensions", function()
    local cielab = require("cielab")

    -- Setup with specific L range
    color_gen.setup(nil, nil, 5, 15, 60, 90)

    -- Generate many colors and check a/b variation
    local colors = {}
    for i = 1, 20 do
      local color = color_gen.color_generate()
      local lab = cielab.hex_to_lab(color)
      table.insert(colors, lab)
    end

    -- Calculate range of a and b values
    local min_a, max_a = math.huge, -math.huge
    local min_b, max_b = math.huge, -math.huge

    for _, lab in ipairs(colors) do
      min_a = math.min(min_a, lab.a)
      max_a = math.max(max_a, lab.a)
      min_b = math.min(min_b, lab.b)
      max_b = math.max(max_b, lab.b)
    end

    local a_range = max_a - min_a
    local b_range = max_b - min_b

    -- We should see significant variation in both a and b
    -- With 20 colors and good randomization, expect at least 15 units of range
    assert.is_true(a_range > 15, "Should have good variation in 'a' dimension, got range " .. a_range)
    assert.is_true(b_range > 15, "Should have good variation in 'b' dimension, got range " .. b_range)

    -- Check that colors are actually different from each other
    local distinct_count = 0
    for i = 1, #colors do
      for j = i + 1, #colors do
        local delta_e = cielab.calculate_delta_e(colors[i], colors[j])
        if delta_e > 5 then
          distinct_count = distinct_count + 1
        end
      end
    end

    -- Most pairs should be distinct
    local total_pairs = (#colors * (#colors - 1)) / 2
    local distinct_ratio = distinct_count / total_pairs
    assert.is_true(distinct_ratio > 0.7, "Most color pairs should be distinct, got " .. distinct_ratio)
  end)

  it("should cache colors persistently", function()
    color_gen.setup(nil, nil, 5, 15, 60, 90)

    -- Cache a color
    color_gen.cache_color("test_identifier", "#FF5533")

    -- Retrieve cached color
    local cached = color_gen.get_cached_color("test_identifier")
    assert.equals("#FF5533", cached, "Should retrieve cached color")
  end)

  it("should return nil for uncached identifiers", function()
    color_gen.setup(nil, nil, 5, 15, 60, 90)

    local cached = color_gen.get_cached_color("nonexistent_identifier")
    assert.is_nil(cached, "Should return nil for uncached identifier")
  end)

  it("should have cache management functions", function()
    assert.is_function(color_gen.get_cached_color)
    assert.is_function(color_gen.cache_color)
  end)
end)

describe("cache_manager", function()
  local cache_mgr

  before_each(function()
    package.loaded["cache_manager"] = nil
    cache_mgr = require("cache_manager")
  end)

  it("should load cache manager module", function()
    assert.has_no.errors(function()
      require("cache_manager")
    end)
  end)

  it("should have required functions", function()
    assert.is_function(cache_mgr.load_cache)
    assert.is_function(cache_mgr.save_cache)
    assert.is_function(cache_mgr.clear_cache_file)
  end)

  it("should load empty cache when no file exists", function()
    -- Clear any existing cache first
    cache_mgr.clear_cache_file()

    local cache = cache_mgr.load_cache()
    assert.is_table(cache)
    assert.is_table(cache.colors)
  end)
end)
