import SwiftUI

@main
struct RollAlongApp: App {
    @StateObject private var gameState = GameState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameState)
        }
    }
}
