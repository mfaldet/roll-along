import Foundation

// ---------------------------------------------------------------------------
// Small pieces of plain logic used when measuring play.  No UI and no SDK,
// so both can be unit tested.
// ---------------------------------------------------------------------------

/// When to ask for an App Store rating: only when a player FIRST reaches
/// one of these levels.  "Reaches" means the highest level they have unlocked
/// moves to or past it.  Each milestone is asked once, and a milestone a
/// player was already past when this rule arrived is never asked.
enum RatingMilestones {
    static let levels: [Int] = [15, 50, 100]

    /// The milestones crossed when the highest unlocked level moves from
    /// `old` to `new`, lowest first.  Empty when none is crossed.
    static func crossed(from old: Int, to new: Int) -> [Int] {
        levels.filter { old < $0 && new >= $0 }
    }

    /// The milestone to ask at for that move, or nil for none: the highest
    /// milestone crossed that has not been asked before.
    static func toAsk(from old: Int, to new: Int, alreadyAsked: Set<Int>) -> Int? {
        crossed(from: old, to: new).last { !alreadyAsked.contains($0) }
    }
}

/// Where on the playfield something happened, as fractions of its width and
/// height: (0, 0) is the top-left corner and (1, 1) the bottom-right.  These
/// are the same units the level pack uses for holes, coins and the goal, so
/// a fall can be laid straight over a level's design.
enum PlayfieldPoint {
    /// `position` in points inside a playfield of `size`, as fractions
    /// rounded to three decimals and kept within 0...1 (a marble that left
    /// through a side counts as on that edge).  A playfield with no size
    /// gives (0, 0).
    static func fractions(of position: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
        guard size.width > 0, size.height > 0 else { return (0, 0) }
        func fraction(_ value: CGFloat, _ extent: CGFloat) -> Double {
            let f = min(1, max(0, Double(value / extent)))
            return (f * 1000).rounded() / 1000
        }
        return (fraction(position.x, size.width), fraction(position.y, size.height))
    }
}
