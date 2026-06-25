# Pinball Rebuild — Sprint Roadmap

> Status: **Sprints 1–2 — first working model committed (needs device build + feel tuning)**
> Last updated: 2026-06-25

The first pinball minigame (hand-rolled physics + primitive shapes in a SwiftUI
`Canvas`) was **scrapped and rebuilt from scratch on SpriteKit**. This doc is the
living plan; update the status column + per-sprint checklists as we go.

## v1 working model (built 2026-06-25)

`RollAlong/PinballView.swift` was fully replaced with a self-contained SpriteKit
build (SwiftUI host + `PinballScene` + `PinballModel` in one file — no new
project files). The layout is a **to-scale reading of the CIRCUS / BIG SHOW
chart**: open lower-centre, three pop bumpers up top, a central column of flush
rollover buttons, standup targets down the sides, slingshot rebounds above two
flippers, a right shooter lane, arched top. Real physics: `SKPhysicsBody` ball,
edge-chain walls, kinematic flippers (tap left/right half), pop-bumper +
slingshot impulses, drain + 3-ball loop, EM scoring (bumper 100 / sling 10 /
target 500 / rollover 50) wired to `recordPinballScore`.

**Open items (Mac builds + playtests, then we tune):** the physics-feel
constants at the top of `PinballScene` (gravity, launch/bumper/sling impulses,
flipper swing) are first-pass guesses — they need a device pass. Likely
follow-ups: exact element positions vs. the chart, side outlanes, lit-bumper
logic, art/lighting (Sprint 3).

## Locked decisions (2026-06-25)

| Decision | Choice | Why |
|---|---|---|
| **Engine** | **SpriteKit** (hosted in SwiftUI via `SpriteView`) | A real 2D physics engine — `SKPhysicsBody`, pinned-joint flippers, restitution, lighting, particles. The hand-rolled Canvas physics is the root cause of the bad feel/look. |
| **Ambition** | **One great table first** | Sprints 0–3 + light modes → ship a polished single table. Modes/missions/multiball are a fast-follow (Sprint 4+). Quality on screen soonest. |
| **Theme** | **Roll Along brand** (NOT space) | *3D Space Cadet* is our reference for **how to build a correct, high-quality table** — its mechanics and polish — **not** a theme cue. The table wears Roll Along's own identity (e.g. the rollover lanes spell **ROLL**), not sci-fi/space. |

## The bar

*3D Space Cadet* **stature** — a reference for table correctness + quality +
mechanics, **not theme**. Branded **Roll Along** (not space). We hit the
*look + feel* in v1, then the *depth*.

## Layout reference & principles (Gottlieb EM wedgehead — *Circus / Big Show*)

Mac's chosen layout reference is the 1970s Gottlieb electromechanical wedgehead
*Circus / Big Show* (shared playfield; *Circus* is the add-a-ball twin of the
replay *Big Show*). Hard principles taken from it:

1. **Open lower-centre.** No obstacle parked in front of the flippers — the ball
   returns down the middle where you can see it and take a clean swing. The
   centre column is *flush rollover buttons*, not blockers. (This killed the
   earlier "center scoop above the flippers" idea.)
2. **Scoring lives up top + along the sides** — three pop ("thumper") bumpers in
   a row up top, standup targets down both side walls, rollover lanes at the top.
   "Many buttons and point systems."
3. **Rounded top ball track** — a clean arch the ball rides around from the
   shooter lane (through a one-way ball gate).
4. **Two flippers only** (no upper flipper), slingshot rebounds above them.

**EM point system** (period-accurate, what we'll emulate): pop bumpers 10 → **100
when lit**; standup targets ~**500** + advance bonus; completing the top rollover
lanes / target sequence **lights the "Special"** (free game on *Big Show*, an
extra ball on add-a-ball *Circus*); slingshots 10; **moveable posts** tune
difficulty. Play style: shoot up the open middle to feed the bumpers, work the
side targets to light the bumpers + the Special, keep it alive off two flippers.

Refs: [IPDB Gottlieb *Big Show*](https://www.ipdb.org/machine.cgi?id=277) ·
[IPDB Gottlieb *Circus*](https://www.ipdb.org/machine.cgi?id=515) ·
[Pinside rulesheet](https://pinside.com/pinball/forum/topic/gottliebs-circus).

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
| 0 | Research & Blueprint | SpriteKit spike *feels* right; table blueprint + theme approved | 🟢 done |
| 1 | Physics core & table shell | 3-ball loop (launch → flip → drain) on the real outline; tilt/nudge | 🟡 built (tuning + tilt pending) |
| 2 | Scoring hardware | Bumpers, slingshots, standup targets, rollovers all react + score | 🟡 built (lit-bumper/bonus pending) |
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
- [ ] Pop bumpers (×3 row): radial impulse + score (10 → **100 when lit**) + lamp + ding.
- [ ] Slingshots / rebounds: kicker impulse + score (10).
- [ ] Standup targets (both sides): score (~500) + advance bonus / light Special.
- [ ] Top rollover lanes (ROLL) + open-centre rollover buttons → light bumpers / advance bonus.
- [ ] Bonus counter + Special (extra ball) when the sequence completes; combos.

### Sprint 3 — Art, lighting & theme  ⚪
- [ ] Illustrated Roll Along-themed playfield background; inserts/lamps.
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

Blueprint **rev 3** (EM-wedgehead style) parts: 1. Plunger (shooter) ·
2. Shooter lane + ball gate · 3. Top arch (ball track) · 4. Top rollover lanes
(**ROLL**) · 5. Thumper (pop) bumpers (×3, in a row) · 6. Standup targets (sides) ·
7. Centre rollover buttons (**open** column) · 8. Slingshots / rebounds (×2) ·
9. Inlanes / outlanes (+ kickback) · 10. Flippers (×2) · 11. Moveable posts ·
12. Return / orbit lanes.

Evolution: rev 1 (scrapped — wrong) → rev 2 (fixed bottom-end geometry, dropped
space theme) → **rev 3** (re-laid to the open-centre EM-wedgehead philosophy:
removed the centre scoop, opened the lower-middle, moved scoring up top + to the
sides, three bumpers in a row, two flippers, clean top track).

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
