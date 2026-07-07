//
//  TrophyPinModelTests.swift
//  RollAlongTests
//
//  S2-T7 acceptance (headless): trophy pinning + chase chips are pure model
//  logic, proven here WITHOUT instantiating a View
//  (docs/trophies/sprint-plan.md §2 S2-T7; design.md §7 "Pinning").
//
//  Verified here (the S2-T7 acceptance points that are headlessly testable):
//  • pins PERSIST across a reload — a fresh `TrophyPinStore` over the same
//    defaults round-trips the `ra_trophyPins` list, in order;
//  • the CAP of 3 is enforced — a 4th pin is refused, order untouched;
//  • a chip's PROGRESS comes from the engine's `progressFraction` API and
//    UPDATES when the underlying stat advances;
//  • chip filtering: an earned pin retires from the strip, an unknown id
//    fabricates nothing, a masked secret pin leaks neither objective nor
//    closeness.
//
//  The pin store is an ObservableObject with no main-actor work; the chip
//  model is a plain value type — neither needs @MainActor.
//

import XCTest
@testable import RollAlong

final class TrophyPinModelTests: XCTestCase {

    // MARK: - Fixtures

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyPinModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// A fresh engine over the REAL bundled catalog, backed by the throwaway
    /// defaults suite (the GameStateTests injected-defaults pattern).
    private func makeEngine() throws -> TrophyEngine {
        TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                     defaults: defaults,
                     now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
    }

    private func makeStore() -> TrophyPinStore {
        TrophyPinStore(defaults: defaults)
    }

    // MARK: - Persistence round-trip (pins survive a reload)

    func testPinsPersistAcrossReload() {
        let store = makeStore()
        XCTAssertTrue(store.pin("a"))
        XCTAssertTrue(store.pin("b"))
        XCTAssertEqual(store.pinnedIDs, ["a", "b"])

        // A brand-new store over the SAME defaults is a "relaunch".
        let reloaded = TrophyPinStore(defaults: defaults)
        XCTAssertEqual(reloaded.pinnedIDs, ["a", "b"],
                       "Pins must round-trip through ra_trophyPins, in order.")
    }

    func testPersistedValueIsWrittenUnderTheDocumentedKey() {
        let store = makeStore()
        store.pin("x")
        store.pin("y")
        // The raw key is what S3/showcase/reload all read — assert it directly.
        let raw = defaults.array(forKey: TrophyPinStore.pinsKey) as? [String]
        XCTAssertEqual(raw, ["x", "y"])
        XCTAssertEqual(TrophyPinStore.pinsKey, "ra_trophyPins")
    }

    func testUnpinPersistsAndReloads() {
        let store = makeStore()
        store.pin("a"); store.pin("b"); store.pin("c")
        XCTAssertTrue(store.unpin("b"))
        XCTAssertEqual(store.pinnedIDs, ["a", "c"], "Unpin preserves the rest's order.")

        let reloaded = TrophyPinStore(defaults: defaults)
        XCTAssertEqual(reloaded.pinnedIDs, ["a", "c"])
    }

    // MARK: - Cap of 3 enforced

    func testCapOfThreeRefusesAFourthPin() {
        let store = makeStore()
        XCTAssertEqual(TrophyPinStore.maxPins, 3)
        XCTAssertTrue(store.pin("a"))
        XCTAssertTrue(store.pin("b"))
        XCTAssertTrue(store.pin("c"))
        XCTAssertFalse(store.canPinMore, "Three pins fills the cap.")
        XCTAssertEqual(store.freeSlots, 0)

        // The 4th pin is refused; the existing three are untouched and ordered.
        XCTAssertFalse(store.pin("d"), "A 4th pin must be refused.")
        XCTAssertEqual(store.pinnedIDs, ["a", "b", "c"])

        // The refusal survives a reload (nothing extra was persisted).
        let reloaded = TrophyPinStore(defaults: defaults)
        XCTAssertEqual(reloaded.pinnedIDs, ["a", "b", "c"])
    }

