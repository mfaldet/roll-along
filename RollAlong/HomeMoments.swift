import SwiftUI

// ===========================================================================
// One-time moments Home shows by itself (1.1), one after another:
//
//   1. the bonus message  — coins paid on the first launch of 1.1 for levels
//                           the player had already fully cleared;
//   2. collection picks   — a free collection pick that is owed (the player
//                           is past level 50, 100 or 200 and has not taken
//                           it), lowest level first;
//
// `HomeMoment.next(for:)` is the single place that decides what is shown
// next.  HomeView presents it full screen and asks again when it closes.
// ===========================================================================
enum HomeMoment: Identifiable, Equatable {
    case earlierBonus(coins: Int)
    case collectionPick(level: Int)

    var id: String {
        switch self {
        case .earlierBonus:              return "bonus"
        case .collectionPick(let level): return "pick-\(level)"
        }
    }

    /// What Home should show next, or nil for nothing.  A pick with nothing
    /// left on the reward list is closed here and skipped.
    static func next(for gameState: GameState) -> HomeMoment? {
        if gameState.earlierBonusToAnnounce > 0 {
            return .earlierBonus(coins: gameState.earlierBonusToAnnounce)
        }
        while let level = gameState.collectionPickDue {
            if gameState.rewardCollectionsNotOwned.isEmpty {
                gameState.closeCollectionPick(level)
            } else {
                return .collectionPick(level: level)
            }
        }
        return nil
    }
}

/// The view for one moment.  `onDone` closes it.
struct HomeMomentView: View {
    let moment: HomeMoment
    let onDone: () -> Void

    var body: some View {
        switch moment {
        case .earlierBonus(let coins):
            EarlierBonusMessageView(coins: coins, onDone: onDone)
        case .collectionPick(let level):
            CollectionPickView(pickLevel: level, onDone: onDone)
        }
    }
}

// ---------------------------------------------------------------------------
// The bonus message: one short message with the total.
// ---------------------------------------------------------------------------
struct EarlierBonusMessageView: View {
    let coins: Int
    let onDone: () -> Void
    @EnvironmentObject private var gameState: GameState

    private let gold = Color(red: 1.00, green: 0.84, blue: 0.30)

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(gold)
                Text("+\(coins) coins")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("A new bonus for fully clearing a level: three stars and every coin. This is for the levels you had already fully cleared.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                Button {
                    if gameState.hapticsEnabled { Haptics.success() }
                    // Shown: do not show it again.
                    gameState.earlierBonusToAnnounce = 0
                    onDone()
                } label: {
                    Text("Nice!")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 18).fill(gold))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// ---------------------------------------------------------------------------
// A free collection pick, shown from Home.  The same choice the game offers
// after a level (choose, confirm, then the gift): one collection from the
// reward list that the player does not own.  Used when a pick is owed at
// launch: a player who was already past level 50 or 100 when 1.1 arrived.
// ---------------------------------------------------------------------------
struct CollectionPickView: View {
    let pickLevel: Int
    let onDone: () -> Void

    @EnvironmentObject private var gameState: GameState

    private enum Step { case choose, confirm, given }
    @State private var step: Step = .choose
    @State private var pickedID: String? = nil
    /// The list as it was when the picker opened, so it does not change
    /// under the player when the gift lands.
    @State private var offered: [CosmeticBundle] = []

    private var picked: CosmeticBundle? {
        guard let pickedID else { return nil }
        return offered.first { $0.id == pickedID }
    }

    private func theme(_ bundle: CosmeticBundle) -> Color {
        bundle.boundaries.first?.color ?? Color(white: 0.75)
    }

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()
            VStack(spacing: 16) {
                switch step {
                case .choose:  chooseStep
                case .confirm: confirmStep
                case .given:   givenStep
                }
            }
            .padding(.vertical, 24)
            .animation(.easeInOut(duration: 0.25), value: step)
        }
        .onAppear {
            if offered.isEmpty { offered = gameState.rewardCollectionsNotOwned }
        }
    }

    private var chooseStep: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("LEVEL \(pickLevel) COMPLETE")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .kerning(2)
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.35))
                Text("Choose a free collection")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("A one-time gift. Pick one — it's free, and it's yours to keep forever.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(offered) { bundle in card(bundle) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                guard picked != nil else { return }
                if gameState.hapticsEnabled { Haptics.medium() }
                step = .confirm
            } label: {
                Text(picked.map { "Choose \($0.displayName)" } ?? "Pick a set")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(picked != nil ? Color.black : Color(white: 0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 18)
                        .fill(picked != nil ? Color.white : Color(white: 0.20)))
            }
            .buttonStyle(.plain)
            .disabled(picked == nil)
            .padding(.horizontal, 20)
        }
    }

    private func card(_ bundle: CosmeticBundle) -> some View {
        let selected = pickedID == bundle.id
        let color = theme(bundle)
        return Button {
            if pickedID != bundle.id {
                pickedID = bundle.id
                if gameState.hapticsEnabled { Haptics.light() }
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 12, height: 12)
                    Text(bundle.displayName)
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(color)
                    }
                }
                pieces(bundle)
                Text(bundle.tagline)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.62))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [color.opacity(selected ? 0.30 : 0.14), Color(white: 0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(selected ? color : Color(white: 0.22), lineWidth: selected ? 2.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(bundle.displayName) collection")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The pieces of a collection as small still pictures: the ball as it
    /// is drawn in play, the others as their colors.
    private func pieces(_ bundle: CosmeticBundle) -> some View {
        HStack(spacing: 6) {
            if let ball = bundle.balls.first {
                tile { BallSkinView(skin: ball, diameter: 48).padding(6) }
            }
            if let goal = bundle.goals.first {
                tile { GoalSkinView(goal: goal).padding(6) }
            }
            if let trail = bundle.trails.first {
                tile { Capsule().fill(trail.color).frame(width: 26, height: 5).rotationEffect(.degrees(-35)) }
            }
            if let floor = bundle.floors.first {
                tile { RoundedRectangle(cornerRadius: 7).fill(floor.color).padding(4) }
            }
            if let pit = bundle.pits.first {
                tile { RoundedRectangle(cornerRadius: 3).fill(pit.color).frame(width: 22, height: 12) }
            }
            if let wall = bundle.boundaries.first {
                tile { RoundedRectangle(cornerRadius: 7).strokeBorder(wall.color, lineWidth: 5).padding(5) }
            }
            Spacer(minLength: 0)
        }
        .environment(\.cosmeticMotion, .tileFrozen)
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.13)))
    }

    private var confirmStep: some View {
        VStack(spacing: 16) {
            if let bundle = picked {
                Text("Choose \(bundle.displayName)?")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("This is a one-time choice. The whole set is free and yours to keep forever.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                pieces(bundle).fixedSize()
                VStack(spacing: 6) {
                    Button {
                        gameState.takeRewardCollection(bundle, pickLevel: pickLevel)
                        if gameState.hapticsEnabled { Haptics.success() }
                        step = .given
                    } label: {
                        Text("Confirm")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 18).fill(theme(bundle)))
                    }
                    .buttonStyle(.plain)
                    Button { step = .choose } label: {
                        Text("Back")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(white: 0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var givenStep: some View {
        VStack(spacing: 14) {
            if let bundle = picked {
                Image(systemName: "gift.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(theme(bundle))
                Text("\(bundle.displayName) is yours!")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Equipped and ready to roll.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.72))
                pieces(bundle).fixedSize()
                Button { onDone() } label: {
                    Text("Continue")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
    }
}
