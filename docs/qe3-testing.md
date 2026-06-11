# QE3 — Test Coverage

Bootstrap the XCTest target, establish unit coverage for core logic, add
snapshot tests for cosmetics rendering, and wire up a basic UI smoke test.

---

## Why Now

The codebase has no test target.  Every sprint so far has shipped without a
safety net: physics changes, coin math, and cosmetics logic are all verified
by eye.  Before wider distribution — and before any future contributor touches
`GameState.addCoins` or the wall-collision solver — a minimal test suite must
exist so regressions surface before they reach the App Store.

---

## Scope Overview

| Area | Priority | Effort |
|---|---|---|
| XCTest target bootstrap | 🔴 High | Small |
| GameState unit tests | 🔴 High | Small |
| Physics helpers unit tests | 🔴 High | Medium |
| Cosmetics / skin catalogue tests | 🟡 Medium | Small |
| Snapshot tests (ball skins) | 🟡 Medium | Small |
| UI smoke test (home → game → home) | 🟡 Medium | Medium |
| Performance baseline (tick loop) | 🟢 Low | Small |

---

## 1 · XCTest Target Bootstrap

### Current state

No `*Tests*` directory or test target exists anywhere in the repository.  The
Xcode project file has a single target: `RollAlong`.

### Implementation

1. In Xcode: **File → New → Target → Unit Testing Bundle**.
   - Product name: `RollAlongTests`
   - Host application: `RollAlong`
2. Add a second target for UI tests: **UI Testing Bundle**, product name
   `RollAlongUITests`.
3. Confirm both targets build with no errors before writing any tests.
4. Add a `tests/` directory at the repo root (or `RollAlongTests/` inside the
   Xcode project folder, following the existing layout) and move the generated
   test stubs there.
5. Ensure `@testable import RollAlong` compiles — `GameState` and all helpers
   must have `internal` (default) or `public` access; no `private` barriers
   on the types being tested.

**Files:** `RollAlong.xcodeproj/project.pbxproj`, `RollAlongTests/` (new),
`RollAlongUITests/` (new)

---

## 2 · GameState Unit Tests

`GameState` is the single most critical class: it owns player progression,
coin balance, and cosmetic ownership.  Bugs here have direct revenue and
retention impact.

### 2a — Coin math

```swift
func testAddCoins_positiveAmount_increasesBalance() {
    let gs = GameState()
    gs.coins = 100
    gs.addCoins(50)
    XCTAssertEqual(gs.coins, 150)
}

func testAddCoins_exceedsCeiling_clampsToMax() {
    let gs = GameState()
    gs.coins = 999_990
    gs.addCoins(50)
    XCTAssertEqual(gs.coins, 999_999)
}

func testAddCoins_zeroAmount_noChange() {
    let gs = GameState()
    gs.coins = 200
    gs.addCoins(0)
    XCTAssertEqual(gs.coins, 200)
}

func testSpendCoins_sufficientBalance_deducts() {
    let gs = GameState()
    gs.coins = 500
    let success = gs.spendCoins(200)
    XCTAssertTrue(success)
    XCTAssertEqual(gs.coins, 300)
}

func testSpendCoins_insufficientBalance_returnsFalse() {
    let gs = GameState()
    gs.coins = 100
    let success = gs.spendCoins(200)
    XCTAssertFalse(success)
    XCTAssertEqual(gs.coins, 100)  // balance unchanged
}
```

### 2b — Track progression

```swift
func testAdvanceTrackProgress_clearsLevel_incrementsLevel() {
    let gs = GameState()
    gs.trackLevel = 3
    gs.advanceTrackProgress()
    XCTAssertEqual(gs.trackLevel, 4)
}

func testDeliverTrackReward_grantsCoins() {
    let gs = GameState()
    let before = gs.coins
    gs.deliverTrackReward(forLevel: 1)
    XCTAssertGreaterThan(gs.coins, before)
}
```

### 2c — Difficulty tier boundaries

The difficulty tiers defined in `GameState` (or wherever `difficultyFor(level:)`
lives) must have exact boundary tests:

```swift
func testDifficultyTier_level1_isEasy() {
    XCTAssertEqual(GameState.difficultyFor(level: 1), .easy)
}

func testDifficultyTier_boundaryLevel_correctTier() {
    // Replace N with the actual tier-boundary constant
    XCTAssertEqual(GameState.difficultyFor(level: N),     .medium)
    XCTAssertEqual(GameState.difficultyFor(level: N - 1), .easy)
}
```

### 2d — Review prompt gating

```swift
func testMaybeRequestReview_belowLevel5_doesNotFire() {
    let gs = GameState()
    gs.highestLevel = 4
    gs.lastReviewPromptDate = nil
    // Capture whether requestReview would be called via a mock or flag
    gs.maybeRequestReview(after: true)
    // Assert the prompt was NOT triggered (check lastReviewPromptDate == nil)
    XCTAssertNil(gs.lastReviewPromptDate)
}

func testMaybeRequestReview_recentPrompt_doesNotFire() {
    let gs = GameState()
    gs.highestLevel = 10
    gs.lastReviewPromptDate = Date()  // just shown
    gs.maybeRequestReview(after: true)
    // Date should be unchanged (no update)
    XCTAssertTrue(abs(gs.lastReviewPromptDate!.timeIntervalSinceNow) < 1)
}
```

**Files:** `RollAlongTests/GameStateTests.swift` (new)

---

## 3 · Physics Helper Unit Tests

Physics correctness is currently only verified by playing the game.  Three
helpers are high-value test targets.

### 3a — Wall collision push-out

The `resolveWallCollision` helper (used in `SnakeGameView` and `GoldRushView`)
projects a point onto a segment and pushes out.  Test with known geometry:

```swift
func testResolveWallCollision_ballCentreOnSegment_pushesOut() {
    // Horizontal wall at y = 0.5 (fractional)
    let seg = WallSegFrac(x1: 0.2, y1: 0.5, x2: 0.8, y2: 0.5)
    var cycle = Cycle(pos: CGPoint(x: 0.5 * 400, y: 0.5 * 800 - 5), vel: CGVector(dx: 0, dy: 3))
    let arena = CGSize(width: 400, height: 800)
    resolveWallCollision(&cycle, seg: seg, arena: arena, headRadius: 10, wallBounce: 0.9)
    // Ball should be pushed above the wall
    XCTAssertLessThan(cycle.pos.y, 0.5 * 800 - 10 + 0.1)
    // Vertical velocity should be reflected (now negative)
    XCTAssertLessThan(cycle.vel.dy, 0)
}

func testResolveWallCollision_ballFarFromSegment_noChange() {
    let seg = WallSegFrac(x1: 0.0, y1: 0.0, x2: 1.0, y2: 0.0)  // top edge
    var cycle = Cycle(pos: CGPoint(x: 200, y: 400), vel: CGVector(dx: 1, dy: 1))
    let before = cycle.pos
    resolveWallCollision(&cycle, seg: seg, arena: CGSize(width: 400, height: 800),
                         headRadius: 10, wallBounce: 0.9)
    XCTAssertEqual(cycle.pos.x, before.x)
    XCTAssertEqual(cycle.pos.y, before.y)
}
```

Note: `resolveWallCollision` is currently a private function in
`SnakeGameView`.  To test it, either:
- Extract it to a `PhysicsHelpers.swift` file (preferred — also solves
  code-duplication between Snake and GoldRush), or
- Mark it `internal` in the view and access via `@testable import`.

### 3b — Edge clamping (`bounceWalls`)

```swift
func testBounceWalls_ballAtLeftEdge_reflectsAndClamps() {
    var pos = CGPoint(x: -5, y: 100)
    var vel = CGVector(dx: -3, dy: 0)
    bounceWalls(pos: &pos, vel: &vel, radius: 10, arena: CGSize(width: 400, height: 800))
    XCTAssertGreaterThanOrEqual(pos.x, 10)
    XCTAssertGreaterThan(vel.dx, 0)
}
```

### 3c — Pillar collision

