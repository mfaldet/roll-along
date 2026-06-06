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
///
/// Pricing is structural — every item in a tier costs the tier's
/// `basePrice`.  Adjust the constants below to re-balance the whole
/// catalogue at once.
///
/// Naming convention exposed to players (in the shop UI) maps to:
///   • standard   → "Standard"
///   • premium    → "Epic"
///   • exclusive  → "Legendary"
enum CosmeticTier: String, Codable {
    case starter        // free, always owned
    case standard       // 50  coins — entry-level skins, tutorial-reward eligible
    case premium        // 200 coins — flashier visuals, mid-grind
    case exclusive      // 500 coins — top-tier, multi-week grind or IAP territory
}

extension CosmeticTier {
    /// Single source of truth for every priceable cosmetic.  An item's
    /// `coinCost` just reads through to `tier.basePrice` — no per-item
    /// overrides.  Keeps the catalogue self-consistent.
    var basePrice: Int {
        switch self {
        case .starter:   return 0
        case .standard:  return 50
        case .premium:   return 200
        case .exclusive: return 500
        }
    }
}

// MARK: - Ball skins
// The existing BallSkin enum stays (in BallSkin.swift).  We attach
// CosmeticItem conformance to it here so the shop can iterate uniformly.
extension BallSkin: CosmeticItem {
    var displayName: String { rawValue }     // already capitalised in raw form
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    static var starter: BallSkin { .red }
    /// Tier rule (player-facing names: Standard / Epic / Legendary):
    ///   • Standard  — mono-shaded marbles (single colour family with
    ///                 light → dark gradient stops, reads as one colour).
    ///   • Epic      — multi-colour marbles whose stops span distinct
    ///                 hues (the gradient blends two or more colours
    ///                 that all read individually).
    ///   • Legendary — animated / special-effect renderers (e.g. the
    ///                 Snowglobe marble's in-game Canvas).
    var tier: CosmeticTier {
        switch self {
        case .red:
            return .starter
        case .blue, .green, .purple, .rose, .coral, .mint, .slate, .lemon,
             .gold, .silver, .copper, .jade, .ruby:
            return .standard   //  50 coins — all mono-shaded
        case .galaxy, .nebula, .opal,
             .earth, .mars, .saturn, .mercury,
             .neptune, .jupiter, .venus, .uranus:
            return .premium    // 200 coins — multi-colour blends / planets
        case .snowglobe, .golfBall, .pluto, .ufo:
            return .exclusive  // 500 coins — animated / special / bundle-only
        }
    }
}

// MARK: - Goal skins
//
// Three rendering paths exist in BallGameView:
//
//   • `.target`  → simpleBullseyeTarget  (the new default — a clean
//                  3-ring red/white/red bullseye, static)
//   • `.archery` → archeryTargetGoal     (FITA-style 5-band target,
//                  white/black/blue/red/yellow with the breathing scale)
//   • every other case → rainbowHole     (the particle-Canvas portal
//                  whose colours come from `holeStyle`)
//
// `.rainbow` is back as the original full-spectrum sparkly portal —
// now an Epic-tier purchasable, not the default.
//
// rawValue strings are persistence keys — don't rename existing cases.
enum GoalSkin: String, CosmeticItem {
    // Starter — new default
    case target         // clean 3-ring red/white/red

    // Standard (50 coins) — particle portals + the FITA archery target
    case archery        // 5-band FITA target (was the default during dev)
    case galaxy         // deep-space spiral
    case crystal        // prismatic shards
    case flame          // warm orange/red particles
    case blossom        // pinks + corals (cherry-blossom palette)
    case mosaic         // muted multi-hue particles
    case ripple         // blue-cyan calm
    case comet          // pale white-blue streaks on near-black

    // Premium / Epic (200 coins)
    case rainbow        // ★ the sparkly full-spectrum portal (restored)
    case neon           // hot magenta-pink on pure black
    case eclipse        // orange-red corona around a black core
    case plasma         // saturated violet-purple
    case mirage         // shimmery yellow-orange

