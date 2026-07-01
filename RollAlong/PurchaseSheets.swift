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

/// Reports the natural height of a sheet's content so the sheet can size itself
/// to fit exactly (no dead space below the last row).
private struct SheetFitHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct BuyLivesSheet: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var store:     StoreKitManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var purchaseError: String? = nil
    @State private var fitHeight: CGFloat = 560   // content height; set on first layout
    @State private var celebrate = false          // drives the Diamond Balls victory loop

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if gameState.unlimitedLives {
                        // Diamond Balls owners never buy lives — hide every
                        // purchasable so a tap can't cost them money they don't
                        // need.  Just celebrate what they already own.
                        celebrationView
                    } else {
                        // Title lives in the content now (no nav bar) so the sheet
                        // can size itself to exactly fit the content.  Matches the
                        // Get Coins title: size 24, centred, with top room so it
                        // sits centred between the grabber and the row below it.
                        Text("Get Lives")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 12)
                        header
                        statusBlock
                        lifePackCards
                        Text("OR NEVER RUN OUT")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .kerning(1.5)
                            .foregroundStyle(Color(white: 0.45))
                            .padding(.top, 6)
                        diamondBallsCard
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 18)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: SheetFitHeightKey.self, value: geo.size.height)
                })
            }
            // Swipe down (or tap above) to close. Restore Purchases is in Settings.
        }
        // Confetti + fanfare on every successful lives purchase.
        .overlay {
            PurchaseCelebrationOverlay(trigger: store.deliveryCount,
                                       kind: .lives,
                                       receipt: store.lastDelivery)
        }
        .preferredColorScheme(.dark)
        // Size the sheet to its content — Diamond Balls fully visible, no gap below.
        .presentationDetents([.height(fitHeight)])
        // Grabber bar signals "drag down (or tap above) to close" — always shown,
        // matching the Get Coins sheet.
        .presentationDragIndicator(.visible)
        .onPreferenceChange(SheetFitHeightKey.self) { fitHeight = max($0, 200) }
        .onAppear { if !reduceMotion { celebrate = true } }
        .onChange(of: store.lastError) { _, err in purchaseError = err }
        .alert("Purchase Failed", isPresented: Binding(
            get: { purchaseError != nil },
            set: { _ in purchaseError = nil; store.clearLastError() }
        ), actions: { Button("OK", role: .cancel) {} },
        message: { Text(purchaseError ?? "") })
    }

    private var header: some View {
        let unlimited = gameState.unlimitedLives
        return HStack(spacing: 6) {
            ForEach(0..<GameState.livesMax, id: \.self) { i in
                // Diamond Balls owners: every slot is a filled diamond marble.
                lifeMarble(filled: unlimited || i < gameState.displayedLives,
                           diamond: unlimited)
            }
            Spacer()
            if unlimited {
                Image(systemName: "infinity")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Self.diamondLifeGradient)
            } else {
                Text("\(gameState.displayedLives) / \(GameState.livesMax)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.75))
            }
        }
        .padding(.bottom, 6)
    }

    /// One life as a glossy marble — the same highlight-dot-and-rim recipe as
    /// the home screen's lives pill (HomeView.marbleIcon), so lives read as
    /// the familiar red ball here too instead of a flat disc.  An empty slot
    /// is a hollow outline, also matching the pill.
    private func lifeMarble(filled: Bool, diamond: Bool = false) -> some View {
        let size: CGFloat = 18
        return ZStack {
            Circle()
                .stroke(Color(white: 0.40).opacity(0.7), lineWidth: 1.0)
                .frame(width: size, height: size)
            if filled {
                Circle()
                    .fill(diamond ? Self.diamondLifeGradient : Self.redLifeGradient)
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
                            .foregroundStyle(Self.diamondLifeGradient)
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

    // MARK: - Diamond Balls celebration (owners only)

    /// Replaces every purchasable once Diamond Balls is owned, so a stray tap
    /// can never spend money on lives the player already has infinite of.
    /// A looping gradient + sparkle victory lap around the diamond marble they
    /// unlocked — and nothing else.
    private var celebrationView: some View {
        // Compact layout: the full celebration fits without scrolling, sizing the
        // sheet to about the Get Coins height.
        VStack(spacing: 10) {
            Text("✦  YOU OWN  ✦")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(3.0)
                .foregroundStyle(Self.diamondGradient)

            // Centerpiece: the real Diamond ball skin, haloed by a slow conic
            // glow and ringed with twinkling sparkles.
            ZStack {
                Circle()
                    .fill(Self.celebrationHalo)
                    .frame(width: 148, height: 148)
                    .blur(radius: 28)
                    .opacity(0.55)
                    .rotationEffect(.degrees(celebrate ? 360 : 0))
                    .animation(.linear(duration: 9).repeatForever(autoreverses: false),
                               value: celebrate)

                ForEach(Array(Self.sparkleOffsets.enumerated()), id: \.offset) { idx, off in
                    Image(systemName: "sparkle")
                        .font(.system(size: idx % 2 == 0 ? 15 : 10, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(celebrate ? 1.0 : 0.7)
                        .scaleEffect(celebrate ? 1.0 : 0.55)
                        .offset(off)
                        .shadow(color: Color(red: 0.55, green: 0.85, blue: 1.0), radius: 6)
                        .animation(.easeInOut(duration: 1.1 + Double(idx) * 0.35)
                                    .repeatForever(autoreverses: true),
                                   value: celebrate)
                }

                BallSkinView(skin: .diamond, diameter: 92)
                    .frame(width: 92, height: 92)
                    .scaleEffect(celebrate ? 1.05 : 0.98)
                    .shadow(color: Color(red: 0.50, green: 0.85, blue: 1.0).opacity(0.7),
                            radius: 18)
                    .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true),
                               value: celebrate)
            }
            .frame(height: 148)

            Text("Diamond Balls")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(Self.diamondGradient)

            HStack(spacing: 7) {
                Image(systemName: "infinity")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Self.diamondLifeGradient)
                Text("Unlimited lives, forever")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.88))
            }

            // The two follow-up notes condensed onto one line so nothing scrolls.
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Self.diamondGradient)
                Text("Indestructible · exclusive Diamond skin unlocked")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.60))
            }
            .padding(.top, 1)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .background(celebrationBackground)
    }

    /// The card's deep-blue base with a slowly rotating aurora sheen — the
    /// "animated gradient" the celebration sits on.
    private var celebrationBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.11, blue: 0.22),
                                 Color(red: 0.10, green: 0.19, blue: 0.34),
                                 Color(red: 0.05, green: 0.09, blue: 0.19)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Circle()
                .fill(Self.celebrationHalo)
                .frame(width: 460, height: 460)
                .blur(radius: 70)
                .opacity(0.28)
                .rotationEffect(.degrees(celebrate ? -360 : 0))
                .animation(.linear(duration: 14).repeatForever(autoreverses: false),
                           value: celebrate)
                .blendMode(.plusLighter)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Self.diamondGradient, lineWidth: 1.5)
        )
        .shadow(color: Color(red: 0.50, green: 0.85, blue: 1.0).opacity(0.30), radius: 16, y: 4)
    }

    /// Cool white→cyan conic sweep reused by the halo and the card sheen.
    private static let celebrationHalo = AngularGradient(
        gradient: Gradient(colors: [
            Color(red: 0.40, green: 0.72, blue: 1.00),
            Color(red: 0.82, green: 0.96, blue: 1.00),
            Color(red: 0.55, green: 0.82, blue: 1.00),
            Color.white,
            Color(red: 0.45, green: 0.70, blue: 0.98),
            Color(red: 0.40, green: 0.72, blue: 1.00),
        ]),
        center: .center)

    /// Where the four twinkling sparkles sit around the diamond marble.
    private static let sparkleOffsets: [CGSize] = [
        CGSize(width: -60, height: -34),
        CGSize(width:  62, height: -22),
        CGSize(width:  52, height:  42),
        CGSize(width: -50, height:  40),
    ]

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
                bonus: lifeBonus(.livesPack5, lives: 60),
                buttonLabel: store.displayPrice(for: .livesPack5, fallback: "$4.99")
            )
            productCard(
                pid: .livesPack10,
                title: "13 full reloads",
                subtitle: "130 lives — for chasers",
                bonus: lifeBonus(.livesPack10, lives: 130),
                buttonLabel: store.displayPrice(for: .livesPack10, fallback: "$9.99")
            )
        }
    }

    /// % more lives than buying the same spend as base 10-life ($0.99) packs,
    /// rounded to the nearest 10%.  Nil for the base pack (it IS the base rate).
    /// Mirrors `coinBonus` so the Get Lives sheet reads like Get Coins.
    private func lifeBonus(_ pid: StoreKitManager.ProductID, lives: Int) -> String? {
        let baseRate = 10.0 / 0.99           // lives per dollar at the base pack
        let price: Double
        switch pid {
        case .livesPack5:  price = 4.99
        case .livesPack10: price = 9.99
        default:           return nil
        }
        let livesIfBoughtAsBase = baseRate * price
        let pct = (Double(lives) / livesIfBoughtAsBase - 1.0) * 100.0
        let rounded = Int((pct / 10.0).rounded()) * 10
        return rounded > 0 ? "+\(rounded)% lives" : nil
    }

    private func productCard(
        pid: StoreKitManager.ProductID,
        title: String,
        subtitle: String,
        bonus: String? = nil,
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
                // Free-lives bonus vs. the base pack — green, mirrors Get Coins.
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
    /// Diamond Balls (unlimited lives) marble + ∞ fill — cool white→cyan,
    /// matching the home lives pill and the in-game HUD.
    private static let diamondLifeGradient = LinearGradient(
        colors: [Color(red: 0.86, green: 0.96, blue: 1.00),
                 Color(red: 0.48, green: 0.74, blue: 0.97)],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Buy Coins Sheet

struct BuyCoinsSheet: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var store:     StoreKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var purchaseError: String? = nil
    // Self-size to the content so the sheet opens exactly tall enough to show
    // every pack (down to the $49.99 tier) with no empty space below — the same
    // content-fit approach BuyLivesSheet uses.
    @State private var fitHeight: CGFloat = 580   // content height; set on first layout

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Title lives in the content (no nav bar) so the sheet can
                    // size itself to exactly fit the packs.  The extra top padding
                    // + matching gap below centre it between the grabber and the
                    // coins/"earn coins" row.
                    Text("Get Coins")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                    header
                    coinPackCards
                }
                .padding(.horizontal, 18)
                .padding(.top, 26)
                .padding(.bottom, 18)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: SheetFitHeightKey.self, value: geo.size.height)
                })
            }
        }
        // Confetti + fanfare on every successful coin purchase.
        .overlay {
            PurchaseCelebrationOverlay(trigger: store.deliveryCount,
                                       kind: .coins,
                                       receipt: store.lastDelivery)
        }
        .preferredColorScheme(.dark)
        // Size the sheet to its content — every pack visible, no gap below.
        // Swipe down (the grabber) to close; Restore Purchases lives in Settings.
        .presentationDetents([.height(fitHeight)])
        .presentationDragIndicator(.visible)
        .onPreferenceChange(SheetFitHeightKey.self) { fitHeight = max($0, 200) }
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
            Text("Earn coins in game\nOr buy them here.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.trailing)
                .fixedSize()
        }
        .padding(.bottom, 6)
    }

    private var coinPackCards: some View {
        VStack(spacing: 10) {
            coinCard(pid: .coins100,   amount: 100)
            coinCard(pid: .coins600,   amount: 600)
            coinCard(pid: .coins1300,  amount: 1300)
            coinCard(pid: .coins3000,  amount: 3000)
            coinCard(pid: .coins10000, amount: 10000)
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
        let isTopTier = pid == .coins10000
        return HStack(alignment: .center, spacing: 12) {
            // Per-tier hoard art — escalates from a few loose coins up to a
            // jewel-stuffed vault so each pack reads at a glance.
            coinPackIcon(for: pid)
                .frame(width: 40, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(amount.formatted(.number)) coins")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if isTopTier {
                    // Top pack: shimmery-diamond "×2 coins" instead of the
                    // plain green "+100% coins" bonus line.
                    DiamondBonusLabel(text: "×2 coins")
                } else if let bonus {
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
                .fill(Color(white: isTopTier ? 0.16 : 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isTopTier ? DiamondBonusLabel.shimmerGradient
                                          : LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing),
                                lineWidth: isTopTier ? 1.2 : 0)
                )
        )
    }

    /// Hoard art for a coin pack — escalates with pack size:
    /// a few coins → a pile of coins → a money bag → a gem-stuffed treasure
    /// chest → a jewel-stuffed vault for the top pack.
    @ViewBuilder
    private func coinPackIcon(for pid: StoreKitManager.ProductID) -> some View {
        switch pid {
        case .coins100:   FewCoinsIcon()
        case .coins600:   CoinPileIcon()
        case .coins1300:  CoinBagIcon()
        case .coins3000:  TreasureChestIcon(gems: true)
        case .coins10000: VaultIcon()
        default:          FewCoinsIcon()
        }
    }

    private func defaultPrice(for pid: StoreKitManager.ProductID) -> String {
        switch pid {
        case .coins100, .livesPack1:   return "$0.99"
        case .coins600, .livesPack5:   return "$4.99"
        case .coins1300, .livesPack10: return "$9.99"
        case .coins3000, .unlimited:   return "$19.99"
        case .coins10000:              return "$49.99"
        case .starterPack:             return "$1.99"
        }
    }

    // (Coin glyph rendering moved to the shared CoinIcon view in
    // BallGameView.swift — see PR notes.)
}


