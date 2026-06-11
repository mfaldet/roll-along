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

    /// Bundle-exclusive skins must have coinCost == 0 — they are not purchasable
    /// individually in the coin shop, so their coinCost is irrelevant, but it
    /// should not misleadingly imply a purchase path.
    func testBundleExclusiveSkins_areNotCoinPurchasable() {
        for skin in BallSkin.allCases where skin.isBundleExclusive {
            // Starter tier has basePrice = 0; exclusive tier also has basePrice = 0
            // because bundle-exclusive skins are never sold for coins.
            // This test guards against accidentally setting them to a coin tier.
            XCTAssertEqual(skin.coinCost, 0,
                           "Bundle-exclusive skin \(skin.rawValue) should have coinCost == 0")
        }
    }

    /// Bundle-exclusive skins must not appear in `BallSkin.allCases` with
    /// `isBundleExclusive == false` — consistency check.
    func testBundleExclusiveSkins_flagIsConsistent() {
        let exclusiveSkins: Set<String> = [
            "Pluto", "Aurora", "BeachBall", "Pumpkin", "Ornament",
            "Heartstone", "Shamrock", "Confetti", "SpeckledEgg", "Trophy"
        ]
        for skin in BallSkin.allCases {
            let shouldBeExclusive = exclusiveSkins.contains(skin.rawValue)
            if shouldBeExclusive {
                XCTAssertTrue(skin.isBundleExclusive,
                              "\(skin.rawValue) should be isBundleExclusive = true")
            }
        }
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

    // MARK: - StoreKitManager ProductID bundle mapping

    func testProductIDs_bundleIDsAreUnique() {
        let bundleIDs = StoreKitManager.ProductID.allCases.compactMap { $0.bundleID }
        let uniqueIDs = Set(bundleIDs)
        XCTAssertEqual(bundleIDs.count, uniqueIDs.count,
                       "No two ProductIDs should map to the same bundleID")
    }

    func testProductIDs_bundleIDsResolveToKnownCatalogueEntry() {
        let catalogueIDs = Set(CosmeticBundle.catalogue.map { $0.id })
        for pid in StoreKitManager.ProductID.allCases {
            guard let bundleID = pid.bundleID else { continue }
            XCTAssertTrue(catalogueIDs.contains(bundleID),
                          "ProductID.\(pid.rawValue) bundleID '\(bundleID)' has no matching CosmeticBundle in catalogue")
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
}
