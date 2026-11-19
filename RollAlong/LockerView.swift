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
    /// True while the Locker scrolls — every tile holds its frame.
    @State private var scrolling = false

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
                        isEquipped: { gameState.isEquipped($0) },
                        onTap:      { if gameState.equip($0) { Haptics.light() } }
                    )
                    packRow
                    cosmeticRow(
                        label: "Goal",
                        items: GoalSkin.allCases.filter { gameState.isOwned($0) },
                        isEquipped: { gameState.isEquipped($0) },
                        onTap:      { if gameState.equip($0) { Haptics.light() } }
                    )
                    cosmeticRow(
                        label: "Trail",
                        items: TrailColor.allCases.filter { gameState.isOwned($0) },
                        isEquipped: { gameState.isEquipped($0) },
                        onTap:      { if gameState.equip($0) { Haptics.light() } }
                    )
                    cosmeticRow(
                        label: "Floor",
                        items: Floor.allCases.filter { gameState.isOwned($0) },
                        isEquipped: { gameState.isEquipped($0) },
                        onTap:      { if gameState.equip($0) { Haptics.light() } }
                    )
                    cosmeticRow(
                        label: "Pit",
                        items: Pit.allCases.filter { gameState.isOwned($0) },
                        isEquipped: { gameState.isEquipped($0) },
                        onTap:      { if gameState.equip($0) { Haptics.light() } }
                    )
                    cosmeticRow(
                        label: "Boundary",
                        items: Boundary.allCases.filter { gameState.isOwned($0) },
                        isEquipped: { gameState.isEquipped($0) },
                        onTap:      { if gameState.equip($0) { Haptics.light() } }
                    )
                    // Music is not in 1.0 (no track plays): no Music row.
                    if CosmeticFeatures.musicEnabled {
                        cosmeticRow(
                            label: "Music",
                            items: MusicTrack.allCases.filter { gameState.isOwned($0) },
                            isEquipped: { gameState.isEquipped($0) },
                            onTap:      { if gameState.equip($0) { Haptics.light() } }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 48)
                // Tiles hold their frames while the Locker scrolls.
                .environment(\.cosmeticTilesScrolling, scrolling)
            }
            .cosmeticTileScrollTracking($scrolling)
            // Tiles draw the game's own renderers (CosmeticTile), frozen or
            // gently animating; nothing here is a full preview.
            .environment(\.cosmeticMotion, .still)
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
            Text("Tap to equip · hold to try on")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
    }

    // MARK: - Category row

    /// Fixed 5-column grid for the Locker — every category wraps into as many
    /// rows of five as it needs (≤5 → one row, 6–10 → two, 11–15 → three, …)
    /// instead of scrolling sideways, so all owned items are visible at once.
    private static let lockerColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    /// One category row: kerned uppercase label above a wrapping 5-up grid of
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
            LazyVGrid(columns: Self.lockerColumns, alignment: .leading, spacing: 14) {
                // The Roll Along piece for this slot always comes first.
                ForEach(Item.rollAlongFirst(items), id: \.id) { item in
                    cosmeticCell(item: item, selected: isEquipped(item)) {
                        onTap(item)
                    }
                }
            }
            // Breathing room so the selected cell's 1.06 scale + 2pt border
            // isn't clipped against the rows above/below.
            .padding(.vertical, 4)
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
        .frame(maxWidth: .infinity)
        // One tap equips (above).  A long press opens "try it on": the
        // gameplay replay with this item on the current setup, plus Equip.
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label(selected ? "Equipped" : "Equip", systemImage: "checkmark.circle")
            }
            .disabled(selected)
        } preview: {
            LoadoutDiorama(loadout: Loadout(equippedIn: gameState).trying(item),
                           framesBoundary: item is Boundary)
                .environment(\.cosmeticMotion, .preview)
                .frame(width: 300, height: 300)
                .background(Color(white: 0.08))
        }
        .accessibilityHint("Double-tap to equip. Touch and hold to try it on.")
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
                LazyVGrid(columns: Self.lockerColumns, alignment: .leading, spacing: 14) {
                    ForEach(owned) { pack in
                        packCell(pack: pack, selected: gameState.isPackEquipped(pack)) {
                            gameState.equipPack(pack)
                        }
                    }
                }
                .padding(.vertical, 4)
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
        .frame(maxWidth: .infinity)
    }

    // MARK: - Per-item preview

    /// The game's own renderer for the item (see `CosmeticTile`), framed to
    /// fill the 56 pt cell: frozen on its hero frame, gently animating while
    /// on screen.
    @ViewBuilder
    private func cosmeticPreview<Item: CosmeticItem>(for item: Item) -> some View {
        switch item {
        case is BallSkin:
            CosmeticTile(item: item, diameter: 46)
        case is GoalSkin, is MusicTrack:
            CosmeticTile(item: item, diameter: 44)
        case is TrailColor:
            CosmeticTile(item: item, trailWidth: 3.5)
                .padding(2)
        default:   // floors, pits, boundaries
            CosmeticTile(item: item, corner: 8)
                .padding(5)
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
