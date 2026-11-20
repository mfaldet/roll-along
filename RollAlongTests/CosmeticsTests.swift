import XCTest
import SwiftUI
@testable import RollAlong

final class CosmeticsTests: XCTestCase {

    // MARK: - BallSkin gradient coverage

    /// Every BallSkin must be able to produce a RadialGradient without crashing.
    /// Regression guard: a new case added without a matching gradient definition
    /// will fall through to the "default" branch in BallSkin.colors — this test
    /// ensures the fallback is at least non-empty (the fallback in BallSkin.swift
    /// returns [.orange, .red, …]).
    func testAllBallSkins_gradientCallable() {
        for skin in BallSkin.allCases {
            // gradient(endRadius:) must not crash for any skin
            let gradient = skin.gradient(endRadius: 30)
            // RadialGradient always has a stops array; we're verifying it exists
            _ = gradient
        }
    }

    /// Every BallSkin must have a non-empty display name.
    func testAllBallSkins_haveDisplayName() {
        for skin in BallSkin.allCases {
            XCTAssertFalse(skin.displayName.isEmpty,
                           "BallSkin.\(skin.rawValue) has an empty displayName")
        }
    }

    // MARK: - isBundleExclusive consistency

    /// Bundle-exclusive skins are always top-tier (`.exclusive`).  They're kept
    /// out of the coin shop by CosmeticShopView's owned-or-hidden filter, NOT by
    /// price — `coinCost` reads through to `tier.basePrice` (1,500), so asserting a
    /// price of 0 would be wrong.  This guards against an event skin being
    /// mis-tiered into a cheap, coin-buyable slot.
    func testBundleExclusiveSkins_areExclusiveTier() {
        for skin in BallSkin.allCases where skin.isBundleExclusive {
            XCTAssertEqual(skin.tier, .exclusive,
                           "Bundle-exclusive skin \(skin.rawValue) must be .exclusive tier")
        }
    }

    /// The bundle-exclusive roster must exactly match the known event /
    /// bundle-locked set — catches a skin silently gaining or losing the flag.
    /// Note: rawValues are the *display* spellings, e.g. "Beach Ball" and
    /// "Speckled Egg" carry a space.
    func testBundleExclusiveSkins_flagIsConsistent() {
        let expected: Set<String> = [
            // Aurora is intentionally absent — it's a regular coin-buyable ball.
            // The Starter Pack GIFTS the Aurora ball (with its trail and boundary); it doesn't lock it.
            "Pluto", "Beach Ball", "Pumpkin", "Ornament",
            "Heartstone", "Shamrock", "Confetti", "Speckled Egg", "Trophy",
            "Diamond",     // Diamond Balls IAP exclusive
            "Money Ball"   // top-coin-pack ($49.99) IAP secret exclusive
        ]
        let actual = Set(BallSkin.allCases.filter { $0.isBundleExclusive }.map { $0.rawValue })
        XCTAssertEqual(actual, expected,
                       "Bundle-exclusive roster drifted from the expected set")
    }

    // MARK: - CosmeticBundle catalogue

    func testBundleCatalogue_isNonEmpty() {
        XCTAssertFalse(CosmeticBundle.catalogue.isEmpty,
                       "Bundle catalogue must have at least one bundle")
    }

