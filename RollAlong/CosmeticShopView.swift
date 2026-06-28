import SwiftUI

// ---------------------------------------------------------------------------
// CosmeticShopView — the player-facing store.
//
// Tabs across the top per category (Ball, Goal, Trail, Background, Music).
// Body: 2-col lazy grid of item cells.  Each cell shows a category-specific
// preview, the item's name, and a state badge:
//   • Equipped   — currently active
//   • Owned      — owned but not equipped (tap to equip)
//   • <price> 🪙 — buyable with coins (tap to buy + auto-equip)
//   • Locked     — only when unlockLevel > player's highestUnlocked
// ---------------------------------------------------------------------------

private enum ShopCategory: String, CaseIterable, Identifiable {
    case collections, ball, goal, trail, floor, pit, boundary, music
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .collections: return "square.stack.3d.up.fill"
        case .ball:        return "circle.fill"
        case .goal:        return "sparkles"
        case .trail:       return "scribble.variable"
        case .floor:       return "square.fill.on.square.fill"
        case .pit:         return "circle.dotted"
        case .boundary:    return "square.dashed"
        case .music:       return "music.note"
        }
    }
    var displayName: String {
        switch self {
        case .collections: return "Collections"
        case .ball:        return "Ball"
        case .goal:        return "Goal"
        case .trail:       return "Trail"
        case .floor:       return "Floor"
        case .pit:         return "Pit"
        case .boundary:    return "Boundary"
        case .music:       return "Music"
        }
    }
}

/// The store has two faces:
///   • `.shop`    — a curated front: the 2-hour rotating featured bundle + a
///                  few odds-and-ends cosmetics.  The ONLY place to buy.
///   • `.catalog` — the full browsable grid (reached from the Shop).  Browse +
///                  equip-owned only; purchasing happens in the Shop.
enum ShopMode { case shop, catalog }

struct CosmeticShopView: View {
    var mode: ShopMode = .catalog

    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator
    @Environment(\.dismiss) private var dismiss
    /// Observed for purchase-in-progress state on seasonal IAP buttons (S8).
    @ObservedObject private var store = StoreKitManager.shared

