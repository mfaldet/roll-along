import Foundation

// ---------------------------------------------------------------------------
// When a downloaded level pack may replace the pack in use.  Plain logic, no
// UI and no network, so it can be unit tested.
//
// The game uses a downloaded pack only if ALL of these hold:
//   1. it parses completely;
//   2. its packVersion is higher than the pack in use;
//   3. it contains every level from 1 to its last, with no gaps;
//   4. it has at least as many levels as the pack in use.
// Otherwise the game keeps the pack it has.  Rule 4 is why a downloaded pack
// can never remove a player's progress: no level a player has played can
// disappear.
// ---------------------------------------------------------------------------

/// What matters about a pack when deciding whether to use it.
struct LevelPackSummary: Equatable {
    var version: Int
    var levelNumbers: Set<Int>
    var levelCount: Int { levelNumbers.count }
}

enum LevelPackRules {
    /// Why a downloaded pack was or was not taken.  Shown in Settings > Debug.
    enum Verdict: Equatable {
        case use
        case didNotParse
        case versionNotHigher
        case hasGaps
        case fewerLevels

        var plainWords: String {
            switch self {
            case .use:              return "accepted"
            case .didNotParse:      return "refused: it did not parse completely"
            case .versionNotHigher: return "kept the pack in use: its version is not higher"
            case .hasGaps:          return "refused: it does not hold every level from 1 to its last"
            case .fewerLevels:      return "refused: it has fewer levels than the pack in use"
            }
        }
    }

    /// `candidate` is nil when the downloaded file did not parse completely.
    static func verdict(candidate: LevelPackSummary?, inUse: LevelPackSummary) -> Verdict {
        guard let candidate else { return .didNotParse }
        guard candidate.version > inUse.version else { return .versionNotHigher }
        guard isGapless(candidate.levelNumbers) else { return .hasGaps }
        guard candidate.levelCount >= inUse.levelCount else { return .fewerLevels }
        return .use
    }

    /// True when the numbers are exactly 1...N for some N of at least 1.
    static func isGapless(_ numbers: Set<Int>) -> Bool {
        guard let last = numbers.max(), let first = numbers.min() else { return false }
        return first == 1 && last == numbers.count
    }
}
