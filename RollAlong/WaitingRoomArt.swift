import SwiftUI

// ===========================================================================
// The Waiting Room collection's art (1.1): the Roll Along ball, floor, pit and
// boundary redrawn in a shiny, colour-shifting foil.  Red ball, white floor,
// black pit, grey boundary, each with:
//   • crinkled foil facets — fixed (seeded), so nothing jumps between frames;
//   • an iridescent sheen whose hue drifts slowly round the colour wheel;
//   • a soft band of light that slides across, as when foil is tilted.
//
// NOT YET LOCKED.  The owner reviews this art before it is added to
// tools/cosmetic-calendar/locked_pieces.json.
//
// Motion: floors stay at or under 15 frames a second, balls 20, walls 30
// (the quality standard).  Every hue change is slow (a full turn of the
// colour wheel takes more than a minute) and nothing flashes.  Under Reduce
// Motion, or on a frozen tile, everything holds still on one frame.
// ===========================================================================
enum FoilArt {
    /// An iridescent tint: `phase` turns of the colour wheel.
    static func tint(_ phase: Double, saturation: Double, brightness: Double) -> Color {
        let h = phase - phase.rounded(.down)
        return Color(hue: h, saturation: saturation, brightness: brightness)
    }

    /// One crinkled-foil facet: a triangle, and a fixed per-facet value
    /// (0…1) that sets how it catches the light.
    struct Facet {
        let path: Path
        let center: CGPoint
        let value: Double
    }

    /// Crinkled foil over `rect`: a jittered grid of points, each cell split
    /// into two triangles.  Fixed for a given seed.
    static func facets(in rect: CGRect, columns: Int, rows: Int, seed: UInt64) -> [Facet] {
        var rng = SeededRNG(seed: seed)
        let cw = rect.width / CGFloat(columns), ch = rect.height / CGFloat(rows)
        var points: [[CGPoint]] = []
        for j in 0...rows {
            var row: [CGPoint] = []
            for i in 0...columns {
                let edgeX = i == 0 || i == columns, edgeY = j == 0 || j == rows
                let jx = edgeX ? 0 : (CGFloat(rng.nextUnit()) - 0.5) * cw * 0.7
                let jy = edgeY ? 0 : (CGFloat(rng.nextUnit()) - 0.5) * ch * 0.7
                row.append(CGPoint(x: rect.minX + CGFloat(i) * cw + jx,
                                   y: rect.minY + CGFloat(j) * ch + jy))
            }
            points.append(row)
        }
        var out: [Facet] = []
        for j in 0..<rows {
            for i in 0..<columns {
                let a = points[j][i], b = points[j][i + 1]
                let c = points[j + 1][i + 1], d = points[j + 1][i]
                let flip = rng.nextUnit() < 0.5
                let tris: [[CGPoint]] = flip ? [[a, b, c], [a, c, d]] : [[a, b, d], [b, c, d]]
                for tri in tris {
                    var p = Path()
                    p.move(to: tri[0]); p.addLine(to: tri[1]); p.addLine(to: tri[2]); p.closeSubpath()
                    let cx = (tri[0].x + tri[1].x + tri[2].x) / 3
                    let cy = (tri[0].y + tri[1].y + tri[2].y) / 3
                    out.append(Facet(path: p, center: CGPoint(x: cx, y: cy), value: rng.nextUnit()))
                }
            }
        }
        return out
    }

    /// Where the sliding band of light is, 0…1 across, at time `t`: it
    /// drifts back and forth over about 14 seconds.
    static func sheenPosition(_ t: Double, offset: Double = 0) -> Double {
        0.5 + 0.62 * sin(t * 0.45 + offset)
    }

    // MARK: Ball

