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
//   • Delivery discipline: a transaction is finished only AFTER its reward
//     is granted and recorded in the persisted delivered-ledger.  Updates
//     that arrive before bootstrap binds gameState are left unfinished and
//     replayed by processUnfinishedTransactions(); replays of already-
//     delivered transactions finish without granting again.
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
        // Coin packs.  The numeric suffixes in the case names / product IDs
        // are HISTORICAL — App Store Connect product IDs are immutable, so
        // they still carry the pre-2026-07-reprice amounts.  The actual
        // grant is `rewardCoins` below (750 / 4,500 / 10,000 / 22,500 /
        // 60,000); display names come from ASC / Products.storekit.
        case coins100     = "com.macfaldet.RollAlong.coins.100"
        case coins600     = "com.macfaldet.RollAlong.coins.600"
        case coins1300    = "com.macfaldet.RollAlong.coins.1300"
        case coins3000    = "com.macfaldet.RollAlong.coins.3000"
        case coins10000   = "com.macfaldet.RollAlong.coins.10000"
        /// One-time welcome offer: 500 coins + the complete Aurora collection
        /// (the "aurora" bundle — ball, goal, trail, floor, pit, and music).
        /// Non-consumable so it can be restored on a new device; delivery
        /// is idempotent (the collection grant is set-insertion and addCoins
        /// only runs when `starterPackClaimed` is still false).
        case starterPack  = "com.macfaldet.RollAlong.starterpack"

        var id: String { rawValue }

        enum Category {
            case lifePack           // grants N lives
            case coinPack           // grants N coins
            case unlimitedUnlock    // non-consumable; flips unlimitedLives true
            case starterPackUnlock  // non-consumable; grants 500 coins + the Aurora collection
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
        ///
        /// 2026-07 reprice (docs/economy/08-reprice.md): amounts re-anchored
        /// to the 750/1,000/1,250/1,500 tier ladder so the smallest pack buys
        /// one Standard item.  Coins-per-dollar must rise MONOTONICALLY up
        /// the ladder (bigger pack = strictly better rate):
        ///
        ///   product     $ price   coins    coins/$
        ///   coins100      0.99       750     758
        ///   coins600      4.99     4,500     902
        ///   coins1300     9.99    10,000   1,001
        ///   coins3000    19.99    22,500   1,126
        ///   coins10000   49.99    60,000   1,200
        ///
        /// (Case names keep their historical amounts — see ProductID note.)
        var rewardCoins: Int {
            switch self {
            case .coins100:    return 750
            case .coins600:    return 4500
            case .coins1300:   return 10000
            case .coins3000:   return 22500
            case .coins10000:  return 60000
            case .starterPack: return 500   // welcome-offer coins (pre-reprice amount)
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
        /// (the top coin pack's random "Money" unlock), or nil.
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

    // MARK: - Delivered-transaction ledger

    /// IDs of transactions whose rewards have been granted, persisted so a
    /// crash between deliverReward and transaction.finish() can't double-grant
    /// consumables when StoreKit replays the update at the next launch.
    /// GameState write-through-persists every granted reward in its didSet,
    /// so recording here immediately after delivery keeps the two stores
    /// consistent (worst case — crash between the two writes — the reward is
    /// granted twice, never lost).
    private var deliveredTransactionIDs: [String] =
        UserDefaults.standard.stringArray(forKey: StoreKitManager.deliveredLedgerKey) ?? []

    private static let deliveredLedgerKey = "ra_iapDeliveredTxnIDs"

    /// Ledger size cap.  StoreKit only replays *unfinished* transactions,
    /// which are always recent, so the ledger never needs deep history —
    /// 200 is orders of magnitude more than can be in flight at once.
    nonisolated static let deliveredLedgerCap = 200

    /// Append a delivered transaction ID, dropping the oldest entries beyond
    /// `cap`.  Pure so unit tests can pin the dedupe + trim behavior.
    nonisolated static func appendingDelivered(
        _ id: String,
        to ledger: [String],
        cap: Int = deliveredLedgerCap
    ) -> [String] {
        var next = ledger
        if !next.contains(id) { next.append(id) }
        if next.count > cap { next.removeFirst(next.count - cap) }
        return next
    }

    private func recordDelivered(_ transactionID: UInt64) {
        deliveredTransactionIDs = Self.appendingDelivered(String(transactionID),
                                                          to: deliveredTransactionIDs)
        UserDefaults.standard.set(deliveredTransactionIDs,
                                  forKey: Self.deliveredLedgerKey)
    }

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
        // Re-drive transactions still unfinished: updates the listener had to
        // defer because they arrived before gameState was bound (Ask to Buy
        // approvals, other-device syncs racing app launch), plus any left
        // over from a crash between deliver and finish in a previous run
        // (the delivered ledger turns those into a bare finish).
        await processUnfinishedTransactions()
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
        // Starter Pack (one-time welcome offer): owners get the complete
        // Aurora collection back on restore — including original buyers who
        // only ever received the ball, who are upgraded to the full
        // collection here — but NOT the 500 coins, which are a one-time
        // consumable delivered only by the purchase path.
        if starterPackSeen, let gs = gameState {
            grantAuroraCollection(to: gs)
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
                    // Same idempotent path as the background listener: the
                    // ledger stops a crash-replay double-grant, and finish
                    // is skipped when delivery fails so StoreKit re-delivers
                    // instead of the purchase being silently lost.
                    guard await handleVerified(transaction) else {
                        self.lastError = "Purchase couldn't be delivered yet — it will retry automatically."
                        return false
                    }
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

    /// Grants the reward for a delivered purchase.  Returns false — having
    /// granted nothing — when gameState isn't bound; the caller must NOT
    /// finish the transaction in that case or the purchase is silently lost.
    /// Deliberately synchronous: handleVerified relies on the ledger check,
    /// this grant, and recordDelivered running without a suspension point so
    /// concurrent MainActor tasks (listener vs. bootstrap replay) can't
    /// interleave and double-deliver the same transaction.
    private func deliverReward(for productID: ProductID) -> Bool {
        guard let gameState else { return false }
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
            // The top coin pack (the historical coins.10000 product, now a
            // 60,000-coin grant) also drops ONE random not-yet-owned "Money"
            // cosmetic — up to three unlock across repeat purchases.
            if productID == .coins10000 {
                grantedCosmetic = grantRandomMoneyCosmetic(gameState)
            }

        case .unlimitedUnlock:
            gameState.unlimitedLives = true
            gameState.grant(BallSkin.diamond)   // exclusive Diamond ball skin
            gameState.reconcileLivesNotification()   // unlimited → no restock alert

        case .starterPackUnlock:
            // Coins deliver exactly once (the claimed flag makes restores and
            // re-deliveries idempotent); the collection grant is set-insertion,
            // so it safely tops up a ball-only legacy buyer too.
            if !gameState.starterPackClaimed {
                gameState.addCoins(productID.rewardCoins)
            }
            grantedCosmetic = grantAuroraCollection(to: gameState)
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
        return true
    }

    /// Grant the complete Aurora collection — every item in the "aurora"
    /// cosmetic bundle (ball, goal, trail, floor, pit, music) — via
    /// `grantBundleFree`, which marks the items free-granted so Sell Back keeps
    /// them but never refunds them.  That marking is load-bearing: the bundle's
    /// items would sell back for 4,125 coins (half their 8,250 catalogue value
    /// under the 2026-07 reprice), so a plain grant would hand a $1.99 pack
    /// nearly the $4.99 coin pack's worth.  Players who already coin-bought part of
    /// the collection are refunded those items' full coinCost by
    /// `grantBundleFree` before the marking, so no paid Sell Back value is
    /// confiscated.  No-ops when the player already owns all six items (a
    /// coin-bought complete bundle keeps its sellability, and the per-launch
    /// restore path avoids churn).  Returns the collection's display name (for
    /// the purchase celebration) when anything new was granted, else nil.
    @discardableResult
    private func grantAuroraCollection(to gs: GameState) -> String? {
        guard let bundle = CosmeticBundle.catalogue.first(where: { $0.id == "aurora" }),
              !gs.completedBundleIDs.contains(bundle.id)
        else { return nil }
        gs.grantBundleFree(bundle)
        return "the \(bundle.displayName) Collection"
    }

    /// Grant ONE random "Money" cosmetic the player doesn't yet own — the ball,
    /// trail, or floor.  Returns its display name (for the celebration) or nil if
    /// all three are already owned.  Deliberately one-at-a-time so the trio
    /// unlocks across repeat top-pack purchases rather than all at once.
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
        /// Reward already granted in a previous pass (crash between deliver
        /// and finish, or the listener overlapping the bootstrap replay) —
        /// finish WITHOUT delivering again.
        case skipAlreadyDelivered
        /// Verified update arrived before bootstrap(with:) bound gameState —
        /// delivering now would silently drop the reward.  Leave the
        /// transaction UNFINISHED; bootstrap's unfinished-transaction replay
        /// (or StoreKit itself at the next launch) re-delivers it.
        case deferUntilBootstrap
    }

    nonisolated static func verifiedUpdateAction(
        productID: String,
        revocationDate: Date?,
        hasGameState: Bool = true,
        alreadyDelivered: Bool = false
    ) -> VerifiedUpdateAction {
        // Revocation wins over everything else: StoreKit delivers refunds and
        // Family Sharing revocations through Transaction.updates as *verified*
        // transactions with revocationDate set.  Delivering here would mint
        // the reward a second time on top of the money back (e.g., refund the
        // top coin pack → another 60,000 coins + a Money cosmetic, forever
        // repeatable).  Revoked and unknown-product updates finish even
        // pre-bootstrap: there is nothing to deliver, so deferring would
        // just leave them unfinished forever (a revoked unlimited unlock is
        // re-mirrored off by refreshEntitlements during bootstrap anyway).
        if revocationDate != nil { return .skipRevoked }
        guard let productID = ProductID(rawValue: productID) else {
            return .skipUnknownProduct
        }
        // An already-granted reward finishes quietly even if gameState isn't
        // bound yet — nothing is left to deliver.
        if alreadyDelivered { return .skipAlreadyDelivered }
        guard hasGameState else { return .deferUntilBootstrap }
        return .deliver(productID)
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            await handle(update, context: "listener")
        }
    }

    /// Called from bootstrap once gameState is bound.  Transactions stay in
    /// Transaction.unfinished until finish() is called, so this picks up both
    /// updates the listener deferred pre-bootstrap and any survivors of a
    /// crash in a previous run.
    private func processUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            await handle(result, context: "unfinished")
        }
    }

    /// Shared per-update processing for the background listener and the
    /// bootstrap unfinished-transaction replay.
    private func handle(_ update: VerificationResult<Transaction>, context: String) async {
        switch update {
        case .verified(let transaction):
            await handleVerified(transaction)
        case .unverified(_, let verificationError):
            // Apple's JWS signature check failed.  Do NOT grant any
            // reward and do NOT finish — let the transaction remain
            // unfinished so StoreKit can retry verification.
            AnalyticsClient.shared.track(
                "iap_verification_failed",
                properties: [
                    "error":   .string(verificationError.localizedDescription),
                    "context": .string(context),
                ]
            )
        }
    }

    /// Processes one *verified* transaction from any source (listener,
    /// bootstrap replay, or the in-app purchase flow).  Returns true when the
    /// player has the reward (delivered now, or found in the ledger) and the
    /// transaction was finished.  A transaction is only ever finished AFTER
    /// its delivery outcome is secured — deliver-then-record-then-finish —
    /// so a crash at any point replays as either a ledger-guarded no-op or a
    /// fresh delivery, never a lost purchase.
    @discardableResult
    private func handleVerified(_ transaction: Transaction) async -> Bool {
        let action = Self.verifiedUpdateAction(
            productID:        transaction.productID,
            revocationDate:   transaction.revocationDate,
            hasGameState:     gameState != nil,
            alreadyDelivered: deliveredTransactionIDs.contains(String(transaction.id))
        )
        switch action {
        case .deliver(let productID):
            // No suspension point between the ledger check above and
            // recordDelivered below — deliverReward is synchronous — so a
            // concurrent MainActor task can't slip in and deliver the same
            // transaction twice.
            guard deliverReward(for: productID) else { return false }
            recordDelivered(transaction.id)
            await transaction.finish()
            return true

        case .skipAlreadyDelivered:
            await transaction.finish()
            return true

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
            await transaction.finish()
            return false

        case .skipUnknownProduct:
            await transaction.finish()
            return false

        case .deferUntilBootstrap:
            // Intentionally NOT finished — processUnfinishedTransactions
            // re-drives it once bootstrap binds gameState.
            AnalyticsClient.shared.track(
                "iap_deferred_pre_bootstrap",
                properties: ["product_id": .string(transaction.productID)]
            )
            return false
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
