import SwiftUI

// ===========================================================================
// GoldRushView — the competitive coin-scramble mode, DISPLAYED as "Coin Pit"
// (display names swapped with the coinpit mode 2026-06-11; code/id/analytics
// names keep "goldrush").
//
// A 60-second coin scramble.  Coins keep scattering across the floor; roll over
// them to bank them.  Slam into a rival hard enough and they SPILL some of their
// hoard onto the ground for anyone to snatch.  Most coins when the clock hits
// zero wins — and your final count is paid straight into your real balance.
//
// Single-player vs AI (solo-testable): you are the blue marble; three AI rivals
// chase the nearest coin, and one of them ("the bully") likes to ram whoever's
// leading.  No second device needed.
//
// SAFE BY CONSTRUCTION: a brand-new, isolated file.  It reuses only the shared
// physics primitives (BallMotion / PhysicsClock), the coin economy on GameState,
// and the CoinIcon view; it touches nothing in the climb engine.  Reached only
// when HomeView routes `.mode("goldrush")` here and GoldRushMode is flagged on.
//
// SIMULATION LIVES IN GoldRushEngine: this view owns no game logic.  Each frame
// it feeds the engine the accelerometer vector, advances it one tick, mirrors
// its state for rendering, and runs the round-end side effects the engine omits
// (the coin award, analytics, and haptics).  FEEL IS TUNABLE there.
// ===========================================================================

