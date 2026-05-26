import SwiftUI

/// One playable course.
///
/// All positions are normalised to 0…1 in each axis so the layout adapts to
/// any device size.  The renderer in `BallGameView` multiplies by the actual
/// arena dimensions at draw time.
struct LevelLayout {
    let holeRects: [CGRect]      // hazards
    let start:    UnitPoint      // ball spawn
    let goal:     UnitPoint      // goal centre
    let coins:    [UnitPoint]    // up to 3 collectibles
    let targetTime: TimeInterval // 2-star threshold (seconds)
    let goldTime:   TimeInterval // 3-star threshold (seconds)

    static func layout(for level: Int) -> LevelLayout {
        if level >= 1 && level <= handCrafted.count {
            return handCrafted[level - 1]
        }
        return generated(for: level)
    }

    // Flip the course vertically: ball ↔ goal swap, obstacle rects mirrored,
    // and coin positions mirrored as well.
    func flipped() -> LevelLayout {
        LevelLayout(
            holeRects: holeRects.map { r in
                CGRect(x: r.origin.x, y: 1 - r.origin.y - r.height,
                       width: r.width, height: r.height)
            },
            start:      UnitPoint(x: start.x, y: 1 - start.y),
            goal:       UnitPoint(x: goal.x,  y: 1 - goal.y),
            coins:      coins.map { UnitPoint(x: $0.x, y: 1 - $0.y) },
            targetTime: targetTime,
            goldTime:   goldTime
        )
    }
}

// MARK: - Hand-crafted level designs

extension LevelLayout {
    /// Side-wall hole rectangles used as the standard arena margins.
    /// Every Classic-theme level has these so the ball can't roll off the side.
    private static let sideWalls: [CGRect] = [
        CGRect(x: 0.00, y: 0, width: 0.12, height: 1),
        CGRect(x: 0.88, y: 0, width: 0.12, height: 1),
    ]

    /// Standard formula for target/gold times based on the start→goal
    /// straight-line distance plus a difficulty penalty per hole.
    /// Tuned so a clean run gets 2 stars and a fast direct line gets 3.
    private static func defaultTimes(start: UnitPoint, goal: UnitPoint,
                                     holeCount: Int) -> (target: TimeInterval, gold: TimeInterval) {
        let dx = goal.x - start.x
        let dy = goal.y - start.y
        let dist = sqrt(dx * dx + dy * dy)          // ~0…1.4 (diagonal max)
        let target = 4.0 * dist + 0.35 * Double(holeCount) + 2.5
        let gold   = 2.8 * dist + 0.20 * Double(holeCount) + 1.8
        return (target, gold)
    }

    /// Convenience initialiser that auto-computes times unless overridden.
    private static func make(
        holes: [CGRect],
        start: UnitPoint,
        goal: UnitPoint,
        coins: [UnitPoint],
        target: TimeInterval? = nil,
        gold: TimeInterval? = nil
    ) -> LevelLayout {
        let allHoles = sideWalls + holes
        let times = defaultTimes(start: start, goal: goal, holeCount: holes.count)
        return LevelLayout(
            holeRects: allHoles,
            start: start,
            goal: goal,
            coins: coins,
            targetTime: target ?? times.target,
            goldTime:   gold   ?? times.gold
        )
    }

