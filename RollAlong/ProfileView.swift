import SwiftUI

// ---------------------------------------------------------------------------
// ProfileView — player career summary.
//
// S13: hero (ball + name + level), progress bars, career-stats grid,
//      scrollable level-records table.
// S14: badge wall (11 achievements, locked/unlocked), social rank line
//      (loaded from the leaderboard when signed in), ShareLink card.
//
// Pushed from HomeView via HomeRoute.profile.
// ---------------------------------------------------------------------------
struct ProfileView: View {
    @EnvironmentObject var gameState: GameState

    // ── Social rank ────────────────────────────────────────────────────────
    @State private var leaderboardRank: Int? = nil
    @State private var rankLoading:     Bool = false

    // ── Derived convenience ────────────────────────────────────────────────
    private var levelsCompleted: Int  { max(0, gameState.highestUnlocked - 1) }
    private var totalPossibleStars: Int { levelsCompleted * 3 }
    private var threeStarCount: Int   { gameState.bestStars.values.filter { $0 == 3 }.count }

    private var levelRecords: [(level: Int, stars: Int, time: TimeInterval?)] {
        gameState.bestStars.keys.sorted().compactMap { lvl in
            guard let stars = gameState.bestStars[lvl] else { return nil }
            return (lvl, stars, gameState.bestTime[lvl])
        }
    }

    var body: some View {
        ZStack {
            // Background — same dark tone as the rest of the app.
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.10),
                         Color(red: 0.09, green: 0.09, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    heroCard
                    loadoutCard
                    progressCard
                    statsGrid
                    badgesCard
                    if !levelRecords.isEmpty {
                        levelRecordsCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            Color(red: 0.06, green: 0.06, blue: 0.10).opacity(0.95),
            for: .navigationBar
        )
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadLeaderboardRank() }
    }

    // =========================================================================
    // MARK: - Hero card
    // Ball preview · player name · level badge · optional unlimited badge
    // · social rank or sign-in nudge · ShareLink
    // =========================================================================
    private var heroCard: some View {
        VStack(spacing: 14) {
            // ── Ball preview with completionist ring ─────────────────────
            let completed = gameState.completedBundleIDs.count
            ZStack {
                if completed > 0 {
                    let ringColor: Color = completed >= 5
                        ? Color(red: 1.00, green: 0.82, blue: 0.22)
                        : Color(red: 0.22, green: 0.88, blue: 0.46)
                    Circle()
                        .stroke(ringColor, lineWidth: 3.0)
                        .frame(width: 108, height: 108)
                        .shadow(color: ringColor.opacity(0.55), radius: 14)
                }
                BallSkinView(skin: gameState.activeSkin, diameter: 88)
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.72), radius: 18, x: 0, y: 10)
            }
            .frame(width: 116, height: 116)