    func testBundleCatalogue_allIDsAreUnique() {
        let ids = CosmeticBundle.catalogue.map { $0.id }
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count,
                       "Every CosmeticBundle must have a unique id")
    }

    func testBundleCatalogue_allBallSkinsAreValidCases() {
        let allSkinRawValues = Set(BallSkin.allCases.map { $0.rawValue })
        for bundle in CosmeticBundle.catalogue {
            for skin in bundle.balls {
                XCTAssertTrue(allSkinRawValues.contains(skin.rawValue),
                              "Bundle '\(bundle.id)' references unknown skin '\(skin.rawValue)'")
            }
        }
    }

    func testBundleCatalogue_displayNamesAreNonEmpty() {
        for bundle in CosmeticBundle.catalogue {
            XCTAssertFalse(bundle.displayName.isEmpty,
                           "Bundle '\(bundle.id)' has an empty displayName")
        }
    }

    // MARK: - CosmeticTier

    func testCosmeticTier_starterPriceIsZero() {
        XCTAssertEqual(CosmeticTier.starter.basePrice, 0)
    }

    /// The approved 2026-07 reprice (07-decisions ruling 2, shipped in
    /// 08-reprice): 750 / 1,000 / 1,250 / 1,500.  Every price must be EVEN
    /// forever — Sell Back refunds exactly half the CURRENT cost as an
    /// integer, so an odd price would truncate the refund.
    func testCosmeticTier_basePricesMatchApprovedLadderAndAreEven() {
        XCTAssertEqual(CosmeticTier.standard.basePrice,  750)
        XCTAssertEqual(CosmeticTier.rare.basePrice,      1000)
        XCTAssertEqual(CosmeticTier.premium.basePrice,   1250)
        XCTAssertEqual(CosmeticTier.exclusive.basePrice, 1500)
        for tier in [CosmeticTier.starter, .standard, .rare, .premium, .exclusive] {
            XCTAssertEqual(tier.basePrice % 2, 0,
                           "Tier \(tier) price must stay even so sell-back halves exactly")
        }
    }

    func testCosmeticTier_basePricesAreMonotonicallyIncreasing() {
        // Ordered from cheapest to most expensive
        let tiers: [CosmeticTier] = [.starter, .standard, .rare, .premium, .exclusive]
        var previous = -1
        for tier in tiers {
            XCTAssertGreaterThan(tier.basePrice, previous,
                                 "Tier \(tier) basePrice should be strictly greater than previous tier")
            previous = tier.basePrice
        }
    }

    // MARK: - BundleDiscount (Shop's randomized featured-bundle discount)

    /// A fresh GameState backed by an isolated UserDefaults suite so each
    /// test starts from a clean owned-set with no cross-test pollution.
    private func makeCleanState() -> GameState {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return GameState(defaults: defaults)
    }

    // MARK: - Equip on tap (GameState.equip — the one path every screen uses)

    func testEquip_ownedPieceEquipsInEverySlot() {
        let gs = makeCleanState()
        gs.ownedBallSkins.insert(BallSkin.jade.rawValue)
        gs.ownedGoals.insert(GoalSkin.meadow.rawValue)
        gs.ownedTrails.insert(TrailColor.forest.rawValue)
        gs.ownedFloors.insert(Floor.meadow.rawValue)
        gs.ownedPits.insert(Pit.meadow.rawValue)
        gs.ownedBoundaries.insert(Boundary.mint.rawValue)

        XCTAssertTrue(gs.equip(BallSkin.jade));    XCTAssertEqual(gs.activeSkin, .jade)
        XCTAssertTrue(gs.equip(GoalSkin.meadow));  XCTAssertEqual(gs.equippedGoal, .meadow)
        XCTAssertTrue(gs.equip(TrailColor.forest)); XCTAssertEqual(gs.equippedTrail, .forest)
        XCTAssertTrue(gs.equip(Floor.meadow));     XCTAssertEqual(gs.equippedFloor, .meadow)
        XCTAssertTrue(gs.equip(Pit.meadow));       XCTAssertEqual(gs.equippedPit, .meadow)
        XCTAssertTrue(gs.equip(Boundary.mint));    XCTAssertEqual(gs.equippedBoundary, .mint)
        for ok in [gs.isEquipped(BallSkin.jade), gs.isEquipped(GoalSkin.meadow),
                   gs.isEquipped(TrailColor.forest), gs.isEquipped(Floor.meadow),
                   gs.isEquipped(Pit.meadow), gs.isEquipped(Boundary.mint)] {
            XCTAssertTrue(ok)
        }
    }

    func testEquip_unownedPieceChangesNothing() {
        let gs = makeCleanState()
        let before = (gs.activeSkin, gs.equippedGoal, gs.equippedBoundary, gs.coinBalance)
        XCTAssertFalse(gs.isOwned(BallSkin.jade))
        XCTAssertFalse(gs.equip(BallSkin.jade))
        XCTAssertFalse(gs.equip(GoalSkin.meadow))
        XCTAssertFalse(gs.equip(Boundary.mint))
        XCTAssertEqual(gs.activeSkin, before.0)
        XCTAssertEqual(gs.equippedGoal, before.1)
        XCTAssertEqual(gs.equippedBoundary, before.2)
        XCTAssertEqual(gs.coinBalance, before.3)
        XCTAssertFalse(gs.isOwned(BallSkin.jade), "equipping must never grant or buy")
    }

    func testEquip_alreadyEquippedIsANoOp() {
        let gs = makeCleanState()
        gs.ownedTrails.insert(TrailColor.forest.rawValue)
        XCTAssertTrue(gs.equip(TrailColor.forest))
        XCTAssertFalse(gs.equip(TrailColor.forest), "second tap does nothing")
        XCTAssertEqual(gs.equippedTrail, .forest)
    }

    func testEquip_ballClearsAnEquippedPack() {
        let gs = makeCleanState()
        guard let pack = BallPack.catalogue.first else { return XCTFail("no packs") }
        gs.ownedPacks.insert(pack.id)
        gs.equipPack(pack)
        XCTAssertNotNil(gs.equippedPackID)
        gs.ownedBallSkins.insert(BallSkin.jade.rawValue)
        // While a pack shuffles, no single ball counts as equipped.
        XCTAssertFalse(gs.isEquipped(BallSkin.jade))
        XCTAssertTrue(gs.equip(BallSkin.jade))
        XCTAssertNil(gs.equippedPackID)
        XCTAssertEqual(gs.activeSkin, .jade)
        XCTAssertTrue(gs.isEquipped(BallSkin.jade))
    }

    /// Quality round: the Roll Along pieces carry their color in the name
    /// (ids unchanged), and Nature's goal is the new Leaf Wreath — a Standard
    /// piece like the Meadow goal it replaced, which is in no collection now.
    func testQualityRound_rollAlongNamesAndNatureGoal() {
        XCTAssertEqual(TrailColor.classic.displayName, "Classic Shadow")
        XCTAssertEqual(Floor.classic.displayName, "Classic White")
        XCTAssertEqual(Pit.classic.displayName, "Classic Black")
        XCTAssertEqual(Boundary.classic.displayName, "Classic Gray")
        XCTAssertEqual(TrailColor.classic.rawValue, "classic")
        XCTAssertEqual(Floor.classic.rawValue, "classic")
        XCTAssertEqual(Pit.classic.rawValue, "classic")
        XCTAssertEqual(Boundary.classic.rawValue, "classic")

        guard let nature = CosmeticBundle.catalogue.first(where: { $0.id == "nature" }) else {
            return XCTFail("nature collection missing")
        }
        XCTAssertEqual(nature.goals, [.leafWreath])
        XCTAssertEqual(GoalSkin.leafWreath.displayName, "Leaf Wreath")
        XCTAssertEqual(GoalSkin.leafWreath.tier, GoalSkin.meadow.tier)
        XCTAssertEqual(nature.fullPrice(), 4_500, "Nature's price is unchanged")
        for b in CosmeticBundle.catalogue {
            XCTAssertFalse(b.goals.contains(.meadow), "\(b.id) still holds the displaced Meadow goal")
            if b.id != "nature" {
                XCTAssertFalse(b.goals.contains(.leafWreath), "\(b.id) shares Nature's goal")
            }
        }
        // The Water floor now carries slow moving light; Fire's stays still.
        XCTAssertTrue(Floor.shallows.hasAnimatedOverlay)
        XCTAssertFalse(Floor.scorched.hasAnimatedOverlay)
    }

    /// Tapping an owned piece of a partially owned collection equips it and
    /// never buys the collection or touches coins.
    func testEquip_fromPartiallyOwnedCollection_neverPurchases() {
        let gs = makeCleanState()
        guard let nature = CosmeticBundle.catalogue.first(where: { $0.id == "nature" }) else {
            return XCTFail("nature collection missing")
        }
        gs.coinBalance = 50_000
        gs.ownedTrails.insert(TrailColor.forest.rawValue)     // 1 of 6 pieces
        let coins = gs.coinBalance
        let completed = gs.completedBundleIDs
        let ownedBalls = gs.ownedBallSkins

        XCTAssertTrue(gs.equip(TrailColor.forest))
        XCTAssertFalse(gs.equip(BallSkin.jade), "an unowned piece is not equipped here")

        XCTAssertEqual(gs.coinBalance, coins)
        XCTAssertEqual(gs.completedBundleIDs, completed)
        XCTAssertEqual(gs.ownedBallSkins, ownedBalls)
        XCTAssertFalse(gs.completedBundleIDs.contains(nature.id))
        XCTAssertEqual(gs.equippedTrail, .forest)
    }

    // MARK: - Reset Cosmetics (coin liquidation)

    func testLiquidate_refundsCoinItems_keepsExclusives_resetsLook() {
        let gs = makeCleanState()
        gs.coinBalance = 0
        gs.ownedBallSkins.insert(BallSkin.blue.rawValue)     // coin (standard)
        gs.ownedBallSkins.insert(BallSkin.diamond.rawValue)  // IAP-exclusive — keep
        gs.ownedGoals.insert(GoalSkin.galaxy.rawValue)        // coin (standard)
        gs.activeSkin   = .blue
        gs.equippedGoal = .galaxy

        let preview = gs.coinLiquidationPreview()
        XCTAssertEqual(preview.count, 2)   // .blue + .galaxy; .diamond excluded
        XCTAssertEqual(preview.coins, BallSkin.blue.coinCost / 2 + GoalSkin.galaxy.coinCost / 2)   // 50% refund

        let r = gs.liquidateCoinCosmetics()
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(gs.coinBalance, r.coins)                                // refunded
        XCTAssertFalse(gs.ownedBallSkins.contains(BallSkin.blue.rawValue))     // coin relocked
        XCTAssertFalse(gs.ownedGoals.contains(GoalSkin.galaxy.rawValue))
        XCTAssertTrue(gs.ownedBallSkins.contains(BallSkin.diamond.rawValue))   // exclusive kept
        XCTAssertEqual(gs.activeSkin, .red)        // look reset to default
        XCTAssertEqual(gs.equippedGoal, .target)
        XCTAssertTrue(gs.isLoadoutDefault)
    }

    func testLiquidate_resetsLookEvenWithNoCoinItems() {
        let gs = makeCleanState()
        gs.ownedBallSkins.insert(BallSkin.diamond.rawValue)  // kept exclusive, equipped
        gs.activeSkin = .diamond
        XCTAssertFalse(gs.isLoadoutDefault)

        let r = gs.liquidateCoinCosmetics()
        XCTAssertEqual(r.count, 0)                 // nothing to refund…
        XCTAssertEqual(gs.activeSkin, .red)        // …but the look still resets
        XCTAssertTrue(gs.ownedBallSkins.contains(BallSkin.diamond.rawValue))   // diamond re-equippable
        XCTAssertTrue(gs.isLoadoutDefault)
    }

    /// Sell Back re-grants every category's starter, so refunding a starter
    /// would mint coins on every pass.  (TrailColor's starter used to be
    /// Graphite — tier .rare — which slipped through the iconic filter and paid
    /// out on every Sell Back.  It is now the starter-tier Classic trail; the
    /// guard stays.)
    func testLiquidate_secondPassRefundsNothing_starterIsNotAFaucet() {
        let gs = makeCleanState()
        gs.coinBalance = 0
        gs.ownedBallSkins.insert(BallSkin.blue.rawValue)             // coin-bought
        gs.ownedTrails.insert(TrailColor.starter.rawValue)           // the starter (Classic)
        gs.ownedTrails.insert(TrailColor.fire.rawValue)              // coin-bought

        let first = gs.liquidateCoinCosmetics()
        XCTAssertEqual(first.count, 2)   // .blue + .fire; the starter NOT refunded
        XCTAssertEqual(first.coins, BallSkin.blue.coinCost / 2 + TrailColor.fire.coinCost / 2)   // 50% refund
        XCTAssertTrue(gs.ownedTrails.contains(TrailColor.starter.rawValue))    // starter kept

        let second = gs.liquidateCoinCosmetics()
        XCTAssertEqual(second.count, 0, "second consecutive Sell Back must refund nothing")
        XCTAssertEqual(second.coins, 0)
        XCTAssertEqual(gs.coinBalance, first.coins)   // balance unchanged by second pass

        // The preview must agree with liquidation — no phantom starter refunds
        // in the Danger-Zone confirm dialog either.
        let preview = gs.coinLiquidationPreview()
        XCTAssertEqual(preview.count, 0)
        XCTAssertEqual(preview.coins, 0)
    }

    /// No category's starter may ever be sellable, regardless of its tier.
    func testStarters_areNeverSellable() {
        XCTAssertFalse(BallSkin.starter.isSellable)
        XCTAssertFalse(GoalSkin.starter.isSellable)
        XCTAssertFalse(TrailColor.starter.isSellable)   // Classic
        XCTAssertFalse(Floor.starter.isSellable)
        XCTAssertFalse(Pit.starter.isSellable)
        XCTAssertFalse(MusicTrack.starter.isSellable)
        XCTAssertFalse(Boundary.starter.isSellable)
    }

    func testBundleDiscount_percentMapping() {
        XCTAssertEqual(BundleDiscount.common.percent,    10)
        XCTAssertEqual(BundleDiscount.rare.percent,      15)
        XCTAssertEqual(BundleDiscount.epic.percent,      25)
        XCTAssertEqual(BundleDiscount.legendary.percent, 50)
    }

    func testBundleDiscount_weightsSumTo100() {
        let total = BundleDiscount.allCases.reduce(0) { $0 + $1.weight }
        XCTAssertEqual(total, 100, "Loot weights should sum to 100")
    }

    func testFeaturedDiscount_isStableWithinAWindow() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = ShopRotation.featuredDiscount(at: date)
        let b = ShopRotation.featuredDiscount(at: date.addingTimeInterval(60))   // same 2-hour window
        XCTAssertEqual(a, b, "Discount must be stable within a shop window")
    }

    func testFeaturedDiscount_variesAcrossWindows() {
        var seen = Set<BundleDiscount>()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<300 {
            let d = ShopRotation.featuredDiscount(
                at: base.addingTimeInterval(Double(i) * ShopRotation.windowSeconds))
            seen.insert(d)
        }
        XCTAssertGreaterThan(seen.count, 1, "Discount should not be constant across windows")
    }

    // MARK: - Bundle pricing (full / prorated / shop)

    func testBundle_fullPrice_equalsSumOfItemCosts() {
        for bundle in CosmeticBundle.catalogue {
            // A slot's default item (a Roll Along piece) is owned by everyone
            // and adds nothing.
            let ballSum  = bundle.balls.filter  { $0 != BallSkin.starter }.reduce(0)   { $0 + $1.coinCost }
            let goalSum  = bundle.goals.filter  { $0 != GoalSkin.starter }.reduce(0)   { $0 + $1.coinCost }
            let trailSum = bundle.trails.filter { $0 != TrailColor.starter }.reduce(0) { $0 + $1.coinCost }
            let floorSum = bundle.floors.filter { $0 != Floor.starter }.reduce(0)      { $0 + $1.coinCost }
            let pitSum   = bundle.pits.filter   { $0 != Pit.starter }.reduce(0)        { $0 + $1.coinCost }
            // Music is priced in only while it is offered (not in 1.0).
            let musicSum = bundle.offeredMusic.filter  { $0 != MusicTrack.starter }.reduce(0) { $0 + $1.coinCost }
            let wallSum  = bundle.boundaries.filter { $0 != Boundary.starter }.reduce(0) { $0 + $1.coinCost }
            let manual = ballSum + goalSum + trailSum + floorSum + pitSum + musicSum + wallSum
            XCTAssertEqual(bundle.fullPrice(), manual, "fullPrice mismatch for '\(bundle.id)'")
        }
    }

    func testBundle_proratedPrice_onCleanStateEqualsFullPrice() {
        let state = makeCleanState()
        for bundle in CosmeticBundle.catalogue {
            XCTAssertEqual(bundle.proratedPrice(in: state), bundle.fullPrice(),
                           "Owning nothing (but starters), prorated should equal full for '\(bundle.id)'")
        }
    }

    func testBundle_proratedPrice_dropsByOwnedItemCost() {
        let state = makeCleanState()
        guard let bundle = CosmeticBundle.catalogue.first(where: {
            !$0.balls.isEmpty && $0.balls[0].coinCost > 0 && $0.itemCount > 1
        }) else { return XCTFail("expected a multi-item bundle with a priced ball") }
        let ball = bundle.balls[0]
        let before = bundle.proratedPrice(in: state)
        state.grant(ball)
        XCTAssertEqual(bundle.proratedPrice(in: state), before - ball.coinCost,
                       "Owning one item should drop the prorated price by exactly its cost")
    }

    func testBundle_proratedPrice_zeroAfterGrantingContents() {
        let state = makeCleanState()
        let bundle = CosmeticBundle.catalogue[0]
        bundle.grantContents(to: state)
        XCTAssertEqual(bundle.proratedPrice(in: state), 0,
                       "Owning every item should make the prorated price 0")
        XCTAssertTrue(state.completedBundleIDs.contains(bundle.id),
                      "Owning every item should mark the bundle complete")
    }

    func testBundle_shopPrice_appliesDiscountFlooredToFive() {
        let state = makeCleanState()
        for bundle in CosmeticBundle.catalogue {
            let prorated = bundle.proratedPrice(in: state)
            for discount in BundleDiscount.allCases {
                let expected = (Int(Double(prorated) * (1.0 - discount.fraction)) / 5) * 5
                let actual = bundle.shopPrice(in: state, discount: discount)
                XCTAssertEqual(actual, expected, "shopPrice mismatch for '\(bundle.id)' @ \(discount)")
                XCTAssertLessThanOrEqual(actual, prorated, "shopPrice must not exceed prorated")
                XCTAssertEqual(actual % 5, 0, "shopPrice must be a clean multiple of 5")
            }
        }
    }

    // MARK: - Bundle rarity + Iconic (Phase 1)

    /// Probe: prints each bundle's member-tier mix and derived rarity so the
    /// derivation rule can be tuned to the live catalogue, and asserts every
    /// rarity band is represented (a healthy Standard tier is required for the
    /// post-tutorial gift picker).
    func test_bundleRarityDistribution() {
        let sorted = CosmeticBundle.catalogue.sorted { $0.fullPrice() < $1.fullPrice() }
        for b in sorted {
            let perm = b.isLimitedTime ? "seasonal " : "PERMANENT"
            let mix = b.tierCounts()
            let mixStr = "std=\(mix[.standard] ?? 0) rare=\(mix[.rare] ?? 0) epic=\(mix[.premium] ?? 0) leg=\(mix[.exclusive] ?? 0) free=\(mix[.starter] ?? 0)"
            print("RARITYDIST \(b.rarity.label.padding(toLength: 9, withPad: " ", startingAt: 0)) \(String(format: "%6d", b.fullPrice()))  \(perm)  \(mixStr)  \(b.id)")
        }
        let buckets = Dictionary(grouping: CosmeticBundle.catalogue, by: { $0.rarity })
        print("RARITYDIST counts:",
              BundleRarity.allCases.map { "\($0.label)=\(buckets[$0]?.count ?? 0)" }.joined(separator: " "))
        for r in BundleRarity.allCases {
            XCTAssertGreaterThan(buckets[r]?.count ?? 0, 0, "no bundles in rarity band \(r.label)")
        }
    }

    /// Pin of the member-tier rarity rule itself, on synthetic bundles with a
    /// hand-picked tier mix (music tracks: piano/jazz/chiptune = Standard,
    /// lofi/downtempo = Epic, celestial/mysterium = Legendary) plus a couple
    /// of live-catalogue anchors.  Rule: ≥2 legendary members → Legendary;
    /// ≥2 epic-or-legendary members → Rare; otherwise Standard.
    func test_bundleRarity_isDerivedFromMemberTiers() {
        func bundle(music: [MusicTrack]) -> CosmeticBundle {
            CosmeticBundle(id: "test", displayName: "Test", tagline: "", contentSummary: "",
                           balls: [], goals: [], trails: [], floors: [], pits: [], music: music)
        }
        XCTAssertEqual(bundle(music: [.piano, .jazz, .chiptune]).rarity, .standard,
                       "an all-standard bundle is Standard")
        XCTAssertEqual(bundle(music: [.piano, .jazz, .celestial]).rarity, .standard,
                       "one showpiece doesn't lift a bundle out of Standard")
        XCTAssertEqual(bundle(music: [.piano, .lofi, .downtempo]).rarity, .rare,
                       "two epic members make a bundle Rare")
        XCTAssertEqual(bundle(music: [.piano, .lofi, .celestial]).rarity, .rare,
                       "an epic + a legendary member make a bundle Rare")
        XCTAssertEqual(bundle(music: [.piano, .celestial, .mysterium]).rarity, .legendary,
                       "two legendary members make a bundle Legendary")

        // Live-catalogue anchors (the price a bundle totals to is irrelevant).
        let byID = Dictionary(uniqueKeysWithValues: CosmeticBundle.catalogue.map { ($0.id, $0) })
        XCTAssertEqual(byID["nature"]?.rarity, .standard, "nature (5 standard + 1 epic) is Standard")
        XCTAssertEqual(byID["champion"]?.rarity, .legendary, "champion carries 2 legendary members")
        XCTAssertEqual(byID["planets"]?.rarity, .legendary, "planets (9 legendary) is Legendary")
    }

    /// Regression guard for the post-tutorial gift (BallGameView filters
    /// `rarity == .standard && isAvailable`): the PERMANENT (non-seasonal)
    /// Standard-rarity pool must never be empty, or the gift picker
    /// dead-ends the moment no seasonal window is open.  A rarity-rule or
    /// catalogue change that empties this pool must fail here, not in prod.
    /// Per docs/economy/08-reprice.md the pool is specified to hold 4–8
    /// bundles — small enough to stay curated, big enough to feel like a
    /// choice — so drifting outside that band also fails.
    func testTutorialGift_permanentStandardBundlePool_neverEmpty() {
        // The picker now offers exactly the four starter element sets.
        let pool = CosmeticBundle.starterGift
        XCTAssertEqual(pool.map(\.id), ["nature", "fire", "water", "storm"])
        for b in pool {
            XCTAssertFalse(b.isLimitedTime, "\(b.id) must be permanent")
            XCTAssertEqual(b.rarity, .standard, "\(b.id) must be Standard")
            XCTAssertTrue(b.isAvailable, "permanent bundle \(b.id) must always be available")
            XCTAssertFalse(b.isRetired, "\(b.id) must be on sale")
        }
        // The wider Standard pool (Shop) still exists and is healthy.
        let standard = CosmeticBundle.active.filter { !$0.isLimitedTime && $0.rarity == .standard }
        XCTAssertTrue((4...8).contains(standard.count),
                      "The permanent Standard pool must hold 4–8 bundles, got \(standard.count)")
    }

    /// Fire, Water and Storm: new complete Standard sets, every piece new art
    /// that belongs to no other collection, priced by the normal rule
    /// (6 × 750) and on sale from launch.  (Pieces of any rarity may move
    /// gently since the quality round, so stillness is no longer asserted.)
    func testStarterElementSets_areNewCompleteStandardSets() {
        let ids = ["fire", "water", "storm"]
        let others = CosmeticBundle.catalogue.filter { !ids.contains($0.id) }
        for id in ids {
            guard let b = CosmeticBundle.catalogue.first(where: { $0.id == id }) else {
                return XCTFail("missing collection \(id)")
            }
            XCTAssertEqual(b.balls.count, 1); XCTAssertEqual(b.goals.count, 1)
            XCTAssertEqual(b.trails.count, 1); XCTAssertEqual(b.floors.count, 1)
            XCTAssertEqual(b.pits.count, 1); XCTAssertEqual(b.boundaries.count, 1)
            XCTAssertEqual(b.rarity, .standard)
            XCTAssertEqual(b.fullPrice(), 4_500, "\(id): six Standard items at 750")
            XCTAssertTrue(CosmeticSchedule.launchBundleIDs.contains(id), "\(id) is launch content")
            let tiers: [CosmeticTier] = [b.balls[0].tier, b.goals[0].tier, b.trails[0].tier,
                                         b.floors[0].tier, b.pits[0].tier, b.boundaries[0].tier]
            XCTAssertTrue(tiers.allSatisfy { $0 == .standard }, "\(id): every piece is Standard")
            XCTAssertTrue(b.pits[0].hasDrawnArt)
            for o in others {
                XCTAssertFalse(o.balls.contains(b.balls[0]), "\(id) ball is also in \(o.id)")
                XCTAssertFalse(o.goals.contains(b.goals[0]), "\(id) goal is also in \(o.id)")
                XCTAssertFalse(o.trails.contains(b.trails[0]), "\(id) trail is also in \(o.id)")
                XCTAssertFalse(o.floors.contains(b.floors[0]), "\(id) floor is also in \(o.id)")
                XCTAssertFalse(o.pits.contains(b.pits[0]), "\(id) pit is also in \(o.id)")
                XCTAssertFalse(o.boundaries.contains(b.boundaries[0]), "\(id) boundary is also in \(o.id)")
            }
        }
    }

    /// Iconic = the un-sellable specials.  Starter look + earned/IAP exclusives
    /// read "Iconic"; coin-purchasable items keep their tier rarity.
    func testIconic_classification() {
        XCTAssertTrue(BallSkin.red.isIconic, "the classic starter ball is Iconic")
        XCTAssertEqual(BallSkin.red.rarityLabel, "Iconic")
        XCTAssertTrue(BallSkin.diamond.isIconic, "Diamond (IAP) is Iconic")
        XCTAssertTrue(BallSkin.trophy.isIconic, "Trophy (earned) is Iconic")
        XCTAssertTrue(TrailColor.moneyRoll.isIconic, "Money Roll (IAP) is Iconic")

        // Seasonal / limited-time exclusives are NOT iconic — they're sellable
        // (liquidated back into coins), even though they're not shop-buyable.
        XCTAssertFalse(BallSkin.pumpkin.isIconic, "seasonal balls are sellable, not Iconic")
        XCTAssertTrue(BallSkin.pumpkin.isSellable)
        XCTAssertFalse(BallSkin.pumpkin.isCoinPurchasable, "…but still not bought in the regular shop")
        XCTAssertEqual(BallSkin.pumpkin.rarityLabel, BallSkin.pumpkin.tier.label, "shows a tier rarity, not Iconic")

        if let coinBall = BallSkin.allCases.first(where: { $0.isCoinPurchasable }) {
            XCTAssertFalse(coinBall.isIconic)
            XCTAssertTrue(coinBall.isSellable)
            XCTAssertEqual(coinBall.rarityLabel, coinBall.tier.label)
        }
    }

    /// Sell Back now liquidates seasonal / limited-time exclusives for coins,
    /// while still keeping the permanent Iconic specials.
    func testLiquidate_sellsSeasonalExclusives_keepsIconic() {
        let gs = makeCleanState()
        gs.coinBalance = 0
        gs.ownedBallSkins.insert(BallSkin.pumpkin.rawValue)   // seasonal exclusive → sellable now
        gs.ownedBallSkins.insert(BallSkin.diamond.rawValue)   // iconic → kept

        let preview = gs.coinLiquidationPreview()
        XCTAssertEqual(preview.count, 1, "only the seasonal pumpkin is sellable")
        XCTAssertEqual(preview.coins, BallSkin.pumpkin.coinCost / 2)   // 50% refund

        // Sell Back pays 50% of the CURRENT item cost: a 1,500-coin exclusive
        // refunds exactly 750.
        XCTAssertEqual(BallSkin.pumpkin.coinCost, 1500, "pumpkin is a 1,500-coin exclusive")
        XCTAssertEqual(preview.coins, 750, "a 1,500-coin exclusive refunds 750")

        let r = gs.liquidateCoinCosmetics()
        XCTAssertEqual(r.coins, BallSkin.pumpkin.coinCost / 2)
        XCTAssertFalse(gs.ownedBallSkins.contains(BallSkin.pumpkin.rawValue), "seasonal ball sold + relocked")
        XCTAssertTrue(gs.ownedBallSkins.contains(BallSkin.diamond.rawValue), "iconic Diamond kept")
    }

    // MARK: - Free-granted bundle gift (Phase 4 — post-tutorial)

    /// A gifted Standard bundle is granted, marked non-refundable, and Sell Back
    /// keeps it (no coins refunded) — it's un-redeemable.
    func testGrantBundleFree_isKeptAndNeverRefunded() {
        let gs = makeCleanState()
        gs.coinBalance = 0
        guard let bundle = CosmeticBundle.catalogue.first(where: { $0.rarity == .standard }) else {
            return XCTFail("expected at least one Standard bundle for the tutorial gift")
        }

        gs.grantBundleFree(bundle)
        // Every member is now owned and recorded as free-granted.
        for b in bundle.balls  { XCTAssertTrue(gs.isOwned(b)); XCTAssertTrue(gs.isFreeGranted(b)) }
        for g in bundle.goals  { XCTAssertTrue(gs.isOwned(g)) }
        XCTAssertTrue(gs.ownedBundles.contains(bundle.id))

        // Sell Back must NOT refund the gift, and must keep its items.
        let preview = gs.coinLiquidationPreview()
        XCTAssertEqual(preview.count, 0, "gifted bundle items are not sellable")
        XCTAssertEqual(preview.coins, 0)
        gs.liquidateCoinCosmetics()
        for b in bundle.balls where b.tier != .starter {
            XCTAssertTrue(gs.ownedBallSkins.contains(b.rawValue), "gifted ball kept after Sell Back")
        }
        XCTAssertEqual(gs.coinBalance, 0, "no coins handed out for the gift")
    }

    // MARK: - Aurora collection shape

    /// The Aurora collection (sold for coins; the Starter Pack grants only its
    /// ball, trail and boundary — see GameStateTests) keeps one item per slot.
    func testAuroraBundle_existsWithOneItemPerCategory() {
        guard let aurora = CosmeticBundle.catalogue.first(where: { $0.id == "aurora" }) else {
            return XCTFail("the \"aurora\" bundle must exist")
        }
        XCTAssertEqual(aurora.balls,  [.aurora])
        XCTAssertEqual(aurora.goals,  [.aurora])
        XCTAssertEqual(aurora.trails, [.aurora])
        XCTAssertEqual(aurora.floors, [.aurora])
        XCTAssertEqual(aurora.pits,   [.aurora])
        XCTAssertEqual(aurora.music,  [.aurora])
        XCTAssertEqual(aurora.boundaries, [.aurora])
    }

    /// Slots left empty when the Roll Along defaults (and Graphite, now
    /// Sketchbook-only) were taken out of other collections.  All four are
    /// retired or seasonal sets; replacements are still to be chosen.
    static let knownSlotGaps: [String: Set<String>] = [
        "heavens":           ["floor"],   // was the Classic floor
        "backtoschool-2026": ["goal"],    // was the Target goal
        "diamond":           ["goal"],    // was the Target goal
        "paper-world":       ["trail"],   // was the Graphite trail
    ]

    /// Every collection is a complete set: at least one item in each of the
    /// seven slots (ball, goal, trail, floor, pit, boundary, music), except the
    /// known gaps above.  The music data stays even while music is off.
    func testEveryCollection_isACompleteSevenSlotSet() {
        for b in CosmeticBundle.catalogue {
            let gaps = Self.knownSlotGaps[b.id] ?? []
            func check(_ empty: Bool, _ slot: String) {
                if gaps.contains(slot) {
                    XCTAssertTrue(empty, "\(b.id) \(slot) gap is filled — update knownSlotGaps")
                } else {
                    XCTAssertFalse(empty, "\(b.id) has no \(slot)")
                }
            }
            check(b.balls.isEmpty, "ball")
            check(b.goals.isEmpty, "goal")
            check(b.trails.isEmpty, "trail")
            check(b.floors.isEmpty, "floor")
            check(b.pits.isEmpty, "pit")
            check(b.boundaries.isEmpty, "boundary")
            XCTAssertFalse(b.music.isEmpty, "\(b.id) has no music")
        }
        XCTAssertTrue(Self.knownSlotGaps.keys.allSatisfy { id in
            CosmeticBundle.catalogue.contains { $0.id == id && $0.isRetired }
        }, "every gap is in a retired set")
    }

    // MARK: - Roll Along (the Iconic default set) and the Classic trail

    func testRollAlong_isTheSixDefaults_iconicFreeAndOwned() {
        let set = CosmeticBundle.rollAlong
        XCTAssertEqual(set.id, "roll-along")
        XCTAssertEqual(set.displayName, "Roll Along")
        XCTAssertEqual(set.balls, [.red])
        XCTAssertEqual(set.goals, [.target])
        XCTAssertEqual(set.trails, [.classic])
        XCTAssertEqual(set.floors, [.classic])
        XCTAssertEqual(set.pits, [.classic])
        XCTAssertEqual(set.boundaries, [.classic])
        XCTAssertEqual(set.fullPrice(), 0)
        XCTAssertTrue(set.isRollAlong)
        for piece in [set.balls.map { $0.isIconic && !$0.isSellable && !$0.isCoinPurchasable },
                      set.goals.map { $0.isIconic && !$0.isSellable && !$0.isCoinPurchasable },
                      set.trails.map { $0.isIconic && !$0.isSellable && !$0.isCoinPurchasable },
                      set.floors.map { $0.isIconic && !$0.isSellable && !$0.isCoinPurchasable },
                      set.pits.map { $0.isIconic && !$0.isSellable && !$0.isCoinPurchasable },
                      set.boundaries.map { $0.isIconic && !$0.isSellable && !$0.isCoinPurchasable }]
            .flatMap({ $0 }) {
            XCTAssertTrue(piece, "every Roll Along piece is Iconic, unsellable and not for sale")
        }
        let gs = makeCleanState()
        XCTAssertTrue(gs.completedBundleIDs.contains("roll-along"), "owned from first launch")
        XCTAssertEqual(gs.equippedTrail, .classic, "Classic is equipped on a fresh install")
        XCTAssertEqual(gs.activeSkin, .red)
        XCTAssertEqual(gs.equippedGoal, .target)
        XCTAssertEqual(gs.equippedFloor, .classic)
        XCTAssertEqual(gs.equippedPit, .classic)
        XCTAssertEqual(gs.equippedBoundary, .classic)
    }

    /// Never sold: not in the catalogue, so never in the Shop rotation, the
    /// featured bundle, gift pools, Challenge Track rewards or the calendar.
    func testRollAlong_isNeverSoldOrScheduled() {
        XCTAssertFalse(CosmeticBundle.catalogue.contains { $0.id == "roll-along" })
        XCTAssertFalse(CosmeticBundle.active.contains { $0.id == "roll-along" })
        XCTAssertFalse(CosmeticBundle.starterGift.contains { $0.id == "roll-along" })
        XCTAssertFalse(ShopRotation.trailPool.contains(.classic))
        XCTAssertFalse(ShopRotation.ballPool.contains(.red))
        XCTAssertTrue(CosmeticSchedule.releaseKeys(of: TrailColor.classic).isEmpty)
    }

    /// No Roll Along piece is in any other collection (active, retired or
    /// seasonal).
    func testRollAlong_sharesNoPieceWithAnyCollection() {
        for b in CosmeticBundle.catalogue {
            XCTAssertFalse(b.balls.contains(.red), "\(b.id) uses the Red ball")
            XCTAssertFalse(b.goals.contains(.target), "\(b.id) uses the Target goal")
            XCTAssertFalse(b.trails.contains(.classic), "\(b.id) uses the Classic trail")
            XCTAssertFalse(b.floors.contains(.classic), "\(b.id) uses the Classic floor")
            XCTAssertFalse(b.pits.contains(.classic), "\(b.id) uses the Classic pit")
            XCTAssertFalse(b.boundaries.contains(.classic), "\(b.id) uses the Classic boundary")
        }
    }

    /// Graphite is a normal Standard trail, sold only in Sketchbook; new
    /// players don't own it.  Sketchbook's price includes it (4,750).
    func testGraphite_isASketchbookOnlyStandardTrail() {
        XCTAssertEqual(TrailColor.graphite.tier, .standard)
        XCTAssertTrue(TrailColor.graphite.isCoinPurchasable)
        XCTAssertTrue(TrailColor.graphite.isSellable)
        XCTAssertNotEqual(TrailColor.starter, .graphite)
        let holders = CosmeticBundle.catalogue.filter { $0.trails.contains(.graphite) }.map(\.id)
        XCTAssertEqual(holders, ["sketchbook"])
        XCTAssertEqual(CosmeticBundle.catalogue.first { $0.id == "sketchbook" }?.fullPrice(), 4_750)
        XCTAssertFalse(makeCleanState().isOwned(TrailColor.graphite))
    }

    /// A saved loadout with a trail the player doesn't own (Graphite from an
    /// older build) falls back to Classic.
    func testSavedUnownedTrail_fallsBackToClassic() {
        let defaults = UserDefaults(suiteName: "roll-along-fallback-\(UUID().uuidString)")!
        defaults.set(TrailColor.graphite.rawValue, forKey: "ra_equippedTrail")
        let gs = GameState(defaults: defaults)
        XCTAssertEqual(gs.equippedTrail, .classic)
    }

    /// Catalog tabs and the Locker list the slot's Roll Along piece first.
    func testRollAlongPiece_isListedFirst() {
        XCTAssertEqual(TrailColor.rollAlongFirst(TrailColor.allCases).first, .classic)
        XCTAssertEqual(BallSkin.rollAlongFirst(BallSkin.allCases.reversed()).first, .red)
        XCTAssertEqual(Floor.rollAlongFirst(Array(Floor.allCases.reversed())).first, .classic)
    }

    // MARK: Quality round — Storm, Sketchbook, Neon

    /// Storm: the same six ids, redrawn.  Three display names changed with
    /// the art; tiers and the price did not.  The floor and pit now move.
    func testQualityRound_stormKeepsIdsTiersAndPrice() {
        guard let storm = CosmeticBundle.active.first(where: { $0.id == "storm" }) else {
            return XCTFail("Storm is not on sale")
        }
        XCTAssertEqual(storm.balls, [.thundercloud])
        XCTAssertEqual(storm.goals, [.thunderRing])
        XCTAssertEqual(storm.trails, [.squall])
        XCTAssertEqual(storm.floors, [.overcast])
        XCTAssertEqual(storm.pits, [.maelstrom])
        XCTAssertEqual(storm.boundaries, [.thunderbolt])
        XCTAssertEqual(GoalSkin.thunderRing.displayName, "Storm Eye")
        XCTAssertEqual(Boundary.thunderbolt.displayName, "Thunderhead")
        XCTAssertEqual(storm.fullPrice(), 4_500)
        XCTAssertEqual(storm.rarity, .standard)
        XCTAssertTrue(Floor.overcast.hasAnimatedOverlay)
        XCTAssertTrue(Pit.maelstrom.hasAnimatedOverlay)
        XCTAssertTrue(Pit.maelstrom.hasDrawnArt, "the pit art stays visible (frozen) under Reduce Motion")
        XCTAssertTrue(Boundary.thunderbolt.textureShowsUnderReduceMotion)
    }

    /// Storm lightning is rare and soft: dark for most of every cycle, never
    /// brighter than 1, a new bolt each strike, and absent under Reduce Motion.
    func testQualityRound_stormLightningIsRareAndNeverUnderReduceMotion() {
        for seed in [0.17, 0.31, 0.45, 0.62, 0.87] {
            let period = StormArt.period(seed)
            XCTAssertGreaterThanOrEqual(period, 7.0)
            XCTAssertLessThanOrEqual(period, 12.0)
            var lit = 0
            let samples = 2_000
            for k in 0..<samples {
                let t = 800_000_000.0 + Double(k) * period * 3.0 / Double(samples)
                let f = StormArt.flash(t, seed: seed)
                XCTAssertGreaterThanOrEqual(f.level, 0)
                XCTAssertLessThanOrEqual(f.level, 1)
                if f.level > 0.02 { lit += 1 }
                XCTAssertEqual(StormArt.strike(t, seed: seed, frozen: false, still: true).level, 0)
            }
            XCTAssertGreaterThan(lit, 0, "seed \(seed) never flashes")
            XCTAssertLessThan(Double(lit) / Double(samples), 0.10,
                              "seed \(seed): the sky is dark at least 90% of the time")
            let a = StormArt.flash(800_000_000.0, seed: seed).id
            let b = StormArt.flash(800_000_000.0 + period, seed: seed).id
            XCTAssertNotEqual(a, b, "each strike draws a different fork")
        }
    }

    /// Sketchbook: the Pencil ball and Scribble goal replace Silver and
    /// Archery (which belong to no collection on sale any more); the floor is
    /// named "Paper" under its old id; the price is unchanged.
    func testQualityRound_sketchbookHasPencilAndScribble() {
        guard let book = CosmeticBundle.active.first(where: { $0.id == "sketchbook" }) else {
            return XCTFail("Sketchbook is not on sale")
        }
        XCTAssertEqual(book.balls, [.pencil])
        XCTAssertEqual(book.goals, [.scribble])
        XCTAssertEqual(book.trails, [.graphite])
        XCTAssertEqual(book.floors, [.sketch])
        XCTAssertEqual(book.pits, [.sketch])
        XCTAssertEqual(book.boundaries, [.slate])
        XCTAssertEqual(BallSkin.pencil.tier, BallSkin.silver.tier, "a replacement takes the old piece's tier")
        XCTAssertEqual(GoalSkin.scribble.tier, GoalSkin.archery.tier)
        XCTAssertEqual(Floor.sketch.displayName, "Paper")
        XCTAssertEqual(Floor.sketch.rawValue, Floor(rawValue: Floor.sketch.rawValue)?.rawValue)
        XCTAssertEqual(Pit.sketch.displayName, "Sketch")
        XCTAssertEqual(book.fullPrice(), 4_750)
        for other in CosmeticBundle.active where other.id != "sketchbook" {
            XCTAssertFalse(other.balls.contains(.pencil), "Pencil is also in \(other.id)")
            XCTAssertFalse(other.goals.contains(.scribble), "Scribble is also in \(other.id)")
        }
        for b in CosmeticBundle.active {
            XCTAssertFalse(b.balls.contains(.silver), "Silver left the sets on sale (\(b.id))")
            XCTAssertFalse(b.goals.contains(.archery), "Archery left the sets on sale (\(b.id))")
        }
    }

    /// Neon: same six ids; the pit is redrawn in place and renamed "Blackout".
    func testQualityRound_neonPitIsBlackout() {
        guard let neon = CosmeticBundle.active.first(where: { $0.id == "neon" }) else {
            return XCTFail("Neon is not on sale")
        }
        XCTAssertEqual(neon.pits, [.graph])
        XCTAssertEqual(Pit.graph.displayName, "Blackout")
        XCTAssertEqual(Floor.graph.displayName, "Graph", "the Graph floor keeps its name")
        XCTAssertEqual(Pit.graph.tier, .standard)
        XCTAssertTrue(Pit.graph.hasDrawnArt)
        XCTAssertEqual(neon.floors, [.gridCity])
        XCTAssertEqual(neon.goals, [.neon])
    }

    /// Every boundary added for a collection belongs to at least one
    /// collection, and the animated (Legendary) ones only sit in collections
    /// that are already Legendary — so adding them moved no rarity band.
    func testCollectionBoundaries_areUsedAndKeepRarityBands() {
        let used = Set(CosmeticBundle.catalogue.flatMap(\.boundaries))
        let added: [Boundary] = [.notebook, .fairway, .sunset, .rose, .ink, .citrus, .pastel,
                                 .pumpkin, .holly, .shamrock, .marigold, .autumn, .lantern,
                                 .hardwood, .cloud, .tide, .velvet, .marble, .phantom, .mahogany,
                                 .sandstone, .abyss, .amethyst, .chrome, .brass, .molten,
                                 .starlight, .aurora, .corona, .storm, .confetti, .starSpangled,
                                 .rainbow, .marquee, .stainedGlass]
        XCTAssertEqual(added.count, 35)
        for w in added { XCTAssertTrue(used.contains(w), "\(w) is in no collection") }
        for b in CosmeticBundle.catalogue {
            for w in b.boundaries where w.tier == .exclusive {
                XCTAssertEqual(b.rarity, .legendary,
                               "animated boundary \(w) put in non-Legendary collection \(b.id)")
            }
        }
    }

    /// A free-granted bundle (the post-tutorial gift path) must refund
    /// nothing through Sell Back, or a gift becomes a coin faucet.
    func testAuroraBundleGrantedFree_isNotACoinFaucet() {
        let gs = makeCleanState()
        gs.coinBalance = 0
        guard let aurora = CosmeticBundle.catalogue.first(where: { $0.id == "aurora" }) else {
            return XCTFail("expected the \"aurora\" bundle in the catalogue")
        }

        gs.grantBundleFree(aurora)
        XCTAssertTrue(gs.isOwned(BallSkin.aurora))
        XCTAssertTrue(gs.isOwned(GoalSkin.aurora))
        XCTAssertTrue(gs.isOwned(TrailColor.aurora))
        XCTAssertTrue(gs.isOwned(Floor.aurora))
        XCTAssertTrue(gs.isOwned(Pit.aurora))
        // Music isn't offered in 1.0, so the gift doesn't grant it.
        XCTAssertEqual(gs.isOwned(MusicTrack.aurora), CosmeticFeatures.musicEnabled)
        XCTAssertTrue(gs.isOwned(Boundary.aurora))
        XCTAssertTrue(gs.completedBundleIDs.contains("aurora"))

        let preview = gs.coinLiquidationPreview()
        XCTAssertEqual(preview.coins, 0, "pack-granted Aurora items must not be refundable")
        gs.liquidateCoinCosmetics()
        XCTAssertTrue(gs.ownedBallSkins.contains(BallSkin.aurora.rawValue), "collection kept after Sell Back")
        XCTAssertEqual(gs.coinBalance, 0, "Sell Back minted coins from the $1.99 pack's items")
    }

    /// A player who coin-bought part of the collection before the free grant
    /// is compensated at `sellBackValue` up front — exactly what Sell Back
    /// would have paid, no more (the grant must neither confiscate paid value
    /// nor out-pay Sell Back).  Uses the goal (rawValue "aurora", shared with
    /// trail/floor/pit/music) AND the ball (rawValue "Aurora", distinct) so
    /// both the colliding and non-colliding key paths are pinned.
    func testGrantBundleFree_compensatesPreviouslyCoinBoughtItems() {
        let gs = makeCleanState()
        gs.coinBalance = GoalSkin.aurora.coinCost + BallSkin.aurora.coinCost
        XCTAssertTrue(gs.purchase(GoalSkin.aurora))
        XCTAssertTrue(gs.purchase(BallSkin.aurora))
        XCTAssertEqual(gs.coinBalance, 0)
        guard let aurora = CosmeticBundle.catalogue.first(where: { $0.id == "aurora" }) else {
            return XCTFail("expected the \"aurora\" bundle in the catalogue")
        }

        let compensation = GoalSkin.aurora.coinCost / 2 + BallSkin.aurora.coinCost / 2
        gs.grantBundleFree(aurora)
        XCTAssertEqual(gs.coinBalance, compensation,
                       "coin-bought pieces are compensated at sellBackValue (half current cost)")
        XCTAssertTrue(gs.completedBundleIDs.contains("aurora"))
        XCTAssertEqual(gs.coinLiquidationPreview().coins, 0,
                       "after compensation the whole collection is free-granted, not sellable")

        // Re-granting must not compensate again (items are now free-marked).
        gs.grantBundleFree(aurora)
        XCTAssertEqual(gs.coinBalance, compensation,
                       "second grant is a no-op, no double refund")
    }

    /// Compensation honours the paid-price cap: an item bought at a discount
    /// is compensated at what was paid when that undercuts the half rate.
    func testGrantBundleFree_compensationHonoursPaidPriceCap() {
        let gs = makeCleanState()
        guard let aurora = CosmeticBundle.catalogue.first(where: { $0.id == "aurora" }) else {
            return XCTFail("expected the \"aurora\" bundle in the catalogue")
        }
        gs.grant(GoalSkin.aurora)
        gs.paidPrices[GameState.paidPriceKey(GoalSkin.aurora)] = 1   // deep-discount record
        gs.coinBalance = 0

        gs.grantBundleFree(aurora)
        XCTAssertEqual(gs.coinBalance, 1, "compensation capped at the recorded paid price")
        XCTAssertNil(gs.paidPrices[GameState.paidPriceKey(GoalSkin.aurora)],
                     "free-marked item's paid-price record is cleared")
    }
    // MARK: - Discounted purchases refund what was PAID (coin-mint fix)
    //
    // Sell Back used to refund every item's full coinCost even when it was
    // bought below cost (the Shop's featured-bundle discount, Ball Packs'
    // 66% pricing) — buy a bundle at 50% off, liquidate for its full price,
    // pocket the difference, repeat every rotation window.  `paidPrices`
    // records the discounted price, and Sell Back pays `sellBackValue`:
    // half the CURRENT coinCost, capped at what was paid — so neither deep
    // discounts nor future price bumps can ever refund more than was spent.

    /// Buying the featured bundle at the deepest (50%) discount and selling
    /// straight back must refund at most what was paid — never a profit.
    func testBundle_discountedShopPurchase_sellBackRefundsPaidNotFull() {
        let gs = makeCleanState()
        // A launch collection: purchaseBundle refuses a set whose release day
        // has not arrived, so a calendar drop would fail before its date.
        guard let bundle = CosmeticSale.fullCollections.first(where: {
            CosmeticSchedule.launchBundleIDs.contains($0.id)
        }) else { return XCTFail("expected a full launch collection") }
        let paid = bundle.shopPrice(in: gs, discount: .legendary)   // 50% off
        gs.coinBalance = paid
        XCTAssertTrue(gs.purchaseBundle(bundle, price: paid))
        XCTAssertEqual(gs.coinBalance, 0)

        let preview = gs.coinLiquidationPreview()
        let r = gs.liquidateCoinCosmetics()
        XCTAssertEqual(preview.coins, r.coins, "preview and liquidation must agree")
        XCTAssertGreaterThan(r.coins, 0, "a discounted purchase still refunds something")
        XCTAssertLessThanOrEqual(r.coins, paid, "Sell Back must never refund more than was paid")
        XCTAssertLessThanOrEqual(gs.coinBalance, paid, "buy-discounted → Sell Back must not mint coins")
    }

    /// The original exploit loop: buy at 50% off, liquidate, re-buy next
    /// window.  Repeating must never grow the balance past its start.
    func testBundle_discountBuySellLoop_neverProfits() {
        let gs = makeCleanState()
        // A launch collection: purchaseBundle refuses a set whose release day
        // has not arrived, so a calendar drop would fail before its date.
        guard let bundle = CosmeticSale.fullCollections.first(where: {
            CosmeticSchedule.launchBundleIDs.contains($0.id)
        }) else { return XCTFail("expected a full launch collection") }
        let start = bundle.fullPrice()
        gs.coinBalance = start
        for pass in 1...3 {
            let price = bundle.shopPrice(in: gs, discount: .legendary)
            XCTAssertTrue(gs.purchaseBundle(bundle, price: price), "pass \(pass) purchase")
            gs.liquidateCoinCosmetics()
            XCTAssertLessThanOrEqual(gs.coinBalance, start,
                                     "pass \(pass): buy-at-discount → Sell Back must never exceed the starting balance")
        }
    }

    /// Ball packs are HELD: their balls are in no full collection, so a pack
    /// is never sold (CosmeticSale).  A refused purchase spends nothing.  An
    /// owner keeps a pack and can still equip it.
    func testPack_heldPacksAreNotSold() {
        let gs = makeCleanState()
        gs.coinBalance = 1_000_000
        for pack in BallPack.catalogue {
            XCTAssertFalse(CosmeticSale.isOnSale(pack), "\(pack.id) holds balls outside a full collection")
            XCTAssertFalse(gs.purchasePack(pack), "\(pack.id) must not be sold")
        }
        XCTAssertEqual(gs.coinBalance, 1_000_000, "a refused purchase spends nothing")
        guard let pack = BallPack.catalogue.first else { return XCTFail("expected a pack in the catalogue") }
        gs.ownedPacks.insert(pack.id)
        gs.equipPack(pack)
        XCTAssertEqual(gs.equippedPackID, pack.id, "an owner can still equip a held pack")
    }

    /// Full-price purchases take the standard rate: an individual Shop buy
    /// refunds half its current coinCost (no paid-price cap in play).
    func testFullPricePurchases_refundHalfCurrentCost() {
        let gs = makeCleanState()
        gs.coinBalance = BallSkin.jade.coinCost
        XCTAssertTrue(gs.purchase(BallSkin.jade))
        let r = gs.liquidateCoinCosmetics()
        XCTAssertEqual(r.coins, BallSkin.jade.coinCost / 2, "full-price purchase refunds half the current cost")
    }

    /// Re-buying an item at full price after a discounted purchase was sold
    /// back must clear the stale discounted record.
    func testRebuyAtFullPrice_clearsDiscountedRecord() {
        let gs = makeCleanState()
        gs.paidPrices[GameState.paidPriceKey(BallSkin.jade)] = 1   // stale discount record
        gs.coinBalance = BallSkin.jade.coinCost
        XCTAssertTrue(gs.purchase(BallSkin.jade))
        XCTAssertEqual(gs.sellBackValue(BallSkin.jade), BallSkin.jade.coinCost / 2,
                       "full-price re-purchase refunds the standard half rate again")
    }

    /// `paidPrices` keys are category-qualified: five different cosmetics
    /// share the rawValue "aurora", and a discounted record for one category
    /// must not distort another's refund.
    func testPaidPrices_keysAreCategoryQualified_noAuroraCollision() {
        let gs = makeCleanState()
        gs.paidPrices[GameState.paidPriceKey(BallSkin.aurora)] = 1
        XCTAssertEqual(gs.sellBackValue(BallSkin.aurora), 1)
        XCTAssertEqual(gs.sellBackValue(TrailColor.aurora), TrailColor.aurora.coinCost / 2)
        XCTAssertEqual(gs.sellBackValue(GoalSkin.aurora), GoalSkin.aurora.coinCost / 2)
        XCTAssertEqual(gs.sellBackValue(Floor.aurora), Floor.aurora.coinCost / 2)
    }

    /// `sellBackValue` never exceeds the standard half rate, even if a
    /// corrupt/legacy record claims more was paid.
    func testSellBackValue_isCappedAtHalfCurrentCost() {
        let gs = makeCleanState()
        gs.paidPrices[GameState.paidPriceKey(BallSkin.jade)] = BallSkin.jade.coinCost * 10
        XCTAssertEqual(gs.sellBackValue(BallSkin.jade), BallSkin.jade.coinCost / 2)
    }
    // MARK: - Release calendar (CosmeticSchedule)

    /// Every FULL active collection is scheduled exactly once — at launch or
    /// in one drop — and nothing else is: no retired set, no loose slot.
    func testSchedule_everyFullCollectionScheduledExactlyOnce() {
        let scheduled = CosmeticSchedule.launchBundleIDs + CosmeticSchedule.drops.flatMap { $0.ids }
        XCTAssertEqual(scheduled.count, Set(scheduled).count, "a collection is scheduled twice")
        XCTAssertEqual(Set(scheduled), Set(CosmeticSale.fullCollections.map(\.id)),
                       "the schedule must cover exactly the full active collections")
        XCTAssertFalse(CosmeticSchedule.builtInReleaseDays.keys.contains { $0.hasPrefix("_loose") },
                       "there are no single-piece release slots")
    }

    /// Collections the game gives away must be available on day one: the
    /// Starter Pack's Aurora, the post-tutorial gift pool, and every
    /// challenge-track reward.
    func testSchedule_giftAndRewardBundlesAreLaunchContent() {
        let launch = Set(CosmeticSchedule.launchBundleIDs)
        XCTAssertTrue(launch.contains("aurora"))
        for b in CosmeticBundle.active where !b.isLimitedTime && b.rarity == .standard {
            XCTAssertTrue(launch.contains(b.id), "gift-pool collection \(b.id) must be launch content")
        }
        for track in GameModeCatalogue.challengeTracks {
            guard let id = ChallengeTrackMode.rewardBundleID(for: track.trackID) else { continue }
            XCTAssertTrue(launch.contains(id), "track reward \(id) must be launch content")
        }
    }

    // A private store per test: no phone storage, no server copy, and (unless a
    // test turns it on) no "already released" memory.
    private func calendarStore(remembers: Bool = false) -> CosmeticCalendarStore {
        CosmeticCalendarStore(defaults: nil, remembersReleases: remembers)
    }

    /// One second before / at midnight Eastern on a day.
    private func eastern(_ y: Int, _ m: Int, _ d: Int, plus seconds: TimeInterval = 0) -> Date {
        CosmeticSchedule.easternMidnight(y, m, d).addingTimeInterval(seconds)
    }

    /// The built-in calendar: every release day brings one or two full
    /// collections (database steps 11 and 21 hold the same rows).
    func testSchedule_everyReleaseIsOneOrTwoFullCollections() {
        let expected: [(String, CalendarDay)] = [
            ("candyland", CalendarDay(2027, 2, 11)), ("nightclub", CalendarDay(2027, 2, 11)),
            ("golf", CalendarDay(2027, 4, 1)),       ("bloom", CalendarDay(2027, 4, 1)),
            ("ocean", CalendarDay(2027, 6, 3)),
        ]
        XCTAssertEqual(CosmeticSchedule.builtInReleaseDays.count, expected.count)
        for (id, day) in expected {
            XCTAssertEqual(CosmeticSchedule.builtInReleaseDays[id], day, id)
        }
        let full = Set(CosmeticSale.fullCollections.map(\.id))
        for drop in CosmeticSchedule.drops {
            XCTAssertTrue((1...2).contains(drop.ids.count), "a release day brings one or two collections")
            for id in drop.ids { XCTAssertTrue(full.contains(id), "\(id) must be a full active collection") }
        }
        let days = CosmeticSchedule.drops.map { $0.day }
        XCTAssertEqual(days, days.sorted(), "drops are in date order")
        XCTAssertNil(CosmeticSchedule.releaseDate(of: "aurora"), "launch collections have no date")
        XCTAssertNil(CosmeticSchedule.releaseDate(of: "cathedral"), "retired sets have no release day")
        XCTAssertEqual(CosmeticBundle.catalogue.first { $0.id == "lunar-2027" }?.displayName,
                       "Lunar New Year")
    }

    /// A drop opens at midnight EASTERN on its day, not the phone's midnight.
    func testSchedule_dropOpensAtMidnightEastern() {
        let store = calendarStore()
        XCTAssertTrue(CosmeticSchedule.isReleased(collectionID: "aurora",
                                                  at: eastern(2020, 1, 1), store: store),
                      "launch content is available from the first open, whenever that is")
        XCTAssertFalse(CosmeticSchedule.isReleased(collectionID: "candyland",
                                                   at: eastern(2027, 2, 11, plus: -1), store: store))
        XCTAssertTrue(CosmeticSchedule.isReleased(collectionID: "candyland",
                                                  at: eastern(2027, 2, 11), store: store))
        // Midnight Eastern on Feb 11 is 05:00 UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour], from: eastern(2027, 2, 11))
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour], [2027, 2, 11, 5])
        XCTAssertEqual(CosmeticSchedule.dayLabel(eastern(2027, 2, 11)).contains("11"), true)
    }

    /// Every collection releases eventually; "Coming soon" names only the
    /// collections on the next release day that has any — never single items —
    /// and is hidden once no collection is scheduled.
    func testSchedule_comingSoonShowsTheNextCollectionDay() {
        let store = calendarStore()
        // There are no single-piece release days: the first release is Feb 11.
        let first = CosmeticSchedule.nextDrop(at: eastern(2026, 12, 1), store: store)
        XCTAssertEqual(first?.date, eastern(2027, 2, 11))
        XCTAssertEqual(Set(first?.bundles.map(\.id) ?? []), ["candyland", "nightclub"])
        let march = CosmeticSchedule.nextDrop(at: eastern(2027, 3, 11, plus: -1), store: store)
        XCTAssertEqual(march?.date, eastern(2027, 4, 1))
        XCTAssertEqual(Set(march?.bundles.map(\.id) ?? []), ["golf", "bloom"])
        let june = CosmeticSchedule.nextDrop(at: eastern(2027, 4, 2), store: store)
        XCTAssertEqual(june?.bundles.map(\.id), ["ocean"])
        XCTAssertNil(CosmeticSchedule.nextDrop(at: eastern(2027, 6, 3), store: store),
                     "no collection scheduled after Ocean: the tile is hidden")
        let afterAll = eastern(2027, 11, 11)
        XCTAssertNil(CosmeticSchedule.nextDrop(at: afterAll, store: store),
                     "nothing is left to announce after the last drop")
        for b in CosmeticBundle.catalogue {
            XCTAssertTrue(CosmeticSchedule.isReleased(b, at: afterAll, store: store), "\(b.id) never releases")
        }
    }

    /// A date in the server table overrides the built-in one, earlier or later;
    /// unknown ids, retired sets, loose slots and broken rows are ignored;
    /// deleting a row restores the built-in date.
    func testSchedule_serverDatesOverrideBuiltIn() {
        let store = calendarStore()
        typealias Row = CosmeticCalendarStore.Row
        store.apply([
            Row(collection_id: "candyland", starts_on: "2027-01-07", ends_on: nil),   // earlier
            Row(collection_id: "golf", starts_on: "2027-05-20", ends_on: nil),        // later
            Row(collection_id: "not-a-collection", starts_on: "2027-01-01", ends_on: nil),
            Row(collection_id: "cathedral", starts_on: "2026-12-17", ends_on: nil),   // retired: ignored
            Row(collection_id: "_loose-1", starts_on: "2027-02-11", ends_on: nil),    // old loose slot: ignored
            Row(collection_id: "ocean", starts_on: "garbage", ends_on: nil),
        ])
        XCTAssertTrue(CosmeticSchedule.isReleased(collectionID: "candyland",
                                                  at: eastern(2027, 1, 7), store: store))
        XCTAssertFalse(CosmeticSchedule.isReleased(collectionID: "golf",
                                                   at: eastern(2027, 4, 2), store: store))
        XCTAssertEqual(CosmeticSchedule.nextDrop(at: eastern(2026, 12, 18), store: store)?.date,
                       eastern(2027, 1, 7), "Coming soon follows the server date")
        XCTAssertEqual(CosmeticSchedule.nextDrop(at: eastern(2026, 12, 18), store: store)?.bundles.map(\.id),
                       ["candyland"], "a leftover row for a retired set announces nothing")
        XCTAssertEqual(CosmeticSchedule.releaseDate(of: "ocean", store: store),
                       eastern(2027, 6, 3), "a broken row falls back to the built-in date")
        XCTAssertNil(CosmeticSchedule.releaseDate(of: "cathedral", store: store))
        store.apply([])
        XCTAssertEqual(CosmeticSchedule.releaseDate(of: "golf", store: store), eastern(2027, 4, 1))
    }

    /// Sticky: a collection this phone has seen released stays released when
    /// its date is later moved back.
    func testSchedule_releasedCollectionStaysReleasedWhenMovedLater() {
        let store = calendarStore(remembers: true)
        // Seen released "now" under a date that has already passed…
        store.apply([CosmeticCalendarStore.Row(collection_id: "golf", starts_on: "2020-01-02", ends_on: nil)])
        XCTAssertTrue(CosmeticSchedule.isReleased(collectionID: "golf", store: store))
        // …then the server moves it far into the future.
        store.apply([CosmeticCalendarStore.Row(collection_id: "golf", starts_on: "2099-01-01", ends_on: nil)])
        XCTAssertTrue(CosmeticSchedule.isReleased(collectionID: "golf", store: store),
                      "a released collection is never taken away")
        // A phone that never saw it released waits for the new date.
        let fresh = calendarStore(remembers: true)
        fresh.apply([CosmeticCalendarStore.Row(collection_id: "golf", starts_on: "2099-01-01", ends_on: nil)])
        XCTAssertFalse(CosmeticSchedule.isReleased(collectionID: "golf", store: fresh))
        // Questions about other moments never mark anything released.
        let probe = calendarStore(remembers: true)
        _ = CosmeticSchedule.isReleased(collectionID: "ocean", at: eastern(2030, 1, 1), store: probe)
        XCTAssertFalse(probe.hasSeenReleased("ocean"))
    }

    /// A piece follows its full collection: not on sale before the
    /// collection's day, on sale from it.  Defaults are never date-gated.
    func testSchedule_itemsFollowTheirCollections() {
        let store = calendarStore()
        XCTAssertTrue(CosmeticSchedule.isReleased(BallSkin.starter, at: eastern(2020, 1, 1), store: store))
        for b in CosmeticSale.fullCollections {
            guard let date = CosmeticSchedule.releaseDate(of: b.id, store: store) else { continue }
            for ball in b.balls {
                XCTAssertFalse(CosmeticSale.isOnSale(ball, at: date.addingTimeInterval(-1), store: store),
                               "\(ball.rawValue) must wait for \(b.id)")
                XCTAssertTrue(CosmeticSale.isOnSale(ball, at: date, store: store),
                              "\(ball.rawValue) must be out with \(b.id)")
            }
        }
    }

    /// Only 22 collections are on sale (21 plus Space Traveler).  Each is one item per offered slot,
    /// and no item is in two of them.  Gift pool, Starter Pack and track
    /// rewards all point at active collections.
    func testActiveCollections_areCompleteAndUnique() {
        let active = CosmeticBundle.active
        XCTAssertEqual(active.count, 22)
        XCTAssertEqual(Set(active.map(\.id)), Set(CosmeticBundle.activeIDs))
        var seen: [String: String] = [:]
        func check(_ b: CosmeticBundle, _ keys: [String]) {
            XCTAssertEqual(keys.count, 1, "\(b.id) must have exactly one item in each slot")
            for k in keys {
                if let other = seen[k] { XCTFail("\(k) is in both \(other) and \(b.id)") }
                seen[k] = b.id
            }
        }
        for b in active {
            XCTAssertFalse(b.isLimitedTime, "\(b.id): active collections are permanent")
            check(b, b.balls.map { "ball|" + $0.rawValue })
            check(b, b.goals.map { "goal|" + $0.rawValue })
            check(b, b.trails.map { "trail|" + $0.rawValue })
            check(b, b.floors.map { "floor|" + $0.rawValue })
            check(b, b.pits.map { "pit|" + $0.rawValue })
            check(b, b.boundaries.map { "boundary|" + $0.rawValue })
        }
        XCTAssertEqual(active.filter { $0.rarity == .standard }.count, 7,
                       "Standard sets: Nature, Fire, Water, Storm, Citrus, Sketchbook, Midas")
        XCTAssertEqual(CosmeticBundle.starterGiftIDs, ["nature", "fire", "water", "storm"],
                       "the post-tutorial choice is exactly the four element sets")
        for id in CosmeticBundle.starterGiftIDs {
            XCTAssertTrue(CosmeticBundle.activeIDs.contains(id), "starter set \(id) must be active")
        }
        XCTAssertTrue(CosmeticBundle.activeIDs.contains("aurora"), "Starter Pack's Aurora stays on sale")
        for track in GameModeCatalogue.challengeTracks {
            guard let id = ChallengeTrackMode.rewardBundleID(for: track.trackID) else { continue }
            XCTAssertTrue(CosmeticBundle.activeIDs.contains(id), "track reward \(id) must be active")
        }
        // Retired sets are never listed: the featured bundle and "containing"
        // lookups only see active ones.
        XCTAssertTrue(CosmeticBundle.bundles(containing: BallSkin.cathedral).isEmpty)
        XCTAssertEqual(CosmeticBundle.bundles(containing: TrailColor.smoke).map(\.id), ["haunted"])
        // Every active collection is FULL (all six slots), so all are sold.
        XCTAssertEqual(CosmeticSale.fullCollections.map(\.id), active.map(\.id))
        for b in active { XCTAssertTrue(b.isComplete, "\(b.id) must fill all six slots") }
    }

    // MARK: - On-sale rule (CosmeticSale)

    /// A piece is on sale only as a member of a full active collection.
    /// Held pieces — retired sets, seasonal sets, displaced pieces, pieces in
    /// no collection — are never in the Shop rotation and cannot be bought.
    func testOnSaleRule_heldPiecesAreNeverShownOrSold() {
        let store = calendarStore()
        let launch = eastern(2026, 12, 1)
        // On sale: pieces of full active launch collections.
        XCTAssertTrue(CosmeticSale.isOnSale(BallSkin.jade, at: launch, store: store))
        XCTAssertTrue(CosmeticSale.isOnSale(TrailColor.forest, at: launch, store: store))
        XCTAssertEqual(CosmeticSale.collectionID(of: TrailColor.smoke), "haunted")
        // Held: retired set, seasonal set, displaced in the quality round, loose.
        XCTAssertTrue(CosmeticSale.isHeld(BallSkin.cathedral), "retired set")
        XCTAssertTrue(CosmeticSale.isHeld(BallSkin.pumpkin), "seasonal ball")
        XCTAssertTrue(CosmeticSale.isHeld(Boundary.pumpkin), "seasonal boundary")
        XCTAssertTrue(CosmeticSale.isHeld(GoalSkin.meadow), "displaced from Nature")
        XCTAssertTrue(CosmeticSale.isHeld(GoalSkin.obsidian), "displaced from Haunted")
        XCTAssertTrue(CosmeticSale.isHeld(TrailColor.snake), "displaced from Ancient Temple")
        XCTAssertTrue(CosmeticSale.isHeld(BallSkin.blue), "in no collection")
        for held in [BallSkin.cathedral, .pumpkin, .blue, .silver] {
            XCTAssertFalse(CosmeticSale.isOnSale(held, at: eastern(2030, 1, 1), store: store),
                           "\(held.rawValue) is never on sale, whatever the date")
        }
        // The Shop rotation holds on-sale pieces only.
        XCTAssertTrue(ShopRotation.ballPool.allSatisfy { CosmeticSale.isOnSale($0) })
        XCTAssertTrue(ShopRotation.goalPool.allSatisfy { CosmeticSale.isOnSale($0) })
        XCTAssertTrue(ShopRotation.trailPool.allSatisfy { CosmeticSale.isOnSale($0) })
        XCTAssertTrue(ShopRotation.floorPool.allSatisfy { CosmeticSale.isOnSale($0) })
        XCTAssertTrue(ShopRotation.pitPool.allSatisfy { CosmeticSale.isOnSale($0) })
        XCTAssertTrue(ShopRotation.boundaryPool.allSatisfy { CosmeticSale.isOnSale($0) })
        XCTAssertFalse(ShopRotation.ballPool.contains(.cathedral))
        XCTAssertFalse(ShopRotation.goalPool.contains(.meadow))
        XCTAssertTrue(ShopRotation.bundlePool.allSatisfy { $0.isComplete && !$0.isRetired })
        // Buying a held piece is refused and spends nothing.
        let gs = makeCleanState()
        gs.coinBalance = 100_000
        XCTAssertFalse(gs.purchase(BallSkin.cathedral))
        XCTAssertFalse(gs.purchase(GoalSkin.meadow))
        XCTAssertFalse(gs.purchase(BallSkin.blue))
        XCTAssertEqual(gs.coinBalance, 100_000)
        XCTAssertFalse(gs.isOwned(BallSkin.cathedral))
        // A retired set is not sold as a set either.
        let retired = CosmeticBundle.catalogue.first { $0.id == "cathedral" }!
        XCTAssertFalse(gs.purchaseBundle(retired, price: 0))
        // A piece of a full collection still sells one at a time.
        XCTAssertTrue(gs.purchase(BallSkin.jade))
    }

    /// A player who already owns a held piece keeps it and can equip it.
    func testOnSaleRule_ownersKeepAndEquipHeldPieces() {
        let gs = makeCleanState()
        gs.ownedBallSkins.insert(BallSkin.cathedral.rawValue)
        gs.ownedGoals.insert(GoalSkin.meadow.rawValue)
        XCTAssertTrue(gs.isOwned(BallSkin.cathedral))
        XCTAssertTrue(gs.equip(BallSkin.cathedral))
        XCTAssertEqual(gs.activeSkin, .cathedral)
        XCTAssertTrue(gs.equip(GoalSkin.meadow))
        XCTAssertEqual(gs.equippedGoal, .meadow)
    }

    /// Defaults and exempt pieces are not held.  Exempt = earned or
    /// purchase-only, never sold for coins.
    func testOnSaleRule_defaultsAndExemptPieces() {
        XCTAssertEqual(CosmeticSale.exemptBalls, [.diamond, .moneyBall, .trophy])
        XCTAssertEqual(CosmeticSale.exemptTrails, [.moneyRoll])
        XCTAssertEqual(CosmeticSale.exemptFloors, [.moneyFull])
        for ball in CosmeticSale.exemptBalls {
            XCTAssertFalse(ball.isCoinPurchasable, "\(ball.rawValue) is never sold for coins")
            XCTAssertFalse(CosmeticSale.isHeld(ball))
        }
        XCTAssertFalse(TrailColor.moneyRoll.isCoinPurchasable)
        XCTAssertFalse(Floor.moneyFull.isCoinPurchasable)
        for piece in CosmeticBundle.rollAlong.balls { XCTAssertFalse(CosmeticSale.isHeld(piece)) }
        XCTAssertFalse(CosmeticSale.isHeld(TrailColor.classic))
        XCTAssertFalse(CosmeticSale.isHeld(Floor.starter))
        XCTAssertFalse(CosmeticSale.isHeld(Pit.starter))
        XCTAssertFalse(CosmeticSale.isHeld(Boundary.starter))
        XCTAssertFalse(CosmeticSale.isHeld(GoalSkin.starter))
        // Every coin-buyable piece is either on sale in a full collection or held.
        for ball in BallSkin.allCases where ball.isCoinPurchasable {
            XCTAssertNotEqual(CosmeticSale.collectionID(of: ball) != nil, CosmeticSale.isHeld(ball), ball.rawValue)
        }
    }

    /// Seasonal events: every seasonal entry is retired as a set and features
    /// one FULL active collection.  Events sell no loose pieces: the seasonal
    /// ball and boundary are held.
    func testSeasonalEvents_featureFullCollectionsOnly() {
        let events = SeasonalEvent.all
        XCTAssertEqual(events.count, 16)
        for e in events {
            XCTAssertTrue(e.bundle.isRetired, "\(e.id) must not be sold as a set")
            XCTAssertNotNil(e.featuredCollection, "\(e.id) features a full active collection")
            XCTAssertEqual(e.featuredCollection?.isComplete, true)
            for ball in e.bundle.balls where !CosmeticSale.isExempt(ball) && CosmeticSale.collectionID(of: ball) == nil {
                XCTAssertTrue(CosmeticSale.isHeld(ball), "\(ball.rawValue) is not sold loose")
            }
        }
        let halloween = events.first { $0.id == "halloween-2026" }!
        XCTAssertEqual(halloween.featuredCollection?.id, "haunted")
        let mid = eastern(2026, 10, 20)
        XCTAssertTrue(halloween.isOpen(at: mid))
        XCTAssertFalse(CosmeticSale.isOnSale(BallSkin.pumpkin, at: mid, store: calendarStore()),
                       "the seasonal ball is not sold, even in season")
        XCTAssertTrue(SeasonalEvent.features(CosmeticBundle.active.first { $0.id == "haunted" }!, at: mid))
    }

    /// The Catalog's Collections filter is by rarity band only (All /
    /// Standard / Rare / Legendary): every band has collections on sale, so
    /// no filter choice is ever empty at launch.
    func testCatalogRarityFilter_everyBandHasActiveCollections() {
        let bands = Set(CosmeticBundle.active.map(\.rarity))
        XCTAssertEqual(bands, Set(BundleRarity.allCases))
        for band in BundleRarity.allCases {
            XCTAssertFalse(CosmeticBundle.active.filter { $0.rarity == band }.isEmpty,
                           "no active \(band.label) collection")
        }
    }

    /// Seasonal windows repeat every year; holidays that move use their
    /// per-year rows.
    func testSeasonalWindowsRepeatYearly() {
        for b in CosmeticBundle.catalogue where b.isLimitedTime {
            guard let from = b.availableFrom, let until = b.availableUntil else {
                XCTFail("seasonal collection \(b.id) needs both dates"); continue
            }
            let mid = from.addingTimeInterval(until.timeIntervalSince(from) / 2)
            XCTAssertTrue(b.isOpen(at: mid), "\(b.id) open mid-window")
            XCTAssertFalse(b.isOpen(at: until.addingTimeInterval(86_400)),
                           "\(b.id) closed the day after its window")
            XCTAssertFalse(b.isExpired)
            if let rows = CosmeticSchedule.builtInSeasonalWindows[b.id] {
                for (year, w) in rows {
                    let open = w.from.easternMidnight
                    let close = w.until.easternMidnight
                    XCTAssertTrue(b.isOpen(at: open), "\(b.id) \(year) opens on its day")
                    XCTAssertFalse(b.isOpen(at: open.addingTimeInterval(-1)), "\(b.id) \(year) not before")
                    XCTAssertFalse(b.isOpen(at: close), "\(b.id) \(year) closed on its end day")
                }
            } else {
                let nextYear = CosmeticSchedule.eastern.date(byAdding: .year, value: 1, to: mid)!
                XCTAssertTrue(b.isOpen(at: nextYear), "\(b.id) returns the following year")
            }
        }
        // Approved window changes.
        let countdown = CosmeticBundle.catalogue.first { $0.id == "newyear-2027" }!
        XCTAssertTrue(countdown.isOpen(at: eastern(2027, 12, 26)))
        XCTAssertFalse(countdown.isOpen(at: eastern(2027, 12, 26, plus: -1)))
        let lunar = CosmeticBundle.catalogue.first { $0.id == "lunar-2027" }!
        XCTAssertTrue(lunar.isOpen(at: eastern(2028, 1, 26)), "Lunar New Year 2028 is Jan 26")
    }

    /// A server row for one year of a seasonal collection replaces that year.
    func testSeasonalWindow_serverRowOverridesOneYear() {
        let store = calendarStore()
        store.apply([CosmeticCalendarStore.Row(collection_id: "mardigras-2027",
                                               starts_on: "2027-02-01", ends_on: "2027-02-12")])
        let mardi = CosmeticBundle.catalogue.first { $0.id == "mardigras-2027" }!
        let w = CosmeticSchedule.seasonalWindow(for: mardi, at: eastern(2027, 1, 20), store: store)
        XCTAssertEqual(w?.from, eastern(2027, 2, 1))
        XCTAssertEqual(w?.until, eastern(2027, 2, 12))
    }

    // MARK: - Quality round: Champion, Winter, Ancient Temple, Abyssal Depths, Space Traveler

    /// The reshaped sets: what each holds now, that replacements took the
    /// tier of the piece they replaced (so no price moved), and that pieces
    /// redrawn in place kept their ids.
    func testQualityRound_reshapedSetsKeepTiersAndPrices() {
        func set(_ id: String) -> CosmeticBundle { CosmeticBundle.active.first { $0.id == id }! }

        let champion = set("champion")
        XCTAssertEqual(champion.balls, [.trophy])
        XCTAssertEqual(champion.goals, [.winnersCircle])
        XCTAssertEqual(champion.trails, [.victoryLap])
        XCTAssertEqual(GoalSkin.winnersCircle.tier, GoalSkin.quasar.tier)
        XCTAssertEqual(TrailColor.victoryLap.tier, TrailColor.cometTrail.tier)
        XCTAssertEqual(champion.rarity, .legendary)

        let temple = set("ancient-temple")
        XCTAssertEqual(temple.trails, [.glyphs])
        XCTAssertEqual(TrailColor.glyphs.tier, TrailColor.snake.tier)
        XCTAssertTrue(CosmeticBundle.bundles(containing: TrailColor.snake).isEmpty,
                      "Snake left Ancient Temple and is in no set on sale")

        let abyss = set("abyssal-depths")
        XCTAssertEqual(abyss.pits, [.vent])
        XCTAssertEqual(Pit.vent.tier, Pit.space.tier)
        XCTAssertTrue(Pit.vent.hasDrawnArt)

        let winter = set("winter")
        XCTAssertEqual(winter.floors, [.twilight]); XCTAssertEqual(winter.pits, [.twilight])
        XCTAssertEqual(Floor.twilight.rawValue, "twilight"); XCTAssertEqual(Floor.twilight.displayName, "Snowfield")
        XCTAssertEqual(Pit.twilight.rawValue, "twilight");   XCTAssertEqual(Pit.twilight.displayName, "Crevasse")
        XCTAssertEqual(Floor.twilight.tier, .standard); XCTAssertEqual(Pit.twilight.tier, .standard)

        // Prices are the sum of unchanged tiers (music is not charged in 1.0).
        func sum(_ b: CosmeticBundle) -> Int {
            b.balls[0].coinCost + b.goals[0].coinCost + b.trails[0].coinCost
                + b.floors[0].coinCost + b.pits[0].coinCost + b.boundaries[0].coinCost
        }
        for b in [champion, temple, abyss, winter] {
            XCTAssertEqual(b.fullPrice(), sum(b), "\(b.id)")
        }
    }

    /// Space Traveler: a full six-slot set on sale from launch, built from
    /// Quasar, Comet and the Space pit plus the retired Space Travel set's
    /// UFO and Moon and a new Starship Hull wall.
    func testQualityRound_spaceTravelerIsAFullLaunchSet() {
        guard let b = CosmeticBundle.active.first(where: { $0.id == "space-traveler" }) else {
            return XCTFail("Space Traveler must be on sale")
        }
        XCTAssertEqual(b.balls, [.ufo]);          XCTAssertEqual(b.goals, [.quasar])
        XCTAssertEqual(b.trails, [.cometTrail]);  XCTAssertEqual(b.floors, [.moon])
        XCTAssertEqual(b.pits, [.space]);         XCTAssertEqual(b.boundaries, [.hull])
        XCTAssertFalse(b.isLimitedTime)
        XCTAssertTrue(CosmeticSchedule.launchBundleIDs.contains(b.id), "on sale at launch: no calendar row")
        XCTAssertTrue(CosmeticSchedule.isReleased(b, at: eastern(2026, 12, 1), store: calendarStore()))
        XCTAssertEqual(b.rarity, .legendary)
        XCTAssertEqual(Boundary.hull.tier, Boundary.starlight.tier)
        // Its pieces are out at launch too (the retired set's March date no longer holds them back).
        XCTAssertTrue(CosmeticSchedule.isReleased(BallSkin.ufo, at: eastern(2026, 12, 1), store: calendarStore()))
        XCTAssertTrue(CosmeticSchedule.isReleased(Floor.moon, at: eastern(2026, 12, 1), store: calendarStore()))
        // The retired "space-travel" set is kept for owners but never sold.
        XCTAssertFalse(CosmeticBundle.activeIDs.contains("space-travel"))
        XCTAssertNotNil(CosmeticBundle.catalogue.first { $0.id == "space-travel" })
    }

    /// Quality-standard audit: the Space pit and the Tide Pool pit are layered
    /// drawn art, so they stay visible (frozen) under Reduce Motion, and both
    /// carry a slow animated overlay.  Ids, tiers and prices are unchanged.
    func testQualityAudit_spaceAndTidePoolPitsAreDrawnArt() {
        XCTAssertTrue(Pit.space.hasDrawnArt)
        XCTAssertTrue(Pit.space.hasAnimatedOverlay)
        XCTAssertTrue(Pit.tidePool.hasDrawnArt)
        XCTAssertTrue(Pit.tidePool.hasAnimatedOverlay)
        XCTAssertEqual(Pit.space.rawValue, "space")
        XCTAssertEqual(Pit.space.tier, .exclusive)
        XCTAssertEqual(Pit.tidePool.tier, .standard)
        XCTAssertEqual(TrailColor.cometTrail.displayName, "Comet")
    }

    // MARK: - Music is not in 1.0

    /// Quality round: Citrus is tropical citrus and Midas is one golden set.
    /// New pieces take the tier of the piece they replaced, so neither set's
    /// price moves, and the displaced pieces are in no collection on sale.
    func testQualityRound_citrusAndMidas() {
        let citrus = CosmeticBundle.active.first { $0.id == "citrus" }!
        XCTAssertEqual(citrus.balls, [.lemon])
        XCTAssertEqual(citrus.goals, [.citrusSlice])
        XCTAssertEqual(citrus.trails, [.zest])
        XCTAssertEqual(citrus.floors, [.grove])
        XCTAssertEqual(citrus.pits, [.tidePool])
        XCTAssertEqual(citrus.boundaries, [.citrus])
        XCTAssertEqual(GoalSkin.citrusSlice.tier, GoalSkin.flame.tier)
        XCTAssertEqual(TrailColor.zest.tier, TrailColor.ember.tier)
        XCTAssertEqual(Floor.grove.tier, Floor.dusk.tier)
        XCTAssertEqual(Pit.tidePool.tier, Pit.sunset.tier)
        XCTAssertEqual(citrus.fullPrice(), 5_250)
        XCTAssertEqual(citrus.rarity, .standard)

        let midas = CosmeticBundle.active.first { $0.id == "midas" }!
        XCTAssertEqual(midas.goals, [.bullion])
        XCTAssertEqual(midas.floors, [.goldLeaf])
        XCTAssertEqual(midas.pits, [.vault])
        XCTAssertEqual(Floor.goldLeaf.tier, Floor.mirage.tier)
        XCTAssertEqual(Pit.vault.tier, Pit.mirage.tier)
        XCTAssertEqual(midas.fullPrice(), 5_000)
        XCTAssertEqual(midas.rarity, .standard)

        // Displaced pieces sit in neither set any more.
        for b in [citrus, midas] {
            XCTAssertFalse(b.goals.contains(.flame))
            XCTAssertFalse(b.trails.contains(.ember))
            XCTAssertFalse(b.floors.contains(.dusk) || b.floors.contains(.mirage))
            XCTAssertFalse(b.pits.contains(.sunset) || b.pits.contains(.mirage))
        }
    }

    /// Approved pit redraws: drawn art for 18 pits; only the two Rare ones
    /// (Graveyard, Aurora) move; Midnight shows as "Moonlit" with its old id.
    func testPitRedraws_tiersAndNames() {
        let drawn = Pit.allCases.filter { $0.hasDrawnArt }
        // 18 redraws + the Fire, Water and Storm starter pits, plus the pits
        // added or redrawn in the quality round (Tide Pool, Vault, Winter's
        // Crevasse, the Sea Vent, …).  A drawn pit may now be any tier and may
        // move gently.
        XCTAssertGreaterThanOrEqual(drawn.count, 21)
        XCTAssertTrue(Pit.tidePool.hasDrawnArt && Pit.vault.hasDrawnArt)
        XCTAssertTrue(drawn.contains(.twilight) && drawn.contains(.vent))
        XCTAssertEqual(Pit.graveyard.tier, .rare)
        XCTAssertEqual(Pit.aurora.tier, .rare)
        XCTAssertEqual(Pit.graveyard.coinCost, 1_000)
        XCTAssertEqual(Pit.midnight.displayName, "Moonlit")
        XCTAssertEqual(Pit.midnight.rawValue, "midnight")
        let haunted = CosmeticBundle.catalogue.first { $0.id == "haunted" }!
        XCTAssertEqual(haunted.fullPrice(), 7_000)
    }

    /// Quality round — Haunted, Cosmos, Aurora and Lava Flow: pieces redrawn
    /// in place keep their ids, tiers and prices; Haunted's goal is the new
    /// Pentagram (taking Obsidian's tier), and Obsidian is in no active set.
    func testQualityRound_hauntedCosmosAuroraLavaFlow() {
        func set(_ id: String) -> CosmeticBundle { CosmeticBundle.catalogue.first { $0.id == id }! }
        let haunted = set("haunted")
        XCTAssertEqual(haunted.goals, [.pentagram])
        XCTAssertEqual(GoalSkin.pentagram.tier, GoalSkin.obsidian.tier)
        XCTAssertEqual(GoalSkin.pentagram.displayName, "Pentagram")
        XCTAssertEqual(GoalSkin.pentagram.rawValue, "pentagram")
        XCTAssertEqual(haunted.fullPrice(), 7_000)
        XCTAssertFalse(CosmeticBundle.active.contains { $0.contains(GoalSkin.obsidian) },
                       "Obsidian left Haunted and is in no collection on sale")
        XCTAssertEqual(CosmeticBundle.bundles(containing: GoalSkin.pentagram).map(\.id), ["haunted"])
        // Redrawn in place: same ids, tiers and so prices.
        XCTAssertEqual(Floor.fog.rawValue, "fog");           XCTAssertEqual(Floor.fog.tier, .standard)
        XCTAssertEqual(Floor.midnight.rawValue, "midnight"); XCTAssertEqual(Floor.midnight.tier, .standard)
        XCTAssertEqual(Floor.ember.rawValue, "ember");       XCTAssertEqual(Floor.ember.tier, .standard)
        XCTAssertEqual(Pit.evil.rawValue, "evil");           XCTAssertEqual(Pit.evil.tier, .exclusive)
        XCTAssertEqual(Pit.midnight.tier, .standard)
        XCTAssertEqual(Floor.aurora.tier, .exclusive)
        // Drawn pits show under Reduce Motion too (frozen), never a flat fill.
        for p in [Pit.evil, .midnight, .graveyard, .aurora] {
            XCTAssertTrue(p.hasDrawnArt, "\(p) should be drawn art")
        }
        // The Aurora floor is no longer hidden under Reduce Motion: its faint
        // ribbons hold still instead.
        XCTAssertFalse(FloorOverlayView.hiddenUnderReduceMotion(.aurora))
        // The four sets are still complete (one piece per slot).
        for id in ["haunted", "cosmos", "aurora", "lava-flow"] {
            let b = set(id)
            XCTAssertEqual([b.balls.count, b.goals.count, b.trails.count,
                            b.floors.count, b.pits.count, b.boundaries.count],
                           [1, 1, 1, 1, 1, 1], "\(id) is not a complete set")
        }
    }

    /// While music is off, no collection offers, prices, grants or requires a
    /// music track, and no player-facing summary names one — but the music
    /// data stays in place so it can return in an update.
    func testMusicOff_collectionsNeitherOfferNorPriceMusic() throws {
        try XCTSkipIf(CosmeticFeatures.musicEnabled, "music is offered")
        let gs = makeCleanState()
        for b in CosmeticBundle.catalogue {
            XCTAssertTrue(b.offeredMusic.isEmpty, "\(b.id) offers music")
            XCTAssertFalse(b.music.isEmpty, "\(b.id) lost its music data")
            XCTAssertFalse(b.displaySummary.lowercased().contains(" music"),
                           "\(b.id) summary still names music: \(b.displaySummary)")
            XCTAssertEqual(b.itemCount, b.balls.count + b.goals.count + b.trails.count
                           + b.floors.count + b.pits.count + b.boundaries.count)
            XCTAssertEqual(b.proratedPrice(in: gs), b.fullPrice(),
                           "\(b.id): a clean state pays the full (music-free) price")
        }
        // Aurora: 8,500 without its music track (the Aurora pit is Rare,
        // 1,000 coins, since its art moves).
        let aurora = CosmeticBundle.catalogue.first { $0.id == "aurora" }!
        XCTAssertEqual(aurora.fullPrice(), 8_500)
        // Owning every offered item completes a collection; music isn't needed.
        aurora.balls.forEach { gs.grant($0) }; aurora.goals.forEach { gs.grant($0) }
        aurora.trails.forEach { gs.grant($0) }; aurora.floors.forEach { gs.grant($0) }
        aurora.pits.forEach { gs.grant($0) }; aurora.boundaries.forEach { gs.grant($0) }
        XCTAssertFalse(gs.isOwned(MusicTrack.aurora))
        XCTAssertTrue(gs.completedBundleIDs.contains("aurora"))
    }

    /// Buying a collection while music is off charges nothing for music and
    /// grants no music track.
    func testMusicOff_bundlePurchaseGrantsNoMusic() throws {
        try XCTSkipIf(CosmeticFeatures.musicEnabled, "music is offered")
        let gs = makeCleanState()
        let aurora = CosmeticBundle.catalogue.first { $0.id == "aurora" }!
        gs.coinBalance = aurora.fullPrice()
        XCTAssertTrue(gs.purchaseBundle(aurora, price: aurora.fullPrice()))
        XCTAssertEqual(gs.coinBalance, 0)
        XCTAssertFalse(gs.isOwned(MusicTrack.aurora), "no music is granted while music is off")
    }

    // MARK: - Sell Back: free gifts keyed by unique id

    /// Two items share the name "aurora" (the goal and the trail).  Gifting the
    /// goal must leave the coin-bought trail sellable, and Sell Back must keep
    /// the gifted goal.
    func testFreeGift_doesNotMarkSameNamedItemInAnotherSlot() {
        XCTAssertEqual(GoalSkin.aurora.rawValue, TrailColor.aurora.rawValue,
                       "the test needs two same-named items in different slots")
        let gs = makeCleanState()
        gs.coinBalance = TrailColor.aurora.coinCost
        XCTAssertTrue(gs.purchase(TrailColor.aurora))   // bought with coins
        XCTAssertEqual(gs.coinBalance, 0)

        let gift = CosmeticBundle(id: "test-gift", displayName: "Gift", tagline: "", contentSummary: "",
                                  balls: [], goals: [.aurora], trails: [], floors: [], pits: [], music: [])
        gs.grantBundleFree(gift)

        XCTAssertTrue(gs.isFreeGranted(GoalSkin.aurora))
        XCTAssertFalse(gs.isFreeGranted(TrailColor.aurora), "the same-named trail is not a gift")

        let preview = gs.coinLiquidationPreview()
        XCTAssertEqual(preview.count, 1, "only the coin-bought trail is sellable")
        XCTAssertEqual(preview.coins, gs.sellBackValue(TrailColor.aurora))
        gs.liquidateCoinCosmetics()
        XCTAssertTrue(gs.isOwned(GoalSkin.aurora), "the gifted goal is kept")
        XCTAssertFalse(gs.isOwned(TrailColor.aurora), "the bought trail was sold back")
        XCTAssertEqual(gs.coinBalance, TrailColor.aurora.coinCost / 2)
    }

    /// Old saves held bare names.  Each is expanded once, conservatively, to
    /// every owned item with that name (a gift can never become sellable);
    /// names matching nothing owned are dropped; new-format ids pass through.
    func testFreeGift_oldBareNamesAreQualifiedOnLoad() {
        let qualified = GameState.qualifyFreeGrants(
            ["aurora", "nothing-owned", "Floor:aurora"],
            balls: [], goals: ["aurora"], trails: ["aurora"], floors: [],
            pits: [], boundaries: [], music: [])
        XCTAssertEqual(qualified, ["GoalSkin:aurora", "TrailColor:aurora", "Floor:aurora"])

        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        defaults.set(["aurora"], forKey: "ra_freeGrantedItems")
        defaults.set(["aurora"], forKey: "ra_ownedGoals")
        let gs = GameState(defaults: defaults)
        XCTAssertTrue(gs.isFreeGranted(GoalSkin.aurora))
        XCTAssertFalse(gs.isFreeGranted(TrailColor.aurora), "not owned → not marked")
        XCTAssertEqual(defaults.stringArray(forKey: "ra_freeGrantedItems"), ["GoalSkin:aurora"],
                       "the upgraded set is saved")
    }

    // MARK: - Diamond ball is Locker-only

    func testDiamondBall_isLockerOnly() {
        XCTAssertTrue(BallSkin.diamond.isLockerOnly)
        XCTAssertFalse(CosmeticBundle.catalogue.contains { $0.balls.contains(.diamond) },
                       "the Diamond ball is in no collection")
        XCTAssertFalse(BallPack.catalogue.contains { $0.skins.contains(.diamond) },
                       "the Diamond ball is in no ball pack")
        XCTAssertFalse(ShopRotation.ballPool.contains(.diamond),
                       "the Diamond ball never rotates into the Shop")
        XCTAssertTrue(CosmeticSchedule.releaseKeys(of: BallSkin.diamond).isEmpty,
                      "the Diamond ball is not on the release calendar")
        XCTAssertFalse(BallSkin.diamond.isCoinPurchasable)
    }

}

