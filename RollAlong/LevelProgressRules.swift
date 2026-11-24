import Foundation

// ---------------------------------------------------------------------------
// Plain rules about a player's place in the level pack.  No UI and no SDK,
// so they can be unit tested.  A level exists only if it is in the pack, and
// the pack's levels run 1...lastLevel.
// ---------------------------------------------------------------------------

/// What the Play button opens for Adventure.
enum PlayTarget: Equatable {
    /// Play this level.
    case level(Int)
    /// Every level is fully cleared: open the level selector.
    case levelSelect
}

enum LevelProgressRules {

    /// A level is fully cleared at three stars with every coin collected.
    static func isFullyCleared(stars: Int, coinsCollected: Int, coinsInLevel: Int) -> Bool {
        stars >= 3 && coinsCollected >= coinsInLevel
    }

    /// What Play opens:
    ///   1. the lowest level the player has not passed;
    ///   2. if every level is passed, the lowest level not fully cleared;
    ///   3. if every level is fully cleared, the level selector.
    /// "Passed" means cleared at least once (one star or more).
    static func playTarget(lastLevel: Int,
                           stars: (Int) -> Int,
                           coinsCollected: (Int) -> Int,
                           coinsInLevel: (Int) -> Int) -> PlayTarget {
        guard lastLevel >= 1 else { return .levelSelect }
        if let notPassed = (1...lastLevel).first(where: { stars($0) < 1 }) {
            return .level(notPassed)
        }
        if let notFull = (1...lastLevel).first(where: {
            !isFullyCleared(stars: stars($0), coinsCollected: coinsCollected($0), coinsInLevel: coinsInLevel($0))
        }) {
            return .level(notFull)
        }
        return .levelSelect
    }

    /// A saved game, as far as levels go.
    struct Progress: Equatable {
        var currentLevel: Int
        /// The highest level open to play.  One past the last level means
        /// every level has been passed.
        var highestUnlocked: Int
        var bestStars: [Int: Int]
        var bestTime: [Int: Double]
        var collectedCoins: [Int: Set<Int>]
    }

    /// Fit a saved game to a pack that ends at `lastLevel`:
    ///   • stars, times and coins recorded for levels past the end are removed;
    ///   • the player's position becomes the last level if it was past it;
    ///   • `highestUnlocked` stops at one past the last level, and only gets
    ///     there if the last level itself has been passed.
    /// A saved game already inside the pack comes back unchanged.
    static func trimmed(_ progress: Progress, toLastLevel lastLevel: Int) -> Progress {
        let last = max(1, lastLevel)
        var p = progress
        p.bestStars      = p.bestStars.filter { $0.key >= 1 && $0.key <= last }
        p.bestTime       = p.bestTime.filter { $0.key >= 1 && $0.key <= last }
        p.collectedCoins = p.collectedCoins.filter { $0.key >= 1 && $0.key <= last }
        p.currentLevel   = min(max(1, p.currentLevel), last)
        let passedLast   = (p.bestStars[last] ?? 0) >= 1
        p.highestUnlocked = min(max(1, p.highestUnlocked), passedLast ? last + 1 : last)
        return p
    }

    /// The highest level open to play after `level` is cleared.
    static func highestUnlocked(afterClearing level: Int, was current: Int, lastLevel: Int) -> Int {
        min(max(current, level + 1), max(1, lastLevel) + 1)
    }
}
