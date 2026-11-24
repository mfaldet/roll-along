import SwiftUI

// ===========================================================================
// The end room (1.1).  Shown from Home (see HomeMoments.swift) the first time
// a player passes the last level in the pack, and again with the second set
// of messages when a later pack adds levels and they pass the new last one.
//
//  • An open playfield with no holes, in the Waiting Room look: the white floor with
//    its faint glow, the glowing edge, and the Waiting Room ball rolling by tilt.
//  • Messages appear one at a time in the center, each sharpening from a blur
//    and then blurring away (`EndRoomRules`).  The only other text is the
//    Locker line, with the first visit's last message.
//  • Small flashes of color move across the screen in waves.  Soft and slow:
//    each flash brightens and fades over more than a second, and nothing
//    flashes on and off.  None under Reduce Motion.
//  • After 30 to 60 seconds the opening animation's swirl (IntroView) plays
//    and ends on Home.
//
// The visit is recorded the moment the room opens, so a player who leaves the
// app mid-room keeps the gift and does not see the room again.
// ===========================================================================
struct EndRoomFlowView: View {
    let visit: EndRoomVisit
    /// Debug preview: records nothing and gives nothing.
    var preview: Bool = false
    let onDone: () -> Void

    @EnvironmentObject private var gameState: GameState
    @State private var showSwirl = false

    var body: some View {
        ZStack {
            EndRoomView(visit: visit, onFinished: {
                withAnimation(.easeInOut(duration: 0.5)) { showSwirl = true }
            })
            if showSwirl {
                // The animation the game opens with: the ball spirals into the
                // portal, the title resolves, and the last frame is Home.
                IntroView(onComplete: onDone)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            if !preview { gameState.recordEndRoomVisit(visit) }
        }
    }
}

struct EndRoomView: View {
    let visit: EndRoomVisit
    let onFinished: () -> Void

    @EnvironmentObject private var gameState: GameState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()
    @State private var arena: CGSize = .zero
    @State private var ballPos: CGPoint = .zero
    @State private var ballVel: CGVector = .zero
    @State private var start = Date()
    @State private var finished = false

    private let ballRadius: CGFloat = 18
    private let wallCorner: CGFloat = 44
    private let ink = Color(white: 0.16)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Floor.waitingRoom.color
                WaitingRoomFloorOverlay()
                if !reduceMotion { EndRoomFlashes(start: start) }
                RoundedRectangle(cornerRadius: wallCorner, style: .continuous)
                    .strokeBorder(Boundary.waitingRoom.color, lineWidth: 4)
                WaitingRoomBoundaryOverlay(cornerRadius: wallCorner)
                BallSkinView(skin: .waitingRoom, diameter: ballRadius * 2)
                    .frame(width: ballRadius * 2, height: ballRadius * 2)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .position(ballPos)
                messageLayer
            }
            .ignoresSafeArea()
            .onAppear {
                arena = geo.size
                ballPos = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.72)
                start = Date()
                motion.start(); clock.start()
            }
            .onDisappear { motion.stop(); clock.stop() }
            .task {
                // The room lasts its set time, then hands over to the swirl.
                let seconds = EndRoomRules.duration(of: visit)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !finished else { return }
                finished = true
                onFinished()
            }
            .onReceive(clock.$tickCount) { _ in tick() }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .accessibilityElement(children: .contain)
    }

    /// The message of the moment, sharpening and blurring away; and, with
    /// the first visit's last message, the Locker line.
    private var messageLayer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSince(start)
            let current = EndRoomRules.message(at: t, of: visit)
            VStack(spacing: 14) {
                if let current {
                    let blur = reduceMotion ? 0 : 14 * (1 - current.clarity)
                    Text(visit.messages[current.index])
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 36)
                        .blur(radius: blur)
                        .opacity(current.clarity)
                        .accessibilityLabel(visit.messages[current.index])
                    if visit.giftMessageIndex == current.index {
                        Text("The Waiting Room collection is in your Locker.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .blur(radius: blur)
                            .opacity(current.clarity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    /// Tilt rolls the ball; it bounces off the wall.  The same feel as the
    /// ball on Home.
    private func tick() {
        let r = ballRadius
        guard arena.width >= 2 * r, arena.height >= 2 * r else { return }
        let dt: CGFloat = 1.0 / 60.0
        ballVel.dx += CGFloat(motion.gravity.x) * 1_400 * dt
        ballVel.dy += CGFloat(motion.gravity.y) * 1_400 * dt
        ballVel.dx *= 0.985
        ballVel.dy *= 0.985
        if motion.gravity == .zero && hypot(ballVel.dx, ballVel.dy) < 5 { ballVel = .zero }
        ballPos.x += ballVel.dx * dt
        ballPos.y += ballVel.dy * dt
        let inset: CGFloat = 4
        let minX = r + inset, maxX = arena.width - r - inset
        let minY = r + inset, maxY = arena.height - r - inset
        if ballPos.x < minX { ballPos.x = minX; ballVel.dx = -ballVel.dx * 0.65 }
        if ballPos.x > maxX { ballPos.x = maxX; ballVel.dx = -ballVel.dx * 0.65 }
        if ballPos.y < minY { ballPos.y = minY; ballVel.dy = -ballVel.dy * 0.65 }
        if ballPos.y > maxY { ballPos.y = maxY; ballVel.dy = -ballVel.dy * 0.65 }
    }
}

/// Small flashes of color moving across the screen in waves.  A new wave
/// sets off every 5 seconds and takes 7 to cross, sweeping on a slant; each
/// flash in it is a small soft dot that brightens and fades as the wave
/// passes (well over a second), never blinking.  Drawn at 30 frames a second.
struct EndRoomFlashes: View {
    let start: Date

    private let waveEvery: Double = 5
    private let crossing: Double = 7
    private let perWave = 18

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                guard t > 0 else { return }
                let span = size.width + size.height * 0.5 + 160
                let firstWave = max(0, Int((t - crossing) / waveEvery))
                let lastWave = Int(t / waveEvery)
                guard lastWave >= firstWave else { return }
                for wave in firstWave...lastWave {
                    let progress = (t - Double(wave) * waveEvery) / crossing
                    guard progress >= 0, progress <= 1 else { continue }
                    let front = CGFloat(progress) * span - 80
                    var rng = SeededRNG(seed: UInt64(wave) &* 0x9E37_79B1 &+ 0x51)
                    let hueBase = rng.nextUnit()
                    for i in 0..<perWave {
                        let y = CGFloat(rng.nextUnit()) * size.height
                        let lag = CGFloat(rng.nextUnit()) * 90
                        // The wave runs on a slant: lower dots trail a little.
                        let x = front - lag - y * 0.5
                        let distance = abs(CGFloat(rng.nextUnit() - 0.5) * 40)
                        // Bright in the middle of the crossing, fading at both ends.
                        let level = sin(progress * Double.pi) * Double(max(0, 1 - distance / 40))
                        guard level > 0.02, x > -20, x < size.width + 20 else { continue }
                        let rad = 6 + CGFloat(rng.nextUnit()) * 8
                        // The glow's own colors: soft, no edge.
                        let color = FoilArt.tint(hueBase + Double(i) * 0.07, saturation: 0.60, brightness: 1)
                        let rect = CGRect(x: x - rad * 2, y: y - rad * 2, width: rad * 4, height: rad * 4)
                        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                            Gradient(colors: [color.opacity(0.55 * level), color.opacity(0)]),
                            center: CGPoint(x: x, y: y), startRadius: 0, endRadius: rad * 2))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