// MARK: - Loadout preview recording

/// The bundled preview recording (PreviewReplay.json) must decode and be
/// playable, or every loadout preview falls back to a still picture.
final class PreviewReplayTests: XCTestCase {

    func testBundledReplayDecodesAndIsPlayable() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: ReplayStore.bundledName,
                                                withExtension: "json"),
                                "PreviewReplay.json is not in the app bundle")
        let replay = try XCTUnwrap(ReplayStore.decode(try Data(contentsOf: url)))
        XCTAssertTrue(replay.isUsable)
        XCTAssertGreaterThan(replay.duration, 3)
        XCTAssertNotNil(replay.endEventTime, "the run should end at the goal or a pit")
        for f in replay.frames {
            XCTAssertTrue((-0.2...1.2).contains(f[1]) && (-0.2...1.2).contains(f[2]))
        }
    }

    func testPositionInterpolatesBetweenFrames() throws {
        let json = """
        {"version":1,"fps":60,"arenaWidth":100,"arenaHeight":200,"ballRadius":18,
         "coinRadius":9,"holes":[],"goal":{"x":0.5,"y":0.1},"coins":[],
         "frames":[[0,0,0,0],[1,1,1,0]],"events":[]}
        """
        let replay = try XCTUnwrap(ReplayStore.decode(Data(json.utf8)))
        let mid = replay.position(at: 0.5)
        XCTAssertEqual(mid.x, 50, accuracy: 0.001)
        XCTAssertEqual(mid.y, 100, accuracy: 0.001)
        XCTAssertEqual(replay.position(at: 5).x, 100, accuracy: 0.001)
    }

    func testBadFileIsRejected() {
        XCTAssertNil(ReplayStore.decode(Data("not json".utf8)))
        let backwards = """
        {"version":1,"fps":60,"arenaWidth":100,"arenaHeight":200,"ballRadius":18,
         "coinRadius":9,"holes":[],"goal":{"x":0.5,"y":0.1},"coins":[],
         "frames":[[1,0,0,0],[0,1,1,0]],"events":[]}
        """
        XCTAssertNil(ReplayStore.decode(Data(backwards.utf8)), "time running backwards")
    }
}

