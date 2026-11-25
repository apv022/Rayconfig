#!/usr/bin/env python3
"""Generate a wallpaper from a Rayconfig palette.

Dev tool, not installed: run it from the repo after editing a palette, commit
the PNG. Stdlib only (zlib), no PIL, no deps.

    ./tools/make-wallpaper.py themes/sunset/palette 1920 1080 |
        ffmpeg -loglevel error -y -i - -q:v 2 themes/sunset/wallpaper.jpg

(PNG on stdout, stdlib only; ffmpeg turns it into the committed JPEG, because
a photograph of the Sun is ten times smaller as a JPEG.)

A vertical gradient from bg to bg2, the Sun itself, a soft vignette, and
ordered dithering so the gradient does not band on 8-bit panels.

The Sun is a real photograph: NASA's Solar Dynamics Observatory, AIA 171 Å
(courtesy of NASA/SDO and the AIA science team; public domain). It is kept as
a grayscale brightness map in tools/sdo-sun-171.png and recoloured from the
palette (red → orange → amber → sun), so every theme gets its own Sun and the
palette stays the only source of colour. Without that file, a plain glow.
"""

import os
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
                pal[k.strip()] = v  # variant=dark etc.
                continue
            v = v.lstrip("#")
            pal[k.strip()] = tuple(int(v[i:i + 2], 16) for i in (0, 2, 4))
    return pal


SUN_MAP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sdo-sun-171.png")


def read_gray_png(path):
    """Decode an 8-bit grayscale, non-interlaced PNG (all we need) with zlib."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, w = 8, b"", 0
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + n]
        if tag == b"IHDR":
            w, h, depth, ctype, _, _, inter = struct.unpack(">IIBBBBB", body)
            if depth != 8 or ctype != 0 or inter != 0:
                raise ValueError("need 8-bit grayscale, non-interlaced")
        elif tag == b"IDAT":
            idat += body
        pos += 12 + n
    raw = zlib.decompress(idat)
    rows, prev, i = [], bytearray(w), 0
    for _ in range(h):
        ft, line = raw[i], bytearray(raw[i + 1:i + 1 + w])
        i += 1 + w
        for x in range(w):
            a = line[x - 1] if x else 0
            b = prev[x]
            c = prev[x - 1] if x else 0
            if ft == 1:
                line[x] = (line[x] + a) & 255
            elif ft == 2:
                line[x] = (line[x] + b) & 255
            elif ft == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(bytes(line))
        prev = line
    return w, h, rows


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

    # the Sun sits right of centre, a little low, partly cut by the edge
    try:
        sw, sh, srows = read_gray_png(SUN_MAP)
    except (OSError, ValueError):
        srows = None
    size = h * 1.15                      # the disc and its corona, in pixels
    sx0, sy0 = w * 0.70 - size / 2, h * 0.52 - size / 2
    # brightness -> colour ramp, all from the palette
    # Dark parts of the photo fall back to the background so the surface keeps
    # its texture; on light themes the brightest parts are the deepest colour,
    # or the Sun would read like a photographic negative.
    if pal.get("variant") == "light":
        ramp = [(0.0, bg), (0.35, sun), (0.7, amber), (1.0, pal["orange"])]
    else:
        ramp = [(0.0, bg), (0.3, pal["red"]), (0.55, pal["orange"]), (0.8, amber), (1.0, sun)]

    def tone(v):
        for (t0, c0), (t1, c1) in zip(ramp, ramp[1:]):
            if v <= t1:
                return lerp(c0, c1, (v - t0) / (t1 - t0))
        return ramp[-1][1]

    cx, cy = w * 0.68, h * 0.24          # fallback glow position
    radius = h * 0.95
    rows = []
    for y in range(h):
        ty = y / (h - 1)
        base = lerp(bg, bg2, ty ** 1.35)
        row = bytearray()
        row.append(0)  # PNG filter: none
        sy = int((y - sy0) * sh / size) if srows else -1
        srow = srows[sy] if srows and 0 <= sy < sh else None
        for x in range(w):
            r, g, b = base

            if srows is not None:
                sxi = int((x - sx0) * sw / size)
                if srow is not None and 0 <= sxi < sw:
                    # the photo's sky is not quite black: drop that level, and
                    # fade the frame's edges out so no square shows
                    v = max(0.0, srow[sxi] / 255.0 - 0.07) / 0.93
                    ex, ey = sxi / sw * 2 - 1, sy / sh * 2 - 1
                    edge = 1.0 - min(1.0, max(0.0, ((ex * ex + ey * ey) ** 0.5 - 0.80) / 0.20))
                    v *= edge
                    if v > 0.0:
                        a = min(1.0, v * 2.0) * 0.85
                        r, g, b = lerp((r, g, b), tone(v), a)
            else:
                dx = (x - cx) / radius
                dy = (y - cy) / radius
                d = (dx * dx + dy * dy) ** 0.5
                if d < 1.0:
                    t = (1.0 - d) ** 2.6
                    core = lerp(amber, sun, min(1.0, (1.0 - d) * 1.6))
                    r, g, b = lerp((r, g, b), core, t * 0.55)

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