// MARK: - Coin-pack hoard art
//
// Per-tier icons for the Get Coins sheet.  They escalate with pack size so a
// player reads the value at a glance: a few loose coins → a money bag → a
// treasure chest (gems on the bigger one) → a jewel-stuffed vault for the top
// pack.  All drawn in pure SwiftUI shapes so they scale crisply and reuse the
// shared CoinIcon gold so the coins match the rest of the app.

/// Lowest tier — just a few coins in a little pile.
private struct FewCoinsIcon: View {
    var body: some View {
        ZStack {
            CoinIcon(size: 17).offset(x: -7, y: 7)
            CoinIcon(size: 17).offset(x:  6, y: 8)
            CoinIcon(size: 20).offset(x: -1, y: -3)
        }
    }
}

/// Second tier — a heaped pile of many coins (apex peeking, front row nearest).
private struct CoinPileIcon: View {
    var body: some View {
        ZStack {
            // Apex — peeks over the top, drawn first so the heap stacks in front.
            CoinIcon(size: 16).offset(x: -4, y: -6)
            CoinIcon(size: 16).offset(x:  4, y: -7)
            // Middle row.
            CoinIcon(size: 16).offset(x: -8.5, y: 2)
            CoinIcon(size: 17).offset(x:  0,   y: 1)
            CoinIcon(size: 16).offset(x:  8.5, y: 2)
            // Bottom-front row — nearest, on top.
            CoinIcon(size: 16).offset(x: -13,  y: 11)
            CoinIcon(size: 17).offset(x: -4.5, y: 12)
            CoinIcon(size: 17).offset(x:  4.5, y: 12)
            CoinIcon(size: 16).offset(x:  13,  y: 11)
        }
    }
}

