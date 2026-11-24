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
    /// True if the item can be bought with coins (individually or via a coin
    /// bundle) — i.e. not the free starter and not an exclusive (earned / IAP /
    /// event-only) item. A protocol REQUIREMENT (not just an extension method)
    /// so generic code dispatches to a type's override. Defaulted below.
    var isCoinPurchasable: Bool { get }
    /// Un-sellable special (starter look + permanent earned/IAP specials). A
    /// protocol REQUIREMENT so generic Sell-Back code dispatches to a type's
    /// override. Defaulted to starter-only below; seasonal items are NOT iconic.
    var isIconic: Bool { get }
}

extension CosmeticItem {
    var isCoinPurchasable: Bool { tier != .starter }

    // MARK: - Iconic & sellability

    /// "Iconic" = the un-sellable special cosmetics: the classic starter look and
    /// the permanent earned/IAP specials (Diamond, Money, Trophy, Aurora).  These
    /// are kept by Sell Back and carry the "Iconic" badge instead of a tier
    /// rarity.  Default is starter-only; types with permanent specials override.
    /// IMPORTANT: seasonal / limited-time cosmetics are NOT iconic — they're
    /// sellable (liquidated back into coins, per design).
    var isIconic: Bool { tier == .starter }

    /// True when Sell Back can liquidate this item for coins — everything that
    /// isn't the starter look or a permanent Iconic special, including seasonal /
    /// limited-time cosmetics.  `Self.starter` (the slot's Roll Along piece) is
    /// excluded explicitly as a guard: Sell Back re-grants every category's
    /// starter, so refunding one would mint coins on every pass.
    var isSellable: Bool { !isIconic && self != Self.starter }

    /// True for this slot's piece of the Iconic Roll Along set (the default).
    var isRollAlongPiece: Bool { self == Self.starter }

    /// `items` with this slot's Roll Along piece moved to the front (other
    /// items keep their order).  Catalog tabs and the Locker list it first.
    static func rollAlongFirst(_ items: [Self]) -> [Self] {
        items.filter(\.isRollAlongPiece) + items.filter { !$0.isRollAlongPiece }
    }

    /// Player-facing rarity word: "Iconic" for un-sellable specials, otherwise
    /// the tier's rarity name (Standard / Rare / Epic / Legendary).
    var rarityLabel: String { isIconic ? "Iconic" : tier.label }

    /// Badge accent — a distinct prismatic magenta for Iconic, else the tier color.
    var rarityColor: Color { isIconic ? Self.iconicColor : tier.color }

    /// Metallic gem colours for the shop-card rarity gem — silver / gold /
    /// amethyst / diamond by tier, with a vivid prismatic gradient for Iconic.
    /// Mirrors `rarityColor`, but feeds the gem badge's gradient.
    var rarityGemColors: [Color] { isIconic ? Self.iconicGemColors : tier.gemColors }

    /// Every item earns a badge now: Iconic items included (the plain classic
    /// look reads as "Iconic"), so this is always true.
    var showsRarityBadge: Bool { true }

    /// Shared Iconic accent — sits apart from the gray→blue→cyan→purple→gold
    /// tier ramp so "Iconic" reads as its own thing, above Legendary.
    static var iconicColor: Color { Color(red: 0.96, green: 0.45, blue: 0.85) }

    /// Iconic gem gradient — prismatic magenta→violet, set apart from the
    /// metallic tier ramp so "Iconic" reads as its own thing.
    static var iconicGemColors: [Color] {
        [Color(red: 1.00, green: 0.62, blue: 0.96), Color(red: 0.70, green: 0.30, blue: 0.95)]
    }
}

extension BallSkin {
    /// Exclusive balls are never coin-purchasable — earned (trophy), IAP
    /// (diamond, money), or seasonal-event drops — so the coin-liquidation
    /// reset keeps them.
    // Aurora is no longer here — it is a regular coin-buyable Legendary ball
    // anchoring the Aurora bundle, sellable when coin-bought.  The Starter
    // Pack welcome offer grants the Aurora ball, trail and boundary
    // free-granted (see StoreKitManager.grantStarterPackItems), which Sell
    // Back keeps but never refunds.
    static let coinExclusiveBalls: Set<BallSkin> =
        [.trophy, .beachBall, .pumpkin, .ornament, .heartstone,
         .shamrock, .confetti, .speckledEgg, .diamond, .moneyBall,
         .waitingRoom]
    var isCoinPurchasable: Bool { tier != .starter && !Self.coinExclusiveBalls.contains(self) }

    /// Permanent un-sellable specials (Iconic): earned (Trophy) and the IAP
    /// secrets (Diamond, Money).  The OTHER `coinExclusiveBalls` (beachBall,
    /// pumpkin, ornament, heartstone, shamrock, confetti, speckledEgg) are
    /// seasonal / limited-time event balls — SELLABLE via Sell Back.
    static let iconicBalls: Set<BallSkin> = [.trophy, .diamond, .moneyBall, .waitingRoom]
    var isIconic: Bool { tier == .starter || Self.iconicBalls.contains(self) }

    /// Balls that exist only in the Locker, and only once owned: never in the
    /// Shop, the Catalog (even when owned), a collection, the release
    /// calendar or a gift pool.  The Diamond ball comes only with the
    /// Diamond Balls purchase.
    static let lockerOnlyBalls: Set<BallSkin> = [.diamond]
    var isLockerOnly: Bool { Self.lockerOnlyBalls.contains(self) }
}

/// Tier roughly corresponds to price + rarity.
///
/// Pricing is structural — every item in a tier costs the tier's
/// `basePrice`.  Adjust the constants below to re-balance the whole
/// catalogue at once.
///
/// The ladder encodes the approved time-to-afford targets
/// (docs/economy/07-decisions.md, ruling 2): Standard 30 min, Rare 40,
/// Epic 50, Legendary 60 minutes of typical play at ~25 coins/min —
/// hence 750 / 1,000 / 1,250 / 1,500.  Two invariants when repricing:
///   1. Every price stays EVEN forever — Sell Back refunds exactly half
///      the CURRENT cost as an integer (sellBackValue = min(cost/2, paid)).
///   2. Only ever drift prices UP (ruling 4's planned inflation); never cut.
///
/// Naming convention exposed to players (in the shop UI) maps to:
///   • standard   → "Standard"
///   • rare       → "Rare"
///   • premium    → "Epic"
///   • exclusive  → "Legendary"
enum CosmeticTier: String, Codable {
    case starter        // free, always owned
    case standard       // 750 coins — entry-level skins, tutorial-reward eligible
    case rare           // 1,000 coins — a notch up; distinctive but not flashy
    case premium        // 1,250 coins — flashier visuals, mid-grind
    case exclusive      // 1,500 coins — top-tier, the longest save or IAP territory
}

extension CosmeticTier {
    /// Single source of truth for every priceable cosmetic.  An item's
    /// `coinCost` just reads through to `tier.basePrice` — no per-item
    /// overrides.  Keeps the catalogue self-consistent.
    /// 250-step ladder, all even (exact sell-back halves 375/500/625/750).
    var basePrice: Int {
        switch self {
        case .starter:   return 0
        case .standard:  return 750
        case .rare:      return 1000
        case .premium:   return 1250
        case .exclusive: return 1500
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

    /// Metallic gem ramp for the shop-card rarity gem — silver → gold →
    /// amethyst → diamond.  (`color` above stays the flat legacy accent used
    /// elsewhere, e.g. the profile music chip.)  Lighter shade first.
    var gemColors: [Color] {
        switch self {
        case .starter:   return [Color(white: 0.78), Color(white: 0.50)]
        case .standard:  return [Color(white: 0.95), Color(white: 0.62)]                 // silver
        case .rare:      return [Color(red: 1.00, green: 0.87, blue: 0.48),
                                 Color(red: 0.84, green: 0.55, blue: 0.15)]              // gold
        case .premium:   return [Color(red: 0.82, green: 0.58, blue: 1.00),
                                 Color(red: 0.50, green: 0.26, blue: 0.80)]              // amethyst (Epic)
        case .exclusive: return [Color(red: 0.85, green: 0.97, blue: 1.00),
                                 Color(red: 0.38, green: 0.80, blue: 0.98)]              // diamond
        }
    }

    /// Catalog sort order — ascending rarity: the free/"iconic" starter items up
    /// top, then Standard, Rare, Epic, and Legendary (exclusive) last.
    var sortRank: Int {
        switch self {
        case .starter:   return 0
        case .standard:  return 1
        case .rare:      return 2
        case .premium:   return 3
        case .exclusive: return 4
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
             .gold, .silver, .copper, .jade, .ruby,
             .blaze, .droplet, .thundercloud,   // starter element sets
             .pencil:                           // Sketchbook (replaces Silver in the set)
            return .standard   //  750 coins — all mono-shaded
        case .opal,
             .pastel, .neon, .dune, .paper,
             .basketball, .soccer, .baseball, .eightBall, .golfBall,
             .geode,           // Geode bundle — Epic (banded agate + druzy core)
             .cathedral:       // Cathedral bundle — Epic (stained-glass rosette)
            return .premium    // 1,250 coins (Epic) — colour blends + sports/paper balls
        case .snowglobe, .pluto, .ufo, .aquarium, .marble,
             .storm, .candy, .ghost, .lava, .trench, .disco,
             .galaxy,          // audit 2026-07 ruling 1(c): R4 animated spiral — Legendary
             .nebula,          // audit 2026-07 ruling 1(c): R4 animated blobs+stars — Legendary
             .lavaLamp,        // audit 2026-07 ruling 1(c): R4 MeshGradient+wax blobs — Legendary
             .highRoller,      // High Roller bundle — coin/bundle purchasable
             .quicksilver,     // Quicksilver bundle — coin/bundle purchasable
             .oracle,          // Oracle bundle — coin/bundle purchasable
             .plasmaGlobe,     // Plasma Globe bundle — coin/bundle purchasable
             .magmaCore,       // Magma Core bundle — coin/bundle purchasable
             .hologram,        // Neon City bundle — coin/bundle purchasable (animated)
             .clockwork,       // Clockwork bundle — coin/bundle purchasable (animated)
             .fireworks,       // Star-Spangled seasonal — coin/bundle purchasable (animated)
             .sugarSkull,      // Día de los Muertos seasonal — coin/bundle purchasable
             .harvest,         // Harvest Moon seasonal — coin/bundle purchasable
             .lunarDragon,     // Lunar New Year seasonal — coin/bundle purchasable
             .mardiGras,       // Mardi Gras seasonal — coin/bundle purchasable
             .spectrum,        // Spectrum seasonal — coin/bundle purchasable
             .oktoberfest,     // Oktoberfest seasonal — coin/bundle purchasable
             .apple,           // Back to School seasonal — coin/bundle purchasable
             .earth, .mars, .saturn, .mercury,        // planets are Legendary now
             .neptune, .jupiter, .venus, .uranus,
             .trophy,           // golden-gauntlet-exclusive; never coin-purchasable
             .waitingRoom,      // end room gift (1.1); never coin-purchasable
             .aurora,          // Legendary — coin-buyable; anchors the Aurora bundle
             .beachBall,       // summer-2026-exclusive; never coin-purchasable
             .pumpkin,         // halloween-2026-exclusive; never coin-purchasable
             .ornament,        // winter-2026-exclusive; never coin-purchasable
             .heartstone,      // valentines-2027-exclusive; never coin-purchasable
             .shamrock,        // stpatricks-2027-exclusive; never coin-purchasable
             .confetti,        // newyear-2027-exclusive; never coin-purchasable
             .speckledEgg,     // spring-2027-exclusive; never coin-purchasable
             .diamond,         // Diamond Balls IAP-exclusive; never coin-purchasable
             .moneyBall:       // top-coin-pack ($49.99) IAP secret exclusive; never coin-purchasable
            return .exclusive  // 1,500 coins (Legendary) — animated / special / planets
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

    // Standard (750 coins) — the FITA archery target
    case archery        // 5-band FITA target (was the default during dev)
    // Standard (750 coins) — static banded targets (no particles / animation),
    // themed so thematically-related bundles can share one goal.
    case frost          // icy blue + white rings
    case ember          // warm red → orange → yellow rings
    case meadow         // forest-green + cream rings
    case bullion        // bronze → gold → cream rings
    case amethyst       // deep-violet + lavender rings
    case candy          // rose → white → pink rings
    case slate          // greyscale rings
    // Standard (750 coins) — static ring-portals (glowing concentric tunnels,
    // no particles / animation, so still Standard tier).
    case vortex         // cosmic-blue glowing portal
    case wormhole       // violet/magenta glowing portal
    // Standard (750 coins) — starter element sets, static drawn goals.
    case flameRing      // Fire set: a burning hoop of flickering flames around a white-hot center
    case whirlpool      // Water set: slowly turning spiral water arms into a deep blue center
    case thunderRing    // Storm set ("Storm Eye"): rolling cloud wall around a calm eye
    // ── Sketchbook (quality round) — Standard (750 coins), static ──
    case scribble       // hand-drawn pencil target on paper (replaces Archery in the set)

    // Epic / Legendary — particle portals (animated)
    case galaxy         // deep-space spiral
    case crystal        // prismatic shards
    case flame          // warm orange/red particles
    case blossom        // pinks + corals (cherry-blossom palette)
    case mosaic         // muted multi-hue particles
    case ripple         // blue-cyan calm
    case comet          // pale white-blue streaks on near-black

    // Premium / Epic (1,250 coins)
    case rainbow        // ★ the sparkly full-spectrum portal (restored)
    case neon           // hot magenta-pink on pure black
    case eclipse        // orange-red corona around a black core
    case plasma         // saturated violet-purple
    case mirage         // shimmery yellow-orange

    // Exclusive / Legendary (1,500 coins)
    case prism          // refracting full-spectrum desat
    case obsidian       // monochromatic deep-blue
    case quasar         // hot magenta + cyan, brightest in the catalogue
    case holeInOne      // golf hole with red flag (Golf bundle)
    case tractorBeam    // ★ NEW (Space Travel bundle) — UFO beam column
    case inferno        // Hellfire bundle — molten lava ring with flame licks
    case halo           // Heavens bundle — radiant golden halo + light rays
    case doodle         // Paper World bundle — hand-drawn pencil bullseye on paper
    case soccerNet      // Soccer bundle — goal mouth with white netting
    case aurora         // Aurora bundle — glowing northern-lights portal
    // ── Quality round: Haunted ──
    case pentagram      // Haunted — a fiery pentagram burning on charred stone
    // ── Nature (quality round) ──
    case leafWreath     // Nature set: a woven ring of leaves and tiny blossoms (replaces Meadow in the set)
    // ── Citrus set (quality round) ──
    case citrusSlice    // Citrus set: a cut citrus wheel, slowly turning (replaces Flame there)
    case winnersCircle  // Champion — a gold laurel wreath around a deep-crimson winner's circle
    // ── Standard audit: Nightclub ──
    case vinyl          // Nightclub — a record on the turntable, slowly turning (replaces Mosaic there)
    // ── Nature (owner request): replaces Leaf Wreath in the set ──
    case treeStump      // Nature — a mossy tree stump seen from above; the growth rings are the target

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .aurora:    return "Aurora"
        case .target:    return "Target"
        case .archery:   return "Archery"
        case .frost:     return "Frost"
        case .ember:     return "Ember"
        case .meadow:    return "Meadow"
        case .bullion:   return "Bullion"
        case .amethyst:  return "Amethyst"
        case .candy:     return "Candy"
        case .slate:     return "Slate"
        case .vortex:    return "Vortex"
        case .wormhole:  return "Wormhole"
        case .flameRing:   return "Flame Ring"
        case .whirlpool:   return "Whirlpool"
        case .thunderRing: return "Storm Eye"
        case .scribble:    return "Scribble"
        case .citrusSlice: return "Citrus Slice"
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
        case .inferno:     return "Inferno"
        case .halo:        return "Halo"
        case .doodle:      return "Doodle"
        case .soccerNet:   return "Soccer Net"
        case .pentagram:   return "Pentagram"   // quality round: Haunted
        // ── Nature (quality round) ──
        case .leafWreath:  return "Leaf Wreath"
        case .winnersCircle: return "Winner's Circle"
        // ── Standard audit: Nightclub ──
        case .vinyl:       return "Vinyl"
        // ── Nature (owner request) ──
        case .treeStump:   return "Tree Stump"
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
        case .target, .archery, .holeInOne, .tractorBeam,
             .inferno, .halo, .doodle, .soccerNet, .aurora,
             .frost, .ember, .meadow, .bullion, .amethyst, .candy, .slate,
             .vortex, .wormhole, .flameRing, .whirlpool, .thunderRing,
             .scribble, .citrusSlice:
            // Not actually consumed (their renderers are bespoke / static), but
            // we keep a placeholder so callers can read it uniformly.
            return HoleStyle(hueBase: 0.0, hueRange: 1.0, saturation: 1.0, bgColor: .clear)
        // ── Nature (quality round) ── bespoke static renderer, placeholder only.
        case .leafWreath, .treeStump:
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
        // — Quality round: Champion — (bespoke renderer; placeholder style)
        case .winnersCircle:
            return HoleStyle(hueBase: 0.12, hueRange: 0.05, saturation: 0.9,
                             bgColor: Color(red: 0.20, green: 0.02, blue: 0.05))
        case .pentagram:   // quality round: Haunted — bespoke renderer, placeholder only
            return HoleStyle(hueBase: 0.03, hueRange: 0.06, saturation: 1.0, bgColor: .clear)
        // ── Standard audit: Nightclub ── (bespoke renderer; placeholder style)
        case .vinyl:
            return HoleStyle(hueBase: 0.86, hueRange: 0.04, saturation: 0.8,
                             bgColor: Color(red: 0.03, green: 0.03, blue: 0.04))
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
    static func previewGradient(for goal: GoalSkin, endRadius: CGFloat = 28) -> AnyShapeStyle {
        switch goal {
        case .aurora:
            // Glowing aurora portal — bright teal-cyan core fading out through
            // violet, on the deep night sky.
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color(red: 0.80, green: 1.00, blue: 0.92), location: 0.00),
                    .init(color: Color(red: 0.24, green: 0.90, blue: 0.74), location: 0.30),
                    .init(color: Color(red: 0.26, green: 0.66, blue: 0.95), location: 0.58),
                    .init(color: Color(red: 0.55, green: 0.40, blue: 1.00), location: 0.82),
                    .init(color: Color(red: 0.04, green: 0.06, blue: 0.14), location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: endRadius))
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
                center: .center, startRadius: 0, endRadius: endRadius
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
                center: .center, startRadius: 0, endRadius: endRadius
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
                center: .center, startRadius: 0, endRadius: endRadius))
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
                center: .center, startRadius: 0, endRadius: endRadius))
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
        case .inferno:
            // Fiery portal — dark molten core bleeding to orange/red.
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color(red: 0.04, green: 0.00, blue: 0.00), location: 0.00),
                    .init(color: Color(red: 0.10, green: 0.01, blue: 0.00), location: 0.40),
                    .init(color: Color(red: 0.95, green: 0.30, blue: 0.05), location: 0.78),
                    .init(color: Color(red: 1.00, green: 0.74, blue: 0.22), location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: endRadius))
        case .halo:
            // Heavenly glow — warm white-gold core into soft sky blue.
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color(red: 1.00, green: 0.98, blue: 0.86), location: 0.00),
                    .init(color: Color(red: 1.00, green: 0.86, blue: 0.40), location: 0.45),
                    .init(color: Color(red: 0.74, green: 0.86, blue: 1.00), location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: endRadius))
        case .doodle:
            // Pencil bullseye on cream paper — grey rings, dark centre.
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color(red: 0.22, green: 0.22, blue: 0.26), location: 0.00),
                    .init(color: Color(red: 0.22, green: 0.22, blue: 0.26), location: 0.22),
                    .init(color: Color(red: 0.97, green: 0.96, blue: 0.90), location: 0.22),
                    .init(color: Color(red: 0.97, green: 0.96, blue: 0.90), location: 0.55),
                    .init(color: Color(red: 0.35, green: 0.35, blue: 0.40), location: 0.55),
                    .init(color: Color(red: 0.97, green: 0.96, blue: 0.90), location: 0.72),
                    .init(color: Color(red: 0.35, green: 0.35, blue: 0.40), location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: endRadius))
        case .soccerNet:
            // White net over a dark goal mouth with a green grass base.
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color.white,                               location: 0.00),
                    .init(color: Color(red: 0.85, green: 0.88, blue: 0.92), location: 0.45),
                    .init(color: Color(red: 0.18, green: 0.22, blue: 0.28), location: 0.80),
                    .init(color: Color(red: 0.30, green: 0.60, blue: 0.26), location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: endRadius))
        case .frost, .ember, .meadow, .bullion, .amethyst, .candy, .slate,
             .flameRing, .whirlpool, .thunderRing, .scribble, .citrusSlice:
            return AnyShapeStyle(Self.bandedTargetPreview(goal.targetBands ?? [], endRadius: endRadius))
        case .vortex, .wormhole:
            return AnyShapeStyle(Self.ringPortalPreview(goal.portalStops ?? [], endRadius: endRadius))
        case .pentagram:
            // Quality round (Haunted): charred disc, ember star glow, ring of fire.
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color(red: 0.03, green: 0.01, blue: 0.01), location: 0.00),
                    .init(color: Color(red: 0.16, green: 0.03, blue: 0.02), location: 0.50),
                    .init(color: Color(red: 0.92, green: 0.26, blue: 0.06), location: 0.80),
                    .init(color: Color(red: 1.00, green: 0.66, blue: 0.20), location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: endRadius))
        // ── Nature (quality round) ──
        case .leafWreath, .treeStump:
            return AnyShapeStyle(Self.bandedTargetPreview(goal.targetBands ?? [], endRadius: endRadius))
        case .winnersCircle:
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color(red: 0.42, green: 0.04, blue: 0.08), location: 0.00),
                    .init(color: Color(red: 0.62, green: 0.08, blue: 0.12), location: 0.42),
                    .init(color: Color(red: 1.00, green: 0.90, blue: 0.52), location: 0.46),
                    .init(color: Color(red: 0.86, green: 0.64, blue: 0.16), location: 0.78),
                    .init(color: Color(red: 0.36, green: 0.44, blue: 0.14), location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: endRadius))
        // ── Standard audit: Nightclub ──
        case .vinyl:
            return AnyShapeStyle(RadialGradient(
                stops: [
                    .init(color: Color(red: 0.03, green: 0.03, blue: 0.04), location: 0.00),
                    .init(color: Color(red: 0.03, green: 0.03, blue: 0.04), location: 0.10),
                    .init(color: Color(red: 0.92, green: 0.24, blue: 0.62), location: 0.12),
                    .init(color: Color(red: 0.92, green: 0.24, blue: 0.62), location: 0.36),
                    .init(color: Color(red: 0.08, green: 0.08, blue: 0.10), location: 0.38),
                    .init(color: Color(red: 0.14, green: 0.14, blue: 0.17), location: 1.00),
                ],
                center: .center, startRadius: 0, endRadius: endRadius))
        }
    }
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    static var starter: GoalSkin { .target }

    /// Ordered band colours (OUTER → INNER) for the static banded-target
    /// Standard goals.  nil for goals with bespoke / particle renderers.  Read
    /// by BOTH the thumbnail preview and the in-game `bandedTargetGoal` renderer
    /// so a goal looks identical everywhere.
    var targetBands: [Color]? {
        switch self {
        case .frost:    return [Color(red: 0.16, green: 0.40, blue: 0.72), .white,
                                Color(red: 0.46, green: 0.80, blue: 0.99)]
        case .ember:    return [Color(red: 0.45, green: 0.08, blue: 0.05),
                                Color(red: 1.00, green: 0.52, blue: 0.16),
                                Color(red: 1.00, green: 0.84, blue: 0.32)]
        case .meadow:   return [Color(red: 0.10, green: 0.36, blue: 0.16),
                                Color(red: 0.95, green: 0.96, blue: 0.84),
                                Color(red: 0.42, green: 0.78, blue: 0.34)]
        case .bullion:  return [Color(red: 0.45, green: 0.32, blue: 0.10),
                                Color(red: 0.98, green: 0.92, blue: 0.70),
                                Color(red: 0.96, green: 0.78, blue: 0.26)]
        case .amethyst: return [Color(red: 0.28, green: 0.12, blue: 0.48),
                                Color(red: 0.86, green: 0.80, blue: 0.98),
                                Color(red: 0.62, green: 0.36, blue: 0.95)]
        case .candy:    return [Color(red: 0.90, green: 0.28, blue: 0.50), .white,
                                Color(red: 1.00, green: 0.58, blue: 0.78)]
        case .slate:    return [Color(red: 0.20, green: 0.22, blue: 0.26),
                                Color(red: 0.82, green: 0.84, blue: 0.88),
                                Color(red: 0.42, green: 0.45, blue: 0.50)]
        case .flameRing:   return [Color(red: 0.55, green: 0.06, blue: 0.04),
                                   Color(red: 0.96, green: 0.30, blue: 0.10),
                                   Color(red: 1.00, green: 0.88, blue: 0.50)]
        case .whirlpool:   return [Color(red: 0.06, green: 0.22, blue: 0.56),
                                   Color(red: 0.30, green: 0.62, blue: 0.96),
                                   Color(red: 0.02, green: 0.08, blue: 0.24)]
        case .thunderRing: return [Color(red: 0.16, green: 0.17, blue: 0.22),
                                   Color(red: 0.46, green: 0.48, blue: 0.55),
                                   Color(red: 0.82, green: 0.86, blue: 0.92)]
        // ── Nature (quality round) ──
        case .leafWreath:  return [Color(red: 0.12, green: 0.38, blue: 0.16),
                                   Color(red: 0.50, green: 0.80, blue: 0.38),
                                   Color(red: 0.05, green: 0.20, blue: 0.08)]
        // ── Nature (owner request) ── bark, heartwood, dark heart.
        case .treeStump:   return [Color(red: 0.36, green: 0.24, blue: 0.14),
                                   Color(red: 0.88, green: 0.76, blue: 0.54),
                                   Color(red: 0.20, green: 0.12, blue: 0.07)]
        case .scribble:    return [Color(red: 0.96, green: 0.96, blue: 0.94),
                                   Color(red: 0.62, green: 0.62, blue: 0.64),
                                   Color(red: 0.20, green: 0.20, blue: 0.22)]
        case .citrusSlice: return [Color(red: 0.98, green: 0.62, blue: 0.10),
                                   Color(red: 1.00, green: 0.95, blue: 0.80),
                                   Color(red: 1.00, green: 0.80, blue: 0.22)]
        default:        return nil
        }
    }

    /// Concentric portal colours (OUTER dark → INNER bright) for the static
    /// ring-portal Standard goals.  nil for non-portal goals.
    var portalStops: [Color]? {
        switch self {
        case .vortex:   return [Color(red: 0.02, green: 0.02, blue: 0.09),
                                Color(red: 0.10, green: 0.20, blue: 0.55),
                                Color(red: 0.20, green: 0.50, blue: 0.95),
                                Color(red: 0.55, green: 0.90, blue: 1.00)]
        case .wormhole: return [Color(red: 0.04, green: 0.00, blue: 0.07),
                                Color(red: 0.28, green: 0.06, blue: 0.48),
                                Color(red: 0.82, green: 0.16, blue: 0.85),
                                Color(red: 1.00, green: 0.62, blue: 0.96)]
        default:        return nil
        }
    }

    /// Thumbnail builder: hard concentric bands (OUTER → INNER), reading as a
    /// ringed target at swatch size.
    static func bandedTargetPreview(_ bands: [Color], endRadius: CGFloat = 28) -> RadialGradient {
        guard !bands.isEmpty else {
            return RadialGradient(colors: [.gray], center: .center, startRadius: 0, endRadius: endRadius)
        }
        let inner = Array(bands.reversed())            // index 0 = centre
        let n = inner.count
        var stops: [Gradient.Stop] = []
        for (i, c) in inner.enumerated() {
            stops.append(.init(color: c, location: Double(i)     / Double(n)))
            stops.append(.init(color: c, location: Double(i + 1) / Double(n)))
        }
        return RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: endRadius)
    }

    /// Thumbnail builder: a smooth glowing portal (bright centre → dark edge).
    static func ringPortalPreview(_ stops: [Color], endRadius: CGFloat = 28) -> RadialGradient {
        guard !stops.isEmpty else {
            return RadialGradient(colors: [.black], center: .center, startRadius: 0, endRadius: endRadius)
        }
        return RadialGradient(colors: Array(stops.reversed()),   // bright centre first
                              center: .center, startRadius: 0, endRadius: endRadius)
    }

    /// Representative accent colour for this goal.  Used to theme effects that
    /// reference the equipped goal but aren't the full portal art — the launch
    /// vortex glow + spiral trail and the goal-reached burst — so the equipped
    /// goal reads consistently everywhere, not just on the in-game portal.
    var accentColor: Color {
        switch self {
        case .aurora:      return Color(red: 0.30, green: 0.88, blue: 0.74)   // aurora teal-cyan
        case .target:      return Color(red: 0.90, green: 0.18, blue: 0.20)
        case .archery:     return Color(red: 1.00, green: 0.80, blue: 0.20)
        case .frost:       return Color(red: 0.50, green: 0.82, blue: 1.00)
        case .ember:       return Color(red: 1.00, green: 0.55, blue: 0.18)
        case .meadow:      return Color(red: 0.42, green: 0.80, blue: 0.34)
        case .bullion:     return Color(red: 0.98, green: 0.80, blue: 0.30)
        case .amethyst:    return Color(red: 0.66, green: 0.42, blue: 0.98)
        case .candy:       return Color(red: 1.00, green: 0.58, blue: 0.80)
        case .slate:       return Color(red: 0.62, green: 0.68, blue: 0.78)
        case .vortex:      return Color(red: 0.40, green: 0.80, blue: 1.00)
        case .wormhole:    return Color(red: 0.92, green: 0.35, blue: 0.92)
        case .flameRing:   return Color(red: 1.00, green: 0.40, blue: 0.14)
        case .whirlpool:   return Color(red: 0.36, green: 0.66, blue: 1.00)
        case .thunderRing: return Color(red: 1.00, green: 0.90, blue: 0.45)
        case .scribble:    return Color(red: 0.42, green: 0.42, blue: 0.46)
        case .citrusSlice: return Color(red: 1.00, green: 0.72, blue: 0.16)
        case .galaxy:      return Color(red: 0.55, green: 0.55, blue: 1.00)
        case .crystal:     return Color(red: 0.55, green: 0.88, blue: 1.00)
        case .flame:       return Color(red: 1.00, green: 0.50, blue: 0.12)
        case .blossom:     return Color(red: 1.00, green: 0.62, blue: 0.78)
        case .mosaic:      return Color(red: 0.95, green: 0.45, blue: 0.85)
        case .ripple:      return Color(red: 0.45, green: 0.85, blue: 1.00)
        case .comet:       return Color(red: 0.75, green: 0.90, blue: 1.00)
        case .rainbow:     return Color(red: 1.00, green: 0.30, blue: 0.85)
        case .neon:        return Color(red: 1.00, green: 0.15, blue: 0.70)
        case .eclipse:     return Color(red: 1.00, green: 0.78, blue: 0.32)
        case .plasma:      return Color(red: 0.70, green: 0.40, blue: 1.00)
        case .mirage:      return Color(red: 1.00, green: 0.82, blue: 0.45)
        case .prism:       return Color(red: 0.80, green: 0.90, blue: 1.00)
        case .obsidian:    return Color(red: 0.35, green: 0.45, blue: 0.80)
        case .quasar:      return Color(red: 1.00, green: 0.25, blue: 0.90)
        case .holeInOne:   return Color(red: 0.40, green: 0.80, blue: 0.30)
        case .tractorBeam: return Color(red: 0.30, green: 0.95, blue: 0.55)
        case .inferno:     return Color(red: 1.00, green: 0.45, blue: 0.10)
        case .halo:        return Color(red: 1.00, green: 0.86, blue: 0.42)
        case .doodle:      return Color(red: 0.55, green: 0.60, blue: 0.75)
        case .soccerNet:   return Color(red: 0.85, green: 0.92, blue: 1.00)
        case .pentagram:   return Color(red: 1.00, green: 0.36, blue: 0.10)   // quality round: Haunted
        // ── Nature (quality round) ──
        case .leafWreath:  return Color(red: 0.46, green: 0.82, blue: 0.36)
        case .winnersCircle: return Color(red: 1.00, green: 0.84, blue: 0.36)
        // ── Standard audit: Nightclub ──
        case .vinyl:       return Color(red: 0.95, green: 0.30, blue: 0.66)
        // ── Nature (owner request) ── warm heartwood.
        case .treeStump:   return Color(red: 0.86, green: 0.70, blue: 0.44)
        }
    }
    /// Tier rule (player-facing: Standard / Epic / Legendary):
    ///   • Standard  — truly static art: solid-banded targets OR static
    ///                 ring-portals (no particles, no animation).
    ///   • Epic      — particle portals with a tight palette / mono
    ///                 hue range (animated but visually focused).
    ///   • Legendary — animated portals whose particles span the full
    ///                 spectrum or carry a special-effect treatment.
    var tier: CosmeticTier {
        switch self {
        case .target:
            return .starter
        case .archery,
             .frost, .ember, .meadow, .bullion, .amethyst, .candy, .slate,
             .vortex, .wormhole, .flameRing, .whirlpool, .thunderRing,
             .scribble:
            return .standard   //  750 coins — static targets + static ring-portals
        case .galaxy, .crystal, .flame, .blossom,
             .ripple, .comet, .eclipse, .plasma,
             .mirage, .obsidian,
             .citrusSlice:     // Citrus set — takes the tier of the Flame goal it replaced there
            return .premium    // 1,250 coins — animated, tight palette
        case .rainbow, .neon, .mosaic, .prism, .quasar, .holeInOne, .tractorBeam,
             .inferno, .halo, .doodle, .soccerNet, .aurora:
            return .exclusive  // 1,500 coins — animated, full-spectrum, or bespoke
        case .pentagram:
            return .premium    // quality round: takes the tier of Obsidian, which it replaces in Haunted
        // ── Nature (quality round) ── takes Meadow's tier (it replaces Meadow in the set).
        case .leafWreath:
            return .standard
        case .winnersCircle:
            return .exclusive
        // ── Standard audit: Nightclub ── takes the tier of Mosaic, which it replaces there.
        case .vinyl:
            return .exclusive
        // ── Nature (owner request) ── takes Leaf Wreath's tier (it replaces it in the set).
        case .treeStump:
            return .standard
        }
    }
}