    func testToggleRefusedAtCapLeavesStateUnchanged() {
        let store = makeStore()
        store.pin("a"); store.pin("b"); store.pin("c")
        // Toggling a NEW id at the cap returns the unchanged (false) state and
        // adds nothing.
        XCTAssertFalse(store.toggle("d"))
        XCTAssertFalse(store.isPinned("d"))
        XCTAssertEqual(store.pinnedIDs, ["a", "b", "c"])
    }

    func testFreeSlotsCountsDown() {
        let store = makeStore()
        XCTAssertEqual(store.freeSlots, 3)
        store.pin("a"); XCTAssertEqual(store.freeSlots, 2)
        store.pin("b"); XCTAssertEqual(store.freeSlots, 1)
        store.pin("c"); XCTAssertEqual(store.freeSlots, 0)
        XCTAssertFalse(store.canPinMore)
    }

    // MARK: - Idempotency + toggle semantics

    func testPinIsIdempotentAndDeduped() {
        let store = makeStore()
        XCTAssertTrue(store.pin("a"))
        XCTAssertFalse(store.pin("a"), "Re-pinning the same id is a no-op.")
        XCTAssertEqual(store.pinnedIDs, ["a"], "No duplicate entry.")
    }

    func testToggleTogglesAndReportsResultingState() {
        let store = makeStore()
        XCTAssertTrue(store.toggle("a"), "Toggle on a free slot pins → true.")
        XCTAssertTrue(store.isPinned("a"))
        XCTAssertFalse(store.toggle("a"), "Toggle again unpins → false.")
        XCTAssertFalse(store.isPinned("a"))
        XCTAssertEqual(store.pinnedIDs, [])
    }

    func testUnpinOfUnpinnedIsNoOp() {
        let store = makeStore()
        store.pin("a")
        XCTAssertFalse(store.unpin("z"), "Unpinning an id that isn't pinned is a no-op.")
        XCTAssertEqual(store.pinnedIDs, ["a"])
    }

    // MARK: - Load-time sanitization (heals a legacy/corrupt value)

    func testLoadDedupesAndClampsAStoredValue() {
        // Simulate a hand-edited / older-build value: over the cap, with a dupe.
        defaults.set(["a", "a", "b", "c", "d", "e"], forKey: TrophyPinStore.pinsKey)
        let store = TrophyPinStore(defaults: defaults)
        XCTAssertEqual(store.pinnedIDs, ["a", "b", "c"],
                       "Load dedupes (first-wins) and clamps to the cap.")
    }

    // MARK: - pruneCompleted drops earned / unknown pins

    func testPruneCompletedDropsEarnedAndUnknownPins() throws {
        let engine = try makeEngine()
        let store = makeStore()

        // Pin one trophy we'll earn, one bogus id, and one still-locked real
        // trophy. `climb_level_10` wants climb_highest_unlocked >= 11;
        // `climb_level_1000` wants >= 1001 (stays locked here).
        store.pin("climb_level_10")      // we'll earn this
        store.pin("totally_made_up_id")  // unknown to the catalog
        store.pin("climb_level_1000")    // stays locked

        // Earn everything through climb_level_10 (push 11) but not level_1000.
        engine.record(.climbHighestUnlocked, value: 11)
        XCTAssertTrue(engine.isUnlocked("climb_level_10"))
        XCTAssertFalse(engine.isUnlocked("climb_level_1000"))

        store.pruneCompleted(using: engine)

        // Earned + unknown pins are gone; the still-locked pin stays; the store
        // persisted the pruned list.
        XCTAssertFalse(store.isPinned("climb_level_10"), "An earned pin is pruned.")
        XCTAssertFalse(store.isPinned("totally_made_up_id"), "An unknown pin is pruned.")
        XCTAssertTrue(store.isPinned("climb_level_1000"), "A still-locked pin survives.")
        XCTAssertEqual(store.pinnedIDs, ["climb_level_1000"])

        let reloaded = TrophyPinStore(defaults: defaults)
        XCTAssertEqual(reloaded.pinnedIDs, ["climb_level_1000"], "Prune persisted across reload.")
    }

