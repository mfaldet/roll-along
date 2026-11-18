import SwiftUI

// ---------------------------------------------------------------------------
// ProfileView — player career summary.
//
// S13: hero (ball + name + level), progress bars, career-stats grid,
//      scrollable level-records table.
// S14: badge wall (11 achievements, locked/unlocked), social rank line
//      (loaded from the leaderboard when signed in), ShareLink card.
// S2-T4 (trophies): the S14 badge wall is RETIRED — the card is now the
//      engine-backed Trophy card (`ProfileTrophyCard`, below), reflecting the
//      latched trophy ledger instead of live-derived, pay-gated "badges".
//
// Pushed from HomeView via HomeRoute.profile.
// ---------------------------------------------------------------------------
struct ProfileView: View {
    @EnvironmentObject var gameState: GameState

    // Measured height of the loadout name-list, so the diorama beside it can
    // match the left column's height for a clean split.
    @State private var loadoutListHeight: CGFloat = 200
    /// The nickname picker (moved here from Settings).
    @State private var showNicknamePicker = false
    @ObservedObject private var auth = AppleAuthManager.shared
    /// The player's friend code, for the share message (nil until the server
    /// has one).
    @State private var myFriendCode: String?

    // ── Derived convenience ────────────────────────────────────────────────
    private var levelsCompleted: Int  { max(0, gameState.highestUnlocked - 1) }
    private var totalPossibleStars: Int { levelsCompleted * 3 }
    private var threeStarCount: Int   { gameState.bestStars.values.filter { $0 == 3 }.count }

