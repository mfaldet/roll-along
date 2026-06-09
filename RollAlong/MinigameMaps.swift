import SwiftUI

// ===========================================================================
// MinigameMaps.swift — Static map catalogues for every competitive minigame.
//
// Architecture:
//   • Each game gets a lightweight map struct and a catalogue enum.
//   • Views read a map by index, cycling on "Play Again."
//   • Shared primitives (WallSegFrac, PillarFrac, SumoPillar) are declared
//     here and are fully wired into the wall engine (S24) and pillar engine
//     (S25); SumoPillar additionally drives the polar-coordinate ring-shrink
//     in SumoSurvivalView.
//
// Sprint status:
//   S23 — PinballMap (12 maps) + PaintBallMap (10 maps)          ✅
//   S24 — CometClashMap (8) + GoldRushMap (8); wall engine        ✅
//   S25 — SumoMap (8) + KOTHMap (8); pillar engine                ✅
//   S26 — MarbleCupMap (8); pitch bumpers + goal width            ✅
//   QE1–QE4 — operational hardening (analytics, lifecycle,        ✅
//             perf, accessibility, hygiene)
// ===========================================================================

// MARK: - Shared primitives (S24 / S25 / S26 engines)

/// Interior wall expressed as unit fractions of the arena/field rect.
/// Convert to screen coords: x_pt = xFrac * arena.width, etc.
/// Wall collision: project ball onto segment → closest point P → if dist < r push out
/// along normal, reflect vel component along normal × wallBounce.
struct WallSegFrac: Equatable {
    let x1, y1, x2, y2: CGFloat
}

/// Circular post or pillar at a fractional field position.
/// Convert to screen coords: cx_pt = pf.cx * field.width, etc.
/// Pillar collision: identical to marble-marble but pillar has infinite mass — ball only.
struct PillarFrac: Equatable {
    let cx, cy: CGFloat   // 0.0–1.0 relative to field bounds
    let r: CGFloat        // radius in points
}

/// Pillar on a Sumo platform in polar coordinates (relative to platform centre).
/// Screen coords: cx = centre.x + cos(angle) × radFrac × currentRadius, etc.
/// Scales automatically as the ring shrinks.
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
///
/// **Bumper count cap — keep ≤ 8.**
/// `collideBumpers()` runs a ball-vs-each-bumper loop every physics tick
/// (O(n) in bumpers).  All current maps use 3–7 bumpers; beyond ~10 the loop
/// overhead becomes measurable at 60 fps.  If you need a denser layout,
/// consider a spatial grid or broad-phase cull first.
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

// MARK: - Comet Clash  (S24)

/// Describes a single Comet Clash arena layout.
/// `walls` are interior `WallSegFrac` segments; `asteroids` are circular rock obstacles.
/// Both use fractions of the full-screen arena (no insets).
struct CometClashMap {
    let name: String
    let walls:     [WallSegFrac]
    let asteroids: [PillarFrac]
}