// MARK: - Trail colors (the streak left behind the ball)
enum TrailColor: String, CosmeticItem {
    // Starter
    case none           // no trail — free "Off" option in the shop
    case classic        // THE default — a faint pressed-in shadow; equipped from first launch (Roll Along set)
    case graphite       // Sketchbook's pencil-lead trail (Standard; no longer a default)

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
    case moneyRoll      // ★ top-coin-pack ($49.99) IAP secret — green trail + fluttering bills
    case aurora         // Aurora bundle — teal→cyan→violet shimmer ribbon
    // Standard — starter element sets (static marks that fade where laid).
    case wildfire       // Fire set: a charred line under tall, forked, deep-red flames
    case splash         // Water set: blue line with droplets and ripple rings
    case squall         // Storm set: driving rain — mist, slanted streaks, splash rings
    // ── Citrus set (quality round) ──
    case zest           // Citrus set: curls of orange and lemon peel with juice drops (replaces Ember there)
    case victoryLap     // Champion: gold ribbon with ticker-tape confetti that flutters down and settles
    case glyphs         // Ancient Temple: carved glyphs pressed into the sand along the path
    // ── Standard audit: Nightclub / Golf / Ocean ──
    case danceSteps     // Nightclub: dance-floor tiles that light up where the ball rolled, then dim
    case dewLine        // Golf: the dark line a ball leaves through morning dew, with dew drops beside it
    case wake           // Ocean: a boat's wake — two foam lines that spread apart and dissolve

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none:        return "Off"
        case .classic:     return "Classic Shadow"
        case .aurora:      return "Aurora"
        case .graphite:    return "Graphite"
        case .moneyRoll:   return "Money Roll"
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
        case .wildfire:    return "Wildfire"
        case .splash:      return "Splash"
        case .squall:      return "Squall"
        case .zest:        return "Zest"
        // — Quality round: Champion / Ancient Temple —
        case .victoryLap:  return "Victory Lap"
        case .glyphs:      return "Glyphs"
        // — Standard audit: Nightclub / Golf / Ocean —
        case .danceSteps:  return "Dance Steps"
        case .dewLine:     return "Dew Line"
        case .wake:        return "Wake"
        }
    }
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    /// The default-equipped trail: Classic, a faint pressed-in shadow (part of
    /// the Iconic Roll Along set).  Not .none, so a brand-new player sees the
    /// ball's path from the very first roll; "Off" stays a free starter-tier
    /// choice for players who prefer no trail.
    static var starter: TrailColor { .classic }
    /// Tier rule:
    ///   • Standard  — solid mono-colour trails.
    ///   • Epic      — multi-colour trails (per-segment hue cycle).
    ///   • Legendary — animated / mechanical trails (grow with
    ///                 coins, sparkle, etc.).
    var tier: CosmeticTier {
        switch self {
        case .none, .classic:
            return .starter
        case .sky, .forest, .bubblegum, .wildfire, .splash, .squall,
             .graphite:        // Sketchbook's pencil trail — priced like its set's other pieces
            return .standard   //  750 coins — solid mono colour
        case .snake, .raybeam, .gilded,
             .zest,            // Citrus set — takes the tier of the Ember trail it replaced there
             .ember:           // audit 2026-07 ruling 1(c): rides the plusLighter glow path — Rare
            return .rare       // 1,000 coins — distinctive textured trails
        case .fire, .cometTrail, .stardust, .smoke, .ice, .rainbow, .air, .aurora,
             .ink,             // audit 2026-07 ruling 1(c): bespoke dwell/bleed lifecycle — Legendary
             .roseTrail,       // audit 2026-07 ruling 1(c): full trailAge petal lifecycle — Legendary
             .moneyRoll:       // top-coin-pack ($49.99) IAP secret — Legendary, never coin-bought
            return .exclusive  // 1,500 coins — animated / special-effect
        // — Quality round — each takes the tier of the trail it replaces.
        case .victoryLap:      // Champion (replaces Comet)
            return .exclusive
        case .glyphs:          // Ancient Temple (replaces Snake)
            return .rare
        // — Standard audit — each takes the tier of the trail it replaces.
        case .danceSteps:      // Nightclub (replaces Rainbow)
            return .exclusive
        case .dewLine:         // Golf (replaces Air)
            return .exclusive
        case .wake:            // Ocean (replaces Sky)
            return .standard
        }
    }

    /// Hidden from the shop/catalog grid (shown only once owned) and never
    /// surfaced as a coin purchase — the Money Roll trail is granted ONLY by the
    /// $49.99 top coin pack (historical ID coins.10000), mirroring the Diamond ball.
    var isBundleExclusive: Bool { self == .moneyRoll }
    var isCoinPurchasable: Bool { tier != .starter && !isBundleExclusive }
    var isIconic: Bool { tier == .starter || self == .moneyRoll }   // Money Roll = IAP secret

    /// SwiftUI Color used when rendering this trail.  `.none` returns
    /// clear; `.rainbow` returns a placeholder colour (the actual
    /// rainbow effect is a per-segment Canvas hue cycle in BallGameView).
    var color: Color {
        switch self {
        case .none:        return .clear
        case .classic:     return Color.black.opacity(0.22)   // hue-less shadow; renderer adds the light edge
        case .aurora:      return Color(red: 0.28, green: 0.92, blue: 0.78).opacity(0.85)   // teal base; renderer adds the violet shimmer
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
        case .moneyRoll:   return Color(red: 0.20, green: 0.62, blue: 0.34).opacity(0.85)  // money green; bills in renderer
        case .wildfire:    return Color(red: 0.86, green: 0.16, blue: 0.08).opacity(0.85)
        case .splash:      return Color(red: 0.22, green: 0.52, blue: 0.95).opacity(0.80)
        case .squall:      return Color(red: 0.46, green: 0.48, blue: 0.54).opacity(0.80)
        case .zest:        return Color(red: 0.98, green: 0.62, blue: 0.12).opacity(0.85)
        // — Quality round: Champion / Ancient Temple —
        case .victoryLap:  return Color(red: 0.98, green: 0.80, blue: 0.30).opacity(0.92)   // gold ribbon; confetti in renderer
        case .glyphs:      return Color(red: 0.60, green: 0.40, blue: 0.20).opacity(0.80)   // carved-sand shadow
        // — Standard audit: Nightclub / Golf / Ocean —
        case .danceSteps:  return Color(red: 0.98, green: 0.30, blue: 0.72).opacity(0.85)   // lit tile; tiles in renderer
        case .dewLine:     return Color(red: 0.10, green: 0.34, blue: 0.14).opacity(0.55)   // dark line through dew
        case .wake:        return Color(red: 0.92, green: 0.97, blue: 1.00).opacity(0.85)   // foam
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

    // Standard (750 coins) — static solid floor colour
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
    case fog              // Haunted bundle — dark flagstones with fog drifting over them
    case scorched         // Fire starter set — burnt flagstones: soot, cracks, faintly glowing seams, embers
    case shallows         // Water starter set — sandy bottom under clear water, slow sunlight moving over it
    case overcast         // Storm starter set — slate cloud cover with a faint yellow streak

    // Exclusive / Legendary (1,500 coins) — animated floor overlays
    case aurora           // the original shimmer
    case disco            // colour-cycling dance-floor squares
    case grass            // golf-course turf with grass tufts (Golf bundle)
    case moon             // ★ NEW (Space Travel bundle) — lunar regolith + craters
    case eclipse          // Eclipse bundle — dark void behind a glowing corona ring

    // Sports bundles (new)
    case court            // Full Court bundle — warm hardwood basketball floor
    case felt             // Billiards Hall bundle — deep-green pool-table felt

    // Premium bundles (textured overlays)
    case gridCity         // Neon City bundle — synthwave neon perspective grid
    case brass            // Clockwork bundle — riveted brass/bronze plating

    // top-coin-pack ($49.99) IAP secret — overlapping stack of $100 bills
    case moneyFull
    // ── Citrus and Midas sets (quality round) ──
    case grove            // Citrus set — sunlit sand under citrus-leaf shade, fallen blossoms
    case goldLeaf         // Midas set — hammered gold-leaf tiles
    // ── Standard audit: Bloom and Ocean ──
    case petalPath        // Bloom — a pale garden path strewn with fallen petals and tiny leaves
    case openSea          // Ocean — deep open water seen from above: slow swell lines and drifting foam
    // ── End room gift (1.1; never sold) ──
    case waitingRoom      // Waiting Room — the classic white floor in colour-shifting foil

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classic:    return "Classic White"
        case .moneyFull:  return "Money Full"
        case .inverted:   return "Inverted"
        case .twilight:   return "Snowfield"   // id stays "twilight" (Winter set: blue-hour snow)
        case .ember:      return "Ember"
        case .notebook:   return "Notebook"
        case .graph:      return "Graph"
        case .blueprint:  return "Blueprint"
        case .dusk:       return "Dusk"
        case .meadow:     return "Meadow"
        case .parchment:  return "Parchment"
        case .sketch:     return "Paper"
        case .velvet:     return "Velvet"
        case .midnight:   return "Midnight"
        case .sunset:     return "Sunset"
        case .origami:    return "Origami"
        case .mirage:     return "Mirage"
        case .desert:     return "Desert"
        case .stormcloud: return "Stormcloud"
        case .sugar:      return "Sugar"
        case .fog:        return "Fog"
        case .scorched:   return "Scorched"
        case .shallows:   return "Shallows"
        case .overcast:   return "Overcast"
        case .grove:      return "Grove"
        case .goldLeaf:   return "Gold Leaf"
        case .petalPath:  return "Petal Path"
        case .openSea:    return "Open Sea"
        case .waitingRoom: return "Waiting Room"
        case .aurora:     return "Aurora"
        case .disco:      return "Disco"
        case .grass:      return "Grass"
        case .moon:       return "Moon"
        case .eclipse:    return "Eclipse"
        case .court:      return "Court"
        case .felt:       return "Felt"
        case .gridCity:   return "Grid City"
        case .brass:      return "Brass Works"
        }
    }
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    static var starter: Floor { .classic }
    var tier: CosmeticTier {
        switch self {
        case .classic:
            return .starter
        case .inverted, .twilight, .ember,
             .blueprint, .dusk, .meadow,
             .velvet, .midnight, .sunset,
             .mirage, .desert, .stormcloud, .sugar, .fog,
             .court, .felt,
             .scorched, .shallows, .overcast,   // starter element sets
             .grove, .goldLeaf,                 // Citrus and Midas sets (replace Dusk / Mirage there)
             .openSea:                          // Ocean (replaces Blueprint there)
            return .standard   //  750 coins
        case .notebook, .graph, .parchment, .sketch, .origami,
             .petalPath:                        // Bloom (replaces Parchment there; takes its tier)
            // audit 2026-07 ruling 1(c): bespoke static texture overlays
            // (ruled lines / grid / vignette+specks / cross-hatch / fold
            // shadows) — exactly the Rare bar; opens the floors Rare rung.
            return .rare       // 1,000 coins — static texture overlay
        case .aurora, .disco, .grass, .moon, .eclipse, .gridCity, .brass,
             .moneyFull,       // top-coin-pack ($49.99) IAP secret — Legendary, never coin-bought
             .waitingRoom:     // end room gift (1.1) — never coin-bought
            return .exclusive  // 1,500 coins — animated / textured overlay
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
        case .ember:      return Color(red: 0.115, green: 0.090, blue: 0.090)  // cooled basalt crust; fissures glow over it
        case .notebook:   return Color(red: 0.980, green: 0.961, blue: 0.902)
        case .graph:      return Color(red: 0.984, green: 0.984, blue: 0.984)
        case .blueprint:  return Color(red: 0.18,  green: 0.36,  blue: 0.62 )
        case .dusk:       return Color(red: 0.95,  green: 0.72,  blue: 0.62 )
        case .meadow:     return Color(red: 0.78,  green: 0.90,  blue: 0.72 )
        case .parchment:  return Color(red: 0.914, green: 0.863, blue: 0.753)
        case .sketch:     return Color(red: 0.980, green: 0.980, blue: 0.965)
        case .velvet:     return Color(red: 0.35,  green: 0.12,  blue: 0.45 )
        case .midnight:   return Color(red: 0.012, green: 0.016, blue: 0.045)  // space black; stars twinkle over it
        case .sunset:     return Color(red: 0.98,  green: 0.55,  blue: 0.25 )
        case .origami:    return Color(red: 0.961, green: 0.937, blue: 0.878)
        case .mirage:     return Color(red: 0.92,  green: 0.82,  blue: 0.55 )
        case .desert:     return Color(red: 0.90,  green: 0.78,  blue: 0.55 )  // warm sand
        case .stormcloud: return Color(red: 0.32,  green: 0.36,  blue: 0.44 )  // slate storm
        case .sugar:      return Color(red: 0.99,  green: 0.92,  blue: 0.95 )  // pale candy-pink
        case .fog:        return Color(red: 0.085, green: 0.105, blue: 0.115)  // dark, damp flagstones; fog drifts over them
        case .scorched:   return Color(red: 0.62,  green: 0.26,  blue: 0.20 )  // scorched red stone
        case .shallows:   return Color(red: 0.40,  green: 0.70,  blue: 0.86 )  // clear, sunlit shallow water
        case .overcast:   return Color(red: 0.34,  green: 0.36,  blue: 0.42 )  // dark storm cloud
        case .grove:      return Color(red: 0.96,  green: 0.89,  blue: 0.70 )  // sunlit beach sand
        case .goldLeaf:   return Color(red: 0.46,  green: 0.34,  blue: 0.11 )  // antique gold leaf: well darker than a coin and than the Vault pit's rim
        case .petalPath:  return Color(red: 0.93,  green: 0.89,  blue: 0.83 )  // pale garden-path stone
        case .openSea:    return Color(red: 0.05,  green: 0.24,  blue: 0.40 )  // deep open water
        case .waitingRoom: return Color(red: 0.925, green: 0.925, blue: 0.935) // silvery white foil; the sheen paints over
        case .aurora:     return Color(red: 0.030, green: 0.050, blue: 0.105)  // dark night sky; a few faint ribbons cross it
        case .disco:      return Color(red: 0.10,  green: 0.10,  blue: 0.14 )  // dark; squares paint over
        case .grass:      return Color(red: 0.35,  green: 0.62,  blue: 0.28 )  // fairway green; tufts paint over
        case .moon:       return Color(red: 0.62,  green: 0.62,  blue: 0.66 )  // pale regolith; craters paint over
        case .eclipse:    return Color(red: 0.04,  green: 0.04,  blue: 0.10 )  // dark void; corona paints over
        case .court:      return Color(red: 0.84,  green: 0.65,  blue: 0.38 )  // warm hardwood
        case .felt:       return Color(red: 0.18,  green: 0.48,  blue: 0.24 )  // pool-table green
        case .gridCity:   return Color(red: 0.03,  green: 0.02,  blue: 0.08 )  // near-black; neon grid paints over
        case .brass:      return Color(red: 0.52,  green: 0.37,  blue: 0.16 )  // warm bronze; plating paints over
        case .moneyFull:  return Color(red: 0.74,  green: 0.83,  blue: 0.72 )  // pale bill-green; $100s paint over
        }
    }

    /// Hidden from the shop/catalog grid (shown only once owned) and never a coin
    /// purchase — the Money Full floor is granted ONLY by the $49.99 /
    /// top ($49.99) coin pack, mirroring the Diamond ball.
    var isBundleExclusive: Bool { self == .moneyFull || self == .waitingRoom }
    var isCoinPurchasable: Bool { tier != .starter && !isBundleExclusive }
    var isIconic: Bool { tier == .starter || self == .moneyFull || self == .waitingRoom }   // Money Full = IAP secret; Waiting Room = end room gift

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
        case .aurora, .disco, .grass, .moon, .eclipse, .gridCity, .brass, .moneyFull,
             .overcast: return true
        case .shallows: return true   // Water set: slow caustic light over the still sand
        case .fog, .midnight, .ember: return true   // quality round: slow fog, twinkling stars, glowing fissures
        case .openSea: return true                  // standard audit: slow swell and drifting foam
        case .waitingRoom: return true              // end room gift: slow colour-shifting foil sheen
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

    // Standard (750 coins) — static (flat color or drawn art; never animates)
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
    case aurora           // Rare — full of slowly swaying aurora curtains
    case canyon           // Round-5 Dune bundle — deep rust gorge
    case downpour         // Round-5 Tempest bundle — dark rainy blue
    case syrup            // Round-5 Candyland bundle — dark molasses
    case graveyard        // Rare — an open dirt grave with smoke rising from it (Haunted bundle)
    case crater           // Fire starter set — glowing red rim falling to a dark core
    case deepEnd          // Water starter set — a pool stepping down from a sunlit shelf to a dark middle
    case maelstrom        // Storm starter set — dark storm vortex with a yellow flash rim

    // Exclusive / Legendary (1,500 coins) — animated pit overlays
    case evil             // burning fire-pit animation
    case sky              // sky-blue gradient with drifting clouds
    case pond             // water with ripples + lily pad (Golf bundle)
    case space            // ★ NEW (Space Travel bundle) — starfield void
    case eclipse          // Eclipse bundle — dark void with a corona ring glow
    case nightclub        // Nightclub bundle — dark void with drifting disco lights

    // Sports bundles (new)
    case sideline         // Full Court bundle — dark-grey out-of-bounds edge
    case pocket           // Billiards Hall bundle — near-black pool pocket
    // ── Citrus and Midas sets (quality round) ──
    case tidePool         // Citrus set — a shaded tide pool: wet sand rim, turquoise shallows, dark deep
    case vault            // Midas set — a treasury vault: stepped gold walls down to a dark floor of coins
    case vent             // Abyssal Depths — deep-sea vent: basalt ledges, a glowing throat, rising bubbles
    // ── Standard audit: Bloom and Ocean ──
    case deepRose         // Bloom — looking down into a rose: rings of petals stepping down to a dark heart
    case reef             // Ocean — a coral reef drop-off: sunlit coral ledges stepping down into the blue
    // ── End room gift (1.1; never sold) ──
    case waitingRoom      // Waiting Room — the classic black pit in dark, colour-shifting foil

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classic:    return "Classic Black"
        case .waitingRoom: return "Waiting Room"
        case .inverted:   return "Inverted"
        case .twilight:   return "Crevasse"    // id stays "twilight" (Winter set: a crack in the ice)
        case .ember:      return "Ember"
        case .notebook:   return "Notebook"
        case .graph:      return "Blackout"
        case .blueprint:  return "Blueprint"
        case .dusk:       return "Dusk"
        case .meadow:     return "Meadow"
        case .parchment:  return "Parchment"
        case .sketch:     return "Sketch"
        case .velvet:     return "Velvet"
        case .midnight:   return "Moonlit"   // id stays "midnight"
        case .sunset:     return "Sunset"
        case .origami:    return "Origami"
        case .mirage:     return "Mirage"
        case .aurora:     return "Aurora"
        case .canyon:     return "Canyon"
        case .downpour:   return "Downpour"
        case .syrup:      return "Syrup"
        case .graveyard:  return "Graveyard"
        case .crater:     return "Crater"
        case .deepEnd:    return "Deep End"
        case .maelstrom:  return "Maelstrom"
        case .tidePool:   return "Tide Pool"
        case .vault:      return "Vault"
        case .evil:       return "Evil"
        case .sky:        return "Sky"
        case .pond:       return "Pond"
        case .space:      return "Space"
        case .eclipse:    return "Eclipse"
        case .nightclub:  return "Nightclub"
        case .sideline:   return "Sideline"
        case .pocket:     return "Pocket"
        // — Quality round: Abyssal Depths —
        case .vent:       return "Sea Vent"
        // — Standard audit: Bloom and Ocean —
        case .deepRose:   return "Deep Rose"
        case .reef:       return "Reef"
        }
    }
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    static var starter: Pit { .classic }
    /// The end room gift is never bought and never sold back.
    var isCoinPurchasable: Bool { tier != .starter && self != .waitingRoom }
    var isIconic: Bool { tier == .starter || self == .waitingRoom }
    var tier: CosmeticTier {
        switch self {
        case .classic:
            return .starter
        case .waitingRoom:
            return .exclusive  // end room gift (1.1); never coin-bought
        case .inverted, .twilight, .ember, .notebook, .graph,
             .blueprint, .dusk, .meadow,
             .parchment, .sketch, .velvet, .midnight, .sunset,
             .origami, .mirage, .canyon, .downpour, .syrup,
             .sideline, .pocket,
             .crater, .deepEnd, .maelstrom,   // starter element sets
             .tidePool, .vault,               // Citrus and Midas sets (replace Sunset / Mirage there)
             .deepRose, .reef:                // Bloom and Ocean (replace Parchment / Blueprint there)
            return .standard   //  750 coins — drawn art
        case .graveyard, .aurora:
            return .rare       // 1,000 coins — drawn art with gentle motion
        case .evil, .sky, .pond, .space, .eclipse, .nightclub:
            return .exclusive  // 1,500 coins — animated overlay
        // — Quality round: Abyssal Depths — (takes the Space pit's tier)
        case .vent:
            return .exclusive
        }
    }

    /// SwiftUI Color used as the base pit fill.  Animated pits
    /// (evil, sky) still have a base colour so non-overlay
    /// contexts render sensibly.
    var color: Color {
        switch self {
        case .classic:    return Color(red: 0.039, green: 0.039, blue: 0.039)
        case .waitingRoom: return Color(red: 0.035, green: 0.035, blue: 0.045)   // black foil; the sheen paints over
        case .inverted:   return Color(red: 0.941, green: 0.937, blue: 0.925)
        case .twilight:   return Color(red: 0.047, green: 0.059, blue: 0.122)
        case .ember:      return Color(red: 0.102, green: 0.039, blue: 0.039)
        case .notebook:   return Color(red: 0.169, green: 0.122, blue: 0.071)
        case .graph:      return Color(red: 0.020, green: 0.020, blue: 0.045)   // "Blackout": pitch black under a neon rim
        case .blueprint:  return Color(red: 0.04,  green: 0.10,  blue: 0.22 )
        case .dusk:       return Color(red: 0.18,  green: 0.06,  blue: 0.08 )
        case .meadow:     return Color(red: 0.06,  green: 0.18,  blue: 0.08 )
        case .parchment:  return Color(red: 0.102, green: 0.059, blue: 0.031)
        case .sketch:     return Color(red: 0.12,  green: 0.12,  blue: 0.14 )
        case .velvet:     return Color(red: 0.08,  green: 0.02,  blue: 0.12 )
        case .midnight:   return Color(red: 0.62,  green: 0.68,  blue: 0.82 )  // moonlit stone; the drawn well steps down to dark
        case .sunset:     return Color(red: 0.30,  green: 0.06,  blue: 0.04 )
        case .origami:    return Color(red: 0.094, green: 0.078, blue: 0.063)
        case .mirage:     return Color(red: 0.22,  green: 0.14,  blue: 0.05 )
        case .aurora:     return Color(red: 0.020, green: 0.030, blue: 0.090)  // deep indigo aurora void
        case .canyon:     return Color(red: 0.32,  green: 0.14,  blue: 0.08 )  // deep rust gorge
        case .downpour:   return Color(red: 0.10,  green: 0.16,  blue: 0.26 )  // dark rainy blue
        case .syrup:      return Color(red: 0.20,  green: 0.06,  blue: 0.10 )  // dark molasses
        case .graveyard:  return Color(red: 0.07,  green: 0.05,  blue: 0.035)  // dark grave soil
        case .crater:     return Color(red: 0.12,  green: 0.02,  blue: 0.01 )  // dark core; glowing rim drawn over
        case .deepEnd:    return Color(red: 0.02,  green: 0.07,  blue: 0.20 )  // deep water
        case .maelstrom:  return Color(red: 0.06,  green: 0.06,  blue: 0.09 )  // dark storm center
        case .tidePool:   return Color(red: 0.02,  green: 0.12,  blue: 0.16 )  // deep pool water
        case .vault:      return Color(red: 0.07,  green: 0.05,  blue: 0.02 )  // dark vault floor
        case .evil:       return Color(red: 0.10,  green: 0.02,  blue: 0.00 )  // dark base; flames paint over
        case .sky:        return Color(red: 0.55,  green: 0.78,  blue: 0.95 )  // pale blue base; clouds drift on top
        case .pond:       return Color(red: 0.08,  green: 0.30,  blue: 0.42 )  // deep water; ripples + lily pad on top
        case .space:      return Color(red: 0.02,  green: 0.02,  blue: 0.06 )  // near-black void; stars twinkle on top
        case .eclipse:    return Color(red: 0.03,  green: 0.02,  blue: 0.07 )  // near-black; corona ring on top
        case .nightclub:  return Color(red: 0.06,  green: 0.04,  blue: 0.10 )  // dark; disco lights drift on top
        case .sideline:   return Color(red: 0.14,  green: 0.14,  blue: 0.16 )  // dark court edge / out-of-bounds
        case .pocket:     return Color(red: 0.06,  green: 0.08,  blue: 0.06 )  // near-black pool pocket
        // — Quality round: Abyssal Depths —
        case .vent:       return Color(red: 0.02,  green: 0.04,  blue: 0.07 )  // black water; basalt ledges + vent glow drawn over
        // — Standard audit: Bloom and Ocean —
        case .deepRose:   return Color(red: 0.10,  green: 0.01,  blue: 0.04 )  // dark heart of the rose
        case .reef:       return Color(red: 0.01,  green: 0.06,  blue: 0.14 )  // deep blue beyond the reef
        }
    }

    /// True when the pit needs an animated Canvas overlay drawn on
    /// top of its base color (Evil flames, Sky clouds, Pond ripples,
    /// Space starfield).
    var hasAnimatedOverlay: Bool {
        switch self {
        case .evil, .sky, .pond, .space, .eclipse, .nightclub,
             .graveyard, .aurora, .maelstrom: return true
        case .waitingRoom: return true // end room gift: slow foil sheen
        case .vent: return true        // Quality round: Abyssal Depths
        case .tidePool: return true    // Quality-standard audit: Citrus tide
        default: return false
        }
    }

    /// True for pits whose look is drawn art (grass, gravestones, ruled
    /// paper, strata …) rather than a flat color.  That art is part of the
    /// pit itself, so it stays visible with Reduce Motion on (frozen for the
    /// two Rare pits, which are the only ones that move).
    var hasDrawnArt: Bool {
        switch self {
        case .meadow, .graveyard, .ember, .notebook, .graph, .blueprint,
             .parchment, .sketch, .origami, .velvet, .sunset, .mirage,
             .aurora, .canyon, .downpour, .syrup, .sideline, .pocket,
             .crater, .deepEnd, .maelstrom,
             .tidePool, .vault:
            return true
        // — Quality round: Winter's Crevasse (id twilight), Abyssal Depths' Sea Vent,
        //   Lava Flow's Evil pit and Cosmos' Moonlit pit (id midnight) —
        case .twilight, .vent, .evil, .midnight:
            return true
        // — Standard audit: Bloom's Deep Rose, Ocean's Reef, and the redrawn
        //   Golf Pond and Nightclub pits (drawn art now; they hold still
        //   under Reduce Motion instead of disappearing) —
        case .deepRose, .reef, .pond, .nightclub:
            return true
        // — End room gift (1.1): black foil, frozen under Reduce Motion —
        case .waitingRoom:
            return true
        default:
            return false
        }
    }
}

// MARK: - Boundary (walls / platforms / perimeter)
//
// The shared cosmetic for every solid play-surface boundary: Roll Out's maze
// walls + table rim, Roll Up's platforms, Roll Along's perimeter border, and
// interior wall "obstacles" in competitive modes.  NOT used by Zen Garden
// (no walls) or Pinball (its table art is bespoke).
//
// rawValue strings are persistence keys — don't rename existing cases.
enum Boundary: String, CosmeticItem {
    // Starter — the neutral grey the games shipped with.
    case classic

    // Standard (750 coins) — solid-colour walls
    case slate
    case ember
    case mint
    case sky
    case orchid
    case sand

    // Rare (1,000 coins) — richer hues
    case neon
    case gold
    case ice

    // Exclusive / Legendary (1,500 coins) — each has a bespoke animated
    // border renderer in BallGameView (obsidian molten sheen + embers,
    // candy scrolling stripes, circuit pulsing traces); `color` below is
    // only their base coat / Reduce Motion fallback.
    case obsidian
    case candy
    case circuit

