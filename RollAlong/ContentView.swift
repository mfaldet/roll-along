import SwiftUI

// ContentView is intentionally thin — the actual game lives in BallGameView.
// Keeping ContentView separate gives us a place to add a future home screen,
// level select, settings, or pause menu without rewiring the App entry point.
struct ContentView: View {
    var body: some View {
        BallGameView()
    }
}

#Preview {
    ContentView()
}
