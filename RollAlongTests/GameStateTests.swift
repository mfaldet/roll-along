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

    // 2026-11 rebalance, round 3: competitive games pay 1/2/3 coins by
    // difficulty (any result), solo games pay none, a win earns a ticket, and
    // Gold Rush costs 5 tickets (`CoinPayouts`).

    func testGoldRushCostsFiveTicketsAndTheBoostTwoRounds() {
        XCTAssertEqual(CoinPayouts.goldRushTicketCost, 5)
        XCTAssertEqual(CoinPayouts.goldRushBoostTicketCost, 10)
        XCTAssertEqual(CoinPayouts.ticketsPerWin, 1)
        XCTAssertEqual(CoinPayouts.minigameMax, 3)
        // Five wins buy exactly one round.
        let gs = makeGameState()
        let start = gs.tickets
        _ = gs.spendTickets(start)
        for _ in 0..<5 {
            gs.recordMinigameResult(modeID: "sumo", difficulty: .normal, won: true, score: 0, placement: 1)
        }
        XCTAssertEqual(gs.tickets, CoinPayouts.goldRushTicketCost)
        XCTAssertTrue(gs.spendTickets(CoinPayouts.goldRushTicketCost))
        XCTAssertEqual(gs.tickets, 0)
    }

    func testCompetitivePayout_byDifficultyWhateverTheResult() {
        XCTAssertEqual(CoinPayouts.competitiveCoins(.easy),   1)
        XCTAssertEqual(CoinPayouts.competitiveCoins(.normal), 2)
        XCTAssertEqual(CoinPayouts.competitiveCoins(.hard),   3)
        // A win, a loss, a draw and every placement pay the same per difficulty.
        for d in MinigameDifficulty.allCases {
            let expected = CoinPayouts.competitiveCoins(d)
            for id in ["snake", "sumo", "paintball", "goldrush", "marblecup", "koth"] {
                for place in [nil, 1, 2, 3, 4] as [Int?] {
                    for won in [true, false] {
                        XCTAssertEqual(CoinPayouts.competitive(modeID: id, won: won,
                                                               placement: place, difficulty: d),
                                       expected, "\(id) \(d) \(String(describing: place)) won=\(won)")
                    }
                }
                XCTAssertEqual(CoinPayouts.competitive(modeID: id, won: false, draw: true,
                                                       placement: nil, difficulty: d), expected)
            }
        }
    }

    func testSoloMinigamesPayNoCoins() {
        for m in [0, 1, 59, 60, 150, 10_000] { XCTAssertEqual(CoinPayouts.rollUp(meters: m), 0) }
        for c in [0, 1, 5, 12, 300] { XCTAssertEqual(CoinPayouts.disco(crossings: c), 0) }
        for z in [0, 59, 60, 60 * 30] { XCTAssertEqual(CoinPayouts.zen(seconds: z), 0) }
        XCTAssertEqual(CoinPayouts.rollOutClear, 0)
        XCTAssertEqual(GameState.minigameBestBonus, 0, "a new best no longer pays a bonus")
    }

    func testZenGardenTimePaysNoCoins() {
        let gs = makeGameState()
        let before = gs.coinBalance
        gs.addZenSeconds(60 * 10)
        XCTAssertEqual(gs.coinBalance, before, "Zen Garden is a solo game: no coins")
    }

    func testRecordMinigameResult_loss_countsAttemptAndPaysTheTable() {
        let gs = makeGameState()
        gs.coinBalance = 0
        let ticketsBefore = gs.tickets
        let paid = gs.recordMinigameResult(modeID: "snake", difficulty: .hard,
                                           won: false, score: 0, placement: 4)
        XCTAssertEqual(paid, 3, "a Hard game pays 3, win or lose")
        XCTAssertEqual(gs.coinBalance, 3)
        XCTAssertEqual(gs.tickets, ticketsBefore, "a loss earns no ticket")
        // A draw earns no ticket either.
        _ = gs.recordMinigameResult(modeID: "marblecup", difficulty: .normal,
                                    won: false, score: 0, draw: true)
        XCTAssertEqual(gs.tickets, ticketsBefore, "a draw earns no ticket")
        XCTAssertEqual(gs.minigameDifficultyPlays["snake|hard"], 1)
        XCTAssertNil(gs.minigameDifficultyWins["snake|hard"], "a loss is not a win")
        XCTAssertEqual(gs.minigameWins["snake"] ?? 0, 0, "lifetime win tally untouched on a loss")
        XCTAssertEqual(gs.minigameSuccessRate("snake", .hard), 0.0)
    }

    func testRecordMinigameResult_win_countsWinPaysTheTableAndATicket() {
        let gs = makeGameState()
        gs.coinBalance = 0
        let ticketsBefore = gs.tickets
        let paid = gs.recordMinigameResult(modeID: "sumo", difficulty: .easy,
                                           won: true, score: 0, placement: 1)
        XCTAssertEqual(paid, 1, "an Easy game pays 1, win or lose")
        XCTAssertEqual(gs.coinBalance, 1)
        XCTAssertEqual(gs.tickets, ticketsBefore + 1, "a win still earns 1 ticket")
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
    /// top coin pack's 10,000 (App Store Connect amount).  If maxSingleAward
    /// falls behind rewardCoins, a $49.99 purchase silently short-delivers.
    func testAddCoins_topCoinPackGrant_isNotClamped() {
        let gs = makeGameState()
        gs.coinBalance = 0
        let topGrant = StoreKitManager.ProductID.coins10000.rewardCoins
        XCTAssertEqual(topGrant, 10_000, "top pack grants 10,000 coins")
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
        // addLives feeds the purchased reserve queue (ad / gift / IAP lives),
        // not the regen bar, so the spendable TOTAL is what grows.
        XCTAssertEqual(gs.totalLives, 6)
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

    /// The one-shot trigger: fires only once coinBalance reaches the
    /// threshold, with the offer never shown, never claimed, and the Aurora
    /// collection incomplete.
    func testStarterPackTrigger_firesOnceAtThreshold() {
        let threshold = GameState.starterPackTriggerCoins
        let gs = makeGameState()
        XCTAssertFalse(gs.shouldTriggerStarterPack, "no trigger at zero coins")

        gs.coinBalance = threshold - 1
        XCTAssertFalse(gs.shouldTriggerStarterPack, "one below the threshold does not fire")

        gs.coinBalance = threshold
        XCTAssertTrue(gs.shouldTriggerStarterPack, "fires at exactly the threshold")

        // Presenting the sheet stamps shownAt — the trigger never re-arms.
        gs.starterPackShownAt = Date()
        XCTAssertFalse(gs.shouldTriggerStarterPack, "one-shot: shownAt disarms it")
    }

    func testStarterPackTrigger_suppressedWhenClaimedDismissedOrItemsOwned() {
        let gs = makeGameState()
        gs.coinBalance = GameState.starterPackTriggerCoins

        gs.starterPackClaimed = true
        XCTAssertFalse(gs.shouldTriggerStarterPack, "delivered players never see it")
        gs.starterPackClaimed = false
        XCTAssertTrue(gs.shouldTriggerStarterPack)

        gs.starterPackDismissed = true
        XCTAssertFalse(gs.shouldTriggerStarterPack, "\"No thanks\" is a permanent opt-out")
        gs.starterPackDismissed = false
        XCTAssertTrue(gs.shouldTriggerStarterPack)

        // Owning only some of the three pack items keeps the offer …
        gs.grant(BallSkin.aurora)
        gs.grant(TrailColor.aurora)
        XCTAssertTrue(gs.shouldTriggerStarterPack, "two of three items: still offered")
        // … owning all three (ball, trail, boundary) suppresses it.
        gs.grant(Boundary.aurora)
        XCTAssertFalse(gs.shouldTriggerStarterPack,
                       "owning the Aurora ball, trail and boundary suppresses the offer")
    }

    /// Starter Pack (Option B): the Aurora ball, trail and boundary plus 500
    /// coins.  The items are free-granted (Sell Back refunds nothing), the
    /// grant is NOT recorded as an owned collection (Aurora stays on sale and
    /// "collections completed" is not inflated), and the coin reward is 500.
    /// @MainActor: `StarterPackSheet` is a View, so its statics are main-actor.
    @MainActor
    func testStarterPack_contentsAndPartialGrant() {
        let p = GameState.starterPackContents
        XCTAssertEqual(p.balls, [.aurora])
        XCTAssertEqual(p.trails, [.aurora])
        XCTAssertEqual(p.boundaries, [.aurora])
        XCTAssertTrue(p.goals.isEmpty && p.floors.isEmpty && p.pits.isEmpty && p.music.isEmpty)
        XCTAssertNil(CosmeticBundle.catalogue.first(where: { $0.id == p.id }),
                     "the Starter Pack's contents are not a catalogue collection")
        XCTAssertEqual(StoreKitManager.ProductID.starterPack.rewardCoins, 500)
        XCTAssertEqual(StarterPackSheet.itemsShopValue, 4_500,
                       "the offer sheet and the docs say the three items are worth 4,500 coins")

        let gs = makeGameState()
        gs.coinBalance = 0
        let completedBefore = gs.completedBundleIDs
        gs.grantBundleFree(p, recordAsOwnedBundle: false)
        XCTAssertTrue(gs.ownsStarterPackItems)
        XCTAssertFalse(gs.ownedBundles.contains(p.id), "partial grant is not an owned bundle")
        XCTAssertEqual(gs.completedBundleIDs, completedBefore,
                       "three Aurora items do not complete the Aurora collection")
        XCTAssertEqual(gs.coinLiquidationPreview().coins, 0,
                       "Starter Pack items are never refundable by Sell Back")
        gs.liquidateCoinCosmetics()
        XCTAssertTrue(gs.isOwned(BallSkin.aurora), "kept after Sell Back")
        XCTAssertEqual(gs.coinBalance, 0, "Sell Back minted coins from the $1.99 pack")
    }

    /// The load-bearing split behind the Ask-to-Buy flow: "No thanks" sets
    /// `dismissed` (offer UI opt-out) but must NOT set `claimed` (the coin
    /// gate) — a pending purchase approved after a dismissal still delivers
    /// its coins.
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

    func testStarterPackWindow_closesOnClaimOrItemsOwned() {
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

        // … and so does coin-buying all three pack items mid-window.
        GameState.starterPackContents.grantContents(to: gs)
        XCTAssertFalse(gs.starterPackOfferActive,
                       "owning the ball, trail and boundary mid-window suppresses the offer")
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

// ---------------------------------------------------------------------------
// MinigameAICalibrationTests — headless win-rate calibration harness.
//
// Runs the PRODUCTION Gold Rush simulation (GoldRushEngine.tick(), the exact
// code GoldRushView drives every frame) against a scripted "median-skill"
// player at each MinigameDifficulty, and reports simulated win rates next to
// `MinigameDifficulty.targetWinRate` (0.70 / 0.50 / 0.30).
//
// WHAT IS REAL vs WHAT IS MODELED — read before trusting a number:
//   • REAL: all opponent behavior (the `OpponentTuning` limits: reaction
//     delay, aiming error, mistakes, effort, top speed; bully charges), all
//     physics, coins, spills, round timing.
//     Zero divergence from the shipped game — it IS the shipped tick.
//   • MODELED: the player. In the real game the player is a human tilting a
//     phone; here it's `MedianPlayer` (reaction latency ~0.25 s, ~40% tilt,
//     ±0.30 rad aim error, opportunistic-but-imperfect charge use).
//
// Consequence: ABSOLUTE win rates from this harness are only as honest as the
// player model, so they must NOT be used alone to retune `OpponentTuning`
// against targetWinRate — live telemetry
// (minigame_result: game/difficulty/won) is the ground truth for absolutes.
// What the harness IS good for:
//   • the difficulty SPREAD (easy must beat hard by a wide margin),
//   • knob sensitivity (re-run after touching the scale tables or engine
//     tunables and compare deltas before shipping),
//   • regression safety (a physics/AI change that flattens the spread fails
//     the sanity assertion below).
//
// Gold Rush only: it is the one mode with the headless engine pattern.  The
// other competitive modes (KotH, PaintBall, MarbleCup, Sumo) run their tick
// inside SwiftUI @State and cannot be simulated without an engine extraction.
// ---------------------------------------------------------------------------

final class MinigameAICalibrationTests: XCTestCase {

    /// Same fixed reference arena as PerformanceTests (iPhone-class portrait).
    private let arena = CGSize(width: 390, height: 844)

    /// Rounds simulated per difficulty.  At n=200 the standard error of a
    /// mid-range rate is ~3.5 points — plenty for spread/sensitivity checks.
    private let roundsPerCell = 200

    // MARK: - Scripted median-skill player

    /// A deliberately imperfect tilt player:
    ///  • Decides only every `reactionTicks` (~0.25 s) — between decisions it
    ///    holds the previous tilt, like a human committed to a lean.
    ///  • Aims at the nearest grabbable coin with a fresh ±`aimError` rad
    ///    mistake per decision, at ~`tiltMagnitude` of full tilt.  0.40 is a
    ///    comfortable 20 to 30 degree lean — what real players do.  (The
    ///    earlier 0.75 was far harder than people tilt and made every
    ///    difficulty look easier than it is.)
    ///  • Uses the charge mechanic opportunistically: when it's off cooldown
    ///    and a coin-carrying rival is close, it re-aims and taps — but only
    ///    half the time it notices (humans miss windows).
    private struct MedianPlayer {
        let reactionTicks = 15              // ~0.25 s @ 60 fps
        let tiltMagnitude: CGFloat = 0.40
        let aimError: CGFloat = 0.30        // radians, resampled per decision
        let chargeRange: CGFloat = 140
        private var input = CGVector.zero
        private var nextDecision = 0

        mutating func drive(_ engine: GoldRushEngine, tick: Int) {
            defer { engine.playerInput = input }
            guard tick >= nextDecision,
                  let me = engine.racers.first(where: { $0.isPlayer }) else { return }
            nextDecision = tick + reactionTicks

            // Opportunistic charge: nearest rival worth ramming, in range.
            if engine.playerChargeReady, Bool.random(),
               let victim = engine.racers
                    .filter({ !$0.isPlayer && $0.score >= 2 })
                    .min(by: { dist($0.pos, me.pos) < dist($1.pos, me.pos) }),
               dist(victim.pos, me.pos) < chargeRange {
                input = aimed(from: me.pos, at: victim.pos)
                engine.playerInput = input
                engine.chargePlayer()
                return
            }

            // Otherwise chase the nearest coin this player may actually grab
            // (own just-spilled coins are briefly off-limits and a human
            // wouldn't hover over them); drift to centre when the board's bare.
            let coin = engine.coins
                .filter { !($0.ignoreRacer == me.id && engine.localTick < $0.ignoreUntil) }
                .min { dist($0.pos, me.pos) < dist($1.pos, me.pos) }
            input = aimed(from: me.pos, at: coin?.pos ?? engine.center)
        }

        private func aimed(from: CGPoint, at target: CGPoint) -> CGVector {
            let ang = atan2(target.y - from.y, target.x - from.x)
                    + CGFloat.random(in: -aimError...aimError)
            return CGVector(dx: cos(ang) * tiltMagnitude,
                            dy: sin(ang) * tiltMagnitude)
        }

        private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            hypot(a.x - b.x, a.y - b.y)
        }
    }

    // MARK: - One headless round

    /// What one round produced.
    private struct RoundResult {
        let won: Bool
        let playerCoins: Int
        let bestOpponentCoins: Int
    }

    /// Exactly what GoldRushView's per-frame driver does, minus rendering:
    /// set the difficulty, feed `playerInput` (the view feeds the phone's tilt
    /// through the same property), fire `chargePlayer()` for a tap, and tick
    /// the REAL engine to round end.  This is the only simulation of this
    /// game; there is no separate copy of the rules.
    private func runRound(difficulty: MinigameDifficulty, map: Int) -> RoundResult {
        let engine = GoldRushEngine(arena: arena)
        engine.loadMap(index: map)
        engine.difficulty = difficulty      // opponents read OpponentTuning for it
        engine.startRound()

        var player = MedianPlayer()
        var tick = 0
        while !engine.isOver {
            player.drive(engine, tick: tick)
            engine.tick()
            tick += 1
            if tick > 4_000 {                    // 60 s round = 3_600 ticks
                XCTFail("round failed to end — engine round-clock regression")
                return RoundResult(won: false, playerCoins: 0, bestOpponentCoins: 0)
            }
        }
        return RoundResult(won: engine.playerWon,
                           playerCoins: engine.playerScore,
                           bestOpponentCoins: engine.bestRivalScore)
    }

    // MARK: - The calibration report

    /// Cells measured so far.  XCTest builds a fresh instance per test method,
    /// so the three per-difficulty tests below share results through this
    /// static; the hard cell (alphabetically last selector, so it runs last)
    /// closes with the cross-difficulty spread check.  One test per difficulty
    /// keeps each under ~25 s and isolates a simulator hiccup to one cell.
    private static var measured: [MinigameDifficulty: Double] = [:]

    private func measureCell(_ difficulty: MinigameDifficulty) {
        var wins = 0
        var playerCoins = 0
        var bestOpponentCoins = 0
        for round in 0..<roundsPerCell {
            // Cycle the shipped maps so no single layout dominates.
            let result = runRound(difficulty: difficulty,
                                  map: round % max(1, GoldRushMaps.maps.count))
            if result.won { wins += 1 }
            playerCoins += result.playerCoins
            bestOpponentCoins += result.bestOpponentCoins
        }
        let rate = Double(wins) / Double(roundsPerCell)
        Self.measured[difficulty] = rate
        // The report — read it from the test log; this is the harness output.
        // The scripted player always knows where the nearest coin is and
        // never tires, so read these as a comparison BETWEEN difficulties,
        // not as what a person will score.
        print(String(format: "[AI-CALIBRATION] Smash and Grab %@ (tuning v%d) rounds=%d  scripted-player win rate %.3f  mean player coins %.1f  mean best-opponent coins %.1f",
                     difficulty.rawValue, OpponentTuning.version, roundsPerCell, rate,
                     Double(playerCoins) / Double(roundsPerCell),
                     Double(bestOpponentCoins) / Double(roundsPerCell)))
    }

    func testWinRate_1_easy()   { measureCell(.easy) }
    func testWinRate_2_normal() { measureCell(.normal) }

    func testWinRate_3_hard_thenSpread() {
        measureCell(.hard)
        // When invoked in isolation the other cells are absent — report only.
        guard let easy = Self.measured[.easy],
              let normal = Self.measured[.normal],
              let hard = Self.measured[.hard] else { return }

        print(String(format: "[AI-CALIBRATION] Smash and Grab summary (tuning v%d) scripted-player win rate: easy %.3f normal %.3f hard %.3f",
                     OpponentTuning.version, easy, normal, hard))

        // Deliberately LOOSE assertions: the harness measures, real results
        // judge.  Only the difficulty ORDERING is gated, with a wide tolerance
        // (n=200 has about ±7 points of noise per cell).
        XCTAssertGreaterThan(easy, normal - 0.08,
            "easy should not simulate clearly harder than normal")
        XCTAssertGreaterThan(normal, hard - 0.08,
            "normal should not simulate clearly harder than hard")
        XCTAssertGreaterThan(easy, hard - 0.05,
            "difficulty order reversed: easy \(easy) vs hard \(hard)")
    }
}

// ===========================================================================
// OpponentTuning / OpponentBrain — the shared human limits.
// ===========================================================================
final class OpponentTuningTests: XCTestCase {

    func testTableGetsHarderWithDifficulty() {
        let e = OpponentTuning.easy, n = OpponentTuning.normal, h = OpponentTuning.hard
        XCTAssertGreaterThan(e.reactionDelaySeconds, n.reactionDelaySeconds)
        XCTAssertGreaterThan(n.reactionDelaySeconds, h.reactionDelaySeconds)
        XCTAssertGreaterThan(e.aimErrorDegrees, n.aimErrorDegrees)
        XCTAssertGreaterThan(n.aimErrorDegrees, h.aimErrorDegrees)
        XCTAssertLessThan(e.mistakeEverySeconds, n.mistakeEverySeconds)
        XCTAssertLessThan(n.mistakeEverySeconds, h.mistakeEverySeconds)
        XCTAssertLessThan(e.effort, n.effort)
        XCTAssertLessThan(n.effort, h.effort)
        XCTAssertLessThanOrEqual(e.kothContenders, n.kothContenders)
        XCTAssertLessThanOrEqual(n.kothContenders, h.kothContenders)
    }

    func testPerceiveReturnsThePositionOneReactionDelayAgo() {
        var brain = OpponentBrain(difficulty: .normal, seed: 7)
        let delay = brain.delayTicks
        XCTAssertEqual(delay, Int((OpponentTuning.normal.reactionDelaySeconds * 60).rounded()))
        XCTAssertGreaterThan(delay, 0)
        var last = CGPoint.zero
        for t in 0..<60 {
            last = brain.perceive(CGPoint(x: CGFloat(t), y: 0))
        }
        XCTAssertEqual(last.x, CGFloat(59 - delay), accuracy: 0.001)
        // Before a full delay has passed it sees the first position.
        var fresh = OpponentBrain(difficulty: .normal, seed: 7)
        XCTAssertEqual(fresh.perceive(CGPoint(x: 5, y: 5)).x, 5, accuracy: 0.001)
    }

    func testAimErrorStaysInsideTheLimitAndMistakesHappen() {
        var brain = OpponentBrain(difficulty: .easy, seed: 42)
        let limit = CGFloat(OpponentTuning.easy.aimErrorDegrees * Double.pi / 180)
        var mistakes = 0
        var mistakeTicks = 0
        for _ in 0..<(60 * 60) {                          // one minute
            if brain.advance() { mistakes += 1 }
            if brain.isMistaking { mistakeTicks += 1 }
            XCTAssertLessThanOrEqual(abs(brain.aimError), limit + 0.0001)
        }
        // The middle Easy opponent: about every 3.5 s plus the 1.1 s it lasts
        // → roughly 10 to 19 a minute.
        XCTAssertGreaterThan(mistakes, 6)
        XCTAssertLessThan(mistakes, 26)
        XCTAssertGreaterThan(mistakeTicks, 0)
    }

    func testPushUsesTheEffortShare() {
        var brain = OpponentBrain(difficulty: .hard, seed: 3)
        brain.advance()
        let v = brain.push(from: .zero, toward: CGPoint(x: 100, y: 0), fullPush: 1_000)
        XCTAssertEqual(hypot(v.dx, v.dy), CGFloat(1_000 * OpponentTuning.hard.effort), accuracy: 0.5)
    }

    /// The three difficulties must not overlap: the weakest Hard opponent is
    /// still stronger than the strongest Normal one, and likewise for Easy.
    func testDifficultyRangesDoNotOverlap() {
        let bands = [OpponentTuning.easyBand, OpponentTuning.normalBand, OpponentTuning.hardBand]
        for band in bands {
            XCTAssertGreaterThan(band.clumsy.reactionDelaySeconds, band.sharp.reactionDelaySeconds)
            XCTAssertGreaterThan(band.clumsy.aimErrorDegrees, band.sharp.aimErrorDegrees)
            XCTAssertLessThan(band.clumsy.mistakeEverySeconds, band.sharp.mistakeEverySeconds)
            XCTAssertLessThan(band.clumsy.effort, band.sharp.effort)
        }
        for (weaker, stronger) in zip(bands, bands.dropFirst()) {
            XCTAssertGreaterThan(weaker.sharp.reactionDelaySeconds, stronger.clumsy.reactionDelaySeconds)
            XCTAssertGreaterThan(weaker.sharp.aimErrorDegrees, stronger.clumsy.aimErrorDegrees)
            XCTAssertLessThan(weaker.sharp.mistakeEverySeconds, stronger.clumsy.mistakeEverySeconds)
            XCTAssertLessThan(weaker.sharp.effort, stronger.clumsy.effort)
            XCTAssertLessThan(weaker.sharp.smashGrabTopSpeed, stronger.clumsy.smashGrabTopSpeed)
            XCTAssertLessThan(weaker.sharp.sumoShove, stronger.clumsy.sumoShove)
        }
    }

    /// Each opponent draws its own skill: three opponents are one from the
    /// bottom third, one from the middle, one from the top.
    func testDealtSkillsAreSpreadAcrossTheRange() {
        for seed in UInt64(1)...40 {
            let skills = OpponentTuning.dealSkills(3, seed: seed).sorted()
            XCTAssertEqual(skills.count, 3)
            XCTAssertLessThan(skills[0], 1.0 / 3.0)
            XCTAssertGreaterThanOrEqual(skills[1], 1.0 / 3.0)
            XCTAssertLessThan(skills[1], 2.0 / 3.0)
            XCTAssertGreaterThanOrEqual(skills[2], 2.0 / 3.0)
            XCTAssertLessThanOrEqual(skills[2], 1.0)
        }
        XCTAssertEqual(OpponentTuning.dealSkills(3, seed: 5), OpponentTuning.dealSkills(3, seed: 5))
        XCTAssertTrue(OpponentTuning.dealSkills(0).isEmpty)
    }

    /// A sharper opponent of the same difficulty reacts sooner and pushes harder.
    func testSkillMovesAnOpponentInsideItsRange() {
        let clumsy = OpponentBrain(difficulty: .normal, skill: 0, seed: 1)
        let sharp  = OpponentBrain(difficulty: .normal, skill: 1, seed: 1)
        XCTAssertGreaterThan(clumsy.delayTicks, sharp.delayTicks)
        XCTAssertLessThan(clumsy.effort, sharp.effort)
    }

    func testSameSeedGivesTheSameOpponent() {
        var a = OpponentBrain(difficulty: .normal, seed: 99)
        var b = OpponentBrain(difficulty: .normal, seed: 99)
        for _ in 0..<600 {
            XCTAssertEqual(a.advance(), b.advance())
            XCTAssertEqual(a.aimError, b.aimError)
        }
    }

    func testADrawIsNotCountedAsAnAttempt() {
        let suite = "OpponentTuningTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let gs = GameState(defaults: defaults)
        let before = gs.minigameDifficultyPlays["marblecup|normal", default: 0]
        gs.recordMinigameResult(modeID: "marblecup", difficulty: .normal,
                                won: false, score: 1, basePayout: 0, draw: true)
        XCTAssertEqual(gs.minigameDifficultyPlays["marblecup|normal", default: 0], before)
        gs.recordMinigameResult(modeID: "marblecup", difficulty: .normal,
                                won: false, score: 1, basePayout: 0)
        XCTAssertEqual(gs.minigameDifficultyPlays["marblecup|normal", default: 0], before + 1)
    }
}

// ===========================================================================
// Preset names — every player-visible name is assembled from fixed lists.
// ===========================================================================
final class PresetNamesTests: XCTestCase {

    func testWordListsAreCleanAndSized() {
        XCTAssertEqual(PresetNames.adjectives.count, 173)
        XCTAssertEqual(PresetNames.nouns.count, 206)
        XCTAssertEqual(PresetNames.clanAdjectives.count, 221)
        XCTAssertEqual(PresetNames.clanNouns.count, 202)
        for list in [PresetNames.adjectives, PresetNames.nouns,
                     PresetNames.clanAdjectives, PresetNames.clanNouns] {
            XCTAssertEqual(Set(list).count, list.count, "a word appears twice in a list")
            for word in list {
                XCTAssertTrue(word.allSatisfy { $0.isASCII && $0.isLetter }, "\(word): letters only")
                XCTAssertEqual(String(word.prefix(1)), word.prefix(1).uppercased(), "\(word): capitalized")
            }
        }
        // Two words of at most 5 letters each: a nickname is at most 10
        // characters, leaving room for the level badge on in-game name tags.
        for word in PresetNames.adjectives + PresetNames.nouns {
            XCTAssertLessThanOrEqual(word.count, 5, "\(word) is too long for a nickname")
        }
        XCTAssertLessThanOrEqual(PresetNames.nicknameMaxLength, 10)
        // 173 × 206 two-word nicknames.  Nicknames are not unique.
        XCTAssertEqual(PresetNames.adjectives.count * PresetNames.nouns.count, 35_638)
        XCTAssertTrue(Set(PresetNames.adjectives).isDisjoint(with: PresetNames.nouns))
    }

    /// The second words for players and for clans are completely separate:
    /// no word appears in both lists, in singular or plural form ("Wolf" for
    /// players means no "Wolves" for clans).  The default nickname "Roller"
    /// counts as a player word too.
    func testPlayerAndClanSecondWordsShareNoStem() {
        let playerWords = Set(PresetNames.nouns.map { $0.lowercased() }
                              + [PresetNames.defaultNickname.lowercased()])
        for clanWord in PresetNames.clanNouns {
            let clash = Self.singularForms(of: clanWord).intersection(playerWords)
            XCTAssertTrue(clash.isEmpty,
                          "clan word \(clanWord) is a form of the player word(s) \(clash.sorted())")
        }
        // No player word is a plural of another, and no two clan words are
        // forms of one word.
        for list in [PresetNames.nouns, PresetNames.clanNouns] {
            let lowered = Set(list.map { $0.lowercased() })
            for word in list {
                let others = Self.singularForms(of: word).subtracting([word.lowercased()])
                XCTAssertTrue(others.intersection(lowered).isEmpty,
                              "\(word) is a form of another word in the same list")
            }
        }
    }

    /// Every word is letters only and short enough: nickname words at most 5
    /// letters (a nickname at most 10, for in-game name tags) and a clan name
    /// with its longest number within the server's 32 characters.
    func testEveryWordIsLettersOnlyAndWithinTheLengthLimit() {
        for word in PresetNames.adjectives + PresetNames.nouns
                    + PresetNames.clanAdjectives + PresetNames.clanNouns {
            XCTAssertFalse(word.isEmpty)
            XCTAssertTrue(word.allSatisfy { $0.isASCII && $0.isLetter }, "\(word): letters only")
        }
        for word in PresetNames.adjectives + PresetNames.nouns {
            XCTAssertLessThanOrEqual(word.count, 5, word)
        }
        XCTAssertLessThanOrEqual(PresetNames.nicknameMaxLength, 10)
        let longestAdjective = PresetNames.clanAdjectives.map(\.count).max() ?? 0
        let longestNoun = PresetNames.clanNouns.map(\.count).max() ?? 0
        XCTAssertLessThanOrEqual(longestAdjective + 1 + longestNoun + " 999".count, 32)
    }

    /// The singulars a plural could come from, lowercased, including the word
    /// itself: regular endings (-s, -es, -ies to -y, -ves to -f / -fe) plus a
    /// table of irregular plurals.
    private static func singularForms(of word: String) -> Set<String> {
        let w = word.lowercased()
        let irregular: [String: String] = [
            "geese": "goose", "mice": "mouse", "leaves": "leaf", "wolves": "wolf",
            "calves": "calf", "halves": "half", "knives": "knife", "lives": "life",
            "elves": "elf", "shelves": "shelf", "hooves": "hoof", "oases": "oasis",
            "cacti": "cactus", "fungi": "fungus", "children": "child", "teeth": "tooth",
            "feet": "foot", "men": "man", "women": "woman", "oxen": "ox", "people": "person",
        ]
        var forms: Set<String> = [w]
        if let singular = irregular[w] { forms.insert(singular) }
        if w.hasSuffix("ies"), w.count > 4 { forms.insert(String(w.dropLast(3)) + "y") }
        if w.hasSuffix("ves") {
            let base = String(w.dropLast(3))
            forms.formUnion([base + "f", base + "fe", String(w.dropLast())])
        }
        if w.hasSuffix("es") { forms.insert(String(w.dropLast(2))) }
        if w.hasSuffix("s"), !w.hasSuffix("ss") { forms.insert(String(w.dropLast())) }
        return forms
    }

    /// Every nickname the pickers can build reads back as exactly the same
    /// choice, so no two selections produce the same text.
    func testEveryNicknameParsesBackToItsChoice() {
        var seen = Set<String>()
        for a in 0..<PresetNames.adjectives.count {
            for n in 0..<PresetNames.nouns.count {
                let choice = PresetNames.Choice(adjective: a, noun: n, number: 0)
                let name = PresetNames.nickname(choice)
                XCTAssertLessThanOrEqual(name.count, 10, name)
                XCTAssertFalse(name.contains(where: { $0.isNumber }), "\(name): a nickname has no number")
                XCTAssertTrue(seen.insert(name).inserted, "\(name) can be built two ways")
                XCTAssertEqual(PresetNames.parseNickname(name), choice, name)
            }
        }
    }

    func testEveryClanNameParsesBackAndFitsTheServerLimits() {
        for a in 0..<PresetNames.clanAdjectives.count {
            for n in 0..<PresetNames.clanNouns.count {
                let choice = PresetNames.Choice(adjective: a, noun: n, number: 999)
                let name = PresetNames.clanName(choice)
                XCTAssertLessThanOrEqual(name.count, 32, name)
                XCTAssertEqual(PresetNames.parseClanName(name), choice, name)
                let tag = PresetNames.hiddenClanTag(choice)
                XCTAssertTrue((2...5).contains(tag.count), tag)
            }
        }
    }

    func testFreeTextAndBlockedNumbersAreRejected() {
        XCTAssertNil(PresetNames.parseNickname("Mackenzie"))
        XCTAssertNotNil(PresetNames.parseNickname("SwiftComet"))    // two words, no number
        XCTAssertNil(PresetNames.parseNickname("SwiftComet42"))     // a number is no longer part of a nickname
        XCTAssertNil(PresetNames.parseNickname("Swift"))            // one word
        XCTAssertNil(PresetNames.parseNickname("SwiftComets"))      // not a listed second word
        XCTAssertFalse(PresetNames.isValidNickname("SwiftComet42"))
        // A name in the old format keeps showing, as its two words.
        XCTAssertEqual(PresetNames.shownNickname("SwiftComet42"), "SwiftComet")
        XCTAssertEqual(PresetNames.shownNickname("SwiftComet7"), "SwiftComet")
        XCTAssertEqual(PresetNames.shownNickname("SwiftComet"), "SwiftComet")
        XCTAssertEqual(PresetNames.shownNickname("SwiftComet07"), "")    // never a valid old name
        XCTAssertEqual(PresetNames.shownNickname("SwiftComet100"), "")   // never a valid old name
        XCTAssertEqual(PresetNames.shownNickname("SwiftComet69"), "")    // blocked number
        XCTAssertEqual(PresetNames.shownNickname("Mackenzie"), "")
        XCTAssertEqual(PresetNames.shownNickname(PresetNames.defaultNickname), PresetNames.defaultNickname)
        XCTAssertNil(PresetNames.parseClanName("The Stones"))
        XCTAssertNil(PresetNames.parseClanName("Swift Rockets 666")) // blocked number
        XCTAssertNotNil(PresetNames.parseClanName("Swift Rockets 1"))
        // "Comet" is a nickname word, so "Comets" is no longer a clan word.
        XCTAssertNil(PresetNames.parseClanName("Swift Comets 1"))
        XCTAssertFalse(PresetNames.clanNumbers.contains(420))
        XCTAssertTrue(PresetNames.isValidNickname(PresetNames.defaultNickname))
        XCTAssertFalse(PresetNames.isValidClanDescription("anything typed"))
        XCTAssertTrue(PresetNames.isValidClanDescription(""))
    }
}

// MARK: - Disco Ball leaderboard best

/// The Disco Ball board ranks the most crossings in one run on any difficulty;
/// a tie on crossings keeps the run with the faster average crossing.
final class DiscoBoardBestTests: XCTestCase {

    private func makeGameState() -> (GameState, UserDefaults, String) {
        let suite = "DiscoBoardBestTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (GameState(defaults: defaults), defaults, suite)
    }

    /// Each difficulty keeps its own best and its own time: a run on one
    /// difficulty never changes another's.
    func testEachDifficultyKeepsItsOwnBest() {
        let (gs, defaults, suite) = makeGameState()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = gs.recordDiscoResult(bestKey: "discoeasy", crossings: 12, crossingSeconds: 48)
        _ = gs.recordDiscoResult(bestKey: "discohard", crossings: 5, crossingSeconds: 30)
        XCTAssertEqual(gs.minigameBests["discoeasy"], 12)
        XCTAssertEqual(gs.minigameBests["discohard"], 5)
        XCTAssertNil(gs.minigameBests["disco"])
        XCTAssertEqual(gs.discoBestAvgMs["easy"], 4_000)
        XCTAssertEqual(gs.discoBestAvgMs["hard"], 6_000)
        XCTAssertNil(gs.discoBestAvgMs["normal"])
        // A longer Easy run does not touch Hardcore.
        _ = gs.recordDiscoResult(bestKey: "discoeasy", crossings: 20, crossingSeconds: 60)
        XCTAssertEqual(gs.minigameBests["discohard"], 5)
        XCTAssertEqual(gs.discoBestAvgMs["hard"], 6_000)
        // The profile summary is the best of the three.
        XCTAssertEqual(gs.discoBoardBest, 20)
        XCTAssertEqual(gs.discoBoardAvgMs, 3_000)
    }

    func testATieKeepsTheFasterRunAndAShorterRunChangesNothing() {
        let (gs, defaults, suite) = makeGameState()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = gs.recordDiscoResult(bestKey: "disco", crossings: 10, crossingSeconds: 50)
        _ = gs.recordDiscoResult(bestKey: "disco", crossings: 10, crossingSeconds: 60)
        XCTAssertEqual(gs.discoBestAvgMs["normal"], 5_000, "a slower tie must not replace the best")
        _ = gs.recordDiscoResult(bestKey: "disco", crossings: 10, crossingSeconds: 42)
        XCTAssertEqual(gs.discoBestAvgMs["normal"], 4_200, "a faster tie replaces the time")
        _ = gs.recordDiscoResult(bestKey: "disco", crossings: 3, crossingSeconds: 3)
        XCTAssertEqual(gs.minigameBests["disco"], 10)
        XCTAssertEqual(gs.discoBestAvgMs["normal"], 4_200)
    }

    func testTheBestSurvivesARelaunch() {
        let (gs, defaults, suite) = makeGameState()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = gs.recordDiscoResult(bestKey: "discohard", crossings: 7, crossingSeconds: 35)
        let reloaded = GameState(defaults: defaults)
        XCTAssertEqual(reloaded.minigameBests["discohard"], 7)
        XCTAssertEqual(reloaded.discoBestAvgMs["hard"], 5_000)
        XCTAssertEqual(reloaded.localLeaderboardProfile.discoballBest, 7)
    }

    func testBoardsKeptPerDifficulty() {
        XCTAssertEqual(LeaderboardBoard.crossingTime(4_300), "4.3 s")
        XCTAssertEqual(LeaderboardBoard.crossingTime(0), "—")
        XCTAssertEqual(LeaderboardBoard.discoBall.category, .solo)
        // Disco Ball and the six competitive games have difficulty tabs.
        XCTAssertEqual(LeaderboardBoard.discoBall.difficultyGameID, "disco")
        XCTAssertEqual(LeaderboardBoard.snacky.difficultyGameID, "snake")
        XCTAssertEqual(LeaderboardBoard.coinPit.difficultyGameID, "goldrush")
        XCTAssertNil(LeaderboardBoard.rollAlong.difficultyGameID)
        XCTAssertNil(LeaderboardBoard.zenGarden.difficultyGameID)
        XCTAssertNil(LeaderboardBoard.rollUp.difficultyGameID)
        let withTabs = LeaderboardBoard.allCases.filter { $0.difficultyGameID != nil }
        XCTAssertEqual(withTabs.count, 7)
        // The game's own names on the tabs.
        XCTAssertEqual(LeaderboardBoard.discoBall.difficultyLabel("hard"), "Hardcore")
        XCTAssertEqual(LeaderboardBoard.sumo.difficultyLabel("hard"), "Hard")
        XCTAssertEqual(LeaderboardBoard.sumo.difficultyLabel("easy"), "Easy")
        // The Disco best keys map to and from difficulties.
        for d in MinigameDifficulty.allCases {
            XCTAssertEqual(GameState.discoDifficulty(forBestKey: GameState.discoBestKey(d)), d)
        }
    }
}


// ---------------------------------------------------------------------------
// Analytics wire format: every event in a batch must encode the SAME keys,
// or PostgREST rejects the whole bulk insert ("All object keys must match").
// ---------------------------------------------------------------------------
final class AnalyticsBatchEncodingTests: XCTestCase {

    private func event(_ name: String, level: Int?, props: [String: AnyEncodable] = [:]) -> PendingEvent {
        PendingEvent(userId: UUID(), sessionId: UUID(), eventName: name,
                     properties: props, level: level,
                     appVersion: "1.0", iosVersion: "18.2", deviceModel: "iPhone17,1")
    }

    func testMixedBatchEncodesIdenticalKeysWithNullLevel() throws {
        let batch = [event("level_attempt", level: 12),
                     event("app_launch", level: nil),
                     event("minigame_result", level: nil, props: ["won": .bool(true)])]
        let data = try PendingEvent.encodeBatch(batch)
        let objects = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(objects.count, 3)
        let expected: Set<String> = ["user_id", "session_id", "event_name", "properties",
                                     "level", "app_version", "ios_version", "device_model"]
        for object in objects {
            XCTAssertEqual(Set(object.keys), expected, "every event must carry the same keys")
        }
        XCTAssertEqual(objects[0]["level"] as? Int, 12)
        XCTAssertTrue(objects[1]["level"] is NSNull, "a missing level is sent as null, not left out")
        XCTAssertTrue(objects[2]["level"] is NSNull)
    }

    func testFieldsAreCutToTheTableLimits() {
        let long = String(repeating: "x", count: 200)
        let e = PendingEvent(userId: UUID(), sessionId: UUID(), eventName: long,
                             properties: [:], level: nil,
                             appVersion: long, iosVersion: long, deviceModel: long)
        XCTAssertEqual(e.eventName.unicodeScalars.count,   PendingEvent.maxEventName)
        XCTAssertEqual(e.appVersion.unicodeScalars.count,  PendingEvent.maxVersion)
        XCTAssertEqual(e.iosVersion.unicodeScalars.count,  PendingEvent.maxVersion)
        XCTAssertEqual(e.deviceModel.unicodeScalars.count, PendingEvent.maxDevice)
        XCTAssertEqual(PendingEvent.clip("é🎱abc", to: 2).unicodeScalars.count, 2)
    }

    func testNonFiniteNumbersEncodeAsNull() throws {
        let data = try PendingEvent.encodeBatch([event("x", level: nil,
                                                       props: ["nan": .double(.nan),
                                                               "inf": .double(.infinity),
                                                               "ok":  .double(1.5)])])
        let objects = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let props = try XCTUnwrap(objects.first?["properties"] as? [String: Any])
        XCTAssertTrue(props["nan"] is NSNull)
        XCTAssertTrue(props["inf"] is NSNull)
        XCTAssertEqual(props["ok"] as? Double, 1.5)
    }

    // MARK: - Minigames never cost lives

    /// Only the Adventure climb and its Challenge Tracks spend lives.  Every
    /// minigame (competitive or solo, shipped or held back like Roll Out) and
    /// the Challenge of the Day must be `.unlimited`.
    func testOnlyTheClimbSpendsLives() {
        for entry in GameModeCatalogue.registry {
            let mode = entry.mode
            if mode.id == "climb" || mode is ChallengeTrackMode {
                XCTAssertEqual(mode.lives, .consume, "\(mode.id) should spend lives")
            } else {
                XCTAssertEqual(mode.lives, .unlimited, "minigame \(mode.id) must never cost a life")
            }
        }
    }
}

/// The in-game border's corner radius comes from a public table, not a
/// private screen key.
final class DisplayCornerTests: XCTestCase {
    func testKnownPanels() {
        XCTAssertEqual(DisplayCorner.radius(nativeHeight: 1334), 0)      // iPhone SE
        XCTAssertEqual(DisplayCorner.radius(nativeHeight: 2556), 55)     // iPhone 15 / 16
        XCTAssertEqual(DisplayCorner.radius(nativeHeight: 2736), 62)     // iPhone Air
    }
    func testUnknownPanelUsesNewModelDefault() {
        XCTAssertEqual(DisplayCorner.radius(nativeHeight: 3000), DisplayCorner.newModelDefault)
    }
}
