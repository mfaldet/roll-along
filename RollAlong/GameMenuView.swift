import SwiftUI

// ===========================================================================
// GameMenuView — the game hub, styled like a content storefront (Netflix /
// the App Store widget grid): a saturated, browseable shelf of games.
//
// LAYOUT (top → bottom)
//   • ROLL ALONG  — the core climb, always the largest widget, always on top.
//   • Challenge of the Day — a skinny banner (a short, brutal daily gauntlet).
//   • CHALLENGE PACKS — themed 100-level gauntlets (cosmetic rewards).
//   • COMPETITIVE     — mini-games vs. rivals (tickets, boards, a winner).
//   • NEW WAYS TO PLAY— a change of pace (Zen Garden, Pinball, the reward runs).
//
// Each category is a horizontal shelf of equal rounded-square widgets — the
// same fabric the home screen + Apple widgets use — so games can be reordered
// (popularity, launches, marketing) without changing how players navigate.
//
// DATA-DRIVEN: shelves group `GameModeCatalogue.enabled` by `section`, so
// flagging a new mode on makes it appear in the right shelf automatically.
// Every widget routes through the existing HomeRoute destinations.
// ===========================================================================

struct GameMenuView: View {
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var gameState: GameState
    @Environment(\.dismiss) var dismiss

    private var competitive: [GameMode] {
        GameModeCatalogue.enabled.filter { $0.section == .competitive }
    }
    private var newWays: [GameMode] {
        // Gold Rush (id "coinpit") is pulled out into its own full-width banner
        // below the Competitive shelf, so keep it out of this shelf.
        GameModeCatalogue.enabled.filter { $0.section == .solo && $0.id != Self.goldRushID }
    }

    /// The reward round shown as a full-width banner.  NB: the tile *displayed*
    /// as "Gold Rush" is catalogue id "coinpit" — the names were swapped with the
    /// competitive mode (id "goldrush", now displayed "Smash and Grab") on
    /// 2026-06-11; ids stayed put through that swap and the later rename.
    private static let goldRushID = "coinpit"
    private var packs: [ChallengeTrackMode] { GameModeCatalogue.challengeTracks }

    /// Arm a mode and return Home — the home Play button then launches it.
    /// (Replaces the old launch-on-tap so the player chooses, then confirms
    /// with Play.)  `modeID` is a catalogue id, e.g. "climb", "pinball",
    /// "challenge.frozen-peaks".
    private func select(_ modeID: String) {
        gameState.currentModeID = modeID
        nav.goHome()
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.05), Color(white: 0.12)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    rollAlongHero
                    levelsLink
                    challengeOfTheDay

                    challengePacksSection

                    shelf("COMPETITIVE",
                          "Mini-games vs. rivals — climb the boards, earn tickets.") {
                        ForEach(competitive, id: \.id) { modeWidget($0) }
                    }

                    goldRushBanner

                    shelf("NEW WAYS TO PLAY",
                          "A change of pace — different rules, different vibe.") {
                        ForEach(newWays, id: \.id) { modeWidget($0) }
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Games")
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
    }

    // MARK: - Header