    // Exclusive / Legendary (500 coins)
    case prism          // refracting full-spectrum desat
    case obsidian       // monochromatic deep-blue
    case quasar         // hot magenta + cyan, brightest in the catalogue
    case holeInOne      // golf hole with red flag (Golf bundle)
    case tractorBeam    // ★ NEW (Space Travel bundle) — UFO beam column

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .target:    return "Target"
        case .archery:   return "Archery"
        case .galaxy:    return "Galaxy"
        case .crystal:   return "Crystal"
        case .flame:     return "Flame"
        case .blossom:   return "Blossom"
        case .mosaic:    return "Mosaic"
        case .ripple:    return "Ripple"
        case .comet:     return "Comet"
        case .rainbow:   return "Rainbow"
        case .neon:      return "Neon"
        case .eclipse:   return "Eclipse"
        case .plasma:    return "Plasma"
        case .mirage:    return "Mirage"
        case .prism:       return "Prism"
        case .obsidian:    return "Obsidian"
        case .quasar:      return "Quasar"
        case .holeInOne:   return "Hole-in-One"
        case .tractorBeam: return "Tractor Beam"
        }
    }

    /// In-game palette for the rainbowHole particle Canvas.  Only
    /// consumed for goal skins that route through that renderer —
    /// `.target` and `.archery` ignore this value (they have their
    /// own static renderers) but still return a sensible style so the
    /// protocol shape stays uniform.
    struct HoleStyle {
        /// Base hue added to the per-particle hue.  Combined with hueRange
        /// to confine the particle palette to a slice of the colour wheel.
        let hueBase: Double
        /// Multiplier on the per-particle hue (1.0 = full spectrum, 0.1 = monochromatic).
        let hueRange: Double
        /// Saturation multiplier (0…1).  Lower for pastels/crystals.
        let saturation: Double
        /// Background ellipse colour that sits behind the particles.
        let bgColor: Color
    }

    var holeStyle: HoleStyle {
        switch self {
        case .target, .archery, .holeInOne, .tractorBeam:
            // Not actually consumed (their renderers are bespoke), but
            // we keep a placeholder so callers can read it uniformly.
            return HoleStyle(hueBase: 0.0, hueRange: 1.0, saturation: 1.0, bgColor: .clear)

        case .rainbow:
            // ★ The restored sparkly portal — full spectrum on the deep
            // purple background the original default shipped with.
            return HoleStyle(
                hueBase: 0.0, hueRange: 1.0, saturation: 1.0,
                bgColor: Color(red: 0.03, green: 0.01, blue: 0.06)
            )
        case .galaxy:
            // Deep blue → violet on a navy backdrop.
            return HoleStyle(
                hueBase: 0.58, hueRange: 0.30, saturation: 0.85,
                bgColor: Color(red: 0.03, green: 0.02, blue: 0.12)
            )
        case .crystal:
            return HoleStyle(
                hueBase: 0.46, hueRange: 0.14, saturation: 0.55,
                bgColor: Color(red: 0.02, green: 0.04, blue: 0.08)
            )
        case .flame:
            return HoleStyle(
                hueBase: 0.0, hueRange: 0.12, saturation: 1.0,
                bgColor: Color(red: 0.08, green: 0.02, blue: 0.0)
            )
        case .blossom:
            // Cherry-blossom palette: warm pinks + corals.
            return HoleStyle(
                hueBase: 0.92, hueRange: 0.10, saturation: 0.70,
                bgColor: Color(red: 0.08, green: 0.03, blue: 0.06)
            )
        case .mosaic:
            // Full spectrum at lower saturation → muted mosaic feel.
            return HoleStyle(
                hueBase: 0.0, hueRange: 1.0, saturation: 0.50,
                bgColor: Color(red: 0.06, green: 0.06, blue: 0.08)
            )
        case .ripple:
            // Cool calm blue-cyans.
            return HoleStyle(
                hueBase: 0.52, hueRange: 0.12, saturation: 0.75,
                bgColor: Color(red: 0.02, green: 0.04, blue: 0.10)
            )
        case .comet:
            // Pale white-blue particles on near-black.
            return HoleStyle(
                hueBase: 0.58, hueRange: 0.08, saturation: 0.30,
                bgColor: Color(red: 0.01, green: 0.02, blue: 0.04)
            )

        case .neon:
            return HoleStyle(
                hueBase: 0.85, hueRange: 0.20, saturation: 1.0,
                bgColor: Color.black
            )
        case .eclipse:
            // Orange-red corona around a deep black core.
            return HoleStyle(
                hueBase: 0.03, hueRange: 0.08, saturation: 0.95,
                bgColor: Color(red: 0.00, green: 0.00, blue: 0.00)
            )
        case .plasma:
            // Saturated violet-purple.
            return HoleStyle(
                hueBase: 0.76, hueRange: 0.10, saturation: 1.0,
                bgColor: Color(red: 0.04, green: 0.00, blue: 0.08)
            )
        case .mirage:
            // Shimmery yellow-orange, low contrast.
            return HoleStyle(
                hueBase: 0.10, hueRange: 0.10, saturation: 0.85,
                bgColor: Color(red: 0.08, green: 0.05, blue: 0.02)
            )

        case .prism:
            return HoleStyle(
                hueBase: 0.0, hueRange: 1.0, saturation: 0.65,
                bgColor: Color(red: 0.08, green: 0.07, blue: 0.10)
            )
        case .obsidian:
            // Monochromatic deep blue, very low hue range.
            return HoleStyle(
                hueBase: 0.60, hueRange: 0.04, saturation: 0.95,
                bgColor: Color(red: 0.01, green: 0.01, blue: 0.03)
            )
        case .quasar:
            // Hot magenta + cyan, brightest in the catalogue.
            return HoleStyle(
                hueBase: 0.90, hueRange: 0.30, saturation: 1.0,
                bgColor: Color(red: 0.02, green: 0.00, blue: 0.04)
            )
        }
    }

    /// Compact static preview style used by the shop + Settings cosmetic
    /// picker + tutorial reward modal.
    ///
    /// Returns `AnyShapeStyle` (rather than the more specific
    /// `LinearGradient`) so the default `.rainbow` skin can return a
    /// concentric-banded `RadialGradient` that reads as an archery
    /// target, while every other skin keeps its existing linear
    /// gradient.  Callers fill a Circle with this — `Circle().fill(...)`
    /// accepts any `ShapeStyle`.
    static func previewGradient(for goal: GoalSkin) -> AnyShapeStyle {
        switch goal {
        case .target:
            // Simple 3-ring red/white/red bullseye — the new default.
            // Hard transitions via paired stops at the same location.
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color(red: 0.85, green: 0.12, blue: 0.18), location: 0.00),
                    .init(color: Color(red: 0.85, green: 0.12, blue: 0.18), location: 0.35),
                    .init(color: Color.white,                                location: 0.35),
                    .init(color: Color.white,                                location: 0.70),
                    .init(color: Color(red: 0.85, green: 0.12, blue: 0.18), location: 0.70),
                    .init(color: Color(red: 0.85, green: 0.12, blue: 0.18), location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: 28
            ))
        case .archery:
            // FITA-style 5-band target: white outer → black → blue → red → yellow.
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color(red: 1.00, green: 0.86, blue: 0.20), location: 0.00),
                    .init(color: Color(red: 1.00, green: 0.86, blue: 0.20), location: 0.20),
                    .init(color: Color(red: 0.92, green: 0.20, blue: 0.20), location: 0.20),
                    .init(color: Color(red: 0.92, green: 0.20, blue: 0.20), location: 0.40),
                    .init(color: Color(red: 0.30, green: 0.55, blue: 0.95), location: 0.40),
                    .init(color: Color(red: 0.30, green: 0.55, blue: 0.95), location: 0.60),
                    .init(color: Color.black,                                 location: 0.60),
                    .init(color: Color.black,                                 location: 0.80),
                    .init(color: Color.white,                                 location: 0.80),
                    .init(color: Color.white,                                 location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: 28
            ))
        case .rainbow:
            // Original sparkly-portal preview — purple→blue→green→yellow→red.
            return AnyShapeStyle(LinearGradient(
                colors: [.purple, .blue, .green, .yellow, .red],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .galaxy:
            return AnyShapeStyle(LinearGradient(colors: [Color(red:0.12,green:0.05,blue:0.30),
                                           Color(red:0.50,green:0.10,blue:0.50)],
                                  startPoint: .top, endPoint: .bottom))
        case .crystal:
            return AnyShapeStyle(LinearGradient(colors: [Color.cyan, Color.white.opacity(0.5)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing))
        case .flame:
            return AnyShapeStyle(LinearGradient(colors: [Color.orange, Color.red],
                                  startPoint: .top, endPoint: .bottom))
        case .blossom:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 1.00, green: 0.78, blue: 0.85),
                         Color(red: 0.95, green: 0.42, blue: 0.55)],
                startPoint: .top, endPoint: .bottom))
        case .mosaic:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.75, green: 0.50, blue: 0.95),
                         Color(red: 0.40, green: 0.75, blue: 0.60),
                         Color(red: 0.95, green: 0.70, blue: 0.40)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .ripple:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.55, green: 0.85, blue: 1.00),
                         Color(red: 0.15, green: 0.45, blue: 0.85)],
                startPoint: .top, endPoint: .bottom))
        case .comet:
            return AnyShapeStyle(LinearGradient(
                colors: [Color.white,
                         Color(red: 0.45, green: 0.65, blue: 1.00).opacity(0.5),
                         Color.black.opacity(0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .neon:
            return AnyShapeStyle(LinearGradient(colors: [Color(red:0.95, green:0.10, blue:0.95),
                                           Color(red:0.10, green:0.90, blue:0.95)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing))
        case .eclipse:
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color.black,                                 location: 0.00),
                    .init(color: Color.black,                                 location: 0.40),
                    .init(color: Color(red: 0.95, green: 0.45, blue: 0.10),  location: 0.55),
                    .init(color: Color(red: 0.55, green: 0.10, blue: 0.05),  location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: 28))
        case .plasma:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.85, green: 0.30, blue: 1.00),
                         Color(red: 0.35, green: 0.05, blue: 0.55)],
                startPoint: .top, endPoint: .bottom))
        case .mirage:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 1.00, green: 0.92, blue: 0.55),
                         Color(red: 0.92, green: 0.55, blue: 0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .prism:
            return AnyShapeStyle(LinearGradient(colors: [Color.white, Color.pink.opacity(0.6), Color.blue.opacity(0.6)],
                                  startPoint: .leading, endPoint: .trailing))
        case .obsidian:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.10, green: 0.12, blue: 0.30),
                         Color.black],
                startPoint: .top, endPoint: .bottom))
        case .quasar:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 1.00, green: 0.20, blue: 0.95),
                         Color(red: 0.20, green: 0.95, blue: 1.00)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .holeInOne:
            // Preview: a golf hole on green — concentric green ring
            // with a dark hole in the middle.  The flagstick paints
            // on top in the in-game renderer; the preview gradient
            // just needs to read as "golf hole" at thumbnail size.
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color.black,                                    location: 0.00),
                    .init(color: Color.black,                                    location: 0.30),
                    .init(color: Color(red: 0.30, green: 0.55, blue: 0.20),     location: 0.30),
                    .init(color: Color(red: 0.45, green: 0.72, blue: 0.30),     location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: 28))
        case .tractorBeam:
            // Preview: a glowing green beam column on near-black —
            // bright core fading to the edges.  The in-game renderer
            // adds the saucer + descending light pulses.
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.95, blue: 0.55).opacity(0.95),
                    Color(red: 0.20, green: 1.00, blue: 0.70).opacity(0.45),
                    Color(red: 0.02, green: 0.10, blue: 0.06),
                ],
                startPoint: .top, endPoint: .bottom))
        }
    }
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    static var starter: GoalSkin { .target }
    /// Tier rule (player-facing: Standard / Epic / Legendary):
    ///   • Standard  — truly static, solid-banded targets (no
    ///                 particles, no animation).
    ///   • Epic      — particle portals with a tight palette / mono
    ///                 hue range (animated but visually focused).
    ///   • Legendary — animated portals whose particles span the full
    ///                 spectrum or carry a special-effect treatment.
    var tier: CosmeticTier {
        switch self {
        case .target:
            return .starter
        case .archery:
            return .standard   //  50 coins — static, solid bands
        case .galaxy, .crystal, .flame, .blossom,
             .ripple, .comet, .eclipse, .plasma,
             .mirage, .obsidian:
            return .premium    // 200 coins — animated, tight palette
        case .rainbow, .neon, .mosaic, .prism, .quasar, .holeInOne, .tractorBeam:
            return .exclusive  // 500 coins — animated, full-spectrum, or bespoke
        }
    }
}