    /// The Waiting Room ball: red foil.  Drawn in the ball's square; the
    /// caller clips it to a circle.
    static func drawBall(_ ctx: inout GraphicsContext, size: CGSize, t: Double, colors: [Color]) {
        let r = min(size.width, size.height) / 2
        let cx = size.width / 2, cy = size.height / 2
        let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

        // 1. The red sphere.
        ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
            Gradient(colors: colors),
            center: CGPoint(x: cx - r * 0.30, y: cy - r * 0.32),
            startRadius: 0, endRadius: r * 1.25))

        // 2. Crinkled facets: some catch light, some fall into shade.
        let hueBase = t * 0.012
        for facet in facets(in: sphere, columns: 4, rows: 4, seed: 0x5A17_0F01) {
            if facet.value > 0.5 {
                ctx.fill(facet.path, with: .color(.white.opacity(0.05 + 0.12 * (facet.value - 0.5))))
            } else {
                ctx.fill(facet.path, with: .color(.black.opacity(0.10 * (0.5 - facet.value))))
            }
        }
        // 3. Iridescent sheen over the facets, its hue drifting slowly.
        var glow = ctx
        glow.blendMode = .plusLighter
        for facet in facets(in: sphere, columns: 4, rows: 4, seed: 0x5A17_0F01) {
            let across = Double((facet.center.x - sphere.minX) / sphere.width)
            let phase = hueBase + facet.value * 0.35 + across * 0.25
            glow.fill(facet.path, with: .color(tint(phase, saturation: 0.55, brightness: 1).opacity(0.14)))
        }
        // 4. The sliding band of light.
        let pos = CGFloat(sheenPosition(t))
        let bandCenter = CGPoint(x: sphere.minX + sphere.width * pos, y: sphere.minY + sphere.height * pos)
        glow.fill(Path(ellipseIn: sphere), with: .linearGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: tint(hueBase + 0.15, saturation: 0.35, brightness: 1).opacity(0.38), location: 0.5),
                .init(color: .clear, location: 1),
            ]),
            // Along the diagonal, so the band itself lies across it.
            startPoint: CGPoint(x: bandCenter.x - r * 0.4, y: bandCenter.y - r * 0.4),
            endPoint: CGPoint(x: bandCenter.x + r * 0.4, y: bandCenter.y + r * 0.4)))

        // 5. Rim shade and a crisp highlight.
        ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
            Gradient(stops: [.init(color: .clear, location: 0.70),
                             .init(color: .black.opacity(0.32), location: 1.0)]),
            center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
        let hl = CGRect(x: cx - r * 0.52, y: cy - r * 0.62, width: r * 0.42, height: r * 0.26)
        ctx.fill(Path(ellipseIn: hl), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.85), .white.opacity(0)]),
            center: CGPoint(x: hl.midX, y: hl.midY), startRadius: 0, endRadius: hl.width * 0.6))
    }

    // MARK: Floor

    /// The Waiting Room floor's sheen over its silvery white base.  Calm on
    /// purpose: the largest surface must never pull the eye from the ball.
    /// No line or tint here goes above 14 % opacity.
    static func drawFloor(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let rect = CGRect(origin: .zero, size: size)
        let hueBase = t * 0.010
        // 1. Crinkled facets, large and faint.
        let cell: CGFloat = 70
        let cols = max(3, Int(size.width / cell)), rows = max(3, Int(size.height / cell))
        for facet in facets(in: rect, columns: cols, rows: rows, seed: 0x5A17_F100) {
            if facet.value > 0.55 {
                ctx.fill(facet.path, with: .color(.white.opacity(0.10 * (facet.value - 0.55) / 0.45)))
            } else if facet.value < 0.35 {
                ctx.fill(facet.path, with: .color(Color(white: 0.55).opacity(0.10 * (0.35 - facet.value) / 0.35)))
            }
        }
        // 2. Wide pastel bands drifting diagonally: the colour shift.
        let span = size.width + size.height
        for k in 0..<3 {
            let pos = CGFloat(sheenPosition(t * 0.6, offset: Double(k) * 2.1)) * span - size.height * 0.5
            let c = tint(hueBase + Double(k) * 0.33, saturation: 0.40, brightness: 1)
            ctx.fill(Path(rect), with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: c.opacity(0.14), location: 0.5),
                    .init(color: .clear, location: 1),
                ]),
                startPoint: CGPoint(x: pos - 120, y: 0),
                endPoint: CGPoint(x: pos + 120, y: size.height * 0.45)))
        }
        // 3. A few glints that brighten and fade slowly (each over 4+ s).
        var rng = SeededRNG(seed: 0x5A17_6117)
        let glints = min(24, max(6, Int(size.width * size.height / 20000)))
        for i in 0..<glints {
            let x = CGFloat(rng.nextUnit()) * size.width
            let y = CGFloat(rng.nextUnit()) * size.height
            let phase = rng.nextUnit() * 6.283
            let level = max(0, sin(t * 0.7 + phase + Double(i)))
            guard level > 0.05 else { continue }
            let g = 2.5 + 2.5 * CGFloat(level)
            let c = tint(hueBase + Double(i) * 0.13, saturation: 0.30, brightness: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: x - g, y: y - g, width: g * 2, height: g * 2)),
                     with: .color(c.opacity(0.14 * level)))
        }
    }

    // MARK: Pit

    /// The Waiting Room pit: black foil, its facet edges catching thin,
    /// slowly shifting colour.
    static func drawPit(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let rect = CGRect(origin: .zero, size: size)
        let hueBase = t * 0.015
        let cell: CGFloat = 26
        let cols = max(2, Int(size.width / cell)), rows = max(1, Int(size.height / cell))
        let all = facets(in: rect, columns: cols, rows: rows, seed: 0x5A17_B17)
        for facet in all {
            ctx.fill(facet.path, with: .color(Color(white: 0.04 + 0.08 * facet.value)))
        }
        var glow = ctx
        glow.blendMode = .plusLighter
        for facet in all {
            let across = Double(facet.center.x / max(1, size.width))
            let c = tint(hueBase + across * 0.4 + facet.value * 0.2, saturation: 0.65, brightness: 0.9)
            glow.stroke(facet.path, with: .color(c.opacity(0.10 + 0.20 * facet.value)), lineWidth: 0.7)
        }
        let pos = CGFloat(sheenPosition(t, offset: 1.3))
        glow.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: tint(hueBase + 0.5, saturation: 0.5, brightness: 1).opacity(0.16), location: 0.5),
                .init(color: .clear, location: 1),
            ]),
            startPoint: CGPoint(x: size.width * pos - 40, y: 0),
            endPoint: CGPoint(x: size.width * pos + 40, y: size.height)))
    }
}

