"""Render the coin-icon proposals side by side at in-game sizes.

Run from this folder:  python3 render_coins.py   (needs Pillow)
Writes coin-proposals.png (3x scale, like an iPhone screen) and one PNG per
design.  The drawing is flat on purpose: one fill, one outline, one bold mark.
The sizes are the CoinIcon(size:) values used in the app.
"""
import math
from PIL import Image, ImageDraw, ImageFont

SCALE = 3          # points -> pixels, like a 3x iPhone
SS = 4             # supersampling for smooth edges
SIZES = [10, 13, 16, 20, 26, 44, 56]
BG = (20, 20, 20)          # Color(white: 0.08) screen background
CARD = (36, 36, 36)        # Color(white: 0.14) cards and pills
TEXT = (210, 210, 210)
SUB = (130, 130, 130)

GOLD = (0xF5, 0xB8, 0x2E)       # face
GOLD_DARK = (0x8A, 0x5A, 0x0E)  # outline and mark
GOLD_MID = (0xC9, 0x8A, 0x1B)   # inner ring (design B)


def tri_points(cx, cy, r, rot=-math.pi / 2):
    return [(cx + math.cos(rot + i * 2 * math.pi / 3) * r,
             cy + math.sin(rot + i * 2 * math.pi / 3) * r) for i in range(3)]


def rounded_tri(d, cx, cy, r, corner, fill):
    """Equilateral triangle (circumradius r) with rounded corners."""
    pts = tri_points(cx, cy, r - corner * 2)
    d.polygon(pts, fill=fill)
    for p in pts:
        d.ellipse([p[0] - corner * 2, p[1] - corner * 2,
                   p[0] + corner * 2, p[1] + corner * 2], fill=fill)
    for i in range(3):
        a, b = pts[i], pts[(i + 1) % 3]
        d.line([a, b], fill=fill, width=max(1, int(corner * 4)))


def draw_current(d, cx, cy, s):
    """Approximation of today's CoinIcon: gradient disc, squiggle rim,
    triangle hole, highlight crescent, dark outline."""
    r = s / 2
    top, mid, bot = (255, 240, 140), (247, 201, 56), (199, 128, 15)
    y = int(cy - r)
    while y <= int(cy + r):
        t = (y - (cy - r)) / (2 * r)
        if t < 0.45:
            k = t / 0.45
            c = tuple(int(top[i] + (mid[i] - top[i]) * k) for i in range(3))
        else:
            k = (t - 0.45) / 0.55
            c = tuple(int(mid[i] + (bot[i] - mid[i]) * k) for i in range(3))
        dy = y - cy
        if abs(dy) <= r:
            dx = math.sqrt(max(0, r * r - dy * dy))
            d.line([(cx - dx, y), (cx + dx, y)], fill=c)
        y += 1
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(60, 45, 20),
              width=max(1, int(s * 0.04)))
    pts = []
    for i in range(221):
        a = i / 220 * 2 * math.pi
        rr = s * 0.405 + math.sin(a * 28) * s * 0.022
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.line(pts, fill=(148, 97, 13), width=max(1, int(s * 0.04)))
    d.polygon(tri_points(cx, cy, s * 0.20), fill=(90, 58, 6))
    hr = r * 0.78
    hx, hy = cx - s * 0.10, cy - s * 0.10
    d.arc([hx - hr, hy - hr, hx + hr, hy + hr], 190, 280,
          fill=(255, 250, 220), width=max(1, int(s * 0.05)))


def draw_a_triangle(d, cx, cy, s):
    """A - Gold Triangle: one rounded triangle, flat gold, dark outline."""
    r = s * 0.56
    cy2 = cy + s * 0.07          # optical centering: a triangle's mass sits low
    rounded_tri(d, cx, cy2, r, s * 0.045, GOLD_DARK)
    rounded_tri(d, cx, cy2, r - s * 0.085, s * 0.03, GOLD)


def draw_b_ring(d, cx, cy, s):
    """B - Ring Coin: flat gold disc, one thick inner ring, dark outline."""
    r = s / 2
    ow = s * 0.08
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD_DARK)
    d.ellipse([cx - r + ow, cy - r + ow, cx + r - ow, cy + r - ow], fill=GOLD)
    ir, iw = s * 0.30, s * 0.09
    d.ellipse([cx - ir - iw / 2, cy - ir - iw / 2,
               cx + ir + iw / 2, cy + ir + iw / 2], fill=GOLD_MID)
    d.ellipse([cx - ir + iw / 2, cy - ir + iw / 2,
               cx + ir - iw / 2, cy + ir - iw / 2], fill=GOLD)


def draw_c_punched(d, cx, cy, s):
    """C - Punched Coin: flat gold disc, dark outline, one bold triangle."""
    r = s / 2
    ow = s * 0.08
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD_DARK)
    d.ellipse([cx - r + ow, cy - r + ow, cx + r - ow, cy + r - ow], fill=GOLD)
    rounded_tri(d, cx, cy + s * 0.03, s * 0.25, s * 0.02, GOLD_DARK)


ROWS = [
    ("Today (approx.)", "gradients, squiggle rim, hole, shine", draw_current),
    ("A  Gold Triangle", "flat triangle, rounded corners", draw_a_triangle),
    ("B  Ring Coin", "flat disc + one thick inner ring", draw_b_ring),
    ("C  Punched Coin", "flat disc + one bold triangle", draw_c_punched),
]


def render(rows, path):
    label_w, cell_w, row_h, top = 230, 76, 92, 64
    W = label_w + cell_w * len(SIZES) + 30
    H = top + row_h * len(rows) + 14
    k = SCALE * SS
    img = Image.new("RGB", (W * k, H * k), BG)
    d = ImageDraw.Draw(img)
    try:
        f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 13 * k)
        fs = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 10 * k)
    except OSError:
        f = fs = ImageFont.load_default()
    for i, s in enumerate(SIZES):
        x = (label_w + cell_w * i + cell_w / 2) * k
        d.text((x, 30 * k), f"{s} pt", fill=SUB, font=fs, anchor="mm")
    for ri, (name, note, fn) in enumerate(rows):
        y0 = top + row_h * ri
        d.text((16 * k, (y0 + 34) * k), name, fill=TEXT, font=f, anchor="lm")
        d.text((16 * k, (y0 + 54) * k), note, fill=SUB, font=fs, anchor="lm")
        for i, s in enumerate(SIZES):
            cx = (label_w + cell_w * i + cell_w / 2) * k
            cy = (y0 + 44) * k
            # Small sizes sit on a card or pill in the game; large ones on the
            # plain screen background.
            if s <= 26:
                pw, ph = 66 * k, 70 * k
                d.rounded_rectangle([cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2],
                                    radius=14 * k, fill=CARD)
            fn(d, cx, cy, s * k)
    img.resize((W * SCALE, H * SCALE), Image.LANCZOS).save(path)


if __name__ == "__main__":
    render(ROWS, "coin-proposals.png")
    for name, note, fn in ROWS[1:]:
        slug = name.split()[0].lower()
        render([ROWS[0], (name, note, fn)], f"coin-proposal-{slug}.png")
    print("ok")
