#!/usr/bin/env python3
"""
Analyze RGB colors by converting them to LAB and reporting ΔE to a background.

Usage examples:
    python analyze_colors.py "255,0,0"
    python analyze_colors.py ff0000 aabbcc --bg "30,30,30"
"""

import argparse
import re
import sys
from pathlib import Path

# Compatibility fix for numpy.asscalar removal in NumPy 1.23+
import numpy as np

if not hasattr(np, "asscalar"):
    np.asscalar = lambda a: a.item()

try:
    from colormath.color_conversions import convert_color
    from colormath.color_diff import delta_e_cie2000
    from colormath.color_objects import LabColor, sRGBColor
except ImportError:
    print("Error: colormath library is required for this script.")
    print("Install with: pip install colormath")
    sys.exit(1)

try:
    from scipy import stats
except ImportError:
    print("Warning: scipy library is recommended for statistical analysis.")
    print("Install with: pip install scipy")
    stats = None


def parse_rgb(value):
    """Parse RGB from '255,0,0', '255 0 0', or hex 'ff0000'/'#ff0000' into a tuple."""
    stripped = value.strip().lower()
    if stripped.startswith("#"):
        stripped = stripped[1:]

    if len(stripped) == 6 and all(ch in "0123456789abcdef" for ch in stripped):
        r = int(stripped[0:2], 16)
        g = int(stripped[2:4], 16)
        b = int(stripped[4:6], 16)
        return r, g, b

    parts = stripped.replace(",", " ").split()
    if len(parts) != 3:
        raise ValueError(f"Expected three components for RGB value, got: {value!r}")

    try:
        r, g, b = (int(component) for component in parts)
    except ValueError as exc:
        raise ValueError(f"RGB components must be integers: {value!r}") from exc

    for component in (r, g, b):
        if not 0 <= component <= 255:
            raise ValueError(f"RGB components must be in range 0-255: {value!r}")

    return r, g, b


def rgb_to_lab(r, g, b):
    """Convert RGB (0-255) to LAB color space."""
    rgb_color = sRGBColor(r / 255.0, g / 255.0, b / 255.0)
    return convert_color(rgb_color, LabColor)


def delta_e(rgb, bg_rgb):
    """Calculate ΔE (CIE2000) between two RGB tuples."""
    lab1 = rgb_to_lab(*rgb)
    lab2 = rgb_to_lab(*bg_rgb)
    result = delta_e_cie2000(lab1, lab2)
    if hasattr(result, "item"):
        return result.item()
    return float(result)


def rgb_to_hex(rgb):
    """Return hex string in #RRGGBB format."""
    r, g, b = rgb
    return f"#{r:02x}{g:02x}{b:02x}"


def format_lab(lab_color):
    """Return a formatted string for LAB components."""
    return f"L={lab_color.lab_l:6.2f}, a={lab_color.lab_a:7.2f}, b={lab_color.lab_b:7.2f}"


def colorize_text(text, rgb):
    """Return text wrapped in an ANSI 24-bit color escape sequence."""
    text = str(text)
    r, g, b = rgb
    return f"\033[38;2;{r};{g};{b}m{text}\033[0m"


def calculate_statistics(values):
    """Calculate descriptive statistics for a list of values."""
    if not values:
        return None

    values_array = np.array(values)
    return {
        "min": np.min(values_array),
        "max": np.max(values_array),
        "mean": np.mean(values_array),
        "median": np.median(values_array),
        "std": np.std(values_array),
        "q1": np.percentile(values_array, 25),
        "q3": np.percentile(values_array, 75),
    }


def analyze_distribution(values):
    """Analyze the distribution characteristics of values."""
    if not values or len(values) < 3:
        return {"type": "insufficient data"}

    values_array = np.array(values)

    # Normalize values to 0-1 range for uniformity test
    val_min, val_max = values_array.min(), values_array.max()
    if val_max - val_min == 0:
        return {"type": "constant", "uniformity_score": 0.0}

    normalized = (values_array - val_min) / (val_max - val_min)

    analysis = {}

    # Test for uniformity using Kolmogorov-Smirnov test
    if stats is not None and len(values) >= 8:
        # Test against uniform distribution
        ks_stat, ks_pvalue = stats.kstest(normalized, 'uniform')
        analysis["ks_statistic"] = ks_stat
        analysis["ks_pvalue"] = ks_pvalue

        # Lower KS statistic means closer to uniform
        # p-value > 0.05 suggests we can't reject uniform distribution
        if ks_pvalue > 0.05:
            analysis["type"] = "uniform-like"
        elif ks_stat < 0.2:
            analysis["type"] = "fairly uniform"
        else:
            analysis["type"] = "non-uniform"
    else:
        analysis["type"] = "unknown"

    # Calculate coefficient of variation (normalized std dev)
    mean_val = values_array.mean()
    if mean_val != 0:
        cv = values_array.std() / abs(mean_val)
        analysis["cv"] = cv

    return analysis


