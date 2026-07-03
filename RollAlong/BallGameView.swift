import SwiftUI
import CoreMotion
import UIKit
import AudioToolbox
import AVFoundation

// ---------------------------------------------------------------------------
// BallGameView — tilt-driven marble game.
//
// White = safe platform. Black rectangles = holes. Iridescent circle = goal.
// A coloured border traces the screen edge and reacts to game state:
//   grey  → playing normally
//   red   → ball fell (oops)
//   green → level complete
// ---------------------------------------------------------------------------

// Pull the device's actual display corner radius via the unsupported KVC key,
// so the border traces the screen curve exactly on any iPhone model.
// Reversed-string trick keeps the literal "_displayCornerRadius" out of the
// source, which is the conventional way to use this value safely.
private extension UIScreen {
    var ra_displayCornerRadius: CGFloat {
        let key = ["Radius", "Corner", "display", "_"].reversed().joined()
        return (self.value(forKey: key) as? CGFloat) ?? 55
    }
}

private var screenCornerRadius: CGFloat {
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let screen = scene.windows.first?.screen {
        return screen.ra_displayCornerRadius
    }
    return 55
}

private enum GamePhase: Equatable {
    case playing, fell, levelComplete
}

/// One-of-any cosmetic selection used by the post-tutorial reward
/// modal.  Each case wraps the picked item from its respective
/// category; the modal holds at most one of these at a time, so a
/// pick in any row replaces a pick in any other row.
/// Phases of the first-time Level 1 tutorial.  The level layout is
/// gradually revealed: ball alone → ball + coins → ball + coins + hole.
/// `notTutorial` is used both for L1 replays (after the first clear)
/// and for every other level — the regular spawn-lock / "Tap to
/// start" flow.
///
/// Transitions are linear except for the tutorial-fall escape hatch:
/// if the player falls into the hole during `.playing`, we drop them
/// to `.notTutorial` for the rest of the session so the respawn shows
/// the standard hint rather than restarting the phased tour.
enum TutorialPhase: Equatable {
    case introHint        // "Hold your phone flat. Tap to start the level."
    case freeRoaming      // ball can move, empty map (no coins, no hole)
    case showCoinsHint    // locked, coins visible, "Tilt your phone to roll the ball…"
    case collectingCoins  // ball can move, coins pickable, no hole
    case showHoleHint     // locked, coins banked + hole visible, "Avoid the hole…"
    case playing          // normal play with full layout (still first attempt)
    case notTutorial      // standard level flow — replays, other levels, post-fall
}

private enum BorderPhase: Equatable {
    /// Ball is spawned but the player hasn't started yet — physics is
    /// paused, the border shows a distinct white "armed" colour, and a
    /// "Tap to start" hint sits above the ball.  Either taps the screen
    /// or waits ~1.5s and play begins automatically.
    case arming
    case normal, fell, won
}

