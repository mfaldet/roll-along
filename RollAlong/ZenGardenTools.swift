import SwiftUI

// ===========================================================================
// ZenGardenTools — the Zen Garden's tool palette + auto-pattern engine +
// decoration props.  All Zen-only; BallGameView owns the @State and drives the
// ball, this file owns the types, the bottom-right dropdown UI, and the prop
// rendering so the shared engine stays lean.
//
//   • ZenPattern  — full-coverage auto-track paths (rows, columns, spiral).
//                   BallGameView advances a progress each tick and reads
//                   `point(progress:in:)` to drive the ball along the path.
//   • ZenSpeedBar — continuous drag bar (upper-right) that sets how fast the
//                   auto-track advances.
//   • ZenItem     — placeable decorations (stones, pavers, bonsai, lantern…).
//   • ZenToolsOverlay — the bottom-right "drop down" button that pops a list of
//                   tools above it (wind ▸ pattern ▸ tree), each with its own
//                   sub-options panel.
//   • ZenDecorationLayer — renders the placed props on the sand.
// ===========================================================================

// MARK: - Pattern

/// Full-coverage auto-track paths.  Each pattern is one LARGE space-filling
/// rake sweep that spans the whole garden with evenly spaced lanes and minimal
/// retracing — the geometric "lawn-mowing" look — not a small motif.  `progress`
/// counts full coverages (integer part = passes done, fraction = position along
/// the current pass); the polyline is arc-length parametrised so the ball moves
/// at an even pace.  Speed is set separately by the ZenSpeedBar.
enum ZenPattern: String, CaseIterable, Identifiable {
    case rows, columns, spiral
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rows:    return "Rows"
        case .columns: return "Columns"
        case .spiral:  return "Spiral"
        }
    }

    var icon: String {
        switch self {
        case .rows:    return "line.3.horizontal"
        case .columns: return "rectangle.split.3x1"
        case .spiral:  return "hurricane"
        }
    }

    /// The ball's position along this pattern at `progress`, in `size`'s
    /// coordinates.  `progress` counts full coverages; each successive lap is
    /// shifted a golden-ratio fraction of a lane (perpendicular to the grooves)
    /// so the rake never retraces the same line — it fills the ridges between
    /// lanes, densifying toward a fully-raked, touching-groove garden.
    func point(progress: Double, in size: CGSize) -> CGPoint {
        let lap = progress.rounded(.down)
        var u = progress - lap
        if u < 0 { u += 1 }
        let offsetFrac = (lap * 0.6180339887498949).truncatingRemainder(dividingBy: 1)
        let pts = pathPoints(in: size, offsetFrac: offsetFrac)
        guard pts.count > 1 else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        var total: CGFloat = 0
        for i in 1..<pts.count { total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
        guard total > 0 else { return pts[0] }
        var target = CGFloat(u) * total
        for i in 1..<pts.count {
            let seg = hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            if target <= seg {
                let t = seg > 0 ? target / seg : 0
                return CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
                               y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t)
            }
            target -= seg
        }
        return pts[pts.count - 1]
    }

    /// One pass as a polyline in `size`'s pixel space.  `offsetFrac` (0…1)
    /// shifts the lanes/rings perpendicular by that fraction of a gap so each
    /// lap lays fresh grooves in the ridges rather than retracing.
    func pathPoints(in size: CGSize, offsetFrac: Double = 0) -> [CGPoint] {
        let w = Double(size.width), h = Double(size.height)
        let m = min(w, h) * 0.075
        let x0 = m, y0 = m, x1 = w - m, y1 = h - m
        let gap = min(w, h) * 0.05            // tight rake-tine spacing
        let off = gap * offsetFrac
        switch self {
        case .rows:    return Self.serpentine(x0, y0, x1, y1, gap: gap, offset: off, horizontal: true)
        case .columns: return Self.serpentine(x0, y0, x1, y1, gap: gap, offset: off, horizontal: false)
        case .spiral:  return Self.rectSpiral(x0, y0, x1, y1, gap: gap, offset: off)
        }
    }

    /// Boustrophedon (back-and-forth lanes) with rounded U-turns, at a FIXED
    /// `gap`, the first lane `offset` in from the top.  `horizontal` sweeps
    /// left/right down the rows; the vertical form is the same path transposed.
    private static func serpentine(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                                   gap: Double, offset: Double, horizontal: Bool) -> [CGPoint] {
        if !horizontal {
            return serpentine(y0, x0, y1, x1, gap: gap, offset: offset, horizontal: true).map { CGPoint(x: $0.y, y: $0.x) }
        }
        var pts: [CGPoint] = []
        let r = gap / 2
        var y = y0 + offset
        var i = 0
        while y <= y1 + 0.01 {
            let ltr = i % 2 == 0
            pts.append(CGPoint(x: ltr ? x0 : x1, y: y))
            pts.append(CGPoint(x: ltr ? x1 : x0, y: y))
            let ny = y + gap
            if ny <= y1 + 0.01 {                        // rounded U-turn into the next lane
                let xEdge = ltr ? x1 : x0
                let sign  = ltr ? 1.0 : -1.0
                let yc = y + r
                for k in 1...8 {
                    let th = -Double.pi / 2 + Double.pi * Double(k) / 8
                    pts.append(CGPoint(x: xEdge + sign * r * cos(th), y: yc + r * sin(th)))
                }
            }
            y = ny
            i += 1
        }
        return pts
    }

    /// Rectangular concentric spiral inward, its outer ring inset by `offset`.
    private static func rectSpiral(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                                   gap: Double, offset: Double) -> [CGPoint] {
        var (a, b, c, d) = (x0 + offset, y0 + offset, x1 - offset, y1 - offset)
        var pts: [CGPoint] = [CGPoint(x: a, y: b)]
        while c - a > gap && d - b > gap {
            pts.append(CGPoint(x: c, y: b))
            pts.append(CGPoint(x: c, y: d))
            pts.append(CGPoint(x: a, y: d))
            pts.append(CGPoint(x: a, y: b + gap))
            a += gap; b += gap; c -= gap; d -= gap
            pts.append(CGPoint(x: a, y: b))
        }
        return pts
    }
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
            // Mirror the game's white home button (bottom-left): a subtle
            // dark-grey glyph on a white circle, so the tools toggle reads as a
            // clean white button rather than the old brown chevron-in-circle.
            Image(systemName: menuOpen ? "chevron.down" : "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(white: 0.38))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color(white: 1.0, opacity: 0.85))
                        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                )
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

/// Continuous speed control for the auto-track — a vertical drag bar on the
/// upper-right.  Drag up to send the rake faster along its pattern, down to
/// slow it.  Shown only while a pattern is running.
struct ZenSpeedBar: View {
    @Binding var fraction: Double        // 0 = slow, 1 = fast
    let haptics: Bool

    private let sand = Color(red: 0.52, green: 0.43, blue: 0.28)

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hare.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(sand)
            GeometryReader { geo in
                let h = geo.size.height
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color(white: 1.0, opacity: 0.85))
                    Capsule()
                        .fill(Color(red: 0.34, green: 0.60, blue: 0.42))
                        .frame(height: max(14, h * CGFloat(fraction)))
                }
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let f = 1 - Double(v.location.y / max(h, 1))
                            let clamped = min(max(f, 0), 1)
                            if haptics && abs(clamped - fraction) > 0.1 { Haptics.soft() }
                            fraction = clamped
                        }
                )
            }
            .frame(width: 12)
            Image(systemName: "tortoise.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(sand)
        }
        .frame(height: 210)
        .accessibilityLabel("Auto-track speed")
    }
}

/// Which tool sub-panel is showing in the Zen dropdown.
enum ZenSubmenu { case none, pattern, items }
