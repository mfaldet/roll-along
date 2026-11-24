import SwiftUI
import AVFoundation
import UIKit

// ===========================================================================
// GameMenuView — the game hub, styled like a content storefront (Netflix /
// the App Store widget grid): a saturated, browseable shelf of games.
//
// LAYOUT (top → bottom)
//   • ROLL ALONG  — the core climb, always the largest widget, always on top.
//   • Challenge of the Day — a skinny banner (held back for 1.0; shown only
//     if its mode is switched back on in GameModeCatalogue).
//   • CHALLENGE PACKS — themed 100-level gauntlets (cosmetic rewards).
//   • MINIGAMES       — one button that opens `MinigamesGridView`, a
//                       two-column grid of every available minigame.
//
// DATA-DRIVEN: the grid lists `GameModeCatalogue.enabled` minigames, so a mode
// switched off in the registry disappears from it automatically.  Their order
// is `MinigamesGridView.soloOrder` / `competitiveOrder` / `rewardOrder`.
// ===========================================================================

struct GameMenuView: View {
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var gameState: GameState
    @Environment(\.dismiss) var dismiss

    private var packs: [ChallengeTrackMode] { GameModeCatalogue.challengeTracks }

    /// Arm a mode and return Home — the home Play button then launches it.
    /// (Replaces the old launch-on-tap so the player chooses, then confirms
    /// with Play.)  `modeID` is a catalogue id, e.g. "climb", "zen",
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
                    // S2-T7: the "what am I chasing?" chase chips — a compact,
                    // horizontal strip of the player's pinned trophies, each
                    // showing live progress read from the engine.  Renders
                    // nothing when nothing is pinned (or every pin is earned).
                    ChaseChipStrip(engine: gameState.trophyEngine,
                                   pins: gameState.trophyPins)

                    rollAlongHero
                    levelsLink
                    // Challenge of the Day is held back for 1.0 (its mode is
                    // off in GameModeCatalogue); show it only if it is on.
                    if GameModeCatalogue.mode(id: "daily") != nil { challengeOfTheDay }

                    challengePacksSection

                    minigamesButton

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            // S2-T2: the game-menu return surface — a trophy-unlock banner
            // host, drained on appearance below.  Covers any pending unlock a
            // run left un-presented (e.g. the player popped Home straight from
            // a result screen).  Inert when nothing is pending (§6).
            TrophyToastHost(queue: gameState.trophyToasts,
                            hapticsEnabled: gameState.hapticsEnabled,
                            soundEnabled: gameState.soundEnabled)

