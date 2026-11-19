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

/// Reports the natural height of a sheet's content so the sheet can size itself
/// to fit exactly (no dead space below the last row).
struct SheetFitHeightKey: PreferenceKey {
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
    @State private var showReserveInfo = false    // popover on the reserve pouch

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
                        // The standing rule, centered under the title and
                        // directly above the row of life balls it describes.
                        Text("You earn 1 life every 6 minutes, up to \(GameState.livesMax).")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(white: 0.55))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, -8)
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
        // Balls spread evenly across the full width (a Spacer after each), with
        // the count at the right edge — no dead gap between the two.
        return HStack(spacing: 0) {
            ForEach(0..<GameState.livesMax, id: \.self) { i in
                // Diamond Balls owners: every slot is a filled diamond marble.
                lifeMarble(filled: unlimited || i < gameState.displayedLives,
                           diamond: unlimited)
                Spacer(minLength: 2)
            }
            if unlimited {
                Image(systemName: "infinity")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Self.diamondLifeGradient)
            } else {
                Text("\(gameState.displayedLives) / \(GameState.livesMax)")
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.75))
                    .lineLimit(1)
                    .fixedSize()
                if gameState.purchasedLives > 0 {
                    reservePouch
                        .padding(.leading, 4)
                }
            }
        }
        .padding(.bottom, 6)
    }

    /// The purchased reserve as a small pouch of red lives with "+N" on it, beside the
    /// row of life balls.  Tapping it explains the reserve in a short popover.
    /// Hidden (by the caller) when the reserve is zero.
    private var reservePouch: some View {
        let reserve = gameState.purchasedLives
        let explanation = "\(reserve) \(reserve == 1 ? "life" : "lives") in reserve. They're used when your free lives run out."
        return Button {
            showReserveInfo = true
        } label: {
            ZStack(alignment: .bottom) {
                LivesPackIcon(kind: .pouch, compact: true)
                    .frame(width: 30, height: 32)
                Text("+\(reserve)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.25, green: 0.16, blue: 0.0))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(red: 1.00, green: 0.85, blue: 0.32)))
                    .overlay(Capsule().stroke(Color(red: 0.55, green: 0.38, blue: 0.05), lineWidth: 0.6))
                    .offset(y: 4)
            }
            .frame(minWidth: 34, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(explanation)
        .accessibilityHint("Shows what the reserve is.")
        .popover(isPresented: $showReserveInfo, arrowEdge: .top) {
            Text(explanation)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 240, alignment: .leading)
                .padding(14)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// One life as a glossy marble — the same highlight-dot-and-rim recipe as
    /// the home screen's lives pill (HomeView.marbleIcon), so lives read as
    /// the familiar red ball here too instead of a flat disc.  An empty slot
    /// is a hollow outline, also matching the pill.
    private func lifeMarble(filled: Bool, diamond: Bool = false) -> some View {
        let size: CGFloat = 20
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

    /// Live status under the marble-row header: the next-life countdown while
    /// regen is active.  (The reserve is the pouch in the header; the earn
    /// rule sits under the title.)
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
                    // The reserve is the pouch beside the life balls, and
                    // the earn rule sits under the title — only the countdown
                    // is left here.
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
                // The Diamond ball cosmetic itself, with a cool glow — the
                // ball this purchase adds to the Locker.
                BallSkinView(skin: .diamond, diameter: 46)
                    .shadow(color: Color(red: 0.50, green: 0.85, blue: 1.0).opacity(0.6), radius: 6)
                    .frame(width: 56, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Diamond Balls")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Self.diamondGradient)
                    Text(isOwned ? "Active — indestructible, never run out."
                                 : "Unlimited lives, forever,\nplus the Diamond ball skin.")
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
                        Text(isOwned ? "Owned" : store.displayPrice(for: pid, fallback: "$49.99"))
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

    private static let diamondGradient = LinearGradient(
        colors: [Color(red: 0.86, green: 0.96, blue: 1.0),
                 Color(red: 0.55, green: 0.80, blue: 1.0),
                 Color(red: 0.80, green: 0.92, blue: 1.0)],
        startPoint: .leading, endPoint: .trailing)

    private var lifePackCards: some View {
        VStack(spacing: 10) {
            lifePackCard(pid: .lives20)
            lifePackCard(pid: .lives120)
            lifePackCard(pid: .lives300)
        }
    }

    /// The price of a lives pack as a number: the live App Store price once
    /// products have loaded, else the catalog price.
    private func livesPackPrice(_ pid: StoreKitManager.ProductID) -> Double {
        if let product = store.product(for: pid) {
            return NSDecimalNumber(decimal: product.price).doubleValue
        }
        switch pid {
        case .lives20:  return 1.99
        case .lives120: return 9.99
        case .lives300: return 19.99
        default:           return 0
        }
    }

    /// Percent saved per life against the smallest pack, from the real prices:
    ///   1 − (this pack's price ÷ its lives) ÷ (smallest pack's price ÷ its lives)
    /// rounded to a whole percent.  Nil for the smallest pack (it IS the base
    /// price) and whenever a pack is not actually cheaper per life.
    /// With today's prices ($1.99 / 20 = $0.0995 a life):
    ///   120 lives: $9.99 / 120  = $0.08325 → 1 − 0.08325 / 0.0995 = 16.3% → 16%
    ///   300 lives: $19.99 / 300 = $0.06663 → 1 − 0.06663 / 0.0995 = 33.0% → 33%
    /// Diamond Balls (unlimited) has no per-life price, so no savings figure.
    private func percentSaved(_ pid: StoreKitManager.ProductID) -> Int? {
        let smallest = StoreKitManager.ProductID.lives20
        guard pid != smallest, pid.rewardLives > 0, smallest.rewardLives > 0 else { return nil }
        let basePerLife = livesPackPrice(smallest) / Double(smallest.rewardLives)
        let thisPerLife = livesPackPrice(pid) / Double(pid.rewardLives)
        guard basePerLife > 0, thisPerLife > 0 else { return nil }
        let percent = Int(((1 - thisPerLife / basePerLife) * 100).rounded())
        return percent > 0 ? percent : nil
    }

    /// One lives pack, laid out like a coin pack on the Get Coins sheet: a
    /// container of red lives that is bigger for bigger packs, the number of lives, the
    /// percent saved (not on the smallest pack), and the price button.
    private func lifePackCard(pid: StoreKitManager.ProductID) -> some View {
        let inProgress = store.purchaseInProgress == pid
        let lives = pid.rewardLives
        let saved = percentSaved(pid)
        let priceText = store.displayPrice(for: pid, fallback: Self.fallbackPrice(pid))
        let spoken: String = saved.map { "Buy \(lives) lives for \(priceText). Save \($0) percent." }
            ?? "Buy \(lives) lives for \(priceText)."
        return HStack(alignment: .center, spacing: 12) {
            // Same frame for every pack; the container inside grows with the pack.
            LivesPackIcon(kind: Self.packIconKind(pid))
                .frame(width: 60, height: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(lives) Lives")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let saved {
                    Text("Save \(saved)%")
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
                    Text(priceText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                }
            }
            .buttonStyle(.plain)
            .disabled(inProgress)
            .accessibilityLabel(spoken)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.13))
        )
    }

    /// Pouch (20) → box (120) → chest (300).  Diamond Balls shows the
    /// Diamond ball itself (see `diamondBallsCard`).
    private static func packIconKind(_ pid: StoreKitManager.ProductID) -> LivesPackIcon.Kind {
        switch pid {
        case .lives120:  return .box
        case .lives300:  return .chest
        default:         return .pouch
        }
    }

    private static func fallbackPrice(_ pid: StoreKitManager.ProductID) -> String {
        switch pid {
        case .lives120: return "$9.99"
        case .lives300: return "$19.99"
        default:        return "$1.99"
        }
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
            // Amounts read from ProductID.rewardCoins — the single source of
            // truth for what each pack actually grants (100 / 600 / 1,300 /
            // 3,000 / 10,000, matching App Store Connect).
            coinCard(pid: .coins100,   amount: StoreKitManager.ProductID.coins100.rewardCoins)
            coinCard(pid: .coins600,   amount: StoreKitManager.ProductID.coins600.rewardCoins)
            coinCard(pid: .coins1300,  amount: StoreKitManager.ProductID.coins1300.rewardCoins)
            coinCard(pid: .coins3000,  amount: StoreKitManager.ProductID.coins3000.rewardCoins)
            coinCard(pid: .coins10000, amount: StoreKitManager.ProductID.coins10000.rewardCoins)
        }
    }

    /// % more coins than buying the same spend as base 100-coin ($0.99) packs,
    /// rounded DOWN to a whole percent so the label never overstates the deal.
    /// Nil for the base pack (it IS the base rate).  Base rate 100 / 0.99 =
    /// 101.01 coins per $:
    ///   600 / (101.01 × 4.99)    = 600 / 504.0     = 1.190 → +19%
    ///   1,300 / (101.01 × 9.99)  = 1,300 / 1,009.1 = 1.288 → +28%
    ///   3,000 / (101.01 × 19.99) = 3,000 / 2,019.2 = 1.486 → +48%
    ///   10,000 / (101.01 × 49.99) = 10,000 / 5,049.5 = 1.980 → +98%
    private func coinBonus(_ pid: StoreKitManager.ProductID, amount: Int) -> String? {
        let baseRate = Double(StoreKitManager.ProductID.coins100.rewardCoins) / 0.99   // coins per dollar at the base pack
        let price: Double
        switch pid {
        case .coins600:   price = 4.99
        case .coins1300:  price = 9.99
        case .coins3000:  price = 19.99
        case .coins10000: price = 49.99
        default:          return nil
        }
        let coinsIfBoughtAsBase = baseRate * price
        let pct = (Double(amount) / coinsIfBoughtAsBase - 1.0) * 100.0
        let whole = Int((pct + 1e-9).rounded(.down))
        return whole > 0 ? "+\(whole)% coins" : nil
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
                    // Top pack: shimmery-diamond bonus label instead of the
                    // plain green one.  Same honest math as the other packs
                    // (+98% at 10,000 coins for $49.99).
                    DiamondBonusLabel(text: bonus ?? "Best value")
                    // The pack's fixed bonus item, stated before purchase.
                    if !gameState.isOwned(BallSkin.moneyBall) {
                        Text("Includes the Money Ball skin")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.40, green: 0.82, blue: 0.52))
                    }
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
        case .coins100:                return "$0.99"
        case .lives20:                 return "$1.99"
        case .coins600:                return "$4.99"
        case .coins1300, .lives120:    return "$9.99"
        case .coins3000, .lives300:    return "$19.99"
        case .coins10000, .unlimited:  return "$49.99"
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

/// Lives-pack art for the Get Lives sheet.  Each pack is a different
/// container, so the size reads from the container alone:
///   .pouch (20 lives)  — a small cloth pouch, drawstring open, a few balls peeking out
///   .box   (120 lives) — a cardboard box, flaps open, filled with balls
///   .chest (300 lives) — a treasure chest, lid open, overflowing with balls
/// Every life ball is the same glossy red (the lives red used across the
/// sheet).  The
/// containers grow with the pack (about 0.58 / 0.76 / 0.90 of the
/// frame's width) while the balls stay one size, so bigger packs visibly hold
/// more.  `compact` draws the pouch filling its frame with larger balls — the
/// purchased-reserve badge beside the life balls.
/// Drawn in a Canvas from fixed layouts: still, no randomness, no assets.
struct LivesPackIcon: View {
    enum Kind { case pouch, box, chest }
    let kind: Kind
    var compact: Bool = false

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let r = max(2.2, s * (compact ? 0.12 : 0.075))
            // The containers are drawn standing on the frame's bottom edge,
            // so the art sat low in its row.  Shift it up so the drawn
            // content (from the top of the pile or lid down to the base) is
            // centered vertically in the frame.  The reserve badge (compact)
            // already fills its frame and is left as it was.
            if !compact {
                let bottom: CGFloat = size.height - 1
                let top: CGFloat = Self.contentTop(kind, size: size, r: r)
                ctx.translateBy(x: 0, y: size.height / 2 - (top + bottom) / 2)
            }
            switch kind {
            case .pouch: Self.drawPouch(&ctx, size: size, r: r, compact: compact)
            case .box:   Self.drawBox(&ctx, size: size, r: r)
            case .chest: Self.drawChest(&ctx, size: size, r: r)
            }
        }
    }

    /// Highest drawn point of each pack's art (top of the peeking balls, the
    /// back flap or pile, the lid), from the same numbers the draw
    /// functions use.
    private static func contentTop(_ kind: Kind, size: CGSize, r: CGFloat) -> CGFloat {
        let h: CGFloat = size.height
        let bottom: CGFloat = h - 1
        switch kind {
        case .pouch:
            let mouthY: CGFloat = bottom - h * 0.50 + r * 0.9
            return mouthY - r * 1.35 - r
        case .box:
            let hb: CGFloat = h * 0.40
            let top: CGFloat = bottom - hb
            let flapTop: CGFloat = top - hb * 0.62
            let pileTop: CGFloat = top + r * 0.55 - 2 * r * 1.62 - r
            return min(flapTop, pileTop)
        case .chest:
            let hc: CGFloat = h * 0.36
            let top: CGFloat = bottom - hc
            let lidTop: CGFloat = top - hc * 1.05
            let pileTop: CGFloat = top + r * 0.55 - 3 * r * 1.62 - r
            return min(lidTop, pileTop)
        }
    }

    // MARK: Balls

    /// The lives red, shaded like a glossy marble.
    private static let lifeRed = Gradient(colors: [
        Color(red: 1.00, green: 0.52, blue: 0.50),
        Color(red: 1.00, green: 0.32, blue: 0.32),
        Color(red: 0.78, green: 0.14, blue: 0.14),
    ])

    /// One red life ball.
    private static func lifeBall(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        let ball = Path(ellipseIn: rect)
        ctx.fill(ball, with: .radialGradient(
            lifeRed,
            center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.40),
            startRadius: 0, endRadius: r * 1.45))
        ctx.stroke(ball, with: .color(.black.opacity(0.35)), lineWidth: max(0.4, r * 0.12))
        let shine = CGRect(x: c.x - r * 0.62, y: c.y - r * 0.66, width: r * 0.56, height: r * 0.46)
        ctx.fill(Path(ellipseIn: shine), with: .color(.white.opacity(0.80)))
    }

    /// Ball centers for a heap whose bottom row sits at `baseY`, filling
    /// `minX...maxX` and narrowing by about a ball per row going up.
    /// Returned top row first, so lower (nearer) rows draw over higher ones.
    private static func heap(baseY: CGFloat, minX: CGFloat, maxX: CGFloat,
                             rows: Int, r: CGFloat) -> [CGPoint] {
        var byRow: [[CGPoint]] = []
        for row in 0..<rows {
            let inset: CGFloat = CGFloat(row) * r * 1.05
            let lo: CGFloat = minX + r + inset
            let hi: CGFloat = maxX - r - inset
            if hi < lo { break }
            let y: CGFloat = baseY - CGFloat(row) * r * 1.62
            let span: CGFloat = hi - lo
            let count: Int = max(1, Int(span / (r * 1.85)) + 1)
            var pts: [CGPoint] = []
            for i in 0..<count {
                let x: CGFloat = count > 1 ? lo + span * CGFloat(i) / CGFloat(count - 1) : (lo + hi) / 2
                pts.append(CGPoint(x: x, y: y))
            }
            byRow.append(pts)
        }
        return byRow.reversed().flatMap { $0 }
    }

    private static let outline = Color.black.opacity(0.35)

    // MARK: 20 lives — cloth pouch

    private static let clothFace = Gradient(colors: [
        Color(red: 0.50, green: 0.60, blue: 0.80),
        Color(red: 0.27, green: 0.34, blue: 0.54),
    ])
    private static let cord = Color(red: 0.96, green: 0.88, blue: 0.68)

    private static func drawPouch(_ ctx: inout GraphicsContext, size: CGSize,
                                  r: CGFloat, compact: Bool) {
        let w = size.width, h = size.height
        let cx = w / 2
        let bottom = h - 1
        let W: CGFloat = w * (compact ? 0.92 : 0.58)
        let H: CGFloat = h * (compact ? 0.80 : 0.50)
        let mouthY: CGFloat = bottom - H + r * 0.9
        let bodyTop: CGFloat = bottom - H * 0.70
        let mouthW: CGFloat = W * 0.70

        // Inside of the open mouth.
        let mouth = CGRect(x: cx - mouthW / 2, y: mouthY - H * 0.07, width: mouthW, height: H * 0.14)
        ctx.fill(Path(ellipseIn: mouth), with: .color(Color(red: 0.12, green: 0.14, blue: 0.24)))

        // A few balls peeking out of the mouth.
        let peek: [CGPoint] = [
            CGPoint(x: cx - r * 1.05, y: mouthY - r * 0.35),
            CGPoint(x: cx + r * 1.05, y: mouthY - r * 0.30),
            CGPoint(x: cx + r * 0.05, y: mouthY - r * 1.35),
        ]
        for p in peek { lifeBall(&ctx, p, r) }

        // Gathered neck, flaring up to the open mouth (covers the balls' lower halves).
        var neck = Path()
        neck.move(to: CGPoint(x: cx - mouthW / 2, y: mouthY))
        neck.addLine(to: CGPoint(x: cx - W * 0.20, y: bodyTop + H * 0.08))
        neck.addLine(to: CGPoint(x: cx + W * 0.20, y: bodyTop + H * 0.08))
        neck.addLine(to: CGPoint(x: cx + mouthW / 2, y: mouthY))
        neck.addQuadCurve(to: CGPoint(x: cx - mouthW / 2, y: mouthY),
                          control: CGPoint(x: cx, y: mouthY + H * 0.10))
        neck.closeSubpath()
        ctx.fill(neck, with: .linearGradient(clothFace,
                                             startPoint: CGPoint(x: cx, y: mouthY),
                                             endPoint: CGPoint(x: cx, y: bottom)))
        ctx.stroke(neck, with: .color(outline), lineWidth: 0.7)

        // Round body.
        let bodyRect = CGRect(x: cx - W / 2, y: bodyTop, width: W, height: bottom - bodyTop)
        let bodyPath = Path(roundedRect: bodyRect, cornerRadius: W * 0.42, style: .continuous)
        ctx.fill(bodyPath, with: .linearGradient(clothFace,
                                                 startPoint: CGPoint(x: cx, y: bodyTop),
                                                 endPoint: CGPoint(x: cx, y: bottom)))
        ctx.stroke(bodyPath, with: .color(outline), lineWidth: 0.8)
        // Stitched seam and a soft cloth highlight.
        let seam = bodyRect.insetBy(dx: W * 0.10, dy: (bottom - bodyTop) * 0.14)
        ctx.stroke(Path(roundedRect: seam, cornerRadius: W * 0.32, style: .continuous),
                   with: .color(.white.opacity(0.30)),
                   style: StrokeStyle(lineWidth: max(0.5, W * 0.025), dash: [W * 0.06, W * 0.05]))
        let gleam = CGRect(x: bodyRect.minX + W * 0.16, y: bodyRect.minY + bodyRect.height * 0.22,
                           width: W * 0.16, height: bodyRect.height * 0.30)
        ctx.fill(Path(ellipseIn: gleam), with: .color(.white.opacity(0.18)))

        // Drawstring around the neck, its two ends hanging loose (open).
        let tieY: CGFloat = bodyTop + H * 0.06
        let tieH: CGFloat = max(2, H * 0.08)
        let tie = CGRect(x: cx - W * 0.26, y: tieY - tieH / 2, width: W * 0.52, height: tieH)
        let tiePath = Path(roundedRect: tie, cornerRadius: tieH / 2)
        ctx.fill(tiePath, with: .color(cord))
        ctx.stroke(tiePath, with: .color(outline), lineWidth: 0.5)
        var ends = Path()
        ends.move(to: CGPoint(x: cx + W * 0.18, y: tieY))
        ends.addQuadCurve(to: CGPoint(x: cx + W * 0.30, y: tieY + H * 0.30),
                          control: CGPoint(x: cx + W * 0.36, y: tieY + H * 0.08))
        ends.move(to: CGPoint(x: cx + W * 0.22, y: tieY))
        ends.addQuadCurve(to: CGPoint(x: cx + W * 0.42, y: tieY + H * 0.22),
                          control: CGPoint(x: cx + W * 0.44, y: tieY + H * 0.02))
        ctx.stroke(ends, with: .color(cord),
                   style: StrokeStyle(lineWidth: max(0.8, W * 0.035), lineCap: .round))
    }

    // MARK: 120 lives — cardboard box

    private static let kraftFace = Gradient(colors: [
        Color(red: 0.86, green: 0.68, blue: 0.44),
        Color(red: 0.64, green: 0.46, blue: 0.26),
    ])
    private static let kraftFlap = Gradient(colors: [
        Color(red: 0.76, green: 0.58, blue: 0.36),
        Color(red: 0.90, green: 0.74, blue: 0.50),
    ])

    private static func drawBox(_ ctx: inout GraphicsContext, size: CGSize, r: CGFloat) {
        let w = size.width, h = size.height
        let W: CGFloat = w * 0.76
        let Hb: CGFloat = h * 0.40
        let left: CGFloat = (w - W) / 2
        let right: CGFloat = left + W
        let bottom: CGFloat = h - 1
        let top: CGFloat = bottom - Hb

        // Back flap, standing up behind the balls.
        let back = CGRect(x: left + W * 0.06, y: top - Hb * 0.62, width: W * 0.88, height: Hb * 0.66)
        ctx.fill(Path(back), with: .color(Color(red: 0.56, green: 0.40, blue: 0.22)))
        ctx.stroke(Path(back), with: .color(outline), lineWidth: 0.6)

        // Side flaps, folded open outward.
        var lf = Path()
        lf.move(to: CGPoint(x: left, y: top))
        lf.addLine(to: CGPoint(x: left - W * 0.13, y: top - Hb * 0.48))
        lf.addLine(to: CGPoint(x: left + W * 0.08, y: top - Hb * 0.56))
        lf.addLine(to: CGPoint(x: left + W * 0.18, y: top))
        lf.closeSubpath()
        var rf = Path()
        rf.move(to: CGPoint(x: right, y: top))
        rf.addLine(to: CGPoint(x: right + W * 0.13, y: top - Hb * 0.48))
        rf.addLine(to: CGPoint(x: right - W * 0.08, y: top - Hb * 0.56))
        rf.addLine(to: CGPoint(x: right - W * 0.18, y: top))
        rf.closeSubpath()
        for flap in [lf, rf] {
            ctx.fill(flap, with: .linearGradient(kraftFlap,
                                                 startPoint: CGPoint(x: left, y: top),
                                                 endPoint: CGPoint(x: left, y: top - Hb * 0.56)))
            ctx.stroke(flap, with: .color(outline), lineWidth: 0.6)
        }

        // Filled to the top with balls.
        for p in heap(baseY: top + r * 0.55, minX: left + 1, maxX: right - 1, rows: 3, r: r) {
            lifeBall(&ctx, p, r)
        }

        // Front face with packing tape.
        let front = CGRect(x: left, y: top, width: W, height: Hb)
        let frontPath = Path(roundedRect: front, cornerRadius: 1.5)
        ctx.fill(frontPath, with: .linearGradient(kraftFace,
                                                  startPoint: CGPoint(x: left, y: top),
                                                  endPoint: CGPoint(x: left, y: bottom)))
        let tape = CGRect(x: left + W * 0.42, y: top, width: W * 0.16, height: Hb)
        ctx.fill(Path(tape), with: .color(Color(red: 0.95, green: 0.84, blue: 0.62).opacity(0.75)))
        var rim = Path()
        rim.move(to: CGPoint(x: left, y: top + 0.5))
        rim.addLine(to: CGPoint(x: right, y: top + 0.5))
        ctx.stroke(rim, with: .color(.white.opacity(0.35)), lineWidth: 0.8)
        ctx.stroke(frontPath, with: .color(outline), lineWidth: 0.8)
    }

    // MARK: 300 lives — treasure chest

    private static let woodFace = Gradient(colors: [
        Color(red: 0.60, green: 0.40, blue: 0.20),
        Color(red: 0.40, green: 0.25, blue: 0.11),
    ])
    private static let woodLid = Gradient(colors: [
        Color(red: 0.52, green: 0.34, blue: 0.16),
        Color(red: 0.34, green: 0.21, blue: 0.09),
    ])
    private static let goldBand = Color(red: 0.93, green: 0.76, blue: 0.32)

    private static func drawChest(_ ctx: inout GraphicsContext, size: CGSize, r: CGFloat) {
        let w = size.width, h = size.height
        let W: CGFloat = w * 0.90
        let Hc: CGFloat = h * 0.36
        let left: CGFloat = (w - W) / 2
        let right: CGFloat = left + W
        let bottom: CGFloat = h - 1
        let top: CGFloat = bottom - Hc

        // Open lid, tipped back: its domed outside and its dark inside.
        let lidRect = CGRect(x: left + W * 0.02, y: top - Hc * 1.05, width: W * 0.96, height: Hc * 0.98)
        let lid = Path(roundedRect: lidRect, cornerRadius: W * 0.22, style: .continuous)
        ctx.fill(lid, with: .linearGradient(woodLid,
                                            startPoint: CGPoint(x: left, y: lidRect.minY),
                                            endPoint: CGPoint(x: left, y: lidRect.maxY)))
        ctx.stroke(lid, with: .color(outline), lineWidth: 0.8)
        let inside = lidRect.insetBy(dx: W * 0.07, dy: Hc * 0.14)
        ctx.fill(Path(roundedRect: inside, cornerRadius: W * 0.16, style: .continuous),
                 with: .color(Color(red: 0.36, green: 0.06, blue: 0.10)))
        var lidBand = Path()
        lidBand.move(to: CGPoint(x: lidRect.minX, y: lidRect.maxY - 1))
        lidBand.addLine(to: CGPoint(x: lidRect.maxX, y: lidRect.maxY - 1))
        ctx.stroke(lidBand, with: .color(goldBand), lineWidth: max(1.2, Hc * 0.10))

        // Heaped well above the rim.
        for p in heap(baseY: top + r * 0.55, minX: left - r * 0.2, maxX: right + r * 0.2, rows: 4, r: r) {
            lifeBall(&ctx, p, r)
        }

        // Chest base with gold bands and latch.
        let base = CGRect(x: left, y: top, width: W, height: Hc)
        let basePath = Path(roundedRect: base, cornerRadius: 2)
        ctx.fill(basePath, with: .linearGradient(woodFace,
                                                 startPoint: CGPoint(x: left, y: top),
                                                 endPoint: CGPoint(x: left, y: bottom)))
        let bandH: CGFloat = max(1.5, Hc * 0.14)
        ctx.fill(Path(CGRect(x: left, y: top, width: W, height: bandH)), with: .color(goldBand))
        let bandXs: [CGFloat] = [0.18, 0.82]
        for fx in bandXs {
            ctx.fill(Path(CGRect(x: left + W * fx - bandH / 2, y: top, width: bandH, height: Hc)),
                     with: .color(goldBand))
        }
        let latch = CGRect(x: left + W / 2 - Hc * 0.15, y: top + bandH * 0.4,
                           width: Hc * 0.30, height: Hc * 0.32)
        let latchPath = Path(roundedRect: latch, cornerRadius: 1.2)
        ctx.fill(latchPath, with: .color(goldBand))
        ctx.stroke(latchPath, with: .color(outline), lineWidth: 0.5)
        ctx.stroke(basePath, with: .color(outline), lineWidth: 0.8)

        // Overflowing: balls spilling over the front edge and onto the ground.
        lifeBall(&ctx, CGPoint(x: right - W * 0.30, y: top + r * 0.7), r)
        lifeBall(&ctx, CGPoint(x: left + r * 0.3, y: bottom - r), r)
        lifeBall(&ctx, CGPoint(x: right - r * 0.2, y: bottom - r), r)
    }

}

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

