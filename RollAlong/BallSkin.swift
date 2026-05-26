import SwiftUI

enum BallSkin: String, CaseIterable, Identifiable {
    case red    = "Classic Red"
    case blue   = "Ocean Blue"
    case green  = "Jade Green"
    case gold   = "Fool's Gold"
    case purple = "Deep Purple"
    case galaxy = "Galaxy"

    var id: String { rawValue }

    func gradient(endRadius: CGFloat) -> RadialGradient {
        RadialGradient(
            colors: colors,
            center: UnitPoint(x: 0.30, y: 0.30),
            startRadius: 0,
            endRadius: endRadius
        )
    }

    private var colors: [Color] {
        switch self {
        case .red:
            return [
                Color(red: 1.00, green: 0.85, blue: 0.85),
                Color(red: 0.95, green: 0.20, blue: 0.20),
                Color(red: 0.55, green: 0.05, blue: 0.05),
                Color(red: 0.25, green: 0.02, blue: 0.02),
            ]
        case .blue:
            return [
                Color(red: 0.78, green: 0.92, blue: 1.00),
                Color(red: 0.18, green: 0.52, blue: 0.96),
                Color(red: 0.05, green: 0.22, blue: 0.68),
                Color(red: 0.02, green: 0.06, blue: 0.36),
            ]
        case .green:
            return [
                Color(red: 0.78, green: 1.00, blue: 0.80),
                Color(red: 0.18, green: 0.82, blue: 0.30),
                Color(red: 0.05, green: 0.50, blue: 0.12),
                Color(red: 0.02, green: 0.22, blue: 0.05),
            ]
        case .gold:
            return [
                Color(red: 1.00, green: 0.98, blue: 0.76),
                Color(red: 1.00, green: 0.80, blue: 0.10),
                Color(red: 0.76, green: 0.56, blue: 0.00),
                Color(red: 0.40, green: 0.28, blue: 0.00),
            ]
        case .purple:
            return [
                Color(red: 0.92, green: 0.76, blue: 1.00),
                Color(red: 0.65, green: 0.15, blue: 0.96),
                Color(red: 0.38, green: 0.05, blue: 0.62),
                Color(red: 0.18, green: 0.02, blue: 0.32),
            ]
        case .galaxy:
            return [
                Color(red: 0.95, green: 0.95, blue: 1.00),
                Color(red: 0.55, green: 0.40, blue: 0.92),
                Color(red: 0.16, green: 0.08, blue: 0.52),
                Color(red: 0.04, green: 0.04, blue: 0.20),
            ]
        }
    }
}
