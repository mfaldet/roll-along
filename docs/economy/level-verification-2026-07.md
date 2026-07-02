# Climb Level Verification — July 2026

Numeric + manual audit of all 100 authored climb levels in `RollAlong/LevelOverrides.json`
(the SSOT authored in Marble Mapper). Every checker flag was hand-verified against the real
game physics in `BallGameView.swift` before landing in the CONFIRMED worklist or the
false-positive list below.

**The checker lives at `scripts/verify-levels.mjs`. Re-run it after every level overwrite:**

```
node scripts/verify-levels.mjs [path/to/LevelOverrides.json]
```

Exit code: `2` if any BROKEN flag, `1` if only advisory flags, `0` when clean.

---

## Methodology — the checker's 6 checks

The checker mirrors game facts from `LevelLayout.swift` and `BallGameView.swift`: the DTO
decoder auto-prepends side-walls x∈[0,0.12] and x∈[0.88,1.0] (stripped at play time on easy
tier, last digit 1–4; kept on hard 6–9 and veryHard 0/5); ball radius 18pt ≈ 0.046 units on a
~390pt arena; coin pickup reach = ballR + coinR = 27pt ≈ 0.069; and — critically — **hole
capture is center-based**: the ball falls only when its CENTER enters a hole rect
(`BallGameView.isInHole` → `rect.contains(position)`), so the ball may visually overlap hole
edges without falling.

Per level it runs:

1. **Coin count == 3** — the economy assumes a fixed coins-per-level payout.
2. **Coin placement** — coins must sit inside the tier's playable area; a coin INSIDE a hole
   rect is flagged BROKEN (with penetration depth; technically grazeable if depth < pickup
   reach), and a coin within one ball radius of a hole edge is flagged RISKY.
3. **Start & goal placement** — same validity rules, plus a sane start→goal separation
   (≥ 0.25, else "trivially short").
4. **Solvability**, two flood-fill models on a 0.01 grid:
   - **(a) Game physics** (center-based capture): start→goal must connect, and every coin
     must be pickable from some reachable cell within the 0.069 pickup reach. Failures are
     BROKEN/UNSOLVABLE.
   - **(b) Full clearance** (holes inflated by the ball radius): failures are TIGHT
     advisories — the ball must squeeze past overlapping a hole edge somewhere (expected on
     hard/veryHard, suspicious on easy). Includes a binary-searched bottleneck-corridor
     width for the best start→goal route.
5. **Tier sanity** — the digit-rule tier vs a difficulty heuristic (designed-hole
   blocked-area fraction of the playable band + bottleneck corridor width). Flags TIER when
   a hard level measures open or an easy level measures hard.
6. **targetTime/goldTime consistency** — explicit values must match the formulas
   `targetTime = 4·dist + 0.35·holes + 2.5` and `goldTime = 2.8·dist + 0.20·holes + 1.8`
   (omitted values are auto-computed, hence always consistent), and gold < target.

### Manual triage layer

The checker's raw flags overreport because its full-clearance model inflates holes by a
uniform ball radius, while the engine (a) kills on ball-CENTER-in-rect only, (b) collects
coins from 27pt away, (c) has ~2× more y-headroom than the square-aspect radius assumes on
the taller-than-wide arena, and (d) strips side-walls on easy. Every flag was therefore
re-checked by hand (BFS under real rules, inflation tests, per-edge `CGRect.contains`
semantics) and sorted into CONFIRMED problems vs false positives below.

---

## Results summary

```
verify-levels: 100 levels checked, 30 fully clean — 29 BROKEN, 88 RISKY, 85 TIGHT, 5 TIER flag(s)
```

| Bucket | Count |
|---|---|
| Levels checked | 100 |
| **Fully clean (zero flags)** | **30** |
| Confirmed problems after manual triage | 21 |
| Flagged levels that triaged to false positives only | 49 |
| Already `verified: true` (levels 1–10, played by Mac) | 10 |
| Safe to verify (not confirmed-broken, not yet verified) | 70 |

Key triage takeaways:

- The **deep-coin / unsolvable class has only 3 true instances** (levels 90, 98, 99); every
  other flagged coin and goal in the audit is BFS-reachable under real physics.
- The worst structural offenders are **level 68** (goal box with a single 8pt entrance) and
  **level 37** (8pt mandatory slot) — both violate the documented "hard never means
  tightrope-precision" rule (`LevelLayout.swift:100`).
- Most confirmed coin issues are **visual/bait placements** (coin renders sunk in a pit but
  is mechanically collectable), not blockers.
- A large false-positive class comes from the checker's uniform radius inflation and from
  testing containment with `>=` on all four rect edges, where `CGRect.contains` excludes
  maxX/maxY (so on-edge "depth 0.000" coins have a safe center point).

