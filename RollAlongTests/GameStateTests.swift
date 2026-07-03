import XCTest
@testable import RollAlong

// ---------------------------------------------------------------------------
// GameStateTests — unit tests for the most business-critical class.
//
// Each test runs against a private, throwaway UserDefaults suite (see setUp),
// injected via GameState(defaults:).  Tests never touch the real "standard"
// save, so they are fully isolated from each other and never disturb the
// app's actual game state on the simulator.
// ---------------------------------------------------------------------------

final class GameStateTests: XCTestCase {

    // Every test runs against a throwaway UserDefaults suite, wiped in setUp,
    // so GameState never reads or writes the real save — tests are isolated
    // from each other and never disturb the app's actual game state.
    private var defaults: UserDefaults!
    private let suiteName = "GameStateTests.isolated"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// A GameState backed by the isolated suite (starts from fresh, empty state).
    private func makeGameState() -> GameState {
        GameState(defaults: defaults)
    }

    // MARK: - Notification scheduling logic

    /// The lives-full notification fires at the deterministic regen restock
    /// instant: lastLifeLostAt + (10 − lives) × 6 min.
    func testLivesRestockDate() {
        let gs = makeGameState()
        gs.unlimitedLives = false
        let t0 = Date()
        gs.lives = 7
        gs.lastLifeLostAt = t0
        XCTAssertEqual(gs.livesRestockDate?.timeIntervalSince(t0) ?? -1,
                       Double(10 - 7) * GameState.livesRegenInterval, accuracy: 0.5)
        // Full bar → nothing pending.
        gs.lives = 10
        gs.lastLifeLostAt = nil
        XCTAssertNil(gs.livesRestockDate)
        // Unlimited → never schedules.
        gs.lives = 5
        gs.lastLifeLostAt = Date()
        gs.unlimitedLives = true
        XCTAssertNil(gs.livesRestockDate)
    }

    /// `livesRestockDate` is invariant under `commitRegen()` — the absolute
    /// restock instant doesn't drift as regen ticks accrue/commit.
    func testLivesRestockDateInvariantUnderRegen() {
        let gs = makeGameState()
        gs.unlimitedLives = false
        gs.lives = 6
        gs.lastLifeLostAt = Date().addingTimeInterval(-400)   // ~1 tick accrued, uncommitted
        let before = gs.livesRestockDate
        gs.commitRegen()                                       // promotes the accrued tick
        let after = gs.livesRestockDate
        XCTAssertNotNil(before); XCTAssertNotNil(after)
        XCTAssertEqual(before!.timeIntervalSinceReferenceDate,
                       after!.timeIntervalSinceReferenceDate, accuracy: 0.5)
    }

