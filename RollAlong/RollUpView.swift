import SwiftUI

// ===========================================================================
// RollUpView — "Roll Up", a vertical jump-platformer.  The ball always falls
// under gravity; the player TILTS left/right to steer it and TAPS the screen to
// pop it up into the air.  Goal: bounce from one floating platform to the next
// and climb as high as possible.
//
// CONTROLS
//   • Tilt left/right  → horizontal acceleration (air + ground steering).
//   • Tap              → jump (when grounded), plus one recovery air-jump.
//
// ECONOMY: FREE TO PLAY.  Minigames never cost lives, so a run that ends (the
// ball falls off the bottom) spends nothing, there is no lives pill, and the
// out-of-lives gate is gone.  Solo games pay no coins
// (`CoinPayouts.rollUp`); the personal best (height + run time) is tracked.
//
// SKY: one permanent backdrop for everyone (not a cosmetic) — see RollUpSky
// at the bottom of this file.  It brightens from a pale horizon through
// sunrise and sunset to deep blue and dark space as the run climbs.
//
// COORDINATES: world space has y INCREASING UPWARD (height).  A camera that only
// ever rises maps world → screen, so climbing scrolls the world down and a fall
// eventually drops the ball off the bottom.
//
// SAFE BY CONSTRUCTION: brand-new isolated file; reuses only BallMotion /
// PhysicsClock, the coin economy, BallSkinView, CoinIcon, and
// ResultShareButton.  Reached only when HomeView routes `.mode("rollup")` here.
// ===========================================================================

