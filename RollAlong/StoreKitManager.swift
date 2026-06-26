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

        /// Seasonal bundle IAP products — non-consumable real-money purchases
        /// that grant the full bundle contents + mark ownedBundles.  Idempotent
        /// on restore via the `ownedBundles.contains` guard in deliverReward.
        case summerBundle2026      = "com.macfaldet.RollAlong.bundle.summer2026"
        case halloweenBundle2026   = "com.macfaldet.RollAlong.bundle.halloween2026"
        case winterBundle2026      = "com.macfaldet.RollAlong.bundle.winter2026"
        case valentinesBundle2027  = "com.macfaldet.RollAlong.bundle.valentines2027"
        case stPatricksBundle2027  = "com.macfaldet.RollAlong.bundle.stpatricks2027"
        case newYearBundle2027     = "com.macfaldet.RollAlong.bundle.newyear2027"
        case springBundle2027      = "com.macfaldet.RollAlong.bundle.spring2027"
        case july4Bundle2026       = "com.macfaldet.RollAlong.bundle.july4_2026"
        case muertosBundle2026     = "com.macfaldet.RollAlong.bundle.muertos2026"
        case harvestBundle2026     = "com.macfaldet.RollAlong.bundle.harvest2026"
        case lunarBundle2027       = "com.macfaldet.RollAlong.bundle.lunar2027"
        case mardiGrasBundle2027   = "com.macfaldet.RollAlong.bundle.mardigras2027"
        case prideBundle2027       = "com.macfaldet.RollAlong.bundle.pride2027"
        case oktoberfestBundle2026 = "com.macfaldet.RollAlong.bundle.oktoberfest2026"
        case earthDayBundle2027    = "com.macfaldet.RollAlong.bundle.earthday2027"
        case backToSchoolBundle2026 = "com.macfaldet.RollAlong.bundle.backtoschool2026"

        var id: String { rawValue }

        enum Category {
            case lifePack           // grants N lives
            case coinPack           // grants N coins
            case unlimitedUnlock    // non-consumable; flips unlimitedLives true
            case starterPackUnlock  // non-consumable; grants 500 coins + Aurora skin
            case bundlePurchase     // non-consumable; grants seasonal bundle contents
        }

        var category: Category {
            switch self {
            case .livesPack1, .livesPack5, .livesPack10: return .lifePack
            case .unlimited:                              return .unlimitedUnlock
            case .coins100, .coins600, .coins1300, .coins3000: return .coinPack
            case .starterPack:                            return .starterPackUnlock
            case .summerBundle2026, .halloweenBundle2026, .winterBundle2026,
                 .valentinesBundle2027, .stPatricksBundle2027,
                 .newYearBundle2027, .springBundle2027,
                 .july4Bundle2026, .muertosBundle2026, .harvestBundle2026,
                 .lunarBundle2027, .mardiGrasBundle2027, .prideBundle2027,
                 .oktoberfestBundle2026, .earthDayBundle2027, .backToSchoolBundle2026:
                                                          return .bundlePurchase
            }
        }

        /// The catalogue bundle ID delivered by this IAP.  Non-nil only for
        /// seasonal bundle products.
        ///
        /// **Exhaustive by design** — non-bundle cases listed explicitly so
        /// the Swift compiler flags any newly-added seasonal bundle ProductID
        /// that is missing a bundleID entry (a silent `nil` would break delivery).
        var bundleID: String? {
            switch self {
            case .summerBundle2026:     return "summer-2026"
            case .halloweenBundle2026:  return "halloween-2026"
            case .winterBundle2026:     return "winter-2026"
            case .valentinesBundle2027: return "valentines-2027"
            case .stPatricksBundle2027: return "stpatricks-2027"
            case .newYearBundle2027:    return "newyear-2027"
            case .springBundle2027:     return "spring-2027"
            case .july4Bundle2026:      return "july4-2026"
            case .muertosBundle2026:    return "muertos-2026"
            case .harvestBundle2026:    return "harvest-2026"
            case .lunarBundle2027:      return "lunar-2027"
            case .mardiGrasBundle2027:  return "mardigras-2027"
            case .prideBundle2027:      return "pride-2027"
            case .oktoberfestBundle2026: return "oktoberfest-2026"
            case .earthDayBundle2027:   return "earthday-2027"
            case .backToSchoolBundle2026: return "backtoschool-2026"
            case .livesPack1, .livesPack5, .livesPack10,
                 .unlimited,
                 .coins100, .coins600, .coins1300, .coins3000,
                 .starterPack:          return nil
            }
        }

        /// Reverse lookup — returns the ProductID whose bundleID matches `id`,
        /// or nil if no seasonal IAP covers that bundle.
        static func productID(forBundleID id: String) -> ProductID? {
            allCases.first { $0.bundleID == id }
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

    /// Called by purchase-sheet alert dismiss to clear the error so the same
    /// error string can re-trigger onChange on a subsequent attempt.
    func clearLastError() { lastError = nil }

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
    /// non-consumable, so it lives in currentEntitlements forever.  Seasonal
    /// bundle IAPs are also non-consumable and handled here for restore.
    func refreshEntitlements() async {
        var unlimitedSeen      = false
        var starterPackSeen    = false
        var summerSeen         = false
        var halloweenSeen      = false
        var winterSeen         = false
        var valentinesSeen     = false
        var stPatricksSeen     = false
        var newYearSeen        = false
        var springSeen         = false
        var july4Seen          = false
        var muertosSeen        = false
        var harvestSeen        = false
        var lunarSeen          = false
        var mardiGrasSeen      = false
        var prideSeen          = false
        var oktoberfestSeen    = false
        var earthDaySeen       = false
        var backToSchoolSeen   = false
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
            case ProductID.summerBundle2026.rawValue:        summerSeen      = true
            case ProductID.halloweenBundle2026.rawValue:     halloweenSeen   = true
            case ProductID.winterBundle2026.rawValue:        winterSeen      = true
            case ProductID.valentinesBundle2027.rawValue:    valentinesSeen  = true
            case ProductID.stPatricksBundle2027.rawValue:    stPatricksSeen  = true
            case ProductID.newYearBundle2027.rawValue:       newYearSeen     = true
            case ProductID.springBundle2027.rawValue:        springSeen      = true
            case ProductID.july4Bundle2026.rawValue:         july4Seen       = true
            case ProductID.muertosBundle2026.rawValue:       muertosSeen     = true
            case ProductID.harvestBundle2026.rawValue:       harvestSeen     = true
            case ProductID.lunarBundle2027.rawValue:         lunarSeen       = true
            case ProductID.mardiGrasBundle2027.rawValue:     mardiGrasSeen   = true
            case ProductID.prideBundle2027.rawValue:         prideSeen       = true
            case ProductID.oktoberfestBundle2026.rawValue:   oktoberfestSeen = true
            case ProductID.earthDayBundle2027.rawValue:      earthDaySeen    = true
            case ProductID.backToSchoolBundle2026.rawValue:  backToSchoolSeen = true
            default: break
            }
        }
        if unlimitedSeen   { gameState?.unlimitedLives = true; gameState?.grant(BallSkin.diamond) }
        if starterPackSeen {
            guard let gs = gameState, !gs.starterPackClaimed else { return }
            gs.addCoins(ProductID.starterPack.rewardCoins)
            gs.grant(BallSkin.aurora)
            gs.starterPackClaimed = true
        }
        if summerSeen       { await deliverReward(for: .summerBundle2026)       }
        if halloweenSeen    { await deliverReward(for: .halloweenBundle2026)    }
        if winterSeen       { await deliverReward(for: .winterBundle2026)       }
        if valentinesSeen   { await deliverReward(for: .valentinesBundle2027)   }
        if stPatricksSeen   { await deliverReward(for: .stPatricksBundle2027)   }
        if newYearSeen      { await deliverReward(for: .newYearBundle2027)      }
        if springSeen       { await deliverReward(for: .springBundle2027)       }
        if july4Seen        { await deliverReward(for: .july4Bundle2026)        }
        if muertosSeen      { await deliverReward(for: .muertosBundle2026)      }
        if harvestSeen      { await deliverReward(for: .harvestBundle2026)      }
        if lunarSeen        { await deliverReward(for: .lunarBundle2027)        }
        if mardiGrasSeen    { await deliverReward(for: .mardiGrasBundle2027)    }
        if prideSeen        { await deliverReward(for: .prideBundle2027)        }
        if oktoberfestSeen  { await deliverReward(for: .oktoberfestBundle2026)  }
        if earthDaySeen     { await deliverReward(for: .earthDayBundle2027)     }
        if backToSchoolSeen { await deliverReward(for: .backToSchoolBundle2026) }
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
            gameState.grant(BallSkin.diamond)   // exclusive Diamond ball skin

        case .starterPackUnlock:
            // Only deliver once — guard lets restore calls be idempotent.
            guard !gameState.starterPackClaimed else { break }
            gameState.addCoins(productID.rewardCoins)
            gameState.grant(BallSkin.aurora)
            gameState.starterPackClaimed = true

        case .bundlePurchase:
            // Non-consumable seasonal bundle — grant contents + record ownership.
            // The ownedBundles.contains guard makes this idempotent on restore.
            guard let bundleID = productID.bundleID,
                  let bundle   = CosmeticBundle.catalogue.first(where: { $0.id == bundleID }),
                  !gameState.ownedBundles.contains(bundleID)
            else { break }
            bundle.grantContents(to: gameState)
            gameState.ownedBundles.insert(bundleID)
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
            switch update {
            case .verified(let transaction):
                guard let productID = ProductID(rawValue: transaction.productID) else {
                    // Unknown product ID (e.g., old product retired from the
                    // catalogue).  Finish so it doesn't keep re-delivering.
                    await transaction.finish()
                    continue
                }
                await deliverReward(for: productID)
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
