import SwiftUI

// ---------------------------------------------------------------------------
// HomeRoute — destinations reachable from the home screen.
// Used as the value type for NavigationStack(path:).
// ---------------------------------------------------------------------------
enum HomeRoute: Hashable {
    case game
    case levels
    case settings
    case shop
}

// ---------------------------------------------------------------------------
// Navigator — shared navigation state.  Injected via environmentObject so
// any descendant view (BallGameView's Home / Levels buttons, win overlay's
// Levels button, etc.) can drive the path without callback plumbing.
// ---------------------------------------------------------------------------
@MainActor
final class Navigator: ObservableObject {
    @Published var path: [HomeRoute] = []

    /// Pop all the way back to the home screen.
    func goHome() {
        path = []
    }

    /// Replace the current stack with [levels] so the user lands on the
    /// Levels grid even if they were inside a game.
    func goToLevels() {
        path = [.levels]
    }

    /// Push the game on top of whatever is currently showing.
    func goToGame() {
        if path.last != .game { path.append(.game) }
    }

    /// Push Settings on top of the current stack.
    func goToSettings() {
        if path.last != .settings { path.append(.settings) }
    }

    /// Push the Cosmetic Shop on top of the current stack.
    func goToShop() {
        if path.last != .shop { path.append(.shop) }
    }
}

struct HomeView: View {
    @EnvironmentObject var gameState: GameState
    @StateObject private var nav    = Navigator()
    @StateObject private var motion = BallMotion()   // same class used in BallGameView
    @StateObject private var clock  = PhysicsClock()

    // Live-physics ball state
    @State private var ballPos:   CGPoint = .zero
    @State private var ballVel:   CGVector = .zero
    @State private var arenaSize: CGSize   = .zero
    @State private var spawned:   Bool     = false

    private let ballRadius: CGFloat = 51   // 120 * 0.85 / 2  (15% smaller)

