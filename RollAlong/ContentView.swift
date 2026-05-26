import SwiftUI

struct ContentView: View {
    @EnvironmentObject var gameState: GameState

    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView().environmentObject(GameState())
}
