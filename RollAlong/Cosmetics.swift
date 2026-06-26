import SwiftUI
import UIKit   // ImageRenderer.uiImage / Image(uiImage:) for the share card

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
///   • rare       → "Rare"
///   • premium    → "Epic"
///   • exclusive  → "Legendary"
enum CosmeticTier: String, Codable {
    case starter        // free, always owned
    case standard       // 50  coins — entry-level skins, tutorial-reward eligible
    case rare           // 100 coins — a notch up; distinctive but not flashy
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
        case .rare:      return 100
        case .premium:   return 200
        case .exclusive: return 500
        }
    }

    /// Player-facing rarity name (shop / profile badges).  starter is implicit
    /// ("Free") and normally renders no badge — see `showsBadge`.
    var label: String {
        switch self {
        case .starter:   return "Free"
        case .standard:  return "Standard"
        case .rare:      return "Rare"
        case .premium:   return "Epic"
        case .exclusive: return "Legendary"
        }
    }

    /// Rarity accent — gray → cool blue → epic purple → legendary gold, the
    /// conventional rarity ramp players already read at a glance.
    var color: Color {
        switch self {
        case .starter:   return Color(white: 0.55)
        case .standard:  return Color(red: 0.45, green: 0.62, blue: 0.85)
        case .rare:      return Color(red: 0.28, green: 0.78, blue: 0.95)
        case .premium:   return Color(red: 0.72, green: 0.45, blue: 0.95)
        case .exclusive: return Color(red: 1.00, green: 0.78, blue: 0.28)
        }
    }

    /// starter/free items don't earn a badge (it's the implicit default).
    var showsBadge: Bool { self != .starter }
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
             .pastel, .neon, .dune,
             .basketball, .soccer, .baseball, .eightBall, .golfBall:
            return .premium    // 200 coins (Epic) — colour blends + sports balls
        case .snowglobe, .pluto, .ufo, .aquarium, .marble,
             .storm, .candy, .ghost, .lava, .trench,
             .earth, .mars, .saturn, .mercury,        // planets are Legendary now
             .neptune, .jupiter, .venus, .uranus,
             .trophy,           // golden-gauntlet-exclusive; never coin-purchasable
             .aurora,          // starter-pack-exclusive; never coin-purchasable
             .beachBall,       // summer-2026-exclusive; never coin-purchasable
             .pumpkin,         // halloween-2026-exclusive; never coin-purchasable
             .ornament,        // winter-2026-exclusive; never coin-purchasable
             .heartstone,      // valentines-2027-exclusive; never coin-purchasable
             .shamrock,        // stpatricks-2027-exclusive; never coin-purchasable
             .confetti,        // newyear-2027-exclusive; never coin-purchasable
             .speckledEgg,     // spring-2027-exclusive; never coin-purchasable
             .diamond:         // Diamond Balls IAP-exclusive; never coin-purchasable
            return .exclusive  // 500 coins (Legendary) — animated / special / planets
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
    case none           // no trail — free "Off" option in the shop
    case graphite       // Paper-world's lead trail; THE default — equipped from first launch

    // Tiers are assigned in `tier` below (Standard / Rare / Legendary).
    case ink
    case fire
    case ice
    case ember
    case sky
    case roseTrail      // raw "roseTrail" to disambiguate from BallSkin.rose
    case forest
    case bubblegum
    case smoke
    case gilded
    case stardust
    case cometTrail     // disambiguate from GoalSkin.comet
    case rainbow        // glowing per-segment hue cycle
    case snake          // grows longer every coin you pick up
    case air            // pillowy jet-stream (Golf bundle)
    case raybeam        // glowing laser streak (Space Travel bundle)

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none:        return "Off"
        case .graphite:    return "Graphite"
        case .ink:         return "Ink"
        case .fire:        return "Fire"
        case .ice:         return "Ice"
        case .ember:       return "Ember"
        case .sky:         return "Sky"
        case .roseTrail:   return "Rose"
        case .forest:      return "Forest"
        case .bubblegum:   return "Bubblegum"
        case .smoke:       return "Smoke"
        case .gilded:      return "Gilded"
        case .stardust:    return "Stardust"
        case .cometTrail:  return "Comet"
        case .rainbow:     return "Rainbow"
        case .snake:       return "Snake"
        case .air:         return "Air"
        case .raybeam:     return "Raybeam"
        }
    }
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    /// The default-equipped trail.  Graphite (not .none) so a brand-new
    /// player sees a trail behind their ball from the very first roll;
    /// "Off" stays a free starter-tier choice in the shop for players
    /// who prefer no trail.
    static var starter: TrailColor { .graphite }
    /// Tier rule:
    ///   • Standard  — solid mono-colour trails.
    ///   • Epic      — multi-colour trails (per-segment hue cycle).
    ///   • Legendary — animated / mechanical trails (grow with
    ///                 coins, sparkle, etc.).
    var tier: CosmeticTier {
        switch self {
        case .none:
            return .starter
        case .ink, .ember, .sky, .forest, .bubblegum:
            return .standard   //  50 coins — solid mono colour
        case .snake, .raybeam, .gilded, .graphite, .roseTrail:
            return .rare       // 100 coins — distinctive textured trails
        case .fire, .cometTrail, .stardust, .smoke, .ice, .rainbow, .air:
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
        case .ember:       return Color(red: 0.92, green: 0.32, blue: 0.10).opacity(0.78)
        case .sky:         return Color(red: 0.40, green: 0.82, blue: 1.00).opacity(0.75)
        case .roseTrail:   return Color(red: 0.52, green: 0.08, blue: 0.22).opacity(0.92)   // dark rose; petals in renderer
        case .forest:      return Color(red: 0.12, green: 0.42, blue: 0.18).opacity(0.78)
        case .rainbow:     return .pink   // placeholder; Canvas does the real thing
        case .bubblegum:   return Color(red: 1.00, green: 0.30, blue: 0.78).opacity(0.85)
        case .smoke:       return Color(red: 0.40, green: 0.42, blue: 0.45).opacity(0.65)
        case .cometTrail:  return Color(red: 0.85, green: 0.92, blue: 1.00).opacity(0.85)
        case .gilded:      return Color(red: 0.92, green: 0.78, blue: 0.32).opacity(0.85)
        case .stardust:    return Color(red: 0.92, green: 0.88, blue: 1.00).opacity(0.85)
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
    case desert           // Round-5 Dune bundle — warm sand
    case stormcloud       // Round-5 Tempest bundle — slate storm
    case sugar            // Round-5 Candyland bundle — pale candy-pink
    case fog              // Round-5 Haunted bundle — cold grey mist

    // Exclusive / Legendary (500 coins) — animated floor overlays
    case aurora           // the original shimmer
    case disco            // colour-cycling dance-floor squares
    case grass            // golf-course turf with grass tufts (Golf bundle)
    case moon             // ★ NEW (Space Travel bundle) — lunar regolith + craters

    // Sports bundles (new)
    case court            // Full Court bundle — warm hardwood basketball floor
    case felt             // Billiards Hall bundle — deep-green pool-table felt

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
        case .desert:     return "Desert"
        case .stormcloud: return "Stormcloud"
        case .sugar:      return "Sugar"
        case .fog:        return "Fog"
        case .aurora:     return "Aurora"
        case .disco:      return "Disco"
        case .grass:      return "Grass"
        case .moon:       return "Moon"
        case .court:      return "Court"
        case .felt:       return "Felt"
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
             .origami, .mirage, .desert, .stormcloud, .sugar, .fog,
             .court, .felt:
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
        case .desert:     return Color(red: 0.90,  green: 0.78,  blue: 0.55 )  // warm sand
        case .stormcloud: return Color(red: 0.32,  green: 0.36,  blue: 0.44 )  // slate storm
        case .sugar:      return Color(red: 0.99,  green: 0.92,  blue: 0.95 )  // pale candy-pink
        case .fog:        return Color(red: 0.66,  green: 0.69,  blue: 0.70 )  // cold grey mist
        case .aurora:     return Color(red: 0.380, green: 0.620, blue: 0.560)
        case .disco:      return Color(red: 0.10,  green: 0.10,  blue: 0.14 )  // dark; squares paint over
        case .grass:      return Color(red: 0.35,  green: 0.62,  blue: 0.28 )  // fairway green; tufts paint over
        case .moon:       return Color(red: 0.62,  green: 0.62,  blue: 0.66 )  // pale regolith; craters paint over
        case .court:      return Color(red: 0.84,  green: 0.65,  blue: 0.38 )  // warm hardwood
        case .felt:       return Color(red: 0.18,  green: 0.48,  blue: 0.24 )  // pool-table green
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
    case canyon           // Round-5 Dune bundle — deep rust gorge
    case downpour         // Round-5 Tempest bundle — dark rainy blue
    case syrup            // Round-5 Candyland bundle — dark molasses
    case graveyard        // Round-5 Haunted bundle — near-black graveyard earth

    // Exclusive / Legendary (500 coins) — animated pit overlays
    case evil             // burning fire-pit animation
    case sky              // sky-blue gradient with drifting clouds
    case pond             // water with ripples + lily pad (Golf bundle)
    case space            // ★ NEW (Space Travel bundle) — starfield void

    // Sports bundles (new)
    case sideline         // Full Court bundle — dark-grey out-of-bounds edge
    case pocket           // Billiards Hall bundle — near-black pool pocket

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
        case .canyon:     return "Canyon"
        case .downpour:   return "Downpour"
        case .syrup:      return "Syrup"
        case .graveyard:  return "Graveyard"
        case .evil:       return "Evil"
        case .sky:        return "Sky"
        case .pond:       return "Pond"
        case .space:      return "Space"
        case .sideline:   return "Sideline"
        case .pocket:     return "Pocket"
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
             .origami, .mirage, .aurora, .canyon, .downpour, .syrup, .graveyard,
             .sideline, .pocket:
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
        case .canyon:     return Color(red: 0.32,  green: 0.14,  blue: 0.08 )  // deep rust gorge
        case .downpour:   return Color(red: 0.10,  green: 0.16,  blue: 0.26 )  // dark rainy blue
        case .syrup:      return Color(red: 0.20,  green: 0.06,  blue: 0.10 )  // dark molasses
        case .graveyard:  return Color(red: 0.04,  green: 0.07,  blue: 0.05 )  // near-black graveyard earth
        case .evil:       return Color(red: 0.10,  green: 0.02,  blue: 0.00 )  // dark base; flames paint over
        case .sky:        return Color(red: 0.55,  green: 0.78,  blue: 0.95 )  // pale blue base; clouds drift on top
        case .pond:       return Color(red: 0.08,  green: 0.30,  blue: 0.42 )  // deep water; ripples + lily pad on top
        case .space:      return Color(red: 0.02,  green: 0.02,  blue: 0.06 )  // near-black void; stars twinkle on top
        case .sideline:   return Color(red: 0.14,  green: 0.14,  blue: 0.16 )  // dark court edge / out-of-bounds
        case .pocket:     return Color(red: 0.06,  green: 0.08,  blue: 0.06 )  // near-black pool pocket
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
// into one purchase.  Buying a bundle grants every yet-unowned contained
// item into the player's owned-set forever — `ownedBundles` is purely for
// UI (the "OWNED" badge in the shop).  Items remain available individually
// after the bundle is owned.
//
// Pricing (per Mac's spec):
//   • fullPrice            — the sum of every item's individual price.
//   • proratedPrice(in:)   — the sum of the UNOWNED items' prices.  This is
//                            the Catalog price (you only pay for what you
//                            don't already own).
//   • shopPrice(in:_:)     — proratedPrice with the Shop's randomized
//                            featured-bundle discount applied.
// ---------------------------------------------------------------------------

/// A randomized discount applied to the Shop's featured bundle.  The four
/// tiers mirror the cosmetic rarity ramp so a deep discount reads as a
/// "lucky drop".  Rolled once per Shop window (stable for 2 hours) by
/// `ShopRotation.featuredDiscount`.
enum BundleDiscount: String, CaseIterable {
    case common, rare, epic, legendary

    /// Percent off the (prorated) bundle price.
    var percent: Int {
        switch self {
        case .common:    return 10
        case .rare:      return 15
        case .epic:      return 25
        case .legendary: return 50
        }
    }

    /// Fractional discount (0…1) for arithmetic.
    var fraction: Double { Double(percent) / 100.0 }

    /// Player-facing rarity name shown in the Shop's "% OFF" chip.
    var label: String {
        switch self {
        case .common:    return "Common"
        case .rare:      return "Rare"
        case .epic:      return "Epic"
        case .legendary: return "Legendary"
        }
    }

    /// Loot-weighted odds — big discounts are rare (sums to 100).
    var weight: Int {
        switch self {
        case .common:    return 50
        case .rare:      return 30
        case .epic:      return 15
        case .legendary: return 5
        }
    }

    /// Rarity accent — the same gray→blue→purple→gold ramp the rest of the
    /// catalogue uses (see `CosmeticTier.color`).  starter has no analogue.
    var color: Color {
        switch self {
        case .common:    return Color(red: 0.45, green: 0.62, blue: 0.85)
        case .rare:      return Color(red: 0.28, green: 0.78, blue: 0.95)
        case .epic:      return Color(red: 0.72, green: 0.45, blue: 0.95)
        case .legendary: return Color(red: 1.00, green: 0.78, blue: 0.28)
        }
    }
}

// ===========================================================================
// Shop rotation — the curated storefront refreshes every 2 hours.  A
// deterministic window index seeds which bundle + odds-and-ends cosmetics are
// featured, so the selection is stable within a window and identical
// everywhere (the Shop display AND the Catalog's "available now" markers).
// ===========================================================================
enum ShopRotation {
    static let windowSeconds: TimeInterval = 2 * 60 * 60   // 2 hours

    static func window(at date: Date = Date()) -> Int {
        Int(date.timeIntervalSince1970 / windowSeconds)
    }
    static func refreshDate(at date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: Double(window(at: date) + 1) * windowSeconds)
    }
    /// "1:59:42" until the next refresh.
    static func countdown(at date: Date = Date()) -> String {
        let s = max(0, Int(refreshDate(at: date).timeIntervalSince(date)))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    // Pools of coin-purchasable items eligible to be featured.
    static var bundlePool: [CosmeticBundle] {
        CosmeticBundle.catalogue.filter { $0.isAvailable && !$0.isExpired }
    }
    static var ballPool: [BallSkin] {
        BallSkin.allCases.filter { !$0.isBundleExclusive && $0.tier != .starter }
    }
    static var trailPool: [TrailColor] {
        // Exclude the free default (graphite) and the bundle-only trails.
        TrailColor.allCases.filter { $0.tier != .starter && $0 != .graphite && $0 != .air && $0 != .raybeam }
    }
    static var goalPool: [GoalSkin] {
        GoalSkin.allCases.filter { $0.tier != .starter }
    }
    static var floorPool: [Floor] {
        Floor.allCases.filter { $0.tier != .starter }
    }
    static var pitPool: [Pit] {
        Pit.allCases.filter { $0.tier != .starter }
    }
    static var musicPool: [MusicTrack] {
        MusicTrack.allCases.filter { $0.tier != .starter }
    }

    private static func pick<T>(_ pool: [T], _ window: Int, salt: Int) -> T? {
        guard !pool.isEmpty else { return nil }
        let h = window &* 31 &+ salt
        return pool[((h % pool.count) + pool.count) % pool.count]
    }

    static func featuredBundle(at date: Date = Date()) -> CosmeticBundle? { pick(bundlePool, window(at: date), salt: 0) }
    static func featuredBall(at date: Date = Date())   -> BallSkin?       { pick(ballPool,   window(at: date), salt: 7) }
    static func featuredTrail(at date: Date = Date())  -> TrailColor?     { pick(trailPool,  window(at: date), salt: 13) }
    static func featuredGoal(at date: Date = Date())   -> GoalSkin?       { pick(goalPool,   window(at: date), salt: 19) }
    static func featuredFloor(at date: Date = Date())  -> Floor?          { pick(floorPool,  window(at: date), salt: 29) }
    static func featuredPit(at date: Date = Date())    -> Pit?            { pick(pitPool,    window(at: date), salt: 37) }
    static func featuredMusic(at date: Date = Date())  -> MusicTrack?     { pick(musicPool,  window(at: date), salt: 41) }

    /// The randomized discount applied to the featured bundle this window.
    /// Loot-weighted (see `BundleDiscount.weight`) so deep discounts are
    /// rare, and deterministic per window so the Shop shows a stable "% OFF".
    static func featuredDiscount(at date: Date = Date()) -> BundleDiscount {
        let total = BundleDiscount.allCases.reduce(0) { $0 + $1.weight }   // 100
        let h = window(at: date) &* 31 &+ 23
        var roll = ((h % total) + total) % total
        for d in BundleDiscount.allCases {
            if roll < d.weight { return d }
            roll -= d.weight
        }
        return .common
    }

    /// True if `item` is one of the individually-featured odds-and-ends OR a
    /// member of the featured bundle — i.e. buyable in the Shop right now.
    /// (Used by the Catalog to draw the blue "available now" border.)
    static func isFeatured<Item: CosmeticItem>(_ item: Item, at date: Date = Date()) -> Bool {
        if let b = item as? BallSkin    { if b == featuredBall(at: date) { return true } }
        if let t = item as? TrailColor  { if t == featuredTrail(at: date) { return true } }
        if let g = item as? GoalSkin    { if g == featuredGoal(at: date) { return true } }
        if let f = item as? Floor       { if f == featuredFloor(at: date) { return true } }
        if let p = item as? Pit         { if p == featuredPit(at: date) { return true } }
        if let m = item as? MusicTrack  { if m == featuredMusic(at: date) { return true } }
        guard let bundle = featuredBundle(at: date) else { return false }
        return bundle.contains(item)
    }
}

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

    // ── Seasonal availability window ───────────────────────────────
    // Both nil = always available (permanent bundle).
    // Non-nil `availableUntil` marks the bundle as limited-time.
    // Shop only shows it when `isAvailable` is true.
    var availableFrom:  Date? = nil
    var availableUntil: Date? = nil

    // MARK: Availability computed vars

    /// True when this bundle has an expiry date (i.e., is seasonal).
    var isLimitedTime: Bool { availableUntil != nil }

    /// True when the current date falls within the availability window.
    var isAvailable: Bool {
        let now = Date()
        if let from  = availableFrom,  now < from  { return false }
        if let until = availableUntil, now >= until { return false }
        return true
    }

    /// True when availableUntil is in the past.
    var isExpired: Bool {
        guard let until = availableUntil else { return false }
        return Date() >= until
    }

    /// True when availableFrom is in the future (offer hasn't opened yet).
    var isUpcoming: Bool {
        guard let from = availableFrom else { return false }
        return Date() < from
    }

    /// Full days remaining until expiry.  nil when not limited or already
    /// expired.  0 = "ends today" (less than 24 h left).
    var daysRemaining: Int? {
        guard isLimitedTime, isAvailable, let until = availableUntil else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: until).day ?? 0
        return max(0, days)
    }

    /// Short human-readable countdown label ("3 days left", "Ends today").
    var timeRemainingLabel: String? {
        guard let days = daysRemaining else { return nil }
        switch days {
        case 0:  return "Ends today"
        case 1:  return "1 day left"
        default: return "\(days) days left"
        }
    }

    // MARK: Date helper

    /// Convenience: build a `Date` from Gregorian year / month / day.
    /// Falls back to `.distantFuture` so a malformed date makes the
    /// bundle safely unavailable rather than always-available.
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return Calendar(identifier: .gregorian).date(from: c) ?? .distantFuture
    }

    var itemCount: Int {
        balls.count + goals.count + trails.count + floors.count + pits.count + music.count
    }

    /// The full price of the bundle — the sum of every contained item's
    /// individual `coinCost`.  Starter items are free, so they add nothing.
    func fullPrice() -> Int {
        // Per-category locals so the Swift type-checker doesn't choke on one
        // giant chained-generic expression.
        let ballSum:  Int = balls.reduce(0)  { $0 + $1.coinCost }
        let goalSum:  Int = goals.reduce(0)  { $0 + $1.coinCost }
        let trailSum: Int = trails.reduce(0) { $0 + $1.coinCost }
        let floorSum: Int = floors.reduce(0) { $0 + $1.coinCost }
        let pitSum:   Int = pits.reduce(0)   { $0 + $1.coinCost }
        let musicSum: Int = music.reduce(0)  { $0 + $1.coinCost }
        return ballSum + goalSum + trailSum + floorSum + pitSum + musicSum
    }

    /// The prorated price — the sum of only the items the player does NOT
    /// already own.  This is the Catalog price (and the base the Shop
    /// discount comes off).  A bundle purchase grants exactly these items.
    func proratedPrice(in state: GameState) -> Int {
        let ballSum:  Int = balls.reduce(0)  { $0 + (state.isOwned($1) ? 0 : $1.coinCost) }
        let goalSum:  Int = goals.reduce(0)  { $0 + (state.isOwned($1) ? 0 : $1.coinCost) }
        let trailSum: Int = trails.reduce(0) { $0 + (state.isOwned($1) ? 0 : $1.coinCost) }
        let floorSum: Int = floors.reduce(0) { $0 + (state.isOwned($1) ? 0 : $1.coinCost) }
        let pitSum:   Int = pits.reduce(0)   { $0 + (state.isOwned($1) ? 0 : $1.coinCost) }
        let musicSum: Int = music.reduce(0)  { $0 + (state.isOwned($1) ? 0 : $1.coinCost) }
        return ballSum + goalSum + trailSum + floorSum + pitSum + musicSum
    }

    /// The Shop's featured-bundle price: the prorated price with the given
    /// discount applied, floored to a clean multiple of 5.
    func shopPrice(in state: GameState, discount: BundleDiscount) -> Int {
        let base = proratedPrice(in: state)
        let discounted = Double(base) * (1.0 - discount.fraction)
        return (Int(discounted) / 5) * 5
    }

    /// Back-compat shim — defaults to the Catalog (prorated) price so any
    /// caller not yet migrated to the explicit methods still reads sensibly.
    func price(in state: GameState) -> Int { proratedPrice(in: state) }

    /// True if this bundle includes `item` (any category).
    func contains<Item: CosmeticItem>(_ item: Item) -> Bool {
        switch item {
        case let s as BallSkin:   return balls.contains(s)
        case let g as GoalSkin:   return goals.contains(g)
        case let t as TrailColor: return trails.contains(t)
        case let f as Floor:      return floors.contains(f)
        case let p as Pit:        return pits.contains(p)
        case let m as MusicTrack: return music.contains(m)
        default:                  return false
        }
    }

    /// Every catalogue bundle whose contents include `item` — i.e. the
    /// set(s) the item was released with.  Used by the Catalog to show
    /// each cosmetic's related bundle(s).
    static func bundles<Item: CosmeticItem>(containing item: Item) -> [CosmeticBundle] {
        catalogue.filter { $0.contains(item) }
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
            contentSummary: "Ruby ball · Ember floor · Evil pit · Fire trail",
            balls:  [.ruby],
            goals:  [],
            trails: [.fire],
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
            contentSummary: "Galaxy ball · Prism goal · Smoke trail · Aurora floor · Aurora pit · Celestial music",
            balls:  [.galaxy],
            goals:  [.prism],
            trails: [.smoke],
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
            contentSummary: "Blue ball · Eclipse goal · Gilded trail · Mysterium music",
            balls:  [.blue],
            goals:  [.eclipse],
            trails: [.gilded],
            floors: [],
            pits:   [],
            music:  [.mysterium]
        ),
        CosmeticBundle(
            id:             "pastel",
            displayName:    "Pastel",
            tagline:        "Soft candy hues and a gentle piano.",
            contentSummary: "Pastel ball · Blossom goal · Rose trail · Twilight floor · Parchment pit · Piano music",
            balls:  [.pastel],
            goals:  [.blossom],
            trails: [.roseTrail],
            floors: [.twilight],
            pits:   [.parchment],
            music:  [.piano]
        ),
        CosmeticBundle(
            id:             "neon",
            displayName:    "Neon",
            tagline:        "Electric pink on a pulsing dance floor.",
            contentSummary: "Neon ball · Neon goal · Bubblegum trail · Disco floor · Midnight pit · Electronic music",
            balls:  [.neon],
            goals:  [.neon],
            trails: [.bubblegum],
            floors: [.disco],
            pits:   [.midnight],
            music:  [.electronic]
        ),
        CosmeticBundle(
            id:             "soccer",
            displayName:    "Soccer",
            tagline:        "Hit the pitch — hex-stitched ball on fresh turf.",
            contentSummary: "Soccer Ball · Smoke trail · Grass floor · Meadow pit · Synthwave music",
            balls:  [.soccer],
            goals:  [],
            trails: [.smoke],
            floors: [.grass],
            pits:   [.meadow],
            music:  [.synthwave]
        ),
        CosmeticBundle(
            id:             "aquarium",
            displayName:    "Aquarium",
            tagline:        "A glass orb of bubbles over a rippling pond.",
            contentSummary: "Aquarium ball · Ripple goal · Ice trail · Mirage floor · Pond pit · Dreamscape music",
            balls:  [.aquarium],
            goals:  [.ripple],
            trails: [.ice],
            floors: [.mirage],
            pits:   [.pond],
            music:  [.dreamscape]
        ),
        CosmeticBundle(
            id:             "realistic-marble",
            displayName:    "Realistic Marble",
            tagline:        "A genuine glass cat's-eye, swirled in cobalt.",
            contentSummary: "Marble ball · Crystal goal · Gilded trail · Velvet floor · Velvet pit · Cinematic music",
            balls:  [.marble],
            goals:  [.crystal],
            trails: [.gilded],
            floors: [.velvet],
            pits:   [.velvet],
            music:  [.cinematic]
        ),

        // ── Round 5 ──
        CosmeticBundle(
            id:             "dune",
            displayName:    "Dune",
            tagline:        "Drift the desert as the sun sinks low.",
            contentSummary: "Dune ball · Mirage goal · Air trail · Desert floor · Canyon pit · Ambient music",
            balls:  [.dune],
            goals:  [.mirage],
            trails: [.air],
            floors: [.desert],
            pits:   [.canyon],
            music:  [.ambient]
        ),
        CosmeticBundle(
            id:             "tempest",
            displayName:    "Tempest",
            tagline:        "Lightning sealed inside a marble.",
            contentSummary: "Storm ball · Plasma goal · Smoke trail · Stormcloud floor · Downpour pit · Retrowave music",
            balls:  [.storm],
            goals:  [.plasma],
            trails: [.smoke],
            floors: [.stormcloud],
            pits:   [.downpour],
            music:  [.retrowave]
        ),
        CosmeticBundle(
            id:             "candyland",
            displayName:    "Candyland",
            tagline:        "A peppermint swirl through a sugar-dusted world.",
            contentSummary: "Candy ball · Mosaic goal · Bubblegum trail · Sugar floor · Syrup pit · Lo-fi music",
            balls:  [.candy],
            goals:  [.mosaic],
            trails: [.bubblegum],
            floors: [.sugar],
            pits:   [.syrup],
            music:  [.lofi]
        ),
        CosmeticBundle(
            id:             "haunted",
            displayName:    "Haunted",
            tagline:        "A restless spirit drifting through the dark.",
            contentSummary: "Ghost ball · Obsidian goal · Smoke trail · Fog floor · Graveyard pit · Downtempo music",
            balls:  [.ghost],
            goals:  [.obsidian],
            trails: [.smoke],
            floors: [.fog],
            pits:   [.graveyard],
            music:  [.downtempo]
        ),

        // ── Seasonal bundles (limited-time, return annually) ───────────
        //
        // Items used here are shared with permanent bundles for now.  S4 will
        // add bespoke exclusive cosmetics (beach ball, sandy floor, wave trail,
        // etc.) and update these entries.  The availability window is what
        // makes them feel special, not just the items.
        CosmeticBundle(
            id:             "summer-2026",
            displayName:    "Summer Vibes",
            tagline:        "Sun, sea, and rolling waves.",
            contentSummary: "Beach Ball · Ripple goal · Sky trail · Blueprint floor · Pond pit · Acoustic music",
            balls:  [.beachBall],
            goals:  [.ripple],
            trails: [.sky],
            floors: [.blueprint],
            pits:   [.pond],
            music:  [.acoustic],
            availableFrom:  CosmeticBundle.date(2026, 6,  1),
            availableUntil: CosmeticBundle.date(2026, 9,  1)
        ),
        CosmeticBundle(
            id:             "halloween-2026",
            displayName:    "Trick or Roll",
            tagline:        "A restless spirit through the dark.",
            contentSummary: "Pumpkin ball · Obsidian goal · Smoke trail · Fog floor · Graveyard pit · Downtempo music",
            balls:  [.pumpkin],
            goals:  [.obsidian],
            trails: [.smoke],
            floors: [.fog],
            pits:   [.graveyard],
            music:  [.downtempo],
            availableFrom:  CosmeticBundle.date(2026, 10,  1),
            availableUntil: CosmeticBundle.date(2026, 11,  1)
        ),
        CosmeticBundle(
            id:             "winter-2026",
            displayName:    "Winter Wonderland",
            tagline:        "A mirror-bright ornament through crystal frost.",
            contentSummary: "Ornament ball · Crystal goal · Ice trail · Twilight floor · Twilight pit · Dreamscape music",
            balls:  [.ornament],
            goals:  [.crystal],
            trails: [.ice],
            floors: [.twilight],
            pits:   [.twilight],
            music:  [.dreamscape],
            availableFrom:  CosmeticBundle.date(2026, 12,  1),
            availableUntil: CosmeticBundle.date(2027,  1,  6)
        ),
        CosmeticBundle(
            id:             "valentines-2027",
            displayName:    "Sweetheart",
            tagline:        "All heart, no brakes.",
            contentSummary: "Heartstone ball · Blossom goal · Rose trail · Velvet floor · Dusk pit · Piano music",
            balls:  [.heartstone],
            goals:  [.blossom],
            trails: [.roseTrail],
            floors: [.velvet],
            pits:   [.dusk],
            music:  [.piano],
            availableFrom:  CosmeticBundle.date(2027, 2,  1),
            availableUntil: CosmeticBundle.date(2027, 2, 15)
        ),
        CosmeticBundle(
            id:             "stpatricks-2027",
            displayName:    "Luck of the Roll",
            tagline:        "Find your four-leaf marble.",
            contentSummary: "Shamrock ball · Mirage goal · Gilded trail · Meadow floor · Pond pit · Lofi music",
            balls:  [.shamrock],
            goals:  [.mirage],
            trails: [.gilded],
            floors: [.meadow],
            pits:   [.pond],
            music:  [.lofi],
            availableFrom:  CosmeticBundle.date(2027, 3,  1),
            availableUntil: CosmeticBundle.date(2027, 3, 18)
        ),
        CosmeticBundle(
            id:             "newyear-2027",
            displayName:    "Countdown",
            tagline:        "Three, two, one — roll.",
            contentSummary: "Confetti ball · Rainbow goal · Gilded trail · Disco floor · Midnight pit · Electronic music",
            balls:  [.confetti],
            goals:  [.rainbow],
            trails: [.gilded],
            floors: [.disco],
            pits:   [.midnight],
            music:  [.electronic],
            availableFrom:  CosmeticBundle.date(2026, 12, 28),
            availableUntil: CosmeticBundle.date(2027,  1,  5)
        ),
        CosmeticBundle(
            id:             "spring-2027",
            displayName:    "Spring Fling",
            tagline:        "Speckled. Bright. Unstoppable.",
            contentSummary: "Speckled Egg ball · Mosaic goal · Forest trail · Meadow floor · Sky pit · Acoustic music",
            balls:  [.speckledEgg],
            goals:  [.mosaic],
            trails: [.forest],
            floors: [.meadow],
            pits:   [.sky],
            music:  [.acoustic],
            availableFrom:  CosmeticBundle.date(2027, 3, 20),
            availableUntil: CosmeticBundle.date(2027, 5,  1)
        ),

        // ── Sports bundles ──────────────────────────────────────────────
        CosmeticBundle(
            id:             "full-court",
            displayName:    "Full Court",
            tagline:        "Hardwood, orange leather, and the buzz of the arena.",
            contentSummary: "Basketball · Eclipse goal · Fire trail · Court floor · Sideline pit · Jazz music",
            balls:  [.basketball],
            goals:  [.eclipse],
            trails: [.fire],
            floors: [.court],
            pits:   [.sideline],
            music:  [.jazz]
        ),
        CosmeticBundle(
            id:             "billiards-hall",
            displayName:    "Billiards Hall",
            tagline:        "Eight ball, corner pocket. The felt is perfect.",
            contentSummary: "8-Ball · Crystal goal · Smoke trail · Felt floor · Pocket pit · Jazz music",
            balls:  [.eightBall],
            goals:  [.crystal],
            trails: [.smoke],
            floors: [.felt],
            pits:   [.pocket],
            music:  [.jazz]
        ),
        CosmeticBundle(
            id:             "diamond",
            displayName:    "Diamond",
            tagline:        "Step up to the plate. The crowd is watching.",
            contentSummary: "Baseball · Target goal · Rose trail · Meadow floor · Sketch pit · Orchestral music",
            balls:  [.baseball],
            goals:  [.target],
            trails: [.roseTrail],
            floors: [.meadow],
            pits:   [.sketch],
            music:  [.orchestral]
        ),

        // ── Challenge Track reward bundles ───────────────────────────────
        //
        // Earned free by completing a 100-level Challenge Track; never
        // sold in the shop as a standalone purchase.  Idempotent delivery
        // via GameState.deliverTrackReward(for:) + ownedBundles guard.
        //
        // Tracks S19: frozen-peaks→winter, deep-cosmos→cosmos,
        //   inferno-run→lava-flow, neon-arcade→neon, haunted-manor→haunted
        //   all reward EXISTING bundles already in this catalogue — no new
        //   entries needed for those five.
        //
        // S20 ─────────────────────────────────────────────────────────────
        CosmeticBundle(
            id:             "ancient-temple",
            displayName:    "Ancient Temple",
            tagline:        "Every stone carries the weight of centuries.",
            contentSummary: "Dune ball · Eclipse goal · Gilded trail · Desert floor · Canyon pit · Orchestral music",
            balls:  [.dune],
            goals:  [.eclipse],
            trails: [.gilded],
            floors: [.desert],
            pits:   [.canyon],
            music:  [.orchestral]
        ),
        //
        // S21 ─────────────────────────────────────────────────────────────
        CosmeticBundle(
            id:             "abyssal-depths",
            displayName:    "Abyssal Depths",
            tagline:        "Light doesn't reach here. Roll by feel.",
            contentSummary: "Trench ball · Comet goal · Ice trail · Blueprint floor · Space pit · Dreamscape music",
            balls:  [.trench],
            goals:  [.comet],
            trails: [.ice],
            floors: [.blueprint],
            pits:   [.space],
            music:  [.dreamscape]
        ),
        // S22 ─────────────────────────────────────────────────────────────
        // Trophy ball is isBundleExclusive = true — hidden from shop grid,
        // only earned by completing Golden Gauntlet.
        CosmeticBundle(
            id:             "champion",
            displayName:    "Champion",
            tagline:        "No tutorial. No mercy. A hundred flawless rooms.",
            contentSummary: "Trophy ball (exclusive) · Quasar goal · Gilded trail · Mirage floor · Mirage pit · Orchestral music",
            balls:  [.trophy],
            goals:  [.quasar],
            trails: [.gilded],
            floors: [.mirage],
            pits:   [.mirage],
            music:  [.orchestral]
        ),

        // ── S15 ──────────────────────────────────────────────────────────
        CosmeticBundle(
            id:             "crystal-cavern",
            displayName:    "Crystal Cavern",
            tagline:        "Deep underground, the crystals glow.",
            contentSummary: "Opal ball · Prism goal · Comet trail · Midnight floor · Aurora pit · Mysterium music",
            balls:  [.opal],
            goals:  [.prism],
            trails: [.cometTrail],
            floors: [.midnight],
            pits:   [.aurora],
            music:  [.mysterium]
        ),

        // ── S16 ──────────────────────────────────────────────────────────
        CosmeticBundle(
            id:             "midnight-carnival",
            displayName:    "Midnight Carnival",
            tagline:        "The rides never stop when the sun goes down.",
            contentSummary: "Copper ball · Neon goal · Fire trail · Midnight floor · Velvet pit · Retrowave music",
            balls:  [.copper],
            goals:  [.neon],
            trails: [.fire],
            floors: [.midnight],
            pits:   [.velvet],
            music:  [.retrowave]
        ),

        // ── S17 ──────────────────────────────────────────────────────────
        CosmeticBundle(
            id:             "lava-flow",
            displayName:    "Lava Flow",
            tagline:        "Slow, relentless, unstoppable.",
            contentSummary: "Lava ball · Eclipse goal · Fire trail · Sunset floor · Evil pit · Downtempo music",
            balls:  [.lava],
            goals:  [.eclipse],
            trails: [.fire],
            floors: [.sunset],
            pits:   [.evil],
            music:  [.downtempo]
        ),
    ]
}

