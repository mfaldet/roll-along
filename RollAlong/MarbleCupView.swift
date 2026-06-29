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
    private let playerAccel:  CGFloat = 1_320     // calmer roll — the match was too hectic
    private let aiAccelBase:  CGFloat = 1_060     // a touch slower than you
    /// Rival acceleration scaled by the chosen difficulty (Hard == base AI).
    private var aiAccel: CGFloat { aiAccelBase * gameState.minigameDifficulty.aiAccelScale }
    private let marbleFriction: CGFloat = 0.990
    private let ballFriction:   CGFloat = 0.993   // the ball glides further
    private let marbleMaxSpeed: CGFloat = 560      // calmer roll (was 660)
    private let ballMaxSpeed:   CGFloat = 830      // a clean strike still rockets it
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

    // Tap-to-dash (speed burst) — mirrored from Smash and Grab, minus the
    // coin-spill: a tap overrides the player marble's velocity to `chargeSpeed`
    // in the tilt direction and lifts its cap for `chargeBoostTicks`, then it's
    // gated for `chargeCooldownTicks` (1.5 s).  AI marbles don't dash.
    private let chargeSpeed:        CGFloat = 720
    private let chargeBoostTicks            = 15
    private let chargeCooldownTicks         = 90    // 1.5 s @ 60 fps

    private var roundTicks: Int { roundSeconds * 60 }

    private static let playerAccent = Color(red: 0.30, green: 0.62, blue: 1.00)
    private static let aiAccent     = Color(red: 1.00, green: 0.42, blue: 0.42)

    // MARK: - Model

    private enum Role { case player, ai, ball }
    /// 1v1 (you vs one CPU) or 2v2 (you + one AI ally vs two AI rivals).
    private enum MatchMode { case oneVone, twoVtwo }

    private struct Mover: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector = .zero
        let role: Role
        let radius: CGFloat
        let mass: CGFloat
        /// Which goal this mover attacks — true = the TOP mouth (the player's
        /// team), false = the BOTTOM mouth (the rival team).  Drives AI steering
        /// and the team tint.  Ignored for the ball.
        var attacksTop: Bool = false
        /// Tap-to-dash state (player only): ticks of active dash + cooldown.
        var charging: Int = 0
        var chargeCD: Int = 0
    }

    // MARK: - State

    @State private var movers: [Mover] = []
    /// Per-AI keystone look (skin+trail+name), keyed by mover id, dealt in
    /// `placeForKickoff()`.  2v2 deals an ally + two rivals.
    @State private var aiLooks: [UUID: RivalCosmetics.Look] = [:]
    /// Chosen on the start screen each match.
    @State private var mode: MatchMode = .oneVone
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
                                RivalNameTag(label: nameTagLabel(m),
                                             color: nameTagColor(m),
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
                    // Tap during play = dash.  Before the match, the start
                    // overlay's 1v1 / 2v2 buttons handle the tap instead.
                    if started && !isOver && !celebrating { firePlayerCharge() }
                }
            }

            topBar
            if started && !isOver { dashIndicator }
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
        case .ai:     return aiLooks[m.id]?.trail ?? .none
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

    /// Every mover on the leading team wears the crown; tie → neither.
    private func isLeader(_ m: Mover) -> Bool {
        guard m.role != .ball else { return false }
        let onPlayerTeam = (m.role == .player) || m.attacksTop
        return onPlayerTeam ? (playerGoals > aiGoals) : (aiGoals > playerGoals)
    }

    /// Name-tag label: YOU, ALLY (an AI on your team), or the rival's dealt name.
    private func nameTagLabel(_ m: Mover) -> String {
        if m.role == .player { return "YOU" }
        if m.attacksTop      { return "ALLY" }
        return aiLooks[m.id]?.name ?? "Rival"
    }

    /// Name-tag tint: you keep your colour, your ally is blue, rivals are red.
    private func nameTagColor(_ m: Mover) -> Color {
        if m.role == .player { return gameState.primaryColor }
        return m.attacksTop ? Self.playerAccent : Self.aiAccent
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
                // Keystone: each AI shows off a real, desirable ball skin.
                BallSkinView(skin: aiLooks[m.id]?.skin ?? .red, diameter: m.radius * 2)
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
                    Text(mode == .twoVtwo ? "TEAM" : "YOU")
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
                    Text(mode == .twoVtwo ? "RIVALS" : "CPU")
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
            Text(lastScorerPlayer
                 ? (mode == .twoVtwo ? "Your team scored!" : "You scored!")
                 : (mode == .twoVtwo ? "Rivals scored" : "CPU scored"))
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
        VStack(spacing: 14) {
            Image(systemName: "soccerball")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white)
            Text("Marble Cup")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Knock the ball into the top goal.\nMost goals in 90 seconds wins.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)

            // Choose the match format — this also starts the match.
            HStack(spacing: 12) {
                modeButton(.oneVone, title: "1 v 1", subtitle: "You vs CPU")
                modeButton(.twoVtwo, title: "2 v 2", subtitle: "You + ally vs 2")
            }

            HStack(spacing: 5) {
                Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                Text("Tap anywhere during play to dash")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Self.playerAccent)

            MinigameDifficultyPicker(selection: $gameState.minigameDifficulty)
                .padding(.top, 2)
        }
        .padding(26)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.62)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Marble Cup. Choose 1 v 1 or 2 v 2 to start. Tilt to knock the ball into the top goal; tap to dash. Most goals in 90 seconds wins.")
    }

    private func modeButton(_ m: MatchMode, title: String, subtitle: String) -> some View {
        Button { startMatch(m) } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.66))
            }
            .frame(width: 132)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(Self.playerAccent.opacity(0.5), lineWidth: 1.5))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
    }

    // MARK: - Dash HUD

    private var playerChargeCD: Int { movers.first(where: { $0.role == .player })?.chargeCD ?? 0 }
    private var dashReady: Bool { started && !isOver && playerChargeCD == 0 }
    private var dashProgress: Double {
        chargeCooldownTicks > 0 ? 1 - Double(playerChargeCD) / Double(chargeCooldownTicks) : 1
    }

    /// A compact bottom-centre pill: bright "TAP TO DASH" when ready, otherwise a
    /// dimmed pill that refills left-to-right over the 1.5 s cooldown.
    private var dashIndicator: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").font(.system(size: 12, weight: .bold))
                Text(dashReady ? "TAP TO DASH" : "DASH")
                    .font(.system(size: 12, weight: .black, design: .rounded)).tracking(1)
            }
            .foregroundStyle(dashReady ? .black : Color(white: 0.7))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.16))
                    GeometryReader { g in
                        Capsule()
                            .fill(dashReady ? Self.playerAccent : Color(white: 0.32))
                            .frame(width: g.size.width * CGFloat(dashProgress))
                    }
                }
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            .padding(.bottom, 34)
            .allowsHitTesting(false)   // taps fall through to the dash gesture
        }
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

    /// Ball at centre, marbles back in their halves, all stationary.  The player
    /// + ally attack the TOP mouth; the rival(s) attack the BOTTOM.
    private func placeForKickoff() {
        let cx = field.midX, w = field.width
        let bottomY = field.minY + field.height * 0.72
        let topY    = field.minY + field.height * 0.28

        // Player always attacks the top goal.
        let playerX = mode == .twoVtwo ? cx + w * 0.15 : cx
        let player = Mover(pos: CGPoint(x: playerX, y: bottomY),
                           role: .player, radius: marbleRadius, mass: marbleMass,
                           attacksTop: true)

        var ais: [Mover] = []
        if mode == .twoVtwo {
            // Ally (player's team) in the bottom half + two rivals up top.
            ais.append(Mover(pos: CGPoint(x: cx - w * 0.18, y: field.minY + field.height * 0.80),
                             role: .ai, radius: marbleRadius, mass: marbleMass, attacksTop: true))
            ais.append(Mover(pos: CGPoint(x: cx - w * 0.15, y: topY),
                             role: .ai, radius: marbleRadius, mass: marbleMass, attacksTop: false))
            ais.append(Mover(pos: CGPoint(x: cx + w * 0.18, y: field.minY + field.height * 0.20),
                             role: .ai, radius: marbleRadius, mass: marbleMass, attacksTop: false))
        } else {
            ais.append(Mover(pos: CGPoint(x: cx, y: topY),
                             role: .ai, radius: marbleRadius, mass: marbleMass, attacksTop: false))
        }

        let ball = Mover(pos: CGPoint(x: cx, y: field.midY),
                         role: .ball, radius: ballRadius, mass: ballMass)
        movers = [player] + ais + [ball]

        // Keystone: deal each AI a showcase look (ally first, then rivals).
        let looks = RivalCosmetics.deal(ais.count)
        var byId: [UUID: RivalCosmetics.Look] = [:]
        for (k, ai) in ais.enumerated() where k < looks.count { byId[ai.id] = looks[k] }
        aiLooks = byId
        trails = [:]
    }

    /// Pick the format and kick off.  (Tapping a start-screen button calls this.)
    private func startMatch(_ m: MatchMode) {
        mode = m
        placeForKickoff()
        started = true
        AnalyticsClient.shared.track(
            "marblecup_match_started",
            properties: ["map_name": .string(MarbleCupMaps.maps[mapIndex % MarbleCupMaps.maps.count].name),
                         "mode": .string(m == .twoVtwo ? "2v2" : "1v1")]
        )
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
            // Tick down the dash window + cooldown (only the player ever sets these).
            if movers[i].charging > 0 { movers[i].charging -= 1 }
            if movers[i].chargeCD  > 0 { movers[i].chargeCD  -= 1 }

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
            // A live dash lifts the player's cap to `chargeSpeed` so it reads.
            let baseMx = movers[i].role == .ball ? ballMaxSpeed : marbleMaxSpeed
            let mx = movers[i].charging > 0 ? max(baseMx, chargeSpeed) : baseMx
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

    /// AI: defend its own goal when the ball is in its defensive third, otherwise
    /// line up behind the ball and shove it toward the goal it attacks.  Works for
    /// both teams via `ai.attacksTop` (top-attackers are the player's ally).
    private func botSteer(_ ai: Mover, ballPos: CGPoint, seed: Int) -> CGVector {
        let attackGoal = CGPoint(x: field.midX, y: ai.attacksTop ? field.minY : field.maxY)
        let defendGoal = CGPoint(x: field.midX, y: ai.attacksTop ? field.maxY : field.minY)
        // The ball is in our defensive third (near the goal we defend)?
        let inDefThird = ai.attacksTop
            ? (ballPos.y > field.maxY - field.height * 0.36)
            : (ballPos.y < field.minY + field.height * 0.36)
        let target: CGPoint
        if inDefThird {
            target = CGPoint(x: (ballPos.x + defendGoal.x) / 2,
                             y: (ballPos.y + defendGoal.y) / 2 + (ai.attacksTop ? -8 : 8))
        } else {
            // Position on the far side of the ball from the attack goal.
            let dir = unit(dx: ballPos.x - attackGoal.x, dy: ballPos.y - attackGoal.y, scale: 1)
            target = CGPoint(x: ballPos.x + dir.dx * (ballRadius + marbleRadius * 0.9),
                             y: ballPos.y + dir.dy * (ballRadius + marbleRadius * 0.9))
        }
        return MinigameAI.humanizedSteer(dx: target.x - ai.pos.x, dy: target.y - ai.pos.y,
                                         scale: aiAccel, seed: seed, tick: localTick,
                                         difficulty: gameState.minigameDifficulty)
    }

    /// Tap-to-dash: override the player marble's velocity to a burst in the tilt
    /// direction (fallback: current heading) and arm the dash window + cooldown.
    private func firePlayerCharge() {
        guard let i = movers.firstIndex(where: { $0.role == .player }),
              movers[i].chargeCD == 0 else { return }
        let aim = CGVector(dx: CGFloat(motion.gravity.x), dy: CGFloat(motion.gravity.y))
        guard let d = chargeDir(aim: aim, fallback: movers[i].vel) else { return }
        movers[i].vel = CGVector(dx: d.dx * chargeSpeed, dy: d.dy * chargeSpeed)
        movers[i].charging = chargeBoostTicks
        movers[i].chargeCD = chargeCooldownTicks
        if gameState.hapticsEnabled { Haptics.medium() }
    }

    /// Unit dash direction: the tilt vector when meaningful, else the marble's
    /// heading, else nil (truly still + level → no dash).
    private func chargeDir(aim: CGVector, fallback vel: CGVector) -> CGVector? {
        let am = hypot(aim.dx, aim.dy)
        if am > 0.05 { return CGVector(dx: aim.dx / am, dy: aim.dy / am) }
        let vm = hypot(vel.dx, vel.dy)
        if vm > 1 { return CGVector(dx: vel.dx / vm, dy: vel.dy / vm) }
        return nil
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
