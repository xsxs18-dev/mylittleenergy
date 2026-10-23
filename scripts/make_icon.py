#!/usr/bin/env python3
"""Draws the MyLittleEnergy app icon (ring + lightning bolt) and writes every size the app needs.

Usage: python3 scripts/make_icon.py App/Resources
"""
import math, sys, os
from PIL import Image, ImageDraw, ImageFilter

S = 1024

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def background():
    image = Image.new("RGB", (S, S))
    pixels = image.load()
    top, bottom = (14, 22, 30), (6, 40, 34)
    for y in range(S):
        for x in range(S):
            t = (x * 0.35 + y * 0.65) / S
            pixels[x, y] = lerp(top, bottom, t)
    return image

def ring_layer():
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    center, radius, width = S / 2, 330, 92
    box = (center - radius, center - radius, center + radius, center + radius)
    draw.arc(box, 0, 360, fill=(255, 255, 255, 28), width=width)
    start, sweep = -90, 290
    steps = 240
    colors = [(50, 215, 75), (100, 230, 200), (10, 180, 255)]
    for i in range(steps):
        t = i / (steps - 1)
        color = lerp(colors[0], colors[1], t * 2) if t < 0.5 else lerp(colors[1], colors[2], (t - 0.5) * 2)
        a0 = start + sweep * i / steps
        a1 = start + sweep * (i + 1.6) / steps
        draw.arc(box, a0, a1, fill=color + (255,), width=width)
    # round caps
    for angle, color in ((start, colors[0]), (start + sweep, colors[2])):
        r = math.radians(angle)
        cx = center + (radius - width / 2) * math.cos(r)
        cy = center + (radius - width / 2) * math.sin(r)
        draw.ellipse((cx - width / 2, cy - width / 2, cx + width / 2, cy + width / 2), fill=color + (255,))
    return layer

def bolt_points(scale=1.0):
    pts = [(0.60, 0.10), (0.30, 0.56), (0.48, 0.56), (0.40, 0.90), (0.72, 0.42), (0.53, 0.42), (0.62, 0.10)]
    size, offset = 430 * scale, (S - 430 * scale) / 2
    return [(offset + x * size, offset + y * size) for x, y in pts]

def bolt_layer():
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(bolt_points(), fill=(255, 255, 255, 255))
    return layer

def main(out):
    base = background().convert("RGBA")
    ring = ring_layer()
    glow = ring.filter(ImageFilter.GaussianBlur(38))
    base = Image.alpha_composite(base, glow)
    base = Image.alpha_composite(base, ring)
    bolt = bolt_layer()
    bolt_glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(bolt_glow).polygon(bolt_points(), fill=(120, 255, 170, 200))
    base = Image.alpha_composite(base, bolt_glow.filter(ImageFilter.GaussianBlur(30)))
    base = Image.alpha_composite(base, bolt)
    icon = base.convert("RGB")
    os.makedirs(out, exist_ok=True)
    for name, size in (("AppIcon60x60@2x.png", 120), ("AppIcon60x60@3x.png", 180),
                       ("AppIcon76x76@2x~ipad.png", 152), ("AppIcon83.5x83.5@2x~ipad.png", 167)):
        icon.resize((size, size), Image.LANCZOS).save(os.path.join(out, name))
    os.makedirs("assets", exist_ok=True)
    icon.save("assets/icon-1024.png")

if __name__ == "__main__":
    main(sys.argv[1])