enum CometClashMaps {
    static let maps: [CometClashMap] = [

        // 1 — Open: classic arena, no obstacles
        CometClashMap(name: "Open",
                      walls: [], asteroids: []),

        // 2 — Asteroid Belt: 5 scattered rocks, open field
        CometClashMap(name: "Asteroid Belt",
                      walls: [],
                      asteroids: [PillarFrac(cx: 0.24, cy: 0.35, r: 22),
                                  PillarFrac(cx: 0.66, cy: 0.24, r: 20),
                                  PillarFrac(cx: 0.44, cy: 0.58, r: 24),
                                  PillarFrac(cx: 0.18, cy: 0.72, r: 18),
                                  PillarFrac(cx: 0.76, cy: 0.66, r: 22)]),

        // 3 — Split: one horizontal wall with a centre gap — two swim lanes
        CometClashMap(name: "Split",
                      walls: [WallSegFrac(x1: 0.05, y1: 0.50, x2: 0.38, y2: 0.50),
                               WallSegFrac(x1: 0.62, y1: 0.50, x2: 0.95, y2: 0.50)],
                      asteroids: []),

        // 4 — Cross: H + V segments each with a centre gap — four quadrants
        CometClashMap(name: "Cross",
                      walls: [WallSegFrac(x1: 0.06, y1: 0.50, x2: 0.38, y2: 0.50),
                               WallSegFrac(x1: 0.62, y1: 0.50, x2: 0.94, y2: 0.50),
                               WallSegFrac(x1: 0.50, y1: 0.06, x2: 0.50, y2: 0.38),
                               WallSegFrac(x1: 0.50, y1: 0.62, x2: 0.50, y2: 0.94)],
                      asteroids: []),

        // 5 — Rock Garden: 8 dense asteroids, no walls
        CometClashMap(name: "Rock Garden",
                      walls: [],
                      asteroids: [PillarFrac(cx: 0.18, cy: 0.28, r: 20),
                                  PillarFrac(cx: 0.46, cy: 0.22, r: 18),
                                  PillarFrac(cx: 0.74, cy: 0.30, r: 22),
                                  PillarFrac(cx: 0.28, cy: 0.52, r: 20),
                                  PillarFrac(cx: 0.64, cy: 0.50, r: 18),
                                  PillarFrac(cx: 0.14, cy: 0.70, r: 22),
                                  PillarFrac(cx: 0.50, cy: 0.72, r: 20),
                                  PillarFrac(cx: 0.80, cy: 0.68, r: 18)]),

        // 6 — Corridor: two long vertical walls forcing a narrow centre lane
        CometClashMap(name: "Corridor",
                      walls: [WallSegFrac(x1: 0.30, y1: 0.06, x2: 0.30, y2: 0.94),
                               WallSegFrac(x1: 0.70, y1: 0.06, x2: 0.70, y2: 0.94)],
                      asteroids: []),

        // 7 — Diamond: 4 angled segments forming a diamond-shaped interior obstacle
        CometClashMap(name: "Diamond",
                      walls: [WallSegFrac(x1: 0.26, y1: 0.50, x2: 0.50, y2: 0.24),
                               WallSegFrac(x1: 0.50, y1: 0.24, x2: 0.74, y2: 0.50),
                               WallSegFrac(x1: 0.74, y1: 0.50, x2: 0.50, y2: 0.76),
                               WallSegFrac(x1: 0.50, y1: 0.76, x2: 0.26, y2: 0.50)],
                      asteroids: []),

        // 8 — Chaos: 3 angled walls + 3 asteroid rocks
        CometClashMap(name: "Chaos",
                      walls: [WallSegFrac(x1: 0.12, y1: 0.20, x2: 0.42, y2: 0.40),
                               WallSegFrac(x1: 0.58, y1: 0.14, x2: 0.88, y2: 0.42),
                               WallSegFrac(x1: 0.22, y1: 0.68, x2: 0.55, y2: 0.82)],
                      asteroids: [PillarFrac(cx: 0.55, cy: 0.58, r: 20),
                                  PillarFrac(cx: 0.32, cy: 0.36, r: 18),
                                  PillarFrac(cx: 0.74, cy: 0.62, r: 22)]),
    ]
}

// MARK: - Gold Rush  (S24)

/// Describes a single Gold Rush arena layout.
/// `walls` are interior segments; fractions of the full arena.
/// Keep yFrac ≥ 0.18 to stay below the HUD (topReserve ≈ 124 pt).
struct GoldRushMap {
    let name: String
    let walls: [WallSegFrac]
}