struct BallGameView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator
    @EnvironmentObject var ads:       AdManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    @State private var ball:               Ball?     = nil
    @State private var phase:              GamePhase = .playing
    @State private var arenaSize:          CGSize    = .zero
    @State private var showWelcomeMoment:  Bool      = false
    @State private var showTutorialReward: Bool      = false

    // Tutorial-reward pick.  Player chooses ONE free standard-tier
    // Standard COLLECTION (bundle) — picking a card selects the whole set; the
    // Claim button unlocks as soon as a collection is selected.  Stores the
    // selected bundle's id.
    @State private var tutorialBundlePick: String? = nil

    // Lives system (Sprint 4c)
    @State private var showOutOfLives:                Bool   = false
    /// Challenge-of-the-Day "Better Luck Tomorrow" overlay — shown when the
    /// player exhausts their free attempts on a CotD sub-level.
    @State private var showDailyFailed:               Bool   = false
    /// Confirmation before quitting an in-progress CotD run from the home
    /// button — leaving forfeits the day, so we guard against a stray tap.
    @State private var showDailyQuitConfirm:          Bool   = false
    @State private var showLivesPlaceholderAlert:     Bool   = false
    @State private var livesPlaceholderMessage:       String = ""

    // StoreKit purchase sheets (Sprint 4h)
    @State private var showBuyLivesSheet:             Bool   = false

    // Ad watch state (Sprint 4i).  Disables the button while an ad is in
    // flight and surfaces a soft retry message if loading hasn't completed.
    @State private var adInFlight:                    Bool   = false
    @State private var showAdNotReadyAlert:           Bool   = false

    // Per-attempt progression state
    @State private var levelStartTime:        Date?    = nil
    @State private var coinsPickedThisAttempt: Set<Int> = []    // coin indices 0…2 picked this attempt

    /// Spawn-lock — when set, physics is paused and the player sees a
    /// "Tap to start" hint over the ball.  Cleared by tap-to-start OR
    /// when the time elapses naturally (whichever happens first).  Set
    /// on every spawn (new level, Replay, Play Now after refill) so the
    /// ball never starts rolling before the player is mentally ready.
    @State private var spawnLockUntil: Date? = nil
    private let spawnLockDuration: TimeInterval = 1.5

    /// L1 first-time-play tutorial phase.  Defaults to `.notTutorial`
    /// for every level except the first attempt of L1, which is
    /// initialised to `.introHint` inside `spawnBall`.
    @State private var tutorialPhase: TutorialPhase = .notTutorial

    /// Tracks coins awarded mid-attempt via the L1 tutorial's
    /// Phase-2→3 bank-and-pay flow.  Added on top of the level-clear
    /// reward when computing `lastClearedCoinReward` so the "Level
    /// Clear" screen reports the full +5 (3 tutorial coins + 2 first
    /// clear bonus) instead of just the +2 first-clear portion.
    /// Reset on every spawn so it never leaks across attempts.
    @State private var tutorialCoinBonus: Int = 0

    // Graphite trail (Paper world).  Holds recent ball positions so we can
    // render a fading lead streak behind the ball.  Cleared each spawn.
    @State private var trailPoints:           [CGPoint] = []
    /// Wall-clock stamp (timeIntervalSinceReferenceDate) for each `trailPoints`
    /// entry, kept strictly in lockstep.  Lets the elemental trails (ink/fire/
    /// ice/air) animate and dissipate on a real clock, in place, instead of
    /// riding the ball.  Cleared with the points each spawn.
    @State private var trailTimes:            [Double] = []
    /// Opacity of the Zen sand groove.  The "smooth the sand" (rake) button
    /// fades this to 0, wipes the trail, then restores it to 1 so the next
    /// strokes draw crisp.  Stays 1 in every other mode.
    @State private var sandClearFade:         Double = 1.0

    // ── Zen Garden tools (all Zen-only; see ZenGardenTools.swift) ──────────
    /// The bottom-right tool dropdown is expanded.
    @State private var zenMenuOpen   = false
    /// Which tool sub-panel is showing (pattern options / item options).
    @State private var zenSubmenu:    ZenSubmenu = .none
    /// Active auto-track pattern, or nil for manual touch-roll.
    @State private var zenPattern:    ZenPattern? = nil
    /// Auto-track speed as a 0…1 fraction (set by the ZenSpeedBar), mapped to a
    /// pattern-advance rate in the tick.  Replaces the old discrete ZenSpeed.
    @State private var zenSpeedFraction: Double = 0.3
    /// Progress along the active pattern (full coverages), advanced each tick.
    @State private var zenPatternPhase = 0.0
    /// Currently-selected prop to drop on the next garden tap (nil = none).
    @State private var zenPlacingItem: ZenItem? = nil
    /// Props placed in the garden this session.
    @State private var zenDecorations: [ZenDecoration] = []
    /// True while the player is holding the garden (manual roll + buttons hidden).
    @State private var zenTouching   = false

    // ── Zen sand accumulation ─────────────────────────────────────────────
    // Unlike the cosmetic trail (a fixed-length fading ribbon), the Zen sand
    // groove is baked into a persistent image that grows until "smooth sand"
    // wipes it — so an auto-pattern left running fills the whole garden and the
    // raked lines stay put.  Updated incrementally (one new segment per move),
    // so cost stays O(1) per frame regardless of how full the garden gets.
    @State private var sandAccumImage: UIImage? = nil
    @State private var lastSandPoint:  CGPoint? = nil
    @State private var sandCanvasSize: CGSize = .zero
    private let sandMinStep: CGFloat = 3.0

    /// Default cap on trail segments — about 1.5s at 60fps.
    private let trailMaxLength = 90
    /// Extra segments granted per coin picked up while the Snake
    /// trail is equipped (~0.5s of growth per coin).
    private let snakeGrowthPerCoin = 30
    private let trailMinStep:  CGFloat = 1.5

    /// Hue assigned to `trailPoints[0]`.  Each later segment's hue
    /// is `offset + i * trailHueStep mod 1`, so once the ball paints
    /// a position with a hue the colour stays put — the spectrum
    /// follows the ball rather than redistributing each frame.  Bump
    /// it forward when segments fall off the tail so the survivors
    /// keep their original colours.
    @State private var trailHueOffset: Double = 0.0
    /// One full ROYGBIV cycle every `trailMaxLength` segments.  The
    /// Snake trail (which can grow past `trailMaxLength`) isn't
    /// rainbow, so the step staying tied to the base length is fine.
    private let trailHueStep: Double = 1.0 / 90.0

    /// Persistent-trail cap for Zen Garden's raked-sand line.  Far longer
    /// than the cosmetic trail so the ball builds a lasting drawing; still
    /// bounded so a long session can't grow the point buffer without limit
    /// (the very oldest marks quietly smooth away once the cap is reached).
    private let sandTrailMaxLength = 2000

    /// True when the active mode carves a single persistent sand line
    /// (Zen Garden) instead of the standard fading cosmetic trail.
    private var usesSandTrail: Bool { activeMode.leavesPersistentTrail }

    /// Actual trim cap used by the tick loop.  Equals `trailMaxLength`
    /// for every trail except the Snake, which grows by
    /// `snakeGrowthPerCoin` for each coin the player has picked up
    /// this attempt — the eat-and-grow mechanic.  Sand-trail modes use the
    /// much larger persistent cap.
    private var effectiveTrailMaxLength: Int {
        if usesSandTrail { return sandTrailMaxLength }
        if gameState.equippedTrail == .snake {
            return trailMaxLength + coinsPickedThisAttempt.count * snakeGrowthPerCoin
        }
        return trailMaxLength
    }

    // MARK: - Coin Pit (collect-count reward round) state
    //
    // The Coin Pit is the shared engine in its "reward" costume: a fixed-time
    // round where coins rain down the screen and the player tilt-rolls to catch
    // them.  No holes, no lives, no progression — a pure payout.  This state is
    // dormant in every other mode (gated by `isCoinPit`, derived from the active
    // mode's `.collectCount` goal), so it cannot touch the climb.
    private struct FallingCoin: Identifiable {
        let id = UUID()
        var x:     CGFloat
        var y:     CGFloat
        var vy:    CGFloat   // fall speed, points/sec
        let size:  CGFloat
        let phase: Double    // spin phase so coins don't pulse in unison
    }
    private let coinPitPayoutPerCoin = 1
    @State private var fallingCoins:       [FallingCoin] = []
    @State private var coinPitDeadline:    Date? = nil
    @State private var coinPitLastRelease: Date? = nil
    @State private var coinPitReleased:    Int = 0
    @State private var zenStart:           Date? = nil   // Zen Garden session start (time leaderboard)
    @State private var coinPitScore:       Int = 0
    @State private var coinPitOver:        Bool = false

    // Ticket staking (Gold Rush economy) — the round is bought up front on the
    // stake overlay: every TIME ticket buys 30 s on the clock (stake as many
    // as you hold).  Tickets are consumed on Start; quitting early refunds one
    // ticket per FULL un-played 30 s block.  The optional ×2-coins boost is
    // bought DURING the round for a flat 2 tickets (non-refundable) and doubles
    // the PAYOUT, not the coin count.  Entering with zero tickets is blocked at
    // the Games hub and again on the stake overlay.
    @State private var coinPitStaked            = false   // round paid & live
    @State private var coinPitStakeTime         = 1       // picker: time tickets (≥1)
    @State private var coinPitTimeTicketsStaked = 0       // frozen at Start (refund math)
    @State private var coinPitStakedMultiplier  = 1       // 1, or 2 after the in-round buy

    /// The catch target if the active mode is a collect-count round, else nil.
    private var coinPitTarget: Int? {
        if case let .collectCount(n) = activeMode.goal { return n }
        return nil
    }
    /// True only while presenting a Coin Pit round.
    private var isCoinPit: Bool { coinPitTarget != nil }

    /// True while playing the Challenge of the Day (the one-shot daily gauntlet).
    private var isDaily: Bool {
        if case .oneShot = activeMode.progression { return true }
        return false
    }

    /// Round length bought at Start: time-tickets × 30 s.
    private var coinPitStakedDuration: TimeInterval {
        Double(max(1, coinPitTimeTicketsStaked)) * GameState.goldRushSecondsPerTicket
    }
    /// Coins dropped this round: the base per-30 s target × time blocks bought.
    /// The ×2 boost deliberately does NOT scale the coin COUNT — flooding the
    /// field with 4–5× coins tanked the frame rate — it doubles the PAYOUT
    /// instead (see the live credit and the payout overlay).
    private var coinPitEffectiveTarget: Int? {
        coinPitTarget.map { $0 * max(1, coinPitTimeTicketsStaked) }
    }

    // Last-completion results (for the win overlay)
    @State private var lastClearedTime:        TimeInterval = 0
    @State private var lastClearedStars:       Int          = 0
    @State private var lastClearedCoinIndices: Set<Int>     = []
    @State private var lastClearedCoinReward:  Int          = 0
    @State private var lastClearedIsNewBestStars: Bool      = false

    // Animation-polish triggers (keyframe animators key off these)
    @State private var squashTrigger:      Int       = 0   // on wall bounce
    @State private var shakeTrigger:       Int       = 0   // on .fell
    @State private var goalBurst:          GoalBurstEvent? = nil

    // MARK: - Pit-fall animation
    //
    // When the ball enters a pit we don't snap straight to the end screen.
    // Instead we freeze physics, fire the loss feedback once, and play a
    // short "the ball sinks into the depth" animation — the ball drops,
    // shrinks, and fades out as if it fell down a deep hole.  Only once it
    // has vanished do we surface Oops / Out-of-Lives.  This both reads far
    // better than a ball snapping out of existence AND fixes the old bug
    // where an out-of-lives fall left `phase == .playing`, so `tick` kept
    // running and re-fired the fall feedback every frame (constant buzz +
    // the screen jerking left while the ball jittered in the pit).
    //
    // `isSinkingIntoPit` freezes the physics tick; `pitSunk` is the
    // animation driver (false = at the rim, true = fallen away).  A
    // one-shot landing reaction (splash / ember burst / smoke poof, keyed
    // to the equipped Pit) is triggered via `pitLandingEvent`.
    @State private var isSinkingIntoPit:   Bool      = false
    @State private var pitSunk:            Bool      = false
    @State private var pitLandingEvent:    PitLandingEvent? = nil

    /// How long the ball takes to fall out of view into the pit.
    private let pitFallDuration: TimeInterval = 0.5
    /// How far (in points) the ball drifts downward as it sinks — well past
    /// the hole rim so it clearly disappears into depth.
    private var pitFallDepth: CGFloat { effectiveBallRadius * 7 }

    private let ballRadius:  CGFloat = 18
    private let coinRadius:  CGFloat = 9
    private let tickRate              = 1.0 / 60.0

    /// The game mode this screen is presenting.  Every Roll Along experience
    /// runs the same tilt-physics engine wearing a different costume; the mode
    /// supplies the rules that differ (HUD flags, control scheme, fail/win
    /// behaviour, progression).  Injected at construction and defaulting to the
    /// endless climb, so every existing `BallGameView()` call site is unchanged
    /// — only an explicit `BallGameView(activeMode:)` (e.g. from a mode picker)
    /// selects something else.
    let activeMode: GameMode

    /// Only `activeMode` is injected; every `@State` / `@StateObject` keeps its
    /// declared default, so this single-parameter init is all SwiftUI needs.
    init(activeMode: GameMode = GameModeCatalogue.climb) {
        self.activeMode = activeMode
    }

    /// The ball's actual radius after the equipped skin's size modifier
    /// is applied.  Every skin is full-size except Pluto (0.5×), the
    /// dwarf planet from the Planets bundle.  Used for BOTH rendering
    /// (frame sizing) and physics (wall bounce, coin pickup, goal /
    /// hole collision) so the small marble behaves consistently.
    private var effectiveBallRadius: CGFloat {
        ballRadius * gameState.activeSkin.radiusScale
    }

    private var layout: LevelLayout {
        // Hole-free modes (Zen Garden, Coin Pit) roll in an open, hazard-free
        // arena rather than the player's current climb level.  ClimbMode and
        // any holed mode still resolve to the real level layout.
        if !activeMode.hasHoles {
            return LevelLayout.openArena
        }
        let base: LevelLayout
        if case .oneShot = activeMode.progression {
            // Challenge of the Day — a date-seeded BRUTAL gauntlet, far harder
            // than any climb level (and not a climb level number).
            base = LevelLayout.dailyChallenge(seed: gameState.dailyChallengeLayoutSeed)
        } else if case .challengeTrack(let id) = activeMode.progression {
            base = LevelLayout.trackLayout(trackID: id, level: gameState.activeTrackLevel)
        } else {
            base = LevelLayout.layout(for: gameState.currentLevel)
        }
        return gameState.ballStartsAtTop ? base.flipped() : base
    }

    /// Layout actually used for rendering + collision detection on the
    /// current tick.  Identical to `layout` for every level except L1
    /// in the first-time tutorial phases, where holes and/or coins
    /// are progressively revealed:
    ///
    ///   • `.introHint`, `.freeRoaming`         → no coins, no hole
    ///   • `.showCoinsHint`, `.collectingCoins` → coins, no hole
    ///   • `.showHoleHint`, `.playing`,
    ///     `.notTutorial`                       → full layout
    private var effectiveLayout: LevelLayout {
        let base = layout
        switch tutorialPhase {
        case .introHint, .freeRoaming:
            return LevelLayout(
                holeRects:  [],
                start:      base.start,
                goal:       base.goal,
                coins:      [],
                targetTime: base.targetTime,
                goldTime:   base.goldTime,
                tier:       base.tier,
                verified:   base.verified
            )
        case .showCoinsHint, .collectingCoins:
            return LevelLayout(
                holeRects:  [],
                start:      base.start,
                goal:       base.goal,
                coins:      base.coins,
                targetTime: base.targetTime,
                goldTime:   base.goldTime,
                tier:       base.tier,
                verified:   base.verified
            )
        case .showHoleHint, .playing, .notTutorial:
            return base
        }
    }

    /// Coin indices already banked for the level being played — CLIMB ONLY.
    /// Challenge Tracks and the Daily Challenge bank nothing, and in those
    /// modes `gameState.currentLevel` still points at the player's parked
    /// climb level — reading it there would mask coins on a completely
    /// different map (dimmed + uncollectible wherever the climb level's
    /// banked indices happen to land).  Non-climb modes therefore always
    /// present their full coin set.
    private var bankedCoinIndices: Set<Int> {
        guard activeMode.progression.banksPickupCoins else { return [] }
        return gameState.coinsCollected(for: gameState.currentLevel)
    }

    /// Equipped Floor and Pit — read from GameState so the view
    /// re-renders when either is swapped.  Replaces the old `theme`
    /// abstraction since Floor and Pit are now independent picks.
    /// The floor cosmetic in play.  Zen Garden ignores whatever the player
    /// has equipped and lays down the warm `.desert` sand bed, so the raked
    /// groove always reads on sand.  As a side effect every cosmetic floor
    /// overlay (aurora/disco/grass/moon/paper) is skipped, since none of the
    /// `floor == .x` checks match `.desert`.  This is render-only — it never
    /// touches `gameState.equippedFloor`, so the player's real floor returns
    /// the moment they leave Zen.
    private var floor: Floor { usesSandTrail ? .desert : gameState.equippedFloor }
    private var pit:   Pit   { gameState.equippedPit }

    // MARK: - Border state

    /// Whether the spawn-lock is currently engaged (ball frozen at start
    /// with the "Tap to start" hint visible).
    private var isArming: Bool {
        guard let until = spawnLockUntil else { return false }
        return Date.now < until
    }

    /// True when the goal/portal should be rendered.  Hidden during the
    /// early L1 tutorial phases — it appears alongside the hole when
    /// the player has collected the third coin, which is the moment
    /// they need to know there's a target to reach.
    private var showGoalForCurrentPhase: Bool {
        switch tutorialPhase {
        case .introHint, .freeRoaming, .showCoinsHint, .collectingCoins:
            return false
        case .showHoleHint, .playing, .notTutorial:
            return true
        }
    }

    private var borderPhase: BorderPhase {
        if isArming { return .arming }
        switch phase {
        case .playing:       return .normal
        case .fell:          return .fell
        case .levelComplete: return .won
        }
    }

    private var borderColor: Color {
        switch borderPhase {
        // Neutral + armed states wear the equipped Boundary cosmetic; fell (red)
        // and won (green) stay semantic so game-state feedback always reads.
        // "Classic" preserves the climb's original border greys exactly.
        case .arming: return gameState.equippedBoundary == .classic
            ? Color(white: 0.95) : gameState.equippedBoundary.edgeColor   // brightened = "ready"
        case .normal: return gameState.equippedBoundary == .classic
            ? Color(white: 0.68) : gameState.equippedBoundary.color
        case .fell:   return Color(red: 0.95, green: 0.15, blue: 0.15)
        case .won:    return Color(red: 0.25, green: 0.90, blue: 0.45)
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Themed floor
                floor.color.ignoresSafeArea()

                // Aurora theme: animated shimmer overlay on top of the base.
                // Skipped under Reduce Motion to avoid continuous background drift.
                if floor == .aurora && !reduceMotion {
                    auroraShimmerOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Disco floor — animated grid of colour-cycling squares.
                // Skipped under Reduce Motion (strobe-y).
                if floor == .disco && !reduceMotion {
                    discoFloorOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Grass floor (Golf bundle) — fairway turf with
                // randomly-distributed grass tufts that sway in the
                // breeze plus drifting seed/firefly motes.  Renders
                // under Reduce Motion too: the clock freezes so the
                // tufts hold still and the motes are skipped.
                if floor == .grass {
                    grassFloorOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Moon floor (Space Travel bundle) — lunar regolith with
                // scattered craters whose rim light slowly drifts, plus
                // twinkling star-glint dust.  Renders under Reduce Motion
                // too: the clock freezes to the classic static craters
                // and the dust is skipped.
                if floor == .moon {
                    moonFloorOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Eclipse floor (Eclipse bundle) — a dark starlit sky with a
                // glowing golden corona ring that slowly pulses.  Skipped under
                // Reduce Motion (the static dark base remains).
                if floor == .eclipse && !reduceMotion {
                    eclipseFloorOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Grid City floor (Neon City bundle) — synthwave neon
                // perspective grid receding to a horizon.  The scroll is
                // frozen internally under Reduce Motion, so it renders in
                // both cases and still shows the grid texture.
                if floor == .gridCity {
                    gridCityFloorOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Brass Works floor (Clockwork bundle) — riveted brass/
                // bronze plating whose engraved cogs slowly turn beneath
                // a traveling sheen.  Renders under Reduce Motion too:
                // the clock freezes (cogs at their original angle) and
                // the sheen is skipped.
                if floor == .brass {
                    brassFloorOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Money Full floor (top-coin-pack ($49.99) IAP secret) — an overlapping
                // tiled stack of $100 bills.  Static, so it renders under Reduce
                // Motion too.
                if floor == .moneyFull {
                    moneyFloorOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Paper-world floor overlays (ruled lines, grids, fold shadows…)
                paperFloorOverlay(geo: geo)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // Graphite trail (Paper world): drawn over the floor, UNDER the
                // holes — the streak should appear cut by the page tear.
                if usesSandTrail {
                    if sandAccumImage != nil {
                        trailOverlay(geo: geo)
                            .opacity(sandClearFade)
                            .allowsHitTesting(false)
                    }
                } else if gameState.equippedTrail != .none && trailPoints.count >= 2 {
                    trailOverlay(geo: geo)
                        .allowsHitTesting(false)
                }

                // Zen Garden — a permanent raked border framing the sand, filling
                // the outer margin the rake pattern doesn't reach.
                if usesSandTrail {
                    zenBorderOverlay(size: geo.size)
                        .allowsHitTesting(false)
                }

                // Zen Garden props (stones, bonsai…) — under the ball so the
                // marble rolls over them.
                if usesSandTrail {
                    ZenDecorationLayer(decorations: zenDecorations, size: geo.size)
                }

                // Hole zones (themed) — only modes that use holes draw them.
                // ClimbMode has holes, so this is unchanged today; hole-free
                // modes (Zen Garden, Coin Pit) render no pits.
                if activeMode.hasHoles {
                    holeLayer(geo: geo)
                }

                // Coins (not-yet-collected this attempt, not-yet-banked overall)
                coinLayer(geo: geo)

                // Coin Pit: the raining coins for the reward round (catch is
                // resolved in the tick; this layer is purely cosmetic).
                if isCoinPit {
                    fallingCoinLayer(geo: geo).allowsHitTesting(false)
                }

                // Goal — three renderer paths:
                //
                //   • `.target`  → simpleBullseyeTarget (3-ring default)
                //   • `.archery` → archeryTargetGoal    (FITA 5-band)
                //   • everything else (incl. .rainbow) → rainbowHole
                //                  (particle Canvas; .rainbow gets the
                //                   restored full-spectrum sparkly portal)
                //
                // Hidden during the early L1 tutorial phases — the
                // portal "spawns" alongside the hole when the player
                // collects their third coin (showHoleHint onward).
                if activeMode.goal == .reachGoal, showGoalForCurrentPhase {
                    Group {
                        switch gameState.equippedGoal {
                        case .target:      simpleBullseyeTarget
                        case .archery:     archeryTargetGoal
                        case .holeInOne:   holeInOneGoal
                        case .tractorBeam: tractorBeamGoal
                        case .inferno:     infernoGoal
                        case .halo:        heavensHaloGoal
                        case .doodle:      doodleGoal
                        case .soccerNet:   soccerNetGoal
                        case .galaxy:      galaxyGoal
                        case .crystal:     crystalGoal
                        case .flame:       flameGoal
                        case .blossom:     blossomGoal
                        case .mosaic:      mosaicGoal
                        case .ripple:      rippleGoal
                        case .comet:       cometGoal
                        case .neon:        neonGoal
                        case .eclipse:     eclipseGoal
                        case .plasma:      plasmaGoal
                        case .mirage:      mirageGoal
                        case .prism:       prismGoal
                        case .obsidian:    obsidianGoal
                        case .quasar:      quasarGoal
                        case .frost, .ember, .meadow, .bullion,
                             .amethyst, .candy, .slate:
                            bandedTargetGoal(gameState.equippedGoal.targetBands ?? [])
                        case .vortex, .wormhole:
                            ringPortalGoal(gameState.equippedGoal.portalStops ?? [])
                        case .aurora:      auroraGoal
                        default:           rainbowHole   // .rainbow + any future goal
                        }
                    }
                    .frame(width: ballRadius * 2.8, height: ballRadius * 2.8)
                    .position(goalPoint(in: geo.size))
                    .transition(.opacity)
                }

                // Ball
                if let ball {
                    marbleView
                        .frame(width: effectiveBallRadius * 2, height: effectiveBallRadius * 2)
                        .keyframeAnimator(
                            initialValue: BallSquash.identity,
                            trigger: squashTrigger
                        ) { content, value in
                            content.scaleEffect(x: value.scaleX, y: value.scaleY)
                        } keyframes: { _ in
                            // Pinch on impact, spring back with a tiny overshoot.
                            KeyframeTrack(\.scaleX) {
                                LinearKeyframe(1.18, duration: 0.06)
                                SpringKeyframe(1.0,  duration: 0.32, spring: .bouncy)
                            }
                            KeyframeTrack(\.scaleY) {
                                LinearKeyframe(0.78, duration: 0.06)
                                SpringKeyframe(1.0,  duration: 0.32, spring: .bouncy)
                            }
                        }
                        // Pit-fall sink — driven by the explicit
                        // withAnimation in `beginPitFall`.  The ball
                        // shrinks (receding into depth), drops below the
                        // rim, and fades out, so by the time the end card
                        // appears it has fully disappeared into the pit.
                        .scaleEffect(pitSunk ? 0.12 : 1.0)
                        .position(ball.position)
                        .offset(y: pitSunk ? pitFallDepth : 0)
                        .opacity(pitSunk ? 0.0 : 1.0)
                        .scaleEffect(phase == .playing ? 1.0 : 0.05)
                        .opacity(phase == .playing ? 1.0 : 0.0)
                        .animation(.easeIn(duration: 0.28), value: phase)
                }

                // Pit landing reaction — splash / embers / smoke that
                // erupts the instant the ball drops into the pit.  Keyed to
                // the equipped Pit so each cosmetic feels distinct.
                if let landing = pitLandingEvent {
                    // No .ignoresSafeArea() — the Canvas shares the ball's
                    // coordinate space so the splash lands exactly where the
                    // ball dropped (event.center == the fall position).
                    PitLandingView(event: landing)
                        .allowsHitTesting(false)
                }

                // Goal burst — one-shot particle blast on goal reach
                if let burst = goalBurst {
                    GoalBurstView(event: burst, accent: gameState.equippedGoal.accentColor)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Zen Garden input — a transparent layer over the garden that
                // turns finger-holds into a free roll (and taps into prop
                // placement).  Sits above the ball so the whole garden reacts
                // uniformly; the HUD + tool buttons render after it, so they
                // capture their own taps first.  Auto-pattern disables it (the
                // ball drives itself).
                if usesSandTrail && (zenPattern == nil || zenPlacingItem != nil) {
                    zenInputLayer(size: geo.size)
                }

                // HUD — just the level label
                hud(safeBottom: geo.safeAreaInsets.bottom)

                // Lives HUD — top-left.  Always visible (including tutorial
                // levels) so the player has a consistent place to check on
                // their marble stockpile.  Failure on tutorial levels still
                // doesn't cost a life — that's handled in handleFell —
                // but the HUD itself is permanent UI furniture.
                // Only consume-lives modes show the marble stockpile HUD;
                // unlimited modes (Zen, Coin Pit) have no lives to display.
                // ClimbMode consumes, so this stays visible today.
                if activeMode.lives == .consume {
                    livesHUDOverlay(safeTop: geo.safeAreaInsets.top)
                }

                // Challenge of the Day attempts HUD — no real lives here, just
                // the per-sub-level free attempts remaining.
                if isDaily {
                    dailyAttemptsHUDOverlay(safeTop: geo.safeAreaInsets.top)
                }

                // Coin Pit: live round HUD — seconds remaining + coins caught.
                // Gated to the reward round, and only once the round has been
                // bought (the stake overlay owns the screen before that).
                if isCoinPit && coinPitStaked {
                    coinPitHUDOverlay(safeTop: geo.safeAreaInsets.top)
                }

                // Coin Pit: optional in-round ×2-coins boost (flat 2 tickets).
                if isCoinPit && coinPitStaked && !coinPitOver {
                    coinPitDoubleButton
                }

                // Spawn-lock "Tap to start" hint — only shown while the
                // lock is engaged.  Sits below the lives HUD, above the
                // home button.  Tap anywhere to release the lock.
                if isArming { tapToStartOverlay }

                // Overlays
                // Oops is suppressed when the player has just used their
                // last life — `showOutOfLives` takes over and surfaces
                // the buy / watch-ad / quit choices instead.  Without
                // this guard, both overlays render in the same frame and
                // the "Oops!" text bleeds through behind Out of Lives.
                if phase == .fell && !showOutOfLives && !showDailyFailed { oopsOverlay }
                if phase == .levelComplete { winOverlay }

                // Coin Pit: round-over payout — the haul, Play Again, Home.
                // Coin Pit never uses .fell/.levelComplete, so this is its
                // only end screen.  Gated so no other mode can surface it.
                if isCoinPit && coinPitOver { coinPitPayoutOverlay }

                // Gold Rush stake screen — buy the round with tickets before
                // the clock starts.  The home button (below) stays on top so
                // the player can back out without spending anything.
                if isCoinPit && !coinPitStaked && !coinPitOver { coinPitStakeOverlay }

                // Out-of-lives overlay — shown when the player tries to play
                // with zero lives.  Sits above the Oops/Win overlays.
                if showOutOfLives { outOfLivesOverlay }

                // Challenge-of-the-Day failure — out of attempts for the day.
                if showDailyFailed { dailyFailedOverlay }

                // Home button — rendered AFTER oops/win overlays so it stays
                // tappable while they're showing.  Hidden during the one-time
                // welcome moment and tutorial reward modal so it doesn't
                // compete for attention with those flows.
                // Home button — also hidden while the player is holding the Zen
                // garden (everything clears so they just roll).
                if !showWelcomeMoment && !showTutorialReward
                    && !(isCoinPit && coinPitOver)
                    && !(usesSandTrail && zenTouching) {
                    homeButtonOverlay(safeBottom: geo.safeAreaInsets.bottom)
                }

                // Zen Garden tools — bottom-right dropdown (wind ▸ pattern ▸
                // tree).  Replaces the old standalone rake button.  Hidden while
                // the player is holding the garden to roll.
                if usesSandTrail && !zenTouching {
                    ZenToolsOverlay(
                        menuOpen:    $zenMenuOpen,
                        submenu:     $zenSubmenu,
                        pattern:     $zenPattern,
                        placingItem: $zenPlacingItem,
                        haptics:     gameState.hapticsEnabled,
                        onSmoothSand: { smoothSand() },
                        onClearItems: { zenDecorations.removeAll() }
                    )
                    .padding(.bottom, geo.safeAreaInsets.bottom)
                }

                // Continuous auto-track speed — a vertical drag bar on the upper
                // half of the right edge, shown only while a pattern is running.
                if usesSandTrail && zenPattern != nil && !zenTouching {
                    HStack {
                        Spacer()
                        ZenSpeedBar(fraction: $zenSpeedFraction, haptics: gameState.hapticsEnabled)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, geo.safeAreaInsets.top + 54)
                    .padding(.trailing, 18)
                }

                if showWelcomeMoment       { welcomeMomentOverlay }
                if showTutorialReward      { tutorialRewardOverlay }

                // Screen border — always on top, colour reacts to game state
                screenBorder
            }
            // Quick screen-shake when the ball falls.
            .keyframeAnimator(
                initialValue: CGFloat(0),
                trigger: shakeTrigger
            ) { content, value in
                content.offset(x: value)
            } keyframes: { _ in
                LinearKeyframe(-5, duration: 0.04)
                LinearKeyframe( 5, duration: 0.05)
                LinearKeyframe(-4, duration: 0.05)
                LinearKeyframe( 4, duration: 0.05)
                LinearKeyframe(-2, duration: 0.05)
                LinearKeyframe( 0, duration: 0.04)
            }
            .onAppear {
                arenaSize = geo.size
                // Snapshot any accumulated regen ticks into stored `lives`
                // before we read displayedLives in spawnBall.
                gameState.commitRegen()
                spawnBall(in: geo.size)
            }
            .onReceive(clock.$tickCount) { _ in
                tick(geoSize: geo.size)
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear  {
            motion.start(); clock.start(); AudioManager.shared.prepareIfNeeded()
            if activeMode.id == "zen" { zenStart = Date() }
        }
        .onDisappear {
            motion.stop()
            clock.stop()
            refundUnplayedCoinPitBlocks()   // Gold Rush early-exit refund
            if activeMode.id == "zen", let z = zenStart {
                gameState.addZenSeconds(Int(Date().timeIntervalSince(z)))   // Zen time leaderboard + reward
                zenStart = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clock.stop(); motion.stop() }
            else if phase == .active && self.phase == .playing { clock.start(); motion.start() }
        }
        // Start each newly-selected auto-track from its origin (top-left / outer
        // corner) so the pattern lays down cleanly rather than mid-sweep.
        .onChange(of: zenPattern) { _, _ in zenPatternPhase = 0 }
    }

    // MARK: - Border

    private var screenBorder: some View {
        // RoundedRectangle with cornerRadius pulled from the actual device's
        // display corner radius, so the stroke traces the screen curve exactly.
        ZStack {
            RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderPhase == .normal ? 4 : 5)
                .animation(.easeInOut(duration: 0.35), value: borderPhase)

            // Legendary boundaries wear a bespoke animated texture on top of
            // the base stroke.  It fades out whenever the border leaves the
            // .normal phase so the semantic state colours (arming-bright,
            // fell-red, won-green) always read unobstructed, then fades back
            // in.  Reduce Motion keeps the plain static stroke above.
            if !reduceMotion {
                legendaryBorderOverlay
                    .opacity(borderPhase == .normal ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.35), value: borderPhase)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Legendary boundary textures
    //
    // Bespoke animated strokes for the three Legendary boundaries
    // (obsidian / candy / circuit).  Each layers TimelineView-driven motion
    // onto the same screen-tracing RoundedRectangle geometry as the base
    // stroke; Standard/Rare boundaries and Classic stay plain flat strokes.

    @ViewBuilder
    private var legendaryBorderOverlay: some View {
        switch gameState.equippedBoundary {
        case .obsidian: obsidianBorderOverlay
        case .candy:    candyBorderOverlay
        case .circuit:  circuitBorderOverlay
        default:        EmptyView()
        }
    }

    /// The border ring shape, inset so a centred `.stroke(lineWidth: 4)`
    /// occupies the same pixels as the base `strokeBorder(lineWidth: 4)`.
    private func borderRing() -> some InsettableShape {
        RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
            .inset(by: 2)
    }

    /// A glowing segment of the border ring at perimeter position
    /// `position` (0…1, wraps) spanning `length` of the perimeter.
    /// Drawn as two trims so segments crossing the trim origin still render.
    private func borderTrimSegment(at position: Double,
                                   length: Double,
                                   color: Color,
                                   lineWidth: CGFloat,
                                   blur: CGFloat) -> some View {
        let raw: Double = position.truncatingRemainder(dividingBy: 1.0)
        let start: Double = raw < 0 ? raw + 1.0 : raw
        let end: Double = start + length
        let firstEnd: Double = min(1.0, end)
        let wrapEnd: Double = max(0.0, end - 1.0)
        return ZStack {
            borderRing()
                .trim(from: CGFloat(start), to: CGFloat(firstEnd))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            borderRing()
                .trim(from: 0, to: CGFloat(wrapEnd))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .blur(radius: blur)
    }

    /// Obsidian — molten glass: the dark base stroke carries a slow-drifting
    /// purple-tinted sheen (plus a fainter trailing echo) and an occasional
    /// ember-glow pulse that creeps along the rim.
    private var obsidianBorderOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t: Double = tl.date.timeIntervalSinceReferenceDate
            let sheenPos: Double = (t * 0.040).truncatingRemainder(dividingBy: 1.0)
            let echoPos: Double = sheenPos + 0.47
            let emberPos: Double = (t * 0.012 + 0.31).truncatingRemainder(dividingBy: 1.0)
            let emberGate: Double = max(0.0, sin(t * 0.55))
            let emberGlow: Double = pow(emberGate, 5.0)          // brief, occasional
            let sheen: Color = Color(red: 0.58, green: 0.42, blue: 0.92)
            let echo: Color = Color(red: 0.44, green: 0.33, blue: 0.78)
            let ember: Color = Color(red: 1.00, green: 0.46, blue: 0.16)
            ZStack {
                borderTrimSegment(at: sheenPos, length: 0.16,
                                  color: sheen.opacity(0.55), lineWidth: 4, blur: 1.5)
                borderTrimSegment(at: echoPos, length: 0.10,
                                  color: echo.opacity(0.38), lineWidth: 4, blur: 2.2)
                borderTrimSegment(at: emberPos, length: 0.05,
                                  color: ember.opacity(0.80 * emberGlow), lineWidth: 5, blur: 3.0)
            }
        }
    }

    /// Candy — candy-cane stripes scrolling along the rim: white + deep-red
    /// dashes phase-shifted over the pink base stroke, plus a soft drifting
    /// sugar-glint highlight.
    private var candyBorderOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t: Double = tl.date.timeIntervalSinceReferenceDate
            let scroll: CGFloat = CGFloat((t * 16.0).truncatingRemainder(dividingBy: 28.0))
            let glintPos: Double = (t * 0.055).truncatingRemainder(dividingBy: 1.0)
            let glintPulse: Double = 0.55 + 0.45 * sin(t * 2.1)
            let stripeRed: Color = Color(red: 0.85, green: 0.16, blue: 0.34)
            ZStack {
                borderRing()
                    .stroke(Color.white.opacity(0.85),
                            style: StrokeStyle(lineWidth: 4, dash: [8, 20], dashPhase: scroll))
                borderRing()
                    .stroke(stripeRed.opacity(0.80),
                            style: StrokeStyle(lineWidth: 4, dash: [8, 20], dashPhase: scroll - 14.0))
                borderTrimSegment(at: glintPos, length: 0.06,
                                  color: Color.white.opacity(0.50 * glintPulse),
                                  lineWidth: 5, blur: 2.0)
            }
        }
    }

    /// Circuit — dark teal board with brighter trace-segments travelling
    /// around the ring like signals, plus three fixed nodes that blink
    /// intermittently.
    private var circuitBorderOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t: Double = tl.date.timeIntervalSinceReferenceDate
            let tracePhase: CGFloat = CGFloat((-t * 26.0).truncatingRemainder(dividingBy: 46.0))
            let signalPos: Double = (t * 0.09).truncatingRemainder(dividingBy: 1.0)
            let blinkA: Double = pow(max(0.0, sin(t * 2.3)), 6.0)
            let blinkB: Double = pow(max(0.0, sin(t * 1.7 + 2.1)), 6.0)
            let blinkC: Double = pow(max(0.0, sin(t * 2.9 + 4.4)), 6.0)
            let board: Color = Color(red: 0.05, green: 0.20, blue: 0.18)
            let trace: Color = Color(red: 0.35, green: 1.00, blue: 0.78)
            let node: Color = Color(red: 0.80, green: 1.00, blue: 0.92)
            ZStack {
                // Dark teal board laid over the base stroke.
                borderRing()
                    .stroke(board.opacity(0.85), lineWidth: 4)
                // Etched traces drifting like clocked signals.
                borderRing()
                    .stroke(trace.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2, dash: [16, 30], dashPhase: tracePhase))
                // One bright packet racing the ring.
                borderTrimSegment(at: signalPos, length: 0.03,
                                  color: trace.opacity(0.95), lineWidth: 3, blur: 1.5)
                // Fixed solder nodes, blinking out of phase.
                borderTrimSegment(at: 0.12, length: 0.012,
                                  color: node.opacity(0.90 * blinkA), lineWidth: 5, blur: 1.0)
                borderTrimSegment(at: 0.55, length: 0.012,
                                  color: node.opacity(0.90 * blinkB), lineWidth: 5, blur: 1.0)
                borderTrimSegment(at: 0.82, length: 0.012,
                                  color: node.opacity(0.90 * blinkC), lineWidth: 5, blur: 1.0)
            }
        }
    }

    // MARK: - Layout helpers

    private func goalPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: layout.goal.x * size.width, y: layout.goal.y * size.height)
    }

    private func startPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: layout.start.x * size.width, y: layout.start.y * size.height)
    }

    // MARK: - Sub-views

    private func holeLayer(geo: GeometryProxy) -> some View {
        ForEach(Array(effectiveLayout.holeRects.enumerated()), id: \.offset) { _, norm in
            let w = norm.width  * geo.size.width
            let h = norm.height * geo.size.height
            let x = (norm.origin.x + norm.width  / 2) * geo.size.width
            let y = (norm.origin.y + norm.height / 2) * geo.size.height
            ZStack {
                Rectangle().fill(pit.color)
                // Animated pit overlays — Evil flames, Sky clouds, Pond
                // ripples — paint over the base colour.  Reduce Motion
                // suppresses the animation; the static base remains.
                if !reduceMotion {
                    switch pit {
                    case .evil:      evilPitOverlay
                    case .sky:       skyPitOverlay
                    case .pond:      pondPitOverlay
                    case .space:     spacePitOverlay
                    case .eclipse:   eclipsePitOverlay
                    case .nightclub: nightclubPitOverlay
                    default:         EmptyView()
                    }
                }

                // Depth shade — a soft inset shadow around the rim plus a
                // darker pooling toward the centre, so EVERY pit (even the
                // flat-colour Standard ones) reads as a recess the ball
                // falls into rather than a painted-on patch.  Drawn last so
                // it deepens the animated overlays too.
                pitDepthShade(width: w, height: h)
            }
            .frame(width: w, height: h)
            .clipped()   // keep the inset-shadow blur inside the hole
            .position(x: x, y: y)
        }
    }

    /// Inset-shadow + centre-pooling overlay that gives a hole visual depth.
    /// Sized to the hole rect so the rim shadow scales with the opening.
    private func pitDepthShade(width w: CGFloat, height h: CGFloat) -> some View {
        let minDim = min(w, h)
        return ZStack {
            // Centre pooling — darkest in the middle, fading out toward the
            // rim, so the floor of the pit feels far below.
            Rectangle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.45),
                            Color.black.opacity(0.0),
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: max(w, h) * 0.62
                    )
                )
                .blendMode(.multiply)
            // Inset rim shadow — a blurred dark border hugging the opening.
            Rectangle()
                .strokeBorder(Color.black.opacity(0.55),
                              lineWidth: max(3, minDim * 0.12))
                .blur(radius: max(2, minDim * 0.07))
                .blendMode(.multiply)
        }
        .allowsHitTesting(false)
    }

    /// Renders coins for this level.  Coins picked up THIS attempt disappear
    /// instantly so the player gets immediate feedback.  Coins already banked
    /// across past attempts render dimmed but visible (signal that this slot
    /// has already been collected).
    private func coinLayer(geo: GeometryProxy) -> some View {
        let banked = bankedCoinIndices
        return ForEach(Array(effectiveLayout.coins.enumerated()), id: \.offset) { idx, norm in
            if !coinsPickedThisAttempt.contains(idx) {
                coinView(banked: banked.contains(idx), index: idx)
                    .position(
                        x: norm.x * geo.size.width,
                        y: norm.y * geo.size.height
                    )
            }
        }
    }

    /// Animated spinning coin.  The 2D illusion of a 3D spin is achieved by
    /// oscillating scale-X between 0.18 (edge-on, looks like a thin line)
    /// and 1.0 (full face).  A small vertical bob keeps it feeling alive.
    /// Each coin is phased differently so they don't spin in unison.
    ///
    /// Already-banked coins render dimmed and static so the player can see
    /// where the previous coin was without it being grabby.
    @ViewBuilder
    private func coinView(banked: Bool, index: Int) -> some View {
        if banked {
            BankedCoinView(size: coinRadius * 2)
        } else {
            SpinningCoinView(
                size: coinRadius * 2,
                phase: Double(index) * 1.7
            )
        }
    }

    /// Grass floor overlay (Golf bundle) — scatter of small grass
    /// blade tufts on top of the base fairway green, with a gentle
    /// breeze sway on the blade tips and the occasional drifting
    /// seed/firefly mote.  Under Reduce Motion the sway amplitude is
    /// zero and the motes are skipped, so the frozen frame is exactly
    /// the old static tuft texture.  Tuft positions come from a
    /// deterministic seeded "random" so they don't shift between
    /// frames; sway phase derives from position so the RNG call
    /// sequence (and thus the layout) is unchanged.
    private var grassFloorOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                // Zero amplitude under Reduce Motion — static fallback.
                let swayAmp: CGFloat = reduceMotion ? 0.0 : 1.4

                // Deterministic pseudo-random so tufts stay put across
                // frames.  A small linear-congruential generator state.
                var state: UInt64 = 0x9E3779B97F4A7C15
                func rand() -> Double {
                    state = state &* 6364136223846793005 &+ 1442695040888963407
                    return Double(state >> 11) / Double(1 << 53)
                }

                let tuftCount = Int(size.width * size.height / 800)  // ~one per 800 sqpt
                let blade = Color(red: 0.18, green: 0.40, blue: 0.12)
                let bladeBright = Color(red: 0.55, green: 0.78, blue: 0.32)

                for _ in 0..<tuftCount {
                    let cx = CGFloat(rand()) * size.width
                    let cy = CGFloat(rand()) * size.height
                    // Breeze phase from position (not rand()) so the RNG
                    // sequence stays identical to the static layout.
                    let phase: Double = Double(cx) * 0.13 + Double(cy) * 0.07
                    let sway: CGFloat = swayAmp * CGFloat(sin(t * 1.1 + phase))
                    // A tuft = 2-3 thin upward slashes.
                    let blades = 2 + Int(rand() * 2)
                    for b in 0..<blades {
                        let offsetX = CGFloat(rand() - 0.5) * 6
                        let tilt = CGFloat(rand() - 0.5) * 4
                        var path = Path()
                        path.move(to: CGPoint(x: cx + offsetX, y: cy + 3))
                        path.addLine(to: CGPoint(x: cx + offsetX + tilt + sway, y: cy - 6 + CGFloat(rand()) * 4))
                        ctx.stroke(
                            path,
                            with: .color(b == 0 ? bladeBright : blade),
                            lineWidth: 1.0
                        )
                    }
                }

                // Drifting seed / firefly motes — sparse glowing specks
                // that ride the breeze diagonally and fade in/out.
                // Motion-only, so skipped entirely under Reduce Motion.
                if !reduceMotion {
                    var mote = ctx
                    mote.blendMode = .plusLighter
                    var mrng = SeededRNG(seed: 0x6F1E_F1E5)
                    let moteCount = 7
                    for i in 0..<moteCount {
                        let lane: CGFloat = CGFloat(mrng.nextUnit())
                        let speed: Double = 0.030 + mrng.nextUnit() * 0.035
                        let mPhase: Double = mrng.nextUnit()
                        // 0→1 loop, drifting left-to-right with a bobbing y.
                        let prog: Double = (t * speed + mPhase).truncatingRemainder(dividingBy: 1.0)
                        let mx: CGFloat = CGFloat(prog) * (size.width + 40) - 20
                        let bob: CGFloat = CGFloat(sin(t * 0.8 + Double(i) * 1.9)) * size.height * 0.04
                        let my: CGFloat = lane * size.height + bob
                        let fade: Double = sin(prog * .pi)   // dim at both ends
                        // Alternate warm firefly / pale seed.
                        let warm: Bool = i % 2 == 0
                        let moteColor: Color = warm
                            ? Color(red: 0.95, green: 0.90, blue: 0.45)
                            : Color(red: 0.90, green: 0.95, blue: 0.80)
                        let mr: CGFloat = warm ? 1.6 : 1.1
                        mote.fill(
                            Path(ellipseIn: CGRect(x: mx - mr, y: my - mr, width: mr * 2, height: mr * 2)),
                            with: .color(moteColor.opacity(0.55 * fade)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Moon floor overlay (Space Travel bundle) — scatter of craters on
    /// the pale-grey regolith base.  Each crater is a darker disc with a
    /// lighter lower-rim crescent so it reads as a shallow bowl lit from
    /// the upper-left.  The rim light now drifts very slowly around each
    /// bowl (a sun-angle parallax feel) and a thin veil of star-glint
    /// dust twinkles across the regolith.  Under Reduce Motion the drift
    /// amplitude is zero and the dust is skipped — the frozen frame is
    /// exactly the old static crater field.  Deterministic seeded
    /// placement so craters don't shift between frames.
    private var moonFloorOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                var rng = SeededRNG(seed: 0x5EED_0C24)
                // ~one crater per 5500 sqpt — sparse so it reads as terrain.
                let craterCount = max(8, Int(size.width * size.height / 5500))
                let floorBase = Color(red: 0.62, green: 0.62, blue: 0.66)
                for _ in 0..<craterCount {
                    let cx = CGFloat(rng.nextUnit()) * size.width
                    let cy = CGFloat(rng.nextUnit()) * size.height
                    let r  = 6 + CGFloat(rng.nextUnit()) * 22
                    // Slow shadow drift — phase from position (not rand())
                    // so the RNG sequence, and thus the crater layout,
                    // matches the old static render exactly.  Zero at t=0.
                    let dPhase: Double = Double(cx) * 0.05 + Double(cy) * 0.03
                    let drift: Double = reduceMotion ? 0.0 : sin(t * 0.12 + dPhase) * 14.0
                    let shadeDX: CGFloat = reduceMotion ? 0.0 : CGFloat(sin(t * 0.12 + dPhase)) * r * 0.06
                    // Crater bowl — slightly darker than the regolith.
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                        with: .radialGradient(
                            Gradient(colors: [
                                floorBase.opacity(0.0),
                                Color(red: 0.42, green: 0.42, blue: 0.46).opacity(0.55),
                            ]),
                            center: CGPoint(x: cx + shadeDX, y: cy),
                            startRadius: r * 0.30,
                            endRadius:   r
                        )
                    )
                    // Dark inner shadow (upper-left, where the wall faces away).
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                        with: .color(Color(red: 0.30, green: 0.30, blue: 0.34).opacity(0.40)),
                        lineWidth: 1.2
                    )
                    // Bright lower-right rim crescent (sunlit far wall) —
                    // its arc swings gently with the drifting sun angle.
                    var rim = Path()
                    rim.addArc(center: CGPoint(x: cx, y: cy), radius: r * 0.96,
                               startAngle: .degrees(20 + drift), endAngle: .degrees(150 + drift), clockwise: false)
                    ctx.stroke(rim, with: .color(Color.white.opacity(0.30)), lineWidth: 1.0)
                }

                // Star-glint dust — tiny bright specks in the regolith that
                // catch the light and twinkle, drifting almost imperceptibly.
                // Motion-only, so skipped under Reduce Motion.
                if !reduceMotion {
                    var dust = ctx
                    dust.blendMode = .plusLighter
                    var drng = SeededRNG(seed: 0xD057_FADE)
                    let dustCount = 16
                    for i in 0..<dustCount {
                        let gx0: CGFloat = CGFloat(drng.nextUnit()) * size.width
                        let gy0: CGFloat = CGFloat(drng.nextUnit()) * size.height
                        let gPhase: Double = drng.nextUnit() * 6.28
                        let gx: CGFloat = gx0 + CGFloat(sin(t * 0.05 + gPhase)) * 6
                        let gy: CGFloat = gy0 + CGFloat(cos(t * 0.04 + gPhase)) * 4
                        let twinkle: Double = 0.5 + 0.5 * sin(t * 1.8 + Double(i) * 2.3)
                        let gr: CGFloat = 0.7 + CGFloat(drng.nextUnit()) * 0.9
                        dust.fill(
                            Path(ellipseIn: CGRect(x: gx - gr, y: gy - gr, width: gr * 2, height: gr * 2)),
                            with: .color(Color.white.opacity(0.10 + 0.30 * twinkle)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Disco floor overlay — full-screen grid of squares whose hues
    /// cycle through the spectrum on a diagonal wave.  Each cell is
    /// `cellSize` × `cellSize`; hue is keyed off `(col, row, time)`
    /// so adjacent cells differ slightly, giving the dance-floor
    /// ripple.  30Hz cap keeps CPU modest at this density.
    private var discoFloorOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let cellSize: CGFloat = 62
                let cols = Int(ceil(size.width  / cellSize))
                let rows = Int(ceil(size.height / cellSize))
                for row in 0..<rows {
                    for col in 0..<cols {
                        let phase = Double(col) * 0.18 + Double(row) * 0.12
                        let hue   = (t * 0.30 + phase).truncatingRemainder(dividingBy: 1.0)
                        let pulse = 0.55 + 0.35 * sin(t * 1.6 + phase * 4)
                        let color = Color(hue: hue, saturation: 0.85, brightness: 0.95)
                        // Leave a small dark gutter between cells so
                        // the grid reads as discrete tiles.
                        let inset: CGFloat = 2
                        ctx.fill(
                            Path(CGRect(
                                x: CGFloat(col) * cellSize + inset,
                                y: CGFloat(row) * cellSize + inset,
                                width: cellSize - inset * 2,
                                height: cellSize - inset * 2
                            )),
                            with: .color(color.opacity(pulse))
                        )
                    }
                }
            }
        }
    }

    /// Grid City floor overlay (Neon City bundle) — a synthwave neon
    /// perspective grid.  Horizontal lines bunch toward a horizon set at
    /// ~38% screen height (above it, a magenta→indigo sky glow); below,
    /// vertical lines fan out from the vanishing point toward the bottom
    /// edge, and horizontal lines spaced by a perspective curve recede to
    /// the horizon and scroll slowly toward the viewer.  Magenta + cyan
    /// glowing gridlines on near-black.  Under Reduce Motion the scroll
    /// freezes (the grid stays put) so it's safe and still textured.
    private var gridCityFloorOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let horizonY = h * 0.38
                let vpX = w / 2                       // vanishing point x

                // Sky glow above the horizon — magenta high → indigo low.
                ctx.fill(
                    Path(CGRect(x: 0, y: 0, width: w, height: horizonY)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.10, green: 0.02, blue: 0.18),
                            Color(red: 0.42, green: 0.06, blue: 0.42),
                            Color(red: 0.85, green: 0.18, blue: 0.62).opacity(0.55),
                        ]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: horizonY)))
                // A bright neon sun-line right on the horizon.
                var hline = Path()
                hline.move(to: CGPoint(x: 0, y: horizonY))
                hline.addLine(to: CGPoint(x: w, y: horizonY))
                ctx.stroke(hline, with: .color(Color(red: 1.0, green: 0.45, blue: 0.95).opacity(0.85)),
                           lineWidth: 2.0)

                let cyan    = Color(red: 0.20, green: 0.95, blue: 1.0)
                let magenta = Color(red: 1.0,  green: 0.30, blue: 0.85)

                // Vertical lines fanning from the vanishing point to the
                // bottom edge.  Evenly spaced along the bottom; all meet at
                // (vpX, horizonY).
                let verticals = 14
                for i in 0...verticals {
                    let f = CGFloat(i) / CGFloat(verticals)
                    let bottomX = (f - 0.5) * w * 2.2 + vpX   // spread wider than screen
                    var p = Path()
                    p.move(to: CGPoint(x: vpX, y: horizonY))
                    p.addLine(to: CGPoint(x: bottomX, y: h))
                    ctx.stroke(p, with: .color(cyan.opacity(0.35)), lineWidth: 1.4)
                    ctx.stroke(p, with: .color(cyan.opacity(0.85)), lineWidth: 0.6)
                }

                // Horizontal lines receding to the horizon, spaced by a
                // perspective curve and scrolling toward the viewer.  We
                // parametrize by k in [0,1): depth = fract(k + scroll); the
                // screen y uses a 1/(1-depth) falloff so lines bunch near
                // the horizon and spread near the bottom.
                let rows = 16
                let scroll = (t * 0.18).truncatingRemainder(dividingBy: 1.0 / Double(rows))
                for i in 0..<rows {
                    let depth = (Double(i) / Double(rows) + scroll).truncatingRemainder(dividingBy: 1.0)
                    // Perspective: depth 0 = horizon, depth 1 = bottom edge.
                    let persp = pow(depth, 2.2)                // ease so near rows are far apart
                    let y = horizonY + CGFloat(persp) * (h - horizonY)
                    guard y > horizonY && y <= h else { continue }
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                    // Nearer rows are brighter / thicker.
                    let near = CGFloat(persp)
                    ctx.stroke(p, with: .color(magenta.opacity(0.25 + 0.55 * Double(near))),
                               lineWidth: 0.6 + 1.6 * near)
                }
            }
        }
    }

    /// Money Full floor (top-coin-pack ($49.99) IAP secret) — a dense, overlapping tiling
    /// of $100 bills laid out brick-fashion so they read as a heaped stack.
    /// Static + deterministic, so it renders identically every frame.
    private var moneyFloorOverlay: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let billW: CGFloat = 150, billH: CGFloat = 66
            let stepX = billW * 0.72            // horizontal overlap
            let stepY = billH * 0.62            // vertical overlap
            let cols = Int(ceil(w / stepX)) + 2
            let rows = Int(ceil(h / stepY)) + 2
            // Top-to-bottom, left-to-right: later bills overlap earlier ones, so
            // the stack reads with each bill layered over the one above it.
            for row in 0..<rows {
                let oy = CGFloat(row) * stepY - billH * 0.3
                let rowOffset: CGFloat = (row % 2 == 0) ? 0 : stepX * 0.5
                for col in 0..<cols {
                    let ox = CGFloat(col) * stepX - billW * 0.4 - rowOffset
                    drawHundred(ctx, CGRect(x: ox, y: oy, width: billW, height: billH))
                }
            }
        }
    }

    /// One $100 bill for the Money Full floor — green paper with a drop shadow
    /// (to lift it off the stack below), an inner frame, a centre portrait oval,
    /// and "100" in two opposite corners.
    private func drawHundred(_ ctx: GraphicsContext, _ rect: CGRect) {
        let paper  = Color(red: 0.62, green: 0.78, blue: 0.62)
        let paperD = Color(red: 0.40, green: 0.60, blue: 0.45)
        let ink    = Color(red: 0.11, green: 0.33, blue: 0.21)
        let r = min(rect.width, rect.height) * 0.10
        // Drop shadow under this bill so it sits above the row beneath it.
        ctx.fill(Path(roundedRect: rect.offsetBy(dx: 1.5, dy: 2.5), cornerRadius: r),
                 with: .color(.black.opacity(0.18)))
        let bill = Path(roundedRect: rect, cornerRadius: r)
        ctx.fill(bill, with: .linearGradient(Gradient(colors: [paper, paperD]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            endPoint:   CGPoint(x: rect.minX, y: rect.maxY)))
        ctx.stroke(bill, with: .color(ink.opacity(0.6)), lineWidth: 1.2)
        // Inner frame.
        ctx.stroke(Path(roundedRect: rect.insetBy(dx: rect.width * 0.05, dy: rect.height * 0.10),
                        cornerRadius: r * 0.6),
                   with: .color(ink.opacity(0.32)), lineWidth: 0.8)
        // Centre portrait oval.
        let ow = rect.width * 0.26, oh = rect.height * 0.62
        let oc = CGRect(x: rect.midX - ow / 2, y: rect.midY - oh / 2, width: ow, height: oh)
        ctx.fill(Path(ellipseIn: oc), with: .color(paperD.opacity(0.7)))
        ctx.stroke(Path(ellipseIn: oc), with: .color(ink.opacity(0.5)), lineWidth: 0.8)
        // "100" in two opposite corners.
        let label = ctx.resolve(
            Text("100").font(.system(size: rect.height * 0.24, weight: .heavy, design: .rounded))
                .foregroundStyle(ink.opacity(0.72)))
        let ix = rect.width * 0.17, iy = rect.height * 0.27
        ctx.draw(label, at: CGPoint(x: rect.minX + ix, y: rect.minY + iy), anchor: .center)
        ctx.draw(label, at: CGPoint(x: rect.maxX - ix, y: rect.maxY - iy), anchor: .center)
    }

    /// Brass Works floor overlay (Clockwork bundle) — riveted brass/bronze
    /// plating laid out as a seamed grid of plates, each with a rivet at its
    /// corners and a faint engraved cog outline, over a warm metallic sheen.
    /// The engraved cogs now slowly ROTATE — alternating direction like a
    /// meshed gear train — and a bright highlight band travels diagonally
    /// across the plating.  Under Reduce Motion the clock freezes at t=0
    /// (cogs at their original angle) and the traveling sheen is skipped,
    /// so the frozen frame is exactly the old static plating.
    /// Deterministic seeded placement so it doesn't shift between frames.
    private var brassFloorOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height

                // Warm metallic sheen — a soft diagonal highlight band.
                ctx.fill(
                    Path(CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.62, green: 0.45, blue: 0.20).opacity(0.0),
                            Color(red: 0.92, green: 0.74, blue: 0.40).opacity(0.30),
                            Color(red: 0.40, green: 0.27, blue: 0.10).opacity(0.30),
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint:   CGPoint(x: w, y: h)))

                // Seamed plates.
                let plate: CGFloat = 96
                let seam   = Color(red: 0.22, green: 0.14, blue: 0.05).opacity(0.55)
                let groove = Color(red: 0.98, green: 0.84, blue: 0.50).opacity(0.30)
                let rivet  = Color(red: 0.98, green: 0.86, blue: 0.52)
                let rivetD = Color(red: 0.40, green: 0.26, blue: 0.10)
                let cog    = Color(red: 0.30, green: 0.20, blue: 0.08).opacity(0.28)

                let cols = Int(ceil(w / plate))
                let rows = Int(ceil(h / plate))
                var rng = SeededRNG(seed: 0xB8A5_5C06)
                for row in 0..<rows {
                    for col in 0..<cols {
                        let x = CGFloat(col) * plate
                        let y = CGFloat(row) * plate
                        let rect = CGRect(x: x, y: y, width: plate, height: plate)
                        // Plate seam (dark groove + bright highlight just inside).
                        ctx.stroke(Path(rect), with: .color(seam), lineWidth: 2.0)
                        ctx.stroke(Path(rect.insetBy(dx: 1.5, dy: 1.5)), with: .color(groove), lineWidth: 0.8)

                        // Faint engraved cog outline in the plate centre on
                        // some plates — slowly turning, alternating direction
                        // checkerboard-fashion like a meshed gear train.  The
                        // spin term is 0 at t=0, so Reduce Motion shows the
                        // cogs at their original engraved angle.
                        if rng.nextUnit() < 0.55 {
                            let ccx = x + plate / 2
                            let ccy = y + plate / 2
                            let cr  = plate * 0.26
                            let dir: Double = ((row + col) % 2 == 0) ? 1.0 : -1.0
                            let spin: Double = t * 0.22 * dir
                            let teeth = 10
                            var p = Path()
                            let n = teeth * 2
                            for k in 0..<n {
                                let a: Double = Double(k) / Double(n) * 2 * .pi + spin
                                let rad = (k % 2 == 0) ? cr : cr * 0.78
                                let pt = CGPoint(x: ccx + CGFloat(cos(a)) * rad, y: ccy + CGFloat(sin(a)) * rad)
                                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                            }
                            p.closeSubpath()
                            ctx.stroke(p, with: .color(cog), lineWidth: 1.2)
                            let hr = cr * 0.30
                            ctx.stroke(Path(ellipseIn: CGRect(x: ccx - hr, y: ccy - hr, width: hr * 2, height: hr * 2)),
                                       with: .color(cog), lineWidth: 1.0)
                        }

                        // Rivets at the four plate corners.
                        let rr: CGFloat = 3.0
                        for (rx, ry) in [(x + 7, y + 7), (x + plate - 7, y + 7),
                                         (x + 7, y + plate - 7), (x + plate - 7, y + plate - 7)] {
                            ctx.fill(Path(ellipseIn: CGRect(x: rx - rr, y: ry - rr, width: rr * 2, height: rr * 2)),
                                with: .radialGradient(Gradient(colors: [rivet, rivetD]),
                                    center: CGPoint(x: rx - rr * 0.3, y: ry - rr * 0.3),
                                    startRadius: 0, endRadius: rr))
                        }
                    }
                }

                // Traveling sheen — a soft diagonal light band that sweeps
                // across the plating, like lamplight gliding over polished
                // brass.  Motion-only, so skipped under Reduce Motion.
                if !reduceMotion {
                    var shine = ctx
                    shine.blendMode = .plusLighter
                    // Band position cycles along the w+h diagonal span.
                    let span: CGFloat = w + h
                    let prog: Double = (t * 0.055).truncatingRemainder(dividingBy: 1.0)
                    let bandC: CGFloat = CGFloat(prog) * (span + 320) - 160
                    let bandHalf: CGFloat = 90
                    var band = Path()
                    band.move(to:    CGPoint(x: bandC - bandHalf, y: 0))
                    band.addLine(to: CGPoint(x: bandC + bandHalf, y: 0))
                    band.addLine(to: CGPoint(x: bandC + bandHalf - h, y: h))
                    band.addLine(to: CGPoint(x: bandC - bandHalf - h, y: h))
                    band.closeSubpath()
                    shine.fill(band, with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 1.0, green: 0.88, blue: 0.55).opacity(0.0),  location: 0.0),
                            .init(color: Color(red: 1.0, green: 0.88, blue: 0.55).opacity(0.14), location: 0.5),
                            .init(color: Color(red: 1.0, green: 0.88, blue: 0.55).opacity(0.0),  location: 1.0),
                        ]),
                        startPoint: CGPoint(x: bandC - bandHalf, y: 0),
                        endPoint:   CGPoint(x: bandC + bandHalf, y: 0)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Evil pit — fire pit animation inside a single hole rect.  A
    /// vertical heat gradient at the back, then 3-5 flickering flame
    /// shapes (overlapping radial gradients) animated by independent
    /// sine offsets.  Each flame's height + width pulse so the fire
    /// breathes.
    private var evilPitOverlay: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate

                // Back gradient — coal → ember → flame tip.
                ctx.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 0.05, green: 0.00, blue: 0.00), location: 0.00),
                            .init(color: Color(red: 0.42, green: 0.05, blue: 0.00), location: 0.55),
                            .init(color: Color(red: 1.00, green: 0.50, blue: 0.05), location: 0.92),
                            .init(color: Color(red: 1.00, green: 0.85, blue: 0.20), location: 1.00),
                        ]),
                        startPoint: .zero,
                        endPoint:   CGPoint(x: 0, y: size.height)
                    )
                )

                // Flickering flame plumes.
                let flameCount = max(3, Int(size.width / 28))
                for i in 0..<flameCount {
                    let seed = Double(i) * 0.73 + 0.11
                    let baseX = size.width * CGFloat(Double(i) + 0.5) / CGFloat(flameCount)
                    let flicker: Double = sin(t * 7 + seed * 4) * 0.30
                                        + sin(t * 13 + seed * 1.6) * 0.15
                    let flickScale: CGFloat = 0.70 + 0.50 * CGFloat(flicker.magnitude)
                    let flameW = size.width / CGFloat(flameCount) * flickScale
                    let flameHFrac: Double = 0.55 + 0.25 * sin(t * 4 + seed * 2)
                    let flameH = size.height * CGFloat(flameHFrac)
                    let flameX = baseX - flameW / 2
                    let flameY = size.height - flameH
                    let centre = CGPoint(x: flameX + flameW / 2, y: flameY + flameH * 0.75)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: flameX, y: flameY,
                                               width: flameW, height: flameH * 1.4)),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: Color(red: 1.00, green: 0.95, blue: 0.30).opacity(0.95), location: 0.00),
                                .init(color: Color(red: 1.00, green: 0.45, blue: 0.05).opacity(0.65), location: 0.50),
                                .init(color: Color(red: 0.85, green: 0.10, blue: 0.00).opacity(0.00), location: 1.00),
                            ]),
                            center: centre,
                            startRadius: 0,
                            endRadius:   max(flameW, flameH) * 0.80
                        )
                    )
                }

                // Rising embers — sparks that drift up from the fire, wobble
                // side to side, and burn out near the top.  Additive so they
                // glow over the flames.  Seeded so each spark keeps its lane.
                var emberCtx = ctx
                emberCtx.blendMode = .plusLighter
                var rng = SeededRNG(seed: 0xE3B1_0F1A)
                let emberCount = max(6, Int(size.width / 16))
                for _ in 0..<emberCount {
                    let lane  = CGFloat(rng.nextUnit())
                    let speed = 0.10 + rng.nextUnit() * 0.12
                    let phase = rng.nextUnit()
                    // 0 = bottom, 1 = top, looping.
                    let rise  = (t * speed + phase).truncatingRemainder(dividingBy: 1.0)
                    let ex    = lane * size.width + CGFloat(sin(t * 2 + phase * 10)) * size.width * 0.04
                    let ey    = size.height * (1.0 - CGFloat(rise))
                    let fade  = sin(rise * .pi)          // dim at both ends
                    let er    = CGFloat(0.8 + rng.nextUnit() * 1.6)
                    emberCtx.fill(
                        Path(ellipseIn: CGRect(x: ex - er, y: ey - er, width: er * 2, height: er * 2)),
                        with: .color(Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.7 * fade))
                    )
                }
            }
        }
    }

    /// Sky pit — vertical sky-blue gradient with white cloud blobs
    /// drifting from left to right.  Each cloud is several overlapping
    /// circles for a fluffy silhouette; opacity is high enough to
    /// read against the darker pit context while remaining clearly a
    /// "look down at the sky" effect.
    private var skyPitOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate

                // Sky gradient — deeper blue at top, paler at bottom.
                ctx.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.40, green: 0.66, blue: 0.94),
                            Color(red: 0.72, green: 0.88, blue: 1.00),
                        ]),
                        startPoint: .zero,
                        endPoint:   CGPoint(x: 0, y: size.height)
                    )
                )

                // Drifting clouds — count scales with pit width so
                // there's always something on screen.  Each cloud's
                // x-position loops via modulo over twice the pit
                // width (off-screen entry + exit).
                let cloudCount = max(2, Int(size.width / 60))
                for i in 0..<cloudCount {
                    let seed = Double(i) * 1.31 + 0.4
                    let speed = 0.06 + (Double(i % 3)) * 0.02
                    let xPhase = (t * speed + seed).truncatingRemainder(dividingBy: 1.0)
                    let cx = size.width * CGFloat(xPhase) * 1.4 - size.width * 0.2
                    let cyN = 0.20 + 0.55 * (sin(seed * 3) * 0.5 + 0.5)
                    let cy = size.height * CGFloat(cyN)
                    let baseR = min(size.width, size.height) * CGFloat(0.10 + 0.04 * Double(i % 3))
                    // 5 overlapping circles → cumulus silhouette.
                    let offsets: [(CGFloat, CGFloat)] = [
                        (-1.4,  0.0), (-0.6, -0.6), (0.0, -0.4), (0.6, -0.6), (1.4, 0.0),
                    ]
                    for off in offsets {
                        let rx = cx + baseR * off.0
                        let ry = cy + baseR * off.1
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: rx - baseR, y: ry - baseR,
                                                   width: baseR * 2, height: baseR * 2)),
                            with: .color(Color.white.opacity(0.78))
                        )
                    }
                }
            }
        }
    }

    /// Pond pit — calm blue water with concentric ripples + a
    /// floating lily-pad and a single cattail blade.  Used by the
    /// Golf bundle's pond pit.  Subtler motion than Evil/Sky so it
    /// doesn't distract from gameplay.
    private var pondPitOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate

                // Water gradient — deeper teal at top, lighter cyan
                // toward the bottom for depth.
                ctx.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.05, green: 0.22, blue: 0.36),
                            Color(red: 0.18, green: 0.50, blue: 0.62),
                        ]),
                        startPoint: .zero,
                        endPoint:   CGPoint(x: 0, y: size.height)
                    )
                )

                // Caustics — soft bands of light dancing on the surface.
                // Additive cyan blobs drift on offset sine waves so the
                // water shimmers like sun through shallow water.
                var caustic = ctx
                caustic.blendMode = .plusLighter
                let bands = max(4, Int(size.height / 26))
                for b in 0..<bands {
                    let by = (CGFloat(b) + 0.5) / CGFloat(bands) * size.height
                    let drift: Double = sin(t * 1.1 + Double(b) * 0.9)
                    let bxScale: CGFloat = 0.5 + 0.32 * CGFloat(drift)
                    let bx = size.width * bxScale
                    let bwFrac: Double = 0.30 + 0.12 * sin(t * 0.7 + Double(b))
                    let bw = size.width * CGFloat(bwFrac)
                    let bh = max(3, size.height * 0.05)
                    caustic.fill(
                        Path(ellipseIn: CGRect(x: bx - bw / 2, y: by - bh / 2, width: bw, height: bh)),
                        with: .color(Color(red: 0.6, green: 0.95, blue: 1.0)
                            .opacity(0.10 + 0.06 * (0.5 + 0.5 * sin(t * 2 + Double(b)))))
                    )
                }

                // Concentric ripples — slowly expanding circles whose
                // alpha fades as they grow.  Two ripples staggered.
                let cx = size.width * 0.5
                let cy = size.height * 0.5
                for k in 0..<2 {
                    let phase = (t * 0.30 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1.0)
                    let r = min(size.width, size.height) * CGFloat(0.10 + 0.40 * phase)
                    let alpha = 0.40 * (1.0 - phase)
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                        with: .color(Color.white.opacity(alpha)),
                        lineWidth: 1.2
                    )
                }

                // Lily pad — green disc with a wedge missing, like
                // the classic top-down lily silhouette.  Sits in the
                // upper-left quadrant.
                let padR = min(size.width, size.height) * 0.18
                let padCx = size.width * 0.32
                let padCy = size.height * 0.40
                var padPath = Path()
                padPath.addArc(
                    center: CGPoint(x: padCx, y: padCy),
                    radius: padR,
                    startAngle: .degrees(20),
                    endAngle: .degrees(360),
                    clockwise: false
                )
                padPath.addLine(to: CGPoint(x: padCx, y: padCy))
                padPath.closeSubpath()
                ctx.fill(padPath, with: .color(Color(red: 0.18, green: 0.55, blue: 0.22).opacity(0.92)))
                // Tiny pink lily flower at the centre of the pad.
                ctx.fill(
                    Path(ellipseIn: CGRect(x: padCx - 3, y: padCy - 3, width: 6, height: 6)),
                    with: .color(Color(red: 1.00, green: 0.65, blue: 0.78))
                )

                // Cattail blade — narrow vertical stalk on the right
                // edge with a brown sausage at the top.
                let stalkX = size.width * 0.78
                let stalkBase = size.height * 0.95
                let stalkTop = size.height * 0.35
                var stalkPath = Path()
                stalkPath.move(to: CGPoint(x: stalkX, y: stalkBase))
                stalkPath.addLine(to: CGPoint(x: stalkX, y: stalkTop))
                ctx.stroke(stalkPath, with: .color(Color(red: 0.20, green: 0.50, blue: 0.20)), lineWidth: 1.6)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: stalkX - 3, y: stalkTop - 14, width: 6, height: 18)),
                    with: .color(Color(red: 0.42, green: 0.22, blue: 0.06))
                )
            }
        }
    }

    /// Space pit (Space Travel bundle) — a deep-void starfield.  A
    /// faint nebula gradient sits behind ~40 stars that twinkle (each
    /// star's brightness oscillates on its own phase).  A couple of
    /// stars are larger "bright" stars with a cross-glint.  Star
    /// positions are seeded so they stay put; only brightness animates.
    private var spacePitOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate

                // Void background — near-black with a faint purple/blue
                // nebula wash diagonally across.
                ctx.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.02, green: 0.02, blue: 0.08),
                            Color(red: 0.08, green: 0.04, blue: 0.16),
                            Color(red: 0.02, green: 0.03, blue: 0.10),
                        ]),
                        startPoint: .zero,
                        endPoint:   CGPoint(x: size.width, y: size.height)
                    )
                )

                // Starfield — seeded positions, animated twinkle.
                var rng = SeededRNG(seed: 0x57A4_F1E1)
                let starCount = max(20, Int(size.width * size.height / 900))
                for i in 0..<starCount {
                    let sx = CGFloat(rng.nextUnit()) * size.width
                    let sy = CGFloat(rng.nextUnit()) * size.height
                    let baseR = 0.6 + CGFloat(rng.nextUnit()) * 1.4
                    let phase = rng.nextUnit() * 6.28
                    let twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 2.2 + phase))
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: sx - baseR, y: sy - baseR,
                                               width: baseR * 2, height: baseR * 2)),
                        with: .color(Color.white.opacity(twinkle))
                    )
                    // Every ~7th star gets a soft glow + glint cross.
                    if i % 7 == 0 {
                        let glowR = baseR * 4
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: sx - glowR, y: sy - glowR,
                                                   width: glowR * 2, height: glowR * 2)),
                            with: .radialGradient(
                                Gradient(colors: [
                                    Color(red: 0.70, green: 0.85, blue: 1.00).opacity(0.35 * twinkle),
                                    .clear,
                                ]),
                                center: CGPoint(x: sx, y: sy),
                                startRadius: 0, endRadius: glowR
                            )
                        )
                    }
                }

                // Shooting star — every ~3.5s a streak crosses the void on a
                // diagonal, leaving a fading tail.  `cycle` is the time since
                // the last launch; we only draw during its brief flight.
                let period = 3.5
                let cycle  = t.truncatingRemainder(dividingBy: period)
                if cycle < 0.9 {
                    let prog = CGFloat(cycle / 0.9)
                    // Seed start position off the launch index so successive
                    // shooting stars take different paths.
                    var sRng = SeededRNG(seed: UInt64(t / period) &* 0x2545_F491 | 1)
                    let startX = CGFloat(sRng.nextUnit()) * size.width
                    let startY = CGFloat(sRng.nextUnit()) * size.height * 0.4
                    let dx = size.width * 0.7, dy = size.height * 0.5
                    let hx = startX + dx * prog
                    let hy = startY + dy * prog
                    var streak = ctx
                    streak.blendMode = .plusLighter
                    // Tail — a short line behind the head.
                    var tail = Path()
                    tail.move(to: CGPoint(x: hx - dx * 0.10, y: hy - dy * 0.10))
                    tail.addLine(to: CGPoint(x: hx, y: hy))
                    streak.stroke(tail,
                        with: .color(Color.white.opacity(Double(0.8 * (1 - prog)))),
                        lineWidth: 1.6)
                    // Head glow.
                    let hr: CGFloat = 2.2
                    streak.fill(
                        Path(ellipseIn: CGRect(x: hx - hr, y: hy - hr, width: hr * 2, height: hr * 2)),
                        with: .color(Color.white.opacity(Double(1 - prog))))
                }
            }
        }
    }

    /// Eclipse floor (Eclipse bundle) — a faint starfield with a large dark
    /// moon disc occluding a glowing golden corona ring, hung in the upper sky.
    /// The corona slowly pulses.  Full-screen overlay.
    private var eclipseFloorOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t  = tl.date.timeIntervalSinceReferenceDate
                let cx = size.width * 0.5
                let cy = size.height * 0.30
                let r  = min(size.width, size.height) * 0.16
                let pulse = 1.0 + 0.06 * sin(t * 1.4)

                // Faint static star specks.
                var rng = SeededRNG(seed: 0xEC11_9523)
                let stars = max(24, Int(size.width * size.height / 5200))
                for _ in 0..<stars {
                    let sx = CGFloat(rng.nextUnit()) * size.width
                    let sy = CGFloat(rng.nextUnit()) * size.height
                    let sr = 0.5 + CGFloat(rng.nextUnit()) * 1.1
                    ctx.fill(Path(ellipseIn: CGRect(x: sx - sr, y: sy - sr, width: sr * 2, height: sr * 2)),
                             with: .color(Color.white.opacity(0.10 + 0.18 * rng.nextUnit())))
                }

                // Broad soft corona glow.
                let glowR = r * 3.2 * CGFloat(pulse)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - glowR, y: cy - glowR, width: glowR * 2, height: glowR * 2)),
                    with: .radialGradient(Gradient(stops: [
                        .init(color: Color(red: 1.0, green: 0.80, blue: 0.36).opacity(0.0),  location: 0.40),
                        .init(color: Color(red: 1.0, green: 0.80, blue: 0.36).opacity(0.30), location: 0.52),
                        .init(color: Color(red: 1.0, green: 0.66, blue: 0.22).opacity(0.0),  location: 0.80),
                    ]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: glowR))

                // Bright corona ring + dark occluding moon.
                let ringR = r * 1.14
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2)),
                           with: .color(Color(red: 1.0, green: 0.86, blue: 0.42).opacity(0.85)),
                           lineWidth: max(2, r * 0.10))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                         with: .color(Color(red: 0.02, green: 0.02, blue: 0.05)))
            }
        }
    }

    /// Eclipse pit (Eclipse bundle) — a mini eclipse in the death zone: a dark
    /// core ringed by a pulsing golden corona over a near-black void.  A second
    /// effect system layers over the pulse: slow counter-rotating corona
    /// filaments licking outward from the ring, plus an occasional bright
    /// flare arc that erupts along the rim and dies away.  (This overlay is
    /// already suppressed entirely under Reduce Motion at the call site.)
    private var eclipsePitOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t  = tl.date.timeIntervalSinceReferenceDate
                let cx = size.width * 0.5, cy = size.height * 0.5
                let r  = min(size.width, size.height) * 0.32
                let pulse = 1.0 + 0.08 * sin(t * 1.6)

                ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                         with: .color(Color(red: 0.02, green: 0.02, blue: 0.05)))
                let glowR = r * 2.4 * CGFloat(pulse)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - glowR, y: cy - glowR, width: glowR * 2, height: glowR * 2)),
                    with: .radialGradient(Gradient(stops: [
                        .init(color: Color(red: 1.0, green: 0.82, blue: 0.38).opacity(0.0),  location: 0.45),
                        .init(color: Color(red: 1.0, green: 0.82, blue: 0.38).opacity(0.45), location: 0.60),
                        .init(color: Color(red: 1.0, green: 0.66, blue: 0.20).opacity(0.0),  location: 0.85),
                    ]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: glowR))
                let ringR = r * 1.1

                // ── Corona filaments — thin plasma tongues rooted on the ring,
                // slowly rotating as a body, each flexing on its own beat.
                var fil = ctx
                fil.blendMode = .plusLighter
                let filaments = 12
                for i in 0..<filaments {
                    let base: Double = Double(i) / Double(filaments) * 2 * .pi
                    let a: Double = base + t * 0.20
                    // Each filament breathes: length swells and shrinks.
                    let flex: Double = 0.55 + 0.45 * sin(t * 1.1 + Double(i) * 2.1)
                    let len: CGFloat = r * (0.28 + 0.42 * CGFloat(flex))
                    let x0: CGFloat = cx + CGFloat(cos(a)) * ringR
                    let y0: CGFloat = cy + CGFloat(sin(a)) * ringR
                    let x1: CGFloat = cx + CGFloat(cos(a)) * (ringR + len)
                    let y1: CGFloat = cy + CGFloat(sin(a)) * (ringR + len)
                    var p = Path()
                    p.move(to: CGPoint(x: x0, y: y0))
                    p.addLine(to: CGPoint(x: x1, y: y1))
                    fil.stroke(p, with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 1.0, green: 0.84, blue: 0.40).opacity(0.55 * flex),
                            Color(red: 1.0, green: 0.62, blue: 0.16).opacity(0.0),
                        ]),
                        startPoint: CGPoint(x: x0, y: y0),
                        endPoint:   CGPoint(x: x1, y: y1)),
                        style: StrokeStyle(lineWidth: max(1.0, r * 0.05), lineCap: .round))
                }

                // ── Occasional flare arc — every few seconds a bright arc
                // erupts along the rim, swells, and fades.  Eruption angle
                // hops per cycle so it never repeats in place.
                let flarePeriod: Double = 6.5
                let cycle: Double = (t / flarePeriod).rounded(.down)
                let prog: Double = (t - cycle * flarePeriod) / flarePeriod
                if prog < 0.22 {
                    let flare: Double = sin(prog / 0.22 * .pi)   // 0→1→0
                    let seed: Double = cycle * 2.399963           // golden-angle hop
                    let a0: Double = seed.truncatingRemainder(dividingBy: 2 * .pi)
                    let sweep: Double = 0.9 + 0.5 * flare
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: cx, y: cy),
                               radius: ringR + r * 0.10 * CGFloat(flare),
                               startAngle: .radians(a0), endAngle: .radians(a0 + sweep),
                               clockwise: false)
                    fil.stroke(arc,
                               with: .color(Color(red: 1.0, green: 0.92, blue: 0.60).opacity(0.85 * flare)),
                               style: StrokeStyle(lineWidth: max(1.5, r * 0.07), lineCap: .round))
                }

                ctx.stroke(Path(ellipseIn: CGRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2)),
                           with: .color(Color(red: 1.0, green: 0.86, blue: 0.42).opacity(0.9)),
                           lineWidth: max(1.5, r * 0.12))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                         with: .color(Color(red: 0.01, green: 0.01, blue: 0.03)))
            }
        }
    }

    /// Nightclub pit (Nightclub bundle) — a dark dancefloor void with drifting,
    /// twinkling coloured spotlights (additive) spilling across it.
    private var nightclubPitOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                         with: .color(Color(red: 0.05, green: 0.03, blue: 0.09)))

                var ctxL = ctx
                ctxL.blendMode = .plusLighter
                let cols = [Color(red: 1.0, green: 0.20, blue: 0.70),
                            Color(red: 0.30, green: 0.80, blue: 1.0),
                            Color(red: 1.0, green: 0.85, blue: 0.20),
                            Color(red: 0.60, green: 0.30, blue: 1.0)]
                var rng = SeededRNG(seed: 0x4B17_C0DE)
                let count = 7
                for i in 0..<count {
                    let bx0 = CGFloat(rng.nextUnit())
                    let by0 = CGFloat(rng.nextUnit())
                    let sp  = 0.5 + rng.nextUnit()
                    let px = (bx0 + CGFloat(0.18 * sin(t * sp + Double(i)))) * size.width
                    let py = (by0 + CGFloat(0.18 * cos(t * (sp * 0.8) + Double(i) * 1.3))) * size.height
                    let rr = min(size.width, size.height) * (0.18 + 0.10 * CGFloat(rng.nextUnit()))
                    let tw = 0.4 + 0.6 * (0.5 + 0.5 * sin(t * 3 + Double(i) * 2.0))
                    ctxL.fill(Path(ellipseIn: CGRect(x: px - rr, y: py - rr, width: rr * 2, height: rr * 2)),
                        with: .radialGradient(Gradient(colors: [cols[i % cols.count].opacity(0.45 * tw), .clear]),
                            center: CGPoint(x: px, y: py), startRadius: 0, endRadius: rr))
                }
            }
        }
    }

    /// Aurora-theme floor shimmer.  Renders a slow drift of soft green/blue/
    /// purple gradient blobs on top of the floor base color.  Drawn at 30Hz
    /// (minimumInterval) to keep CPU cost modest — physics still runs at 60Hz
    /// via the CADisplayLink.
    // Aurora floor — a living northern-lights sky: a broad colour wash of soft
    // hue-drifting glow blobs, four wavy vertical light CURTAINS that undulate
    // and slide (the signature aurora ribbons), and a twinkling starfield.  All
    // additive over the deep-night floor base so the colours luminesce.
    private var auroraShimmerOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height

                // ── 1. Soft aurora glow wash ───────────────────────────────
                ctx.blendMode = .plusLighter
                let blobs: [(Double, Double, Double, Double)] = [
                    (0.0, 0.0, 0.42, 0.07),   // teal-green
                    (1.7, 2.4, 0.52, 0.09),   // cyan
                    (3.5, 1.1, 0.74, 0.06),   // violet
                    (5.2, 4.0, 0.46, 0.08),   // aqua
                    (2.4, 5.1, 0.66, 0.07),   // indigo-violet
                ]
                let r = w * 0.9
                for (xSeed, ySeed, hueSeed, speed) in blobs {
                    let bxFrac: Double = 0.5 + 0.55 * sin(t * speed       + xSeed)
                    let byFrac: Double = 0.40 + 0.40 * sin(t * speed * 1.3 + ySeed)
                    let bx = w * CGFloat(bxFrac)
                    let by = h * CGFloat(byFrac)
                    let hue = (hueSeed + t * 0.010).truncatingRemainder(dividingBy: 1.0)
                    let color = Color(hue: hue, saturation: 0.60, brightness: 0.95)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(0.20), .clear]),
                            center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: r))
                }

                // ── 2. Aurora curtains — wavy vertical light ribbons ───────
                // x-fraction, base hue, phase, drift speed.
                let curtains: [(CGFloat, Double, Double, Double)] = [
                    (0.18, 0.40, 0.0, 0.45),
                    (0.42, 0.52, 1.9, 0.32),
                    (0.66, 0.74, 3.4, 0.38),
                    (0.85, 0.46, 5.0, 0.28),
                ]
                let steps = 16
                for (xf, hue0, ph, spd) in curtains {
                    let hue = (hue0 + t * 0.008).truncatingRemainder(dividingBy: 1.0)
                    let col = Color(hue: hue, saturation: 0.72, brightness: 1.0)
                    let baseSway: CGFloat = CGFloat(sin(t * spd + ph)) * w * 0.06
                    let baseX = w * xf + baseSway
                    let bandW = w * 0.14
                    var leftPts: [CGPoint] = [], rightPts: [CGPoint] = []
                    for s in 0...steps {
                        let yf = Double(s) / Double(steps)
                        let y  = h * CGFloat(yf)
                        let swayArg: Double = t * spd * 1.4 + ph + yf * 3.4
                        let sway:  CGFloat = CGFloat(sin(swayArg) * Double(w) * 0.05)
                        let halfFrac: Double = 0.35 + 0.65 * sin(yf * Double.pi)  // pinch top & bottom
                        let half:  CGFloat = bandW * CGFloat(halfFrac)
                        leftPts.append(CGPoint(x: baseX + sway - half, y: y))
                        rightPts.append(CGPoint(x: baseX + sway + half, y: y))
                    }
                    var path = Path()
                    path.move(to: leftPts[0])
                    for p in leftPts.dropFirst() { path.addLine(to: p) }
                    for p in rightPts.reversed() { path.addLine(to: p) }
                    path.closeSubpath()
                    ctx.fill(path, with: .linearGradient(
                        Gradient(stops: [
                            .init(color: col.opacity(0.0),  location: 0.0),
                            .init(color: col.opacity(0.30), location: 0.32),
                            .init(color: col.opacity(0.12), location: 0.68),
                            .init(color: .clear,            location: 1.0),
                        ]),
                        startPoint: CGPoint(x: baseX, y: 0), endPoint: CGPoint(x: baseX, y: h)))
                }
                ctx.blendMode = .normal

                // ── 3. Twinkling starfield ─────────────────────────────────
                for i in 0..<24 {
                    let fx = abs((sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1.0))
                    let fy = abs((sin(Double(i) * 78.2330) * 12543.1234).truncatingRemainder(dividingBy: 1.0))
                    let tw = 0.4 + 0.6 * sin(t * 1.8 + Double(i) * 1.3)
                    if tw < 0.2 { continue }
                    let px = w * CGFloat(fx), py = h * CGFloat(fy) * 0.72
                    let s  = CGFloat(0.7 + 1.1 * tw)
                    ctx.fill(Path(ellipseIn: CGRect(x: px - s, y: py - s, width: s * 2, height: s * 2)),
                             with: .color(.white.opacity(0.45 * tw)))
                }
            }
        }
    }

    /// Trail — drawn as a sequence of short line segments with increasing
    /// opacity from oldest (tail) to newest (head).  This gives a natural
    /// pencil-fade without needing a gradient-stroke API.
    ///
    /// Most trail colors are flat (.graphite, .fire, .ice, .ink, .gold)
    /// so each segment uses the trail's single color.  The .rainbow
    /// trail uses a stable per-segment hue baked in at creation —
    /// `trailHueOffset + i × trailHueStep`.  As segments fall off the
    /// tail the offset advances by exactly the number dropped, so the
    /// surviving positions keep their original colours and the
    /// spectrum follows the ball.
    private func trailOverlay(geo: GeometryProxy) -> some View {
        Canvas { ctx, size in
            // Zen Garden — the raked-sand groove is a PERSISTENT furrow baked
            // into an image (see addSandPoint), so a running auto-pattern fills
            // the whole garden and hand-raked lines stay until "smooth sand".
            if usesSandTrail {
                if let img = sandAccumImage {
                    ctx.draw(Image(uiImage: img), in: CGRect(origin: .zero, size: size))
                }
                return
            }
            // Bespoke, animated per-trail rendering (scales, fire→smoke, snow
            // trench, jet-stream, …) — the same renderer the home trail uses,
            // so a trail looks identical everywhere.
            let n = trailPoints.count
            guard n >= 2 else { return }
            drawRichTrail(ctx, points: trailPoints,
                          trail: gameState.equippedTrail,
                          t: Date().timeIntervalSinceReferenceDate,
                          times: trailTimes)
        }
    }

    /// A permanent raked border framing the Zen sand — fills the outer margin
    /// the rake pattern leaves.  Same carved look as the trail (soft depression
    /// + pale carved centre); unaffected by "smooth sand".
    private func zenBorderOverlay(size: CGSize) -> some View {
        Canvas { ctx, _ in
            let inset: CGFloat = 15
            let rect = CGRect(x: inset, y: inset,
                              width: size.width - 2 * inset, height: size.height - 2 * inset)
            let frame = Path(roundedRect: rect, cornerRadius: 30)
            ctx.stroke(frame, with: .color(Color(red: 0.69, green: 0.55, blue: 0.29)), lineWidth: 26)
            ctx.stroke(frame, with: .color(Color(red: 0.98, green: 0.93, blue: 0.79)), lineWidth: 6)
        }
    }

    /// Sub-theme floor overlays for the Paper world (L51-100).
    /// Returns an empty view for non-paper themes so the call site can
    /// stay simple.
    @ViewBuilder
    private func paperFloorOverlay(geo: GeometryProxy) -> some View {
        switch floor {
        case .notebook:  notebookRules(geo: geo)
        case .graph:     graphGrid(geo: geo)
        case .parchment: parchmentTexture(geo: geo)
        case .sketch:    sketchGrain(geo: geo)
        case .origami:   origamiFolds(geo: geo)
        default:         EmptyView()
        }
    }

    // ── Notebook: horizontal pale-blue ruled lines + red margin ─────────
    private func notebookRules(geo: GeometryProxy) -> some View {
        Canvas { ctx, size in
            let lineColor = Color(red: 0.66, green: 0.78, blue: 0.92).opacity(0.70)
            let marginColor = Color(red: 0.90, green: 0.42, blue: 0.42).opacity(0.55)
            let spacing: CGFloat = 26
            var y: CGFloat = spacing
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(lineColor), lineWidth: 0.8)
                y += spacing
            }
            // Red left margin
            var margin = Path()
            margin.move(to: CGPoint(x: size.width * 0.15, y: 0))
            margin.addLine(to: CGPoint(x: size.width * 0.15, y: size.height))
            ctx.stroke(margin, with: .color(marginColor), lineWidth: 1.2)
        }
    }

    // ── Graph: pale green grid ───────────────────────────────────────────
    private func graphGrid(geo: GeometryProxy) -> some View {
        Canvas { ctx, size in
            let color = Color(red: 0.55, green: 0.78, blue: 0.65).opacity(0.55)
            let step: CGFloat = 18
            var x: CGFloat = 0
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(color), lineWidth: 0.5)
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(color), lineWidth: 0.5)
                y += step
            }
        }
    }

    // ── Parchment: warm vignette + scattered subtle specks ──────────────
    private func parchmentTexture(geo: GeometryProxy) -> some View {
        Canvas { ctx, size in
            // Warm vignette toward edges
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0.40),
                        .init(color: Color(red: 0.55, green: 0.40, blue: 0.20).opacity(0.20), location: 1.00),
                    ]),
                    center: CGPoint(x: size.width / 2, y: size.height / 2),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.65
                )
            )
            // Specks of aged ink
            var rng = SeededRNG(seed: 4242)
            let speckColor = Color(red: 0.42, green: 0.30, blue: 0.18).opacity(0.18)
            for _ in 0..<60 {
                let x = CGFloat(rng.nextUnit()) * size.width
                let y = CGFloat(rng.nextUnit()) * size.height
                let r = 0.5 + CGFloat(rng.nextUnit()) * 1.2
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .color(speckColor)
                )
            }
        }
    }

    // ── Sketch: light cross-hatch grain ─────────────────────────────────
    private func sketchGrain(geo: GeometryProxy) -> some View {
        Canvas { ctx, size in
            let color = Color(red: 0.20, green: 0.20, blue: 0.22).opacity(0.08)
            var rng = SeededRNG(seed: 1337)
            // Short pencil strokes at random positions
            for _ in 0..<140 {
                let x = CGFloat(rng.nextUnit()) * size.width
                let y = CGFloat(rng.nextUnit()) * size.height
                let len = CGFloat(rng.nextUnit()) * 6 + 4
                let angleSel = rng.nextUnit()
                // Pick from a small set of pencil angles
                let angle: Double = angleSel < 0.33 ? .pi / 4
                                  : angleSel < 0.66 ? -.pi / 4
                                  : .pi / 6
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + cos(angle) * Double(len),
                                          y: y + sin(angle) * Double(len)))
                ctx.stroke(path, with: .color(color), lineWidth: 0.6)
            }
        }
    }

    // ── Origami: diagonal fold shadows ──────────────────────────────────
    private func origamiFolds(geo: GeometryProxy) -> some View {
        Canvas { ctx, size in
            let shadow = Color(red: 0.25, green: 0.20, blue: 0.15).opacity(0.10)
            // Two soft diagonal "fold" gradient stripes
            for i in 0...3 {
                let frac = CGFloat(i) * 0.27 - 0.15
                let cx = size.width * frac
                ctx.fill(
                    Path(CGRect(x: cx, y: 0, width: 8, height: size.height * 2)
                            .applying(.init(rotationAngle: .pi / 5))),
                    with: .linearGradient(
                        Gradient(colors: [.clear, shadow, .clear]),
                        startPoint: CGPoint(x: cx, y: 0),
                        endPoint:   CGPoint(x: cx + 8, y: 0)
                    )
                )
            }
            // Subtle simple straight fold lines for clarity
            let fold = Color(red: 0.20, green: 0.16, blue: 0.10).opacity(0.18)
            for i in 1...3 {
                let y = size.height * CGFloat(i) / 4
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y - 6))
                ctx.stroke(path, with: .color(fold), lineWidth: 0.6)
            }
        }
    }

    /// Default goal renderer — a classic archery target.  Five concentric
    /// bands (white → black → blue → red → yellow bullseye) using
    /// approximately FITA-standard colours, with a faint top-left
    /// highlight for depth and a slow breath-scale so the target feels
    /// alive without being noisy.  Static, no particles — distinct from
    /// the other goal skins which all share the `rainbowHole` Canvas.
    /// Default goal renderer — a clean 3-ring bullseye (red / white /
    /// red) with the same gentle breath scale as the FITA archery
    /// target.  Reads instantly even at small sizes — the simplest
    /// possible "shoot for this" cue for new players.
    private var simpleBullseyeTarget: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t       = timeline.date.timeIntervalSinceReferenceDate
                let breathe = 1.0 + sin(t * 1.3) * 0.025
                let cx      = size.width  / 2
                let cy      = size.height / 2
                let maxR    = min(size.width, size.height) / 2 * 0.95 * breathe

                // Three bands, outer to inner.  Red border / white mid /
                // red bullseye — same red on both ends so the whole
                // shape reads as a single recognisable target.
                let bands: [(fraction: Double, color: Color)] = [
                    (1.00, Color(red: 0.85, green: 0.12, blue: 0.18)),   // outer red
                    (0.70, Color.white),                                  // middle white
                    (0.35, Color(red: 0.85, green: 0.12, blue: 0.18)),   // inner red bullseye
                ]
                for band in bands {
                    let r = maxR * band.fraction
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                               width: r * 2, height: r * 2)),
                        with: .color(band.color)
                    )
                }

                // Outer dark rim — defines the shape against any background.
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: cx - maxR, y: cy - maxR,
                                           width: maxR * 2, height: maxR * 2)),
                    with: .color(Color.black.opacity(0.55)),
                    lineWidth: 1.4
                )
                // Band dividers — keep the rings legible at every size.
                for band in bands.dropFirst() {
                    let r = maxR * band.fraction
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                               width: r * 2, height: r * 2)),
                        with: .color(Color.black.opacity(0.30)),
                        lineWidth: 0.7
                    )
                }

                // Soft top-left highlight — subtle depth.
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - maxR, y: cy - maxR,
                                           width: maxR * 2, height: maxR * 2)),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.18), .clear]),
                        center: CGPoint(x: cx - maxR * 0.30, y: cy - maxR * 0.30),
                        startRadius: 0,
                        endRadius: maxR * 0.95
                    )
                )
            }
        }
    }

    /// Reusable static banded-target renderer for the Standard goals — the same
    /// recipe as `simpleBullseyeTarget`, driven by a caller-supplied colour ramp
    /// (OUTER → INNER, from the goal's `targetBands`).  No particles; a faint
    /// breathe keeps it alive.
    private func bandedTargetGoal(_ colors: [Color]) -> some View {
        let ramp = colors.isEmpty ? [Color.gray] : colors
        return TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t       = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breathe = 1.0 + sin(t * 1.3) * 0.025
                let cx = size.width / 2, cy = size.height / 2
                let maxR = min(size.width, size.height) / 2 * 0.95 * breathe
                let n = ramp.count
                let step = n > 1 ? 0.70 / Double(n - 1) : 0    // 1.0 … 0.30 spread

                for (i, color) in ramp.enumerated() {
                    let r = maxR * CGFloat(1.0 - Double(i) * step)
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                             with: .color(color))
                }
                // Outer dark rim — defines the shape against any background.
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - maxR, y: cy - maxR, width: maxR * 2, height: maxR * 2)),
                           with: .color(Color.black.opacity(0.55)), lineWidth: 1.4)
                // Band dividers.
                for i in 1..<max(1, n) {
                    let r = maxR * CGFloat(1.0 - Double(i) * step)
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                               with: .color(Color.black.opacity(0.30)), lineWidth: 0.7)
                }
                // Soft top-left highlight — subtle depth.
                ctx.fill(Path(ellipseIn: CGRect(x: cx - maxR, y: cy - maxR, width: maxR * 2, height: maxR * 2)),
                         with: .radialGradient(Gradient(colors: [Color.white.opacity(0.18), .clear]),
                                               center: CGPoint(x: cx - maxR * 0.30, y: cy - maxR * 0.30),
                                               startRadius: 0, endRadius: maxR * 0.95))
            }
        }
    }

    /// Aurora goal — a glowing northern-lights PORTAL: a deep-night disc with
    /// soft aurora light-clouds drifting and hue-shifting inside it, a breathing
    /// outer halo, a luminous teal-cyan rim with a bright glint that orbits it,
    /// and a bright inner core.  The signature animated centerpiece of the
    /// Aurora bundle.  Freezes gracefully under Reduce Motion.
    private var auroraGoal: some View {
        TimelineView(.animation) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2
                let R  = min(w, h) / 2
                let center = CGPoint(x: cx, y: cy)
                let teal   = Color(red: 0.32, green: 0.96, blue: 0.80)

                // ── 1. Breathing outer halo ────────────────────────────────
                let pulse = 0.5 + 0.5 * sin(t * 1.6)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - R, y: cy - R, width: R * 2, height: R * 2)),
                    with: .radialGradient(Gradient(stops: [
                        .init(color: teal.opacity(0.0),                 location: 0.46),
                        .init(color: teal.opacity(0.16 + 0.14 * pulse), location: 0.78),
                        .init(color: .clear,                            location: 1.0),
                    ]), center: center, startRadius: 0, endRadius: R))

                // ── 2. Portal disc (deep night) ────────────────────────────
                let pr = R * 0.74
                let disc = Path(ellipseIn: CGRect(x: cx - pr, y: cy - pr, width: pr * 2, height: pr * 2))
                ctx.fill(disc, with: .radialGradient(Gradient(stops: [
                    .init(color: Color(red: 0.06, green: 0.11, blue: 0.20), location: 0.0),
                    .init(color: Color(red: 0.03, green: 0.06, blue: 0.13), location: 0.7),
                    .init(color: Color(red: 0.01, green: 0.02, blue: 0.06), location: 1.0),
                ]), center: center, startRadius: 0, endRadius: pr))

                // ── 3. Aurora light-clouds drifting inside the portal ──────
                ctx.drawLayer { lc in
                    lc.clip(to: disc)
                    lc.blendMode = .plusLighter
                    let clouds: [(Double, Double, Double)] = [   // baseHue, phase, speed
                        (0.42, 0.0, 0.55), (0.54, 2.1, 0.40),
                        (0.74, 4.0, 0.46), (0.48, 5.4, 0.33),
                    ]
                    for (hue0, ph, spd) in clouds {
                        let hue = (hue0 + t * 0.04).truncatingRemainder(dividingBy: 1.0)
                        let col = Color(hue: hue, saturation: 0.74, brightness: 1.0)
                        let bx  = cx + CGFloat(cos(t * spd + ph)) * pr * 0.42
                        let by  = cy + CGFloat(sin(t * spd * 1.3 + ph)) * pr * 0.42
                        let br  = pr * 0.85
                        lc.fill(Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                                with: .radialGradient(Gradient(colors: [col.opacity(0.42), .clear]),
                                    center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: br))
                    }
                }

                // ── 4. Bright inner core ───────────────────────────────────
                let cr = pr * 0.42
                ctx.fill(Path(ellipseIn: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2)),
                    with: .radialGradient(Gradient(colors: [
                        Color.white.opacity(0.85), teal.opacity(0.5), .clear]),
                        center: center, startRadius: 0, endRadius: cr))

                // ── 5. Luminous rim + an orbiting glint ────────────────────
                ctx.stroke(disc, with: .color(teal.opacity(0.9)), lineWidth: max(1.4, R * 0.045))
                let ga = t * 0.9
                let gx = cx + CGFloat(cos(ga)) * pr
                let gy = cy + CGFloat(sin(ga)) * pr
                let gs = R * 0.18
                ctx.fill(Path(ellipseIn: CGRect(x: gx - gs, y: gy - gs, width: gs * 2, height: gs * 2)),
                    with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), teal.opacity(0.4), .clear]),
                        center: CGPoint(x: gx, y: gy), startRadius: 0, endRadius: gs))
            }
        }
    }

    /// Reusable static ring-portal renderer for the portal-style Standard goals
    /// — concentric glowing rings (OUTER dark → INNER bright, from the goal's
    /// `portalStops`) reading as a tunnel.  Static: no particles, just a faint
    /// breathe + a soft core glow.
    private func ringPortalGoal(_ colors: [Color]) -> some View {
        let ramp  = colors.isEmpty ? [Color.black, Color.white] : colors
        let inner = Array(ramp.reversed())             // bright centre first
        return TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t       = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breathe = 1.0 + sin(t * 1.3) * 0.03
                let cx = size.width / 2, cy = size.height / 2
                let maxR = min(size.width, size.height) / 2 * 0.95 * breathe

                // Base radial fill: bright centre → dark edge.
                ctx.fill(Path(ellipseIn: CGRect(x: cx - maxR, y: cy - maxR, width: maxR * 2, height: maxR * 2)),
                         with: .radialGradient(Gradient(colors: inner),
                                               center: CGPoint(x: cx, y: cy),
                                               startRadius: 0, endRadius: maxR))
                // Concentric ring strokes for tunnel depth (additive glow).
                var g = ctx; g.blendMode = .plusLighter
                let rings = max(3, inner.count + 1)
                for i in 0..<rings {
                    let r = maxR * CGFloat(0.92 - Double(i) * (0.74 / Double(rings)))
                    let c = inner[min(inner.count - 1, i)]
                    g.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                             with: .color(c.opacity(0.5)), lineWidth: max(1.0, maxR * 0.05))
                }
                // Bright core glow.
                let cr = maxR * 0.26
                g.fill(Path(ellipseIn: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2)),
                       with: .radialGradient(Gradient(colors: [Color.white.opacity(0.95), .clear]),
                                             center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: cr))
                // Outer dark rim.
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - maxR, y: cy - maxR, width: maxR * 2, height: maxR * 2)),
                           with: .color(Color.black.opacity(0.55)), lineWidth: 1.4)
            }
        }
        .clipShape(Circle())
    }

    /// Hole-in-One goal (Golf bundle) — a golf-green disc with a
    /// dark hole in the middle and a red flag on a white pole rising
    /// out of it.  Static (no animation) so it reads at a glance.
    private var holeInOneGoal: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2 * 0.95

            // Green disc — golf-course turf colour with a subtle
            // radial gradient so it doesn't look flat.
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                       width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 0.55, green: 0.78, blue: 0.30),
                        Color(red: 0.35, green: 0.60, blue: 0.22),
                    ]),
                    center: CGPoint(x: cx - r * 0.3, y: cy - r * 0.3),
                    startRadius: 0,
                    endRadius:   r
                )
            )
            // Dark green rim stroke.
            ctx.stroke(
                Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                       width: r * 2, height: r * 2)),
                with: .color(Color(red: 0.15, green: 0.30, blue: 0.08).opacity(0.85)),
                lineWidth: 1.5
            )

            // The hole — black circle, ~30% of the green's radius.
            let holeR = r * 0.30
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - holeR, y: cy - holeR,
                                       width: holeR * 2, height: holeR * 2)),
                with: .color(Color(red: 0.05, green: 0.05, blue: 0.04))
            )

            // Flagstick — thin white pole rising up from the hole's
            // centre, offset slightly so the flag overhangs the green.
            let poleTop = cy - r * 1.05
            let poleX   = cx + r * 0.05
            var pole = Path()
            pole.move(to: CGPoint(x: poleX, y: cy))
            pole.addLine(to: CGPoint(x: poleX, y: poleTop))
            ctx.stroke(pole,
                       with: .color(Color(white: 0.95)),
                       lineWidth: max(1.5, r * 0.05))

            // Red triangular flag at the top of the pole.
            var flag = Path()
            flag.move(to: CGPoint(x: poleX, y: poleTop))
            flag.addLine(to: CGPoint(x: poleX + r * 0.55, y: poleTop + r * 0.14))
            flag.addLine(to: CGPoint(x: poleX, y: poleTop + r * 0.30))
            flag.closeSubpath()
            ctx.fill(flag, with: .color(Color(red: 0.90, green: 0.18, blue: 0.18)))
            ctx.stroke(flag,
                       with: .color(Color(red: 0.55, green: 0.08, blue: 0.05)),
                       lineWidth: 0.8)
        }
    }

    /// Tractor Beam goal (Space Travel bundle) — a small saucer at the
    /// top emitting a widening green light cone, with pulses of light
    /// descending the beam toward a glowing landing pad at the centre
    /// (the actual win zone).  Animated via TimelineView; Reduce Motion
    /// freezes the descending pulses but keeps the beam + pad.
    private var tractorBeamGoal: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let w  = size.width
                let h  = size.height
                let cx = w / 2

                // Landing pad — bright green disc at the centre (the
                // win zone the ball rolls into).
                let padCy = h * 0.58
                let padR  = min(w, h) * 0.26
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - padR, y: padCy - padR * 0.55,
                                           width: padR * 2, height: padR * 1.1)),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 0.65, green: 1.00, blue: 0.78).opacity(0.95),
                            Color(red: 0.15, green: 0.85, blue: 0.50).opacity(0.55),
                            .clear,
                        ]),
                        center: CGPoint(x: cx, y: padCy),
                        startRadius: 0, endRadius: padR
                    )
                )

                // Beam cone — narrow at the saucer (top), wide at the
                // pad.  Soft green, semi-transparent.
                let saucerCy = h * 0.14
                let topHalf  = w * 0.10
                let botHalf  = padR * 0.95
                var beam = Path()
                beam.move(to: CGPoint(x: cx - topHalf, y: saucerCy))
                beam.addLine(to: CGPoint(x: cx + topHalf, y: saucerCy))
                beam.addLine(to: CGPoint(x: cx + botHalf, y: padCy))
                beam.addLine(to: CGPoint(x: cx - botHalf, y: padCy))
                beam.closeSubpath()
                ctx.fill(
                    beam,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.40, green: 1.00, blue: 0.65).opacity(0.55),
                            Color(red: 0.20, green: 0.90, blue: 0.55).opacity(0.18),
                        ]),
                        startPoint: CGPoint(x: cx, y: saucerCy),
                        endPoint:   CGPoint(x: cx, y: padCy)
                    )
                )

                // Descending pulse bands — thin bright ellipses sliding
                // down the cone, looping.  Width interpolates with the
                // cone so they hug its edges.
                let pulseCount = 3
                for i in 0..<pulseCount {
                    let phase = (t * 0.7 + Double(i) / Double(pulseCount))
                        .truncatingRemainder(dividingBy: 1.0)
                    let py = saucerCy + (padCy - saucerCy) * CGFloat(phase)
                    let halfW = topHalf + (botHalf - topHalf) * CGFloat(phase)
                    let alpha = 0.55 * (1.0 - phase)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: cx - halfW, y: py - 2,
                                               width: halfW * 2, height: 4)),
                        with: .color(Color(red: 0.75, green: 1.00, blue: 0.80).opacity(alpha))
                    )
                }

                // Saucer at the top of the beam — small metallic disc
                // with a green dome.
                let saucerW = w * 0.42
                let saucerH = h * 0.16
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - saucerW / 2, y: saucerCy - saucerH * 0.35,
                                           width: saucerW, height: saucerH)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.82, green: 0.88, blue: 0.94),
                            Color(red: 0.30, green: 0.36, blue: 0.44),
                        ]),
                        startPoint: CGPoint(x: cx, y: saucerCy - saucerH * 0.35),
                        endPoint:   CGPoint(x: cx, y: saucerCy + saucerH * 0.65)
                    )
                )
                let domeW = saucerW * 0.42
                let domeH = saucerH * 0.95
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - domeW / 2, y: saucerCy - saucerH * 0.35 - domeH * 0.6,
                                           width: domeW, height: domeH)),
                    with: .color(Color(red: 0.30, green: 0.92, blue: 0.55).opacity(0.95))
                )
            }
        }
    }

    /// Inferno goal (Hellfire bundle) — a molten lava ring around a dark core
    /// with flame tongues licking outward.  Animated flicker; Reduce Motion
    /// freezes the flames.
    private var infernoGoal: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let w  = size.width, h = size.height
                let cx = w / 2, cy = h / 2
                let r  = min(w, h) / 2 * 0.95

                // Molten ring — dark centre bleeding out to a bright rim.
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(Gradient(stops: [
                        .init(color: Color(red: 0.03, green: 0.00, blue: 0.00), location: 0.00),
                        .init(color: Color(red: 0.08, green: 0.01, blue: 0.00), location: 0.42),
                        .init(color: Color(red: 0.95, green: 0.28, blue: 0.04), location: 0.74),
                        .init(color: Color(red: 1.00, green: 0.74, blue: 0.20), location: 0.93),
                        .init(color: Color(red: 1.00, green: 0.45, blue: 0.08).opacity(0.0), location: 1.00),
                    ]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))

                // Flame tongues around the rim — additive so they glow.
                var fctx = ctx
                fctx.blendMode = .plusLighter
                let flames = 12
                for i in 0..<flames {
                    let a     = Double(i) / Double(flames) * 2 * .pi
                    let flick = 0.6 + 0.4 * sin(t * 6 + Double(i) * 1.7)
                    let baseR = r * 0.78
                    let tipR  = r * (0.92 + 0.26 * flick)
                    let perp  = a + .pi / 2
                    let wdt   = r * 0.10
                    let bx = cx + CGFloat(cos(a)) * baseR
                    let by = cy + CGFloat(sin(a)) * baseR
                    let tx = cx + CGFloat(cos(a)) * tipR
                    let ty = cy + CGFloat(sin(a)) * tipR
                    var fl = Path()
                    fl.move(to: CGPoint(x: bx + CGFloat(cos(perp)) * wdt, y: by + CGFloat(sin(perp)) * wdt))
                    fl.addQuadCurve(to: CGPoint(x: tx, y: ty),
                                    control: CGPoint(x: bx + CGFloat(cos(perp)) * wdt * 0.5, y: by + CGFloat(sin(perp)) * wdt * 0.5))
                    fl.addQuadCurve(to: CGPoint(x: bx - CGFloat(cos(perp)) * wdt, y: by - CGFloat(sin(perp)) * wdt),
                                    control: CGPoint(x: bx - CGFloat(cos(perp)) * wdt * 0.5, y: by - CGFloat(sin(perp)) * wdt * 0.5))
                    fl.closeSubpath()
                    fctx.fill(fl, with: .color(Color(red: 1.0, green: 0.5, blue: 0.12).opacity(0.5 * flick)))
                }
            }
        }
    }

    /// Halo goal (Heavens bundle) — a radiant golden halo with slowly rotating
    /// light rays over a soft heavenly glow.  Reduce Motion freezes the rays.
    private var heavensHaloGoal: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let w  = size.width, h = size.height
                let cx = w / 2, cy = h / 2
                let r  = min(w, h) / 2 * 0.95

                // Heavenly background glow.
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(Gradient(colors: [
                        Color(red: 1.00, green: 0.99, blue: 0.92).opacity(0.95),
                        Color(red: 0.80, green: 0.90, blue: 1.00).opacity(0.55),
                        Color(red: 0.65, green: 0.80, blue: 1.00).opacity(0.0),
                    ]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))

                // Rotating sunburst rays.
                var rctx = ctx
                rctx.blendMode = .plusLighter
                let rays  = 12
                let pulse = 1.0 + 0.05 * sin(t * 2)
                for i in 0..<rays {
                    let a      = Double(i) / Double(rays) * 2 * .pi + t * 0.25
                    let innerR = r * 0.30
                    let outerR = r * pulse
                    let perp   = a + .pi / 2
                    let half   = r * 0.05
                    let ix = cx + CGFloat(cos(a)) * innerR, iy = cy + CGFloat(sin(a)) * innerR
                    let ox = cx + CGFloat(cos(a)) * outerR, oy = cy + CGFloat(sin(a)) * outerR
                    var ray = Path()
                    ray.move(to: CGPoint(x: ix + CGFloat(cos(perp)) * half, y: iy + CGFloat(sin(perp)) * half))
                    ray.addLine(to: CGPoint(x: ox, y: oy))
                    ray.addLine(to: CGPoint(x: ix - CGFloat(cos(perp)) * half, y: iy - CGFloat(sin(perp)) * half))
                    ray.closeSubpath()
                    rctx.fill(ray, with: .color(Color(red: 1.0, green: 0.95, blue: 0.70).opacity(0.18)))
                }

                // Golden halo ring with a bright inner highlight.
                let haloR = r * 0.55
                let haloRect = CGRect(x: cx - haloR, y: cy - haloR, width: haloR * 2, height: haloR * 2)
                ctx.stroke(Path(ellipseIn: haloRect),
                           with: .color(Color(red: 1.0, green: 0.84, blue: 0.35)),
                           lineWidth: max(2, r * 0.10))
                ctx.stroke(Path(ellipseIn: haloRect),
                           with: .color(Color(red: 1.0, green: 0.97, blue: 0.80).opacity(0.9)),
                           lineWidth: max(1, r * 0.04))
            }
        }
    }

    /// Doodle goal (Paper World bundle) — a hand-drawn pencil bullseye on cream
    /// paper.  The rings wobble (seeded, stable) so they read as sketched, not
    /// printed.  Static — no animation.
    private var doodleGoal: some View {
        Canvas { ctx, size in
            let w  = size.width, h = size.height
            let cx = w / 2, cy = h / 2
            let r  = min(w, h) / 2 * 0.95
            let lead = Color(red: 0.22, green: 0.22, blue: 0.26)

            // Cream paper disc.
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                     with: .color(Color(red: 0.97, green: 0.96, blue: 0.90)))

            // Concentric wobbly pencil rings.
            let fracs: [CGFloat] = [0.92, 0.66, 0.40]
            for (ri, frac) in fracs.enumerated() {
                let rr  = r * frac
                let seg = 60
                var ring = Path()
                for s in 0...seg {
                    let a   = Double(s) / Double(seg) * 2 * .pi
                    let wob = sin(a * 5 + Double(ri) * 2.1) * 0.5 + sin(a * 9 + Double(ri)) * 0.5
                    let rad = rr + CGFloat(wob) * r * 0.02
                    let p   = CGPoint(x: cx + CGFloat(cos(a)) * rad, y: cy + CGFloat(sin(a)) * rad)
                    if s == 0 { ring.move(to: p) } else { ring.addLine(to: p) }
                }
                ctx.stroke(ring, with: .color(lead.opacity(0.85)),
                           style: StrokeStyle(lineWidth: max(1.2, r * 0.045), lineCap: .round, lineJoin: .round))
            }

            // Filled centre dot.
            let dotR = r * 0.16
            ctx.fill(Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)),
                     with: .color(lead.opacity(0.9)))
        }
    }

    /// Soccer Net goal (Soccer bundle) — a goal mouth: a square white net over a
    /// dark interior with a green grass strip, framed by two posts + crossbar.
    /// Static — no animation.
    private var soccerNetGoal: some View {
        Canvas { ctx, size in
            var ctx = ctx
            let w  = size.width, h = size.height
            let cx = w / 2, cy = h / 2
            let r  = min(w, h) / 2 * 0.95
            let circle = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.clip(to: circle)

            // Dark goal-mouth interior + grass strip across the bottom.
            ctx.fill(circle, with: .color(Color(red: 0.12, green: 0.14, blue: 0.18)))
            ctx.fill(Path(CGRect(x: cx - r, y: cy + r * 0.52, width: r * 2, height: r * 0.9)),
                     with: .color(Color(red: 0.30, green: 0.60, blue: 0.26)))

            // Square net mesh — thin white lines.
            let net   = Color.white.opacity(0.62)
            let cells = 7
            let step  = (r * 2) / CGFloat(cells)
            for k in 0...cells {
                let x = cx - r + CGFloat(k) * step
                var v = Path(); v.move(to: CGPoint(x: x, y: cy - r)); v.addLine(to: CGPoint(x: x, y: cy + r))
                ctx.stroke(v, with: .color(net), lineWidth: 1)
                let y = cy - r + CGFloat(k) * step
                var hz = Path(); hz.move(to: CGPoint(x: cx - r, y: y)); hz.addLine(to: CGPoint(x: cx + r, y: y))
                ctx.stroke(hz, with: .color(net), lineWidth: 1)
            }

            // White goal frame — two posts + crossbar.
            let postW  = max(2.5, r * 0.13)
            let frame  = Color.white
            let topY   = cy - r * 0.72
            let botY   = cy + r * 0.72
            let leftX  = cx - r * 0.80
            let rightX = cx + r * 0.80
            ctx.fill(Path(CGRect(x: leftX, y: topY, width: postW, height: botY - topY)), with: .color(frame))
            ctx.fill(Path(CGRect(x: rightX - postW, y: topY, width: postW, height: botY - topY)), with: .color(frame))
            ctx.fill(Path(CGRect(x: leftX, y: topY, width: rightX - leftX, height: postW)), with: .color(frame))
        }
    }

    private var archeryTargetGoal: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t      = timeline.date.timeIntervalSinceReferenceDate
                let breathe = 1.0 + sin(t * 1.3) * 0.025   // gentle ±2.5%
                let cx      = size.width  / 2
                let cy      = size.height / 2
                let maxR    = min(size.width, size.height) / 2 * 0.95 * breathe

                // Bands from outermost to innermost — radius is a
                // fraction of maxR.  Standard archery target order.
                let bands: [(fraction: Double, color: Color)] = [
                    (1.00, Color.white),
                    (0.80, Color.black),
                    (0.60, Color(red: 0.30, green: 0.55, blue: 0.95)), // blue
                    (0.40, Color(red: 0.92, green: 0.20, blue: 0.20)), // red
                    (0.22, Color(red: 1.00, green: 0.86, blue: 0.20)), // yellow bullseye
                ]

                // Filled concentric circles (largest first so smaller
                // bands paint on top).
                for band in bands {
                    let r = maxR * band.fraction
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                               width: r * 2, height: r * 2)),
                        with: .color(band.color)
                    )
                }

                // Outer rim — darker stroke around the whole target.
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: cx - maxR, y: cy - maxR,
                                           width: maxR * 2, height: maxR * 2)),
                    with: .color(Color.black.opacity(0.55)),
                    lineWidth: 1.4
                )

                // Thin dark dividers between each band — separates the
                // colours cleanly even at small sizes.
                for band in bands.dropFirst() {
                    let r = maxR * band.fraction
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                               width: r * 2, height: r * 2)),
                        with: .color(Color.black.opacity(0.35)),
                        lineWidth: 0.7
                    )
                }

                // Central pinpoint — "aim here" cue inside the bullseye.
                let dotR = maxR * 0.05
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - dotR, y: cy - dotR,
                                           width: dotR * 2, height: dotR * 2)),
                    with: .color(Color.black.opacity(0.7))
                )

                // Soft top-left highlight gives the target subtle depth
                // (reads as light catching a slightly-domed disc).
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - maxR, y: cy - maxR,
                                           width: maxR * 2, height: maxR * 2)),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.18), .clear]),
                        center: CGPoint(x: cx - maxR * 0.30, y: cy - maxR * 0.30),
                        startRadius: 0,
                        endRadius: maxR * 0.95
                    )
                )
            }
        }
    }

    // ── Distinct bespoke portals for the former "particle" goals ─────────
    // Each goal now has its own unique art instead of sharing rainbowHole.

    /// Galaxy — two spiral arms of stars winding around a bright core.
    private var galaxyGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                    with: .radialGradient(Gradient(colors: [Color(red:0.10,green:0.06,blue:0.22), Color(red:0.02,green:0.01,blue:0.06)]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
                var g = ctx; g.blendMode = .plusLighter
                for arm in 0..<2 {
                    let base = Double(arm) * .pi + t * 0.3
                    for i in 0..<40 {
                        let f = Double(i) / 40.0
                        let ang = base + f * 3.2
                        let rad = r * CGFloat(f)
                        let px = cx + CGFloat(cos(ang)) * rad
                        let py = cy + CGFloat(sin(ang)) * rad
                        let sz = CGFloat(1.2 + 2.0 * (1 - f))
                        let hue: Double = 0.60 + 0.15 * sin(f * 6 + t)
                        g.fill(Path(ellipseIn: CGRect(x: px-sz, y: py-sz, width: sz*2, height: sz*2)),
                            with: .color(Color(hue: hue, saturation: 0.6, brightness: 1).opacity(0.8 * (1 - f) + 0.2)))
                    }
                }
                let cr = r * 0.28
                g.fill(Path(ellipseIn: CGRect(x: cx-cr, y: cy-cr, width: cr*2, height: cr*2)),
                    with: .radialGradient(Gradient(colors: [Color.white.opacity(0.95), Color(red:0.8,green:0.7,blue:1).opacity(0.4), .clear]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: cr))
            }
        }
        .clipShape(Circle())
    }

    /// Crystal — radiating angular facets that shimmer in icy blue.
    private var crystalGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                    with: .color(Color(red:0.03,green:0.08,blue:0.12)))
                var g = ctx; g.blendMode = .plusLighter
                let facets = 8
                for i in 0..<facets {
                    let a0 = Double(i) / Double(facets) * 2 * .pi
                    let a1 = Double(i+1) / Double(facets) * 2 * .pi
                    var p = Path()
                    p.move(to: CGPoint(x: cx, y: cy))
                    p.addLine(to: CGPoint(x: cx + CGFloat(cos(a0)) * r, y: cy + CGFloat(sin(a0)) * r))
                    p.addLine(to: CGPoint(x: cx + CGFloat(cos(a1)) * r, y: cy + CGFloat(sin(a1)) * r))
                    p.closeSubpath()
                    let shimmer = 0.3 + 0.5 * (0.5 + 0.5 * sin(t * 2 + Double(i) * 1.3))
                    g.fill(p, with: .color(Color(red:0.5,green:0.85,blue:1.0).opacity(0.16 + 0.24 * shimmer)))
                    g.stroke(p, with: .color(Color.white.opacity(0.25)), lineWidth: 0.6)
                }
                let cr = r * 0.20
                g.fill(Path(ellipseIn: CGRect(x: cx-cr, y: cy-cr, width: cr*2, height: cr*2)),
                    with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), .clear]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: cr))
            }
        }
        .clipShape(Circle())
    }

    /// Flame — a ring of dancing flames around a dark mouth.
    private var flameGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                    with: .radialGradient(Gradient(colors: [Color(red:0.18,green:0.04,blue:0.0), Color(red:0.03,green:0.0,blue:0.0)]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
                var g = ctx; g.blendMode = .plusLighter
                let n = 14
                for i in 0..<n {
                    let a = Double(i) / Double(n) * 2 * .pi
                    let flick = 0.6 + 0.4 * sin(t * 7 + Double(i) * 1.9)
                    let baseR = r * 0.55
                    let tipR  = r * (0.78 + 0.30 * flick)
                    let perp = a + .pi/2
                    let w = r * 0.11
                    let bx = cx + CGFloat(cos(a)) * baseR, by = cy + CGFloat(sin(a)) * baseR
                    let tx = cx + CGFloat(cos(a)) * tipR,  ty = cy + CGFloat(sin(a)) * tipR
                    var fl = Path()
                    fl.move(to: CGPoint(x: bx + CGFloat(cos(perp))*w, y: by + CGFloat(sin(perp))*w))
                    fl.addQuadCurve(to: CGPoint(x: tx, y: ty), control: CGPoint(x: bx + CGFloat(cos(perp))*w*0.4, y: by + CGFloat(sin(perp))*w*0.4))
                    fl.addQuadCurve(to: CGPoint(x: bx - CGFloat(cos(perp))*w, y: by - CGFloat(sin(perp))*w), control: CGPoint(x: bx - CGFloat(cos(perp))*w*0.4, y: by - CGFloat(sin(perp))*w*0.4))
                    fl.closeSubpath()
                    g.fill(fl, with: .color(Color(red:1.0,green:0.55,blue:0.12).opacity(0.5 * flick)))
                }
                let cr = r * 0.42
                ctx.fill(Path(ellipseIn: CGRect(x: cx-cr, y: cy-cr, width: cr*2, height: cr*2)),
                    with: .color(Color(red:0.05,green:0.0,blue:0.0)))
            }
        }
        .clipShape(Circle())
    }

    /// Blossom — a soft cherry-blossom flower with drifting petals.
    private var blossomGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                    with: .radialGradient(Gradient(colors: [Color(red:0.20,green:0.06,blue:0.12), Color(red:0.06,green:0.02,blue:0.05)]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
                let petalColor = Color(red:1.0,green:0.62,blue:0.78)
                let petals = 5
                for i in 0..<petals {
                    let a = Double(i) / Double(petals) * 2 * .pi - t * 0.3
                    let pr = r * 0.5
                    let pc = CGPoint(x: cx + CGFloat(cos(a)) * pr * 0.6, y: cy + CGFloat(sin(a)) * pr * 0.6)
                    let ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
                    let s = pr * 0.55
                    func rp(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: pc.x + x*ca - y*sa, y: pc.y + x*sa + y*ca) }
                    var petal = Path()
                    petal.move(to: rp(-s, 0))
                    petal.addQuadCurve(to: rp(s, 0), control: rp(0, -s*0.9))
                    petal.addQuadCurve(to: rp(-s, 0), control: rp(0, s*0.9))
                    petal.closeSubpath()
                    ctx.fill(petal, with: .color(petalColor.opacity(0.85)))
                }
                let cr = r * 0.20
                ctx.fill(Path(ellipseIn: CGRect(x: cx-cr, y: cy-cr, width: cr*2, height: cr*2)),
                    with: .radialGradient(Gradient(colors: [Color(red:1.0,green:0.92,blue:0.5), Color(red:1.0,green:0.7,blue:0.4).opacity(0.4), .clear]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: cr))
            }
        }
        .clipShape(Circle())
    }

    /// Mosaic — a ring of small multi-coloured tiles around a dark centre.
    private var mosaicGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                    with: .color(Color(red:0.06,green:0.06,blue:0.08)))
                let rings = 3
                for ring in 1...rings {
                    let rad = r * (0.35 + 0.55 * CGFloat(ring) / CGFloat(rings))
                    let count = 8 + ring * 4
                    for i in 0..<count {
                        let a = Double(i) / Double(count) * 2 * .pi + Double(ring) * 0.4
                        let px = cx + CGFloat(cos(a)) * rad, py = cy + CGFloat(sin(a)) * rad
                        let hue = (Double(i) / Double(count) + Double(ring) * 0.2).truncatingRemainder(dividingBy: 1.0)
                        let tw = 0.6 + 0.4 * sin(t * 2 + Double(i) + Double(ring))
                        let s = r * 0.09
                        ctx.fill(Path(roundedRect: CGRect(x: px-s, y: py-s, width: s*2, height: s*2), cornerRadius: s*0.3),
                            with: .color(Color(hue: hue, saturation: 0.7, brightness: 0.95).opacity(0.55 + 0.4 * tw)))
                    }
                }
            }
        }
        .clipShape(Circle())
    }

    /// Ripple — concentric water rings expanding outward over a calm pool.
    private var rippleGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                    with: .radialGradient(Gradient(colors: [Color(red:0.08,green:0.30,blue:0.46), Color(red:0.02,green:0.10,blue:0.20)]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
                let waves = 4
                for i in 0..<waves {
                    let phase = (t * 0.5 + Double(i) / Double(waves)).truncatingRemainder(dividingBy: 1.0)
                    let rr = r * CGFloat(phase)
                    let op = (1 - phase) * 0.7
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx-rr, y: cy-rr, width: rr*2, height: rr*2)),
                        with: .color(Color(red:0.7,green:0.92,blue:1.0).opacity(op)),
                        lineWidth: max(1, r * 0.05))
                }
                let cr = r * 0.10
                ctx.fill(Path(ellipseIn: CGRect(x: cx-cr, y: cy-cr, width: cr*2, height: cr*2)),
                    with: .color(Color(red:0.8,green:0.95,blue:1.0).opacity(0.8)))
            }
        }
        .clipShape(Circle())
    }

    /// Comet — white-blue streaks whirling around a glowing core.
    private var cometGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                    with: .color(Color(red:0.01,green:0.02,blue:0.05)))
                var g = ctx; g.blendMode = .plusLighter
                let streaks = 5
                for i in 0..<streaks {
                    let a = Double(i) / Double(streaks) * 2 * .pi + t * 1.1
                    let rad = r * 0.78
                    let hx = cx + CGFloat(cos(a)) * rad, hy = cy + CGFloat(sin(a)) * rad
                    var trail = Path()
                    trail.move(to: CGPoint(x: hx, y: hy))
                    for k in 1...10 {
                        let kk = Double(k)
                        let aa = a - kk * 0.10
                        let rr = rad * CGFloat(1 - kk * 0.06)
                        trail.addLine(to: CGPoint(x: cx + CGFloat(cos(aa)) * rr, y: cy + CGFloat(sin(aa)) * rr))
                    }
                    g.stroke(trail, with: .color(Color(red:0.75,green:0.9,blue:1.0).opacity(0.6)),
                             style: StrokeStyle(lineWidth: r * 0.06, lineCap: .round))
                    g.fill(Path(ellipseIn: CGRect(x: hx-r*0.06, y: hy-r*0.06, width: r*0.12, height: r*0.12)),
                           with: .color(Color.white.opacity(0.95)))
                }
                let cr = r * 0.22
                g.fill(Path(ellipseIn: CGRect(x: cx-cr, y: cy-cr, width: cr*2, height: cr*2)),
                    with: .radialGradient(Gradient(colors: [Color(red:0.85,green:0.95,blue:1.0).opacity(0.9), .clear]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: cr))
            }
        }
        .clipShape(Circle())
    }

    /// Neon — concentric glowing neon tubes flickering while their hues cycle
    /// through the full spectrum (each tube offset so the set always spans
    /// several colours), plus a bright highlight that orbits each tube like
    /// current racing round the glass.  At t=0 (Reduce Motion) the hues sit
    /// on the classic magenta/cyan pair and the orbiting highlight is
    /// skipped, so the frozen frame matches the original two-hue sign.
    private var neonGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)), with: .color(.black))
                var g = ctx; g.blendMode = .plusLighter
                for i in 0..<4 {
                    let rr = r * CGFloat(0.30 + 0.20 * Double(i))
                    let flick = 0.7 + 0.3 * sin(t * 8 + Double(i) * 2)
                    // Full-spectrum hue cycle, seeded on the classic pair
                    // (magenta ~0.88 / cyan ~0.52) so t=0 keeps the old look;
                    // per-tube offset keeps several hues on screen at once.
                    let hueBase: Double = (i % 2 == 0) ? 0.88 : 0.52
                    let hue: Double = (hueBase + t * 0.07 + Double(i) * 0.04).truncatingRemainder(dividingBy: 1.0)
                    let col = Color(hue: hue, saturation: 0.92, brightness: 1.0)
                    g.stroke(Path(ellipseIn: CGRect(x: cx-rr, y: cy-rr, width: rr*2, height: rr*2)),
                             with: .color(col.opacity(0.25 * flick)), lineWidth: r * 0.16)
                    g.stroke(Path(ellipseIn: CGRect(x: cx-rr, y: cy-rr, width: rr*2, height: rr*2)),
                             with: .color(col.opacity(0.9 * flick)), lineWidth: r * 0.04)

                    // Traveling highlight — a short white-hot arc racing round
                    // the tube, alternating direction per ring.  Motion-only.
                    if !reduceMotion {
                        let dir: Double = (i % 2 == 0) ? 1.0 : -1.0
                        let a0: Double = t * 1.4 * dir + Double(i) * 1.7
                        var hi = Path()
                        hi.addArc(center: CGPoint(x: cx, y: cy), radius: rr,
                                  startAngle: .radians(a0), endAngle: .radians(a0 + 0.55),
                                  clockwise: false)
                        g.stroke(hi, with: .color(Color.white.opacity(0.75 * flick)),
                                 style: StrokeStyle(lineWidth: r * 0.05, lineCap: .round))
                    }
                }
            }
        }
        .clipShape(Circle())
    }

    /// Eclipse — a black disc ringed by a slowly-pulsing golden corona.
    private var eclipseGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                let pulse = 1.0 + 0.06 * sin(t * 1.6)
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)), with: .color(Color(red:0.02,green:0.02,blue:0.05)))
                var g = ctx; g.blendMode = .plusLighter
                let glowR = r * CGFloat(pulse)
                g.fill(Path(ellipseIn: CGRect(x: cx-glowR, y: cy-glowR, width: glowR*2, height: glowR*2)),
                    with: .radialGradient(Gradient(stops: [
                        .init(color: Color(red:1.0,green:0.82,blue:0.38).opacity(0.0), location: 0.50),
                        .init(color: Color(red:1.0,green:0.82,blue:0.38).opacity(0.5), location: 0.66),
                        .init(color: Color(red:1.0,green:0.6,blue:0.15).opacity(0.0), location: 0.95)]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: glowR))
                let ringR = r * 0.60
                ctx.stroke(Path(ellipseIn: CGRect(x: cx-ringR, y: cy-ringR, width: ringR*2, height: ringR*2)),
                           with: .color(Color(red:1.0,green:0.86,blue:0.42).opacity(0.95)), lineWidth: r * 0.06)
                let cr = r * 0.55
                ctx.fill(Path(ellipseIn: CGRect(x: cx-cr, y: cy-cr, width: cr*2, height: cr*2)), with: .color(Color(red:0.01,green:0.01,blue:0.03)))
            }
        }
        .clipShape(Circle())
    }

    /// Plasma — jagged electric arcs writhing out of a white-hot core.
    private var plasmaGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                    with: .radialGradient(Gradient(colors: [Color(red:0.18,green:0.04,blue:0.28), Color(red:0.04,green:0.0,blue:0.08)]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
                var g = ctx; g.blendMode = .plusLighter
                let arcs = 6
                for i in 0..<arcs {
                    let a = Double(i) / Double(arcs) * 2 * .pi + t * 0.8
                    var p = Path()
                    p.move(to: CGPoint(x: cx, y: cy))
                    for k in 1...6 {
                        let f = Double(k) / 6.0
                        let aa = a + sin(t * 9 + Double(i) * 3 + Double(k) * 2.0) * 0.25
                        let rr = r * 0.9 * CGFloat(f)
                        p.addLine(to: CGPoint(x: cx + CGFloat(cos(aa)) * rr, y: cy + CGFloat(sin(aa)) * rr))
                    }
                    g.stroke(p, with: .color(Color(red:0.8,green:0.5,blue:1.0).opacity(0.7)),
                             style: StrokeStyle(lineWidth: r * 0.03, lineCap: .round, lineJoin: .round))
                }
                let cr = r * 0.20
                g.fill(Path(ellipseIn: CGRect(x: cx-cr, y: cy-cr, width: cr*2, height: cr*2)),
                    with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), Color(red:0.7,green:0.4,blue:1).opacity(0.3), .clear]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: cr))
            }
        }
        .clipShape(Circle())
    }

    /// Mirage — shimmering wavy heat-haze bands over warm desert gold.
    private var mirageGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                    with: .radialGradient(Gradient(colors: [Color(red:1.0,green:0.85,blue:0.45), Color(red:0.6,green:0.35,blue:0.08)]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
                var g = ctx; g.blendMode = .plusLighter
                let bands = 7
                for i in 0..<bands {
                    let yy = cy - r + r * 2 * CGFloat(i) / CGFloat(bands - 1)
                    var p = Path()
                    p.move(to: CGPoint(x: cx - r, y: yy))
                    for k in 0...12 {
                        let fx = Double(k) / 12.0
                        let x = cx - r + r * 2 * CGFloat(fx)
                        let wob = sin(fx * 6 + t * 2 + Double(i)) * Double(r) * 0.04
                        p.addLine(to: CGPoint(x: x, y: yy + CGFloat(wob)))
                    }
                    g.stroke(p, with: .color(Color(red:1.0,green:0.95,blue:0.7).opacity(0.22)), lineWidth: r * 0.03)
                }
            }
        }
        .clipShape(Circle())
    }

    /// Prism — a glass triangle fanning a white beam into a spectrum.
    private var prismGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)), with: .color(Color(red:0.06,green:0.06,blue:0.09)))
                var g = ctx; g.blendMode = .plusLighter
                let beams = 7
                for i in 0..<beams {
                    let hue = Double(i) / Double(beams)
                    let spread = (Double(i) - Double(beams - 1) / 2) * 0.12
                    let a = Double.pi / 2 + spread + sin(t * 0.6) * 0.05
                    let bx = cx + CGFloat(cos(a)) * r, by = cy + CGFloat(sin(a)) * r
                    var p = Path(); p.move(to: CGPoint(x: cx, y: cy)); p.addLine(to: CGPoint(x: bx, y: by))
                    g.stroke(p, with: .color(Color(hue: hue, saturation: 0.9, brightness: 1).opacity(0.5)), lineWidth: r * 0.08)
                }
                var tri = Path()
                tri.move(to: CGPoint(x: cx, y: cy - r * 0.45))
                tri.addLine(to: CGPoint(x: cx - r * 0.4, y: cy + r * 0.25))
                tri.addLine(to: CGPoint(x: cx + r * 0.4, y: cy + r * 0.25))
                tri.closeSubpath()
                ctx.fill(tri, with: .color(Color.white.opacity(0.18)))
                ctx.stroke(tri, with: .color(Color.white.opacity(0.8)), lineWidth: 1.2)
            }
        }
        .clipShape(Circle())
    }

    /// Obsidian — dark volcanic glass with faint facets and a gliding sheen.
    private var obsidianGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                    with: .radialGradient(Gradient(colors: [Color(red:0.06,green:0.08,blue:0.18), Color(red:0.0,green:0.0,blue:0.02)]),
                        center: CGPoint(x: cx - r*0.3, y: cy - r*0.3), startRadius: 0, endRadius: r))
                for i in 0..<6 {
                    let a = Double(i) / 6.0 * .pi
                    var p = Path()
                    p.move(to: CGPoint(x: cx - CGFloat(cos(a)) * r, y: cy - CGFloat(sin(a)) * r))
                    p.addLine(to: CGPoint(x: cx + CGFloat(cos(a)) * r, y: cy + CGFloat(sin(a)) * r))
                    ctx.stroke(p, with: .color(Color(red:0.3,green:0.4,blue:0.7).opacity(0.18)), lineWidth: 0.8)
                }
                var g = ctx; g.blendMode = .plusLighter
                let off = CGFloat(sin(t * 0.8)) * r * 0.5
                var sheen = Path()
                sheen.move(to: CGPoint(x: cx - r*0.5 + off, y: cy - r))
                sheen.addLine(to: CGPoint(x: cx - r*0.2 + off, y: cy - r))
                sheen.addLine(to: CGPoint(x: cx + r*0.3 + off, y: cy + r))
                sheen.addLine(to: CGPoint(x: cx + off, y: cy + r))
                sheen.closeSubpath()
                g.fill(sheen, with: .color(Color(red:0.5,green:0.65,blue:1.0).opacity(0.18)))
            }
        }
        .clipShape(Circle())
    }

    /// Quasar — a white-hot core firing two counter-rotating energy jets,
    /// now with hot sparks streaming outward along each jet and an accretion
    /// disc that shimmers segment-by-segment as it slowly turns.  The sparks
    /// and shimmer are motion-only; at t=0 (Reduce Motion) the frozen frame
    /// is the original core + jets + plain ring.
    private var quasarGoal: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cx = size.width / 2, cy = size.height / 2
                let r  = min(size.width, size.height) / 2 * 0.95
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)), with: .color(Color(red:0.02,green:0.0,blue:0.05)))
                var g = ctx; g.blendMode = .plusLighter
                let ang = t * 0.5
                for dir in [CGFloat(1), -1] {
                    let ax = cx + CGFloat(cos(ang)) * r * dir
                    let ay = cy + CGFloat(sin(ang)) * r * dir
                    var jet = Path(); jet.move(to: CGPoint(x: cx, y: cy)); jet.addLine(to: CGPoint(x: ax, y: ay))
                    g.stroke(jet, with: .linearGradient(Gradient(colors: [Color(red:1.0,green:0.2,blue:0.9), Color(red:0.2,green:0.95,blue:1.0).opacity(0.0)]),
                        startPoint: CGPoint(x: cx, y: cy), endPoint: CGPoint(x: ax, y: ay)), style: StrokeStyle(lineWidth: r * 0.12, lineCap: .round))

                    // Jet sparks — hot flecks flung outward along the beam,
                    // fading as they outrun it.  Motion-only.
                    if !reduceMotion {
                        for s in 0..<5 {
                            let sPhase: Double = Double(s) * 0.2
                            let prog: Double = (t * 0.45 + sPhase).truncatingRemainder(dividingBy: 1.0)
                            let f: CGFloat = CGFloat(prog)
                            // Perpendicular scatter off the beam centreline.
                            let jog: Double = sin(t * 6.0 + Double(s) * 2.6) * 0.05
                            let px: CGFloat = cx + (ax - cx) * f + CGFloat(cos(ang + .pi / 2) * jog) * r * dir
                            let py: CGFloat = cy + (ay - cy) * f + CGFloat(sin(ang + .pi / 2) * jog) * r * dir
                            let fade: Double = sin(prog * .pi)
                            let sr: CGFloat = 1.2 + 1.2 * (1 - f)
                            g.fill(Path(ellipseIn: CGRect(x: px - sr, y: py - sr, width: sr * 2, height: sr * 2)),
                                   with: .color(Color(red: 0.75, green: 0.95, blue: 1.0).opacity(0.8 * fade)))
                        }
                    }
                }
                let rr = r * 0.45
                g.stroke(Path(ellipseIn: CGRect(x: cx-rr, y: cy-rr, width: rr*2, height: rr*2)),
                         with: .color(Color(red:0.2,green:0.9,blue:1.0).opacity(0.5)), lineWidth: r * 0.05)

                // Accretion shimmer — short arc segments riding the disc,
                // slowly orbiting while each glints on its own beat.
                if !reduceMotion {
                    let segs = 8
                    for k in 0..<segs {
                        let a0: Double = Double(k) / Double(segs) * 2 * .pi + t * 0.35
                        let glint: Double = 0.5 + 0.5 * sin(t * 2.6 + Double(k) * 1.3)
                        var seg = Path()
                        seg.addArc(center: CGPoint(x: cx, y: cy), radius: rr,
                                   startAngle: .radians(a0), endAngle: .radians(a0 + 0.34),
                                   clockwise: false)
                        g.stroke(seg,
                                 with: .color(Color(red: 0.85, green: 0.98, blue: 1.0).opacity(0.15 + 0.45 * glint)),
                                 style: StrokeStyle(lineWidth: r * 0.06, lineCap: .round))
                    }
                }
                let cr = r * 0.22
                g.fill(Path(ellipseIn: CGRect(x: cx-cr, y: cy-cr, width: cr*2, height: cr*2)),
                    with: .radialGradient(Gradient(colors: [Color.white, Color(red:1.0,green:0.4,blue:0.9).opacity(0.4), .clear]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: cr))
            }
        }
        .clipShape(Circle())
    }

    private var rainbowHole: some View {
        // Style derived from the currently-equipped goal so each variant
        // looks visually distinct without needing its own renderer.
        let style = gameState.equippedGoal.holeStyle
        return TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t    = timeline.date.timeIntervalSinceReferenceDate
                let cx   = size.width  / 2
                let cy   = size.height / 2
                let maxR = (size.width / 2) * 0.90
                let ctr  = CGPoint(x: cx, y: cy)

                // ── Themed dark background ───────────────────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                    with: .color(style.bgColor.opacity(0.60))
                )

                // ── Rim shadow vignette — darkens toward the edge ────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .clear,                       location: 0.55),
                            .init(color: Color.black.opacity(0.40),    location: 0.82),
                            .init(color: Color.black.opacity(0.65),    location: 1.00),
                        ]),
                        center: ctr,
                        startRadius: maxR * 0.55,
                        endRadius:   maxR * 1.02
                    )
                )

                // ── Three concentric particle rings ──────────────────────────
                // (count, radiusFraction, orbitalSpeedBase, minSize, maxSize)
                let rings: [(Int, Double, Double, Double, Double)] = [
                    (16, 0.88, 0.38, 2.6, 7.5),
                    (11, 0.58, 0.58, 2.2, 5.8),
                    (7,  0.28, 0.80, 1.6, 4.2),
                ]

                for (ringIdx, ring) in rings.enumerated() {
                    let (count, rFrac, speedBase, minSz, maxSz) = ring
                    for i in 0..<count {
                        let phase = Double(i) / Double(count)

                        let dir: Double = ringIdx % 2 == 0 ? 1 : -1
                        let speed: Double = dir * (speedBase + Double(i % 5) * 0.10)
                        let angle: Double = phase * 2 * Double.pi + t * speed

                        let breathe: Double = sin(t * 1.5 + phase * 5.8 + Double(ringIdx) * 1.1) * 0.10
                        let r = maxR * (rFrac + breathe)

                        let px = cx + cos(angle) * r
                        let py = cy + sin(angle) * r
                        let pCtr = CGPoint(x: px, y: py)

                        let hueOffset = Double(ringIdx) * 0.33
                        // Map the unbounded "raw" hue through the equipped
                        // goal's hueBase + hueRange so each goal occupies a
                        // distinct slice of the colour wheel.
                        let rawHue = (phase + t * 0.06 + hueOffset).truncatingRemainder(dividingBy: 1.0)
                        let hue = (style.hueBase + rawHue * style.hueRange).truncatingRemainder(dividingBy: 1.0)

                        let twinkFreq: Double = 2.8 + Double(i % 7) * 0.55
                        let twinkArg: Double = t * twinkFreq + phase * .pi * 3 + Double(ringIdx * 7)
                        let raw: Double = (sin(twinkArg) + 1) / 2
                        let twinkle: Double = pow(raw, 2.2)

                        let alpha: Double = 0.30 + twinkle * 0.70
                        let pR: CGFloat = CGFloat(minSz + twinkle * (maxSz - minSz))
                        let color = Color(hue: hue, saturation: style.saturation, brightness: 0.55 + twinkle * 0.45)

                        // Wide glow — radial gradient, bright centre → transparent
                        let gR = pR * 3.8
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: px-gR, y: py-gR, width: gR*2, height: gR*2)),
                            with: .radialGradient(
                                Gradient(colors: [color.opacity(alpha * 0.40), .clear]),
                                center: pCtr, startRadius: 0, endRadius: gR
                            )
                        )

                        // Core dot — white hot centre → saturated hue → transparent edge
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: px-pR, y: py-pR, width: pR*2, height: pR*2)),
                            with: .radialGradient(
                                Gradient(stops: [
                                    .init(color: Color.white.opacity(alpha),          location: 0.00),
                                    .init(color: color.opacity(alpha),                location: 0.45),
                                    .init(color: color.opacity(alpha * 0.15),         location: 1.00),
                                ]),
                                center: pCtr, startRadius: 0, endRadius: pR
                            )
                        )

                        // Sparkle cross at peak brightness
                        if twinkle > 0.60 {
                            let intensity = CGFloat((twinkle - 0.60) / 0.40)
                            let arm  = pR * 2.4 * intensity
                            let stem = CGFloat(0.85)
                            ctx.fill(
                                Path(CGRect(x: px-arm,    y: py-stem/2, width: arm*2,  height: stem)),
                                with: .color(Color.white.opacity(Double(intensity) * 0.90))
                            )
                            ctx.fill(
                                Path(CGRect(x: px-stem/2, y: py-arm,    width: stem,   height: arm*2)),
                                with: .color(Color.white.opacity(Double(intensity) * 0.90))
                            )
                        }
                    }
                }
            }
        }
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.55), radius: 6, x: 0, y: 2)
    }

    /// In-game marble.  All rendering is delegated to BallSkinView, which
    /// dispatches to the appropriate Canvas renderer or gradient based on the
    /// active skin.  Clipping, overlay strokes, and animation are handled
    /// inside BallSkinView so the shop, home screen, and in-game view are
    /// guaranteed to show identical art for every skin.
    private var marbleView: some View {
        BallSkinView(skin: gameState.activeSkin, diameter: effectiveBallRadius * 2)
            .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 5)
    }

    /// Bottom HUD — just the LEVEL X label.  The home button is rendered
    /// separately by `homeButtonOverlay` so it can sit ABOVE the Oops / Win
    /// overlays and remain tappable while those are showing.
    private func hud(safeBottom: CGFloat) -> some View {
        VStack {
            Spacer()
            Text(bottomLabelText)
                .font(.system(size: 12, weight: .ultraLight, design: .monospaced))
                .kerning(4)
                .foregroundStyle(Color(white: 0.40))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.bottom, max(safeBottom, 12) + 8)
        }
    }

    /// Bottom-HUD caption: the climb shows the level number; other modes show
    /// their own name (e.g. "ZEN GARDEN") since they aren't climb levels.
    private var bottomLabelText: String {
        if case .mainClimb = activeMode.progression {
            return "LEVEL \(gameState.currentLevel)"
        }
        if case .challengeTrack = activeMode.progression {
            return "\(activeMode.displayName.uppercased())  \(gameState.activeTrackLevel) / 100"
        }
        if case .oneShot = activeMode.progression {
            return "CHALLENGE  \(gameState.dailyChallengeIndex + 1) / \(gameState.todaysDailyChallenge.levelCount)"
        }
        return activeMode.displayName.uppercased()
    }

    /// Floating home button — always tappable, even when Oops / Win overlays
    /// are showing.  Rendered in its own layer so it sits on top.  Hidden
    /// during the one-time "Roll Along friend!" welcome moment so it doesn't
    /// compete for the player's attention.
    private func homeButtonOverlay(safeBottom: CGFloat) -> some View {
        VStack {
            Spacer()
            HStack {
                Button {
                    // Quitting an in-progress Challenge of the Day forfeits the
                    // day — confirm first so a stray tap can't cost the run.
                    if isDaily && !gameState.dailyChallengeSettledToday {
                        showDailyQuitConfirm = true
                    } else {
                        nav.goHome()
                    }
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(white: 0.38))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(Color(white: 1.0, opacity: 0.85))
                                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                        )
                }
                .accessibilityLabel("Quit to home screen")
                .accessibilityHint(isDaily
                    ? "Leaving forfeits today's Challenge of the Day."
                    : "Returns to the main menu. No level progress is lost.")
                .confirmationDialog("Forfeit today's Challenge?",
                                    isPresented: $showDailyQuitConfirm,
                                    titleVisibility: .visible) {
                    Button("Quit & Forfeit", role: .destructive) {
                        gameState.failTodaysDailyChallenge()
                        nav.goHome()
                    }
                    Button("Keep Playing", role: .cancel) {}
                } message: {
                    Text("Leaving now ends your run — the Challenge of the Day will be marked failed until tomorrow.")
                }
                Spacer()
            }
            .padding(.leading, 22)
            .padding(.bottom, max(safeBottom, 12) + 8)
        }
    }

    /// Floating rake button (Zen Garden) — bottom-right mirror of the home
    /// button.  Gently smooths the sand: fades the groove out, wipes the
    /// trail, then restores full opacity so the next strokes draw crisp.
    /// Transparent full-garden gesture layer (Zen Garden, manual mode only).
    /// Holding the garden frees the ball to roll with tilt and clears the UI;
    /// releasing re-locks it.  When a prop is selected, a tap drops (or removes)
    /// that prop instead of rolling.
    private func zenInputLayer(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        // Placing a prop: don't roll the ball.
                        guard zenPlacingItem == nil else { return }
                        if !zenTouching {
                            zenTouching = true
                            zenMenuOpen = false      // tuck the menu away while rolling
                            zenSubmenu  = .none
                        }
                    }
                    .onEnded { value in
                        if let item = zenPlacingItem {
                            placeOrRemoveZenProp(item, at: value.location, in: size)
                        } else {
                            zenTouching = false       // re-lock the ball
                        }
                    }
            )
    }

    /// Drop a prop at `location`, or remove an existing prop if the tap landed
    /// on one (so a tap toggles).
    private func placeOrRemoveZenProp(_ item: ZenItem, at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let hitR: CGFloat = 28
        // Explicit types + broken-up sub-expressions: the single chained hypot
        // form below pushed the Swift type-checker over its per-expression time
        // budget on some machines (cascading "cannot find type" errors).
        let hit: (ZenDecoration) -> Bool = { d in
            let dx: CGFloat = d.pos.x * size.width  - location.x
            let dy: CGFloat = d.pos.y * size.height - location.y
            return hypot(dx, dy) < hitR
        }
        if let idx = zenDecorations.firstIndex(where: hit) {
            zenDecorations.remove(at: idx)
        } else {
            let frac = CGPoint(x: location.x / size.width, y: location.y / size.height)
            zenDecorations.append(ZenDecoration(item: item, pos: frac))
        }
        if gameState.hapticsEnabled { Haptics.soft() }
    }

    /// Bake one more sand segment into the persistent groove image.  The groove
    /// accumulates (never fades) so a running pattern fills the whole garden;
    /// "smooth sand" clears it.  Drawing only the NEW segment onto the prior
    /// image keeps this O(1) per frame.
    private func addSandPoint(_ p: CGPoint, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        // (Re)start the canvas on a size change (rotation) or first use — keyed
        // on SIZE ONLY.  Also testing `sandAccumImage == nil` here deadlocked
        // the trail: while the image is still nil (before the very first stroke
        // is baked), every call re-nil'd `lastSandPoint`, so the `guard let
        // last` below always failed, the draw code never ran, and the image
        // stayed nil forever — the ball never left a mark.  `sandCanvasSize`
        // starts `.zero`, so the first real call still initialises here.
        if sandCanvasSize != size {
            sandCanvasSize = size
            sandAccumImage = nil
            lastSandPoint  = nil
        }
        guard let last = lastSandPoint else { lastSandPoint = p; return }
        let d = hypot(p.x - last.x, p.y - last.y)
        guard d > sandMinStep else { return }
        // Pen-up on big jumps (switching pattern, motif crossing centre) so we
        // don't draw a stray line across the garden.
        if d > 90 { lastSandPoint = p; return }

        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 2            // retina-ish: crisp groove edges without the full 3× redraw cost
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { rc in
            sandAccumImage?.draw(at: .zero)
            let cg = rc.cgContext
            cg.setLineCap(.round); cg.setLineJoin(.round)
            // OPAQUE strokes (alpha 1): each move bakes ONE short segment onto the
            // accumulating image, and consecutive round caps overlap at every
            // joint.  With translucent strokes that overlap stacks alpha into a
            // dark bead every few px, so the groove reads as a dotted/dashed
            // line.  Opaque colours (sitting just off the warm-sand bed
            // 0.90,0.78,0.55) overwrite instead of stacking, so the furrow is a
            // single continuous carved line.
            // Groove roughly as wide as the ball (Ø ≈ 36pt) so the trail reads
            // like the marble carved it.  The lane spacing is set wider to match,
            // so the broad grooves stay DISTINCT with a sand ridge between them.
            // Soft darker depression…
            cg.setStrokeColor(UIColor(red: 0.69, green: 0.55, blue: 0.29, alpha: 1.0).cgColor)
            cg.setLineWidth(26)
            cg.move(to: last); cg.addLine(to: p); cg.strokePath()
            // …with a crisp pale carved centre.
            cg.setStrokeColor(UIColor(red: 0.98, green: 0.93, blue: 0.79, alpha: 1.0).cgColor)
            cg.setLineWidth(6)
            cg.move(to: last); cg.addLine(to: p); cg.strokePath()
        }
        sandAccumImage = img
        lastSandPoint = p
    }

    /// Rake action — fade the sand groove away, then wipe it and restore
    /// opacity.  The ball keeps rolling throughout; its fresh marks draw at
    /// full strength once the wipe completes.
    private func smoothSand() {
        if gameState.hapticsEnabled { Haptics.soft() }
        withAnimation(.easeOut(duration: 0.45)) { sandClearFade = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            trailPoints.removeAll(keepingCapacity: true)
            trailTimes.removeAll(keepingCapacity: true)
            // Wipe the persistent groove image so the next strokes draw fresh.
            sandAccumImage = nil
            lastSandPoint  = nil
            sandClearFade = 1
        }
    }

    // MARK: - Lives HUD (top-left)

    /// 6-ball lives indicator with regen countdown.  Wrapped in TimelineView
    /// so the countdown ticks every second and `displayedLives` stays fresh
    /// without us having to manually call `commitRegen` on a timer.
    private func livesHUDOverlay(safeTop: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            // One marble + the live count.  When running low (< 6 lives) a
            // countdown to the next free life appears beside it.  Diamond Balls
            // owners see a diamond marble + ∞.
            let unlimited = gameState.unlimitedLives
            let display   = gameState.displayedLives

            HStack(spacing: 6) {
                lifeIcon(filled: true, gold: unlimited)

                if unlimited {
                    Image(systemName: "infinity")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Self.diamondLifeGradient)
                } else {
                    Text("\(display)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()

                    if display < 6, let secs = gameState.timeToNextLife() {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 10, weight: .semibold))
                            Text(Self.mmss(secs))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color(white: 0.62))
                        .padding(.leading, 2)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.black.opacity(0.35))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
            )
            .padding(.leading, 16)
            // Clear the status bar / Dynamic Island (min 50pt, per earlier runs).
            .padding(.top, max(safeTop + 4, 50))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(livesAccessibilityLabel)
        }
    }

    /// Challenge-of-the-Day attempts HUD — a top-left capsule of pips showing
    /// the free attempts remaining on the current sub-level.  No real lives are
    /// ever at stake in the CotD, so this stands in for the lives HUD.
    private func dailyAttemptsHUDOverlay(safeTop: CGFloat) -> some View {
        let total = GameState.dailyChallengeAttemptsPerLevel
        let left  = gameState.dailyChallengeAttemptsLeft
        return HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.99, green: 0.63, blue: 0.20))
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i < left
                              ? Color(red: 0.99, green: 0.63, blue: 0.20)
                              : Color(white: 0.28))
                        .frame(width: 9, height: 9)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.black.opacity(0.35))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
        )
        .padding(.leading, 16)
        .padding(.top, max(safeTop + 4, 50))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(left) of \(total) attempts left on this Challenge level.")
    }

    /// "M:SS" for a seconds interval (the lives regen countdown).
    private static func mmss(_ secs: TimeInterval) -> String {
        let s = max(0, Int(secs.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Coin Pit live HUD

    /// The Coin Pit round HUD: a top-center pill showing the seconds left and
    /// the running haul (coins caught / target).  The countdown is driven on a
    /// 1-second cadence; the score updates instantly because `coinPitScore` is
    /// observed @State.  Dormant outside the Coin Pit (gated by the caller).
    private func coinPitHUDOverlay(safeTop: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let target = coinPitEffectiveTarget ?? 0
            // Show the full bought duration until the first tick arms the
            // clock, then the live remaining time (never negative).
            let remaining: TimeInterval = {
                guard let deadline = coinPitDeadline else { return coinPitStakedDuration }
                return max(0, deadline.timeIntervalSince(context.date))
            }()
            let urgent = remaining <= 5

            HStack(spacing: 12) {
                // Countdown — turns warm red in the closing seconds.
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(Self.formatCountdown(remaining))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(urgent ? Color(red: 1.00, green: 0.42, blue: 0.38) : .white)

                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 1, height: 16)

                // Haul so far (plus the coin multiplier when one was staked).
                HStack(spacing: 5) {
                    CoinIcon(size: 16)
                    Text("\(coinPitScore)/\(target)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    if coinPitStakedMultiplier > 1 {
                        Text("×\(coinPitStakedMultiplier)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 1.00, green: 0.82, blue: 0.28))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.32))
                    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
            )
            .padding(.top, max(safeTop + 4, 50))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(Int(ceil(remaining))) seconds left. "
                + "\(coinPitScore) of \(target) coins caught."
            )
        }
    }

    private var livesAccessibilityLabel: String {
        if gameState.unlimitedLives {
            return "Unlimited lives."
        }
        let display    = gameState.displayedLives
        let filled     = min(display, GameState.livesMax)
        let stockpile  = max(0, display - GameState.livesMax)
        var label = "\(filled) of \(GameState.livesMax) lives."
        if stockpile > 0 {
            label += " Plus \(stockpile) stockpiled."
        }
        if let next = gameState.timeToNextLife() {
            label += " Next life in \(Self.formatCountdown(next))."
        }
        return label
    }

    /// One life slot.  Three modes (matches HomeView.marbleIcon so the
    /// two HUDs look identical):
    ///   • `filled == true`   → full gradient fill with highlight + shadow
    ///   • `partialFill > 0`  → bottom-aligned partial fill clipped to the
    ///                          circle silhouette (regen progress)
    ///   • neither            → hollow grey outline
    @ViewBuilder
    private func lifeIcon(
        filled:      Bool,
        gold:        Bool,
        partialFill: Double = 0,
        size:        CGFloat = 13
    ) -> some View {
        ZStack {
            Circle()
                .stroke(Color(white: 0.40).opacity(0.7), lineWidth: 0.9)
                .frame(width: size, height: size)

            if filled {
                Circle()
                    .fill(gold ? Self.diamondLifeGradient : Self.redLifeGradient)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.55))
                            .frame(width: size * 0.28, height: size * 0.28)
                            .offset(x: -size * 0.18, y: -size * 0.18)
                    )
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.40), lineWidth: 0.6)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 1.5, y: 1)
            } else if partialFill > 0 {
                Circle()
                    .fill(gold ? Self.diamondLifeGradient : Self.redLifeGradient)
                    .frame(width: size, height: size)
                    .clipShape(BottomFillRect(fraction: partialFill))
            }
        }
        .frame(width: size, height: size)
    }

    private static let redLifeGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.32, blue: 0.32),
            Color(red: 0.78, green: 0.14, blue: 0.14),
        ],
        startPoint: .top, endPoint: .bottom
    )
    /// The "diamond" marble gradient — Diamond Balls (unlimited lives).  Cool
    /// white→cyan, matching the home lives pill so the indestructible-ball
    /// iconography reads the same everywhere (HUD, Out of Lives, Get Lives).
    private static let diamondLifeGradient = LinearGradient(
        colors: [
            Color(red: 0.86, green: 0.96, blue: 1.00),
            Color(red: 0.48, green: 0.74, blue: 0.97),
        ],
        startPoint: .top, endPoint: .bottom
    )

    private static func formatCountdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(ceil(seconds)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Spawn-lock "Tap to start" overlay

    /// Hint shown while the spawn-lock is engaged.  Tap anywhere inside
    /// the arena to advance.  The text changes during the L1 phased
    /// tutorial to introduce concepts one at a time; every other lock
    /// shows the standard "Tap to start".
    ///
    /// The view sits in front of the play area and grabs taps so the
    /// player can begin without targeting any specific control.  Home
    /// button is rendered above this overlay so it stays tappable.
    private var tapToStartOverlay: some View {
        ZStack {
            // Full-screen invisible tap target — release the lock on
            // any tap inside the play area.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { releaseSpawnLock() }

            // Hint pill anchored near the bottom of the safe area.
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(tapToStartHintText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color(white: 0.14))
                        .overlay(
                            Capsule().stroke(Color(white: 0.30), lineWidth: 0.8)
                        )
                )
                // Gentle pulse to draw the eye without being noisy.
                .symbolEffect(.pulse, options: .repeating)
                .padding(.horizontal, 24)
                .padding(.bottom, 160)   // clear of the home button
            }
            .allowsHitTesting(false)     // taps fall through to Color.clear above
        }
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tapToStartHintText)
    }

    /// Hint text driven by tutorial phase.  L1 first-time-play
    /// progresses through three explanatory phrases; every other state
    /// (replays, L2+, post-tutorial respawn) shows the brief "Tap to
    /// start" prompt.
    private var tapToStartHintText: String {
        switch tutorialPhase {
        case .introHint:
            return "Hold your phone flat. Tap to start the level."
        case .showCoinsHint:
            return "Tilt your phone to roll the ball. Tap to continue."
        case .showHoleHint:
            return "Avoid the hole, if you fall in you lose a life. Reach the target to pass the level. Tap to continue."
        default:
            return "Tap to start"
        }
    }

    /// Release the spawn lock immediately and start the play timer.
    /// Idempotent — calling when no lock is active is a no-op.
    ///
    /// Also drives the L1 tutorial state machine: dismissing each hint
    /// advances to the next phase.  Some advancements relock the ball
    /// straight away (the next hint is queued behind another lock).
    private func releaseSpawnLock() {
        guard spawnLockUntil != nil else { return }
        spawnLockUntil = nil
        levelStartTime = .now

        switch tutorialPhase {
        case .introHint:
            // Phase 0 → 1: empty map, ball free, schedule the coins hint.
            tutorialPhase = .freeRoaming
            scheduleAdvanceToCoinsHint()
        case .showCoinsHint:
            // Phase 2: coins exist, ball free to collect them.
            tutorialPhase = .collectingCoins
        case .showHoleHint:
            // Phase 3: full layout with hole, normal play begins.
            tutorialPhase = .playing
        default:
            break
        }
    }

    /// Lock the ball at its current position with an indefinite spawn
    /// lock — the player must tap to continue.  Used by the L1 tutorial
    /// when revealing the next stage of the layout (coins, then hole).
    private func tutorialLock() {
        spawnLockUntil = .distantFuture
    }

    /// Transition into the "coins available" hint state.  Called ~1.5s
    /// after the player dismisses the intro hint.
    private func enterShowCoinsHint() {
        guard tutorialPhase == .freeRoaming else { return }
        tutorialPhase = .showCoinsHint
        tutorialLock()
    }

    /// Transition into the "hole exists, avoid it" hint state.  Called
    /// the moment the player picks up their third tutorial coin.  The
    /// tutorial re-triggers from `spawnBall` based on `time(for: 1) ==
    /// nil`, so a player who bails after banking but before clearing
    /// will see the tutorial again next time — the spawnBall path
    /// wipes any banked-but-unclaimed L1 coin state so the Phase 2
    /// pickup flow starts fresh.
    private func enterShowHoleHint() {
        guard tutorialPhase == .collectingCoins else { return }
        tutorialPhase = .showHoleHint
        tutorialLock()
    }

    /// Sleeps ~1.5s on the main actor, then advances `.freeRoaming`
    /// into `.showCoinsHint`.  Cancellation-safe: if the phase has
    /// shifted (e.g. the player navigated home) the advancement is
    /// silently dropped.
    private func scheduleAdvanceToCoinsHint() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            enterShowCoinsHint()
        }
    }

    // MARK: - Out of lives overlay

    /// Centred lives-status pill used inside the out-of-lives overlay.
    /// Visually identical to the home-screen lives pill so the player
    /// gets a consistent read of their state regardless of context.
    private var outOfLivesMarbleRow: some View {
        let unlimited     = gameState.unlimitedLives
        let display       = gameState.displayedLives
        let filledMarbles = unlimited ? GameState.livesMax : min(display, GameState.livesMax)
        let stockpile     = unlimited ? 0 : max(0, display - GameState.livesMax)
        let regen         = unlimited ? nil : gameState.regenProgress()

        return HStack(spacing: 6) {
            ForEach(0..<GameState.livesMax, id: \.self) { i in
                let isFilled = i < filledMarbles
                let partial: Double = (!isFilled
                                       && i == filledMarbles
                                       && regen != nil) ? (regen ?? 0) : 0
                lifeIcon(
                    filled:      isFilled,
                    gold:        unlimited,
                    partialFill: partial,
                    size:        20
                )
            }
            if unlimited {
                Image(systemName: "infinity")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Self.diamondLifeGradient)
                    .padding(.leading, 2)
            } else if stockpile > 0 {
                Text("+\(stockpile)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(white: 0.14))
                .overlay(
                    Capsule().stroke(Color(white: 0.28), lineWidth: 0.8)
                )
        )
    }

    private var outOfLivesOverlay: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            ZStack {
                Color.black.opacity(0.78).ignoresSafeArea()

                VStack(spacing: 22) {
                    Spacer()

                    VStack(spacing: 6) {
                        Text("Out of Lives")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Lives refill 1 every 10 minutes.")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(white: 0.70))
                    }

                    // Identical to the home pill — 20pt marbles, 6pt
                    // spacing, regen progress shown as a bottom-up
                    // partial fill on the next-empty marble, stockpile
                    // "+N" or unlimited ∞ trailing.  Capsule background
                    // matches the home/coin pill aesthetic.
                    outOfLivesMarbleRow

                    Spacer()

                    VStack(spacing: 10) {
                        // Play Now appears when a regen tick has filled a life.
                        if gameState.displayedLives > 0 {
                            Button {
                                gameState.commitRegen()
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    showOutOfLives = false
                                }
                                spawnBall(in: arenaSize)
                            } label: {
                                Text("Play Now")
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white)
                                    )
                            }
                        }

                        // Watch ad — grants exactly 1 life on completion.  No
                        // cap on stockpile.  Pre-loaded at app launch and after
                        // every dismissal so the tap is instant.
                        Button {
                            guard !adInFlight else { return }
                            if !ads.isReady {
                                // No ad cached — kick off a load and surface a
                                // soft retry message.  Most users hit this only
                                // on a flaky network.
                                showAdNotReadyAlert = true
                                AnalyticsClient.shared.track("ad_watch_tap_not_ready")
                                return
                            }
                            adInFlight = true
                            AnalyticsClient.shared.track("ad_watch_tap")
                            ads.showRewarded { _ in
                                adInFlight = false
                                // Lives are granted inside AdManager's reward
                                // handler — no extra plumbing needed here.
                                // If the ad earned a reward, gameState.lives
                                // already bumped; the regen / Play Now button
                                // path can resume naturally.
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if adInFlight {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(Color(white: 0.92))
                                } else {
                                    Image(systemName: "play.rectangle.fill")
                                }
                                Text(adInFlight ? "Loading…" : "Watch ad — +1 life")
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(white: 0.92))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(white: 0.18))
                            )
                        }
                        .disabled(adInFlight)
                        .alert("Ad not ready yet", isPresented: $showAdNotReadyAlert) {
                            Button("OK", role: .cancel) { }
                        } message: {
                            Text("Give it a few seconds and try again — the next ad is loading in the background.")
                        }

                        // Buy lives — opens the StoreKit-backed purchase sheet.
                        Button {
                            showBuyLivesSheet = true
                            AnalyticsClient.shared.track("buy_lives_sheet_opened")
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "cart.fill")
                                Text("Buy lives")
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.white)
                            )
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.28)) { showOutOfLives = false }
                            nav.goHome()
                        } label: {
                            Text("Quit to Home")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(red: 0.95, green: 0.36, blue: 0.36))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .alert("Coming soon", isPresented: $showLivesPlaceholderAlert) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text(livesPlaceholderMessage)
        }
        .sheet(isPresented: $showBuyLivesSheet) {
            BuyLivesSheet()
        }
        .transition(.opacity)
    }

    /// "Better Luck Tomorrow" — the Challenge of the Day is failed once the
    /// player burns all their attempts on a sub-level.  No reward, no retry;
    /// the hub banner greys out until tomorrow's challenge rotates in.
    private var dailyFailedOverlay: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(Color(white: 0.55))
                    Text("Better Luck Tomorrow")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("You're out of attempts for today's Challenge of the Day. A fresh one rolls in tomorrow.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.70))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) { showDailyFailed = false }
                    nav.goHome()
                } label: {
                    Text("Back to Home")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private var oopsOverlay: some View {
        // The Challenge of the Day shows the free attempts that remain so the
        // player feels the stakes (3 per sub-level); every other mode just
        // nudges them to retry.
        let attemptsLeft = gameState.dailyChallengeAttemptsLeft
        return ZStack {
            Color.black.opacity(0.52).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Oops!")
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                if isDaily {
                    Text("\(attemptsLeft) attempt\(attemptsLeft == 1 ? "" : "s") left — tap to try again")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(attemptsLeft == 1
                                         ? Color(red: 0.98, green: 0.55, blue: 0.35)
                                         : Color(white: 0.85))
                        .multilineTextAlignment(.center)
                } else {
                    Text("Tap to try again")
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.78))
                }
            }
        }
        .onTapGesture {
            spawnBall(in: arenaSize)
        }
        .transition(.opacity)
    }

    private var winOverlay: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()

            VStack(spacing: 26) {
                VStack(spacing: 6) {
                    Text("Level Clear!")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.25, green: 0.90, blue: 0.45))
                    if lastClearedIsNewBestStars && lastClearedStars > 1 {
                        Text("New best!")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.30))
                            .padding(.top, 2)
                    }
                }

                // Stars — only modes that score on stars surface this row.
                if activeMode.showsStars {
                    HStack(spacing: 14) {
                        ForEach(0..<3) { i in
                            Image(systemName: i < lastClearedStars ? "star.fill" : "star")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(
                                    i < lastClearedStars
                                        ? Color(red: 1.00, green: 0.84, blue: 0.30)
                                        : Color(white: 0.30)
                                )
                                .shadow(color: i < lastClearedStars
                                        ? Color(red: 1.00, green: 0.84, blue: 0.30).opacity(0.5)
                                        : .clear,
                                        radius: 8)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(lastClearedStars) of 3 stars earned")
                }

                // Time + personal best — only timed modes show the clock.
                if activeMode.showsTimer {
                    VStack(spacing: 4) {
                        Text(String(format: "%.2fs", lastClearedTime))
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                        if let best = gameState.time(for: gameState.currentLevel),
                           best < lastClearedTime + 0.001 {
                            // Only show "Best" if it's actually different from the
                            // current run, otherwise we'd just be repeating.
                            let isNewBest = abs(best - lastClearedTime) < 0.01
                            Text(isNewBest
                                 ? "New best!"
                                 : String(format: "Best  %.2fs", best))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(
                                    isNewBest
                                        ? Color(red: 1.00, green: 0.84, blue: 0.30)
                                        : Color(white: 0.55)
                                )
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        String(format: "Completed in %.2f seconds.", lastClearedTime)
                        + (gameState.time(for: gameState.currentLevel).map {
                            String(format: " Best %.2f seconds.", $0)
                        } ?? "")
                    )
                }

                // The Challenge of the Day has no coins on its maps and never
                // talks coins on its clear screens — show gauntlet progress
                // instead.  The 30-coin reward is granted silently on full
                // completion and surfaced on the hub banner, not here.
                if isDaily {
                    Text("Level \(gameState.dailyChallengeIndex + 1) of \(gameState.todaysDailyChallenge.levelCount)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.78))
                        .accessibilityLabel("Level \(gameState.dailyChallengeIndex + 1) of \(gameState.todaysDailyChallenge.levelCount).")
                } else {
                    // Coins row — shows all 3 pickup slots.  Collected this
                    // attempt → full detailed CoinIcon (same graphic as the
                    // home pill / shop / in-game coin face); not collected →
                    // hollow grey outline so the slot still reads as "a coin
                    // is here".
                    HStack(spacing: 10) {
                        ForEach(0..<3) { i in
                            if lastClearedCoinIndices.contains(i) {
                                CoinIcon(size: 26)
                                    .shadow(color: Color(red: 0.93, green: 0.65, blue: 0.10).opacity(0.45),
                                            radius: 6)
                            } else {
                                Circle()
                                    .stroke(Color(white: 0.30), lineWidth: 1.4)
                                    .frame(width: 26, height: 26)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(lastClearedCoinIndices.count) of 3 coins collected")

                    // Coin reward earned this run
                    if lastClearedCoinReward > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                            Text("\(lastClearedCoinReward) coins")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.30))
                        .accessibilityLabel("Plus \(lastClearedCoinReward) coins earned.")
                    }
                }

                // Actions
                VStack(spacing: 12) {
                    // Primary advance button.  The Challenge of the Day is a
                    // one-shot gauntlet, so on its final sub-level the button
                    // reads "Finish" (which banks the day + pops home) and the
                    // Levels/Replay row is hidden — you don't replay a CotD.
                    let dailyIsLastLevel = isDaily
                        && gameState.dailyChallengeIndex >= gameState.todaysDailyChallenge.levelCount - 1
                    Button { advanceFromLevelClear() } label: {
                        Text(dailyIsLastLevel ? "Finish" : "Next Level")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(red: 0.20, green: 0.78, blue: 0.38))
                            )
                    }
                    if !isDaily {
                        HStack(spacing: 12) {
                            // Levels button — LEFT.  Takes the player to the Level
                            // Select grid (not home).  Goes via the Navigator so
                            // the path is correctly reset.
                            Button { nav.goToLevels() } label: {
                                Text("Levels")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(white: 0.85))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color(white: 0.20))
                                    )
                            }
                            // Replay button — RIGHT.  Re-runs the current level
                            // without leaving BallGameView.
                            Button { spawnBall(in: arenaSize) } label: {
                                Text("Replay")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(white: 0.85))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color(white: 0.20))
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    // MARK: - Coin Pit payout screen
    //
    // Shown when a Coin Pit round ends (target reached or time up).  Presents
    // the haul and offers another round or a trip home.  "Play Again" re-runs
    // spawnBall, whose reset block clears the round state for a fresh start;
    // the new round's clock arms only once the player taps to begin.
    private var coinPitPayoutOverlay: some View {
        let target  = coinPitEffectiveTarget ?? 0
        let perfect = target > 0 && coinPitScore >= target
        // ×2 buy retroactively credits already-caught coins, so every catch is
        // worth the multiplier — this simple formula stays exact.
        let banked  = coinPitScore * coinPitPayoutPerCoin * max(1, coinPitStakedMultiplier)

        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 26) {
                VStack(spacing: 6) {
                    Text(perfect ? "Pit Cleared!" : "Time!")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 1.00, green: 0.82, blue: 0.28))
                    Text(perfect ? "You caught every coin."
                                 : "Nice haul — grab the rest next time.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.65))
                }

                // The haul — a big coin and the count caught.
                HStack(spacing: 12) {
                    CoinIcon(size: 46)
                        .shadow(color: Color(red: 0.93, green: 0.65, blue: 0.10).opacity(0.5),
                                radius: 10)
                    Text("\(coinPitScore)")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("You caught \(coinPitScore) of \(target) coins.")

                Text("+\(banked) coins banked")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.30))
                    .accessibilityLabel("Plus \(banked) coins banked.")

                // Remaining stake — Play Again leads back to the stake
                // screen, which handles the out-of-tickets case itself.
                HStack(spacing: 5) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(gameState.tickets) ticket\(gameState.tickets == 1 ? "" : "s") left")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(Color(white: 0.65))

                // Actions
                VStack(spacing: 12) {
                    Button { spawnBall(in: arenaSize) } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(red: 1.00, green: 0.70, blue: 0.20))
                            )
                    }
                    ResultShareButton(result: ShareableResult(
                        mode: "Gold Rush",   // the coin-pit mode is DISPLAYED as Gold Rush
                        headline: "\(coinPitScore) coins",
                        subtitle: perfect ? "Cleared the pit 💰" : "\(coinPitScore) of \(target)",
                        skin: gameState.activeSkin,
                        trail: gameState.equippedTrail,
                        won: perfect))
                    Button { nav.goHome() } label: {
                        Text("Home")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(white: 0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(white: 0.20))
                            )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    // MARK: - Gold Rush in-round ×2 boost

    /// The only mid-round upsell: a flat 2 tickets to double your coins for the
    /// rest of the round.  Buying it retroactively doubles everything caught so
    /// far (one extra payout of the current haul), then `coinPitStakedMultiplier`
    /// makes every later catch worth ×2.  Disappears once bought (the HUD then
    /// shows the ×2 badge), and greys out when you can't afford it.
    @ViewBuilder
    private var coinPitDoubleButton: some View {
        if coinPitStakedMultiplier == 1 {
            let canAfford = gameState.tickets >= 2
            Button {
                guard coinPitStakedMultiplier == 1, gameState.spendTickets(2) else { return }
                gameState.addCoins(coinPitScore * coinPitPayoutPerCoin)   // back-pay the haul
                coinPitStakedMultiplier = 2
                fireCoinPickup()
                AnalyticsClient.shared.track("goldrush_double_bought",
                    properties: ["score_at_buy": .int(coinPitScore)])
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("×2 Coins").fontWeight(.heavy)
                    HStack(spacing: 3) {
                        Image(systemName: "ticket.fill").font(.system(size: 11))
                        Text("2").fontWeight(.bold)
                    }
                    .opacity(0.8)
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Capsule().fill(canAfford
                    ? Color(red: 1.00, green: 0.82, blue: 0.28)
                    : Color(white: 0.45)))
                .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!canAfford)
            .opacity(canAfford ? 1 : 0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Gold Rush stake overlay (ticket economy)

    /// Pre-roll for the Gold Rush reward round — the round is bought with
    /// tickets before the clock starts: every TIME ticket buys 30 s, and you
    /// can stake as many as you hold.  (The ×2-coins boost is a separate
    /// in-round purchase, not part of the stake.)  With exactly 1 ticket the
    /// picker is skipped — Start stakes it for a straight 30 s round.  With
    /// none, the round can't begin (the Games hub also gates entry; this
    /// covers deep links and Play Again when broke).
    private var coinPitStakeOverlay: some View {
        let balance = gameState.tickets
        let total   = coinPitStakeTime          // time tickets only

        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color(red: 1.00, green: 0.82, blue: 0.28))
                    Text("Gold Rush")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(balance == 0
                         ? "You're out of tickets."
                         : "You have \(balance) ticket\(balance == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.65))
                        .monospacedDigit()
                }

                if balance == 0 {
                    Text("Win a competitive game to earn a ticket, then come back for the rush.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                } else if balance == 1 {
                    Text("Your ticket buys 30 seconds of raining coins — everything you catch is yours. Spend more to add time; double your coins mid-round for 2 tickets.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                } else {
                    Text("Add as much time as you like — every ticket is another 30 seconds. You can double your coins mid-round for 2 tickets.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    stakeRow("Time", "+30 s each",
                             value: $coinPitStakeTime,
                             lo: 1, hi: max(1, balance))

                    // What the stake buys, at a glance.
                    HStack(spacing: 14) {
                        Label("\(coinPitStakeTime * 30) s", systemImage: "clock.fill")
                        Label("\(total)/\(balance) tickets", systemImage: "ticket.fill")
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 1.00, green: 0.82, blue: 0.28))
                }

                if balance > 0 {
                    Button { startCoinPitRound() } label: {
                        Text(total == 1 ? "Start — 1 ticket" : "Start — \(total) tickets")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(red: 1.00, green: 0.82, blue: 0.28))
                            )
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
        .onAppear { clampCoinPitStakes() }
    }

    /// One stake picker row — minus/plus around the current value, clamped
    /// to [lo, hi] (the bounds shrink as the other row eats the budget).
    private func stakeRow(_ title: String, _ detail: String,
                          value: Binding<Int>, lo: Int, hi: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
            }
            Spacer()
            HStack(spacing: 14) {
                Button {
                    value.wrappedValue = max(lo, value.wrappedValue - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(value.wrappedValue > lo ? Color.white : Color(white: 0.35))
                }
                .disabled(value.wrappedValue <= lo)

                Text("\(value.wrappedValue)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(minWidth: 30)

                Button {
                    value.wrappedValue = min(hi, value.wrappedValue + 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(value.wrappedValue < hi ? Color.white : Color(white: 0.35))
                }
                .disabled(value.wrappedValue >= hi)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.13))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value.wrappedValue) tickets. \(detail).")
    }

    /// Consume the staked tickets and arm the round.  The clock itself
    /// starts on the next physics tick (coinPitTick arms the deadline).
    private func startCoinPitRound() {
        clampCoinPitStakes()
        let time = max(1, coinPitStakeTime)
        guard gameState.spendTickets(time) else { return }
        coinPitTimeTicketsStaked = time
        coinPitStakedMultiplier  = 1          // ×2 is an optional in-round buy
        coinPitStaked = true
        AnalyticsClient.shared.track(
            "goldrush_round_staked",
            properties: ["time_tickets": .int(time)]
        )
    }

    /// Keep the pickers inside the live budget — the balance can shrink
    /// between rounds (Play Again after spending), so re-clamp on entry.
    private func clampCoinPitStakes() {
        // Time tickets are limited only by the player's balance now.
        coinPitStakeTime = min(max(1, coinPitStakeTime), max(1, gameState.tickets))
    }

    /// Early-exit refund: leaving mid-round returns one ticket per FULL
    /// 30 s block still un-played (coin tickets never refund).  No-op once
    /// the round finished, or before anything was staked.
    private func refundUnplayedCoinPitBlocks() {
        guard isCoinPit, coinPitStaked, !coinPitOver else { return }
        let unplayed: Int
        if let deadline = coinPitDeadline {
            let remaining = max(0, deadline.timeIntervalSinceNow)
            unplayed = Int(remaining / GameState.goldRushSecondsPerTicket)
        } else {
            // Staked but the clock never armed — nothing was played.
            unplayed = coinPitTimeTicketsStaked
        }
        coinPitStaked = false
        let refund = min(unplayed, coinPitTimeTicketsStaked)
        guard refund > 0 else { return }
        gameState.addTickets(refund)
        AnalyticsClient.shared.track(
            "goldrush_ticket_refund",
            properties: ["tickets": .int(refund)]
        )
    }

    // MARK: - Tutorial reward modal (one-time, after first L10 clear)
    //
    // Awarded after the tutorial — player picks ONE .standard-tier item
    // from ANY category to keep for free.  Selecting an item in any row
    // replaces any prior selection (across all categories).  The picked
    // item is granted + equipped on Claim.

    private var tutorialRewardOverlay: some View {
        // The post-tutorial gift: pick ONE entire Standard-rarity collection.
        let bundles = CosmeticBundle.catalogue.filter { $0.rarity == .standard && $0.isAvailable }
        let hasPick = tutorialBundlePick != nil

        return ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 0) {
                // Title
                VStack(spacing: 6) {
                    Text("Tutorial Complete!")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Pick a free starter collection — the whole set is yours to keep.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.70))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 18)

                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(bundles) { bundle in
                            tutorialBundleCard(bundle, selected: tutorialBundlePick == bundle.id)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }

                Button {
                    claimTutorialBundle()
                } label: {
                    Text(hasPick ? "Claim collection" : "Pick a collection")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(hasPick ? .black : Color(white: 0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(hasPick ? Color.white : Color(white: 0.20))
                        )
                }
                .disabled(!hasPick)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .transition(.opacity)
    }

    /// One selectable Standard-collection card: name + rarity badge, a row of the
    /// six contained cosmetic previews, and the tagline.
    private func tutorialBundleCard(_ bundle: CosmeticBundle, selected: Bool) -> some View {
        Button {
            tutorialBundlePick = bundle.id
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(bundle.displayName)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    TierBadge(rarity: bundle.rarity, compact: true)
                }
                HStack(spacing: 7) {
                    if let b = bundle.balls.first  { bundleSlotTile(b) }
                    if let g = bundle.goals.first  { bundleSlotTile(g) }
                    if let t = bundle.trails.first { bundleSlotTile(t) }
                    if let f = bundle.floors.first { bundleSlotTile(f) }
                    if let p = bundle.pits.first   { bundleSlotTile(p) }
                    if let m = bundle.music.first  { bundleSlotTile(m) }
                    Spacer(minLength: 0)
                }
                Text(bundle.tagline)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18)
                .fill(selected ? Color(white: 0.17) : Color(white: 0.09)))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(selected ? Color.white : Color(white: 0.20),
                        lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    /// A 40×40 preview tile for one of a bundle's cosmetics (reuses rewardPreview).
    @ViewBuilder
    private func bundleSlotTile<Item: CosmeticItem>(_ item: Item) -> some View {
        rewardPreview(for: item)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.13)))
    }

    /// Compact previews mirror the shop's category-specific renderings.
    @ViewBuilder
    private func rewardPreview<Item: CosmeticItem>(for item: Item) -> some View {
        switch item {
        case let s as BallSkin:
            BallSkinView(skin: s, diameter: 48)
                .padding(6)
        case let g as GoalSkin:
            Circle()
                .fill(GoalSkin.previewGradient(for: g))
                .overlay(Circle().stroke(Color.white.opacity(0.30), lineWidth: 1))
                .padding(6)
        case let t as TrailColor:
            Canvas { ctx, size in
                var path = Path()
                let n = 10
                for i in 0..<n {
                    let p = Double(i) / Double(n - 1)
                    let x = size.width  * CGFloat(0.15 + p * 0.7)
                    let y = size.height * CGFloat(0.85 - p * 0.7)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else      { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(path,
                           with: .color(t == .rainbow
                                        ? Color(red: 0.95, green: 0.30, blue: 0.85)
                                        : t.color),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            .padding(4)
        case let f as Floor:
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(f.color)
            }
            .padding(4)
        case let p as Pit:
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.20))
                RoundedRectangle(cornerRadius: 2).fill(p.color).frame(width: 22, height: 12)
            }
            .padding(4)
        case _ as MusicTrack:
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.45, green: 0.65, blue: 1.0),
                                 Color(red: 0.25, green: 0.40, blue: 0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        default:
            EmptyView()
        }
    }

    // MARK: - Welcome moment (one-time, after first L1 clear)

    private var welcomeMomentOverlay: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            // Continuous sparkle burst behind the text
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    drawWelcomeSparkles(ctx: ctx, size: size,
                                        t: tl.date.timeIntervalSinceReferenceDate)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 16) {
                Spacer()

                Text("Roll Along friend!")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(white: 0.82)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.55), radius: 14, y: 6)
                    .multilineTextAlignment(.center)

                Text("Welcome to your journey.\nReady for level 2?")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.80))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 4)

                Spacer()

                Button {
                    dismissWelcomeMoment()
                } label: {
                    Text("Let's go")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 56)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.white)
                        )
                }
                .padding(.bottom, 80)
            }
            .padding(.horizontal, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissWelcomeMoment() }
        .transition(.opacity)
    }

    /// Rainbow particle burst — drifting + twinkling, full-screen.
    /// Shares the visual language of the rainbow goal and AI play button.
    private func drawWelcomeSparkles(ctx: GraphicsContext, size: CGSize, t: Double) {
        let cx = size.width / 2
        let cy = size.height / 2
        let count = 56

        for i in 0..<count {
            let seed  = Double(i)
            let phase = seed / Double(count)

            // Position: drift around centre with two overlaid orbits
            let angle  = phase * 2 * .pi + seed * 1.3
            let radius = size.width * (0.15 + 0.55 * (0.5 + 0.5 * sin(t * 0.32 + seed * 1.7)))
            let px = cx + cos(angle + t * 0.10) * radius
            let py = cy + sin(angle + t * 0.10) * radius
            let pCtr = CGPoint(x: px, y: py)

            // Twinkle pulse
            let twinkFreq = 2.4 + (seed.truncatingRemainder(dividingBy: 7)) * 0.55
            let raw       = (sin(t * twinkFreq + phase * .pi * 4) + 1) / 2
            let twinkle   = pow(raw, 2.2)

            let hue   = (phase + t * 0.075).truncatingRemainder(dividingBy: 1.0)
            let alpha = 0.30 + twinkle * 0.70
            let pR    = CGFloat(2.5 + twinkle * 7.0)
            let color = Color(hue: hue, saturation: 1.0, brightness: 0.65 + twinkle * 0.35)

            // Glow
            let gR = pR * 4.0
            ctx.fill(
                Path(ellipseIn: CGRect(x: px-gR, y: py-gR, width: gR*2, height: gR*2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(alpha * 0.40), .clear]),
                    center: pCtr, startRadius: 0, endRadius: gR
                )
            )

            // Core
            ctx.fill(
                Path(ellipseIn: CGRect(x: px-pR, y: py-pR, width: pR*2, height: pR*2)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color.white.opacity(alpha),       location: 0.00),
                        .init(color: color.opacity(alpha),             location: 0.45),
                        .init(color: color.opacity(alpha * 0.15),      location: 1.00),
                    ]),
                    center: pCtr, startRadius: 0, endRadius: pR
                )
            )

            // Sparkle cross at peak brightness
            if twinkle > 0.62 {
                let intensity = CGFloat((twinkle - 0.62) / 0.38)
                let arm  = pR * 2.4 * intensity
                let stem = CGFloat(0.9)
                ctx.fill(Path(CGRect(x: px-arm,    y: py-stem/2, width: arm*2, height: stem)),
                         with: .color(Color.white.opacity(Double(intensity) * 0.90)))
                ctx.fill(Path(CGRect(x: px-stem/2, y: py-arm,    width: stem,  height: arm*2)),
                         with: .color(Color.white.opacity(Double(intensity) * 0.90)))
            }
        }
    }

    /// Tapped from the "Next Level" button on the win overlay.
    /// "Next Level" handler from the win overlay.  Routes through one-time
    /// moments (welcome after L1, tutorial reward after L10) when applicable;
    /// otherwise just advances + respawns.
    private func advanceFromLevelClear() {
        // Challenge of the Day — advance through its 1-3 levels; on the last,
        // bank the reward, mark today done, and pop home.
        if case .oneShot = activeMode.progression {
            if gameState.advanceDailyChallenge() {
                gameState.completeTodaysDailyChallenge()
                AnalyticsClient.shared.track("daily_challenge_completed")
                nav.goHome()
            } else {
                spawnBall(in: arenaSize)
            }
            return
        }
        // Challenge tracks bypass the climb's welcome/tutorial moments.
        if case .challengeTrack = activeMode.progression {
            let completed = gameState.advanceTrackLevel()
            if completed {
                // Level 100 cleared — pop back to the track select screen.
                nav.goHome()
            } else {
                spawnBall(in: arenaSize)
            }
            return
        }
        if gameState.currentLevel == 1 && !gameState.seenWelcomeMoment {
            withAnimation(.easeInOut(duration: 0.32)) { showWelcomeMoment = true }
        } else if gameState.currentLevel == 10 && !gameState.seenTutorialReward {
            withAnimation(.easeInOut(duration: 0.32)) { showTutorialReward = true }
        } else {
            gameState.advanceLevel()
            spawnBall(in: arenaSize)
        }
    }

    private func dismissWelcomeMoment() {
        gameState.seenWelcomeMoment = true
        AnalyticsClient.shared.track("welcome_moment_dismissed")
        gameState.advanceLevel()
        spawnBall(in: arenaSize)
        withAnimation(.easeInOut(duration: 0.32)) {
            showWelcomeMoment = false
        }
    }

    /// Claim handler for the tutorial reward modal.  Grants + equips the
    /// single picked cosmetic, marks the moment as seen, then advances
    /// to Level 11.  No-op if the player somehow lands here without a
    /// selection (Claim is disabled until then, so shouldn't happen).
    private func claimTutorialBundle() {
        guard let id = tutorialBundlePick,
              let bundle = CosmeticBundle.catalogue.first(where: { $0.id == id })
        else { return }

        // Gift the whole collection (un-redeemable — never refundable on Sell Back).
        gameState.grantBundleFree(bundle)
        // Equip the full look from the gifted collection so the change is instant.
        if let b = bundle.balls.first  { gameState.equipBall(b) }
        if let g = bundle.goals.first  { gameState.equippedGoal  = g }
        if let t = bundle.trails.first { gameState.equippedTrail = t }
        if let f = bundle.floors.first { gameState.equippedFloor = f }
        if let p = bundle.pits.first   { gameState.equippedPit   = p }
        if let m = bundle.music.first  { gameState.equippedMusic = m }

        gameState.seenTutorialReward = true
        AnalyticsClient.shared.track(
            "tutorial_bundle_claimed",
            properties: ["bundle": .string(bundle.id)]
        )
        withAnimation(.easeInOut(duration: 0.32)) { showTutorialReward = false }
        gameState.advanceLevel()
        spawnBall(in: arenaSize)
    }

    // MARK: - Game logic

    private func spawnBall(in size: CGSize) {
        // Lives gate — non-tutorial levels require a life to attempt.
        // If the player tries to spawn with zero lives, show the
        // out-of-lives overlay instead.
        if activeMode.lives == .consume,
           !gameState.isTutorialLevel(gameState.currentLevel),
           !gameState.unlimitedLives,
           gameState.displayedLives <= 0 {
            withAnimation(.easeInOut(duration: 0.28)) { showOutOfLives = true }
            return
        }
        showOutOfLives = false

        // Clear any in-flight pit-fall state from a prior attempt so the
        // fresh ball spawns at full size/opacity and physics runs immediately.
        endPitFallStateWithoutAnimation()
        pitLandingEvent = nil

        // If a ball Pack is equipped, advance to its next shuffled skin so
        // every attempt rolls a different member of the pack.
        gameState.advancePackSkin()

        ball = Ball(position: startPoint(in: size), velocity: .zero)
        goalBurst = nil  // clear any leftover burst from previous level
        coinsPickedThisAttempt = []
        trailPoints.removeAll(keepingCapacity: true)
        trailTimes.removeAll(keepingCapacity: true)
        trailHueOffset = 0.0
        // Coin Pit: a fresh ball means a fresh round — clear the rain, the
        // clock, and the stake (the stake overlay re-appears for the next
        // round; defaults reset to the minimum 1-time-ticket buy).
        if isCoinPit {
            fallingCoins.removeAll()
            coinPitDeadline    = nil
            coinPitLastRelease = nil
            coinPitReleased    = 0
            coinPitScore       = 0
            coinPitOver        = false
            coinPitStaked            = false
            coinPitTimeTicketsStaked = 0
            coinPitStakedMultiplier  = 1
            coinPitStakeTime         = 1
        }
        // Engage the spawn lock — physics is paused, border shows the
        // "armed" white state, and a "Tap to start" hint sits above the
        // ball.  levelStartTime is intentionally NOT set here — it's set
        // when the lock releases (via tap or 1.5s timeout) so star-time
        // scoring measures real play, not the prep window.
        levelStartTime = nil
        // L1 phased tutorial — runs WHENEVER the player has L1 as
        // their only unlocked level AND hasn't passed it yet (no
        // recorded best time).  This covers:
        //   • Fresh installs (highestUnlocked = 1, time = nil)
        //   • "Reset level progress" from Settings (same state)
        //   • Mid-tutorial bails that came back later
        //
        // Once L1 is cleared (bestTime[1] gets set), every subsequent
        // spawn — Replay, Next Level → ... → L1 from Level Select —
        // uses the standard 1.5s spawn-lock with the normal hint.
        //
        // Any banked coin progress on L1 from a prior aborted tutorial
        // is wiped so the Phase 2 pickup flow works fresh.
        // The phased L1 tutorial belongs to the climb only — never run it in
        // an alternate mode (e.g. a new player who taps Zen Garden before
        // clearing L1 would otherwise get climb intro hints in the sandbox).
        var isClimb: Bool { if case .mainClimb = activeMode.progression { return true } else { return false } }
        let isFirstL1Run = isClimb
                        && gameState.currentLevel == 1
                        && gameState.time(for: 1) == nil
        if isFirstL1Run {
            tutorialPhase  = .introHint
            spawnLockUntil = .distantFuture
            gameState.clearCollectedCoins(for: 1)
            tutorialCoinBonus = 0
        } else {
            tutorialPhase  = .notTutorial
            // Zen Garden has no "tap to start" — the ball rests, locked, until
            // the player holds the garden to roll it (see tick()).
            spawnLockUntil = usesSandTrail ? nil : .now.addingTimeInterval(spawnLockDuration)
            tutorialCoinBonus = 0
        }
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }

        // `level_attempt` is a climb-funnel event keyed to a climb level —
        // only meaningful for goal-reaching modes (the climb today, themed
        // challenge tracks later).  Endless/score modes like Zen Garden have
        // no "level attempt," so logging one against the player's current
        // climb level would pollute the climb's attempt→complete funnel.
        if activeMode.goal == .reachGoal {
            AnalyticsClient.shared.track(
                "level_attempt",
                properties: [
                    "tier":        .string(layout.tier.rawValue),
                    "is_tutorial": .bool(gameState.isTutorialLevel(gameState.currentLevel)),
                ],
                level: gameState.currentLevel
            )
        }
        // Challenge Track funnel: parallel start event so we can measure
        // started → cleared drop-off per track and level.
        if case .challengeTrack(let trackID) = activeMode.progression {
            AnalyticsClient.shared.track(
                "track_level_started",
                properties: [
                    "track_id": .string(trackID),
                    "level":    .int(gameState.activeTrackLevel),
                ]
            )
        }
    }

    private func tick(geoSize: CGSize) {
        // `isSinkingIntoPit` freezes physics while the ball plays its
        // fall-into-the-pit animation — without this the ball would keep
        // rolling (and re-triggering the fall) behind the end screen.
        guard phase == .playing, !isSinkingIntoPit, !showDailyQuitConfirm, var b = ball else { return }

        // Spawn-lock: physics is paused while the player gets oriented.
        // When the lock expires naturally we arm levelStartTime here (so
        // star-time scoring starts the moment the player could actually
        // input).  Tap-to-start handles the early-release path.
        if let until = spawnLockUntil {
            if Date.now < until { return }
            spawnLockUntil = nil
            levelStartTime = .now
        }

        // Coin Pit: once the round ends, freeze play behind the payout card.
        if isCoinPit && coinPitOver { return }

        let dt = CGFloat(tickRate)

        // Zen Garden control:
        //   • an auto-pattern drives the ball along its parametric path, or
        //   • the ball is locked in place unless the player is holding the
        //     garden (manual roll falls through to the normal tilt physics).
        if usesSandTrail {
            if let pattern = zenPattern {
                // Map the 0…1 speed fraction to loops-per-second.  One loop is
                // the full multi-pass fill (a long path), so the rate is small —
                // the ball's visible pace stays calm (very slow → brisk).
                let rate = 0.008 + 0.04 * zenSpeedFraction
                zenPatternPhase += rate * Double(dt)
                let p = pattern.point(progress: zenPatternPhase, in: geoSize)
                b.position = p
                b.velocity = .zero
                ball = b
                addSandPoint(p, size: geoSize)
                return
            }
            if !zenTouching {
                b.velocity = .zero
                ball = b
                return
            }
        }

        // Reduce Motion: dampen tilt acceleration so the ball is easier to
        // control for players sensitive to fast motion.
        let accelScale: CGFloat = reduceMotion ? 1080 : 1800
        b.velocity.dx += CGFloat(motion.gravity.x) * accelScale * dt
        b.velocity.dy += CGFloat(motion.gravity.y) * accelScale * dt

        b.velocity.dx *= 0.985
        b.velocity.dy *= 0.985

        if motion.gravity == .zero && hypot(b.velocity.dx, b.velocity.dy) < 6 {
            b.velocity = .zero
        }

        b.position.x += b.velocity.dx * dt
        b.position.y += b.velocity.dy * dt

        // Zen Garden manual roll bakes into the persistent sand image (same as
        // the auto-pattern), so a hand-raked garden also fills and stays.
        if usesSandTrail {
            addSandPoint(b.position, size: geoSize)
        }
        // Graphite trail (Paper world / cosmetic trails) — accumulate position
        // points so we can render the fading streak behind the ball.  Skip if
        // too close to the previous point (the ball is nearly stationary).
        else if gameState.equippedTrail != .none {
            let now = Date().timeIntervalSinceReferenceDate
            if let last = trailPoints.last {
                if hypot(b.position.x - last.x, b.position.y - last.y) > trailMinStep {
                    trailPoints.append(b.position)
                    trailTimes.append(now)
                }
            } else {
                trailPoints.append(b.position)
                trailTimes.append(now)
            }
            let cap = effectiveTrailMaxLength
            if trailPoints.count > cap {
                let removed = trailPoints.count - cap
                trailPoints.removeFirst(removed)
                trailTimes.removeFirst(min(removed, trailTimes.count))   // stay in lockstep
                // Bake-in hue per position: advancing the tail offset
                // by `removed × step` means each surviving segment
                // keeps the colour it had before the trim.
                trailHueOffset = (trailHueOffset
                                  + Double(removed) * trailHueStep)
                    .truncatingRemainder(dividingBy: 1.0)
            }
        }

        // Screen-edge wall bounces.  The screen border is a permanent
        // boundary on every level — the ball always bounces off it.
        // (Death zones come from explicit hole-rects in the level
        // layout, NOT from rolling off the edge of the screen.  Easy
        // levels strip the standard side-wall holes, so without these
        // bounces the ball would tumble straight off into the
        // off-screen fall detector.)
        //
        // Bounce coefficient 0.55 matches the original top/bottom feel.
        // Squash + haptic only fire above the velocity threshold so a
        // ball that's barely resting against the wall doesn't pulse
        // continuously.
        let r = effectiveBallRadius
        let bounceVelocityThreshold: CGFloat = 180  // below this, no feedback
        if b.position.y < r {
            b.position.y = r
            let incoming = abs(b.velocity.dy)
            b.velocity.dy = -b.velocity.dy * 0.55
            if incoming > bounceVelocityThreshold { fireWallHit(axis: .vertical, force: incoming) }
        }
        if b.position.y > geoSize.height - r {
            b.position.y = geoSize.height - r
            let incoming = abs(b.velocity.dy)
            b.velocity.dy = -b.velocity.dy * 0.55
            if incoming > bounceVelocityThreshold { fireWallHit(axis: .vertical, force: incoming) }
        }
        if b.position.x < r {
            b.position.x = r
            let incoming = abs(b.velocity.dx)
            b.velocity.dx = -b.velocity.dx * 0.55
            if incoming > bounceVelocityThreshold { fireWallHit(axis: .horizontal, force: incoming) }
        }
        if b.position.x > geoSize.width - r {
            b.position.x = geoSize.width - r
            let incoming = abs(b.velocity.dx)
            b.velocity.dx = -b.velocity.dx * 0.55
            if incoming > bounceVelocityThreshold { fireWallHit(axis: .horizontal, force: incoming) }
        }

        // Coin Pit: rain, fall, and catch the falling coins for this round.
        if isCoinPit { coinPitTick(ballPos: b.position, size: geoSize, dt: dt) }

        // Coin pickup — collect any not yet picked this attempt + not banked.
        // Multiple coins can be collected per run.  Driven by
        // effectiveLayout so the L1 tutorial doesn't allow pickups while
        // coins aren't yet "revealed".
        let banked = bankedCoinIndices
        for (idx, c) in effectiveLayout.coins.enumerated() {
            if coinsPickedThisAttempt.contains(idx) { continue }
            if banked.contains(idx) { continue }
            let cx = c.x * geoSize.width
            let cy = c.y * geoSize.height
            let dist = hypot(b.position.x - cx, b.position.y - cy)
            if dist < effectiveBallRadius + coinRadius {
                coinsPickedThisAttempt.insert(idx)
                fireCoinPickup()
            }
        }

        // L1 tutorial — 3rd coin pickup advances to the hole-intro hint.
        // Banking + reward happens here (instead of at level clear) so a
        // fall in the subsequent .playing phase doesn't make the coins
        // re-appear as pickable on respawn.
        //
        // `coinsPickedThisAttempt` is INTENTIONALLY left populated for
        // the rest of this attempt — that's what keeps the coin layer
        // from re-rendering the now-banked coins as dimmed "ghosts" the
        // instant they're banked.  handleLevelClear filters
        // already-banked indices out of its reward math so the player
        // isn't paid twice.
        if tutorialPhase == .collectingCoins,
           coinsPickedThisAttempt.count >= effectiveLayout.coins.count,
           !effectiveLayout.coins.isEmpty {
            let picked = coinsPickedThisAttempt
            let bonus  = picked.count * GameState.coinPerPickup
            gameState.bankCoins(for: gameState.currentLevel, indices: picked)
            gameState.addCoins(bonus)
            tutorialCoinBonus += bonus    // surface this in lastClearedCoinReward
            enterShowHoleHint()
            ball = b   // commit ball position to state before bailing
            return     // skip goal/hole checks this tick — physics locks anyway
        }

        // Goal check.  The target is always rendered (so the player
        // sees the destination even during the tutorial), but it's
        // only WIN-eligible once the player has met the hole — i.e.
        // tutorial is either over (`.playing`) or never started
        // (`.notTutorial`).  This stops a first-time L1 player from
        // accidentally rolling into the goal during the free-roam or
        // coin-collecting phases and skipping the rest of the tour.
        // The goal is only a winning target in modes that win by reaching it.
        // ClimbMode's goal is `.reachGoal`, so this is unchanged today;
        // endless/score modes (Zen, Snake, Coin Pit) never trigger a win here.
        let goalLive = activeMode.goal == .reachGoal
            && (tutorialPhase == .playing || tutorialPhase == .notTutorial)
        let gp = goalPoint(in: geoSize)
        if goalLive,
           hypot(b.position.x - gp.x, b.position.y - gp.y) < effectiveBallRadius * 1.7 {
            ball = b
            handleLevelClear(at: gp)
            return
        }

        // Hole check
        if isInHole(position: b.position, size: geoSize) || b.position.x < -r || b.position.x > geoSize.width + r {
            // No-fail modes (Zen Garden) can't lose: there's nothing to fall
            // into and no Oops state.  If the ball somehow escapes a wall
            // bounce under extreme velocity, quietly recenter and carry on —
            // no life, no overlay, no analytics fail event.
            if activeMode.onFail == FailKind.none {
                ball = Ball(position: startPoint(in: geoSize), velocity: .zero)
                return
            }
            // Spawn-grace: a fall registered in the first ~300ms of an
            // attempt is almost always spurious — the player hasn't had
            // time to tilt yet, motion gravity is still ramping, or the
            // freshly-spawned ball briefly overlaps a hole rect during
            // the respawn animation.  Without this guard, tapping Replay
            // right after a fast clear can register a "fall" before the
            // player even sees the ball, silently consuming a life and
            // jumping straight to Out of Lives.
            //
            // Per design: a life is consumed only when the ball falls
            // *during gameplay the player actually had time to play*.
            let elapsedSinceSpawn = levelStartTime.map { Date.now.timeIntervalSince($0) } ?? 0
            if elapsedSinceSpawn < 0.3 {
                // Reset to start with zero velocity — gives the player a
                // clean re-attempt without burning a life.  The next
                // tick will run with a fresh velocity vector.
                ball = Ball(position: startPoint(in: geoSize), velocity: .zero)
                return
            }

            ball = b
            AnalyticsClient.shared.track(
                "level_fail",
                properties: [
                    "tier":          .string(layout.tier.rawValue),
                    "time_to_fail":  .double(elapsedSinceSpawn),
                    "coins_picked":  .int(coinsPickedThisAttempt.count),
                    "is_tutorial":   .bool(gameState.isTutorialLevel(gameState.currentLevel)),
                ],
                level: gameState.currentLevel
            )
            // Hand off to the pit-fall animation: freeze physics, fire the
            // loss feedback once, sink the ball into the depth, then resolve
            // to the right end state.  The branching that used to live here
            // (tutorial reset / Out-of-Lives / Oops / CotD attempts) now runs
            // in `resolvePitFall`, after the ball has visibly fallen away.
            beginPitFall(at: b.position, geoSize: geoSize)
            return
        }

        ball = b
    }

    // MARK: - Pit-fall sequence

    /// Begins the "ball sinks into the pit" animation.  Fires the single
    /// loss feedback (one haptic double-tap + one screen shake + life
    /// consumption, all via `fireFell`), kicks off a pit-specific landing
    /// reaction, animates the ball dropping out of view, and schedules
    /// `resolvePitFall` to surface the end screen once it has vanished.
    private func beginPitFall(at point: CGPoint, geoSize: CGSize) {
        // Re-entrancy guard — a single fall must not stack feedback or
        // schedule multiple resolutions.
        guard !isSinkingIntoPit else { return }
        isSinkingIntoPit = true

        // The one-and-only loss feedback for this fall.
        fireFell()

        // Pit-specific splash / ember / smoke reaction at the entry point.
        // Suppressed under Reduce Motion (the ball still sinks, just plainly).
        if !reduceMotion {
            pitLandingEvent = PitLandingEvent(center: point, start: .now, pit: pit)
        }

        // Animate the descent.  Reduce Motion skips the long drop and just
        // resolves promptly so motion-sensitive players aren't held on a
        // moving ball.
        let duration = reduceMotion ? 0.0 : pitFallDuration
        if duration > 0 {
            withAnimation(.easeIn(duration: duration)) { pitSunk = true }
        } else {
            pitSunk = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) {
            resolvePitFall(geoSize: geoSize)
        }
    }

    /// Runs once the ball has sunk out of view: clears the sink state and
    /// surfaces the correct end screen (tutorial reset / Out-of-Lives /
    /// Oops).  Guarded so a mid-fall navigation away (e.g. tapping Home)
    /// can't fire a stale resolution.
    private func resolvePitFall(geoSize: CGSize) {
        guard isSinkingIntoPit else { return }

        // L1 first-time-play tutorial: a fall during the tour just drops the
        // player out of the phased tutorial and respawns at the start — no
        // Oops, no life lost (L1 is a tutorial level so `consumeLife` was a
        // no-op above).  Banked coins reappear as dimmed indicators.
        if gameState.currentLevel == 1 && tutorialPhase != .notTutorial {
            tutorialPhase = .notTutorial
            coinsPickedThisAttempt = []
            // The mid-tour coin credit was already paid AND its coins are now
            // banked (un-pickable on the respawn), so leaving the bonus set
            // would subtract it from the eventual clear's payout — zero it so
            // the clear pays its full tier bonus.
            tutorialCoinBonus = 0
            levelStartTime = nil
            spawnLockUntil = .now.addingTimeInterval(spawnLockDuration)
            respawnAfterPitFall(in: geoSize)
            return
        }

        // Clear the sink flags WITHOUT animation so the (now-hidden) ball
        // doesn't visibly "rise" back out before the overlay covers it.
        endPitFallStateWithoutAnimation()
        // The ball has fallen away — drop it so nothing renders or jitters
        // behind the end card.  Replay/Next re-creates it via `spawnBall`.
        ball = nil

        // Challenge of the Day: no real lives are ever spent.  Each sub-level
        // grants a fixed number of free attempts — spend one here; if it was
        // the last, the day is failed (no reward, greyed in the hub) with a
        // "Better Luck Tomorrow" send-off, otherwise it's a normal Oops retry
        // (which shows the attempts that remain).
        if isDaily {
            if gameState.recordDailyAttemptFailure() {
                gameState.failTodaysDailyChallenge()
                AnalyticsClient.shared.track(
                    "daily_challenge_failed",
                    properties: ["sub_level": .int(gameState.dailyChallengeIndex)]
                )
                phase = .fell
                withAnimation(.easeInOut(duration: 0.28)) { showDailyFailed = true }
            } else {
                withAnimation(.easeIn(duration: 0.22)) { phase = .fell }
            }
            return
        }

        // If that was the player's last life, go straight to Out of Lives;
        // otherwise show the Oops screen.  Tutorial levels (lives not
        // consumed) keep displayedLives > 0 and always take the Oops path.
        if !gameState.isTutorialLevel(gameState.currentLevel),
           !gameState.unlimitedLives,
           gameState.displayedLives <= 0 {
            withAnimation(.easeInOut(duration: 0.28)) { showOutOfLives = true }
        } else {
            withAnimation(.easeIn(duration: 0.22)) { phase = .fell }
        }
    }

    /// Respawns the ball at the start after a tutorial-L1 pit fall, resetting
    /// the sink state without an unwanted reverse animation.
    private func respawnAfterPitFall(in geoSize: CGSize) {
        endPitFallStateWithoutAnimation()
        ball = Ball(position: startPoint(in: geoSize), velocity: .zero)
    }

    /// Resets the pit-fall flags outside any animation transaction, so the
    /// next ball appears at full size/opacity instantly rather than easing
    /// up out of the depth.
    private func endPitFallStateWithoutAnimation() {
        var txn = Transaction()
        txn.disablesAnimations = true
        withTransaction(txn) {
            isSinkingIntoPit = false
            pitSunk = false
        }
    }

    // MARK: - Feedback fan-out

    private enum BounceAxis { case horizontal, vertical }

    private func fireWallHit(axis: BounceAxis, force: CGFloat) {
        if gameState.hapticsEnabled { Haptics.light() }
        AudioManager.shared.playBounce(enabled: gameState.soundEnabled)
        // Skip squash animation under Reduce Motion — scale changes can feel
        // jarring for motion-sensitive users.
        if !reduceMotion { squashTrigger &+= 1 }
    }

    private func fireGoalReached(at center: CGPoint) {
        if gameState.hapticsEnabled { Haptics.success() }
        AudioManager.shared.playWin(enabled: gameState.soundEnabled)
        goalBurst = GoalBurstEvent(center: center, start: .now)
    }

    /// Ball fell.  Intentionally NO sound — losing should never feel like a
    /// jump scare.  We use a double-tap medium haptic instead: a brief
    /// "tap-tap on the shoulder" that nudges the player back without
    /// startling them.  Also previous "thud" SystemSound bypassed silent mode,
    /// which the player understandably hated.
    private func fireFell() {
        if gameState.hapticsEnabled {
            Haptics.medium()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                Haptics.medium()
            }
        }
        // Skip screen shake under Reduce Motion — sharp translation can
        // trigger discomfort for motion-sensitive users.
        if !reduceMotion { shakeTrigger &+= 1 }

        // Lives consumption — only modes whose lives policy is `.consume`,
        // and tutorial (L1-10) is always exempt.  ClimbMode consumes, so this
        // is unchanged today; endless/unlimited modes (Zen, Coin Pit) won't
        // burn a life on a fall.
        if activeMode.lives == .consume,
           !gameState.isTutorialLevel(gameState.currentLevel) {
            gameState.consumeLife()
        }
    }

    private func fireCoinPickup() {
        if gameState.hapticsEnabled { Haptics.soft() }
        AudioManager.shared.playCoin(enabled: gameState.soundEnabled)
    }

    // MARK: - Coin Pit round simulation
    //
    // Driven once per physics tick while a Coin Pit round is live.  Releases
    // coins on a steady cadence (front-loaded so the last few seconds aren't
    // empty), advances each coin's fall, catches any that overlap the ball,
    // banks the haul as real currency, and ends the round on target-or-timeout.
    private func coinPitTick(ballPos: CGPoint, size: CGSize, dt: CGFloat) {
        // No clock, no rain until the round is bought on the stake overlay.
        guard coinPitStaked, let target = coinPitEffectiveTarget, !coinPitOver else { return }
        let now = Date.now

        // First tick of the round arms the clock and the release pacing.
        if coinPitDeadline == nil {
            coinPitDeadline    = now.addingTimeInterval(coinPitStakedDuration)
            coinPitLastRelease = now
        }

        // Drip the full target out over the first 85% of the round so the
        // closing seconds are about catching stragglers, not waiting on spawns.
        let interval = (coinPitStakedDuration * 0.85) / Double(target)
        if coinPitReleased < target,
           now.timeIntervalSince(coinPitLastRelease ?? now) >= interval {
            spawnFallingCoin(in: size)
            coinPitReleased   += 1
            coinPitLastRelease = now
        }

        // Advance falls, catch overlaps, cull off-screen coins in one pass.
        let r = effectiveBallRadius
        var survivors: [FallingCoin] = []
        survivors.reserveCapacity(fallingCoins.count)
        var caught = 0
        for var c in fallingCoins {
            c.y += c.vy * dt
            if hypot(ballPos.x - c.x, ballPos.y - c.y) < r + c.size / 2 {
                caught += 1
                continue
            }
            if c.y > size.height + c.size { continue }   // fell past the floor
            survivors.append(c)
        }
        fallingCoins = survivors

        if caught > 0 {
            coinPitScore += caught
            gameState.addCoins(caught * coinPitPayoutPerCoin * max(1, coinPitStakedMultiplier))
            fireCoinPickup()
        }

        // End on target reached or time up; freeze the field for the payout.
        if coinPitScore >= target || now >= (coinPitDeadline ?? now) {
            coinPitOver = true
            gameState.recordGoldRushCoins(coinPitScore)   // leaderboard + new-best bonus
            fallingCoins.removeAll()
        }
    }

    /// Drop a single coin from just above the top edge at a random x and speed.
    private func spawnFallingCoin(in size: CGSize) {
        let s: CGFloat = coinRadius * 2
        let margin = s
        let x  = CGFloat.random(in: margin...max(margin, size.width - margin))
        let vy = CGFloat.random(in: 240...430)
        fallingCoins.append(
            FallingCoin(x: x, y: -s, vy: vy, size: s,
                        phase: Double.random(in: 0...6.28))
        )
    }

    /// The raining coins.  Purely cosmetic — catching is resolved in the tick.
    private func fallingCoinLayer(geo: GeometryProxy) -> some View {
        ForEach(fallingCoins) { coin in
            SpinningCoinView(size: coin.size, phase: coin.phase)
                .position(x: coin.x, y: coin.y)
        }
    }

    // MARK: - Level clear handler

    /// Called when the ball reaches the goal.  Records the result, computes
    /// stars, awards currency-coins for newly-earned achievements, then
    /// transitions to .levelComplete.
    private func handleLevelClear(at center: CGPoint) {
        fireGoalReached(at: center)

        let elapsed = levelStartTime.map { Date.now.timeIntervalSince($0) } ?? 0
        let stars   = computeStars(elapsed: elapsed)

        // ── Challenge Track fast-path ───────────────────────────────────────
        if case .challengeTrack(let trackID) = activeMode.progression {
            let coinReward = coinsPickedThisAttempt.count * GameState.coinPerPickup
                           + GameState.coinPerClear
            if coinReward > 0 { gameState.addCoins(coinReward) }
            lastClearedTime           = elapsed
            lastClearedStars          = stars
            lastClearedCoinIndices    = coinsPickedThisAttempt
            lastClearedIsNewBestStars = true   // no persistent record; always "new"
            lastClearedCoinReward     = coinReward
            AnalyticsClient.shared.track(
                "track_level_cleared",
                properties: [
                    "track_id": .string(trackID),
                    "level":    .int(gameState.activeTrackLevel),
                    "stars":    .int(stars),
                    "time":     .double(elapsed),
                ]
            )
            if gameState.activeTrackLevel == 100 {
                AnalyticsClient.shared.track(
                    "track_completed",
                    properties: ["track_id": .string(trackID)]
                )
            }
            // Prompt at milestone levels — positive moment, player is clearly engaged.
            if [10, 50, 100].contains(gameState.activeTrackLevel) {
                gameState.maybeRequestReview(after: true)
            }
            withAnimation(.easeIn(duration: 0.35)) { phase = .levelComplete }
            return
        }

        // ── Daily Challenge (one-shot) fast-path ───────────────────────────
        // The gauntlet plays generated maps that are NOT `currentLevel` — the
        // player's parked climb level.  Falling through to the climb logic
        // would stamp a bogus 3-star best + time onto that parked level
        // (daily layouts carry sentinel 999 s targets), pay its first-clear
        // bonus, and could bump `highestUnlocked` past the frontier.  A
        // sub-level clear only surfaces gauntlet progress; the day's coin
        // reward is banked once by `completeTodaysDailyChallenge()` when
        // "Finish" is tapped on the last sub-level (see advanceFromLevelClear).
        if case .oneShot = activeMode.progression {
            lastClearedTime           = elapsed
            lastClearedStars          = stars
            lastClearedCoinIndices    = coinsPickedThisAttempt
            lastClearedIsNewBestStars = false   // no persistent record; nothing to best
            lastClearedCoinReward     = 0       // day reward pays on completion, not per level
            AnalyticsClient.shared.track(
                "daily_challenge_level_cleared",
                properties: [
                    "sub_level": .int(gameState.dailyChallengeIndex),
                    "time":      .double(elapsed),
                ]
            )
            withAnimation(.easeIn(duration: 0.35)) { phase = .levelComplete }
            return
        }
        // ── Main climb (original logic below) ──────────────────────────────
        // Everything past this point writes persistent records against
        // `gameState.currentLevel` — only the climb's progression may.
        assert(activeMode.progression.recordsClimbResult,
               "mode \(activeMode.id) fell through to climb record-keeping")

        let level     = gameState.currentLevel
        let prevStars = gameState.stars(for: level)

        // Currency-coin reward.  Two stackable sources:
        //
        //   1. Flat per-clear bonus (`clearCoins(for:)` — 2/3/4 by the
        //      level's difficulty tier) — on EVERY clear, first time or
        //      replay.  Replay farming is blessed (2026-07-01 economy
        //      calibration): the climb pays like the Challenge Tracks,
        //      whether the player pushes to level 10,000 or replays
        //      level 1 ten thousand times.
        //
        //   2. Per-pickup (`coinPerPickup`) for each currency-coin grabbed
        //      this run.  Banked coins can't be re-picked (the pickup gate
        //      skips them), so sticky pickups still pay only once ACROSS
        //      attempts — only the flat bonus repeats.
        //
        // A perfect first clear of an easy level awards 2 + 3.  Replays
        // award the flat bonus plus any never-before-banked pickups.
        let newStars = max(0, stars - prevStars)
        // `coinReward` is the amount we add to the balance HERE.  The L1
        // tutorial may have already banked + credited the three coins at
        // the Phase-2→3 transition (`tutorialCoinBonus`); subtract that
        // portion so the player isn't paid twice in the same attempt.
        let coinReward = GameState.clearCoins(for: level)
                       + coinsPickedThisAttempt.count * GameState.coinPerPickup
                       - tutorialCoinBonus
        // `displayedCoinReward` is what the Level Clear screen shows
        // ("+N coins").  It surfaces the FULL haul from this attempt
        // — coinReward plus any tutorial bonus already paid out — so
        // a first L1 clear correctly reads "+5" (3 tutorial + 2 first
        // clear) instead of the bare "+2".
        let displayedCoinReward = coinReward + tutorialCoinBonus

        lastClearedTime           = elapsed
        lastClearedStars          = stars
        lastClearedCoinIndices    = coinsPickedThisAttempt
        lastClearedIsNewBestStars = stars > prevStars
        lastClearedCoinReward     = displayedCoinReward

        gameState.recordResult(
            level: level,
            stars: stars,
            time:  elapsed,
            coinIndices: coinsPickedThisAttempt
        )
        if coinReward > 0 {
            gameState.addCoins(coinReward)
        }

        AnalyticsClient.shared.track(
            "level_complete",
            properties: [
                "tier":          .string(layout.tier.rawValue),
                "time":          .double(elapsed),
                "stars":         .int(stars),
                "prev_stars":    .int(prevStars),
                "new_stars":     .int(newStars),
                "coins_picked":  .int(coinsPickedThisAttempt.count),
                "coin_reward":   .int(coinReward),
                "is_new_best":   .bool(stars > prevStars),
                "is_tutorial":   .bool(gameState.isTutorialLevel(level)),
            ],
            level: level
        )

        // Prompt on a 3-star clear — peak positive emotional moment on the main climb.
        if stars == 3 {
            gameState.maybeRequestReview(after: true)
        }
        withAnimation(.easeIn(duration: 0.35)) { phase = .levelComplete }
    }

    /// 1 star for clearing, 2 if under target, 3 if under gold.
    private func computeStars(elapsed: TimeInterval) -> Int {
        if elapsed <= layout.goldTime   { return 3 }
        if elapsed <= layout.targetTime { return 2 }
        return 1
    }

    private func isInHole(position: CGPoint, size: CGSize) -> Bool {
        effectiveLayout.holeRects.contains { norm in
            CGRect(
                x: norm.origin.x * size.width,
                y: norm.origin.y * size.height,
                width: norm.width  * size.width,
                height: norm.height * size.height
            ).contains(position)
        }
    }
}