    private var header: some View {
        Text("Choose the way you want to roll.")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - ROLL ALONG hero (the core game — biggest, on top)

    private var rollAlongHero: some View {
        Button { select("climb") } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(red: 0.42, green: 0.30, blue: 0.96),
                             Color(red: 0.95, green: 0.42, blue: 0.74),
                             Color(red: 0.99, green: 0.78, blue: 0.42)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)

                // A big glossy ball nestled in the corner.
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0.0)],
                        center: .init(x: 0.35, y: 0.30), startRadius: 2, endRadius: 90))
                    .frame(width: 150, height: 150)
                    .offset(x: 150, y: -28)
                    .blendMode(.plusLighter)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CORE GAME")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Roll Along")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("The endless climb · Level \(gameState.currentLevel)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                }
                .padding(20)
            }
            .frame(height: 184)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .shadow(color: Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.55), radius: 22, y: 9)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rollAlong")
        .accessibilityLabel("Roll Along, the core game. Level \(gameState.currentLevel).")
    }

    /// Small secondary affordance — replay any unlocked floor.
    private var levelsLink: some View {
        NavigationLink(value: HomeRoute.levels) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Replay levels")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color(white: 0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("levels")
    }

    // MARK: - Challenge of the Day (skinny banner)

    @ViewBuilder
    private var challengeOfTheDay: some View {
        let done   = gameState.dailyChallengeDoneToday
        let failed = gameState.dailyChallengeFailedToday
        if done || failed {
            // Once the day is decided, collapse to a slim, low-attention bar.
            dailyChallengeSlimBar(done: done)
        } else {
            // Fresh: the full orange call-to-action banner.
            dailyChallengeBanner
        }
    }

    /// Slim summary bar shown after the Challenge of the Day is cleared or failed
    /// — minimal height + attention, like a secondary button row.
    private func dailyChallengeSlimBar(done: Bool) -> some View {
        let ch    = gameState.todaysDailyChallenge
        let green = Color(red: 0.30, green: 0.92, blue: 0.50)
        return HStack(spacing: 9) {
            Image(systemName: done ? "checkmark.circle.fill" : "moon.zzz.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(done ? green : Color(white: 0.5))
            Text(done ? "Challenge of the Day cleared"
                      : "Challenge of the Day — out of attempts")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(done ? Color(white: 0.9) : Color(white: 0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            if done {
                HStack(spacing: 3) {
                    Text("+\(ch.rewardCoins)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(green)
                    CoinIcon(size: 12)
                }
            } else {
                dailyResetCountdown
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.13))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(done ? green.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(done
            ? "Challenge of the Day cleared today. Plus \(ch.rewardCoins) coins earned."
            : "Challenge of the Day: out of attempts today. Resets at midnight.")
        .accessibilityIdentifier("dailyChallenge")
    }

    /// Live H:MM:SS countdown to the next Challenge-of-the-Day reset (local
    /// midnight — the CotD is keyed by the calendar day).
    private var dailyResetCountdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let cal = Calendar.current
            let reset = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            let secs = max(0, Int(reset.timeIntervalSince(now)))
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .bold))
                Text(String(format: "%d:%02d:%02d", secs / 3600, (secs % 3600) / 60, secs % 60))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(Color(white: 0.5))
        }
    }

    /// Full orange call-to-action banner — shown only while today's challenge is
    /// still unplayed.
    private var dailyChallengeBanner: some View {
        let ch = gameState.todaysDailyChallenge
        return NavigationLink(value: HomeRoute.mode("daily")) {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CHALLENGE OF THE DAY")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(ch.title)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(ch.levelCount) brutal level\(ch.levelCount == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(11)
                    .background(Circle().fill(.white))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.96, green: 0.34, blue: 0.24),
                                 Color(red: 0.99, green: 0.63, blue: 0.20)],
                        startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: Color(red: 0.96, green: 0.4, blue: 0.2).opacity(0.35), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Challenge of the Day: \(ch.title). \(ch.levelCount) brutal levels.")
        .accessibilityIdentifier("dailyChallenge")
    }

    // MARK: - Gold Rush (full-width banner)

    /// Gold Rush gets its own full-width banner — same chrome as Challenge of the
    /// Day — sitting between the Competitive shelf and New Ways to Play.
    private var goldRushBanner: some View {
        let mode = GameModeCatalogue.enabled.first { $0.id == Self.goldRushID }
        let s = Self.style(for: Self.goldRushID)
        let tickets = gameState.tickets
        let noTickets = tickets <= 0
        return VStack(alignment: .leading, spacing: 6) {
            // No tickets to spend → say how to earn them, above a greyed card.
            if noTickets {
                Text("Win competitive games to earn tickets")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.leading, 4)
            }
            Button { select(Self.goldRushID) } label: {
                HStack(spacing: 14) {
                    Image(systemName: s.icon)
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REWARD ROUND")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(mode?.displayName ?? "Gold Rush")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(mode?.tagline ?? "Thirty seconds. Up to a hundred coins. Go.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                    // Ticket balance (spent to play Gold Rush) — replaces the play
                    // glyph; reads as "N 🎟" in white straight over the gradient.
                    HStack(spacing: 5) {
                        Text("\(tickets)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .monospacedDigit()
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(colors: s.colors,
                                             startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: (s.colors.first ?? .black).opacity(0.40), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .grayscale(noTickets ? 0.9 : 0)
            .opacity(noTickets ? 0.6 : 1)
            .accessibilityIdentifier(Self.goldRushID)
            .accessibilityLabel("\(mode?.displayName ?? "Gold Rush"). \(mode?.tagline ?? ""). " +
                                (noTickets ? "No tickets. Win competitive games to earn tickets."
                                           : "\(tickets) ticket\(tickets == 1 ? "" : "s")."))
        }
    }

    // MARK: - Shelves

    /// A captioned, horizontally-scrolling shelf of equal widgets.
    @ViewBuilder
    private func shelf<Content: View>(_ title: String, _ subtitle: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.5))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) { content() }
                    .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Widgets

    @ViewBuilder
    private func modeWidget(_ mode: GameMode) -> some View {
        let s = Self.style(for: mode.id)
        let locked = mode.id == "coinpit" && gameState.tickets <= 0
        if locked {
            widgetCard(icon: s.icon, colors: s.colors, title: mode.displayName,
                       locked: true)
                .accessibilityIdentifier(mode.id)
                .accessibilityLabel("\(mode.displayName). Locked. Win a competitive game to earn a ticket.")
        } else {
            Button { select(mode.id) } label: {
                widgetCard(icon: s.icon, colors: s.colors, title: mode.displayName,
                           ticket: mode.id == "coinpit" ? gameState.tickets : nil)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(mode.id)
        }
    }

    /// CHALLENGE PACKS — an 8-tile illustrative grid that taps through as a whole
    /// to the full Challenge Tracks page (replaces the old horizontal shelf + its
    /// "See all" tail tile).  No per-pack selection here; that lives on the
    /// Challenge Tracks page.
    private var challengePacksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CHALLENGE PACKS")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white)
                    Text("Themed hundred-level gauntlets — clear one for its cosmetics.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    Text("See all")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color(white: 0.6))
            }
            NavigationLink(value: HomeRoute.challengeTracks) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                          spacing: 12) {
                    ForEach(packs, id: \.id) { packTile($0) }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(white: 0.10))
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(white: 0.20), lineWidth: 1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tracks")
            .accessibilityLabel("Challenge Packs. Open all challenge tracks.")
        }
    }

    /// One small illustrative tile in the Challenge Packs grid — the pack's glyph
    /// on its gradient + its name.  Not individually tappable; the whole grid
    /// navigates to the Challenge Tracks page.
    private func packTile(_ track: ChallengeTrackMode) -> some View {
        let s = Self.packStyle(for: track.trackID)
        return VStack(spacing: 5) {
            ZStack {
                LinearGradient(colors: s.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: s.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(track.displayName)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// The shared game tile — a wide, centered, individually-branded card: a big
    /// logo in a frosted badge floating over an oversized watermark of the same
    /// glyph, the name centered beneath, all on the game's own gradient with a
    /// matching colored glow.  Used by every shelf (modes + challenge packs).
    private func widgetCard(icon: String, colors: [Color], title: String,
                            locked: Bool = false, ticket: Int? = nil) -> some View {
        let accent = colors.first ?? .white
        return ZStack {
            // Base gradient.
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            // Oversized watermark of the game's glyph — a themed, unique backdrop
            // that keeps each tile from blending into its neighbours.
            Image(systemName: icon)
                .font(.system(size: 132, weight: .bold))
                .foregroundStyle(.white.opacity(0.14))
                .rotationEffect(.degrees(-15))
                .offset(x: 74, y: 30)

            // Soft top-left sheen so the card reads glossy.
            RadialGradient(colors: [.white.opacity(0.38), .clear],
                           center: .init(x: 0.22, y: 0.12), startRadius: 2, endRadius: 150)
                .blendMode(.plusLighter)

            // Centered logo + name — the brand.
            VStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.20))
                        .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                        .frame(width: 64, height: 64)
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                }
                Text(title)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 228, height: 152)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        // Lock / ticket badge (top-right) — only modes that use it pass it in.
        .overlay(alignment: .topTrailing) {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(12)
            } else if let ticket {
                HStack(spacing: 2) {
                    Image(systemName: "ticket.fill").font(.system(size: 10, weight: .bold))
                    Text("\(ticket)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.30)))
                .padding(10)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.18), lineWidth: 1))
        .opacity(locked ? 0.5 : 1.0)
        .shadow(color: accent.opacity(0.55), radius: 14, y: 7)
    }

    // MARK: - Per-mode art (icon + saturated gradient), keyed by catalogue id

    private static func style(for id: String) -> (icon: String, colors: [Color]) {
        switch id {
        case "zen":      return ("leaf.fill",                [c(0.20, 0.72, 0.52), c(0.10, 0.50, 0.55)])
        case "coinpit":  return ("dollarsign.circle.fill",   [c(1.00, 0.80, 0.28), c(0.95, 0.55, 0.12)])
        case "snake":    return ("sparkles",                 [c(0.32, 0.55, 1.00), c(0.58, 0.30, 0.95)])
        case "sumo":     return ("circle.dashed",            [c(0.98, 0.45, 0.40), c(0.92, 0.30, 0.45)])
        case "paintball":return ("paintbrush.pointed.fill",  [c(0.30, 0.62, 1.00), c(0.90, 0.40, 0.80)])
        case "goldrush": return ("bag.fill",                 [c(1.00, 0.78, 0.30), c(0.90, 0.50, 0.15)])
        case "marblecup":return ("soccerball",               [c(0.30, 0.72, 0.55), c(0.22, 0.50, 0.85)])
        case "koth":     return ("flag.fill",                [c(0.25, 0.78, 0.70), c(0.20, 0.55, 0.60)])
        case "pinball":  return ("hand.tap.fill",            [c(0.74, 0.40, 0.96), c(0.92, 0.30, 0.70)])
        case "rollout":  return ("circle.grid.cross.fill",   [c(0.30, 0.78, 0.58), c(0.16, 0.52, 0.50)])
        case "rollup":   return ("arrow.up.circle.fill",     [c(0.36, 0.62, 1.00), c(0.40, 0.34, 0.92)])
        case "disco":    return ("circle.grid.3x3.fill",     [c(0.32, 0.85, 1.00), c(0.80, 0.30, 0.95)])
        default:         return ("gamecontroller.fill",      [c(0.40, 0.55, 0.95), c(0.30, 0.35, 0.80)])
        }
    }

    /// Themed gradient per Challenge Pack, matched to its cosmetic-reward theme.
    private static func packStyle(for trackID: String) -> (icon: String, colors: [Color]) {
        switch trackID {
        case "frozen-peaks":   return ("snowflake",          [c(0.55, 0.82, 1.00), c(0.30, 0.55, 0.92)])
        case "deep-cosmos":    return ("moon.stars.fill",    [c(0.42, 0.32, 0.85), c(0.20, 0.18, 0.55)])
        case "inferno-run":    return ("flame.fill",         [c(0.98, 0.45, 0.18), c(0.85, 0.18, 0.20)])
        case "neon-arcade":    return ("gamecontroller.fill",[c(0.95, 0.30, 0.80), c(0.30, 0.85, 0.95)])
        case "haunted-manor":  return ("moon.fill",          [c(0.50, 0.32, 0.72), c(0.18, 0.30, 0.28)])
        case "ancient-temple": return ("building.columns.fill", [c(0.92, 0.72, 0.30), c(0.62, 0.42, 0.18)])
        case "abyssal-depths": return ("water.waves",        [c(0.18, 0.45, 0.65), c(0.08, 0.22, 0.42)])
        case "golden-gauntlet":return ("crown.fill",         [c(1.00, 0.82, 0.30), c(0.72, 0.50, 0.12)])
        default:               return ("flag.checkered",     [c(0.95, 0.62, 0.30), c(0.80, 0.45, 0.20)])
        }
    }

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }
}

#Preview {
    NavigationStack {
        GameMenuView()
            .environmentObject(Navigator())
            .environmentObject(GameState())
    }
}
