import Foundation

// ---------------------------------------------------------------------------
// AdRetrySchedule — when the rewarded ad should be loaded again.
//
// Plain logic with no ads SDK in it, so it can be unit tested.  AdManager
// owns one and asks it before every load and after every result:
//
//   • One load at a time: `beginLoad` refuses while a load is running or an
//     ad is already waiting.
//   • After a failed load, wait before trying again: 10 s, 30 s, 60 s, then
//     every 2 minutes.  A successful load starts the waits over.
//   • No retries while the app is in the background.  A failure there
//     schedules nothing; the return to the foreground starts the next load.
// ---------------------------------------------------------------------------
struct AdRetrySchedule: Equatable {

    /// Waits after the first, second and third failed load in a row.
    static let firstWaits: [TimeInterval] = [10, 30, 60]
    /// The wait after every later failure.
    static let steadyWait: TimeInterval = 120

    /// The wait before the retry that follows the `failures`-th failed load
    /// in a row (1 = the first failure).
    static func wait(afterFailures failures: Int) -> TimeInterval {
        guard failures >= 1 else { return firstWaits[0] }
        return failures <= firstWaits.count ? firstWaits[failures - 1] : steadyWait
    }

    /// Failed loads in a row since the last success.
    private(set) var failuresInARow = 0
    /// True between `beginLoad` returning true and the load's result.
    private(set) var isLoading = false
    /// False while the app is in the background.
    private(set) var isInForeground = true

    /// Ask before starting a load.  True means "go ahead" and marks a load as
    /// running; false means one is already running or an ad is already ready.
    mutating func beginLoad(adReady: Bool) -> Bool {
        guard !isLoading, !adReady else { return false }
        isLoading = true
        return true
    }

    /// The running load produced an ad.  The waits start over.
    mutating func loadSucceeded() {
        isLoading = false
        failuresInARow = 0
    }

    /// The running load failed.  Returns how long to wait before the next
    /// try, or nil when no retry should be scheduled because the app is in
    /// the background.
    mutating func loadFailed() -> TimeInterval? {
        isLoading = false
        failuresInARow += 1
        return isInForeground ? Self.wait(afterFailures: failuresInARow) : nil
    }

    /// The app went to the background.  Any waiting retry must be dropped by
    /// the caller; `retryIsDue` stays false until the app is back.
    mutating func didEnterBackground() {
        isInForeground = false
    }

    /// The app came back to the foreground.  Returns true when a load should
    /// start now: no ad is ready and no load is running.
    mutating func didEnterForeground(adReady: Bool) -> Bool {
        isInForeground = true
        return !adReady && !isLoading
    }

    /// Asked when a retry's wait is over: should the load start?  False in
    /// the background, while a load is running, or once an ad is ready.
    func retryIsDue(adReady: Bool) -> Bool {
        isInForeground && !isLoading && !adReady
    }
}