/// Where animated cosmetics may move (shop grids stay still; previews move at
/// most 30 fps; Reduce Motion stops every preview; play is unchanged).
final class CosmeticMotionTests: XCTestCase {

    func testGridsAndListsNeverAnimate() {
        XCTAssertFalse(CosmeticMotion.still.showsAnimatedRenderers(reduceMotion: false))
        XCTAssertTrue(CosmeticMotion.still.isPaused(reduceMotion: false))
    }

    func testPreviewAnimatesAtMostThirtyFPS() {
        XCTAssertTrue(CosmeticMotion.preview.showsAnimatedRenderers(reduceMotion: false))
        XCTAssertFalse(CosmeticMotion.preview.isPaused(reduceMotion: false))
        XCTAssertEqual(CosmeticMotion.preview.frameInterval(nil) ?? 0, 1.0 / 30.0, accuracy: 1e-9)
        // A renderer already slower than 30 fps keeps its own rate.
        XCTAssertEqual(CosmeticMotion.preview.frameInterval(0.1) ?? 0, 0.1, accuracy: 1e-9)
    }

    func testReduceMotionStopsEveryPreview() {
        XCTAssertFalse(CosmeticMotion.preview.showsAnimatedRenderers(reduceMotion: true))
        XCTAssertTrue(CosmeticMotion.preview.isPaused(reduceMotion: true))
        XCTAssertFalse(CosmeticMotion.held.showsAnimatedRenderers(reduceMotion: true))
    }