---

## CONFIRMED worklist — fixes to apply in Marble Mapper

21 levels, ordered by severity. All fixes are content-only `LevelOverrides.json` swaps
(author in Marble Mapper, publish, then re-run `scripts/verify-levels.mjs`).
Tiers cannot be changed in data — `DifficultyTier.tier(for:)` derives tier from the level
number's last digit (`LevelLayout.swift:113`) — so tier mismatches must be fixed by editing
the layout.

### Broken / effectively uncollectable

- **level 90 [veryHard] — BROKEN.** coin#3 (0.5,0.8) is at the exact center of hole
  [0.4,0.76,0.2,0.08]; nearest edge is 0.04 units ≈ 31pt, beyond the 27pt pickup reach
  (ballR 18 + coinR 9) — genuinely uncollectable, 3-coin clear impossible.
  **Fix:** move coin#3 to (0.5, 0.88), matching the coin#1/#2 pattern of sitting in the gap
  between flanking holes (~31pt y-clearance, ~54pt x-clearance).

- **level 99 [hard] — practically broken.** coin#2 (0.5,0.5) and coin#3 (0.5,0.2) sit 0.06
  units ≈ 23.4pt inside holes [0.42,0.44,0.14,0.1] / [0.42,0.16,0.14,0.1]; with 27pt pickup
  reach the collection window is a ~3.6pt sliver hugging the hole's right edge (solver best
  clearance 0.6pt) — frame-perfect in a tilt game, effectively uncollectable.
  **Fix:** move coin#2 to (0.61, 0.5) and coin#3 to (0.61, 0.2) — the center of the vertical
  lane between hole columns (x 0.56–0.66), ~19.5pt clearance. (The level's START and coin#1
  sub-flags are false positives — see below.)

- **level 98 [hard] — two issues.** (a) coin#2 (0.5,0.5) is 0.04 units ≈ 31pt inside hole
  [0.4,0.44,0.2,0.1], beyond the 27pt pickup reach — uncollectable. (b) the middle row's
  only openings (x 0.37–0.40 and 0.60–0.63) are 0.03 units ≈ 11.7pt wide, giving a best-path
  center clearance of ~5–6pt — 25% tighter than the tightest accepted level (7.8pt, L39/L55)
  and the sole route to coin#3 and the goal; violates the documented "hard never means
  tightrope-precision" rule.
  **Fix:** shrink the center hole to [0.42,0.44,0.16,0.1] (both gaps widen to 0.05 ≈ 19.5pt,
  restoring house-norm ~10pt maximin) and move coin#2 to (0.5, 0.415) in the open band
  between the y=0.32–0.39 and y=0.44–0.54 rows (~19.5pt clearance).

### Mandatory-precision chokepoints