def calculate_randomness_score(l_values, a_values, b_values, delta_e_values):
    """
    Calculate a composite randomness score (0-100) based on multiple factors.

    Higher score = more random/uniform distribution
    Lower score = more clustered/patterned
    """
    if not l_values or len(l_values) < 3:
        return 0.0

    scores = []

    # 1. Uniformity score from distribution tests (25 points max)
    uniformity_score = 0
    for values in [l_values, a_values, b_values, delta_e_values]:
        dist_analysis = analyze_distribution(values)
        if "ks_statistic" in dist_analysis:
            # Lower KS stat is better (max 1.0, typically < 0.5 for reasonable data)
            # Convert to 0-100 scale where lower KS = higher score
            ks_score = max(0, 100 * (1 - dist_analysis["ks_statistic"]))
            uniformity_score += ks_score / 4

    scores.append(min(25, uniformity_score))

    # 2. Coverage score - how well colors span the space (25 points max)
    l_array = np.array(l_values)
    a_array = np.array(a_values)
    b_array = np.array(b_values)

    # LAB typical ranges: L:[0,100], a:[-128,127], b:[-128,127]
    l_coverage = (l_array.max() - l_array.min()) / 100.0
    a_coverage = (a_array.max() - a_array.min()) / 255.0
    b_coverage = (b_array.max() - b_array.min()) / 255.0

    coverage_score = 25 * (l_coverage + a_coverage + b_coverage) / 3
    scores.append(coverage_score)

    # 3. Spacing consistency score (25 points max)
    # Good random distribution has consistent spacing (moderate CV)
    delta_e_array = np.array(delta_e_values)
    if len(delta_e_array) > 1:
        # Sort to analyze spacing
        sorted_values = np.sort(delta_e_array)
        spacing = np.diff(sorted_values)
        if len(spacing) > 0:
            spacing_cv = spacing.std() / spacing.mean() if spacing.mean() > 0 else 0
            # CV around 0.5-1.0 is ideal for randomness
            # Too low = too uniform (artificial), too high = clustered
            spacing_score = 25 * np.exp(-abs(spacing_cv - 0.75))
            scores.append(spacing_score)

    # 4. Entropy/disorder score (25 points max)
    # Measure how unpredictable the color sequence is
    if len(l_values) >= 5:
        # Calculate entropy of binned values
        def calculate_entropy(values, bins=10):
            hist, _ = np.histogram(values, bins=bins)
            hist = hist[hist > 0]  # Remove empty bins
            probs = hist / hist.sum()
            return -np.sum(probs * np.log2(probs))

        # Normalize entropy to 0-1 scale (max entropy = log2(bins))
        max_entropy = np.log2(10)
        l_entropy = calculate_entropy(l_values) / max_entropy
        a_entropy = calculate_entropy(a_values) / max_entropy
        b_entropy = calculate_entropy(b_values) / max_entropy

        entropy_score = 25 * (l_entropy + a_entropy + b_entropy) / 3
        scores.append(entropy_score)

    return sum(scores)


def display_statistics(l_values, a_values, b_values, delta_e_values):
    """Display statistical summary and randomness analysis."""
    print("\n" + "="*80)
    print("STATISTICAL SUMMARY")
    print("="*80)

    # Calculate statistics for each column
    l_stats = calculate_statistics(l_values)
    a_stats = calculate_statistics(a_values)
    b_stats = calculate_statistics(b_values)
    delta_stats = calculate_statistics(delta_e_values)

    # Display table header
    print(f"\n{'Statistic':<12} {'L':>10} {'A':>10} {'B':>10} {'ΔE':>10}")
    print("-" * 54)

    # Display each statistic
    stat_names = [
        ("Min", "min"),
        ("Q1", "q1"),
        ("Median", "median"),
        ("Mean", "mean"),
        ("Q3", "q3"),
        ("Max", "max"),
        ("Std Dev", "std"),
    ]

    for label, key in stat_names:
        print(f"{label:<12} {l_stats[key]:>10.2f} {a_stats[key]:>10.2f} {b_stats[key]:>10.2f} {delta_stats[key]:>10.2f}")

    # Distribution analysis
    print(f"\n{'Distribution Analysis':<12}")
    print("-" * 54)

    l_dist = analyze_distribution(l_values)
    a_dist = analyze_distribution(a_values)
    b_dist = analyze_distribution(b_values)
    delta_dist = analyze_distribution(delta_e_values)

    if "ks_statistic" in l_dist:
        print(f"{'KS Statistic':<12} {l_dist['ks_statistic']:>10.4f} {a_dist['ks_statistic']:>10.4f} {b_dist['ks_statistic']:>10.4f} {delta_dist['ks_statistic']:>10.4f}")
        print(f"{'KS p-value':<12} {l_dist['ks_pvalue']:>10.4f} {a_dist['ks_pvalue']:>10.4f} {b_dist['ks_pvalue']:>10.4f} {delta_dist['ks_pvalue']:>10.4f}")
        print(f"\n  Note: KS statistic near 0 = uniform distribution; p-value > 0.05 = likely uniform")

    # Randomness score
    randomness = calculate_randomness_score(l_values, a_values, b_values, delta_e_values)
    print(f"\n{'RANDOMNESS SCORE':<12} {randomness:>10.1f} / 100.0")

    # Interpretation
    if randomness >= 75:
        interpretation = "Highly random - excellent color space coverage and uniformity"
    elif randomness >= 60:
        interpretation = "Moderately random - good distribution with minor clustering"
    elif randomness >= 40:
        interpretation = "Somewhat random - noticeable patterns or clustering present"
    else:
        interpretation = "Low randomness - significant clustering or limited coverage"

    print(f"  Interpretation: {interpretation}")
    print("="*80 + "\n")


