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

    /// Marble palette — index 0 is always the player (blue).  Now used only as
    /// a thin per-racer identity *rim* (the fill shows the actual ball skin).
    private static let racerColors: [Color] = [
        Color(red: 0.25, green: 0.62, blue: 1.00),   // you — blue
        Color(red: 1.00, green: 0.35, blue: 0.62),   // pink
        Color(red: 0.55, green: 0.86, blue: 0.32),   // green
        Color(red: 1.00, green: 0.60, blue: 0.20),   // orange
    ]

    // Rival looks + nicknames come from the shared RivalCosmetics helper
    // (see Cosmetics.swift) — same pool every competitive view uses.

    // Per-racer home-style trail (the keystone: opponents' trails are visible).
    private let trailMaxLen = 14
    private let trailMinStep: CGFloat = 3

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

    /// Each rival's keystone look (colorIndex → skin+trail+name), dealt in reset().
    /// The player always renders their OWN equipped skin/trail.
    @State private var rivalLooks: [Int: RivalCosmetics.Look] = [:]
    /// Recent positions per racer (colorIndex → points) for the trail layer.
    @State private var trails: [Int: [CGPoint]] = [:]

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
                    trailsLayer.allowsHitTesting(false)
                    ForEach(racers) { r in
                        marble(r)
                            .overlay(alignment: .top) {
                                RivalNameTag(label: r.isPlayer ? "YOU" : (rivalLooks[r.colorIndex]?.name ?? "Rival"),
                                             color: Self.racerColors[r.colorIndex],
                                             isPlayer: r.isPlayer,
                                             isLeader: isLeader(r))
                                    .offset(y: -15).allowsHitTesting(false)
                            }
                            .position(r.pos)
                    }
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
        // NOTE: no accessibilityIdentifier here — the "GoldRushView" anchor
        // lives on the HUD's caps label.  A container identifier propagates
        // to and overwrites every child's identifier (incl. the close button).
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

    /// KEYSTONE — every racer's equipped TRAIL, visible to all: the player's
    /// own, each rival's the one dealt in `reset()`.  Fading home-style streak;
    /// rainbow gets a per-segment hue cycle.
    private var trailsLayer: some View {
        Canvas { ctx, _ in
            for r in racers {
                let pts = trails[r.colorIndex] ?? []
                guard pts.count >= 2 else { continue }
                let trail = trailFor(r)
                guard trail != .none else { continue }
                let rainbow = trail == .rainbow
                let solid = trail.color
                for i in 1..<pts.count {
                    let age = Double(i) / Double(pts.count - 1)
                    let segColor: Color = rainbow
                        ? Color(hue: (Double(i) / Double(pts.count)).truncatingRemainder(dividingBy: 1),
                                saturation: 1, brightness: 1)
                        : solid
                    var path = Path(); path.move(to: pts[i - 1]); path.addLine(to: pts[i])
                    ctx.stroke(path, with: .color(segColor.opacity(0.10 + 0.55 * age)),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    /// The TrailColor a racer renders with — own for the player, dealt for rivals.
    private func trailFor(_ r: GoldRushEngine.Racer) -> TrailColor {
        r.isPlayer ? gameState.equippedTrail : (rivalLooks[r.colorIndex]?.trail ?? .none)
    }

    private func marble(_ r: GoldRushEngine.Racer) -> some View {
        // No per-racer colour highlight — the name tag identifies each ball, so
        // every marble just wears its own skin (same neutral edge as solo play).
        return Circle().fill(skinFor(r).gradient(endRadius: marbleRadius * 1.4))
            .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 1))
            .frame(width: marbleRadius * 2, height: marbleRadius * 2)
            .overlay(alignment: .topLeading) {
                Circle().fill(.white.opacity(0.5))
                    .frame(width: marbleRadius * 0.5, height: marbleRadius * 0.5)
                    .offset(x: marbleRadius * 0.35, y: marbleRadius * 0.35)
            }
            .shadow(color: .black.opacity(0.5), radius: 5, x: 1, y: 3)
    }

    /// The skin a racer renders with — the player's equipped skin, each rival's
    /// dealt showcase skin.
    private func skinFor(_ r: GoldRushEngine.Racer) -> BallSkin {
        r.isPlayer ? gameState.activeSkin : (rivalLooks[r.colorIndex]?.skin ?? .red)
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
                .accessibilityLabel("Close")
                .accessibilityIdentifier("GoldRushCloseButton")  // smoke test exits via this (nav bar is hidden, so no swipe-back)
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
                        .accessibilityIdentifier("GoldRushView")  // smoke-test anchor (leaf, not root — see body note)
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
                    if isLeader(r) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.30))
                    }
                    MiniBall(skin: skinFor(r), size: 14)   // each racer's real ball decal
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

            // Difficulty selector — custom Buttons, NOT a segmented Picker:
            // the arena's full-screen tap-to-start gesture interferes with a
            // UIKit-backed segmented control (that's why selection was stuck on
            // the default).  SwiftUI Buttons consume their own taps cleanly, so
            // they select without starting the round; tapping elsewhere starts.
            Text("Rival difficulty")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.5))
                .padding(.top, 8)
            HStack(spacing: 8) {
                ForEach(MinigameDifficulty.allCases) { d in
                    let selected = gameState.minigameDifficulty == d
                    Button { gameState.minigameDifficulty = d } label: {
                        Text(d.displayName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? .black : Color(white: 0.82))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selected
                                          ? Color(red: 1.0, green: 0.82, blue: 0.30)
                                          : Color(white: 0.18))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
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
                    ResultShareButton(result: ShareableResult(
                        mode: "Coin Pit",   // this view is DISPLAYED as Coin Pit
                        headline: "\(playerScore) coins",
                        subtitle: "\(ordinal(placement)) of \(racers.count)",
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
        dealRivalLooks()                  // keystone: deal each rival a showcase look
        trails.removeAll()                // fresh trails for the new round
        prevPlayerScore = 0
        syncFromEngine()
    }

    /// Deal each AI rival a distinct, desirable look from a shuffled slice of
    /// the showcase pool, so competitive play shows off the catalogue.  (Real
    /// opponents will wear their own equipped gear once multiplayer lands.)
    private func dealRivalLooks() {
        let rivals = engine.racers.filter { !$0.isPlayer }
        rivalLooks = Dictionary(uniqueKeysWithValues:
            zip(rivals.map(\.colorIndex), RivalCosmetics.deal(rivals.count)))
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
        accumulateTrails()
    }

    /// Append each racer's current position to its trail buffer (min-step +
    /// cap) so `trailsLayer` can draw a fading streak behind every marble.
    private func accumulateTrails() {
        for r in engine.racers {
            var pts = trails[r.colorIndex] ?? []
            if let last = pts.last {
                if hypot(r.pos.x - last.x, r.pos.y - last.y) > trailMinStep { pts.append(r.pos) }
            } else {
                pts.append(r.pos)
            }
            if pts.count > trailMaxLen { pts.removeFirst(pts.count - trailMaxLen) }
            trails[r.colorIndex] = pts
        }
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
        if engine.playerWon {
            gameState.addTickets(1)   // Gold Rush ticket — one per competitive win
            AnalyticsClient.shared.track("ticket_earned",
                                         properties: ["source": .string("goldrush")])
        }
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
