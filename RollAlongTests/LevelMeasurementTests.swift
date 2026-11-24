import XCTest
import Foundation
@testable import RollAlong

final class LevelMeasurementTests: XCTestCase {

    // MARK: Rating milestones

    func test_asksOnlyWhenAMilestoneIsFirstReached() {
        XCTAssertNil(RatingMilestones.toAsk(from: 13, to: 14, alreadyAsked: []))
        XCTAssertEqual(RatingMilestones.toAsk(from: 14, to: 15, alreadyAsked: []), 15)
        XCTAssertNil(RatingMilestones.toAsk(from: 15, to: 16, alreadyAsked: []))
        XCTAssertEqual(RatingMilestones.toAsk(from: 49, to: 50, alreadyAsked: [15]), 50)
        XCTAssertEqual(RatingMilestones.toAsk(from: 99, to: 100, alreadyAsked: [15, 50]), 100)
        XCTAssertNil(RatingMilestones.toAsk(from: 100, to: 101, alreadyAsked: [15, 50, 100]))
    }

    func test_aMilestoneIsAskedOnce() {
        XCTAssertNil(RatingMilestones.toAsk(from: 14, to: 15, alreadyAsked: [15]))
    }

    func test_playersAlreadyPastAMilestoneAreNotAskedForIt() {
        // At level 30 when the rule arrives: 15 is behind them and never asked.
        XCTAssertNil(RatingMilestones.toAsk(from: 30, to: 31, alreadyAsked: []))
        XCTAssertEqual(RatingMilestones.toAsk(from: 49, to: 50, alreadyAsked: []), 50)
        // Past level 100: nothing left to ask.
        XCTAssertNil(RatingMilestones.toAsk(from: 120, to: 121, alreadyAsked: []))
    }

    func test_aJumpOverSeveralMilestonesAsksOnce_forTheHighest() {
        XCTAssertEqual(RatingMilestones.crossed(from: 10, to: 60), [15, 50])
        XCTAssertEqual(RatingMilestones.toAsk(from: 10, to: 60, alreadyAsked: []), 50)
    }

    func test_noOtherLevelAsks() {
        for level in 1...200 where ![15, 50, 100].contains(level) {
            XCTAssertNil(RatingMilestones.toAsk(from: level - 1, to: level, alreadyAsked: []), "level \(level)")
        }
    }

    // MARK: Where the marble fell

    func test_fallPointIsAFractionOfThePlayfield() {
        let size = CGSize(width: 400, height: 800)
        let p = PlayfieldPoint.fractions(of: CGPoint(x: 100, y: 600), in: size)
        XCTAssertEqual(p.x, 0.25)
        XCTAssertEqual(p.y, 0.75)
    }

    func test_fallPointIsRoundedToThreeDecimals() {
        let p = PlayfieldPoint.fractions(of: CGPoint(x: 1, y: 2), in: CGSize(width: 3, height: 3))
        XCTAssertEqual(p.x, 0.333)
        XCTAssertEqual(p.y, 0.667)
    }

    func test_fallPointOutsideThePlayfieldIsPlacedOnItsEdge() {
        let size = CGSize(width: 400, height: 800)
        let left = PlayfieldPoint.fractions(of: CGPoint(x: -30, y: 400), in: size)
        XCTAssertEqual(left.x, 0)
        XCTAssertEqual(left.y, 0.5)
        let right = PlayfieldPoint.fractions(of: CGPoint(x: 460, y: 900), in: size)
        XCTAssertEqual(right.x, 1)
        XCTAssertEqual(right.y, 1)
    }

    func test_fallPointWithNoPlayfieldIsZero() {
        let p = PlayfieldPoint.fractions(of: CGPoint(x: 10, y: 10), in: .zero)
        XCTAssertEqual(p.x, 0)
        XCTAssertEqual(p.y, 0)
    }
}
