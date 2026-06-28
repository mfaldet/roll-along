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

/// The 30-second reward mini-game (displayed as "Gold Rush").  Roll to gather
/// up to 100 coins raining down the screen.  No hazards, no lives; a pure
/// payout round.
struct CoinPitMode: GameMode {
    // Display name swapped with the goldrush mode (2026-06-11, Mac's call) —
    // ids stay put: they're analytics keys, routes, and test anchors.
    let id          = "coinpit"
    let displayName = "Gold Rush"
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
    // Display name swapped with the coinpit mode (2026-06-11, Mac's call) —
    // ids stay put: they're analytics keys, routes, and test anchors.
    let id          = "goldrush"
    let displayName = "Coin Pit"
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

/// Roll Out — a true marble maze.  Tilt an extra-small ball through screen-
/// filling maze walls from the start to the goal without dropping into a hole.
/// Shares the climb's life economy: each fall costs a real life.  Self-contained
/// RollOutView; listed under "New ways to play".
struct RollOutMode: GameMode {
    let id          = "rollout"
    let displayName = "Roll Out"
    let tagline     = "A true marble maze. Reach the goal — don't fall in a hole."
    let section:     GameModeSection = .solo
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .reachGoal
    let onFail:      FailKind        = .loseLifeAndRetry
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .consume
    let hasHoles                     = true
}

/// Roll Up — a vertical jump-platformer.  Gravity pulls the ball down; tilt to
/// steer left/right and tap to pop it up onto floating platforms, climbing as
/// high as possible.  Each run (a fall off the bottom) costs a real life.
/// Self-contained RollUpView; listed under "New ways to play".
struct RollUpMode: GameMode {
    let id          = "rollup"
    let displayName = "Roll Up"
    let tagline     = "Tilt to steer, tap to jump. Climb the platforms as high as you can."
    let section:     GameModeSection = .solo
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .score
    let onFail:      FailKind        = .endRun
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .consume
    let hasHoles                     = false
    let showsScore                   = true
}

/// Disco Ball — a memorization + coordination game.  Memorize a lit path across
/// a tile floor between two safe zones, then roll it without a wrong step; score
/// is total crossings.  No life cost (pure score attack).  Self-contained
/// DiscoBallView; listed under "New ways to play".
struct DiscoBallMode: GameMode {
    let id          = "disco"
    let displayName = "Disco Ball"
    let tagline     = "Memorize the lit path. Roll across without a wrong step."
    let section:     GameModeSection = .solo
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .score
    let onFail:      FailKind        = .endRun
    let progression: ProgressionKind = .none
    let lives:       LivesPolicy     = .unlimited
    let hasHoles                     = false
    let showsScore                   = true
}

/// Challenge of the Day — a short (1–3 level), brutally hard daily gauntlet that
/// rotates every day, deterministically derived from the date so every player
/// gets the same one.  Reuses the climb's level generator at very high level
/// numbers (= maximum difficulty); failing just retries (no life cost).
struct DailyChallengeMode: GameMode {
    let id          = "daily"
    let displayName = "Challenge of the Day"
    let tagline     = "A short, brutal daily gauntlet."
    let section:     GameModeSection = .climb   // hidden from hub shelves; shown via the CotD banner
    let control:     ControlScheme   = .tiltAccel
    let goal:        GoalKind        = .reachGoal
    let onFail:      FailKind        = .loseLifeAndRetry
    let progression: ProgressionKind = .oneShot
    let lives:       LivesPolicy     = .unlimited   // retries are free — it's hard enough
    let hasHoles                     = true
    let showsStars                   = false
    let showsTimer                   = false         // not time-scored — pure survival
}

/// The deterministic content for a given day's Challenge of the Day.  There's no
/// hand-authored list — the date seeds a title, a length (1–3 levels), a base
/// difficulty (a high climb level), and a reward, so it's populated every day
/// through 2026 and beyond.
struct DailyChallenge {
    let dateKey: String     // "2026-06-24" — the completion key
    let title: String       // a punchy daily name
    let levelCount: Int      // 1…3 brutal levels
    let seed: Int            // the calendar day number — seeds the brutal layouts
    let rewardCoins: Int

    /// A distinct brutal-layout seed for the `index`-th level of the gauntlet
    /// (fed to `LevelLayout.dailyChallenge(seed:)`).
    func layoutSeed(for index: Int) -> Int { seed &* 101 &+ index }