    /// Levels 1-10 — World 1, Classic sub-theme.
    /// Difficulty climbs gradually so new players learn tilt control.
    static let handCrafted: [LevelLayout] = [

        // ── L1: Intro corridor ─────────────────────────────────────────────
        // No interior holes. Just tilt forward.  Coins along the centre.
        make(
            holes: [],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.5, y: 0.70),
                UnitPoint(x: 0.5, y: 0.50),
                UnitPoint(x: 0.5, y: 0.28),
            ]
        ),

        // ── L2: First obstacle ─────────────────────────────────────────────
        // One hole in the middle, go around either side.
        make(
            holes: [
                CGRect(x: 0.32, y: 0.45, width: 0.36, height: 0.13),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.22, y: 0.50),  // left detour
                UnitPoint(x: 0.78, y: 0.50),  // right detour
                UnitPoint(x: 0.5,  y: 0.25),  // centre after the hole
            ]
        ),

        // ── L3: Split routes ───────────────────────────────────────────────
        make(
            holes: [
                CGRect(x: 0.25, y: 0.40, width: 0.20, height: 0.12),
                CGRect(x: 0.55, y: 0.55, width: 0.20, height: 0.12),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.50, y: 0.48),  // squeeze between
                UnitPoint(x: 0.20, y: 0.65),
                UnitPoint(x: 0.80, y: 0.45),
            ]
        ),

        // ── L4: Three-step zigzag ──────────────────────────────────────────
        make(
            holes: [
                CGRect(x: 0.18, y: 0.30, width: 0.30, height: 0.09),
                CGRect(x: 0.52, y: 0.48, width: 0.30, height: 0.09),
                CGRect(x: 0.18, y: 0.66, width: 0.30, height: 0.09),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.75, y: 0.72),
                UnitPoint(x: 0.30, y: 0.55),
                UnitPoint(x: 0.78, y: 0.38),
            ]
        ),

        // ── L5: Diamond gate ───────────────────────────────────────────────
        make(
            holes: [
                CGRect(x: 0.42, y: 0.32, width: 0.18, height: 0.10),  // top
                CGRect(x: 0.20, y: 0.48, width: 0.18, height: 0.10),  // left
                CGRect(x: 0.62, y: 0.48, width: 0.18, height: 0.10),  // right
                CGRect(x: 0.42, y: 0.64, width: 0.18, height: 0.10),  // bottom
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.50, y: 0.55),   // dead centre — risky
                UnitPoint(x: 0.18, y: 0.30),
                UnitPoint(x: 0.82, y: 0.72),
            ]
        ),

        // ── L6: Narrow corridor ────────────────────────────────────────────
        // Pinches in the middle — requires controlled descent.
        make(
            holes: [
                CGRect(x: 0.12, y: 0.30, width: 0.30, height: 0.08),
                CGRect(x: 0.58, y: 0.30, width: 0.30, height: 0.08),
                CGRect(x: 0.12, y: 0.55, width: 0.30, height: 0.08),
                CGRect(x: 0.58, y: 0.55, width: 0.30, height: 0.08),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.50, y: 0.42),
                UnitPoint(x: 0.50, y: 0.68),
                UnitPoint(x: 0.50, y: 0.20),
            ]
        ),

        // ── L7: S-curve ────────────────────────────────────────────────────
        make(
            holes: [
                CGRect(x: 0.12, y: 0.25, width: 0.50, height: 0.08),
                CGRect(x: 0.38, y: 0.45, width: 0.50, height: 0.08),
                CGRect(x: 0.12, y: 0.65, width: 0.50, height: 0.08),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.78, y: 0.78),
                UnitPoint(x: 0.20, y: 0.55),
                UnitPoint(x: 0.78, y: 0.36),
            ]
        ),

        // ── L8: Sniper alley ───────────────────────────────────────────────
        // Tight gap straight through; rewards staying centred.
        make(
            holes: [
                CGRect(x: 0.12, y: 0.25, width: 0.32, height: 0.10),
                CGRect(x: 0.56, y: 0.25, width: 0.32, height: 0.10),
                CGRect(x: 0.12, y: 0.45, width: 0.32, height: 0.10),
                CGRect(x: 0.56, y: 0.45, width: 0.32, height: 0.10),
                CGRect(x: 0.12, y: 0.65, width: 0.32, height: 0.10),
                CGRect(x: 0.56, y: 0.65, width: 0.32, height: 0.10),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.50, y: 0.55),
                UnitPoint(x: 0.50, y: 0.35),
                UnitPoint(x: 0.50, y: 0.18),
            ]
        ),

        // ── L9: Peninsula ──────────────────────────────────────────────────
        // Holes carve out a one-way passage along the right side.
        make(
            holes: [
                CGRect(x: 0.12, y: 0.20, width: 0.55, height: 0.10),
                CGRect(x: 0.12, y: 0.40, width: 0.40, height: 0.10),
                CGRect(x: 0.12, y: 0.60, width: 0.55, height: 0.10),
                CGRect(x: 0.30, y: 0.78, width: 0.40, height: 0.08),
            ],
            start: UnitPoint(x: 0.18, y: 0.90),
            goal:  UnitPoint(x: 0.18, y: 0.10),
            coins: [
                UnitPoint(x: 0.80, y: 0.50),   // tip of peninsula
                UnitPoint(x: 0.62, y: 0.32),
                UnitPoint(x: 0.20, y: 0.30),
            ]
        ),

        // ── L10: Classic finale ────────────────────────────────────────────
        // Combines split routes, zigzag, and a tight finish.
        make(
            holes: [
                CGRect(x: 0.20, y: 0.20, width: 0.18, height: 0.08),
                CGRect(x: 0.62, y: 0.20, width: 0.18, height: 0.08),
                CGRect(x: 0.40, y: 0.36, width: 0.20, height: 0.08),
                CGRect(x: 0.15, y: 0.50, width: 0.22, height: 0.08),
                CGRect(x: 0.63, y: 0.50, width: 0.22, height: 0.08),
                CGRect(x: 0.40, y: 0.64, width: 0.20, height: 0.08),
                CGRect(x: 0.20, y: 0.78, width: 0.18, height: 0.06),
                CGRect(x: 0.62, y: 0.78, width: 0.18, height: 0.06),
            ],
            start: UnitPoint(x: 0.5,  y: 0.92),
            goal:  UnitPoint(x: 0.5,  y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.28),
                UnitPoint(x: 0.18, y: 0.42),
                UnitPoint(x: 0.82, y: 0.58),
            ]
        ),

        // ═══════════════════════════════════════════════════════════════════
        // INVERTED — levels 11-20
        // Black floor, white holes. Same physics, brain has to re-parse.
        // ═══════════════════════════════════════════════════════════════════

        // L11 — Intro: single central hole, reminds player of mechanics
        make(
            holes: [
                CGRect(x: 0.35, y: 0.45, width: 0.30, height: 0.12),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.20, y: 0.50),
                UnitPoint(x: 0.80, y: 0.50),
                UnitPoint(x: 0.50, y: 0.25),
            ]
        ),

        // L12 — Off-centre hazard
        make(
            holes: [
                CGRect(x: 0.50, y: 0.30, width: 0.32, height: 0.40),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.22, y: 0.50),
                UnitPoint(x: 0.50, y: 0.78),
                UnitPoint(x: 0.78, y: 0.18),
            ]
        ),

        // L13 — Offset bar gates
        make(
            holes: [
                CGRect(x: 0.12, y: 0.30, width: 0.60, height: 0.08),
                CGRect(x: 0.28, y: 0.55, width: 0.60, height: 0.08),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.80, y: 0.42),
                UnitPoint(x: 0.20, y: 0.66),
                UnitPoint(x: 0.50, y: 0.22),
            ]
        ),

        // L14 — Stepped descent
        make(
            holes: [
                CGRect(x: 0.18, y: 0.22, width: 0.18, height: 0.08),
                CGRect(x: 0.40, y: 0.36, width: 0.18, height: 0.08),
                CGRect(x: 0.62, y: 0.50, width: 0.18, height: 0.08),
                CGRect(x: 0.40, y: 0.64, width: 0.18, height: 0.08),
                CGRect(x: 0.18, y: 0.78, width: 0.18, height: 0.06),
            ],
            start: UnitPoint(x: 0.5,  y: 0.92),
            goal:  UnitPoint(x: 0.5,  y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.78),
                UnitPoint(x: 0.30, y: 0.50),
                UnitPoint(x: 0.78, y: 0.30),
            ]
        ),

        // L15 — Cross
        make(
            holes: [
                CGRect(x: 0.42, y: 0.30, width: 0.18, height: 0.10),  // top
                CGRect(x: 0.22, y: 0.46, width: 0.18, height: 0.10),  // left
                CGRect(x: 0.42, y: 0.46, width: 0.18, height: 0.10),  // centre
                CGRect(x: 0.62, y: 0.46, width: 0.18, height: 0.10),  // right
                CGRect(x: 0.42, y: 0.62, width: 0.18, height: 0.10),  // bottom
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.18, y: 0.36),
                UnitPoint(x: 0.82, y: 0.36),
                UnitPoint(x: 0.50, y: 0.80),
            ]
        ),

        // L16 — Hourglass narrowing
        make(
            holes: [
                CGRect(x: 0.12, y: 0.32, width: 0.30, height: 0.12),
                CGRect(x: 0.58, y: 0.32, width: 0.30, height: 0.12),
                CGRect(x: 0.20, y: 0.56, width: 0.22, height: 0.12),
                CGRect(x: 0.58, y: 0.56, width: 0.22, height: 0.12),
            ],
            start: UnitPoint(x: 0.5,  y: 0.88),
            goal:  UnitPoint(x: 0.5,  y: 0.12),
            coins: [
                UnitPoint(x: 0.50, y: 0.74),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.22),
            ]
        ),

        // L17 — Pinball: scattered small holes
        make(
            holes: [
                CGRect(x: 0.22, y: 0.22, width: 0.12, height: 0.07),
                CGRect(x: 0.62, y: 0.25, width: 0.12, height: 0.07),
                CGRect(x: 0.42, y: 0.35, width: 0.12, height: 0.07),
                CGRect(x: 0.20, y: 0.46, width: 0.12, height: 0.07),
                CGRect(x: 0.66, y: 0.48, width: 0.12, height: 0.07),
                CGRect(x: 0.44, y: 0.60, width: 0.12, height: 0.07),
                CGRect(x: 0.24, y: 0.72, width: 0.12, height: 0.07),
                CGRect(x: 0.62, y: 0.72, width: 0.12, height: 0.07),
            ],
            start: UnitPoint(x: 0.5,  y: 0.90),
            goal:  UnitPoint(x: 0.5,  y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.78),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.22),
            ]
        ),

        // L18 — Funnel
        make(
            holes: [
                CGRect(x: 0.12, y: 0.30, width: 0.18, height: 0.08),
                CGRect(x: 0.70, y: 0.30, width: 0.18, height: 0.08),
                CGRect(x: 0.18, y: 0.45, width: 0.18, height: 0.08),
                CGRect(x: 0.64, y: 0.45, width: 0.18, height: 0.08),
                CGRect(x: 0.24, y: 0.60, width: 0.18, height: 0.08),
                CGRect(x: 0.58, y: 0.60, width: 0.18, height: 0.08),
                CGRect(x: 0.30, y: 0.74, width: 0.18, height: 0.07),
                CGRect(x: 0.52, y: 0.74, width: 0.18, height: 0.07),
            ],
            start: UnitPoint(x: 0.5,  y: 0.92),
            goal:  UnitPoint(x: 0.5,  y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.82),
                UnitPoint(x: 0.50, y: 0.52),
                UnitPoint(x: 0.50, y: 0.22),
            ]
        ),

        // L19 — Spinal: vertical bar down centre, weave around
        make(
            holes: [
                CGRect(x: 0.44, y: 0.20, width: 0.12, height: 0.55),
            ],
            start: UnitPoint(x: 0.25, y: 0.92),
            goal:  UnitPoint(x: 0.75, y: 0.10),
            coins: [
                UnitPoint(x: 0.25, y: 0.45),
                UnitPoint(x: 0.75, y: 0.45),
                UnitPoint(x: 0.50, y: 0.85),
            ]
        ),

        // L20 — Inverted finale: dense layered field
        make(
            holes: [
                CGRect(x: 0.18, y: 0.20, width: 0.25, height: 0.08),
                CGRect(x: 0.57, y: 0.20, width: 0.25, height: 0.08),
                CGRect(x: 0.30, y: 0.36, width: 0.40, height: 0.08),
                CGRect(x: 0.15, y: 0.50, width: 0.30, height: 0.08),
                CGRect(x: 0.55, y: 0.50, width: 0.30, height: 0.08),
                CGRect(x: 0.30, y: 0.64, width: 0.40, height: 0.08),
                CGRect(x: 0.18, y: 0.78, width: 0.25, height: 0.06),
                CGRect(x: 0.57, y: 0.78, width: 0.25, height: 0.06),
            ],
            start: UnitPoint(x: 0.5,  y: 0.92),
            goal:  UnitPoint(x: 0.5,  y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.28),
                UnitPoint(x: 0.50, y: 0.58),
                UnitPoint(x: 0.50, y: 0.85),
            ]
        ),

        // ═══════════════════════════════════════════════════════════════════
        // TWILIGHT — levels 21-30
        // Calmer mood, longer paths, slightly more open arenas.
        // ═══════════════════════════════════════════════════════════════════

        // L21 — Open beauty
        make(
            holes: [
                CGRect(x: 0.30, y: 0.42, width: 0.40, height: 0.18),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.18, y: 0.50),
                UnitPoint(x: 0.82, y: 0.50),
                UnitPoint(x: 0.50, y: 0.25),
            ]
        ),

        // L22 — Parallel paths
        make(
            holes: [
                CGRect(x: 0.30, y: 0.20, width: 0.08, height: 0.55),
                CGRect(x: 0.62, y: 0.20, width: 0.08, height: 0.55),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.20, y: 0.45),
                UnitPoint(x: 0.50, y: 0.45),
                UnitPoint(x: 0.80, y: 0.45),
            ]
        ),

        // L23 — Gentle long S-curve
        make(
            holes: [
                CGRect(x: 0.12, y: 0.30, width: 0.45, height: 0.07),
                CGRect(x: 0.43, y: 0.50, width: 0.45, height: 0.07),
                CGRect(x: 0.12, y: 0.70, width: 0.45, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.80, y: 0.82),
                UnitPoint(x: 0.20, y: 0.62),
                UnitPoint(x: 0.80, y: 0.40),
            ]
        ),

        // L24 — Corner sentinels
        make(
            holes: [
                CGRect(x: 0.18, y: 0.22, width: 0.20, height: 0.10),
                CGRect(x: 0.62, y: 0.22, width: 0.20, height: 0.10),
                CGRect(x: 0.18, y: 0.68, width: 0.20, height: 0.10),
                CGRect(x: 0.62, y: 0.68, width: 0.20, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.20, y: 0.50),
                UnitPoint(x: 0.80, y: 0.50),
            ]
        ),

        // L25 — Pinwheel
        make(
            holes: [
                CGRect(x: 0.42, y: 0.20, width: 0.30, height: 0.08),
                CGRect(x: 0.68, y: 0.42, width: 0.20, height: 0.30),
                CGRect(x: 0.28, y: 0.72, width: 0.30, height: 0.08),
                CGRect(x: 0.12, y: 0.28, width: 0.20, height: 0.30),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.20, y: 0.78),
                UnitPoint(x: 0.80, y: 0.22),
            ]
        ),

        // L26 — Long descending zigzag
        make(
            holes: [
                CGRect(x: 0.15, y: 0.20, width: 0.40, height: 0.06),
                CGRect(x: 0.45, y: 0.35, width: 0.40, height: 0.06),
                CGRect(x: 0.15, y: 0.50, width: 0.40, height: 0.06),
                CGRect(x: 0.45, y: 0.65, width: 0.40, height: 0.06),
                CGRect(x: 0.15, y: 0.80, width: 0.40, height: 0.06),
            ],
            start: UnitPoint(x: 0.50, y: 0.92),
            goal:  UnitPoint(x: 0.50, y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.72),
                UnitPoint(x: 0.22, y: 0.42),
                UnitPoint(x: 0.78, y: 0.28),
            ]
        ),

        // L27 — Two-tier gauntlet
        make(
            holes: [
                CGRect(x: 0.18, y: 0.30, width: 0.18, height: 0.08),
                CGRect(x: 0.44, y: 0.30, width: 0.18, height: 0.08),
                CGRect(x: 0.66, y: 0.30, width: 0.18, height: 0.08),
                CGRect(x: 0.30, y: 0.55, width: 0.18, height: 0.08),
                CGRect(x: 0.52, y: 0.55, width: 0.18, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.18, y: 0.45),
                UnitPoint(x: 0.78, y: 0.45),
                UnitPoint(x: 0.50, y: 0.70),
            ]
        ),

        // L28 — River flow (diagonal band)
        make(
            holes: [
                CGRect(x: 0.12, y: 0.30, width: 0.20, height: 0.08),
                CGRect(x: 0.30, y: 0.42, width: 0.20, height: 0.08),
                CGRect(x: 0.48, y: 0.54, width: 0.20, height: 0.08),
                CGRect(x: 0.66, y: 0.66, width: 0.22, height: 0.08),
            ],
            start: UnitPoint(x: 0.18, y: 0.88),
            goal:  UnitPoint(x: 0.82, y: 0.18),
            coins: [
                UnitPoint(x: 0.30, y: 0.78),
                UnitPoint(x: 0.50, y: 0.42),
                UnitPoint(x: 0.78, y: 0.32),
            ]
        ),

        // L29 — Tight maze
        make(
            holes: [
                CGRect(x: 0.12, y: 0.25, width: 0.40, height: 0.06),
                CGRect(x: 0.60, y: 0.25, width: 0.28, height: 0.06),
                CGRect(x: 0.30, y: 0.40, width: 0.40, height: 0.06),
                CGRect(x: 0.12, y: 0.55, width: 0.30, height: 0.06),
                CGRect(x: 0.50, y: 0.55, width: 0.38, height: 0.06),
                CGRect(x: 0.30, y: 0.70, width: 0.40, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.20, y: 0.80),
                UnitPoint(x: 0.50, y: 0.48),
                UnitPoint(x: 0.80, y: 0.20),
            ]
        ),

        // L30 — Twilight finale
        make(
            holes: [
                CGRect(x: 0.16, y: 0.18, width: 0.16, height: 0.10),
                CGRect(x: 0.68, y: 0.18, width: 0.16, height: 0.10),
                CGRect(x: 0.40, y: 0.30, width: 0.20, height: 0.08),
                CGRect(x: 0.16, y: 0.46, width: 0.22, height: 0.10),
                CGRect(x: 0.62, y: 0.46, width: 0.22, height: 0.10),
                CGRect(x: 0.40, y: 0.62, width: 0.20, height: 0.08),
                CGRect(x: 0.16, y: 0.76, width: 0.16, height: 0.08),
                CGRect(x: 0.68, y: 0.76, width: 0.16, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.18),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.82),
            ]
        ),

        // ═══════════════════════════════════════════════════════════════════
        // EMBER — levels 31-40
        // Warmer mood, denser hazard fields, sharper precision required.
        // ═══════════════════════════════════════════════════════════════════

        // L31 — Heavy intro
        make(
            holes: [
                CGRect(x: 0.20, y: 0.30, width: 0.18, height: 0.10),
                CGRect(x: 0.42, y: 0.30, width: 0.18, height: 0.10),
                CGRect(x: 0.64, y: 0.30, width: 0.16, height: 0.10),
                CGRect(x: 0.30, y: 0.55, width: 0.18, height: 0.10),
                CGRect(x: 0.52, y: 0.55, width: 0.18, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.18, y: 0.50),
                UnitPoint(x: 0.50, y: 0.72),
                UnitPoint(x: 0.50, y: 0.42),
            ]
        ),

        // L32 — Stair descent (6 steps)
        make(
            holes: [
                CGRect(x: 0.55, y: 0.16, width: 0.30, height: 0.06),
                CGRect(x: 0.15, y: 0.28, width: 0.30, height: 0.06),
                CGRect(x: 0.55, y: 0.40, width: 0.30, height: 0.06),
                CGRect(x: 0.15, y: 0.52, width: 0.30, height: 0.06),
                CGRect(x: 0.55, y: 0.64, width: 0.30, height: 0.06),
                CGRect(x: 0.15, y: 0.76, width: 0.30, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.78, y: 0.84),
                UnitPoint(x: 0.78, y: 0.48),
                UnitPoint(x: 0.78, y: 0.12),
            ]
        ),

        // L33 — Gauntlet maze
        make(
            holes: [
                CGRect(x: 0.18, y: 0.22, width: 0.10, height: 0.12),
                CGRect(x: 0.36, y: 0.22, width: 0.10, height: 0.12),
                CGRect(x: 0.54, y: 0.22, width: 0.10, height: 0.12),
                CGRect(x: 0.72, y: 0.22, width: 0.10, height: 0.12),
                CGRect(x: 0.27, y: 0.42, width: 0.10, height: 0.12),
                CGRect(x: 0.45, y: 0.42, width: 0.10, height: 0.12),
                CGRect(x: 0.63, y: 0.42, width: 0.10, height: 0.12),
                CGRect(x: 0.18, y: 0.62, width: 0.10, height: 0.12),
                CGRect(x: 0.36, y: 0.62, width: 0.10, height: 0.12),
                CGRect(x: 0.54, y: 0.62, width: 0.10, height: 0.12),
                CGRect(x: 0.72, y: 0.62, width: 0.10, height: 0.12),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.50, y: 0.36),
                UnitPoint(x: 0.50, y: 0.56),
                UnitPoint(x: 0.50, y: 0.76),
            ]
        ),

        // L34 — Diamond grid
        make(
            holes: [
                CGRect(x: 0.42, y: 0.20, width: 0.16, height: 0.08),
                CGRect(x: 0.22, y: 0.36, width: 0.16, height: 0.08),
                CGRect(x: 0.62, y: 0.36, width: 0.16, height: 0.08),
                CGRect(x: 0.42, y: 0.50, width: 0.16, height: 0.08),
                CGRect(x: 0.22, y: 0.64, width: 0.16, height: 0.08),
                CGRect(x: 0.62, y: 0.64, width: 0.16, height: 0.08),
                CGRect(x: 0.42, y: 0.78, width: 0.16, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.30),
                UnitPoint(x: 0.50, y: 0.58),
                UnitPoint(x: 0.50, y: 0.86),
            ]
        ),

        // L35 — Forced single corridor
        make(
            holes: [
                CGRect(x: 0.12, y: 0.18, width: 0.32, height: 0.65),
                CGRect(x: 0.56, y: 0.18, width: 0.32, height: 0.65),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.78),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.20),
            ]
        ),

        // L36 — Precision threading
        make(
            holes: [
                CGRect(x: 0.12, y: 0.22, width: 0.34, height: 0.16),
                CGRect(x: 0.54, y: 0.22, width: 0.34, height: 0.16),
                CGRect(x: 0.30, y: 0.46, width: 0.40, height: 0.10),
                CGRect(x: 0.12, y: 0.66, width: 0.34, height: 0.16),
                CGRect(x: 0.54, y: 0.66, width: 0.34, height: 0.16),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.82),
                UnitPoint(x: 0.18, y: 0.50),
                UnitPoint(x: 0.50, y: 0.18),
            ]
        ),

        // L37 — Spiral
        make(
            holes: [
                CGRect(x: 0.12, y: 0.20, width: 0.55, height: 0.07),
                CGRect(x: 0.60, y: 0.27, width: 0.10, height: 0.45),
                CGRect(x: 0.30, y: 0.65, width: 0.40, height: 0.07),
                CGRect(x: 0.30, y: 0.40, width: 0.10, height: 0.25),
                CGRect(x: 0.40, y: 0.40, width: 0.18, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.50),  // goal in centre of spiral
            coins: [
                UnitPoint(x: 0.78, y: 0.85),
                UnitPoint(x: 0.18, y: 0.50),
                UnitPoint(x: 0.20, y: 0.30),
            ]
        ),

        // L38 — Dual-route puzzle
        make(
            holes: [
                CGRect(x: 0.40, y: 0.18, width: 0.20, height: 0.65),
                CGRect(x: 0.15, y: 0.40, width: 0.16, height: 0.10),
                CGRect(x: 0.69, y: 0.40, width: 0.16, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.22, y: 0.30),
                UnitPoint(x: 0.78, y: 0.30),
                UnitPoint(x: 0.50, y: 0.92),  // start area
            ]
        ),

        // L39 — Hourglass (tighter than L16)
        make(
            holes: [
                CGRect(x: 0.12, y: 0.30, width: 0.36, height: 0.10),
                CGRect(x: 0.52, y: 0.30, width: 0.36, height: 0.10),
                CGRect(x: 0.18, y: 0.50, width: 0.28, height: 0.10),
                CGRect(x: 0.54, y: 0.50, width: 0.28, height: 0.10),
                CGRect(x: 0.12, y: 0.70, width: 0.36, height: 0.10),
                CGRect(x: 0.52, y: 0.70, width: 0.36, height: 0.10),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.82),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.18),
            ]
        ),

        // L40 — Ember finale
        make(
            holes: [
                CGRect(x: 0.18, y: 0.18, width: 0.14, height: 0.08),
                CGRect(x: 0.42, y: 0.18, width: 0.14, height: 0.08),
                CGRect(x: 0.66, y: 0.18, width: 0.14, height: 0.08),
                CGRect(x: 0.30, y: 0.32, width: 0.14, height: 0.08),
                CGRect(x: 0.54, y: 0.32, width: 0.14, height: 0.08),
                CGRect(x: 0.18, y: 0.46, width: 0.14, height: 0.08),
                CGRect(x: 0.42, y: 0.46, width: 0.14, height: 0.08),
                CGRect(x: 0.66, y: 0.46, width: 0.14, height: 0.08),
                CGRect(x: 0.30, y: 0.60, width: 0.14, height: 0.08),
                CGRect(x: 0.54, y: 0.60, width: 0.14, height: 0.08),
                CGRect(x: 0.18, y: 0.74, width: 0.14, height: 0.08),
                CGRect(x: 0.42, y: 0.74, width: 0.14, height: 0.08),
                CGRect(x: 0.66, y: 0.74, width: 0.14, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.25),
                UnitPoint(x: 0.50, y: 0.53),
                UnitPoint(x: 0.50, y: 0.81),
            ]
        ),

        // ═══════════════════════════════════════════════════════════════════
        // AURORA — levels 41-50
        // Climactic finale to World 1.  Floor shimmers via Canvas overlay.
        // ═══════════════════════════════════════════════════════════════════

        // L41 — Open Aurora (show off the shimmer)
        make(
            holes: [
                CGRect(x: 0.40, y: 0.46, width: 0.20, height: 0.16),
            ],
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.12),
            coins: [
                UnitPoint(x: 0.20, y: 0.30),
                UnitPoint(x: 0.80, y: 0.30),
                UnitPoint(x: 0.50, y: 0.72),
            ]
        ),

        // L42 — Ascending zigzag
        make(
            holes: [
                CGRect(x: 0.55, y: 0.20, width: 0.30, height: 0.06),
                CGRect(x: 0.15, y: 0.35, width: 0.30, height: 0.06),
                CGRect(x: 0.55, y: 0.50, width: 0.30, height: 0.06),
                CGRect(x: 0.15, y: 0.65, width: 0.30, height: 0.06),
                CGRect(x: 0.55, y: 0.80, width: 0.30, height: 0.06),
            ],
            start: UnitPoint(x: 0.20, y: 0.90),
            goal:  UnitPoint(x: 0.80, y: 0.10),
            coins: [
                UnitPoint(x: 0.20, y: 0.45),
                UnitPoint(x: 0.80, y: 0.45),
                UnitPoint(x: 0.20, y: 0.18),
            ]
        ),

        // L43 — Starfield (many small holes)
        make(
            holes: [
                CGRect(x: 0.20, y: 0.20, width: 0.08, height: 0.08),
                CGRect(x: 0.40, y: 0.22, width: 0.08, height: 0.08),
                CGRect(x: 0.60, y: 0.20, width: 0.08, height: 0.08),
                CGRect(x: 0.74, y: 0.30, width: 0.08, height: 0.08),
                CGRect(x: 0.30, y: 0.36, width: 0.08, height: 0.08),
                CGRect(x: 0.50, y: 0.40, width: 0.08, height: 0.08),
                CGRect(x: 0.18, y: 0.48, width: 0.08, height: 0.08),
                CGRect(x: 0.65, y: 0.50, width: 0.08, height: 0.08),
                CGRect(x: 0.40, y: 0.58, width: 0.08, height: 0.08),
                CGRect(x: 0.22, y: 0.66, width: 0.08, height: 0.08),
                CGRect(x: 0.54, y: 0.68, width: 0.08, height: 0.08),
                CGRect(x: 0.74, y: 0.72, width: 0.08, height: 0.08),
                CGRect(x: 0.40, y: 0.78, width: 0.08, height: 0.08),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.25),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.85),
            ]
        ),

        // L44 — Nebula (few large soft hazards)
        make(
            holes: [
                CGRect(x: 0.16, y: 0.24, width: 0.30, height: 0.20),
                CGRect(x: 0.58, y: 0.30, width: 0.30, height: 0.20),
                CGRect(x: 0.18, y: 0.56, width: 0.30, height: 0.22),
                CGRect(x: 0.58, y: 0.60, width: 0.30, height: 0.22),
            ],
            start: UnitPoint(x: 0.5, y: 0.90),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.50, y: 0.78),
                UnitPoint(x: 0.50, y: 0.50),
                UnitPoint(x: 0.50, y: 0.20),
            ]
        ),

        // L45 — Prism: diagonal-ish hazards
        make(
            holes: [
                CGRect(x: 0.12, y: 0.25, width: 0.28, height: 0.07),
                CGRect(x: 0.34, y: 0.36, width: 0.28, height: 0.07),
                CGRect(x: 0.56, y: 0.47, width: 0.32, height: 0.07),
                CGRect(x: 0.34, y: 0.58, width: 0.28, height: 0.07),
                CGRect(x: 0.12, y: 0.69, width: 0.28, height: 0.07),
            ],
            start: UnitPoint(x: 0.80, y: 0.90),
            goal:  UnitPoint(x: 0.20, y: 0.10),
            coins: [
                UnitPoint(x: 0.78, y: 0.74),
                UnitPoint(x: 0.50, y: 0.42),
                UnitPoint(x: 0.20, y: 0.32),
            ]
        ),

        // L46 — Void crossing (massive central hole)
        make(
            holes: [
                CGRect(x: 0.22, y: 0.28, width: 0.56, height: 0.44),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.16, y: 0.50),
                UnitPoint(x: 0.84, y: 0.50),
                UnitPoint(x: 0.50, y: 0.16),
            ]
        ),

        // L47 — Aurora dance (curved feel via staggered holes)
        make(
            holes: [
                CGRect(x: 0.62, y: 0.20, width: 0.22, height: 0.07),
                CGRect(x: 0.40, y: 0.32, width: 0.22, height: 0.07),
                CGRect(x: 0.18, y: 0.42, width: 0.20, height: 0.07),
                CGRect(x: 0.18, y: 0.55, width: 0.20, height: 0.07),
                CGRect(x: 0.40, y: 0.65, width: 0.22, height: 0.07),
                CGRect(x: 0.62, y: 0.75, width: 0.22, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.78, y: 0.50),
                UnitPoint(x: 0.50, y: 0.48),
                UnitPoint(x: 0.50, y: 0.18),
            ]
        ),

        // L48 — Tempest (dense chaotic)
        make(
            holes: [
                CGRect(x: 0.16, y: 0.18, width: 0.18, height: 0.07),
                CGRect(x: 0.42, y: 0.22, width: 0.18, height: 0.07),
                CGRect(x: 0.66, y: 0.16, width: 0.18, height: 0.07),
                CGRect(x: 0.20, y: 0.34, width: 0.18, height: 0.07),
                CGRect(x: 0.50, y: 0.36, width: 0.18, height: 0.07),
                CGRect(x: 0.30, y: 0.48, width: 0.18, height: 0.07),
                CGRect(x: 0.60, y: 0.50, width: 0.18, height: 0.07),
                CGRect(x: 0.16, y: 0.62, width: 0.18, height: 0.07),
                CGRect(x: 0.46, y: 0.62, width: 0.18, height: 0.07),
                CGRect(x: 0.70, y: 0.66, width: 0.18, height: 0.07),
                CGRect(x: 0.28, y: 0.78, width: 0.18, height: 0.07),
                CGRect(x: 0.56, y: 0.78, width: 0.18, height: 0.07),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.08),
            coins: [
                UnitPoint(x: 0.50, y: 0.28),
                UnitPoint(x: 0.50, y: 0.55),
                UnitPoint(x: 0.50, y: 0.85),
            ]
        ),

        // L49 — Convergence (paths funnel to tight goal)
        make(
            holes: [
                CGRect(x: 0.30, y: 0.20, width: 0.40, height: 0.06),
                CGRect(x: 0.18, y: 0.35, width: 0.18, height: 0.06),
                CGRect(x: 0.64, y: 0.35, width: 0.18, height: 0.06),
                CGRect(x: 0.18, y: 0.50, width: 0.30, height: 0.06),
                CGRect(x: 0.52, y: 0.50, width: 0.30, height: 0.06),
                CGRect(x: 0.32, y: 0.65, width: 0.36, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.92),
            goal:  UnitPoint(x: 0.5, y: 0.10),
            coins: [
                UnitPoint(x: 0.20, y: 0.80),
                UnitPoint(x: 0.80, y: 0.80),
                UnitPoint(x: 0.50, y: 0.30),
            ]
        ),

        // L50 — WORLD 1 FINALE
        // The boss of World 1.  Combines every learned pattern into one
        // demanding course.  Coin placements punish greed.
        make(
            holes: [
                CGRect(x: 0.18, y: 0.16, width: 0.14, height: 0.08),
                CGRect(x: 0.38, y: 0.16, width: 0.24, height: 0.08),
                CGRect(x: 0.68, y: 0.16, width: 0.14, height: 0.08),
                CGRect(x: 0.30, y: 0.30, width: 0.16, height: 0.08),
                CGRect(x: 0.54, y: 0.30, width: 0.16, height: 0.08),
                CGRect(x: 0.16, y: 0.44, width: 0.20, height: 0.08),
                CGRect(x: 0.44, y: 0.44, width: 0.12, height: 0.08),
                CGRect(x: 0.64, y: 0.44, width: 0.20, height: 0.08),
                CGRect(x: 0.30, y: 0.58, width: 0.16, height: 0.08),
                CGRect(x: 0.54, y: 0.58, width: 0.16, height: 0.08),
                CGRect(x: 0.18, y: 0.72, width: 0.14, height: 0.08),
                CGRect(x: 0.38, y: 0.72, width: 0.24, height: 0.08),
                CGRect(x: 0.68, y: 0.72, width: 0.14, height: 0.08),
                CGRect(x: 0.40, y: 0.84, width: 0.20, height: 0.06),
            ],
            start: UnitPoint(x: 0.5, y: 0.94),
            goal:  UnitPoint(x: 0.5, y: 0.06),
            coins: [
                UnitPoint(x: 0.50, y: 0.25),   // mid-flight near top
                UnitPoint(x: 0.50, y: 0.51),   // dead centre
                UnitPoint(x: 0.50, y: 0.78),   // near start
            ]
        ),
    ]

    /// Procedurally add more hazards as levels climb past the hand-crafted set.
    /// No coins on generated levels (yet) — future PRs add the remaining 90.
    static func generated(for level: Int) -> LevelLayout {
        var holes: [CGRect] = sideWalls
        let count = min(level + 1, 8)
        for i in 0..<count {
            let col = i % 2 == 0 ? 0.18 : 0.52
            let rowStep = 0.55 / Double(count)
            let y = 0.28 + Double(i) * rowStep
            let w = 0.16 + Double(i % 3) * 0.06
            let h = 0.07 + Double(i % 2) * 0.04
            holes.append(CGRect(x: col, y: y, width: w, height: h))
        }
        let start = UnitPoint(x: 0.5, y: 0.88)
        let goal  = UnitPoint(x: 0.5, y: 0.10)
        let times = defaultTimes(start: start, goal: goal, holeCount: count)
        return LevelLayout(
            holeRects: holes,
            start: start,
            goal: goal,
            coins: [],
            targetTime: times.target,
            goldTime:   times.gold
        )
    }
}

