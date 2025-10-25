#!/usr/bin/env python3
"""
Generate random RGB colors and compare them to a background using LAB color space.

Usage:
    python generate_colors.py --count 10
    python generate_colors.py --count 20 --bg "#1e1e1e"
    python generate_colors.py --count 24 --bg "#282828" --grid --cols 8
"""

import sys
import argparse
import random
import string

# Compatibility fix for numpy.asscalar removal in NumPy 1.23+
import numpy as np
if not hasattr(np, 'asscalar'):
    np.asscalar = lambda a: a.item()

try:
    from colormath.color_objects import sRGBColor, LabColor
    from colormath.color_conversions import convert_color
    from colormath.color_diff import delta_e_cie2000
    COLORMATH_AVAILABLE = True
except ImportError:
    COLORMATH_AVAILABLE = False
    print("Error: colormath library is required for this script.")
    print("Install with: pip install colormath")
    sys.exit(1)


def parse_hex_color(hex_str):
    """Parse hex color string to RGB tuple."""
    hex_str = hex_str.lstrip('#')
    if len(hex_str) == 6:
        r = int(hex_str[0:2], 16)
        g = int(hex_str[2:4], 16)
        b = int(hex_str[4:6], 16)
        return (r, g, b)
    else:
        raise ValueError(f"Invalid hex color: {hex_str}")


def generate_random_color():
    """Generate a random RGB color."""
    r = random.randint(0, 255)
    g = random.randint(0, 255)
    b = random.randint(0, 255)
    return (r, g, b)


def rgb_to_lab(r, g, b):
    """Convert RGB (0-255) to LAB color space."""
    # Normalize RGB to 0-1 range for sRGBColor
    rgb_color = sRGBColor(r / 255.0, g / 255.0, b / 255.0)
    lab_color = convert_color(rgb_color, LabColor)
    return lab_color


def calculate_delta_e(r1, g1, b1, r2, g2, b2):
    """Calculate ΔE (CIE2000) between two RGB colors."""
    lab1 = rgb_to_lab(r1, g1, b1)
    lab2 = rgb_to_lab(r2, g2, b2)
    result = delta_e_cie2000(lab1, lab2)
    # Handle both numpy arrays and scalars
    if hasattr(result, 'item'):
        return result.item()
    return float(result)


def get_luminance(r, g, b):
    """Calculate relative luminance of a color."""
    # Normalize to 0-1
    r_norm = r / 255.0
    g_norm = g / 255.0
    b_norm = b / 255.0

    # Apply gamma correction
    def adjust(c):
        if c <= 0.03928:
            return c / 12.92
        else:
            return ((c + 0.055) / 1.055) ** 2.4

    r_adj = adjust(r_norm)
    g_adj = adjust(g_norm)
    b_adj = adjust(b_norm)

    # Calculate luminance
    return 0.2126 * r_adj + 0.7152 * g_adj + 0.0722 * b_adj


def generate_random_text(length=8):
    """Generate random text that looks like code identifiers."""
    # Mix of identifier-like patterns
    patterns = [
        lambda: ''.join(random.choices(string.ascii_lowercase, k=length)),
        lambda: ''.join(random.choices(string.ascii_lowercase + string.digits, k=length)),
        lambda: ''.join(random.choices(string.ascii_letters, k=length)),
        lambda: '_'.join([''.join(random.choices(string.ascii_lowercase, k=random.randint(3, 5)))
                         for _ in range(2)])[:length],
    ]
    return random.choice(patterns)()