enum GoldRushMaps {
    static let maps: [GoldRushMap] = [

        // 1 — Open: current layout, no barriers
        GoldRushMap(name: "Open", walls: []),

        // 2 — Lanes: two horizontal dividers with centre gaps — creates 3 swim lanes
        GoldRushMap(name: "Lanes",
                    walls: [WallSegFrac(x1: 0.05, y1: 0.38, x2: 0.42, y2: 0.38),
                             WallSegFrac(x1: 0.58, y1: 0.38, x2: 0.95, y2: 0.38),
                             WallSegFrac(x1: 0.05, y1: 0.66, x2: 0.42, y2: 0.66),
                             WallSegFrac(x1: 0.58, y1: 0.66, x2: 0.95, y2: 0.66)]),

        // 3 — Box: 4 walls forming an open square — centre coin-collection pocket
        GoldRushMap(name: "Box",
                    walls: [WallSegFrac(x1: 0.22, y1: 0.32, x2: 0.78, y2: 0.32),
                             WallSegFrac(x1: 0.22, y1: 0.74, x2: 0.78, y2: 0.74),
                             WallSegFrac(x1: 0.22, y1: 0.32, x2: 0.22, y2: 0.74),
                             WallSegFrac(x1: 0.78, y1: 0.32, x2: 0.78, y2: 0.74)]),

        // 4 — Split: one vertical wall with gaps at top and bottom — two-room arena
        GoldRushMap(name: "Split",
                    walls: [WallSegFrac(x1: 0.50, y1: 0.34, x2: 0.50, y2: 0.68)]),

        // 5 — Pinball: 3 angled walls that deflect marbles unexpectedly
        GoldRushMap(name: "Pinball",
                    walls: [WallSegFrac(x1: 0.14, y1: 0.55, x2: 0.38, y2: 0.36),
                             WallSegFrac(x1: 0.44, y1: 0.30, x2: 0.56, y2: 0.30),
                             WallSegFrac(x1: 0.62, y1: 0.36, x2: 0.86, y2: 0.55)]),

        // 6 — Crossroads: H + V with gaps — four-quadrant coin zones
        GoldRushMap(name: "Crossroads",
                    walls: [WallSegFrac(x1: 0.05, y1: 0.52, x2: 0.38, y2: 0.52),
                             WallSegFrac(x1: 0.62, y1: 0.52, x2: 0.95, y2: 0.52),
                             WallSegFrac(x1: 0.50, y1: 0.20, x2: 0.50, y2: 0.38),
                             WallSegFrac(x1: 0.50, y1: 0.65, x2: 0.50, y2: 0.92)]),

        // 7 — Tight Corners: 4 short diagonal walls in the corners — coins collect in nooks
        GoldRushMap(name: "Tight Corners",
                    walls: [WallSegFrac(x1: 0.05, y1: 0.32, x2: 0.24, y2: 0.20),
                             WallSegFrac(x1: 0.76, y1: 0.20, x2: 0.95, y2: 0.32),
                             WallSegFrac(x1: 0.05, y1: 0.76, x2: 0.24, y2: 0.90),
                             WallSegFrac(x1: 0.76, y1: 0.90, x2: 0.95, y2: 0.76)]),

        // 8 — Maze: 5-wall partial maze — hardest routing
        GoldRushMap(name: "Maze",
                    walls: [WallSegFrac(x1: 0.05, y1: 0.38, x2: 0.48, y2: 0.38),
                             WallSegFrac(x1: 0.52, y1: 0.38, x2: 0.95, y2: 0.52),
                             WallSegFrac(x1: 0.22, y1: 0.65, x2: 0.72, y2: 0.65),
                             WallSegFrac(x1: 0.22, y1: 0.38, x2: 0.22, y2: 0.65),
                             WallSegFrac(x1: 0.72, y1: 0.52, x2: 0.72, y2: 0.82)]),
    ]
}

// MARK: - Sumo Survival  (S25)

/// Describes a single Sumo Survival arena layout.
/// `pillars` are static obstacles in polar coords relative to the platform centre.
/// Their screen position scales with `currentRadius` so they stay on-platform as the
/// ring shrinks: cx = centre.x + cos(p.angle) × p.radFrac × currentRadius.
struct SumoMap {
    let name: String
    let pillars: [SumoPillar]
}

enum SumoMaps {
    private static let π = CGFloat.pi

