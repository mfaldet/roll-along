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
    @State private var showFeedback = false
    #if DEBUG
    /// Debug builds only: the "All Collections" review gallery.
    @State private var showCollectionGallery = false
    #endif
    /// The screen Settings was opened from, recorded with feedback.
    var openedFrom: String = "Home"

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    gameSection
                    notificationsSection
                    accountSection
                    cosmeticsSection
                    purchasesSection
                    aboutSection
                    resetSection
                    #if DEBUG
                    debugSection
                    #endif
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
                let name = gameState.playerName.isEmpty ? "Roller" : gameState.playerName
                Task {
                    try? await SocialClient.shared.upsertMyProfile(
                        displayName:     name,
                        climbLevel:      gameState.highestUnlocked,
                        highestUnlocked: gameState.highestUnlocked,
                        totalStars:      gameState.totalStars,
                        coinsCollected:  gameState.totalCoins,
                        lives:           gameState.totalLives
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
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet(source: "Settings (from \(openedFrom))")
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
            Text("This sells back every cosmetic you bought with coins — including seasonal & limited-time pieces — for half their current coin value (never more than you paid), and resets your equipped look to default. Kept, just unequipped: your Iconic items (the classic starter look and secret rewards like Diamond, Money & Trophy) and anything you were given (the tutorial gift, Challenge Track rewards, the Starter Pack). Heads up: seasonal pieces may not be re-buyable once their event ends. Your level progress is untouched.")
        }
    }

    /// Delete the player's account server-side, then drop the local session.
    @MainActor
    private func performAccountDeletion() async {
        isDeletingAccount = true
        deleteAccountError = nil
        // Re-confirm with Apple first.  That yields a one-time code the server
        // uses to revoke the Sign in with Apple token as part of deletion.
        // Canceling Apple's sheet cancels the deletion; if Apple cannot
        // provide a code for any other reason the account is still deleted.
        var appleCode: String? = nil
        switch await auth.requestAuthorizationCode() {
        case .code(let code): appleCode = code
        case .cancelled:
            deleteAccountError = "Account not deleted. Confirm with Apple to finish deleting your account."
            isDeletingAccount = false
            return
        case .unavailable:    appleCode = nil
        }
        do {
            try await SocialClient.shared.deleteMyAccount(appleAuthorizationCode: appleCode)
            auth.signOut()
        } catch {
            deleteAccountError = "Couldn't delete your account. Check your connection and try again."
        }
        isDeletingAccount = false
    }

    // MARK: - Sections

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
                        Text("Your Adventure level appears on leaderboards.")
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

                // Public trophy showcase toggle (S3-T9; design.md §7 / D6 —
                // default ON for signed-in players). Off = delete the showcase
                // server-side; on = publish the curated projection.
                Toggle(isOn: $gameState.trophyShowcaseEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Show Trophies on Profile")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color(white: 0.75))
                            Text("Share your grade counts and top trophies on your public profile")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color(white: 0.42))
                        }
                    } icon: {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .tint(Color(red: 0.20, green: 0.50, blue: 0.96))
                .padding()
                .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
                .onChange(of: gameState.trophyShowcaseEnabled) { _, on in
                    let engine = gameState.trophyEngine
                    Task { await TrophySyncService.shared.syncShowcase(engine: engine, enabled: on) }
                }

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

                Text("Permanently remove your profile, friends, clan membership, and leaderboard standing.\nUnlocked items, cosmetic, coins all stay on this device.")
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

                    Text("Optional. Sign in to climb the global leaderboard, add friends, and join a clan to share lives with clanmates. Your level progress is always saved on this device either way.")
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
            Text("This permanently deletes your account and all its data — profile, friends, clan membership, and leaderboard standing. This can't be undone. Apple will ask you to confirm once more.")
        }
    }

    private var gameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Game")

            VStack(spacing: 0) {
                Toggle(isOn: $gameState.tapToStart) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Tap to Start")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color(white: 0.75))
                            Text(gameState.tapToStart
                                 ? "A level waits until you tap"
                                 : "Auto Start: a level begins by itself")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color(white: 0.42))
                        }
                    } icon: {
                        Image(systemName: gameState.tapToStart
                              ? "hand.tap.fill"
                              : "play.circle.fill")
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .tint(Color(red: 0.20, green: 0.50, blue: 0.96))
                .padding()

                Divider().background(Color(white: 0.22)).padding(.leading, 16)

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

    // Opt-in local notifications.  Default OFF; flipping one ON asks for system
    // permission.  Scheduling itself lives in GameState (recordShopViewed /
    // reconcileLivesNotification) → NotificationManager.
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Notifications")

            VStack(spacing: 0) {
                Toggle(isOn: $gameState.shopFreshNotifEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Shop Restock")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color(white: 0.75))
                            Text("Once when the shop has fresh items since you last looked")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color(white: 0.42))
                        }
                    } icon: {
                        Image(systemName: "bag.fill")
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .tint(Color(red: 0.20, green: 0.50, blue: 0.96))
                .padding()
                .onChange(of: gameState.shopFreshNotifEnabled) { _, on in
                    if on { NotificationManager.shared.requestAuthorization() }
                    else  { NotificationManager.shared.cancelShopFresh() }
                }

                Divider().background(Color(white: 0.22)).padding(.leading, 16)

                Toggle(isOn: $gameState.livesFullNotifEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Lives Full")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color(white: 0.75))
                            Text("When your lives refill to 10")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color(white: 0.42))
                        }
                    } icon: {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .tint(Color(red: 0.20, green: 0.50, blue: 0.96))
                .padding()
                .onChange(of: gameState.livesFullNotifEnabled) { _, on in
                    if on {
                        NotificationManager.shared.requestAuthorization()
                        gameState.reconcileLivesNotification()
                    } else {
                        NotificationManager.shared.cancelLivesFull()
                    }
                }
            }
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
        }
    }

    private var purchasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Purchases")
            // Restore Purchases is App Store–required for non-consumable IAPs
            // (Unlimited Lives, Starter Pack) — re-activates them on a new device
            // / after a reinstall, and reports a clear result.
            Button {
                Task { await restorePurchases() }
            } label: {
                HStack(spacing: 8) {
                    if isRestoring {
                        ProgressView().tint(Color(red: 1.0, green: 0.60, blue: 0.20))
                    }
                    Text(isRestoring ? "Restoring…" : "Restore Purchases")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Color(red: 1.0, green: 0.60, blue: 0.20))   // orange
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(white: 0.12).clipShape(RoundedRectangle(cornerRadius: 14)))
            }
            .disabled(isRestoring)

            Text("New device? Your purchases are always yours.\nTap to restore anything you've bought with real money.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
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
        } else if gameState.unlimitedLives || gameState.starterPackClaimed {
            // Both restorable purchases count: Diamond Balls and the Starter Pack.
            var restored: [String] = []
            if gameState.unlimitedLives     { restored.append("Diamond Balls (unlimited lives)") }
            if gameState.starterPackClaimed { restored.append("Starter Pack") }
            restoreResultMessage = "Restore complete — active on this device: "
                + restored.joined(separator: " and ") + "."
        } else {
            restoreResultMessage = "Restore complete. No previous purchases were found to restore."
        }
        showRestoreResult = true
    }

    // ── Cosmetics — beneficial: sell coin-bought cosmetics back for the coins
    //    paid and tidy the locker.  Recoverable (re-buy anything anytime), so
    //    it sits with the friendly sections, above Purchases.
    // Privacy policy + contact (App Review Guideline 5.1.1(i): the policy must be
    // reachable inside the app; 1.2 / 2.5.18: published contact details).
    private static let privacyPolicyURL = URL(string: "https://mfaldet.github.io/roll-along/privacy.html")!
    private static let contactURL = URL(string: "mailto:rollalongsupport@gmail.com?subject=Roll%20Along%20support")!

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("About")
            VStack(spacing: 0) {
                Link(destination: Self.privacyPolicyURL) {
                    aboutRow(icon: "hand.raised.fill", title: "Privacy Policy")
                }
                Divider().background(Color(white: 0.22)).padding(.leading, 16)
                Link(destination: Self.contactURL) {
                    aboutRow(icon: "envelope.fill", title: "Contact Us")
                }
                Divider().background(Color(white: 0.22)).padding(.leading, 16)
                Button { showFeedback = true } label: {
                    aboutRow(icon: "bubble.left.and.exclamationmark.bubble.right.fill",
                             title: "Send Feedback", trailing: "chevron.right")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Report a bug, share an idea, ask a question or pay a compliment")
            }
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))

            Text("Questions, a problem with an ad, or a concern about another player? Contact us and we'll help.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
    }

    #if DEBUG
    /// Debug builds only — never compiled into a release build.
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Debug")
            Button { showCollectionGallery = true } label: {
                aboutRow(icon: "square.grid.3x3.fill", title: "All Collections", trailing: "chevron.right")
            }
            .buttonStyle(.plain)
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
            Text("Review gallery: every collection with its real art. Nothing here buys, grants or equips anything.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
        .fullScreenCover(isPresented: $showCollectionGallery) {
            CollectionReviewGallery()
                .environmentObject(gameState)
        }
    }
    #endif

    private func aboutRow(icon: String, title: String,
                          trailing: String = "arrow.up.right") -> some View {
        HStack {
            Label {
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color(white: 0.75))
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(Color(white: 0.55))
            }
            Spacer()
            Image(systemName: trailing)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(white: 0.4))
        }
        .padding()
        .contentShape(Rectangle())
    }

    private var cosmeticsSection: some View {
        let cosmetic = gameState.coinLiquidationPreview()
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Cosmetics")
            Button {
                showCosmeticResetAlert = true
            } label: {
                Text("Sell Back Cosmetics")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color(white: 0.9))   // uncolored
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.12).clipShape(RoundedRectangle(cornerRadius: 14)))
            }
            .disabled(cosmetic.count == 0 && gameState.isLoadoutDefault)
            .opacity(cosmetic.count == 0 && gameState.isLoadoutDefault ? 0.5 : 1)

            Text("Tidy up your locker.\nRemove cosmetics you've bought with coin, sell them back for half their current value.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
            if let m = cosmeticResetMessage {
                Text(m)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(red: 0.3, green: 0.8, blue: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // ── Danger Zone — the one destructive, unrecoverable reset, gated behind a
    //    typed "STARTOVER" confirmation. ──
    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Danger Zone")
            Button {
                showResetConfirm = true
            } label: {
                Text("Reset Level Progress")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.3, blue: 0.3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.12).clipShape(RoundedRectangle(cornerRadius: 14)))
            }

            Text("Reset your Roll Along core game level progress.\nKeeps settings, cosmetics, and all other game progress, awards and rankings.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 22, weight: .semibold, design: .rounded))
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

// ===========================================================================
// Preset-name pickers — shared by Settings (nickname) and Clans (clan name).
// Word lists and rules live in `PresetNames` (SocialClient.swift).
// ===========================================================================

/// Wheels: first word · second word, and — when `numbers` is given — a
/// number.  Nicknames have no number (two wheels); clan names do (three).
struct PresetNameWheels: View {
    @Binding var choice: PresetNames.Choice
    let adjectives: [String]
    let nouns: [String]
    var numbers: [Int] = []

    var body: some View {
        HStack(spacing: 0) {
            Picker("First word", selection: $choice.adjective) {
                ForEach(0..<adjectives.count, id: \.self) { i in
                    Text(adjectives[i]).lineLimit(1).minimumScaleFactor(0.6).tag(i)
                }
            }
            Picker("Second word", selection: $choice.noun) {
                ForEach(0..<nouns.count, id: \.self) { i in
                    Text(nouns[i]).lineLimit(1).minimumScaleFactor(0.6).tag(i)
                }
            }
            if !numbers.isEmpty {
                Picker("Number", selection: $choice.number) {
                    ForEach(numbers, id: \.self) { n in
                        Text(String(n)).tag(n)
                    }
                }
                .frame(maxWidth: 90)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 150)
        .environment(\.colorScheme, .dark)
    }
}

/// Profile → Nickname.  Saves a preset-built nickname locally and, when the
/// player is signed in, to their public profile.
struct NicknamePickerSheet: View {
    @EnvironmentObject var gameState: GameState
    @Environment(\.dismiss) private var dismiss
    @State private var choice = PresetNames.randomNicknameChoice()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                VStack(spacing: 18) {
                    // Preview exactly as other players will see it: the two
                    // words with the Adventure level beside them.
                    PlayerNameLabel(name: PresetNames.nickname(choice),
                                    level: gameState.highestUnlocked,
                                    font: .system(size: 28, weight: .bold, design: .rounded),
                                    tint: gameState.primaryColor)
                        .padding(.top, 12)
                    PresetNameWheels(choice: $choice,
                                     adjectives: PresetNames.adjectives,
                                     nouns: PresetNames.nouns)
                    Button {
                        choice = PresetNames.randomNicknameChoice()
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Capsule().fill(Color(white: 0.2)))
                    }
                    .buttonStyle(.plain)
                    Text("Pick two words. Your Adventure level is shown next to your name. Other players see it on leaderboards, in clans and on your profile. Names are not unique.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Nickname")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.foregroundStyle(.white)
                }
            }
            .onAppear {
                if let current = PresetNames.parseNickname(gameState.playerName) { choice = current }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let name = PresetNames.nickname(choice)
        gameState.playerName = name
        if SocialClient.shared.isSignedIn {
            let level = gameState.highestUnlocked
            let stars = gameState.totalStars
            let coins = gameState.totalCoins
            let lives = gameState.totalLives
            Task {
                try? await SocialClient.shared.upsertMyProfile(
                    displayName:     name,
                    climbLevel:      level,
                    highestUnlocked: level,
                    totalStars:      stars,
                    coinsCollected:  coins,
                    lives:           lives
                )
            }
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(GameState())
            .environmentObject(StoreKitManager.shared)
    }
}

/// Settings → Send Feedback. The player picks a kind and writes a message
/// (up to 1,000 characters). App version, iOS version, phone model, the
/// screen they came from and — if signed in — their player id are added
/// quietly; see `FeedbackOutbox` in SocialClient.swift. Nothing they write
/// is shown to other players.
struct FeedbackSheet: View {
    let source: String

    @Environment(\.dismiss) private var dismiss
    @State private var kind: FeedbackKind = .bug
    @State private var message = ""
    @State private var sent = false
    @State private var limitReached = !FeedbackOutbox.shared.canSubmit
    @FocusState private var editorFocused: Bool

    private var trimmed: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSend: Bool { !trimmed.isEmpty && !limitReached }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.09).ignoresSafeArea()
                if sent {
                    thankYou
                } else {
                    form
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                kindPicker

                Text(prompt)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $message)
                        .focused($editorFocused)
                        .scrollContentBackground(.hidden)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minHeight: 180)
                        .padding(8)
                        .onChange(of: message) { _, new in
                            if new.count > FeedbackOutbox.maxLength {
                                message = String(new.prefix(FeedbackOutbox.maxLength))
                            }
                        }
                    if message.isEmpty {
                        Text("Write your message here")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color(white: 0.4))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 12)))

                HStack(alignment: .top) {
                    Text("Your app version, iOS version and phone model are included. Nothing you write is shown to other players.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(white: 0.45))
                    Spacer(minLength: 8)
                    Text("\(message.count)/\(FeedbackOutbox.maxLength)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(message.count >= FeedbackOutbox.maxLength
                                         ? Color.orange : Color(white: 0.45))
                }

                if limitReached {
                    Text("You've sent \(FeedbackOutbox.maxPerDay) messages in the last day. Please try again tomorrow.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.orange)
                }

                Button(action: send) {
                    Text("Send")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(canSend ? .white : Color(white: 0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background((canSend ? Color.blue : Color(white: 0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 12)))
                }
                .disabled(!canSend)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { editorFocused = true }
    }

    /// Four tiles, icon over title: Bug, Idea, Question, Compliment.
    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(FeedbackKind.allCases) { k in
                kindTile(k)
            }
        }
    }

    private func kindTile(_ k: FeedbackKind) -> some View {
        let selected: Bool = k == kind
        return Button { kind = k } label: {
            VStack(spacing: 6) {
                Image(systemName: k.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(k.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(selected ? Color.black : Color(white: 0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.white : Color(white: 0.16))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(k.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var prompt: String {
        switch kind {
        case .bug:        return "What happened, and what were you doing just before?"
        case .idea:       return "What would make Roll Along better?"
        case .question:   return "What would you like to know? We read every message."
        case .compliment: return "What do you enjoy? We'd love to hear it."
        }
    }

    private var thankYou: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Thank you!")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text("We got your message. If you're offline, it will be sent the next time you're connected.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color(white: 0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func send() {
        switch FeedbackOutbox.shared.submit(kind: kind, message: message, source: source) {
        case .queued:
            editorFocused = false
            withAnimation { sent = true }
            AnalyticsClient.shared.track("feedback_sent",
                                         properties: ["kind": .string(kind.rawValue)])
        case .limitReached:
            limitReached = true
        case .empty:
            break
        }
    }
}

#if DEBUG
// ---------------------------------------------------------------------------
// CollectionReviewGallery — DEBUG BUILDS ONLY (Settings → Debug → All
// Collections).  A review tool for looking at every collection's real art.
//
// It lists Roll Along plus every catalogue collection — on sale, retired and
// seasonal, released or not — straight from `CosmeticBundle` data, so new or
// changed pieces show up with no edits here.  Every piece is drawn large by
// the same code the game uses, with its live animation, and "Try full set"
// plays the gameplay replay with the whole set on.
//
// READ-ONLY: it never buys, grants, equips or changes ownership.
// ---------------------------------------------------------------------------
struct CollectionReviewGallery: View {
    @EnvironmentObject var gameState: GameState
    @Environment(\.dismiss) private var dismiss
    @State private var tryOnID: String?

    private var bundles: [CosmeticBundle] { [CosmeticBundle.rollAlong] + CosmeticBundle.catalogue }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text("\(bundles.count) collections · debug build only · nothing here changes what you own")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.55))
                    ForEach(bundles) { bundle in
                        card(bundle)
                    }
                }
                .padding(16)
            }
            .background(Color(white: 0.08).ignoresSafeArea())
            .navigationTitle("All Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        // Pieces animate as they do in a Shop preview (and stop under Reduce Motion).
        .environment(\.cosmeticMotion, .preview)
        .preferredColorScheme(.dark)
    }

    private func status(_ b: CosmeticBundle) -> String {
        if b.isRollAlong { return "Iconic · owned by everyone" }
        var parts: [String] = []
        parts.append(b.isLimitedTime ? "Seasonal" : (b.isRetired ? "Retired" : "On sale"))
        if b.isLimitedTime && b.isRetired { parts.append("retired as a set") }
        parts.append(CosmeticSchedule.isReleased(b) ? "released" : "not released yet")
        return parts.joined(separator: " · ")
    }

    private func card(_ b: CosmeticBundle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(b.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(b.isRollAlong ? "Free" : "\(b.fullPrice()) coins")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.75))
            }
            Text("id \(b.id) · \(b.rarity.label) · \(status(b))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.55))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(b.balls) { piece("Ball", $0) }
                    ForEach(b.goals) { piece("Goal", $0) }
                    ForEach(b.trails) { piece("Trail", $0) }
                    ForEach(b.floors) { piece("Floor", $0) }
                    ForEach(b.pits) { piece("Pit", $0) }
                    ForEach(b.boundaries) { piece("Boundary", $0) }
                }
            }

            if tryOnID == b.id {
                // The live gameplay replay with the whole set swapped in.
                // Slots the set leaves empty keep the equipped piece.
                LoadoutDiorama(loadout: Loadout(equippedIn: gameState).trying(bundle: b))
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
            }
            Button {
                tryOnID = (tryOnID == b.id) ? nil : b.id
            } label: {
                Label(tryOnID == b.id ? "Hide preview" : "Try full set",
                      systemImage: tryOnID == b.id ? "eye.slash.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color(white: 0.20)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.13)))
    }

    private func piece<Item: CosmeticItem>(_ slot: String, _ item: Item) -> some View {
        VStack(spacing: 6) {
            CosmeticTile(item: item, diameter: 104, corner: 14, trailWidth: 9)
                .frame(width: 112, height: 112)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.09)))
            Text(item.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("\(slot) · \(item.rarityLabel) · \(item.coinCost)")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.5))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 112)
    }
}
#endif
