#!/usr/bin/env python3
"""Generate the Polaris app icons (light, dark, tinted) + a marketing preview.

Design: the North Star — a concave four-point star (astroid) carrying the
app's mint→ice data gradient, floating over the dark aurora the app itself
uses, with a small companion star. The same artwork ships two ways:

  * Assets.xcassets/AppIcon.appiconset PNGs (fallback / older toolchains)
  * Polaris/AppIcon.icon (Icon Composer document — Xcode 26 renders it with
    real Liquid Glass: specular, translucency, dark/tinted variants)

Usage: python3 scripts/generate_icons.py
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # supersample factor for crisp edges
S = SIZE * SS

# App palette (Theme.accent + heroGradient endpoint + aurora inks).
MINT = (74, 230, 184)
ICE = (89, 160, 248)
INK_TOP = (9, 14, 18)
INK_BOTTOM = (20, 33, 40)
PAPER_TOP = (243, 246, 245)
PAPER_BOTTOM = (228, 236, 234)

OUT = os.path.join(
    os.path.dirname(__file__), "..",
    "Polaris", "Resources", "Assets.xcassets", "AppIcon.appiconset",
)


def astroid_points(cx, cy, r, exponent=3.4, samples=720):
    """Concave four-point star: |cos|^a, |sin|^a polar sampling (astroid-like).

    Cusps land on the axes, so the star points N/E/S/W like a compass.
    """
    pts = []
    for i in range(samples):
        theta = 2 * math.pi * i / samples
        c, s = math.cos(theta), math.sin(theta)
        x = cx + r * math.copysign(abs(c) ** exponent, c)
        y = cy + r * math.copysign(abs(s) ** exponent, s)
        pts.append((x, y))
    return pts


def vertical_gradient(size, top, bottom):
    img = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        img.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img.resize((size, size))


def diagonal_gradient(size, start, end):
    """Top-left → bottom-right, matching Theme.heroGradient."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(0, size, 4):  # coarse columns, smoothed by resize later
            t = (x + y) / (2 * (size - 1))
            color = tuple(int(a + (b - a) * t) for a, b in zip(start, end))
            for dx in range(4):
                if x + dx < size:
                    px[x + dx, y] = color
    return img


def glow_blob(canvas, center, radius, color, alpha):
    blob = Image.new("L", canvas.size, 0)
    draw = ImageDraw.Draw(blob)
    draw.ellipse(
        [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius],
        fill=alpha,
    )
    blob = blob.filter(ImageFilter.GaussianBlur(radius * 0.6))
    overlay = Image.new("RGB", canvas.size, color)
    canvas.paste(overlay, (0, 0), blob)


def star_mask(size, cx, cy, r, exponent=3.4):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon(astroid_points(cx, cy, r, exponent), fill=255)
    return mask


def compose_stars(base_rgb, for_dark_background):
    """Paint glow + gradient stars onto an RGB canvas; returns RGBA 1024."""
    canvas = base_rgb.convert("RGB")

    main = star_mask(S, S * 0.5, S * 0.52, S * 0.38)
    companion = star_mask(S, S * 0.745, S * 0.245, S * 0.072)
    stars = Image.new("L", (S, S), 0)
    stars.paste(main, (0, 0), main)
    stars.paste(companion, (0, 0), companion)

    if for_dark_background:
        halo = stars.filter(ImageFilter.GaussianBlur(S * 0.035)).point(lambda v: v * 0.55)
        canvas.paste(Image.new("RGB", (S, S), MINT), (0, 0), halo)

    gradient = diagonal_gradient(S, MINT, ICE)
    canvas.paste(gradient, (0, 0), stars)

    out = canvas.convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    return out


def make_dark(name):
    base = vertical_gradient(S, INK_TOP, INK_BOTTOM)
    glow_blob(base, (int(S * 0.18), int(S * 0.92)), int(S * 0.45), MINT, 38)
    glow_blob(base, (int(S * 0.88), int(S * 0.12)), int(S * 0.40), ICE, 30)
    compose_stars(base, for_dark_background=True).save(os.path.join(OUT, name))
    print("wrote", name)


def make_light(name):
    base = vertical_gradient(S, PAPER_TOP, PAPER_BOTTOM)
    glow_blob(base, (int(S * 0.18), int(S * 0.92)), int(S * 0.45), MINT, 22)
    glow_blob(base, (int(S * 0.88), int(S * 0.12)), int(S * 0.40), ICE, 16)
    compose_stars(base, for_dark_background=False).save(os.path.join(OUT, name))
    print("wrote", name)


def make_tinted(name):
    """Grayscale-on-transparent for the tinted appearance."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    white = Image.new("RGBA", (S, S), (235, 238, 240, 255))
    stars = Image.new("L", (S, S), 0)
    main = star_mask(S, S * 0.5, S * 0.52, S * 0.38)
    companion = star_mask(S, S * 0.745, S * 0.245, S * 0.072)
    stars.paste(main, (0, 0), main)
    stars.paste(companion, (0, 0), companion)
    img.paste(white, (0, 0), stars)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, name))
    print("wrote", name)


def make_preview(name):
    """Rounded-corner marketing preview (not shipped)."""
    icon = Image.open(os.path.join(OUT, "icon-dark.png")).convert("RGBA")
    radius = int(SIZE * 0.2237)  # iOS squircle-ish corner radius
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE, SIZE], radius=radius, fill=255)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(icon, (0, 0), mask)
    out.save(name)
    print("wrote", name)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_dark("icon-dark.png")
    make_light("icon-light.png")
    make_tinted("icon-tinted.png")
    make_preview("/tmp/polaris-icon-preview.png")
