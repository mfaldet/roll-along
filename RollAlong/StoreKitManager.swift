import Foundation
import StoreKit

// ---------------------------------------------------------------------------
// StoreKitManager — StoreKit 2 wrapper.
//
// Responsibilities:
//   • Fetch the 8 App Store product records on app launch.
//   • Drive purchase + restore flows from UI.
//   • Listen for Transaction updates from the App Store in the background
//     (foreground processing for purchases made on other devices, refunds,
//     etc.).
//   • Translate purchases into in-game rewards (lives, coins, or unlimited
//     unlock) by mutating GameState.
//
// Notes:
//   • Hardcoded product IDs match what Mac created in App Store Connect.
//     A typo in either side would silently produce "product not found"; the
//     RawValue strings here are the source of truth.
//   • For simulator testing, see Products.storekit (configured via the
//     scheme's Run → Options → StoreKit Configuration setting).
// ---------------------------------------------------------------------------

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    // MARK: - Product catalogue

    enum ProductID: String, CaseIterable, Identifiable {
        case livesPack1   = "com.macfaldet.RollAlong.lives.pack1"
        case livesPack5   = "com.macfaldet.RollAlong.lives.pack5"
        case livesPack10  = "com.macfaldet.RollAlong.lives.pack10"
        case unlimited    = "com.macfaldet.RollAlong.unlimited"
        case coins100     = "com.macfaldet.RollAlong.coins.100"
        case coins600     = "com.macfaldet.RollAlong.coins.600"
        case coins1300    = "com.macfaldet.RollAlong.coins.1300"
        case coins3000    = "com.macfaldet.RollAlong.coins.3000"
        /// One-time welcome offer: 500 coins + exclusive Aurora ball skin.
        /// Non-consumable so it can be restored on a new device; delivery
        /// is idempotent (grantCosmetic + addCoins are safe to call twice
        /// — grantCosmetic is a set.insert and addCoins only runs when
        /// `starterPackClaimed` is still false).
        case starterPack  = "com.macfaldet.RollAlong.starterpack"

        var id: String { rawValue }

        enum Category {
            case lifePack           // grants N lives
            case coinPack           // grants N coins
            case unlimitedUnlock    // non-consumable; flips unlimitedLives true
            case starterPackUnlock  // non-consumable; grants 500 coins + Aurora skin
        }

        var category: Category {
            switch self {
            case .livesPack1, .livesPack5, .livesPack10: return .lifePack
            case .unlimited:                              return .unlimitedUnlock
            case .coins100, .coins600, .coins1300, .coins3000: return .coinPack
            case .starterPack:                            return .starterPackUnlock
            }
        }

        /// Lives granted by this purchase.  Zero for non-life products.
        var rewardLives: Int {
            switch self {
            case .livesPack1:  return 6    // 1 full reload
            case .livesPack5:  return 36   // 6 reloads
            case .livesPack10: return 78   // 13 reloads
            default:           return 0
            }
        }

        /// Coins granted by this purchase.  Zero for non-coin products.
        var rewardCoins: Int {
            switch self {
            case .coins100:    return 100
            case .coins600:    return 600
            case .coins1300:   return 1300
            case .coins3000:   return 3000
            case .starterPack: return 500
            default:           return 0
            }
        }
    }

    // MARK: - Published state (observable by SwiftUI)

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseInProgress: ProductID? = nil
    @Published private(set) var lastError: String? = nil
    @Published private(set) var lastDelivery: DeliveryReceipt? = nil

    /// Surface-able info for the UI after a successful purchase or restore.
    struct DeliveryReceipt: Equatable {
        let productID: ProductID
        let lives: Int
        let coins: Int
        let unlimitedActivated: Bool
    }

    // MARK: - Transaction listener

    /// Long-lived task spun up at init that processes StoreKit Transaction
    /// updates from outside our purchase flow (e.g., parent-approved
    /// purchases, refunds, sync from other devices).
    private var transactionListener: Task<Void, Never>?

    // MARK: - GameState binding

    /// Set once at app launch so the manager can grant rewards.  Not
    /// directly injected because StoreKitManager is a singleton; the App
    /// passes its GameState reference at startup.
    weak var gameState: GameState?

    private init() {
        transactionListener = Task { [weak self] in
            await self?.listenForTransactions()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Bootstrap

    /// Load products from the App Store + verify any prior non-consumable
    /// purchases (specifically: unlimited).  Call once near app launch.
    func bootstrap(with gameState: GameState) async {
        self.gameState = gameState
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        let ids = Set(ProductID.allCases.map(\.rawValue))
        do {
            let fetched = try await Product.products(for: ids)
            // Preserve our enum order rather than App Store's arbitrary order.
            self.products = ProductID.allCases.compactMap { pid in
                fetched.first { $0.id == pid.rawValue }
            }
            self.lastError = nil
        } catch {
            self.products = []
            self.lastError = "Couldn't load store: \(error.localizedDescription)"
        }
    }

    /// Re-check the user's current entitlements.  The unlimited tier is a
    /// non-consumable, so it lives in currentEntitlements forever.
    func refreshEntitlements() async {
        var unlimitedSeen     = false
        var starterPackSeen   = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result else { continue }
            if txn.productID == ProductID.unlimited.rawValue    { unlimitedSeen   = true }
            if txn.productID == ProductID.starterPack.rawValue  { starterPackSeen = true }
        }
        if unlimitedSeen   { gameState?.unlimitedLives = true }
        if starterPackSeen {
            guard let gs = gameState, !gs.starterPackClaimed else { return }
            gs.addCoins(ProductID.starterPack.rewardCoins)
            gs.grant(BallSkin.aurora)
            gs.starterPackClaimed = true
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(_ productID: ProductID) async -> Bool {
        guard let product = products.first(where: { $0.id == productID.rawValue }) else {
            self.lastError = "Product not available."
            return false
        }
        guard purchaseInProgress == nil else { return false }
        purchaseInProgress = productID
        defer { purchaseInProgress = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await deliverReward(for: productID)
                    await transaction.finish()
                    AnalyticsClient.shared.track(
                        "iap_purchased",
                        properties: [
                            "product_id":     .string(productID.rawValue),
                            "category":       .string(String(describing: productID.category)),
                            "reward_lives":   .int(productID.rewardLives),
                            "reward_coins":   .int(productID.rewardCoins),
                            "price":          .string(product.displayPrice),
                        ]
                    )
                    return true
                } else {
                    self.lastError = "Couldn't verify purchase."
                    return false
                }
            case .pending:
                // Awaiting approval (e.g., Ask to Buy).  Transaction listener
                // will pick it up later.
                AnalyticsClient.shared.track(
                    "iap_pending",
                    properties: ["product_id": .string(productID.rawValue)]
                )
                return false
            case .userCancelled:
                AnalyticsClient.shared.track(
                    "iap_cancelled",
                    properties: ["product_id": .string(productID.rawValue)]
                )
                return false
            @unknown default:
                return false
            }
        } catch {
            self.lastError = error.localizedDescription
            AnalyticsClient.shared.track(
                "iap_failed",
                properties: [
                    "product_id": .string(productID.rawValue),
                    "error":      .string(error.localizedDescription),
                ]
            )
            return false
        }
    }

    // MARK: - Restore

    /// Triggers App Store sync; Transaction.currentEntitlements is then
    /// authoritative.  Useful when a user installs on a new device, or if
    /// they think they paid for unlimited but it isn't showing.
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            AnalyticsClient.shared.track("iap_restored")
        } catch {
            self.lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Reward delivery

    private func deliverReward(for productID: ProductID) async {
        guard let gameState else { return }
        switch productID.category {
        case .lifePack:
            // Lives from purchases stockpile unbounded.  $9.99 = 78 lives
            // promised in the App Store Connect product description; the
            // player gets exactly that.  Earlier code clamped to 24 — that
            // was a bug, fixed here.
            gameState.lives += productID.rewardLives
            // Clearing lastLifeLostAt stops the regen timer; the stockpile
            // doesn't need regen and the timer would just churn confusingly.
            gameState.lastLifeLostAt = nil

        case .coinPack:
            gameState.addCoins(productID.rewardCoins)

        case .unlimitedUnlock:
            gameState.unlimitedLives = true

        case .starterPackUnlock:
            // Only deliver once — guard lets restore calls be idempotent.
            guard !gameState.starterPackClaimed else { break }
            gameState.addCoins(productID.rewardCoins)
            gameState.grant(BallSkin.aurora)
            gameState.starterPackClaimed = true
        }
        lastDelivery = DeliveryReceipt(
            productID:          productID,
            lives:              productID.rewardLives,
            coins:              productID.rewardCoins,
            unlimitedActivated: productID.category == .unlimitedUnlock
        )
    }

    // MARK: - Background transaction listener

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            guard case .verified(let transaction) = update else { continue }
            guard let productID = ProductID(rawValue: transaction.productID) else {
                await transaction.finish()
                continue
            }
            await deliverReward(for: productID)
            await transaction.finish()
        }
    }
}

// ---------------------------------------------------------------------------
// Convenience helpers for SwiftUI views
// ---------------------------------------------------------------------------
extension StoreKitManager {
    func product(for id: ProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    /// Display price for a product, or a fallback if products haven't loaded.
    func displayPrice(for id: ProductID, fallback: String) -> String {
        product(for: id)?.displayPrice ?? fallback
    }
}
