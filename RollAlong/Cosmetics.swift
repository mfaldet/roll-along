import SwiftUI

// ---------------------------------------------------------------------------
// Cosmetic system — types
//
// Every cosmetic category has its own enum.  Each enum:
//   • Codable (so GameState can persist equipped + owned sets)
//   • CaseIterable (so the shop UI can list everything)
//   • Identifiable (raw string == id)
//   • Default case is always free + always owned (the "starter" item)
//   • Each non-default case has a coin cost or unlock condition
//
// The actual visuals (gradients, particle systems, etc.) are kept in
// BallGameView and Theme — these enums are pure data identifiers.
// ---------------------------------------------------------------------------

protocol CosmeticItem: Hashable, Identifiable, CaseIterable, Codable
    where RawValue == String, ID == String
{
    associatedtype RawValue
    var rawValue: String { get }
    var displayName: String { get }
    var coinCost: Int { get }            // 0 == free / default
    var unlockLevel: Int { get }         // 0 == always available
    static var starter: Self { get }     // default item, always owned
    /// Tier classification.  Shapes the shop layout + which items are
    /// pick-able as the post-tutorial reward.
    var tier: CosmeticTier { get }
}

/// Tier roughly corresponds to price + rarity.
enum CosmeticTier: String, Codable {
    case starter        // free, always owned
    case standard       // earnable with coins, also tutorial-reward eligible
    case premium        // higher coin cost OR paid-only
    case exclusive      // gated behind the $20 unlimited-lives subscription
}

// MARK: - Ball skins
// The existing BallSkin enum stays (in BallSkin.swift).  We attach
// CosmeticItem conformance to it here so the shop can iterate uniformly.
extension BallSkin: CosmeticItem {
    var displayName: String { rawValue }     // already capitalised in raw form
    var coinCost: Int {
        switch self {
        case .red:    return 0
        case .blue:   return 200
        case .green:  return 200
        case .gold:   return 400
        case .purple: return 300
        case .galaxy: return 800
        }
    }
    var unlockLevel: Int { 0 }
    static var starter: BallSkin { .red }
    var tier: CosmeticTier {
        switch self {
        case .red:               return .starter
        case .blue, .green:      return .standard
        case .purple:            return .standard
        case .gold:              return .premium
        case .galaxy:            return .premium
        }
    }
}