// ---------------------------------------------------------------------------
// SeededRNG — tiny deterministic generator (LCG) used by paper-texture
// overlays so specks/strokes land in the same place every redraw.
// ---------------------------------------------------------------------------
struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next() -> UInt64 {
        state &*= 6364136223846793005
        state &+= 1442695040888963407
        return state
    }
    /// Returns a Double in [0, 1)
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

// ---------------------------------------------------------------------------
// Ball model
// ---------------------------------------------------------------------------
private struct Ball {
    var position: CGPoint
    var velocity: CGVector
}

// ---------------------------------------------------------------------------
// GoalBurstEvent — one-shot particle burst when ball reaches the goal.
// Holds the centre + start time so a TimelineView+Canvas can animate it.
// ---------------------------------------------------------------------------
struct GoalBurstEvent: Equatable {
    let center: CGPoint
    let start:  Date
    let tint:   Color = .white   // particles tinted along their own hue, white is unused fallback

    static func == (lhs: GoalBurstEvent, rhs: GoalBurstEvent) -> Bool {
        lhs.start == rhs.start && lhs.center == rhs.center
    }
}

// ---------------------------------------------------------------------------
// PitLandingEvent — one-shot reaction the moment the ball drops into a pit.
// The look is keyed to the equipped Pit (a water splash for Pond, an ember
// burst for Evil, a smoke poof for the rest …) so a higher-rarity pit feels
// alive when it swallows the ball.  A TimelineView+Canvas reads `start` to
// drive a brief, self-terminating animation.
// ---------------------------------------------------------------------------
struct PitLandingEvent: Equatable {
    let center: CGPoint
    let start:  Date
    let pit:    Pit

