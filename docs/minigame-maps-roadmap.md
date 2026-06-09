# Minigame Maps Roadmap

Seven competitive minigames currently ship with a single static (or trivially random) arena.  This roadmap adds curated map variety to every game that places obstacles, and introduces the shared infrastructure — wall segments and pillars — needed to support varied layouts across games.

---

## Current State

| Game | View File | What Creates the "Map" Today | Variety? |
|---|---|---|---|
| Comet Clash | SnakeGameView.swift | Open `CGRect` arena; comets bounce off 4 outer walls | None |
| Sumo Survival | SumoSurvivalView.swift | Circular shrinking platform, no obstacles | None |
| Paint Ball | PaintBallView.swift | 6 pits randomly scattered via `scatterPits()` | Pseudo-random — no named layouts |
| Gold Rush | GoldRushView.swift | Open `CGRect` arena; no static objects | None |
| Marble Cup | MarbleCupView.swift | Fixed portrait pitch, fixed goal boxes | None |
| King of the Hill | KingOfTheHillView.swift | Open `CGRect` field; zone drifts freely | None |
| Pinball | PinballView.swift | 3 hardcoded bumpers at fixed fractional positions | None |

---

## Architecture

### New file: `RollAlong/MinigameMaps.swift`

All map definitions live here.  Views stay thin — they read a map by index and call `reset()`.

```swift
// ── Shared primitives ────────────────────────────────────────────────────────

/// Interior wall expressed as unit fractions of the arena/field rect.
struct WallSegFrac {
    let x1, y1, x2, y2: CGFloat   // 0.0–1.0 relative to field.width / field.height
}

/// Circular post or pillar at a fractional field position.
struct PillarFrac {
    let cx, cy: CGFloat   // 0.0–1.0 relative to field bounds
    let r: CGFloat        // radius in points (device-size invariant)
}

/// Pillar on a Sumo platform in polar coordinates relative to platform centre.
struct SumoPillar {
    let radFrac: CGFloat   // fraction of base platform radius
    let angle:   CGFloat   // radians from +x axis
    let r:       CGFloat   // radius in points
}
```

### Map cycling

Each view gains `@State private var mapIndex = 0`.  On "Play Again" the button increments `mapIndex` modulo the catalogue count, so players see every layout before repeating.  The map name is briefly shown in the HUD when a round starts.

```swift
// In the "Play Again" button action:
mapIndex = (mapIndex + 1) % SomeGame.maps.count
reset()
```

No persistence needed — `mapIndex` returns to 0 when the view is re-entered from Home.

---

## Per-Game Plans

### 1 · Pinball — 12 maps  *(S23)*

**What changes:** Replace the 3 hardcoded `CGPoint` bumpers with a `PinballMap` struct.  Flippers and the lane divider stay fixed.

```swift
struct PinballMap {
    let name: String
    let bumperFracs: [(CGFloat, CGFloat)]   // (xFrac, yFrac) within field
    let hasCenterPost: Bool                 // single post at (0.50, 0.60)
    let hasGuideRails: Bool                 // short walls at left/right at y ≈ 0.55
}
```

| # | Name | Bumpers | Extras | Notes |
|---|---|---|---|---|
| 1 | Classic | 3 (current positions) | — | Baseline |
| 2 | Diamond | 4 (diamond) | — | |
| 3 | Spread | 5 (wide fan) | — | |
| 4 | Cluster | 6 (tight centre) | — | |
| 5 | Cross | 4 (+ shape) | — | |
| 6 | Two Rows | 6 (3 + 3 rows) | — | |
| 7 | Zigzag | 5 (staggered cols) | — | |
| 8 | Centre Post | 3 | center post | Forces flanking shots |
| 9 | Railed | 3 | guide rails | Narrows lanes |
| 10 | Wide Ring | 6 (outer perimeter) | — | |
| 11 | Funnel | 4 (converging pairs) | — | Guides ball to centre |
| 12 | Chaos | 8 (scattered) | — | Hardest to predict |

**Physics needed:** None.  Bumpers already provide elastic reflection.

---

### 2 · Paint Ball — 10 maps  *(S23)*

**What changes:** Replace `scatterPits()` random placement with a `PaintBallMap` catalogue.  Pit radius and freeze logic are untouched.

```swift
struct PaintBallMap {
    let name: String
    // (xFrac, yFrac): yFrac ≥ 0.22 to stay below HUD; avoid centre spawn (0.5, 0.5)
    let pitFracs: [(CGFloat, CGFloat)]
}
```

