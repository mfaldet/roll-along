import Foundation

// ---------------------------------------------------------------------------
// Which trophies can be earned with the level pack in use.  Plain logic, no
// UI, so it can be unit tested.
//
// A trophy that cannot be earned is hidden from players who have not earned
// it.  It shows again by itself when a larger pack makes it earnable, because
// this is worked out from the pack's last level every time.  A trophy a
// player HAS earned is always shown.
// ---------------------------------------------------------------------------
enum TrophyEarnability {
    /// Metric names as written in TrophyCatalog.json.
    static let levelMetric = "climb_highest_unlocked"
    static let starsMetric = "climb_total_stars"
    static let perfectWorldMetric = "climb_perfect_worlds"

    /// Whether a trophy with this metric and threshold can be earned by
    /// playing a pack that ends at `lastLevel`.
    ///  • Level trophies count "highest unlocked", which stops at last + 1.
    ///  • Star trophies: a level gives at most 3 stars.
    ///  • Perfect worlds: a world must lie wholly inside the pack.
    ///  • Every other metric does not depend on the pack.
    static func canBeEarned(metric: String, threshold: Double,
                            lastLevel: Int, wholeWorldsInPack: Int) -> Bool {
        switch metric {
        case levelMetric:        return threshold <= Double(lastLevel + 1)
        case starsMetric:        return threshold <= Double(3 * lastLevel)
        case perfectWorldMetric: return threshold <= Double(wholeWorldsInPack)
        default:                 return true
        }
    }

    /// A trophy that requires other trophies (the capstone) can be earned
    /// only if every one of them can.
    static func canBeEarned(requiring required: [String],
                            eachCanBeEarned: (String) -> Bool) -> Bool {
        required.allSatisfy(eachCanBeEarned)
    }

    /// Hidden means: cannot be earned now AND not already earned.
    static func isHidden(canBeEarned: Bool, isEarned: Bool) -> Bool {
        !canBeEarned && !isEarned
    }
}
