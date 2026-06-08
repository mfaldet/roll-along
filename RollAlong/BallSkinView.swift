import SwiftUI

// ---------------------------------------------------------------------------
// BallSkinView — shared marble renderer used by the shop, home screen,
// and in-game view.
//
// Pass `diameter` equal to the intended display size — it drives the
// radial-gradient end-radius for solid/gradient skins so the shading reads
// correctly at any size.  Callers size the view with
//     .frame(width: diameter, height: diameter)
// and apply their own .shadow(…).  Clip, overlay stroke, and animation are
// all handled internally so every surface gets identical art automatically.
//
// Rendering paths
// ───────────────
//   • Gradient skins   → Circle filled with a radial gradient.
//   • Bespoke (clipped)→ Canvas clipped to Circle + rim stroke overlay.
//   • Bespoke (free)   → Canvas only (Saturn rings / UFO saucer exceed the
//                        inscribed circle and must not be clipped).
//   • Animated         → TimelineView wraps the Canvas (Snowglobe, UFO).
// ---------------------------------------------------------------------------

struct BallSkinView: View {
    let skin: BallSkin
    /// Intended display diameter in points.  Used only for gradient-based
    /// skins' radial endRadius — Canvas skins read `size` from their
    /// context and scale automatically with the caller's frame.
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch skin {

        // ── Animated bespoke (TimelineView) ────────────────────────────
        case .snowglobe:
            snowglobeCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 0.5))

        case .ufo:
            ufoCanvas   // NOT clipped — saucer fills the square frame

        // ── Static bespoke (Canvas) ─────────────────────────────────────
        case .golfBall:
            golfBallCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 0.5))

        case .soccer:
            soccerCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.30), lineWidth: 0.5))

        case .saturn:
            saturnCanvas   // NOT clipped — rings extend beyond body

        case .aquarium:
            aquariumCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 0.5))

        case .marble:
            glassMarbleCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.22), lineWidth: 0.5))

        case .storm:
            stormCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.30), lineWidth: 0.5))

        case .candy:
            candyCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.22), lineWidth: 0.5))

        case .ghost:
            ghostCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 0.5))

        // ── New sports bespoke skins ────────────────────────────────────
        case .basketball:
            basketballCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.30), lineWidth: 0.5))

        case .eightBall:
            eightBallCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 0.5))

        case .baseball:
            baseballCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.20), lineWidth: 0.5))

        // ── Gradient-based (all remaining skins) ───────────────────────
        default:
            Circle()
                .fill(skin.gradient(endRadius: diameter * 0.70))
                .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 0.6))
        }
    }

    // =========================================================================
    // MARK: - Saturn
    // Pale-gold body with a tilted elliptical ring system.  Drawn in a Canvas
    // so the rings render in front of the lower half of the planet and behind
    // the upper half, selling the 3-D tilt.  Static.
    // =========================================================================
    private var saturnCanvas: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let bodyR  = min(w, h) * 0.34
            let ringRx = min(w, h) * 0.52
            let ringRy = ringRx * 0.34

            let ringMain  = Color(red: 0.86, green: 0.74, blue: 0.50)
            let ringInner = Color(red: 0.62, green: 0.50, blue: 0.30)

            func ringPath(scale: CGFloat) -> Path {
                let rx = ringRx * scale
                let ry = ringRy * scale
                return Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry,
                                              width: rx * 2, height: ry * 2))
            }

            // Back rings (full ellipse, dimmed)
            ctx.stroke(ringPath(scale: 1.0),
                       with: .color(ringMain.opacity(0.55)), lineWidth: bodyR * 0.30)
            ctx.stroke(ringPath(scale: 0.74),
                       with: .color(ringInner.opacity(0.50)), lineWidth: bodyR * 0.14)

            // Planet body
            let bodyRect = CGRect(x: cx - bodyR, y: cy - bodyR,
                                  width: bodyR * 2, height: bodyR * 2)
            ctx.fill(Path(ellipseIn: bodyRect),
                     with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 1.00, green: 0.96, blue: 0.80),
                            Color(red: 0.92, green: 0.80, blue: 0.52),
                            Color(red: 0.66, green: 0.50, blue: 0.26),
                            Color(red: 0.34, green: 0.24, blue: 0.10),
                        ]),
                        center: CGPoint(x: cx - bodyR * 0.3, y: cy - bodyR * 0.3),
                        startRadius: 0, endRadius: bodyR * 1.4))
            ctx.stroke(Path(ellipseIn: bodyRect),
                       with: .color(.black.opacity(0.30)), lineWidth: 0.5)

            // Front rings (lower half only — clip below equator)
            var front = ctx
            front.clip(to: Path(CGRect(x: 0, y: cy, width: w, height: h - cy)))
            front.stroke(ringPath(scale: 1.0),
                         with: .color(ringMain), lineWidth: bodyR * 0.30)
            front.stroke(ringPath(scale: 0.74),
                         with: .color(ringInner), lineWidth: bodyR * 0.14)
        }
    }

    // =========================================================================
    // MARK: - UFO
    // Metallic flying saucer with a glowing green dome and belly lights that
    // pulse in sequence (reads as rotating running lights).  Animated via
    // TimelineView; under Reduce Motion the lights hold steady.
    // =========================================================================
    private var ufoCanvas: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let w  = size.width
                let h  = size.height
                let cx = w / 2
                let cy = h / 2

                // Saucer hull
                let hullW = w * 0.96
                let hullH = h * 0.42
                let hullRect = CGRect(x: cx - hullW / 2, y: cy - hullH * 0.10,
                                      width: hullW, height: hullH)
                ctx.fill(Path(ellipseIn: hullRect),
                         with: .linearGradient(
                            Gradient(stops: [
                                .init(color: Color(red: 0.88, green: 0.92, blue: 0.96), location: 0.00),
                                .init(color: Color(red: 0.60, green: 0.66, blue: 0.74), location: 0.45),
                                .init(color: Color(red: 0.30, green: 0.36, blue: 0.44), location: 0.85),
                                .init(color: Color(red: 0.14, green: 0.18, blue: 0.24), location: 1.00),
                            ]),
                            startPoint: CGPoint(x: cx, y: hullRect.minY),
                            endPoint:   CGPoint(x: cx, y: hullRect.maxY)))
                ctx.stroke(Path(ellipseIn: hullRect),
                           with: .color(.black.opacity(0.30)), lineWidth: 0.6)

                // Glass dome
                let domeW = w * 0.50
                let domeH = h * 0.46
                let domeRect = CGRect(x: cx - domeW / 2,
                                      y: cy - hullH * 0.10 - domeH * 0.72,
                                      width: domeW, height: domeH)
                ctx.fill(Path(ellipseIn: domeRect),
                         with: .radialGradient(
                            Gradient(colors: [
                                Color(red: 0.70, green: 1.00, blue: 0.80),
                                Color(red: 0.20, green: 0.85, blue: 0.55),
                                Color(red: 0.05, green: 0.45, blue: 0.30),
                            ]),
                            center: CGPoint(x: domeRect.midX - domeW * 0.18,
                                            y: domeRect.midY - domeH * 0.18),
                            startRadius: 0, endRadius: domeW * 0.75))
                ctx.stroke(Path(ellipseIn: domeRect),
                           with: .color(.white.opacity(0.35)), lineWidth: 0.5)

                // Belly lights — pulse in sequence
                let lightCount = 5
                let lightY     = cy + hullH * 0.30
                let lightR     = max(1.2, w * 0.05)
                for i in 0..<lightCount {
                    let frac   = (Double(i) + 0.5) / Double(lightCount)
                    let lx     = hullRect.minX + hullW * 0.14 + (hullW * 0.72) * CGFloat(frac)
                    let pulse  = 0.40 + 0.60 * (0.5 + 0.5 * sin(t * 6 - Double(i) * 1.1))
                    ctx.fill(Path(ellipseIn: CGRect(x: lx - lightR, y: lightY - lightR,
                                                    width: lightR * 2, height: lightR * 2)),
                             with: .color(Color(red: 1.00, green: 0.92, blue: 0.45)
                                .opacity(pulse)))
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Golf Ball
    // White sphere with the classic dimple pattern.  Dimples are a
    // deterministic hex grid so they don't dance frame-to-frame.
    // =========================================================================
    private var golfBallCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color.white,                                 location: 0.00),
                        .init(color: Color(red: 0.94, green: 0.94, blue: 0.92),  location: 0.55),
                        .init(color: Color(red: 0.70, green: 0.70, blue: 0.66),  location: 0.95),
                        .init(color: Color(red: 0.42, green: 0.42, blue: 0.40),  location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.32, y: h * 0.32),
                    startRadius: 0, endRadius: r * 1.30))

            let dimpleR  = r * 0.075
            let spacing  = dimpleR * 2.4
            let rowCount = Int(ceil(h / spacing)) + 1
            for row in 0..<rowCount {
                let isOddRow = row % 2 == 1
                let y = CGFloat(row) * spacing + (isOddRow ? spacing / 2 : 0) - spacing / 2
                let xOffset: CGFloat = isOddRow ? spacing / 2 : 0
                let colCount = Int(ceil(w / spacing)) + 1
                for col in 0..<colCount {
                    let x  = CGFloat(col) * spacing + xOffset - spacing / 2
                    let dx = x - cx
                    let dy = y - cy
                    if sqrt(dx * dx + dy * dy) > r * 0.93 { continue }
                    ctx.fill(Path(ellipseIn: CGRect(x: x - dimpleR, y: y - dimpleR,
                                                    width: dimpleR * 2, height: dimpleR * 2)),
                             with: .color(Color.black.opacity(0.10)))
                    let rimR = dimpleR * 0.55
                    ctx.fill(Path(ellipseIn: CGRect(x: x + dimpleR * 0.15, y: y + dimpleR * 0.15,
                                                    width: rimR * 2, height: rimR * 2)),
                             with: .color(Color.white.opacity(0.55)))
                }
            }

            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.10, y: h * 0.08,
                                       width: w * 0.32, height: h * 0.26)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.50), .clear]),
                    center: CGPoint(x: w * 0.25, y: h * 0.20),
                    startRadius: 0, endRadius: r * 0.40))
        }
    }

    // =========================================================================
    // MARK: - Soccer Ball
    // Classic Telstar pattern: white sphere with a central black pentagon
    // ringed by five more.  The outer pentagons sit past the body radius
    // so the circle clip in the caller trims them, selling the wrap.
    // =========================================================================
    private var soccerCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color.white,                                 location: 0.00),
                        .init(color: Color(red: 0.95, green: 0.95, blue: 0.95),  location: 0.55),
                        .init(color: Color(red: 0.72, green: 0.72, blue: 0.72),  location: 0.95),
                        .init(color: Color(red: 0.42, green: 0.42, blue: 0.42),  location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.32, y: h * 0.32),
                    startRadius: 0, endRadius: r * 1.30))

            func pentagon(center c: CGPoint, radius pr: CGFloat, rotation rot: CGFloat) -> Path {
                var p = Path()
                for i in 0..<5 {
                    let a  = rot - .pi / 2 + CGFloat(i) * (2 * .pi / 5)
                    let pt = CGPoint(x: c.x + pr * cos(a), y: c.y + pr * sin(a))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
                return p
            }

            let black = Color(red: 0.09, green: 0.09, blue: 0.11)
            let pentR = r * 0.30
            ctx.fill(pentagon(center: CGPoint(x: cx, y: cy), radius: pentR, rotation: .pi),
                     with: .color(black))
            let ringDist = r * 0.74
            for i in 0..<5 {
                let a  = -.pi / 2 + CGFloat(i) * (2 * .pi / 5)
                let pc = CGPoint(x: cx + ringDist * cos(a), y: cy + ringDist * sin(a))
                ctx.fill(pentagon(center: pc, radius: pentR * 0.95, rotation: a + .pi / 2),
                         with: .color(black))
            }

            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.10, y: h * 0.08,
                                       width: w * 0.32, height: h * 0.26)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.45), .clear]),
                    center: CGPoint(x: w * 0.25, y: h * 0.20),
                    startRadius: 0, endRadius: r * 0.40))
        }
    }

    // =========================================================================
    // MARK: - Aquarium
    // Translucent aqua glass sphere with a cluster of static bubbles.
    // =========================================================================
    private var aquariumCanvas: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let r = min(w, h) / 2

            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.80, green: 0.98, blue: 0.98), location: 0.00),
                        .init(color: Color(red: 0.36, green: 0.84, blue: 0.92), location: 0.45),
                        .init(color: Color(red: 0.10, green: 0.55, blue: 0.72), location: 0.82),
                        .init(color: Color(red: 0.03, green: 0.26, blue: 0.40), location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.34, y: h * 0.32),
                    startRadius: 0, endRadius: r * 1.25))

            let bubbles: [(x: CGFloat, y: CGFloat, rad: CGFloat)] = [
                (0.36, 0.62, 0.15), (0.58, 0.46, 0.10),
                (0.50, 0.76, 0.07), (0.70, 0.66, 0.06), (0.30, 0.40, 0.055),
            ]
            for b in bubbles {
                let c    = CGPoint(x: w * b.x, y: h * b.y)
                let br   = r * b.rad
                let rect = CGRect(x: c.x - br, y: c.y - br, width: br * 2, height: br * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.12)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.75)),
                           lineWidth: max(1, br * 0.18))
                let hr = br * 0.30
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - br * 0.40 - hr,
                                                y: c.y - br * 0.40 - hr,
                                                width: hr * 2, height: hr * 2)),
                         with: .color(.white.opacity(0.85)))
            }

            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.12, y: h * 0.08,
                                       width: w * 0.34, height: h * 0.24)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.55), .clear]),
                    center: CGPoint(x: w * 0.26, y: h * 0.18),
                    startRadius: 0, endRadius: r * 0.42))
        }
    }

    // =========================================================================
    // MARK: - Glass Marble (Realistic Marble skin)
    // Clear glass sphere with an internal cobalt cat's-eye vane — three
    // curved blades meeting at the centre.
    // =========================================================================
    private var glassMarbleCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.97, green: 0.99, blue: 1.00), location: 0.00),
                        .init(color: Color(red: 0.86, green: 0.91, blue: 0.97), location: 0.50),
                        .init(color: Color(red: 0.62, green: 0.70, blue: 0.82), location: 0.88),
                        .init(color: Color(red: 0.30, green: 0.38, blue: 0.52), location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.34, y: h * 0.32),
                    startRadius: 0, endRadius: r * 1.25))

            func blade(angle a: CGFloat, length len: CGFloat, width wd: CGFloat) -> Path {
                var p    = Path()
                let tip  = CGPoint(x: cx + len * cos(a), y: cy + len * sin(a))
                let perp = a + .pi / 2
                let mid  = CGPoint(x: cx + len * 0.5 * cos(a), y: cy + len * 0.5 * sin(a))
                let b1   = CGPoint(x: mid.x + wd * cos(perp), y: mid.y + wd * sin(perp))
                let b2   = CGPoint(x: mid.x - wd * cos(perp), y: mid.y - wd * sin(perp))
                p.move(to: CGPoint(x: cx, y: cy))
                p.addQuadCurve(to: tip, control: b1)
                p.addQuadCurve(to: CGPoint(x: cx, y: cy), control: b2)
                p.closeSubpath()
                return p
            }

            let cobalt = Color(red: 0.12, green: 0.34, blue: 0.86)
            let azure  = Color(red: 0.45, green: 0.72, blue: 1.00)
            for i in 0..<3 {
                let a = -.pi / 2 + CGFloat(i) * (2 * .pi / 3)
                ctx.fill(blade(angle: a, length: r * 0.78, width: r * 0.26),
                         with: .color(cobalt.opacity(0.92)))
            }
            for i in 0..<3 {
                let a = -.pi / 2 + CGFloat(i) * (2 * .pi / 3)
                ctx.fill(blade(angle: a, length: r * 0.48, width: r * 0.16),
                         with: .color(azure.opacity(0.95)))
            }

            let ctrR = r * 0.10
            ctx.fill(Path(ellipseIn: CGRect(x: cx - ctrR, y: cy - ctrR,
                                            width: ctrR * 2, height: ctrR * 2)),
                     with: .color(.white.opacity(0.85)))

            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .clear, location: 0.82),
                        .init(color: Color(red: 0.10, green: 0.16, blue: 0.30).opacity(0.55),
                              location: 1.00),
                    ]),
                    center: CGPoint(x: cx, y: cy),
                    startRadius: 0, endRadius: r))

            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.14, y: h * 0.09,
                                       width: w * 0.34, height: h * 0.24)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.75), .clear]),
                    center: CGPoint(x: w * 0.27, y: h * 0.18),
                    startRadius: 0, endRadius: r * 0.40))
        }
    }

    // =========================================================================
    // MARK: - Ghost
    // Luminous pale orb with hollow eyes and a wailing mouth.
    // =========================================================================
    private var ghostCanvas: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let r = min(w, h) / 2

            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.97, green: 0.98, blue: 1.00), location: 0.00),
                        .init(color: Color(red: 0.82, green: 0.86, blue: 0.94), location: 0.55),
                        .init(color: Color(red: 0.58, green: 0.64, blue: 0.76), location: 0.85),
                        .init(color: Color(red: 0.34, green: 0.40, blue: 0.54), location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.40, y: h * 0.34),
                    startRadius: 0, endRadius: r * 1.25))

            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.18, y: h * 0.18,
                                       width: w * 0.50, height: h * 0.50)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.55), .clear]),
                    center: CGPoint(x: w * 0.42, y: h * 0.40),
                    startRadius: 0, endRadius: r * 0.70))

            let eyeColor = Color(red: 0.16, green: 0.18, blue: 0.26)
            let eyeW = w * 0.16
            let eyeH = h * 0.22
            for ex in [w * 0.36, w * 0.60] {
                ctx.fill(Path(ellipseIn: CGRect(x: ex - eyeW / 2, y: h * 0.36,
                                                width: eyeW, height: eyeH)),
                         with: .color(eyeColor))
            }

            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.50 - w * 0.10, y: h * 0.62,
                                       width: w * 0.20, height: h * 0.20)),
                with: .color(eyeColor))

            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.16, y: h * 0.08,
                                       width: w * 0.30, height: h * 0.22)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.65), .clear]),
                    center: CGPoint(x: w * 0.28, y: h * 0.16),
                    startRadius: 0, endRadius: r * 0.36))
        }
    }

    // =========================================================================
    // MARK: - Candy
    // Glossy peppermint sphere with a white pinwheel swirl.
    // =========================================================================
    private var candyCanvas: some View {
        Canvas { ctx, size in
            let w      = size.width
            let h      = size.height
            let r      = min(w, h) / 2
            let center = CGPoint(x: w / 2, y: h / 2)

            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 1.00, green: 0.62, blue: 0.66), location: 0.00),
                        .init(color: Color(red: 0.92, green: 0.20, blue: 0.28), location: 0.50),
                        .init(color: Color(red: 0.74, green: 0.08, blue: 0.18), location: 0.85),
                        .init(color: Color(red: 0.46, green: 0.03, blue: 0.10), location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.36, y: h * 0.32),
                    startRadius: 0, endRadius: r * 1.25))

            let arms      = 6
            let reach     = r * 1.05
            let twist: CGFloat   = 0.55
            let armWidth: CGFloat = (.pi * 2 / CGFloat(arms)) * 0.5
            let white     = Color(red: 0.99, green: 0.97, blue: 0.98)
            for i in 0..<arms {
                let base  = CGFloat(i) / CGFloat(arms) * .pi * 2
                let aLead = base + twist
                var arm   = Path()
                arm.move(to: center)
                arm.addQuadCurve(
                    to: CGPoint(x: center.x + cos(aLead) * reach,
                                y: center.y + sin(aLead) * reach),
                    control: CGPoint(x: center.x + cos(base + twist * 0.4) * reach * 0.55,
                                     y: center.y + sin(base + twist * 0.4) * reach * 0.55))
                arm.addArc(center: center, radius: reach,
                           startAngle: .radians(Double(aLead)),
                           endAngle:   .radians(Double(aLead + armWidth)), clockwise: false)
                arm.addQuadCurve(
                    to: center,
                    control: CGPoint(
                        x: center.x + cos(base + armWidth + twist * 0.4) * reach * 0.55,
                        y: center.y + sin(base + armWidth + twist * 0.4) * reach * 0.55))
                arm.closeSubpath()
                ctx.fill(arm, with: .color(white))
            }

            let capR = r * 0.16
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - capR, y: center.y - capR,
                                            width: capR * 2, height: capR * 2)),
                     with: .color(white))

            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.14, y: h * 0.08,
                                       width: w * 0.34, height: h * 0.26)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.55), .clear]),
                    center: CGPoint(x: w * 0.28, y: h * 0.18),
                    startRadius: 0, endRadius: r * 0.42))
        }
    }

    // =========================================================================
    // MARK: - Storm
    // Dark storm-cloud sphere with billowing puffs and a jagged lightning bolt.
    // =========================================================================
    private var stormCanvas: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let r = min(w, h) / 2

            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.66, green: 0.70, blue: 0.78), location: 0.00),
                        .init(color: Color(red: 0.36, green: 0.42, blue: 0.52), location: 0.45),
                        .init(color: Color(red: 0.16, green: 0.20, blue: 0.30), location: 0.82),
                        .init(color: Color(red: 0.05, green: 0.07, blue: 0.14), location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.32, y: h * 0.30),
                    startRadius: 0, endRadius: r * 1.30))

            let puffs: [(x: CGFloat, y: CGFloat, rad: CGFloat)] = [
                (0.34, 0.40, 0.30), (0.60, 0.34, 0.24),
                (0.50, 0.54, 0.26), (0.70, 0.52, 0.20),
            ]
            for p in puffs {
                let c  = CGPoint(x: w * p.x, y: h * p.y)
                let pr = r * p.rad
                ctx.fill(
                    Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr,
                                           width: pr * 2, height: pr * 2)),
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 0.80, green: 0.83, blue: 0.90).opacity(0.42), .clear]),
                        center: c, startRadius: 0, endRadius: pr))
            }

            var bolt = Path()
            let pts  = [
                CGPoint(x: w * 0.54, y: h * 0.18),
                CGPoint(x: w * 0.44, y: h * 0.46),
                CGPoint(x: w * 0.56, y: h * 0.48),
                CGPoint(x: w * 0.42, y: h * 0.82),
            ]
            bolt.move(to: pts[0])
            for pt in pts.dropFirst() { bolt.addLine(to: pt) }
            ctx.stroke(bolt,
                       with: .color(Color(red: 1.00, green: 0.92, blue: 0.45).opacity(0.35)),
                       style: StrokeStyle(lineWidth: r * 0.22, lineCap: .round, lineJoin: .round))
            ctx.stroke(bolt,
                       with: .color(Color(red: 1.00, green: 0.98, blue: 0.78)),
                       style: StrokeStyle(lineWidth: r * 0.08, lineCap: .round, lineJoin: .round))

            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.12, y: h * 0.08,
                                       width: w * 0.32, height: h * 0.24)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.40), .clear]),
                    center: CGPoint(x: w * 0.26, y: h * 0.18),
                    startRadius: 0, endRadius: r * 0.40))
        }
    }

    // =========================================================================
    // MARK: - Snowglobe
    // Frosted-glass sphere with ~14 white snowflakes that drift downward with
    // a gentle sine x-oscillation.  Pure Canvas + TimelineView.
    // =========================================================================
    private var snowglobeCanvas: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t  = timeline.date.timeIntervalSinceReferenceDate
                let w  = size.width
                let h  = size.height
                let cx = w / 2
                let cy = h / 2
                let r  = min(w, h) / 2

                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 0.96, green: 0.98, blue: 1.00), location: 0.00),
                            .init(color: Color(red: 0.78, green: 0.88, blue: 0.98), location: 0.55),
                            .init(color: Color(red: 0.18, green: 0.30, blue: 0.50), location: 1.00),
                        ]),
                        center: CGPoint(x: w * 0.32, y: h * 0.32),
                        startRadius: 0, endRadius: r * 1.40))

                let flakeCount = 14
                for i in 0..<flakeCount {
                    let seed    = Double(i) * 0.713 + 0.21
                    let fall    = (t * 0.22 + seed).truncatingRemainder(dividingBy: 1.0)
                    let xOsc    = sin(t * 0.65 + seed * 5.3)
                    let xN      = 0.18 + 0.64 * (0.5 + 0.5 * xOsc)
                    let yN      = 0.10 + 0.80 * fall
                    let px      = w * CGFloat(xN)
                    let py      = h * CGFloat(yN)
                    let dx      = px - cx
                    let dy      = py - cy
                    if sqrt(dx * dx + dy * dy) > r * 0.90 { continue }
                    let twinkle = 0.65 + 0.35 * sin(t * 1.4 + seed * 7)
                    let flakeR  = r * (0.045 + Double(i % 3) * 0.012)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: px - flakeR, y: py - flakeR,
                                               width: flakeR * 2, height: flakeR * 2)),
                        with: .color(Color.white.opacity(twinkle)))
                }

                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.10, y: h * 0.08,
                                           width: w * 0.34, height: h * 0.28)),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.45), .clear]),
                        center: CGPoint(x: w * 0.27, y: h * 0.22),
                        startRadius: 0, endRadius: r * 0.45))
            }
        }
    }

    // =========================================================================
    // MARK: - Basketball  (NEW)
    // Orange sphere with the classic NBA seam pattern: two vertical bow-arcs
    // (left and right of centre) and two horizontal seam curves.
    // =========================================================================
    private var basketballCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // Orange body — bright highlight → saturated orange → deep terracotta
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 1.00, green: 0.78, blue: 0.38), location: 0.00),
                        .init(color: Color(red: 0.92, green: 0.44, blue: 0.06), location: 0.50),
                        .init(color: Color(red: 0.68, green: 0.24, blue: 0.02), location: 0.85),
                        .init(color: Color(red: 0.36, green: 0.10, blue: 0.01), location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.32, y: h * 0.30),
                    startRadius: 0, endRadius: r * 1.30))

            let seam      = Color(red: 0.14, green: 0.08, blue: 0.04)
            let seamWidth = r * 0.058

            // Helper: quadratic bezier path from p0 to p1 via control c
            func qbPath(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint) -> Path {
                var path = Path()
                path.move(to: p0)
                path.addQuadCurve(to: p1, control: c)
                return path
            }

            let style = StrokeStyle(lineWidth: seamWidth, lineCap: .round)

            // Left bow-arc: top-centre → bottom-centre, bowing left
            ctx.stroke(
                qbPath(CGPoint(x: cx, y: cy - r * 0.94),
                       CGPoint(x: cx - r * 0.72, y: cy),
                       CGPoint(x: cx, y: cy + r * 0.94)),
                with: .color(seam), style: style)

            // Right bow-arc: mirrors left, bowing right
            ctx.stroke(
                qbPath(CGPoint(x: cx, y: cy - r * 0.94),
                       CGPoint(x: cx + r * 0.72, y: cy),
                       CGPoint(x: cx, y: cy + r * 0.94)),
                with: .color(seam), style: style)

            // Upper horizontal seam: left edge → right edge, curving upward
            ctx.stroke(
                qbPath(CGPoint(x: cx - r * 0.94, y: cy - r * 0.12),
                       CGPoint(x: cx,             y: cy - r * 0.52),
                       CGPoint(x: cx + r * 0.94, y: cy - r * 0.12)),
                with: .color(seam), style: style)

            // Lower horizontal seam: mirrors upper, curving downward
            ctx.stroke(
                qbPath(CGPoint(x: cx - r * 0.94, y: cy + r * 0.12),
                       CGPoint(x: cx,             y: cy + r * 0.52),
                       CGPoint(x: cx + r * 0.94, y: cy + r * 0.12)),
                with: .color(seam), style: style)

            // Top gloss crescent
            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.12, y: h * 0.08,
                                       width: w * 0.30, height: h * 0.22)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.42), .clear]),
                    center: CGPoint(x: w * 0.24, y: h * 0.17),
                    startRadius: 0, endRadius: r * 0.36))
        }
    }

    // =========================================================================
    // MARK: - 8-Ball  (NEW)
    // Near-black sphere with a white circle containing a bold "8".  The
    // classic billiards marker that's also iconically marble-like.
    // =========================================================================
    private var eightBallCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // Near-black body — subtle highlight so it reads as a sphere
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.28, green: 0.28, blue: 0.32), location: 0.00),
                        .init(color: Color(red: 0.10, green: 0.10, blue: 0.12), location: 0.40),
                        .init(color: Color(red: 0.04, green: 0.04, blue: 0.06), location: 0.82),
                        .init(color: Color.black,                                location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.32, y: h * 0.30),
                    startRadius: 0, endRadius: r * 1.30))

            // White circle badge
            let circleR = r * 0.44
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - circleR, y: cy - circleR,
                                       width: circleR * 2, height: circleR * 2)),
                with: .color(.white))

            // "8" numeral — resolved and drawn at centre
            let fontSize   = circleR * 1.15
            let resolvedText = ctx.resolve(
                Text("8")
                    .font(.system(size: fontSize, weight: .black, design: .default))
                    .foregroundColor(.black))
            ctx.draw(resolvedText, at: CGPoint(x: cx, y: cy), anchor: .center)

            // Subtle gloss crescent — dimmed so it reads on the dark body
            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.14, y: h * 0.08,
                                       width: w * 0.30, height: h * 0.22)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.38), .clear]),
                    center: CGPoint(x: w * 0.26, y: h * 0.17),
                    startRadius: 0, endRadius: r * 0.36))
        }
    }

    // =========================================================================
    // MARK: - Baseball  (NEW)
    // Off-white leather sphere with two red C-shaped seam curves, each
    // stitched with small perpendicular dashes for the thread effect.
    // =========================================================================
    private var baseballCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // Leather body
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color.white,                                 location: 0.00),
                        .init(color: Color(red: 0.96, green: 0.94, blue: 0.90),  location: 0.55),
                        .init(color: Color(red: 0.80, green: 0.76, blue: 0.70),  location: 0.90),
                        .init(color: Color(red: 0.56, green: 0.50, blue: 0.44),  location: 1.00),
                    ]),
                    center: CGPoint(x: w * 0.32, y: h * 0.30),
                    startRadius: 0, endRadius: r * 1.30))

            let stitchRed  = Color(red: 0.72, green: 0.12, blue: 0.12)
            let seamW      = r * 0.055
            let stitchW    = r * 0.040
            let tickLen    = r * 0.10
            let stitchN    = 11   // tick marks per seam curve

            // Helper: generate tick-mark paths perpendicular to a quad bezier
            func tickPaths(from p0: CGPoint, ctrl: CGPoint, to p1: CGPoint) -> [Path] {
                var ticks = [Path]()
                for i in 0..<stitchN {
                    let t  = CGFloat(i + 1) / CGFloat(stitchN + 1)
                    let mt = 1 - t
                    // Point on bezier
                    let px = mt * mt * p0.x + 2 * mt * t * ctrl.x + t * t * p1.x
                    let py = mt * mt * p0.y + 2 * mt * t * ctrl.y + t * t * p1.y
                    // Tangent (derivative)
                    let dx = 2 * (mt * (ctrl.x - p0.x) + t * (p1.x - ctrl.x))
                    let dy = 2 * (mt * (ctrl.y - p0.y) + t * (p1.y - ctrl.y))
                    let dLen = sqrt(dx * dx + dy * dy)
                    guard dLen > 0 else { continue }
                    // Perpendicular normal
                    let nx = -dy / dLen
                    let ny =  dx / dLen
                    var tick = Path()
                    tick.move(to:    CGPoint(x: px - nx * tickLen, y: py - ny * tickLen))
                    tick.addLine(to: CGPoint(x: px + nx * tickLen, y: py + ny * tickLen))
                    ticks.append(tick)
                }
                return ticks
            }

            // Left seam: C-curve on the right side of centre, opening leftward
            let lp0   = CGPoint(x: cx + r * 0.20, y: cy - r * 0.78)
            let lCtrl = CGPoint(x: cx - r * 0.58, y: cy)
            let lp1   = CGPoint(x: cx + r * 0.20, y: cy + r * 0.78)
            var leftSeam = Path()
            leftSeam.move(to: lp0)
            leftSeam.addQuadCurve(to: lp1, control: lCtrl)
            ctx.stroke(leftSeam, with: .color(stitchRed),
                       style: StrokeStyle(lineWidth: seamW, lineCap: .round))
            for tick in tickPaths(from: lp0, ctrl: lCtrl, to: lp1) {
                ctx.stroke(tick, with: .color(stitchRed),
                           style: StrokeStyle(lineWidth: stitchW, lineCap: .round))
            }

            // Right seam: mirrors left, opening rightward
            let rp0   = CGPoint(x: cx - r * 0.20, y: cy - r * 0.78)
            let rCtrl = CGPoint(x: cx + r * 0.58, y: cy)
            let rp1   = CGPoint(x: cx - r * 0.20, y: cy + r * 0.78)
            var rightSeam = Path()
            rightSeam.move(to: rp0)
            rightSeam.addQuadCurve(to: rp1, control: rCtrl)
            ctx.stroke(rightSeam, with: .color(stitchRed),
                       style: StrokeStyle(lineWidth: seamW, lineCap: .round))
            for tick in tickPaths(from: rp0, ctrl: rCtrl, to: rp1) {
                ctx.stroke(tick, with: .color(stitchRed),
                           style: StrokeStyle(lineWidth: stitchW, lineCap: .round))
            }

            // Gloss crescent
            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.10, y: h * 0.08,
                                       width: w * 0.30, height: h * 0.22)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.50), .clear]),
                    center: CGPoint(x: w * 0.22, y: h * 0.16),
                    startRadius: 0, endRadius: r * 0.36))
        }
    }
}