// MARK: - Theme system

/// Identifies a sub-theme.  Used for analytics + UI labelling.
enum ThemeID: String {
    case classic
    case inverted
    case twilight
    case ember
    case aurora
    case notebook    // Paper world
    case graph
    case parchment
    case sketch
    case origami
}

/// Visual presentation for a level — floor + hole colours, plus a flag for
/// whether the world has the graphite-trail mechanic enabled (Paper world).
/// Floor overlays (ruled lines, grids, fold shadows) ship in PR 2b/2c.
struct Theme {
    let id:           ThemeID
    let name:         String
    let floorColor:   Color
    let holeColor:    Color
    let trailEnabled: Bool
    let trailColor:   Color

    /// Maps a level number to the theme it should render under.
    /// World 1 (levels 1-50) — 5 sub-themes of 10 levels each.
    /// World 2 (levels 51-100) — Paper world, 5 sub-themes of 10 levels each.
    static func forLevel(_ level: Int) -> Theme {
        let clamped = max(1, level)
        switch clamped {
        case 1...10:    return classic
        case 11...20:   return inverted
        case 21...30:   return twilight
        case 31...40:   return ember
        case 41...50:   return aurora
        case 51...60:   return notebook
        case 61...70:   return graph
        case 71...80:   return parchment
        case 81...90:   return sketch
        case 91...100:  return origami
        default:        return classic  // future worlds wrap to classic until added
        }
    }

