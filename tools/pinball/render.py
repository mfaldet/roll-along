#!/usr/bin/env python3
"""Render the Roll Along pinball table layout (table.json) to a PNG so it can be
visually inspected and traced against a reference playfield image.

Usage:
    python3 render.py                      # standalone render -> out.png
    python3 render.py REF.png              # overlay trace on REF.png -> out.png
    python3 render.py REF.png OUT.png      # custom output path

Coordinates in table.json are normalised to the playfield rect:
    fx: 0..1 left->right,  fy: 0..1 TOP->bottom.
When a reference image is given, the canvas is the reference's pixel size so the
overlay lands 1:1 — tune the JSON, re-render, look, repeat.
"""
import json, sys, os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))


def load_table():
    with open(os.path.join(HERE, "table.json")) as f:
        return json.load(f)


def quad(p0, p1, p2, n=24):
    """Sample a quadratic bezier from p0 (control p1) to p2."""
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0]
        y = u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]
        pts.append((x, y))
    return pts


def render(ref_path=None, out_path=None):
    t = load_table()
    if ref_path and os.path.exists(ref_path):
        base = Image.open(ref_path).convert("RGBA")
        W, H = base.size
        # dim the reference so the overlay reads clearly
        base = Image.blend(base, Image.new("RGBA", (W, H), (20, 20, 28, 255)), 0.45)
    else:
        W = 640
        H = int(W * t.get("aspect", 1.95))
        base = Image.new("RGBA", (W, H), (16, 18, 26, 255))

    img = base.copy()
    d = ImageDraw.Draw(img)

    def P(fx, fy):
        return (fx * W, fy * H)

    WALL   = (220, 220, 230, 255)
    BUMPER = (242, 140, 38, 255)
    SLING  = (230, 72, 86, 255)
    TARGET = (76, 178, 255, 255)
    ROLL   = (210, 210, 210, 255)
    FLIP   = (64, 140, 255, 255)
    DRAIN  = (255, 80, 80, 255)
    BALL   = (255, 255, 255, 255)

    # walls (with curves)
    for wall in t["walls"]:
        cur = None
        for op in wall["ops"]:
            k = op[0]
            if k == "M":
                cur = P(op[1], op[2])
            elif k == "L":
                nxt = P(op[1], op[2])
                d.line([cur, nxt], fill=WALL, width=3)
                cur = nxt
            elif k == "Q":
                c = P(op[1], op[2]); e = P(op[3], op[4])
                d.line(quad(cur, c, e), fill=WALL, width=3, joint="curve")
                cur = e

    def circle(cx, cy, r, **kw):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], **kw)

    for b in t["bumpers"]:
        cx, cy = P(b["x"], b["y"]); r = b["r"] * W
        circle(cx, cy, r, fill=BUMPER, outline=(255, 255, 255, 255), width=2)
        circle(cx, cy, r * 0.42, fill=(20, 22, 30, 255))

    for s in t["slings"]:
        d.polygon([P(p[0], p[1]) for p in s], fill=SLING, outline=(255, 255, 255, 255))

    for tg in t["targets"]:
        cx, cy = P(tg["x"], tg["y"]); w = tg["w"] * W; h = tg["h"] * H
        d.rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2],
                    fill=TARGET, outline=(255, 255, 255, 255))

    for ro in t["rollovers"]:
        cx, cy = P(ro["x"], ro["y"]); r = ro["r"] * W
        circle(cx, cy, r, outline=ROLL, width=2)

    import math
    for f in t["flippers"]:
        px, py = P(f["px"], f["py"]); ln = f["len"] * W; dr = f["dir"]
        ang = 0.5  # resting droop (screen y-down)
        ex = px + dr * ln * math.cos(ang)
        ey = py + ln * math.sin(ang)
        d.line([(px, py), (ex, ey)], fill=FLIP, width=int(max(4, 0.024 * W)))
        circle(px, py, 3, fill=(255, 255, 255, 255))

    dr_ = t["drain"]
    cx, cy = P(dr_["x"], dr_["y"]); w = dr_["w"] * W; h = dr_["h"] * H
    d.rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], outline=DRAIN, width=3)

    bs = t["ballStart"]
    cx, cy = P(bs["x"], bs["y"]); r = bs["r"] * W
    circle(cx, cy, r, fill=BALL)

    out = out_path or os.path.join(HERE, "out.png")
    img.convert("RGB").save(out)
    print(f"wrote {out}  ({W}x{H})")


if __name__ == "__main__":
    ref = sys.argv[1] if len(sys.argv) > 1 else None
    out = sys.argv[2] if len(sys.argv) > 2 else None
    render(ref, out)
