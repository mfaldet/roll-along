import XCTest
@testable import RollAlong

final class EndRoomRulesTests: XCTestCase {
    func testTheFirstVisitIsDueOnceEveryLevelIsPassed() {
        XCTAssertNil(EndRoomRules.visitDue(highestUnlocked: 100, lastLevel: 100, seenAtLastLevel: 0))
        XCTAssertEqual(EndRoomRules.visitDue(highestUnlocked: 101, lastLevel: 100, seenAtLastLevel: 0), .first)
    }

    func testItIsShownOncePerPack() {
        XCTAssertNil(EndRoomRules.visitDue(highestUnlocked: 101, lastLevel: 100, seenAtLastLevel: 100))
    }

    func testTheSecondVisitWaitsForTheNewLastLevel() {
        // A pack of 120 levels arrives; the player is still at 101.
        XCTAssertNil(EndRoomRules.visitDue(highestUnlocked: 101, lastLevel: 120, seenAtLastLevel: 100))
        // They pass level 120.
        XCTAssertEqual(EndRoomRules.visitDue(highestUnlocked: 121, lastLevel: 120, seenAtLastLevel: 100), .second)
        XCTAssertNil(EndRoomRules.visitDue(highestUnlocked: 121, lastLevel: 120, seenAtLastLevel: 120))
    }

    func testOnlyTheFirstVisitHasAGift() {
        XCTAssertEqual(EndRoomVisit.first.giftMessageIndex, 4)
        XCTAssertEqual(EndRoomVisit.first.messages[4], "Until then, this one's for you.")
        XCTAssertNil(EndRoomVisit.second.giftMessageIndex)
    }

    func testBothVisitsLastBetween30And60Seconds() {
        for visit in [EndRoomVisit.first, .second] {
            let d = EndRoomRules.duration(of: visit)
            XCTAssertGreaterThanOrEqual(d, 30)
            XCTAssertLessThanOrEqual(d, 60)
            // Every message finishes before the room ends.
            let lastEnds = EndRoomRules.lead + Double(visit.messages.count) * EndRoomRules.perMessage
            XCTAssertLessThanOrEqual(lastEnds, d)
        }
        XCTAssertEqual(EndRoomRules.duration(of: .first), 41)
        XCTAssertEqual(EndRoomRules.duration(of: .second), 30)
    }

    func testMessagesSharpenThenBlurOneAtATime() {
        XCTAssertNil(EndRoomRules.message(at: 1, of: .first), "nothing before the first message")
        let start = EndRoomRules.message(at: 2, of: .first)
        XCTAssertEqual(start?.index, 0); XCTAssertEqual(start?.clarity ?? -1, 0, accuracy: 1e-9)
        let middle = EndRoomRules.message(at: 5, of: .first)
        XCTAssertEqual(middle?.index, 0); XCTAssertEqual(middle?.clarity ?? -1, 1, accuracy: 1e-9)
        let next = EndRoomRules.message(at: 8.5, of: .first)
        XCTAssertEqual(next?.index, 1)
        XCTAssertNil(EndRoomRules.message(at: 2 + 6 * 6 + 0.5, of: .first), "after the last message")
    }
}