    // ── Sub-theme palettes ──────────────────────────────────────────────

    static let classic = Theme(
        id:           .classic,
        name:         "Classic",
        floorColor:   Color(red: 0.941, green: 0.937, blue: 0.925),  // warm off-white
        holeColor:    Color(red: 0.039, green: 0.039, blue: 0.039),  // deep black
        trailEnabled: false,
        trailColor:   .clear
    )

    static let inverted = Theme(
        id:           .inverted,
        name:         "Inverted",
        floorColor:   Color(red: 0.039, green: 0.039, blue: 0.039),  // black floor
        holeColor:    Color(red: 0.941, green: 0.937, blue: 0.925),  // white holes
        trailEnabled: false,
        trailColor:   .clear
    )

    static let twilight = Theme(
        id:           .twilight,
        name:         "Twilight",
        floorColor:   Color(red: 0.835, green: 0.824, blue: 0.890),  // pale lavender
        holeColor:    Color(red: 0.047, green: 0.059, blue: 0.122),  // navy-black
        trailEnabled: false,
        trailColor:   .clear
    )

    static let ember = Theme(
        id:           .ember,
        name:         "Ember",
        floorColor:   Color(red: 0.910, green: 0.835, blue: 0.753),  // warm peach
        holeColor:    Color(red: 0.102, green: 0.039, blue: 0.039),  // maroon-black
        trailEnabled: false,
        trailColor:   .clear
    )