// MARK: - Goal skins (alt versions of the rainbow hole)
enum GoalSkin: String, CosmeticItem {
    case rainbow        // default
    case galaxy         // deep-space spiral
    case crystal        // prismatic shards
    case flame          // warm orange/red particles
    case neon           // hot cyan/magenta on black
    case prism          // refracting beams

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .galaxy:  return "Galaxy"
        case .crystal: return "Crystal"
        case .flame:   return "Flame"
        case .neon:    return "Neon"
        case .prism:   return "Prism"
        }
    }

    /// Compact static preview gradient used by the shop + tutorial reward
    /// modal until the full Canvas renderers ship.
    static func previewGradient(for goal: GoalSkin) -> LinearGradient {
        switch goal {
        case .rainbow:
            return LinearGradient(
                colors: [.purple, .blue, .green, .yellow, .red],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .galaxy:
            return LinearGradient(colors: [Color(red:0.12,green:0.05,blue:0.30),
                                           Color(red:0.50,green:0.10,blue:0.50)],
                                  startPoint: .top, endPoint: .bottom)
        case .crystal:
            return LinearGradient(colors: [Color.cyan, Color.white.opacity(0.5)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .flame:
            return LinearGradient(colors: [Color.orange, Color.red],
                                  startPoint: .top, endPoint: .bottom)
        case .neon:
            return LinearGradient(colors: [Color(red:0.95, green:0.10, blue:0.95),
                                           Color(red:0.10, green:0.90, blue:0.95)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .prism:
            return LinearGradient(colors: [Color.white, Color.pink.opacity(0.6), Color.blue.opacity(0.6)],
                                  startPoint: .leading, endPoint: .trailing)
        }
    }
    var coinCost: Int {
        switch self {
        case .rainbow: return 0
        case .galaxy:  return 400
        case .crystal: return 400
        case .flame:   return 400
        case .neon:    return 600
        case .prism:   return 800
        }
    }
    var unlockLevel: Int { 0 }
    static var starter: GoalSkin { .rainbow }
    var tier: CosmeticTier {
        switch self {
        case .rainbow: return .starter
        case .galaxy, .crystal, .flame: return .standard
        case .neon:    return .standard
        case .prism:   return .premium
        }
    }
}

// MARK: - Trail colors (the streak left behind the ball)
enum TrailColor: String, CosmeticItem {
    case none           // default — no trail
    case graphite       // matches Paper world's classic lead trail
    case rainbow
    case fire
    case ice
    case ink
    case gold

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none:     return "Off"
        case .graphite: return "Graphite"
        case .rainbow:  return "Rainbow"
        case .fire:     return "Fire"
        case .ice:      return "Ice"
        case .ink:      return "Ink"
        case .gold:     return "Gold"
        }
    }
    var coinCost: Int {
        switch self {
        case .none, .graphite: return 0       // graphite is the original
        case .rainbow:         return 300
        case .fire, .ice:      return 250
        case .ink:             return 200
        case .gold:            return 500
        }
    }
    var unlockLevel: Int { 0 }
    static var starter: TrailColor { .none }
    var tier: CosmeticTier {
        switch self {
        case .none:                  return .starter
        case .graphite:              return .starter
        case .ink, .fire, .ice:      return .standard
        case .rainbow:               return .standard
        case .gold:                  return .premium
        }
    }

    /// SwiftUI Color used when rendering this trail.  `.none` returns clear.
    var color: Color {
        switch self {
        case .none:     return .clear
        case .graphite: return Color(red: 0.20, green: 0.20, blue: 0.22).opacity(0.70)
        case .rainbow:  return .pink   // actual rainbow is a Canvas effect
        case .fire:     return Color(red: 0.95, green: 0.42, blue: 0.10).opacity(0.75)
        case .ice:      return Color(red: 0.55, green: 0.78, blue: 1.00).opacity(0.75)
        case .ink:      return Color(red: 0.09, green: 0.09, blue: 0.14).opacity(0.80)
        case .gold:     return Color(red: 0.95, green: 0.70, blue: 0.20).opacity(0.85)
        }
    }
}

// MARK: - Background themes (replaces the auto-by-level theme bands)
enum BackgroundTheme: String, CosmeticItem {
    case classic        // default
    case inverted
    case twilight
    case ember
    case aurora
    case notebook
    case graph
    case parchment
    case sketch
    case origami

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classic:   return "Classic"
        case .inverted:  return "Inverted"
        case .twilight:  return "Twilight"
        case .ember:     return "Ember"
        case .aurora:    return "Aurora"
        case .notebook:  return "Notebook"
        case .graph:     return "Graph"
        case .parchment: return "Parchment"
        case .sketch:    return "Sketch"
        case .origami:   return "Origami"
        }
    }
    var coinCost: Int {
        switch self {
        case .classic:   return 0
        case .inverted:  return 300
        case .twilight:  return 400
        case .ember:     return 400
        case .aurora:    return 700
        case .notebook:  return 500
        case .graph:     return 500
        case .parchment: return 600
        case .sketch:    return 600
        case .origami:   return 800
        }
    }
    var unlockLevel: Int { 0 }
    static var starter: BackgroundTheme { .classic }
    var tier: CosmeticTier {
        switch self {
        case .classic:               return .starter
        case .inverted, .ember, .twilight: return .standard
        case .notebook, .graph:      return .standard
        case .parchment, .sketch:    return .standard
        case .aurora, .origami:      return .premium
        }
    }
}

// MARK: - Music tracks (genres — actual audio files arrive in V1.1)
enum MusicTrack: String, CosmeticItem {
    case none           // default — silent
    case ambient
    case piano
    case chiptune
    case lofi

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none:     return "Off"
        case .ambient:  return "Ambient"
        case .piano:    return "Piano"
        case .chiptune: return "Chiptune"
        case .lofi:     return "Lo-fi"
        }
    }
    var coinCost: Int {
        switch self {
        case .none, .ambient: return 0
        case .piano:          return 400
        case .chiptune:       return 400
        case .lofi:           return 500
        }
    }
    var unlockLevel: Int { 0 }
    static var starter: MusicTrack { .none }
    var tier: CosmeticTier {
        switch self {
        case .none, .ambient: return .starter
        case .piano, .chiptune, .lofi: return .standard
        }
    }
}
