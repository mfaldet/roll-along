import SwiftUI

@main
struct RollAlongApp: App {
    @StateObject private var gameState = GameState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameState)
                .onAppear {
                    // Cold-start analytics ping.  AnalyticsClient.shared
                    // initialises the persistent user_id + session_id on
                    // first access.
                    AnalyticsClient.shared.track(
                        "app_launch",
                        properties: [
                            "level":           .int(gameState.currentLevel),
                            "lives":           .int(gameState.displayedLives),
                            "coin_balance":    .int(gameState.coinBalance),
                            "total_stars":     .int(gameState.totalStars),
                            "highest_unlocked": .int(gameState.highestUnlocked),
                        ]
                    )
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                // Best-effort flush so events don't get lost when the user
                // backgrounds the app.
                AnalyticsClient.shared.flush()
            case .active:
                // Mint a new session if we've been idle long enough that
                // the previous one shouldn't count as "the same session".
                // Threshold: 5 minutes.  Implemented inside startNewSession
                // via tracking the last-active timestamp.
                AnalyticsClient.shared.track("app_resume")
            @unknown default:
                break
            }
        }
    }
}