    static let aurora = Theme(
        id:           .aurora,
        name:         "Aurora",
        floorColor:   Color(red: 0.380, green: 0.620, blue: 0.560),  // base; the
                                                                       // Canvas overlay
                                                                       // animates a hue
                                                                       // shift on top
        holeColor:    Color(red: 0.000, green: 0.000, blue: 0.000),
        trailEnabled: false,
        trailColor:   .clear
    )

    // World 2 — Paper.  trailEnabled = true means the ball leaves a graphite streak.

    static let notebook = Theme(
        id:           .notebook,
        name:         "Notebook",
        floorColor:   Color(red: 0.980, green: 0.961, blue: 0.902),
        holeColor:    Color(red: 0.169, green: 0.122, blue: 0.071),
        trailEnabled: true,
        trailColor:   Color(red: 0.20, green: 0.20, blue: 0.22).opacity(0.7)
    )

    static let graph = Theme(
        id:           .graph,
        name:         "Graph",
        floorColor:   Color(red: 0.984, green: 0.984, blue: 0.984),
        holeColor:    Color(red: 0.055, green: 0.102, blue: 0.180),
        trailEnabled: true,
        trailColor:   Color(red: 0.20, green: 0.20, blue: 0.22).opacity(0.7)
    )

    static let parchment = Theme(
        id:           .parchment,
        name:         "Parchment",
        floorColor:   Color(red: 0.914, green: 0.863, blue: 0.753),
        holeColor:    Color(red: 0.102, green: 0.059, blue: 0.031),
        trailEnabled: true,
        trailColor:   Color(red: 0.20, green: 0.15, blue: 0.10).opacity(0.7)
    )

    static let sketch = Theme(
        id:           .sketch,
        name:         "Sketch",
        floorColor:   Color(red: 0.988, green: 0.988, blue: 0.980),
        holeColor:    Color(red: 0.102, green: 0.102, blue: 0.102),
        trailEnabled: true,
        trailColor:   Color(red: 0.18, green: 0.18, blue: 0.20).opacity(0.7)
    )

    static let origami = Theme(
        id:           .origami,
        name:         "Origami",
        floorColor:   Color(red: 0.961, green: 0.937, blue: 0.878),
        holeColor:    Color(red: 0.094, green: 0.078, blue: 0.063),
        trailEnabled: true,
        trailColor:   Color(red: 0.20, green: 0.18, blue: 0.15).opacity(0.7)
    )
}
