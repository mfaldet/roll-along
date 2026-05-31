import SwiftUI

/// Grid view showing all 100 hand-crafted levels with star/coin progress.
/// Tapping a cleared (or next-unlocked) level pushes BallGameView for that
/// level.  Locked levels show a lock and don't navigate.
struct LevelSelectView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator
    @Environment(\.dismiss) var dismiss

    /// Total levels currently designed.  Grows in PR 2b/2c.
    private let totalLevels = 100
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    grid
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Levels")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { nav.goHome() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Home")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Sub-views

    // MARK: - Progress math (over currently-unlocked-and-designed levels)
    //
    // The user explicitly wanted the header stats to measure progress on
    // levels they have ACCESS to, not the full 100-level pool.  Otherwise
    // the percentage starts at near-zero forever and never feels like
    // progress.  So we cap the denominator at `min(highestUnlocked,
    // designedLevels)`.

    private var unlockedDesignedCount: Int {
        min(gameState.highestUnlocked, LevelLayout.handCrafted.count)
    }

    private var unlockedStarsEarned: Int {
        guard unlockedDesignedCount > 0 else { return 0 }
        return (1...unlockedDesignedCount).reduce(0) { acc, lvl in
            acc + gameState.stars(for: lvl)
        }
    }

    private var unlockedCoinsEarned: Int {
        guard unlockedDesignedCount > 0 else { return 0 }
        return (1...unlockedDesignedCount).reduce(0) { acc, lvl in
            acc + gameState.coinsCollected(for: lvl).count
        }
    }

    private var maxStarsAvailable: Int { unlockedDesignedCount * 3 }
    private var maxCoinsAvailable: Int { unlockedDesignedCount * 3 }

    private var starPercent: Double {
        maxStarsAvailable > 0
            ? Double(unlockedStarsEarned) / Double(maxStarsAvailable) : 0
    }
    private var coinPercent: Double {
        maxCoinsAvailable > 0
            ? Double(unlockedCoinsEarned) / Double(maxCoinsAvailable) : 0
    }

    /// Three-tier achievement nickname based on percent completion of a
    /// stat.  Below 34 % is "low" (entry-level encouragement), 34-66 % is
    /// "mid" (notable progress), 67 %+ is "high" (badge of honour).
    private static func starNickname(for pct: Double) -> String {
        if pct < 0.34 { return "Expansionist" }
        if pct < 0.67 { return "20 Mile Marcher" }
        return "Speed Demon"
    }

    private static func coinNickname(for pct: Double) -> String {
        if pct < 0.34 { return "Minimalist" }
        if pct < 0.67 { return "Coin Counter" }
        return "Economic Animal"
    }

    private var header: some View {
        HStack(spacing: 16) {
            progressStat(
                icon: "star.fill",
                tint: Color(red: 1.00, green: 0.84, blue: 0.30),
                label: "Stars",
                earned: unlockedStarsEarned,
                max:    maxStarsAvailable,
                percent: starPercent,
                nickname: Self.starNickname(for: starPercent)
            )
            progressStat(
                icon: "circle.fill",
                tint: Color(red: 0.93, green: 0.65, blue: 0.10),
                label: "Coins",
                earned: unlockedCoinsEarned,
                max:    maxCoinsAvailable,
                percent: coinPercent,
                nickname: Self.coinNickname(for: coinPercent)
            )
        }
        .padding(.top, 8)
    }

    /// One progress stat card: icon + label header, "earned / max" main row,
    /// percentage line, threshold-based achievement nickname.
    private func progressStat(
        icon: String,
        tint: Color,
        label: String,
        earned: Int,
        max: Int,
        percent: Double,
        nickname: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // The "Coins" row uses the shared CoinIcon graphic so the
                // currency reads identically here, on the home pill, in
                // the shop, and on the level-clear screen.  Stars stay
                // as their SF Symbol — they're a separate award concept.
                if label == "Coins" {
                    CoinIcon(size: 16)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .kerning(1.5)
                    .foregroundStyle(Color(white: 0.55))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(earned)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("/ \(max)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.45))
            }
            Text(String(format: "%.0f%%", percent * 100))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(nickname)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.78))
                .italic()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.14))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(earned) of \(max) \(label.lowercased()) earned. " +
            String(format: "%.0f percent. ", percent * 100) +
            "Ranked \(nickname)."
        )
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(1...totalLevels, id: \.self) { level in
                cell(for: level)
            }
        }
    }

    @ViewBuilder
    private func cell(for level: Int) -> some View {
        let unlocked = gameState.isUnlocked(level)
        let stars    = gameState.stars(for: level)
        let coins    = gameState.coinsCollected(for: level)
        // For cells, preview the player's currently-equipped background
        // theme rather than the (now obsolete) per-level theme bands.
        let floor    = gameState.equippedFloor
        let pit      = gameState.equippedPit
        let isDesigned = level <= LevelLayout.handCrafted.count

        if unlocked && isDesigned {
            Button {
                // Set currentLevel BEFORE pushing the game so BallGameView
                // reads the right course on first appear.
                gameState.currentLevel = level
                nav.goToGame()
            } label: {
                cellContent(level: level, stars: stars, coins: coins,
                            floor: floor, pit: pit, unlocked: true, designed: true)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(level: level, stars: stars, coins: coins.count, locked: false, designed: true))
            .accessibilityHint("Double-tap to play.")
        } else {
            cellContent(level: level, stars: stars, coins: coins,
                        floor: floor, pit: pit, unlocked: unlocked, designed: isDesigned)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(level: level, stars: stars, coins: coins.count, locked: !unlocked, designed: isDesigned))
        }
    }

    private func accessibilityLabel(level: Int, stars: Int, coins: Int, locked: Bool, designed: Bool) -> String {
        if locked  { return "Level \(level), locked" }
        if !designed { return "Level \(level), coming soon" }
        let tier = DifficultyTier.tier(for: level).displayName
        return "Level \(level), \(tier), \(stars) of 3 stars, \(coins) of 3 coins collected"
    }

    private func cellContent(level: Int, stars: Int, coins: Set<Int>,
                             floor: Floor, pit: Pit,
                             unlocked: Bool, designed: Bool) -> some View {
        let canPlay = unlocked && designed
        let tier = DifficultyTier.tier(for: level)
        return VStack(spacing: 6) {
            ZStack {
                // Floor color swatch as background hint
                RoundedRectangle(cornerRadius: 12)
                    .fill(canPlay ? floor.color : Color(white: 0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(white: 0.28), lineWidth: 1)
                    )

                if !canPlay {
                    if !designed && unlocked {
                        // Designed-but-not-yet-shipped (coming soon)
                        VStack(spacing: 3) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(Color(white: 0.5))
                            Text("Soon")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(white: 0.5))
                        }
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(white: 0.4))
                    }
                } else {
                    Text("\(level)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(pit.color)

                    // Tier badge — small colored dot in the top-right of the cell
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(tier.color)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.25), lineWidth: 0.5)
                                )
                                .padding(5)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 70)

            // Stars row
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Image(systemName: i < stars ? "star.fill" : "star")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(
                            i < stars
                                ? Color(red: 1.00, green: 0.84, blue: 0.30)
                                : Color(white: 0.30)
                        )
                }
            }

            // Coins row
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(
                            coins.contains(i)
                                ? Color(red: 0.93, green: 0.65, blue: 0.10)
                                : Color(white: 0.22)
                        )
                        .frame(width: 7, height: 7)
                }
            }

            // Best time — shown only for played levels.  Fixed-height
            // placeholder ensures all cells in a row line up vertically.
            Group {
                if let best = gameState.time(for: level), canPlay {
                    Text(String(format: "%.2fs", best))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.62))
                } else {
                    Text(" ")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
            }
        }
        .padding(.vertical, 6)
        .opacity(canPlay ? 1.0 : 0.7)
    }

}

#Preview {
    NavigationStack {
        LevelSelectView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