    func testPruneKeepsAStillLockedPin() throws {
        let engine = try makeEngine()
        let store = makeStore()
        // `climb_100` wants a very high value; keep it locked.
        store.pin("climb_level_100")
        engine.record(.climbHighestUnlocked, value: 3)   // nowhere near climb_100
        XCTAssertFalse(engine.isUnlocked("climb_level_100"))

        store.pruneCompleted(using: engine)
        XCTAssertTrue(store.isPinned("climb_level_100"),
                      "A still-locked, still-cataloged pin survives a prune.")
    }

    func testPruneWithNothingToDropDoesNotThrashPersistence() throws {
        let engine = try makeEngine()
        let store = makeStore()
        store.pin("climb_level_100")   // locked, cataloged → nothing to prune
        store.pruneCompleted(using: engine)
        XCTAssertEqual(store.pinnedIDs, ["climb_level_100"])
    }

    // MARK: - Chase chips read the engine's progress API

    func testChipProgressComesFromEngineProgressFraction() throws {
        let engine = try makeEngine()
        // `climb_first_clear` wants climb_highest_unlocked >= 2. Push 1: it
        // stays LOCKED with real progress (1/2 = 0.5).
        engine.record(.climbHighestUnlocked, value: 1)

        let model = ChaseChipModel(engine: engine, pinnedIDs: ["climb_first_clear"])
        let chip = try XCTUnwrap(model.chips.first)

        XCTAssertEqual(chip.id, "climb_first_clear")
        let p = try XCTUnwrap(chip.progress)
        // The chip's progress IS the engine's fraction — same source, no
        // recomputation.
        XCTAssertEqual(p, try XCTUnwrap(engine.progressFraction(for: "climb_first_clear")),
                       accuracy: 0.0001, "Chip progress must come from the engine API.")
        XCTAssertEqual(p, 0.5, accuracy: 0.001)
        XCTAssertEqual(chip.progressCaption, "50%")
    }

    func testChipProgressUpdatesWhenTheStatAdvances() throws {
        let engine = try makeEngine()
        // `climb_50` wants climb_highest_unlocked >= 51. Push 25 → ~0.49.
        engine.record(.climbHighestUnlocked, value: 25)

        let before = ChaseChipModel(engine: engine, pinnedIDs: ["climb_level_50"])
        let pBefore = try XCTUnwrap(before.chips.first?.progress)

        // The stat advances (a run pushes the metric higher).
        engine.record(.climbHighestUnlocked, value: 40)

        let after = ChaseChipModel(engine: engine, pinnedIDs: ["climb_level_50"])
        let pAfter = try XCTUnwrap(after.chips.first?.progress)

        XCTAssertGreaterThan(pAfter, pBefore,
                             "A chip's progress rises as the underlying stat advances.")
        XCTAssertEqual(pAfter, try XCTUnwrap(engine.progressFraction(for: "climb_level_50")),
                       accuracy: 0.0001)
    }

    func testChipsPreservePinOrder() throws {
        let engine = try makeEngine()
        let model = ChaseChipModel(engine: engine,
                                   pinnedIDs: ["climb_level_50", "climb_level_10", "climb_level_100"])
        XCTAssertEqual(model.chips.map(\.id), ["climb_level_50", "climb_level_10", "climb_level_100"],
                       "Chips render in the player's pin order.")
    }

    // MARK: - Chip filtering (earned / unknown / masked)

    func testEarnedPinDropsFromTheStrip() throws {
        let engine = try makeEngine()
        // Earn climb_first_clear (>=2).
        engine.record(.climbHighestUnlocked, value: 2)
        XCTAssertTrue(engine.isUnlocked("climb_first_clear"))

        let model = ChaseChipModel(engine: engine, pinnedIDs: ["climb_first_clear"])
        XCTAssertTrue(model.isEmpty,
                      "An earned pin is no longer a chase — it drops from the strip.")
    }