struct GoldRushView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables (rendering + round length; simulation lives in GoldRushEngine)

    private let marbleRadius: CGFloat = 17          // render size; mirrors the engine's collision radius
    private let coinSize:     CGFloat = 20
    private let roundSeconds       = 60

    private var roundTicks: Int { roundSeconds * 60 }

    /// Marble palette — index 0 is always the player (blue).
    private static let racerColors: [Color] = [
        Color(red: 0.25, green: 0.62, blue: 1.00),   // you — blue
        Color(red: 1.00, green: 0.35, blue: 0.62),   // pink
        Color(red: 0.55, green: 0.86, blue: 0.32),   // green
        Color(red: 1.00, green: 0.60, blue: 0.20),   // orange
    ]

    // MARK: - State

    /// The single source of truth for the simulation.  The view feeds it
    /// accelerometer input and renders its state; it owns no game logic.
    @State private var engine = GoldRushEngine(arena: .zero)

    // Per-tick render mirrors — copied from the engine each frame.  Driving the
    // body off these @State arrays is what schedules SwiftUI redraws, while the
    // engine stays a plain (non-Observable) type so PerformanceTests still
    // measures pure simulation cost.
    @State private var racers: [GoldRushEngine.Racer] = []
    @State private var coins:  [GoldRushEngine.Coin]  = []
    @State private var poofs:  [GoldRushEngine.Poof]  = []

    /// Player score at the end of the previous tick — lets the view fire the
    /// in-game coin/ram haptics (which the headless engine omits) from the
    /// score delta.
    @State private var prevPlayerScore = 0

    // Map cycling (S24) — view-side rendering of the same map the engine loads.
    @State private var mapIndex   = 0
    @State private var showMapName = false
    @State private var walls: [WallSegFrac] = []

    // MARK: - Computed (thin forwards onto the engine — the source of truth)

    private var arena: CGSize { engine.arena }
    private var started: Bool { engine.started }
    private var isOver: Bool { engine.isOver }
    private var playerWon: Bool { engine.playerWon }
    private var localTick: Int { engine.localTick }
    private var roundTick: Int { engine.roundTick }
    private var playerScore: Int { engine.playerScore }
    private var maxScore: Int { engine.maxScore }

    private var secondsLeft: Int { max(0, Int(ceil(Double(roundTicks - roundTick) / 60.0))) }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Color.clear
                    floor
                    wallsLayer.allowsHitTesting(false)
                    ForEach(coins) { c in coinView(c) }
                    poofLayer.allowsHitTesting(false)
                    ForEach(racers) { r in marble(r).position(r.pos) }
                }
                .contentShape(Rectangle())
                .onAppear { layout(geo.size); reset() }
                .onChange(of: geo.size) { _, newSize in
                    let wasEmpty = racers.isEmpty
                    layout(newSize)
                    if wasEmpty { reset() }
                }
                .onTapGesture {
                    if !started && !isOver {
                        engine.beginPlay()
                        AnalyticsClient.shared.track(
                            "goldrush_round_started",
                            properties: ["map_name": .string(GoldRushMaps.maps[mapIndex % GoldRushMaps.maps.count].name)]
                        )
                    }
                }
            }

            topBar
            if !started && !isOver { startPrompt }
            if isOver { gameOverOverlay }
            if showMapName && started { mapNameLabel }
        }
        .navigationBarBackButtonHidden(true)
        .accessibilityIdentifier("GoldRushView")  // UI smoke test anchor
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(clock.$tickCount) { _ in tick() }
        .onAppear { motion.start(); clock.start() }
        .onDisappear { motion.stop(); clock.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clock.stop(); motion.stop() }
            else if phase == .active && started && !isOver { clock.start(); motion.start() }
        }
    }

    // MARK: - Render layers

    private var wallsLayer: some View {
        Canvas { ctx, _ in
            guard arena.width > 0 else { return }
            for seg in walls {
                let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
                let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
                var path = Path(); path.move(to: p1); path.addLine(to: p2)
                ctx.stroke(path, with: .color(Color(white: 0.32).opacity(0.9)),
                           style: StrokeStyle(lineWidth: 8, lineCap: .round))
                ctx.stroke(path, with: .color(Color(white: 0.55).opacity(0.5)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    private var floor: some View {
        RadialGradient(colors: [Color(white: 0.11), Color(white: 0.05)],
                       center: .center, startRadius: 0,
                       endRadius: max(arena.width, arena.height) * 0.7)
            .ignoresSafeArea()
    }

    private func coinView(_ c: GoldRushEngine.Coin) -> some View {
        CoinIcon(size: coinSize)
            .scaleEffect(c.popScale)   // stabilises at 1.0 after 8 ticks — no localTick dependency
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .position(c.pos)
    }

    @ViewBuilder
    private var poofLayer: some View {
        ForEach(poofs) { p in
            let age = Double(max(0, localTick - p.born)) / 22.0
            if age <= 1 {
                Circle()
                    .stroke(Self.racerColors[p.colorIndex].opacity(0.8 * (1 - age)), lineWidth: 4)
                    .frame(width: marbleRadius * 2 * (1 + age * 2.2),
                           height: marbleRadius * 2 * (1 + age * 2.2))
                    .position(p.pos)
            }
        }
    }

    private func marble(_ r: GoldRushEngine.Racer) -> some View {
        let paint = Self.racerColors[r.colorIndex]
        return ZStack {
            if r.isPlayer {
                Circle().fill(gameState.activeSkin.gradient(endRadius: marbleRadius * 1.4))
                    .overlay(Circle().stroke(paint, lineWidth: 3))
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
            } else {
                Circle().fill(RadialGradient(
                    colors: [paint, paint.opacity(0.7)],
                    center: .init(x: 0.35, y: 0.32),
                    startRadius: 1, endRadius: marbleRadius * 1.4))
                    .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 0.5))
            }
        }
        .frame(width: marbleRadius * 2, height: marbleRadius * 2)
        .overlay(alignment: .topLeading) {
            Circle().fill(.white.opacity(0.5))
                .frame(width: marbleRadius * 0.5, height: marbleRadius * 0.5)
                .offset(x: marbleRadius * 0.35, y: marbleRadius * 0.35)
        }
        .shadow(color: .black.opacity(0.5), radius: 5, x: 1, y: 3)
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
                Spacer()
                VStack(spacing: 1) {
                    Text(timeString)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(secondsLeft <= 10 ? Color(red: 1.0, green: 0.45, blue: 0.4) : .white)
                        .monospacedDigit()
                    Text("COIN PIT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                        .tracking(2)
                }
                Spacer()
                Color.clear.frame(width: 38, height: 38)
            }
            standingsRow
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var timeString: String { String(format: "0:%02d", secondsLeft) }

    private var standingsRow: some View {
        HStack(spacing: 8) {
            ForEach(racers.sorted { $0.colorIndex < $1.colorIndex }) { r in
                HStack(spacing: 4) {
                    if r.isPlayer {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Self.racerColors[r.colorIndex])
                    } else {
                        Circle().fill(Self.racerColors[r.colorIndex]).frame(width: 10, height: 10)
                    }
                    Text("\(r.score)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isLeader(r) ? Color.white.opacity(0.20) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule().stroke(isLeader(r) ? Self.racerColors[r.colorIndex].opacity(0.9) : .clear,
                                     lineWidth: 1.5)
                )
            }
        }
    }

    private func isLeader(_ r: GoldRushEngine.Racer) -> Bool { maxScore > 0 && r.score == maxScore }

    private var startPrompt: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                Image(systemName: "bag.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.30))
                Text("Tilt to play")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Grab the most coins in 60 seconds.\nRam rivals to knock coins loose.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Coin Pit. Tilt to steer. Grab the most coins in 60 seconds. Ram rivals to knock coins loose. Tap anywhere to begin.")

            // The card sits above the arena's tap-to-start gesture, so
            // adjusting difficulty here never accidentally starts the round.
            Picker("Rival difficulty", selection: $gameState.minigameDifficulty) {
                ForEach(MinigameDifficulty.allCases) { d in
                    Text(d.displayName).tag(d)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 8)
            Text("Rival difficulty")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.5))
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
    }

    private var gameOverOverlay: some View {
        let placement = 1 + racers.filter { !$0.isPlayer && $0.score > playerScore }.count
        let banked = engine.banked
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(playerWon ? "You Win!" : "Round Over")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(playerWon
                            ? Color(red: 1.0, green: 0.82, blue: 0.30)
                            : Color(white: 0.85))
                    Text("You grabbed \(playerScore) coins — \(ordinal(placement)) place")
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Plus \(banked) coins banked")
                Text("coins banked")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.30))
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Button {
                        mapIndex = (mapIndex + 1) % GoldRushMaps.maps.count
                        reset()
                    } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 1.0, green: 0.82, blue: 0.30)))
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

    private var mapNameLabel: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: Layout.mapNameTopInset)
            Text(GoldRushMaps.maps[mapIndex % GoldRushMaps.maps.count].name)
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

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1:  return "1st"
        case 2:  return "2nd"
        case 3:  return "3rd"
        default: return "\(n)th"
        }
    }

    // MARK: - Lifecycle

    private func layout(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        engine.updateArena(size)
    }

    private func reset() {
        guard arena.width > 0 else { return }
        engine.loadMap(index: mapIndex)   // engine's simulation walls (coin spawns avoid them)
        engine.resetBoard()               // fresh board, round left un-started
        loadMap()                         // view's render walls + map-name banner
        prevPlayerScore = 0
        syncFromEngine()
    }

    private func loadMap() {
        walls = GoldRushMaps.maps[mapIndex % GoldRushMaps.maps.count].walls
        showMapName = true
    }

    /// Copy the engine's per-tick state into the view's render mirrors.  The
    /// assignment to these @State arrays is what schedules the next redraw.
    private func syncFromEngine() {
        racers = engine.racers
        coins  = engine.coins
        poofs  = engine.poofs
    }

    /// Round-end side effects the headless engine intentionally omits: pay the
    /// banked coins into the real balance, log analytics, and buzz.
    private func finishRound() {
        let banked = engine.banked
        if banked > 0 { gameState.addCoins(banked) }
        AnalyticsClient.shared.track(
            "goldrush_round_over",
            properties: ["won": .bool(engine.playerWon),
                         "collected": .int(engine.playerScore),
                         "coins": .int(banked),
                         "map_name": .string(GoldRushMaps.maps[mapIndex % GoldRushMaps.maps.count].name)]
        )
        if gameState.hapticsEnabled {
            if engine.playerWon { Haptics.success() } else { Haptics.warning() }
        }
    }

    // MARK: - Per-frame driver

    /// Feed input to the engine, advance it one tick, mirror its state for
    /// rendering, and fire the side effects the engine leaves to the host.
    private func tick() {
        engine.playerInput = CGVector(dx: CGFloat(motion.gravity.x),
                                      dy: CGFloat(motion.gravity.y))
        let difficulty = gameState.minigameDifficulty
        engine.aiAccelScale = difficulty.aiAccelScale
        engine.aiSpeedScale = difficulty.aiSpeedScale
        let wasOver = engine.isOver
        engine.tick()
        syncFromEngine()

        // In-game haptics inferred from the player's score delta: a grab nudges
        // the score up (light), a ram-spill knocks it down (heavy).
        let score = engine.playerScore
        if gameState.hapticsEnabled {
            if score > prevPlayerScore { Haptics.light() }
            else if score < prevPlayerScore { Haptics.heavy() }
        }
        prevPlayerScore = score

        if !wasOver && engine.isOver { finishRound() }
    }
}

#Preview {
    NavigationStack {
        GoldRushView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
