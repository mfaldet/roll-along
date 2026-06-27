import SwiftUI

// ===========================================================================
// LeaderboardView — the global climb ranking.
//
// Reads the public `players` table via SocialClient.fetchLeaderboard (ordered
// climb_level desc, then total_stars desc) and renders a ranked list.  The
// signed-in player's own row is highlighted so they can spot themselves.
//
// Requires a Supabase session (Sign in with Apple).  When signed out it shows
// a friendly prompt rather than an empty list — the leaderboard is the
// competitive pillar's hook, so we explain the payoff and route to Settings.
//
// SAFE BY CONSTRUCTION: read-only.  It mutates no local state and writes
// nothing to the server; the worst case on a paused/unreachable backend is a
// retryable error banner.
// ===========================================================================

struct LeaderboardView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator
    @ObservedObject private var auth = AppleAuthManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var rows:      [PlayerProfile] = []
    @State private var isLoading  = false
    @State private var errorText: String?

    @State private var sortKey:       SortKey         = .level
    @State private var selectedBoard: LeaderboardBoard = .rollAlong

    /// Which Roll Along stat the board ranks by.  (Speed was dropped — we lean
    /// on stars for skill.)  Only changes ranking — never which columns show.
    private enum SortKey: String, CaseIterable, Identifiable {
        case level = "Level", stars = "Stars", coins = "Coins"
        var id: String { rawValue }
    }

    // The set of boards (identity / ranking order / "has played") lives in the
    // shared `LeaderboardBoard` so the profile "Player Ranks" section stays in
    // lockstep with this picker.

    /// Rows re-sorted client-side by the active key (Roll Along only).
    private var sortedRows: [PlayerProfile] {
        switch sortKey {
        case .level: return rows.sorted { ($0.climbLevel, $0.totalStars) > ($1.climbLevel, $1.totalStars) }
        case .stars: return rows.sorted { ($0.totalStars, $0.climbLevel) > ($1.totalStars, $1.climbLevel) }
        case .coins: return rows.sorted { (($0.coinsCollected ?? 0), $0.climbLevel) > (($1.coinsCollected ?? 0), $1.climbLevel) }
        }
    }

    /// What the list shows: Roll Along uses the client sort; every other board
    /// keeps the server order (already ranked) and drops players who haven't
    /// played that game yet.
    private var displayRows: [PlayerProfile] {
        selectedBoard == .rollAlong ? sortedRows : rows.filter { selectedBoard.hasPlayed($0) }
    }

    private var myId: UUID? { SocialClient.shared.currentUserId }

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            if !auth.isSignedIn {
                signedOutState
            } else {
                VStack(spacing: 0) {
                    leaderboardHeader
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .task { await load() }
        .onChange(of: selectedBoard) { _, _ in
            rows = []
            Task { await load() }
        }
    }

    // MARK: - Signed-in content

    @ViewBuilder
    private var content: some View {
        if isLoading && rows.isEmpty {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
        } else if let errorText, rows.isEmpty {
            errorState(errorText)
        } else if displayRows.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                columnHeader
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(displayRows.enumerated()), id: \.element.id) { index, profile in
                            leaderboardRow(rank: index + 1, profile: profile)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .refreshable { await load() }
            }
        }
    }

    // MARK: - Column model
    //
    // Every board renders the SAME column set for its game on every row — the
    // sort/order only changes ranking, never which columns show.  The header row
    // and the data rows both iterate `columns`, so they stay aligned by width.

    private struct StatColumn: Identifiable {
        let id: String                       // header label, also the row id
        let width: CGFloat
        let highlighted: Bool                // the active ranking column
        let cell: (PlayerProfile) -> AnyView
    }

    // Stat tints, shared by header accents and row cells.
    private static let starTint = Color(red: 1.00, green: 0.84, blue: 0.30)
    private static let pinTint  = Color(red: 0.30, green: 0.62, blue: 1.00)
    private static let zenTint  = Color(red: 0.40, green: 0.82, blue: 0.55)
    private static let winTint  = Color(red: 1.00, green: 0.81, blue: 0.30)

    /// The columns shown on every row of the current board.
    private var columns: [StatColumn] {
        switch selectedBoard {
        case .rollAlong:
            return [
                StatColumn(id: "LVL", width: 46, highlighted: sortKey == .level) { p in
                    AnyView(self.plainCell("\(p.climbLevel)")) },
                StatColumn(id: "STARS", width: 56, highlighted: sortKey == .stars) { p in
                    AnyView(self.iconCell(system: "star.fill", tint: Self.starTint, value: "\(p.totalStars)")) },
                StatColumn(id: "COINS", width: 60, highlighted: sortKey == .coins) { p in
                    AnyView(self.coinCell(p.coinsCollected ?? 0)) },
            ]
        case .pinball:
            return [ StatColumn(id: "BEST", width: 92, highlighted: true) { p in
                AnyView(self.iconCell(system: "gamecontroller.fill", tint: Self.pinTint,
                                      value: (p.pinballBest ?? 0).formatted())) } ]
        case .zenGarden:
            return [ StatColumn(id: "TIME", width: 92, highlighted: true) { p in
                AnyView(self.iconCell(system: "leaf.fill", tint: Self.zenTint,
                                      value: LeaderboardBoard.zenText(p.zenSeconds ?? 0))) } ]
        default:
            // Competitive boards: Wins (ranking) + Best.
            let mode = selectedBoard.competitiveModeID ?? ""
            return [
                StatColumn(id: "WINS", width: 54, highlighted: true) { p in
                    AnyView(self.iconCell(system: "trophy.fill", tint: Self.winTint,
                                          value: "\(p.competitiveWins(mode))")) },
                StatColumn(id: "BEST", width: 74, highlighted: false) { p in
                    AnyView(self.bestCell(LeaderboardBoard.bestText(mode, p.competitiveBest(mode)))) },
            ]
        }
    }

    /// Column titles above the list — aligned to the row columns by width.
    private var columnHeader: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 34, height: 1)          // rank-badge gutter
            Text("PLAYER").font(Self.headerFont).foregroundStyle(Color(white: 0.45))
            Spacer(minLength: 0)
            ForEach(columns) { col in
                Text(col.id)
                    .font(Self.headerFont)
                    .foregroundStyle(col.highlighted ? Self.starTint : Color(white: 0.45))
                    .frame(width: col.width)
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
    }

    private static let headerFont = Font.system(size: 10, weight: .heavy, design: .rounded)

    private func leaderboardRow(rank: Int, profile: PlayerProfile) -> some View {
        let isMe = (profile.id == myId)
        let cols = columns

        return HStack(spacing: 12) {
            rankBadge(rank)

            Text(profile.displayName.isEmpty ? "Climber" : profile.displayName)
                .font(.system(.body, design: .rounded).weight(isMe ? .bold : .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            ForEach(cols) { col in
                col.cell(profile).frame(width: col.width)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isMe ? Color(red: 0.20, green: 0.50, blue: 0.96).opacity(0.18)
                           : Color(white: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isMe ? Color(red: 0.30, green: 0.58, blue: 0.98).opacity(0.7)
                                     : Color.clear,
                                lineWidth: 1.2)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(rank: rank, profile: profile, isMe: isMe))
    }

    /// A spoken summary covering every column on the current board.
    private func rowAccessibilityLabel(rank: Int, profile: PlayerProfile, isMe: Bool) -> String {
        let name = profile.displayName.isEmpty ? "Climber" : profile.displayName
        var parts = ["Rank \(rank). \(name)"]
        switch selectedBoard {
        case .rollAlong:
            parts.append("level \(profile.climbLevel)")
            parts.append("\(profile.totalStars) stars")
            parts.append("\(profile.coinsCollected ?? 0) coins")
        case .pinball:
            parts.append("best \(profile.pinballBest ?? 0)")
        case .zenGarden:
            parts.append("\(LeaderboardBoard.zenText(profile.zenSeconds ?? 0)) in the garden")
        default:
            let mode = selectedBoard.competitiveModeID ?? ""
            parts.append("\(profile.competitiveWins(mode)) wins")
            parts.append("best \(LeaderboardBoard.bestText(mode, profile.competitiveBest(mode)))")
        }
        return parts.joined(separator: ", ") + "." + (isMe ? " This is you." : "")
    }

    // MARK: - Cell builders

    private func plainCell(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
    }
    private func bestCell(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color(white: 0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
    private func iconCell(system: String, tint: Color, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: system).font(.system(size: 10)).foregroundStyle(tint)
            Text(value).font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color(white: 0.82)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
    private func coinCell(_ v: Int) -> some View {
        HStack(spacing: 3) {
            CoinIcon(size: 12)
            Text("\(v)").font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color(white: 0.82)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // Stat formatting (zen time, competitive best) is shared with the profile
    // via `LeaderboardBoard`'s static helpers — see Self → LeaderboardBoard.

    // MARK: - Header (game filter + sort)

    private var leaderboardHeader: some View {
        VStack(spacing: 12) {
            // Game filter — a dropdown sitting just under the nav title.
            Menu {
                ForEach(LeaderboardBoard.allCases) { g in
                    Button { selectedBoard = g } label: {
                        if selectedBoard == g {
                            Label(g.rawValue, systemImage: "checkmark")
                        } else {
                            Text(g.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedBoard.title)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(white: 0.6))
                }
            }

            // Sort toggles — only meaningful for the Roll Along board.
            if selectedBoard == .rollAlong {
                HStack(spacing: 8) {
                    ForEach(SortKey.allCases) { key in
                        sortChip(key)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private func sortChip(_ key: SortKey) -> some View {
        let active = (sortKey == key)
        return Button { sortKey = key } label: {
            Text(key.rawValue)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(active ? .black : Color(white: 0.72))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active
                        ? Color(red: 1.00, green: 0.84, blue: 0.30)
                        : Color(white: 0.16))
                )
        }
        .buttonStyle(.plain)
    }

    /// Medal disc for the top 3, plain numeral otherwise.
    private func rankBadge(_ rank: Int) -> some View {
        let medal: Color? = {
            switch rank {
            case 1:  return Color(red: 1.00, green: 0.81, blue: 0.30)  // gold
            case 2:  return Color(red: 0.80, green: 0.83, blue: 0.88)  // silver
            case 3:  return Color(red: 0.80, green: 0.55, blue: 0.34)  // bronze
            default: return nil
            }
        }()

        return ZStack {
            Circle()
                .fill(medal ?? Color(white: 0.20))
                .frame(width: 34, height: 34)
            Text("\(rank)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(medal == nil ? Color(white: 0.7) : .black)
                .monospacedDigit()
        }
    }

    // MARK: - Empty / error / signed-out states

    private var emptyState: some View {
        let isClimb = (selectedBoard == .rollAlong)
        return messageBlock(
            icon: "trophy",
            title: isClimb ? "No climbers yet" : "No scores yet",
            message: isClimb
                ? "Be the first on the board — clear a level to post your rank."
                : "Be the first on the board — play a round of \(selectedBoard.title) to post your rank.",
            actionTitle: nil,
            action: nil
        )
    }

    private func errorState(_ text: String) -> some View {
        messageBlock(
            icon: "wifi.exclamationmark",
            title: "Couldn't load the leaderboard",
            message: text,
            actionTitle: "Try Again",
            action: { Task { await load() } }
        )
    }

    private var signedOutState: some View {
        messageBlock(
            icon: "trophy.fill",
            title: "Climb the global board",
            message: "Sign in with Apple to see where you rank against climbers worldwide, join clans, and send friends extra lives. Your level progress is saved on this device either way.",
            actionTitle: "Sign in from Settings",
            action: { nav.goToSettings() }
        )
    }

    private func messageBlock(icon: String,
                              title: String,
                              message: String,
                              actionTitle: String?,
                              action: (() -> Void)?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Color(white: 0.4))
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color(white: 0.55))
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Color(red: 0.20, green: 0.50, blue: 0.96))
                        )
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Data

    private func load() async {
        guard auth.isSignedIn else { return }
        isLoading = true
        errorText = nil
        do {
            rows = try await SocialClient.shared.fetchLeaderboard(order: selectedBoard.order)
        } catch {
            errorText = "The ranking server is unreachable right now. Pull to refresh or try again."
        }
        isLoading = false
    }
}
