import SwiftUI

// ===========================================================================
// DiscoBallView — "Disco Ball", a memorization + coordination game.
//
// LAYOUT
//   • Top and bottom 1/8 of the screen are SAFE ZONES.
//   • The middle 3/4 is a grid of tiles (cols × rows).
//
// FLOW (one round)
//   1. MEMORIZE — the ball is locked inside the current safe zone (tilt to roll
//      around freely). A light pattern marches along a linear path of tiles that
//      links this safe zone to the far one, repeating until you tap.
//   2. CROSS — tapping stops the reveal and frees the ball. Roll across: each
//      correct (on-path) tile you touch lights GREEN and stays lit. Touch any
//      tile that isn't on the path and every tile blinks RED — the run is over.
//   3. CELEBRATE — reach the far safe zone and the whole floor blinks random
//      disco colours for a beat, your crossing count ticks up, then the next
//      path is revealed from the new safe zone (back the other way).
//
// SCORE: total crossings (back and forth). Best is tracked like Pinball / Roll
// Up via `minigameBests["disco"]`. ECONOMY: no life cost (pure score attack);
// coins scale with crossings. Reached only when HomeView routes `.mode("disco")`.
//
// SAFE BY CONSTRUCTION: brand-new isolated file; reuses only BallMotion /
// PhysicsClock, the coin economy, BallSkinView, CoinIcon, and ResultShareButton.
// ===========================================================================

