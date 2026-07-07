//
//  TrophyToastWiringTests.swift
//  RollAlongTests
//
//  S2-T2 — surface-wiring logic tests.  S2-T1 unit-tested the toast QUEUE in
//  isolation (TrophyToastQueueTests); this file tests the WIRING S2-T2 added
//  between GameState's live trophy funnels and that queue:
//
//    • `fireTrophy` — every LIVE trophy trigger routes through it, so a real
//      gameplay funnel (`recordMinigameResult`, `recordResult`, `advanceLevel`,
//      the social latches, …) hands its newly-unlocked trophies to the queue.
//    • `beginTrophyRun()` / `endTrophyRun()` — the run-lifecycle the result
//      overlays drive: unlocks earned between them are HELD + coalesced and
//      surface as ONE batch at run end, never mid-run (design.md §6).
//    • Backfill (`activateTrophies`) deliberately BYPASSES the feed — a
//      veteran's grandfathered unlocks never toast (S2-T6 owns that reveal).
//
//  Everything here is driven through GameState's public gameplay API on an
//  isolated UserDefaults suite (the GameStateTests pattern) — no View is ever
//  instantiated.  The queue is a plain ObservableObject, so `@MainActor` on
//  the case is only for its `@Published` reads/writes landing on main.
//

import XCTest
@testable import RollAlong

