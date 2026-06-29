import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var store:     StoreKitManager
    @ObservedObject private var auth = AppleAuthManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var showResetConfirm = false
    @State private var showCosmeticResetAlert = false
    @State private var cosmeticResetMessage: String?
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showRestoreResult = false
    @State private var restoreResultMessage = ""
    @State private var isRestoring = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    personalizationSection
                    gameSection
                    accountSection
                    purchasesSection
                    resetSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            // After a successful Apple sign-in, publish the player's current
            // profile so they appear on leaderboards immediately (rather than
            // waiting for their next level clear to PATCH progress).
            auth.onSignedIn = { [weak gameState] in
                guard let gameState else { return }
                let name = gameState.playerName.isEmpty ? "Climber" : gameState.playerName
                Task {
                    try? await SocialClient.shared.upsertMyProfile(
                        displayName:     name,
                        climbLevel:      gameState.highestUnlocked,
                        highestUnlocked: gameState.highestUnlocked,
                        totalStars:      gameState.totalStars,
                        coinsCollected:  gameState.totalCoins,
                        lives:           gameState.lives
                    )
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(.white)
            }
        }
        .sheet(isPresented: $showResetConfirm) {
            ResetProgressConfirmSheet(currentLevel: gameState.currentLevel) {
                gameState.resetProgress()
            }
        }
        .alert("Sell Back Cosmetics?", isPresented: $showCosmeticResetAlert) {
            Button("Sell Back") {
                let r = gameState.liquidateCoinCosmetics()
                cosmeticResetMessage = r.coins > 0
                    ? "Sold back \(r.count) cosmetic\(r.count == 1 ? "" : "s") for \(r.coins) coins and reset your look to default."
                    : "Reset your look to the default red ball."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This returns the cosmetics you bought with coins for a full refund and resets your equipped look to default — handy for tidying your locker and freeing up coins to spend on something new. Earned cosmetics (challenge-pack rewards) and ones that came with a purchase (Diamond & Aurora) are kept, just unequipped. You can re-buy anything anytime. Your level progress is untouched.")
        }
    }

    /// Delete the player's account server-side, then drop the local session.
    @MainActor
    private func performAccountDeletion() async {
        isDeletingAccount = true
        deleteAccountError = nil
        do {
            try await SocialClient.shared.deleteMyAccount()
            auth.signOut()
        } catch {
            deleteAccountError = "Couldn't delete your account. Check your connection and try again."
        }
        isDeletingAccount = false
    }

    // MARK: - Sections

    private var personalizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Personalization")
            HStack {
                Text("Nickname")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color(white: 0.75))
                Spacer()
                TextField("Enter a nickname", text: $gameState.playerName)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { nameFocused = false }
            }
            .padding()
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))

            ColorPicker(selection: Binding(get:  { gameState.primaryColor },
                                           set:  { gameState.primaryColor = $0 }),
                        supportsOpacity: false) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Accent Color")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color(white: 0.75))
                    Text("Outlines your nickname in competitive games")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(white: 0.42))
                }
            }
            .padding()
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
        }
    }

    // MARK: - Account (Sign in with Apple)

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Account")

            if auth.isSignedIn {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.45))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Your climb appears on leaderboards.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color(white: 0.45))
                    }
                    Spacer()
                    Button("Sign Out") { auth.signOut() }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.45))
                }
                .padding()
                .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))

                // Account deletion — required by App Store Guideline 5.1.1(v)
                // for any app that supports account creation.
                Button(role: .destructive) {
                    showDeleteAccountAlert = true
                } label: {
                    HStack(spacing: 8) {
                        if isDeletingAccount {
                            ProgressView().tint(Color(red: 0.95, green: 0.32, blue: 0.32))
                        }
                        Text(isDeletingAccount ? "Deleting…" : "Delete Account")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    }
                    .foregroundStyle(Color(red: 0.95, green: 0.32, blue: 0.32))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.12).clipShape(RoundedRectangle(cornerRadius: 14)))
                }
                .disabled(isDeletingAccount)

                if let err = deleteAccountError {
                    Text(err)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.45))
                }

                Text("Deleting your account permanently removes your profile, friends, clan membership, and leaderboard standing. Your level progress stays on this device.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(white: 0.45))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        auth.startSignIn()
                    } label: {
                        HStack(spacing: 8) {
                            if auth.isWorking {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 17, weight: .medium))
                            }
                            Text(auth.isWorking ? "Signing in…" : "Sign in with Apple")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.clipShape(RoundedRectangle(cornerRadius: 14)))
                    }
                    .disabled(auth.isWorking)

                    Text("Optional. Sign in to climb the global leaderboard, join clans, and send friends extra lives. Your level progress is always saved on this device either way.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(white: 0.45))

                    if let err = auth.lastError {
                        Text(err)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.45))
                    }
                }
            }
        }
        // Attached here (not on `body`, which already owns the Reset alert) —
        // SwiftUI presents only one alert per view, so two on the same view
        // would silently swallow the second.
        .alert("Delete Account?", isPresented: $showDeleteAccountAlert) {
            Button("Delete", role: .destructive) { Task { await performAccountDeletion() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and all its data — profile, friends, clan membership, and leaderboard standing. This can't be undone.")
        }
    }

    private var gameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Game")

            VStack(spacing: 0) {
                Toggle(isOn: $gameState.ballStartsAtTop) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Ball Starts at Top")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color(white: 0.75))
                            Text(gameState.ballStartsAtTop
                                 ? "Goal is at the bottom"
                                 : "Goal is at the top")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color(white: 0.42))
                        }
                    } icon: {
                        Image(systemName: gameState.ballStartsAtTop
                              ? "arrow.down.circle.fill"
                              : "arrow.up.circle.fill")
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .tint(Color(red: 0.20, green: 0.50, blue: 0.96))
                .padding()

                Divider().background(Color(white: 0.22)).padding(.leading, 16)

                Toggle(isOn: $gameState.hapticsEnabled) {
                    Label {
                        Text("Haptic Feedback")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color(white: 0.75))
                    } icon: {
                        Image(systemName: "hand.tap.fill")
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .tint(Color(red: 0.20, green: 0.50, blue: 0.96))
                .padding()

                Divider().background(Color(white: 0.22)).padding(.leading, 16)

                Toggle(isOn: $gameState.soundEnabled) {
                    Label {
                        Text("Sound Effects")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color(white: 0.75))
                    } icon: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .tint(Color(red: 0.20, green: 0.50, blue: 0.96))
                .padding()

                Divider().background(Color(white: 0.22)).padding(.leading, 16)

                Toggle(isOn: $gameState.introEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Opening Animation")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color(white: 0.75))
                            Text("Play the cinematic intro when the app opens")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color(white: 0.42))
                        }
                    } icon: {
                        Image(systemName: "movieclapper")
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .tint(Color(red: 0.20, green: 0.50, blue: 0.96))
                .padding()
            }
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
        }
    }

    private var purchasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Purchases")
            VStack(spacing: 0) {
                // Restore Purchases is App Store–required for non-consumable IAPs
                // (Unlimited Lives, Starter Pack). It re-activates them on a new
                // device / after a reinstall, and now reports a clear result so
                // it never feels like a dead button.
                Button {
                    Task { await restorePurchases() }
                } label: {
                    HStack(spacing: 12) {
                        if isRestoring {
                            ProgressView().tint(Color(white: 0.6))
                                .frame(width: 18)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Color(white: 0.55))
                                .frame(width: 18)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isRestoring ? "Restoring…" : "Restore Purchases")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color(white: 0.85))
                            Text("Brings back anything you bought with real money — Unlimited Lives and the Starter Pack — on a new phone or after reinstalling. Won't touch your coins or cosmetics.")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color(white: 0.42))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding()
                }
                .disabled(isRestoring)
            }
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
        }
        .alert("Restore Purchases", isPresented: $showRestoreResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreResultMessage)
        }
    }

    /// Run the StoreKit restore and surface a clear result (the old button gave
    /// no feedback, which is why it felt like it "did nothing").
    private func restorePurchases() async {
        isRestoring = true
        await store.restore()
        isRestoring = false
        if store.lastError?.hasPrefix("Restore") == true {
            restoreResultMessage = store.lastError
                ?? "Restore failed. Check your connection and try again."
        } else if gameState.unlimitedLives {
            restoreResultMessage = "Restore complete — your purchases are active on this device."
        } else {
            restoreResultMessage = "Restore complete. No previous purchases were found to restore."
        }
        showRestoreResult = true
    }

    private var resetSection: some View {
        let cosmetic = gameState.coinLiquidationPreview()
        return VStack(alignment: .leading, spacing: 12) {
            // ── Cosmetics — beneficial: sell coin-bought cosmetics back for a
            //    full refund and tidy the locker.  Sits ABOVE the Danger Zone
            //    because it's recoverable (re-buy anything anytime), so it gets
            //    an inviting, non-alarming treatment.
            sectionHeader("Cosmetics")
            Button {
                showCosmeticResetAlert = true
            } label: {
                HStack {
                    Image(systemName: "arrow.uturn.backward.circle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sell Back Cosmetics")
                            .font(.system(.body, design: .rounded))
                        Text(cosmetic.count > 0
                             ? "Sell the cosmetics you bought with coins back for a full refund and tidy your locker."
                             : "Return your equipped look to the default.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color(white: 0.45))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Keeps the cosmetics you earned or bought with cash — re-buy anything anytime.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color(white: 0.38))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if cosmetic.coins > 0 {
                        HStack(spacing: 3) {
                            Text("+\(cosmetic.coins)")
                                .font(.system(.footnote, design: .rounded).weight(.semibold))
                            CoinIcon(size: 13)
                        }
                        .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.32))
                    }
                }
                .foregroundStyle(Color(white: 0.9))
                .padding()
                .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
            }
            .disabled(cosmetic.count == 0 && gameState.isLoadoutDefault)
            .opacity(cosmetic.count == 0 && gameState.isLoadoutDefault ? 0.5 : 1)
            if let m = cosmeticResetMessage {
                Text(m)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(red: 0.3, green: 0.8, blue: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // ── Danger Zone — the one destructive, unrecoverable reset, gated
            //    behind a typed "STARTOVER" confirmation. ──
            sectionHeader("Danger Zone")
                .padding(.top, 10)
            Button {
                showResetConfirm = true
            } label: {
                HStack(alignment: .top) {
                    Image(systemName: "arrow.counterclockwise")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset Level Progress")
                            .font(.system(.body, design: .rounded))
                        Text("Wipes every level back to Level 1 — keeps your cosmetics, nickname & settings. Can't be undone.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color(red: 0.78, green: 0.42, blue: 0.42))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text("Level \(gameState.currentLevel)")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color(white: 0.4))
                }
                .foregroundStyle(Color(red: 0.95, green: 0.3, blue: 0.3))
                .padding()
                .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .kerning(1.5)
            .foregroundStyle(Color(white: 0.45))
    }

}

/// Typed-confirmation sheet for the unrecoverable "Reset Level Progress" action:
/// the player must type STARTOVER exactly before the Reset button enables, so the
/// wipe can't happen on a stray tap.
private struct ResetProgressConfirmSheet: View {
    let currentLevel: Int
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines) == "STARTOVER"
    }
    private let danger = Color(red: 0.95, green: 0.3, blue: 0.3)

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(danger)
                .padding(.top, 28)

            Text("Reset Level Progress?")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            Text("This wipes all level progress — stars, coins, and best times — and drops you back to Level 1 (you're on Level \(currentLevel)). Your cosmetics, nickname, and settings are kept. This can't be undone.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Type STARTOVER to confirm")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(white: 0.5))
                TextField("STARTOVER", text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color(white: 0.12).clipShape(RoundedRectangle(cornerRadius: 10)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(matches ? danger : Color(white: 0.22), lineWidth: 1)
                    )
            }

            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(white: 0.16).clipShape(RoundedRectangle(cornerRadius: 12)))
                        .foregroundStyle(.white)
                }
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("Reset")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background((matches ? danger : Color(white: 0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 12)))
                        .foregroundStyle(matches ? .white : Color(white: 0.45))
                }
                .disabled(!matches)
            }
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.09).ignoresSafeArea())
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(GameState())
            .environmentObject(StoreKitManager.shared)
    }
}
