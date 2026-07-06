import SwiftUI

// ===========================================================================
// RollOutView — "Roll Out", a true marble maze (à la the classic wooden
// tilt-labyrinth).  The screen is a fully bordered table; an EXTRA-SMALL ball
// starts at the bottom and must reach the goal at the top by weaving through
// maze walls without dropping into one of the holes that punctuate the map.
//
// RELATION TO THE CLIMB
//   It's the climb's DNA — tilt-to-roll, walls, holes, a goal — but tuned for
//   precision: a tiny ball, low restitution, dense interior walls, and a
//   "mind the holes" hazard layout.  Per Mac's call it shares the climb's life
//   economy: each fall in a hole costs a real life (Diamond Balls = no cost),
//   and running out surfaces the Get Lives sheet.
//
// SAFE BY CONSTRUCTION: a brand-new, isolated file.  It reuses only the shared
// physics primitives (BallMotion / PhysicsClock / bounceEdges /
// resolveWallSegment), the lives + coin economy on GameState, BallSkinView,
// CoinIcon, and ResultShareButton.  It touches nothing in the climb engine.
// Reached only when HomeView routes `.mode("rollout")` here.
// ===========================================================================

// MARK: - Map model

/// A single fall-hazard hole, positioned as unit fractions of the table with a
/// radius in points (like PillarFrac).
struct RollOutHole: Equatable {
    let cx, cy: CGFloat   // 0…1 of the table rect
    let r: CGFloat        // points
}

/// One hand-authored maze: interior walls (fractional segments), holes to dodge,
/// and the fractional start + goal positions.  Every maze is solvable by rolling
/// along the open lanes; holes always leave clearance to one side.
struct RollOutMaze {
    let name: String
    let walls: [WallSegFrac]
    let holes: [RollOutHole]
    let start: CGPoint   // fractional (0…1)
    let goal:  CGPoint   // fractional (0…1)
}

enum RollOutMazes {
    /// Active catalogue: a bundled `rollout.json` (authored in Marble Mapper)
    /// overrides the built-in mazes; absent/empty → built-in list (unchanged).
    static var all: [RollOutMaze] { RollOutMazeStore.mazes ?? builtin }

