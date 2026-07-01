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

extension Loadout {
    /// Build a preview Loadout from a CosmeticBundle: the first cosmetic in each
    /// slot the bundle defines, falling back to the starter/classic look for any
    /// slot it omits (e.g. Planets carries only balls).  Bundles carry no
    /// boundary, so the boundary is always the classic wall.
    init(bundle: CosmeticBundle) {
        self.init(
            ball:     bundle.balls.first  ?? .red,
            trail:    bundle.trails.first ?? .graphite,
            goal:     bundle.goals.first  ?? .target,
            floor:    bundle.floors.first ?? .classic,
            pit:      bundle.pits.first   ?? .classic,
            boundary: .classic
        )
    }
}

// ===========================================================================
// LoadoutDiorama — a small, looping diorama of a loadout "in action".
//
// Choreography (one clean, legible hero run that reads like real play):
//   the marble starts lower-left and arcs up-and-right on a decelerating rise,
//   banks off the wall in the top-middle, then arcs down-and-right on an
//   accelerating fall into the goal on the right — clearing, the whole way, the
//   pit along the bottom.  A tail in the trail colour follows.
//
// The motion is a deterministic two-arc kinematic path (rise → bank → fall),
// not a hand-drawn spline, so it never curls or overshoots and the trail is
// simply the marble's own swept path.  The scene fills the caller's frame; the
// layout is symmetric (wall top-centre, pit bottom-centre, goal right) so it
// reads coherently at any aspect the callers use — the wide profile card, the
// narrow catalog sliver, the mode-selector cell — without stretching into
// nonsense.  The ball's roll line and bank apex are derived per-size from its
// pixel radius, so it sits exactly on the floor and just kisses the wall at any
// size.  Respects Reduce Motion by freezing on the final in-goal frame.
// ===========================================================================
struct LoadoutDiorama: View {
    let loadout: Loadout
    /// Corner treatment.  Default rounds + hairlines the diorama itself; pass
    /// `nil` when an outer container already clips (e.g. the challenge-pack
    /// showcase card) so the two clips don't fight and double-border.
    var cornerRadius: CGFloat? = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // ── Scene geometry (normalised: x 0→1 left→right, y 0→1 top→bottom) ───────
    // Only x-anchors and the fixed surfaces live here; the ball's roll line and
    // bank apex are derived per-size from the ball radius (see startPt/bouncePt)
    // so it sits on the floor and kisses the wall at any size.
    private let floorTopY:  CGFloat = 0.86           // top surface of the floor
    private let floorThick: CGFloat = 0.24
    private let wallX0: CGFloat = 0.37, wallX1: CGFloat = 0.63   // top-middle wall
    private let wallY0: CGFloat = 0.11, wallY1: CGFloat = 0.19
    private let pitX0:  CGFloat = 0.34, pitX1:  CGFloat = 0.66   // bottom pit gap
    private let goalC  = CGPoint(x: 0.86, y: 0.60)   // raised target on the right
    private let ctrl1  = CGPoint(x: 0.30, y: 0.40)   // arc-1 (rise) control
    private let ctrl2  = CGPoint(x: 0.68, y: 0.385)  // arc-2 (fall) control