// MARK: - Ball Packs
//
// A Pack is a curated set of BALL skins only — distinct from a
// CosmeticBundle (which spans multiple cosmetic categories).  Packs
// live INSIDE the Ball section of the shop + inventory (no separate
// tab).  When a Pack is equipped, the ball shuffles to a different
// member skin at the start of every attempt — a no-repeat shuffle bag,
// see `GameState.advancePackSkin()`.  Buying a Pack grants every member
// skin individually AND records Pack ownership, so the player can equip
// the whole Pack (shuffle) or any single ball from it.
struct BallPack: Identifiable {
    let id: String
    let displayName: String
    /// One-line marketing pitch shown under the title.
    let tagline: String
    /// Member ball skins in catalogue order (the shuffle bag is derived
    /// from this set).
    let skins: [BallSkin]

    var itemCount: Int { skins.count }

    /// 66% of the sum of member-skin coin costs, floored to the nearest
    /// multiple of 20 — same discount + rounding as `CosmeticBundle`.
    func price(in _: GameState) -> Int {
        let sum = skins.reduce(0) { $0 + $1.coinCost }
        let discounted = Double(sum) * 0.66
        return Int(discounted / 20.0) * 20
    }

    /// Grant every member skin to the player's owned-set.  One-way — the
    /// skins stay owned even if the Pack later leaves the catalogue.
    func grantContents(to state: GameState) {
        skins.forEach { state.grant($0) }
    }