    static func == (lhs: PitLandingEvent, rhs: PitLandingEvent) -> Bool {
        lhs.start == rhs.start && lhs.center == rhs.center && lhs.pit == rhs.pit
    }
}

// ---------------------------------------------------------------------------
// BallMotion — CMMotionManager wrapper
// ---------------------------------------------------------------------------
@MainActor
final class BallMotion: ObservableObject {
    @Published var gravity: SIMD2<Float> = .zero

    private let manager  = CMMotionManager()
    private let queue    = OperationQueue()
    private let deadband: Float = 0.05

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gx  = Float(motion.gravity.x)
            let gy  = Float(-motion.gravity.y)
            let mag = sqrt(gx * gx + gy * gy)
            let result: SIMD2<Float> = (mag < self.deadband) ? .zero : SIMD2(gx, gy)
            Task { @MainActor in self.gravity = result }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}

// ---------------------------------------------------------------------------
// PhysicsClock — CADisplayLink-backed tick source.
// More reliable than Timer.publish because it's hardware-vsync driven and
// resists starvation when other main-thread work (e.g. heavy Canvas redraws)
// is in flight.  Pinned to 60Hz so dt = 1/60 stays valid on ProMotion.
// ---------------------------------------------------------------------------
final class PhysicsClock: NSObject, ObservableObject {
    @Published private(set) var tickCount: Int = 0
    private var link: CADisplayLink?