            // ── Name ─────────────────────────────────────────────────────
            Text(gameState.playerName.isEmpty ? "Anonymous Roller" : gameState.playerName)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            // ── Badges row ───────────────────────────────────────────────
            HStack(spacing: 8) {
                pillBadge(
                    text: "Level \(gameState.currentLevel)",
                    bg: Color(red: 0.26, green: 0.16, blue: 0.58),
                    border: Color(red: 0.50, green: 0.38, blue: 0.90).opacity(0.55),
                    fg: .white
                )
                if gameState.unlimitedLives {
                    HStack(spacing: 4) {
                        Image(systemName: "infinity")
                            .font(.system(size: 11, weight: .bold))
                        Text("Unlimited")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.22))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.22, green: 0.16, blue: 0.04))
                            .overlay(Capsule().stroke(Color(red: 0.93, green: 0.65, blue: 0.10).opacity(0.55), lineWidth: 1))
                    )
                }
            }

            // ── Social rank ──────────────────────────────────────────────
            if SocialClient.shared.isSignedIn {
                Group {
                    if rankLoading {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.70)
                            Text("Fetching rank…")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Color(white: 0.50))
                        }
                    } else if let rank = leaderboardRank {
                        HStack(spacing: 5) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.22))
                            Text("Rank #\(rank) globally")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(white: 0.68))
                        }
                    }
                }
            } else {
                Text("Sign in to rank globally")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color(white: 0.38))
            }

            Divider()
                .background(Color(white: 0.22))
                .padding(.horizontal, 4)

            // ── Share button ─────────────────────────────────────────────
            ShareLink(
                item: shareText,
                preview: SharePreview(
                    "My Roll Along Profile",
                    icon: Image(systemName: "circle.fill")
                )
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Share Profile")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color(white: 0.75))
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Color(white: 0.15))
                        .overlay(Capsule().stroke(Color(white: 0.26), lineWidth: 0.8))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .profileCard()
    }

    private var shareText: String {
        """
        My Roll Along stats 🎱
        Level \(gameState.currentLevel) Climber
        ⭐ \(gameState.totalStars) stars earned
        🔥 \(gameState.liveStreak)-day streak
        🎨 \(gameState.completedBundleIDs.count) bundle\(gameState.completedBundleIDs.count == 1 ? "" : "s") complete
        """
    }

    // =========================================================================
    // MARK: - Progress card
    // Three animated bars: stars earned, levels cleared, perfect (3-star) levels
    // =========================================================================
    // =========================================================================
    // MARK: - Loadout showcase
    // The player's equipped cosmetics as social capital — each with its rarity,
    // so the profile shows off what you've earned/collected at a glance.
    // =========================================================================
    private var loadoutCard: some View {
        VStack(spacing: 14) {
            sectionLabel("My Loadout")

            VStack(spacing: 10) {
                loadoutRow(category: "Ball",
                           name: gameState.activeSkin.displayName,
                           tier: gameState.activeSkin.tier) {
                    MiniBall(skin: gameState.activeSkin, size: 26)
                }
                loadoutRow(category: "Trail",
                           name: gameState.equippedTrail.displayName,
                           tier: gameState.equippedTrail.tier) {
                    Capsule()
                        .fill(gameState.equippedTrail == .none
                              ? Color(white: 0.30)
                              : gameState.equippedTrail.color)
                        .frame(width: 24, height: 7)
                }
                loadoutRow(category: "Goal",
                           name: gameState.equippedGoal.displayName,
                           tier: gameState.equippedGoal.tier) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(gameState.equippedGoal.tier.color)
                }
                loadoutRow(category: "Floor",
                           name: gameState.equippedFloor.displayName,
                           tier: gameState.equippedFloor.tier) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(gameState.equippedFloor.tier.color)
                }
                loadoutRow(category: "Pit",
                           name: gameState.equippedPit.displayName,
                           tier: gameState.equippedPit.tier) {
                    Image(systemName: "circle.bottomhalf.filled")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(gameState.equippedPit.tier.color)
                }
                loadoutRow(category: "Music",
                           name: gameState.equippedMusic.displayName,
                           tier: gameState.equippedMusic.tier) {
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(gameState.equippedMusic.tier.color)
                }
            }
        }
        .padding(18)
        .profileCard()
    }

    /// One equipped-cosmetic row: a small preview, the category + item name,
    /// and its rarity badge (right-aligned).
    private func loadoutRow<Leading: View>(
        category: String,
        name: String,
        tier: CosmeticTier,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(spacing: 12) {
            leading()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.5))
                    .tracking(1)
                Text(name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
            TierBadge(tier: tier)
        }
    }

    private var progressCard: some View {
        VStack(spacing: 16) {
            sectionLabel("Progress")

            VStack(spacing: 14) {
                progressRow(
                    icon: "star.fill",
                    label: "Stars earned",
                    value: gameState.totalStars,
                    total: max(1, totalPossibleStars),
                    color: Color(red: 1.0, green: 0.80, blue: 0.20)
                )
                progressRow(
                    icon: "flag.checkered",
                    label: "Levels cleared",
                    value: levelsCompleted,
                    total: max(1, levelsCompleted),
                    color: Color(red: 0.30, green: 0.75, blue: 0.42)
                )
                progressRow(
                    icon: "star.circle.fill",
                    label: "Perfect levels (3★)",
                    value: threeStarCount,
                    total: max(1, levelsCompleted),
                    color: Color(red: 1.0, green: 0.62, blue: 0.10)
                )
            }
        }
        .padding(18)
        .profileCard()
    }

    private func progressRow(
        icon:  String,
        label: String,
        value: Int,
        total: Int,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.72))
                Spacer()
                Text("\(value) / \(total)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(white: 0.17))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(
                            width: geo.size.width * CGFloat(min(1.0, Double(value) / Double(max(1, total)))),
                            height: 6
                        )
                }
            }
            .frame(height: 6)
        }
    }

    // =========================================================================
    // MARK: - Stats grid
    // 3×2 grid of large-number cells: stars, streak, coins, bundles, level,
    // balance.
    // =========================================================================
    private var statsGrid: some View {
        VStack(spacing: 16) {
            sectionLabel("Career Stats")

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                statCell(value: "\(gameState.totalStars)",
                         label: "Stars",
                         icon:  "star.fill",
                         color: Color(red: 1.0, green: 0.80, blue: 0.20))
                statCell(value: "\(gameState.liveStreak)",
                         label: "Streak",
                         icon:  "flame.fill",
                         color: Color(red: 1.0, green: 0.45, blue: 0.15))
                statCell(value: "\(gameState.totalCoins)",
                         label: "Coins Found",
                         icon:  "circle.fill",
                         color: Color(red: 0.95, green: 0.75, blue: 0.20))
                statCell(value: "\(gameState.completedBundleIDs.count)",
                         label: "Bundles",
                         icon:  "gift.fill",
                         color: Color(red: 0.58, green: 0.32, blue: 0.96))
                statCell(value: "\(gameState.highestUnlocked)",
                         label: "Max Level",
                         icon:  "flag.fill",
                         color: Color(red: 0.30, green: 0.75, blue: 0.42))
                statCell(value: "\(gameState.coinBalance)",
                         label: "Balance",
                         icon:  "banknote.fill",
                         color: Color(red: 0.38, green: 0.80, blue: 0.46))
            }
        }
        .padding(18)
        .profileCard()
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.48))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.125))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(white: 0.20), lineWidth: 0.6)
                )
        )
    }

    // =========================================================================
    // MARK: - Badges card  (S14)
    // 11 achievements arranged in a horizontal scroll.  Earned badges show their
    // full icon + colour; locked badges show a lock on a dim circle.
    // Earned badges are listed first, then locked ones.
    // =========================================================================

    // Badge definition — private to this view
    private struct BadgeDef: Identifiable {
        let id:       String
        let icon:     String
        let title:    String
        let subtitle: String
        let color:    Color
        let check:    (GameState) -> Bool
    }

    private static let allBadges: [BadgeDef] = [
        BadgeDef(id: "first_steps",
                 icon:     "figure.walk",
                 title:    "First Steps",
                 subtitle: "Clear level 1",
                 color:    Color(red: 0.28, green: 0.82, blue: 0.44),
                 check:    { $0.highestUnlocked > 1 }),

        BadgeDef(id: "hat_trick",
                 icon:     "star.fill",
                 title:    "Hat Trick",
                 subtitle: "3-star any level",
                 color:    Color(red: 1.0, green: 0.82, blue: 0.22),
                 check:    { $0.bestStars.values.contains(3) }),

        BadgeDef(id: "star_collector",
                 icon:     "star.circle.fill",
                 title:    "Star Collector",
                 subtitle: "50 total stars",
                 color:    Color(red: 1.0, green: 0.60, blue: 0.12),
                 check:    { $0.totalStars >= 50 }),

        BadgeDef(id: "stellar",
                 icon:     "staroflife.fill",
                 title:    "Stellar",
                 subtitle: "150 total stars",
                 color:    Color(red: 1.0, green: 0.38, blue: 0.10),
                 check:    { $0.totalStars >= 150 }),

        BadgeDef(id: "on_a_roll",
                 icon:     "flame.fill",
                 title:    "On a Roll",
                 subtitle: "7-day streak",
                 color:    Color(red: 1.0, green: 0.48, blue: 0.12),
                 check:    { $0.dailyStreak >= 7 }),

        BadgeDef(id: "dedicated",
                 icon:     "calendar.badge.checkmark",
                 title:    "Dedicated",
                 subtitle: "30-day streak",
                 color:    Color(red: 0.92, green: 0.22, blue: 0.22),
                 check:    { $0.dailyStreak >= 30 }),

        BadgeDef(id: "coin_hoarder",
                 icon:     "dollarsign.circle.fill",
                 title:    "Coin Hoarder",
                 subtitle: "100 in-game coins",
                 color:    Color(red: 0.95, green: 0.78, blue: 0.20),
                 check:    { $0.totalCoins >= 100 }),

        BadgeDef(id: "completionist",
                 icon:     "checkmark.seal.fill",
                 title:    "Completionist",
                 subtitle: "Complete any bundle",
                 color:    Color(red: 0.28, green: 0.60, blue: 0.96),
                 check:    { !$0.completedBundleIDs.isEmpty }),

        BadgeDef(id: "bundle_hunter",
                 icon:     "gift.fill",
                 title:    "Bundle Hunter",
                 subtitle: "Complete 3 bundles",
                 color:    Color(red: 0.55, green: 0.28, blue: 0.96),
                 check:    { $0.completedBundleIDs.count >= 3 }),

        BadgeDef(id: "unlimited",
                 icon:     "infinity",
                 title:    "Unlimited Power",
                 subtitle: "Unlock Unlimited Lives",
                 color:    Color(red: 0.93, green: 0.65, blue: 0.10),
                 check:    { $0.unlimitedLives }),

        BadgeDef(id: "legend",
                 icon:     "crown.fill",
                 title:    "Legend",
                 subtitle: "Reach level 50",
                 color:    Color(red: 0.95, green: 0.72, blue: 0.15),
                 check:    { $0.highestUnlocked >= 50 }),
    ]

    private var badgesCard: some View {
        let earned = Self.allBadges.filter {  $0.check(gameState) }
        let locked = Self.allBadges.filter { !$0.check(gameState) }
        return VStack(spacing: 16) {
            HStack {
                sectionLabel("Badges")
                Spacer()
                Text("\(earned.count) / \(Self.allBadges.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.40))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(earned) { badge in
                        badgeCell(badge, isEarned: true)
                    }
                    ForEach(locked) { badge in
                        badgeCell(badge, isEarned: false)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .profileCard()
    }

    private func badgeCell(_ badge: BadgeDef, isEarned: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isEarned
                          ? badge.color.opacity(0.18)
                          : Color(white: 0.12))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(isEarned
                                    ? badge.color.opacity(0.48)
                                    : Color(white: 0.18),
                                    lineWidth: 1.2)
                    )

                if isEarned {
                    Image(systemName: badge.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(badge.color)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color(white: 0.30))
                }
            }

            Text(badge.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isEarned ? .white : Color(white: 0.32))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(badge.subtitle)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Color(white: 0.32))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 78)
    }

    // =========================================================================
    // MARK: - Level records card
    // Scrollable table: one row per beaten level, sorted ascending.
    // Columns: level number badge · star icons (3 always rendered) · best time.
    // =========================================================================
    private var levelRecordsCard: some View {
        VStack(spacing: 16) {
            HStack {
                sectionLabel("Level Records")
                Spacer()
                Text("\(levelRecords.count) cleared")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.40))
            }

            VStack(spacing: 6) {
                ForEach(levelRecords, id: \.level) { record in
                    levelRow(record)
                }
            }
        }
        .padding(18)
        .profileCard()
    }

    private func levelRow(_ record: (level: Int, stars: Int, time: TimeInterval?)) -> some View {
        HStack(spacing: 10) {
            // Level badge
            Text("L\(record.level)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(white: 0.68))
                .frame(width: 32, alignment: .leading)

            // 3 star icons
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < record.stars ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            i < record.stars
                                ? Color(red: 1.0, green: 0.80, blue: 0.20)
                                : Color(white: 0.24)
                        )
                }
            }

            Spacer()

            // Best time
            if let t = record.time {
                Text(Self.formatTime(t))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.58))
            } else {
                Text("—")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color(white: 0.28))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(white: 0.12))
        )
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    /// Section title above each card's content.
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A tinted pill badge used in the hero section.
    private func pillBadge(text: String, bg: Color, border: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(bg)
                    .overlay(Capsule().stroke(border, lineWidth: 1))
            )
    }

    /// Time interval → "42.3s" or "1:05.3" string.
    private static func formatTime(_ t: TimeInterval) -> String {
        let total   = max(0, t)
        let minutes = Int(total) / 60
        let secs    = total - Double(minutes * 60)
        if minutes > 0 {
            return String(format: "%d:%04.1f", minutes, secs)
        } else {
            return String(format: "%.1fs", secs)
        }
    }

    // =========================================================================
    // MARK: - Social rank loader
    // Fetches the global leaderboard (up to 500) and finds the signed-in
    // player's position.  Fire-and-forget on appear; rank is purely cosmetic.
    // =========================================================================
    private func loadLeaderboardRank() async {
        guard SocialClient.shared.isSignedIn,
              let myId = SocialClient.shared.currentUserId else { return }
        rankLoading = true
        defer { rankLoading = false }
        guard let board = try? await SocialClient.shared.fetchLeaderboard(limit: 500) else { return }
        leaderboardRank = board.firstIndex(where: { $0.id == myId }).map { $0 + 1 }
    }
}

// ---------------------------------------------------------------------------
// ProfileCard — the dark rounded-rect backdrop shared by every card.
// Applied as a ViewModifier so the call sites are clean.
// ---------------------------------------------------------------------------
private struct ProfileCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(white: 0.105))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color(white: 0.18), lineWidth: 0.8)
                    )
            )
    }
}

private extension View {
    func profileCard() -> some View { modifier(ProfileCardModifier()) }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(GameState())
    }
}