    // ── Collection boundaries (every collection is a complete set) ──
    // Added so every collection carries a boundary that fits its theme.
    // Solid walls are Standard / Rare like the originals; the animated ones
    // are Legendary with a bespoke border renderer in `BoundaryOverlayView`,
    // and only go to collections that are already Legendary, so no
    // collection's rarity band changes.
    // Standard (750 coins)
    case notebook       // Paper World, Back to School — ruled-paper blue
    case fairway        // Golf, Soccer, Diamond — fresh pitch green
    case sunset         // Golden Hour — warm amber-coral
    case rose           // Bloom, Sweetheart — rose pink
    case ink            // Noir — inky charcoal
    case citrus         // Citrus — rind wall set with lemon, lime and orange slices
    case pastel         // Pastel, Spring Fling — soft lilac
    case pumpkin        // Halloween — pumpkin orange
    case holly          // Winter Wonderland — holly green
    case shamrock       // St. Patrick's — clover green
    case marigold       // Día de los Muertos — marigold orange
    case autumn         // Harvest Moon, Oktoberfest — russet
    case lantern        // Lunar New Year — lacquer red
    case hardwood       // Full Court — court maple
    case flare          // Fire starter set — a burning wall: flame licks creeping round a charred rim
    case breakers       // Water starter set — swells rolling round the rim, each led by a foam crest
    case thunderbolt    // Storm starter set — gray wall with yellow bolts
    // Rare (1,000 coins)
    case cloud          // Heavens — pale cloud white-blue
    case tide           // Ocean, Aquarium — sea teal
    case velvet         // Velvet Night — deep plum
    case marble         // Realistic Marble — polished white stone
    case phantom        // Haunted — ghostly pale green
    case mahogany       // Billiards Hall, High Roller — table-rail wood
    case sandstone      // Ancient Temple — carved terracotta
    case abyss          // Abyssal Depths — deep-sea navy
    case amethyst       // Crystal Cavern, Geode — crystal violet
    case chrome         // Quicksilver — mirror silver
    case brass          // Clockwork — polished brass
    // Exclusive / Legendary (1,500 coins) — animated border renderers
    case molten         // Hellfire, Lava Flow, Magma Core — creeping lava glow
    case starlight      // Planets, Space Travel, Cosmos, Oracle — twinkling stars
    case aurora         // Aurora — drifting green / violet curtains
    case corona         // Eclipse — black rim with a travelling golden flare
    case storm          // Tempest, Plasma Globe — lightning flicker
    case confetti       // Countdown (New Year) — scrolling confetti dashes
    case starSpangled   // Star-Spangled — red / white / blue bunting
    case rainbow        // Pride — the full spectrum cycling around the rim
    case marquee        // Midnight Carnival — chasing marquee bulbs
    case stainedGlass   // Cathedral — slowly glowing colored panes
    // — Quality round: Space Traveler —
    case hull           // Space Traveler — starship hull plating with slow running lights
    // — End room gift (1.1; never sold) —
    case waitingRoom    // Waiting Room — the classic grey wall in colour-shifting foil

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classic:  return "Classic Gray"
        case .waitingRoom: return "Waiting Room"
        case .slate:    return "Slate"
        case .ember:    return "Ember"
        case .mint:     return "Mint"
        case .sky:      return "Sky"
        case .orchid:   return "Orchid"
        case .sand:     return "Sand"
        case .neon:     return "Neon"
        case .gold:     return "Gold"
        case .ice:      return "Ice"
        case .obsidian: return "Obsidian"
        case .candy:    return "Candy"
        case .circuit:  return "Circuit"
        case .notebook:      return "Notebook"
        case .fairway:       return "Fairway"
        case .sunset:        return "Sunset"
        case .rose:          return "Rose"
        case .ink:           return "Ink"
        case .citrus:        return "Citrus"
        case .pastel:        return "Pastel"
        case .pumpkin:       return "Pumpkin"
        case .holly:         return "Holly"
        case .shamrock:      return "Shamrock"
        case .marigold:      return "Marigold"
        case .autumn:        return "Autumn"
        case .lantern:       return "Lantern"
        case .hardwood:      return "Hardwood"
        case .cloud:         return "Cloud"
        case .tide:          return "Tide"
        case .velvet:        return "Velvet"
        case .marble:        return "Marble"
        case .phantom:       return "Phantom"
        case .mahogany:      return "Mahogany"
        case .sandstone:     return "Sandstone"
        case .abyss:         return "Abyss"
        case .amethyst:      return "Amethyst"
        case .chrome:        return "Chrome"
        case .brass:         return "Brass"
        case .molten:        return "Molten"
        case .starlight:     return "Starlight"
        case .aurora:        return "Aurora"
        case .corona:        return "Corona"
        case .storm:         return "Storm"
        case .confetti:      return "Confetti"
        case .starSpangled:  return "Star-Spangled"
        case .rainbow:       return "Rainbow"
        case .marquee:       return "Marquee"
        case .stainedGlass:  return "Stained Glass"
        case .flare:         return "Flare"
        case .breakers:      return "Breakers"
        case .thunderbolt:   return "Thunderhead"
        // — Quality round: Space Traveler —
        case .hull:          return "Starship Hull"
        }
    }
    var coinCost: Int { tier.basePrice }
    var unlockLevel: Int { 0 }
    static var starter: Boundary { .classic }
    /// The end room gift is never bought and never sold back.
    var isCoinPurchasable: Bool { tier != .starter && self != .waitingRoom }
    var isIconic: Bool { tier == .starter || self == .waitingRoom }
    var tier: CosmeticTier {
        switch self {
        case .classic:
            return .starter
        case .waitingRoom:
            return .exclusive  // end room gift (1.1); never coin-bought
        case .slate, .ember, .mint, .sky, .orchid, .sand:
            return .standard   //  750 coins
        case .neon, .gold, .ice:
            return .rare       // 1,000 coins
        case .obsidian, .candy, .circuit:
            return .exclusive  // 1,500 coins
        case .notebook, .fairway, .sunset, .rose, .ink, .citrus, .pastel,
             .pumpkin, .holly, .shamrock, .marigold, .autumn, .lantern, .hardwood,
             .flare, .breakers, .thunderbolt:
            return .standard   //  750 coins — solid themed walls
        case .cloud, .tide, .velvet, .marble, .phantom, .mahogany,
             .sandstone, .abyss, .amethyst, .chrome, .brass:
            return .rare       // 1,000 coins — richer / material hues
        case .molten, .starlight, .aurora, .corona, .storm, .confetti,
             .starSpangled, .rainbow, .marquee, .stainedGlass:
            return .exclusive  // 1,500 coins — animated border renderer
        // — Quality round: Space Traveler — (takes Starlight's tier, the
        //   wall of the retired Space Travel set)
        case .hull:
            return .exclusive
        }
    }

    /// Base fill for the wall / platform / border.
    ///
    /// For the Legendary (animated) boundaries this is the base coat only:
    /// `BoundaryOverlayView` layers a bespoke animated texture on the screen
    /// border, and this flat colour is the static fallback under Reduce
    /// Motion and in non-animated contexts.
    var color: Color {
        switch self {
        case .classic:  return Color(white: 0.34)
        case .waitingRoom: return Color(white: 0.52)   // grey foil; the sheen paints over
        case .slate:    return Color(red: 0.36, green: 0.42, blue: 0.52)
        case .ember:    return Color(red: 0.78, green: 0.34, blue: 0.22)
        case .mint:     return Color(red: 0.34, green: 0.74, blue: 0.58)
        case .sky:      return Color(red: 0.34, green: 0.60, blue: 0.92)
        case .orchid:   return Color(red: 0.66, green: 0.40, blue: 0.86)
        case .sand:     return Color(red: 0.80, green: 0.68, blue: 0.44)
        case .neon:     return Color(red: 0.10, green: 0.92, blue: 0.74)
        case .gold:     return Color(red: 0.92, green: 0.74, blue: 0.28)
        case .ice:      return Color(red: 0.62, green: 0.84, blue: 0.96)
        case .obsidian: return Color(red: 0.16, green: 0.16, blue: 0.22)
        case .candy:    return Color(red: 0.98, green: 0.46, blue: 0.70)
        case .circuit:  return Color(red: 0.20, green: 0.70, blue: 0.55)
        case .notebook:      return Color(red: 0.56, green: 0.70, blue: 0.90)
        case .fairway:       return Color(red: 0.30, green: 0.66, blue: 0.32)
        case .sunset:        return Color(red: 0.96, green: 0.56, blue: 0.34)
        case .rose:          return Color(red: 0.90, green: 0.42, blue: 0.56)
        case .ink:           return Color(red: 0.20, green: 0.21, blue: 0.25)
        case .citrus:        return Color(red: 0.84, green: 0.86, blue: 0.26)
        case .pastel:        return Color(red: 0.84, green: 0.70, blue: 0.90)
        case .pumpkin:       return Color(red: 0.95, green: 0.52, blue: 0.14)
        case .holly:         return Color(red: 0.14, green: 0.48, blue: 0.30)
        case .shamrock:      return Color(red: 0.20, green: 0.70, blue: 0.36)
        case .marigold:      return Color(red: 0.98, green: 0.66, blue: 0.12)
        case .autumn:        return Color(red: 0.70, green: 0.36, blue: 0.18)
        case .lantern:       return Color(red: 0.82, green: 0.16, blue: 0.16)
        case .hardwood:      return Color(red: 0.80, green: 0.56, blue: 0.32)
        case .cloud:         return Color(red: 0.84, green: 0.90, blue: 0.98)
        case .tide:          return Color(red: 0.12, green: 0.56, blue: 0.66)
        case .velvet:        return Color(red: 0.42, green: 0.16, blue: 0.42)
        case .marble:        return Color(red: 0.88, green: 0.87, blue: 0.84)
        case .phantom:       return Color(red: 0.66, green: 0.80, blue: 0.74)
        case .mahogany:      return Color(red: 0.44, green: 0.18, blue: 0.12)
        case .sandstone:     return Color(red: 0.78, green: 0.48, blue: 0.32)
        case .abyss:         return Color(red: 0.06, green: 0.20, blue: 0.36)
        case .amethyst:      return Color(red: 0.56, green: 0.36, blue: 0.82)
        case .chrome:        return Color(red: 0.76, green: 0.79, blue: 0.84)
        case .brass:         return Color(red: 0.78, green: 0.62, blue: 0.28)
        case .molten:        return Color(red: 0.36, green: 0.08, blue: 0.04)
        case .starlight:     return Color(red: 0.08, green: 0.10, blue: 0.26)
        case .aurora:        return Color(red: 0.10, green: 0.42, blue: 0.40)
        case .corona:        return Color(red: 0.10, green: 0.08, blue: 0.06)
        case .storm:         return Color(red: 0.22, green: 0.26, blue: 0.36)
        case .confetti:      return Color(red: 0.30, green: 0.22, blue: 0.46)
        case .starSpangled:  return Color(red: 0.12, green: 0.20, blue: 0.52)
        case .rainbow:       return Color(red: 0.60, green: 0.30, blue: 0.90)
        case .marquee:       return Color(red: 0.40, green: 0.06, blue: 0.10)
        case .stainedGlass:  return Color(red: 0.10, green: 0.12, blue: 0.24)
        case .flare:         return Color(red: 0.78, green: 0.14, blue: 0.08)
        case .breakers:      return Color(red: 0.16, green: 0.42, blue: 0.86)
        case .thunderbolt:   return Color(red: 0.22, green: 0.23, blue: 0.28)
        // — Quality round: Space Traveler —
        case .hull:          return Color(red: 0.30, green: 0.33, blue: 0.40)
        }
    }

    /// True for the themed Standard / Rare walls whose texture is still (or
    /// only gently moving and freezes cleanly), so it stays drawn under
    /// Reduce Motion.  The Legendary animated walls keep their old rule:
    /// under Reduce Motion only the plain base stroke shows.
    var textureShowsUnderReduceMotion: Bool {
        switch self {
        case .ember, .notebook, .fairway, .sunset, .pastel, .holly, .autumn,
             .lantern, .hardwood, .flare, .breakers, .thunderbolt, .citrus,
             .velvet, .marble, .mahogany, .sandstone, .abyss, .brass,
             .neon, .gold, .ice, .cloud, .tide, .phantom, .amethyst, .chrome:
            return true
        case .hull: return true        // Quality round: Space Traveler (plating stays; lights hold still)
        case .waitingRoom: return true // end room gift: the foil holds still
        // Standard audit: the redrawn Candy cane, Marquee bulbs and Rose briar
        // are drawn textures that hold still cleanly.
        case .candy, .marquee, .rose: return true
        default:
            return false
        }
    }

    /// Darker shade — gradient depth (platform undersides, wall base).
    var deepColor: Color { color.boundaryShaded(0.62) }
    /// Brighter shade — the lit rim/highlight along an edge.
    var edgeColor: Color { color.boundaryShaded(1.45) }
}

fileprivate extension Color {
    /// Multiply brightness by `factor` (clamped 0…1) — used to derive a
    /// Boundary's depth + edge shades from its base colour.
    func boundaryShaded(_ factor: CGFloat) -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(hue: Double(h), saturation: Double(s),
                     brightness: Double(min(1, max(0, b * factor))), opacity: Double(a))
    }
}

// MARK: - Feature switches

/// Switches for cosmetic slots that are not offered yet.
enum CosmeticFeatures {
    /// Music is NOT in 1.0: no track plays in the game, so nothing a player
    /// sees may offer music as something to own or buy.  The music data,
    /// owned sets and code stay in place so it can return in an update by
    /// flipping this to true.  While false: collections show six slots and
    /// never price, grant or require their music; the Shop has no Music
    /// section or category; the Locker, Profile and loadout hide music; and
    /// the Full Fit trophy needs six slots, not seven.
    static let musicEnabled = false
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

    // Standard (750 coins)
    case piano
    case chiptune
    case jazz
    case classical
    case electronic
    case acoustic
    case orchestral
    case synthwave

    // Premium / Epic (1,250 coins)
    case lofi
    case downtempo
    case retrowave
    case cinematic
    case dreamscape

    // Exclusive / Legendary (1,500 coins)
    case celestial
    case mysterium
    case opus
    case aurora         // Aurora bundle — ambient, drifting pads

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none:        return "Off"
        case .aurora:      return "Aurora"
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
            return .standard   // 750 coins
        case .lofi, .downtempo, .retrowave, .cinematic, .dreamscape:
            return .premium    // 1,250 coins
        case .celestial, .mysterium, .opus, .aurora:
            return .exclusive  // 1,500 coins
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
/// "lucky drop".  Rolled once per Shop window (stable for 1 hour) by
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
// CosmeticSchedule — the release calendar.  Most cosmetics are HELD BACK at
// launch and arrive on fixed calendar dates.
//
//   • There is NO launch date.  `launchBundleIDs` are available from the
//     first time the app is opened, whenever that is (they include every
//     collection the game GIVES away: the Starter Pack's Aurora, the
//     post-tutorial gift pool, and the eight challenge-track rewards).
//   • Every other permanent collection has its own release DAY.  The days are
//     kept in the server table `public.cosmetic_calendar`
//     (docs/cosmetics/cosmetic-calendar.sql, database step 11); the app reads
//     it at launch and on return (at most every 6 hours), caches it, and falls
//     back to the identical built-in copy below (`builtInReleaseDays`).
//     Changing a date in the table needs no app update.
//   • A day starts at midnight EASTERN time (America/New_York), like the clan
//     seasons (`SeasonCalendar.seasonTimeZoneName`).
//   • Sticky: once this phone has seen a collection released, it stays
//     released here even if its date is later moved back
//     (`CosmeticCalendarStore`).  Owned items are never gated by the
//     schedule at all.
//   • Seasonal collections follow their yearly windows (see
//     `CosmeticBundle.currentWindow`); holidays that move get per-year rows
//     (`builtInSeasonalWindows`, overridable by the same table).
//   • Every release is one or two FULL collections.  A single piece follows
//     the one full collection it belongs to (`CosmeticSale`); a piece in no
//     full active collection is HELD — never shown, sold or announced — so it
//     has no release day at all.  There are no single-piece releases.
//   • Unreleased collections are announced in the Catalog's "Coming soon"
//     row with their date, and App Review is told about the calendar in the
//     review notes — nothing here is a hidden feature.
//
// CosmeticsTests pins the invariants (every permanent collection scheduled
// exactly once; gift and reward collections at launch; built-in dates).
// ===========================================================================

/// A calendar day (no time, no zone).  Midnight Eastern is applied when it is
/// turned into a `Date`.
struct CalendarDay: Hashable, Comparable, Codable {
    let year: Int, month: Int, day: Int
    init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year; self.month = month; self.day = day
    }
    /// "2027-02-11" → day; nil for anything else.
    init?(iso: String) {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]),
              parts[0] >= 2000, parts[0] < 3000 else { return nil }
        // Reject impossible days such as Feb 30 instead of rolling them over.
        var greg = Calendar(identifier: .gregorian)
        greg.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard comps.isValidDate(in: greg) else { return nil }
        self.init(parts[0], parts[1], parts[2])
    }
    static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
    /// Midnight at the start of this day in Eastern time.
    var easternMidnight: Date { CosmeticSchedule.easternMidnight(year, month, day) }
}

/// A seasonal window: opens at the start of `from`, closes at the start of
/// `until` (so `until` is the first day it is gone).
struct CalendarWindow: Hashable, Codable {
    let from: CalendarDay
    let until: CalendarDay
}

enum CosmeticSchedule {

    // MARK: Clock

    /// The calendar the release dates are evaluated in: Gregorian, Eastern.
    /// Built once: the Catalog asks about hundreds of items per redraw.
    static let eastern: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: SeasonCalendar.seasonTimeZoneName) ?? .gmt
        return cal
    }()

    /// Midnight Eastern at the start of the given day.  A malformed day gives
    /// `.distantFuture`, so it is safely unreleased rather than released.
    static func easternMidnight(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return eastern.date(from: c) ?? .distantFuture
    }

    /// "Dec 17, 2026" — a release day as shown in "Coming soon" (formatted
    /// in Eastern so it is the same calendar day for every player).
    static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = eastern
        f.timeZone = eastern.timeZone
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return f.string(from: date)
    }

    // MARK: Built-in calendar (the fallback; identical to step 11's rows)

    /// Permanent collections available from the first launch.
    static let launchBundleIDs: [String] = [
        // Starter Pack, the post-tutorial starter choice, and the other
        // Standard sets
        "aurora", "nature", "fire", "water", "storm",
        "citrus", "sketchbook", "midas",
        // Challenge-track rewards (ChallengeTrackMode.rewardBundleID)
        "winter", "cosmos", "lava-flow", "neon", "haunted",
        "ancient-temple", "abyssal-depths", "champion",
        // Quality round: the new Space Traveler set is on sale from launch.
        "space-traveler",
    ]

    /// The drops, in date order: each day brings one or two FULL collections
    /// (docs/proposals/cosmetic-calendar.md; database steps 11 and 21).
    /// Retired sets and loose single-piece slots have no release day: their
    /// pieces are held (`CosmeticSale`).
    static let drops: [(day: CalendarDay, ids: [String])] = [
        (CalendarDay(2026, 12, 17), ["candyland", "nightclub"]),
        (CalendarDay(2027,  1, 14), ["golf", "bloom"]),
        (CalendarDay(2027,  2, 11), ["ocean"]),
    ]

    /// Collection id → built-in release day.
    static let builtInReleaseDays: [String: CalendarDay] = {
        var map: [String: CalendarDay] = [:]
        for drop in drops { for id in drop.ids { map[id] = drop.day } }
        return map
    }()

    /// Per-year windows for seasonal collections whose holiday moves.  Years
    /// not listed (and every other seasonal collection) use the collection's
    /// own yearly window from its catalogue entry.
    static let builtInSeasonalWindows: [String: [Int: CalendarWindow]] = [
        "lunar-2027": [
            2027: CalendarWindow(from: CalendarDay(2027, 1, 27), until: CalendarDay(2027, 2, 20)),
            2028: CalendarWindow(from: CalendarDay(2028, 1, 16), until: CalendarDay(2028, 2, 10)),
        ],
        "mardigras-2027": [
            2027: CalendarWindow(from: CalendarDay(2027, 1, 28), until: CalendarDay(2027, 2, 10)),
            2028: CalendarWindow(from: CalendarDay(2028, 2, 17), until: CalendarDay(2028, 3, 1)),
        ],
        "oktoberfest-2026": [
            2027: CalendarWindow(from: CalendarDay(2027, 9, 16), until: CalendarDay(2027, 10, 4)),
            2028: CalendarWindow(from: CalendarDay(2028, 9, 14), until: CalendarDay(2028, 10, 4)),
        ],
    ]

    // MARK: Effective dates (server table over built-in)

    /// The release moment of a permanent collection; nil when it has no date
    /// (launch collections, unknown ids) — i.e. always available.
    static func releaseDate(of id: String, store: CosmeticCalendarStore = .shared) -> Date? {
        if launchBundleIDs.contains(id) { return nil }
        if let day = store.releaseDayOverride(for: id) { return day.easternMidnight }
        return builtInReleaseDays[id]?.easternMidnight
    }

    /// Released = has no date, this phone already saw it released, or its
    /// day has begun in Eastern time.
    static func isReleased(collectionID id: String, at now: Date = Date(),
                           store: CosmeticCalendarStore = .shared) -> Bool {
        guard let date = releaseDate(of: id, store: store) else { return true }
        if store.hasSeenReleased(id) { return true }
        guard now >= date else { return false }
        store.rememberReleased(id, at: now)
        return true
    }

    // MARK: Collections

    static func isReleased(_ bundle: CosmeticBundle, at now: Date = Date(),
                           store: CosmeticCalendarStore = .shared) -> Bool {
        if bundle.isLimitedTime { return true }      // seasonal: its window governs
        return isReleased(collectionID: bundle.id, at: now, store: store)
    }

    // MARK: Single items

    /// The release keys an item waits on: the id of the full collection it
    /// belongs to, when that collection has a release day.  Empty = no day to
    /// wait for (launch collection, a default, an exempt piece, or a held
    /// piece — which is never on sale anyway, see `CosmeticSale`).
    static func releaseKeys<Item: CosmeticItem>(of item: Item) -> [String] {
        guard let id = CosmeticSale.collectionID(of: item),
              builtInReleaseDays[id] != nil else { return [] }
        return [id]
    }

    /// True once the item's collection has been released (always true for an
    /// item with no release day).  This is about DATES only; whether a piece
    /// may be shown or sold at all is `CosmeticSale.isOnSale`.
    static func isReleased<Item: CosmeticItem>(_ item: Item, at now: Date = Date(),
                                               store: CosmeticCalendarStore = .shared) -> Bool {
        let keys = releaseKeys(of: item)
        if keys.isEmpty { return true }
        return keys.contains { isReleased(collectionID: $0, at: now, store: store) }
    }

    /// A ball pack is released once every ball in it is.
    static func isReleased(_ pack: BallPack, at now: Date = Date(),
                           store: CosmeticCalendarStore = .shared) -> Bool {
        pack.skins.allSatisfy { isReleased($0, at: now, store: store) }
    }

    // MARK: Seasonal windows

    /// The window of a seasonal collection that is open now or opens next.
    /// For each year: the per-year row (server, else built-in) if there is
    /// one, else the collection's own yearly window shifted to that year.
    static func seasonalWindow(for bundle: CosmeticBundle, at now: Date = Date(),
                               store: CosmeticCalendarStore = .shared) -> (from: Date, until: Date)? {
        guard let baseUntil = bundle.availableUntil else { return nil }
        let baseFrom = bundle.availableFrom ?? baseUntil
        let cal = eastern
        let baseYear = cal.component(.year, from: baseFrom)
        let nowYear = cal.component(.year, from: now)
        let rows = builtInSeasonalWindows[bundle.id] ?? [:]
        for year in (nowYear - 1)...(nowYear + 2) {
            let from: Date
            let until: Date
            if let w = store.seasonalOverride(for: bundle.id, year: year) ?? rows[year] {
                from = w.from.easternMidnight
                until = w.until.easternMidnight
            } else {
                let delta = year - baseYear
                from = cal.date(byAdding: .year, value: delta, to: baseFrom) ?? baseFrom
                until = cal.date(byAdding: .year, value: delta, to: baseUntil) ?? baseUntil
            }
            if until > from, now < until { return (from, until) }
        }
        return nil
    }

    // MARK: Coming soon

    struct Upcoming {
        let date: Date
        /// Active collections released that day (never empty).
        let bundles: [CosmeticBundle]
    }

    /// The next release day that has not arrived yet and brings at least one
    /// collection on sale.  Days that only release single items (pieces of
    /// retired sets) are skipped — "Coming soon" names collections only.  nil
    /// when no collection is scheduled.  Uses the effective (server or
    /// built-in) dates.
    static func nextDrop(at now: Date = Date(),
                         store: CosmeticCalendarStore = .shared) -> Upcoming? {
        var byDay: [Date: [CosmeticBundle]] = [:]
        for bundle in CosmeticSale.fullCollections {
            guard !isReleased(collectionID: bundle.id, at: now, store: store),
                  let day = releaseDate(of: bundle.id, store: store) else { continue }
            byDay[day, default: []].append(bundle)
        }
        guard let day = byDay.keys.min(), let bundles = byDay[day] else { return nil }
        return Upcoming(date: day, bundles: bundles)
    }
}

/// The one green used for every "equipped" mark (Shop, Catalog, Locker,
/// collection cards and popup rows).  Bright enough to read on light and dark
/// tiles alike.
extension Color {
    static let equippedGreen = Color(red: 0.20, green: 0.90, blue: 0.46)
}

// ===========================================================================
// CosmeticCalendarStore — the server copy of the release calendar plus the
// "already released on this phone" memory.
//
//   • Reads `public.cosmetic_calendar` (anyone may read; nobody may write
//     from the app) with the public key, at launch and on return to the app,
//     at most every 6 hours.  Never during test runs.
//   • The last good copy is cached on the phone; with no copy the built-in
//     dates in `CosmeticSchedule` are used.  Each read REPLACES the copy, so
//     deleting a row returns that collection to its built-in date.
//   • Rows for unknown ids, broken dates or the wrong shape are ignored.
//   • Remembers every collection this phone has seen released, so moving a
//     date later never takes a released collection away.
// ===========================================================================
final class CosmeticCalendarStore: ObservableObject, @unchecked Sendable {

    static let shared = CosmeticCalendarStore(
        defaults: RuntimeEnvironment.isRunningTests ? nil : UserDefaults.standard,
        remembersReleases: !RuntimeEnvironment.isRunningTests)

    struct Row: Codable, Equatable {
        let collection_id: String
        let starts_on: String
        let ends_on: String?
    }

    static let refreshInterval: TimeInterval = 6 * 60 * 60
    private static let rowsKey = "ra_cosmeticCalendarRows_v1"
    private static let seenKey = "ra_cosmeticReleasedSeen_v1"
    private static let fetchedKey = "ra_cosmeticCalendarFetchedAt_v1"

    private let lock = NSLock()
    private let defaults: UserDefaults?
    /// Off for the shared store during tests, so a test that asks about a
    /// future date never marks anything released for the next test.
    let remembersReleases: Bool
    private var releaseOverrides: [String: CalendarDay] = [:]
    private var seasonalOverrides: [String: [Int: CalendarWindow]] = [:]
    private var seen: Set<String>
    private var lastFetch: Date?
    private var fetching = false

    init(defaults: UserDefaults?, remembersReleases: Bool) {
        self.defaults = defaults
        self.remembersReleases = remembersReleases
        seen = Set(defaults?.stringArray(forKey: Self.seenKey) ?? [])
        lastFetch = defaults?.object(forKey: Self.fetchedKey) as? Date
        if let data = defaults?.data(forKey: Self.rowsKey),
           let rows = try? JSONDecoder().decode([Row].self, from: data) {
            install(rows)
        }
    }

    // MARK: Reads (used by CosmeticSchedule)

    func releaseDayOverride(for id: String) -> CalendarDay? {
        lock.lock(); defer { lock.unlock() }
        return releaseOverrides[id]
    }

    func seasonalOverride(for id: String, year: Int) -> CalendarWindow? {
        lock.lock(); defer { lock.unlock() }
        return seasonalOverrides[id]?[year]
    }

    func hasSeenReleased(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return seen.contains(id)
    }

    /// Remember a release — only for the real current time (a question about
    /// some other moment, e.g. in a test, never marks anything).
    func rememberReleased(_ id: String, at now: Date) {
        guard remembersReleases, abs(now.timeIntervalSinceNow) < 120 else { return }
        lock.lock()
        let inserted = seen.insert(id).inserted
        let snapshot = Array(seen)
        lock.unlock()
        if inserted { defaults?.set(snapshot, forKey: Self.seenKey) }
    }

    // MARK: Applying rows

    /// Replace the server copy with `rows` (validated; bad rows dropped).
    func apply(_ rows: [Row]) {
        install(rows)
        if let data = try? JSONEncoder().encode(rows) {
            defaults?.set(data, forKey: Self.rowsKey)
        }
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    private func install(_ rows: [Row]) {
        let seasonalIDs = Set(CosmeticBundle.catalogue.filter(\.isLimitedTime).map(\.id))
        var releases: [String: CalendarDay] = [:]
        var seasonal: [String: [Int: CalendarWindow]] = [:]
        for row in rows {
            guard let start = CalendarDay(iso: row.starts_on) else { continue }
            if let endText = row.ends_on {
                guard seasonalIDs.contains(row.collection_id),
                      let end = CalendarDay(iso: endText), start < end else { continue }
                seasonal[row.collection_id, default: [:]][start.year] =
                    CalendarWindow(from: start, until: end)
            } else {
                guard CosmeticSchedule.builtInReleaseDays[row.collection_id] != nil else { continue }
                releases[row.collection_id] = start
            }
        }
        lock.lock()
        releaseOverrides = releases
        seasonalOverrides = seasonal
        lock.unlock()
    }

    // MARK: Fetch

    private static let projectURL = "https://mhwpcwauzvmtmuphtajs.supabase.co"
    /// Anon (public) key — the same public key as the other anonymous reads.
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1od3Bjd2F1enZtdG11cGh0YWpzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwMDI1MzMsImV4cCI6MjA5NTU3ODUzM30." +
        "dKtYkbLF43vLYiCMaxhurBT8rTqAMxuKuJ2z5mkXKsM"

    // Lock work stays in these synchronous helpers (NSLock is not for async code).
    private func beginFetchIfDue(now: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let due = !fetching
            && (lastFetch.map { let age = now.timeIntervalSince($0); return age >= Self.refreshInterval || age < 0 } ?? true)
        if due { fetching = true }
        return due
    }

    private func endFetch(succeeded: Bool, at now: Date) {
        lock.lock()
        fetching = false
        if succeeded { lastFetch = now }
        lock.unlock()
        if succeeded { defaults?.set(now, forKey: Self.fetchedKey) }
    }

    /// Read the table if the last good read is older than 6 hours.  Failures
    /// keep the cached (or built-in) dates and are logged in Debug builds.
    func refreshIfDue(now: Date = Date()) async {
        guard defaults != nil, !RuntimeEnvironment.isRunningTests, beginFetchIfDue(now: now) else { return }
        var succeeded = false
        defer { endFetch(succeeded: succeeded, at: now) }

        let query = "select=collection_id,starts_on,ends_on&order=starts_on"
        guard let url = URL(string: "\(Self.projectURL)/rest/v1/cosmetic_calendar?\(query)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Self.anonKey)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(status) else {
                #if DEBUG
                print("[CosmeticCalendar] read refused: HTTP \(status) \(String(data: data, encoding: .utf8) ?? "")")
                #endif
                return
            }
            let rows = try JSONDecoder().decode([Row].self, from: data)
            apply(rows)
            succeeded = true
        } catch {
            #if DEBUG
            print("[CosmeticCalendar] read failed: \(error)")
            #endif
        }
    }
}

