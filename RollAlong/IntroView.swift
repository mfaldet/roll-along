import SwiftUI

/// "Cold Open" — the cinematic opening-credits intro played over the dark
/// stage on a cold launch (gated by `GameState.introEnabled`, default OFF).
///
/// Four beats, ~3.7s, fully skippable (tap anywhere):
///   1. The Roll   — the player's equipped ball rolls in from the edge with a
///                   fading trail, wandering like a tilt response, while dim
///                   ghost orbs tease the skin catalogue.
///   2. The Vortex — a portal glow blooms centre and the ball spirals inward
///                   and shrinks (the same drain math as the level-launch
///                   transition in GameMode.swift).
///   3. The Title  — "Roll Along" resolves above the drain; the ball pops back
///                   out of the portal with a spring, an aurora glow pulsing
///                   behind (the aurora vocabulary from BallGameView).
///   4. Handoff    — the caller cross-fades to HomeView (its roaming ball is
///                   already moving, so the hero ball appears to *become* it).
///
/// Reduce Motion collapses beats 1–3 to a static title card. Self-contained:
/// reuses BallSkinView, Haptics and AudioManager but touches no game state.
struct IntroView: View {
    let onComplete: () -> Void

    @EnvironmentObject private var gameState: GameState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var startDate = Date()
    @State private var done = false
    @State private var completionTask: Task<Void, Never>? = nil

    // Beat durations (seconds).
    private let rollDur: Double = 1.40
    private let vortexDur: Double = 1.20
    private let titleHold: Double = 1.10
    private let reducedTotal: Double = 1.50

