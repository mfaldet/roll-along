# QE1 — Operational Excellence

Hardening sprint: ratings prompt, analytics completeness, accessibility,
app-lifecycle correctness, and performance guardrails.

---

## Why Now

Feature development through S26 has built a deep, polished game.  This sprint
locks in the operational layer before wider distribution — ensuring the game
instructs itself well, surfaces at the right moments, degrades gracefully under
pressure, and is usable by everyone.

---

## Scope Overview

| Area | Priority | Effort |
|---|---|---|
| Ratings prompt (App Store growth) | 🔴 High | Small |
| Analytics completeness | 🔴 High | Small |
| App lifecycle hardening | 🟡 Medium | Small |
| Accessibility audit | 🟡 Medium | Medium |
| Performance guardrails | 🟡 Medium | Medium |
| Error-state UX | 🟢 Low | Small |

---

## 1 · Ratings Prompt

**Current state:** `SKStoreReviewController` is not used anywhere in the codebase.
The App Store listing has zero organic reviews.

**Implementation:**

Add a `RatingPrompter` helper to `GameState` that gates a single `requestReview`
call behind three conditions:
1. Player has cleared at least level 5 on the main climb.
2. Player just won a round (not lost) — positive emotional moment.
3. The prompt has not been shown in the last 30 days (tracked in `UserDefaults`).

```swift
// GameState.swift
func maybeRequestReview(after win: Bool) {
    guard win,
          highestLevel >= 5,
          Date().timeIntervalSince(lastReviewPromptDate ?? .distantPast) > 30 * 86_400
    else { return }
    lastReviewPromptDate = Date()
    DispatchQueue.main.async {
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
```

Call sites — add `gameState.maybeRequestReview(after: true)` in:
- `BallGameView.endLevel()` — after a 3-star clear
- `SnakeGameView.endRun(didWin:)` — when `didWin == true`
- `ChallengeTrackView` — after clearing level 10, 50, or 100

**Files:** `GameState.swift`, `BallGameView.swift`, `SnakeGameView.swift`,
`ChallengeTrackView.swift`

---

## 2 · Analytics Completeness

### 2a — Missing round-start events

All 7 minigame views fire a `*_round_over` event but **none fire a round-start
event**.  Without a start event, funnel drop-off (started but never finished)
is invisible.

Add a `*_round_started` track call at the top of `startRound()` (or at the
first `tick()` where `started` transitions to `true`) in each view:

| View | Event name | Key properties |
|---|---|---|
| `SnakeGameView` | `comet_round_started` | `map_name` |
| `GoldRushView` | `goldrush_round_started` | `map_name` |
| `SumoSurvivalView` | `sumo_round_started` | `map_name` |
| `KingOfTheHillView` | `koth_round_started` | `map_name` |
| `MarbleCupView` | `marblecup_match_started` | `map_name` |
| `PinballView` | `pinball_game_started` | `map_name` |
| `PaintBallView` | `paintball_round_started` | `map_name` |

### 2b — Map name missing from round-over events

The `*_round_over` events carry score/coin properties but not the map that was
played.  Add `"map_name"` to every existing round-over `properties` dict so
layout difficulty can be correlated with retention.

### 2c — Challenge Track missing level-start event

`BallGameView` fires `track_level_cleared` and `track_completed` but not
`track_level_started`.  Add it at the top of the level-start path in
`BallGameView` when `gameState.isInTrack` is true.

### 2d — Minigame entry not tracked

`HomeView` fires `onboarding_dismissed` but not `minigame_entered`.  Add a
`minigame_entered` event at the navigation call site in `HomeView` with a
`"game_mode"` property.

### Summary table

