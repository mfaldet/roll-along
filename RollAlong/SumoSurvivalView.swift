import SwiftUI

// ===========================================================================
// SumoSurvivalView — the "Sumo Survival" competitive mode.
//
// A sumo dohyo on a round platform floating in the void.  Tilt accelerates
// your marble; shove rivals off the edge.  The rim IS the hazard — any marble
// whose center crosses it falls out.
//
// MATCH FORMAT (Mac's spec):
//   • Exactly FOUR players every match: you + three AI.  No waves.
//   • THREE rounds, the same four players.
//   • Per-round points by fall order: 1st out → 1, 2nd → 2, 3rd → 3,
//     last marble standing → 5.
//   • Fall and you SPECTATE — the round plays on (AI vs AI) until one remains.
//   • After three rounds, total points decide placement → coins:
//     1st 10 · 2nd 5 · 3rd 3 · 4th 2.  Placing 1st is a competitive win.
//
// TILT DUELS: collisions are mass-weighted by how hard each marble is driving
// INTO the contact.  Tilt harder into a rival than they're pushing back and
// you out-muscle them off the ring.  The AI drives gently, so it's beatable.
//
// SAFE BY CONSTRUCTION: an isolated file.  It reuses only the shared physics
// primitives (BallMotion / PhysicsClock), the cosmetics, and the coin economy
// on GameState; it touches nothing in the climb engine.
//
// FEEL IS TUNABLE: every gameplay number lives in the "Tunables" block.
// ===========================================================================

