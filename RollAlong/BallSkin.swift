import SwiftUI

// ---------------------------------------------------------------------------
// BallSkin — every available ball appearance.
//
// Each skin is a 4-stop radial gradient (off-centre highlight → main →
// shadow → deep shadow) so the ball reads as a 3D marble.  Tier
// classification + pricing live in Cosmetics.swift as an extension.
//
// rawValue strings are the persistence keys for ownership / equipped
// state — don't rename or reorder existing cases.
// ---------------------------------------------------------------------------
enum BallSkin: String, CaseIterable, Identifiable {
    // Starter
    case red    = "Classic Red"

    // Standard (50 coins)
    case blue   = "Ocean Blue"
    case green  = "Jade Green"
    case purple = "Deep Purple"
    case rose   = "Rose"
    case coral  = "Coral"
    case mint   = "Mint"
    case slate  = "Slate"
    case lemon  = "Lemon"

    // Premium / Epic (200 coins)
    case gold   = "Fool's Gold"
    case silver = "Silver"
    case copper = "Copper"
    case jade   = "Jade"
    case ruby   = "Ruby"

    // Exclusive / Legendary (500 coins) — animated / special-effect renderers
    case galaxy    = "Galaxy"          // multi-colour gradient (kept here for parity)
    case nebula    = "Nebula"          // multi-colour gradient
    case opal      = "Opal"            // multi-colour gradient
    case snowglobe = "Snowglobe"       // glass marble with swirling snow inside
    case golfBall  = "Golf Ball"       // white with dimples (Golf bundle)

    // Planets bundle (200 coins each — multi-colour gradient marbles).
    // Saturn gets a bespoke ringed Canvas in BallGameView; the rest are
    // pure radial-gradient marbles.
    case earth   = "Earth"
    case mars    = "Mars"
    case saturn  = "Saturn"
    case mercury = "Mercury"
    case neptune = "Neptune"
    case jupiter = "Jupiter"
    case venus   = "Venus"
    case uranus  = "Uranus"

    // ★ Pluto — exclusive, bundle-ONLY (never in the standalone Ball
    // shop tab).  Rolls at HALF the normal ball radius for a unique
    // gameplay feel — see `radiusScale` + BallGameView.effectiveBallRadius.
    case pluto   = "Pluto"

    // Space Travel bundle — animated flying-saucer marble with a
    // bespoke Canvas renderer (glowing dome + rotating under-lights)
    // in BallGameView.ufoMarble.
    case ufo     = "UFO"

    // Round-4 themed bundles.
    //   • pastel / neon — pure radial-gradient marbles (default renderer).
    //   • soccer — white body with black pentagons via the bespoke
    //     `soccerMarble` Canvas in BallGameView (clipped to a circle so
    //     the edge pentagons run off the silhouette like the real thing).
    case pastel  = "Pastel"
    case neon    = "Neon"
    case soccer  = "Soccer Ball"

    // Round-4 pass 2 — bespoke glass spheres.
    //   • aquarium — translucent aqua orb with static bubbles, via the
    //     `aquariumMarble` Canvas in BallGameView (clipped to a circle).
    //   • marble — clear glass with an internal cobalt cat's-eye swirl,
    //     via the `glassMarble` Canvas (clipped to a circle).
    case aquarium = "Aquarium"
    case marble   = "Marble"

    // Round-5 themed bundles.
    //   • dune — warm desert gradient (sand → ochre → terracotta → dusk),
    //     pure radial gradient via the default renderer.
    case dune = "Dune"
    //   • storm — dark storm-cloud sphere with a lightning bolt, via the
    //     bespoke `stormMarble` Canvas in BallGameView (clipped to circle).
    case storm = "Storm"
    //   • candy — glossy peppermint pinwheel of red/white wedges, via the
    //     bespoke `candyMarble` Canvas in BallGameView (clipped to circle).
    case candy = "Candy"
    //   • ghost — luminous pale orb with hollow eyes and a wailing mouth,
    //     via the bespoke `ghostMarble` Canvas in BallGameView.
    case ghost = "Ghost"

