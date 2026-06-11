import XCTest
@testable import RollAlong

// ---------------------------------------------------------------------------
// GameStateTests — unit tests for the most business-critical class.
//
// GameState persists to UserDefaults in didSet observers; tests that mutate
// state will write to the standard suite.  Each test creates a fresh
// GameState() so they are isolated from each other (GameState.init() reads
// from UserDefaults, so tests share the stored suite — reset sensitive fields
// in setUp if needed for test ordering sensitivity).
// ---------------------------------------------------------------------------

final class GameStateTests: XCTestCase {

    // MARK: - addCoins — normal cases

    func testAddCoins_positiveAmount_increasesBalance() {
        let gs = GameState()
        gs.coinBalance = 100
        gs.addCoins(50)
        XCTAssertEqual(gs.coinBalance, 150)
    }

    func testAddCoins_zeroAmount_noChange() {
        let gs = GameState()
        gs.coinBalance = 200
        gs.addCoins(0)
        XCTAssertEqual(gs.coinBalance, 200)
    }

    // MARK: - addCoins — ceiling

    func testAddCoins_exactlyAtCeiling_noChange() {
        let gs = GameState()
        gs.coinBalance = GameState.maxCoinBalance
        gs.addCoins(1)
        XCTAssertEqual(gs.coinBalance, GameState.maxCoinBalance)
    }

    func testAddCoins_wouldExceedCeiling_clampsToMax() {
        let gs = GameState()
        gs.coinBalance = GameState.maxCoinBalance - 5
        gs.addCoins(50)
        XCTAssertEqual(gs.coinBalance, GameState.maxCoinBalance)
    }

    func testAddCoins_largeAmountFromZero_clampsToMax() {
        let gs = GameState()
        gs.coinBalance = 0
        gs.addCoins(999_999_999)   // way over maxSingleAward → clamped to maxSingleAward, then balance ceiling
        XCTAssertLessThanOrEqual(gs.coinBalance, GameState.maxCoinBalance)
        XCTAssertGreaterThan(gs.coinBalance, 0)
    }

    // MARK: - spendCoins

    func testSpendCoins_sufficientBalance_deductsAndReturnsTrue() {
        let gs = GameState()
        gs.coinBalance = 500
        let success = gs.spendCoins(200)
        XCTAssertTrue(success)
        XCTAssertEqual(gs.coinBalance, 300)
    }

    func testSpendCoins_exactBalance_deductsToZero() {
        let gs = GameState()
        gs.coinBalance = 100
        let success = gs.spendCoins(100)
        XCTAssertTrue(success)
        XCTAssertEqual(gs.coinBalance, 0)
    }

    func testSpendCoins_insufficientBalance_returnsFalseNoChange() {
        let gs = GameState()
        gs.coinBalance = 100
        let success = gs.spendCoins(200)
        XCTAssertFalse(success)
        XCTAssertEqual(gs.coinBalance, 100, "Balance should be unchanged on failure")
    }

    func testSpendCoins_zeroAmount_returnsTrueNoChange() {
        let gs = GameState()
        gs.coinBalance = 100
        let success = gs.spendCoins(0)
        XCTAssertTrue(success)
        XCTAssertEqual(gs.coinBalance, 100)
    }

    func testSpendCoins_negativeAmount_returnsFalse() {
        let gs = GameState()
        gs.coinBalance = 100
        let success = gs.spendCoins(-50)
        XCTAssertFalse(success, "Negative spend amount should always fail")
    }

    // MARK: - addCoins / spendCoins round-trip

    func testCoinRoundTrip_addThenSpend_correctBalance() {
        let gs = GameState()
        gs.coinBalance = 0
        gs.addCoins(300)
        _ = gs.spendCoins(100)
        XCTAssertEqual(gs.coinBalance, 200)
    }

    // MARK: - Review prompt gating

    func testMaybeRequestReview_belowLevel5_doesNotSetPromptDate() {
        let gs = GameState()
        gs.highestUnlocked = 4
        gs.lastReviewPromptDate = nil
        gs.maybeRequestReview(after: true)
        XCTAssertNil(gs.lastReviewPromptDate,
                     "Prompt should not fire when highestUnlocked < 5")
    }

