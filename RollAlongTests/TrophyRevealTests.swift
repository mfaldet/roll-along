//
//  TrophyRevealTests.swift
//  RollAlongTests
//
//  S2-T6 acceptance (headless): the one-time retroactive-grant reveal — the
//  single coalesced "Trophy Room unlocked — you've already earned N" moment a
//  veteran gets on the first open after the trophy update — is offered EXACTLY
//  ONCE and NEVER as N separate toasts (docs/trophies/sprint-plan.md §2 S2-T6;
//  design.md §6 "Anti-spam batching: retroactive grants get a single one-time
//  summary — never a toast cascade").
//
//  The banner's visual presentation is a device-QA item (it cannot be verified
//  headlessly). This file proves the LATCH + the correct N + the flag-clears
//  semantics:
//
//  • a veteran save (existing stats that backfill grants trophies from), taken
//    through the real GameState `activateTrophies()`, offers EXACTLY ONE reveal
//    whose N equals the number of trophies the backfill granted;
//  • the reveal's presented flag clears (persists) so a SECOND launch — a fresh
//    model/engine over the same save — offers NOTHING, even though the backfill
//    counters still read true/N (they are the historical fact, a ratchet);
//  • a fresh install (backfill ran but granted 0) shows no banner and retires
//    the reveal silently;
//  • an already-armed reveal never re-arms (idempotent — never a cascade);
//  • the reveal never mutates the trophy ledger or the economy (D1 never-mint);
//  • GameState wires the model as its own inert-by-default ObservableObject and
//    the grandfathered unlocks never leak into the small-toast feed.
//
//  The model is a plain ObservableObject driven from main-thread funnels, so
//  this case is @MainActor for its @Published reads/writes.
//

import XCTest
@testable import RollAlong