    // ── Sports bundle skins (new) ──────────────────────────────────────
    //   • basketball — orange sphere with classic NBA seam curves, via the
    //     bespoke `basketballCanvas` in BallSkinView.
    case basketball = "Basketball"
    //   • eightBall — near-black sphere with a white badge containing "8",
    //     via the bespoke `eightBallCanvas` in BallSkinView.
    case eightBall  = "8-Ball"
    //   • baseball — off-white leather sphere with red stitched seam curves,
    //     via the bespoke `baseballCanvas` in BallSkinView.
    case baseball   = "Baseball"

    // ── Starter Pack exclusive ──────────────────────────────────────────
    //   • aurora — deep midnight sphere with animated teal-green and violet
    //     Northern Lights bands and twinkling stars.  Available ONLY via
    //     the one-time $1.99 Starter Pack offer; never purchasable with
    //     coins and hidden from the regular shop grid.
    case aurora = "Aurora"

    // ── Summer 2026 seasonal exclusive ──────────────────────────────────
    //   • beachBall — classic glossy inflatable beach ball with red, yellow,
    //     and blue wedge panels.  Available ONLY via the Summer Vibes
    //     seasonal bundle (Jun–Sep 2026); never coin-purchasable and hidden
    //     from the regular shop grid.
    case beachBall = "Beach Ball"

    // ── Halloween 2026 seasonal exclusive ────────────────────────────────
    //   • pumpkin — Jack-o'-lantern sphere with five vertical rib lines, a
    //     warm amber inner glow, triangular eyes, a jagged toothed grin, and
    //     a small curved stem.  Available ONLY via the Trick or Roll bundle
    //     (Oct 2026); never coin-purchasable and hidden from the regular
    //     shop grid.
    case pumpkin  = "Pumpkin"

    // ── Winter 2026 seasonal exclusive ───────────────────────────────────
    //   • ornament — mirror-glossy deep crimson Christmas ornament with a
    //     gold metallic cap, thin equatorial gold stripe, an oversized
    //     specular highlight (sells the mirror-glass quality), and a small
    //     caustic reflection.  Available ONLY via the Winter Wonderland
    //     bundle (Dec 2026–Jan 2027); never coin-purchasable and hidden
    //     from the regular shop grid.
    case ornament = "Ornament"

    var id: String { rawValue }

    /// Multiplier on the in-game ball radius (rendering AND physics).
    /// Every skin is full-size (1.0) except Pluto, the demoted dwarf
    /// planet, which rolls at half size for a distinct challenge.
    var radiusScale: CGFloat {
        switch self {
        case .pluto: return 0.5
        default:     return 1.0
        }
    }

    /// True for skins that can ONLY be obtained through a bundle — they
    /// are hidden from the standalone shop's individual Ball grid.
    var isBundleExclusive: Bool {
        switch self {
        case .pluto, .aurora, .beachBall, .pumpkin, .ornament: return true
        default:                          return false
        }
    }

    func gradient(endRadius: CGFloat) -> RadialGradient {
        RadialGradient(
            colors: colors,
            center: UnitPoint(x: 0.30, y: 0.30),
            startRadius: 0,
            endRadius: endRadius
        )
    }

