# Pinball Rebuild — Sprint Roadmap

> Status: **Sprint 0 (Research & Blueprint) — in progress**
> Last updated: 2026-06-25

The first pinball minigame (hand-rolled physics + primitive shapes in a SwiftUI
`Canvas`) is being **scrapped and rebuilt from scratch**. This doc is the living
plan; update the status column + the per-sprint checklists as we go.

## Locked decisions (2026-06-25)

| Decision | Choice | Why |
|---|---|---|
| **Engine** | **SpriteKit** (hosted in SwiftUI via `SpriteView`) | A real 2D physics engine — `SKPhysicsBody`, pinned-joint flippers, restitution, lighting, particles. The hand-rolled Canvas physics is the root cause of the bad feel/look. |
| **Ambition** | **One great table first** | Sprints 0–3 + light modes → ship a polished single table. Modes/missions/multiball are a fast-follow (Sprint 4+). Quality on screen soonest. |
| **Theme** | **Roll Along brand** (NOT space) | *3D Space Cadet* is our reference for **how to build a correct, high-quality table** — its mechanics and polish — **not** a theme cue. The table wears Roll Along's own identity (e.g. the rollover lanes spell **ROLL**), not sci-fi/space. |

## The bar

*3D Space Cadet* **stature** — used as a reference for table correctness +
quality + mechanics, **not theme**. A curved, illustrated, **lit** playfield:
top arch, shooter lane, thumper-bumper cluster, rebound slingshots,
inlanes/outlanes, rollover lanes, drop/standup targets, a spinner, a center
scoop, ranks + missions, multiball. Branded **Roll Along** (not space). We hit
the *look + feel* in v1, then the *depth*.

## What we keep vs. throw away

- **Throw away:** `RollAlong/PinballView.swift` in full (hand-rolled segment
  collision, Canvas rendering, the `MinigameMaps.PinballMaps` bumper format).
- **Keep:** the leaderboard plumbing already built —
  `GameState.recordPinballScore(_:)` + the Pinball board in `LeaderboardView`.
  The new table just calls the same hook on game-over. Also keep the
  `GameMode`/clock/economy integration points.

## Sprint scorecard

| # | Sprint | Exit criteria | Status |
|---|--------|---------------|--------|
| 0 | Research & Blueprint | SpriteKit spike *feels* right; table blueprint + theme approved | 🟡 in progress |
| 1 | Physics core & table shell | 3-ball loop (launch → flip → drain) on the real outline; tilt/nudge | ⚪ not started |
| 2 | Scoring hardware | Bumpers, slingshots, drop/standup targets, spinner, rollovers all react + score | ⚪ not started |
| 3 | Art, lighting & theme | Illustrated, lit playfield with inserts, rails, plastics, particle FX | ⚪ not started |
| 4 | Modes, missions & depth | Rank progression, lit-sequence modes, multiball, jackpots | ⚪ fast-follow |
| 5 | Audio, haptics & juice | Flipper clack, bumper ding, mode music, haptics, screen-shake | ⚪ fast-follow |
| 6 | Tuning, balance & ship | 60fps, tuned feel + economy, old `PinballView` retired | ⚪ fast-follow |

## Sprint detail

### Sprint 0 — Research & Blueprint  🟡
- [x] Diagnose root cause; decide engine / ambition / theme.
- [x] Proposed table blueprint (numbered playfield-chart, cosmic theme).
- [ ] **Physics spike** — bare SpriteKit scene: ball + 2 flippers + 1 bumper.
      De-risk the single biggest unknown (does it *feel* right?) before any
      structure work.
- [ ] Canonical element catalog → coordinates (see blueprint + list below).
- [ ] Data-driven table format (JSON) so tables stay authorable (eventually a
      Marble Mapper extension). Decide v1: hand-built table is fine; design the
      format so it can be externalized later.
- [ ] Art direction sheet: palette, insert/lamp style, plastics, apron.

### Sprint 1 — Physics core & table shell  ⚪
- [ ] `SpriteView`-hosted `SKScene`; gravity tuned to a table slope.
- [ ] Table boundary as edge physics bodies from the blueprint outline
      (curved top arch, side rails) — **not** a rounded rect.
- [ ] Shooter lane + variable-power plunger (hold-to-charge).
- [ ] Lower flippers: pinned bodies + angular impulse on tap; tuned
      restitution/friction so flicks land and don't tunnel.
- [ ] Tilt / nudge via accelerometer + tilt warning + penalty.
- [ ] Drain detection, ball count (3), ball-save timer.

### Sprint 2 — Scoring hardware  ⚪
- [ ] Pop bumpers: radial impulse + score + lamp flash + ding.
- [ ] Slingshots: triangular kickers, impulse + score.
- [ ] Drop-target bank (bank-clear bonus + multiplier), standup targets, spinner.
- [ ] Rollover lanes (ROLL) → lane completion bonus / lane change.
- [ ] Bonus counter + playfield multiplier; combos.

### Sprint 3 — Art, lighting & theme  ⚪
- [ ] Illustrated cosmic playfield background; inserts/lamps.
- [ ] Rails, lane guides, apron art, plastics.
- [ ] `SKLightNode` / emissive lighting; lamps light per game state.
- [ ] Particle FX (bumper sparks, ball trail, mode bursts); ball reflection.
- [ ] Score HUD + DMD-style callouts.

### Sprint 4+ — Depth, audio, ship (fast-follow)  ⚪
- Modes/missions framework + rank progression (Cadet → Admiral) tied to the
  Roll Along economy/cosmetics; multiball; jackpots; kickback.
- Sound design + haptics + juice.
- Physics tuning + balance; leaderboard wiring; performance; retire old view.

## Canonical element catalog (the blueprint, keyed)

1. Plunger (variable-power launch) · 2. Shooter lane · 3. Top arch · 4. Rollover
lanes (**ROLL**) · 5. Orbit / return lanes · 6. Pop bumpers (×3) · 7. Spinner ·
8. Drop-target bank (spaced) · 9. Center scoop (saucer) · 10. Slingshots (×2) ·
11. Inlanes / outlanes (+ kickback) · 12. Flippers (lower ×2 + 1 upper) ·
13. Standup targets · 14. Posts / rubbers.

Blueprint **rev 2** corrected the bottom-end geometry (flippers no longer cross;
real inlane/outlane channels; slingshots in the proper rebound position),
spaced the drop targets, reshaped the top arch, and dropped the space theme.

## Tech notes (SpriteKit)

- Host: `SpriteView(scene:)` inside the existing SwiftUI navigation; pass a
  `GameState` reference in for coins/haptics/score submission.
- Physics: one dynamic `SKPhysicsBody` ball; static edge bodies for walls;
  flippers = kinematic bodies on `SKPhysicsJointPin`, driven by angular impulse;
  bumpers/slings apply impulses in `didBegin(_:)` via contact bitmasks.
- Gravity: `physicsWorld.gravity` tuned low (table-slope feel), plus optional
  accelerometer nudge.
- Coordinate space: design in the blueprint's units, scale to the device.

## Risks / open questions

- **Feel is the whole game** — Sprint 0's physics spike must pass before we
  invest in structure/art. If SpriteKit flippers don't feel right tuned, revisit.
- **Performance**: lighting + particles at 60fps on older devices — budget early.
- **Table authoring**: hand-built v1 vs. JSON-driven. Leaning hand-built for v1,
  format designed for later externalization.
- **No local compiler** for Roll Along — build in small, separately-committed
  increments; Mac compiles/playtests.