// ===========================================================================
// CosmeticSale — THE rule for what may be seen and bought.
//
// A cosmetic is ON SALE only if it belongs to a FULL active collection: an
// active (not retired, not seasonal) collection with all six slots filled —
// ball, goal, trail, floor, pit and boundary (music is not in 1.0) — whose
// release day has arrived.  Pieces are still bought one at a time, but only
// pieces of such a collection.
//
// Every other piece is HELD: not shown, not sold, not announced.  That covers
// pieces of retired and seasonal sets, pieces displaced from a collection and
// pieces in no collection.  Held pieces keep their code and ids; a player who
// already owns one keeps it and can equip it from the Locker.
//
// Not held:
//   • the Roll Along defaults (free, owned by everyone);
//   • EXEMPT pieces — earned or purchase-only, never sold for coins
//     (`exemptBalls`, `exemptTrails`, `exemptFloors`, `exemptPits`,
//     `exemptBoundaries`).  They are shown only to
//     a player who owns them.
//
// Every listing and every purchase goes through here: the Shop rotation
// pools, the Catalog tabs, the featured bundle, Coming Soon, the seasonal
// events and `GameState.purchase`.
// ===========================================================================
enum CosmeticSale {

    /// The active collections with all six slots filled, in catalogue order.
    /// Only these are sold, featured, announced or released.
    static let fullCollections: [CosmeticBundle] =
        CosmeticBundle.active.filter { !$0.isLimitedTime && $0.isComplete }

    /// Earned or purchase-only pieces that were never sold for coins.
    ///   • Diamond ball — comes with the Diamond Balls purchase (Locker only).
    ///   • Money Ball — comes with the first 10,000-coin pack.
    ///   • Trophy ball — earned by finishing the Golden Gauntlet track (it is
    ///     also the Champion collection's ball, granted with that set).
    ///   • Waiting Room ball, floor, pit and boundary — the end room gift
    ///     (1.1), given once to a player who clears every level in the pack.
    static let exemptBalls: Set<BallSkin> = [.diamond, .moneyBall, .trophy, .waitingRoom]
    /// Money Roll trail / Money floor — purchase-only Money pieces.
    static let exemptTrails: Set<TrailColor> = [.moneyRoll]
    static let exemptFloors: Set<Floor> = [.moneyFull, .waitingRoom]
    static let exemptPits: Set<Pit> = [.waitingRoom]
    static let exemptBoundaries: Set<Boundary> = [.waitingRoom]

    private static func key<Item: CosmeticItem>(_ item: Item) -> String {
        String(describing: Item.self) + "|" + item.rawValue
    }

    /// "<Type>|<rawValue>" → id of the full collection the piece belongs to.
    private static let collectionIDs: [String: String] = {
        var map: [String: String] = [:]
        func note<Item: CosmeticItem>(_ items: [Item], _ id: String) {
            for item in items where map[key(item)] == nil { map[key(item)] = id }
        }
        for bundle in fullCollections {
            note(bundle.balls, bundle.id);  note(bundle.goals, bundle.id)
            note(bundle.trails, bundle.id); note(bundle.floors, bundle.id)
            note(bundle.pits, bundle.id);   note(bundle.boundaries, bundle.id)
        }
        return map
    }()

    /// The id of the full collection `item` belongs to; nil for held pieces,
    /// defaults and exempt pieces outside a collection.
    static func collectionID<Item: CosmeticItem>(of item: Item) -> String? {
        collectionIDs[key(item)]
    }

    /// The full collection `item` belongs to, if any.
    static func collection<Item: CosmeticItem>(of item: Item) -> CosmeticBundle? {
        guard let id = collectionID(of: item) else { return nil }
        return fullCollections.first { $0.id == id }
    }

    /// A Roll Along default (free, owned by everyone, never sold).
    static func isDefault<Item: CosmeticItem>(_ item: Item) -> Bool {
        item.tier == .starter || item == Item.starter
    }

    /// Earned or purchase-only, never sold for coins.
    static func isExempt<Item: CosmeticItem>(_ item: Item) -> Bool {
        switch item {
        case let b as BallSkin:   return exemptBalls.contains(b)
        case let t as TrailColor: return exemptTrails.contains(t)
        case let f as Floor:      return exemptFloors.contains(f)
        case let p as Pit:        return exemptPits.contains(p)
        case let w as Boundary:   return exemptBoundaries.contains(w)
        default:                  return false
        }
    }

    /// True when `item` may be shown and sold now: it belongs to a full
    /// active collection whose release day has arrived.
    static func isOnSale<Item: CosmeticItem>(_ item: Item, at now: Date = Date(),
                                             store: CosmeticCalendarStore = .shared) -> Bool {
        guard let id = collectionID(of: item) else { return false }
        return CosmeticSchedule.isReleased(collectionID: id, at: now, store: store)
    }

    /// True for a piece that is held back: in no full active collection, not
    /// a default and not exempt.  Held pieces are never shown, sold or
    /// announced; owners keep and can equip them.
    static func isHeld<Item: CosmeticItem>(_ item: Item) -> Bool {
        if item is MusicTrack { return false }          // music is off in 1.0 (CosmeticFeatures)
        return collectionID(of: item) == nil && !isDefault(item) && !isExempt(item)
    }

    /// A ball pack is on sale only when every ball in it is.  (Today no pack
    /// qualifies: each holds balls that are in no full collection, so all
    /// three packs are held.  Owners keep and can equip them.)
    static func isOnSale(_ pack: BallPack, at now: Date = Date(),
                         store: CosmeticCalendarStore = .shared) -> Bool {
        pack.skins.allSatisfy { isOnSale($0, at: now, store: store) }
    }
}

// ===========================================================================
// Shop rotation — the curated storefront refreshes every hour.  A
// deterministic window index seeds which bundle + odds-and-ends cosmetics are
// featured, so the selection is stable within a window and identical
// everywhere (the Shop display AND the Catalog's "available now" markers).
// ===========================================================================
enum ShopRotation {
    static let windowSeconds: TimeInterval = 1 * 60 * 60   // 1 hour

    static func window(at date: Date = Date()) -> Int {
        Int(date.timeIntervalSince1970 / windowSeconds)
    }
    static func refreshDate(at date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: Double(window(at: date) + 1) * windowSeconds)
    }
    /// "0:59:42" until the next refresh.
    static func countdown(at date: Date = Date()) -> String {
        let s = max(0, Int(refreshDate(at: date).timeIntervalSince(date)))
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    // Pools of coin-purchasable items eligible to be featured.  Only pieces
    // ON SALE — members of a released, full, active collection
    // (`CosmeticSale.isOnSale`) — can ever be featured.  Held pieces never are.
    static var bundlePool: [CosmeticBundle] {
        CosmeticSale.fullCollections.filter {
            $0.isAvailable && !$0.isExpired && CosmeticSchedule.isReleased($0)
        }
    }
    static var ballPool: [BallSkin] {
        BallSkin.allCases.filter { $0.isCoinPurchasable && CosmeticSale.isOnSale($0) }
    }
    static var trailPool: [TrailColor] {
        // Air and Raybeam are sold only with their collections (Golf, Neon).
        TrailColor.allCases.filter { $0.isCoinPurchasable && $0 != .air && $0 != .raybeam
            && CosmeticSale.isOnSale($0) }
    }
    static var goalPool: [GoalSkin] {
        GoalSkin.allCases.filter { $0.isCoinPurchasable && CosmeticSale.isOnSale($0) }
    }
    static var floorPool: [Floor] {
        Floor.allCases.filter { $0.isCoinPurchasable && CosmeticSale.isOnSale($0) }
    }
    static var pitPool: [Pit] {
        Pit.allCases.filter { $0.isCoinPurchasable && CosmeticSale.isOnSale($0) }
    }
    static var boundaryPool: [Boundary] {
        Boundary.allCases.filter { $0.isCoinPurchasable && CosmeticSale.isOnSale($0) }
    }
    static var musicPool: [MusicTrack] {
        MusicTrack.allCases.filter { $0.tier != .starter && CosmeticSchedule.isReleased($0) }
    }

    private static func pick<T>(_ pool: [T], _ window: Int, salt: Int) -> T? {
        guard !pool.isEmpty else { return nil }
        let h = window &* 31 &+ salt
        return pool[((h % pool.count) + pool.count) % pool.count]
    }

    static func featuredBundle(at date: Date = Date()) -> CosmeticBundle? { pick(bundlePool, window(at: date), salt: 0) }

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

    // MARK: Storefront multi-picks (one section per category)

    /// Deterministic shuffle of `pool` for `window` — stable within the 1-hour
    /// window, rotates with it.  xorshift64 seeded by window+salt.
    private static func shuffled<T>(_ pool: [T], _ window: Int, salt: Int) -> [T] {
        guard pool.count > 1 else { return pool }
        var arr = pool
        var seed = UInt64(bitPattern: Int64(window &* 2_654_435_761 &+ salt)) | 1
        func next() -> UInt64 {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return seed
        }
        for i in stride(from: arr.count - 1, to: 0, by: -1) {
            arr.swapAt(i, Int(next() % UInt64(i + 1)))
        }
        return arr
    }

    /// Three picks for a category: two Standard-tier items + one better-than-
    /// Standard (Rare/Epic/Legendary), deterministic per window.  Falls back to
    /// filling from the whole pool when a tier is too small to supply its share.
    private static func triplePick<T: CosmeticItem>(_ pool: [T], _ window: Int, salt: Int) -> [T] {
        let standard = pool.filter { $0.tier == .standard }
        let better   = pool.filter { $0.tier != .standard }   // pool already excludes starter
        var picks = Array(shuffled(standard, window, salt: salt).prefix(2))
        if let top = shuffled(better, window, salt: salt &+ 1).first { picks.append(top) }
        if picks.count < 3 {
            let extra = shuffled(pool.filter { !picks.contains($0) }, window, salt: salt &+ 2)
            picks.append(contentsOf: extra.prefix(3 - picks.count))
        }
        return picks
    }

    static func featuredBalls(at date: Date = Date())      -> [BallSkin]   { triplePick(ballPool,     window(at: date), salt: 71) }
    static func featuredTrails(at date: Date = Date())     -> [TrailColor] { triplePick(trailPool,    window(at: date), salt: 73) }
    static func featuredGoals(at date: Date = Date())      -> [GoalSkin]   { triplePick(goalPool,     window(at: date), salt: 79) }
    static func featuredFloors(at date: Date = Date())     -> [Floor]      { triplePick(floorPool,    window(at: date), salt: 83) }
    static func featuredPits(at date: Date = Date())       -> [Pit]        { triplePick(pitPool,      window(at: date), salt: 89) }
    static func featuredBoundaries(at date: Date = Date()) -> [Boundary]   { triplePick(boundaryPool, window(at: date), salt: 97) }
    static func featuredMusicSet(at date: Date = Date())   -> [MusicTrack] { triplePick(musicPool,    window(at: date), salt: 101) }

    /// True if `item` is one of the Shop's current picks (any category's three)
    /// OR a member of the featured bundle — i.e. buyable in the Shop right now.
    /// (Used by the Catalog to draw the blue "available now" border.)
    static func isFeatured<Item: CosmeticItem>(_ item: Item, at date: Date = Date()) -> Bool {
        switch item {
        case let b  as BallSkin:   if featuredBalls(at: date).contains(b)       { return true }
        case let t  as TrailColor: if featuredTrails(at: date).contains(t)      { return true }
        case let g  as GoalSkin:   if featuredGoals(at: date).contains(g)       { return true }
        case let f  as Floor:      if featuredFloors(at: date).contains(f)      { return true }
        case let p  as Pit:        if featuredPits(at: date).contains(p)        { return true }
        case let bd as Boundary:   if featuredBoundaries(at: date).contains(bd) { return true }
        case let m  as MusicTrack:
            if CosmeticFeatures.musicEnabled, featuredMusicSet(at: date).contains(m) { return true }
        default: break
        }
        return featuredBundle(at: date)?.contains(item) ?? false
    }
}

// ===========================================================================
// SeasonalEvent — the yearly holiday windows, now that seasonal collections
// are retired as sets.
//
// Each retired seasonal catalogue entry keeps its window (same yearly dates,
// per-year rows and server overrides as before: `CosmeticSchedule.
// seasonalWindow`, Eastern midnight).  While its window is open the Shop
// shows the event and the one FULL active collection it features.  An event
// never sells loose pieces: its own ball and boundary are held
// (`CosmeticSale`), like every piece outside a full collection.
// ===========================================================================
struct SeasonalEvent: Identifiable {
    /// The retired seasonal catalogue entry: name and window.
    let bundle: CosmeticBundle
    var id: String { bundle.id }
    var displayName: String { bundle.displayName }

    /// The full active collection featured during this event, if any.
    var featuredCollection: CosmeticBundle? {
        guard let fid = Self.featuredCollectionIDs[bundle.id] else { return nil }
        return CosmeticSale.fullCollections.first { $0.id == fid }
    }

    func isOpen(at now: Date = Date()) -> Bool { bundle.isOpen(at: now) }

    /// Event id → featured active collection id.
    static let featuredCollectionIDs: [String: String] = [
        "summer-2026":       "ocean",
        "halloween-2026":    "haunted",
        "winter-2026":       "winter",
        "valentines-2027":   "bloom",
        "stpatricks-2027":   "nature",
        "newyear-2027":      "nightclub",
        "spring-2027":       "bloom",
        "july4-2026":        "cosmos",
        "muertos-2026":      "haunted",
        "harvest-2026":      "citrus",
        "lunar-2027":        "ancient-temple",
        "mardigras-2027":    "nightclub",
        "pride-2027":        "aurora",
        "oktoberfest-2026":  "midas",
        "earthday-2027":     "nature",
        "backtoschool-2026": "sketchbook",
    ]

    /// Every seasonal event, in catalogue order.
    static var all: [SeasonalEvent] {
        CosmeticBundle.catalogue.filter(\.isLimitedTime).map { SeasonalEvent(bundle: $0) }
    }

    /// The events whose window is open now.
    static func open(at now: Date = Date()) -> [SeasonalEvent] {
        all.filter { $0.isOpen(at: now) }
    }

    /// True when an open event features `bundle`.
    static func features(_ bundle: CosmeticBundle, at now: Date = Date()) -> Bool {
        open(at: now).contains { $0.featuredCollection?.id == bundle.id }
    }
}

/// A bundle's overall rarity, derived from its MEMBER TIERS.  Three bands so
/// the shop reads at a glance and the post-tutorial gift can filter to Standard.
enum BundleRarity: String, CaseIterable {
    case standard, rare, legendary

    /// Member-count thresholds.  ≥ `legendaryMembersFloor` legendary
    /// (`.exclusive`) items → Legendary; ≥ `highTierMembersFloor` epic-or-
    /// legendary (`.premium`/`.exclusive`) items → Rare; otherwise Standard.
    /// In one sentence: a Legendary bundle is packed with legendary items, a
    /// Rare bundle carries a couple of high-tier showpieces, and a Standard
    /// bundle is (almost) all standard fare.
    ///
    /// Replaces the old `fullPrice()` coin floors (5,500 / 6,500): under the
    /// near-flat 2026-07 tier ladder (750/1,000/1,250/1,500) total price
    /// mostly measured ITEM COUNT, not content quality.  Deriving from member
    /// tiers keeps rarity price-free — future reprices can't silently reshuffle
    /// the bands.  Validated against the ACTUAL catalogue
    /// (test_bundleRarityDistribution dump, 66 bundles, after the 2026-07
    /// audit ruling-1c under-tier promotions):
    ///   • the split stays a pyramid — 4 / 19 / 43 (6% / 29% / 65%), from
    ///     7 / 21 / 38 pre-ruling (diamond → Rare; bloom, backtoschool-2026,
    ///     lava-lamp, valentines-2027, muertos-2026 → Legendary);
    ///   • the PERMANENT (non-seasonal) Standard pool feeding the
    ///     post-tutorial gift picker holds 4 bundles (nature, citrus,
    ///     sketchbook, midas) — at the FLOOR of the required 4–8 band, guarded
    ///     by testTutorialGift_permanentStandardBundlePool_neverEmpty; any
    ///     further promotion out of this pool needs a replacement Standard
    ///     bundle first.
    static let legendaryMembersFloor = 2
    static let highTierMembersFloor  = 2

    var label: String {
        switch self {
        case .standard:  return "Standard"
        case .rare:      return "Rare"
        case .legendary: return "Legendary"
        }
    }

    /// Mirrors the item tier ramp — Standard blue, Rare cyan, Legendary gold.
    var color: Color {
        switch self {
        case .standard:  return Color(red: 0.45, green: 0.62, blue: 0.85)
        case .rare:      return Color(red: 0.28, green: 0.78, blue: 0.95)
        case .legendary: return Color(red: 1.00, green: 0.78, blue: 0.28)
        }
    }

    /// Metallic gem ramp for the bundle's rarity gem — silver / gold / diamond.
    var gemColors: [Color] {
        switch self {
        case .standard:  return [Color(white: 0.95), Color(white: 0.62)]                 // silver
        case .rare:      return [Color(red: 1.00, green: 0.87, blue: 0.48),
                                 Color(red: 0.84, green: 0.55, blue: 0.15)]              // gold
        case .legendary: return [Color(red: 0.85, green: 0.97, blue: 1.00),
                                 Color(red: 0.38, green: 0.80, blue: 0.98)]              // diamond
        }
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
    /// The collection's boundary (walls / platforms / screen border).  Every
    /// collection carries exactly one.  Declared after `music` with a default
    /// so the memberwise initializer keeps its existing argument order.
    var boundaries: [Boundary] = []

    /// The collection's music as offered to players: its tracks when music is
    /// on, otherwise none.  Everything a player sees, pays for or is granted
    /// goes through this; `music` itself is kept for when music returns.
    var offeredMusic: [MusicTrack] { CosmeticFeatures.musicEnabled ? music : [] }

    /// What the player gets, built from the set's actual items (so it can
    /// never drift from the contents), e.g. "Jade ball · Meadow goal · …".
    /// Music is listed only while music is offered.
    var displaySummary: String {
        func named(_ name: String, _ slot: String) -> String {
            name.lowercased().hasSuffix(slot) ? name : "\(name) \(slot)"
        }
        var parts: [String] = []
        parts += balls.map { named($0.displayName, "ball") }
        parts += goals.map { named($0.displayName, "goal") }
        parts += trails.map { named($0.displayName, "trail") }
        parts += floors.map { named($0.displayName, "floor") }
        parts += pits.map { named($0.displayName, "pit") }
        parts += boundaries.map { named($0.displayName, "boundary") }
        parts += offeredMusic.map { named($0.displayName, "music") }
        return parts.joined(separator: " · ")
    }

    // ── Seasonal availability window ───────────────────────────────
    // Both nil = always available (permanent bundle).
    // Non-nil `availableUntil` marks the bundle as limited-time.
    // Shop only shows it when `isAvailable` is true.
    var availableFrom:  Date? = nil
    var availableUntil: Date? = nil

    // MARK: Availability computed vars

    /// True when this bundle has an expiry date (i.e., is seasonal).
    var isLimitedTime: Bool { availableUntil != nil }

    /// Seasonal windows REPEAT EVERY YEAR.  `availableFrom` / `availableUntil`
    /// describe one year's window (`availableUntil` is the first day it is
    /// gone); this returns the window that is open now or opens next.  Holidays
    /// that move (Lunar New Year, Mardi Gras, Oktoberfest) have per-year rows
    /// in the release calendar, which the server table can also set
    /// (`CosmeticSchedule.seasonalWindow`).  Days start at midnight Eastern.
    /// nil for a permanent bundle.
    func currentWindow(at now: Date = Date()) -> (from: Date, until: Date)? {
        CosmeticSchedule.seasonalWindow(for: self, at: now)
    }

    /// True when `now` falls within the availability window (always true for
    /// a permanent bundle — release timing is `CosmeticSchedule`'s job).
    func isOpen(at now: Date) -> Bool {
        guard isLimitedTime else {
            if let from = availableFrom, now < from { return false }
            return true
        }
        guard let window = currentWindow(at: now) else { return false }
        return now >= window.from
    }

    /// True when the current date falls within the availability window.
    var isAvailable: Bool { isOpen(at: Date()) }

    /// True when a limited-time bundle has no future window left (never the
    /// case in practice now that seasons repeat yearly).
    var isExpired: Bool {
        isLimitedTime && currentWindow() == nil
    }

    /// True when the offer hasn't opened yet (waiting for its next window).
    var isUpcoming: Bool {
        if isLimitedTime { return !isAvailable && !isExpired }
        guard let from = availableFrom else { return false }
        return Date() < from
    }

    /// Full days remaining until the current window closes.  nil when not
    /// limited or not currently open.  0 = "ends today" (less than 24 h left).
    var daysRemaining: Int? {
        guard isLimitedTime, isAvailable, let until = currentWindow()?.until else { return nil }
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
        // Midnight Eastern, like every release date (CosmeticSchedule).
        CosmeticSchedule.easternMidnight(year, month, day)
    }

    var itemCount: Int {
        balls.count + goals.count + trails.count + floors.count + pits.count
            + boundaries.count + offeredMusic.count
    }

    /// The full price of the bundle — the sum of every contained item's
    /// individual `coinCost`.  Starter items are free, so they add nothing.
    func fullPrice() -> Int {
        // Per-category locals so the Swift type-checker doesn't choke on one
        // giant chained-generic expression.
        let ballSum:  Int = balls.reduce(0)  { $0 + Self.listPrice($1) }
        let goalSum:  Int = goals.reduce(0)  { $0 + Self.listPrice($1) }
        let trailSum: Int = trails.reduce(0) { $0 + Self.listPrice($1) }
        let floorSum: Int = floors.reduce(0) { $0 + Self.listPrice($1) }
        let pitSum:   Int = pits.reduce(0)   { $0 + Self.listPrice($1) }
        let musicSum: Int = offeredMusic.reduce(0)  { $0 + Self.listPrice($1) }
        let wallSum:  Int = boundaries.reduce(0) { $0 + Self.listPrice($1) }
        return ballSum + goalSum + trailSum + floorSum + pitSum + musicSum + wallSum
    }

    /// An item's price inside a collection: its coin cost, except a slot's
    /// default item (e.g. the Graphite trail in Paper World), which every
    /// player already owns and so never costs anything.
    static func listPrice<Item: CosmeticItem>(_ item: Item) -> Int {
        item == Item.starter ? 0 : item.coinCost
    }

    /// Count of contained items per cosmetic tier (starter items included —
    /// they're free and don't affect rarity).  Feeds `rarity` and the
    /// distribution dump in CosmeticsTests.
    func tierCounts() -> [CosmeticTier: Int] {
        var counts: [CosmeticTier: Int] = [:]
        for b in balls  { counts[b.tier, default: 0] += 1 }
        for g in goals  { counts[g.tier, default: 0] += 1 }
        for t in trails { counts[t.tier, default: 0] += 1 }
        for f in floors { counts[f.tier, default: 0] += 1 }
        for p in pits   { counts[p.tier, default: 0] += 1 }
        // Rarity counts the music track even while music is off, so no
        // collection changes band (and the Standard gift pool stays the same).
        for m in music  { counts[m.tier, default: 0] += 1 }
        for w in boundaries { counts[w.tier, default: 0] += 1 }
        return counts
    }

    /// Bundle rarity — derived from the bundle's MEMBER TIERS, not its price:
    /// two or more legendary items → Legendary; two or more epic-or-legendary
    /// items → Rare; otherwise Standard.  Price never appears in the rule, so
    /// reprices can't reshuffle the bands (see `BundleRarity` for the full
    /// derivation).  Standard bundles are the post-tutorial gift pool.
    var rarity: BundleRarity {
        let counts = tierCounts()
        let legendaryMembers = counts[.exclusive] ?? 0
        let highTierMembers  = legendaryMembers + (counts[.premium] ?? 0)
        if legendaryMembers >= BundleRarity.legendaryMembersFloor { return .legendary }
        if highTierMembers  >= BundleRarity.highTierMembersFloor  { return .rare }
        return .standard
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
        let musicSum: Int = offeredMusic.reduce(0)  { $0 + (state.isOwned($1) ? 0 : $1.coinCost) }
        let wallSum:  Int = boundaries.reduce(0) { $0 + (state.isOwned($1) ? 0 : $1.coinCost) }
        return ballSum + goalSum + trailSum + floorSum + pitSum + musicSum + wallSum
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
        case let m as MusicTrack: return offeredMusic.contains(m)
        case let w as Boundary:   return boundaries.contains(w)
        default:                  return false
        }
    }

    /// True when all six slots are filled: ball, goal, trail, floor, pit and
    /// boundary (music is not offered in 1.0).  Only complete active
    /// collections are sold (`CosmeticSale.fullCollections`).
    var isComplete: Bool {
        !balls.isEmpty && !goals.isEmpty && !trails.isEmpty
            && !floors.isEmpty && !pits.isEmpty && !boundaries.isEmpty
    }

    /// Every catalogue bundle whose contents include `item` — i.e. the
    /// set(s) the item was released with.  Used by the Catalog to show
    /// each cosmetic's related bundle(s).
    static func bundles<Item: CosmeticItem>(containing item: Item) -> [CosmeticBundle] {
        CosmeticSale.fullCollections.filter { $0.contains(item) }
    }

    // ── Active vs retired collections ──────────────────────────────
    //
    // Only these collections are on sale (Shop, Catalog, featured bundle,
    // post-tutorial starter choice, Challenge Track rewards).  Each has exactly
    // one item per offered slot, and no item is in more than one of them
    // (CosmeticsTests pins both).  Every other catalogue entry is RETIRED: it
    // is never listed or sold as a set, but its definition stays so owners'
    // records (`ownedBundles`, completed-collection counts) keep their
    // meaning.  Pieces of retired and seasonal sets are HELD — not shown, not
    // sold, not announced (`CosmeticSale`); owners keep and can equip them.
    // Seasonal events sell nothing of their own; each features one full
    // active collection (`SeasonalEvent`).

    static let activeIDs: [String] = [
        // Launch: the Starter Pack's Aurora, the post-tutorial starter
        // choice (Nature, Fire, Water, Storm), the other Standard sets and
        // the eight Challenge Track rewards.
        "aurora", "nature", "fire", "water", "storm",
        "citrus", "sketchbook", "midas",
        "winter", "cosmos", "lava-flow", "neon", "haunted",
        "ancient-temple", "abyssal-depths", "champion",
        // Quality round: Space Traveler (Quasar, Comet and the Space pit moved here).
        "space-traveler",
        // Calendar drops.
        "candyland", "nightclub", "golf", "bloom", "ocean",
    ]
    private static let activeIDSet = Set(activeIDs)

    /// The one-time post-tutorial starter choice, in display order: exactly
    /// these four element sets.  (Citrus, Midas and Sketchbook stay on sale
    /// in the Shop but are no longer offered here.)
    static let starterGiftIDs: [String] = ["nature", "fire", "water", "storm"]

    /// The starter-choice collections, in `starterGiftIDs` order.
    static var starterGift: [CosmeticBundle] {
        starterGiftIDs.compactMap { id in catalogue.first { $0.id == id } }
    }

    /// True for a collection that is no longer sold as a set.
    var isRetired: Bool { !Self.activeIDSet.contains(id) }

    // MARK: Roll Along — the Iconic default set

    /// The six defaults every player starts with: Red ball, Target goal and the
    /// Classic trail, floor, pit and boundary.  Iconic: free, owned by every
    /// player from first launch and equipped on a fresh install; never sold or
    /// sellable.  Deliberately NOT in `catalogue`, so it is never in the Shop
    /// rotation, the featured bundle, gift pools, Challenge Track rewards or
    /// the release calendar.  The Catalog pins it first in Collections.
    static let rollAlongID = "roll-along"
    static let rollAlong = CosmeticBundle(
        id:             rollAlongID,
        displayName:    "Roll Along",
        tagline:        "The classic look every player starts with. Yours forever.",
        contentSummary: "Red ball · Target goal · Classic Shadow trail · Classic White floor · Classic Black pit · Classic Gray boundary",
        balls:  [BallSkin.starter],
        goals:  [GoalSkin.starter],
        trails: [TrailColor.starter],
        floors: [Floor.starter],
        pits:   [Pit.starter],
        music:  [],
        boundaries: [Boundary.starter]
    )

    /// True for the Iconic Roll Along set (free, owned by all, never sold).
    var isRollAlong: Bool { id == Self.rollAlongID }

    /// The Waiting Room collection (1.1): the Roll Along ball, floor, pit and
    /// boundary redrawn in a shiny, colour-shifting foil.  Given once, by the
    /// end room, to a player who clears every level in the pack.  Never sold:
    /// like `rollAlong` it is NOT in `catalogue`, so it is never in the Shop,
    /// the Catalog, a gift pool or the release calendar.  Its pieces show in
    /// the Locker once owned.
    static let waitingRoomID = "waiting-room"
    static let waitingRoom = CosmeticBundle(
        id:             waitingRoomID,
        displayName:    "Waiting Room",
        tagline:        "For clearing every level there is. So far.",
        contentSummary: "Waiting Room ball · Waiting Room floor · Waiting Room pit · Waiting Room boundary",
        balls:  [.waitingRoom],
        goals:  [],
        trails: [],
        floors: [.waitingRoom],
        pits:   [.waitingRoom],
        music:  [],
        boundaries: [.waitingRoom]
    )

    /// The collections on sale, in catalogue order.
    static var active: [CosmeticBundle] { catalogue.filter { !$0.isRetired } }

    /// Add every contained item to the appropriate owned-set on
    /// `state`.  One-way grant — items remain owned forever even if
    /// the bundle itself is later removed from the catalogue.
    func grantContents(to state: GameState) {
        balls.forEach  { state.grant($0) }
        goals.forEach  { state.grant($0) }
        trails.forEach { state.grant($0) }
        floors.forEach { state.grant($0) }
        pits.forEach   { state.grant($0) }
        offeredMusic.forEach  { state.grant($0) }
        boundaries.forEach { state.grant($0) }
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
            contentSummary: "Ruby ball · Inferno goal · Ember floor · Evil pit · Fire trail · Synthwave music · Molten boundary",
            balls:  [.ruby],
            goals:  [.inferno],
            trails: [.fire],
            floors: [.ember],
            pits:   [.evil],
            music:  [.synthwave],
            boundaries: [.molten]
        ),
        CosmeticBundle(
            id:             "heavens",
            displayName:    "Heavens",
            tagline:        "Drift the sky on opal lustre.",
            contentSummary: "Opal ball · Halo goal · Sky pit · Stardust trail · Celestial music · Cloud boundary",
            balls:  [.opal],
            goals:  [.halo],
            trails: [.stardust],
            floors: [],
            pits:   [.sky],
            music:  [.celestial],
            boundaries: [.cloud]
        ),
        CosmeticBundle(
            id:             "nightclub",
            displayName:    "Nightclub",
            tagline:        "Mirror ball, a spinning record and a sunken dance floor.",
            contentSummary: "Disco Ball · Vinyl goal · Dance Steps trail · Disco floor · Nightclub pit · Retrowave music · Marquee boundary",
            balls:  [.disco],
            goals:  [.vinyl],
            trails: [.danceSteps],
            floors: [.disco],
            pits:   [.nightclub],
            music:  [.retrowave],
            boundaries: [.marquee]
        ),
        CosmeticBundle(
            id:             "paper-world",
            displayName:    "Paper World",
            tagline:        "The full Notebook pack.",
            contentSummary: "Paper ball · Doodle goal · Notebook floor · Notebook pit · Lo-fi music · Notebook boundary",
            balls:  [.paper],
            goals:  [.doodle],
            trails: [],            // Graphite now belongs to Sketchbook only (no shared pieces)
            floors: [.notebook],
            pits:   [.notebook],
            music:  [.lofi],
            boundaries: [.notebook]
        ),
        CosmeticBundle(
            id:             "golf",
            displayName:    "Golf",
            tagline:        "Dimpled ball, a mown green in the morning dew, a lily-pad pond and the flag.",
            contentSummary: "Golf Ball · Hole-in-One goal · Dew Line trail · Grass floor · Pond pit · Jazz music · Fairway boundary",
            balls:  [.golfBall],
            goals:  [.holeInOne],
            trails: [.dewLine],
            floors: [.grass],
            pits:   [.pond],
            music:  [.jazz],
            boundaries: [.fairway]
        ),