    var body: some View {
        ZStack {
            // Background — the app's dark tone, tinted with the player's own
            // accent color (it used to be a fixed dark blue for everyone).
            LinearGradient(
                colors: [Self.baseTop.mix(with: accent, by: 0.22),
                         Self.baseBottom.mix(with: accent, by: 0.10)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. Header: ball, name, level, with the Nickname and
                    //    Accent Color controls (moved here from Settings).
                    heroCard
                    // 2. Friend code (only when signed in and the server has one).
                    if SocialClient.shared.isSignedIn { FriendCodeCard() }
                    // 3. My Loadout — opens the Locker.
                    loadoutCard
                    // 4. Trophies — opens the Trophy Room (Home has no Trophies
                    //    button).
                    ProfileTrophyCard(engine: gameState.trophyEngine,
                                      pins: gameState.trophyPins)
                    // 5. Everything else, as before.
                    careerCard
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
            Self.baseTop.mix(with: accent, by: 0.22).opacity(0.95),
            for: .navigationBar
        )
        .toolbarColorScheme(.dark, for: .navigationBar)
        // The friend code, for the share message.
        .task(id: auth.isSignedIn) {
            myFriendCode = auth.isSignedIn ? await SocialClient.shared.fetchMyFriendCode() : nil
        }
    }

    // =========================================================================
    // MARK: - Hero card
    // Ball preview (with the level marker on its top-right) · player name ·
    // ShareLink.  (Lives count and global Rank were removed — Rank will be
    // replaced by nuanced awards/titles.)
    // =========================================================================
    private var heroCard: some View {
        VStack(spacing: 14) {
            // ── Ball preview ─────────────────────────────────────────────
            // No completionist ring here — that only appears in the Shop and
            // the Settings cosmetics picker, not on the Profile.
            // ── Ball preview with the level marker on its top-right ──────
            ZStack {
                BallSkinView(skin: gameState.activeSkin, diameter: 88)
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.72), radius: 18, x: 0, y: 10)
                    .overlay(alignment: .topTrailing) {
                        levelMarker
                            .offset(x: 16, y: -6)
                    }
            }
            .frame(width: 124, height: 116)

            // ── Name ─────────────────────────────────────────────────────
            PlayerNameLabel(name: gameState.playerName.isEmpty ? "Anonymous Roller" : gameState.playerName,
                            level: gameState.highestUnlocked,
                            font: .system(size: 26, weight: .bold, design: .rounded),
                            tint: gameState.primaryColor)

            // Lives count and global Rank were removed here — Rank is being
            // replaced by nuanced awards/titles.  Above the line the header is
            // static (ball, name, level); the controls sit below it.

            Divider()
                .background(Color(white: 0.22))
                .padding(.horizontal, 4)

            // ── Nickname · Accent Color · Share Profile ───────────────────
            // One row when it fits, else Nickname and Accent Color on one line
            // with Share Profile under them.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { nicknameButton; accentControl; shareButton }
                VStack(spacing: 10) {
                    HStack(spacing: 8) { nicknameButton; accentControl }
                    shareButton
                }
            }
            .sheet(isPresented: $showNicknamePicker) {
                NicknamePickerSheet().environmentObject(gameState)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .profileCard()
    }

    /// The same message as Friends → Invite a friend (`InviteMessage`).
    private var shareText: String { InviteMessage.text(friendCode: myFriendCode) }

    private var nicknameButton: some View {
        Button { showNicknamePicker = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .bold))
                Text("Nickname")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color(white: 0.75))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Color(white: 0.15))
                .overlay(Capsule().stroke(Color(white: 0.26), lineWidth: 0.8)))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Change nickname")
        .accessibilityHint("Pick two preset words for your name.")
    }

    private var accentControl: some View {
        HStack(spacing: 6) {
            // The system color well: a tap opens the color picker.
            ColorPicker("Accent color",
                        selection: Binding(get: { gameState.primaryColor },
                                           set: { gameState.primaryColor = $0 }),
                        supportsOpacity: false)
                .labelsHidden()
                .frame(width: 24, height: 24)
            Text("Accent Color")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.75))
        }
        .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 5)
        .background(Capsule().fill(Color(white: 0.15))
            .overlay(Capsule().stroke(Color(white: 0.26), lineWidth: 0.8)))
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    private var shareButton: some View {
        ShareLink(item: shareText) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                Text("Share Profile")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color(white: 0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color(white: 0.15))
                    .overlay(Capsule().stroke(Color(white: 0.26), lineWidth: 0.8))
            )
        }
        .fixedSize()
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
            // "My Locker ›" says the card opens the screen to change what is
            // equipped.
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("My Loadout")
                HStack(spacing: 3) {
                    Text("My Locker")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(TrophyGradeStyle.forTier(.gold).accent)
                .fixedSize()
                .accessibilityHidden(true)
            }

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

                LoadoutDiorama(loadout: Loadout(
                                ball:     gameState.activeSkin,
                                trail:    gameState.equippedTrail,
                                goal:     gameState.equippedGoal,
                                floor:    gameState.equippedFloor,
                                pit:      gameState.equippedPit,
                                boundary: gameState.equippedBoundary))
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
    // MARK: - Trophy card  (S2-T4 — replaces the retired S14 badge wall)
    //
    // The old 11-badge wall (BadgeDef / allBadges) was removed here: it derived
    // "badges" LIVE from regressable GameState stats and pay-gated one entry
    // ("Unlimited Power" → the $-gated `unlimitedLives` IAP, dropped per
    // internal-economy.md §4). The card is now `ProfileTrophyCard` (a top-level
    // view further down this file), which reflects the LATCHED trophy ledger
    // from `TrophyEngine` and links through to the full Trophy Room (S2-T3).
    // =========================================================================

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

    /// The level marker badge that sits on the marble's top-right corner —
    /// a small "LVL" eyebrow over a large level number.
    /// The player's own accent color, made readable on the dark background.
    private var accent: Color { AccentColor.readable(gameState.primaryColor) }
    private static let baseTop    = Color(red: 0.06, green: 0.06, blue: 0.10)
    private static let baseBottom = Color(red: 0.09, green: 0.09, blue: 0.14)

    private var levelMarker: some View {
        VStack(spacing: -2) {
            Text("LVL")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.85))
            // The Adventure level, the same number as the badge by the name.
            Text("\(gameState.highestUnlocked)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(minWidth: 42)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            // The player's accent (was a fixed purple for everyone): a
            // darkened fill so the white digits read, and a brighter rim.
            RoundedRectangle(cornerRadius: 14)
                .fill(accent.mix(with: .black, by: 0.45))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(accent.opacity(0.85), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
        )
    }


}

