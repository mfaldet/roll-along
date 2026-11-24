import XCTest
@testable import RollAlong

/// Trophies the level pack in use cannot award are hidden from a player who
/// has not earned them, and show again when the pack grows (1.1).
final class TrophyHidingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TrophyHidingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeEngine() throws -> TrophyEngine {
        TrophyEngine(catalog: try TrophyCatalog.load(bundle: .main),
                     defaults: defaults,
                     now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
    }

    private func ids(_ model: TrophyRoomModel) -> Set<String> {
        Set(model.sections.flatMap(\.rows).map(\.id))
    }

    /// The twelve trophies a 100-level pack cannot award.
    private let beyondAHundredLevels: Set<String> = [
        "climb_level_250", "climb_level_500", "climb_level_1000", "climb_level_1500",
        "climb_level_2500", "climb_summit",
        "climb_stars_500", "climb_stars_1000", "climb_stars_3000", "climb_stars_5000",
        "climb_stars_10000",
        "capstone_all",
    ]

    func testWithAHundredLevelsTheUnearnableTrophiesAreHidden() throws {
        let engine = try makeEngine()
        let everything = TrophyRoomModel(engine: engine)
        let shown = TrophyRoomModel(engine: engine, lastLevel: 100)
        XCTAssertEqual(ids(everything).subtracting(ids(shown)), beyondAHundredLevels)
        XCTAssertEqual(shown.summary.total, everything.summary.total - beyondAHundredLevels.count)
        // What a 100-level pack CAN award stays.
        XCTAssertTrue(ids(shown).contains("climb_level_100"))
        XCTAssertTrue(ids(shown).contains("climb_stars_300"))
        XCTAssertTrue(ids(shown).contains("climb_perfect_world"))
    }

    func testTheyShowAgainWhenThePackGrows() throws {
        let engine = try makeEngine()
        let at250 = ids(TrophyRoomModel(engine: engine, lastLevel: 250))
        XCTAssertTrue(at250.contains("climb_level_250"))
        XCTAssertTrue(at250.contains("climb_stars_500"))
        XCTAssertFalse(at250.contains("climb_level_500"))
        XCTAssertFalse(at250.contains("capstone_all"), "the capstone waits for every trophy it requires")
        let at5000 = TrophyRoomModel(engine: engine, lastLevel: 5000)
        XCTAssertEqual(ids(at5000), ids(TrophyRoomModel(engine: engine)))
    }

    func testAnEarnedTrophyIsNeverHidden() throws {
        let engine = try makeEngine()
        _ = engine.record(.climbHighestUnlocked, value: 251)      // earned on an older, longer game
        let shown = ids(TrophyRoomModel(engine: engine, lastLevel: 100))
        XCTAssertTrue(shown.contains("climb_level_250"))
        XCTAssertFalse(shown.contains("climb_level_500"))
    }

    func testTheProfileAndPublicTotalsLeaveHiddenTrophiesOut() throws {
        let engine = try makeEngine()
        let all = TrophyShowcaseModel(engine: engine).total
        XCTAssertEqual(TrophyShowcaseModel(engine: engine, lastLevel: 100).total, all - beyondAHundredLevels.count)
        XCTAssertEqual(TrophyPublicShowcase(engine: engine, lastLevel: 100).total, all - beyondAHundredLevels.count)
    }

    func testAHiddenTrophyIsNotShownAsAPinnedChase() throws {
        let engine = try makeEngine()
        let pins = ["climb_level_250", "climb_level_100"]
        XCTAssertEqual(ChaseChipModel(engine: engine, pinnedIDs: pins).chips.map(\.id), pins)
        XCTAssertEqual(ChaseChipModel(engine: engine, pinnedIDs: pins, lastLevel: 100).chips.map(\.id),
                       ["climb_level_100"])
    }
}