| Event | Status | Action |
|---|---|---|
| `comet_round_started` | ❌ Missing | Add to `SnakeGameView` |
| `goldrush_round_started` | ❌ Missing | Add to `GoldRushView` |
| `sumo_round_started` | ❌ Missing | Add to `SumoSurvivalView` |
| `koth_round_started` | ❌ Missing | Add to `KingOfTheHillView` |
| `marblecup_match_started` | ❌ Missing | Add to `MarbleCupView` |
| `pinball_game_started` | ❌ Missing | Add to `PinballView` |
| `paintball_round_started` | ❌ Missing | Add to `PaintBallView` |
| `map_name` property on `*_round_over` | ❌ Missing | Add to all 7 |
| `track_level_started` | ❌ Missing | Add to `BallGameView` |
| `minigame_entered` | ❌ Missing | Add to `HomeView` |
| `app_launch` | ✅ Present | `RollAlongApp.swift` |
| `level_complete` / `level_fail` | ✅ Present | `BallGameView` |
| `iap_purchased` / `iap_failed` | ✅ Present | `StoreKitManager` |
| `cosmetic_purchased` / `pack_purchased` | ✅ Present | `CosmeticShopView` |
| Ad lifecycle events | ✅ Present | `AdManager` |

---

## 3 · App Lifecycle Hardening

### 3a — Physics clock pause on background

`BallMotion` (motion sensor) and `PhysicsClock` (timer) should both pause when
the app enters the background and resume on foreground.  Unverified whether
this is currently wired — add an explicit `scenePhase` observer in each game
view if not already present:

```swift
@Environment(\.scenePhase) private var scenePhase
// In body:
.onChange(of: scenePhase) { _, phase in
    if phase == .background { clock.stop(); motion.stop() }
    else if phase == .active && started && !isOver { clock.start(); motion.start() }
}
```

Check all 7 minigame views and `BallGameView` for this pattern.

### 3b — GameState save on background

Verify that `GameState` calls its persistence layer (`.save()` or equivalent)
on `scenePhase == .background` so no progress is lost if the app is terminated
from the background.

### 3c — Arena size guard on rapid navigation

All game views have `guard arena.width > 0` at the top of `reset()`.  Audit
that `tick()` never fires before `arena` is set (race between `clock.start()`
in `.onAppear` and `GeometryReader` delivering its first size).  If the clock
starts first, a tick with `arena == .zero` runs silently; ensure the guard
covers this.

---

## 4 · Accessibility Audit

The codebase has ~45 accessibility annotations — a reasonable start.
The following passes are needed:

### 4a — Interactive element coverage

Audit every `Button`, `Slider`, and tappable `ZStack` across:
- `HomeView` — tap targets on the lives pill, game mode cards
- `CosmeticShopView` — item grid cells must have `.accessibilityLabel` with
  item name + price + owned/locked state
- `ChallengeTrackSelectView` — track cards with progress ring
- All game-over overlays — "Play Again" and "Home" buttons

### 4b — CoinIcon accessibility value

`CoinIcon` is used to display the player's balance.  It needs
`.accessibilityLabel("coins")` and `.accessibilityValue("\(count)")` at call
sites where it appears alongside a count.

### 4c — Minimum tap target enforcement

Any interactive element smaller than 44×44 pt should get
`.frame(minWidth: 44, minHeight: 44)` (or `.contentShape`) to meet HIG
guidelines.  Specifically check:
- Close (×) buttons in overlays (currently use `padding(10)` + 16pt icon ≈ 36pt total)
- Pinball and Paint Ball score cells

### 4d — Dynamic Type

Audit all custom font sizes set with `.font(.system(size: N))` that do not use
`relativeTo:`.  Sizes below 15 pt should use `relativeTo: .caption` at minimum
so text remains legible on Accessibility Extra Large.

### 4e — VoiceOver game descriptions

Add `.accessibilityLabel` to the `startPrompt` text block in each minigame so
VoiceOver users understand the rules before tapping to start.

---

## 5 · Performance Guardrails

### 5a — Trail-cap enforcement (Comet Clash)

