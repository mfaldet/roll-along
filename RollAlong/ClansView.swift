import SwiftUI

// ===========================================================================
// ClansView — clans as a lives-sharing community (built on clans / clan_members
// / clan_events / players, all RLS-scoped through SocialClient).
//
// Secondary navigation (a segmented control), so you can always browse other
// clans even while in one:
//   • My Clan / Create — in a clan: header, stats, the lives loop (ask for a
//                        life · send to members · fulfill), the clan chat
//                        (the activity feed as a conversation, with premade
//                        quick-chat messages), an invite link, and a settings
//                        sheet (members leave / ask for a promotion; the owner
//                        renames — more personalization later — or disbands).
//                        Not in a clan: a "start your own" callout.
//   • Browse           — search + list of all clans; tap one to push its detail
//                        (roster, stats → Join).
//
// Requires a Supabase session (Sign in with Apple); signed out it shows the
// same friendly prompt as Friends/Leaderboard and routes to Settings.
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
    @State private var events:     [ClanEvent] = []

    // Discover.
    @State private var browse:     [Clan] = []
    @State private var searchTerm  = ""
    @State private var isSearching = false

    // Secondary nav.
    enum Tab: Hashable { case mine, browse }
    @State private var tab: Tab = .mine
    @State private var tabPinned = false   // honour the user's pick after first load

    // Lifecycle / feedback.
    @State private var hasLoaded   = false
    @State private var isLoading   = false
    @State private var errorText:  String?
    @State private var actionBusy  = false
    @State private var busyIds:     Set<UUID> = []
    @State private var sentLifeIds: Set<UUID> = []
    @State private var thankedActorIds: Set<UUID> = []
    @State private var showCreate    = false
    @State private var settingsClan: Clan?     // non-nil → clan settings sheet
    @State private var chatSending   = false   // a quick-chat post in flight
    @State private var banner: String?

    private var myId: UUID? { SocialClient.shared.currentUserId }
    private var inClan:   Bool { membership != nil }
    private var iAmAsking: Bool { myId.flatMap { rosterProfiles[$0]?.isAskingForLives } ?? false }
    /// True once my promotion ask is in the (recent) feed — keeps the settings
    /// sheet's button from being re-tapped across sessions.
    private var iAskedForPromotion: Bool {
        guard let myId else { return false }
        return events.contains { $0.kind == "requested_promotion" && $0.actorId == myId }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            if !auth.isSignedIn { signedOutState } else { content }
            if let banner { bannerView(banner) }
        }
        .navigationTitle("Clans")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 3) { Image(systemName: "chevron.left"); Text("Back") }
                        .foregroundStyle(.white)
                }
            }
            // Clan settings — members leave / ask for a promotion; the owner
            // renames (more personalization later) or disbands.
            ToolbarItem(placement: .navigationBarTrailing) {
                if let myClan {
                    Button { settingsClan = myClan } label: {
                        Image(systemName: "gearshape.fill").foregroundStyle(.white)
                    }
                    .accessibilityLabel("Clan settings")
                }
            }
        }
        .task { await load() }
        // clan_join (S1-T6): creating a clan counts, same as joining. `onCreated`
        // fires only after `SocialClient.createClan` succeeds.
        .sheet(isPresented: $showCreate) {
            ClanCreateSheet { gameState.recordClanJoined(); Task { await load() } }
        }
        .sheet(item: $settingsClan) { clan in
            ClanSettingsSheet(clan: clan,
                              role: membership?.role ?? "member",
                              alreadyAskedPromotion: iAskedForPromotion,
                              onRename:       { await rename(to: $0) },
                              onAskPromotion: { await askForPromotion() },
                              onLeave:        { Task { await leave() } },
                              onDisband:      { Task { await disband() } })
        }
    }

    // MARK: - Content + secondary nav

    @ViewBuilder
    private var content: some View {
        if !hasLoaded && isLoading {
            ProgressView().tint(.white).scaleEffect(1.2)
        } else if let errorText, !hasLoaded {
            errorState(errorText)
        } else {
            VStack(spacing: 0) {
                segmentedNav
                ScrollView {
                    VStack(spacing: 20) {
                        if tab == .mine {
                            if inClan { myClanSections } else { createCallout }
                        } else {
                            browseSections
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await load() }
            }
        }
    }

    private var segmentedNav: some View {
        Picker("", selection: $tab) {
            Text(inClan ? "My Clan" : "Create").tag(Tab.mine)
            Text("Browse").tag(Tab.browse)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onChange(of: tab) { _, _ in tabPinned = true }
    }

    // MARK: - My clan

    @ViewBuilder
    private var myClanSections: some View {
        clanHeader
        clanStatsRow
        lifeLoopSection
        inviteRow
        rosterSection
        chatSection
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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.13)))
    }

    /// Members · combined climb levels · lives shared (a sense of the collective).
    private var clanStatsRow: some View {
        HStack(spacing: 10) {
            clanStat("\(roster.count)", "Members", "person.3.fill", Color(red: 0.55, green: 0.78, blue: 1.0))
            clanStat("\(combinedLevels)", "Levels", "flag.fill", Color(red: 0.30, green: 0.75, blue: 0.42))
            clanStat("\(livesShared)", "Lives shared", "heart.fill", Color(red: 0.95, green: 0.32, blue: 0.45))
        }
    }

    private var combinedLevels: Int { roster.reduce(0) { $0 + (rosterProfiles[$1.playerId]?.climbLevel ?? 0) } }
    private var livesShared:    Int { events.filter { $0.kind == "sent_life" }.count }

    private func clanStat(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(color)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
            Text(label).font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.48)).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
    }

    // The lives loop: ask for a life (or cancel) — clan-mates see it on the roster.
    @ViewBuilder
    private var lifeLoopSection: some View {
        if iAmAsking {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(Color(red: 0.95, green: 0.32, blue: 0.45))
                    Text("You're asking your clan for lives")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                Button { Task { await cancelAsk() } } label: {
                    actionLabel("Cancel request", busy: actionBusy, tint: Color(white: 0.22))
                }
                .disabled(actionBusy).buttonStyle(.plain)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.95, green: 0.32, blue: 0.45).opacity(0.14)))
        } else {
            Button { Task { await askForLives() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square.fill")
                    Text("Ask the clan for a life")
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Capsule().fill(Color(red: 0.95, green: 0.32, blue: 0.45)))
                .opacity(actionBusy ? 0.6 : 1)
            }
            .disabled(actionBusy).buttonStyle(.plain)
        }
    }

    private var inviteRow: some View {
        let link = URL(string: "rollalong://clan/\(myClan?.id.uuidString ?? "")")!
        let name = myClan?.name.nonEmpty ?? "my clan"
        return ShareLink(item: link,
                         subject: Text("Join my Roll Along clan"),
                         message: Text("Join \(name) on Roll Along so we can send each other lives! Tap: \(link.absoluteString)")) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 15, weight: .semibold))
                Text("Invite a friend to the clan")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                Spacer()
                Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.20, green: 0.50, blue: 0.96).opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(red: 0.20, green: 0.50, blue: 0.96).opacity(0.45), lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Roster", "person.3.fill")
            ForEach(sortedRoster) { member in rosterRow(member) }
        }
    }

    /// Owner pinned to the top, then by climb level descending.
    private var sortedRoster: [ClanMember] {
        roster.sorted { a, b in
            if a.isOwner != b.isOwner { return a.isOwner }
            return (rosterProfiles[a.playerId]?.climbLevel ?? 0) > (rosterProfiles[b.playerId]?.climbLevel ?? 0)
        }
    }

    private func rosterRow(_ member: ClanMember) -> some View {
        let prof  = rosterProfiles[member.playerId]
        let name  = prof?.displayName.nonEmpty ?? "Climber"
        let level = prof?.climbLevel ?? 1
        let world = World.world(for: max(1, level))
        let isMe  = member.playerId == myId
        let asking = prof?.isAskingForLives ?? false
        return HStack(spacing: 12) {
            Button { if let prof { nav.goToPlayer(prof) } } label: {
                HStack(spacing: 12) {
                    avatar(name, tint: world.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(name)
                                .font(.system(.body, design: .rounded).weight(isMe ? .bold : .semibold))
                                .foregroundStyle(.white).lineLimit(1)
                            Text("\(level)")
                                .font(.system(.caption2, design: .rounded).weight(.bold)).monospacedDigit()
                                .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(world.accent.opacity(0.28))
                                    .overlay(Capsule().stroke(world.accent.opacity(0.6), lineWidth: 1)))
                        }
                        if asking {
                            Text("needs a life ♥")
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.55))
                        }
                    }
                }
            }
            .buttonStyle(.plain).disabled(prof == nil)
            Spacer(minLength: 8)
            if !isMe { sendLifeControl(member.playerId) }
            else { roleBadge(member.role) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(isMe ? Color(red: 0.20, green: 0.50, blue: 0.96).opacity(0.16)
                       : (asking ? Color(red: 0.95, green: 0.32, blue: 0.45).opacity(0.10) : Color(white: 0.14))))
    }

    @ViewBuilder
    private func sendLifeControl(_ id: UUID) -> some View {
        if sentLifeIds.contains(id) {
            tag("Sent ♥", Color(red: 0.95, green: 0.32, blue: 0.45))
        } else {
            actionButton("Send life", busy: busyIds.contains(id)) { await sendLife(to: id) }
        }
    }

    // MARK: - Clan chat (the activity feed as a conversation)

    /// Premade quick-chat messages — each is a fixed `chat_*` event kind and
    /// the text is mapped on-device, so no free text ever reaches the server
    /// (nothing to moderate).  Add a pair here to grow the vocabulary; the
    /// schema allows any `chat_*` kind, so no migration is needed.
    private static let quickChats: [(kind: String, text: String)] = [
        ("chat_hi",        "Hi team! 👋"),
        ("chat_lets_roll", "Let's roll! 🚀"),
        ("chat_nice",      "Nice climbing! 🔥"),
        ("chat_gl",        "Good luck! 🍀"),
        ("chat_ty",        "Thank you! 💙"),
    ]
    private static let quickChatText: [String: String] =
        Dictionary(uniqueKeysWithValues: quickChats.map { ($0.kind, $0.text) })

    /// Membership / clan changes render as centered one-liners, not bubbles.
    private static let systemKinds: Set<String> = ["created", "joined", "left", "renamed"]

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Clan chat", "bubble.left.and.bubble.right.fill")
            chatPanel
            quickChatBar
        }
    }

    /// Oldest → newest, like any messages app (the server returns newest-first).
    private var chronologicalEvents: [ClanEvent] { Array(events.reversed()) }

    /// The scroll itself: bubbles + system lines, pinned to the newest entry,
    /// with a light poll so clan-mates' posts appear while you're looking.
    private var chatPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    if events.isEmpty {
                        Text("It's quiet in here — send a quick message below 👇")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color(white: 0.45))
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 36)
                    }
                    ForEach(chronologicalEvents) { e in
                        chatRow(e).id(e.id)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 320)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.11)))
            .onAppear { scrollToLatest(proxy, animated: false) }
            .onChange(of: events.count) { _, _ in scrollToLatest(proxy, animated: true) }
            .task(id: myClan?.id) { await pollChat() }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = chronologicalEvents.last?.id else { return }
        if animated { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
        else        { proxy.scrollTo(last, anchor: .bottom) }
    }

    @ViewBuilder
    private func chatRow(_ e: ClanEvent) -> some View {
        if Self.systemKinds.contains(e.kind) { systemLine(e) } else { chatBubble(e) }
    }

    private func systemLine(_ e: ClanEvent) -> some View {
        HStack(spacing: 5) {
            Image(systemName: eventIcon(e.kind)).font(.system(size: 10))
            Text(systemText(e))
            if let t = relativeTime(e.createdAt) {
                Text("· \(t)").foregroundStyle(Color(white: 0.35))
            }
        }
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(Color(white: 0.45))
        .frame(maxWidth: .infinity)
    }

    /// A speech bubble: mine right-aligned in clan blue, everyone else's on
    /// the left under their name.  A life sent to me grows a Thanks reaction.
    private func chatBubble(_ e: ClanEvent) -> some View {
        let mine  = e.actorId == myId
        let who   = name(of: e.actorId)
        let world = World.world(for: max(1, rosterProfiles[e.actorId]?.climbLevel ?? 1))
        return HStack(alignment: .bottom, spacing: 8) {
            if mine {
                Spacer(minLength: 44)
            } else {
                avatar(who, tint: world.accent, size: 28)
            }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if !mine {
                    Text(who)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(world.accent)
                }
                Text(bubbleText(e))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(bubbleShape(mine: mine))
                HStack(spacing: 8) {
                    if let t = relativeTime(e.createdAt) {
                        Text(t).font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color(white: 0.4))
                    }
                    thanksReaction(e)
                }
            }
            if !mine { Spacer(minLength: 44) }
        }
    }

    private func bubbleShape(mine: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 14,
                               bottomLeadingRadius: mine ? 14 : 4,
                               bottomTrailingRadius: mine ? 4 : 14,
                               topTrailingRadius: 14)
            .fill(mine ? Color(red: 0.20, green: 0.50, blue: 0.96).opacity(0.55)
                       : Color(white: 0.17))
    }

    /// Say thanks for a life someone sent ME (premade reaction).
    @ViewBuilder
    private func thanksReaction(_ e: ClanEvent) -> some View {
        if e.kind == "sent_life", e.targetId == myId, e.actorId != myId {
            if thankedActorIds.contains(e.actorId) {
                Text("Thanked 🙏").font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color(white: 0.5))
            } else {
                Button { Task { await thank(e.actorId) } } label: {
                    Text("Thanks 🙏").font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(red: 0.30, green: 0.62, blue: 0.42)))
                }.buttonStyle(.plain)
            }
        }
    }

    /// One-tap premade messages — the send side of the chat.
    private var quickChatBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.quickChats, id: \.kind) { chat in
                    Button { Task { await sendQuickChat(chat.kind) } } label: {
                        Text(chat.text)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(Capsule().fill(Color(white: 0.17))
                                .overlay(Capsule().stroke(Color(white: 0.28), lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(chatSending)
                }
            }
            .opacity(chatSending ? 0.55 : 1)
        }
    }

    /// Bubble copy reads as the speaker talking (their name sits above).
    private func bubbleText(_ e: ClanEvent) -> String {
        switch e.kind {
        case "requested_life":      return "Could someone send me a life? ♥"
        case "sent_life":           return e.targetId == myId
                                        ? "Sent you a life ♥"
                                        : "Sent \(e.targetId.map(name(of:)) ?? "a member") a life ♥"
        case "thanked":             return e.targetId == myId
                                        ? "Thanks for the life 🙏"
                                        : "Thanks, \(e.targetId.map(name(of:)) ?? "team")! 🙏"
        case "requested_promotion": return "May I have a promotion? 📣"
        default:                    return Self.quickChatText[e.kind] ?? "✨"
        }
    }

    private func systemText(_ e: ClanEvent) -> String {
        let actor = name(of: e.actorId)
        switch e.kind {
        case "created": return "\(actor) created the clan"
        case "joined":  return "\(actor) joined the clan"
        case "left":    return "\(actor) left the clan"
        case "renamed": return "\(actor) renamed the clan"
        default:        return "\(actor) was here"
        }
    }

    private func eventIcon(_ kind: String) -> String {
        switch kind {
        case "joined", "created": return "person.fill.badge.plus"
        case "left":              return "person.fill.badge.minus"
        case "renamed":           return "pencil.line"
        default:                  return "sparkle"
        }
    }

    private func name(of id: UUID) -> String {
        if id == myId { return "You" }
        return rosterProfiles[id]?.displayName.nonEmpty ?? "A climber"
    }

    // MARK: - Create callout (My Clan tab when not in a clan)

    private var createCallout: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.2.crossed.fill").font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
            Text("Start your own clan")
                .font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
            Text("Create a clan, pick a [TAG], and send each other lives.")
                .font(.system(.callout, design: .rounded)).foregroundStyle(Color(white: 0.55))
                .multilineTextAlignment(.center)
            Button { showCreate = true } label: {
                actionLabel("Create a clan", busy: false, tint: Color(red: 0.20, green: 0.50, blue: 0.96))
            }.buttonStyle(.plain).padding(.top, 2)
            Button { tab = .browse } label: {
                Text("…or browse existing clans")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
            }.buttonStyle(.plain).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.13)))
    }

    // MARK: - Browse

    @ViewBuilder
    private var browseSections: some View {
        searchField
        browseSection
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color(white: 0.5))
            TextField("", text: $searchTerm, prompt: Text("Search clans by name"))
                .foregroundStyle(.white).autocorrectionDisabled().submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
            if !searchTerm.isEmpty {
                Button { searchTerm = ""; Task { await runSearch() } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color(white: 0.45))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14)))
    }

    @ViewBuilder
    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(searchTerm.isEmpty ? "Browse clans" : "Results", "rectangle.stack.fill")
            if isSearching {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if browse.isEmpty {
                Text(searchTerm.isEmpty ? "No clans yet — be the first to start one."
                                        : "No clans match “\(searchTerm)”.")
                    .font(.system(.callout, design: .rounded)).foregroundStyle(Color(white: 0.5)).padding(.vertical, 6)
            } else {
                ForEach(browse) { clan in browseRow(clan) }
            }
        }
    }

    private func browseRow(_ clan: Clan) -> some View {
        Button { nav.goToClan(clan) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let t = clan.tag.nonEmpty {
                            Text("[\(t)]").font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
                        }
                        Text(clan.name.nonEmpty ?? "Clan")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white).lineLimit(1)
                    }
                    if let d = clan.description.nonEmpty {
                        Text(d).font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color(white: 0.55)).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.4))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared small UI

    private func avatar(_ name: String, tint: Color, size: CGFloat = 38) -> some View {
        ZStack {
            Circle().fill(tint.opacity(0.28)).frame(width: size, height: size)
            Text(String(name.first ?? "?").uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
    }

    private func roleBadge(_ role: String) -> some View {
        let (label, color): (String, Color) = {
            switch role {
            case "owner":   return ("Owner",   Color(red: 1.00, green: 0.81, blue: 0.30))
            case "officer": return ("Officer", Color(red: 0.55, green: 0.78, blue: 1.0))
            default:         return ("Member",  Color(white: 0.55))
            }
        }()
        return Text(label).font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private func sectionHeader(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.5))
            Text(title.uppercased()).font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color(white: 0.5)).tracking(0.5)
            Spacer()
        }
    }

    private func actionLabel(_ title: String, busy: Bool, tint: Color) -> some View {
        ZStack {
            Text(title).opacity(busy ? 0 : 1)
            if busy { ProgressView().tint(.white).scaleEffect(0.8) }
        }
        .font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 13).background(Capsule().fill(tint))
    }

    private func actionButton(_ title: String, busy: Bool, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(.white).scaleEffect(0.7) }
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().fill(Color(red: 0.20, green: 0.50, blue: 0.96)))
        }
        .disabled(busy).buttonStyle(.plain)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(color).padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private func bannerView(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Capsule().fill(Color(white: 0.18))).padding(.bottom, 28)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity)).allowsHitTesting(false)
    }

    // MARK: - Empty / error / signed-out

    private func errorState(_ text: String) -> some View {
        messageBlock(icon: "wifi.exclamationmark", title: "Couldn't load clans",
                     message: text, actionTitle: "Try Again", action: { Task { await load() } })
    }
    private var signedOutState: some View {
        messageBlock(icon: "person.3.fill", title: "Join a clan",
                     message: "Sign in with Apple to start or join a clan and send each other lives. Your progress is saved on this device either way.",
                     actionTitle: "Sign in from Settings", action: { nav.goToSettings() })
    }
    private func messageBlock(icon: String, title: String, message: String,
                              actionTitle: String?, action: (() -> Void)?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 44, weight: .medium)).foregroundStyle(Color(white: 0.4))
            Text(title).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
            Text(message).font(.system(.callout, design: .rounded)).foregroundStyle(Color(white: 0.55))
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Capsule().fill(Color(red: 0.20, green: 0.50, blue: 0.96)))
                }.padding(.top, 4)
            }
        }
        .padding(.horizontal, 36).frame(maxWidth: .infinity)
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
                async let eventsCall = SocialClient.shared.fetchClanEvents(clanId: mem.clanId)
                let clan    = try await clanCall
                let members = try await rosterCall
                let evs     = (try? await eventsCall) ?? []
                let profs = try await SocialClient.shared.fetchProfiles(ids: members.map { $0.playerId })
                var map: [UUID: PlayerProfile] = [:]
                for p in profs { map[p.id] = p }
                myClan = clan; roster = members; rosterProfiles = map; events = evs; browse = []
                if !tabPinned { tab = .mine }
            } else {
                myClan = nil; roster = []; events = []
                browse = try await SocialClient.shared.fetchClans()
                if !tabPinned { tab = .browse }
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
            browse = term.isEmpty ? try await SocialClient.shared.fetchClans()
                                  : try await SocialClient.shared.searchClans(matching: term)
        } catch { browse = []; flash("Search failed — try again.") }
        isSearching = false
    }

    // MARK: - Actions

    private func leave() async {
        guard let clan = myClan else { return }
        actionBusy = true; defer { actionBusy = false }
        do {
            try? await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "left")
            try await SocialClient.shared.leaveClan(id: clan.id)
            tabPinned = false; await load(); flash("You left the clan.")
        } catch { flash("Couldn't leave — try again.") }
    }

    private func disband() async {
        guard let clan = myClan else { return }
        actionBusy = true; defer { actionBusy = false }
        do {
            try await SocialClient.shared.disbandClan(id: clan.id)
            tabPinned = false; await load(); flash("Clan disbanded.")
        } catch { flash("Couldn't disband — try again.") }
    }

    private func askForLives() async {
        guard let clan = myClan else { return }
        actionBusy = true; defer { actionBusy = false }
        do {
            try await SocialClient.shared.askForLives()
            try? await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "requested_life")
            await load(); flash("Your clan knows you need a life ♥")
        } catch { flash("Couldn't post your request — try again.") }
    }

    private func cancelAsk() async {
        actionBusy = true; defer { actionBusy = false }
        do { try await SocialClient.shared.clearNeedsLives(); await load() }
        catch { flash("Couldn't cancel — try again.") }
    }

    private func sendLife(to id: UUID) async {
        guard let clan = myClan else { return }
        busyIds.insert(id); defer { busyIds.remove(id) }
        // Capture the fulfillment signal BEFORE the send (a successful send may
        // later clear the recipient's ask): a life to a clanmate who was asking
        // is a request FULFILLMENT (`clan_fulfill`), not just a gift.
        let wasAsking = rosterProfiles[id]?.isAskingForLives ?? false
        do {
            try await SocialClient.shared.sendLife(to: id, amount: 1)
            try? await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "sent_life", target: id)
            // social_send_life / social_lives_sent_25 (S1-T6): every clan gift
            // counts toward lives sent, whether or not it fulfills a request.
            gameState.recordLifeSent()
            // clan_fulfill (S1-T6): additionally, a gift to an asking clanmate.
            if wasAsking { gameState.recordClanRequestFulfilled() }
            sentLifeIds.insert(id); flash("Life sent ♥")
        } catch { flash("Couldn't send a life — try again.") }
    }

    private func thank(_ actorId: UUID) async {
        guard let clan = myClan else { return }
        do {
            try await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "thanked", target: actorId)
            thankedActorIds.insert(actorId); flash("Thanks sent 🙏")
            await refreshEvents()
        } catch { flash("Couldn't send thanks — try again.") }
    }

    /// Post a premade quick-chat message, then refresh just the feed so the
    /// bubble (and anything clan-mates said meanwhile) appears immediately.
    private func sendQuickChat(_ kind: String) async {
        guard let clan = myClan else { return }
        chatSending = true; defer { chatSending = false }
        do {
            try await SocialClient.shared.postClanEvent(clanId: clan.id, kind: kind)
            await refreshEvents()
        } catch { flash("Couldn't send — try again.") }
    }

    /// Refresh only the feed, plus profiles for anyone it mentions that we
    /// haven't resolved yet — cheap enough to run from the chat poll.
    private func refreshEvents() async {
        guard let clan = myClan else { return }
        guard let evs = try? await SocialClient.shared.fetchClanEvents(clanId: clan.id) else { return }
        events = evs
        let mentioned = Set(evs.flatMap { [$0.actorId, $0.targetId].compactMap { $0 } })
        let unknown = mentioned.filter { rosterProfiles[$0] == nil }
        if !unknown.isEmpty,
           let profs = try? await SocialClient.shared.fetchProfiles(ids: Array(unknown)) {
            for p in profs { rosterProfiles[p.id] = p }
        }
    }

    /// Poll the feed every 20s while My Clan is on screen so the chat feels
    /// live.  Cancelled automatically when the view (or clan) goes away.
    private func pollChat() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            await refreshEvents()
        }
    }

    /// Owner-only rename (the settings sheet calls this).  Returns a
    /// user-facing error string, or nil on success.
    private func rename(to newName: String) async -> String? {
        guard let clan = myClan else { return "You're not in a clan." }
        do {
            try await SocialClient.shared.renameClan(id: clan.id, name: newName)
            try? await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "renamed")
            await load()
            flash("Clan renamed to “\(newName)”.")
            return nil
        } catch {
            return "Couldn't rename — that name may already be taken."
        }
    }

    /// Ask the leadership for a promotion — lands in the clan chat where the
    /// owner (and everyone else) sees it.
    private func askForPromotion() async -> Bool {
        guard let clan = myClan else { return false }
        do {
            try await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "requested_promotion")
            await refreshEvents()
            flash("Asked! Your request is in the clan chat 📣")
            return true
        } catch {
            flash("Couldn't ask — try again.")
            return false
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
// ClanDetailView — a clan's public detail, pushed from Browse or a deep link.
// Shows the roster + stats; lets you Join if you're not already in a clan.
// ===========================================================================
struct ClanDetailView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator
    @Environment(\.dismiss) var dismiss

    let clan: Clan
    @State private var roster:   [ClanMember] = []
    @State private var profiles: [UUID: PlayerProfile] = [:]
    @State private var myMembership: ClanMember?
    @State private var loading = true
    @State private var joining = false
    @State private var bannerText: String?

    private var myId: UUID? { SocialClient.shared.currentUserId }
    private var iAmMember: Bool { roster.contains { $0.playerId == myId } }
    private var inAnotherClan: Bool { (myMembership != nil) && myMembership?.clanId != clan.id }
    private var combinedLevels: Int { roster.reduce(0) { $0 + (profiles[$1.playerId]?.climbLevel ?? 0) } }

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    statsRow
                    joinAction
                    rosterSection
                }
                .padding(.horizontal, 16).padding(.vertical, 18)
            }
            .refreshable { await load() }
            if let bannerText { bannerView(bannerText) }
        }
        .navigationTitle(clan.name.nonEmpty ?? "Clan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 3) { Image(systemName: "chevron.left"); Text("Back") }.foregroundStyle(.white)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { nav.goHome() } label: { Image(systemName: "house.fill").foregroundStyle(.white) }
                    .accessibilityLabel("Home")
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if let t = clan.tag.nonEmpty {
                Text("[\(t)]").font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
            }
            Text(clan.name.nonEmpty ?? "Clan").font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white).multilineTextAlignment(.center)
            if let d = clan.description.nonEmpty {
                Text(d).font(.system(.callout, design: .rounded)).foregroundStyle(Color(white: 0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.13)))
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat("\(roster.count)", "Members", Color(red: 0.55, green: 0.78, blue: 1.0))
            stat("\(combinedLevels)", "Combined levels", Color(red: 0.30, green: 0.75, blue: 0.42))
        }
    }
    private func stat(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 6) {
            Text(v).font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
            Text(l).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Color(white: 0.48))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
    }

    @ViewBuilder
    private var joinAction: some View {
        if iAmMember {
            Text("You're a member of this clan")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(Color(red: 0.30, green: 0.75, blue: 0.42))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Capsule().fill(Color(red: 0.30, green: 0.75, blue: 0.42).opacity(0.16)))
        } else if inAnotherClan {
            Text("Leave your current clan to join another")
                .font(.system(.caption, design: .rounded)).foregroundStyle(Color(white: 0.5))
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        } else {
            Button { Task { await join() } } label: {
                ZStack {
                    Text("Join \(clan.name.nonEmpty ?? "clan")").opacity(joining ? 0 : 1)
                    if joining { ProgressView().tint(.white).scaleEffect(0.8) }
                }
                .font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Capsule().fill(Color(red: 0.20, green: 0.50, blue: 0.96)))
            }.disabled(joining).buttonStyle(.plain)
        }
    }

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "person.3.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.5))
                Text("ROSTER").font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(Color(white: 0.5)).tracking(0.5)
                Spacer()
            }
            if loading {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                ForEach(sorted) { m in rosterRow(m) }
            }
        }
    }

    private func rosterRow(_ m: ClanMember) -> some View {
        let prof = profiles[m.playerId]
        let nm = prof?.displayName.nonEmpty ?? "Climber"
        let lvl = prof?.climbLevel ?? 1
        let world = World.world(for: max(1, lvl))
        return Button { if let prof { nav.goToPlayer(prof) } } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(world.accent.opacity(0.28)).frame(width: 36, height: 36)
                    Text(String(nm.first ?? "?").uppercased())
                        .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
                Text(nm).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text("\(lvl)").font(.system(.caption2, design: .rounded).weight(.bold)).monospacedDigit()
                    .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(world.accent.opacity(0.28)))
                Spacer(minLength: 8)
                if m.role != "member" {
                    Text(m.role.capitalized).font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.81, blue: 0.30))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14)))
        }
        .buttonStyle(.plain).disabled(prof == nil)
    }

    private var sorted: [ClanMember] {
        roster.sorted { a, b in
            if a.isOwner != b.isOwner { return a.isOwner }
            return (profiles[a.playerId]?.climbLevel ?? 0) > (profiles[b.playerId]?.climbLevel ?? 0)
        }
    }

    private func bannerView(_ text: String) -> some View {
        VStack { Spacer()
            Text(text).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 12).background(Capsule().fill(Color(white: 0.18))).padding(.bottom, 28)
        }.transition(.move(edge: .bottom).combined(with: .opacity)).allowsHitTesting(false)
    }

    private func load() async {
        loading = true; defer { loading = false }
        myMembership = try? await SocialClient.shared.fetchMyClanMembership()
        if let members = try? await SocialClient.shared.fetchClanRoster(clanId: clan.id) {
            roster = members
            if let profs = try? await SocialClient.shared.fetchProfiles(ids: members.map { $0.playerId }) {
                var map: [UUID: PlayerProfile] = [:]
                for p in profs { map[p.id] = p }
                profiles = map
            }
        }
    }

    private func join() async {
        joining = true; defer { joining = false }
        do {
            try await SocialClient.shared.joinClan(id: clan.id)
            try? await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "joined")
            await load()
            // clan_join (S1-T6): latched on a successful join.
            gameState.recordClanJoined()
            flash("Joined \(clan.name.nonEmpty ?? "the clan")!")
        } catch {
            flash("Couldn't join — you may already be in a clan.")
        }
    }

    private func flash(_ text: String) {
        withAnimation { bannerText = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if bannerText == text { withAnimation { bannerText = nil } }
        }
    }
}