    // ── Catalogue ──────────────────────────────────────────────────
    // Pass 1 uses ONLY ball skins that already render.  Themed packs
    // that need new art (billiards solids/stripes, more sports balls,
    // more vintage glass marbles) arrive in follow-up passes once their
    // bespoke renderers exist.
    static let catalogue: [BallPack] = [
        BallPack(
            id:          "planets",
            displayName: "Planets",
            tagline:     "Roll a different world every run.",
            skins:       [.earth, .mars, .saturn, .mercury,
                          .neptune, .jupiter, .venus, .uranus]
        ),
        BallPack(
            id:          "sports-balls",
            displayName: "Sports Balls",
            tagline:     "Take the field — a new ball each attempt.",
            skins:       [.golfBall, .soccer, .basketball, .baseball]
        ),
        BallPack(
            id:          "glass-marbles",
            displayName: "Vintage Glass Marbles",
            tagline:     "A jar of classics — cat's-eye, frost, and shimmer.",
            skins:       [.marble, .aquarium, .snowglobe, .opal]
        ),
    ]
}

// ---------------------------------------------------------------------------
// RivalCosmetics — shared "keystone" looks for the competitive minigames.
//
// Each AI rival shows off a desirable ball skin + trail and a fun nickname, so
// competitive play doubles as a catalogue ad ("ooh, I want that one") and you
// can always tell who's who.  (When real multiplayer lands, rivals will instead
// wear their OWN equipped gear + real display name, fetched from their profile.)
// Used by GoldRushView and the other competitive views.
// ---------------------------------------------------------------------------
enum RivalCosmetics {
    struct Look { let skin: BallSkin; let trail: TrailColor; let name: String }