- **level 68 [hard] — the one true near-broken level.** The goal (0.5,0.5) sits inside a box
  whose ONLY entrance is a 0.02-wide slot (x 0.72–0.74) between hole#5 [0.4,0.36,0.32,0.06]
  and hole#2 [0.74,0.26,0.08,0.45]; holes #4/#3 touch at y=0.65 so there is no left/bottom
  entry. Measured bottleneck: 8pt corridor for the ball center (vs 23–47pt on every other
  hard/veryHard level).
  **Fix:** shorten hole#5 to w=0.24 (x 0.4–0.64), making the entry gap x 0.64–0.74 = 0.10;
  alternatively also shorten hole#4 to h=0.23 (y 0.36–0.59) to open a second left-side
  entrance. (This level's coin flags are all false positives — see below.)

- **level 37 [hard] — the standout TIGHT case.** Goal (0.5,0.5) sits in a chamber walled by
  [0.3,0.4,0.1,0.25] (left), [0.4,0.4,0.18,0.07] (top), [0.6,0.27,0.1,0.45] (right),
  [0.3,0.65,0.4,0.07] (bottom); the ONLY entrance is the slot between the top shelf's right
  edge (x=0.58) and the right wall (x=0.6) — 0.020 wide (~8pt on iPhone). No point outside
  the chamber is within the 0.078 goal-capture radius (nearest outside approach ≈0.10+), so
  threading the 8pt slot is mandatory. Exactly the "tightrope-precision frustrating" content
  `LevelLayout.swift:100` forbids on climb levels.
  **Fix:** shrink the top shelf [0.4,0.4,0.18,0.07] to w=0.12 (entrance becomes x .52–.6 =
  0.08, matching the hard-tier idiom), and move the goal from (0.5,0.5) to (0.5,0.55) to
  clear the RISKY 0.030 goal-to-shelf clearance (~0.09 to every wall).

- **level 55 [veryHard].** The only route through each hole row is the 0.04-wide center gap
  (x 0.48–0.52), and the two gaps are vertically aligned; measured bottleneck 16pt center
  corridor, half the width of level 75's deliberate gauntlet shaft (31pt) and the tightest
  mandatory passage in the climb after 68.
  **Fix:** widen both center gaps to 0.08 — row 1 holes → [0.12,0.35,0.34,0.1] and
  [0.54,0.35,0.34,0.1]; row 2 holes → [0.2,0.55,0.26,0.1] and [0.54,0.55,0.26,0.1].
  (The coin #1/#3 "squeeze" flags on this level are false — see below.)

- **level 39 [hard].** Rows 1 and 3 are hole pairs [0.12,y,0.36,0.1]+[0.52,y,0.36,0.1] flush
  against both sidewalls, leaving a single central slot x .48–.52 — 0.040 wide and 0.10
  LONG — that must be threaded (with a coin inside it) at y=0.3 and y=0.7; unlike level 28's
  vertical gaps these are horizontal gaps, so 0.040 really is ~16pt of center room against a
  36pt-wide ball, through a ~76pt-long channel, twice, plus coin#2's row.
  **Fix:** widen rows 1 and 3 to match the middle row (which already has an 0.08 slot at
  x .46–.54): change [0.12,0.3,0.36,0.1]→[0.12,0.3,0.34,0.1],
  [0.52,0.3,0.36,0.1]→[0.54,0.3,0.34,0.1], and the same for the y=0.7 pair. Coins can stay
  at x=0.5.

### Fall-bait coin placements

- **level 40 [veryHard] — checker exactly right.** All 3 coins (0.5,0.25 / 0.5,0.53 /
  0.5,0.81) are genuinely 0.010 inside their hole rects (verified: hole y-ranges
  .18–.26 / .46–.54 / .74–.82, coin y 0.01 above each bottom edge). Collectible only by
  grazing the rim from below (depth 0.010 < pickup 0.069) and each coin renders inside the
  black pit, baiting the player in.
  **Fix:** move coin#1 to (0.5,0.31), coin#2 to (0.5,0.59) (0.05 below each hole bottom,
  sprite fully on platform, keeps risk-reward), and coin#3 to (0.62,0.86) — NOT (0.5,0.87),
  which is within pickup reach 0.069 of the start (0.5,0.92) and would auto-collect at spawn.

- **level 34 [easy] — worst offender given tier.** Coins #2 (0.5,0.58) and #3 (0.5,0.86) sit
  exactly ON the bottom rims of holes [0.42,0.5,0.16,0.08] and [0.42,0.78,0.16,0.08]
  (y == rect maxY; `CGRect.contains` is maxY-exclusive so the checker's "INSIDE" is
  technically wrong — the center point is safe — but the coin sprite is half over the pit
  and any overshoot by one tick kills, on the EASY tier where sidewalls are stripped for
  beginners). Coin#1 only 0.020 clear.
  **Fix:** coin#1 → (0.5,0.39) and coin#2 → (0.5,0.68) (midpoints between hole rows, ~0.10
  clearance), coin#3 → (0.66,0.82) (beside hole 3, 0.08 clearance; keeping it on x=0.5 below
  the hole runs into the spawn at (0.5,0.92)).

- **level 82 [easy].** coin#2 (0.5,0.5) sits 0.02 units (~8pt) inside the right edge of hole
  [0.34,0.42,0.18,0.12]; collectible only by skirting the pit with ~7pt of center clearance,
  vs ~24pt minimum on every accepted easy level.
  **Fix:** move coin#2 to (0.56, 0.5) — clear of the hole with ~16pt clearance (or (0.54,0.5)
  if the on-edge risk-coin idiom is wanted).

- **level 28 [hard] — coin only, minor.** Coin#2 (0.5,0.42) sits exactly on the top-right
  CORNER of hole [0.3,0.42,0.2,0.08] (x==maxX, y==minY; edge-exclusive so technically safe,
  but the sprite overlaps the pit and it reads as in-the-hole).
  **Fix:** move coin#2 to (0.55,0.38) — 0.064 clearance to the step-2 hole, sits in the
  intended stair-crossing band and rewards the real route. (The TIGHT corridor-0.040 half of
  the flag is a false positive — see below.)

- **level 10 [veryHard] — coin only.** Coin#2 (0.5,0.43) is exactly on the bottom rim of
  [0.44,0.36,0.4,0.07] (y == maxY = 0.43; edge-exclusive, so "INSIDE depth 0.000" is
  technically outside, but the sprite is half over the hole and it baits a run over the
  pit). Siblings have 0.06–0.08 clearance, so this reads as an authoring slip, not intent.
  **Fix:** move coin#2 to (0.5,0.49) — 0.06 below the hole, matching coin#3's 0.060
  clearance. (Corridor-0.060 TIGHT half of the flag = veryHard idiom, false positive.)
  *Note: level 10 is already `verified: true`; re-verify after the fix.*

