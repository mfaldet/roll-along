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

/// Which designated area of the Games hub (GameMenuView) a mode belongs to.
/// `.climb` content (the adventure spine and its Challenge Tracks) is reached
/// through dedicated cards rather than per-mode rows, so the hub renders only
/// `.competitive` and `.solo` modes as individual entries.
enum GameModeSection {
    case climb          // the main adventure + its 100-level Challenge Tracks
    case competitive    // vs AI rivals — a winner is declared
    case solo           // self-paced, no rivals
}

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
    /// Which designated area of the Games hub this mode is listed under.
    var section: GameModeSection { get }

    var control:     ControlScheme  { get }
    var goal:        GoalKind       { get }
    var onFail:      FailKind       { get }
    var progression: ProgressionKind { get }
    var lives:       LivesPolicy    { get }

    /// Whether the arena contains fall-hazards (holes/pits) at all.
    var hasHoles:    Bool { get }

    /// Whether the ball carves one persistent line that stays for the whole
    /// session — the raked-sand signature of Zen Garden.  Most modes use the
    /// standard fading cosmetic trail and leave this false.
    var leavesPersistentTrail: Bool { get }

    // HUD composition — which overlays the mode shows.
    var showsStars:  Bool { get }
    var showsTimer:  Bool { get }
    var showsScore:  Bool { get }
}

// Sensible defaults so each mode struct only states what makes it distinct.
extension GameMode {
    var tagline:     String { "" }
    var section:     GameModeSection { .solo }
    var leavesPersistentTrail: Bool { false }
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
    let section:     GameModeSection = .climb
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

/// A themed 100-level side quest (e.g. "Frosty Peaks").  Plays like the
/// climb but on its own self-contained track, with a consistent difficulty
/// arc from easy (levels 1–15) through expert (81–95) to pinnacle (96–100),
/// and a free cosmetic bundle delivered on clearing level 100.
///
/// Difficulty Arc (applies to all tracks; see docs/challenge-tracks-roadmap.md):
///   1–15   Tutorial Phase    — easy tier, open layouts, learn the theme
///  16–35   Apprentice Phase  — easy/hard mix, 2 per-track obstacle types
///  36–60   Journeyman Phase  — hard tier, theme-specific mechanic introduced
///  61–80   Expert Phase      — very hard, precision routing required
///  81–95   Master Phase      — very hard, no redundant space, tight gold times
///  96–100  Pinnacle          — 5 showcase levels, equivalent to main-climb ~500+
struct ChallengeTrackMode: GameMode {
    let trackID: String
    let displayName: String
    let tagline: String

    var id: String { "challenge.\(trackID)" }
    let section:     GameModeSection = .climb
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .reachGoal
    let onFail:      FailKind        = .loseLifeAndRetry
    var progression: ProgressionKind { .challengeTrack(trackID) }
    let lives:       LivesPolicy     = .consume
    let hasHoles                     = true
    let showsStars                   = true
    let showsTimer                   = true

    // MARK: - Difficulty helpers (called by LevelLayout.trackLayout)

    /// Converts a track level (1–100) to a 0…1 difficulty fraction that drives
    /// hole density and obstacle complexity.  Matches the 6-phase arc:
    ///   Tutorial (1–15) → Apprentice (16–35) → Journeyman (36–60)
    ///   → Expert (61–80) → Master (81–95) → Pinnacle (96–100)
    /// 0…1 difficulty fraction for a track level — delegates to LevelLayout
    /// which owns the authoritative implementation (same file as the generator).
    static func difficultyFraction(for level: Int) -> Double {
        LevelLayout.difficultyFraction(for: level)
    }

    /// DifficultyTier for a track level — delegates to LevelLayout.
    static func challengeTier(for level: Int) -> DifficultyTier {
        LevelLayout.trackDifficultyTier(for: level)
    }