struct DiscoBallView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables
    private let cols = 5
    private let rows = 6
    private let ballRadius:  CGFloat = 13
    private let moveAccel:   CGFloat = 1_500
    private let friction:    CGFloat = 0.94
    private let maxSpeed:    CGFloat = 700
    private let wallBounce:  CGFloat = 0.45
    private let revealSpeed:  Double = 0.14        // path-reveal head, tiles/tick
    private let celebrateDuration: TimeInterval = 2.6
    private let failDuration:      TimeInterval = 1.4
    private static let coinsPerCrossing = 3

    // MARK: - Palette
    private static let tileOff     = Color(white: 0.13)
    private static let tileEdge    = Color(white: 0.20)
    private static let revealColor = Color(red: 0.32, green: 0.85, blue: 1.00)   // cyan path
    private static let greenLit    = Color(red: 0.25, green: 0.90, blue: 0.46)
    private static let safeFill    = Color(red: 0.16, green: 0.16, blue: 0.22)

    // MARK: - Model
    private struct GridPos: Hashable { let row: Int; let col: Int }
    private enum Phase { case memorize, crossing, celebrate, failed, gameOver }

    // MARK: - State
    @State private var arena: CGSize = .zero
    @State private var phase: Phase = .memorize
    @State private var atBottom = true             // current safe zone
    @State private var crossings = 0
    @State private var startedEver = false         // controls the intro hint

    @State private var ball: CGPoint = .zero
    @State private var vel: CGVector = .zero

    @State private var pathOrder: [GridPos] = []
    @State private var pathSet:   Set<GridPos> = []
    @State private var pathIndex: [GridPos: Int] = [:]
    @State private var touched:   Set<GridPos> = []
    @State private var revealHead: Double = 0
    @State private var phaseEndAt: Date? = nil
    @State private var blinkFrame = 0

    // MARK: - Derived geometry
    private var safeH:      CGFloat { arena.height / 8 }
    private var gridTop:    CGFloat { safeH }
    private var gridBottom: CGFloat { arena.height - safeH }
    private var gridH:      CGFloat { gridBottom - gridTop }
    private var tileW:      CGFloat { arena.width / CGFloat(cols) }
    private var tileH:      CGFloat { gridH / CGFloat(rows) }
    private var best: Int { gameState.minigameBests["disco", default: 0] }
    /// Coins this run would bank right now.
    private var runCoins: Int { crossings * Self.coinsPerCrossing }

    // MARK: - Body
    var body: some View {
        ZStack {
            background

            GeometryReader { geo in
                ZStack {
                    safeZonesLayer
                    tilesLayer
                    ballLayer
                }
                .contentShape(Rectangle())
                .onAppear { layout(geo.size) }
                .onChange(of: geo.size) { _, s in layout(s) }
                .onTapGesture { handleTap() }
            }

            topBar
            if phase == .memorize { memorizeHint }
            if phase == .gameOver { gameOverOverlay }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(clock.$tickCount) { _ in tick() }
        .onAppear { motion.start(); clock.start() }
        .onDisappear { motion.stop(); clock.stop() }
        .onChange(of: scenePhase) { _, ph in
            if ph == .background { clock.stop(); motion.stop() }
            else if ph == .active { clock.start(); motion.start() }
        }
    }

    // MARK: - Layers

    private var background: some View {
        LinearGradient(colors: [Color(white: 0.05), Color(white: 0.11)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var safeZonesLayer: some View {
        VStack(spacing: 0) {
            safeZone(isTarget: phase == .crossing && atBottom)     // top band
            Spacer(minLength: 0)
            safeZone(isTarget: phase == .crossing && !atBottom)    // bottom band
        }
        .allowsHitTesting(false)
    }

    private func safeZone(isTarget: Bool) -> some View {
        ZStack {
            Rectangle().fill(Self.safeFill)
            Rectangle()
                .fill(Self.greenLit.opacity(isTarget ? 0.22 : 0))
            Text("SAFE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundStyle(Color(white: isTarget ? 0.75 : 0.40))
        }
        .frame(height: safeH)
        .overlay(alignment: isTarget ? .center : .center) {
            Rectangle()
                .fill(Self.greenLit.opacity(isTarget ? 0.9 : 0.18))
                .frame(height: 2)
        }
    }

    private var tilesLayer: some View {
        ForEach(0..<rows, id: \.self) { r in
            ForEach(0..<cols, id: \.self) { c in
                let pos = GridPos(row: r, col: c)
                RoundedRectangle(cornerRadius: 6)
                    .fill(tileFill(pos))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Self.tileEdge, lineWidth: 1))
                    .frame(width: max(1, tileW - 5), height: max(1, tileH - 5))
                    .position(x: (CGFloat(c) + 0.5) * tileW,
                              y: gridTop + (CGFloat(r) + 0.5) * tileH)
            }
        }
        .allowsHitTesting(false)
    }

    private var ballLayer: some View {
        BallSkinView(skin: gameState.activeSkin, diameter: ballRadius * 2)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            .position(ball)
            .allowsHitTesting(false)
    }

    private func tileFill(_ pos: GridPos) -> Color {
        switch phase {
        case .memorize:
            guard let idx = pathIndex[pos] else { return Self.tileOff }
            let d = revealHead - Double(idx)
            if d < 0 { return Self.tileOff }
            return Self.revealColor.opacity(max(0.30, 1.0 - d * 0.10))
        case .crossing:
            return touched.contains(pos) ? Self.greenLit : Self.tileOff
        case .celebrate:
            return discoColor(pos)
        case .failed:
            return redBlink(pos)
        case .gameOver:
            return touched.contains(pos) ? Self.greenLit.opacity(0.45) : Self.tileOff
        }
    }

    private func discoColor(_ pos: GridPos) -> Color {
        Color(hue: seed(pos, blinkFrame), saturation: 0.9, brightness: 1.0)
    }
    private func redBlink(_ pos: GridPos) -> Color {
        seed(pos, blinkFrame) > 0.4
            ? Color(red: 0.95, green: 0.16, blue: 0.16)
            : Color(red: 0.34, green: 0.05, blue: 0.05)
    }
    /// Stable per-tile pseudo-random in 0..<1, varied by the blink frame.
    private func seed(_ pos: GridPos, _ frame: Int) -> Double {
        var x = UInt64(bitPattern: Int64(pos.row &* 73856093 ^ pos.col &* 19349663 ^ frame &* 83492791))
        x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33
        return Double(x % 1000) / 1000.0
    }

    // MARK: - HUD

    private var topBar: some View {
        VStack {
            HStack(alignment: .top) {
                Button { nav.goHome() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Circle().fill(Color(white: 0.16)))
                }
                .accessibilityLabel("Close")
                Spacer()
                VStack(spacing: 1) {
                    Text("\(crossings)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("CROSSINGS")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color(white: 0.5))
                        .accessibilityIdentifier("DiscoBallView")
                }
                Spacer()
                VStack(spacing: 1) {
                    Text("\(max(best, crossings))")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.revealColor)
                        .monospacedDigit()
                    Text("BEST")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color(white: 0.5))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var memorizeHint: some View {
        VStack {
            Spacer()
            VStack(spacing: 4) {
                Text("MEMORIZE THE PATH")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Self.revealColor)
                Text(startedEver
                     ? "Line up at the start · tap to roll"
                     : "Roll to the start tile · tap to cross without a wrong step")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var gameOverOverlay: some View {
        let isBest = crossings > 0 && crossings >= best
        return ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(isBest && crossings > 0 ? "New Best!" : "Game Over")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(isBest && crossings > 0 ? Self.revealColor : Color(white: 0.88))
                    Text("\(crossings) crossing\(crossings == 1 ? "" : "s") · best \(max(best, crossings))")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.65))
                }
                HStack(spacing: 12) {
                    CoinIcon(size: 40)
                    Text("+\(runCoins)")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Plus \(runCoins) coins")
                VStack(spacing: 12) {
                    Button { resetGame() } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Self.revealColor))
                    }
                    ResultShareButton(result: ShareableResult(
                        mode: "Disco Ball",
                        headline: "\(crossings) crossings",
                        subtitle: "Best \(max(best, crossings))",
                        skin: gameState.activeSkin,
                        trail: gameState.equippedTrail,
                        won: isBest && crossings > 0))
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game over. \(crossings) crossings. Best \(max(best, crossings)). Plus \(runCoins) coins.")
    }

    // MARK: - Lifecycle

    private func layout(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let first = (arena == .zero)
        arena = size
        if first { resetGame() }
    }

    private func resetGame() {
        crossings = 0
        atBottom = true
        startedEver = false
        beginMemorize()
    }

    private func beginMemorize() {
        touched = []
        revealHead = 0
        phaseEndAt = nil
        generatePath()
        spawnBallInSafeZone()
        phase = .memorize
    }

    private func spawnBallInSafeZone() {
        guard arena.width > 0 else { return }
        let y = atBottom ? (arena.height - safeH / 2) : safeH / 2
        ball = CGPoint(x: arena.width / 2, y: y)
        vel = .zero
    }

    /// A connected staircase path from the near safe-zone row to the far one.
    private func generatePath() {
        let shift = 1 + min(crossings / 3, 2)          // winds more as you go
        let near  = atBottom ? rows - 1 : 0
        let step  = atBottom ? -1 : 1
        var order: [GridPos] = []
        var col = Int.random(in: 0..<cols)
        var row = near
        for _ in 0..<rows {
            let target = max(0, min(cols - 1, col + Int.random(in: -shift...shift)))
            let dir = col <= target ? 1 : -1
            for c in stride(from: col, through: target, by: dir) {
                order.append(GridPos(row: row, col: c))
            }
            col = target
            row += step
        }
        pathOrder = order
        pathSet = Set(order)
        pathIndex = Dictionary(order.enumerated().map { ($0.element, $0.offset) },
                               uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Input

    private func handleTap() {
        switch phase {
        case .memorize:
            startedEver = true
            phase = .crossing
        case .celebrate:
            advanceAfterCelebrate()
        default:
            break
        }
    }

    // MARK: - Simulation

    private func tick() {
        guard arena.width > 0 else { return }
        blinkFrame = clock.tickCount / 6

        switch phase {
        case .memorize:
            let loopLen = Double(pathOrder.count) + 8     // pause before repeating
            revealHead += revealSpeed
            if revealHead >= loopLen { revealHead = 0 }
            stepPhysics(confineToSafeZone: true)
        case .crossing:
            stepPhysics(confineToSafeZone: false)
            evaluateCrossing()
        case .celebrate:
            stepPhysics(confineToSafeZone: false)
            if let end = phaseEndAt, Date() >= end { advanceAfterCelebrate() }
        case .failed:
            if let end = phaseEndAt, Date() >= end { endGame() }
        case .gameOver:
            break
        }
    }

    private func stepPhysics(confineToSafeZone: Bool) {
        let dt: CGFloat = 1.0 / 60.0
        vel.dx += CGFloat(motion.gravity.x) * moveAccel * dt
        vel.dy += CGFloat(motion.gravity.y) * moveAccel * dt
        vel.dx *= friction; vel.dy *= friction
        let sp = hypot(vel.dx, vel.dy)
        if sp > maxSpeed { let k = maxSpeed / sp; vel.dx *= k; vel.dy *= k }

        var p = CGPoint(x: ball.x + vel.dx * dt, y: ball.y + vel.dy * dt)
        let r = ballRadius

        if p.x < r { p.x = r; vel.dx = -vel.dx * wallBounce }
        if p.x > arena.width - r { p.x = arena.width - r; vel.dx = -vel.dx * wallBounce }

        let topLimit: CGFloat, botLimit: CGFloat
        if confineToSafeZone {
            if atBottom { topLimit = gridBottom + r; botLimit = arena.height - r }
            else        { topLimit = r;              botLimit = gridTop - r }
        } else {
            topLimit = r; botLimit = arena.height - r
        }
        if p.y < topLimit { p.y = topLimit; vel.dy = -vel.dy * wallBounce }
        if p.y > botLimit { p.y = botLimit; vel.dy = -vel.dy * wallBounce }

        ball = p
    }

    /// During a crossing: light correct tiles, fail on a wrong one, win on the
    /// far safe zone.
    private func evaluateCrossing() {
        // Reached the far safe zone?
        let reachedFar = atBottom ? (ball.y <= gridTop) : (ball.y >= gridBottom)
        if reachedFar { succeedCrossing(); return }

        // Inside the grid? Check the tile under the ball's centre.
        guard ball.y > gridTop, ball.y < gridBottom else { return }
        let c = Int((ball.x / tileW).rounded(.down))
        let r = Int(((ball.y - gridTop) / tileH).rounded(.down))
        guard c >= 0, c < cols, r >= 0, r < rows else { return }
        let pos = GridPos(row: r, col: c)
        if pathSet.contains(pos) {
            touched.insert(pos)
        } else {
            failCrossing()
        }
    }

    private func succeedCrossing() {
        crossings += 1
        if gameState.hapticsEnabled { Haptics.success() }
        AudioManager.shared.playWin(enabled: gameState.soundEnabled)
        phase = .celebrate
        phaseEndAt = Date().addingTimeInterval(celebrateDuration)
    }

    private func advanceAfterCelebrate() {
        guard phase == .celebrate else { return }
        atBottom.toggle()           // the far zone is now the current zone
        beginMemorize()
    }

    private func failCrossing() {
        if gameState.hapticsEnabled { Haptics.warning() }
        phase = .failed
        phaseEndAt = Date().addingTimeInterval(failDuration)
    }

    private func endGame() {
        let wasBest = crossings > best
        if wasBest { gameState.minigameBests["disco"] = crossings }
        if runCoins > 0 { gameState.addCoins(runCoins) }
        if wasBest && crossings > 0 { gameState.addCoins(GameState.minigameBestBonus) }
        AnalyticsClient.shared.track(
            "disco_game_over",
            properties: ["crossings": .int(crossings),
                         "best": .int(max(best, crossings))]
        )
        phase = .gameOver
    }
}
