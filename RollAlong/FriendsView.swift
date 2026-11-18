import SwiftUI
import UIKit

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

    // Friend codes.
    @State private var myFriendCode: String?
    @State private var codeInput = ""
    @State private var codeLookupBusy = false
    @State private var codeResult: PlayerProfile?

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

                    if searchTerm.isEmpty {
                        inviteRow
                        addByCodeSection
                    }

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

    // MARK: - Invite (share the invite message so a friend can add you)

    /// Shares `InviteMessage`: your friend code and the download link.  Only
    /// shown when signed in.
    @ViewBuilder
    private var inviteRow: some View {
        if myId != nil {
            // One shared message (`InviteMessage`), the same as Profile →
            // Share Profile: the friend code (typed on Friends → Add by code)
            // and the download link.
            ShareLink(item: InviteMessage.text(friendCode: myFriendCode)) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Invite a friend")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Send your friend code and a download link")
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

    // MARK: - Add by code

    /// Type a friend's code to find them exactly (names are not unique).
    @ViewBuilder
    private var addByCodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Add by code", "number")
            HStack(spacing: 10) {
                TextField("", text: $codeInput, prompt: Text("Friend code, e.g. AF3K-7MXY"))
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.search)
                    .onChange(of: codeInput) { _, new in
                        let filtered = FriendCode.filterTyping(new)
                        if filtered != new { codeInput = filtered }
                        codeResult = nil
                    }
                    .onSubmit { Task { await lookUpCode() } }
                Button { Task { await lookUpCode() } } label: {
                    if codeLookupBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text("Find")
                            .font(.system(.callout, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(FriendCode.normalize(codeInput) == nil || codeLookupBusy)
                .opacity(FriendCode.normalize(codeInput) == nil ? 0.4 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14)))
            if let codeResult {
                searchRow(codeResult)
            }
            if let myFriendCode {
                Text("Your code: \(FriendCode.display(myFriendCode))")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color(white: 0.55))
                    .textSelection(.enabled)
            }
        }
    }

    private func lookUpCode() async {
        guard let code = FriendCode.normalize(codeInput) else { return }
        if code == myFriendCode { flash("That's your own code."); return }
        codeLookupBusy = true
        defer { codeLookupBusy = false }
        do {
            if let found = try await SocialClient.shared.findPlayer(friendCode: code) {
                profiles[found.id] = profiles[found.id] ?? found
                codeResult = found
            } else {
                codeResult = nil
                flash("No player has the code \(FriendCode.display(code)).")
            }
        } catch {
            flash("Couldn't look up that code — try again.")
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
        let name   = sender?.displayName.nonEmpty ?? "A roller"
        return HStack(spacing: 14) {
            avatar(name, tint: Color(red: 0.95, green: 0.32, blue: 0.45))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    PlayerNameLabel(name: name, level: sender?.climbLevel ?? 1, compact: true,
                                    tint: sender?.accentColor)
                    Text("sent you")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
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
                // Decline is a compact round "×" so the row keeps room for
                // the name on the smallest iPhones.
                declineButton(busy: busyIds.contains(edge.id)) {
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

    /// Card with avatar, name and level badge, and a caller-supplied trailing
    /// control — the shared `SocialPersonRow` layout.
    private func personCard<Trailing: View>(
        _ profile: PlayerProfile?,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        let name  = profile?.displayName.nonEmpty ?? "Roller"
        let level = profile?.climbLevel ?? 1
        let world = World.world(for: max(1, level))
        let open: (() -> Void)? = profile.map { p -> () -> Void in { nav.goToPlayer(p) } }
        return SocialPersonRow(
            name: name, level: level,
            tint: profile?.id == myId ? gameState.primaryColor : profile?.accentColor,
            onTap: open
        ) {
            avatar(name, tint: world.accent)
        } trailing: {
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

    /// A round "×" button for declining a request (VoiceOver: "Decline").
    private func declineButton(busy: Bool,
                               action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                Circle().fill(Color(white: 0.20))
                if busy {
                    ProgressView().tint(Color(white: 0.7)).scaleEffect(0.7)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(white: 0.75))
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .disabled(busy)
        .buttonStyle(.plain)
        .accessibilityLabel("Decline")
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
            title: "Roll together",
            message: "Search for friends by name to send each other extra lives. The further you get in Adventure, the higher you both rank.",
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
        if myFriendCode == nil { myFriendCode = await SocialClient.shared.fetchMyFriendCode() }
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
            // One "Send life" per friend per day: mark today's as sent.
            let sentToday = await SocialClient.shared.fetchMyGiftsToday()
            sentLifeIds.formUnion(sentToday)
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
            // social_first_friend / social_friends_5 (S1-T6): the reload above
            // refreshed `edges`, so `friends.count` is the current accepted-
            // friend high-water. The engine latches the best — removing a
            // friend later never revokes.
            gameState.recordFriendAccepted(peak: friends.count)
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
            flash("Request sent to \(profile.displayName.nonEmpty ?? "roller").")
        } catch {
            flash("Couldn't send request — try again.")
        }
    }

    private func sendLife(to id: UUID) async {
        busyIds.insert(id)
        defer { busyIds.remove(id) }
        do {
            try await SocialClient.shared.sendLife(to: id, amount: 1)
            // social_send_life / social_lives_sent_25 (S1-T6): friend gift.
            gameState.recordLifeSent()
            sentLifeIds.insert(id)
            flash("Life sent ♥")
        } catch SocialError.http(_, let body) where body.contains("gift_limit") {
            sentLifeIds.insert(id)
            flash("You already sent this friend a life today.")
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

// ===========================================================================
// Shared social bits — used by Friends, Clans, the leaderboard and Home.
// Kept in this file (not a new one) to avoid touching the Xcode project.
// ===========================================================================

/// The level badge shown next to a player's name everywhere: the Adventure
/// level in a capsule.  `tint` is the player's accent color (the player's own
/// from Settings, or another player's stored one); with no tint it uses the
/// color of the level's world, as before.
struct LevelBadge: View {
    let level: Int
    var compact: Bool = false
    /// The smallest size, for the floating name tags in the minigames.
    var tiny: Bool = false
    /// The player's accent color; nil = the world color.
    var tint: Color? = nil

    var body: some View {
        let world = World.world(for: max(1, level))
        let color = tint.map(AccentColor.readable) ?? world.accent
        Text("\(max(1, level))")
            .font(tiny ? .system(size: 9, weight: .heavy, design: .rounded)
                       : .system(compact ? .caption2 : .caption, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, tiny ? 4 : (compact ? 6 : 7))
            .padding(.vertical, tiny ? 0 : (compact ? 1 : 2))
            .background(
                Capsule().fill(color.opacity(0.28))
                    .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
            )
            .fixedSize()
            .accessibilityLabel("Level \(max(1, level))")
    }
}

/// A player's name and Adventure level as ONE unit: the two-word nickname
/// immediately followed by the level badge ("SwiftComet [42]"), in the place
/// a number used to occupy.  Use this wherever a player's name is shown.
/// When space is short the NAME truncates; the badge never does.  VoiceOver
/// reads it as one item: "SwiftComet, level 42".
struct PlayerNameLabel: View {
    let name: String
    let level: Int
    var font: Font = .system(.body, design: .rounded).weight(.semibold)
    var color: Color = .white
    var compact: Bool = false
    /// The player's accent color for the badge; nil = the world color.
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Text(name)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
            LevelBadge(level: level, compact: compact, tint: tint)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), level \(max(1, level))")
    }
}

/// Keeps an accent color readable on the game's dark backgrounds.  The badge
/// draws white text over a 28% fill with a 60% outline, so a LIGHT accent
/// (yellow, pale pink) stays legible as it is; only a very DARK accent (navy,
/// near-black) would vanish into the background, so it is lifted toward
/// white until its brightness reaches a floor.
enum AccentColor {
    /// Brightness (0 to 1, Rec. 709 luma) below which an accent is lifted.
    static let minimumLuma: CGFloat = 0.35

    static func readable(_ color: Color) -> Color {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard luma < minimumLuma else { return color }
        // Mix toward white just enough to reach the floor.
        let t = min(1, (minimumLuma - luma) / max(0.001, 1 - luma))
        return Color(red: Double(r + (1 - r) * t),
                     green: Double(g + (1 - g) * t),
                     blue: Double(b + (1 - b) * t))
    }
}

/// The deep page background tinted with an accent color: the app's dark
/// navy tone with a little of the accent mixed in, dark enough that white
/// text stays readable whatever color the player picked (a pale yellow or
/// pink only reaches about a quarter brightness at the top).  Used by the
/// Profile tab and the player's own public profile; pass `nil` for the
/// plain dark tone.
struct AccentBackground: View {
    var accent: Color?

    static let baseTop    = Color(red: 0.06, green: 0.06, blue: 0.10)
    static let baseBottom = Color(red: 0.09, green: 0.09, blue: 0.14)
    /// How much accent goes into the top and bottom of the page.
    static let topMix: Double = 0.22
    static let bottomMix: Double = 0.10

    static func top(_ accent: Color?) -> Color {
        guard let accent else { return baseTop }
        return baseTop.mix(with: accent, by: topMix)
    }
    static func bottom(_ accent: Color?) -> Color {
        guard let accent else { return baseBottom }
        return baseBottom.mix(with: accent, by: bottomMix)
    }
    /// The navigation bar color that matches the top of the page.
    static func bar(_ accent: Color?) -> Color { top(accent).opacity(0.95) }

    var body: some View {
        LinearGradient(colors: [Self.top(accent), Self.bottom(accent)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// One player row, shared by the friends list, friend requests, friend
/// search, the clan roster and the clan page's member list, so they all read
/// the same on every iPhone from the smallest up.
///
/// Layout, left to right: an optional leading view (avatar or rank), then the
/// player's name with the level badge right after it, an optional small
/// accessory (owner crown, role), and at most ONE detail line below; the
/// trailing control (Send life, Give life, Accept…) sits on the right at its
/// natural size and never wraps.
///
/// When space is short:
///   • the trailing control keeps its shape (`fixedSize`);
///   • the name takes all the remaining width and only a LONG name is
///     shortened, at the end — the level badge is never squeezed;
///   • the detail line drops its less important items first, then disappears
///     entirely, rather than squeezing the name or the button;
///   • at accessibility text sizes the trailing control moves below the name
///     instead of fighting it for width.
struct SocialPersonRow<Leading: View, Trailing: View>: View {
    let name: String
    let level: Int
    let tint: Color?
    let nameFont: Font
    let nameAccessory: AnyView?
    /// Detail items, most important first.  Shown on one line; when the line
    /// cannot fit, only the first item is shown; failing that, none.
    let details: [AnyView]
    /// Replaces the identity part's VoiceOver label when set.
    let spokenLabel: String?
    let onTap: (() -> Void)?
    let leading: () -> Leading
    let trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    init(name: String,
         level: Int,
         tint: Color? = nil,
         nameFont: Font = .system(.body, design: .rounded).weight(.semibold),
         nameAccessory: AnyView? = nil,
         details: [AnyView] = [],
         spokenLabel: String? = nil,
         onTap: (() -> Void)? = nil,
         @ViewBuilder leading: @escaping () -> Leading,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.name = name
        self.level = level
        self.tint = tint
        self.nameFont = nameFont
        self.nameAccessory = nameAccessory
        self.details = details
        self.spokenLabel = spokenLabel
        self.onTap = onTap
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                identity
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    trailing()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        } else {
            HStack(spacing: 10) {
                identity
                    .layoutPriority(1)
                Spacer(minLength: 6)
                trailing()
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var identity: some View {
        if let onTap {
            Button(action: onTap) {
                identityContent.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(OptionalSpokenLabel(text: spokenLabel))
        } else {
            identityContent
                .modifier(OptionalSpokenLabel(text: spokenLabel))
        }
    }

    private var identityContent: some View {
        HStack(spacing: 10) {
            leading()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    PlayerNameLabel(name: name, level: level, font: nameFont,
                                    compact: true, tint: tint)
                        .layoutPriority(1)
                    if let nameAccessory {
                        nameAccessory.fixedSize()
                    }
                }
                if !details.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        detailLine(details)
                        detailLine(Array(details.prefix(1)))
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
            }
        }
    }

    private func detailLine(_ items: [AnyView]) -> some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { i in items[i] }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// Replaces a view's VoiceOver label (combining its children) when `text`
/// is set; leaves it alone otherwise.
private struct OptionalSpokenLabel: ViewModifier {
    let text: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
        } else {
            content
        }
    }
}

/// Red circular badge with a count (open life requests).  Draws nothing at 0.
struct CountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(Color(red: 0.92, green: 0.20, blue: 0.24)))
                .fixedSize()
                .accessibilityLabel("\(count) open life request\(count == 1 ? "" : "s")")
        }
    }
}

/// A clan's standing in the monthly clan battle: this season's score, its
/// wins (months finished first) and where it finished last month.
struct ClanStandingLine: View {
    let standing: ClanRanking
    var centered: Bool = true

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 3) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "star.circle.fill")
                    Text("\(SeasonCalendar.monthName()) season: \(standing.seasonScore)")
                }
                .foregroundStyle(Color(red: 1.0, green: 0.81, blue: 0.30))
                if let wins = standing.winsLine {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                        Text(wins)
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.81, blue: 0.30))
                }
            }
            .font(.system(.caption, design: .rounded).weight(.bold))
            .monospacedDigit()
            if let last = standing.lastMonthLine {
                Text(last)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color(white: 0.6))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One member's stars for the clan this season ("★ 37 this season").
/// Draws nothing at 0.
struct SeasonStarsLabel: View {
    let stars: Int

    var body: some View {
        if stars > 0 {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.system(size: 9))
                Text("\(stars) this season")
            }
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color(red: 1.0, green: 0.81, blue: 0.30))
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(stars) stars this season")
        }
    }
}