// MARK: - Trail colors (the streak left behind the ball)
enum TrailColor: String, CosmeticItem {
    // Starter
    case none           // no trail — silent default
    case graphite       // Paper-world's lead trail; default visible trail

    // Standard (50 coins) — solid mono-coloured streaks
    case ink
    case fire
    case ice
    case mist
    case ember
    case sky
    case roseTrail      // raw "roseTrail" to disambiguate from BallSkin.rose
    case forest
    case bubblegum
    case smoke
    case gilded
    case gold
    case stardust
    case phoenix
    case cometTrail     // disambiguate from GoalSkin.comet

    // Premium / Epic (200 coins) — multi-colour per-segment streak
    case rainbow        // each segment hue derived from its position

    // Exclusive / Legendary (500 coins) — animated / special-effect
    case snake          // grows longer every coin you pick up
    case air            // semi-translucent, extra fade on length (Golf bundle)
    case raybeam        // ★ NEW (Space Travel bundle) — glowing laser streak

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none:        return "Off"
        case .graphite:    return "Graphite"
        case .ink:         return "Ink"
        case .fire:        return "Fire"
        case .ice:         return "Ice"
        case .mist:        return "Mist"
        case .ember:       return "Ember"
        case .sky:         return "Sky"
        case .roseTrail:   return "Rose"
        case .forest:      return "Forest"
        case .bubblegum:   return "Bubblegum"
        case .smoke:       return "Smoke"
        case .gilded:      return "Gilded"
        case .gold:        return "Gold"
        case .stardust:    return "Stardust"
        case .phoenix:     return "Phoenix"
        case .cometTrail:  return "Comet"
        case .rainbow:     return "Rainbow"
        case .snake:       return "Snake"
        case .air:         return "Air"
        case .raybeam:     return "Raybeam"
        }
    }
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    static var starter: TrailColor { .none }
    /// Tier rule:
    ///   • Standard  — solid mono-colour trails.
    ///   • Epic      — multi-colour trails (per-segment hue cycle).
    ///   • Legendary — animated / mechanical trails (grow with
    ///                 coins, sparkle, etc.).
    var tier: CosmeticTier {
        switch self {
        case .none, .graphite:
            return .starter
        case .ink, .fire, .ice, .mist, .ember, .sky, .roseTrail, .forest,
             .bubblegum, .smoke, .gilded, .gold, .stardust, .phoenix,
             .cometTrail:
            return .standard   //  50 coins — solid mono colour
        case .rainbow:
            return .premium    // 200 coins — per-segment hue cycle
        case .snake, .air, .raybeam:
            return .exclusive  // 500 coins — animated / special-effect
        }
    }

    /// SwiftUI Color used when rendering this trail.  `.none` returns
    /// clear; `.rainbow` returns a placeholder colour (the actual
    /// rainbow effect is a per-segment Canvas hue cycle in BallGameView).
    var color: Color {
        switch self {
        case .none:        return .clear
        case .graphite:    return Color(red: 0.20, green: 0.20, blue: 0.22).opacity(0.70)
        case .ink:         return Color(red: 0.09, green: 0.09, blue: 0.14).opacity(0.80)
        case .fire:        return Color(red: 0.95, green: 0.42, blue: 0.10).opacity(0.75)
        case .ice:         return Color(red: 0.55, green: 0.78, blue: 1.00).opacity(0.75)
        case .mist:        return Color(red: 0.75, green: 0.82, blue: 0.88).opacity(0.55)
        case .ember:       return Color(red: 0.92, green: 0.32, blue: 0.10).opacity(0.78)
        case .sky:         return Color(red: 0.40, green: 0.82, blue: 1.00).opacity(0.75)
        case .roseTrail:   return Color(red: 0.95, green: 0.40, blue: 0.62).opacity(0.78)
        case .forest:      return Color(red: 0.12, green: 0.42, blue: 0.18).opacity(0.78)
        case .rainbow:     return .pink   // placeholder; Canvas does the real thing
        case .bubblegum:   return Color(red: 1.00, green: 0.30, blue: 0.78).opacity(0.85)
        case .smoke:       return Color(red: 0.40, green: 0.42, blue: 0.45).opacity(0.65)
        case .cometTrail:  return Color(red: 0.85, green: 0.92, blue: 1.00).opacity(0.85)
        case .gilded:      return Color(red: 0.92, green: 0.78, blue: 0.32).opacity(0.85)
        case .gold:        return Color(red: 0.95, green: 0.70, blue: 0.20).opacity(0.90)
        case .stardust:    return Color(red: 0.92, green: 0.88, blue: 1.00).opacity(0.85)
        case .phoenix:     return Color(red: 1.00, green: 0.35, blue: 0.05).opacity(0.92)
        case .snake:       return Color(red: 0.20, green: 0.65, blue: 0.22).opacity(0.92)
        case .air:         return Color.white.opacity(0.65)   // additional decay in trail renderer
        case .raybeam:     return Color(red: 0.20, green: 1.00, blue: 0.70).opacity(0.95)  // glow added in renderer
        }
    }
}