`SnakeGameView` caps trail nodes at `maxTrailNodes = 600` per comet with 4
comets = up to 2 400 nodes.  The `resolveCollisions()` loop is O(comets ×
total_trail_nodes).  Verify the cap is enforced *before* the collision pass,
not after.  Current code prunes in step 3 of `tick()` and collides in step 4 —
order is correct; add a comment confirming this.

### 5b — Canvas redraw frequency

The `staticLayer` Canvas in `SnakeGameView` (walls + asteroids) is fully static
but redraws every frame because it lives inside the same `ZStack` driven by
`@State` changes.  Extract it into a separate `View` that only depends on
`walls` and `asteroids` so SwiftUI can skip redraws on unrelated state changes.
Same pattern applies to `pillarsLayer` in `KingOfTheHillView` and
`SumoSurvivalView`.

### 5c — GoldRush coin view redraws

`ForEach(coins) { coinView($0) }` redraws every coin every frame during the
`pop` animation because `localTick` is in `@State`.  Pin the pop to happen
only for the first 8 ticks post-spawn; after that the view should be stable.

### 5d — Pinball O(n²) bumper–marble check

Each tick in `PinballView` should be audited for pairwise distance checks.
The bumper count is at most 8; the check is cheap, but document it explicitly
so future map additions don't silently worsen this.

---

## 6 · Error-State UX

### 6a — StoreKit purchase failure messaging

When `iap_failed` fires, the user currently sees nothing.  Add a brief in-app
alert or toast in `StoreKitManager` (or via a published error state consumed by
`PurchaseSheets`) so the player knows the purchase didn't complete.

### 6b — GameState load failure

If `UserDefaults` returns a corrupt or missing value on first launch (device
restore, reset), `GameState` should initialise cleanly to level 1 / 0 coins
rather than crashing or showing stale data.  Add a guard/catch at the load
site.

---

## Files Touched

| File | Change |
|---|---|
| `GameState.swift` | Add `maybeRequestReview`, `lastReviewPromptDate`, background save guard |
| `BallGameView.swift` | Add `track_level_started`, ratings call after 3-star |
| `SnakeGameView.swift` | Add `comet_round_started`, `map_name` on over event, scenePhase guard, static-layer extract |
| `GoldRushView.swift` | Add `goldrush_round_started`, `map_name` on over event |
| `SumoSurvivalView.swift` | Add `sumo_round_started`, `map_name` on over event, scenePhase guard |
| `KingOfTheHillView.swift` | Add `koth_round_started`, `map_name` on over event, scenePhase guard |
| `MarbleCupView.swift` | Add `marblecup_match_started`, `map_name` on over event |
| `PinballView.swift` | Add `pinball_game_started`, `map_name` on over event |
| `PaintBallView.swift` | Add `paintball_round_started`, `map_name` on over event |
| `HomeView.swift` | Add `minigame_entered` event |
| `ChallengeTrackView.swift` | Add ratings call at levels 10 / 50 / 100 |
| `CosmeticShopView.swift` | Accessibility labels on item grid cells |
| `StoreKitManager.swift` | User-facing error state on `iap_failed` |
| `PurchaseSheets.swift` | Consume and display StoreKit error state |

---

## Acceptance Criteria

- [ ] `SKStoreReviewController.requestReview` fires on first win at level ≥ 5, never more than once per 30 days
- [ ] All 7 minigame views fire `*_round_started` with a `map_name` property
- [ ] All 7 minigame `*_round_over` events include `map_name`
- [ ] `track_level_started` and `minigame_entered` events exist
- [ ] `PhysicsClock` + `BallMotion` pause on `scenePhase == .background` in all game views
- [ ] Every `Button` in all overlays meets 44×44 pt tap target
- [ ] `CoinIcon` has `.accessibilityLabel` + `.accessibilityValue` at balance display sites
- [ ] Static Canvas layers (walls, pillars) do not redraw on unrelated `@State` changes
- [ ] Purchase failure shows user-visible feedback
