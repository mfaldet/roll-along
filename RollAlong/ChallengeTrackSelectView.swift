import SwiftUI

// ---------------------------------------------------------------------------
// ChallengeTrackSelectView — scrollable catalogue of all 8 Challenge Tracks.
//
// Layout:
//   • Header — title + subtitle
//   • One card per track in GameModeCatalogue.challengeTracks (all 8)
//   • Each card: track name, tagline, progress ring, reward bundle name,
//     lock icon for golden-gauntlet (requires 3 other completions).
//   • Tapping a card navigates to ChallengeTrackView (NavigationLink).
// ---------------------------------------------------------------------------

struct ChallengeTrackSelectView: View {
    @EnvironmentObject var gameState: GameState

    private var completedCount: Int { gameState.completedTracks.count }

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ── Header ──────────────────────────────────────────────
                    VStack(spacing: 6) {
                        Text("Challenge Tracks")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("100 levels · one theme · one reward")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(white: 0.45))
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 24)

                    // ── Track cards ─────────────────────────────────────────
                    LazyVStack(spacing: 14) {
                        ForEach(GameModeCatalogue.challengeTracks, id: \.id) { track in
                            TrackCard(track: track,
                                      progress: gameState.trackProgress[track.trackID] ?? 0,
                                      completed: gameState.completedTracks.contains(track.trackID),
                                      isLocked: isLocked(track),
                                      rewardBundleName: rewardName(for: track.trackID))
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer().frame(height: 40)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(white: 0.07), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func isLocked(_ track: ChallengeTrackMode) -> Bool {
        track.trackID == "golden-gauntlet" && completedCount < 3
    }

    private func rewardName(for trackID: String) -> String {
        guard let bundleID = ChallengeTrackMode.rewardBundleID(for: trackID),
              let bundle   = CosmeticBundle.catalogue.first(where: { $0.id == bundleID })
        else { return "Bundle reward" }
        return bundle.displayName
    }
}

// MARK: - TrackCard

private struct TrackCard: View {
    let track:           ChallengeTrackMode
    let progress:        Int          // highest level cleared (0 = not started)
    let completed:       Bool
    let isLocked:        Bool
    let rewardBundleName: String

    private var progressFraction: Double { Double(progress) / 100.0 }
    private var nextLevel: Int { min(100, max(1, progress + 1)) }

    var body: some View {
        NavigationLink(destination: ChallengeTrackView(track: track)) {
            cardContent
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    @ViewBuilder
    private var cardContent: some View {
        HStack(spacing: 14) {
            // Progress ring
            progressRing

            // Text block
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(track.displayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(isLocked ? Color(white: 0.35) : .white)
                    if completed {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.20))
                    }
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(white: 0.35))
                    }
                }
                Text(track.tagline)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color(white: isLocked ? 0.28 : 0.48))
                    .lineLimit(2)
                Spacer().frame(height: 2)
                HStack(spacing: 4) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: isLocked ? 0.22 : 0.38))
                    Text(rewardBundleName)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: isLocked ? 0.22 : 0.38))
                }
            }

            Spacer()

            // Right side: level count or chevron
            VStack(alignment: .trailing, spacing: 2) {
                if isLocked {
                    Text("Complete 3 tracks")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color(white: 0.28))
                        .multilineTextAlignment(.trailing)
                } else if completed {
                    Text("DONE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.20))
                } else {
                    Text(progress == 0 ? "New" : "Lvl \(nextLevel)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.55))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(white: 0.30))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: isLocked ? 0.09 : 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            completed
                                ? Color(red: 1.0, green: 0.78, blue: 0.20).opacity(0.40)
                                : Color(white: isLocked ? 0.14 : 0.20),
                            lineWidth: 0.8
                        )
                )
        )
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color(white: 0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(progressFraction))
                .stroke(
                    completed
                        ? Color(red: 1.0, green: 0.78, blue: 0.20)
                        : Color(red: 0.35, green: 0.78, blue: 0.55),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(completed ? "✓" : "\(progress)")
                .font(.system(size: progress >= 100 ? 11 : 12, weight: .bold, design: .rounded))
                .foregroundStyle(isLocked ? Color(white: 0.30) : .white)
        }
        .frame(width: 44, height: 44)
    }
}

#Preview {
    NavigationStack {
        ChallengeTrackSelectView()
            .environmentObject(GameState())
    }
}
