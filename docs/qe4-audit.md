# QE4 — General Audit

Codebase hygiene: magic-number extraction, deprecated API sweep, import
cleanup, asset catalogue audit, MARK consistency, and docs freshness.

---

## Why Now

Six sprints of feature work across 41 Swift files have left behind scattered
constants, inconsistent code organisation, and a few stale comments.  None of
these items are blockers individually, but collectively they slow future
contributors and create surface area for subtle bugs (e.g., duplicated
constants drifting out of sync).  A focused hygiene pass before distribution
locks in a clean baseline.

---

## Scope Overview

| Area | Priority | Effort |
|---|---|---|
| Magic number extraction | 🔴 High | Medium |
| Deprecated API sweep | 🔴 High | Small |
| Import hygiene | 🟡 Medium | Small |
| Asset catalogue audit | 🟡 Medium | Small |
| MARK section consistency | 🟡 Medium | Small |
| Docs freshness | 🟢 Low | Small |
| Dead code removal | 🟢 Low | Small |

---

## 1 · Magic Number Extraction

Constants duplicated across files are a maintenance hazard — one site gets
updated, the other doesn't.

### 1a — Shared layout constants

The following values appear in multiple views with no shared source of truth:

| Value | Likely intent | Appears in |
|---|---|---|
| `CGFloat = 124` (top reserve / HUD height) | `topReserve` safe-area offset | Multiple game views |
| `CGFloat = 44` (tap target minimum) | HIG minimum touch target | Various button frames |
| `CGFloat = 0.042` / similar small fracs | Ball/marble radius fractions | Multiple game views |
| `0.70` / `0.80` wall bounce coefficient | `wallBounce` | `SnakeGameView`, `GoldRushView` |
| `600` max trail nodes | `maxTrailNodes` | `SnakeGameView` |
| `30 * 86_400` review cooldown | 30-day interval | `GameState` |

**Implementation:** Create `RollAlong/Constants.swift` with namespaced enums:

```swift
enum Layout {
    static let topReserve:    CGFloat = 124
    static let minTapTarget:  CGFloat = 44
    static let hudHeight:     CGFloat = 56
}

enum Physics {
    static let wallBounce:     CGFloat = 0.75
    static let trailNodeCap:   Int     = 600
    static let ballRadiusFrac: CGFloat = 0.042
}

enum Timing {
    static let reviewCooldownDays: Double = 30
    static let reviewCooldownSecs: Double = reviewCooldownDays * 86_400
}
```

Then replace all literal occurrences with the named constant.  Run a
project-wide search for each value before and after to confirm coverage.

**Files:** `Constants.swift` (new), all game views that use these values

### 1b — Map geometry constants

Each map struct in `MinigameMaps.swift` uses inline fractional coordinates.
These are intentionally per-map literals and do **not** need extraction — the
inline form is the most readable representation of map layout data.  Leave
them as-is.

---

## 2 · Deprecated API Sweep

### 2a — SwiftUI modifiers

Audit all 41 Swift files for SwiftUI APIs that are deprecated on the
deployment target.  Key suspects:

| Deprecated API | Replacement | Notes |
|---|---|---|
| `.onChange(of:perform:)` (1-arg closure) | `.onChange(of:) { _, new in }` | Deprecated in iOS 17 |
| `NavigationView` | `NavigationStack` | Deprecated in iOS 16 |
| `StateObject` + `@main` patterns | Unchanged — fine | n/a |

Run:
```bash
xcodebuild -project RollAlong.xcodeproj -scheme RollAlong \
    -destination 'generic/platform=iOS' \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=NO 2>&1 | grep -i deprecat
```

Resolve every deprecation warning before the next submission.

### 2b — UIKit bridging

`SKStoreReviewController.requestReview(in:)` uses `UIApplication.shared
.connectedScenes` — valid on iOS 16+.  If the deployment target is iOS 15,
add an `#available(iOS 16, *)` guard (or raise the deployment target to 16).

### 2c — Deployment target alignment

Confirm `IPHONEOS_DEPLOYMENT_TARGET` in the project settings is consistent
with:
- The lowest iOS version advertised on the App Store listing.
- The `@available` guards actually present in the codebase.
- The SwiftUI features in use (e.g., `NavigationStack` requires iOS 16).

**Files:** All Swift files with deprecation warnings; `project.pbxproj` if
deployment target needs updating

---

## 3 · Import Hygiene

Unused `import` statements add noise and can mask name conflicts.

### Implementation

Run the following across all Swift files:
```bash
find RollAlong -name "*.swift" | xargs grep -l "^import " | sort
```

For each file, verify each imported module is actually used.  Common
unnecessary imports found in SwiftUI projects:
- `import UIKit` in files that only use SwiftUI
- `import Combine` in files that use `@Published` but no explicit `Combine`
  types (SwiftUI re-exports the necessary parts)
- `import Foundation` in files already importing `SwiftUI` (Foundation is
  transitively imported)

Remove unused imports.  The build should remain clean after each removal.

**Files:** All 41 Swift files (sweep, not a full rewrite)

---

## 4 · Asset Catalogue Audit

### 4a — Unused image assets

Run a reverse lookup: for every image in `Assets.xcassets`, confirm at least
one `Image("name")` or `UIImage(named: "name")` call references it:

```bash
# List all asset names
find RollAlong/Assets.xcassets -name "*.imageset" -exec basename {} .imageset \; | sort > /tmp/assets.txt

# List all image references in Swift files
grep -rh 'Image("\|UIImage(named:' RollAlong/ | grep -oE '"[^"]+"' | tr -d '"' | sort -u > /tmp/refs.txt

# Find assets with no reference
comm -23 /tmp/assets.txt /tmp/refs.txt
```

