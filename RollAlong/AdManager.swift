import Foundation
import UIKit
import AppTrackingTransparency
import GoogleMobileAds

// ---------------------------------------------------------------------------
// AdManager — Google Mobile Ads SDK wrapper for rewarded video.
//
// One ad unit (rewarded video) → 1 life on completion.  No cap (lives
// stockpile unbounded after PR #19).
//
// The SDK is initialised once at app launch.  An ad is pre-loaded so the
// out-of-lives overlay's "Watch ad" button is instant when tapped, then
// the next ad is pre-loaded immediately after the current one dismisses
// to keep the cycle going.
//
// ATT (App Tracking Transparency, iOS 14.5+) — required for personalised
// ads.  We request it once on first cold-start AFTER the user has been
// shown onboarding, so they understand the app before deciding.  Denying
// ATT doesn't block ads — Google just serves non-personalised ones (lower
// eCPM but functional).
//
// DEBUG vs RELEASE — in DEBUG builds we use Google's documented test ad
// unit ID so dev runs don't generate fraud impressions against the real
// account.  Release builds use the real Roll Along ad unit.
// ---------------------------------------------------------------------------

@MainActor
final class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()

    // MARK: - Configuration

    /// Test ad unit in DEBUG, real Roll Along ad unit in RELEASE.
    /// Google's test ID is publicly documented at
    /// https://developers.google.com/admob/ios/test-ads
    private static let rewardedAdUnitID: String = {
        #if DEBUG
        return "ca-app-pub-3940256099942544/1712485313"   // Google rewarded test ID
        #else
        return "ca-app-pub-7121593460502747/2422200111"   // Roll Along Life Reward
        #endif
    }()

    // MARK: - Published state

    /// True once a rewarded ad has been pre-loaded and is ready to present.
    @Published private(set) var isReady: Bool = false

    /// True while an ad is being displayed full-screen.
    @Published private(set) var isShowing: Bool = false

    /// Surfaced for debugging / analytics — last error message from a load
    /// or present call.
    @Published private(set) var lastError: String? = nil

    // MARK: - Internal state

    private var rewardedAd: RewardedAd?
    private var isLoading: Bool = false
    private var pendingRewardHandler: ((Bool) -> Void)?

    weak var gameState: GameState?

    private override init() { super.init() }

    // MARK: - Bootstrap

    /// Initialise the Mobile Ads SDK and pre-load the first ad.  Call once
    /// at app launch.  Safe to call multiple times — subsequent calls are
    /// no-ops apart from ensuring an ad is loaded.
    ///
    /// **ATT timing:** on first launch (`seenOnboarding == false`) the ATT
    /// dialog is NOT shown here — `HomeView` calls `requestTracking()` after
    /// the onboarding overlay is dismissed, so the user understands the app
    /// before deciding.  On subsequent launches (`seenOnboarding == true`)
    /// the ATT status is already determined and `requestTracking()` is called
    /// here directly; the system returns the cached value with no dialog.
    func bootstrap(with gameState: GameState) async {
        self.gameState = gameState
        if gameState.seenOnboarding {
            // Non-first-launch: status is cached — no dialog will appear.
            await requestTracking()
        }
        // Start the Mobile Ads SDK.  Google falls back to non-personalised
        // ads automatically until/unless ATT is authorised.
        _ = await MobileAds.shared.start()
        await loadRewarded()
    }

    /// Request ATT authorisation and fire an `att_response` analytics event.
    ///
    /// - On **first launch** this is called by `HomeView` after the user
    ///   dismisses the onboarding overlay — the system dialog appears here.
    /// - On **subsequent launches** this is called by `bootstrap` when
    ///   `seenOnboarding == true` — `requestTrackingAuthorization()` returns
    ///   the already-determined status immediately with no dialog.
    func requestTracking() async {
        let status = await ATTrackingManager.requestTrackingAuthorization()
        AnalyticsClient.shared.track(
            "att_response",
            properties: [
                "status": .string(Self.attStatusString(status)),
            ]
        )
    }

    private static func attStatusString(_ status: ATTrackingManager.AuthorizationStatus) -> String {
        switch status {
        case .authorized:    return "authorized"
        case .denied:        return "denied"
        case .notDetermined: return "not_determined"
        case .restricted:    return "restricted"
        @unknown default:    return "unknown"
        }
    }

    // MARK: - Pre-load

    /// Load the next rewarded ad in the background.  Idempotent.
    func loadRewarded() async {
        guard !isLoading, rewardedAd == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let ad = try await RewardedAd.load(
                with: Self.rewardedAdUnitID,
                request: Request()
            )
            ad.fullScreenContentDelegate = self
            self.rewardedAd = ad
            self.isReady = true
            self.lastError = nil
            AnalyticsClient.shared.track(
                "ad_loaded",
                properties: ["ad_unit": .string(Self.rewardedAdUnitID)]
            )
        } catch {
            self.rewardedAd = nil
            self.isReady = false
            self.lastError = error.localizedDescription
            AnalyticsClient.shared.track(
                "ad_load_failed",
                properties: [
                    "ad_unit": .string(Self.rewardedAdUnitID),
                    "error":   .string(error.localizedDescription),
                ]
            )
        }
    }

    // MARK: - Show

    /// Present the loaded rewarded ad.  On reward earn, grants 1 life and
    /// fires the completion handler with `true`.  If the user closes the
    /// ad early or it fails, fires with `false`.
    ///
    /// If no ad is loaded, kicks off a load and immediately calls the
    /// handler with `false` so the UI can surface "try again in a moment".
    func showRewarded(onComplete: @escaping (Bool) -> Void) {
        guard let ad = rewardedAd else {
            // Trigger a load for next time and tell the caller we couldn't show.
            Task { await loadRewarded() }
            AnalyticsClient.shared.track("ad_show_attempted_unloaded")
            onComplete(false)
            return
        }
        guard let rootVC = Self.topViewController() else {
            onComplete(false)
            return
        }
        pendingRewardHandler = onComplete
        isShowing = true

        AnalyticsClient.shared.track(
            "ad_started",
            properties: ["ad_unit": .string(Self.rewardedAdUnitID)]
        )

        ad.present(from: rootVC) { [weak self] in
            // userDidEarnRewardHandler — fires once when the reward is
            // earned (typically after the user watches enough of the video).
            guard let self else { return }
            self.gameState?.addLives(1)
            AnalyticsClient.shared.track(
                "ad_reward_earned",
                properties: [
                    "ad_unit": .string(Self.rewardedAdUnitID),
                    "lives_granted": .int(1),
                ]
            )
            // Mark that we earned a reward so the dismiss handler knows.
            self.earnedRewardThisPresentation = true
        }
    }

    /// Per-presentation flag — set in the userDidEarnRewardHandler so the
    /// FullScreenContentDelegate dismiss callback can decide what success
    /// state to fire.
    private var earnedRewardThisPresentation: Bool = false

    // MARK: - View controller hand-off

    /// Find the topmost view controller for ad presentation.  Adapted from
    /// the Google sample boilerplate; works regardless of SwiftUI scene
    /// architecture.
    private static func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
        let root: UIViewController?
        if let base { root = base }
        else {
            root = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.windows.first?.rootViewController }
                .first
        }
        if let nav = root as? UINavigationController { return topViewController(nav.visibleViewController) }
        if let tab = root as? UITabBarController, let sel = tab.selectedViewController {
            return topViewController(sel)
        }
        if let presented = root?.presentedViewController { return topViewController(presented) }
        return root
    }
}

