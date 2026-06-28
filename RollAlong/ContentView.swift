import SwiftUI

struct ContentView: View {
    @EnvironmentObject var gameState: GameState
    @ObservedObject private var auth = AppleAuthManager.shared

    /// Whether the opening-credits intro should still be on screen. Seeded once,
    /// before the first frame, from the persisted flag — so when the intro is
    /// disabled (the default) HomeView renders immediately with zero overhead.
    @State private var showIntro: Bool

    /// Sign-in nudge shown once per launch, after the opening animation, when the
    /// player isn't signed in with Apple.
    @State private var showSignInPrompt = false

    /// Cold-launch guard: the intro plays at most once per process. The static
    /// survives any re-creation of ContentView (scene phase changes, etc.); a
    /// fresh launch resets it, so the intro replays only on a true cold start.
    private static var introHasPlayed = false

    /// Cold-launch guard so the sign-in nudge is considered at most once per
    /// process (no re-prompt on every scene-phase re-creation of ContentView).
    private static var signInPromptConsidered = false

    init() {
        let enabled = UserDefaults.standard.bool(forKey: "ra_introEnabled")
        _showIntro = State(initialValue: enabled && !ContentView.introHasPlayed)
    }

    var body: some View {
        ZStack {
            HomeView()
            if showIntro {
                IntroView(onComplete: {
                    ContentView.introHasPlayed = true
                    gameState.homeBallRecenterSignal += 1   // align live ball with the settle
                    withAnimation(.easeInOut(duration: 0.40)) { showIntro = false }
                    maybeOfferSignIn()   // only after the full animation has played
                })
                .transition(.opacity)
                .zIndex(1)
            }
            if showSignInPrompt {
                SignInPromptView(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.30)) { showSignInPrompt = false }
                })
                .transition(.opacity)
                .zIndex(2)
            }
        }
        // No intro to wait on (the default) — consider the nudge once home is up.
        .onAppear { if !showIntro { maybeOfferSignIn() } }
    }

    /// Offer Sign in with Apple once per launch if the player isn't signed in.
    /// Waits a beat so any persisted Apple session (restored asynchronously at
    /// launch) lands first, and stays out of the way during onboarding.
    private func maybeOfferSignIn() {
        guard !Self.signInPromptConsidered else { return }
        Self.signInPromptConsidered = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if !auth.isSignedIn && gameState.seenOnboarding {
                withAnimation(.easeInOut(duration: 0.30)) { showSignInPrompt = true }
            }
        }
    }
}

/// One-time-per-launch nudge to sign in with Apple, shown after the opening
/// animation when the player isn't signed in. Dismissible ("Not now") and
/// auto-dismisses the instant a sign-in (or a restored session) succeeds.
struct SignInPromptView: View {
    var onDismiss: () -> Void
    @ObservedObject private var auth = AppleAuthManager.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 50, weight: .regular))
                    .foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.45))
                Text("Sign in to play with friends")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Sign in with Apple to climb the global leaderboard, join clans, and send friends extra lives. Your level progress is always saved on this device either way.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(white: 0.62))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Spacer()
                VStack(spacing: 10) {
                    Button { auth.startSignIn() } label: {
                        HStack(spacing: 8) {
                            if auth.isWorking {
                                ProgressView().tint(.black)
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

                    Button("Not now") { onDismiss() }
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(white: 0.6))
                        .padding(.vertical, 6)

                    if let err = auth.lastError {
                        Text(err)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.45))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 36)
            }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { onDismiss() }
        }
        .accessibilityAddTraits(.isModal)
    }
}

#Preview {
    ContentView().environmentObject(GameState())
}