        CosmeticBundle(
            id:             "planets",
            displayName:    "Planets",
            tagline:        "Roll the whole solar system — plus a tiny Pluto.",
            contentSummary: "Earth · Mars · Saturn · Mercury · Neptune · Jupiter · Venus · Uranus + exclusive half-size Pluto · Galaxy goal · Stardust trail · Midnight floor · Space pit · Celestial music · Starlight boundary",
            balls:  [.earth, .mars, .saturn, .mercury,
                     .neptune, .jupiter, .venus, .uranus, .pluto],
            goals:  [.galaxy],
            trails: [.stardust],
            floors: [.midnight],
            pits:   [.space],
            music:  [.celestial],
            boundaries: [.starlight]
        ),

        CosmeticBundle(
            id:             "space-travel",
            displayName:    "Space Travel",
            tagline:        "Pilot a saucer across the moon and into the void.",
            contentSummary: "UFO ball · Moon floor · Space pit · Tractor Beam goal · Raybeam trail · Retrowave music · Starlight boundary",
            balls:  [.ufo],
            goals:  [.tractorBeam],
            trails: [.raybeam],
            floors: [.moon],
            pits:   [.space],
            music:  [.retrowave],
            boundaries: [.starlight]
        ),

        // Quality round: the active space set.  UFO and Moon come from the
        // retired "space-travel" set above (kept for owners); Quasar and Comet
        // came from Champion and the Space pit from Abyssal Depths.  On sale
        // from launch (see CosmeticSchedule.launchBundleIDs), so it needs no
        // calendar row.
        CosmeticBundle(
            id:             "space-traveler",
            displayName:    "Space Traveler",
            tagline:        "A saucer, a comet's wake and a quasar to steer by.",
            contentSummary: "UFO ball · Quasar goal · Comet trail · Moon floor · Space pit · Retrowave music · Starship Hull boundary",
            balls:  [.ufo],
            goals:  [.quasar],
            trails: [.cometTrail],
            floors: [.moon],
            pits:   [.space],
            music:  [.retrowave],
            boundaries: [.hull]
        ),

        CosmeticBundle(
            id:             "winter",
            displayName:    "Winter",
            tagline:        "A frozen pond, deep snow and a snowglobe ball.",
            contentSummary: "Snowglobe ball · Frost goal · Ice trail · Snowfield floor · Crevasse pit · Classical music · Ice boundary",
            balls:  [.snowglobe],
            goals:  [.frost],
            trails: [.ice],
            floors: [.twilight],
            pits:   [.twilight],
            music:  [.classical],
            boundaries: [.ice]
        ),

        CosmeticBundle(
            id:             "cosmos",
            displayName:    "Cosmos",
            tagline:        "Drift the deep with a nebula in hand.",
            contentSummary: "Nebula ball · Galaxy goal · Stardust trail · Midnight floor · Moonlit pit · Celestial music · Starlight boundary",
            balls:  [.nebula],
            goals:  [.galaxy],
            trails: [.stardust],
            floors: [.midnight],
            pits:   [.midnight],
            music:  [.celestial],
            boundaries: [.starlight]
        ),

        CosmeticBundle(
            id:             "nature",
            displayName:    "Nature",
            tagline:        "A mossy tree stump, long grass and a mint-green rim.",
            contentSummary: "Jade ball · Tree Stump goal · Forest trail · Meadow floor · Meadow pit · Acoustic music · Mint boundary",
            balls:  [.jade],
            goals:  [.treeStump],
            trails: [.forest],
            floors: [.meadow],
            pits:   [.meadow],
            music:  [.acoustic],
            boundaries: [.mint]
        ),

        // ── Starter element sets (post-tutorial choice, with Nature) ──
        // All-new Standard art, every piece still; one per offered slot.
        CosmeticBundle(
            id:             "fire",
            displayName:    "Fire",
            tagline:        "Glowing coals, flame tongues and a crater of embers.",
            contentSummary: "Blaze ball · Flame Ring goal · Wildfire trail · Scorched floor · Crater pit · Electronic music · Flare boundary",
            balls:  [.blaze],
            goals:  [.flameRing],
            trails: [.wildfire],
            floors: [.scorched],
            pits:   [.crater],
            music:  [.electronic],
            boundaries: [.flare]
        ),
        CosmeticBundle(
            id:             "water",
            displayName:    "Water",
            tagline:        "Droplets, ripples and a whirlpool to roll into.",
            contentSummary: "Droplet ball · Whirlpool goal · Splash trail · Shallows floor · Deep End pit · Classical music · Breakers boundary",
            balls:  [.droplet],
            goals:  [.whirlpool],
            trails: [.splash],
            floors: [.shallows],
            pits:   [.deepEnd],
            music:  [.classical],
            boundaries: [.breakers]
        ),
        CosmeticBundle(
            id:             "storm",
            displayName:    "Storm",
            tagline:        "Dark rolling cloud, driving rain and rare forked lightning.",
            contentSummary: "Thundercloud ball · Storm Eye goal · Squall trail · Overcast floor · Maelstrom pit · Orchestral music · Thunderhead boundary",
            balls:  [.thundercloud],
            goals:  [.thunderRing],
            trails: [.squall],
            floors: [.overcast],
            pits:   [.maelstrom],
            music:  [.orchestral],
            boundaries: [.thunderbolt]
        ),

        CosmeticBundle(
            id:             "ocean",
            displayName:    "Ocean",
            tagline:        "Open water, a coral reef and the tide coming in.",
            contentSummary: "Aquarium ball · Ripple goal · Wake trail · Open Sea floor · Reef pit · Lo-fi music · Tide boundary",
            balls:  [.aquarium],
            goals:  [.ripple],
            trails: [.wake],
            floors: [.openSea],
            pits:   [.reef],
            music:  [.lofi],
            boundaries: [.tide]
        ),

        CosmeticBundle(
            id:             "velvet-night",
            displayName:    "Velvet Night",
            tagline:        "Plasma and rainbow over deep velvet.",
            contentSummary: "Purple ball · Plasma goal · Rainbow trail · Velvet floor · Velvet pit · Downtempo music · Velvet boundary",
            balls:  [.purple],
            goals:  [.plasma],
            trails: [.rainbow],
            floors: [.velvet],
            pits:   [.velvet],
            music:  [.downtempo],
            boundaries: [.velvet]
        ),

        CosmeticBundle(
            id:             "golden-hour",
            displayName:    "Golden Hour",
            tagline:        "Chase the last warm light of the day.",
            contentSummary: "Coral ball · Mirage goal · Fire trail · Sunset floor · Dusk pit · Acoustic music · Sunset boundary",
            balls:  [.coral],
            goals:  [.mirage],
            trails: [.fire],
            floors: [.sunset],
            pits:   [.dusk],
            music:  [.acoustic],
            boundaries: [.sunset]
        ),

        CosmeticBundle(
            id:             "arcade",
            displayName:    "Arcade",
            tagline:        "Pixel-perfect retro on a grid.",
            contentSummary: "Copper ball · Comet goal · Comet trail · Graph floor · Blackout pit · Chiptune music · Neon boundary",
            balls:  [.copper],
            goals:  [.comet],
            trails: [.cometTrail],
            floors: [.graph],
            pits:   [.graph],
            music:  [.chiptune],
            boundaries: [.neon]
        ),

        CosmeticBundle(
            id:             "bloom",
            displayName:    "Bloom",
            tagline:        "A rose garden in full bloom, petals on the path.",
            contentSummary: "Rose ball · Blossom goal · Rose trail · Petal Path floor · Deep Rose pit · Piano music · Rose boundary",
            balls:  [.rose],
            goals:  [.blossom],
            trails: [.roseTrail],
            floors: [.petalPath],
            pits:   [.deepRose],
            music:  [.piano],
            boundaries: [.rose]
        ),

        CosmeticBundle(
            id:             "noir",
            displayName:    "Noir",
            tagline:        "Black, white, and everything stark.",
            contentSummary: "Slate ball · Obsidian goal · Ink trail · Inverted floor · Inverted pit · Cinematic music · Ink boundary",
            balls:  [.slate],
            goals:  [.obsidian],
            trails: [.ink],
            floors: [.inverted],
            pits:   [.inverted],
            music:  [.cinematic],
            boundaries: [.ink]
        ),

        CosmeticBundle(
            id:             "aurora",
            displayName:    "Aurora",
            tagline:        "Chase the northern lights.",
            contentSummary: "Aurora ball · Aurora goal · Aurora trail · Aurora floor · Aurora pit · Aurora music · Aurora boundary",
            balls:  [.aurora],
            goals:  [.aurora],
            trails: [.aurora],
            floors: [.aurora],
            pits:   [.aurora],
            music:  [.aurora],
            boundaries: [.aurora]
        ),

        CosmeticBundle(
            id:             "citrus",
            displayName:    "Citrus",
            tagline:        "Tropical groves, cut fruit and bright beach light.",
            contentSummary: "Lemon ball · Citrus Slice goal · Zest trail · Grove floor · Tide Pool pit · Jazz music · Citrus boundary",
            balls:  [.lemon],
            goals:  [.citrusSlice],
            trails: [.zest],
            floors: [.grove],
            pits:   [.tidePool],
            music:  [.jazz],
            boundaries: [.citrus]
        ),

        CosmeticBundle(
            id:             "midas",
            displayName:    "Midas",
            tagline:        "Everything you touch turns to gold.",
            contentSummary: "Fool's Gold ball · Bullion goal · Gilded trail · Gold Leaf floor · Vault pit · Orchestral music · Gold boundary",
            balls:  [.gold],
            goals:  [.bullion],
            trails: [.gilded],
            floors: [.goldLeaf],
            pits:   [.vault],
            music:  [.orchestral],
            boundaries: [.gold]
        ),

        CosmeticBundle(
            id:             "sketchbook",
            displayName:    "Sketchbook",
            tagline:        "A pencil, a page of doodles and a hand-drawn target.",
            contentSummary: "Pencil ball · Scribble goal · Graphite trail · Paper floor · Sketch pit · Classical music · Slate boundary",
            balls:  [.pencil],
            goals:  [.scribble],
            trails: [.graphite],
            floors: [.sketch],
            pits:   [.sketch],
            music:  [.classical],
            boundaries: [.slate]
        ),

        CosmeticBundle(
            id:             "zen-garden",
            displayName:    "Zen Garden",
            tagline:        "A folded-paper serpent in a calm green world.",
            contentSummary: "Green ball · Rainbow goal · Snake trail · Origami floor · Origami pit · Dreamscape music · Sand boundary",
            balls:  [.green],
            goals:  [.rainbow],
            trails: [.snake],
            floors: [.origami],
            pits:   [.origami],
            music:  [.dreamscape],
            boundaries: [.sand]
        ),

        CosmeticBundle(
            id:             "eclipse",
            displayName:    "Eclipse",
            tagline:        "A golden corona around the dark.",
            contentSummary: "Blue ball · Eclipse goal · Eclipse floor · Eclipse pit · Gilded trail · Mysterium music · Corona boundary",
            balls:  [.blue],
            goals:  [.eclipse],
            trails: [.gilded],
            floors: [.eclipse],
            pits:   [.eclipse],
            music:  [.mysterium],
            boundaries: [.corona]
        ),
        CosmeticBundle(
            id:             "pastel",
            displayName:    "Pastel",
            tagline:        "Soft candy hues and a gentle piano.",
            contentSummary: "Pastel ball · Blossom goal · Rose trail · Twilight floor · Parchment pit · Piano music · Pastel boundary",
            balls:  [.pastel],
            goals:  [.blossom],
            trails: [.roseTrail],
            floors: [.twilight],
            pits:   [.parchment],
            music:  [.piano],
            boundaries: [.pastel]
        ),
        CosmeticBundle(
            id:             "neon",
            displayName:    "Neon",
            tagline:        "Electric pink and laser green on a glowing grid.",
            contentSummary: "Neon ball · Neon goal · Raybeam trail · Grid City floor · Blackout pit · Electronic music · Neon boundary",
            balls:  [.neon],
            goals:  [.neon],
            trails: [.raybeam],
            floors: [.gridCity],
            pits:   [.graph],
            music:  [.electronic],
            boundaries: [.neon]
        ),
        CosmeticBundle(
            id:             "soccer",
            displayName:    "Soccer",
            tagline:        "Hit the pitch — hex-stitched ball on fresh turf.",
            contentSummary: "Soccer Ball · Soccer Net goal · Smoke trail · Grass floor · Meadow pit · Synthwave music · Fairway boundary",
            balls:  [.soccer],
            goals:  [.soccerNet],
            trails: [.smoke],
            floors: [.grass],
            pits:   [.meadow],
            music:  [.synthwave],
            boundaries: [.fairway]
        ),
        CosmeticBundle(
            id:             "aquarium",
            displayName:    "Aquarium",
            tagline:        "A glass orb of bubbles over a rippling pond.",
            contentSummary: "Aquarium ball · Ripple goal · Ice trail · Mirage floor · Pond pit · Dreamscape music · Tide boundary",
            balls:  [.aquarium],
            goals:  [.ripple],
            trails: [.ice],
            floors: [.mirage],
            pits:   [.pond],
            music:  [.dreamscape],
            boundaries: [.tide]
        ),
        CosmeticBundle(
            id:             "realistic-marble",
            displayName:    "Realistic Marble",
            tagline:        "A genuine glass cat's-eye, swirled in cobalt.",
            contentSummary: "Marble ball · Crystal goal · Gilded trail · Velvet floor · Velvet pit · Cinematic music · Marble boundary",
            balls:  [.marble],
            goals:  [.crystal],
            trails: [.gilded],
            floors: [.velvet],
            pits:   [.velvet],
            music:  [.cinematic],
            boundaries: [.marble]
        ),

        // ── Round 5 ──
        CosmeticBundle(
            id:             "dune",
            displayName:    "Dune",
            tagline:        "Drift the desert as the sun sinks low.",
            contentSummary: "Dune ball · Mirage goal · Air trail · Desert floor · Canyon pit · Ambient music · Sand boundary",
            balls:  [.dune],
            goals:  [.mirage],
            trails: [.air],
            floors: [.desert],
            pits:   [.canyon],
            music:  [.ambient],
            boundaries: [.sand]
        ),
        CosmeticBundle(
            id:             "tempest",
            displayName:    "Tempest",
            tagline:        "Lightning sealed inside a marble.",
            contentSummary: "Storm ball · Plasma goal · Smoke trail · Stormcloud floor · Downpour pit · Retrowave music · Storm boundary",
            balls:  [.storm],
            goals:  [.plasma],
            trails: [.smoke],
            floors: [.stormcloud],
            pits:   [.downpour],
            music:  [.retrowave],
            boundaries: [.storm]
        ),
        CosmeticBundle(
            id:             "candyland",
            displayName:    "Candyland",
            tagline:        "Peppermint, bubblegum and a pool of syrup.",
            contentSummary: "Candy ball · Candy goal · Bubblegum trail · Sugar floor · Syrup pit · Lo-fi music · Candy boundary",
            balls:  [.candy],
            goals:  [.candy],
            trails: [.bubblegum],
            floors: [.sugar],
            pits:   [.syrup],
            music:  [.lofi],
            boundaries: [.candy]
        ),
        CosmeticBundle(
            id:             "haunted",
            displayName:    "Haunted",
            tagline:        "A restless spirit drifting through the dark.",
            contentSummary: "Ghost ball · Pentagram goal · Smoke trail · Fog floor · Graveyard pit · Downtempo music · Phantom boundary",
            balls:  [.ghost],
            goals:  [.pentagram],
            trails: [.smoke],
            floors: [.fog],
            pits:   [.graveyard],
            music:  [.downtempo],
            boundaries: [.phantom]
        ),

        // ── Seasonal bundles (limited-time, return annually) ───────────
        // The dates below are one year's window; it repeats on the same
        // calendar days every year, except where the release calendar has a
        // per-year row (CosmeticBundle.currentWindow).  Windows match the
        // approved calendar (docs/proposals/cosmetic-calendar.md) and the
        // seasonal rows in database step 11.
        //
        // Items used here are shared with permanent bundles for now.  S4 will
        // add bespoke exclusive cosmetics (beach ball, sandy floor, wave trail,
        // etc.) and update these entries.  The availability window is what
        // makes them feel special, not just the items.
        CosmeticBundle(
            id:             "summer-2026",
            displayName:    "Summer Vibes",
            tagline:        "Sun, sea, and rolling waves.",
            contentSummary: "Beach Ball · Ripple goal · Sky trail · Blueprint floor · Pond pit · Acoustic music · Sky boundary",
            balls:  [.beachBall],
            goals:  [.ripple],
            trails: [.sky],
            floors: [.blueprint],
            pits:   [.pond],
            music:  [.acoustic],
            boundaries: [.sky],
            availableFrom:  CosmeticBundle.date(2026, 6,  1),
            availableUntil: CosmeticBundle.date(2026, 9,  1)
        ),
        CosmeticBundle(
            id:             "halloween-2026",
            displayName:    "Trick or Roll",
            tagline:        "A restless spirit through the dark.",
            contentSummary: "Pumpkin ball · Obsidian goal · Smoke trail · Fog floor · Graveyard pit · Downtempo music · Pumpkin boundary",
            balls:  [.pumpkin],
            goals:  [.obsidian],
            trails: [.smoke],
            floors: [.fog],
            pits:   [.graveyard],
            music:  [.downtempo],
            boundaries: [.pumpkin],
            availableFrom:  CosmeticBundle.date(2026, 10,  1),
            availableUntil: CosmeticBundle.date(2026, 11,  1)
        ),
        CosmeticBundle(
            id:             "winter-2026",
            displayName:    "Winter Wonderland",
            tagline:        "A mirror-bright ornament through crystal frost.",
            contentSummary: "Ornament ball · Crystal goal · Ice trail · Twilight floor · Twilight pit · Dreamscape music · Holly boundary",
            balls:  [.ornament],
            goals:  [.crystal],
            trails: [.ice],
            floors: [.twilight],
            pits:   [.twilight],
            music:  [.dreamscape],
            boundaries: [.holly],
            availableFrom:  CosmeticBundle.date(2026, 12,  1),
            availableUntil: CosmeticBundle.date(2027,  1,  6)
        ),
        CosmeticBundle(
            id:             "valentines-2027",
            displayName:    "Sweetheart",
            tagline:        "All heart, no brakes.",
            contentSummary: "Heartstone ball · Blossom goal · Rose trail · Velvet floor · Dusk pit · Piano music · Rose boundary",
            balls:  [.heartstone],
            goals:  [.blossom],
            trails: [.roseTrail],
            floors: [.velvet],
            pits:   [.dusk],
            music:  [.piano],
            boundaries: [.rose],
            availableFrom:  CosmeticBundle.date(2027, 2,  1),
            availableUntil: CosmeticBundle.date(2027, 2, 15)
        ),
        CosmeticBundle(
            id:             "stpatricks-2027",
            displayName:    "Luck of the Roll",
            tagline:        "Find your four-leaf marble.",
            contentSummary: "Shamrock ball · Mirage goal · Gilded trail · Meadow floor · Pond pit · Lofi music · Shamrock boundary",
            balls:  [.shamrock],
            goals:  [.mirage],
            trails: [.gilded],
            floors: [.meadow],
            pits:   [.pond],
            music:  [.lofi],
            boundaries: [.shamrock],
            availableFrom:  CosmeticBundle.date(2027, 3,  1),
            availableUntil: CosmeticBundle.date(2027, 3, 18)
        ),
        CosmeticBundle(
            id:             "newyear-2027",
            displayName:    "Countdown",
            tagline:        "Three, two, one — roll.",
            contentSummary: "Confetti ball · Rainbow goal · Gilded trail · Disco floor · Moonlit pit · Electronic music · Confetti boundary",
            balls:  [.confetti],
            goals:  [.rainbow],
            trails: [.gilded],
            floors: [.disco],
            pits:   [.midnight],
            music:  [.electronic],
            boundaries: [.confetti],
            availableFrom:  CosmeticBundle.date(2026, 12, 26),
            availableUntil: CosmeticBundle.date(2027,  1,  5)
        ),
        CosmeticBundle(
            id:             "spring-2027",
            displayName:    "Spring Fling",
            tagline:        "Speckled. Bright. Unstoppable.",
            contentSummary: "Speckled Egg ball · Mosaic goal · Forest trail · Meadow floor · Sky pit · Acoustic music · Pastel boundary",
            balls:  [.speckledEgg],
            goals:  [.mosaic],
            trails: [.forest],
            floors: [.meadow],
            pits:   [.sky],
            music:  [.acoustic],
            boundaries: [.pastel],
            availableFrom:  CosmeticBundle.date(2027, 3, 20),
            availableUntil: CosmeticBundle.date(2027, 5,  1)
        ),
        CosmeticBundle(
            id:             "july4-2026",
            displayName:    "Star-Spangled",
            tagline:        "Light up the night sky.",
            contentSummary: "Fireworks ball · Rainbow goal · Stardust trail · Midnight floor · Moonlit pit · Orchestral music · Star-Spangled boundary",
            balls:  [.fireworks],
            goals:  [.rainbow],
            trails: [.stardust],
            floors: [.midnight],
            pits:   [.midnight],
            music:  [.orchestral],
            boundaries: [.starSpangled],
            availableFrom:  CosmeticBundle.date(2026, 6, 21),
            availableUntil: CosmeticBundle.date(2026, 7,  6)
        ),
        CosmeticBundle(
            id:             "muertos-2026",
            displayName:    "Día de los Muertos",
            tagline:        "Roll bright, remember well.",
            contentSummary: "Sugar Skull ball · Blossom goal · Rose trail · Velvet floor · Graveyard pit · Downtempo music · Marigold boundary",
            balls:  [.sugarSkull],
            goals:  [.blossom],
            trails: [.roseTrail],
            floors: [.velvet],
            pits:   [.graveyard],
            music:  [.downtempo],
            boundaries: [.marigold],
            availableFrom:  CosmeticBundle.date(2026, 10, 21),
            availableUntil: CosmeticBundle.date(2026, 11,  3)
        ),
        CosmeticBundle(
            id:             "harvest-2026",
            displayName:    "Harvest Moon",
            tagline:        "Gather the golden hour in.",
            contentSummary: "Harvest Moon ball · Flame goal · Ember trail · Desert floor · Canyon pit · Lo-fi music · Autumn boundary",
            balls:  [.harvest],
            goals:  [.flame],
            trails: [.ember],
            floors: [.desert],
            pits:   [.canyon],
            music:  [.lofi],
            boundaries: [.autumn],
            availableFrom:  CosmeticBundle.date(2026, 11, 1),
            availableUntil: CosmeticBundle.date(2026, 11, 30)
        ),
        CosmeticBundle(
            id:             "lunar-2027",
            displayName:    "Lunar New Year",
            tagline:        "Fortune favors the fast.",
            contentSummary: "Golden Dragon ball · Flame goal · Gilded trail · Velvet floor · Velvet pit · Cinematic music · Lantern boundary",
            balls:  [.lunarDragon],
            goals:  [.flame],
            trails: [.gilded],
            floors: [.velvet],
            pits:   [.velvet],
            music:  [.cinematic],
            boundaries: [.lantern],
            availableFrom:  CosmeticBundle.date(2027, 1, 27),
            availableUntil: CosmeticBundle.date(2027, 2, 20)
        ),
        CosmeticBundle(
            id:             "mardigras-2027",
            displayName:    "Mardi Gras",
            tagline:        "Purple, green, and gold — let the good times roll.",
            contentSummary: "Mardi Gras ball · Plasma goal · Bubblegum trail · Disco floor · Moonlit pit · Jazz music · Orchid boundary",
            balls:  [.mardiGras],
            goals:  [.plasma],
            trails: [.bubblegum],
            floors: [.disco],
            pits:   [.midnight],
            music:  [.jazz],
            boundaries: [.orchid],
            availableFrom:  CosmeticBundle.date(2027, 1, 28),
            availableUntil: CosmeticBundle.date(2027, 2, 10)
        ),
        CosmeticBundle(
            id:             "pride-2027",
            displayName:    "Spectrum",
            tagline:        "Roll proud, roll loud.",
            contentSummary: "Spectrum ball · Rainbow goal · Rainbow trail · Aurora floor · Aurora pit · Electronic music · Rainbow boundary",
            balls:  [.spectrum],
            goals:  [.rainbow],
            trails: [.rainbow],
            floors: [.aurora],
            pits:   [.aurora],
            music:  [.electronic],
            boundaries: [.rainbow],
            availableFrom:  CosmeticBundle.date(2027, 6, 1),
            availableUntil: CosmeticBundle.date(2027, 6, 30)
        ),
        CosmeticBundle(
            id:             "oktoberfest-2026",
            displayName:    "Oktoberfest",
            tagline:        "Prost! Raise a stein and roll.",
            contentSummary: "Oktoberfest ball · Mirage goal · Ember trail · Meadow floor · Canyon pit · Acoustic music · Autumn boundary",
            balls:  [.oktoberfest],
            goals:  [.mirage],
            trails: [.ember],
            floors: [.meadow],
            pits:   [.canyon],
            music:  [.acoustic],
            boundaries: [.autumn],
            availableFrom:  CosmeticBundle.date(2026, 9, 16),
            availableUntil: CosmeticBundle.date(2026, 10, 4)
        ),
        CosmeticBundle(
            id:             "earthday-2027",
            displayName:    "Earth Day",
            tagline:        "One small planet, one perfect roll.",
            contentSummary: "Earth ball · Blossom goal · Forest trail · Meadow floor · Meadow pit · Ambient music · Mint boundary",
            balls:  [.earth],
            goals:  [.blossom],
            trails: [.forest],
            floors: [.meadow],
            pits:   [.meadow],
            music:  [.ambient],
            boundaries: [.mint],
            availableFrom:  CosmeticBundle.date(2027, 4, 12),
            availableUntil: CosmeticBundle.date(2027, 4, 26)
        ),
        CosmeticBundle(
            id:             "backtoschool-2026",
            displayName:    "Back to School",
            tagline:        "Sharpen up. Class is rolling.",
            contentSummary: "Teacher's Apple ball · Ink trail · Notebook floor · Notebook pit · Piano music · Notebook boundary",
            balls:  [.apple],
            goals:  [],
            trails: [.ink],
            floors: [.notebook],
            pits:   [.notebook],
            music:  [.piano],
            boundaries: [.notebook],
            availableFrom:  CosmeticBundle.date(2026, 8, 1),
            availableUntil: CosmeticBundle.date(2026, 9, 8)
        ),

        // ── Sports bundles ──────────────────────────────────────────────
        CosmeticBundle(
            id:             "full-court",
            displayName:    "Full Court",
            tagline:        "Hardwood, orange leather, and the buzz of the arena.",
            contentSummary: "Basketball · Eclipse goal · Fire trail · Court floor · Sideline pit · Jazz music · Hardwood boundary",
            balls:  [.basketball],
            goals:  [.eclipse],
            trails: [.fire],
            floors: [.court],
            pits:   [.sideline],
            music:  [.jazz],
            boundaries: [.hardwood]
        ),
        CosmeticBundle(
            id:             "billiards-hall",
            displayName:    "Billiards Hall",
            tagline:        "Eight ball, corner pocket. The felt is perfect.",
            contentSummary: "8-Ball · Crystal goal · Smoke trail · Felt floor · Pocket pit · Jazz music · Mahogany boundary",
            balls:  [.eightBall],
            goals:  [.crystal],
            trails: [.smoke],
            floors: [.felt],
            pits:   [.pocket],
            music:  [.jazz],
            boundaries: [.mahogany]
        ),
        CosmeticBundle(
            id:             "diamond",
            displayName:    "Diamond",
            tagline:        "Step up to the plate. The crowd is watching.",
            contentSummary: "Baseball · Rose trail · Meadow floor · Sketch pit · Orchestral music · Fairway boundary",
            balls:  [.baseball],
            goals:  [],
            trails: [.roseTrail],
            floors: [.meadow],
            pits:   [.sketch],
            music:  [.orchestral],
            boundaries: [.fairway]
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
            tagline:        "Carved glyphs, drifting sand and sun-baked stone.",
            contentSummary: "Dune ball · Eclipse goal · Glyphs trail · Desert floor · Canyon pit · Orchestral music · Sandstone boundary",
            balls:  [.dune],
            goals:  [.eclipse],
            trails: [.glyphs],
            floors: [.desert],
            pits:   [.canyon],
            music:  [.orchestral],
            boundaries: [.sandstone]
        ),
        //
        // S21 ─────────────────────────────────────────────────────────────
        CosmeticBundle(
            id:             "abyssal-depths",
            displayName:    "Abyssal Depths",
            tagline:        "Squid ink, a whirlpool and a glowing vent at the bottom of the sea.",
            contentSummary: "Trench ball · Vortex goal · Ink trail · Inverted floor · Sea Vent pit · Dreamscape music · Abyss boundary",
            balls:  [.trench],
            goals:  [.vortex],
            trails: [.ink],
            floors: [.inverted],
            pits:   [.vent],
            music:  [.dreamscape],
            boundaries: [.abyss]
        ),
        // S22 ─────────────────────────────────────────────────────────────
        // Trophy ball is isBundleExclusive = true — hidden from shop grid,
        // only earned by completing Golden Gauntlet.
        CosmeticBundle(
            id:             "champion",
            displayName:    "Champion",
            tagline:        "Polished brass, a laurel wreath and the trophy itself.",
            contentSummary: "Trophy ball · Winner's Circle goal · Victory Lap trail · Brass Works floor · Sideline pit · Orchestral music · Brass boundary",
            balls:  [.trophy],
            goals:  [.winnersCircle],
            trails: [.victoryLap],
            floors: [.brass],
            pits:   [.sideline],
            music:  [.orchestral],
            boundaries: [.brass]
        ),

        // ── S15 ──────────────────────────────────────────────────────────
        CosmeticBundle(
            id:             "crystal-cavern",
            displayName:    "Crystal Cavern",
            tagline:        "Deep underground, the crystals glow.",
            contentSummary: "Opal ball · Prism goal · Comet trail · Midnight floor · Aurora pit · Mysterium music · Amethyst boundary",
            balls:  [.opal],
            goals:  [.prism],
            trails: [.cometTrail],
            floors: [.midnight],
            pits:   [.aurora],
            music:  [.mysterium],
            boundaries: [.amethyst]
        ),

        // ── S16 ──────────────────────────────────────────────────────────
        CosmeticBundle(
            id:             "midnight-carnival",
            displayName:    "Midnight Carnival",
            tagline:        "The rides never stop when the sun goes down.",
            contentSummary: "Copper ball · Neon goal · Fire trail · Midnight floor · Velvet pit · Retrowave music · Marquee boundary",
            balls:  [.copper],
            goals:  [.neon],
            trails: [.fire],
            floors: [.midnight],
            pits:   [.velvet],
            music:  [.retrowave],
            boundaries: [.marquee]
        ),

        // ── S17 ──────────────────────────────────────────────────────────
        CosmeticBundle(
            id:             "lava-flow",
            displayName:    "Lava Flow",
            tagline:        "Molten rock, open flame and a demon's pit.",
            contentSummary: "Lava ball · Inferno goal · Fire trail · Ember floor · Evil pit · Downtempo music · Molten boundary",
            balls:  [.lava],
            goals:  [.inferno],
            trails: [.fire],
            floors: [.ember],
            pits:   [.evil],
            music:  [.downtempo],
            boundaries: [.molten]
        ),