struct RollUpView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables
    private let ballRadius:   CGFloat = 18      // matches Roll Along's ball (BallGameView.ballRadius)
    private let gravity:      CGFloat = 2_200     // px/s² downward
    private let jumpSpeed:    CGFloat = 980       // px/s upward on a jump
    private let moveAccel:    CGFloat = 6_900     // tilt → horizontal accel (2× the previous sensitivity)
    private let airFriction:  CGFloat = 0.90
    private let maxVx:        CGFloat = 1_080      // raised with moveAccel so terminal steering speed actually doubles (cap doesn't clip)
    private let maxFall:      CGFloat = 1_500
    private let cameraTargetFrac: CGFloat = 0.46  // keep the ball ~46% down the screen
    private let pixelsPerMeter:  CGFloat = 12      // height → "m" score

    // MARK: - Model
    private struct Platform: Identifiable {
        let id: Int
        var worldX: CGFloat   // centre, screen-x space
        let worldY: CGFloat   // height (y up)
        let width: CGFloat
    }

    private enum Phase { case ready, playing, over }

    // MARK: - State
    @State private var arena: CGSize = .zero
    @State private var phase: Phase = .ready

    @State private var ballX: CGFloat = 0          // screen-x
    @State private var ballY: CGFloat = 0          // world height (y up)
    @State private var prevBallY: CGFloat = 0
    @State private var vx: CGFloat = 0
    @State private var vy: CGFloat = 0
    @State private var grounded: Int? = nil         // platform id the ball rests on
    @State private var airJumpsLeft = 0

    @State private var platforms: [Platform] = []
    @State private var nextPlatformID = 0
    @State private var topSpawnY: CGFloat = 0
    @State private var camBottom: CGFloat = 0
    @State private var groundY: CGFloat = 0
    @State private var maxBallY: CGFloat = 0
    /// Seconds elapsed while actually climbing (accumulated from the physics
    /// tick, so it excludes paused / backgrounded time).  Drives the run-time
    /// half of the Roll Up highscore.
    @State private var runSeconds: Double = 0

    @State private var trail: [CGPoint] = []
    private let trailMaxLen = 14
    private let trailMinStep: CGFloat = 4

    // MARK: - Derived
    private var heightMeters: Int { max(0, Int((maxBallY - groundY) / pixelsPerMeter)) }
    private var bestMeters: Int { gameState.minigameBests["rollup", default: 0] }
    /// This run's elapsed climb time, whole seconds.
    private var runTimeSeconds: Int { Int(runSeconds.rounded()) }
    private var boundary: Boundary { gameState.equippedBoundary }
    /// Continuous best height of this run in meters (0 at the start) — drives
    /// the sky.  It follows `maxBallY`, so it matches the score, never goes
    /// back down mid-run, and resets with a new run.
    private var skyMeters: Double {
        guard arena.height > 0 else { return 0 }
        return max(0, Double(maxBallY - groundY) / Double(pixelsPerMeter))
    }
    /// 0 when the sky behind the HUD is light (dark text), 1 when it is dark
    /// (white text); eased so the swap is gradual, not a flip.
    private var hudWhiteness: Double {
        let top = RollUpSky.altitude(atY: 0, height: Double(arena.height), meters: skyMeters)
        let l = RollUpSky.lab(atMeters: top).L
        return 1 - RollUpSky.smoothstep(0.70, 0.78, l)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            background

            GeometryReader { geo in
                ZStack {
                    platformsLayer
                    trailLayer.allowsHitTesting(false)
                    ballLayer
                }
                .contentShape(Rectangle())
                .onAppear { layout(geo.size) }
                .onChange(of: geo.size) { _, s in layout(s) }
                .onTapGesture { handleTap() }
            }

            topBar
            HomeQuitButton()
            if phase == .ready { startPrompt }
            if phase == .over { gameOverOverlay }

            // S2-T2: trophy-unlock banner host — inert until the game-over
            // overlay drains the queue (never mid-run; §6).
            TrophyToastHost(queue: gameState.trophyToasts,
                            hapticsEnabled: gameState.hapticsEnabled,
                            soundEnabled: gameState.soundEnabled)
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

    /// The Roll Up sky — the same for every player (not a cosmetic).  One
    /// Canvas draws the gradient, stars and clouds from precomputed data; the
    /// TimelineView only animates twinkle and drift, and pauses entirely
    /// under Reduce Motion.  A static noise tile dithers away gradient bands.
    private var background: some View {
        let meters = skyMeters
        let still = reduceMotion
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: still)) { timeline in
            let t = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                RollUpSky.draw(in: &ctx, size: size, meters: meters, time: t, still: still)
            }
        }
        .overlay { ditherOverlay }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var ditherOverlay: some View {
        if let tile = RollUpSky.ditherTile {
            Image(decorative: tile, scale: 3)
                .resizable(resizingMode: .tile)
                .interpolation(.none)
                .opacity(0.035)
        }
    }

    private var platformsLayer: some View {
        Canvas { ctx, _ in
            guard arena.width > 0 else { return }
            for p in platforms {
                let sy = screenY(p.worldY)
                guard sy > -20, sy < arena.height + 20 else { continue }
                let isGround = p.id == 0
                let rect = CGRect(x: p.worldX - p.width / 2, y: sy - 7,
                                  width: p.width, height: 14)
                let path = Path(roundedRect: rect, cornerRadius: 7)
                // The Boundary cosmetic themes the platforms; the ground is a
                // darker shade of the same so it reads as the same material.
                let top = isGround ? boundary.deepColor : boundary.color
                let bot = isGround ? boundary.deepColor : boundary.deepColor
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: [top, bot]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
                ctx.stroke(path, with: .color(boundary.edgeColor.opacity(0.45)), lineWidth: 1)
            }
        }
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
                ctx.stroke(path, with: .color(color.opacity(0.08 + 0.45 * age)),
                           style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private var ballLayer: some View {
        BallSkinView(skin: gameState.activeSkin, diameter: ballRadius * 2)
            .frame(width: ballRadius * 2, height: ballRadius * 2)
            .shadow(color: .black.opacity(0.5), radius: 5, x: 1, y: 3)
            .position(x: ballX, y: screenY(ballY))
            .opacity(phase == .over ? 0 : 1)
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
                    // Text color follows the sky: dark on the pale horizon,
                    // white once the sky deepens.
                    Text("\(heightMeters) m")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(Color(white: 0.13 + 0.87 * hudWhiteness))
                        .monospacedDigit()
                    Text("ROLL UP")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color(white: 0.36 + 0.16 * hudWhiteness))
                        .accessibilityIdentifier("RollUpView")
                }
                Spacer()
                // No lives pill — minigames are free.  Keep a matching slot so
                // the height stays centered.
                Color.clear.frame(width: 36, height: 36)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var startPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 1.0))
            Text("Tap to jump")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Tilt to steer, tap to pop up.\nClimb as high as you can.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roll Up. Tilt to steer and tap to jump up the platforms. Climb as high as you can. Tap to begin.")
    }

    private var gameOverOverlay: some View {
        let isBest = heightMeters > 0 && heightMeters >= bestMeters
        let coins = runCoins
        return ZStack {
            Color.black.opacity(0.74).ignoresSafeArea()
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(isBest ? "New Best!" : "Run Over")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(isBest ? Color(red: 0.45, green: 0.82, blue: 1.0)
                                               : Color(white: 0.88))
                    Text("\(heightMeters) m climbed · best \(max(bestMeters, heightMeters)) m")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.65))
                    Text("Time \(LeaderboardBoard.rollUpTime(runTimeSeconds)) · best run \(LeaderboardBoard.rollUpTime(gameState.rollupBestSeconds))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                }
                // Solo minigames pay no coins, so this line only shows if a
                // payout is ever set in CoinPayouts.
                if coins > 0 {
                    HStack(spacing: 12) {
                        CoinIcon(size: 40)
                        Text("+\(coins)")
                            .font(.system(size: 46, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Plus \(coins) coins")
                }
                VStack(spacing: 12) {
                    Button { startRun() } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 0.45, green: 0.78, blue: 1.0)))
                    }
                    ResultShareButton(result: ShareableResult(
                        mode: "Roll Up",
                        headline: "\(heightMeters) m",
                        subtitle: "Best \(max(bestMeters, heightMeters)) m",
                        skin: gameState.activeSkin,
                        trail: gameState.equippedTrail,
                        won: isBest))
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
        // S2-T2: run ended — drain this run's trophies, coalesced (§6).
        .onAppear { gameState.endTrophyRun() }
    }

    // MARK: - Coordinate mapping

    /// World height (y up) → screen y (y down).  The camera (`camBottom`) is the
    /// world height sitting at the bottom edge of the screen.
    private func screenY(_ worldY: CGFloat) -> CGFloat {
        arena.height - (worldY - camBottom)
    }

    // MARK: - Lifecycle

    private func layout(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let wasEmpty = arena.width == 0
        arena = size
        if wasEmpty { startRun() }
    }

    /// Lay out a fresh run: ground platform + a reachable stack above, ball
    /// resting on the ground, camera at the bottom.  Leaves the run un-started
    /// (`.ready`) so the start prompt shows over a settled board.
    private func startRun() {
        guard arena.width > 0 else { return }
        // S2-T2: a fresh climb — arm the toast queue (§6 coalesce-at-run-end).
        gameState.beginTrophyRun()
        camBottom = 0
        groundY = arena.height * 0.20            // ground sits ~80% down the screen
        platforms = [Platform(id: 0, worldX: arena.width / 2, worldY: groundY, width: arena.width)]
        nextPlatformID = 1
        topSpawnY = groundY

        ballX = arena.width / 2
        ballY = groundY + ballRadius
        prevBallY = ballY
        vx = 0; vy = 0
        grounded = 0
        airJumpsLeft = 1
        maxBallY = ballY
        runSeconds = 0
        trail = []
        ensurePlatforms()
        phase = .ready
    }

    /// Coins paid for a finished run (`CoinPayouts.rollUp`: none — solo).
    private var runCoins: Int { CoinPayouts.rollUp(meters: heightMeters) }

    // MARK: - Input

    private func handleTap() {
        switch phase {
        case .ready:
            phase = .playing
            jump()
        case .playing:
            jump()
        case .over:
            break   // overlay buttons handle restart
        }
    }

    private func jump() {
        if grounded != nil {
            vy = jumpSpeed
            grounded = nil
            airJumpsLeft = 1
            if gameState.hapticsEnabled { Haptics.light() }
            AudioManager.shared.playBounce(enabled: gameState.soundEnabled)
        } else if airJumpsLeft > 0 {
            vy = jumpSpeed * 0.9
            airJumpsLeft -= 1
            if gameState.hapticsEnabled { Haptics.soft() }
            AudioManager.shared.playBounce(enabled: gameState.soundEnabled)
        }
    }

    // MARK: - Simulation

    private func tick() {
        guard phase == .playing, arena.width > 0 else { return }
        let dt: CGFloat = 1.0 / 60.0
        runSeconds += Double(dt)   // climb time (playing frames only)

        // Horizontal: tilt → accel, with air friction + cap.
        vx += CGFloat(motion.gravity.x) * moveAccel * dt
        vx *= airFriction
        if vx > maxVx { vx = maxVx } else if vx < -maxVx { vx = -maxVx }
        ballX += vx * dt
        // Bounce gently off the side walls so the ball stays in play.
        if ballX < ballRadius { ballX = ballRadius; vx = abs(vx) * 0.5 }
        else if ballX > arena.width - ballRadius { ballX = arena.width - ballRadius; vx = -abs(vx) * 0.5 }

        if grounded != nil {
            // Resting on a platform: roll off the edge → become airborne.
            if let p = platforms.first(where: { $0.id == grounded }) {
                if abs(ballX - p.worldX) > p.width / 2 + ballRadius * 0.4 {
                    grounded = nil
                } else {
                    ballY = p.worldY + ballRadius   // stay glued while grounded
                }
            } else {
                grounded = nil
            }
        }

        if grounded == nil {
            // Gravity (y up → subtract) with a fall-speed cap.
            vy -= gravity * dt
            if vy < -maxFall { vy = -maxFall }
            prevBallY = ballY
            ballY += vy * dt
            landingCheck()
        }

        maxBallY = max(maxBallY, ballY)
        updateCamera()
        ensurePlatforms()
        prunePlatforms()
        accumulateTrail()

        // Fell off the bottom of the screen → run over.
        if screenY(ballY) > arena.height + ballRadius * 2 { endRun() }
    }

    /// One-way landing: only when falling (vy ≤ 0) and the ball's bottom crosses
    /// a platform's top from above, with horizontal overlap.
    private func landingCheck() {
        guard vy <= 0 else { return }
        let bottom = ballY - ballRadius
        let prevBottom = prevBallY - ballRadius
        for p in platforms {
            guard abs(ballX - p.worldX) <= p.width / 2 + ballRadius * 0.5 else { continue }
            if prevBottom >= p.worldY && bottom <= p.worldY {
                ballY = p.worldY + ballRadius
                vy = 0
                grounded = p.id
                airJumpsLeft = 1
                if gameState.hapticsEnabled { Haptics.soft() }
                return
            }
        }
    }

    /// Raise the camera so a climbing ball stays around `cameraTargetFrac` down
    /// the screen.  The camera never descends, so a fall plays out fully.
    private func updateCamera() {
        let target = arena.height * cameraTargetFrac
        let sy = screenY(ballY)
        if sy < target { camBottom += (target - sy) }
    }

    /// Spawn platforms above until the world is populated past the top of screen.
    private func ensurePlatforms() {
        let ceiling = camBottom + arena.height + 220
        while topSpawnY < ceiling {
            // Difficulty rises with height: wider gaps, narrower platforms.
            let climb = max(0, topSpawnY - groundY)
            let extra = min(55, climb / 70)          // ramp gaps up, but stay single-jump reachable (~218px)
            let gap = CGFloat.random(in: 105...135) + extra
            topSpawnY += gap
            let width = max(58, 112 - climb / 120)
            let half = width / 2 + 10
            let x = CGFloat.random(in: half...(arena.width - half))
            platforms.append(Platform(id: nextPlatformID, worldX: x, worldY: topSpawnY, width: width))
            nextPlatformID += 1
        }
    }

    /// Drop platforms that have scrolled well below the screen.
    private func prunePlatforms() {
        let floor = camBottom - 60
        platforms.removeAll { $0.worldY < floor && $0.id != grounded }
    }

    private func accumulateTrail() {
        let screenPos = CGPoint(x: ballX, y: screenY(ballY))
        if let last = trail.last {
            if hypot(screenPos.x - last.x, screenPos.y - last.y) > trailMinStep { trail.append(screenPos) }
        } else {
            trail.append(screenPos)
        }
        if trail.count > trailMaxLen { trail.removeFirst(trail.count - trailMaxLen) }
    }

    private func endRun() {
        phase = .over
        let meters  = heightMeters
        let seconds = runTimeSeconds
        // Keeps the best height + the duration of that run, and publishes both
        // to the leaderboard.
        let isBest  = gameState.recordRollUpRun(height: meters, seconds: seconds)
        let coins = runCoins
        if coins > 0 { gameState.addCoins(coins) }
        if isBest && meters > 0 { gameState.addCoins(GameState.minigameBestBonus) }
        // No `consumeLife()` — minigames never cost lives.
        if gameState.hapticsEnabled {
            Haptics.medium()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { Haptics.medium() }
        }
        AnalyticsClient.shared.track(
            "minigame_round_over",
            properties: ["game_mode": .string("rollup"),
                         "won": .bool(isBest),
                         "height_m": .int(meters),
                         "time_s": .int(seconds),
                         "coins": .int(coins)])
    }
}