struct SumoSurvivalView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables

    private let marbleRadius: CGFloat = 19
    private let playerAccel:  CGFloat = 1_520     // your tilt → acceleration
    private let aiAccel:      CGFloat = 900       // rival acceleration (≈60% of you — easier)
    private let friction:     CGFloat = 0.992     // marbles glide on the floor
    private let maxSpeed:     CGFloat = 780
    private let restitution:  CGFloat = 0.92      // bounciness of marble hits
    private let platformMargin: CGFloat = 26      // void gap around the platform
    private let shrinkFrac:    CGFloat = 0.42     // ring closes to 58% of full…
    private let shrinkOverTicks     = 35 * 60     // …across ~35s, so rounds resolve
    private let edgePull       = 0.55             // AI retreats from the rim past this × radius (self-preserving)
    private let aiJitter:     CGFloat = 0.16      // radians of aim wobble (imperfect AI)
    private let aiHesitationChance  = 0.10        // chance per tick a rival eases off
    private let aiStrength:   CGFloat = 0.45      // AI's duel "push" (< a firm player tilt of ~0.8–1.0)
    private let pushGain:     CGFloat = 2.4       // how much drive-into-contact adds to collision mass

    private let roundCount     = 3
    private let winnerPoints   = 5
    private let placementCoins = [10, 5, 3, 2]    // 1st…4th by total points

    /// Points for the `orderIndex`-th marble to fall (0-based): 1, 2, 3.
    private func fallPoints(orderIndex: Int) -> Int { orderIndex + 1 }

    // MARK: - Model

    /// A match contestant — persists across all three rounds so points add up.
    private struct Racer: Identifiable {
        let id: UUID
        let isPlayer: Bool
        let color: Color
        var points: Int = 0
    }

    /// A per-round active body.  `id` matches its `Racer.id`.
    private struct Bumper: Identifiable {
        let id: UUID
        var pos: CGPoint
        var vel: CGVector = .zero
        let color: Color
        let isPlayer: Bool
        /// This tick's intended push (unit direction × strength 0…1) — drives
        /// the mass-weighted "tilt duel" in `resolveCollisions`.
        var drive: CGVector = .zero
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

    @State private var roster:  [Racer]  = []     // the 4 contestants (stable across rounds)
    @State private var bumpers: [Bumper] = []     // active this round
    @State private var poofs:   [Poof]   = []
    @State private var rivalLooks: [UUID: RivalCosmetics.Look] = [:]
    @State private var trails:  [UUID: [CGPoint]] = [:]
    @State private var arena:   CGSize = .zero
    @State private var center:  CGPoint = .zero
    @State private var baseRadius: CGFloat = 0
    @State private var radius:  CGFloat = 0        // current (shrunken) ring radius

    @State private var started = false             // round 1 waits for a tap
    @State private var round   = 1
    @State private var roundTicks = 0              // ticks within the current round (drives shrink)
    @State private var fallenThisRound: [UUID] = []  // finishing order this round (fallers, then winner)
    @State private var playerSpectating = false
    @State private var roundOver = false           // between-round overlay
    @State private var matchOver = false           // final results overlay
    @State private var awarded   = false
    @State private var localTick = 0

    // Map cycling (S25)
    @State private var mapIndex   = 0
    @State private var showMapName = false

    // MARK: - Computed

    private var currentPillars: [SumoPillar] {
        SumoMaps.maps[mapIndex % SumoMaps.maps.count].pillars
    }
    private var playerAlive: Bool { bumpers.contains { $0.isPlayer } }

    /// This round's points per racer id, derived from the finishing order.
    private var roundPoints: [UUID: Int] {
        var out: [UUID: Int] = [:]
        let last = fallenThisRound.count - 1
        for (idx, id) in fallenThisRound.enumerated() {
            out[id] = (idx == last) ? winnerPoints : fallPoints(orderIndex: idx)
        }
        return out
    }

    /// Roster sorted best→worst; ties favour the player so a tie for 1st reads
    /// as a win.
    private var rankedRoster: [Racer] {
        roster.sorted { a, b in
            if a.points != b.points { return a.points > b.points }
            if a.isPlayer != b.isPlayer { return a.isPlayer }
            return a.id.uuidString < b.id.uuidString
        }
    }

    private func name(for id: UUID) -> String {
        if roster.first(where: { $0.id == id })?.isPlayer == true { return "YOU" }
        return rivalLooks[id]?.name ?? "Rival"
    }
    private func color(for id: UUID) -> Color {
        roster.first(where: { $0.id == id })?.color ?? .white
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.04).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Color.clear
                    platformLayer
                    pillarsLayer.allowsHitTesting(false)
                    poofLayer.allowsHitTesting(false)
                    trailsLayer.allowsHitTesting(false)
                    ForEach(bumpers) { b in
                        marble(b)
                            .overlay(alignment: .top) {
                                RivalNameTag(label: b.isPlayer ? "YOU" : (rivalLooks[b.id]?.name ?? "Rival"),
                                             color: b.isPlayer ? .white : b.color,
                                             isPlayer: b.isPlayer)
                                    .offset(y: -13).allowsHitTesting(false)
                            }
                            .position(b.pos)
                    }
                }
                .contentShape(Rectangle())
                .onAppear { layout(geo.size); reset() }
                .onChange(of: geo.size) { _, newSize in
                    let wasEmpty = roster.isEmpty
                    layout(newSize)
                    if wasEmpty { reset() }
                }
                .onTapGesture {
                    if !started && !roundOver && !matchOver {
                        started = true
                        AnalyticsClient.shared.track(
                            "sumo_round_started",
                            properties: ["map_name": .string(SumoMaps.maps[mapIndex % SumoMaps.maps.count].name)]
                        )
                    }
                }
            }

            topBar
            if !started && !roundOver && !matchOver { startPrompt }
            if playerSpectating && !roundOver && !matchOver { spectatingBanner }
            if roundOver { roundResultOverlay }
            if matchOver { matchOverOverlay }
            if showMapName && started { mapNameLabel }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(clock.$tickCount) { _ in tick() }
        .onAppear { motion.start(); clock.start() }
        .onDisappear { motion.stop(); clock.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clock.stop(); motion.stop() }
            else if phase == .active && started && !roundOver && !matchOver { clock.start(); motion.start() }
        }
    }

    // MARK: - Render layers

    private var pillarsLayer: some View {
        Canvas { ctx, _ in
            guard radius > 0 else { return }
            for p in currentPillars {
                let cx = center.x + cos(p.angle) * p.radFrac * radius
                let cy = center.y + sin(p.angle) * p.radFrac * radius
                let rect = CGRect(x: cx - p.r, y: cy - p.r, width: p.r * 2, height: p.r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.30)))
                ctx.stroke(Path(ellipseIn: rect),
                           with: .color(Color(red: 0.62, green: 0.30, blue: 0.26).opacity(0.9)),
                           lineWidth: 2.5)
            }
        }
    }

    private var mapNameLabel: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 90)
            Text(SumoMaps.maps[mapIndex % SumoMaps.maps.count].name)
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

    private var platformLayer: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.20), Color(white: 0.12)],
                                 center: .center, startRadius: 0, endRadius: radius))
            .overlay(Circle().stroke(Color(red: 0.62, green: 0.30, blue: 0.26).opacity(0.9), lineWidth: 5))
            .overlay(Circle().stroke(Color(white: 0.32), lineWidth: 1))
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

    private func trailFor(_ b: Bumper) -> TrailColor {
        b.isPlayer ? gameState.equippedTrail : (rivalLooks[b.id]?.trail ?? .none)
    }

    private var trailsLayer: some View {
        Canvas { ctx, _ in
            drawTrails(ctx, bumpers.map { (trails[$0.id] ?? [], trailFor($0)) })
        }
    }

    private func marble(_ b: Bumper) -> some View {
        let skin = b.isPlayer ? gameState.activeSkin : (rivalLooks[b.id]?.skin ?? .red)
        return BallSkinView(skin: skin, diameter: marbleRadius * 2)
            .frame(width: marbleRadius * 2, height: marbleRadius * 2)
            .shadow(color: .black.opacity(0.55), radius: 6, x: 2, y: 4)
    }

    // MARK: - HUD / overlays

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                Button { nav.goHome() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Circle().fill(Color(white: 0.16)))
                }
                .accessibilityIdentifier("SumoCloseButton")
                .accessibilityLabel("Close")
                Spacer()
                Text("ROUND \(min(round, roundCount)) / \(roundCount)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                Spacer()
                // Spacer balance for the close button.
                Color.clear.frame(width: 38, height: 38)
            }
            scoreboardBar
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A compact running scoreboard — the four contestants and their totals.
    private var scoreboardBar: some View {
        HStack(spacing: 8) {
            ForEach(rankedRoster) { r in
                HStack(spacing: 5) {
                    Circle().fill(r.isPlayer ? Color.white : r.color)
                        .frame(width: 9, height: 9)
                    Text(r.isPlayer ? "YOU" : (rivalLooks[r.id]?.name ?? "Rival"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(r.isPlayer ? .white : Color(white: 0.8))
                        .lineLimit(1)
                    Text("\(r.points)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(
                    Capsule().fill(Color(white: r.isPlayer ? 0.22 : 0.13))
                        .overlay(Capsule().stroke(r.isPlayer ? Color.white.opacity(0.5) : .clear, lineWidth: 1))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var spectatingBanner: some View {
        VStack {
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "eye.fill").font(.system(size: 13, weight: .bold))
                Text("You're out — watching the round finish")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .padding(.bottom, 40)
        }
        .allowsHitTesting(false)
    }

    private var startPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color(red: 0.98, green: 0.45, blue: 0.40))
            Text("Tilt to play")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Four marbles, three rounds.\nShove rivals off — last one standing wins the round.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sumo Survival. Four marbles, three rounds. Tilt to shove rivals off the ring; last one standing wins the round. Tap anywhere to begin.")
    }

    /// Between-round results: this round's points + running totals, then a
    /// button into the next round.
    private var roundResultOverlay: some View {
        let rp = roundPoints
        let order = rankedRoster   // show standings after this round
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Round \(round) Complete")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                VStack(spacing: 8) {
                    ForEach(order) { r in
                        standingRow(rank: (order.firstIndex(where: { $0.id == r.id }) ?? 0) + 1,
                                    racer: r, trailing: "+\(rp[r.id] ?? 0)")
                    }
                }
                .padding(.horizontal, 8)

                Button {
                    round += 1
                    startRound()
                    started = true
                    roundOver = false
                } label: {
                    Text("Next Round")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 18)
                            .fill(Color(red: 0.98, green: 0.55, blue: 0.45)))
                }
                .padding(.horizontal, 40)
            }
            .padding(28)
        }
    }

    private var matchOverOverlay: some View {
        let order = rankedRoster
        let playerRank = (order.firstIndex(where: { $0.isPlayer }) ?? 0)
        let playerCoins = placementCoins[min(playerRank, placementCoins.count - 1)]
        let won = playerRank == 0
        return ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(won ? "You Win!" : "Match Over")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(won ? Color(red: 1.00, green: 0.84, blue: 0.30)
                                         : Color(red: 0.98, green: 0.45, blue: 0.40))
                Text(won ? "1st place over three rounds"
                         : "You placed \(ordinal(playerRank + 1)) of 4")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.7))

                VStack(spacing: 8) {
                    ForEach(order) { r in
                        standingRow(rank: (order.firstIndex(where: { $0.id == r.id }) ?? 0) + 1,
                                    racer: r,
                                    trailing: "\(r.points) pts")
                    }
                }
                .padding(.horizontal, 8)

                HStack(spacing: 12) {
                    CoinIcon(size: 40)
                        .shadow(color: Color(red: 0.93, green: 0.65, blue: 0.10).opacity(0.5), radius: 10)
                    Text("+\(playerCoins)")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("You placed \(ordinal(playerRank + 1)). Plus \(playerCoins) coins.")

                VStack(spacing: 10) {
                    Button {
                        mapIndex = (mapIndex + 1) % SumoMaps.maps.count
                        reset()
                    } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 0.98, green: 0.55, blue: 0.45)))
                    }
                    ResultShareButton(result: ShareableResult(
                        mode: "Sumo Survival",
                        headline: won ? "1st place" : "\(ordinal(playerRank + 1)) place",
                        subtitle: "\(order.first(where: { $0.isPlayer })?.points ?? 0) points",
                        skin: gameState.activeSkin,
                        trail: gameState.equippedTrail,
                        won: won))
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
            .padding(24)
        }
    }

    /// One standings row: rank badge · colour dot · name · trailing value.
    private func standingRow(rank: Int, racer r: Racer, trailing: String) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .frame(width: 20)
            Circle().fill(r.isPlayer ? Color.white : r.color).frame(width: 12, height: 12)
            Text(r.isPlayer ? "YOU" : (rivalLooks[r.id]?.name ?? "Rival"))
                .font(.system(size: 16, weight: r.isPlayer ? .black : .semibold, design: .rounded))
                .foregroundStyle(r.isPlayer ? .white : Color(white: 0.82))
            Spacer()
            Text(trailing)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(Color(white: r.isPlayer ? 0.20 : 0.12)))
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"; case 2: return "2nd"; case 3: return "3rd"; default: return "\(n)th"
        }
    }

    // MARK: - Lifecycle

    private func layout(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        arena = size
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        baseRadius = min(size.width, size.height) / 2 - platformMargin
        if radius == 0 { radius = baseRadius }
    }

    /// Start a fresh MATCH: build the four-contestant roster, reset scores, and
    /// lay out round 1 (which waits for a tap to begin).
    private func reset() {
        guard baseRadius > 0 else { return }
        started = false
        matchOver = false
        roundOver = false
        awarded = false
        round = 1
        poofs = []
        radius = baseRadius

        var r: [Racer] = [Racer(id: UUID(), isPlayer: true, color: .white)]
        for i in 0..<3 {
            r.append(Racer(id: UUID(), isPlayer: false,
                           color: Self.rivalColors[i % Self.rivalColors.count]))
        }
        roster = r
        rivalLooks = [:]
        for racer in roster where !racer.isPlayer { rivalLooks[racer.id] = RivalCosmetics.random() }

        startRound()
        showMapName = true
    }

    /// Lay out the current round: player center, three rivals spaced on a ring.
    /// Keeps the roster + scores; clears only per-round state.  Does NOT set
    /// `started` (round 1 waits for a tap; later rounds start from the overlay).
    private func startRound() {
        guard baseRadius > 0 else { return }
        roundOver = false
        playerSpectating = false
        fallenThisRound = []
        roundTicks = 0
        radius = baseRadius
        poofs = []
        trails = [:]

        var fresh: [Bumper] = []
        if let p = roster.first(where: { $0.isPlayer }) {
            fresh.append(Bumper(id: p.id, pos: center, color: p.color, isPlayer: true))
        }
        let ais = roster.filter { !$0.isPlayer }
        let spawnR = baseRadius * 0.62
        for (i, racer) in ais.enumerated() {
            let angle = (Double(i) / Double(max(1, ais.count))) * 2 * .pi - .pi / 2
            let pos = CGPoint(x: center.x + CGFloat(cos(angle)) * spawnR,
                              y: center.y + CGFloat(sin(angle)) * spawnR)
            fresh.append(Bumper(id: racer.id, pos: pos, color: racer.color, isPlayer: false))
        }
        bumpers = fresh
    }

    /// Called when a round resolves (one marble left).  Advances to the next
    /// round or ends the match.
    private func endRound() {
        started = false
        AnalyticsClient.shared.track(
            "sumo_round_over",
            properties: ["round": .int(round),
                         "map_name": .string(SumoMaps.maps[mapIndex % SumoMaps.maps.count].name)]
        )
        if round >= roundCount {
            matchOver = true
            finishMatch()
        } else {
            roundOver = true
        }
        if gameState.hapticsEnabled { Haptics.warning() }
    }

    /// Final placement → coins (10/5/3/2) + a competitive win for 1st.  Guarded
    /// so it pays exactly once.
    private func finishMatch() {
        guard !awarded else { return }
        awarded = true
        let order = rankedRoster
        let playerRank = order.firstIndex(where: { $0.isPlayer }) ?? (order.count - 1)
        let coins = placementCoins[min(playerRank, placementCoins.count - 1)]
        gameState.addCoins(coins)
        if playerRank == 0 { gameState.recordCompetitiveWin("sumo") }
        AnalyticsClient.shared.track(
            "sumo_match_over",
            properties: ["placement": .int(playerRank + 1),
                         "points": .int(order.first(where: { $0.isPlayer })?.points ?? 0),
                         "coins": .int(coins),
                         "map_name": .string(SumoMaps.maps[mapIndex % SumoMaps.maps.count].name)]
        )
    }

    // MARK: - Simulation

    private func tick() {
        localTick &+= 1
        prunePoofs()
        guard started, !roundOver, !matchOver, baseRadius > 0 else { return }
        roundTicks += 1
        updateRing()
        let dt: CGFloat = 1.0 / 60.0

        // 1) Steering / acceleration + this tick's "drive" for the duel model.
        for i in bumpers.indices {
            if bumpers[i].isPlayer {
                let g = CGVector(dx: CGFloat(motion.gravity.x), dy: CGFloat(motion.gravity.y))
                bumpers[i].vel.dx += g.dx * playerAccel * dt
                bumpers[i].vel.dy += g.dy * playerAccel * dt
                bumpers[i].drive = clampedDrive(g)
            } else {
                let r = aiSteer(for: bumpers[i])
                bumpers[i].vel.dx += r.steer.dx * dt
                bumpers[i].vel.dy += r.steer.dy * dt
                bumpers[i].drive = r.drive
            }
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

        // 3) Collisions (mass-weighted by drive — the tilt duel).
        resolveCollisions()
        // 3b) Pillars.
        resolvePillarCollisions()
        // 4) Eliminations + scoring.
        resolveEliminations()

        // 5) Trails.
        let liveIds = Set(bumpers.map(\.id))
        for b in bumpers { recordTrail(&trails, b.id, b.pos) }
        trails = trails.filter { liveIds.contains($0.key) }
    }

    /// Close the ring over the round, down to `1 - shrinkFrac` of full.
    private func updateRing() {
        let progress = min(1, CGFloat(roundTicks) / CGFloat(shrinkOverTicks))
        radius = baseRadius * (1 - shrinkFrac * progress)
    }

    /// Clamp the tilt vector to magnitude ≤ 1 — the player's "push strength".
    private func clampedDrive(_ g: CGVector) -> CGVector {
        let m = hypot(g.dx, g.dy)
        guard m > 1 else { return g }
        return CGVector(dx: g.dx / m, dy: g.dy / m)
    }

    /// Gentle, self-preserving AI: chase the nearest marble with wobbly aim,
    /// retreat from the rim early, and occasionally ease off.  Returns the
    /// acceleration to apply and the duel drive (unit dir × aiStrength).
    private func aiSteer(for b: Bumper) -> (steer: CGVector, drive: CGVector) {
        var target: CGPoint?
        var best = CGFloat.greatestFiniteMagnitude
        for o in bumpers where o.id != b.id {
            let d = hypot(o.pos.x - b.pos.x, o.pos.y - b.pos.y)
            if d < best { best = d; target = o.pos }
        }
        var dir = CGVector(dx: 0, dy: 0)
        if let t = target { dir = unitVec(dx: t.x - b.pos.x, dy: t.y - b.pos.y) }

        // Imperfect aim — wobble the heading a little.
        let wob = CGFloat.random(in: -aiJitter...aiJitter)
        dir = rotate(dir, by: wob)

        // Self-preservation: bias hard toward center when near the rim.
        let fromC = CGVector(dx: b.pos.x - center.x, dy: b.pos.y - center.y)
        let distC = hypot(fromC.dx, fromC.dy)
        if distC > radius * edgePull {
            let inward = unitVec(dx: -fromC.dx, dy: -fromC.dy)
            dir = unitVec(dx: dir.dx * 0.3 + inward.dx * 1.2,
                          dy: dir.dy * 0.3 + inward.dy * 1.2)
        }

        // Occasionally hesitate (ease off) so they don't laser-charge.
        let strength: CGFloat = (Double.random(in: 0..<1) < aiHesitationChance) ? 0.25 : 1.0
        return (CGVector(dx: dir.dx * aiAccel * strength, dy: dir.dy * aiAccel * strength),
                CGVector(dx: dir.dx * aiStrength * strength, dy: dir.dy * aiStrength * strength))
    }

    /// Mass-weighted elastic collisions.  Each marble's mass grows with how
    /// hard it's driving INTO the contact, so whoever pushes harder shoves the
    /// other — the "tilt duel".
    private func resolveCollisions() {
        guard bumpers.count >= 2 else { return }
        let minDist = marbleRadius * 2
        for i in 0..<bumpers.count {
            for j in (i + 1)..<bumpers.count {
                let dx = bumpers[j].pos.x - bumpers[i].pos.x
                let dy = bumpers[j].pos.y - bumpers[i].pos.y
                let dist = hypot(dx, dy)
                guard dist > 0, dist < minDist else { continue }
                let nx = dx / dist, ny = dy / dist     // normal i → j

                // Mass from drive projected into the contact.
                let driveI = max(0, bumpers[i].drive.dx * nx + bumpers[i].drive.dy * ny)
                let driveJ = max(0, bumpers[j].drive.dx * -nx + bumpers[j].drive.dy * -ny)
                let mI = 1 + pushGain * driveI
                let mJ = 1 + pushGain * driveJ
                let totalM = mI + mJ

                // Separate the overlap inversely to mass (heavier moves less).
                let overlap = minDist - dist
                bumpers[i].pos.x -= nx * overlap * (mJ / totalM)
                bumpers[i].pos.y -= ny * overlap * (mJ / totalM)
                bumpers[j].pos.x += nx * overlap * (mI / totalM)
                bumpers[j].pos.y += ny * overlap * (mI / totalM)

                // Normal impulse (unequal mass, restitution).
                let relVel = (bumpers[j].vel.dx - bumpers[i].vel.dx) * nx
                           + (bumpers[j].vel.dy - bumpers[i].vel.dy) * ny
                guard relVel < 0 else { continue }
                let jImp = -(1 + restitution) * relVel / (1 / mI + 1 / mJ)
                bumpers[i].vel.dx -= (jImp / mI) * nx
                bumpers[i].vel.dy -= (jImp / mI) * ny
                bumpers[j].vel.dx += (jImp / mJ) * nx
                bumpers[j].vel.dy += (jImp / mJ) * ny
            }
        }
    }

    /// Eliminate marbles whose center crossed the rim; award fall points in
    /// order, mark the player spectating, and end the round when one remains.
    private func resolveEliminations() {
        guard !bumpers.isEmpty else { return }
        let limit = radius + marbleRadius * 0.3
        var survivors: [Bumper] = []
        var fell: [Bumper] = []
        for b in bumpers {
            let d = hypot(b.pos.x - center.x, b.pos.y - center.y)
            if d > limit { fell.append(b) } else { survivors.append(b) }
        }
        guard !fell.isEmpty else { return }

        if survivors.count >= 1 {
            for b in fell { recordFall(b, winner: false) }
            bumpers = survivors
            if survivors.count == 1, let w = survivors.first {
                recordFall(w, winner: true)
                bumpers = []
                endRound()
            }
        } else {
            // Rare: every remaining marble fell this tick — last one is the winner.
            for (idx, b) in fell.enumerated() {
                recordFall(b, winner: idx == fell.count - 1)
            }
            bumpers = []
            endRound()
        }
    }

    /// Award a marble its finish for this round (fall points by order, or the
    /// winner's 5), record the finishing order, and poof it.
    private func recordFall(_ b: Bumper, winner: Bool) {
        poofs.append(Poof(pos: b.pos, color: b.isPlayer ? .white : b.color, born: localTick))
        let pts = winner ? winnerPoints : fallPoints(orderIndex: fallenThisRound.count)
        if let idx = roster.firstIndex(where: { $0.id == b.id }) { roster[idx].points += pts }
        fallenThisRound.append(b.id)
        if b.isPlayer && !winner { playerSpectating = true }
        if gameState.hapticsEnabled { Haptics.heavy() }
    }

    private func prunePoofs() {
        if !poofs.isEmpty { poofs.removeAll { localTick - $0.born > 26 } }
    }

    // MARK: - Pillar collision (S25)

    private func resolvePillarCollisions() {
        guard radius > 0, !currentPillars.isEmpty else { return }
        for i in bumpers.indices {
            for p in currentPillars {
                let cx = center.x + cos(p.angle) * p.radFrac * radius
                let cy = center.y + sin(p.angle) * p.radFrac * radius
                let dx = bumpers[i].pos.x - cx, dy = bumpers[i].pos.y - cy
                let dist = hypot(dx, dy)
                let minD = marbleRadius + p.r
                guard dist < minD, dist > 0 else { continue }
                let nx = dx / dist, ny = dy / dist
                bumpers[i].pos.x += nx * (minD - dist)
                bumpers[i].pos.y += ny * (minD - dist)
                let dot = bumpers[i].vel.dx * nx + bumpers[i].vel.dy * ny
                guard dot < 0 else { continue }
                bumpers[i].vel.dx -= 2 * dot * nx * restitution
                bumpers[i].vel.dy -= 2 * dot * ny * restitution
            }
        }
    }

    // MARK: - Vector helpers

    private func unitVec(dx: CGFloat, dy: CGFloat) -> CGVector {
        let m = hypot(dx, dy)
        guard m > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: dx / m, dy: dy / m)
    }

    private func rotate(_ v: CGVector, by a: CGFloat) -> CGVector {
        let c = cos(a), s = sin(a)
        return CGVector(dx: v.dx * c - v.dy * s, dy: v.dx * s + v.dy * c)
    }
}

#Preview {
    NavigationStack {
        SumoSurvivalView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