        // ── Premium bundles (permanent — no availability window) ─────────
        CosmeticBundle(
            id:             "high-roller",
            displayName:    "High Roller",
            tagline:        "The house always remembers your name.",
            contentSummary: "High Roller ball · Quasar goal · Gilded trail · Felt floor · Pocket pit · Jazz music · Mahogany boundary",
            balls:  [.highRoller],
            goals:  [.quasar],
            trails: [.gilded],
            floors: [.felt],
            pits:   [.pocket],
            music:  [.jazz],
            boundaries: [.mahogany]
        ),
        CosmeticBundle(
            id:             "quicksilver",
            displayName:    "Quicksilver",
            tagline:        "Liquid metal with a mind of its own.",
            contentSummary: "Quicksilver ball · Prism goal · Smoke trail · Inverted floor · Inverted pit · Cinematic music · Chrome boundary",
            balls:  [.quicksilver],
            goals:  [.prism],
            trails: [.smoke],
            floors: [.inverted],
            pits:   [.inverted],
            music:  [.cinematic],
            boundaries: [.chrome]
        ),
        CosmeticBundle(
            id:             "oracle",
            displayName:    "Oracle",
            tagline:        "Gaze in. Roll forward.",
            contentSummary: "Oracle ball · Galaxy goal · Stardust trail · Midnight floor · Moonlit pit · Mysterium music · Starlight boundary",
            balls:  [.oracle],
            goals:  [.galaxy],
            trails: [.stardust],
            floors: [.midnight],
            pits:   [.midnight],
            music:  [.mysterium],
            boundaries: [.starlight]
        ),
        CosmeticBundle(
            id:             "geode",
            displayName:    "Geode",
            tagline:        "Cracked open, brilliant inside.",
            contentSummary: "Geode ball · Crystal goal · Ice trail · Velvet floor · Velvet pit · Classical music · Amethyst boundary",
            balls:  [.geode],
            goals:  [.crystal],
            trails: [.ice],
            floors: [.velvet],
            pits:   [.velvet],
            music:  [.classical],
            boundaries: [.amethyst]
        ),
        CosmeticBundle(
            id:             "lava-lamp",
            displayName:    "Lava Lamp",
            tagline:        "Slow, warm, and a little groovy.",
            contentSummary: "Lava Lamp ball · Plasma goal · Ember trail · Disco floor · Moonlit pit · Retrowave music · Orchid boundary",
            balls:  [.lavaLamp],
            goals:  [.plasma],
            trails: [.ember],
            floors: [.disco],
            pits:   [.midnight],
            music:  [.retrowave],
            boundaries: [.orchid]
        ),
        CosmeticBundle(
            id:             "plasma-globe",
            displayName:    "Plasma Globe",
            tagline:        "Touch the glass. Feel the charge.",
            contentSummary: "Plasma Globe ball · Neon goal · Raybeam trail · Midnight floor · Space pit · Synthwave music · Storm boundary",
            balls:  [.plasmaGlobe],
            goals:  [.neon],
            trails: [.raybeam],
            floors: [.midnight],
            pits:   [.space],
            music:  [.synthwave],
            boundaries: [.storm]
        ),
        CosmeticBundle(
            id:             "cathedral",
            displayName:    "Cathedral",
            tagline:        "Light through a thousand panes.",
            contentSummary: "Cathedral ball · Prism goal · Smoke trail · Velvet floor · Velvet pit · Orchestral music · Stained Glass boundary",
            balls:  [.cathedral],
            goals:  [.prism],
            trails: [.smoke],
            floors: [.velvet],
            pits:   [.velvet],
            music:  [.orchestral],
            boundaries: [.stainedGlass]
        ),
        CosmeticBundle(
            id:             "magma-core",
            displayName:    "Magma Core",
            tagline:        "A cracked shell over a molten heart.",
            contentSummary: "Magma Core ball · Eclipse goal · Fire trail · Stormcloud floor · Downpour pit · Cinematic music · Molten boundary",
            balls:  [.magmaCore],
            goals:  [.eclipse],
            trails: [.fire],
            floors: [.stormcloud],
            pits:   [.downpour],
            music:  [.cinematic],
            boundaries: [.molten]
        ),
        CosmeticBundle(
            id:             "neon-city",
            displayName:    "Neon City",
            tagline:        "Jack in. Roll out.",
            contentSummary: "Hologram ball · Neon goal · Raybeam trail · Grid City floor · Space pit · Synthwave music · Circuit boundary",
            balls:  [.hologram],
            goals:  [.neon],
            trails: [.raybeam],
            floors: [.gridCity],
            pits:   [.space],
            music:  [.synthwave],
            boundaries: [.circuit]
        ),
        CosmeticBundle(
            id:             "clockwork",
            displayName:    "Clockwork",
            tagline:        "Every tooth in its place.",
            contentSummary: "Clockwork ball · Eclipse goal · Smoke trail · Brass Works floor · Canyon pit · Classical music · Brass boundary",
            balls:  [.clockwork],
            goals:  [.eclipse],
            trails: [.smoke],
            floors: [.brass],
            pits:   [.canyon],
            music:  [.classical],
            boundaries: [.brass]
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
    /// A computer opponent's look: skin, trail and name.  Computer opponents
    /// have NO level — the level badge is for real players only.
    struct Look {
        let skin: BallSkin
        let trail: TrailColor
        let name: String
    }

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

// MARK: - Color ⇄ hex (persists the player's primary color)

extension Color {
    /// "#RRGGBB" → opaque Color.  nil on malformed input.
    init?(hexRGB: String) {
        var s = hexRGB.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >>  8) & 0xFF) / 255,
                  blue:  Double( v        & 0xFF) / 255,
                  opacity: 1)
    }

    /// Resolve to an opaque "#RRGGBB" string.
    var hexRGB: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp = { (x: CGFloat) in Int((max(0, min(1, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

/// The floating bottom-left "home" button used by the solo minigames — the same
/// affordance the climb / Zen Garden show in BallGameView, so leaving a game is
/// consistent everywhere.  Always tappable; pops back to the home screen.
struct HomeQuitButton: View {
    @EnvironmentObject private var nav: Navigator

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Button { nav.goHome() } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(white: 0.38))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(Color(white: 1.0, opacity: 0.85))
                                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                        )
                }
                .accessibilityLabel("Quit to home screen")
                Spacer()
            }
            .padding(.leading, 22)
            .padding(.bottom, 16)
        }
        .allowsHitTesting(true)
    }
}

/// Shared pre-game difficulty selector for the competitive minigames: three
/// buttons, Easy / Normal / Hard, and nothing else.  Custom Buttons (not a
/// segmented Picker) so an arena's tap-to-start gesture can't steal the
/// selection.  Binds straight to the remembered `minigameDifficulty`.
struct MinigameDifficultyPicker: View {
    @Binding var selection: MinigameDifficulty
    var accent: Color = Color(red: 1.0, green: 0.82, blue: 0.30)

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MinigameDifficulty.allCases) { d in
                StartPanelOptionButton(title: d.displayName,
                                       selected: selection == d,
                                       accent: accent) { selection = d }
            }
        }
    }
}

/// One option button in the start panel's row (Easy, Normal, Hard, Solo…).
struct StartPanelOptionButton: View {
    let title: String
    let selected: Bool
    var accent: Color = Color(red: 1.0, green: 0.82, blue: 0.30)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? .black : Color(white: 0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? accent : Color(white: 0.20)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// ===========================================================================
// CompetitiveStartPanel — the start screen of every competitive minigame.
//
// A compact panel pinned near the BOTTOM of the screen, so the arena, the
// opponents and the player's own marble stay visible above it (pair it with
// `StartSpotRing` at the player's position).  It holds the game's title, a
// few short bullets, the option row (Easy / Normal / Hard, optionally a
// leading "Solo"), any extra controls the game needs (`accessory`, e.g.
// Marble Cup's 1 v 1 / 2 v 2), and "Tap anywhere to start".
//
// It stays up as long as the player wants.  Tapping an option only changes
// the option; tapping anywhere else on the panel calls `onStart` (each game
// also starts on a tap on the arena).  Usage:
//
//     CompetitiveStartPanel(title: "Paint Ball", icon: "paintbrush.pointed.fill",
//                           bullets: ["Tilt to roll", "Paint the most floor in 60 s"],
//                           difficulty: $gameState.minigameDifficulty,
//                           onStart: beginRound)
//
// A game with a Solo mode (Snacky) passes `solo: $isSolo`: a "Solo" option
// then leads the row, and choosing a difficulty turns Solo off.
// ===========================================================================
struct CompetitiveStartPanel<Accessory: View>: View {
    let title: String
    var icon: String = "flag.checkered"
    var tint: Color = .white
    let bullets: [String]
    @Binding var difficulty: MinigameDifficulty
    /// When set, a leading "Solo" option is shown and bound to this.
    var solo: Binding<Bool>? = nil
    /// Hide the option row (e.g. Sumo rounds 2 and 3: difficulty is locked).
    var showsOptions: Bool = true
    var startLabel: String = "Tap anywhere to start"
    let onStart: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    private let accent = Color(red: 1.0, green: 0.82, blue: 0.30)

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            panel
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(bullets, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•").foregroundStyle(accent)
                        Text(line).foregroundStyle(Color(white: 0.85))
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }
            .accessibilityElement(children: .combine)

            accessory()

            if showsOptions {
                HStack(spacing: 8) {
                    if let solo {
                        StartPanelOptionButton(title: "Solo", selected: solo.wrappedValue,
                                               accent: accent) { solo.wrappedValue = true }
                    }
                    ForEach(MinigameDifficulty.allCases) { d in
                        StartPanelOptionButton(title: d.displayName,
                                               selected: difficulty == d && solo?.wrappedValue != true,
                                               accent: accent) {
                            difficulty = d
                            solo?.wrappedValue = false
                        }
                    }
                }
            }

            Text(startLabel)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.72))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(white: 0.25), lineWidth: 0.8)))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { onStart() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Starts the game.")
    }
}

extension CompetitiveStartPanel where Accessory == EmptyView {
    init(title: String, icon: String = "flag.checkered", tint: Color = .white,
         bullets: [String], difficulty: Binding<MinigameDifficulty>,
         solo: Binding<Bool>? = nil, showsOptions: Bool = true,
         startLabel: String = "Tap anywhere to start",
         onStart: @escaping () -> Void) {
        self.init(title: title, icon: icon, tint: tint, bullets: bullets,
                  difficulty: difficulty, solo: solo, showsOptions: showsOptions,
                  startLabel: startLabel, onStart: onStart,
                  accessory: { EmptyView() })
    }
}

/// A soft pulsing ring around the player's marble before a match starts, so
/// the player can find their starting spot.  Still with Reduce Motion.
/// Place it at the marble's position in the arena: `.position(playerPos)`.
struct StartSpotRing: View {
    var color: Color = .white
    var diameter: CGFloat = 58

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.85), lineWidth: 2.5)
            .frame(width: diameter, height: diameter)
            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.18 : 0.92))
            .opacity(reduceMotion ? 0.9 : (pulse ? 0.35 : 0.95))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

struct RivalNameTag: View {
    let label: String
    let color: Color
    let isPlayer: Bool
    var isLeader: Bool = false      // draws a crown above the tag (current leader)
    /// The player's own Adventure level, shown as part of the name.  nil = no
    /// badge (always nil for computer opponents).
    var level: Int? = nil
    var body: some View {
        VStack(spacing: 1) {
            if isLeader {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.30))
                    .shadow(color: .black.opacity(0.55), radius: 1, y: 0.5)
            }
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: isPlayer ? 11 : 10,
                                  weight: isPlayer ? .heavy : .bold, design: .rounded))
                    .foregroundStyle(isPlayer ? Color.white : color)
                if let level { LevelBadge(level: level, tiny: true, tint: isPlayer ? color : nil) }
            }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(isPlayer ? 0.6 : 0.42)))
                .overlay(Capsule().stroke(color.opacity(0.95), lineWidth: isPlayer ? 1.5 : 1))
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.map { "\(label), level \(max(1, $0))" } ?? label)
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
/// Rarity badge: a faceted gem in the rarity's metallic colour (silver / gold /
/// amethyst / diamond, prismatic for Iconic), sized for a card's top-right
/// corner.  Colour carries the rarity; `label` rides along for VoiceOver.
struct TierBadge: View {
    let label: String
    let gemColors: [Color]
    var shows: Bool = true
    var compact: Bool = false

    /// Item-aware: the Iconic prismatic gem for un-sellable specials, else the
    /// metallic tier gem (silver / gold / amethyst / diamond).
    init<Item: CosmeticItem>(item: Item, compact: Bool = false) {
        self.init(label: item.rarityLabel, gemColors: item.rarityGemColors,
                  shows: item.showsRarityBadge, compact: compact)
    }
    /// Plain tier gem (kept for callers that only have a `CosmeticTier`).
    init(tier: CosmeticTier, compact: Bool = false) {
        self.init(label: tier.label, gemColors: tier.gemColors,
                  shows: tier.showsBadge, compact: compact)
    }
    /// Bundle rarity gem.
    init(rarity: BundleRarity, compact: Bool = false) {
        self.init(label: rarity.label, gemColors: rarity.gemColors, compact: compact)
    }
    init(label: String, gemColors: [Color], shows: Bool = true, compact: Bool = false) {
        self.label = label; self.gemColors = gemColors; self.shows = shows; self.compact = compact
    }

    var body: some View {
        if shows {
            Image(systemName: "diamond.fill")
                .font(.system(size: compact ? 12 : 14, weight: .black))
                .foregroundStyle(
                    LinearGradient(colors: gemColors,
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(4)
                .background(Circle().fill(Color.black.opacity(0.42)))
                .overlay(Circle().stroke((gemColors.first ?? .white).opacity(0.70), lineWidth: 0.8))
                .shadow(color: (gemColors.first ?? .white).opacity(0.55), radius: 2.5)
                .accessibilityLabel("\(label) rarity")
        }
    }
}

// ===========================================================================
// Trail marks — ONE system for every trail, everywhere a trail is drawn
// (gameplay, Home, replays, Shop tiles, try-on, the Locker and the
// minigames' racer trails).
//
//   • A mark is laid at the ball's position at that moment, stamped with the
//     time it was laid.  It never moves with the ball afterward.
//   • Marks are laid at a fixed spacing along the path (`spacing`), so every
//     trail has the same density whatever the ball's speed.  A fast step lays
//     several marks along the straight line it covered, with interpolated
//     laid times.
//   • Marks expire by AGE (`lifetime`): each one fades out where it was laid,
//     on its own clock — even while the ball rests.
//   • A hard cap (`cap`) bounds memory and draw cost.  Past it (only above
//     ~465 pt/s) the oldest marks drop early.
//
// Every renderer below draws from the marks alone and keys each mark's look
// to its own laid time (`trailSeed`) and age — never to its index counted
// back from the ball.  That index-from-the-head keying (plus a fixed-length
// buffer) is what made most trails look towed: a mark's width, brightness and
// decorations were recomputed from "how far behind the ball am I" every frame,
// so the whole effect slid along with the ball.
// ===========================================================================
struct TrailMarks: Equatable {
    /// Distance between consecutive marks, in points.
    static let spacing: CGFloat = 4
    /// How long a mark lives, in seconds (shared by every trail).
    static let lifetime: Double = 1.1
    /// Most marks alive at once: a full `lifetime` of path at up to ~465 pt/s.
    static let cap = 128
    /// Most marks one step may lay, so a respawn jump can't flood the buffer.
    static let maxPerStep = 16
    /// Racer trails in the minigames are shorter, so four marbles don't
    /// smear the board.  Same laying rule, same fade.
    static let racerLifetime: Double = 0.45
    static let racerCap = 48

    /// Mark positions, oldest first (the newest sits at the ball).
    private(set) var points: [CGPoint] = []
    /// When each mark was laid (same clock as `now`), parallel to `points`.
    private(set) var times: [Double] = []

    init() {}

    var isEmpty: Bool { points.isEmpty }
    var count: Int { points.count }

    mutating func clear() {
        points.removeAll(keepingCapacity: true)
        times.removeAll(keepingCapacity: true)
    }

    /// Record the ball at `p` at time `now` (call every tick, moving or not):
    /// lays marks every `spacing` points from the last mark toward `p`, then
    /// drops marks older than `lifetime` and any beyond `cap`.
    mutating func add(_ p: CGPoint, at now: Double,
                      lifetime: Double = TrailMarks.lifetime,
                      cap: Int = TrailMarks.cap) {
        if let last = points.last, let lastT = times.last {
            let dx: CGFloat = p.x - last.x
            let dy: CGFloat = p.y - last.y
            let d: CGFloat = (dx * dx + dy * dy).squareRoot()
            if d.isFinite && d >= Self.spacing {
                let whole: Int = Int(d / Self.spacing)
                let k: Int = min(Self.maxPerStep, whole)
                // Whole spacings normally; spread evenly to `p` if capped.
                let step: CGFloat = whole > Self.maxPerStep ? d / CGFloat(k) : Self.spacing
                for j in 1...k {
                    let f: CGFloat = step * CGFloat(j) / d
                    points.append(CGPoint(x: last.x + dx * f, y: last.y + dy * f))
                    times.append(lastT + (now - lastT) * Double(f))
                }
            }
        } else {
            points.append(p)
            times.append(now)
        }
        expire(now: now, lifetime: lifetime, cap: cap)
    }

    /// Drop marks older than `lifetime`, then any beyond `cap` (oldest first).
    mutating func expire(now: Double, lifetime: Double = TrailMarks.lifetime,
                         cap: Int = TrailMarks.cap) {
        var drop = 0
        while drop < times.count, now - times[drop] > lifetime { drop += 1 }
        if times.count - drop > cap { drop = times.count - cap }
        if drop > 0 {
            points.removeFirst(drop)
            times.removeFirst(drop)
        }
    }

    /// Marks laid by a ball that followed `samples` (oldest first), as of time
    /// `now`.  Used by replays: feeding the whole clip from its start keeps
    /// every mark exactly where the live game would have laid it.
    static func laid(along samples: [(t: Double, p: CGPoint)], now: Double,
                     lifetime: Double = TrailMarks.lifetime) -> TrailMarks {
        var m = TrailMarks()
        for s in samples where s.t <= now { m.add(s.p, at: s.t, lifetime: lifetime) }
        m.expire(now: now, lifetime: lifetime)
        return m
    }
}

// ---------------------------------------------------------------------------
// Competitive trails — the keystone "opponents' trails are visible" streak,
// one implementation across every competitive view.  Same laying rule as the
// rich trail (marks stay where laid, fade on a timer), drawn as a simple line.
// ---------------------------------------------------------------------------

/// Lay one racer's marks for this tick (call once per racer, every tick).
func recordTrail<K: Hashable>(_ trails: inout [K: TrailMarks], _ key: K, _ pos: CGPoint,
                              now: Double = Date().timeIntervalSinceReferenceDate) {
    // `default:` mutates the stored value in place — no copy of its buffers.
    trails[key, default: TrailMarks()].add(pos, at: now,
                                           lifetime: TrailMarks.racerLifetime,
                                           cap: TrailMarks.racerCap)
}

/// Draw racer trails into a Canvas `ctx`.  Each mark's segment fades by its
/// own age where it was laid.  `.rainbow` colors each mark by when it was
/// laid, so a mark keeps its hue; `.none` and <2-mark trails are skipped.
/// `toScreen` maps stored positions to the canvas (Roll Up stores world
/// coordinates and scrolls).
func drawTrails(_ ctx: GraphicsContext,
                _ entries: [(marks: TrailMarks, trail: TrailColor)],
                now: Double = Date().timeIntervalSinceReferenceDate,
                lineWidth: CGFloat = 5,
                toScreen: (CGPoint) -> CGPoint = { $0 }) {
    for e in entries {
        let pts = e.marks.points, times = e.marks.times
        guard pts.count >= 2, times.count == pts.count, e.trail != .none else { continue }
        let rainbow = e.trail == .rainbow
        let solid = e.trail.color
        for i in 1..<pts.count {
            let fresh: Double = max(0, 1 - (now - times[i - 1]) / TrailMarks.racerLifetime)
            guard fresh > 0.01 else { continue }
            let segColor: Color = rainbow
                ? Color(hue: trailHue(times[i]), saturation: 1, brightness: 1)
                : solid
            var path = Path(); path.move(to: toScreen(pts[i - 1])); path.addLine(to: toScreen(pts[i]))
            ctx.stroke(path, with: .color(segColor.opacity(0.65 * fresh)),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Stable 0…1 pseudo-random value for a mark, from the time it was laid.
/// Laid times only ever increase, so this is a per-mark identity that never
/// changes as the buffer shifts — and unlike a position it doesn't change
/// when a replay camera moves.
func trailSeed(_ laidAt: Double) -> Double {
    let a: Double = laidAt * 61.7
    let v: Double = sin((a - floor(a)) * 12.9898 + floor(a).truncatingRemainder(dividingBy: 997.0) * 0.7853) * 43758.5453
    return v - floor(v)
}

/// A mark's rainbow hue, from when it was laid: neighbours differ a little,
/// so the path reads as a spectrum, and a mark never changes colour.
func trailHue(_ laidAt: Double) -> Double {
    let v: Double = laidAt * 0.55
    return v - floor(v)
}

// ===========================================================================
// Rich per-trail rendering — the player's equipped trail (gameplay, Home,
// replays, the Shop).  Every effect lives at a mark: it appears where the
// ball was, may change gently IN PLACE (smoke thins and rises, sparks rise,
// bubbles pop, flames flicker) and fades on the mark's own clock.  Under
// Reduce Motion the marks still appear and fade, with no extra movement.
// ===========================================================================

/// What a renderer needs about the current marks.
private struct TrailFrame {
    let pts: [CGPoint]
    let laid: [Double]
    let now: Double
    let life: Double
    /// 1 normally, 0 under Reduce Motion — scales every in-place movement.
    let m: Double
    let bw: CGFloat

    var n: Int { pts.count }
    /// Time used for in-place flicker/sway; frozen under Reduce Motion.
    var tm: Double { now * m }
    func age(_ i: Int) -> Double { max(0, now - laid[i]) }
    /// 0 just laid → 1 expired.
    func f(_ i: Int) -> Double { min(1, age(i) / life) }
    /// 1 just laid → 0 expired.
    func fresh(_ i: Int) -> Double { 1 - f(i) }
    func seed(_ i: Int) -> Double { trailSeed(laid[i]) }
}

/// Draw the equipped trail from its marks.
///
/// `points`/`times` are the marks (oldest first, see `TrailMarks`); `t` is
/// "now" on the same clock as `times`.  When `times` is missing the marks are
/// spread evenly over one lifetime, newest at the head.
func drawRichTrail(_ ctx: GraphicsContext, points pts: [CGPoint],
                   trail: TrailColor, t: Double, baseWidth: CGFloat = 6,
                   times: [Double]? = nil,
                   lifetime: Double = TrailMarks.lifetime,
                   reduceMotion: Bool = false) {
    guard pts.count >= 2, trail != .none else { return }
    let laid: [Double]
    if let times, times.count == pts.count {
        laid = times
    } else {
        let n = pts.count
        let span = lifetime * 0.95 / Double(n - 1)
        laid = (0..<n).map { i -> Double in
            t - Double(n - 1 - i) * span
        }
    }
    let fr = TrailFrame(pts: pts, laid: laid, now: t, life: lifetime,
                        m: reduceMotion ? 0 : 1, bw: baseWidth)
    switch trail {
    case .snake:           trailSnake(ctx, fr)
    case .cometTrail:      trailComet(ctx, fr)
    case .ice:             trailIce(ctx, fr)
    case .fire:            trailFire(ctx, fr)
    case .ink:             trailInk(ctx, fr)
    case .smoke:           trailMist(ctx, fr, base: trail.color)
    case .stardust:        trailStardust(ctx, fr)
    case .air:             trailAir(ctx, fr)
    case .rainbow:         trailRainbow(ctx, fr)
    case .classic:         trailClassic(ctx, fr)
    case .graphite:        trailGraphite(ctx, fr)
    case .roseTrail:       trailRose(ctx, fr)
    case .moneyRoll:       trailMoney(ctx, fr)
    case .aurora:          trailAurora(ctx, fr)
    case .forest:          trailForest(ctx, fr)
    case .bubblegum:       trailBubblegum(ctx, fr)
    case .ember:           trailEmber(ctx, fr)
    case .wildfire:        trailWildfire(ctx, fr)
    case .splash:          trailSplash(ctx, fr)
    case .squall:          trailSquall(ctx, fr)
    case .zest:            trailZest(ctx, fr)
    // — Quality round: Champion / Ancient Temple —
    case .victoryLap:      trailVictoryLap(ctx, fr)
    case .glyphs:          trailGlyphs(ctx, fr)
    // — Standard audit: Nightclub / Golf / Ocean —
    case .danceSteps:      trailDanceSteps(ctx, fr)
    case .dewLine:         trailDewLine(ctx, fr)
    case .wake:            trailWake(ctx, fr)
    default:
        trailTapered(ctx, fr, width: baseWidth, color: trail.color,
                     glow: trail == .raybeam || trail == .gilded)
    }
}

/// The plain line: each segment narrows and fades with the age of its older
/// mark, so the line thins away from the tail where it was laid.  Used by the
/// simple colour trails (Sky, Gilded, Raybeam) and under several rich ones.
private func trailTapered(_ ctx: GraphicsContext, _ fr: TrailFrame,
                          width: CGFloat, color: Color, glow: Bool) {
    var ctx = ctx
    for i in 1..<fr.n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        let w: CGFloat = width * CGFloat(0.35 + 0.65 * k)
        var p = Path(); p.move(to: fr.pts[i - 1]); p.addLine(to: fr.pts[i])
        if glow {
            ctx.blendMode = .plusLighter
            ctx.stroke(p, with: .color(color.opacity(0.16 * k)),
                       style: StrokeStyle(lineWidth: w * 2.4, lineCap: .round))
            ctx.blendMode = .normal
        }
        ctx.stroke(p, with: .color(color.opacity(0.82 * k)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
}

/// Aurora — a luminous ribbon, teal-green through cyan to violet.  Each mark's
/// hue comes from when it was laid and shimmers slowly in place; an additive
/// glow and a bright core on the freshest stretch.
private func trailAurora(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    var ctx = ctx
    ctx.blendMode = .plusLighter
    for i in 1..<fr.n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        let w: CGFloat = fr.bw * CGFloat(0.35 + 0.90 * k)
        let phase: Double = fr.laid[i] * 3.0 + fr.tm * 0.8
        let hue: Double = 0.42 + 0.32 * (0.5 + 0.5 * sin(phase))
        let col = Color(hue: hue, saturation: 0.80, brightness: 1.0)
        var p = Path(); p.move(to: fr.pts[i - 1]); p.addLine(to: fr.pts[i])
        ctx.stroke(p, with: .color(col.opacity(0.16 * k)),
                   style: StrokeStyle(lineWidth: w * 2.8, lineCap: .round))
        ctx.stroke(p, with: .color(col.opacity(0.83 * k)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        if k > 0.55 {
            ctx.stroke(p, with: .color(Color(red: 0.85, green: 1.0, blue: 0.95).opacity(0.5 * k)),
                       style: StrokeStyle(lineWidth: w * 0.4, lineCap: .round))
        }
    }
    ctx.blendMode = .normal
}

/// Snake — a scaled body laid along the path, head at the ball.  Each body
/// segment narrows and fades with its own age where it was laid, so the snake
/// sheds its tail behind it instead of being dragged; coins lengthen its life
/// (the caller passes a longer `lifetime`).
private func trailSnake(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    let dark = Color(red: 0.09, green: 0.38, blue: 0.15)
    let mid  = Color(red: 0.18, green: 0.64, blue: 0.24)
    let lite = Color(red: 0.50, green: 0.90, blue: 0.42)
    let headW: CGFloat = fr.bw * 2.0
    let n = fr.n
    for i in 1..<n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        let w: CGFloat = headW * CGFloat(0.30 + 0.70 * k)
        let a = fr.pts[i - 1], b = fr.pts[i]
        var p = Path(); p.move(to: a); p.addLine(to: b)
        ctx.stroke(p, with: .color(dark.opacity(k)), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(mid.opacity(k)),  style: StrokeStyle(lineWidth: w * 0.72, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(lite.opacity(0.5 * k)), style: StrokeStyle(lineWidth: w * 0.24, lineCap: .round, lineJoin: .round))
        // Scale chevron across the body at this mark.
        let dx: CGFloat = b.x - a.x, dy: CGFloat = b.y - a.y
        let len: CGFloat = max(0.001, hypot(dx, dy))
        let ux: CGFloat = dx / len, uy: CGFloat = dy / len
        let px: CGFloat = -uy, py: CGFloat = ux
        let h: CGFloat = w * 0.42
        var chev = Path()
        chev.move(to: CGPoint(x: b.x + px * h - ux * h, y: b.y + py * h - uy * h))
        chev.addLine(to: b)
        chev.addLine(to: CGPoint(x: b.x - px * h - ux * h, y: b.y - py * h - uy * h))
        ctx.stroke(chev, with: .color(dark.opacity(0.45 * k)),
                   style: StrokeStyle(lineWidth: max(0.6, w * 0.09), lineCap: .round, lineJoin: .round))
    }
    // Head — on the newest mark (the ball); fades away if the ball rests so
    // long that even the newest mark expires.
    let hk: Double = fr.fresh(n - 1)
    guard hk > 0.05 else { return }
    let head = fr.pts[n - 1], prev = fr.pts[n - 2]
    let hdx: CGFloat = head.x - prev.x, hdy: CGFloat = head.y - prev.y
    let hlen: CGFloat = max(0.001, hypot(hdx, hdy))
    let ux: CGFloat = hdx / hlen, uy: CGFloat = hdy / hlen
    let ex: CGFloat = -uy, ey: CGFloat = ux
    let hr: CGFloat = headW * 0.62
    let headRect = CGRect(x: head.x - hr, y: head.y - hr, width: hr * 2, height: hr * 2)
    ctx.fill(Path(ellipseIn: headRect), with: .color(mid.opacity(hk)))
    ctx.fill(Path(ellipseIn: headRect),
        with: .radialGradient(Gradient(colors: [lite.opacity(0.6 * hk), .clear]),
            center: CGPoint(x: head.x - hr * 0.3, y: head.y - hr * 0.3), startRadius: 0, endRadius: hr))
    let er: CGFloat = hr * 0.22
    for s in [CGFloat(1), -1] {
        let cxp: CGFloat = head.x + ux * hr * 0.2 + ex * hr * 0.45 * s
        let cyp: CGFloat = head.y + uy * hr * 0.2 + ey * hr * 0.45 * s
        ctx.fill(Path(ellipseIn: CGRect(x: cxp - er, y: cyp - er, width: er * 2, height: er * 2)),
                 with: .color(Color.white.opacity(hk)))
        ctx.fill(Path(ellipseIn: CGRect(x: cxp - er * 0.5, y: cyp - er * 0.5, width: er, height: er)),
                 with: .color(Color.black.opacity(hk)))
    }
    var tongue = Path()
    tongue.move(to: CGPoint(x: head.x + ux * hr, y: head.y + uy * hr))
    tongue.addLine(to: CGPoint(x: head.x + ux * hr * 2.1, y: head.y + uy * hr * 2.1))
    ctx.stroke(tongue, with: .color(Color(red: 0.9, green: 0.12, blue: 0.30).opacity(hk)),
               style: StrokeStyle(lineWidth: max(0.8, hr * 0.16), lineCap: .round))
}

/// Comet — each mark burns bright yellow-white when laid, cools through orange
/// to deep red, then turns into a grey smoke puff that swells, rises a little
/// and thins away where it was laid.
private func trailComet(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    var ctx = ctx
    // Smoke: marks past 30 % of their life, every other mark (by seed).
    for i in 0..<fr.n {
        let f: Double = fr.f(i)
        guard f > 0.30, f < 1 else { continue }
        let seed: Double = fr.seed(i)
        guard seed < 0.55 else { continue }
        let s: Double = (f - 0.30) / 0.70                       // 0 → 1 across the smoke phase
        let env: Double = min(1, s / 0.15) * (1 - s)
        guard env > 0.02 else { continue }
        let p = fr.pts[i]
        let pr: CGFloat = fr.bw * CGFloat(1.6 + 2.4 * s * fr.m)
        let lift: CGFloat = CGFloat(s * fr.m) * fr.bw * 1.4
        let drift: CGFloat = CGFloat(sin(seed * 6.283 + fr.tm * 1.2) * fr.m * s) * fr.bw * 0.5
        let c = CGPoint(x: p.x + drift, y: p.y - lift)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2)),
            with: .radialGradient(Gradient(colors: [Color(white: 0.55).opacity(0.22 * env), .clear]),
                center: c, startRadius: 0, endRadius: pr))
    }
    // Fire: the young half of each mark's life.
    ctx.blendMode = .plusLighter
    for i in 1..<fr.n {
        let f: Double = fr.f(i - 1)
        guard f < 0.5 else { continue }
        let k: Double = 1 - f / 0.5                              // 1 fresh → 0 cooled
        let col: Color = k > 0.7 ? Color(red: 1, green: 0.96, blue: 0.65)
                : (k > 0.4 ? Color(red: 1, green: 0.55, blue: 0.12)
                           : Color(red: 0.82, green: 0.12, blue: 0.05))
        let w: CGFloat = fr.bw * CGFloat(0.5 + 1.7 * k)
        var p = Path(); p.move(to: fr.pts[i - 1]); p.addLine(to: fr.pts[i])
        ctx.stroke(p, with: .color(col.opacity(0.25 + 0.6 * k)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
}

/// Ice — a faint icy cut with snow piles heaped on each side.  Each pile heaps
/// up where it was laid, settles gently in place, then melts away.
private func trailIce(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    for i in 1..<fr.n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        var p = Path(); p.move(to: fr.pts[i - 1]); p.addLine(to: fr.pts[i])
        ctx.stroke(p, with: .color(Color(red: 0.62, green: 0.84, blue: 1.0).opacity(0.22 * k)),
                   style: StrokeStyle(lineWidth: fr.bw * 0.7, lineCap: .round, lineJoin: .round))
        // A thin bright skate-cut down the middle of the frozen track.
        ctx.stroke(p, with: .color(Color.white.opacity(0.55 * k)),
                   style: StrokeStyle(lineWidth: max(0.8, fr.bw * 0.16), lineCap: .round, lineJoin: .round))
    }
    // Frost flakes: a small six-armed crystal beside about one mark in five.
    // Each sits where it was laid, glints slowly in place and melts with age.
    for i in 1..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed >= 0.60, seed < 0.80 else { continue }
        let k: Double = fr.fresh(i)
        guard k > 0.03 else { continue }
        let s2: Double = (seed * 13.7).truncatingRemainder(dividingBy: 1.0)
        let dx: CGFloat = fr.pts[i].x - fr.pts[i - 1].x, dy: CGFloat = fr.pts[i].y - fr.pts[i - 1].y
        let len: CGFloat = max(0.001, hypot(dx, dy))
        let side: CGFloat = s2 < 0.5 ? 1 : -1
        let off: CGFloat = fr.bw * CGFloat(1.5 + 0.9 * s2)
        let c = CGPoint(x: fr.pts[i].x - dy / len * off * side, y: fr.pts[i].y + dx / len * off * side)
        let glint: Double = 0.75 + 0.25 * sin(fr.tm * 1.6 + seed * 40.0)
        let fr6: CGFloat = fr.bw * CGFloat(0.55 + 0.45 * s2) * CGFloat(0.5 + 0.5 * k)
        var flake = Path()
        for arm in 0..<6 {
            let a: Double = Double(arm) / 6.0 * 2.0 * Double.pi + s2 * 1.0
            let ex: CGFloat = c.x + CGFloat(cos(a)) * fr6, ey: CGFloat = c.y + CGFloat(sin(a)) * fr6
            flake.move(to: c)
            flake.addLine(to: CGPoint(x: ex, y: ey))
            // Two short barbs two-thirds of the way out.
            let mx: CGFloat = c.x + CGFloat(cos(a)) * fr6 * 0.62, my: CGFloat = c.y + CGFloat(sin(a)) * fr6 * 0.62
            for sgn in [0.55, -0.55] {
                flake.move(to: CGPoint(x: mx, y: my))
                flake.addLine(to: CGPoint(x: mx + CGFloat(cos(a + sgn)) * fr6 * 0.30,
                                          y: my + CGFloat(sin(a + sgn)) * fr6 * 0.30))
            }
        }
        ctx.stroke(flake, with: .color(Color.white.opacity(0.90 * k * glint)),
                   style: StrokeStyle(lineWidth: max(0.6, fr.bw * 0.11), lineCap: .round))
    }
    for i in 1..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.6 else { continue }                       // a pile at about 3 marks in 5
        let age: Double = fr.age(i)
        let life: Double = fr.f(i)
        guard life < 1 else { continue }
        let rise: Double = fr.m > 0 ? min(1.0, age / 0.10) : 1.0
        let melt: Double = life < 0.6 ? 1.0 : 1.0 - (life - 0.6) / 0.4
        let env: Double = rise * max(0, melt)
        guard env > 0.02 else { continue }
        let dx: CGFloat = fr.pts[i].x - fr.pts[i - 1].x, dy: CGFloat = fr.pts[i].y - fr.pts[i - 1].y
        let len: CGFloat = max(0.001, hypot(dx, dy))
        let px: CGFloat = -dy / len, py: CGFloat = dx / len
        let baseOff: CGFloat = fr.bw * 0.9
        for side in [CGFloat(1), -1] {
            let s2: Double = side > 0 ? seed : (seed * 7.3 + 0.37).truncatingRemainder(dividingBy: 1.0)
            let settle: Double = 0.92 + 0.08 * sin(fr.tm * 2.0 + s2 * 6.283) * fr.m
            let pileR: CGFloat = fr.bw * (0.50 + 0.70 * CGFloat(s2)) * CGFloat(env * settle)
            if pileR < 0.6 { continue }
            let cx: CGFloat = fr.pts[i].x + px * baseOff * side
            let cy: CGFloat = fr.pts[i].y + py * baseOff * side
            let op: Double = 0.85 * env
            for k in 0..<3 {
                let kk = Double(k)
                let bx: CGFloat = cx + CGFloat(cos(kk * 2.1 + s2 * 3)) * pileR * 0.6
                let by: CGFloat = cy + CGFloat(sin(kk * 2.1 + s2 * 3)) * pileR * 0.6 - pileR * 0.2
                let br: CGFloat = pileR * CGFloat(0.55 + 0.45 * (kk / 3))
                ctx.fill(Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2)),
                    with: .radialGradient(Gradient(colors: [.white.opacity(op),
                                                            Color(red: 0.86, green: 0.93, blue: 1.0).opacity(0)]),
                        center: CGPoint(x: bx - br * 0.3, y: by - br * 0.3), startRadius: 0, endRadius: br))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: cx - pileR * 0.8, y: cy + pileR * 0.3, width: pileR * 1.6, height: pileR * 0.7)),
                with: .color(Color(red: 0.5, green: 0.66, blue: 0.88).opacity(0.12 * env)))
        }
    }
}

/// Classic — the default.  A very subtle shallow indent pressed into the floor:
/// a soft low-alpha dark groove with a faint light lip on one side (like an
/// emboss), no hue of its own, so it reads on light and dark floors alike.
/// Marks stay where they were laid and only fade with age (no motion).
private func trailClassic(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    for i in 1..<fr.n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        let a: CGPoint = fr.pts[i - 1], b: CGPoint = fr.pts[i]
        let dx: CGFloat = b.x - a.x, dy: CGFloat = b.y - a.y
        let len: CGFloat = max(0.001, hypot(dx, dy))
        // Unit normal; the light lip sits on the lower-right side of the groove
        // (light from the top-left, as on the ball's highlight).
        var nx: CGFloat = -dy / len, ny: CGFloat = dx / len
        if nx + ny < 0 { nx = -nx; ny = -ny }
        let w: CGFloat = fr.bw * CGFloat(0.55 + 0.45 * k)
        var groove = Path(); groove.move(to: a); groove.addLine(to: b)
        ctx.stroke(groove, with: .color(Color.black.opacity(0.20 * k)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round))
        let off: CGFloat = w * 0.45
        var lip = Path()
        lip.move(to: CGPoint(x: a.x + nx * off, y: a.y + ny * off))
        lip.addLine(to: CGPoint(x: b.x + nx * off, y: b.y + ny * off))
        ctx.stroke(lip, with: .color(Color.white.opacity(0.16 * k)),
                   style: StrokeStyle(lineWidth: max(0.6, w * 0.22), lineCap: .round))
    }
}

/// Graphite — pencil on paper: a faint base line broken up by short, uneven
/// strokes.  The jitter comes from each mark's own seed, so a stroke never
/// shifts; it simply fades where it was drawn.
private func trailGraphite(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    let lead = Color(red: 0.20, green: 0.20, blue: 0.22)
    for i in 1..<fr.n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        let a = fr.pts[i - 1], b = fr.pts[i]
        var base = Path(); base.move(to: a); base.addLine(to: b)
        ctx.stroke(base, with: .color(lead.opacity(0.40 * k)),
                   style: StrokeStyle(lineWidth: fr.bw * 0.6, lineCap: .round))
        let dx: CGFloat = b.x - a.x, dy: CGFloat = b.y - a.y
        let len: CGFloat = max(0.001, hypot(dx, dy))
        let ux: CGFloat = dx / len, uy: CGFloat = dy / len
        let px: CGFloat = -uy, py: CGFloat = ux
        let seed: Double = fr.seed(i) * 12.9898
        for s in 0..<3 {
            let f: Double = (Double(s) + 0.5) / 3.0
            let jit: CGFloat = CGFloat((seed * Double(s + 1)).truncatingRemainder(dividingBy: 1.0) - 0.5) * fr.bw * 0.7
            let mx: CGFloat = a.x + dx * CGFloat(f) + px * jit
            let my: CGFloat = a.y + dy * CGFloat(f) + py * jit
            let l2: CGFloat = fr.bw * 0.55
            var mk = Path()
            mk.move(to: CGPoint(x: mx - ux * l2, y: my - uy * l2))
            mk.addLine(to: CGPoint(x: mx + ux * l2, y: my + uy * l2))
            let op: Double = 0.6 * k * (0.4 + 0.6 * (seed * Double(s + 3)).truncatingRemainder(dividingBy: 1.0))
            ctx.stroke(mk, with: .color(lead.opacity(op)),
                       style: StrokeStyle(lineWidth: max(0.5, fr.bw * 0.16), lineCap: .round))
        }
    }
}

