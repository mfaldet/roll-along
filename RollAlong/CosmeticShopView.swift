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
    case collections, ball, goal, trail, floor, pit, music
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .collections: return "square.stack.3d.up.fill"
        case .ball:        return "circle.fill"
        case .goal:        return "sparkles"
        case .trail:       return "scribble.variable"
        case .floor:       return "square.fill.on.square.fill"
        case .pit:         return "circle.dotted"
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
        case .music:       return "Music"
        }
    }
}

struct CosmeticShopView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator

    @State private var category: ShopCategory = .collections
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var showBuyCoinsSheet: Bool = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                tabBar
                ScrollView {
                    grid
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                }
            }
        }
        .navigationTitle("Shop")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { nav.goHome() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Home")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.white)
                }
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
    }

    // MARK: - Header (coin balance)

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                CoinIcon(size: 22)
                Text("\(gameState.coinBalance)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(gameState.coinBalance)))
                    .animation(.easeInOut(duration: 0.4), value: gameState.coinBalance)
                Text("coins")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
            }
            Spacer()
            Button {
                showBuyCoinsSheet = true
                AnalyticsClient.shared.track("buy_coins_sheet_opened",
                                             properties: ["from": .string("shop_header")])
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Get more")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
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
            categoryGrid(items: TrailColor.allCases)
        case .floor:
            categoryGrid(items: Floor.allCases)
        case .pit:
            categoryGrid(items: Pit.allCases)
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
            // Bundle-exclusive balls (e.g. Pluto) are hidden from the
            // individual Ball grid — they're only obtainable via a bundle.
            categoryGrid(items: BallSkin.allCases.filter { !$0.isBundleExclusive })
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

                stateBadge(item: item, owned: owned, equipped: equipped)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(equipped ? Color.white.opacity(0.55) : Color.clear,
                                    lineWidth: 1.5)
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
                HStack(spacing: 4) {
                    CoinIcon(size: 13)
                    Text("\(item.coinCost)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(canAfford(item) ? .white : Color(white: 0.45))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(canAfford(item) ? Color(red: 0.20, green: 0.78, blue: 0.38).opacity(0.85)
                                              : Color(white: 0.22))
                )
            }
        }
    }

    private func accessibilityLabel<Item: CosmeticItem>(item: Item, owned: Bool, equipped: Bool) -> String {
        let category = String(describing: type(of: item))
        if equipped { return "\(item.displayName) \(category), equipped." }
        if owned    { return "\(item.displayName) \(category), owned. Double-tap to equip." }
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
        }
    }

    private func equip<Item: CosmeticItem>(_ item: Item) {
        switch item {
        case let s as BallSkin:   gameState.equipBall(s)
        case let g as GoalSkin:   gameState.equippedGoal = g
        case let t as TrailColor: gameState.equippedTrail = t
        case let f as Floor:      gameState.equippedFloor = f
        case let p as Pit:        gameState.equippedPit = p
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
        case let m as MusicTrack: musicPreview(m)
        default: EmptyView()
        }
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

    private func trailPreview(_ trail: TrailColor) -> some View {
        // A short streak in the trail's color, from lower-left to upper-right.
        Canvas { ctx, size in
            var path = Path()
            let pts = 14
            for i in 0..<pts {
                let t = Double(i) / Double(pts - 1)
                let x = size.width * CGFloat(0.15 + t * 0.7)
                let y = size.height * CGFloat(0.85 - t * 0.7)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else      { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            if trail == .rainbow {
                // Render rainbow as multiple short segments
                let segs = pts - 1
                for i in 0..<segs {
                    let t1 = Double(i) / Double(segs)
                    let t2 = Double(i+1) / Double(segs)
                    let x1 = size.width * CGFloat(0.15 + t1 * 0.7)
                    let y1 = size.height * CGFloat(0.85 - t1 * 0.7)
                    let x2 = size.width * CGFloat(0.15 + t2 * 0.7)
                    let y2 = size.height * CGFloat(0.85 - t2 * 0.7)
                    var s = Path()
                    s.move(to: CGPoint(x: x1, y: y1))
                    s.addLine(to: CGPoint(x: x2, y: y2))
                    let hue = t1
                    ctx.stroke(s, with: .color(Color(hue: hue, saturation: 1.0, brightness: 1.0)),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            } else {
                ctx.stroke(path, with: .color(trail == .none ? Color(white: 0.30) : trail.color),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
        .padding(8)
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
        let bundleOwned = gameState.ownedBundles.contains(bundle.id)
        let owned       = ownedCount(in: bundle)
        let total       = bundle.itemCount
        let cost        = bundle.price(in: gameState)
        let canAfford   = gameState.coinBalance >= cost

        return VStack(alignment: .leading, spacing: 10) {
            // ── Title row ────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    // Chips row — ⭐ FEATURED and/or 🔥 LIMITED
                    let showFeatured = isFeatured
                    let showLimited  = bundle.isLimitedTime && bundle.isAvailable
                    if showFeatured || showLimited {
                        HStack(spacing: 6) {
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
                        HStack(spacing: 3) {
                            CoinIcon(size: 13)
                            Text("\(cost)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(canAfford ? .black : Color(white: 0.45))
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
        if bundleOwned                                       { return Color(red: 0.24, green: 0.82, blue: 0.48).opacity(0.35) }
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

    private func canAffordBundle(_ bundle: CosmeticBundle) -> Bool {
        gameState.coinBalance >= bundle.price(in: gameState)
    }

    private func handleBundleTap(_ bundle: CosmeticBundle, owned: Bool) {
        if owned { return }
        let cost = bundle.price(in: gameState)
        guard gameState.coinBalance >= cost else {
            alertMessage = "You need \(cost - gameState.coinBalance) more coins for the \(bundle.displayName) bundle.\n\nEarn coins by playing levels and collecting pickups, or buy a coin pack."
            showAlert = true
            return
        }
        _ = gameState.spendCoins(cost)
        bundle.grantContents(to: gameState)
        gameState.ownedBundles.insert(bundle.id)
        AnalyticsClient.shared.track(
            "bundle_purchased",
            properties: [
                "bundle":  .string(bundle.id),
                "price":   .int(cost),
                "items":   .int(bundle.itemCount),
            ]
        )
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