/// Mid tier — a drawstring money bag with coins spilling from the mouth.
private struct CoinBagIcon: View {
    var body: some View {
        ZStack {
            // Round sack bulb
            Circle()
                .fill(CoinPackArt.bagFace)
                .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
                .frame(width: 27, height: 27)
                .offset(y: 6)
            // Gathered, flared neck above the tie
            BagNeck()
                .fill(CoinPackArt.bagNeck)
                .frame(width: 19, height: 11)
                .offset(y: -7)
            // Drawstring tie
            Capsule()
                .fill(CoinPackArt.bagTie)
                .frame(width: 20, height: 4.5)
                .offset(y: -3)
            // Gold $ stamped on the sack face
            Text("$")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(CoinIcon.goldenFace)
                .shadow(color: .black.opacity(0.3), radius: 0.5, y: 0.5)
                .offset(y: 7)
            // Coins peeking out of the mouth
            CoinIcon(size: 11).offset(x: -5, y: -12)
            CoinIcon(size: 11).offset(x:  5, y: -13)
        }
    }
}

/// Upper-mid tiers — a banded treasure chest heaped with coins; `gems` adds a
/// couple of jewels for the bigger of the two chest packs.
private struct TreasureChestIcon: View {
    let gems: Bool
    var body: some View {
        ZStack {
            // Chest base
            RoundedRectangle(cornerRadius: 3)
                .fill(CoinPackArt.woodFace)
                .frame(width: 30, height: 15)
                .offset(y: 8)
            // Domed lid
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 8, bottomLeading: 1,
                                   bottomTrailing: 1, topTrailing: 8))
                .fill(CoinPackArt.woodLid)
                .frame(width: 30, height: 13)
                .offset(y: -1)
            // Iron bands + latch
            Rectangle().fill(CoinPackArt.goldBand)
                .frame(width: 30, height: 2.5).offset(y: 1.5)
            Rectangle().fill(CoinPackArt.goldBand)
                .frame(width: 3, height: 22).offset(y: 4)
            RoundedRectangle(cornerRadius: 1).fill(CoinPackArt.goldBand)
                .frame(width: 6, height: 6).offset(y: 2.5)
            // Treasure heaped on top, spilling over the front-right edge
            if gems {
                gem(CoinPackArt.gemCyan, size: 9).offset(x: -3, y: -13)
                gem(CoinPackArt.gemPink, size: 8).offset(x:  7, y: -14)
            }
            CoinIcon(size: 11).offset(x: -9, y: -10)
            CoinIcon(size: 12).offset(x:  0, y: -12)
            CoinIcon(size: 11).offset(x:  9, y: -10)
            CoinIcon(size:  9).offset(x: 13, y:  6)
        }
    }
}

