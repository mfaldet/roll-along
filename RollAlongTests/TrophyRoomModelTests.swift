//
//  TrophyRoomModelTests.swift
//  RollAlongTests
//
//  S2-T3 acceptance (headless): the Trophy Room's catalog→row data model is
//  pure logic proven here WITHOUT instantiating a View
//  (docs/trophies/sprint-plan.md §2 S2-T3; design.md §7).
//
//  Verified here:
//  • (a) every NON-secret trophy renders with the correct
//    locked/unlocked/progress state pulled from the engine;
//  • (b) a locked SECRET trophy leaks NO title / description / criteria —
//    it masks to "???" + a generic subtitle and suppresses its progress;
//  • (c) overall completion % and per-grade counts are computed correctly;
//  • (d) the model reads the ENGINE, not GameState (it is constructed from
//    a bare `TrophyEngine` with no GameState in scope);
//  • grouping is play-path ordered with no empty sections; masked secrets
//    reveal fully on unlock; the rarity slot is the "—" S3 placeholder.
//
//  The model is a plain value type, so this case is not @MainActor.
//

import XCTest
@testable import RollAlong

final class TrophyRoomModelTests: XCTestCase {

    // MARK: - Fixtures

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyRoomModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// A fresh engine over the REAL bundled 89-trophy catalog, backed by a
    /// throwaway defaults suite (the GameStateTests injected-defaults
    /// pattern). No GameState anywhere — this is the (d) acceptance proof:
    /// the model derives purely from `TrophyEngine`.
    private func makeEngine() throws -> TrophyEngine {
        TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                     defaults: defaults,
                     now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
    }

    /// The real catalog, for cross-checking expected copy/counts.
    private func loadCatalog() throws -> TrophyCatalog {
        try TrophyCatalog.load(bundle: .main)
    }

    private func row(_ model: TrophyRoomModel, id: String) -> TrophyRoomRow? {
        model.sections.flatMap(\.rows).first { $0.id == id }
    }

    // MARK: - (d) The model reads the engine, not GameState

    func testModelDerivesPurelyFromEngine() throws {
        // Constructed with only a TrophyEngine in scope — there is no
        // GameState in this test at all, so the model cannot be reading it.
        let engine = try makeEngine()
        let model = TrophyRoomModel(engine: engine)

        let catalog = try loadCatalog()
        let rowCount = model.sections.reduce(0) { $0 + $1.rows.count }
        XCTAssertEqual(rowCount, catalog.trophies.count,
                       "Every catalog trophy must appear exactly once as a row.")
        XCTAssertEqual(model.summary.total, catalog.trophies.count)
    }

    // MARK: - (a) Non-secret locked/unlocked/progress state from the engine

    func testNonSecretLockedRowShowsRealCopyAndProgress() throws {
        let engine = try makeEngine()
        // `climb_first_clear` wants climb_highest_unlocked >= 2. Push 1 so it
        // stays LOCKED but has real progress toward the threshold.
        engine.record(.climbHighestUnlocked, value: 1)

        let model = TrophyRoomModel(engine: engine)
        let r = try XCTUnwrap(row(model, id: "climb_first_clear"))

        XCTAssertFalse(r.isUnlocked, "Threshold not met → locked.")
        XCTAssertFalse(r.isMasked, "A non-secret trophy is never masked.")

        let def = try XCTUnwrap(loadCatalog().trophy(withID: "climb_first_clear"))
        XCTAssertEqual(r.displayTitle, def.title, "Locked non-secret shows its real title.")
        XCTAssertEqual(r.displayDescription, def.lockedDescription,
                       "Locked non-secret shows the real objective text.")
        XCTAssertNil(r.unlockDate, "A locked trophy has no unlock date.")

        // Progress is the engine's fraction: 1 of threshold 2 = 0.5.
        let p = try XCTUnwrap(r.progress, "A locked cumulative trophy exposes progress.")
        XCTAssertEqual(p, 0.5, accuracy: 0.001)
        XCTAssertEqual(p, try XCTUnwrap(engine.progressFraction(for: "climb_first_clear")),
                       accuracy: 0.0001, "Row progress must match the engine.")
    }