@MainActor
final class TrophyToastWiringTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyToastWiringTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeGameState() -> GameState {
        TrophyTestHarness.makeGameState(defaults: defaults)
    }

    /// Win one competitive minigame match through the shipped view funnel.
    /// A fresh save's first win latches `arcade_first_win` + `<mode>_first_win`.
    @discardableResult
    private func winMinigame(_ gs: GameState, _ mode: String = "snake") -> Int {
        gs.recordMinigameResult(modeID: mode, difficulty: .normal,
                                won: true, score: 1, basePayout: 0)
    }

    // MARK: - The feed exists at all

    /// A live funnel that unlocks a trophy hands it to the toast queue.  With
    /// no run active, the queue presents immediately (the "unlock outside a
    /// run" path — e.g. a cosmetic buy or sign-in).  A single funnel that
    /// unlocks several trophies shows the first and coalesces the rest behind
    /// it (queue rule: max 1 in-flight, overflow pends) — so the run-armed
    /// surfaces are what guarantee ONE batch; here we assert the feed reached
    /// the queue at all (presented ∪ pending covers every unlock).
    func testLiveUnlockOutsideRunFeedsAndPresentsImmediately() {
        let gs = makeGameState()
        XCTAssertNil(gs.trophyToasts.presented)

        winMinigame(gs)   // no beginTrophyRun() → queue is idle, presents now

        XCTAssertNotNil(gs.trophyToasts.presented,
                        "A live unlock with no run active should present immediately.")
        // Every unlock the funnel produced reached the queue — the first is
        // on screen, any others coalesce into the buffer behind it.
        let onScreen = Set(gs.trophyToasts.presented?.trophies.map(\.id) ?? [])
        let buffered = Set(gs.trophyToasts.pending.map(\.id))
        let fed = onScreen.union(buffered)
        XCTAssertTrue(fed.contains("arcade_first_win"))
        XCTAssertTrue(fed.contains("snake_first_win"))
    }

    /// A no-unlock funnel bump (the common path) never presents anything.
    func testNoUnlockBumpPresentsNothing() {
        let gs = makeGameState()
        // A LOSS records the attempt but unlocks no first-win trophy.
        gs.recordMinigameResult(modeID: "snake", difficulty: .normal,
                                won: false, score: 1, basePayout: 0)
        XCTAssertNil(gs.trophyToasts.presented)
        XCTAssertEqual(gs.trophyToasts.pendingCount, 0)
    }

    // MARK: - Never mid-run

    /// Between `beginTrophyRun()` and `endTrophyRun()` a live unlock is HELD —
    /// it accumulates in the queue but nothing presents (design.md §6 "never
    /// mid-run"; a banner over a live tilt run is a death sentence).
    func testUnlockDuringRunIsHeldNotPresented() {
        let gs = makeGameState()
        gs.beginTrophyRun()

        winMinigame(gs)

        XCTAssertNil(gs.trophyToasts.presented,
                     "No banner may present while a run is active.")
        XCTAssertGreaterThan(gs.trophyToasts.pendingCount, 0,
                             "The unlock must accumulate for run-end coalescing.")
    }

    /// The result-overlay call (`endTrophyRun`) drains everything the run
    /// accumulated into ONE presented batch.
    func testEndTrophyRunDrainsHeldUnlocks() {
        let gs = makeGameState()
        gs.beginTrophyRun()
        winMinigame(gs)
        XCTAssertNil(gs.trophyToasts.presented)

        gs.endTrophyRun()

        XCTAssertNotNil(gs.trophyToasts.presented,
                        "The result overlay's endTrophyRun() must present the batch.")
        XCTAssertEqual(gs.trophyToasts.pendingCount, 0,
                       "Draining clears the coalescing buffer.")
    }

    // MARK: - Coalescing at run end

    /// Several trophies unlocked across one run surface as a SINGLE coalesced
    /// batch — not one banner each (design.md §6 "one stacked card").
    func testMultipleUnlocksInOneRunCoalesceToOneBatch() {
        let gs = makeGameState()
        gs.beginTrophyRun()

        // One win latches BOTH arcade_first_win and snake_first_win in the
        // same run — plus more if the mode crosses another threshold.
        winMinigame(gs, "snake")
        winMinigame(gs, "sumo")   // arcade_first_win already latched; sumo_first_win is new

        XCTAssertNil(gs.trophyToasts.presented)   // still held mid-run

        gs.endTrophyRun()

        let batch = gs.trophyToasts.presented
        XCTAssertNotNil(batch)
        let ids = Set(batch?.trophies.map(\.id) ?? [])
        // All of the run's unlocks ride the one batch.
        XCTAssertTrue(ids.contains("arcade_first_win"))
        XCTAssertTrue(ids.contains("snake_first_win"))
        XCTAssertTrue(ids.contains("sumo_first_win"))
        XCTAssertGreaterThanOrEqual(batch?.count ?? 0, 3)
    }

    /// A run that unlocks NOTHING presents nothing at run end — `endTrophyRun`
    /// is a no-op when the buffer is empty (no empty banner flashes).
    func testRunWithNoUnlocksPresentsNothingAtEnd() {
        let gs = makeGameState()
        gs.beginTrophyRun()
        // A loss: attempt recorded, no trophy.
        gs.recordMinigameResult(modeID: "snake", difficulty: .normal,
                                won: false, score: 1, basePayout: 0)
        gs.endTrophyRun()
        XCTAssertNil(gs.trophyToasts.presented)
    }

    // MARK: - Climb funnel (recordResult) feeds too

    /// The climb funnel (`recordResult` → `recordClimbTrophies`) also feeds the
    /// queue.  A fresh save clearing level 1 latches `climb_first_clear`, held
    /// during the run and surfaced at the winOverlay's `endTrophyRun`.
    func testClimbClearFeedsQueueAndCoalescesAtRunEnd() {
        let gs = makeGameState()
        XCTAssertFalse(gs.trophyEngine.isUnlocked("climb_first_clear"))
        gs.beginTrophyRun()

        gs.recordResult(level: 1, stars: 3, time: 8, coinIndices: [])

        XCTAssertTrue(gs.trophyEngine.isUnlocked("climb_first_clear"),
                      "The climb funnel must still latch the unlock.")
        XCTAssertNil(gs.trophyToasts.presented, "Held during the run.")

        gs.endTrophyRun()
        let ids = gs.trophyToasts.presented?.trophies.map(\.id) ?? []
        XCTAssertTrue(ids.contains("climb_first_clear"))
    }

    // MARK: - Backfill never toasts

    /// The one-time retroactive backfill (`activateTrophies`) bypasses the
    /// feed entirely — a veteran's many grandfathered unlocks must NOT toast
    /// (S2-T6 owns the single coalesced "Trophy Room opens" reveal).  The
    /// engine still latches them; the queue stays empty.
    func testBackfillGrantsDoNotFeedTheToastQueue() {
        let h = TrophyTestHarness(save: .veteran, backfill: true)
        // Backfill latched a pile of trophies…
        XCTAssertGreaterThan(h.gameState.trophyEngine.unlockedIDs.count, 0,
                             "Sanity: the veteran backfill actually granted trophies.")
        // …but none of them reached the toast queue.
        XCTAssertNil(h.gameState.trophyToasts.presented,
                     "Backfilled unlocks must never present a banner.")
        XCTAssertEqual(h.gameState.trophyToasts.pendingCount, 0,
                       "Backfilled unlocks must never enter the coalescing buffer.")
    }

    /// After a backfill, a genuinely NEW live unlock still feeds the queue —
    /// bypassing backfill doesn't disarm the live feed.
    func testLiveUnlockAfterBackfillStillFeedsQueue() {
        // A fresh save + backfill grants nothing derivable-from-nothing, so the
        // live feed is unambiguous: the win below is the first thing to toast.
        let h = TrophyTestHarness(save: .fresh, backfill: true)
        XCTAssertNil(h.gameState.trophyToasts.presented)

        h.gameState.recordMinigameResult(modeID: "snake", difficulty: .normal,
                                         won: true, score: 1, basePayout: 0)

        XCTAssertNotNil(h.gameState.trophyToasts.presented,
                        "A post-backfill live unlock must still surface.")
    }

    // MARK: - Never-mint (D1) — the feed grants no coins

    /// The toast feed is display-only: routing an unlock through `fireTrophy`
    /// and presenting a banner must not change the coin balance beyond the
    /// funnel's own (non-trophy) payout.  Here a zero-payout win banks no
    /// coins, yet still unlocks + toasts — proving the toast path itself mints
    /// nothing (D1 never-mint; §5 economy invariant).
    func testToastFeedMintsNoCoins() {
        let gs = makeGameState()
        let before = gs.coinBalance
        gs.beginTrophyRun()
        gs.recordMinigameResult(modeID: "snake", difficulty: .normal,
                                won: true, score: 0, basePayout: 0)   // zero payout
        gs.endTrophyRun()

        XCTAssertNotNil(gs.trophyToasts.presented, "The win still toasts…")
        XCTAssertEqual(gs.coinBalance, before,
                       "…but the toast path grants no coins (D1 never-mint).")
    }

    // MARK: - Idempotency across a re-armed run

    /// Draining, then arming a fresh run, then a double-fire of the same
    /// trophy never re-presents an already-shown unlock (the queue de-dups
    /// against the on-screen batch; S2-T1 guaranteed this — here through the
    /// live funnel).
    func testAlreadyPresentedUnlockNotRepresentedOnReplay() {
        let gs = makeGameState()
        gs.beginTrophyRun()
        winMinigame(gs, "snake")
        gs.endTrophyRun()
        let firstBatchIDs = Set(gs.trophyToasts.presented?.trophies.map(\.id) ?? [])
        XCTAssertTrue(firstBatchIDs.contains("snake_first_win"))

        // Replay: arm a new run and win snake again — snake_first_win is
        // already latched, so the funnel unlocks nothing new.
        gs.beginTrophyRun()
        winMinigame(gs, "snake")
        gs.endTrophyRun()

        // Nothing new to add; the still-onscreen batch is unchanged and no
        // duplicate entered the buffer.
        XCTAssertEqual(gs.trophyToasts.pendingCount, 0)
    }
}
