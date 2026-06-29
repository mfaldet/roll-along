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
    @State private var diffFilter:    DiffFilter      = .overall
    @State private var showBoardPicker = false

    /// Which Roll Along stat the board ranks by.  (Speed was dropped — we lean
    /// on stars for skill.)  Only changes ranking — never which columns show.
    private enum SortKey: String, CaseIterable, Identifiable {
        case level = "Level", stars = "Stars", coins = "Coins"
        var id: String { rawValue }
    }

    /// Difficulty filter for the competitive boards.  `.overall` is the combined
    /// all-difficulty totals (today's aggregate); the others rank by that
    /// difficulty's per-(game,difficulty) `minigame_scores` rows.
    private enum DiffFilter: String, CaseIterable, Identifiable {
        case overall = "Overall", easy = "Easy", normal = "Normal", hard = "Hard"
        var id: String { rawValue }
        /// nil for Overall (aggregate); else the MinigameDifficulty rawValue.
        var key: String? {
            switch self {
            case .overall: return nil
            case .easy:    return "easy"
            case .normal:  return "normal"
            case .hard:    return "hard"
            }
        }
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
        .onChange(of: selectedBoard) { _, board in
            // Difficulty only applies to competitive boards; reset it otherwise.
            if board.competitiveModeID == nil { diffFilter = .overall }
            rows = []
            Task { await load() }
        }
        .onChange(of: diffFilter) { _, _ in
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
                statusStrip
                Divider().overlay(Self.hairline)
                columnHeader
                Divider().overlay(Self.hairline)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(displayRows.enumerated()), id: \.element.id) { index, profile in
                            leaderboardRow(rank: index + 1, profile: profile)
                        }
                    }
                }
                .refreshable { await load() }
            }
            .background(Self.panelFill)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(white: 0.18), lineWidth: 1))
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    /// Ranked-player count shown in the status strip.
    private var rankedCount: Int { displayRows.count }

    @ViewBuilder
    private var statusStrip: some View {
        HStack {
            HStack(spacing: 5) {
                Circle().fill(Self.starTint).frame(width: 6, height: 6)
                Text("\(rankedCount) RANKED")
                    .font(Self.headerFont)
                    .foregroundStyle(Color(white: 0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
    /// Highlight for the signed-in player's own row (scoreboard green).
    private static let meAccent = Color(red: 0.28, green: 0.82, blue: 0.52)
    private static let panelFill = Color(white: 0.11)
    private static let hairline  = Color(white: 0.16)
    /// Shared surface for the filter pill + sort segmented control.
    private static let controlTrack  = Color(white: 0.12)
    private static let controlBorder = Color(white: 0.22)
    private static let controlPill   = Color(white: 0.22)   // selected segment

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
            Text("#").font(Self.headerFont).foregroundStyle(Color(white: 0.40))
                .frame(width: 30)
            Text("PLAYER").font(Self.headerFont).foregroundStyle(Color(white: 0.40))
            Spacer(minLength: 0)
            ForEach(columns) { col in
                Text(col.id)
                    .font(Self.headerFont)
                    .foregroundStyle(col.highlighted ? Self.starTint : Color(white: 0.40))
                    .frame(width: col.width, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private static let headerFont = Font.system(size: 10, weight: .heavy, design: .rounded)

    private func leaderboardRow(rank: Int, profile: PlayerProfile) -> some View {
        let isMe = (profile.id == myId)
        let cols = columns

        return HStack(spacing: 12) {
            rankBadge(rank)

            // The own-row is already cued by the green tint + left bar and the
            // player's own nickname, so no "YOU" badge is needed.
            Text(profile.displayName.isEmpty ? "Climber" : profile.displayName)
                .font(.system(.subheadline, design: .rounded).weight(isMe ? .heavy : .semibold))
                .foregroundStyle(isMe ? .white : Color(white: 0.92))
                .lineLimit(1)

            Spacer(minLength: 0)

            ForEach(cols) { col in
                col.cell(profile).frame(width: col.width, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isMe ? Self.meAccent.opacity(0.10) : Color.clear)
        .overlay(alignment: .leading) {
            if isMe { Rectangle().fill(Self.meAccent).frame(width: 3) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Self.hairline).frame(height: 0.5).padding(.leading, 14)
        }
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

    // MARK: - Board picker (game filter)

    /// Per-board usage for the local player — drives the filter's "most played
    /// first" ordering.  Competitive boards use real play counts; Pinball/Zen
    /// have no play counter, so a binary "played" signal is used (ties fall back
    /// to alphabetical).  Roll Along uses climb level.
    private func boardUsage(_ b: LeaderboardBoard) -> Int {
        if let mode = b.competitiveModeID {
            return gameState.minigameDifficultyPlays
                .filter { $0.key.hasPrefix(mode + "|") }
                .reduce(0) { $0 + $1.value }
        }
        switch b {
        case .rollAlong: return gameState.currentLevel
        case .pinball:   return gameState.pinballBest > 0 ? 1 : 0
        case .zenGarden: return gameState.zenSeconds   > 0 ? 1 : 0
        default:         return 0
        }
    }

    /// Boards in one category, most-played first; not-yet-played games sink to
    /// the bottom in alphabetical order.
    private func boards(in category: BoardCategory) -> [LeaderboardBoard] {
        LeaderboardBoard.allCases
            .filter { $0.category == category }
            .sorted { a, b in
                let ua = boardUsage(a), ub = boardUsage(b)
                let pa = ua > 0, pb = ub > 0
                if pa != pb     { return pa }          // played before not-played
                if pa, ua != ub { return ua > ub }     // both played: most used first
                return a.title < b.title                // tie / unplayed: alphabetical
            }
    }

    /// Grouped, bigger-named game picker presented from the filter pill.
    private var boardPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(BoardCategory.allCases, id: \.self) { cat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cat.title.uppercased())
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .kerning(1.5)
                            .foregroundStyle(Self.starTint)
                            .padding(.bottom, 6)
                        ForEach(boards(in: cat)) { b in
                            Button {
                                selectedBoard = b
                                showBoardPicker = false
                            } label: {
                                HStack {
                                    Text(b.title)
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(b == selectedBoard ? Self.starTint : .white)
                                    Spacer(minLength: 8)
                                    if b == selectedBoard {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(Self.starTint)
                                    }
                                }
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(white: 0.07).ignoresSafeArea())
    }

    // MARK: - Header (game filter + sort)

    private var leaderboardHeader: some View {
        VStack(spacing: 12) {
            // Game filter — opens a grouped picker (bigger names, sorted by
            // category then by how much the player has played each game).
            Button { showBoardPicker = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Self.starTint)
                    Text(selectedBoard.title)
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(white: 0.5))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(Self.controlTrack)
                        .overlay(Capsule().stroke(Self.controlBorder, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showBoardPicker) {
                boardPicker
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }

            // Difficulty selector — competitive boards only, sits above the sort.
            // Overall = the combined totals; Easy/Normal/Hard = per-difficulty.
            if selectedBoard.competitiveModeID != nil {
                HStack(spacing: 0) {
                    ForEach(DiffFilter.allCases) { d in
                        diffSegment(d)
                    }
                }
                .padding(3)
                .background(
                    Capsule().fill(Self.controlTrack)
                        .overlay(Capsule().stroke(Self.controlBorder, lineWidth: 1))
                )
            }

            // Sort selector — a segmented control (Roll Along board only),
            // matching the filter pill's surface.
            if selectedBoard == .rollAlong {
                HStack(spacing: 0) {
                    ForEach(SortKey.allCases) { key in
                        sortSegment(key)
                    }
                }
                .padding(3)
                .background(
                    Capsule().fill(Self.controlTrack)
                        .overlay(Capsule().stroke(Self.controlBorder, lineWidth: 1))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    /// One segment of the sort selector: an elevated pill with gold text when
    /// active, plain gray otherwise.
    private func sortSegment(_ key: SortKey) -> some View {
        let active = (sortKey == key)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { sortKey = key }
        } label: {
            Text(key.rawValue)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(active ? Self.starTint : Color(white: 0.55))
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? Self.controlPill : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    /// One segment of the difficulty selector (Overall / Easy / Normal / Hard),
    /// full-width so the four share the row.
    private func diffSegment(_ d: DiffFilter) -> some View {
        let active = (diffFilter == d)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { diffFilter = d }
        } label: {
            Text(d.rawValue)
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(active ? Self.starTint : Color(white: 0.55))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? Self.controlPill : Color.clear)
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
            if let medal {
                Circle().fill(medal).frame(width: 28, height: 28)
                Text("\(rank)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .monospacedDigit()
            } else {
                Text("\(rank)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.45))
                    .monospacedDigit()
            }
        }
        .frame(width: 30)
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
            if let game = selectedBoard.competitiveModeID, let diff = diffFilter.key {
                // Per-(game, difficulty) board from the minigame_scores table.
                rows = try await SocialClient.shared.fetchMinigameDifficultyLeaderboard(
                    game: game, difficulty: diff)
            } else {
                rows = try await SocialClient.shared.fetchLeaderboard(order: selectedBoard.order)
            }
        } catch {
            errorText = "The ranking server is unreachable right now. Pull to refresh or try again."
        }
        isLoading = false
    }
}
