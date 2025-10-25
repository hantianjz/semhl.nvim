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

    if not entries:
        print("No valid colors to analyze.")
        sys.exit(1)

    label_width = max(len(str(label)) for label, _ in entries)

    bg_lab = rgb_to_lab(*bg_rgb)
    print(f"Background: {rgb_to_hex(bg_rgb)}  LAB: {format_lab(bg_lab)}")
    print()

    for label, rgb in entries:
        lab_color = rgb_to_lab(*rgb)
        delta = delta_e(rgb, bg_rgb)
        padded_label = str(label).ljust(label_width)
        colored_label = colorize_text(padded_label, rgb)
        print(
            f"{colored_label}  Color: {rgb_to_hex(rgb):>8}  LAB: {format_lab(lab_color)}  ΔE (vs bg): {delta:6.2f}"
        )


if __name__ == "__main__":
    main()