/// Rose — petals dropped where the ball passed.  Each pops in, settles (falls
/// a little, sways, turns slowly) in place while it fades.  A faint stem fades
/// beneath them.
private func trailRose(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    let stem = Color(red: 0.42, green: 0.06, blue: 0.18)
    let petals = [Color(red: 0.85, green: 0.20, blue: 0.40),
                  Color(red: 0.95, green: 0.45, blue: 0.60),
                  Color(red: 0.62, green: 0.10, blue: 0.28)]
    for i in 1..<fr.n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        var p = Path(); p.move(to: fr.pts[i - 1]); p.addLine(to: fr.pts[i])
        ctx.stroke(p, with: .color(stem.opacity(0.22 * k)),
                   style: StrokeStyle(lineWidth: fr.bw * 0.5, lineCap: .round, lineJoin: .round))
    }
    for i in 0..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.45 else { continue }
        let age: Double = fr.age(i)
        let life: Double = fr.f(i)
        guard life < 1 else { continue }
        let rise: Double = fr.m > 0 ? min(1.0, age / 0.06) : 1.0
        let fade: Double = life < 0.55 ? 1.0 : 1.0 - (life - 0.55) / 0.45
        let env: Double = rise * max(0, fade)
        guard env > 0.02 else { continue }
        let r2: Double = (seed * 2.13 * 10).truncatingRemainder(dividingBy: 1.0)
        let r3: Double = (seed * 5.70 * 10).truncatingRemainder(dividingBy: 1.0)
        let side: CGFloat = r2 < 0.5 ? -1 : 1
        let scatter: CGFloat = fr.bw * (0.2 + 0.6 * CGFloat(r2))
        let sway: CGFloat = CGFloat(sin(fr.tm * 1.6 + seed * 6.283) * life * fr.m) * fr.bw * 0.22
        let fall: CGFloat = CGFloat(life * fr.m) * fr.bw * 0.55
        let p = fr.pts[i]
        let c = CGPoint(x: p.x + side * scatter + sway, y: p.y + fall)
        let sz: CGFloat = fr.bw * CGFloat(0.32 + 0.26 * r3) * (1.0 - 0.22 * CGFloat(life * fr.m))
        let rot: Double = seed * 6.283 + (fr.tm * 0.5 + life * 1.0) * fr.m
        let colorIdx: Int = min(2, max(0, Int(r3 * 3)))
        drawPetal(ctx, c, sz, rot, petals[colorIdx].opacity(0.82 * env))
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

/// Money Roll — a money-green streak shedding little dollar bills.  Each bill
/// pops in where it was laid, flutters and floats up a touch in place while
/// it fades.
private func trailMoney(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    let green = Color(red: 0.16, green: 0.55, blue: 0.30)
    for i in 1..<fr.n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        var p = Path(); p.move(to: fr.pts[i - 1]); p.addLine(to: fr.pts[i])
        ctx.stroke(p, with: .color(green.opacity(0.34 * k)),
                   style: StrokeStyle(lineWidth: fr.bw * 0.55, lineCap: .round, lineJoin: .round))
    }
    for i in 0..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.45 else { continue }
        let age: Double = fr.age(i)
        let life: Double = fr.f(i)
        guard life < 1 else { continue }
        let rise: Double = fr.m > 0 ? min(1.0, age / 0.05) : 1.0
        let fade: Double = life < 0.6 ? 1.0 : 1.0 - (life - 0.6) / 0.4
        let env: Double = rise * max(0, fade)
        guard env > 0.02 else { continue }
        let r2: Double = (seed * 2.13 * 10).truncatingRemainder(dividingBy: 1.0)
        let r3: Double = (seed * 5.70 * 10).truncatingRemainder(dividingBy: 1.0)
        let side: CGFloat = r2 < 0.5 ? -1 : 1
        let scatter: CGFloat = fr.bw * (0.2 + 0.7 * CGFloat(r2))
        let sway: CGFloat = CGFloat(sin(fr.tm * 3.0 + seed * 6.283) * (1 - life * 0.4) * fr.m) * fr.bw * 0.5
        let lift: CGFloat = -CGFloat(life * fr.m) * fr.bw * 0.6
        let p = fr.pts[i]
        let c = CGPoint(x: p.x + side * scatter + sway, y: p.y + lift)
        let sz: CGFloat = fr.bw * CGFloat(0.55 + 0.30 * r3)
        let rot: Double = seed * 6.283 + (fr.tm * (1.4 + r3) + Double(side) * life * 2.0) * fr.m
        drawBill(ctx, c, sz, rot, env)
    }
}

/// One little dollar bill — a green rounded card with a faint "portrait" oval
/// and corner pips, rotated by `rot`.
private func drawBill(_ ctx: GraphicsContext, _ c: CGPoint, _ s: CGFloat, _ rot: Double, _ env: Double) {
    var ctx = ctx
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: .radians(rot))
    let w = s * 2.0, h = s * 1.1
    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    let paper = Color(red: 0.40, green: 0.66, blue: 0.44)
    let ink   = Color(red: 0.10, green: 0.34, blue: 0.20)
    let bill  = Path(roundedRect: rect, cornerRadius: s * 0.12)
    ctx.fill(bill, with: .color(paper.opacity(0.92 * env)))
    ctx.stroke(bill, with: .color(ink.opacity(0.55 * env)), lineWidth: max(0.4, s * 0.07))
    let ow = w * 0.34, oh = h * 0.6
    ctx.stroke(Path(ellipseIn: CGRect(x: -ow / 2, y: -oh / 2, width: ow, height: oh)),
               with: .color(ink.opacity(0.5 * env)), lineWidth: max(0.3, s * 0.05))
    let pr = s * 0.12
    for sx in [CGFloat(-1), 1] {
        for sy in [CGFloat(-1), 1] {
            ctx.fill(Path(ellipseIn: CGRect(x: sx * (w / 2 - pr * 1.6) - pr,
                                            y: sy * (h / 2 - pr * 1.6) - pr,
                                            width: pr * 2, height: pr * 2)),
                     with: .color(ink.opacity(0.5 * env)))
        }
    }
}

/// Fire — little flames left along the path.  Each flares up where it was
/// laid, flickers in place, burns steady, then sinks and dies.
private func trailFire(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    var ctx = ctx
    ctx.blendMode = .plusLighter
    for i in 0..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.7 else { continue }                       // a flame at about 7 marks in 10
        let age: Double = fr.age(i)
        let life: Double = fr.f(i)
        guard life < 1 else { continue }
        let rise: Double = fr.m > 0 ? min(1.0, age / 0.05) : 1.0
        let env: Double = life < 0.55 ? 1.0 : 1.0 - (life - 0.55) / 0.45
        let intensity: Double = rise * max(0, env)
        guard intensity > 0.02 else { continue }
        let p = fr.pts[i]
        let flick: Double = 0.65 + 0.35 * sin(fr.tm * 11 + seed * 6.283)
        let grow: Double = 0.55 + 0.45 * intensity
        let h: CGFloat = fr.bw * CGFloat((1.5 + 1.2 * flick) * grow)
        let w: CGFloat = fr.bw * 0.85 * CGFloat(0.6 + 0.4 * intensity)
        let sway: CGFloat = CGFloat(sin(fr.tm * 7 + seed * 6.283) * fr.m) * w * 0.35
        let baseY: CGFloat = p.y + w * 0.5
        let gr: CGFloat = w * 1.5
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - gr, y: p.y - gr * 0.5, width: gr * 2, height: gr)),
            with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.5, blue: 0.15).opacity(0.22 * intensity), .clear]),
                center: p, startRadius: 0, endRadius: gr))
        var flame = Path()
        flame.move(to: CGPoint(x: p.x, y: baseY))
        flame.addQuadCurve(to: CGPoint(x: p.x + sway, y: p.y - h), control: CGPoint(x: p.x + w, y: p.y))
        flame.addQuadCurve(to: CGPoint(x: p.x, y: baseY), control: CGPoint(x: p.x - w + sway, y: p.y))
        ctx.fill(flame, with: .color(Color(red: 1, green: 0.42, blue: 0.05).opacity(0.55 * intensity)))
        var inner = Path()
        inner.move(to: CGPoint(x: p.x, y: p.y + w * 0.2))
        inner.addQuadCurve(to: CGPoint(x: p.x + sway * 0.7, y: p.y - h * 0.6), control: CGPoint(x: p.x + w * 0.5, y: p.y))
        inner.addQuadCurve(to: CGPoint(x: p.x, y: p.y + w * 0.2), control: CGPoint(x: p.x - w * 0.5 + sway * 0.7, y: p.y))
        ctx.fill(inner, with: .color(Color(red: 1, green: 0.9, blue: 0.45).opacity(0.6 * intensity)))
    }
}

/// Smoke — puffs laid where the ball passed.  Each pops in small and dense,
/// then swells, curls, rises a little and thins away in place, cooling from
/// the base grey toward a faint blue-grey.
private func trailMist(_ ctx: GraphicsContext, _ fr: TrailFrame, base: Color) {
    let cool = Color(red: 0.60, green: 0.68, blue: 0.80)
    for i in 0..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.7 else { continue }                       // a puff at about 7 marks in 10
        let age: Double = fr.age(i)
        let life: Double = fr.f(i)
        guard life < 1 else { continue }
        let rise: Double = fr.m > 0 ? min(1.0, age / 0.08) : 1.0
        let thin: Double = life < 0.40 ? 1.0 : 1.0 - (life - 0.40) / 0.60
        let env: Double = rise * max(0.0, thin)
        guard env > 0.02 else { continue }
        let p = fr.pts[i]
        let expand: Double = 1.0 + 1.8 * life * fr.m
        let curl: Double = seed * 6.283 + age * 1.4 * fr.m
        let lift: CGFloat = CGFloat(life * fr.m) * fr.bw * 0.9
        let coreOp: Double = (0.06 + 0.12 * (1.0 - 0.55 * life)) * env
        let coolOp: Double = 0.08 * life * env
        for k in 0..<2 {
            let kk: Double = Double(k)
            let ang: Double = curl + kk * 3.1
            let orbit: CGFloat = fr.bw * CGFloat(0.35 + 0.65 * life * fr.m)
            let pr: CGFloat = fr.bw * CGFloat((0.90 + 0.25 * kk) * expand)
            let cx: CGFloat = p.x + CGFloat(cos(ang)) * orbit
            let cy: CGFloat = p.y + CGFloat(sin(ang)) * orbit * 0.7 - lift
            ctx.fill(Path(ellipseIn: CGRect(x: cx - pr, y: cy - pr, width: pr * 2, height: pr * 2)),
                with: .radialGradient(Gradient(stops: [
                    .init(color: base.opacity(coreOp), location: 0.00),
                    .init(color: cool.opacity(coolOp), location: 0.55),
                    .init(color: cool.opacity(0.0),    location: 1.00)]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: pr))
        }
    }
}

/// Stardust — a soft glowing line with small stars set beside it.  Each star
/// sits at a fixed spot next to the mark that laid it, twinkles in place and
/// fades.
private func trailStardust(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    trailTapered(ctx, fr, width: fr.bw * 0.5, color: Color(red: 0.85, green: 0.82, blue: 1.0), glow: true)
    var ctx = ctx
    ctx.blendMode = .plusLighter
    for i in 0..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.62 else { continue }                      // slightly more stars
        let k: Double = fr.fresh(i)
        guard k > 0.01 else { continue }
        let tw: Double = fr.m > 0 ? 0.4 + 0.6 * sin(fr.tm * 4 + seed * 37.0) : 0.8
        guard tw > 0.25 else { continue }
        let ang: Double = seed * 6.283 * 3
        let off: CGFloat = fr.bw * CGFloat(0.6 + 1.6 * ((seed * 7.0).truncatingRemainder(dividingBy: 1.0)))
        let c = CGPoint(x: fr.pts[i].x + CGFloat(cos(ang)) * off, y: fr.pts[i].y + CGFloat(sin(ang)) * off)
        let sz: CGFloat = fr.bw * CGFloat(0.28 + 0.34 * k)   // slightly larger stars
        trailStar(ctx, c, sz, Color(red: 1, green: 0.98, blue: 0.85).opacity(tw * 0.9 * k))
    }
}

/// Forest (Standard) — a green line with small leaves set along it in two
/// greens.  Each leaf is keyed to the mark that laid it, stays put and fades.
private func trailForest(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    trailTapered(ctx, fr, width: fr.bw * 0.55, color: TrailColor.forest.color, glow: false)
    let dark  = Color(red: 0.10, green: 0.40, blue: 0.16)
    let light = Color(red: 0.38, green: 0.70, blue: 0.26)
    for i in 1..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.55 else { continue }                      // about half the marks carry a leaf
        let k: Double = fr.fresh(i)
        guard k > 0.01 else { continue }
        let p = fr.pts[i], a = fr.pts[i - 1]
        let dir: Double = atan2(Double(p.y - a.y), Double(p.x - a.x))
        let side: Double = (seed * 20).truncatingRemainder(dividingBy: 2) < 1 ? 1 : -1
        let ang: Double = dir + side * 0.9
        let len: CGFloat = fr.bw * CGFloat(0.9 + 0.6 * ((seed * 9).truncatingRemainder(dividingBy: 1)))
        let wid: CGFloat = len * 0.48
        let base = CGPoint(x: p.x + CGFloat(cos(ang)) * fr.bw * 0.2,
                           y: p.y + CGFloat(sin(ang)) * fr.bw * 0.2)
        let tip = CGPoint(x: base.x + CGFloat(cos(ang)) * len, y: base.y + CGFloat(sin(ang)) * len)
        let nx: CGFloat = CGFloat(-sin(ang)) * wid, ny: CGFloat = CGFloat(cos(ang)) * wid
        let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
        var leaf = Path()
        leaf.move(to: base)
        leaf.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
        leaf.addQuadCurve(to: base, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
        let col: Color = (seed * 13).truncatingRemainder(dividingBy: 1.0) < 0.5 ? dark : light
        ctx.fill(leaf, with: .color(col.opacity(0.95 * k)))
        var vein = Path(); vein.move(to: base); vein.addLine(to: tip)
        ctx.stroke(vein, with: .color(Color.black.opacity(0.18 * k)), lineWidth: 0.6)
    }
}

/// Wildfire (Standard, Fire set) — the ball leaves a burning scorch.  A
/// charred black line with a hot seam down the middle stays on the ground,
/// and tall, ragged, forked red flames stand on it: each leans its own way,
/// flickers where it was lit, then sinks and throws an ember upward as it
/// dies.  Unlike the Fire trail (small upright orange flames of light), this
/// is a taller, wilder, deep-red blaze over burnt ground.  Under Reduce
/// Motion the flames stand still and only fade.
private func trailWildfire(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    // Burnt ground and its glowing seam.
    trailTapered(ctx, fr, width: fr.bw * 0.72,
                 color: Color(red: 0.10, green: 0.04, blue: 0.03).opacity(0.80), glow: false)
    trailTapered(ctx, fr, width: fr.bw * 0.22,
                 color: Color(red: 1.00, green: 0.40, blue: 0.08).opacity(0.90), glow: false)
    let crimson = Color(red: 0.84, green: 0.10, blue: 0.05)
    let orange = Color(red: 1.00, green: 0.48, blue: 0.08)
    let yellow = Color(red: 1.00, green: 0.86, blue: 0.36)
    for i in 1..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.55 else { continue }                      // a flame at about half the marks
        let life: Double = fr.f(i)
        guard life < 1 else { continue }
        let age: Double = fr.age(i)
        let rise: Double = fr.m > 0 ? min(1.0, age / 0.07) : 1.0
        let env: Double = life < 0.50 ? 1.0 : 1.0 - (life - 0.50) / 0.50
        let k: Double = rise * max(0.0, env)
        guard k > 0.02 else { continue }
        let p = fr.pts[i]
        let s2: Double = (seed * 7.0).truncatingRemainder(dividingBy: 1.0)
        let s3: Double = (seed * 13.0).truncatingRemainder(dividingBy: 1.0)
        // A slow waver (about a 2-second period, a tenth of the height), not a flicker.
        let flick: Double = 0.90 + 0.10 * sin(fr.tm * 3.0 + seed * 40.0)
        let h: CGFloat = fr.bw * CGFloat((2.6 + 1.8 * s2) * flick * (0.55 + 0.45 * k))
        let w: CGFloat = fr.bw * 0.95
        let lean: CGFloat = CGFloat((s3 - 0.5) * 0.9 + sin(fr.tm * 1.8 + seed * 17.0) * 0.10 * fr.m) * h * 0.5
        let baseY: CGFloat = p.y + w * 0.30
        let tall = CGPoint(x: p.x + lean, y: p.y - h)
        let fork = CGPoint(x: p.x - w * 0.55 + lean * 0.45, y: p.y - h * 0.62)
        let notch = CGPoint(x: p.x - w * 0.10 + lean * 0.40, y: p.y - h * 0.42)
        var flame = Path()
        flame.move(to: CGPoint(x: p.x - w, y: baseY))
        flame.addQuadCurve(to: fork, control: CGPoint(x: p.x - w * 1.15, y: p.y - h * 0.28))
        flame.addLine(to: notch)
        flame.addQuadCurve(to: tall, control: CGPoint(x: p.x + w * 0.15 + lean * 0.5, y: p.y - h * 0.72))
        flame.addQuadCurve(to: CGPoint(x: p.x + w, y: baseY),
                           control: CGPoint(x: p.x + w * 1.20 + lean * 0.6, y: p.y - h * 0.30))
        flame.closeSubpath()
        ctx.fill(flame, with: .color(crimson.opacity(0.92 * k)))
        // Orange body inside the red.
        var body = Path()
        body.move(to: CGPoint(x: p.x - w * 0.55, y: baseY))
        body.addQuadCurve(to: CGPoint(x: p.x + lean * 0.75, y: p.y - h * 0.68),
                          control: CGPoint(x: p.x - w * 0.60, y: p.y - h * 0.30))
        body.addQuadCurve(to: CGPoint(x: p.x + w * 0.55, y: baseY),
                          control: CGPoint(x: p.x + w * 0.70 + lean * 0.4, y: p.y - h * 0.26))
        body.closeSubpath()
        ctx.fill(body, with: .color(orange.opacity(0.95 * k)))
        // Yellow heart at the foot.
        let hr: CGFloat = w * 0.34
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - hr, y: p.y - hr * 1.6, width: hr * 2, height: hr * 2.2)),
                 with: .color(yellow.opacity(0.90 * k)))
        // An ember thrown up as the flame dies.
        if life > 0.50 {
            let up: Double = (life - 0.50) / 0.50
            let ex: CGFloat = p.x + lean * 0.8 + CGFloat(sin(seed * 90.0)) * w * 0.6
            let ey: CGFloat = p.y - h * 0.7 - CGFloat(up * fr.m) * fr.bw * 3.0
            let er: CGFloat = max(0.6, fr.bw * 0.14)
            ctx.fill(Path(ellipseIn: CGRect(x: ex - er, y: ey - er, width: er * 2, height: er * 2)),
                     with: .color(yellow.opacity(0.85 * (1.0 - up))))
        }
    }
}

/// Splash (Standard, Water set) — a blue line with droplets beside it and,
/// on some marks, a thin ripple ring.  Everything stays put and fades.
private func trailSplash(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    trailTapered(ctx, fr, width: fr.bw * 0.45, color: TrailColor.splash.color, glow: false)
    let blue = Color(red: 0.30, green: 0.62, blue: 1.00)
    for i in 0..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.55 else { continue }
        let k: Double = fr.fresh(i)
        guard k > 0.01 else { continue }
        let off: CGFloat = CGFloat(sin(seed * 80.0)) * fr.bw * 0.8
        let c = CGPoint(x: fr.pts[i].x + off, y: fr.pts[i].y - off * 0.4)
        if seed < 0.15 {
            let rr: CGFloat = fr.bw * CGFloat(0.7 + seed * 3)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr * 0.6, width: rr * 2, height: rr * 1.2)),
                       with: .color(blue.opacity(0.55 * k)), lineWidth: max(0.5, fr.bw * 0.08))
            continue
        }
        let r: CGFloat = fr.bw * CGFloat(0.22 + 0.30 * (seed / 0.55))
        var drop = Path()
        drop.move(to: CGPoint(x: c.x, y: c.y - r * 1.7))
        drop.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * 0.9, y: c.y - r * 0.9))
        drop.addArc(center: c, radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        drop.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r * 1.7), control: CGPoint(x: c.x - r * 0.9, y: c.y - r * 0.9))
        ctx.fill(drop, with: .color(blue.opacity(0.85 * k)))
        let hr: CGFloat = r * 0.34
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.40 - hr / 2, y: c.y - r * 0.30 - hr / 2, width: hr, height: hr)),
                 with: .color(Color.white.opacity(0.80 * k)))
    }
}