/// The bonus subtitle on the top coin pack (+98% at 10,000 coins for $49.99):
/// a cool diamond gradient with a highlight that sweeps across the glyphs.
/// Shown instead of the plain green bonus text so the best-value pack reads
/// as premium.
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

// MARK: - Starter Pack Sheet

/// One-time welcome offer: $1.99 → 500 coins + the Aurora ball, trail and
/// boundary (free-granted so Sell Back keeps but never refunds them).  Presented
/// automatically on the first app open after the tutorial set was picked
/// (`GameState.shouldTriggerStarterPack`), and again on re-launch while the
/// 48-hour window is open.  The sheet is exactly as tall as its content.  Purchase sets
/// `starterPackClaimed` (via reward delivery);
/// "No thanks" sets `starterPackDismissed`.  Either one closes the sheet and
/// keeps it from ever showing again — but ONLY delivery sets `claimed`, so an
/// Ask-to-Buy purchase approved after a dismissal still pays out in full.
struct StarterPackSheet: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var store:     StoreKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var purchaseError: String? = nil
    /// Measured height of the sheet's content.  The sheet uses it as its one
    /// detent, so it is exactly as tall as its content, anchored to the
    /// bottom of the screen, with no empty space below.
    @State private var contentHeight: CGFloat = 560

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
                        Text("Ball · Trail · Boundary — plus 500 coins")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 0.62, green: 0.45, blue: 0.98))
                            .padding(.bottom, 28)

                        // ── What you get ────────────────────────────────────
                        VStack(spacing: 10) {
                            rewardRow(icon: "sparkles", label: "Aurora ball, trail and boundary",
                                      detail: "Worth \(Self.itemsShopValue.formatted()) coins in the shop")
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
                        // Sets `dismissed`, NOT `claimed` — the claimed flag
                        // gates the once-only coin delivery, and a pending
                        // (Ask-to-Buy) purchase approved later must still
                        // deliver its coins after a dismissal.
                        Button {
                            AnalyticsClient.shared.track("starter_pack_dismissed")
                            gameState.starterPackDismissed = true
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
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        if abs(h - contentHeight) > 0.5 { contentHeight = h }
                    }
                }
                // Scrolls only if the content is taller than the screen.
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationBarHidden(true)
            .onChange(of: gameState.starterPackClaimed) { _, claimed in
                if claimed { dismiss() }   // rewards delivered (purchase/restore)
            }
            .onChange(of: gameState.starterPackDismissed) { _, dismissed in
                if dismissed { dismiss() }
            }
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.hidden)
        .onChange(of: store.lastError) { _, err in purchaseError = err }
        .alert("Purchase Failed", isPresented: Binding(
            get: { purchaseError != nil },
            set: { _ in purchaseError = nil; store.clearLastError() }
        ), actions: { Button("OK", role: .cancel) {} },
        message: { Text(purchaseError ?? "") })
    }

    /// Shop price of the three Starter Pack items, summed from their own
    /// `coinCost` so the figure can never drift from the catalogue.
    static var itemsShopValue: Int {
        let p = GameState.starterPackContents
        return p.balls.map(\.coinCost).reduce(0, +)
             + p.trails.map(\.coinCost).reduce(0, +)
             + p.boundaries.map(\.coinCost).reduce(0, +)
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
            // The top ($49.99) coin pack also includes the Money Ball skin the
            // first time — announce it in place of the usual subtitle.
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
