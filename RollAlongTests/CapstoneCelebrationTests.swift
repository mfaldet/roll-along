//
//  CapstoneCelebrationTests.swift
//  RollAlongTests
//
//  S2-T5 acceptance (headless): the Platinum-capstone full-screen celebration
//  fires EXACTLY ONCE ever and never again, latched against BOTH the engine's
//  unlock state and a durable `ra_trophyCapstonePresented` flag
//  (docs/trophies/sprint-plan.md §2 S2-T5; design.md §6 "capstone blowout ·
//  shown once"). The Reduce-Motion branch and the confetti/sound/haptics/share
//  render are device-QA items (they cannot be verified headlessly) — this case
//  proves the once-ever LATCH, the split-off-the-small-feed routing, and the
//  never-mint invariant.
//
//  Verified here:
//  • a locked capstone arms nothing;
//  • latching the full base set arms the moment exactly once;
//  • a re-check while armed does not re-arm (idempotent);
//  • after `markPresented()` the moment is dead — a fresh model over the SAME
//    defaults (a relaunch) never re-arms, even with the capstone still latched;
//  • `celebrateIfEarned` never mutates the ledger or the economy (display-only);
//  • GameState wires the model as its own inert-by-default ObservableObject.
//
//  The model is a plain ObservableObject driven from main-thread funnels, so
//  this case is @MainActor for its @Published reads/writes.
//

import XCTest
@testable import RollAlong