/// Squall (Standard, Storm set) — driving rain.  Each mark leaves a faint
/// patch of mist; slanted rain streaks fall onto the path and burst into small
/// splash rings where they land.  Everything happens where the mark was laid
/// (nothing follows the ball).  Under Reduce Motion the streaks and rings are
/// still and simply fade.
private func trailSquall(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    let mist = Color(red: 0.50, green: 0.53, blue: 0.60)
    let rain = Color(red: 0.82, green: 0.87, blue: 0.96)
    let slantX: CGFloat = -0.34                      // driven down and to the left
    let slantY: CGFloat = 0.94
    for i in 0..<fr.n {
        let k: Double = fr.fresh(i)
        guard k > 0.01 else { continue }
        let seed: Double = fr.seed(i)
        let r: CGFloat = fr.bw * CGFloat(0.50 + 0.35 * seed)
        let c = fr.pts[i]
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: [mist.opacity(0.40 * k), mist.opacity(0)]),
                                       center: c, startRadius: 0, endRadius: r))
    }
    let hitAt: Double = 0.30                         // share of the lifetime spent falling
    let streakWidth: CGFloat = max(0.7, fr.bw * 0.14)
    let ringWidth: CGFloat = max(0.6, fr.bw * 0.10)
    for i in 0..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.55 else { continue }          // about one mark in two
        let f: Double = fr.f(i)
        guard f < 1 else { continue }
        let side: CGFloat = CGFloat(sin(seed * 71.0)) * fr.bw * 0.9
        let land = CGPoint(x: fr.pts[i].x + side, y: fr.pts[i].y + side * 0.3)
        if fr.m > 0 && f < hitAt {
            let u: CGFloat = CGFloat(1.0 - f / hitAt)            // 1 far away → 0 landed
            let fall: CGFloat = fr.bw * 3.2 * u
            let len: CGFloat = fr.bw * 1.5
            let tip = CGPoint(x: land.x - slantX * fall, y: land.y - slantY * fall)
            let tail = CGPoint(x: tip.x - slantX * len, y: tip.y - slantY * len)
            var streak = Path()
            streak.move(to: tail)
            streak.addLine(to: tip)
            ctx.stroke(streak, with: .color(rain.opacity(0.75)),
                       style: StrokeStyle(lineWidth: streakWidth, lineCap: .round))
        } else {
            let u: Double = fr.m > 0 ? (f - hitAt) / (1.0 - hitAt) : 0.35
            let rr: CGFloat = fr.bw * CGFloat(0.25 + 0.75 * u)
            let a: Double = fr.m > 0 ? 0.65 * (1.0 - u) : 0.55 * fr.fresh(i)
            let ring = Path(ellipseIn: CGRect(x: land.x - rr, y: land.y - rr * 0.55,
                                              width: rr * 2, height: rr * 1.1))
            ctx.stroke(ring, with: .color(rain.opacity(a)), lineWidth: ringWidth)
            if fr.m == 0 {
                var streak = Path()
                streak.move(to: CGPoint(x: land.x - slantX * fr.bw * 1.7, y: land.y - slantY * fr.bw * 1.7))
                streak.addLine(to: CGPoint(x: land.x - slantX * fr.bw * 0.4, y: land.y - slantY * fr.bw * 0.4))
                ctx.stroke(streak, with: .color(rain.opacity(0.50 * fr.fresh(i))),
                           style: StrokeStyle(lineWidth: streakWidth, lineCap: .round))
            }
        }
    }
}

/// Zest (Citrus set) — a thin juice line with curls of orange and lemon peel
/// laid beside it and a few juice drops.  Each curl stays where it fell and
/// fades there; nothing moves.
private func trailZest(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    trailTapered(ctx, fr, width: fr.bw * 0.30, color: TrailColor.zest.color, glow: false)
    let orange = Color(red: 0.98, green: 0.56, blue: 0.10)
    let lemon  = Color(red: 1.00, green: 0.86, blue: 0.22)
    let lime   = Color(red: 0.56, green: 0.80, blue: 0.22)
    let pith   = Color(red: 1.00, green: 0.96, blue: 0.84)
    for i in 1..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.42 else { continue }
        let k: Double = fr.fresh(i)
        guard k > 0.01 else { continue }
        let p = fr.pts[i], a = fr.pts[i - 1]
        let dir: Double = atan2(Double(p.y - a.y), Double(p.x - a.x))
        let pick: Double = (seed * 37).truncatingRemainder(dividingBy: 1)
        if seed < 0.10 {
            // A juice drop.
            let off: CGFloat = fr.bw * CGFloat(0.5 + pick)
            let sideSign: CGFloat = pick < 0.5 ? 1 : -1
            let c = CGPoint(x: p.x + CGFloat(-sin(dir)) * off * sideSign,
                            y: p.y + CGFloat(cos(dir)) * off * sideSign)
            let r: CGFloat = fr.bw * CGFloat(0.16 + 0.14 * pick)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .color(lemon.opacity(0.85 * k)))
            let hr: CGFloat = r * 0.4
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.4 - hr / 2, y: c.y - r * 0.4 - hr / 2,
                                            width: hr, height: hr)),
                     with: .color(Color.white.opacity(0.7 * k)))
            continue
        }
        // A curl of peel: a short spiral arc, rind color outside, pale pith inside.
        let rind: Color = pick < 0.45 ? orange : (pick < 0.8 ? lemon : lime)
        let side: Double = (seed * 20).truncatingRemainder(dividingBy: 2) < 1 ? 1 : -1
        let off: CGFloat = fr.bw * 0.75
        let c = CGPoint(x: p.x + CGFloat(-sin(dir) * side) * off,
                        y: p.y + CGFloat(cos(dir) * side) * off)
        let r0: CGFloat = fr.bw * CGFloat(0.42 + 0.30 * pick)
        var curl = Path()
        let steps = 9
        for j in 0...steps {
            let u: Double = Double(j) / Double(steps)
            let ang: Double = dir + side * (0.4 + u * 4.2)
            let rr: CGFloat = r0 * CGFloat(1.0 - 0.62 * u)
            let q = CGPoint(x: c.x + CGFloat(cos(ang)) * rr, y: c.y + CGFloat(sin(ang)) * rr)
            if j == 0 { curl.move(to: q) } else { curl.addLine(to: q) }
        }
        let w: CGFloat = max(1.2, fr.bw * 0.24)
        ctx.stroke(curl, with: .color(rind.opacity(0.92 * k)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        ctx.stroke(curl, with: .color(pith.opacity(0.55 * k)),
                   style: StrokeStyle(lineWidth: w * 0.34, lineCap: .round, lineJoin: .round))
    }
}

/// Bubblegum (Standard) — a pink line with small pink bubbles, each with a
/// white highlight.  A bubble stays where it was laid, fades, and at the end
/// of its life pops (a quick ring that widens and vanishes).
private func trailBubblegum(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    trailTapered(ctx, fr, width: fr.bw * 0.45, color: TrailColor.bubblegum.color, glow: false)
    let pink = Color(red: 1.00, green: 0.42, blue: 0.80)
    for i in 0..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.6 else { continue }
        let f: Double = fr.f(i)
        guard f < 1 else { continue }
        let pick: Double = seed / 0.6
        let r: CGFloat = fr.bw * CGFloat(0.35 + 0.55 * pick)
        let off: CGFloat = CGFloat(sin(seed * 90.0)) * fr.bw * 0.7
        let c = CGPoint(x: fr.pts[i].x + off, y: fr.pts[i].y - off * 0.5)
        if fr.m > 0 && f > 0.82 {
            // Pop: a thin ring widens and vanishes.
            let s: Double = (f - 0.82) / 0.18
            let pr: CGFloat = r * CGFloat(1 + 0.6 * s)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2)),
                       with: .color(pink.opacity(0.7 * (1 - s))), lineWidth: max(0.5, r * 0.12))
            continue
        }
        let a: Double = fr.m > 0 ? min(1, (1 - f) / 0.2) : 1 - f
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(pink.opacity(0.50 * a)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(pink.opacity(0.9 * a)), lineWidth: max(0.6, r * 0.18))
        let hr: CGFloat = r * 0.32
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.45 - hr / 2, y: c.y - r * 0.45 - hr / 2,
                                        width: hr, height: hr)),
                 with: .color(Color.white.opacity(0.85 * a)))
    }
}

/// Ember (Rare) — a glowing orange line with a few tiny sparks.  Each spark
/// is born where its mark was laid, rises and sways a little, and fades.
private func trailEmber(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    trailTapered(ctx, fr, width: fr.bw, color: TrailColor.ember.color, glow: true)
    var ctx = ctx
    ctx.blendMode = .plusLighter
    for i in 0..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.22 else { continue }                      // about one mark in five sheds a spark
        let life: Double = fr.f(i)
        guard life < 1 else { continue }
        let p = fr.pts[i]
        let rise: CGFloat = CGFloat(life * fr.m) * fr.bw * 2.2
        let sway: CGFloat = CGFloat(sin(seed * 6.283 + life * 3.0) * fr.m) * fr.bw * 0.6
        let c = CGPoint(x: p.x + sway, y: p.y - rise)
        let r: CGFloat = fr.bw * CGFloat(0.20 * (1 - life * 0.5))
        let glow = Color(red: 1.0, green: 0.62, blue: 0.20).opacity(0.75 * (1 - life))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 2, y: c.y - r * 2, width: r * 4, height: r * 4)),
                 with: .radialGradient(Gradient(colors: [glow.opacity(0.5), .clear]),
                                       center: c, startRadius: 0, endRadius: r * 2))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .color(Color(red: 1.0, green: 0.86, blue: 0.50).opacity(0.85 * (1 - life))))
    }
}

/// Air — soft puffs laid where the ball passed.  Each billows in, swells a
/// little, lifts and sways in place, and fades.
private func trailAir(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    for i in 0..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.7 else { continue }
        let age: Double = fr.age(i)
        let life: Double = fr.f(i)
        guard life < 1 else { continue }
        let rise: Double = fr.m > 0 ? min(1.0, age / 0.08) : 1.0
        let env: Double = rise * max(0, 1 - life)
        guard env > 0.02 else { continue }
        let p = fr.pts[i]
        let expand: Double = 1.0 + 0.8 * life * fr.m
        let drift: CGFloat = CGFloat(sin(fr.tm * 1.6 + seed * 6.283) * fr.m) * fr.bw * 0.5
        let lift: CGFloat = -CGFloat(life * fr.m) * fr.bw * 0.8
        let pr: CGFloat = fr.bw * CGFloat(1.3 * expand)
        let cxp: CGFloat = p.x + drift, cyp: CGFloat = p.y + lift
        for k in 0..<2 {
            let ox: CGFloat = CGFloat(k == 0 ? -0.32 : 0.32) * pr
            ctx.fill(Path(ellipseIn: CGRect(x: cxp + ox - pr, y: cyp - pr, width: pr * 2, height: pr * 2)),
                with: .radialGradient(Gradient(colors: [Color(red: 0.88, green: 0.94, blue: 1.0).opacity(0.18 * env), .clear]),
                    center: CGPoint(x: cxp + ox, y: cyp), startRadius: 0, endRadius: pr))
        }
    }
}

/// Ink — a neat pen line while the ball moves; where it lingers the ink pools
/// and bleeds wider, like a pen held to paper.  Dwell is the time gap to the
/// next mark: a fast stroke lays marks in quick succession (a crisp line); a
/// resting ball lays none, so its newest mark's blot keeps widening until it
/// saturates.  Once the pen moves on each blot is fixed where it was set, and
/// fades there on its own clock.
private func trailInk(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    let ink = Color(red: 0.05, green: 0.05, blue: 0.10)
    let neatR: CGFloat = fr.bw * 0.30
    let maxBleed: CGFloat = fr.bw * 3.2
    let tau: Double = 0.10
    let n = fr.n
    func radius(_ i: Int) -> CGFloat {
        let next: Double = i < n - 1 ? fr.laid[i + 1] : fr.now
        let dwell: Double = max(0, next - fr.laid[i])
        return neatR + CGFloat(Double(maxBleed) * (1 - exp(-dwell / tau)))
    }
    /// Full ink while fresh, then fades over the last 40 % of its life.
    func inkFade(_ i: Int) -> Double {
        let f: Double = fr.f(i)
        return f < 0.6 ? 1.0 : max(0, 1.0 - (f - 0.6) / 0.4)
    }
    for i in 1..<n {
        let k: Double = inkFade(i - 1)
        guard k > 0.01 else { continue }
        let w: CGFloat = radius(i - 1) + radius(i)
        var p = Path(); p.move(to: fr.pts[i - 1]); p.addLine(to: fr.pts[i])
        ctx.stroke(p, with: .color(ink.opacity(k)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
    for i in 0..<n {
        let r: CGFloat = radius(i)
        guard r > neatR + 0.6 else { continue }
        let k: Double = inkFade(i)
        guard k > 0.01 else { continue }
        let p = fr.pts[i]
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(Gradient(stops: [
                .init(color: ink.opacity(k),   location: 0.00),
                .init(color: ink.opacity(k),   location: 0.97),
                .init(color: ink.opacity(0.0), location: 1.00)]),
                center: p, startRadius: 0, endRadius: r))
    }
}

/// Rainbow — a glowing spectrum line.  Each mark gets its hue when laid and
/// keeps it, so the colours stay where they were painted.  A segment blooms,
/// holds, then dissolves into tiny spectral sparkles that scatter outward and
/// twinkle out in place.
private func trailRainbow(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    var ctx = ctx
    for i in 1..<fr.n {
        let age: Double = fr.age(i - 1)
        let life: Double = fr.f(i - 1)
        guard life < 1 else { continue }
        let bloom: Double = fr.m > 0 ? min(1.0, age / 0.10) : 1.0
        let fade: Double = life < 0.30 ? 1.0 : 1.0 - (life - 0.30) / 0.45
        let env: Double = bloom * max(0.0, fade)
        guard env > 0.02 else { continue }
        let col = Color(hue: trailHue(fr.laid[i]), saturation: 1, brightness: 1)
        let w: CGFloat = fr.bw * CGFloat(0.4 + 0.8 * env)
        var p = Path(); p.move(to: fr.pts[i - 1]); p.addLine(to: fr.pts[i])
        ctx.blendMode = .plusLighter
        ctx.stroke(p, with: .color(col.opacity(0.20 * env)),
                   style: StrokeStyle(lineWidth: w * 2.2, lineCap: .round))
        ctx.blendMode = .normal
        ctx.stroke(p, with: .color(col.opacity(0.90 * env)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
    ctx.blendMode = .plusLighter
    for i in 0..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.40 else { continue }
        let life: Double = fr.f(i)
        guard life > 0.35, life < 1 else { continue }
        let s: Double = (life - 0.35) / 0.65
        let tw: Double = fr.m > 0 ? 0.55 + 0.45 * sin(fr.tm * 6.0 + seed * 40.0) : 0.8
        let op: Double = (1.0 - s) * tw * 0.9
        guard op > 0.03 else { continue }
        let ang: Double = seed * 6.283 * 2.5
        let scatter: CGFloat = fr.bw * CGFloat(0.6 + 2.0 * s * fr.m)
        let c = CGPoint(x: fr.pts[i].x + CGFloat(cos(ang)) * scatter,
                        y: fr.pts[i].y + CGFloat(sin(ang)) * scatter)
        let sz: CGFloat = fr.bw * CGFloat(0.36 - 0.14 * s)
        trailStar(ctx, c, sz, Color(hue: trailHue(fr.laid[i]), saturation: 0.85, brightness: 1.0).opacity(op))
    }
}

/// A small 4-point sparkle star (used by the stardust and rainbow trails).
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

// — Quality round: Champion —
/// Victory Lap — a winner's ribbon laid flat along the path (crimson edges,
/// a gold body, a pale center stripe) with ticker-tape confetti tossed out to
/// either side.  Each piece flutters down for a moment where it was thrown,
/// settles, and fades with its mark; under Reduce Motion it is simply settled.
private func trailVictoryLap(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    let crimson = Color(red: 0.70, green: 0.08, blue: 0.14)
    let gold    = Color(red: 0.98, green: 0.80, blue: 0.30)
    let pale    = Color(red: 1.00, green: 0.95, blue: 0.72)
    for i in 1..<fr.n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        // About half the base width (quality standard), so the ball is never hidden.
        let w: CGFloat = fr.bw * CGFloat(0.42 + 0.22 * k)
        var p = Path(); p.move(to: fr.pts[i - 1]); p.addLine(to: fr.pts[i])
        ctx.stroke(p, with: .color(crimson.opacity(0.85 * k)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(gold.opacity(0.95 * k)),
                   style: StrokeStyle(lineWidth: w * 0.66, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(pale.opacity(0.70 * k)),
                   style: StrokeStyle(lineWidth: max(0.6, w * 0.16), lineCap: .round, lineJoin: .round))
    }
    let colors: [Color] = [gold, Color.white, crimson, pale]
    for i in 1..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.55 else { continue }                      // confetti at about half the marks
        let k: Double = fr.fresh(i)
        guard k > 0.03 else { continue }
        let age: Double = fr.age(i)
        // 0 just thrown -> 1 settled (0.8 s, a slow half-turn); settled at once under Reduce Motion.
        let settle: Double = fr.m > 0 ? min(1.0, age / 0.80) : 1.0
        let dx: CGFloat = fr.pts[i].x - fr.pts[i - 1].x, dy: CGFloat = fr.pts[i].y - fr.pts[i - 1].y
        let len: CGFloat = max(0.001, hypot(dx, dy))
        let px: CGFloat = -dy / len, py: CGFloat = dx / len
        for piece in 0..<2 {
            let s2: Double = (seed * (piece == 0 ? 17.3 : 29.1) + 0.21).truncatingRemainder(dividingBy: 1.0)
            let side: CGFloat = piece == 0 ? 1 : -1
            let reach: CGFloat = fr.bw * CGFloat(1.1 + 1.5 * s2)
            // Thrown from the ribbon outward, dropping a little as it lands.
            let out: CGFloat = reach * CGFloat(0.35 + 0.65 * settle)
            let lift: CGFloat = fr.bw * 0.9 * CGFloat(1.0 - settle)
            let cx: CGFloat = fr.pts[i].x + px * out * side
            let cy: CGFloat = fr.pts[i].y + py * out * side - lift
            let spin: Double = s2 * 6.283 + (1.0 - settle) * 2.2
            let hw: CGFloat = fr.bw * 0.34, hh: CGFloat = fr.bw * 0.14
            let ca: CGFloat = CGFloat(cos(spin)), sa: CGFloat = CGFloat(sin(spin))
            var rect = Path()
            rect.move(to: CGPoint(x: cx - ca * hw + sa * hh, y: cy - sa * hw - ca * hh))
            rect.addLine(to: CGPoint(x: cx + ca * hw + sa * hh, y: cy + sa * hw - ca * hh))
            rect.addLine(to: CGPoint(x: cx + ca * hw - sa * hh, y: cy + sa * hw + ca * hh))
            rect.addLine(to: CGPoint(x: cx - ca * hw - sa * hh, y: cy - sa * hw + ca * hh))
            rect.closeSubpath()
            let color: Color = colors[Int(s2 * 3.999)]
            ctx.fill(rect, with: .color(color.opacity(0.92 * k)))
        }
    }
}

// — Quality round: Ancient Temple —
/// Glyphs — a shallow groove pressed into the sand with small carved glyphs
/// (a sun disc, a water zig-zag, an eye, a stepped pyramid) to either side.
/// Each glyph is carved where the ball passed, keeps its place and shape, and
/// fades as the sand fills it in.  No motion.
private func trailGlyphs(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    let cut  = Color(red: 0.42, green: 0.26, blue: 0.12)        // shadowed side of a cut
    let lip  = Color(red: 1.00, green: 0.93, blue: 0.74)        // sunlit lip
    for i in 1..<fr.n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        var p = Path(); p.move(to: fr.pts[i - 1]); p.addLine(to: fr.pts[i])
        let w: CGFloat = fr.bw * CGFloat(0.30 + 0.25 * k)
        ctx.stroke(p.offsetBy(dx: 0.8, dy: 0.8), with: .color(lip.opacity(0.42 * k)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(cut.opacity(0.55 * k)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
    for i in 1..<fr.n {
        let seed: Double = fr.seed(i)
        // About one mark in five, never two in a row, so glyphs don't pile up.
        guard seed < 0.22, fr.seed(i - 1) >= 0.22 else { continue }
        let k: Double = fr.fresh(i)
        guard k > 0.03 else { continue }
        let s2: Double = (seed * 41.3 + 0.13).truncatingRemainder(dividingBy: 1.0)
        let dx: CGFloat = fr.pts[i].x - fr.pts[i - 1].x, dy: CGFloat = fr.pts[i].y - fr.pts[i - 1].y
        let len: CGFloat = max(0.001, hypot(dx, dy))
        let side: CGFloat = s2 < 0.5 ? 1 : -1
        let off: CGFloat = fr.bw * 1.9
        let c = CGPoint(x: fr.pts[i].x - dy / len * off * side, y: fr.pts[i].y + dx / len * off * side)
        let g: CGFloat = fr.bw * 0.95                               // glyph half-size
        var glyph = Path()
        switch Int(seed / 0.22 * 3.999) {
        case 0:   // sun disc: a ring with a center dot
            glyph.addEllipse(in: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2))
            glyph.addEllipse(in: CGRect(x: c.x - g * 0.22, y: c.y - g * 0.22, width: g * 0.44, height: g * 0.44))
        case 1:   // water: a zig-zag line
            glyph.move(to: CGPoint(x: c.x - g, y: c.y + g * 0.35))
            glyph.addLine(to: CGPoint(x: c.x - g * 0.5, y: c.y - g * 0.35))
            glyph.addLine(to: CGPoint(x: c.x, y: c.y + g * 0.35))
            glyph.addLine(to: CGPoint(x: c.x + g * 0.5, y: c.y - g * 0.35))
            glyph.addLine(to: CGPoint(x: c.x + g, y: c.y + g * 0.35))
        case 2:   // eye: an almond with a pupil
            glyph.move(to: CGPoint(x: c.x - g, y: c.y))
            glyph.addQuadCurve(to: CGPoint(x: c.x + g, y: c.y), control: CGPoint(x: c.x, y: c.y - g * 1.0))
            glyph.addQuadCurve(to: CGPoint(x: c.x - g, y: c.y), control: CGPoint(x: c.x, y: c.y + g * 1.0))
            glyph.addEllipse(in: CGRect(x: c.x - g * 0.25, y: c.y - g * 0.25, width: g * 0.5, height: g * 0.5))
        default:  // stepped pyramid
            glyph.move(to: CGPoint(x: c.x - g, y: c.y + g * 0.7))
            glyph.addLine(to: CGPoint(x: c.x - g, y: c.y + g * 0.2))
            glyph.addLine(to: CGPoint(x: c.x - g * 0.5, y: c.y + g * 0.2))
            glyph.addLine(to: CGPoint(x: c.x - g * 0.5, y: c.y - g * 0.3))
            glyph.addLine(to: CGPoint(x: c.x + g * 0.5, y: c.y - g * 0.3))
            glyph.addLine(to: CGPoint(x: c.x + g * 0.5, y: c.y + g * 0.2))
            glyph.addLine(to: CGPoint(x: c.x + g, y: c.y + g * 0.2))
            glyph.addLine(to: CGPoint(x: c.x + g, y: c.y + g * 0.7))
            glyph.closeSubpath()
        }
        let lw: CGFloat = max(0.8, fr.bw * 0.17)
        ctx.stroke(glyph.offsetBy(dx: 0.7, dy: 0.7), with: .color(lip.opacity(0.55 * k)),
                   style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        ctx.stroke(glyph, with: .color(cut.opacity(0.80 * k)),
                   style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
    }
}

// — Standard audit: Nightclub —
/// Dance Steps — the dance floor lights up where the ball rolled.  A thin
/// dim line shows the path; about one mark in three leaves a floor tile (a
/// small upright square, magenta, cyan or violet) that is lit when laid and
/// dims where it lies.  Tiles never move; with Reduce Motion they simply fade.
private func trailDanceSteps(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    trailTapered(ctx, fr, width: fr.bw * 0.34,
                 color: Color(red: 0.72, green: 0.30, blue: 0.86).opacity(0.50), glow: false)
    let hues: [Color] = [Color(red: 1.00, green: 0.26, blue: 0.72),
                         Color(red: 0.26, green: 0.86, blue: 1.00),
                         Color(red: 0.66, green: 0.40, blue: 1.00)]
    var glow = ctx
    glow.blendMode = .plusLighter
    for i in 1..<fr.n {
        let seed: Double = fr.seed(i)
        // Never two in a row, so tiles sit apart like squares of a floor.
        guard seed < 0.34, fr.seed(i - 1) >= 0.34 else { continue }
        let f: Double = fr.f(i)
        guard f < 1 else { continue }
        // Lit at full for the first third of its life, then dims.
        let lit: Double = f < 0.30 ? 1.0 : max(0.0, 1.0 - (f - 0.30) / 0.70)
        guard lit > 0.02 else { continue }
        let pick: Int = min(2, Int(seed / 0.34 * 2.999))
        let color: Color = hues[pick]
        let half: CGFloat = fr.bw * 0.95
        let c: CGPoint = fr.pts[i]
        let rect = CGRect(x: c.x - half, y: c.y - half, width: half * 2, height: half * 2)
        let tile = Path(roundedRect: rect, cornerRadius: half * 0.16)
        glow.fill(Path(roundedRect: rect.insetBy(dx: -half * 0.45, dy: -half * 0.45),
                       cornerRadius: half * 0.5),
                  with: .color(color.opacity(0.14 * lit)))
        ctx.fill(tile, with: .color(color.opacity(0.42 * lit)))
        ctx.stroke(tile, with: .color(Color.white.opacity(0.55 * lit)),
                   lineWidth: max(0.6, fr.bw * 0.10))
        // A soft sheen across the top half, as on a glass floor panel.
        let sheen = CGRect(x: rect.minX + half * 0.22, y: rect.minY + half * 0.20,
                           width: half * 1.56, height: half * 0.42)
        ctx.fill(Path(roundedRect: sheen, cornerRadius: half * 0.12),
                 with: .color(Color.white.opacity(0.22 * lit)))
    }
}

// — Standard audit: Golf —
/// Dew Line — the dark track a ball leaves through morning dew on a mown
/// green: a soft dark-green line where the dew was pressed away, with small
/// dew drops left standing along both edges.  Each drop keeps its place and
/// catches the light with a slow glint; nothing moves.  With Reduce Motion the
/// glint holds still.
private func trailDewLine(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    let track = Color(red: 0.08, green: 0.30, blue: 0.12)
    for i in 1..<fr.n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        var p = Path(); p.move(to: fr.pts[i - 1]); p.addLine(to: fr.pts[i])
        // A wide, very soft pressed band, then the darker line down its middle.
        ctx.stroke(p, with: .color(track.opacity(0.16 * k)),
                   style: StrokeStyle(lineWidth: fr.bw * 1.05, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(track.opacity(0.46 * k)),
                   style: StrokeStyle(lineWidth: fr.bw * 0.46, lineCap: .round, lineJoin: .round))
    }
    let drop = Color(red: 0.86, green: 0.97, blue: 1.00)
    for i in 1..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.52 else { continue }
        let k: Double = fr.fresh(i)
        guard k > 0.03 else { continue }
        let dx: CGFloat = fr.pts[i].x - fr.pts[i - 1].x
        let dy: CGFloat = fr.pts[i].y - fr.pts[i - 1].y
        let len: CGFloat = max(0.001, hypot(dx, dy))
        let s2: Double = (seed * 37.7 + 0.31).truncatingRemainder(dividingBy: 1.0)
        let side: CGFloat = s2 < 0.5 ? 1 : -1
        let off: CGFloat = fr.bw * CGFloat(0.72 + 0.34 * s2)
        let c = CGPoint(x: fr.pts[i].x - dy / len * off * side,
                        y: fr.pts[i].y + dx / len * off * side)
        let r: CGFloat = fr.bw * CGFloat(0.13 + 0.12 * (seed / 0.52))
        // Slow glint, each drop on its own phase (about a 2.4 s period).
        let glint: Double = fr.m > 0 ? 0.70 + 0.30 * sin(fr.tm * 2.6 + seed * 40.0) : 0.85
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.7 + r * 0.5, width: r * 2, height: r * 1.4)),
                 with: .color(track.opacity(0.30 * k)))                      // tiny shadow under the drop
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .color(drop.opacity(0.50 * k)))
        let hr: CGFloat = r * 0.42
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.35 - hr / 2, y: c.y - r * 0.35 - hr / 2,
                                        width: hr, height: hr)),
                 with: .color(Color.white.opacity(0.95 * k * glint)))
    }
}

// — Standard audit: Ocean —
/// Wake — the wake of a boat.  Where the ball passed, churned pale water
/// lies down the middle and a line of foam runs along each side; as each mark
/// ages its two foam edges ease apart and thin out, the way a wake widens
/// behind a hull, with a few foam flecks left between.  Every mark stays
/// where it was laid.  With Reduce Motion the edges keep one width and fade.
private func trailWake(_ ctx: GraphicsContext, _ fr: TrailFrame) {
    let churn = Color(red: 0.62, green: 0.90, blue: 0.96)
    let foam = Color(red: 0.96, green: 0.99, blue: 1.00)
    // Spread of one mark's foam edge from the path, by its age.
    func spread(_ i: Int) -> CGFloat {
        let f: Double = fr.m > 0 ? fr.f(i) : 0.45
        return fr.bw * CGFloat(0.30 + 0.95 * f)
    }
    for i in 1..<fr.n {
        let k: Double = fr.fresh(i - 1)
        guard k > 0.01 else { continue }
        let a: CGPoint = fr.pts[i - 1], b: CGPoint = fr.pts[i]
        let dx: CGFloat = b.x - a.x, dy: CGFloat = b.y - a.y
        let len: CGFloat = max(0.001, hypot(dx, dy))
        let nx: CGFloat = -dy / len, ny: CGFloat = dx / len
        var mid = Path(); mid.move(to: a); mid.addLine(to: b)
        ctx.stroke(mid, with: .color(churn.opacity(0.20 * k)),
                   style: StrokeStyle(lineWidth: fr.bw * 0.80, lineCap: .round, lineJoin: .round))
        let sa: CGFloat = spread(i - 1), sb: CGFloat = spread(i)
        let w: CGFloat = fr.bw * CGFloat(0.12 + 0.16 * k)
        for side in [CGFloat(1), CGFloat(-1)] {
            var edge = Path()
            edge.move(to: CGPoint(x: a.x + nx * sa * side, y: a.y + ny * sa * side))
            edge.addLine(to: CGPoint(x: b.x + nx * sb * side, y: b.y + ny * sb * side))
            ctx.stroke(edge, with: .color(foam.opacity(0.80 * k)),
                       style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
    }
    // Foam flecks left in the churned water, on about one mark in three.
    for i in 1..<fr.n {
        let seed: Double = fr.seed(i)
        guard seed < 0.34 else { continue }
        let k: Double = fr.fresh(i)
        guard k > 0.05 else { continue }
        let s2: Double = (seed * 53.9 + 0.17).truncatingRemainder(dividingBy: 1.0)
        let dx: CGFloat = fr.pts[i].x - fr.pts[i - 1].x
        let dy: CGFloat = fr.pts[i].y - fr.pts[i - 1].y
        let len: CGFloat = max(0.001, hypot(dx, dy))
        let off: CGFloat = spread(i) * CGFloat(s2 * 1.6 - 0.8)
        let c = CGPoint(x: fr.pts[i].x - dy / len * off, y: fr.pts[i].y + dx / len * off)
        let r: CGFloat = fr.bw * CGFloat(0.07 + 0.09 * (seed / 0.34))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .color(foam.opacity(0.75 * k)))
    }
}

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