| # | Name | Pit count | Layout | Notes |
|---|---|---|---|---|
| 1 | Cross | 5 | + shape, centre heavy | |
| 2 | Ring | 6 | Hexagonal ring | |
| 3 | Corners | 4 | One in each corner | Dangerous edges |
| 4 | Spine | 6 | Down the vertical centre | Bisects the arena |
| 5 | Twin Walls | 6 | 3+3 along left and right thirds | Wide centre highway |
| 6 | Scattered | 7 | Mimics current random feel (fixed) | Baseline |
| 7 | Cluster | 4 | Grouped centre-left | One safe open side |
| 8 | Diagonal | 5 | Diagonal band | |
| 9 | Honeycomb | 7 | Offset rows | Busiest map |
| 10 | Top & Bottom | 6 | Top and bottom thirds only | Long centre lane |

**Physics needed:** None.  Pit detection and freeze logic already work.

---

### 3 · Comet Clash — 8 maps  *(S24)*

**What changes:** Add optional interior walls.  Comets already bounce off the outer walls; internal `WallSegFrac` entries use the same reflection logic.

```swift
struct CometClashMap {
    let name: String
    let walls:     [WallSegFrac]   // interior wall segments
    let asteroids: [PillarFrac]    // static circular rocks
}
```

**New physics:** `resolveWallCollision(vel:pos:seg:arena:)` — converts `WallSegFrac` to screen coords, projects ball onto segment, pushes out along normal, reflects velocity component.

| # | Name | Walls | Asteroids | Notes |
|---|---|---|---|---|
| 1 | Open | None | None | Current layout |
| 2 | Asteroid Belt | None | 5 | Scattered rocks |
| 3 | Split | 1 centre horizontal (with gap) | None | Two-lane arena |
| 4 | Cross | H + V segments (with gaps) | None | Four quadrants |
| 5 | Rock Garden | None | 8 | Dense field |
| 6 | Corridor | 2 parallel vertical walls | None | Forces narrow path |
| 7 | Diamond | 4 angled segments forming diamond | None | Interior obstacle |
| 8 | Chaos | 3 angled walls + 3 rocks | — | Hardest |

---

### 4 · Gold Rush — 8 maps  *(S24)*

**What changes:** Add wall barriers to redirect marble movement and create coin-collecting zones.  Coins still spawn randomly inside open areas.

```swift
struct GoldRushMap {
    let name: String
    let walls: [WallSegFrac]
}
```

Reuses the **same wall collision engine** built for Comet Clash in S24.

| # | Name | Barriers | Notes |
|---|---|---|---|
| 1 | Open | None | Current layout |
| 2 | Lanes | 2 horizontal dividers (with gaps) | Creates 3 rows |
| 3 | Box | 4 walls forming open square | Centre collection pocket |
| 4 | Split | 1 vertical wall (gap top + bottom) | Two-room arena |
| 5 | Pinball | 3 angled walls | Bouncy chaos |
| 6 | Crossroads | H + V with gaps | Four-quadrant coins |
| 7 | Tight Corners | 4 short corner walls | Coins collect in nooks |
| 8 | Maze | 5 walls, partial maze | Hardest routing |

---

### 5 · Sumo Survival — 8 maps  *(S25)*

**What changes:** Add pillar obstacles on the platform.  Pillars create bottlenecks that force confrontation.  Pillar centres scale with `currentRadius` so they stay on the platform as the ring shrinks.

```swift
struct SumoMap {
    let name: String
    let pillars: [SumoPillar]   // polar coords, fraction of base platform radius
}
```

**New physics:** `resolvePillarCollision(ball:pillarPos:pillarR:)` — same circle-circle separation as marble-marble but the pillar has infinite mass (only the ball moves).  Screen coords: `pillarPos = centre + CGPoint(cos(angle), sin(angle)) × radFrac × currentRadius`.

| # | Name | Pillars | Notes |
|---|---|---|---|
| 1 | Open | None | Classic |
| 2 | Centre Post | 1 (dead centre) | Forces flanking |
| 3 | Triangle | 3 at 120° | Three lanes |
| 4 | Cross | 4 at 90°, mid-radius | Four sectors |
| 5 | Ring | 5 at 72°, outer zone | Wall of posts |
| 6 | Dual | 2 opposite at mid | Divides platform |
| 7 | Orbit | 6 at 60°, small posts | Dense inner ring |
| 8 | Star | 4 mid + 1 centre | Combined threat |

---

### 6 · King of the Hill — 8 maps  *(S25)*

**What changes:** Add static pillar obstacles to the rectangular field.  Pillars force routing so bots can't trivially beeline to the zone.  Zone continues to drift freely on all maps.

```swift
struct KOTHMap {
    let name: String
    let pillars: [PillarFrac]   // Cartesian, relative to field bounds
}
```

Reuses the **same pillar collision engine** built for Sumo Survival in S25.

