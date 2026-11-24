import SwiftUI

#if DEBUG
// ===========================================================================
// The Debug page (debug builds only — never compiled into a release build).
// Opened from the one "Debug" row at the bottom of Settings.  Every Debug
// button and card, grouped: Levels, Rewards, End room, Ads, Analytics.
// ===========================================================================
struct DebugView: View {
    @EnvironmentObject var gameState: GameState
    /// Lets "Show Out of Lives screen" open the game.
    @EnvironmentObject private var nav: Navigator

    /// The "All Collections" review gallery.
    @State private var showCollectionGallery = false
    /// Whether a level shows the purple test buttons.
    @AppStorage(DebugSwitches.showLevelTestButtonsKey) private var debugShowLevelTestButtons = false
    /// The end room preview open, if any.
    @State private var debugEndRoom: EndRoomVisit? = nil
    @State private var showWaitingRoomArt = false
    /// The result of the last level pack check.
    @State private var debugPackCheck = LevelPackStore.lastCheck

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    levelsGroup
                    rewardsGroup
                    endRoomGroup
                    adsGroup
                    analyticsGroup
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(item: $debugEndRoom) { visit in
            EndRoomFlowView(visit: visit, preview: true, onDone: { debugEndRoom = nil })
                .environmentObject(gameState)
        }
        .sheet(isPresented: $showWaitingRoomArt) {
            WaitingRoomArtPreview()
        }
        .fullScreenCover(isPresented: $showCollectionGallery) {
            CollectionReviewGallery()
                .environmentObject(gameState)
        }
    }

    // MARK: - Groups

    private var levelsGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Levels")
            Toggle(isOn: $debugShowLevelTestButtons) {
                Text("Show level test buttons")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
            }
            .tint(.purple)
            .padding(14)
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
            Text("While on, a level shows three purple buttons: Debug: fall, Debug: coins (picks up every coin) and Debug: finish. Off by default; the choice is remembered.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
            VStack(spacing: 8) {
                debugProgressButton("Old save: on level 250, then fit to the pack", .oldSavePastThePack)
                debugProgressButton("Pass every level with one star", .everyLevelPassed)
                debugProgressButton("Fully clear every level", .everyLevelFullyCleared)
            }
            Text("Adventure progress (replaces the saved progress on this device). Now: on level \(gameState.currentLevel), highest unlocked \(gameState.highestUnlocked), \(gameState.totalStars) stars, pack ends at level \(LevelLayout.lastLevel). Play would open: \(debugPlayTargetText).")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
            VStack(spacing: 8) {
                Button {
                    debugPackCheck = "checking…"
                    Task { debugPackCheck = await LevelPackStore.refresh() }
                } label: { debugButtonLabel("Check for a published level pack now") }
                .buttonStyle(.plain)
                Button {
                    LevelPackStore.debugForgetDownloadedPack()
                    debugPackCheck = LevelPackStore.lastCheck
                } label: { debugButtonLabel("Forget the downloaded level pack") }
                .buttonStyle(.plain)
            }
            Text("Level pack in use: version \(LevelLayout.packVersion), \(LevelLayout.lastLevel) levels, \(LevelLayout.packSource == .downloaded ? "downloaded" : "from the app"). Last check: \(debugPackCheck). A pack accepted now is used from the next launch. Published at \(LevelPackStore.remoteURL.absoluteString)")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
                .textSelection(.enabled)
        }
    }

    private var rewardsGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Rewards")
            VStack(spacing: 8) {
                Button { gameState.debugStandOn(level: 1) } label: { debugButtonLabel("Rewards check: start again on level 1") }
                    .buttonStyle(.plain)
                Button { gameState.debugStandOn(level: 50) } label: { debugButtonLabel("Rewards check: stand on level 50") }
                    .buttonStyle(.plain)
                Button { gameState.debugStandOn(level: 100) } label: { debugButtonLabel("Rewards check: stand on level 100") }
                    .buttonStyle(.plain)
                Button { gameState.debugMakeSaveFromBefore11() } label: {
                    debugButtonLabel("Set up a save from before 1.1 (then close and reopen the app)")
                }
                .buttonStyle(.plain)
            }
            Text("The save from before 1.1 has every level passed, levels 1 to 30 fully cleared, and no 1.1 reward record. Close the app and open it again: Home shows the bonus message (+420 coins), then the level 50 pick, then the level 100 pick, then the end room. The stand-on buttons replace the saved Adventure progress and forget every 1.1 reward record. \(gameState.debugRewardsSummary)")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
            Button { showCollectionGallery = true } label: {
                aboutRow(icon: "square.grid.3x3.fill", title: "All Collections", trailing: "chevron.right")
            }
            .buttonStyle(.plain)
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
            Text("Review gallery: every collection with its real art. Nothing here buys, grants or equips anything.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
    }

    private var endRoomGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("End room")
            VStack(spacing: 8) {
                Button { debugEndRoom = .first } label: { debugButtonLabel("Open the end room (first visit)") }
                    .buttonStyle(.plain)
                Button { debugEndRoom = .second } label: { debugButtonLabel("Open the end room (second visit)") }
                    .buttonStyle(.plain)
                Button { showWaitingRoomArt = true } label: { debugButtonLabel("Waiting Room art (for review)") }
                    .buttonStyle(.plain)
                Button { gameState.endRoomSeenAtLastLevel = 0 } label: { debugButtonLabel("Forget that the end room was seen") }
                    .buttonStyle(.plain)
            }
            Text("The two end room buttons show the room only: they record nothing and give nothing, and the swirl returns here. To see the real thing, set up a save from before 1.1 (under Rewards) or forget that the room was seen, then go Home.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
    }

    private var adsGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Ads")
            Button { debugShowOutOfLives() } label: {
                aboutRow(icon: "heart.slash.fill", title: "Show Out of Lives screen", trailing: "chevron.right")
            }
            .buttonStyle(.plain)
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
            Text("For testing the rewarded ad where the phone cannot be tilted. Sets lives to zero, moves past the tutorial levels if needed, and opens Adventure on the real Out of Lives screen. This changes the saved game on this device.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
            VStack(alignment: .leading, spacing: 6) {
                Text("Ad settings in effect")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Text(AdManager.shared.debugAudienceSummary)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(white: 0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
        }
    }

    private var analyticsGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Analytics")
            VStack(alignment: .leading, spacing: 6) {
                Text("Last level event sent")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                Text(AnalyticsClient.debugLastLevelEvent)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(white: 0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
            HStack(spacing: 8) {
                ForEach(RatingMilestones.levels, id: \.self) { milestone in
                    Button { gameState.debugRequestReview(atMilestone: milestone) } label: {
                        Text("Level \(milestone)")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Rating request: acts as if you had just reached that level for the first time. Milestones already asked: \(gameState.reviewMilestonesAsked.sorted().map(String.init).joined(separator: ", ").isEmpty ? "none" : gameState.reviewMilestonesAsked.sorted().map(String.init).joined(separator: ", ")).")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
    }

    // MARK: - Helpers

    /// Debug builds only: one row that rewrites Adventure progress.
    private func debugProgressButton(_ title: String, _ kind: GameState.DebugProgress) -> some View {
        Button { gameState.debugSetProgress(kind) } label: { debugButtonLabel(title) }
            .buttonStyle(.plain)
    }

    private func debugButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
    }

    /// Debug builds only: what the Play button would open, in words.
    private var debugPlayTargetText: String {
        switch gameState.adventurePlayTarget {
        case .level(let level): return "level \(level)"
        case .levelSelect:      return "the level selector"
        }
    }

    /// Debug builds only.  Puts the game where a player is after losing
    /// their last life, then opens Adventure.  The game checks lives as it
    /// appears (`BallGameView.spawnBall`), finds none and shows the real
    /// Out of Lives screen, with the real "Watch ad" button.
    ///
    /// That check only shows the screen when all of these hold, so each is
    /// set here:
    ///   • the mode spends lives — Adventure does;
    ///   • the level is past the tutorial levels, which never spend a life;
    ///   • unlimited lives is off;
    ///   • no lives are left, in the refilling bar or in the reserve.
    private func debugShowOutOfLives() {
        gameState.unlimitedLives = false
        let firstRealLevel = GameState.tutorialLevelCount + 1
        if gameState.isTutorialLevel(gameState.currentLevel) {
            gameState.currentLevel = firstRealLevel
        }
        gameState.highestUnlocked = max(gameState.highestUnlocked, gameState.currentLevel)
        gameState.lives = 0
        gameState.purchasedLives = 0
        // As after a real last fall: the 6-minute refill starts now.
        gameState.lastLifeLostAt = .now
        gameState.currentModeID = "climb"
        // Leave Settings and open the game in its place.
        nav.path = [.game]
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .kerning(1.5)
            .foregroundStyle(Color(white: 0.45))
    }

    private func aboutRow(icon: String, title: String,
                          trailing: String = "arrow.up.right") -> some View {
        HStack {
            Label {
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color(white: 0.75))
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(Color(white: 0.55))
            }
            Spacer()
            Image(systemName: trailing)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(white: 0.4))
        }
        .padding()
        .contentShape(Rectangle())
    }
}
#endif
