# AI calibration harness — feasibility, first measurements, procedure (2026-07)

Follow-up to the [06-sprint-plan](06-sprint-plan.md) AI-calibration track:
can we measure minigame win rates against the `targetWinRate` ladder
(**Easy 0.80 · Normal 0.45 · Hard 0.22**) *without* waiting for live
telemetry? **Verdict: yes — built and shipping in this branch**, for Gold
Rush (Smash and Grab). The harness is
`MinigameAICalibrationTests` in `RollAlongTests/GameStateTests.swift`
(appended to the existing file — no new pbxproj entries needed).

Read this doc before trusting or retuning anything off the harness numbers.

## 1. Architecture: what is headless today, and what isn't

Two patterns coexist across the six competitive modes.

### Pattern A — headless engine (Gold Rush only)

`RollAlong/GoldRushEngine.swift` is a plain non-Observable class:
`private(set)` state, a public `tick()` (line 235), a settable
`playerInput: CGVector`, and settable knobs `aiAccelScale` / `aiSpeedScale` /
`difficulty`. `GoldRushView.swift`'s per-frame driver (~line 596–604) does
nothing but set those four things from `BallMotion.gravity` +
`gameState.minigameDifficulty` and call `engine.tick()`.

Consequence: a test can run the **exact production AI + physics with zero
divergence** — `PerformanceTests.swift` already drives the engine this way
for benchmarks, and the calibration harness does the same for win rates.

### Pattern B — tick-on-the-View (everything else)

