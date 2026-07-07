//
//  TrophyShowcaseModelTests.swift
//  RollAlongTests
//
//  S2-T4 acceptance (headless): the Profile Trophy card's data model is pure
//  logic proven here WITHOUT instantiating a View
//  (docs/trophies/sprint-plan.md §2 S2-T4; design.md §7 "Profile showcase").
//
//  Verified here:
//  • (a) the card shows PERSISTED unlocks with the engine's timestamps —
//    every showcase entry is an earned trophy carrying its ledger unlockDate;
//  • (b) THE RATCHET: driving a real GameState, unlocking a trophy, then
//    calling `resetProgress()` AND `liquidateCoinCosmetics()` leaves the
//    trophy still shown (nothing un-earns) — the acceptance headline;
//  • ordering: most-recently-earned first, legacy-backfill unlocks sink,
//    the pin seam floats pinned ids to the front and fabricates nothing;
//  • only EARNED trophies appear (a masked secret never leaks into the card);
//  • per-grade counts + capstone flag mirror the engine;
//  • the Diamond GRADE entry uses the grade glyph, not the cosmetic gem.
//
//  Model + entries are plain value types, so this case is not @MainActor for
//  the pure-model tests; the two GameState-driven ratchet tests run on the
//  main actor (GameState is @MainActor).
//

import XCTest
@testable import RollAlong

final class TrophyShowcaseModelTests: XCTestCase {

