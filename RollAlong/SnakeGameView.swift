import SwiftUI

// ===========================================================================
// SnackyView — "Snacky", the snake minigame (internal mode id "snake").
//
// Snacky replaced Comet Clash in version 1.0.  It keeps Comet Clash's mode id
// ("snake") so the stored leaderboard rows, the two "snake_wins" trophies and
// the analytics game id carry over.  Comet Clash itself is held back in
// tools/comet-clash/ (not built into the app).
//
// THE GAME
//   • An open arena: no walls, holes or obstacles.  The screen edges bounce a
//     ball back gently; an edge never knocks anyone out.
//   • Every ball rolls at a steady speed; tilt steers it.
//   • Eating an orb adds one more ball behind you, identical to your own, so
//     a snake is a line of matching balls.
//   • A head that touches ANY ball in ANY chain — its own or another's — is
//     out.  Two heads meeting knocks out both.  Right after an edge bounce a
//     ball cannot hit its own chain (a bounce is always survivable), and it
//     can never hit the first balls right behind its own head.
//
// FOUR MODES (chosen on the start screen, remembered)
//   • Solo — you alone, one orb at a time.  Score = orbs eaten.  The round
//     ends when you hit your own chain.  No coins, no ticket; its own board.
//   • Easy / Normal / Hard — you against three computer snakes, several orbs
//     at once.  Last ball left wins.  Pays like the other competitive games
//     (through `recordMinigameResult`), and a win earns a ticket.
//
// Every number lives in the SNACKY block of `OpponentTuning` (GameState.swift).
// ===========================================================================

/// The four ways to play Snacky.
enum SnackyMode: String, CaseIterable, Identifiable {
    case solo, easy, normal, hard
    var id: String { rawValue }

    var title: String {
        switch self {
        case .solo:   return "Solo"
        case .easy:   return "Easy"
        case .normal: return "Normal"
        case .hard:   return "Hard"
        }
    }

    /// The competitive difficulty, or nil for Solo.
    var difficulty: MinigameDifficulty? {
        switch self {
        case .solo:   return nil
        case .easy:   return .easy
        case .normal: return .normal
        case .hard:   return .hard
        }
    }
}

/// Pure geometry for Snacky, kept apart from the view so it can be tested.
enum SnackyGeometry {

    /// The chain behind a head: `count` points spaced `spacing` apart along
    /// the path the head has travelled (`history`, oldest first, newest last,
    /// ending at the head).  Fewer points are returned while the path is still
    /// too short to hold them all.
    static func chain(history: [CGPoint], count: Int, spacing: CGFloat) -> [CGPoint] {
        guard count > 0, history.count >= 2, spacing > 0 else { return [] }
        var out: [CGPoint] = []
        out.reserveCapacity(count)
        var next = spacing                 // path distance of the next ball
        var travelled: CGFloat = 0         // path distance already walked back
        var k = history.count - 1
        while k > 0, out.count < count {
            let a = history[k], b = history[k - 1]
            let seg = hypot(a.x - b.x, a.y - b.y)
            if seg > 0 {
                while out.count < count, travelled + seg >= next {
                    let t = (next - travelled) / seg
                    out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                    next += spacing
                }
                travelled += seg
            }
            k -= 1
        }
        return out
    }

    /// Path length of `history` from its newest point backwards.
    static func pathLength(_ history: [CGPoint]) -> CGFloat {
        guard history.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for k in 1..<history.count {
            total += hypot(history[k].x - history[k - 1].x, history[k].y - history[k - 1].y)
        }
        return total
    }

    /// Reflect a heading off the arena edges if `p` has gone past one.
    /// Returns the clamped point, the new heading and whether it bounced.
    static func bounce(_ p: CGPoint, heading: CGFloat, radius r: CGFloat,
                       in size: CGSize) -> (CGPoint, CGFloat, Bool) {
        var q = p
        var dx = cos(heading), dy = sin(heading)
        var bounced = false
        if q.x < r              { q.x = r;               dx =  abs(dx); bounced = true }
        if q.x > size.width - r { q.x = size.width - r;  dx = -abs(dx); bounced = true }
        if q.y < r              { q.y = r;               dy =  abs(dy); bounced = true }
        if q.y > size.height - r { q.y = size.height - r; dy = -abs(dy); bounced = true }
        return (q, bounced ? atan2(dy, dx) : heading, bounced)
    }