    /// Hand-built ladder of rising difficulty.  Start sits at the bottom, goal
    /// at the top; walls form a serpentine the ball weaves up, holes force a
    /// careful line.  Cleared mazes advance; the run ends when lives run out.
    static let builtin: [RollOutMaze] = [

        // 1 — Warm-Up: two offset dividers, no holes.  Learn the weave.
        RollOutMaze(name: "Warm-Up",
                    walls: [WallSegFrac(x1: 0.00, y1: 0.64, x2: 0.60, y2: 0.64),
                            WallSegFrac(x1: 0.40, y1: 0.36, x2: 1.00, y2: 0.36)],
                    holes: [],
                    start: CGPoint(x: 0.50, y: 0.88),
                    goal:  CGPoint(x: 0.50, y: 0.12)),

        // 2 — First Pits: three dividers, a hole centred in each open lane.
        RollOutMaze(name: "First Pits",
                    walls: [WallSegFrac(x1: 0.00, y1: 0.72, x2: 0.62, y2: 0.72),
                            WallSegFrac(x1: 0.38, y1: 0.50, x2: 1.00, y2: 0.50),
                            WallSegFrac(x1: 0.00, y1: 0.28, x2: 0.62, y2: 0.28)],
                    holes: [RollOutHole(cx: 0.50, cy: 0.61, r: 15),
                            RollOutHole(cx: 0.50, cy: 0.39, r: 15)],
                    start: CGPoint(x: 0.50, y: 0.90),
                    goal:  CGPoint(x: 0.50, y: 0.10)),

        // 3 — The Weave: four dividers, holes offset toward each gap.
        RollOutMaze(name: "The Weave",
                    walls: [WallSegFrac(x1: 0.00, y1: 0.78, x2: 0.64, y2: 0.78),
                            WallSegFrac(x1: 0.36, y1: 0.59, x2: 1.00, y2: 0.59),
                            WallSegFrac(x1: 0.00, y1: 0.40, x2: 0.64, y2: 0.40),
                            WallSegFrac(x1: 0.36, y1: 0.21, x2: 1.00, y2: 0.21)],
                    holes: [RollOutHole(cx: 0.30, cy: 0.685, r: 15),
                            RollOutHole(cx: 0.70, cy: 0.495, r: 15),
                            RollOutHole(cx: 0.30, cy: 0.305, r: 15)],
                    start: CGPoint(x: 0.50, y: 0.91),
                    goal:  CGPoint(x: 0.50, y: 0.09)),

        // 4 — Pinch: dividers plus a vertical stub that narrows the lane; holes
        //     flank the squeeze.
        RollOutMaze(name: "Pinch",
                    walls: [WallSegFrac(x1: 0.00, y1: 0.76, x2: 0.58, y2: 0.76),
                            WallSegFrac(x1: 0.42, y1: 0.57, x2: 1.00, y2: 0.57),
                            WallSegFrac(x1: 0.50, y1: 0.57, x2: 0.50, y2: 0.76),  // vertical stub
                            WallSegFrac(x1: 0.00, y1: 0.38, x2: 0.58, y2: 0.38),
                            WallSegFrac(x1: 0.42, y1: 0.19, x2: 1.00, y2: 0.19)],
                    holes: [RollOutHole(cx: 0.74, cy: 0.665, r: 16),
                            RollOutHole(cx: 0.26, cy: 0.475, r: 16),
                            RollOutHole(cx: 0.74, cy: 0.285, r: 16)],
                    start: CGPoint(x: 0.28, y: 0.91),
                    goal:  CGPoint(x: 0.50, y: 0.08)),

        // 5 — Gauntlet: five dividers, four holes — a tight, hole-dense climb.
        RollOutMaze(name: "Gauntlet",
                    walls: [WallSegFrac(x1: 0.00, y1: 0.82, x2: 0.66, y2: 0.82),
                            WallSegFrac(x1: 0.34, y1: 0.66, x2: 1.00, y2: 0.66),
                            WallSegFrac(x1: 0.00, y1: 0.50, x2: 0.66, y2: 0.50),
                            WallSegFrac(x1: 0.34, y1: 0.34, x2: 1.00, y2: 0.34),
                            WallSegFrac(x1: 0.00, y1: 0.18, x2: 0.66, y2: 0.18)],
                    holes: [RollOutHole(cx: 0.32, cy: 0.74, r: 15),
                            RollOutHole(cx: 0.68, cy: 0.58, r: 15),
                            RollOutHole(cx: 0.32, cy: 0.42, r: 15),
                            RollOutHole(cx: 0.68, cy: 0.26, r: 15)],
                    start: CGPoint(x: 0.50, y: 0.92),
                    goal:  CGPoint(x: 0.50, y: 0.08)),
    ]
}

// MARK: - View