    /// 4-stop radial palette: light highlight → mid → shadow → deep
    /// shadow.  Picked to read clearly on every BackgroundTheme.
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
        case .purple:
            return [
                Color(red: 0.92, green: 0.76, blue: 1.00),
                Color(red: 0.65, green: 0.15, blue: 0.96),
                Color(red: 0.38, green: 0.05, blue: 0.62),
                Color(red: 0.18, green: 0.02, blue: 0.32),
            ]
        case .rose:
            return [
                Color(red: 1.00, green: 0.88, blue: 0.92),
                Color(red: 0.98, green: 0.45, blue: 0.62),
                Color(red: 0.70, green: 0.15, blue: 0.35),
                Color(red: 0.32, green: 0.04, blue: 0.14),
            ]
        case .coral:
            return [
                Color(red: 1.00, green: 0.92, blue: 0.82),
                Color(red: 1.00, green: 0.55, blue: 0.35),
                Color(red: 0.78, green: 0.28, blue: 0.12),
                Color(red: 0.36, green: 0.10, blue: 0.03),
            ]
        case .mint:
            return [
                Color(red: 0.86, green: 1.00, blue: 0.95),
                Color(red: 0.38, green: 0.86, blue: 0.72),
                Color(red: 0.10, green: 0.55, blue: 0.45),
                Color(red: 0.02, green: 0.22, blue: 0.18),
            ]
        case .slate:
            return [
                Color(red: 0.86, green: 0.88, blue: 0.92),
                Color(red: 0.46, green: 0.50, blue: 0.58),
                Color(red: 0.22, green: 0.26, blue: 0.34),
                Color(red: 0.08, green: 0.10, blue: 0.14),
            ]
        case .lemon:
            return [
                Color(red: 1.00, green: 1.00, blue: 0.78),
                Color(red: 1.00, green: 0.92, blue: 0.18),
                Color(red: 0.78, green: 0.62, blue: 0.04),
                Color(red: 0.34, green: 0.24, blue: 0.00),
            ]

        // ── Premium / Epic ──
        case .gold:
            return [
                Color(red: 1.00, green: 0.98, blue: 0.76),
                Color(red: 1.00, green: 0.80, blue: 0.10),
                Color(red: 0.76, green: 0.56, blue: 0.00),
                Color(red: 0.40, green: 0.28, blue: 0.00),
            ]
        case .silver:
            return [
                Color(red: 1.00, green: 1.00, blue: 1.00),
                Color(red: 0.85, green: 0.87, blue: 0.92),
                Color(red: 0.50, green: 0.54, blue: 0.62),
                Color(red: 0.20, green: 0.22, blue: 0.28),
            ]
        case .copper:
            return [
                Color(red: 1.00, green: 0.88, blue: 0.72),
                Color(red: 0.92, green: 0.55, blue: 0.30),
                Color(red: 0.60, green: 0.28, blue: 0.08),
                Color(red: 0.24, green: 0.10, blue: 0.02),
            ]
        case .jade:
            return [
                Color(red: 0.84, green: 1.00, blue: 0.92),
                Color(red: 0.22, green: 0.72, blue: 0.58),
                Color(red: 0.06, green: 0.40, blue: 0.30),
                Color(red: 0.02, green: 0.16, blue: 0.12),
            ]
        case .ruby:
            return [
                Color(red: 1.00, green: 0.78, blue: 0.84),
                Color(red: 0.88, green: 0.12, blue: 0.32),
                Color(red: 0.46, green: 0.02, blue: 0.14),
                Color(red: 0.18, green: 0.00, blue: 0.06),
            ]

        // ── Exclusive / Legendary ──
        case .galaxy:
            return [
                Color(red: 0.95, green: 0.95, blue: 1.00),
                Color(red: 0.55, green: 0.40, blue: 0.92),
                Color(red: 0.16, green: 0.08, blue: 0.52),
                Color(red: 0.04, green: 0.04, blue: 0.20),
            ]
        case .nebula:
            return [
                Color(red: 1.00, green: 0.82, blue: 0.95),
                Color(red: 0.85, green: 0.30, blue: 0.78),
                Color(red: 0.35, green: 0.08, blue: 0.55),
                Color(red: 0.08, green: 0.02, blue: 0.18),
            ]
        case .opal:
            return [
                Color(red: 1.00, green: 0.98, blue: 1.00),
                Color(red: 0.85, green: 0.92, blue: 1.00),
                Color(red: 0.55, green: 0.60, blue: 0.85),
                Color(red: 0.18, green: 0.22, blue: 0.42),
            ]
        case .snowglobe:
            // Static gradient used by previews + the home/settings/shop
            // pickers.  In-game the marble swaps to a bespoke animated
            // Canvas in `BallGameView.snowglobeMarble` (glass dome with
            // swirling snowflakes inside).  This palette reads as a
            // pale frosted glass ball at-rest.
            return [
                Color(red: 0.96, green: 0.98, blue: 1.00),
                Color(red: 0.78, green: 0.88, blue: 0.98),
                Color(red: 0.40, green: 0.56, blue: 0.78),
                Color(red: 0.12, green: 0.22, blue: 0.38),
            ]
        case .golfBall:
            // Static gradient — used by previews and the home/settings
            // pickers.  In-game the dimples render on top via the
            // bespoke `golfBallMarble` Canvas in BallGameView.
            return [
                Color(red: 1.00, green: 1.00, blue: 1.00),
                Color(red: 0.94, green: 0.94, blue: 0.92),
                Color(red: 0.75, green: 0.75, blue: 0.72),
                Color(red: 0.45, green: 0.45, blue: 0.42),
            ]