// MARK: - Roll Up sky
//
// One long sky for everyone, painted by height climbed (meters, = the score):
//
//     0 m  pale near-white horizon      140 m  dusk violet
//    20 m  pale cream                   185 m  deep blue
//    45 m  sunrise gold                 240 m  night navy
//    75 m  coral                        310 m  deep space
//   105 m  sunset rose                  400 m+ space black
//
// Colors are blended in OKLab with a Catmull-Rom curve through the stops, so
// the change has no kinks (seams) at the stops.  Soft clouds live at 35–235 m
// (fading in from 35 m, full 60–165 m, gone by 235 m) with parallax; stars
// fade in from 150 m and are full by 330 m.  Everything (stops in OKLab,
// stars, clouds and their tints, the dither tile) is computed once.
private enum RollUpSky {
    /// Must match RollUpView.pixelsPerMeter.
    static let pointsPerMeter = 12.0
    /// How much of the sky the screen shows: 1 = the sky scrolls with the
    /// platforms, smaller = a slower, gentler gradient top to bottom.
    static let screenSpread = 0.4
    static let sampleCount = 10

    struct Lab { var L: Double; var a: Double; var b: Double }

    // (height in meters, sRGB 0–1)
    private static let stopTable: [(Double, Double, Double, Double)] = [
        (  0, 0.965, 0.961, 0.945),   // horizon: pale near-white
        ( 20, 0.992, 0.925, 0.835),   // pale cream
        ( 45, 1.000, 0.808, 0.580),   // sunrise gold
        ( 75, 0.988, 0.580, 0.427),   // coral
        (105, 0.882, 0.384, 0.494),   // sunset rose
        (140, 0.553, 0.302, 0.604),   // dusk violet
        (185, 0.196, 0.259, 0.588),   // deep blue
        (240, 0.078, 0.110, 0.322),   // night navy
        (310, 0.031, 0.039, 0.122),   // deep space
        (400, 0.012, 0.012, 0.035),   // space black
    ]
    private static let stopMeters: [Double] = stopTable.map { $0.0 }
    private static let stopLabs: [Lab] = stopTable.map { oklab(r: $0.1, g: $0.2, b: $0.3) }

