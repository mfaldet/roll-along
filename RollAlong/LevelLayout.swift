import SwiftUI

// ===========================================================================
// LevelRNG — a tiny deterministic random source.
//
// The procedural level generator must be DETERMINISTIC: level 1,234 has to
// produce the exact same layout on every device, every launch, forever — so
// star times, leaderboards, and "I'm stuck on 1,234" all mean the same thing
// for everyone.  Swift's SystemRandomNumberGenerator is non-deterministic, so
// we seed our own (SplitMix64) from the level number.
// ===========================================================================
struct LevelRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// Uniform Double in 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
    /// Uniform Double in lo...hi.
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
    /// Uniform Int in lo...hi (inclusive).
    mutating func int(_ lo: Int, _ hi: Int) -> Int { lo + Int(unit() * Double(hi - lo + 1)) }
}

// ===========================================================================
// World — a named 100-level chapter of the main climb.
//
//   50 worlds × 100 levels = 5,000.
//
// A world is the climb's CHAPTER structure: it gives each 100-level stretch an
// identity (name + accent colour) and anchors the difficulty curve the
// generator follows (deeper world → longer, busier courses — never tighter
// pixel-precision, per the core design rule).
//
// A world does NOT override the player's equipped cosmetics.  Floor / pit /
// ball stay player choices — the old per-level theme bands were retired (see
// LevelSelectView).  `suggestedFloor` / `suggestedPit` are optional and used
// only as level-select chrome today, leaving the door open to an opt-in
// "world re-skin" later without reworking this model.
// ===========================================================================
struct World {
    let index: Int            // 1…50
    let name:  String
    let accent: Color

    static let count          = 50
    static let levelsPerWorld = 100
    static let maxLevel       = count * levelsPerWorld   // 5,000

    var levelRange: ClosedRange<Int> {
        ((index - 1) * levelsPerWorld + 1) ... (index * levelsPerWorld)
    }

    /// 0…1 position of this world across the whole climb — the master
    /// difficulty dial the generator reads.
    var difficulty: Double { Double(index - 1) / Double(max(1, count - 1)) }

    static func index(for level: Int) -> Int {
        min(count, max(1, (level - 1) / levelsPerWorld + 1))
    }
    static func world(for level: Int) -> World { all[index(for: level) - 1] }

    /// The 50 chapters, ascending from gentle ground to the final summit.
    /// Accent is a smooth hue sweep so the map reads as one long journey.
    static let all: [World] = names.enumerated().map { i, name in
        World(index: i + 1,
              name:  name,
              accent: Color(hue: Double(i) / Double(count),
                            saturation: 0.58, brightness: 0.90))
    }

    private static let names: [String] = [
        "Meadowgate",   "Pebble Shore",  "Hollow Woods",  "Amber Dunes",   "Cinder Reach",
        "Frostpine",    "Tidecaller",    "Glasswind",     "Thornfield",    "Sunspire",
        "Mistmarsh",    "Copper Mesa",   "Verdant Hollow","Saltflats",     "Stormwatch",
        "Ironwood",     "Cobalt Bay",    "Emberfall",     "Driftwood",     "Dawnspire",
        "Ashen Vale",   "Lumen Grove",   "Quartz Canyon", "Bramblewick",   "Gale Crest",
        "Umbral Fen",   "Marble Heights","Solace Reef",   "Nettle Run",    "Duskspire",
        "Hollowmere",   "Garnet Wastes", "Willowdeep",    "Cinderpath",    "Auric Steppe",
        "Frostward",    "Tempest Line",  "Opaline Coast", "Briarmoor",     "Starspire",
        "Veil Hollow",  "Prism Reach",   "Onyx Span",     "The Verge",     "Aurora Gate",
        "Nimbus Field", "Halcyon",       "Eventide",      "Zenith Climb",  "The Summit",
    ]
}

// ---------------------------------------------------------------------------
// DifficultyTier — what kind of level is this?
//
// CORE DESIGN RULE (applies levels 1 … 1,000,000+):
//   • Last digit 1 / 2 / 3 / 4 → .easy
//   • Last digit 6 / 7 / 8 / 9 → .hard
//   • Last digit 0 / 5         → .veryHard
//
// Per group of 10:  E E E E V H H H H V    (Easy / VeryHard / Hard / VeryHard)
//
// IMPORTANT: "Hard" never means tightrope-precision frustrating.  All players
// of all ages must be able to pass every level eventually.  Hard / Very Hard
// simply means a longer path or more obstacles — slower star goals because
// the level inherently takes longer to complete.  True precision content is
// reserved for separate "Challenge" events shipped later.
// ---------------------------------------------------------------------------
enum DifficultyTier: String, Codable {
    case easy
    case hard
    case veryHard

    /// Derive the tier for a level from its number, per the core design rule.
    /// Works for any positive level number.
    static func tier(for level: Int) -> DifficultyTier {
        let lastDigit = abs(level) % 10
        switch lastDigit {
        case 1, 2, 3, 4: return .easy
        case 6, 7, 8, 9: return .hard
        case 0, 5:       return .veryHard
        default:         return .easy   // mathematically unreachable
        }
    }

    /// Multiplier applied to formula-based star times.  Harder levels get
    /// more time before docking stars because the path is longer, not because
    /// the player is being punished.
    var timeMultiplier: Double {
        switch self {
        case .easy:     return 1.0
        case .hard:     return 1.3
        case .veryHard: return 1.6
        }
    }

    var displayName: String {
        switch self {
        case .easy:     return "Easy"
        case .hard:     return "Hard"
        case .veryHard: return "Very Hard"
        }
    }

    var color: Color {
        switch self {
        case .easy:     return Color(red: 0.25, green: 0.78, blue: 0.40)
        case .hard:     return Color(red: 0.95, green: 0.65, blue: 0.20)
        case .veryHard: return Color(red: 0.90, green: 0.28, blue: 0.32)
        }
    }
}

/// One playable course.
///
/// All positions are normalised to 0…1 in each axis so the layout adapts to
/// any device size.  The renderer in `BallGameView` multiplies by the actual
/// arena dimensions at draw time.
struct LevelLayout {
    let holeRects:  [CGRect]      // hazards
    let start:      UnitPoint     // ball spawn
    let goal:       UnitPoint     // goal centre
    let coins:      [UnitPoint]   // up to 3 collectibles
    let targetTime: TimeInterval  // 2-star threshold (seconds) — BEFORE tier multiplier
    let goldTime:   TimeInterval  // 3-star threshold (seconds) — BEFORE tier multiplier
    let tier:       DifficultyTier
    let verified:   Bool          // true = hand-reviewed, do not auto-modify

    /// Per-level explicit tier overrides — when a designed layout doesn't
    /// fit the position-derived tier, list it here.  Empty by default; the
    /// last-digit rule covers all 100 currently-shipped levels well.
    static let tierOverrides: [Int: DifficultyTier] = [:]

    /// Per-level explicit "verified" flag — set true once a level has been
    /// hand-reviewed and should be considered locked.  Listed externally
    /// so we can mark levels verified without re-editing every layout.
    static let verifiedLevels: Set<Int> = []

    static func layout(for level: Int) -> LevelLayout {
        let base: LevelLayout
        if level >= 1 && level <= handCrafted.count {
            base = handCrafted[level - 1]
        } else {
            base = generated(for: level)
        }
        let tier = tierOverrides[level] ?? DifficultyTier.tier(for: level)
        let mult = tier.timeMultiplier
        // Easy levels (digits 1-4) play across the FULL arena width
        // instead of the standard narrow column flanked by side-wall
        // hole-rects.  The off-screen detection (`x < -r` etc.) still
        // catches a ball that escapes wall bounces under extreme
        // velocity, but the player no longer sees big black "death
        // bars" lining the left and right of the screen.
        let stripSideWalls = tier == .easy
        let cleanedHoles: [CGRect]
        if stripSideWalls {
            cleanedHoles = base.holeRects.filter { !isSideWall($0) }
        } else {
            cleanedHoles = base.holeRects
        }
        return LevelLayout(
            holeRects:  cleanedHoles,
            start:      base.start,
            goal:       base.goal,
            coins:      base.coins,
            targetTime: base.targetTime * mult,
            goldTime:   base.goldTime * mult,
            tier:       tier,
            verified:   base.verified || verifiedLevels.contains(level)
        )
    }

    // Flip the course vertically: ball ↔ goal swap, obstacle rects mirrored,
    // and coin positions mirrored as well.  Tier + verified preserved.
    func flipped() -> LevelLayout {
        LevelLayout(
            holeRects: holeRects.map { r in
                CGRect(x: r.origin.x, y: 1 - r.origin.y - r.height,
                       width: r.width, height: r.height)
            },
            start:      UnitPoint(x: start.x, y: 1 - start.y),
            goal:       UnitPoint(x: goal.x,  y: 1 - goal.y),
            coins:      coins.map { UnitPoint(x: $0.x, y: 1 - $0.y) },
            targetTime: targetTime,
            goldTime:   goldTime,
            tier:       tier,
            verified:   verified
        )
    }
}

// MARK: - Hand-crafted level designs

extension LevelLayout {
    /// Side-wall hole rectangles used as the standard arena margins.
    /// Auto-prepended by `make(...)` so every hand-crafted level ships
    /// with them.  Stripped by `layout(for:)` for Easy-tier levels
    /// (digits 1-4) so beginners play across the full arena width.
    private static let sideWalls: [CGRect] = [
        CGRect(x: 0.00, y: 0, width: 0.12, height: 1),
        CGRect(x: 0.88, y: 0, width: 0.12, height: 1),
    ]

    /// True when a hole rect matches one of the standard `sideWalls`
    /// (left or right strip).  Used to strip side walls on Easy-tier
    /// levels without affecting any real designed holes.
    private static func isSideWall(_ rect: CGRect) -> Bool {
        let eps: CGFloat = 0.001
        return abs(rect.height - 1)     < eps
            && abs(rect.origin.y)       < eps
            && abs(rect.width - 0.12)   < eps
            && (abs(rect.origin.x)             < eps
                || abs(rect.origin.x - 0.88)   < eps)
    }

    /// Standard formula for target/gold times based on the start→goal
    /// straight-line distance plus a difficulty penalty per hole.
    /// Tuned so a clean run gets 2 stars and a fast direct line gets 3.
    private static func defaultTimes(start: UnitPoint, goal: UnitPoint,
                                     holeCount: Int) -> (target: TimeInterval, gold: TimeInterval) {
        let dx = goal.x - start.x
        let dy = goal.y - start.y
        let dist = sqrt(dx * dx + dy * dy)          // ~0…1.4 (diagonal max)
        let target = 4.0 * dist + 0.35 * Double(holeCount) + 2.5
        let gold   = 2.8 * dist + 0.20 * Double(holeCount) + 1.8
        return (target, gold)
    }

    /// Convenience initialiser that auto-computes times unless overridden.
    ///
    /// Note: `tier` and `verified` are placeholders here.  The real values
    /// are injected by `LevelLayout.layout(for:)` based on level number +
    /// the optional override maps.  This keeps the per-level definitions
    /// concise — designers only specify holes, start, goal, coins, and
    /// optional time overrides.
    private static func make(
        holes: [CGRect],
        start: UnitPoint,
        goal: UnitPoint,
        coins: [UnitPoint],
        target: TimeInterval? = nil,
        gold: TimeInterval? = nil,
        verified: Bool = false
    ) -> LevelLayout {
        let allHoles = sideWalls + holes
        let times = defaultTimes(start: start, goal: goal, holeCount: holes.count)
        return LevelLayout(
            holeRects:  allHoles,
            start:      start,
            goal:       goal,
            coins:      coins,
            targetTime: target ?? times.target,
            goldTime:   gold   ?? times.gold,
            tier:       .easy,    // placeholder; overridden in layout(for:)
            verified:   verified
        )
    }

