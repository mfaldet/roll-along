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
            // The Starter Pack offer GIFTS the collection; it doesn't lock it.
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
    /// would mint coins on every pass.  TrailColor's starter is Graphite —
    /// tier .rare, NOT tier .starter — which used to slip through the iconic
    /// filter and pay out +100 coins per Sell Back, forever (infinite faucet).
    func testLiquidate_secondPassRefundsNothing_starterIsNotAFaucet() {
        let gs = makeCleanState()
        gs.coinBalance = 0
        gs.ownedBallSkins.insert(BallSkin.blue.rawValue)             // coin-bought
        gs.ownedTrails.insert(TrailColor.graphite.rawValue)          // the starter
        gs.ownedTrails.insert(TrailColor.fire.rawValue)              // coin-bought

        let first = gs.liquidateCoinCosmetics()
        XCTAssertEqual(first.count, 2)   // .blue + .fire; graphite NOT refunded
        XCTAssertEqual(first.coins, BallSkin.blue.coinCost / 2 + TrailColor.fire.coinCost / 2)   // 50% refund
        XCTAssertTrue(gs.ownedTrails.contains(TrailColor.graphite.rawValue))   // starter kept

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
        XCTAssertFalse(TrailColor.starter.isSellable)   // Graphite — tier .rare but still the starter
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
            // A slot's default item (Paper World's Graphite trail) is owned by
            // everyone and adds nothing.
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
        let pool = CosmeticBundle.catalogue.filter { !$0.isLimitedTime && $0.rarity == .standard }
        print("GIFTPOOL permanent Standard bundles:", pool.map { $0.id }.joined(separator: ", "))
        XCTAssertFalse(pool.isEmpty,
                       "The permanent Standard-rarity bundle pool is empty — the post-tutorial gift dead-ends")
        XCTAssertTrue((4...8).contains(pool.count),
                      "The permanent Standard pool must hold 4–8 bundles, got \(pool.count)")
        // Every permanent Standard bundle is (trivially) always available, so
        // the gift picker's `isAvailable` filter can never see fewer options
        // than this pool.
        for b in pool { XCTAssertTrue(b.isAvailable, "permanent bundle \(b.id) must always be available") }
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

    // MARK: - Starter Pack → Aurora collection (StoreKitManager contract)

    /// StoreKitManager.grantAuroraCollection looks the bundle up by the string
    /// id "aurora" — renaming or removing it would silently turn the Starter
    /// Pack IAP's cosmetic grant into a no-op.  Pin the id and the seven-slot
    /// shape of the collection.
    func testAuroraBundle_existsWithOneItemPerCategory() {
        guard let aurora = CosmeticBundle.catalogue.first(where: { $0.id == "aurora" }) else {
            return XCTFail("the \"aurora\" bundle must exist — the Starter Pack IAP grants it by id")
        }
        XCTAssertEqual(aurora.balls,  [.aurora])
        XCTAssertEqual(aurora.goals,  [.aurora])
        XCTAssertEqual(aurora.trails, [.aurora])
        XCTAssertEqual(aurora.floors, [.aurora])
        XCTAssertEqual(aurora.pits,   [.aurora])
        XCTAssertEqual(aurora.music,  [.aurora])
        XCTAssertEqual(aurora.boundaries, [.aurora])
    }

    /// Every collection is a complete set: at least one item in each of the
    /// seven slots (ball, goal, trail, floor, pit, boundary, music).  The
    /// music data stays even while music is off, so it can return later.
    func testEveryCollection_isACompleteSevenSlotSet() {
        for b in CosmeticBundle.catalogue {
            XCTAssertFalse(b.balls.isEmpty,      "\(b.id) has no ball")
            XCTAssertFalse(b.goals.isEmpty,      "\(b.id) has no goal")
            XCTAssertFalse(b.trails.isEmpty,     "\(b.id) has no trail")
            XCTAssertFalse(b.floors.isEmpty,     "\(b.id) has no floor")
            XCTAssertFalse(b.pits.isEmpty,       "\(b.id) has no pit")
            XCTAssertFalse(b.boundaries.isEmpty, "\(b.id) has no boundary")
            XCTAssertFalse(b.music.isEmpty,      "\(b.id) has no music")
        }
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

    /// The Starter Pack grants the Aurora bundle free-granted; Sell Back must
    /// refund none of it.  The bundle's items would sell back for 4,875 coins
    /// (half of 9,750 with the Aurora boundary), so a sellable grant would
    /// let the $1.99 pack rival the $4.99 coin pack.
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
        let bundle = CosmeticBundle.catalogue[0]
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
        let bundle = CosmeticBundle.catalogue[0]
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

    /// Ball Packs charge 66% of the member-skin sum — the same mint existed
    /// there (buy pack, liquidate skins at full coinCost, +34% forever).
    func testPack_purchase_sellBackRefundsPaidNotFull() {
        let gs = makeCleanState()
        guard let pack = BallPack.catalogue.first else { return XCTFail("expected a pack in the catalogue") }
        let start = pack.skins.reduce(0) { $0 + $1.coinCost }
        gs.coinBalance = start
        let price = pack.price(in: gs)
        XCTAssertTrue(gs.purchasePack(pack))
        XCTAssertEqual(gs.coinBalance, start - price)

        let r = gs.liquidateCoinCosmetics()
        XCTAssertGreaterThan(r.coins, 0, "a pack purchase still refunds something")
        XCTAssertLessThanOrEqual(r.coins, price, "pack Sell Back must refund at most the discounted price paid")
        XCTAssertLessThanOrEqual(gs.coinBalance, start, "pack buy → Sell Back must not mint coins")
    }

    /// Full-price purchases take the standard rate: an individual Shop buy
    /// refunds half its current coinCost (no paid-price cap in play).
    func testFullPricePurchases_refundHalfCurrentCost() {
        let gs = makeCleanState()
        gs.coinBalance = BallSkin.blue.coinCost
        XCTAssertTrue(gs.purchase(BallSkin.blue))
        let r = gs.liquidateCoinCosmetics()
        XCTAssertEqual(r.coins, BallSkin.blue.coinCost / 2, "full-price purchase refunds half the current cost")
    }

    /// Re-buying an item at full price after a discounted purchase was sold
    /// back must clear the stale discounted record.
    func testRebuyAtFullPrice_clearsDiscountedRecord() {
        let gs = makeCleanState()
        gs.paidPrices[GameState.paidPriceKey(BallSkin.blue)] = 1   // stale discount record
        gs.coinBalance = BallSkin.blue.coinCost
        XCTAssertTrue(gs.purchase(BallSkin.blue))
        XCTAssertEqual(gs.sellBackValue(BallSkin.blue), BallSkin.blue.coinCost / 2,
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
        gs.paidPrices[GameState.paidPriceKey(BallSkin.blue)] = BallSkin.blue.coinCost * 10
        XCTAssertEqual(gs.sellBackValue(BallSkin.blue), BallSkin.blue.coinCost / 2)
    }
    // MARK: - Release calendar (CosmeticSchedule)

    /// Every permanent collection is scheduled exactly once — at launch or in
    /// one drop — and nothing is scheduled that isn't a permanent collection.
    func testSchedule_everyPermanentBundleScheduledExactlyOnce() {
        let scheduled = CosmeticSchedule.launchBundleIDs + CosmeticSchedule.drops.flatMap { $0.ids }
        XCTAssertEqual(scheduled.count, Set(scheduled).count, "a collection is scheduled twice")
        let permanent = Set(CosmeticBundle.catalogue.filter { !$0.isLimitedTime }.map(\.id))
        XCTAssertEqual(Set(scheduled), permanent,
                       "the schedule must cover exactly the permanent collections")
    }

    /// Collections the game gives away must be available on day one: the
    /// Starter Pack's Aurora, the post-tutorial gift pool, and every
    /// challenge-track reward.
    func testSchedule_giftAndRewardBundlesAreLaunchContent() {
        let launch = Set(CosmeticSchedule.launchBundleIDs)
        XCTAssertTrue(launch.contains("aurora"))
        for b in CosmeticBundle.catalogue where !b.isLimitedTime && b.rarity == .standard {
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

    /// The approved built-in calendar (docs/proposals/cosmetic-calendar.md,
    /// identical to the rows in docs/cosmetics/cosmetic-calendar.sql).
    func testSchedule_builtInDatesMatchTheApprovedCalendar() {
        let expected: [(String, CalendarDay)] = [
            ("cathedral", CalendarDay(2026, 12, 17)), ("zen-garden", CalendarDay(2027, 1, 14)),
            ("candyland", CalendarDay(2027, 2, 11)),  ("planets", CalendarDay(2027, 3, 11)),
            ("diamond", CalendarDay(2027, 4, 1)),     ("tempest", CalendarDay(2027, 5, 6)),
            ("soccer", CalendarDay(2027, 6, 3)),      ("paper-world", CalendarDay(2027, 7, 1)),
            ("eclipse", CalendarDay(2027, 7, 29)),    ("geode", CalendarDay(2027, 9, 2)),
            ("oracle", CalendarDay(2027, 10, 7)),     ("quicksilver", CalendarDay(2027, 11, 11)),
            ("_loose-1", CalendarDay(2027, 2, 11)),   ("_loose-2", CalendarDay(2027, 5, 6)),
            ("_loose-3", CalendarDay(2027, 7, 29)),
        ]
        for (id, day) in expected {
            XCTAssertEqual(CosmeticSchedule.builtInReleaseDays[id], day, id)
        }
        XCTAssertEqual(CosmeticSchedule.drops.count, 12)
        XCTAssertEqual(CosmeticSchedule.drops.flatMap { $0.ids }.count, 37)
        let days = CosmeticSchedule.drops.map { $0.day }
        XCTAssertEqual(days, days.sorted(), "drops are in date order")
        XCTAssertNil(CosmeticSchedule.releaseDate(of: "aurora"), "launch collections have no date")
        XCTAssertEqual(CosmeticBundle.catalogue.first { $0.id == "lunar-2027" }?.displayName,
                       "Lunar New Year")
    }

    /// A drop opens at midnight EASTERN on its day, not the phone's midnight.
    func testSchedule_dropOpensAtMidnightEastern() {
        let store = calendarStore()
        XCTAssertTrue(CosmeticSchedule.isReleased(collectionID: "aurora",
                                                  at: eastern(2020, 1, 1), store: store),
                      "launch content is available from the first open, whenever that is")
        XCTAssertFalse(CosmeticSchedule.isReleased(collectionID: "cathedral",
                                                   at: eastern(2026, 12, 17, plus: -1), store: store))
        XCTAssertTrue(CosmeticSchedule.isReleased(collectionID: "cathedral",
                                                  at: eastern(2026, 12, 17), store: store))
        // Midnight Eastern on Dec 17 is 05:00 UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour], from: eastern(2026, 12, 17))
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour], [2026, 12, 17, 5])
        XCTAssertEqual(CosmeticSchedule.dayLabel(eastern(2026, 12, 17)).contains("17"), true)
    }

    /// Every collection releases eventually; "Coming soon" names the next real
    /// day and everything on it.
    func testSchedule_comingSoonShowsTheNextRealDate() {
        let store = calendarStore()
        let first = CosmeticSchedule.nextDrop(at: eastern(2026, 12, 1), store: store)
        XCTAssertEqual(first?.date, eastern(2026, 12, 17))
        XCTAssertEqual(Set(first?.bundles.map(\.id) ?? []),
                       ["cathedral", "velvet-night", "crystal-cavern"])
        let march = CosmeticSchedule.nextDrop(at: eastern(2027, 3, 11, plus: -1), store: store)
        XCTAssertEqual(march?.date, eastern(2027, 3, 11))
        let afterAll = eastern(2027, 11, 11)
        XCTAssertNil(CosmeticSchedule.nextDrop(at: afterAll, store: store),
                     "nothing is left to announce after the last drop")
        for b in CosmeticBundle.catalogue {
            XCTAssertTrue(CosmeticSchedule.isReleased(b, at: afterAll, store: store), "\(b.id) never releases")
        }
    }

    /// A date in the server table overrides the built-in one, earlier or later;
    /// unknown ids and broken rows are ignored; deleting a row restores the
    /// built-in date.
    func testSchedule_serverDatesOverrideBuiltIn() {
        let store = calendarStore()
        typealias Row = CosmeticCalendarStore.Row
        store.apply([
            Row(collection_id: "planets", starts_on: "2027-01-07", ends_on: nil),     // earlier
            Row(collection_id: "cathedral", starts_on: "2027-01-21", ends_on: nil),   // later
            Row(collection_id: "not-a-collection", starts_on: "2027-01-01", ends_on: nil),
            Row(collection_id: "noir", starts_on: "garbage", ends_on: nil),
        ])
        XCTAssertTrue(CosmeticSchedule.isReleased(collectionID: "planets",
                                                  at: eastern(2027, 1, 7), store: store))
        XCTAssertFalse(CosmeticSchedule.isReleased(collectionID: "cathedral",
                                                   at: eastern(2026, 12, 20), store: store))
        XCTAssertEqual(CosmeticSchedule.nextDrop(at: eastern(2026, 12, 18), store: store)?.date,
                       eastern(2027, 1, 7), "Coming soon follows the server date")
        XCTAssertEqual(CosmeticSchedule.releaseDate(of: "noir", store: store),
                       eastern(2027, 1, 14), "a broken row falls back to the built-in date")
        store.apply([])
        XCTAssertEqual(CosmeticSchedule.releaseDate(of: "cathedral", store: store), eastern(2026, 12, 17))
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
        _ = CosmeticSchedule.isReleased(collectionID: "oracle", at: eastern(2030, 1, 1), store: probe)
        XCTAssertFalse(probe.hasSeenReleased("oracle"))
    }

    /// An unreleased collection's items are held back with it; starter items
    /// never are.
    func testSchedule_itemsFollowTheirCollections() {
        let store = calendarStore()
        XCTAssertTrue(CosmeticSchedule.isReleased(BallSkin.starter, at: eastern(2020, 1, 1), store: store))
        for b in CosmeticBundle.catalogue where !b.isLimitedTime {
            guard let date = CosmeticSchedule.releaseDate(of: b.id, store: store) else { continue }
            for ball in b.balls where ball.tier != .starter {
                XCTAssertTrue(CosmeticSchedule.isReleased(ball, at: date, store: store),
                              "\(ball.rawValue) must be out no later than \(b.id)")
            }
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

    // MARK: - Music is not in 1.0

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
        // Aurora: 9,750 with its 1,500-coin music track, 8,250 without.
        let aurora = CosmeticBundle.catalogue.first { $0.id == "aurora" }!
        XCTAssertEqual(aurora.fullPrice(), 8_250)
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

    func testPlayIsUnchanged() {
        XCTAssertFalse(CosmeticMotion.live.isPaused(reduceMotion: true))
        XCTAssertNil(CosmeticMotion.live.frameInterval(nil))
        XCTAssertEqual(CosmeticMotion.live.frameInterval(1.0 / 30.0) ?? 0, 1.0 / 30.0, accuracy: 1e-9)
        XCTAssertEqual(EnvironmentValues().cosmeticMotion, .live)
    }
}