    /// Desirable (skin, trail) pairs — easily edited; add/swap any pair.
    static let showcase: [(skin: BallSkin, trail: TrailColor)] = [
        (.galaxy, .rainbow), (.nebula, .stardust), (.lava,   .fire),
        (.aurora, .cometTrail), (.neon, .raybeam), (.gold,   .gilded),
        (.saturn, .sky), (.opal, .air), (.storm, .ice), (.ghost, .smoke),
    ]

    static let names: [String] = [
        "Pip", "Ace", "Bolt", "Nova", "Zip", "Echo", "Dash", "Fizz",
        "Quill", "Bandit", "Comet", "Jinx", "Rook", "Sly", "Pixel",
    ]

    /// Deal `count` distinct rival looks (skin + trail + nickname), shuffled.
    static func deal(_ count: Int) -> [Look] {
        let s = showcase.shuffled(), n = names.shuffled()
        return (0..<max(0, count)).map { i in
            let p = s[i % s.count]
            return Look(skin: p.skin, trail: p.trail, name: n[i % n.count])
        }
    }

    /// One random look — for modes that spawn rivals one at a time (waves).
    static func random() -> Look {
        let p = showcase.randomElement()!
        return Look(skin: p.skin, trail: p.trail, name: names.randomElement()!)
    }
}

