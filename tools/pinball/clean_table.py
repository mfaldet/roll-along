#!/usr/bin/env python3
"""A pinball table COMPOSED from clean primitives (not traced) — proof that the
right approach yields a clean, functional table instead of a scribble. Renders a
top-down preview PNG.
"""
import math
from PIL import Image, ImageDraw

W = 560
ASPECT = 1.9
H = int(W * ASPECT)
img = Image.new("RGB", (W, H), (14, 16, 22))
d = ImageDraw.Draw(img)

def P(fx, fy): return (fx * W, fy * H)
def quad(p0, p1, p2, n=40):
    out = []
    for i in range(n + 1):
        t = i / n; u = 1 - t
        out.append((u*u*p0[0] + 2*u*t*p1[0] + t*t*p2[0],
                    u*u*p0[1] + 2*u*t*p1[1] + t*t*p2[1]))
    return out

WALL = (150, 158, 172)
def stroke(pts, w=3, col=WALL):
    d.line(pts, fill=col, width=w, joint="curve")

# ---- outer shell: smooth arch + walls + bottom funnel (drain gap at centre) ----
shell = []
shell += [P(0.40, 0.95)]
shell += quad(P(0.40, 0.95), P(0.10, 0.93), P(0.05, 0.74))
shell += [P(0.05, 0.16)]
shell += quad(P(0.05, 0.16), P(0.05, 0.035), P(0.26, 0.028))
shell += quad(P(0.26, 0.028), P(0.45, 0.005), P(0.64, 0.030))
shell += quad(P(0.64, 0.030), P(0.82, 0.06), P(0.82, 0.18))
shell += [P(0.82, 0.74)]
shell += quad(P(0.82, 0.74), P(0.78, 0.93), P(0.52, 0.95))
stroke(shell, 3)

# ---- shooter lane on the right ----
lane = [P(0.93, 0.95)] + [P(0.93, 0.13)] + quad(P(0.93, 0.13), P(0.93, 0.045), P(0.84, 0.045))
stroke(lane, 3)
stroke([P(0.84, 0.95), P(0.84, 0.20)], 3)   # inner lane wall

# ---- top rollover lanes ----
for lx in (0.30, 0.40, 0.50):
    stroke([P(lx, 0.10), P(lx, 0.17)], 2, (110, 118, 132))

# ---- 3 pop bumpers (triangle) ----
def disc(c, r, fill, ring=(255,255,255)):
    d.ellipse([c[0]-r, c[1]-r, c[0]+r, c[1]+r], fill=fill, outline=ring, width=3)
for (bx, by) in [(0.30, 0.30), (0.57, 0.30), (0.435, 0.22)]:
    c = P(bx, by); r = 0.046 * W
    disc(c, r, (242, 140, 38)); disc(c, r*0.4, (16,18,26), None)

# ---- standup targets on the sides ----
for (tx, ty) in [(0.085, 0.40), (0.085, 0.48), (0.80, 0.40), (0.80, 0.48)]:
    c = P(tx, ty); w = 0.012*W; h = 0.03*H
    d.rectangle([c[0]-w/2, c[1]-h/2, c[0]+w/2, c[1]+h/2], fill=(76,178,255), outline=(255,255,255))

# ---- lane-guide islands (inlane / outlane split) ----
for ix in (0.155, 0.685):
    c = P(ix, 0.80); w = 0.012*W; h = 0.06*H
    d.rounded_rectangle([c[0]-w/2, c[1]-h/2, c[0]+w/2, c[1]+h/2], radius=w/2,
                        outline=WALL, width=2)

# ---- slingshots (above each flipper) ----
def tri(pts, fill=(226,72,86)):
    d.polygon(pts, fill=fill, outline=(255,255,255))
tri([P(0.20,0.78), P(0.30,0.83), P(0.20,0.85)])
tri([P(0.64,0.78), P(0.54,0.83), P(0.64,0.85)])

# ---- flippers (2, angled down-inward) ----
def flipper(pivot, tip, col=(64,140,255)):
    d.line([pivot, tip], fill=col, width=int(0.022*W))
    d.ellipse([pivot[0]-4, pivot[1]-4, pivot[0]+4, pivot[1]+4], fill=(255,255,255))
flipper(P(0.27, 0.865), P(0.42, 0.915))
flipper(P(0.61, 0.865), P(0.45, 0.915))

# ---- center drain marker ----
d.rectangle([P(0.40,0.945)[0], P(0.40,0.945)[1], P(0.50,0.965)[0], P(0.50,0.965)[1]],
            outline=(255,80,80), width=2)

# ---- ball resting in the lane ----
c = P(0.885, 0.92); r = 0.018*W
d.ellipse([c[0]-r, c[1]-r, c[0]+r, c[1]+r], fill=(255,255,255))

img.save("clean_table.png")
print("wrote clean_table.png", (W, H))