```swift
func testResolvePillarCollision_overlappingBall_pushesOut() {
    // Pillar at (200, 400), radius 15; ball centre at (205, 400), radius 10
    var pos = CGPoint(x: 205, y: 400)
    var vel = CGVector(dx: -2, dy: 0)
    let pillarCentre = CGPoint(x: 200, y: 400)
    resolvePillarCollision(pos: &pos, vel: &vel, pillarCentre: pillarCentre,
                           pillarRadius: 15, ballRadius: 10, restitution: 0.8)
    XCTAssertGreaterThanOrEqual(pos.x - 200, 25 - 0.1)  // pushed to at least combined radii
    XCTAssertGreaterThan(vel.dx, 0)  // reflected away
}
```

**Files:** `PhysicsHelpers.swift` (new, extracted from game views),
`RollAlongTests/PhysicsHelpersTests.swift` (new)

---

## 4 · Cosmetics Catalogue Tests

### 4a — All BallSkin cases have gradient definitions

```swift
func testAllBallSkins_haveGradients() {
    for skin in BallSkin.allCases {
        let gradient = skin.gradient
        XCTAssertFalse(gradient.stops.isEmpty,
                       "BallSkin.\(skin) has no gradient stops")
    }
}
```

### 4b — Bundle IDs resolve to known skins

```swift
func testAllBundleSkins_areValidBallSkins() {
    for bundle in CosmeticBundle.allCases {
        for skinID in bundle.skinIDs {
            XCTAssertNotNil(BallSkin(rawValue: skinID),
                            "Bundle \(bundle) references unknown skin '\(skinID)'")
        }
    }
}
```

### 4c — isBundleExclusive is consistent

```swift
func testBundleExclusiveSkins_notInGeneralCatalogue() {
    let bundleExclusive = BallSkin.allCases.filter { $0.isBundleExclusive }
    let generalCatalogue = CosmeticShopItem.allGeneralItems.map { $0.skin }
    for skin in bundleExclusive {
        XCTAssertFalse(generalCatalogue.contains(skin),
                       "Bundle-exclusive skin \(skin) appears in general catalogue")
    }
}
```

**Files:** `RollAlongTests/CosmeticsTests.swift` (new)

---

## 5 · Snapshot Tests (Ball Skins)

Visual regression tests catch unintended colour or gradient changes to skins.

### Implementation