    func testHeldPreviewKeepsItsRenderersButStopsTicking() {
        XCTAssertTrue(CosmeticMotion.held.showsAnimatedRenderers(reduceMotion: false))
        XCTAssertTrue(CosmeticMotion.held.isPaused(reduceMotion: false))
    }

    func testTilesDrawTheRealRenderersAtTheTileRate() {
        for state in [CosmeticMotion.tile, .tileHeld, .tileFrozen] {
            XCTAssertTrue(state.showsAnimatedRenderers(reduceMotion: false))
            XCTAssertTrue(state.showsAnimatedRenderers(reduceMotion: true),
                          "a frozen tile still uses the game's renderer")
            XCTAssertEqual(state.frameInterval(nil) ?? 0, 1.0 / ShopTileMotion.fps, accuracy: 1e-9)
            XCTAssertTrue(state.isTile)
        }
        XCTAssertGreaterThanOrEqual(ShopTileMotion.fps, 12)
        XCTAssertLessThanOrEqual(ShopTileMotion.fps, 15)
        // A visible tile moves; scrolling, off screen or frozen it does not.
        XCTAssertFalse(CosmeticMotion.tile.isPaused(reduceMotion: false))
        XCTAssertTrue(CosmeticMotion.tile.isPaused(reduceMotion: true))
        XCTAssertTrue(CosmeticMotion.tileHeld.isPaused(reduceMotion: false))
        XCTAssertTrue(CosmeticMotion.tileFrozen.isPaused(reduceMotion: false))
        // Held tiles keep their frame; frozen balls show their still art.
        XCTAssertTrue(CosmeticMotion.tileHeld.holdsFrame)
        XCTAssertFalse(CosmeticMotion.tileFrozen.holdsFrame)
        XCTAssertTrue(CosmeticMotion.tileFrozen.showsBallStillArt)
        XCTAssertFalse(CosmeticMotion.tile.showsBallStillArt)
        XCTAssertNil(EnvironmentValues().cosmeticHeroTime)
        XCTAssertFalse(EnvironmentValues().cosmeticTilesScrolling)
    }

