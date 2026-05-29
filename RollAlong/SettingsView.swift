import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var store:     StoreKitManager
    @Environment(\.dismiss) var dismiss
    @State private var showResetAlert = false
    @FocusState private var nameFocused: Bool

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    personalizationSection
                    skinSection
                    gameSection
                    purchasesSection
                    resetSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
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
            Text("This wipes all level progress — stars, coins, and best times. Your skin, name, and settings will be kept.")
        }
    }

    // MARK: - Sections

    private var personalizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Personalization")
            HStack {
                Text("Your Name")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color(white: 0.75))
                Spacer()
                TextField("Enter name", text: $gameState.playerName)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { nameFocused = false }
            }
            .padding()
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
        }
    }

    private var skinSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Ball Skin")
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(BallSkin.allCases) { skin in
                    skinCell(skin)
                }
            }
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
            }
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
        }
    }

    private var purchasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Purchases")
            VStack(spacing: 0) {
                Button {
                    Task { await store.restore() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Color(white: 0.55))
                        Text("Restore Purchases")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color(white: 0.85))
                        Spacer()
                    }
                    .padding()
                }
                if gameState.unlimitedLives {
                    Divider().background(Color(white: 0.22)).padding(.leading, 16)
                    HStack {
                        Image(systemName: "infinity")
                            .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.30))
                        Text("Unlimited Lives — Active")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color(red: 1.00, green: 0.88, blue: 0.55))
                        Spacer()
                    }
                    .padding()
                }
            }
            .background(Color(white: 0.14).clipShape(RoundedRectangle(cornerRadius: 14)))
        }
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .kerning(1.5)
            .foregroundStyle(Color(white: 0.45))
    }

    private func skinCell(_ skin: BallSkin) -> some View {
        let selected = gameState.activeSkin == skin
        return Button {
            gameState.activeSkin = skin
        } label: {
            VStack(spacing: 8) {
                Circle()
                    .fill(skin.gradient(endRadius: 32))
                    .frame(width: 62, height: 62)
                    .overlay(
                        Circle()
                            .stroke(
                                selected
                                    ? Color.white
                                    : Color(white: 0.25),
                                lineWidth: selected ? 2.5 : 1
                            )
                    )
                    .shadow(
                        color: selected ? .white.opacity(0.25) : .clear,
                        radius: 8
                    )
                    .scaleEffect(selected ? 1.06 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selected)

                Text(skin.rawValue)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(selected ? .white : Color(white: 0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(skin.rawValue) ball skin")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Double-tap to choose this skin.")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        SettingsView().environmentObject(GameState())
    }
}
