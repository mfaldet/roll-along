import SwiftUI

// ===========================================================================
// PinballView — the "Pinball" mode.
//
// Classic single-ball pinball, NO tilt.  Gravity pulls the ball down a vertical
// playfield; you tap the LEFT half of the screen to flick the left flipper and
// the RIGHT half to flick the right one.  Knock the ball into the pop bumpers
// up top to rack up score, and keep it alive off the flippers.  Three balls,
// then the run ends and your score converts to coins.
//
// Single-player by construction: there is no AI and no second device — it is
// you against gravity and the drain.
//
// Copyright-safe: this is generic pinball (flippers, pop bumpers, a plunger
// lane, a centre drain).  Game mechanics are not copyrightable; only specific
// creative expression is.  No trademarked table names, manufacturer marks, or
// licensed themes appear here, and all art is drawn from primitives.
//
// SAFE BY CONSTRUCTION: an isolated file.  It reuses only PhysicsClock and the
// coin / skin economy on GameState; it touches nothing in the climb engine and
// deliberately does NOT use BallMotion (this mode ignores tilt).  Reached only
// when HomeView routes `.mode("pinball")` here and PinballMode is flagged on.
//
// FEEL IS TUNABLE: every gameplay number lives in the "Tunables" block.
// ===========================================================================

