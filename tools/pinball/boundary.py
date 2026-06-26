#!/usr/bin/env python3
"""Trace the boundary in the map sketch: BLACK = wall, WHITE/coloured = track
(the ball flows on the track). Detects the track region and overlays the exact
white/black edge so it can be verified pixel-perfect before becoming the game's
walls. Internal black shapes (ramps/posts) are kept as interior boundaries.

Usage: python3 boundary.py [map.png] [threshold=70]
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

src = sys.argv[1] if len(sys.argv) > 1 else "map.png"
thr = int(sys.argv[2]) if len(sys.argv) > 2 else 70

im = Image.open(src).convert("RGB")
a = np.asarray(im).astype(int)
H, W, _ = a.shape
bright = a.max(axis=2)
track = bright > thr                      # not-black = track

track = ndimage.binary_opening(track, iterations=2)
track = ndimage.binary_closing(track, iterations=2)

# keep the largest track region (drops stray coloured dots sitting in the black)
lab, n = ndimage.label(track)
if n:
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    track = lab == (int(np.argmax(sizes)) + 1)

# fill only TINY holes (noise / coloured dots); keep large interior black shapes
filled = ndimage.binary_fill_holes(track)
holes = filled & ~track
hl, hn = ndimage.label(holes)
fillmask = np.zeros_like(track)
for i in range(1, hn + 1):
    if (hl == i).sum() < 0.0006 * H * W:
        fillmask |= hl == i
track = track | fillmask

# boundary band (a few px) = the white/black edge, outer + interior
band = ndimage.binary_dilation(track, iterations=2) & ~ndimage.binary_erosion(track, iterations=2)

base = Image.blend(im, Image.new("RGB", (W, H), (16, 16, 24)), 0.45)
out = np.asarray(base).copy()
out[band] = (0, 255, 200)
Image.fromarray(out).save("boundary_overlay.png")

# also save a clean black/white track mask for reference
Image.fromarray((track * 255).astype(np.uint8)).save("track_mask.png")
print(f"wrote boundary_overlay.png + track_mask.png  ({W}x{H})  track={100*track.mean():.1f}%")
