import SwiftUI

// ---------------------------------------------------------------------------
// PurchaseSheets — the UI for buying lives, coins, and the unlimited
// subscription.  Used as .sheet(isPresented:) from the out-of-lives overlay
// and the cosmetic shop.
//
// Both sheets are TabView-free + scrollable so they fit on smaller phones
// without cramping.  Each product row uses StoreKitManager.displayPrice to
// show Apple's localised price string — if StoreKit hasn't loaded yet, we
// fall back to a hardcoded USD string so the UI is never empty.
// ---------------------------------------------------------------------------

// MARK: - Buy Lives Sheet

struct BuyLivesSheet: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var store:     StoreKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var purchaseError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        statusBlock
                        lifePackCards
                        Text("OR NEVER RUN OUT")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .kerning(1.5)
                            .foregroundStyle(Color(white: 0.45))
                            .padding(.top, 6)
                        diamondBallsCard
                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Get Lives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Restore") {
                        Task { await store.restore() }
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        // Open tall enough that the Diamond Balls offer is fully visible at
        // rest (medium clipped its bottom); still draggable to full height.
        .presentationDetents([.fraction(0.85), .large])
        .onChange(of: store.lastError) { _, err in purchaseError = err }
        .alert("Purchase Failed", isPresented: Binding(
            get: { purchaseError != nil },
            set: { _ in purchaseError = nil; store.clearLastError() }
        ), actions: { Button("OK", role: .cancel) {} },
        message: { Text(purchaseError ?? "") })
    }

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(0..<GameState.livesMax, id: \.self) { i in
                lifeMarble(filled: i < gameState.displayedLives)
            }
            Spacer()
            Text("\(gameState.displayedLives) / \(GameState.livesMax)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.75))
        }
        .padding(.bottom, 6)
    }

    /// One life as a glossy marble — the same highlight-dot-and-rim recipe as
    /// the home screen's lives pill (HomeView.marbleIcon), so lives read as
    /// the familiar red ball here too instead of a flat disc.  An empty slot
    /// is a hollow outline, also matching the pill.
    private func lifeMarble(filled: Bool) -> some View {
        let size: CGFloat = 18
        return ZStack {
            Circle()
                .stroke(Color(white: 0.40).opacity(0.7), lineWidth: 1.0)
                .frame(width: size, height: size)
            if filled {
                Circle()
                    .fill(Self.redLifeGradient)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.55))
                            .frame(width: size * 0.28, height: size * 0.28)
                            .offset(x: -size * 0.18, y: -size * 0.18)
                    )
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.40), lineWidth: 0.6)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 1.5, y: 1)
            }
        }
        .frame(width: size, height: size)
    }

    /// Live status + explanation block under the marble-row header.  Shows
    /// the next-life countdown when regen is active and the standing rule
    /// (1 life every 6 min, up to 10).  Hidden for unlimited subscribers
    /// — we tell them they're set instead.
    private var statusBlock: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            VStack(alignment: .leading, spacing: 6) {
                if gameState.unlimitedLives {
                    HStack(spacing: 6) {
                        Image(systemName: "infinity")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.00, green: 0.86, blue: 0.36),
                                        Color(red: 0.93, green: 0.65, blue: 0.10),
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        Text("You have unlimited lives.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(white: 0.85))
                    }
                } else {
                    if let countdown = gameState.timeToNextLife() {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 11))
                            Text("Next life in \(Self.formatCountdown(countdown))")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color(white: 0.78))
                    }
                    Text("You earn 1 life every 6 minutes, up to \(GameState.livesMax).")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
        }
    }

    private static func formatCountdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(ceil(seconds)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The headline one-time unlock — indestructible "Diamond Balls" = unlimited
    /// lives, forever.  Deliberately the shiniest thing in the sheet, shown last.
    @ViewBuilder
    private var diamondBallsCard: some View {
        let pid: StoreKitManager.ProductID = .unlimited
        let isOwned = gameState.unlimitedLives
        let inProgress = store.purchaseInProgress == pid
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                diamondBall(size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Diamond Balls")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Self.diamondGradient)
                    Text(isOwned ? "Active — indestructible, never run out."
                                 : "Indestructible.\nUnlimited lives, forever.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    Task { await store.purchase(pid) }
                } label: {
                    if inProgress {
                        ProgressView()
                            .progressViewStyle(.circular).tint(.black)
                            .frame(width: 56, height: 30)
                            .background(Capsule().fill(Color.white))
                    } else {
                        Text(isOwned ? "Owned" : store.displayPrice(for: pid, fallback: "$19.99"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(isOwned ? Color(white: 0.45) : .black)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(Capsule().fill(isOwned ? Color(white: 0.25) : Color.white))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isOwned || inProgress)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.10, green: 0.17, blue: 0.26),
                                     Color(red: 0.17, green: 0.24, blue: 0.36)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Self.diamondGradient, lineWidth: 1.5)
                    )
            )
            .shadow(color: Color(red: 0.50, green: 0.85, blue: 1.0).opacity(0.30), radius: 10, y: 2)

            // Exclusive cosmetic — obtainable ONLY through this purchase.
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Self.diamondGradient)
                Text("Also unlocks the exclusive Diamond ball skin — available only here.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
    }

    /// A super-shiny diamond marble — cool white→cyan, a bright specular, and a
    /// sparkle.  The visual identity for indestructible lives (was "golden ball").
    private func diamondBall(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white,
                                 Color(red: 0.74, green: 0.93, blue: 1.0),
                                 Color(red: 0.45, green: 0.72, blue: 0.96)],
                        center: .init(x: 0.34, y: 0.30),
                        startRadius: 1, endRadius: size * 0.75)
                )
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
            Circle().fill(Color.white.opacity(0.9))
                .frame(width: size * 0.26, height: size * 0.26)
                .offset(x: -size * 0.18, y: -size * 0.20)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.28, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.22, y: size * 0.20)
        }
        .shadow(color: Color(red: 0.50, green: 0.85, blue: 1.0).opacity(0.6), radius: 6)
    }

    private static let diamondGradient = LinearGradient(
        colors: [Color(red: 0.86, green: 0.96, blue: 1.0),
                 Color(red: 0.55, green: 0.80, blue: 1.0),
                 Color(red: 0.80, green: 0.92, blue: 1.0)],
        startPoint: .leading, endPoint: .trailing)

    private var lifePackCards: some View {
        VStack(spacing: 10) {
            productCard(
                pid: .livesPack1,
                title: "1 full reload",
                subtitle: "10 lives",
                buttonLabel: store.displayPrice(for: .livesPack1, fallback: "$0.99")
            )
            productCard(
                pid: .livesPack5,
                title: "6 full reloads",
                subtitle: "60 lives — best value casual",
                buttonLabel: store.displayPrice(for: .livesPack5, fallback: "$4.99")
            )
            productCard(
                pid: .livesPack10,
                title: "13 full reloads",
                subtitle: "130 lives — for chasers",
                buttonLabel: store.displayPrice(for: .livesPack10, fallback: "$9.99")
            )
        }
    }

    private func productCard(
        pid: StoreKitManager.ProductID,
        title: String,
        subtitle: String,
        badge: String? = nil,
        badgeColor: Color = .clear,
        buttonLabel: String,
        isDisabled: Bool = false,
        isLarge: Bool = false
    ) -> some View {
        let inProgress = store.purchaseInProgress == pid
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: isLarge ? 17 : 15,
                                       weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .kerning(0.8)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(badgeColor))
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.65))
            }
            Spacer()
            Button {
                Task { await store.purchase(pid) }
            } label: {
                if inProgress {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                        .frame(width: 56, height: 30)
                        .background(Capsule().fill(Color.white))
                } else {
                    Text(buttonLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isDisabled ? Color(white: 0.45) : .black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(isDisabled ? Color(white: 0.25) : .white)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isDisabled || inProgress)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isLarge ? Color(white: 0.16) : Color(white: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isLarge ? Color(red: 1.00, green: 0.84, blue: 0.30).opacity(0.5)
                                        : Color.clear,
                                lineWidth: 1.0)
                )
        )
    }

    private static let redLifeGradient = LinearGradient(
        colors: [Color(red: 1.00, green: 0.32, blue: 0.32),
                 Color(red: 0.78, green: 0.14, blue: 0.14)],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Buy Coins Sheet

struct BuyCoinsSheet: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var store:     StoreKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var purchaseError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        coinPackCards
                        Spacer().frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Get Coins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Restore") {
                        Task { await store.restore() }
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: store.lastError) { _, err in purchaseError = err }
        .alert("Purchase Failed", isPresented: Binding(
            get: { purchaseError != nil },
            set: { _ in purchaseError = nil; store.clearLastError() }
        ), actions: { Button("OK", role: .cancel) {} },
        message: { Text(purchaseError ?? "") })
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                CoinIcon(size: 22)
                Text("\(gameState.coinBalance)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("coins")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
            }
            Spacer()
            Text("Buy a pack below —\nor just play to earn more.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.trailing)
                .fixedSize()
        }
        .padding(.bottom, 6)
    }

    private var coinPackCards: some View {
        VStack(spacing: 10) {
            coinCard(pid: .coins100,  amount: 100)
            coinCard(pid: .coins600,  amount: 600)
            coinCard(pid: .coins1300, amount: 1300)
            coinCard(pid: .coins3000, amount: 3000)
        }
    }

    /// % more coins than buying the same spend as base 100-coin ($0.99) packs,
    /// rounded to the nearest 10%.  Nil for the base pack (it IS the base rate).
    private func coinBonus(_ pid: StoreKitManager.ProductID, amount: Int) -> String? {
        let baseRate = 100.0 / 0.99          // coins per dollar at the base pack
        let price: Double
        switch pid {
        case .coins600:  price = 4.99
        case .coins1300: price = 9.99
        case .coins3000: price = 19.99
        default:         return nil
        }
        let coinsIfBoughtAsBase = baseRate * price
        let pct = (Double(amount) / coinsIfBoughtAsBase - 1.0) * 100.0
        let rounded = Int((pct / 10.0).rounded()) * 10
        return rounded > 0 ? "+\(rounded)% coins" : nil
    }

    private func coinCard(
        pid: StoreKitManager.ProductID,
        amount: Int
    ) -> some View {
        let inProgress = store.purchaseInProgress == pid
        let bonus = coinBonus(pid, amount: amount)
        return HStack(alignment: .center, spacing: 12) {
            // Stacked coin icons — a small pile of the shared coin graphic.
            ZStack {
                ForEach(0..<3) { i in
                    CoinIcon(size: 24)
                        .offset(x: CGFloat(i) * 3, y: CGFloat(i) * -2)
                }
            }
            .frame(width: 34, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(amount.formatted(.number)) coins")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let bonus {
                    Text(bonus)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.40, green: 0.82, blue: 0.52))
                }
            }
            Spacer()

            Button {
                Task { await store.purchase(pid) }
            } label: {
                if inProgress {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                        .frame(width: 56, height: 30)
                        .background(Capsule().fill(Color.white))
                } else {
                    Text(store.displayPrice(for: pid, fallback: defaultPrice(for: pid)))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                }
            }
            .buttonStyle(.plain)
            .disabled(inProgress)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.13))
        )
    }

    private func defaultPrice(for pid: StoreKitManager.ProductID) -> String {
        switch pid {
        case .coins100, .livesPack1:   return "$0.99"
        case .coins600, .livesPack5:   return "$4.99"
        case .coins1300, .livesPack10: return "$9.99"
        case .coins3000, .unlimited:   return "$19.99"
        case .starterPack:             return "$1.99"
        case .summerBundle2026, .halloweenBundle2026, .winterBundle2026,
             .valentinesBundle2027, .stPatricksBundle2027,
             .newYearBundle2027, .springBundle2027:
                                       return "$2.99"
        }
    }

    // (Coin glyph rendering moved to the shared CoinIcon view in
    // BallGameView.swift — see PR notes.)
}

