import XCTest
@testable import RollAlong

final class ClearRewardsTests: XCTestCase {
    func testTheFlatPaymentIsForTheFirstClearOnly() {
        XCTAssertEqual(ClearRewards.flatPayment(levelAmount: 3, isFirstClear: true), 3)
        XCTAssertEqual(ClearRewards.flatPayment(levelAmount: 3, isFirstClear: false), 0)
    }

    func testTheFullClearBonusPaysOncePerLevel() {
        XCTAssertEqual(ClearRewards.fullClearBonus(level: 7, isFullyClearedNow: true, tierBonus: 15,
                                                   alreadyPaid: []), 15)
        XCTAssertEqual(ClearRewards.fullClearBonus(level: 7, isFullyClearedNow: true, tierBonus: 15,
                                                   alreadyPaid: [7]), 0)
        XCTAssertEqual(ClearRewards.fullClearBonus(level: 7, isFullyClearedNow: false, tierBonus: 15,
                                                   alreadyPaid: []), 0)
    }

    func testLevelsFullyClearedBeforeTheUpdateArePaidInOneSum() {
        // Levels 1 (easy, 10), 5 (very hard, 20), 6 (hard, 15); 6 was already paid.
        let bonus: (Int) -> Int = { [1: 10, 5: 20, 6: 15][$0] ?? 0 }
        let settled = ClearRewards.bonusForEarlierFullClears(levels: [1, 5, 6], alreadyPaid: [6], tierBonus: bonus)
        XCTAssertEqual(settled.total, 30)
        XCTAssertEqual(settled.levels, [1, 5])
        let nothing = ClearRewards.bonusForEarlierFullClears(levels: [], alreadyPaid: [], tierBonus: bonus)
        XCTAssertEqual(nothing.total, 0)
    }

    func testTheBonusAmounts() {
        XCTAssertEqual(ClearRewards.fullClearBonusEasy, 10)
        XCTAssertEqual(ClearRewards.fullClearBonusHard, 15)
        XCTAssertEqual(ClearRewards.fullClearBonusVeryHard, 20)
    }

    func testAPickIsOwedAfterLevels50_100And200() {
        XCTAssertNil(ClearRewards.pickDue(highestUnlocked: 50, taken: []))      // on level 50, not past it
        XCTAssertEqual(ClearRewards.pickDue(highestUnlocked: 51, taken: []), 50)
        XCTAssertNil(ClearRewards.pickDue(highestUnlocked: 100, taken: [50]))
        XCTAssertEqual(ClearRewards.pickDue(highestUnlocked: 101, taken: [50]), 100)
        XCTAssertEqual(ClearRewards.pickDue(highestUnlocked: 201, taken: [50, 100]), 200)
        XCTAssertNil(ClearRewards.pickDue(highestUnlocked: 500, taken: [50, 100, 200]))
    }

    func testOwedPicksAreOfferedLowestFirst() {
        XCTAssertEqual(ClearRewards.pickDue(highestUnlocked: 101, taken: []), 50)
    }

    func testAPlayerAlreadyPastLevel100IsOwedBothPicksInOrder() {
        XCTAssertEqual(ClearRewards.pickDue(highestUnlocked: 101, taken: []), 50)
        XCTAssertEqual(ClearRewards.pickDue(highestUnlocked: 101, taken: [50]), 100)
        XCTAssertNil(ClearRewards.pickDue(highestUnlocked: 101, taken: [50, 100]))
    }
}