    func testUnknownPinFabricatesNothing() throws {
        let engine = try makeEngine()
        let model = ChaseChipModel(engine: engine, pinnedIDs: ["totally_made_up_id"])
        XCTAssertTrue(model.isEmpty, "An unknown id produces no chip.")
    }

    func testMaskedSecretPinLeaksNothing() throws {
        let engine = try makeEngine()
        let catalog = try TrophyCatalog.load(bundle: .main)
        // Find a locked SECRET trophy to pin (a player could pin one only via a
        // stale/hand path, but the chip must still never leak it).
        let secret = try XCTUnwrap(catalog.trophies.first { $0.isSecret },
                                   "The v1 catalog has secret trophies.")
        XCTAssertFalse(engine.isUnlocked(secret.id))

        let model = ChaseChipModel(engine: engine, pinnedIDs: [secret.id])
        let chip = try XCTUnwrap(model.chips.first)

        XCTAssertTrue(chip.isMasked)
        XCTAssertEqual(chip.title, ChaseChipModel.maskedTitle)
        XCTAssertNotEqual(chip.title, secret.title, "Masked chip must not show the real title.")
        XCTAssertNil(chip.progress, "A masked chip suppresses progress (no closeness leak).")
        XCTAssertEqual(chip.progressCaption, "—")
        // The masked title tracks the Trophy Room's masking vocabulary.
        XCTAssertEqual(ChaseChipModel.maskedTitle, TrophyRoomModel.maskedTitle)
        // VoiceOver never speaks the hidden title.
        XCTAssertFalse(chip.accessibilityLabel.lowercased().contains(secret.title.lowercased()),
                       "The chip's a11y label leaks the hidden title.")
    }

    func testEmptyPinListMakesNoChips() throws {
        let engine = try makeEngine()
        let model = ChaseChipModel(engine: engine, pinnedIDs: [])
        XCTAssertTrue(model.isEmpty)
    }

    // MARK: - Diamond-grade rider surfaced through the chip

    func testDiamondGradeChipUsesGradeGlyphNotCosmeticGem() throws {
        let engine = try makeEngine()
        let catalog = try TrophyCatalog.load(bundle: .main)
        // Pin a locked diamond-tier trophy; its chip must wear the grade glyph
        // (violet laurel), NOT the cyan cosmetic `diamond.fill` gem.
        let diamond = try XCTUnwrap(catalog.trophies.first {
            $0.tier == .diamond && !engine.isUnlocked($0.id) && !$0.isSecret
        })
        let model = ChaseChipModel(engine: engine, pinnedIDs: [diamond.id])
        let chip = try XCTUnwrap(model.chips.first)
        XCTAssertEqual(chip.gradeGlyph, TrophyGradeStyle.forTier(.diamond).glyph)
        XCTAssertNotEqual(chip.gradeGlyph,
                          TrophyGradeStyle.cosmeticDiamondTreatment.glyph,
                          "The Diamond GRADE chip must not borrow the cosmetic gem (design.md §2 R2).")
    }

    // MARK: - GameState ownership + prune wiring (end-to-end through the funnel)

    func testGameStateOwnsPinStoreAndPrunesOnUnlock() {
        // A live unlock of a PINNED trophy must retire it via GameState's
        // routeUnlockedToPresentation → pruneCompleted path. Drive it through
        // the public GameState API only.
        let state = GameState(defaults: defaults,
                              now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
        state.trophyPins.pin("climb_first_clear")   // wants climb_highest_unlocked >= 2
        XCTAssertTrue(state.trophyPins.isPinned("climb_first_clear"))

        // Clearing level 2 advances highestUnlocked past the climb_first_clear
        // threshold via the real climb funnel; the pin should then prune.
        state.recordResult(level: 2, stars: 3, time: 30, coinIndices: [])

        XCTAssertTrue(state.trophyEngine.isUnlocked("climb_first_clear"),
                      "The climb funnel latches the trophy.")
        XCTAssertFalse(state.trophyPins.isPinned("climb_first_clear"),
                       "A pinned trophy that unlocks live is pruned from the chase.")
    }
}
