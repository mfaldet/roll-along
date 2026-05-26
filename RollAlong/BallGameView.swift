import SwiftUI
import CoreMotion
import Combine
import UIKit
import AudioToolbox

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
    @Environment(\.dismiss) var dismiss

    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    @State private var ball:               Ball?     = nil
    @State private var phase:              GamePhase = .playing
    @State private var arenaSize:          CGSize    = .zero
    @State private var showWelcomeMoment:  Bool      = false

    // Animation-polish triggers (keyframe animators key off these)
    @State private var squashTrigger:      Int       = 0   // on wall bounce
    @State private var shakeTrigger:       Int       = 0   // on .fell
    @State private var goalBurst:          GoalBurstEvent? = nil

    private let ballRadius: CGFloat = 18
    private let tickRate            = 1.0 / 60.0

    private var layout: LevelLayout {
        let base = LevelLayout.layout(for: gameState.currentLevel)
        return gameState.ballStartsAtTop ? base.flipped() : base
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
                // White platform
                Color(white: 0.94).ignoresSafeArea()

                // Hole zones (black)
                holeLayer(geo: geo)

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

                // HUD
                hud(safeBottom: geo.safeAreaInsets.bottom)

                // Overlays
                if phase == .fell          { oopsOverlay }
                if phase == .levelComplete { winOverlay }
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
                spawnBall(in: geo.size)
            }
            .onReceive(clock.$tickCount) { _ in
                tick(geoSize: geo.size)
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear  { motion.start(); clock.start() }
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
                .fill(Color.black)
                .frame(width: w, height: h)
                .position(x: x, y: y)
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

                        let twinkFreq = 2.8 + Double(i % 7) * 0.55
                        let raw = (sin(t * twinkFreq + phase * .pi * 3 + Double(ringIdx * 7)) + 1) / 2
                        let twinkle = pow(raw, 2.2)

                        let alpha = 0.30 + twinkle * 0.70
                        let pR    = CGFloat(minSz + twinkle * (maxSz - minSz))
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

    private func hud(safeBottom: CGFloat) -> some View {
        VStack {
            Spacer()
            ZStack(alignment: .center) {
                Text("LEVEL \(gameState.currentLevel)")
                    .font(.system(size: 12, weight: .ultraLight, design: .monospaced))
                    .kerning(4)
                    .foregroundStyle(Color(white: 0.40))
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "house.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(white: 0.38))
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(Color(white: 1.0, opacity: 0.72))
                                    .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                            )
                    }
                    Spacer()
                }
            }
            .padding(.leading, 22)
            .padding(.trailing, 16)
            .padding(.bottom, max(safeBottom, 12) + 8)
        }
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
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Level Clear!")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.25, green: 0.90, blue: 0.45))
                    Text("Level \(gameState.currentLevel) complete")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(red: 0.60, green: 0.95, blue: 0.68))
                }
                Button {
                    advanceFromLevelClear()
                } label: {
                    Text("Next Level")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 0.20, green: 0.78, blue: 0.38))
                        )
                }
            }
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
        ball = Ball(position: startPoint(in: size), velocity: .zero)
        goalBurst = nil  // clear any leftover burst from previous level
        withAnimation(.easeOut(duration: 0.2)) { phase = .playing }
    }

    private func tick(geoSize: CGSize) {
        guard phase == .playing, var b = ball else { return }
        let dt = CGFloat(tickRate)

        let accelScale: CGFloat = 1800
        b.velocity.dx += CGFloat(motion.gravity.x) * accelScale * dt
        b.velocity.dy += CGFloat(motion.gravity.y) * accelScale * dt

        b.velocity.dx *= 0.985
        b.velocity.dy *= 0.985

        if motion.gravity == .zero && hypot(b.velocity.dx, b.velocity.dy) < 6 {
            b.velocity = .zero
        }

        b.position.x += b.velocity.dx * dt
        b.position.y += b.velocity.dy * dt

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

        // Goal check
        let gp = goalPoint(in: geoSize)
        if hypot(b.position.x - gp.x, b.position.y - gp.y) < ballRadius * 1.7 {
            ball = b
            fireGoalReached(at: gp)
            withAnimation(.easeIn(duration: 0.35)) { phase = .levelComplete }
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
        SFX.bounce(enabled: gameState.soundEnabled)
        squashTrigger &+= 1
    }

    private func fireGoalReached(at center: CGPoint) {
        if gameState.hapticsEnabled { Haptics.success() }
        SFX.goal(enabled: gameState.soundEnabled)
        goalBurst = GoalBurstEvent(center: center, start: .now)
    }

    private func fireFell() {
        if gameState.hapticsEnabled { Haptics.heavy() }
        SFX.drop(enabled: gameState.soundEnabled)
        shakeTrigger &+= 1
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

enum SFX {
    // System sound IDs — see https://github.com/TUNER88/iOSSystemSoundsLibrary
    private static let bounceID:  SystemSoundID = 1104  // light "tick"
    private static let dropID:    SystemSoundID = 1073  // low "thud"
    private static let goalID:    SystemSoundID = 1025  // bright "ding"
    private static let coinID:    SystemSoundID = 1306  // sharp pickup tick
    private static let tapID:     SystemSoundID = 1306  // UI tap

    static func bounce(enabled: Bool) { play(bounceID, enabled: enabled) }
    static func drop  (enabled: Bool) { play(dropID,   enabled: enabled) }
    static func goal  (enabled: Bool) { play(goalID,   enabled: enabled) }
    static func coin  (enabled: Bool) { play(coinID,   enabled: enabled) }
    static func tap   (enabled: Bool) { play(tapID,    enabled: enabled) }

    private static func play(_ id: SystemSoundID, enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(id)
    }
}
