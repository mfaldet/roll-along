import SwiftUI

// ===========================================================================
// GameMode — the seam that lets Roll Along grow many games from one engine.
//
// CORE IDEA
//   Every experience Roll Along ships — the main climb, themed challenge
//   tracks, Zen Garden, the Coin Pit reward, competitive modes like Snake or
//   Bumper Cars — is the SAME tilt-physics ball-in-an-arena engine wearing a
//   different costume.  They differ only in a handful of rules:
//
//     • how the ball is controlled        → `ControlScheme`
//     • what counts as winning             → `GoalKind`
//     • what falling / failing does        → `FailKind`
//     • whether it feeds a progress counter→ `ProgressionKind`
//     • how the lives economy applies      → `LivesPolicy`
//     • which HUD elements show            → `showsStars` / `showsTimer` / …
//
//   A `GameMode` bundles those rules.  The engine (today fused into
//   BallGameView) reads the active mode and behaves accordingly, instead of
//   hard-coding "the climb."  Adding a new game becomes: write one struct,
//   flag it on in `GameModeCatalogue`.
//
// WHY THIS SHAPE
//   This is the "resiliently planned to dynamically evolve" foundation.  By
//   describing the climb AND every planned mode against one protocol up front,
//   we prove the abstraction holds before building any of them, and the modes
//   become A/B-testable, feature-flaggable content — measured by the existing
//   AnalyticsClient — so we can find the modes players actually enjoy.
//
// SAFE BY CONSTRUCTION
//   This file only DEFINES types.  It edits nothing else, so it cannot change
//   current behavior.  Wiring BallGameView to consult the active mode happens
//   later, in small behavior-preserving steps.
// ===========================================================================

// MARK: - Mode rule axes

/// How the player controls the ball.
enum ControlScheme: String, Codable {
    /// Standard Roll Along: device tilt → acceleration.
    case tiltAccel
    /// Scripted/magnetic path drives the ball; tilt is disabled.  Used by the
    /// Zen Garden magnet-track tool and any "watch it paint" passive demo.
    case magnetTrack
    /// No player control at all (results screens, cutscenes).
    case disabled
}

/// What ends a mode in success.
enum GoalKind: Equatable, Codable {
    /// Touch the goal marker — the climb and challenge tracks.
    case reachGoal
    /// Gather N collectibles — the Coin Pit (up to 100 falling coins).
    case collectCount(Int)
    /// Stay alive / keep going for a fixed time — survival rounds.
    case survive(TimeInterval)
    /// Highest score wins; no fixed end beyond the mode's own rules —
    /// competitive modes like Snake or Bumper Cars.
    case score
    /// Never ends; the player leaves when they choose — Zen Garden.
    case endless
}

/// What happens when the ball falls in a hole / the player fails.
enum FailKind: String, Codable {
    /// Costs a life and restarts the attempt — the climb.
    case loseLifeAndRetry
    /// The run is over; show the score/result — competitive modes.
    case endRun
    /// Nothing: no hazards, or hazards don't penalise — Zen, Coin Pit.
    case none
}

/// How a mode feeds the player's progression counters.
///
/// IMPORTANT: only `.mainClimb` moves the headline number shown next to the
/// player's name on leaderboards and in clans.  Everything else keeps its own
/// separate counter so a relaxer (Zen) and a grinder (climb) each have a
/// meaningful number without one polluting the other.
enum ProgressionKind: Equatable, Codable {
    /// Advances `playerLevel` — the canonical, server-synced headline number.
    case mainClimb
    /// A self-contained themed track (e.g. the 100-level "Frosty Challenge"),
    /// keyed by id, with its own 1…100 counter and a cosmetic reward at the end.
    case challengeTrack(String)
    /// Complete once per occurrence — the Daily Challenge.
    case oneShot
    /// No progression — Zen, Coin Pit, casual competitive play.
    case none
}

/// How the lives economy applies to a mode.
enum LivesPolicy: String, Codable {
    /// Each attempt consumes a life (the climb).
    case consume
    /// Lives are ignored — Zen, reward windows, the Coin Pit.
    case unlimited
}

// MARK: - GameMode protocol

/// A self-contained game mode: a strategy layered on the shared physics engine.
///
/// Conformers are tiny value types — pure configuration.  The engine asks the
/// active mode these questions each frame / at each decision point.
protocol GameMode {
    /// Stable identifier — also the analytics key and the remote-config flag.
    var id: String { get }
    /// Player-facing name.
    var displayName: String { get }
    /// One-line pitch for the mode-select UI.
    var tagline: String { get }

    var control:     ControlScheme  { get }
    var goal:        GoalKind       { get }
    var onFail:      FailKind       { get }
    var progression: ProgressionKind { get }
    var lives:       LivesPolicy    { get }

    /// Whether the arena contains fall-hazards (holes/pits) at all.
    var hasHoles:    Bool { get }

