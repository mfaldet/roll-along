import XCTest
@testable import RollAlong

/// The rewarded-ad retry rules, tested without the ads SDK.
final class AdRetryScheduleTests: XCTestCase {

    /// Fail a load `times` times in a row and collect the waits handed back.
    private func waits(afterFailing times: Int, on schedule: inout AdRetrySchedule) -> [TimeInterval?] {
        (0..<times).map { _ in
            XCTAssertTrue(schedule.beginLoad(adReady: false))
            return schedule.loadFailed()
        }
    }

    // MARK: The wait sequence

    func test_waitsGrow_10_30_60_thenEveryTwoMinutes() {
        var schedule = AdRetrySchedule()
        XCTAssertEqual(waits(afterFailing: 6, on: &schedule), [10, 30, 60, 120, 120, 120])
    }

    func test_waitAfterFailures_table() {
        XCTAssertEqual(AdRetrySchedule.wait(afterFailures: 1), 10)
        XCTAssertEqual(AdRetrySchedule.wait(afterFailures: 2), 30)
        XCTAssertEqual(AdRetrySchedule.wait(afterFailures: 3), 60)
        XCTAssertEqual(AdRetrySchedule.wait(afterFailures: 4), 120)
        XCTAssertEqual(AdRetrySchedule.wait(afterFailures: 50), 120)
    }

    // MARK: Reset after success

    func test_successStartsTheWaitsOver() {
        var schedule = AdRetrySchedule()
        XCTAssertEqual(waits(afterFailing: 3, on: &schedule), [10, 30, 60])

        XCTAssertTrue(schedule.beginLoad(adReady: false))
        schedule.loadSucceeded()
        XCTAssertEqual(schedule.failuresInARow, 0)

        // The ad was shown and dismissed; the next load fails again.
        XCTAssertEqual(waits(afterFailing: 2, on: &schedule), [10, 30])
    }

    // MARK: One load at a time

    func test_noSecondLoadWhileOneIsRunning() {
        var schedule = AdRetrySchedule()
        XCTAssertTrue(schedule.beginLoad(adReady: false))
        XCTAssertFalse(schedule.beginLoad(adReady: false), "a second load must be refused")
        XCTAssertFalse(schedule.retryIsDue(adReady: false), "a retry must not start a second load")
        XCTAssertFalse(schedule.didEnterForeground(adReady: false), "coming to the foreground must not start a second load")

        _ = schedule.loadFailed()
        XCTAssertTrue(schedule.beginLoad(adReady: false), "once the first load has ended, the next may start")
    }

    func test_noLoadWhileAnAdIsReady() {
        var schedule = AdRetrySchedule()
        XCTAssertFalse(schedule.beginLoad(adReady: true))
        XCTAssertFalse(schedule.isLoading)
        XCTAssertFalse(schedule.retryIsDue(adReady: true))
        XCTAssertFalse(schedule.didEnterForeground(adReady: true))
    }

    // MARK: Nothing in the background

    func test_failureInTheBackgroundSchedulesNoRetry() {
        var schedule = AdRetrySchedule()
        XCTAssertTrue(schedule.beginLoad(adReady: false))
        schedule.didEnterBackground()
        XCTAssertNil(schedule.loadFailed(), "a load that fails in the background must not schedule a retry")
    }

    func test_aWaitingRetryIsNotDueInTheBackground() {
        var schedule = AdRetrySchedule()
        XCTAssertTrue(schedule.beginLoad(adReady: false))
        XCTAssertEqual(schedule.loadFailed(), 10)
        XCTAssertTrue(schedule.retryIsDue(adReady: false))

        schedule.didEnterBackground()
        XCTAssertFalse(schedule.retryIsDue(adReady: false))
    }

    func test_returningToTheForegroundStartsALoad_andKeepsTheWaits() {
        var schedule = AdRetrySchedule()
        XCTAssertEqual(waits(afterFailing: 2, on: &schedule), [10, 30])

        schedule.didEnterBackground()
        XCTAssertTrue(schedule.didEnterForeground(adReady: false), "no ad and no load: start one")

        // The waits carry on from where they were, not from the start.
        XCTAssertTrue(schedule.beginLoad(adReady: false))
        XCTAssertEqual(schedule.loadFailed(), 60)
    }
}