    /// Maps every defined Challenge Track ID to its cosmetic reward bundle ID.
    /// The bundle is granted for free by `GameState.deliverTrackReward(for:)`
    /// when the player clears level 100.  Returning nil means the track is
    /// planned but its reward bundle hasn't been built yet.
    static func rewardBundleID(for trackID: String) -> String? {
        switch trackID {
        // ── Packs backed by existing bundles (live in S19) ──────────────
        case "frozen-peaks":    return "winter"
        case "deep-cosmos":     return "cosmos"
        case "inferno-run":     return "lava-flow"
        case "neon-arcade":     return "neon"
        case "haunted-manor":   return "haunted"
        // ── Packs backed by new bundles (added progressively, S20–S22) ──
        case "ancient-temple":  return "ancient-temple"   // S20 — uses existing cosmetics
        case "abyssal-depths":  return "abyssal-depths"   // S21 — needs Trench ball
        case "golden-gauntlet": return "champion"         // S22 — needs Trophy ball (exclusive)
        default:                return nil
        }
    }
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
    let leavesPersistentTrail        = true
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

/// Comet Clash — Tron light-cycle twist (internal id stays "snake").  Tilt-steer
/// a comet that leaves a glowing, lethal wall; the wall fades over time but lasts
/// longer the more sparks you grab and rivals you wreck.  Last comet glowing wins.
struct SnakeMode: GameMode {
    let id          = "snake"
    let displayName = "Comet Clash"
    let tagline     = "Leave a glowing wall. Grab sparks to extend it. Touch any trail and you're out."
    let section:     GameModeSection = .competitive
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .score
    let onFail:      FailKind        = .endRun
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = false
    let showsScore                   = true
}

/// Sumo Survival — sumo dohyo with a shrinking ring and endless waves of rivals.
/// Tilt to ram rivals off the rim; survive as long as you can.  Score = your
/// knockouts.  (Evolved from the old "Bumper Cars" last-one-standing round.)
struct SumoSurvivalMode: GameMode {
    let id          = "sumo"
    let displayName = "Sumo Survival"
    let tagline     = "Shove rivals off a shrinking ring. Survive the waves."
    let section:     GameModeSection = .competitive
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .score
    let onFail:      FailKind        = .endRun
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = true   // the ring edge is the hazard
    let showsScore                   = true
}

/// Paint Ball — 60-second territory scramble: every marble trails its own paint
/// colour; most paint on the floor when the clock hits zero wins.  Scattered
/// puddle-pits freeze a marble that rolls in for a 3-second penalty.
struct PaintBallMode: GameMode {
    let id          = "paintball"
    let displayName = "Paint Ball"
    let tagline     = "Sixty seconds. Splash the most paint. Mind the puddles."
    let section:     GameModeSection = .competitive
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .score
    let onFail:      FailKind        = .none   // pits penalise, they don't end the run
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = false
    let showsTimer                   = true
    let showsScore                   = true
}

/// Gold Rush — 60-second coin scramble: grab the most coins off the floor;
/// ramming a rival knocks coins loose for anyone to snatch.  Your final count
/// is paid into your real balance, plus a win bonus.
struct GoldRushMode: GameMode {
    let id          = "goldrush"
    let displayName = "Gold Rush"
    let tagline     = "Grab the most coins in a minute. Bump rivals to make them spill."
    let section:     GameModeSection = .competitive
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .score
    let onFail:      FailKind        = .none
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = false
    let showsTimer                   = true
    let showsScore                   = true
}

/// Marble Cup — 90-second marble soccer (Rocket League with marbles).  Tilt to
/// slam a light neutral ball into the opponent's goal; the heavy marbles launch
/// it on a clean hit.  A solo match versus a defending AI.  Most goals wins.
struct MarbleCupMode: GameMode {
    let id          = "marblecup"
    let displayName = "Marble Cup"
    let tagline     = "Marble soccer. Roll the ball into their net before the whistle."
    let section:     GameModeSection = .competitive
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .score
    let onFail:      FailKind        = .none
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = false
    let showsTimer                   = true
    let showsScore                   = true
}

/// King of the Hill — 60-second fight over a glowing zone that drifts around the
/// arena.  Hold it alone to bank time; a rival rolling in makes it contested
/// (nobody scores) until you shove them out.  Most hold-time wins.
struct KingOfTheHillMode: GameMode {
    let id          = "koth"
    let displayName = "King of the Hill"
    let tagline     = "Hold the moving zone — alone. Most time on the hill wins."
    let section:     GameModeSection = .competitive
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .score
    let onFail:      FailKind        = .none
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = false
    let showsTimer                   = true
    let showsScore                   = true
}

/// Pinball — classic single-ball pinball, NO tilt.  Tap the LEFT half of the
/// screen to flick the left flipper, the RIGHT half for the right one.  Knock
/// the ball into the pop bumpers up top to score; three balls, then the run's
/// score banks coins.  Single-player against gravity and the drain.
struct PinballMode: GameMode {
    let id          = "pinball"
    let displayName = "Pinball"
    let tagline     = "No tilt — tap left & right to flick the flippers. Three balls."
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .score
    let onFail:      FailKind        = .none
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = false
    let showsTimer                   = false
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

    // ── Challenge Tracks ─────────────────────────────────────────────────
    // 100-level themed side quests.  Disabled until the challenge-track
    // engine (ChallengeTrackView, level generator, progress HUD) ships in S18.
    // See docs/challenge-tracks-roadmap.md for the full design.
    //
    // Reward bundles delivered by GameState.deliverTrackReward(for:) when
    // the player clears level 100.