Use [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
(add via Swift Package Manager):

```swift
import SnapshotTesting

class BallSkinSnapshotTests: XCTestCase {
    func testBallSkin_renders_matchesSnapshot() {
        for skin in BallSkin.allCases {
            let view = BallSkinView(skin: skin)
                .frame(width: 60, height: 60)
            assertSnapshot(matching: view, as: .image, named: skin.rawValue)
        }
    }
}
```

**First run** generates reference images in
`RollAlongTests/__Snapshots__/BallSkinSnapshotTests/`.  Commit these alongside
the tests.  Future runs fail if a skin changes unexpectedly.

> **Note:** Snapshot tests are device/OS-specific.  Pin them to a single
> simulator (e.g., iPhone 16 Pro, iOS 18) and document this in the test target
> scheme's environment.

**Files:** `Package.swift` (add swift-snapshot-testing),
`RollAlongTests/BallSkinSnapshotTests.swift` (new),
`RollAlongTests/__Snapshots__/` (generated)

---

## 6 · UI Smoke Test

A single end-to-end test that navigates from the home screen into a minigame,
triggers game-over, and returns home.  This catches navigation regressions —
the most visible class of production bugs.

### Implementation

```swift
class SmokeTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--skip-onboarding"]
        app.launch()
    }

    func testHomeToGoldRushAndBack() throws {
        // 1. Home screen is visible
        XCTAssertTrue(app.otherElements["HomeView"].waitForExistence(timeout: 5))

        // 2. Navigate into Gold Rush
        app.buttons["GoldRush"].tap()
        XCTAssertTrue(app.otherElements["GoldRushView"].waitForExistence(timeout: 5))

        // 3. Wait for game-over overlay (inject a --instant-gameover flag or
        //    wait the minimum round duration)
        XCTAssertTrue(app.buttons["PlayAgain"].waitForExistence(timeout: 30))

        // 4. Tap Home
        app.buttons["HomeButton"].tap()
        XCTAssertTrue(app.otherElements["HomeView"].waitForExistence(timeout: 5))
    }
}
```

**Prerequisites:**

- Add `--skip-onboarding` launch argument handling in `RollAlongApp.swift` to
  bypass the onboarding flow in UI tests.
- Add `accessibilityIdentifier` strings to `HomeView`, `GoldRushView`,
  "Play Again", and "Home" buttons — these identifiers can serve double duty
  as accessibility labels.

**Files:** `RollAlongUITests/SmokeTests.swift` (new),
`RollAlongApp.swift` (launch argument handler),
`HomeView.swift`, `GoldRushView.swift` (accessibilityIdentifier additions)

---

## 7 · Performance Baseline

A `measure` block ensures the physics tick loop stays under 16 ms (60 fps
budget) even as map complexity grows.

```swift
func testGoldRushTick_performance() {
    let view = GoldRushViewModel(arena: CGSize(width: 390, height: 844))
    view.loadMap(index: 0)
    view.startRound()
    measure {
        for _ in 0..<60 { view.tick() }  // 1 second at 60 fps
    }
}
```

> `measure` defaults to 10 iterations and reports the mean + standard
> deviation.  Establish a baseline on first run, then add
> `self.measureMetrics([.wallClockTime], automaticallyStartMeasuring: true)`
> with a `maxStandardDeviations` budget if the CI environment is stable enough.

Note: this test requires extracting tick logic from `@State` view structs into
a `ViewModel` or `Engine` class.  If extraction is out of scope for QE3,
document this as a prerequisite for a future refactor sprint.

**Files:** `RollAlongTests/PerformanceTests.swift` (new)

---

## Files Touched

| File | Change |
|---|---|
| `RollAlong.xcodeproj/project.pbxproj` | Add `RollAlongTests` and `RollAlongUITests` targets |
| `Package.swift` | Add swift-snapshot-testing dependency |
| `PhysicsHelpers.swift` (new) | Extract `resolveWallCollision`, `bounceWalls`, `resolvePillarCollision` from game views |
| `RollAlongApp.swift` | Handle `--skip-onboarding` launch argument |
| `HomeView.swift` | Add `accessibilityIdentifier` to root view and navigation buttons |
| `GoldRushView.swift` | Add `accessibilityIdentifier` to root view |
| `RollAlongTests/GameStateTests.swift` (new) | Coin math, track progression, difficulty tiers, review prompt gating |
| `RollAlongTests/PhysicsHelpersTests.swift` (new) | Wall collision, edge clamping, pillar collision |
| `RollAlongTests/CosmeticsTests.swift` (new) | Gradient coverage, bundle ID resolution, isBundleExclusive consistency |
| `RollAlongTests/BallSkinSnapshotTests.swift` (new) | Visual regression for all ball skins |
| `RollAlongUITests/SmokeTests.swift` (new) | Home → minigame → game-over → home |
| `RollAlongTests/PerformanceTests.swift` (new) | Tick loop 60-frame measure block |

---

## Acceptance Criteria

- [ ] `RollAlongTests` target builds and all unit tests pass with `⌘ U`
- [ ] `GameState` coin math tests cover: add, add-at-ceiling, spend-success, spend-fail
- [ ] `GameState` review prompt tests confirm prompt does not fire below level 5 or within 30 days
- [ ] Physics wall-collision test confirms push-out direction is correct for a known configuration
- [ ] All `BallSkin.allCases` have non-empty gradient definitions
- [ ] All bundle skin IDs resolve to valid `BallSkin` raw values
- [ ] Snapshot references committed for all ball skins; re-run passes without regeneration
- [ ] UI smoke test navigates home → Gold Rush → game-over → home without error
- [ ] Performance baseline recorded; 60-tick loop completes within 16 ms mean on reference device
