import XCTest
@testable import RollAlong

final class LevelPackRulesTests: XCTestCase {
    private func pack(_ version: Int, _ levels: ClosedRange<Int>) -> LevelPackSummary {
        LevelPackSummary(version: version, levelNumbers: Set(levels))
    }

    func testAHigherVersionWithTheSameOrMoreLevelsIsUsed() {
        XCTAssertEqual(LevelPackRules.verdict(candidate: pack(2, 1...100), inUse: pack(1, 1...100)), .use)
        XCTAssertEqual(LevelPackRules.verdict(candidate: pack(2, 1...120), inUse: pack(1, 1...100)), .use)
    }

    func testAPackThatDidNotParseIsRefused() {
        XCTAssertEqual(LevelPackRules.verdict(candidate: nil, inUse: pack(1, 1...100)), .didNotParse)
    }

    func testTheSameOrALowerVersionIsNotUsed() {
        XCTAssertEqual(LevelPackRules.verdict(candidate: pack(1, 1...120), inUse: pack(1, 1...100)), .versionNotHigher)
        XCTAssertEqual(LevelPackRules.verdict(candidate: pack(0, 1...120), inUse: pack(1, 1...100)), .versionNotHigher)
    }

    func testAPackWithAGapIsRefused() {
        var levels = Set(1...120); levels.remove(57)
        let gappy = LevelPackSummary(version: 2, levelNumbers: levels)
        XCTAssertEqual(LevelPackRules.verdict(candidate: gappy, inUse: pack(1, 1...100)), .hasGaps)
        let noLevelOne = LevelPackSummary(version: 2, levelNumbers: Set(2...121))
        XCTAssertEqual(LevelPackRules.verdict(candidate: noLevelOne, inUse: pack(1, 1...100)), .hasGaps)
        let empty = LevelPackSummary(version: 2, levelNumbers: [])
        XCTAssertEqual(LevelPackRules.verdict(candidate: empty, inUse: pack(1, 1...100)), .hasGaps)
    }

    func testAPackWithFewerLevelsIsRefused() {
        XCTAssertEqual(LevelPackRules.verdict(candidate: pack(2, 1...99), inUse: pack(1, 1...100)), .fewerLevels)
    }
}

final class RouteRecorderTests: XCTestCase {
    private let tick = 1.0 / 60.0

    func testTwentyPointsPerSecondOfPlay() {
        var route = RouteRecorder()
        for _ in 0..<120 { route.tick(x: 0.5, y: 0.5, dt: tick) }   // two seconds
        XCTAssertEqual(route.pointCount, 40)
        XCTAssertEqual(route.step, 0.05, accuracy: 1e-9)
    }

    func testPointsAreThousandthsAndTheEndIsAlwaysKept() {
        var route = RouteRecorder()
        route.tick(x: 0.1234, y: 0.9, dt: tick)
        route.end(x: 0.5, y: 1.7)             // off the bottom counts as the edge
        XCTAssertEqual(route.encoded, "123,900;500,1000")
        route.tick(x: 0.2, y: 0.2, dt: tick)  // nothing is added after the end
        route.end(x: 0.3, y: 0.3)
        XCTAssertEqual(route.pointCount, 2)
    }

    func testALongRunStaysWithinTheLimitAndCoversTheWholeRun() {
        var route = RouteRecorder()
        // Five minutes of play, moving steadily down the playfield.
        let ticks = 5 * 60 * 60
        for i in 0..<ticks { route.tick(x: 0.5, y: Double(i) / Double(ticks), dt: tick) }
        route.end(x: 0.5, y: 1)
        XCTAssertLessThanOrEqual(route.pointCount, RouteRecorder.maxPoints)
        XCTAssertGreaterThan(route.pointCount, RouteRecorder.maxPoints / 2 - 1)
        XCTAssertEqual(route.ys.first, 0)
        XCTAssertEqual(route.ys.last, 1000)
        XCTAssertEqual(route.ys, route.ys.sorted(), "points stay in the order they happened")
        XCTAssertGreaterThan(route.step, 0.05, "the gap between points grew")
        XCTAssertLessThanOrEqual(route.encoded.utf8.count, RouteRecorder.maxPoints * 9)
    }

    func testResetStartsAgain() {
        var route = RouteRecorder()
        route.tick(x: 0.5, y: 0.5, dt: tick); route.end(x: 0.5, y: 0.5)
        route.reset()
        XCTAssertEqual(route.pointCount, 0)
        XCTAssertEqual(route.encoded, "")
        route.tick(x: 0.25, y: 0.75, dt: tick)
        XCTAssertEqual(route.encoded, "250,750")
    }
}

final class TrophyEarnabilityTests: XCTestCase {
    private func can(_ metric: String, _ threshold: Double, last: Int, worlds: Int = 1) -> Bool {
        TrophyEarnability.canBeEarned(metric: metric, threshold: threshold,
                                      lastLevel: last, wholeWorldsInPack: worlds)
    }

    func testLevelTrophiesUpToTheEndOfThePack() {
        XCTAssertTrue(can("climb_highest_unlocked", 101, last: 100))    // clear level 100
        XCTAssertFalse(can("climb_highest_unlocked", 251, last: 100))   // clear level 250
        XCTAssertTrue(can("climb_highest_unlocked", 251, last: 250), "shows again when the pack grows")
    }

    func testStarTrophiesUpToThreePerLevel() {
        XCTAssertTrue(can("climb_total_stars", 300, last: 100))
        XCTAssertFalse(can("climb_total_stars", 500, last: 100))
        XCTAssertTrue(can("climb_total_stars", 500, last: 167))
    }

    func testPerfectWorldNeedsAWholeWorld() {
        XCTAssertTrue(can("climb_perfect_worlds", 1, last: 100, worlds: 1))
        XCTAssertFalse(can("climb_perfect_worlds", 1, last: 60, worlds: 0))
    }

    func testOtherTrophiesDoNotDependOnThePack() {
        XCTAssertTrue(can("snake_wins", 1000, last: 1))
    }

    func testTheCapstoneFollowsTheTrophiesItRequires() {
        XCTAssertTrue(TrophyEarnability.canBeEarned(requiring: ["a", "b"]) { _ in true })
        XCTAssertFalse(TrophyEarnability.canBeEarned(requiring: ["a", "b"]) { $0 != "b" })
    }

    func testAnEarnedTrophyIsNeverHidden() {
        XCTAssertTrue(TrophyEarnability.isHidden(canBeEarned: false, isEarned: false))
        XCTAssertFalse(TrophyEarnability.isHidden(canBeEarned: false, isEarned: true))
        XCTAssertFalse(TrophyEarnability.isHidden(canBeEarned: true, isEarned: false))
    }
}