// ---------------------------------------------------------------------------
// FullScreenContentDelegate — handles the ad's lifecycle outside of the
// reward callback.  We use these to:
//   • Reset `isShowing` so SwiftUI overlays don't think an ad is still up.
//   • Fire `ad_dismissed` / `ad_present_failed` analytics events.
//   • Call back to the original showRewarded caller (the out-of-lives
//     overlay) with success/failure.
//   • Pre-load the next ad so the cycle keeps going.
// ---------------------------------------------------------------------------
extension AdManager: FullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        // Already set isShowing in showRewarded — leave it.
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        let success = earnedRewardThisPresentation
        let handler = pendingRewardHandler
        pendingRewardHandler = nil
        earnedRewardThisPresentation = false
        isShowing = false
        rewardedAd = nil
        isReady = false

        AnalyticsClient.shared.track(
            "ad_dismissed",
            properties: [
                "ad_unit": .string(Self.rewardedAdUnitID),
                "completed": .bool(success),
            ]
        )

        handler?(success)
        // Always pre-load the next one so the next "Watch ad" tap is instant.
        Task { await loadRewarded() }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        let handler = pendingRewardHandler
        pendingRewardHandler = nil
        earnedRewardThisPresentation = false
        isShowing = false
        rewardedAd = nil
        isReady = false
        lastError = error.localizedDescription

        AnalyticsClient.shared.track(
            "ad_present_failed",
            properties: [
                "ad_unit": .string(Self.rewardedAdUnitID),
                "error":   .string(error.localizedDescription),
            ]
        )

        handler?(false)
        Task { await loadRewarded() }
    }
}