    /// Levels 1-10 — World 1, Classic sub-theme.
    /// Difficulty climbs gradually so new players learn tilt control.
    static let handCrafted: [LevelLayout] = [

        // ═══════════════════════════════════════════════════════════════════
        // TUTORIAL — levels 1-10
        //
        // Each level is a concept introduction.  They follow the universal
        // tier pattern E E E E V H H H H V:
        //
        //   L1  Easy       roll straight down
        //   L2  Easy       curve around one obstacle
        //   L3  Easy       diagonal navigation
        //   L4  Easy       zigzag
        //   L5  Very Hard  precision threading (narrow gaps in series)
        //   L6  Hard       tighter spaces
        //   L7  Hard       multiple scattered obstacles
        //   L8  Hard       circles — loop around a central feature
        //   L9  Hard       maze — multiple corridors with dead ends
        //   L10 Very Hard  finale combining every concept above
        //
        // All ten are marked `verified: true` — they are intentional,
        // hand-crafted, do-not-auto-modify.
        // ═══════════════════════════════════════════════════════════════════

        // ── L1 Easy — Phased intro + roll past one wide hole ───────────────
        // On first play, BallGameView runs L1 as a 4-phase tutorial
        // (intro hint → free roam → coins → hole), revealing each
        // element with an explanatory pill.  After the player dismisses
        // the third hint (or wins once), L1 plays as the layout below.
        //
        // Coins arrange in a slight zig-zag (top-left, top-right, then
        // just-above-centre in the played orientation — base coords
        // need the y values flipped since ballStartsAtTop = true).
        //
        // The hole is wide (48% × 7%) and sits just BELOW centre in
        // the played view → just ABOVE centre in base coords (y=0.45).
        // Easy tier means `layout(for:)` strips the side-wall hole
        // strips, so the full arena width is playable — the player
        // can flow around either end of the hole.
        make(
            // Base y=0.38, h=0.07 → flipped played y range 0.55–0.62
            // (clearly below the vertical centre, between the third
            // coin and the goal).  Width 0.48 = ~3× the original
            // small hole.
            holes: [
                CGRect(x: 0.26, y: 0.38, width: 0.48, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.25, y: 0.75),    // → top-left   in played orientation
                UnitPoint(x: 0.75, y: 0.75),    // → top-right  in played orientation
                UnitPoint(x: 0.50, y: 0.60),    // → just above centre in played orientation
            ],
            verified: true
        ),

        // ── L2 Easy — Curve around one obstacle ────────────────────────────
        // Wide single hole in the middle.  Player learns to tilt sideways
        // mid-roll.  Coins on both routes incentivise either choice.
        make(
            holes: [
                CGRect(x: 0.30, y: 0.42, width: 0.40, height: 0.16),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.20, y: 0.50),   // left route
                UnitPoint(x: 0.80, y: 0.50),   // right route
                UnitPoint(x: 0.50, y: 0.24),   // centre after rejoin
            ],
            verified: true
        ),

        // ── L3 Easy — Diagonal navigation ──────────────────────────────────
        // Start bottom-left, goal top-right.  One staircase pair of bars
        // forces the player to roll diagonally rather than straight.
        // Coins arc along the diagonal path.
        make(
            holes: [
                CGRect(x: 0.36, y: 0.55, width: 0.50, height: 0.08),
                CGRect(x: 0.14, y: 0.30, width: 0.50, height: 0.08),
            ],
            start: UnitPoint(x: 0.18, y: 0.92),
            goal:  UnitPoint(x: 0.82, y: 0.10),
            coins: [
                UnitPoint(x: 0.22, y: 0.75),
                UnitPoint(x: 0.78, y: 0.45),
                UnitPoint(x: 0.82, y: 0.20),
            ],
            verified: true
        ),

        // ── L4 Easy — Zigzag ───────────────────────────────────────────────
        // Three alternating bars.  Player weaves left-right-left through
        // the openings.  Classic zigzag teaches rhythmic tilt control.
        make(
            holes: [
                CGRect(x: 0.18, y: 0.28, width: 0.40, height: 0.08),
                CGRect(x: 0.42, y: 0.48, width: 0.40, height: 0.08),
                CGRect(x: 0.18, y: 0.68, width: 0.40, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.78),
                UnitPoint(x: 0.22, y: 0.58),
                UnitPoint(x: 0.78, y: 0.38),
            ],
            verified: true
        ),