    func start() {
        stop()
        let l = CADisplayLink(target: self, selector: #selector(fire(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func fire(_ link: CADisplayLink) {
        tickCount &+= 1
    }
}

// ---------------------------------------------------------------------------
// Haptics — thin wrapper around UIKit's feedback generators.
// All calls are no-ops when gameState.hapticsEnabled is false (the caller is
// responsible for that check; this keeps the helper stateless).
// ---------------------------------------------------------------------------
enum Haptics {
    static func light()   { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy()   { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func soft()    { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// ---------------------------------------------------------------------------
// SFX — MVP sound layer using AudioToolbox SystemSoundIDs.
//
// NOTE: these are iOS built-in placeholders so the game has audible feedback
// from day one without bundling audio assets.  Replace with proper royalty-
// free or commissioned .wav files in a follow-up pass (see Sprint 1 notes).
// To swap a sound, drop a .wav into the bundle and call .playFile("name").
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// BallSquash — animatable scale pair used by the squash-on-bounce
// keyframeAnimator.  Both axes are independently driven via KeyframeTrack
// so a horizontal pinch reads correctly even mid-bounce.
// ---------------------------------------------------------------------------
struct BallSquash: Animatable {
    var scaleX: CGFloat
    var scaleY: CGFloat
    static let identity = BallSquash(scaleX: 1, scaleY: 1)

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(scaleX, scaleY) }
        set { scaleX = newValue.first; scaleY = newValue.second }
    }
}

// ---------------------------------------------------------------------------
// GoalBurstView — one-shot rainbow burst at the goal location.
// Renders for ~0.75s after the event start, then draws nothing.
// ---------------------------------------------------------------------------
struct GoalBurstView: View {
    let event: GoalBurstEvent
    /// Equipped goal's accent colour — the burst matches the goal you reached.
    var accent: Color = .white
    private let lifetime: TimeInterval = 0.75
    private let particleCount = 26

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let elapsed = tl.date.timeIntervalSince(event.start)
                guard elapsed >= 0, elapsed <= lifetime else { return }
                let t      = CGFloat(elapsed)
                let life   = CGFloat(lifetime)
                let progress = t / life           // 0…1
                let easedOut = 1 - pow(1 - progress, 2.5)  // ease-out

                for i in 0..<particleCount {
                    let seed  = Double(i)
                    let phase = seed / Double(particleCount)
                    let angle = phase * 2 * .pi + seed * 0.13

                    // Per-particle reach varies — adds organic spread
                    let reach = CGFloat(220 + (seed.truncatingRemainder(dividingBy: 5)) * 22)
                    let r = reach * easedOut
                    let px = event.center.x + cos(angle) * r
                    let py = event.center.y + sin(angle) * r

                    let alpha = Double(1.0 - progress)
                    let pR    = CGFloat(7.0 * (1.0 - progress) + 2.0)
                    let color = accent

                    // Glow
                    let gR = pR * 3.0
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: px - gR, y: py - gR, width: gR*2, height: gR*2)),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(alpha * 0.45), .clear]),
                            center: CGPoint(x: px, y: py),
                            startRadius: 0, endRadius: gR
                        )
                    )

                    // Core
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: px - pR, y: py - pR, width: pR*2, height: pR*2)),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: Color.white.opacity(alpha), location: 0.0),
                                .init(color: color.opacity(alpha),       location: 0.5),
                                .init(color: color.opacity(0),           location: 1.0),
                            ]),
                            center: CGPoint(x: px, y: py),
                            startRadius: 0, endRadius: pR
                        )
                    )
                }

                // Central flash ring — bright at start, fades out fast
                if progress < 0.35 {
                    let ringR  = 24 + 80 * progress
                    let ringAlpha = (0.55 * (1 - progress / 0.35))
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: event.center.x - ringR,
                                                y: event.center.y - ringR,
                                                width: ringR*2, height: ringR*2)),
                        with: .color(Color.white.opacity(Double(ringAlpha))),
                        lineWidth: 2.5
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// PitLandingView — one-shot reaction the moment the ball drops into a pit.
//
// The look is keyed to the equipped Pit so each cosmetic swallows the ball
// in character: water pits splash, fire pits throw embers, void pits implode
// inward, the nightclub pit bursts confetti, and everything else coughs up a
// soft dust poof.  Renders for ~0.6s after the event, then draws nothing.
// ---------------------------------------------------------------------------
struct PitLandingView: View {
    let event: PitLandingEvent
    private let lifetime: TimeInterval = 0.6

