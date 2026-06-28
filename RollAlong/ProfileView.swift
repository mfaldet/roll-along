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

    // Measured height of the loadout name-list, so the diorama beside it can
    // match the left column's height for a clean split.
    @State private var loadoutListHeight: CGFloat = 200

    // ── Derived convenience ────────────────────────────────────────────────
    private var levelsCompleted: Int  { max(0, gameState.highestUnlocked - 1) }
    private var totalPossibleStars: Int { levelsCompleted * 3 }
    private var threeStarCount: Int   { gameState.bestStars.values.filter { $0 == 3 }.count }

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
                    careerCard
                    badgesCard
                    loadoutCard
                    PlayerRanksCard(profile: gameState.localLeaderboardProfile,
                                    playerId: SocialClient.shared.currentUserId)
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
            // ── Ball preview ─────────────────────────────────────────────
            // No completionist ring here — that only appears in the Shop and
            // the Settings cosmetics picker, not on the Profile.
            ZStack {
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
                    text: "\(gameState.currentLevel)",
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
        Top level \(gameState.currentLevel)
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
        // Tapping the loadout opens the Locker to equip cosmetics. The Locker
        // reads the route beneath it (.profile) to show a "< Profile" back button.
        NavigationLink(value: HomeRoute.locker) {
        VStack(spacing: 14) {
            sectionLabel("My Loadout")

            // Split down the middle: the equipped items (names) on the left, an
            // animated diorama of them "in action" on the right. The rarity
            // badges are gone — the scene is the showcase now.
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 10) {
                    loadoutRow(category: "Ball",
                               name: gameState.activeSkin.displayName) {
                        MiniBall(skin: gameState.activeSkin, size: 24)
                    }
                    loadoutRow(category: "Trail",
                               name: gameState.equippedTrail.displayName) {
                        Capsule()
                            .fill(gameState.equippedTrail == .none
                                  ? Color(white: 0.30)
                                  : gameState.equippedTrail.color)
                            .frame(width: 22, height: 7)
                    }
                    loadoutRow(category: "Goal",
                               name: gameState.equippedGoal.displayName) {
                        // Actual goal colour, not a tinted flag — so the swatch
                        // matches what's equipped (including the default).
                        Circle()
                            .fill(GoalSkin.previewGradient(for: gameState.equippedGoal))
                            .overlay(Circle().stroke(Color.white.opacity(0.30), lineWidth: 1))
                            .frame(width: 20, height: 20)
                    }
                    loadoutRow(category: "Floor",
                               name: gameState.equippedFloor.displayName) {
                        // The floor's real colour — "Classic" included.
                        RoundedRectangle(cornerRadius: 6)
                            .fill(gameState.equippedFloor.color)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(white: 0.32), lineWidth: 0.6))
                            .frame(width: 22, height: 22)
                    }
                    loadoutRow(category: "Pit",
                               name: gameState.equippedPit.displayName) {
                        // A mini pit — dark well with the pit's real colour bar.
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.16))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(gameState.equippedPit.color)
                                .frame(width: 14, height: 7)
                        }
                        .frame(width: 22, height: 22)
                    }
                    loadoutRow(category: "Boundary",
                               name: gameState.equippedBoundary.displayName) {
                        // A mini wall segment in the boundary's real colour.
                        RoundedRectangle(cornerRadius: 4)
                            .fill(gameState.equippedBoundary.color)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(gameState.equippedBoundary.edgeColor, lineWidth: 1))
                            .frame(width: 10, height: 22)
                    }
                    loadoutRow(category: "Music",
                               name: gameState.equippedMusic.displayName) {
                        Image(systemName: gameState.equippedMusic == .none
                              ? "speaker.slash.fill" : "music.note")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(gameState.equippedMusic.tier.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { g in
                    Color.clear.preference(key: LoadoutHeightKey.self,
                                           value: g.size.height)
                })

                LoadoutScene(ball:     gameState.activeSkin,
                             trail:    gameState.equippedTrail,
                             goal:     gameState.equippedGoal,
                             floor:    gameState.equippedFloor,
                             pit:      gameState.equippedPit,
                             boundary: gameState.equippedBoundary)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(150, loadoutListHeight))
            }
            .onPreferenceChange(LoadoutHeightKey.self) { loadoutListHeight = $0 }
        }
        .padding(18)
        .profileCard()
        }
        .buttonStyle(.plain)
    }

    /// One equipped-cosmetic row: a small preview swatch + the category and item
    /// name.  Rarity now lives in the animated scene, not a per-row badge.
    private func loadoutRow<Leading: View>(
        category: String,
        name: String,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(spacing: 10) {
            leading()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.5))
                    .tracking(1)
                Text(name)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
    }

    // =========================================================================
    // MARK: - Career card  (merged Progress + Career Stats)
    // Ratio bars on top (stars, perfect levels), then counter cells below. Each
    // stat appears exactly once — Max Level replaces the old "Levels cleared"
    // bar + "Max Level" cell, and the wallet Balance is intentionally omitted
    // (spend shouldn't be visible from a profile).
    // =========================================================================
    private var careerCard: some View {
        VStack(spacing: 18) {
            sectionLabel("Career Stats")

            VStack(spacing: 14) {
                progressRow(
                    icon: "star.fill",
                    label: "Stars earned",
                    value: gameState.totalStars,
                    total: max(1, totalPossibleStars),
                    color: Color(red: 1.0, green: 0.80, blue: 0.20)
                )
                progressRow(
                    icon: "star.circle.fill",
                    label: "Perfect levels (3★)",
                    value: threeStarCount,
                    total: max(1, levelsCompleted),
                    color: Color(red: 1.0, green: 0.62, blue: 0.10)
                )
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                statCell(value: "\(gameState.highestUnlocked)",
                         label: "Max Level",
                         icon:  "flag.fill",
                         color: Color(red: 0.30, green: 0.75, blue: 0.42))
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

/// Reports the loadout name-list's height up to the card so the diorama can
/// match it.
private struct LoadoutHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// ===========================================================================
// LoadoutScene — a small, looping diorama of the equipped cosmetics "in
// action": the ball rolls along the floor, hops up and over the pit, bounces
// off the boundary wall, and settles into the goal — a tail in the equipped
// trail colour following it the whole way.  (The equipped music is heard, not
// drawn.)  Pure-value inputs so it renders identically in the profile and in
// previews.  Respects Reduce Motion by freezing on the final frame.
// ===========================================================================
private struct LoadoutScene: View {
    let ball:     BallSkin
    let trail:    TrailColor
    let goal:     GoalSkin
    let floor:    Floor
    let pit:      Pit
    let boundary: Boundary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // ── Scene geometry (normalised: x 0→1 left→right, y 0→1 top→bottom) ──────
    private let floorTopY:  CGFloat = 0.60   // top surface of the floor
    private let floorThick: CGFloat = 0.12
    private let pitX:       CGFloat = 0.40   // centre of the pit gap
    private let pitHalf:    CGFloat = 0.07
    private let wallX:      CGFloat = 0.88   // boundary-wall centre
    private let wallHalf:   CGFloat = 0.038
    private let goalCenter  = CGPoint(x: 0.62, y: 0.52)

    // The ball's journey, as waypoints densified into a smooth polyline that
    // both the trail stroke and the ball position read from.
    private static let waypoints: [CGPoint] = [
        CGPoint(x: 0.10, y: 0.52),   // start on the floor (left)
        CGPoint(x: 0.30, y: 0.52),   // roll right
        CGPoint(x: 0.40, y: 0.32),   // hop up and over the pit
        CGPoint(x: 0.54, y: 0.52),   // land past the pit
        CGPoint(x: 0.82, y: 0.50),   // roll up to the boundary wall
        CGPoint(x: 0.84, y: 0.42),   // bounce off the wall
        CGPoint(x: 0.66, y: 0.54),   // arc back down-left
        CGPoint(x: 0.62, y: 0.52),   // settle into the goal
    ]
    private static let path: [CGPoint] = catmullRom(waypoints, samplesPerSegment: 20)

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            ZStack {
                background
                setPieces(s)
                if reduceMotion {
                    movers(s, f: 1.0, alpha: 1.0)
                } else {
                    TimelineView(.animation) { tl in
                        let c = Self.cycle(at: tl.date)
                        movers(s, f: c.f, alpha: c.alpha)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8))
        }
    }

    // ── Backdrop ────────────────────────────────────────────────────────────
    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.06, blue: 0.10),
                     Color(red: 0.08, green: 0.09, blue: 0.14)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // ── Static set pieces: floor (split by the pit), pit well, boundary wall,
    //    and the goal target ────────────────────────────────────────────────
    @ViewBuilder
    private func setPieces(_ s: CGSize) -> some View {
        // Floor ledges, left + right of the pit gap.
        ledge(rect(0.02, floorTopY, pitX - pitHalf - 0.02, floorThick, s))
        ledge(rect(pitX + pitHalf, floorTopY, 0.84 - (pitX + pitHalf), floorThick, s))

        // Pit — a darkening well between the ledges.
        pitWell(rect(pitX - pitHalf, floorTopY, pitHalf * 2, 0.24, s))

        // Boundary wall on the right that the ball bounces off.
        wall(rect(wallX - wallHalf, 0.30, wallHalf * 2, floorTopY + 0.04 - 0.30, s))

        // Goal target, resting on the floor.
        Circle()
            .fill(GoalSkin.previewGradient(for: goal))
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .frame(width: goalD(s), height: goalD(s))
            .position(scale(goalCenter, s))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private func ledge(_ r: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(floor.color)
            // Top highlight so even near-black floors read against the backdrop.
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 3)
                .stroke(Color.black.opacity(0.25), lineWidth: 0.5))
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }

    private func pitWell(_ r: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(pit.color)
            .overlay(
                LinearGradient(colors: [.clear, .black.opacity(0.5)],
                               startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            )
            .overlay(RoundedRectangle(cornerRadius: 5)
                .stroke(Color.black.opacity(0.35), lineWidth: 0.8))
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }

    private func wall(_ r: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(boundary.color)
            // Lit left face (the side the ball strikes) + a darker outline.
            .overlay(alignment: .leading) {
                Rectangle().fill(boundary.edgeColor.opacity(0.9)).frame(width: 2)
            }
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(boundary.deepColor, lineWidth: 0.8))
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }

    // ── Moving parts: the trail tail + the ball ──────────────────────────────
    @ViewBuilder
    private func movers(_ s: CGSize, f: CGFloat, alpha: Double) -> some View {
        let pts = Self.path
        let n   = pts.count
        let bIdx = clampIndex(Int((f * CGFloat(n - 1)).rounded()), n)
        let aIdx = clampIndex(Int((max(0, f - 0.30) * CGFloat(n - 1)).rounded()), n)
        let bd   = ballD(s)

        if bIdx > aIdx {
            trailPath(from: aIdx, to: bIdx, s: s)
                .stroke(trailStroke,
                        style: StrokeStyle(lineWidth: bd * 0.42,
                                           lineCap: .round, lineJoin: .round))
                .opacity(alpha)
        }

        MiniBall(skin: ball, size: bd)
            .rotationEffect(.degrees(Double(f) * 760))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .position(scale(pts[bIdx], s))
            .opacity(alpha)
    }

    private var trailStroke: Color {
        trail == .none ? Color.white.opacity(0.5) : trail.color
    }

    private func trailPath(from a: Int, to b: Int, s: CGSize) -> Path {
        var p = Path()
        let pts = Self.path
        guard a < b else { return p }
        p.move(to: scale(pts[a], s))
        for i in (a + 1)...b { p.addLine(to: scale(pts[i], s)) }
        return p
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    private func scale(_ p: CGPoint, _ s: CGSize) -> CGPoint {
        CGPoint(x: p.x * s.width, y: p.y * s.height)
    }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                      _ s: CGSize) -> CGRect {
        CGRect(x: x * s.width, y: y * s.height, width: w * s.width, height: h * s.height)
    }
    private func ballD(_ s: CGSize) -> CGFloat {
        min(34, max(16, min(s.width, s.height) * 0.16))
    }
    private func goalD(_ s: CGSize) -> CGFloat {
        min(44, max(22, min(s.width, s.height) * 0.24))
    }
    private func clampIndex(_ i: Int, _ n: Int) -> Int { max(0, min(n - 1, i)) }

    /// Loop clock → (position fraction `f`, `alpha`).  The ball reaches the
    /// goal at 80% and rests; alpha fades in/out at the seam to hide the reset.
    private static func cycle(at date: Date) -> (f: CGFloat, alpha: Double) {
        let period = 4.2
        let raw = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period          // 0…1
        let f = smoothstep(CGFloat(min(1.0, raw / 0.80)))
        let alpha: Double
        if raw < 0.05      { alpha = raw / 0.05 }                       // fade in
        else if raw > 0.93 { alpha = max(0, (1.0 - raw) / 0.07) }       // fade out
        else               { alpha = 1.0 }
        return (f, alpha)
    }
    private static func smoothstep(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t)); return x * x * (3 - 2 * x)
    }

    /// Catmull-Rom spline through `pts`, sampled into a dense polyline.
    private static func catmullRom(_ pts: [CGPoint],
                                   samplesPerSegment: Int) -> [CGPoint] {
        guard pts.count >= 2 else { return pts }
        var out: [CGPoint] = []
        let n = pts.count
        for i in 0..<(n - 1) {
            let p0 = pts[max(0, i - 1)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(n - 1, i + 2)]
            for k in 0..<samplesPerSegment {
                let t = CGFloat(k) / CGFloat(samplesPerSegment)
                out.append(catmull(p0, p1, p2, p3, t))
            }
        }
        out.append(pts[n - 1])
        return out
    }
    private static func catmull(_ p0: CGPoint, _ p1: CGPoint,
                                _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let t2 = t * t, t3 = t2 * t
        func c(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat {
            0.5 * (2 * b + (-a + cc) * t
                   + (2 * a - 5 * b + 4 * cc - d) * t2
                   + (-a + 3 * b - 3 * cc + d) * t3)
        }
        return CGPoint(x: c(p0.x, p1.x, p2.x, p3.x),
                       y: c(p0.y, p1.y, p2.y, p3.y))
    }
}

