import SwiftUI

// ===========================================================================
// GoldRushView — the "Gold Rush" competitive mode.
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
// FEEL IS TUNABLE: every gameplay number lives in the "Tunables" block.
// ===========================================================================

struct GoldRushView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables

    private let marbleRadius: CGFloat = 17
    private let playerAccel:  CGFloat = 1_500
    private let aiAccel:      CGFloat = 1_180
    private let friction:     CGFloat = 0.990
    private let maxSpeed:     CGFloat = 640
    private let wallBounce:   CGFloat = 0.70
    private let restitution:  CGFloat = 0.85
    private let rivalCount         = 3
    private let roundSeconds       = 60
    private let initialCoins       = 12
    private let maxCoins           = 18
    private let spawnEveryTicks    = 20            // a fresh coin ~3×/sec until full
    private let coinSize:     CGFloat = 20
    private let spillImpact:  CGFloat = 360         // closing speed that knocks coins loose
    private let coinsPerSpill      = 3
    private let spillImmunityTicks = 45             // dropper can't instantly re-grab spill
    private let ramSeekRange: CGFloat = 220         // bully only chases a near leader
    private let winBonus           = 15

    private var roundTicks: Int { roundSeconds * 60 }
    private let topReserve: CGFloat = Layout.topReserve  // keep coins/marbles clear of the HUD

    /// Marble palette — index 0 is always the player (blue).
    private static let racerColors: [Color] = [
        Color(red: 0.25, green: 0.62, blue: 1.00),   // you — blue
        Color(red: 1.00, green: 0.35, blue: 0.62),   // pink
        Color(red: 0.55, green: 0.86, blue: 0.32),   // green
        Color(red: 1.00, green: 0.60, blue: 0.20),   // orange
    ]

    // MARK: - Model

    private struct Racer: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector = .zero
        let colorIndex: Int
        let isPlayer: Bool
        let aggro: Bool          // a "bully" rival that rams the leader
        var score: Int = 0
    }

    private struct Coin: Identifiable {
        let id = UUID()
        var pos: CGPoint
        let value: Int
        var ignoreRacer: UUID? = nil    // who can't grab it yet (a fresh spill)
        var ignoreUntil: Int = 0
        let born: Int
        /// Pre-computed spawn-pop scale (0.6 → 1.0 over the first 8 ticks).
        /// Stored in the struct so coinView doesn't depend on `localTick` and
        /// SwiftUI can skip redraws for coins whose scale has stabilised at 1.0.
        var popScale: CGFloat = 0.6
    }

    private struct Poof: Identifiable {
        let id = UUID()
        let pos: CGPoint
        let color: Color
        let born: Int
    }

    // MARK: - State

    @State private var racers: [Racer] = []
    @State private var coins:  [Coin]  = []
    @State private var poofs:  [Poof]  = []

    @State private var arena:  CGSize  = .zero
    @State private var center: CGPoint = .zero

    @State private var started   = false
    @State private var isOver    = false
    @State private var playerWon = false
    @State private var localTick = 0
    @State private var roundTick = 0
    @State private var awarded   = false

    // Map cycling (S24)
    @State private var mapIndex   = 0
    @State private var showMapName = false
    @State private var walls: [WallSegFrac] = []

    // MARK: - Computed

    private var secondsLeft: Int { max(0, Int(ceil(Double(roundTicks - roundTick) / 60.0))) }
    private var playerScore: Int { racers.first { $0.isPlayer }?.score ?? 0 }
    private var maxScore: Int { racers.map(\.score).max() ?? 0 }

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
                        started = true
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

    private func coinView(_ c: Coin) -> some View {
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
                    .stroke(p.color.opacity(0.8 * (1 - age)), lineWidth: 4)
                    .frame(width: marbleRadius * 2 * (1 + age * 2.2),
                           height: marbleRadius * 2 * (1 + age * 2.2))
                    .position(p.pos)
            }
        }
    }

    private func marble(_ r: Racer) -> some View {
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
                    Text("GOLD RUSH")
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

    private func isLeader(_ r: Racer) -> Bool { maxScore > 0 && r.score == maxScore }

    private var startPrompt: some View {
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
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gold Rush. Tilt to steer. Grab the most coins in 60 seconds. Ram rivals to knock coins loose. Tap anywhere to begin.")
    }

    private var gameOverOverlay: some View {
        let placement = 1 + racers.filter { !$0.isPlayer && $0.score > playerScore }.count
        let banked = playerScore + (playerWon ? winBonus : 0)
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
        arena = size
        center = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func reset() {
        guard arena.width > 0 else { return }
        started = false
        isOver = false
        playerWon = false
        awarded = false
        roundTick = 0
        poofs = []
        coins = []

        var fresh: [Racer] = [Racer(pos: center, colorIndex: 0, isPlayer: true, aggro: false)]
        let ringR = min(arena.width, arena.height) * 0.30
        for i in 0..<rivalCount {
            let angle = (Double(i) / Double(rivalCount)) * 2 * .pi - .pi / 2
            let p = CGPoint(x: center.x + CGFloat(cos(angle)) * ringR,
                            y: center.y + CGFloat(sin(angle)) * ringR)
            fresh.append(Racer(pos: p, colorIndex: i + 1, isPlayer: false, aggro: i == 0))
        }
        racers = fresh

        loadMap()
        for _ in 0..<initialCoins { spawnCoin() }
    }

    private func loadMap() {
        walls = GoldRushMaps.maps[mapIndex % GoldRushMaps.maps.count].walls
        showMapName = true
    }

    private func endRound() {
        guard !isOver else { return }
        isOver = true
        playerWon = !racers.contains { !$0.isPlayer && $0.score > playerScore }
        if !awarded {
            awarded = true
            let banked = playerScore + (playerWon ? winBonus : 0)
            if banked > 0 { gameState.addCoins(banked) }
            AnalyticsClient.shared.track(
                "goldrush_round_over",
                properties: ["won": .bool(playerWon),
                             "collected": .int(playerScore),
                             "coins": .int(banked),
                             "map_name": .string(GoldRushMaps.maps[mapIndex % GoldRushMaps.maps.count].name)]
            )
            if gameState.hapticsEnabled {
                if playerWon { Haptics.success() } else { Haptics.warning() }
            }
        }
    }

    // MARK: - Simulation

    private func tick() {
        localTick &+= 1
        prunePoofs()
        guard started, !isOver, arena.width > 0 else { return }
        roundTick += 1

        if coins.count < maxCoins && localTick % spawnEveryTicks == 0 { spawnCoin() }

        // Advance pop scale for coins still in their 8-tick spawn animation.
        // After age 8 popScale is locked at 1.0 — no further mutations, so
        // coinView no longer reads localTick and the coin view can stay stable.
        for i in coins.indices {
            let age = localTick - coins[i].born
            guard age <= 8 else { continue }
            coins[i].popScale = CGFloat(0.6 + 0.4 * Double(age) / 8.0)
        }

        let dt: CGFloat = 1.0 / 60.0
        for i in racers.indices {
            if racers[i].isPlayer {
                racers[i].vel.dx += CGFloat(motion.gravity.x) * playerAccel * dt
                racers[i].vel.dy += CGFloat(motion.gravity.y) * playerAccel * dt
            } else {
                let steer = botSteer(racers[i])
                racers[i].vel.dx += steer.dx * dt
                racers[i].vel.dy += steer.dy * dt
            }
            racers[i].vel.dx *= friction
            racers[i].vel.dy *= friction
            let s = hypot(racers[i].vel.dx, racers[i].vel.dy)
            if s > maxSpeed {
                let k = maxSpeed / s
                racers[i].vel.dx *= k
                racers[i].vel.dy *= k
            }
            racers[i].pos.x += racers[i].vel.dx * dt
            racers[i].pos.y += racers[i].vel.dy * dt
            bounceWalls(&racers[i])
            bounceStaticWalls(&racers[i])
        }

        resolveCollisions()
        collectCoins()

        if roundTick >= roundTicks { endRound() }
    }

    /// Head for the nearest grabbable coin.  A "bully" rival instead chases the
    /// current leader when they're close, to bump coins loose.
    private func botSteer(_ r: Racer) -> CGVector {
        if r.aggro, let leader = leaderToHarass(than: r),
           hypot(leader.pos.x - r.pos.x, leader.pos.y - r.pos.y) < ramSeekRange {
            return unit(dx: leader.pos.x - r.pos.x, dy: leader.pos.y - r.pos.y, scale: aiAccel)
        }
        if let coin = nearestCoin(to: r) {
            return unit(dx: coin.pos.x - r.pos.x, dy: coin.pos.y - r.pos.y, scale: aiAccel)
        }
        // Nothing to chase — drift back toward the middle.
        return unit(dx: center.x - r.pos.x, dy: center.y - r.pos.y, scale: aiAccel * 0.5)
    }

    private func nearestCoin(to r: Racer) -> Coin? {
        var best: Coin?
        var bestD = CGFloat.greatestFiniteMagnitude
        for c in coins {
            if c.ignoreRacer == r.id && localTick < c.ignoreUntil { continue }
            let d = hypot(c.pos.x - r.pos.x, c.pos.y - r.pos.y)
            if d < bestD { bestD = d; best = c }
        }
        return best
    }

    private func leaderToHarass(than r: Racer) -> Racer? {
        var best: Racer?
        for o in racers where o.id != r.id {
            if o.score <= r.score { continue }
            if best == nil || o.score > best!.score { best = o }
        }
        return best
    }

    private func bounceWalls(_ r: inout Racer) {
        bounceEdges(pos: &r.pos, vel: &r.vel,
                    radius: marbleRadius, arena: arena, restitution: wallBounce)
    }

    // MARK: - Static wall collision (S24)

    /// Reflect a marble off interior wall segments.
    private func bounceStaticWalls(_ r: inout Racer) {
        for seg in walls {
            let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
            let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
            resolveWallSegment(pos: &r.pos, vel: &r.vel,
                               p1: p1, p2: p2,
                               radius: marbleRadius, restitution: wallBounce)
        }
    }

    /// True if a coin spawn candidate sits too close to an interior wall.
    private func isNearWall(_ p: CGPoint) -> Bool {
        let margin = marbleRadius + 8
        for seg in walls {
            let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
            let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
            let dx = p2.x - p1.x, dy = p2.y - p1.y
            let lenSq = dx * dx + dy * dy
            guard lenSq > 0 else { continue }
            let t = max(0, min(1, ((p.x - p1.x) * dx + (p.y - p1.y) * dy) / lenSq))
            if hypot(p.x - (p1.x + t * dx), p.y - (p1.y + t * dy)) < margin { return true }
        }
        return false
    }

    private func resolveCollisions() {
        guard racers.count >= 2 else { return }
        let minDist = marbleRadius * 2
        var spilled: [Coin] = []
        for i in 0..<racers.count {
            for j in (i + 1)..<racers.count {
                let dx = racers[j].pos.x - racers[i].pos.x
                let dy = racers[j].pos.y - racers[i].pos.y
                let dist = hypot(dx, dy)
                guard dist > 0, dist < minDist else { continue }
                let nx = dx / dist, ny = dy / dist
                let overlap = (minDist - dist) / 2
                racers[i].pos.x -= nx * overlap
                racers[i].pos.y -= ny * overlap
                racers[j].pos.x += nx * overlap
                racers[j].pos.y += ny * overlap

                let relVel = (racers[j].vel.dx - racers[i].vel.dx) * nx
                           + (racers[j].vel.dy - racers[i].vel.dy) * ny
                guard relVel < 0 else { continue }

                // Capture pre-impact speeds to decide who got run into.
                let si = hypot(racers[i].vel.dx, racers[i].vel.dy)
                let sj = hypot(racers[j].vel.dx, racers[j].vel.dy)

                let jImp = -(1 + restitution) * relVel / 2
                racers[i].vel.dx -= jImp * nx
                racers[i].vel.dy -= jImp * ny
                racers[j].vel.dx += jImp * nx
                racers[j].vel.dy += jImp * ny

                // Hard hit → the slower (hittee) spills some coins.
                if -relVel > spillImpact {
                    let hit = si <= sj ? i : j
                    let k = min(coinsPerSpill, racers[hit].score)
                    if k > 0 {
                        racers[hit].score -= k
                        for _ in 0..<k { spilled.append(makeSpill(at: racers[hit].pos, by: racers[hit].id)) }
                        poofs.append(Poof(pos: racers[hit].pos,
                                          color: Self.racerColors[racers[hit].colorIndex],
                                          born: localTick))
                        if racers[hit].isPlayer && gameState.hapticsEnabled { Haptics.heavy() }
                    }
                }
            }
        }
        if !spilled.isEmpty { coins.append(contentsOf: spilled) }
    }

    private func collectCoins() {
        guard !coins.isEmpty else { return }
        let grab = marbleRadius + 10
        var remaining: [Coin] = []
        for c in coins {
            var taken = false
            for i in racers.indices {
                if c.ignoreRacer == racers[i].id && localTick < c.ignoreUntil { continue }
                if hypot(racers[i].pos.x - c.pos.x, racers[i].pos.y - c.pos.y) < grab {
                    racers[i].score += c.value
                    if racers[i].isPlayer && gameState.hapticsEnabled { Haptics.light() }
                    taken = true
                    break
                }
            }
            if !taken { remaining.append(c) }
        }
        if remaining.count != coins.count { coins = remaining }
    }

    private func spawnCoin() {
        guard arena.width > 0 else { return }
        let margin: CGFloat = 34
        for _ in 0..<8 {
            let x = CGFloat.random(in: margin...(arena.width - margin))
            let y = CGFloat.random(in: topReserve...(arena.height - margin))
            let pt = CGPoint(x: x, y: y)
            if racers.contains(where: { hypot($0.pos.x - x, $0.pos.y - y) < marbleRadius * 2 }) { continue }
            if isNearWall(pt) { continue }
            coins.append(Coin(pos: pt, value: 1, born: localTick))
            return
        }
    }

    private func makeSpill(at pos: CGPoint, by who: UUID) -> Coin {
        let angle = Double.random(in: 0..<(2 * .pi))
        let r = CGFloat.random(in: 18...34)
        var p = CGPoint(x: pos.x + CGFloat(cos(angle)) * r, y: pos.y + CGFloat(sin(angle)) * r)
        p.x = min(max(marbleRadius, p.x), arena.width - marbleRadius)
        p.y = min(max(topReserve, p.y), arena.height - marbleRadius)
        return Coin(pos: p, value: 1, ignoreRacer: who, ignoreUntil: localTick + spillImmunityTicks, born: localTick)
    }

    private func prunePoofs() {
        if !poofs.isEmpty { poofs.removeAll { localTick - $0.born > 24 } }
    }

    private func unit(dx: CGFloat, dy: CGFloat, scale: CGFloat) -> CGVector {
        let m = hypot(dx, dy)
        guard m > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: dx / m * scale, dy: dy / m * scale)
    }
}

#Preview {
    NavigationStack {
        GoldRushView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