    /// The shop-fresh notification targets the next hourly rotation boundary.
    func testShopRefreshBoundaryIsNextHour() {
        let now = Date()
        let next = ShopRotation.refreshDate(at: now)
        XCTAssertGreaterThan(next.timeIntervalSince(now), 0)
        XCTAssertLessThanOrEqual(next.timeIntervalSince(now), 3600)
        XCTAssertEqual(next.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600),
                       0, accuracy: 0.001, "must land exactly on an hourly boundary")
    }

    // MARK: - Minigame difficulty (payout scaling + success tracking)

    func testMinigamePayout_scalesByDifficulty() {
        let gs = makeGameState()
        XCTAssertEqual(gs.minigamePayout(base: 100, difficulty: .easy),   100)
        XCTAssertEqual(gs.minigamePayout(base: 100, difficulty: .normal), 150)
        XCTAssertEqual(gs.minigamePayout(base: 100, difficulty: .hard),   200)
        // Rounds to the nearest coin.
        XCTAssertEqual(gs.minigamePayout(base: 5, difficulty: .normal), 8)   // 7.5 -> 8
    }

    func testPayoutMultiplier_spreadIsOneOneHalfTwo() {
        XCTAssertEqual(MinigameDifficulty.easy.payoutMultiplier,   1.0)
        XCTAssertEqual(MinigameDifficulty.normal.payoutMultiplier, 1.5)
        XCTAssertEqual(MinigameDifficulty.hard.payoutMultiplier,   2.0)
    }

    func testRecordMinigameResult_loss_countsAttemptAndAwardsScaledPayout() {
        let gs = makeGameState()
        gs.coinBalance = 0
        let paid = gs.recordMinigameResult(modeID: "snake", difficulty: .hard,
                                           won: false, score: 0, basePayout: 30)
        XCTAssertEqual(paid, 60, "30 base × 2.0 (hard)")
        XCTAssertEqual(gs.coinBalance, 60)
        XCTAssertEqual(gs.minigameDifficultyPlays["snake|hard"], 1)
        XCTAssertNil(gs.minigameDifficultyWins["snake|hard"], "a loss is not a win")
        XCTAssertEqual(gs.minigameWins["snake"] ?? 0, 0, "lifetime win tally untouched on a loss")
        XCTAssertEqual(gs.minigameSuccessRate("snake", .hard), 0.0)
    }

    func testRecordMinigameResult_win_countsWinAndBumpsLifetimeTally() {
        let gs = makeGameState()
        gs.coinBalance = 0
        let paid = gs.recordMinigameResult(modeID: "sumo", difficulty: .easy,
                                           won: true, score: 0, basePayout: 10)
        XCTAssertEqual(paid, 10, "10 base × 1.0 (easy)")
        XCTAssertEqual(gs.coinBalance, 10)
        XCTAssertEqual(gs.minigameDifficultyPlays["sumo|easy"], 1)
        XCTAssertEqual(gs.minigameDifficultyWins["sumo|easy"], 1)
        XCTAssertEqual(gs.minigameWins["sumo"], 1, "win bumps the lifetime tally")
        XCTAssertEqual(gs.minigameSuccessRate("sumo", .easy), 1.0)
    }

    func testMinigameSuccessRate_aggregatesAndIsNilWhenUnplayed() {
        let gs = makeGameState()
        XCTAssertNil(gs.minigameSuccessRate("koth", .normal), "never played → nil")
        gs.recordMinigameResult(modeID: "koth", difficulty: .normal, won: true,  score: 0, basePayout: 0)
        gs.recordMinigameResult(modeID: "koth", difficulty: .normal, won: false, score: 0, basePayout: 0)
        gs.recordMinigameResult(modeID: "koth", difficulty: .normal, won: false, score: 0, basePayout: 0)
        XCTAssertEqual(gs.minigameDifficultyPlays["koth|normal"], 3)
        XCTAssertEqual(gs.minigameSuccessRate("koth", .normal) ?? -1, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testMinigameDifficultyTracking_persistsAcrossReload() {
        let gs = makeGameState()
        gs.recordMinigameResult(modeID: "paintball", difficulty: .hard, won: true, score: 0, basePayout: 0)
        let reloaded = GameState(defaults: defaults)
        XCTAssertEqual(reloaded.minigameDifficultyPlays["paintball|hard"], 1)
        XCTAssertEqual(reloaded.minigameDifficultyWins["paintball|hard"], 1)
    }

    func testMinigameDifficultyBest_keepsTheMaxPerDifficulty() {
        let gs = makeGameState()
        gs.recordMinigameResult(modeID: "snake", difficulty: .hard, won: false, score: 40, basePayout: 0)
        gs.recordMinigameResult(modeID: "snake", difficulty: .hard, won: true,  score: 25, basePayout: 0)
        XCTAssertEqual(gs.minigameDifficultyBests["snake|hard"], 40, "best keeps the max, not the latest")
        // A different difficulty is tracked independently.
        gs.recordMinigameResult(modeID: "snake", difficulty: .easy, won: true, score: 12, basePayout: 0)
        XCTAssertEqual(gs.minigameDifficultyBests["snake|easy"], 12)
        XCTAssertEqual(gs.minigameDifficultyBests["snake|hard"], 40)
    }

    // MARK: - Roll Up highscore (height + run time)

    /// The record keeps the best HEIGHT and the time of that run; height is the
    /// primary key, and on a tie the LONGER run wins (endurance).  A strictly
    /// lower height never changes the record.
    func testRecordRollUpRun_keepsBestHeightAndItsTime() {
        let gs = makeGameState()

        // First real run sets the record and reports a new best.
        XCTAssertTrue(gs.recordRollUpRun(height: 120, seconds: 45))
        XCTAssertEqual(gs.rollupBest, 120)
        XCTAssertEqual(gs.rollupBestSeconds, 45)

        // A higher climb replaces both, even if it was quicker.
        XCTAssertTrue(gs.recordRollUpRun(height: 200, seconds: 30))
        XCTAssertEqual(gs.rollupBest, 200)
        XCTAssertEqual(gs.rollupBestSeconds, 30)

        // A lower climb is ignored entirely (height AND time unchanged).
        XCTAssertFalse(gs.recordRollUpRun(height: 150, seconds: 999))
        XCTAssertEqual(gs.rollupBest, 200)
        XCTAssertEqual(gs.rollupBestSeconds, 30)

        // Same height on a LONGER run keeps the longer time (endurance tiebreak),
        // but it is not a new height "best".
        XCTAssertFalse(gs.recordRollUpRun(height: 200, seconds: 90))
        XCTAssertEqual(gs.rollupBest, 200)
        XCTAssertEqual(gs.rollupBestSeconds, 90)

        // Same height on a shorter run does not shrink the recorded time.
        XCTAssertFalse(gs.recordRollUpRun(height: 200, seconds: 10))
        XCTAssertEqual(gs.rollupBestSeconds, 90)

        // A zero-height run is a no-op.
        XCTAssertFalse(gs.recordRollUpRun(height: 0, seconds: 5))
        XCTAssertEqual(gs.rollupBest, 200)
    }

    /// The Roll Up record survives a reload (height in the shared dict, seconds
    /// in its own key).
    func testRecordRollUpRun_persistsAcrossReload() {
        let gs = makeGameState()
        _ = gs.recordRollUpRun(height: 275, seconds: 132)
        let reloaded = GameState(defaults: defaults)
        XCTAssertEqual(reloaded.rollupBest, 275)
        XCTAssertEqual(reloaded.rollupBestSeconds, 132)
    }

    // MARK: - Challenge of the Day

    func testDailyChallenge_fullPass_awards30CoinsAndLocksDay() {
        let gs = makeGameState()
        gs.coinBalance = 0
        gs.startDailyChallenge()
        XCTAssertEqual(gs.dailyChallengeAttemptsLeft, 3)
        XCTAssertFalse(gs.dailyChallengeDoneToday)

        // Clear every sub-level of today's gauntlet.
        var done = false
        while !done { done = gs.advanceDailyChallenge() }
        gs.completeTodaysDailyChallenge()

        XCTAssertEqual(gs.todaysDailyChallenge.rewardCoins, 30, "CotD reward is a flat 30 coins")
        XCTAssertEqual(gs.coinBalance, 30, "clearing the day banks exactly 30 coins")
        XCTAssertTrue(gs.dailyChallengeDoneToday)
        XCTAssertFalse(gs.dailyChallengeFailedToday)
        XCTAssertTrue(gs.dailyChallengeSettledToday)
    }

    func testDailyChallenge_completeIsIdempotent_doesNotDoubleReward() {
        let gs = makeGameState()
        gs.coinBalance = 0
        gs.startDailyChallenge()
        var done = false
        while !done { done = gs.advanceDailyChallenge() }
        gs.completeTodaysDailyChallenge()
        gs.completeTodaysDailyChallenge()   // second call must be a no-op
        XCTAssertEqual(gs.coinBalance, 30)
    }

    func testDailyChallenge_threeFailures_exhaustsAttemptsAndFailsDay() {
        let gs = makeGameState()
        gs.startDailyChallenge()
        XCTAssertFalse(gs.recordDailyAttemptFailure())   // 3 -> 2
        XCTAssertEqual(gs.dailyChallengeAttemptsLeft, 2)
        XCTAssertFalse(gs.recordDailyAttemptFailure())   // 2 -> 1
        XCTAssertTrue(gs.recordDailyAttemptFailure())    // 1 -> 0, exhausted
        XCTAssertEqual(gs.dailyChallengeAttemptsLeft, 0)

        gs.failTodaysDailyChallenge()
        XCTAssertTrue(gs.dailyChallengeFailedToday)
        XCTAssertTrue(gs.dailyChallengeSettledToday)
        XCTAssertFalse(gs.dailyChallengeDoneToday, "a failed day is not a cleared day")
    }

    func testDailyChallenge_advancingASubLevel_refreshesAttempts() {
        let gs = makeGameState()
        gs.startDailyChallenge()
        guard gs.todaysDailyChallenge.levelCount >= 2 else {
            return   // single-level day — nothing to advance into
        }
        _ = gs.recordDailyAttemptFailure()                // 3 -> 2
        XCTAssertEqual(gs.dailyChallengeAttemptsLeft, 2)
        let done = gs.advanceDailyChallenge()             // into sub-level 1
        XCTAssertFalse(done)
        XCTAssertEqual(gs.dailyChallengeAttemptsLeft, 3, "each new sub-level grants a fresh 3")
    }

    func testDailyChallenge_failurePersistsAcrossReload() {
        let gs = makeGameState()
        gs.failTodaysDailyChallenge()
        XCTAssertTrue(gs.dailyChallengeFailedToday)
        let reloaded = GameState(defaults: defaults)
        XCTAssertTrue(reloaded.dailyChallengeFailedToday, "failure is saved + reloaded")
    }

    func testDailyChallenge_quitWhileRunning_forfeitsTheDay() {
        let gs = makeGameState()
        gs.startDailyChallenge()
        XCTAssertEqual(gs.dailyChallengeRunStartedKey, DailyChallenge.key())
        XCTAssertFalse(gs.dailyChallengeFailedToday)

        gs.forfeitDailyChallengeIfRunning()   // home button / app kill mid-run
        XCTAssertTrue(gs.dailyChallengeFailedToday)
        XCTAssertNil(gs.dailyChallengeRunStartedKey)
    }

    func testDailyChallenge_abandonedRunForfeitsOnReload() {
        // Start a run, then simulate an app kill: a fresh GameState reloads the
        // persisted in-progress key, and the home reconcile fails the day.
        let a = makeGameState()
        a.startDailyChallenge()
        XCTAssertFalse(a.dailyChallengeDoneToday)

        let reloaded = GameState(defaults: defaults)
        XCTAssertEqual(reloaded.dailyChallengeRunStartedKey, DailyChallenge.key())
        reloaded.forfeitDailyChallengeIfRunning()
        XCTAssertTrue(reloaded.dailyChallengeFailedToday)
    }

    func testDailyChallenge_completeClearsInProgressKey_andSurvivesReconcile() {
        let gs = makeGameState()
        gs.startDailyChallenge()
        var done = false
        while !done { done = gs.advanceDailyChallenge() }
        gs.completeTodaysDailyChallenge()
        XCTAssertNil(gs.dailyChallengeRunStartedKey, "completing settles the run")

        gs.forfeitDailyChallengeIfRunning()   // must NOT flip a cleared day to failed
        XCTAssertFalse(gs.dailyChallengeFailedToday)
        XCTAssertTrue(gs.dailyChallengeDoneToday)
    }

    func testDailyChallenge_staleRunKey_clearsWithoutFailingToday() {
        let gs = makeGameState()
        gs.dailyChallengeRunStartedKey = "2020-01-01"   // a run from a long-gone day
        gs.forfeitDailyChallengeIfRunning()
        XCTAssertFalse(gs.dailyChallengeFailedToday, "a stale key never penalises today")
        XCTAssertNil(gs.dailyChallengeRunStartedKey)
    }

    // MARK: - addCoins — normal cases

    func testAddCoins_positiveAmount_increasesBalance() {
        let gs = makeGameState()
        gs.coinBalance = 100
        gs.addCoins(50)
        XCTAssertEqual(gs.coinBalance, 150)
    }

    func testAddCoins_zeroAmount_noChange() {
        let gs = makeGameState()
        gs.coinBalance = 200
        gs.addCoins(0)
        XCTAssertEqual(gs.coinBalance, 200)
    }

    // MARK: - addCoins — ceiling

    func testAddCoins_exactlyAtCeiling_noChange() {
        let gs = makeGameState()
        gs.coinBalance = GameState.maxCoinBalance
        gs.addCoins(1)
        XCTAssertEqual(gs.coinBalance, GameState.maxCoinBalance)
    }

    func testAddCoins_wouldExceedCeiling_clampsToMax() {
        let gs = makeGameState()
        gs.coinBalance = GameState.maxCoinBalance - 5
        gs.addCoins(50)
        XCTAssertEqual(gs.coinBalance, GameState.maxCoinBalance)
    }

    func testAddCoins_largeAmountFromZero_clampsToMax() {
        let gs = makeGameState()
        gs.coinBalance = 0
        gs.addCoins(999_999_999)   // way over maxSingleAward → clamped to maxSingleAward, then balance ceiling
        XCTAssertLessThanOrEqual(gs.coinBalance, GameState.maxCoinBalance)
        XCTAssertGreaterThan(gs.coinBalance, 0)
    }

    /// The single-award clamp must clear the biggest legitimate grant — the
    /// top coin pack's 60,000 (2026-07 IAP re-anchor).  If maxSingleAward
    /// falls behind rewardCoins, a $49.99 purchase silently short-delivers.
    func testAddCoins_topCoinPackGrant_isNotClamped() {
        let gs = makeGameState()
        gs.coinBalance = 0
        let topGrant = StoreKitManager.ProductID.coins10000.rewardCoins
        XCTAssertEqual(topGrant, 60_000, "top pack grants 60,000 coins post-reprice")
        gs.addCoins(topGrant)
        XCTAssertEqual(gs.coinBalance, topGrant,
                       "the top coin pack grant must never be clamped by maxSingleAward")
    }

    // MARK: - spendCoins

    func testSpendCoins_sufficientBalance_deductsAndReturnsTrue() {
        let gs = makeGameState()
        gs.coinBalance = 500
        let success = gs.spendCoins(200)
        XCTAssertTrue(success)
        XCTAssertEqual(gs.coinBalance, 300)
    }

    func testSpendCoins_exactBalance_deductsToZero() {
        let gs = makeGameState()
        gs.coinBalance = 100
        let success = gs.spendCoins(100)
        XCTAssertTrue(success)
        XCTAssertEqual(gs.coinBalance, 0)
    }

    func testSpendCoins_insufficientBalance_returnsFalseNoChange() {
        let gs = makeGameState()
        gs.coinBalance = 100
        let success = gs.spendCoins(200)
        XCTAssertFalse(success)
        XCTAssertEqual(gs.coinBalance, 100, "Balance should be unchanged on failure")
    }

    func testSpendCoins_zeroAmount_returnsTrueNoChange() {
        let gs = makeGameState()
        gs.coinBalance = 100
        let success = gs.spendCoins(0)
        XCTAssertTrue(success)
        XCTAssertEqual(gs.coinBalance, 100)
    }

    func testSpendCoins_negativeAmount_returnsFalse() {
        let gs = makeGameState()
        gs.coinBalance = 100
        let success = gs.spendCoins(-50)
        XCTAssertFalse(success, "Negative spend amount should always fail")
    }

    // MARK: - addCoins / spendCoins round-trip

    func testCoinRoundTrip_addThenSpend_correctBalance() {
        let gs = makeGameState()
        gs.coinBalance = 0
        gs.addCoins(300)
        _ = gs.spendCoins(100)
        XCTAssertEqual(gs.coinBalance, 200)
    }

    // MARK: - Review prompt gating

    func testMaybeRequestReview_belowLevel5_doesNotSetPromptDate() {
        let gs = makeGameState()
        gs.highestUnlocked = 4
        gs.lastReviewPromptDate = nil
        gs.maybeRequestReview(after: true)
        XCTAssertNil(gs.lastReviewPromptDate,
                     "Prompt should not fire when highestUnlocked < 5")
    }

    func testMaybeRequestReview_winFalse_doesNotFire() {
        let gs = makeGameState()
        gs.highestUnlocked = 10
        gs.lastReviewPromptDate = nil
        gs.maybeRequestReview(after: false)   // after: false means no win
        XCTAssertNil(gs.lastReviewPromptDate,
                     "Prompt should not fire on a loss")
    }

    func testMaybeRequestReview_recentPrompt_doesNotFire() {
        let gs = makeGameState()
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
        let gs = makeGameState()
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
        let gs = makeGameState()
        gs.highestUnlocked = 10
        gs.lastReviewPromptDate = nil
        gs.maybeRequestReview(after: true)
        XCTAssertNotNil(gs.lastReviewPromptDate,
                        "First eligible review prompt should set lastReviewPromptDate")
    }

    // MARK: - Track progression

    func testAdvanceTrackProgress_newHighWaterMark_advances() {
        let gs = makeGameState()
        let trackID = "test-track-\(UUID().uuidString)"  // unique to avoid state pollution
        gs.advanceTrackProgress(trackID: trackID, to: 5)
        XCTAssertEqual(gs.trackProgress[trackID], 5)
    }

    func testAdvanceTrackProgress_lowerLevel_doesNotRegress() {
        let gs = makeGameState()
        let trackID = "test-track-\(UUID().uuidString)"
        gs.advanceTrackProgress(trackID: trackID, to: 10)
        gs.advanceTrackProgress(trackID: trackID, to: 3)   // lower than stored high
        XCTAssertEqual(gs.trackProgress[trackID], 10,
                       "Progress should never go backward")
    }

    func testAdvanceTrackProgress_sameLevel_noChange() {
        let gs = makeGameState()
        let trackID = "test-track-\(UUID().uuidString)"
        gs.advanceTrackProgress(trackID: trackID, to: 7)
        gs.advanceTrackProgress(trackID: trackID, to: 7)
        XCTAssertEqual(gs.trackProgress[trackID], 7)
    }

    // MARK: - Cosmetic ownership

    func testGrantBallSkin_ownedAfterGrant() {
        let gs = makeGameState()
        gs.grant(BallSkin.green)
        XCTAssertTrue(gs.isOwned(BallSkin.green))
    }

    func testStarterSkin_alwaysOwned() {
        let gs = makeGameState()
        // Starter items are owned regardless of the owned set
        XCTAssertTrue(gs.isOwned(BallSkin.red),
                      "The starter ball skin should always be owned")
    }

    // MARK: - Lives

    func testAddLives_increasesLives() {
        let gs = makeGameState()
        // addLives is a no-op under unlimited lives, and commitRegen() can fold
        // in regenerated lives when lastLifeLostAt is set — pin both so the
        // assertion is deterministic regardless of any persisted state.
        gs.unlimitedLives = false
        gs.lastLifeLostAt = nil
        gs.lives = 3
        gs.addLives(3)
        XCTAssertEqual(gs.lives, 6)
    }

    // MARK: - Gold Rush tickets

    func testAddTickets_increasesBalance() {
        let gs = makeGameState()
        gs.addTickets(3)
        XCTAssertEqual(gs.tickets, 3)
    }

    func testSpendTickets_sufficientBalance_deductsAndReturnsTrue() {
        let gs = makeGameState()
        gs.addTickets(5)
        XCTAssertTrue(gs.spendTickets(3))
        XCTAssertEqual(gs.tickets, 2)
    }

    func testSpendTickets_insufficientBalance_returnsFalseNoChange() {
        let gs = makeGameState()
        gs.addTickets(2)
        XCTAssertFalse(gs.spendTickets(3))
        XCTAssertEqual(gs.tickets, 2, "Balance should be unchanged on failure")
    }

    func testAddTickets_clampsToCeiling() {
        let gs = makeGameState()
        gs.addTickets(GameState.maxTicketBalance + 50)
        XCTAssertEqual(gs.tickets, GameState.maxTicketBalance)
    }

    // MARK: - Persistence isolation (injected suite)

    func testInjectedSuite_persistsAcrossInstances() {
        let a = makeGameState()
        a.coinBalance = 4321
        // A second GameState on the SAME suite reads the saved value back.
        let b = GameState(defaults: defaults)
        XCTAssertEqual(b.coinBalance, 4321,
                       "A GameState on the same suite should read back the saved balance")
    }

    func testInjectedSuite_doesNotTouchStandard() {
        let key = "ra_coinBalance"
        let standardBefore = UserDefaults.standard.integer(forKey: key)
        let gs = makeGameState()
        gs.addCoins(777)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: key), standardBefore,
                       "Mutating an isolated GameState must not write to UserDefaults.standard")
    }

    // MARK: - Starter Pack offer window

    /// The one-shot trigger: fires only at coinBalance >= 50 with the offer
    /// never shown, never claimed, and the Aurora collection incomplete.
    func testStarterPackTrigger_firesOnceAtFiftyCoins() {
        let gs = makeGameState()
        XCTAssertFalse(gs.shouldTriggerStarterPack, "no trigger before 50 coins")

        gs.coinBalance = 49
        XCTAssertFalse(gs.shouldTriggerStarterPack, "49 is below the threshold")

        gs.coinBalance = 50
        XCTAssertTrue(gs.shouldTriggerStarterPack, "fires at exactly 50")

        // Presenting the sheet stamps shownAt — the trigger never re-arms.
        gs.starterPackShownAt = Date()
        XCTAssertFalse(gs.shouldTriggerStarterPack, "one-shot: shownAt disarms it")
    }

    func testStarterPackTrigger_suppressedWhenClaimedDismissedOrCollectionOwned() {
        let gs = makeGameState()
        gs.coinBalance = 100

        gs.starterPackClaimed = true
        XCTAssertFalse(gs.shouldTriggerStarterPack, "delivered players never see it")
        gs.starterPackClaimed = false
        XCTAssertTrue(gs.shouldTriggerStarterPack)

        gs.starterPackDismissed = true
        XCTAssertFalse(gs.shouldTriggerStarterPack, "\"No thanks\" is a permanent opt-out")
        gs.starterPackDismissed = false
        XCTAssertTrue(gs.shouldTriggerStarterPack)

        guard let aurora = CosmeticBundle.catalogue.first(where: { $0.id == "aurora" }) else {
            return XCTFail("expected the \"aurora\" bundle in the catalogue")
        }
        aurora.grantContents(to: gs)
        XCTAssertFalse(gs.shouldTriggerStarterPack,
                       "owning the complete collection suppresses the offer")
    }

    /// The load-bearing split behind the Ask-to-Buy flow: "No thanks" sets
    /// `dismissed` (offer UI opt-out) but must NOT set `claimed` (the coin
    /// gate) — a pending purchase approved after a dismissal still delivers
    /// its 500 coins.
    func testStarterPackDismissal_doesNotBlockCoinDelivery() {
        let gs = makeGameState()
        gs.starterPackDismissed = true
        XCTAssertFalse(gs.starterPackClaimed,
                       "dismissal must leave the coin-delivery gate open")
        XCTAssertFalse(gs.starterPackOfferActive)
        XCTAssertFalse(gs.shouldTriggerStarterPack)
    }

    /// The 48-hour window: active right after first show, dead after 48h,
    /// and `starterPackSecondsRemaining` counts down and clamps at 0.
    func testStarterPackWindow_fortyEightHourCountdown() {
        let gs = makeGameState()
        XCTAssertFalse(gs.starterPackOfferActive, "inactive before first show")
        XCTAssertEqual(gs.starterPackSecondsRemaining, 0, "no countdown before first show")

        // Mid-window: shown 47 hours ago.
        gs.starterPackShownAt = Date(timeIntervalSinceNow: -47 * 3_600)
        XCTAssertTrue(gs.starterPackOfferActive, "window still open at 47h")
        XCTAssertEqual(gs.starterPackSecondsRemaining, 3_600, accuracy: 5,
                       "about one hour left at 47h")

        // Expired: shown 49 hours ago.
        gs.starterPackShownAt = Date(timeIntervalSinceNow: -49 * 3_600)
        XCTAssertFalse(gs.starterPackOfferActive, "window closed after 48h")
        XCTAssertEqual(gs.starterPackSecondsRemaining, 0, "remaining clamps at 0")
    }

    func testStarterPackWindow_closesOnClaimOrCollectionCompletion() {
        let gs = makeGameState()
        gs.starterPackShownAt = Date()   // window just opened
        XCTAssertTrue(gs.starterPackOfferActive)

        // Delivery closes the window …
        gs.starterPackClaimed = true
        XCTAssertFalse(gs.starterPackOfferActive, "claimed closes the window")
        gs.starterPackClaimed = false
        XCTAssertTrue(gs.starterPackOfferActive, "re-armed")

        // … so does "No thanks" …
        gs.starterPackDismissed = true
        XCTAssertFalse(gs.starterPackOfferActive, "dismissed closes the window")
        gs.starterPackDismissed = false
        XCTAssertTrue(gs.starterPackOfferActive, "re-armed for the completion check")

        // … and so does coin-completing the Aurora collection mid-window.
        guard let aurora = CosmeticBundle.catalogue.first(where: { $0.id == "aurora" }) else {
            return XCTFail("expected the \"aurora\" bundle in the catalogue")
        }
        aurora.grantContents(to: gs)
        XCTAssertFalse(gs.starterPackOfferActive,
                       "mid-window collection completion suppresses the offer")
    }
}