// ---------------------------------------------------------------------------
// ProfileCard — the dark rounded-rect backdrop shared by every card.
// Applied as a ViewModifier so the call sites are clean.
// ---------------------------------------------------------------------------
struct ProfileCardModifier: ViewModifier {
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

extension View {
    /// The Profile section card: dark fill with a faint light rim.
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
    @State private var diffRanks: [String: Int] = [:] // "game|difficulty" → rank
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
        let diffs  = perDifficultyRanks(board)
        let played = board.hasPlayed(profile) || !diffs.isEmpty
        // A board kept per difficulty has no single rank: its chip shows the
        // best of the player's difficulty ranks, listed underneath.
        let rank   = board.difficultyGameID == nil ? ranks[board.rawValue]
                                                   : diffs.map { $0.rank }.min()
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: Self.icon(board))
                    .font(.system(size: 15))
                    .foregroundStyle(played ? Self.tint(board) : Color(white: 0.30))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(board.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(played ? .white : Color(white: 0.45))
                    Text(played ? (board.hasPlayed(profile) ? board.statText(profile)
                                                            : "Ranked by difficulty")
                                : "Not played yet")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                rankChip(rank: rank, played: played)
            }

            // Per-difficulty ranks (competitive boards and Disco Ball), where
            // the player is ranked.
            if !diffs.isEmpty {
                HStack(spacing: 10) {
                    ForEach(diffs, id: \.label) { d in
                        Text("\(d.label) #\(d.rank)")
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(d.rank <= 3
                                             ? Color(red: 1.0, green: 0.81, blue: 0.30)
                                             : Color(white: 0.55))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 36)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.125))
        )
    }

    /// Per-difficulty ranks (Easy / Normal / Hard, or Hardcore on Disco Ball)
    /// for a board kept per difficulty, in order, only where the player is
    /// actually ranked.
    private func perDifficultyRanks(_ board: LeaderboardBoard) -> [(label: String, rank: Int)] {
        guard let game = board.difficultyGameID else { return [] }
        return ["easy", "normal", "hard"].compactMap { key in
            diffRanks["\(game)|\(key)"].map { (label: board.difficultyLabel(key), rank: $0) }
        }
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
        async let overall = SocialClient.shared.fetchAllRanks(for: id)
        async let perDiff = SocialClient.shared.fetchMinigameDifficultyRanks(for: id)
        ranks = await overall
        diffRanks = await perDiff
    }

    // Per-board icon + tint (the data model stays UI-free).
    private static func icon(_ b: LeaderboardBoard) -> String {
        switch b {
        case .rollAlong:  return "flag.fill"
        case .zenGarden:  return "leaf.fill"
        case .rollUp:     return "arrow.up.circle.fill"
        case .snacky:     return "ellipsis"
        case .sumo:       return "shield.fill"
        case .paintBall:  return "paintbrush.fill"
        case .coinPit:    return "dollarsign.circle.fill"
        case .marbleCup:  return "soccerball"
        case .kingOfHill: return "crown.fill"
        case .discoBall:  return "figure.dance"
        }
    }
    private static func tint(_ b: LeaderboardBoard) -> Color {
        switch b {
        case .rollAlong:  return Color(red: 0.30, green: 0.75, blue: 0.42)
        case .zenGarden:  return Color(red: 0.34, green: 0.78, blue: 0.55)
        case .rollUp:     return Color(red: 0.36, green: 0.70, blue: 1.00)
        case .snacky:     return Color(red: 0.55, green: 1.00, blue: 0.62)
        case .sumo:       return Color(red: 0.95, green: 0.45, blue: 0.30)
        case .paintBall:  return Color(red: 0.70, green: 0.42, blue: 0.96)
        case .coinPit:    return Color(red: 1.00, green: 0.78, blue: 0.20)
        case .marbleCup:  return Color(red: 0.30, green: 0.80, blue: 0.70)
        case .kingOfHill: return Color(red: 0.95, green: 0.72, blue: 0.15)
        case .discoBall:  return Color(red: 0.32, green: 0.85, blue: 1.00)
        }
    }
}

// ===========================================================================
// MARK: - ProfileTrophyCard  (S2-T4)
//
// The Profile card that replaced the retired 11-badge wall. It reflects the
// LATCHED trophy ledger from `TrophyEngine` (never live-derived, regressable
// GameState stats), showing:
//   • a header with earned/total + overall completion %,
//   • a per-grade strip (Bronze…Platinum, glyph + earned/total; NO points —
//     design.md §2 ships grades + capstone only),
//   • a showcase strip of the player's staged trophies (pinned-first once
//     S2-T7 wires pins, else most-recently-earned),
// and links through to the full Trophy Room (S2-T3) via `HomeRoute.trophies`.
//
// All display logic lives in `TrophyShowcaseModel` (pure, unit-tested); this
// view only draws it. Observes the engine so a mid-session unlock refreshes
// the card. Display-only — reads the engine, writes nothing (NEVER-MINT).
//
// Diamond rider (design.md §2 R2): grade glyph/accent come from the single
// `TrophyGradeStyle` source via the model's entries — the Diamond GRADE never
// borrows the Diamond-ball cosmetic gem.
// ===========================================================================
struct ProfileTrophyCard: View {