    // MARK: - Fixtures

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyShowcaseModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// A fresh engine over the REAL bundled 89-trophy catalog, backed by a
    /// throwaway defaults suite. Fixed clock so unlock timestamps are
    /// deterministic. No GameState — proves the model derives purely from the
    /// engine for the pure-model tests.
    private func makeEngine(now: @escaping () -> Date =
                            { Date(timeIntervalSinceReferenceDate: 800_000_000) }) throws -> TrophyEngine {
        TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                     defaults: defaults,
                     now: now)
    }

    private func loadCatalog() throws -> TrophyCatalog {
        try TrophyCatalog.load(bundle: .main)
    }

    // MARK: - (a) Persisted unlocks with the engine's timestamps

    func testShowcaseShowsPersistedUnlocksWithEngineTimestamps() throws {
        let engine = try makeEngine()
        // Push climb high enough to latch a spread of climb trophies.
        engine.record(.climbHighestUnlocked, value: 60)   // first/10/50 clears

        let earnedIDs = try loadCatalog().trophies
            .map(\.id).filter { engine.isUnlocked($0) }
        XCTAssertFalse(earnedIDs.isEmpty, "Expected several climb unlocks.")

        let model = TrophyShowcaseModel(engine: engine)

        XCTAssertEqual(model.earned, earnedIDs.count,
                       "Card's earned count mirrors the engine ledger.")
        XCTAssertFalse(model.isEmpty)

        // Every showcase entry is a persisted unlock carrying the engine's
        // exact timestamp.
        for entry in model.showcase {
            XCTAssertTrue(engine.isUnlocked(entry.id),
                          "\(entry.id) is on stage but not unlocked in the engine.")
            XCTAssertEqual(entry.unlockDate, engine.unlockDate(for: entry.id),
                           "\(entry.id) must carry the engine's unlock timestamp.")
            // Real (revealed) copy — a masked "???" never reaches an entry.
            let def = try XCTUnwrap(loadCatalog().trophy(withID: entry.id))
            XCTAssertEqual(entry.title, def.title)
            XCTAssertEqual(entry.subtitle, def.unlockedDescription)
        }
    }

    // MARK: - (b) THE RATCHET — nothing un-earns after reset / liquidation

    @MainActor
    func testRatchet_TrophyStaysAfterResetProgress() throws {
        let gs = GameState(defaults: defaults)

        // Unlock a real trophy through the engine (climb_first_clear: >= 2).
        gs.trophyEngine.record(.climbHighestUnlocked, value: 2)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("climb_first_clear"))

        let before = TrophyShowcaseModel(engine: gs.trophyEngine)
        XCTAssertTrue(before.showcase.contains { $0.id == "climb_first_clear" },
                      "Precondition: the unlock is on the card.")
        let stampBefore = gs.trophyEngine.unlockDate(for: "climb_first_clear")

        // Wipe level progress — the stat the OLD badge wall keyed off of.
        gs.resetProgress()

        let after = TrophyShowcaseModel(engine: gs.trophyEngine)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("climb_first_clear"),
                      "resetProgress must NOT revoke a latched trophy.")
        XCTAssertTrue(after.showcase.contains { $0.id == "climb_first_clear" },
                      "The trophy must still be shown after resetProgress().")
        XCTAssertEqual(after.earned, before.earned,
                       "resetProgress un-earns nothing.")
        XCTAssertEqual(gs.trophyEngine.unlockDate(for: "climb_first_clear"), stampBefore,
                       "The unlock timestamp is preserved across a reset.")
    }

    @MainActor
    func testRatchet_TrophyStaysAfterLiquidation() throws {
        let gs = GameState(defaults: defaults)

        gs.trophyEngine.record(.climbHighestUnlocked, value: 2)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("climb_first_clear"))
        let earnedBefore = TrophyShowcaseModel(engine: gs.trophyEngine).earned

        // Selling back every sellable cosmetic must not touch the ledger.
        gs.liquidateCoinCosmetics()

        let after = TrophyShowcaseModel(engine: gs.trophyEngine)
        XCTAssertTrue(gs.trophyEngine.isUnlocked("climb_first_clear"),
                      "liquidateCoinCosmetics must NOT revoke a latched trophy.")
        XCTAssertTrue(after.showcase.contains { $0.id == "climb_first_clear" },
                      "The trophy must still be shown after liquidation.")
        XCTAssertEqual(after.earned, earnedBefore,
                       "Liquidation un-earns nothing.")
    }

    @MainActor
    func testRatchet_TrophyStaysAfterResetThenLiquidation() throws {
        // The acceptance's exact sequence: unlock → reset → liquidate → assert.
        let gs = GameState(defaults: defaults)
        gs.trophyEngine.record(.climbHighestUnlocked, value: 60)
        let earnedBefore = TrophyShowcaseModel(engine: gs.trophyEngine).earned
        XCTAssertGreaterThan(earnedBefore, 0)

        gs.resetProgress()
        gs.liquidateCoinCosmetics()

        let after = TrophyShowcaseModel(engine: gs.trophyEngine)
        XCTAssertEqual(after.earned, earnedBefore,
                       "Neither reset nor liquidation may un-earn any trophy.")
        XCTAssertFalse(after.isEmpty)
    }

    // MARK: - Ordering: recent-first, legacy sinks

    func testShowcaseOrdersMostRecentFirst() throws {
        // A mutable clock so successive unlocks get increasing timestamps.
        var t = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let engine = try makeEngine(now: { t })

        // Earn climb_first_clear (>=2) at t0, then a later trophy at t1.
        engine.record(.climbHighestUnlocked, value: 2)      // climb_first_clear @ t0
        t = t.addingTimeInterval(3600)
        engine.record(.climbTotalStars, value: 25)          // climb_stars_25 @ t1 (later)

        let model = TrophyShowcaseModel(engine: engine)
        XCTAssertGreaterThanOrEqual(model.showcase.count, 2,
                                    "Fixture must earn two distinct trophies.")

        // The later unlock sorts ahead of the earlier one.
        let dates = model.showcase.map(\.unlockDate)
        XCTAssertEqual(dates, dates.sorted(by: >),
                       "Showcase is ordered most-recently-earned first.")
    }

    func testLegacyBackfillUnlocksSinkBelowRealUnlocks() throws {
        let engine = try makeEngine()
        // Backfill grants a batch stamped at the legacy sentinel (earliest).
        var snap: TrophyEngine.MetricSnapshot = [:]
        snap[.climbHighestUnlocked] = 60
        engine.backfill(from: snap)
        let legacyCount = try loadCatalog().trophies.filter { engine.isUnlocked($0.id) }.count
        XCTAssertGreaterThan(legacyCount, 0)

        // Now earn a fresh trophy at a real (later) time. climb_stars_25 wants
        // >= 25 total stars — not covered by the climb-level backfill above.
        engine.record(.climbTotalStars, value: 25)
        XCTAssertTrue(engine.isUnlocked("climb_stars_25"),
                      "Precondition: a fresh non-legacy unlock landed.")

        let model = TrophyShowcaseModel(engine: engine)
        // The freshly-earned (non-legacy) entry must lead the showcase.
        let first = try XCTUnwrap(model.showcase.first)
        XCTAssertFalse(first.isLegacyUnlock,
                       "A real unlock must lead ahead of legacy backfill entries.")
        XCTAssertEqual(first.id, "climb_stars_25")
    }

    // MARK: - Pin seam floats pinned ids first, fabricates nothing

    func testPinnedIDsFloatToFrontOfShowcase() throws {
        var t = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let engine = try makeEngine(now: { t })
        engine.record(.climbHighestUnlocked, value: 2)      // climb_first_clear @ t0
        t = t.addingTimeInterval(3600)
        engine.record(.climbTotalStars, value: 25)          // climb_stars_25 @ t1 (later)
        XCTAssertTrue(engine.isUnlocked("climb_stars_25"))

        // Pin the OLDER trophy: it must jump ahead of the newer one despite
        // being earned earlier.
        let model = TrophyShowcaseModel(engine: engine, pinnedIDs: ["climb_first_clear"])
        XCTAssertEqual(model.showcase.first?.id, "climb_first_clear",
                       "A pinned trophy leads the showcase regardless of recency.")
    }

    func testUnearnedOrUnknownPinsFabricateNothing() throws {
        let engine = try makeEngine()
        engine.record(.climbHighestUnlocked, value: 2)      // one real unlock

        // Pin an id that is NOT earned + a bogus id: neither may appear.
        let model = TrophyShowcaseModel(
            engine: engine,
            pinnedIDs: ["capstone_all", "totally_made_up_id"])

        XCTAssertFalse(model.showcase.contains { $0.id == "capstone_all" },
                       "An unearned pin must not fabricate a showcase entry.")
        XCTAssertFalse(model.showcase.contains { $0.id == "totally_made_up_id" },
                       "An unknown pin id must not fabricate a showcase entry.")
        // Every entry is still a real earned trophy.
        for entry in model.showcase {
            XCTAssertTrue(engine.isUnlocked(entry.id))
        }
    }

    // MARK: - Only earned trophies appear (no masked-secret leak)

    func testShowcaseContainsOnlyEarnedTrophies() throws {
        let engine = try makeEngine()   // nothing unlocked
        let empty = TrophyShowcaseModel(engine: engine)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(empty.showcase.isEmpty, "No unlocks → nothing on stage.")

        // Now unlock a secret trophy; it should appear FULLY revealed (never
        // as a masked '???'), because only earned trophies become entries.
        engine.record(.levelOneFalls, value: 1)             // whimsy_gravity_check
        XCTAssertTrue(engine.isUnlocked("whimsy_gravity_check"))

        let model = TrophyShowcaseModel(engine: engine)
        let entry = try XCTUnwrap(model.showcase.first { $0.id == "whimsy_gravity_check" })
        let def = try XCTUnwrap(loadCatalog().trophy(withID: "whimsy_gravity_check"))
        XCTAssertEqual(entry.title, def.title, "An earned secret is revealed, not masked.")
        XCTAssertNotEqual(entry.title, "???")
    }

    func testShowcaseRespectsTheLimit() throws {
        let engine = try makeEngine()
        // Unlock a large spread so we exceed the showcase cap.
        engine.record(.climbHighestUnlocked, value: 300)
        engine.record(.climbTotalStars, value: 400)
        engine.record(.minigamesPlayed, value: 12)

        let model = TrophyShowcaseModel(engine: engine)
        XCTAssertGreaterThan(model.earned, TrophyShowcaseModel.showcaseLimit,
                             "Fixture should earn more than the cap.")
        XCTAssertLessThanOrEqual(model.showcase.count, TrophyShowcaseModel.showcaseLimit,
                                 "Showcase never exceeds its cap.")
    }

    // MARK: - Per-grade counts + capstone flag mirror the engine

    func testGradeCountsAndCompletionMirrorEngine() throws {
        let engine = try makeEngine()
        engine.record(.climbHighestUnlocked, value: 60)

        let catalog = try loadCatalog()
        let model = TrophyShowcaseModel(engine: engine)

        // Totals cover the whole catalog, in ladder order.
        XCTAssertEqual(model.total, catalog.trophies.count)
        XCTAssertEqual(model.gradeCounts.map(\.tier), TrophyTier.allCases.sorted())

        var expectedTotals: [TrophyTier: Int] = [:]
        for t in catalog.trophies { expectedTotals[t.tier, default: 0] += 1 }
        for g in model.gradeCounts {
            XCTAssertEqual(g.total, expectedTotals[g.tier] ?? 0,
                           "\(g.gradeName) total mirrors the catalog histogram.")
        }
        // Per-grade earned sums to the overall earned; earned mirrors engine.
        let gradeEarnedSum = model.gradeCounts.reduce(0) { $0 + $1.earned }
        XCTAssertEqual(gradeEarnedSum, model.earned)
        let engineEarned = catalog.trophies.filter { engine.isUnlocked($0.id) }.count
        XCTAssertEqual(model.earned, engineEarned)

        // Completion percent matches the fraction.
        let expectedPct = Int((Double(engineEarned) / Double(catalog.trophies.count) * 100).rounded())
        XCTAssertEqual(model.completionPercent, expectedPct)
    }

    func testCapstoneFlagTracksEngine() throws {
        let engine = try makeEngine()
        let model = TrophyShowcaseModel(engine: engine)
        let cap = try loadCatalog().capstone
        XCTAssertEqual(model.capstoneUnlocked, engine.isUnlocked(cap.id))
        XCTAssertFalse(model.capstoneUnlocked, "Fresh engine: no capstone.")
    }

    func testEmptyStateAtZeroUnlocks() throws {
        let engine = try makeEngine()
        let model = TrophyShowcaseModel(engine: engine)
        XCTAssertEqual(model.earned, 0)
        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.completionPercent, 0)
        XCTAssertTrue(model.showcase.isEmpty)
        // Grade strip is still fully populated (stable layout).
        XCTAssertEqual(model.gradeCounts.count, TrophyTier.allCases.count)
        for g in model.gradeCounts { XCTAssertEqual(g.earned, 0) }
    }

    // MARK: - Diamond-grade rider surfaced through the entry

    func testDiamondGradeEntryUsesGradeGlyphNotCosmeticGem() throws {
        let engine = try makeEngine()
        let catalog = try loadCatalog()

        // Force-earn every trophy via a broad snapshot so a diamond-tier entry
        // is guaranteed on the card. Use a very high push across metrics.
        engine.record(.climbHighestUnlocked, value: 100_000)
        engine.record(.climbTotalStars, value: 100_000)

        // Find any earned diamond-tier trophy; if none earned by climb alone,
        // fall back to asserting the entry TYPE's glyph source directly.
        let model = TrophyShowcaseModel(engine: engine, pinnedIDs:
            catalog.trophies.filter { $0.tier == .diamond }.map(\.id))

        if let diamondEntry = model.showcase.first(where: { $0.tier == .diamond }) {
            XCTAssertEqual(diamondEntry.gradeGlyph, TrophyGradeStyle.forTier(.diamond).glyph)
            XCTAssertNotEqual(diamondEntry.gradeGlyph,
                              TrophyGradeStyle.cosmeticDiamondTreatment.glyph,
                              "The Diamond GRADE entry must not borrow the cosmetic gem (design.md §2 R2).")
        } else {
            // No diamond earned by this fixture — assert the invariant on a
            // constructed entry so the rider is still covered.
            let entry = TrophyShowcaseEntry(
                id: "x", tier: .diamond, title: "t", subtitle: "s",
                unlockDate: Date())
            XCTAssertEqual(entry.gradeGlyph, TrophyGradeStyle.forTier(.diamond).glyph)
            XCTAssertNotEqual(entry.gradeGlyph,
                              TrophyGradeStyle.cosmeticDiamondTreatment.glyph)
        }
    }
}
