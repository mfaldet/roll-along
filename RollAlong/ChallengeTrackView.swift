import SwiftUI

// ---------------------------------------------------------------------------
// ChallengeTrackView — detail view for a single Challenge Track.
//
// Layout (top → bottom):
//   1. Hero: animated ball skin + track name + tagline
//   2. Progress bar: N / 100 levels with phase labels
//   3. Reward bundle card: bundle name + 6 cosmetic items
//   4. Level grid: 10 × 10 tappable cells (cleared / current / locked)
//   5. Sticky Play button at the bottom
// ---------------------------------------------------------------------------

struct ChallengeTrackView: View {
    let track: ChallengeTrackMode

    @EnvironmentObject var gameState: GameState
    @Environment(\.dismiss) private var dismiss

    private var progress:   Int  { gameState.trackProgress[track.trackID] ?? 0 }
    private var nextLevel:  Int  { min(100, max(1, progress + 1)) }
    private var completed:  Bool { gameState.completedTracks.contains(track.trackID) }

    private var rewardBundle: CosmeticBundle? {
        guard let id = ChallengeTrackMode.rewardBundleID(for: track.trackID) else { return nil }
        return CosmeticBundle.catalogue.first { $0.id == id }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(white: 0.07).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    heroSection
                    progressSection
                    if let bundle = rewardBundle { rewardCard(bundle) }
                    levelGrid
                    Spacer().frame(height: 96)   // room for sticky Play button
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            // Sticky Play / Replay button
            playButton
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .background(
                    LinearGradient(
                        colors: [Color(white: 0.07).opacity(0), Color(white: 0.07)],
                        startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)
                    )
                    .ignoresSafeArea()
                )
        }
        .navigationTitle(track.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(white: 0.07), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 10) {
            // Ball skin preview
            BallSkinView(skin: heroSkin, diameter: 80)
                .shadow(color: heroGlowColor.opacity(0.40), radius: 20, x: 0, y: 6)

            Text(track.tagline)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color(white: 0.48))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 8)
    }

    /// Show the reward bundle's ball skin in the hero; fall back to active skin.
    private var heroSkin: BallSkin {
        rewardBundle?.balls.first ?? gameState.activeSkin
    }

    private var heroGlowColor: Color {
        heroSkin.highlightColor
    }

    // MARK: - Progress bar

    private var progressSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text(completed ? "Completed!" : "\(progress) / 100 levels")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(completed ? Color(red: 1.0, green: 0.78, blue: 0.20) : Color(white: 0.65))
                Spacer()
                if !completed {
                    phaseLabel
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.14)).frame(height: 8)
                    Capsule()
                        .fill(
                            completed
                                ? LinearGradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.20),
                                                           Color(red: 0.90, green: 0.60, blue: 0.10)],
                                                  startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color(red: 0.25, green: 0.72, blue: 0.50),
                                                           Color(red: 0.40, green: 0.88, blue: 0.65)],
                                                  startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * CGFloat(progress) / 100.0, height: 8)
                        .animation(.easeOut(duration: 0.4), value: progress)

                    // Phase tick marks (15, 35, 60, 80, 95)
                    ForEach([15, 35, 60, 80, 95], id: \.self) { tick in
                        Rectangle()
                            .fill(Color(white: 0.25))
                            .frame(width: 1, height: 12)
                            .offset(x: geo.size.width * CGFloat(tick) / 100.0 - 0.5,
                                    y: -2)
                    }
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.10))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 0.16), lineWidth: 0.8))
        )
    }

    private var phaseLabel: some View {
        let (name, color): (String, Color) = {
            switch nextLevel {
            case  1...15: return ("Tutorial",    Color(red: 0.35, green: 0.78, blue: 0.55))
            case 16...35: return ("Apprentice",  Color(red: 0.55, green: 0.78, blue: 0.35))
            case 36...60: return ("Journeyman",  Color(red: 0.90, green: 0.70, blue: 0.25))
            case 61...80: return ("Expert",      Color(red: 0.90, green: 0.45, blue: 0.20))
            case 81...95: return ("Master",      Color(red: 0.85, green: 0.25, blue: 0.25))
            default:      return ("Pinnacle",    Color(red: 0.95, green: 0.20, blue: 0.55))
            }
        }()
        return Text(name)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: - Reward card

    private func rewardCard(_ bundle: CosmeticBundle) -> some View {
        let alreadyOwned = gameState.ownedBundles.contains(bundle.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: alreadyOwned ? "checkmark.seal.fill" : "gift.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(alreadyOwned
                        ? Color(red: 1.0, green: 0.78, blue: 0.20)
                        : Color(red: 0.35, green: 0.72, blue: 0.55))
                Text(alreadyOwned ? "Reward Earned" : "Complete to Earn")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.50))
                Spacer()
                Text(bundle.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(bundle.contentSummary)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color(white: 0.38))
                .lineLimit(2)

            // Ball skin preview row
            if !bundle.balls.isEmpty {
                HStack(spacing: 8) {
                    ForEach(bundle.balls, id: \.rawValue) { skin in
                        BallSkinView(skin: skin, diameter: 32)
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            alreadyOwned
                                ? Color(red: 1.0, green: 0.78, blue: 0.20).opacity(0.35)
                                : Color(white: 0.18),
                            lineWidth: 0.8
                        )
                )
        )
    }

    // MARK: - Level grid (10 × 10)

    private var levelGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Levels")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.40))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 10),
                spacing: 5
            ) {
                ForEach(1...100, id: \.self) { level in
                    levelCell(level)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.10))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.16), lineWidth: 0.8))
        )
    }

    @ViewBuilder
    private func levelCell(_ level: Int) -> some View {
        let cleared = level <= progress
        let isCurrent = level == nextLevel && !completed
        let locked = level > nextLevel

        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(cellBackground(cleared: cleared, isCurrent: isCurrent, locked: locked))

            if cleared {
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Color(white: 0.55))
            } else if isCurrent {
                Circle()
                    .fill(Color(red: 0.35, green: 0.82, blue: 0.58))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(height: 22)
        .onTapGesture {
            guard !locked else { return }
            gameState.startTrack(track.trackID, atLevel: level)
        }
    }

    private func cellBackground(cleared: Bool, isCurrent: Bool, locked: Bool) -> Color {
        if cleared   { return Color(white: 0.20) }
        if isCurrent { return Color(red: 0.18, green: 0.40, blue: 0.30) }
        return Color(white: 0.13)
    }

    // MARK: - Play button

    @ViewBuilder
    private var playButton: some View {
        if completed {
            NavigationLink(destination: BallGameView(activeMode: track)
                .onAppear { gameState.startTrack(track.trackID, atLevel: 1) })
            {
                replayLabel
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: BallGameView(activeMode: track)
                .onAppear { gameState.startTrack(track.trackID) })
            {
                playLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var playLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .bold))
            Text(progress == 0 ? "Start Track" : "Continue — Level \(nextLevel)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.35, green: 0.88, blue: 0.60))
        )
    }

    private var replayLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .bold))
            Text("Replay from Level 1")
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.20))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 1.0, green: 0.78, blue: 0.20).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(red: 1.0, green: 0.78, blue: 0.20).opacity(0.35), lineWidth: 1)
                )
        )
    }
}

#Preview {
    NavigationStack {
        ChallengeTrackView(track: GameModeCatalogue.frozenPeaks)
            .environmentObject(GameState())
    }
}
