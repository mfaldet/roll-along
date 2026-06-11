import SwiftUI

@main
struct RollAlongApp: App {
    @StateObject private var gameState = GameState()
    @StateObject private var store     = StoreKitManager.shared
    @StateObject private var ads       = AdManager.shared
    @Environment(\.scenePhase) private var scenePhase

    /// True when launched by the UI test runner with `--skip-onboarding`.
    /// Setting `seenOnboarding = true` in the GameState before the first
    /// frame prevents the onboarding overlay from blocking UI test navigation.
    private var isUITesting: Bool {
        CommandLine.arguments.contains("--skip-onboarding")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    if isUITesting { gameState.seenOnboarding = true }
                }
                .environmentObject(gameState)
                .environmentObject(store)
                .environmentObject(ads)
                .task {
                    // Bootstrap StoreKit — fetch product catalogue from the
                    // App Store and re-check non-consumable entitlements
                    // (the unlimited unlock).
                    await store.bootstrap(with: gameState)
                }
                .task {
                    // Bootstrap Google Mobile Ads — requests ATT once on
                    // first cold start (after the user has seen the rest of
                    // the app at least briefly), initialises the SDK, and
                    // pre-loads the first rewarded ad so the "Watch ad" tap
                    // is instant.
                    await ads.bootstrap(with: gameState)
                }
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
