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
    case leaderboard
    case friends
    case clans
    case games
    /// Launch an alternate game mode by its GameModeCatalogue id (e.g. "zen").
    /// The climb uses `.game`; this carries the id so one route serves every
    /// non-climb mode as the modes hub grows.
    case mode(String)
    case profile
    case challengeTracks
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

    /// Push the global Leaderboard on top of the current stack.
    func goToLeaderboard() {
        if path.last != .leaderboard { path.append(.leaderboard) }
    }

    /// Push the Friends screen on top of the current stack.
    func goToFriends() {
        if path.last != .friends { path.append(.friends) }
    }

    /// Push the Clans screen on top of the current stack.
    func goToClans() {
        if path.last != .clans { path.append(.clans) }
    }

    /// Push the Game Menu (all non-climb modes) on top of the current stack.
    func goToGames() {
        if path.last != .games { path.append(.games) }
    }

    /// Push the Profile screen on top of the current stack.
    func goToProfile() {
        if path.last != .profile { path.append(.profile) }
    }

    /// Push the Challenge Tracks selection screen.
    func goToTracks() {
        if path.last != .challengeTracks { path.append(.challengeTracks) }
    }
}

struct HomeView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var ads:       AdManager
    @StateObject private var nav    = Navigator()
    @StateObject private var motion = BallMotion()   // same class used in BallGameView
    @StateObject private var clock  = PhysicsClock()

    // Live-physics ball state
    @State private var ballPos:   CGPoint = .zero
    @State private var ballVel:   CGVector = .zero
    @State private var arenaSize: CGSize   = .zero
    @State private var spawned:   Bool     = false

    /// Recent ball positions for the home-screen trail.  Mirrors the
    /// in-game trail mechanic — only populated when the player has a
    /// non-`.none` TrailColor equipped.
    @State private var trailPoints: [CGPoint] = []
    private let homeTrailMaxLength = 120        // ~2.0s at 60fps — doubled so the streak reads across the full-screen arena
    private let homeTrailMinStep:  CGFloat = 1.5

    /// Hue assigned to `trailPoints[0]` (the visible tail end).  Each
    /// later segment's hue is `offset + i * homeTrailHueStep mod 1`,
    /// so once a position is coloured, its hue stays put — the
    /// spectrum follows the ball rather than redistributing across
    /// the current segment count.  When segments fall off the tail
    /// we advance this offset by `removed × step` so the surviving
    /// segments keep their original hues.
    @State private var trailHueOffset: Double = 0.0

    /// Frames (in the arena coordinate space) of every UI element the
    /// free-roaming ball bounces off — reported by `.homeBallCollider()`
    /// on the title, buttons, and pills; consumed each tick.
    @State private var colliders: [CGRect] = []

    /// One full ROYGBIV cycle every `homeTrailMaxLength` segments.
    /// At less than full length the trail covers a partial slice of
    /// the spectrum; at full length it shows the whole rainbow.
    private var homeTrailHueStep: Double { 1.0 / Double(homeTrailMaxLength) }

    // Lives sheet (top-left pill → BuyLivesSheet, which also serves as
    // the "lives status / explanation" screen).
    @State private var showBuyLivesSheet: Bool = false

    // Daily-reward sheet — the gift pill opens it, and it auto-presents once
    // per launch when a reward is unclaimed.  `autoPresentedDaily` guards the
    // auto-pop so popping back from a sub-screen doesn't re-open it.
    @State private var showDailyRewardSheet: Bool = false
    @State private var autoPresentedDaily: Bool = false

    // Starter Pack sheet — shown once automatically when coinBalance first
    // reaches 50.  Also shown on re-launch while the 48-hour window is open.
    @State private var showStarterPackSheet: Bool = false

    private let ballRadius: CGFloat = 42   // a touch smaller than before — leaves room for the trail to read behind the ball

    /// Named coordinate space the collider frames are reported in — owned by
    /// the root ZStack, which the ball's GeometryReader fills exactly, so
    /// collider rects and `ballPos` share one origin.
    static let arenaSpaceName = "homeArena"

    var body: some View {
        NavigationStack(path: $nav.path) {
            ZStack {
                background

                // ── Live physics layer — the ball roams the WHOLE screen ────
                // Sits under every UI element; the UI reports its frames via
                // HomeColliderKey and tickBall() bounces the ball off them,
                // so the ball can roll anywhere and caroms off the title,
                // buttons, pills, and screen edges.
                GeometryReader { geo in
                    ZStack {
                        // Forces the ZStack to fill the GeometryReader.
                        // Without this the ZStack collapsed to the ball's
                        // frame and ballPos coords were wrong, pinning
                        // the ball off the left edge of the screen.
                        Color.clear

                        // Equipped trail — same rendering rules as the
                        // in-game trail (segment opacity ramps from
                        // 0.10 at the tail to 1.0 at the head;
                        // `.rainbow` gets a per-segment hue cycle).
                        if gameState.equippedTrail != .none {
                            homeTrailLayer
                                .allowsHitTesting(false)
                        }

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
                    // Tap any open space to respawn the ball at centre —
                    // buttons sit above this layer and keep their taps.
                    .onTapGesture {
                        respawnBall(in: arenaSize)
                    }
                }

                VStack(spacing: 0) {
                    // Hug the top pills — the greeting + title sit right
                    // below the lives / coins indicators.
                    Spacer().frame(height: 48)

                    greeting
                        .homeBallCollider()

                    titleText
                        .homeBallCollider()
                        .padding(.bottom, 20)

                    // Open roaming space — the ball lives on the layer behind.
                    Spacer()

                    // Game Modes sits ABOVE Play.  The capsule is narrow and
                    // centred, so the ball can roll down past it on either
                    // side (each gap is wider than the ball) — but never
                    // through it: it's a collider like every other control.
                    // One tap to every non-climb experience — Zen Garden,
                    // Coin Pit, and the competitive modes as they come online.
                    NavigationLink(value: HomeRoute.games) {
                        HStack(spacing: 8) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 15))
                            Text("Game Modes")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color(white: 0.85))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 11)
                        .background(
                            Capsule()
                                .fill(Color(white: 0.14))
                                .overlay(Capsule().stroke(Color(white: 0.28), lineWidth: 0.8))
                        )
                    }
                    // Identifier FIRST so it attaches straight to the link —
                    // the smoke test queries app.buttons["GameModesButton"],
                    // and interposing the collider background can re-target
                    // which accessibility element receives the identifier.
                    .accessibilityIdentifier("GameModesButton")  // UI smoke test
                    .homeBallCollider()
                    .padding(.bottom, 12)

                    playButton
                        .homeBallCollider()
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)

                    // Five square, icon-only buttons hugging the bottom edge.
                    // Equal slots via maxWidth so the spacing is uniform on
                    // every device width.
                    HStack(spacing: 0) {
                        squareNavButton("trophy.fill",    "Ranks",    HomeRoute.leaderboard)
                        squareNavButton("person.3.fill",  "Clans",    HomeRoute.clans)
                        squareNavButton("person.2.fill",  "Friends",  HomeRoute.friends)
                        squareNavButton("person.fill",    "Profile",  HomeRoute.profile)
                        squareNavButton("gearshape.fill", "Settings", HomeRoute.settings)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }

                // Coin balance pill — top-right, always visible (except
                // during the onboarding overlay).
                if gameState.seenOnboarding {
                    coinBalancePill
                    livesMarblePill
                    dailyRewardPill
                }

                // First-launch onboarding overlay
                if !gameState.seenOnboarding {
                    onboardingOverlay
                        .transition(.opacity)
                }
            }
            .accessibilityIdentifier("HomeView")  // UI smoke test anchor
            .coordinateSpace(name: Self.arenaSpaceName)
            .onPreferenceChange(HomeColliderKey.self) { rects in
                // Drop degenerate frames — e.g. the greeting collapses to
                // zero when no player name is set — so they can't act as
                // invisible point obstacles.
                colliders = rects.filter { $0.width > 1 && $0.height > 1 }
            }
            .onReceive(clock.$tickCount) { _ in tickBall() }
            .onAppear    { motion.start(); clock.start(); maybeAutoPresentDailyReward() }
            .onDisappear { motion.stop();  clock.stop()  }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .game:        BallGameView()
                case .levels:      LevelSelectView()
                case .settings:    SettingsView()
                case .shop:        CosmeticShopView()
                case .leaderboard: LeaderboardView()
                case .friends:     FriendsView()
                case .clans:       ClansView()
                case .games:       GameMenuView()
                case .mode("snake"):
                    SnakeGameView()
                        .onAppear { AnalyticsClient.shared.track("minigame_entered", properties: ["game_mode": .string("snake")]) }
                case .mode("sumo"):
                    SumoSurvivalView()
                        .onAppear { AnalyticsClient.shared.track("minigame_entered", properties: ["game_mode": .string("sumo")]) }
                case .mode("paintball"):
                    PaintBallView()
                        .onAppear { AnalyticsClient.shared.track("minigame_entered", properties: ["game_mode": .string("paintball")]) }
                case .mode("goldrush"):
                    GoldRushView()
                        .onAppear { AnalyticsClient.shared.track("minigame_entered", properties: ["game_mode": .string("goldrush")]) }
                case .mode("marblecup"):
                    MarbleCupView()
                        .onAppear { AnalyticsClient.shared.track("minigame_entered", properties: ["game_mode": .string("marblecup")]) }
                case .mode("koth"):
                    KingOfTheHillView()
                        .onAppear { AnalyticsClient.shared.track("minigame_entered", properties: ["game_mode": .string("koth")]) }
                case .mode("pinball"):
                    PinballView()
                        .onAppear { AnalyticsClient.shared.track("minigame_entered", properties: ["game_mode": .string("pinball")]) }
                case .profile:          ProfileView()
                case .challengeTracks:  ChallengeTrackSelectView()
                case .mode(let id):
                    BallGameView(activeMode: GameModeCatalogue.mode(id: id)
                                 ?? GameModeCatalogue.climb)
                }
            }
            // Sheet driven by tapping the top-left lives pill.  Re-uses
            // the existing BuyLivesSheet (which itself has been extended
            // with a regen-countdown + "1 life per 6 min" explanation
            // block in its header).
            .sheet(isPresented: $showBuyLivesSheet) {
                BuyLivesSheet()
                    .environmentObject(gameState)
            }
            .sheet(isPresented: $showDailyRewardSheet) {
                DailyRewardView()
                    .environmentObject(gameState)
            }
            .sheet(isPresented: $showStarterPackSheet) {
                StarterPackSheet()
                    .environmentObject(gameState)
                    .environmentObject(StoreKitManager.shared)
            }
            // Auto-present the Starter Pack sheet the first time coinBalance
            // reaches 50 (trigger fires once and is never re-armed).
            // On re-launch, also re-present while the 48-hour window is still
            // open.  The `showStarterPackSheet` guard prevents a double-pop
            // when dailyReward fires at the same moment.
            .onChange(of: gameState.coinBalance) { _, _ in
                maybeAutoPresentStarterPack()
            }
            .onAppear {
                maybeAutoPresentStarterPack()
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
        // Request ATT now that the user has seen the app — fires the system
        // dialog on first launch only.  requestTracking() is a no-op on
        // subsequent launches (status already determined), but it's not called
        // from this path after the first launch anyway.
        Task { await ads.requestTracking() }
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
        trailPoints.removeAll(keepingCapacity: true)
        trailHueOffset = 0.0
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

        // Bounce off the on-screen UI — title, Play, Game Modes, the nav
        // squares, and the top pills all report their frames as colliders.
        for rect in colliders {
            resolveRectObstacle(pos: &ballPos, vel: &ballVel,
                                rect: rect, radius: r, restitution: 0.65)
        }

        // Hard safety clamp — guarantees the ball can never escape the arena
        ballPos.x = min(max(ballPos.x, r), arenaSize.width  - r)
        ballPos.y = min(max(ballPos.y, r), arenaSize.height - r)

        // Trail — append a new point only if the ball moved enough
        // since the last segment.  Skipped entirely when the player
        // has `.none` equipped (no trail to draw).
        if gameState.equippedTrail != .none {
            if let last = trailPoints.last {
                if hypot(ballPos.x - last.x, ballPos.y - last.y) > homeTrailMinStep {
                    trailPoints.append(ballPos)
                }
            } else {
                trailPoints.append(ballPos)
            }
            if trailPoints.count > homeTrailMaxLength {
                let removed = trailPoints.count - homeTrailMaxLength
                trailPoints.removeFirst(removed)
                // Advance the tail hue by exactly the number of
                // segments we dropped — every remaining segment
                // keeps its original colour.
                trailHueOffset = (trailHueOffset
                                  + Double(removed) * homeTrailHueStep)
                    .truncatingRemainder(dividingBy: 1.0)
            }
        } else if !trailPoints.isEmpty {
            // Player just switched to .none — clear any residual trail.
            trailPoints.removeAll(keepingCapacity: true)
            trailHueOffset = 0.0
        }
    }

    /// Trail render.  Opacity ramps from 0.10 at the tail to 1.0 at
    /// the head.  Rainbow trails use a stable per-segment hue baked
    /// in at creation (`trailHueOffset + i × step`) so each spot
    /// keeps its colour as the ball moves on — the spectrum follows
    /// the ball rather than redistributing across the active count.
    private var homeTrailLayer: some View {
        Canvas { ctx, _ in
            let n = trailPoints.count
            guard n >= 2 else { return }
            let isRainbow = gameState.equippedTrail == .rainbow
            let isAir     = gameState.equippedTrail == .air
            // Air trail — overall opacity decays as the streak grows
            // longer, matching the in-game air effect.
            let airDecay: Double = isAir
                ? max(0.10, 1.0 - Double(n) / Double(homeTrailMaxLength) * 0.85)
                : 1.0
            for i in 1..<n {
                let prev = trailPoints[i - 1]
                let curr = trailPoints[i]
                let age = Double(i) / Double(n - 1)
                let opacity = (0.10 + 0.90 * age) * airDecay
                var path = Path()
                path.move(to: prev)
                path.addLine(to: curr)
                let segmentColor: Color
                if isRainbow {
                    var hue = (trailHueOffset + Double(i) * homeTrailHueStep)
                        .truncatingRemainder(dividingBy: 1.0)
                    if hue < 0 { hue += 1.0 }
                    segmentColor = Color(hue: hue, saturation: 1.0, brightness: 1.0)
                } else {
                    segmentColor = gameState.equippedTrail.color
                }
                ctx.stroke(
                    path,
                    with: .color(segmentColor.opacity(opacity)),
                    style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    // MARK: - Sub-views

    /// One of the five square, icon-only nav buttons hugging the bottom
    /// edge (Ranks / Clans / Friends / Profile / Settings).  Equal-width
    /// slots (maxWidth: .infinity) keep the row evenly spaced on any
    /// device; the name is exposed to accessibility instead of drawn.
    private func squareNavButton(_ icon: String, _ label: String, _ route: HomeRoute) -> some View {
        NavigationLink(value: route) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(white: 0.75))
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(white: 0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(white: 0.26), lineWidth: 0.8)
                        )
                )
        }
        .homeBallCollider()
        .accessibilityLabel(label)
        .frame(maxWidth: .infinity)
    }

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
    // Gift pill — top-centre call-to-action shown only while a daily reward is
    // unclaimed.  Tapping opens DailyRewardView; it vanishes once claimed
    // (until tomorrow).  Auto-present covers first-glance discovery; this is
    // the re-entry affordance if the player dismissed the sheet.
    @ViewBuilder
    private var dailyRewardPill: some View {
        if gameState.dailyRewardAvailable {
            VStack {
                Button { showDailyRewardSheet = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.30))
                        Text("Daily Reward")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Circle()
                            .fill(Color(red: 1.0, green: 0.36, blue: 0.36))
                            .frame(width: 7, height: 7)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.14))
                            .overlay(Capsule().stroke(Color(red: 1.0, green: 0.82, blue: 0.30).opacity(0.5),
                                                      lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .homeBallCollider()
                .accessibilityLabel("Daily reward available")
                .accessibilityHint("Opens the daily reward.")
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    /// True when launched by the UI test runner (SmokeTests passes
    /// `--uitesting`).  Auto-presenting sheets are suppressed: a sheet
    /// hides the home screen's accessibility elements, so an auto-pop
    /// 0.5s after launch races the test's element queries and makes
    /// "GameModesButton not found" failures that have nothing to do
    /// with the navigation under test.
    private static let isUITesting = CommandLine.arguments.contains("--uitesting")

    /// Auto-present the daily-reward sheet the first time Home appears this
    /// launch — only when something's unclaimed and onboarding is done.  The
    /// short delay lets Home settle so the sheet animates in cleanly.
    private func maybeAutoPresentDailyReward() {
        guard !Self.isUITesting else { return }
        guard !autoPresentedDaily,
              gameState.seenOnboarding,
              gameState.dailyRewardAvailable else { return }
        autoPresentedDaily = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if gameState.dailyRewardAvailable { showDailyRewardSheet = true }
        }
    }

    /// Present the Starter Pack sheet when:
    ///   (a) coinBalance just crossed 50 for the first time (trigger fires once), OR
    ///   (b) the player re-opens the app while the 48-hour window is still live.
    /// Guards prevent double-pop or showing when another sheet is already visible.
    private func maybeAutoPresentStarterPack() {
        guard !Self.isUITesting else { return }
        guard gameState.seenOnboarding, !showStarterPackSheet else { return }

        if gameState.shouldTriggerStarterPack {
            // First trigger: stamp shownAt so the countdown starts now.
            gameState.starterPackShownAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard !showDailyRewardSheet else { return }
                showStarterPackSheet = true
            }
        } else if gameState.starterPackOfferActive {
            // Re-open within the 48-hour window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard !showDailyRewardSheet else { return }
                showStarterPackSheet = true
            }
        }
    }

    private var coinBalancePill: some View {
        VStack {
            HStack {
                Spacer()
                Button { nav.goToShop() } label: {
                    HStack(spacing: 6) {
                        // Shared coin graphic — same paw-print minted
                        // coin used on every screen.  Slightly larger
                        // than a plain glyph so the detail reads inside
                        // the small pill.
                        CoinIcon(size: 18)

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
                .homeBallCollider()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(gameState.coinBalance) coins")
                .accessibilityHint("Opens the cosmetic shop.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    /// Floating lives pill in the top-LEFT corner — a mirror of the coin
    /// pill on the right: one red marble + the live count + a chevron.
    /// Unlimited-lives subscribers see one gold marble + an ∞ glyph.
    /// Tapping it opens BuyLivesSheet (which doubles as the "lives status
    /// + explanation + purchase" screen, including the regen countdown).
    private var livesMarblePill: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let unlimited = gameState.unlimitedLives

            VStack {
                HStack {
                    Button {
                        AnalyticsClient.shared.track("home_lives_pill_tapped")
                        showBuyLivesSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            marbleIcon(filled: true, gold: unlimited, size: 18)

                            if unlimited {
                                Image(systemName: "infinity")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Self.goldLifeGradient)
                            } else {
                                Text("\(gameState.displayedLives)")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                            }

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
                    .homeBallCollider()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(livesAccessibilityLabel)
                    .accessibilityHint("Opens the lives status and purchase sheet.")
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.top, 8)
        }
    }

    /// One marble slot.  Three modes:
    ///   • `filled == true`        → full gradient fill with the glossy
    ///                               highlight + drop shadow.
    ///   • `partialFill > 0`       → bottom-aligned partial fill only,
    ///                               clipped to the circle silhouette
    ///                               (no highlight, no shadow — they
    ///                               look weird at half-coverage).
    ///   • neither                 → hollow grey outline.
    @ViewBuilder
    private func marbleIcon(
        filled:      Bool,
        gold:        Bool,
        partialFill: Double = 0,
        size:        CGFloat = 20
    ) -> some View {
        ZStack {
            // Outline — always rendered so the empty/partial states still
            // read as a "marble shape".
            Circle()
                .stroke(Color(white: 0.40).opacity(0.7), lineWidth: 1.0)
                .frame(width: size, height: size)

            if filled {
                Circle()
                    .fill(gold ? Self.goldLifeGradient : Self.redLifeGradient)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.55))
                            .frame(width: size * 0.28, height: size * 0.28)
                            .offset(x: -size * 0.18, y: -size * 0.18)
                    )
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.40), lineWidth: 0.6)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 1.5, y: 1)
            } else if partialFill > 0 {
                // Render the full gradient and clip to the bottom
                // `partialFill` fraction.  The clip shape is a Rect, but
                // because the source is a Circle the visible region
                // naturally curves along the circle's arc at the
                // clip-line — exactly the look we want.
                Circle()
                    .fill(gold ? Self.goldLifeGradient : Self.redLifeGradient)
                    .frame(width: size, height: size)
                    .clipShape(BottomFillRect(fraction: partialFill))
            }
        }
        .frame(width: size, height: size)
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

    /// The live rolling ball on the home screen, with an optional
    /// completionist aura ring when the player has completed at least
    /// one bundle collection.  Green for 1–4 complete, gold for 5+.
    private var liveBall: some View {
        let completedCount = gameState.completedBundleIDs.count
        return ZStack {
            if completedCount > 0 {
                let ringColor: Color = completedCount >= 5
                    ? Color(red: 1.00, green: 0.82, blue: 0.22)   // gold — 5+ collections
                    : Color(red: 0.22, green: 0.88, blue: 0.46)   // green — 1–4
                Circle()
                    .stroke(ringColor, lineWidth: 2.5)
                    .frame(width: ballRadius * 2 + 10, height: ballRadius * 2 + 10)
                    .shadow(color: ringColor.opacity(0.55), radius: 10)
            }
            BallSkinView(skin: gameState.activeSkin, diameter: ballRadius * 2)
                .frame(width: ballRadius * 2, height: ballRadius * 2)
                .shadow(color: .black.opacity(0.65), radius: 14, x: 3, y: 9)
        }
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

// ---------------------------------------------------------------------------
// BottomFillRect — clip shape used by the lives marbles to render the
// regen-progress partial fill.  The rect occupies the bottom `fraction`
// of the frame; clipping a Circle to it produces a curved water-line
// look (the visible boundary follows the circle's arc, not a flat
// horizontal cut).
// ---------------------------------------------------------------------------
struct BottomFillRect: Shape {
    let fraction: Double
    func path(in rect: CGRect) -> Path {
        let h = rect.height * fraction
        return Path(
            CGRect(
                x:      rect.minX,
                y:      rect.maxY - h,
                width:  rect.width,
                height: h
            )
        )
    }
}

// ---------------------------------------------------------------------------
// Home-ball collider plumbing — the free-roaming home ball bounces off any
// UI element tagged with `.homeBallCollider()`.  Each tagged view reports its
// frame (in HomeView's arena coordinate space) through this preference; the
// root ZStack collects them and tickBall() resolves circle-vs-rect contacts
// via PhysicsHelpers.resolveRectObstacle.
// ---------------------------------------------------------------------------

private struct HomeColliderKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    /// Report this view's frame as an obstacle for the home screen's
    /// free-roaming ball.  Apply BEFORE padding so the collider hugs the
    /// visible element rather than its breathing room.
    func homeBallCollider() -> some View {
        background(
            GeometryReader { g in
                Color.clear.preference(
                    key: HomeColliderKey.self,
                    value: [g.frame(in: .named(HomeView.arenaSpaceName))]
                )
            }
        )
    }
}

#Preview {
    HomeView().environmentObject(GameState())
}