// MARK: - Floor (formerly half of "Theme")
//
// What the ball rolls on.  Picked separately from the Pit (the hole
// colour / death-zone treatment) so the player can mix and match.
enum Floor: String, CosmeticItem {
    // Starter
    case classic

    // Standard (50 coins) — static solid floor colour
    case inverted
    case twilight
    case ember
    case notebook
    case graph
    case blueprint
    case dusk
    case meadow
    case parchment
    case sketch
    case velvet
    case midnight
    case sunset
    case origami
    case mirage

    // Exclusive / Legendary (500 coins) — animated floor overlays
    case aurora           // the original shimmer
    case disco            // colour-cycling dance-floor squares
    case grass            // golf-course turf with grass tufts (Golf bundle)
    case moon             // ★ NEW (Space Travel bundle) — lunar regolith + craters

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classic:    return "Classic"
        case .inverted:   return "Inverted"
        case .twilight:   return "Twilight"
        case .ember:      return "Ember"
        case .notebook:   return "Notebook"
        case .graph:      return "Graph"
        case .blueprint:  return "Blueprint"
        case .dusk:       return "Dusk"
        case .meadow:     return "Meadow"
        case .parchment:  return "Parchment"
        case .sketch:     return "Sketch"
        case .velvet:     return "Velvet"
        case .midnight:   return "Midnight"
        case .sunset:     return "Sunset"
        case .origami:    return "Origami"
        case .mirage:     return "Mirage"
        case .aurora:     return "Aurora"
        case .disco:      return "Disco"
        case .grass:      return "Grass"
        case .moon:       return "Moon"
        }
    }
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    static var starter: Floor { .classic }
    var tier: CosmeticTier {
        switch self {
        case .classic:
            return .starter
        case .inverted, .twilight, .ember, .notebook, .graph,
             .blueprint, .dusk, .meadow,
             .parchment, .sketch, .velvet, .midnight, .sunset,
             .origami, .mirage:
            return .standard   //  50 coins
        case .aurora, .disco, .grass, .moon:
            return .exclusive  // 500 coins — animated / textured overlay
        }
    }

    /// SwiftUI Color used as the base floor fill.  Animated floors
    /// (aurora, disco) still have a base colour underneath their
    /// overlay so non-overlay-supporting contexts still read sensibly.
    var color: Color {
        switch self {
        case .classic:    return Color(red: 0.941, green: 0.937, blue: 0.925)
        case .inverted:   return Color(red: 0.039, green: 0.039, blue: 0.039)
        case .twilight:   return Color(red: 0.835, green: 0.824, blue: 0.890)
        case .ember:      return Color(red: 0.910, green: 0.835, blue: 0.753)
        case .notebook:   return Color(red: 0.980, green: 0.961, blue: 0.902)
        case .graph:      return Color(red: 0.984, green: 0.984, blue: 0.984)
        case .blueprint:  return Color(red: 0.18,  green: 0.36,  blue: 0.62 )
        case .dusk:       return Color(red: 0.95,  green: 0.72,  blue: 0.62 )
        case .meadow:     return Color(red: 0.78,  green: 0.90,  blue: 0.72 )
        case .parchment:  return Color(red: 0.914, green: 0.863, blue: 0.753)
        case .sketch:     return Color(red: 0.980, green: 0.980, blue: 0.965)
        case .velvet:     return Color(red: 0.35,  green: 0.12,  blue: 0.45 )
        case .midnight:   return Color(red: 0.04,  green: 0.06,  blue: 0.16 )
        case .sunset:     return Color(red: 0.98,  green: 0.55,  blue: 0.25 )
        case .origami:    return Color(red: 0.961, green: 0.937, blue: 0.878)
        case .mirage:     return Color(red: 0.92,  green: 0.82,  blue: 0.55 )
        case .aurora:     return Color(red: 0.380, green: 0.620, blue: 0.560)
        case .disco:      return Color(red: 0.10,  green: 0.10,  blue: 0.14 )  // dark; squares paint over
        case .grass:      return Color(red: 0.35,  green: 0.62,  blue: 0.28 )  // fairway green; tufts paint over
        case .moon:       return Color(red: 0.62,  green: 0.62,  blue: 0.66 )  // pale regolith; craters paint over
        }
    }

    /// Whether this floor has the Paper-world graphite-trail mechanic.
    var paperTrailEnabled: Bool {
        switch self {
        case .notebook, .graph, .parchment, .sketch, .origami: return true
        default: return false
        }
    }

    /// True when the floor needs an animated Canvas overlay drawn on
    /// top of its base color (aurora shimmer, disco squares, grass
    /// tufts, etc.).
    var hasAnimatedOverlay: Bool {
        switch self {
        case .aurora, .disco, .grass, .moon: return true
        default: return false
        }
    }
}