/// A small floating tag above a competitive marble — a bold "YOU" for the
/// player, the rival's nickname otherwise.  `color` is the racer's identity rim.
struct RivalNameTag: View {
    let label: String
    let color: Color
    let isPlayer: Bool
    var isLeader: Bool = false      // draws a crown above the tag (current leader)
    var body: some View {
        VStack(spacing: 1) {
            if isLeader {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.30))
                    .shadow(color: .black.opacity(0.55), radius: 1, y: 0.5)
            }
            Text(label)
                .font(.system(size: isPlayer ? 11 : 10,
                              weight: isPlayer ? .heavy : .bold, design: .rounded))
                .foregroundStyle(isPlayer ? Color.white : color)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(isPlayer ? 0.6 : 0.42)))
                .overlay(Capsule().stroke(color.opacity(0.95), lineWidth: isPlayer ? 1.5 : 1))
        }
        .fixedSize()
    }
}

/// A tiny ball-decal chip — a racer's actual equipped skin, for HUDs/standings
/// (replaces flat colored dots so players see real cosmetics up top too).
struct MiniBall: View {
    let skin: BallSkin
    var size: CGFloat = 14
    var body: some View {
        // The one canonical ball renderer, so a skin looks identical everywhere.
        BallSkinView(skin: skin, diameter: size)
            .frame(width: size, height: size)
    }
}

