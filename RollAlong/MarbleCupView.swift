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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables

    private let marbleRadius: CGFloat = 18
    private let ballRadius:   CGFloat = 14
    private let playerAccel:  CGFloat = 1_550
    private let aiAccelBase:  CGFloat = 1_250     // a touch slower than you
    /// Rival acceleration scaled by the chosen difficulty (Hard == base AI).
    private var aiAccel: CGFloat { aiAccelBase * gameState.minigameDifficulty.aiAccelScale }
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
    /// The single AI rival's keystone look (skin+trail+name), dealt in reset().
    @State private var rivalLook: RivalCosmetics.Look?
    /// Recent positions per mover (id → points) for the trail layer (ball excluded).
    @State private var trails: [UUID: [CGPoint]] = [:]
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

    // Map cycling (S26)
    @State private var mapIndex          = 0
    @State private var showMapName       = false
    @State private var currentGoalWidthFrac: CGFloat = 0.42
    @State private var sidePosts:  [(yFrac: CGFloat, side: MarbleCupMap.Side)] = []
    @State private var midBumpers: [PillarFrac] = []

    private let postR: CGFloat = 14          // radius of all side-post bumpers

    // MARK: - Computed

    private var secondsLeft: Int { max(0, Int(ceil(Double(roundTicks - roundTick) / 60.0))) }
    private var goalHalf: CGFloat { field.width * currentGoalWidthFrac / 2 }
    private var celebrating: Bool { localTick < celebrateUntil }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Color.clear
                    pitch
                    trailsLayer.allowsHitTesting(false)
                    if let ball = movers.first(where: { $0.role == .ball }) {
                        moverView(ball).position(ball.pos)
                    }
                    ForEach(movers.filter { $0.role != .ball }) { m in
                        moverView(m)
                            .overlay(alignment: .top) {
                                RivalNameTag(label: m.role == .player ? "YOU" : (rivalLook?.name ?? "Rival"),
                                             color: m.role == .player ? gameState.primaryColor : Self.aiAccent,
                                             isPlayer: m.role == .player,
                                             isLeader: isLeader(m))
                                    .offset(y: -15).allowsHitTesting(false)
                            }
                            .position(m.pos)
                    }
                }
                .contentShape(Rectangle())
                .onAppear { layout(geo.size); reset() }
                .onChange(of: geo.size) { _, newSize in
                    let wasEmpty = movers.isEmpty
                    layout(newSize)
                    if wasEmpty { reset() }
                }
                .onTapGesture {
                    if !started && !isOver {
                        started = true
                        AnalyticsClient.shared.track(
                            "marblecup_match_started",
                            properties: ["map_name": .string(MarbleCupMaps.maps[mapIndex % MarbleCupMaps.maps.count].name)]
                        )
                    }
                }
            }

            topBar
            if celebrating && started && !isOver { goalBanner }
            if !started && !isOver { startPrompt }
            if isOver { matchOverOverlay }
            if showMapName && started { mapNameLabel }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(clock.$tickCount) { _ in tick() }
        .onAppear { motion.start(); clock.start() }
        .onDisappear { motion.stop(); clock.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clock.stop(); motion.stop() }
            else if phase == .active && started && !isOver { clock.start(); motion.start() }
        }
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

                // Side posts and mid bumpers (S26)
                let postFill = Color(white: 0.55).opacity(0.8)
                let postStroke = Color.white.opacity(0.6)
                for sp in sidePosts {
                    let py = field.minY + sp.yFrac * field.height
                    let pxLeft  = field.minX + postR
                    let pxRight = field.maxX - postR
                    let xs: [CGFloat]
                    switch sp.side {
                    case .left:  xs = [pxLeft]
                    case .right: xs = [pxRight]
                    case .both:  xs = [pxLeft, pxRight]
                    }
                    for px in xs {
                        let rect = CGRect(x: px - postR, y: py - postR,
                                          width: postR * 2, height: postR * 2)
                        ctx.fill(Path(ellipseIn: rect), with: .color(postFill))
                        ctx.stroke(Path(ellipseIn: rect), with: .color(postStroke), lineWidth: 2)
                    }
                }
                for mb in midBumpers {
                    let bx = field.minX + mb.cx * field.width
                    let by = field.minY + mb.cy * field.height
                    let rect = CGRect(x: bx - mb.r, y: by - mb.r,
                                      width: mb.r * 2, height: mb.r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.50).opacity(0.85)))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(postStroke), lineWidth: 2)
                }
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

    /// The TrailColor a mover renders with — own for the player, dealt for the
    /// AI rival, none for the neutral ball.
    private func trailFor(_ m: Mover) -> TrailColor {
        switch m.role {
        case .player: return gameState.equippedTrail
        case .ai:     return rivalLook?.trail ?? .none
        case .ball:   return .none
        }
    }

    /// Keystone: the player's own trail + the rival's dealt trail (not the ball).
    private var trailsLayer: some View {
        Canvas { ctx, _ in
            drawTrails(ctx, movers.filter { $0.role != .ball }
                                  .map { (trails[$0.id] ?? [], trailFor($0)) })
        }
    }

    /// The current match leader (more goals) — wears the crown; tie → neither.
    private func isLeader(_ m: Mover) -> Bool {
        switch m.role {
        case .player: return playerGoals > aiGoals
        case .ai:     return aiGoals > playerGoals
        case .ball:   return false
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
                BallSkinView(skin: gameState.activeSkin, diameter: m.radius * 2)
            case .ai:
                // Keystone: the rival shows off a real, desirable ball skin.
                BallSkinView(skin: rivalLook?.skin ?? .red, diameter: m.radius * 2)
            }
        }
        .frame(width: m.radius * 2, height: m.radius * 2)
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

    private var mapNameLabel: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 98)
            Text(MarbleCupMaps.maps[mapIndex % MarbleCupMaps.maps.count].name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.7))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color(white: 0.14)))
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showMapName = false }
                    }
                }
            Spacer()
        }
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
            MinigameDifficultyPicker(selection: $gameState.minigameDifficulty)
                .padding(.top, 6)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Marble Cup. Tilt to knock the ball into the opponent's goal. Most goals in 90 seconds wins. Tap anywhere to begin.")
    }

    private var matchOverOverlay: some View {
        let banked = gameState.minigamePayout(base: playerGoals * coinsPerGoal + (playerWon ? winBonus : 0),
                                              difficulty: gameState.minigameDifficulty)
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Plus \(banked) coins banked")
                Text("coins banked")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.30))
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Button {
                        mapIndex = (mapIndex + 1) % MarbleCupMaps.maps.count
                        reset()
                    } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Self.playerAccent))
                    }
                    ResultShareButton(result: ShareableResult(
                        mode: "Marble Cup",
                        headline: "\(playerGoals) – \(aiGoals)",
                        subtitle: playerWon ? "Marble Cup champ ⚽️"
                                            : (playerGoals == aiGoals ? "Hard-fought draw" : "Good match"),
                        skin: gameState.activeSkin,
                        trail: gameState.equippedTrail,
                        won: playerWon))
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
        loadMap()
        placeForKickoff()
    }

    private func loadMap() {
        let map = MarbleCupMaps.maps[mapIndex % MarbleCupMaps.maps.count]
        currentGoalWidthFrac = map.goalWidthFrac
        sidePosts  = map.sidePosts
        midBumpers = map.midBumpers
        showMapName = true
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
        rivalLook = RivalCosmetics.deal(1).first   // keystone: deal the AI rival a showcase look
        trails = [:]
    }

    private func endMatch() {
        guard !isOver else { return }
        isOver = true
        playerWon = playerGoals > aiGoals
        if !awarded {
            awarded = true
            let base = playerGoals * coinsPerGoal + (playerWon ? winBonus : 0)
            gameState.recordCompetitiveScore("marblecup", playerGoals)   // leaderboard best (goals)
            // Difficulty scales the payout + records the attempt/win for tracking.
            let banked = gameState.recordMinigameResult(
                modeID: "marblecup", difficulty: gameState.minigameDifficulty,
                won: playerWon, score: playerGoals, basePayout: base)
            AnalyticsClient.shared.track(
                "marblecup_match_over",
                properties: ["won": .bool(playerWon),
                             "difficulty": .string(gameState.minigameDifficulty.rawValue),
                             "goals_for": .int(playerGoals),
                             "goals_against": .int(aiGoals),
                             "base_coins": .int(base),
                             "coins": .int(banked),
                             "map_name": .string(MarbleCupMaps.maps[mapIndex % MarbleCupMaps.maps.count].name)]
            )
            if playerWon {
                AnalyticsClient.shared.track("ticket_earned",
                                             properties: ["source": .string("marblecup")])
            }
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
                let s = botSteer(movers[i], ballPos: ballPos, seed: i)
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
        resolveBumperCollisions()
        checkGoal()

        for m in movers where m.role != .ball { recordTrail(&trails, m.id, m.pos) }

        if !isOver && roundTick >= roundTicks { endMatch() }
    }

    /// AI: defend the top goal when the ball is in its third, otherwise line up
    /// behind the ball and shove it toward the bottom goal.
    private func botSteer(_ ai: Mover, ballPos: CGPoint, seed: Int) -> CGVector {
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
        return MinigameAI.humanizedSteer(dx: target.x - ai.pos.x, dy: target.y - ai.pos.y,
                                         scale: aiAccel, seed: seed, tick: localTick,
                                         difficulty: gameState.minigameDifficulty)
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

    // MARK: - Bumper collision (S26)

    /// Resolve collisions between all movers and the current map's side posts + mid bumpers.
    /// All obstacles have infinite mass — only the mover moves.
    private func resolveBumperCollisions() {
        guard field.width > 0 else { return }
        // Build obstacle list: mid bumpers + expanded side-post entries
        var obstacles: [(cx: CGFloat, cy: CGFloat, r: CGFloat)] = []
        for mb in midBumpers {
            obstacles.append((field.minX + mb.cx * field.width,
                               field.minY + mb.cy * field.height, mb.r))
        }
        for sp in sidePosts {
            let py = field.minY + sp.yFrac * field.height
            switch sp.side {
            case .left:  obstacles.append((field.minX + postR, py, postR))
            case .right: obstacles.append((field.maxX - postR, py, postR))
            case .both:
                obstacles.append((field.minX + postR, py, postR))
                obstacles.append((field.maxX - postR, py, postR))
            }
        }
        guard !obstacles.isEmpty else { return }
        for i in movers.indices {
            let e: CGFloat = movers[i].role == .ball ? ballRestitution : marbleRestitution
            for obs in obstacles {
                let dx = movers[i].pos.x - obs.cx, dy = movers[i].pos.y - obs.cy
                let dist = hypot(dx, dy)
                let minD = movers[i].radius + obs.r
                guard dist < minD, dist > 0 else { continue }
                let nx = dx / dist, ny = dy / dist
                movers[i].pos.x += nx * (minD - dist)
                movers[i].pos.y += ny * (minD - dist)
                let dot = movers[i].vel.dx * nx + movers[i].vel.dy * ny
                guard dot < 0 else { continue }
                movers[i].vel.dx -= (1 + e) * dot * nx
                movers[i].vel.dy -= (1 + e) * dot * ny
            }
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
        MarbleCupView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
