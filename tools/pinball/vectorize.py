#!/usr/bin/env python3
"""Vectorise the detected track/boundary (track_mask.png) into clean wall
polylines with smooth straightaways AND crisp turns.

Per contour: marching-squares -> Douglas-Peucker simplify (removes pixel jaggies
but keeps the turn shape) -> LOW-smoothing periodic B-spline through those points
(hugs the turns instead of cutting them) -> dense resample, in playfield
fractions. Writes walls_vector.json + a colour-coded overlay.

Usage: python3 vectorize.py [dp_tol=2.5] [spline_s=0.25] [minlen_px=60]
  dp_tol   : simplify tolerance px (bigger = fewer points, looser)
  spline_s : spline smoothing factor (× simplified-point count; smaller = tighter)
"""
import json, sys, colorsys
import numpy as np
from PIL import Image, ImageDraw
from skimage import measure
from scipy import interpolate

dp_tol   = float(sys.argv[1]) if len(sys.argv) > 1 else 2.5
spline_s = float(sys.argv[2]) if len(sys.argv) > 2 else 0.25
minlen   = float(sys.argv[3]) if len(sys.argv) > 3 else 60.0

mask = np.asarray(Image.open("track_mask.png").convert("L"))
H, W = mask.shape
field = (mask > 127).astype(float)
contours = measure.find_contours(field, 0.5)

FLIPPER_BOXES = [(0.20, 0.42, 0.88, 0.99), (0.55, 0.72, 0.88, 0.99)]


def smooth_poly(c):
    """c: Nx2 (row, col). -> ([(x,y)...] px, perim) or None."""
    perim = float(np.sqrt((np.diff(c, axis=0) ** 2).sum(axis=1)).sum())
    if perim < minlen:
        return None
    closed = abs(c[0, 0] - c[-1, 0]) < 2 and abs(c[0, 1] - c[-1, 1]) < 2
    cc = c[:-1] if closed else c
    simp = measure.approximate_polygon(cc, tolerance=dp_tol)   # crisp, jaggy-free
    if len(simp) < 5:
        return [(p[1], p[0]) for p in simp], perim
    x, y = simp[:, 1], simp[:, 0]
    try:
        tck, _ = interpolate.splprep([x, y], s=spline_s * len(simp),
                                     per=1 if closed else 0, k=3)
    except Exception:
        return [(p[1], p[0]) for p in simp], perim
    n = int(min(500, max(48, perim * 0.14)))
    u = np.linspace(0, 1, n)
    xs, ys = interpolate.splev(u, tck)
    return list(zip(xs, ys)), perim


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
print(f"{len(polys)} walls, {sum(len(p['pts']) for p in polys)} vertices "
      f"(dp_tol={dp_tol}, spline_s={spline_s})")

base = Image.blend(Image.open("map.png").convert("RGB"),
                   Image.new("RGB", (W, H), (16, 16, 24)), 0.45)
d = ImageDraw.Draw(base)
for i, p in enumerate(polys):
    pix = [(x * W, y * H) for x, y in p["pts"]]
    col = tuple(int(255 * v) for v in colorsys.hsv_to_rgb((i * 0.137) % 1.0, 0.85, 1.0))
    d.line(pix + [pix[0]], fill=col, width=2)
base.save("vector_overlay.png")
print("wrote vector_overlay.png + walls_vector.json")