    /// "YYYY-MM-DD" for a date — the per-day completion key.
    static func key(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The deterministic challenge for a given day (defaults to today).
    static func current(_ date: Date = Date()) -> DailyChallenge {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let dayNum = (c.year ?? 2026) * 10000 + (c.month ?? 1) * 100 + (c.day ?? 1)
        // Self-contained deterministic stream seeded by the calendar day.
        var h = UInt64(bitPattern: Int64(dayNum)) &* 2654435761
        func next(_ mod: Int) -> Int {
            h = h &* 6364136223846793005 &+ 1442695040888963407
            return Int(h >> 33) % mod
        }
        let titlePool = [
            "No Mercy", "The Gauntlet", "Hole Hell", "Knife's Edge", "Brutal Mile",
            "The Crucible", "Iron Path", "Pure Pain", "The Meatgrinder", "Sweat Test",
            "Nightmare Lane", "The Long Drop", "Last Nerve", "Precision Run",
            "Hard Reset", "The Grind",
        ]
        let title      = titlePool[next(titlePool.count)]
        let levelCount = 1 + next(3)              // 1…3 brutal levels
        let reward     = 30                        // flat 30 coins for clearing the day
        return DailyChallenge(dateKey: key(date), title: title,
                              levelCount: levelCount, seed: dayNum, rewardCoins: reward)
    }
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
        (DailyChallengeMode(), true),  // section .climb → hidden from shelves; launched via the CotD banner
        (ZenGardenMode(),    true),    // engine behavior implemented — live
        (CoinPitMode(),      true),    // engine behavior implemented — live
        (SnakeMode(),        true),    // self-contained SnakeGameView — live
        (SumoSurvivalMode(), true),    // self-contained SumoSurvivalView — live
        (PaintBallMode(),    true),    // self-contained PaintBallView — live
        (GoldRushMode(),     true),    // self-contained GoldRushView — live
        (MarbleCupMode(),    true),    // self-contained MarbleCupView — live
        (KingOfTheHillMode(),true),    // self-contained KingOfTheHillView — live
        (PinballMode(),      true),    // self-contained PinballView — live
        (RollOutMode(),      true),    // self-contained RollOutView — live
        (RollUpMode(),       true),    // self-contained RollUpView — live
        (DiscoBallMode(),    true),    // self-contained DiscoBallView — live
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

// ===========================================================================
// ModeTutorial — the one-time "how to play" card shown the first time a player
// opens a given mode (Nintendo-style: controls · goal · hazard · reward).  The
// climb is excluded: it has its own phased L1–L10 intro.
// ===========================================================================

struct ModeTutorial {
    let controls: String
    let goal: String
    let hazard: String?     // the obstacle to avoid (nil = nothing can hurt you)
    let reward: String

    /// Authored copy per catalogue id (not display name).  Returns nil for
    /// modes that don't need a card (the climb, the challenge tracks).
    static func `for`(_ id: String) -> ModeTutorial? {
        switch id {
        case "zen":
            return .init(controls: "Tilt to roll. There's no rush.",
                         goal: "There's no goal — just roll and breathe.",
                         hazard: nil,
                         reward: "A calm, perfect line carved in the sand.")
        case "coinpit":   // displayed "Gold Rush" — the 30s reward run
            return .init(controls: "Tilt to roll around the floor.",
                         goal: "Scoop up as many coins as you can in 30 seconds.",
                         hazard: "Only the clock — nothing can hurt you.",
                         reward: "Every coin you grab banks straight to your balance.")
        case "goldrush":  // displayed "Coin Pit" — the 60s competitive scramble
            return .init(controls: "Tilt to roll and chase the coins.",
                         goal: "Grab the most coins of anyone in 60 seconds.",
                         hazard: "Rivals ram you to knock your coins loose.",
                         reward: "Your haul banks as coins — win to earn a ticket.")
        case "snake":     // Comet Clash
            return .init(controls: "Tilt to steer your comet.",
                         goal: "Be the last comet still glowing.",
                         hazard: "Touch ANY glowing wall — yours or theirs — and you're out.",
                         reward: "Grab sparks to extend your wall and outlast everyone.")
        case "sumo":
            return .init(controls: "Tilt to charge and ram.",
                         goal: "Survive the endless waves of rivals.",
                         hazard: "Get shoved off the shrinking ring and it's over.",
                         reward: "Coins for every knockout and every second survived.")
        case "paintball":
            return .init(controls: "Tilt to roll — you paint the floor as you go.",
                         goal: "Cover the most floor in your colour in 60 seconds.",
                         hazard: "Roll through a puddle and you're frozen for 3 seconds.",
                         reward: "Coins for your coverage, plus a bonus for first place.")
        case "marblecup":
            return .init(controls: "Tilt to roll into the ball.",
                         goal: "Knock the ball into their net — most goals in 90s wins.",
                         hazard: "A defending AI guards the goal and counterattacks.",
                         reward: "Coins for every goal, plus a bonus if you win.")
        case "koth":      // King of the Hill
            return .init(controls: "Tilt to roll into the glowing zone.",
                         goal: "Hold the moving hill — alone — the longest.",
                         hazard: "A rival in the zone makes it contested: nobody scores.",
                         reward: "Coins for your hold time, plus a win bonus.")
        case "pinball":
            return .init(controls: "No tilt — tap the LEFT or RIGHT half to flick that flipper.",
                         goal: "Bash the bumpers up top for the highest score.",
                         hazard: "Don't let all three balls drain past the flippers.",
                         reward: "Your final score banks as coins.")
        case "rollout":
            return .init(controls: "Tilt to roll the tiny ball through the maze.",
                         goal: "Reach the flag at the top of each maze.",
                         hazard: "Fall in a hole and it costs a life.",
                         reward: "Coins for every maze you clear.")
        case "rollup":
            return .init(controls: "Tilt to steer left/right. Tap to jump.",
                         goal: "Climb the floating platforms as high as you can.",
                         hazard: "Fall off the bottom and the run ends — costing a life.",
                         reward: "Coins for your height, plus a bonus on a new best.")
        case "disco":
            return .init(controls: "Pick Normal or Hardcore, then tilt to roll. Memorize the lit path before you cross.",
                         goal: "Roll between the safe zones, back and forth, as many times as you can.",
                         hazard: "Touch a tile that isn't on the lit path and the run is over (Hardcore also adds a 10s timer).",
                         reward: "Coins for every crossing, plus a bonus on a new best.")
        default:
            return nil
        }
    }
}

/// Full-screen "how to play" card: dimmed background, labelled rows, and a big
/// "Got it — Play" button.  `onPlay` dismisses it and reveals the mode beneath.
struct ModeTutorialOverlay: View {
    let title: String
    let tutorial: ModeTutorial
    let onPlay: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.80).ignoresSafeArea()
            VStack(spacing: 0) {
                Text("HOW TO PLAY")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Color(white: 0.55))
                Text(title)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.bottom, 22)

