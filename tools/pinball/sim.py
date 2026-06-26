#!/usr/bin/env python3
"""Playable pinball harness in pymunk (Chipmunk 7.0.3 — same engine as iOS).
Builds the clean composed table with LIVE flippers (pivot joint + rotary limit +
motor), drops a ball, and AUTO-FLIPS when the ball reaches a flipper so the catch
+ launch can be seen. Renders the ball trajectory + flippers so flow/feel can be
tuned. Tune the constants up top, run, read the PNG, repeat.
"""
import sys, math
import pymunk
from PIL import Image, ImageDraw

W = 560
H = int(W * 1.9)

GRAV    = float(sys.argv[1]) if len(sys.argv) > 1 else 1500.0
WALL_E  = 0.32
BUMP_E  = 1.15
SLING_E = 0.85
BALL_R  = 10.0
FLIP_SWING = 0.95
FLIP_RATE  = 28.0     # motor rad/s when flipping up
HOLD_RATE  = 18.0     # motor rad/s holding at rest
FLIP_FORCE = 8_000_000

def Pp(fx, fy): return (fx * W, fy * H)
def quad(p0, p1, p2, n=40):
    o = []
    for i in range(n + 1):
        t = i / n; u = 1 - t
        o.append((u*u*p0[0]+2*u*t*p1[0]+t*t*p2[0], u*u*p0[1]+2*u*t*p1[1]+t*t*p2[1]))
    return o

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
    flippers = [(Pp(0.27,0.865),Pp(0.42,0.915),"L"), (Pp(0.61,0.865),Pp(0.45,0.915),"R")]
    bumpers = [(Pp(0.30,0.30),0.046*W),(Pp(0.57,0.30),0.046*W),(Pp(0.435,0.22),0.046*W)]
    return walls, slings, flippers, bumpers

walls, slings, flippers_geo, bumpers = table_geometry()

space = pymunk.Space()
space.gravity = (0, GRAV)
sb = space.static_body
def add_poly(pts, e, f=0.3, r=2.0):
    for a, b in zip(pts, pts[1:]):
        s = pymunk.Segment(sb, a, b, r); s.elasticity = e; s.friction = f
        space.add(s)

for w in walls:  add_poly(w, WALL_E)
for s in slings: add_poly(s, SLING_E)
for c, r in bumpers:
    bb = pymunk.Body(body_type=pymunk.Body.STATIC); bb.position = c
    cc = pymunk.Circle(bb, r); cc.elasticity = BUMP_E; cc.friction = 0.1
    space.add(bb, cc)

# ── live flippers ─────────────────────────────────────────────────────────
def make_flipper(pivot, tip, side):
    px, py = pivot; tx, ty = tip
    length = math.hypot(tx - px, ty - py)
    rest = math.atan2(ty - py, tx - px)
    mass = 0.5
    body = pymunk.Body(mass, pymunk.moment_for_segment(mass, (0,0), (length,0), 6))
    body.position = pivot; body.angle = rest
    seg = pymunk.Segment(body, (0,0), (length,0), 6); seg.elasticity = 0.0; seg.friction = 0.6
    space.add(body, seg)
    if side == "L":
        flipped = rest - FLIP_SWING; lo, hi = flipped, rest
        frate, hrate = -FLIP_RATE, HOLD_RATE
    else:
        flipped = rest + FLIP_SWING; lo, hi = rest, flipped
        frate, hrate = FLIP_RATE, -HOLD_RATE
    space.add(pymunk.PivotJoint(sb, body, pivot))
    space.add(pymunk.RotaryLimitJoint(sb, body, lo, hi))
    motor = pymunk.SimpleMotor(sb, body, hrate); motor.max_force = FLIP_FORCE
    space.add(motor)
    return {"body": body, "pivot": pivot, "length": length, "side": side,
            "motor": motor, "frate": frate, "hrate": hrate}

flips = [make_flipper(p, t, s) for (p, t, s) in flippers_geo]
def set_flip(fl, up): fl["motor"].rate = fl["frate"] if up else fl["hrate"]

# ── ball ──────────────────────────────────────────────────────────────────
ball = pymunk.Body(1.0, pymunk.moment_for_circle(1.0, 0, BALL_R))
ball.position = Pp(0.46, 0.11)
bs = pymunk.Circle(ball, BALL_R); bs.elasticity = 0.35; bs.friction = 0.2
space.add(ball, bs)
ball.velocity = (150, 240)

def near(fl):
    px, py = fl["pivot"]; bx, by = ball.position
    side_ok = (bx < 0.47*W) if fl["side"] == "L" else (bx > 0.44*W)
    return side_ok and (py - 45) < by < (py + 70)

traj = []
drained = False
for i in range(3000):
    for fl in flips:
        set_flip(fl, near(fl) and ball.velocity.y > -20)   # flip as ball arrives
    for _ in range(3): space.step(1/240.0)
    p = ball.position; traj.append((p.x, p.y))
    if p.y > H + 30: drained = True; break

# ── render ────────────────────────────────────────────────────────────────
img = Image.new("RGB", (W, H), (14, 16, 22)); d = ImageDraw.Draw(img)
for w in walls:  d.line(w, fill=(150,158,172), width=2, joint="curve")
for s in slings: d.polygon(s, fill=(226,72,86))
for c, r in bumpers: d.ellipse([c[0]-r,c[1]-r,c[0]+r,c[1]+r], fill=(242,140,38), outline=(255,255,255), width=2)
for fl in flips:
    px, py = fl["pivot"]; a = fl["body"].angle; L = fl["length"]
    d.line([(px,py),(px+L*math.cos(a), py+L*math.sin(a))], fill=(64,140,255), width=11)
if len(traj) > 1: d.line(traj, fill=(90,220,255), width=2)
img.save("sim_traj.png")

alive = len(traj) * 3 / 240.0
ys = [p[1] for p in traj]
bounced_back = any(ys[k] < ys[k-1] - 80 for k in range(1, len(ys)))   # any strong rise
print(f"grav={GRAV} alive={alive:.1f}s {'DRAINED' if drained else 'ALIVE'} "
      f"maxY={max(ys):.0f} flipper-launch={'seen' if (max(ys)>0.85*H and bounced_back) else '?'}")