    static let maps: [SumoMap] = [

        // 1 — Open: classic no-obstacle ring
        SumoMap(name: "Open", pillars: []),

        // 2 — Centre Post: one post dead centre — forces flanking approach
        SumoMap(name: "Centre Post",
                pillars: [SumoPillar(radFrac: 0.00, angle: 0, r: 16)]),

        // 3 — Triangle: 3 posts at 120° — three lanes
        SumoMap(name: "Triangle",
                pillars: [SumoPillar(radFrac: 0.42, angle: 0,          r: 16),
                          SumoPillar(radFrac: 0.42, angle: π * 2 / 3, r: 16),
                          SumoPillar(radFrac: 0.42, angle: π * 4 / 3, r: 16)]),

        // 4 — Cross: 4 posts at 90° — four equal sectors
        SumoMap(name: "Cross",
                pillars: [SumoPillar(radFrac: 0.44, angle: 0,         r: 16),
                          SumoPillar(radFrac: 0.44, angle: π / 2,     r: 16),
                          SumoPillar(radFrac: 0.44, angle: π,         r: 16),
                          SumoPillar(radFrac: 0.44, angle: π * 3 / 2, r: 16)]),

        // 5 — Ring: 5 posts in outer zone — a wall of obstacles
        SumoMap(name: "Ring",
                pillars: [SumoPillar(radFrac: 0.62, angle: 0,             r: 14),
                          SumoPillar(radFrac: 0.62, angle: π * 2 / 5,    r: 14),
                          SumoPillar(radFrac: 0.62, angle: π * 4 / 5,    r: 14),
                          SumoPillar(radFrac: 0.62, angle: π * 6 / 5,    r: 14),
                          SumoPillar(radFrac: 0.62, angle: π * 8 / 5,    r: 14)]),

        // 6 — Dual: 2 opposite posts at mid-radius — divides the platform
        SumoMap(name: "Dual",
                pillars: [SumoPillar(radFrac: 0.40, angle: 0, r: 18),
                          SumoPillar(radFrac: 0.40, angle: π, r: 18)]),

        // 7 — Orbit: 6 small posts in an inner ring — dense gauntlet
        SumoMap(name: "Orbit",
                pillars: [SumoPillar(radFrac: 0.35, angle: 0,             r: 12),
                          SumoPillar(radFrac: 0.35, angle: π / 3,         r: 12),
                          SumoPillar(radFrac: 0.35, angle: π * 2 / 3,     r: 12),
                          SumoPillar(radFrac: 0.35, angle: π,             r: 12),
                          SumoPillar(radFrac: 0.35, angle: π * 4 / 3,     r: 12),
                          SumoPillar(radFrac: 0.35, angle: π * 5 / 3,     r: 12)]),

        // 8 — Star: 4 diagonal mid posts + 1 centre post — combined threat
        SumoMap(name: "Star",
                pillars: [SumoPillar(radFrac: 0.00, angle: 0,          r: 14),
                          SumoPillar(radFrac: 0.44, angle: π / 4,      r: 16),
                          SumoPillar(radFrac: 0.44, angle: π * 3 / 4,  r: 16),
                          SumoPillar(radFrac: 0.44, angle: π * 5 / 4,  r: 16),
                          SumoPillar(radFrac: 0.44, angle: π * 7 / 4,  r: 16)]),
    ]
}

// MARK: - King of the Hill  (S25)

/// Describes a single King of the Hill arena layout.
/// `pillars` are static Cartesian obstacles at fractional positions within the field rect.
struct KOTHMap {
    let name: String
    let pillars: [PillarFrac]
}

enum KOTHMaps {
    static let maps: [KOTHMap] = [

        // 1 — Open: classic open field
        KOTHMap(name: "Open", pillars: []),

        // 2 — Centre Post: one pillar at field centre — zone zig-zags around it
        KOTHMap(name: "Centre Post",
                pillars: [PillarFrac(cx: 0.50, cy: 0.50, r: 20)]),

        // 3 — Four Corners: 4 pillars near corners — pinches the field
        KOTHMap(name: "Four Corners",
                pillars: [PillarFrac(cx: 0.18, cy: 0.22, r: 20),
                          PillarFrac(cx: 0.82, cy: 0.22, r: 20),
                          PillarFrac(cx: 0.18, cy: 0.78, r: 20),
                          PillarFrac(cx: 0.82, cy: 0.78, r: 20)]),

        // 4 — Gauntlet: 4 pillars in a horizontal line — north–south split
        KOTHMap(name: "Gauntlet",
                pillars: [PillarFrac(cx: 0.20, cy: 0.50, r: 18),
                          PillarFrac(cx: 0.40, cy: 0.50, r: 18),
                          PillarFrac(cx: 0.60, cy: 0.50, r: 18),
                          PillarFrac(cx: 0.80, cy: 0.50, r: 18)]),

        // 5 — Maze Thirds: 6 pillars in two staggered rows — winding paths
        KOTHMap(name: "Maze Thirds",
                pillars: [PillarFrac(cx: 0.18, cy: 0.36, r: 18),
                          PillarFrac(cx: 0.44, cy: 0.26, r: 18),
                          PillarFrac(cx: 0.70, cy: 0.36, r: 18),
                          PillarFrac(cx: 0.30, cy: 0.64, r: 18),
                          PillarFrac(cx: 0.56, cy: 0.74, r: 18),
                          PillarFrac(cx: 0.82, cy: 0.64, r: 18)]),

        // 6 — Triangle: 3 large pillars — three approach lanes
        KOTHMap(name: "Triangle",
                pillars: [PillarFrac(cx: 0.50, cy: 0.24, r: 22),
                          PillarFrac(cx: 0.22, cy: 0.72, r: 22),
                          PillarFrac(cx: 0.78, cy: 0.72, r: 22)]),

        // 7 — Dumbbell: 2 large pillars flanking centre — forces play to the edges
        KOTHMap(name: "Dumbbell",
                pillars: [PillarFrac(cx: 0.26, cy: 0.50, r: 26),
                          PillarFrac(cx: 0.74, cy: 0.50, r: 26)]),

        // 8 — Tight: 8 small scattered pillars — densest map
        KOTHMap(name: "Tight",
                pillars: [PillarFrac(cx: 0.20, cy: 0.26, r: 14),
                          PillarFrac(cx: 0.50, cy: 0.20, r: 14),
                          PillarFrac(cx: 0.80, cy: 0.26, r: 14),
                          PillarFrac(cx: 0.30, cy: 0.50, r: 14),
                          PillarFrac(cx: 0.70, cy: 0.50, r: 14),
                          PillarFrac(cx: 0.20, cy: 0.74, r: 14),
                          PillarFrac(cx: 0.50, cy: 0.80, r: 14),
                          PillarFrac(cx: 0.80, cy: 0.74, r: 14)]),
    ]
}

