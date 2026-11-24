import XCTest
@testable import RollAlong

final class ClearRewardsTests: XCTestCase {
    func testTheFlatPaymentIsForTheFirstClearOnly() {
        XCTAssertEqual(ClearRewards.flatPayment(levelAmount: 3, isFirstClear: true), 3)
        XCTAssertEqual(ClearRewards.flatPayment(levelAmount: 3, isFirstClear: false), 0)
    }

    func testTheFullClearBonusPaysOncePerLevel() {
        XCTAssertEqual(ClearRewards.fullClearBonus(level: 7, isFullyClearedNow: true, tierBonus: 15,
                                                   alreadyPaid: [], held: []), 15)
        XCTAssertEqual(ClearRewards.fullClearBonus(level: 7, isFullyClearedNow: true, tierBonus: 15,
                                                   alreadyPaid: [7], held: []), 0)
        XCTAssertEqual(ClearRewards.fullClearBonus(level: 7, isFullyClearedNow: false, tierBonus: 15,
                                                   alreadyPaid: [], held: []), 0)
    }

    func testALevelFullyClearedBeforeTheUpdateIsHeldNotPaid() {
        XCTAssertEqual(ClearRewards.fullClearBonus(level: 7, isFullyClearedNow: true, tierBonus: 15,
                                                   alreadyPaid: [], held: [7]), 0)
    }

    func testTheBonusAmounts() {
        XCTAssertEqual(ClearRewards.fullClearBonusEasy, 10)
        XCTAssertEqual(ClearRewards.fullClearBonusHard, 15)
        XCTAssertEqual(ClearRewards.fullClearBonusVeryHard, 20)
    }

    func testAPickIsOwedAfterLevels50_100And200() {
        XCTAssertNil(ClearRewards.pickDue(highestUnlocked: 50, taken: [], held: []))      // on level 50, not past it
        XCTAssertEqual(ClearRewards.pickDue(highestUnlocked: 51, taken: [], held: []), 50)
        XCTAssertNil(ClearRewards.pickDue(highestUnlocked: 100, taken: [50], held: []))
        XCTAssertEqual(ClearRewards.pickDue(highestUnlocked: 101, taken: [50], held: []), 100)
        XCTAssertEqual(ClearRewards.pickDue(highestUnlocked: 201, taken: [50, 100], held: []), 200)
        XCTAssertNil(ClearRewards.pickDue(highestUnlocked: 500, taken: [50, 100, 200], held: []))
    }

    func testOwedPicksAreOfferedLowestFirst() {
        XCTAssertEqual(ClearRewards.pickDue(highestUnlocked: 101, taken: [], held: []), 50)
    }

    func testMilestonesPassedBeforeTheUpdateAreHeld() {
        let held = ClearRewards.milestonesAlreadyPassed(highestUnlocked: 101)
        XCTAssertEqual(held, [50, 100])
        XCTAssertNil(ClearRewards.pickDue(highestUnlocked: 101, taken: [], held: held))
        XCTAssertEqual(ClearRewards.milestonesAlreadyPassed(highestUnlocked: 50), [])
    }
}
