import SwiftUI

// ===========================================================================
// SnakeGameView — the "Snake" competitive mode.
//
// A self-contained take on the shared marble: tilt rolls the head, which
// leaves a thick, growing body behind it.  Eat a pellet to grow longer and
// score; cross your own body and the run ends.  No lives, no progression —
// a quick high-score chase that banks coins on game over.
//
// SAFE BY CONSTRUCTION: this is a brand-new, isolated file.  It reuses only
// the shared physics primitives (BallMotion / PhysicsClock) and the coin /
// skin economy on GameState — it touches nothing in the climb engine, so it
// cannot affect the main game.  It's reached only when HomeView routes
// `.mode("snake")` here and SnakeMode is flagged on in the catalogue.
//
// FEEL IS TUNABLE: every gameplay number lives in the "Tunables" block below
// so the difficulty / pace can be dialed in from one place after playtesting.
// ===========================================================================

struct SnakeGameView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables

    private let headRadius:  CGFloat = 15        // the rolling head marble
    private let bodyWidth:   CGFloat = 26        // drawn thickness of the body
    private let accel:       CGFloat = 1_300     // tilt → acceleration
    private let friction:    CGFloat = 0.986     // per-tick velocity damping
    private let maxSpeed:    CGFloat = 540        // velocity clamp (pts/sec)
    private let wallBounce:  CGFloat = 0.55       // energy kept on a wall hit
    private let segmentStep: CGFloat = 5          // min head travel per body node
    private let startSegments  = 26               // body length at spawn (nodes)
    private let growPerPellet  = 7                // nodes added per pellet eaten
    private let safeSkipNodes  = 6                // nodes nearest the head ignored
    private let pelletRadius:  CGFloat = 12
    private let coinsPerPellet = 2                // coins banked per pellet

    /// Head-to-body-centerline distance that counts as a self-hit.
    private var collideDistance: CGFloat { headRadius * 0.85 + bodyWidth * 0.20 }

    // MARK: - State

    @State private var headPos: CGPoint = .zero
    @State private var headVel: CGVector = .zero
    @State private var arena:   CGSize  = .zero

    /// The body, oldest node first, newest (closest to the head) last.
    @State private var body: [CGPoint] = []
    @State private var maxNodes = 0

    @State private var pellet: CGPoint?
    @State private var score  = 0

    @State private var started = false   // begins on first tilt / tap
    @State private var isOver  = false
    @State private var awarded = false   // guard so coins bank exactly once

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.05), Color(white: 0.12)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Color.clear
                    bodyLayer.allowsHitTesting(false)
                    pelletLayer.allowsHitTesting(false)
                    headMarble.position(headPos)
                }
                .contentShape(Rectangle())
                .onAppear {
                    arena = geo.size
                    reset(in: geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    arena = newSize
                    if body.isEmpty { reset(in: newSize) }
                }
                .onTapGesture { if !started && !isOver { started = true } }
            }

            topBar
            if !started && !isOver { startPrompt }
            if isOver { gameOverOverlay }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(clock.$tickCount) { _ in tick() }
        .onAppear { motion.start(); clock.start() }
        .onDisappear { motion.stop(); clock.stop() }
    }

    // MARK: - Render layers

    private var bodyLayer: some View {
        Canvas { ctx, _ in
            guard body.count >= 2 else { return }
            var path = Path()
            path.move(to: body[0])
            for p in body.dropFirst() { path.addLine(to: p) }
            // Soft outer glow, then the bright body on top.
            ctx.stroke(path,
                       with: .color(Color(red: 0.20, green: 0.55, blue: 0.25).opacity(0.55)),
                       style: StrokeStyle(lineWidth: bodyWidth + 6, lineCap: .round, lineJoin: .round))
            ctx.stroke(path,
                       with: .linearGradient(
                            Gradient(colors: [Color(red: 0.45, green: 0.85, blue: 0.40),
                                              Color(red: 0.30, green: 0.72, blue: 0.32)]),
                            startPoint: body.first ?? .zero,
                            endPoint:   body.last ?? .zero),
                       style: StrokeStyle(lineWidth: bodyWidth, lineCap: .round, lineJoin: .round))
        }
    }

    @ViewBuilder
    private var pelletLayer: some View {
        if let pellet {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.35))
                    .frame(width: pelletRadius * 3, height: pelletRadius * 3)
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.45),
                                                  Color(red: 0.95, green: 0.25, blue: 0.30)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: pelletRadius * 2, height: pelletRadius * 2)
                    .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
            }
            .position(pellet)
        }
    }

    private var headMarble: some View {
        Circle()
            .fill(gameState.activeSkin.gradient(endRadius: headRadius * 1.4))
            .frame(width: headRadius * 2, height: headRadius * 2)
            .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.6), radius: 8, x: 2, y: 5)
    }

    // MARK: - HUD / overlays

    private var topBar: some View {
        VStack {
            HStack {
                Button { nav.goHome() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Circle().fill(Color(white: 0.16)))
                }
                Spacer()
                VStack(spacing: 1) {
                    Text("\(score)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("LENGTH")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                        .tracking(1)
                }
                Spacer()
                // Balances the X so the score stays centered.
                Color.clear.frame(width: 38, height: 38)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var startPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "gyroscope")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color(red: 0.45, green: 0.85, blue: 0.40))
            Text("Tilt to play")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Roll into the pellets to grow.\nDon't cross your own body.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
    }

    private var gameOverOverlay: some View {
        let banked = score * coinsPerPellet
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Game Over")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.45, green: 0.85, blue: 0.40))
                    Text("You grew to a length of \(score).")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.65))
                }

                HStack(spacing: 12) {
                    CoinIcon(size: 44)
                        .shadow(color: Color(red: 0.93, green: 0.65, blue: 0.10).opacity(0.5), radius: 10)
                    Text("+\(banked)")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                Text("coins banked")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.30))

                VStack(spacing: 12) {
                    Button { reset(in: arena) } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 0.50, green: 0.88, blue: 0.45)))
                    }
                    Button { nav.goHome() } label: {
                        Text("Home")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(white: 0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 40)
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Lifecycle

    private func reset(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        headPos = CGPoint(x: size.width / 2, y: size.height / 2)
        headVel = .zero
        body = [headPos]
        maxNodes = startSegments
        score = 0
        started = false
        isOver = false
        awarded = false
        spawnPellet(in: size)
    }

    private func endRun() {
        guard !isOver else { return }
        isOver = true
        headVel = .zero
        if !awarded {
            awarded = true
            let banked = score * coinsPerPellet
            if banked > 0 { gameState.addCoins(banked) }
            AnalyticsClient.shared.track(
                "snake_round_over",
                properties: ["length": .int(score), "coins": .int(banked)]
            )
        }
    }

    // MARK: - Simulation

    private func tick() {
        guard started, !isOver else { return }
        let r = headRadius
        guard arena.width >= 2 * r, arena.height >= 2 * r else { return }
        let dt: CGFloat = 1.0 / 60.0

        // Integrate tilt → velocity (same model as the home/climb physics).
        headVel.dx += CGFloat(motion.gravity.x) * accel * dt
        headVel.dy += CGFloat(motion.gravity.y) * accel * dt
        headVel.dx *= friction
        headVel.dy *= friction

        // Clamp top speed so the snake stays steerable.
        let speed = hypot(headVel.dx, headVel.dy)
        if speed > maxSpeed {
            let k = maxSpeed / speed
            headVel.dx *= k
            headVel.dy *= k
        }

        headPos.x += headVel.dx * dt
        headPos.y += headVel.dy * dt

        // Walls bounce (the body is the only fatal hazard).
        if headPos.x < r              { headPos.x = r;              headVel.dx = -headVel.dx * wallBounce }
        if headPos.x > arena.width - r { headPos.x = arena.width - r; headVel.dx = -headVel.dx * wallBounce }
        if headPos.y < r              { headPos.y = r;              headVel.dy = -headVel.dy * wallBounce }
        if headPos.y > arena.height - r { headPos.y = arena.height - r; headVel.dy = -headVel.dy * wallBounce }
        headPos.x = min(max(headPos.x, r), arena.width  - r)
        headPos.y = min(max(headPos.y, r), arena.height - r)

        // Extend the body only when the head has travelled far enough — so
        // sitting still never piles nodes (and never self-collides at rest).
        if let last = body.last {
            if hypot(headPos.x - last.x, headPos.y - last.y) >= segmentStep {
                body.append(headPos)
            } else {
                body[body.count - 1] = headPos   // keep the tip glued to the head
            }
        } else {
            body.append(headPos)
        }
        if body.count > maxNodes {
            body.removeFirst(body.count - maxNodes)
        }

        eatPelletIfReached()
        checkSelfCollision()
    }

    private func eatPelletIfReached() {
        guard let p = pellet else { return }
        if hypot(headPos.x - p.x, headPos.y - p.y) <= headRadius + pelletRadius {
            score += 1
            maxNodes += growPerPellet
            if gameState.hapticsEnabled { Haptics.light() }
            spawnPellet(in: arena)
        }
    }

    private func checkSelfCollision() {
        // Skip the nodes nearest the head — they're always "touching."
        let checkable = body.count - safeSkipNodes
        guard checkable > 0 else { return }
        for i in 0..<checkable {
            let seg = body[i]
            if hypot(headPos.x - seg.x, headPos.y - seg.y) < collideDistance {
                if gameState.hapticsEnabled { Haptics.heavy() }
                endRun()
                return
            }
        }
    }

    private func spawnPellet(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let margin = pelletRadius + 14
        // Try a handful of spots; prefer one clear of the head and body.
        var best: CGPoint = CGPoint(x: size.width / 2, y: size.height / 2)
        var bestClearance: CGFloat = -1
        for _ in 0..<12 {
            let candidate = CGPoint(
                x: CGFloat.random(in: margin...(size.width  - margin)),
                y: CGFloat.random(in: margin...(size.height - margin)))
            var nearest = hypot(candidate.x - headPos.x, candidate.y - headPos.y)
            for seg in body {
                nearest = min(nearest, hypot(candidate.x - seg.x, candidate.y - seg.y))
            }
            if nearest > bestClearance {
                bestClearance = nearest
                best = candidate
            }
            if nearest > bodyWidth * 2 { break }   // good enough
        }
        pellet = best
    }
}

#Preview {
    NavigationStack {
        SnakeGameView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