/// Top tier — a bank vault, wheel and all, overflowing with coins, gems, and
/// a gold ring (jewelry) at the base.
private struct VaultIcon: View {
    var body: some View {
        ZStack {
            // Hinges on the left edge
            ForEach(0..<2, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(CoinPackArt.steelDark)
                    .frame(width: 4, height: 6)
                    .offset(x: -15, y: CGFloat(i == 0 ? -9 : 4))
            }
            // Vault door
            RoundedRectangle(cornerRadius: 7)
                .fill(CoinPackArt.steelFace)
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(CoinPackArt.steelLight.opacity(0.8), lineWidth: 1))
                .frame(width: 28, height: 28)
                .offset(y: -4)
            // Recessed inner frame
            RoundedRectangle(cornerRadius: 5)
                .stroke(CoinPackArt.steelDark, lineWidth: 1.5)
                .frame(width: 21, height: 21)
                .offset(y: -4)
            // Spoked wheel / dial
            VaultDial().offset(y: -4)
            // Hoard spilling out the bottom: jewelry ring, gems, coins
            Circle()
                .stroke(CoinIcon.goldenFace, lineWidth: 2)
                .frame(width: 8, height: 8)
                .offset(x: 13, y: 10)
            gem(CoinPackArt.gemGreen, size: 9).offset(x: -12, y: 9)
            gem(CoinPackArt.gemPink,  size: 7).offset(x:   4, y: 14)
            CoinIcon(size: 11).offset(x: -7, y: 13)
            CoinIcon(size: 12).offset(x:  2, y: 15)
            CoinIcon(size: 10).offset(x: 10, y: 13)
        }
    }
}