    /// S19 — Winter / ice theme. Reward: "winter" bundle.
    static let frozenPeaks = ChallengeTrackMode(
        trackID:     "frozen-peaks",
        displayName: "Frosty Peaks",
        tagline:     "A hundred icy corridors. Every degree colder."
    )
    /// S19 — Nebulae / asteroid field theme. Reward: "cosmos" bundle.
    static let deepCosmos = ChallengeTrackMode(
        trackID:     "deep-cosmos",
        displayName: "Deep Cosmos",
        tagline:     "Roll through the asteroid belt. The void is patient."
    )
    /// S19 — Volcano / lava tubes theme. Reward: "lava-flow" bundle.
    static let infernoRun = ChallengeTrackMode(
        trackID:     "inferno-run",
        displayName: "Inferno Run",
        tagline:     "The floor is lava. Every floor. All one hundred."
    )
    /// S19 — Retro neon arcade theme. Reward: "neon" bundle.
    static let neonArcade = ChallengeTrackMode(
        trackID:     "neon-arcade",
        displayName: "Neon Arcade",
        tagline:     "Insert coin. Roll perfect. High score awaits."
    )
    /// S19 — Haunted manor / ghost theme. Reward: "haunted" bundle.
    static let hauntedManor = ChallengeTrackMode(
        trackID:     "haunted-manor",
        displayName: "Haunted Manor",
        tagline:     "The fog never lifts. The graveyard is the goal."
    )
    /// S20 — Desert ruins / archaeology theme. Reward: "ancient-temple" bundle.
    static let ancientTemple = ChallengeTrackMode(
        trackID:     "ancient-temple",
        displayName: "Ancient Temple",
        tagline:     "Carved corridors. Gilded traps. The relic waits."
    )
    /// S21 — Deep ocean descent theme. Reward: "abyssal-depths" bundle.
    /// NOTE: requires Trench BallSkin (bioluminescent navy) — built in S21.
    static let abyssalDepths = ChallengeTrackMode(
        trackID:     "abyssal-depths",
        displayName: "Abyssal Depths",
        tagline:     "Light doesn't reach here. Roll by feel."
    )
    /// S22 — Prestige gauntlet. Reward: "champion" bundle (pack-exclusive).
    /// NOTE: requires Trophy BallSkin (polished gold, exclusive) — built in S22.
    /// All 100 levels are Expert / Pinnacle tier — no Phase 1/2 ramp.
    static let goldenGauntlet = ChallengeTrackMode(
        trackID:     "golden-gauntlet",
        displayName: "Golden Gauntlet",
        tagline:     "No tutorial. No mercy. A hundred flawless rooms."
    )

    /// Everything else, with its launch flag.  Off until each mode's engine
    /// behavior is implemented.
    static let registry: [(mode: GameMode, isEnabled: Bool)] = [
        (climb,              true),
        (ZenGardenMode(),    true),    // engine behavior implemented — live
        (CoinPitMode(),      true),    // engine behavior implemented — live
        (SnakeMode(),        true),    // self-contained SnakeGameView — live
        (SumoSurvivalMode(), true),    // self-contained SumoSurvivalView — live
        (PaintBallMode(),    true),    // self-contained PaintBallView — live
        (GoldRushMode(),     true),    // self-contained GoldRushView — live
        (MarbleCupMode(),    true),    // self-contained MarbleCupView — live
        (KingOfTheHillMode(),true),    // self-contained KingOfTheHillView — live
        (PinballMode(),      true),    // self-contained PinballView — live
        // ── Challenge Tracks ─────────────────────────────────────────────
        // S19: existing-bundle tracks — engine + generator live
        (frozenPeaks,    true),
        (deepCosmos,     true),
        (infernoRun,     true),
        (neonArcade,     true),
        (hauntedManor,   true),
        // S20: ancient-temple bundle uses existing cosmetics — live
        (ancientTemple,  true),
        // S21: requires Trench ball + abyssal-depths bundle — live
        (abyssalDepths,  true),
        // S22: requires Trophy ball + champion bundle; gated at ≥3 completions
        (goldenGauntlet, true),
    ]

    /// Modes the player can currently see in the UI.
    static var enabled: [GameMode] { registry.filter { $0.isEnabled }.map { $0.mode } }

    /// All registered Challenge Tracks (enabled or not).
    static var challengeTracks: [ChallengeTrackMode] {
        registry.compactMap { $0.mode as? ChallengeTrackMode }
    }

    /// Look up a mode by id (e.g. to resume the last-played mode).
    static func mode(id: String) -> GameMode? {
        registry.first { $0.mode.id == id }?.mode
    }
}
