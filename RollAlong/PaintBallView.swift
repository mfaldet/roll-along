import SwiftUI

// ===========================================================================
// PaintBallView — the "Paint Ball" competitive mode.
//
// A 60-second territory scramble.  Every marble trails its own paint colour as
// it rolls; whoever has the most paint on the floor when the clock hits zero
// wins.  Scattered "puddle" pits freeze any marble that rolls into one for a
// 3-second penalty — no painting, no moving — so positioning matters.
//
// Single-player vs AI (solo-testable): you are the blue painter; three AI
// rivals each chase fresh ground in their own colour.  Coverage is tracked on
// a coarse grid (the source of truth) and rendered as overlapping paint blobs.
//
// SAFE BY CONSTRUCTION: a brand-new, isolated file.  It reuses only the shared
// physics primitives (BallMotion / PhysicsClock) and the coin / skin economy on
// GameState; it touches nothing in the climb engine.  Reached only when
// HomeView routes `.mode("paintball")` here and PaintBallMode is flagged on.
//
// FEEL IS TUNABLE: every gameplay number lives in the "Tunables" block.
// ===========================================================================

struct PaintBallView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables

    private let marbleRadius: CGFloat = 16
    private let playerAccel:  CGFloat = 1_500     // your tilt → acceleration
    private let aiAccelBase:  CGFloat = 1_150     // a touch slower than you
    /// Rival acceleration scaled by the chosen difficulty (Hard == base AI).
    private var aiAccel: CGFloat { aiAccelBase * gameState.minigameDifficulty.aiAccelScale }
    private let friction:     CGFloat = 0.990
    private let maxSpeed:     CGFloat = 620
    private let wallBounce:   CGFloat = 0.70
    private let rivalCount         = 3
    private let roundSeconds       = 60
    private let cellSize:     CGFloat = 24         // paint-grid resolution
    private let paintRadius:  CGFloat = 23         // brush blob radius around a marble
    private let penaltySeconds     = 3             // freeze time on falling in a pit
    private let pitCount           = 6
    private let pitRadius:    CGFloat = 26
    private let graceTicks         = 36            // immunity after climbing out (~0.6s)
    private let retargetTicks      = 50            // how often a bot picks a new goal
    private let winBonus           = 20

    private var colorCount: Int { 1 + rivalCount }
    private var penaltyTicks: Int { penaltySeconds * 60 }
    private var roundTicks:   Int { roundSeconds * 60 }

    /// Paint palette — index 0 is always the player (blue).
    private static let paintColors: [Color] = [
        Color(red: 0.25, green: 0.62, blue: 1.00),   // you — blue
        Color(red: 1.00, green: 0.35, blue: 0.62),   // pink
        Color(red: 0.55, green: 0.86, blue: 0.32),   // green
        Color(red: 1.00, green: 0.60, blue: 0.20),   // orange
    ]

    // MARK: - Model

    private struct Painter: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector = .zero
        let colorIndex: Int
        let isPlayer: Bool
        // AI goal-seeking
        var target: CGPoint = .zero
        var retargetAt: Int = 0
        // penalty state
        var stuckUntil: Int = 0
        var immuneUntil: Int = 0
        var stuckPit: Int = -1
    }

    private struct Pit: Identifiable {
        let id = UUID()
        let pos: CGPoint
        let radius: CGFloat
    }

    private struct Splash: Identifiable {
        let id = UUID()
        let pos: CGPoint
        let color: Color
        let born: Int
    }

    // MARK: - State

    @State private var painters: [Painter] = []
    /// Each rival's keystone look (colorIndex → skin+trail+name), dealt in reset().
    @State private var rivalLooks: [Int: RivalCosmetics.Look] = [:]
    /// Recent positions per painter (colorIndex → points) for the trail layer.
    @State private var trails: [Int: [CGPoint]] = [:]
    @State private var pits:     [Pit]     = []
    @State private var splashes: [Splash]  = []

    @State private var grid:    [Int8] = []     // colour index per cell, -1 = bare
    @State private var paintTick: [Int] = []    // localTick a cell was (re)painted — drives the bloom
    @State private var blocked: [Bool] = []     // cells under a pit — never paintable
    @State private var coverage: [Int] = []     // painted-cell count per colour
    @State private var totalPaintable = 0

    @State private var arena:  CGSize  = .zero
    @State private var center: CGPoint = .zero
    @State private var cols = 0
    @State private var rows = 0
    @State private var cellW: CGFloat = 0
    @State private var cellH: CGFloat = 0

    @State private var started   = false
    @State private var isOver    = false
    @State private var playerWon = false
    @State private var localTick = 0
    @State private var roundTick = 0
    @State private var awarded   = false

    @State private var mapIndex    = 0
    @State private var showMapName = false

    // MARK: - Computed

    private var secondsLeft: Int {
        max(0, Int(ceil(Double(roundTicks - roundTick) / 60.0)))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Color.clear
                    paintLayer.allowsHitTesting(false)
                    pitLayer.allowsHitTesting(false)
                    splashLayer.allowsHitTesting(false)
                    trailsLayer.allowsHitTesting(false)
                    ForEach(painters) { p in
                        marble(p)
                            .overlay(alignment: .top) {
                                RivalNameTag(label: p.isPlayer ? "YOU" : (rivalLooks[p.colorIndex]?.name ?? "Rival"),
                                             color: Self.paintColors[p.colorIndex],
                                             isPlayer: p.isPlayer,
                                             isLeader: isLeader(p))
                                    .offset(y: -15).allowsHitTesting(false)
                            }
                            .position(p.pos)
                    }
                }
                .contentShape(Rectangle())
                .onAppear { layout(geo.size); reset() }
                .onChange(of: geo.size) { _, newSize in
                    let wasEmpty = painters.isEmpty
                    layout(newSize)
                    if wasEmpty { reset() }
                }
                .onTapGesture {
                    if !started && !isOver {
                        started = true
                        AnalyticsClient.shared.track(
                            "paintball_round_started",
                            properties: ["map_name": .string(PaintBallMaps.maps[mapIndex % PaintBallMaps.maps.count].name)]
                        )
                    }
                }
            }

            topBar
            if !started && !isOver { startPrompt }
            if isOver { gameOverOverlay }
            if showMapName && !isOver { mapNameLabel }
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

    /// The painted floor.  Each cell is a blob, but the blobs are accumulated
    /// into ONE path per colour and filled once — so overlapping cells merge
    /// into continuous paint with curvy (arc) edges instead of a seamed dot
    /// grid.  Per-cell jitter (stable hash) breaks up the lattice so the
    /// frontier reads as organic splotches, and each freshly painted cell
    /// "blooms" in (and re-blooms when a rival paints over it).
    private var paintLayer: some View {
        Canvas { ctx, _ in
            guard cols > 0, rows > 0,
                  grid.count == cols * rows, paintTick.count == grid.count else { return }
            let baseRad = max(cellW, cellH) * 0.72
            let bloom   = 12.0   // ticks (~0.2s) for a tile to pop to full size

            var paths = [Path](repeating: Path(), count: colorCount)
            for row in 0..<rows {
                let base   = row * cols
                let cyBase = (CGFloat(row) + 0.5) * cellH
                for col in 0..<cols {
                    let idx = base + col
                    let v = grid[idx]
                    if v < 0 || Int(v) >= colorCount { continue }

                    // Stable per-cell jitter → organic, non-gridded edges.
                    let h = Self.hash2(col, row)
                    let jx = (CGFloat(h & 0xFF)        / 255.0 - 0.5) * cellW * 0.5
                    let jy = (CGFloat(h >> 8  & 0xFF)  / 255.0 - 0.5) * cellH * 0.5
                    let rmul = 0.82 + CGFloat(h >> 16 & 0xFF) / 255.0 * 0.42   // 0.82…1.24

                    // Bloom: scale the blob up from nothing over `bloom` ticks.
                    let t    = max(0, min(1, Double(localTick - paintTick[idx]) / bloom))
                    let rad  = baseRad * rmul * CGFloat(Self.easeOutBack(t))
                    if rad <= 0.3 { continue }

                    let cx = (CGFloat(col) + 0.5) * cellW + jx
                    let cy = cyBase + jy
                    paths[Int(v)].addEllipse(in: CGRect(x: cx - rad, y: cy - rad,
                                                        width: rad * 2, height: rad * 2))
                }
            }
            for i in 0..<colorCount {
                ctx.fill(paths[i], with: .color(Self.paintColors[i].opacity(0.96)))
            }
        }
    }

    @ViewBuilder
    private var pitLayer: some View {
        ForEach(pits) { pit in
            Circle()
                .fill(RadialGradient(colors: [.black, Color(white: 0.05)],
                                     center: .center, startRadius: 0, endRadius: pit.radius))
                .overlay(Circle().stroke(Color(white: 0.22), lineWidth: 2))
                .frame(width: pit.radius * 2, height: pit.radius * 2)
                .position(pit.pos)
                .shadow(color: .black.opacity(0.6), radius: 6)
        }
    }

    @ViewBuilder
    private var splashLayer: some View {
        ForEach(splashes) { s in
            let age = Double(max(0, localTick - s.born)) / 22.0   // 0→1 over ~0.37s
            if age <= 1 {
                Circle()
                    .stroke(s.color.opacity(0.8 * (1 - age)), lineWidth: 4)
                    .frame(width: marbleRadius * 2 * (1 + age * 2.4),
                           height: marbleRadius * 2 * (1 + age * 2.4))
                    .position(s.pos)
            }
        }
    }

    /// The TrailColor a painter renders with — own for the player, dealt for rivals.
    private func trailFor(_ p: Painter) -> TrailColor {
        p.isPlayer ? gameState.equippedTrail : (rivalLooks[p.colorIndex]?.trail ?? .none)
    }

    /// Keystone: each painter's equipped trail — a flair streak, distinct from
    /// the paint coverage that drives scoring.
    private var trailsLayer: some View {
        Canvas { ctx, _ in
            drawTrails(ctx, painters.map { (trails[$0.colorIndex] ?? [], trailFor($0)) })
        }
    }

    /// The current coverage leader — wears the crown.
    private func isLeader(_ p: Painter) -> Bool {
        guard !coverage.isEmpty else { return false }
        var best = 0
        for i in 1..<coverage.count where coverage[i] > coverage[best] { best = i }
        return coverage[best] > 0 && p.colorIndex == best
    }

    private func marble(_ p: Painter) -> some View {
        let stuck = localTick < p.stuckUntil
        let paint = Self.paintColors[p.colorIndex]
        return ZStack {
            if p.isPlayer {
                BallSkinView(skin: gameState.activeSkin, diameter: marbleRadius * 2)
                    .overlay(Circle().stroke(paint, lineWidth: 3))
            } else {
                // Keystone: rival shows off a real ball skin, but keeps a thick
                // PAINT-COLOUR rim — in Paint Ball the colour is the gameplay
                // identity (whose paint is whose), so it must stay legible.
                let skin = rivalLooks[p.colorIndex]?.skin ?? .red
                BallSkinView(skin: skin, diameter: marbleRadius * 2)
                    .overlay(Circle().stroke(paint, lineWidth: 3))
            }
        }
        .frame(width: marbleRadius * 2, height: marbleRadius * 2)
        .opacity(stuck ? 0.5 : 1)
        .overlay {
            if stuck {
                let left = max(1, Int(ceil(Double(p.stuckUntil - localTick) / 60.0)))
                Circle().stroke(paint.opacity(0.9), lineWidth: 3)
                    .frame(width: marbleRadius * 3, height: marbleRadius * 3)
                    .overlay(
                        Text("\(left)")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    )
            }
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
                    Text("PAINT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                        .tracking(2)
                }
                Spacer()
                Color.clear.frame(width: 38, height: 38)
            }
            coverageBar
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var timeString: String {
        let s = secondsLeft
        return String(format: "0:%02d", s)
    }

    private var coverageBar: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(0..<colorCount, id: \.self) { i in
                        Self.paintColors[i]
                            .frame(width: g.size.width * fraction(i))
                    }
                    Color(white: 0.18)   // bare floor remainder
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))

            HStack(spacing: 4) {
                Circle().fill(Self.paintColors[0]).frame(width: 9, height: 9)
                Text("You  \(percent(0))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fraction(_ i: Int) -> CGFloat {
        guard totalPaintable > 0, i < coverage.count else { return 0 }
        return CGFloat(coverage[i]) / CGFloat(totalPaintable)
    }

    private func percent(_ i: Int) -> Int {
        guard totalPaintable > 0, i < coverage.count else { return 0 }
        return Int((Double(coverage[i]) / Double(totalPaintable)) * 100)
    }

    private var mapNameLabel: some View {
        VStack {
            Spacer().frame(height: 98)
            Text(PaintBallMaps.maps[mapIndex % PaintBallMaps.maps.count].name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.60))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color(white: 0.14)))
            Spacer()
        }
        .transition(.opacity)
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) { showMapName = false }
            }
        }
    }

    private var startPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Self.paintColors[0])
            Text("Tilt to play")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Splash the most paint in 60 seconds.\nAvoid the puddles — they freeze you for 3s.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
            MinigameDifficultyPicker(selection: $gameState.minigameDifficulty)
                .padding(.top, 6)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paint Ball. Tilt to splash the most paint in 60 seconds. Avoid enemy puddles — they freeze you for 3 seconds. Tap anywhere to begin.")
    }

    private var gameOverOverlay: some View {
        let pct = percent(0)
        let placement = 1 + coverage.enumerated().filter { $0.offset != 0 && $0.element > coverage[0] }.count
        let banked = gameState.minigamePayout(base: pct + (playerWon ? winBonus : 0),
                                              difficulty: gameState.minigameDifficulty)
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(playerWon ? "You Win!" : "Round Over")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(playerWon
                            ? Self.paintColors[0]
                            : Color(white: 0.85))
                    Text("You painted \(pct)% — \(ordinal(placement)) place")
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
                        mapIndex = (mapIndex + 1) % PaintBallMaps.maps.count
                        reset()
                    } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18)
                                .fill(Self.paintColors[0]))
                    }
                    ResultShareButton(result: ShareableResult(
                        mode: "Paint Ball",
                        headline: "\(pct)% painted",
                        subtitle: "\(ordinal(placement)) of \(painters.count)",
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
        cols = max(1, Int(size.width / cellSize))
        rows = max(1, Int(size.height / cellSize))
        cellW = size.width / CGFloat(cols)
        cellH = size.height / CGFloat(rows)
    }

    private func reset() {
        guard cols > 0, rows > 0 else { return }
        started = false
        isOver = false
        playerWon = false
        awarded = false
        roundTick = 0
        splashes = []

        // Fresh, bare canvas.
        grid = Array(repeating: -1, count: cols * rows)
        paintTick = Array(repeating: 0, count: cols * rows)
        coverage = Array(repeating: 0, count: colorCount)

        loadMapPits(PaintBallMaps.maps[mapIndex % PaintBallMaps.maps.count])
        showMapName = true
        spawnPainters()
    }

    private func loadMapPits(_ map: PaintBallMap) {
        guard cols > 0, rows > 0 else { return }
        pits = map.pitFracs.map { xf, yf in
            Pit(pos: CGPoint(x: arena.width * xf, y: arena.height * yf), radius: pitRadius)
        }
        // Mark every cell under a pit as unpaintable, and tally the rest.
        var b = Array(repeating: false, count: cols * rows)
        for row in 0..<rows {
            let cy = (CGFloat(row) + 0.5) * cellH
            for col in 0..<cols {
                let cx = (CGFloat(col) + 0.5) * cellW
                if pits.contains(where: { hypot(cx - $0.pos.x, cy - $0.pos.y) <= $0.radius }) {
                    b[row * cols + col] = true
                }
            }
        }
        blocked = b
        totalPaintable = b.lazy.filter { !$0 }.count
    }

    private func spawnPainters() {
        var fresh: [Painter] = [Painter(pos: center, colorIndex: 0, isPlayer: true,
                                        immuneUntil: localTick + 45)]
        let ringR = min(arena.width, arena.height) * 0.30
        for i in 0..<rivalCount {
            let angle = (Double(i) / Double(rivalCount)) * 2 * .pi - .pi / 2
            let p = CGPoint(x: center.x + CGFloat(cos(angle)) * ringR,
                            y: center.y + CGFloat(sin(angle)) * ringR)
            fresh.append(Painter(pos: p, colorIndex: i + 1, isPlayer: false,
                                 target: p, immuneUntil: localTick + 45))
        }
        let rivals = fresh.filter { !$0.isPlayer }
        rivalLooks = Dictionary(uniqueKeysWithValues:
            zip(rivals.map(\.colorIndex), RivalCosmetics.deal(rivals.count)))
        trails = [:]
        painters = fresh
    }

    private func endRound() {
        guard !isOver else { return }
        isOver = true
        let top = topColorIndex()
        playerWon = (top == 0)
        if !awarded {
            awarded = true
            let pct = percent(0)
            let base = pct + (playerWon ? winBonus : 0)
            gameState.recordCompetitiveScore("paintball", pct)   // leaderboard best (coverage %)
            // Difficulty scales the payout + records the attempt/win for tracking.
            let banked = gameState.recordMinigameResult(
                modeID: "paintball", difficulty: gameState.minigameDifficulty,
                won: playerWon, basePayout: base)
            AnalyticsClient.shared.track(
                "paintball_round_over",
                properties: ["won": .bool(playerWon),
                             "difficulty": .string(gameState.minigameDifficulty.rawValue),
                             "coverage_pct": .int(pct),
                             "base_coins": .int(base),
                             "coins": .int(banked),
                             "map_name": .string(PaintBallMaps.maps[mapIndex % PaintBallMaps.maps.count].name)]
            )
            if playerWon {
                AnalyticsClient.shared.track("ticket_earned",
                                             properties: ["source": .string("paintball")])
            }
            if gameState.hapticsEnabled {
                if playerWon { Haptics.success() } else { Haptics.warning() }
            }
        }
    }

    private func topColorIndex() -> Int {
        var best = 0
        for i in 1..<coverage.count where coverage[i] > coverage[best] { best = i }
        return best
    }

    // MARK: - Simulation

    private func tick() {
        localTick &+= 1
        pruneSplashes()
        guard started, !isOver, cols > 0 else { return }
        roundTick += 1
        let dt: CGFloat = 1.0 / 60.0

        for i in painters.indices {
            // Frozen: serving a pit penalty — no input, no motion.
            if localTick < painters[i].stuckUntil {
                painters[i].vel = .zero
                continue
            }
            // Just climbed out — pop clear of the pit and grant brief immunity.
            if painters[i].stuckPit >= 0 {
                releaseFromPit(&painters[i])
            }

            // Accelerate.
            if painters[i].isPlayer {
                painters[i].vel.dx += CGFloat(motion.gravity.x) * playerAccel * dt
                painters[i].vel.dy += CGFloat(motion.gravity.y) * playerAccel * dt
            } else {
                steerBot(&painters[i])
            }

            // Friction + speed clamp.
            painters[i].vel.dx *= friction
            painters[i].vel.dy *= friction
            let s = hypot(painters[i].vel.dx, painters[i].vel.dy)
            if s > maxSpeed {
                let k = maxSpeed / s
                painters[i].vel.dx *= k
                painters[i].vel.dy *= k
            }

            // Integrate + bounce off the arena walls.
            painters[i].pos.x += painters[i].vel.dx * dt
            painters[i].pos.y += painters[i].vel.dy * dt
            bounceWalls(&painters[i])
        }

        resolvePits()
        paintPass()

        for p in painters { recordTrail(&trails, p.colorIndex, p.pos) }

        if roundTick >= roundTicks { endRound() }
    }

    private func releaseFromPit(_ p: inout Painter) {
        let pit = pits[p.stuckPit]
        var dir = unit(dx: center.x - pit.pos.x, dy: center.y - pit.pos.y, scale: 1)
        if dir.dx == 0 && dir.dy == 0 { dir = CGVector(dx: 1, dy: 0) }
        p.pos = CGPoint(x: pit.pos.x + dir.dx * (pit.radius + marbleRadius + 3),
                        y: pit.pos.y + dir.dy * (pit.radius + marbleRadius + 3))
        p.vel = .zero
        p.immuneUntil = localTick + graceTicks
        p.stuckPit = -1
    }

    private func steerBot(_ p: inout Painter) {
        if localTick >= p.retargetAt
            || hypot(p.target.x - p.pos.x, p.target.y - p.pos.y) < 40 {
            p.target = pickTarget(for: p)
            p.retargetAt = localTick + retargetTicks
        }
        let dt: CGFloat = 1.0 / 60.0
        let s = unit(dx: p.target.x - p.pos.x, dy: p.target.y - p.pos.y, scale: aiAccel)
        p.vel.dx += s.dx * dt
        p.vel.dy += s.dy * dt
    }

    /// Sample a handful of points and head for the most worthwhile one:
    /// bare floor beats a rival's paint beats the bot's own colour.
    private func pickTarget(for p: Painter) -> CGPoint {
        var best = p.pos
        var bestScore = -1
        let margin: CGFloat = 36
        for _ in 0..<10 {
            let x = CGFloat.random(in: margin...(arena.width - margin))
            let y = CGFloat.random(in: margin...(arena.height - margin))
            if pits.contains(where: { hypot(x - $0.pos.x, y - $0.pos.y) < $0.radius + marbleRadius * 1.5 }) {
                continue
            }
            let col = min(cols - 1, max(0, Int(x / cellW)))
            let row = min(rows - 1, max(0, Int(y / cellH)))
            let v = grid[row * cols + col]
            let worth = (v < 0) ? 2 : (Int(v) == p.colorIndex ? 0 : 1)
            let travel = Int(hypot(x - p.pos.x, y - p.pos.y) / 18)
            let score = worth * 1_000 + travel + Int.random(in: 0...40)
            if score > bestScore { bestScore = score; best = CGPoint(x: x, y: y) }
        }
        return best
    }

    private func bounceWalls(_ p: inout Painter) {
        if p.pos.x < marbleRadius {
            p.pos.x = marbleRadius; p.vel.dx = -p.vel.dx * wallBounce
        } else if p.pos.x > arena.width - marbleRadius {
            p.pos.x = arena.width - marbleRadius; p.vel.dx = -p.vel.dx * wallBounce
        }
        if p.pos.y < marbleRadius {
            p.pos.y = marbleRadius; p.vel.dy = -p.vel.dy * wallBounce
        } else if p.pos.y > arena.height - marbleRadius {
            p.pos.y = arena.height - marbleRadius; p.vel.dy = -p.vel.dy * wallBounce
        }
    }

    private func resolvePits() {
        for i in painters.indices {
            if localTick < painters[i].stuckUntil { continue }   // already frozen
            if localTick < painters[i].immuneUntil { continue }  // just got out
            for (pi, pit) in pits.enumerated() {
                if hypot(painters[i].pos.x - pit.pos.x, painters[i].pos.y - pit.pos.y) < pit.radius {
                    painters[i].pos = pit.pos
                    painters[i].vel = .zero
                    painters[i].stuckUntil = localTick + penaltyTicks
                    painters[i].stuckPit = pi
                    splashes.append(Splash(pos: pit.pos,
                                           color: Self.paintColors[painters[i].colorIndex],
                                           born: localTick))
                    if painters[i].isPlayer && gameState.hapticsEnabled { Haptics.warning() }
                    break
                }
            }
        }
    }

    /// Stamp every moving (non-frozen) marble's brush blob onto the grid.
    /// Copies grid + coverage into locals and writes back once for one redraw.
    private func paintPass() {
        guard grid.count == cols * rows, paintTick.count == grid.count else { return }
        var g = grid
        var cov = coverage
        var pt = paintTick
        var changed = false
        for p in painters {
            if localTick < p.stuckUntil { continue }    // frozen marbles don't paint
            if stamp(&g, &cov, &pt, at: p.pos, color: p.colorIndex) { changed = true }
        }
        if changed { grid = g; coverage = cov; paintTick = pt }
    }

    @discardableResult
    private func stamp(_ g: inout [Int8], _ cov: inout [Int], _ pt: inout [Int],
                       at pos: CGPoint, color: Int) -> Bool {
        let c0 = Int(pos.x / cellW)
        let r0 = Int(pos.y / cellH)
        let span = 2
        var changed = false
        for dr in -span...span {
            let r = r0 + dr
            if r < 0 || r >= rows { continue }
            let cy = (CGFloat(r) + 0.5) * cellH
            for dc in -span...span {
                let c = c0 + dc
                if c < 0 || c >= cols { continue }
                let idx = r * cols + c
                if blocked[idx] { continue }
                let cx = (CGFloat(c) + 0.5) * cellW
                if hypot(cx - pos.x, cy - pos.y) > paintRadius { continue }
                let old = g[idx]
                if Int(old) == color { continue }
                if old >= 0 { cov[Int(old)] -= 1 }
                cov[color] += 1
                g[idx] = Int8(color)
                pt[idx] = localTick        // restart this tile's bloom in the new colour
                changed = true
            }
        }
        return changed
    }

    private func pruneSplashes() {
        if !splashes.isEmpty {
            splashes.removeAll { localTick - $0.born > 24 }
        }
    }

    private func unit(dx: CGFloat, dy: CGFloat, scale: CGFloat) -> CGVector {
        let m = hypot(dx, dy)
        guard m > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: dx / m * scale, dy: dy / m * scale)
    }

    /// Stable per-cell pseudo-random hash → jitter that's fixed for a given
    /// tile (so paint doesn't shimmer frame to frame) but varied across tiles.
    private static func hash2(_ x: Int, _ y: Int) -> UInt {
        var h = UInt(bitPattern: x &* 73_856_093) ^ UInt(bitPattern: y &* 19_349_663)
        h ^= h >> 13; h = h &* 0x9E37_79B1; h ^= h >> 16
        return h
    }

    /// Ease-out with a slight overshoot — gives each tile a "splat" pop as it
    /// blooms in.  0 at t=0, settles to 1 at t=1.
    private static func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158, c3 = 1.70158 + 1.0
        let p = t - 1.0
        return 1.0 + c3 * p * p * p + c1 * p * p
    }
}

#Preview {
    NavigationStack {
        PaintBallView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
