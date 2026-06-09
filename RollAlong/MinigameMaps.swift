import SwiftUI

// ===========================================================================
// MinigameMaps.swift — Static map catalogues for every competitive minigame.
//
// Architecture:
//   • Each game gets a lightweight map struct and a catalogue enum.
//   • Views read a map by index, cycling on "Play Again."
//   • Shared primitives (WallSegFrac, PillarFrac, SumoPillar) are declared
//     here for use in S24+ wall and pillar engines; they are not yet wired to
//     any physics in S23.
//
// Sprint status:
//   S23 — PinballMap (12 maps) + PaintBallMap (10 maps)          ✅
//   S24 — WallSegFrac wired into CometClash + GoldRush            🔲
//   S25 — PillarFrac / SumoPillar wired into Sumo + KOTH          🔲
//   S26 — MarbleCupMap wired into MarbleCup                       🔲
// ===========================================================================

// MARK: - Shared primitives (S24 / S25 engines)

/// Interior wall expressed as unit fractions of the arena/field rect.
/// Convert to screen coords: x_pt = xFrac * arena.width, etc.
struct WallSegFrac {
    let x1, y1, x2, y2: CGFloat
}

/// Circular post or pillar at a fractional field position.
struct PillarFrac {
    let cx, cy: CGFloat   // 0.0–1.0 relative to field bounds
    let r: CGFloat        // radius in points
}

/// Pillar on a Sumo platform in polar coordinates (relative to platform centre).
struct SumoPillar {
    let radFrac: CGFloat   // fraction of base platform radius
    let angle:   CGFloat   // radians from +x axis
    let r:       CGFloat   // radius in points
}

// MARK: - Pinball

/// Describes a single Pinball table layout.
/// `bumperFracs` are (xFrac, yFrac) within the playfield rect, where
/// (0,0) = field.minX/minY and (1,1) = field.maxX/maxY.
/// Keep xFrac ≤ 0.74 to stay clear of the right launch lane (≈ rightmost 11%).
struct PinballMap {
    let name: String
    let bumperFracs: [(CGFloat, CGFloat)]
}

enum PinballMaps {
    static let maps: [PinballMap] = [

        // 1 — Classic (original 3-bumper layout)
        PinballMap(name: "Classic",
                   bumperFracs: [(0.30, 0.24), (0.58, 0.18), (0.42, 0.40)]),

        // 2 — Diamond: 4 bumpers in a diamond shape
        PinballMap(name: "Diamond",
                   bumperFracs: [(0.40, 0.13), (0.22, 0.27), (0.58, 0.27), (0.40, 0.41)]),

        // 3 — Spread: 5 bumpers in a wide fan across the top
        PinballMap(name: "Spread",
                   bumperFracs: [(0.13, 0.22), (0.30, 0.14), (0.50, 0.20), (0.70, 0.14), (0.40, 0.36)]),

        // 4 — Cluster: 6 bumpers tightly packed in the upper centre
        PinballMap(name: "Cluster",
                   bumperFracs: [(0.30, 0.17), (0.50, 0.15), (0.70, 0.22),
                                 (0.38, 0.30), (0.58, 0.30), (0.20, 0.32)]),

        // 5 — Cross: 4 bumpers in a plus (+) shape
        PinballMap(name: "Cross",
                   bumperFracs: [(0.40, 0.13), (0.18, 0.26), (0.62, 0.26), (0.40, 0.39)]),

        // 6 — Two Rows: 6 bumpers arranged in two horizontal rows of 3
        PinballMap(name: "Two Rows",
                   bumperFracs: [(0.18, 0.16), (0.40, 0.16), (0.62, 0.16),
                                 (0.18, 0.34), (0.40, 0.34), (0.62, 0.34)]),

        // 7 — Zigzag: 5 bumpers in a staggered column pattern
        PinballMap(name: "Zigzag",
                   bumperFracs: [(0.15, 0.14), (0.35, 0.26), (0.55, 0.14), (0.72, 0.26), (0.38, 0.40)]),

        // 8 — Centre Post: Classic 3 bumpers + one lone post mid-field
        PinballMap(name: "Centre Post",
                   bumperFracs: [(0.30, 0.24), (0.58, 0.18), (0.42, 0.40), (0.42, 0.58)]),

        // 9 — Wide Ring: 6 bumpers around the outer ring of the play area
        PinballMap(name: "Wide Ring",
                   bumperFracs: [(0.12, 0.16), (0.35, 0.10), (0.62, 0.14),
                                 (0.72, 0.30), (0.62, 0.44), (0.12, 0.38)]),

        // 10 — Funnel: 4 bumpers forming two converging pairs
        PinballMap(name: "Funnel",
                   bumperFracs: [(0.15, 0.13), (0.65, 0.13), (0.28, 0.34), (0.55, 0.34)]),

        // 11 — Triangle: 3 bumpers in an equilateral triangle
        PinballMap(name: "Triangle",
                   bumperFracs: [(0.40, 0.13), (0.22, 0.38), (0.58, 0.38)]),

        // 12 — Chaos: 8 bumpers scattered across the field
        PinballMap(name: "Chaos",
                   bumperFracs: [(0.14, 0.13), (0.44, 0.11), (0.68, 0.18),
                                 (0.26, 0.26), (0.58, 0.28), (0.18, 0.40),
                                 (0.66, 0.42), (0.40, 0.50)]),
    ]
}

