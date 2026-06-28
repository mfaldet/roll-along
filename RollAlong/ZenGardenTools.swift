import SwiftUI

// ===========================================================================
// ZenGardenTools — the Zen Garden's tool palette + auto-pattern engine +
// decoration props.  All Zen-only; BallGameView owns the @State and drives the
// ball, this file owns the types, the bottom-right dropdown UI, and the prop
// rendering so the shared engine stays lean.
//
//   • ZenPattern  — parametric auto-track paths (circle, figure-8, spiral,
//                   rose, square).  BallGameView advances a phase each tick and
//                   reads `point(phase:in:)` to drive the ball along the path.
//   • ZenSpeed    — how fast the phase advances on an auto-track.
//   • ZenItem     — placeable decorations (stones, pavers, bonsai, lantern…).
//   • ZenToolsOverlay — the bottom-right "drop down" button that pops a list of
//                   tools above it (wind ▸ pattern ▸ tree), each with its own
//                   sub-options panel.
//   • ZenDecorationLayer — renders the placed props on the sand.
// ===========================================================================

// MARK: - Pattern

/// Parametric auto-track paths.  `phase` is an angle in radians advanced over
/// time; one full loop is 2π.  Returns a point in arena (point) coordinates.
enum ZenPattern: String, CaseIterable, Identifiable {
    case circle, figureEight, spiral, rose, square
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .circle:      return "Circle"
        case .figureEight: return "Figure 8"
        case .spiral:      return "Spiral"
        case .rose:        return "Rose"
        case .square:      return "Square"
        }
    }

    var icon: String {
        switch self {
        case .circle:      return "circle"
        case .figureEight: return "infinity"
        case .spiral:      return "hurricane"
        case .rose:        return "camera.macro"
        case .square:      return "square"
        }
    }

    /// The ball's position on this path at `phase`, centred in `size`.
    ///
    /// Each pattern is a fast LOCAL motif (its signature shape) riding a slow
    /// full-screen DRIFT.  The drift is a Lissajous sweep whose two frequencies
    /// are in the golden ratio — an irrational ratio, so the trajectory never
    /// exactly repeats and is *dense* in the screen rectangle.  Left running,
    /// every pattern therefore eventually rakes the entire garden (a space-
    /// filling sweep, in the spirit of the requested fractal fill) rather than
    /// retracing one closed loop forever.
    func point(phase: Double, in size: CGSize) -> CGPoint {
        let w = Double(size.width), h = Double(size.height)
        let brushR = min(w, h) * 0.14            // size of the local motif
        let margin = brushR + 10
        let ampX = max(0, w / 2 - margin)
        let ampY = max(0, h / 2 - margin)

        // Slow drift across the whole interior.  φ = golden ratio makes the two
        // axes incommensurate → dense (eventually visits everywhere).
        let drift = 0.20
        let phi   = 1.6180339887498949
        let cx = w / 2 + ampX * sin(phase * drift)
        let cy = h / 2 + ampY * sin(phase * drift * phi + .pi / 2)

        // Fast local motif — stamped as the drift carries it across the sand.
        let a = phase * 5
        let m = motif(a, r: brushR)
        return CGPoint(x: CGFloat(cx + m.dx), y: CGFloat(cy + m.dy))
    }

    /// The pattern's signature shape as an (dx, dy) offset from the drifting
    /// centre, at brush radius `r`.
    private func motif(_ a: Double, r: Double) -> (dx: Double, dy: Double) {
        switch self {
        case .circle:
            return (r * cos(a), r * sin(a))
        case .figureEight:
            return (r * sin(a), r * 0.6 * sin(2 * a))
        case .spiral:
            // Spiral out then back in over 3 turns (triangle wave on radius).
            let turns = 3.0
            let frac = (a / (2 * .pi * turns)).truncatingRemainder(dividingBy: 1.0)
            let tri = 1 - abs(2 * frac - 1)                 // 0→1→0
            let rr = r * (0.15 + 0.85 * tri)
            return (rr * cos(a), rr * sin(a))
        case .rose:
            let rr = r * cos(2 * a)                          // 4-petal rosette
            return (rr * cos(a), rr * sin(a))
        case .square:
            // Walk the perimeter of a square of half-size r, one lap per 2π.
            let s = (a / (2 * .pi)).truncatingRemainder(dividingBy: 1.0)
            let seg = s * 4
            let side = Int(seg)
            let f = seg - Double(side)
            switch side {
            case 0:  return (-r + 2 * r * f, -r)            // top L→R
            case 1:  return ( r,             -r + 2 * r * f) // right ↓
            case 2:  return ( r - 2 * r * f,  r)            // bottom R→L
            default: return (-r,              r - 2 * r * f) // left ↑
            }
        }
    }
}