KotH (`KingOfTheHillView.swift:507`), Paint Ball (`PaintBallView.swift:620`),
Marble Cup (`MarbleCupView.swift:711`), Sumo (`SumoSurvivalView.swift:643`),
and Comet Clash (`SnakeGameView.swift`) run `tick()` as a **private method on
the SwiftUI View struct**, mutating `@State` arrays (racers / painters /
movers / bumpers, plus Paint Ball's grid/coverage) and reading
`motion.gravity` + `gameState.minigameDifficulty` inline. These four cannot
be simulated headlessly today.

The saving grace: the shared **`MinigameAI` humanizer
(`GameState.swift:1859`) is stateless and pure** — `weaveAngle` /
`humanizedSteer` take `(seed, tick, difficulty)` — so the AI *policy* is
already headless everywhere. What blocks headless runs in those four modes is
only that the physics/scoring state lives in View `@State`.

### Per-mode rival strength (for reference)

Each mode multiplies its `aiAccelBase` by `MinigameDifficulty.aiAccelScale`
(Easy 0.55 · Normal 0.78 · Hard 1.0):

| Mode | `aiAccelBase` | Where |
|---|---:|---|
| King of the Hill | 1,250 | `KingOfTheHillView.swift:34` |
| Comet Clash (snake) | 1,200 | `SnakeGameView.swift:61` |
| Gold Rush | 1,180 | `GoldRushEngine.swift:34` (as `aiAccel`) |
| Paint Ball | 1,150 | `PaintBallView.swift:34` |
| Marble Cup | 1,060 | `MarbleCupView.swift:37` |
| Sumo Survival | 900 | `SumoSurvivalView.swift:41` |

## 2. The harness

`MinigameAICalibrationTests` runs the production `GoldRushEngine.tick()`
against a scripted **median-skill player** (`MedianPlayer`): ~0.25 s reaction
latency, 75% tilt magnitude, ±0.30 rad aim error resampled per decision,
opportunistic-but-imperfect charge use. **n = 200 rounds per difficulty**,
cycling all shipped Gold Rush maps so no single layout dominates. It is split
into three per-difficulty tests (~20 s each — one 62 s monolith hit a
simulator crash/timeout) with **deliberately weak assertions** (difficulty
ordering + minimum easy-vs-hard spread) so it *measures* rather than gates.

Run it with:

```sh
xcodebuild test -only-testing:RollAlongTests/MinigameAICalibrationTests ...
```

and read the `[AI-CALIBRATION]` lines from the test log.

### Honesty caveat — by construction

- **REAL (zero divergence from the shipped game):** all rival AI
  (MinigameAI weave/hesitation, `aiAccelScale`, `aiSpeedScale`, bully
  charges), all physics, coins, spills, round timing. It *is* the shipped
  tick — better than any reimplemented simulation.
- **MODELED:** the player. Absolute win rates are only as trustworthy as
  `MedianPlayer`.

The harness is therefore valid for **difficulty spread**, **knob-sensitivity
deltas**, and **regression safety** — **not** as a substitute for telemetry
on absolutes. Do not retune the `MinigameDifficulty` tables off harness
absolutes alone.

## 3. First measurements (2026-07-02, iPhone 17 simulator)

| Cell | Simulated | Target | n | SE | Read |
|---|---:|---:|---:|---:|---|
| goldrush × easy | **0.835** | 0.80 | 200 | ≈0.026 | within noise of target |
| goldrush × normal | **0.540** | 0.45 | 200 | ≈0.035 | ~9 pts high |
| goldrush × hard | **0.540** | 0.22 | 200 | ≈0.035 | 2.5× target — and statistically indistinguishable from normal |

Runtime: 23.3 s + 21.2 s + 19.9 s ≈ 64 s suite total (each test individually
well under a 60 s budget).

### The red flag: normal == hard

The normal→hard knob step (`aiAccelScale` 0.78→1.0, `aiSpeedScale`
0.85→1.0, humanizer off) produced **zero win-rate separation** for a
fixed-skill player in Gold Rush. Plausible mechanism, worth investigating
before touching the tables:

1. On Hard the humanizer is fully off, so all three *surgical* rivals
   converge on the same nearest coin and interfere with each other —
   Normal's aim weave effectively de-collides their targeting.
2. Ties count as player wins in `GoldRushEngine.endRound()`
   (`GoldRushEngine.swift:541` — the player wins unless a rival strictly
   outscores them).

**Cross-check against live `minigame_result` telemetry before acting** (the
~2-weeks-post-launch recheck). If hard's live win rate is also well above
0.22 and close to normal's, widen the top of the knob tables for Gold Rush
(e.g. reduce hard rivals' effective `aiSpeedScale` handicap-removal or add a
Gold Rush-specific hard multiplier) and chase the cluster hypothesis in the
engine first.

## 4. Calibration procedure going forward

### Ground truth: telemetry (per [minigame-difficulty.md](../minigame-difficulty.md))

Every match already emits `minigame_result`
`{game, difficulty, won, base_payout, payout}`. The loop:

1. Aggregate win rate per game × difficulty cell — **act only on n ≥ 200**:

   ```sql
   SELECT properties->>'game'        AS g,
          properties->>'difficulty'  AS d,
          count(*)                   AS n,
          avg((properties->>'won')::boolean::int) AS win_rate
   FROM events
   WHERE name = 'minigame_result'
   GROUP BY 1, 2
   HAVING count(*) >= 200;
   ```

2. If a tier is off its `targetWinRate`, move that tier's `aiAccelScale` —
   the tables on `MinigameDifficulty` (`RollAlong/GameState.swift`) are the
   **single source of truth**.
3. Adjust `payoutMultiplier` only if the coin-EV shape drifts.
4. Edit only the tables, ship, repeat.

### Fast loop: harness re-runs (relative, not absolute)

Re-run `MinigameAICalibrationTests` after **any** change to the
`MinigameDifficulty` tables, `MinigameAI`, or `GoldRushEngine` tunables, and
compare **deltas** against the last recorded run. This is where the harness
beats telemetry: knob-sensitivity feedback in ~1 minute instead of ~2 weeks.
The built-in assertions only gate on ordering + spread collapse, so an
intentional retune won't fight the tests.

### Recommendation summary

1. **Do not** retune `aiAccelScale` off harness absolutes — the player model
   sets the level of the curve.
2. **Do** treat normal == hard as a real signal; confirm against telemetry,
   then fix in the engine/tables as above.
3. Telemetry (n ≥ 200 per cell) remains the tuning authority.
4. If headless calibration proves valuable, extract **KotH next** (~1
   session): its dynamics differ most from Gold Rush (contested-zone holding
   vs coin racing) and it has the simplest state (racers + zone).
5. Keep the harness green in CI as a spread/regression instrument.

## 5. Extending the harness: engine extraction per mode

Extraction is mechanical, not architectural. Each Pattern-B mode's tick
depends only on `motion.gravity`, `gameState.minigameDifficulty`, and
round-end side effects (GameState / analytics / haptics) that
`GoldRushEngine` already demonstrates how to leave to the host view.
`GoldRushView` + `GoldRushEngine` is the worked template.

Cost per mode: move the model structs + `tick()` + steer/collision/scoring
helpers (~300–450 lines) into an `XEngine` class, mirror the arrays into the
view once per tick, 1 new file = **4 manual `project.pbxproj` entries**
(explicit file refs, no synchronized group).

| Mode | Difficulty of extraction | Notes |
|---|---|---|
| King of the Hill | easiest | simplest state: racers + zone |
| Marble Cup | moderate | racers + cups |
| Sumo Survival | moderate | multi-round bookkeeping stays in the view |
| Paint Ball | hairiest | grid / coverage / paintTick arrays |
| Comet Clash | n/a for now | excluded from MinigameAI humanizer anyway |
