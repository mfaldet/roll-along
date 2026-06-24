import SwiftUI

// ===========================================================================
// SumoSurvivalView — the "Sumo Survival" competitive mode.
//
// A sumo dohyo on a round platform floating in the void.  Tilt accelerates
// your marble; ram the AI rivals off the edge.  The rim IS the hazard — any
// marble whose center crosses it falls out.  But this is SURVIVAL, not a
// one-and-done round:
//
//   • the ring slowly SHRINKS, closing in to force confrontation;
//   • fresh rivals keep SPAWNING in waves, so the pressure never stops;
//   • your score is the number of rivals YOU knock out;
//   • you last until *you* get rung out — then bank your coins.
//
// SAFE BY CONSTRUCTION: an isolated file.  It reuses only the shared physics
// primitives (BallMotion / PhysicsClock) and the coin / skin economy on
// GameState; it touches nothing in the climb engine.  Reached only when
// HomeView routes `.mode("sumo")` here and SumoSurvivalMode is flagged on.
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
    private let aiAccel:      CGFloat = 1_160     // base rival acceleration
    private let aiAccelRampPerSec: CGFloat = 5    // rivals speed up the longer you last
    private let aiAccelRampCap:    CGFloat = 260  // …up to this much extra
    private let friction:     CGFloat = 0.992     // marbles glide on the floor
    private let maxSpeed:     CGFloat = 780
    private let restitution:  CGFloat = 0.92       // bounciness of marble hits
    private let startingRivals     = 3
    private let maxConcurrentRivals = 5
    private let spawnEveryTicks    = 150           // a fresh rival every ~2.5s
    private let platformMargin: CGFloat = 26       // void gap around the platform
    private let shrinkFrac:    CGFloat = 0.42      // ring closes to 58% of full…
    private let shrinkOverTicks     = 60 * 60      // …across the first 60 seconds
    private let edgePull       = 0.62              // AI starts steering home past this × radius
    private let coinsPerKO         = 4
    private let coinsPerSurvived4s = 1             // a coin for every 4s you stay alive

    // MARK: - Model

    private struct Bumper: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector = .zero
        let color: Color
        let isPlayer: Bool
        var lastHitBy: UUID? = nil   // who shoved me most recently (for KO credit)
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
        Color(red: 0.45, green: 0.85, blue: 0.55),
    ]

    // MARK: - State

    @State private var bumpers: [Bumper] = []
    @State private var poofs:   [Poof]   = []
    /// Each rival's keystone look (bumper id → skin+trail+name); dealt on spawn
    /// (Sumo feeds rivals in waves, so looks are keyed by id, not colorIndex).
    @State private var rivalLooks: [UUID: RivalCosmetics.Look] = [:]
    /// Recent positions per bumper (id → points) for the trail layer.
    @State private var trails: [UUID: [CGPoint]] = [:]
    @State private var arena:   CGSize = .zero
    @State private var center:  CGPoint = .zero
    @State private var baseRadius: CGFloat = 0
    @State private var radius:  CGFloat = 0       // current (shrunken) ring radius

    @State private var started = false
    @State private var isOver  = false
    @State private var knockouts = 0
    @State private var survivalTicks = 0
    @State private var localTick = 0
    @State private var awarded = false

    // Map cycling (S25)
    @State private var mapIndex   = 0
    @State private var showMapName = false

    // MARK: - Computed

    private var currentPillars: [SumoPillar] {
        SumoMaps.maps[mapIndex % SumoMaps.maps.count].pillars
    }

    private var rivalsAlive: Int { bumpers.filter { !$0.isPlayer }.count }
    private var playerAlive: Bool { bumpers.contains { $0.isPlayer } }
    private var survivedSeconds: Int { survivalTicks / 60 }

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
                    let wasEmpty = bumpers.isEmpty
                    layout(newSize)
                    if wasEmpty { reset() }
                }
                .onTapGesture {
                    if !started && !isOver {
                        started = true
                        AnalyticsClient.shared.track(
                            "sumo_round_started",
                            properties: ["map_name": .string(SumoMaps.maps[mapIndex % SumoMaps.maps.count].name)]
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

    /// Pillar obstacles scaled to the current platform radius (S25).
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

    /// The TrailColor a bumper renders with — own for the player, dealt for rivals.
    private func trailFor(_ b: Bumper) -> TrailColor {
        b.isPlayer ? gameState.equippedTrail : (rivalLooks[b.id]?.trail ?? .none)
    }

    /// Keystone: every bumper's equipped trail, visible to all.
    private var trailsLayer: some View {
        Canvas { ctx, _ in
            drawTrails(ctx, bumpers.map { (trails[$0.id] ?? [], trailFor($0)) })
        }
    }

    private func marble(_ b: Bumper) -> some View {
        // No per-racer colour highlight — the name tag identifies each ball.
        let skin = b.isPlayer ? gameState.activeSkin : (rivalLooks[b.id]?.skin ?? .red)
        return BallSkinView(skin: skin, diameter: marbleRadius * 2)
            .frame(width: marbleRadius * 2, height: marbleRadius * 2)
            .shadow(color: .black.opacity(0.55), radius: 6, x: 2, y: 4)
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
                VStack(spacing: 1) {
                    Text("\(knockouts)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("KNOCKOUTS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                        .tracking(1)
                }
                Spacer()
                VStack(spacing: 1) {
                    Text(timeString)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(white: 0.85))
                        .monospacedDigit()
                    Text("SURVIVED")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                        .tracking(1)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var timeString: String {
        String(format: "%d:%02d", survivedSeconds / 60, survivedSeconds % 60)
    }

    private var startPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color(red: 0.98, green: 0.45, blue: 0.40))
            Text("Tilt to play")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Shove rivals off the ring.\nIt shrinks, they keep coming — survive.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sumo Survival. Tilt to push rivals off the shrinking ring. Last marble standing wins. Tap anywhere to begin.")
    }

    private var gameOverOverlay: some View {
        let banked = knockouts * coinsPerKO + survivedSeconds / 4 * coinsPerSurvived4s
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Knocked Out")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.98, green: 0.45, blue: 0.40))
                    Text("\(knockouts) knockouts · survived \(timeString)")
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
                        headline: "\(knockouts) knockouts",
                        subtitle: "survived \(timeString)",
                        skin: gameState.activeSkin,
                        trail: gameState.equippedTrail,
                        won: knockouts >= 3))
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
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        baseRadius = min(size.width, size.height) / 2 - platformMargin
        if radius == 0 { radius = baseRadius }
    }

    private func reset() {
        guard baseRadius > 0 else { return }
        started = false
        isOver = false
        knockouts = 0
        survivalTicks = 0
        awarded = false
        poofs = []
        radius = baseRadius

        // Player spawns dead center; rivals on a ring around it.
        var fresh: [Bumper] = [Bumper(pos: center, color: .white, isPlayer: true)]
        let spawnR = baseRadius * 0.6
        for i in 0..<startingRivals {
            let angle = (Double(i) / Double(startingRivals)) * 2 * .pi - .pi / 2
            let p = CGPoint(x: center.x + CGFloat(cos(angle)) * spawnR,
                            y: center.y + CGFloat(sin(angle)) * spawnR)
            fresh.append(Bumper(pos: p,
                                color: Self.rivalColors[i % Self.rivalColors.count],
                                isPlayer: false))
        }
        bumpers = fresh
        rivalLooks = [:]
        for b in bumpers where !b.isPlayer { rivalLooks[b.id] = RivalCosmetics.random() }
        trails = [:]
        showMapName = true
    }

    private func endRun() {
        guard !isOver else { return }
        isOver = true
        if !awarded {
            awarded = true
            let banked = knockouts * coinsPerKO + survivedSeconds / 4 * coinsPerSurvived4s
            if banked > 0 { gameState.addCoins(banked) }
            AnalyticsClient.shared.track(
                "sumo_round_over",
                properties: ["knockouts": .int(knockouts),
                             "survived_sec": .int(survivedSeconds),
                             "coins": .int(banked),
                             "map_name": .string(SumoMaps.maps[mapIndex % SumoMaps.maps.count].name)]
            )
            if gameState.hapticsEnabled { Haptics.warning() }
        }
    }

    // MARK: - Simulation

    private func tick() {
        localTick &+= 1
        prunePoofs()
        guard started, !isOver, baseRadius > 0 else { return }
        survivalTicks += 1
        updateRing()
        let dt: CGFloat = 1.0 / 60.0
        let effAiAccel = aiAccel + min(aiAccelRampCap, CGFloat(survivedSeconds) * aiAccelRampPerSec)

        // 1) Steering / acceleration.
        for i in bumpers.indices {
            if bumpers[i].isPlayer {
                bumpers[i].vel.dx += CGFloat(motion.gravity.x) * playerAccel * dt
                bumpers[i].vel.dy += CGFloat(motion.gravity.y) * playerAccel * dt
            } else {
                let steer = aiSteer(for: bumpers[i], accel: effAiAccel)
                bumpers[i].vel.dx += steer.dx * dt
                bumpers[i].vel.dy += steer.dy * dt
            }
            // friction + speed clamp
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

        // 3) Resolve pairwise collisions (equal mass, elastic w/ restitution).
        resolveCollisions()

        // 3b) Resolve pillar collisions (S25).
        resolvePillarCollisions()

        // 4) Eliminate anyone whose center crossed the rim.
        resolveEliminations()

        // 4b) Grow each survivor's trail; prune dead bumpers so the dict stays
        //     bounded across waves.
        let liveIds = Set(bumpers.map(\.id))
        for b in bumpers { recordTrail(&trails, b.id, b.pos) }
        trails = trails.filter { liveIds.contains($0.key) }

        // 5) Feed the waves.
        spawnWaveIfNeeded()
    }

    /// Close the ring in over time, down to `1 - shrinkFrac` of full.
    private func updateRing() {
        let progress = min(1, CGFloat(survivalTicks) / CGFloat(shrinkOverTicks))
        radius = baseRadius * (1 - shrinkFrac * progress)
    }

    /// Aim at the nearest other marble, but steer back toward center when near
    /// the rim so rivals don't trivially drive themselves off.
    private func aiSteer(for b: Bumper, accel: CGFloat) -> CGVector {
        var target: CGPoint?
        var best = CGFloat.greatestFiniteMagnitude
        for o in bumpers where o.id != b.id {
            let d = hypot(o.pos.x - b.pos.x, o.pos.y - b.pos.y)
            if d < best { best = d; target = o.pos }
        }
        var steer = CGVector(dx: 0, dy: 0)
        if let t = target {
            steer = unit(dx: t.x - b.pos.x, dy: t.y - b.pos.y, scale: accel)
        }
        let fromCenter = CGVector(dx: b.pos.x - center.x, dy: b.pos.y - center.y)
        let distC = hypot(fromCenter.dx, fromCenter.dy)
        if distC > radius * edgePull {
            let inward = unit(dx: -fromCenter.dx, dy: -fromCenter.dy, scale: accel * 1.4)
            steer = CGVector(dx: steer.dx * 0.35 + inward.dx,
                             dy: steer.dy * 0.35 + inward.dy)
        }
        return steer
    }

    private func resolveCollisions() {
        guard bumpers.count >= 2 else { return }
        let minDist = marbleRadius * 2
        for i in 0..<bumpers.count {
            for j in (i + 1)..<bumpers.count {
                let dx = bumpers[j].pos.x - bumpers[i].pos.x
                let dy = bumpers[j].pos.y - bumpers[i].pos.y
                let dist = hypot(dx, dy)
                guard dist > 0, dist < minDist else { continue }
                let nx = dx / dist, ny = dy / dist
                // Separate the overlap equally.
                let overlap = (minDist - dist) / 2
                bumpers[i].pos.x -= nx * overlap
                bumpers[i].pos.y -= ny * overlap
                bumpers[j].pos.x += nx * overlap
                bumpers[j].pos.y += ny * overlap
                // Elastic impulse along the normal (equal mass).
                let relVel = (bumpers[j].vel.dx - bumpers[i].vel.dx) * nx
                           + (bumpers[j].vel.dy - bumpers[i].vel.dy) * ny
                // Record who shoved whom — last contact wins KO credit.
                let idI = bumpers[i].id, idJ = bumpers[j].id
                bumpers[i].lastHitBy = idJ
                bumpers[j].lastHitBy = idI
                guard relVel < 0 else { continue }
                let jImp = -(1 + restitution) * relVel / 2
                bumpers[i].vel.dx -= jImp * nx
                bumpers[i].vel.dy -= jImp * ny
                bumpers[j].vel.dx += jImp * nx
                bumpers[j].vel.dy += jImp * ny
            }
        }
    }

    private func resolveEliminations() {
        let limit = radius + marbleRadius * 0.3   // center past the rim = falling
        let playerID = bumpers.first(where: { $0.isPlayer })?.id
        var survivors: [Bumper] = []
        var playerFell = false
        for b in bumpers {
            let d = hypot(b.pos.x - center.x, b.pos.y - center.y)
            if d > limit {
                poofs.append(Poof(pos: b.pos, color: b.isPlayer ? .white : b.color, born: localTick))
                if b.isPlayer {
                    playerFell = true
                } else if b.lastHitBy == playerID {
                    knockouts += 1     // you shoved this one off — credit
                }
                if gameState.hapticsEnabled { Haptics.heavy() }
            } else {
                survivors.append(b)
            }
        }
        if survivors.count != bumpers.count { bumpers = survivors }
        if playerFell { endRun() }
    }

    /// Periodically feed in a fresh rival from near the rim so the pressure
    /// never lets up.  Capped so the floor doesn't get impossibly crowded.
    private func spawnWaveIfNeeded() {
        guard survivalTicks % spawnEveryTicks == 0, rivalsAlive < maxConcurrentRivals else { return }
        let angle = Double.random(in: 0..<(2 * .pi))
        let r = radius * 0.82
        let p = CGPoint(x: center.x + CGFloat(cos(angle)) * r,
                        y: center.y + CGFloat(sin(angle)) * r)
        let color = Self.rivalColors[Int.random(in: 0..<Self.rivalColors.count)]
        let rival = Bumper(pos: p, color: color, isPlayer: false)
        bumpers.append(rival)
        rivalLooks[rival.id] = RivalCosmetics.random()   // keystone: deal the wave rival a look
    }

    private func prunePoofs() {
        if !poofs.isEmpty {
            poofs.removeAll { localTick - $0.born > 26 }
        }
    }

    // MARK: - Pillar collision (S25)

    /// Resolve collisions between all marbles and the current map's pillar obstacles.
    /// Pillars have infinite mass — only the ball moves.
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

    private func unit(dx: CGFloat, dy: CGFloat, scale: CGFloat) -> CGVector {
        let m = hypot(dx, dy)
        guard m > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: dx / m * scale, dy: dy / m * scale)
    }
}

#Preview {
    NavigationStack {
        SumoSurvivalView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
