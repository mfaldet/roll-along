import SwiftUI
import CoreMotion
import Combine
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
enum TutorialPick: Equatable {
    case ball(BallSkin)
    case goal(GoalSkin)
    case trail(TrailColor)
    case floor(Floor)
    case pit(Pit)
    case music(MusicTrack)
}

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

    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    @State private var ball:               Ball?     = nil
    @State private var phase:              GamePhase = .playing
    @State private var arenaSize:          CGSize    = .zero
    @State private var showWelcomeMoment:  Bool      = false
    @State private var showTutorialReward: Bool      = false

    // Tutorial-reward pick.  Player chooses ONE free standard-tier
    // cosmetic from ANY category — picking a new item replaces any
    // prior selection (across all categories), and the Claim button
    // unlocks as soon as something is selected.
    @State private var tutorialPick: TutorialPick? = nil

    // Lives system (Sprint 4c)
    @State private var showOutOfLives:                Bool   = false
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

    /// Actual trim cap used by the tick loop.  Equals `trailMaxLength`
    /// for every trail except the Snake, which grows by
    /// `snakeGrowthPerCoin` for each coin the player has picked up
    /// this attempt — the eat-and-grow mechanic.
    private var effectiveTrailMaxLength: Int {
        if gameState.equippedTrail == .snake {
            return trailMaxLength + coinsPickedThisAttempt.count * snakeGrowthPerCoin
        }
        return trailMaxLength
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

    private let ballRadius:  CGFloat = 18
    private let coinRadius:  CGFloat = 9
    private let tickRate              = 1.0 / 60.0

    /// The ball's actual radius after the equipped skin's size modifier
    /// is applied.  Every skin is full-size except Pluto (0.5×), the
    /// dwarf planet from the Planets bundle.  Used for BOTH rendering
    /// (frame sizing) and physics (wall bounce, coin pickup, goal /
    /// hole collision) so the small marble behaves consistently.
    private var effectiveBallRadius: CGFloat {
        ballRadius * gameState.activeSkin.radiusScale
    }

    private var layout: LevelLayout {
        let base = LevelLayout.layout(for: gameState.currentLevel)
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

    /// Equipped Floor and Pit — read from GameState so the view
    /// re-renders when either is swapped.  Replaces the old `theme`
    /// abstraction since Floor and Pit are now independent picks.
    private var floor: Floor { gameState.equippedFloor }
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
        case .arming: return Color(white: 0.95)   // bright white = "ready"
        case .normal: return Color(white: 0.68)
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

                // Grass floor (Golf bundle) — static fairway turf with
                // randomly-distributed grass tufts.  Subtle so it's
                // not noisy; not animated so it stays under Reduce
                // Motion as well.
                if floor == .grass {
                    grassFloorOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Moon floor (Space Travel bundle) — static lunar
                // regolith with scattered craters.  Like grass it's
                // not animated, so it renders under Reduce Motion too.
                if floor == .moon {
                    moonFloorOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Paper-world floor overlays (ruled lines, grids, fold shadows…)
                paperFloorOverlay(geo: geo)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // Graphite trail (Paper world): drawn over the floor, UNDER the
                // holes — the streak should appear cut by the page tear.
                if gameState.equippedTrail != .none && trailPoints.count >= 2 {
                    trailOverlay(geo: geo)
                        .allowsHitTesting(false)
                }

                // Hole zones (themed)
                holeLayer(geo: geo)

                // Coins (not-yet-collected this attempt, not-yet-banked overall)
                coinLayer(geo: geo)

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
                if showGoalForCurrentPhase {
                    Group {
                        switch gameState.equippedGoal {
                        case .target:      simpleBullseyeTarget
                        case .archery:     archeryTargetGoal
                        case .holeInOne:   holeInOneGoal
                        case .tractorBeam: tractorBeamGoal
                        default:           rainbowHole
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
                        .position(ball.position)
                        .scaleEffect(phase == .playing ? 1.0 : 0.05)
                        .opacity(phase == .playing ? 1.0 : 0.0)
                        .animation(.easeIn(duration: 0.28), value: phase)
                }

                // Goal burst — one-shot particle blast on goal reach
                if let burst = goalBurst {
                    GoalBurstView(event: burst)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // HUD — just the level label
                hud(safeBottom: geo.safeAreaInsets.bottom)

                // Lives HUD — top-left.  Always visible (including tutorial
                // levels) so the player has a consistent place to check on
                // their marble stockpile.  Failure on tutorial levels still
                // doesn't cost a life — that's handled in handleFell —
                // but the HUD itself is permanent UI furniture.
                livesHUDOverlay(safeTop: geo.safeAreaInsets.top)

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
                if phase == .fell && !showOutOfLives { oopsOverlay }
                if phase == .levelComplete { winOverlay }

                // Out-of-lives overlay — shown when the player tries to play
                // with zero lives.  Sits above the Oops/Win overlays.
                if showOutOfLives { outOfLivesOverlay }

                // Home button — rendered AFTER oops/win overlays so it stays
                // tappable while they're showing.  Hidden during the one-time
                // welcome moment and tutorial reward modal so it doesn't
                // compete for attention with those flows.
                if !showWelcomeMoment && !showTutorialReward {
                    homeButtonOverlay(safeBottom: geo.safeAreaInsets.bottom)
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
        .onAppear  { motion.start(); clock.start(); AudioManager.shared.prepareIfNeeded() }
        .onDisappear { motion.stop();  clock.stop()  }
    }

    // MARK: - Border

    private var screenBorder: some View {
        // RoundedRectangle with cornerRadius pulled from the actual device's
        // display corner radius, so the stroke traces the screen curve exactly.
        RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
            .strokeBorder(borderColor, lineWidth: borderPhase == .normal ? 4 : 5)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.35), value: borderPhase)
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
                    case .evil:  evilPitOverlay
                    case .sky:   skyPitOverlay
                    case .pond:  pondPitOverlay
                    case .space: spacePitOverlay
                    default:     EmptyView()
                    }
                }
            }
            .frame(width: w, height: h)
            .position(x: x, y: y)
        }
    }

    /// Renders coins for this level.  Coins picked up THIS attempt disappear
    /// instantly so the player gets immediate feedback.  Coins already banked
    /// across past attempts render dimmed but visible (signal that this slot
    /// has already been collected).
    private func coinLayer(geo: GeometryProxy) -> some View {
        let banked = gameState.coinsCollected(for: gameState.currentLevel)
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
    /// blade tufts on top of the base fairway green.  Static (no
    /// animation), so Reduce Motion users still get the texture.
    /// Tuft positions come from a deterministic seeded "random" so
    /// they don't shift between frames.
    private var grassFloorOverlay: some View {
        Canvas { ctx, size in
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
                // A tuft = 2-3 thin upward slashes.
                let blades = 2 + Int(rand() * 2)
                for b in 0..<blades {
                    let offsetX = CGFloat(rand() - 0.5) * 6
                    let tilt = CGFloat(rand() - 0.5) * 4
                    var path = Path()
                    path.move(to: CGPoint(x: cx + offsetX, y: cy + 3))
                    path.addLine(to: CGPoint(x: cx + offsetX + tilt, y: cy - 6 + CGFloat(rand()) * 4))
                    ctx.stroke(
                        path,
                        with: .color(b == 0 ? bladeBright : blade),
                        lineWidth: 1.0
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Moon floor overlay (Space Travel bundle) — scatter of craters on
    /// the pale-grey regolith base.  Each crater is a darker disc with a
    /// lighter lower-rim crescent so it reads as a shallow bowl lit from
    /// the upper-left.  Deterministic seeded placement so craters don't
    /// shift between frames.  Static (no animation).
    private var moonFloorOverlay: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(seed: 0x5EED_0C24)
            // ~one crater per 5500 sqpt — sparse so it reads as terrain.
            let craterCount = max(8, Int(size.width * size.height / 5500))
            let floorBase = Color(red: 0.62, green: 0.62, blue: 0.66)
            for _ in 0..<craterCount {
                let cx = CGFloat(rng.nextUnit()) * size.width
                let cy = CGFloat(rng.nextUnit()) * size.height
                let r  = 6 + CGFloat(rng.nextUnit()) * 22
                // Crater bowl — slightly darker than the regolith.
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [
                            floorBase.opacity(0.0),
                            Color(red: 0.42, green: 0.42, blue: 0.46).opacity(0.55),
                        ]),
                        center: CGPoint(x: cx, y: cy),
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
                // Bright lower-right rim crescent (sunlit far wall).
                var rim = Path()
                rim.addArc(center: CGPoint(x: cx, y: cy), radius: r * 0.96,
                           startAngle: .degrees(20), endAngle: .degrees(150), clockwise: false)
                ctx.stroke(rim, with: .color(Color.white.opacity(0.30)), lineWidth: 1.0)
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
                    let flicker = sin(t * 7 + seed * 4) * 0.30
                                + sin(t * 13 + seed * 1.6) * 0.15
                    let flameW = (size.width / CGFloat(flameCount)) * (0.70 + 0.50 * CGFloat(flicker.magnitude))
                    let flameH = size.height * CGFloat(0.55 + 0.25 * sin(t * 4 + seed * 2))
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
            }
        }
    }

    /// Aurora-theme floor shimmer.  Renders a slow drift of soft green/blue/
    /// purple gradient blobs on top of the floor base color.  Drawn at 30Hz
    /// (minimumInterval) to keep CPU cost modest — physics still runs at 60Hz
    /// via the CADisplayLink.
    private var auroraShimmerOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate

                // 4 large soft blobs in the aurora palette
                let blobs: [(Double, Double, Double, Double)] = [
                    (0.0, 0.0, 0.42, 0.08),   // teal-green
                    (1.7, 2.4, 0.62, 0.10),   // blue
                    (3.5, 1.1, 0.75, 0.07),   // purple
                    (5.2, 4.0, 0.50, 0.09),   // cyan
                ]
                let r = size.width * 0.85
                for (xSeed, ySeed, hueSeed, speed) in blobs {
                    let bx = size.width  * CGFloat(0.5 + 0.55 * sin(t * speed       + xSeed))
                    let by = size.height * CGFloat(0.5 + 0.45 * sin(t * speed * 1.3 + ySeed))
                    let hue = (hueSeed + t * 0.012).truncatingRemainder(dividingBy: 1.0)
                    let color = Color(hue: hue, saturation: 0.55, brightness: 0.92)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: bx - r, y: by - r,
                                                width: r * 2, height: r * 2)),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(0.32), .clear]),
                            center: CGPoint(x: bx, y: by),
                            startRadius: 0, endRadius: r
                        )
                    )
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
        Canvas { ctx, _ in
            let n = trailPoints.count
            guard n >= 2 else { return }
            let isRainbow = gameState.equippedTrail == .rainbow
            let isAir     = gameState.equippedTrail == .air
            let isRaybeam = gameState.equippedTrail == .raybeam
            // Air trail — overall opacity decays as the trail grows
            // longer, giving the "moving air" effect Mac specified.
            // Cap at the base trail length (90); above that the air
            // is already ~vanished.
            let airDecay: Double = isAir
                ? max(0.10, 1.0 - Double(n) / Double(trailMaxLength) * 0.85)
                : 1.0
            for i in 1..<n {
                let prev = trailPoints[i - 1]
                let curr = trailPoints[i]
                // Fade from 0.10 (tail) → 1.0 (head)
                let age = Double(i) / Double(n - 1)
                let opacity = (0.10 + 0.90 * age) * airDecay
                var path = Path()
                path.move(to: prev)
                path.addLine(to: curr)
                var rainbowHue: Double {
                    var h = (trailHueOffset + Double(i) * trailHueStep)
                        .truncatingRemainder(dividingBy: 1.0)
                    if h < 0 { h += 1.0 }
                    return h
                }
                let segmentColor: Color = isRainbow
                    ? Color(hue: rainbowHue,
                            saturation: 1.0,
                            brightness: 1.0)
                    : gameState.equippedTrail.color
                if isRaybeam {
                    // Laser look — a wide soft glow under a bright thin
                    // core, both fading along the trail.
                    ctx.stroke(
                        path,
                        with: .color(Color(red: 0.20, green: 1.00, blue: 0.70).opacity(opacity * 0.35)),
                        style: StrokeStyle(lineWidth: 8.0, lineCap: .round, lineJoin: .round)
                    )
                    ctx.stroke(
                        path,
                        with: .color(Color(red: 0.85, green: 1.00, blue: 0.92).opacity(opacity)),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                    )
                } else {
                    ctx.stroke(
                        path,
                        with: .color(segmentColor.opacity(opacity)),
                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                    )
                }
            }
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
                        let speed = dir * (speedBase + Double(i % 5) * 0.10)
                        let angle = phase * 2 * .pi + t * speed

                        let breathe = sin(t * 1.5 + phase * 5.8 + Double(ringIdx) * 1.1) * 0.10
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

    /// In-game marble.  Standard / Epic ball skins use the shared
    /// radial-gradient renderer; the Snowglobe (Legendary) marble
    /// swaps in a bespoke animated Canvas with snowflakes drifting
    /// inside a frosted-glass dome.
    @ViewBuilder
    private var marbleView: some View {
        switch gameState.activeSkin {
        case .snowglobe:
            snowglobeMarble
                .frame(width: effectiveBallRadius * 2, height: effectiveBallRadius * 2)
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 5)
        case .golfBall:
            golfBallMarble
                .frame(width: effectiveBallRadius * 2, height: effectiveBallRadius * 2)
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 5)
        case .soccer:
            // White body + black pentagons.  Clipped to a circle so the
            // ring pentagons run off the silhouette like a real ball.
            soccerMarble
                .frame(width: effectiveBallRadius * 2, height: effectiveBallRadius * 2)
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.30), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 5)
        case .saturn:
            // Bespoke ringed renderer — the gas-giant body plus the
            // iconic tilted ring system.  The rings extend beyond the
            // body so this case is NOT clipped to a circle.
            saturnMarble
                .frame(width: effectiveBallRadius * 2, height: effectiveBallRadius * 2)
                .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 5)
        case .ufo:
            // Animated flying saucer — metallic disc, glowing green
            // dome, rotating belly lights.  Not clipped (the saucer is
            // wider than tall and fits inside the square frame).
            ufoMarble
                .frame(width: effectiveBallRadius * 2, height: effectiveBallRadius * 2)
                .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 5)
        default:
            Circle()
                .fill(gameState.activeSkin.gradient(endRadius: effectiveBallRadius * 1.4))
                .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 5)
        }
    }

    /// Saturn — pale-gold body with a tilted elliptical ring system.
    /// Drawn in a Canvas so the rings can render in front of the lower
    /// half of the planet and behind the upper half, selling the 3D
    /// tilt.  Static (no animation) — reads as a ringed planet at any
    /// size, including Pluto-scale would-be use (Saturn is full-size).
    private var saturnMarble: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let bodyR = min(w, h) * 0.34            // planet body radius
            let ringRx = min(w, h) * 0.52           // ring outer x-radius
            let ringRy = ringRx * 0.34              // squashed → tilt

            // Ring colours (front + back share the palette; the back arc
            // is dimmed so the body reads as occluding it).
            let ringMain  = Color(red: 0.86, green: 0.74, blue: 0.50)
            let ringInner = Color(red: 0.62, green: 0.50, blue: 0.30)

            // Helper to stroke a tilted ellipse arc.
            func ringPath(scale: CGFloat) -> Path {
                let rx = ringRx * scale
                let ry = ringRy * scale
                return Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry,
                                              width: rx * 2, height: ry * 2))
            }

            // 1. BACK half of the rings (behind the planet) — drawn
            //    first, dimmer.  We draw the full ellipse then let the
            //    body paint over its front/lower portion.
            ctx.stroke(ringPath(scale: 1.0), with: .color(ringMain.opacity(0.55)), lineWidth: bodyR * 0.30)
            ctx.stroke(ringPath(scale: 0.74), with: .color(ringInner.opacity(0.50)), lineWidth: bodyR * 0.14)

            // 2. Planet body — radial gradient marble.
            let bodyRect = CGRect(x: cx - bodyR, y: cy - bodyR,
                                  width: bodyR * 2, height: bodyR * 2)
            let grad = Gradient(colors: [
                Color(red: 1.00, green: 0.96, blue: 0.80),
                Color(red: 0.92, green: 0.80, blue: 0.52),
                Color(red: 0.66, green: 0.50, blue: 0.26),
                Color(red: 0.34, green: 0.24, blue: 0.10),
            ])
            ctx.fill(Path(ellipseIn: bodyRect),
                     with: .radialGradient(grad,
                                           center: CGPoint(x: cx - bodyR * 0.3, y: cy - bodyR * 0.3),
                                           startRadius: 0, endRadius: bodyR * 1.4))
            ctx.stroke(Path(ellipseIn: bodyRect), with: .color(.black.opacity(0.30)), lineWidth: 0.5)

            // 3. FRONT half of the rings — clip to the lower band so only
            //    the part crossing in front of the planet's lower half is
            //    painted brightly on top.
            var front = ctx
            front.clip(to: Path(CGRect(x: 0, y: cy, width: w, height: h - cy)))
            front.stroke(ringPath(scale: 1.0), with: .color(ringMain), lineWidth: bodyR * 0.30)
            front.stroke(ringPath(scale: 0.74), with: .color(ringInner), lineWidth: bodyR * 0.14)
        }
    }

    /// UFO marble (Space Travel bundle) — a metallic flying saucer with
    /// a glowing green glass dome and a row of belly lights that pulse
    /// in sequence (reads as "rotating" running lights).  Animated via
    /// TimelineView; under Reduce Motion the lights hold steady (we
    /// still draw them, just without the time-driven pulse).
    private var ufoMarble: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let w  = size.width
                let h  = size.height
                let cx = w / 2
                let cy = h / 2

                // Saucer hull — a squashed ellipse occupying the lower
                // ~55% of the frame.  Metallic vertical gradient.
                let hullW = w * 0.96
                let hullH = h * 0.42
                let hullRect = CGRect(x: cx - hullW / 2, y: cy - hullH * 0.10,
                                      width: hullW, height: hullH)
                ctx.fill(
                    Path(ellipseIn: hullRect),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 0.88, green: 0.92, blue: 0.96), location: 0.00),
                            .init(color: Color(red: 0.60, green: 0.66, blue: 0.74), location: 0.45),
                            .init(color: Color(red: 0.30, green: 0.36, blue: 0.44), location: 0.85),
                            .init(color: Color(red: 0.14, green: 0.18, blue: 0.24), location: 1.00),
                        ]),
                        startPoint: CGPoint(x: cx, y: hullRect.minY),
                        endPoint:   CGPoint(x: cx, y: hullRect.maxY)
                    )
                )
                ctx.stroke(Path(ellipseIn: hullRect),
                           with: .color(.black.opacity(0.30)), lineWidth: 0.6)

                // Glass dome — a green-tinted half-ellipse on top of the
                // hull, with a soft glow.
                let domeW = w * 0.50
                let domeH = h * 0.46
                let domeRect = CGRect(x: cx - domeW / 2, y: cy - hullH * 0.10 - domeH * 0.72,
                                      width: domeW, height: domeH)
                ctx.fill(
                    Path(ellipseIn: domeRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 0.70, green: 1.00, blue: 0.80),
                            Color(red: 0.20, green: 0.85, blue: 0.55),
                            Color(red: 0.05, green: 0.45, blue: 0.30),
                        ]),
                        center: CGPoint(x: domeRect.midX - domeW * 0.18,
                                        y: domeRect.midY - domeH * 0.18),
                        startRadius: 0,
                        endRadius:   domeW * 0.75
                    )
                )
                ctx.stroke(Path(ellipseIn: domeRect),
                           with: .color(.white.opacity(0.35)), lineWidth: 0.5)

                // Belly lights — a horizontal row of small dots across
                // the lower hull.  Each pulses on a phase offset so the
                // row appears to chase / rotate.
                let lightCount = 5
                let lightY = cy + hullH * 0.30
                let lightR = max(1.2, w * 0.05)
                for i in 0..<lightCount {
                    let frac = (Double(i) + 0.5) / Double(lightCount)
                    let lx = hullRect.minX + hullW * 0.14 + (hullW * 0.72) * CGFloat(frac)
                    let pulse = 0.40 + 0.60 * (0.5 + 0.5 * sin(t * 6 - Double(i) * 1.1))
                    let lightColor = Color(red: 1.00, green: 0.92, blue: 0.45)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: lx - lightR, y: lightY - lightR,
                                               width: lightR * 2, height: lightR * 2)),
                        with: .color(lightColor.opacity(pulse))
                    )
                }
            }
        }
    }

    /// Golf-ball marble — white sphere with the classic dimple
    /// pattern.  Dimples are deterministic (seeded RNG) so they
    /// don't dance frame-to-frame; the ball itself doesn't rotate
    /// visually (we don't track an angle), so a fixed pattern reads
    /// as the canonical golf ball texture.
    private var golfBallMarble: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // Base white sphere — radial gradient for 3D shading.
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color.white,                                  location: 0.00),
                        .init(color: Color(red: 0.94, green: 0.94, blue: 0.92),    location: 0.55),
                        .init(color: Color(red: 0.70, green: 0.70, blue: 0.66),    location: 0.95),
                        .init(color: Color(red: 0.42, green: 0.42, blue: 0.40),    location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.32, y: h * 0.32),
                    startRadius: 0,
                    endRadius:   r * 1.30
                )
            )

            // Dimple pattern — hex-ish grid, clipped to the sphere
            // silhouette.  Each dimple is a tiny dark spot with a
            // light highlight to suggest a concavity.
            let dimpleR = r * 0.075
            let spacing = dimpleR * 2.4
            // Offset alternating rows for a honeycomb feel.
            let rowCount = Int(ceil(h / spacing)) + 1
            for row in 0..<rowCount {
                let isOddRow = row % 2 == 1
                let y = CGFloat(row) * spacing + (isOddRow ? spacing / 2 : 0) - spacing / 2
                let xOffset: CGFloat = isOddRow ? spacing / 2 : 0
                let colCount = Int(ceil(w / spacing)) + 1
                for col in 0..<colCount {
                    let x = CGFloat(col) * spacing + xOffset - spacing / 2
                    // Clip to the sphere (centre dist + small margin).
                    let dx = x - cx
                    let dy = y - cy
                    let dist = sqrt(dx * dx + dy * dy)
                    if dist > r * 0.93 { continue }

                    // Inner shadow makes the dimple read as concave.
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - dimpleR, y: y - dimpleR,
                                               width: dimpleR * 2, height: dimpleR * 2)),
                        with: .color(Color.black.opacity(0.10))
                    )
                    // Tiny lower-right rim highlight.
                    let rimR = dimpleR * 0.55
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x + dimpleR * 0.15, y: y + dimpleR * 0.15,
                                               width: rimR * 2, height: rimR * 2)),
                        with: .color(Color.white.opacity(0.55))
                    )
                }
            }

            // Final highlight crescent — sells the gloss.
            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.10, y: h * 0.08,
                                       width: w * 0.32, height: h * 0.26)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.50), .clear]),
                    center: CGPoint(x: w * 0.25, y: h * 0.20),
                    startRadius: 0,
                    endRadius:   r * 0.40
                )
            )
        }
    }

    /// Soccer-ball marble — the classic Telstar pattern: a white sphere
    /// with one central black pentagon ringed by five more.  Static (no
    /// rotation tracked).  The ring pentagons sit past the body radius so
    /// the circle clip in `marbleView` trims them, selling the wrap.
    private var soccerMarble: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // Base white sphere — radial gradient for 3D shading.
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color.white,                                  location: 0.00),
                        .init(color: Color(red: 0.95, green: 0.95, blue: 0.95),    location: 0.55),
                        .init(color: Color(red: 0.72, green: 0.72, blue: 0.72),    location: 0.95),
                        .init(color: Color(red: 0.42, green: 0.42, blue: 0.42),    location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.32, y: h * 0.32),
                    startRadius: 0,
                    endRadius:   r * 1.30
                )
            )

            // Regular-pentagon path centred at `c`, vertex radius `pr`,
            // rotated by `rot` radians (0 → one vertex points straight up).
            func pentagon(center c: CGPoint, radius pr: CGFloat, rotation rot: CGFloat) -> Path {
                var p = Path()
                for i in 0..<5 {
                    let a = rot - .pi / 2 + CGFloat(i) * (2 * .pi / 5)
                    let pt = CGPoint(x: c.x + pr * cos(a), y: c.y + pr * sin(a))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
                return p
            }

            let black  = Color(red: 0.09, green: 0.09, blue: 0.11)
            let pentR  = r * 0.30

            // Central pentagon (flat top — one vertex pointing down).
            ctx.fill(pentagon(center: CGPoint(x: cx, y: cy), radius: pentR, rotation: .pi),
                     with: .color(black))

            // Five ring pentagons, each pointing outward from centre and
            // sitting partway off the body so the clip trims them.
            let ringDist = r * 0.74
            for i in 0..<5 {
                let a  = -.pi / 2 + CGFloat(i) * (2 * .pi / 5)
                let pc = CGPoint(x: cx + ringDist * cos(a), y: cy + ringDist * sin(a))
                ctx.fill(pentagon(center: pc, radius: pentR * 0.95, rotation: a + .pi / 2),
                         with: .color(black))
            }

            // Gloss highlight crescent — sells the gloss.
            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.10, y: h * 0.08,
                                       width: w * 0.32, height: h * 0.26)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.45), .clear]),
                    center: CGPoint(x: w * 0.25, y: h * 0.20),
                    startRadius: 0,
                    endRadius:   r * 0.40
                )
            )
        }
    }

    /// Snowglobe marble — a frosted-glass sphere with ~14 white
    /// snowflakes that drift downward (and gently swirl left/right
    /// via a sine offset) inside the dome.  Pure Canvas + TimelineView
    /// so it stays cheap to render at 60fps.
    private var snowglobeMarble: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let w = size.width
                let h = size.height
                let cx = w / 2
                let cy = h / 2
                let r  = min(w, h) / 2

                // Frosted-glass background — radial gradient white →
                // pale blue → deeper blue, anchored to the upper-left
                // so the orb reads as a 3D sphere.
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 0.96, green: 0.98, blue: 1.00), location: 0.00),
                            .init(color: Color(red: 0.78, green: 0.88, blue: 0.98), location: 0.55),
                            .init(color: Color(red: 0.18, green: 0.30, blue: 0.50), location: 1.00),
                        ]),
                        center: CGPoint(x: w * 0.32, y: h * 0.32),
                        startRadius: 0,
                        endRadius:   r * 1.40
                    )
                )

                // Snowflakes — staggered phases so they don't fall in
                // unison.  Each has a slow sine x-drift for "swirling".
                let flakeCount = 14
                for i in 0..<flakeCount {
                    let seed   = Double(i) * 0.713 + 0.21
                    // Fall fraction: 0…1 looping; offset by seed.
                    let fall   = (t * 0.22 + seed).truncatingRemainder(dividingBy: 1.0)
                    // x oscillates as sine for swirl.
                    let xOsc   = sin(t * 0.65 + seed * 5.3)
                    let xN     = 0.18 + 0.64 * (0.5 + 0.5 * xOsc)
                    let yN     = 0.10 + 0.80 * fall
                    let px     = w * CGFloat(xN)
                    let py     = h * CGFloat(yN)

                    // Clip the snowflake to the sphere — discard any
                    // whose centre lies outside the inscribed circle.
                    let dx = px - cx
                    let dy = py - cy
                    let rr = sqrt(dx * dx + dy * dy)
                    if rr > r * 0.90 { continue }

                    // Twinkle alpha so flakes shimmer as they drift.
                    let twinkle = 0.65 + 0.35 * sin(t * 1.4 + seed * 7)
                    let flakeR  = r * (0.045 + Double(i % 3) * 0.012)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: px - flakeR, y: py - flakeR,
                                               width: flakeR * 2, height: flakeR * 2)),
                        with: .color(Color.white.opacity(twinkle))
                    )
                }

                // Top-left highlight — sells the glass sphere look.
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.10, y: h * 0.08,
                                           width: w * 0.34, height: h * 0.28)),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.45), .clear]),
                        center: CGPoint(x: w * 0.27, y: h * 0.22),
                        startRadius: 0,
                        endRadius:   r * 0.45
                    )
                )
            }
        }
    }

    /// Bottom HUD — just the LEVEL X label.  The home button is rendered
    /// separately by `homeButtonOverlay` so it can sit ABOVE the Oops / Win
    /// overlays and remain tappable while those are showing.
    private func hud(safeBottom: CGFloat) -> some View {
        VStack {
            Spacer()
            Text("LEVEL \(gameState.currentLevel)")
                .font(.system(size: 12, weight: .ultraLight, design: .monospaced))
                .kerning(4)
                .foregroundStyle(Color(white: 0.40))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.bottom, max(safeBottom, 12) + 8)
        }
    }

    /// Floating home button — always tappable, even when Oops / Win overlays
    /// are showing.  Rendered in its own layer so it sits on top.  Hidden
    /// during the one-time "Roll Along friend!" welcome moment so it doesn't
    /// compete for the player's attention.
    private func homeButtonOverlay(safeBottom: CGFloat) -> some View {
        VStack {
            Spacer()
            HStack {
                Button { nav.goHome() } label: {
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
                .accessibilityHint("Returns to the main menu. No level progress is lost.")
                Spacer()
            }
            .padding(.leading, 22)
            .padding(.bottom, max(safeBottom, 12) + 8)
        }
    }

    // MARK: - Lives HUD (top-left)

    /// 6-ball lives indicator with regen countdown.  Wrapped in TimelineView
    /// so the countdown ticks every second and `displayedLives` stays fresh
    /// without us having to manually call `commitRegen` on a timer.
    private func livesHUDOverlay(safeTop: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            // Per the agreed spec:
            //   • Always render 6 marbles.
            //   • Filled red marbles = your active lives (clamped to 6 max for
            //     the bar).
            //   • Stockpiled lives above 6 show as "+N" to the right of the
            //     6th marble.
            //   • Unlimited-lives subscribers get 6 gold marbles + an
            //     infinity symbol instead of "+N".
            let unlimited     = gameState.unlimitedLives
            let display       = gameState.displayedLives   // may be > 6 with stockpile
            let filledMarbles = unlimited ? GameState.livesMax : min(display, GameState.livesMax)
            let stockpile     = unlimited ? 0 : max(0, display - GameState.livesMax)

            HStack(spacing: 5) {
                ForEach(0..<GameState.livesMax, id: \.self) { i in
                    lifeIcon(filled: i < filledMarbles, gold: unlimited)
                }
                // Trailing indicator — either the stockpile counter or
                // the infinity glyph for unlimited subscribers.
                if unlimited {
                    Image(systemName: "infinity")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.86, blue: 0.36),
                                    Color(red: 0.93, green: 0.65, blue: 0.10),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .padding(.leading, 2)
                } else if stockpile > 0 {
                    Text("+\(stockpile)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.leading, 2)
                }
            }
            .padding(.leading, 18)
            // Drop well below the system status bar / Dynamic Island.
            // safeTop alone wasn't enough on test runs — the marbles
            // landed under the clock glyphs.  Minimum 50pt ensures the
            // row clears a standard status bar (~20pt) plus the Dynamic
            // Island visual (~37pt) regardless of what safeAreaInsets
            // reports inside this GeometryReader.
            //
            // Per-spec the regen countdown text is no longer shown here;
            // on the home screen it's visualised by the partial-fill
            // marble instead.
            .padding(.top, max(safeTop + 4, 50))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(livesAccessibilityLabel)
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
                    .fill(gold ? Self.goldLifeGradient : Self.redLifeGradient)
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
                    .fill(gold ? Self.goldLifeGradient : Self.redLifeGradient)
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
    private static let goldLifeGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.86, blue: 0.36),
            Color(red: 0.93, green: 0.65, blue: 0.10),
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
                    .foregroundStyle(Self.goldLifeGradient)
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

    private var oopsOverlay: some View {
        ZStack {
            Color.black.opacity(0.52).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Oops!")
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Tap to try again")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(white: 0.78))
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

                // Stars
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

                // Time + personal best
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

                // Actions
                VStack(spacing: 12) {
                    Button { advanceFromLevelClear() } label: {
                        Text("Next Level")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color(red: 0.20, green: 0.78, blue: 0.38))
                            )
                    }
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
                .padding(.horizontal, 32)
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    // MARK: - Tutorial reward modal (one-time, after first L10 clear)
    //
    // Awarded after the tutorial — player picks ONE .standard-tier item
    // from ANY category to keep for free.  Selecting an item in any row
    // replaces any prior selection (across all categories).  The picked
    // item is granted + equipped on Claim.

    private var tutorialRewardOverlay: some View {
        // Selected-item derivations — only one of these is non-nil at a
        // time, mirroring the single-pick rule.
        let selBall:  BallSkin?    = { if case let .ball(v)  = tutorialPick { return v } else { return nil } }()
        let selGoal:  GoalSkin?    = { if case let .goal(v)  = tutorialPick { return v } else { return nil } }()
        let selTrail: TrailColor?  = { if case let .trail(v) = tutorialPick { return v } else { return nil } }()
        let selFloor: Floor?       = { if case let .floor(v) = tutorialPick { return v } else { return nil } }()
        let selPit:   Pit?         = { if case let .pit(v)   = tutorialPick { return v } else { return nil } }()
        let selMusic: MusicTrack?  = { if case let .music(v) = tutorialPick { return v } else { return nil } }()

        let hasPick = tutorialPick != nil

        return ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 0) {
                // Title
                VStack(spacing: 6) {
                    Text("Tutorial Complete!")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Pick one free cosmetic — from any category.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.70))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        rewardRow(label: "Ball",
                                  items: BallSkin.allCases.filter { $0.tier == .standard },
                                  selected: selBall,
                                  onPick: { tutorialPick = .ball($0) })
                        rewardRow(label: "Goal",
                                  items: GoalSkin.allCases.filter { $0.tier == .standard },
                                  selected: selGoal,
                                  onPick: { tutorialPick = .goal($0) })
                        rewardRow(label: "Trail",
                                  items: TrailColor.allCases.filter { $0.tier == .standard },
                                  selected: selTrail,
                                  onPick: { tutorialPick = .trail($0) })
                        rewardRow(label: "Floor",
                                  items: Floor.allCases.filter { $0.tier == .standard },
                                  selected: selFloor,
                                  onPick: { tutorialPick = .floor($0) })
                        rewardRow(label: "Pit",
                                  items: Pit.allCases.filter { $0.tier == .standard },
                                  selected: selPit,
                                  onPick: { tutorialPick = .pit($0) })
                        rewardRow(label: "Music",
                                  items: MusicTrack.allCases.filter { $0.tier == .standard },
                                  selected: selMusic,
                                  onPick: { tutorialPick = .music($0) })
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }

                Button {
                    claimTutorialReward()
                } label: {
                    Text(hasPick ? "Claim cosmetic" : "Pick a cosmetic")
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

    /// One row of pick-able cosmetic items for the tutorial reward modal.
    private func rewardRow<Item: CosmeticItem>(
        label: String,
        items: [Item],
        selected: Item?,
        onPick: @escaping (Item) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(1.5)
                .foregroundStyle(Color(white: 0.55))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items, id: \.id) { item in
                        let isSelected = selected.map { $0.id == item.id } ?? false
                        Button {
                            onPick(item)
                        } label: {
                            VStack(spacing: 6) {
                                rewardPreview(for: item)
                                    .frame(width: 56, height: 56)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(white: 0.10))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isSelected ? Color.white : Color.clear,
                                                    lineWidth: 2.0)
                                    )
                                Text(item.displayName)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : Color(white: 0.70))
                                    .lineLimit(1)
                            }
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(isSelected ? Color(white: 0.18) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Compact previews mirror the shop's category-specific renderings.
    @ViewBuilder
    private func rewardPreview<Item: CosmeticItem>(for item: Item) -> some View {
        switch item {
        case let s as BallSkin:
            Circle()
                .fill(s.gradient(endRadius: 30))
                .overlay(Circle().stroke(Color.black.opacity(0.30), lineWidth: 0.5))
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
    private func claimTutorialReward() {
        guard let pick = tutorialPick else { return }

        let (category, itemRaw): (String, String)
        switch pick {
        case .ball(let b):
            gameState.grant(b)
            gameState.activeSkin = b
            (category, itemRaw) = ("ball", b.rawValue)
        case .goal(let g):
            gameState.grant(g)
            gameState.equippedGoal = g
            (category, itemRaw) = ("goal", g.rawValue)
        case .trail(let t):
            gameState.grant(t)
            gameState.equippedTrail = t
            (category, itemRaw) = ("trail", t.rawValue)
        case .floor(let f):
            gameState.grant(f)
            gameState.equippedFloor = f
            (category, itemRaw) = ("floor", f.rawValue)
        case .pit(let p):
            gameState.grant(p)
            gameState.equippedPit = p
            (category, itemRaw) = ("pit", p.rawValue)
        case .music(let m):
            gameState.grant(m)
            gameState.equippedMusic = m
            (category, itemRaw) = ("music", m.rawValue)
        }

        gameState.seenTutorialReward = true
        AnalyticsClient.shared.track(
            "tutorial_reward_claimed",
            properties: [
                "category": .string(category),
                "item":     .string(itemRaw),
            ]
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
        if !gameState.isTutorialLevel(gameState.currentLevel),
           !gameState.unlimitedLives,
           gameState.displayedLives <= 0 {
            withAnimation(.easeInOut(duration: 0.28)) { showOutOfLives = true }
            return
        }
        showOutOfLives = false

        ball = Ball(position: startPoint(in: size), velocity: .zero)
        goalBurst = nil  // clear any leftover burst from previous level
        coinsPickedThisAttempt = []
        trailPoints.removeAll(keepingCapacity: true)
        trailHueOffset = 0.0
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
        let isFirstL1Run = gameState.currentLevel == 1
                        && gameState.time(for: 1) == nil
        if isFirstL1Run {
            tutorialPhase  = .introHint
            spawnLockUntil = .distantFuture
            gameState.clearCollectedCoins(for: 1)
            tutorialCoinBonus = 0
        } else {
            tutorialPhase  = .notTutorial
            spawnLockUntil = .now.addingTimeInterval(spawnLockDuration)
            tutorialCoinBonus = 0
        }
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }

        AnalyticsClient.shared.track(
            "level_attempt",
            properties: [
                "tier":        .string(layout.tier.rawValue),
                "is_tutorial": .bool(gameState.isTutorialLevel(gameState.currentLevel)),
            ],
            level: gameState.currentLevel
        )
    }

    private func tick(geoSize: CGSize) {
        guard phase == .playing, var b = ball else { return }

        // Spawn-lock: physics is paused while the player gets oriented.
        // When the lock expires naturally we arm levelStartTime here (so
        // star-time scoring starts the moment the player could actually
        // input).  Tap-to-start handles the early-release path.
        if let until = spawnLockUntil {
            if Date.now < until { return }
            spawnLockUntil = nil
            levelStartTime = .now
        }

        let dt = CGFloat(tickRate)

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

        // Graphite trail (Paper world) — accumulate position points so we
        // can render the streak behind the ball.  Skip if too close to the
        // previous point (the ball is nearly stationary).
        if gameState.equippedTrail != .none {
            if let last = trailPoints.last {
                if hypot(b.position.x - last.x, b.position.y - last.y) > trailMinStep {
                    trailPoints.append(b.position)
                }
            } else {
                trailPoints.append(b.position)
            }
            let cap = effectiveTrailMaxLength
            if trailPoints.count > cap {
                let removed = trailPoints.count - cap
                trailPoints.removeFirst(removed)
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

        // Coin pickup — collect any not yet picked this attempt + not banked.
        // Multiple coins can be collected per run.  Driven by
        // effectiveLayout so the L1 tutorial doesn't allow pickups while
        // coins aren't yet "revealed".
        let banked = gameState.coinsCollected(for: gameState.currentLevel)
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
        let goalLive = tutorialPhase == .playing || tutorialPhase == .notTutorial
        let gp = goalPoint(in: geoSize)
        if goalLive,
           hypot(b.position.x - gp.x, b.position.y - gp.y) < effectiveBallRadius * 1.7 {
            ball = b
            handleLevelClear(at: gp)
            return
        }

        // Hole check
        if isInHole(position: b.position, size: geoSize) || b.position.x < -r || b.position.x > geoSize.width + r {
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
            fireFell()
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
            // L1 first-time-play tutorial: a fall during `.playing`
            // means the player has met the hole concept and bumped
            // into it.  Per design, drop them out of the phased
            // tutorial entirely (no more hint pills), reset the ball
            // to start, and engage the standard spawn-lock + "Tap to
            // start" pill — no Oops screen.  Coins stay banked, hole
            // stays present, no life is consumed (L1 is a tutorial
            // level so consumeLife is already a no-op).
            if gameState.currentLevel == 1 && tutorialPhase != .notTutorial {
                tutorialPhase = .notTutorial
                ball = Ball(position: startPoint(in: geoSize), velocity: .zero)
                levelStartTime = nil
                spawnLockUntil = .now.addingTimeInterval(spawnLockDuration)
                // Reset coinsPickedThisAttempt so the banked coins
                // become visible again as dimmed "already collected"
                // indicators on the new attempt — matches the look of
                // any normal replay of a level you've previously
                // banked coins on.
                coinsPickedThisAttempt = []
                return
            }
            // If that was the player's last life, skip the Oops screen
            // entirely and jump straight to Out of Lives.  Otherwise the
            // overlay-stack hierarchy (Oops drawn under Out of Lives)
            // leaves an "Oops!" ghost bleeding through behind the modal.
            // Tutorial levels (where lives aren't consumed) never trigger
            // this branch because displayedLives stays > 0 for them.
            if !gameState.isTutorialLevel(gameState.currentLevel),
               !gameState.unlimitedLives,
               gameState.displayedLives <= 0 {
                withAnimation(.easeInOut(duration: 0.28)) { showOutOfLives = true }
            } else {
                withAnimation(.easeIn(duration: 0.22)) { phase = .fell }
            }
            return
        }

        ball = b
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

        // Lives consumption — tutorial (L1-10) is exempt.
        if !gameState.isTutorialLevel(gameState.currentLevel) {
            gameState.consumeLife()
        }
    }

    private func fireCoinPickup() {
        if gameState.hapticsEnabled { Haptics.soft() }
        AudioManager.shared.playCoin(enabled: gameState.soundEnabled)
    }

    // MARK: - Level clear handler

    /// Called when the ball reaches the goal.  Records the result, computes
    /// stars, awards currency-coins for newly-earned achievements, then
    /// transitions to .levelComplete.
    private func handleLevelClear(at center: CGPoint) {
        fireGoalReached(at: center)

        let elapsed = levelStartTime.map { Date.now.timeIntervalSince($0) } ?? 0
        let stars   = computeStars(elapsed: elapsed)
        let level   = gameState.currentLevel
        let prevStars = gameState.stars(for: level)

        // Currency-coin reward.  Two stackable sources:
        //
        //   1. Flat per-clear bonus (`coinPerClear`) — only on the FIRST
        //      time the level is cleared.  We detect first clear by the
        //      absence of a recorded best-time; `recordResult` (called
        //      below) is what sets bestTime, so we can safely read it
        //      here to decide.
        //
        //   2. Per-pickup (`coinPerPickup`) for each currency-coin grabbed
        //      this run.  `coinsPickedThisAttempt` is already filtered
        //      to first-time pickups at collection time.
        //
        // A perfect first clear awards coinPerClear + 3.  Replays of an
        // already-cleared level award only the value of any newly-banked
        // pickup coins (typically 0 since they're sticky).
        let newStars     = max(0, stars - prevStars)
        let isFirstClear = gameState.time(for: level) == nil
        // L1 tutorial may have already banked + paid out the three
        // coins at the Phase-2→3 transition.  Filter those out so the
        // player isn't rewarded twice for the same pickups.
        let alreadyBanked = gameState.coinsCollected(for: level)
        let newCoinsThisRun = coinsPickedThisAttempt.subtracting(alreadyBanked)
        // `coinReward` is the amount we add to the balance HERE — the
        // tutorial-bank moment already credited its own portion.
        let coinReward = (isFirstClear ? GameState.coinPerClear : 0)
                       + newCoinsThisRun.count * GameState.coinPerPickup
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
                    let hue   = (phase + Double(t) * 0.4).truncatingRemainder(dividingBy: 1.0)
                    let color = Color(hue: hue, saturation: 1.0, brightness: 1.0)

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

            // INNER RECESSED RING — the most "minted" cue.  A second
            // ellipse drawn slightly smaller with the deeper gold gradient,
            // outlined in dark to read as an etched border.
            Ellipse()
                .fill(Self.goldenFaceDeep)
                .scaleEffect(0.78)
                .overlay(
                    Ellipse()
                        .stroke(Color.black.opacity(0.38), lineWidth: 0.9)
                        .scaleEffect(0.78)
                )

            // Centred paw-print mint mark — gives the coin its unique
            // Roll Along identity (stars belong to skill/speed awards,
            // not currency).  Same silhouette as the menu CoinIcon.
            CatPawPrint()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.34, blue: 0.04),
                            Color(red: 0.30, green: 0.18, blue: 0.02),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: size * 0.55, height: size * 0.55)
                // A tiny white highlight on the upper-left edge sells
                // the embossed, raised feel — fades as the coin spins
                // edge-on.
                .overlay(
                    CatPawPrint()
                        .stroke(Color.white.opacity(0.35 * spinRaw),
                                lineWidth: 0.5)
                        .frame(width: size * 0.55, height: size * 0.55)
                        .offset(x: -0.5, y: -0.5)
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
// CatPawPrint — stylised paw silhouette used as the mint mark on every
// Roll Along coin (both the in-game spinning coin and the static menu
// coin icon).  Built from five overlapping ellipses inside a Shape so
// the path is a single fillable region with no internal seams:
//
//   • 1 main pad — wide ellipse at the bottom-centre
//   • 4 toe beans — smaller ellipses fanned across the top, outer
//     toes slightly lower than inner toes (mimics a real paw print)
//
// Star symbolism is reserved for level-completion stars (speed/skill
// awards) — keeping that meaning distinct from the coin currency is
// why we mint the coin with a paw instead.
// ---------------------------------------------------------------------------
struct CatPawPrint: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w  = rect.width
        let h  = rect.height
        let cx = rect.midX

        // Main pad — rounded shape occupying the lower band.  Slightly
        // wider than tall to read as the heel pad rather than another toe.
        let padW = w * 0.62
        let padH = h * 0.46
        path.addEllipse(in: CGRect(
            x:      cx - padW / 2,
            y:      rect.minY + h * 0.46,
            width:  padW,
            height: padH
        ))

        // 4 toe beans across the top.  Outer toes are wider apart and
        // sit slightly lower; inner toes are closer together and sit
        // higher, giving the silhouette a natural fan.
        let toeW: CGFloat = w * 0.22
        let toeH: CGFloat = h * 0.26
        let toes: [CGPoint] = [
            CGPoint(x: cx - w * 0.30, y: rect.minY + h * 0.32),  // outer left
            CGPoint(x: cx - w * 0.10, y: rect.minY + h * 0.14),  // inner left
            CGPoint(x: cx + w * 0.10, y: rect.minY + h * 0.14),  // inner right
            CGPoint(x: cx + w * 0.30, y: rect.minY + h * 0.32),  // outer right
        ]
        for t in toes {
            path.addEllipse(in: CGRect(
                x:      t.x - toeW / 2,
                y:      t.y - toeH / 2,
                width:  toeW,
                height: toeH
            ))
        }
        return path
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
//   • Outer face gradient (bright top → deep amber bottom)
//   • Dark outline stroke
//   • Recessed inner ring — deeper gold w/ etched dark outline, sells
//     the "minted" feel even at small sizes
//   • CatPawPrint mark — dark embossed silhouette centred
//   • Upper-left highlight crescent — catches the light
//   • Subtle drop shadow
// ---------------------------------------------------------------------------
struct CoinIcon: View {
    let size: CGFloat

    init(size: CGFloat = 18) { self.size = size }

    var body: some View {
        ZStack {
            // Base face + dark outline
            Circle()
                .fill(Self.goldenFace)
                .overlay(
                    Circle().stroke(Color.black.opacity(0.45),
                                    lineWidth: max(0.5, size * 0.04))
                )

            // Recessed inner ring — etched darker gold + dark stroke
            Circle()
                .fill(Self.goldenFaceDeep)
                .scaleEffect(0.78)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.38),
                                lineWidth: max(0.4, size * 0.035))
                        .scaleEffect(0.78)
                )

            // Paw print mint mark
            CatPawPrint()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.34, blue: 0.04),
                            Color(red: 0.30, green: 0.18, blue: 0.02),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: size * 0.58, height: size * 0.58)

            // Inner highlight crescent
            Circle()
                .stroke(Color.white.opacity(0.55),
                        lineWidth: max(0.5, size * 0.05))
                .scaleEffect(0.70)
                .offset(x: -size * 0.10, y: -size * 0.10)
                // Clip the highlight to the recessed ring so it doesn't
                // overflow into the outer rim area.
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
        try? engine.start()

        winBuffer = makeWinBuffer(format: format)
    }

    func playWin(enabled: Bool) {
        guard enabled, let buffer = winBuffer else { return }
        if !engine.isRunning {
            try? engine.start()
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
