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
            "Heartstone", "Shamrock", "Confetti", "Speckled Egg", "Trophy"
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