// ===========================================================================
// ClanCreateSheet — collects name / [TAG] / description and creates the clan.
// Posts a `created` activity event so the new clan's feed isn't empty.
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
        (2...32).contains(trimmedName.count) && (2...5).contains(trimmedTag.count) && trimmedDesc.count <= 200
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        field(title: "Clan name", text: $name, placeholder: "Marble Climbers", limit: 32)
                        field(title: "Tag (2–5 characters)", text: $tag, placeholder: "CLMB", limit: 5, uppercase: true)
                        field(title: "Description (optional)", text: $desc, placeholder: "What's your clan about?", limit: 200)
                        if let error {
                            Text(error).font(.system(.callout, design: .rounded)).foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.45))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New clan").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(.white) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .foregroundStyle(isValid ? Color(red: 0.40, green: 0.66, blue: 1.0) : Color(white: 0.4))
                        .disabled(!isValid || working)
                }
            }
        }
    }

    private func field(title: String, text: Binding<String>, placeholder: String, limit: Int, uppercase: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color(white: 0.5)).tracking(0.5)
            TextField("", text: text, prompt: Text(placeholder))
                .foregroundStyle(.white).autocorrectionDisabled()
                .textInputAutocapitalization(uppercase ? .characters : .sentences)
                .padding(.horizontal, 14).padding(.vertical, 12)
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
        working = true; error = nil
        do {
            let clan = try await SocialClient.shared.createClan(name: trimmedName, tag: trimmedTag, description: trimmedDesc)
            try? await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "created")
            onCreated(); dismiss()
        } catch {
            self.error = "Couldn't create — that name or tag may already be taken."
        }
        working = false
    }
}

