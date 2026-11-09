#!/usr/bin/env python3
"""Locate pink progress bar rows + dark control bands in a screenshot.
usage: analyze_screenshot.py <png> [scale]  (scale = original/this, default 2672/height)
Prints candidate rows (y, x-range, count) for pink pixels, and runs tesseract OCR crop info hints."""
import sys
from PIL import Image

path = sys.argv[1]
im = Image.open(path).convert('RGB')
W, H = im.size
scale = float(sys.argv[2]) if len(sys.argv) > 2 else 2672.0 / H
px = im.load()

def is_pink(r, g, b):
    # bilibili pink ~ #FB7299 (251,114,153); tolerant range
    return r > 200 and 60 < g < 170 and 100 < b < 200 and (r - g) > 60

rows = []
for y in range(H):
    xs = [x for x in range(0, W, 4) if is_pink(*px[x, y])]
    if len(xs) >= 5:
        rows.append((y, min(xs) * 1, max(xs) * 1, len(xs)))

# merge adjacent rows into bands
bands = []
for y, x0, x1, n in rows:
    if bands and y - bands[-1][1] <= 3:
        b = bands[-1]
        bands[-1] = (b[0], y, min(b[2], x0), max(b[3], x1), max(b[4], n))
    else:
        bands.append((y, y, x0, x1, n))
print(f"image {W}x{H} scale_to_original={scale:.3f}")
for y0, y1, x0, x1, n in bands:
    print(f"pink band y={y0}-{y1} x={x0}-{x1} samples={n} -> original y~{int(y0*scale)}-{int(y1*scale)} x~{int(x0*scale)}-{int(x1*scale)}")