    func testMaybeRequestReview_winFalse_doesNotFire() {
        let gs = GameState()
        gs.highestUnlocked = 10
        gs.lastReviewPromptDate = nil
        gs.maybeRequestReview(after: false)   // after: false means no win
        XCTAssertNil(gs.lastReviewPromptDate,
                     "Prompt should not fire on a loss")
    }

    func testMaybeRequestReview_recentPrompt_doesNotFire() {
        let gs = GameState()
        gs.highestUnlocked = 20
        let recentDate = Date()
        gs.lastReviewPromptDate = recentDate
        gs.maybeRequestReview(after: true)
        // Date should be unchanged (no update while cooldown active)
        let delta = abs(gs.lastReviewPromptDate!.timeIntervalSince(recentDate))
        XCTAssertLessThan(delta, 1.0,
                          "lastReviewPromptDate should not change within cooldown period")
    }

    func testMaybeRequestReview_eligiblePlayer_setsPromptDate() {
        let gs = GameState()
        gs.highestUnlocked = 10
        // Simulate last prompt far in the past (well beyond 30-day cooldown)
        gs.lastReviewPromptDate = Date(timeIntervalSinceNow: -(40 * 86_400))
        gs.maybeRequestReview(after: true)
        // lastReviewPromptDate should now be a recent date
        let delta = abs(gs.lastReviewPromptDate!.timeIntervalSinceNow)
        XCTAssertLessThan(delta, 2.0,
                          "lastReviewPromptDate should be updated to approximately now")
    }

    func testMaybeRequestReview_noPreviousPrompt_eligiblePlayer_setsPromptDate() {
        let gs = GameState()
        gs.highestUnlocked = 10
        gs.lastReviewPromptDate = nil
        gs.maybeRequestReview(after: true)
        XCTAssertNotNil(gs.lastReviewPromptDate,
                        "First eligible review prompt should set lastReviewPromptDate")
    }

    // MARK: - Track progression

    func testAdvanceTrackProgress_newHighWaterMark_advances() {
        let gs = GameState()
        let trackID = "test-track-\(UUID().uuidString)"  // unique to avoid state pollution
        gs.advanceTrackProgress(trackID: trackID, to: 5)
        XCTAssertEqual(gs.trackProgress[trackID], 5)
    }

    func testAdvanceTrackProgress_lowerLevel_doesNotRegress() {
        let gs = GameState()
        let trackID = "test-track-\(UUID().uuidString)"
        gs.advanceTrackProgress(trackID: trackID, to: 10)
        gs.advanceTrackProgress(trackID: trackID, to: 3)   // lower than stored high
        XCTAssertEqual(gs.trackProgress[trackID], 10,
                       "Progress should never go backward")
    }

    func testAdvanceTrackProgress_sameLevel_noChange() {
        let gs = GameState()
        let trackID = "test-track-\(UUID().uuidString)"
        gs.advanceTrackProgress(trackID: trackID, to: 7)
        gs.advanceTrackProgress(trackID: trackID, to: 7)
        XCTAssertEqual(gs.trackProgress[trackID], 7)
    }

    // MARK: - Cosmetic ownership

    func testGrantBallSkin_ownedAfterGrant() {
        let gs = GameState()
        gs.grant(BallSkin.green)
        XCTAssertTrue(gs.isOwned(BallSkin.green))
    }

    func testStarterSkin_alwaysOwned() {
        let gs = GameState()
        // Starter items are owned regardless of the owned set
        XCTAssertTrue(gs.isOwned(BallSkin.red),
                      "The starter ball skin should always be owned")
    }

    // MARK: - Lives

    func testAddLives_increasesLives() {
        let gs = GameState()
        // addLives is a no-op under unlimited lives, and commitRegen() can fold
        // in regenerated lives when lastLifeLostAt is set — pin both so the
        // assertion is deterministic regardless of any persisted state.
        gs.unlimitedLives = false
        gs.lastLifeLostAt = nil
        gs.lives = 3
        gs.addLives(3)
        XCTAssertEqual(gs.lives, 6)
    }
}