    func testNonSecretUnlockedRowReflectsEngineLatch() throws {
        let engine = try makeEngine()
        // Push 2 → `climb_first_clear` (>=2) latches.
        engine.record(.climbHighestUnlocked, value: 2)
        XCTAssertTrue(engine.isUnlocked("climb_first_clear"))

        let model = TrophyRoomModel(engine: engine)
        let r = try XCTUnwrap(row(model, id: "climb_first_clear"))

        XCTAssertTrue(r.isUnlocked)
        XCTAssertFalse(r.isMasked)
        let def = try XCTUnwrap(loadCatalog().trophy(withID: "climb_first_clear"))
        XCTAssertEqual(r.displayTitle, def.title)
        XCTAssertEqual(r.displayDescription, def.unlockedDescription,
                       "Unlocked shows the celebration copy.")
        XCTAssertNil(r.progress, "An unlocked trophy shows no progress bar.")
        XCTAssertEqual(r.unlockDate, engine.unlockDate(for: "climb_first_clear"),
                       "Row carries the engine's unlock timestamp.")
    }

    /// Sweep: EVERY non-secret trophy's row state matches the engine, both
    /// before and after a broad unlock push.
    func testEveryNonSecretRowMatchesEngineState() throws {
        let engine = try makeEngine()
        // Latch a spread of trophies across categories.
        engine.record(.climbHighestUnlocked, value: 260)   // through level_250
        engine.record(.climbTotalStars, value: 200)
        engine.record(.tracksCompleted, value: 3)
        engine.record(.minigamesPlayed, value: 12)

        let model = TrophyRoomModel(engine: engine)
        let catalog = try loadCatalog()

        for def in catalog.trophies where !def.isSecret {
            let r = try XCTUnwrap(row(model, id: def.id),
                                  "Non-secret \(def.id) must have a row.")
            XCTAssertEqual(r.isUnlocked, engine.isUnlocked(def.id),
                           "\(def.id) lock state must match the engine.")
            XCTAssertFalse(r.isMasked, "\(def.id) is not secret; never masked.")
            XCTAssertEqual(r.displayTitle, def.title,
                           "\(def.id) shows its real title (never masked).")
            if r.isUnlocked {
                XCTAssertNil(r.progress, "\(def.id) unlocked → no progress bar.")
            }
        }
    }

    // MARK: - (b) Secret masking leaks nothing pre-unlock

    func testLockedSecretTrophyLeaksNothing() throws {
        let engine = try makeEngine()   // nothing unlocked → all secrets locked
        let model = TrophyRoomModel(engine: engine)
        let catalog = try loadCatalog()

        let secretDefs = catalog.trophies.filter(\.isSecret)
        XCTAssertFalse(secretDefs.isEmpty, "The v1 catalog has secret trophies.")

        for def in secretDefs {
            let r = try XCTUnwrap(row(model, id: def.id))
            XCTAssertTrue(r.isMasked, "\(def.id) is a locked secret → masked.")
            XCTAssertFalse(r.isUnlocked)

            // Title/description must NOT be the real copy.
            XCTAssertEqual(r.displayTitle, TrophyRoomModel.maskedTitle)
            XCTAssertNotEqual(r.displayTitle, def.title,
                              "Masked row must not show the real title.")
            XCTAssertNotEqual(r.displayDescription, def.lockedDescription,
                              "Masked row must not show the real objective.")
            XCTAssertNotEqual(r.displayDescription, def.unlockedDescription)
            XCTAssertEqual(r.displayDescription, TrophyRoomModel.maskedSubtitle)

            // No criteria may leak: the real locked description names the
            // objective, so assert none of its distinctive words survive.
            let leakWords = def.lockedDescription
                .split(whereSeparator: { !$0.isLetter })
                .map { $0.lowercased() }
                .filter { $0.count >= 5 }
            let shown = (r.displayTitle + " " + r.displayDescription).lowercased()
            for word in leakWords {
                XCTAssertFalse(shown.contains(word),
                               "Masked row leaks criteria word '\(word)' from \(def.id).")
            }

            // Progress is suppressed so the bar can't leak "how close".
            XCTAssertNil(r.progress, "A masked secret must not expose progress.")

            // The accessibility label must not speak the real title either.
            XCTAssertFalse(r.accessibilityLabel.lowercased().contains(def.title.lowercased()),
                           "VoiceOver label leaks the hidden title of \(def.id).")
        }
    }

