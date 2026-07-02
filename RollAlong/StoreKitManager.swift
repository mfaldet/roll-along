import Foundation
import StoreKit

// ---------------------------------------------------------------------------
// StoreKitManager — StoreKit 2 wrapper.
//
// Responsibilities:
//   • Fetch the 10 App Store product records on app launch.
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
        case coins10000   = "com.macfaldet.RollAlong.coins.10000"
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
            case .coins100, .coins600, .coins1300, .coins3000, .coins10000: return .coinPack
            case .starterPack:                            return .starterPackUnlock
            }
        }

        /// Lives granted by this purchase.  Zero for non-life products.
        var rewardLives: Int {
            switch self {
            case .livesPack1:  return 10    // 1 full reload (10-life cap)
            case .livesPack5:  return 60    // 6 reloads
            case .livesPack10: return 130   // 13 reloads
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
            case .coins10000:  return 10000
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
    /// Monotonic counter bumped once per successful delivery.  UI observes this
    /// (rather than `lastDelivery`) to fire a celebration on *every* purchase —
    /// `lastDelivery` is Equatable, so buying the same pack twice in a row would
    /// not register as a change.
    @Published private(set) var deliveryCount: Int = 0

    /// Called by purchase-sheet alert dismiss to clear the error so the same
    /// error string can re-trigger onChange on a subsequent attempt.
    func clearLastError() { lastError = nil }

    /// Surface-able info for the UI after a successful purchase or restore.
    struct DeliveryReceipt: Equatable {
        let productID: ProductID
        let lives: Int
        let coins: Int
        let unlimitedActivated: Bool
        /// Display name of a secret cosmetic dropped alongside this purchase
        /// (the 10,000-coin pack's random "Money" unlock), or nil.
        var grantedCosmeticName: String? = nil
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
        var unlimitedSeen      = false
        var starterPackSeen    = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result else {
                // .unverified: Apple's JWS signature check failed.  Skip —
                // no entitlement granted.  Log for monitoring.
                if case .unverified(_, let verificationError) = result {
                    AnalyticsClient.shared.track(
                        "iap_verification_failed",
                        properties: [
                            "error":   .string(verificationError.localizedDescription),
                            "context": .string("entitlements"),
                        ]
                    )
                }
                continue
            }
            switch txn.productID {
            case ProductID.unlimited.rawValue:               unlimitedSeen   = true
            case ProductID.starterPack.rawValue:             starterPackSeen = true
            default: break
            }
        }
        // The unlimited entitlement IS the source of truth: mirror it exactly, so
        // removing the purchase (a refund, or deleting a StoreKit test transaction)
        // turns unlimited lives back off on the next launch.  Only *grant* the
        // Diamond ball when entitled — never revoke a cosmetic already owned.
        gameState?.unlimitedLives = unlimitedSeen
        if unlimitedSeen { gameState?.grant(BallSkin.diamond) }
        // Legacy: the Starter Pack IAP is retired (no longer sold).  Past
        // purchasers still get their Aurora skin back on restore (one-time) —
        // but NOT the 500 coins, which were a one-time consumable already spent.
        if starterPackSeen, let gs = gameState, !gs.starterPackClaimed {
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
                // Explicit switch — .unverified must NEVER grant a reward.
                switch verification {
                case .verified(let transaction):
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
                case .unverified(_, let verificationError):
                    // Apple's JWS signature check failed — do NOT grant any
                    // reward.  Log for monitoring (could indicate a tampered
                    // receipt on a jailbroken device).
                    self.lastError = "Couldn't verify purchase."
                    AnalyticsClient.shared.track(
                        "iap_verification_failed",
                        properties: [
                            "product_id": .string(productID.rawValue),
                            "error":      .string(verificationError.localizedDescription),
                            "context":    .string("purchase"),
                        ]
                    )
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
        var grantedCosmetic: String? = nil
        switch productID.category {
        case .lifePack:
            // Lives from purchases stockpile unbounded.  $9.99 = 130 lives
            // promised in the App Store Connect product description; the
            // player gets exactly that.  Earlier code clamped to 24 — that
            // was a bug, fixed here.
            gameState.lives += productID.rewardLives
            // Clearing lastLifeLostAt stops the regen timer; the stockpile
            // doesn't need regen and the timer would just churn confusingly.
            gameState.lastLifeLostAt = nil
            gameState.reconcileLivesNotification()   // now full → cancel any pending alert

        case .coinPack:
            gameState.addCoins(productID.rewardCoins)
            // The 10,000-coin pack also drops ONE random not-yet-owned "Money"
            // cosmetic — up to three unlock across repeat purchases.
            if productID == .coins10000 {
                grantedCosmetic = grantRandomMoneyCosmetic(gameState)
            }

        case .unlimitedUnlock:
            gameState.unlimitedLives = true
            gameState.grant(BallSkin.diamond)   // exclusive Diamond ball skin
            gameState.reconcileLivesNotification()   // unlimited → no restock alert

        case .starterPackUnlock:
            // Only deliver once — guard lets restore calls be idempotent.
            guard !gameState.starterPackClaimed else { break }
            gameState.addCoins(productID.rewardCoins)
            gameState.grant(BallSkin.aurora)
            gameState.starterPackClaimed = true
        }
        lastDelivery = DeliveryReceipt(
            productID:           productID,
            lives:               productID.rewardLives,
            coins:               productID.rewardCoins,
            unlimitedActivated:  productID.category == .unlimitedUnlock,
            grantedCosmeticName: grantedCosmetic
        )
        deliveryCount += 1
    }

    /// Grant ONE random "Money" cosmetic the player doesn't yet own — the ball,
    /// trail, or floor.  Returns its display name (for the celebration) or nil if
    /// all three are already owned.  Deliberately one-at-a-time so the trio
    /// unlocks across repeat 10,000-coin purchases rather than all at once.
    private func grantRandomMoneyCosmetic(_ gs: GameState) -> String? {
        var pool: [(name: String, grant: () -> Void)] = []
        if !gs.isOwned(BallSkin.moneyBall)   { pool.append(("Money Ball", { gs.grant(BallSkin.moneyBall) })) }
        if !gs.isOwned(TrailColor.moneyRoll) { pool.append(("Money Roll", { gs.grant(TrailColor.moneyRoll) })) }
        if !gs.isOwned(Floor.moneyFull)      { pool.append(("Money Full", { gs.grant(Floor.moneyFull) })) }
        guard let pick = pool.randomElement() else { return nil }
        pick.grant()
        return pick.name
    }

    // MARK: - Background transaction listener

    /// What the listener should do with a *verified* transaction update.
    /// Pure decision logic, split out of `listenForTransactions()` so unit
    /// tests can pin the refund handling without constructing real StoreKit
    /// transactions (which require Apple-signed JWS payloads).
    enum VerifiedUpdateAction: Equatable {
        /// Deliver the reward (fresh purchase, Ask to Buy approval,
        /// sync from another device).
        case deliver(ProductID)
        /// Refund or Family Sharing revocation — finish WITHOUT delivering.
        case skipRevoked
        /// Product retired from the catalogue — finish so it stops
        /// re-delivering; nothing to grant.
        case skipUnknownProduct
    }

    nonisolated static func verifiedUpdateAction(
        productID: String,
        revocationDate: Date?
    ) -> VerifiedUpdateAction {
        // Revocation wins over everything else: StoreKit delivers refunds and
        // Family Sharing revocations through Transaction.updates as *verified*
        // transactions with revocationDate set.  Delivering here would mint
        // the reward a second time on top of the money back (e.g., refund the
        // 10,000-coin pack → another 10,000 coins + a Money cosmetic, forever
        // repeatable).
        if revocationDate != nil { return .skipRevoked }
        guard let productID = ProductID(rawValue: productID) else {
            return .skipUnknownProduct
        }
        return .deliver(productID)
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            switch update {
            case .verified(let transaction):
                switch Self.verifiedUpdateAction(productID: transaction.productID,
                                                 revocationDate: transaction.revocationDate) {
                case .deliver(let productID):
                    await deliverReward(for: productID)
                case .skipRevoked:
                    // A refunded unlimited unlock should stop granting free
                    // lives right away, not at the next launch (where
                    // refreshEntitlements re-mirrors the entitlement anyway).
                    // Consumables aren't clawed back: coins/lives already
                    // granted may be spent, and Apple owns the refund risk.
                    if transaction.productID == ProductID.unlimited.rawValue {
                        gameState?.unlimitedLives = false
                    }
                    let reason: String
                    if let revocationReason = transaction.revocationReason {
                        reason = revocationReason == .developerIssue ? "developer_issue" : "other"
                    } else {
                        reason = "unknown"
                    }
                    AnalyticsClient.shared.track(
                        "iap_revoked",
                        properties: [
                            "product_id": .string(transaction.productID),
                            "reason":     .string(reason),
                        ]
                    )
                case .skipUnknownProduct:
                    break
                }
                // Finish verified updates whether delivered or skipped, so
                // StoreKit stops re-delivering them.
                await transaction.finish()
            case .unverified(_, let verificationError):
                // Apple's JWS signature check failed.  Do NOT grant any
                // reward and do NOT finish — let the transaction remain
                // unfinished so StoreKit can retry verification.
                AnalyticsClient.shared.track(
                    "iap_verification_failed",
                    properties: [
                        "error":   .string(verificationError.localizedDescription),
                        "context": .string("listener"),
                    ]
                )
            }
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
