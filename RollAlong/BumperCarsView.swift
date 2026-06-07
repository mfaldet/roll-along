import SwiftUI

// ===========================================================================
// BumperCarsView — the "Bumper Cars" competitive mode.
//
// A sumo arena on a round platform floating in the void.  Tilt accelerates
// your marble; ram the AI rivals off the edge.  The edge IS the hazard — any
// marble whose center crosses the rim falls out.  Last marble standing wins.
//
// SAFE BY CONSTRUCTION: a brand-new, isolated file.  It reuses only the shared
// physics primitives (BallMotion / PhysicsClock) and the coin / skin economy
// on GameState; it touches nothing in the climb engine.  Reached only when
// HomeView routes `.mode("bumper")` here and BumperCarsMode is flagged on.
//
// FEEL IS TUNABLE: every gameplay number lives in the "Tunables" block.
// ===========================================================================

struct BumperCarsView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables

    private let marbleRadius: CGFloat = 19
    private let playerAccel:  CGFloat = 1_520     // your tilt → acceleration
    private let aiAccel:      CGFloat = 1_180     // a touch slower, so you can win
    private let friction:     CGFloat = 0.992     // marbles glide on the floor
    private let maxSpeed:     CGFloat = 760
    private let restitution:  CGFloat = 0.92       // bounciness of marble hits
    private let rivalCount         = 3
    private let platformMargin: CGFloat = 26       // void gap around the platform
    private let edgePull       = 0.62              // AI starts steering home past this × radius
    private let coinsPerKO         = 4
    private let winBonus           = 12

    // MARK: - Model

    private struct Bumper: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector = .zero
        let color: Color
        let isPlayer: Bool
    }

    private struct Poof: Identifiable {
        let id = UUID()
        let pos: CGPoint
        let color: Color
        let born: Int
    }

    private static let rivalColors: [Color] = [
        Color(red: 0.98, green: 0.45, blue: 0.40),
        Color(red: 0.40, green: 0.70, blue: 0.98),
        Color(red: 0.95, green: 0.78, blue: 0.30),
        Color(red: 0.70, green: 0.55, blue: 0.98),
    ]

    // MARK: - State

    @State private var bumpers: [Bumper] = []
    @State private var poofs:   [Poof]   = []
    @State private var arena:   CGSize = .zero
    @State private var center:  CGPoint = .zero
    @State private var radius:  CGFloat = 0

    @State private var started = false
    @State private var isOver  = false
    @State private var playerWon = false
    @State private var eliminatedRivals = 0
    @State private var localTick = 0
    @State private var awarded = false

    private var rivalsAlive: Int { bumpers.filter { !$0.isPlayer }.count }
    private var playerAlive: Bool { bumpers.contains { $0.isPlayer } }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.04).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Color.clear
                    platformLayer
                    poofLayer.allowsHitTesting(false)
                    ForEach(bumpers) { b in
                        marble(b).position(b.pos)
                    }
                }
                .contentShape(Rectangle())
                .onAppear { layout(geo.size); reset() }
                .onChange(of: geo.size) { _, newSize in
                    let wasEmpty = bumpers.isEmpty
                    layout(newSize)
                    if wasEmpty { reset() }
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

    private var platformLayer: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.20), Color(white: 0.12)],
                                 center: .center, startRadius: 0, endRadius: radius))
            .overlay(Circle().stroke(Color(white: 0.32), lineWidth: 4))
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
            .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
    }

    @ViewBuilder
    private var poofLayer: some View {
        ForEach(poofs) { p in
            let age = Double(max(0, localTick - p.born)) / 24.0   // 0→1 over ~0.4s
            if age <= 1 {
                Circle()
                    .stroke(p.color.opacity(0.7 * (1 - age)), lineWidth: 4)
                    .frame(width: marbleRadius * 2 * (1 + age * 2.2),
                           height: marbleRadius * 2 * (1 + age * 2.2))
                    .position(p.pos)
            }
        }
    }

    private func marble(_ b: Bumper) -> some View {
        ZStack {
            if b.isPlayer {
                Circle().fill(gameState.activeSkin.gradient(endRadius: marbleRadius * 1.4))
            } else {
                Circle().fill(RadialGradient(
                    colors: [b.color, b.color.opacity(0.7)],
                    center: .init(x: 0.35, y: 0.32),
                    startRadius: 1, endRadius: marbleRadius * 1.4))
            }
        }
        .frame(width: marbleRadius * 2, height: marbleRadius * 2)
        .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 0.5))
        .overlay(alignment: .topLeading) {
            Circle().fill(.white.opacity(0.5))
                .frame(width: marbleRadius * 0.5, height: marbleRadius * 0.5)
                .offset(x: marbleRadius * 0.35, y: marbleRadius * 0.35)
        }
        .shadow(color: .black.opacity(0.55), radius: 6, x: 2, y: 4)
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
                    Text("\(max(0, bumpers.count))")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("MARBLES LEFT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                        .tracking(1)
                }
                Spacer()
                Color.clear.frame(width: 38, height: 38)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var startPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color(red: 0.98, green: 0.45, blue: 0.40))
            Text("Tilt to play")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Shove the other marbles off the edge.\nLast one on the floor wins.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
    }

    private var gameOverOverlay: some View {
        let banked = eliminatedRivals * coinsPerKO + (playerWon ? winBonus : 0)
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text(playerWon ? "You Win!" : "Knocked Out")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(playerWon
                            ? Color(red: 0.50, green: 0.88, blue: 0.45)
                            : Color(red: 0.98, green: 0.45, blue: 0.40))
                    Text(playerWon
                         ? "Last marble standing."
                         : "You knocked out \(eliminatedRivals) of \(rivalCount).")
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
                    Button { reset() } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 0.98, green: 0.55, blue: 0.45)))
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

    private func layout(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        arena = size
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        radius = min(size.width, size.height) / 2 - platformMargin
    }

    private func reset() {
        guard radius > 0 else { return }
        started = false
        isOver = false
        playerWon = false
        eliminatedRivals = 0
        awarded = false
        poofs = []

        // Player spawns dead center; rivals on a ring around it.
        var fresh: [Bumper] = [Bumper(pos: center, color: .white, isPlayer: true)]
        let spawnR = radius * 0.6
        for i in 0..<rivalCount {
            let angle = (Double(i) / Double(rivalCount)) * 2 * .pi - .pi / 2
            let p = CGPoint(x: center.x + CGFloat(cos(angle)) * spawnR,
                            y: center.y + CGFloat(sin(angle)) * spawnR)
            fresh.append(Bumper(pos: p,
                                color: Self.rivalColors[i % Self.rivalColors.count],
                                isPlayer: false))
        }
        bumpers = fresh
    }

    private func endRun(won: Bool) {
        guard !isOver else { return }
        isOver = true
        playerWon = won
        if !awarded {
            awarded = true
            let banked = eliminatedRivals * coinsPerKO + (won ? winBonus : 0)
            if banked > 0 { gameState.addCoins(banked) }
            AnalyticsClient.shared.track(
                "bumper_round_over",
                properties: ["won": .bool(won),
                             "knockouts": .int(eliminatedRivals),
                             "coins": .int(banked)]
            )
        }
    }

    // MARK: - Simulation

    private func tick() {
        localTick &+= 1
        prunePoofs()
        guard started, !isOver, radius > 0 else { return }
        let dt: CGFloat = 1.0 / 60.0

        // 1) Steering / acceleration.
        for i in bumpers.indices {
            if bumpers[i].isPlayer {
                bumpers[i].vel.dx += CGFloat(motion.gravity.x) * playerAccel * dt
                bumpers[i].vel.dy += CGFloat(motion.gravity.y) * playerAccel * dt
            } else {
                let steer = aiSteer(for: bumpers[i])
                bumpers[i].vel.dx += steer.dx * dt
                bumpers[i].vel.dy += steer.dy * dt
            }
            // friction + speed clamp
            bumpers[i].vel.dx *= friction
            bumpers[i].vel.dy *= friction
            let s = hypot(bumpers[i].vel.dx, bumpers[i].vel.dy)
            if s > maxSpeed {
                let k = maxSpeed / s
                bumpers[i].vel.dx *= k
                bumpers[i].vel.dy *= k
            }
        }

        // 2) Integrate.
        for i in bumpers.indices {
            bumpers[i].pos.x += bumpers[i].vel.dx * dt
            bumpers[i].pos.y += bumpers[i].vel.dy * dt
        }

        // 3) Resolve pairwise collisions (equal mass, elastic w/ restitution).
        resolveCollisions()

        // 4) Eliminate anyone whose center crossed the rim.
        resolveEliminations()
    }

    /// Aim at the nearest other marble, but steer back toward center when near
    /// the rim so rivals don't trivially drive themselves off.
    private func aiSteer(for b: Bumper) -> CGVector {
        var target: CGPoint?
        var best = CGFloat.greatestFiniteMagnitude
        for o in bumpers where o.id != b.id {
            let d = hypot(o.pos.x - b.pos.x, o.pos.y - b.pos.y)
            if d < best { best = d; target = o.pos }
        }
        var steer = CGVector(dx: 0, dy: 0)
        if let t = target {
            steer = unit(dx: t.x - b.pos.x, dy: t.y - b.pos.y, scale: aiAccel)
        }
        let fromCenter = CGVector(dx: b.pos.x - center.x, dy: b.pos.y - center.y)
        let distC = hypot(fromCenter.dx, fromCenter.dy)
        if distC > radius * edgePull {
            let inward = unit(dx: -fromCenter.dx, dy: -fromCenter.dy, scale: aiAccel * 1.4)
            steer = CGVector(dx: steer.dx * 0.35 + inward.dx,
                             dy: steer.dy * 0.35 + inward.dy)
        }
        return steer
    }

    private func resolveCollisions() {
        guard bumpers.count >= 2 else { return }
        let minDist = marbleRadius * 2
        for i in 0..<bumpers.count {
            for j in (i + 1)..<bumpers.count {
                let dx = bumpers[j].pos.x - bumpers[i].pos.x
                let dy = bumpers[j].pos.y - bumpers[i].pos.y
                let dist = hypot(dx, dy)
                guard dist > 0, dist < minDist else { continue }
                let nx = dx / dist, ny = dy / dist
                // Separate the overlap equally.
                let overlap = (minDist - dist) / 2
                bumpers[i].pos.x -= nx * overlap
                bumpers[i].pos.y -= ny * overlap
                bumpers[j].pos.x += nx * overlap
                bumpers[j].pos.y += ny * overlap
                // Elastic impulse along the normal (equal mass).
                let relVel = (bumpers[j].vel.dx - bumpers[i].vel.dx) * nx
                           + (bumpers[j].vel.dy - bumpers[i].vel.dy) * ny
                guard relVel < 0 else { continue }
                let jImp = -(1 + restitution) * relVel / 2
                bumpers[i].vel.dx -= jImp * nx
                bumpers[i].vel.dy -= jImp * ny
                bumpers[j].vel.dx += jImp * nx
                bumpers[j].vel.dy += jImp * ny
            }
        }
    }

    private func resolveEliminations() {
        let limit = radius + marbleRadius * 0.3   // center past the rim = falling
        var survivors: [Bumper] = []
        var playerFell = false
        for b in bumpers {
            let d = hypot(b.pos.x - center.x, b.pos.y - center.y)
            if d > limit {
                poofs.append(Poof(pos: b.pos, color: b.isPlayer ? .white : b.color, born: localTick))
                if b.isPlayer { playerFell = true }
                else { eliminatedRivals += 1 }
                if gameState.hapticsEnabled { Haptics.heavy() }
            } else {
                survivors.append(b)
            }
        }
        if survivors.count != bumpers.count { bumpers = survivors }

        if playerFell {
            endRun(won: false)
        } else if rivalsAlive == 0 {
            endRun(won: true)
        }
    }

    private func prunePoofs() {
        if !poofs.isEmpty {
            poofs.removeAll { localTick - $0.born > 26 }
        }
    }

    private func unit(dx: CGFloat, dy: CGFloat, scale: CGFloat) -> CGVector {
        let m = hypot(dx, dy)
        guard m > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: dx / m * scale, dy: dy / m * scale)
    }
}

#Preview {
    NavigationStack {
        BumperCarsView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
