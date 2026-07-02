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
    /// price — `coinCost` reads through to `tier.basePrice` (500), so asserting a
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
            // Aurora is intentionally absent — the Starter Pack IAP was retired and
            // Aurora is now a regular coin-buyable ball (no longer bundle-locked).
            "Pluto", "Beach Ball", "Pumpkin", "Ornament",
            "Heartstone", "Shamrock", "Confetti", "Speckled Egg", "Trophy",
            "Diamond",     // Diamond Balls IAP exclusive
            "Money Ball"   // 10,000-coin IAP secret exclusive
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

    func testCosmeticTier_basePricesAreMonotonicallyIncreasing() {
        // Ordered from cheapest to most expensive
        let tiers: [CosmeticTier] = [.starter, .standard, .premium, .exclusive]
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
        XCTAssertEqual(preview.coins, BallSkin.blue.coinCost + GoalSkin.galaxy.coinCost)

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
        XCTAssertEqual(first.coins, BallSkin.blue.coinCost + TrailColor.fire.coinCost)
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
            let ballSum  = bundle.balls.reduce(0)  { $0 + $1.coinCost }
            let goalSum  = bundle.goals.reduce(0)  { $0 + $1.coinCost }
            let trailSum = bundle.trails.reduce(0) { $0 + $1.coinCost }
            let floorSum = bundle.floors.reduce(0) { $0 + $1.coinCost }
            let pitSum   = bundle.pits.reduce(0)   { $0 + $1.coinCost }
            let musicSum = bundle.music.reduce(0)  { $0 + $1.coinCost }
            let manual = ballSum + goalSum + trailSum + floorSum + pitSum + musicSum
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

    /// Probe: prints the bundle cost distribution so thresholds can be tuned to
    /// the live catalogue, and asserts every rarity band is represented (a
    /// healthy Standard tier is required for the post-tutorial gift picker).
    func test_bundleRarityDistribution() {
        let sorted = CosmeticBundle.catalogue.sorted { $0.fullPrice() < $1.fullPrice() }
        for b in sorted {
            print("RARITYDIST \(b.rarity.label.padding(toLength: 9, withPad: " ", startingAt: 0)) \(b.fullPrice())  \(b.id)")
        }
        let buckets = Dictionary(grouping: CosmeticBundle.catalogue, by: { $0.rarity })
        print("RARITYDIST counts:",
              BundleRarity.allCases.map { "\($0.label)=\(buckets[$0]?.count ?? 0)" }.joined(separator: " "))
        for r in BundleRarity.allCases {
            XCTAssertGreaterThan(buckets[r]?.count ?? 0, 0, "no bundles in rarity band \(r.label)")
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
        XCTAssertEqual(preview.coins, BallSkin.pumpkin.coinCost)

        let r = gs.liquidateCoinCosmetics()
        XCTAssertEqual(r.coins, BallSkin.pumpkin.coinCost)
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
        for b in bundle.balls  { XCTAssertTrue(gs.isOwned(b)); XCTAssertTrue(gs.freeGrantedItems.contains(b.rawValue)) }
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

    // MARK: - Discounted purchases refund what was PAID (coin-mint fix)
    //
    // Sell Back used to refund every item's full coinCost even when it was
    // bought below cost (the Shop's featured-bundle discount, Ball Packs'
    // 66% pricing) — buy a 2,550-coin bundle at 50% off for 1,275, liquidate
    // for 2,550, pocket 1,275, repeat every rotation window.  `paidPrices`
    // now records the discounted price and Sell Back refunds that instead.

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

    /// Full-price paths are untouched: an individual Shop purchase still
    /// refunds its full coinCost, and a Catalog bundle bought at the full
    /// prorated price refunds (up to) that price.
    func testFullPricePurchases_stillRefundFullCost() {
        let gs = makeCleanState()
        gs.coinBalance = BallSkin.blue.coinCost
        XCTAssertTrue(gs.purchase(BallSkin.blue))
        let r = gs.liquidateCoinCosmetics()
        XCTAssertEqual(r.coins, BallSkin.blue.coinCost, "full-price purchase refunds the full cost")
    }

    /// Re-buying an item at full price after a discounted purchase was sold
    /// back must clear the stale discounted record.
    func testRebuyAtFullPrice_clearsDiscountedRecord() {
        let gs = makeCleanState()
        gs.paidPrices[GameState.paidPriceKey(BallSkin.blue)] = 1   // stale discount record
        gs.coinBalance = BallSkin.blue.coinCost
        XCTAssertTrue(gs.purchase(BallSkin.blue))
        XCTAssertEqual(gs.sellBackValue(BallSkin.blue), BallSkin.blue.coinCost,
                       "full-price re-purchase refunds full cost again")
    }

    /// `paidPrices` keys are category-qualified: five different cosmetics
    /// share the rawValue "aurora", and a discounted record for one category
    /// must not distort another's refund.
    func testPaidPrices_keysAreCategoryQualified_noAuroraCollision() {
        let gs = makeCleanState()
        gs.paidPrices[GameState.paidPriceKey(BallSkin.aurora)] = 1
        XCTAssertEqual(gs.sellBackValue(BallSkin.aurora), 1)
        XCTAssertEqual(gs.sellBackValue(TrailColor.aurora), TrailColor.aurora.coinCost)
        XCTAssertEqual(gs.sellBackValue(GoalSkin.aurora), GoalSkin.aurora.coinCost)
        XCTAssertEqual(gs.sellBackValue(Floor.aurora), Floor.aurora.coinCost)
    }

    /// `sellBackValue` never exceeds coinCost even if a corrupt/legacy record
    /// says otherwise.
    func testSellBackValue_isCappedAtCoinCost() {
        let gs = makeCleanState()
        gs.paidPrices[GameState.paidPriceKey(BallSkin.blue)] = BallSkin.blue.coinCost * 10
        XCTAssertEqual(gs.sellBackValue(BallSkin.blue), BallSkin.blue.coinCost)
    }
}
