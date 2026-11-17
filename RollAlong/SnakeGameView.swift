import SwiftUI

// ===========================================================================
// SnakeGameView — the "Comet Clash" competitive mode (internal id "snake").
//
// A Tron light-cycle take on the shared marble.  Tilt rolls your comet, which
// leaves a glowing TRAIL behind it.  The trail is a solid, lethal wall — but
// it is NOT permanent.  Each piece of trail fades and disappears on its own,
// and touching ANY live trail (yours or a rival's) ends that comet's run.
//
// Trail length is A + B:
//   A — how long ago you were last in that spot.  Every trail node ages and
//       expires after a time-to-live; old wall vanishes from the tail.
//   B — how much you've collected / destroyed.  Each spark you grab and each
//       rival you wreck raises your TTL, so your wall lingers longer and
//       reaches further.  Early on your wall is short; late game it's a maze.
//
// Single-player by construction: rivals are AI comets (added in increment 2),
// so no second device is ever needed.
//
// SAFE BY CONSTRUCTION: a brand-new, isolated file.  It reuses only the shared
// physics primitives (BallMotion / PhysicsClock) and the coin / skin economy
// on GameState — it touches nothing in the climb engine.  Reached only when
// HomeView routes `.mode("snake")` here and SnakeMode is flagged on.
//
// FEEL IS TUNABLE: every gameplay number lives in the "Tunables" block.
// ===========================================================================