struct RollOutView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables (precision feel — tighter than the coin-scramble modes)
    private let ballRadius:  CGFloat = 7      // extra small, per the brief
    private let goalRadius:  CGFloat = 17
    private let playerAccel: CGFloat = 1_250
    private let friction:    CGFloat = 0.984
    private let maxSpeed:    CGFloat = 430
    private let wallBounce:  CGFloat = 0.45   // dull bounce so the ball settles
    private let coinsPerClear      = 10

    // MARK: - Phase
    private enum Phase { case ready, playing, cleared, fell }

    // MARK: - State
    @State private var arena: CGSize = .zero
    @State private var pos: CGPoint = .zero
    @State private var vel: CGVector = .zero
    @State private var mazeIndex = 0
    @State private var phase: Phase = .ready
    @State private var trail: [CGPoint] = []
    @State private var goalPulse = false
    @State private var showBuyLivesSheet = false
    private let trailMaxLen = 16
    private let trailMinStep: CGFloat = 3

    private var maze: RollOutMaze { RollOutMazes.all[mazeIndex % RollOutMazes.all.count] }
    private var boundary: Boundary { gameState.equippedBoundary }
    private var outOfLives: Bool { !gameState.unlimitedLives && gameState.displayedLives <= 0 }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    tableFloor
                    holesLayer.allowsHitTesting(false)
                    wallsLayer.allowsHitTesting(false)
                    goalLayer.allowsHitTesting(false)
                    trailLayer.allowsHitTesting(false)
                    ballLayer
                }
                .contentShape(Rectangle())
                .onAppear { layout(geo.size) }
                .onChange(of: geo.size) { _, s in layout(s) }
                .onTapGesture {
                    if phase == .ready && !outOfLives {
                        phase = .playing
                        AnalyticsClient.shared.track(
                            "minigame_round_started",
                            properties: ["game_mode": .string("rollout"),
                                         "maze": .string(maze.name)])
                    }
                }
            }

            tableBorder.allowsHitTesting(false)
            topBar
            HomeQuitButton()
            if phase == .ready && !outOfLives { startPrompt }
            if phase == .cleared { clearedOverlay }
            if phase == .fell && !outOfLives { fellOverlay }
            if outOfLives && phase != .cleared { outOfLivesOverlay }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(clock.$tickCount) { _ in tick() }
        .onAppear { motion.start(); clock.start(); goalPulse = true }
        .onDisappear { motion.stop(); clock.stop() }
        .onChange(of: scenePhase) { _, ph in
            if ph == .background { clock.stop(); motion.stop() }
            else if ph == .active { clock.start(); motion.start() }
        }
        .sheet(isPresented: $showBuyLivesSheet) {
            BuyLivesSheet().environmentObject(gameState)
        }
    }

    // MARK: - Layers

    private var tableFloor: some View {
        RadialGradient(colors: [Color(white: 0.13), Color(white: 0.055)],
                       center: .center, startRadius: 0,
                       endRadius: max(arena.width, arena.height) * 0.75)
            .ignoresSafeArea()
    }

    private var tableBorder: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(
                LinearGradient(colors: [boundary.edgeColor, boundary.deepColor],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 5)
            .ignoresSafeArea()
    }

    private var wallsLayer: some View {
        Canvas { ctx, _ in
            guard arena.width > 0 else { return }
            for seg in maze.walls {
                let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
                let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
                var path = Path(); path.move(to: p1); path.addLine(to: p2)
                ctx.stroke(path, with: .color(boundary.color),
                           style: StrokeStyle(lineWidth: 9, lineCap: .round))
                ctx.stroke(path, with: .color(boundary.edgeColor.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
    }

    private var holesLayer: some View {
        Canvas { ctx, _ in
            guard arena.width > 0 else { return }
            for h in maze.holes {
                let c = holeCenter(h)
                let rect = CGRect(x: c.x - h.r, y: c.y - h.r, width: h.r * 2, height: h.r * 2)
                // Recessed pit: dark well + a soft rim so it reads as a hole.
                ctx.fill(Path(ellipseIn: rect),
                         with: .radialGradient(
                            Gradient(colors: [.black, Color(white: 0.02)]),
                            center: c, startRadius: 0, endRadius: h.r))
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -1, dy: -1)),
                           with: .color(Color(white: 0.30)),
                           style: StrokeStyle(lineWidth: 2))
            }
        }
    }

    private var goalLayer: some View {
        let c = CGPoint(x: maze.goal.x * arena.width, y: maze.goal.y * arena.height)
        return ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.45, green: 0.95, blue: 0.65).opacity(0.55), .clear],
                    center: .center, startRadius: 1, endRadius: goalRadius * 2.2))
                .frame(width: goalRadius * 4, height: goalRadius * 4)
                .scaleEffect(goalPulse ? 1.12 : 0.86)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                           value: goalPulse)
            Circle()
                .strokeBorder(Color(red: 0.5, green: 1.0, blue: 0.7), lineWidth: 3)
                .background(Circle().fill(Color(red: 0.20, green: 0.5, blue: 0.35).opacity(0.5)))
                .frame(width: goalRadius * 2, height: goalRadius * 2)
            Image(systemName: "flag.checkered")
                .font(.system(size: goalRadius * 0.9, weight: .bold))
                .foregroundStyle(.white)
        }
        .position(c)
    }

    private var trailLayer: some View {
        Canvas { ctx, _ in
            let t = gameState.equippedTrail
            guard t != .none, trail.count >= 2 else { return }
            for i in 1..<trail.count {
                let age = Double(i) / Double(trail.count - 1)
                let color: Color = t == .rainbow
                    ? Color(hue: (Double(i) / Double(trail.count)).truncatingRemainder(dividingBy: 1),
                            saturation: 1, brightness: 1)
                    : t.color
                var path = Path(); path.move(to: trail[i - 1]); path.addLine(to: trail[i])
                ctx.stroke(path, with: .color(color.opacity(0.10 + 0.5 * age)),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private var ballLayer: some View {
        BallSkinView(skin: gameState.activeSkin, diameter: ballRadius * 2)
            .frame(width: ballRadius * 2, height: ballRadius * 2)
            .shadow(color: .black.opacity(0.55), radius: 4, x: 1, y: 2)
            .position(pos)
            .opacity(phase == .cleared || phase == .fell ? 0 : 1)
    }

    // MARK: - HUD / overlays

    private var topBar: some View {
        VStack {
            HStack {
                // Home is now the floating bottom-left button (HomeQuitButton),
                // matching the climb / Zen Garden; keep the slot to centre the score.
                Color.clear.frame(width: 36, height: 36)
                Spacer()
                VStack(spacing: 1) {
                    Text("Maze \(mazeIndex + 1)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("ROLL OUT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color(white: 0.5))
                        .accessibilityIdentifier("RollOutView")
                }
                Spacer()
                livesPill
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var livesPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.42, blue: 0.42),
                                              Color(red: 0.85, green: 0.18, blue: 0.22)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 14, height: 14)
                .overlay(Circle().fill(.white.opacity(0.5))
                    .frame(width: 4, height: 4).offset(x: -2.5, y: -2.5))
            if gameState.unlimitedLives {
                Image(systemName: "infinity")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(gameState.displayedLives)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Capsule().fill(Color(white: 0.16)))
        .accessibilityLabel(gameState.unlimitedLives ? "Unlimited lives"
                            : "\(gameState.displayedLives) lives")
    }

    private var startPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.grid.cross.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color(red: 0.5, green: 1.0, blue: 0.7))
            Text("Tilt to roll")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Reach the flag — don't fall in a hole.\nEach fall costs a life.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roll Out. Tilt to roll the ball to the flag without falling in a hole. Each fall costs a life. Tap to begin.")
    }

    private var clearedOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("Maze Cleared!")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.5, green: 1.0, blue: 0.7))
                    Text(maze.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.65))
                }
                HStack(spacing: 12) {
                    CoinIcon(size: 40)
                    Text("+\(coinsPerClear)")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Plus \(coinsPerClear) coins")
                VStack(spacing: 12) {
                    Button { advance() } label: {
                        Text("Next Maze")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 0.5, green: 1.0, blue: 0.7)))
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

    private var fellOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("Down the Hole!")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(Color(white: 0.9))
                    Text("\(livesWord) left")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.6))
                }
                VStack(spacing: 12) {
                    Button { restartMaze() } label: {
                        Text("Try Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
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

    private var livesWord: String {
        gameState.unlimitedLives ? "Unlimited lives"
            : "\(gameState.displayedLives) " + (gameState.displayedLives == 1 ? "life" : "lives")
    }

    private var outOfLivesOverlay: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Color(red: 0.95, green: 0.4, blue: 0.4))
                Text("Out of Lives")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Get more lives to keep rolling.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    Button { showBuyLivesSheet = true } label: {
                        Text("Get Lives")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 1.0, green: 0.45, blue: 0.45)))
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

    // MARK: - Geometry helpers

    private func holeCenter(_ h: RollOutHole) -> CGPoint {
        CGPoint(x: h.cx * arena.width, y: h.cy * arena.height)
    }

    private func startPoint() -> CGPoint {
        CGPoint(x: maze.start.x * arena.width, y: maze.start.y * arena.height)
    }

    // MARK: - Lifecycle

    private func layout(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let wasEmpty = arena.width == 0
        arena = size
        if wasEmpty { resetBall() }
    }

    private func resetBall() {
        pos = startPoint()
        vel = .zero
        trail = [pos]
    }

    /// Restart the current maze (after a fall) — back to the tap-to-start state.
    private func restartMaze() {
        resetBall()
        phase = .ready
    }

    /// Advance to the next maze in the ladder after a clear.
    private func advance() {
        mazeIndex += 1
        resetBall()
        phase = .ready
    }

    // MARK: - Simulation

    private func tick() {
        guard phase == .playing, arena.width > 0 else { return }
        let dt: CGFloat = 1.0 / 60.0

        // Tilt → acceleration (same convention as every tilt minigame).
        vel.dx += CGFloat(motion.gravity.x) * playerAccel * dt
        vel.dy += CGFloat(motion.gravity.y) * playerAccel * dt
        vel.dx *= friction
        vel.dy *= friction
        let s = hypot(vel.dx, vel.dy)
        if s > maxSpeed { let k = maxSpeed / s; vel.dx *= k; vel.dy *= k }

        pos.x += vel.dx * dt
        pos.y += vel.dy * dt

        // Table edges + interior walls.
        bounceEdges(pos: &pos, vel: &vel, radius: ballRadius, arena: arena, restitution: wallBounce)
        for seg in maze.walls {
            let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
            let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
            resolveWallSegment(pos: &pos, vel: &vel, p1: p1, p2: p2,
                               radius: ballRadius, restitution: wallBounce)
        }

        accumulateTrail()

        // Goal first: a clean roll into the flag wins even if it grazed a rim.
        let g = CGPoint(x: maze.goal.x * arena.width, y: maze.goal.y * arena.height)
        if hypot(pos.x - g.x, pos.y - g.y) < goalRadius + ballRadius {
            clearMaze(); return
        }
        // Holes: centre inside the hole (minus a small lip) drops the ball.
        for h in maze.holes {
            let c = holeCenter(h)
            if hypot(pos.x - c.x, pos.y - c.y) < h.r - ballRadius * 0.4 {
                fall(); return
            }
        }
    }

    private func accumulateTrail() {
        if let last = trail.last {
            if hypot(pos.x - last.x, pos.y - last.y) > trailMinStep { trail.append(pos) }
        } else {
            trail.append(pos)
        }
        if trail.count > trailMaxLen { trail.removeFirst(trail.count - trailMaxLen) }
    }

    private func clearMaze() {
        phase = .cleared
        gameState.addCoins(coinsPerClear)
        // Best = furthest maze reached (1-based).  The record, the shared
        // 100-coin new-best bonus, and the Roll Out trophies now funnel
        // through GameState (S1-T4); the view keeps only the per-clear payout.
        let reached = mazeIndex + 1
        gameState.recordRollOutResult(reached: reached)
        if gameState.hapticsEnabled { Haptics.success() }
        AudioManager.shared.playWin(enabled: gameState.soundEnabled)
        AnalyticsClient.shared.track(
            "minigame_round_over",
            properties: ["game_mode": .string("rollout"),
                         "won": .bool(true),
                         "maze": .int(reached)])
    }

    private func fall() {
        // Mirrors the climb's fall feedback + life cost (Diamond Balls exempt).
        if gameState.hapticsEnabled {
            Haptics.medium()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { Haptics.medium() }
        }
        gameState.consumeLife()
        phase = .fell
        AnalyticsClient.shared.track(
            "minigame_round_over",
            properties: ["game_mode": .string("rollout"),
                         "won": .bool(false),
                         "maze": .int(mazeIndex + 1)])
    }
}