    /// Coarse reaction families — keeps the Canvas branching readable while
    /// every Pit maps to a deliberate feel.
    private enum Style { case splash, embers, smoke, voidImplosion, confetti }

    private var style: Style {
        switch event.pit {
        case .pond, .downpour, .syrup:                 return .splash
        case .evil, .ember, .sunset, .dusk:            return .embers
        case .space, .eclipse, .aurora, .midnight,
             .twilight, .velvet:                       return .voidImplosion
        case .nightclub:                               return .confetti
        default:                                       return .smoke
        }
    }

    /// Primary / secondary tints per pit, used by the splash & smoke styles
    /// (embers/void/confetti carry their own fixed palettes).
    private var tint: (Color, Color) {
        switch event.pit {
        case .pond:      return (Color(red: 0.55, green: 0.85, blue: 1.0),  Color(red: 0.18, green: 0.50, blue: 0.62))
        case .downpour:  return (Color(red: 0.62, green: 0.78, blue: 1.0),  Color(red: 0.10, green: 0.16, blue: 0.26))
        case .syrup:     return (Color(red: 0.55, green: 0.25, blue: 0.18), Color(red: 0.20, green: 0.06, blue: 0.10))
        case .meadow:    return (Color(red: 0.55, green: 0.78, blue: 0.42), Color(red: 0.10, green: 0.22, blue: 0.10))
        case .canyon:    return (Color(red: 0.78, green: 0.52, blue: 0.34), Color(red: 0.32, green: 0.14, blue: 0.08))
        case .graveyard: return (Color(red: 0.45, green: 0.55, blue: 0.45), Color(red: 0.10, green: 0.14, blue: 0.10))
        default:         return (Color(white: 0.78),                        Color(white: 0.42))
        }
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let elapsed = tl.date.timeIntervalSince(event.start)
                guard elapsed >= 0, elapsed <= lifetime else { return }
                let p = CGFloat(elapsed / lifetime)   // 0…1 progress
                let c = event.center
                // Seed from the event start so particle placement is stable
                // across this landing's frames but differs between falls.
                let seed = event.start.timeIntervalSinceReferenceDate.bitPattern ^ 0x9E37_79B9_7F4A_7C15
                var rng = SeededRNG(seed: seed)
                switch style {
                case .splash:        drawSplash(ctx, c, p, &rng)
                case .embers:        drawEmbers(ctx, c, p, &rng)
                case .smoke:         drawSmoke(ctx, c, p, &rng)
                case .voidImplosion: drawVoid(ctx, c, p, &rng)
                case .confetti:      drawConfetti(ctx, c, p, &rng)
                }
            }
        }
    }

    // MARK: Style renderers

    /// Water: an expanding ripple ring plus droplets that arc up then fall.
    private func drawSplash(_ ctx: GraphicsContext, _ c: CGPoint, _ p: CGFloat, _ rng: inout SeededRNG) {
        let (bright, deep) = tint
        // Ripple ring — expands and fades.
        let ringR = 10 + 70 * p
        ctx.stroke(
            Path(ellipseIn: CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2)),
            with: .color(bright.opacity(Double(0.5 * (1 - p)))),
            lineWidth: 2.5 * (1 - p) + 0.5
        )
        // Droplets — launched outward+up, pulled back down by gravity.
        let drops = 11
        for i in 0..<drops {
            let ang = (Double(i) / Double(drops)) * .pi - .pi   // upper hemisphere
            let spread = 70 + rng.nextUnit() * 60
            let vx = CGFloat(cos(ang)) * CGFloat(spread)
            let vy = CGFloat(sin(ang)) * CGFloat(spread) * 1.2
            let gx = c.x + vx * p
            let gy = c.y + vy * p + 220 * p * p           // gravity arc
            let r  = CGFloat(2 + rng.nextUnit() * 3) * (1 - p * 0.6)
            ctx.fill(
                Path(ellipseIn: CGRect(x: gx - r, y: gy - r, width: r * 2, height: r * 2)),
                with: .color((i % 2 == 0 ? bright : deep).opacity(Double(1 - p)))
            )
        }
    }

    /// Fire: a quick warm flash then sparks shooting up and flickering out.
    private func drawEmbers(_ ctx: GraphicsContext, _ c: CGPoint, _ p: CGFloat, _ rng: inout SeededRNG) {
        // Warm flash, brightest at the start.
        if p < 0.4 {
            let fR = 22 + 60 * p
            ctx.fill(
                Path(ellipseIn: CGRect(x: c.x - fR, y: c.y - fR, width: fR * 2, height: fR * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 1.0, green: 0.7, blue: 0.2).opacity(Double(0.6 * (1 - p / 0.4))), .clear]),
                    center: c, startRadius: 0, endRadius: fR
                )
            )
        }
        var lighter = ctx
        lighter.blendMode = .plusLighter
        let sparks = 16
        for i in 0..<sparks {
            let ang = -(.pi / 2) + (rng.nextUnit() - 0.5) * 2.4   // mostly upward
            let speed = 80 + rng.nextUnit() * 110
            let sx = c.x + CGFloat(cos(ang)) * CGFloat(speed) * p
            let sy = c.y + CGFloat(sin(ang)) * CGFloat(speed) * p + 60 * p * p
            let flick = 0.5 + 0.5 * sin(Double(i) * 1.7 + Double(p) * 18)
            let r = CGFloat(1.5 + rng.nextUnit() * 2.5) * (1 - p)
            let col = i % 3 == 0
                ? Color(red: 1.0, green: 0.9, blue: 0.4)
                : Color(red: 1.0, green: 0.45, blue: 0.1)
            lighter.fill(
                Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)),
                with: .color(col.opacity(Double((1 - p) * flick)))
            )
        }
    }

    /// Default: a few soft dust puffs that rise and expand as they fade.
    private func drawSmoke(_ ctx: GraphicsContext, _ c: CGPoint, _ p: CGFloat, _ rng: inout SeededRNG) {
        let (bright, deep) = tint
        let puffs = 6
        for i in 0..<puffs {
            let ang = (Double(i) / Double(puffs)) * 2 * .pi + rng.nextUnit()
            let dist = (18 + rng.nextUnit() * 22) * Double(p)
            let px = c.x + CGFloat(cos(ang)) * CGFloat(dist)
            let py = c.y + CGFloat(sin(ang)) * CGFloat(dist) - 40 * p   // drift up
            let r  = CGFloat(10 + rng.nextUnit() * 14) * (0.5 + p)      // grow
            ctx.fill(
                Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(colors: [
                        (i % 2 == 0 ? bright : deep).opacity(Double(0.40 * (1 - p))),
                        .clear,
                    ]),
                    center: CGPoint(x: px, y: py), startRadius: 0, endRadius: r
                )
            )
        }
    }

    /// Void: particles are pulled inward and snuffed out, with a faint dark
    /// shockwave ring — the pit "swallows" the ball.
    private func drawVoid(_ ctx: GraphicsContext, _ c: CGPoint, _ p: CGFloat, _ rng: inout SeededRNG) {
        var lighter = ctx
        lighter.blendMode = .plusLighter
        let motes = 18
        for _ in 0..<motes {
            let ang  = rng.nextUnit() * 2 * .pi
            let r0   = 30 + rng.nextUnit() * 55
            let r    = CGFloat(r0) * (1 - p)               // collapse inward
            let mx   = c.x + CGFloat(cos(ang)) * r
            let my   = c.y + CGFloat(sin(ang)) * r
            let dot  = CGFloat(1.0 + rng.nextUnit() * 1.8) * (1 - p * 0.4)
            lighter.fill(
                Path(ellipseIn: CGRect(x: mx - dot, y: my - dot, width: dot * 2, height: dot * 2)),
                with: .color(Color(red: 0.75, green: 0.82, blue: 1.0).opacity(Double(0.85 * (1 - p))))
            )
        }
        // Dark imploding shockwave ring.
        let ringR = 60 * (1 - p) + 6
        ctx.stroke(
            Path(ellipseIn: CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2)),
            with: .color(Color(red: 0.55, green: 0.45, blue: 0.95).opacity(Double(0.5 * (1 - p)))),
            lineWidth: 2.0
        )
    }

    /// Nightclub: a quick burst of multicoloured confetti dots that fall.
    private func drawConfetti(_ ctx: GraphicsContext, _ c: CGPoint, _ p: CGFloat, _ rng: inout SeededRNG) {
        let cols = [Color(red: 1.0, green: 0.20, blue: 0.70),
                    Color(red: 0.30, green: 0.80, blue: 1.0),
                    Color(red: 1.0, green: 0.85, blue: 0.20),
                    Color(red: 0.60, green: 0.30, blue: 1.0)]
        let bits = 18
        for i in 0..<bits {
            let ang = rng.nextUnit() * 2 * .pi
            let speed = 70 + rng.nextUnit() * 90
            let bx = c.x + CGFloat(cos(ang)) * CGFloat(speed) * p
            let by = c.y + CGFloat(sin(ang)) * CGFloat(speed) * p + 200 * p * p
            let s  = CGFloat(3 + rng.nextUnit() * 3) * (1 - p * 0.5)
            ctx.fill(
                Path(CGRect(x: bx - s / 2, y: by - s / 2, width: s, height: s * 1.6)),
                with: .color(cols[i % cols.count].opacity(Double(1 - p)))
            )
        }
    }
}