struct PinballView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav: Navigator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var clock = PhysicsClock()

    // MARK: - Tunables

    private let ballRadius:    CGFloat = 8         // smaller ball → the playfield feels larger
    private let gravity:       CGFloat = 980        // downward pull, points per second^2
    private let drag:          CGFloat = 0.999      // gentle air damping per tick
    private let maxSpeed:      CGFloat = 1_400
    private let wallBounce:    CGFloat = 0.82

    private let bumperRadius:  CGFloat = 27
    private let bumperRest:    CGFloat = 0.90
    private let bumperPop:     CGFloat = 380         // floor on speed right after a bumper kick
    private let bumperScore         = 500

    private let slingThickness: CGFloat = 7
    private let slingRest:      CGFloat = 0.55
    private let slingPop:       CGFloat = 320         // outward kick off a slingshot
    private let slingScore           = 150
    private let targetScore          = 300
    private let bankBonus            = 2500           // clearing the whole drop-target bank
    private let maxMultiplier        = 5

    private let flipperLenFrac: CGFloat = 0.26       // of field width — shorter, so the flick can't slip past the ball
    private let flipperThickness: CGFloat = 7         // visual half-thickness
    private let flipperHitThickness: CGFloat = 11     // collision band (wider than the look) — resists tunnelling
    private let flipperRest:    CGFloat = 0.32        // restitution off a still flipper
    private let restAngleDeg:   CGFloat = 26          // tip down-and-inward at rest
    private let activeAngleDeg: CGFloat = -24         // tip swings up when flicked
    private let flickGain:      CGFloat = 2.6         // multiplier on the bat's upward surface speed (the kick)
    private let flickDuration       = 9               // ticks a flick stays "up"

    private let launchSpeed:    CGFloat = 1_180       // plunger kick up the lane
    private let curvePush:      CGFloat = 1_500       // curved lane top nudges ball into play

    private let startingBalls       = 3
    private let coinsPerScore       = 250             // coins = score / this

    private let topReserve: CGFloat = 120             // HUD breathing room at the top

    // MARK: - Model

    private struct BallBody {
        var pos: CGPoint = .zero
        var vel: CGVector = .zero
    }

    private struct Bumper: Identifiable {
        let id = UUID()
        var pos: CGPoint
        var litTicks = 0
    }

    /// An angled kicker just above each flipper — bounces the ball back into
    /// play (keeps it alive) and scores.
    private struct Sling { var a: CGPoint = .zero; var b: CGPoint = .zero; var litTicks = 0 }

    /// A drop target in the upper bank.  Lighting the whole bank bumps the
    /// score multiplier and pays a bonus, then the bank resets.
    private struct Target: Identifiable { let id = UUID(); var rect: CGRect; var lit = false; var litTicks = 0 }

    private static let ballTint   = Color(red: 0.85, green: 0.88, blue: 0.95)
    private static let flipperTint = Color(red: 0.25, green: 0.62, blue: 1.00)
    private static let bumperTint = Color(red: 1.00, green: 0.62, blue: 0.28)
    private static let slingTint  = Color(red: 0.40, green: 0.85, blue: 0.55)
    private static let targetTint = Color(red: 1.00, green: 0.85, blue: 0.30)

    // MARK: - State

    @State private var field: CGRect = .zero
    @State private var ball = BallBody()
    @State private var bumpers: [Bumper] = []
    @State private var leftSling  = Sling()
    @State private var rightSling = Sling()
    @State private var targets: [Target] = []
    @State private var multiplier = 1

    // Derived geometry, filled by layout().
    @State private var leftPivot:   CGPoint = .zero
    @State private var rightPivot:  CGPoint = .zero
    @State private var flipperLen:  CGFloat = 0
    @State private var dividerX:    CGFloat = 0
    @State private var dividerTopY: CGFloat = 0
    @State private var laneCenterX: CGFloat = 0

    @State private var leftFlickTicks  = 0
    @State private var rightFlickTicks = 0
    @State private var touchActive     = false   // one flick per finger-press

    @State private var score      = 0
    @State private var ballsLeft  = 3
    @State private var ballInPlay = false

    @State private var started = false
    @State private var isOver  = false
    @State private var awarded = false
    @State private var localTick = 0

    @State private var mapIndex    = 0
    @State private var showMapName = false

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.07), Color(white: 0.03)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    Color.clear
                    playfield
                    laneDivider
                    ForEach(targets) { targetView($0) }
                    ForEach(bumpers) { bumperView($0).position($0.pos) }
                    slingView(leftSling)
                    slingView(rightSling)
                    flipperPath(isLeft: true)
                    flipperPath(isLeft: false)
                    ballView
                }
                .contentShape(Rectangle())
                .onAppear { layout(geo.size); reset() }
                .onChange(of: geo.size) { _, newSize in
                    let wasEmpty = bumpers.isEmpty
                    layout(newSize)
                    if wasEmpty { reset() }
                }
                .gesture(
                    // Fire on touch-DOWN (not lift) so the flippers feel instant;
                    // one action per touch via `touchActive`.
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if !touchActive { touchActive = true; handleTap(at: v.startLocation) }
                        }
                        .onEnded { _ in touchActive = false }
                )
            }

            topBar
            if !started && !isOver { startPrompt }
            if isOver { gameOverOverlay }
            if showMapName && !isOver { mapNameLabel }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(clock.$tickCount) { _ in tick() }
        .onAppear { clock.start() }
        .onDisappear { clock.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clock.stop() }
            else if phase == .active && started && !isOver { clock.start() }
        }
    }

    // MARK: - Render

    private var playfield: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.08)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.22), lineWidth: 1.5))
            .frame(width: field.width, height: field.height)
            .position(x: field.midX, y: field.midY)
    }

    private var laneDivider: some View {
        Path { p in
            p.move(to: CGPoint(x: dividerX, y: field.maxY))
            p.addLine(to: CGPoint(x: dividerX, y: dividerTopY))
        }
        .stroke(Color(white: 0.30), style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }

    private func slingView(_ s: Sling) -> some View {
        let lit = s.litTicks > 0
        return Path { p in p.move(to: s.a); p.addLine(to: s.b) }
            .stroke(lit ? Color.white : Self.slingTint,
                    style: StrokeStyle(lineWidth: slingThickness * 2, lineCap: .round))
            .shadow(color: Self.slingTint.opacity(lit ? 0.9 : 0.4), radius: lit ? 8 : 3)
    }

    private func targetView(_ t: Target) -> some View {
        let on = t.lit || t.litTicks > 0
        return RoundedRectangle(cornerRadius: 3)
            .fill(on ? Self.targetTint : Color(white: 0.28))
            .frame(width: t.rect.width, height: t.rect.height)
            .overlay(RoundedRectangle(cornerRadius: 3)
                .stroke(Self.targetTint.opacity(on ? 0.95 : 0.40), lineWidth: 1))
            .shadow(color: Self.targetTint.opacity(on ? 0.7 : 0), radius: on ? 6 : 0)
            .position(x: t.rect.midX, y: t.rect.midY)
    }

    private func bumperView(_ b: Bumper) -> some View {
        let lit = b.litTicks > 0
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Self.bumperTint.opacity(lit ? 1.0 : 0.85),
                                              Self.bumperTint.opacity(0.35)],
                                     center: .init(x: 0.4, y: 0.35),
                                     startRadius: 1, endRadius: bumperRadius * 1.3))
            Circle().stroke(.white.opacity(lit ? 0.95 : 0.45), lineWidth: lit ? 4 : 2)
        }
        .frame(width: bumperRadius * 2, height: bumperRadius * 2)
        .shadow(color: Self.bumperTint.opacity(lit ? 0.7 : 0.0), radius: lit ? 14 : 0)
    }

    private func flipperPath(isLeft: Bool) -> some View {
        let pivot = isLeft ? leftPivot : rightPivot
        let tip = currentTip(isLeft: isLeft)
        return Path { p in
            p.move(to: pivot)
            p.addLine(to: tip)
        }
        .stroke(Self.flipperTint,
                style: StrokeStyle(lineWidth: flipperThickness * 2, lineCap: .round))
        .shadow(color: Self.flipperTint.opacity(0.5), radius: 4)
    }

    private var ballView: some View {
        BallSkinView(skin: gameState.activeSkin, diameter: ballRadius * 2)
            .frame(width: ballRadius * 2, height: ballRadius * 2)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 1, y: 2)
            .position(ball.pos)
            .opacity(ballInPlay ? 1 : (started ? 0.85 : 1))
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
                    Text("\(score)")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("SCORE")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color(white: 0.5))
                    if multiplier > 1 {
                        Text("×\(multiplier)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(Self.targetTint)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Self.targetTint.opacity(0.18)))
                            .padding(.top, 2)
                    }
                }
                Spacer()
                ballsPip
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var ballsPip: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<startingBalls, id: \.self) { i in
                    Circle()
                        .fill(i < ballsLeft ? Self.ballTint : Color(white: 0.22))
                        .frame(width: 9, height: 9)
                }
            }
            Text("BALLS")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(Color(white: 0.5))
        }
        .frame(width: 52, alignment: .trailing)
    }

    private var mapNameLabel: some View {
        VStack {
            Spacer().frame(height: topReserve + 6)
            Text(PinballMaps.maps[mapIndex % PinballMaps.maps.count].name)
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
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white)
            Text("Tap to launch")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Tap LEFT for the left flipper,\nRIGHT for the right.  No tilt — keep it alive!")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pinball. Tap the left side of the screen for the left flipper, the right side for the right flipper. Keep the ball alive and score as high as you can. Tap anywhere to launch.")
    }

    private var gameOverOverlay: some View {
        let banked = score / coinsPerScore
        return ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("Game Over")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("final score \(score)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.65))
                        .monospacedDigit()
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
                        mapIndex = (mapIndex + 1) % PinballMaps.maps.count
                        reset()
                    } label: {
                        Text("Play Again")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Self.flipperTint))
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

    // MARK: - Geometry

    private func layout(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let side: CGFloat = 12, bottom: CGFloat = 28
        field = CGRect(x: side, y: topReserve,
                       width: size.width - side * 2,
                       height: size.height - topReserve - bottom)

        flipperLen = field.width * flipperLenFrac
        let flipperY = field.maxY - field.height * 0.10
        let pivotInset = field.width * 0.17   // pivots nudged inward so the shorter bats still close the drain
        leftPivot  = CGPoint(x: field.minX + pivotInset, y: flipperY)
        rightPivot = CGPoint(x: field.maxX - pivotInset, y: flipperY)

        let laneWidth = field.width * 0.11
        dividerX = field.maxX - laneWidth
        dividerTopY = field.minY + field.height * 0.32
        laneCenterX = field.maxX - laneWidth / 2

        // Slingshots — angled kickers above + outboard of each flipper that
        // throw the ball back into play.
        let slBotY = flipperY - field.height * 0.05
        let slTopY = flipperY - field.height * 0.17
        leftSling  = Sling(a: CGPoint(x: field.minX + field.width * 0.05, y: slBotY),
                           b: CGPoint(x: leftPivot.x + field.width * 0.03, y: slTopY))
        rightSling = Sling(a: CGPoint(x: dividerX - field.width * 0.05, y: slBotY),
                           b: CGPoint(x: rightPivot.x - field.width * 0.03, y: slTopY))

        // Drop-target bank — a row across the mid-field; clearing every target
        // bumps the score multiplier and pays a bonus, then resets.
        let tW = field.width * 0.11, tH = field.height * 0.022
        let tY = field.minY + field.height * 0.55
        let span = field.width * 0.52
        let startX = field.midX - span / 2
        targets = (0..<4).map { i in
            let cxp = startX + span * CGFloat(i) / 3.0
            return Target(rect: CGRect(x: cxp - tW / 2, y: tY, width: tW, height: tH))
        }

        applyBumpers()
    }

    // MARK: - Lifecycle

    private func reset() {
        guard field.width > 0 else { return }
        started = false
        isOver = false
        awarded = false
        score = 0
        ballsLeft = startingBalls
        leftFlickTicks = 0
        rightFlickTicks = 0
        multiplier = 1
        for i in targets.indices { targets[i].lit = false; targets[i].litTicks = 0 }
        leftSling.litTicks = 0
        rightSling.litTicks = 0
        applyBumpers()
        showMapName = true
        placeBallInLane()
    }

    private func applyBumpers() {
        guard field.width > 0 else { return }
        let map = PinballMaps.maps[mapIndex % PinballMaps.maps.count]
        bumpers = map.bumperFracs.map { xf, yf in
            Bumper(pos: CGPoint(x: field.minX + field.width  * xf,
                                y: field.minY + field.height * yf))
        }
    }

    private func placeBallInLane() {
        ball.pos = CGPoint(x: laneCenterX, y: field.maxY - ballRadius - 4)
        ball.vel = .zero
        ballInPlay = false
    }

    private func launchBall() {
        ball.pos = CGPoint(x: laneCenterX, y: field.maxY - ballRadius - 4)
        ball.vel = CGVector(dx: 0, dy: -launchSpeed)
        ballInPlay = true
        if gameState.hapticsEnabled { Haptics.medium() }
    }

    private func loseBall() {
        ballInPlay = false
        ballsLeft -= 1
        if ballsLeft <= 0 {
            endGame()
        } else {
            placeBallInLane()
            if gameState.hapticsEnabled { Haptics.warning() }
        }
    }

    private func endGame() {
        guard !isOver else { return }
        isOver = true
        if !awarded {
            awarded = true
            let banked = score / coinsPerScore
            if banked > 0 { gameState.addCoins(banked) }
            gameState.recordPinballScore(score)   // leaderboard + new-best bonus
            AnalyticsClient.shared.track(
                "pinball_game_over",
                properties: ["score": .int(score),
                             "coins": .int(banked),
                             "map_name": .string(PinballMaps.maps[mapIndex % PinballMaps.maps.count].name)]
            )
            if gameState.hapticsEnabled { Haptics.success() }
        }
    }

    // MARK: - Input

    private func handleTap(at p: CGPoint) {
        if isOver { return }
        if !started {
            started = true
            AnalyticsClient.shared.track(
                "pinball_game_started",
                properties: ["map_name": .string(PinballMaps.maps[mapIndex % PinballMaps.maps.count].name)]
            )
            launchBall()
            return
        }
        if !ballInPlay { launchBall(); return }
        if p.x < field.midX { flick(isLeft: true) } else { flick(isLeft: false) }
    }

    private func flick(isLeft: Bool) {
        if isLeft { leftFlickTicks = flickDuration } else { rightFlickTicks = flickDuration }
        if gameState.hapticsEnabled { Haptics.soft() }
    }

    // MARK: - Flipper geometry

    private func currentTip(isLeft: Bool) -> CGPoint {
        let ticks = isLeft ? leftFlickTicks : rightFlickTicks
        let frac = CGFloat(ticks) / CGFloat(flickDuration)
        return flipperTip(isLeft: isLeft, frac: frac)
    }

    private func flipperTip(isLeft: Bool, frac: CGFloat) -> CGPoint {
        let pivot = isLeft ? leftPivot : rightPivot
        let restA = restAngleDeg * .pi / 180
        let actA  = activeAngleDeg * .pi / 180
        let ang = restA + (actA - restA) * frac
        let dx = cos(ang) * flipperLen * (isLeft ? 1 : -1)
        let dy = sin(ang) * flipperLen
        return CGPoint(x: pivot.x + dx, y: pivot.y + dy)
    }

    // MARK: - Simulation

    private func tick() {
        localTick &+= 1
        guard started, !isOver, field.width > 0 else { return }

        if leftFlickTicks > 0  { leftFlickTicks -= 1 }
        if rightFlickTicks > 0 { rightFlickTicks -= 1 }
        for i in bumpers.indices where bumpers[i].litTicks > 0 { bumpers[i].litTicks -= 1 }
        if leftSling.litTicks > 0  { leftSling.litTicks -= 1 }
        if rightSling.litTicks > 0 { rightSling.litTicks -= 1 }
        for i in targets.indices where targets[i].litTicks > 0 { targets[i].litTicks -= 1 }

        guard ballInPlay else { return }
        let dt: CGFloat = 1.0 / 60.0

        // Gravity + the curved lane top that feeds the ball into play.
        ball.vel.dy += gravity * dt
        if ball.pos.x > dividerX && ball.pos.y < dividerTopY {
            ball.vel.dx -= curvePush * dt
        }
        ball.vel.dx *= drag
        ball.vel.dy *= drag

        let sp = hypot(ball.vel.dx, ball.vel.dy)
        if sp > maxSpeed { let k = maxSpeed / sp; ball.vel.dx *= k; ball.vel.dy *= k }

        ball.pos.x += ball.vel.dx * dt
        ball.pos.y += ball.vel.dy * dt

        collideWalls()
        collideDivider()
        collideBumpers()
        collideSlings()
        collideTargets()
        collideFlipper(isLeft: true)
        collideFlipper(isLeft: false)

        if ball.pos.y - ballRadius > field.maxY { loseBall() }
    }

    private func collideWalls() {
        let r = ballRadius
        if ball.pos.x < field.minX + r {
            ball.pos.x = field.minX + r; ball.vel.dx = abs(ball.vel.dx) * wallBounce
        } else if ball.pos.x > field.maxX - r {
            ball.pos.x = field.maxX - r; ball.vel.dx = -abs(ball.vel.dx) * wallBounce
        }
        if ball.pos.y < field.minY + r {
            ball.pos.y = field.minY + r; ball.vel.dy = abs(ball.vel.dy) * wallBounce
        }
    }

    /// One-way-ish lane wall: keeps the launching ball in the lane until it
    /// clears the top, then keeps it in the playfield once it's crossed over.
    private func collideDivider() {
        guard ball.pos.y > dividerTopY else { return }
        let r = ballRadius
        let d = ball.pos.x - dividerX
        guard abs(d) < r else { return }
        if d >= 0 {
            ball.pos.x = dividerX + r; ball.vel.dx = abs(ball.vel.dx) * wallBounce
        } else {
            ball.pos.x = dividerX - r; ball.vel.dx = -abs(ball.vel.dx) * wallBounce
        }
    }

    /// Ball-vs-bumper overlap resolution.  O(n) in bumper count — see
    /// `PinballMap` doc comment for the ≤ 8 cap rationale.
    private func collideBumpers() {
        let r = ballRadius
        for i in bumpers.indices {
            let dx = ball.pos.x - bumpers[i].pos.x
            let dy = ball.pos.y - bumpers[i].pos.y
            let dist = hypot(dx, dy)
            let minD = r + bumperRadius
            guard dist > 0, dist < minD else { continue }
            let nx = dx / dist, ny = dy / dist
            ball.pos.x = bumpers[i].pos.x + nx * minD
            ball.pos.y = bumpers[i].pos.y + ny * minD
            let vn = ball.vel.dx * nx + ball.vel.dy * ny
            if vn < 0 {
                ball.vel.dx -= (1 + bumperRest) * vn * nx
                ball.vel.dy -= (1 + bumperRest) * vn * ny
            }
            let sp = hypot(ball.vel.dx, ball.vel.dy)
            if sp < bumperPop {
                let k = bumperPop / max(sp, 0.001)
                ball.vel.dx *= k; ball.vel.dy *= k
            }
            score += bumperScore * multiplier
            bumpers[i].litTicks = 12
            if gameState.hapticsEnabled { Haptics.light() }
        }
    }

    /// Slingshots — angled kickers that actively throw the ball back into play.
    private func collideSlings() {
        collideSling(&leftSling)
        collideSling(&rightSling)
    }

    private func collideSling(_ s: inout Sling) {
        let a = s.a, b = s.b
        let vx = b.x - a.x, vy = b.y - a.y
        let len2 = vx * vx + vy * vy
        guard len2 > 0 else { return }
        let wx = ball.pos.x - a.x, wy = ball.pos.y - a.y
        let t = max(0, min(1, (wx * vx + wy * vy) / len2))
        let qx = a.x + t * vx, qy = a.y + t * vy
        let dx = ball.pos.x - qx, dy = ball.pos.y - qy
        let dist = hypot(dx, dy)
        let minD = ballRadius + slingThickness
        guard dist > 0, dist < minD else { return }
        let nx = dx / dist, ny = dy / dist
        ball.pos.x = qx + nx * minD
        ball.pos.y = qy + ny * minD
        let vn = ball.vel.dx * nx + ball.vel.dy * ny
        if vn < 0 {
            ball.vel.dx -= (1 + slingRest) * vn * nx
            ball.vel.dy -= (1 + slingRest) * vn * ny
        }
        // Active pop — kicks the ball off the face every time it touches.
        ball.vel.dx += nx * slingPop
        ball.vel.dy += ny * slingPop
        score += slingScore * multiplier
        s.litTicks = 10
        if gameState.hapticsEnabled { Haptics.light() }
    }

    /// Drop targets — light one per hit; clearing the whole bank bumps the
    /// multiplier, pays a bonus, and resets the bank for another go.
    private func collideTargets() {
        for i in targets.indices {
            let rect = targets[i].rect
            let cxp = min(max(ball.pos.x, rect.minX), rect.maxX)
            let cyp = min(max(ball.pos.y, rect.minY), rect.maxY)
            let dx = ball.pos.x - cxp, dy = ball.pos.y - cyp
            let dist = hypot(dx, dy)
            guard dist < ballRadius else { continue }
            let nx = dist > 0 ? dx / dist : 0
            let ny = dist > 0 ? dy / dist : -1
            ball.pos.x = cxp + nx * ballRadius
            ball.pos.y = cyp + ny * ballRadius
            let vn = ball.vel.dx * nx + ball.vel.dy * ny
            if vn < 0 {
                ball.vel.dx -= 1.6 * vn * nx
                ball.vel.dy -= 1.6 * vn * ny
            }
            targets[i].litTicks = 10
            guard !targets[i].lit else { continue }
            targets[i].lit = true
            score += targetScore * multiplier
            if targets.allSatisfy({ $0.lit }) {
                multiplier = min(multiplier + 1, maxMultiplier)
                score += bankBonus * multiplier
                for j in targets.indices { targets[j].lit = false }
            }
            if gameState.hapticsEnabled { Haptics.light() }
        }
    }

    /// Closest-point-on-segment collision against a flipper, plus a launch
    /// impulse along the contact normal while the flipper is mid-flick.
    private func collideFlipper(isLeft: Bool) {
        let pivot = isLeft ? leftPivot : rightPivot
        let tip = currentTip(isLeft: isLeft)
        let vx = tip.x - pivot.x, vy = tip.y - pivot.y
        let wx = ball.pos.x - pivot.x, wy = ball.pos.y - pivot.y
        let len2 = vx * vx + vy * vy
        let t = len2 > 0 ? max(0, min(1, (wx * vx + wy * vy) / len2)) : 0
        let qx = pivot.x + t * vx, qy = pivot.y + t * vy
        let dx = ball.pos.x - qx, dy = ball.pos.y - qy
        let dist = hypot(dx, dy)
        let minD = ballRadius + flipperHitThickness
        guard dist < minD else { return }

        let active = (isLeft ? leftFlickTicks : rightFlickTicks) > 0

        // Standard contact normal (segment → ball).
        let snx = dist > 0 ? dx / dist : 0
        let sny = dist > 0 ? dy / dist : -1
        // The bat's UP normal — perpendicular to the flipper, pointing into the
        // playfield.  While flicking we ALWAYS resolve the ball to this top side
        // so it launches up, never spiked down off the underside (the old bug).
        let segLen = max(0.001, hypot(vx, vy))
        var unx = -vy / segLen, uny = vx / segLen
        if uny > 0 { unx = -unx; uny = -uny }

        let nx = active ? unx : snx
        let ny = active ? uny : sny
        ball.pos.x = qx + nx * minD
        ball.pos.y = qy + ny * minD

        let vn = ball.vel.dx * nx + ball.vel.dy * ny
        if vn < 0 {
            ball.vel.dx -= (1 + flipperRest) * vn * nx
            ball.vel.dy -= (1 + flipperRest) * vn * ny
        }

        if active {
            // The kick = the swinging bat's surface speed at the contact point,
            // directed up.  ω = swing angle / swing time; further out = harder.
            let restA = restAngleDeg * .pi / 180
            let actA  = activeAngleDeg * .pi / 180
            let omega = abs(actA - restA) / (CGFloat(flickDuration) * (1.0 / 60.0))
            let kick  = omega * (t * flipperLen) * flickGain
            ball.vel.dx += unx * kick
            ball.vel.dy += uny * kick
        }
    }
}

#Preview {
    NavigationStack {
        PinballView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