            // S2-T5: the hub is a run-end surface, so it also hosts the
            // Platinum-capstone blowout — covers a capstone latched in a
            // minigame the player exits straight to the menu.  The model gates
            // it to fire exactly once ever; inert when nothing is armed.
            CapstoneCelebrationHost(
                model: gameState.capstoneCelebration,
                skin: gameState.activeSkin,
                trail: gameState.equippedTrail,
                hapticsEnabled: gameState.hapticsEnabled,
                soundEnabled: gameState.soundEnabled)
        }
        .onAppear {
            // Returning to the hub is a run-end surface (sprint-plan §2 S2-T2):
            // flush anything a just-finished run accumulated as one coalesced
            // banner.  Safe when idle — presents nothing if the buffer's empty.
            gameState.endTrophyRun()
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
                    GameModeCardTitle(label: "CORE GAME",
                                      title: "Roll Along",
                                      line: "Endless Adventure · Level \(gameState.currentLevel)")
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

    // MARK: - Minigames

    /// One full-width button that opens the minigames grid.  Replaces the
    /// sideways-scrolling shelves (and the Gold Rush banner, which is now a
    /// tile in the grid).
    private var minigamesButton: some View {
        let count = MinigamesGridView.available.count
        return NavigationLink(value: HomeRoute.minigames) {
            HStack(alignment: .bottom) {
                // Same lettering as the Roll Along card, without a line.
                GameModeCardTitle(label: "ARCADE · \(count) GAMES", title: "Minigames")
                Spacer(minLength: 8)
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(LinearGradient(colors: [Self.c(0.36, 0.62, 1.00), Self.c(0.80, 0.30, 0.95)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: Self.c(0.36, 0.62, 1.00).opacity(0.45), radius: 16, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Minigames. \(count) games.")
        .accessibilityIdentifier("MinigamesButton")
    }

    /// CHALLENGE PACKS — one card over the looping gameplay replay, with the
    /// same lettering as the Roll Along card.  The whole card opens the full
    /// Challenge Tracks page; a "See all" chip inside it says so.
    private var challengePacksSection: some View {
        let cleared = packs.filter { gameState.completedTracks.contains($0.trackID) }.count
        let line = "\(packs.count) tracks · \(cleared) cleared"
        return NavigationLink(value: HomeRoute.challengeTracks) {
            ZStack(alignment: .topLeading) {
                // A looping "video" that revolves through each pack's reward
                // collection, shown as a live loadout diorama.
                ChallengePackShowcase(entries: packShowcaseEntries)

                // Top scrim so the title reads over any floor color.
                LinearGradient(colors: [.black.opacity(0.55), .clear],
                               startPoint: .top, endPoint: .center)
                    .allowsHitTesting(false)

                GameModeCardTitle(label: "THEMED TRACKS", title: "Challenge Packs", line: line)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                    .padding(20)
            }
            // "See all" lives inside the card, bottom right.
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 3) {
                    Text("See all")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(.black.opacity(0.45)))
                .padding(14)
            }
            .frame(height: 184)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26)
                .stroke(Color(white: 0.20), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("tracks")
        .accessibilityLabel("Challenge Packs. \(packs.count) tracks, \(cleared) cleared. Opens all challenge tracks.")
    }

    /// The challenge-pack collections the showcase cycles through: each track
    /// paired with the loadout of the cosmetic bundle it unlocks, plus the pack's
    /// glyph/accent for the corner chip.
    private var packShowcaseEntries: [ChallengePackShowcase.Entry] {
        packs.compactMap { track in
            guard let bid = ChallengeTrackMode.rewardBundleID(for: track.trackID),
                  let bundle = CosmeticBundle.catalogue.first(where: { $0.id == bid })
            else { return nil }
            let style = Self.packStyle(for: track.trackID)
            return ChallengePackShowcase.Entry(
                id:      track.trackID,
                name:    track.displayName,
                icon:    style.icon,
                accent:  style.colors.first ?? .white,
                loadout: Loadout(bundle: bundle))
        }
    }

    // MARK: - Per-mode art (icon + saturated gradient), keyed by catalogue id

    static func style(for id: String) -> (icon: String, colors: [Color]) {
        switch id {
        case "zen":      return ("leaf.fill",                [c(0.20, 0.72, 0.52), c(0.10, 0.50, 0.55)])
        case "coinpit":  return ("dollarsign.circle.fill",   [c(1.00, 0.80, 0.28), c(0.95, 0.55, 0.12)])
        case "snake":    return ("ellipsis",                 [c(0.32, 0.55, 1.00), c(0.58, 0.30, 0.95)])
        case "sumo":     return ("circle.dashed",            [c(0.98, 0.45, 0.40), c(0.92, 0.30, 0.45)])
        case "paintball":return ("paintbrush.pointed.fill",  [c(0.30, 0.62, 1.00), c(0.90, 0.40, 0.80)])
        case "goldrush": return ("bag.fill",                 [c(1.00, 0.78, 0.30), c(0.90, 0.50, 0.15)])
        case "marblecup":return ("soccerball",               [c(0.30, 0.72, 0.55), c(0.22, 0.50, 0.85)])
        case "koth":     return ("flag.fill",                [c(0.25, 0.78, 0.70), c(0.20, 0.55, 0.60)])
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

    static func c(_ r: Double, _ g: Double, _ b: Double) -> Color {
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

// ===========================================================================
// ChallengePackShowcase — a looping "video" for the Challenge Packs section:
// it revolves through each pack's reward collection, cross-fading a live
// LoadoutDiorama from one collection to the next every few seconds, with the
// pack's name + glyph in the corner.  One shared clock drives the rotation.
// ===========================================================================
/// The lettering every Game Modes card uses (Roll Along, Challenge Packs,
/// Minigames): a small spaced label, a large title, and an optional short line.
private struct GameModeCardTitle: View {
    let label: String
    let title: String
    var line: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.85))
            Text(title)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let line {
                Text(line)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

private struct ChallengePackShowcase: View {
    struct Entry: Identifiable {
        let id:      String
        let name:    String
        let icon:    String
        let accent:  Color
        let loadout: Loadout
    }

    let entries: [Entry]
    /// Seconds each collection is shown before cross-fading to the next.
    var slot: Double = 3.8

    var body: some View {
        if entries.isEmpty {
            Color(white: 0.10)
        } else {
            TimelineView(.animation) { tl in
                let count = entries.count
                let pos   = tl.date.timeIntervalSinceReferenceDate / slot
                let base  = pos.rounded(.down)
                let i     = ((Int(base) % count) + count) % count
                let frac  = pos - base                        // 0…1 within this slot
                // Cross-fade to the next collection over the slot's final 16%.
                let fadeStart = 0.84
                let x = frac <= fadeStart ? 0.0
                        : Double((frac - fadeStart) / (1 - fadeStart))
                ZStack {
                    Color.black
                    cell(entries[i]).opacity(1 - x)
                    if x > 0 { cell(entries[(i + 1) % count]).opacity(x) }
                }
            }
        }
    }

    private func cell(_ e: Entry) -> some View {
        ZStack(alignment: .bottomLeading) {
            // The showcase card already clips to radius 18, so let this fill it
            // squarely rather than nesting a second rounded clip + hairline.
            LoadoutDiorama(loadout: e.loadout, cornerRadius: nil)

            // Bottom scrim so the label reads over any floor colour.
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            HStack(spacing: 7) {
                Image(systemName: e.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(e.accent.opacity(0.9)))
                Text(e.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            }
            .padding(12)
        }
    }
}

// ===========================================================================
// ChaseChipStrip — the S2-T7 "what am I chasing?" surface on the game menu.
// A compact, horizontal row of the player's PINNED trophies (up to 3), each a
// chip showing the grade glyph, the trophy name, and LIVE progress read from
// the TrophyEngine's `progressFraction` API.  It renders nothing when nothing
// is pinned (or every pin is already earned), so it never takes space it hasn't
// earned.  Tapping a chip deep-links into the Trophy Room, where pins are
// managed.  Display-only (D1 never-mint): it reads the engine + pin store and
// writes nothing.
//
// Accessible: each chip is one combined a11y element speaking name + grade +
// percent (a scalable Dynamic-Type font, never color-only for the grade — the
// glyph is the second cue).  A masked secret pin (if one is ever pinned) draws
// a generic "Hidden trophy" chip and never leaks its objective or closeness.
// ===========================================================================
private struct ChaseChipStrip: View {

    @ObservedObject var engine: TrophyEngine
    @ObservedObject var pins: TrophyPinStore

    /// Rebuilt each render from the current engine + pin snapshot — cheap: at
    /// most `maxPins` (3) value-type chips.
    private var model: ChaseChipModel {
        ChaseChipModel(engine: engine, pinnedIDs: pins.pinnedIDs, lastLevel: LevelLayout.lastLevel)
    }

    var body: some View {
        let chips = model.chips
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(white: 0.7))
                        .accessibilityHidden(true)
                    Text("CHASING")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(chips) { chip in
                            NavigationLink(value: HomeRoute.trophies) {
                                chipCard(chip)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// One chase chip: grade glyph, trophy name, a progress bar + percent.
    private func chipCard(_ chip: ChaseChip) -> some View {
        HStack(spacing: 10) {
            Image(systemName: chip.isMasked ? "questionmark.circle" : chip.tileIcon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(chip.gradeAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(chip.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    // Progress bar only when progress is exposed (a masked
                    // secret suppresses it so the bar can't leak closeness).
                    if let progress = chip.progress {
                        ProgressView(value: progress)
                            .tint(chip.gradeAccent)
                            .frame(width: 90)
                            .accessibilityHidden(true)
                    }
                    Text(chip.progressCaption)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(white: 0.75))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(chip.gradeAccent.opacity(0.55), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chip.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the Trophy Room.")
    }
}

// ===========================================================================
// MinigamesGridView — every available minigame as a two-column grid, opened
// from the Minigames button on the game-mode screen.
//
// • The list comes from the mode registry (`GameModeCatalogue.enabled`), so a
//   mode switched off there disappears here too.  `hiddenMinigameIDs` holds
//   back anything not ready for this release even if the registry lists it.
// • Three labeled sections, each with its own order list: `soloOrder`,
//   `competitiveOrder`, `rewardOrder` — edit those to reorder the grid.
// • Tap a tile to choose that game (it is armed and the player returns Home,
//   where Play launches it — the same as the old shelves).
// • Press and hold a tile to play its preview clip (see `MinigameClip` and
//   docs/minigame-clips.md).  A game with no clip shows its icon only.
// ===========================================================================
struct MinigamesGridView: View {
    @EnvironmentObject var nav: Navigator
    @EnvironmentObject var gameState: GameState
    @Environment(\.dismiss) var dismiss

    /// THE ORDER of the minigames grid, by catalogue id, in three sections.
    /// A minigame not listed in any section goes at the end of its own kind
    /// (competitive → Competitive, anything else → Solo, before Zen Garden).
    static let soloOrder: [String] = [
        "rollup",     // Roll Up            — first
        "disco",      // Disco Ball
        "zen",        // Zen Garden         — last
    ]
    static let competitiveOrder: [String] = [
        "snake",      // Snacky
        "sumo",       // Sumo Survival
        "paintball",  // Paint Ball
        "goldrush",   // Smash and Grab
        "marblecup",  // Marble Cup
        "koth",       // King of the Hill
    ]
    static let rewardOrder: [String] = [
        "coinpit",    // Gold Rush          — costs 5 tickets won in the games above
    ]
    /// Every listed id, in display order (Solo, Competitive, Reward).
    static var minigameOrder: [String] { soloOrder + competitiveOrder + rewardOrder }

    /// The three sections of the grid.
    enum GridSection: CaseIterable {
        case solo, competitive, reward
    }

    /// Not in this release, even if the registry still lists them.
    /// Roll Out's mazes are being rebuilt.
    static let hiddenMinigameIDs: Set<String> = ["rollout"]

    /// The tile DISPLAYED as "Gold Rush" is catalogue id "coinpit" — the names
    /// were swapped with the competitive mode (id "goldrush", now displayed
    /// "Smash and Grab") on 2026-06-11; ids stayed put through that swap and
    /// the later rename.  Gold Rush costs `CoinPayouts.goldRushTicketCost`
    /// tickets a round, won in competitive games.
    static let goldRushID = "coinpit"

    /// The minigames of one section, in order.
    static func games(in section: GridSection) -> [GameMode] {
        let all = available
        func pick(_ ids: [String]) -> [GameMode] { ids.compactMap { id in all.first { $0.id == id } } }
        let listed = Set(minigameOrder)
        let extras = all.filter { !listed.contains($0.id) }
        switch section {
        case .solo:
            var solo = pick(soloOrder)
            let extraSolo = extras.filter { $0.section != .competitive }
            if let zen = solo.firstIndex(where: { $0.id == "zen" }) {
                solo.insert(contentsOf: extraSolo, at: zen)
            } else {
                solo.append(contentsOf: extraSolo)
            }
            return solo
        case .competitive:
            return pick(competitiveOrder) + extras.filter { $0.section == .competitive }
        case .reward:
            return pick(rewardOrder)
        }
    }

    /// Every minigame the player can see, in grid order.
    static var available: [GameMode] {
        let games = GameModeCatalogue.enabled.filter { mode in
            (mode.section == .competitive || mode.section == .solo)
                && !(mode is ChallengeTrackMode)
                && !hiddenMinigameIDs.contains(mode.id)
        }
        var ordered: [GameMode] = minigameOrder.compactMap { id in games.first { $0.id == id } }
        let extras = games.filter { !minigameOrder.contains($0.id) }
        if let zenIndex = ordered.firstIndex(where: { $0.id == "zen" }) {
            ordered.insert(contentsOf: extras, at: zenIndex)
        } else {
            ordered.append(contentsOf: extras)
        }
        return ordered
    }

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    /// Arm a mode and return Home — the home Play button then launches it.
    private func select(_ modeID: String) {
        gameState.currentModeID = modeID
        nav.goHome()
    }

    var body: some View {
        let games = Self.available
        let anyClip = games.contains { MinigameClip.url(for: $0.id) != nil }
        return ZStack {
            LinearGradient(colors: [Color(white: 0.05), Color(white: 0.12)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(anyClip
                         ? "Tap a game to choose it, then press Play. Press and hold a game to watch a preview."
                         : "Tap a game to choose it, then press Play.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.55))
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(GridSection.allCases, id: \.self) { section in
                        let sectionGames = Self.games(in: section)
                        if !sectionGames.isEmpty {
                            MinigameSectionHeader(section: section, tickets: gameState.tickets)
                                .padding(.top, section == .solo ? 4 : 14)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(sectionGames, id: \.id) { mode in
                                    MinigameTile(mode: mode,
                                                 tickets: gameState.tickets,
                                                 onSelect: { select(mode.id) })
                                }
                            }
                            // The link between the two: wins above pay for Gold Rush below.
                            if section == .competitive && !Self.games(in: .reward).isEmpty {
                                TicketFlowNote()
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Minigames")
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
}

/// A section title in the Minigames grid: an icon in the section's color, the
/// title, and one plain line saying what the section is for.  The Reward
/// section also shows the player's ticket count.
private struct MinigameSectionHeader: View {
    let section: MinigamesGridView.GridSection
    let tickets: Int

    private static let ticketGold = Color(red: 1.00, green: 0.78, blue: 0.20)

    private var icon: String {
        switch section {
        case .solo:        return "person.fill"
        case .competitive: return "flag.checkered"
        case .reward:      return "ticket.fill"
        }
    }
    private var tint: Color {
        switch section {
        case .solo:        return Color(red: 0.45, green: 0.78, blue: 1.00)
        case .competitive: return Color(red: 0.98, green: 0.45, blue: 0.40)
        case .reward:      return Self.ticketGold
        }
    }
    private var title: String {
        switch section {
        case .solo:        return "Solo"
        case .competitive: return "Competitive · win tickets"
        case .reward:      return "Reward · spend tickets"
        }
    }
    private var subtitle: String {
        switch section {
        case .solo:        return "Play at your own pace."
        case .competitive: return "Beat the computer players. Every win earns 1 ticket."
        case .reward:      return "Gold Rush costs \(CoinPayouts.goldRushTicketCost) tickets a round."
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(tint)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if section == .reward {
                HStack(spacing: 4) {
                    Image(systemName: "ticket.fill").font(.system(size: 12, weight: .bold))
                    Text("\(tickets)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.black.opacity(0.8))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Self.ticketGold))
                .accessibilityLabel("\(tickets) ticket\(tickets == 1 ? "" : "s")")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Between the Competitive and Reward sections: a small arrow line that says
/// the tickets won above are what Gold Rush spends below.
private struct TicketFlowNote: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .bold))
            Image(systemName: "ticket.fill")
                .font(.system(size: 11, weight: .bold))
            Text("\(CoinPayouts.goldRushTicketCost) tickets you win here buy a Gold Rush round")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Color(red: 1.00, green: 0.78, blue: 0.20).opacity(0.85))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Where minigame preview clips live and how big a tile is.
/// Spec for recording them: docs/minigame-clips.md.
enum MinigameClip {
    /// Folder (an Xcode folder reference) the clips are copied from.
    static let folder = "MinigameClips"
    /// Tiles are 4:5 portrait (width : height); clips fill them, cropped to fit.
    static let tileAspect: CGFloat = 4.0 / 5.0
    /// Accepted file types, in the order they are looked for.
    static let extensions = ["mp4", "mov", "m4v"]

    /// `clip_<mode id>` in the clips folder (or loose in the app bundle), or
    /// nil when there is no clip for this game yet.
    static func url(for modeID: String) -> URL? {
        let name = "clip_\(modeID)"
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: folder) {
                return url
            }
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}

/// One minigame tile: the game's gradient, icon and name.  Tap chooses the
/// game.  Press and hold plays its preview clip (muted, looping) until the
/// finger lifts; with no clip, holding does nothing.
private struct MinigameTile: View {
    let mode: GameMode
    let tickets: Int
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressing = false
    @State private var previewing = false
    /// Set when a hold started a preview, so the release that ends it is not
    /// also taken as a tap that opens the game.
    @State private var didPreview = false
    @State private var holdTask: Task<Void, Never>?

    /// Seconds a finger must stay down before the preview starts.
    private static let holdSeconds: Double = 0.35

    private var isGoldRush: Bool { mode.id == MinigamesGridView.goldRushID }
    /// Gold Rush cannot be played: fewer tickets than one round costs.
    private var noTickets: Bool { isGoldRush && tickets < CoinPayouts.goldRushTicketCost }

    var body: some View {
        let style = GameMenuView.style(for: mode.id)
        let clip = MinigameClip.url(for: mode.id)
        return ZStack {
            LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            // Watermark of the game's glyph, as on the old shelf tiles.
            Image(systemName: style.icon)
                .font(.system(size: 104, weight: .bold))
                .foregroundStyle(.white.opacity(0.14))
                .rotationEffect(.degrees(-15))
                .offset(x: 46, y: 52)

            if previewing, let clip {
                LoopingClipView(url: clip)
                    .transition(.opacity)
            } else {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.20))
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                            .frame(width: 58, height: 58)
                        Image(systemName: style.icon)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    }
                    Text(mode.displayName)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
                    if noTickets {
                        Text("\(tickets) of \(CoinPayouts.goldRushTicketCost) tickets — win competitive rounds to earn them")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .aspectRatio(MinigameClip.tileAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        // While the clip plays, keep the name readable along the bottom.
        .overlay(alignment: .bottom) {
            if previewing {
                Text(mode.displayName)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.45))
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20))
            }
        }
        // Gold Rush: ticket balance, top right.
        .overlay(alignment: .topTrailing) {
            if isGoldRush {
                HStack(spacing: 2) {
                    Image(systemName: "ticket.fill").font(.system(size: 10, weight: .bold))
                    Text("\(tickets)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.30)))
                .padding(10)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.18), lineWidth: 1))
        .grayscale(noTickets ? 0.9 : 0)
        .opacity(noTickets ? 0.6 : 1)
        .scaleEffect(pressing && !reduceMotion ? 0.97 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: pressing)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        // A quick tap chooses the game.  (The tap gesture also has to come
        // BEFORE the long press so the grid still scrolls.)
        .onTapGesture {
            if didPreview { didPreview = false; return }
            onSelect()
        }
        // Press and hold: the very long minimum duration means the long press
        // never completes while held, so `pressing` stays true until the finger
        // lifts (or moves away to scroll) — that is what stops the clip.
        .onLongPressGesture(minimumDuration: 600, maximumDistance: 12,
                            perform: {},
                            onPressingChanged: { isPressing in
            pressing = isPressing
            holdTask?.cancel()
            if isPressing {
                didPreview = false
                guard clip != nil else { return }
                holdTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(Self.holdSeconds * 1_000_000_000))
                    guard !Task.isCancelled, pressing else { return }
                    didPreview = true
                    withAnimation(.easeOut(duration: 0.2)) { previewing = true }
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { previewing = false }
            }
        })
        .onDisappear {
            holdTask?.cancel()
            previewing = false
            pressing = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect() }
        .accessibilityIdentifier(mode.id)
    }

    private var accessibilityText: String {
        guard isGoldRush else { return mode.displayName }
        return noTickets
            ? "\(mode.displayName). \(tickets) of \(CoinPayouts.goldRushTicketCost) tickets. A round costs \(CoinPayouts.goldRushTicketCost). Win competitive games to earn them."
            : "\(mode.displayName). \(tickets) ticket\(tickets == 1 ? "" : "s")."
    }
}

/// A muted clip that loops for as long as it is on screen.  No controls.
private struct LoopingClipView: UIViewRepresentable {
    let url: URL

    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .clear
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        context.coordinator.looper = AVPlayerLooper(player: player,
                                                    templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
        uiView.playerLayer.player = nil
        coordinator.looper?.disableLooping()
        coordinator.looper = nil
    }
}
