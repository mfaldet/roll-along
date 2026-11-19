import SwiftUI

// ===========================================================================
// KingOfTheHillView — the "King of the Hill" competitive mode.
//
// A 60-second scrap over a glowing zone that DRIFTS around the arena.  Tilt
// your marble into the zone and hold it — but only while you're alone in it.
// The moment a rival rolls in too, the hill is CONTESTED and nobody banks
// time, so you have to shove them out to keep scoring.  Most hold-time when
// the clock hits zero wins.
//
// Single-player vs AI: the bots converge on the hill, so the zone is always
// a fight.  No second device needed.
//
// SAFE BY CONSTRUCTION: an isolated file.  It reuses only the shared physics
// primitives (BallMotion / PhysicsClock) and the coin / skin economy on
// GameState; it touches nothing in the climb engine.  Reached only when
// HomeView routes `.mode("koth")` here and KingOfTheHillMode is flagged on.
//
// FEEL IS TUNABLE: every gameplay number lives in the "Tunables" block.
// ===========================================================================

struct KingOfTheHillView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables

    private let marbleRadius: CGFloat = 17
    private let playerAccel:  CGFloat = 1_500
    /// Full opponent push.  Each opponent uses its effort share of this
    /// (`OpponentTuning`).
    private let aiAccelBase:  CGFloat = 1_250
    private let friction:     CGFloat = 0.990
    private let maxSpeed:     CGFloat = 660
    private let wallBounce:   CGFloat = 0.70
    private let restitution:  CGFloat = 0.86   // used for marble↔pillar bounces
    /// Ball-to-ball knockback: a struck marble flies off at this multiple of the
    /// impact (closing) speed…
    private let knockbackGain: CGFloat = 2.0
    /// …and never separates slower than this, so AI marbles can't jam up and
    /// stalemate on the now single-marble hill.
    private let minKnockSpeed: CGFloat = 200
    private let rivalCount         = 3
    private let roundSeconds       = 60
    private let zoneRadius:   CGFloat = CGFloat(OpponentTuning.kothZoneRadius)
    private let zoneDriftSpeed: CGFloat = 42       // points per second the hill wanders
    private let zoneRepickDist: CGFloat = 14       // re-aim when this close to its target
    private let topReserve: CGFloat = Layout.topReserve  // HUD breathing room at the top

    private var roundTicks: Int { roundSeconds * 60 }

    // MARK: - Model

    private struct Racer: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var vel: CGVector = .zero
        let colorIndex: Int
        let isPlayer: Bool
        var holdTicks = 0
    }

    private static let palette: [Color] = [
        Color(red: 0.30, green: 0.62, blue: 1.00),   // 0 — player blue
        Color(red: 0.98, green: 0.45, blue: 0.40),   // 1 — red
        Color(red: 0.95, green: 0.78, blue: 0.30),   // 2 — gold
        Color(red: 0.55, green: 0.85, blue: 0.50),   // 3 — green
        Color(red: 0.70, green: 0.55, blue: 0.98),   // 4 — violet
    ]
    private static let playerColor = palette[0]

    // MARK: - State

    @State private var racers: [Racer] = []

    /// Coins actually paid for the finished game (shown on the result screen).
    @State private var paidCoins = 0
    /// One brain per opponent (human limits from `OpponentTuning`), by color.
    @State private var brains: [Int: OpponentBrain] = [:]
    /// Each opponent's movement state (heading, hesitation, push ramp).
    @State private var motors: [Int: KothMotor] = [:]

    /// How an opponent is currently moving: the direction it has committed
    /// to, any hesitation still to wait out, and how long it has been pushing
    /// that way (its push builds up gradually).
    private struct KothMotor {
        var heading: CGVector = .zero
        var hesitateTicks = 0
        var pushTicks = 0
    }
    /// Each opponent's skill for this round (by color), dealt in reset().
    @State private var rivalSkills: [Int: Double] = [:]
    /// The round tick at which the current holder started holding alone.
    @State private var holderSinceTick = 0
    /// Each rival's keystone look (colorIndex → skin+trail+name), dealt in reset().
    @State private var rivalLooks: [Int: RivalCosmetics.Look] = [:]
    /// Trail marks per racer (colorIndex → marks laid in place) for the trail layer.
    @State private var trails: [Int: TrailMarks] = [:]
    @State private var arena:  CGSize  = .zero
    @State private var field:  CGRect  = .zero
    @State private var zoneCenter: CGPoint = .zero
    @State private var zoneTarget: CGPoint = .zero

    @State private var holderID: UUID? = nil       // who controls the hill right now (nil = open/contested)
    @State private var contested = false

    @State private var started   = false
    @State private var isOver     = false
    @State private var playerWon  = false
    @State private var localTick  = 0
    @State private var roundTick  = 0
    @State private var awarded    = false

    // Map cycling (S25)
    @State private var mapIndex   = 0
    @State private var showMapName = false

    // MARK: - Computed

    private var currentPillars: [PillarFrac] {
        KOTHMaps.maps[mapIndex % KOTHMaps.maps.count].pillars
    }

    private var secondsLeft: Int { max(0, Int(ceil(Double(roundTicks - roundTick) / 60.0))) }

    private var playerHoldTicks: Int { racers.first(where: { $0.isPlayer })?.holdTicks ?? 0 }
    private var bestRivalHoldTicks: Int {
        racers.filter { !$0.isPlayer }.map(\.holdTicks).max() ?? 0
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.07), Color(white: 0.03)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Color.clear
                    pitch
                    PillarsLayer(field: field, pillars: currentPillars)
                        .equatable()
                        .allowsHitTesting(false)
                    zoneView
                    trailsLayer.allowsHitTesting(false)
                    // Before the round: a pulsing ring marks your marble.
                    if !started && !isOver, let me = racers.first(where: { $0.isPlayer }) {
                        StartSpotRing(color: gameState.primaryColor).position(me.pos)
                    }
                    ForEach(racers) { r in
                        marble(r)
                            .overlay(alignment: .top) {
                                RivalNameTag(label: r.isPlayer ? "YOU" : (rivalLooks[r.colorIndex]?.name ?? "Rival"),
                                             color: r.isPlayer ? gameState.primaryColor : Self.palette[r.colorIndex % Self.palette.count],
                                             isPlayer: r.isPlayer,
                                             isLeader: isLeader(r),
                                             level: r.isPlayer ? gameState.highestUnlocked : nil)
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
                .onTapGesture { beginRound() }
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

    private var mapNameLabel: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: Layout.mapNameTopInset)
            Text(KOTHMaps.maps[mapIndex % KOTHMaps.maps.count].name)
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

    private var pitch: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.09)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.22), lineWidth: 1.5))
            .frame(width: field.width, height: field.height)
            .position(x: field.midX, y: field.midY)
    }

    private var zoneView: some View {
        let color = holderColor
        return ZStack {
            Circle()
                .fill(color.opacity(contested ? 0.16 : 0.22))
                .overlay(Circle().stroke(color.opacity(0.9), lineWidth: contested ? 2 : 4))
                .overlay(
                    Circle().stroke(color.opacity(0.35), lineWidth: 1)
                        .scaleEffect(1.18)
                )
            Image(systemName: "flag.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color.opacity(0.85))
        }
        .frame(width: zoneRadius * 2, height: zoneRadius * 2)
        .position(zoneCenter)
        .allowsHitTesting(false)
    }

    /// Colour of the hill: the holder's colour, white if contested, grey if open.
    private var holderColor: Color {
        if contested { return Color(white: 0.85) }
        guard let id = holderID, let r = racers.first(where: { $0.id == id }) else {
            return Color(white: 0.45)
        }
        return Self.palette[r.colorIndex % Self.palette.count]
    }

    /// The TrailColor a racer renders with — own for the player, dealt for rivals.
    private func trailFor(_ r: Racer) -> TrailColor {
        r.isPlayer ? gameState.equippedTrail : (rivalLooks[r.colorIndex]?.trail ?? .none)
    }

    /// Keystone: every racer's equipped trail, visible to all (player's own,
    /// each rival's the one dealt in reset()).
    private var trailsLayer: some View {
        Canvas { ctx, _ in
            drawTrails(ctx, racers.map { (trails[$0.colorIndex] ?? TrailMarks(), trailFor($0)) })
        }
    }

    /// The current hill leader (most accumulated hold time) — wears the crown.
    private func isLeader(_ r: Racer) -> Bool {
        let top = racers.map(\.holdTicks).max() ?? 0
        return top > 0 && r.holdTicks == top
    }

    private func marble(_ r: Racer) -> some View {
        // Canonical ball renderer — identical to home/shop/climb; tag IDs who.
        let skin = r.isPlayer ? gameState.activeSkin : (rivalLooks[r.colorIndex]?.skin ?? .red)
        return BallSkinView(skin: skin, diameter: marbleRadius * 2)
            .frame(width: marbleRadius * 2, height: marbleRadius * 2)
            .shadow(color: .black.opacity(0.5), radius: 5, x: 1, y: 3)
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
                VStack(spacing: 3) {
                    Text(timeString)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(secondsLeft <= 10 ? Color(red: 0.98, green: 0.45, blue: 0.40) : .white)
                        .monospacedDigit()
                    controlPill
                }
                Spacer()
                Color.clear.frame(width: 38, height: 38)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            holdBar
                .padding(.horizontal, 22)
                .padding(.top, 2)
            Spacer()
        }
    }

    private var controlPill: some View {
        let label: String
        let color: Color
        if contested {
            label = "CONTESTED"; color = Color(white: 0.85)
        } else if holderID == racers.first(where: { $0.isPlayer })?.id {
            label = "YOU HOLD"; color = Self.playerColor
        } else if holderID != nil {
            label = "RIVAL HOLDS"; color = Color(red: 0.98, green: 0.45, blue: 0.40)
        } else {
            label = "OPEN"; color = Color(white: 0.5)
        }
        return Text(label)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private var holdBar: some View {
        HStack(spacing: 10) {
            holdStat(title: "YOU", ticks: playerHoldTicks, color: Self.playerColor)
            holdStat(title: "TOP RIVAL", ticks: bestRivalHoldTicks,
                     color: Color(red: 0.98, green: 0.45, blue: 0.40))
        }
    }

    private func holdStat(title: String, ticks: Int, color: Color) -> some View {
        return HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color(white: 0.55))
            Text(Self.holdText(ticks))
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.12)))
    }

    /// Time held, to one decimal place: "4.3 s".
    private static func holdText(_ ticks: Int) -> String {
        String(format: "%.1f s", Double(ticks) / 60.0)
    }

    private var timeString: String {
        String(format: "%d:%02d", secondsLeft / 60, secondsLeft % 60)
    }

    /// Start the round (a tap on the arena or on the start panel).
    private func beginRound() {
        guard !started && !isOver else { return }
        started = true
        gameState.markModePlayed("koth")
        AnalyticsClient.shared.track(
            "koth_round_started",
            properties: ["map_name": .string(KOTHMaps.maps[mapIndex % KOTHMaps.maps.count].name)]
        )
    }

    private var startPrompt: some View {
        CompetitiveStartPanel(title: "King of the Hill",
                              icon: "flag.checkered",
                              tint: .white,
                              bullets: ["Tilt to roll",
                                        "Hold the glowing zone alone",
                                        "Most time on the hill in 60 seconds wins"],
                              difficulty: $gameState.minigameDifficulty,
                              onStart: beginRound)
    }

    private var gameOverOverlay: some View {
        let banked = paidCoins
        let title = playerWon ? "You Win!" : "You Lose"
        let titleColor: Color = playerWon ? Color(red: 0.50, green: 0.88, blue: 0.55)
                                          : Color(red: 0.98, green: 0.45, blue: 0.40)
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(titleColor)
                    Text("held \(Self.holdText(playerHoldTicks)) · best rival \(Self.holdText(bestRivalHoldTicks))")
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
                        mapIndex = (mapIndex + 1) % KOTHMaps.maps.count
                        reset()
                    } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Self.playerColor))
                    }
                    ResultShareButton(result: ShareableResult(
                        mode: "King of the Hill",
                        headline: Self.holdText(playerHoldTicks),
                        subtitle: playerWon ? "Held the crown 👑" : "Held the hill",
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
        // S2-T2: match ended — drain this match's trophies into one coalesced
        // banner at the result screen (design.md §6).  Overlay-appearance
        // trigger, never during play.
        .onAppear { gameState.endTrophyRun() }
    }

    // MARK: - Lifecycle

    private func layout(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        arena = size
        let side: CGFloat = 12, bottom: CGFloat = 28
        field = CGRect(x: side, y: topReserve,
                       width: size.width - side * 2,
                       height: size.height - topReserve - bottom)
    }

    private func reset() {
        guard field.width > 0 else { return }
        // S2-T2: a fresh match — arm the toast queue so any trophy earned
        // this match is held + coalesced, surfaced only at the game-over
        // overlay (design.md §6 "never mid-run").
        gameState.beginTrophyRun()
        started = false
        isOver = false
        playerWon = false
        awarded = false
        roundTick = 0
        holderID = nil
        holderSinceTick = 0
        contested = false
        zoneCenter = CGPoint(x: field.midX, y: field.midY)
        zoneTarget = randomZonePoint()

        // Fair start: all four marbles on one circle around the first zone
        // (the field center), evenly spaced, the player at the bottom — so
        // the player is exactly as far from the zone as every opponent.
        brains = [:]
        motors = [:]
        let startR = min(field.width, field.height) * CGFloat(OpponentTuning.kothStartRing)
        let total = Double(rivalCount + 1)
        var fresh: [Racer] = [Racer(pos: clampToField(CGPoint(x: field.midX, y: field.midY + startR)),
                                    colorIndex: 0, isPlayer: true)]
        for i in 0..<rivalCount {
            let angle = Double.pi / 2 + (Double(i + 1) / total) * 2 * Double.pi
            let p = CGPoint(x: field.midX + CGFloat(cos(angle)) * startR,
                            y: field.midY + CGFloat(sin(angle)) * startR)
            fresh.append(Racer(pos: clampToField(p),
                               colorIndex: (i % (Self.palette.count - 1)) + 1,
                               isPlayer: false))
        }
        let rivals = fresh.filter { !$0.isPlayer }
        rivalLooks = Dictionary(uniqueKeysWithValues:
            zip(rivals.map(\.colorIndex), RivalCosmetics.deal(rivals.count)))
        // Each opponent draws its own skill for the round: one clumsy, one
        // average, one sharp.  (The brains are built on the first tick, so a
        // difficulty picked on the start screen is the one that is used.)
        rivalSkills = Dictionary(uniqueKeysWithValues:
            zip(rivals.map(\.colorIndex), OpponentTuning.dealSkills(rivals.count)))
        racers = fresh
        trails.removeAll()
        showMapName = true
    }

    private func endRun() {
        guard !isOver else { return }
        isOver = true
        playerWon = playerHoldTicks >= bestRivalHoldTicks && playerHoldTicks > 0
        if !awarded {
            awarded = true
            let holdSec = playerHoldTicks / 60
            gameState.recordCompetitiveScore("koth", holdSec)   // leaderboard best (hold seconds)
            // Difficulty scales the payout + records the attempt/win for tracking.
            let banked = gameState.recordMinigameResult(
                modeID: "koth", difficulty: gameState.minigameDifficulty,
                won: playerWon, score: holdSec,
                placement: 1 + racers.filter { !$0.isPlayer && $0.holdTicks > playerHoldTicks }.count,
                bestRivalScore: bestRivalHoldTicks / 60,
                durationSeconds: roundTick / 60)
            paidCoins = banked   // what the result screen shows
            AnalyticsClient.shared.track(
                "koth_round_over",
                properties: ["won": .bool(playerWon),
                             "difficulty": .string(gameState.minigameDifficulty.rawValue),
                             "hold_sec": .int(holdSec),
                             "coins": .int(banked),
                             "map_name": .string(KOTHMaps.maps[mapIndex % KOTHMaps.maps.count].name)]
            )
            if playerWon {
                AnalyticsClient.shared.track("ticket_earned",
                                             properties: ["source": .string("koth")])
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
        roundTick += 1
        let dt: CGFloat = 1.0 / 60.0

        driftZone(dt)

        // Steering + integration.
        for i in racers.indices {
            if racers[i].isPlayer {
                racers[i].vel.dx += CGFloat(motion.gravity.x) * playerAccel * dt
                racers[i].vel.dy += CGFloat(motion.gravity.y) * playerAccel * dt
            } else {
                let s = opponentSteer(racers[i])
                racers[i].vel.dx += s.dx * dt
                racers[i].vel.dy += s.dy * dt
            }
            racers[i].vel.dx *= friction
            racers[i].vel.dy *= friction
            let sp = hypot(racers[i].vel.dx, racers[i].vel.dy)
            let cap = racers[i].isPlayer ? maxSpeed : opponentTopSpeed(racers[i])
            if sp > cap { let k = cap / sp; racers[i].vel.dx *= k; racers[i].vel.dy *= k }
            racers[i].pos.x += racers[i].vel.dx * dt
            racers[i].pos.y += racers[i].vel.dy * dt
            bounceWalls(&racers[i])
        }

        resolveCollisions()
        resolvePillarCollisions()
        scoreHill()

        for r in racers { recordTrail(&trails, r.colorIndex, r.pos) }

        if roundTick >= roundTicks { endRun() }
    }

    /// An opponent's top speed: lower for a low push share, so a clumsy
    /// opponent is visibly slower than a sharp one.
    private func opponentTopSpeed(_ r: Racer) -> CGFloat {
        let effort = brains[r.colorIndex]?.effort ?? 0.5
        let floor = CGFloat(OpponentTuning.kothTopSpeedAtZeroEffort)
        return maxSpeed * min(1, floor + (1 - floor) * effort)
    }

    /// Opponent steering.  Only some opponents go for the zone at a time
    /// (`kothContenders` per difficulty, taking turns every
    /// `kothRotateSeconds`).  The others do not idle: they stay right beside
    /// the zone, and once one marble has held it alone for
    /// `kothPressAfterSeconds` they go and bump the holder out.  Human limits
    /// (`OpponentTuning`): it heads for where its goal WAS one reaction delay
    /// ago, with a held aiming error, at its push share; and during a
    /// mistake a contender overshoots — it rolls on past the zone.
    private func opponentSteer(_ r: Racer) -> CGVector {
        var brain = brains[r.colorIndex]
            ?? OpponentBrain(difficulty: gameState.minigameDifficulty,
                             skill: rivalSkills[r.colorIndex] ?? 0.5)
        brain.advance()

        // Whose turn is it?  Opponent colors are 1…rivalCount.
        let slot = max(0, r.colorIndex - 1)
        let turn = roundTick / max(1, Int(OpponentTuning.kothRotateSeconds * 60))
        let contesting = (slot + turn) % max(1, rivalCount) < brain.limits.kothContenders

        var goal = zoneCenter
        if contesting {
            let speed = hypot(r.vel.dx, r.vel.dy)
            if brain.isMistaking && speed > 1 {
                let over = CGFloat(OpponentTuning.kothOvershootDistance)
                goal = CGPoint(x: zoneCenter.x + r.vel.dx / speed * over,
                               y: zoneCenter.y + r.vel.dy / speed * over)
            }
        } else {
            // Not its turn.  Has someone else been sitting in the zone alone
            // for long enough?  Then go and bump them out.
            let pressTicks = Int(OpponentTuning.kothPressAfterSeconds(gameState.minigameDifficulty) * 60)
            if let holder = racers.first(where: { $0.id == holderID }),
               holder.id != r.id, !brain.isMistaking,
               roundTick - holderSinceTick >= pressTicks {
                goal = holder.pos
            } else {
                // Otherwise wait right beside the zone, on its own side.
                let wait = CGFloat(OpponentTuning.kothWaitDistance)
                var away = unit(dx: r.pos.x - zoneCenter.x, dy: r.pos.y - zoneCenter.y, scale: 1)
                if away.dx == 0 && away.dy == 0 { away = CGVector(dx: 0, dy: -1) }
                goal = clampToField(CGPoint(x: zoneCenter.x + away.dx * wait,
                                            y: zoneCenter.y + away.dy * wait))
            }
        }

        let seen = brain.perceive(goal)
        brains[r.colorIndex] = brain
        let raw = brain.push(from: r.pos, toward: seen, fullPush: aiAccelBase)
        return humanMotion(r, raw: raw, goal: seen, skill: brain.skill)
    }

    /// Turns an opponent's ideal push into a clumsy human one
    /// (`OpponentTuning.kothMotion`):
    ///   • it uses only part of its push, and the push builds up over a
    ///     moment after it picks a direction — no instant full-power starts;
    ///   • when the way it wants to go swings sharply, it hesitates first,
    ///     drifting with no push, then sets off the new way;
    ///   • it never brakes: it stops pushing and coasts, and it misjudges how
    ///     far it will coast, so it lets go late and rolls past its target.
    private func humanMotion(_ r: Racer, raw: CGVector, goal: CGPoint, skill: Double) -> CGVector {
        let m = OpponentTuning.kothMotion(for: gameState.minigameDifficulty, skill: skill)
        var motor = motors[r.colorIndex] ?? KothMotor()
        defer { motors[r.colorIndex] = motor }

        let mag = hypot(raw.dx, raw.dy)
        guard mag > 0 else {
            motor.pushTicks = 0
            return .zero
        }
        let want = CGVector(dx: raw.dx / mag, dy: raw.dy / mag)

        // Hesitation before a sharp turn: drift, then commit to the new way.
        if motor.hesitateTicks > 0 {
            motor.hesitateTicks -= 1
            if motor.hesitateTicks == 0 {
                motor.heading = want
                motor.pushTicks = 0
            }
            return .zero
        }
        if motor.heading == .zero {
            motor.heading = want
            motor.pushTicks = 0
        } else {
            let cosTurn = want.dx * motor.heading.dx + want.dy * motor.heading.dy
            let limit = CGFloat(cos(OpponentTuning.kothTurnAngleDegrees * Double.pi / 180))
            if cosTurn < limit {
                motor.hesitateTicks = max(1, Int((m.hesitationSeconds * 60).rounded()))
                return .zero
            }
            motor.heading = want          // small corrections follow at once
        }

        // Late letting-go: coast once inside its (underestimated) stopping
        // distance while rolling toward the target.  Coasting distance with
        // per-tick friction f is speed × f / (1 − f) / 60.
        let toGoal = CGVector(dx: goal.x - r.pos.x, dy: goal.y - r.pos.y)
        let dist = hypot(toGoal.dx, toGoal.dy)
        let speed = hypot(r.vel.dx, r.vel.dy)
        let closing = dist > 0 ? (r.vel.dx * toGoal.dx + r.vel.dy * toGoal.dy) / dist : 0
        if closing > 0 {
            let coast = speed * friction / max(0.0001, 1 - friction) / 60
            if dist < coast * CGFloat(m.stopJudge) {
                motor.pushTicks = 0
                return .zero
            }
        }

        // The push builds up after a new start.
        motor.pushTicks += 1
        let rampTicks = max(1, m.rampSeconds * 60)
        let ramp = CGFloat(min(1, Double(motor.pushTicks) / rampTicks))
        let scale = CGFloat(m.pushScale) * ramp
        return CGVector(dx: want.dx * mag * scale, dy: want.dy * mag * scale)
    }

    /// The hill wanders toward a waypoint, picking a fresh one when it arrives.
    private func driftZone(_ dt: CGFloat) {
        let dx = zoneTarget.x - zoneCenter.x
        let dy = zoneTarget.y - zoneCenter.y
        let d = hypot(dx, dy)
        if d < zoneRepickDist {
            zoneTarget = randomZonePoint()
        } else {
            let step = min(d, zoneDriftSpeed * dt)
            zoneCenter.x += dx / d * step
            zoneCenter.y += dy / d * step
        }
    }

    private func randomZonePoint() -> CGPoint {
        let inset = zoneRadius + 10
        let loX = field.minX + inset, hiX = field.maxX - inset
        let loY = field.minY + inset, hiY = field.maxY - inset
        let x = hiX > loX ? CGFloat.random(in: loX...hiX) : field.midX
        let y = hiY > loY ? CGFloat.random(in: loY...hiY) : field.midY
        return CGPoint(x: x, y: y)
    }

    /// Award a tick of hold-time only if exactly one marble is in the zone.
    private func scoreHill() {
        var insideIdx: [Int] = []
        for i in racers.indices {
            let d = hypot(racers[i].pos.x - zoneCenter.x, racers[i].pos.y - zoneCenter.y)
            if d <= zoneRadius { insideIdx.append(i) }
        }
        if insideIdx.count == 1 {
            racers[insideIdx[0]].holdTicks += 1
            if holderID != racers[insideIdx[0]].id { holderSinceTick = roundTick }
            holderID = racers[insideIdx[0]].id
            contested = false
        } else {
            holderID = nil
            contested = insideIdx.count > 1
        }
    }

    private func bounceWalls(_ r: inout Racer) {
        let rad = marbleRadius
        if r.pos.x < field.minX + rad { r.pos.x = field.minX + rad; r.vel.dx = -r.vel.dx * wallBounce }
        else if r.pos.x > field.maxX - rad { r.pos.x = field.maxX - rad; r.vel.dx = -r.vel.dx * wallBounce }
        if r.pos.y < field.minY + rad { r.pos.y = field.minY + rad; r.vel.dy = -r.vel.dy * wallBounce }
        else if r.pos.y > field.maxY - rad { r.pos.y = field.maxY - rad; r.vel.dy = -r.vel.dy * wallBounce }
    }

    private func resolveCollisions() {
        guard racers.count >= 2 else { return }
        let minDist = marbleRadius * 2
        for i in 0..<racers.count {
            for j in (i + 1)..<racers.count {
                let dx = racers[j].pos.x - racers[i].pos.x
                let dy = racers[j].pos.y - racers[i].pos.y
                let dist = hypot(dx, dy)
                guard dist > 0, dist < minDist else { continue }
                let nx = dx / dist, ny = dy / dist
                // Separate the overlap so the marbles no longer intersect.
                let overlap = (minDist - dist) / 2
                racers[i].pos.x -= nx * overlap
                racers[i].pos.y -= ny * overlap
                racers[j].pos.x += nx * overlap
                racers[j].pos.y += ny * overlap

                // Forceful knockback.  `relVel` < 0 means the marbles are closing.
                // We force them to fly apart at `knockbackGain ×` the impact speed,
                // but never slower than `minKnockSpeed` — so a fast hit launches the
                // other marble hard, and two marbles jammed on the hill (impact ≈ 0)
                // still get popped apart instead of stalemating.
                let relVel = (racers[j].vel.dx - racers[i].vel.dx) * nx
                           + (racers[j].vel.dy - racers[i].vel.dy) * ny
                let desiredSep = max(minKnockSpeed, -relVel * knockbackGain)
                guard relVel < desiredSep else { continue }   // already parting fast enough
                let jImp = (desiredSep - relVel) / 2
                racers[i].vel.dx -= jImp * nx
                racers[i].vel.dy -= jImp * ny
                racers[j].vel.dx += jImp * nx
                racers[j].vel.dy += jImp * ny
            }
        }
    }

    // MARK: - Pillar collision (S25)

    /// Resolve collisions between all marbles and the current map's pillar obstacles.
    /// Pillars have infinite mass — only the marble moves.
    private func resolvePillarCollisions() {
        guard field.width > 0, !currentPillars.isEmpty else { return }
        for i in racers.indices {
            for p in currentPillars {
                let cx = field.minX + p.cx * field.width
                let cy = field.minY + p.cy * field.height
                let dx = racers[i].pos.x - cx, dy = racers[i].pos.y - cy
                let dist = hypot(dx, dy)
                let minD = marbleRadius + p.r
                guard dist < minD, dist > 0 else { continue }
                let nx = dx / dist, ny = dy / dist
                racers[i].pos.x += nx * (minD - dist)
                racers[i].pos.y += ny * (minD - dist)
                let dot = racers[i].vel.dx * nx + racers[i].vel.dy * ny
                guard dot < 0 else { continue }
                let jImp = -(1 + restitution) * dot
                racers[i].vel.dx += jImp * nx
                racers[i].vel.dy += jImp * ny
            }
        }
    }

    private func clampToField(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, field.minX + marbleRadius), field.maxX - marbleRadius),
                y: min(max(p.y, field.minY + marbleRadius), field.maxY - marbleRadius))
    }

    private func unit(dx: CGFloat, dy: CGFloat, scale: CGFloat) -> CGVector {
        let m = hypot(dx, dy)
        guard m > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: dx / m * scale, dy: dy / m * scale)
    }
}

// MARK: - Pillar layer (extracted for equatable skip)

/// Circular pillar obstacles at fractional field positions (S25 engine).
/// Extracted so `.equatable()` lets SwiftUI skip this Canvas on every physics tick —
/// `field` and `pillars` only change on map load or screen-size change.
private struct PillarsLayer: View, Equatable {
    let field:   CGRect
    let pillars: [PillarFrac]

    var body: some View {
        Canvas { ctx, _ in
            guard field.width > 0 else { return }
            for p in pillars {
                let cx = field.minX + p.cx * field.width
                let cy = field.minY + p.cy * field.height
                let rect = CGRect(x: cx - p.r, y: cy - p.r, width: p.r * 2, height: p.r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.20)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(Color(white: 0.38)), lineWidth: 2)
            }
        }
    }
}

#Preview {
    NavigationStack {
        KingOfTheHillView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
