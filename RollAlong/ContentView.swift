import SwiftUI

struct ContentView: View {
    @EnvironmentObject var gameState: GameState

    /// Whether the opening-credits intro should still be on screen. Seeded once,
    /// before the first frame, from the persisted flag — so when the intro is
    /// disabled (the default) HomeView renders immediately with zero overhead.
    @State private var showIntro: Bool

    /// Cold-launch guard: the intro plays at most once per process. The static
    /// survives any re-creation of ContentView (scene phase changes, etc.); a
    /// fresh launch resets it, so the intro replays only on a true cold start.
    private static var introHasPlayed = false

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
                })
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}

#Preview {
    ContentView().environmentObject(GameState())
}
