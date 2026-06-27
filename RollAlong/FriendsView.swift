import SwiftUI

// ===========================================================================
// FriendsView — the social pillar's home: gifts, friend requests, friends,
// and a search box to add new ones.  All four sections read & write the
// `friendships` / `life_gifts` / `players` tables through SocialClient, so
// every action is RLS-scoped to the signed-in player.
//
// Sections (top to bottom, each shown only when it has content):
//   • Gift inbox      — unclaimed lives someone sent you.  Claim credits the
//                       lives on-device via GameState.addLives AFTER the
//                       server marks the gift claimed, so a failed write can
//                       never hand out free lives.
//   • Friend requests — incoming pending edges; accept or decline.
//   • Friends         — accepted edges; send each one a life.
//   • Add friends     — search players by name, send a request.
//
// Requires a Supabase session (Sign in with Apple).  Signed out, it shows the
// same friendly prompt as the leaderboard and routes to Settings.
//
// SAFE BY CONSTRUCTION: additive.  Until HomeView routes to it, nothing here
// runs; the worst case on an unreachable backend is a retryable error banner.
// ===========================================================================

struct FriendsView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator
    @ObservedObject private var auth = AppleAuthManager.shared
    @Environment(\.dismiss) var dismiss

    // Server state
    @State private var gifts:    [LifeGift] = []
    @State private var edges:    [Friendship] = []
    @State private var profiles: [UUID: PlayerProfile] = [:]   // id → resolved profile

    // Search
    @State private var searchTerm    = ""
    @State private var searchResults: [PlayerProfile] = []
    @State private var isSearching   = false

    // Lifecycle / feedback
    @State private var isLoading  = false
    @State private var errorText: String?
    @State private var busyIds:      Set<UUID> = []   // rows with an action in flight
    @State private var sentLifeIds:  Set<UUID> = []   // friends gifted this session
    @State private var banner: String?

    private var myId: UUID? { SocialClient.shared.currentUserId }

    // MARK: - Derived lists

    private var incoming: [Friendship] {
        guard let me = myId else { return [] }
        return edges.filter { $0.isIncomingPending(for: me) }
    }
    private var friends: [Friendship] {
        edges.filter { $0.status == "accepted" }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            if !auth.isSignedIn {
                signedOutState
            } else {
                signedInContent
            }

            if let banner {
                bannerView(banner)
            }
        }
        .navigationTitle("Friends")
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
    }

    // MARK: - Signed-in content

    @ViewBuilder
    private var signedInContent: some View {
        if isLoading && edges.isEmpty && gifts.isEmpty {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
        } else {
            ScrollView {
                VStack(spacing: 22) {
                    searchField

                    if searchTerm.isEmpty { inviteRow }

                    if !searchTerm.isEmpty {
                        searchSection
                    }

                    if let errorText, edges.isEmpty, gifts.isEmpty {
                        errorState(errorText)
                            .padding(.top, 40)
                    } else {
                        if !gifts.isEmpty    { giftSection }
                        if !incoming.isEmpty { requestSection }
                        if !friends.isEmpty  { friendSection }

                        if gifts.isEmpty, incoming.isEmpty, friends.isEmpty,
                           searchTerm.isEmpty {
                            emptyState.padding(.top, 36)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await load() }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(white: 0.5))
            TextField("", text: $searchTerm,
                      prompt: Text("Find players by name"))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
            if !searchTerm.isEmpty {
                Button {
                    searchTerm = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(white: 0.45))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14))
        )
    }

    // MARK: - Invite (share a deep link so a friend can add you)

    /// A `rollalong://player/<my id>` link a friend taps to open your profile
    /// and add you back.  Only shown when signed in (so there's an id to share).
    @ViewBuilder
    private var inviteRow: some View {
        if let me = myId {
            let link = URL(string: "rollalong://player/\(me.uuidString)")!
            let who  = gameState.playerName.isEmpty ? "me" : gameState.playerName
            ShareLink(item: link,
                      subject: Text("Add me on Roll Along"),
                      message: Text("Add \(who) on Roll Along so we can send each other lives! Tap: \(link.absoluteString)")) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Invite a friend")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Share a link so they can add you")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color(white: 0.6))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.45))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.20, green: 0.50, blue: 0.96).opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(red: 0.20, green: 0.50, blue: 0.96).opacity(0.45), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Search", "person.crop.circle.badge.plus")
            if isSearching {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
            } else if searchResults.isEmpty {
                Text("No players match “\(searchTerm)”.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Color(white: 0.5))
                    .padding(.vertical, 6)
            } else {
                ForEach(searchResults) { profile in
                    searchRow(profile)
                }
            }
        }
    }

    private func searchRow(_ profile: PlayerProfile) -> some View {
        personCard(profile) {
            switch relationship(with: profile.id) {
            case .friend:
                tag("Friends", .green)
            case .outgoing:
                tag("Requested", Color(white: 0.5))
            case .incoming:
                actionButton("Accept", filled: true, busy: busyIds.contains(profile.id)) {
                    if let edge = edges.first(where: {
                        $0.isIncomingPending(for: myId ?? UUID()) &&
                        $0.otherId(than: myId ?? UUID()) == profile.id
                    }) {
                        await accept(edge)
                    }
                }
            case .unrelated:
                actionButton("Add", filled: true, busy: busyIds.contains(profile.id)) {
                    await sendRequest(to: profile)
                }
            }
        }
    }

    // MARK: - Gift inbox

    @ViewBuilder
    private var giftSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Life gifts", "heart.fill")
            ForEach(gifts) { gift in
                giftRow(gift)
            }
        }
    }

    private func giftRow(_ gift: LifeGift) -> some View {
        let sender = profiles[gift.senderId]
        let name   = sender?.displayName.nonEmpty ?? "A climber"
        return HStack(spacing: 14) {
            avatar(name, tint: Color(red: 0.95, green: 0.32, blue: 0.45))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(name) sent you")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.95, green: 0.32, blue: 0.45))
                    Text("\(gift.amount) life\(gift.amount == 1 ? "" : "s")")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(white: 0.6))
                }
            }
            Spacer()
            actionButton("Claim", filled: true, busy: busyIds.contains(gift.id)) {
                await claim(gift)
            }
        }
        .cardBackground()
    }

    // MARK: - Incoming requests

    @ViewBuilder
    private var requestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Friend requests", "person.crop.circle.badge.questionmark")
            ForEach(incoming) { edge in
                requestRow(edge)
            }
        }
    }

    private func requestRow(_ edge: Friendship) -> some View {
        let id   = edge.otherId(than: myId ?? UUID())
        let prof = profiles[id]
        return personCard(prof) {
            HStack(spacing: 8) {
                actionButton("Accept", filled: true, busy: busyIds.contains(edge.id)) {
                    await accept(edge)
                }
                actionButton("Decline", filled: false, busy: busyIds.contains(edge.id)) {
                    await remove(edge)
                }
            }
        }
    }

    // MARK: - Friends

    @ViewBuilder
    private var friendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Friends", "person.2.fill")
            ForEach(friends) { edge in
                friendRow(edge)
            }
        }
    }

    private func friendRow(_ edge: Friendship) -> some View {
        let id   = edge.otherId(than: myId ?? UUID())
        let prof = profiles[id]
        let sent = sentLifeIds.contains(id)
        return personCard(prof) {
            if sent {
                tag("Sent ♥", Color(red: 0.95, green: 0.32, blue: 0.45))
            } else {
                actionButton("Send life", filled: true, busy: busyIds.contains(id)) {
                    await sendLife(to: id)
                }
            }
        }
    }

    // MARK: - Reusable person card

    /// Card with avatar + name + world, and a caller-supplied trailing control.
    private func personCard<Trailing: View>(
        _ profile: PlayerProfile?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let name  = profile?.displayName.nonEmpty ?? "Climber"
        let level = profile?.climbLevel ?? 1
        let world = World.world(for: max(1, level))
        return HStack(spacing: 14) {
            Button {
                if let profile { nav.goToPlayer(profile) }
            } label: {
                HStack(spacing: 14) {
                    avatar(name, tint: world.accent)
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(level)")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(world.accent.opacity(0.28))
                                    .overlay(Capsule().stroke(world.accent.opacity(0.6), lineWidth: 1))
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(profile == nil)
            Spacer(minLength: 8)
            trailing()
        }
        .cardBackground()
    }

    private func avatar(_ name: String, tint: Color) -> some View {
        ZStack {
            Circle().fill(tint.opacity(0.28)).frame(width: 38, height: 38)
            Text(String(name.first ?? "?").uppercased())
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Small controls

    private func sectionHeader(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(white: 0.5))
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color(white: 0.5))
                .tracking(0.5)
            Spacer()
        }
    }

    /// A capsule action button.  While `busy`, it shows a spinner and disables.
    private func actionButton(_ title: String,
                              filled: Bool,
                              busy: Bool,
                              action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .opacity(busy ? 0 : 1)
                if busy {
                    ProgressView().tint(filled ? .white : Color(white: 0.7)).scaleEffect(0.7)
                }
            }
            .foregroundStyle(filled ? .white : Color(white: 0.75))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(filled ? Color(red: 0.20, green: 0.50, blue: 0.96)
                                 : Color(white: 0.20))
            )
        }
        .disabled(busy)
        .buttonStyle(.plain)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private func bannerView(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color(white: 0.18)))
                .padding(.bottom, 28)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
    }

    // MARK: - Empty / error / signed-out states

    private var emptyState: some View {
        messageBlock(
            icon: "person.2",
            title: "Climb together",
            message: "Search for friends by name to send each other extra lives. The more you climb, the higher you both rank.",
            actionTitle: nil, action: nil
        )
    }

    private func errorState(_ text: String) -> some View {
        messageBlock(
            icon: "wifi.exclamationmark",
            title: "Couldn't load friends",
            message: text,
            actionTitle: "Try Again",
            action: { Task { await load() } }
        )
    }

    private var signedOutState: some View {
        messageBlock(
            icon: "person.2.fill",
            title: "Play with friends",
            message: "Sign in with Apple to add friends, send each other extra lives, and climb the board together. Your progress is saved on this device either way.",
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
                        .background(Capsule().fill(Color(red: 0.20, green: 0.50, blue: 0.96)))
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Relationship lookup (for search rows)

    private enum Relationship { case unrelated, friend, outgoing, incoming }

    private func relationship(with id: UUID) -> Relationship {
        guard let me = myId else { return .unrelated }
        guard let edge = edges.first(where: { $0.otherId(than: me) == id }) else { return .unrelated }
        if edge.status == "accepted" { return .friend }
        if edge.isIncomingPending(for: me) { return .incoming }
        if edge.isOutgoingPending(for: me) { return .outgoing }
        return .unrelated
    }

    // MARK: - Data

    private func load() async {
        guard auth.isSignedIn, let me = myId else { return }
        isLoading = true
        errorText = nil
        do {
            async let giftsCall = SocialClient.shared.fetchUnclaimedGifts()
            async let edgesCall = SocialClient.shared.fetchFriendships()
            let loadedGifts = try await giftsCall
            let loadedEdges = try await edgesCall

            // Resolve every counterpart + gift sender to a profile in one call.
            var ids = Set<UUID>()
            for e in loadedEdges { ids.insert(e.otherId(than: me)) }
            for g in loadedGifts { ids.insert(g.senderId) }
            let resolved = try await SocialClient.shared.fetchProfiles(ids: Array(ids))

            var map: [UUID: PlayerProfile] = [:]
            for p in resolved { map[p.id] = p }

            gifts    = loadedGifts
            edges    = loadedEdges
            profiles = map
        } catch {
            errorText = "The social server is unreachable right now. Pull to refresh or try again."
        }
        isLoading = false
    }

    private func runSearch() async {
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { searchResults = []; return }
        isSearching = true
        do {
            let found = try await SocialClient.shared.searchPlayers(matching: term)
            // Merge any freshly-seen profiles into the cache so relationship
            // tags + names stay consistent if they're also friends.
            for p in found where profiles[p.id] == nil { profiles[p.id] = p }
            searchResults = found
        } catch {
            searchResults = []
            flash("Search failed — try again.")
        }
        isSearching = false
    }

    // MARK: - Actions

    private func claim(_ gift: LifeGift) async {
        busyIds.insert(gift.id)
        defer { busyIds.remove(gift.id) }
        do {
            // Server first: a failed write must never credit free lives.
            try await SocialClient.shared.claimGift(id: gift.id)
            gameState.addLives(gift.amount)
            gifts.removeAll { $0.id == gift.id }
            flash("Claimed \(gift.amount) life\(gift.amount == 1 ? "" : "s")!")
        } catch {
            flash("Couldn't claim that gift — try again.")
        }
    }

    private func accept(_ edge: Friendship) async {
        busyIds.insert(edge.id)
        defer { busyIds.remove(edge.id) }
        do {
            try await SocialClient.shared.acceptFriendRequest(id: edge.id)
            await load()
            flash("You're now friends!")
        } catch {
            flash("Couldn't accept — try again.")
        }
    }

    private func remove(_ edge: Friendship) async {
        busyIds.insert(edge.id)
        defer { busyIds.remove(edge.id) }
        do {
            try await SocialClient.shared.removeFriendship(id: edge.id)
            edges.removeAll { $0.id == edge.id }
        } catch {
            flash("Couldn't update — try again.")
        }
    }

    private func sendRequest(to profile: PlayerProfile) async {
        busyIds.insert(profile.id)
        defer { busyIds.remove(profile.id) }
        do {
            try await SocialClient.shared.sendFriendRequest(to: profile.id)
            await load()
            flash("Request sent to \(profile.displayName.nonEmpty ?? "climber").")
        } catch {
            flash("Couldn't send request — try again.")
        }
    }

    private func sendLife(to id: UUID) async {
        busyIds.insert(id)
        defer { busyIds.remove(id) }
        do {
            try await SocialClient.shared.sendLife(to: id, amount: 1)
            sentLifeIds.insert(id)
            flash("Life sent ♥")
        } catch {
            flash("Couldn't send a life — try again.")
        }
    }

    private func flash(_ message: String) {
        withAnimation { banner = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if banner == message { withAnimation { banner = nil } }
        }
    }
}

// MARK: - Helpers

private extension View {
    /// The standard rounded dark card used by every row in this screen.
    func cardBackground() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14)))
    }
}

private extension String {
    /// `nil` when the string is empty after trimming — lets callers fall back
    /// to a placeholder ("Climber") cleanly with `??`.
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