// MARK: - Marble Cup  (S26)

/// Describes a single Marble Cup pitch layout.
/// `goalWidthFrac` overrides the default 0.42 (fraction of pitch width).
/// `sidePosts` are circular bumpers pinned near the left/right pitch walls at fractional
/// y-positions; `side` selects which wall(s) get a post.
/// `midBumpers` are floating circular bumpers at fractional pitch positions.
struct MarbleCupMap {
    enum Side { case left, right, both }
    let name: String
    let goalWidthFrac: CGFloat
    let sidePosts: [(yFrac: CGFloat, side: Side)]
    let midBumpers: [PillarFrac]
}

enum MarbleCupMaps {
    static let maps: [MarbleCupMap] = [

        // 1 — Standard: default layout
        MarbleCupMap(name: "Standard",
                     goalWidthFrac: 0.42, sidePosts: [], midBumpers: []),

        // 2 — Tight Goals: narrower mouth — precision required
        MarbleCupMap(name: "Tight Goals",
                     goalWidthFrac: 0.30, sidePosts: [], midBumpers: []),

        // 3 — Wide Open: wider mouth — easier scoring
        MarbleCupMap(name: "Wide Open",
                     goalWidthFrac: 0.55, sidePosts: [], midBumpers: []),

        // 4 — Side Posts: posts on both walls deflect long shots
        MarbleCupMap(name: "Side Posts",
                     goalWidthFrac: 0.42,
                     sidePosts: [(yFrac: 0.34, side: .both),
                                 (yFrac: 0.66, side: .both)],
                     midBumpers: []),

        // 5 — Rebounder: 2 midfield bumpers cause wild ball paths
        MarbleCupMap(name: "Rebounder",
                     goalWidthFrac: 0.42,
                     sidePosts: [],
                     midBumpers: [PillarFrac(cx: 0.28, cy: 0.50, r: 14),
                                  PillarFrac(cx: 0.72, cy: 0.50, r: 14)]),

        // 6 — Chaos Pit: right-side posts + 2 mid bumpers — most chaotic
        MarbleCupMap(name: "Chaos Pit",
                     goalWidthFrac: 0.42,
                     sidePosts: [(yFrac: 0.40, side: .right),
                                 (yFrac: 0.62, side: .right)],
                     midBumpers: [PillarFrac(cx: 0.38, cy: 0.40, r: 12),
                                  PillarFrac(cx: 0.36, cy: 0.66, r: 12)]),

        // 7 — Funnel: narrower goal + posts on both sides guide shots inward
        MarbleCupMap(name: "Funnel",
                     goalWidthFrac: 0.38,
                     sidePosts: [(yFrac: 0.38, side: .both),
                                 (yFrac: 0.62, side: .both)],
                     midBumpers: []),

        // 8 — Pro League: tightest goal + 4 wall posts + 1 centre bumper
        MarbleCupMap(name: "Pro League",
                     goalWidthFrac: 0.34,
                     sidePosts: [(yFrac: 0.32, side: .both),
                                 (yFrac: 0.68, side: .both)],
                     midBumpers: [PillarFrac(cx: 0.50, cy: 0.50, r: 16)]),
    ]
}
