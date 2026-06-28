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
// ECONOMY (Mac's call): shares the climb's life economy — each run that ends
// (the ball falls off the bottom) costs a real life; Diamond Balls = no cost,
// and running out surfaces the Get Lives sheet.  Coins scale with the height
// reached, and a personal best is tracked like Pinball / Gold Rush.
//
// COORDINATES: world space has y INCREASING UPWARD (height).  A camera that only
// ever rises maps world → screen, so climbing scrolls the world down and a fall
// eventually drops the ball off the bottom.
//
// SAFE BY CONSTRUCTION: brand-new isolated file; reuses only BallMotion /
// PhysicsClock, the lives + coin economy, BallSkinView, CoinIcon, and
// ResultShareButton.  Reached only when HomeView routes `.mode("rollup")` here.
// ===========================================================================

struct RollUpView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = BallMotion()
    @StateObject private var clock  = PhysicsClock()

    // MARK: - Tunables
    private let ballRadius:   CGFloat = 18      // matches Roll Along's ball (BallGameView.ballRadius)
    private let gravity:      CGFloat = 2_200     // px/s² downward
    private let jumpSpeed:    CGFloat = 980       // px/s upward on a jump
    private let moveAccel:    CGFloat = 3_450     // tilt → horizontal accel (3× more sensitive)
    private let airFriction:  CGFloat = 0.90
    private let maxVx:        CGFloat = 540
    private let maxFall:      CGFloat = 1_500
    private let cameraTargetFrac: CGFloat = 0.46  // keep the ball ~46% down the screen
    private let pixelsPerMeter:  CGFloat = 12      // height → "m" score
    private let coinsPerMeter:   Double  = 0.20    // payout scale
    private let maxRunCoins      = 250

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

    @State private var trail: [CGPoint] = []
    @State private var showBuyLivesSheet = false
    private let trailMaxLen = 14
    private let trailMinStep: CGFloat = 4

    // MARK: - Derived
    private var heightMeters: Int { max(0, Int((maxBallY - groundY) / pixelsPerMeter)) }
    private var bestMeters: Int { gameState.minigameBests["rollup", default: 0] }
    private var boundary: Boundary { gameState.equippedBoundary }
    private var outOfLives: Bool { !gameState.unlimitedLives && gameState.displayedLives <= 0 }

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
            if phase == .ready && !outOfLives { startPrompt }
            if phase == .over && !outOfLives { gameOverOverlay }
            if outOfLives { outOfLivesOverlay }
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
        .sheet(isPresented: $showBuyLivesSheet) {
            BuyLivesSheet().environmentObject(gameState)
        }
    }

    // MARK: - Layers

    private var background: some View {
        LinearGradient(colors: [Color(red: 0.06, green: 0.09, blue: 0.18),
                                Color(red: 0.10, green: 0.14, blue: 0.30),
                                Color(red: 0.04, green: 0.06, blue: 0.14)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
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
                Button { nav.goHome() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Circle().fill(Color(white: 0.16)))
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("RollUpCloseButton")
                Spacer()
                VStack(spacing: 1) {
                    Text("\(heightMeters) m")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("ROLL UP")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color(white: 0.5))
                        .accessibilityIdentifier("RollUpView")
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
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color(red: 0.45, green: 0.78, blue: 1.0))
            Text("Tap to jump")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Tilt to steer, tap to pop up.\nClimb as high as you can — a fall costs a life.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roll Up. Tilt to steer and tap to jump up the platforms. Climb as high as you can. A fall costs a life. Tap to begin.")
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
                }
                HStack(spacing: 12) {
                    CoinIcon(size: 40)
                    Text("+\(coins)")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Plus \(coins) coins")
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
                Text("Get more lives to keep climbing.")
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
        trail = []
        ensurePlatforms()
        phase = .ready
    }

    /// Coins paid for a finished run — scaled by height, capped.
    private var runCoins: Int {
        min(maxRunCoins, Int((Double(heightMeters) * coinsPerMeter).rounded()))
    }

    // MARK: - Input

    private func handleTap() {
        if outOfLives { return }
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
        let meters = heightMeters
        let isBest = meters > bestMeters
        if isBest { gameState.minigameBests["rollup"] = meters }
        let coins = runCoins
        if coins > 0 { gameState.addCoins(coins) }
        if isBest && meters > 0 { gameState.addCoins(GameState.minigameBestBonus) }
        gameState.consumeLife()
        if gameState.hapticsEnabled {
            Haptics.medium()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { Haptics.medium() }
        }
        AnalyticsClient.shared.track(
            "minigame_round_over",
            properties: ["game_mode": .string("rollup"),
                         "won": .bool(isBest),
                         "height_m": .int(meters),
                         "coins": .int(coins)])
    }
}

#Preview {
    NavigationStack {
        RollUpView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