// MARK: - Starter Pack Sheet

/// One-time welcome offer: $1.99 → 500 coins + exclusive Aurora ball skin.
/// Presented automatically the first time the player's coin balance reaches 50,
/// and again on re-launch while the 48-hour window is still open.  After the
/// player purchases OR taps "No thanks (forever)", `gameState.starterPackClaimed`
/// is set to true and the sheet is never shown again.
struct StarterPackSheet: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var store:     StoreKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var purchaseError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                // Deep midnight gradient — echoes the Aurora ball's own palette.
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.16),
                        Color(red: 0.08, green: 0.04, blue: 0.18),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 28)

                        // ── Header badge ────────────────────────────────────
                        Text("✦  WELCOME GIFT  ✦")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .kerning(2.0)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.22, green: 0.95, blue: 0.65),
                                        Color(red: 0.62, green: 0.45, blue: 0.98),
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .padding(.bottom, 24)

                        // ── Aurora ball preview ─────────────────────────────
                        BallSkinView(skin: .aurora, diameter: 100)
                            .frame(width: 100, height: 100)
                            .shadow(color: Color(red: 0.22, green: 0.95, blue: 0.65).opacity(0.55),
                                    radius: 24, x: 0, y: 0)
                            .padding(.bottom, 20)

                        Text("Aurora")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Exclusive · Never sold separately")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.62, green: 0.45, blue: 0.98))
                            .padding(.bottom, 28)

                        // ── What you get ────────────────────────────────────
                        VStack(spacing: 10) {
                            rewardRow(icon: "sparkles", label: "Aurora ball skin",
                                      detail: "Exclusive to this offer")
                            rewardRow(icon: "circle.grid.cross.fill", label: "500 coins",
                                      detail: "Spend in the cosmetics shop")
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)

                        // ── Countdown timer ─────────────────────────────────
                        if gameState.starterPackOfferActive {
                            countdownView
                                .padding(.bottom, 24)
                        }

                        // ── Buy button ──────────────────────────────────────
                        let pid: StoreKitManager.ProductID = .starterPack
                        let inProgress = store.purchaseInProgress == pid

                        Button {
                            Task { await store.purchase(pid) }
                        } label: {
                            if inProgress {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.black)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(.white)
                                    )
                            } else {
                                HStack(spacing: 8) {
                                    Text(store.displayPrice(for: pid, fallback: "$1.99"))
                                        .font(.system(size: 18, weight: .black, design: .rounded))
                                        .foregroundStyle(.black)
                                    Text("— Claim Offer")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.black.opacity(0.72))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.84, green: 1.00, blue: 0.90),
                                                    Color(red: 0.72, green: 0.88, blue: 1.00),
                                                ],
                                                startPoint: .leading, endPoint: .trailing
                                            )
                                        )
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(inProgress || gameState.starterPackClaimed)
                        .padding(.horizontal, 24)

                        // ── Dismiss (permanent) ─────────────────────────────
                        Button {
                            gameState.starterPackClaimed = true
                            dismiss()
                        } label: {
                            Text("No thanks")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(white: 0.40))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 14)

                        Spacer().frame(height: 32)
                    }
                }
            }
            .navigationBarHidden(true)
            .onChange(of: gameState.starterPackClaimed) { _, claimed in
                if claimed { dismiss() }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onChange(of: store.lastError) { _, err in purchaseError = err }
        .alert("Purchase Failed", isPresented: Binding(
            get: { purchaseError != nil },
            set: { _ in purchaseError = nil; store.clearLastError() }
        ), actions: { Button("OK", role: .cancel) {} },
        message: { Text(purchaseError ?? "") })
    }

    // ── Reward row helper ────────────────────────────────────────────────
    private func rewardRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.95, blue: 0.65),
                            Color(red: 0.62, green: 0.45, blue: 0.98),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(white: 0.55))
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.10))
        )
    }

    // ── Countdown timer ──────────────────────────────────────────────────
    private var countdownView: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let secs = Int(gameState.starterPackSecondsRemaining)
            let h = secs / 3600
            let m = (secs % 3600) / 60
            let s = secs % 60
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(format: "%d:%02d:%02d remaining", h, m, s))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }
            .foregroundStyle(Color(white: 0.55))
        }
    }
}