    func testSecretTrophyRevealsFullyOnUnlock() throws {
        let engine = try makeEngine()
        // `whimsy_gravity_check` wants level_one_falls >= 1.
        engine.record(.levelOneFalls, value: 1)
        XCTAssertTrue(engine.isUnlocked("whimsy_gravity_check"))

        let model = TrophyRoomModel(engine: engine)
        let r = try XCTUnwrap(row(model, id: "whimsy_gravity_check"))

        XCTAssertFalse(r.isMasked, "Unlocking a secret reveals it.")
        XCTAssertTrue(r.isUnlocked)
        let def = try XCTUnwrap(loadCatalog().trophy(withID: "whimsy_gravity_check"))
        XCTAssertEqual(r.displayTitle, def.title, "Now shows the real title.")
        XCTAssertEqual(r.displayDescription, def.unlockedDescription,
                       "Now shows the real celebration copy.")
    }

    // MARK: - (c) Completion % + per-grade counts

    func testCompletionAndGradeCountsAtZero() throws {
        let engine = try makeEngine()
        let model = TrophyRoomModel(engine: engine)
        let catalog = try loadCatalog()

        XCTAssertEqual(model.summary.unlocked, 0)
        XCTAssertEqual(model.summary.total, catalog.trophies.count)
        XCTAssertEqual(model.summary.completionPercent, 0)
        XCTAssertEqual(model.summary.completionFraction, 0, accuracy: 0.0001)
        XCTAssertFalse(model.summary.capstoneUnlocked)

        // Per-grade totals cover the whole catalog and match the catalog's
        // own tier histogram; earned is 0 across the board.
        var expectedTotals: [TrophyTier: Int] = [:]
        for t in catalog.trophies { expectedTotals[t.tier, default: 0] += 1 }
        for g in model.summary.gradeCounts {
            XCTAssertEqual(g.earned, 0, "\(g.gradeName) earned should be 0.")
            XCTAssertEqual(g.total, expectedTotals[g.tier] ?? 0,
                           "\(g.gradeName) total must match the catalog.")
        }
        // Every ladder rung is represented, in ascending order.
        XCTAssertEqual(model.summary.gradeCounts.map(\.tier),
                       TrophyTier.allCases.sorted(),
                       "Grade counts cover every rung in ladder order.")
    }

    func testCompletionPercentMatchesUnlockedFraction() throws {
        let engine = try makeEngine()
        let catalog = try loadCatalog()

        // Unlock a known ladder of climb trophies by pushing the metric high.
        engine.record(.climbHighestUnlocked, value: 260)  // first/10/50/100/250
        let expectedUnlocked = catalog.trophies.filter { engine.isUnlocked($0.id) }.count
        XCTAssertGreaterThan(expectedUnlocked, 0)

        let model = TrophyRoomModel(engine: engine)
        XCTAssertEqual(model.summary.unlocked, expectedUnlocked,
                       "Header unlocked count matches the engine ledger.")

        let expectedPct = Int((Double(expectedUnlocked) / Double(catalog.trophies.count) * 100).rounded())
        XCTAssertEqual(model.summary.completionPercent, expectedPct)

        // Sum of per-grade earned equals the overall unlocked count.
        let gradeEarnedSum = model.summary.gradeCounts.reduce(0) { $0 + $1.earned }
        XCTAssertEqual(gradeEarnedSum, model.summary.unlocked,
                       "Per-grade earned counts sum to the overall unlocked total.")
        // And sum of per-grade totals equals the catalog size.
        let gradeTotalSum = model.summary.gradeCounts.reduce(0) { $0 + $1.total }
        XCTAssertEqual(gradeTotalSum, catalog.trophies.count)
    }

