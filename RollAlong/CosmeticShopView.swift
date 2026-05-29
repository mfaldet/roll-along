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
    case ball, goal, trail, background, music
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .ball:       return "circle.fill"
        case .goal:       return "sparkles"
        case .trail:      return "scribble.variable"
        case .background: return "rectangle.fill.on.rectangle.fill"
        case .music:      return "music.note"
        }
    }
    var displayName: String {
        switch self {
        case .ball:       return "Ball"
        case .goal:       return "Goal"
        case .trail:      return "Trail"
        case .background: return "Theme"
        case .music:      return "Music"
        }
    }
}

struct CosmeticShopView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator

    @State private var category: ShopCategory = .ball
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
                Circle()
                    .fill(Self.coinGradient)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.black.opacity(0.30), lineWidth: 0.6))
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
        case .ball:
            categoryGrid(items: BallSkin.allCases)
        case .goal:
            categoryGrid(items: GoalSkin.allCases)
        case .trail:
            categoryGrid(items: TrailColor.allCases)
        case .background:
            categoryGrid(items: BackgroundTheme.allCases)
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
                    Circle()
                        .fill(Self.coinGradient)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color.black.opacity(0.30), lineWidth: 0.5))
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
        case let s as BallSkin:        gameState.activeSkin = s
        case let g as GoalSkin:        gameState.equippedGoal = g
        case let t as TrailColor:      gameState.equippedTrail = t
        case let b as BackgroundTheme: gameState.equippedBackground = b
        case let m as MusicTrack:      gameState.equippedMusic = m
        default: break
        }
    }

    private func isEquipped<Item: CosmeticItem>(_ item: Item) -> Bool {
        switch item {
        case let s as BallSkin:        return s == gameState.activeSkin
        case let g as GoalSkin:        return g == gameState.equippedGoal
        case let t as TrailColor:      return t == gameState.equippedTrail
        case let b as BackgroundTheme: return b == gameState.equippedBackground
        case let m as MusicTrack:      return m == gameState.equippedMusic
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
        case let s as BallSkin:        ballPreview(s)
        case let g as GoalSkin:        goalPreview(g)
        case let t as TrailColor:      trailPreview(t)
        case let b as BackgroundTheme: backgroundPreview(b)
        case let m as MusicTrack:      musicPreview(m)
        default: EmptyView()
        }
    }

    private func ballPreview(_ skin: BallSkin) -> some View {
        Circle()
            .fill(skin.gradient(endRadius: 35))
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.6))
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

    private func backgroundPreview(_ bg: BackgroundTheme) -> some View {
        let t = Theme.for(bg)
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(t.floorColor)
            // Tiny floating "hole" to show contrast
            RoundedRectangle(cornerRadius: 3)
                .fill(t.holeColor)
                .frame(width: 28, height: 16)
                .offset(x: 0, y: -2)
        }
        .frame(width: 90, height: 60)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.25), lineWidth: 0.6)
        )
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

    // MARK: - Constants

    private static let coinGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.88, blue: 0.40),
            Color(red: 0.93, green: 0.65, blue: 0.10),
        ],
        startPoint: .top, endPoint: .bottom
    )
}

#Preview {
    NavigationStack {
        CosmeticShopView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