    func testHeroFramesSitAtThePulsePeak() {
        // Breathing targets: sin(1.3 t) peaks at pi / 2.6.
        XCTAssertEqual(CosmeticTileHero.goal(.target), Double.pi / 2.6, accuracy: 1e-9)
        XCTAssertEqual(CosmeticTileHero.goal(.halo), Double.pi / 4, accuracy: 1e-9)
        // Everything else freezes past the first second, never at t = 0.
        XCTAssertEqual(CosmeticTileHero.time(for: TrailColor.fire), ShopTileMotion.defaultHeroTime)
        for goal in GoalSkin.allCases {
            XCTAssertGreaterThan(CosmeticTileHero.goal(goal), 0, "\(goal) hero frame")
        }
    }

    func testPlayIsUnchanged() {
        XCTAssertFalse(CosmeticMotion.live.isPaused(reduceMotion: true))
        XCTAssertNil(CosmeticMotion.live.frameInterval(nil))
        XCTAssertEqual(CosmeticMotion.live.frameInterval(1.0 / 30.0) ?? 0, 1.0 / 30.0, accuracy: 1e-9)
        XCTAssertEqual(EnvironmentValues().cosmeticMotion, .live)
    }
}

// MARK: - Trail marks (every trail is laid in place and fades on a timer)