// ---------------------------------------------------------------------------
// LevelOverridesTests — guardrail for the JSON single-source-of-truth.
//
// The climb's hand-crafted levels now live in the bundled LevelOverrides.json
// (authored in Marble Mapper); the Swift `handCrafted` array is intentionally
// empty.  LevelOverrideStore.loadBundled() fails SILENTLY to [:] on a missing,
// truncated, or corrupt file — which would quietly regress every authored level
// to the procedural generator with no crash and no error.  These tests fail
// loudly instead, so a bad export can't ship.  (Runs in-process against the
// app bundle: the test target is app-hosted, so Bundle.main is RollAlong.app.)
// ---------------------------------------------------------------------------
final class LevelOverridesTests: XCTestCase {

    /// The bundled overrides must cover a contiguous 1...N authored range
    /// (currently 1...100).  A gap means a level silently falls through to the
    /// generator instead of its designed layout.
    func testBundledClimbOverridesCoverAuthoredRange() {
        let overrides = LevelLayout.overrides
        XCTAssertFalse(overrides.isEmpty,
                       "LevelOverrides.json decoded to empty — bundled file missing/corrupt? "
                       + "With handCrafted retired, every climb level would regress to generated().")
        let keys = Set(overrides.keys)
        let maxLevel = keys.max() ?? 0
        XCTAssertGreaterThanOrEqual(maxLevel, 100,
                                    "Authored climb range shrank below 100 levels (max key = \(maxLevel)).")
        let missing = (1...maxLevel).filter { !keys.contains($0) }
        XCTAssertTrue(missing.isEmpty,
                      "LevelOverrides.json has gaps in the authored range: \(Array(missing.prefix(10)))")
    }