/// The vault's spoked turn-wheel.
private struct VaultDial: View {
    var body: some View {
        ZStack {
            // Handle spokes poking out past the hub
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(CoinPackArt.steelLight)
                    .frame(width: 2.5, height: 17)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            Circle().fill(CoinPackArt.steelDial).frame(width: 11, height: 11)
            Circle().stroke(CoinPackArt.steelLight, lineWidth: 1.5).frame(width: 11, height: 11)
            Circle().fill(CoinPackArt.steelLight).frame(width: 3.5, height: 3.5)
        }
        .frame(width: 18, height: 18)
    }
}

/// A faceted gem — a simple brilliant-cut silhouette with a top-facet glint.
private func gem(_ fill: LinearGradient, size: CGFloat) -> some View {
    GemShape()
        .fill(fill)
        .overlay(GemShape().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
        .frame(width: size, height: size)
}

/// Gem silhouette: a flat table on top tapering to a single point.
private struct GemShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.38))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.24, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.24, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.38))
        p.closeSubpath()
        return p
    }
}

/// The gathered, flared mouth of the money bag (wide at the top, pinching down
/// to the tie).
private struct BagNeck: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let inset = r.width * 0.26
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + inset, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Shared palette for the hoard art.
private enum CoinPackArt {
    static let woodFace = LinearGradient(
        colors: [Color(red: 0.60, green: 0.40, blue: 0.20),
                 Color(red: 0.40, green: 0.25, blue: 0.11)],
        startPoint: .top, endPoint: .bottom)
    static let woodLid = LinearGradient(
        colors: [Color(red: 0.52, green: 0.34, blue: 0.16),
                 Color(red: 0.34, green: 0.21, blue: 0.09)],
        startPoint: .top, endPoint: .bottom)
    static let goldBand = Color(red: 0.93, green: 0.76, blue: 0.32)

