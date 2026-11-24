import Foundation

// ---------------------------------------------------------------------------
// The end room (1.1): when it is shown, what it says and how long it lasts.
// Plain logic, no UI, so it can be unit tested.
//
//  • First visit: the first time a player passes the last level in the pack.
//    It comes with the Waiting Room collection.
//  • Second visit: a later pack has a new last level, and a player who has
//    already seen the room passes it.  The second set of messages; no gift.
//    Every visit after that uses the second set too.
//
// `seenAtLastLevel` is the pack's last level when the player last saw the
// room (0 = never).  "Passed every level" means highest unlocked is above
// the last level.
// ---------------------------------------------------------------------------
enum EndRoomVisit: String, Equatable, Identifiable {
    case first, second

    var id: String { rawValue }

    var messages: [String] {
        switch self {
        case .first:
            return [
                "You cleared every level there is. So far.",
                "Roll Along is a passion project, made by one person.",
                "I'm so glad you're here.",
                "More levels are on the way.",
                "Until then, this one's for you.",
                "Thanks for rolling along!",
            ]
        case .second:
            return [
                "You did it again.",
                "Every level, cleared.",
                "New ones are being built right now.",
                "Thanks for rolling along!",
            ]
        }
    }

    /// The message during which the gift is shown, or nil for no gift.
    var giftMessageIndex: Int? { self == .first ? 4 : nil }
}

enum EndRoomRules {
    /// Seconds before the first message.
    static let lead: Double = 2.0
    /// Seconds each message takes: sharpening, held, blurring away.
    static let perMessage: Double = 6.0
    /// Seconds of the sharpening and of the blurring within a message.
    static let fade: Double = 1.4
    /// The room lasts between these, then the swirl takes the player Home.
    static let shortest: Double = 30
    static let longest: Double = 60

    /// The visit due now, or nil.
    static func visitDue(highestUnlocked: Int, lastLevel: Int, seenAtLastLevel: Int) -> EndRoomVisit? {
        guard lastLevel >= 1, highestUnlocked > lastLevel else { return nil }
        if seenAtLastLevel <= 0 { return .first }
        return seenAtLastLevel < lastLevel ? .second : nil
    }

    /// How long the room lasts for `visit`, in seconds: the messages plus a
    /// closing pause, never under 30 or over 60.
    static func duration(of visit: EndRoomVisit) -> Double {
        let natural = lead + Double(visit.messages.count) * perMessage + 3
        return min(longest, max(shortest, natural))
    }

    /// Which message shows at `t` seconds into the room, and how sharp it is
    /// (0 = fully blurred and invisible, 1 = sharp).  nil between messages.
    static func message(at t: Double, of visit: EndRoomVisit) -> (index: Int, clarity: Double)? {
        let u = t - lead
        guard u >= 0 else { return nil }
        let index = Int(u / perMessage)
        guard index < visit.messages.count else { return nil }
        let local = u - Double(index) * perMessage
        let rise = min(1, local / fade)
        let fall = min(1, max(0, (perMessage - local) / fade))
        return (index, max(0, min(rise, fall)))
    }
}