/// How fast an auto-track advances (radians / second).
enum ZenSpeed: String, CaseIterable, Identifiable {
    case slow, medium, fast
    var id: String { rawValue }
    var rate: Double {
        switch self {
        case .slow:   return 0.5
        case .medium: return 1.0
        case .fast:   return 1.9
        }
    }
    var icon: String {
        switch self {
        case .slow:   return "tortoise.fill"
        case .medium: return "figure.walk"
        case .fast:   return "hare.fill"
        }
    }
    var label: String { rawValue.capitalized }
}

// MARK: - Decorations

/// A placeable Zen-garden prop.
enum ZenItem: String, CaseIterable, Identifiable {
    case stone, pebbles, pavers, bonsai, lantern, bamboo
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .stone:   return "Stone"
        case .pebbles: return "Pebbles"
        case .pavers:  return "Pavers"
        case .bonsai:  return "Bonsai"
        case .lantern: return "Lantern"
        case .bamboo:  return "Bamboo"
        }
    }
    var icon: String {
        switch self {
        case .stone:   return "circle.fill"
        case .pebbles: return "circle.grid.2x2.fill"
        case .pavers:  return "square.grid.2x2.fill"
        case .bonsai:  return "leaf.fill"
        case .lantern: return "lightbulb.fill"
        case .bamboo:  return "line.diagonal"
        }
    }
}

/// One placed prop, positioned as unit fractions of the arena so it survives
/// rotation / resize.
struct ZenDecoration: Identifiable, Equatable {
    let id = UUID()
    let item: ZenItem
    let pos: CGPoint   // fractional (0…1)
}

/// Renders all placed props on the sand.  Sits below the ball so the marble
/// rolls over them.
struct ZenDecorationLayer: View {
    let decorations: [ZenDecoration]
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(decorations) { d in
                ZenItemView(item: d.item)
                    .position(x: d.pos.x * size.width, y: d.pos.y * size.height)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The drawn appearance of a single prop — simple shapes so it reads on sand
/// without art assets.
struct ZenItemView: View {
    let item: ZenItem

    var body: some View {
        switch item {
        case .stone:
            Ellipse()
                .fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.40)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 38, height: 30)
                .overlay(Ellipse().fill(.white.opacity(0.35)).frame(width: 12, height: 7)
                    .offset(x: -6, y: -6))
                .overlay(Ellipse().stroke(.black.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        case .pebbles:
            ZStack {
                pebble(.init(white: 0.58), 16, x: -8, y: 2)
                pebble(.init(white: 0.70), 13, x: 7, y: -4)
                pebble(.init(white: 0.50), 14, x: 4, y: 8)
            }
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        case .pavers:
            let c = Color(red: 0.55, green: 0.52, blue: 0.48)
            VStack(spacing: 3) {
                HStack(spacing: 3) { paver(c); paver(c) }
                HStack(spacing: 3) { paver(c); paver(c) }
            }
            .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
        case .bonsai:
            ZStack {
                Capsule().fill(Color(red: 0.45, green: 0.30, blue: 0.18))
                    .frame(width: 6, height: 20).offset(y: 8)
                Circle().fill(Color(red: 0.24, green: 0.52, blue: 0.28))
                    .frame(width: 34, height: 26).offset(y: -6)
                Circle().fill(Color(red: 0.30, green: 0.62, blue: 0.34))
                    .frame(width: 20, height: 16).offset(x: -8, y: -12)
                Circle().fill(Color(red: 0.30, green: 0.62, blue: 0.34))
                    .frame(width: 18, height: 14).offset(x: 9, y: -10)
            }
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        case .lantern:
            let stone = Color(red: 0.52, green: 0.50, blue: 0.46)
            VStack(spacing: 0) {
                Triangle().fill(stone).frame(width: 26, height: 10)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 1.0, green: 0.86, blue: 0.45))
                    .frame(width: 16, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(stone, lineWidth: 2.5))
                Rectangle().fill(stone).frame(width: 9, height: 14)
            }
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        case .bamboo:
            HStack(alignment: .bottom, spacing: 4) {
                stalk(height: 40)
                stalk(height: 52)
                stalk(height: 34)
            }
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
        }
    }

    private func pebble(_ c: Color, _ d: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(c).frame(width: d, height: d).offset(x: x, y: y)
            .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 0.8).offset(x: x, y: y))
    }
    private func paver(_ c: Color) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 15, height: 15)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.black.opacity(0.18), lineWidth: 0.8))
    }
    private func stalk(height: CGFloat) -> some View {
        Capsule().fill(Color(red: 0.40, green: 0.62, blue: 0.30))
            .frame(width: 6, height: height)
    }
}

