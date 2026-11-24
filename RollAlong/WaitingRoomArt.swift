import SwiftUI

// ===========================================================================
// The Waiting Room collection's art (1.1): the Roll Along ball, floor, pit and
// boundary with a soft, flowing, color-shifting glow, like the shimmer on a
// soap bubble or the Apple Intelligence edge glow.  Colors blend into each
// other with no hard edges, no shapes and no patterns.
//
// Built from one SwiftUI MeshGradient per piece (`FoilMesh`): a 3 × 3 grid of
// colors whose inner points drift slowly, softened with blur where the piece
// is small enough for blur to be cheap.
//
// NOT YET LOCKED.  The owner reviews this art before it is added to
// tools/cosmetic-calendar/locked_pieces.json.
//
// KEEPING IT CHEAP
//   • Nine points per piece.  The GPU draws the gradient; no Swift code runs
//     per pixel, and there are no Canvas loops, particles or paths to build.
//   • Few frames: the floor, pit and wall redraw at most 15 times a second,
//     the ball 20.  The drift is slow (a point takes 20 to 40 seconds to come
//     back), so more frames would not look smoother.
//   • Blur only where it is cheap: on the ball (36 points across) and on the
//     pit rims (a few small rectangles).  The floor uses none: a mesh
//     gradient is already soft, and blurring the whole screen every frame
//     would be the most expensive thing on it.  The wall's glow uses one
//     small blur, flattened with the rest of the wall into a single layer
//     (`drawingGroup`).
//   • Nothing animates when it is not shown or should hold still: under
//     Reduce Motion, on a frozen Shop or Locker tile, or while a list
//     scrolls, the clock stops and the colors hold still.
// ===========================================================================
enum FoilArt {
    /// A color on the glow's wheel: `phase` turns of the color wheel.
    static func tint(_ phase: Double, saturation: Double, brightness: Double) -> Color {
        let h = phase - phase.rounded(.down)
        return Color(hue: h, saturation: saturation, brightness: brightness)
    }

    /// The nine points of the mesh at time `t`.  Corners stay put; the edge
    /// midpoints slide a little along their edge; the center wanders in a
    /// slow loop.  Every period is 20 to 40 seconds.
    static func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        func wave(_ period: Double, _ phase: Double, _ amount: Double) -> Float {
            Float(amount * sin(t * 2 * .pi / period + phase))
        }
        return [
            [0, 0],                          [0.5 + wave(29, 0.0, 0.14), 0],                          [1, 0],
            [0, 0.5 + wave(23, 1.1, 0.14)],  [0.5 + wave(31, 2.0, 0.18), 0.5 + wave(37, 0.4, 0.18)], [1, 0.5 + wave(27, 2.6, 0.14)],
            [0, 1],                          [0.5 + wave(33, 3.3, 0.14), 1],                          [1, 1],
        ]
    }

    /// The nine colors at time `t`: blue, violet, pink, orange and cyan, as in
    /// the Apple Intelligence glow, each turning slowly round the color wheel
    /// (a full turn takes about 80 seconds).
    static func meshColors(_ t: Double, saturation: Double, brightness: Double) -> [Color] {
        let turn = t / 80
        // Starting hues: blue, violet, pink / cyan, (center) blue, orange /
        // violet, pink, cyan.
        let hues: [Double] = [0.60, 0.76, 0.90,
                              0.50, 0.66, 0.07,
                              0.78, 0.94, 0.52]
        return hues.map { tint($0 + turn, saturation: saturation, brightness: brightness) }
    }
}

/// The glow itself: one 3 × 3 MeshGradient at time `t`.
struct FoilMesh: View {
    let t: Double
    var saturation: Double = 0.65
    var brightness: Double = 1.0

    var body: some View {
        MeshGradient(width: 3, height: 3,
                     points: FoilArt.meshPoints(t),
                     colors: FoilArt.meshColors(t, saturation: saturation, brightness: brightness),
                     smoothsColors: true)
    }
}

/// The clock every Waiting Room piece shares: paused (time 0, colors still)
/// under Reduce Motion, on a frozen tile and while a list scrolls; a frozen
/// Shop tile shows its chosen moment.
private struct FoilClock<Content: View>: View {
    let framesPerSecond: Double
    @ViewBuilder let content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cosmeticMotion) private var cosmeticMotion
    @Environment(\.cosmeticHeroTime) private var heroTime

    var body: some View {
        TimelineView(.animation(minimumInterval: cosmeticMotion.frameInterval(1.0 / framesPerSecond),
                                paused: reduceMotion || cosmeticMotion.isPaused(reduceMotion: reduceMotion))) { tl in
            content(heroTime ?? (reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate))
        }
    }
}

