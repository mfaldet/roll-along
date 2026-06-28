import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var store:     StoreKitManager
    @ObservedObject private var auth = AppleAuthManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var showResetAlert = false
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
        .alert("Reset Progress?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) { gameState.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This wipes all level progress — stars, coins, and best times. Your cosmetics, nickname, and settings will be kept.")
        }
        .alert("Reset Cosmetics?", isPresented: $showCosmeticResetAlert) {
            Button("Reset", role: .destructive) {
                let r = gameState.liquidateCoinCosmetics()
                cosmeticResetMessage = r.coins > 0
                    ? "Reset your look to default and refunded \(r.coins) coins from \(r.count) cosmetic\(r.count == 1 ? "" : "s")."
                    : "Reset your look to the default red ball."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets your equipped look to the default (red ball, no trail), relocks every cosmetic you bought with coins, and refunds those coins. Cosmetics you earned (challenge-pack rewards) or that came with a purchase (the Diamond & Aurora skins) are kept — just unequipped. Your level progress is untouched. This can't be undone.")
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
                    Text("Primary Color")
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
                            Text("Re-activate past purchases on this device")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color(white: 0.42))
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
            sectionHeader("Danger Zone")
            Button {
                showResetAlert = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset Level Progress")
                        .font(.system(.body, design: .rounded))
                    Spacer()
                    Text("Level \(gameState.currentLevel)")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color(white: 0.4))
                }
                .foregroundStyle(Color(red: 0.95, green: 0.3, blue: 0.3))
                .padding()
                .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
            }
            Button {
                showCosmeticResetAlert = true
            } label: {
                HStack {
                    Image(systemName: "paintbrush.pointed")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset Cosmetics")
                            .font(.system(.body, design: .rounded))
                        Text(cosmetic.count > 0
                             ? "Reset look · refund \(cosmetic.count) coin item\(cosmetic.count == 1 ? "" : "s")"
                             : "Reset your look to default")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color(white: 0.4))
                    }
                    Spacer()
                    if cosmetic.coins > 0 {
                        HStack(spacing: 3) {
                            Text("+\(cosmetic.coins)")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Color(white: 0.4))
                            CoinIcon(size: 13)
                        }
                    }
                }
                .foregroundStyle(Color(red: 0.95, green: 0.3, blue: 0.3))
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

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(GameState())
            .environmentObject(StoreKitManager.shared)
    }
}