@MainActor
final class TrophyRevealTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyRevealTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeDefinition(id: String,
                               tier: TrophyTier = .bronze,
                               category: TrophyCategory = .climb,
                               metric: TrophyMetric,
                               threshold: Double,
                               requiredTrophyIDs: [String]? = nil) -> TrophyDefinition {
        TrophyDefinition(id: id,
                         title: "Title \(id)",
                         tier: tier,
                         category: category,
                         lockedDescription: "Do the thing.",
                         unlockedDescription: "You did the thing.",
                         isSecret: false,
                         criteria: TrophyCriteria(metric: metric,
                                                  threshold: threshold,
                                                  requiredTrophyIDs: requiredTrophyIDs),
                         rewardID: nil,
                         addedInVersion: TrophyCatalog.launchVersion)
    }

    /// A tiny VALID catalog: three easily-derived base trophies plus the
    /// required single capstone (so it passes the same guardrail validation
    /// the bundled catalog does). The reveal model reads only the backfill
    /// grant count — the capstone is here purely to satisfy the catalog shape.
    /// Built through `TrophyCatalog.load(from:)`.
    private func makeEngine(defaults d: UserDefaults) throws -> TrophyEngine {
        let trophies = [
            makeDefinition(id: "base_one",   metric: .climbHighestUnlocked, threshold: 5),
            makeDefinition(id: "base_two",   metric: .snakeWins,            threshold: 3),
            makeDefinition(id: "base_three", metric: .zenSeconds,           threshold: 60),
            makeDefinition(id: "capstone_all",
                           tier: .platinum,
                           category: .capstone,
                           metric: .baseTrophiesUnlocked,
                           threshold: 3,
                           requiredTrophyIDs: ["base_one", "base_two", "base_three"]),
        ]
        let file = TrophyCatalog.CatalogFile(catalogVersion: 1, trophies: trophies)
        let catalog = try TrophyCatalog.load(from: JSONEncoder().encode(file))
        return TrophyEngine(catalog: catalog,
                            defaults: d,
                            now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
    }

    /// A snapshot that satisfies exactly TWO of the three base trophies — so
    /// the backfill grants exactly 2 and the capstone stays locked (no cascade
    /// inflating the count). N is therefore a clean, deterministic 2.
    private func partialSnapshot() -> TrophyEngine.MetricSnapshot {
        [.climbHighestUnlocked: 5, .snakeWins: 3]
    }

    // MARK: - Model in isolation: exactly one reveal with the correct N

    /// Backfill grants trophies → the reveal arms once with N == grant count.
    func testBackfillGrantArmsExactlyOneRevealWithCorrectCount() throws {
        let engine = try makeEngine(defaults: defaults)
        let granted = engine.backfill(from: partialSnapshot())
        XCTAssertEqual(granted.count, 2, "sanity: the snapshot grandfathers exactly two bases")
        XCTAssertTrue(engine.didBackfill)
        XCTAssertEqual(engine.backfillGrantCount, 2)
        XCTAssertFalse(engine.isUnlocked("capstone_all"),
                       "sanity: a partial base does not cascade the capstone")

        let model = TrophyRevealModel(defaults: defaults)
        XCTAssertTrue(model.revealIfOwed(engine: engine),
                      "A non-empty backfill owes exactly one reveal.")
        XCTAssertEqual(model.pendingCount, 2,
                       "The reveal's N equals the number of trophies granted.")
        XCTAssertFalse(model.hasPresented, "Not yet dismissed — still pending.")
    }

    /// A second `revealIfOwed` WHILE the reveal is armed does not re-arm — it is
    /// already pending (idempotent; never a cascade of banners).
    func testArmedRevealDoesNotReArm() throws {
        let engine = try makeEngine(defaults: defaults)
        _ = engine.backfill(from: partialSnapshot())

        let model = TrophyRevealModel(defaults: defaults)
        XCTAssertTrue(model.revealIfOwed(engine: engine))
        XCTAssertEqual(model.pendingCount, 2)

        XCTAssertFalse(model.revealIfOwed(engine: engine),
                       "An already-armed reveal must not re-arm on a re-check.")
        XCTAssertEqual(model.pendingCount, 2, "…and the pending count is unchanged.")
    }

    // MARK: - The flag clears: a second launch shows nothing

    /// The load-bearing S2-T6 acceptance: after the reveal is offered once, a
    /// relaunch — a fresh model + engine over the SAME persisted save — offers
    /// NOTHING, even though the backfill counters still read true/N.
    func testRevealNeverReOffersAcrossRelaunch() throws {
        // Session 1: backfill grants, reveal offered, dismissed.
        let engine1 = try makeEngine(defaults: defaults)
        _ = engine1.backfill(from: partialSnapshot())
        let model1 = TrophyRevealModel(defaults: defaults)
        XCTAssertTrue(model1.revealIfOwed(engine: engine1))
        XCTAssertEqual(model1.pendingCount, 2)
        model1.markPresented()
        XCTAssertNil(model1.pendingCount, "Dismissing clears the pending reveal.")
        XCTAssertTrue(model1.hasPresented)
        XCTAssertTrue(defaults.bool(forKey: TrophyRevealModel.presentedKey),
                      "The once-ever flag persisted.")

        // Session 2: a fresh engine (didBackfill still true, count still 2) + a
        // fresh model over the same defaults (a relaunch). Nothing is owed.
        let engine2 = try makeEngine(defaults: defaults)
        XCTAssertTrue(engine2.didBackfill, "backfill-done survives relaunch (ratchet).")
        XCTAssertEqual(engine2.backfillGrantCount, 2,
                       "the grant count survives relaunch — it is the historical fact.")
        let model2 = TrophyRevealModel(defaults: defaults)
        XCTAssertTrue(model2.hasPresented, "The fresh model loads the persisted flag.")
        XCTAssertFalse(model2.revealIfOwed(engine: engine2),
                       "A relaunch after the reveal must never re-offer it.")
        XCTAssertNil(model2.pendingCount)
    }

    /// `markPresented()` is idempotent — a double dismiss does not thrash.
    func testMarkPresentedIsIdempotent() {
        let model = TrophyRevealModel(defaults: defaults)
        model.markPresented()
        XCTAssertTrue(model.hasPresented)
        model.markPresented()   // again
        XCTAssertTrue(model.hasPresented)
        XCTAssertNil(model.pendingCount)
    }

    // MARK: - Fresh install: nothing to reveal, no banner

    /// A fresh install runs the backfill but grants 0 trophies — no banner, and
    /// the reveal is retired silently so it never considers this save again.
    func testFreshInstallNeverArmsAndRetiresSilently() throws {
        let engine = try makeEngine(defaults: defaults)
        let granted = engine.backfill(from: [:])   // empty snapshot → grants nothing
        XCTAssertEqual(granted.count, 0)
        XCTAssertTrue(engine.didBackfill)
        XCTAssertEqual(engine.backfillGrantCount, 0)

        let model = TrophyRevealModel(defaults: defaults)
        XCTAssertFalse(model.revealIfOwed(engine: engine),
                       "A zero-grant backfill owes no reveal.")
        XCTAssertNil(model.pendingCount, "No banner on a fresh install.")
        XCTAssertTrue(model.hasPresented,
                      "The empty reveal is retired so it never re-checks this save.")
        XCTAssertTrue(defaults.bool(forKey: TrophyRevealModel.presentedKey))
    }

    /// Before the backfill has run (activateTrophies not called), the reveal
    /// stays inert and does NOT retire itself — a later call after backfill can
    /// still offer it.
    func testBeforeBackfillRevealStaysInertAndUnretired() throws {
        let engine = try makeEngine(defaults: defaults)
        XCTAssertFalse(engine.didBackfill, "sanity: backfill has not run yet")

        let model = TrophyRevealModel(defaults: defaults)
        XCTAssertFalse(model.revealIfOwed(engine: engine),
                       "Nothing is owed until the backfill has run.")
        XCTAssertNil(model.pendingCount)
        XCTAssertFalse(model.hasPresented,
                       "Must NOT retire before backfill — the reveal is still owed later.")

        // Now the backfill runs and grants trophies: the reveal is owed.
        _ = engine.backfill(from: partialSnapshot())
        XCTAssertTrue(model.revealIfOwed(engine: engine))
        XCTAssertEqual(model.pendingCount, 2)
    }

    // MARK: - Display-only (never-mint / ledger untouched)

    /// Arming the reveal reads the engine's counters and mutates only the
    /// model's own presentation state — it never latches, revokes, or restamps
    /// a trophy (D1 never-mint; the model is display-only).
    func testRevealDoesNotMutateTheLedger() throws {
        let engine = try makeEngine(defaults: defaults)
        _ = engine.backfill(from: partialSnapshot())
        let unlocksBefore = engine.unlockedIDs
        let countBefore = engine.backfillGrantCount

        let model = TrophyRevealModel(defaults: defaults)
        _ = model.revealIfOwed(engine: engine)
        model.markPresented()

        XCTAssertEqual(engine.unlockedIDs, unlocksBefore,
                       "The reveal must not change the unlock set.")
        XCTAssertEqual(engine.backfillGrantCount, countBefore,
                       "The reveal must not change the backfill count.")
    }

    // MARK: - GameState integration on a real veteran save

    /// End-to-end acceptance: a VETERAN save taken through the real GameState
    /// `activateTrophies()` (which runs the backfill AND arms the reveal) offers
    /// EXACTLY ONE reveal whose N equals the trophies the backfill granted —
    /// and a relaunch offers nothing.
    func testVeteranSaveOffersExactlyOneRevealThenNothing() {
        // Session 1: a real veteran save; activateTrophies backfills + arms.
        let h1 = TrophyTestHarness(save: .veteran)
        XCTAssertNil(h1.gameState.trophyReveal.pendingCount,
                     "Nothing is armed before activateTrophies runs.")

        let granted = h1.gameState.activateTrophies()
        XCTAssertGreaterThan(granted.count, 0,
                             "Sanity: the veteran backfill actually grandfathered trophies.")
        XCTAssertEqual(h1.gameState.trophyReveal.pendingCount, granted.count,
                       "Exactly one reveal, N == the number grandfathered.")
        XCTAssertEqual(h1.gameState.trophyReveal.pendingCount, h1.engine.backfillGrantCount,
                       "N matches the engine's own persisted backfill count.")

        // Calling activateTrophies AGAIN this session (as production does on a
        // re-check) does not re-arm — the reveal is already pending.
        _ = h1.gameState.activateTrophies()
        XCTAssertEqual(h1.gameState.trophyReveal.pendingCount, granted.count,
                       "A re-check does not multiply the reveal.")

        // The player opens/dismisses the reveal.
        h1.gameState.trophyReveal.markPresented()
        XCTAssertNil(h1.gameState.trophyReveal.pendingCount)
        XCTAssertTrue(h1.gameState.trophyReveal.hasPresented)
    }

    /// The flag persists across a true relaunch of the SAME save: a second
    /// GameState over the same defaults offers no reveal. Uses the harness's
    /// believable veteran seeding (kept alive so its suite survives), then
    /// builds a second GameState over the same suite as the "relaunch".
    func testVeteranRevealFlagPersistsAcrossRelaunch() throws {
        // Session 1: the harness owns a veteran-seeded suite. Keep it alive for
        // the whole test so its deinit doesn't wipe the suite mid-way.
        let h = TrophyTestHarness(save: .veteran)
        let granted = h.gameState.activateTrophies()
        XCTAssertGreaterThan(granted.count, 0)
        XCTAssertEqual(h.gameState.trophyReveal.pendingCount, granted.count)
        h.gameState.trophyReveal.markPresented()
        XCTAssertTrue(h.defaults.bool(forKey: TrophyRevealModel.presentedKey))

        // Session 2: a fresh GameState over the SAME suite (a relaunch). The
        // backfill is a no-op (already done), and the reveal never re-offers.
        let gs2 = GameState(defaults: h.defaults)
        XCTAssertTrue(gs2.trophyEngine.didBackfill)
        XCTAssertGreaterThan(gs2.trophyEngine.backfillGrantCount, 0)
        _ = gs2.activateTrophies()
        XCTAssertNil(gs2.trophyReveal.pendingCount,
                     "A relaunch after the reveal must never re-offer it.")
        XCTAssertTrue(gs2.trophyReveal.hasPresented)
    }

    /// GameState exposes the reveal on its own ObservableObject, inert on a
    /// fresh save until activateTrophies runs, and the grandfathered unlocks
    /// never leak into the small-toast feed (they get the reveal, not toasts).
    func testGameStateExposesInertRevealAndNoToastStorm() {
        let h = TrophyTestHarness(save: .veteran)
        XCTAssertNil(h.gameState.trophyReveal.pendingCount,
                     "A save arms no reveal before activateTrophies.")
        XCTAssertFalse(h.gameState.trophyReveal.hasPresented)

        _ = h.gameState.activateTrophies()
        // The reveal is armed…
        XCTAssertNotNil(h.gameState.trophyReveal.pendingCount)
        // …and the grandfathered unlocks did NOT storm the small-toast queue
        // (backfill bypasses fireTrophy — the whole point of the reveal).
        XCTAssertNil(h.gameState.trophyToasts.presented,
                     "Backfill unlocks must never surface as toasts.")
        XCTAssertEqual(h.gameState.trophyToasts.pendingCount, 0,
                       "…nor accumulate in the toast coalescing buffer.")
    }
}