// ===========================================================================
// PlayerRanksCard — the bottom-of-profile section listing the player's stats
// AND global rank on every game-mode board.  Shared by ProfileView (your own,
// stats sourced from local GameState) and PublicProfileView (another player,
// stats from their remote PlayerProfile).  Ranks are fetched from the server
// (signed-in only); every board is listed, with unplayed boards shown dim.
// ===========================================================================
struct PlayerRanksCard: View {
    /// The stat source — local snapshot for your own profile, remote row for others.
    let profile: PlayerProfile
    /// The player's id for the rank lookup; nil (or signed out) → stats only.
    let playerId: UUID?

    @State private var ranks:   [String: Int] = [:]   // board.rawValue → rank
    @State private var loading = false
    @State private var loaded  = false

    private var canRank: Bool { playerId != nil && SocialClient.shared.isSignedIn }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Player Ranks")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if loading { ProgressView().scaleEffect(0.7).tint(.white) }
            }

            VStack(spacing: 8) {
                ForEach(LeaderboardBoard.allCases) { board in
                    rankRow(board)
                }
            }

            if !canRank {
                Text("Sign in to see your global ranks.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color(white: 0.42))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(white: 0.105))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(white: 0.18), lineWidth: 0.8))
        )
        .task { await loadRanks() }
    }

    private func rankRow(_ board: LeaderboardBoard) -> some View {
        let played = board.hasPlayed(profile)
        let rank   = ranks[board.rawValue]
        return HStack(spacing: 12) {
            Image(systemName: Self.icon(board))
                .font(.system(size: 15))
                .foregroundStyle(played ? Self.tint(board) : Color(white: 0.30))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(board.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(played ? .white : Color(white: 0.45))
                Text(played ? board.statText(profile) : "Not played yet")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color(white: 0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            rankChip(rank: rank, played: played)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.125))
        )
    }

    @ViewBuilder
    private func rankChip(rank: Int?, played: Bool) -> some View {
        if let rank {
            Text("#\(rank)")
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(rank <= 3 ? .black : .white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(
                    Capsule().fill(rank <= 3
                                   ? Color(red: 1.0, green: 0.81, blue: 0.30)   // top-3 gold
                                   : Color(white: 0.22))
                )
        } else if played && canRank && loading {
            Text("…").font(.system(size: 13, design: .rounded)).foregroundStyle(Color(white: 0.5))
        } else if played && canRank {
            // Played, ranks loaded, but outside the fetched window.
            Text("Unranked").font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.4))
        } else {
            Text("—").font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(white: 0.3))
        }
    }

    private func loadRanks() async {
        guard !loaded, canRank, let id = playerId else { return }
        loaded = true
        loading = true; defer { loading = false }
        ranks = await SocialClient.shared.fetchAllRanks(for: id)
    }

    // Per-board icon + tint (the data model stays UI-free).
    private static func icon(_ b: LeaderboardBoard) -> String {
        switch b {
        case .rollAlong:  return "flag.fill"
        case .pinball:    return "gamecontroller.fill"
        case .zenGarden:  return "leaf.fill"
        case .cometClash: return "sparkles"
        case .sumo:       return "shield.fill"
        case .paintBall:  return "paintbrush.fill"
        case .coinPit:    return "dollarsign.circle.fill"
        case .marbleCup:  return "soccerball"
        case .kingOfHill: return "crown.fill"
        }
    }
    private static func tint(_ b: LeaderboardBoard) -> Color {
        switch b {
        case .rollAlong:  return Color(red: 0.30, green: 0.75, blue: 0.42)
        case .pinball:    return Color(red: 0.36, green: 0.62, blue: 1.00)
        case .zenGarden:  return Color(red: 0.34, green: 0.78, blue: 0.55)
        case .cometClash: return Color(red: 0.42, green: 0.80, blue: 1.00)
        case .sumo:       return Color(red: 0.95, green: 0.45, blue: 0.30)
        case .paintBall:  return Color(red: 0.70, green: 0.42, blue: 0.96)
        case .coinPit:    return Color(red: 1.00, green: 0.78, blue: 0.20)
        case .marbleCup:  return Color(red: 0.30, green: 0.80, blue: 0.70)
        case .kingOfHill: return Color(red: 0.95, green: 0.72, blue: 0.15)
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(GameState())
    }
}