/// A small rarity pill — "Standard" / "Epic" / "Legendary" in the tier's accent
/// colour.  Surfaces rarity-as-status in the shop and profile.  Renders nothing
/// for starter/free items.
struct TierBadge: View {
    let tier: CosmeticTier
    var compact: Bool = false
    var body: some View {
        if tier.showsBadge {
            Text(tier.label.uppercased())
                .font(.system(size: compact ? 8 : 9, weight: .black, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(tier.color)
                .padding(.horizontal, compact ? 5 : 7)
                .padding(.vertical, compact ? 2 : 3)
                .background(Capsule().fill(tier.color.opacity(0.16)))
                .overlay(Capsule().stroke(tier.color.opacity(0.55), lineWidth: 1))
                .fixedSize()
        }
    }
}

// ---------------------------------------------------------------------------
// Competitive trails — shared so the keystone "opponents' trails are visible"
// streak is one implementation across every competitive view.
// ---------------------------------------------------------------------------

/// Append a position to a per-key trail buffer (min-step gate + length cap).
/// Call once per racer each tick; the buffer feeds `drawTrails`.
func recordTrail<K: Hashable>(_ trails: inout [K: [CGPoint]], _ key: K, _ pos: CGPoint,
                              maxLen: Int = 14, minStep: CGFloat = 3) {
    var pts = trails[key] ?? []
    if let last = pts.last {
        if hypot(pos.x - last.x, pos.y - last.y) > minStep { pts.append(pos) }
    } else {
        pts.append(pos)
    }
    if pts.count > maxLen { pts.removeFirst(pts.count - maxLen) }
    trails[key] = pts
}

/// Draw fading competitive trails into a Canvas `ctx`.  Each entry is one
/// racer's recent points + the TrailColor to draw it in (`.rainbow` → a
/// per-segment hue cycle; `.none` and <2-point trails are skipped).
func drawTrails(_ ctx: GraphicsContext,
                _ entries: [(points: [CGPoint], trail: TrailColor)]) {
    for e in entries {
        let pts = e.points
        guard pts.count >= 2, e.trail != .none else { continue }
        let rainbow = e.trail == .rainbow
        let solid = e.trail.color
        for i in 1..<pts.count {
            let age = Double(i) / Double(pts.count - 1)
            let segColor: Color = rainbow
                ? Color(hue: (Double(i) / Double(pts.count)).truncatingRemainder(dividingBy: 1),
                        saturation: 1, brightness: 1)
                : solid
            var path = Path(); path.move(to: pts[i - 1]); path.addLine(to: pts[i])
            ctx.stroke(path, with: .color(segColor.opacity(0.10 + 0.55 * age)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
    }
}

// ===========================================================================
// Rich per-trail rendering — bespoke, animated effects for the player's
// equipped trail (snow trench for ice, fire→smoke for comet, scales for snake,
// twinkling stars for stardust, a jet-stream for air, …).  Drawn for ONE ball
// at a time (home + climb), so it can afford the detail.  `pts` runs
// oldest→newest (the ball sits at pts.last); `t` is a time value for animation.
// ===========================================================================
/// Draw the equipped trail.
///
/// `times` is the wall-clock stamp (`timeIntervalSinceReferenceDate`) at which
/// each point was laid, parallel to `pts`.  The "elemental" trails (ink, fire,
/// ice, air) use it to drive a real-time lifecycle — each mark stays put where
/// it was laid and animates/dissipates on its own clock, independent of the
/// ball's speed — rather than the old index-as-age proxy that pinned the effect
/// to the ball.  When `times` is nil (e.g. the static shop preview) those trails
/// fall back to a synthetic age spread so they still read.
func drawRichTrail(_ ctx: GraphicsContext, points pts: [CGPoint],
                   trail: TrailColor, t: Double, baseWidth: CGFloat = 6,
                   times: [Double]? = nil) {
    guard pts.count >= 2, trail != .none else { return }
    let n = pts.count
    switch trail {
    case .snake:           trailSnake(ctx, pts, n, t, baseWidth)
    case .cometTrail:      trailComet(ctx, pts, n, t, baseWidth)
    case .ice:             trailIce(ctx, pts, n, t, baseWidth, times)
    case .fire:            trailFire(ctx, pts, n, t, baseWidth, times)
    case .ink:             trailInk(ctx, pts, n, t, baseWidth, times)
    case .smoke:           trailMist(ctx, pts, n, t, baseWidth, base: trail.color)
    case .stardust:        trailStardust(ctx, pts, n, t, baseWidth)
    case .air:             trailAir(ctx, pts, n, t, baseWidth, times)
    case .rainbow:         trailRainbow(ctx, pts, n, t, baseWidth)
    case .graphite:        trailGraphite(ctx, pts, n, baseWidth)
    case .roseTrail:       trailRose(ctx, pts, n, t, baseWidth, times)
    default:
        trailTapered(ctx, pts, n, baseWidth, color: trail.color,
                     glow: trail == .raybeam || trail == .gilded || trail == .ember)
    }
}

/// Real seconds since point `i` was laid.  Falls back to a synthetic spread
/// (head ≈ fresh, tail ≈ `lifetime`) when timestamps are unavailable — e.g. the
/// static shop preview — so the lifecycle still animates.
private func trailAge(_ i: Int, _ n: Int, _ t: Double,
                      _ times: [Double]?, lifetime: Double) -> Double {
    if let times, i < times.count { return max(0, t - times[i]) }
    guard n > 1 else { return 0 }
    return Double(n - 1 - i) / Double(n - 1) * lifetime * 0.95
}

/// Stable per-location phase seed so an element flickers/sways IN PLACE instead
/// of jumping when the FIFO buffer shifts its index out from under it.
private func trailSeed(_ p: CGPoint) -> Double {
    Double(p.x) * 0.1037 + Double(p.y) * 0.0719
}

/// Tapered, optionally-glowing streak — the default for the simple colour trails.
private func trailTapered(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int,
                          _ baseWidth: CGFloat, color: Color, glow: Bool) {
    var ctx = ctx
    for i in 1..<n {
        let age = Double(i) / Double(n - 1)
        let w   = baseWidth * CGFloat(0.30 + 0.70 * age)
        var p = Path(); p.move(to: pts[i - 1]); p.addLine(to: pts[i])
        if glow {
            ctx.blendMode = .plusLighter
            ctx.stroke(p, with: .color(color.opacity(0.16 * age)),
                       style: StrokeStyle(lineWidth: w * 2.4, lineCap: .round))
            ctx.blendMode = .normal
        }
        ctx.stroke(p, with: .color(color.opacity(0.12 + 0.70 * age)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
}

/// Snake — a fat scaled body that tapers to the tail, with a head + eyes +
/// tongue.  The body slithers: each point is swung sideways by a sine wave that
/// travels down the length over time, so the snake winds back and forth like
/// it's threading through grass — even while the ball is momentarily still.
private func trailSnake(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int, _ t: Double, _ baseWidth: CGFloat) {
    let dark = Color(red: 0.09, green: 0.38, blue: 0.15)
    let mid  = Color(red: 0.18, green: 0.64, blue: 0.24)
    let lite = Color(red: 0.50, green: 0.90, blue: 0.42)
    let headW = baseWidth * 2.0

    // ── Slither: offset every point sideways by a travelling sine wave.  The
    //    phase is keyed to arc-length-FROM-THE-HEAD (stable as the FIFO trims
    //    the tail, so the wave glides smoothly instead of jumping), and the
    //    amplitude ramps up from 0 at the head — the head stays pinned to the
    //    ball while the body winds behind it.
    let amp        = Double(baseWidth) * 2.0     // sideways swing (px)
    let waveLen    = Double(baseWidth) * 18.0    // px between crests
    let slitherSpd = 5.0                         // wave travel speed (rad/s)
    let headAnchor = Double(baseWidth) * 5.0     // px over which amplitude eases in

    var sFromHead = [Double](repeating: 0, count: n)
    for i in stride(from: n - 2, through: 0, by: -1) {
        sFromHead[i] = sFromHead[i + 1]
            + Double(hypot(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y))
    }
    var body = [CGPoint](repeating: .zero, count: n)
    for i in 0..<n {
        let a = pts[max(0, i - 1)], b = pts[min(n - 1, i + 1)]
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let len = max(0.001, (dx * dx + dy * dy).squareRoot())
        let px = -dy / len, py = dx / len                 // unit perpendicular
        let s = sFromHead[i]
        let fade = min(1.0, s / headAnchor)               // anchor the head
        let lat = amp * fade * sin(s / waveLen * 2 * .pi - t * slitherSpd)
        body[i] = CGPoint(x: pts[i].x + CGFloat(px * lat),
                          y: pts[i].y + CGFloat(py * lat))
    }

    for i in 1..<n {
        let age = CGFloat(i) / CGFloat(n - 1)
        let w = headW * (0.30 + 0.70 * age)
        var p = Path(); p.move(to: body[i - 1]); p.addLine(to: body[i])
        ctx.stroke(p, with: .color(dark), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(mid),  style: StrokeStyle(lineWidth: w * 0.72, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(lite.opacity(0.5)), style: StrokeStyle(lineWidth: w * 0.24, lineCap: .round, lineJoin: .round))
        // Scale chevron across the body at this segment.
        let dx = body[i].x - body[i - 1].x, dy = body[i].y - body[i - 1].y
        let len = max(0.001, hypot(dx, dy))
        let ux = dx / len, uy = dy / len, px = -uy, py = ux
        let h = w * 0.42, b = body[i]
        var chev = Path()
        chev.move(to: CGPoint(x: b.x + px * h - ux * h, y: b.y + py * h - uy * h))
        chev.addLine(to: CGPoint(x: b.x, y: b.y))
        chev.addLine(to: CGPoint(x: b.x - px * h - ux * h, y: b.y - py * h - uy * h))
        ctx.stroke(chev, with: .color(dark.opacity(0.45)),
                   style: StrokeStyle(lineWidth: max(0.6, w * 0.09), lineCap: .round, lineJoin: .round))
    }
    // Head — pinned to the ball (body[n-1] == pts[n-1]), banking along the slither.
    let head = body[n - 1], prev = body[n - 2]
    let hdx = head.x - prev.x, hdy = head.y - prev.y, hlen = max(0.001, hypot(hdx, hdy))
    let ux = hdx / hlen, uy = hdy / hlen, ex = -uy, ey = ux
    let hr = headW * 0.62
    ctx.fill(Path(ellipseIn: CGRect(x: head.x - hr, y: head.y - hr, width: hr * 2, height: hr * 2)), with: .color(mid))
    ctx.fill(Path(ellipseIn: CGRect(x: head.x - hr, y: head.y - hr, width: hr * 2, height: hr * 2)),
        with: .radialGradient(Gradient(colors: [lite.opacity(0.6), .clear]),
            center: CGPoint(x: head.x - hr * 0.3, y: head.y - hr * 0.3), startRadius: 0, endRadius: hr))
    let er = hr * 0.22
    for s in [CGFloat(1), -1] {
        let cxp = head.x + ux * hr * 0.2 + ex * hr * 0.45 * s
        let cyp = head.y + uy * hr * 0.2 + ey * hr * 0.45 * s
        ctx.fill(Path(ellipseIn: CGRect(x: cxp - er, y: cyp - er, width: er * 2, height: er * 2)), with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: cxp - er * 0.5, y: cyp - er * 0.5, width: er, height: er)), with: .color(.black))
    }
    var tongue = Path()
    tongue.move(to: CGPoint(x: head.x + ux * hr, y: head.y + uy * hr))
    tongue.addLine(to: CGPoint(x: head.x + ux * hr * 2.1, y: head.y + uy * hr * 2.1))
    ctx.stroke(tongue, with: .color(Color(red: 0.9, green: 0.12, blue: 0.30)),
               style: StrokeStyle(lineWidth: max(0.8, hr * 0.16), lineCap: .round))
}

/// Comet — bright yellow/white fire at the head, bleeding to deep red, then a
/// long tail of dissipating grey smoke.
private func trailComet(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int, _ t: Double, _ baseWidth: CGFloat) {
    var ctx = ctx
    // Smoke on the older portion — soft grey puffs that spread + drift.
    for i in 0..<n {
        let age = Double(i) / Double(n - 1)
        guard age <= 0.6 else { continue }
        let f = age / 0.6                         // 0 tail → 1 mid
        let p = pts[i]
        let pr = baseWidth * CGFloat(1.4 + 3.0 * (1 - f))
        let drift = CGFloat(sin(t * 1.2 + Double(i))) * baseWidth * 0.5
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - pr + drift, y: p.y - pr, width: pr * 2, height: pr * 2)),
            with: .radialGradient(Gradient(colors: [Color(white: 0.55).opacity(0.18 * f), .clear]),
                center: CGPoint(x: p.x + drift, y: p.y), startRadius: 0, endRadius: pr))
    }
    // Fire near the head — additive, yellow/white → orange → deep red.
    ctx.blendMode = .plusLighter
    for i in 1..<n {
        let age = Double(i) / Double(n - 1)
        guard age >= 0.45 else { continue }
        let f = (age - 0.45) / 0.55               // 0 mid → 1 head
        let col = f > 0.7 ? Color(red: 1, green: 0.96, blue: 0.65)
                : (f > 0.4 ? Color(red: 1, green: 0.55, blue: 0.12)
                           : Color(red: 0.82, green: 0.12, blue: 0.05))
        let w = baseWidth * CGFloat(0.5 + 1.7 * f)
        var p = Path(); p.move(to: pts[i - 1]); p.addLine(to: pts[i])
        ctx.stroke(p, with: .color(col.opacity(0.25 + 0.6 * f)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
}

/// Ice — a carved trench: a faint cut down the middle with snow mounds piled
/// on each side.
/// Ice — an icy-blue trench the ball cuts through, with irregular snow piles
/// heaped on each side.  The piles are DISCRETE clumps (not continuous rails)
/// with seeded varying size and a little settling "life", so it reads as snow
/// shoved aside rather than three coloured lines.
private func trailIce(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int, _ t: Double, _ baseWidth: CGFloat,
                      _ times: [Double]?) {
    let lifetime = 1.4
    // A faint icy cut connecting recent points — fades out as it ages so it
    // doesn't read as a permanent ribbon trailing the ball.
    for i in 1..<n {
        let age = trailAge(i, n, t, times, lifetime: lifetime)
        guard age < lifetime else { continue }
        let env = max(0, 1 - age / lifetime)
        var p = Path(); p.move(to: pts[i - 1]); p.addLine(to: pts[i])
        ctx.stroke(p, with: .color(Color(red: 0.62, green: 0.84, blue: 1.0).opacity(0.22 * env)),
                   style: StrokeStyle(lineWidth: baseWidth * 0.7, lineCap: .round, lineJoin: .round))
    }
    // Snow piles — clumps heaped where the ball passed.  Each pile is laid at
    // full size, settles gently in place, then melts (shrinks + fades) at the
    // end of its life, rather than scaling with distance from the ball.
    for i in stride(from: 1, to: n, by: 2) {
        let age = trailAge(i, n, t, times, lifetime: lifetime)
        guard age < lifetime else { continue }
        let life = age / lifetime
        let rise = min(1.0, age / 0.10)                          // quick heap-up
        let melt = life < 0.6 ? 1.0 : 1.0 - (life - 0.6) / 0.4   // hold, then melt
        let env  = rise * max(0, melt)
        guard env > 0.02 else { continue }
        let dx = pts[i].x - pts[i - 1].x, dy = pts[i].y - pts[i - 1].y
        let len = max(0.001, hypot(dx, dy)), px = -dy / len, py = dx / len
        let baseOff = baseWidth * 0.9
        for side in [CGFloat(1), -1] {
            let seed = trailSeed(pts[i]) + (side > 0 ? 0.0 : 0.37)
            let r1 = seed.truncatingRemainder(dividingBy: 1.0)            // 0…1, stable per pile
            let settle = 0.92 + 0.08 * sin(t * 2.0 + seed * 6.283)        // gentle in-place settling
            let pileR = baseWidth * (0.50 + 0.70 * CGFloat(r1)) * CGFloat(env) * CGFloat(settle)
            if pileR < 0.6 { continue }
            let cx = pts[i].x + px * baseOff * side, cy = pts[i].y + py * baseOff * side
            let op = 0.85 * Double(env)
            // Lumpy clump — three overlapping blobs of varying size.
            for k in 0..<3 {
                let kk = Double(k)
                let bx = cx + CGFloat(cos(kk * 2.1 + seed * 3)) * pileR * 0.6
                let by = cy + CGFloat(sin(kk * 2.1 + seed * 3)) * pileR * 0.6 - pileR * 0.2
                let br = pileR * CGFloat(0.55 + 0.45 * (kk / 3))
                ctx.fill(Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(op),
                                                            Color(red: 0.86, green: 0.93, blue: 1.0).opacity(0)]),
                        center: CGPoint(x: bx - br * 0.3, y: by - br * 0.3), startRadius: 0, endRadius: br))
            }
            // Cool shadow where the pile meets the ground.
            ctx.fill(Path(ellipseIn: CGRect(x: cx - pileR * 0.8, y: cy + pileR * 0.3, width: pileR * 1.6, height: pileR * 0.7)),
                with: .color(Color(red: 0.5, green: 0.66, blue: 0.88).opacity(0.12 * Double(env))))
        }
    }
}

/// Graphite — pencil on paper: a faint base line broken up by short, jittered,
/// uneven strokes so it reads as scratchy lead catching the paper's tooth (not
/// a solid ink line).  Static — the jitter is seeded per segment so it holds.
private func trailGraphite(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int, _ baseWidth: CGFloat) {
    let lead = Color(red: 0.20, green: 0.20, blue: 0.22)
    for i in 1..<n {
        let age = Double(i) / Double(n - 1)
        let a = pts[i - 1], b = pts[i]
        var base = Path(); base.move(to: a); base.addLine(to: b)
        ctx.stroke(base, with: .color(lead.opacity(0.10 + 0.30 * age)),
                   style: StrokeStyle(lineWidth: baseWidth * 0.6, lineCap: .round))
        let dx = b.x - a.x, dy = b.y - a.y, len = max(0.001, hypot(dx, dy))
        let ux = dx / len, uy = dy / len, px = -uy, py = ux
        let seed = Double(i) * 12.9898
        for k in 0..<3 {
            let f = (Double(k) + 0.5) / 3.0
            let jit = CGFloat((seed * Double(k + 1)).truncatingRemainder(dividingBy: 1.0) - 0.5) * baseWidth * 0.7
            let mx = a.x + dx * CGFloat(f) + px * jit, my = a.y + dy * CGFloat(f) + py * jit
            let l2 = baseWidth * 0.55
            var m = Path()
            m.move(to: CGPoint(x: mx - ux * l2, y: my - uy * l2))
            m.addLine(to: CGPoint(x: mx + ux * l2, y: my + uy * l2))
            let op = (0.10 + 0.5 * age) * (0.4 + 0.6 * (seed * Double(k + 3)).truncatingRemainder(dividingBy: 1.0))
            ctx.stroke(m, with: .color(lead.opacity(op)),
                       style: StrokeStyle(lineWidth: max(0.5, baseWidth * 0.16), lineCap: .round))
        }
    }
}

/// Rose — sheds rose petals that settle where they're laid and dissipate in
/// place over a short life (like the fire/ice trails), rather than being towed
/// along behind the ball.  A faint rose stem fades beneath them so the path
/// still reads.  `times` drives each petal's own lifecycle so it lives and dies
/// on its own clock wherever it was dropped, independent of the ball's motion.
private func trailRose(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int, _ t: Double, _ baseWidth: CGFloat,
                       _ times: [Double]?) {
    let lifetime = 1.3
    let stem = Color(red: 0.42, green: 0.06, blue: 0.18)
    let petals = [Color(red: 0.85, green: 0.20, blue: 0.40),
                  Color(red: 0.95, green: 0.45, blue: 0.60),
                  Color(red: 0.62, green: 0.10, blue: 0.28)]

    // Faint stem connecting recent points, fading out as it ages so it doesn't
    // read as a permanent ribbon towed behind the ball.
    for i in 1..<n {
        let age = trailAge(i, n, t, times, lifetime: lifetime)
        guard age < lifetime else { continue }
        let env = max(0, 1 - age / lifetime)
        var p = Path(); p.move(to: pts[i - 1]); p.addLine(to: pts[i])
        ctx.stroke(p, with: .color(stem.opacity(0.22 * env)),
                   style: StrokeStyle(lineWidth: baseWidth * 0.5, lineCap: .round, lineJoin: .round))
    }

    // Petals — dropped along the path and left behind.  Each is pinned to the
    // spot it was laid (a fixed point in `pts`): it pops in, then gently settles
    // (falls + sways + slowly turns) IN PLACE while it fades, and vanishes.
    // Whether a spot sheds a petal is a stable function of its position, so the
    // scatter doesn't flicker as the FIFO buffer shifts indices underneath it.
    for i in 0..<n {
        let p = pts[i]
        let seed = trailSeed(p)
        let r1 = seed.truncatingRemainder(dividingBy: 1.0)
        guard r1 < 0.34 else { continue }                    // stable thinning of shed spots
        let age = trailAge(i, n, t, times, lifetime: lifetime)
        guard age < lifetime else { continue }
        let life = age / lifetime
        let rise = min(1.0, age / 0.06)                      // pop in when shed
        let fade = life < 0.55 ? 1.0 : 1.0 - (life - 0.55) / 0.45
        let env  = rise * max(0, fade)
        guard env > 0.02 else { continue }

        let r2   = (seed * 2.13).truncatingRemainder(dividingBy: 1.0)
        let r3   = (seed * 5.70).truncatingRemainder(dividingBy: 1.0)
        let side = r2 < 0.5 ? CGFloat(-1) : CGFloat(1)
        let scatter = baseWidth * (0.2 + 0.6 * CGFloat(r2))  // sits just off the path
        let sway = CGFloat(sin(t * 1.6 + seed * 6.283)) * baseWidth * 0.22 * CGFloat(life)
        let fall = CGFloat(life) * baseWidth * 0.55          // gentle drop as it settles
        let cx = p.x + side * scatter + sway
        let cy = p.y + fall
        let sz = baseWidth * CGFloat(0.32 + 0.26 * r3) * (1.0 - 0.22 * CGFloat(life))
        let rot = seed * 6.283 + t * 0.5 + Double(life) * 1.0   // slow turn in place
        drawPetal(ctx, CGPoint(x: cx, y: cy), sz, rot,
                  petals[Int(r3 * 3) % 3].opacity(0.82 * env))
    }
}

/// One rotated rose petal (a pointed leaf shape).
private func drawPetal(_ ctx: GraphicsContext, _ c: CGPoint, _ s: CGFloat, _ rot: Double, _ color: Color) {
    let ca = CGFloat(cos(rot)), sa = CGFloat(sin(rot))
    func rp(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: c.x + x * ca - y * sa, y: c.y + x * sa + y * ca)
    }
    var petal = Path()
    petal.move(to: rp(0, -s))
    petal.addQuadCurve(to: rp(0, s), control: rp(s * 0.9, 0))
    petal.addQuadCurve(to: rp(0, -s), control: rp(-s * 0.9, 0))
    petal.closeSubpath()
    ctx.fill(petal, with: .color(color))
}

/// Fire — flickering little flames left along the trail.
private func trailFire(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int, _ t: Double, _ baseWidth: CGFloat,
                       _ times: [Double]?) {
    var ctx = ctx
    ctx.blendMode = .plusLighter
    let lifetime = 0.9
    for i in 0..<n {
        let age = trailAge(i, n, t, times, lifetime: lifetime)
        guard age < lifetime else { continue }
        let life = age / lifetime
        let rise = min(1.0, age / 0.05)                          // quick flare-up when laid
        let env  = life < 0.55 ? 1.0 : 1.0 - (life - 0.55) / 0.45 // burn steady, then die down
        let intensity = rise * max(0, env)
        guard intensity > 0.02 else { continue }
        let p = pts[i]
        let seed = trailSeed(p)                                  // stable per-spot flicker phase
        let flick = 0.65 + 0.35 * sin(t * 11 + seed * 6.283)
        let grow  = 0.55 + 0.45 * intensity                     // flames sink as they die
        let h = baseWidth * CGFloat(1.5 + 1.2 * flick) * CGFloat(grow)
        let w = baseWidth * 0.85 * CGFloat(0.6 + 0.4 * intensity)
        let sway = CGFloat(sin(t * 7 + seed * 6.283)) * w * 0.35
        let baseY = p.y + w * 0.5
        // Heat glow pooled at the foot so a fresh flame reads hot.
        let gr = w * 1.5
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - gr, y: p.y - gr * 0.5, width: gr * 2, height: gr)),
            with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.5, blue: 0.15).opacity(0.22 * intensity), .clear]),
                center: CGPoint(x: p.x, y: p.y), startRadius: 0, endRadius: gr))
        // Outer flame (orange) — always licking upward.
        var flame = Path()
        flame.move(to: CGPoint(x: p.x, y: baseY))
        flame.addQuadCurve(to: CGPoint(x: p.x + sway, y: p.y - h), control: CGPoint(x: p.x + w, y: p.y))
        flame.addQuadCurve(to: CGPoint(x: p.x, y: baseY), control: CGPoint(x: p.x - w + sway, y: p.y))
        ctx.fill(flame, with: .color(Color(red: 1, green: 0.42, blue: 0.05).opacity(0.55 * intensity)))
        // Inner flame (yellow-white core).
        var inner = Path()
        inner.move(to: CGPoint(x: p.x, y: p.y + w * 0.2))
        inner.addQuadCurve(to: CGPoint(x: p.x + sway * 0.7, y: p.y - h * 0.6), control: CGPoint(x: p.x + w * 0.5, y: p.y))
        inner.addQuadCurve(to: CGPoint(x: p.x, y: p.y + w * 0.2), control: CGPoint(x: p.x - w * 0.5 + sway * 0.7, y: p.y))
        ctx.fill(inner, with: .color(Color(red: 1, green: 0.9, blue: 0.45).opacity(0.6 * intensity)))
    }
}