def load_cache_colors(cache_path):
    """Load identifier → RGB hex mapping from a semhl cache file."""
    path = Path(cache_path).expanduser()
    if not path.is_file():
        raise FileNotFoundError(f"Cache file not found: {path}")

    pattern = re.compile(r'\["(?P<key>[^"]+)"\]\s*=\s*"(?P<value>#[0-9a-fA-F]{6})"')
    colors = {}
    found_block = False
    in_block = False
    brace_depth = 0

    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not in_block:
                if '["colors"]' in line and "=" in line and "{" in line:
                    in_block = True
                    found_block = True
                    brace_depth = line.count("{") - line.count("}")
                continue

            brace_depth += line.count("{")
            brace_depth -= line.count("}")
            if brace_depth <= 0:
                break

            match = pattern.search(line)
            if match:
                colors[match.group("key")] = match.group("value")

    if not found_block:
        raise ValueError(f"Could not locate a colors table in cache file: {path}")
    if not colors:
        raise ValueError(f"No colors found in cache file: {path}")

    return colors


def main():
    parser = argparse.ArgumentParser(
        description="Convert RGB colors to LAB and compute ΔE to a background color.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python analyze_colors.py "255,0,0"
  python analyze_colors.py "12 34 56" "200,200,200" --bg "30,30,30"
  python analyze_colors.py ff0000 --bg 2a2a2a
        """,
    )

    parser.add_argument(
        "colors",
        nargs="*",
        help="Foreground RGB colors as 'R,G,B', 'R G B', or hex RRGGBB (with/without '#').",
    )

    parser.add_argument(
        "--cache",
        help="Path to semhl.nvim cache file mapping identifiers to RGB hex colors (Lua table).",
    )

    parser.add_argument(
        "--bg",
        default="0,0,0",
        help="Background RGB color as 'R,G,B', 'R G B', or hex RRGGBB (default: black).",
    )

    args = parser.parse_args()

    if not args.colors and not args.cache:
        parser.error("Provide one or more colors or a --cache file to analyze.")

    try:
        bg_rgb = parse_rgb(args.bg)
    except ValueError as err:
        print(f"Error parsing --bg: {err}")
        sys.exit(1)

    entries = []
    for color_str in args.colors:
        try:
            rgb = parse_rgb(color_str)
        except ValueError as err:
            print(f"Skipping invalid color {color_str!r}: {err}")
            continue
        entries.append((color_str, rgb))

    has_cache_data = False
    cache_start_index = len(entries)

    if args.cache:
        try:
            cache_colors = load_cache_colors(args.cache)
        except (OSError, ValueError) as err:
            print(f"Failed to load cache: {err}")
        else:
            cache_entries = []
            for name, hex_value in cache_colors.items():
                try:
                    rgb = parse_rgb(hex_value)
                except ValueError as err:
                    print(f"Skipping invalid cache color {name!r}: {err}")
                    continue
                cache_entries.append((name, rgb))
            cache_entries.sort(key=lambda item: item[1])
            entries.extend(cache_entries)
            has_cache_data = len(cache_entries) > 0

    if not entries:
        print("No valid colors to analyze.")
        sys.exit(1)

    label_width = max(len(str(label)) for label, _ in entries)

    bg_lab = rgb_to_lab(*bg_rgb)
    print(f"Background: {rgb_to_hex(bg_rgb)}  LAB: {format_lab(bg_lab)}")
    print()

    # Collect statistics for cache entries
    l_values = []
    a_values = []
    b_values = []
    delta_e_values = []

    for idx, (label, rgb) in enumerate(entries):
        lab_color = rgb_to_lab(*rgb)
        delta = delta_e(rgb, bg_rgb)
        padded_label = str(label).ljust(label_width)
        colored_label = colorize_text(padded_label, rgb)
        print(
            f"{colored_label}  Color: {rgb_to_hex(rgb):>8}  LAB: {format_lab(lab_color)}  ΔE (vs bg): {delta:6.2f}"
        )

        # Collect statistics only for cache entries
        if has_cache_data and idx >= cache_start_index:
            l_values.append(lab_color.lab_l)
            a_values.append(lab_color.lab_a)
            b_values.append(lab_color.lab_b)
            delta_e_values.append(delta)

    # Display statistical summary for cache data
    if has_cache_data and l_values:
        display_statistics(l_values, a_values, b_values, delta_e_values)


if __name__ == "__main__":
    main()