    static let bagFace = LinearGradient(
        colors: [Color(red: 0.82, green: 0.64, blue: 0.38),
                 Color(red: 0.54, green: 0.36, blue: 0.16)],
        startPoint: .top, endPoint: .bottom)
    static let bagNeck = LinearGradient(
        colors: [Color(red: 0.74, green: 0.56, blue: 0.31),
                 Color(red: 0.58, green: 0.40, blue: 0.18)],
        startPoint: .top, endPoint: .bottom)
    static let bagTie = Color(red: 0.40, green: 0.26, blue: 0.10)

    static let steelFace = LinearGradient(
        colors: [Color(red: 0.80, green: 0.84, blue: 0.90),
                 Color(red: 0.46, green: 0.51, blue: 0.59)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let steelDial = LinearGradient(
        colors: [Color(red: 0.42, green: 0.46, blue: 0.54),
                 Color(red: 0.24, green: 0.27, blue: 0.33)],
        startPoint: .top, endPoint: .bottom)
    static let steelLight = Color(red: 0.88, green: 0.91, blue: 0.96)
    static let steelDark  = Color(red: 0.30, green: 0.34, blue: 0.41)

    static let gemCyan = LinearGradient(
        colors: [Color(red: 0.66, green: 0.96, blue: 1.00),
                 Color(red: 0.20, green: 0.66, blue: 0.92)],
        startPoint: .top, endPoint: .bottom)
    static let gemPink = LinearGradient(
        colors: [Color(red: 1.00, green: 0.74, blue: 0.88),
                 Color(red: 0.90, green: 0.34, blue: 0.64)],
        startPoint: .top, endPoint: .bottom)
    static let gemGreen = LinearGradient(
        colors: [Color(red: 0.66, green: 0.98, blue: 0.74),
                 Color(red: 0.22, green: 0.74, blue: 0.45)],
        startPoint: .top, endPoint: .bottom)
}

// MARK: - Shimmery-diamond bonus label

/// The "×2 coins" subtitle on the top coin pack: a cool diamond gradient with a
/// highlight that sweeps across the glyphs.  Shown instead of the plain green
/// "+100% coins" bonus so the best-value pack reads as premium.
private struct DiamondBonusLabel: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    /// Cool white→cyan→blue sweep — also used for the top pack's card border so
    /// the label and the card read as a set.
    static let shimmerGradient = LinearGradient(
        colors: [Color(red: 0.86, green: 0.96, blue: 1.00),
                 Color(red: 0.55, green: 0.80, blue: 1.00),
                 Color(red: 0.80, green: 0.92, blue: 1.00)],
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        content
            .foregroundStyle(Self.shimmerGradient)
            .overlay(shimmerSweep)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
    }

    private var content: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
    }

    /// A bright band that slides left→right, masked to the label's glyphs.
    private var shimmerSweep: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(colors: [.clear, Color.white.opacity(0.95), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: w * 0.5)
                .offset(x: shimmer ? w : -w * 0.6)
                .blendMode(.plusLighter)
        }
        .mask(content)
        .allowsHitTesting(false)
    }
}

// MARK: - Purchase celebration (confetti + fanfare)

/// Which sheet is celebrating — drives the reward badge's wording + icon.
enum PurchaseCelebrationKind {
    case lives
    case coins
}

/// Drop-in overlay for the Get Lives / Get Coins sheets.  Each time `trigger`
/// increments (one bump per successful delivery, via
/// `StoreKitManager.deliveryCount`) it rains confetti, pops a reward badge,
/// plays the win fanfare, and fires a success haptic — all respecting the
/// player's sound/haptics toggles.  Never blocks touches.
private struct PurchaseCelebrationOverlay: View {
    let trigger: Int
    let kind: PurchaseCelebrationKind
    let receipt: StoreKitManager.DeliveryReceipt?

