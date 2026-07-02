import XCTest
@testable import RollAlong

// ---------------------------------------------------------------------------
// StoreKitManagerTests — pins the transaction-listener decision logic.
//
// Real StoreKit Transactions can't be constructed in unit tests (they require
// Apple-signed JWS payloads), so the listener's per-update decision lives in
// the pure StoreKitManager.verifiedUpdateAction(productID:revocationDate:)
// and is tested here directly.  The critical case: a refunded purchase
// arrives through Transaction.updates as a VERIFIED transaction with
// revocationDate set, and must never deliver its reward again.
// ---------------------------------------------------------------------------

final class StoreKitManagerTests: XCTestCase {

    // MARK: - Delivery (happy path)

    /// Every catalogue product delivers when the transaction isn't revoked.
    func testAllKnownProductsDeliverWhenNotRevoked() {
        for productID in StoreKitManager.ProductID.allCases {
            XCTAssertEqual(
                StoreKitManager.verifiedUpdateAction(productID: productID.rawValue,
                                                     revocationDate: nil),
                .deliver(productID),
                "\(productID.rawValue) should deliver its reward"
            )
        }
    }

    // MARK: - Coin pack rewards (2026-07 reprice)

    /// Pins the re-anchored coin amounts (product IDs are immutable in App
    /// Store Connect, so the case names keep their historical numbers).
    func testCoinPackRewardCoins_matchRepricedAmounts() {
        XCTAssertEqual(StoreKitManager.ProductID.coins100.rewardCoins,      750)
        XCTAssertEqual(StoreKitManager.ProductID.coins600.rewardCoins,    4_500)
        XCTAssertEqual(StoreKitManager.ProductID.coins1300.rewardCoins,  10_000)
        XCTAssertEqual(StoreKitManager.ProductID.coins3000.rewardCoins,  22_500)
        XCTAssertEqual(StoreKitManager.ProductID.coins10000.rewardCoins, 60_000)
    }

    /// Coins-per-dollar must rise strictly with pack size — a bigger pack is
    /// never a worse deal (758 / 902 / 1,001 / 1,126 / 1,200 per $ at the
    /// intended $0.99/$4.99/$9.99/$19.99/$49.99 price points).
    func testCoinPacks_coinsPerDollarRiseMonotonically() {
        let ladder: [(StoreKitManager.ProductID, Double)] = [
            (.coins100,    0.99),
            (.coins600,    4.99),
            (.coins1300,   9.99),
            (.coins3000,  19.99),
            (.coins10000, 49.99),
        ]
        var previousRate = 0.0
        for (pid, dollars) in ladder {
            let rate = Double(pid.rewardCoins) / dollars
            XCTAssertGreaterThan(rate, previousRate,
                                 "\(pid.rawValue) must beat the smaller pack's coins-per-dollar")
            previousRate = rate
        }
    }

    // MARK: - Refund / revocation

    /// The refund exploit: buy the top ($49.99) coin pack, request an Apple refund,
    /// and the revocation update must NOT mint another 60,000 coins (plus a
    /// Money cosmetic) on top of the money back.
    func testRevokedCoinPackDoesNotDeliver() {
        XCTAssertEqual(
            StoreKitManager.verifiedUpdateAction(
                productID: StoreKitManager.ProductID.coins10000.rawValue,
                revocationDate: Date(timeIntervalSince1970: 1_780_000_000)),
            .skipRevoked
        )
    }

    /// A refunded unlimited unlock must not re-flip unlimitedLives back on.
    func testRevokedUnlimitedDoesNotDeliver() {
        XCTAssertEqual(
            StoreKitManager.verifiedUpdateAction(
                productID: StoreKitManager.ProductID.unlimited.rawValue,
                revocationDate: Date(timeIntervalSince1970: 1_780_000_000)),
            .skipRevoked
        )
    }

    /// Revocation is checked for every product in the catalogue — no product
    /// is allowed to deliver once revocationDate is set.
    func testNoKnownProductDeliversWhenRevoked() {
        let revokedAt = Date(timeIntervalSince1970: 1_780_000_000)
        for productID in StoreKitManager.ProductID.allCases {
            XCTAssertEqual(
                StoreKitManager.verifiedUpdateAction(productID: productID.rawValue,
                                                     revocationDate: revokedAt),
                .skipRevoked,
                "\(productID.rawValue) must not deliver when revoked"
            )
        }
    }

    // MARK: - Unknown products

    /// A product retired from the catalogue is finished without delivering.
    func testUnknownProductSkips() {
        XCTAssertEqual(
            StoreKitManager.verifiedUpdateAction(
                productID: "com.macfaldet.RollAlong.retired.pack",
                revocationDate: nil),
            .skipUnknownProduct
        )
    }

    /// Revocation takes precedence even for unknown products, so the refund
    /// analytics event fires rather than the silent unknown-product skip.
    func testRevokedUnknownProductReportsRevoked() {
        XCTAssertEqual(
            StoreKitManager.verifiedUpdateAction(
                productID: "com.macfaldet.RollAlong.retired.pack",
                revocationDate: Date(timeIntervalSince1970: 1_780_000_000)),
            .skipRevoked
        )
    }
}