    @ObservedObject var engine: TrophyEngine

    /// The pin store (S2-T7). Observed so pinning a trophy in the Trophy Room
    /// floats it to the front of this card's showcase on return. Optional so
    /// the card still renders in previews/tests without a store (empty pins).
    @ObservedObject var pins: TrophyPinStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(engine: TrophyEngine, pins: TrophyPinStore = TrophyPinStore()) {
        self.engine = engine
        self.pins = pins
    }

    /// Recomputed each render from the current engine + pin snapshot. Cheap:
    /// one pass over the catalog of value types. Pinned trophies (the S2-T7
    /// `ra_trophyPins` order) float to the front of the showcase; the rest is
    /// most-recently-earned.
    private var model: TrophyShowcaseModel {
        TrophyShowcaseModel(engine: engine, pinnedIDs: pins.pinnedIDs)
    }

    var body: some View {
        NavigationLink(value: HomeRoute.trophies) {
            content(model)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens the Trophy Room")
    }

    @ViewBuilder
    private func content(_ model: TrophyShowcaseModel) -> some View {
        VStack(spacing: 16) {
            header(model)
            gradeStrip(model)

            if model.isEmpty {
                emptyState
            } else {
                showcaseStrip(model)
            }
        }
        .padding(18)
        .profileCard()
        .contentShape(Rectangle())
    }

    // MARK: Header — title + earned/total + completion %

    @ViewBuilder
    private func header(_ model: TrophyShowcaseModel) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                Text("Trophies")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if model.capstoneUnlocked {
                    Image(systemName: "rosette")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TrophyGradeStyle.forTier(.platinum).accent)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 8)
            // Says plainly that the card opens the Trophy Room.
            HStack(spacing: 3) {
                Text("Trophy Room")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(TrophyGradeStyle.forTier(.gold).accent)
            .padding(.leading, 6)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerAccessibilityLabel(model))
    }

    private func headerAccessibilityLabel(_ model: TrophyShowcaseModel) -> String {
        var parts = ["Trophies"]
        if model.capstoneUnlocked { parts.append("Platinum capstone earned") }
        return parts.joined(separator: ", ")
    }

    // MARK: Per-grade strip (ladder order; NO points)

    @ViewBuilder
    private func gradeStrip(_ model: TrophyShowcaseModel) -> some View {
        HStack(spacing: 8) {
            ForEach(model.gradeCounts) { g in
                gradeChip(g)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func gradeChip(_ g: TrophyShowcaseModel.GradeCount) -> some View {
        let style = TrophyGradeStyle.forTier(g.tier)
        VStack(spacing: 3) {
            Image(systemName: style.glyph)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(g.earned > 0 ? style.accent : style.accent.opacity(0.35))
            Text("\(g.earned)/\(g.total)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(g.earned > 0 ? .white : Color(white: 0.40))
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(style.accent.opacity(g.earned > 0 ? 0.5 : 0.12), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(g.gradeName), \(g.earned) of \(g.total) earned")
    }

    // MARK: Showcase strip (earned trophies on stage)

    @ViewBuilder
    private func showcaseStrip(_ model: TrophyShowcaseModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(model.showcase) { entry in
                    showcaseCell(entry)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func showcaseCell(_ entry: TrophyShowcaseEntry) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(entry.gradeAccent.opacity(0.18))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle().stroke(entry.gradeAccent.opacity(0.48), lineWidth: 1.2)
                    )
                Image(systemName: entry.tileIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(entry.gradeAccent)
            }

            Text(entry.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(entry.gradeName)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .frame(width: 78)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel)
    }

    // MARK: Empty state (no trophies earned yet)

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy")
                .font(.system(size: 20))
                .foregroundStyle(Color(white: 0.45))
                .accessibilityHidden(true)
            Text("No trophies yet — play to earn your first.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No trophies yet. Play to earn your first.")
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(GameState())
    }
}