Delete assets with no code references.  Confirm the app still builds and
renders correctly.

### 4b — Duplicate / near-duplicate colours

If `Assets.xcassets` contains colour assets, audit for colours that appear
twice with slightly different names (e.g., `GoldYellow` and `YellowGold`).
Consolidate to a single name and update all call sites.

### 4c — App icon sizes

Confirm the app icon set has all required sizes for the submission target
(iOS 17+ needs a single 1024×1024 PDF/PNG in a universal icon slot;
older slot-based icons are deprecated).

**Files:** `RollAlong/Assets.xcassets/` (deletions only)

---

## 5 · MARK Section Consistency

All view files should follow a consistent internal structure so contributors
can navigate any file without reading it top to bottom.

### Target layout (per view file)

```swift
// MARK: - Types
// (nested structs, enums, type aliases used only in this file)

// MARK: - State
// (@State, @StateObject, @EnvironmentObject, @Binding properties)

// MARK: - Tunables
// (private let constants specific to this view)

// MARK: - Computed
// (computed properties)

// MARK: - Body
// (var body: some View)

// MARK: - Subviews
// (private var / func returning View)

// MARK: - Actions
// (private func that mutates state)

// MARK: - Physics / Game Logic
// (tick, collision, scoring helpers)

// MARK: - Lifecycle
// (onAppear, reset, loadMap)
```

### Implementation

Audit each of the 9 game view files and `GameState.swift`.  Add missing
`// MARK:` comments; do not move code between sections in this pass (that
is a refactor, not a hygiene fix) unless a section is clearly misplaced.

**Files:** `SnakeGameView.swift`, `GoldRushView.swift`, `SumoSurvivalView.swift`,
`KingOfTheHillView.swift`, `MarbleCupView.swift`, `PinballView.swift`,
`PaintBallView.swift`, `BallGameView.swift`, `GameState.swift`

---

## 6 · Docs Freshness

### 6a — MinigameMaps.swift header comment

The sprint status block at the top of `MinigameMaps.swift` should be updated
to reflect completed sprints:

```swift
// Sprint status:
// S22 (Pinball map variants)      ✅ Complete
// S23 (Paint Ball map variants)   ✅ Complete
// S24 (Comet Clash + Gold Rush)   ✅ Complete
// S25 (Sumo Survival + KOTH)      ✅ Complete
// S26 (Marble Cup)                ✅ Complete
// QE1–QE4 (operational hardening) 🔄 In progress
```

Confirm the current header matches reality and update if not.

### 6b — README / App Store copy review

If a `README.md` exists at the repo root, verify it still accurately describes
the current feature set (e.g., all 7 minigames, challenge track, cosmetics
shop).

### 6c — Inline TODO / FIXME sweep

A codebase-wide `grep -rn "TODO\|FIXME\|HACK\|XXX"` returned zero results —
the codebase is clean.  Verify this remains true after QE1–QE3 changes.

```bash
grep -rn "TODO\|FIXME\|HACK\|XXX" RollAlong/ --include="*.swift"
```

If any appear, either resolve them in this sprint or file them as future work
with a linked issue number so they are not invisible.

**Files:** `MinigameMaps.swift` (header comment), `README.md` if present

---

## 7 · Dead Code Removal

### 7a — Unreachable `switch` branches

After map variants were added, confirm no `default:` branches in game logic
were carrying silent no-ops that mask unhandled cases.  Prefer exhaustive
`switch` over `default` where the enum is under our control.

### 7b — Commented-out code blocks

Scan for multi-line `//`-commented blocks (not documentation comments) that
were left behind during iterative development:

```bash
grep -n "^    //" RollAlong/*.swift | grep -v "MARK:\|///\| -" | head -40
```

Review each hit; delete if the code is no longer relevant.  If it represents
an intentional future path, replace the comment with a `// TODO(#NNN):` note.

### 7c — Stale `@State` variables

After QE1 changes (scenePhase observers, analytics), audit each game view for
`@State` variables that are declared but never mutated (write-once at init).
These should be `let` constants or `private let` tunables instead.

**Files:** All game view Swift files

---

## Files Touched

| File | Change |
|---|---|
| `Constants.swift` (new) | Shared layout, physics, and timing constants |
| All game views (sweep) | Replace magic literals with `Constants.*` references |
| All Swift files (sweep) | Remove unused imports |
| All game view files | Add / align `// MARK:` section headers |
| `MinigameMaps.swift` | Update sprint status header comment |
| `RollAlong/Assets.xcassets/` | Delete unreferenced image assets |
| `project.pbxproj` | Confirm deployment target alignment |

---

## Acceptance Criteria

- [ ] `Constants.swift` exists; `topReserve`, `wallBounce`, `trailNodeCap`, and `reviewCooldownSecs` are referenced from it at all call sites
- [ ] Zero deprecation warnings in a clean build targeting the declared deployment target
- [ ] No unused `import` statements remain (verify with build-time unused-import warning or manual sweep)
- [ ] All unreferenced image assets removed from `Assets.xcassets`
- [ ] All 9 game view files and `GameState.swift` have the standard `// MARK:` section structure
- [ ] `MinigameMaps.swift` sprint status header is accurate
- [ ] `grep -rn "TODO\|FIXME" RollAlong/` returns zero results (or all results have linked issue numbers)
- [ ] No multi-line commented-out code blocks remain in game view files
