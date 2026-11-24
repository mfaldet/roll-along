import XCTest
import Foundation
@testable import RollAlong

final class LevelProgressRulesTests: XCTestCase {

    private func target(last: Int, stars: [Int: Int], coins: [Int: Int] = [:]) -> PlayTarget {
        LevelProgressRules.playTarget(lastLevel: last,
                                      stars: { stars[$0] ?? 0 },
                                      coinsCollected: { coins[$0] ?? 0 },
                                      coinsInLevel: { _ in 3 })
    }

    // MARK: Play button

    func test_play_opensTheLowestLevelNotPassed() {
        XCTAssertEqual(target(last: 5, stars: [:]), .level(1))
        XCTAssertEqual(target(last: 5, stars: [1: 3, 2: 1]), .level(3))
        // A gap lower down wins over the frontier.
        XCTAssertEqual(target(last: 5, stars: [1: 2, 3: 3, 4: 1]), .level(2))
    }

    func test_play_whenEveryLevelIsPassed_opensTheLowestNotFullyCleared() {
        let stars = [1: 3, 2: 3, 3: 2, 4: 1, 5: 3]
        let coins = [1: 3, 2: 3, 3: 3, 4: 3, 5: 3]
        XCTAssertEqual(target(last: 5, stars: stars, coins: coins), .level(3))
    }

    func test_play_threeStarsWithoutAllCoinsIsNotFullyCleared() {
        let stars = [1: 3, 2: 3, 3: 3]
        let coins = [1: 3, 2: 2, 3: 3]
        XCTAssertEqual(target(last: 3, stars: stars, coins: coins), .level(2))
    }

    func test_play_whenEverythingIsFullyCleared_opensTheLevelSelector() {
        let stars = [1: 3, 2: 3, 3: 3]
        let coins = [1: 3, 2: 3, 3: 3]
        XCTAssertEqual(target(last: 3, stars: stars, coins: coins), .levelSelect)
    }

    func test_play_neverOpensALevelPastTheEndOfThePack() {
        // Stars recorded past the end are ignored.
        XCTAssertEqual(target(last: 2, stars: [1: 1, 2: 1, 3: 0], coins: [:]), .level(1))
    }

    func test_fullyCleared() {
        XCTAssertTrue(LevelProgressRules.isFullyCleared(stars: 3, coinsCollected: 3, coinsInLevel: 3))
        XCTAssertFalse(LevelProgressRules.isFullyCleared(stars: 2, coinsCollected: 3, coinsInLevel: 3))
        XCTAssertFalse(LevelProgressRules.isFullyCleared(stars: 3, coinsCollected: 2, coinsInLevel: 3))
    }

    // MARK: Fitting a saved game to the pack

    private func progress(current: Int, highest: Int, clearedThrough n: Int) -> LevelProgressRules.Progress {
        var stars: [Int: Int] = [:], times: [Int: Double] = [:], coins: [Int: Set<Int>] = [:]
        if n >= 1 { for l in 1...n { stars[l] = 2; times[l] = 12.5; coins[l] = [0, 1] } }
        return .init(currentLevel: current, highestUnlocked: highest,
                     bestStars: stars, bestTime: times, collectedCoins: coins)
    }

    func test_trim_aPlayerPastTheLastLevelIsPlacedOnIt() {
        let before = progress(current: 250, highest: 250, clearedThrough: 249)
        let after = LevelProgressRules.trimmed(before, toLastLevel: 100)
        XCTAssertEqual(after.currentLevel, 100)
        XCTAssertEqual(after.highestUnlocked, 101, "every level passed: one past the last")
        XCTAssertEqual(after.bestStars.count, 100)
        XCTAssertEqual(after.bestTime.count, 100)
        XCTAssertEqual(after.collectedCoins.count, 100)
        XCTAssertNil(after.bestStars[101])
        XCTAssertEqual(after.bestStars[100], 2, "records inside the pack are kept as they were")
    }

    func test_trim_aPlayerInsideThePackIsUnchanged() {
        let before = progress(current: 40, highest: 41, clearedThrough: 40)
        XCTAssertEqual(LevelProgressRules.trimmed(before, toLastLevel: 100), before)
    }

    func test_trim_aPlayerOnTheLastLevelNotYetPassedStaysOnIt() {
        let before = progress(current: 100, highest: 100, clearedThrough: 99)
        let after = LevelProgressRules.trimmed(before, toLastLevel: 100)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.highestUnlocked, 100)
    }

    func test_trim_isSafeToRunTwice() {
        let once = LevelProgressRules.trimmed(progress(current: 250, highest: 250, clearedThrough: 249), toLastLevel: 100)
        XCTAssertEqual(LevelProgressRules.trimmed(once, toLastLevel: 100), once)
    }

    // MARK: Unlocking

    func test_unlocking_stopsOnePastTheLastLevel() {
        XCTAssertEqual(LevelProgressRules.highestUnlocked(afterClearing: 5, was: 5, lastLevel: 100), 6)
        XCTAssertEqual(LevelProgressRules.highestUnlocked(afterClearing: 3, was: 9, lastLevel: 100), 9, "a replay unlocks nothing")
        XCTAssertEqual(LevelProgressRules.highestUnlocked(afterClearing: 100, was: 100, lastLevel: 100), 101)
        XCTAssertEqual(LevelProgressRules.highestUnlocked(afterClearing: 100, was: 101, lastLevel: 100), 101)
    }
}