// MARK: - Paint Ball

/// Describes a single Paint Ball arena layout.
/// `pitFracs` are (xFrac, yFrac) of the full arena size.
/// Keep yFrac ≥ 0.22 to stay below the HUD (topReserve ≈ 130 pt).
/// Keep all pits ≥ ~95 pt from arena centre to clear the player spawn.
struct PaintBallMap {
    let name: String
    let pitFracs: [(CGFloat, CGFloat)]
}

enum PaintBallMaps {
    static let maps: [PaintBallMap] = [

        // 1 — Cross: 5 pits in a plus (+) pattern, centre-heavy
        PaintBallMap(name: "Cross",
                     pitFracs: [(0.50, 0.30), (0.50, 0.72), (0.50, 0.87),
                                (0.25, 0.52), (0.75, 0.52)]),

        // 2 — Ring: 6 pits arranged in a hexagonal ring around the centre
        PaintBallMap(name: "Ring",
                     pitFracs: [(0.72, 0.50), (0.61, 0.33), (0.39, 0.33),
                                (0.28, 0.50), (0.39, 0.67), (0.61, 0.67)]),

        // 3 — Corners: 4 pits, one deep in each corner
        PaintBallMap(name: "Corners",
                     pitFracs: [(0.15, 0.28), (0.85, 0.28),
                                (0.15, 0.82), (0.85, 0.82)]),

        // 4 — Spine: 6 pits down the vertical centre (skips spawn zone)
        PaintBallMap(name: "Spine",
                     pitFracs: [(0.50, 0.28), (0.50, 0.39),
                                (0.50, 0.63), (0.50, 0.74), (0.50, 0.84), (0.50, 0.91)]),

        // 5 — Twin Walls: 3+3 pits along the left and right thirds
        PaintBallMap(name: "Twin Walls",
                     pitFracs: [(0.22, 0.30), (0.22, 0.55), (0.22, 0.80),
                                (0.78, 0.30), (0.78, 0.55), (0.78, 0.80)]),

        // 6 — Scattered: 7 pits mimicking the old random feel (but fixed)
        PaintBallMap(name: "Scattered",
                     pitFracs: [(0.18, 0.35), (0.38, 0.26), (0.68, 0.30),
                                (0.82, 0.58), (0.28, 0.70), (0.60, 0.75), (0.45, 0.88)]),

        // 7 — Cluster: 4 pits grouped in the lower-left quadrant
        PaintBallMap(name: "Cluster",
                     pitFracs: [(0.22, 0.38), (0.34, 0.44), (0.25, 0.60), (0.38, 0.68)]),

        // 8 — Diagonal: 5 pits forming a diagonal band (skips centre zone)
        PaintBallMap(name: "Diagonal",
                     pitFracs: [(0.18, 0.26), (0.30, 0.38),
                                (0.64, 0.62), (0.76, 0.74), (0.88, 0.86)]),

        // 9 — Honeycomb: 7 pits in offset rows
        PaintBallMap(name: "Honeycomb",
                     pitFracs: [(0.20, 0.30), (0.50, 0.30), (0.80, 0.30),
                                (0.30, 0.57), (0.70, 0.57),
                                (0.20, 0.80), (0.80, 0.80)]),

        // 10 — Top & Bottom: 6 pits in top and bottom thirds only — long centre highway
        PaintBallMap(name: "Top & Bottom",
                     pitFracs: [(0.20, 0.28), (0.50, 0.28), (0.80, 0.28),
                                (0.20, 0.85), (0.50, 0.85), (0.80, 0.85)]),
    ]
}
