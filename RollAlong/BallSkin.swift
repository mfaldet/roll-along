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

    // Standard (750 coins)
    case blue   = "Ocean Blue"
    case green  = "Jade Green"
    case purple = "Deep Purple"
    case rose   = "Rose"
    case coral  = "Coral"
    case mint   = "Mint"
    case slate  = "Slate"
    case lemon  = "Lemon"

    // Premium / Epic (1,250 coins)
    case gold   = "Fool's Gold"
    case silver = "Silver"
    case copper = "Copper"
    case jade   = "Jade"
    case ruby   = "Ruby"

    // Exclusive / Legendary (1,500 coins) — animated / special-effect renderers
    case galaxy    = "Galaxy"          // animated spiral canvas (Legendary since audit 2026-07)
    case nebula    = "Nebula"          // animated nebula canvas (Legendary since audit 2026-07)
    case opal      = "Opal"            // multi-colour gradient
    case snowglobe = "Snowglobe"       // glass marble with swirling snow inside
    case golfBall  = "Golf Ball"       // white with dimples (Golf bundle)

    // Planets bundle (1,500 coins each, Legendary tier — multi-colour gradient marbles).
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

    // ── Round-6 bundle completion skins ─────────────────────────────────
    //   • disco — mirror-ball sphere of twinkling silver-violet facets
    //     (Nightclub bundle), via the bespoke animated `discoCanvas`.
    case disco = "Disco Ball"
    //   • paper — crumpled cream-paper sphere with shaded fold creases
    //     (Paper World bundle), via the bespoke static `paperCanvas`.
    case paper = "Paper"

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
    //   • lava — animated molten sphere with drifting dark amber blobs
    //     rising through a vivid orange-red magma field.  Coin-purchasable
    //     (exclusive tier, 1,500 coins); also included in the Lava Flow bundle.
    case lava       = "Lava"
    //   • trench — deep navy sphere with slowly pulsing bioluminescent teal
    //     dot clusters.  Animated Canvas; coin-purchasable (exclusive tier,
    //     1,500 coins); also included in the Abyssal Depths challenge bundle.
    case trench     = "Trench"

    // ── Golden Gauntlet exclusive (pack-exclusive, never coin-purchasable) ─
    //   • trophy — lustrous prize-gold sphere with a raised, iridescent
    //     rainbow champion star at its heart, a breathing victory halo, an
    //     orbiting specular, and twinkling glints.  Awarded ONLY by
    //     completing the Golden Gauntlet challenge track; hidden from the
    //     shop grid.
    case trophy     = "Trophy"

    // ── Aurora (Legendary, coin-buyable; anchors the Aurora bundle) ──────
    //   • aurora — deep midnight sphere with animated teal-green and violet
    //     Northern Lights bands and twinkling stars.  A regular coin-buyable
    //     Legendary ball and the centerpiece of the Aurora bundle; the legacy
    //     Starter Pack IAP grants the entire Aurora collection free-granted
    //     (see StoreKitManager.grantAuroraCollection).
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

    // ── Valentine's Day 2027 seasonal exclusive ─────────────────────────
    //   • heartstone — deep fuchsia sphere with a gold embossed heart.
    //     Available ONLY via the Sweetheart bundle (Feb 1–14, 2027); never
    //     coin-purchasable and hidden from the regular shop grid.
    case heartstone  = "Heartstone"

    // ── St. Patrick's Day 2027 seasonal exclusive ────────────────────────
    //   • shamrock — vivid forest-green sphere with a white 4-leaf clover.
    //     Available ONLY via the Luck of the Roll bundle (Mar 1–17, 2027);
    //     never coin-purchasable and hidden from the regular shop grid.
    case shamrock    = "Shamrock"

    // ── New Year's 2027 seasonal exclusive ──────────────────────────────
    //   • confetti — champagne-gold sphere with scattered multicolor confetti
    //     squares. Available ONLY via the Countdown bundle (Dec 28 – Jan 4);
    //     never coin-purchasable and hidden from the regular shop grid.
    case confetti    = "Confetti"

    // ── Spring 2027 seasonal exclusive ──────────────────────────────────
    //   • speckledEgg — robin's-egg blue sphere with dark freckle speckles.
    //     Available ONLY via the Spring Fling bundle (Mar 20 – May 1, 2027);
    //     never coin-purchasable and hidden from the regular shop grid.
    case speckledEgg = "Speckled Egg"

    // ── Diamond Balls IAP exclusive ──────────────────────────────────────
    //   • diamond — brilliant white-cyan cut gem.  Granted ONLY by the
    //     one-time "Diamond Balls" unlimited-lives purchase; never coin-
    //     purchasable and hidden from the regular shop grid.
    case diamond = "Diamond"

    // ── top-coin-pack ($49.99) IAP secret exclusive ─────────────────────────────────
    //   • moneyBall — a rolled-up wad of dollar bills.  One of three "Money"
    //     cosmetics granted at random ONLY by the $49.99 top coin pack (historical ID coins.10000);
    //     never coin-purchasable and hidden from the shop grid.
    case moneyBall = "Money Ball"

    // ── Premium bundle skins (coin/bundle purchasable — NOT bundle-exclusive) ─
    //   • highRoller — casino roulette wheel: alternating deep-red and black
    //     wedges inside a gold-rimmed rim with a crisp white centre pip and a
    //     glossy specular.  Static.  High Roller bundle (Legendary).
    case highRoller  = "High Roller"
    //   • quicksilver — perfectly reflective liquid-chrome blob (T-1000): a
    //     steely silver MeshGradient with a bright roving specular highlight.
    //     Animated.  Quicksilver bundle (Legendary).
    case quicksilver = "Quicksilver"
    //   • oracle — smoky violet fortune crystal: swirling inner fog with a tiny
    //     galaxy/star core glowing through; deep purples + magenta.  Animated.
    //     Oracle bundle (Legendary).
    case oracle      = "Oracle"
    //   • geode — cracked-open agate: banded amethyst rings around the rim with
    //     a sparkly druzy (crystalline) centre catching light; purples + quartz
    //     white.  Static-but-twinkling.  Geode bundle (Epic).
    case geode       = "Geode"
    //   • lavaLamp — retro lava lamp: fat warm-orange/coral wax blobs slowly
    //     rising, merging and splitting inside a magenta-violet fluid with a
    //     soft glow.  Animated.  Lava Lamp bundle (Epic).
    case lavaLamp    = "Lava Lamp"
    //   • plasmaGlobe — Tesla plasma globe: electric magenta/cyan tendrils
    //     arcing from a bright central electrode to the glass, flickering and
    //     rerouting over a dark interior.  Animated.  Plasma Globe bundle (Legendary).
    case plasmaGlobe = "Plasma Globe"
    //   • cathedral — stained-glass rosette window: jewel-tone panes (ruby,
    //     cobalt, emerald, amber) divided by dark leaded cames radiating from
    //     the centre, with light glinting through.  Subtle shimmer.  Cathedral
    //     bundle (Epic).
    case cathedral   = "Cathedral"
    //   • magmaCore — dark obsidian/basalt shell with glowing molten-orange
    //     fracture seams pulsing as if lava flows beneath; drifting embers.
    //     Animated.  Magma Core bundle (Legendary).
    case magmaCore   = "Magma Core"
    //   • hologram — glitchy holographic sphere: translucent cyan/magenta with
    //     horizontal scanlines, chromatic-aberration edges, and occasional
    //     flicker/jitter; sci-fi HUD feel.  Animated.  Neon City bundle (Legendary).
    case hologram    = "Hologram"
    //   • clockwork — interlocking brass/copper gears meshing and slowly
    //     rotating over a warm metal body; rivets, patina, a polished sheen.
    //     Animated rotation.  Clockwork bundle (Legendary).
    case clockwork   = "Clockwork"

    // ── Seasonal bundle skins (catalogue + real-money IAP — NOT bundle-exclusive) ─
    //   • fireworks — dark night-sky sphere with bursting red / white / blue
    //     firework shells and falling sparks; celebratory.  Animated, Reduce-
    //     Motion-safe.  Star-Spangled bundle (Legendary).
    case fireworks   = "Fireworks"
    //   • sugarSkull — ornate white calavera (sugar skull) decorated with
    //     marigold-orange and rose floral patterns; bright and festive.  Static.
    //     Día de los Muertos bundle (Legendary).
    case sugarSkull  = "Sugar Skull"
    //   • harvest — warm amber-to-maple gradient sphere with a subtle autumn-
    //     leaf motif; cozy fall tones.  Static.  Harvest Moon bundle (Legendary).
    case harvest     = "Harvest Moon"
    //   • lunarDragon — deep-red lacquer sphere with gold dragon-scale texture
    //     and filigree; a regal sheen with a subtle Reduce-Motion-safe shimmer.
    //     Year of the Dragon bundle (Legendary).
    case lunarDragon = "Golden Dragon"
    //   • mardiGras — festive harlequin-diamond pattern in royal purple,
    //     emerald green, and gold with a jeweled bead-like sheen.  Static.
    //     Mardi Gras bundle (Legendary).
    case mardiGras   = "Mardi Gras"
    //   • spectrum — bold glossy six-colour rainbow sphere (red/orange/yellow/
    //     green/blue/violet bands) with a bright specular highlight.  Static.
    //     Spectrum bundle (Legendary).
    case spectrum    = "Spectrum"
    //   • oktoberfest — Bavarian blue-and-white diamond (lozenge) pattern with
    //     warm pretzel-gold accents and a creamy foam highlight at the top.
    //     Festive beer-hall feel.  Static.  Oktoberfest seasonal (Legendary).
    case oktoberfest = "Oktoberfest"
    //   • apple — glossy classic-red teacher's apple with a small green leaf,
    //     brown stem, and a bright specular highlight.  Clean and cheerful.
    //     Static.  Back to School seasonal (Legendary).
    case apple       = "Teacher's Apple"

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
        case .pluto, .beachBall, .pumpkin, .ornament,
             .heartstone, .shamrock, .confetti, .speckledEgg,
             .trophy,    // Golden Gauntlet completion exclusive
             .diamond,   // Diamond Balls IAP exclusive
             .moneyBall: // top-coin-pack ($49.99) IAP secret exclusive
            return true
        // Aurora was the Starter Pack IAP exclusive; that pack is retired, so
        // Aurora is now a regular coin-buyable Legendary ball (and the anchor of
        // the Aurora bundle) — no longer bundle-locked.
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

    /// First (highlight) colour of the skin's radial palette.  Handy as a
    /// lightweight tint / glow accent without constructing a full gradient.
    var highlightColor: Color { colors.first ?? .white }

    /// 4-stop radial palette: light highlight → mid → shadow → deep
    /// shadow.  Picked to read clearly on every BackgroundTheme.
    /// The skin's gradient palette (highlight → mid → dark → deep).  Exposed so
    /// BallSkinView's premium renderers (gloss / metal / gem) can build a richer
    /// marble than a flat gradient from the same colours.
    var colors: [Color] {
        switch self {
        case .red:
            return [
                Color(red: 1.00, green: 0.85, blue: 0.85),
                Color(red: 0.95, green: 0.20, blue: 0.20),
                Color(red: 0.55, green: 0.05, blue: 0.05),
                Color(red: 0.25, green: 0.02, blue: 0.02),
            ]
        case .disco:
            return [
                Color(red: 0.95, green: 0.95, blue: 1.00),
                Color(red: 0.70, green: 0.72, blue: 0.86),
                Color(red: 0.38, green: 0.40, blue: 0.55),
                Color(red: 0.14, green: 0.14, blue: 0.22),
            ]
        case .paper:
            return [
                Color(red: 1.00, green: 0.99, blue: 0.95),
                Color(red: 0.90, green: 0.89, blue: 0.82),
                Color(red: 0.66, green: 0.64, blue: 0.58),
                Color(red: 0.40, green: 0.39, blue: 0.35),
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

        case .lava:
            // Molten lava — pale incandescent highlight → vivid orange →
            // deep ember red → near-black scorched crust.  Animated blobs
            // are rendered by lavaCanvas in BallSkinView; this gradient
            // is the static fallback used by shop thumbnails, etc.
            return [
                Color(red: 1.00, green: 0.60, blue: 0.20),
                Color(red: 0.95, green: 0.30, blue: 0.08),
                Color(red: 0.65, green: 0.10, blue: 0.02),
                Color(red: 0.28, green: 0.04, blue: 0.00),
            ]

        case .trench:
            // Abyssal deep — pale bioluminescent cyan highlight → dark navy →
            // near-black abyssal blue.  Animated glowing dot clusters are
            // rendered by trenchCanvas in BallSkinView.
            return [
                Color(red: 0.42, green: 0.92, blue: 0.88),
                Color(red: 0.06, green: 0.22, blue: 0.48),
                Color(red: 0.02, green: 0.08, blue: 0.24),
                Color(red: 0.01, green: 0.02, blue: 0.10),
            ]

        case .trophy:
            // Polished prize gold — bright crown highlight → rich gold → bronze
            // → deep bronze rim.  Static fallback; the champion star, halo,
            // orbiting specular and glints are rendered by trophyCanvas.
            return [
                Color(red: 1.00, green: 0.97, blue: 0.72),
                Color(red: 0.99, green: 0.81, blue: 0.28),
                Color(red: 0.66, green: 0.45, blue: 0.08),
                Color(red: 0.16, green: 0.10, blue: 0.01),
            ]

        // ── Aurora (Legendary; anchors the Aurora bundle) ──
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

        // ── Valentine's Day 2027 ──
        case .heartstone:
            // Deep fuchsia sphere — rosy highlight → hot pink → deep magenta →
            // near-black shadow.  Gold embossed heart paints on top via the
            // bespoke heartstoneCanvas in BallSkinView.
            return [
                Color(red: 0.98, green: 0.72, blue: 0.82),
                Color(red: 0.92, green: 0.22, blue: 0.56),
                Color(red: 0.62, green: 0.06, blue: 0.30),
                Color(red: 0.28, green: 0.02, blue: 0.12),
            ]

        // ── St. Patrick's Day 2027 ──
        case .shamrock:
            // Vivid forest-green sphere — light spring-green highlight →
            // saturated green → dark forest → near-black shadow.  White
            // 4-leaf clover with gold stem paints on top via shamrockCanvas.
            return [
                Color(red: 0.68, green: 0.98, blue: 0.48),
                Color(red: 0.18, green: 0.74, blue: 0.22),
                Color(red: 0.06, green: 0.42, blue: 0.10),
                Color(red: 0.02, green: 0.16, blue: 0.04),
            ]

        // ── New Year's 2027 ──
        case .confetti:
            // Champagne-gold sphere — bright warm highlight → golden mid →
            // rich amber → deep shadow.  Scattered multicolor confetti squares
            // paint on top via the bespoke confettiCanvas in BallSkinView.
            return [
                Color(red: 1.00, green: 0.96, blue: 0.80),
                Color(red: 0.94, green: 0.78, blue: 0.32),
                Color(red: 0.70, green: 0.52, blue: 0.14),
                Color(red: 0.36, green: 0.24, blue: 0.04),
            ]

        // ── Spring 2027 ──
        case .speckledEgg:
            // Robin's-egg blue sphere — pale sky highlight → mid robin blue →
            // deeper teal-blue → dark shadow.  Dark oval speckles paint on top
            // via the bespoke speckledEggCanvas in BallSkinView.
            return [
                Color(red: 0.82, green: 0.96, blue: 0.98),
                Color(red: 0.46, green: 0.82, blue: 0.90),
                Color(red: 0.22, green: 0.60, blue: 0.76),
                Color(red: 0.08, green: 0.28, blue: 0.44),
            ]

        // ── Diamond Balls IAP exclusive ──
        case .diamond:
            // Brilliant white → ice-blue → cyan → deep blue.  A cut-gem
            // renderer (facets + glints) paints on top in BallSkinView.
            return [
                Color.white,
                Color(red: 0.80, green: 0.95, blue: 1.00),
                Color(red: 0.50, green: 0.78, blue: 0.98),
                Color(red: 0.22, green: 0.45, blue: 0.74),
            ]

        // ── top-coin-pack ($49.99) IAP secret exclusive ──
        case .moneyBall:
            // Currency green → the rolled-bill renderer paints paper + $ on top.
            return [
                Color(red: 0.74, green: 0.86, blue: 0.70),
                Color(red: 0.45, green: 0.66, blue: 0.46),
                Color(red: 0.20, green: 0.42, blue: 0.26),
                Color(red: 0.09, green: 0.22, blue: 0.14),
            ]

        // ── Premium bundle skins ─────────────────────────────────────────────
        case .highRoller:
            // Casino felt-red → deep crimson → black, gold-warm highlight.
            // The roulette wedges + gold rim + white pip paint on top via the
            // bespoke highRollerCanvas in BallSkinView.
            return [
                Color(red: 1.00, green: 0.86, blue: 0.55),
                Color(red: 0.78, green: 0.10, blue: 0.12),
                Color(red: 0.34, green: 0.03, blue: 0.05),
                Color(red: 0.08, green: 0.02, blue: 0.03),
            ]

        case .quicksilver:
            // Bright chrome highlight → cool steely silver → slate → near-black.
            // The liquid-chrome MeshGradient + roving specular paint on top via
            // the bespoke quicksilverCanvas in BallSkinView.
            return [
                Color(red: 0.97, green: 0.98, blue: 1.00),
                Color(red: 0.74, green: 0.80, blue: 0.88),
                Color(red: 0.40, green: 0.46, blue: 0.56),
                Color(red: 0.10, green: 0.13, blue: 0.18),
            ]

        case .oracle:
            // Pale magenta highlight → violet → deep purple → near-black.  The
            // swirling fog + glowing galaxy core paint on top via the bespoke
            // oracleCanvas in BallSkinView.
            return [
                Color(red: 0.86, green: 0.62, blue: 0.98),
                Color(red: 0.52, green: 0.22, blue: 0.78),
                Color(red: 0.24, green: 0.06, blue: 0.42),
                Color(red: 0.06, green: 0.02, blue: 0.14),
            ]

        case .geode:
            // Quartz-white highlight → lilac → amethyst → deep violet.  The
            // banded agate rings + druzy crystal core paint on top via the
            // bespoke geodeCanvas in BallSkinView.
            return [
                Color(red: 0.97, green: 0.93, blue: 1.00),
                Color(red: 0.74, green: 0.52, blue: 0.86),
                Color(red: 0.46, green: 0.24, blue: 0.62),
                Color(red: 0.20, green: 0.08, blue: 0.34),
            ]

        case .lavaLamp:
            // Warm coral-orange wax highlight → orange → magenta-violet fluid →
            // deep purple.  The rising/merging wax blobs paint on top via the
            // bespoke lavaLampCanvas in BallSkinView.
            return [
                Color(red: 1.00, green: 0.76, blue: 0.46),
                Color(red: 0.98, green: 0.46, blue: 0.30),
                Color(red: 0.58, green: 0.14, blue: 0.52),
                Color(red: 0.18, green: 0.04, blue: 0.26),
            ]

        case .plasmaGlobe:
            // Bright electrode magenta-white highlight → magenta → cyan-violet →
            // near-black interior.  The arcing electric tendrils paint on top via
            // the bespoke plasmaGlobeCanvas in BallSkinView.
            return [
                Color(red: 0.98, green: 0.80, blue: 1.00),
                Color(red: 0.82, green: 0.24, blue: 0.92),
                Color(red: 0.24, green: 0.28, blue: 0.70),
                Color(red: 0.03, green: 0.02, blue: 0.10),
            ]

        case .cathedral:
            // Amber-gold glint → ruby → cobalt → deep leaded-black.  The radiating
            // stained-glass rosette of jewel-tone panes paints on top via the
            // bespoke cathedralCanvas in BallSkinView.
            return [
                Color(red: 1.00, green: 0.86, blue: 0.42),
                Color(red: 0.82, green: 0.14, blue: 0.22),
                Color(red: 0.14, green: 0.24, blue: 0.66),
                Color(red: 0.06, green: 0.05, blue: 0.10),
            ]

        case .magmaCore:
            // Molten-orange seam glow → ember orange → basalt grey → obsidian
            // black.  The cracked crust + pulsing molten fracture seams paint on
            // top via the bespoke magmaCoreCanvas in BallSkinView.
            return [
                Color(red: 1.00, green: 0.78, blue: 0.30),
                Color(red: 0.96, green: 0.42, blue: 0.10),
                Color(red: 0.26, green: 0.22, blue: 0.22),
                Color(red: 0.05, green: 0.04, blue: 0.05),
            ]

        case .hologram:
            // Bright cyan highlight → magenta mid → deep indigo → near-black
            // interior.  The translucent scanlines, chromatic-aberration edges
            // and flicker/jitter paint on top via the bespoke hologramCanvas
            // in BallSkinView.
            return [
                Color(red: 0.62, green: 1.00, blue: 0.98),
                Color(red: 0.90, green: 0.26, blue: 0.92),
                Color(red: 0.16, green: 0.18, blue: 0.46),
                Color(red: 0.02, green: 0.03, blue: 0.10),
            ]

        case .clockwork:
            // Polished brass glint → warm copper → aged bronze → dark patina.
            // The meshing/rotating gears, rivets and engraved sheen paint on top
            // via the bespoke clockworkCanvas in BallSkinView.
            return [
                Color(red: 1.00, green: 0.88, blue: 0.56),
                Color(red: 0.84, green: 0.58, blue: 0.24),
                Color(red: 0.52, green: 0.34, blue: 0.14),
                Color(red: 0.18, green: 0.12, blue: 0.07),
            ]

        // ── Seasonal bundle skins ─────────────────────────────────────────────
        case .fireworks:
            // Dark indigo night sky — faint top glow → deep navy → near-black
            // horizon.  The bursting red/white/blue shells and falling sparks
            // paint on top via the bespoke fireworksCanvas in BallSkinView.
            return [
                Color(red: 0.18, green: 0.20, blue: 0.42),
                Color(red: 0.06, green: 0.08, blue: 0.24),
                Color(red: 0.02, green: 0.03, blue: 0.12),
                Color(red: 0.00, green: 0.01, blue: 0.05),
            ]

        case .sugarSkull:
            // Bright bone-white calavera — pure white highlight → ivory → warm
            // shadow.  The marigold-orange and rose floral decorations paint on
            // top via the bespoke sugarSkullCanvas in BallSkinView.
            return [
                Color(red: 1.00, green: 1.00, blue: 0.99),
                Color(red: 0.96, green: 0.95, blue: 0.90),
                Color(red: 0.80, green: 0.76, blue: 0.68),
                Color(red: 0.48, green: 0.42, blue: 0.36),
            ]

        case .harvest:
            // Warm autumn moon — pale gold highlight → amber → maple-orange →
            // deep russet shadow.  The subtle autumn-leaf motif paints on top
            // via the bespoke harvestCanvas in BallSkinView.
            return [
                Color(red: 1.00, green: 0.90, blue: 0.62),
                Color(red: 0.94, green: 0.66, blue: 0.28),
                Color(red: 0.74, green: 0.40, blue: 0.14),
                Color(red: 0.38, green: 0.18, blue: 0.06),
            ]

        case .lunarDragon:
            // Deep-red lacquer sphere — bright gilt highlight → vivid lacquer
            // red → deep oxblood → near-black shadow.  The gold dragon-scale
            // texture, filigree, and shimmer paint on top via the bespoke
            // lunarDragonCanvas in BallSkinView.
            return [
                Color(red: 0.98, green: 0.82, blue: 0.42),
                Color(red: 0.78, green: 0.12, blue: 0.10),
                Color(red: 0.46, green: 0.05, blue: 0.06),
                Color(red: 0.16, green: 0.02, blue: 0.03),
            ]

        case .mardiGras:
            // Festive base — bright gold highlight → royal purple → emerald
            // green → deep aubergine shadow.  The harlequin-diamond pattern in
            // purple / green / gold and jeweled sheen paint on top via the
            // bespoke mardiGrasCanvas in BallSkinView.
            return [
                Color(red: 1.00, green: 0.86, blue: 0.30),
                Color(red: 0.42, green: 0.12, blue: 0.62),
                Color(red: 0.06, green: 0.52, blue: 0.24),
                Color(red: 0.14, green: 0.04, blue: 0.22),
            ]

        case .spectrum:
            // Bold rainbow base — bright specular white → warm red → cool blue
            // → deep violet shadow.  The six vivid red/orange/yellow/green/blue/
            // violet bands and bright highlight paint on top via the bespoke
            // spectrumCanvas in BallSkinView.
            return [
                Color(red: 1.00, green: 0.98, blue: 0.98),
                Color(red: 0.94, green: 0.22, blue: 0.20),
                Color(red: 0.16, green: 0.40, blue: 0.92),
                Color(red: 0.30, green: 0.08, blue: 0.46),
            ]

        case .oktoberfest:
            // Bavarian base — creamy foam-white highlight → bright Bavarian
            // blue → deeper sky blue → warm pretzel-gold shadow.  The blue/white
            // lozenge diamonds, gold accents, and foam cap paint on top via the
            // bespoke oktoberfestCanvas in BallSkinView.
            return [
                Color(red: 0.98, green: 0.97, blue: 0.92),
                Color(red: 0.16, green: 0.46, blue: 0.86),
                Color(red: 0.09, green: 0.32, blue: 0.66),
                Color(red: 0.74, green: 0.52, blue: 0.16),
            ]

        case .apple:
            // Glossy red apple — bright specular white → vivid apple red →
            // deep crimson → dark maroon shadow.  The leaf, stem, and wet
            // gloss highlight paint on top via the bespoke appleCanvas in
            // BallSkinView.
            return [
                Color(red: 1.00, green: 0.96, blue: 0.94),
                Color(red: 0.90, green: 0.16, blue: 0.16),
                Color(red: 0.62, green: 0.06, blue: 0.10),
                Color(red: 0.34, green: 0.03, blue: 0.06),
            ]
        }
    }
}