/// Mist / smoke — soft cloud puffs spreading in all directions.
private func trailMist(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int, _ t: Double, _ baseWidth: CGFloat, base: Color) {
    for i in 0..<n {
        let age = Double(i) / Double(n - 1)
        let p = pts[i]
        for k in 0..<3 {
            let ang = Double(k) * 2.1 + t * 0.5 + Double(i)
            let spread = baseWidth * CGFloat(1.0 + 2.0 * (1 - age))
            let ox = CGFloat(cos(ang)) * spread * 0.5, oy = CGFloat(sin(ang)) * spread * 0.5
            let pr = baseWidth * CGFloat(1.0 + 1.5 * age)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x + ox - pr, y: p.y + oy - pr, width: pr * 2, height: pr * 2)),
                with: .radialGradient(Gradient(colors: [base.opacity(0.08 * age + 0.04), .clear]),
                    center: CGPoint(x: p.x + ox, y: p.y + oy), startRadius: 0, endRadius: pr))
        }
    }
}

/// Stardust — twinkling stars spinning off the trail.
private func trailStardust(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int, _ t: Double, _ baseWidth: CGFloat) {
    trailTapered(ctx, pts, n, baseWidth * 0.5, color: Color(red: 0.85, green: 0.82, blue: 1.0), glow: true)
    var ctx = ctx
    ctx.blendMode = .plusLighter
    for i in 0..<n {
        let age = Double(i) / Double(n - 1)
        let tw = 0.4 + 0.6 * sin(t * 4 + Double(i) * 1.3)
        guard tw > 0.25 else { continue }
        let ang = t * 1.2 + Double(i) * 1.9
        let off = baseWidth * CGFloat(0.6 + 2.2 * (1 - age))
        let sx = pts[i].x + CGFloat(cos(ang)) * off, sy = pts[i].y + CGFloat(sin(ang)) * off
        let sz = baseWidth * CGFloat(0.22 + 0.30 * age)
        trailStar(ctx, CGPoint(x: sx, y: sy), sz, Color(red: 1, green: 0.98, blue: 0.85).opacity(tw * (0.3 + 0.6 * age)))
    }
}