    func testCapstoneFlagTracksEngine() throws {
        let engine = try makeEngine()
        XCTAssertFalse(TrophyRoomModel(engine: engine).summary.capstoneUnlocked)

        // The capstone latches via the ledger cascade once its whole required
        // base is earned. Rather than reproduce that here, assert the flag is
        // the engine's `isUnlocked(capstone)` — the model's only source.
        let cap = try loadCatalog().capstone
        let model = TrophyRoomModel(engine: engine)
        XCTAssertEqual(model.summary.capstoneUnlocked, engine.isUnlocked(cap.id))
    }

    // MARK: - Grouping + ordering

    func testSectionsAreInPlayPathOrderWithNoEmpties() throws {
        let engine = try makeEngine()
        let model = TrophyRoomModel(engine: engine)

        // No empty sections.
        for s in model.sections {
            XCTAssertFalse(s.rows.isEmpty, "\(s.category) section must not be empty.")
        }
        // Strictly increasing play-path order.
        let orders = model.sections.map { $0.category.roomSortOrder }
        XCTAssertEqual(orders, orders.sorted(), "Sections must be play-path ordered.")
        XCTAssertEqual(Set(model.sections.map(\.category)).count, model.sections.count,
                       "Each category appears at most once.")

        // Every row in a section belongs to that section's category.
        for s in model.sections {
            for r in s.rows {
                XCTAssertEqual(r.category, s.category)
            }
        }
    }

    func testEverySectionCaptionMatchesItsRows() throws {
        let engine = try makeEngine()
        engine.record(.climbHighestUnlocked, value: 60)  // some climb unlocks
        let model = TrophyRoomModel(engine: engine)

        for s in model.sections {
            XCTAssertEqual(s.unlockedCount, s.rows.filter(\.isUnlocked).count)
            XCTAssertEqual(s.total, s.rows.count)
        }
    }

    // MARK: - Rarity slot is the S2 placeholder

    func testEveryRowRarityIsThePlaceholder() throws {
        let engine = try makeEngine()
        engine.record(.climbHighestUnlocked, value: 300)  // mix locked+unlocked
        let model = TrophyRoomModel(engine: engine)

        for r in model.sections.flatMap(\.rows) {
            XCTAssertEqual(r.rarityLabel, TrophyRoomModel.rarityPlaceholder,
                           "\(r.id): rarity slot stays '—' until S3-T4 feeds it.")
            // Binding Diamond rider: the placeholder never uses diamond glyphs.
            XCTAssertFalse(r.rarityLabel.contains("diamond"))
        }
    }

    // MARK: - Diamond-grade rider surfaced through the row

    func testDiamondGradeRowUsesGradeGlyphNotCosmeticGem() throws {
        let engine = try makeEngine()
        let model = TrophyRoomModel(engine: engine)
        let catalog = try loadCatalog()

        // Find a diamond-tier row and assert its glyph is the grade glyph
        // (violet laurel), NOT the cyan cosmetic `diamond.fill` gem.
        let diamondDef = try XCTUnwrap(catalog.trophies.first { $0.tier == .diamond })
        let r = try XCTUnwrap(row(model, id: diamondDef.id))
        XCTAssertEqual(r.gradeGlyph, TrophyGradeStyle.forTier(.diamond).glyph)
        XCTAssertNotEqual(r.gradeGlyph,
                          TrophyGradeStyle.cosmeticDiamondTreatment.glyph,
                          "The Diamond GRADE row must not borrow the cosmetic gem (design.md §2 R2).")
    }
}