                VStack(spacing: 14) {
                    row("hand.draw.fill", "CONTROLS", tutorial.controls,
                        Color(red: 0.40, green: 0.62, blue: 1.0))
                    row("flag.checkered", "GOAL", tutorial.goal,
                        Color(red: 0.40, green: 0.82, blue: 0.52))
                    if let hazard = tutorial.hazard {
                        row("exclamationmark.triangle.fill", "WATCH OUT", hazard,
                            Color(red: 0.98, green: 0.55, blue: 0.35))
                    }
                    row("gift.fill", "REWARD", tutorial.reward,
                        Color(red: 1.0, green: 0.82, blue: 0.30))
                }

                Button(action: onPlay) {
                    Text("Got it — Play")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(LinearGradient(colors: [.white, Color(white: 0.85)],
                                                     startPoint: .top, endPoint: .bottom))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 26)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color(white: 0.12))
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color(white: 0.24), lineWidth: 1))
            )
            .padding(.horizontal, 28)
        }
    }

    private func row(_ icon: String, _ label: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(color)
                Text(text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Gates a mode's view behind its one-time how-to-play card.  Applied to each
/// mode destination: `SnakeGameView().firstPlayTutorial("snake")`.  No-ops for
/// ids without an authored ModeTutorial (the climb, challenge tracks).
private struct FirstPlayTutorialModifier: ViewModifier {
    let modeID: String
    @EnvironmentObject var gameState: GameState
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if show, let tut = ModeTutorial.for(modeID) {
                    ModeTutorialOverlay(
                        title: GameModeCatalogue.mode(id: modeID)?.displayName ?? "Play",
                        tutorial: tut,
                        onPlay: {
                            gameState.markModePlayed(modeID)
                            withAnimation(.easeOut(duration: 0.22)) { show = false }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .onAppear {
                if !gameState.hasPlayedMode(modeID), ModeTutorial.for(modeID) != nil {
                    show = true
                }
            }
    }
}

extension View {
    func firstPlayTutorial(_ modeID: String) -> some View {
        modifier(FirstPlayTutorialModifier(modeID: modeID))
    }
}

/// Launch flourish played over the home screen when Play is pressed: the
/// player's ball spirals INWARD and shrinks into a glowing goal/portal at the
/// centre — like draining down a bowl, the same goal/portal on every Roll Along
/// map — then the camera is sucked into the portal (black expands from centre)
/// and the game pushes in underneath.  Self-contained; driven by a TimelineView
/// so the ball follows a true spiral path.
/// Full-screen portal glow + the "camera sucked down the drain" black wipe.
/// The spiralling ball itself is drawn separately by `LaunchBall`, in the home
/// ball's own coordinate space, so the two are layered but independent.
struct LaunchTransition: View {
    let since: Date
    /// Live spiral length in seconds.  Shrinks when the player taps to rush the
    /// launch (see HomeView.rushLaunch); the unrushed default is `defaultDuration`.
    let duration: Double
    /// The equipped goal's accent colour — the portal the ball drains into is
    /// tinted to match the goal you're rolling toward.
    var accent: Color = Color(red: 0.45, green: 0.78, blue: 1.0)
    static let defaultDuration: Double = 3.4

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let c = CGPoint(x: w / 2, y: h / 2)
            TimelineView(.animation) { tl in
                let p = min(1.0, tl.date.timeIntervalSince(since) / duration)  // 0→1
                let glow   = Double(pow(p, 2.0))                   // portal brightens as ball nears
                let blackP = max(0.0, (p - 0.78) / 0.18)           // black covers only at the very end (p≈0.96), after the long spiral
                let blackSize = CGFloat(blackP) * hypot(w, h) * 1.2

                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [accent.opacity(0.60 * glow),
                                     accent.opacity(0.28 * glow),
                                     .clear],
                            center: .center, startRadius: 0, endRadius: 70))
                        .frame(width: 150, height: 150)
                        .position(c)

                    Circle()
                        .fill(Color.black)
                        .frame(width: blackSize, height: blackSize)
                        .position(c)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// The equipped ball spiralling from its current home position down into the
/// centre, leaving a fading vortex trail.  Rendered INSIDE the home ball's
/// coordinate space, so `start` lines up exactly with where the roaming ball
/// sits — it visually replaces it.
struct LaunchBall: View {
    let skin: BallSkin
    let start: CGPoint        // current ball centre (arena space)
    let center: CGPoint       // arena centre — the drain
    let diameter: CGFloat     // starting size (matches the home ball)
    let since: Date
    let duration: Double      // live spiral length; shrinks on a rush tap
    /// Equipped goal's accent colour — tints the draining vortex trail.
    var accent: Color = Color(red: 0.62, green: 0.86, blue: 1.0)
    private static let turns: Double = 6.0

    /// Whirlpool path position at progress `pp` (0…1).  Tuned to read like the
    /// cold-open vortex in `IntroView`: the radius draws inward *steadily* from
    /// the first frame — no dwelling out at the rim — while the angular speed
    /// ramps up toward the centre, so the marble winds ever tighter as it
    /// drains (a real whirlpool whip rather than slow, wide outer orbits).
    ///
    /// Decoupling the two easings is the whole trick.  A single `pp²` used to
    /// drive *both* radius and angle, which left the ball loitering at full
    /// radius for ~2s and only whipping in at the very end.  Now `radEase`
    /// (linear → steady draw) and `angEase` (ease-in → accelerating spin) are
    /// independent.  `pos(0) == start` and `pos(1) == center` still hold, so the
    /// spiral begins exactly where the roaming home ball sits.
    /// A method (not a closure-local func) so it lives outside the ViewBuilder.
    private func pos(_ pp: Double) -> CGPoint {
        let r0 = hypot(start.x - center.x, start.y - center.y)
        let a0 = Double(atan2(start.y - center.y, start.x - center.x))
        let radEase = pp                 // steady inward draw — kills the rim-dwell
        let angEase = pow(pp, 1.7)       // angular speed ramps up toward the centre
        let rad = r0 * CGFloat(1 - radEase)
        let ang = a0 + angEase * 2 * .pi * Self.turns
        return CGPoint(x: center.x + CGFloat(cos(ang)) * rad,
                       y: center.y + CGFloat(sin(ang)) * rad)
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let p  = min(1.0, tl.date.timeIntervalSince(since) / duration)
            let here     = pos(p)
            // Shrinks steadily alongside the inward draw (was a late pp² drop,
            // which kept the ball large while the old rim-dwell played out).
            let ballSize = max(7, diameter * (1 - CGFloat(pow(p, 1.6))))
            let blackP   = max(0.0, (p - 0.78) / 0.18)

            ZStack {
                // Fading vortex trail — sample the spiral path just behind the ball.
                Canvas { ctx, _ in
                    let steps = 22
                    var prev: CGPoint? = nil
                    for j in stride(from: steps, through: 0, by: -1) {
                        let frac = Double(j) / Double(steps)
                        let pt = pos(max(0, p - 0.16 * frac))
                        if let pv = prev {
                            let op = (1 - frac) * 0.55 * (1 - Double(blackP))
                            let lw = ballSize * CGFloat(0.40 + (1 - frac) * 0.55)
                            var seg = Path(); seg.move(to: pv); seg.addLine(to: pt)
                            ctx.stroke(seg, with: .color(accent.opacity(op)),
                                       style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                        }
                        prev = pt
                    }
                }
                BallSkinView(skin: skin, diameter: ballSize)
                    .frame(width: ballSize, height: ballSize)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .position(here)
                    .opacity(1 - Double(blackP))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
