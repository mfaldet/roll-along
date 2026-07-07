import SwiftUI

// ===========================================================================
// PublicProfileView — another player's profile, in the same look as your own
// ProfileView, but driven by the remote `PlayerProfile` (so no local-only
// loadout/badges, which aren't synced).  Pushed via HomeRoute.player from any
// player name in Friends or a Clan roster, and from a rollalong://player/<id>
// deep link.  Back pops to wherever you came from; Home clears the stack.
//
// S3-T9 (fills the S2-T4 seam): this profile shows OTHER players, so its trophy
// showcase is driven by SERVER-synced data — the curated `player_showcase` row
// (per-grade counts + up to 3 showcased ids), fetched via `TrophySyncService`.
// We deliberately do NOT read the local `trophyEngine` LEDGER here (that would
// paint the VIEWER'S own trophies onto someone else's profile).  We DO resolve
// the showcased ids' display titles from the bundled `TrophyCatalog` (static
// content, identical for every install — not the viewer's unlock state) and
// the grade glyph/color from the single `TrophyGradeStyle` source (so the
// Diamond grade never borrows the cosmetic gem — design.md §2 R2).  When the
// player has no showcase (never set / toggled off / offline), we fall back to
// the honest placeholder instead of a fake.
// ===========================================================================
struct PublicProfileView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator
    @Environment(\.dismiss) var dismiss

    /// The profile to show.  May start as a partial row (from a search/roster,
    /// which omits coins/minigame stats); `.task` refreshes it to the full row.
    @State private var profile: PlayerProfile
    @State private var edges:   [Friendship] = []
    @State private var busy      = false
    @State private var sentLife  = false
    @State private var banner:   String?

    /// The fetched public trophy showcase for THIS profile (nil until loaded /
    /// when the player has none). S3-T9 — server-synced, never the local ledger.
    @State private var showcase: TrophyPublicShowcase?
    /// True while the first showcase fetch is in flight (so we show a spinner
    /// rather than the "coming soon" placeholder before we know).
    @State private var showcaseLoading = true

    init(player: PlayerProfile) { _profile = State(initialValue: player) }

    private var myId:  UUID? { SocialClient.shared.currentUserId }
    private var isMe:  Bool  { myId == profile.id }
    private var world: World { World.world(for: max(1, profile.climbLevel)) }

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.10),
                         Color(red: 0.09, green: 0.09, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    heroCard
                    if !isMe && SocialClient.shared.isSignedIn { actionRow }
                    statsGrid
                    trophySeamCard
                    PlayerRanksCard(profile: profile, playerId: profile.id)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 48)
            }

            if let banner { bannerView(banner) }
        }
        .navigationTitle(profile.displayName.nonEmptyName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(Color(red: 0.06, green: 0.06, blue: 0.10).opacity(0.95), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 3) { Image(systemName: "chevron.left"); Text("Back") }
                        .foregroundStyle(.white)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { nav.goHome() } label: {
                    Image(systemName: "house.fill").foregroundStyle(.white)
                }
                .accessibilityLabel("Home")
            }
        }
        .task { await refresh() }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(world.accent.opacity(0.28)).frame(width: 96, height: 96)
                    .overlay(Circle().stroke(world.accent.opacity(0.60), lineWidth: 1.5))
                Text(String(profile.displayName.first ?? "?").uppercased())
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.6), radius: 14, x: 0, y: 8)

            Text(profile.displayName.nonEmptyName)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                pill(text: "Level \(profile.climbLevel)", color: world.accent)
                pill(text: "\(profile.lives)", color: Color(red: 0.95, green: 0.32, blue: 0.45),
                     icon: "heart.fill")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .ppCard()
    }

    // MARK: - Social actions (Add friend / Send life)

    @ViewBuilder private var actionRow: some View {
        HStack(spacing: 10) {
            friendControl
            Button { Task { await sendLife() } } label: {
                actionLabel(sentLife ? "Sent ♥" : "Send life",
                            icon: "heart.fill",
                            tint: Color(red: 0.95, green: 0.32, blue: 0.45),
                            busy: busy && !sentLife)
            }
            .disabled(busy || sentLife)
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var friendControl: some View {
        switch relationship {
        case .friend:
            statusLabel("Friends", icon: "checkmark", tint: Color(red: 0.30, green: 0.75, blue: 0.42))
        case .outgoing:
            statusLabel("Requested", icon: "clock", tint: Color(white: 0.5))
        case .incoming:
            Button { Task { await accept() } } label: {
                actionLabel("Accept", icon: "person.badge.plus",
                            tint: Color(red: 0.20, green: 0.50, blue: 0.96), busy: busy)
            }
            .disabled(busy).buttonStyle(.plain)
        case .unrelated:
            Button { Task { await addFriend() } } label: {
                actionLabel("Add friend", icon: "person.badge.plus",
                            tint: Color(red: 0.20, green: 0.50, blue: 0.96), busy: busy)
            }
            .disabled(busy).buttonStyle(.plain)
        }
    }

    // MARK: - Stats

    private var statsGrid: some View {
        VStack(spacing: 16) {
            sectionLabel("Career")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCell("\(profile.climbLevel)",        "Climb Level", "flag.fill",  world.accent)
                statCell("\(profile.highestUnlocked)",   "Max Level",   "flag.checkered", Color(red: 0.30, green: 0.75, blue: 0.42))
                statCell("\(profile.totalStars)",        "Stars",       "star.fill",  Color(red: 1.0, green: 0.80, blue: 0.20))
                statCell("\(profile.coinsCollected ?? 0)", "Coins",     "circle.fill", Color(red: 0.95, green: 0.75, blue: 0.20))
                statCell("\(profile.lives)",             "Lives",       "heart.fill", Color(red: 0.95, green: 0.32, blue: 0.45))
                statCell(relationship == .friend ? "Yes" : "—", "Friend", "person.2.fill", Color(red: 0.58, green: 0.32, blue: 0.96))
            }
        }
        .padding(18)
        .ppCard()
    }

    // MARK: - Trophy showcase (S3-T9 — fills the S2-T4 seam)
    //
    // Renders the SERVER-synced curated showcase (per-grade counts + up to 3
    // showcased ids) fetched into `showcase`.  Never reads the viewer's own
    // ledger; showcased-id TITLES come from the bundled catalog (static content)
    // and grade glyph/color from `TrophyGradeStyle` (Diamond grade ≠ cosmetic
    // gem, design.md §2 R2).  Falls back to an honest placeholder when the
    // player has no showcase (never set / toggled off / offline).
    @ViewBuilder private var trophySeamCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Trophies")
            if let sc = showcase, !sc.isEmpty {
                showcaseHeader(sc)
                gradeStrip(sc)
                if !sc.showcasedIDs.isEmpty { showcasedStrip(sc) }
            } else if showcaseLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(Color(white: 0.6))
                    Text("Loading trophies…")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color(white: 0.55))
                    Spacer(minLength: 0)
                }
            } else {
                showcaseEmpty
            }
        }
        .padding(18)
        .ppCard()
    }

    private func showcaseHeader(_ sc: TrophyPublicShowcase) -> some View {
        HStack(spacing: 8) {
            Text("\(sc.earned) of \(sc.total)")
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text("· \(sc.completionPercent)% complete")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color(white: 0.5))
            Spacer(minLength: 0)
            if sc.capstone {
                Image(systemName: TrophyGradeStyle.forTier(.platinum).glyph)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(TrophyGradeStyle.forTier(.platinum).accent)
                    .accessibilityLabel("Platinum capstone earned")
            }
        }
    }

    private func gradeStrip(_ sc: TrophyPublicShowcase) -> some View {
        HStack(spacing: 8) {
            ForEach(TrophyTier.allCases.sorted(), id: \.self) { tier in
                gradeChip(tier: tier, count: sc.gradeCounts[tier] ?? 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gradeChip(tier: TrophyTier, count: Int) -> some View {
        let style = TrophyGradeStyle.forTier(tier)
        return VStack(spacing: 3) {
            Image(systemName: style.glyph)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(count > 0 ? style.accent : style.accent.opacity(0.35))
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(count > 0 ? .white : Color(white: 0.40))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.14))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(style.accent.opacity(count > 0 ? 0.5 : 0.12), lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tier.displayName), \(count) earned")
    }

    private func showcasedStrip(_ sc: TrophyPublicShowcase) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(sc.showcasedIDs, id: \.self) { id in
                    showcasedCell(id)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder private func showcasedCell(_ id: String) -> some View {
        // Resolve display metadata from the bundled catalog (static content, not
        // the viewer's ledger). An id the local catalog doesn't know (a newer
        // build authored it) still renders a neutral chip rather than vanishing.
        let def = gameState.trophyEngine.catalog.trophy(withID: id)
        let tier = def?.tier ?? .bronze
        let style = TrophyGradeStyle.forTier(tier)
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(style.accent.opacity(0.18)).frame(width: 52, height: 52)
                    .overlay(Circle().stroke(style.accent.opacity(0.48), lineWidth: 1.2))
                Image(systemName: style.glyph)
                    .font(.system(size: 22)).foregroundStyle(style.accent)
            }
            Text(def?.title ?? "Trophy")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(2)
            Text(tier.displayName)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Color(white: 0.45)).lineLimit(1)
        }
        .frame(width: 78)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(def?.title ?? "Trophy"), \(tier.displayName) grade")
    }

    private var showcaseEmpty: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy")
                .font(.system(size: 20))
                .foregroundStyle(Color(white: 0.45))
                .accessibilityHidden(true)
            Text(isMe ? "Turn on “Show Trophies on Profile” in Settings to share yours."
                      : "This roller hasn’t shared a trophy showcase.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color(white: 0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Relationship

    private enum Rel { case unrelated, friend, outgoing, incoming }
    private var relationship: Rel {
        guard let me = myId, let edge = edges.first(where: { $0.otherId(than: me) == profile.id }) else { return .unrelated }
        if edge.status == "accepted" { return .friend }
        if edge.isIncomingPending(for: me) { return .incoming }
        if edge.isOutgoingPending(for: me) { return .outgoing }
        return .unrelated
    }
    private var incomingEdge: Friendship? {
        guard let me = myId else { return nil }
        return edges.first { $0.isIncomingPending(for: me) && $0.otherId(than: me) == profile.id }
    }

    // MARK: - Data + actions

    private func refresh() async {
        if let full = try? await SocialClient.shared.fetchProfile(id: profile.id) { profile = full }
        if SocialClient.shared.isSignedIn, let e = try? await SocialClient.shared.fetchFriendships() { edges = e }
        // S3-T9: fetch this player's curated public showcase (nil = none / off /
        // offline → placeholder). Never reads the viewer's local ledger.
        showcase = await TrophySyncService.shared.fetchShowcase(for: profile.id)
        showcaseLoading = false
    }

    private func addFriend() async {
        busy = true; defer { busy = false }
        do { try await SocialClient.shared.sendFriendRequest(to: profile.id)
             if let e = try? await SocialClient.shared.fetchFriendships() { edges = e }
             flash("Request sent to \(profile.displayName.nonEmptyName).")
        } catch { flash("Couldn't send request — try again.") }
    }

    private func accept() async {
        guard let edge = incomingEdge else { return }
        busy = true; defer { busy = false }
        do { try await SocialClient.shared.acceptFriendRequest(id: edge.id)
             if let e = try? await SocialClient.shared.fetchFriendships() { edges = e }
             flash("You're now friends!")
        } catch { flash("Couldn't accept — try again.") }
    }

    private func sendLife() async {
        busy = true; defer { busy = false }
        do { try await SocialClient.shared.sendLife(to: profile.id, amount: 1)
             sentLife = true; flash("Life sent ♥")
        } catch { flash("Couldn't send a life — try again.") }
    }

    // MARK: - Small UI

    private func pill(text: String, color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
            Text(text).font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.28)).overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1)))
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statCell(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
            Text(label).font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.48)).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.125))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.20), lineWidth: 0.6)))
    }

    private func actionLabel(_ title: String, icon: String, tint: Color, busy: Bool) -> some View {
        ZStack {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(.subheadline, design: .rounded).weight(.semibold))
            }.opacity(busy ? 0 : 1)
            if busy { ProgressView().tint(.white).scaleEffect(0.7) }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Capsule().fill(tint))
    }

    private func statusLabel(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(.subheadline, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(tint).frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Capsule().fill(tint.opacity(0.16)))
    }

    private func bannerView(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 12)
                .background(Capsule().fill(Color(white: 0.18))).padding(.bottom, 28)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity)).allowsHitTesting(false)
    }

    private func flash(_ message: String) {
        withAnimation { banner = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if banner == message { withAnimation { banner = nil } }
        }
    }
}

// MARK: - File-local helpers

private extension String {
    /// A display-ready name, never blank.
    var nonEmptyName: String {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Anonymous Roller" : t
    }
}

private struct PPCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.105))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(white: 0.18), lineWidth: 0.8))
        )
    }
}
private extension View { func ppCard() -> some View { modifier(PPCardModifier()) } }