    static let cloudStart = 35.0, cloudFullFrom = 60.0, cloudFullTo = 165.0, cloudEnd = 235.0
    static let starStart = 150.0, starFull = 330.0

    // MARK: Color math

    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    /// Sky height (m) shown at screen y.  The screen center shows the height
    /// climbed; the top shows a little higher, the bottom a little lower.
    static func altitude(atY y: Double, height h: Double, meters: Double) -> Double {
        meters + (h * 0.5 - y) / pointsPerMeter * screenSpread
    }

    /// Sky color at a height, in OKLab.  Catmull-Rom through the stops (C1
    /// continuous, so no visible seams); clamped at both ends.
    static func lab(atMeters m: Double) -> Lab {
        let n = stopMeters.count
        if m <= stopMeters[0] { return stopLabs[0] }
        if m >= stopMeters[n - 1] { return stopLabs[n - 1] }
        var i = 0
        while i < n - 2 && m >= stopMeters[i + 1] { i += 1 }
        let t = (m - stopMeters[i]) / (stopMeters[i + 1] - stopMeters[i])
        let t2 = t * t, t3 = t2 * t
        let p0 = stopLabs[max(0, i - 1)], p1 = stopLabs[i]
        let p2 = stopLabs[i + 1],         p3 = stopLabs[min(n - 1, i + 2)]
        func cr(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            let k1 = (-a + c) * t
            let k2 = (2 * a - 5 * b + 4 * c - d) * t2
            let k3 = (-a + 3 * b - 3 * c + d) * t3
            return 0.5 * (2 * b + k1 + k2 + k3)
        }
        return Lab(L: cr(p0.L, p1.L, p2.L, p3.L),
                   a: cr(p0.a, p1.a, p2.a, p3.a),
                   b: cr(p0.b, p1.b, p2.b, p3.b))
    }

