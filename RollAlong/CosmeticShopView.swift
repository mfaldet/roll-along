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
///   • `.shop`    — a curated front: the hourly-rotating featured bundle + a
///                  few odds-and-ends cosmetics.  The ONLY place to buy.
///   • `.catalog` — the full browsable grid (reached from the Shop).  Browse +
///                  equip-owned only; purchasing happens in the Shop.
enum ShopMode { case shop, catalog }

/// Measures the collection popup's cosmetic-list height so the diorama beside it
/// can match (list shows the whole set, no inner scroll).
private struct DetailListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Payload for the Catalog "where to buy" popup — shown when the player taps an
/// unowned individual cosmetic (which isn't sold directly in the Catalog).
private struct CatalogPurchaseInfo: Identifiable {
    let id = UUID()
    let name: String
    let bundles: [String]     // collections that include this item (may be empty)
    let preview: AnyView      // the cosmetic's own preview, used as the card hero
}

/// Catalog "Collections" filter — derived from each bundle's existing data (its
/// limited-time window + ball count), so no per-bundle tagging is required.
private enum BundleFilter: String, CaseIterable, Identifiable {
    case all, seasonal, space, nature, sports, nightlife, luxe, fire, mystic, sweet, art
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       return "All Collections"
        case .seasonal:  return "Seasonal & Holiday"
        case .space:     return "Space"
        case .nature:    return "Nature"
        case .sports:    return "Sports"
        case .nightlife: return "Nightlife"
        case .luxe:      return "Luxe"
        case .fire:      return "Fire"
        case .mystic:    return "Mystic"
        case .sweet:     return "Sweet"
        case .art:       return "Art"
        }
    }
    var icon: String {
        switch self {
        case .all:       return "square.stack.3d.up.fill"
        case .seasonal:  return "gift.fill"
        case .space:     return "moon.stars.fill"
        case .nature:    return "leaf.fill"
        case .sports:    return "sportscourt.fill"
        case .nightlife: return "music.note"
        case .luxe:      return "crown.fill"
        case .fire:      return "flame.fill"
        case .mystic:    return "wand.and.stars"
        case .sweet:     return "birthday.cake.fill"
        case .art:       return "paintbrush.fill"
        }
    }

    /// "Seasonal & Holiday" derives from the limited-time window; the themed
    /// categories come from `themeMap` (keyed by bundle id, so adding a category
    /// never means editing the bundle initializers).  A limited-time bundle also
    /// carries a theme, so it shows under both its theme and Seasonal & Holiday.
    func matches(_ b: CosmeticBundle) -> Bool {
        switch self {
        case .all:      return true
        case .seasonal: return b.isLimitedTime
        default:        return BundleFilter.themeMap[b.id] == self
        }
    }

    private static let themeMap: [String: BundleFilter] = {
        var m: [String: BundleFilter] = [:]
        func tag(_ t: BundleFilter, _ ids: [String]) { ids.forEach { m[$0] = t } }
        tag(.space,     ["planets", "space-travel", "cosmos", "eclipse", "aurora"])
        tag(.nature,    ["winter", "nature", "ocean", "bloom", "zen-garden", "aquarium",
                         "dune", "abyssal-depths", "summer-2026", "winter-2026",
                         "stpatricks-2027", "spring-2027", "harvest-2026", "earthday-2027"])
        tag(.sports,    ["golf", "soccer", "full-court", "billiards-hall", "champion",
                         "sports-balls"])
        tag(.nightlife, ["nightclub", "arcade", "neon", "midnight-carnival", "lava-lamp",
                         "plasma-globe", "neon-city", "clockwork", "newyear-2027",
                         "july4-2026", "mardigras-2027", "pride-2027", "oktoberfest-2026"])
        tag(.luxe,      ["velvet-night", "golden-hour", "midas", "diamond",
                         "high-roller", "quicksilver"])
        tag(.fire,      ["hellfire", "citrus", "lava-flow", "magma-core"])
        tag(.mystic,    ["heavens", "noir", "realistic-marble", "glass-marbles", "tempest",
                         "haunted", "ancient-temple", "crystal-cavern", "oracle", "geode",
                         "halloween-2026", "muertos-2026", "lunar-2027"])
        tag(.sweet,     ["pastel", "candyland", "valentines-2027"])
        tag(.art,       ["paper-world", "sketchbook", "cathedral", "backtoschool-2026"])
        return m
    }()
}