    // HUD composition — which overlays the mode shows.
    var showsStars:  Bool { get }
    var showsTimer:  Bool { get }
    var showsScore:  Bool { get }
}

// Sensible defaults so each mode struct only states what makes it distinct.
extension GameMode {
    var tagline:     String { "" }
    var showsStars:  Bool   { false }
    var showsTimer:  Bool   { false }
    var showsScore:  Bool   { false }
}

// MARK: - The main climb (today's game, expressed as a mode)

/// The never-ending level climb — Roll Along's spine and the only mode that
/// advances the headline `playerLevel`.  This encodes exactly how the game
/// behaves today; wiring BallGameView to read it changes nothing.
struct ClimbMode: GameMode {
    let id          = "climb"
    let displayName = "Adventure"
    let tagline     = "Climb the endless tower, one level at a time."
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .reachGoal
    let onFail:      FailKind        = .loseLifeAndRetry
    let progression: ProgressionKind = .mainClimb
    let lives:       LivesPolicy     = .consume
    let hasHoles                     = true
    let showsStars                   = true
    let showsTimer                   = true
    let showsScore                   = false
}

// MARK: - Blueprint modes (defined now to prove the protocol; gated off)
//
// These are real conformers, not stubs — they demonstrate the abstraction
// already describes the full vision.  They ship disabled in the catalogue
// until each is actually built out (arena setup + per-tick rules live in the
// engine layer, added per-mode later).

/// A themed 100-level side quest (e.g. "Frosty Challenge").  Plays like the
/// climb but on its own self-contained track, assembling a cosmetic as you go
/// (a piece every 10 levels) and awarding a bundle at level 100.
struct ChallengeTrackMode: GameMode {
    let trackID: String
    let displayName: String
    let tagline: String

    var id: String { "challenge.\(trackID)" }
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .reachGoal
    let onFail:      FailKind        = .loseLifeAndRetry
    var progression: ProgressionKind { .challengeTrack(trackID) }
    let lives:       LivesPolicy     = .consume
    let hasHoles                     = true
    let showsStars                   = true
    let showsTimer                   = true
}

/// Zen Garden — a metallic marble on an unbounded sand field.  No goal, no
/// holes, no lives, no progression: just the ASMR of the trail carved in sand,
/// plus tools (rake to re-smooth, magnet-track to auto-paint patterns).
struct ZenGardenMode: GameMode {
    let id          = "zen"
    let displayName = "Zen Garden"
    let tagline     = "No goal. No pressure. Just sand and a slow, perfect line."
    let control:     ControlScheme   = .tiltAccel   // magnet-track tool flips this to .magnetTrack at runtime
    let goal:        GoalKind        = .endless
    let onFail:      FailKind        = .none
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = false
}

/// Coin Pit — the 30-second reward mini-game.  Roll to gather up to 100 coins
/// raining down the screen.  No hazards, no lives; a pure payout round.
struct CoinPitMode: GameMode {
    let id          = "coinpit"
    let displayName = "Coin Pit"
    let tagline     = "Thirty seconds. Up to a hundred coins. Go."
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .collectCount(100)
    let onFail:      FailKind        = .none
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = false
    let showsTimer                   = true
    let showsScore                   = true
}

/// Snake — competitive twist: tilt-steer a growing tail; don't cross yourself.
struct SnakeMode: GameMode {
    let id          = "snake"
    let displayName = "Snake"
    let tagline     = "Tilt to steer. Grow. Don't cross your own trail."
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .score
    let onFail:      FailKind        = .endRun
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = false
    let showsScore                   = true
}

/// Bumper Cars — competitive arena: tilt-accelerate to knock rivals off.
struct BumperCarsMode: GameMode {
    let id          = "bumper"
    let displayName = "Bumper Cars"
    let tagline     = "Tilt for speed. Last marble on the floor wins."
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .score
    let onFail:      FailKind        = .endRun
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = true   // the arena edge is the hazard
    let showsScore                   = true
}

// MARK: - Catalogue + feature flags

/// The registry of game modes and whether each is live.
///
/// `isEnabled` is the local feature flag for now; later it can be overridden by
/// remote config so modes can be toggled / A-B tested without an app release —
/// the mechanism by which we discover which modes players enjoy.
enum GameModeCatalogue {
    /// The always-on spine.
    static let climb = ClimbMode()

    /// Everything else, with its launch flag.  Off until each mode's engine
    /// behavior is implemented.
    static let registry: [(mode: GameMode, isEnabled: Bool)] = [
        (climb,            true),
        (ZenGardenMode(),  true),    // engine behavior implemented — live
        (CoinPitMode(),    false),
        (SnakeMode(),      false),
        (BumperCarsMode(), false),
    ]

    /// Modes the player can currently see in the UI.
    static var enabled: [GameMode] { registry.filter { $0.isEnabled }.map { $0.mode } }

    /// Look up a mode by id (e.g. to resume the last-played mode).
    static func mode(id: String) -> GameMode? {
        registry.first { $0.mode.id == id }?.mode
    }
}