    @EnvironmentObject private var gameState: GameState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confettiTick = 0
    @State private var badge: BadgeContent? = nil
    @State private var badgeShown = false

    struct BadgeContent: Equatable {
        let title: String
        let subtitle: String
        let kind: Kind
        enum Kind { case coins, life, unlimited }
    }

    var body: some View {
        ZStack {
            PurchaseConfettiView(trigger: confettiTick)
            if let badge, badgeShown {
                rewardBadge(badge)
                    .transition(reduceMotion ? .opacity
                                             : .scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, newValue in
            guard newValue > 0 else { return }
            celebrate()
        }
    }

    private func celebrate() {
        // Defensive: only celebrate the kind this sheet sells (normally just one
        // sheet is alive at a time, so this rarely matters).
        guard let r = receipt else { return }
        let content: BadgeContent
        switch kind {
        case .lives:
            if r.unlimitedActivated {
                content = BadgeContent(title: "Unlimited Lives!",
                                       subtitle: "Never run out again",
                                       kind: .unlimited)
            } else if r.lives > 0 {
                content = BadgeContent(title: "+\(r.lives) lives",
                                       subtitle: "Lives added", kind: .life)
            } else { return }
        case .coins:
            guard r.coins > 0 else { return }
            // The 10,000-coin pack may also drop a secret "Money" cosmetic —
            // announce it in place of the usual subtitle.
            let sub = r.grantedCosmeticName.map { "🎉 Unlocked \($0)!" } ?? "Added to your balance"
            content = BadgeContent(title: "+\(r.coins.formatted(.number)) coins",
                                   subtitle: sub, kind: .coins)
        }

        // Fanfare + haptic, gated by the player's toggles.
        if gameState.soundEnabled {
            AudioManager.shared.prepareIfNeeded()
            AudioManager.shared.playWin(enabled: true)
        }
        if gameState.hapticsEnabled { Haptics.success() }

        // Visuals: kick the confetti (skipped under Reduce Motion), pop the
        // badge, then auto-dismiss it.
        if !reduceMotion { confettiTick += 1 }
        badge = content
        let pop: Animation = reduceMotion ? .easeOut(duration: 0.3)
                                          : .spring(response: 0.45, dampingFraction: 0.62)
        withAnimation(pop) { badgeShown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            withAnimation(.easeOut(duration: 0.4)) { badgeShown = false }
        }
    }

    @ViewBuilder
    private func rewardBadge(_ b: BadgeContent) -> some View {
        let accent: Color = {
            switch b.kind {
            case .coins:     return Color(red: 1.00, green: 0.80, blue: 0.25)
            case .unlimited: return Color(red: 0.55, green: 0.85, blue: 1.00)
            case .life:      return Color(red: 1.00, green: 0.42, blue: 0.42)
            }
        }()
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(accent.opacity(0.30)).frame(width: 96, height: 96).blur(radius: 14)
                badgeIcon(b.kind)
            }
            .frame(height: 60)
            Text(b.title)
                .font(.system(size: 23, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(b.subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.70))
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(white: 0.12))
                .overlay(RoundedRectangle(cornerRadius: 22)
                    .stroke(accent.opacity(0.65), lineWidth: 1.5))
        )
        .shadow(color: accent.opacity(0.40), radius: 22, y: 6)
    }

    @ViewBuilder
    private func badgeIcon(_ kind: BadgeContent.Kind) -> some View {
        switch kind {
        case .coins:
            CoinIcon(size: 56)
        case .unlimited:
            Image(systemName: "infinity")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(LinearGradient(
                    colors: [Color(red: 0.86, green: 0.96, blue: 1.00),
                             Color(red: 0.48, green: 0.74, blue: 0.97)],
                    startPoint: .top, endPoint: .bottom))
        case .life:
            // Glossy red marble — the app's standing icon for a life.
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 1.00, green: 0.32, blue: 0.32),
                             Color(red: 0.78, green: 0.14, blue: 0.14)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 54, height: 54)
                .overlay(Circle().fill(Color.white.opacity(0.55))
                    .frame(width: 16, height: 16).offset(x: -10, y: -10))
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
        }
    }
}

