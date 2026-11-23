#!/usr/bin/env python3
"""Draws the Ember app icon (1024x1024 PNG) using only the Python standard library.

Usage: python3 make_icon.py <output.png>
Run automatically by the GitHub build before the app is compiled.
"""
import math
import struct
import sys
import zlib

S = 1024
BG = (14, 14, 18)
ORANGE = (255, 107, 53)
WHITE = (255, 255, 255)
CX, CY = S / 2, S / 2 + 40      # glow + ring centre
R, W = 250, 64                   # ring radius, stroke width
GAP_HALF = math.radians(30)      # opening at the top of the ring
BAR_X, BAR_TOP, BAR_BOT = S / 2, S / 2 - 260, S / 2 + 30


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def coverage(x, y):
    """Return 0..1 white coverage for the power symbol at pixel (x, y)."""
    best = 0.0
    # Ring with a gap at the top
    dx, dy = x - CX, y - CY
    d = math.hypot(dx, dy)
    ang = math.atan2(dx, -dy)    # 0 = straight up
    if abs(ang) > GAP_HALF:
        best = max(best, min(1.0, max(0.0, W / 2 - abs(d - R) + 0.5)))
    # Vertical bar with round caps
    py = min(max(y, BAR_TOP), BAR_BOT)
    dist = math.hypot(x - BAR_X, y - py)
    best = max(best, min(1.0, max(0.0, W / 2 - dist + 0.5)))
    return best


def pixel(x, y):
    r = math.hypot(x - CX, y - CY)
    glow = max(0.0, 1 - r / 560) ** 1.6
    base = mix(BG, ORANGE, glow * 0.95)
    return mix(base, WHITE, coverage(x + 0.5, y + 0.5))


def write_png(path):
    rows = bytearray()
    for y in range(S):
        rows.append(0)  # filter: none
        for x in range(S):
            rows.extend(pixel(x, y))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0))  # 8-bit RGB, no alpha
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    write_png(sys.argv[1] if len(sys.argv) > 1 else "icon.png")
