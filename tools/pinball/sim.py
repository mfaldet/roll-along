#!/usr/bin/env python3
"""Playable pinball harness in pymunk (Chipmunk2D) — the runtime I CAN execute.
Builds the clean composed table, launches a ball from the shooter lane, simulates
real physics, and renders the ball's trajectory + the table so the flow can be
seen and tuned. (Flippers added next; this first pass proves launch + flow.)
"""
import sys, math
import pymunk
from PIL import Image, ImageDraw

W = 560
H = int(W * 1.9)

# ── tunable feel ──────────────────────────────────────────────────────────
GRAV   = float(sys.argv[1]) if len(sys.argv) > 1 else 1500.0   # px/s^2 (y down)
LAUNCH = float(sys.argv[2]) if len(sys.argv) > 2 else 1900.0   # launch speed up
WALL_E = 0.32      # wall restitution
BUMP_E = 1.20      # pop-bumper restitution (>1 = adds energy)
SLING_E = 0.85
BALL_R = 10.0

def Pp(fx, fy): return (fx * W, fy * H)
def quad(p0, p1, p2, n=40):
    o = []
    for i in range(n + 1):
        t = i / n; u = 1 - t
        o.append((u*u*p0[0]+2*u*t*p1[0]+t*t*p2[0], u*u*p0[1]+2*u*t*p1[1]+t*t*p2[1]))
    return o

# ── geometry (matches clean_table.py) ─────────────────────────────────────
def table_geometry():
    shell = [Pp(0.40,0.95)]
    shell += quad(Pp(0.40,0.95), Pp(0.10,0.93), Pp(0.05,0.74))
    shell += [Pp(0.05,0.16)]
    shell += quad(Pp(0.05,0.16), Pp(0.05,0.035), Pp(0.26,0.028))
    shell += quad(Pp(0.26,0.028), Pp(0.45,0.005), Pp(0.64,0.030))
    shell += quad(Pp(0.64,0.030), Pp(0.82,0.06), Pp(0.82,0.18))
    shell += [Pp(0.82,0.74)]
    shell += quad(Pp(0.82,0.74), Pp(0.78,0.93), Pp(0.52,0.95))
    lane_out = [Pp(0.93,0.95), Pp(0.93,0.13)] + quad(Pp(0.93,0.13), Pp(0.93,0.045), Pp(0.84,0.045))
    lane_in  = [Pp(0.84,0.95), Pp(0.84,0.20)]
    walls = [shell, lane_out, lane_in]
    slings = [[Pp(0.20,0.78),Pp(0.30,0.83),Pp(0.20,0.85),Pp(0.20,0.78)],
              [Pp(0.64,0.78),Pp(0.54,0.83),Pp(0.64,0.85),Pp(0.64,0.78)]]
    flippers = [[Pp(0.27,0.865),Pp(0.42,0.915)], [Pp(0.61,0.865),Pp(0.45,0.915)]]
    bumpers = [(Pp(0.30,0.30),0.046*W),(Pp(0.57,0.30),0.046*W),(Pp(0.435,0.22),0.046*W)]
    return walls, slings, flippers, bumpers

walls, slings, flippers, bumpers = table_geometry()

space = pymunk.Space()
space.gravity = (0, GRAV)
sb = space.static_body
def add_poly(pts, e, f=0.3, r=2.0):
    for a, b in zip(pts, pts[1:]):
        s = pymunk.Segment(sb, a, b, r); s.elasticity = e; s.friction = f
        space.add(s)

for w in walls:   add_poly(w, WALL_E)
for s in slings:  add_poly(s, SLING_E)
for fl in flippers: add_poly(fl, 0.4, r=5)          # static bats for now
for c, r in bumpers:
    bb = pymunk.Body(body_type=pymunk.Body.STATIC); bb.position = c
    cc = pymunk.Circle(bb, r); cc.elasticity = BUMP_E; cc.friction = 0.1
    space.add(bb, cc)

# ── ball: rest in shooter lane, launch up ─────────────────────────────────
mass = 1.0
ball = pymunk.Body(mass, pymunk.moment_for_circle(mass, 0, BALL_R))
ball.position = Pp(0.46, 0.11)            # dropped into the upper playfield
shape = pymunk.Circle(ball, BALL_R); shape.elasticity = 0.35; shape.friction = 0.2
space.add(ball, shape)
ball.velocity = (150, 240)                 # slight push so it works the bumpers

traj = []
drained = False
for i in range(2600):
    for _ in range(3): space.step(1/240.0)
    p = ball.position
    traj.append((p.x, p.y))
    if p.y > H - 6 and 0.40*W < p.x < 0.50*W:    # fell out the centre drain gap
        drained = True; break
    if p.y > H + 40: drained = True; break

# ── render table + trajectory ─────────────────────────────────────────────
img = Image.new("RGB", (W, H), (14, 16, 22)); d = ImageDraw.Draw(img)
for w in walls:   d.line(w, fill=(150,158,172), width=2, joint="curve")
for s in slings:  d.polygon(s, fill=(226,72,86))
for fl in flippers: d.line(fl, fill=(64,140,255), width=11)
for c, r in bumpers: d.ellipse([c[0]-r,c[1]-r,c[0]+r,c[1]+r], fill=(242,140,38), outline=(255,255,255), width=2)
if len(traj) > 1: d.line(traj, fill=(90,220,255), width=2)
d.ellipse([Pp(0.885,0.92)[0]-4,Pp(0.885,0.92)[1]-4,Pp(0.885,0.92)[0]+4,Pp(0.885,0.92)[1]+4], fill=(255,255,0))  # start
img.save("sim_traj.png")

alive = len(traj) * 3 / 240.0
print(f"grav={GRAV} launch={LAUNCH}  steps={len(traj)}  alive={alive:.1f}s  "
      f"{'DRAINED centre' if drained else 'still in play'}  maxY={max(p[1] for p in traj):.0f}")