    private var vortexStart: Double { rollDur }
    private var vortexEnd: Double { rollDur + vortexDur }
    private var titleStart: Double { vortexEnd - 0.20 }   // overlaps the flare
    private var animTotal: Double { rollDur + vortexDur + titleHold }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(white: 0.04)
                content(geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { skip() }
        }
        .ignoresSafeArea()
        .onAppear(perform: begin)
        .onDisappear { completionTask?.cancel() }
    }

    @ViewBuilder
    private func content(_ size: CGSize) -> some View {
        if reduceMotion {
            staticCard(size)
        } else {
            animated(size)
        }
    }

    // MARK: - Animated sequence

    private func animated(_ size: CGSize) -> some View {
        TimelineView(.animation) { tl in
            let t = max(0, tl.date.timeIntervalSince(startDate))
            let driftTime = tl.date.timeIntervalSinceReferenceDate
            let d = drain(size)
            let baseD = heroBaseDiameter(size)
            let hc = heroCenter(t, size)
            let hs = heroSize(t, baseD)
            let titleOp = clamp01((t - titleStart) / 0.5)
            let titleE = easeOut(clamp01((t - titleStart) / 0.6))

            ZStack {
                auroraLayer(size: size, time: driftTime, opacity: 0.14 + 0.20 * titleOp)
                ghostLayer(size: size, t: t)
                portalGlow(center: d, brightness: glow(t))
                trailLayer(size: size, t: t)
                BallSkinView(skin: gameState.activeSkin, diameter: hs)
                    .frame(width: hs, height: hs)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .position(hc)
                    .opacity(heroOpacity(t))
                titleView(size: size,
                          opacity: titleOp,
                          scale: 0.86 + 0.14 * titleE,
                          yOffset: (1 - titleE) * 16)
            }
        }
    }

    private func staticCard(_ size: CGSize) -> some View {
        let d = drain(size)
        let baseD = heroBaseDiameter(size)
        return ZStack {
            titleView(size: size, opacity: 1, scale: 1, yOffset: 0)
            BallSkinView(skin: gameState.activeSkin, diameter: baseD)
                .frame(width: baseD, height: baseD)
                .shadow(color: .black.opacity(0.5), radius: 8)
                .position(d)
        }
    }

    // MARK: - Layers

    private func auroraLayer(size: CGSize, time t: Double, opacity: Double) -> some View {
        Canvas { ctx, cs in
            let blobs: [(Double, Double, Double, Double)] = [
                (0.0, 0.0, 0.55, 0.06),   // teal-green
                (1.7, 2.4, 0.62, 0.08),   // blue
                (3.5, 1.1, 0.72, 0.05),   // purple
            ]
            let r = cs.width * 0.8
            for (xSeed, ySeed, hueSeed, speed) in blobs {
                let bx = cs.width  * CGFloat(0.5 + 0.50 * sin(t * speed       + xSeed))
                let by = cs.height * CGFloat(0.5 + 0.45 * sin(t * speed * 1.3 + ySeed))
                let hue = (hueSeed + t * 0.01).truncatingRemainder(dividingBy: 1.0)
                let color = Color(hue: hue, saturation: 0.55, brightness: 0.90)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(0.32), .clear]),
                        center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: r)
                )
            }
        }
        .opacity(opacity)
        .blur(radius: 8)
        .allowsHitTesting(false)
    }

    /// Dim, blurred orbs in premium-skin colours that drift behind the roll,
    /// then fade out as the vortex takes over.
    private func ghostLayer(size: CGSize, t: Double) -> some View {
        let fade = clamp01(1 - max(0, t - rollDur) / 0.6)
        return Canvas { ctx, cs in
            let orbs: [(Double, Double, Double, Color)] = [
                (0.20, 0.30, 26, Color(red: 0.55, green: 0.40, blue: 0.92)), // galaxy
                (0.78, 0.24, 20, Color(red: 0.86, green: 0.42, blue: 0.22)), // mars
                (0.66, 0.74, 30, Color(red: 0.30, green: 0.85, blue: 0.80)), // aurora
            ]
            for (fx, fy, baseR, col) in orbs {
                let cx = cs.width  * CGFloat(fx) + CGFloat(sin(t * 0.6 + fx * 6) * 10)
                let cy = cs.height * CGFloat(fy) + CGFloat(cos(t * 0.5 + fy * 6) * 8)
                let r = CGFloat(baseR)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [col.opacity(0.6), col.opacity(0.0)]),
                        center: CGPoint(x: cx - r * 0.25, y: cy - r * 0.25),
                        startRadius: 0, endRadius: r)
                )
            }
        }
        .opacity(fade * 0.5)
        .blur(radius: 3)
        .allowsHitTesting(false)
    }

    private func portalGlow(center: CGPoint, brightness: Double) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [Color(red: 0.45, green: 0.78, blue: 1.0).opacity(0.65 * brightness),
                         Color(red: 0.30, green: 0.55, blue: 0.95).opacity(0.30 * brightness),
                         .clear],
                center: .center, startRadius: 0, endRadius: 90))
            .frame(width: 200, height: 200)
            .position(center)
            .allowsHitTesting(false)
    }

    /// Fading comet trail sampled from the hero's own path a few frames back —
    /// same segment-fade technique as the cosmetic trail / launch vortex.
    private func trailLayer(size: CGSize, t: Double) -> some View {
        Canvas { ctx, _ in
            let steps = 18
            let dt = 0.020
            var prev: CGPoint? = nil
            for j in stride(from: steps, through: 1, by: -1) {
                let past = t - Double(j) * dt
                guard past >= 0 else { prev = nil; continue }
                let pt = heroCenter(past, size)
                let frac = Double(j) / Double(steps)   // 1 = tail, →0 = head
                if let pv = prev {
                    let op = (1 - frac) * 0.5 * trailFade(t)
                    let lw = max(2, heroSize(past, heroBaseDiameter(size))
                                 * CGFloat(0.30 + (1 - frac) * 0.5))
                    var seg = Path(); seg.move(to: pv); seg.addLine(to: pt)
                    ctx.stroke(seg,
                               with: .color(Color(red: 0.62, green: 0.86, blue: 1.0).opacity(op)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                }
                prev = pt
            }
        }
        .allowsHitTesting(false)
    }

    private func titleView(size: CGSize, opacity: Double, scale: Double, yOffset: Double) -> some View {
        let d = drain(size)
        return Text("Roll Along")
            .font(.system(size: min(size.width * 0.135, 56), weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(colors: [.white, Color(white: 0.82)],
                               startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
            .opacity(opacity)
            .scaleEffect(scale)
            .position(x: size.width / 2, y: d.y - size.height * 0.17 + CGFloat(yOffset))
            .allowsHitTesting(false)
    }

    // MARK: - Geometry & motion (methods, never closure-local funcs)

    private func drain(_ size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.54)
    }

    private func heroBaseDiameter(_ size: CGSize) -> CGFloat {
        min(size.width, size.height) * 0.14
    }

    /// Hero ball centre over time: roll in → spiral to the drain → rest there.
    /// The roll ends exactly on the spiral's start point so the two beats join
    /// seamlessly.
    private func heroCenter(_ t: Double, _ size: CGSize) -> CGPoint {
        let d = drain(size)
        let r0 = min(size.width, size.height) * 0.30
        let a0 = -0.55
        let turns = 2.5
        let spiralStart = CGPoint(x: d.x + CGFloat(cos(a0)) * r0,
                                  y: d.y + CGFloat(sin(a0)) * r0)

        if t <= rollDur {
            let rp = easeInOut(clamp01(t / rollDur))
            let startX = -size.width * 0.18
            let x = lerp(Double(startX), Double(spiralStart.x), rp)
            let baseY = lerp(Double(d.y + size.height * 0.12), Double(spiralStart.y), rp)
            let wob = sin(rp * .pi * 3) * Double(size.height) * 0.07 * (1 - rp)
            return CGPoint(x: x, y: baseY + wob)
        } else if t <= vortexEnd {
            let sp = clamp01((t - vortexStart) / vortexDur)
            let spin = pow(sp, 1.8)
            let rad = r0 * CGFloat(1 - spin)
            let ang = a0 + spin * 2 * .pi * turns
            return CGPoint(x: d.x + CGFloat(cos(ang)) * rad,
                           y: d.y + CGFloat(sin(ang)) * rad)
        } else {
            return d
        }
    }

    /// Full size during the roll, shrinks into the drain, then springs back.
    private func heroSize(_ t: Double, _ baseD: CGFloat) -> CGFloat {
        if t <= vortexStart {
            return baseD
        } else if t <= vortexEnd {
            let spin = pow(clamp01((t - vortexStart) / vortexDur), 1.8)
            return baseD * CGFloat(max(0.12, 1 - spin))
        } else {
            let e = clamp01((t - vortexEnd) / 0.45)
            return baseD * CGFloat(0.12 + (1.0 - 0.12) * easeOutBack(e))
        }
    }

    private func heroOpacity(_ t: Double) -> Double { clamp01(t / 0.25) }

    private func glow(_ t: Double) -> Double {
        if t <= vortexStart {
            return 0
        } else if t <= vortexEnd {
            return pow(clamp01((t - vortexStart) / vortexDur), 2.0)
        } else {
            return max(0, 1 - (t - vortexEnd) / 0.7)
        }
    }

    private func trailFade(_ t: Double) -> Double {
        clamp01(1 - max(0, t - vortexEnd) / 0.4)
    }

    // MARK: - Easing

    private func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }
    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    private func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    // MARK: - Lifecycle

    private func begin() {
        startDate = Date()
        AudioManager.shared.prepareIfNeeded()

        if reduceMotion {
            completionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(reducedTotal * 1_000_000_000))
                guard !Task.isCancelled else { return }
                finish()
            }
            return
        }

        if gameState.hapticsEnabled { Haptics.soft() }
        completionTask = Task { @MainActor in
            // Flare moment: success haptic + the win chime as the title resolves.
            try? await Task.sleep(nanoseconds: UInt64(vortexEnd * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if gameState.hapticsEnabled { Haptics.success() }
            AudioManager.shared.playWin(enabled: gameState.soundEnabled)

            try? await Task.sleep(nanoseconds: UInt64((animTotal - vortexEnd + 0.05) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func skip() {
        completionTask?.cancel()
        if !reduceMotion && gameState.hapticsEnabled { Haptics.light() }
        finish()
    }

    private func finish() {
        guard !done else { return }
        done = true
        onComplete()
    }
}

#Preview {
    IntroView(onComplete: {})
        .environmentObject(GameState())
        .preferredColorScheme(.dark)
}