// ===========================================================================
// ClanSettingsSheet — role-aware clan settings, opened from the gear in the
// My Clan toolbar.
//   Members & officers: see their role, ask the leadership for a promotion
//                       (lands in the clan chat), and leave the clan.
//   The owner:          renames the clan (future personalization/preference
//                       knobs slot into the same section) and can disband.
// Mutations run through the parent's closures so ClansView stays the single
// place that talks to SocialClient and refreshes clan state.
// ===========================================================================
private struct ClanSettingsSheet: View {
    @Environment(\.dismiss) var dismiss

    let clan: Clan
    let role: String                                  // owner | officer | member
    let alreadyAskedPromotion: Bool
    let onRename:       (String) async -> String?     // → error text, nil = ok
    let onAskPromotion: () async -> Bool
    let onLeave:        () -> Void
    let onDisband:      () -> Void

    @State private var name        = ""
    @State private var renameBusy  = false
    @State private var renameError: String?
    @State private var askBusy     = false
    @State private var asked       = false
    @State private var confirmLeave   = false
    @State private var confirmDisband = false

    private var isOwner:     Bool   { role == "owner" }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSaveName: Bool   { trimmedName != clan.name && (2...32).contains(trimmedName.count) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        roleCard
                        if isOwner { personalizationSection } else { promotionSection }
                        membershipSection
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Clan settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.white)
                }
            }
            .onAppear { name = clan.name }
        }
    }

    /// Who you are here — clan name + your role.
    private var roleCard: some View {
        HStack(spacing: 10) {
            Image(systemName: isOwner ? "crown.fill" : "person.fill")
                .font(.system(size: 18))
                .foregroundStyle(isOwner ? Color(red: 1.00, green: 0.81, blue: 0.30)
                                         : Color(red: 0.55, green: 0.78, blue: 1.0))
            VStack(alignment: .leading, spacing: 2) {
                Text(clan.name)
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(roleLine)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
    }

    private var roleLine: String {
        switch role {
        case "owner":   return "You're the owner"
        case "officer": return "You're an officer"
        default:        return "You're a member"
        }
    }

    // Owner: clan personalization — just the name today; description, tag,
    // colors and other preferences will live in this same section.
    private var personalizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Personalization")
            VStack(alignment: .leading, spacing: 7) {
                Text("CLAN NAME")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(white: 0.5)).tracking(0.5)
                TextField("", text: $name, prompt: Text("Clan name"))
                    .foregroundStyle(.white).autocorrectionDisabled()
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
                    .onChange(of: name) { _, newValue in
                        if newValue.count > 32 { name = String(newValue.prefix(32)) }
                    }
            }
            Button { Task { await saveName() } } label: {
                ZStack {
                    Text("Save name").opacity(renameBusy ? 0 : 1)
                    if renameBusy { ProgressView().tint(.white).scaleEffect(0.8) }
                }
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Capsule().fill(canSaveName ? Color(red: 0.20, green: 0.50, blue: 0.96)
                                                       : Color(white: 0.2)))
            }
            .disabled(!canSaveName || renameBusy).buttonStyle(.plain)
            if let renameError {
                Text(renameError)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.45))
            }
            Text("Renaming is announced in the clan chat.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
    }

    // Members & officers: ask the leadership to move you up.
    private var promotionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Role")
            if asked || alreadyAskedPromotion {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.30, green: 0.75, blue: 0.42))
                    Text("Asked — your request is in the clan chat.")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color(white: 0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
            } else {
                Button { Task { await ask() } } label: {
                    ZStack {
                        Text("Ask for a promotion 📣").opacity(askBusy ? 0 : 1)
                        if askBusy { ProgressView().tint(.white).scaleEffect(0.8) }
                    }
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Capsule().fill(Color(red: 0.20, green: 0.50, blue: 0.96)))
                }
                .disabled(askBusy).buttonStyle(.plain)
            }
            Text("Drops a note in the clan chat so the owner sees you'd like to move up.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
    }

    private var membershipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Membership")
            if isOwner {
                Button { confirmDisband = true } label: {
                    Text("Disband clan")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Capsule().fill(Color(red: 0.90, green: 0.30, blue: 0.32)))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Disband this clan? It's removed for every member.",
                                    isPresented: $confirmDisband, titleVisibility: .visible) {
                    Button("Disband", role: .destructive) { dismiss(); onDisband() }
                    Button("Cancel", role: .cancel) {}
                }
                Text("Disbanding removes the clan for everyone.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(white: 0.45))
            } else {
                Button { confirmLeave = true } label: {
                    Text("Leave clan")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Capsule().fill(Color(white: 0.22)))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Leave this clan?", isPresented: $confirmLeave,
                                    titleVisibility: .visible) {
                    Button("Leave", role: .destructive) { dismiss(); onLeave() }
                    Button("Cancel", role: .cancel) {}
                }
                Text("You can rejoin, or join another clan, anytime.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(Color(white: 0.5)).tracking(0.5)
    }

    private func saveName() async {
        renameBusy = true; renameError = nil
        let err = await onRename(trimmedName)
        renameBusy = false
        if let err { renameError = err } else { dismiss() }
    }

    private func ask() async {
        askBusy = true
        if await onAskPromotion() { asked = true }
        askBusy = false
    }
}

// MARK: - File-local helpers

/// Human "2m ago" from an ISO-8601 timestamp string (best effort).
private func relativeTime(_ iso: String?) -> String? {
    guard let iso else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let date else { return nil }
    let rel = RelativeDateTimeFormatter(); rel.unitsStyle = .short
    return rel.localizedString(for: date, relativeTo: Date())
}

private extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