// @MainActor: `ShopTrailCurve` is a View, so its statics are main-actor isolated.
@MainActor
final class TrailMarksTests: XCTestCase {

    /// Marks are laid every `spacing` points along the path, with laid times
    /// interpolated along the step — the same density at any speed.
    func testMarksAreLaidAtFixedSpacing() {
        var m = TrailMarks()
        m.add(CGPoint(x: 0, y: 0), at: 100.0)
        m.add(CGPoint(x: 20, y: 0), at: 100.1)          // one fast step: 20 pt
        XCTAssertEqual(m.count, 1 + 5)                   // start + 20 / 4
        for i in 1..<m.count {
            let d = m.points[i].x - m.points[i - 1].x
            XCTAssertEqual(d, TrailMarks.spacing, accuracy: 0.0001)
            XCTAssertGreaterThan(m.times[i], m.times[i - 1])
        }
        XCTAssertEqual(m.times.last ?? 0, 100.1, accuracy: 0.0001)
        // A step shorter than the spacing lays nothing.
        m.add(CGPoint(x: 21, y: 0), at: 100.12)
        XCTAssertEqual(m.count, 6)
    }

    /// Marks never move once laid: later steps only append.
    func testLaidMarksNeverMove() {
        var m = TrailMarks()
        m.add(.zero, at: 0)
        m.add(CGPoint(x: 12, y: 0), at: 0.05)
        let before = m.points
        m.add(CGPoint(x: 12, y: 40), at: 0.10)
        XCTAssertEqual(Array(m.points.prefix(before.count)), before)
    }

