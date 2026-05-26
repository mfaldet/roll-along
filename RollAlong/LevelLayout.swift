import SwiftUI

struct LevelLayout {
    let holeRects: [CGRect]  // normalized 0…1 in each axis
    let start: UnitPoint     // normalized ball spawn
    let goal: UnitPoint      // normalized goal center

    static func layout(for level: Int) -> LevelLayout {
        switch level {
        case 1:
            return LevelLayout(
                holeRects: [
                    CGRect(x: 0,    y: 0, width: 0.12, height: 1),
                    CGRect(x: 0.88, y: 0, width: 0.12, height: 1),
                ],
                start: UnitPoint(x: 0.5, y: 0.85),
                goal:  UnitPoint(x: 0.5, y: 0.12)
            )
        case 2:
            return LevelLayout(
                holeRects: [
                    CGRect(x: 0,    y: 0, width: 0.12, height: 1),
                    CGRect(x: 0.88, y: 0, width: 0.12, height: 1),
                    CGRect(x: 0.25, y: 0.40, width: 0.20, height: 0.12),
                    CGRect(x: 0.55, y: 0.55, width: 0.20, height: 0.12),
                ],
                start: UnitPoint(x: 0.5, y: 0.85),
                goal:  UnitPoint(x: 0.5, y: 0.12)
            )
        case 3:
            return LevelLayout(
                holeRects: [
                    CGRect(x: 0,    y: 0, width: 0.12, height: 1),
                    CGRect(x: 0.88, y: 0, width: 0.12, height: 1),
                    CGRect(x: 0.20, y: 0.30, width: 0.25, height: 0.10),
                    CGRect(x: 0.55, y: 0.50, width: 0.20, height: 0.10),
                    CGRect(x: 0.30, y: 0.65, width: 0.18, height: 0.10),
                ],
                start: UnitPoint(x: 0.5, y: 0.85),
                goal:  UnitPoint(x: 0.5, y: 0.12)
            )
        default:
            return generated(for: level)
        }
    }

    // Flip the course vertically: ball ↔ goal swap, obstacle rects mirrored
    func flipped() -> LevelLayout {
        LevelLayout(
            holeRects: holeRects.map { r in
                CGRect(x: r.origin.x, y: 1 - r.origin.y - r.height,
                       width: r.width, height: r.height)
            },
            start: UnitPoint(x: start.x, y: 1 - start.y),
            goal:  UnitPoint(x: goal.x,  y: 1 - goal.y)
        )
    }

    // Procedurally add more hazards as levels climb
    private static func generated(for level: Int) -> LevelLayout {
        var holes: [CGRect] = [
            CGRect(x: 0,    y: 0, width: 0.10, height: 1),
            CGRect(x: 0.90, y: 0, width: 0.10, height: 1),
        ]
        let count = min(level + 1, 8)
        for i in 0..<count {
            let col = i % 2 == 0 ? 0.18 : 0.52
            let rowStep = 0.55 / Double(count)
            let y = 0.28 + Double(i) * rowStep
            let w = 0.16 + Double(i % 3) * 0.06
            let h = 0.07 + Double(i % 2) * 0.04
            holes.append(CGRect(x: col, y: y, width: w, height: h))
        }
        return LevelLayout(
            holeRects: holes,
            start: UnitPoint(x: 0.5, y: 0.88),
            goal:  UnitPoint(x: 0.5, y: 0.10)
        )
    }
}