    @State private var category: ShopCategory = .collections
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var showBuyCoinsSheet: Bool = false
    @State private var purchaseError: String? = nil
    /// Non-nil while the collection-complete toast is visible.  Holds the
    /// display name of the newly completed bundle.
    @State private var completionToastBundle: String? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            if mode == .shop {
                shopFront
            } else {
                VStack(spacing: 0) {
                    tabBar
                    ScrollView {
                        grid
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 36)
                    }
                }
            }

            // ── Collection-complete toast (S7) ────────────────────────────
            // Floats above the scroll view and slides in from the bottom
            // edge.  Auto-dismisses after 3 seconds.  Non-interactive so it
            // doesn't block taps on the shop.
            if let bundleName = completionToastBundle {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(red: 0.24, green: 0.82, blue: 0.48))
                        Text("Collection Complete!")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(bundleName)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(white: 0.68))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.16))
                            .overlay(
                                Capsule().stroke(
                                    Color(red: 0.24, green: 0.82, blue: 0.48).opacity(0.55),
                                    lineWidth: 1)
                            )
                    )
                    .shadow(color: .black.opacity(0.40), radius: 12, y: 4)
                    .padding(.bottom, 28)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: completionToastBundle)
        .navigationTitle(mode == .shop ? "Shop" : "Catalog")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                // Shop returns Home; Catalog (pushed from the Shop) pops back.
                Button { if mode == .shop { nav.goHome() } else { dismiss() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(mode == .shop ? "Home" : "Shop")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.white)
                }
            }
            // Coin pill, top-right — tap to summon the Get Coins sheet.
            ToolbarItem(placement: .navigationBarTrailing) {
                coinPill
            }
        }
        .alert("Heads up", isPresented: $showAlert) {
            Button("Get more coins") {
                showBuyCoinsSheet = true
                AnalyticsClient.shared.track("buy_coins_sheet_opened",
                                             properties: ["from": .string("shortfall_alert")])
            }
            Button("Got it", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showBuyCoinsSheet) {
            BuyCoinsSheet()
        }
        .onChange(of: store.lastError) { _, err in purchaseError = err }
        .alert("Purchase Failed", isPresented: Binding(
            get: { purchaseError != nil },
            set: { _ in purchaseError = nil; store.clearLastError() }
        ), actions: { Button("OK", role: .cancel) {} },
        message: { Text(purchaseError ?? "") })
    }

    // MARK: - Shop front (curated, rotating storefront)

    private var shopFront: some View {
        ScrollView {
            VStack(spacing: 22) {
                // Refresh countdown — the whole shop rotates every 2 hours.
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .bold))
                        Text("Refreshes in \(ShopRotation.countdown(at: ctx.date))")
                            .monospacedDigit()
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
                    .frame(maxWidth: .infinity)
                }

                // The single bundle buyable right now.
                if let bundle = ShopRotation.featuredBundle() {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("FEATURED BUNDLE")
                        collectionCard(bundle, isFeatured: true)
                    }
                }

                // Odds-and-ends — one featured pick from each of the seven
                // cosmetic categories (ball · trail · goal · floor · pit ·
                // boundary · music).
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("TODAY'S PICKS")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                        GridItem(.flexible(), spacing: 14),
                                        GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        if let b  = ShopRotation.featuredBall()  { itemCell(item: b) }
                        if let tr = ShopRotation.featuredTrail() { itemCell(item: tr) }
                        if let g  = ShopRotation.featuredGoal()  { itemCell(item: g) }
                        if let f  = ShopRotation.featuredFloor() { itemCell(item: f) }
                        if let p  = ShopRotation.featuredPit()   { itemCell(item: p) }
                        if let bd = ShopRotation.featuredBoundary() { itemCell(item: bd) }
                        if let m  = ShopRotation.featuredMusic() { itemCell(item: m) }
                    }
                }

                // The player's wardrobe — equip what they already own.  Sits
                // just above the Catalog so "equip" reads before "browse/buy".
                NavigationLink(value: HomeRoute.locker) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.18))
                                .frame(width: 58, height: 58)
                            Image(systemName: "tshirt.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open Your Locker")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Equip the balls, trails, goals, floors & more you own")
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.10, green: 0.62, blue: 0.55),
                                         Color(red: 0.16, green: 0.44, blue: 0.72)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.white.opacity(0.20), lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.12, green: 0.52, blue: 0.55).opacity(0.45),
                            radius: 16, y: 7)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                // Everything else lives in the browsable Catalog — a big,
                // gradient call-to-action so it reads as the next thing to do.
                NavigationLink(value: HomeRoute.catalog) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.18))
                                .frame(width: 58, height: 58)
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 27, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Browse Full Catalog")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Every ball, trail, goal, floor & more — buy complete sets")
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.30, green: 0.42, blue: 0.95),
                                         Color(red: 0.56, green: 0.30, blue: 0.95)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.white.opacity(0.20), lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.42, green: 0.34, blue: 0.95).opacity(0.45),
                            radius: 16, y: 7)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
    }

    // MARK: - Coin pill (top-right, summons Get Coins)

    /// The same coin pill as the home screen — shows the balance and opens the
    /// Get Coins sheet on tap.  Lives in the nav bar's trailing slot here.
    private var coinPill: some View {
        Button {
            showBuyCoinsSheet = true
            AnalyticsClient.shared.track("buy_coins_sheet_opened",
                                         properties: ["from": .string("shop_pill")])
        } label: {
            HStack(spacing: 6) {
                CoinIcon(size: 16)
                Text("\(gameState.coinBalance)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(gameState.coinBalance)))
                    .animation(.easeInOut(duration: 0.4), value: gameState.coinBalance)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(white: 0.55))
            }
            // No custom capsule here — the nav-bar toolbar item already supplies
            // its own pill background (same as the Home button). Adding our own
            // produced a double border.
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gameState.coinBalance) coins")
        .accessibilityHint("Opens the get-coins shop.")
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ShopCategory.allCases) { cat in
                    tabButton(cat)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    private func tabButton(_ cat: ShopCategory) -> some View {
        let isActive = category == cat
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { category = cat }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(cat.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isActive ? .black : Color(white: 0.80))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isActive ? Color.white : Color(white: 0.16))
            )
        }
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        switch category {
        case .collections:
            collectionsView
        case .ball:
            ballSection
        case .goal:
            categoryGrid(items: GoalSkin.allCases)
        case .trail:
            // Bundle-exclusive trails (Money Roll) hidden unless owned — same
            // rule as the Ball grid.
            categoryGrid(items: TrailColor.allCases.filter {
                !$0.isBundleExclusive || gameState.isOwned($0)
            })
        case .floor:
            categoryGrid(items: Floor.allCases.filter {
                !$0.isBundleExclusive || gameState.isOwned($0)
            })
        case .pit:
            categoryGrid(items: Pit.allCases)
        case .boundary:
            categoryGrid(items: Boundary.allCases)
        case .music:
            categoryGrid(items: MusicTrack.allCases)
        }
    }

    private func categoryGrid<Item: CosmeticItem>(items: [Item]) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(items, id: \.id) { item in
                itemCell(item: item)
            }
        }
    }

    /// The Ball tab stacks Packs (multi-ball collections that shuffle each
    /// attempt) above the individual ball grid — Packs live inside the Ball
    /// section rather than getting their own tab.
    @ViewBuilder
    private var ballSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !BallPack.catalogue.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("PACKS")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(BallPack.catalogue) { pack in
                            packCell(pack)
                        }
                    }
                }
                sectionLabel("BALLS")
            }
            // Bundle-exclusive balls are hidden from the individual Ball grid
            // if the user does NOT own them — purchase path is via the IAP
            // bundle, not the coin shop.  Owned bundle-exclusive skins ARE
            // shown so the user can equip them (possession implies legitimate
            // acquisition via the bundle, starter pack, or challenge track).
            categoryGrid(items: BallSkin.allCases.filter {
                !$0.isBundleExclusive || gameState.isOwned($0)
            })
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .kerning(1.4)
            .foregroundStyle(Color(white: 0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Item cell

    private func itemCell<Item: CosmeticItem>(item: Item) -> some View {
        let owned = gameState.isOwned(item)
        let equipped = isEquipped(item)
        let inShop = ShopRotation.isFeatured(item)
        let bundleComplete = owned && CosmeticBundle.catalogue.contains {
            gameState.completedBundleIDs.contains($0.id) && $0.contains(item)
        }
        // In the Catalog, locked items grey out; the strongest status border
        // wins: equipped (green) ▸ bundle-complete (gold) ▸ in-shop-now (blue).
        let greyed = (mode == .catalog) && !owned
        let border: Color? =
            equipped         ? Color(red: 0.28, green: 0.85, blue: 0.45)
            : bundleComplete ? Color(red: 1.00, green: 0.82, blue: 0.30)
            : (mode == .catalog && !owned && inShop) ? Color(red: 0.30, green: 0.62, blue: 1.00)
            : nil
        return Button {
            handleTap(item: item, owned: owned, equipped: equipped)
        } label: {
            VStack(spacing: 8) {
                preview(for: item)
                    .frame(height: 78)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(white: 0.10))
                    )
                    .overlay(alignment: .topTrailing) {
                        TierBadge(tier: item.tier, compact: true)
                            .padding(6)
                    }

                Text(item.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                // Catalog: surface the set(s) this cosmetic was released with.
                if mode == .catalog {
                    let caption = bundleCaption(for: item)
                    Text(caption.isEmpty ? "Daily picks only" : caption)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.50))
                        .lineLimit(1)
                }

                stateBadge(item: item, owned: owned, equipped: equipped)
            }
            .opacity(greyed ? 0.5 : 1.0)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(border ?? .clear, lineWidth: border == nil ? 0 : 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(item: item, owned: owned, equipped: equipped))
    }

    private func stateBadge<Item: CosmeticItem>(item: Item, owned: Bool, equipped: Bool) -> some View {
        Group {
            if equipped {
                Text("EQUIPPED")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(1.0)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white))
            } else if owned {
                Text("OWNED — TAP TO EQUIP")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(Color(white: 0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(white: 0.22)))
            } else {
                // Catalog shows the individual price as information only — you
                // buy the bundle, not the item — so it's a neutral pill there.
                // The Shop keeps the green "affordable / buy" pill.
                let inCatalog = (mode == .catalog)
                HStack(spacing: 4) {
                    CoinIcon(size: 13)
                    Text("\(item.coinCost)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(inCatalog ? Color(white: 0.82)
                                                   : (canAfford(item) ? .white : Color(white: 0.45)))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(inCatalog ? Color(white: 0.20)
                                        : (canAfford(item) ? Color(red: 0.20, green: 0.78, blue: 0.38).opacity(0.85)
                                                           : Color(white: 0.22)))
                )
            }
        }
    }

    private func accessibilityLabel<Item: CosmeticItem>(item: Item, owned: Bool, equipped: Bool) -> String {
        let category = String(describing: type(of: item))
        if equipped { return "\(item.displayName) \(category), equipped." }
        if owned    { return "\(item.displayName) \(category), owned. Double-tap to equip." }
        if mode == .catalog {
            return "\(item.displayName) \(category), \(item.coinCost) coins. Sold as part of a bundle — double-tap for details."
        }
        return "\(item.displayName) \(category), \(item.coinCost) coins. Double-tap to buy."
    }

    // MARK: - Tap handling

    private func handleTap<Item: CosmeticItem>(item: Item, owned: Bool, equipped: Bool) {
        if equipped { return }
        if owned {
            equip(item)
            AnalyticsClient.shared.track(
                "cosmetic_equipped",
                properties: [
                    "category": .string(category.rawValue),
                    "item":     .string(item.rawValue),
                    "tier":     .string(item.tier.rawValue),
                ]
            )
            return
        }
        // Catalog: individuals aren't bought directly — you buy the bundle.
        // EXCEPTION: when this is the last unowned item of a set, buying it
        // completes that set, so route straight to that bundle purchase.
        if mode == .catalog {
            if let bundle = lastItemBundle(for: item) {
                handleBundleTap(bundle, owned: false)
            } else {
                let names = CosmeticBundle.bundles(containing: item).map(\.displayName)
                if names.isEmpty {
                    alertMessage = "\(item.displayName) shows up in the Shop's daily picks — grab it there."
                } else {
                    let list = names.joined(separator: ", ")
                    let noun = names.count > 1 ? "bundles" : "bundle"
                    alertMessage = "\(item.displayName) is part of the \(list) \(noun). Buy the \(noun) from the Collections tab to unlock it."
                }
                showAlert = true
            }
            return
        }
        // Buy + equip
        if !canAfford(item) {
            AnalyticsClient.shared.track(
                "cosmetic_purchase_blocked",
                properties: [
                    "category":  .string(category.rawValue),
                    "item":      .string(item.rawValue),
                    "cost":      .int(item.coinCost),
                    "balance":   .int(gameState.coinBalance),
                    "shortfall": .int(item.coinCost - gameState.coinBalance),
                ]
            )
            alertMessage = "You need \(item.coinCost - gameState.coinBalance) more coins.\n\nEarn coins by playing levels and collecting pickups, or buy a coin pack (coming with the next update)."
            showAlert = true
            return
        }
        let beforeCompleted = gameState.completedBundleIDs
        let bought = gameState.purchase(item)
        if bought {
            AnalyticsClient.shared.track(
                "cosmetic_purchased",
                properties: [
                    "category": .string(category.rawValue),
                    "item":     .string(item.rawValue),
                    "tier":     .string(item.tier.rawValue),
                    "cost":     .int(item.coinCost),
                ]
            )
            equip(item)
            AnalyticsClient.shared.track(
                "cosmetic_equipped",
                properties: [
                    "category":      .string(category.rawValue),
                    "item":          .string(item.rawValue),
                    "after_purchase": .bool(true),
                ]
            )
            checkCompletionToast(before: beforeCompleted)
        }
    }

    private func equip<Item: CosmeticItem>(_ item: Item) {
        switch item {
        case let s as BallSkin:   gameState.equipBall(s)
        case let g as GoalSkin:   gameState.equippedGoal = g
        case let t as TrailColor: gameState.equippedTrail = t
        case let f as Floor:      gameState.equippedFloor = f
        case let p as Pit:        gameState.equippedPit = p
        case let b as Boundary:   gameState.equippedBoundary = b
        case let m as MusicTrack: gameState.equippedMusic = m
        default: break
        }
    }

    private func isEquipped<Item: CosmeticItem>(_ item: Item) -> Bool {
        switch item {
        case let s as BallSkin:   return s == gameState.activeSkin && gameState.equippedPackID == nil
        case let g as GoalSkin:   return g == gameState.equippedGoal
        case let t as TrailColor: return t == gameState.equippedTrail
        case let f as Floor:      return f == gameState.equippedFloor
        case let p as Pit:        return p == gameState.equippedPit
        case let b as Boundary:   return b == gameState.equippedBoundary
        case let m as MusicTrack: return m == gameState.equippedMusic
        default: return false
        }
    }

    private func canAfford<Item: CosmeticItem>(_ item: Item) -> Bool {
        gameState.coinBalance >= item.coinCost
    }

    // MARK: - Previews

    @ViewBuilder
    private func preview<Item: CosmeticItem>(for item: Item) -> some View {
        switch item {
        case let s as BallSkin:   ballPreview(s)
        case let g as GoalSkin:   goalPreview(g)
        case let t as TrailColor: trailPreview(t)
        case let f as Floor:      floorPreview(f)
        case let p as Pit:        pitPreview(p)
        case let b as Boundary:   boundaryPreview(b)
        case let m as MusicTrack: musicPreview(m)
        default: EmptyView()
        }
    }

    /// A short length of wall in the Boundary's colours — base fill, a lit top
    /// edge, and a darker base, the same recipe the games render walls with.
    private func boundaryPreview(_ boundary: Boundary) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(colors: [boundary.color, boundary.deepColor],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 86, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(boundary.edgeColor.opacity(0.9), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 5, x: 0, y: 3)
    }

    private func ballPreview(_ skin: BallSkin) -> some View {
        BallSkinView(skin: skin, diameter: 54)
            .frame(width: 54, height: 54)
            .shadow(color: Color.black.opacity(0.40), radius: 6, x: 2, y: 4)
    }

    private func goalPreview(_ goal: GoalSkin) -> some View {
        Circle()
            .fill(GoalSkin.previewGradient(for: goal))
            .overlay(
                Circle()
                    .stroke(LinearGradient(
                        colors: [.white.opacity(0.4), .clear],
                        startPoint: .top, endPoint: .bottom
                    ), lineWidth: 1.5)
            )
            .frame(width: 56, height: 56)
            .shadow(color: Color.black.opacity(0.40), radius: 6, x: 0, y: 4)
    }

    @ViewBuilder
    private func trailPreview(_ trail: TrailColor) -> some View {
        if trail == .none {
            Canvas { ctx, size in
                var p = Path()
                p.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.80))
                p.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.22))
                ctx.stroke(p, with: .color(Color(white: 0.30)),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 5]))
            }
            .padding(8)
        } else {
            // Render the actual trail effect along a gentle sample curve so the
            // cell sells what the trail really does.  Animated like in-game.
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    let n = 18
                    var pts: [CGPoint] = []
                    for i in 0..<n {
                        let f = Double(i) / Double(n - 1)
                        let x = size.width  * CGFloat(0.14 + f * 0.72)
                        let y = size.height * CGFloat(0.50 + 0.30 * sin(f * .pi * 1.4))
                        pts.append(CGPoint(x: x, y: y))
                    }
                    drawRichTrail(ctx, points: pts, trail: trail, t: t, baseWidth: 5)
                }
            }
            .padding(8)
        }
    }

    private func floorPreview(_ floor: Floor) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(floor.color)
            .frame(width: 90, height: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black.opacity(0.25), lineWidth: 0.6)
            )
    }

    private func pitPreview(_ pit: Pit) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.18))
            RoundedRectangle(cornerRadius: 4)
                .fill(pit.color)
                .frame(width: 38, height: 22)
        }
        .frame(width: 90, height: 60)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.25), lineWidth: 0.6)
        )
    }

    // =========================================================================
    // MARK: - Collections view (S2)
    //
    // Collection cards replaced the old flat bundle list.  Each card shows:
    //   • A 6-slot item preview row (ball · goal · trail · floor · pit · music)
    //     with owned items full-colour and unowned items dimmed + locked.
    //   • X/Y progress badge in the top-right corner.
    //   • "Complete the Set" CTA when partially owned; "Get Bundle" when 0 owned;
    //     "✓ Collection Complete" when all owned.
    // The featured collection (weekly rotation) gets a gold border and badge.
    // =========================================================================

    /// Weekly-rotating featured bundle — drawn only from permanent (non-seasonal)
    /// bundles so seasonal items don't occupy two sections at once.
    private var permanentFeaturedBundle: CosmeticBundle {
        let permanent = CosmeticBundle.catalogue.filter { !$0.isLimitedTime }
        guard !permanent.isEmpty else { return CosmeticBundle.catalogue[0] }
        let week = Calendar.current.component(.weekOfYear, from: Date())
        return permanent[week % permanent.count]
    }

    @ViewBuilder
    private var collectionsView: some View {
        let seasonal  = CosmeticBundle.catalogue.filter { $0.isLimitedTime && $0.isAvailable }
        let permanent = CosmeticBundle.catalogue.filter { !$0.isLimitedTime }
        let featured  = permanentFeaturedBundle

        LazyVStack(alignment: .leading, spacing: 0) {
            // ── Limited-time seasonal bundles (top of shop) ───────────────
            if !seasonal.isEmpty {
                limitedTimeSectionHeader
                    .padding(.bottom, 8)
                ForEach(seasonal) { bundle in
                    collectionCard(bundle, isFeatured: false)
                        .padding(.bottom, 12)
                }
                Color(white: 0.20)
                    .frame(height: 0.5)
                    .padding(.vertical, 14)
            }

            // ── Weekly featured (permanent rotation) ─────────────────────
            sectionLabel("FEATURED THIS WEEK")
                .padding(.bottom, 8)
            collectionCard(featured, isFeatured: true)
                .padding(.bottom, 22)

            // ── All permanent collections ─────────────────────────────────
            sectionLabel("ALL COLLECTIONS")
                .padding(.bottom, 8)
            ForEach(permanent.filter { $0.id != featured.id }) { bundle in
                collectionCard(bundle, isFeatured: false)
                    .padding(.bottom, 12)
            }
        }
    }

    private var limitedTimeSectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 1.00, green: 0.42, blue: 0.18))
            Text("LIMITED TIME")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .kerning(1.4)
                .foregroundStyle(Color(red: 1.00, green: 0.42, blue: 0.18))
        }
    }

    private func collectionCard(_ bundle: CosmeticBundle, isFeatured: Bool) -> some View {
        // A set the player already owns in full (bought as a unit OR every
        // item owned individually) reads as complete — no buy button.
        let bundleOwned = gameState.completedBundleIDs.contains(bundle.id)
        let owned       = ownedCount(in: bundle)
        let total       = bundle.itemCount
        // Catalog sells bundles at the full prorated price; the Shop sells the
        // featured bundle at the window's randomized discount off that price.
        let isShop      = mode == .shop
        let discount    = ShopRotation.featuredDiscount()
        let prorated    = bundle.proratedPrice(in: gameState)
        let cost        = bundleCost(bundle)
        let discounted  = isShop && cost < prorated
        let canAfford   = gameState.coinBalance >= cost

        return VStack(alignment: .leading, spacing: 10) {
            // ── Title row ────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    // Chips row — ⚡ DEAL, ⭐ FEATURED and/or 🔥 LIMITED
                    let showFeatured = isFeatured
                    let showLimited  = bundle.isLimitedTime && bundle.isAvailable
                    if discounted || showFeatured || showLimited {
                        HStack(spacing: 6) {
                            if discounted {
                                Text("⚡ \(discount.label.uppercased()) DEAL · \(discount.percent)% OFF")
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .kerning(1.2)
                                    .foregroundStyle(discount.color)
                            }
                            if showFeatured {
                                Text("⭐ FEATURED")
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .kerning(1.4)
                                    .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.30))
                            }
                            if showLimited {
                                HStack(spacing: 3) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    if let label = bundle.timeRemainingLabel {
                                        Text(label.uppercased())
                                    } else {
                                        Text("LIMITED TIME")
                                    }
                                }
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .kerning(1.2)
                                .foregroundStyle(limitedTimeColor(for: bundle))
                            }
                        }
                    }
                    Text(bundle.displayName)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(bundle.tagline)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.58))
                        .lineLimit(2)
                }
                Spacer()
                // X/Y progress badge
                if !bundleOwned {
                    collectionProgressBadge(owned: owned, total: total)
                }
            }

            // ── 6-slot item row ──────────────────────────────────────────
            collectionSlotRow(bundle)

            // ── Action button ────────────────────────────────────────────
            if bundleOwned {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Collection Complete")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color(red: 0.24, green: 0.82, blue: 0.48))
                .padding(.top, 2)
            } else {
                Button {
                    handleBundleTap(bundle, owned: bundleOwned)
                } label: {
                    HStack(spacing: 6) {
                        Text(owned > 0 ? "Complete the Set" : "Get Bundle")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(canAfford ? .black : Color(white: 0.50))
                        Spacer()
                        HStack(spacing: 5) {
                            if discounted {
                                Text("\(prorated)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .strikethrough(true, color: (canAfford ? Color.black : Color(white: 0.45)).opacity(0.55))
                                    .foregroundStyle((canAfford ? Color.black : Color(white: 0.45)).opacity(0.55))
                            }
                            HStack(spacing: 3) {
                                CoinIcon(size: 13)
                                Text("\(cost)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(canAfford ? .black : Color(white: 0.45))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canAfford
                                  ? (owned > 0
                                     ? Color(red: 0.30, green: 0.86, blue: 0.56)   // teal-green for "complete set"
                                     : Color.white)                                  // white for "get bundle"
                                  : Color(white: 0.20))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(white: isFeatured ? 0.14 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(borderColor(bundle: bundle,
                                            isFeatured: isFeatured,
                                            bundleOwned: bundleOwned),
                                lineWidth: 1.2)
                )
        )
    }

    /// Border color for a collection card — priority: complete > seasonal > featured > none.
    private func borderColor(bundle: CosmeticBundle, isFeatured: Bool, bundleOwned: Bool) -> Color {
        // Owned/complete → gold.  Currently the Shop's featured (buyable) bundle → blue.
        if bundleOwned                                       { return Color(red: 1.00, green: 0.82, blue: 0.30).opacity(0.85) }
        if ShopRotation.featuredBundle()?.id == bundle.id    { return Color(red: 0.30, green: 0.62, blue: 1.00).opacity(0.85) }
        if bundle.isLimitedTime && bundle.isAvailable        { return limitedTimeColor(for: bundle).opacity(0.50) }
        if isFeatured                                        { return Color(red: 1.00, green: 0.84, blue: 0.30).opacity(0.40) }
        return .clear
    }

    /// Countdown text colour scales from amber (many days) → orange → red as deadline nears.
    private func limitedTimeColor(for bundle: CosmeticBundle) -> Color {
        switch bundle.daysRemaining ?? 999 {
        case 0...3:   return Color(red: 1.00, green: 0.28, blue: 0.18)  // urgent red-orange
        case 4...7:   return Color(red: 1.00, green: 0.52, blue: 0.18)  // orange
        default:      return Color(red: 1.00, green: 0.72, blue: 0.22)  // amber
        }
    }

    // X / Y badge showing collection progress.
    private func collectionProgressBadge(owned: Int, total: Int) -> some View {
        let fraction = total > 0 ? Double(owned) / Double(total) : 0
        let color: Color = owned == 0
            ? Color(white: 0.35)
            : (owned == total
               ? Color(red: 0.24, green: 0.82, blue: 0.48)
               : Color(red: 1.00, green: 0.72, blue: 0.20))
        return HStack(spacing: 3) {
            // Mini dot-progress strip
            HStack(spacing: 3) {
                ForEach(0..<min(total, 6), id: \.self) { i in
                    Circle()
                        .fill(i < owned ? color : Color(white: 0.22))
                        .frame(width: 6, height: 6)
                }
            }
            Text("\(owned)/\(total)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(white: 0.12)))
        .animation(.easeInOut(duration: 0.3), value: fraction)
    }

    // ── 6-slot item row ──────────────────────────────────────────────────────

    private func collectionSlotRow(_ bundle: CosmeticBundle) -> some View {
        HStack(spacing: 6) {
            // Ball
            collectionSlot(label: "Ball",
                           isOwned: bundle.balls.first.map { gameState.isOwned($0) }) {
                if let ball = bundle.balls.first {
                    BallSkinView(skin: ball, diameter: 34)
                        .frame(width: 34, height: 34)
                }
                if bundle.balls.count > 1 {
                    Text("+\(bundle.balls.count - 1)")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(Color(white: 0.85))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color(white: 0.22)))
                        .offset(x: 10, y: -10)
                }
            }
            // Goal
            collectionSlot(label: "Goal",
                           isOwned: bundle.goals.first.map { gameState.isOwned($0) }) {
                if let goal = bundle.goals.first {
                    Circle()
                        .fill(GoalSkin.previewGradient(for: goal))
                        .frame(width: 34, height: 34)
                }
            }
            // Trail
            collectionSlot(label: "Trail",
                           isOwned: bundle.trails.first.map { gameState.isOwned($0) }) {
                if let trail = bundle.trails.first {
                    Canvas { ctx, size in
                        var p = Path()
                        p.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.88))
                        p.addLine(to: CGPoint(x: size.width * 0.88, y: size.height * 0.12))
                        ctx.stroke(p, with: .color(trail == .none ? Color(white: 0.30) : trail.color),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                    .frame(width: 38, height: 38)
                }
            }
            // Floor
            collectionSlot(label: "Floor",
                           isOwned: bundle.floors.first.map { gameState.isOwned($0) }) {
                if let floor = bundle.floors.first {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(floor.color)
                        .frame(width: 38, height: 26)
                }
            }
            // Pit
            collectionSlot(label: "Pit",
                           isOwned: bundle.pits.first.map { gameState.isOwned($0) }) {
                if let pit = bundle.pits.first {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(white: 0.22))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(pit.color)
                            .frame(width: 18, height: 10)
                    }
                    .frame(width: 38, height: 26)
                }
            }
            // Music
            collectionSlot(label: "Music",
                           isOwned: bundle.music.first.map { gameState.isOwned($0) }) {
                if let track = bundle.music.first {
                    Image(systemName: track == .none ? "speaker.slash.fill" : "music.note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.45, green: 0.65, blue: 1.00),
                                         Color(red: 0.25, green: 0.40, blue: 0.85)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
            }
        }
    }

    /// A single item slot in a collection card.  `isOwned == nil` means the
    /// bundle has no item in this category → renders a dotted empty placeholder.
    /// `isOwned == false` → dimmed preview + lock icon.
    /// `isOwned == true`  → full-colour preview + subtle green ring.
    private func collectionSlot<Content: View>(
        label: String,
        isOwned: Bool?,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let owned   = isOwned == true
        let isEmpty = isOwned == nil

        return VStack(spacing: 4) {
            ZStack {
                // Slot background
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEmpty ? Color.clear : Color(white: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isEmpty
                                    ? Color(white: 0.22).opacity(0.60)
                                    : (owned
                                       ? Color(red: 0.24, green: 0.82, blue: 0.48).opacity(0.55)
                                       : Color.clear),
                                style: isEmpty
                                    ? StrokeStyle(lineWidth: 1.0, dash: [3, 3])
                                    : StrokeStyle(lineWidth: 1.2)
                            )
                    )

                if isEmpty {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(white: 0.22))
                } else {
                    // Item preview — dimmed when locked
                    content()
                        .opacity(owned ? 1.0 : 0.28)

                    // Lock icon overlay
                    if !owned {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(white: 0.70))
                    }
                }
            }
            .frame(width: 52, height: 52)

            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(isEmpty ? Color(white: 0.22) : Color(white: 0.40))
        }
        .frame(maxWidth: .infinity)
    }

    // ── Bundle ownership helpers ─────────────────────────────────────────────

    private func ownedCount(in bundle: CosmeticBundle) -> Int {
        var n = 0
        n += bundle.balls.filter  { gameState.isOwned($0) }.count
        n += bundle.goals.filter  { gameState.isOwned($0) }.count
        n += bundle.trails.filter { gameState.isOwned($0) }.count
        n += bundle.floors.filter { gameState.isOwned($0) }.count
        n += bundle.pits.filter   { gameState.isOwned($0) }.count
        n += bundle.music.filter  { gameState.isOwned($0) }.count
        return n
    }

    /// The bundle for which `item` is the single remaining unowned item, so
    /// buying it completes the set.  nil if the item isn't one-away in any set.
    /// (Only meaningful when `item` itself is unowned, which is the only path
    /// that calls it.)
    private func lastItemBundle<Item: CosmeticItem>(for item: Item) -> CosmeticBundle? {
        CosmeticBundle.catalogue.first {
            $0.contains(item) && ownedCount(in: $0) == $0.itemCount - 1
        }
    }

    /// Human-readable list of the bundle(s) an item was released with, e.g.
    /// "Hellfire" or "Hellfire +1".  Empty when the item is in no bundle
    /// (obtainable only via the Shop's daily individual picks).
    private func bundleCaption<Item: CosmeticItem>(for item: Item) -> String {
        let names = CosmeticBundle.bundles(containing: item).map(\.displayName)
        guard let first = names.first else { return "" }
        return names.count > 1 ? "\(first) +\(names.count - 1)" : first
    }

    /// The price the player pays for `bundle` on the current surface: the
    /// Catalog charges the full prorated price; the Shop charges the window's
    /// discounted price off that same prorated base.
    private func bundleCost(_ bundle: CosmeticBundle) -> Int {
        mode == .shop
            ? bundle.shopPrice(in: gameState, discount: ShopRotation.featuredDiscount())
            : bundle.proratedPrice(in: gameState)
    }

    private func canAffordBundle(_ bundle: CosmeticBundle) -> Bool {
        gameState.coinBalance >= bundleCost(bundle)
    }

    /// Buy a bundle — grants every yet-unowned item and marks the set owned.
    /// Live in BOTH surfaces now: the Catalog charges the full prorated price,
    /// the Shop the discounted price for the featured bundle.
    private func handleBundleTap(_ bundle: CosmeticBundle, owned: Bool) {
        if owned { return }
        let cost = bundleCost(bundle)
        guard gameState.coinBalance >= cost else {
            alertMessage = "You need \(cost - gameState.coinBalance) more coins for the \(bundle.displayName) bundle.\n\nEarn coins by playing levels and collecting pickups, or buy a coin pack."
            showAlert = true
            return
        }
        let discountPct = mode == .shop ? ShopRotation.featuredDiscount().percent : 0
        let beforeCompleted = gameState.completedBundleIDs
        _ = gameState.spendCoins(cost)
        bundle.grantContents(to: gameState)
        gameState.ownedBundles.insert(bundle.id)
        AnalyticsClient.shared.track(
            "bundle_purchased",
            properties: [
                "bundle":       .string(bundle.id),
                "price":        .int(cost),
                "items":        .int(bundle.itemCount),
                "surface":      .string(mode == .shop ? "shop" : "catalog"),
                "discount_pct": .int(discountPct),
            ]
        )
        checkCompletionToast(before: beforeCompleted)
    }

    /// Show the collection-complete toast if the most recent purchase
    /// caused any new bundle to be fully owned.  Call with a snapshot of
    /// `completedBundleIDs` taken BEFORE the purchase.  Auto-dismisses
    /// after 3 seconds.
    private func checkCompletionToast(before: Set<String>) {
        let newIDs = gameState.completedBundleIDs.subtracting(before)
        guard let newID = newIDs.first,
              let bundle = CosmeticBundle.catalogue.first(where: { $0.id == newID })
        else { return }
        completionToastBundle = bundle.displayName
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            completionToastBundle = nil
        }
    }

    // MARK: - Pack cell

    private func packCell(_ pack: BallPack) -> some View {
        let owned    = gameState.ownsPack(pack)
        let equipped = gameState.isPackEquipped(pack)
        return Button {
            handlePackTap(pack, owned: owned, equipped: equipped)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(pack.displayName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    packBadge(pack, owned: owned, equipped: equipped)
                }
                Text(pack.tagline)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.65))
                    .multilineTextAlignment(.leading)
                // Mini swatches of every ball in the pack.
                HStack(spacing: 8) {
                    ForEach(pack.skins, id: \.self) { skin in
                        BallSkinView(skin: skin, diameter: 30)
                            .frame(width: 30, height: 30)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(equipped ? Color.white.opacity(0.55)
                                             : (owned ? Color.white.opacity(0.30) : Color.clear),
                                    lineWidth: equipped ? 1.5 : 1.2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func packBadge(_ pack: BallPack, owned: Bool, equipped: Bool) -> some View {
        if equipped {
            Text("EQUIPPED")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(1.0)
                .foregroundStyle(.black)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color.white))
        } else if owned {
            Text("OWNED — TAP TO EQUIP")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(Color(white: 0.85))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color(white: 0.22)))
        } else {
            let affordable = gameState.coinBalance >= pack.price(in: gameState)
            HStack(spacing: 4) {
                CoinIcon(size: 13)
                Text("\(pack.price(in: gameState))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(affordable ? .white : Color(white: 0.45))
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(
                Capsule().fill(affordable ? Color(red: 0.20, green: 0.78, blue: 0.38).opacity(0.85)
                                          : Color(white: 0.22))
            )
        }
    }

    private func handlePackTap(_ pack: BallPack, owned: Bool, equipped: Bool) {
        if equipped { return }
        if owned {
            gameState.equipPack(pack)
            AnalyticsClient.shared.track(
                "pack_equipped",
                properties: ["pack": .string(pack.id)]
            )
            return
        }
        let cost = pack.price(in: gameState)
        guard gameState.coinBalance >= cost else {
            alertMessage = "You need \(cost - gameState.coinBalance) more coins for the \(pack.displayName) pack.\n\nEarn coins by playing levels and collecting pickups, or buy a coin pack."
            showAlert = true
            return
        }
        if gameState.purchasePack(pack) {
            AnalyticsClient.shared.track(
                "pack_purchased",
                properties: [
                    "pack":  .string(pack.id),
                    "price": .int(cost),
                    "items": .int(pack.itemCount),
                ]
            )
            gameState.equipPack(pack)
            AnalyticsClient.shared.track(
                "pack_equipped",
                properties: [
                    "pack":           .string(pack.id),
                    "after_purchase": .bool(true),
                ]
            )
        }
    }

    private func musicPreview(_ track: MusicTrack) -> some View {
        Image(systemName: track == .none ? "speaker.slash.fill" : "music.note")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: track == .none
                        ? [Color(white: 0.35), Color(white: 0.20)]
                        : [Color(red: 0.45, green: 0.65, blue: 1.00),
                           Color(red: 0.25, green: 0.40, blue: 0.85)],
                    startPoint: .top, endPoint: .bottom
                )
            )
    }

    // (Coin glyph rendering moved to the shared CoinIcon view in
    // BallGameView.swift — every screen uses the same paw-print
    // minted-coin graphic now.)
}

#Preview {
    NavigationStack {
        CosmeticShopView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