// ---------------------------------------------------------------------------
// BankedCoinView — already-collected coin, static + dimmed.
// ---------------------------------------------------------------------------
struct BankedCoinView: View {
    let size: CGFloat
    var body: some View {
        Circle()
            .fill(Self.dimmed)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.black.opacity(0.20), lineWidth: 1))
            .opacity(0.45)
    }
    static let dimmed = LinearGradient(
        colors: [Color(white: 0.55), Color(white: 0.35)],
        startPoint: .top, endPoint: .bottom
    )
}

// ---------------------------------------------------------------------------
// SpinningCoinView — minted gold coin with real visible thickness.
//
// Built from two layered shapes:
//
//   • RIM  — a vertical Capsule rendered BEHIND the face.  Wide (~30% of
//            the coin diameter) so the thickness reads even at moderate
//            spin angles.  Decorated with prominent milled grooves —
//            sharp, evenly-spaced horizontal notches that look like the
//            knurled edge of a real coin.
//   • FACE — a gold Ellipse on top, scales in X by |sin(t)| from face-on
//            (full circle) to edge-on (gone).  Decorated with a recessed
//            inner ring + a 5-pointed minted star at the centre.
//
// Phased per coin so adjacent coins never go edge-on at the same time.
// ---------------------------------------------------------------------------
struct SpinningCoinView: View {
    let size:  CGFloat
    let phase: Double

