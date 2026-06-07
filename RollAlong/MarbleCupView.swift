import SwiftUI

// ===========================================================================
// MarbleCupView — the "Marble Cup" competitive mode (marble soccer / Rocket
// League).
//
// A 90-second 1v1 match on a portrait pitch.  Tilt to accelerate your marble
// and slam a neutral ball into the opponent's goal (the TOP mouth).  The AI
// defends that goal and tries to push the ball into yours (the BOTTOM mouth).
// Most goals when the clock hits zero wins.  Own goals count — mind your
// clearances.
//
// The ball is light and the marbles are heavy, so a solid hit ROCKETS it:
// collisions are mass-weighted (the heavy marble barely flinches, the ball
// flies).  Single-player vs AI — no second device needed.
//
// SAFE BY CONSTRUCTION: a brand-new, isolated file.  It reuses only the shared
// physics primitives (BallMotion / PhysicsClock) and the coin / skin economy on
// GameState; it touches nothing in the climb engine.  Reached only when
// HomeView routes `.mode("marblecup")` here and MarbleCupMode is flagged on.
//
// FEEL IS TUNABLE: every gameplay number lives in the "Tunables" block.
// ===========================================================================

struct MarbleCupView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables

    private let marbleRadius: CGFloat = 18
    private let ballRadius:   CGFloat = 14
    private let playerAccel:  CGFloat = 1_550
    private let aiAccel:      CGFloat = 1_250     // a touch slower than you
    private let marbleFriction: CGFloat = 0.990
    private let ballFriction:   CGFloat = 0.993   // the ball glides further
    private let marbleMaxSpeed: CGFloat = 660
    private let ballMaxSpeed:   CGFloat = 920      // a clean strike rockets it
    private let marbleWallBounce: CGFloat = 0.55
    private let ballWallBounce:   CGFloat = 0.72
    private let marbleMass: CGFloat = 3.2          // heavy — barely flinches
    private let ballMass:   CGFloat = 1.0          // light — gets launched
    private let marbleRestitution: CGFloat = 0.50
    private let ballRestitution:   CGFloat = 0.88
    private let roundSeconds       = 90
    private let goalWidthFrac: CGFloat = 0.42      // goal mouth = 42% of pitch width
    private let celebrateTicks     = 75            // GOAL! freeze (~1.25s, clock paused)
    private let coinsPerGoal       = 6
    private let winBonus           = 15

    private var roundTicks: Int { roundSeconds * 60 }

    private static let playerAccent = Color(red: 0.30, green: 0.62, blue: 1.00)
    private static let aiAccent     = Color(red: 1.00, green: 0.42, blue: 0.42)

    // MARK: - Model

    private enum Role { case player, ai, ball }

    private struct Mover: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector = .zero
        let role: Role
        let radius: CGFloat
        let mass: CGFloat
    }

    // MARK: - State

    @State private var movers: [Mover] = []
    @State private var arena:  CGSize  = .zero
    @State private var field:  CGRect  = .zero

    @State private var playerGoals = 0
    @State private var aiGoals     = 0

    @State private var started    = false
    @State private var isOver     = false
    @State private var playerWon  = false
    @State private var localTick  = 0
    @State private var roundTick  = 0
    @State private var awarded    = false
    @State private var celebrateUntil = 0
    @State private var lastScorerPlayer = false

    private var secondsLeft: Int { max(0, Int(ceil(Double(roundTicks - roundTick) / 60.0))) }
    private var goalHalf: CGFloat { field.width * goalWidthFrac / 2 }
    private var celebrating: Bool { localTick < celebrateUntil }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Color.clear
                    pitch
                    if let ball = movers.first(where: { $0.role == .ball }) {
                        moverView(ball).position(ball.pos)
                    }
                    ForEach(movers.filter { $0.role != .ball }) { m in
                        moverView(m).position(m.pos)
                    }
                }
                .contentShape(Rectangle())
                .onAppear { layout(geo.size); reset() }
                .onChange(of: geo.size) { _, newSize in
                    let wasEmpty = movers.isEmpty
                    layout(newSize)
                    if wasEmpty { reset() }
                }
                .onTapGesture { if !started && !isOver { started = true } }
            }

            topBar
            if celebrating && started && !isOver { goalBanner }
            if !started && !isOver { startPrompt }
            if isOver { matchOverOverlay }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(clock.$tickCount) { _ in tick() }
        .onAppear { motion.start(); clock.start() }
        .onDisappear { motion.stop(); clock.stop() }
    }

    // MARK: - Pitch / markings

    private var pitch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.42, blue: 0.22),
                                              Color(red: 0.12, green: 0.34, blue: 0.18)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: field.width, height: field.height)
                .position(x: field.midX, y: field.midY)
                .shadow(color: .black.opacity(0.5), radius: 14, y: 6)

            Canvas { ctx, _ in
                guard field.width > 0 else { return }
                let line = Color.white.opacity(0.22)
                // halfway line
                var mid = Path()
                mid.move(to: CGPoint(x: field.minX, y: field.midY))
                mid.addLine(to: CGPoint(x: field.maxX, y: field.midY))
                ctx.stroke(mid, with: .color(line), lineWidth: 2)
                // centre circle
                let cr: CGFloat = 46
                ctx.stroke(Path(ellipseIn: CGRect(x: field.midX - cr, y: field.midY - cr,
                                                  width: cr * 2, height: cr * 2)),
                           with: .color(line), lineWidth: 2)
                // goal areas (top + bottom)
                let boxW = goalHalf * 2 + 42
                let boxH: CGFloat = 48
                ctx.stroke(Path(CGRect(x: field.midX - boxW / 2, y: field.minY,
                                       width: boxW, height: boxH)),
                           with: .color(line), lineWidth: 2)
                ctx.stroke(Path(CGRect(x: field.midX - boxW / 2, y: field.maxY - boxH,
                                       width: boxW, height: boxH)),
                           with: .color(line), lineWidth: 2)
            }

            goalMouth(top: true)
            goalMouth(top: false)
        }
    }

    private func goalMouth(top: Bool) -> some View {
        let y = top ? field.minY : field.maxY
        let accent = top ? Self.playerAccent : Self.aiAccent
        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent.opacity(0.55))
                .frame(width: goalHalf * 2, height: 8)
                .position(x: field.midX, y: y)
            Circle().fill(.white).frame(width: 9, height: 9)
                .position(x: field.midX - goalHalf, y: y)
            Circle().fill(.white).frame(width: 9, height: 9)
                .position(x: field.midX + goalHalf, y: y)
        }
    }

    private func moverView(_ m: Mover) -> some View {
        ZStack {
            switch m.role {
            case .ball:
                Circle().fill(RadialGradient(colors: [.white, Color(white: 0.80)],
                                             center: .init(x: 0.36, y: 0.32),
                                             startRadius: 1, endRadius: m.radius * 1.5))
                    .overlay(Circle().stroke(Color(white: 0.55), lineWidth: 1))
            case .player:
                Circle().fill(gameState.activeSkin.gradient(endRadius: m.radius * 1.4))
                    .overlay(Circle().stroke(Self.playerAccent, lineWidth: 3))
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
            case .ai:
                Circle().fill(RadialGradient(colors: [Self.aiAccent, Self.aiAccent.opacity(0.7)],
                                             center: .init(x: 0.35, y: 0.32),
                                             startRadius: 1, endRadius: m.radius * 1.4))
                    .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 0.5))
            }
        }
        .frame(width: m.radius * 2, height: m.radius * 2)
        .overlay(alignment: .topLeading) {
            Circle().fill(.white.opacity(0.5))
                .frame(width: m.radius * 0.5, height: m.radius * 0.5)
                .offset(x: m.radius * 0.3, y: m.radius * 0.3)
        }
        .shadow(color: .black.opacity(0.5), radius: 5, x: 1, y: 3)
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
                scoreboard
                Spacer()
                Color.clear.frame(width: 38, height: 38)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var scoreboard: some View {
        VStack(spacing: 2) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text("\(playerGoals)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(Self.playerAccent)
                        .monospacedDigit()
                    Text("YOU")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.playerAccent.opacity(0.8))
                        .tracking(1)
                }
                Text("–")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.5))
                VStack(spacing: 0) {
                    Text("\(aiGoals)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(Self.aiAccent)
                        .monospacedDigit()
                    Text("CPU")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.aiAccent.opacity(0.8))
                        .tracking(1)
                }
            }
            Text(timeString)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(secondsLeft <= 10 ? Self.aiAccent : Color(white: 0.6))
                .monospacedDigit()
        }
    }

    private var timeString: String {
        String(format: "%d:%02d", secondsLeft / 60, secondsLeft % 60)
    }

    private var goalBanner: some View {
        VStack(spacing: 6) {
            Text("GOAL!")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundStyle(lastScorerPlayer ? Self.playerAccent : Self.aiAccent)
            Text(lastScorerPlayer ? "You scored!" : "CPU scored")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.6), radius: 10)
    }

    private var startPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "soccerball")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white)
            Text("Tilt to play")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Knock the ball into the top goal.\nMost goals in 90 seconds wins.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
    }

    private var matchOverOverlay: some View {
        let banked = playerGoals * coinsPerGoal + (playerWon ? winBonus : 0)
        let title = playerWon ? "You Win!" : (playerGoals == aiGoals ? "Draw" : "You Lose")
        let titleColor: Color = playerWon ? Self.playerAccent
            : (playerGoals == aiGoals ? Color(white: 0.85) : Self.aiAccent)
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(titleColor)
                    Text("\(playerGoals) – \(aiGoals)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
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
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Self.playerAccent))
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
        let side: CGFloat = 10, top: CGFloat = 116, bottom: CGFloat = 44
        field = CGRect(x: side, y: top, width: size.width - side * 2, height: size.height - top - bottom)
    }

    private func reset() {
        guard field.width > 0 else { return }
        started = false
        isOver = false
        playerWon = false
        awarded = false
        roundTick = 0
        playerGoals = 0
        aiGoals = 0
        celebrateUntil = 0
        placeForKickoff()
    }

    /// Ball at centre, marbles back in their halves, all stationary.
    private func placeForKickoff() {
        let p = Mover(pos: CGPoint(x: field.midX, y: field.minY + field.height * 0.72),
                      role: .player, radius: marbleRadius, mass: marbleMass)
        let a = Mover(pos: CGPoint(x: field.midX, y: field.minY + field.height * 0.28),
                      role: .ai, radius: marbleRadius, mass: marbleMass)
        let b = Mover(pos: CGPoint(x: field.midX, y: field.midY),
                      role: .ball, radius: ballRadius, mass: ballMass)
        movers = [p, a, b]
    }

    private func endMatch() {
        guard !isOver else { return }
        isOver = true
        playerWon = playerGoals > aiGoals
        if !awarded {
            awarded = true
            let banked = playerGoals * coinsPerGoal + (playerWon ? winBonus : 0)
            if banked > 0 { gameState.addCoins(banked) }
            AnalyticsClient.shared.track(
                "marblecup_match_over",
                properties: ["won": .bool(playerWon),
                             "goals_for": .int(playerGoals),
                             "goals_against": .int(aiGoals),
                             "coins": .int(banked)]
            )
            if gameState.hapticsEnabled {
                if playerWon { Haptics.success() } else { Haptics.warning() }
            }
        }
    }

    // MARK: - Simulation

    private func tick() {
        localTick &+= 1
        guard started, !isOver, field.width > 0 else { return }
        if celebrating { return }   // GOAL! freeze — clock paused
        roundTick += 1

        guard let bi = movers.firstIndex(where: { $0.role == .ball }) else { return }
        let ballPos = movers[bi].pos
        let dt: CGFloat = 1.0 / 60.0

        for i in movers.indices {
            switch movers[i].role {
            case .player:
                movers[i].vel.dx += CGFloat(motion.gravity.x) * playerAccel * dt
                movers[i].vel.dy += CGFloat(motion.gravity.y) * playerAccel * dt
            case .ai:
                let s = botSteer(movers[i], ballPos: ballPos)
                movers[i].vel.dx += s.dx * dt
                movers[i].vel.dy += s.dy * dt
            case .ball:
                break
            }
            let fr = movers[i].role == .ball ? ballFriction : marbleFriction
            movers[i].vel.dx *= fr
            movers[i].vel.dy *= fr
            let mx = movers[i].role == .ball ? ballMaxSpeed : marbleMaxSpeed
            let sp = hypot(movers[i].vel.dx, movers[i].vel.dy)
            if sp > mx { let k = mx / sp; movers[i].vel.dx *= k; movers[i].vel.dy *= k }
            movers[i].pos.x += movers[i].vel.dx * dt
            movers[i].pos.y += movers[i].vel.dy * dt
            bounceWalls(&movers[i])
        }

        resolveCollisions()
        checkGoal()

        if !isOver && roundTick >= roundTicks { endMatch() }
    }

    /// AI: defend the top goal when the ball is in its third, otherwise line up
    /// behind the ball and shove it toward the bottom goal.
    private func botSteer(_ ai: Mover, ballPos: CGPoint) -> CGVector {
        let topGoal = CGPoint(x: field.midX, y: field.minY)       // AI defends this
        let bottomGoal = CGPoint(x: field.midX, y: field.maxY)    // AI attacks this
        let defThird = field.minY + field.height * 0.36
        let target: CGPoint
        if ballPos.y < defThird {
            target = CGPoint(x: (ballPos.x + topGoal.x) / 2,
                             y: (ballPos.y + topGoal.y) / 2 + 8)
        } else {
            let dir = unit(dx: ballPos.x - bottomGoal.x, dy: ballPos.y - bottomGoal.y, scale: 1)
            target = CGPoint(x: ballPos.x + dir.dx * (ballRadius + marbleRadius * 0.9),
                             y: ballPos.y + dir.dy * (ballRadius + marbleRadius * 0.9))
        }
        return unit(dx: target.x - ai.pos.x, dy: target.y - ai.pos.y, scale: aiAccel)
    }

    private func inMouth(_ x: CGFloat) -> Bool { abs(x - field.midX) <= goalHalf }

    private func bounceWalls(_ m: inout Mover) {
        let r = m.radius
        let wb = m.role == .ball ? ballWallBounce : marbleWallBounce
        if m.pos.x < field.minX + r {
            m.pos.x = field.minX + r; m.vel.dx = -m.vel.dx * wb
        } else if m.pos.x > field.maxX - r {
            m.pos.x = field.maxX - r; m.vel.dx = -m.vel.dx * wb
        }
        // Top wall — the ball passes through the goal mouth (scoring handled later).
        if m.pos.y < field.minY + r {
            if !(m.role == .ball && inMouth(m.pos.x)) {
                m.pos.y = field.minY + r; m.vel.dy = -m.vel.dy * wb
            }
        }
        // Bottom wall — same.
        if m.pos.y > field.maxY - r {
            if !(m.role == .ball && inMouth(m.pos.x)) {
                m.pos.y = field.maxY - r; m.vel.dy = -m.vel.dy * wb
            }
        }
    }

    private func resolveCollisions() {
        guard movers.count >= 2 else { return }
        for i in 0..<movers.count {
            for j in (i + 1)..<movers.count {
                let a = movers[i], b = movers[j]
                let dx = b.pos.x - a.pos.x
                let dy = b.pos.y - a.pos.y
                let dist = hypot(dx, dy)
                let minDist = a.radius + b.radius
                guard dist > 0, dist < minDist else { continue }
                let nx = dx / dist, ny = dy / dist
                let overlap = minDist - dist
                let invA = 1 / a.mass, invB = 1 / b.mass
                let invSum = invA + invB

                // Positional separation, weighted by inverse mass (heavy moves less).
                movers[i].pos.x = a.pos.x - nx * overlap * (invA / invSum)
                movers[i].pos.y = a.pos.y - ny * overlap * (invA / invSum)
                movers[j].pos.x = b.pos.x + nx * overlap * (invB / invSum)
                movers[j].pos.y = b.pos.y + ny * overlap * (invB / invSum)

                let relVel = (b.vel.dx - a.vel.dx) * nx + (b.vel.dy - a.vel.dy) * ny
                guard relVel < 0 else { continue }
                let e = (a.role == .ball || b.role == .ball) ? ballRestitution : marbleRestitution
                let jImp = -(1 + e) * relVel / invSum
                movers[i].vel.dx = a.vel.dx - jImp * invA * nx
                movers[i].vel.dy = a.vel.dy - jImp * invA * ny
                movers[j].vel.dx = b.vel.dx + jImp * invB * nx
                movers[j].vel.dy = b.vel.dy + jImp * invB * ny

                // Satisfying thump when you strike the ball hard.
                let playerHitsBall = (a.role == .player && b.role == .ball)
                                  || (a.role == .ball && b.role == .player)
                if playerHitsBall && -relVel > 240 && gameState.hapticsEnabled {
                    Haptics.medium()
                }
            }
        }
    }

    private func checkGoal() {
        guard let bi = movers.firstIndex(where: { $0.role == .ball }) else { return }
        let bp = movers[bi].pos
        if bp.y < field.minY && inMouth(bp.x) {
            scoreGoal(playerScored: true)
        } else if bp.y > field.maxY && inMouth(bp.x) {
            scoreGoal(playerScored: false)
        }
    }

    private func scoreGoal(playerScored: Bool) {
        if playerScored { playerGoals += 1 } else { aiGoals += 1 }
        lastScorerPlayer = playerScored
        celebrateUntil = localTick + celebrateTicks
        if gameState.hapticsEnabled {
            if playerScored { Haptics.success() } else { Haptics.warning() }
        }
        placeForKickoff()
    }

    private func unit(dx: CGFloat, dy: CGFloat, scale: CGFloat) -> CGVector {
        let m = hypot(dx, dy)
        guard m > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: dx / m * scale, dy: dy / m * scale)
    }
}

#Preview {
    NavigationStack {
        MarbleCupView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
