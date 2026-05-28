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

private enum BorderPhase: Equatable {
    case normal, fell, won
}

struct BallGameView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    @State private var ball:               Ball?     = nil
    @State private var phase:              GamePhase = .playing
    @State private var arenaSize:          CGSize    = .zero
    @State private var showWelcomeMoment:  Bool      = false

    // Lives system (Sprint 4c)
    @State private var showOutOfLives:                Bool   = false
    @State private var showLivesPlaceholderAlert:     Bool   = false
    @State private var livesPlaceholderMessage:       String = ""

    // Per-attempt progression state
    @State private var levelStartTime:        Date?    = nil
    @State private var coinsPickedThisAttempt: Set<Int> = []    // coin indices 0…2 picked this attempt

    // Graphite trail (Paper world).  Holds recent ball positions so we can
    // render a fading lead streak behind the ball.  Cleared each spawn.
    @State private var trailPoints:           [CGPoint] = []
    private let trailMaxLength = 90        // ~1.5s of trail at 60fps
    private let trailMinStep:  CGFloat = 1.5

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

    private var layout: LevelLayout {
        let base = LevelLayout.layout(for: gameState.currentLevel)
        return gameState.ballStartsAtTop ? base.flipped() : base
    }

    /// Active theme — driven by what the player has equipped in the cosmetic
    /// shop, not by level number.  Defaults to Classic for new players.
    private var theme: Theme {
        Theme.for(gameState.equippedBackground)
    }

    // MARK: - Border state

    private var borderPhase: BorderPhase {
        switch phase {
        case .playing:       return .normal
        case .fell:          return .fell
        case .levelComplete: return .won
        }
    }

    private var borderColor: Color {
        switch borderPhase {
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
                theme.floorColor.ignoresSafeArea()

                // Aurora theme: animated shimmer overlay on top of the base.
                // Skipped under Reduce Motion to avoid continuous background drift.
                if theme.id == .aurora && !reduceMotion {
                    auroraShimmerOverlay
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

                // Rainbow goal
                rainbowHole
                    .frame(width: ballRadius * 2.8, height: ballRadius * 2.8)
                    .position(goalPoint(in: geo.size))

                // Ball
                if let ball {
                    marbleView
                        .frame(width: ballRadius * 2, height: ballRadius * 2)
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

                // Lives HUD — top-left.  Hidden on tutorial levels (where
                // failure doesn't cost a life) so it doesn't add cognitive
                // load during onboarding.
                if !gameState.isTutorialLevel(gameState.currentLevel) {
                    livesHUDOverlay(safeTop: geo.safeAreaInsets.top)
                }

                // Overlays
                if phase == .fell          { oopsOverlay }
                if phase == .levelComplete { winOverlay }

                // Out-of-lives overlay — shown when the player tries to play
                // with zero lives.  Sits above the Oops/Win overlays.
                if showOutOfLives { outOfLivesOverlay }

                // Home button — rendered AFTER oops/win overlays so it stays
                // tappable while they're showing.  Hidden during the welcome
                // moment so it doesn't compete for attention there.
                if !showWelcomeMoment {
                    homeButtonOverlay(safeBottom: geo.safeAreaInsets.bottom)
                }

                if showWelcomeMoment       { welcomeMomentOverlay }

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
        ForEach(Array(layout.holeRects.enumerated()), id: \.offset) { _, norm in
            let w = norm.width  * geo.size.width
            let h = norm.height * geo.size.height
            let x = (norm.origin.x + norm.width  / 2) * geo.size.width
            let y = (norm.origin.y + norm.height / 2) * geo.size.height
            Rectangle()
                .fill(theme.holeColor)
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
        return ForEach(Array(layout.coins.enumerated()), id: \.offset) { idx, norm in
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

    /// Graphite trail — drawn as a sequence of short line segments with
    /// increasing opacity from oldest (tail) to newest (head).  This gives
    /// the streak a natural fade without needing a gradient-stroke API.
    private func trailOverlay(geo: GeometryProxy) -> some View {
        Canvas { ctx, _ in
            let n = trailPoints.count
            guard n >= 2 else { return }
            for i in 1..<n {
                let prev = trailPoints[i - 1]
                let curr = trailPoints[i]
                // Fade from 0.10 (tail) → 1.0 (head)
                let age = Double(i) / Double(n - 1)
                let opacity = 0.10 + 0.90 * age
                var path = Path()
                path.move(to: prev)
                path.addLine(to: curr)
                ctx.stroke(
                    path,
                    with: .color(gameState.equippedTrail.color.opacity(opacity)),
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    /// Sub-theme floor overlays for the Paper world (L51-100).
    /// Returns an empty view for non-paper themes so the call site can
    /// stay simple.
    @ViewBuilder
    private func paperFloorOverlay(geo: GeometryProxy) -> some View {
        switch theme.id {
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

    private var rainbowHole: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t    = timeline.date.timeIntervalSinceReferenceDate
                let cx   = size.width  / 2
                let cy   = size.height / 2
                let maxR = (size.width / 2) * 0.90
                let ctr  = CGPoint(x: cx, y: cy)

                // ── Deep dark background ─────────────────────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                    with: .color(Color(red: 0.03, green: 0.01, blue: 0.06).opacity(0.60))
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
                        let hue = (phase + t * 0.06 + hueOffset).truncatingRemainder(dividingBy: 1.0)

                        let twinkFreq: Double = 2.8 + Double(i % 7) * 0.55
                        let twinkArg: Double = t * twinkFreq + phase * .pi * 3 + Double(ringIdx * 7)
                        let raw: Double = (sin(twinkArg) + 1) / 2
                        let twinkle: Double = pow(raw, 2.2)

                        let alpha: Double = 0.30 + twinkle * 0.70
                        let pR: CGFloat = CGFloat(minSz + twinkle * (maxSz - minSz))
                        let color = Color(hue: hue, saturation: 1.0, brightness: 0.55 + twinkle * 0.45)

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

    private var marbleView: some View {
        Circle()
            .fill(gameState.activeSkin.gradient(endRadius: ballRadius * 1.4))
            .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.55), radius: 4, x: 2, y: 5)
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    ForEach(0..<GameState.livesMax, id: \.self) { i in
                        lifeIcon(filled: i < gameState.displayedLives,
                                 gold: gameState.unlimitedLives)
                    }
                }
                if let countdown = gameState.timeToNextLife() {
                    Text("+1 in \(Self.formatCountdown(countdown))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.50))
                }
            }
            .padding(.leading, 18)
            .padding(.top, max(safeTop, 8) + 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(livesAccessibilityLabel)
        }
    }

    private var livesAccessibilityLabel: String {
        if gameState.unlimitedLives {
            return "Unlimited lives."
        }
        let count = gameState.displayedLives
        var label = "\(count) of \(GameState.livesMax) lives."
        if let next = gameState.timeToNextLife() {
            label += " Next life in \(Self.formatCountdown(next))."
        }
        return label
    }

    /// One life slot.  Filled = available, outlined = used.
    @ViewBuilder
    private func lifeIcon(filled: Bool, gold: Bool) -> some View {
        if filled {
            Circle()
                .fill(gold ? Self.goldLifeGradient : Self.redLifeGradient)
                .frame(width: 13, height: 13)
                .overlay(
                    // Tiny upper-left highlight to suggest a marble
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 4, height: 4)
                        .offset(x: -2.5, y: -2.5)
                )
                .overlay(
                    Circle().stroke(Color.black.opacity(0.40), lineWidth: 0.6)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 1.5, y: 1)
        } else {
            Circle()
                .stroke(Color(white: 0.40).opacity(0.7), lineWidth: 0.9)
                .frame(width: 13, height: 13)
        }
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

    // MARK: - Out of lives overlay

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

                    HStack(spacing: 8) {
                        ForEach(0..<GameState.livesMax, id: \.self) { i in
                            lifeIcon(filled: i < gameState.displayedLives, gold: false)
                                .scaleEffect(1.6)
                        }
                    }
                    .padding(.vertical, 6)

                    if let countdown = gameState.timeToNextLife() {
                        Text("Next life in \(Self.formatCountdown(countdown))")
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(white: 0.92))
                    }

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

                        // Placeholder action — Watch Ad (real wiring in 4i).
                        Button {
                            livesPlaceholderMessage = "Rewarded video ads launch with the next update.\n\nFor now, lives refill 1 every 10 minutes — or play tutorial levels (1-10) which don't consume lives."
                            showLivesPlaceholderAlert = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.rectangle.fill")
                                Text("Watch ad — +1 life")
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

                        // Placeholder action — Buy Lives (real wiring in 4h).
                        Button {
                            livesPlaceholderMessage = "Life and unlimited-lives purchases launch with the next update.\n\nFor now, lives refill 1 every 10 minutes — or play tutorial levels (1-10) which don't consume lives."
                            showLivesPlaceholderAlert = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "cart.fill")
                                Text("Buy lives")
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

                // Coins row — shows all 3 slots, filled gold for picked this attempt
                HStack(spacing: 10) {
                    ForEach(0..<3) { i in
                        if lastClearedCoinIndices.contains(i) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.00, green: 0.88, blue: 0.40),
                                            Color(red: 0.93, green: 0.65, blue: 0.10),
                                        ],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .shadow(color: Color(red: 0.93, green: 0.65, blue: 0.10).opacity(0.5),
                                        radius: 6)
                        } else {
                            Image(systemName: "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(Color(white: 0.30))
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
    /// If the player just cleared Level 1 for the very first time, route
    /// through the one-time "Roll Along friend" welcome moment before
    /// advancing.  Otherwise advance immediately.
    private func advanceFromLevelClear() {
        if gameState.currentLevel == 1 && !gameState.seenWelcomeMoment {
            withAnimation(.easeInOut(duration: 0.32)) {
                showWelcomeMoment = true
            }
        } else {
            gameState.advanceLevel()
            spawnBall(in: arenaSize)
        }
    }

    private func dismissWelcomeMoment() {
        gameState.seenWelcomeMoment = true
        gameState.advanceLevel()
        spawnBall(in: arenaSize)
        withAnimation(.easeInOut(duration: 0.32)) {
            showWelcomeMoment = false
        }
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
        levelStartTime = .now
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }

    private func tick(geoSize: CGSize) {
        guard phase == .playing, var b = ball else { return }
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
            if trailPoints.count > trailMaxLength {
                trailPoints.removeFirst(trailPoints.count - trailMaxLength)
            }
        }

        // Top and bottom wall bounce
        let r = ballRadius
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

        // Coin pickup — collect any not yet picked this attempt + not banked.
        // Multiple coins can be collected per run.
        let banked = gameState.coinsCollected(for: gameState.currentLevel)
        for (idx, c) in layout.coins.enumerated() {
            if coinsPickedThisAttempt.contains(idx) { continue }
            if banked.contains(idx) { continue }
            let cx = c.x * geoSize.width
            let cy = c.y * geoSize.height
            let dist = hypot(b.position.x - cx, b.position.y - cy)
            if dist < ballRadius + coinRadius {
                coinsPickedThisAttempt.insert(idx)
                fireCoinPickup()
            }
        }

        // Goal check
        let gp = goalPoint(in: geoSize)
        if hypot(b.position.x - gp.x, b.position.y - gp.y) < ballRadius * 1.7 {
            ball = b
            handleLevelClear(at: gp)
            return
        }

        // Hole check
        if isInHole(position: b.position, size: geoSize) || b.position.x < -r || b.position.x > geoSize.width + r {
            ball = b
            fireFell()
            withAnimation(.easeIn(duration: 0.22)) { phase = .fell }
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

        // Currency-coin reward
        //
        // Per-level coin pickups (coinsPickedThisAttempt) are by definition
        // first-time — banked coins are skipped at pickup time — so we award
        // for every coin in the set.
        //
        // Star awards count only NEW stars this run.  A 2-star clear of a
        // previously 1-star level awards +20 (the new second star).
        let newStars   = max(0, stars - prevStars)
        let coinReward = newStars * GameState.coinPerNewStar
                       + coinsPickedThisAttempt.count * GameState.coinPerPickup

        lastClearedTime           = elapsed
        lastClearedStars          = stars
        lastClearedCoinIndices    = coinsPickedThisAttempt
        lastClearedIsNewBestStars = stars > prevStars
        lastClearedCoinReward     = coinReward

        gameState.recordResult(
            level: level,
            stars: stars,
            time:  elapsed,
            coinIndices: coinsPickedThisAttempt
        )
        if coinReward > 0 {
            gameState.addCoins(coinReward)
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
        layout.holeRects.contains { norm in
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

    /// Face gradient — bright top, deep amber bottom.
    private static let goldenFace = LinearGradient(
        stops: [
            .init(color: Color(red: 1.00, green: 0.94, blue: 0.55), location: 0.00),
            .init(color: Color(red: 0.97, green: 0.79, blue: 0.22), location: 0.45),
            .init(color: Color(red: 0.78, green: 0.50, blue: 0.06), location: 1.00),
        ],
        startPoint: .top, endPoint: .bottom
    )
    /// Slightly darker version of the face gradient — used for the
    /// recessed inner ring so it reads as "etched into" the face.
    private static let goldenFaceDeep = LinearGradient(
        stops: [
            .init(color: Color(red: 0.85, green: 0.70, blue: 0.18), location: 0.00),
            .init(color: Color(red: 0.72, green: 0.50, blue: 0.10), location: 1.00),
        ],
        startPoint: .top, endPoint: .bottom
    )
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

            // Centred minted star — gives the coin a unique mark.
            MintedStar(points: 5, innerRatio: 0.45)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.34, blue: 0.04),
                            Color(red: 0.30, green: 0.18, blue: 0.02),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: size * 0.42, height: size * 0.42)
                .overlay(
                    MintedStar(points: 5, innerRatio: 0.45)
                        .stroke(Color.black.opacity(0.45), lineWidth: 0.6)
                        .frame(width: size * 0.42, height: size * 0.42)
                )
                // A tiny white highlight on the upper-left edge of the star
                // sells the embossed, raised feel.
                .overlay(
                    MintedStar(points: 5, innerRatio: 0.45)
                        .stroke(Color.white.opacity(0.45 * spinRaw), lineWidth: 0.5)
                        .frame(width: size * 0.41, height: size * 0.41)
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
// MintedStar — 5-pointed star shape used on the coin face.
// Drawn as a Path with explicit outer/inner radii so the star reads
// crisp at any size.
// ---------------------------------------------------------------------------
struct MintedStar: Shape {
    let points: Int
    let innerRatio: CGFloat   // inner radius / outer radius (~0.4-0.5)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * innerRatio
        let totalPoints = points * 2
        let step = .pi * 2 / Double(totalPoints)
        // Start at the top point, pointing up
        let startAngle = -Double.pi / 2

        for i in 0..<totalPoints {
            let r = i.isMultiple(of: 2) ? outerR : innerR
            let angle = startAngle + Double(i) * step
            let pt = CGPoint(
                x: center.x + CGFloat(cos(angle)) * r,
                y: center.y + CGFloat(sin(angle)) * r
            )
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
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