    /// The signed smallest angle from `a` to `b`, in -π…π.
    static func angleDelta(from a: CGFloat, to b: CGFloat) -> CGFloat {
        var d = b - a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
}

struct SnackyView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    /// True when the player last chose Solo.  Easy / Normal / Hard is the
    /// shared `gameState.minigameDifficulty`, so the last mode is remembered.
    @AppStorage("ra_snackySolo") private var soloChosen: Bool = false
    /// The player's best Solo score (orbs eaten), on this phone.
    @AppStorage("ra_snackySoloBest") private var soloBest: Int = 0

    private var mode: SnackyMode {
        if soloChosen { return .solo }
        switch gameState.minigameDifficulty {
        case .easy:   return .easy
        case .normal: return .normal
        case .hard:   return .hard
        }
    }

    // MARK: - Tunables (all from OpponentTuning's SNACKY block)

    private var r: CGFloat           { CGFloat(OpponentTuning.snackyBallRadius) }
    private var spacing: CGFloat     { CGFloat(OpponentTuning.snackySegmentSpacing) }
    private var orbR: CGFloat        { CGFloat(OpponentTuning.snackyOrbRadius) }
    private var hitDistance: CGFloat { 2 * r * CGFloat(OpponentTuning.snackyHitShare) }
    private var rivalCount: Int      { mode == .solo ? 0 : 3 }
    private var orbTarget: Int       { mode == .solo ? OpponentTuning.snackyOrbsSolo : OpponentTuning.snackyOrbsVersus }

    // MARK: - Model

    private struct Snake: Identifiable {
        let id: Int                    // 0 = the player
        let isPlayer: Bool
        var head: CGPoint
        var heading: CGFloat           // radians
        var speed: CGFloat             // points per second
        var turnRate: CGFloat          // radians per second
        var history: [CGPoint] = []    // the path travelled, oldest first
        var segments: [CGPoint] = []   // the chain behind the head, nearest first
        var eaten = 0                  // orbs eaten = balls in the chain
        var alive = true
        var graceUntil = 0             // tick until which its own chain cannot hit it
    }

    private struct Orb: Identifiable {
        let id = UUID()
        var pos: CGPoint
    }

