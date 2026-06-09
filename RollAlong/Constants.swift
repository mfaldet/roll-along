import CoreGraphics

// ===========================================================================
// Constants.swift — Shared named constants for Roll Along.
//
// Philosophy:
//   • Only values that genuinely appear in MULTIPLE files live here.
//   • Per-game tunable values (physics feel, speeds, radii) stay in each
//     view's own "Tunables" block — coupling them here would prevent
//     independent tuning of each minigame.
//   • Single-site constants (e.g. reviewCooldownSecs in GameState, maxTrail
//     Nodes in SnakeGameView) are left in place to avoid the overhead of a
//     cross-file hop for something with one call site.
//
// Add a constant here only when you confirm it appears in ≥ 2 files.
// ===========================================================================

// MARK: - Layout

enum Layout {
    /// Y-offset from the top of the screen reserved for the HUD bar (score,
    /// lives, timer, etc.) in tilt-arena minigames.  Arena and field rects
    /// start at this Y so marbles never spawn behind the HUD.
    ///
    /// Used by: GoldRushView, KingOfTheHillView.
    /// PinballView uses 120 pt (different layout) and keeps its own local constant.
    static let topReserve: CGFloat = 124

    /// Top inset for the floating map-name badge that fades in at round start.
    /// Positions it just below the HUD bar.
    ///
    /// Used by: GoldRushView (mapNameLabel), KingOfTheHillView (mapNameLabel).
    static let mapNameTopInset: CGFloat = 108
}

// MARK: - Timing

enum Timing {
    /// Minimum interval between App Store review prompts (30 days in seconds).
    /// Single call site: GameState.maybeRequestReview(after:).
    /// Defined here for discoverability — search for review throttling lands here.
    static let reviewCooldownSecs: Double = 30 * 86_400
}