/// The signed-in player's friend code, shown on their own profile, with Copy.  Draws nothing when signed out or before the server has codes.
struct FriendCodeCard: View {
    @ObservedObject private var auth = AppleAuthManager.shared
    @State private var code: String?
    @State private var copied = false

    // One compact line: "Friend code AF3K-7MXY  [Copy]".  Shows only when
    // signed in AND the server has a code (codes are assigned by the database,
    // docs/social-schema-v5.sql section 10).  The code is fetched every time
    // the card appears, so it shows up on the next visit to Profile once the
    // database step is applied.
    //
    // The outer VStack always exists (even when it has nothing to show), so
    // the fetch below always runs.  An empty Group would never appear, and
    // its fetch would never run — which is why the code never showed before.
    var body: some View {
        VStack(spacing: 0) {
            if auth.isSignedIn, let code {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        // Same title style as "My Loadout" and "Trophies".
                        Text("Friend Code")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        Button {
                            UIPasteboard.general.string = FriendCode.display(code)
                            copied = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(copied ? "Copied" : "Copy")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color(white: 0.20)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(copied ? "Copied" : "Copy friend code")
                    }
                    Text(FriendCode.display(code))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .profileCard()          // the same rim as the other Profile cards
                .accessibilityElement(children: .contain)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: auth.isSignedIn) {
            copied = false
            code = auth.isSignedIn ? await SocialClient.shared.fetchMyFriendCode() : nil
        }
    }
}

/// The invite message, shared by Friends → Invite a friend and Profile →
/// Share Profile, so the two never differ.
enum InviteMessage {
    /// Where "Download Roll Along" points: the app's page on the project
    /// website.  Before launch that page must be changed to send visitors to
    /// the App Store listing (see docs/site/index.html).
    static let downloadURL = "https://mfaldet.github.io/roll-along/"

    /// The exact text sent.  With a friend code:
    ///   Come, Roll Along with me!
    ///   My Friend Code is AF3K-7MXY (Friends → Add by code).
    ///   Download Roll Along: https://mfaldet.github.io/roll-along/
    /// Without one (signed out, or before the server has codes), the middle
    /// line is left out.
    static func text(friendCode: String?) -> String {
        var lines = ["Come, Roll Along with me!"]
        if let code = friendCode, !code.isEmpty {
            lines.append("My Friend Code is \(FriendCode.display(code)) (Friends → Add by code).")
        }
        lines.append("Download Roll Along: \(downloadURL)")
        return lines.joined(separator: "\n")
    }
}