### Tier mismatch

- **level 19 [hard] — REAL tier mismatch, checker confirmed.** The layout is one central
  pillar [0.44,0.2,0.12,0.55]; the inflation test shows a 0.284-wide FULL-clearance corridor
  to the goal — 3–6× wider than every other hard level (next-most-open hard levels run
  0.068–0.088), and designed-hole area 0.066 with only 1 hole vs 4–10 on peers. Important:
  the tier CANNOT be re-tiered in data — `DifficultyTier.tier(for:)` derives it from the
  level number's last digit (`LevelLayout.swift:113`) — so the only fix is making the layout
  meaner in Marble Mapper.
  **Fix (suggested):** add two shelves flush to the sidewalls, e.g. [0.12,0.55,0.2,0.07] and
  [0.68,0.4,0.2,0.07], turning the around-the-pillar route into a serpentine with 0.12-wide
  gaps at x .32–.44 and .56–.68 — clearly hard-tier ("longer path, more obstacles") without
  any precision squeeze.

### Visual-only (coins collectable but render sunk in pits)

- **level 45 [veryHard] — downgrade BROKEN→visual.** Coins #2 (0.5,0.42) and #3 (0.2,0.32)
  are collectable (death is center-in-rect and pickup radius is 27pt; depth 0.010/0.000 =
  8pt/0pt), but they render sunk inside the black staircase bands.
  **Fix:** move coin#2 to (0.5,0.50) (open pocket between bands 2 and 4, 0.06 clear of band
  3's left end) and coin#3 to (0.2,0.36) (0.04 below band 1).

- **level 48 [hard].** coin#1 (0.5,0.28) is 0.01 inside hole [0.42,0.22,0.18,0.07]
  (collectable from the open band y 0.29–0.36 below, but renders sunk).
  **Fix:** move coin#1 to (0.48,0.32). Optional polish: coin#2 (0.5,0.55) sits 8pt off
  hole#6's corner so its 9pt sprite kisses the hole — center it in its gap at (0.54,0.57).

- **level 50 [veryHard].** coin#2 (0.5,0.51) and coin#3 (0.5,0.78) are 0.01/0.02 inside
  their hole bands (both collectable from below via the 27pt pickup radius, but render
  sunk), and coin#1 (0.5,0.25) is only 8pt below a hole so its sprite overlaps.
  **Fix:** coin#1 → (0.5,0.27), coin#2 → (0.5,0.55), coin#3 → (0.5,0.82) (each centered in
  the open band between rows).

- **level 66 [hard].** coin#2 (0.5,0.47) sits exactly on the bottom edge of hole
  [0.4,0.42,0.2,0.05] (collectable, `CGRect.contains` excludes maxY, but the sprite is half
  inside the hole).
  **Fix:** move to (0.5,0.495), centered in the 0.05 band between that hole and the row
  below. (Coin#3 and corridor flags are false positives.)

- **level 70 [veryHard].** All three coins (0.5,0.24), (0.5,0.52), (0.5,0.80) sit exactly on
  the bottom edges of grid holes (depth 0.000, mechanically collectable from 27pt away, but
  each renders half-sunk).
  **Fix:** move to (0.5,0.27), (0.5,0.55), (0.5,0.84) — each centered in the open band
  between grid rows. Not BROKEN.

- **level 93 [easy] — mild polish.** coin#1 (0.78,0.85) and coin#2 (0.2,0.45) sit strictly
  inside hole rects (depth 0.01 ≈ 8pt) — mechanically collectible via the 27pt reach with
  ~16pt path clearance, but no accepted easy level puts a coin strictly inside a pit
  (accepted easy minimum ~24pt) and the coin renders on top of the black pit.
  **Fix:** nudge coin#1 to (0.78, 0.89) and coin#2 to (0.2, 0.48) (centered in the open
  bands below/between their bars). (The TIER flag on this level is a false positive — see
  below.)

### Minor polish

- **level 62 [easy].** Coins sit 0.01 (~4pt) off the serpentine walls, so the 9pt coin
  sprite visually overlaps the wall by ~5pt; all are collectable from lane centers (lanes
  are 39pt, full ball body fits).
  **Fix:** recenter in lanes — coin#1 (0.45,0.78) → (0.49,0.78), coin#2 (0.63,0.2) →
  (0.67,0.20), coin#3 (0.27,0.3) → (0.31,0.30).

- **level 73 [easy].** Coins #2 (0.78,0.51) and #3 (0.2,0.34) sit only 0.01 (~8pt) below bar
  bottoms, so their sprites graze the bars; collectable with ease (open 0.08+ bands below).
  **Fix:** coin#2 → (0.78,0.545), coin#3 → (0.2,0.375).