struct SnakeGameView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables

    private let headRadius:  CGFloat = 14         // the rolling comet head
    private let trailWidth:  CGFloat = 16         // drawn thickness of the wall
    // Speeds, the tail and the opponents' look-ahead all come from
    // `OpponentTuning` (GameState.swift) — change them there.
    private var accel:       CGFloat { CGFloat(OpponentTuning.cometPlayerPush) }   // tilt → acceleration
    private let friction:    CGFloat = 0.986      // per-tick velocity damping
    private var maxSpeed:    CGFloat { CGFloat(OpponentTuning.cometTopSpeed) }     // velocity clamp (pts/sec)
    private var minCruise:   CGFloat { CGFloat(OpponentTuning.cometCruiseSpeed) }  // always-forward drift
    private let wallBounce:  CGFloat = 0.50        // energy kept on an arena-wall hit (walls are NOT lethal)
    /// Distance between tail points.  Points are laid by DISTANCE travelled,
    /// so the tail is even at any speed.
    private var segmentStep: CGFloat { max(2, CGFloat(OpponentTuning.cometTailPointSpacing)) }

    /// Newest own-tail points a comet cannot hit (a wall bounce is survivable).
    private var safeSkipNodes: Int {
        Int((OpponentTuning.cometOwnTailIgnoreLength / max(2, OpponentTuning.cometTailPointSpacing)).rounded(.up))
    }
    private let maxTrailNodes  = 600               // hard safety cap per comet

    private let orbRadius:   CGFloat = 11
    private let orbCount       = 3                 // sparks live on the field at once
    private let coinsPerPower  = 3                 // coins banked per point of power
    private let winBonus       = 20                // coins for last-comet-standing
    private let poofLifeTicks  = 26                // death-burst animation length

    private let rivalCount     = 3                 // AI rival comets

    // Rival AI
    private let aiAvoidRadius: CGFloat = 34         // a probe within this of a wall or tail counts as blocked
    /// Own newest tail points the opponent ignores as obstacles (a little
    /// more than it is immune to, so it never plans a path it cannot survive).
    private var aiSelfSkip: Int { safeSkipNodes + 2 }

    /// Head-to-trail-centerline distance that counts as a fatal hit.
    private var collideDistance: CGFloat { headRadius + trailWidth * 0.35 }

    // MARK: - Model

    private struct TrailNode {
        var pos: CGPoint
        var birthTick: Int
    }

    private struct Cycle: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector = .zero
        var heading: CGFloat                   // radians; last real travel direction
        var trail: [TrailNode] = []
        /// Distance rolled since the last tail point was laid.
        var sinceNode: CGFloat = 0
        var collects = 0
        var kills = 0
        let colorIndex: Int
        let isPlayer: Bool
        var alive = true
        var power: Int { collects + kills }    // mechanic B
    }

    private struct Orb: Identifiable {
        let id = UUID()
        var pos: CGPoint
    }

    private struct Poof: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var colorIndex: Int
        var age = 0
    }

    private static let palette: [Color] = [
        Color(red: 0.30, green: 0.72, blue: 1.00),   // 0 — player cyan
        Color(red: 1.00, green: 0.42, blue: 0.42),   // 1 — red
        Color(red: 0.68, green: 0.50, blue: 1.00),   // 2 — violet
        Color(red: 1.00, green: 0.78, blue: 0.32),   // 3 — amber
    ]
    private static let playerColor = palette[0]

    // MARK: - State

    @State private var cycles: [Cycle] = []
    /// One brain per opponent (human limits from `OpponentTuning`), by index.
    @State private var brains: [Int: OpponentBrain] = [:]
    /// Ticks each opponent has seen its path blocked without reacting yet.
    @State private var blockedFor: [Int: Int] = [:]
    /// The heading each opponent has decided to steer toward (it turns toward
    /// it at its own turn rate and re-decides every few ticks).
    @State private var wantHeading: [Int: CGFloat] = [:]
    /// Each rival's keystone look (colorIndex → skin+trail+name), dealt in reset().
    @State private var rivalLooks: [Int: RivalCosmetics.Look] = [:]
    @State private var orbs:   [Orb]   = []
    @State private var poofs:  [Poof]  = []
    @State private var arena:  CGSize  = .zero
    @State private var localTick = 0

    @State private var started   = false
    @State private var isOver     = false
    @State private var playerWon  = false
    @State private var awarded     = false

    // Map cycling (S24)
    @State private var mapIndex   = 0
    @State private var showMapName = false
    @State private var walls:     [WallSegFrac] = []
    @State private var asteroids: [PillarFrac]  = []

    // MARK: - Computed

    private var playerCycle: Cycle? { cycles.first(where: { $0.isPlayer }) }
    private var totalRivals: Int { cycles.filter { !$0.isPlayer }.count }
    private var rivalsAlive: Int { cycles.filter { !$0.isPlayer && $0.alive }.count }
    /// The player's current tail length in points (shown in the top bar).
    private var playerTailLength: Int { Int(tailLength(power: playerCycle?.power ?? 0)) }

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.05), Color(white: 0.11)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Color.clear
                    StaticObstacleLayer(arena: arena, walls: walls, asteroids: asteroids,
                                        wallColor: gameState.equippedBoundary.color,
                                        wallEdge: gameState.equippedBoundary.edgeColor)
                        .equatable()
                        .allowsHitTesting(false)
                    trailsLayer.allowsHitTesting(false)
                    orbsLayer.allowsHitTesting(false)
                    ForEach(cycles.filter { $0.alive }) { c in
                        headView(c)
                            .overlay(alignment: .top) {
                                RivalNameTag(label: c.isPlayer ? "YOU" : (rivalLooks[c.colorIndex]?.name ?? "Rival"),
                                             color: c.isPlayer ? gameState.primaryColor : Self.palette[c.colorIndex % Self.palette.count],
                                             isPlayer: c.isPlayer,
                                             level: c.isPlayer ? gameState.highestUnlocked : nil)
                                    .offset(y: -12).allowsHitTesting(false)
                            }
                            .position(c.pos)
                    }
                    poofLayer.allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onAppear { arena = geo.size; reset() }
                .onChange(of: geo.size) { _, newSize in
                    arena = newSize
                    if cycles.isEmpty { reset() }
                }
                .onTapGesture {
                    if !started && !isOver {
                        started = true
                        AnalyticsClient.shared.track(
                            "comet_round_started",
                            properties: ["map_name": .string(CometClashMaps.maps[mapIndex % CometClashMaps.maps.count].name)]
                        )
                    }
                }
            }

            topBar
            if !started && !isOver { startPrompt }
            if isOver { gameOverOverlay }
            if showMapName && started { mapNameLabel }

            // S2-T2: trophy-unlock banner host — inert until the game-over
            // overlay drains the queue (never mid-match; §6).
            TrophyToastHost(queue: gameState.trophyToasts,
                            hapticsEnabled: gameState.hapticsEnabled,
                            soundEnabled: gameState.soundEnabled)
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

    private var trailsLayer: some View {
        Canvas { ctx, _ in
            for c in cycles {
                let t = c.trail
                guard !t.isEmpty else { continue }
                // One line through the tail points, in the order they were
                // laid, ending at the head.  Two points are only ever joined
                // when they are next to each other in space, so a line can
                // never sweep across the arena.
                let joinLimit = segmentStep * 4
                var path = Path()
                path.move(to: t[0].pos)
                var last = t[0].pos
                for k in 1..<t.count {
                    let p = t[k].pos
                    if abs(p.x - last.x) + abs(p.y - last.y) > joinLimit { path.move(to: p) }
                    else { path.addLine(to: p) }
                    last = p
                }
                if c.alive, abs(c.pos.x - last.x) + abs(c.pos.y - last.y) <= joinLimit {
                    path.addLine(to: c.pos)
                }
                let col = Self.palette[c.colorIndex % Self.palette.count]
                ctx.stroke(path,
                           with: .color(col.opacity(0.28)),
                           style: StrokeStyle(lineWidth: trailWidth + 7, lineCap: .round, lineJoin: .round))
                ctx.stroke(path,
                           with: .linearGradient(
                                Gradient(colors: [col.opacity(0.22), col]),
                                startPoint: t[0].pos, endPoint: c.alive ? c.pos : t[t.count - 1].pos),
                           style: StrokeStyle(lineWidth: trailWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private var orbsLayer: some View {
        ForEach(orbs) { orb in
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.90, blue: 0.50).opacity(0.30))
                    .frame(width: orbRadius * 3, height: orbRadius * 3)
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(red: 1.0, green: 0.84, blue: 0.34)],
                                         center: .center, startRadius: 0, endRadius: orbRadius))
                    .frame(width: orbRadius * 2, height: orbRadius * 2)
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
            }
            .position(orb.pos)
        }
    }

    private func headView(_ c: Cycle) -> some View {
        let col = Self.palette[c.colorIndex % Self.palette.count]
        return ZStack {
            if c.isPlayer {
                BallSkinView(skin: gameState.activeSkin, diameter: headRadius * 2)
                    .overlay(Circle().stroke(col, lineWidth: 2.5))
            } else {
                // Keystone: each rival comet shows off a real ball skin (its
                // lethal wall stays palette-coloured — that's a game mechanic).
                let skin = rivalLooks[c.colorIndex]?.skin ?? .red
                BallSkinView(skin: skin, diameter: headRadius * 2)
                    .overlay(Circle().stroke(col.opacity(0.9), lineWidth: 2))
            }
        }
        .frame(width: headRadius * 2, height: headRadius * 2)
        .shadow(color: col.opacity(0.7), radius: 8)
    }

    private var poofLayer: some View {
        ForEach(poofs) { p in
            let f = CGFloat(p.age) / CGFloat(poofLifeTicks)        // 0 → 1 over its life
            let col = Self.palette[p.colorIndex % Self.palette.count]
            let ring = headRadius * 2 + f * 64
            ZStack {
                Circle()
                    .stroke(col.opacity(Double(1 - f)), lineWidth: 3.5 * (1 - f) + 0.5)
                    .frame(width: ring, height: ring)
                Circle()
                    .fill(col.opacity(Double((1 - f) * 0.5)))
                    .frame(width: headRadius * 2 * (1 - f), height: headRadius * 2 * (1 - f))
            }
            .position(p.pos)
        }
    }

    // MARK: - HUD / overlays

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
                Spacer()
                VStack(spacing: 1) {
                    Text("\(playerCycle?.power ?? 0)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("CHARGE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                        .tracking(1)
                    Text("tail \(playerTailLength)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Self.playerColor.opacity(0.9))
                        .monospacedDigit()
                }
                Spacer()
                rivalsPip
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            Spacer()
        }
    }

    @ViewBuilder
    private var rivalsPip: some View {
        if totalRivals > 0 {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(cycles.filter { !$0.isPlayer }) { r in
                        Circle()
                            .fill(r.alive ? Self.palette[r.colorIndex % Self.palette.count]
                                          : Color(white: 0.22))
                            .frame(width: 9, height: 9)
                    }
                }
                Text("RIVALS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Color(white: 0.5))
            }
            .frame(width: 56, alignment: .trailing)
        } else {
            Color.clear.frame(width: 38, height: 38)
        }
    }

    private var startPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Self.playerColor)
            Text("Tilt to play")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Leave a glowing trail.  Grab sparks to make\nyour wall last longer.  Touching any trail is fatal.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
            MinigameDifficultyPicker(selection: $gameState.minigameDifficulty)
                .padding(.top, 6)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Comet Clash. Tilt to steer your comet. Leave a glowing trail. Grab sparks to extend your wall. Touching any trail eliminates you. Tap anywhere to begin.")
    }

    private var gameOverOverlay: some View {
        let power = playerCycle?.power ?? 0
        let kills = playerCycle?.kills ?? 0
        let collects = playerCycle?.collects ?? 0
        let banked = gameState.minigamePayout(base: power * coinsPerPower + (playerWon ? winBonus : 0),
                                              difficulty: gameState.minigameDifficulty)
        let title = playerWon ? "You Win!" : "Eliminated"
        let titleColor: Color = playerWon ? Color(red: 0.45, green: 0.88, blue: 0.55)
                                          : Color(red: 1.00, green: 0.45, blue: 0.45)
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(titleColor)
                    Text("charged to \(power) · \(kills) KO · \(collects) sparks")
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
                        mapIndex = (mapIndex + 1) % CometClashMaps.maps.count
                        reset()
                    } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Self.playerColor))
                    }
                    ResultShareButton(result: ShareableResult(
                        mode: "Comet Clash",
                        headline: "\(kills) KOs",
                        subtitle: playerWon ? "Last comet standing ☄️" : "charged to \(power)",
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
        // S2-T2: match ended — drain this match's trophies, coalesced (§6).
        .onAppear { gameState.endTrophyRun() }
    }

    private var mapNameLabel: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 90)
            Text(CometClashMaps.maps[mapIndex % CometClashMaps.maps.count].name)
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

    // MARK: - Lifecycle

    private func reset() {
        guard arena.width > 0, arena.height > 0 else { return }
        // S2-T2: fresh match — arm the toast queue (§6 coalesce-at-run-end).
        gameState.beginTrophyRun()
        localTick = 0
        started = false
        isOver = false
        playerWon = false
        awarded = false
        brains = [:]
        blockedFor = [:]

        wantHeading = [:]

        // The map first: starting places depend on its walls and rocks.
        loadMap()

        // Every comet starts in open space, in the same connected area, well
        // apart from the others.  The player gets the place nearest the
        // bottom middle.
        let starts = openStarts(count: 1 + rivalCount)
        var fresh: [Cycle] = []
        for (n, start) in starts.enumerated() {
            if n == 0 {
                fresh.append(Cycle(pos: start.pos, heading: start.heading,
                                   colorIndex: 0, isPlayer: true))
            } else {
                fresh.append(Cycle(pos: start.pos, heading: start.heading,
                                   colorIndex: ((n - 1) % (Self.palette.count - 1)) + 1,
                                   isPlayer: false))
            }
        }

        // Each opponent draws its own skill for the round — one clumsy, one
        // average, one sharp — and keeps it until the next round.
        let skills = OpponentTuning.dealSkills(rivalCount)
        var freshBrains: [Int: OpponentBrain] = [:]
        for n in 1..<fresh.count {
            freshBrains[n] = OpponentBrain(difficulty: gameState.minigameDifficulty,
                                           skill: skills[(n - 1) % max(1, skills.count)])
        }
        brains = freshBrains

        let rivals = fresh.filter { !$0.isPlayer }
        rivalLooks = Dictionary(uniqueKeysWithValues:
            zip(rivals.map(\.colorIndex), RivalCosmetics.deal(rivals.count)))
        cycles = fresh

        orbs = []
        for _ in 0..<orbCount { orbs.append(Orb(pos: randomOrbPoint())) }
    }

    private func loadMap() {
        let map = CometClashMaps.maps[mapIndex % CometClashMaps.maps.count]
        walls     = map.walls
        asteroids = map.asteroids
        showMapName = true
    }

    private func endRun(didWin: Bool) {
        guard !isOver else { return }
        isOver = true
        playerWon = didWin
        if !awarded {
            awarded = true
            let power = playerCycle?.power ?? 0
            let kills = playerCycle?.kills ?? 0
            let collects = playerCycle?.collects ?? 0
            let base = power * coinsPerPower + (didWin ? winBonus : 0)
            gameState.recordCompetitiveScore("snake", power)   // leaderboard best
            // Difficulty scales the payout + records the attempt/win for tracking
            // (also banks the coins and, on a win, bumps the tally + ticket).
            // Placement: 1st when you outlive everyone, else one place per
            // opponent still alive when you fell.
            let banked = gameState.recordMinigameResult(
                modeID: "snake", difficulty: gameState.minigameDifficulty,
                won: didWin, score: power, basePayout: base,
                placement: didWin ? 1 : 1 + rivalsAlive,
                bestRivalScore: cycles.filter { !$0.isPlayer }.map(\.power).max() ?? 0,
                durationSeconds: localTick / 60)
            AnalyticsClient.shared.track(
                "comet_round_over",
                properties: ["won": .bool(didWin),
                             "difficulty": .string(gameState.minigameDifficulty.rawValue),
                             "power": .int(power),
                             "kills": .int(kills),
                             "collects": .int(collects),
                             "base_coins": .int(base),
                             "coins": .int(banked),
                             "map_name": .string(CometClashMaps.maps[mapIndex % CometClashMaps.maps.count].name)]
            )
            if didWin {
                AnalyticsClient.shared.track("ticket_earned",
                                             properties: ["source": .string("snake")])
            }
            if gameState.hapticsEnabled {
                if didWin { Haptics.success() } else { Haptics.warning() }
            }
            gameState.maybeRequestReview(after: didWin)
        }
    }

    // MARK: - Simulation

    private func tick() {
        // `started` remains false until the player taps — this guard also
        // covers the clock/GeometryReader race: ticks can fire in .onAppear
        // before the GeometryReader delivers its first size, but they are
        // silently discarded here.  The arena.width > 1 check is a secondary
        // safety net for any future path that sets `started` early.
        guard started, !isOver, arena.width > 1, arena.height > 1 else { return }
        localTick &+= 1
        let dt: CGFloat = 1.0 / 60.0

        // 1) Steer + integrate every living comet, laying tail as it goes.
        for i in cycles.indices where cycles[i].alive {
            let before = cycles[i].pos
            if cycles[i].isPlayer {
                cycles[i].vel.dx += CGFloat(motion.gravity.x) * accel * dt
                cycles[i].vel.dy += CGFloat(motion.gravity.y) * accel * dt
                cycles[i].vel.dx *= friction
                cycles[i].vel.dy *= friction

                var sp = hypot(cycles[i].vel.dx, cycles[i].vel.dy)
                if sp > 1 { cycles[i].heading = atan2(cycles[i].vel.dy, cycles[i].vel.dx) }
                if sp < minCruise {
                    cycles[i].vel.dx = cos(cycles[i].heading) * minCruise
                    cycles[i].vel.dy = sin(cycles[i].heading) * minCruise
                    sp = minCruise
                }
                if sp > maxSpeed { let k = maxSpeed / sp; cycles[i].vel.dx *= k; cycles[i].vel.dy *= k }
            } else {
                aiDrive(i, dt: dt)
            }

            cycles[i].pos.x += cycles[i].vel.dx * dt
            cycles[i].pos.y += cycles[i].vel.dy * dt
            bounceWalls(&cycles[i])
            for seg in walls     { resolveWallCollision(&cycles[i], seg: seg) }
            for ast in asteroids { resolveAsteroidCollision(&cycles[i], ast: ast) }
            // A bounce changes the direction of travel: keep the heading true.
            let after = hypot(cycles[i].vel.dx, cycles[i].vel.dy)
            if after > 1 { cycles[i].heading = atan2(cycles[i].vel.dy, cycles[i].vel.dx) }

            // 2) Lay tail along the stretch just rolled.
            layTail(i, from: before, to: cycles[i].pos)
        }

        // 3) Age out old wall (dead comets' walls keep fading too).
        //    maxTrailNodes cap is enforced here — BEFORE resolveCollisions() in
        //    step 4.  This keeps the O(comets × total_trail_nodes) collision
        //    loop bounded at 4 × 600 = 2 400 nodes in the worst case.
        for i in cycles.indices { prune(i) }

        // 4) Sparks, death bursts, fatal trails, then win/lose.
        collectOrbs()
        agePoofs()
        resolveCollisions()
        evaluateEnd()
    }

    /// Lay tail points along the straight stretch from `a` to `b`, exactly
    /// `segmentStep` apart measured along the path — so the tail is the same
    /// behind a slow comet and a fast one.  A laid point never moves.
    private func layTail(_ i: Int, from a: CGPoint, to b: CGPoint) {
        let d = hypot(b.x - a.x, b.y - a.y)
        guard d > 0 else { return }
        let step = segmentStep
        var carried = cycles[i].sinceNode
        var at: CGFloat = 0
        var laid = 0
        while carried + (d - at) >= step && laid < 64 {
            at += step - carried
            carried = 0
            let t = at / d
            cycles[i].trail.append(TrailNode(pos: CGPoint(x: a.x + (b.x - a.x) * t,
                                                          y: a.y + (b.y - a.y) * t),
                                             birthTick: localTick))
            laid += 1
        }
        cycles[i].sinceNode = carried + (d - at)
    }

    /// How long a tail may be right now (points): it starts short, grows with
    /// the round, and grows with charge.
    private func tailLength(power: Int) -> CGFloat {
        let seconds = Double(localTick) / 60.0
        let length = OpponentTuning.cometTailStartLength
            + OpponentTuning.cometTailGrowthPerSecond * seconds
            + OpponentTuning.cometTailPerCharge * Double(power)
        return CGFloat(min(OpponentTuning.cometTailMaxLength, max(0, length)))
    }

    /// Drop the oldest tail beyond the allowed length, at once.  A knocked-out
    /// comet's tail is eaten away from the back until it is gone.
    private func prune(_ idx: Int) {
        let count = cycles[idx].trail.count
        guard count > 0 else { return }
        if cycles[idx].alive {
            let allowed = min(maxTrailNodes, Int(tailLength(power: cycles[idx].power) / segmentStep))
            if count > allowed { cycles[idx].trail.removeFirst(count - allowed) }
        } else {
            let fadeTicks = max(1.0, OpponentTuning.cometDeadTailFadeSeconds * 60)
            let longestTail = OpponentTuning.cometTailMaxLength / Double(segmentStep)   // in points of tail
            let perTick = max(1, Int((longestTail / fadeTicks).rounded(.up)))
            cycles[idx].trail.removeFirst(min(count, perTick))
        }
    }

    private func agePoofs() {
        for j in poofs.indices { poofs[j].age += 1 }
        poofs.removeAll { $0.age >= poofLifeTicks }
    }

    private func collectOrbs() {
        let reach = (headRadius + orbRadius) * (headRadius + orbRadius)
        for ci in cycles.indices where cycles[ci].alive {
            let h = cycles[ci].pos
            for oi in orbs.indices {
                let dx = h.x - orbs[oi].pos.x, dy = h.y - orbs[oi].pos.y
                if dx * dx + dy * dy <= reach {
                    cycles[ci].collects += 1
                    if cycles[ci].isPlayer && gameState.hapticsEnabled { Haptics.light() }
                    orbs[oi].pos = randomOrbPoint()
                }
            }
        }
    }

    /// Any head touching any live trail dies.  If the wall belonged to another
    /// comet, that comet banks the kill (+1 power → a longer-lasting wall).
    private func resolveCollisions() {
        var died: [Int] = []
        var credit: [Int] = []
        let lethal2 = collideDistance * collideDistance
        for xi in cycles.indices where cycles[xi].alive {
            let h = cycles[xi].pos
            var hit = false
            var killer = -1
            for yi in cycles.indices {
                let trail = cycles[yi].trail
                let isSelf = (yi == xi)
                let upper = isSelf ? max(0, trail.count - safeSkipNodes) : trail.count
                var k = 0
                while k < upper {
                    let dx = h.x - trail[k].pos.x, dy = h.y - trail[k].pos.y
                    if dx * dx + dy * dy < lethal2 {
                        hit = true
                        killer = isSelf ? -1 : yi
                        break
                    }
                    k += 1
                }
                if hit { break }
            }
            if hit { died.append(xi); credit.append(killer) }
        }
        guard !died.isEmpty else { return }
        for n in died.indices {
            let xi = died[n]
            cycles[xi].alive = false
            poofs.append(Poof(pos: cycles[xi].pos, colorIndex: cycles[xi].colorIndex))
            if cycles[xi].isPlayer && gameState.hapticsEnabled { Haptics.heavy() }
            if credit[n] >= 0 { cycles[credit[n]].kills += 1 }
        }
    }

    private func evaluateEnd() {
        guard !isOver else { return }
        let alive = playerCycle?.alive ?? false
        if !alive { endRun(didWin: false); return }
        if totalRivals > 0 && rivalsAlive == 0 { endRun(didWin: true) }
    }

    private func bounceWalls(_ c: inout Cycle) {
        bounceEdges(pos: &c.pos, vel: &c.vel,
                    radius: headRadius, arena: arena, restitution: wallBounce)
    }

    private func clampInside(_ p: CGPoint) -> CGPoint {
        let m = headRadius + 6
        return CGPoint(x: min(max(p.x, m), arena.width - m),
                       y: min(max(p.y, m), arena.height - m))
    }

    // MARK: - Static collision (S24)

    /// Reflect a comet off an interior wall segment.
    private func resolveWallCollision(_ c: inout Cycle, seg: WallSegFrac) {
        let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
        let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
        resolveWallSegment(pos: &c.pos, vel: &c.vel,
                           p1: p1, p2: p2,
                           radius: headRadius, restitution: wallBounce)
    }

    /// Reflect a comet off a circular asteroid rock.
    private func resolveAsteroidCollision(_ c: inout Cycle, ast: PillarFrac) {
        let centre = CGPoint(x: ast.cx * arena.width, y: ast.cy * arena.height)
        resolveCircleObstacle(pos: &c.pos, vel: &c.vel,
                              centre: centre, obstacleRadius: ast.r,
                              ballRadius: headRadius, restitution: wallBounce)
    }

    /// True if an orb spawn candidate is too close to a wall or asteroid.
    private func isOrbBlocked(_ p: CGPoint) -> Bool {
        let margin = orbRadius + headRadius + 6
        for seg in walls {
            let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
            let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
            let dx = p2.x - p1.x, dy = p2.y - p1.y
            let lenSq = dx * dx + dy * dy
            guard lenSq > 0 else { continue }
            let t = max(0, min(1, ((p.x - p1.x) * dx + (p.y - p1.y) * dy) / lenSq))
            if hypot(p.x - (p1.x + t * dx), p.y - (p1.y + t * dy)) < margin { return true }
        }
        for ast in asteroids {
            if hypot(p.x - ast.cx * arena.width, p.y - ast.cy * arena.height) < margin + ast.r {
                return true
            }
        }
        return false
    }

    private func randomOrbPoint() -> CGPoint {
        let m = orbRadius + 18
        let loX = m, hiX = arena.width - m
        let loY = m, hiY = arena.height - m
        guard hiX > loX, hiY > loY else { return CGPoint(x: arena.width / 2, y: arena.height / 2) }
        for _ in 0..<12 {
            let p = CGPoint(x: CGFloat.random(in: loX...hiX),
                            y: CGFloat.random(in: loY...hiY))
            if !isOrbBlocked(p) { return p }
        }
        return CGPoint(x: arena.width / 2, y: arena.height / 2)
    }

    // MARK: - Rival AI

    /// Drive one opponent for a tick.  It steers like a person: it decides
    /// on a heading, turns toward it no faster than its turn rate, and rolls
    /// at its own top speed.  Avoiding trails and walls comes FIRST; going
    /// for a spark comes second (see `planHeading`).
    /// Human limits (`OpponentTuning`): it re-decides only every so often
    /// (reaction delay), aims at the spark with a held error, turns and rolls
    /// according to its effort, and during a mistake looks only a short way
    /// ahead.  No mistakes in the opening seconds of a round.
    private func aiDrive(_ i: Int, dt: CGFloat) {
        let c = cycles[i]
        var brain = brains[i] ?? OpponentBrain(difficulty: gameState.minigameDifficulty)
        brain.advance()

        let inGrace = Double(localTick) < OpponentTuning.cometGraceSeconds * 60
        let mistaking = brain.isMistaking && !inGrace
        let effort = min(1, max(0, brain.effort))

        // Its own top speed and turn rate.
        let floorShare = CGFloat(OpponentTuning.cometOpponentSpeedFloor)
        let topSpeed = max(minCruise, maxSpeed * (floorShare + (1 - floorShare) * effort))
        let slowTurn = CGFloat(OpponentTuning.cometTurnSlowDegrees)
        let fastTurn = CGFloat(OpponentTuning.cometTurnFastDegrees)
        let turnRate = (slowTurn + (fastTurn - slowTurn) * effort) * .pi / 180

        var speed = hypot(c.vel.dx, c.vel.dy)

        // How far ahead it looks: further when faster, much less mid-mistake.
        var look = max(CGFloat(OpponentTuning.cometLookAheadMin),
                       max(speed, minCruise) * CGFloat(OpponentTuning.cometLookAheadSeconds))
        if mistaking { look *= CGFloat(OpponentTuning.cometMistakeLookShare) }

        // Where it believes the nearest spark is (one reaction delay ago).
        var seenSpark: CGPoint? = nil
        if let spark = nearestOrb(to: c.pos) { seenSpark = brain.perceive(spark) }

        // Re-decide every few ticks; in between keep turning toward the plan.
        let every = max(2, Int((Double(brain.delayTicks) * OpponentTuning.cometReplanDelayShare).rounded()))
        var want = wantHeading[i] ?? c.heading
        if wantHeading[i] == nil || (localTick + i * 3) % every == 0 {
            want = planHeading(i, brain: brain, spark: seenSpark, look: look)
        }
        wantHeading[i] = want

        // Turn toward the plan, no faster than the turn rate.
        var diff = want - c.heading
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        let maxStep = turnRate * dt
        let heading = c.heading + min(maxStep, max(-maxStep, diff))

        // Get up to speed.
        speed = min(topSpeed, speed + CGFloat(OpponentTuning.cometOpponentSpeedUp) * dt)
        speed = max(minCruise, speed)

        cycles[i].heading = heading
        cycles[i].vel = CGVector(dx: cos(heading) * speed, dy: sin(heading) * speed)
        brains[i] = brain
    }

    /// Choose a heading.  Thirteen directions fanned around the current
    /// heading (out to 120° either side) plus the direct line to the spark
    /// are each scored: how far the way is clear counts most, pointing toward
    /// the spark counts second, and a small cost discourages needless turns.
    private func planHeading(_ i: Int, brain: OpponentBrain, spark: CGPoint?, look: CGFloat) -> CGFloat {
        let c = cycles[i]
        var goal = c.heading
        if let spark {
            let u = brain.aimed(dx: spark.x - c.pos.x, dy: spark.y - c.pos.y)
            if u.dx != 0 || u.dy != 0 { goal = atan2(u.dy, u.dx) }
        }
        var goalOffset = goal - c.heading
        while goalOffset > .pi { goalOffset -= 2 * .pi }
        while goalOffset < -.pi { goalOffset += 2 * .pi }

        var offsets: [CGFloat] = []
        for k in -6...6 { offsets.append(CGFloat(k) * (.pi / 9)) }      // 20° steps
        if abs(goalOffset) <= 2 * .pi / 3 { offsets.append(goalOffset) }

        var best = c.heading
        var bestScore = -CGFloat.greatestFiniteMagnitude
        for offset in offsets {
            let h = c.heading + offset
            let free = freeDistance(from: c.pos, heading: h, limit: look, for: i)
            let clear: CGFloat = look > 0 ? free / look : 0              // 0…1
            let toward: CGFloat = cos(h - goal)                          // −1…1
            let score: CGFloat = 2.0 * clear + 0.3 * toward - 0.05 * abs(offset)
            if score > bestScore { bestScore = score; best = h }
        }
        return best
    }

    /// How far (up to `limit`) the way is clear along a heading: the distance
    /// to the first point that is on a tail, near a wall or rock, or off the
    /// arena.
    private func freeDistance(from p: CGPoint, heading: CGFloat, limit: CGFloat, for i: Int) -> CGFloat {
        let step: CGFloat = 12
        let ux = cos(heading), uy = sin(heading)
        var d = step
        while d <= limit {
            if isBlocked(CGPoint(x: p.x + ux * d, y: p.y + uy * d), for: i) { return d - step }
            d += step
        }
        return limit
    }

    // MARK: - Starting places

    /// Distance from a point to the nearest wall, rock or arena edge.
    private func staticClearance(_ p: CGPoint) -> CGFloat {
        var nearest = min(min(p.x, arena.width - p.x), min(p.y, arena.height - p.y))
        for seg in walls {
            let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
            let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
            let dx = p2.x - p1.x, dy = p2.y - p1.y
            let lenSq = dx * dx + dy * dy
            guard lenSq > 0 else { continue }
            let t = max(0, min(1, ((p.x - p1.x) * dx + (p.y - p1.y) * dy) / lenSq))
            nearest = min(nearest, hypot(p.x - (p1.x + t * dx), p.y - (p1.y + t * dy)))
        }
        for ast in asteroids {
            nearest = min(nearest, hypot(p.x - ast.cx * arena.width, p.y - ast.cy * arena.height) - ast.r)
        }
        return nearest
    }

    /// Starting places for `count` comets (the player's first).
    ///
    /// The arena is cut into small cells.  A cell is passable when a comet
    /// fits there.  The largest connected group of passable cells is the
    /// open play area — so nobody can start sealed inside a closed shape.
    /// Inside it, the player gets the roomy cell nearest the bottom middle,
    /// and each opponent in turn gets the roomy cell farthest from everyone
    /// already placed.  Each comet starts facing the way with the most room.
    private func openStarts(count: Int) -> [(pos: CGPoint, heading: CGFloat)] {
        let cell: CGFloat = 16
        let cols = max(1, Int(arena.width / cell))
        let rows = max(1, Int(arena.height / cell))
        let cw = arena.width / CGFloat(cols), ch = arena.height / CGFloat(rows)
        let fits = headRadius + 6
        let topReserve: CGFloat = min(110, arena.height * 0.16)          // clear of the top bar

        var room = [CGFloat](repeating: 0, count: cols * rows)
        var open = [Bool](repeating: false, count: cols * rows)
        for r in 0..<rows {
            for col in 0..<cols {
                let p = CGPoint(x: (CGFloat(col) + 0.5) * cw, y: (CGFloat(r) + 0.5) * ch)
                let clear = staticClearance(p)
                room[r * cols + col] = clear
                open[r * cols + col] = clear >= fits
            }
        }

        // Group the passable cells into connected areas; keep the largest.
        var area = [Int](repeating: -1, count: cols * rows)
        var sizes: [Int] = []
        for startCell in 0..<(cols * rows) where open[startCell] && area[startCell] < 0 {
            let label = sizes.count
            var size = 0
            var stack = [startCell]
            area[startCell] = label
            while let cur = stack.popLast() {
                size += 1
                let r = cur / cols, col = cur % cols
                if col > 0        { let n = cur - 1;    if open[n] && area[n] < 0 { area[n] = label; stack.append(n) } }
                if col < cols - 1 { let n = cur + 1;    if open[n] && area[n] < 0 { area[n] = label; stack.append(n) } }
                if r > 0          { let n = cur - cols; if open[n] && area[n] < 0 { area[n] = label; stack.append(n) } }
                if r < rows - 1   { let n = cur + cols; if open[n] && area[n] < 0 { area[n] = label; stack.append(n) } }
            }
            sizes.append(size)
        }

        func point(_ index: Int) -> CGPoint {
            CGPoint(x: (CGFloat(index % cols) + 0.5) * cw, y: (CGFloat(index / cols) + 0.5) * ch)
        }

        var candidates: [Int] = []
        if let biggest = sizes.indices.max(by: { sizes[$0] < sizes[$1] }) {
            // Prefer roomy cells; relax the room needed if the map is tight.
            var need = CGFloat(OpponentTuning.cometStartClearance)
            while candidates.count < count * 3 && need >= fits {
                candidates = (0..<(cols * rows)).filter {
                    area[$0] == biggest && room[$0] >= need && point($0).y >= topReserve
                }
                need -= 6
            }
        }

        var chosen: [CGPoint] = []
        if !candidates.isEmpty {
            // The player: nearest the bottom middle.
            let home = CGPoint(x: arena.width * 0.5, y: arena.height * 0.80)
            var firstPoint = point(candidates[0])
            var firstGap = CGFloat.greatestFiniteMagnitude
            for index in candidates {
                let p = point(index)
                let gap = hypot(p.x - home.x, p.y - home.y)
                if gap < firstGap { firstGap = gap; firstPoint = p }
            }
            chosen.append(firstPoint)
            // Everyone else: as far as possible from all already placed.
            while chosen.count < count {
                var bestPoint = chosen[0]
                var bestGap: CGFloat = -1
                for index in candidates {
                    let p = point(index)
                    var gap = CGFloat.greatestFiniteMagnitude
                    for q in chosen { gap = min(gap, hypot(p.x - q.x, p.y - q.y)) }
                    if gap > bestGap { bestGap = gap; bestPoint = p }
                }
                chosen.append(bestPoint)
            }
        }
        // Last resort (an arena with no open cell at all): the old ring.
        while chosen.count < count {
            let n = chosen.count
            let ang = (Double(n) / Double(max(1, count))) * 2 * Double.pi + Double.pi / 2
            chosen.append(clampInside(CGPoint(x: arena.width / 2 + CGFloat(cos(ang)) * arena.width * 0.3,
                                              y: arena.height / 2 + CGFloat(sin(ang)) * arena.height * 0.3)))
        }

        // Face the way with the most room (walls and rocks only: no tails yet).
        var result: [(pos: CGPoint, heading: CGFloat)] = []
        for p in chosen {
            var bestHeading: CGFloat = -.pi / 2
            var bestFree: CGFloat = -1
            for k in 0..<8 {
                let h = CGFloat(k) * (.pi / 4) - .pi / 2
                var d: CGFloat = 12
                while d <= 240 {
                    let q = CGPoint(x: p.x + cos(h) * d, y: p.y + sin(h) * d)
                    if staticClearance(q) < fits { break }
                    d += 12
                }
                if d > bestFree + 0.5 { bestFree = d; bestHeading = h }
            }
            result.append((pos: p, heading: bestHeading))
        }
        return result
    }

    private func project(from p: CGPoint, heading: CGFloat, dist: CGFloat) -> CGPoint {
        CGPoint(x: p.x + cos(heading) * dist, y: p.y + sin(heading) * dist)
    }

    private func unit(_ dx: CGFloat, _ dy: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let m = hypot(dx, dy)
        guard m > 0 else { return (0, 0) }
        return (dx / m, dy / m)
    }

    private func nearestOrb(to p: CGPoint) -> CGPoint? {
        var best: CGPoint? = nil
        var bestD = CGFloat.greatestFiniteMagnitude
        for o in orbs {
            let d = (o.pos.x - p.x) * (o.pos.x - p.x) + (o.pos.y - p.y) * (o.pos.y - p.y)
            if d < bestD { bestD = d; best = o.pos }
        }
        return best
    }

    /// True if a probe point is off the arena, on a live trail, near a wall, or
    /// overlapping an asteroid.
    private func isBlocked(_ p: CGPoint, for i: Int) -> Bool {
        let m = headRadius
        if p.x < m || p.x > arena.width - m || p.y < m || p.y > arena.height - m { return true }
        // Trails
        let r2 = aiAvoidRadius * aiAvoidRadius
        for yi in cycles.indices {
            let trail = cycles[yi].trail
            let upper = (yi == i) ? max(0, trail.count - aiSelfSkip) : trail.count
            var k = 0
            while k < upper {
                let dx = p.x - trail[k].pos.x, dy = p.y - trail[k].pos.y
                if dx * dx + dy * dy < r2 { return true }
                k += 1
            }
        }
        // Interior walls
        for seg in walls {
            let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
            let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
            let dx = p2.x - p1.x, dy = p2.y - p1.y
            let lenSq = dx * dx + dy * dy
            guard lenSq > 0 else { continue }
            let t = max(0, min(1, ((p.x - p1.x) * dx + (p.y - p1.y) * dy) / lenSq))
            if hypot(p.x - (p1.x + t * dx), p.y - (p1.y + t * dy)) < aiAvoidRadius { return true }
        }
        // Asteroids
        for ast in asteroids {
            if hypot(p.x - ast.cx * arena.width, p.y - ast.cy * arena.height) < aiAvoidRadius + ast.r {
                return true
            }
        }
        return false
    }

    /// Open space around a probe point: distance to the nearest wall, trail, or asteroid.
    /// Off-arena probes return a negative score so they're never preferred.
    private func clearance(_ p: CGPoint, for i: Int) -> CGFloat {
        let m = headRadius
        if p.x < m || p.x > arena.width - m || p.y < m || p.y > arena.height - m { return -1 }
        var nearest = min(min(p.x, arena.width - p.x), min(p.y, arena.height - p.y))
        // Trails
        for yi in cycles.indices {
            let trail = cycles[yi].trail
            let upper = (yi == i) ? max(0, trail.count - aiSelfSkip) : trail.count
            var k = 0
            while k < upper {
                let dx = p.x - trail[k].pos.x, dy = p.y - trail[k].pos.y
                let d = dx * dx + dy * dy
                if d < nearest * nearest { nearest = sqrt(d) }
                k += 1
            }
        }
        // Interior walls
        for seg in walls {
            let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
            let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
            let dx = p2.x - p1.x, dy = p2.y - p1.y
            let lenSq = dx * dx + dy * dy
            guard lenSq > 0 else { continue }
            let t = max(0, min(1, ((p.x - p1.x) * dx + (p.y - p1.y) * dy) / lenSq))
            let d = hypot(p.x - (p1.x + t * dx), p.y - (p1.y + t * dy))
            if d < nearest { nearest = d }
        }
        // Asteroids
        for ast in asteroids {
            let d = max(0, hypot(p.x - ast.cx * arena.width, p.y - ast.cy * arena.height) - ast.r)
            if d < nearest { nearest = d }
        }
        return nearest
    }
}

