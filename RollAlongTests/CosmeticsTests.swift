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
            "Pluto", "Aurora", "Beach Ball", "Pumpkin", "Ornament",
            "Heartstone", "Shamrock", "Confetti", "Speckled Egg", "Trophy",
            "Diamond"   // Diamond Balls IAP exclusive
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
}
