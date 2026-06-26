#!/usr/bin/env python3
"""Vectorise the detected track/boundary (track_mask.png) into clean wall
polylines: marching-squares contours -> Douglas-Peucker simplification ->
fraction coords. Writes walls_vector.json and an overlay so the VECTOR walls can
be checked against the sketch.

Usage: python3 vectorize.py [tolerance_px=2.5] [minlen_px=60]
"""
import json, sys, colorsys
import numpy as np
from PIL import Image, ImageDraw
from skimage import measure

tol = float(sys.argv[1]) if len(sys.argv) > 1 else 2.5
minlen = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0

mask = np.asarray(Image.open("track_mask.png").convert("L"))
H, W = mask.shape
field = (mask > 127).astype(float)
contours = measure.find_contours(field, 0.5)

polys = []
for c in contours:                                  # c is (row, col) = (y, x)
    perim = np.sqrt((np.diff(c, axis=0) ** 2).sum(axis=1)).sum()
    if perim < minlen:
        continue
    simp = measure.approximate_polygon(c, tolerance=tol)
    pts = [[round(float(x) / W, 4), round(float(y) / H, 4)] for (y, x) in simp]
    polys.append(pts)

polys.sort(key=len, reverse=True)
json.dump({"aspect": round(H / W, 3), "walls": polys}, open("walls_vector.json", "w"))
print(f"{len(polys)} wall polylines, {sum(len(p) for p in polys)} vertices (tol={tol}px, minlen={minlen}px)")

base = Image.blend(Image.open("map.png").convert("RGB"),
                   Image.new("RGB", (W, H), (16, 16, 24)), 0.45)
d = ImageDraw.Draw(base)
for i, p in enumerate(polys):
    pix = [(x * W, y * H) for x, y in p]
    col = tuple(int(255 * v) for v in colorsys.hsv_to_rgb((i * 0.137) % 1.0, 0.85, 1.0))
    d.line(pix, fill=col, width=2)
    for (x, y) in pix:                              # mark vertices
        d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=col)
base.save("vector_overlay.png")
print("wrote vector_overlay.png + walls_vector.json")