/// One row in the collection detail popup — a single cosmetic from the bundle,
/// shown the way the loadout lists equipped items (preview + category + name).
private struct BundleItemRow: Identifiable {
    let id = UUID()
    let category: String
    let name: String
    let owned: Bool
    let preview: AnyView
}

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
    /// Non-nil while the Catalog "where to buy" popup is showing (tap an unowned
    /// individual cosmetic).  Replaces the old coin-shortfall "Heads up" alert.
    @State private var catalogInfo: CatalogPurchaseInfo? = nil
    /// Catalog → Collections type filter (the dropdown that replaced the
    /// "ALL COLLECTIONS" header).
    @State private var bundleFilter: BundleFilter = .all
    /// Non-nil while the collection detail popup is open (tap a collection card).
    @State private var detailBundle: CosmeticBundle? = nil
    /// Measured height of the popup's cosmetic list, so the diorama beside it
    /// can match — the whole set stays visible with no inner scroll.
    @State private var detailListHeight: CGFloat = 0

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

            // Catalog "where to buy" popup — replaces the old Heads-up alert for
            // tapping an unowned individual cosmetic.  Tap anywhere to close.
            if let info = catalogInfo {
                catalogPurchasePopup(info)
            }

            // Collection detail popup — opened by tapping a collection card.
            if let bundle = detailBundle {
                collectionDetailPopup(bundle)
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
        .onAppear {
            // Viewing the Shop (not the Catalog) resets the "shop fresh" alert:
            // re-arm it for the next rotation boundary.
            if mode == .shop { gameState.recordShopViewed() }
        }
    }

    // MARK: - Catalog "where to buy" popup

    /// Tapping an unowned individual cosmetic in the Catalog can't buy it (they're
    /// only sold in the Shop, or by buying a Collection).  This card makes that
    /// obvious at a glance and points to the two routes.  Tap anywhere to close.
    private func catalogPurchasePopup(_ info: CatalogPurchaseInfo) -> some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()

            VStack(spacing: 16) {
                // Hero — the cosmetic itself.
                info.preview
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 5) {
                    Text(info.name)
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Not sold individually in the Catalog —\nhere's where to unlock it:")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.62))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    purchaseRouteRow(icon: "bag.fill",
                                     tint: Color(red: 0.34, green: 0.66, blue: 1.00),
                                     title: "Buy it in the Shop",
                                     subtitle: "Cosmetics rotate through the Shop's picks")
                    if !info.bundles.isEmpty {
                        purchaseRouteRow(icon: "square.stack.3d.up.fill",
                                         tint: Color(red: 1.00, green: 0.80, blue: 0.34),
                                         title: "Or unlock the Collection",
                                         subtitle: collectionRouteSubtitle(info.bundles))
                    }
                }

                Text("Tap anywhere to close")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.45))
            }
            .padding(24)
            .frame(maxWidth: 330)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color(white: 0.13))
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.55), radius: 26, y: 12)
            .padding(.horizontal, 28)
        }
        // Tap anywhere — dim OR card — closes the popup.
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { catalogInfo = nil } }
        .transition(.opacity)
    }

    private func purchaseRouteRow(icon: String, tint: Color,
                                  title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.10)))
    }

    private func collectionRouteSubtitle(_ bundles: [String]) -> String {
        let shown = bundles.prefix(2).joined(separator: ", ")
        let more  = bundles.count > 2 ? " +\(bundles.count - 2) more" : ""
        let noun  = bundles.count > 1 ? "collections" : "collection"
        return "Part of the \(shown)\(more) \(noun)"
    }

    // MARK: - Shop front (curated, rotating storefront)

    private var shopFront: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ── Top nav: Locker + Catalog, side by side ───────────────
                HStack(spacing: 12) {
                    topNavButton(title: "Locker",
                                 subtitle: "Equip what you own",
                                 icon: "tshirt.fill",
                                 colors: [Color(red: 0.10, green: 0.62, blue: 0.55),
                                          Color(red: 0.16, green: 0.44, blue: 0.72)],
                                 route: .locker)
                    topNavButton(title: "Catalog",
                                 subtitle: "Browse everything",
                                 icon: "square.grid.2x2.fill",
                                 colors: [Color(red: 0.30, green: 0.42, blue: 0.95),
                                          Color(red: 0.56, green: 0.30, blue: 0.95)],
                                 route: .catalog)
                }

                // ── Big enticing title + rotation countdown ───────────────
                VStack(alignment: .leading, spacing: 5) {
                    Text("Limited Deals & Rare Finds")
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(red: 1.00, green: 0.86, blue: 0.42),
                                     Color(red: 1.00, green: 0.55, blue: 0.30)],
                            startPoint: .leading, endPoint: .trailing))
                        .fixedSize(horizontal: false, vertical: true)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12, weight: .bold))
                            Text("New shop items in \(ShopRotation.countdown(at: ctx.date))")
                                .monospacedDigit()
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.55))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // ── Bundle — one random featured collection ───────────────
                if let bundle = ShopRotation.featuredBundle() {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("FEATURED BUNDLE")
                        collectionCard(bundle, isFeatured: true)
                    }
                }

                // ── One section per cosmetic category: three picks each
                //    (two Standard + one better), in the requested order. ───
                shopPicksSection("BALLS",      items: ShopRotation.featuredBalls())
                shopPicksSection("TRAILS",     items: ShopRotation.featuredTrails())
                shopPicksSection("FLOORS",     items: ShopRotation.featuredFloors())
                shopPicksSection("PITS",       items: ShopRotation.featuredPits())
                shopPicksSection("BOUNDARIES", items: ShopRotation.featuredBoundaries())
                shopPicksSection("GOALS",      items: ShopRotation.featuredGoals())
                shopPicksSection("MUSIC",      items: ShopRotation.featuredMusicSet())
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
    }

    /// A compact gradient nav button (Locker / Catalog) for the top of the Shop.
    private func topNavButton(title: String, subtitle: String, icon: String,
                              colors: [Color], route: HomeRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.white.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: colors,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// One Shop category section: a label over a 3-up row of buyable item cells.
    private func shopPicksSection<Item: CosmeticItem>(_ title: String,
                                                      items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(title)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(items, id: \.id) { item in
                    itemCell(item: item)
                }
            }
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
                Text(GameState.coinPillText(gameState.coinBalance))
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

    // MARK: - Category filter (persistent square tiles)

    /// A non-scrolling row of square category tiles.  It lives ABOVE the
    /// ScrollView (see `body`), so every cosmetic type stays visible and one tap
    /// away while the player scrolls the Catalog — no horizontal swiping to reach
    /// a filter, and the bar never scrolls off the top.
    private var tabBar: some View {
        // Two rows of four filter tiles (8 categories) instead of one tight row
        // of eight — each tile is ~twice as wide, so the icon + label are bigger
        // and easier to read.  Still no scrolling; same filter behaviour.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                  spacing: 6) {
            ForEach(ShopCategory.allCases) { cat in
                tabButton(cat)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func tabButton(_ cat: ShopCategory) -> some View {
        let isActive = category == cat
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { category = cat }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(cat.displayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(isActive ? .black : Color(white: 0.82))
            .frame(maxWidth: .infinity)   // equal-width tiles fill each column
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(isActive ? Color.white : Color(white: 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(isActive ? Color.clear : Color(white: 0.24), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cat.displayName)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
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
        // Sort every Catalog page by rarity — "iconic" (free starter) up top,
        // then Standard, Rare, Epic, Legendary.  Pairing the tier rank with the
        // original index keeps the sort stable, so items within a tier hold their
        // natural catalogue order.
        let sorted = items.enumerated()
            .sorted { ($0.element.tier.sortRank, $0.offset) < ($1.element.tier.sortRank, $1.offset) }
            .map(\.element)
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(sorted, id: \.id) { item in
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
            // acquisition via the bundle or challenge track).
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
        // In the Catalog the art, name, and collection caption stay fully visible
        // even for unowned items — only the price pill reads as greyed (you buy
        // in the Shop / a Collection, not here).  Equipped items keep the green
        // status border.
        let border: Color? = equipped ? Color(red: 0.28, green: 0.85, blue: 0.45) : nil
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
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(border ?? .clear, lineWidth: border == nil ? 0 : 2)
                    )
            )
            // Rarity corner tab — a colored triangle + white star in the top-right.
            .overlay(alignment: .topTrailing) {
                RarityCornerTab(colors: item.rarityGemColors, side: 40, corner: 16)
            }
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
                Text("OWNED")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(1.0)
                    .foregroundStyle(Color(white: 0.85))
                    .padding(.horizontal, 9)
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
                .background(costPillBackground(inCatalog: inCatalog, affordable: canAfford(item)))
                // Catalog: the price is informational only — grey the pill so it's
                // clear the item isn't bought here.
                .opacity(inCatalog ? 0.5 : 1.0)
            }
        }
    }

    /// Background for the price pill.  The affordable (Shop) state used to be a
    /// solid bright-green fill that washed out the white coin amount; it's now a
    /// muted top-to-bottom opacity gradient over the dark card, so the lettering
    /// reads clearly while still signalling "you can buy this".
    @ViewBuilder
    private func costPillBackground(inCatalog: Bool, affordable: Bool) -> some View {
        if inCatalog {
            Capsule().fill(Color(white: 0.20))
        } else if affordable {
            Capsule()
                .fill(LinearGradient(
                    colors: [Color(red: 0.22, green: 0.74, blue: 0.42).opacity(0.55),
                             Color(red: 0.12, green: 0.42, blue: 0.24).opacity(0.28)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(
                    Capsule().stroke(Color(red: 0.32, green: 0.84, blue: 0.52).opacity(0.45),
                                     lineWidth: 0.8))
        } else {
            Capsule().fill(Color(white: 0.22))
        }
    }

    private func accessibilityLabel<Item: CosmeticItem>(item: Item, owned: Bool, equipped: Bool) -> String {
        let category = String(describing: type(of: item))
        let rarity = item.showsRarityBadge ? ", \(item.rarityLabel)" : ""
        if equipped { return "\(item.displayName) \(category)\(rarity), equipped." }
        if owned    { return "\(item.displayName) \(category)\(rarity), owned. Double-tap to equip." }
        if mode == .catalog {
            return "\(item.displayName) \(category)\(rarity), \(item.coinCost) coins. Sold as part of a bundle — double-tap for details."
        }
        return "\(item.displayName) \(category)\(rarity), \(item.coinCost) coins. Double-tap to buy."
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
                // Individual cosmetics aren't bought in the Catalog — show a
                // custom "where to buy" card (Shop / Collections) instead of the
                // coin-shortfall alert.
                let names = CosmeticBundle.bundles(containing: item).map(\.displayName)
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    catalogInfo = CatalogPurchaseInfo(name: item.displayName,
                                                      bundles: names,
                                                      preview: AnyView(preview(for: item)))
                }
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

    /// Aurora swatch gradient — teal-green → cyan → violet, the bundle palette.
    /// Used to give the deep-night Aurora floor/pit a luminous shop preview.
    private var auroraSwatchGradient: LinearGradient {
        LinearGradient(colors: [
            Color(red: 0.18, green: 0.88, blue: 0.66).opacity(0.85),
            Color(red: 0.23, green: 0.78, blue: 0.95).opacity(0.65),
            Color(red: 0.60, green: 0.42, blue: 1.00).opacity(0.80),
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func floorPreview(_ floor: Floor) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(floor.color)
            .frame(width: 90, height: 60)
            .overlay {
                if floor == .aurora {
                    auroraSwatchGradient
                        .blendMode(.plusLighter)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
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
                .overlay {
                    if pit == .aurora {
                        auroraSwatchGradient.opacity(0.7)
                            .blendMode(.plusLighter)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
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

    @ViewBuilder
    private var collectionsView: some View {
        // The Catalog lists every collection plainly — no "limited time"
        // countdown and no "featured this week" spotlight.  Browsing is the
        // point; a bundle is the one thing you can actually buy here.  (Seasonal
        // bundles still appear only while their window is open, so they can't be
        // bought out of season.)
        // Filtered by the chosen collection type, then sorted by full price
        // (simplest/cheapest up top), alphabetically for equal-priced bundles.
        // Seasonal bundles still appear only while their window is open.
        let bundles = CosmeticBundle.catalogue
            .filter { !$0.isLimitedTime || $0.isAvailable }
            .filter { bundleFilter.matches($0) }
            .sorted {
                $0.fullPrice() != $1.fullPrice()
                    ? $0.fullPrice() < $1.fullPrice()
                    : $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        LazyVStack(alignment: .leading, spacing: 0) {
            collectionFilterMenu
                .padding(.bottom, 10)
            if bundles.isEmpty {
                Text("No collections match this filter.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                ForEach(bundles) { bundle in
                    collectionCard(bundle, isFeatured: false)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    /// Dropdown that replaced the old "ALL COLLECTIONS" header — filters the
    /// Collections list by type (Seasonal / Holiday / Ball Packs / Evergreen).
    private var collectionFilterMenu: some View {
        Menu {
            Picker("Filter collections", selection: $bundleFilter) {
                ForEach(BundleFilter.allCases) { f in
                    Label(f.label, systemImage: f.icon).tag(f)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: bundleFilter.icon)
                    .font(.system(size: 12, weight: .bold))
                Text(bundleFilter.label.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .kerning(1.2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(Color(white: 0.16))
                    .overlay(Capsule().stroke(Color(white: 0.26), lineWidth: 0.8))
            )
        }
        .buttonStyle(.plain)
    }

    private func collectionCard(_ bundle: CosmeticBundle, isFeatured: Bool) -> some View {
        let bundleOwned = gameState.completedBundleIDs.contains(bundle.id)
        let owned       = ownedCount(in: bundle)
        let total       = bundle.itemCount
        let isShop      = mode == .shop
        let discount    = ShopRotation.featuredDiscount()
        // Shop's featured bundle is discounted off the prorated price.
        let discounted  = isShop && bundleCost(bundle) < bundle.proratedPrice(in: gameState)

        let cost      = bundleCost(bundle)
        let prorated  = bundle.proratedPrice(in: gameState)
        let canAfford = gameState.coinBalance >= cost

        let card = VStack(alignment: .leading, spacing: 10) {
            // ── Title row ────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    let showLimited = isShop && bundle.isLimitedTime && bundle.isAvailable
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
                    Text(bundle.displayName)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(bundle.tagline)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.58))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                // % OFF sticker on a discounted (Shop) bundle; in the Catalog an
                // OWNED tag for a complete set; otherwise the X/Y counter.
                if discounted {
                    discountSticker(discount)
                } else if bundleOwned && !isShop {
                    ownedTag
                } else if !bundleOwned {
                    collectionProgressBadge(owned: owned, total: total)
                }
            }
            .padding(.trailing, 40)

            // ── 6-slot item row ──────────────────────────────────────────
            collectionSlotRow(bundle)

            // ── Action button — SHOP ONLY ────────────────────────────────
            // The Shop keeps the large inline "Buy the Collection" / "Complete
            // the Set" CTA.  The Catalog has no inline button — tapping the card
            // opens the detail popup instead (handled below).
            if isShop {
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
                        handleBundleTap(bundle, owned: false)
                    } label: {
                        HStack(spacing: 6) {
                            Text(owned > 0 ? "Complete the Set" : "Buy the Collection")
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
                                         ? Color(red: 0.30, green: 0.86, blue: 0.56)   // teal-green "complete set"
                                         : Color.white)                                  // white "buy collection"
                                      : Color(white: 0.20))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(white: isFeatured ? 0.14 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(borderColor(bundle: bundle), lineWidth: 1.2)
                )
        )
        // Rarity corner tab — colored triangle + white star, top-right.
        .overlay(alignment: .topTrailing) {
            RarityCornerTab(colors: bundle.rarity.gemColors, side: 44, corner: 18)
        }

        // Catalog: the whole card is a button that opens the detail popup.  Shop:
        // the card stays a plain container so its inline button owns the taps.
        return Group {
            if isShop {
                card
            } else {
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { detailBundle = bundle }
                } label: { card }
                .buttonStyle(.plain)
            }
        }
    }

    /// Small green "owned" tag shown where the X/Y progress badge sits, for a
    /// fully-owned collection.
    private var ownedTag: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .bold))
            Text("OWNED").font(.system(size: 10, weight: .black, design: .rounded)).tracking(0.5)
        }
        .foregroundStyle(Color(red: 0.24, green: 0.82, blue: 0.48))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color(red: 0.24, green: 0.82, blue: 0.48).opacity(0.16)))
    }

    // MARK: - Collection detail popup

    private func dismissDetail() {
        withAnimation(.easeOut(duration: 0.2)) { detailBundle = nil }
    }

    /// Opened by tapping a collection card.  Demonstrates every cosmetic in the
    /// set (the way the loadout lists equipped items), with one purchase button
    /// and a close option (X or tap the backdrop).
    private func collectionDetailPopup(_ bundle: CosmeticBundle) -> some View {
        let bundleOwned = gameState.completedBundleIDs.contains(bundle.id)
        let owned       = ownedCount(in: bundle)
        let cost        = bundleCost(bundle)
        let prorated    = bundle.proratedPrice(in: gameState)
        let discounted  = mode == .shop && cost < prorated
        let canAfford   = gameState.coinBalance >= cost

        return ZStack {
            Color.black.opacity(0.64).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissDetail() }

            VStack(spacing: 14) {
                // Header — name + tagline, with an X to close.
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bundle.displayName)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(bundle.tagline)
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(white: 0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button { dismissDetail() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(white: 0.72))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(white: 0.18)))
                    }
                    .buttonStyle(.plain)
                }

                // Every cosmetic in the set (left) beside a live diorama of the
                // whole loadout in action (right) — the same "list + illustrate"
                // format as the profile's My Loadout.  The list shows the full
                // set with no inner scroll; the diorama matches its height.
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 8) {
                        ForEach(bundleDetailRows(bundle)) { collectionItemRow($0) }
                    }
                    .frame(maxWidth: .infinity)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: DetailListHeightKey.self,
                                               value: g.size.height)
                    })

                    LoadoutDiorama(loadout: Loadout(bundle: bundle))
                        .frame(width: 126, height: max(180, detailListHeight))
                }
                .onPreferenceChange(DetailListHeightKey.self) { detailListHeight = $0 }

                // Footer — purchase, or a complete badge if already owned.
                if bundleOwned {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 15, weight: .bold))
                        Text("Collection Complete")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(red: 0.24, green: 0.82, blue: 0.48))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.10)))
                } else {
                    Button {
                        handleBundleTap(bundle, owned: false)
                        // Close on a successful buy; a shortfall keeps it open
                        // (the shortfall alert shows over the popup).
                        if gameState.ownedBundles.contains(bundle.id) { dismissDetail() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(owned > 0 ? "Complete the Set" : "Get Bundle")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(canAfford ? .black : Color(white: 0.5))
                            Spacer()
                            HStack(spacing: 5) {
                                if discounted {
                                    Text("\(prorated)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .strikethrough(true, color: (canAfford ? Color.black : Color(white: 0.45)).opacity(0.55))
                                        .foregroundStyle((canAfford ? Color.black : Color(white: 0.45)).opacity(0.55))
                                }
                                CoinIcon(size: 14)
                                Text("\(cost)")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(canAfford ? .black : Color(white: 0.45))
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(canAfford
                                      ? (owned > 0 ? Color(red: 0.30, green: 0.86, blue: 0.56) : Color.white)
                                      : Color(white: 0.20))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color(white: 0.12))
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.55), radius: 28, y: 14)
            .padding(.horizontal, 22)
        }
        .transition(.opacity)
    }

    /// The bundle's cosmetics as loadout-style rows (every item in every category).
    private func bundleDetailRows(_ b: CosmeticBundle) -> [BundleItemRow] {
        var rows: [BundleItemRow] = []
        for x in b.balls {
            rows.append(BundleItemRow(category: "Ball", name: x.displayName,
                                      owned: gameState.isOwned(x),
                                      preview: AnyView(BallSkinView(skin: x, diameter: 30))))
        }
        for x in b.goals {
            rows.append(BundleItemRow(category: "Goal", name: x.displayName,
                                      owned: gameState.isOwned(x),
                                      preview: AnyView(Circle().fill(GoalSkin.previewGradient(for: x))
                                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                                        .frame(width: 28, height: 28))))
        }
        for x in b.trails {
            rows.append(BundleItemRow(category: "Trail", name: x.displayName,
                                      owned: gameState.isOwned(x),
                                      preview: AnyView(trailSwatch(x))))
        }
        for x in b.floors {
            rows.append(BundleItemRow(category: "Floor", name: x.displayName,
                                      owned: gameState.isOwned(x),
                                      preview: AnyView(RoundedRectangle(cornerRadius: 6).fill(x.color)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.2), lineWidth: 0.6))
                                        .frame(width: 30, height: 24))))
        }
        for x in b.pits {
            rows.append(BundleItemRow(category: "Pit", name: x.displayName,
                                      owned: gameState.isOwned(x),
                                      preview: AnyView(pitSwatch(x))))
        }
        for x in b.music {
            rows.append(BundleItemRow(category: "Music", name: x.displayName,
                                      owned: gameState.isOwned(x),
                                      preview: AnyView(musicSwatch(x))))
        }
        return rows
    }

    private func collectionItemRow(_ row: BundleItemRow) -> some View {
        HStack(spacing: 12) {
            row.preview
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.category.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.5)).tracking(1)
                Text(row.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if row.owned {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    Text("Owned").font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color(red: 0.24, green: 0.82, blue: 0.48))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.09)))
    }

    @ViewBuilder private func trailSwatch(_ trail: TrailColor) -> some View {
        Canvas { ctx, size in
            var p = Path()
            p.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.85))
            p.addLine(to: CGPoint(x: size.width * 0.88, y: size.height * 0.15))
            ctx.stroke(p, with: .color(trail == .none ? Color(white: 0.30) : trail.color),
                       style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }
    @ViewBuilder private func pitSwatch(_ pit: Pit) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.20))
            RoundedRectangle(cornerRadius: 3).fill(pit.color).frame(width: 16, height: 9)
        }
    }
    @ViewBuilder private func musicSwatch(_ track: MusicTrack) -> some View {
        Image(systemName: track == .none ? "speaker.slash.fill" : "music.note")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(LinearGradient(
                colors: [Color(red: 0.45, green: 0.65, blue: 1.00),
                         Color(red: 0.25, green: 0.40, blue: 0.85)],
                startPoint: .top, endPoint: .bottom))
    }

    /// Border color for a collection card.  The gold "complete / featured" and
    /// blue "buyable now" status borders were removed for a cleaner card; only
    /// the seasonal "limited time" accent remains (Shop only).
    private func borderColor(bundle: CosmeticBundle) -> Color {
        if mode == .shop && bundle.isLimitedTime && bundle.isAvailable {
            return limitedTimeColor(for: bundle).opacity(0.50)
        }
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

    /// Big "% OFF" sticker for the Shop's discounted featured bundle — sits in
    /// the card's top-right corner in place of the progress counter.  Tinted by
    /// the discount tier (deeper deals run hotter), dark text for contrast, and
    /// tilted a touch so it reads as a slapped-on price sticker.
    private func discountSticker(_ discount: BundleDiscount) -> some View {
        VStack(spacing: -2) {
            Text("\(discount.percent)%")
                .font(.system(size: 19, weight: .black, design: .rounded))
            Text("OFF")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .kerning(2)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [discount.color, discount.color.opacity(0.82)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: discount.color.opacity(0.55), radius: 5, y: 2)
        )
        .rotationEffect(.degrees(-6))
        .accessibilityLabel("\(discount.percent) percent off")
    }

    // ── 6-slot item row ──────────────────────────────────────────────────────

    private func collectionSlotRow(_ bundle: CosmeticBundle) -> some View {
        HStack(spacing: 6) {
            // Ball
            collectionSlot(label: "Ball",
                           isOwned: bundle.balls.first.map { gameState.isOwned($0) },
                           isEquipped: bundle.balls.first.map { isEquipped($0) } ?? false) {
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
                           isOwned: bundle.goals.first.map { gameState.isOwned($0) },
                           isEquipped: bundle.goals.first.map { isEquipped($0) } ?? false) {
                if let goal = bundle.goals.first {
                    Circle()
                        .fill(GoalSkin.previewGradient(for: goal))
                        .frame(width: 34, height: 34)
                }
            }
            // Trail
            collectionSlot(label: "Trail",
                           isOwned: bundle.trails.first.map { gameState.isOwned($0) },
                           isEquipped: bundle.trails.first.map { isEquipped($0) } ?? false) {
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
                           isOwned: bundle.floors.first.map { gameState.isOwned($0) },
                           isEquipped: bundle.floors.first.map { isEquipped($0) } ?? false) {
                if let floor = bundle.floors.first {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(floor.color)
                        .frame(width: 38, height: 26)
                }
            }
            // Pit
            collectionSlot(label: "Pit",
                           isOwned: bundle.pits.first.map { gameState.isOwned($0) },
                           isEquipped: bundle.pits.first.map { isEquipped($0) } ?? false) {
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
                           isOwned: bundle.music.first.map { gameState.isOwned($0) },
                           isEquipped: bundle.music.first.map { isEquipped($0) } ?? false) {
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
    /// bundle has no item in this category → dotted empty placeholder.
    /// `isOwned == false` → dimmed preview + lock icon.  `isOwned == true` →
    /// full-colour preview.  The green ring appears ONLY when the item is the one
    /// currently equipped (`isEquipped`), not merely owned.
    private func collectionSlot<Content: View>(
        label: String,
        isOwned: Bool?,
        isEquipped: Bool = false,
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
                                    : (isEquipped
                                       ? Color(red: 0.24, green: 0.82, blue: 0.48).opacity(0.85)
                                       : Color.clear),
                                style: isEmpty
                                    ? StrokeStyle(lineWidth: 1.0, dash: [3, 3])
                                    : StrokeStyle(lineWidth: isEquipped ? 2.0 : 1.2)
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
        // Auto-equip the new set so the purchase shows up instantly — the buyer
        // sees their new look right away instead of equipping each piece by hand.
        if let b = bundle.balls.first  { gameState.equipBall(b) }
        if let g = bundle.goals.first  { gameState.equippedGoal  = g }
        if let t = bundle.trails.first { gameState.equippedTrail = t }
        if let f = bundle.floors.first { gameState.equippedFloor = f }
        if let p = bundle.pits.first   { gameState.equippedPit   = p }
        if let m = bundle.music.first  { gameState.equippedMusic = m }
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
            Text("OWNED")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(1.0)
                .foregroundStyle(Color(white: 0.85))
                .padding(.horizontal, 9).padding(.vertical, 4)
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

/// The rarity marker used on Shop / Catalog cards: a colored right-triangle in
/// the top-right corner (the card's corner radius is rounded to match) with a
/// white star.  Color = the item/bundle's rarity gem ramp.  Replaces the inline
/// gem badge.  Not used in Locker / Loadout / Profile.
struct RarityCornerTab: View {
    let colors: [Color]            // rarity gem ramp (top-left → bottom-right)
    var side: CGFloat = 44
    var corner: CGFloat = 16

    var body: some View {
        ZStack {
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: side, y: 0))
                p.addLine(to: CGPoint(x: side, y: side))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: colors.isEmpty ? [Color(white: 0.5)] : colors,
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "star.fill")
                .font(.system(size: side * 0.30, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.28), radius: 0.5, y: 0.5)
                .position(x: side * 0.66, y: side * 0.34)
        }
        .frame(width: side, height: side)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 0, topTrailingRadius: corner))
        .allowsHitTesting(false)
    }
}

#Preview {
    NavigationStack {
        CosmeticShopView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
