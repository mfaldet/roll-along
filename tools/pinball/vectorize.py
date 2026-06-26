#!/usr/bin/env python3
"""Vectorise the detected track/boundary (track_mask.png) into SMOOTH wall
polylines. Marching-squares contours -> periodic smoothing B-spline (so long
outer walls become clean barrel arcs the ball won't rattle on) -> dense resample
in playfield fractions. Writes walls_vector.json + a colour-coded overlay.

Usage: python3 vectorize.py [smooth=2.0] [minlen_px=60]
  smooth : spline smoothing strength (× point count). Higher = smoother arcs.
"""
import json, sys, colorsys
import numpy as np
from PIL import Image, ImageDraw
from skimage import measure
from scipy import interpolate

smooth = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0
minlen = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0

mask = np.asarray(Image.open("track_mask.png").convert("L"))
H, W = mask.shape
field = (mask > 127).astype(float)
contours = measure.find_contours(field, 0.5)


def smooth_poly(c):
    """c: Nx2 (row, col). Returns smoothed [(x,y)...] in pixels or None."""
    y, x = c[:, 0], c[:, 1]
    perim = float(np.sqrt((np.diff(c, axis=0) ** 2).sum(axis=1)).sum())
    if perim < minlen:
        return None
    closed = abs(x[0] - x[-1]) < 2 and abs(y[0] - y[-1]) < 2
    if closed:
        x, y = x[:-1], y[:-1]
    if len(x) < 6:
        return None
    try:
        tck, _ = interpolate.splprep([x, y], s=smooth * len(x),
                                     per=1 if closed else 0, k=3)
    except Exception:
        return None
    n = int(min(420, max(48, perim * 0.12)))
    u = np.linspace(0, 1, n)
    xs, ys = interpolate.splev(u, tck)
    return list(zip(xs, ys)), perim


# the two white ovals near the bottom are flippers (dynamic) — not walls
FLIPPER_BOXES = [(0.20, 0.42, 0.88, 0.99), (0.55, 0.72, 0.88, 0.99)]

polys = []
for c in contours:
    cx, cy = float(c[:, 1].mean()) / W, float(c[:, 0].mean()) / H
    if any(bx0 <= cx <= bx1 and by0 <= cy <= by1 for bx0, bx1, by0, by1 in FLIPPER_BOXES):
        continue
    res = smooth_poly(c)
    if res is None:
        continue
    pix, perim = res
    pts = [[round(float(px) / W, 4), round(float(py) / H, 4)] for px, py in pix]
    polys.append({"pts": pts, "perim": round(perim, 1)})

polys.sort(key=lambda p: p["perim"], reverse=True)
json.dump({"aspect": round(H / W, 3), "walls": [p["pts"] for p in polys]},
          open("walls_vector.json", "w"))
print(f"{len(polys)} smooth wall polylines, "
      f"{sum(len(p['pts']) for p in polys)} vertices (smooth={smooth})")

base = Image.blend(Image.open("map.png").convert("RGB"),
                   Image.new("RGB", (W, H), (16, 16, 24)), 0.45)
d = ImageDraw.Draw(base)
for i, p in enumerate(polys):
    pix = [(x * W, y * H) for x, y in p["pts"]]
    col = tuple(int(255 * v) for v in colorsys.hsv_to_rgb((i * 0.137) % 1.0, 0.85, 1.0))
    d.line(pix + [pix[0]], fill=col, width=2)
base.save("vector_overlay.png")
print("wrote vector_overlay.png + walls_vector.json")
