# Roll Along

A tilt-driven iOS marble game for the App Store. Tilt the device to roll your marble through 100 climb levels and 7 competitive minigames, collect cosmetics, and compete on leaderboards.

**Platform:** iOS 18+ · **Language:** Swift / SwiftUI · **Physics:** CoreMotion + custom tick engine

---

## Features

### Climb mode
100 procedurally-laid-out levels with increasing difficulty. Each level places the marble at the top (or bottom) of the arena and scores on time and stars. Lives regenerate over time or can be refilled via IAP.

### 7 Competitive minigames
| Mode | Mechanic |
|---|---|
| Comet Clash | Tron light-cycle — tilt to leave a fading trail; outlast AI rivals |
| Gold Rush | Collect the most coins against AI racers in a timed round |
| Sumo Survival | Knock rivals off a shrinking ring |
| King of the Hill | Hold the moving zone longer than any rival |
| Marble Cup | Tilt-soccer — knock the ball into the opponent's goal |
| Pinball | Tap-flipper pinball with 12 map layouts |
| Paint Ball | Cover the most arena surface in your colour |

### Challenge Tracks
8 handcrafted skill tracks (Beginner → Elite → Legendary), each with 100 levels and exclusive cosmetic rewards on completion.

### Cosmetics shop
Ball skins, goal skins, trail colours, floor themes, pit styles, and music tracks — earnable with in-game coins, won from challenge tracks, or purchased as seasonal/IAP bundles. All 52 ball skins are drawn by a single Canvas renderer (`BallSkinView`) so a skin looks identical everywhere; several are animated. See [`docs/cosmetics-rendering.md`](docs/cosmetics-rendering.md).

### Social
Clans, friends, global leaderboards via Supabase backend.

---

## Project layout

```
RollAlong/
├── RollAlongApp.swift          ← app entry point + scene-lifecycle handler
├── ContentView.swift           ← thin shell wrapping HomeView
├── HomeView.swift              ← routing hub (climb, minigames, shop, profile)
├── BallGameView.swift          ← climb engine + physics + rendering (~4 000 lines)
├── GameState.swift             ← all persisted player state + IAP rewards
├── StoreKitManager.swift       ← StoreKit 2 purchase + restore flow
├── Constants.swift             ← shared Layout / Timing constants
├── MinigameMaps.swift          ← static map data for all 7 minigames
├── [Mode]View.swift            ← one file per minigame (7 files)
├── LevelLayout.swift           ← procedural level generator
├── Cosmetics.swift             ← cosmetic catalogue (skins, goals, trails, …)
├── BallSkin.swift / BallSkinView.swift  ← skin enum + Canvas renderers
└── Assets.xcassets/            ← app icon + accent colour (all art is Canvas)
```

---

## Running locally

Open `RollAlong.xcodeproj` in Xcode 16+ and run on a **physical device** — `CMMotionManager` does not report device motion in the simulator. An iOS 18+ device is required (the rich ball skins use SwiftUI `MeshGradient`).

For IAP testing, select the `Products.storekit` configuration under the scheme's **Run → Options → StoreKit Configuration**.

---

## Architecture notes

- **Physics clock:** `PhysicsClock` (CADisplayLink-backed, 60 fps) drives all minigames via `onReceive(clock.$tickCount)`. Paused automatically on `scenePhase == .background`.
- **Motion:** `BallMotion` wraps `CMMotionManager`, publishes a 2D gravity vector at 60 Hz with a ~3° deadband.
- **Canvas rendering:** All game art (marbles, trails, arenas, cosmetics) is drawn with SwiftUI `Canvas` — no image assets.
- **One ball renderer:** every ball is drawn by `BallSkinView` (exhaustive `switch` over `BallSkin`, no `default`), so a skin is pixel-identical across home, launch, shop, and gameplay. Animated skins use `TimelineView` and honour Reduce Motion.
- **Persistence:** All player state persists in `UserDefaults` via `@Published` `didSet` observers in `GameState`. JSON-encoded for complex types (`[Int: Int]`, sets).
- **Analytics:** `AnalyticsClient` batches events and flushes on background transition.

---

## Documentation

- [`CHANGELOG.md`](CHANGELOG.md) — notable changes, newest first.
- [`docs/cosmetics-rendering.md`](docs/cosmetics-rendering.md) — ball-skin system + how to add a skin.
- [`docs/gold-rush-economy.md`](docs/gold-rush-economy.md) — Gold Rush ticket economy + the ×2 boost.
- [`docs/AppStore.md`](docs/AppStore.md), [`docs/TestFlight.md`](docs/TestFlight.md) — release/distribution.
- [`docs/research/`](docs/research) — market teardown, roadmap, soft-launch plan.

---

## License

Personal project — all rights reserved.
