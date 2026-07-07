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
                    // Bootstrap Google Mobile Ads — initialises the SDK and
                    // pre-loads the first rewarded ad so the "Watch ad" tap is
                    // instant.  No ATT prompt — ads are always non-personalised.
                    await ads.bootstrap(with: gameState)
                }
                .task {
                    // Restore a persisted Sign in with Apple session (refresh
                    // token in the Keychain) so the player stays signed in
                    // across launches without re-authenticating.
                    await AppleAuthManager.shared.restoreSession()
                }
                .task {
                    // Trophy bootstrap, in order, every launch:
                    // 1. First-launch-with-trophies backfill (S0-T4, wired at
                    //    S1-T1): grandfather every trophy the save's existing
                    //    stats already earn, once, BEFORE live play.  Idempotent
                    //    across relaunches (the engine short-circuits after the
                    //    first run).
                    gameState.activateTrophies()
                    // 2. Reconcile the iCloud key-value ratchet mirror (S3-T8):
                    //    union-restores unlocks after a delete+reinstall and
                    //    converges multiple devices.  A local-only no-op until
                    //    the iCloud KV entitlement is added (graceful degrade).
                    _ = TrophyCloudMirror.shared.reconcile(engine: gameState.trophyEngine)
                    // 3. Push the unioned unlock set to the backend (S3-T3):
                    //    the anonymous rarity rail (trophy_unlocks) for EVERY
                    //    player — signed-in or not — plus player_trophies when
                    //    signed in.  Anonymous sync is how rarity counts the
                    //    ~100% of players who never sign in.  A no-op when the
                    //    sync-dirty flag is clean.
                    await TrophySyncService.shared.sync(engine: gameState.trophyEngine)
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
                .onAppear {
                    // Install the foreground-presentation delegate and bring the
                    // lives-restock notification in line with the current state
                    // (it may have fired / become moot while the app was closed).
                    NotificationManager.shared.start()
                    gameState.reconcileLivesNotification()
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
                // Re-affirm the lives-restock alert against time elapsed while
                // backgrounded (regen kept accruing; the alert may need to be
                // rescheduled or cleared).
                gameState.reconcileLivesNotification()
                // Trophy catch-up on resume: pull any cross-device iCloud
                // updates (S3-T8) and flush unlocks earned offline to the
                // rarity rail (S3-T3).  Both no-op when nothing changed.
                Task {
                    _ = TrophyCloudMirror.shared.reconcile(engine: gameState.trophyEngine)
                    await TrophySyncService.shared.sync(engine: gameState.trophyEngine)
                }
            @unknown default:
                break
            }
        }
    }
}
