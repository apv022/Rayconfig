#!/usr/bin/env python3
"""Generate a wallpaper from a Rayconfig palette.

Dev tool, not installed: run it from the repo after editing a palette, commit
the PNG. Stdlib only (zlib), no PIL, no deps.

    ./tools/make-wallpaper.py themes/sunset/palette 2560 1440 > themes/sunset/wallpaper.png

A vertical gradient from bg to bg2, a sun glow in the accent colour, a soft
vignette, and ordered dithering so the gradient does not band on 8-bit panels.
"""

import struct
import sys
import zlib

# 8x8 Bayer matrix, values 0..63.
BAYER8 = [
    0, 32, 8, 40, 2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44, 4, 36, 14, 46, 6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
    3, 35, 11, 43, 1, 33, 9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47, 7, 39, 13, 45, 5, 37,
    63, 31, 55, 23, 61, 29, 53, 21,
]


def read_palette(path):
    pal = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            k, v = line.split("=", 1)
            v = v.strip()
            if not v.startswith("#"):
                continue  # variant=dark etc.
            v = v.lstrip("#")
            pal[k.strip()] = tuple(int(v[i:i + 2], 16) for i in (0, 2, 4))
    return pal


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def clamp(x):
    return 0 if x < 0 else (255 if x > 255 else int(x))


def dither_noise(x, y, seed):
    """Ordered 8x8 Bayer dither in [-0.8, 0.8].

    Ordered rather than random on purpose: same banding fix, but the pattern
    repeats so the PNG stays a few hundred KB instead of three megabytes.
    """
    return (BAYER8[(y & 7) * 8 + (x & 7)] / 63.0 - 0.5) * 1.6


def render(pal, w, h):
    bg = pal["bg"]
    bg2 = pal["bg2"]
    sun = pal["sun"]
    amber = pal["amber"]

    # sun sits upper right, like a low sun through a window
    cx, cy = w * 0.68, h * 0.24
    radius = h * 0.95
    rows = []
    for y in range(h):
        ty = y / (h - 1)
        base = lerp(bg, bg2, ty ** 1.35)
        row = bytearray()
        row.append(0)  # PNG filter: none
        for x in range(w):
            r, g, b = base

            # radial glow, warm core fading through amber into the base
            dx = (x - cx) / radius
            dy = (y - cy) / radius
            d = (dx * dx + dy * dy) ** 0.5
            if d < 1.0:
                t = (1.0 - d) ** 2.6
                core = lerp(amber, sun, min(1.0, (1.0 - d) * 1.6))
                r2, g2, b2 = lerp((r, g, b), core, t * 0.55)
                r, g, b = r2, g2, b2

            # vignette toward the corners
            vx = (x / w - 0.5) * 2.0
            vy = (y / h - 0.5) * 2.0
            v = 1.0 - 0.22 * min(1.0, (vx * vx + vy * vy) * 0.55)
            r, g, b = r * v, g * v, b * v

            n = dither_noise(x, y, 0)
            row += bytes((clamp(r + n), clamp(g + n), clamp(b + n)))
        rows.append(bytes(row))
    return b"".join(rows)


def png(width, height, raw):
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: make-wallpaper.py <palette> [width] [height]")
    pal = read_palette(sys.argv[1])
    w = int(sys.argv[2]) if len(sys.argv) > 2 else 2560
    h = int(sys.argv[3]) if len(sys.argv) > 3 else 1440
    sys.stdout.buffer.write(png(w, h, render(pal, w, h)))


if __name__ == "__main__":
    main()