// ---------------------------------------------------------------------------
// The views the game's floor, pit and boundary renderers show for the
// Waiting Room pieces.
// ---------------------------------------------------------------------------

struct WaitingRoomFloorOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cosmeticMotion) private var cosmeticMotion
    @Environment(\.cosmeticHeroTime) private var heroTime

    var body: some View {
        TimelineView(.animation(minimumInterval: cosmeticMotion.frameInterval(1.0 / 15.0),
                                paused: reduceMotion || cosmeticMotion.isPaused(reduceMotion: reduceMotion))) { tl in
            Canvas { ctx, size in
                let t: Double = heroTime ?? (reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate)
                FoilArt.drawFloor(&ctx, size: size, t: t)
            }
        }
        .allowsHitTesting(false)
    }
}

struct WaitingRoomPitOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cosmeticMotion) private var cosmeticMotion
    @Environment(\.cosmeticHeroTime) private var heroTime

    var body: some View {
        TimelineView(.animation(minimumInterval: cosmeticMotion.frameInterval(1.0 / 20.0),
                                paused: reduceMotion || cosmeticMotion.isPaused(reduceMotion: reduceMotion))) { tl in
            Canvas { ctx, size in
                let t: Double = heroTime ?? (reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate)
                FoilArt.drawPit(&ctx, size: size, t: t)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Grey foil wall: an iridescent line whose colours turn slowly round the
/// wall, and a soft glint that travels along it.
struct WaitingRoomBoundaryOverlay: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cosmeticMotion) private var cosmeticMotion
    @Environment(\.cosmeticHeroTime) private var heroTime

    private func ring(_ inset: CGFloat) -> some InsettableShape {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).inset(by: inset)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: cosmeticMotion.frameInterval(1.0 / 30.0),
                                paused: reduceMotion || cosmeticMotion.isPaused(reduceMotion: reduceMotion))) { tl in
            let t: Double = heroTime ?? (reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate)
            let turn = t * 0.012
            let hues: [Color] = (0...6).map {
                FoilArt.tint(turn + Double($0) / 6.0, saturation: 0.45, brightness: 1)
            }
            let glint = (t * 0.035).truncatingRemainder(dividingBy: 1)
            ZStack {
                ring(2).stroke(Color(white: 0.62), lineWidth: 4)
                ring(2)
                    .stroke(AngularGradient(colors: hues, center: .center), lineWidth: 2.4)
                    .opacity(0.55)
                    .blendMode(.plusLighter)
                ring(0.8).stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                ring(3.4).stroke(Color.black.opacity(0.18), lineWidth: 0.8)
                ring(2)
                    .trim(from: CGFloat(glint), to: CGFloat(min(1, glint + 0.06)))
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .blur(radius: 1.5)
            }
        }
        .allowsHitTesting(false)
    }
}

#if DEBUG
/// Debug builds only (Settings > Debug > "Waiting Room art"): the four pieces
/// large, for the owner to review before they are locked.
struct WaitingRoomArtPreview: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Waiting Room — for review, not locked")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                piece("Ball (red foil)") {
                    BallSkinView(skin: .waitingRoom, diameter: 160)
                        .frame(width: 160, height: 160)
                        .frame(maxWidth: .infinity)
                }
                piece("Floor (white foil), with the ball") {
                    ZStack {
                        Floor.waitingRoom.color
                        WaitingRoomFloorOverlay()
                        BallSkinView(skin: .waitingRoom, diameter: 36).frame(width: 36, height: 36)
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                piece("Pit (black foil), on the floor") {
                    ZStack {
                        Floor.waitingRoom.color
                        WaitingRoomFloorOverlay()
                        ZStack {
                            Pit.waitingRoom.color
                            WaitingRoomPitOverlay()
                        }
                        .frame(width: 220, height: 60)
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                piece("Boundary (grey foil)") {
                    ZStack {
                        Floor.waitingRoom.color
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(Boundary.waitingRoom.color, lineWidth: 4)
                        WaitingRoomBoundaryOverlay(cornerRadius: 30)
                    }
                    .frame(height: 220)
                }
                Text("Turn on Reduce Motion to see the still version.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(Color(white: 0.08).ignoresSafeArea())
    }

    private func piece<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color(white: 0.8))
            content()
        }
    }
}
#endif
