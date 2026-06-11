import SwiftUI

// ===========================================================================
// GameMenuView — the hub for ALL game content, in designated areas.
//
// THE CLIMB   — the adventure spine's deeper cuts: the Levels grid (replay any
//               unlocked floor) and the Challenge Tracks (themed 100-level
//               gauntlets with bundle rewards).  These route to their own
//               select pages, not straight into an engine.
// COMPETITIVE — vs AI rivals; a winner is declared (Comet Clash, Sumo,
//               Paint Ball, Gold Rush, Marble Cup, King of the Hill).
// SOLO        — self-paced, no rivals (Zen Garden, Coin Pit, Pinball).
//
// DATA-DRIVEN: the two mode areas group `GameModeCatalogue.enabled` by each
// mode's `section`, so flagging a new mode on in the catalogue makes it appear
// in the right area automatically — no edits to this file.  Challenge Tracks
// are deliberately NOT listed as individual rows (their `section` is .climb);
// they're reached through the Tracks card so progress and rewards show on the
// proper select page.
//
// Each mode row routes through the existing `HomeRoute.mode(id)` destination,
// so the engine launches the mode exactly as before.
// ===========================================================================

struct GameMenuView: View {
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var gameState: GameState
    @Environment(\.dismiss) var dismiss

    /// Every enabled, individually-listed mode (the climb spine and the
    /// Challenge Tracks live behind the THE CLIMB cards instead).
    private var minigames: [GameMode] {
        GameModeCatalogue.enabled.filter { $0.section != .climb }
    }

    private var competitive: [GameMode] { minigames.filter { $0.section == .competitive } }
    private var solo:        [GameMode] { minigames.filter { $0.section == .solo } }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.06), Color(white: 0.13)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header

                    sectionCaption("THE CLIMB")
                    NavigationLink(value: HomeRoute.levels) {
                        hubCard(icon: "square.grid.3x3.fill",
                                accent: Color(red: 0.55, green: 0.78, blue: 1.0),
                                title: "Levels",
                                tagline: "Replay any floor of the adventure you've reached.")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("levels")

                    NavigationLink(value: HomeRoute.challengeTracks) {
                        hubCard(icon: "flag.checkered",
                                accent: Color(red: 0.95, green: 0.62, blue: 0.30),
                                title: "Challenge Tracks",
                                tagline: "Themed hundred-level gauntlets. Clear one for its cosmetic bundle.")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tracks")

                    sectionCaption("COMPETITIVE")
                    ForEach(competitive, id: \.id) { mode in
                        modeRow(mode)
                    }

                    sectionCaption("SOLO")
                    ForEach(solo, id: \.id) { mode in
                        modeRow(mode)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
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

    // MARK: - Sub-views

    private var header: some View {
        VStack(spacing: 6) {
            Text("Game Modes")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Every way to roll.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color(white: 0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    /// Tiny tracked caption naming a designated area — same recipe as the
    /// home screen's SOCIAL / ACCOUNT strips, sized for the hub list.
    private func sectionCaption(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Color(white: 0.45))
            .tracking(2.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
    }

    @ViewBuilder
    private func modeRow(_ mode: GameMode) -> some View {
        let style = Self.style(for: mode.id)
        if mode.id == "coinpit" {
            // Gold Rush costs tickets to play — gate entry when broke and
            // show the live balance on the card otherwise.
            if gameState.tickets > 0 {
                NavigationLink(value: HomeRoute.mode(mode.id)) {
                    hubCard(icon: style.icon, accent: style.accent,
                            title: mode.displayName, tagline: mode.tagline,
                            ticketBadge: gameState.tickets)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(mode.id)
            } else {
                hubCard(icon: style.icon, accent: style.accent,
                        title: mode.displayName,
                        tagline: "Needs a ticket — win a competitive game to earn one.",
                        ticketBadge: 0)
                    .opacity(0.45)
                    .accessibilityIdentifier(mode.id)
                    .accessibilityLabel("\(mode.displayName). Locked. Win a competitive game to earn a ticket.")
            }
        } else {
            NavigationLink(value: HomeRoute.mode(mode.id)) {
                hubCard(icon: style.icon, accent: style.accent,
                        title: mode.displayName, tagline: mode.tagline)
            }
            .buttonStyle(.plain)
            // accessibility identifier = mode id ("goldrush", "snake", …)
            // used by UI smoke tests: app.buttons["goldrush"].tap()
            .accessibilityIdentifier(mode.id)
        }
    }

    /// The shared card chrome for every hub entry — mode rows and the
    /// THE CLIMB cards alike.  `ticketBadge` (Gold Rush) shows the player's
    /// live ticket balance in a small gold capsule before the chevron.
    private func hubCard(icon: String, accent: Color,
                         title: String, tagline: String,
                         ticketBadge: Int? = nil) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                if !tagline.isEmpty {
                    Text(tagline)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color(white: 0.6))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let tickets = ticketBadge {
                HStack(spacing: 3) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("\(tickets)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(Color(red: 1.00, green: 0.82, blue: 0.28))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color(red: 1.00, green: 0.82, blue: 0.28).opacity(0.12))
                )
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(white: 0.4))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(white: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                )
        )
    }

    /// Per-mode icon + accent, keyed by the catalogue id.  Unknown ids fall
    /// back to a generic controller glyph so a newly-flagged mode still renders.
    private static func style(for id: String) -> (icon: String, accent: Color) {
        switch id {
        case "zen":     return ("leaf.fill",             Color(red: 0.45, green: 0.80, blue: 0.55))
        case "coinpit": return ("dollarsign.circle.fill", Color(red: 1.00, green: 0.82, blue: 0.28))
        case "snake":   return ("sparkles",               Color(red: 0.30, green: 0.72, blue: 1.00))
        case "sumo":    return ("circle.dashed",          Color(red: 0.98, green: 0.45, blue: 0.40))
        case "paintball": return ("paintbrush.pointed.fill", Color(red: 0.25, green: 0.62, blue: 1.0))
        case "goldrush": return ("bag.fill",              Color(red: 1.00, green: 0.82, blue: 0.28))
        case "marblecup": return ("soccerball",           Color(red: 0.30, green: 0.62, blue: 1.0))
        case "koth":    return ("flag.fill",              Color(red: 0.30, green: 0.80, blue: 0.70))
        case "pinball": return ("hand.tap.fill",          Color(red: 0.78, green: 0.42, blue: 0.95))
        default:        return ("gamecontroller.fill",    Color(red: 0.55, green: 0.78, blue: 1.0))
        }
    }
}

#Preview {
    NavigationStack {
        GameMenuView()
            .environmentObject(Navigator())
            .environmentObject(GameState())
    }
}