    /// A decoded override must carry real content (the migration/publish wrote a
    /// usable layout, not an empty husk).  L1 = 1 designed hole + 2 side-walls
    /// auto-added on decode, plus its 3 coins.
    func testDecodedClimbOverrideHasContent() {
        guard let l1 = LevelLayout.overrides[1] else { return XCTFail("missing level 1") }
        XCTAssertEqual(l1.coins.count, 3, "L1 should decode 3 coins")
        XCTAssertGreaterThanOrEqual(l1.holeRects.count, 1, "L1 should decode holes (designed + side-walls)")
    }

    /// The migration preserved the `verified` flag exactly: levels 1-10 were
    /// authored `verified: true`, all later levels `false`.
    func testVerifiedFlagPreservedThroughMigration() {
        XCTAssertEqual(LevelLayout.overrides[1]?.verified, true, "L1 should be verified")
        XCTAssertEqual(LevelLayout.overrides[10]?.verified, true, "L10 should be verified")
        XCTAssertEqual(LevelLayout.overrides[50]?.verified, false, "L50 should not be verified")
    }
}

// ---------------------------------------------------------------------------
// CoinBankingGateTests — which modes may consult the climb's banked-coin set.
//
// `gameState.currentLevel` is always the player's parked CLIMB level, even
// while a Challenge Track or the Daily Challenge is being played.  BallGame's
// coin masking (dim + skip-pickup of already-banked indices) must therefore
// apply ONLY on the main climb — every other progression generates its own
// maps, banks nothing, and masking against the parked level would hide coins
// the player never collected there.  Regression: track levels silently lost
// whichever coin indices happened to be banked on the parked climb level.
// ---------------------------------------------------------------------------
final class CoinBankingGateTests: XCTestCase {

