import SwiftUI

// ===========================================================================
// GameMenuView — the hub for every mode that ISN'T the main climb.
//
// The home Play button is the 5,000-level Adventure climb (the spine).  Every
// other experience — Zen Garden, Coin Pit, and the competitive modes (Snake,
// Bumper Cars) as they come online — lives here, one tap off the main menu.
//
// DATA-DRIVEN: the list is `GameModeCatalogue.enabled` minus the climb, so
// flagging a new mode on in the catalogue makes it appear here automatically —
// no edits to this file.  A mode that's still gated off simply doesn't show.
//
// Each row routes through the existing `HomeRoute.mode(id)` destination, so the
// engine (BallGameView) launches the mode exactly as the old home capsules did.
// ===========================================================================

struct GameMenuView: View {
    @EnvironmentObject var nav: Navigator
    @Environment(\.dismiss) var dismiss

    /// Every enabled mode except the climb spine (which is the home Play button).
    private var modes: [GameMode] {
        GameModeCatalogue.enabled.filter { $0.id != GameModeCatalogue.climb.id }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.06), Color(white: 0.13)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    ForEach(modes, id: \.id) { mode in
                        NavigationLink(value: HomeRoute.mode(mode.id)) {
                            modeCard(mode)
                        }
                        .buttonStyle(.plain)
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
            Text("Take a break from the climb.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color(white: 0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    private func modeCard(_ mode: GameMode) -> some View {
        let style = Self.style(for: mode.id)
        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(style.accent.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: style.icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(style.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.displayName)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                if !mode.tagline.isEmpty {
                    Text(mode.tagline)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color(white: 0.6))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
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
                        .stroke(style.accent.opacity(0.18), lineWidth: 1)
                )
        )
    }

    /// Per-mode icon + accent, keyed by the catalogue id.  Unknown ids fall
    /// back to a generic controller glyph so a newly-flagged mode still renders.
    private static func style(for id: String) -> (icon: String, accent: Color) {
        switch id {
        case "zen":     return ("leaf.fill",             Color(red: 0.45, green: 0.80, blue: 0.55))
        case "coinpit": return ("dollarsign.circle.fill", Color(red: 1.00, green: 0.82, blue: 0.28))
        case "snake":   return ("scribble.variable",      Color(red: 0.50, green: 0.85, blue: 0.45))
        case "sumo":    return ("circle.dashed",          Color(red: 0.98, green: 0.45, blue: 0.40))
        case "paintball": return ("paintbrush.pointed.fill", Color(red: 0.25, green: 0.62, blue: 1.0))
        case "goldrush": return ("bag.fill",              Color(red: 1.00, green: 0.82, blue: 0.28))
        case "marblecup": return ("soccerball",           Color(red: 0.30, green: 0.62, blue: 1.0))
        case "koth":    return ("flag.fill",              Color(red: 0.30, green: 0.80, blue: 0.70))
        default:        return ("gamecontroller.fill",    Color(red: 0.55, green: 0.78, blue: 1.0))
        }
    }
}

#Preview {
    NavigationStack {
        GameMenuView().environmentObject(Navigator())
    }
}