/// A one-shot confetti shower driven by a `trigger` counter.  Idle (and
/// CPU-free) until `trigger` changes, then rains a fresh field of pieces for
/// `duration` seconds.
private struct PurchaseConfettiView: View {
    let trigger: Int
    private let duration: TimeInterval = 2.8

    @State private var startDate: Date? = nil
    @State private var pieces: [ConfettiBit] = []

    var body: some View {
        TimelineView(.animation(paused: startDate == nil)) { tl in
            Canvas { ctx, size in
                guard let start = startDate else { return }
                let elapsed = tl.date.timeIntervalSince(start)
                guard elapsed <= duration else { return }
                draw(ctx, size: size, elapsed: elapsed)
            }
        }
        .onChange(of: trigger) { _, v in
            guard v > 0 else { return }
            pieces = ConfettiBit.field(count: 72)
            startDate = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
                // Stop the timeline only if no newer burst has started.
                if let s = startDate, Date().timeIntervalSince(s) >= duration {
                    startDate = nil
                }
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let W = Double(size.width), H = Double(size.height)
        for p in pieces {
            let py = Double(p.y0) * H + Double(p.fall) * elapsed
            if py > H + 30 { continue }
            let px = Double(p.x) * W
                   + Double(p.drift) * elapsed
                   + Double(p.swayAmp) * sin(elapsed * Double(p.swayFreq) + Double(p.phase))

            var op = 1.0
            if elapsed < 0.12 { op = elapsed / 0.12 }
            let fadeStart = duration - 0.7
            if elapsed > fadeStart { op = max(0, (duration - elapsed) / 0.7) }

            var layer = ctx
            layer.opacity = op
            layer.translateBy(x: CGFloat(px), y: CGFloat(py))
            layer.rotate(by: .radians(Double(p.spin) * elapsed))
            let rect = CGRect(x: -Double(p.w) / 2, y: -Double(p.h) / 2,
                              width: Double(p.w), height: Double(p.h))
            if p.round {
                layer.fill(Path(ellipseIn: rect), with: .color(p.color))
            } else {
                layer.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(p.color))
            }
        }
    }
}

/// One confetti piece: where it starts, how it drifts/sways/spins, and its look.
private struct ConfettiBit {
    let x: CGFloat          // 0…1 across the width
    let y0: CGFloat         // start fraction (negative → above the top edge)
    let w: CGFloat
    let h: CGFloat
    let color: Color
    let fall: CGFloat       // px/sec downward
    let drift: CGFloat      // px/sec horizontal
    let swayAmp: CGFloat
    let swayFreq: CGFloat
    let phase: CGFloat
    let spin: CGFloat       // rad/sec
    let round: Bool

    static func field(count: Int) -> [ConfettiBit] {
        let palette: [Color] = [
            Color(red: 1.00, green: 0.32, blue: 0.32),
            Color(red: 1.00, green: 0.78, blue: 0.20),
            Color(red: 0.35, green: 0.80, blue: 1.00),
            Color(red: 0.40, green: 0.85, blue: 0.52),
            Color(red: 0.78, green: 0.50, blue: 1.00),
            Color(red: 1.00, green: 0.55, blue: 0.80),
            Color(red: 0.45, green: 0.95, blue: 0.90),
        ]
        var rng = SystemRandomNumberGenerator()
        return (0..<count).map { _ in
            ConfettiBit(
                x:        .random(in: 0...1, using: &rng),
                y0:       .random(in: -0.25...0.05, using: &rng),
                w:        .random(in: 5...10, using: &rng),
                h:        .random(in: 7...14, using: &rng),
                color:    palette.randomElement(using: &rng)!,
                fall:     .random(in: 150...320, using: &rng),
                drift:    .random(in: -40...40, using: &rng),
                swayAmp:  .random(in: 6...22, using: &rng),
                swayFreq: .random(in: 1.5...3.5, using: &rng),
                phase:    .random(in: 0...(2 * .pi), using: &rng),
                spin:     .random(in: -6...6, using: &rng),
                round:    .random(using: &rng)
            )
        }
    }
}