    /// Enum-level truth table: only `.mainClimb` banks pickup coins.
    func testBanksPickupCoins_onlyMainClimb() {
        XCTAssertTrue(ProgressionKind.mainClimb.banksPickupCoins)
        XCTAssertFalse(ProgressionKind.challengeTrack("frozen-peaks").banksPickupCoins)
        XCTAssertFalse(ProgressionKind.oneShot.banksPickupCoins)
        XCTAssertFalse(ProgressionKind.none.banksPickupCoins)
    }

    /// Registry sweep: the climb is the ONLY registered mode that banks.
    /// Guards against a future mode accidentally shipping `.mainClimb`
    /// progression (which would let it mask/bank against the parked level).
    func testRegistry_onlyTheClimbBanksPickupCoins() {
        for (mode, _) in GameModeCatalogue.registry {
            if mode.id == GameModeCatalogue.climb.id {
                XCTAssertTrue(mode.progression.banksPickupCoins,
                              "the climb must bank pickup coins")
            } else {
                XCTAssertFalse(mode.progression.banksPickupCoins,
                               "\(mode.id) must NOT consult the climb's banked coins")
            }
        }
    }

    /// The concrete regression scenario: coins banked on the parked climb
    /// level exist in GameState, but a track/daily mode's progression says
    /// not to consult them — so track maps present their full coin set.
    func testBankedClimbCoins_doNotLeakIntoNonClimbModes() {
        let suite = "CoinBankingGateTests.isolated"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let gs = GameState(defaults: defaults)
        gs.bankCoins(for: gs.currentLevel, indices: [0, 1, 2])
        XCTAssertEqual(gs.coinsCollected(for: gs.currentLevel), [0, 1, 2])

        guard let track = GameModeCatalogue.challengeTracks.first else {
            return XCTFail("at least one Challenge Track should be registered")
        }
        XCTAssertFalse(track.progression.banksPickupCoins,
                       "a track must ignore the parked climb level's banked coins")
        XCTAssertFalse(DailyChallengeMode().progression.banksPickupCoins,
                       "the daily gauntlet must ignore the parked climb level's banked coins")
    }
}