    // Loop timing (seconds): arc-1 end (bank), arc-2 end (in goal), loop end.
    private let tArc1 = 1.15, tArc2 = 2.30, tLoop = 3.25
    private let trailDur = 0.42

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            let scene = ZStack {
                background
                setPieces(s)
                if reduceMotion {
                    movers(s, t: tArc2, alpha: 1.0)          // frozen in the goal
                } else {
                    TimelineView(.animation) { tl in
                        let c = cycle(at: tl.date)
                        movers(s, t: c.t, alpha: c.alpha)
                    }
                }
            }
            // Always clip to the frame so the floor can't spill past the edge;
            // only round + hairline it when we own the corner.
            if let r = cornerRadius {
                scene
                    .clipShape(RoundedRectangle(cornerRadius: r))
                    .overlay(RoundedRectangle(cornerRadius: r)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8))
            } else {
                scene.clipShape(Rectangle())
            }
        }
    }

    // ── Backdrop ──────────────────────────────────────────────────────────────
    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.06, blue: 0.10),
                     Color(red: 0.08, green: 0.09, blue: 0.14)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // ── Static set pieces: floor split by the bottom pit, the pit well, the
    //    top-middle bank wall, and the raised goal target ─────────────────────
    @ViewBuilder
    private func setPieces(_ s: CGSize) -> some View {
        // Floor ledges either side of the pit; they run past the frame edge so
        // no gap shows under the floor.
        ledge(rectIn(0.0, floorTopY, pitX0, floorThick, s))
        ledge(rectIn(pitX1, floorTopY, 1.0 - pitX1, floorThick, s))

        // Pit — a darkening well in the gap between the ledges.
        pitWell(rectIn(pitX0, floorTopY, pitX1 - pitX0, floorThick * 0.7, s))

        // Bank wall in the top-middle, struck from below.
        wallBar(rectIn(wallX0, wallY0, wallX1 - wallX0, wallY1 - wallY0, s))

        // Raised goal target the marble settles into (Roll Along goals glow).
        // The gradient's endRadius is threaded to the drawn size so multi-ring
        // goal skins keep their rings instead of collapsing to a dot.
        let gd = goalDia(s)
        ZStack {
            Circle()
                .fill(GoalSkin.previewGradient(for: loadout.goal, endRadius: gd / 2))
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.4))
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 2)
                .scaleEffect(1.35)
                .blur(radius: 2)
        }
        .frame(width: gd, height: gd)
        .position(toFrame(goalC, s))
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

    private func wallBar(_ r: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(loadout.boundary.color)
            // Lit underside (the face the ball strikes) + a darker outline.
            .overlay(alignment: .bottom) {
                Rectangle().fill(loadout.boundary.edgeColor.opacity(0.9)).frame(height: 2)
            }
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(loadout.boundary.deepColor, lineWidth: 0.8))
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }

    // ── Moving parts: the trail tail + the ball ──────────────────────────────
    @ViewBuilder
    private func movers(_ s: CGSize, t: Double, alpha: Double) -> some View {
        let bd = ballDia(s)
        let tt = min(t, tArc2)
        let pts = trailSamples(s, endTime: tt)     // head → tail, in frame px

        // Trail: a faint white underlay (so even dark trails read on the dark
        // backdrop) beneath the colour, which tapers + fades toward the past.
        Canvas { ctx, _ in
            guard pts.count >= 2 else { return }
            var underlay = Path(); underlay.addLines(pts)
            ctx.stroke(underlay, with: .color(.white.opacity(0.10 * alpha)),
                       style: StrokeStyle(lineWidth: bd * 0.50, lineCap: .round, lineJoin: .round))
            let n = pts.count
            for i in 0..<(n - 1) {
                let age = 1 - Double(i) / Double(n - 1)         // 1 at head → 0 at tail
                var seg = Path(); seg.move(to: pts[i]); seg.addLine(to: pts[i + 1])
                let w  = bd * 0.42 * CGFloat(0.35 + 0.65 * age)
                let op = alpha * (0.20 + 0.75 * age)
                ctx.stroke(seg, with: .color(trailStroke.opacity(op)),
                           style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
        }

        MiniBall(skin: loadout.ball, size: bd)
            .rotationEffect(.degrees(spinDegrees(tt)))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .position(toFrame(pos(at: tt, s), s))
            .opacity(alpha)
    }

    private var trailStroke: Color {
        loadout.trail == .none ? Color.white.opacity(0.6) : loadout.trail.color
    }

    /// The tail as frame-space points, head (at the ball) first.  A stateless
    /// look-back over the parametric path — the look-back time is clamped to 0
    /// so a stub exists from the very first frame (no empty subpath).
    private func trailSamples(_ s: CGSize, endTime: Double) -> [CGPoint] {
        let steps = 26
        var pts: [CGPoint] = []
        pts.reserveCapacity(steps + 1)
        for k in 0...steps {
            let t = max(0, endTime - (Double(k) / Double(steps)) * trailDur)
            pts.append(toFrame(pos(at: min(t, tArc2), s), s))
        }
        return pts
    }

    // ── The ball's journey: two quadratic arcs meeting at the bank wall ───────
    /// Ball-centre position at run-time `t` (seconds); clamps to the goal after
    /// arrival.  Arc 1 rises and decelerates into the wall; arc 2 falls and
    /// accelerates into the goal — mirroring gravity, so it reads as real play.
    private func pos(at t: Double, _ s: CGSize) -> CGPoint {
        let start = startPt(s), bounce = bouncePt(s)
        if t <= 0 { return start }
        if t < tArc1 {
            let tau = CGFloat(t / tArc1)
            let u = 1 - (1 - tau) * (1 - tau)        // rise: fast → slow
            return qbez(start, ctrl1, bounce, u)
        }
        if t < tArc2 {
            let tau = CGFloat((t - tArc1) / (tArc2 - tArc1))
            let u = tau * tau                        // fall: slow → fast
            return qbez(bounce, ctrl2, goalC, u)
        }
        return goalC
    }

    private func qbez(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ u: CGFloat) -> CGPoint {
        let m = 1 - u
        return CGPoint(x: m * m * a.x + 2 * m * u * c.x + u * u * b.x,
                       y: m * m * a.y + 2 * m * u * c.y + u * u * b.y)
    }

    /// Spin the marble ~300°/s while it travels; frozen once it rests in the goal.
    private func spinDegrees(_ tt: Double) -> Double { tt * 300 }

    // ── Per-size anchoring ────────────────────────────────────────────────────
    // Ball/goal diameters are clamped in points so the hero elements stay legible
    // at the small callers (and don't over-inflate at the large ones).
    private func ballDia(_ s: CGSize) -> CGFloat { min(38, max(18, min(s.width, s.height) * 0.17)) }
    private func goalDia(_ s: CGSize) -> CGFloat { min(40, max(22, min(s.width, s.height) * 0.22)) }
    /// The ball radius as a fraction of height — used to seat the ball on the
    /// floor and to place the bank apex so its top just kisses the wall.
    private func radN(_ s: CGSize) -> CGFloat { (ballDia(s) / 2) / max(1, s.height) }
    private func startPt(_ s: CGSize) -> CGPoint  { CGPoint(x: 0.12, y: floorTopY - radN(s)) }
    private func bouncePt(_ s: CGSize) -> CGPoint { CGPoint(x: 0.50, y: wallY1 + radN(s)) }

    // ── Helpers ──────────────────────────────────────────────────────────────
    private func toFrame(_ p: CGPoint, _ s: CGSize) -> CGPoint {
        CGPoint(x: p.x * s.width, y: p.y * s.height)
    }
    private func rectIn(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                        _ s: CGSize) -> CGRect {
        CGRect(x: x * s.width, y: y * s.height, width: w * s.width, height: h * s.height)
    }

    /// Loop clock → (run-time `t`, `alpha`).  The ball reaches the goal at
    /// `tArc2` and rests until `tLoop`; alpha fades in/out at the seam to hide
    /// the reset.
    private func cycle(at date: Date) -> (t: Double, alpha: Double) {
        let raw = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: tLoop)
        let alpha: Double
        if raw < 0.10              { alpha = raw / 0.10 }
        else if raw > tLoop - 0.18 { alpha = max(0, (tLoop - raw) / 0.18) }
        else                       { alpha = 1.0 }
        return (raw, alpha)
    }
}