        // ── Planets bundle ──
        case .earth:
            // Blue oceans → green landmass → deep navy night side.
            return [
                Color(red: 0.72, green: 0.90, blue: 1.00),
                Color(red: 0.20, green: 0.52, blue: 0.85),
                Color(red: 0.10, green: 0.42, blue: 0.24),
                Color(red: 0.02, green: 0.10, blue: 0.26),
            ]
        case .mars:
            // The rusty red planet — pale dust → iron oxide → dark crust.
            return [
                Color(red: 1.00, green: 0.78, blue: 0.58),
                Color(red: 0.86, green: 0.42, blue: 0.22),
                Color(red: 0.55, green: 0.20, blue: 0.10),
                Color(red: 0.26, green: 0.08, blue: 0.04),
            ]
        case .saturn:
            // Pale gold gas giant.  The signature rings paint on top via
            // the bespoke `saturnMarble` Canvas in BallGameView.
            return [
                Color(red: 1.00, green: 0.96, blue: 0.80),
                Color(red: 0.92, green: 0.80, blue: 0.52),
                Color(red: 0.66, green: 0.50, blue: 0.26),
                Color(red: 0.34, green: 0.24, blue: 0.10),
            ]
        case .mercury:
            // Cratered grey-brown, sun-scorched.
            return [
                Color(red: 0.88, green: 0.84, blue: 0.78),
                Color(red: 0.60, green: 0.56, blue: 0.50),
                Color(red: 0.36, green: 0.32, blue: 0.28),
                Color(red: 0.14, green: 0.12, blue: 0.10),
            ]
        case .neptune:
            // Deep azure ice giant.
            return [
                Color(red: 0.66, green: 0.84, blue: 1.00),
                Color(red: 0.20, green: 0.42, blue: 0.92),
                Color(red: 0.08, green: 0.18, blue: 0.62),
                Color(red: 0.02, green: 0.06, blue: 0.30),
            ]
        case .jupiter:
            // Banded tan / orange giant with a deep-red storm at the core.
            return [
                Color(red: 1.00, green: 0.92, blue: 0.78),
                Color(red: 0.90, green: 0.68, blue: 0.44),
                Color(red: 0.70, green: 0.34, blue: 0.20),
                Color(red: 0.42, green: 0.14, blue: 0.10),
            ]
        case .venus:
            // Pale cream → sulphur-yellow → amber cloud tops.
            return [
                Color(red: 1.00, green: 0.96, blue: 0.80),
                Color(red: 0.96, green: 0.82, blue: 0.42),
                Color(red: 0.78, green: 0.54, blue: 0.18),
                Color(red: 0.42, green: 0.26, blue: 0.06),
            ]
        case .uranus:
            // Pale cyan ice giant — cooler + lighter than Neptune.
            return [
                Color(red: 0.82, green: 1.00, blue: 1.00),
                Color(red: 0.46, green: 0.86, blue: 0.88),
                Color(red: 0.16, green: 0.56, blue: 0.62),
                Color(red: 0.04, green: 0.26, blue: 0.32),
            ]
        case .pluto:
            // Icy beige dwarf — pale nitrogen ice → tan → dark crust.
            return [
                Color(red: 1.00, green: 0.94, blue: 0.84),
                Color(red: 0.84, green: 0.70, blue: 0.56),
                Color(red: 0.54, green: 0.40, blue: 0.32),
                Color(red: 0.26, green: 0.18, blue: 0.14),
            ]
        case .ufo:
            // Static fallback — metallic steel saucer.  In-game the
            // bespoke animated `ufoMarble` Canvas takes over (glowing
            // green dome + rotating belly lights).
            return [
                Color(red: 0.82, green: 0.88, blue: 0.92),
                Color(red: 0.55, green: 0.62, blue: 0.70),
                Color(red: 0.30, green: 0.36, blue: 0.44),
                Color(red: 0.12, green: 0.16, blue: 0.22),
            ]

