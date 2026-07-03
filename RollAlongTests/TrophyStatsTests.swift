//
//  TrophyStatsTests.swift
//  RollAlongTests
//
//  S0-T2 — TrophyStats counter tests (sprint-plan.md §2 S0-T2 acceptance
//  criteria): every counter proves increment at its GameState funnel, a
//  persistence round-trip, and monotonicity; the counter inventory is
//  test-enumerated 1:1 against trophy-catalog.md §6 items {4, 5, 6, 15};
//  and `resetProgress()` / `liquidateCoinCosmetics()` provably do NOT
//  touch any trophy counter. The prohibitions (no coins-spent counter,
//  no falls/failure counter, no speculative counters) are enforced as
//  exact key-set equality plus funnel-sweep subset checks.
//
//  Pattern per GameStateTests: every test runs against a private,
//  throwaway UserDefaults suite injected via GameState(defaults:) /
//  TrophyStats(defaults:), so tests never touch the real save.
//

import XCTest
@testable import RollAlong

final class TrophyStatsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "TrophyStatsTests.isolated"

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

    /// A GameState backed by the isolated suite (fresh, empty state).
    private func makeGameState() -> GameState {
        GameState(defaults: defaults)
    }

    /// Snapshot of every `ra_trophy*` key currently persisted in the suite.
    private func persistedTrophyKeyValues() -> [String: Int] {
        var snapshot: [String: Int] = [:]
        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix("ra_trophy") {
            snapshot[key] = value as? Int
        }
        return snapshot
    }

    // MARK: - §6 item 4 — lifetime coins earned from play

    /// Source filter: play and daily count; IAP, refund, and
    /// gift-compensation are the load-bearing exclusions.
    func testRecordCoins_countsOnlyPlayEarnedSources() {
        let stats = TrophyStats(defaults: defaults)
        stats.recordCoins(100, source: .play)
        stats.recordCoins(30, source: .daily)
        stats.recordCoins(60_000, source: .iap)
        stats.recordCoins(500, source: .refund)
        stats.recordCoins(375, source: .giftCompensation)
        XCTAssertEqual(stats.coinsEarnedFromPlay, 130, "only play + daily count (§6 item 4)")
    }

    /// Monotonic: zero and negative amounts are ignored.
    func testRecordCoins_ignoresNonPositiveAmounts() {
        let stats = TrophyStats(defaults: defaults)
        stats.recordCoins(50, source: .play)
        stats.recordCoins(0, source: .play)
        stats.recordCoins(-25, source: .play)
        XCTAssertEqual(stats.coinsEarnedFromPlay, 50)
    }

    /// Funnel: a default (untagged) `addCoins` is play income — the
    /// counter and the balance move together, clamps intact.
    func testAddCoins_playSourceBumpsLifetimeCounter() {
        let gs = makeGameState()
        gs.coinBalance = 0
        gs.addCoins(50)
        gs.addCoins(2, source: .play)
        XCTAssertEqual(gs.coinBalance, 52)
        XCTAssertEqual(gs.trophyStats.coinsEarnedFromPlay, 52)
    }

    /// Funnel: the existing 60k single-award clamp is intact and the
    /// counter records the actually-granted (clamped) award; the 999,999
    /// balance cap is a wallet limit, not an earn limit — a full wallet
    /// still earns.
    func testAddCoins_clampsIntactAndCounterRecordsGrantedAward() {
        let gs = makeGameState()
        gs.coinBalance = 0
        gs.addCoins(70_000)   // exceeds maxSingleAward
        XCTAssertEqual(gs.coinBalance, 60_000, "single-award clamp unchanged")
        XCTAssertEqual(gs.trophyStats.coinsEarnedFromPlay, 60_000)

        gs.coinBalance = GameState.maxCoinBalance
        gs.addCoins(100)
        XCTAssertEqual(gs.coinBalance, GameState.maxCoinBalance, "balance cap unchanged")
        XCTAssertEqual(gs.trophyStats.coinsEarnedFromPlay, 60_100,
                       "earning continues at the wallet cap")
    }

    /// Funnel: IAP-tagged awards raise the balance but never the counter
    /// (the StoreKitManager call sites pass `.iap`).
    func testAddCoins_iapSourceExcluded() {
        let gs = makeGameState()
        gs.coinBalance = 0
        gs.addCoins(60_000, source: .iap)
        XCTAssertEqual(gs.coinBalance, 60_000)
        XCTAssertEqual(gs.trophyStats.coinsEarnedFromPlay, 0,
                       "IAP grants are purchased, not earned (§6 item 4)")
    }

    /// Funnel: Sell Back liquidation refunds are recycled capital — the
    /// wardrobe-churn exploit the exclusion exists to close.
    func testLiquidateCoinCosmetics_refundExcludedFromPlayEarned() throws {
        let gs = makeGameState()
        let ball = try XCTUnwrap(
            BallSkin.allCases.first { $0.isSellable },
            "need a sellable ball skin")
        gs.addCoins(ball.coinCost)                       // play-funded
        XCTAssertTrue(gs.purchase(ball))
        let before = gs.trophyStats.coinsEarnedFromPlay
        XCTAssertEqual(before, ball.coinCost)

        let result = gs.liquidateCoinCosmetics()
        XCTAssertEqual(result.coins, ball.coinCost / 2, "Sell Back pays min(cost/2, paid)")
        XCTAssertEqual(gs.coinBalance, ball.coinCost / 2, "refund reached the balance")
        XCTAssertEqual(gs.trophyStats.coinsEarnedFromPlay, before,
                       "refunds never count as play income")
    }

    /// Funnel: `grantBundleFree` compensation (PR #114's refund-shaped
    /// credit) is excluded.
    func testGrantBundleFree_compensationExcludedFromPlayEarned() throws {
        let gs = makeGameState()
        let bundle = try XCTUnwrap(
            CosmeticBundle.catalogue.first { $0.balls.contains { $0.isSellable } },
            "need a bundle containing a sellable ball")
        let ball = try XCTUnwrap(bundle.balls.first { $0.isSellable })
        gs.addCoins(ball.coinCost)                       // play-funded
        XCTAssertTrue(gs.purchase(ball))
        let earnedBefore = gs.trophyStats.coinsEarnedFromPlay
        let balanceBefore = gs.coinBalance

        gs.grantBundleFree(bundle)
        XCTAssertEqual(gs.coinBalance, balanceBefore + ball.coinCost / 2,
                       "compensation reached the balance at sellBackValue")
        XCTAssertEqual(gs.trophyStats.coinsEarnedFromPlay, earnedBefore,
                       "gift compensation never counts as play income")
    }

    /// Funnel: the CotD clear reward is genuine play income.
    func testCompleteTodaysDailyChallenge_rewardCountsAsPlay() {
        let gs = makeGameState()
        gs.completeTodaysDailyChallenge()
        XCTAssertEqual(gs.trophyStats.coinsEarnedFromPlay,
                       gs.todaysDailyChallenge.rewardCoins)
        // Same-day double completion guard: no double count.
        gs.completeTodaysDailyChallenge()
        XCTAssertEqual(gs.trophyStats.coinsEarnedFromPlay,
                       gs.todaysDailyChallenge.rewardCoins)
    }

    // MARK: - §6 item 5 — lifetime daily-reward claims

    /// Funnel: a successful claim bumps the counter exactly once; the
    /// same-day re-claim is a nil no-op; the ladder coins count as
    /// play-earned (`.daily` source).
    func testClaimDailyReward_bumpsClaimCounterOncePerDay() {
        let gs = makeGameState()
        let amount = gs.claimDailyReward()
        XCTAssertNotNil(amount)
        XCTAssertEqual(gs.trophyStats.dailyRewardClaims, 1)
        XCTAssertEqual(gs.trophyStats.coinsEarnedFromPlay, amount,
                       "daily-reward ladder coins count as play-earned")

        XCTAssertNil(gs.claimDailyReward(), "second same-day claim is a no-op")
        XCTAssertEqual(gs.trophyStats.dailyRewardClaims, 1)
    }

    /// The claim counter counts claims, not streaks: a broken streak
    /// (missed day) still increments the lifetime count.
    func testClaimDailyReward_countsClaimsNotStreaks() {
        let gs = makeGameState()
        _ = gs.claimDailyReward()
        // Simulate "claimed the day before yesterday" — streak broken.
        gs.lastDailyClaim = Calendar.current.date(byAdding: .day, value: -2, to: .now)
        _ = gs.claimDailyReward()
        XCTAssertEqual(gs.trophyStats.dailyRewardClaims, 2,
                       "kind to imperfect schedules — claims accumulate across broken streaks")
    }

    // MARK: - §6 item 6 — consecutive no-fall clear streak

    /// Funnel: climb clears grow the streak; the best-ratchet follows.
    func testRecordResult_climbClearIncrementsStreak() {
        let gs = makeGameState()
        gs.currentModeID = "climb"
        for level in 1...3 {
            gs.recordResult(level: level, stars: 3, time: 10, coinIndices: [])
        }
        XCTAssertEqual(gs.trophyStats.noFallClearStreak, 3)
        XCTAssertEqual(gs.trophyStats.bestNoFallClearStreak, 3)
    }

    /// Defense-in-depth: with a non-climb mode armed, a (synthetic)
    /// `recordResult` call must not grow the streak — no future mode may
    /// pollute climb trophies (§6 item 3 vocabulary:
    /// `progression.recordsClimbResult`).
    func testRecordResult_nonClimbModeDoesNotIncrement() {
        let gs = makeGameState()
        gs.currentModeID = "zen"
        gs.recordResult(level: 1, stars: 3, time: 10, coinIndices: [])
        XCTAssertEqual(gs.trophyStats.noFallClearStreak, 0)
        XCTAssertEqual(gs.trophyStats.bestNoFallClearStreak, 0)
    }

    /// Funnel: a climb fall (`consumeLife` while the climb is armed)
    /// resets the working streak; the best-ratchet is latched forever.
    func testConsumeLife_climbFallResetsStreakButNotBest() {
        let gs = makeGameState()
        gs.currentModeID = "climb"
        for level in 1...5 {
            gs.recordResult(level: level, stars: 1, time: 20, coinIndices: [])
        }
        gs.consumeLife()
        XCTAssertEqual(gs.trophyStats.noFallClearStreak, 0, "climb fall breaks the streak")
        XCTAssertEqual(gs.trophyStats.bestNoFallClearStreak, 5, "the ratchet never regresses")
        // The next clear restarts the count from 1.
        gs.recordResult(level: 6, stars: 1, time: 20, coinIndices: [])
        XCTAssertEqual(gs.trophyStats.noFallClearStreak, 1)
        XCTAssertEqual(gs.trophyStats.bestNoFallClearStreak, 5)
    }

    /// Mode gate: Roll Out / Roll Up life consumption must NOT reset the
    /// climb streak (their views call the same `consumeLife`).
    func testConsumeLife_rollOutRollUpDoesNotResetStreak() {
        let gs = makeGameState()
        gs.currentModeID = "climb"
        for level in 1...4 {
            gs.recordResult(level: level, stars: 1, time: 20, coinIndices: [])
        }
        for modeID in ["rollout", "rollup", "challenge.frozen-peaks"] {
            gs.currentModeID = modeID
            gs.consumeLife()
            XCTAssertEqual(gs.trophyStats.noFallClearStreak, 4,
                           "a \(modeID) life consumption must not reset the climb streak")
        }
        XCTAssertEqual(gs.trophyStats.bestNoFallClearStreak, 4)
    }

    /// An unlimited-lives subscriber's climb fall still breaks the streak
    /// — the subscription must not farm `skill_clean_sheet_*`.
    func testConsumeLife_unlimitedLivesStillResetsStreak() {
        let gs = makeGameState()
        gs.currentModeID = "climb"
        gs.unlimitedLives = true
        for level in 1...3 {
            gs.recordResult(level: level, stars: 1, time: 20, coinIndices: [])
        }
        XCTAssertTrue(gs.consumeLife(), "subscribers keep their free retry")
        XCTAssertEqual(gs.trophyStats.noFallClearStreak, 0,
                       "a fall is a fall — unlimited lives can't protect the streak")
        XCTAssertEqual(gs.trophyStats.bestNoFallClearStreak, 3)
    }

    /// The streak persists across sessions (catalog `skill_clean_sheet_10`
    /// row note) — a relaunched GameState resumes the same streak.
    func testNoFallStreak_persistsAcrossRelaunch() {
        let gs = makeGameState()
        gs.currentModeID = "climb"
        gs.recordResult(level: 1, stars: 1, time: 20, coinIndices: [])
        gs.recordResult(level: 2, stars: 1, time: 20, coinIndices: [])

        let relaunched = makeGameState()
        XCTAssertEqual(relaunched.trophyStats.noFallClearStreak, 2)
        XCTAssertEqual(relaunched.trophyStats.bestNoFallClearStreak, 2)
    }

    // MARK: - §6 item 15 — CotD consecutive-date derivation (no storage)

    func testDailyClearRunDerivation_basics() {
        XCTAssertEqual(TrophyStats.longestConsecutiveDailyClearRun(in: []), 0)
        XCTAssertEqual(TrophyStats.longestConsecutiveDailyClearRun(in: ["2026-07-02"]), 1)
        XCTAssertEqual(TrophyStats.longestConsecutiveDailyClearRun(
            in: ["2026-07-01", "2026-07-02", "2026-07-03", "2026-07-10", "2026-07-11"]), 3)
        // Non-adjacent dates never chain.
        XCTAssertEqual(TrophyStats.longestConsecutiveDailyClearRun(
            in: ["2026-01-05", "2026-02-05", "2026-03-05"]), 1)
    }

    /// Month, year, and leap-day boundaries are consecutive calendar dates.
    func testDailyClearRunDerivation_calendarBoundaries() {
        XCTAssertEqual(TrophyStats.longestConsecutiveDailyClearRun(
            in: ["2026-01-30", "2026-01-31", "2026-02-01"]), 3)
        XCTAssertEqual(TrophyStats.longestConsecutiveDailyClearRun(
            in: ["2026-12-31", "2027-01-01"]), 2)
        XCTAssertEqual(TrophyStats.longestConsecutiveDailyClearRun(
            in: ["2028-02-28", "2028-02-29", "2028-03-01"]), 3, "2028 is a leap year")
    }

    /// The `daily_week_streak` shape: exactly 7 consecutive dates → 7;
    /// a 6-run plus a detached date stays below the threshold.
    func testDailyClearRunDerivation_weekStreakBoundary() {
        let sevenRun: Set<String> = ["2026-03-01", "2026-03-02", "2026-03-03",
                                     "2026-03-04", "2026-03-05", "2026-03-06",
                                     "2026-03-07"]
        XCTAssertEqual(TrophyStats.longestConsecutiveDailyClearRun(in: sevenRun), 7)

        var sixPlusGap = sevenRun
        sixPlusGap.remove("2026-03-04")   // 3-run + 3-run
        sixPlusGap.insert("2026-03-20")
        XCTAssertEqual(TrophyStats.longestConsecutiveDailyClearRun(in: sixPlusGap), 3)
    }

    /// Malformed keys are skipped, never crash, never chain.
    func testDailyClearRunDerivation_ignoresMalformedKeys() {
        XCTAssertEqual(TrophyStats.longestConsecutiveDailyClearRun(
            in: ["garbage", "", "2026-13-01", "2026-00-10", "07-02", "2026-07-02"]), 1)
    }

    /// The helper understands the ACTUAL shipped key format — keys minted
    /// by `DailyChallenge.key()` for adjacent days chain.
    func testDailyClearRunDerivation_matchesDailyChallengeKeyFormat() throws {
        let today = Date()
        let yesterday = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: -1, to: today))
        let run = TrophyStats.longestConsecutiveDailyClearRun(
            in: [DailyChallenge.key(yesterday), DailyChallenge.key(today)])
        XCTAssertEqual(run, 2)
    }

    /// Item 15 is derivation-only: driving the derivation writes NO
    /// UserDefaults key (the completions date set is the only storage).
    func testDailyClearRunDerivation_writesNoStorage() {
        _ = TrophyStats.longestConsecutiveDailyClearRun(in: ["2026-07-01", "2026-07-02"])
        XCTAssertTrue(persistedTrophyKeyValues().isEmpty,
                      "the CotD streak derives from dailyChallengeCompletions — no new storage")
    }

    // MARK: - Persistence round-trips + monotonic load

    /// Every counter survives a store round-trip on the same defaults.
    func testPersistenceRoundTrip() {
        let stats = TrophyStats(defaults: defaults)
        stats.recordCoins(1_234, source: .play)
        stats.recordDailyRewardClaim()
        stats.recordDailyRewardClaim()
        stats.recordNoFallClimbClear()
        stats.recordNoFallClimbClear()
        stats.resetNoFallClearStreak()
        stats.recordNoFallClimbClear()

        let reloaded = TrophyStats(defaults: defaults)
        XCTAssertEqual(reloaded.coinsEarnedFromPlay, 1_234)
        XCTAssertEqual(reloaded.dailyRewardClaims, 2)
        XCTAssertEqual(reloaded.noFallClearStreak, 1)
        XCTAssertEqual(reloaded.bestNoFallClearStreak, 2)
    }

    /// Defensive loads: corrupt negatives clamp to 0; a best below the
    /// working streak self-heals upward (the ratchet can never be behind).
    func testInit_defensiveLoads() {
        defaults.set(-50, forKey: TrophyStats.coinsEarnedFromPlayKey)
        defaults.set(-1, forKey: TrophyStats.dailyRewardClaimsKey)
        defaults.set(7, forKey: TrophyStats.noFallClearStreakKey)
        defaults.set(3, forKey: TrophyStats.noFallClearStreakBestKey)

        let stats = TrophyStats(defaults: defaults)
        XCTAssertEqual(stats.coinsEarnedFromPlay, 0)
        XCTAssertEqual(stats.dailyRewardClaims, 0)
        XCTAssertEqual(stats.noFallClearStreak, 7)
        XCTAssertEqual(stats.bestNoFallClearStreak, 7, "best self-heals to ≥ current")
    }

    // MARK: - Ratchet immunity fixtures (resetProgress / liquidation)

    /// `resetProgress()` wipes level progress but provably does not touch
    /// a single trophy counter key.
    func testResetProgress_touchesNoTrophyCounter() {
        let gs = makeGameState()
        gs.currentModeID = "climb"
        gs.addCoins(500)
        _ = gs.claimDailyReward()
        gs.recordResult(level: 1, stars: 3, time: 9, coinIndices: [0, 1, 2])
        gs.recordResult(level: 2, stars: 3, time: 9, coinIndices: [])
        let before = persistedTrophyKeyValues()
        XCTAssertFalse(before.isEmpty)

        gs.resetProgress()

        XCTAssertEqual(persistedTrophyKeyValues(), before,
                       "resetProgress must not touch ra_trophy* keys")
        XCTAssertEqual(gs.currentLevel, 1, "reset still did its job")
        XCTAssertTrue(gs.bestStars.isEmpty)
    }

    /// `liquidateCoinCosmetics()` relocks cosmetics and refunds coins but
    /// provably does not move any trophy counter (its refund is tagged).
    func testLiquidateCoinCosmetics_touchesNoTrophyCounter() throws {
        let gs = makeGameState()
        gs.currentModeID = "climb"
        gs.recordResult(level: 1, stars: 3, time: 9, coinIndices: [])
        _ = gs.claimDailyReward()
        let ball = try XCTUnwrap(BallSkin.allCases.first { $0.isSellable })
        gs.addCoins(ball.coinCost)
        XCTAssertTrue(gs.purchase(ball))
        let before = persistedTrophyKeyValues()
        XCTAssertFalse(before.isEmpty)

        let result = gs.liquidateCoinCosmetics()
        XCTAssertGreaterThan(result.count, 0, "liquidation still did its job")

        XCTAssertEqual(persistedTrophyKeyValues(), before,
                       "liquidateCoinCosmetics must not touch ra_trophy* keys")
    }

    // MARK: - Prohibitions + 1:1 catalog mapping (test-enumerated)

    /// The complete counter inventory maps 1:1 onto trophy-catalog.md §6
    /// items {4, 5, 6}; item 15 is storage-free by design. Exact set
    /// equality IS the prohibition proof: a coins-spent counter, a
    /// falls/failure counter, or any speculative counter (results-shared,
    /// session count, lives received, climb attempts) would have to
    /// appear in this set — and may not.
    func testEveryCounterMapsOneToOneToCatalogItem() {
        let documentedInventory: [String: (item: Int, feeds: TrophyMetric)] = [
            TrophyStats.coinsEarnedFromPlayKey:
                (item: 4, feeds: .coinsEarnedFromPlay),        // econ_working_capital
            TrophyStats.dailyRewardClaimsKey:
                (item: 5, feeds: .dailyRewardClaims),          // econ_punch_card
            TrophyStats.noFallClearStreakKey:
                (item: 6, feeds: .noFallClearStreakBest),      // working value
            TrophyStats.noFallClearStreakBestKey:
                (item: 6, feeds: .noFallClearStreakBest),      // the ratchet
        ]
        XCTAssertEqual(TrophyStats.allPersistedKeys, Set(documentedInventory.keys),
                       "counter inventory drifted from the §6 mapping")
        XCTAssertEqual(Set(documentedInventory.values.map { $0.item }), [4, 5, 6],
                       "S0-T2 owns exactly the GameState-funnel items 4–6")
        // Item 15 (daily_clear_streak_best) is derivation-only — its metric
        // exists in the vocabulary but no key backs it.
        XCTAssertFalse(TrophyStats.allPersistedKeys.contains {
            $0.lowercased().contains("dailyclear") || $0.lowercased().contains("cotd")
        })
        // Banned vocabulary can never appear in a persisted counter name.
        for key in TrophyStats.allPersistedKeys {
            let lower = key.lowercased()
            for banned in ["spent", "spend", "fail", "outoflives", "attempt",
                           "session", "shared", "livesreceived"] {
                XCTAssertFalse(lower.contains(banned),
                               "\(key) smells like a banned counter (\(banned))")
            }
        }
    }

    /// Sweep the funnels end-to-end: spends and falls move NO counter
    /// upward (no coins-spent counter, no falls/failure counter), and the
    /// only `ra_trophy*` keys ever written are the enumerated four.
    /// (S0-T3's engine adds its separate `ra_trophyUnlocks` ledger keys —
    /// that session extends this allowlist when it wires the engine in.)
    func testFunnelSweep_writesOnlyEnumeratedKeys_spendsAndFallsCountNothing() {
        let gs = makeGameState()
        gs.currentModeID = "climb"

        gs.addCoins(500)
        gs.recordResult(level: 1, stars: 2, time: 15, coinIndices: [0])
        _ = gs.claimDailyReward()
        let earned = gs.trophyStats.coinsEarnedFromPlay
        let claims = gs.trophyStats.dailyRewardClaims
        let best = gs.trophyStats.bestNoFallClearStreak

        // A spend moves nothing.
        XCTAssertTrue(gs.spendCoins(200))
        XCTAssertEqual(gs.trophyStats.coinsEarnedFromPlay, earned,
                       "no coins-spent counter, and spends never touch play-earned")

        // A fall moves nothing upward — the working streak reset is the
        // only effect, and the ratchet holds.
        gs.consumeLife()
        XCTAssertEqual(gs.trophyStats.coinsEarnedFromPlay, earned)
        XCTAssertEqual(gs.trophyStats.dailyRewardClaims, claims)
        XCTAssertEqual(gs.trophyStats.bestNoFallClearStreak, best)
        XCTAssertEqual(gs.trophyStats.noFallClearStreak, 0)

        gs.resetProgress()
        _ = gs.liquidateCoinCosmetics()

        let written = Set(persistedTrophyKeyValues().keys)
        XCTAssertTrue(written.isSubset(of: TrophyStats.allPersistedKeys),
                      "unexpected ra_trophy* keys written: " +
                      "\(written.subtracting(TrophyStats.allPersistedKeys).sorted())")
    }

    /// Monotonicity, structurally: after arbitrary funnel traffic the
    /// lifetime counters and the best-ratchet never sit below any value
    /// they previously held (spot-checked across every mutating call).
    func testCountersAreMonotonicAcrossFunnelTraffic() {
        let gs = makeGameState()
        gs.currentModeID = "climb"
        var floorEarned = 0
        var floorClaims = 0
        var floorBest = 0

        func assertRatchets(_ label: String) {
            XCTAssertGreaterThanOrEqual(gs.trophyStats.coinsEarnedFromPlay, floorEarned, label)
            XCTAssertGreaterThanOrEqual(gs.trophyStats.dailyRewardClaims, floorClaims, label)
            XCTAssertGreaterThanOrEqual(gs.trophyStats.bestNoFallClearStreak, floorBest, label)
            floorEarned = gs.trophyStats.coinsEarnedFromPlay
            floorClaims = gs.trophyStats.dailyRewardClaims
            floorBest = gs.trophyStats.bestNoFallClearStreak
        }

        gs.addCoins(300); assertRatchets("addCoins")
        _ = gs.claimDailyReward(); assertRatchets("claimDailyReward")
        gs.recordResult(level: 1, stars: 3, time: 8, coinIndices: []); assertRatchets("recordResult")
        gs.consumeLife(); assertRatchets("consumeLife")
        _ = gs.spendCoins(250); assertRatchets("spendCoins")
        gs.resetProgress(); assertRatchets("resetProgress")
        _ = gs.liquidateCoinCosmetics(); assertRatchets("liquidateCoinCosmetics")
        gs.completeTodaysDailyChallenge(); assertRatchets("completeTodaysDailyChallenge")
    }

    // MARK: - S0-T5 harness usage over a stats-backed trophy

    /// The S0-T5 `TrophyTestHarness` (defined in TrophyEngineTests.swift) is
    /// shared scaffolding usable from every trophy test file — here it drives
    /// a COUNTER-backed trophy end-to-end. `econ_punch_card` unlocks at 30
    /// lifetime daily-reward claims (`TrophyStats.dailyRewardClaims`, §6 item
    /// 5).
    ///
    /// Important boundary this test also documents: the NEW `ra_trophy*`
    /// counters (claims, play-earned coins, no-fall streak) are deliberately
    /// ABSENT from `TrophyBackfill.snapshot` — backfill must not grandfather a
    /// counter that starts at zero the day trophies ship — so `harness.sync()`
    /// (the existing-stats path) never fires a counter-backed trophy. The
    /// live path drives the metric from its counter directly, which is exactly
    /// what S1-T2's `claimDailyReward` funnel will do internally. This is the
    /// copy-paste shape for S1-T2's `econ_punch_card` trigger test.
    func testHarnessDrivesACounterBackedTrophy() {
        let h = TrophyTestHarness()
        h.assertLocked("econ_punch_card")

        // 29 claims across broken streaks — the counter is claims, not streak.
        for offset in stride(from: 58, through: 2, by: -2) {
            h.gameState.lastDailyClaim = Calendar.current.date(
                byAdding: .day, value: -offset, to: .now)
            XCTAssertNotNil(h.gameState.claimDailyReward())
        }
        XCTAssertEqual(h.gameState.trophyStats.dailyRewardClaims, 29)
        // Drive the live counter value into the engine (the S1-T2 funnel move).
        XCTAssertTrue(h.record(.dailyRewardClaims,
                               value: Double(h.gameState.trophyStats.dailyRewardClaims)).isEmpty,
                      "29 claims is below the 30 bar")
        h.assertLocked("econ_punch_card")

        // The 30th claim crosses the threshold; the record latches it once.
        h.gameState.lastDailyClaim = Calendar.current.date(byAdding: .day, value: -1, to: .now)
        XCTAssertNotNil(h.gameState.claimDailyReward())
        XCTAssertEqual(h.gameState.trophyStats.dailyRewardClaims, 30)
        h.assertUnlocked("econ_punch_card",
                         in: h.record(.dailyRewardClaims,
                                      value: Double(h.gameState.trophyStats.dailyRewardClaims)))
        h.assertUnlocked("econ_punch_card")
    }
}
