import SwiftUI

/// Grid view showing all 100 hand-crafted levels with star/coin progress.
/// Tapping a cleared (or next-unlocked) level pushes BallGameView for that
/// level.  Locked levels show a lock and don't navigate.
struct LevelSelectView: View {
    @EnvironmentObject var gameState: GameState
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
                Button { dismiss() } label: {
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

    private var header: some View {
        HStack(spacing: 16) {
            statBlock(
                icon: "star.fill",
                tint: Color(red: 1.00, green: 0.84, blue: 0.30),
                value: "\(gameState.totalStars)",
                cap:   "/ \(totalLevels * 3)",
                label: "Stars"
            )
            statBlock(
                icon: "circle.fill",
                tint: Color(red: 0.93, green: 0.65, blue: 0.10),
                value: "\(gameState.totalCoins)",
                cap:   "/ \(totalLevels * 3)",
                label: "Coins"
            )
        }
        .padding(.top, 8)
    }

    private func statBlock(icon: String, tint: Color, value: String, cap: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .kerning(1.5)
                    .foregroundStyle(Color(white: 0.55))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(cap)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.14))
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
        let theme    = Theme.forLevel(level)
        let isDesigned = level <= LevelLayout.handCrafted.count

        if unlocked && isDesigned {
            NavigationLink(destination: BallGameView()) {
                cellContent(level: level, stars: stars, coins: coins,
                            theme: theme, unlocked: true, designed: true)
            }
            .buttonStyle(.plain)
            // Set currentLevel BEFORE navigation so BallGameView reads
            // the right course on first appear.  Done via tap gesture
            // rather than inside the destination closure to avoid
            // state-mutation-during-view-update warnings.
            .simultaneousGesture(TapGesture().onEnded {
                gameState.currentLevel = level
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(level: level, stars: stars, coins: coins.count, locked: false, designed: true))
            .accessibilityHint("Double-tap to play.")
        } else {
            cellContent(level: level, stars: stars, coins: coins,
                        theme: theme, unlocked: unlocked, designed: isDesigned)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(level: level, stars: stars, coins: coins.count, locked: !unlocked, designed: isDesigned))
        }
    }

    private func accessibilityLabel(level: Int, stars: Int, coins: Int, locked: Bool, designed: Bool) -> String {
        if locked  { return "Level \(level), locked" }
        if !designed { return "Level \(level), coming soon" }
        return "Level \(level), \(stars) of 3 stars, \(coins) of 3 coins collected"
    }

    private func cellContent(level: Int, stars: Int, coins: Set<Int>,
                             theme: Theme, unlocked: Bool, designed: Bool) -> some View {
        let canPlay = unlocked && designed
        return VStack(spacing: 6) {
            ZStack {
                // Theme color swatch as background hint
                RoundedRectangle(cornerRadius: 12)
                    .fill(canPlay ? theme.floorColor : Color(white: 0.18))
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
                        .foregroundStyle(theme.holeColor)
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
        }
        .padding(.vertical, 6)
        .opacity(canPlay ? 1.0 : 0.7)
    }

}

#Preview {
    NavigationStack {
        LevelSelectView().environmentObject(GameState())
    }
}