/// Air — pillowy puffs that billow behind the ball and sway like a jet stream.
private func trailAir(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int, _ t: Double, _ baseWidth: CGFloat,
                      _ times: [Double]?) {
    let lifetime = 1.1
    for i in 0..<n {
        let age = trailAge(i, n, t, times, lifetime: lifetime)
        guard age < lifetime else { continue }
        let life = age / lifetime
        let rise = min(1.0, age / 0.08)
        let env  = rise * max(0, 1 - life)             // billow in, then fade out
        guard env > 0.02 else { continue }
        let p = pts[i]
        let seed = trailSeed(p)                        // stable per-spot drift phase
        // Each puff expands a little and lifts/sways AS IT AGES, in place.
        let expand = 1.0 + 0.8 * life
        let drift  = CGFloat(sin(t * 1.6 + seed * 6.283)) * baseWidth * 0.5
        let lift   = -CGFloat(life) * baseWidth * 0.8
        let pr = baseWidth * CGFloat(1.3 * expand)
        let cxp = p.x + drift, cyp = p.y + lift
        // Two overlapping lobes read as a soft cloud rather than a disc.
        for k in 0..<2 {
            let ox = CGFloat(k == 0 ? -0.32 : 0.32) * pr
            ctx.fill(Path(ellipseIn: CGRect(x: cxp + ox - pr, y: cyp - pr, width: pr * 2, height: pr * 2)),
                with: .radialGradient(Gradient(colors: [Color(red: 0.88, green: 0.94, blue: 1.0).opacity(0.18 * env), .clear]),
                    center: CGPoint(x: cxp + ox, y: cyp), startRadius: 0, endRadius: pr))
        }
    }
}

/// Ink — a wide, neat line while the pen moves; where the ball lingers the ink
/// pools and bleeds outward, wider the longer it dwells, like a pen held to
/// paper.  Dwell is read from the time GAP between successive points: fast
/// strokes lay points in quick succession (tiny gaps → a crisp line); a resting
/// ball stops laying new points, so the last gap keeps growing and that spot's
/// blot bleeds wider and wider until it saturates.  Once the pen moves on, each
/// spot's gap is fixed, so the bled blot stays exactly where it was set.
private func trailInk(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int, _ t: Double, _ baseWidth: CGFloat,
                      _ times: [Double]?) {
    let ink      = Color(red: 0.07, green: 0.07, blue: 0.12)
    let neatR    = baseWidth * 0.65          // half-width of the crisp stroke (wider than before)
    let maxBleed = baseWidth * 3.5           // cap so a long rest can't flood the whole page
    let tau      = 0.22                       // dwell time-constant for the bleed ramp (s)

    // 1) Crisp connecting line through every point — the pen stroke itself.
    //    A gentle fade over the oldest few points hides the FIFO pop as marks
    //    scroll off the tail (ink that's "run out" of the visible window).
    for i in 1..<n {
        let tailFade = min(1.0, Double(i + 1) / Double(n))      // ~0 tail → 1 head
        var p = Path(); p.move(to: pts[i - 1]); p.addLine(to: pts[i])
        ctx.stroke(p, with: .color(ink.opacity(0.25 + 0.60 * tailFade)),
                   style: StrokeStyle(lineWidth: neatR * 2, lineCap: .round, lineJoin: .round))
    }

    // 2) Bleed blots — radius grows with how long the pen dwelled at each spot.
    for i in 0..<n {
        let dwell: Double
        if let times, i < times.count {
            let next = (i < times.count - 1) ? times[i + 1] : t  // head keeps growing while at rest
            dwell = max(0, next - times[i])
        } else {
            // No timing (shop preview): synthesize a little pooling toward the
            // head so the cell still sells the bleed.
            let f = n > 1 ? Double(i) / Double(n - 1) : 0
            dwell = f * f * 0.4
        }
        let bleed = CGFloat(Double(maxBleed) * (1 - exp(-dwell / tau)))
        let r = neatR + bleed
        guard r > neatR + 0.5 else { continue }                  // skip spots that didn't pool
        let tailFade = min(1.0, Double(i + 1) / Double(n))
        let p = pts[i]
        // Soft-edged ink puddle: near-solid core feathering to a wet rim.
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(Gradient(stops: [
                .init(color: ink.opacity(0.85 * tailFade), location: 0.00),
                .init(color: ink.opacity(0.78 * tailFade), location: 0.60),
                .init(color: ink.opacity(0.0),             location: 1.00)]),
                center: p, startRadius: 0, endRadius: r))
    }
}

/// Rainbow — a glowing, hue-cycling streak (now a Legendary).
private func trailRainbow(_ ctx: GraphicsContext, _ pts: [CGPoint], _ n: Int, _ t: Double, _ baseWidth: CGFloat) {
    var ctx = ctx
    for i in 1..<n {
        let age = Double(i) / Double(n - 1)
        // `t * 0.30` (was 0.15) ripples the spectrum along the trail twice as fast.
        let hue = (Double(i) / Double(n) + t * 0.30).truncatingRemainder(dividingBy: 1)
        let col = Color(hue: hue, saturation: 1, brightness: 1)
        let w = baseWidth * CGFloat(0.4 + 0.8 * age)
        var p = Path(); p.move(to: pts[i - 1]); p.addLine(to: pts[i])
        ctx.blendMode = .plusLighter
        ctx.stroke(p, with: .color(col.opacity(0.20 * age)), style: StrokeStyle(lineWidth: w * 2.2, lineCap: .round))
        ctx.blendMode = .normal
        ctx.stroke(p, with: .color(col.opacity(0.20 + 0.7 * age)), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
}

/// A small 4-point sparkle star (used by the stardust trail).
private func trailStar(_ ctx: GraphicsContext, _ c: CGPoint, _ s: CGFloat, _ color: Color) {
    var star = Path()
    for k in 0..<8 {
        let a = Double(k) * .pi / 4 - .pi / 2
        let rad = (k % 2 == 0) ? s : s * 0.4
        let p = CGPoint(x: c.x + CGFloat(cos(a)) * rad, y: c.y + CGFloat(sin(a)) * rad)
        if k == 0 { star.move(to: p) } else { star.addLine(to: p) }
    }
    star.closeSubpath()
    ctx.fill(star, with: .color(color))
}

// ---------------------------------------------------------------------------
// Shareable result card — the cheapest virality unlock (roadmap Phase 1).
// A round-over overlay builds a ShareableResult and drops in a
// ResultShareButton; the card rasterises to an image and goes out the system
// share sheet, carrying the player's cosmetics + a "beat me" hook.
// ---------------------------------------------------------------------------

/// The data a round-over share card needs.  Mode-agnostic so every competitive
/// (and solo) overlay can build one from its own final state + the player's gear.
struct ShareableResult {
    let mode: String        // "Gold Rush", "King of the Hill", …
    let headline: String    // the big number/verdict, e.g. "1,240 coins"
    let subtitle: String?   // optional flavour, e.g. "2nd of 4"
    let skin: BallSkin      // the player's equipped skin — their identity
    let trail: TrailColor   // the player's equipped trail
    let won: Bool           // tints the card gold on a win
}

/// The visual shared on a win/round-over: the player's ball + their result +
/// a "can you beat me?" hook.  Fixed size so it rasterises predictably.
struct ResultShareCard: View {
    let result: ShareableResult

    var body: some View {
        VStack(spacing: 16) {
            Text(result.mode.uppercased())
                .font(.system(size: 15, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.85))

            ZStack {
                // A few fading dots trailing into the ball, in the equipped trail.
                if result.trail != .none {
                    ForEach(0..<6) { i in
                        Circle()
                            .fill(result.trail.color.opacity(0.10 + Double(i) * 0.07))
                            .frame(width: 26, height: 26)
                            .offset(x: CGFloat(i - 5) * 17)
                    }
                }
                BallSkinView(skin: result.skin, diameter: 116)
                    .frame(width: 116, height: 116)
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 3))
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 7)
            }
            .frame(height: 130)

            VStack(spacing: 4) {
                Text(result.headline)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let sub = result.subtitle {
                    Text(sub)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 3) {
                HStack(spacing: 7) {
                    Image(systemName: "circle.circle.fill").font(.system(size: 18))
                    Text("ROLL ALONG")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .tracking(1)
                }
                .foregroundStyle(.white)
                Text("Can you beat me?")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(26)
        .frame(width: 320, height: 400)
        .background(
            LinearGradient(
                colors: result.won
                    ? [Color(red: 0.22, green: 0.17, blue: 0.02), Color(red: 0.48, green: 0.36, blue: 0.05)]
                    : [Color(red: 0.07, green: 0.09, blue: 0.16), Color(red: 0.14, green: 0.17, blue: 0.30)],
                startPoint: .top, endPoint: .bottom)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(result.won ? Color(red: 1.0, green: 0.84, blue: 0.30).opacity(0.6)
                                   : .white.opacity(0.15), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

/// Renders a ShareableResult to a shareable SwiftUI Image (≈3× for crispness).
@MainActor
func renderResultCard(_ result: ShareableResult) -> Image? {
    let renderer = ImageRenderer(content: ResultShareCard(result: result))
    renderer.scale = 3
    guard let ui = renderer.uiImage else { return nil }
    return Image(uiImage: ui)
}

/// A drop-in Share button for round-over overlays: renders the card once, shares
/// it via the system sheet, and fires the `result_shared` analytics event.
struct ResultShareButton: View {
    let result: ShareableResult
    @State private var card: Image?

    var body: some View {
        Group {
            if let card {
                ShareLink(
                    item: card,
                    subject: Text("Roll Along — \(result.mode)"),
                    // The image carries the score + mode; the body is a warm,
                    // social invite about the app's breadth, not this one round.
                    message: Text("Come roll with me! 🌀 A whole pile of quick games to mess around in, your own marble to deck out, and clans so we can squad up. Fair warning: it's weirdly addictive."),
                    preview: SharePreview("Roll Along — \(result.mode)", image: card)
                ) { shareLabel }
                .simultaneousGesture(TapGesture().onEnded {
                    AnalyticsClient.shared.track("result_shared",
                                                 properties: ["mode": .string(result.mode)])
                })
            } else {
                shareLabel.opacity(0.5)   // brief moment while the card renders
            }
        }
        .onAppear { if card == nil { card = renderResultCard(result) } }
    }

    private var shareLabel: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.and.arrow.up")
            Text("Share")
        }
        .font(.system(size: 17, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.25), lineWidth: 1))
    }
}
