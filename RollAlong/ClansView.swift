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
    enum Tab: Hashable { case mine, browse, rankings }
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
    /// A notice that stays until tapped (used for "you are no longer in …").
    @State private var stickyNotice: String?

    // Life requests I have already given to (server-read, see
    // SocialClient.fetchMyRequestGiftKeys) — a request can be given to once.
    @State private var givenRequestKeys: Set<String> = []

    // Clan rankings (read-only).
    @State private var rankings: [ClanRanking] = []
    @State private var rankSort: ClanRankSort = .season

    // Monthly clan battle.
    @State private var myStanding: ClanRanking?          // my clan's season score, wins, last finish
    @State private var seasonStars: [UUID: Int] = [:]    // each member's stars this season
    @State private var prizes: [SeasonPrize] = []        // unclaimed, newest first
    @State private var claimingPrize = false

    // Owner controls: the member waiting on a confirmation.
    @State private var confirmRemove: ClanMember?
    @State private var confirmHandOver: ClanMember?
    private var iAmOwner: Bool { membership?.isOwner ?? false }

    /// The clan this player was last seen in (id and name), kept on the
    /// device so a player who was removed can be told so.
    private static let lastClanIdKey = "ra_lastClanId"
    private static let lastClanNameKey = "ra_lastClanName"
    private static let lastClanPlayerKey = "ra_lastClanPlayer"   // whose clan it was
    @State private var rankingsLoading = false
    @State private var rankingsUnavailable = false

    private var myId: UUID? { SocialClient.shared.currentUserId }

    /// The request key of a member who is asking right now, else nil.
    private func openRequestKey(_ id: UUID) -> String? {
        // An expired request is no longer open, even before the server clears it.
        guard let prof = rosterProfiles[id], prof.isAskingForLives,
              let at = prof.needsLivesAt, !at.isEmpty else { return nil }
        return SocialClient.requestKey(id, at)
    }
    /// True when this clanmate has an open request I have not given to.
    private func needsMyLife(_ id: UUID) -> Bool {
        guard id != myId, let key = openRequestKey(id) else { return false }
        return !givenRequestKeys.contains(key)
    }
    /// The number on the red badge.
    private var openRequestCount: Int { roster.filter { needsMyLife($0.playerId) }.count }
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
            if let stickyNotice { stickyNoticeView(stickyNotice) }
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
                              ownerCanLeave:  SocialSettings.current.loadedFromServer && roster.count > 1,
                              onLeave:        { Task { await leave() } },
                              onDisband:      { Task { await disband() } })
        }
        .confirmationDialog(
            "Remove \(confirmRemove.map { memberName($0.playerId) } ?? "this member") from the clan?",
            isPresented: Binding(get: { confirmRemove != nil },
                                 set: { if !$0 { confirmRemove = nil } }),
            titleVisibility: .visible, presenting: confirmRemove
        ) { member in
            Button("Remove", role: .destructive) { Task { await remove(member) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("They can join again later. The stars they earned for the clan this season stay with the clan.")
        }
        .confirmationDialog(
            "Make \(confirmHandOver.map { memberName($0.playerId) } ?? "this member") the clan owner?",
            isPresented: Binding(get: { confirmHandOver != nil },
                                 set: { if !$0 { confirmHandOver = nil } }),
            titleVisibility: .visible, presenting: confirmHandOver
        ) { member in
            Button("Hand over ownership") { Task { await handOver(to: member) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You stay in the clan as a member. Only the new owner can undo this.")
        }
    }

    /// A member's shown name ("Roller" when unknown).
    private func memberName(_ id: UUID) -> String {
        rosterProfiles[id]?.displayName.nonEmpty ?? "Roller"
    }

    /// The owner's menu on another member's row: hand over, remove.
    private func ownerMenu(_ member: ClanMember) -> some View {
        Menu {
            Button { confirmHandOver = member } label: {
                Label("Make owner", systemImage: "crown")
            }
            Button(role: .destructive) { confirmRemove = member } label: {
                Label("Remove from clan", systemImage: "person.fill.badge.minus")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20))
                .foregroundStyle(Color(white: 0.6))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Owner options for \(memberName(member.playerId))")
    }

    private func remove(_ member: ClanMember) async {
        guard let clan = myClan, iAmOwner, member.playerId != myId else { return }
        busyIds.insert(member.playerId); defer { busyIds.remove(member.playerId) }
        let name = memberName(member.playerId)
        do {
            try await SocialClient.shared.removeClanMember(clanId: clan.id, playerId: member.playerId)
            try? await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "removed",
                                                         target: member.playerId)
            await load(); flash("\(name) was removed from the clan.")
        } catch { flash("Couldn't remove \(name) — try again.") }
    }

    private func handOver(to member: ClanMember) async {
        guard let clan = myClan, iAmOwner, member.playerId != myId else { return }
        actionBusy = true; defer { actionBusy = false }
        let name = memberName(member.playerId)
        do {
            try await SocialClient.shared.transferClanOwnership(clanId: clan.id, to: member.playerId)
            await load(); flash("\(name) is now the clan owner.")
        } catch { flash("Couldn't hand over the clan — try again.") }
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
                        if let prize = prizes.first { prizeCard(prize) }
                        if tab == .mine {
                            if inClan { myClanSections } else { createCallout }
                        } else if tab == .browse {
                            browseSections
                        } else {
                            rankingsSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    await load()
                    if tab == .rankings { await loadRankings() }
                }
            }
        }
    }

    private var segmentedNav: some View {
        Picker("", selection: $tab) {
            Text(inClan ? "My Clan" : "Create").tag(Tab.mine)
            Text("Browse").tag(Tab.browse)
            Text("Rankings").tag(Tab.rankings)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onChange(of: tab) { _, newTab in
            tabPinned = true
            if newTab == .rankings { Task { await loadRankings() } }
        }
    }

    // MARK: - Rankings (read-only)

    @ViewBuilder
    private var rankingsSection: some View {
        Picker("", selection: $rankSort) {
            Text("Season").tag(ClanRankSort.season)
            Text("Levels").tag(ClanRankSort.levels)
            Text("Stars").tag(ClanRankSort.stars)
        }
        .pickerStyle(.segmented)
        .onChange(of: rankSort) { _, _ in Task { await loadRankings() } }

        if rankSort == .season { seasonBanner }

        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Clan rankings", "list.number")
            if rankingsLoading && rankings.isEmpty {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if rankingsUnavailable {
                Text("Clan rankings are not available yet.")
                    .font(.system(.callout, design: .rounded)).foregroundStyle(Color(white: 0.5)).padding(.vertical, 6)
            } else if rankings.isEmpty {
                Text("No clans yet — be the first to start one.")
                    .font(.system(.callout, design: .rounded)).foregroundStyle(Color(white: 0.5)).padding(.vertical, 6)
            } else {
                ForEach(Array(rankings.enumerated()), id: \.element.id) { index, row in
                    rankingRow(row, rank: index + 1)
                }
            }
        }
    }

    /// "December season · 16 days left", and what the season is.
    private var seasonBanner: some View {
        let days = SeasonCalendar.daysRemaining()
        let prizesOn = SeasonCalendar.awardsPrizes(SeasonCalendar.seasonKey())
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(SeasonCalendar.monthName()) season · \(days) day\(days == 1 ? "" : "s") left")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(prizesOn
                 ? "A clan's score is the new Adventure stars its members earn this month. Top clans win coins at month end."
                 : "A clan's score is the new Adventure stars its members earn this month. This first season is a warm-up: clans are ranked, with no prizes.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
    }

    /// Last month's result with a Claim button.  Shown on the Clans screen
    /// until claimed; if several months are waiting, the newest shows first.
    private func prizeCard(_ prize: SeasonPrize) -> some View {
        let month = SeasonCalendar.monthName(prize.season)
        let tier = SeasonCalendar.tierName(prize.tier)
        let place = "\(SeasonCalendar.ordinal(prize.clanRank)) of \(prize.clansRanked)"
        return VStack(spacing: 10) {
            Text("\(month) season result")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color(white: 0.6)).tracking(0.5)
            Text("\(prize.clanName) finished \(place)")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white).multilineTextAlignment(.center)
            Text("\(tier.isEmpty ? "Ranked" : tier + " tier") · you earned \(prize.contribution) stars for the clan")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.65)).multilineTextAlignment(.center)
            Button { Task { await claim(prize) } } label: {
                ZStack {
                    Text("Claim \(prize.coins) coins").opacity(claimingPrize ? 0 : 1)
                    if claimingPrize { ProgressView().tint(.black).scaleEffect(0.8) }
                }
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Capsule().fill(Color(red: 1.0, green: 0.81, blue: 0.30)))
            }
            .disabled(claimingPrize).buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.13))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(red: 1.0, green: 0.81, blue: 0.30).opacity(0.7), lineWidth: 1.5)))
    }

    private func claim(_ prize: SeasonPrize) async {
        guard !claimingPrize else { return }
        claimingPrize = true
        defer { claimingPrize = false }
        do {
            // Server first: a failed call must never credit coins.
            let coins = try await SocialClient.shared.claimSeasonPrize(season: prize.season)
            if coins > 0 { gameState.addCoins(coins) }
            prizes.removeAll { $0.season == prize.season }
            flash(coins > 0 ? "\(coins) coins added!" : "That prize was already claimed.")
        } catch {
            flash("Couldn't claim — try again.")
        }
    }

    private func rankingRow(_ row: ClanRanking, rank: Int) -> some View {
        let mine = row.clan.id == myClan?.id
        let clanName: String = row.clan.name.nonEmpty ?? "Clan"
        let spoken: String = "Rank \(rank). \(clanName). \(row.memberCount) of \(Clan.memberCap) members. Season score \(row.seasonScore). \(row.totalLevels) total levels, \(row.totalStars) total stars. \(row.seasonWins) wins."
        return Button { nav.goToClan(row.clan) } label: {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold)).monospacedDigit()
                    .foregroundStyle(Color(white: 0.6))
                    .frame(minWidth: 26, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let t = row.clan.tag.nonEmpty {
                            Text("[\(t)]").font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
                        }
                        Text(row.clan.name.nonEmpty ?? "Clan")
                            .font(.system(.body, design: .rounded).weight(mine ? .bold : .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text("\(row.memberCount) of \(Clan.memberCap) members")
                            .font(.system(.caption2, design: .rounded)).foregroundStyle(Color(white: 0.5))
                        if let wins = row.winsLine {
                            Text(wins)
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(Color(red: 1.0, green: 0.81, blue: 0.30))
                        }
                    }
                    if let last = row.lastMonthLine {
                        Text(last)
                            .font(.system(.caption2, design: .rounded)).foregroundStyle(Color(white: 0.5))
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Image(systemName: rankSort == .levels ? "flag.fill" : "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(rankSort == .levels ? Color(red: 0.30, green: 0.75, blue: 0.42)
                                                             : Color(red: 1.0, green: 0.81, blue: 0.30))
                    Text("\(rankValue(row))")
                        .font(.system(.subheadline, design: .rounded).weight(.bold)).monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(mine ? Color(red: 0.20, green: 0.50, blue: 0.96).opacity(0.16) : Color(white: 0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
    }

    /// The number a ranking row shows for the current sort.
    private func rankValue(_ row: ClanRanking) -> Int {
        switch rankSort {
        case .season: return row.seasonScore
        case .levels: return row.totalLevels
        case .stars:  return row.totalStars
        }
    }

    private func loadRankings() async {
        let sort = rankSort
        rankingsLoading = true
        defer { rankingsLoading = false }
        do {
            let rows = try await SocialClient.shared.fetchClanRankings(sort: sort)
            guard sort == rankSort else { return }   // the sort changed meanwhile
            rankings = rows
            rankingsUnavailable = false
        } catch {
            guard sort == rankSort else { return }
            rankings = []
            rankingsUnavailable = true
        }
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
            if let standing = myStanding { ClanStandingLine(standing: standing) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 22)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.13))
                // Each member's equipped ball rolling slowly around the edge.
                ClanmatesOrbit(skins: memberSkins)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        )
    }

    /// Every current member's equipped ball (yours from this phone; others'
    /// as stored on the server, else the classic ball), owner first.
    private var memberSkins: [BallSkin] {
        sortedRoster.map { member in
            member.playerId == myId
                ? gameState.activeSkin
                : (rosterProfiles[member.playerId]?.ballSkin ?? .red)
        }
    }

    /// Members · combined climb levels · lives shared (a sense of the collective).
    private var clanStatsRow: some View {
        HStack(spacing: 10) {
            clanStat("\(roster.count) of \(Clan.memberCap)", "Members", "person.3.fill", Color(red: 0.55, green: 0.78, blue: 1.0))
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
        let settings = SocialSettings.current
        let wait = myId.flatMap { rosterProfiles[$0]?.askWaitRemaining() } ?? 0
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
                Text("Up to \(settings.requestSize) lives, one from each clanmate. Closes after \(settings.requestHours) hours.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { Task { await cancelAsk() } } label: {
                    actionLabel("Cancel request", busy: actionBusy, tint: Color(white: 0.22))
                }
                .disabled(actionBusy).buttonStyle(.plain)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.95, green: 0.32, blue: 0.45).opacity(0.14)))
        } else if wait > 0 {
            // The wait between requests, shown where the ask button is.
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                Text("You can ask again in \(Self.waitText(wait))")
            }
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(Color(white: 0.6))
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(Capsule().fill(Color(white: 0.16)))
            .accessibilityElement(children: .combine)
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

    /// "5 h 12 min" / "12 min" for a wait in seconds (rounded up to a minute).
    private static func waitText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(seconds / 60)))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
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
            // Red badge: open life requests I have not given to yet.
            sectionHeader("Roster", "person.3.fill")
                .overlay(alignment: .trailing) { CountBadge(count: openRequestCount) }
            ForEach(sortedRoster) { member in rosterRow(member) }
        }
    }

    /// Open life requests I can still give to first, then the owner, then by
    /// level descending.
    private var sortedRoster: [ClanMember] {
        roster.sorted { a, b in
            let na = needsMyLife(a.playerId), nb = needsMyLife(b.playerId)
            if na != nb { return na }
            if a.isOwner != b.isOwner { return a.isOwner }
            return (rosterProfiles[a.playerId]?.climbLevel ?? 0) > (rosterProfiles[b.playerId]?.climbLevel ?? 0)
        }
    }

    private func rosterRow(_ member: ClanMember) -> some View {
        let prof  = rosterProfiles[member.playerId]
        let name  = prof?.displayName.nonEmpty ?? "Roller"
        let level = prof?.climbLevel ?? 1
        let world = World.world(for: max(1, level))
        let isMe  = member.playerId == myId
        let asking = prof?.isAskingForLives ?? false
        let waitingOnMe = needsMyLife(member.playerId)
        return HStack(spacing: 12) {
            Button { if let prof { nav.goToPlayer(prof) } } label: {
                HStack(spacing: 12) {
                    avatar(name, tint: world.accent)
                        // Red badge on the request itself; clears when I give,
                        // or when the request is filled or cancelled.
                        .overlay(alignment: .topTrailing) {
                            CountBadge(count: waitingOnMe ? 1 : 0).offset(x: 6, y: -6)
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            PlayerNameLabel(name: name, level: level,
                                            font: .system(.body, design: .rounded).weight(isMe ? .bold : .semibold),
                                            compact: true,
                                            tint: isMe ? gameState.primaryColor : prof?.accentColor)
                            if member.isOwner && !isMe {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(red: 1.0, green: 0.81, blue: 0.30))
                                    .accessibilityLabel("Owner")
                            }
                        }
                        HStack(spacing: 8) {
                            SeasonStarsLabel(stars: seasonStars[member.playerId] ?? 0)
                            WeekPaceLabel(levels: prof?.levelsThisWeek ?? 0)
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
            if !isMe {
                sendLifeControl(member.playerId)
                if iAmOwner { ownerMenu(member) }
            } else { roleBadge(member.role) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(isMe ? AccentColor.readable(gameState.primaryColor).opacity(0.16)
                       : (asking ? Color(red: 0.95, green: 0.32, blue: 0.45).opacity(0.10) : Color(white: 0.14))))
    }

    @ViewBuilder
    private func sendLifeControl(_ id: UUID) -> some View {
        if let key = openRequestKey(id) {
            // An open request: each clanmate can give to it once.  Giving
            // never costs the giver a life.
            if givenRequestKeys.contains(key) {
                tag("Given ♥", Color(red: 0.95, green: 0.32, blue: 0.45))
            } else {
                actionButton("Give life", busy: busyIds.contains(id)) { await sendLife(to: id) }
            }
        } else if sentLifeIds.contains(id) {
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
        ("chat_nice",      "Nice rolling! 🔥"),
        ("chat_gl",        "Good luck! 🍀"),
        ("chat_ty",        "Thank you! 💙"),
    ]
    private static let quickChatText: [String: String] =
        Dictionary(uniqueKeysWithValues: quickChats.map { ($0.kind, $0.text) })

    /// Membership / clan changes render as centered one-liners, not bubbles.
    private static let systemKinds: Set<String> =
        ["created", "joined", "left", "renamed", "removed", "new_owner"]

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
        // Another member's name and badge use their stored accent color when
        // there is one, else the world color as before.
        let theirAccent = rosterProfiles[e.actorId]?.accentColor
        let nameColor = theirAccent.map(AccentColor.readable) ?? world.accent
        return HStack(alignment: .bottom, spacing: 8) {
            if mine {
                Spacer(minLength: 44)
            } else {
                avatar(who, tint: world.accent, size: 28)
            }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if !mine {
                    PlayerNameLabel(name: who,
                                    level: rosterProfiles[e.actorId]?.climbLevel ?? 1,
                                    font: .system(.caption2, design: .rounded).weight(.semibold),
                                    color: nameColor, compact: true,
                                    tint: theirAccent)
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
            .fill(mine ? AccentColor.readable(gameState.primaryColor).opacity(0.55)
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
        case "removed":
            let who = e.targetId.map { name(of: $0) } ?? "a member"
            return "\(actor) removed \(who) from the clan"
        case "new_owner":
            let who = e.targetId.map { name(of: $0) } ?? actor
            return who == "You" ? "You are now the clan owner" : "\(who) is now the clan owner"
        default:        return "\(actor) was here"
        }
    }

    private func eventIcon(_ kind: String) -> String {
        switch kind {
        case "joined", "created": return "person.fill.badge.plus"
        case "left":              return "person.fill.badge.minus"
        case "renamed":           return "pencil.line"
        case "removed":           return "person.fill.badge.minus"
        case "new_owner":         return "crown.fill"
        default:                  return "sparkle"
        }
    }

    private func name(of id: UUID) -> String {
        if id == myId { return "You" }
        return rosterProfiles[id]?.displayName.nonEmpty ?? "A roller"
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

    /// A banner that stays until the player taps it.
    private func stickyNoticeView(_ text: String) -> some View {
        VStack {
            Spacer()
            Button {
                withAnimation { stickyNotice = nil }
            } label: {
                VStack(spacing: 4) {
                    Text(text)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Tap to dismiss")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color(white: 0.6))
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.18)))
                .padding(.horizontal, 20).padding(.bottom, 28)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Dismisses this message.")
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
        guard auth.isSignedIn else { prizes = []; return }
        isLoading = true
        errorText = nil
        await SocialClient.shared.refreshSocialSettings()
        // Last month's result: shown here until claimed, in a clan or not.
        prizes = await SocialClient.shared.fetchUnclaimedPrizes()
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
                // Remember the clan, so a later removal can be explained.
                UserDefaults.standard.set(mem.clanId.uuidString, forKey: Self.lastClanIdKey)
                UserDefaults.standard.set(clan?.name ?? "", forKey: Self.lastClanNameKey)
                UserDefaults.standard.set(mem.playerId.uuidString, forKey: Self.lastClanPlayerKey)
                givenRequestKeys = await SocialClient.shared.fetchMyRequestGiftKeys()
                let sentToday = await SocialClient.shared.fetchMyGiftsToday()
                sentLifeIds.formUnion(sentToday)
                gameState.clanRequestBadge = openRequestCount
                myStanding  = await SocialClient.shared.fetchClanStanding(id: mem.clanId)
                seasonStars = await SocialClient.shared.fetchSeasonContributions(clanId: mem.clanId)
                if !tabPinned { tab = .mine }
            } else {
                myClan = nil; roster = []; events = []
                // In a clan last time and not now, without leaving: the owner
                // removed this player, or the clan was disbanded.  Say so once.
                if UserDefaults.standard.string(forKey: Self.lastClanIdKey) != nil {
                    let old = UserDefaults.standard.string(forKey: Self.lastClanNameKey)?.nonEmpty
                    // Only for the account that was in it (another account may
                    // have signed in on this device since).
                    let sameAccount = UserDefaults.standard.string(forKey: Self.lastClanPlayerKey)
                        == myId?.uuidString
                    Self.forgetLastClan()
                    if sameAccount {
                        withAnimation {
                            stickyNotice = "You are no longer in \(old ?? "your clan"). You were removed, or the clan was disbanded."
                        }
                    }
                }
                givenRequestKeys = []
                gameState.clanRequestBadge = 0
                myStanding = nil; seasonStars = [:]
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

    private static func forgetLastClan() {
        UserDefaults.standard.removeObject(forKey: lastClanIdKey)
        UserDefaults.standard.removeObject(forKey: lastClanNameKey)
        UserDefaults.standard.removeObject(forKey: lastClanPlayerKey)
    }

    private func leave() async {
        guard let clan = myClan else { return }
        actionBusy = true; defer { actionBusy = false }
        do {
            try? await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "left")
            try await SocialClient.shared.leaveClan(id: clan.id)
            Self.forgetLastClan()
            tabPinned = false; await load(); flash("You left the clan.")
        } catch { flash("Couldn't leave — try again.") }
    }

    private func disband() async {
        guard let clan = myClan else { return }
        actionBusy = true; defer { actionBusy = false }
        do {
            try await SocialClient.shared.disbandClan(id: clan.id)
            Self.forgetLastClan()
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
        } catch SocialError.http(_, let body) where body.contains("request_cooldown") {
            await load()
            flash("You asked recently — you can ask again after the wait.")
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
        let requestKey = openRequestKey(id)
        do {
            try await SocialClient.shared.sendLife(to: id, amount: 1)
            // The request is now one I have given to: its badge clears.
            if let requestKey {
                givenRequestKeys.insert(requestKey)
                gameState.clanRequestBadge = openRequestCount
            }
            try? await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "sent_life", target: id)
            // social_send_life / social_lives_sent_25 (S1-T6): every clan gift
            // counts toward lives sent, whether or not it fulfills a request.
            gameState.recordLifeSent()
            // clan_fulfill (S1-T6): additionally, a gift to an asking clanmate.
            if wasAsking { gameState.recordClanRequestFulfilled() }
            // An ordinary gift uses up today's "Send life" to this player; a
            // gift that answered a request does not.
            if requestKey == nil { sentLifeIds.insert(id) }
            flash("Life sent ♥")
        } catch SocialError.http(_, let body) where body.contains("already_gave") {
            // The server refused a second gift to the same request.
            if let requestKey { givenRequestKeys.insert(requestKey) }
            gameState.clanRequestBadge = openRequestCount
            flash("You already gave to this request.")
        } catch SocialError.http(_, let body) where body.contains("gift_limit") {
            sentLifeIds.insert(id)
            flash("You already sent this player a life today.")
        } catch { flash("Couldn't send a life — try again.") }
    }

    /// Re-read who is asking and what I have given to, so a request that was
    /// filled, cancelled or newly posted shows within one poll.
    private func refreshRequests() async {
        guard let clan = myClan,
              let members = try? await SocialClient.shared.fetchClanRoster(clanId: clan.id),
              let profs = try? await SocialClient.shared.fetchProfiles(ids: members.map { $0.playerId })
        else { return }
        roster = members
        for p in profs { rosterProfiles[p.id] = p }
        givenRequestKeys = await SocialClient.shared.fetchMyRequestGiftKeys()
        gameState.clanRequestBadge = openRequestCount
        seasonStars = await SocialClient.shared.fetchSeasonContributions(clanId: clan.id)
        if let standing = await SocialClient.shared.fetchClanStanding(id: clan.id) { myStanding = standing }
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
            await refreshRequests()
        }
    }

    /// Owner-only rename (the settings sheet calls this).  Returns a
    /// user-facing error string, or nil on success.
    private func rename(to choice: PresetNames.Choice) async -> String? {
        guard let clan = myClan else { return "You're not in a clan." }
        let newName = PresetNames.clanName(choice)
        do {
            try await SocialClient.shared.renameClan(id: clan.id, name: choice)
            try? await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "renamed")
            await load()
            flash("Clan renamed to “\(newName)”.")
            return nil
        } catch {
            return "Couldn't rename — that name is taken. Try a different number."
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
    @State private var standing: ClanRanking?           // season score, wins, last finish
    @State private var seasonStars: [UUID: Int] = [:]   // each member's stars this season

    private var myId: UUID? { SocialClient.shared.currentUserId }
    private var iAmMember: Bool { roster.contains { $0.playerId == myId } }
    private var inAnotherClan: Bool { (myMembership != nil) && myMembership?.clanId != clan.id }
    private var combinedLevels: Int { roster.reduce(0) { $0 + (profiles[$1.playerId]?.climbLevel ?? 0) } }
    private var combinedStars:  Int { roster.reduce(0) { $0 + (profiles[$1.playerId]?.totalStars ?? 0) } }
    private var isFull: Bool { roster.count >= Clan.memberCap }

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
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

    /// Compact header: tag and name on one line, the description, then one
    /// line of totals ("7 of 12 members · 412 levels · 980 stars").
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let t = clan.tag.nonEmpty {
                    Text("[\(t)]").font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
                }
                Text(clan.name.nonEmpty ?? "Clan").font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            if let d = clan.description.nonEmpty {
                Text(d).font(.system(.footnote, design: .rounded)).foregroundStyle(Color(white: 0.6))
            }
            if !loading {
                Text("\(roster.count) of \(Clan.memberCap) members · \(combinedLevels) levels · \(combinedStars) stars")
                    .font(.system(.caption, design: .rounded).weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Color(white: 0.72))
            }
            if let standing { ClanStandingLine(standing: standing, centered: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22).padding(.horizontal, 22)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.13))
                ClanmatesOrbit(skins: roster.map { m in
                    m.playerId == myId ? gameState.activeSkin : (profiles[m.playerId]?.ballSkin ?? .red)
                })
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        )
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
        } else if loading {
            EmptyView()
        } else if isFull {
            Text("This clan is full (\(Clan.memberCap) of \(Clan.memberCap) members)")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(Color(white: 0.6))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Capsule().fill(Color(white: 0.16)))
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
                Text("MEMBERS").font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(Color(white: 0.5)).tracking(0.5)
                Spacer()
            }
            if loading {
                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, m in
                    rosterRow(m, rank: index + 1)
                }
            }
        }
    }

    /// One ranked member: rank, name, level badge, role, stars and this
    /// week's levels.
    private func rosterRow(_ m: ClanMember, rank: Int) -> some View {
        let prof = profiles[m.playerId]
        let nm = prof?.displayName.nonEmpty ?? "Roller"
        let lvl = prof?.climbLevel ?? 1
        let stars = prof?.totalStars ?? 0
        let roleText: String = m.role != "member" ? ", \(m.role)" : ""
        let spoken: String = "Rank \(rank). \(nm), level \(lvl), \(stars) stars\(roleText)."
        return Button { if let prof { nav.goToPlayer(prof) } } label: {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold)).monospacedDigit()
                    .foregroundStyle(Color(white: 0.6))
                    .frame(minWidth: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        PlayerNameLabel(name: nm, level: lvl, compact: true,
                                        tint: m.playerId == myId ? gameState.primaryColor : prof?.accentColor)
                        if m.role != "member" {
                            Text(m.role.capitalized).font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(Color(red: 1.0, green: 0.81, blue: 0.30))
                        }
                    }
                    HStack(spacing: 8) {
                        SeasonStarsLabel(stars: seasonStars[m.playerId] ?? 0)
                        WeekPaceLabel(levels: prof?.levelsThisWeek ?? 0)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 11))
                        .foregroundStyle(Color(red: 1.0, green: 0.81, blue: 0.30))
                    Text("\(stars)").font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit().foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.14)))
        }
        .buttonStyle(.plain).disabled(prof == nil)
        .accessibilityLabel(spoken)
    }

    /// Ranked by level, then stars.
    private var sorted: [ClanMember] {
        roster.sorted { a, b in
            let la = profiles[a.playerId]?.climbLevel ?? 0, lb = profiles[b.playerId]?.climbLevel ?? 0
            if la != lb { return la > lb }
            return (profiles[a.playerId]?.totalStars ?? 0) > (profiles[b.playerId]?.totalStars ?? 0)
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
        await SocialClient.shared.refreshSocialSettings()
        standing    = await SocialClient.shared.fetchClanStanding(id: clan.id)
        seasonStars = await SocialClient.shared.fetchSeasonContributions(clanId: clan.id)
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
        } catch SocialError.http(_, let body) where body.contains("clan_full") {
            await load()
            flash("This clan is full (\(Clan.memberCap) members).")
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
// ClanCreateSheet — picks a preset-built name (+ derived tag) and an optional
// preset description, and creates the clan.
// Posts a `created` activity event so the new clan's feed isn't empty.
// ===========================================================================
private struct ClanCreateSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var choice = PresetNames.randomClanChoice()
    @State private var descIndex: Int? = nil       // nil = no description
    @State private var working = false
    @State private var error:  String?
    let onCreated: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ClanNamePicker(choice: $choice)
                        ClanDescriptionPicker(selection: $descIndex)
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
                        .foregroundStyle(Color(red: 0.40, green: 0.66, blue: 1.0))
                        .disabled(working)
                }
            }
        }
    }

    private func create() async {
        working = true; error = nil
        do {
            let desc = descIndex.map { PresetNames.clanDescriptions[$0] } ?? ""
            let clan = try await SocialClient.shared.createClan(name: choice, description: desc)
            try? await SocialClient.shared.postClanEvent(clanId: clan.id, kind: "created")
            onCreated(); dismiss()
        } catch {
            self.error = "Couldn't create — that name is taken. Try a different number."
        }
        working = false
    }
}