#Preview {
    NavigationStack {
        RollOutView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}

// ===========================================================================
// RollOutMazeStore — JSON override seam for the Roll Out maze catalogue.
//
// Mirrors the climb's LevelOverrideStore + the minigame seams. If a bundled
// `rollout.json` (authored in Marble Mapper) is present and non-empty, it
// REPLACES the built-in mazes; otherwise the built-ins are used unchanged.
//
// File shape:
//   { "schemaVersion": 1,
//     "mazes": [ { "name": "…", "walls": [ {"x1":,"y1":,"x2":,"y2":} ],
//                  "holes": [ {"cx":,"cy":,"r":} ],
//                  "start": {"x":,"y":}, "goal": {"x":,"y":} } ] }
// ===========================================================================
private struct ROPointDTO:  Decodable { let x, y: CGFloat }
private struct ROCircleDTO: Decodable { let cx, cy, r: CGFloat }
private struct ROWallDTO:   Decodable { let x1, y1, x2, y2: CGFloat }
private struct ROMazeDTO:   Decodable { let name: String?; let walls: [ROWallDTO]?; let holes: [ROCircleDTO]?; let start: ROPointDTO; let goal: ROPointDTO }
private struct ROFile:      Decodable { let schemaVersion: Int; let mazes: [ROMazeDTO] }

enum RollOutMazeStore {
    static let mazes: [RollOutMaze]? = load()

    private static func load() -> [RollOutMaze]? {
        guard let url = Bundle.main.url(forResource: "rollout", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ROFile.self, from: data),
              !file.mazes.isEmpty else { return nil }
        return file.mazes.map { m in
            RollOutMaze(
                name:  m.name ?? "Maze",
                walls: (m.walls ?? []).map { WallSegFrac(x1: $0.x1, y1: $0.y1, x2: $0.x2, y2: $0.y2) },
                holes: (m.holes ?? []).map { RollOutHole(cx: $0.cx, cy: $0.cy, r: $0.r) },
                start: CGPoint(x: m.start.x, y: m.start.y),
                goal:  CGPoint(x: m.goal.x,  y: m.goal.y))
        }
    }
}