@MainActor
final class CapstoneCelebrationTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CapstoneCelebrationTests.\(UUID().uuidString)"
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
                         unlockedDescription: "You earned the Platinum capstone.",
                         isSecret: false,
                         criteria: TrophyCriteria(metric: metric,
                                                  threshold: threshold,
                                                  requiredTrophyIDs: requiredTrophyIDs),
                         rewardID: nil,
                         addedInVersion: TrophyCatalog.launchVersion)
    }

    /// A tiny VALID catalog whose capstone id is the REAL frozen `capstone_all`
    /// (the id `CapstoneCelebrationModel` hardcodes), plus two easily-satisfied
    /// base trophies it requires. Built through `TrophyCatalog.load(from:)` so
    /// it passes the same guardrail validation the bundled catalog does — the
    /// capstone base list is exactly this catalog's visible B/S/G launch
    /// trophies (the two bases), so the capstone-shape check is satisfied.
    private func makeCapstoneEngine(defaults d: UserDefaults? = nil) throws -> TrophyEngine {
        let trophies = [
            makeDefinition(id: "base_one", metric: .climbHighestUnlocked, threshold: 5),
            makeDefinition(id: "base_two", metric: .snakeWins, threshold: 3),
            makeDefinition(id: "capstone_all",
                           tier: .platinum,
                           category: .capstone,
                           metric: .baseTrophiesUnlocked,
                           threshold: 2,
                           requiredTrophyIDs: ["base_one", "base_two"]),
        ]
        let file = TrophyCatalog.CatalogFile(catalogVersion: 1, trophies: trophies)
        let catalog = try TrophyCatalog.load(from: JSONEncoder().encode(file))
        return TrophyEngine(catalog: catalog,
                            defaults: d ?? defaults,
                            now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
    }

    /// Latch the full capstone base on `engine`, so its ledger cascade unlocks
    /// `capstone_all`. Returns after the cascade has run.
    private func latchWholeBase(_ engine: TrophyEngine) {
        engine.record(.climbHighestUnlocked, value: 5)   // base_one
        engine.record(.snakeWins, value: 3)              // base_two → cascade → capstone_all
    }

    // MARK: - Locked capstone arms nothing

    func testLockedCapstoneDoesNotArm() throws {
        let engine = try makeCapstoneEngine()
        XCTAssertFalse(engine.isUnlocked("capstone_all"), "sanity: capstone starts locked")

        let model = CapstoneCelebrationModel(defaults: defaults)
        XCTAssertFalse(model.celebrateIfEarned(engine: engine),
                       "A locked capstone must never arm the celebration.")
        XCTAssertNil(model.pending)
        XCTAssertFalse(model.hasPresented)
    }

    /// A partial base (one of two) still leaves the capstone locked → no arm.
    func testPartialBaseDoesNotArm() throws {
        let engine = try makeCapstoneEngine()
        engine.record(.climbHighestUnlocked, value: 5)   // only base_one
        XCTAssertTrue(engine.isUnlocked("base_one"))
        XCTAssertFalse(engine.isUnlocked("capstone_all"))

        let model = CapstoneCelebrationModel(defaults: defaults)
        XCTAssertFalse(model.celebrateIfEarned(engine: engine))
        XCTAssertNil(model.pending)
    }

    // MARK: - Fires exactly once

    func testCapstoneArmsExactlyOnceWhenEarned() throws {
        let engine = try makeCapstoneEngine()
        latchWholeBase(engine)
        XCTAssertTrue(engine.isUnlocked("capstone_all"), "sanity: the full base latched the capstone")

        let model = CapstoneCelebrationModel(defaults: defaults)

        // First check after the capstone is earned: arms.
        XCTAssertTrue(model.celebrateIfEarned(engine: engine),
                      "The earned capstone arms the full-screen moment.")
        XCTAssertNotNil(model.pending)
        XCTAssertEqual(model.pending?.id, "capstone_all")
        XCTAssertEqual(model.pending?.tier, .platinum)

        // A second check WHILE the moment is still armed does not re-arm — it is
        // already pending (idempotent; no double-fire).
        XCTAssertFalse(model.celebrateIfEarned(engine: engine),
                       "An already-armed moment must not re-arm on a re-check.")
        XCTAssertEqual(model.pending?.id, "capstone_all")
    }

    // MARK: - Never again after it has played

    func testMarkPresentedRetiresTheMomentForever() throws {
        let engine = try makeCapstoneEngine()
        latchWholeBase(engine)

        let model = CapstoneCelebrationModel(defaults: defaults)
        XCTAssertTrue(model.celebrateIfEarned(engine: engine))

        // The player dismisses — the moment is retired forever.
        model.markPresented()
        XCTAssertNil(model.pending, "Dismissing clears the pending moment.")
        XCTAssertTrue(model.hasPresented)

        // A re-check on the SAME model never re-arms.
        XCTAssertFalse(model.celebrateIfEarned(engine: engine),
                       "Once played, the moment never arms again this session.")
        XCTAssertNil(model.pending)
    }

    /// The load-bearing S2-T5 acceptance: the moment fires exactly once EVER —
    /// a relaunch (a brand-new model over the SAME persisted defaults) never
    /// replays it, even though the capstone is still latched on the engine.
    func testMomentNeverReplaysAcrossRelaunch() throws {
        // Session 1: earn the capstone, play the moment, dismiss it.
        let engine1 = try makeCapstoneEngine()
        latchWholeBase(engine1)
        let model1 = CapstoneCelebrationModel(defaults: defaults)
        XCTAssertTrue(model1.celebrateIfEarned(engine: engine1))
        model1.markPresented()
        XCTAssertTrue(defaults.bool(forKey: CapstoneCelebrationModel.presentedKey),
                      "The once-ever flag persisted.")

        // Session 2: a fresh engine + a fresh model over the same defaults (a
        // relaunch). The capstone is still latched (the ledger is a ratchet),
        // but the celebration must NEVER play again.
        let engine2 = try makeCapstoneEngine()
        XCTAssertTrue(engine2.isUnlocked("capstone_all"),
                      "The capstone ledger survives relaunch (ratchet).")
        let model2 = CapstoneCelebrationModel(defaults: defaults)
        XCTAssertTrue(model2.hasPresented,
                      "The fresh model loads the persisted once-ever flag.")
        XCTAssertFalse(model2.celebrateIfEarned(engine: engine2),
                       "A relaunch with the capstone earned must not replay the moment.")
        XCTAssertNil(model2.pending)
    }

    /// `markPresented()` is idempotent — calling it when already presented does
    /// not thrash the flag or crash.
    func testMarkPresentedIsIdempotent() throws {
        let model = CapstoneCelebrationModel(defaults: defaults)
        model.markPresented()
        XCTAssertTrue(model.hasPresented)
        model.markPresented()   // again
        XCTAssertTrue(model.hasPresented)
        XCTAssertNil(model.pending)
    }

    // MARK: - Display-only (never-mint / ledger untouched)

    /// Arming the celebration reads the ledger and mutates only the model's own
    /// presentation state — it never latches, revokes, or restamps a trophy
    /// (D1 never-mint; the model is display-only).
    func testCelebrateDoesNotMutateTheLedger() throws {
        let engine = try makeCapstoneEngine()
        latchWholeBase(engine)
        let unlocksBefore = engine.unlockedIDs
        let capstoneDateBefore = engine.unlockDate(for: "capstone_all")

        let model = CapstoneCelebrationModel(defaults: defaults)
        _ = model.celebrateIfEarned(engine: engine)
        model.markPresented()

        XCTAssertEqual(engine.unlockedIDs, unlocksBefore,
                       "The celebration must not change the unlock set.")
        XCTAssertEqual(engine.unlockDate(for: "capstone_all"), capstoneDateBefore,
                       "The celebration must not restamp the capstone.")
    }

    // MARK: - GameState wiring

    /// GameState owns the model on its own ObservableObject and it starts inert
    /// on a fresh save (no capstone earned → nothing armed, nothing presented).
    func testGameStateExposesInertCelebrationOnFreshSave() {
        let gs = TrophyTestHarness.makeGameState(defaults: defaults)
        XCTAssertNil(gs.capstoneCelebration.pending,
                     "A fresh save arms no capstone moment.")
        XCTAssertFalse(gs.capstoneCelebration.hasPresented)
    }

    /// A standard (non-capstone) live unlock routes to the small toast queue and
    /// NEVER arms the capstone moment — "standard unlocks stay small" (the
    /// split enforced in GameState.routeUnlockedToPresentation).
    func testStandardUnlockDoesNotArmCapstoneMoment() {
        let gs = TrophyTestHarness.makeGameState(defaults: defaults)
        gs.recordMinigameResult(modeID: "snake", difficulty: .normal,
                                won: true, score: 1, basePayout: 0)   // arcade_first_win, etc.

        XCTAssertNotNil(gs.trophyToasts.presented,
                        "A standard unlock surfaces as a small banner…")
        XCTAssertNil(gs.capstoneCelebration.pending,
                     "…and never escalates to the capstone full-screen moment.")
    }
}
