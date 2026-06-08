import SwiftUI
import StoreKit

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

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        statusBlock
                        unlimitedCard
                        Text("OR PACKS")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .kerning(1.5)
                            .foregroundStyle(Color(white: 0.45))
                            .padding(.top, 6)
                        lifePackCards
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
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: 10) {
            ForEach(0..<6) { i in
                Circle()
                    .fill(i < gameState.displayedLives
                          ? Self.redLifeGradient
                          : Self.dimGradient)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.30), lineWidth: 0.6)
                    )
            }
            Spacer()
            Text("\(gameState.displayedLives) / 6")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.75))
        }
        .padding(.bottom, 6)
    }

    /// Live status + explanation block under the 6-marble header.  Shows
    /// the next-life countdown when regen is active and the standing rule
    /// (1 life every 10 min, up to 6).  Hidden for unlimited subscribers
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
                    Text("You earn 1 life every 10 minutes, up to 6.")
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

    @ViewBuilder
    private var unlimitedCard: some View {
        let pid: StoreKitManager.ProductID = .unlimited
        let isOwned = gameState.unlimitedLives
        productCard(
            pid: pid,
            title: "Unlimited Lives",
            subtitle: isOwned ? "Active" : "One-time purchase. Never run out.",
            badge: "BEST",
            badgeColor: Color(red: 1.00, green: 0.84, blue: 0.30),
            buttonLabel: isOwned ? "Owned" : store.displayPrice(for: pid, fallback: "$19.99"),
            isDisabled: isOwned,
            isLarge: true
        )
    }

    private var lifePackCards: some View {
        VStack(spacing: 10) {
            productCard(
                pid: .livesPack1,
                title: "1 full reload",
                subtitle: "6 lives",
                buttonLabel: store.displayPrice(for: .livesPack1, fallback: "$0.99")
            )
            productCard(
                pid: .livesPack5,
                title: "6 full reloads",
                subtitle: "36 lives — best value casual",
                buttonLabel: store.displayPrice(for: .livesPack5, fallback: "$4.99")
            )
            productCard(
                pid: .livesPack10,
                title: "13 full reloads",
                subtitle: "78 lives — for chasers",
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
    private static let dimGradient = LinearGradient(
        colors: [Color(white: 0.25), Color(white: 0.18)],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Buy Coins Sheet

struct BuyCoinsSheet: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var store:     StoreKitManager
    @Environment(\.dismiss) private var dismiss

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
    }

    private var header: some View {
        HStack {
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
        }
        .padding(.bottom, 6)
    }

    private var coinPackCards: some View {
        VStack(spacing: 10) {
            coinCard(pid: .coins100,  amount: 100,   bonus: nil)
            coinCard(pid: .coins600,  amount: 600,   bonus: "+100 bonus")
            coinCard(pid: .coins1300, amount: 1300,  bonus: "+300 bonus", isFeatured: true)
            coinCard(pid: .coins3000, amount: 3000,  bonus: "biggest pack")
        }
    }

    private func coinCard(
        pid: StoreKitManager.ProductID,
        amount: Int,
        bonus: String?,
        isFeatured: Bool = false
    ) -> some View {
        let inProgress = store.purchaseInProgress == pid
        return HStack(alignment: .center, spacing: 12) {
            // Stacked coin icons — three CoinIcons offset to suggest a
            // small pile.  Same paw-print minted graphic as everywhere
            // else in the app.
            ZStack {
                ForEach(0..<3) { i in
                    CoinIcon(size: 24)
                        .offset(x: CGFloat(i) * 3, y: CGFloat(i) * -2)
                }
            }
            .frame(width: 34, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(amount.formatted(.number)) coins")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if isFeatured {
                        Text("BEST VALUE")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .kerning(0.8)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color(red: 1.00, green: 0.84, blue: 0.30))
                            )
                    }
                }
                if let bonus {
                    Text(bonus)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.65))
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
                .fill(isFeatured ? Color(white: 0.16) : Color(white: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFeatured
                                ? Color(red: 1.00, green: 0.84, blue: 0.30).opacity(0.5)
                                : Color.clear, lineWidth: 1.0)
                )
        )
    }

    private func defaultPrice(for pid: StoreKitManager.ProductID) -> String {
        switch pid {
        case .coins100, .livesPack1:  return "$0.99"
        case .coins600, .livesPack5:  return "$4.99"
        case .coins1300, .livesPack10: return "$9.99"
        case .coins3000, .unlimited:  return "$19.99"
        case .starterPack:            return "$1.99"
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