// MARK: - Pit (formerly the other half of "Theme")
//
// What the ball falls into — the death-zone treatment.  Independent
// from Floor; a player can pair a vivid Sky pit with a Notebook floor
// if they want.
enum Pit: String, CosmeticItem {
    // Starter
    case classic

    // Standard (50 coins) — static solid pit colour
    case inverted
    case twilight
    case ember
    case notebook
    case graph
    case blueprint
    case dusk
    case meadow
    case parchment
    case sketch
    case velvet
    case midnight
    case sunset
    case origami
    case mirage
    case aurora

    // Exclusive / Legendary (500 coins) — animated pit overlays
    case evil             // burning fire-pit animation
    case sky              // sky-blue gradient with drifting clouds
    case pond             // water with ripples + lily pad (Golf bundle)
    case space            // ★ NEW (Space Travel bundle) — starfield void

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classic:    return "Classic"
        case .inverted:   return "Inverted"
        case .twilight:   return "Twilight"
        case .ember:      return "Ember"
        case .notebook:   return "Notebook"
        case .graph:      return "Graph"
        case .blueprint:  return "Blueprint"
        case .dusk:       return "Dusk"
        case .meadow:     return "Meadow"
        case .parchment:  return "Parchment"
        case .sketch:     return "Sketch"
        case .velvet:     return "Velvet"
        case .midnight:   return "Midnight"
        case .sunset:     return "Sunset"
        case .origami:    return "Origami"
        case .mirage:     return "Mirage"
        case .aurora:     return "Aurora"
        case .evil:       return "Evil"
        case .sky:        return "Sky"
        case .pond:       return "Pond"
        case .space:      return "Space"
        }
    }
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    static var starter: Pit { .classic }
    var tier: CosmeticTier {
        switch self {
        case .classic:
            return .starter
        case .inverted, .twilight, .ember, .notebook, .graph,
             .blueprint, .dusk, .meadow,
             .parchment, .sketch, .velvet, .midnight, .sunset,
             .origami, .mirage, .aurora:
            return .standard   //  50 coins
        case .evil, .sky, .pond, .space:
            return .exclusive  // 500 coins — animated overlay
        }
    }

    /// SwiftUI Color used as the base pit fill.  Animated pits
    /// (evil, sky) still have a base colour so non-overlay
    /// contexts render sensibly.
    var color: Color {
        switch self {
        case .classic:    return Color(red: 0.039, green: 0.039, blue: 0.039)
        case .inverted:   return Color(red: 0.941, green: 0.937, blue: 0.925)
        case .twilight:   return Color(red: 0.047, green: 0.059, blue: 0.122)
        case .ember:      return Color(red: 0.102, green: 0.039, blue: 0.039)
        case .notebook:   return Color(red: 0.169, green: 0.122, blue: 0.071)
        case .graph:      return Color(red: 0.055, green: 0.102, blue: 0.180)
        case .blueprint:  return Color(red: 0.04,  green: 0.10,  blue: 0.22 )
        case .dusk:       return Color(red: 0.18,  green: 0.06,  blue: 0.08 )
        case .meadow:     return Color(red: 0.06,  green: 0.18,  blue: 0.08 )
        case .parchment:  return Color(red: 0.102, green: 0.059, blue: 0.031)
        case .sketch:     return Color(red: 0.12,  green: 0.12,  blue: 0.14 )
        case .velvet:     return Color(red: 0.08,  green: 0.02,  blue: 0.12 )
        case .midnight:   return Color(red: 0.82,  green: 0.85,  blue: 0.92 )
        case .sunset:     return Color(red: 0.30,  green: 0.06,  blue: 0.04 )
        case .origami:    return Color(red: 0.094, green: 0.078, blue: 0.063)
        case .mirage:     return Color(red: 0.22,  green: 0.14,  blue: 0.05 )
        case .aurora:     return Color(red: 0.000, green: 0.000, blue: 0.000)
        case .evil:       return Color(red: 0.10,  green: 0.02,  blue: 0.00 )  // dark base; flames paint over
        case .sky:        return Color(red: 0.55,  green: 0.78,  blue: 0.95 )  // pale blue base; clouds drift on top
        case .pond:       return Color(red: 0.08,  green: 0.30,  blue: 0.42 )  // deep water; ripples + lily pad on top
        case .space:      return Color(red: 0.02,  green: 0.02,  blue: 0.06 )  // near-black void; stars twinkle on top
        }
    }

    /// True when the pit needs an animated Canvas overlay drawn on
    /// top of its base color (Evil flames, Sky clouds, Pond ripples,
    /// Space starfield).
    var hasAnimatedOverlay: Bool {
        switch self {
        case .evil, .sky, .pond, .space: return true
        default: return false
        }
    }
}