| # | Name | Pillars | Notes |
|---|---|---|---|
| 1 | Open | None | Classic |
| 2 | Centre Post | 1 (field centre) | Zone zig-zags around it |
| 3 | Four Corners | 4 near corners | Pinches the field |
| 4 | Gauntlet | 4 in a horizontal line | North-south split |
| 5 | Maze Thirds | 6 in 2 staggered rows | Winding paths |
| 6 | Triangle | 3 in triangle | Three approach lanes |
| 7 | Dumbbell | 2 large pillars flanking centre | Forces play to the edges |
| 8 | Tight | 8 small pillars scattered | Densest map |

---

### 7 · Marble Cup — 8 maps  *(S26)*

**What changes:** Vary goal width and add post/deflector obstacles on the pitch.

```swift
struct MarbleCupMap {
    let name: String
    let goalWidthFrac: CGFloat            // overrides the `goalWidthFrac` tunable (default 0.42)
    let sidePosts: [(yFrac: CGFloat, side: Side)]  // posts pinned to left/right pitch walls
    let midBumpers: [PillarFrac]          // circular bumpers floating on the pitch
    enum Side { case left, right, both }
}
```

Posts and bumpers reuse the **pillar collision engine** from S25 applied to the rectangular `field` rect.

| # | Name | Goal width | Side posts | Mid bumpers | Notes |
|---|---|---|---|---|---|
| 1 | Standard | 0.42 | None | None | Current layout |
| 2 | Tight Goals | 0.30 | None | None | Precision required |
| 3 | Wide Open | 0.55 | None | None | Easier scoring |
| 4 | Side Posts | 0.42 | 4 (both sides) | None | Deflects long shots |
| 5 | Rebounder | 0.42 | None | 2 at midfield | Ball bounces wildly |
| 6 | Chaos Pit | 0.42 | 2 (one side) | 2 | Most chaotic |
| 7 | Funnel | 0.38 | 2 angled inward | None | Narrows attacking lane |
| 8 | Pro League | 0.34 | 4 (both sides) | 1 centre | Hardest map |

---

## Sprint Breakdown

| Sprint | Title | Scope | Maps added | New physics |
|---|---|---|---|---|
| **S23** | Map Data Layer | `MinigameMaps.swift` with shared primitives; Pinball 12 maps + Paint Ball 10 maps; `mapIndex` cycling; map-name HUD label | **22** | None |
| **S24** | Wall Segment Engine | `resolveWallCollision`; Comet Clash 8 maps + Gold Rush 8 maps | **16** | `WallSegFrac` reflection |
| **S25** | Pillar Engine | `resolvePillarCollision`; Sumo Survival 8 maps + King of the Hill 8 maps | **16** | Circle-circle (infinite mass) |
| **S26** | Marble Cup + Polish | Marble Cup 8 maps (extends pillar engine to pitch); map names on all 7 games; balance pass | **8** | Extends pillar engine |

**Total: 62 layouts across all 7 minigames in 4 sprints.**

---

## Implementation Notes

### Wall collision

```
WallSegFrac → screen coords: x1_px = wf.x1 × arena.width, etc.

1. Closest point P on segment to ball centre B
2. dist = |B − P|
3. If dist < marbleRadius:
   a. Push ball along normal: pos += normal × (marbleRadius − dist)
   b. Reflect vel component along normal: vel -= 2 × dot(vel, n) × n × wallBounce
```

### Pillar collision

```
PillarFrac → screen coords: cx_px = pf.cx × field.width, cy_px = pf.cy × field.height
SumoPillar → screen coords: cx_px = centre.x + cos(angle) × radFrac × currentRadius, etc.

1. dx/dy from ball centre to pillar centre
2. If hypot(dx, dy) < marbleRadius + pillar.r:
   a. Separate along normal (pillar has infinite mass — only ball moves)
   b. Reflect vel × restitution (match each view's existing restitution tunable)
```

Both helpers are `private static func` within their respective view file until S26 consolidation makes sharing worthwhile.

### Map name HUD label

A brief capsule appears at round start and fades after 2 seconds:

```swift
@State private var showMapName = true

// In reset():
showMapName = true

// In body overlay (above startPrompt):
if showMapName && started {
    Text(currentMap.name)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(Color(white: 0.7))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color(white: 0.14)))
        .transition(.opacity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showMapName = false }
            }
        }
}
```

### Coin / collectible spawn awareness

Maps with interior walls: `spawnCoin()` / `scatterPits()` must reject positions that land inside a wall's exclusion zone.  Add a `isBlocked(point:map:) -> Bool` helper in `MinigameMaps.swift` that each game calls during placement retry loops.

---

## Files Touched

| Sprint | Files Created | Files Modified |
|---|---|---|
| S23 | `MinigameMaps.swift` | `PinballView.swift`, `PaintBallView.swift` |
| S24 | — | `SnakeGameView.swift`, `GoldRushView.swift`, `MinigameMaps.swift` |
| S25 | — | `SumoSurvivalView.swift`, `KingOfTheHillView.swift`, `MinigameMaps.swift` |
| S26 | — | `MarbleCupView.swift`, `MinigameMaps.swift` |