    /// Marks expire by age, even when the ball stops.
    func testMarksExpireByAge() {
        var m = TrailMarks()
        m.add(.zero, at: 0)
        m.add(CGPoint(x: 40, y: 0), at: 0.2)
        XCTAssertEqual(m.count, 11)
        // Ball resting at the last mark: nothing new is laid, old marks go.
        m.add(CGPoint(x: 40, y: 0), at: 0.2 + TrailMarks.lifetime - 0.01)
        XCTAssertTrue(m.times.allSatisfy { 0.2 + TrailMarks.lifetime - 0.01 - $0 <= TrailMarks.lifetime })
        XCTAssertLessThan(m.count, 11)
        m.add(CGPoint(x: 40, y: 0), at: 10)
        XCTAssertTrue(m.isEmpty)
    }

    /// The cap bounds the buffer at any speed, and one step lays at most
    /// `maxPerStep` marks (a respawn jump can't flood it).
    func testCapAndPerStepLimit() {
        var m = TrailMarks()
        m.add(.zero, at: 0)
        m.add(CGPoint(x: 10_000, y: 0), at: 0.016)
        XCTAssertEqual(m.count, 1 + TrailMarks.maxPerStep)
        XCTAssertEqual(m.points.last?.x ?? 0, 10_000, accuracy: 0.001)
        var t = 0.016
        var x: CGFloat = 10_000
        for _ in 0..<200 { t += 0.016; x += 60; m.add(CGPoint(x: x, y: 0), at: t) }
        XCTAssertLessThanOrEqual(m.count, TrailMarks.cap)
    }

    /// A mark's seed comes from when it was laid, so it is the same however
    /// the buffer shifts or the camera moves.
    func testSeedIsStablePerMark() {
        var m = TrailMarks()
        m.add(.zero, at: 50)
        m.add(CGPoint(x: 40, y: 0), at: 50.2)
        let laid = m.times[5]
        let seed = trailSeed(laid)
        m.add(CGPoint(x: 80, y: 0), at: 50.4)
        m.add(CGPoint(x: 80, y: 0), at: 51.15)          // older marks expire, indices shift
        let idx = m.times.firstIndex(of: laid)
        XCTAssertNotNil(idx)
        if let idx { XCTAssertEqual(trailSeed(m.times[idx]), seed) }
        XCTAssertTrue((0..<1).contains(seed))
    }

    /// Replays rebuild exactly the marks the live game would have laid.
    func testReplayMarksMatchLiveMarks() {
        let samples: [(t: Double, p: CGPoint)] = (0..<60).map { i in
            (t: Double(i) / 60, p: CGPoint(x: CGFloat(i) * 5, y: CGFloat(i % 7)))
        }
        var live = TrailMarks()
        for s in samples { live.add(s.p, at: s.t) }
        let replay = TrailMarks.laid(along: samples, now: samples.last!.t)
        XCTAssertEqual(replay, live)
    }

    /// The Shop curve lays real marks: spaced along the curve, oldest first,
    /// none older than a lifetime, and the frozen frame puts the ball near
    /// the end with a full trail behind it.
    func testShopCurveLaysRealMarks() {
        let pts = ShopTrailCurve.unitCurve.map { CGPoint(x: $0.x * 100, y: $0.y * 100) }
        let frozen = ShopTrailCurve.marks(along: pts, t: 7.3, rolling: false)
        XCTAssertGreaterThan(frozen.points.count, 8)
        XCTAssertEqual(frozen.times, frozen.times.sorted())
        XCTAssertTrue(frozen.times.allSatisfy { 7.3 - $0 < TrailMarks.lifetime && $0 <= 7.3 })
        let rolling = ShopTrailCurve.marks(along: pts, t: 7.3, rolling: true)
        XCTAssertTrue(rolling.times.allSatisfy { 7.3 - $0 < TrailMarks.lifetime && $0 <= 7.3 + 1e-9 })
    }

    /// The rolling tile: the ball leaves past the right edge and stays off
    /// screen until the whole trail has faded, so a new lap never starts
    /// over the old trail.
    func testShopCurveHoldsOffscreenUntilTrailFades() {
        let unit = ShopTrailCurve.rollingCurve
        let pts = unit.map { CGPoint(x: $0.x * 100, y: $0.y * 100) }
        let visible = ShopTrailCurve.unitCurve.count
        XCTAssertGreaterThan(unit.last?.x ?? 0, 1.0)
        // Sample a few cycles finely: whenever a lap has just started (the
        // ball is near the left), no mark from the previous lap remains.
        var t = 0.0
        while t < 20 {
            let m = ShopTrailCurve.marks(along: pts, t: t, rolling: true, visibleCount: visible)
            XCTAssertEqual(m.lapBreak, 0)
            XCTAssertTrue(m.times.allSatisfy { t - $0 < TrailMarks.lifetime && $0 <= t + 1e-9 })
            if !m.ballVisible { XCTAssertGreaterThan(m.head.x, 100) }
            t += 0.05
        }
        XCTAssertGreaterThan(ShopTrailCurve.offscreenHold, TrailMarks.lifetime)
    }
}