    /// Rim width as a fraction of the coin diameter.  ~30% makes the
    /// thickness visible even at moderate spin angles.
    private var rimWidth: CGFloat { size * 0.30 }

    /// Face gradients — pulled from CoinIcon so the menu coin icon and
    /// the in-game spinning coin render the same gold palette.
    private static let goldenFace     = CoinIcon.goldenFace
    private static let goldenFaceDeep = CoinIcon.goldenFaceDeep
    /// Rim gradient: lit at top + bottom, dark in the middle band.
    /// Mimics the light/shadow on a cylinder side.
    private static let rimGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0.78, green: 0.55, blue: 0.10), location: 0.00),
            .init(color: Color(red: 0.40, green: 0.25, blue: 0.03), location: 0.50),
            .init(color: Color(red: 0.76, green: 0.53, blue: 0.09), location: 1.00),
        ],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        TimelineView(.animation) { tl in
            let t       = tl.date.timeIntervalSinceReferenceDate
            let spinRaw = abs(sin(t * 2.6 + phase))
            let bob     = sin(t * 2.2 + phase * 0.7) * 1.6

            coinBody(spinRaw: spinRaw)
                .offset(y: bob)
        }
    }

    private func coinBody(spinRaw: Double) -> some View {
        ZStack {
            // RIM with milled grooves and bevelled outline
            rimLayer
                .frame(width: rimWidth, height: size * 0.97)

            // FACE with minted detail, scaled in X by the spin
            faceLayer(spinRaw: spinRaw)
                .frame(width: size, height: size)
                .scaleEffect(x: CGFloat(spinRaw), y: 1.0)
        }
    }

    // MARK: - Rim

    private var rimLayer: some View {
        Capsule()
            .fill(Self.rimGradient)
            .overlay(milledGrooves)
            .overlay(
                Capsule().stroke(Color.black.opacity(0.55), lineWidth: 0.9)
            )
            // Subtle inner shadow at the top to suggest the recessed
            // junction between face and rim.
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.30), lineWidth: 0.8)
                    .blur(radius: 0.6)
                    .offset(y: 0.5)
                    .mask(Capsule())
            )
    }

    /// Prominent milled (knurled) edge — many short horizontal notches
    /// evenly spaced down the rim.  This is the most "minted-looking"
    /// detail on the whole coin.
    private var milledGrooves: some View {
        GeometryReader { geo in
            let notchCount = 22
            ForEach(0..<notchCount, id: \.self) { i in
                Rectangle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: geo.size.width * 0.85, height: 0.9)
                    .offset(x: geo.size.width * 0.075,
                            y: geo.size.height * CGFloat(i) / CGFloat(notchCount - 1))
            }
            // Highlight ridges between notches (every other slot)
            ForEach(0..<notchCount, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: geo.size.width * 0.85, height: 0.5)
                    .offset(x: geo.size.width * 0.075,
                            y: geo.size.height * CGFloat(i) / CGFloat(notchCount - 1) + 1.0)
            }
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
    }

    // MARK: - Face

    private func faceLayer(spinRaw: Double) -> some View {
        ZStack {
            // Base face
            Ellipse().fill(Self.goldenFace)

            // Outer face stroke
            Ellipse().stroke(Color.black.opacity(0.45), lineWidth: 1)

            // Squiggle engraving along the rim — identical to the static
            // CoinIcon; foreshortens with the spin via the parent's X scale.
            CoinSquiggle()
                .stroke(Color(red: 0.58, green: 0.38, blue: 0.05).opacity(0.9),
                        lineWidth: 0.9)

            // Triangle hole punched out of the middle — the new shared mark.
            CoinTriangle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.46, green: 0.30, blue: 0.03),
                                 Color(red: 0.24, green: 0.15, blue: 0.01)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: size * 0.40, height: size * 0.40)
                .overlay(
                    CoinTriangle()
                        .stroke(Color.white.opacity(0.35 * spinRaw), lineWidth: 0.5)
                        .frame(width: size * 0.40, height: size * 0.40)
                        .offset(x: -0.4, y: -0.5)
                )

            // Inner highlight crescent on the face — catches the "light"
            Ellipse()
                .stroke(Color.white.opacity(0.55 * spinRaw), lineWidth: 1.0)
                .scaleEffect(0.72)
                .offset(x: -size * 0.10, y: -size * 0.10)

            // Specular sweep — vertical stripe that travels across the face
            shine(spinRaw: spinRaw)
        }
    }

    private func shine(spinRaw: Double) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear,
                             Color.white.opacity(0.50 * spinRaw),
                             .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(width: size * 0.32, height: size)
            .offset(x: CGFloat(spinRaw - 0.5) * size * 0.7)
            .clipShape(Ellipse())
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

// ---------------------------------------------------------------------------
// CoinIcon — the single source of truth for what a Roll Along coin
// looks like everywhere outside the gameplay arena (home page lives /
// coin pill, level-clear summary, level-select stats, cosmetic shop
// header + per-item price, buy-lives/buy-coins sheets).  The in-game
// spinning coin (SpinningCoinView) renders the same face when face-on,
// just with an animated rim.
//
// Anatomy (all scaled by `size`):
//   • Outer face gradient (bright top → deep amber bottom; silver for platinum)
//   • Dark outline stroke
//   • Squiggle engraving traced along the outer rim (CoinSquiggle)
//   • Triangle hole punched out of the middle (CoinTriangle), dark + recessed
//   • Upper-left highlight crescent — catches the light
//   • Subtle drop shadow
// ---------------------------------------------------------------------------
/// A wavy ring traced near the coin's outer edge — the "squiggle" engraving
/// shared by every coin (static icon + in-game spinning coin).
struct CoinSquiggle: Shape {
    var waves: Int = 28
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let dim = min(rect.width, rect.height)
        let baseR = dim * 0.405
        let amp = dim * 0.022
        let steps = 220
        for i in 0...steps {
            let ang = Double(i) / Double(steps) * 2 * .pi
            let r = baseR + CGFloat(sin(ang * Double(waves))) * amp
            let pt = CGPoint(x: c.x + CGFloat(cos(ang)) * r,
                             y: c.y + CGFloat(sin(ang)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// An equilateral triangle (point up) — the "hole" punched in the coin's centre.
struct CoinTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) * 0.5
        for i in 0..<3 {
            let a = -Double.pi / 2 + Double(i) * (2 * .pi / 3)
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * r,
                             y: c.y + CGFloat(sin(a)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct CoinIcon: View {
    let size: CGFloat
    let platinum: Bool

    init(size: CGFloat = 18, platinum: Bool = false) {
        self.size = size
        self.platinum = platinum
    }

    var body: some View {
        let face = platinum ? Self.platinumFace : Self.goldenFace
        let engrave: Color = platinum
            ? Color(red: 0.42, green: 0.50, blue: 0.62)
            : Color(red: 0.58, green: 0.38, blue: 0.05)
        let holeColors: [Color] = platinum
            ? [Color(red: 0.45, green: 0.52, blue: 0.62), Color(red: 0.24, green: 0.30, blue: 0.40)]
            : [Color(red: 0.46, green: 0.30, blue: 0.03), Color(red: 0.24, green: 0.15, blue: 0.01)]
        let tri = size * 0.40
        return ZStack {
            // Gold (or platinum) body + dark outline.
            Circle()
                .fill(face)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.45),
                                    lineWidth: max(0.5, size * 0.04))
                )

            // Squiggle engraving traced along the outer rim.
            CoinSquiggle()
                .stroke(engrave.opacity(0.9), lineWidth: max(0.5, size * 0.04))

            // Triangle hole punched out of the middle (dark + recessed; a
            // top-left lip sells the "punched" depth).
            CoinTriangle()
                .fill(LinearGradient(colors: holeColors, startPoint: .top, endPoint: .bottom))
                .frame(width: tri, height: tri)
                .overlay(
                    CoinTriangle()
                        .stroke(Color.white.opacity(platinum ? 0.5 : 0.3), lineWidth: 0.6)
                        .frame(width: tri, height: tri)
                        .offset(x: -0.4, y: -0.5)
                )

            // Top-left highlight crescent — brighter on platinum (extra shiny).
            Circle()
                .stroke(Color.white.opacity(platinum ? 0.72 : 0.5),
                        lineWidth: max(0.5, size * 0.05))
                .scaleEffect(0.78)
                .offset(x: -size * 0.10, y: -size * 0.10)
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.18),
                radius: max(0.8, size * 0.06),
                y:      max(0.4, size * 0.04))
    }

    // Exposed so SpinningCoinView (in-game animated coin) renders the
    // identical face gradient — keeps the visual language consistent
    // between menus and gameplay.
    static let goldenFace = LinearGradient(
        stops: [
            .init(color: Color(red: 1.00, green: 0.94, blue: 0.55), location: 0.00),
            .init(color: Color(red: 0.97, green: 0.79, blue: 0.22), location: 0.45),
            .init(color: Color(red: 0.78, green: 0.50, blue: 0.06), location: 1.00),
        ],
        startPoint: .top, endPoint: .bottom
    )
    static let goldenFaceDeep = LinearGradient(
        stops: [
            .init(color: Color(red: 0.85, green: 0.70, blue: 0.18), location: 0.00),
            .init(color: Color(red: 0.72, green: 0.50, blue: 0.10), location: 1.00),
        ],
        startPoint: .top, endPoint: .bottom
    )

    // Platinum variant — a cool silver face for the 3-point bonus coin.
    static let platinumFace = LinearGradient(
        stops: [
            .init(color: Color(red: 0.93, green: 0.96, blue: 1.00), location: 0.00),
            .init(color: Color(red: 0.74, green: 0.81, blue: 0.90), location: 0.45),
            .init(color: Color(red: 0.47, green: 0.55, blue: 0.66), location: 1.00),
        ],
        startPoint: .top, endPoint: .bottom
    )
    static let platinumFaceDeep = LinearGradient(
        stops: [
            .init(color: Color(red: 0.80, green: 0.86, blue: 0.94), location: 0.00),
            .init(color: Color(red: 0.55, green: 0.63, blue: 0.74), location: 1.00),
        ],
        startPoint: .top, endPoint: .bottom
    )
}

// ---------------------------------------------------------------------------
// AudioManager — game sound layer.
//
// Two channels:
// 1. Short UI taps (bounce, coin) play via SystemSoundIDs in the 1100-1306
//    range.  These are documented as UI sounds and respect the device
//    silent switch.  We deliberately avoid the alert-category IDs (1000s)
//    that bypass silent — those were the cause of the "loud thud playing
//    even on silent" complaint.
// 2. The win sound plays via AVAudioEngine through an AVAudioSession
//    configured as .ambient — meaning it respects the silent switch and
//    mixes politely with any other audio.  The buffer is synthesized on
//    init (small ascending C-E-G-C major arpeggio) so we don't have to
//    ship a WAV asset.
//
// There is intentionally no "drop" sound.  When the ball falls, we lean
// entirely on a double-tap haptic — losing should feel like a tap on the
// shoulder, not a jump-scare.
// ---------------------------------------------------------------------------
final class AudioManager {
    static let shared = AudioManager()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var winBuffer:  AVAudioPCMBuffer?
    private var sessionConfigured = false

    private init() {}

    /// Lazily configure the audio session + synth the win buffer.  Called
    /// from BallGameView's onAppear so we don't pay this cost until the
    /// game actually starts.
    func prepareIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true

        // Ambient + mixWithOthers: respects the silent switch, mixes with
        // music apps, never ducks anything.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        engine.attach(player)
        let format = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        winBuffer = makeWinBuffer(format: format)

        engine.prepare()
        try? engine.start()

        // Keep the engine warm.  The system STOPS the engine on an audio
        // interruption (call, Siri, another app) or an engine-config change
        // (route change — e.g. plugging in headphones), and a freshly-stopped
        // engine can't be played until it has rendered an IO cycle.  Restarting
        // on those events means playWin() rarely has to cold-start, which is
        // what triggers the "player did not see an IO cycle" crash.
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification,
                       object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self.restartEngine()
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange,
                       object: engine, queue: .main) { [weak self] _ in
            self?.restartEngine()
        }
        // Returning from the background re-activates the session and restarts the
        // engine, so the engine is already warm by the time the player wins.
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.restartEngine()
        }
    }

    /// Re-activate the session and restart the engine if the system stopped it.
    private func restartEngine() {
        try? AVAudioSession.sharedInstance().setActive(true)
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
    }

    func playWin(enabled: Bool) {
        guard enabled, let buffer = winBuffer else { return }
        // Only play when the engine is ALREADY running — i.e. it has been
        // rendering IO cycles.  If the system stopped it (interruption / route
        // change / backgrounding), restart it for next time but SKIP this one
        // sound: calling play() on a just-started engine that hasn't yet
        // rendered an IO cycle throws "player did not see an IO cycle" and
        // crashes.  A rare missed win chime beats a crash.
        guard engine.isRunning else {
            try? AVAudioSession.sharedInstance().setActive(true)
            engine.prepare()
            try? engine.start()
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    /// Short UI tick for wall bounces.  System sound 1104 ("Tink") respects
    /// silent mode.
    func playBounce(enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(1104)
    }

    /// Coin pickup tick.  System sound 1306 (UI "Pop") respects silent.
    func playCoin(enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(1306)
    }

    // MARK: - Win sound synthesis

    /// Synthesises a short C-major arpeggio (C5 → E5 → G5 → C6) with a
    /// gentle exponential decay on each note.  Sounds bright and celebratory
    /// without being loud or jangly.  Total ~0.7s.
    private func makeWinBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let totalDuration = 0.75
        let frameCount = AVAudioFrameCount(sampleRate * totalDuration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        // Notes: (startSec, attackEndSec, releaseDuration, freqHz, gain)
        let notes: [(start: Double, attack: Double, release: Double, freq: Double, gain: Double)] = [
            (0.00, 0.012, 0.32, 523.25, 0.20),   // C5
            (0.08, 0.012, 0.32, 659.25, 0.20),   // E5
            (0.16, 0.012, 0.34, 783.99, 0.22),   // G5
            (0.26, 0.018, 0.45, 1046.50, 0.26),  // C6  — slightly louder finale
        ]

        guard let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            var s: Double = 0
            for n in notes {
                guard t >= n.start else { continue }
                let local = t - n.start
                // Attack ramp then exponential release.
                let envelope: Double
                if local < n.attack {
                    envelope = local / n.attack
                } else {
                    let decay = local - n.attack
                    envelope = exp(-decay / n.release)
                }
                // Tiny bit of second harmonic for warmth.
                let fundamental = sin(2.0 * .pi * n.freq * local)
                let harmonic    = sin(2.0 * .pi * n.freq * 2.0 * local) * 0.18
                s += (fundamental + harmonic) * envelope * n.gain
            }
            // Soft global limiter — divide by ~2 worth of overlap, clamp.
            let sample = Float(max(-0.95, min(0.95, s)))
            for ch in 0..<channelCount {
                channelData[ch][frame] = sample
            }
        }
        return buffer
    }
}