        // ── Round-4 themed bundles ──
        case .pastel:
            // Soft multi-pastel: pale pink highlight → blush → periwinkle
            // → mint shadow.  Reads as a gentle candy marble.
            return [
                Color(red: 1.00, green: 0.93, blue: 0.97),
                Color(red: 0.98, green: 0.78, blue: 0.90),
                Color(red: 0.74, green: 0.80, blue: 0.98),
                Color(red: 0.55, green: 0.84, blue: 0.80),
            ]
        case .neon:
            // Electric magenta → violet → blue.  Bright, club-lit.
            return [
                Color(red: 1.00, green: 0.86, blue: 1.00),
                Color(red: 1.00, green: 0.10, blue: 0.90),
                Color(red: 0.45, green: 0.05, blue: 0.85),
                Color(red: 0.05, green: 0.40, blue: 0.95),
            ]
        case .soccer:
            // White sphere base — the black pentagons paint on top via
            // the bespoke `soccerMarble` Canvas in BallGameView.
            return [
                Color(red: 1.00, green: 1.00, blue: 1.00),
                Color(red: 0.95, green: 0.95, blue: 0.95),
                Color(red: 0.72, green: 0.72, blue: 0.72),
                Color(red: 0.42, green: 0.42, blue: 0.42),
            ]
        case .aquarium:
            // Translucent aqua glass — bright cyan highlight → teal →
            // deep sea.  Bubbles paint on top via the bespoke
            // `aquariumMarble` Canvas in BallGameView.
            return [
                Color(red: 0.80, green: 0.98, blue: 0.98),
                Color(red: 0.36, green: 0.84, blue: 0.92),
                Color(red: 0.10, green: 0.55, blue: 0.72),
                Color(red: 0.03, green: 0.26, blue: 0.40),
            ]
        case .marble:
            // Clear glass base — near-white highlight → pale grey-blue →
            // refractive rim.  The cobalt cat's-eye swirl paints on top
            // via the bespoke `glassMarble` Canvas in BallGameView.
            return [
                Color(red: 0.96, green: 0.99, blue: 1.00),
                Color(red: 0.85, green: 0.90, blue: 0.96),
                Color(red: 0.62, green: 0.70, blue: 0.82),
                Color(red: 0.30, green: 0.38, blue: 0.52),
            ]

        // ── Round-5 themed bundles ──
        case .dune:
            // Desert at dusk — pale sand → golden ochre → terracotta →
            // cool violet shadow.  Spans warm hues into a dusk shadow,
            // reading as a layered sandstone marble (Epic).
            return [
                Color(red: 0.98, green: 0.92, blue: 0.74),
                Color(red: 0.86, green: 0.66, blue: 0.34),
                Color(red: 0.64, green: 0.34, blue: 0.22),
                Color(red: 0.26, green: 0.16, blue: 0.30),
            ]
        case .storm:
            // Dark storm cloud — pale grey highlight → slate → deep navy.
            // The lightning bolt + cloud puffs paint on top via the
            // bespoke `stormMarble` Canvas in BallGameView.
            return [
                Color(red: 0.66, green: 0.70, blue: 0.78),
                Color(red: 0.36, green: 0.42, blue: 0.52),
                Color(red: 0.16, green: 0.20, blue: 0.30),
                Color(red: 0.05, green: 0.07, blue: 0.14),
            ]
        case .candy:
            // Glossy candy red — bright cherry highlight → deep red.  The
            // white peppermint pinwheel paints on top via the bespoke
            // `candyMarble` Canvas in BallGameView.
            return [
                Color(red: 1.00, green: 0.62, blue: 0.66),
                Color(red: 0.92, green: 0.20, blue: 0.28),
                Color(red: 0.74, green: 0.08, blue: 0.18),
                Color(red: 0.46, green: 0.03, blue: 0.10),
            ]
        case .ghost:
            // Luminous pale spirit — soft white core fading to a cold
            // blue-grey rim.  The eyes + mouth paint on top via the bespoke
            // `ghostMarble` Canvas in BallGameView.
            return [
                Color(red: 0.97, green: 0.98, blue: 1.00),
                Color(red: 0.82, green: 0.86, blue: 0.94),
                Color(red: 0.58, green: 0.64, blue: 0.76),
                Color(red: 0.34, green: 0.40, blue: 0.54),
            ]