// MARK: - Static obstacle layer (extracted for equatable skip)

/// Interior walls and asteroid rocks, drawn below trails every frame.
/// Extracted as a separate `View` struct so SwiftUI can skip re-rendering it
/// on every physics tick — `.equatable()` at the call site lets the engine
/// compare `arena`, `walls`, and `asteroids` and bail out if nothing changed.
private struct StaticObstacleLayer: View, Equatable {
    let arena:    CGSize
    let walls:    [WallSegFrac]
    let asteroids: [PillarFrac]
    /// Equipped Boundary cosmetic colours (themes the interior walls).
    var wallColor: Color = Color(white: 0.30)
    var wallEdge:  Color = Color(white: 0.55)

    var body: some View {
        Canvas { ctx, _ in
            guard arena.width > 0 else { return }
            for seg in walls {
                let p1 = CGPoint(x: seg.x1 * arena.width, y: seg.y1 * arena.height)
                let p2 = CGPoint(x: seg.x2 * arena.width, y: seg.y2 * arena.height)
                var path = Path(); path.move(to: p1); path.addLine(to: p2)
                ctx.stroke(path, with: .color(wallColor.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round))
                ctx.stroke(path, with: .color(wallEdge.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            for ast in asteroids {
                let cx = ast.cx * arena.width, cy = ast.cy * arena.height
                let rect = CGRect(x: cx - ast.r, y: cy - ast.r,
                                  width: ast.r * 2, height: ast.r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.24)))
                ctx.stroke(Path(ellipseIn: rect),
                           with: .color(Color(white: 0.42).opacity(0.8)), lineWidth: 2)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SnakeGameView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