// ---------------------------------------------------------------------------
// ClimbRecordGateTests — which modes may write the climb's per-level records.
//
// `gameState.currentLevel` is always the player's parked CLIMB level, even
// while the Daily Challenge (or a Challenge Track) is being played.
// handleLevelClear's record-keeping tail — recordResult (stars / best time /
// unlock frontier), the first-clear coin bonus, and the "level_complete"
// analytics event — must therefore run ONLY on the main climb.  Regression:
// clearing a Daily Challenge sub-level fell through that tail and stamped a
// 3-star best + bogus best-time onto the parked climb level (daily layouts
// carry sentinel 999 s gold times, so any clear "beat gold"), paid its
// first-clear bonus, and — when the player was parked on their frontier —
// unlocked the next climb level without it ever being cleared.
// ---------------------------------------------------------------------------
final class ClimbRecordGateTests: XCTestCase {

    /// Enum-level truth table: only `.mainClimb` records climb results.
    func testRecordsClimbResult_onlyMainClimb() {
        XCTAssertTrue(ProgressionKind.mainClimb.recordsClimbResult)
        XCTAssertFalse(ProgressionKind.challengeTrack("frozen-peaks").recordsClimbResult)
        XCTAssertFalse(ProgressionKind.oneShot.recordsClimbResult)
        XCTAssertFalse(ProgressionKind.none.recordsClimbResult)
    }

