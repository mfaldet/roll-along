import Foundation

// ---------------------------------------------------------------------------
// Coins and free collections earned by clearing Adventure levels (1.1).
// Plain logic, no UI, so it can be unit tested.
//
//  • The flat payment for clearing a level is paid on the FIRST clear only.
//  • A full-clear bonus is paid once per level, when the level first becomes
//    fully cleared (three stars and every coin): 10 easy, 15 hard, 20 very hard.
//  • A free collection pick is offered after level 10 (as before) and again
//    after levels 50, 100 and 200.
//
// What a player had already done when 1.1 arrived is settled once, on the
// first launch of 1.1 (`GameState.settleRewardsFromBefore11`): every level
// already fully cleared pays its bonus in one sum, and the picks for
// milestones already passed are offered one after another.
// ---------------------------------------------------------------------------
enum ClearRewards {
    static let fullClearBonusEasy = 10
    static let fullClearBonusHard = 15
    static let fullClearBonusVeryHard = 20

    /// The flat payment for this clear: the level's amount on its first
    /// clear, nothing on a replay.
    static func flatPayment(levelAmount: Int, isFirstClear: Bool) -> Int {
        isFirstClear ? max(0, levelAmount) : 0
    }

    /// The full-clear bonus to pay now for `level`, or 0.
    static func fullClearBonus(level: Int,
                               isFullyClearedNow: Bool,
                               tierBonus: Int,
                               alreadyPaid: Set<Int>) -> Int {
        guard isFullyClearedNow, !alreadyPaid.contains(level) else { return 0 }
        return max(0, tierBonus)
    }

    /// The levels after which a free collection pick is offered again.
    /// (Level 10's pick is the tutorial reward and keeps its own record.)
    static let pickMilestones: [Int] = [50, 100, 200]

    /// The lowest milestone whose pick is owed: the player has passed that
    /// level and has not taken its pick.  nil for none.
    /// `highestUnlocked` is one more than the highest level passed in order.
    static func pickDue(highestUnlocked: Int, taken: Set<Int>) -> Int? {
        pickMilestones.first { highestUnlocked > $0 && !taken.contains($0) }
    }

    /// The one-time sum for levels fully cleared before 1.1: each level's
    /// bonus, for every such level not already paid.
    static func bonusForEarlierFullClears(levels: Set<Int>, alreadyPaid: Set<Int>,
                                          tierBonus: (Int) -> Int) -> (total: Int, levels: Set<Int>) {
        let owed = levels.subtracting(alreadyPaid)
        return (owed.reduce(0) { $0 + max(0, tierBonus($1)) }, owed)
    }
}
