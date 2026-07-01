import SwiftUI

// ===========================================================================
// Loadout — a value-typed bundle of the cosmetics a diorama draws "in action".
// Music is carried for labelling/completeness but is heard, not drawn.  Value
// semantics mean a diorama renders identically wherever it's reused: the
// profile's "My Loadout", the catalog collection popup, and the challenge-pack
// showcase all feed the same LoadoutDiorama a Loadout.
// ===========================================================================
struct Loadout: Equatable {
    var ball:     BallSkin
    var trail:    TrailColor
    var goal:     GoalSkin
    var floor:    Floor
    var pit:      Pit
    var boundary: Boundary

    init(ball: BallSkin, trail: TrailColor, goal: GoalSkin,
         floor: Floor, pit: Pit, boundary: Boundary) {
        self.ball = ball; self.trail = trail; self.goal = goal
        self.floor = floor; self.pit = pit; self.boundary = boundary
    }
}

// ===========================================================================
// LoadoutDiorama — a small, looping diorama of a loadout "in action".
//
// Choreography (one continuous, legible run that ENDS at the goal and never
// crosses it early):
//   roll in along the floor → hop up and over the pit → bank off the boundary
//   wall on the right → arc up and settle into the goal, which sits raised in
//   front of the wall.  A tail in the trail colour follows the whole way.
//
// Everything hangs off a single shared ground line derived from the ball's
// pixel radius, so the ball always sits *on* the floor (no float/sink), and the
// goal is a clearly-raised target the ball drops into (not a disc half-buried
// in the floor).  Respects Reduce Motion by freezing on the final in-goal frame.
// ===========================================================================
struct LoadoutDiorama: View {
    let loadout: Loadout

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // ── Scene geometry (normalised: x 0→1 left→right, y 0→1 top→bottom) ──────
    // Only x-anchors and the floor surface are fixed here; the ball's roll line
    // is derived per-size from the ball radius (see `rollY`) so it sits exactly
    // on the floor at any size/aspect.
    private let floorTopY:  CGFloat = 0.74   // top surface of the floor
    private let floorThick: CGFloat = 0.22
    private let pitCenterX: CGFloat = 0.33
    private let pitHalf:    CGFloat = 0.085
    private let wallInnerX: CGFloat = 0.85   // left (struck) face of the wall
    private let wallOuterX: CGFloat = 0.99
    private let wallTopY:   CGFloat = 0.14
    private let goalCenter  = CGPoint(x: 0.66, y: 0.37)   // raised target
    private let hopHeight:  CGFloat = 0.22   // apex rise above the roll line
    private let bankApex    = CGPoint(x: 0.75, y: 0.27)   // post-bounce high point

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            let rollY = self.rollY(s)
            let path  = self.path(rollY: rollY)
            ZStack {
                background
                setPieces(s)
                if reduceMotion {
                    movers(s, path: path, f: 1.0, alpha: 1.0)
                } else {
                    TimelineView(.animation) { tl in
                        let c = Self.cycle(at: tl.date)
                        movers(s, path: path, f: c.f, alpha: c.alpha)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8))
        }
    }

    // ── Backdrop ────────────────────────────────────────────────────────────
    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.06, blue: 0.10),
                     Color(red: 0.08, green: 0.09, blue: 0.14)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // ── Static set pieces: floor (split by the pit), pit well, boundary wall,
    //    and the raised goal target ─────────────────────────────────────────
    @ViewBuilder
    private func setPieces(_ s: CGSize) -> some View {
        let pitLeft  = pitCenterX - pitHalf
        let pitRight = pitCenterX + pitHalf

        // Floor ledges, left + right of the pit gap.  The right ledge runs under
        // the wall to the scene edge.
        ledge(rect(0.0, floorTopY, pitLeft, floorThick, s))
        ledge(rect(pitRight, floorTopY, 1.0 - pitRight, floorThick, s))

        // Pit — a darkening well between the ledges.
        pitWell(rect(pitLeft, floorTopY, pitRight - pitLeft, floorThick + 0.06, s))

        // Boundary wall on the right that the ball banks off.
        wall(rect(wallInnerX, wallTopY, wallOuterX - wallInnerX,
                  floorTopY - wallTopY, s))

        // Raised goal target the ball settles into.  A soft halo sells it as an
        // intentional in-air target (Roll Along goals glow), not a floating disc.
        let gd = goalD(s)
        ZStack {
            Circle()
                .fill(GoalSkin.previewGradient(for: loadout.goal))
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.4))
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 2)
                .scaleEffect(1.35)
                .blur(radius: 2)
        }
        .frame(width: gd, height: gd)
        .position(scale(goalCenter, s))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }

    private func ledge(_ r: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(loadout.floor.color)
            // Top highlight so even near-black floors read against the backdrop.
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 3)
                .stroke(Color.black.opacity(0.25), lineWidth: 0.5))
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }

    private func pitWell(_ r: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(loadout.pit.color)
            .overlay(
                LinearGradient(colors: [.clear, .black.opacity(0.5)],
                               startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            )
            .overlay(RoundedRectangle(cornerRadius: 5)
                .stroke(Color.black.opacity(0.35), lineWidth: 0.8))
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }

    private func wall(_ r: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(loadout.boundary.color)
            // Lit left face (the side the ball strikes) + a darker outline.
            .overlay(alignment: .leading) {
                Rectangle().fill(loadout.boundary.edgeColor.opacity(0.9)).frame(width: 2)
            }
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(loadout.boundary.deepColor, lineWidth: 0.8))
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }

    // ── Moving parts: the trail tail + the ball ──────────────────────────────
    @ViewBuilder
    private func movers(_ s: CGSize, path pts: [CGPoint], f: CGFloat, alpha: Double) -> some View {
        let n    = pts.count
        let bIdx = clampIndex(Int((f * CGFloat(n - 1)).rounded()), n)
        let aIdx = clampIndex(Int((max(0, f - 0.34) * CGFloat(n - 1)).rounded()), n)
        let bd   = ballD(s)

        if bIdx > aIdx {
            trailPath(pts, from: aIdx, to: bIdx, s: s)
                .stroke(trailStroke,
                        style: StrokeStyle(lineWidth: bd * 0.42,
                                           lineCap: .round, lineJoin: .round))
                .opacity(alpha)
        }

        MiniBall(skin: loadout.ball, size: bd)
            .rotationEffect(.degrees(Double(f) * 760))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .position(scale(pts[bIdx], s))
            .opacity(alpha)
    }

    private var trailStroke: Color {
        loadout.trail == .none ? Color.white.opacity(0.5) : loadout.trail.color
    }

    private func trailPath(_ pts: [CGPoint], from a: Int, to b: Int, s: CGSize) -> Path {
        var p = Path()
        guard a < b else { return p }
        p.move(to: scale(pts[a], s))
        for i in (a + 1)...b { p.addLine(to: scale(pts[i], s)) }
        return p
    }

    // ── The ball's journey ───────────────────────────────────────────────────
    /// Ball-centre roll line: sits exactly on the floor for the current size.
    private func rollY(_ s: CGSize) -> CGFloat {
        let r = ballD(s) / 2
        return floorTopY - r / max(1, s.height)
    }

    /// Waypoints (ball centre) → densified Catmull-Rom polyline.  Authored from
    /// the per-size roll line so the floor phases hug the floor precisely.
    private func path(rollY: CGFloat) -> [CGPoint] {
        let wps: [CGPoint] = [
            CGPoint(x: 0.05, y: rollY),                       // start left on floor
            CGPoint(x: 0.21, y: rollY),                       // roll right
            CGPoint(x: pitCenterX, y: rollY - hopHeight),     // hop apex over the pit
            CGPoint(x: 0.47, y: rollY),                       // land past the pit
            CGPoint(x: 0.72, y: rollY),                       // roll on (passes UNDER the raised goal)
            CGPoint(x: wallInnerX - 0.02, y: rollY - 0.06),   // graze the wall low → bank
            bankApex,                                         // ricochet up-left
            goalCenter,                                       // settle into the goal
        ]
        return Self.catmullRom(wps, samplesPerSegment: 24)
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    private func scale(_ p: CGPoint, _ s: CGSize) -> CGPoint {
        CGPoint(x: p.x * s.width, y: p.y * s.height)
    }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                      _ s: CGSize) -> CGRect {
        CGRect(x: x * s.width, y: y * s.height, width: w * s.width, height: h * s.height)
    }
    private func ballD(_ s: CGSize) -> CGFloat {
        min(38, max(18, min(s.width, s.height) * 0.17))
    }
    private func goalD(_ s: CGSize) -> CGFloat {
        min(40, max(22, min(s.width, s.height) * 0.22))
    }
    private func clampIndex(_ i: Int, _ n: Int) -> Int { max(0, min(n - 1, i)) }

    /// Loop clock → (position fraction `f`, `alpha`).  The ball reaches the goal
    /// at 82% and rests; alpha fades in/out at the seam to hide the reset.
    private static func cycle(at date: Date) -> (f: CGFloat, alpha: Double) {
        let period = 4.6
        let raw = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period          // 0…1
        let f = smoothstep(CGFloat(min(1.0, raw / 0.82)))
        let alpha: Double
        if raw < 0.05      { alpha = raw / 0.05 }                       // fade in
        else if raw > 0.93 { alpha = max(0, (1.0 - raw) / 0.07) }       // fade out
        else               { alpha = 1.0 }
        return (f, alpha)
    }
    private static func smoothstep(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t)); return x * x * (3 - 2 * x)
    }

    /// Catmull-Rom spline through `pts`, sampled into a dense polyline.
    private static func catmullRom(_ pts: [CGPoint],
                                   samplesPerSegment: Int) -> [CGPoint] {
        guard pts.count >= 2 else { return pts }
        var out: [CGPoint] = []
        let n = pts.count
        for i in 0..<(n - 1) {
            let p0 = pts[max(0, i - 1)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(n - 1, i + 2)]
            for k in 0..<samplesPerSegment {
                let t = CGFloat(k) / CGFloat(samplesPerSegment)
                out.append(catmull(p0, p1, p2, p3, t))
            }
        }
        out.append(pts[n - 1])
        return out
    }
    private static func catmull(_ p0: CGPoint, _ p1: CGPoint,
                                _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let t2 = t * t, t3 = t2 * t
        func c(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat {
            0.5 * (2 * b + (-a + cc) * t
                   + (2 * a - 5 * b + 4 * cc - d) * t2
                   + (-a + 3 * b - 3 * cc + d) * t3)
        }
        return CGPoint(x: c(p0.x, p1.x, p2.x, p3.x),
                       y: c(p0.y, p1.y, p2.y, p3.y))
    }
}
