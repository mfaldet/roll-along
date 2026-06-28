import SwiftUI

// ===========================================================================
// LockerView — the player's cosmetics wardrobe.
//
// The one place to EQUIP what you own: ball (+ ball packs), goal, trail, floor,
// pit, and music.  Buying happens in the Shop / Catalog; this is equip-only and
// lists just the items the player owns.  Moved here out of Settings so the
// loadout lives next to the store it's filled from — reached from the Shop,
// just above the Catalog.
//
// SAFE BY CONSTRUCTION: only flips the equipped-cosmetic selections on
// GameState (the same setters Settings used); it buys nothing and touches no
// progress or server state.
// ===========================================================================
struct LockerView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator
    @Environment(\.dismiss) var dismiss

    /// The screen beneath the Locker in the nav stack decides the back-button
    /// label: "Profile" when opened from the profile's loadout, "Shop" from the
    /// Cosmetic Shop (and the default for any other entry point).
    private var backLabel: String {
        if case .profile? = nav.path.dropLast().last { return "Profile" }
        return "Shop"
    }

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

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
                        label: "Boundary",
                        items: Boundary.allCases.filter { gameState.isOwned($0) },
                        isEquipped: { $0 == gameState.equippedBoundary },
                        onTap:      { gameState.equippedBoundary = $0 }
                    )
                    cosmeticRow(
                        label: "Music",
                        items: MusicTrack.allCases.filter { gameState.isOwned($0) },
                        isEquipped: { $0 == gameState.equippedMusic },
                        onTap:      { gameState.equippedMusic = $0 }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("Locker")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text(backLabel)
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your Cosmetics")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text("Tap to equip")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
    }

    // MARK: - Category row

    /// One category row: kerned uppercase label + horizontal scroll of owned
    /// items.  Selected item gets a white ring + slight scale-up.
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
            // Wrap a crowded category into two stacked rows: more than 5 owned
            // items split into a first-half row on top and the rest below,
            // instead of one long horizontal strip.  5 or fewer stay a single
            // row, and every category decides independently (others unaffected).
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if items.count > 5 {
                        VStack(alignment: .leading, spacing: 12) {
                            cosmeticCellsRow(items.prefix((items.count + 1) / 2),
                                             isEquipped: isEquipped, onTap: onTap)
                            cosmeticCellsRow(items.suffix(items.count / 2),
                                             isEquipped: isEquipped, onTap: onTap)
                        }
                    } else {
                        cosmeticCellsRow(items[...], isEquipped: isEquipped, onTap: onTap)
                    }
                }
                .padding(.horizontal, 2)
                // Vertical breathing room — the selected cell uses
                // .scaleEffect(1.06) + a 2pt border, which together push it
                // ~4pt taller; without this padding the ScrollView clips the
                // selected cell's top/bottom border.
                .padding(.vertical, 6)
            }
        }
    }

    /// One horizontal strip of cosmetic cells.  Shared by `cosmeticRow` so a
    /// single category can render as one strip (≤5 owned) or two stacked strips
    /// (>5 owned) without duplicating the cell layout.
    private func cosmeticCellsRow<Item: CosmeticItem>(
        _ items: ArraySlice<Item>,
        isEquipped: @escaping (Item) -> Bool,
        onTap: @escaping (Item) -> Void
    ) -> some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.id) { item in
                cosmeticCell(item: item, selected: isEquipped(item)) {
                    onTap(item)
                }
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

    // MARK: - Per-item preview

    @ViewBuilder
    private func cosmeticPreview<Item: CosmeticItem>(for item: Item) -> some View {
        switch item {
        case let s as BallSkin:
            BallSkinView(skin: s, diameter: 48)
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
        case let b as Boundary:
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [b.color, b.deepColor],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 16)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(b.edgeColor.opacity(0.9), lineWidth: 1.2))
                .padding(8)
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
}

#Preview {
    NavigationStack {
        LockerView()
            .environmentObject(GameState())
            .environmentObject(Navigator())
    }
}
