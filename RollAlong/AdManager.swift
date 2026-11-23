import Foundation
import UIKit
import GoogleMobileAds

// ---------------------------------------------------------------------------
// AdManager — Google Mobile Ads SDK wrapper for rewarded video.
//
// One ad unit (rewarded video) → 1 life on completion, granted into the
// purchased-lives reserve queue.  No cap (the reserve is unbounded).
//
// The SDK is initialised once at app launch.  An ad is pre-loaded so the
// out-of-lives overlay's "Watch ad" button is instant when tapped, then
// the next ad is pre-loaded immediately after the current one dismisses
// to keep the cycle going.
//
// A load that fails is tried again by itself: after 10 s, 30 s, 60 s, then
// every 2 minutes, until one succeeds (`AdRetrySchedule`).  A load also
// starts when the app returns to the foreground, when the out-of-lives
// screen appears and when "Watch ad" is tapped with no ad ready.  Only one
// load runs at a time, and nothing is retried in the background.
//
// Privacy — Roll Along never tracks users.  We do NOT request App Tracking
// Transparency and never touch the advertising identifier (IDFA); every ad
// request is tagged non-personalised (npa=1), so AdMob serves only generic
// ads.  No ATT prompt is ever shown.
//
// Audience — the game is for players aged 9 and up, so every player is
// treated as a child: every request carries Google's child age treatment,
// ad content is capped at Google's "General audiences" (G) rating, and the
// SDK's coarse-location collection is switched off (see `bootstrap`).
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
    /// One load at a time, and when to try again after a failed one.
    private var retry = AdRetrySchedule()
    /// The wait before the next automatic retry, if one is pending.
    private var retryTask: Task<Void, Never>?
    /// True once `MobileAds.shared.start()` has finished.  Nothing loads before.
    private var sdkStarted: Bool = false
    private var pendingRewardHandler: ((Bool) -> Void)?

    weak var gameState: GameState?

    private override init() { super.init() }

    // MARK: - Bootstrap

    /// Initialise the Mobile Ads SDK and pre-load the first ad.  Call once
    /// at app launch.  Safe to call multiple times — subsequent calls are
    /// no-ops apart from ensuring an ad is loaded.
    ///
    /// No ATT / no tracking: we never call `requestTrackingAuthorization`, so
    /// the system prompt never appears.  Every ad request is non-personalised.
    func bootstrap(with gameState: GameState) async {
        self.gameState = gameState
        // Audience settings — set BEFORE the SDK starts so they apply to every
        // request.  Roll Along is for players aged 9 and up and never learns a
        // player's age, so every request is made as if the player is a child:
        //   • ageRestrictedTreatment = child — Google applies its child
        //     ad-serving protections.  This replaces the deprecated
        //     tagForChildDirectedTreatment (COPPA) and tagForUnderAgeOfConsent
        //     (GDPR) settings, and is the equivalent of setting both to true.
        //   • maxAdContentRating = general — no ad rated above "General
        //     audiences" (G), the lowest of Google's four content ratings
        //     (G, PG, T, MA).
        //   • coarseLocationCollectionEnabled = false — the SDK does not
        //     collect approximate location.  (Property added in Google Mobile
        //     Ads SDK 13.12.0.  The app never asks for location permission.)
        let adConfig = MobileAds.shared.requestConfiguration
        adConfig.ageRestrictedTreatment = .child
        adConfig.maxAdContentRating = .general
        adConfig.coarseLocationCollectionEnabled = false
        // The app owns the audio session (.ambient, set once at launch).  Without
        // this the SDK may switch the session category around ad playback,
        // which can pause or alter other apps' audio.  Under .ambient a
        // rewarded ad's sound mixes with the player's music and is silent
        // when the ring/silent switch is on.
        MobileAds.shared.audioVideoManager.isAudioSessionApplicationManaged = true
        // Start the Mobile Ads SDK.  All ad requests are non-personalised.
        _ = await MobileAds.shared.start()
        sdkStarted = true
        await loadRewarded()
    }

    /// A non-personalised ad request (`npa=1`).  AdMob serves only generic ads
    /// and never uses the advertising identifier — no user tracking.
    private static func nonPersonalizedRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }

    // MARK: - Pre-load

    /// Load the next rewarded ad in the background.  Idempotent: a no-op
    /// while a load is running or an ad is already waiting.  A failed load
    /// schedules its own retry (see `AdRetrySchedule`).
    func loadRewarded() async {
        guard sdkStarted, retry.beginLoad(adReady: rewardedAd != nil) else { return }
        // This load replaces any retry that was still waiting.
        retryTask?.cancel()
        retryTask = nil
        do {
            let ad = try await RewardedAd.load(
                with: Self.rewardedAdUnitID,
                request: Self.nonPersonalizedRequest()
            )
            ad.fullScreenContentDelegate = self
            self.rewardedAd = ad
            self.isReady = true
            self.lastError = nil
            retry.loadSucceeded()
            AnalyticsClient.shared.track(
                "ad_loaded",
                properties: ["ad_unit": .string(Self.rewardedAdUnitID)]
            )
        } catch {
            self.rewardedAd = nil
            self.isReady = false
            self.lastError = error.localizedDescription
            // The code and domain tell "no ad available" apart from an
            // account or configuration problem; the message alone does not.
            let nsError = error as NSError
            AnalyticsClient.shared.track(
                "ad_load_failed",
                properties: [
                    "ad_unit": .string(Self.rewardedAdUnitID),
                    "error":   .string(error.localizedDescription),
                    "error_code":   .int(nsError.code),
                    "error_domain": .string(nsError.domain),
                ]
            )
            if let wait = retry.loadFailed() {
                scheduleRetry(after: wait)
            }
        }
    }

    /// Start a load if there is no ad ready and none loading.  Called when
    /// "Watch ad" is tapped with no ad ready and when the out-of-lives
    /// screen appears.
    func loadIfNeeded() {
        Task { await loadRewarded() }
    }

    /// Try again once `wait` seconds have passed, unless something else has
    /// loaded an ad or the app has gone to the background by then.
    private func scheduleRetry(after wait: TimeInterval) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            guard self.retry.retryIsDue(adReady: self.rewardedAd != nil) else { return }
            await self.loadRewarded()
        }
    }

    #if DEBUG
    /// Debug builds only: the audience settings as the SDK itself reports
    /// them, shown in Settings → Debug so they can be checked without
    /// reading the code.
    var debugAudienceSummary: String {
        let config = MobileAds.shared.requestConfiguration
        let age = config.ageRestrictedTreatment == .child ? "child" : "NOT child"
        let rating = config.maxAdContentRating == .general ? "G (general audiences)" : "NOT G"
        let location = config.coarseLocationCollectionEnabled ? "ON" : "off"
        return "Age treatment: \(age) · Content cap: \(rating) · Location collection: \(location)"
    }
    #endif

    // MARK: - Foreground / background

    /// The app came to the foreground: with no ad ready and no load running,
    /// start one.
    func appDidBecomeActive() {
        if retry.didEnterForeground(adReady: rewardedAd != nil) {
            loadIfNeeded()
        }
    }

    /// The app went to the background: drop any waiting retry.  Nothing is
    /// loaded until the app is back.
    func appDidEnterBackground() {
        retry.didEnterBackground()
        retryTask?.cancel()
        retryTask = nil
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