// ===========================================================================
// ClanNamePicker / ClanDescriptionPicker — the ONLY ways to set a clan's
// name, tag and description.  Everything is assembled from `PresetNames`
// lists; there is no text field, so there is no user-written content.
// ===========================================================================
private struct ClanNamePicker: View {
    @Binding var choice: PresetNames.Choice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLAN NAME").font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color(white: 0.5)).tracking(0.5)
            HStack(spacing: 8) {
                Text("[\(PresetNames.clanTag(choice))]")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
                Text(PresetNames.clanName(choice))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Button {
                    choice = PresetNames.randomClanChoice()
                } label: {
                    Image(systemName: "shuffle").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white).padding(9)
                        .background(Circle().fill(Color(white: 0.2)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shuffle name")
            }
            PresetNameWheels(choice: $choice,
                             adjectives: PresetNames.clanAdjectives,
                             nouns: PresetNames.clanNouns,
                             numbers: PresetNames.clanNumbers)
            Text("Pick two words and a number. The tag is made from the name.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
    }
}

private struct ClanDescriptionPicker: View {
    @Binding var selection: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESCRIPTION (OPTIONAL)").font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Color(white: 0.5)).tracking(0.5)
            ForEach(0..<PresetNames.clanDescriptions.count, id: \.self) { i in
                Button {
                    selection = (selection == i) ? nil : i
                } label: {
                    HStack {
                        Text(PresetNames.clanDescriptions[i])
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if selection == i {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(red: 0.30, green: 0.75, blue: 0.42))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14)))
                }
                .buttonStyle(.plain)
            }
        }
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
    let onRename:       (PresetNames.Choice) async -> String?   // → error text, nil = ok
    let onAskPromotion: () async -> Bool
    /// True when the owner may leave: there is someone to hand the clan to,
    /// and the server rule that does the hand-over is in place.
    var ownerCanLeave: Bool = false
    let onLeave:        () -> Void
    let onDisband:      () -> Void

    @State private var nameChoice  = PresetNames.randomClanChoice()
    @State private var renameBusy  = false
    @State private var renameError: String?
    @State private var askBusy     = false
    @State private var asked       = false
    @State private var confirmLeave   = false
    @State private var confirmDisband = false

    private var isOwner:     Bool   { role == "owner" }
    private var canSaveName: Bool   { PresetNames.clanName(nameChoice) != clan.name }

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
            .onAppear {
                // Start the wheels on the current name when it is preset-format.
                if let current = PresetNames.parseClanName(clan.name) { nameChoice = current }
            }
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
                Text(clan.name.isEmpty ? "Clan" : clan.name)
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

    // Owner: clan personalization — the name (built from preset words; the tag
    // follows the name).
    private var personalizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Personalization")
            ClanNamePicker(choice: $nameChoice)
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
                if ownerCanLeave {
                    Button { confirmLeave = true } label: {
                        Text("Leave clan")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Capsule().fill(Color(white: 0.22)))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Leave your own clan?", isPresented: $confirmLeave,
                                        titleVisibility: .visible) {
                        Button("Leave", role: .destructive) { dismiss(); onLeave() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The clan passes to its longest-standing member.")
                    }
                    Text("To choose the next owner yourself, use the menu beside a member on the roster. If you leave without choosing, the clan passes to its longest-standing member.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(white: 0.45))
                }
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
        let err = await onRename(nameChoice)
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

// ===========================================================================
// ClanmatesOrbit — each clan member's ball rolling slowly around the inside
// edge of the clan header tile, evenly spaced.  Drawn behind the clan name
// (the header's padding keeps the text clear of the track).  With Reduce
// Motion on, the balls sit still at their spaced positions.
// ===========================================================================
struct ClanmatesOrbit: View {
    let skins: [BallSkin]

    /// Ball size and how far in from the tile's edge the track runs.
    static let ballSize: CGFloat = 13
    static let inset: CGFloat = 5
    /// Seconds for one ball to go once around the tile.
    static let lapSeconds: Double = 40

    /// Switch to turn the rolling balls off everywhere (set to false and
    /// rebuild) if they ever slow the Clans screen down.
    static let isEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            if Self.isEnabled {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                orbit(in: geo.size, time: t)
            }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func orbit(in size: CGSize, time: Double) -> some View {
        let r = Self.ballSize / 2
        let track = CGRect(x: Self.inset + r, y: Self.inset + r,
                           width: max(0, size.width - 2 * (Self.inset + r)),
                           height: max(0, size.height - 2 * (Self.inset + r)))
        let perimeter = 2 * (track.width + track.height)
        let count = max(1, skins.count)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(skins.enumerated()), id: \.offset) { index, skin in
                let progress = (time / Self.lapSeconds + Double(index) / Double(count))
                    .truncatingRemainder(dividingBy: 1)
                let distance = CGFloat(progress) * perimeter
                BallSkinView(skin: skin, diameter: Self.ballSize)
                    .frame(width: Self.ballSize, height: Self.ballSize)
                    // Rolling: the ball turns by the distance it has travelled.
                    .rotationEffect(.radians(Double(distance / max(r, 1))))
                    .position(Self.point(at: distance, on: track))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// The point `distance` along the rectangle's edge, clockwise from the
    /// top-left corner.
    static func point(at distance: CGFloat, on rect: CGRect) -> CGPoint {
        guard rect.width > 0 || rect.height > 0 else { return CGPoint(x: rect.midX, y: rect.midY) }
        var d = distance.truncatingRemainder(dividingBy: 2 * (rect.width + rect.height))
        if d < 0 { d += 2 * (rect.width + rect.height) }
        if d <= rect.width { return CGPoint(x: rect.minX + d, y: rect.minY) }
        d -= rect.width
        if d <= rect.height { return CGPoint(x: rect.maxX, y: rect.minY + d) }
        d -= rect.height
        if d <= rect.width { return CGPoint(x: rect.maxX - d, y: rect.maxY) }
        d -= rect.width
        return CGPoint(x: rect.minX, y: rect.maxY - d)
    }
}
