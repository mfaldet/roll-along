import Foundation
import UserNotifications

// ---------------------------------------------------------------------------
// NotificationManager — local notifications for the two events a player can
// opt into (Settings → Notifications):
//
//   • SHOP FRESH — ONE alert the first time the shop rotates after the player
//     last viewed it.  GameState.recordShopViewed() (called when the Shop
//     appears) schedules it for the next hourly rotation boundary, replacing
//     any prior request; after it fires there's no more until they view again.
//
//   • LIVES FULL — ONE alert when the free 6-minute regen brings lives back to
//     the max of 10, but only after they'd dropped below 10.  GameState
//     .reconcileLivesNotification() schedules it for the deterministic restock
//     time after every lives change (and on app foreground); earning a life to
//     the cap or topping up cancels it.
//
// Both are SCHEDULED local notifications (deterministic future timestamps), so
// they fire whether the app is foreground (even mid-minigame — see the
// foreground-presentation delegate), backgrounded, or killed.  No background
// execution or server is involved.
//
// Mirrors the AnalyticsClient / SocialClient singleton shape: `.shared`,
// referenced directly (no @EnvironmentObject).  GameState owns the when/whether
// and calls schedule*/cancel*; this class is a thin scheduler + delegate.
// ---------------------------------------------------------------------------

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() { super.init() }

    private let center = UNUserNotificationCenter.current()

    // Fixed request identifiers — re-adding one replaces the pending request,
    // so we never stack duplicates.
    private enum ID {
        static let shopFresh = "ra.notif.shopFresh"
        static let livesFull = "ra.notif.livesFull"
    }

    /// Suppress all notification activity under the UI-test runner so the
    /// system permission prompt can't appear and hang a test.
    private var isUITesting: Bool { CommandLine.arguments.contains("--uitesting") }

    // MARK: - Lifecycle

    /// Install the foreground-presentation delegate.  Call once at app launch.
    func start() {
        guard !isUITesting else { return }
        center.delegate = self
    }

    /// Ask for permission if we haven't already.  Idempotent — iOS only shows
    /// the system prompt while status is `.notDetermined`; later calls no-op.
    /// Call when the player enables a notification toggle.
    func requestAuthorization() {
        guard !isUITesting else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Shop fresh

    /// One "new in the shop" alert at the next rotation boundary.
    func scheduleShopFresh(at date: Date) {
        schedule(id: ID.shopFresh, at: date,
                 title: "New in the Shop",
                 body: "Fresh items just landed — take a look before they rotate out.")
    }
    func cancelShopFresh() { cancel(id: ID.shopFresh) }

    // MARK: - Lives full

    /// One "lives full" alert at the deterministic restock time.
    func scheduleLivesFull(at date: Date) {
        schedule(id: ID.livesFull, at: date,
                 title: "Lives Restored",
                 body: "You're back to a full bar of 10 — ready to climb.")
    }
    func cancelLivesFull() { cancel(id: ID.livesFull) }

    // MARK: - Plumbing

    private func schedule(id: String, at date: Date, title: String, body: String) {
        guard !isUITesting else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Relative trigger (>= 1s) — robust against same-second edge cases and
        // unaffected by wall-clock changes; fires once.
        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)   // same identifier replaces any pending request
    }

    private func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Present the banner + sound even when the app is in the foreground, so a
    /// player mid-minigame still sees the alert.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
