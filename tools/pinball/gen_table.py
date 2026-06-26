#!/usr/bin/env python3
"""Build game_table.json: the trace data the SpriteKit game consumes.
- walls: from walls_vector.json, downsampled for physics (cap pts/wall)
- bumpers / slings / ballStart / drain / dropHole: from table.json
- flippers: detected from the two white flipper ovals (PCA -> pivot + tip)
"""
import json
import numpy as np
from PIL import Image
from skimage import measure

CAP = 56  # max points per wall

wv = json.load(open("walls_vector.json"))
tj = json.load(open("table.json"))
W = 1100  # reference px width used for detection (fractions are resolution-free)

def downsample(pts, cap=CAP):
    if len(pts) <= cap:
        return pts
    idx = np.linspace(0, len(pts) - 1, cap).round().astype(int)
    return [pts[i] for i in sorted(set(idx.tolist()))]

walls = [downsample(w) for w in wv["walls"]]

# Flipper ovals are white-on-white (no mask edge) so they can't be auto-detected;
# set from the sketch's two white ovals. Pivot = outer end, tip = inner end
# (resting droop, tips toward centre). Refinable via the overlay tool.
flippers = [
    {"pivot": [0.25, 0.920], "tip": [0.43, 0.955], "side": "L"},
    {"pivot": [0.69, 0.920], "tip": [0.51, 0.955], "side": "R"},
]

out = {
    "aspect": wv["aspect"],
    "walls": walls,
    "bumpers": tj["bumpers"],
    "slings": tj["slings"],
    "flippers": flippers,
    "ballStart": {"x": tj["ballStart"]["x"], "y": tj["ballStart"]["y"]},
    "drain": tj["drain"],
    "dropHole": {"x": tj["dropHole"]["x"], "y": tj["dropHole"]["y"]},
}
json.dump(out, open("game_table.json", "w"), separators=(",", ":"))
import os
print("flippers:", flippers)
print(f"walls={len(walls)} pts={sum(len(w) for w in walls)} "
      f"bumpers={len(out['bumpers'])} size={os.path.getsize('game_table.json')}B")
