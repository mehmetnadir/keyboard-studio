#!/usr/bin/env python3
"""Draws the app icon and builds AppIcon.icns.

Programmatic rather than painted: macOS icons have to sit inside a specific
squircle at a specific inset and stay sharp from 16 px to 1024 px, which is a
geometry problem rather than an illustration one.
"""
from PIL import Image, ImageDraw, ImageFilter
import math, os, subprocess, sys

S = 1024
ACCENT = (155, 89, 182)
ACCENT_2 = (0, 200, 210)


def squircle(size, radius_ratio=0.2237):
    """Apple's rounded-rect: a superellipse, not a plain rounded rectangle."""
    mask = Image.new("L", (size * 4, size * 4), 0)
    d = ImageDraw.Draw(mask)
    n = 5.0
    a = size * 4 / 2
    points = []
    for i in range(720):
        t = i / 720 * 2 * math.pi
        ct, st = math.cos(t), math.sin(t)
        x = a * (abs(ct) ** (2 / n)) * (1 if ct >= 0 else -1)
        y = a * (abs(st) ** (2 / n)) * (1 if st >= 0 else -1)
        points.append((a + x, a + y))
    d.polygon(points, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def vertical_gradient(size, top, bottom):
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        f = y / max(size - 1, 1)
        grad.putpixel((0, y), tuple(int(top[c] + (bottom[c] - top[c]) * f) for c in range(3)))
    return grad.resize((size, size), Image.BICUBIC)


def draw_icon():
    # Dark base, matching the app's own surfaces.
    base = vertical_gradient(S, (38, 38, 52), (13, 13, 17)).convert("RGBA")
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(base, (0, 0))
    d = ImageDraw.Draw(icon)

    # Glow around the keycap — the RGB lighting, implied rather than drawn.
    # It wraps the key rather than pooling below it, which is how backlight
    # actually looks and keeps the shape readable at small sizes.
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle([S * 0.17, S * 0.17, S * 0.83, S * 0.80],
                         radius=S * 0.13, fill=ACCENT + (210,))
    gd.rounded_rectangle([S * 0.22, S * 0.30, S * 0.78, S * 0.82],
                         radius=S * 0.12, fill=ACCENT_2 + (170,))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.055))
    icon = Image.alpha_composite(icon, glow)
    d = ImageDraw.Draw(icon)

    # Keycap: a slab with a lighter top face, read as a single key.
    left, right = S * 0.235, S * 0.765
    top, bottom = S * 0.215, S * 0.665
    depth = S * 0.075
    d.rounded_rectangle([left, top + depth, right, bottom + depth],
                        radius=S * 0.085, fill=(24, 24, 32, 255))
    d.rounded_rectangle([left, top, right, bottom], radius=S * 0.085,
                        fill=(52, 52, 68, 255))
    inset = S * 0.045
    d.rounded_rectangle([left + inset, top + inset, right - inset, bottom - inset * 0.7],
                        radius=S * 0.055, fill=(70, 70, 90, 255))

    # The screen on the keycap — what makes this keyboard worth an app.
    sl, sr = S * 0.335, S * 0.665
    st, sb = S * 0.315, S * 0.545
    d.rounded_rectangle([sl, st, sr, sb], radius=S * 0.028, fill=(8, 8, 12, 255))
    panel = vertical_gradient(int(sr - sl), ACCENT, ACCENT_2).convert("RGBA")
    panel_mask = Image.new("L", (int(sr - sl), int(sb - st)), 0)
    ImageDraw.Draw(panel_mask).rounded_rectangle(
        [0, 0, int(sr - sl) - 1, int(sb - st) - 1], radius=int(S * 0.022), fill=255)
    icon.paste(panel.resize((int(sr - sl), int(sb - st))), (int(sl), int(st)), panel_mask)
    d = ImageDraw.Draw(icon)

    # Bars on the panel: the statistics, the thing no competitor shows.
    bar_w = (sr - sl) * 0.09
    gap = (sr - sl) * 0.055
    heights = [0.30, 0.55, 0.38, 0.72, 0.48]
    x = sl + gap * 1.3
    for h in heights:
        bar_h = (sb - st) * h * 0.68
        d.rounded_rectangle([x, sb - (sb - st) * 0.16 - bar_h, x + bar_w, sb - (sb - st) * 0.16],
                            radius=bar_w * 0.35, fill=(255, 255, 255, 235))
        x += bar_w + gap

    # A whisper of light along the top edge, so the cap reads as a physical
    # object. Kept faint — at 32 px anything stronger becomes a stray bar.
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hl).rounded_rectangle(
        [left + inset * 1.4, top + inset * 0.5, right - inset * 1.4, top + inset * 0.95],
        radius=S * 0.012, fill=(255, 255, 255, 55))
    icon = Image.alpha_composite(icon, hl.filter(ImageFilter.GaussianBlur(S * 0.006)))

    return icon


def main():
    icon = draw_icon()
    icon.putalpha(squircle(S))

    out = "Resources/icon"
    os.makedirs(f"{out}/AppIcon.iconset", exist_ok=True)
    icon.save(f"{out}/icon-1024.png")

    # The sizes macOS actually asks for.
    for size in (16, 32, 64, 128, 256, 512, 1024):
        for scale, suffix in ((1, ""), (2, "@2x")):
            px = size * scale
            if px > 1024:
                continue
            name = f"icon_{size}x{size}{suffix}.png"
            icon.resize((px, px), Image.LANCZOS).save(f"{out}/AppIcon.iconset/{name}")

    subprocess.run(["iconutil", "-c", "icns", f"{out}/AppIcon.iconset",
                    "-o", f"{out}/AppIcon.icns"], check=True)
    print(f"wrote {out}/AppIcon.icns")


if __name__ == "__main__":
    main()