// MARK: - Music tracks
//
// Pure identifiers — actual `.m4a` audio + AVAudioPlayer wiring arrive
// in V1.1.  The shop / settings already render and price these so the
// catalogue ships preview-able.
enum MusicTrack: String, CosmeticItem {
    // Starter
    case none           // silent
    case ambient        // light ambient pad

    // Standard (50 coins)
    case piano
    case chiptune
    case jazz
    case classical
    case electronic
    case acoustic
    case orchestral
    case synthwave

    // Premium / Epic (200 coins)
    case lofi
    case downtempo
    case retrowave
    case cinematic
    case dreamscape

    // Exclusive / Legendary (500 coins)
    case celestial
    case mysterium
    case opus

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none:        return "Off"
        case .ambient:     return "Ambient"
        case .piano:       return "Piano"
        case .chiptune:    return "Chiptune"
        case .jazz:        return "Jazz"
        case .classical:   return "Classical"
        case .electronic:  return "Electronic"
        case .acoustic:    return "Acoustic"
        case .orchestral:  return "Orchestral"
        case .synthwave:   return "Synthwave"
        case .lofi:        return "Lo-fi"
        case .downtempo:   return "Downtempo"
        case .retrowave:   return "Retrowave"
        case .cinematic:   return "Cinematic"
        case .dreamscape:  return "Dreamscape"
        case .celestial:   return "Celestial"
        case .mysterium:   return "Mysterium"
        case .opus:        return "Opus"
        }
    }
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    static var starter: MusicTrack { .none }
    var tier: CosmeticTier {
        switch self {
        case .none, .ambient:
            return .starter
        case .piano, .chiptune, .jazz, .classical,
             .electronic, .acoustic, .orchestral, .synthwave:
            return .standard   // 50 coins
        case .lofi, .downtempo, .retrowave, .cinematic, .dreamscape:
            return .premium    // 200 coins
        case .celestial, .mysterium, .opus:
            return .exclusive  // 500 coins
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Bundles
//
// A bundle wraps several cosmetic items from any number of categories
// into one purchase.  Buying a bundle grants every contained item into
// the player's owned-set forever — `ownedBundles` is purely for UI
// (the "OWNED" badge in the shop).  Items remain available individually
// after the bundle is owned; the bundle just costs less than the sum
// of its parts.
//
// Pricing: 66% of (sum of individual item prices), rounded DOWN to
// the nearest multiple of 20.  Per Mac's spec.
// ---------------------------------------------------------------------------

struct CosmeticBundle: Identifiable {
    /// Stable persistence key.
    let id: String
    let displayName: String
    /// One-line marketing pitch shown under the title.
    let tagline: String
    /// Comma-joined list of contained item names — what the player
    /// gets, in human-readable form.
    let contentSummary: String

    let balls:  [BallSkin]
    let goals:  [GoalSkin]
    let trails: [TrailColor]
    let floors: [Floor]
    let pits:   [Pit]
    let music:  [MusicTrack]

    var itemCount: Int {
        balls.count + goals.count + trails.count + floors.count + pits.count + music.count
    }

    /// 66% of the sum-of-individuals.  Re-computed on each read so
    /// future tier shuffles automatically update bundle prices.
    func price(in _: GameState) -> Int {
        // Broken into per-category locals so the Swift type-checker
        // doesn't choke on one giant chained-generic expression.
        let ballSum:  Int = balls.reduce(0)  { $0 + $1.coinCost }
        let goalSum:  Int = goals.reduce(0)  { $0 + $1.coinCost }
        let trailSum: Int = trails.reduce(0) { $0 + $1.coinCost }
        let floorSum: Int = floors.reduce(0) { $0 + $1.coinCost }
        let pitSum:   Int = pits.reduce(0)   { $0 + $1.coinCost }
        let musicSum: Int = music.reduce(0)  { $0 + $1.coinCost }
        let sum = ballSum + goalSum + trailSum + floorSum + pitSum + musicSum
        // 66% discount, then rounded DOWN to the nearest multiple of 20
        // so every bundle lands on a clean price point (per Mac's spec).
        let discounted = Double(sum) * 0.66
        return Int(discounted / 20.0) * 20
    }

    /// Add every contained item to the appropriate owned-set on
    /// `state`.  One-way grant — items remain owned forever even if
    /// the bundle itself is later removed from the catalogue.
    func grantContents(to state: GameState) {
        balls.forEach  { state.grant($0) }
        goals.forEach  { state.grant($0) }
        trails.forEach { state.grant($0) }
        floors.forEach { state.grant($0) }
        pits.forEach   { state.grant($0) }
        music.forEach  { state.grant($0) }
    }

    // ── Catalogue ──────────────────────────────────────────────────
    //
    // Example bundles using items that already render.  The Golf /
    // Planets / Space Travel bundles Mac requested are stubbed out
    // below but commented — they each require multiple bespoke
    // renderers that haven't been written yet.

    static let catalogue: [CosmeticBundle] = [
        CosmeticBundle(
            id:             "hellfire",
            displayName:    "Hellfire",
            tagline:        "Roll a ruby through the inferno.",
            contentSummary: "Ruby ball · Ember floor · Evil pit · Phoenix trail",
            balls:  [.ruby],
            goals:  [],
            trails: [.phoenix],
            floors: [.ember],
            pits:   [.evil],
            music:  []
        ),
        CosmeticBundle(
            id:             "heavens",
            displayName:    "Heavens",
            tagline:        "Drift the sky on opal lustre.",
            contentSummary: "Opal ball · Classic floor · Sky pit · Stardust trail",
            balls:  [.opal],
            goals:  [],
            trails: [.stardust],
            floors: [.classic],
            pits:   [.sky],
            music:  []
        ),
        CosmeticBundle(
            id:             "nightclub",
            displayName:    "Nightclub",
            tagline:        "Disco lights, neon goal, bubblegum streak.",
            contentSummary: "Disco floor · Neon goal · Bubblegum trail",
            balls:  [],
            goals:  [.neon],
            trails: [.bubblegum],
            floors: [.disco],
            pits:   [],
            music:  []
        ),
        CosmeticBundle(
            id:             "paper-world",
            displayName:    "Paper World",
            tagline:        "The full Notebook + Graphite-trail pack.",
            contentSummary: "Notebook floor · Notebook pit · Graphite trail (starter)",
            balls:  [],
            goals:  [],
            trails: [],   // graphite is starter; included by default
            floors: [.notebook],
            pits:   [.notebook],
            music:  []
        ),
        CosmeticBundle(
            id:             "golf",
            displayName:    "Golf",
            tagline:        "Dimpled ball, fairway green, lily-pad pond, hole-in-one flag.",
            contentSummary: "Golf Ball · Grass floor · Pond pit · Air trail · Hole-in-One goal",
            balls:  [.golfBall],
            goals:  [.holeInOne],
            trails: [.air],
            floors: [.grass],
            pits:   [.pond],
            music:  []
        ),

        CosmeticBundle(
            id:             "planets",
            displayName:    "Planets",
            tagline:        "Roll the whole solar system — plus a tiny Pluto.",
            contentSummary: "Earth · Mars · Saturn · Mercury · Neptune · Jupiter · Venus · Uranus + exclusive half-size Pluto",
            balls:  [.earth, .mars, .saturn, .mercury,
                     .neptune, .jupiter, .venus, .uranus, .pluto],
            goals:  [],
            trails: [],
            floors: [],
            pits:   [],
            music:  []
        ),

        CosmeticBundle(
            id:             "space-travel",
            displayName:    "Space Travel",
            tagline:        "Pilot a saucer across the moon and into the void.",
            contentSummary: "UFO ball · Moon floor · Space pit · Tractor Beam goal · Raybeam trail",
            balls:  [.ufo],
            goals:  [.tractorBeam],
            trails: [.raybeam],
            floors: [.moon],
            pits:   [.space],
            music:  []
        ),

        CosmeticBundle(
            id:             "winter",
            displayName:    "Winter",
            tagline:        "A snowglobe marble through crystal frost.",
            contentSummary: "Snowglobe ball · Crystal goal · Ice trail · Twilight floor · Twilight pit",
            balls:  [.snowglobe],
            goals:  [.crystal],
            trails: [.ice],
            floors: [.twilight],
            pits:   [.twilight],
            music:  []
        ),

        CosmeticBundle(
            id:             "cosmos",
            displayName:    "Cosmos",
            tagline:        "Drift the deep with a nebula in hand.",
            contentSummary: "Nebula ball · Galaxy goal · Stardust trail · Midnight floor · Midnight pit",
            balls:  [.nebula],
            goals:  [.galaxy],
            trails: [.stardust],
            floors: [.midnight],
            pits:   [.midnight],
            music:  []
        ),

        CosmeticBundle(
            id:             "nature",
            displayName:    "Nature",
            tagline:        "Jade and blossoms over a meadow green.",
            contentSummary: "Jade ball · Blossom goal · Forest trail · Meadow floor · Meadow pit",
            balls:  [.jade],
            goals:  [.blossom],
            trails: [.forest],
            floors: [.meadow],
            pits:   [.meadow],
            music:  []
        ),

        CosmeticBundle(
            id:             "ocean",
            displayName:    "Ocean",
            tagline:        "Ride the tide on a wave of mint.",
            contentSummary: "Mint ball · Ripple goal · Sky trail · Blueprint floor · Blueprint pit",
            balls:  [.mint],
            goals:  [.ripple],
            trails: [.sky],
            floors: [.blueprint],
            pits:   [.blueprint],
            music:  []
        ),

        CosmeticBundle(
            id:             "velvet-night",
            displayName:    "Velvet Night",
            tagline:        "Plasma and rainbow over deep velvet.",
            contentSummary: "Purple ball · Plasma goal · Rainbow trail · Velvet floor · Velvet pit",
            balls:  [.purple],
            goals:  [.plasma],
            trails: [.rainbow],
            floors: [.velvet],
            pits:   [.velvet],
            music:  []
        ),

        CosmeticBundle(
            id:             "golden-hour",
            displayName:    "Golden Hour",
            tagline:        "Chase the last warm light of the day.",
            contentSummary: "Coral ball · Mirage goal · Fire trail · Sunset floor · Dusk pit · Acoustic music",
            balls:  [.coral],
            goals:  [.mirage],
            trails: [.fire],
            floors: [.sunset],
            pits:   [.dusk],
            music:  [.acoustic]
        ),

        CosmeticBundle(
            id:             "arcade",
            displayName:    "Arcade",
            tagline:        "Pixel-perfect retro on a grid.",
            contentSummary: "Copper ball · Comet goal · Comet trail · Graph floor · Graph pit · Chiptune music",
            balls:  [.copper],
            goals:  [.comet],
            trails: [.cometTrail],
            floors: [.graph],
            pits:   [.graph],
            music:  [.chiptune]
        ),

        CosmeticBundle(
            id:             "bloom",
            displayName:    "Bloom",
            tagline:        "Soft petals on warm parchment.",
            contentSummary: "Rose ball · Mosaic goal · Rose trail · Parchment floor · Parchment pit · Piano music",
            balls:  [.rose],
            goals:  [.mosaic],
            trails: [.roseTrail],
            floors: [.parchment],
            pits:   [.parchment],
            music:  [.piano]
        ),

        CosmeticBundle(
            id:             "noir",
            displayName:    "Noir",
            tagline:        "Black, white, and everything stark.",
            contentSummary: "Slate ball · Obsidian goal · Ink trail · Inverted floor · Inverted pit · Cinematic music",
            balls:  [.slate],
            goals:  [.obsidian],
            trails: [.ink],
            floors: [.inverted],
            pits:   [.inverted],
            music:  [.cinematic]
        ),

        CosmeticBundle(
            id:             "aurora",
            displayName:    "Aurora",
            tagline:        "Northern lights over a shimmering field.",
            contentSummary: "Galaxy ball · Prism goal · Mist trail · Aurora floor · Aurora pit · Celestial music",
            balls:  [.galaxy],
            goals:  [.prism],
            trails: [.mist],
            floors: [.aurora],
            pits:   [.aurora],
            music:  [.celestial]
        ),

        CosmeticBundle(
            id:             "citrus",
            displayName:    "Citrus",
            tagline:        "Zest and warmth from dawn to dusk.",
            contentSummary: "Lemon ball · Flame goal · Ember trail · Dusk floor · Sunset pit · Jazz music",
            balls:  [.lemon],
            goals:  [.flame],
            trails: [.ember],
            floors: [.dusk],
            pits:   [.sunset],
            music:  [.jazz]
        ),

        CosmeticBundle(
            id:             "midas",
            displayName:    "Midas",
            tagline:        "Everything you touch turns to gold.",
            contentSummary: "Gold ball · Quasar goal · Gilded trail · Mirage floor · Mirage pit · Orchestral music",
            balls:  [.gold],
            goals:  [.quasar],
            trails: [.gilded],
            floors: [.mirage],
            pits:   [.mirage],
            music:  [.orchestral]
        ),

        CosmeticBundle(
            id:             "sketchbook",
            displayName:    "Sketchbook",
            tagline:        "Pencil, graphite, and a steady hand.",
            contentSummary: "Silver ball · Archery goal · Smoke trail · Sketch floor · Sketch pit · Classical music",
            balls:  [.silver],
            goals:  [.archery],
            trails: [.smoke],
            floors: [.sketch],
            pits:   [.sketch],
            music:  [.classical]
        ),

        CosmeticBundle(
            id:             "zen-garden",
            displayName:    "Zen Garden",
            tagline:        "A folded-paper serpent in a calm green world.",
            contentSummary: "Green ball · Rainbow goal · Snake trail · Origami floor · Origami pit · Dreamscape music",
            balls:  [.green],
            goals:  [.rainbow],
            trails: [.snake],
            floors: [.origami],
            pits:   [.origami],
            music:  [.dreamscape]
        ),

        CosmeticBundle(
            id:             "eclipse",
            displayName:    "Eclipse",
            tagline:        "A golden corona around the dark.",
            contentSummary: "Blue ball · Eclipse goal · Gold trail · Mysterium music",
            balls:  [.blue],
            goals:  [.eclipse],
            trails: [.gold],
            floors: [],
            pits:   [],
            music:  [.mysterium]
        ),
    ]
}