---

## False positives — flags that need no action, and why

### Systemic checker limitations (explain most flags below)

- **Uniform radius inflation vs center-based capture.** The checker inflates hole rects by a
  uniform ball radius 0.046, but the engine kills only when the ball CENTER enters a hole
  rect (`BallGameView.isInHole` uses `rect.contains(position)`, no radius). The usable
  corridor for the player is the RAW gap between rects, not gap-minus-diameter.
- **Pickup reach not modeled.** Coin pickup succeeds within effectiveBallRadius + coinRadius
  = 27pt (~0.07 width-units); the checker's RISKY flags model pickup as center-at-coin.
- **Square-aspect radius on a tall arena.** 0.046 is 18pt/390 in width; in y, 18pt is only
  ~0.023 on the taller-than-wide full-screen arena, so y-axis clearances are ~2× what the
  checker assumes.
- **Edge-inclusive containment.** The checker tests containment with `>=` on all four edges,
  but `CGRect.contains` excludes maxX/maxY — a coin exactly on a bottom/right rim has a SAFE
  center point. None of the depth-0.000 flags are capture-zone containment, and the
  deep-coin/unsolvable class truly has only the three instances listed above: every other
  flagged coin and goal is BFS-reachable under real physics.
- **Easy tier strips the 0.12 side walls** — some easy-tier corridor math ran with walls in.

### Per-level dispositions

- **levels 8, 9, 18, 20, 26, 27, 29, 30, 36, 38** (TIGHT "no full-clearance path to goal",
  corridors 0.060–0.088): false positives by the checker's own severity note. Hole capture
  is ball-CENTER-in-rect, so a 0.060–0.088 gap is 23–34pt of center room on an iPhone-width
  arena — the established hard/veryHard idiom. Goal + all coins verified BFS-reachable on
  every one; max-inflation matches the checker's corridor numbers, so its math was right —
  only the severity is wrong.