def display_color_on_background(fg_r, fg_g, fg_b, bg_r, bg_g, bg_b, show_grid=False):
    """Display a foreground color on a background color with ANSI codes."""
    # Generate random text instead of color blocks
    text = generate_random_text(8)
    color_text = f"\033[48;2;{bg_r};{bg_g};{bg_b}m\033[38;2;{fg_r};{fg_g};{fg_b}m{text}\033[0m"

    if show_grid:
        return color_text
    else:
        # Format the color info
        fg_hex = f"#{fg_r:02x}{fg_g:02x}{fg_b:02x}"
        fg_rgb = f"RGB({fg_r:3d}, {fg_g:3d}, {fg_b:3d})"

        # Get LAB values
        lab = rgb_to_lab(fg_r, fg_g, fg_b)
        lab_str = f"LAB(L={lab.lab_l:6.2f}, a={lab.lab_a:7.2f}, b={lab.lab_b:7.2f})"

        # Calculate delta_e
        delta_e = calculate_delta_e(fg_r, fg_g, fg_b, bg_r, bg_g, bg_b)
        delta_e_str = f"ΔE={delta_e:6.2f}"

        return f"{color_text}  {fg_hex:9s} {fg_rgb:19s} {lab_str}  {delta_e_str}"


def display_color_grid(colors, bg_r, bg_g, bg_b, cols=8):
    """Display colors in a grid format."""
    print(f"\nColor Grid ({len(colors)} colors):\n")

    for i in range(0, len(colors), cols):
        row_colors = colors[i:i+cols]
        # Display color blocks
        row = ""
        for r, g, b in row_colors:
            row += display_color_on_background(r, g, b, bg_r, bg_g, bg_b, show_grid=True) + " "
        print(row)
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Generate random RGB colors and compare to background using LAB color space",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate 10 random colors on black background (default)
  python generate_colors.py --count 10

  # Generate 20 colors on dark background
  python generate_colors.py --count 20 --bg "#1e1e1e"

  # Generate colors in grid view
  python generate_colors.py --count 24 --bg "#282828" --grid --cols 8
        """
    )

    parser.add_argument('--count', '-n', type=int, default=10,
                        help='Number of colors to generate (default: 10)')
    parser.add_argument('--bg', '--background', type=str, default='#000000',
                        help='Background color in hex format (default: #000000 - black)')

    parser.add_argument('--grid', action='store_true',
                        help='Display colors in a grid layout')
    parser.add_argument('--cols', type=int, default=8,
                        help='Number of columns in grid view (default: 8)')

    parser.add_argument('--seed', type=int, default=None,
                        help='Random seed for reproducible results')

    parser.add_argument('--min-delta-e', type=float, default=None,
                        help='Minimum ΔE value to filter colors (optional)')

    args = parser.parse_args()

    # Set random seed if provided
    if args.seed is not None:
        random.seed(args.seed)

    # Parse background color
    try:
        bg_r, bg_g, bg_b = parse_hex_color(args.bg)
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)

    bg_hex = f"#{bg_r:02x}{bg_g:02x}{bg_b:02x}"
    bg_lab = rgb_to_lab(bg_r, bg_g, bg_b)

    # Display configuration
    print(f"\nGenerating {args.count} random RGB colors")
    print(f"Background: {bg_hex} (LAB: L={bg_lab.lab_l:.2f}, a={bg_lab.lab_a:.2f}, b={bg_lab.lab_b:.2f})")

    if args.seed is not None:
        print(f"Random seed: {args.seed}")

    if args.min_delta_e is not None:
        print(f"Filtering colors with ΔE >= {args.min_delta_e:.2f}")

    # Generate colors
    colors = []
    attempts = 0
    max_attempts = args.count * 100 if args.min_delta_e else args.count

    while len(colors) < args.count and attempts < max_attempts:
        attempts += 1
        r, g, b = generate_random_color()

        # If min_delta_e is specified, filter colors
        if args.min_delta_e is not None:
            delta_e = calculate_delta_e(r, g, b, bg_r, bg_g, bg_b)
            if delta_e < args.min_delta_e:
                continue

        colors.append((r, g, b))

    if len(colors) < args.count:
        print(f"\nWarning: Only generated {len(colors)} colors after {attempts} attempts")

    # Display colors
    if args.grid:
        display_color_grid(colors, bg_r, bg_g, bg_b, args.cols)
    else:
        print(f"\nGenerated Colors:\n")
        for r, g, b in colors:
            print(display_color_on_background(r, g, b, bg_r, bg_g, bg_b))

    print()


if __name__ == "__main__":
    main()