// ---------------------------------------------------------------------------
// Ball: the classic red with the glow flowing across it, and a bright glossy
// highlight so it still reads as a ball.  `still` is the ball renderer's own
// Reduce Motion / frozen-tile rule.
// ---------------------------------------------------------------------------
struct WaitingRoomBall: View {
    let colors: [Color]
    let still: Bool
    let paused: Bool
    let frameInterval: Double?

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            TimelineView(.animation(minimumInterval: frameInterval, paused: paused || still)) { tl in
                let t = still ? 0 : tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    // The red ball.
                    Circle().fill(RadialGradient(colors: colors,
                                                 center: UnitPoint(x: 0.32, y: 0.30),
                                                 startRadius: 0, endRadius: d * 0.62))
                    // The glow flowing over it, soft at every edge.
                    FoilMesh(t: t, saturation: 0.55)
                        .blur(radius: d * 0.06)
                        .opacity(0.55)
                        .blendMode(.screen)
                        .clipShape(Circle())
                    // Shade toward the rim, so it stays round.
                    Circle().fill(RadialGradient(
                        stops: [.init(color: .clear, location: 0.62),
                                .init(color: .black.opacity(0.38), location: 1.0)],
                        center: .center, startRadius: 0, endRadius: d * 0.5))
                    // The glossy highlight.
                    Ellipse()
                        .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: d * 0.18))
                        .frame(width: d * 0.42, height: d * 0.28)
                        .offset(x: -d * 0.16, y: -d * 0.24)
                        .blur(radius: d * 0.015)
                }
                .frame(width: d, height: d)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// ---------------------------------------------------------------------------
// Floor: the classic white with a faint, slow soap-bubble drift of color.
// Light on purpose (16 % at most), so holes and coins stay easy to see.
// ---------------------------------------------------------------------------
struct WaitingRoomFloorOverlay: View {
    var body: some View {
        FoilClock(framesPerSecond: 15) { t in
            FoilMesh(t: t, saturation: 0.35)
                .opacity(0.16)
        }
        .allowsHitTesting(false)
    }
}

// ---------------------------------------------------------------------------
// Pit: the classic black pit with a thin glowing rim that slowly shifts
// color, like the Apple Intelligence border.  Drawn over the pit's own
// rectangle.
// ---------------------------------------------------------------------------
struct WaitingRoomPitOverlay: View {
    var body: some View {
        FoilClock(framesPerSecond: 15) { t in
            ZStack {
                // The soft glow just inside the rim.
                FoilMesh(t: t, saturation: 0.75)
                    .mask(Rectangle().strokeBorder(lineWidth: 5).blur(radius: 3))
                    .opacity(0.55)
                // The thin bright rim.
                FoilMesh(t: t, saturation: 0.70)
                    .mask(Rectangle().strokeBorder(lineWidth: 1.5))
            }
        }
        .allowsHitTesting(false)
    }
}

// ---------------------------------------------------------------------------
// Boundary: the same glowing, color-shifting edge, like the Apple
// Intelligence glow around the screen: a thin bright line, and a soft glow
// falling inward from it.
// ---------------------------------------------------------------------------
struct WaitingRoomBoundaryOverlay: View {
    let cornerRadius: CGFloat

    private func ring(_ inset: CGFloat) -> some InsettableShape {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).inset(by: inset)
    }

    var body: some View {
        FoilClock(framesPerSecond: 15) { t in
            ZStack {
                FoilMesh(t: t, saturation: 0.75)
                    .mask(ring(2).stroke(lineWidth: 14).blur(radius: 8))
                    .opacity(0.60)
                FoilMesh(t: t, saturation: 0.70)
                    .mask(ring(2).stroke(lineWidth: 3))
            }
            // One flattened layer: the masks and the blur render together.
            .drawingGroup()
        }
        .allowsHitTesting(false)
    }
}

#if DEBUG
/// Debug builds only (Settings > Debug > End room > "Waiting Room art"): the
/// four pieces large, for the owner to review before they are locked.
struct WaitingRoomArtPreview: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Waiting Room — for review, not locked")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                piece("Ball") {
                    BallSkinView(skin: .waitingRoom, diameter: 160)
                        .frame(width: 160, height: 160)
                        .frame(maxWidth: .infinity)
                }
                piece("Floor, with the ball and a coin-sized dot") {
                    ZStack {
                        Floor.waitingRoom.color
                        WaitingRoomFloorOverlay()
                        HStack(spacing: 40) {
                            BallSkinView(skin: .waitingRoom, diameter: 36).frame(width: 36, height: 36)
                            Circle().fill(Color(red: 1.0, green: 0.80, blue: 0.20)).frame(width: 18, height: 18)
                        }
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                piece("Pit, on the floor") {
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
                piece("Boundary") {
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
