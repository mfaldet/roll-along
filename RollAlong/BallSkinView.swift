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

        case .pluto:
            plutoCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.28), lineWidth: 0.5))

        // ── Planets — textured spheres, not flat gradients ───────────────
        case .earth:
            planet(Self.earthPalette, mottle: true).clipShape(Circle()).overlay(planetRim)
        case .mars:
            planet(Self.marsPalette, mottle: true, poles: true).clipShape(Circle()).overlay(planetRim)
        case .mercury:
            planet(Self.mercuryPalette, mottle: true).clipShape(Circle()).overlay(planetRim)
        case .jupiter:
            planet(Self.jupiterPalette, bands: true,
                   spot: Color(red: 0.82, green: 0.30, blue: 0.16)).clipShape(Circle()).overlay(planetRim)
        case .neptune:
            planet(Self.neptunePalette, bands: true,
                   spot: Color(red: 0.05, green: 0.10, blue: 0.40)).clipShape(Circle()).overlay(planetRim)
        case .venus:
            planet(Self.venusPalette, bands: true).clipShape(Circle()).overlay(planetRim)
        case .uranus:
            planet(Self.uranusPalette, bands: true).clipShape(Circle()).overlay(planetRim)

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

        // ── Round-6 bundle completion bespoke skins ─────────────────────
        case .disco:
            discoCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.30), lineWidth: 0.5))

        case .paper:
            paperCanvas
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

        case .lava:
            lavaCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.55, green: 0.08, blue: 0.00).opacity(0.55), lineWidth: 0.5))

        case .trench:
            trenchCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.04, green: 0.18, blue: 0.40).opacity(0.70), lineWidth: 0.5))

        case .trophy:
            trophyCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.82, green: 0.60, blue: 0.08).opacity(0.60), lineWidth: 0.5))

        // ── Aurora (Legendary; anchors the Aurora bundle) ───────────────
        case .aurora:
            auroraCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 0.5))

        // ── Summer 2026 seasonal exclusive ──────────────────────────────
        case .beachBall:
            beachBallCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.22), lineWidth: 0.5))

        // ── Halloween 2026 seasonal exclusive ────────────────────────────
        case .pumpkin:
            pumpkinCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.28), lineWidth: 0.5))

        // ── Winter 2026 seasonal exclusive ───────────────────────────────
        case .ornament:
            ornamentCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 0.5))

        // ── Valentine's Day 2027 seasonal exclusive ──────────────────────
        case .heartstone:
            heartstoneCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.22), lineWidth: 0.5))

        // ── St. Patrick's Day 2027 seasonal exclusive ─────────────────────
        case .shamrock:
            shamrockCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.28), lineWidth: 0.5))

        // ── New Year's 2027 seasonal exclusive ───────────────────────────
        case .confetti:
            confettiCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.22), lineWidth: 0.5))

        // ── Spring 2027 seasonal exclusive ───────────────────────────────
        case .speckledEgg:
            speckledEggCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.20), lineWidth: 0.5))

        // ── Cosmic / electric — bespoke animated ───────────────────────
        case .galaxy:  galaxyCanvas.clipShape(Circle()).overlay(planetRim)
        case .nebula:  nebulaCanvas.clipShape(Circle()).overlay(planetRim)
        case .opal:    opalCanvas.clipShape(Circle()).overlay(planetRim)
        case .neon:    neonCanvas.clipShape(Circle()).overlay(planetRim)

        // ── Polished marbles / metals / gems — richer than a flat gradient ─
        // The basic solid colours get an understated plain marble — no rim
        // highlight, just gentle shading (per Mac).  Metals keep their sheen.
        case .pastel, .dune:
            glossMarble(skin.colors).clipShape(Circle()).overlay(planetRim)
        case .red, .blue, .green, .purple, .rose, .coral, .mint, .slate, .lemon:
            plainMarble(skin.colors).clipShape(Circle()).overlay(planetRim)
        case .gold, .silver, .copper:
            metalMarble(skin.colors).clipShape(Circle()).overlay(planetRim)
        case .jade, .ruby:
            gemMarble(skin.colors).clipShape(Circle()).overlay(planetRim)
        case .diamond:
            diamondCanvas.clipShape(Circle()).overlay(planetRim)

        case .moneyBall:
            moneyBallCanvas.clipShape(Circle()).overlay(planetRim)

        // ── Premium bundle skins ────────────────────────────────────────
        case .highRoller:
            highRollerCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.78, green: 0.58, blue: 0.18).opacity(0.65), lineWidth: 0.5))

        case .quicksilver:
            quicksilverCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 0.5))

        case .oracle:
            oracleCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.45, green: 0.18, blue: 0.66).opacity(0.55), lineWidth: 0.5))

        case .geode:
            geodeCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.36, green: 0.18, blue: 0.50).opacity(0.55), lineWidth: 0.5))

        case .lavaLamp:
            lavaLampCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.40, green: 0.10, blue: 0.42).opacity(0.55), lineWidth: 0.5))

        case .plasmaGlobe:
            plasmaGlobeCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.60, green: 0.30, blue: 0.90).opacity(0.50), lineWidth: 0.5))

        case .cathedral:
            cathedralCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 0.8))

        case .magmaCore:
            magmaCoreCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.55, green: 0.20, blue: 0.04).opacity(0.55), lineWidth: 0.5))

        case .hologram:
            hologramCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.40, green: 0.92, blue: 1.0).opacity(0.45), lineWidth: 0.5))

        case .clockwork:
            clockworkCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.42, green: 0.28, blue: 0.10).opacity(0.60), lineWidth: 0.6))

        // ── Seasonal bundle skins ───────────────────────────────────────
        case .fireworks:
            fireworksCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 0.5))

        case .sugarSkull:
            sugarSkullCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.22), lineWidth: 0.5))

        case .harvest:
            harvestCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.50, green: 0.26, blue: 0.08).opacity(0.55), lineWidth: 0.5))

        case .lunarDragon:
            lunarDragonCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.86, green: 0.66, blue: 0.26).opacity(0.55), lineWidth: 0.6))

        case .mardiGras:
            mardiGrasCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.86, green: 0.70, blue: 0.22).opacity(0.50), lineWidth: 0.5))

        case .spectrum:
            spectrumCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 0.5))

        case .oktoberfest:
            oktoberfestCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.74, green: 0.52, blue: 0.16).opacity(0.55), lineWidth: 0.6))

        case .apple:
            appleCanvas
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.40, green: 0.04, blue: 0.06).opacity(0.45), lineWidth: 0.5))

        // No `default`: every BallSkin has an explicit renderer above, so the
        // switch is exhaustive.  Adding a new skin will (intentionally) fail to
        // compile here until it's given a case — same as the colors/tier switches.
        }
    }

    // =========================================================================
    // MARK: - Disco Ball (Nightclub bundle)
    // Mirror-ball sphere: a foreshortened grid of small reflective facets that
    // brighten toward the light and twinkle on their own clocks, with a crisp
    // specular.  Animated; Reduce Motion freezes the twinkle.  Clipped to a
    // circle by the body switch caller.
    // =========================================================================
    private var discoCanvas: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let w  = size.width, h = size.height
                let cx = w / 2, cy = h / 2
                let r  = min(w, h) / 2

                // Base sphere — dark silvery violet.
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(Gradient(colors: [
                        Color(red: 0.55, green: 0.57, blue: 0.72),
                        Color(red: 0.30, green: 0.32, blue: 0.46),
                        Color(red: 0.12, green: 0.12, blue: 0.20),
                    ]),
                    center: CGPoint(x: cx - r * 0.3, y: cy - r * 0.3), startRadius: 0, endRadius: r * 1.1))

                // Mirror facets — a grid of small tiles, foreshortened toward
                // the rim, brighter near the centre, each twinkling.
                let cols = 9, rows = 7
                for iy in 0..<rows {
                    for ix in 0..<cols {
                        let u  = (CGFloat(ix) + 0.5) / CGFloat(cols)
                        let v  = (CGFloat(iy) + 0.5) / CGFloat(rows)
                        let px = cx - r + u * r * 2
                        let py = cy - r + v * r * 2
                        let dx = px - cx, dy = py - cy
                        let dist = (dx * dx + dy * dy).squareRoot()
                        if dist > r * 0.95 { continue }
                        let fore  = 1 - (dist / r) * 0.55
                        let tileW = (r * 2 / CGFloat(cols)) * 0.82 * fore
                        let tileH = (r * 2 / CGFloat(rows)) * 0.82 * fore
                        let seed  = Double(ix) * 1.7 + Double(iy) * 2.3
                        let tw    = 0.5 + 0.5 * sin(t * 3 + seed)
                        let lightFace = max(0, 1 - dist / r)
                        let bright = 0.32 + 0.46 * lightFace + 0.20 * tw
                        let col = Color(red: 0.85 * bright + 0.10,
                                        green: 0.85 * bright + 0.10,
                                        blue: 0.95 * bright + 0.12)
                        ctx.fill(
                            Path(roundedRect: CGRect(x: px - tileW / 2, y: py - tileH / 2,
                                                     width: tileW, height: tileH),
                                 cornerRadius: tileW * 0.18),
                            with: .color(col.opacity(0.92)))
                    }
                }

                // Specular highlight.
                let hl = r * 0.5
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.55, y: cy - r * 0.62, width: hl, height: hl)),
                    with: .radialGradient(Gradient(colors: [Color.white.opacity(0.55), .clear]),
                        center: CGPoint(x: cx - r * 0.40, y: cy - r * 0.46), startRadius: 0, endRadius: hl))
            }
        }
    }

    // =========================================================================
    // MARK: - Paper Ball (Paper World bundle)
    // Crumpled cream-paper sphere — a soft paper gradient with a few angular
    // fold creases (shaded line + adjacent highlight) and faint folded facets.
    // Static.  Clipped to a circle by the body switch caller.
    // =========================================================================
    private var paperCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width, h = size.height
            let cx = w / 2, cy = h / 2
            let r  = min(w, h) / 2

            // Base cream paper sphere.
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                with: .radialGradient(Gradient(colors: [
                    Color(red: 1.00, green: 0.99, blue: 0.95),
                    Color(red: 0.92, green: 0.90, blue: 0.83),
                    Color(red: 0.74, green: 0.72, blue: 0.65),
                ]),
                center: CGPoint(x: cx - r * 0.3, y: cy - r * 0.3), startRadius: 0, endRadius: r * 1.1))

            let creaseShade = Color(red: 0.55, green: 0.53, blue: 0.47)
            // Fold creases — shaded polylines with a highlight offset alongside.
            let creases: [[CGPoint]] = [
                [CGPoint(x: cx - r * 0.55, y: cy - r * 0.7), CGPoint(x: cx - r * 0.1, y: cy - r * 0.1), CGPoint(x: cx + r * 0.45, y: cy - r * 0.4)],
                [CGPoint(x: cx - r * 0.7,  y: cy + r * 0.1), CGPoint(x: cx - r * 0.05, y: cy + r * 0.05), CGPoint(x: cx + r * 0.3, y: cy + r * 0.6)],
                [CGPoint(x: cx + r * 0.1,  y: cy - r * 0.55), CGPoint(x: cx + r * 0.18, y: cy + r * 0.0), CGPoint(x: cx + r * 0.6, y: cy + r * 0.25)],
            ]
            for line in creases {
                var p = Path()
                p.move(to: line[0]); for pt in line.dropFirst() { p.addLine(to: pt) }
                ctx.stroke(p, with: .color(creaseShade.opacity(0.5)),
                           style: StrokeStyle(lineWidth: max(1, r * 0.03), lineCap: .round, lineJoin: .round))
                var hi = Path()
                hi.move(to: CGPoint(x: line[0].x + 1.5, y: line[0].y + 1.5))
                for pt in line.dropFirst() { hi.addLine(to: CGPoint(x: pt.x + 1.5, y: pt.y + 1.5)) }
                ctx.stroke(hi, with: .color(Color.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: max(0.8, r * 0.02), lineCap: .round, lineJoin: .round))
            }
            // Faint folded facets (subtle shaded patches).
            let facets: [[CGPoint]] = [
                [CGPoint(x: cx - r * 0.1, y: cy - r * 0.1), CGPoint(x: cx + r * 0.45, y: cy - r * 0.4), CGPoint(x: cx + r * 0.5, y: cy + r * 0.05), CGPoint(x: cx + r * 0.1, y: cy + r * 0.0)],
                [CGPoint(x: cx - r * 0.7, y: cy + r * 0.1), CGPoint(x: cx - r * 0.05, y: cy + r * 0.05), CGPoint(x: cx - r * 0.2, y: cy + r * 0.55)],
            ]
            for f in facets {
                var p = Path()
                p.move(to: f[0]); for pt in f.dropFirst() { p.addLine(to: pt) }; p.closeSubpath()
                ctx.fill(p, with: .color(creaseShade.opacity(0.12)))
            }
            // Specular highlight.
            let hl = r * 0.5
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r * 0.55, y: cy - r * 0.62, width: hl, height: hl)),
                with: .radialGradient(Gradient(colors: [Color.white.opacity(0.40), .clear]),
                    center: CGPoint(x: cx - r * 0.40, y: cy - r * 0.46), startRadius: 0, endRadius: hl))
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

            // Dimples on a hex grid, FORESHORTENED toward the rim (smaller as
            // they wrap away from the viewer) so they read as a sphere, not a
            // flat polka-dot disc.  Each is a concave well: a recessed shadow
            // with the catch-light on the far (bottom-right) interior wall —
            // the inverse of a raised bump, which is what sells "dimple".
            let baseR    = r * 0.072
            let spacing  = baseR * 2.1
            let rowCount = Int(ceil(h / spacing)) + 2
            let colCount = Int(ceil(w / spacing)) + 2
            for row in 0..<rowCount {
                let isOdd = row % 2 == 1
                let y = CGFloat(row) * spacing - spacing + (isOdd ? spacing / 2 : 0)
                for col in 0..<colCount {
                    let x  = CGFloat(col) * spacing - spacing + (isOdd ? spacing / 2 : 0)
                    let dx = x - cx, dy = y - cy
                    let d  = sqrt(dx * dx + dy * dy)
                    guard d < r * 0.95 else { continue }
                    // 1 at centre → 0 at the rim: shrink + dim dimples as they curve away.
                    let f  = sqrt(max(0, 1 - (d / r) * (d / r)))
                    let dr = baseR * (0.35 + 0.65 * f)
                    guard dr > 0.5 else { continue }
                    // Recessed well — darker in the middle.
                    ctx.fill(Path(ellipseIn: CGRect(x: x - dr, y: y - dr, width: dr * 2, height: dr * 2)),
                        with: .radialGradient(Gradient(colors: [Color.black.opacity(0.22), .clear]),
                            center: CGPoint(x: x, y: y), startRadius: 0, endRadius: dr))
                    // Catch-light on the lit far wall (bottom-right) → concave read.
                    let hlr = dr * 0.30
                    ctx.fill(Path(ellipseIn: CGRect(x: x + dr * 0.30 - hlr, y: y + dr * 0.30 - hlr,
                                                    width: hlr * 2, height: hlr * 2)),
                             with: .color(Color.white.opacity(0.5 * f)))
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
    // curved blades meeting at the centre.  Animated: the vane rotates slowly
    // inside the glass while a refracted caustic orbits behind it, giving the
    // sphere real internal depth.  Under Reduce Motion the vane rests in its
    // original pose — exactly the original static marble.
    // =========================================================================
    private var glassMarbleCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                // Cat's-eye rotation — zero under Reduce Motion → original pose.
                let spin: CGFloat = reduceMotion ? 0.0 : CGFloat(t.truncatingRemainder(dividingBy: 2.0 * .pi / 0.26) * 0.26)

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

                // Inner glass depth — a refracted cobalt caustic that orbits
                // slowly BEHIND the vane, so the sphere reads as solid glass.
                //     (skipped entirely under Reduce Motion → static fallback)
                if !reduceMotion {
                    let orbA: CGFloat = -spin * 0.6 + 2.4
                    let orbC = CGPoint(x: cx + cos(orbA) * r * 0.34,
                                       y: cy + sin(orbA) * r * 0.34)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: orbC.x - r * 0.40, y: orbC.y - r * 0.40,
                                               width: r * 0.80, height: r * 0.80)),
                        with: .radialGradient(
                            Gradient(colors: [Color(red: 0.30, green: 0.55, blue: 0.95).opacity(0.16), .clear]),
                            center: orbC, startRadius: 0, endRadius: r * 0.40))
                }

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
                    let a: CGFloat = -.pi / 2 + spin + CGFloat(i) * (2 * .pi / 3)
                    ctx.fill(blade(angle: a, length: r * 0.78, width: r * 0.26),
                             with: .color(cobalt.opacity(0.92)))
                }
                for i in 0..<3 {
                    let a: CGFloat = -.pi / 2 + spin + CGFloat(i) * (2 * .pi / 3)
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

                // Glassy micro-glint — a second, small refraction highlight
                // that circles the lower hemisphere (additive; absent under
                // Reduce Motion).
                if !reduceMotion {
                    let glA: CGFloat = spin * 0.6 + 0.8
                    let glC = CGPoint(x: cx + cos(glA) * r * 0.58,
                                      y: cy + abs(sin(glA)) * r * 0.52)
                    let glO: Double = 0.20 + 0.10 * sin(t * 1.7)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: glC.x - r * 0.10, y: glC.y - r * 0.07,
                                               width: r * 0.20, height: r * 0.14)),
                        with: .radialGradient(
                            Gradient(colors: [Color.white.opacity(glO), .clear]),
                            center: glC, startRadius: 0, endRadius: r * 0.12))
                }

                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.14, y: h * 0.09,
                                           width: w * 0.34, height: h * 0.24)),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.75), .clear]),
                        center: CGPoint(x: w * 0.27, y: h * 0.18),
                        startRadius: 0, endRadius: r * 0.40))
            }
        }
    }

    // =========================================================================
    // MARK: - Ghost
    // Luminous pale orb with hollow eyes and a wailing mouth.  Animated: the
    // spirit hovers with a slow bob, pale wisps curl up around it, and the
    // hollow eyes blink shut on a lazy clock.  Under Reduce Motion the haunt
    // holds perfectly still — exactly the original static ghost.
    // =========================================================================
    private var ghostCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate

                let w = size.width
                let h = size.height
                let r = min(w, h) / 2

                // Hover bob — zero under Reduce Motion → original face position.
                let bobPhase: Double = reduceMotion ? 0.0 : sin(t * 1.1)
                let bob: CGFloat = CGFloat(bobPhase) * r * 0.05

                // Blink — the eyes squash shut for a beat every ~3.8 s.
                // 1.0 (fully open) reproduces the original static eyes.
                let blinkCycle: Double = (t * 0.26).truncatingRemainder(dividingBy: 1.0)
                let blinkP: Double = blinkCycle / 0.08
                let blinkRaw: Double = blinkCycle < 0.08 ? abs(blinkP * 2.0 - 1.0) : 1.0
                let eyeOpen: Double = reduceMotion ? 1.0 : max(0.12, blinkRaw)

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

                // Inner luminous glow — rides the hover bob with the face.
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.18, y: h * 0.18 + bob,
                                           width: w * 0.50, height: h * 0.50)),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.55), .clear]),
                        center: CGPoint(x: w * 0.42, y: h * 0.40 + bob),
                        startRadius: 0, endRadius: r * 0.70))

                // Rising wisps — pale curls drifting up the flanks.
                //     (skipped entirely under Reduce Motion → static fallback)
                if !reduceMotion {
                    for i in 0..<4 {
                        let seed: Double  = Double(i) * 0.73 + 0.21
                        let speed: Double = 0.10 + 0.04 * Double(i % 2)
                        let cycle: Double = (t * speed + seed).truncatingRemainder(dividingBy: 1.0)
                        let sway: Double  = sin(t * 0.9 + seed * 7.0)
                        let sideSign: CGFloat = i % 2 == 0 ? -1.0 : 1.0
                        let px: CGFloat = w / 2 + sideSign * r * 0.62 + CGFloat(sway) * r * 0.10
                        let py: CGFloat = h * 0.92 - CGFloat(cycle) * h * 0.80
                        let fade: Double = 0.30 * (1.0 - cycle) * min(1.0, cycle * 5.0)
                        let ws: CGFloat = r * (0.10 + 0.05 * CGFloat(i % 2))
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: px - ws, y: py - ws * 0.7,
                                                   width: ws * 2, height: ws * 1.4)),
                            with: .radialGradient(
                                Gradient(colors: [Color.white.opacity(fade), .clear]),
                                center: CGPoint(x: px, y: py),
                                startRadius: 0, endRadius: ws))
                    }
                }

                let eyeColor = Color(red: 0.16, green: 0.18, blue: 0.26)
                let eyeW = w * 0.16
                let eyeH = h * 0.22
                // Blink squashes the eye about its centre; at eyeOpen == 1.0
                // and bob == 0 the rect is exactly the original.
                let eyeDrawH: CGFloat = eyeH * CGFloat(eyeOpen)
                let eyeMidY: CGFloat = h * 0.36 + eyeH / 2 + bob
                for ex in [w * 0.36, w * 0.60] {
                    ctx.fill(Path(ellipseIn: CGRect(x: ex - eyeW / 2, y: eyeMidY - eyeDrawH / 2,
                                                    width: eyeW, height: eyeDrawH)),
                             with: .color(eyeColor))
                    // Faint spirit-shimmer inside each open eye (additive;
                    // invisible under Reduce Motion).
                    if !reduceMotion && eyeOpen > 0.5 {
                        let glint: Double = 0.22 + 0.16 * sin(t * 2.3 + Double(ex))
                        ctx.fill(Path(ellipseIn: CGRect(x: ex - eyeW * 0.18, y: eyeMidY - eyeDrawH * 0.22,
                                                        width: eyeW * 0.36, height: eyeDrawH * 0.36)),
                                 with: .radialGradient(
                                     Gradient(colors: [Color(red: 0.70, green: 0.85, blue: 1.00).opacity(glint), .clear]),
                                     center: CGPoint(x: ex, y: eyeMidY),
                                     startRadius: 0, endRadius: eyeW * 0.40))
                    }
                }

                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.50 - w * 0.10, y: h * 0.62 + bob,
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
    }

    // =========================================================================
    // MARK: - Candy
    // Glossy peppermint sphere with a white pinwheel swirl.  Animated: the
    // pinwheel turns like a slowly licked lollipop and tiny sugar-crystal
    // glints twinkle on the red lacquer.  Under Reduce Motion the swirl rests
    // in its original pose — exactly the original static candy.
    // =========================================================================
    private var candyCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                // Pinwheel spin — zero under Reduce Motion → original swirl pose.
                let spin: CGFloat = reduceMotion ? 0.0 : CGFloat(t.truncatingRemainder(dividingBy: 2.0 * .pi / 0.30) * 0.30)

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
                    let base: CGFloat = spin + CGFloat(i) / CGFloat(arms) * .pi * 2
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

                // Sugar-crystal glints — tiny sparkles riding the lacquer,
                // each twinkling on its own clock.
                //     (skipped entirely under Reduce Motion → static fallback)
                if !reduceMotion {
                    for i in 0..<8 {
                        let seed: Double = Double(i) * 0.79 + 0.13
                        let ang: CGFloat = spin + CGFloat(seed) * .pi * 2
                        let rad: CGFloat = r * (0.42 + 0.38 * CGFloat(seed.truncatingRemainder(dividingBy: 0.5)))
                        let px: CGFloat = center.x + cos(ang) * rad
                        let py: CGFloat = center.y + sin(ang) * rad
                        let tw: Double = max(0.0, sin(t * 2.6 + seed * 9.0))
                        let glint: Double = 0.65 * tw * tw
                        let gs: CGFloat = r * (0.028 + 0.012 * CGFloat(i % 2))
                        ctx.fill(Path(ellipseIn: CGRect(x: px - gs, y: py - gs,
                                                        width: gs * 2, height: gs * 2)),
                                 with: .color(.white.opacity(glint)))
                    }
                }

                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.14, y: h * 0.08,
                                           width: w * 0.34, height: h * 0.26)),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.55), .clear]),
                        center: CGPoint(x: w * 0.28, y: h * 0.18),
                        startRadius: 0, endRadius: r * 0.42))
            }
        }
    }

    // =========================================================================
    // MARK: - Storm
    // Dark storm-cloud sphere with billowing puffs and a jagged lightning
    // bolt.  Animated: the cloud puffs drift and churn slowly while the bolt
    // strikes in irregular flashes that light the whole cell.  Under Reduce
    // Motion the storm freezes mid-strike — exactly the original static art.
    // =========================================================================
    private var stormCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate

                // Lightning strike — two offset strike clocks so the rhythm
                // reads irregular.  1.0 under Reduce Motion → the original
                // fully-lit bolt.
                let cyc1: Double = (t * 0.31).truncatingRemainder(dividingBy: 1.0)
                let cyc2: Double = (t * 0.13 + 0.47).truncatingRemainder(dividingBy: 1.0)
                let spike1: Double = cyc1 < 0.10 ? 1.0 - cyc1 / 0.10 : 0.0
                let spike2: Double = cyc2 < 0.07 ? 1.0 - cyc2 / 0.07 : 0.0
                let spike: Double = max(spike1, spike2 * 0.8)
                let flash: Double = reduceMotion ? 1.0 : 0.55 + 0.45 * spike

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

                // Cloud puffs — each drifts on its own slow clock; the strike
                // brightens them from within.  Drift is zero under Reduce
                // Motion → original positions, original 0.42 opacity.
                let puffGlow: Double = reduceMotion ? 0.42 : 0.42 + 0.20 * spike
                let puffs: [(x: CGFloat, y: CGFloat, rad: CGFloat)] = [
                    (0.34, 0.40, 0.30), (0.60, 0.34, 0.24),
                    (0.50, 0.54, 0.26), (0.70, 0.52, 0.20),
                ]
                for (i, p) in puffs.enumerated() {
                    let seed: Double = Double(i) * 1.7 + 0.4
                    let driftX: CGFloat = reduceMotion ? 0.0 : CGFloat(sin(t * 0.34 + seed)) * r * 0.055
                    let driftY: CGFloat = reduceMotion ? 0.0 : CGFloat(sin(t * 0.22 + seed * 2.1)) * r * 0.030
                    let c  = CGPoint(x: w * p.x + driftX, y: h * p.y + driftY)
                    let pr = r * p.rad
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr,
                                               width: pr * 2, height: pr * 2)),
                        with: .radialGradient(
                            Gradient(colors: [Color(red: 0.80, green: 0.83, blue: 0.90).opacity(puffGlow), .clear]),
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
                           with: .color(Color(red: 1.00, green: 0.92, blue: 0.45).opacity(0.35 * flash)),
                           style: StrokeStyle(lineWidth: r * 0.22, lineCap: .round, lineJoin: .round))
                ctx.stroke(bolt,
                           with: .color(Color(red: 1.00, green: 0.98, blue: 0.78).opacity(flash)),
                           style: StrokeStyle(lineWidth: r * 0.08, lineCap: .round, lineJoin: .round))

                // Sheet-lightning wash — the whole cell lights up at the
                // instant of a strike (additive; absent under Reduce Motion).
                if !reduceMotion && spike > 0.01 {
                    let washO: Double = 0.20 * spike
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                        with: .radialGradient(
                            Gradient(colors: [Color(red: 0.95, green: 0.95, blue: 1.00).opacity(washO), .clear]),
                            center: CGPoint(x: w * 0.50, y: h * 0.42),
                            startRadius: 0, endRadius: r * 1.15))
                }

                ctx.fill(
                    Path(ellipseIn: CGRect(x: w * 0.12, y: h * 0.08,
                                           width: w * 0.32, height: h * 0.24)),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.40), .clear]),
                        center: CGPoint(x: w * 0.26, y: h * 0.18),
                        startRadius: 0, endRadius: r * 0.40))
            }
        }
    }

    // =========================================================================
    // MARK: - Snowglobe
    // Frosted-glass sphere caught mid-blizzard: ~22 detailed feathered flakes
    // plus ~52 fine snow dots, all swirling vigorously around the dome (orbit +
    // turbulence), like a hard-shaken globe.  Pure Canvas + TimelineView.
    // =========================================================================
    private var snowglobeCanvas: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t  = timeline.date.timeIntervalSinceReferenceDate
                let w  = size.width, h = size.height
                let cx = w / 2, cy = h / 2
                let r  = min(w, h) / 2
                let rect = CGRect(x: 0, y: 0, width: w, height: h)

                // ── Glass body — translucent, so the dark background shows
                //    through the middle (see-through), with a frosted, light-
                //    catching rim.  This is what reads as "glass", not a fill.
                ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.20, green: 0.32, blue: 0.48).opacity(0.14), location: 0.00),
                        .init(color: Color(red: 0.40, green: 0.56, blue: 0.74).opacity(0.22), location: 0.66),
                        .init(color: Color(red: 0.84, green: 0.93, blue: 1.00).opacity(0.62), location: 1.00),
                    ]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))

                // Bottom-right refraction glow — light bending through the glass.
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: r * 0.05, dy: r * 0.05)),
                    with: .radialGradient(
                        Gradient(colors: [.clear, Color(red: 0.72, green: 0.88, blue: 1.0).opacity(0.45)]),
                        center: CGPoint(x: w * 0.70, y: h * 0.74),
                        startRadius: r * 0.2, endRadius: r * 0.95))

                // ── Snow — crisp 6-armed, feathered flakes drifting, swaying,
                //    rotating, and twinkling inside the dome.
                for i in 0..<22 {
                    let seed = Double(i) * 0.618 + 0.13
                    let f1 = (seed * 1.7).truncatingRemainder(dividingBy: 1.0)
                    let f2 = (seed * 3.1).truncatingRemainder(dividingBy: 1.0)
                    // Vigorous orbit around the dome — each flake at its own
                    // radius + speed — plus a fast little epicycle so the swirl
                    // churns and tumbles instead of tracing clean circles.
                    let swirl = t * (1.3 + 0.9 * f1) + seed * 6.283
                    let rad   = r * CGFloat(0.16 + 0.66 * f2)
                    let px = cx + CGFloat(cos(swirl)) * rad + CGFloat(cos(t * 2.1 + seed * 4)) * r * 0.10
                    let py = cy + CGFloat(sin(swirl)) * rad + CGFloat(sin(t * 1.8 + seed * 5)) * r * 0.10
                    if hypot(px - cx, py - cy) > r * 0.88 { continue }
                    let twinkle = 0.55 + 0.45 * sin(t * 1.8 + seed * 7)
                    let fr  = r * CGFloat(0.05 + Double(i % 4) * 0.018)
                    let rot = t * 0.9 + seed * 6

                    var flake = Path()
                    for k in 0..<3 {                      // 3 lines → 6 arms
                        let a = rot + Double(k) * Double.pi / 3
                        let ex = CGFloat(cos(a)) * fr, ey = CGFloat(sin(a)) * fr
                        flake.move(to: CGPoint(x: px - ex, y: py - ey))
                        flake.addLine(to: CGPoint(x: px + ex, y: py + ey))
                    }
                    for k in 0..<6 {                      // feathered branches
                        let a = rot + Double(k) * Double.pi / 3
                        let root = CGPoint(x: px + CGFloat(cos(a)) * fr * 0.58,
                                           y: py + CGFloat(sin(a)) * fr * 0.58)
                        for s in [Double.pi / 4, -Double.pi / 4] {
                            flake.move(to: root)
                            flake.addLine(to: CGPoint(x: root.x + CGFloat(cos(a + s)) * fr * 0.34,
                                                      y: root.y + CGFloat(sin(a + s)) * fr * 0.34))
                        }
                    }
                    ctx.stroke(flake, with: .color(.white.opacity(twinkle)),
                               lineWidth: max(0.6, r * 0.022))
                }

                // ── Fine blizzard snow — lots of cheap dots churning fast,
                //    layered over the detailed flakes for whiteout density.
                for i in 0..<52 {
                    let seed = Double(i) * 0.371 + 0.07
                    let f1 = (seed * 2.3).truncatingRemainder(dividingBy: 1.0)
                    let f2 = (seed * 4.7).truncatingRemainder(dividingBy: 1.0)
                    let swirl = t * (1.7 + 1.1 * f1) + seed * 6.283
                    let rad   = r * CGFloat(0.08 + 0.80 * f2)
                    let px = cx + CGFloat(cos(swirl)) * rad + CGFloat(cos(t * 2.6 + seed * 3)) * r * 0.09
                    let py = cy + CGFloat(sin(swirl)) * rad + CGFloat(sin(t * 2.3 + seed * 4)) * r * 0.09
                    if hypot(px - cx, py - cy) > r * 0.90 { continue }
                    let sz = r * CGFloat(0.013 + 0.018 * f1)
                    let tw = 0.45 + 0.45 * sin(t * 2.2 + seed * 5)
                    ctx.fill(Path(ellipseIn: CGRect(x: px - sz, y: py - sz, width: sz * 2, height: sz * 2)),
                             with: .color(.white.opacity(tw)))
                }

                // ── Glass edge — the rim catching light (sells the sphere).
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.04, dy: r * 0.04)),
                           with: .color(Color(red: 0.86, green: 0.94, blue: 1.0).opacity(0.55)),
                           lineWidth: max(0.8, r * 0.05))

                // ── Specular highlight — top-left glossy reflection.
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.16, y: h * 0.12,
                                                width: w * 0.30, height: h * 0.24)),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.9), .clear]),
                        center: CGPoint(x: w * 0.27, y: h * 0.20),
                        startRadius: 0, endRadius: r * 0.40))
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

            // Classic basketball: a straight vertical meridian + horizontal
            // equator (the centre cross), plus two meridians bowing out to the
            // left and right — the eight-panel look everyone recognises.

            // Vertical meridian (front seam), straight down the centre.
            var vLine = Path()
            vLine.move(to: CGPoint(x: cx, y: cy - r * 0.97))
            vLine.addLine(to: CGPoint(x: cx, y: cy + r * 0.97))
            ctx.stroke(vLine, with: .color(seam), style: style)

            // Horizontal equator, straight across.
            var hLine = Path()
            hLine.move(to: CGPoint(x: cx - r * 0.97, y: cy))
            hLine.addLine(to: CGPoint(x: cx + r * 0.97, y: cy))
            ctx.stroke(hLine, with: .color(seam), style: style)

            // Left meridian — top pole → bottom pole, bowing left.
            ctx.stroke(
                qbPath(CGPoint(x: cx, y: cy - r * 0.92),
                       CGPoint(x: cx - r * 0.82, y: cy),
                       CGPoint(x: cx, y: cy + r * 0.92)),
                with: .color(seam), style: style)

            // Right meridian — mirrors left, bowing right.
            ctx.stroke(
                qbPath(CGPoint(x: cx, y: cy - r * 0.92),
                       CGPoint(x: cx + r * 0.82, y: cy),
                       CGPoint(x: cx, y: cy + r * 0.92)),
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
                    .foregroundStyle(.black))
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

    // =========================================================================
    // MARK: - Aurora  (Legendary · anchors the Aurora bundle)
    // A dark night sky with Northern Lights that fade in and out and drift, the
    // way they really do.  TWO MeshGradient layers: a constant dark-sky base,
    // and an additive aurora layer whose green/teal/violet patches each pulse
    // fully in and out on independent phases (so the lights come and go) while
    // the control points sway (so they travel).  When all patches are low the
    // sphere is just the dark starry sky.  A Canvas overlay adds limb-darkening,
    // twinkling stars, and a small specular.  Reduce Motion freezes it.
    // =========================================================================
    private static let auroraGrid: [SIMD2<Float>] = [
        [0, 0],   [0.5, 0],   [1, 0],
        [0, 0.5], [0.5, 0.5], [1, 0.5],
        [0, 1],   [0.5, 1],   [1, 1],
    ]
    /// Constant dark night sky — deep indigo up top fading to near-black.
    private static let nightMesh: [Color] = [
        Color(red: 0.06, green: 0.09, blue: 0.22), Color(red: 0.05, green: 0.08, blue: 0.20), Color(red: 0.06, green: 0.09, blue: 0.22),
        Color(red: 0.03, green: 0.05, blue: 0.15), Color(red: 0.02, green: 0.04, blue: 0.12), Color(red: 0.03, green: 0.05, blue: 0.15),
        Color(red: 0.01, green: 0.02, blue: 0.08), Color(red: 0.01, green: 0.02, blue: 0.07), Color(red: 0.01, green: 0.02, blue: 0.08),
    ]

    private var auroraCanvas: some View {
        TimelineView(.animation) { tl in
            let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate

            // Each patch fades fully in and out (clamped sine → off about half
            // its cycle) on its own slow phase, so the lights come and go and
            // seem to travel.  Reduce Motion holds a gentle steady glow.
            let i0 = reduceMotion ? 0.5 : max(0, sin(t * 0.33 + 0.0))
            let i1 = reduceMotion ? 0.4 : max(0, sin(t * 0.27 + 1.7))
            let i2 = reduceMotion ? 0.3 : max(0, sin(t * 0.31 + 3.1))
            let i3 = reduceMotion ? 0.5 : max(0, sin(t * 0.23 + 4.6))
            let i4 = reduceMotion ? 0.3 : max(0, sin(t * 0.29 + 5.9))
            let green  = Color(red: 0.16, green: 0.95, blue: 0.55)
            let aqua   = Color(red: 0.22, green: 0.82, blue: 0.80)
            let violet = Color(red: 0.60, green: 0.34, blue: 0.98)
            let pink   = Color(red: 0.95, green: 0.40, blue: 0.78)
            let auroraColors: [Color] = [
                .clear,                      green.opacity(0.85 * i0),    .clear,
                green.opacity(0.80 * i1),    aqua.opacity(0.70 * i2),     violet.opacity(0.85 * i3),
                pink.opacity(0.45 * i2),     violet.opacity(0.65 * i4),   .clear,
            ]
            // Curtains sway — drift the aurora layer's interior + mid-edge
            // points (corners stay pinned so it always covers the sphere).
            let dx = Float(sin(t * 0.40))       * 0.08
            let dy = Float(sin(t * 0.33 + 1.0)) * 0.06
            let auroraPts: [SIMD2<Float>] = [
                [0, 0],              [0.5 + dx, 0],          [1, 0],
                [0, 0.45 + dy],      [0.5 - dx, 0.5 + dy],   [1, 0.45 - dy],
                [0, 1],              [0.5 + dx, 1],          [1, 1],
            ]

            ZStack {
                // Constant dark sky.
                MeshGradient(width: 3, height: 3, points: Self.auroraGrid, colors: Self.nightMesh)

                // Aurora light — additive, so it glows over the night and is
                // invisible where its colour is clear.
                MeshGradient(width: 3, height: 3, points: auroraPts, colors: auroraColors)
                    .blendMode(.plusLighter)

                Canvas { ctx, size in
                    let w = size.width, h = size.height
                    let cx = w / 2, cy = h / 2, r = min(w, h) / 2

                    // Limb darkening — reads as a lit sphere, keeps edges dark.
                    ctx.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                        with: .radialGradient(Gradient(stops: [
                            .init(color: .clear, location: 0.55),
                            .init(color: .black.opacity(0.35), location: 0.84),
                            .init(color: .black.opacity(0.75), location: 1.0)]),
                            center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))

                    // Twinkling stars (seen through the dark sky).
                    for (i, s) in [(0.30, 0.30), (0.66, 0.24), (0.52, 0.60),
                                   (0.24, 0.60), (0.74, 0.56), (0.44, 0.42),
                                   (0.60, 0.72), (0.36, 0.20)].enumerated() {
                        let tw = reduceMotion ? 0.7 : 0.4 + 0.5 * sin(t * 2.2 + Double(i) * 1.7)
                        if tw < 0.2 { continue }
                        let px = w * CGFloat(s.0), py = h * CGFloat(s.1)
                        if hypot(px - cx, py - cy) > r * 0.86 { continue }
                        let ss = r * 0.018
                        ctx.fill(Path(ellipseIn: CGRect(x: px - ss, y: py - ss, width: ss * 2, height: ss * 2)),
                                 with: .color(.white.opacity(tw)))
                    }

                    // Small crisp specular — sells the glossy sphere without
                    // washing the dark sky grey.
                    ctx.fill(Path(ellipseIn: CGRect(x: w * 0.20, y: h * 0.13, width: w * 0.22, height: h * 0.16)),
                        with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .clear]),
                            center: CGPoint(x: w * 0.28, y: h * 0.19), startRadius: 0, endRadius: r * 0.26))
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Pluto  (Legendary)
    // Icy tan dwarf-planet: a warm beige surface reddening toward the limb,
    // dark equatorial maculae, and the signature cream "heart" (Tombaugh Regio)
    // — the one feature everyone recognises Pluto by.  Static, like the planets.
    // =========================================================================
    private var plutoCanvas: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w / 2, cy = h / 2
            let r  = min(w, h) / 2

            // Surface — icy tan, reddening toward the limb.
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 0.87, green: 0.77, blue: 0.63),
                                      Color(red: 0.70, green: 0.52, blue: 0.40),
                                      Color(red: 0.40, green: 0.25, blue: 0.19)]),
                    center: CGPoint(x: cx - r * 0.22, y: cy - r * 0.24),
                    startRadius: 0, endRadius: r * 1.25))

            // Dark maculae — soft reddish-brown blotches (Cthulhu Macula etc.).
            for (fx, fy, fr) in [(0.28, 0.64, 0.30), (0.16, 0.42, 0.18), (0.76, 0.66, 0.22)] {
                let bx = cx - r + CGFloat(fx) * r * 2
                let by = cy - r + CGFloat(fy) * r * 2
                let br = CGFloat(fr) * r
                ctx.fill(Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 0.30, green: 0.17, blue: 0.13).opacity(0.65), .clear]),
                        center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: br))
            }

            // Tombaugh Regio — the signature cream-white heart, lower-centre.
            let hx = cx + r * 0.08, hy = cy + r * 0.16, hs = r * 0.60
            var heart = Path()
            let n = 44
            for i in 0...n {
                let a = Double(i) / Double(n) * 2 * .pi
                let px = hx + CGFloat(16 * pow(sin(a), 3)) / 32 * hs
                let py = hy - CGFloat(13 * cos(a) - 5 * cos(2*a) - 2 * cos(3*a) - cos(4*a)) / 32 * hs
                if i == 0 { heart.move(to: CGPoint(x: px, y: py)) } else { heart.addLine(to: CGPoint(x: px, y: py)) }
            }
            heart.closeSubpath()
            ctx.fill(heart, with: .radialGradient(
                Gradient(colors: [Color(red: 0.97, green: 0.94, blue: 0.87),
                                  Color(red: 0.84, green: 0.78, blue: 0.70).opacity(0.85)]),
                center: CGPoint(x: hx, y: hy - hs * 0.2), startRadius: 0, endRadius: hs * 0.95))

            // Cool ice specular (top-left).
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.46, y: cy - r * 0.80, width: r * 0.52, height: r * 0.34)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.5), .clear]),
                    center: CGPoint(x: cx - r * 0.30, y: cy - r * 0.64), startRadius: 0, endRadius: r * 0.4))
        }
    }

    // =========================================================================
    // MARK: - Planets (shared renderer)
    // A textured sphere — lit base, optional latitude bands (gas giants),
    // surface mottle (rocky worlds), polar caps, a storm spot, plus a
    // terminator + specular that sell the 3-D read.  Clipped to a circle by
    // the caller.  Far richer than the old flat radial gradient.
    // =========================================================================
    private var planetRim: some View { Circle().stroke(.black.opacity(0.28), lineWidth: 0.5) }

    private func planet(_ colors: [Color], bands: Bool = false, mottle: Bool = false,
                        spot: Color? = nil, poles: Bool = false) -> some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w / 2, cy = h / 2
            let r  = min(w, h) / 2
            let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

            // Lit base sphere.
            ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                Gradient(colors: colors),
                center: CGPoint(x: cx - r * 0.28, y: cy - r * 0.30),
                startRadius: 0, endRadius: r * 1.28))

            // Latitude bands (gas giants).
            if bands {
                let n = 8
                for i in 0..<n {
                    let yf = (Double(i) + 0.5) / Double(n)
                    let by = cy - r + CGFloat(yf) * r * 2
                    let bh = r * 2 / CGFloat(n)
                    let tint = (i % 2 == 0) ? colors[1].opacity(0.30) : colors[2].opacity(0.30)
                    ctx.fill(Path(roundedRect: CGRect(x: cx - r, y: by - bh / 2, width: r * 2, height: bh),
                                  cornerRadius: 0), with: .color(tint))
                }
            }

            // Surface mottle (continents / craters) — seeded blobs, dark tone.
            if mottle {
                var s: UInt64 = 0xA17C5
                func rnd() -> CGFloat { s = s &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(s >> 40) / CGFloat(1 << 24) }
                for _ in 0..<11 {
                    let bx = cx + (rnd() - 0.5) * r * 1.5
                    let by = cy + (rnd() - 0.5) * r * 1.5
                    let br = r * (0.10 + rnd() * 0.18)
                    ctx.fill(Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                        with: .radialGradient(Gradient(colors: [colors[2].opacity(0.55), .clear]),
                            center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: br))
                }
            }

            // Polar caps (Mars).
            if poles {
                for fy in [CGFloat(0.07), CGFloat(0.93)] {
                    let py = cy - r + fy * r * 2
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.45, y: py - r * 0.14, width: r * 0.9, height: r * 0.28)),
                        with: .radialGradient(Gradient(colors: [.white.opacity(0.85), .clear]),
                            center: CGPoint(x: cx, y: py), startRadius: 0, endRadius: r * 0.5))
                }
            }

            // Storm spot (Jupiter red / Neptune dark).
            if let spot {
                let sx = cx + r * 0.28, sy = cy + r * 0.16
                ctx.fill(Path(ellipseIn: CGRect(x: sx - r * 0.20, y: sy - r * 0.12, width: r * 0.40, height: r * 0.24)),
                    with: .radialGradient(Gradient(colors: [spot, spot.opacity(0.0)]),
                        center: CGPoint(x: sx, y: sy), startRadius: 0, endRadius: r * 0.22))
            }

            // Terminator — night-side darkening, bottom-right.
            ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                Gradient(stops: [.init(color: .clear, location: 0.0),
                                 .init(color: .clear, location: 0.55),
                                 .init(color: .black.opacity(0.50), location: 1.0)]),
                center: CGPoint(x: cx + r * 0.34, y: cy + r * 0.36), startRadius: 0, endRadius: r * 1.25))

            // Specular highlight.
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.46, y: cy - r * 0.80, width: r * 0.5, height: r * 0.34)),
                with: .radialGradient(Gradient(colors: [.white.opacity(0.45), .clear]),
                    center: CGPoint(x: cx - r * 0.30, y: cy - r * 0.64), startRadius: 0, endRadius: r * 0.4))
        }
    }

    private static let earthPalette   = [Color(red: 0.72, green: 0.90, blue: 1.00), Color(red: 0.20, green: 0.52, blue: 0.85), Color(red: 0.10, green: 0.46, blue: 0.24), Color(red: 0.02, green: 0.10, blue: 0.26)]
    private static let marsPalette    = [Color(red: 1.00, green: 0.78, blue: 0.58), Color(red: 0.86, green: 0.42, blue: 0.22), Color(red: 0.55, green: 0.20, blue: 0.10), Color(red: 0.26, green: 0.08, blue: 0.04)]
    private static let mercuryPalette = [Color(red: 0.88, green: 0.84, blue: 0.78), Color(red: 0.60, green: 0.56, blue: 0.50), Color(red: 0.36, green: 0.32, blue: 0.28), Color(red: 0.14, green: 0.12, blue: 0.10)]
    private static let jupiterPalette = [Color(red: 1.00, green: 0.92, blue: 0.78), Color(red: 0.90, green: 0.68, blue: 0.44), Color(red: 0.70, green: 0.34, blue: 0.20), Color(red: 0.42, green: 0.14, blue: 0.10)]
    private static let neptunePalette = [Color(red: 0.66, green: 0.84, blue: 1.00), Color(red: 0.20, green: 0.42, blue: 0.92), Color(red: 0.08, green: 0.18, blue: 0.62), Color(red: 0.02, green: 0.06, blue: 0.30)]
    private static let venusPalette   = [Color(red: 1.00, green: 0.96, blue: 0.80), Color(red: 0.96, green: 0.82, blue: 0.42), Color(red: 0.78, green: 0.54, blue: 0.18), Color(red: 0.42, green: 0.26, blue: 0.06)]
    private static let uranusPalette  = [Color(red: 0.82, green: 1.00, blue: 1.00), Color(red: 0.46, green: 0.86, blue: 0.88), Color(red: 0.16, green: 0.56, blue: 0.62), Color(red: 0.04, green: 0.26, blue: 0.32)]

    // =========================================================================
    // MARK: - Premium marble / metal / gem (shared renderers)
    // Turn a flat 4-stop palette into a believable polished sphere — a glowing
    // Fresnel rim, a soft + sharp specular, two-tone metal reflections, or cut-
    // gem facets.  Clipped to a circle by the caller.
    // =========================================================================

    /// Polished glass marble — lit base + glowing rim light + soft & sharp speculars.
    private func glossMarble(_ colors: [Color]) -> some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w / 2, cy = h / 2, r = min(w, h) / 2
            let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

            ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(Gradient(colors: colors),
                center: CGPoint(x: cx - r * 0.30, y: cy - r * 0.32), startRadius: 0, endRadius: r * 1.25))

            // Fresnel rim — a soft COLOURED glow where light wraps the edge
            // (not white), kept gentle.
            ctx.blendMode = .plusLighter
            ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                Gradient(stops: [.init(color: .clear, location: 0.0),
                                 .init(color: .clear, location: 0.82),
                                 .init(color: (colors.first ?? .white).opacity(0.38), location: 1.0)]),
                center: CGPoint(x: cx + r * 0.42, y: cy + r * 0.46), startRadius: 0, endRadius: r * 1.05))
            ctx.blendMode = .normal

            // Soft top-left sheen — a gentle highlight, NOT a hot white crescent.
            // (The big 0.60 blob + 0.90 hotspot that read as a bright shiny
            // streak are gone — this is just a subtle glossy lift.)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.52, y: cy - r * 0.72, width: r * 0.58, height: r * 0.40)),
                with: .radialGradient(Gradient(colors: [.white.opacity(0.20), .clear]),
                    center: CGPoint(x: cx - r * 0.30, y: cy - r * 0.46), startRadius: 0, endRadius: r * 0.46))
        }
    }

    /// Plain solid marble — a cleanly lit sphere with gentle depth and only a
    /// whisper of top sheen.  NO rim highlight, minimal glow.  Used by the basic
    /// solid colours (red/blue/green/…), which Mac wants understated.
    private func plainMarble(_ colors: [Color]) -> some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w / 2, cy = h / 2, r = min(w, h) / 2
            let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

            // Lit base sphere — highlight up top-left, deep colour toward the rim.
            ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(Gradient(colors: colors),
                center: CGPoint(x: cx - r * 0.26, y: cy - r * 0.30), startRadius: 0, endRadius: r * 1.28))

            // Gentle bottom darkening for roundness — no bright top band, no rim.
            ctx.fill(Path(ellipseIn: sphere), with: .linearGradient(
                Gradient(stops: [.init(color: .clear, location: 0.52),
                                 .init(color: (colors.last ?? .black).opacity(0.40), location: 1.0)]),
                startPoint: CGPoint(x: cx, y: cy - r), endPoint: CGPoint(x: cx, y: cy + r)))

            // A whisper of top-left sheen (much softer than the metal/gloss ones).
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.48, y: cy - r * 0.70, width: r * 0.46, height: r * 0.30)),
                with: .radialGradient(Gradient(colors: [.white.opacity(0.13), .clear]),
                    center: CGPoint(x: cx - r * 0.30, y: cy - r * 0.48), startRadius: 0, endRadius: r * 0.36))
        }
    }

    /// Polished metal — base + bright sky / dark ground reflection + specular streak.
    private func metalMarble(_ colors: [Color]) -> some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w / 2, cy = h / 2, r = min(w, h) / 2
            let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

            ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(Gradient(colors: colors),
                center: CGPoint(x: cx - r * 0.22, y: cy - r * 0.26), startRadius: 0, endRadius: r * 1.25))
            // Two-tone reflection: bright sky up top, dark ground below.
            ctx.fill(Path(ellipseIn: sphere), with: .linearGradient(
                Gradient(stops: [.init(color: (colors.first ?? .white).opacity(0.85), location: 0.0),
                                 .init(color: .clear, location: 0.42),
                                 .init(color: .clear, location: 0.58),
                                 .init(color: (colors.last ?? .black).opacity(0.70), location: 1.0)]),
                startPoint: CGPoint(x: cx, y: cy - r), endPoint: CGPoint(x: cx, y: cy + r)))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.45, y: cy - r * 0.60, width: r * 0.34, height: r * 0.14)),
                with: .color(.white.opacity(0.92)))
            ctx.stroke(Path(ellipseIn: sphere.insetBy(dx: r * 0.03, dy: r * 0.03)),
                with: .color((colors.first ?? .white).opacity(0.45)), lineWidth: max(0.6, r * 0.045))
        }
    }

    /// Cut gemstone — deep translucent body, inner glow, facet glints, bright rim.
    private func gemMarble(_ colors: [Color]) -> some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w / 2, cy = h / 2, r = min(w, h) / 2
            let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            let mid = colors.count > 1 ? colors[1] : (colors.first ?? .white)

            ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(Gradient(colors: colors),
                center: CGPoint(x: cx - r * 0.26, y: cy - r * 0.28), startRadius: 0, endRadius: r * 1.30))

            ctx.blendMode = .plusLighter
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.5, y: cy - r * 0.4, width: r, height: r)),
                with: .radialGradient(Gradient(colors: [mid.opacity(0.70), .clear]),
                    center: CGPoint(x: cx, y: cy + r * 0.10), startRadius: 0, endRadius: r * 0.60))
            for (fx, fy, fr) in [(-0.28, -0.10, 0.10), (0.20, 0.24, 0.08), (0.05, -0.30, 0.07), (-0.10, 0.34, 0.06)] {
                let gx = cx + CGFloat(fx) * r, gy = cy + CGFloat(fy) * r, gr = CGFloat(fr) * r
                var d = Path()
                d.move(to: CGPoint(x: gx, y: gy - gr));        d.addLine(to: CGPoint(x: gx + gr * 0.6, y: gy))
                d.addLine(to: CGPoint(x: gx, y: gy + gr));     d.addLine(to: CGPoint(x: gx - gr * 0.6, y: gy))
                d.closeSubpath()
                ctx.fill(d, with: .color(.white.opacity(0.80)))
            }
            ctx.blendMode = .normal

            ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.46, y: cy - r * 0.66, width: r * 0.34, height: r * 0.22)),
                with: .radialGradient(Gradient(colors: [.white.opacity(0.85), .clear]),
                    center: CGPoint(x: cx - r * 0.34, y: cy - r * 0.56), startRadius: 0, endRadius: r * 0.30))
            ctx.stroke(Path(ellipseIn: sphere.insetBy(dx: r * 0.02, dy: r * 0.02)),
                with: .color(mid.opacity(0.55)), lineWidth: max(0.6, r * 0.04))
        }
    }

    // =========================================================================
    // MARK: - Cosmic / electric (bespoke animated)
    // Galaxy spiral, drifting nebula clouds, shifting opal iridescence, and a
    // pulsing neon orb — far beyond a flat gradient.  Reduce Motion freezes them.
    // =========================================================================

    private var galaxyCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2
                let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.14, green: 0.10, blue: 0.30), Color(red: 0.03, green: 0.02, blue: 0.12)]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r * 1.2))
                ctx.blendMode = .plusLighter
                for i in 0..<55 {                       // two spiral arms of stars
                    let f = Double(i) / 55.0
                    let ang = f * 5.5 + t * 0.25 + Double(i % 2) * .pi
                    let rad = r * CGFloat(pow(f, 0.85)) * 0.96
                    let sx = cx + CGFloat(cos(ang)) * rad
                    let sy = cy + CGFloat(sin(ang)) * rad
                    if hypot(sx - cx, sy - cy) > r * 0.95 { continue }
                    let ss = r * CGFloat(0.012 + (1 - f) * 0.02)
                    let col = f < 0.4 ? Color(red: 1, green: 0.95, blue: 0.85) : Color(red: 0.72, green: 0.82, blue: 1.0)
                    let tw = reduceMotion ? 0.85 : 0.5 + 0.5 * sin(t * 3 + Double(i))
                    ctx.fill(Path(ellipseIn: CGRect(x: sx - ss, y: sy - ss, width: ss * 2, height: ss * 2)),
                             with: .color(col.opacity(tw)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.4, y: cy - r * 0.4, width: r * 0.8, height: r * 0.8)),
                    with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.8).opacity(0.9),
                                                            Color(red: 0.8, green: 0.6, blue: 1).opacity(0.3), .clear]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r * 0.45))
                ctx.blendMode = .normal
                galaxySpecular(ctx, cx: cx, cy: cy, r: r)
            }
        }
    }

    private var nebulaCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2
                let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.16, green: 0.06, blue: 0.22), Color(red: 0.04, green: 0.02, blue: 0.10)]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r * 1.2))
                ctx.blendMode = .plusLighter
                let blobs: [(CGFloat, CGFloat, Color)] = [
                    (-0.30, -0.20, Color(red: 0.95, green: 0.30, blue: 0.70)),
                    ( 0.28,  0.10, Color(red: 0.55, green: 0.30, blue: 0.95)),
                    ( 0.00,  0.35, Color(red: 0.30, green: 0.70, blue: 0.95)),
                    ( 0.15, -0.30, Color(red: 0.95, green: 0.55, blue: 0.40)),
                ]
                for (i, blob) in blobs.enumerated() {
                    let bx = cx + blob.0 * r + CGFloat(sin(t * 0.4 + Double(i) * 1.7)) * r * 0.08
                    let by = cy + blob.1 * r + CGFloat(cos(t * 0.3 + Double(i))) * r * 0.06
                    let br = r * (0.45 + 0.10 * CGFloat(sin(t * 0.5 + Double(i))))
                    ctx.fill(Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                        with: .radialGradient(Gradient(colors: [blob.2.opacity(0.55), .clear]),
                            center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: br))
                }
                for (idx, s) in [(0.30, 0.20), (0.70, 0.30), (0.50, 0.60), (0.22, 0.70),
                                 (0.80, 0.60), (0.45, 0.40), (0.60, 0.16)].enumerated() {
                    let sx = cx - r + CGFloat(s.0) * r * 2, sy = cy - r + CGFloat(s.1) * r * 2
                    if hypot(sx - cx, sy - cy) > r * 0.9 { continue }
                    let tw = reduceMotion ? 0.7 : 0.4 + 0.5 * sin(t * 2.5 + Double(idx))
                    let ss = r * 0.02
                    ctx.fill(Path(ellipseIn: CGRect(x: sx - ss, y: sy - ss, width: ss * 2, height: ss * 2)),
                             with: .color(.white.opacity(tw)))
                }
                ctx.blendMode = .normal
                galaxySpecular(ctx, cx: cx, cy: cy, r: r)
            }
        }
    }

    private var opalCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2
                let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.96, green: 0.97, blue: 1.0), Color(red: 0.70, green: 0.74, blue: 0.86),
                                      Color(red: 0.40, green: 0.44, blue: 0.60)]),
                    center: CGPoint(x: cx - r * 0.28, y: cy - r * 0.30), startRadius: 0, endRadius: r * 1.25))
                ctx.blendMode = .plusLighter
                let patches: [(CGFloat, CGFloat, Double)] = [(-0.25, -0.15, 0.0), (0.22, 0.05, 0.3),
                                                             (0.0, 0.30, 0.55), (-0.15, 0.30, 0.75), (0.30, -0.25, 0.9)]
                for (i, p) in patches.enumerated() {
                    let hue = (t * 0.08 + p.2).truncatingRemainder(dividingBy: 1.0)
                    let col = Color(hue: hue, saturation: 0.75, brightness: 1.0)
                    let bx = cx + p.0 * r, by = cy + p.1 * r
                    let br = r * (0.30 + 0.06 * CGFloat(sin(t * 0.6 + Double(i))))
                    ctx.fill(Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                        with: .radialGradient(Gradient(colors: [col.opacity(0.5), .clear]),
                            center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: br))
                }
                ctx.blendMode = .normal
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.52, y: cy - r * 0.80, width: r * 0.55, height: r * 0.34)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(0.70), .clear]),
                        center: CGPoint(x: cx - r * 0.34, y: cy - r * 0.60), startRadius: 0, endRadius: r * 0.4))
            }
        }
    }

    private var neonCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2
                let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                let pulse = reduceMotion ? 0.8 : 0.6 + 0.4 * sin(t * 2.4)
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 1.0, green: 0.30, blue: 0.95), Color(red: 0.55, green: 0.10, blue: 0.92),
                                      Color(red: 0.10, green: 0.20, blue: 0.85), Color(red: 0.05, green: 0.02, blue: 0.30)]),
                    center: CGPoint(x: cx - r * 0.20, y: cy - r * 0.24), startRadius: 0, endRadius: r * 1.25))
                ctx.blendMode = .plusLighter
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 1.0, green: 0.30, blue: 0.95).opacity(0.5 * pulse), .clear]),
                    center: CGPoint(x: cx - r * 0.15, y: cy - r * 0.18), startRadius: 0, endRadius: r * 0.9))
                ctx.stroke(Path(ellipseIn: sphere.insetBy(dx: r * 0.04, dy: r * 0.04)),
                    with: .color(Color(red: 0.4, green: 0.9, blue: 1.0).opacity(0.6 * pulse)), lineWidth: max(0.8, r * 0.06))
                ctx.blendMode = .normal
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.46, y: cy - r * 0.74, width: r * 0.4, height: r * 0.26)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(0.8), .clear]),
                        center: CGPoint(x: cx - r * 0.32, y: cy - r * 0.58), startRadius: 0, endRadius: r * 0.3))
            }
        }
    }

    /// Shared top-left gloss for the dark cosmic skins.
    private func galaxySpecular(_ ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.5, y: cy - r * 0.82, width: r * 0.5, height: r * 0.30)),
            with: .radialGradient(Gradient(colors: [.white.opacity(0.4), .clear]),
                center: CGPoint(x: cx - r * 0.32, y: cy - r * 0.62), startRadius: 0, endRadius: r * 0.35))
    }

    // =========================================================================
    // MARK: - Diamond (Diamond Balls IAP exclusive)
    // The showpiece skin: a brilliant-cut gem with a faceted crown that
    // shimmers facet-by-facet, slowly rotating spectral "fire" (refracted
    // rainbow light), and twinkling 4-point sparkle flares.  Reduce Motion
    // freezes all three.
    // =========================================================================
    private var diamondCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2
                let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

                // Brilliant icy base.
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [.white,
                                      Color(red: 0.80, green: 0.95, blue: 1.0),
                                      Color(red: 0.50, green: 0.78, blue: 0.98),
                                      Color(red: 0.20, green: 0.42, blue: 0.72)]),
                    center: CGPoint(x: cx - r * 0.26, y: cy - r * 0.30), startRadius: 0, endRadius: r * 1.30))

                // Spectral fire — drifting refracted rainbow, additively blended.
                ctx.blendMode = .plusLighter
                for i in 0..<6 {
                    let a   = t * 0.5 + Double(i) * .pi / 3
                    let hue = (t * 0.06 + Double(i) / 6.0).truncatingRemainder(dividingBy: 1.0)
                    let col = Color(hue: hue, saturation: 0.62, brightness: 1.0)
                    let px  = cx + CGFloat(cos(a)) * r * 0.34
                    let py  = cy + CGFloat(sin(a)) * r * 0.34
                    let br  = r * 0.42
                    ctx.fill(Path(ellipseIn: CGRect(x: px - br, y: py - br, width: br * 2, height: br * 2)),
                        with: .radialGradient(Gradient(colors: [col.opacity(0.28), .clear]),
                            center: CGPoint(x: px, y: py), startRadius: 0, endRadius: br))
                }
                ctx.blendMode = .normal

                // Faceted brilliant cut — radiating triangles, each shimmering
                // on its own phase, plus a central table.
                let facets = 10
                let tableR = r * 0.40
                for k in 0..<facets {
                    let a0 = Double(k)     / Double(facets) * 2 * .pi - .pi / 2
                    let a1 = Double(k + 1) / Double(facets) * 2 * .pi - .pi / 2
                    let am = (a0 + a1) / 2
                    let in0 = CGPoint(x: cx + CGFloat(cos(a0)) * tableR, y: cy + CGFloat(sin(a0)) * tableR)
                    let in1 = CGPoint(x: cx + CGFloat(cos(a1)) * tableR, y: cy + CGFloat(sin(a1)) * tableR)
                    let out = CGPoint(x: cx + CGFloat(cos(am)) * r * 0.97, y: cy + CGFloat(sin(am)) * r * 0.97)
                    var f = Path(); f.move(to: in0); f.addLine(to: in1); f.addLine(to: out); f.closeSubpath()
                    let shimmer = 0.5 + 0.5 * sin(t * 2.0 + Double(k) * 0.9)
                    ctx.fill(f, with: .color(.white.opacity(0.10 + 0.22 * shimmer)))
                    ctx.stroke(f, with: .color(.white.opacity(0.16)), lineWidth: max(0.4, r * 0.009))
                }
                var table = Path()
                for k in 0...facets {
                    let a = Double(k) / Double(facets) * 2 * .pi - .pi / 2
                    let p = CGPoint(x: cx + CGFloat(cos(a)) * tableR, y: cy + CGFloat(sin(a)) * tableR)
                    if k == 0 { table.move(to: p) } else { table.addLine(to: p) }
                }
                let tableShim = 0.5 + 0.5 * sin(t * 1.5)
                ctx.fill(table, with: .color(.white.opacity(0.12 + 0.16 * tableShim)))
                ctx.stroke(table, with: .color(.white.opacity(0.30)), lineWidth: max(0.5, r * 0.012))

                // Twinkling 4-point sparkle flares.
                ctx.blendMode = .plusLighter
                for (i, s) in [(-0.30, -0.22, 0.0), (0.26, -0.12, 0.4), (0.06, 0.30, 0.7),
                               (0.34, 0.24, 0.2), (-0.16, 0.12, 0.9)].enumerated() {
                    let tw = 0.5 + 0.5 * sin(t * 3.0 + s.2 * 6.283 + Double(i))
                    if tw < 0.18 { continue }
                    diamondSparkle(ctx, at: CGPoint(x: cx + CGFloat(s.0) * r, y: cy + CGFloat(s.1) * r),
                                   size: r * (0.09 + 0.10 * CGFloat(tw)), opacity: tw)
                }
                ctx.blendMode = .normal

                // Crisp top-left specular + cool bright rim.
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.50, y: cy - r * 0.74, width: r * 0.42, height: r * 0.28)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(0.9), .clear]),
                        center: CGPoint(x: cx - r * 0.36, y: cy - r * 0.58), startRadius: 0, endRadius: r * 0.32))
                ctx.stroke(Path(ellipseIn: sphere.insetBy(dx: r * 0.02, dy: r * 0.02)),
                    with: .color(Color(red: 0.85, green: 0.95, blue: 1.0).opacity(0.6)), lineWidth: max(0.6, r * 0.04))
            }
        }
    }

    /// A bright 4-point sparkle flare with a soft bloom.
    private func diamondSparkle(_ ctx: GraphicsContext, at c: CGPoint, size: CGFloat, opacity: Double) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - size, y: c.y - size, width: size * 2, height: size * 2)),
            with: .radialGradient(Gradient(colors: [.white.opacity(0.5 * opacity), .clear]),
                center: c, startRadius: 0, endRadius: size))
        var star = Path()
        let L = size, inr = size * 0.16
        for k in 0..<8 {
            let a   = Double(k) * .pi / 4 - .pi / 2
            let rad = (k % 2 == 0) ? L : inr
            let p   = CGPoint(x: c.x + CGFloat(cos(a)) * rad, y: c.y + CGFloat(sin(a)) * rad)
            if k == 0 { star.move(to: p) } else { star.addLine(to: p) }
        }
        star.closeSubpath()
        ctx.fill(star, with: .color(.white.opacity(min(1.0, 0.95 * opacity))))
    }

    // =========================================================================
    // MARK: - Money Ball  (top-coin-pack ($49.99) IAP secret · Legendary)
    // A rolled-up wad of dollar bills: a money-green body with the rolled paper
    // edges reading as stacked striations, a gold currency band strapped around
    // the middle with a "$", and a crisp specular.  Static.  Clipped to a circle
    // by the body switch caller.
    // =========================================================================
    private var moneyBallCanvas: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w / 2, cy = h / 2, r = min(w, h) / 2
            let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

            // 1. Money-green body.
            ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                Gradient(colors: [
                    Color(red: 0.80, green: 0.91, blue: 0.76),
                    Color(red: 0.44, green: 0.68, blue: 0.46),
                    Color(red: 0.18, green: 0.44, blue: 0.27),
                    Color(red: 0.07, green: 0.21, blue: 0.14)]),
                center: CGPoint(x: cx - r * 0.28, y: cy - r * 0.30), startRadius: 0, endRadius: r * 1.25))

            // 2. Rolled-bill striations — the stacked paper edges of the roll.
            //    Each edge is a faintly-bowed line with a thin highlight above it.
            let edge   = Color(red: 0.09, green: 0.29, blue: 0.18).opacity(0.50)
            let hilite = Color(red: 0.88, green: 0.96, blue: 0.84).opacity(0.32)
            let lines  = 9
            for i in 0..<lines {
                let frac = CGFloat(i) / CGFloat(lines - 1)        // 0…1
                let y = cy - r * 0.80 + frac * r * 1.60
                var p = Path()
                p.move(to: CGPoint(x: cx - r, y: y))
                p.addQuadCurve(to: CGPoint(x: cx + r, y: y), control: CGPoint(x: cx, y: y + r * 0.05))
                ctx.stroke(p, with: .color(edge), lineWidth: max(0.6, r * 0.028))
                var p2 = Path()
                p2.move(to: CGPoint(x: cx - r, y: y - r * 0.03))
                p2.addQuadCurve(to: CGPoint(x: cx + r, y: y - r * 0.03), control: CGPoint(x: cx, y: y - r * 0.03 + r * 0.05))
                ctx.stroke(p2, with: .color(hilite), lineWidth: max(0.4, r * 0.014))
            }

            // 3. Gold currency band (the strap) wrapping the roll vertically.
            let bandW = r * 0.52
            let band  = CGRect(x: cx - bandW / 2, y: cy - r, width: bandW, height: r * 2)
            ctx.fill(Path(band), with: .linearGradient(
                Gradient(colors: [Color(red: 0.96, green: 0.84, blue: 0.40),
                                  Color(red: 0.82, green: 0.64, blue: 0.22),
                                  Color(red: 0.66, green: 0.48, blue: 0.14)]),
                startPoint: CGPoint(x: band.minX, y: 0), endPoint: CGPoint(x: band.maxX, y: 0)))
            ctx.stroke(Path(band), with: .color(.black.opacity(0.22)), lineWidth: max(0.5, r * 0.02))

            // 4. "$" stamped on the band.
            let dollar = ctx.resolve(
                Text("$").font(.system(size: r * 0.66, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.16, green: 0.40, blue: 0.25)))
            ctx.draw(dollar, at: CGPoint(x: cx, y: cy), anchor: .center)

            // 5. Crisp top-left specular.
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.52, y: cy - r * 0.74, width: r * 0.46, height: r * 0.28)),
                with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .clear]),
                    center: CGPoint(x: cx - r * 0.34, y: cy - r * 0.60), startRadius: 0, endRadius: r * 0.5))
        }
    }

    // =========================================================================
    // MARK: - High Roller  (High Roller bundle · Legendary)
    // A casino roulette wheel / chip: alternating deep-red and black wedges
    // radiating from the centre, ringed by a polished gold rim, with a crisp
    // white centre pip and a glossy top-left specular.  Static.  Clipped to a
    // circle by the body switch caller.
    // =========================================================================
    private var highRollerCanvas: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w / 2, cy = h / 2, r = min(w, h) / 2
            let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

            let red   = Color(red: 0.74, green: 0.07, blue: 0.10)
            let black = Color(red: 0.07, green: 0.05, blue: 0.06)
            let gold  = Color(red: 0.92, green: 0.74, blue: 0.30)
            let goldD = Color(red: 0.58, green: 0.42, blue: 0.10)

            // 1. Gold rim base (fills the whole disc; wedges sit inside it).
            ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                Gradient(colors: [gold, goldD]),
                center: CGPoint(x: cx - r * 0.24, y: cy - r * 0.26), startRadius: 0, endRadius: r * 1.25))

            // 2. Alternating red/black wedges inside the rim.
            let wedges = 16
            let inner  = r * 0.10
            let outer  = r * 0.86          // leaves a gold rim band
            for k in 0..<wedges {
                let a0 = Double(k)     / Double(wedges) * 2 * .pi - .pi / 2
                let a1 = Double(k + 1) / Double(wedges) * 2 * .pi - .pi / 2
                var wedge = Path()
                wedge.move(to: CGPoint(x: cx + CGFloat(cos(a0)) * inner, y: cy + CGFloat(sin(a0)) * inner))
                wedge.addLine(to: CGPoint(x: cx + CGFloat(cos(a0)) * outer, y: cy + CGFloat(sin(a0)) * outer))
                wedge.addArc(center: CGPoint(x: cx, y: cy), radius: outer,
                             startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                wedge.addLine(to: CGPoint(x: cx + CGFloat(cos(a1)) * inner, y: cy + CGFloat(sin(a1)) * inner))
                wedge.addArc(center: CGPoint(x: cx, y: cy), radius: inner,
                             startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
                wedge.closeSubpath()
                ctx.fill(wedge, with: .color(k % 2 == 0 ? red : black))
                ctx.stroke(wedge, with: .color(gold.opacity(0.55)), lineWidth: max(0.4, r * 0.012))
            }

            // 3. Gold separator ring between wedges and rim.
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - outer, y: cy - outer, width: outer * 2, height: outer * 2)),
                       with: .color(gold), lineWidth: max(0.8, r * 0.05))

            // 4. White centre pip with a gold ring.
            let pipR = r * 0.16
            ctx.fill(Path(ellipseIn: CGRect(x: cx - pipR, y: cy - pipR, width: pipR * 2, height: pipR * 2)),
                     with: .radialGradient(Gradient(colors: [.white, Color(red: 0.86, green: 0.86, blue: 0.88)]),
                        center: CGPoint(x: cx - pipR * 0.3, y: cy - pipR * 0.3), startRadius: 0, endRadius: pipR * 1.2))
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - pipR, y: cy - pipR, width: pipR * 2, height: pipR * 2)),
                       with: .color(gold), lineWidth: max(0.6, r * 0.03))

            // 5. Roundness (limb darkening) + glossy top-left specular.
            ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(Gradient(stops: [
                .init(color: .clear, location: 0.55),
                .init(color: .black.opacity(0.45), location: 1.0)]),
                center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.52, y: cy - r * 0.80, width: r * 0.50, height: r * 0.30)),
                with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .clear]),
                    center: CGPoint(x: cx - r * 0.34, y: cy - r * 0.62), startRadius: 0, endRadius: r * 0.38))
        }
    }

    // =========================================================================
    // MARK: - Quicksilver  (Quicksilver bundle · Legendary)
    // A perfectly reflective liquid-chrome blob (T-1000): a cool steely-silver
    // MeshGradient body with a bright roving specular highlight that drifts
    // across the surface, plus a dark sky/ground reflection split and a bright
    // rim that sell the polished mercury read.  Reduce Motion freezes the
    // specular.  Clipped to a circle by the body switch caller.
    // =========================================================================
    private static let quicksilverGrid: [SIMD2<Float>] = [
        [0, 0],   [0.5, 0],   [1, 0],
        [0, 0.5], [0.5, 0.5], [1, 0.5],
        [0, 1],   [0.5, 1],   [1, 1],
    ]
    private var quicksilverCanvas: some View {
        TimelineView(.animation) { tl in
            let t = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate

            // Cool chrome palette; the interior nodes brighten/darken slightly
            // over time so the metal looks like it's quietly rippling.
            let hi   = Color(red: 0.97, green: 0.98, blue: 1.00)
            let mid  = Color(red: 0.70, green: 0.77, blue: 0.86)
            let steel = Color(red: 0.42, green: 0.49, blue: 0.60)
            let dark = Color(red: 0.10, green: 0.13, blue: 0.19)
            let ripple = Float(0.5 + 0.5 * sin(t * 0.8))
            let centerCol = Color(red: 0.78 + 0.10 * Double(ripple),
                                  green: 0.84 + 0.08 * Double(ripple),
                                  blue:  0.92 + 0.06 * Double(ripple))
            let mesh: [Color] = [
                dark, steel, hi,
                steel, centerCol, mid,
                hi,   mid,   steel,
            ]
            // The mesh nodes drift, so the reflection "flows" like liquid metal.
            let dx = Float(sin(t * 0.6)) * 0.07
            let dy = Float(cos(t * 0.5)) * 0.06
            let pts: [SIMD2<Float>] = [
                [0, 0],            [0.5 + dx, 0],         [1, 0],
                [0, 0.5 - dy],     [0.5 + dx, 0.5 + dy],  [1, 0.5 + dy],
                [0, 1],            [0.5 - dx, 1],         [1, 1],
            ]

            ZStack {
                MeshGradient(width: 3, height: 3, points: pts, colors: mesh)

                Canvas { ctx, size in
                    let w = size.width, h = size.height
                    let cx = w / 2, cy = h / 2, r = min(w, h) / 2
                    let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

                    // Sky/ground reflection split — bright up top, dark below.
                    ctx.fill(Path(ellipseIn: sphere), with: .linearGradient(
                        Gradient(stops: [.init(color: .white.opacity(0.55), location: 0.0),
                                         .init(color: .clear, location: 0.42),
                                         .init(color: .clear, location: 0.58),
                                         .init(color: dark.opacity(0.75), location: 1.0)]),
                        startPoint: CGPoint(x: cx, y: cy - r), endPoint: CGPoint(x: cx, y: cy + r)))

                    // Roving bright specular — drifts on a slow Lissajous path.
                    let sx = cx + CGFloat(cos(t * 0.9)) * r * 0.34 - r * 0.10
                    let sy = cy + CGFloat(sin(t * 0.7)) * r * 0.30 - r * 0.18
                    ctx.fill(Path(ellipseIn: CGRect(x: sx - r * 0.30, y: sy - r * 0.20,
                                                    width: r * 0.60, height: r * 0.40)),
                        with: .radialGradient(Gradient(colors: [.white.opacity(0.95), .clear]),
                            center: CGPoint(x: sx, y: sy), startRadius: 0, endRadius: r * 0.34))

                    // Bright cool rim — sells the chrome edge.
                    ctx.stroke(Path(ellipseIn: sphere.insetBy(dx: r * 0.03, dy: r * 0.03)),
                        with: .color(Color(red: 0.90, green: 0.94, blue: 1.0).opacity(0.7)),
                        lineWidth: max(0.7, r * 0.05))
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Oracle  (Oracle bundle · Legendary)
    // A smoky violet fortune crystal: deep-purple glass with swirling inner fog
    // and a tiny glowing galaxy/star core spinning at its heart.  The fog drifts
    // and the core's stars twinkle; Reduce Motion freezes both.  Clipped to a
    // circle by the body switch caller.
    // =========================================================================
    private var oracleCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2
                let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

                // Deep violet glass base.
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.40, green: 0.18, blue: 0.62),
                                      Color(red: 0.20, green: 0.06, blue: 0.36),
                                      Color(red: 0.05, green: 0.02, blue: 0.12)]),
                    center: CGPoint(x: cx - r * 0.20, y: cy - r * 0.24), startRadius: 0, endRadius: r * 1.25))

                // Swirling inner fog — drifting purple/magenta clouds.
                ctx.blendMode = .plusLighter
                let fog: [(CGFloat, CGFloat, Color)] = [
                    (-0.26, -0.14, Color(red: 0.62, green: 0.26, blue: 0.92)),
                    ( 0.24,  0.08, Color(red: 0.92, green: 0.30, blue: 0.78)),
                    ( 0.02,  0.30, Color(red: 0.46, green: 0.18, blue: 0.86)),
                    (-0.14,  0.26, Color(red: 0.78, green: 0.34, blue: 0.96)),
                ]
                for (i, f) in fog.enumerated() {
                    let bx = cx + f.0 * r + CGFloat(sin(t * 0.45 + Double(i) * 1.6)) * r * 0.10
                    let by = cy + f.1 * r + CGFloat(cos(t * 0.38 + Double(i))) * r * 0.08
                    let br = r * (0.40 + 0.08 * CGFloat(sin(t * 0.5 + Double(i))))
                    ctx.fill(Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                        with: .radialGradient(Gradient(colors: [f.2.opacity(0.42), .clear]),
                            center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: br))
                }

                // Glowing galaxy core — a small bright bloom of spiralling stars.
                let coreR = r * 0.34
                ctx.fill(Path(ellipseIn: CGRect(x: cx - coreR, y: cy - coreR, width: coreR * 2, height: coreR * 2)),
                    with: .radialGradient(Gradient(colors: [Color(red: 1.0, green: 0.92, blue: 1.0).opacity(0.95),
                                                            Color(red: 0.85, green: 0.45, blue: 1.0).opacity(0.35), .clear]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: coreR))
                for i in 0..<22 {
                    let f   = Double(i) / 22.0
                    let ang = f * 5.0 + t * 0.5 + Double(i % 2) * .pi
                    let rad = coreR * CGFloat(pow(f, 0.85))
                    let sx  = cx + CGFloat(cos(ang)) * rad
                    let sy  = cy + CGFloat(sin(ang)) * rad
                    let ss  = r * CGFloat(0.010 + (1 - f) * 0.012)
                    let tw  = reduceMotion ? 0.85 : 0.5 + 0.5 * sin(t * 3 + Double(i))
                    ctx.fill(Path(ellipseIn: CGRect(x: sx - ss, y: sy - ss, width: ss * 2, height: ss * 2)),
                             with: .color(Color(red: 1.0, green: 0.92, blue: 1.0).opacity(tw)))
                }
                ctx.blendMode = .normal

                // Glassy top-left specular.
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.50, y: cy - r * 0.80, width: r * 0.46, height: r * 0.30)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .clear]),
                        center: CGPoint(x: cx - r * 0.34, y: cy - r * 0.62), startRadius: 0, endRadius: r * 0.34))
            }
        }
    }

    // =========================================================================
    // MARK: - Geode  (Geode bundle · Epic)
    // A cracked-open agate: concentric banded amethyst rings around the rim,
    // opening to a sparkly druzy (crystalline) centre of quartz-white facets
    // that catch the light.  Mostly static, with a few twinkling crystal
    // glints.  Clipped to a circle by the body switch caller.
    // =========================================================================
    private var geodeCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2
                let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

                // Deep amethyst base.
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.58, green: 0.36, blue: 0.74),
                                      Color(red: 0.36, green: 0.16, blue: 0.52),
                                      Color(red: 0.16, green: 0.06, blue: 0.28)]),
                    center: CGPoint(x: cx - r * 0.22, y: cy - r * 0.26), startRadius: 0, endRadius: r * 1.25))

                // Banded agate rings — concentric rim bands, alternating tints.
                let bands: [(CGFloat, Color)] = [
                    (1.00, Color(red: 0.30, green: 0.14, blue: 0.44)),
                    (0.90, Color(red: 0.56, green: 0.34, blue: 0.72)),
                    (0.80, Color(red: 0.40, green: 0.20, blue: 0.58)),
                    (0.70, Color(red: 0.68, green: 0.46, blue: 0.82)),
                    (0.60, Color(red: 0.48, green: 0.26, blue: 0.66)),
                    (0.50, Color(red: 0.78, green: 0.58, blue: 0.90)),
                ]
                for (scale, col) in bands {
                    let rr = r * scale
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)),
                               with: .color(col.opacity(0.85)), lineWidth: max(1.0, r * 0.06))
                }

                // Druzy crystal core — a cluster of white quartz facets.
                let coreR = r * 0.44
                ctx.fill(Path(ellipseIn: CGRect(x: cx - coreR, y: cy - coreR, width: coreR * 2, height: coreR * 2)),
                    with: .radialGradient(Gradient(colors: [Color(red: 0.98, green: 0.95, blue: 1.0),
                                                            Color(red: 0.82, green: 0.74, blue: 0.94)]),
                        center: CGPoint(x: cx - coreR * 0.2, y: cy - coreR * 0.2), startRadius: 0, endRadius: coreR * 1.1))
                // Crystalline facets — small white diamonds packed in the core.
                let facets: [(CGFloat, CGFloat, CGFloat)] = [
                    (-0.16, -0.10, 0.12), (0.14, -0.06, 0.10), (0.02, 0.16, 0.11),
                    (-0.12, 0.14, 0.08), (0.18, 0.16, 0.07), (0.00, -0.18, 0.08),
                    (-0.22, 0.02, 0.07), (0.22, 0.00, 0.06),
                ]
                for (fx, fy, fr) in facets {
                    let gx = cx + fx * r, gy = cy + fy * r, gr = fr * r
                    var d = Path()
                    d.move(to: CGPoint(x: gx, y: gy - gr));        d.addLine(to: CGPoint(x: gx + gr * 0.62, y: gy))
                    d.addLine(to: CGPoint(x: gx, y: gy + gr));     d.addLine(to: CGPoint(x: gx - gr * 0.62, y: gy))
                    d.closeSubpath()
                    ctx.fill(d, with: .color(Color(red: 0.92, green: 0.88, blue: 1.0).opacity(0.8)))
                    ctx.stroke(d, with: .color(Color(red: 0.55, green: 0.40, blue: 0.70).opacity(0.5)),
                               lineWidth: max(0.4, r * 0.008))
                }

                // Twinkling crystal glints.
                ctx.blendMode = .plusLighter
                for (i, s) in [(-0.10, -0.08), (0.12, 0.06), (0.02, 0.18), (-0.16, 0.10)].enumerated() {
                    let tw = reduceMotion ? 0.7 : 0.5 + 0.5 * sin(t * 2.6 + Double(i) * 1.4)
                    if tw < 0.25 { continue }
                    let gx = cx + CGFloat(s.0) * r, gy = cy + CGFloat(s.1) * r, gs = r * 0.05 * CGFloat(tw)
                    ctx.fill(Path(ellipseIn: CGRect(x: gx - gs, y: gy - gs, width: gs * 2, height: gs * 2)),
                             with: .color(.white.opacity(tw)))
                }
                ctx.blendMode = .normal

                // Glassy top-left specular.
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.48, y: cy - r * 0.76, width: r * 0.44, height: r * 0.28)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(0.6), .clear]),
                        center: CGPoint(x: cx - r * 0.32, y: cy - r * 0.60), startRadius: 0, endRadius: r * 0.32))
            }
        }
    }

    // =========================================================================
    // MARK: - Lava Lamp  (Lava Lamp bundle · Epic)
    // A retro 70s lava lamp: a magenta-violet fluid field with fat warm
    // orange/coral wax blobs that slowly rise, drift, and pulse in size as if
    // merging and splitting.  A MeshGradient supplies the moody fluid; the wax
    // blobs and soft glow paint on top via Canvas with .plusLighter so they
    // bloom.  Reduce Motion freezes the rise and pulse to a still warm frame.
    // Clipped to a circle by the body switch caller.
    // =========================================================================
    private var lavaLampCanvas: some View {
        TimelineView(.animation) { tl in
            let t = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate

            // Magenta-violet fluid base — gently shifting MeshGradient so the
            // fluid itself glows and breathes behind the wax.
            let drift = Float(0.5 + 0.5 * sin(t * 0.4))
            let fluidHi  = Color(red: 0.70, green: 0.18, blue: 0.62)
            let fluidMid = Color(red: 0.44, green: 0.10, blue: 0.48)
            let fluidLo  = Color(red: 0.16, green: 0.03, blue: 0.24)
            let warmGlow = Color(red: 0.62 + 0.10 * Double(drift),
                                 green: 0.20, blue: 0.40)
            let mesh: [Color] = [
                fluidLo,  fluidMid, fluidLo,
                fluidMid, warmGlow, fluidMid,
                fluidLo,  fluidMid, fluidHi,
            ]
            let mdx = Float(sin(t * 0.5)) * 0.05
            let mdy = Float(cos(t * 0.4)) * 0.05
            let pts: [SIMD2<Float>] = [
                [0, 0],          [0.5 + mdx, 0],        [1, 0],
                [0, 0.5 - mdy],  [0.5 - mdx, 0.5 + mdy], [1, 0.5 + mdy],
                [0, 1],          [0.5 + mdx, 1],        [1, 1],
            ]

            ZStack {
                MeshGradient(width: 3, height: 3, points: pts, colors: mesh)

                Canvas { ctx, size in
                    let w = size.width, h = size.height
                    let cx = w / 2, cy = h / 2, r = min(w, h) / 2

                    // Warm wax blobs — each rises slowly, wrapping top→bottom,
                    // and pulses in radius so they appear to merge and split.
                    // (xBase, phase, baseSize, speed)
                    let blobs: [(CGFloat, Double, CGFloat, Double)] = [
                        (-0.22, 0.0, 0.30, 0.14),
                        ( 0.20, 1.9, 0.26, 0.11),
                        ( 0.02, 3.4, 0.34, 0.09),
                        (-0.10, 5.0, 0.22, 0.16),
                        ( 0.26, 2.4, 0.20, 0.13),
                    ]
                    ctx.blendMode = .plusLighter
                    for (i, b) in blobs.enumerated() {
                        // Vertical position cycles 0→1 then wraps; map to y in
                        // the sphere with a gentle horizontal sway.
                        let prog = (t * b.3 + b.1).truncatingRemainder(dividingBy: 1.0)
                        let by = cy + r * (0.85 - 1.7 * CGFloat(prog))
                        let bx = cx + b.0 * r + CGFloat(sin(t * 0.5 + Double(i) * 1.3)) * r * 0.10
                        let pulse = 0.85 + 0.30 * CGFloat(sin(t * 0.9 + Double(i) * 1.7))
                        let br = b.2 * r * pulse
                        // Two-tone wax: bright coral core fading to deep orange.
                        ctx.fill(Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                            with: .radialGradient(
                                Gradient(colors: [Color(red: 1.0, green: 0.74, blue: 0.42).opacity(0.92),
                                                  Color(red: 0.98, green: 0.42, blue: 0.24).opacity(0.55),
                                                  .clear]),
                                center: CGPoint(x: bx - br * 0.2, y: by - br * 0.2),
                                startRadius: 0, endRadius: br))
                    }
                    ctx.blendMode = .normal

                    // Soft overall warm glow from the centre — the lamp's lit body.
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                        with: .radialGradient(
                            Gradient(colors: [Color(red: 1.0, green: 0.50, blue: 0.30).opacity(0.18), .clear]),
                            center: CGPoint(x: cx, y: cy + r * 0.2), startRadius: 0, endRadius: r * 1.1))

                    // Glassy top-left specular sells the lamp glass.
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.50, y: cy - r * 0.80, width: r * 0.46, height: r * 0.30)),
                        with: .radialGradient(Gradient(colors: [.white.opacity(0.50), .clear]),
                            center: CGPoint(x: cx - r * 0.34, y: cy - r * 0.62), startRadius: 0, endRadius: r * 0.34))
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Plasma Globe  (Plasma Globe bundle · Legendary)
    // A Tesla plasma globe: a dark interior with a bright central electrode from
    // which electric magenta/cyan tendrils arc out to the glass, flickering and
    // rerouting over time.  Each tendril is a jagged poly-line whose mid-points
    // jitter; their brightness flickers and they occasionally re-aim.  Drawn
    // with .plusLighter for an additive electric glow.  Reduce Motion freezes
    // the arcs and flicker to a steady lit frame.  Clipped to a circle by the
    // body switch caller.
    // =========================================================================
    private var plasmaGlobeCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2
                let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

                // Dark glass interior with a faint violet vignette.
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.10, green: 0.06, blue: 0.22),
                                      Color(red: 0.05, green: 0.02, blue: 0.12),
                                      Color(red: 0.01, green: 0.00, blue: 0.05)]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r * 1.1))

                ctx.blendMode = .plusLighter

                // Electric tendrils arcing from the central electrode to the glass.
                let count = 7
                for i in 0..<count {
                    // Each tendril slowly sweeps and occasionally re-aims.
                    let baseAng = Double(i) / Double(count) * 2 * .pi
                    let aim = baseAng + sin(t * 0.5 + Double(i) * 2.1) * 0.6
                    let endR = r * 0.92
                    let endP = CGPoint(x: cx + CGFloat(cos(aim)) * endR,
                                       y: cy + CGFloat(sin(aim)) * endR)
                    let start = CGPoint(x: cx, y: cy)

                    // Jagged poly-line: interpolate start→end, jitter the mids.
                    let segs = 6
                    var path = Path()
                    path.move(to: start)
                    for s in 1...segs {
                        let f = CGFloat(s) / CGFloat(segs)
                        let lx = start.x + (endP.x - start.x) * f
                        let ly = start.y + (endP.y - start.y) * f
                        // Perpendicular jitter that shrinks toward the endpoint.
                        let perp: Double = aim + .pi / 2
                        let jAmp: Double = Double(r) * 0.16 * Double(f) * (1 - Double(f) + 0.25)
                        let jitArg: Double = t * 6 + Double(i) * 3 + Double(s) * 1.9
                        let jit: CGFloat = CGFloat(sin(jitArg) * jAmp)
                        let px = lx + CGFloat(cos(perp)) * jit
                        let py = ly + CGFloat(sin(perp)) * jit
                        path.addLine(to: CGPoint(x: px, y: py))
                    }
                    // Flicker — some arcs dim and brighten independently.
                    let flick = reduceMotion ? 0.8 : 0.45 + 0.55 * abs(sin(t * 4 + Double(i) * 1.3))
                    // Alternate magenta / cyan tendrils.
                    let col = (i % 2 == 0)
                        ? Color(red: 0.96, green: 0.34, blue: 0.96)
                        : Color(red: 0.42, green: 0.86, blue: 1.0)
                    ctx.stroke(path, with: .color(col.opacity(flick)), lineWidth: max(0.8, r * 0.04))
                    ctx.stroke(path, with: .color(.white.opacity(flick * 0.6)), lineWidth: max(0.4, r * 0.015))
                }

                // Bright central electrode bloom.
                let eR = r * 0.30
                ctx.fill(Path(ellipseIn: CGRect(x: cx - eR, y: cy - eR, width: eR * 2, height: eR * 2)),
                    with: .radialGradient(
                        Gradient(colors: [.white,
                                          Color(red: 0.95, green: 0.55, blue: 1.0).opacity(0.7),
                                          .clear]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: eR))
                ctx.blendMode = .normal

                // Glass rim sheen + top-left specular.
                ctx.stroke(Path(ellipseIn: sphere.insetBy(dx: r * 0.04, dy: r * 0.04)),
                    with: .color(Color(red: 0.70, green: 0.80, blue: 1.0).opacity(0.35)),
                    lineWidth: max(0.6, r * 0.03))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.50, y: cy - r * 0.82, width: r * 0.42, height: r * 0.26)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(0.40), .clear]),
                        center: CGPoint(x: cx - r * 0.34, y: cy - r * 0.66), startRadius: 0, endRadius: r * 0.30))
            }
        }
    }

    // =========================================================================
    // MARK: - Cathedral  (Cathedral bundle · Epic)
    // A stained-glass rosette window: jewel-tone panes (ruby, cobalt, emerald,
    // amber, violet) arranged in two radial rings, divided by dark leaded
    // "cames", with a small central boss.  A slow shimmer of light sweeps the
    // panes (a moving bright wedge with .plusLighter) so it reads as sunlight
    // passing through.  Reduce Motion holds the shimmer at a flattering angle.
    // Clipped to a circle by the body switch caller.
    // =========================================================================
    private var cathedralCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2

                // Jewel palette for the panes.
                let jewels: [Color] = [
                    Color(red: 0.82, green: 0.12, blue: 0.20),   // ruby
                    Color(red: 0.12, green: 0.26, blue: 0.74),   // cobalt
                    Color(red: 0.10, green: 0.56, blue: 0.34),   // emerald
                    Color(red: 0.92, green: 0.66, blue: 0.16),   // amber
                    Color(red: 0.50, green: 0.16, blue: 0.62),   // violet
                ]
                let lead = Color(red: 0.05, green: 0.04, blue: 0.06)

                // Dark leaded background fills any gaps.
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                         with: .color(lead))

                // Helper: draw one wedge pane between two angles, inner→outer radii.
                func pane(a0: Double, a1: Double, r0: CGFloat, r1: CGFloat, color: Color) {
                    var p = Path()
                    p.move(to: CGPoint(x: cx + CGFloat(cos(a0)) * r0, y: cy + CGFloat(sin(a0)) * r0))
                    p.addLine(to: CGPoint(x: cx + CGFloat(cos(a0)) * r1, y: cy + CGFloat(sin(a0)) * r1))
                    // Arc the outer edge for a rounded rosette look.
                    let steps = 5
                    for s in 1...steps {
                        let a = a0 + (a1 - a0) * Double(s) / Double(steps)
                        p.addLine(to: CGPoint(x: cx + CGFloat(cos(a)) * r1, y: cy + CGFloat(sin(a)) * r1))
                    }
                    p.addLine(to: CGPoint(x: cx + CGFloat(cos(a1)) * r0, y: cy + CGFloat(sin(a1)) * r0))
                    p.closeSubpath()
                    // Pane fill with a slight radial brighten toward the rim.
                    ctx.fill(p, with: .radialGradient(
                        Gradient(colors: [color.opacity(0.78), color]),
                        center: CGPoint(x: cx, y: cy), startRadius: r0, endRadius: r1))
                    ctx.stroke(p, with: .color(lead), lineWidth: max(1.0, r * 0.05))
                }

                // Outer ring of 12 panes.
                let outerN = 12
                let gap = 0.04
                for i in 0..<outerN {
                    let a0 = Double(i) / Double(outerN) * 2 * .pi + gap
                    let a1 = Double(i + 1) / Double(outerN) * 2 * .pi - gap
                    pane(a0: a0, a1: a1, r0: r * 0.50, r1: r * 0.98,
                         color: jewels[i % jewels.count])
                }
                // Inner ring of 6 panes, offset half a step for a woven look.
                let innerN = 6
                for i in 0..<innerN {
                    let off = Double.pi / Double(innerN)
                    let a0 = Double(i) / Double(innerN) * 2 * .pi + gap + off
                    let a1 = Double(i + 1) / Double(innerN) * 2 * .pi - gap + off
                    pane(a0: a0, a1: a1, r0: r * 0.18, r1: r * 0.50,
                         color: jewels[(i + 2) % jewels.count])
                }

                // Central boss — a small bright amber roundel.
                let bR = r * 0.18
                ctx.fill(Path(ellipseIn: CGRect(x: cx - bR, y: cy - bR, width: bR * 2, height: bR * 2)),
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 1.0, green: 0.92, blue: 0.62),
                                          Color(red: 0.86, green: 0.56, blue: 0.12)]),
                        center: CGPoint(x: cx - bR * 0.2, y: cy - bR * 0.2), startRadius: 0, endRadius: bR))
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - bR, y: cy - bR, width: bR * 2, height: bR * 2)),
                           with: .color(lead), lineWidth: max(1.0, r * 0.05))

                // Shimmer — a slowly sweeping bright wedge of "sunlight" through
                // the glass, additive so it lights whichever panes it crosses.
                let sweep = reduceMotion ? (-0.7) : t * 0.5
                ctx.blendMode = .plusLighter
                var beam = Path()
                let half = 0.55
                beam.move(to: CGPoint(x: cx, y: cy))
                let bs = 6
                for s in 0...bs {
                    let a = sweep - half + Double(s) / Double(bs) * (half * 2)
                    beam.addLine(to: CGPoint(x: cx + CGFloat(cos(a)) * r * 1.1,
                                             y: cy + CGFloat(sin(a)) * r * 1.1))
                }
                beam.closeSubpath()
                ctx.fill(beam, with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.30), .clear]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r * 1.1))
                ctx.blendMode = .normal

                // Subtle top-left glass specular.
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.52, y: cy - r * 0.82, width: r * 0.42, height: r * 0.26)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(0.28), .clear]),
                        center: CGPoint(x: cx - r * 0.36, y: cy - r * 0.66), startRadius: 0, endRadius: r * 0.30))
            }
        }
    }

    // =========================================================================
    // MARK: - Magma Core  (Magma Core bundle · Legendary)
    // A dark obsidian/basalt shell cracked by glowing molten-orange fracture
    // seams that pulse (brighten/dim) as if lava flows beneath the crust, plus
    // a few drifting embers rising off the surface.  The seams are a fixed
    // branching network whose glow is driven by a per-seam sine so the lava
    // "breathes".  Drawn with .plusLighter for the molten bloom.  Reduce Motion
    // holds the seams at a warm steady glow and stills the embers.  Clipped to
    // a circle by the body switch caller.
    // =========================================================================
    private var magmaCoreCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2
                let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

                // Dark basalt/obsidian shell with a subtle top-left sheen.
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.30, green: 0.27, blue: 0.27),
                                      Color(red: 0.12, green: 0.11, blue: 0.12),
                                      Color(red: 0.03, green: 0.03, blue: 0.04)]),
                    center: CGPoint(x: cx - r * 0.26, y: cy - r * 0.30), startRadius: 0, endRadius: r * 1.2))

                // A faint deep-orange glow from the molten heart, leaking through.
                ctx.blendMode = .plusLighter
                let heart = reduceMotion ? 0.5 : 0.45 + 0.35 * (0.5 + 0.5 * sin(t * 1.1))
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.95, green: 0.30, blue: 0.05).opacity(heart * 0.5), .clear]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r * 0.9))

                // Fracture seams — a fixed network of crooked cracks.  Each is a
                // poly-line of normalized points (unit-circle space) with its own
                // pulse phase so different seams glow at different times.
                let seams: [(phase: Double, pts: [(CGFloat, CGFloat)])] = [
                    (0.0, [(-0.78, -0.10), (-0.40, -0.04), (-0.12, -0.18), (0.18, -0.10), (0.52, -0.24), (0.82, -0.16)]),
                    (1.6, [(-0.60, 0.40), (-0.30, 0.18), (-0.04, 0.30), (0.26, 0.16), (0.50, 0.34), (0.78, 0.22)]),
                    (3.1, [(-0.10, -0.80), (-0.02, -0.40), (-0.14, -0.06), (0.04, 0.24), (-0.06, 0.56), (0.06, 0.82)]),
                    (4.4, [(0.30, -0.70), (0.18, -0.34), (0.34, -0.02), (0.20, 0.30), (0.36, 0.62)]),
                    (5.2, [(-0.34, -0.62), (-0.20, -0.28), (-0.36, 0.02), (-0.22, 0.34), (-0.34, 0.60)]),
                ]
                for seam in seams {
                    var path = Path()
                    for (j, p) in seam.pts.enumerated() {
                        let pt = CGPoint(x: cx + p.0 * r, y: cy + p.1 * r)
                        if j == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    let glow = reduceMotion ? 0.7 : 0.40 + 0.60 * (0.5 + 0.5 * sin(t * 1.6 + seam.phase))
                    // Wide soft molten under-glow.
                    ctx.stroke(path, with: .color(Color(red: 1.0, green: 0.34, blue: 0.04).opacity(glow * 0.55)),
                               lineWidth: max(2.0, r * 0.11))
                    // Brighter inner seam.
                    ctx.stroke(path, with: .color(Color(red: 1.0, green: 0.60, blue: 0.16).opacity(glow * 0.9)),
                               lineWidth: max(1.0, r * 0.05))
                    // Hot white-yellow core line.
                    ctx.stroke(path, with: .color(Color(red: 1.0, green: 0.92, blue: 0.66).opacity(glow)),
                               lineWidth: max(0.5, r * 0.02))
                }

                // Drifting embers rising off the crust.
                let embers = 7
                for i in 0..<embers {
                    let seed = Double(i) * 1.7
                    let prog = (t * 0.35 + seed).truncatingRemainder(dividingBy: 1.0)
                    let ex = cx + CGFloat(sin(seed * 2.3)) * r * 0.6 + CGFloat(sin(t * 0.8 + seed)) * r * 0.06
                    let ey = cy + r * (0.7 - 1.4 * CGFloat(prog))
                    let life = 1.0 - prog            // fade as they rise
                    let es = r * 0.035 * CGFloat(0.6 + 0.4 * sin(t * 3 + seed))
                    ctx.fill(Path(ellipseIn: CGRect(x: ex - es, y: ey - es, width: es * 2, height: es * 2)),
                        with: .radialGradient(
                            Gradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.30).opacity(life),
                                              Color(red: 1.0, green: 0.35, blue: 0.05).opacity(life * 0.5),
                                              .clear]),
                            center: CGPoint(x: ex, y: ey), startRadius: 0, endRadius: es * 1.6))
                }
                ctx.blendMode = .normal

                // Cool top-left specular on the glassy obsidian crust.
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.52, y: cy - r * 0.82, width: r * 0.40, height: r * 0.26)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(0.32), .clear]),
                        center: CGPoint(x: cx - r * 0.36, y: cy - r * 0.66), startRadius: 0, endRadius: r * 0.28))
            }
        }
    }

    // =========================================================================
    // MARK: - Hologram  (Neon City bundle · Legendary)
    // A glitchy holographic sphere: a translucent cyan/magenta orb crossed by
    // horizontal scanlines, with chromatic-aberration fringes (cyan + magenta
    // ghost rims offset to either side) and an occasional flicker/jitter that
    // shifts the whole projection a pixel or two.  Reads like a sci-fi HUD
    // projection.  Reduce Motion holds it steady (no scroll, no jitter, no
    // flicker — but the scanlines + aberration remain for the holo look).
    // Clipped to a circle by the body switch caller.
    // =========================================================================
    private var hologramCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2

                // Occasional flicker — most of the time fully present, with brief
                // dips, plus a tiny horizontal jitter of the whole projection.
                let flickRaw = sin(t * 13.0) * sin(t * 7.3 + 1.1)
                let flicker  = reduceMotion ? 1.0 : (flickRaw > 0.86 ? 0.55 : 1.0)
                let jitterX  = reduceMotion ? 0.0 : CGFloat(sin(t * 31.0)) * (flickRaw > 0.9 ? r * 0.03 : r * 0.006)
                let ox = jitterX

                let sphere = CGRect(x: cx - r + ox, y: cy - r, width: r * 2, height: r * 2)

                // Dark glassy interior so the glow reads as projected light.
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.06, green: 0.10, blue: 0.20),
                                      Color(red: 0.03, green: 0.04, blue: 0.12),
                                      Color(red: 0.01, green: 0.01, blue: 0.05)]),
                    center: CGPoint(x: cx + ox, y: cy), startRadius: 0, endRadius: r * 1.1))

                ctx.blendMode = .plusLighter

                // Chromatic aberration: cyan + magenta ghost orbs offset L/R.
                let aber = r * (0.05 + (reduceMotion ? 0.0 : 0.02 * CGFloat(sin(t * 2.0))))
                ctx.fill(Path(ellipseIn: sphere.offsetBy(dx: -aber, dy: 0)),
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 0.30, green: 0.95, blue: 1.0).opacity(0.55 * flicker), .clear]),
                        center: CGPoint(x: cx + ox - aber, y: cy), startRadius: 0, endRadius: r * 1.0))
                ctx.fill(Path(ellipseIn: sphere.offsetBy(dx: aber, dy: 0)),
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 1.0, green: 0.32, blue: 0.92).opacity(0.50 * flicker), .clear]),
                        center: CGPoint(x: cx + ox + aber, y: cy), startRadius: 0, endRadius: r * 1.0))

                // Core teal body glow.
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.55, green: 1.0, blue: 0.95).opacity(0.45 * flicker),
                                      Color(red: 0.25, green: 0.70, blue: 0.95).opacity(0.30 * flicker),
                                      .clear]),
                    center: CGPoint(x: cx + ox - r * 0.2, y: cy - r * 0.2), startRadius: 0, endRadius: r * 0.95))

                // Horizontal scanlines clipped to the sphere, scrolling slowly.
                var scan = ctx
                scan.clip(to: Path(ellipseIn: sphere))
                let lineGap = max(2.0, r * 0.10)
                let scroll  = reduceMotion ? 0.0 : CGFloat((t * 14.0).truncatingRemainder(dividingBy: Double(lineGap)))
                var y = cy - r - lineGap + scroll
                while y < cy + r + lineGap {
                    let lr = CGRect(x: cx - r + ox, y: y, width: r * 2, height: max(0.6, lineGap * 0.34))
                    scan.fill(Path(lr), with: .color(Color(red: 0.6, green: 1.0, blue: 1.0).opacity(0.16 * flicker)))
                    y += lineGap
                }

                // Crisp holographic rim — cyan inside, magenta fringe.
                ctx.stroke(Path(ellipseIn: sphere.insetBy(dx: r * 0.03, dy: r * 0.03)),
                    with: .color(Color(red: 0.40, green: 0.98, blue: 1.0).opacity(0.55 * flicker)),
                    lineWidth: max(0.8, r * 0.035))

                ctx.blendMode = .normal

                // Top-left specular sheen.
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.52 + ox, y: cy - r * 0.82, width: r * 0.40, height: r * 0.24)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(0.35 * flicker), .clear]),
                        center: CGPoint(x: cx - r * 0.36 + ox, y: cy - r * 0.66), startRadius: 0, endRadius: r * 0.28))
            }
        }
    }

    // =========================================================================
    // MARK: - Clockwork  (Clockwork bundle · Legendary)
    // A warm brass/copper body with several interlocking gears that mesh and
    // rotate slowly — adjacent gears spin in opposite directions so they read
    // as actually meshing.  Rivets ring the rim and a polished top-left sheen
    // gives the metal a buffed shine; faint patina darkens the lower body.
    // Reduce Motion freezes the gears at a flattering angle.  Clipped to a
    // circle by the body switch caller.
    // =========================================================================
    private var clockworkCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t  = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2, r = min(w, h) / 2
                let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

                // Warm brass body with a top-left sheen, patina toward the base.
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.95, green: 0.80, blue: 0.46),
                                      Color(red: 0.78, green: 0.54, blue: 0.22),
                                      Color(red: 0.46, green: 0.30, blue: 0.12),
                                      Color(red: 0.20, green: 0.13, blue: 0.07)]),
                    center: CGPoint(x: cx - r * 0.28, y: cy - r * 0.32), startRadius: 0, endRadius: r * 1.3))

                // Helper: draw one gear (toothed disc) centred at (gx,gy).
                func gear(gx: CGFloat, gy: CGFloat, radius: CGFloat, teeth: Int,
                          angle: Double, body: Color, tooth: Color) {
                    var p = Path()
                    let inner = radius * 0.78
                    let outer = radius
                    let n = teeth * 2
                    for k in 0..<n {
                        let a = angle + Double(k) / Double(n) * 2 * .pi
                        let rad = (k % 2 == 0) ? outer : inner
                        let pt = CGPoint(x: gx + CGFloat(cos(a)) * rad, y: gy + CGFloat(sin(a)) * rad)
                        if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    p.closeSubpath()
                    // Toothed rim.
                    ctx.fill(p, with: .radialGradient(
                        Gradient(colors: [tooth, body, body.opacity(0.85)]),
                        center: CGPoint(x: gx - radius * 0.3, y: gy - radius * 0.3),
                        startRadius: 0, endRadius: radius * 1.2))
                    ctx.stroke(p, with: .color(.black.opacity(0.35)), lineWidth: max(0.5, radius * 0.04))
                    // Hub ring + centre hole.
                    let hubR = radius * 0.42
                    ctx.fill(Path(ellipseIn: CGRect(x: gx - hubR, y: gy - hubR, width: hubR * 2, height: hubR * 2)),
                        with: .color(body.opacity(0.9)))
                    ctx.stroke(Path(ellipseIn: CGRect(x: gx - hubR, y: gy - hubR, width: hubR * 2, height: hubR * 2)),
                        with: .color(.black.opacity(0.30)), lineWidth: max(0.5, radius * 0.03))
                    let holeR = radius * 0.16
                    ctx.fill(Path(ellipseIn: CGRect(x: gx - holeR, y: gy - holeR, width: holeR * 2, height: holeR * 2)),
                        with: .color(Color(red: 0.16, green: 0.10, blue: 0.05)))
                    // A few spokes for mechanical detail.
                    for s in 0..<4 {
                        let sa = angle + Double(s) / 4.0 * 2 * .pi
                        var spoke = Path()
                        spoke.move(to: CGPoint(x: gx + CGFloat(cos(sa)) * holeR, y: gy + CGFloat(sin(sa)) * holeR))
                        spoke.addLine(to: CGPoint(x: gx + CGFloat(cos(sa)) * hubR, y: gy + CGFloat(sin(sa)) * hubR))
                        ctx.stroke(spoke, with: .color(.black.opacity(0.22)), lineWidth: max(0.5, radius * 0.05))
                    }
                }

                let brass  = Color(red: 0.80, green: 0.58, blue: 0.26)
                let copper = Color(red: 0.74, green: 0.44, blue: 0.22)
                let bright = Color(red: 0.98, green: 0.84, blue: 0.50)

                // Big central gear + two smaller meshing gears spinning opposite.
                let spin = t * 0.6
                gear(gx: cx, gy: cy, radius: r * 0.52, teeth: 12, angle: spin,
                     body: brass, tooth: bright)
                gear(gx: cx + r * 0.58, gy: cy - r * 0.40, radius: r * 0.30, teeth: 9,
                     angle: -spin * 1.4 + 0.3, body: copper, tooth: bright)
                gear(gx: cx - r * 0.52, gy: cy + r * 0.50, radius: r * 0.26, teeth: 8,
                     angle: -spin * 1.6 + 0.8, body: copper, tooth: bright)

                // Rivets around the rim.
                let rivets = 16
                for i in 0..<rivets {
                    let a = Double(i) / Double(rivets) * 2 * .pi
                    let rx = cx + CGFloat(cos(a)) * r * 0.90
                    let ry = cy + CGFloat(sin(a)) * r * 0.90
                    let rr = r * 0.05
                    ctx.fill(Path(ellipseIn: CGRect(x: rx - rr, y: ry - rr, width: rr * 2, height: rr * 2)),
                        with: .radialGradient(Gradient(colors: [bright, copper.opacity(0.8)]),
                            center: CGPoint(x: rx - rr * 0.3, y: ry - rr * 0.3), startRadius: 0, endRadius: rr))
                }

                // Polished top-left sheen.
                ctx.blendMode = .plusLighter
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.55, y: cy - r * 0.85, width: r * 0.46, height: r * 0.28)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(0.40), .clear]),
                        center: CGPoint(x: cx - r * 0.38, y: cy - r * 0.68), startRadius: 0, endRadius: r * 0.30))
                ctx.blendMode = .normal
            }
        }
    }

    // =========================================================================
    // MARK: - Beach Ball  (Summer 2026 seasonal exclusive)
    // Classic glossy inflatable beach ball with 6 alternating wedge panels:
    // red · yellow · blue · red · yellow · blue, radiating from the centre.
    // A radial edge-darkening overlay + upper-left specular highlight sell
    // the inflated 3-D read.  Clipped to a circle by the body switch caller.
    // =========================================================================
    private var beachBallCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // ── 1. Base white fill ──────────────────────────────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .color(.white))

            // ── 2. Six coloured wedge panels ────────────────────────────
            // Each wedge spans 60°.  The oversized radius (r * 1.05) lets
            // them fill the circle cleanly; clipShape(Circle()) trims any
            // overflow.
            let wedgeColors: [Color] = [
                Color(red: 0.90, green: 0.18, blue: 0.22),  // red
                Color(red: 0.96, green: 0.84, blue: 0.10),  // yellow
                Color(red: 0.22, green: 0.54, blue: 0.92),  // blue
                Color(red: 0.90, green: 0.18, blue: 0.22),  // red
                Color(red: 0.96, green: 0.84, blue: 0.10),  // yellow
                Color(red: 0.22, green: 0.54, blue: 0.92),  // blue
            ]
            let wedgeAngle = CGFloat.pi * 2 / CGFloat(wedgeColors.count)
            for (i, color) in wedgeColors.enumerated() {
                let startAngle = CGFloat(i) * wedgeAngle - .pi / 2
                let endAngle   = startAngle + wedgeAngle
                var wedge = Path()
                wedge.move(to: CGPoint(x: cx, y: cy))
                wedge.addArc(center: CGPoint(x: cx, y: cy),
                             radius: r * 1.05,
                             startAngle: .radians(Double(startAngle)),
                             endAngle:   .radians(Double(endAngle)),
                             clockwise:  false)
                wedge.closeSubpath()
                ctx.fill(wedge, with: .color(color))
            }

            // ── 3. Thin white seam lines between panels ─────────────────
            for i in 0..<6 {
                let angle = CGFloat(i) * wedgeAngle - .pi / 2
                var seam = Path()
                seam.move(to: CGPoint(x: cx, y: cy))
                seam.addLine(to: CGPoint(x: cx + cos(angle) * r * 1.05,
                                         y: cy + sin(angle) * r * 1.05))
                ctx.stroke(seam,
                           with: .color(Color.white.opacity(0.72)),
                           style: StrokeStyle(lineWidth: max(1, r * 0.035),
                                              lineCap: .round))
            }

            // ── 4. Spherical shading — edge-darkening inflated look ──────
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.00), location: 0.00),
                        .init(color: .white.opacity(0.00), location: 0.50),
                        .init(color: .black.opacity(0.28), location: 1.00),
                    ]),
                    center: CGPoint(x: cx, y: cy),
                    startRadius: 0, endRadius: r * 1.05))

            // ── 5. Specular highlight — upper-left gloss crescent ────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: w * 0.10, y: h * 0.08,
                                       width: w * 0.32, height: h * 0.24)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.70), .clear]),
                    center: CGPoint(x: w * 0.22, y: h * 0.16),
                    startRadius: 0, endRadius: r * 0.40))
        }
    }

    // =========================================================================
    // MARK: - Pumpkin  (Halloween 2026 seasonal exclusive · Legendary)
    // Orange Jack-o'-lantern with five vertical rib lines, a warm amber
    // inner glow, triangular eyes, a jagged three-toothed grin, and a
    // small curved stem.  Animated: the inner candle flickers on two
    // incommensurate clocks, the carved eyes and grin breathe with it, and a
    // few embers drift up past the face.  Under Reduce Motion the candle
    // holds steady and the embers are gone — exactly the original static
    // carving.  Clipped to a circle by the body switch caller.
    // =========================================================================
    private var pumpkinCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                // Candle flicker — 1.0 means "original steady glow", so the
                // Reduce Motion fallback reproduces the static skin exactly.
                let flick: Double = reduceMotion ? 1.0 : 0.84 + 0.11 * sin(t * 6.8) + 0.05 * sin(t * 11.3 + 1.7)
                // Carve-glow strength for the eyes/grin (additive layer only).
                let carve: Double = reduceMotion ? 0.0 : 0.22 + 0.55 * (flick - 0.68)

                let w  = size.width
                let h  = size.height
                let cx = w / 2
                let cy = h / 2
                let r  = min(w, h) / 2

                // ── 1. Orange radial gradient sphere base ───────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 1.00, green: 0.72, blue: 0.22), location: 0.00),
                            .init(color: Color(red: 0.95, green: 0.44, blue: 0.08), location: 0.48),
                            .init(color: Color(red: 0.62, green: 0.22, blue: 0.04), location: 0.82),
                            .init(color: Color(red: 0.32, green: 0.10, blue: 0.01), location: 1.00),
                        ]),
                        center: CGPoint(x: cx - r * 0.18, y: cy - r * 0.22),
                        startRadius: 0, endRadius: r * 1.28))

                // ── 2. Warm amber inner glow — flickering candle inside ──────
                // Opacity and reach ride the flicker; at flick == 1.0 the
                // numbers match the original static glow (0.52 / 0.22 / 0.72r).
                let glowReach: CGFloat = r * (0.56 + 0.16 * CGFloat(flick))
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.58, y: cy - r * 0.22,
                                           width: r * 1.16, height: r * 0.88)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 1.00, green: 0.88, blue: 0.28).opacity(0.52 * flick), location: 0.00),
                            .init(color: Color(red: 1.00, green: 0.68, blue: 0.08).opacity(0.22 * flick), location: 0.55),
                            .init(color: .clear, location: 1.00),
                        ]),
                        center: CGPoint(x: cx, y: cy + r * 0.18),
                        startRadius: 0, endRadius: glowReach))

                // ── 3. Five rib lines — fan from north pole to south pole ────
                let ribColor = Color(red: 0.24, green: 0.09, blue: 0.01)
                let ribW     = max(1, r * 0.052)
                let ribStyle = StrokeStyle(lineWidth: ribW, lineCap: .round)

                // Centre rib — straight vertical
                var centre = Path()
                centre.move(to: CGPoint(x: cx, y: cy - r * 0.88))
                centre.addLine(to: CGPoint(x: cx, y: cy + r * 0.88))
                ctx.stroke(centre, with: .color(ribColor.opacity(0.68)), style: ribStyle)

                // Inner pair — bow ±r*0.44 outward
                for sign in [-1, 1] as [CGFloat] {
                    var rib = Path()
                    rib.move(to: CGPoint(x: cx, y: cy - r * 0.86))
                    rib.addQuadCurve(to: CGPoint(x: cx, y: cy + r * 0.86),
                                     control: CGPoint(x: cx + sign * r * 0.44, y: cy))
                    ctx.stroke(rib, with: .color(ribColor.opacity(0.62)), style: ribStyle)
                }

                // Outer pair — bow ±r*0.82 outward
                for sign in [-1, 1] as [CGFloat] {
                    var rib = Path()
                    rib.move(to: CGPoint(x: cx, y: cy - r * 0.78))
                    rib.addQuadCurve(to: CGPoint(x: cx, y: cy + r * 0.78),
                                     control: CGPoint(x: cx + sign * r * 0.82, y: cy))
                    ctx.stroke(rib, with: .color(ribColor.opacity(0.50)), style: ribStyle)
                }

                // ── 4. Stem — small curved stalk at north pole ───────────────
                var stemPath = Path()
                stemPath.move(to: CGPoint(x: cx + r * 0.04, y: cy - r * 0.82))
                stemPath.addQuadCurve(
                    to:      CGPoint(x: cx + r * 0.14, y: cy - r * 0.96),
                    control: CGPoint(x: cx + r * 0.16, y: cy - r * 0.86))
                ctx.stroke(stemPath,
                           with: .color(Color(red: 0.16, green: 0.34, blue: 0.10)),
                           style: StrokeStyle(lineWidth: max(1.5, r * 0.10), lineCap: .round))

                // ── 5. Two triangular eyes — downward-pointing ───────────────
                // The dark cutout stays; a candle-glow gradient breathes over
                // it in step 5b so the carve looks lit from within.
                let candle = Color(red: 1.00, green: 0.78, blue: 0.20)
                let faceColor = Color(red: 0.08, green: 0.03, blue: 0.00)
                let eyeW  = r * 0.22
                let eyeH  = r * 0.26
                let eyeTop = cy - r * 0.30

                for ex in [cx - r * 0.30, cx + r * 0.30] as [CGFloat] {
                    var eye = Path()
                    eye.move(to: CGPoint(x: ex - eyeW / 2, y: eyeTop))
                    eye.addLine(to: CGPoint(x: ex + eyeW / 2, y: eyeTop))
                    eye.addLine(to: CGPoint(x: ex,            y: eyeTop + eyeH))
                    eye.closeSubpath()
                    ctx.fill(eye, with: .color(faceColor))
                    // 5b. Flickering candlelight inside the socket (additive;
                    //     zero-opacity — i.e. invisible — under Reduce Motion).
                    if carve > 0 {
                        ctx.fill(eye, with: .radialGradient(
                            Gradient(colors: [candle.opacity(carve), .clear]),
                            center: CGPoint(x: ex, y: eyeTop + eyeH * 0.55),
                            startRadius: 0, endRadius: eyeH * 1.1))
                    }
                }

                // ── 6. Jagged grin — 3 orange teeth visible at bottom ────────
                // The dark filled grin shape has three triangular notches cut
                // from its lower edge, exposing the orange sphere beneath them.
                // This creates 3 orange triangular teeth rising from the bottom
                // of the grin opening — the classic carved Jack-o'-lantern look.
                let mouthL    = cx - r * 0.44
                let mouthR    = cx + r * 0.44
                let mouthT    = cy + r * 0.08
                let mouthB    = cy + r * 0.38
                let mH2       = mouthB - mouthT
                let seg       = (mouthR - mouthL) / 7.0
                let toothTopY = mouthT + mH2 * 0.30  // tips of orange notches

                var grin = Path()
                grin.move(to: CGPoint(x: mouthL, y: mouthT))
                grin.addLine(to: CGPoint(x: mouthR,              y: mouthT))
                grin.addLine(to: CGPoint(x: mouthR,              y: mouthB))
                grin.addLine(to: CGPoint(x: mouthL + seg * 6,    y: mouthB))
                grin.addLine(to: CGPoint(x: mouthL + seg * 5.5,  y: toothTopY))
                grin.addLine(to: CGPoint(x: mouthL + seg * 5,    y: mouthB))
                grin.addLine(to: CGPoint(x: mouthL + seg * 4,    y: mouthB))
                grin.addLine(to: CGPoint(x: mouthL + seg * 3.5,  y: toothTopY))
                grin.addLine(to: CGPoint(x: mouthL + seg * 3,    y: mouthB))
                grin.addLine(to: CGPoint(x: mouthL + seg * 2,    y: mouthB))
                grin.addLine(to: CGPoint(x: mouthL + seg * 1.5,  y: toothTopY))
                grin.addLine(to: CGPoint(x: mouthL + seg * 1,    y: mouthB))
                grin.addLine(to: CGPoint(x: mouthL,              y: mouthB))
                grin.closeSubpath()
                ctx.fill(grin, with: .color(faceColor))
                // 6b. Candlelight spilling through the grin (additive layer).
                if carve > 0 {
                    let grinGlowR: CGFloat = (mouthR - mouthL) * 0.55
                    ctx.fill(grin, with: .radialGradient(
                        Gradient(colors: [candle.opacity(carve), .clear]),
                        center: CGPoint(x: cx, y: (mouthT + mouthB) / 2),
                        startRadius: 0, endRadius: grinGlowR))
                }

                // ── 7. Drifting embers — a few sparks rise past the face ─────
                //     (skipped entirely under Reduce Motion → static fallback)
                if !reduceMotion {
                    let ember = Color(red: 1.00, green: 0.62, blue: 0.10)
                    for i in 0..<6 {
                        let seed: Double  = Double(i) * 0.61 + 0.17
                        let speed: Double = 0.16 + 0.05 * Double(i % 3)
                        let cycle: Double = (t * speed + seed).truncatingRemainder(dividingBy: 1.0)
                        let sway: Double  = sin(t * 1.4 + seed * 6.0)
                        let drift: CGFloat = CGFloat(seed.truncatingRemainder(dividingBy: 0.5) - 0.25)
                        let px: CGFloat = cx + drift * r * 1.4 + CGFloat(sway) * r * 0.07
                        let py: CGFloat = cy + r * 0.42 - CGFloat(cycle) * r * 1.15
                        // Fade in just off the grin, fade out toward the crown.
                        let fade: Double = 0.75 * (1.0 - cycle) * min(1.0, cycle * 6.0)
                        let es: CGFloat = r * (0.028 + 0.014 * CGFloat(i % 2))
                        ctx.fill(Path(ellipseIn: CGRect(x: px - es, y: py - es,
                                                        width: es * 2, height: es * 2)),
                                 with: .color(ember.opacity(fade)))
                    }
                }

                // ── 8. Specular highlight ────────────────────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.54, y: cy - r * 0.66,
                                           width: r * 0.36, height: r * 0.24)),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.48), .clear]),
                        center: CGPoint(x: cx - r * 0.38, y: cy - r * 0.56),
                        startRadius: 0, endRadius: r * 0.28))
            }
        }
    }

    // =========================================================================
    // MARK: - Ornament  (Winter 2026 seasonal exclusive)
    // Mirror-glossy deep crimson Christmas ornament.  The very large specular
    // highlight is the signature element — it's substantially bigger and
    // brighter than other skins to sell the mirror-glass quality.  Gold
    // metallic cap at north pole, thin equatorial gold stripe, small caustic
    // secondary reflection at lower-right.
    // Clipped to a circle by the body switch caller.
    // =========================================================================
    private var ornamentCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // ── 1. Deep crimson sphere — very high contrast ──────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.98, green: 0.58, blue: 0.58), location: 0.00),
                        .init(color: Color(red: 0.88, green: 0.06, blue: 0.14), location: 0.30),
                        .init(color: Color(red: 0.50, green: 0.02, blue: 0.08), location: 0.65),
                        .init(color: Color(red: 0.10, green: 0.00, blue: 0.02), location: 1.00),
                    ]),
                    center: CGPoint(x: cx - r * 0.22, y: cy - r * 0.28),
                    startRadius: 0, endRadius: r * 1.05))

            // ── 2. Thin gold equatorial stripe ───────────────────────────
            let stripeRx   = r * 0.95
            let stripeRy   = r * 0.13
            let stripeRect = CGRect(x: cx - stripeRx, y: cy - stripeRy,
                                     width: stripeRx * 2, height: stripeRy * 2)
            ctx.stroke(
                Path(ellipseIn: stripeRect),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.72, green: 0.56, blue: 0.18), location: 0.00),
                        .init(color: Color(red: 1.00, green: 0.88, blue: 0.50), location: 0.40),
                        .init(color: Color(red: 0.80, green: 0.62, blue: 0.22), location: 0.75),
                        .init(color: Color(red: 0.48, green: 0.36, blue: 0.08), location: 1.00),
                    ]),
                    startPoint: CGPoint(x: cx - stripeRx, y: cy),
                    endPoint:   CGPoint(x: cx + stripeRx, y: cy)),
                lineWidth: max(1.5, r * 0.058))

            // ── 3. Gold metallic cap at north pole ───────────────────────
            let capRx   = r * 0.19
            let capRy   = r * 0.11
            let capCy   = cy - r * 0.82
            let capRect = CGRect(x: cx - capRx, y: capCy - capRy,
                                  width: capRx * 2, height: capRy * 2)
            ctx.fill(
                Path(ellipseIn: capRect),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 1.00, green: 0.94, blue: 0.60), location: 0.00),
                        .init(color: Color(red: 0.78, green: 0.60, blue: 0.20), location: 0.55),
                        .init(color: Color(red: 0.44, green: 0.30, blue: 0.08), location: 1.00),
                    ]),
                    startPoint: CGPoint(x: cx, y: capCy - capRy),
                    endPoint:   CGPoint(x: cx, y: capCy + capRy)))
            ctx.stroke(
                Path(ellipseIn: capRect),
                with: .color(Color(red: 0.22, green: 0.14, blue: 0.03).opacity(0.75)),
                lineWidth: max(0.5, r * 0.022))

            // ── 4. Very large specular highlight — mirror-glass signature ─
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r * 0.64, y: cy - r * 0.76,
                                       width: r * 0.72, height: r * 0.50)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.94), location: 0.00),
                        .init(color: .white.opacity(0.62), location: 0.30),
                        .init(color: .white.opacity(0.00), location: 1.00),
                    ]),
                    center: CGPoint(x: cx - r * 0.30, y: cy - r * 0.55),
                    startRadius: 0, endRadius: r * 0.52))

            // ── 5. Small secondary caustic reflection — lower-right ───────
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx + r * 0.26, y: cy + r * 0.30,
                                       width: r * 0.22, height: r * 0.14)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.38), .clear]),
                    center: CGPoint(x: cx + r * 0.36, y: cy + r * 0.36),
                    startRadius: 0, endRadius: r * 0.14))
        }
    }

    // =========================================================================
    // MARK: - Heartstone  (Valentine's Day 2027 seasonal exclusive)
    // Deep fuchsia sphere with a gold embossed heart inlaid at centre.
    // The heart is built from four cubic Bézier curves meeting at a bottom
    // tip point — the classic cardioid construction.  A large upper-left
    // specular sells the spherical gloss.
    // Clipped to a circle by the body switch caller.
    // =========================================================================
    private var heartstoneCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // ── 1. Deep fuchsia radial gradient sphere ───────────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.98, green: 0.72, blue: 0.82), location: 0.00),
                        .init(color: Color(red: 0.92, green: 0.22, blue: 0.56), location: 0.38),
                        .init(color: Color(red: 0.62, green: 0.06, blue: 0.30), location: 0.75),
                        .init(color: Color(red: 0.28, green: 0.02, blue: 0.12), location: 1.00),
                    ]),
                    center: CGPoint(x: cx - r * 0.22, y: cy - r * 0.28),
                    startRadius: 0, endRadius: r * 1.05))

            // ── 2. Gold embossed heart — 4 cubic Bézier construction ─────
            // Scale factor and centre of the heart motif.
            let pS  = r * 0.28
            let hCx = cx
            let hCy = cy + r * 0.04

            // Tip (bottom of heart) and the four quadrant points in
            // normalised coordinates (multiplied by pS and offset by hCx/hCy).
            func hp(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
                CGPoint(x: hCx + nx * pS, y: hCy + ny * pS)
            }

            var heart = Path()
            // Start at bottom tip
            heart.move(to: hp(0.0,  0.90))
            // Bottom-left lobe sweep
            heart.addCurve(to:        hp(-1.00, -0.30),
                           control1:  hp(-0.10,  1.00),
                           control2:  hp(-1.20,  0.30))
            // Top-left crossing to top-centre
            heart.addCurve(to:        hp( 0.00, -0.80),
                           control1:  hp(-1.20, -0.90),
                           control2:  hp(-0.40, -1.10))
            // Top-right to right lobe
            heart.addCurve(to:        hp( 1.00, -0.30),
                           control1:  hp( 0.40, -1.10),
                           control2:  hp( 1.20, -0.90))
            // Bottom-right lobe back to tip
            heart.addCurve(to:        hp( 0.00,  0.90),
                           control1:  hp( 1.20,  0.30),
                           control2:  hp( 0.10,  1.00))
            heart.closeSubpath()

            ctx.fill(heart,
                     with: .color(Color(red: 0.92, green: 0.76, blue: 0.28)))
            ctx.stroke(heart,
                       with: .color(Color(red: 0.55, green: 0.38, blue: 0.08)),
                       lineWidth: max(0.8, r * 0.028))

            // ── 3. Large specular highlight crescent (upper-left) ────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r * 0.58, y: cy - r * 0.74,
                                       width: r * 0.46, height: r * 0.30)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.68), .clear]),
                    center: CGPoint(x: cx - r * 0.38, y: cy - r * 0.62),
                    startRadius: 0, endRadius: r * 0.32))
        }
    }

    // =========================================================================
    // MARK: - Shamrock  (St. Patrick's Day 2027 seasonal exclusive)
    // Vivid forest-green sphere with a white four-leaf clover — four
    // overlapping petal circles arranged at N/E/S/W with a small centre
    // circle unifying them.  Gold outline rings the petals.  A curved gold
    // stem descends from the base of the clover.
    // Clipped to a circle by the body switch caller.
    // =========================================================================
    private var shamrockCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // ── 1. Forest-green radial gradient sphere ───────────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.72, green: 0.98, blue: 0.52), location: 0.00),
                        .init(color: Color(red: 0.20, green: 0.72, blue: 0.22), location: 0.42),
                        .init(color: Color(red: 0.06, green: 0.42, blue: 0.10), location: 0.80),
                        .init(color: Color(red: 0.02, green: 0.18, blue: 0.04), location: 1.00),
                    ]),
                    center: CGPoint(x: cx - r * 0.20, y: cy - r * 0.26),
                    startRadius: 0, endRadius: r * 1.30))

            // ── 2. Four-leaf clover ──────────────────────────────────────
            let cloverCX = cx
            let cloverCY = cy - r * 0.06
            let petalR   = r * 0.195
            let petalD   = r * 0.155   // centre-to-petal-centre offset
            let goldStroke = Color(red: 0.88, green: 0.74, blue: 0.24)
            let strokeW    = max(0.6, r * 0.022)

            // Cardinal offsets: N, E, S, W
            let offsets: [(CGFloat, CGFloat)] = [(0, -1), (1, 0), (0, 1), (-1, 0)]
            for (dx, dy) in offsets {
                let pcx = cloverCX + dx * petalD
                let pcy = cloverCY + dy * petalD
                let pRect = CGRect(x: pcx - petalR, y: pcy - petalR,
                                   width: petalR * 2, height: petalR * 2)
                ctx.fill(Path(ellipseIn: pRect), with: .color(.white))
                ctx.stroke(Path(ellipseIn: pRect),
                           with: .color(goldStroke), lineWidth: strokeW)
            }

            // Small centre circle to unify the four petals
            let ctrR = petalR * 0.35
            ctx.fill(Path(ellipseIn: CGRect(x: cloverCX - ctrR, y: cloverCY - ctrR,
                                            width: ctrR * 2, height: ctrR * 2)),
                     with: .color(.white))

            // ── 3. Gold curved stem ──────────────────────────────────────
            let stemBase = cloverCY + petalD + petalR * 0.6
            var stem = Path()
            stem.move(to:    CGPoint(x: cloverCX + r * 0.02, y: stemBase))
            stem.addQuadCurve(
                to:      CGPoint(x: cloverCX + r * 0.08, y: stemBase + petalR * 1.5),
                control: CGPoint(x: cloverCX - r * 0.02, y: stemBase + petalR * 1.1))
            ctx.stroke(stem,
                       with: .color(Color(red: 0.88, green: 0.72, blue: 0.22)),
                       style: StrokeStyle(lineWidth: max(1.5, r * 0.075), lineCap: .round))

            // ── 4. Specular highlight crescent ───────────────────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r * 0.52, y: cy - r * 0.70,
                                       width: r * 0.38, height: r * 0.26)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.52), .clear]),
                    center: CGPoint(x: cx - r * 0.35, y: cy - r * 0.60),
                    startRadius: 0, endRadius: r * 0.28))
        }
    }

    // =========================================================================
    // MARK: - Confetti  (New Year's 2027 seasonal exclusive)
    // Champagne-gold sphere scattered with 18 deterministic multicolor
    // confetti rectangles, each individually rotated via a manual 2-D
    // rotation matrix (SwiftUI Canvas has no transform API).
    // Clipped to a circle by the body switch caller.
    // =========================================================================
    private var confettiCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // ── 1. Champagne-gold radial gradient sphere ─────────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 1.00, green: 0.96, blue: 0.80), location: 0.00),
                        .init(color: Color(red: 0.94, green: 0.78, blue: 0.32), location: 0.40),
                        .init(color: Color(red: 0.70, green: 0.52, blue: 0.14), location: 0.78),
                        .init(color: Color(red: 0.36, green: 0.24, blue: 0.04), location: 1.00),
                    ]),
                    center: CGPoint(x: cx - r * 0.18, y: cy - r * 0.22),
                    startRadius: 0, endRadius: r * 1.28))

            // ── 2. 18 deterministic rotated confetti rectangles ──────────
            let pieceW = max(2.0, r * 0.075)
            let pieceH = max(1.5, r * 0.045)
            let confettiColors: [Color] = [
                Color(red: 0.92, green: 0.12, blue: 0.18),   // red
                Color(red: 0.18, green: 0.42, blue: 0.92),   // cobalt
                Color(red: 0.12, green: 0.76, blue: 0.30),   // emerald
                Color(red: 0.96, green: 0.22, blue: 0.80),   // magenta
                Color(red: 0.56, green: 0.16, blue: 0.94),   // violet
                Color(red: 1.00, green: 1.00, blue: 1.00),   // white
            ]
            // (normX, normY, angleDeg, colorIdx) — positions in [0,1] space
            let pieces: [(CGFloat, CGFloat, CGFloat, Int)] = [
                (0.32, 0.18,  25, 0), (0.55, 0.22, -35, 1), (0.44, 0.32,  55, 2),
                (0.68, 0.30, -20, 3), (0.25, 0.42,  45, 4), (0.58, 0.42,  70, 5),
                (0.38, 0.55, -50, 0), (0.72, 0.50,  15, 1), (0.28, 0.60,  60, 2),
                (0.50, 0.62, -40, 3), (0.70, 0.68,  30, 4), (0.22, 0.28, -60, 5),
                (0.42, 0.72,  45, 0), (0.62, 0.78, -25, 1), (0.35, 0.78,  65, 2),
                (0.74, 0.38, -45, 3), (0.18, 0.52,  20, 4), (0.56, 0.14, -55, 5),
            ]

            for (nx, ny, angleDeg, colorIdx) in pieces {
                let px = cx - r + nx * r * 2
                let py = cy - r + ny * r * 2
                let dx = px - cx
                let dy = py - cy
                // Skip pieces that fall outside the sphere silhouette
                if sqrt(dx * dx + dy * dy) > r * 0.86 { continue }

                // Manual 2-D rotation matrix: avoids the unavailable ctx.transform
                let angleRad = angleDeg * CGFloat.pi / 180
                let cosA     = cos(angleRad)
                let sinA     = sin(angleRad)

                // Half-extents of the rectangle in local space
                let lx = pieceW / 2
                let ly = pieceH / 2

                // Rotate all four corners around (px, py)
                func rotate(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
                    CGPoint(x: px + lx * cosA - ly * sinA,
                            y: py + lx * sinA + ly * cosA)
                }

                var piece = Path()
                piece.move(to:    rotate(-lx, -ly))
                piece.addLine(to: rotate( lx, -ly))
                piece.addLine(to: rotate( lx,  ly))
                piece.addLine(to: rotate(-lx,  ly))
                piece.closeSubpath()

                ctx.fill(piece, with: .color(confettiColors[colorIdx]))
            }

            // ── 3. Bright specular highlight (upper-left) ────────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r * 0.56, y: cy - r * 0.72,
                                       width: r * 0.48, height: r * 0.32)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.80), location: 0.00),
                        .init(color: .white.opacity(0.42), location: 0.40),
                        .init(color: .clear,               location: 1.00),
                    ]),
                    center: CGPoint(x: cx - r * 0.36, y: cy - r * 0.60),
                    startRadius: 0, endRadius: r * 0.36))
        }
    }

    // =========================================================================
    // MARK: - Speckled Egg  (Spring 2027 seasonal exclusive)
    // Robin's-egg blue sphere with 16 deterministic dark oval speckles
    // scattered across its face.  Each oval is slightly elongated (width >
    // height) and slightly random in size via a per-speckle sizeScale factor.
    // A bright white specular crescent at upper-left anchors the lighting.
    // Clipped to a circle by the body switch caller.
    // =========================================================================
    private var speckledEggCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // ── 1. Robin's-egg blue radial gradient sphere ───────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.82, green: 0.96, blue: 0.98), location: 0.00),
                        .init(color: Color(red: 0.46, green: 0.82, blue: 0.90), location: 0.42),
                        .init(color: Color(red: 0.22, green: 0.60, blue: 0.76), location: 0.80),
                        .init(color: Color(red: 0.08, green: 0.28, blue: 0.44), location: 1.00),
                    ]),
                    center: CGPoint(x: cx - r * 0.20, y: cy - r * 0.28),
                    startRadius: 0, endRadius: r * 1.25))

            // ── 2. 16 deterministic dark oval speckles ───────────────────
            let baseSpeckleR = r * 0.040
            let speckleColor = Color(red: 0.10, green: 0.28, blue: 0.38).opacity(0.80)

            // (normX, normY, sizeScale) — positions in [0,1] space
            let speckles: [(CGFloat, CGFloat, CGFloat)] = [
                (0.42, 0.22, 0.90), (0.62, 0.20, 1.10), (0.36, 0.36, 0.75),
                (0.58, 0.38, 0.95), (0.72, 0.34, 0.80), (0.28, 0.44, 1.00),
                (0.50, 0.46, 0.70), (0.66, 0.52, 1.05), (0.36, 0.58, 0.85),
                (0.52, 0.60, 0.90), (0.70, 0.62, 0.75), (0.30, 0.68, 0.95),
                (0.48, 0.72, 0.80), (0.62, 0.74, 1.00), (0.38, 0.80, 0.70),
                (0.56, 0.82, 0.85),
            ]

            for (nx, ny, scale) in speckles {
                let sx = cx - r + nx * r * 2
                let sy = cy - r + ny * r * 2
                let dx = sx - cx
                let dy = sy - cy
                // Skip speckles outside the sphere silhouette
                if sqrt(dx * dx + dy * dy) > r * 0.88 { continue }

                let sr = baseSpeckleR * scale
                // Slightly elongated oval (1.0 wide, 0.62 tall)
                let sRect = CGRect(x: sx - sr, y: sy - sr * 0.62,
                                   width: sr * 2, height: sr * 1.24)
                ctx.fill(Path(ellipseIn: sRect), with: .color(speckleColor))
            }

            // ── 3. Bright white specular crescent (upper-left) ───────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r * 0.54, y: cy - r * 0.72,
                                       width: r * 0.44, height: r * 0.30)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.72), location: 0.00),
                        .init(color: .white.opacity(0.36), location: 0.45),
                        .init(color: .clear,               location: 1.00),
                    ]),
                    center: CGPoint(x: cx - r * 0.34, y: cy - r * 0.60),
                    startRadius: 0, endRadius: r * 0.34))
        }
    }

    // ── Lava ────────────────────────────────────────────────────────────────
    // Animated molten sphere.  A vivid orange-red radial gradient base is
    // overlaid with 6 dark amber "blob" ovals that drift sinusoidally
    // upward, simulating slow convection currents.  A pulsing magma core
    // adds internal glow, an edge vignette deepens the scorched crust, and
    // a small dim specular keeps it from looking totally matte.
    //
    // Animation is frozen (t = 0) when reduceMotion is on.
    private var lavaCanvas: some View {
        return TimelineView(.animation) { timeline in
            let rawT = timeline.date.timeIntervalSinceReferenceDate
            let t: Double = reduceMotion ? 0.0 : rawT

            Canvas { ctx, size in
                let r  = min(size.width, size.height) * 0.5
                let cx = size.width  * 0.5
                let cy = size.height * 0.5

                // ── 1. Molten base gradient ──────────────────────────────
                let baseGrad = Gradient(stops: [
                    .init(color: Color(red: 1.00, green: 0.70, blue: 0.28), location: 0.00),
                    .init(color: Color(red: 0.96, green: 0.30, blue: 0.06), location: 0.38),
                    .init(color: Color(red: 0.60, green: 0.08, blue: 0.01), location: 0.72),
                    .init(color: Color(red: 0.20, green: 0.02, blue: 0.00), location: 1.00),
                ])
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(baseGrad,
                                         center: CGPoint(x: cx, y: cy),
                                         startRadius: 0,
                                         endRadius: r))

                // ── 2. Pulsing magma core ───────────────────────────────
                let corePulse = 0.85 + 0.15 * sin(t * 0.7)
                let coreGrad = Gradient(stops: [
                    .init(color: Color(red: 1.00, green: 0.90, blue: 0.50).opacity(0.55 * corePulse), location: 0.00),
                    .init(color: Color(red: 1.00, green: 0.55, blue: 0.10).opacity(0.28 * corePulse), location: 0.45),
                    .init(color: .clear, location: 1.00),
                ])
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.46, y: cy - r * 0.46,
                                           width: r * 0.92, height: r * 0.92)),
                    with: .radialGradient(coreGrad,
                                         center: CGPoint(x: cx, y: cy),
                                         startRadius: 0,
                                         endRadius: r * 0.46))

                // ── 3. Drifting dark amber blobs (convection) ──────────
                // Each tuple: (xFrac, yBase, yAmp, speed, phase, rFrac)
                let blobs: [(CGFloat, CGFloat, CGFloat, Double, Double, CGFloat)] = [
                    (0.32, 0.55, 0.14, 0.48, 0.00, 0.22),
                    (0.62, 0.48, 0.18, 0.55, 1.30, 0.19),
                    (0.45, 0.68, 0.12, 0.42, 2.60, 0.16),
                    (0.22, 0.36, 0.20, 0.60, 0.80, 0.14),
                    (0.72, 0.62, 0.16, 0.38, 1.90, 0.20),
                    (0.54, 0.28, 0.10, 0.52, 3.40, 0.13),
                ]
                let blobColor = Color(red: 0.30, green: 0.06, blue: 0.00)
                for (xFrac, yBase, yAmp, speed, phase, rFrac) in blobs {
                    let bx  = cx + (xFrac - 0.5) * r * 2
                    let byF = yBase + CGFloat(yAmp) * CGFloat(sin(t * speed + phase))
                    let by  = cy + (byF - 0.5) * r * 2
                    let br  = r * rFrac

                    // Skip blobs entirely outside the sphere silhouette
                    let dx = bx - cx, dy = by - cy
                    if sqrt(dx * dx + dy * dy) > r * 0.88 + br { continue }

                    ctx.fill(
                        Path(ellipseIn: CGRect(x: bx - br, y: by - br * 0.72,
                                               width: br * 2, height: br * 1.44)),
                        with: .color(blobColor.opacity(0.62)))
                }

                // ── 4. Edge vignette (scorched crust) ───────────────────
                let vigGrad = Gradient(stops: [
                    .init(color: .clear,                                     location: 0.60),
                    .init(color: Color(red: 0.10, green: 0.01, blue: 0.00).opacity(0.72), location: 1.00),
                ])
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(vigGrad,
                                         center: CGPoint(x: cx, y: cy),
                                         startRadius: 0,
                                         endRadius: r))

                // ── 5. Dim matte specular (upper-left) ──────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.50, y: cy - r * 0.68,
                                           width: r * 0.38, height: r * 0.24)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 1.0, green: 0.70, blue: 0.45).opacity(0.32), location: 0.00),
                            .init(color: .clear, location: 1.00),
                        ]),
                        center: CGPoint(x: cx - r * 0.31, y: cy - r * 0.56),
                        startRadius: 0, endRadius: r * 0.26))
            }
        }
    }

    // ── Trench ───────────────────────────────────────────────────────────────
    // Deep navy sphere with 7 bioluminescent teal/green dot clusters that
    // pulse slowly (opacity sine wave per cluster).  A dark radial vignette
    // sells the crushing abyssal pressure, and a faint cyan edge rim keeps
    // the silhouette readable on dark backgrounds.
    //
    // Animation freezes at t = 0 when reduceMotion is on.
    private var trenchCanvas: some View {
        return TimelineView(.animation) { timeline in
            let rawT = timeline.date.timeIntervalSinceReferenceDate
            let t: Double = reduceMotion ? 0.0 : rawT

            Canvas { ctx, size in
                let r  = min(size.width, size.height) * 0.5
                let cx = size.width  * 0.5
                let cy = size.height * 0.5

                // ── 1. Deep navy base gradient ───────────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 0.05, green: 0.15, blue: 0.38), location: 0.00),
                            .init(color: Color(red: 0.02, green: 0.07, blue: 0.22), location: 0.50),
                            .init(color: Color(red: 0.01, green: 0.02, blue: 0.10), location: 1.00),
                        ]),
                        center: CGPoint(x: cx, y: cy),
                        startRadius: 0, endRadius: r))

                // ── 2. Bioluminescent dot clusters ────────────────────────
                // Each tuple: (xFrac, yFrac, dotCount, baseRadius, speed, phase, hue)
                //   hue: 0 = teal, 1 = green-cyan
                let clusters: [(CGFloat, CGFloat, Int, CGFloat, Double, Double, Bool)] = [
                    (0.38, 0.55, 5, 0.025, 0.42, 0.00, false),
                    (0.62, 0.38, 4, 0.022, 0.55, 1.40, true),
                    (0.28, 0.32, 6, 0.020, 0.38, 2.80, false),
                    (0.70, 0.65, 3, 0.028, 0.48, 0.70, true),
                    (0.50, 0.72, 5, 0.023, 0.35, 2.10, false),
                    (0.42, 0.22, 4, 0.018, 0.60, 3.50, true),
                    (0.65, 0.28, 3, 0.026, 0.44, 1.05, false),
                ]
                var clusterRng = LevelRNG(seed: 42)
                for (xFrac, yFrac, count, baseR, speed, phase, greenTint) in clusters {
                    let bx  = cx + (xFrac - 0.5) * r * 1.62
                    let by  = cy + (yFrac - 0.5) * r * 1.62
                    let dx  = bx - cx
                    let dy  = by - cy
                    guard sqrt(dx*dx + dy*dy) < r * 0.88 else { continue }

                    let pulse = 0.40 + 0.60 * (sin(t * speed + phase) * 0.5 + 0.5)
                    let dotColor = greenTint
                        ? Color(red: 0.10, green: 0.92, blue: 0.68).opacity(pulse * 0.82)
                        : Color(red: 0.18, green: 0.82, blue: 0.88).opacity(pulse * 0.82)
                    let glowColor = greenTint
                        ? Color(red: 0.05, green: 0.80, blue: 0.55).opacity(pulse * 0.28)
                        : Color(red: 0.08, green: 0.70, blue: 0.85).opacity(pulse * 0.28)

                    for _ in 0..<count {
                        let ox = CGFloat(clusterRng.range(-1, 1)) * baseR * r * 3.5
                        let oy = CGFloat(clusterRng.range(-1, 1)) * baseR * r * 3.5
                        let px = bx + ox
                        let py = by + oy
                        let dpx = px - cx; let dpy = py - cy
                        guard sqrt(dpx*dpx + dpy*dpy) < r * 0.84 else { continue }
                        let dr = baseR * r
                        // Glow halo
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: px - dr*1.8, y: py - dr*1.8,
                                                   width: dr*3.6, height: dr*3.6)),
                            with: .color(glowColor))
                        // Core dot
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: px - dr, y: py - dr,
                                                   width: dr*2, height: dr*2)),
                            with: .color(dotColor))
                    }
                }

                // ── 3. Depth vignette ────────────────────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0.55),
                            .init(color: Color(red: 0.01, green: 0.02, blue: 0.08).opacity(0.80), location: 1.00),
                        ]),
                        center: CGPoint(x: cx, y: cy),
                        startRadius: 0, endRadius: r))

                // ── 4. Cyan rim highlight ────────────────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.52, y: cy - r * 0.70,
                                           width: r * 0.34, height: r * 0.20)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 0.40, green: 0.92, blue: 0.88).opacity(0.22), location: 0),
                            .init(color: .clear, location: 1),
                        ]),
                        center: CGPoint(x: cx - r * 0.35, y: cy - r * 0.60),
                        startRadius: 0, endRadius: r * 0.22))
            }
        }
    }

    // ── Trophy ───────────────────────────────────────────────────────────────
    // The Golden Gauntlet's exclusive prize — a lustrous prize-gold sphere with a
    // raised, iridescent CHAMPION STAR at its heart that shimmers through every
    // hue of the rainbow, a soft victory halo that breathes behind it, a specular
    // highlight that orbits the surface like light catching polished metal as it
    // rolls, and sparkle glints that twinkle across the finish.  Made to feel
    // earned, not bought.
    //
    // Rendering layers:
    //   1. Polished gold base (bright crown highlight → deep bronze rim)
    //   2. Victory halo behind the emblem (gentle breathing pulse)
    //   3. Iridescent champion star (drifting rainbow fill + pearlescent sheen +
    //      bevel + twinkling sparkles riding on the star)
    //   4. Orbiting mirror specular
    //   5. Twinkling gold sparkle glints
    //   6. Warm reflected rim light (lower-right)
    //
    // Freezes at t = 0 when reduceMotion is on (halo at mid-breath, light fixed
    // upper-left, sparkles held at a steady gleam).
    private var trophyCanvas: some View {
        return TimelineView(.animation) { timeline in
            let rawT = timeline.date.timeIntervalSinceReferenceDate
            let t: Double = reduceMotion ? 0.0 : rawT

            Canvas { ctx, size in
                let r  = min(size.width, size.height) * 0.5
                let cx = size.width  * 0.5
                let cy = size.height * 0.5
                let center = CGPoint(x: cx, y: cy)
                let sphere = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

                // ── 1. Polished gold base ────────────────────────────────
                ctx.fill(Path(ellipseIn: sphere), with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 1.00, green: 0.98, blue: 0.80), location: 0.00),
                        .init(color: Color(red: 0.99, green: 0.84, blue: 0.34), location: 0.34),
                        .init(color: Color(red: 0.82, green: 0.57, blue: 0.11), location: 0.66),
                        .init(color: Color(red: 0.44, green: 0.28, blue: 0.04), location: 0.90),
                        .init(color: Color(red: 0.19, green: 0.11, blue: 0.01), location: 1.00),
                    ]),
                    center: CGPoint(x: cx - r * 0.22, y: cy - r * 0.26),
                    startRadius: 0, endRadius: r * 1.15))

                // ── 2. Victory halo behind the emblem (breathing pulse) ──
                let pulse = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(t * 1.5)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.80, y: cy - r * 0.80,
                                           width: r * 1.60, height: r * 1.60)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 1.0, green: 0.93, blue: 0.62).opacity(0.0), location: 0.30),
                            .init(color: Color(red: 1.0, green: 0.90, blue: 0.54).opacity(0.10 + 0.13 * pulse), location: 0.60),
                            .init(color: .clear, location: 0.92),
                        ]),
                        center: center, startRadius: 0, endRadius: r * 0.80))

                // ── 3. Iridescent champion star ──────────────────────────
                let starR  = r * 0.55
                let starIn = r * 0.225
                let rot    = -Double.pi / 2          // one point up
                let star   = Self.starPath(center: center, outer: starR, inner: starIn, rotation: rot)
                // 3a. engraved drop-shadow (down-right → raised toward the light)
                ctx.fill(Self.starPath(center: CGPoint(x: cx + r * 0.045, y: cy + r * 0.055),
                                       outer: starR, inner: starIn, rotation: rot),
                         with: .color(Color(red: 0.07, green: 0.06, blue: 0.10).opacity(0.55)))
                // 3b. dark base under the star so the iridescence reads vividly
                ctx.fill(star, with: .color(Color(red: 0.09, green: 0.07, blue: 0.13)))
                // 3c. iridescent rainbow — a hue band drifts through the star while
                //     the gradient direction slowly rotates (prismatic shimmer).
                let hueShift = reduceMotion ? 0.0 : (t * 0.11).truncatingRemainder(dividingBy: 1.0)
                let irisStops: [Gradient.Stop] = (0...6).map { i in
                    let loc = Double(i) / 6.0
                    let hue = (loc + hueShift).truncatingRemainder(dividingBy: 1.0)
                    return .init(color: Color(hue: hue, saturation: 0.82, brightness: 1.0), location: loc)
                }
                let irisAng = reduceMotion ? 0.7 : t * 0.22
                let idx = CGFloat(cos(irisAng)) * starR
                let idy = CGFloat(sin(irisAng)) * starR
                ctx.fill(star, with: .linearGradient(
                    Gradient(stops: irisStops),
                    startPoint: CGPoint(x: cx - idx, y: cy - idy),
                    endPoint:   CGPoint(x: cx + idx, y: cy + idy)))
                // 3d. pearlescent sheen on the upper half (glossy lacquer)
                ctx.fill(star, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.55), location: 0.0),
                        .init(color: .white.opacity(0.06), location: 0.42),
                        .init(color: .clear, location: 0.62),
                    ]),
                    startPoint: CGPoint(x: cx, y: cy - starR),
                    endPoint:   CGPoint(x: cx, y: cy + starR)))
                // 3e. bright white bevel edge
                ctx.stroke(star, with: .color(.white.opacity(0.92)), lineWidth: max(0.5, r * 0.022))
                // 3f. twinkling sparkles riding on the star
                let starGlints: [(CGFloat, CGFloat, Double)] = [
                    (0.0, -0.60, 0.0), (-0.30, 0.18, 2.1), (0.32, 0.10, 4.0),
                ]
                for (gx, gy, ph) in starGlints {
                    let tw = reduceMotion ? 0.7 : max(0.0, sin(t * 3.0 + ph))
                    if tw <= 0.05 { continue }
                    let p = CGPoint(x: cx + gx * starR, y: cy + gy * starR)
                    trophyGlint(ctx, at: p, size: r * 0.11 * CGFloat(0.55 + 0.5 * tw), opacity: tw)
                }

                // ── 4. Orbiting mirror specular ──────────────────────────
                let orbit = t * 0.6 - 2.2
                let sx = cx + r * 0.34 * CGFloat(cos(orbit))
                let sy = cy + r * 0.34 * CGFloat(sin(orbit)) - r * 0.28
                ctx.fill(
                    Path(ellipseIn: CGRect(x: sx - r * 0.30, y: sy - r * 0.16,
                                           width: r * 0.60, height: r * 0.32)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .white.opacity(0.78), location: 0.0),
                            .init(color: .white.opacity(0.22), location: 0.45),
                            .init(color: .clear, location: 1.0),
                        ]),
                        center: CGPoint(x: sx, y: sy), startRadius: 0, endRadius: r * 0.32))

                // ── 5. Twinkling gold sparkle glints ─────────────────────
                let glints: [(CGFloat, CGFloat, Double)] = [
                    (0.30, 0.30, 0.0), (0.74, 0.40, 1.9), (0.60, 0.74, 3.6), (0.34, 0.64, 5.1),
                ]
                for (gx, gy, ph) in glints {
                    let tw = reduceMotion ? 0.5 : max(0.0, sin(t * 2.1 + ph))
                    if tw <= 0.02 { continue }
                    let ox: CGFloat = (gx - 0.5) * 2 * r * 0.82
                    let oy: CGFloat = (gy - 0.5) * 2 * r * 0.82
                    let p = CGPoint(x: cx + ox, y: cy + oy)
                    if hypot(p.x - cx, p.y - cy) > r * 0.92 { continue }
                    let glintSize: CGFloat = r * 0.13 * CGFloat(0.6 + 0.4 * tw)
                    trophyGlint(ctx, at: p, size: glintSize, opacity: tw)
                }

                // ── 6. Warm reflected rim light (lower-right) ────────────
                ctx.stroke(
                    Path(ellipseIn: sphere.insetBy(dx: r * 0.04, dy: r * 0.04)),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0.30),
                            .init(color: Color(red: 1.0, green: 0.90, blue: 0.55).opacity(0.5), location: 0.62),
                            .init(color: .clear, location: 0.85),
                        ]),
                        startPoint: CGPoint(x: cx - r, y: cy - r),
                        endPoint:   CGPoint(x: cx + r, y: cy + r)),
                    lineWidth: max(0.6, r * 0.03))
            }
        }
    }

    /// A pointed star path (default 5 points), used for the Trophy's champion emblem.
    private static func starPath(center c: CGPoint, outer R: CGFloat, inner: CGFloat,
                                 points: Int = 5, rotation rot: Double) -> Path {
        var p = Path()
        for k in 0..<(points * 2) {
            let a   = rot + Double(k) * .pi / Double(points)
            let rad = (k % 2 == 0) ? R : inner
            let pt  = CGPoint(x: c.x + CGFloat(cos(a)) * rad, y: c.y + CGFloat(sin(a)) * rad)
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// A warm 4-point sparkle flare for the Trophy's gleam (gold-tinted bloom + white star).
    private func trophyGlint(_ ctx: GraphicsContext, at c: CGPoint, size: CGFloat, opacity: Double) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - size, y: c.y - size, width: size * 2, height: size * 2)),
                 with: .radialGradient(Gradient(colors: [
                    Color(red: 1.0, green: 0.96, blue: 0.78).opacity(0.5 * opacity), .clear]),
                    center: c, startRadius: 0, endRadius: size))
        var star = Path()
        let L = size, inr = size * 0.18
        for k in 0..<8 {
            let a   = Double(k) * .pi / 4 - .pi / 2
            let rad = (k % 2 == 0) ? L : inr
            let p   = CGPoint(x: c.x + CGFloat(cos(a)) * rad, y: c.y + CGFloat(sin(a)) * rad)
            if k == 0 { star.move(to: p) } else { star.addLine(to: p) }
        }
        star.closeSubpath()
        ctx.fill(star, with: .color(.white.opacity(min(1.0, 0.9 * opacity))))
    }

    // =========================================================================
    // MARK: - Fireworks  (Star-Spangled seasonal · Legendary)
    // A dark night-sky sphere with three firework "shells" bursting in red,
    // white, and blue.  Each shell is a ring of radial spark streaks whose
    // length and brightness pulse fully in and out on its own slow phase, so
    // the bursts bloom and fade like real fireworks; falling sparks drift
    // downward beneath the faded bursts.  Twinkling background stars and a
    // small specular complete the sphere.  Reduce Motion freezes every burst
    // mid-bloom and stills the sparks.
    // Clipped to a circle by the body switch caller.
    // =========================================================================
    private var fireworksCanvas: some View {
        TimelineView(.animation) { tl in
            let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate

            Canvas { ctx, size in
                let w  = size.width
                let h  = size.height
                let cx = w / 2
                let cy = h / 2
                let r  = min(w, h) / 2

                // ── 1. Dark night-sky sphere ─────────────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 0.18, green: 0.20, blue: 0.42), location: 0.00),
                            .init(color: Color(red: 0.06, green: 0.08, blue: 0.24), location: 0.45),
                            .init(color: Color(red: 0.02, green: 0.03, blue: 0.12), location: 0.80),
                            .init(color: Color(red: 0.00, green: 0.01, blue: 0.05), location: 1.00),
                        ]),
                        center: CGPoint(x: cx - r * 0.18, y: cy - r * 0.24),
                        startRadius: 0, endRadius: r * 1.25))

                // ── 2. Twinkling background stars ────────────────────────
                for (i, s) in [(0.30, 0.26), (0.68, 0.22), (0.50, 0.66),
                               (0.22, 0.58), (0.78, 0.60), (0.40, 0.44),
                               (0.62, 0.74), (0.34, 0.18)].enumerated() {
                    let tw = reduceMotion ? 0.6 : 0.35 + 0.5 * sin(t * 2.4 + Double(i) * 1.6)
                    if tw < 0.18 { continue }
                    let px = w * CGFloat(s.0), py = h * CGFloat(s.1)
                    if hypot(px - cx, py - cy) > r * 0.88 { continue }
                    let ss = r * 0.014
                    ctx.fill(Path(ellipseIn: CGRect(x: px - ss, y: py - ss, width: ss * 2, height: ss * 2)),
                             with: .color(.white.opacity(tw)))
                }

                // ── 3. Three bursting firework shells ────────────────────
                // (centreXFrac, centreYFrac, hue, speed, phase)
                let red   = Color(red: 1.00, green: 0.28, blue: 0.24)
                let white = Color(red: 1.00, green: 1.00, blue: 0.96)
                let blue  = Color(red: 0.36, green: 0.58, blue: 1.00)
                let shells: [(CGFloat, CGFloat, Color, Double, Double)] = [
                    (0.36, 0.34, red,   0.55, 0.0),
                    (0.66, 0.42, blue,  0.47, 2.1),
                    (0.50, 0.60, white, 0.61, 4.2),
                ]
                let spokes = 14
                for (fx, fy, hue, speed, phase) in shells {
                    let bx = cx - r + fx * r * 2
                    let by = cy - r + fy * r * 2

                    // Burst intensity: blooms 0→1→0 over its phase.
                    let raw   = reduceMotion ? 0.85 : sin(t * speed + phase)
                    let bloom = max(0, raw)
                    if bloom < 0.04 { continue }
                    // Sparks fly outward as the burst blooms.
                    let reach  = r * (0.10 + 0.34 * bloom)
                    let inner  = r * 0.05
                    let lw     = max(0.8, r * 0.022)

                    for k in 0..<spokes {
                        let a  = Double(k) / Double(spokes) * 2 * .pi
                        let x0 = bx + CGFloat(cos(a)) * inner
                        let y0 = by + CGFloat(sin(a)) * inner
                        let x1 = bx + CGFloat(cos(a)) * reach
                        let y1 = by + CGFloat(sin(a)) * reach
                        // Clip streaks that run outside the sphere silhouette.
                        if hypot(x1 - cx, y1 - cy) > r * 0.94 { continue }
                        var streak = Path()
                        streak.move(to: CGPoint(x: x0, y: y0))
                        streak.addLine(to: CGPoint(x: x1, y: y1))
                        ctx.stroke(streak,
                                   with: .color(hue.opacity(0.85 * bloom)),
                                   style: StrokeStyle(lineWidth: lw, lineCap: .round))
                        // Bright spark tip.
                        let tipR = r * 0.020
                        ctx.fill(Path(ellipseIn: CGRect(x: x1 - tipR, y: y1 - tipR,
                                                        width: tipR * 2, height: tipR * 2)),
                                 with: .color(.white.opacity(0.9 * bloom)))
                    }
                    // Hot core flash.
                    let coreR = r * 0.08 * bloom
                    ctx.fill(Path(ellipseIn: CGRect(x: bx - coreR, y: by - coreR,
                                                    width: coreR * 2, height: coreR * 2)),
                             with: .radialGradient(
                                Gradient(colors: [.white.opacity(0.9 * bloom), hue.opacity(0.0)]),
                                center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: max(0.1, coreR)))
                }

                // ── 4. Small specular (upper-left) ───────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.50, y: cy - r * 0.74,
                                           width: r * 0.34, height: r * 0.22)),
                    with: .radialGradient(
                        Gradient(colors: [.white.opacity(0.40), .clear]),
                        center: CGPoint(x: cx - r * 0.34, y: cy - r * 0.64),
                        startRadius: 0, endRadius: r * 0.24))
            }
        }
    }

    // =========================================================================
    // MARK: - Sugar Skull  (Día de los Muertos seasonal · Legendary)
    // An ornate white calavera: a bone-white sphere with two large round eye
    // sockets ringed by marigold-orange petals, a small inverted-heart nose, a
    // stitched smile across the lower face, and a rose-and-marigold floral
    // motif on the forehead.  Bright and festive.  Animated: the marigold
    // sparks in the eye sockets pulse like votive candles (each on its own
    // phase) and a handful of tiny marigold/rose sparks drift up around the
    // face.  Under Reduce Motion both are gone — exactly the original static
    // calavera.  Clipped to a circle by the body switch caller.
    // =========================================================================
    private var sugarSkullCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate

                let w  = size.width
                let h  = size.height
                let cx = w / 2
                let cy = h / 2
                let r  = min(w, h) / 2

                let marigold = Color(red: 1.00, green: 0.60, blue: 0.12)
                let rose     = Color(red: 0.92, green: 0.24, blue: 0.46)
                let outline  = Color(red: 0.30, green: 0.20, blue: 0.16)

                // ── 1. Bone-white sphere ─────────────────────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 1.00, green: 1.00, blue: 0.99), location: 0.00),
                            .init(color: Color(red: 0.96, green: 0.95, blue: 0.90), location: 0.45),
                            .init(color: Color(red: 0.80, green: 0.76, blue: 0.68), location: 0.82),
                            .init(color: Color(red: 0.48, green: 0.42, blue: 0.36), location: 1.00),
                        ]),
                        center: CGPoint(x: cx - r * 0.20, y: cy - r * 0.26),
                        startRadius: 0, endRadius: r * 1.22))

                // ── 2. Forehead floral motif (rose + marigold petals) ────────
                let fcx = cx
                let fcy = cy - r * 0.46
                // Marigold petal ring.
                for k in 0..<8 {
                    let a  = Double(k) / 8.0 * 2 * .pi
                    let pr = r * 0.085
                    let px = fcx + CGFloat(cos(a)) * r * 0.13
                    let py = fcy + CGFloat(sin(a)) * r * 0.13
                    ctx.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr, width: pr * 2, height: pr * 2)),
                             with: .color(marigold.opacity(0.92)))
                }
                // Rose centre.
                let roseR = r * 0.10
                ctx.fill(Path(ellipseIn: CGRect(x: fcx - roseR, y: fcy - roseR, width: roseR * 2, height: roseR * 2)),
                         with: .color(rose))
                let roseR2 = r * 0.045
                ctx.fill(Path(ellipseIn: CGRect(x: fcx - roseR2, y: fcy - roseR2, width: roseR2 * 2, height: roseR2 * 2)),
                         with: .color(.white.opacity(0.85)))

                // ── 3. Eye sockets with marigold petal rings ─────────────────
                let eyeDX = r * 0.34
                let eyeY  = cy - r * 0.02
                let eyeR  = r * 0.20
                for sgn in [CGFloat(-1), 1] {
                    let ecx = cx + sgn * eyeDX
                    // Marigold petals around the socket.
                    for k in 0..<10 {
                        let a  = Double(k) / 10.0 * 2 * .pi
                        let pr = r * 0.045
                        let px = ecx + CGFloat(cos(a)) * eyeR * 1.05
                        let py = eyeY + CGFloat(sin(a)) * eyeR * 1.05
                        ctx.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr, width: pr * 2, height: pr * 2)),
                                 with: .color((k % 2 == 0 ? marigold : rose).opacity(0.85)))
                    }
                    // Dark socket.
                    ctx.fill(Path(ellipseIn: CGRect(x: ecx - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2)),
                             with: .color(outline))
                    // Small bright spark glint in each socket (static base).
                    let gr = eyeR * 0.34
                    ctx.fill(Path(ellipseIn: CGRect(x: ecx - gr, y: eyeY - gr, width: gr * 2, height: gr * 2)),
                             with: .color(marigold.opacity(0.55)))
                    // 3b. Votive-candle pulse — a marigold halo breathing over
                    //     the socket and its petal ring, each eye on its own
                    //     phase.  Additive; invisible under Reduce Motion.
                    if !reduceMotion {
                        let phase: Double = sgn > 0 ? 0.0 : 1.9
                        let pulse: Double = 0.14 + 0.22 * (0.5 + 0.5 * sin(t * 1.7 + phase))
                        let hr: CGFloat = eyeR * 1.55
                        ctx.fill(Path(ellipseIn: CGRect(x: ecx - hr, y: eyeY - hr,
                                                        width: hr * 2, height: hr * 2)),
                                 with: .radialGradient(
                                    Gradient(colors: [marigold.opacity(pulse), .clear]),
                                    center: CGPoint(x: ecx, y: eyeY),
                                    startRadius: 0, endRadius: hr))
                    }
                }

                // ── 4. Inverted-heart nose ───────────────────────────────────
                let nCx = cx
                let nCy = cy + r * 0.22
                let nS  = r * 0.10
                var nose = Path()
                nose.move(to: CGPoint(x: nCx, y: nCy + nS))                                  // bottom tip
                nose.addQuadCurve(to: CGPoint(x: nCx - nS, y: nCy - nS * 0.4),
                                  control: CGPoint(x: nCx - nS * 1.1, y: nCy + nS * 0.4))
                nose.addArc(center: CGPoint(x: nCx - nS * 0.5, y: nCy - nS * 0.4),
                            radius: nS * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                nose.addArc(center: CGPoint(x: nCx + nS * 0.5, y: nCy - nS * 0.4),
                            radius: nS * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                nose.addQuadCurve(to: CGPoint(x: nCx, y: nCy + nS),
                                  control: CGPoint(x: nCx + nS * 1.1, y: nCy + nS * 0.4))
                nose.closeSubpath()
                ctx.fill(nose, with: .color(outline))

                // ── 5. Stitched smile ────────────────────────────────────────
                let smileY = cy + r * 0.50
                var smile = Path()
                smile.move(to: CGPoint(x: cx - r * 0.42, y: smileY))
                smile.addQuadCurve(to: CGPoint(x: cx + r * 0.42, y: smileY),
                                   control: CGPoint(x: cx, y: smileY + r * 0.12))
                ctx.stroke(smile, with: .color(outline),
                           style: StrokeStyle(lineWidth: max(1.0, r * 0.03), lineCap: .round))
                // Vertical stitch ticks crossing the smile.
                for f in stride(from: CGFloat(-0.34), through: 0.34, by: 0.115) {
                    let sx = cx + f * r
                    let droop = (1 - (f / 0.42) * (f / 0.42)) * r * 0.10
                    var tick = Path()
                    tick.move(to: CGPoint(x: sx, y: smileY + droop - r * 0.05))
                    tick.addLine(to: CGPoint(x: sx, y: smileY + droop + r * 0.05))
                    ctx.stroke(tick, with: .color(outline),
                               style: StrokeStyle(lineWidth: max(0.8, r * 0.018), lineCap: .round))
                }

                // ── 6. Drifting marigold sparks — tiny petals of light rising
                //     around the face, twinkling on individual clocks.
                //     (skipped entirely under Reduce Motion → static fallback)
                if !reduceMotion {
                    for i in 0..<8 {
                        let seed: Double  = Double(i) * 0.57 + 0.11
                        let speed: Double = 0.10 + 0.04 * Double(i % 3)
                        let cycle: Double = (t * speed + seed).truncatingRemainder(dividingBy: 1.0)
                        let ang: Double   = seed * 6.283 + t * 0.25
                        let orbit: CGFloat = r * (0.55 + 0.8 * CGFloat(seed.truncatingRemainder(dividingBy: 0.4)))
                        let px: CGFloat = cx + CGFloat(cos(ang)) * orbit
                        let py: CGFloat = cy + r * 0.90 - CGFloat(cycle) * r * 1.80
                        let tw: Double   = 0.30 + 0.45 * (0.5 + 0.5 * sin(t * 2.3 + seed * 7.0))
                        let fade: Double = tw * min(1.0, cycle * 5.0) * min(1.0, (1.0 - cycle) * 5.0)
                        let ss: CGFloat = r * (0.020 + 0.012 * CGFloat(i % 2))
                        let col = (i % 3 == 0) ? rose : marigold
                        ctx.fill(Path(ellipseIn: CGRect(x: px - ss, y: py - ss,
                                                        width: ss * 2, height: ss * 2)),
                                 with: .color(col.opacity(fade)))
                    }
                }

                // ── 7. Specular highlight (upper-left) ───────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.58, y: cy - r * 0.78,
                                           width: r * 0.40, height: r * 0.26)),
                    with: .radialGradient(
                        Gradient(colors: [.white.opacity(0.55), .clear]),
                        center: CGPoint(x: cx - r * 0.40, y: cy - r * 0.66),
                        startRadius: 0, endRadius: r * 0.28))
            }
        }
    }

    // =========================================================================
    // MARK: - Harvest Moon  (Harvest Moon seasonal · Legendary)
    // A warm amber-to-maple gradient sphere with a subtle autumn-leaf motif:
    // a few translucent maple-leaf silhouettes drifting across the lit face
    // in deeper russet, plus soft mottled "moon" patches.  Cozy fall tones.
    // Animated: the resident leaves sway gently on individual clocks, a warm
    // amber harvest-light leans slowly side to side, and a few small leaves
    // tumble down the face.  Under Reduce Motion all motion stops at the
    // original static pose.  Clipped to a circle by the body switch caller.
    // =========================================================================
    private var harvestCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                // Per-leaf sway (zero under Reduce Motion → original pose).
                let sway1: Double = reduceMotion ? 0.0 : 0.16 * sin(t * 0.70)
                let sway2: Double = reduceMotion ? 0.0 : 0.16 * sin(t * 0.60 + 2.1)
                let sway3: Double = reduceMotion ? 0.0 : 0.16 * sin(t * 0.80 + 4.2)

                let w  = size.width
                let h  = size.height
                let cx = w / 2
                let cy = h / 2
                let r  = min(w, h) / 2

                // ── 1. Warm amber → maple gradient sphere ────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color(red: 1.00, green: 0.90, blue: 0.62), location: 0.00),
                            .init(color: Color(red: 0.94, green: 0.66, blue: 0.28), location: 0.42),
                            .init(color: Color(red: 0.74, green: 0.40, blue: 0.14), location: 0.80),
                            .init(color: Color(red: 0.38, green: 0.18, blue: 0.06), location: 1.00),
                        ]),
                        center: CGPoint(x: cx - r * 0.22, y: cy - r * 0.28),
                        startRadius: 0, endRadius: r * 1.24))

                // ── 2. Soft mottled "moon" patches (deeper maria) ────────────
                let maria = Color(red: 0.64, green: 0.34, blue: 0.12).opacity(0.32)
                for (fx, fy, fr) in [(0.40, 0.36, 0.20), (0.66, 0.58, 0.16),
                                     (0.30, 0.62, 0.13), (0.58, 0.30, 0.11)] {
                    let bx = cx - r + CGFloat(fx) * r * 2
                    let by = cy - r + CGFloat(fy) * r * 2
                    let br = CGFloat(fr) * r
                    ctx.fill(Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                             with: .radialGradient(Gradient(colors: [maria, .clear]),
                                                   center: CGPoint(x: bx, y: by), startRadius: 0, endRadius: br))
                }

                // ── 2b. Swaying amber harvest-light — a warm glow that leans
                //     slowly side to side across the lit face.  Additive;
                //     skipped under Reduce Motion → static fallback.
                if !reduceMotion {
                    let warmX: CGFloat = cx + CGFloat(sin(t * 0.5)) * r * 0.24
                    let warm: Double = 0.14 + 0.06 * sin(t * 0.6 + 1.0)
                    let warmR: CGFloat = r * 0.80
                    ctx.fill(Path(ellipseIn: CGRect(x: warmX - warmR, y: cy - r * 0.10 - warmR,
                                                    width: warmR * 2, height: warmR * 2)),
                             with: .radialGradient(
                                Gradient(colors: [Color(red: 1.00, green: 0.82, blue: 0.42).opacity(warm), .clear]),
                                center: CGPoint(x: warmX, y: cy - r * 0.10),
                                startRadius: 0, endRadius: warmR))
                }

                // ── 3. Autumn-leaf motif — a few maple silhouettes ───────────
                // A 7-point star-ish maple leaf built from radial spokes.
                func leaf(at center: CGPoint, scale: CGFloat, rot: Double, color: Color) {
                    let lobes = 7
                    var path = Path()
                    for i in 0...(lobes * 2) {
                        let frac = Double(i) / Double(lobes * 2)
                        let a    = frac * 2 * .pi + rot
                        // Alternate long tip / short valley to suggest serrated lobes.
                        let rad  = (i % 2 == 0 ? scale : scale * 0.46)
                        let px   = center.x + CGFloat(cos(a)) * rad
                        let py   = center.y + CGFloat(sin(a)) * rad
                        if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
                        else      { path.addLine(to: CGPoint(x: px, y: py)) }
                    }
                    path.closeSubpath()
                    ctx.fill(path, with: .color(color))
                    // Short stem.
                    var stem = Path()
                    stem.move(to: center)
                    stem.addLine(to: CGPoint(x: center.x - CGFloat(cos(rot)) * scale * 1.3,
                                             y: center.y - CGFloat(sin(rot)) * scale * 1.3))
                    ctx.stroke(stem, with: .color(color),
                               style: StrokeStyle(lineWidth: max(0.8, scale * 0.10), lineCap: .round))
                }
                let russet = Color(red: 0.60, green: 0.26, blue: 0.08).opacity(0.55)
                let amber  = Color(red: 0.86, green: 0.50, blue: 0.16).opacity(0.50)
                leaf(at: CGPoint(x: cx - r * 0.34, y: cy + r * 0.18), scale: r * 0.20, rot: 0.4 + sway1,  color: russet)
                leaf(at: CGPoint(x: cx + r * 0.30, y: cy - r * 0.10), scale: r * 0.16, rot: 2.1 + sway2,  color: amber)
                leaf(at: CGPoint(x: cx + r * 0.06, y: cy + r * 0.40), scale: r * 0.14, rot: -0.8 + sway3, color: russet)

                // ── 3b. Falling leaves — small maples tumbling down the face,
                //     fading in near the crown and out near the base.
                //     (skipped entirely under Reduce Motion → static fallback)
                if !reduceMotion {
                    let fallBase = Color(red: 0.72, green: 0.34, blue: 0.10)
                    for i in 0..<4 {
                        let seed: Double  = Double(i) * 0.77 + 0.21
                        let speed: Double = 0.09 + 0.03 * Double(i % 2)
                        let cycle: Double = (t * speed + seed).truncatingRemainder(dividingBy: 1.0)
                        let flutter: Double = sin(t * 0.9 + seed * 6.0)
                        let drift: CGFloat = CGFloat(seed.truncatingRemainder(dividingBy: 0.6) - 0.3)
                        let px: CGFloat = cx + drift * r * 1.9 + CGFloat(flutter) * r * 0.10
                        let py: CGFloat = cy - r * 0.95 + CGFloat(cycle) * r * 1.90
                        let rot: Double = seed * 3.0 + t * (0.5 + 0.2 * Double(i % 2))
                        let fade: Double = min(1.0, cycle * 8.0) * min(1.0, (1.0 - cycle) * 8.0)
                        let sc: CGFloat = r * (0.070 + 0.020 * CGFloat(i % 2))
                        leaf(at: CGPoint(x: px, y: py), scale: sc, rot: rot,
                             color: fallBase.opacity(0.50 * fade))
                    }
                }

                // ── 4. Warm specular highlight (upper-left) ──────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.56, y: cy - r * 0.76,
                                           width: r * 0.44, height: r * 0.30)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .white.opacity(0.55), location: 0.00),
                            .init(color: Color(red: 1.0, green: 0.92, blue: 0.66).opacity(0.30), location: 0.45),
                            .init(color: .clear,               location: 1.00),
                        ]),
                        center: CGPoint(x: cx - r * 0.36, y: cy - r * 0.64),
                        startRadius: 0, endRadius: r * 0.34))
            }
        }
    }

    // =========================================================================
    // MARK: - Golden Dragon  (Year of the Dragon seasonal · Legendary)
    // A deep-red lacquer sphere with a gold dragon-scale field, gilt filigree
    // arcs, and a regal sheen.  A MeshGradient supplies the lustrous lacquer
    // base; a Canvas paints the overlapping gold scales, filigree, and a roving
    // gilt specular.  A single slow shimmer band drifts across the lit face —
    // under Reduce Motion it holds steady (no animation).  Clipped to a circle
    // by the body switch caller.
    // =========================================================================
    private var lunarDragonCanvas: some View {
        TimelineView(.animation) { tl in
            let t = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
            // Slow shimmer phase — 0…1, used to drift one bright band.
            let shimmer = reduceMotion ? 0.30 : (sin(t * 0.7) * 0.5 + 0.5)

            ZStack {
                // ── 1. Lacquer-red lustre base (MeshGradient) ────────────────
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
                    ],
                    colors: [
                        Color(red: 0.94, green: 0.30, blue: 0.20), Color(red: 0.80, green: 0.14, blue: 0.12), Color(red: 0.52, green: 0.06, blue: 0.08),
                        Color(red: 0.86, green: 0.18, blue: 0.14), Color(red: 0.66, green: 0.09, blue: 0.09), Color(red: 0.34, green: 0.03, blue: 0.05),
                        Color(red: 0.50, green: 0.05, blue: 0.07), Color(red: 0.30, green: 0.02, blue: 0.04), Color(red: 0.14, green: 0.01, blue: 0.02),
                    ]
                )

                // ── 2. Gold dragon-scale field + filigree + sheen ────────────
                Canvas { ctx, size in
                    let w  = size.width
                    let h  = size.height
                    let cx = w / 2
                    let cy = h / 2
                    let r  = min(w, h) / 2

                    let gold     = Color(red: 0.92, green: 0.74, blue: 0.30)
                    let goldDark = Color(red: 0.62, green: 0.44, blue: 0.12)
                    let goldHi   = Color(red: 1.00, green: 0.92, blue: 0.58)

                    // ── Overlapping dragon scales — rows of gilt-edged arcs ──
                    let scale = r * 0.22
                    var row = 0
                    var y = cy - r * 0.92
                    while y < cy + r * 0.95 {
                        // Offset alternate rows for a tessellated scale look.
                        let xOff = (row % 2 == 0) ? 0.0 : scale
                        var x = cx - r - scale
                        while x < cx + r + scale {
                            let scx = x + CGFloat(xOff)
                            // Distance-cull so scales sit inside the sphere edge.
                            let dx = scx - cx
                            let dy = y  - cy
                            if dx * dx + dy * dy < (r * 0.98) * (r * 0.98) {
                                // Scale = a downward fan (half-disc) with a gilt rim.
                                let rect = CGRect(x: scx - scale, y: y - scale,
                                                  width: scale * 2, height: scale * 2)
                                var fan = Path()
                                fan.addArc(center: CGPoint(x: scx, y: y),
                                           radius: scale,
                                           startAngle: .degrees(0), endAngle: .degrees(180),
                                           clockwise: false)
                                fan.closeSubpath()
                                ctx.fill(fan, with: .radialGradient(
                                    Gradient(colors: [goldHi.opacity(0.55), gold.opacity(0.32), .clear]),
                                    center: CGPoint(x: scx, y: y + scale * 0.2),
                                    startRadius: 0, endRadius: scale * 1.1))
                                ctx.stroke(fan, with: .color(goldDark.opacity(0.5)),
                                           lineWidth: max(0.5, scale * 0.06))
                                _ = rect
                            }
                            x += scale * 2
                        }
                        y += scale * 0.9
                        row += 1
                    }

                    // ── Gilt filigree arcs (two sweeping S-curves) ───────────
                    for sgn in [CGFloat(-1), 1] {
                        var fil = Path()
                        fil.move(to: CGPoint(x: cx + sgn * r * 0.10, y: cy - r * 0.72))
                        fil.addCurve(to: CGPoint(x: cx + sgn * r * 0.62, y: cy + r * 0.20),
                                     control1: CGPoint(x: cx + sgn * r * 0.70, y: cy - r * 0.50),
                                     control2: CGPoint(x: cx + sgn * r * 0.30, y: cy - r * 0.10))
                        fil.addCurve(to: CGPoint(x: cx + sgn * r * 0.04, y: cy + r * 0.74),
                                     control1: CGPoint(x: cx + sgn * r * 0.90, y: cy + r * 0.48),
                                     control2: CGPoint(x: cx + sgn * r * 0.34, y: cy + r * 0.56))
                        ctx.stroke(fil, with: .color(gold.opacity(0.7)),
                                   style: StrokeStyle(lineWidth: max(1.0, r * 0.035), lineCap: .round))
                    }

                    // ── Drifting shimmer band (Reduce-Motion-safe) ───────────
                    let bandX = cx - r + CGFloat(shimmer) * r * 2
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: bandX - r * 0.30, y: cy - r * 1.1,
                                               width: r * 0.60, height: r * 2.2)),
                        with: .linearGradient(
                            Gradient(colors: [.clear, goldHi.opacity(0.30), .clear]),
                            startPoint: CGPoint(x: bandX - r * 0.30, y: cy),
                            endPoint:   CGPoint(x: bandX + r * 0.30, y: cy)))

                    // ── Regal specular highlight (upper-left) ────────────────
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: cx - r * 0.58, y: cy - r * 0.78,
                                               width: r * 0.44, height: r * 0.30)),
                        with: .radialGradient(
                            Gradient(colors: [.white.opacity(0.55), goldHi.opacity(0.25), .clear]),
                            center: CGPoint(x: cx - r * 0.38, y: cy - r * 0.66),
                            startRadius: 0, endRadius: r * 0.34))
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Mardi Gras  (Mardi Gras seasonal · Legendary)
    // A festive harlequin-diamond pattern in royal purple, emerald green, and
    // gold, with a jeweled bead-like sheen.  A Canvas tiles a diagonal diamond
    // lattice (clipped to the sphere by the body switch caller), tints it with a
    // radial sphere-shade so it reads 3-D, scatters a few bright bead glints,
    // and adds a specular highlight.  Animated: the gold lattice shimmers on a
    // slow clock, a parade-float glint band sweeps across the sphere, and each
    // bead glint twinkles on its own phase.  Under Reduce Motion everything
    // holds at the original static look.
    // =========================================================================
    private var mardiGrasCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                // Lattice shimmer — 0.45 is the original static stroke opacity.
                let latticeGlow: Double = reduceMotion ? 0.45 : 0.36 + 0.16 * (0.5 + 0.5 * sin(t * 1.2))

                let w  = size.width
                let h  = size.height
                let cx = w / 2
                let cy = h / 2
                let r  = min(w, h) / 2

                let purple = Color(red: 0.42, green: 0.12, blue: 0.62)
                let green  = Color(red: 0.06, green: 0.52, blue: 0.24)
                let gold   = Color(red: 0.92, green: 0.74, blue: 0.20)

                // ── 1. Harlequin diamond lattice ─────────────────────────────
                // Rotated 45° grid of diamonds; colour cycles purple→green→gold
                // by (row+col) so adjacent diamonds always differ.
                let d = r * 0.42                       // diamond half-diagonal
                let cols = Int(w / d) + 3
                let rows = Int(h / d) + 3
                for rr in -1..<rows {
                    for cc in -1..<cols {
                        let dcx = CGFloat(cc) * d - (rr % 2 == 0 ? 0 : d / 2)
                        let dcy = CGFloat(rr) * (d * 0.7)
                        // Cull to sphere.
                        let dx = dcx - cx
                        let dy = dcy - cy
                        if dx * dx + dy * dy > (r * 1.05) * (r * 1.05) { continue }
                        var dia = Path()
                        dia.move(to: CGPoint(x: dcx,         y: dcy - d * 0.7))
                        dia.addLine(to: CGPoint(x: dcx + d * 0.5, y: dcy))
                        dia.addLine(to: CGPoint(x: dcx,         y: dcy + d * 0.7))
                        dia.addLine(to: CGPoint(x: dcx - d * 0.5, y: dcy))
                        dia.closeSubpath()
                        let hue = (rr + cc) % 3
                        let col = (hue == 0 ? purple : (hue == 1 ? green : gold))
                        ctx.fill(dia, with: .color(col))
                        ctx.stroke(dia, with: .color(gold.opacity(latticeGlow)),
                                   lineWidth: max(0.5, r * 0.012))
                    }
                }

                // ── 2. Radial sphere-shade so the lattice reads 3-D ──────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .white.opacity(0.30),       location: 0.00),
                            .init(color: .clear,                     location: 0.46),
                            .init(color: .black.opacity(0.22),       location: 0.82),
                            .init(color: .black.opacity(0.55),       location: 1.00),
                        ]),
                        center: CGPoint(x: cx - r * 0.24, y: cy - r * 0.28),
                        startRadius: 0, endRadius: r * 1.24))

                // ── 2b. Bead-glint sweep — a soft light band gliding across
                //     the sphere like passing parade lights.  Skipped under
                //     Reduce Motion → static fallback.
                if !reduceMotion {
                    let sweepCycle: Double = (t * 0.30).truncatingRemainder(dividingBy: 1.6)
                    let bandX: CGFloat = cx - r * 1.5 + CGFloat(sweepCycle) * r * 2.2
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: bandX - r * 0.26, y: cy - r * 1.1,
                                               width: r * 0.52, height: r * 2.2)),
                        with: .linearGradient(
                            Gradient(colors: [.clear, .white.opacity(0.22), .clear]),
                            startPoint: CGPoint(x: bandX - r * 0.26, y: cy),
                            endPoint:   CGPoint(x: bandX + r * 0.26, y: cy)))
                }

                // ── 3. Jeweled bead glints — each twinkling on its own phase
                //     (steady at the original brightness under Reduce Motion).
                let spots: [(Double, Double, Double)] = [
                    (0.30, 0.32, 0.06), (0.66, 0.40, 0.05), (0.46, 0.62, 0.055),
                    (0.72, 0.66, 0.04), (0.24, 0.58, 0.04)]
                for (idx, spot) in spots.enumerated() {
                    let tw: Double = reduceMotion ? 1.0 : 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 2.6 + Double(idx) * 1.9))
                    let bx = cx - r + CGFloat(spot.0) * r * 2
                    let by = cy - r + CGFloat(spot.1) * r * 2
                    let br = CGFloat(spot.2) * r
                    ctx.fill(Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                             with: .radialGradient(
                                Gradient(colors: [.white.opacity(0.85 * tw), gold.opacity(0.4 * tw), .clear]),
                                center: CGPoint(x: bx - br * 0.3, y: by - br * 0.3),
                                startRadius: 0, endRadius: br))
                }

                // ── 4. Specular highlight (upper-left) ───────────────────────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.56, y: cy - r * 0.76,
                                           width: r * 0.42, height: r * 0.28)),
                    with: .radialGradient(
                        Gradient(colors: [.white.opacity(0.55), .clear]),
                        center: CGPoint(x: cx - r * 0.38, y: cy - r * 0.64),
                        startRadius: 0, endRadius: r * 0.30))
            }
        }
    }

    // =========================================================================
    // MARK: - Spectrum  (Spectrum seasonal · Legendary)
    // A bold, glossy six-colour rainbow sphere — vivid red/orange/yellow/green/
    // blue/violet bands running top→bottom, shaded into a sphere by a radial
    // overlay, with a bright specular highlight for a wet-gloss finish.
    // Animated: the bands flow continuously upward so every point on the
    // sphere cycles through the full spectrum, and a soft light sheen sweeps
    // across the gloss.  Under Reduce Motion the bands hold their original
    // top→bottom layout — exactly the original static spectrum.
    // Clipped to a circle by the body switch caller.
    // =========================================================================
    private var spectrumCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                // Band flow — fraction of one full six-band cycle scrolled so
                // far.  Zero under Reduce Motion → original band positions.
                let phase: Double = reduceMotion ? 0.0 : (t * 0.09).truncatingRemainder(dividingBy: 1.0)

                let w  = size.width
                let h  = size.height
                let cx = w / 2
                let cy = h / 2
                let r  = min(w, h) / 2

                // ── 1. Six vivid rainbow bands, flowing upward ───────────────
                // Twelve tiles (two spectra) scroll by `offsetY`; at phase 0
                // tiles 0–5 sit exactly where the static bands did.
                let bands: [Color] = [
                    Color(red: 0.93, green: 0.16, blue: 0.16),   // red
                    Color(red: 0.97, green: 0.55, blue: 0.10),   // orange
                    Color(red: 0.99, green: 0.84, blue: 0.10),   // yellow
                    Color(red: 0.18, green: 0.72, blue: 0.28),   // green
                    Color(red: 0.13, green: 0.42, blue: 0.92),   // blue
                    Color(red: 0.52, green: 0.16, blue: 0.78),   // violet
                ]
                let bandH: CGFloat = h / CGFloat(bands.count)
                let offsetY: CGFloat = CGFloat(phase) * h
                for i in 0..<12 {
                    let yy: CGFloat = CGFloat(i) * bandH - offsetY
                    if yy > h || yy + bandH + 1 < 0 { continue }
                    let col: Color = bands[i % 6]
                    ctx.fill(Path(CGRect(x: 0, y: yy, width: w, height: bandH + 1)),
                             with: .color(col))
                }

                // ── 2. Sphere-shade overlay (lit upper-left, dark rim) ───────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .white.opacity(0.34),  location: 0.00),
                            .init(color: .clear,                location: 0.42),
                            .init(color: .black.opacity(0.18),  location: 0.80),
                            .init(color: .black.opacity(0.52),  location: 1.00),
                        ]),
                        center: CGPoint(x: cx - r * 0.24, y: cy - r * 0.28),
                        startRadius: 0, endRadius: r * 1.24))

                // ── 2b. Sweeping light sheen across the gloss ────────────────
                //     (skipped entirely under Reduce Motion → static fallback)
                if !reduceMotion {
                    let sweep: Double = sin(t * 0.55)
                    let shX: CGFloat = cx + CGFloat(sweep) * r * 0.60
                    let shO: Double = 0.14 + 0.06 * sin(t * 0.55 * 2.0)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: shX - r * 0.34, y: cy - r * 0.95,
                                               width: r * 0.68, height: r * 1.90)),
                        with: .radialGradient(
                            Gradient(colors: [Color.white.opacity(shO), .clear]),
                            center: CGPoint(x: shX, y: cy - r * 0.10),
                            startRadius: 0, endRadius: r * 0.75))
                }

                // ── 3. Bright wet-gloss specular highlight (upper-left) ───────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.56, y: cy - r * 0.78,
                                           width: r * 0.46, height: r * 0.30)),
                    with: .radialGradient(
                        Gradient(colors: [.white.opacity(0.9), .white.opacity(0.25), .clear]),
                        center: CGPoint(x: cx - r * 0.38, y: cy - r * 0.66),
                        startRadius: 0, endRadius: r * 0.32))
            }
        }
    }

    // =========================================================================
    // MARK: - Oktoberfest
    // Bavarian blue-and-white diamond (lozenge) pattern with warm pretzel-gold
    // accent lines and a creamy foam-like highlight along the top.  Festive
    // beer-hall feel.  Animated: the gold lattice shimmers under a slow gloss
    // sweep, the foam cap bobs gently, and a few beer bubbles rise up into it.
    // Under Reduce Motion the stein settles — exactly the original static
    // pattern.
    // =========================================================================
    private var oktoberfestCanvas: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t: Double = reduceMotion ? 0.0 : tl.date.timeIntervalSinceReferenceDate
                // Lozenge-grid shimmer — 0.55 is the original static opacity.
                let gridGlow: Double = reduceMotion ? 0.55 : 0.45 + 0.20 * (0.5 + 0.5 * sin(t * 1.1))
                // Foam bob — zero under Reduce Motion → original foam position.
                let bobPhase: Double = reduceMotion ? 0.0 : sin(t * 0.8)

                let w  = size.width
                let h  = size.height
                let cx = w / 2
                let cy = h / 2
                let r  = min(w, h) / 2
                let bob: CGFloat = CGFloat(bobPhase) * r * 0.045

                // ── 1. Creamy white base ─────────────────────────────────────
                ctx.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                         with: .color(Color(red: 0.98, green: 0.97, blue: 0.92)))

                // ── 2. Bavarian blue lozenge (diamond) lattice ───────────────
                let blue  = Color(red: 0.13, green: 0.42, blue: 0.82)
                let gold  = Color(red: 0.80, green: 0.58, blue: 0.18)
                let cell  = w / 4.0                  // diamond half-pitch
                // Tile diamonds so that alternating cells are filled blue.
                var row = -1
                var y = -cell
                while y < h + cell {
                    var col = 0
                    var x = -cell
                    while x < w + cell {
                        if (row + col) % 2 == 0 {
                            var dia = Path()
                            dia.move(to:    CGPoint(x: x,             y: y - cell))
                            dia.addLine(to: CGPoint(x: x + cell,      y: y))
                            dia.addLine(to: CGPoint(x: x,             y: y + cell))
                            dia.addLine(to: CGPoint(x: x - cell,      y: y))
                            dia.closeSubpath()
                            ctx.fill(dia, with: .color(blue))
                        }
                        x += cell
                        col += 1
                    }
                    y += cell
                    row += 1
                }

                // ── 3. Warm pretzel-gold accent lines along the diamond grid ─
                var grid = Path()
                var gx = -cell
                while gx < w + cell {
                    grid.move(to:    CGPoint(x: gx,            y: 0))
                    grid.addLine(to: CGPoint(x: gx + h,       y: h))   // ╲ diagonal
                    grid.move(to:    CGPoint(x: gx,            y: h))
                    grid.addLine(to: CGPoint(x: gx + h,       y: 0))   // ╱ diagonal
                    gx += cell
                }
                ctx.stroke(grid, with: .color(gold.opacity(gridGlow)), lineWidth: 1.0)

                // ── 3b. Lozenge shimmer sweep — a soft gloss band gliding
                //     across the lattice.  Skipped under Reduce Motion.
                if !reduceMotion {
                    let sweepCycle: Double = (t * 0.24).truncatingRemainder(dividingBy: 1.5)
                    let bandX: CGFloat = cx - r * 1.4 + CGFloat(sweepCycle) * r * 2.2
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: bandX - r * 0.24, y: cy - r * 1.1,
                                               width: r * 0.48, height: r * 2.2)),
                        with: .linearGradient(
                            Gradient(colors: [.clear, .white.opacity(0.18), .clear]),
                            startPoint: CGPoint(x: bandX - r * 0.24, y: cy),
                            endPoint:   CGPoint(x: bandX + r * 0.24, y: cy)))
                }

                // ── 3c. Rising beer bubbles — small cream rings drifting up
                //     from the base and vanishing into the foam cap.
                //     (skipped entirely under Reduce Motion → static fallback)
                if !reduceMotion {
                    let cream = Color(red: 1.00, green: 0.99, blue: 0.94)
                    for i in 0..<7 {
                        let seed: Double  = Double(i) * 0.83 + 0.29
                        let speed: Double = 0.12 + 0.05 * Double(i % 3)
                        let cycle: Double = (t * speed + seed).truncatingRemainder(dividingBy: 1.0)
                        let sway: Double  = sin(t * 1.1 + seed * 5.0)
                        let drift: CGFloat = CGFloat(seed.truncatingRemainder(dividingBy: 0.7) - 0.35)
                        let px: CGFloat = cx + drift * r * 2.0 + CGFloat(sway) * r * 0.05
                        let py: CGFloat = cy + r * 0.85 - CGFloat(cycle) * r * 1.55
                        let fade: Double = 0.55 * min(1.0, cycle * 6.0) * min(1.0, (1.0 - cycle) * 3.0)
                        let bs: CGFloat = r * (0.030 + 0.016 * CGFloat(i % 3))
                        ctx.stroke(Path(ellipseIn: CGRect(x: px - bs, y: py - bs,
                                                          width: bs * 2, height: bs * 2)),
                                   with: .color(cream.opacity(fade)),
                                   lineWidth: max(0.6, r * 0.02))
                    }
                }

                // ── 4. Creamy foam highlight along the top (bobbing gently) ──
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.80, y: cy - r * 1.02 + bob,
                                           width: r * 1.60, height: r * 0.70)),
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 1.0, green: 0.99, blue: 0.95).opacity(0.85),
                                          .white.opacity(0.25), .clear]),
                        center: CGPoint(x: cx, y: cy - r * 0.66 + bob),
                        startRadius: 0, endRadius: r * 0.92))

                // ── 5. Sphere-shade overlay (lit upper-left, dark rim) ───────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .white.opacity(0.30),  location: 0.00),
                            .init(color: .clear,                location: 0.44),
                            .init(color: .black.opacity(0.18),  location: 0.82),
                            .init(color: .black.opacity(0.50),  location: 1.00),
                        ]),
                        center: CGPoint(x: cx - r * 0.24, y: cy - r * 0.30),
                        startRadius: 0, endRadius: r * 1.22))

                // ── 6. Bright wet-gloss specular highlight (upper-left) ──────
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - r * 0.56, y: cy - r * 0.76,
                                           width: r * 0.44, height: r * 0.28)),
                    with: .radialGradient(
                        Gradient(colors: [.white.opacity(0.85), .white.opacity(0.2), .clear]),
                        center: CGPoint(x: cx - r * 0.38, y: cy - r * 0.64),
                        startRadius: 0, endRadius: r * 0.30))
            }
        }
    }

    // =========================================================================
    // MARK: - Teacher's Apple
    // Glossy classic-red apple with a small green leaf and brown stem at the
    // top and a bright specular highlight.  Clean and cheerful.  Static.
    // =========================================================================
    private var appleCanvas: some View {
        Canvas { ctx, size in
            let w  = size.width
            let h  = size.height
            let cx = w / 2
            let cy = h / 2
            let r  = min(w, h) / 2

            // ── 1. Rounded apple-red body (radial shading) ───────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.97, green: 0.32, blue: 0.28), location: 0.00),
                        .init(color: Color(red: 0.88, green: 0.13, blue: 0.14), location: 0.46),
                        .init(color: Color(red: 0.60, green: 0.05, blue: 0.09), location: 0.84),
                        .init(color: Color(red: 0.34, green: 0.03, blue: 0.06), location: 1.00),
                    ]),
                    center: CGPoint(x: cx - r * 0.22, y: cy - r * 0.24),
                    startRadius: 0, endRadius: r * 1.18))

            // ── 2. Subtle dimple shading at the top (apple navel) ────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r * 0.30, y: cy - r * 0.92,
                                       width: r * 0.60, height: r * 0.40)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 0.40, green: 0.03, blue: 0.06).opacity(0.55), .clear]),
                    center: CGPoint(x: cx, y: cy - r * 0.74),
                    startRadius: 0, endRadius: r * 0.36))

            // ── 3. Brown stem ───────────────────────────────────────────
            var stem = Path()
            stem.move(to:    CGPoint(x: cx - r * 0.05, y: cy - r * 0.72))
            stem.addQuadCurve(to: CGPoint(x: cx + r * 0.08, y: cy - r * 1.02),
                              control: CGPoint(x: cx - r * 0.02, y: cy - r * 0.92))
            ctx.stroke(stem,
                       with: .color(Color(red: 0.42, green: 0.26, blue: 0.10)),
                       style: StrokeStyle(lineWidth: max(2, r * 0.10), lineCap: .round))

            // ── 4. Small green leaf beside the stem ──────────────────────
            var leaf = Path()
            let lx = cx + r * 0.10
            let ly = cy - r * 0.88
            leaf.move(to: CGPoint(x: lx, y: ly))
            leaf.addQuadCurve(to: CGPoint(x: lx + r * 0.42, y: ly - r * 0.18),
                              control: CGPoint(x: lx + r * 0.22, y: ly - r * 0.34))
            leaf.addQuadCurve(to: CGPoint(x: lx, y: ly),
                              control: CGPoint(x: lx + r * 0.22, y: ly + r * 0.04))
            ctx.fill(leaf, with: .linearGradient(
                Gradient(colors: [Color(red: 0.36, green: 0.72, blue: 0.30),
                                  Color(red: 0.18, green: 0.52, blue: 0.20)]),
                startPoint: CGPoint(x: lx, y: ly - r * 0.2),
                endPoint:   CGPoint(x: lx + r * 0.42, y: ly + r * 0.05)))
            // leaf mid-vein
            var vein = Path()
            vein.move(to: CGPoint(x: lx + r * 0.02, y: ly - r * 0.02))
            vein.addQuadCurve(to: CGPoint(x: lx + r * 0.38, y: ly - r * 0.16),
                              control: CGPoint(x: lx + r * 0.22, y: ly - r * 0.16))
            ctx.stroke(vein, with: .color(Color(red: 0.14, green: 0.40, blue: 0.16).opacity(0.7)),
                       lineWidth: 0.8)

            // ── 5. Sphere-shade rim ─────────────────────────────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .clear,               location: 0.55),
                        .init(color: .black.opacity(0.14), location: 0.84),
                        .init(color: .black.opacity(0.46), location: 1.00),
                    ]),
                    center: CGPoint(x: cx - r * 0.20, y: cy - r * 0.24),
                    startRadius: 0, endRadius: r * 1.18))

            // ── 6. Bright wet-gloss specular highlight (upper-left) ──────
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - r * 0.58, y: cy - r * 0.62,
                                       width: r * 0.50, height: r * 0.34)),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.92), .white.opacity(0.3), .clear]),
                    center: CGPoint(x: cx - r * 0.38, y: cy - r * 0.50),
                    startRadius: 0, endRadius: r * 0.34))
        }
    }
}