    /// Registry sweep: the climb is the ONLY registered mode whose clears may
    /// write climb records.  Guards against a future mode accidentally
    /// shipping `.mainClimb` progression and silently polluting the parked
    /// level's stars / times / unlock frontier.
    func testRegistry_onlyTheClimbRecordsClimbResults() {
        for (mode, _) in GameModeCatalogue.registry {
            if mode.id == GameModeCatalogue.climb.id {
                XCTAssertTrue(mode.progression.recordsClimbResult,
                              "the climb must record climb results")
            } else {
                XCTAssertFalse(mode.progression.recordsClimbResult,
                               "\(mode.id) must NOT write the parked climb level's records")
            }
        }
    }

    /// The concrete regression scenario: `recordResult` against the parked
    /// frontier level is exactly the pollution a daily sub-level clear used
    /// to cause — a fake 3-star best, a bogus best-time, and an unearned
    /// unlock.  The daily's progression must say "hands off" so
    /// handleLevelClear never makes that call for it.
    func testDailyClear_mustNotRecordAgainstParkedClimbLevel() {
        let suite = "ClimbRecordGateTests.isolated"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let gs = GameState(defaults: defaults)
        let parked = gs.currentLevel
        XCTAssertNil(gs.time(for: parked), "fresh save — the parked level has no best yet")
        let frontierBefore = gs.highestUnlocked

        // What the old fall-through did on a daily sub-level clear:
        gs.recordResult(level: parked, stars: 3, time: 4.2, coinIndices: [])
        XCTAssertEqual(gs.stars(for: parked), 3, "recordResult stamps a fake 3-star best")
        XCTAssertEqual(gs.time(for: parked), 4.2, "recordResult stamps a bogus best-time")
        XCTAssertGreaterThan(gs.highestUnlocked, frontierBefore,
                             "recordResult on the frontier unlocks the next climb level")

        // The gate that keeps handleLevelClear from ever making that call
        // outside the climb:
        XCTAssertFalse(DailyChallengeMode().progression.recordsClimbResult,
                       "the daily gauntlet must never write climb records")
    }
}