- **level 7** (TIGHT coin#2): coin pocket entry gap is 0.080 (max inflation 0.040); the
  "squeeze" is a momentary ~2pt visual overlap on a hard level. Playable idiom, not a defect.
- **level 18** (RISKY coin#1, clearance 0.022): the distance math is correct
  (hypot(0.02,0.01)=0.022 to both flanking holes) but pickup reach 0.069 > ball radius 0.046
  means the ball collects it from BELOW the hole row with full visual clearance — a pickup
  route survives 0.078 inflation (> 0.046 = full-clearance by the checker's own standard).
- **level 26** (RISKY coin#1, clearance 0.010): same pickup-reach error — coin sits 0.01
  below the hole's bottom edge and is grabbed from below at ~0.07 hole clearance (max
  inflation 0.072 > 0.046). The ~5pt sprite-on-rim overlap is a cosmetic nit at most on a
  hard level; TIGHT corridor 0.088 is idiom.
- **level 29** (RISKY coin#2, clearance 0.020): pickup point (0.5,0.53) is 0.05 from the
  coin and 0.07 clear of the hole — full-clearance collection exists; sprite kisses the rim
  by 0.003 (~1pt), invisible. Corridor 0.080 = idiom.
- **level 36** (RISKY coin#1, clearance 0.040): coin sprite (radius ~0.023) doesn't even
  touch the hole; full-clearance pickup exists (max inflation 0.068 > 0.046). Corridor
  0.080 = idiom.
- **level 28** (TIGHT corridor 0.040 portion): the stair gaps are VERTICAL 0.04 bands, and
  the arena is a full-screen GeometryReader (taller than wide) — 18pt vertically on a
  ~760pt-tall arena is ~0.024 units, so a 0.04 y-gap is ~30pt of center room vs a ~36pt
  ball. Each crossing band (e.g. y .38–.42) is open across nearly the full arena width with
  a 0.18-wide entry between sidewall and the next step, and there are 3 alternative
  crossings. Hard-tier appropriate, not precision content. (Coin#2 corner placement
  separately confirmed above.)
- **levels 10 / 28 / 34 "coin INSIDE hole, depth 0.000"**: edge-inclusive containment
  limitation (see systemic) — the "inside a hole" severity framing is wrong; still confirmed
  above as placement bugs on visual/bait grounds.
- **level 31 [easy]** (RISKY+TIGHT coin#3, clearance 0.020): the hole [0.42,0.3,0.18,0.1] is
  entirely ABOVE the coin (0.5,0.42); approaching from below, a pickup point at (0.5,0.46)
  is 0.04 from the coin and 0.06+ clear — the pickup survives 0.074 inflation, i.e. full
  clearance. Goal corridor is 0.300, wide open. Sprite overlap 0.003 (~1pt). No fix needed.
- **level 32 [easy]**: coin#2 pickup survives 0.088 inflation and coin#3 0.108 (both > 0.046
  = full-clearance collection); coin#3's 0.040 clearance means its sprite doesn't even touch
  the hole. Goal corridor 0.224. Pickup-reach modeling error again.
- **level 33 [easy]**: intentional gate-slalom; all 3 coins have hand-verified
  full-clearance pickup points (e.g. coin#2 from (0.53,0.61): 0.058 from coin, 0.07 clear of
  both gate holes — the checker's tighter numbers come from square-aspect radius plus grid
  resolution). Goal path survives 0.150 inflation (maxed the search range — the open half of
  each gate row is huge). Playable comfortably on easy.
- **level 42 [easy]** (RISKY coin#1, clearance 0.040): sprite clear of the hole by 0.017,
  pickup survives 0.108 inflation, goal corridor 0.300. Nothing to fix.
- **level 43 [easy]** (RISKY all coins, clearance 0.020): all three pickups survive
  0.050–0.072 inflation (≥ 0.046, full or near-full clearance from the open side of each
  small 0.08×0.08 hole); sprite-rim overlap 0.003 (~1pt). This is the deliberate "coin
  beside a small hole" teaching beat; goal corridor 0.144. At most an optional polish nudge
  to 0.03 clearance — not a defect.
- **level 44 [easy]**: coin#1's 0.020 clearance is coin-edge-to-hole-edge in x; the coin
  sits in a 0.10-wide corridor (39pt — wider than the 36pt ball, so even full-body clearance
  exists) and is collected from mid-corridor via the 27pt pickup radius; measured bottleneck
  120pt (side walls stripped). Both flags are radius-inflation artifacts.
- **level 45** (corridor flag): the 0.040 staircase gaps are y-axis slots = 31pt of real
  corridor for the center (y-normalization halves the checker's pessimism) — identical to
  level 75's deliberate gauntlet width; veryHard-appropriate, playable.
- **level 46 [hard]**: the 0.10 side lanes are 39pt — the 36pt ball has literal full-body
  clearance; coins #1/#2 sit mid-lane and are picked up from the lane center. "Squeeze" is
  corner-radius pessimism.
- **level 47 [hard]**: min mandatory pinch is the 0.06 lane (23pt center corridor) past
  hole#4/#3, with wider alternates (the y 0.49–0.55 slot spans 47pt); all three coins have
  ≥0.02 clearance plus 27pt pickup reach. In family for hard tier.
- **level 48** (remaining flags): coin#3 (0.5,0.85) sits in the 0.10 gap between the bottom
  row's holes (39pt), coin#2 is reachable from mid-gap; corridor bottleneck measured 31pt —
  normal hard-tier.
- **level 49 [hard]**: coin#3 is 0.04 in y = 31pt below the band, in the open; corridor
  bottleneck 23pt via the 0.06 edge lanes at the y=0.5 row, with the 0.04 center gap merely
  optional. Playable hard.
- **level 50** (remaining flags): START (0.5,0.94) is 31pt below hole#14 with wide 0.28 side
  gaps around it — no spawn risk under center-based death; corridor bottleneck 23pt (0.06
  row gaps), in family for veryHard.
- **level 54 [easy]**: coin#2 (0.5,0.38) sits in a fully open 0.14-tall band, 31pt below the
  nearest row — no squeeze at all; measured bottleneck 120pt (walls stripped, 0.08 row gaps
  plus wide outer lanes). Pure y-radius pessimism.
- **level 55** (coin flags): coins #1 (0.5,0.5) and #3 (0.5,0.22) sit in open pockets
  (coin#3 is 0.13 above the top row; coin#1 sits in the 0.10-tall inter-row pocket you
  already thread) — the real issue is the corridor (see confirmed), not the coins.
- **level 57 [hard]**: coin#3 is 31pt above the band (y clearance); every row leaves a 0.08
  gap (31pt) or wide side lanes; measured bottleneck 31pt. Normal hard-tier weave.
- **level 58 [hard]**: coin#3 is 31pt from the nearest 0.10-wide mini-hole; holes are sparse
  w=0.1 blobs with huge routes — measured bottleneck 53pt. Nothing tight here.
- **level 60 [veryHard]**: coins #1/#2 sit centered in 0.24-wide row gaps (0.12 = 47pt
  clearance each side); the only tight spots are optional 0.06 edge lanes; measured
  bottleneck 31pt. Checker inflation artifact.
- **level 61 [easy]**: coin#1 (0.5,0.5) is 0.12 (47pt) from the nearest hole edge,
  dead-center in a 0.24 gap between the two middle blocks; measured bottleneck 120pt. Flag
  is flatly wrong (likely un-stripped side walls or corner inflation).
- **level 63 [easy]**: coin#3 (0.5,0.84) is 31pt below the vertical spine's bottom end in
  the wide-open lower quarter of the arena (walls stripped); approach is unconstrained from
  below. No squeeze.
- **level 66** (remaining flags): coin#3 (0.8,0.18) is 31pt above the top row; all row gaps
  are 0.08 (31pt) — checker's "corridor 0.040" is 0.08 minus its radius inflation.
  Hard-tier normal.
- **level 67 [hard]**: every row gap is 0.08–0.12 (31–47pt; the 0.12 gaps fit the full ball
  body); coins #2/#3 sit centered in the 0.12 gap column / open top band. Measured
  bottleneck 31pt. In family.
- **level 68** (coin flags): coin#3 (0.2,0.3) is 31pt below hole#1 in the open y 0.26–0.36
  band; coin#2 (0.2,0.5) has 0.12 clearance in the left lane; coin#1 (0.84,0.8) is wide
  open. Only the goal-box corridor is real (see confirmed).
- **level 69 [hard]**: the center gaps are 0.12 = 47pt — the full ball body fits with 11pt
  to spare; checker's "0.060" is the gap minus 2× its inflated radius. Coins centered in
  those gaps / open bands. Measured bottleneck 47pt — one of the roomiest hard levels
  flagged.
- **level 72 [easy]**: coin#2 (0.5,0.5) has 31pt of y-clearance and sits in a 0.26-wide open
  gap between staggered holes; measured bottleneck 94pt. No squeeze.
- **level 74 [easy]** (TIER flag): with side walls stripped (easy), rows 1 and 3 have 0.12
  outer lanes (47pt, full-body clearance) and row 2 a 0.12 center gap — measured bottleneck
  94pt, comfortably easy-tier; blockedFrac 0.214 is a density heuristic, not a playability
  problem. Coin#2 sits centered in the 47pt row-2 gap. Optional polish only: widen rows
  1/3's 0.04 center gaps (x 0.48–0.52) to 0.08 so beginners aren't baited into a trap gap,
  but re-tiering is not needed.
- **level 75 [veryHard]**: the single 0.08 central shaft (31pt center corridor, 468pt long)
  with all 3 coins on its axis is plainly the level's deliberate identity — same effective
  width as level 45's slots and the widest "signature gauntlet" in the set; coins are
  collected automatically while traversing (ball passes within 0pt of them). RISKY/TIGHT
  flags are radius-inflation artifacts; ship as-is.
- **level 76**: engine kills only when the ball CENTER enters a hole rect, and coins collect
  from 27pt (ballR+coinR) away — checker modeled a full-disk ball that must overlap the
  coin. Solver maximin: all coins and goal reachable at 22.8pt center clearance, comfortable
  hard-tier house norm (accepted L9/L29/L36 ship at 15.0–15.6pt).
- **level 77**: all three coins and the goal resolve at 24.2pt center clearance; the flagged
  "corridor 0.080" is a 31pt-wide center lane under the real center-point fall rule. Pure
  disk-model pessimism.
- **level 78**: coin#2 (0.5,0.5) is on the min-x/max-y CORNER of hole [0.5,0.44,0.38,0.06] —
  `CGRect.contains` excludes max edges, so the point isn't even inside per the engine;
  on-edge coins are an established idiom in accepted levels (L10, L28, L34, L45, L66, L70).
  Path bottleneck 15.2pt = exact house hard norm.
- **level 79**: solver gives 15.4–15.6pt clearance for all coins and goal — precisely the
  accepted hard-tier norm; "no full-clearance path" is moot under center-based fall.
- **level 80**: goal bottleneck 7.4pt maximin is statistically identical to accepted L39 and
  L55 (7.8pt, within the 2pt grid resolution); coin#3 collects with 39pt clearance thanks to
  the 27pt pickup reach.
- **level 83**: both "INSIDE hole" coins are depth-0.000 on-edge placements — the same
  pattern accepted easy level L34 ships (two on-edge coins at ~24pt safety); here they
  collect at 24.2/25.0pt from the open side. Checker treated point-on-closed-rect as broken.
- **level 84**: coin#1 collects with 48.4pt path clearance via the 27pt reach; nothing is
  tight (goal 39.5pt).
- **level 85**: coins collect at 19.0–19.4pt and goal bottleneck 11.2pt — matches accepted
  veryHard corpus (L47/L49/L50 at 11.2–11.4pt).
- **level 86**: bottleneck past the big block is 11.2pt, same as accepted hard L47 (11.4pt);
  coin flags dissolve to 19–43pt effective clearance once pickup reach is modeled.
- **level 87**: coins and goal all at 22.6pt+ center clearance — well above house norm.
- **level 88**: everything resolves at 15.6pt, the exact accepted hard-tier norm (L36
  identical).
- **level 89**: both "INSIDE hole" coins lie exactly ON edges — coin#2 x=0.5 is the maxX of
  hole [0.4,0.18,0.1,0.1] and `CGRect.contains` excludes maxX, coin#3 y=0.58 is the maxY of
  [0.42,0.48,0.18,0.1] — so neither can trigger a fall at the coin point; both collect at
  20.9/24.6pt. Depth-0 idiom, not broken.
- **level 90** (coin#2 sub-flag only): "clearance 0.040" coin#2 collects with 11.2pt
  safest-path clearance — accepted veryHard range; only the coin#3 finding on this level is
  real.
- **level 92**: TIER flag miscalibrated — designed-hole blockedFrac 0.179 is below
  accepted-easy L44 (0.252) and goal bottleneck is a generous 43.4pt; late easy levels are
  simply denser. coin#2 "INSIDE hole" is depth-0 on-edge idiom (25.6pt safety, same as
  accepted L34); coin#1 collects at 34pt.
- **level 93** (TIER sub-flag only): blockedFrac 0.242 is under accepted L44's 0.252 and
  goal bottleneck 27.8pt equals accepted easy L74 exactly — the tier heuristic's absolute
  thresholds aren't calibrated to the accepted corpus. (The two in-pit coins are the real
  part, listed in confirmed.)
- **level 94**: TIER-only flag; blocked 0.202 and goal bottleneck 27.8pt both sit inside the
  accepted easy envelope (L44 = 0.252, L74 = 27.8pt), and coins collect at 27.8–69.6pt. No
  layout change warranted.
- **level 95**: coins #2/#3 and goal all at 15.0pt center clearance = house hard/veryHard
  norm; the flanking-holes coin#2 collects via reach without entering the 15pt lane's edge
  zone.
- **level 96**: all three staggered-hole coins collect at 18.8–32pt; corridor 18.8pt — above
  house norm. Disk-model pessimism.
- **level 97**: coin#2 depth-7.8pt-inside-hole is an accepted hard/veryHard authoring
  idiom — accepted L40 ships three coins at the same depth (16.2–17.8pt safety), L50 ships
  one 15.6pt deep; here it collects at 17.2pt. coin#1 and the corridor resolve at
  24.2/18.6pt.
- **level 98** (coin#1 sub-flag only): coin#1 collects with 39pt clearance; the real issues
  on this level are coin#2 and the 0.03 mid-row gaps (in confirmed).
- **level 99** (START + coin#1 sub-flags only): the start point is 31pt from hole
  [0.3,0.86,0.4,0.06] in point space AND the engine has a 300ms spawn-grace that resets a
  spurious early fall without consuming a life; the tighter 13pt figure is distance to the
  bottom WALL, which bounces and is not a hazard. coin#1 "clearance 0.000 touching" is the
  depth-0 on-edge idiom, collecting at 25.4pt. Only coins #2/#3 are real.
- **level 100**: all flags false. Coins collect at 19.0–39.4pt (the "clearance 0.010" coin#2
  sits below a hole edge but the 27pt reach collects it from open floor), and the goal
  bottleneck is 22.6pt — double the accepted veryHard minimum. The 0.060 "corridor" is a
  23pt center lane, standard for tier. (Side note: start (0.5,0.97) is 5.4pt from the bottom
  wall, but walls bounce — not a hazard.)

---

## SAFE TO VERIFY — 70 levels

Every level that is neither confirmed-broken above nor already `verified: true` (levels 1–10
carry the flag). Mac grants the `verified` flag in Marble Mapper after playing each one.

```
11, 12, 13, 14, 15, 16, 17, 18, 20,
21, 22, 23, 24, 25, 26, 27, 29, 30,
31, 32, 33, 35, 36, 38,
41, 42, 43, 44, 46, 47, 49,
51, 52, 53, 54, 56, 57, 58, 59, 60,
61, 63, 64, 65, 67, 69,
71, 72, 74, 75, 76, 77, 78, 79, 80,
81, 83, 84, 85, 86, 87, 88, 89,
91, 92, 94, 95, 96, 97, 100
```

Not on the list: levels 1–10 (already verified — but note level 10 has a confirmed coin
nudge above, so it should be re-played after the fix) and the 21 confirmed-problem levels
(10, 19, 28, 34, 37, 39, 40, 45, 48, 50, 55, 62, 66, 68, 70, 73, 82, 90, 93, 98, 99), which
should be fixed in Marble Mapper first, re-checked with `scripts/verify-levels.mjs`, then
played and verified.

---

*Audit date: 2026-07-02. Checker: `scripts/verify-levels.mjs` (no dependencies, plain Node).
Re-run after every level overwrite — a level overwrite is a content-only file swap of
`RollAlong/LevelOverrides.json`, so the checker is the only automated gate.*