    private struct Poof: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var color: Color
        var age = 0
    }

    private static let palette: [Color] = [
        Color(red: 0.30, green: 0.72, blue: 1.00),   // 0 — the player
        Color(red: 1.00, green: 0.42, blue: 0.42),   // 1
        Color(red: 0.68, green: 0.50, blue: 1.00),   // 2
        Color(red: 1.00, green: 0.78, blue: 0.32),   // 3
    ]
    private static let poofLifeTicks = 26
    private static let orbColor = Color(red: 0.55, green: 1.00, blue: 0.62)

    // MARK: - State

    @State private var snakes: [Snake] = []
    @State private var orbs:   [Orb]   = []
    @State private var poofs:  [Poof]  = []
    @State private var arena:  CGSize  = .zero
    @State private var localTick = 0

    @State private var started   = false
    @State private var isOver    = false
    @State private var playerWon = false
    @State private var awarded   = false
    @State private var paidCoins = 0
    @State private var finalPlacement = 1
    @State private var newSoloBest = false

    /// One brain per opponent (human limits from `OpponentTuning`), by id.
    @State private var brains: [Int: OpponentBrain] = [:]
    /// The heading each opponent has decided to steer toward.
    @State private var wantHeading: [Int: CGFloat] = [:]
    /// Each opponent's look (ball skin and name), dealt once per round.
    @State private var rivalLooks: [Int: RivalCosmetics.Look] = [:]

    // MARK: - Computed

    private var player: Snake? { snakes.first(where: { $0.isPlayer }) }
    private var rivalsAlive: Int { snakes.filter { !$0.isPlayer && $0.alive }.count }
    private var playerOut: Bool { started && !isOver && !(player?.alive ?? true) }

    private func skin(for s: Snake) -> BallSkin {
        s.isPlayer ? gameState.activeSkin : (rivalLooks[s.id]?.skin ?? .red)
    }
    private func color(for s: Snake) -> Color {
        s.isPlayer ? gameState.primaryColor : Self.palette[s.id % Self.palette.count]
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.05), Color(white: 0.11)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Color.clear
                    orbsLayer.allowsHitTesting(false)
                    chainsLayer.allowsHitTesting(false)
                    ForEach(snakes.filter { $0.alive }) { s in
                        headView(s)
                            .overlay(alignment: .top) {
                                RivalNameTag(label: s.isPlayer ? "YOU" : (rivalLooks[s.id]?.name ?? "Rival"),
                                             color: color(for: s),
                                             isPlayer: s.isPlayer,
                                             level: s.isPlayer ? gameState.highestUnlocked : nil)
                                    .offset(y: -12).allowsHitTesting(false)
                            }
                            .position(s.head)
                    }
                    if !started && !isOver, let p = player {
                        StartSpotRing(color: gameState.primaryColor, diameter: r * 2 + 22)
                            .position(p.head)
                    }
                    poofLayer.allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onAppear { arena = geo.size; reset() }
                .onChange(of: geo.size) { _, newSize in
                    arena = newSize
                    if !started { reset() }
                }
                .onTapGesture { startIfReady() }
                .onChange(of: soloChosen) { _, _ in if !started { reset() } }
                .onChange(of: gameState.minigameDifficulty) { _, _ in if !started && !soloChosen { reset() } }
            }

            topBar
            if !started && !isOver { startPanel }
            if playerOut { spectateBar }
            if isOver { gameOverOverlay }

            // Trophy moment host — inert until the result overlay drains the queue.
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

    /// Every chain ball, drawn by one Canvas.  Each snake's ball skin is
    /// rendered once as a Canvas symbol and stamped at every chain position,
    /// so a long chain costs one draw per ball, not one live view per ball.
    /// (Animated skins show as a still picture in the chain; the head stays a
    /// live, animated ball.)
    private var chainsLayer: some View {
        let d = r * 2
        let live = snakes.filter { $0.alive }
        return Canvas { ctx, _ in
            for s in live {
                guard let symbol = ctx.resolveSymbol(id: s.id) else { continue }
                // Farthest first, so nearer balls overlap the ones behind.
                for p in s.segments.reversed() { ctx.draw(symbol, at: p) }
            }
        } symbols: {
            ForEach(live) { s in
                BallSkinView(skin: skin(for: s), diameter: d)
                    .frame(width: d, height: d)
                    .overlay(Circle().stroke(color(for: s).opacity(0.55), lineWidth: 1.2))
                    .tag(s.id)
            }
        }
    }

    private var orbsLayer: some View {
        ForEach(orbs) { orb in
            ZStack {
                Circle()
                    .fill(Self.orbColor.opacity(0.28))
                    .frame(width: orbR * 3, height: orbR * 3)
                Circle()
                    .fill(RadialGradient(colors: [.white, Self.orbColor],
                                         center: .center, startRadius: 0, endRadius: orbR))
                    .frame(width: orbR * 2, height: orbR * 2)
            }
            .position(orb.pos)
        }
    }

    private func headView(_ s: Snake) -> some View {
        let col = color(for: s)
        return BallSkinView(skin: skin(for: s), diameter: r * 2)
            .frame(width: r * 2, height: r * 2)
            .overlay(Circle().stroke(col, lineWidth: 2.2))
            .shadow(color: col.opacity(0.6), radius: 6)
    }

    private var poofLayer: some View {
        ForEach(poofs) { p in
            let f = CGFloat(p.age) / CGFloat(Self.poofLifeTicks)
            let ring = r * 2 + f * 60
            Circle()
                .stroke(p.color.opacity(Double(1 - f)), lineWidth: 3.5 * (1 - f) + 0.5)
                .frame(width: ring, height: ring)
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
                .accessibilityLabel("Home")
                Spacer()
                if mode != .solo { rivalsPip }
                // The score — orbs eaten — in the corner throughout.
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(player?.eaten ?? 0)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("ORBS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                        .tracking(1)
                    if mode == .solo && soloBest > 0 {
                        Text("best \(soloBest)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(white: 0.6))
                            .monospacedDigit()
                    }
                }
                .padding(.leading, 12)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var rivalsPip: some View {
        HStack(spacing: 4) {
            ForEach(snakes.filter { !$0.isPlayer }) { s in
                Circle()
                    .fill(s.alive ? color(for: s) : Color(white: 0.22))
                    .frame(width: 9, height: 9)
            }
        }
        .padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rivalsAlive) rivals left")
    }

    /// The start screen: the shared compact panel at the bottom (Solo · Easy
    /// · Normal · Hard), so the arena and the player's starting ball stay in
    /// view.  It stays until the player taps.
    private var startPanel: some View {
        CompetitiveStartPanel(title: "Snacky",
                              icon: GameMenuView.style(for: "snake").icon,
                              tint: Color(red: 0.55, green: 1.00, blue: 0.62),
                              bullets: mode == .solo
                                ? ["Tilt to steer", "Eat orbs to grow", "Hit any chain and you're out"]
                                : ["Tilt to steer · eat orbs to grow", "Hit any chain and you're out",
                                   "Last ball left wins"],
                              difficulty: $gameState.minigameDifficulty,
                              solo: $soloChosen,
                              onStart: startIfReady)
    }

    /// Shown once the player is out while computer snakes remain.
    private var spectateBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "eye.fill").font(.system(size: 13, weight: .bold))
                Text("You're out — the round is finishing")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .allowsHitTesting(false)
            Button { skipToResult() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "forward.end.fill").font(.system(size: 14, weight: .bold))
                    Text("Skip to result")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 22).padding(.vertical, 12)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("SnackySkipToResult")
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    private var gameOverOverlay: some View {
        let eaten = player?.eaten ?? 0
        let solo = mode == .solo
        let title = solo ? "\(eaten) orb\(eaten == 1 ? "" : "s")" : (playerWon ? "You Win!" : "Out!")
        let titleColor: Color = solo ? .white
            : (playerWon ? Color(red: 0.45, green: 0.88, blue: 0.55) : Color(red: 1.00, green: 0.45, blue: 0.45))
        let subtitle = solo
            ? (newSoloBest ? "New best!" : "Best \(soloBest)")
            : "\(eaten) orb\(eaten == 1 ? "" : "s") · \(ordinal(finalPlacement)) of 4"
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(titleColor)
                    Text(subtitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(newSoloBest && solo ? Color(red: 1.0, green: 0.82, blue: 0.30)
                                                             : Color(white: 0.65))
                }

                if !solo {
                    HStack(spacing: 12) {
                        CoinIcon(size: 44)
                        Text("+\(paidCoins)")
                            .font(.system(size: 52, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Plus \(paidCoins) coins")
                    if playerWon {
                        HStack(spacing: 6) {
                            Image(systemName: "ticket.fill")
                            Text("+1 ticket")
                        }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.30))
                    }
                }

                VStack(spacing: 12) {
                    Button { reset() } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 1.0, green: 0.82, blue: 0.30)))
                    }
                    ResultShareButton(result: ShareableResult(
                        mode: "Snacky",
                        headline: "\(eaten) orb\(eaten == 1 ? "" : "s")",
                        subtitle: solo ? "Solo" : (playerWon ? "Last ball standing" : "\(ordinal(finalPlacement)) of 4"),
                        skin: gameState.activeSkin,
                        trail: gameState.equippedTrail,
                        won: solo ? newSoloBest : playerWon))
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
        // Round over — show any trophies earned in it.
        .onAppear { gameState.endTrophyRun() }
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    // MARK: - Lifecycle

    private func reset() {
        guard arena.width > 0, arena.height > 0 else { return }
        gameState.beginTrophyRun()
        localTick = 0
        started = false
        isOver = false
        playerWon = false
        awarded = false
        paidCoins = 0
        finalPlacement = 1
        newSoloBest = false
        poofs = []
        wantHeading = [:]

        let w = arena.width, h = arena.height
        let playerSpeed = CGFloat(OpponentTuning.snackyPlayerSpeed)
        let playerTurn = CGFloat(OpponentTuning.snackyPlayerTurnDegrees) * .pi / 180
        // The player starts in the middle, heading up.  Opponents start near
        // the top corners heading down their own side, and at the bottom
        // heading right — none toward the player or toward each other.
        var fresh: [Snake] = [
            Snake(id: 0, isPlayer: true,
                  head: CGPoint(x: w * 0.5, y: h * (mode == .solo ? 0.5 : 0.48)),
                  heading: -.pi / 2, speed: playerSpeed, turnRate: playerTurn)
        ]
        if rivalCount > 0 {
            let difficulty = mode.difficulty ?? .normal
            let skills = OpponentTuning.dealSkills(rivalCount)
            let starts: [(CGPoint, CGFloat)] = [
                (CGPoint(x: w * 0.18, y: h * 0.20), .pi * 0.5),
                (CGPoint(x: w * 0.82, y: h * 0.20), .pi * 0.5),
                (CGPoint(x: w * 0.50, y: h * 0.84), 0),
            ]
            var freshBrains: [Int: OpponentBrain] = [:]
            for n in 1...rivalCount {
                let brain = OpponentBrain(difficulty: difficulty, skill: skills[(n - 1) % max(1, skills.count)])
                freshBrains[n] = brain
                let e = Double(brain.effort)
                let speedShare = OpponentTuning.snackyOpponentSpeedFloor
                    + (1 - OpponentTuning.snackyOpponentSpeedFloor) * e
                let turnDeg = OpponentTuning.snackyTurnSlowDegrees
                    + (OpponentTuning.snackyTurnFastDegrees - OpponentTuning.snackyTurnSlowDegrees) * e
                let start = starts[(n - 1) % starts.count]
                fresh.append(Snake(id: n, isPlayer: false, head: start.0, heading: start.1,
                                   speed: playerSpeed * CGFloat(speedShare),
                                   turnRate: CGFloat(turnDeg) * .pi / 180))
            }
            brains = freshBrains
            rivalLooks = Dictionary(uniqueKeysWithValues:
                zip(Array(1...rivalCount), RivalCosmetics.deal(rivalCount)))
        } else {
            brains = [:]
            rivalLooks = [:]
        }
        for i in fresh.indices { fresh[i].history = [fresh[i].head] }
        snakes = fresh

        orbs = []
        topUpOrbs()
    }

    private func startIfReady() {
        guard !started, !isOver, arena.width > 1 else { return }
        started = true
        gameState.markModePlayed("snake")
        AnalyticsClient.shared.track("snacky_round_started",
                                     properties: ["mode": .string(mode.rawValue)])
    }

    // MARK: - Simulation

    private func tick() {
        guard started, !isOver, arena.width > 1, arena.height > 1 else { return }
        // Once the player is out, the rest of the round plays faster.
        let steps = playerOut ? max(1, OpponentTuning.snackySpectateSpeed) : 1
        for _ in 0..<steps where !isOver { simulateStep() }
        agePoofs()
    }

    private func simulateStep() {
        localTick &+= 1
        let dt: CGFloat = 1.0 / 60.0

        // 1) Steer and move every living ball.
        for i in snakes.indices where snakes[i].alive {
            if snakes[i].isPlayer {
                steerPlayer(i, dt: dt)
            } else {
                steerOpponent(i, dt: dt)
            }
            var s = snakes[i]
            let next = CGPoint(x: s.head.x + cos(s.heading) * s.speed * dt,
                               y: s.head.y + sin(s.heading) * s.speed * dt)
            let (clamped, heading, bounced) = SnackyGeometry.bounce(next, heading: s.heading,
                                                                   radius: r, in: arena)
            s.head = clamped
            s.heading = heading
            if bounced {
                s.graceUntil = localTick + Int(OpponentTuning.snackyEdgeGraceSeconds * 60)
            }
            s.history.append(s.head)
            trimHistory(&s)
            s.segments = SnackyGeometry.chain(history: s.history,
                                              count: min(s.eaten, OpponentTuning.snackyMaxSegments),
                                              spacing: spacing)
            snakes[i] = s
        }

        // 2) Orbs, then knockouts, then the result.
        eatOrbs()
        resolveCollisions()
        evaluateEnd()
    }

    /// Keep only as much path as the chain needs (plus a little).
    private func trimHistory(_ s: inout Snake) {
        let need = CGFloat(min(s.eaten, OpponentTuning.snackyMaxSegments) + 2) * spacing
        guard s.history.count > 8 else { return }
        var total: CGFloat = 0
        var k = s.history.count - 1
        while k > 0 {
            total += hypot(s.history[k].x - s.history[k - 1].x, s.history[k].y - s.history[k - 1].y)
            if total > need { break }
            k -= 1
        }
        if k > 1 { s.history.removeFirst(k - 1) }
    }

    /// Tilt steers: the head turns toward the tilt direction at a set rate;
    /// speed stays the same.
    private func steerPlayer(_ i: Int, dt: CGFloat) {
        let gx = CGFloat(motion.gravity.x), gy = CGFloat(motion.gravity.y)
        guard hypot(gx, gy) > CGFloat(OpponentTuning.snackyTiltDeadZone) else { return }
        turn(i, toward: atan2(gy, gx), dt: dt)
    }

    private func turn(_ i: Int, toward target: CGFloat, dt: CGFloat) {
        let delta = SnackyGeometry.angleDelta(from: snakes[i].heading, to: target)
        let maxTurn = snakes[i].turnRate * dt
        snakes[i].heading += max(-maxTurn, min(maxTurn, delta))
    }

    // MARK: - Opponents

    /// Avoid chains and edges first, chase orbs second.  Each opponent looks
    /// ahead along a fan of headings, keeps the clearest, and prefers the one
    /// that points at the orb it last saw.  Reaction delay, mistakes and turn
    /// rate come from its own brain (difficulty and skill).
    private func steerOpponent(_ i: Int, dt: CGFloat) {
        let id = snakes[i].id
        guard var brain = brains[id] else { return }
        brain.advance()
        let graceTicks = Int(OpponentTuning.snackyGraceSeconds * 60)
        let mistaking = brain.isMistaking && localTick > graceTicks

        // The orb it is going for, as it was one reaction delay ago.
        let head = snakes[i].head
        let nearest = orbs.min { a, b in
            hypot(a.pos.x - head.x, a.pos.y - head.y) < hypot(b.pos.x - head.x, b.pos.y - head.y)
        }
        let seenOrb = nearest.map { brain.perceive($0.pos) }

        let replanEvery = max(2, Int(Double(brain.delayTicks) * OpponentTuning.snackyReplanDelayShare))
        if wantHeading[id] == nil || localTick % replanEvery == id % replanEvery {
            let e = Double(brain.effort)
            let lookSeconds = OpponentTuning.snackyLookAheadSlowSeconds
                + (OpponentTuning.snackyLookAheadFastSeconds - OpponentTuning.snackyLookAheadSlowSeconds) * e
            var look = max(CGFloat(OpponentTuning.snackyLookAheadMin), snakes[i].speed * CGFloat(lookSeconds))
            if mistaking { look *= CGFloat(OpponentTuning.snackyMistakeLookShare) }
            wantHeading[id] = planHeading(i, look: look, orb: seenOrb) + brain.aimError * 0.4
        }
        brains[id] = brain
        if let want = wantHeading[id] { turn(i, toward: want, dt: dt) }
    }

    private func planHeading(_ i: Int, look: CGFloat, orb: CGPoint?) -> CGFloat {
        let s = snakes[i]
        let spread = OpponentTuning.snackyCandidateSpreadDegrees * .pi / 180
        let steps = max(2, OpponentTuning.snackyCandidateCount - 1)
        let obstacles = obstaclePoints(excludingNearestOf: i)
        var best = s.heading
        var bestScore = -CGFloat.greatestFiniteMagnitude
        for k in 0...steps {
            let offset = -spread + 2 * spread * Double(k) / Double(steps)
            let h = s.heading + CGFloat(offset)
            let free = freeDistance(from: s.head, heading: h, look: look, obstacles: obstacles)
            var score = 2.0 * free / max(1, look)
            if let orb {
                let toOrb = atan2(orb.y - s.head.y, orb.x - s.head.x)
                let align = (cos(SnackyGeometry.angleDelta(from: h, to: toOrb)) + 1) / 2   // 0…1
                score += 0.6 * align
            }
            score -= 0.25 * CGFloat(abs(offset) / .pi)          // prefer gentle turns
            if score > bestScore { bestScore = score; best = h }
        }
        return best
    }

    /// Every chain ball and every other head an opponent must avoid.  Its own
    /// first few balls are left out (it cannot hit them).
    private func obstaclePoints(excludingNearestOf i: Int) -> [CGPoint] {
        var pts: [CGPoint] = []
        let skipOwn = OpponentTuning.snackyOwnSkipSegments + 1
        for (j, other) in snakes.enumerated() where other.alive {
            if j == i {
                if other.segments.count > skipOwn { pts.append(contentsOf: other.segments[skipOwn...]) }
            } else {
                pts.append(other.head)
                pts.append(contentsOf: other.segments)
            }
        }
        return pts
    }

    /// How far a ball could roll along `heading` before it would hit a ball
    /// or come too close to an edge (up to `look`).
    private func freeDistance(from p: CGPoint, heading: CGFloat, look: CGFloat,
                              obstacles: [CGPoint]) -> CGFloat {
        let step = max(4, r)
        let clearSq = (2 * r + 4) * (2 * r + 4)
        let edge = r + CGFloat(OpponentTuning.snackyEdgeAvoidMargin)
        let dx = cos(heading), dy = sin(heading)
        var d = step
        while d <= look {
            let q = CGPoint(x: p.x + dx * d, y: p.y + dy * d)
            if q.x < edge || q.x > arena.width - edge || q.y < edge || q.y > arena.height - edge {
                return d - step
            }
            for o in obstacles {
                let ox = o.x - q.x, oy = o.y - q.y
                if ox * ox + oy * oy < clearSq { return d - step }
            }
            d += step
        }
        return look
    }

    // MARK: - Orbs

    private func topUpOrbs() {
        while orbs.count < orbTarget {
            guard let p = openSpot() else { break }
            orbs.append(Orb(pos: p))
        }
    }

    /// A random spot clear of every ball and orb, away from the edges.
    private func openSpot() -> CGPoint? {
        let margin = r * 2.5
        // The spot's range starts 60 pt below the top margin, so the arena
        // must be taller than that or the range below would be invalid.
        guard arena.width > margin * 2, arena.height > margin * 2 + 60 else { return nil }
        let clear = r * 3
        for _ in 0..<40 {
            let p = CGPoint(x: CGFloat.random(in: margin...(arena.width - margin)),
                            y: CGFloat.random(in: (margin + 60)...(arena.height - margin)))
            var ok = true
            for s in snakes where s.alive {
                if hypot(p.x - s.head.x, p.y - s.head.y) < clear * 2 { ok = false; break }
                for q in s.segments where hypot(p.x - q.x, p.y - q.y) < clear { ok = false; break }
                if !ok { break }
            }
            if ok { for o in orbs where hypot(p.x - o.pos.x, p.y - o.pos.y) < clear * 2 { ok = false; break } }
            if ok { return p }
        }
        return nil
    }

    private func eatOrbs() {
        let reach = r + orbR
        var ate = false
        for i in snakes.indices where snakes[i].alive {
            let h = snakes[i].head
            if let k = orbs.firstIndex(where: { hypot($0.pos.x - h.x, $0.pos.y - h.y) < reach }) {
                orbs.remove(at: k)
                snakes[i].eaten += 1
                ate = true
                if snakes[i].isPlayer && gameState.hapticsEnabled { Haptics.light() }
            }
        }
        if ate { topUpOrbs() }
    }

    // MARK: - Knockouts

    private func resolveCollisions() {
        let hitSq = hitDistance * hitDistance
        let skipOwn = OpponentTuning.snackyOwnSkipSegments
        var out = Set<Int>()
        for a in snakes.indices where snakes[a].alive {
            let h = snakes[a].head
            for b in snakes.indices where snakes[b].alive {
                if a == b {
                    // Its own chain: never the first few balls, and not at all
                    // just after an edge bounce.
                    if localTick < snakes[a].graceUntil { continue }
                    let segs = snakes[a].segments
                    guard segs.count > skipOwn else { continue }
                    for q in segs[skipOwn...] {
                        let dx = q.x - h.x, dy = q.y - h.y
                        if dx * dx + dy * dy < hitSq { out.insert(a); break }
                    }
                } else {
                    // Another head: both are out.
                    let o = snakes[b].head
                    if (o.x - h.x) * (o.x - h.x) + (o.y - h.y) * (o.y - h.y) < hitSq {
                        out.insert(a); out.insert(b)
                    }
                    for q in snakes[b].segments {
                        let dx = q.x - h.x, dy = q.y - h.y
                        if dx * dx + dy * dy < hitSq { out.insert(a); break }
                    }
                }
                if out.contains(a) { break }
            }
        }
        guard !out.isEmpty else { return }

        let playerDiesNow = out.contains(where: { snakes[$0].isPlayer })
        for k in out {
            snakes[k].alive = false
            poofs.append(Poof(pos: snakes[k].head, color: color(for: snakes[k])))
            snakes[k].segments = []
        }
        if playerDiesNow {
            // Placement: one place behind every opponent still in.  Going out
            // together with the last opponent is not a win: 2nd.
            finalPlacement = max(2, 1 + rivalsAlive)
            if mode == .solo { finalPlacement = 1 }
            if gameState.hapticsEnabled { Haptics.warning() }
        }
    }

    private func evaluateEnd() {
        guard !isOver else { return }
        let playerAlive = player?.alive ?? false
        if mode == .solo {
            if !playerAlive { endRun(won: false) }
            return
        }
        if playerAlive && rivalsAlive == 0 {
            finalPlacement = 1
            endRun(won: true)
        } else if !playerAlive && rivalsAlive <= 1 {
            endRun(won: false)
        }
    }

    /// "Skip to result": play the rest of the round at once, up to a time
    /// limit; if several opponents are still going after it, the round ends
    /// there (the player's place is already decided).
    private func skipToResult() {
        guard playerOut else { return }
        var budget = Int(OpponentTuning.snackySkipMaxSeconds * 60)
        while budget > 0, !isOver {
            simulateStep()
            budget -= 1
        }
        if !isOver { endRun(won: false) }
    }

    private func endRun(won: Bool) {
        guard !isOver else { return }
        isOver = true
        playerWon = won
        guard !awarded else { return }
        awarded = true
        let eaten = player?.eaten ?? 0

        if mode == .solo {
            // Solo pays nothing and earns no ticket; it keeps a best score
            // and its own board.
            if eaten > soloBest {
                soloBest = eaten
                newSoloBest = true
            }
            let best = soloBest
            if SocialClient.shared.isSignedIn, best > 0 {
                Task {
                    try? await SocialClient.shared.syncMinigameScore(
                        game: "snake", difficulty: "solo", wins: 0, best: best)
                }
            }
            AnalyticsClient.shared.track("snacky_round_over",
                                         properties: ["mode": .string("solo"),
                                                      "orbs": .int(eaten),
                                                      "new_best": .bool(newSoloBest),
                                                      "duration_s": .int(localTick / 60)])
            if gameState.hapticsEnabled { if newSoloBest { Haptics.success() } }
            return
        }

        let difficulty = mode.difficulty ?? .normal
        gameState.recordCompetitiveScore("snake", eaten)          // board best (orbs)
        let banked = gameState.recordMinigameResult(
            modeID: "snake", difficulty: difficulty,
            won: won, score: eaten,
            placement: won ? 1 : finalPlacement,
            bestRivalScore: snakes.filter { !$0.isPlayer }.map(\.eaten).max() ?? 0,
            durationSeconds: localTick / 60)
        paidCoins = banked
        AnalyticsClient.shared.track("snacky_round_over",
                                     properties: ["mode": .string(mode.rawValue),
                                                  "won": .bool(won),
                                                  "orbs": .int(eaten),
                                                  "placement": .int(won ? 1 : finalPlacement),
                                                  "coins": .int(banked)])
        if won {
            AnalyticsClient.shared.track("ticket_earned", properties: ["source": .string("snake")])
        }
        if gameState.hapticsEnabled {
            if won { Haptics.success() } else { Haptics.warning() }
        }
        gameState.maybeRequestReview(after: won)
    }

    private func agePoofs() {
        guard !poofs.isEmpty else { return }
        for k in poofs.indices { poofs[k].age += 1 }
        poofs.removeAll { $0.age > Self.poofLifeTicks }
    }
}

#Preview {
    NavigationStack {
        SnackyView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