    var body: some View {
        NavigationStack(path: $nav.path) {
            ZStack {
                background

                VStack(spacing: 0) {
                    Spacer().frame(height: 90)

                    greeting

                    titleText
                        .padding(.bottom, 20)

                    // ── Live physics arena ──────────────────────────────────
                    GeometryReader { geo in
                        ZStack {
                            // Forces the ZStack to fill the GeometryReader.
                            // Without this the ZStack collapsed to the ball's
                            // 102×102 frame and ballPos coords were wrong,
                            // pinning the ball off the left edge of the screen.
                            Color.clear

                            liveBall
                                .position(ballPos)
                        }
                        .contentShape(Rectangle())
                        .onAppear {
                            arenaSize = geo.size
                            respawnBall(in: geo.size)
                            spawned = true
                        }
                        .onChange(of: geo.size) { _, newSize in
                            arenaSize = newSize
                            if !spawned {
                                respawnBall(in: newSize)
                                spawned = true
                            }
                        }
                        // Tap anywhere in the arena to respawn ball at centre
                        .onTapGesture {
                            respawnBall(in: arenaSize)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    playButton
                        .padding(.horizontal, 40)
                        .padding(.bottom, 14)

                    HStack(spacing: 28) {
                        NavigationLink(value: HomeRoute.levels) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.3x3.fill")
                                    .font(.system(size: 14))
                                Text("Levels")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(Color(white: 0.5))
                        }
                        NavigationLink(value: HomeRoute.settings) {
                            HStack(spacing: 6) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 14))
                                Text("Settings")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(Color(white: 0.5))
                        }
                    }

                    Spacer().frame(height: 48)
                }

                // Coin balance pill — top-right, always visible (except
                // during the onboarding overlay).
                if gameState.seenOnboarding {
                    coinBalancePill
                    livesMarblePill
                }

                // First-launch onboarding overlay
                if !gameState.seenOnboarding {
                    onboardingOverlay
                        .transition(.opacity)
                }
            }
            .onReceive(clock.$tickCount) { _ in tickBall() }
            .onAppear    { motion.start(); clock.start() }
            .onDisappear { motion.stop();  clock.stop()  }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .game:     BallGameView()
                case .levels:   LevelSelectView()
                case .settings: SettingsView()
                case .shop:     CosmeticShopView()
                }
            }
        }
        .environmentObject(nav)
    }

    // MARK: - Onboarding overlay

    private var onboardingOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Tilting-phone visual cue
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(white: 0.78)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating)

                VStack(spacing: 14) {
                    Text("Tilt to roll")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Tilt your phone in any direction\nto roll the ball.\nReach the rainbow to clear the level.")
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.78))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer()

                Button {
                    dismissOnboarding(via: "button")
                } label: {
                    Text("Got it")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 56)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.white)
                        )
                }
                .padding(.bottom, 60)
            }
            .padding(.horizontal, 32)
        }
        // Tap anywhere also dismisses, for users who skip the button
        .contentShape(Rectangle())
        .onTapGesture {
            dismissOnboarding(via: "background_tap")
        }
    }

    private func dismissOnboarding(via source: String) {
        AnalyticsClient.shared.track(
            "onboarding_dismissed",
            properties: ["source": .string(source)]
        )
        withAnimation(.easeInOut(duration: 0.32)) {
            gameState.seenOnboarding = true
        }
    }

    // MARK: - Physics

    /// Always place the ball at arena centre and reset velocity.
    private func respawnBall(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        ballPos = CGPoint(x: size.width / 2, y: size.height / 2)
        ballVel = .zero
    }

    private func tickBall() {
        let r = ballRadius
        // Need an arena large enough to contain the ball.
        guard arenaSize.width >= 2 * r, arenaSize.height >= 2 * r else { return }
        let dt: CGFloat = 1.0 / 60.0

        ballVel.dx += CGFloat(motion.gravity.x) * 1_400 * dt
        ballVel.dy += CGFloat(motion.gravity.y) * 1_400 * dt
        ballVel.dx *= 0.985
        ballVel.dy *= 0.985

        if motion.gravity == .zero && hypot(ballVel.dx, ballVel.dy) < 5 {
            ballVel = .zero
        }

        ballPos.x += ballVel.dx * dt
        ballPos.y += ballVel.dy * dt

        // Wall bounces (elastic with energy loss)
        if ballPos.x < r                    { ballPos.x = r;                    ballVel.dx = -ballVel.dx * 0.65 }
        if ballPos.x > arenaSize.width  - r { ballPos.x = arenaSize.width  - r; ballVel.dx = -ballVel.dx * 0.65 }
        if ballPos.y < r                    { ballPos.y = r;                    ballVel.dy = -ballVel.dy * 0.65 }
        if ballPos.y > arenaSize.height - r { ballPos.y = arenaSize.height - r; ballVel.dy = -ballVel.dy * 0.65 }

        // Hard safety clamp — guarantees the ball can never escape the arena
        ballPos.x = min(max(ballPos.x, r), arenaSize.width  - r)
        ballPos.y = min(max(ballPos.y, r), arenaSize.height - r)
    }

    // MARK: - Sub-views

    private var background: some View {
        LinearGradient(
            colors: [Color(white: 0.06), Color(white: 0.13)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var greeting: some View {
        if !gameState.playerName.isEmpty {
            Text("Welcome back, \(gameState.playerName)!")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.55))
                .padding(.bottom, 12)
        }
    }

    private var titleText: some View {
        Text("Roll Along")
            .font(.system(size: 52, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(colors: [.white, Color(white: 0.82)],
                               startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
    }

    /// Floating coin-balance pill in the top-right corner.  Tappable —
    /// opens the Cosmetic Shop.  Uses the Navigator so the home path
    /// becomes [.shop].
    private var coinBalancePill: some View {
        VStack {
            HStack {
                Spacer()
                Button { nav.goToShop() } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.00, green: 0.88, blue: 0.40),
                                        Color(red: 0.93, green: 0.65, blue: 0.10),
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.6)
                            )
                            .frame(width: 14, height: 14)

                        Text("\(gameState.coinBalance)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(gameState.coinBalance)))
                            .animation(.easeInOut(duration: 0.4), value: gameState.coinBalance)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.14))
                            .overlay(
                                Capsule().stroke(Color(white: 0.28), lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(gameState.coinBalance) coins")
                .accessibilityHint("Opens the cosmetic shop.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    /// Floating lives indicator in the top-LEFT corner — mirrors the
    /// in-game HUD spec: 6 red marbles always rendered; filled = lives
    /// you currently have, outlined = empty slots.  Stockpiled lives
    /// past 6 show as "+N" to the right; unlimited-lives subscribers
    /// see 6 gold marbles + an infinity glyph.
    ///
    /// Wrapped in a TimelineView so the "next life in M:SS" countdown
    /// ticks every second and the marble count refreshes when regen
    /// commits.
    private var livesMarblePill: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let unlimited     = gameState.unlimitedLives
            let display       = gameState.displayedLives
            let filledMarbles = unlimited ? GameState.livesMax : min(display, GameState.livesMax)
            let stockpile     = unlimited ? 0 : max(0, display - GameState.livesMax)

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            ForEach(0..<GameState.livesMax, id: \.self) { i in
                                marbleIcon(filled: i < filledMarbles, gold: unlimited)
                            }
                            if unlimited {
                                Image(systemName: "infinity")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Self.goldLifeGradient)
                                    .padding(.leading, 2)
                            } else if stockpile > 0 {
                                Text("+\(stockpile)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.leading, 2)
                            }
                        }
                        if let countdown = gameState.timeToNextLife() {
                            Text("+1 in \(Self.formatCountdown(countdown))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(white: 0.50))
                        }
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 18)
            .padding(.top, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(livesAccessibilityLabel)
        }
    }

    /// One marble slot — fills red (or gold for unlimited) when the slot
    /// is occupied, hollow grey outline when empty.  Matches the in-game
    /// HUD so the two reads consistently across menu and gameplay.
    @ViewBuilder
    private func marbleIcon(filled: Bool, gold: Bool) -> some View {
        if filled {
            Circle()
                .fill(gold ? Self.goldLifeGradient : Self.redLifeGradient)
                .frame(width: 13, height: 13)
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 4, height: 4)
                        .offset(x: -2.5, y: -2.5)
                )
                .overlay(
                    Circle().stroke(Color.black.opacity(0.40), lineWidth: 0.6)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 1.5, y: 1)
        } else {
            Circle()
                .stroke(Color(white: 0.40).opacity(0.7), lineWidth: 0.9)
                .frame(width: 13, height: 13)
        }
    }

    private var livesAccessibilityLabel: String {
        if gameState.unlimitedLives {
            return "Unlimited lives."
        }
        let display    = gameState.displayedLives
        let filled     = min(display, GameState.livesMax)
        let stockpile  = max(0, display - GameState.livesMax)
        var label = "\(filled) of \(GameState.livesMax) lives."
        if stockpile > 0 {
            label += " Plus \(stockpile) stockpiled."
        }
        if let next = gameState.timeToNextLife() {
            label += " Next life in \(Self.formatCountdown(next))."
        }
        return label
    }

    private static let redLifeGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.32, blue: 0.32),
            Color(red: 0.78, green: 0.14, blue: 0.14),
        ],
        startPoint: .top, endPoint: .bottom
    )
    private static let goldLifeGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.86, blue: 0.36),
            Color(red: 0.93, green: 0.65, blue: 0.10),
        ],
        startPoint: .top, endPoint: .bottom
    )

    private static func formatCountdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(ceil(seconds)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var liveBall: some View {
        Circle()
            .fill(gameState.activeSkin.gradient(endRadius: ballRadius * 1.4))
            .frame(width: ballRadius * 2, height: ballRadius * 2)
            .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.65), radius: 14, x: 3, y: 9)
    }

    // ── AI gradient Play button ─────────────────────────────────────────────
    private var playButton: some View {
        NavigationLink(value: HomeRoute.game) {
            playButtonBody
        }
        .accessibilityLabel("Play Level \(gameState.currentLevel)")
        .accessibilityHint("Starts the next unlocked level.")
    }

    private var playButtonBody: some View {
        ZStack {
            // Shifting AI gradient background
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    aiButtonBackground(ctx: ctx, size: size,
                                       t: tl.date.timeIntervalSinceReferenceDate)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // Bold black label
            VStack(spacing: 2) {
                Text("Play")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Level \(gameState.currentLevel)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .opacity(0.65)
            }
            .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .shadow(color: .white.opacity(0.22), radius: 12, y: 4)
    }

    // Shifting colour blobs + white sparkle accents — liquid "AI" gradient
    private func aiButtonBackground(ctx: GraphicsContext, size: CGSize, t: Double) {
        // ── White base ──────────────────────────────────────────────────────
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
            with: .color(Color(white: 0.97))
        )

        // ── Five slow-drifting colour blobs ─────────────────────────────────
        // (xSeed, ySeed, hueSeed, driftSpeed)
        let blobs: [(Double, Double, Double, Double)] = [
            (0.0, 0.0, 0.72, 0.18),   // violet-purple
            (1.9, 2.7, 0.57, 0.15),   // cobalt blue
            (3.5, 1.1, 0.47, 0.22),   // cyan-teal
            (5.2, 4.0, 0.87, 0.19),   // hot pink
            (2.4, 5.8, 0.10, 0.16),   // warm gold
        ]

        let blobR = size.width * 0.58

        for (xSeed, ySeed, hueSeed, speed) in blobs {
            let bx = size.width  * CGFloat(0.5 + 0.48 * sin(t * speed        + xSeed))
            let by = size.height * CGFloat(0.5 + 0.48 * sin(t * speed * 1.41 + ySeed))
            let hue = (hueSeed + t * 0.045).truncatingRemainder(dividingBy: 1.0)
            let color = Color(hue: hue, saturation: 0.82, brightness: 1.0)

            ctx.fill(
                Path(ellipseIn: CGRect(x: bx - blobR, y: by - blobR,
                                       width: blobR * 2, height: blobR * 2)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(0.62), .clear]),
                    center: CGPoint(x: bx, y: by),
                    startRadius: 0,
                    endRadius: blobR
                )
            )
        }

        // ── White sparkle accents ───────────────────────────────────────────
        let sparkCount = 22
        for i in 0..<sparkCount {
            let seed  = Double(i)
            let phase = seed / Double(sparkCount)

            let px = size.width  * CGFloat(0.04 + 0.92 * (0.5 + 0.5 * sin(t * (0.19 + seed * 0.06) + seed * 2.1)))
            let py = size.height * CGFloat(0.08 + 0.84 * (0.5 + 0.5 * sin(t * (0.15 + seed * 0.05) + seed * 1.7)))
            let pCtr = CGPoint(x: px, y: py)

            let freq    = 2.4 + (seed.truncatingRemainder(dividingBy: 7)) * 0.55
            let raw     = (sin(t * freq + phase * .pi * 4) + 1) / 2
            let twinkle = pow(raw, 2.5)

            let pR    = CGFloat(0.7 + twinkle * 2.8)
            let alpha = 0.25 + twinkle * 0.75

            // Soft white glow
            let gR = pR * 3.0
            ctx.fill(
                Path(ellipseIn: CGRect(x: px - gR, y: py - gR, width: gR * 2, height: gR * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(alpha * 0.35), .clear]),
                    center: pCtr, startRadius: 0, endRadius: gR
                )
            )

            // Bright white core
            ctx.fill(
                Path(ellipseIn: CGRect(x: px - pR, y: py - pR, width: pR * 2, height: pR * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(alpha), Color.white.opacity(0)]),
                    center: pCtr, startRadius: 0, endRadius: pR
                )
            )

            // Sparkle cross at peak brightness
            if twinkle > 0.68 {
                let intensity = CGFloat((twinkle - 0.68) / 0.32)
                let arm  = pR * 2.0 * intensity
                let stem = CGFloat(0.65)
                ctx.fill(Path(CGRect(x: px - arm,    y: py - stem / 2, width: arm * 2, height: stem)),
                         with: .color(Color.white.opacity(Double(intensity) * 0.88)))
                ctx.fill(Path(CGRect(x: px - stem / 2, y: py - arm,    width: stem, height: arm * 2)),
                         with: .color(Color.white.opacity(Double(intensity) * 0.88)))
            }
        }

        // ── Top gloss strip — subtle depth ──────────────────────────────────
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.45)),
            with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.28), .clear]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint:   CGPoint(x: 0, y: size.height * 0.45)
            )
        )
    }
}

#Preview {
    HomeView().environmentObject(GameState())
}
