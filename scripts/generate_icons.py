#!/usr/bin/env python3
"""Generate the minimal Spendrift app icons (light, dark, tinted).

Design: a thin upward trend line ending in a four-point sparkle — the AI
copilot reading your money's trajectory. One accent color, no gradients.

Usage: python3 scripts/generate_icons.py
Outputs 1024x1024 PNGs into Spendrift/Resources/Assets.xcassets/AppIcon.appiconset/
"""

from PIL import Image, ImageDraw
import math
import os

SIZE = 1024
SS = 4  # supersample factor for crisp edges
S = SIZE * SS

MINT = (52, 199, 167, 255)
INK = (14, 21, 20, 255)          # deep charcoal-teal
PAPER = (246, 248, 247, 255)     # near-white
INK_LINE = (24, 33, 32, 255)

OUT = os.path.join(
    os.path.dirname(__file__), "..",
    "Spendrift", "Resources", "Assets.xcassets", "AppIcon.appiconset",
)


def sparkle(draw, cx, cy, r, color):
    """Four-point star: two quadratic-ish concave diamonds."""
    pts = []
    for i in range(8):
        angle = math.pi / 4 * i - math.pi / 2
        radius = r if i % 2 == 0 else r * 0.22
        pts.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    draw.polygon(pts, fill=color)


def trend(draw, color, width):
    """Upward polyline across the lower-left two-thirds of the canvas."""
    pts = [
        (S * 0.20, S * 0.72),
        (S * 0.38, S * 0.58),
        (S * 0.50, S * 0.64),
        (S * 0.68, S * 0.40),
    ]
    draw.line(pts, fill=color, width=width, joint="curve")
    # round caps
    r = width / 2
    for p in (pts[0], pts[-1]):
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=color)


def make(background, line_color, sparkle_color, name):
    img = Image.new("RGBA", (S, S), background)
    draw = ImageDraw.Draw(img)
    trend(draw, line_color, int(S * 0.045))
    sparkle(draw, S * 0.72, S * 0.30, S * 0.13, sparkle_color)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(os.path.join(OUT, name))
    print("wrote", name)


def make_tinted(name):
    """Grayscale-on-transparent for iOS 18 tinted appearance."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    gray = (180, 180, 180, 255)
    bright = (240, 240, 240, 255)
    trend(draw, gray, int(S * 0.045))
    sparkle(draw, S * 0.72, S * 0.30, S * 0.13, bright)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(os.path.join(OUT, name))
    print("wrote", name)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make(INK, (235, 240, 239, 255), MINT, "icon-dark.png")
    make(PAPER, INK_LINE, MINT, "icon-light.png")
    make_tinted("icon-tinted.png")