        // ── Sports skins (new) ──
        case .basketball:
            // Fallback gradient — bright orange highlight → deep terracotta.
            // The bespoke Canvas renderer in BallSkinView is the real display path.
            return [
                Color(red: 1.00, green: 0.78, blue: 0.38),
                Color(red: 0.92, green: 0.44, blue: 0.06),
                Color(red: 0.68, green: 0.24, blue: 0.02),
                Color(red: 0.36, green: 0.10, blue: 0.01),
            ]
        case .eightBall:
            // Fallback gradient — near-black with subtle highlight.
            return [
                Color(red: 0.30, green: 0.30, blue: 0.32),
                Color(red: 0.10, green: 0.10, blue: 0.12),
                Color(red: 0.04, green: 0.04, blue: 0.06),
                Color.black,
            ]
        case .baseball:
            // Fallback gradient — off-white leather.
            return [
                Color.white,
                Color(red: 0.95, green: 0.93, blue: 0.88),
                Color(red: 0.78, green: 0.74, blue: 0.68),
                Color(red: 0.54, green: 0.48, blue: 0.42),
            ]

        // ── Starter Pack exclusive ──
        case .aurora:
            // Northern Lights — icy highlight → vivid teal-green aurora →
            // deep violet sky → near-black midnight.  Fallback for any static
            // context that doesn't go through BallSkinView's animated Canvas.
            return [
                Color(red: 0.88, green: 1.00, blue: 0.96),
                Color(red: 0.20, green: 0.92, blue: 0.62),
                Color(red: 0.42, green: 0.10, blue: 0.72),
                Color(red: 0.04, green: 0.04, blue: 0.18),
            ]

        // ── Summer 2026 seasonal exclusive ──
        case .beachBall:
            // Classic inflatable beach ball — vivid primary panels (red,
            // yellow, blue) painted by the bespoke beachBallCanvas in
            // BallSkinView.  This fallback gradient reads as a bright,
            // toy-coloured sphere in static contexts (settings picker, etc.).
            return [
                Color(red: 1.00, green: 0.78, blue: 0.60),
                Color(red: 0.96, green: 0.30, blue: 0.30),
                Color(red: 0.22, green: 0.44, blue: 0.82),
                Color(red: 0.06, green: 0.18, blue: 0.40),
            ]

        // ── Halloween 2026 seasonal exclusive ──
        case .pumpkin:
            // Jack-o'-lantern — bright pumpkin-orange highlight → saturated
            // orange → deep burnt-sienna shadow.  Ribs, stem, eyes, and grin
            // paint on top via the bespoke pumpkinCanvas in BallSkinView.
            return [
                Color(red: 1.00, green: 0.72, blue: 0.22),
                Color(red: 0.95, green: 0.44, blue: 0.08),
                Color(red: 0.62, green: 0.22, blue: 0.04),
                Color(red: 0.32, green: 0.10, blue: 0.01),
            ]

        // ── Winter 2026 seasonal exclusive ──
        case .ornament:
            // Christmas ornament — vivid crimson highlight → deep ruby red →
            // near-black shadow.  Gold cap, stripe, and specular paint on top
            // via the bespoke ornamentCanvas in BallSkinView.
            return [
                Color(red: 0.98, green: 0.60, blue: 0.60),
                Color(red: 0.86, green: 0.08, blue: 0.16),
                Color(red: 0.48, green: 0.02, blue: 0.08),
                Color(red: 0.18, green: 0.00, blue: 0.02),
            ]
        }
    }
}
