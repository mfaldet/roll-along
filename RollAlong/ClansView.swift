import SwiftUI

// ===========================================================================
// ClansView — collaborative groups built on the `clans` / `clan_members`
// tables (RLS-scoped through SocialClient).  A player belongs to at most one
// clan, so the screen has two faces:
//
//   • In a clan  — header (name, [TAG], description, size), a roster ranked
//                  by climb level with role badges, and a footer action:
//                  Leave (members) or Disband (owner, cascades the roster).
//   • No clan    — a "start your own" callout that opens a create sheet, plus
//                  a browse/search list of clans to join.
//
// Requires a Supabase session (Sign in with Apple); signed out it shows the
// same friendly prompt as Friends/Leaderboard and routes to Settings.
//
// SAFE BY CONSTRUCTION: additive.  Until HomeView routes to it, nothing here
// runs; the worst case on an unreachable backend is a retryable error banner.
// ===========================================================================

struct ClansView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator
    @ObservedObject private var auth = AppleAuthManager.shared
    @Environment(\.dismiss) var dismiss

    // My membership + the clan I'm in (both nil when I belong to no clan).
    @State private var membership: ClanMember?
    @State private var myClan:     Clan?
    @State private var roster:     [ClanMember] = []
    @State private var rosterProfiles: [UUID: PlayerProfile] = [:]

    // Discover (only loaded when I'm not in a clan).
    @State private var browse:     [Clan] = []
    @State private var searchTerm  = ""
    @State private var isSearching = false

    // Lifecycle / feedback
    @State private var hasLoaded   = false
    @State private var isLoading   = false
    @State private var errorText:  String?
    @State private var actionBusy  = false      // leave / disband in flight
    @State private var joiningId:  UUID?        // clan currently being joined
    @State private var showCreate    = false
    @State private var confirmLeave  = false
    @State private var confirmDisband = false
    @State private var banner: String?

    private var myId: UUID? { SocialClient.shared.currentUserId }
    private var iAmOwner: Bool { membership?.isOwner ?? false }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            if !auth.isSignedIn {
                signedOutState
            } else {
                content
            }

            if let banner {
                bannerView(banner)
            }
        }
        .navigationTitle("Clans")
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
        .sheet(isPresented: $showCreate) {
            ClanCreateSheet { Task { await load() } }
        }
        .confirmationDialog("Leave this clan?",
                            isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await leave() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Disband this clan? It's removed for every member.",
                            isPresented: $confirmDisband, titleVisibility: .visible) {
            Button("Disband", role: .destructive) { Task { await disband() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Signed-in content

    @ViewBuilder
    private var content: some View {
        if !hasLoaded && isLoading {
            ProgressView().tint(.white).scaleEffect(1.2)
        } else if let errorText, !hasLoaded {
            errorState(errorText)
        } else if membership != nil {
            myClanContent
        } else {
            discoverContent
        }
    }

    // MARK: - In a clan

    private var myClanContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                clanHeader
                rosterSection
                membershipAction
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .refreshable { await load() }
    }

    private var clanHeader: some View {
        let tag  = myClan?.tag.nonEmpty
        let name = myClan?.name.nonEmpty ?? "Clan"
        let desc = myClan?.description.nonEmpty
        return VStack(spacing: 10) {
            if let tag {
                Text("[\(tag)]")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
            }
            Text(name)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let desc {
                Text(desc)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))
                    .multilineTextAlignment(.center)
            }
            Text(roster.count == 1 ? "1 member" : "\(roster.count) members")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Color(white: 0.45))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.13))
        )
    }

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Roster", "person.3.fill")
            ForEach(sortedRoster) { member in
                rosterRow(member)
            }
        }
    }

    /// Owner pinned to the top, then by climb level descending.
    private var sortedRoster: [ClanMember] {
        roster.sorted { a, b in
            if a.isOwner != b.isOwner { return a.isOwner }
            let la = rosterProfiles[a.playerId]?.climbLevel ?? 0
            let lb = rosterProfiles[b.playerId]?.climbLevel ?? 0
            return la > lb
        }
    }

    private func rosterRow(_ member: ClanMember) -> some View {
        let prof  = rosterProfiles[member.playerId]
        let name  = prof?.displayName.nonEmpty ?? "Climber"
        let level = prof?.climbLevel ?? 1
        let world = World.world(for: max(1, level))
        let isMe  = (member.playerId == myId)
        return HStack(spacing: 14) {
            avatar(name, tint: world.accent)
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(.body, design: .rounded).weight(isMe ? .bold : .semibold))
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
            Spacer(minLength: 8)
            roleBadge(member.role)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isMe ? Color(red: 0.20, green: 0.50, blue: 0.96).opacity(0.16)
                           : Color(white: 0.14))
        )
    }

    private func roleBadge(_ role: String) -> some View {
        let (label, color): (String, Color) = {
            switch role {
            case "owner":   return ("Owner",   Color(red: 1.00, green: 0.81, blue: 0.30))
            case "officer": return ("Officer", Color(red: 0.55, green: 0.78, blue: 1.0))
            default:         return ("Member",  Color(white: 0.55))
            }
        }()
        return Text(label)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    @ViewBuilder
    private var membershipAction: some View {
        if iAmOwner {
            Button { confirmDisband = true } label: {
                actionLabel("Disband clan", busy: actionBusy, tint: Color(red: 0.90, green: 0.30, blue: 0.32))
            }
            .disabled(actionBusy)
            .buttonStyle(.plain)
            Text("Disbanding removes the clan for everyone.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.4))
                .padding(.top, 2)
        } else {
            Button { confirmLeave = true } label: {
                actionLabel("Leave clan", busy: actionBusy, tint: Color(white: 0.22))
            }
            .disabled(actionBusy)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Discover (not in a clan)

    private var discoverContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                createCallout
                searchField
                browseSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await load() }
    }

    private var createCallout: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.2.crossed.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
            Text("Start your own clan")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text("Create a clan, pick a [TAG], and climb together.")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color(white: 0.55))
                .multilineTextAlignment(.center)
            Button { showCreate = true } label: {
                actionLabel("Create a clan", busy: false,
                            tint: Color(red: 0.20, green: 0.50, blue: 0.96))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.13)))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(white: 0.5))
            TextField("", text: $searchTerm,
                      prompt: Text("Search clans by name"))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
            if !searchTerm.isEmpty {
                Button {
                    searchTerm = ""
                    Task { await runSearch() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(white: 0.45))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14)))
    }

    @ViewBuilder
    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(searchTerm.isEmpty ? "Browse clans" : "Results",
                          "rectangle.stack.fill")
            if isSearching {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if browse.isEmpty {
                Text(searchTerm.isEmpty
                     ? "No clans yet — be the first to start one."
                     : "No clans match “\(searchTerm)”.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Color(white: 0.5))
                    .padding(.vertical, 6)
            } else {
                ForEach(browse) { clan in
                    browseRow(clan)
                }
            }
        }
    }

    private func browseRow(_ clan: Clan) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let t = clan.tag.nonEmpty {
                        Text("[\(t)]")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
                    }
                    Text(clan.name.nonEmpty ?? "Clan")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if let d = clan.description.nonEmpty {
                    Text(d)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(white: 0.55))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            actionButton("Join", busy: joiningId == clan.id) {
                await join(clan)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14)))
    }

    // MARK: - Reusable bits

    private func avatar(_ name: String, tint: Color) -> some View {
        ZStack {
            Circle().fill(tint.opacity(0.28)).frame(width: 38, height: 38)
            Text(String(name.first ?? "?").uppercased())
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

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

    /// A full-width capsule label (used by the big Create/Leave/Disband
    /// buttons).  Shows a spinner in place of the title while `busy`.
    private func actionLabel(_ title: String, busy: Bool, tint: Color) -> some View {
        ZStack {
            Text(title).opacity(busy ? 0 : 1)
            if busy { ProgressView().tint(.white).scaleEffect(0.8) }
        }
        .font(.system(.body, design: .rounded).weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(Capsule().fill(tint))
    }

    /// A compact capsule action button (the Join buttons in the browse list).
    private func actionButton(_ title: String,
                              busy: Bool,
                              action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(.white).scaleEffect(0.7) }
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color(red: 0.20, green: 0.50, blue: 0.96)))
        }
        .disabled(busy)
        .buttonStyle(.plain)
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

    // MARK: - Empty / error / signed-out

    private func errorState(_ text: String) -> some View {
        messageBlock(icon: "wifi.exclamationmark",
                     title: "Couldn't load clans",
                     message: text,
                     actionTitle: "Try Again",
                     action: { Task { await load() } })
    }

    private var signedOutState: some View {
        messageBlock(icon: "person.3.fill",
                     title: "Join a clan",
                     message: "Sign in with Apple to start or join a clan and climb together. Your progress is saved on this device either way.",
                     actionTitle: "Sign in from Settings",
                     action: { nav.goToSettings() })
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

    // MARK: - Data

    private func load() async {
        guard auth.isSignedIn else { return }
        isLoading = true
        errorText = nil
        do {
            let mem = try await SocialClient.shared.fetchMyClanMembership()
            membership = mem
            if let mem {
                async let clanCall   = SocialClient.shared.fetchClan(id: mem.clanId)
                async let rosterCall = SocialClient.shared.fetchClanRoster(clanId: mem.clanId)
                let clan    = try await clanCall
                let members = try await rosterCall
                let profs = try await SocialClient.shared.fetchProfiles(ids: members.map { $0.playerId })
                var map: [UUID: PlayerProfile] = [:]
                for p in profs { map[p.id] = p }
                myClan         = clan
                roster         = members
                rosterProfiles = map
                browse         = []
            } else {
                myClan = nil
                roster = []
                browse = try await SocialClient.shared.fetchClans()
            }
            hasLoaded = true
        } catch {
            errorText = "The clan server is unreachable right now. Pull to refresh or try again."
        }
        isLoading = false
    }

    private func runSearch() async {
        isSearching = true
        do {
            let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            browse = term.isEmpty
                ? try await SocialClient.shared.fetchClans()
                : try await SocialClient.shared.searchClans(matching: term)
        } catch {
            browse = []
            flash("Search failed — try again.")
        }
        isSearching = false
    }

    // MARK: - Actions

    private func join(_ clan: Clan) async {
        joiningId = clan.id
        defer { joiningId = nil }
        do {
            try await SocialClient.shared.joinClan(id: clan.id)
            await load()
            flash("Joined \(clan.name.nonEmpty ?? "the clan")!")
        } catch {
            flash("Couldn't join — you may already be in a clan.")
        }
    }

    private func leave() async {
        guard let clan = myClan else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            try await SocialClient.shared.leaveClan(id: clan.id)
            await load()
            flash("You left the clan.")
        } catch {
            flash("Couldn't leave — try again.")
        }
    }

    private func disband() async {
        guard let clan = myClan else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            try await SocialClient.shared.disbandClan(id: clan.id)
            await load()
            flash("Clan disbanded.")
        } catch {
            flash("Couldn't disband — try again.")
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

// ===========================================================================
// ClanCreateSheet — collects name / [TAG] / description and creates the clan.
// Self-contained: it calls SocialClient directly, surfaces server errors
// (e.g. a taken name/tag) inline, and only dismisses on success — so a failed
// attempt keeps the player's typed input.  `onCreated` lets the parent reload.
// ===========================================================================
private struct ClanCreateSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var tag  = ""
    @State private var desc = ""
    @State private var working = false
    @State private var error:  String?
    let onCreated: () -> Void

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTag:  String { tag.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDesc: String { desc.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        (2...32).contains(trimmedName.count) &&
        (2...5).contains(trimmedTag.count) &&
        trimmedDesc.count <= 200
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        field(title: "Clan name", text: $name,
                              placeholder: "Marble Climbers", limit: 32)
                        field(title: "Tag (2–5 characters)", text: $tag,
                              placeholder: "CLMB", limit: 5, uppercase: true)
                        field(title: "Description (optional)", text: $desc,
                              placeholder: "What's your clan about?", limit: 200)

                        if let error {
                            Text(error)
                                .font(.system(.callout, design: .rounded))
                                .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.45))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New clan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .foregroundStyle(isValid ? Color(red: 0.40, green: 0.66, blue: 1.0) : Color(white: 0.4))
                        .disabled(!isValid || working)
                }
            }
        }
    }

    private func field(title: String, text: Binding<String>,
                       placeholder: String, limit: Int,
                       uppercase: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color(white: 0.5))
                .tracking(0.5)
            TextField("", text: text, prompt: Text(placeholder))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(uppercase ? .characters : .sentences)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
                .onChange(of: text.wrappedValue) { _, newValue in
                    var v = newValue
                    if uppercase { v = v.uppercased() }
                    if v.count > limit { v = String(v.prefix(limit)) }
                    if v != newValue { text.wrappedValue = v }
                }
        }
    }

    private func create() async {
        working = true
        error = nil
        do {
            _ = try await SocialClient.shared.createClan(
                name: trimmedName, tag: trimmedTag, description: trimmedDesc)
            onCreated()
            dismiss()
        } catch {
            self.error = "Couldn't create — that name or tag may already be taken."
        }
        working = false
    }
}

// MARK: - File-local helpers

private extension String {
    /// `nil` when empty after trimming, so callers can `??` a placeholder.
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
