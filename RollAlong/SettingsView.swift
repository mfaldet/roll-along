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
                    cosmeticsSection
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
            Text("This wipes all level progress — stars, coins, and best times. Your cosmetics, nickname, and settings will be kept.")
        }
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
        }
    }

    private var cosmeticsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader("Cosmetics")
                Spacer()
                Text("Tap to equip")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.45))
            }
            cosmeticRow(
                label: "Ball",
                items: BallSkin.allCases.filter { gameState.isOwned($0) },
                isEquipped: { $0 == gameState.activeSkin && gameState.equippedPackID == nil },
                onTap:      { gameState.equipBall($0) }
            )
            packRow
            cosmeticRow(
                label: "Goal",
                items: GoalSkin.allCases.filter { gameState.isOwned($0) },
                isEquipped: { $0 == gameState.equippedGoal },
                onTap:      { gameState.equippedGoal = $0 }
            )
            cosmeticRow(
                label: "Trail",
                items: TrailColor.allCases.filter { gameState.isOwned($0) },
                isEquipped: { $0 == gameState.equippedTrail },
                onTap:      { gameState.equippedTrail = $0 }
            )
            cosmeticRow(
                label: "Floor",
                items: Floor.allCases.filter { gameState.isOwned($0) },
                isEquipped: { $0 == gameState.equippedFloor },
                onTap:      { gameState.equippedFloor = $0 }
            )
            cosmeticRow(
                label: "Pit",
                items: Pit.allCases.filter { gameState.isOwned($0) },
                isEquipped: { $0 == gameState.equippedPit },
                onTap:      { gameState.equippedPit = $0 }
            )
            cosmeticRow(
                label: "Music",
                items: MusicTrack.allCases.filter { gameState.isOwned($0) },
                isEquipped: { $0 == gameState.equippedMusic },
                onTap:      { gameState.equippedMusic = $0 }
            )
        }
    }

    /// One category row: kerned uppercase label + horizontal scroll of
    /// owned items.  Selected item gets a white ring + slight scale-up.
    private func cosmeticRow<Item: CosmeticItem>(
        label: String,
        items: [Item],
        isEquipped: @escaping (Item) -> Bool,
        onTap: @escaping (Item) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .kerning(1.5)
                .foregroundStyle(Color(white: 0.55))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items, id: \.id) { item in
                        cosmeticCell(item: item, selected: isEquipped(item)) {
                            onTap(item)
                        }
                    }
                }
                .padding(.horizontal, 2)
                // Vertical breathing room — the selected cell uses
                // .scaleEffect(1.06) + a 2pt border, which together push
                // it ~4pt taller than an unselected cell.  Without this
                // padding the ScrollView's viewport sizes to the
                // un-scaled height and clips the selected cell's top
                // border.
                .padding(.vertical, 6)
            }
        }
    }

    private func cosmeticCell<Item: CosmeticItem>(
        item: Item,
        selected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                cosmeticPreview(for: item)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(white: 0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selected ? Color.white : Color(white: 0.22),
                                    lineWidth: selected ? 2.0 : 0.8)
                    )
                    .scaleEffect(selected ? 1.06 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selected)
                Text(item.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(selected ? .white : Color(white: 0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 64)
    }

    /// Packs inventory row — owned ball Packs, shown beneath the Ball row.
    /// Bespoke (not `cosmeticRow`) because `BallPack` isn't a `CosmeticItem`.
    /// Tapping equips the whole pack; the ball then shuffles through its
    /// members each attempt.
    @ViewBuilder
    private var packRow: some View {
        let owned = BallPack.catalogue.filter { gameState.ownsPack($0) }
        if !owned.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("PACKS")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .kerning(1.5)
                    .foregroundStyle(Color(white: 0.55))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(owned) { pack in
                            packCell(pack: pack, selected: gameState.isPackEquipped(pack)) {
                                gameState.equipPack(pack)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func packCell(pack: BallPack,
                          selected: Bool,
                          onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    // Back swatch (second ball) peeks out to signal a stack.
                    if pack.skins.count > 1 {
                        Circle()
                            .fill(pack.skins[1].gradient(endRadius: 16))
                            .overlay(Circle().stroke(Color.black.opacity(0.30), lineWidth: 0.5))
                            .frame(width: 30, height: 30)
                            .offset(x: 11, y: 8)
                    }
                    Circle()
                        .fill(pack.skins[0].gradient(endRadius: 18))
                        .overlay(Circle().stroke(Color.black.opacity(0.30), lineWidth: 0.5))
                        .frame(width: 36, height: 36)
                        .offset(x: -6, y: -4)
                }
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.10)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selected ? Color.white : Color(white: 0.22),
                                lineWidth: selected ? 2.0 : 0.8)
                )
                .scaleEffect(selected ? 1.06 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selected)
                Text(pack.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(selected ? .white : Color(white: 0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 64)
    }

    @ViewBuilder
    private func cosmeticPreview<Item: CosmeticItem>(for item: Item) -> some View {
        switch item {
        case let s as BallSkin:
            Circle()
                .fill(s.gradient(endRadius: 28))
                .overlay(Circle().stroke(Color.black.opacity(0.30), lineWidth: 0.5))
                .padding(8)
        case let g as GoalSkin:
            Circle()
                .fill(GoalSkin.previewGradient(for: g))
                .overlay(Circle().stroke(Color.white.opacity(0.30), lineWidth: 1))
                .padding(8)
        case let t as TrailColor:
            Canvas { ctx, size in
                var path = Path()
                let pts = 10
                for i in 0..<pts {
                    let p = Double(i) / Double(pts - 1)
                    let x = size.width * CGFloat(0.15 + p * 0.7)
                    let y = size.height * CGFloat(0.85 - p * 0.7)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else      { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                if t == .rainbow {
                    // Multi-hue stroke for the rainbow preview.
                    let segs = pts - 1
                    for i in 0..<segs {
                        let t1 = Double(i) / Double(segs)
                        let t2 = Double(i + 1) / Double(segs)
                        let x1 = size.width * CGFloat(0.15 + t1 * 0.7)
                        let y1 = size.height * CGFloat(0.85 - t1 * 0.7)
                        let x2 = size.width * CGFloat(0.15 + t2 * 0.7)
                        let y2 = size.height * CGFloat(0.85 - t2 * 0.7)
                        var s = Path()
                        s.move(to: CGPoint(x: x1, y: y1))
                        s.addLine(to: CGPoint(x: x2, y: y2))
                        ctx.stroke(s,
                                   with: .color(Color(hue: t1, saturation: 1.0, brightness: 1.0)),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                } else {
                    ctx.stroke(path,
                               with: .color(t == .none ? Color(white: 0.30) : t.color),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
            }
            .padding(4)
        case let f as Floor:
            RoundedRectangle(cornerRadius: 8).fill(f.color)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.30), lineWidth: 0.5))
                .padding(6)
        case let p as Pit:
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.18))
                RoundedRectangle(cornerRadius: 2).fill(p.color).frame(width: 26, height: 14)
            }
            .padding(6)
        case let m as MusicTrack:
            Image(systemName: m == .none ? "speaker.slash.fill" : "music.note")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: m == .none
                            ? [Color(white: 0.35), Color(white: 0.20)]
                            : [Color(red: 0.45, green: 0.65, blue: 1.00),
                               Color(red: 0.25, green: 0.40, blue: 0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        default:
            EmptyView()
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

}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(GameState())
            .environmentObject(StoreKitManager.shared)
    }
}