        // ── L5 Very Hard — Precision threading ─────────────────────────────
        // Three rows of paired narrow gaps.  Each row requires the player
        // to slow down, line up, and pass through the gap before moving
        // to the next.  Teaches deliberate, paced movement.  The tier
        // multiplier (1.6x) gives 60% more time on star thresholds since
        // this level takes longer by design — never punishing.
        make(
            holes: [
                CGRect(x: 0.12, y: 0.24, width: 0.32, height: 0.09),
                CGRect(x: 0.56, y: 0.24, width: 0.32, height: 0.09),
                CGRect(x: 0.12, y: 0.46, width: 0.32, height: 0.09),
                CGRect(x: 0.56, y: 0.46, width: 0.32, height: 0.09),
                CGRect(x: 0.12, y: 0.68, width: 0.32, height: 0.09),
                CGRect(x: 0.56, y: 0.68, width: 0.32, height: 0.09),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.5, y: 0.80),   // before first gap
                UnitPoint(x: 0.5, y: 0.57),   // between gaps
                UnitPoint(x: 0.5, y: 0.16),   // after final gap
            ],
            verified: true
        ),

        // ── L6 Hard — Tighter spaces ───────────────────────────────────────
        // Wider hole pairs leaving a narrower vertical corridor.  Forces
        // more controlled, centred descent than L4's zigzag.
        make(
            holes: [
                CGRect(x: 0.12, y: 0.22, width: 0.32, height: 0.18),
                CGRect(x: 0.56, y: 0.22, width: 0.32, height: 0.18),
                CGRect(x: 0.12, y: 0.60, width: 0.32, height: 0.18),
                CGRect(x: 0.56, y: 0.60, width: 0.32, height: 0.18),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.84),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.16),
            ],
            verified: true
        ),

        // ── L7 Hard — Scattered obstacles ──────────────────────────────────
        // Many small holes spread across the arena.  No single forced path
        // — the player must look at the board and pick a route.  Teaches
        // strategic route-finding rather than reactive dodging.
        make(
            holes: [
                CGRect(x: 0.20, y: 0.22, width: 0.12, height: 0.08),
                CGRect(x: 0.46, y: 0.22, width: 0.12, height: 0.08),
                CGRect(x: 0.68, y: 0.30, width: 0.12, height: 0.08),
                CGRect(x: 0.30, y: 0.38, width: 0.12, height: 0.08),
                CGRect(x: 0.56, y: 0.46, width: 0.12, height: 0.08),
                CGRect(x: 0.18, y: 0.50, width: 0.12, height: 0.08),
                CGRect(x: 0.40, y: 0.58, width: 0.12, height: 0.08),
                CGRect(x: 0.66, y: 0.62, width: 0.12, height: 0.08),
                CGRect(x: 0.22, y: 0.70, width: 0.12, height: 0.08),
                CGRect(x: 0.50, y: 0.76, width: 0.12, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.80, y: 0.80),
                UnitPoint(x: 0.18, y: 0.40),
                UnitPoint(x: 0.82, y: 0.18),
            ],
            verified: true
        ),

        // ── L8 Hard — Circles ──────────────────────────────────────────────
        // A ring of holes around a central safe area.  Player can loop
        // around the outside, OR thread through one of the gaps and
        // traverse the centre.  Teaches that the obvious "straight line"
        // isn't always the answer.
        make(
            holes: [
                // Top arc
                CGRect(x: 0.28, y: 0.26, width: 0.12, height: 0.08),
                CGRect(x: 0.44, y: 0.22, width: 0.12, height: 0.08),
                CGRect(x: 0.60, y: 0.26, width: 0.12, height: 0.08),
                // Sides
                CGRect(x: 0.18, y: 0.42, width: 0.10, height: 0.16),
                CGRect(x: 0.72, y: 0.42, width: 0.10, height: 0.16),
                // Bottom arc
                CGRect(x: 0.28, y: 0.66, width: 0.12, height: 0.08),
                CGRect(x: 0.44, y: 0.70, width: 0.12, height: 0.08),
                CGRect(x: 0.60, y: 0.66, width: 0.12, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.48),   // dead centre of the ring
                UnitPoint(x: 0.36, y: 0.46),
                UnitPoint(x: 0.64, y: 0.50),
            ],
            verified: true
        ),

        // ── L9 Hard — Maze intro ───────────────────────────────────────────
        // Connected corridors with dead ends.  The clear path snakes through
        // the layout.  Teaches the player to look ahead and avoid traps.
        make(
            holes: [
                CGRect(x: 0.12, y: 0.22, width: 0.50, height: 0.07),
                CGRect(x: 0.30, y: 0.36, width: 0.58, height: 0.07),
                CGRect(x: 0.12, y: 0.50, width: 0.30, height: 0.07),
                CGRect(x: 0.50, y: 0.50, width: 0.38, height: 0.07),
                CGRect(x: 0.30, y: 0.64, width: 0.40, height: 0.07),
                CGRect(x: 0.12, y: 0.78, width: 0.50, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.85),
                UnitPoint(x: 0.20, y: 0.43),
                UnitPoint(x: 0.78, y: 0.15),
            ],
            verified: true
        ),

        // ── L10 Very Hard — Combine concepts (Tutorial finale) ─────────────
        // The graduation level.  Includes a zigzag opener, a tight corridor
        // mid-section, scattered obstacles, and a final pinch before goal.
        // Tier multiplier gives generous time so the achievement of clearing
        // it feels great rather than punishing.
        //
        // FUTURE: clearing this level for the first time should trigger
        // the "Pick a free cosmetic per category" reward modal.  That
        // modal arrives with PR 4f when the cosmetic shop is in place.
        make(
            holes: [
                // Zigzag opener (top)
                CGRect(x: 0.16, y: 0.22, width: 0.40, height: 0.07),
                CGRect(x: 0.44, y: 0.36, width: 0.40, height: 0.07),
                // Narrow corridor mid
                CGRect(x: 0.12, y: 0.50, width: 0.28, height: 0.10),
                CGRect(x: 0.60, y: 0.50, width: 0.28, height: 0.10),
                // Scattered field
                CGRect(x: 0.22, y: 0.66, width: 0.12, height: 0.07),
                CGRect(x: 0.44, y: 0.66, width: 0.12, height: 0.07),
                CGRect(x: 0.66, y: 0.66, width: 0.12, height: 0.07),
                // Final pinch
                CGRect(x: 0.18, y: 0.80, width: 0.24, height: 0.07),
                CGRect(x: 0.58, y: 0.80, width: 0.24, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.94),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.88),
                UnitPoint(x: 0.50, y: 0.43),
                UnitPoint(x: 0.50, y: 0.16),
            ],
            verified: true
        ),

        // ═══════════════════════════════════════════════════════════════════
        // INVERTED — levels 11-20
        // Black floor, white holes. Same physics, brain has to re-parse.
        // ═══════════════════════════════════════════════════════════════════

        // L11 — Intro: single central hole, reminds player of mechanics
        make(
            holes: [
                CGRect(x: 0.35, y: 0.45, width: 0.30, height: 0.12),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.20, y: 0.50),
                UnitPoint(x: 0.80, y: 0.50),
                UnitPoint(x: 0.50, y: 0.25),
            ]
        ),

        // L12 — Off-centre hazard
        make(
            holes: [
                CGRect(x: 0.50, y: 0.30, width: 0.32, height: 0.40),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.22, y: 0.50),
                UnitPoint(x: 0.50, y: 0.78),
                UnitPoint(x: 0.78, y: 0.18),
            ]
        ),

        // L13 — Offset bar gates
        make(
            holes: [
                CGRect(x: 0.12, y: 0.30, width: 0.60, height: 0.08),
                CGRect(x: 0.28, y: 0.55, width: 0.60, height: 0.08),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.80, y: 0.42),
                UnitPoint(x: 0.20, y: 0.66),
                UnitPoint(x: 0.50, y: 0.22),
            ]
        ),

        // L14 — Stepped descent
        make(
            holes: [
                CGRect(x: 0.18, y: 0.22, width: 0.18, height: 0.08),
                CGRect(x: 0.40, y: 0.36, width: 0.18, height: 0.08),
                CGRect(x: 0.62, y: 0.50, width: 0.18, height: 0.08),
                CGRect(x: 0.40, y: 0.64, width: 0.18, height: 0.08),
                CGRect(x: 0.18, y: 0.78, width: 0.18, height: 0.06),
            ],
            start: UnitPoint(x: 0.5,  y: 0.92),
            goal:  UnitPoint(x: 0.5,  y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.78),
                UnitPoint(x: 0.30, y: 0.50),
                UnitPoint(x: 0.78, y: 0.30),
            ]
        ),

        // L15 — Cross
        make(
            holes: [
                CGRect(x: 0.42, y: 0.30, width: 0.18, height: 0.10),  // top
                CGRect(x: 0.22, y: 0.46, width: 0.18, height: 0.10),  // left
                CGRect(x: 0.42, y: 0.46, width: 0.18, height: 0.10),  // centre
                CGRect(x: 0.62, y: 0.46, width: 0.18, height: 0.10),  // right
                CGRect(x: 0.42, y: 0.62, width: 0.18, height: 0.10),  // bottom
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.18, y: 0.36),
                UnitPoint(x: 0.82, y: 0.36),
                UnitPoint(x: 0.50, y: 0.80),
            ]
        ),

        // L16 — Hourglass narrowing
        make(
            holes: [
                CGRect(x: 0.12, y: 0.32, width: 0.30, height: 0.12),
                CGRect(x: 0.58, y: 0.32, width: 0.30, height: 0.12),
                CGRect(x: 0.20, y: 0.56, width: 0.22, height: 0.12),
                CGRect(x: 0.58, y: 0.56, width: 0.22, height: 0.12),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.50, y: 0.74),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.22),
            ]
        ),

        // L17 — Pinball: scattered small holes
        make(
            holes: [
                CGRect(x: 0.22, y: 0.22, width: 0.12, height: 0.07),
                CGRect(x: 0.62, y: 0.25, width: 0.12, height: 0.07),
                CGRect(x: 0.42, y: 0.35, width: 0.12, height: 0.07),
                CGRect(x: 0.20, y: 0.46, width: 0.12, height: 0.07),
                CGRect(x: 0.66, y: 0.48, width: 0.12, height: 0.07),
                CGRect(x: 0.44, y: 0.60, width: 0.12, height: 0.07),
                CGRect(x: 0.24, y: 0.72, width: 0.12, height: 0.07),
                CGRect(x: 0.62, y: 0.72, width: 0.12, height: 0.07),
            ],
            start: UnitPoint(x: 0.5,  y: 0.90),
            goal:  UnitPoint(x: 0.5,  y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.78),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.22),
            ]
        ),

        // L18 — Funnel
        make(
            holes: [
                CGRect(x: 0.12, y: 0.30, width: 0.18, height: 0.08),
                CGRect(x: 0.70, y: 0.30, width: 0.18, height: 0.08),
                CGRect(x: 0.18, y: 0.45, width: 0.18, height: 0.08),
                CGRect(x: 0.64, y: 0.45, width: 0.18, height: 0.08),
                CGRect(x: 0.24, y: 0.60, width: 0.18, height: 0.08),
                CGRect(x: 0.58, y: 0.60, width: 0.18, height: 0.08),
                CGRect(x: 0.30, y: 0.74, width: 0.18, height: 0.07),
                CGRect(x: 0.52, y: 0.74, width: 0.18, height: 0.07),
            ],
            start: UnitPoint(x: 0.5,  y: 0.92),
            goal:  UnitPoint(x: 0.5,  y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.82),
                UnitPoint(x: 0.50, y: 0.52),
                UnitPoint(x: 0.50, y: 0.22),
            ]
        ),

        // L19 — Spinal: vertical bar down centre, weave around
        make(
            holes: [
                CGRect(x: 0.44, y: 0.20, width: 0.12, height: 0.55),
            ],
            start: UnitPoint(x: 0.25, y: 0.92),
            goal:  UnitPoint(x: 0.75, y: 0.10),
            coins: [
                UnitPoint(x: 0.25, y: 0.45),
                UnitPoint(x: 0.75, y: 0.45),
                UnitPoint(x: 0.50, y: 0.85),
            ]
        ),

        // L20 — Inverted finale: dense layered field
        make(
            holes: [
                CGRect(x: 0.18, y: 0.20, width: 0.25, height: 0.08),
                CGRect(x: 0.57, y: 0.20, width: 0.25, height: 0.08),
                CGRect(x: 0.30, y: 0.36, width: 0.40, height: 0.08),
                CGRect(x: 0.15, y: 0.50, width: 0.30, height: 0.08),
                CGRect(x: 0.55, y: 0.50, width: 0.30, height: 0.08),
                CGRect(x: 0.30, y: 0.64, width: 0.40, height: 0.08),
                CGRect(x: 0.18, y: 0.78, width: 0.25, height: 0.06),
                CGRect(x: 0.57, y: 0.78, width: 0.25, height: 0.06),
            ],
            start: UnitPoint(x: 0.5,  y: 0.92),
            goal:  UnitPoint(x: 0.5,  y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.28),
                UnitPoint(x: 0.50, y: 0.58),
                UnitPoint(x: 0.50, y: 0.85),
            ]
        ),

        // ═══════════════════════════════════════════════════════════════════
        // TWILIGHT — levels 21-30
        // Calmer mood, longer paths, slightly more open arenas.
        // ═══════════════════════════════════════════════════════════════════

        // L21 — Open beauty
        make(
            holes: [
                CGRect(x: 0.30, y: 0.42, width: 0.40, height: 0.18),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.18, y: 0.50),
                UnitPoint(x: 0.82, y: 0.50),
                UnitPoint(x: 0.50, y: 0.25),
            ]
        ),

        // L22 — Parallel paths
        make(
            holes: [
                CGRect(x: 0.30, y: 0.20, width: 0.08, height: 0.55),
                CGRect(x: 0.62, y: 0.20, width: 0.08, height: 0.55),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.20, y: 0.45),
                UnitPoint(x: 0.50, y: 0.45),
                UnitPoint(x: 0.80, y: 0.45),
            ]
        ),

        // L23 — Gentle long S-curve
        make(
            holes: [
                CGRect(x: 0.12, y: 0.30, width: 0.45, height: 0.07),
                CGRect(x: 0.43, y: 0.50, width: 0.45, height: 0.07),
                CGRect(x: 0.12, y: 0.70, width: 0.45, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.80, y: 0.82),
                UnitPoint(x: 0.20, y: 0.62),
                UnitPoint(x: 0.80, y: 0.40),
            ]
        ),

        // L24 — Corner sentinels
        make(
            holes: [
                CGRect(x: 0.18, y: 0.22, width: 0.20, height: 0.10),
                CGRect(x: 0.62, y: 0.22, width: 0.20, height: 0.10),
                CGRect(x: 0.18, y: 0.68, width: 0.20, height: 0.10),
                CGRect(x: 0.62, y: 0.68, width: 0.20, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.20, y: 0.50),
                UnitPoint(x: 0.80, y: 0.50),
            ]
        ),

        // L25 — Pinwheel
        make(
            holes: [
                CGRect(x: 0.42, y: 0.20, width: 0.30, height: 0.08),
                CGRect(x: 0.68, y: 0.42, width: 0.20, height: 0.30),
                CGRect(x: 0.28, y: 0.72, width: 0.30, height: 0.08),
                CGRect(x: 0.12, y: 0.28, width: 0.20, height: 0.30),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.20, y: 0.78),
                UnitPoint(x: 0.80, y: 0.22),
            ]
        ),

        // L26 — Long descending zigzag
        make(
            holes: [
                CGRect(x: 0.15, y: 0.20, width: 0.40, height: 0.06),
                CGRect(x: 0.45, y: 0.35, width: 0.40, height: 0.06),
                CGRect(x: 0.15, y: 0.50, width: 0.40, height: 0.06),
                CGRect(x: 0.45, y: 0.65, width: 0.40, height: 0.06),
                CGRect(x: 0.15, y: 0.80, width: 0.40, height: 0.06),
            ],
            start: UnitPoint(x: 0.50, y: 0.92),
            goal:  UnitPoint(x: 0.50, y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.72),
                UnitPoint(x: 0.22, y: 0.42),
                UnitPoint(x: 0.78, y: 0.28),
            ]
        ),

        // L27 — Two-tier gauntlet
        make(
            holes: [
                CGRect(x: 0.18, y: 0.30, width: 0.18, height: 0.08),
                CGRect(x: 0.44, y: 0.30, width: 0.18, height: 0.08),
                CGRect(x: 0.66, y: 0.30, width: 0.18, height: 0.08),
                CGRect(x: 0.30, y: 0.55, width: 0.18, height: 0.08),
                CGRect(x: 0.52, y: 0.55, width: 0.18, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.18, y: 0.45),
                UnitPoint(x: 0.78, y: 0.45),
                UnitPoint(x: 0.50, y: 0.70),
            ]
        ),

        // L28 — River flow (diagonal band)
        make(
            holes: [
                CGRect(x: 0.12, y: 0.30, width: 0.20, height: 0.08),
                CGRect(x: 0.30, y: 0.42, width: 0.20, height: 0.08),
                CGRect(x: 0.48, y: 0.54, width: 0.20, height: 0.08),
                CGRect(x: 0.66, y: 0.66, width: 0.22, height: 0.08),
            ],
            start: UnitPoint(x: 0.18, y: 0.88),
            goal:  UnitPoint(x: 0.82, y: 0.18),
            coins: [
                UnitPoint(x: 0.30, y: 0.78),
                UnitPoint(x: 0.50, y: 0.42),
                UnitPoint(x: 0.78, y: 0.32),
            ]
        ),

        // L29 — Tight maze
        make(
            holes: [
                CGRect(x: 0.12, y: 0.25, width: 0.40, height: 0.06),
                CGRect(x: 0.60, y: 0.25, width: 0.28, height: 0.06),
                CGRect(x: 0.30, y: 0.40, width: 0.40, height: 0.06),
                CGRect(x: 0.12, y: 0.55, width: 0.30, height: 0.06),
                CGRect(x: 0.50, y: 0.55, width: 0.38, height: 0.06),
                CGRect(x: 0.30, y: 0.70, width: 0.40, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.20, y: 0.80),
                UnitPoint(x: 0.50, y: 0.48),
                UnitPoint(x: 0.80, y: 0.20),
            ]
        ),

        // L30 — Twilight finale
        make(
            holes: [
                CGRect(x: 0.16, y: 0.18, width: 0.16, height: 0.10),
                CGRect(x: 0.68, y: 0.18, width: 0.16, height: 0.10),
                CGRect(x: 0.40, y: 0.30, width: 0.20, height: 0.08),
                CGRect(x: 0.16, y: 0.46, width: 0.22, height: 0.10),
                CGRect(x: 0.62, y: 0.46, width: 0.22, height: 0.10),
                CGRect(x: 0.40, y: 0.62, width: 0.20, height: 0.08),
                CGRect(x: 0.16, y: 0.76, width: 0.16, height: 0.08),
                CGRect(x: 0.68, y: 0.76, width: 0.16, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.18),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.82),
            ]
        ),

        // ═══════════════════════════════════════════════════════════════════
        // EMBER — levels 31-40
        // Warmer mood, denser hazard fields, sharper precision required.
        // ═══════════════════════════════════════════════════════════════════

        // L31 — Heavy intro
        make(
            holes: [
                CGRect(x: 0.20, y: 0.30, width: 0.18, height: 0.10),
                CGRect(x: 0.42, y: 0.30, width: 0.18, height: 0.10),
                CGRect(x: 0.64, y: 0.30, width: 0.16, height: 0.10),
                CGRect(x: 0.30, y: 0.55, width: 0.18, height: 0.10),
                CGRect(x: 0.52, y: 0.55, width: 0.18, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.18, y: 0.50),
                UnitPoint(x: 0.50, y: 0.72),
                UnitPoint(x: 0.50, y: 0.42),
            ]
        ),

        // L32 — Stair descent (6 steps)
        make(
            holes: [
                CGRect(x: 0.55, y: 0.16, width: 0.30, height: 0.06),
                CGRect(x: 0.15, y: 0.28, width: 0.30, height: 0.06),
                CGRect(x: 0.55, y: 0.40, width: 0.30, height: 0.06),
                CGRect(x: 0.15, y: 0.52, width: 0.30, height: 0.06),
                CGRect(x: 0.55, y: 0.64, width: 0.30, height: 0.06),
                CGRect(x: 0.15, y: 0.76, width: 0.30, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.78, y: 0.84),
                UnitPoint(x: 0.78, y: 0.48),
                UnitPoint(x: 0.78, y: 0.12),
            ]
        ),

        // L33 — Gauntlet maze
        make(
            holes: [
                CGRect(x: 0.18, y: 0.22, width: 0.10, height: 0.12),
                CGRect(x: 0.36, y: 0.22, width: 0.10, height: 0.12),
                CGRect(x: 0.54, y: 0.22, width: 0.10, height: 0.12),
                CGRect(x: 0.72, y: 0.22, width: 0.10, height: 0.12),
                CGRect(x: 0.27, y: 0.42, width: 0.10, height: 0.12),
                CGRect(x: 0.45, y: 0.42, width: 0.10, height: 0.12),
                CGRect(x: 0.63, y: 0.42, width: 0.10, height: 0.12),
                CGRect(x: 0.18, y: 0.62, width: 0.10, height: 0.12),
                CGRect(x: 0.36, y: 0.62, width: 0.10, height: 0.12),
                CGRect(x: 0.54, y: 0.62, width: 0.10, height: 0.12),
                CGRect(x: 0.72, y: 0.62, width: 0.10, height: 0.12),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.50, y: 0.36),
                UnitPoint(x: 0.50, y: 0.56),
                UnitPoint(x: 0.50, y: 0.76),
            ]
        ),

        // L34 — Diamond grid
        make(
            holes: [
                CGRect(x: 0.42, y: 0.20, width: 0.16, height: 0.08),
                CGRect(x: 0.22, y: 0.36, width: 0.16, height: 0.08),
                CGRect(x: 0.62, y: 0.36, width: 0.16, height: 0.08),
                CGRect(x: 0.42, y: 0.50, width: 0.16, height: 0.08),
                CGRect(x: 0.22, y: 0.64, width: 0.16, height: 0.08),
                CGRect(x: 0.62, y: 0.64, width: 0.16, height: 0.08),
                CGRect(x: 0.42, y: 0.78, width: 0.16, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.30),
                UnitPoint(x: 0.50, y: 0.58),
                UnitPoint(x: 0.50, y: 0.86),
            ]
        ),

        // L35 — Forced single corridor
        make(
            holes: [
                CGRect(x: 0.12, y: 0.18, width: 0.32, height: 0.65),
                CGRect(x: 0.56, y: 0.18, width: 0.32, height: 0.65),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.78),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.20),
            ]
        ),

        // L36 — Precision threading
        make(
            holes: [
                CGRect(x: 0.12, y: 0.22, width: 0.34, height: 0.16),
                CGRect(x: 0.54, y: 0.22, width: 0.34, height: 0.16),
                CGRect(x: 0.30, y: 0.46, width: 0.40, height: 0.10),
                CGRect(x: 0.12, y: 0.66, width: 0.34, height: 0.16),
                CGRect(x: 0.54, y: 0.66, width: 0.34, height: 0.16),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.82),
                UnitPoint(x: 0.18, y: 0.50),
                UnitPoint(x: 0.50, y: 0.18),
            ]
        ),

        // L37 — Spiral
        make(
            holes: [
                CGRect(x: 0.12, y: 0.20, width: 0.55, height: 0.07),
                CGRect(x: 0.60, y: 0.27, width: 0.10, height: 0.45),
                CGRect(x: 0.30, y: 0.65, width: 0.40, height: 0.07),
                CGRect(x: 0.30, y: 0.40, width: 0.10, height: 0.25),
                CGRect(x: 0.40, y: 0.40, width: 0.18, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.50),  // goal in centre of spiral
            coins: [
                UnitPoint(x: 0.78, y: 0.85),
                UnitPoint(x: 0.18, y: 0.50),
                UnitPoint(x: 0.20, y: 0.30),
            ]
        ),

        // L38 — Dual-route puzzle
        make(
            holes: [
                CGRect(x: 0.40, y: 0.18, width: 0.20, height: 0.65),
                CGRect(x: 0.15, y: 0.40, width: 0.16, height: 0.10),
                CGRect(x: 0.69, y: 0.40, width: 0.16, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.22, y: 0.30),
                UnitPoint(x: 0.78, y: 0.30),
                UnitPoint(x: 0.50, y: 0.92),  // start area
            ]
        ),

        // L39 — Hourglass (tighter than L16)
        make(
            holes: [
                CGRect(x: 0.12, y: 0.30, width: 0.36, height: 0.10),
                CGRect(x: 0.52, y: 0.30, width: 0.36, height: 0.10),
                CGRect(x: 0.18, y: 0.50, width: 0.28, height: 0.10),
                CGRect(x: 0.54, y: 0.50, width: 0.28, height: 0.10),
                CGRect(x: 0.12, y: 0.70, width: 0.36, height: 0.10),
                CGRect(x: 0.52, y: 0.70, width: 0.36, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.82),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.18),
            ]
        ),

        // L40 — Ember finale
        make(
            holes: [
                CGRect(x: 0.18, y: 0.18, width: 0.14, height: 0.08),
                CGRect(x: 0.42, y: 0.18, width: 0.14, height: 0.08),
                CGRect(x: 0.66, y: 0.18, width: 0.14, height: 0.08),
                CGRect(x: 0.30, y: 0.32, width: 0.14, height: 0.08),
                CGRect(x: 0.54, y: 0.32, width: 0.14, height: 0.08),
                CGRect(x: 0.18, y: 0.46, width: 0.14, height: 0.08),
                CGRect(x: 0.42, y: 0.46, width: 0.14, height: 0.08),
                CGRect(x: 0.66, y: 0.46, width: 0.14, height: 0.08),
                CGRect(x: 0.30, y: 0.60, width: 0.14, height: 0.08),
                CGRect(x: 0.54, y: 0.60, width: 0.14, height: 0.08),
                CGRect(x: 0.18, y: 0.74, width: 0.14, height: 0.08),
                CGRect(x: 0.42, y: 0.74, width: 0.14, height: 0.08),
                CGRect(x: 0.66, y: 0.74, width: 0.14, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.25),
                UnitPoint(x: 0.50, y: 0.53),
                UnitPoint(x: 0.50, y: 0.81),
            ]
        ),

        // ═══════════════════════════════════════════════════════════════════
        // AURORA — levels 41-50
        // Climactic finale to World 1.  Floor shimmers via Canvas overlay.
        // ═══════════════════════════════════════════════════════════════════

        // L41 — Open Aurora (show off the shimmer)
        make(
            holes: [
                CGRect(x: 0.40, y: 0.46, width: 0.20, height: 0.16),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.20, y: 0.30),
                UnitPoint(x: 0.80, y: 0.30),
                UnitPoint(x: 0.50, y: 0.72),
            ]
        ),

        // L42 — Ascending zigzag
        make(
            holes: [
                CGRect(x: 0.55, y: 0.20, width: 0.30, height: 0.06),
                CGRect(x: 0.15, y: 0.35, width: 0.30, height: 0.06),
                CGRect(x: 0.55, y: 0.50, width: 0.30, height: 0.06),
                CGRect(x: 0.15, y: 0.65, width: 0.30, height: 0.06),
                CGRect(x: 0.55, y: 0.80, width: 0.30, height: 0.06),
            ],
            start: UnitPoint(x: 0.20, y: 0.90),
            goal:  UnitPoint(x: 0.80, y: 0.10),
            coins: [
                UnitPoint(x: 0.20, y: 0.45),
                UnitPoint(x: 0.80, y: 0.45),
                UnitPoint(x: 0.20, y: 0.18),
            ]
        ),

        // L43 — Starfield (many small holes)
        make(
            holes: [
                CGRect(x: 0.20, y: 0.20, width: 0.08, height: 0.08),
                CGRect(x: 0.40, y: 0.22, width: 0.08, height: 0.08),
                CGRect(x: 0.60, y: 0.20, width: 0.08, height: 0.08),
                CGRect(x: 0.74, y: 0.30, width: 0.08, height: 0.08),
                CGRect(x: 0.30, y: 0.36, width: 0.08, height: 0.08),
                CGRect(x: 0.50, y: 0.40, width: 0.08, height: 0.08),
                CGRect(x: 0.18, y: 0.48, width: 0.08, height: 0.08),
                CGRect(x: 0.65, y: 0.50, width: 0.08, height: 0.08),
                CGRect(x: 0.40, y: 0.58, width: 0.08, height: 0.08),
                CGRect(x: 0.22, y: 0.66, width: 0.08, height: 0.08),
                CGRect(x: 0.54, y: 0.68, width: 0.08, height: 0.08),
                CGRect(x: 0.74, y: 0.72, width: 0.08, height: 0.08),
                CGRect(x: 0.40, y: 0.78, width: 0.08, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.25),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.85),
            ]
        ),

        // L44 — Nebula (few large soft hazards)
        make(
            holes: [
                CGRect(x: 0.16, y: 0.24, width: 0.30, height: 0.20),
                CGRect(x: 0.58, y: 0.30, width: 0.30, height: 0.20),
                CGRect(x: 0.18, y: 0.56, width: 0.30, height: 0.22),
                CGRect(x: 0.58, y: 0.60, width: 0.30, height: 0.22),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.78),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.20),
            ]
        ),

        // L45 — Prism: diagonal-ish hazards
        make(
            holes: [
                CGRect(x: 0.12, y: 0.25, width: 0.28, height: 0.07),
                CGRect(x: 0.34, y: 0.36, width: 0.28, height: 0.07),
                CGRect(x: 0.56, y: 0.47, width: 0.32, height: 0.07),
                CGRect(x: 0.34, y: 0.58, width: 0.28, height: 0.07),
                CGRect(x: 0.12, y: 0.69, width: 0.28, height: 0.07),
            ],
            start: UnitPoint(x: 0.80, y: 0.90),
            goal:  UnitPoint(x: 0.20, y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.74),
                UnitPoint(x: 0.50, y: 0.42),
                UnitPoint(x: 0.20, y: 0.32),
            ]
        ),

        // L46 — Void crossing (massive central hole)
        make(
            holes: [
                CGRect(x: 0.22, y: 0.28, width: 0.56, height: 0.44),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.16, y: 0.50),
                UnitPoint(x: 0.84, y: 0.50),
                UnitPoint(x: 0.50, y: 0.16),
            ]
        ),

        // L47 — Aurora dance (curved feel via staggered holes)
        make(
            holes: [
                CGRect(x: 0.62, y: 0.20, width: 0.22, height: 0.07),
                CGRect(x: 0.40, y: 0.32, width: 0.22, height: 0.07),
                CGRect(x: 0.18, y: 0.42, width: 0.20, height: 0.07),
                CGRect(x: 0.18, y: 0.55, width: 0.20, height: 0.07),
                CGRect(x: 0.40, y: 0.65, width: 0.22, height: 0.07),
                CGRect(x: 0.62, y: 0.75, width: 0.22, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.78, y: 0.50),
                UnitPoint(x: 0.50, y: 0.48),
                UnitPoint(x: 0.50, y: 0.18),
            ]
        ),

        // L48 — Tempest (dense chaotic)
        make(
            holes: [
                CGRect(x: 0.16, y: 0.18, width: 0.18, height: 0.07),
                CGRect(x: 0.42, y: 0.22, width: 0.18, height: 0.07),
                CGRect(x: 0.66, y: 0.16, width: 0.18, height: 0.07),
                CGRect(x: 0.20, y: 0.34, width: 0.18, height: 0.07),
                CGRect(x: 0.50, y: 0.36, width: 0.18, height: 0.07),
                CGRect(x: 0.30, y: 0.48, width: 0.18, height: 0.07),
                CGRect(x: 0.60, y: 0.50, width: 0.18, height: 0.07),
                CGRect(x: 0.16, y: 0.62, width: 0.18, height: 0.07),
                CGRect(x: 0.46, y: 0.62, width: 0.18, height: 0.07),
                CGRect(x: 0.70, y: 0.66, width: 0.18, height: 0.07),
                CGRect(x: 0.28, y: 0.78, width: 0.18, height: 0.07),
                CGRect(x: 0.56, y: 0.78, width: 0.18, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.28),
                UnitPoint(x: 0.50, y: 0.55),
                UnitPoint(x: 0.50, y: 0.85),
            ]
        ),

        // L49 — Convergence (paths funnel to tight goal)
        make(
            holes: [
                CGRect(x: 0.30, y: 0.20, width: 0.40, height: 0.06),
                CGRect(x: 0.18, y: 0.35, width: 0.18, height: 0.06),
                CGRect(x: 0.64, y: 0.35, width: 0.18, height: 0.06),
                CGRect(x: 0.18, y: 0.50, width: 0.30, height: 0.06),
                CGRect(x: 0.52, y: 0.50, width: 0.30, height: 0.06),
                CGRect(x: 0.32, y: 0.65, width: 0.36, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.20, y: 0.80),
                UnitPoint(x: 0.80, y: 0.80),
                UnitPoint(x: 0.50, y: 0.30),
            ]
        ),

        // L50 — WORLD 1 FINALE
        // The boss of World 1.  Combines every learned pattern into one
        // demanding course.  Coin placements punish greed.
        make(
            holes: [
                CGRect(x: 0.18, y: 0.16, width: 0.14, height: 0.08),
                CGRect(x: 0.38, y: 0.16, width: 0.24, height: 0.08),
                CGRect(x: 0.68, y: 0.16, width: 0.14, height: 0.08),
                CGRect(x: 0.30, y: 0.30, width: 0.16, height: 0.08),
                CGRect(x: 0.54, y: 0.30, width: 0.16, height: 0.08),
                CGRect(x: 0.16, y: 0.44, width: 0.20, height: 0.08),
                CGRect(x: 0.44, y: 0.44, width: 0.12, height: 0.08),
                CGRect(x: 0.64, y: 0.44, width: 0.20, height: 0.08),
                CGRect(x: 0.30, y: 0.58, width: 0.16, height: 0.08),
                CGRect(x: 0.54, y: 0.58, width: 0.16, height: 0.08),
                CGRect(x: 0.18, y: 0.72, width: 0.14, height: 0.08),
                CGRect(x: 0.38, y: 0.72, width: 0.24, height: 0.08),
                CGRect(x: 0.68, y: 0.72, width: 0.14, height: 0.08),
                CGRect(x: 0.40, y: 0.84, width: 0.20, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.94),
            goal:  UnitPoint(x: 0.5, y: 0.06),
            coins: [
                UnitPoint(x: 0.50, y: 0.25),   // mid-flight near top
                UnitPoint(x: 0.50, y: 0.51),   // dead centre
                UnitPoint(x: 0.50, y: 0.78),   // near start
            ]
        ),

        // ═══════════════════════════════════════════════════════════════════
        // WORLD 2 — PAPER (levels 51-100)
        // The ball now leaves a graphite trail behind it.
        // ═══════════════════════════════════════════════════════════════════

        // ── NOTEBOOK (L51-60) — ruled paper, gentle introduction to World 2 ─

        // L51 — Fresh page intro
        make(
            holes: [
                CGRect(x: 0.36, y: 0.42, width: 0.28, height: 0.16),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.18, y: 0.50),
                UnitPoint(x: 0.82, y: 0.50),
                UnitPoint(x: 0.50, y: 0.75),
            ]
        ),

        // L52 — Bar gates
        make(
            holes: [
                CGRect(x: 0.15, y: 0.30, width: 0.55, height: 0.07),
                CGRect(x: 0.30, y: 0.55, width: 0.55, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.78, y: 0.42),
                UnitPoint(x: 0.22, y: 0.66),
                UnitPoint(x: 0.50, y: 0.22),
            ]
        ),

        // L53 — Zigzag
        make(
            holes: [
                CGRect(x: 0.18, y: 0.30, width: 0.32, height: 0.08),
                CGRect(x: 0.50, y: 0.48, width: 0.32, height: 0.08),
                CGRect(x: 0.18, y: 0.66, width: 0.32, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.78, y: 0.72),
                UnitPoint(x: 0.30, y: 0.55),
                UnitPoint(x: 0.78, y: 0.38),
            ]
        ),

        // L54 — Three-row gauntlet
        make(
            holes: [
                CGRect(x: 0.18, y: 0.26, width: 0.16, height: 0.08),
                CGRect(x: 0.42, y: 0.26, width: 0.16, height: 0.08),
                CGRect(x: 0.66, y: 0.26, width: 0.16, height: 0.08),
                CGRect(x: 0.30, y: 0.48, width: 0.16, height: 0.08),
                CGRect(x: 0.54, y: 0.48, width: 0.16, height: 0.08),
                CGRect(x: 0.18, y: 0.70, width: 0.16, height: 0.08),
                CGRect(x: 0.42, y: 0.70, width: 0.16, height: 0.08),
                CGRect(x: 0.66, y: 0.70, width: 0.16, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.84),
                UnitPoint(x: 0.50, y: 0.38),
                UnitPoint(x: 0.50, y: 0.60),
            ]
        ),

        // L55 — Pinch point
        make(
            holes: [
                CGRect(x: 0.12, y: 0.35, width: 0.36, height: 0.10),
                CGRect(x: 0.52, y: 0.35, width: 0.36, height: 0.10),
                CGRect(x: 0.20, y: 0.55, width: 0.28, height: 0.10),
                CGRect(x: 0.52, y: 0.55, width: 0.28, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.78),
                UnitPoint(x: 0.50, y: 0.22),
            ]
        ),

        // L56 — Dual route around centre block
        make(
            holes: [
                CGRect(x: 0.36, y: 0.25, width: 0.28, height: 0.50),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.20, y: 0.50),
                UnitPoint(x: 0.80, y: 0.50),
                UnitPoint(x: 0.50, y: 0.88),
            ]
        ),

        // L57 — Tight maze
        make(
            holes: [
                CGRect(x: 0.12, y: 0.22, width: 0.40, height: 0.07),
                CGRect(x: 0.60, y: 0.22, width: 0.28, height: 0.07),
                CGRect(x: 0.30, y: 0.36, width: 0.40, height: 0.07),
                CGRect(x: 0.12, y: 0.50, width: 0.30, height: 0.07),
                CGRect(x: 0.50, y: 0.50, width: 0.38, height: 0.07),
                CGRect(x: 0.30, y: 0.64, width: 0.40, height: 0.07),
                CGRect(x: 0.12, y: 0.78, width: 0.40, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.82),
                UnitPoint(x: 0.20, y: 0.43),
                UnitPoint(x: 0.78, y: 0.18),
            ]
        ),

        // L58 — Scattered ink-blot holes
        make(
            holes: [
                CGRect(x: 0.22, y: 0.22, width: 0.10, height: 0.07),
                CGRect(x: 0.50, y: 0.24, width: 0.10, height: 0.07),
                CGRect(x: 0.72, y: 0.30, width: 0.10, height: 0.07),
                CGRect(x: 0.34, y: 0.38, width: 0.10, height: 0.07),
                CGRect(x: 0.58, y: 0.44, width: 0.10, height: 0.07),
                CGRect(x: 0.22, y: 0.50, width: 0.10, height: 0.07),
                CGRect(x: 0.68, y: 0.58, width: 0.10, height: 0.07),
                CGRect(x: 0.40, y: 0.62, width: 0.10, height: 0.07),
                CGRect(x: 0.22, y: 0.70, width: 0.10, height: 0.07),
                CGRect(x: 0.62, y: 0.74, width: 0.10, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.82),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.20),
            ]
        ),

        // L59 — Hourglass
        make(
            holes: [
                CGRect(x: 0.12, y: 0.32, width: 0.30, height: 0.10),
                CGRect(x: 0.58, y: 0.32, width: 0.30, height: 0.10),
                CGRect(x: 0.18, y: 0.54, width: 0.26, height: 0.10),
                CGRect(x: 0.56, y: 0.54, width: 0.26, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.48),
                UnitPoint(x: 0.50, y: 0.76),
                UnitPoint(x: 0.50, y: 0.20),
            ]
        ),

        // L60 — Notebook finale
        make(
            holes: [
                CGRect(x: 0.18, y: 0.18, width: 0.20, height: 0.08),
                CGRect(x: 0.62, y: 0.18, width: 0.20, height: 0.08),
                CGRect(x: 0.40, y: 0.30, width: 0.20, height: 0.08),
                CGRect(x: 0.16, y: 0.44, width: 0.22, height: 0.08),
                CGRect(x: 0.62, y: 0.44, width: 0.22, height: 0.08),
                CGRect(x: 0.40, y: 0.58, width: 0.20, height: 0.08),
                CGRect(x: 0.18, y: 0.72, width: 0.20, height: 0.08),
                CGRect(x: 0.62, y: 0.72, width: 0.20, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.22),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.80),
            ]
        ),

        // ── GRAPH (L61-70) — green grid, sharper geometric layouts ─────────

        // L61 — Plus
        make(
            holes: [
                CGRect(x: 0.40, y: 0.24, width: 0.20, height: 0.12),
                CGRect(x: 0.18, y: 0.44, width: 0.20, height: 0.12),
                CGRect(x: 0.62, y: 0.44, width: 0.20, height: 0.12),
                CGRect(x: 0.40, y: 0.64, width: 0.20, height: 0.12),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.18, y: 0.30),
                UnitPoint(x: 0.82, y: 0.70),
            ]
        ),

        // L62 — Lattice maze
        make(
            holes: [
                CGRect(x: 0.18, y: 0.24, width: 0.08, height: 0.45),
                CGRect(x: 0.36, y: 0.36, width: 0.08, height: 0.45),
                CGRect(x: 0.54, y: 0.24, width: 0.08, height: 0.45),
                CGRect(x: 0.72, y: 0.36, width: 0.08, height: 0.45),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.45, y: 0.78),
                UnitPoint(x: 0.63, y: 0.20),
                UnitPoint(x: 0.27, y: 0.30),
            ]
        ),

        // L63 — Grid intersection
        make(
            holes: [
                CGRect(x: 0.18, y: 0.30, width: 0.64, height: 0.08),
                CGRect(x: 0.18, y: 0.62, width: 0.64, height: 0.08),
                CGRect(x: 0.42, y: 0.18, width: 0.08, height: 0.62),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.20, y: 0.48),
                UnitPoint(x: 0.80, y: 0.48),
                UnitPoint(x: 0.50, y: 0.84),
            ]
        ),

        // L64 — Stair right
        make(
            holes: [
                CGRect(x: 0.15, y: 0.20, width: 0.20, height: 0.06),
                CGRect(x: 0.30, y: 0.34, width: 0.20, height: 0.06),
                CGRect(x: 0.45, y: 0.48, width: 0.20, height: 0.06),
                CGRect(x: 0.60, y: 0.62, width: 0.20, height: 0.06),
                CGRect(x: 0.45, y: 0.76, width: 0.20, height: 0.06),
            ],
            start: UnitPoint(x: 0.18, y: 0.90),
            goal:  UnitPoint(x: 0.82, y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.78),
                UnitPoint(x: 0.20, y: 0.50),
                UnitPoint(x: 0.78, y: 0.42),
            ]
        ),

        // L65 — Branching corridors
        make(
            holes: [
                CGRect(x: 0.30, y: 0.25, width: 0.10, height: 0.50),
                CGRect(x: 0.60, y: 0.25, width: 0.10, height: 0.50),
                CGRect(x: 0.42, y: 0.45, width: 0.18, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.20, y: 0.50),
                UnitPoint(x: 0.80, y: 0.50),
                UnitPoint(x: 0.50, y: 0.28),
            ]
        ),

        // L66 — Dense maze
        make(
            holes: [
                CGRect(x: 0.12, y: 0.22, width: 0.30, height: 0.05),
                CGRect(x: 0.50, y: 0.22, width: 0.38, height: 0.05),
                CGRect(x: 0.30, y: 0.32, width: 0.40, height: 0.05),
                CGRect(x: 0.12, y: 0.42, width: 0.20, height: 0.05),
                CGRect(x: 0.40, y: 0.42, width: 0.20, height: 0.05),
                CGRect(x: 0.68, y: 0.42, width: 0.20, height: 0.05),
                CGRect(x: 0.30, y: 0.52, width: 0.40, height: 0.05),
                CGRect(x: 0.12, y: 0.62, width: 0.38, height: 0.05),
                CGRect(x: 0.58, y: 0.62, width: 0.30, height: 0.05),
                CGRect(x: 0.30, y: 0.72, width: 0.40, height: 0.05),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.20, y: 0.80),
                UnitPoint(x: 0.50, y: 0.47),
                UnitPoint(x: 0.80, y: 0.18),
            ]
        ),

        // L67 — Tight gap rows
        make(
            holes: [
                CGRect(x: 0.12, y: 0.22, width: 0.36, height: 0.06),
                CGRect(x: 0.56, y: 0.22, width: 0.32, height: 0.06),
                CGRect(x: 0.20, y: 0.36, width: 0.32, height: 0.06),
                CGRect(x: 0.60, y: 0.36, width: 0.28, height: 0.06),
                CGRect(x: 0.12, y: 0.50, width: 0.32, height: 0.06),
                CGRect(x: 0.56, y: 0.50, width: 0.32, height: 0.06),
                CGRect(x: 0.20, y: 0.64, width: 0.32, height: 0.06),
                CGRect(x: 0.60, y: 0.64, width: 0.28, height: 0.06),
                CGRect(x: 0.12, y: 0.78, width: 0.32, height: 0.06),
                CGRect(x: 0.56, y: 0.78, width: 0.32, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.86),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.14),
            ]
        ),

        // L68 — Boxed spiral
        make(
            holes: [
                CGRect(x: 0.18, y: 0.20, width: 0.64, height: 0.06),
                CGRect(x: 0.74, y: 0.26, width: 0.08, height: 0.45),
                CGRect(x: 0.32, y: 0.65, width: 0.50, height: 0.06),
                CGRect(x: 0.32, y: 0.36, width: 0.08, height: 0.29),
                CGRect(x: 0.40, y: 0.36, width: 0.32, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.50),  // centre of spiral
            coins: [
                UnitPoint(x: 0.84, y: 0.80),
                UnitPoint(x: 0.20, y: 0.50),
                UnitPoint(x: 0.20, y: 0.30),
            ]
        ),

        // L69 — Precision threading
        make(
            holes: [
                CGRect(x: 0.12, y: 0.22, width: 0.32, height: 0.16),
                CGRect(x: 0.56, y: 0.22, width: 0.32, height: 0.16),
                CGRect(x: 0.32, y: 0.44, width: 0.36, height: 0.10),
                CGRect(x: 0.12, y: 0.60, width: 0.32, height: 0.16),
                CGRect(x: 0.56, y: 0.60, width: 0.32, height: 0.16),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.82),
                UnitPoint(x: 0.50, y: 0.30),
                UnitPoint(x: 0.50, y: 0.16),
            ]
        ),

        // L70 — Graph finale
        make(
            holes: [
                CGRect(x: 0.18, y: 0.16, width: 0.14, height: 0.08),
                CGRect(x: 0.40, y: 0.16, width: 0.14, height: 0.08),
                CGRect(x: 0.62, y: 0.16, width: 0.14, height: 0.08),
                CGRect(x: 0.30, y: 0.30, width: 0.14, height: 0.08),
                CGRect(x: 0.54, y: 0.30, width: 0.14, height: 0.08),
                CGRect(x: 0.18, y: 0.44, width: 0.14, height: 0.08),
                CGRect(x: 0.40, y: 0.44, width: 0.14, height: 0.08),
                CGRect(x: 0.62, y: 0.44, width: 0.14, height: 0.08),
                CGRect(x: 0.30, y: 0.58, width: 0.14, height: 0.08),
                CGRect(x: 0.54, y: 0.58, width: 0.14, height: 0.08),
                CGRect(x: 0.18, y: 0.72, width: 0.14, height: 0.08),
                CGRect(x: 0.40, y: 0.72, width: 0.14, height: 0.08),
                CGRect(x: 0.62, y: 0.72, width: 0.14, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.24),
                UnitPoint(x: 0.50, y: 0.52),
                UnitPoint(x: 0.50, y: 0.80),
            ]
        ),

        // ── PARCHMENT (L71-80) — aged ink, slightly harder, mysterious ────

        // L71 — Open with single large blot
        make(
            holes: [
                CGRect(x: 0.30, y: 0.36, width: 0.40, height: 0.28),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.18, y: 0.50),
                UnitPoint(x: 0.82, y: 0.50),
                UnitPoint(x: 0.50, y: 0.78),
            ]
        ),

        // L72 — Scattered blots
        make(
            holes: [
                CGRect(x: 0.20, y: 0.22, width: 0.16, height: 0.10),
                CGRect(x: 0.62, y: 0.20, width: 0.18, height: 0.10),
                CGRect(x: 0.42, y: 0.36, width: 0.16, height: 0.10),
                CGRect(x: 0.18, y: 0.50, width: 0.18, height: 0.10),
                CGRect(x: 0.62, y: 0.52, width: 0.18, height: 0.10),
                CGRect(x: 0.40, y: 0.66, width: 0.18, height: 0.10),
                CGRect(x: 0.22, y: 0.78, width: 0.18, height: 0.08),
                CGRect(x: 0.62, y: 0.78, width: 0.18, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.86),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.16),
            ]
        ),

        // L73 — Zigzag bars
        make(
            holes: [
                CGRect(x: 0.15, y: 0.25, width: 0.45, height: 0.08),
                CGRect(x: 0.40, y: 0.42, width: 0.45, height: 0.08),
                CGRect(x: 0.15, y: 0.59, width: 0.45, height: 0.08),
                CGRect(x: 0.40, y: 0.76, width: 0.45, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.20, y: 0.85),
                UnitPoint(x: 0.78, y: 0.51),
                UnitPoint(x: 0.20, y: 0.34),
            ]
        ),

        // L74 — Tight hourglass
        make(
            holes: [
                CGRect(x: 0.12, y: 0.28, width: 0.36, height: 0.10),
                CGRect(x: 0.52, y: 0.28, width: 0.36, height: 0.10),
                CGRect(x: 0.20, y: 0.46, width: 0.24, height: 0.10),
                CGRect(x: 0.56, y: 0.46, width: 0.24, height: 0.10),
                CGRect(x: 0.12, y: 0.64, width: 0.36, height: 0.10),
                CGRect(x: 0.52, y: 0.64, width: 0.36, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.82),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.18),
            ]
        ),

        // L75 — Forced corridor
        make(
            holes: [
                CGRect(x: 0.12, y: 0.20, width: 0.34, height: 0.60),
                CGRect(x: 0.54, y: 0.20, width: 0.34, height: 0.60),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.80),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.20),
            ]
        ),

        // L76 — Dense scatter
        make(
            holes: [
                CGRect(x: 0.18, y: 0.18, width: 0.12, height: 0.08),
                CGRect(x: 0.42, y: 0.22, width: 0.12, height: 0.08),
                CGRect(x: 0.66, y: 0.18, width: 0.12, height: 0.08),
                CGRect(x: 0.28, y: 0.34, width: 0.12, height: 0.08),
                CGRect(x: 0.54, y: 0.36, width: 0.12, height: 0.08),
                CGRect(x: 0.18, y: 0.48, width: 0.12, height: 0.08),
                CGRect(x: 0.66, y: 0.50, width: 0.12, height: 0.08),
                CGRect(x: 0.42, y: 0.56, width: 0.12, height: 0.08),
                CGRect(x: 0.28, y: 0.70, width: 0.12, height: 0.08),
                CGRect(x: 0.54, y: 0.72, width: 0.12, height: 0.08),
                CGRect(x: 0.18, y: 0.82, width: 0.12, height: 0.07),
                CGRect(x: 0.66, y: 0.82, width: 0.12, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.95),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.92),
                UnitPoint(x: 0.50, y: 0.55),
                UnitPoint(x: 0.50, y: 0.20),
            ]
        ),

        // L77 — Weaving path
        make(
            holes: [
                CGRect(x: 0.30, y: 0.22, width: 0.55, height: 0.06),
                CGRect(x: 0.15, y: 0.36, width: 0.55, height: 0.06),
                CGRect(x: 0.30, y: 0.50, width: 0.55, height: 0.06),
                CGRect(x: 0.15, y: 0.64, width: 0.55, height: 0.06),
                CGRect(x: 0.30, y: 0.78, width: 0.55, height: 0.06),
            ],
            start: UnitPoint(x: 0.18, y: 0.92),
            goal:  UnitPoint(x: 0.82, y: 0.10),
            coins: [
                UnitPoint(x: 0.20, y: 0.71),
                UnitPoint(x: 0.80, y: 0.57),
                UnitPoint(x: 0.20, y: 0.29),
            ]
        ),

        // L78 — Maze
        make(
            holes: [
                CGRect(x: 0.12, y: 0.20, width: 0.50, height: 0.06),
                CGRect(x: 0.70, y: 0.20, width: 0.18, height: 0.06),
                CGRect(x: 0.30, y: 0.32, width: 0.50, height: 0.06),
                CGRect(x: 0.12, y: 0.44, width: 0.30, height: 0.06),
                CGRect(x: 0.50, y: 0.44, width: 0.38, height: 0.06),
                CGRect(x: 0.30, y: 0.56, width: 0.50, height: 0.06),
                CGRect(x: 0.12, y: 0.68, width: 0.50, height: 0.06),
                CGRect(x: 0.70, y: 0.68, width: 0.18, height: 0.06),
                CGRect(x: 0.30, y: 0.80, width: 0.40, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.84),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.20, y: 0.18),
            ]
        ),

        // L79 — Precision corridors
        make(
            holes: [
                CGRect(x: 0.18, y: 0.22, width: 0.10, height: 0.55),
                CGRect(x: 0.36, y: 0.22, width: 0.10, height: 0.55),
                CGRect(x: 0.54, y: 0.22, width: 0.10, height: 0.55),
                CGRect(x: 0.72, y: 0.22, width: 0.10, height: 0.55),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.31, y: 0.50),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.68, y: 0.50),
            ]
        ),

        // L80 — Parchment finale
        make(
            holes: [
                CGRect(x: 0.18, y: 0.16, width: 0.18, height: 0.10),
                CGRect(x: 0.64, y: 0.16, width: 0.18, height: 0.10),
                CGRect(x: 0.40, y: 0.28, width: 0.20, height: 0.08),
                CGRect(x: 0.16, y: 0.42, width: 0.20, height: 0.10),
                CGRect(x: 0.64, y: 0.42, width: 0.20, height: 0.10),
                CGRect(x: 0.40, y: 0.56, width: 0.20, height: 0.08),
                CGRect(x: 0.16, y: 0.70, width: 0.20, height: 0.08),
                CGRect(x: 0.40, y: 0.70, width: 0.20, height: 0.08),
                CGRect(x: 0.64, y: 0.70, width: 0.20, height: 0.08),
                CGRect(x: 0.30, y: 0.84, width: 0.40, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.95),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.22),
                UnitPoint(x: 0.50, y: 0.48),
                UnitPoint(x: 0.50, y: 0.92),
            ]
        ),

        // ── SKETCH (L81-90) — charcoal smudges, demanding precision ───────

        // L81 — Big sweeping hazards
        make(
            holes: [
                CGRect(x: 0.20, y: 0.25, width: 0.60, height: 0.10),
                CGRect(x: 0.18, y: 0.60, width: 0.60, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.18),
                UnitPoint(x: 0.50, y: 0.48),
                UnitPoint(x: 0.50, y: 0.82),
            ]
        ),

        // L82 — Tight gap field
        make(
            holes: [
                CGRect(x: 0.12, y: 0.22, width: 0.18, height: 0.12),
                CGRect(x: 0.34, y: 0.22, width: 0.18, height: 0.12),
                CGRect(x: 0.56, y: 0.22, width: 0.18, height: 0.12),
                CGRect(x: 0.12, y: 0.42, width: 0.18, height: 0.12),
                CGRect(x: 0.34, y: 0.42, width: 0.18, height: 0.12),
                CGRect(x: 0.56, y: 0.42, width: 0.18, height: 0.12),
                CGRect(x: 0.12, y: 0.62, width: 0.18, height: 0.12),
                CGRect(x: 0.34, y: 0.62, width: 0.18, height: 0.12),
                CGRect(x: 0.56, y: 0.62, width: 0.18, height: 0.12),
            ],
            start: UnitPoint(x: 0.84, y: 0.90),
            goal:  UnitPoint(x: 0.84, y: 0.10),
            coins: [
                UnitPoint(x: 0.82, y: 0.50),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.30, y: 0.85),
            ]
        ),

        // L83 — Layered S-curves
        make(
            holes: [
                CGRect(x: 0.12, y: 0.20, width: 0.45, height: 0.06),
                CGRect(x: 0.42, y: 0.32, width: 0.45, height: 0.06),
                CGRect(x: 0.12, y: 0.44, width: 0.45, height: 0.06),
                CGRect(x: 0.42, y: 0.56, width: 0.45, height: 0.06),
                CGRect(x: 0.12, y: 0.68, width: 0.45, height: 0.06),
                CGRect(x: 0.42, y: 0.80, width: 0.45, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.94),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.80, y: 0.86),
                UnitPoint(x: 0.20, y: 0.50),
                UnitPoint(x: 0.80, y: 0.26),
            ]
        ),

        // L84 — Serpentine
        make(
            holes: [
                CGRect(x: 0.15, y: 0.22, width: 0.55, height: 0.07),
                CGRect(x: 0.30, y: 0.38, width: 0.55, height: 0.07),
                CGRect(x: 0.15, y: 0.54, width: 0.55, height: 0.07),
                CGRect(x: 0.30, y: 0.70, width: 0.55, height: 0.07),
            ],
            start: UnitPoint(x: 0.18, y: 0.90),
            goal:  UnitPoint(x: 0.18, y: 0.12),
            coins: [
                UnitPoint(x: 0.78, y: 0.80),
                UnitPoint(x: 0.20, y: 0.46),
                UnitPoint(x: 0.78, y: 0.30),
            ]
        ),

        // L85 — Dense scatter (harder than L76)
        make(
            holes: [
                CGRect(x: 0.16, y: 0.16, width: 0.10, height: 0.07),
                CGRect(x: 0.30, y: 0.18, width: 0.10, height: 0.07),
                CGRect(x: 0.44, y: 0.16, width: 0.10, height: 0.07),
                CGRect(x: 0.58, y: 0.18, width: 0.10, height: 0.07),
                CGRect(x: 0.72, y: 0.16, width: 0.10, height: 0.07),
                CGRect(x: 0.22, y: 0.30, width: 0.10, height: 0.07),
                CGRect(x: 0.40, y: 0.32, width: 0.10, height: 0.07),
                CGRect(x: 0.58, y: 0.30, width: 0.10, height: 0.07),
                CGRect(x: 0.16, y: 0.44, width: 0.10, height: 0.07),
                CGRect(x: 0.30, y: 0.46, width: 0.10, height: 0.07),
                CGRect(x: 0.50, y: 0.44, width: 0.10, height: 0.07),
                CGRect(x: 0.66, y: 0.46, width: 0.10, height: 0.07),
                CGRect(x: 0.22, y: 0.58, width: 0.10, height: 0.07),
                CGRect(x: 0.40, y: 0.60, width: 0.10, height: 0.07),
                CGRect(x: 0.58, y: 0.58, width: 0.10, height: 0.07),
                CGRect(x: 0.16, y: 0.72, width: 0.10, height: 0.07),
                CGRect(x: 0.32, y: 0.72, width: 0.10, height: 0.07),
                CGRect(x: 0.50, y: 0.72, width: 0.10, height: 0.07),
                CGRect(x: 0.66, y: 0.72, width: 0.10, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.07),
            coins: [
                UnitPoint(x: 0.50, y: 0.85),
                UnitPoint(x: 0.50, y: 0.52),
                UnitPoint(x: 0.50, y: 0.25),
            ]
        ),

        // L86 — Forced narrow path
        make(
            holes: [
                CGRect(x: 0.12, y: 0.18, width: 0.30, height: 0.62),
                CGRect(x: 0.52, y: 0.18, width: 0.30, height: 0.62),
                CGRect(x: 0.42, y: 0.40, width: 0.16, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.82),
                UnitPoint(x: 0.50, y: 0.58),
                UnitPoint(x: 0.50, y: 0.20),
            ]
        ),

        // L87 — Branching scrambles
        make(
            holes: [
                CGRect(x: 0.30, y: 0.20, width: 0.40, height: 0.06),
                CGRect(x: 0.18, y: 0.34, width: 0.20, height: 0.06),
                CGRect(x: 0.50, y: 0.34, width: 0.20, height: 0.06),
                CGRect(x: 0.30, y: 0.48, width: 0.40, height: 0.06),
                CGRect(x: 0.12, y: 0.62, width: 0.20, height: 0.06),
                CGRect(x: 0.68, y: 0.62, width: 0.20, height: 0.06),
                CGRect(x: 0.30, y: 0.74, width: 0.40, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.20, y: 0.85),
                UnitPoint(x: 0.50, y: 0.55),
                UnitPoint(x: 0.80, y: 0.15),
            ]
        ),

        // L88 — Punishing precision
        make(
            holes: [
                CGRect(x: 0.12, y: 0.22, width: 0.34, height: 0.14),
                CGRect(x: 0.54, y: 0.22, width: 0.34, height: 0.14),
                CGRect(x: 0.30, y: 0.42, width: 0.40, height: 0.08),
                CGRect(x: 0.12, y: 0.56, width: 0.34, height: 0.14),
                CGRect(x: 0.54, y: 0.56, width: 0.34, height: 0.14),
                CGRect(x: 0.30, y: 0.76, width: 0.40, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.87),
                UnitPoint(x: 0.50, y: 0.52),
                UnitPoint(x: 0.50, y: 0.18),
            ]
        ),

        // L89 — High difficulty multi-route
        make(
            holes: [
                CGRect(x: 0.20, y: 0.18, width: 0.10, height: 0.10),
                CGRect(x: 0.40, y: 0.18, width: 0.10, height: 0.10),
                CGRect(x: 0.60, y: 0.18, width: 0.10, height: 0.10),
                CGRect(x: 0.30, y: 0.34, width: 0.40, height: 0.07),
                CGRect(x: 0.12, y: 0.48, width: 0.18, height: 0.10),
                CGRect(x: 0.42, y: 0.48, width: 0.18, height: 0.10),
                CGRect(x: 0.70, y: 0.48, width: 0.18, height: 0.10),
                CGRect(x: 0.30, y: 0.66, width: 0.40, height: 0.07),
                CGRect(x: 0.20, y: 0.80, width: 0.10, height: 0.08),
                CGRect(x: 0.40, y: 0.80, width: 0.10, height: 0.08),
                CGRect(x: 0.60, y: 0.80, width: 0.10, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.95),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.92),
                UnitPoint(x: 0.50, y: 0.27),
                UnitPoint(x: 0.50, y: 0.58),
            ]
        ),

        // L90 — Sketch finale
        make(
            holes: [
                CGRect(x: 0.18, y: 0.16, width: 0.18, height: 0.08),
                CGRect(x: 0.64, y: 0.16, width: 0.18, height: 0.08),
                CGRect(x: 0.40, y: 0.28, width: 0.20, height: 0.08),
                CGRect(x: 0.16, y: 0.40, width: 0.24, height: 0.08),
                CGRect(x: 0.60, y: 0.40, width: 0.24, height: 0.08),
                CGRect(x: 0.40, y: 0.52, width: 0.20, height: 0.08),
                CGRect(x: 0.16, y: 0.64, width: 0.24, height: 0.08),
                CGRect(x: 0.60, y: 0.64, width: 0.24, height: 0.08),
                CGRect(x: 0.40, y: 0.76, width: 0.20, height: 0.08),
                CGRect(x: 0.18, y: 0.86, width: 0.18, height: 0.06),
                CGRect(x: 0.64, y: 0.86, width: 0.18, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.95),
            goal:  UnitPoint(x: 0.5, y: 0.06),
            coins: [
                UnitPoint(x: 0.50, y: 0.20),
                UnitPoint(x: 0.50, y: 0.48),
                UnitPoint(x: 0.50, y: 0.80),
            ]
        ),

        // ── ORIGAMI (L91-100) — folded paper, the climax of the game ──────

        // L91 — Open Origami intro
        make(
            holes: [
                CGRect(x: 0.32, y: 0.40, width: 0.36, height: 0.20),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.18, y: 0.50),
                UnitPoint(x: 0.82, y: 0.50),
                UnitPoint(x: 0.50, y: 0.74),
            ]
        ),

        // L92 — Complex paths
        make(
            holes: [
                CGRect(x: 0.16, y: 0.22, width: 0.32, height: 0.07),
                CGRect(x: 0.54, y: 0.22, width: 0.32, height: 0.07),
                CGRect(x: 0.34, y: 0.36, width: 0.32, height: 0.07),
                CGRect(x: 0.16, y: 0.50, width: 0.32, height: 0.07),
                CGRect(x: 0.54, y: 0.50, width: 0.32, height: 0.07),
                CGRect(x: 0.34, y: 0.64, width: 0.32, height: 0.07),
                CGRect(x: 0.16, y: 0.78, width: 0.32, height: 0.07),
                CGRect(x: 0.54, y: 0.78, width: 0.32, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.94),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.86),
                UnitPoint(x: 0.50, y: 0.43),
                UnitPoint(x: 0.50, y: 0.16),
            ]
        ),

        // L93 — Maze
        make(
            holes: [
                CGRect(x: 0.12, y: 0.20, width: 0.50, height: 0.06),
                CGRect(x: 0.30, y: 0.30, width: 0.58, height: 0.06),
                CGRect(x: 0.12, y: 0.40, width: 0.30, height: 0.06),
                CGRect(x: 0.50, y: 0.40, width: 0.38, height: 0.06),
                CGRect(x: 0.20, y: 0.50, width: 0.40, height: 0.06),
                CGRect(x: 0.68, y: 0.50, width: 0.20, height: 0.06),
                CGRect(x: 0.12, y: 0.60, width: 0.50, height: 0.06),
                CGRect(x: 0.30, y: 0.70, width: 0.50, height: 0.06),
                CGRect(x: 0.12, y: 0.80, width: 0.30, height: 0.06),
                CGRect(x: 0.50, y: 0.80, width: 0.38, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.85),
                UnitPoint(x: 0.20, y: 0.45),
                UnitPoint(x: 0.50, y: 0.14),
            ]
        ),

        // L94 — Dual routes
        make(
            holes: [
                CGRect(x: 0.40, y: 0.18, width: 0.20, height: 0.65),
                CGRect(x: 0.12, y: 0.35, width: 0.18, height: 0.10),
                CGRect(x: 0.70, y: 0.35, width: 0.18, height: 0.10),
                CGRect(x: 0.12, y: 0.55, width: 0.18, height: 0.10),
                CGRect(x: 0.70, y: 0.55, width: 0.18, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.22, y: 0.25),
                UnitPoint(x: 0.78, y: 0.25),
                UnitPoint(x: 0.50, y: 0.90),
            ]
        ),

        // L95 — Precision
        make(
            holes: [
                CGRect(x: 0.12, y: 0.22, width: 0.30, height: 0.10),
                CGRect(x: 0.58, y: 0.22, width: 0.30, height: 0.10),
                CGRect(x: 0.20, y: 0.38, width: 0.30, height: 0.10),
                CGRect(x: 0.50, y: 0.38, width: 0.30, height: 0.10),
                CGRect(x: 0.12, y: 0.54, width: 0.30, height: 0.10),
                CGRect(x: 0.58, y: 0.54, width: 0.30, height: 0.10),
                CGRect(x: 0.20, y: 0.70, width: 0.30, height: 0.10),
                CGRect(x: 0.50, y: 0.70, width: 0.30, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.85),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.17),
            ]
        ),

        // L96 — Dense field
        make(
            holes: [
                CGRect(x: 0.18, y: 0.18, width: 0.10, height: 0.07),
                CGRect(x: 0.38, y: 0.18, width: 0.10, height: 0.07),
                CGRect(x: 0.58, y: 0.18, width: 0.10, height: 0.07),
                CGRect(x: 0.78, y: 0.18, width: 0.04, height: 0.07),
                CGRect(x: 0.12, y: 0.30, width: 0.04, height: 0.07),
                CGRect(x: 0.28, y: 0.30, width: 0.10, height: 0.07),
                CGRect(x: 0.48, y: 0.30, width: 0.10, height: 0.07),
                CGRect(x: 0.68, y: 0.30, width: 0.10, height: 0.07),
                CGRect(x: 0.18, y: 0.42, width: 0.10, height: 0.07),
                CGRect(x: 0.38, y: 0.42, width: 0.10, height: 0.07),
                CGRect(x: 0.58, y: 0.42, width: 0.10, height: 0.07),
                CGRect(x: 0.28, y: 0.54, width: 0.10, height: 0.07),
                CGRect(x: 0.48, y: 0.54, width: 0.10, height: 0.07),
                CGRect(x: 0.68, y: 0.54, width: 0.10, height: 0.07),
                CGRect(x: 0.18, y: 0.66, width: 0.10, height: 0.07),
                CGRect(x: 0.38, y: 0.66, width: 0.10, height: 0.07),
                CGRect(x: 0.58, y: 0.66, width: 0.10, height: 0.07),
                CGRect(x: 0.28, y: 0.78, width: 0.10, height: 0.07),
                CGRect(x: 0.48, y: 0.78, width: 0.10, height: 0.07),
                CGRect(x: 0.68, y: 0.78, width: 0.10, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.86),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.14),
            ]
        ),

        // L97 — Weaving corridors
        make(
            holes: [
                CGRect(x: 0.15, y: 0.20, width: 0.45, height: 0.07),
                CGRect(x: 0.40, y: 0.32, width: 0.45, height: 0.07),
                CGRect(x: 0.15, y: 0.44, width: 0.45, height: 0.07),
                CGRect(x: 0.40, y: 0.56, width: 0.45, height: 0.07),
                CGRect(x: 0.15, y: 0.68, width: 0.45, height: 0.07),
                CGRect(x: 0.40, y: 0.80, width: 0.45, height: 0.07),
            ],
            start: UnitPoint(x: 0.18, y: 0.95),
            goal:  UnitPoint(x: 0.82, y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.88),
                UnitPoint(x: 0.20, y: 0.50),
                UnitPoint(x: 0.78, y: 0.26),
            ]
        ),

        // L98 — Punishing
        make(
            holes: [
                CGRect(x: 0.12, y: 0.18, width: 0.30, height: 0.10),
                CGRect(x: 0.58, y: 0.18, width: 0.30, height: 0.10),
                CGRect(x: 0.32, y: 0.32, width: 0.36, height: 0.07),
                CGRect(x: 0.12, y: 0.44, width: 0.25, height: 0.10),
                CGRect(x: 0.40, y: 0.44, width: 0.20, height: 0.10),
                CGRect(x: 0.63, y: 0.44, width: 0.25, height: 0.10),
                CGRect(x: 0.32, y: 0.58, width: 0.36, height: 0.07),
                CGRect(x: 0.12, y: 0.70, width: 0.30, height: 0.10),
                CGRect(x: 0.58, y: 0.70, width: 0.30, height: 0.10),
                CGRect(x: 0.32, y: 0.84, width: 0.36, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.95),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.92),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.15),
            ]
        ),

        // L99 — Pre-finale
        make(
            holes: [
                CGRect(x: 0.18, y: 0.16, width: 0.14, height: 0.10),
                CGRect(x: 0.42, y: 0.16, width: 0.14, height: 0.10),
                CGRect(x: 0.66, y: 0.16, width: 0.14, height: 0.10),
                CGRect(x: 0.28, y: 0.30, width: 0.14, height: 0.10),
                CGRect(x: 0.54, y: 0.30, width: 0.14, height: 0.10),
                CGRect(x: 0.18, y: 0.44, width: 0.14, height: 0.10),
                CGRect(x: 0.42, y: 0.44, width: 0.14, height: 0.10),
                CGRect(x: 0.66, y: 0.44, width: 0.14, height: 0.10),
                CGRect(x: 0.28, y: 0.58, width: 0.14, height: 0.10),
                CGRect(x: 0.54, y: 0.58, width: 0.14, height: 0.10),
                CGRect(x: 0.18, y: 0.72, width: 0.14, height: 0.10),
                CGRect(x: 0.42, y: 0.72, width: 0.14, height: 0.10),
                CGRect(x: 0.66, y: 0.72, width: 0.14, height: 0.10),
                CGRect(x: 0.30, y: 0.86, width: 0.40, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.96),
            goal:  UnitPoint(x: 0.5, y: 0.06),
            coins: [
                UnitPoint(x: 0.50, y: 0.92),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.20),
            ]
        ),

        // L100 — THE FINAL LEVEL — boss of World 2 + game finale
        // Punishing maze that tests every skill from 99 prior levels.
        make(
            holes: [
                CGRect(x: 0.16, y: 0.14, width: 0.16, height: 0.07),
                CGRect(x: 0.36, y: 0.14, width: 0.20, height: 0.07),
                CGRect(x: 0.60, y: 0.14, width: 0.16, height: 0.07),
                CGRect(x: 0.26, y: 0.26, width: 0.20, height: 0.07),
                CGRect(x: 0.50, y: 0.26, width: 0.20, height: 0.07),
                CGRect(x: 0.16, y: 0.38, width: 0.16, height: 0.07),
                CGRect(x: 0.36, y: 0.38, width: 0.20, height: 0.07),
                CGRect(x: 0.60, y: 0.38, width: 0.16, height: 0.07),
                CGRect(x: 0.26, y: 0.50, width: 0.20, height: 0.07),
                CGRect(x: 0.50, y: 0.50, width: 0.20, height: 0.07),
                CGRect(x: 0.16, y: 0.62, width: 0.16, height: 0.07),
                CGRect(x: 0.36, y: 0.62, width: 0.20, height: 0.07),
                CGRect(x: 0.60, y: 0.62, width: 0.16, height: 0.07),
                CGRect(x: 0.26, y: 0.74, width: 0.20, height: 0.07),
                CGRect(x: 0.50, y: 0.74, width: 0.20, height: 0.07),
                CGRect(x: 0.16, y: 0.86, width: 0.16, height: 0.06),
                CGRect(x: 0.36, y: 0.86, width: 0.20, height: 0.06),
                CGRect(x: 0.60, y: 0.86, width: 0.16, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.97),
            goal:  UnitPoint(x: 0.5, y: 0.05),
            coins: [
                UnitPoint(x: 0.50, y: 0.95),   // tucked at the start
                UnitPoint(x: 0.50, y: 0.46),   // dead centre, hardest
                UnitPoint(x: 0.50, y: 0.10),   // right by the goal
            ]
        ),
    ]

    // -----------------------------------------------------------------------
    // Procedural generator — deterministic, archetype-based, difficulty-scaled.
    //
    // Produces every level beyond the hand-crafted set, all the way to 5,000.
    // Deterministic (seeded by level number) so a given level is identical for
    // every player forever.  Four archetypes that ALWAYS leave a clear route —
    // density and course length scale with World.difficulty, gaps never shrink
    // to pixel-precision (core rule: harder = longer / busier, not punishing).
    //
    // Any generated level can later be replaced by a hand-crafted "landmark"
    // or a fix via `handCrafted` + the override maps in `layout(for:)`.
    // -----------------------------------------------------------------------
    static func generated(for level: Int) -> LevelLayout {
        var rng   = LevelRNG(seed: UInt64(max(0, level)))
        let world = World.world(for: level)
        let d     = world.difficulty                 // 0…1 across the climb

        let start = UnitPoint(x: 0.5, y: 0.90)
        let goal  = UnitPoint(x: 0.5, y: 0.10)

        let designed: [CGRect]
        switch level % 4 {
        case 0:  designed = genZigzag(&rng, d)
        case 1:  designed = genStaircase(&rng, d)
        case 2:  designed = genScattered(&rng, d)
        default: designed = genCorridor(&rng, d)
        }

        let coins = [0.27, 0.50, 0.73].map { y in
            UnitPoint(x: freeX(at: y, holes: designed), y: y)
        }

        let holes = sideWalls + designed
        var times = defaultTimes(start: start, goal: goal, holeCount: designed.count)
        times.target += d * 1.2          // deeper worlds run a little longer
        times.gold   += d * 0.8
        return LevelLayout(
            holeRects:  holes,
            start:      start,
            goal:       goal,
            coins:      coins,
            targetTime: times.target,
            goldTime:   times.gold,
            tier:       .easy,           // placeholder; overridden in layout(for:)
            verified:   false
        )
    }

    // Archetype 0 — Zigzag: alternating wide bars; weave through the gaps.
    private static func genZigzag(_ rng: inout LevelRNG, _ d: Double) -> [CGRect] {
        let rows = 3 + Int(d * 4.0)                   // 3…7
        let w    = 0.46 + d * 0.06                    // gap stays ≥ ~0.24
        var out: [CGRect] = []
        for i in 0..<rows {
            let y = 0.22 + (0.60 / Double(max(1, rows - 1))) * Double(i)
            let x = (i % 2 == 0) ? 0.12 : (0.88 - w)
            out.append(CGRect(x: x, y: y, width: w, height: 0.05 + rng.range(0, 0.02)))
        }
        return out
    }

    // Archetype 1 — Staircase: stepped bars descending side to side.
    private static func genStaircase(_ rng: inout LevelRNG, _ d: Double) -> [CGRect] {
        let steps = 4 + Int(d * 4.0)                  // 4…8
        let w     = 0.30 + d * 0.06
        var out: [CGRect] = []
        for i in 0..<steps {
            let y = 0.18 + (0.64 / Double(max(1, steps - 1))) * Double(i)
            let x = (i % 2 == 0) ? (0.14 + rng.range(0, 0.04))
                                 : (0.86 - w - rng.range(0, 0.04))
            out.append(CGRect(x: x, y: y, width: w, height: 0.05))
        }
        return out
    }

    // Archetype 2 — Scattered: small holes on a jittered grid; pick a route.
    private static func genScattered(_ rng: inout LevelRNG, _ d: Double) -> [CGRect] {
        let rows = 5 + Int(d * 3.0)                   // 5…8 rows
        var out: [CGRect] = []
        for r in 0..<rows {
            let y = 0.20 + (0.62 / Double(max(1, rows - 1))) * Double(r)
            // 1 or 2 small holes per row, always leaving a wide gap.
            let n = 1 + (rng.unit() < (0.2 + d * 0.5) ? 1 : 0)
            for _ in 0..<n {
                let s = 0.08 + rng.range(0, 0.03)
                let x = rng.range(0.16, 0.84 - s)
                out.append(CGRect(x: x, y: y, width: s, height: 0.07))
            }
        }
        return out
    }

    // Archetype 3 — Corridor: side blocks leaving a winding centre lane.
    private static func genCorridor(_ rng: inout LevelRNG, _ d: Double) -> [CGRect] {
        var out: [CGRect] = []
        let blocks = 3 + Int(d * 3.0)                 // 3…6 pinch points
        for i in 0..<blocks {
            let y = 0.20 + (0.62 / Double(max(1, blocks - 1))) * Double(i)
            let fromLeft = (i % 2 == 0)               // serpentine lane
            let w = 0.40 + d * 0.10 + rng.range(0, 0.04)
            let x = fromLeft ? 0.12 : (0.88 - w)
            out.append(CGRect(x: x, y: y, width: w, height: 0.07 + d * 0.02))
        }
        return out
    }

    // Find an x at the given y not sitting on a hole (with margin) so a coin
    // lands on open floor.  Falls back to centre if nothing clears.
    private static func freeX(at y: Double, holes: [CGRect]) -> Double {
        let candidates = [0.50, 0.30, 0.70, 0.22, 0.78, 0.40, 0.60]
        let margin = 0.05
        for x in candidates {
            let p = CGPoint(x: x, y: y)
            if holes.allSatisfy({ !$0.insetBy(dx: -margin, dy: -margin).contains(p) }) {
                return x
            }
        }
        return 0.5
    }
}