    static func color(atMeters m: Double) -> Color { color(lab(atMeters: m)) }

    static func color(_ c: Lab, opacity: Double = 1) -> Color {
        let rgb = srgb(c)
        return Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: opacity)
    }

    private static func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    private static func toGamma(_ c: Double) -> Double {
        let v = min(1, max(0, c))
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    static func oklab(r: Double, g: Double, b: Double) -> Lab {
        let lr = toLinear(r), lg = toLinear(g), lb = toLinear(b)
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        let outL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let outA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let outB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return Lab(L: outL, a: outA, b: outB)
    }

    static func srgb(_ c: Lab) -> (Double, Double, Double) {
        let l1 = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b
        let m1 = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b
        let s1 = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b
        let l = l1 * l1 * l1, m = m1 * m1 * m1, s = s1 * s1 * s1
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return (toGamma(r), toGamma(g), toGamma(b))
    }

    // MARK: Precomputed scenery

    /// SplitMix64 — a tiny seeded generator so the scenery is identical for
    /// everyone and every run.
    private struct RNG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }
    }

    struct Star {
        let x: Double; let y: Double; let r: Double; let bright: Double
        let phase: Double; let speed: Double
    }
    struct Puff { let dx: Double; let dy: Double; let r: Double }
    struct Cloud {
        let meters: Double; let x: Double; let scale: Double
        let parallax: Double; let drift: Double; let alpha: Double
        let tint: Color; let puffs: [Puff]
    }

    static let stars: [Star] = {
        var rng = RNG(state: 0x57A25)
        var out: [Star] = []
        out.reserveCapacity(150)
        for _ in 0..<150 {
            let big = rng.unit() < 0.08
            let x = rng.unit(), y = rng.unit()
            let r = big ? 1.3 + rng.unit() * 0.6 : 0.5 + rng.unit() * 0.7
            let bright = 0.45 + rng.unit() * 0.55
            let phase = rng.unit() * 2 * Double.pi
            let speed = 0.8 + rng.unit() * 1.8
            out.append(Star(x: x, y: y, r: r, bright: bright, phase: phase, speed: speed))
        }
        return out
    }()

    static let clouds: [Cloud] = {
        var rng = RNG(state: 0xC10D5)
        var out: [Cloud] = []
        var m = cloudStart
        var left = rng.unit() < 0.5
        while m < cloudEnd {
            let count = 4 + Int(rng.unit() * 3)
            var puffs: [Puff] = []
            for i in 0..<count {
                let f = Double(i) / Double(count - 1) - 0.5          // -0.5 … 0.5
                let mid = 0.5 - abs(f)                                 // 0 at the ends, 0.5 center
                let dx = f * 1.7 + (rng.unit() - 0.5) * 0.25
                let dy = (rng.unit() - 0.5) * 0.2 - mid * 0.35
                let r = 0.42 + mid * 0.55 + rng.unit() * 0.15
                puffs.append(Puff(dx: dx, dy: dy, r: r))
            }
            let parallax = 0.45 + rng.unit() * 0.3
            // Farther (slower) clouds are a little fainter.
            let depth = 0.7 + 0.3 * (parallax - 0.45) / 0.3
            let env = smoothstep(cloudStart, cloudFullFrom, m)
                    * (1 - smoothstep(cloudFullTo, cloudEnd, m))
            // Tint: mostly white, picking up the sky's hue at that height.
            let sky = lab(atMeters: m)
            let tint = color(Lab(L: sky.L + (1 - sky.L) * 0.75, a: sky.a * 0.4, b: sky.b * 0.4))
            let x = left ? 0.10 + rng.unit() * 0.32 : 0.58 + rng.unit() * 0.32
            let scale = 0.75 + rng.unit() * 0.5
            let drift = (rng.unit() - 0.5) * 8                         // pt/s, either way
            out.append(Cloud(meters: m, x: x, scale: scale, parallax: parallax,
                             drift: drift, alpha: 0.6 * env * depth,
                             tint: tint, puffs: puffs))
            m += 11 + rng.unit() * 9
            left.toggle()
        }
        return out
    }()

    /// 64×64 gray noise, drawn tiled at ~3.5% to break up gradient banding.
    static let ditherTile: CGImage? = {
        let n = 64
        var rng = RNG(state: 0xD17E5)
        var bytes = [UInt8](repeating: 0, count: n * n)
        for i in 0..<bytes.count { bytes[i] = UInt8(truncatingIfNeeded: rng.next() >> 56) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }()

    private static func wrap(_ v: Double, _ span: Double) -> Double {
        let r = v.truncatingRemainder(dividingBy: span)
        return r < 0 ? r + span : r
    }

    // MARK: Drawing

    static func draw(in ctx: inout GraphicsContext, size: CGSize, meters: Double,
                     time t: Double, still: Bool) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 0, h > 0 else { return }

        // 1. The gradient for the visible window.
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(sampleCount)
        for i in 0..<sampleCount {
            let f = Double(i) / Double(sampleCount - 1)
            let alt = altitude(atY: f * h, height: h, meters: meters)
            stops.append(Gradient.Stop(color: color(atMeters: alt), location: CGFloat(f)))
        }
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(stops: stops),
                                       startPoint: .zero,
                                       endPoint: CGPoint(x: 0, y: size.height)))

        // 2. Stars — only once the top of the screen is high enough.
        if altitude(atY: 0, height: h, meters: meters) > starStart {
            for s in stars {
                let y = wrap(s.y * h + meters * pointsPerMeter * 0.05, h)
                let fade = smoothstep(starStart, starFull,
                                      altitude(atY: y, height: h, meters: meters))
                if fade < 0.01 { continue }
                let twinkle = still ? 1.0 : 0.72 + 0.28 * sin(t * s.speed + s.phase)
                let a = fade * s.bright * twinkle
                let x = s.x * w
                let dot = CGRect(x: x - s.r, y: y - s.r, width: s.r * 2, height: s.r * 2)
                ctx.fill(Path(ellipseIn: dot), with: .color(.white.opacity(a)))
                if s.r > 1.3 {
                    let g = s.r * 3
                    let glow = CGRect(x: x - g, y: y - g, width: g * 2, height: g * 2)
                    ctx.fill(Path(ellipseIn: glow), with: .color(.white.opacity(a * 0.12)))
                }
            }
        }

        // 3. Clouds — soft radial puffs, each cloud at a fixed height with its
        //    own parallax (slower than the platforms, so they sit behind).
        if meters > cloudStart - 80 && meters < cloudEnd + 80 {
            let base = w * 0.17
            for c in clouds where c.alpha > 0.01 {
                let unit = base * c.scale
                let reach = unit * 1.8
                let cy = h * 0.5 - (c.meters - meters) * pointsPerMeter * c.parallax
                if cy < -reach || cy > h + reach { continue }
                let span = w + 2 * reach
                let driftX = still ? 0 : c.drift * t
                let cx = wrap(c.x * w + driftX + reach, span) - reach
                let gradient = Gradient(stops: [
                    Gradient.Stop(color: c.tint.opacity(c.alpha), location: 0),
                    Gradient.Stop(color: c.tint.opacity(c.alpha * 0.55), location: 0.55),
                    Gradient.Stop(color: c.tint.opacity(0), location: 1)])
                for p in c.puffs {
                    let r = p.r * unit
                    let center = CGPoint(x: cx + p.dx * unit, y: cy + p.dy * unit)
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect),
                             with: .radialGradient(gradient, center: center,
                                                   startRadius: 0, endRadius: r))
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RollUpView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