/// A simple upward triangle (lantern roof).
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Tools overlay (bottom-right "drop down")

/// The Zen tool palette.  A bottom-right disclosure button pops a vertical list
/// of tools above it — Wind (smooth sand), Pattern, Tree — each revealing its
/// own options panel.  Pure UI: it reads/writes bindings BallGameView owns and
/// calls back for the two actions that touch engine state.
struct ZenToolsOverlay: View {
    @Binding var menuOpen: Bool
    @Binding var submenu: ZenSubmenu
    @Binding var pattern: ZenPattern?
    @Binding var speed: ZenSpeed
    @Binding var placingItem: ZenItem?
    let haptics: Bool
    let onSmoothSand: () -> Void
    let onClearItems: () -> Void

    private let sand   = Color(red: 0.52, green: 0.43, blue: 0.28)   // warm icon brown
    private let active = Color(red: 0.34, green: 0.60, blue: 0.42)   // selected green

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    if menuOpen && submenu == .pattern { patternPanel }
                    if menuOpen && submenu == .items   { itemsPanel }
                    if menuOpen { toolColumn }
                    dropdownButton
                }
            }
            .padding(.trailing, 22)
            .padding(.bottom, 20)
        }
    }

    // The three tools, stacked above the dropdown button.
    private var toolColumn: some View {
        VStack(spacing: 10) {
            toolButton("wind", on: false) {
                submenu = .none
                onSmoothSand()
            }
            toolButton("circle.hexagonpath", on: submenu == .pattern || pattern != nil) {
                tap(); submenu = (submenu == .pattern) ? .none : .pattern
            }
            toolButton("tree.fill", on: submenu == .items || placingItem != nil) {
                tap(); submenu = (submenu == .items) ? .none : .items
            }
        }
        .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
    }

    // MARK: Pattern options

    private var patternPanel: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(ZenPattern.allCases) { p in
                    optionButton(icon: p.icon, on: pattern == p) {
                        tap()
                        pattern = (pattern == p) ? nil : p
                    }
                }
                // Stop the auto-track (back to manual roll).
                optionButton(icon: "stop.fill", on: pattern == nil, tint: Color(red: 0.85, green: 0.4, blue: 0.35)) {
                    tap(); pattern = nil
                }
            }
            HStack(spacing: 8) {
                ForEach(ZenSpeed.allCases) { s in
                    optionButton(icon: s.icon, on: speed == s) { tap(); speed = s }
                }
            }
        }
        .padding(12)
        .background(panelBackground)
        .transition(.scale(scale: 0.7, anchor: .bottomTrailing).combined(with: .opacity))
    }

    // MARK: Item options

    private var itemsPanel: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(ZenItem.allCases) { item in
                    optionButton(icon: item.icon, on: placingItem == item) {
                        tap()
                        placingItem = (placingItem == item) ? nil : item
                    }
                }
            }
            HStack(spacing: 8) {
                optionButton(icon: "trash", on: false,
                             tint: Color(red: 0.85, green: 0.4, blue: 0.35)) {
                    tap(); onClearItems()
                }
            }
        }
        .padding(12)
        .background(panelBackground)
        .transition(.scale(scale: 0.7, anchor: .bottomTrailing).combined(with: .opacity))
    }

    // MARK: Buttons

    private var dropdownButton: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                if menuOpen { submenu = .none }
                menuOpen.toggle()
            }
            tap()
        } label: {
            Image(systemName: menuOpen ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(sand)
                .background(Circle().fill(Color(white: 1.0, opacity: 0.9)).padding(2))
                .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
        }
        .accessibilityLabel(menuOpen ? "Close tools" : "Zen tools")
        .accessibilityHint("Wind to smooth the sand, patterns to auto-roll, and props to decorate.")
    }

    private func toolButton(_ icon: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? .white : sand)
                .frame(width: 38, height: 38)
                .background(Circle().fill(on ? active : Color(white: 1.0, opacity: 0.9)))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
    }

    private func optionButton(icon: String, on: Bool, tint: Color? = nil,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? .white : (tint ?? sand))
                .frame(width: 34, height: 34)
                .background(Circle().fill(on ? (tint ?? active) : Color(white: 1.0, opacity: 0.92)))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color(red: 0.20, green: 0.17, blue: 0.12).opacity(0.85))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    private func tap() { if haptics { Haptics.soft() } }
}

/// Which tool sub-panel is showing in the Zen dropdown.
enum ZenSubmenu { case none, pattern, items }
