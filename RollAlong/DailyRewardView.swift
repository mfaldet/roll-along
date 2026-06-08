import SwiftUI

// ===========================================================================
// DailyRewardView — the login-streak claim sheet.
//
// The retention loop's front end.  Renders the 7-day coin ladder
// (GameState.dailyRewardLadder), highlights today's claimable tile, marks the
// days already collected this cycle, and dims what's still ahead.  Tapping
// Claim routes through GameState.claimDailyReward(), which advances the streak,
// banks the coins, and stamps the date — the @Published state then flips this
// view to its "claimed, come back tomorrow" face automatically.
//
// Presented as a .sheet from HomeView (increment 3).  Self-contained: depends
// only on GameState's daily-reward API, the shared CoinIcon, and Haptics.
// ===========================================================================

struct DailyRewardView: View {
    @EnvironmentObject var gameState: GameState
    @Environment(\.dismiss) private var dismiss

    @State private var celebrate   = false
    @State private var lastAwarded = 0

    private let cycleLength = GameState.dailyRewardLadder.count

    private enum DayState { case claimed, today, tomorrow, upcoming }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.08), Color(white: 0.14)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                header
                ladder
                Spacer(minLength: 4)
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 22)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("Daily Reward")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(streakColor)
                Text(streakText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.7))
            }
        }
    }

    private var streakText: String {
        let s = gameState.liveStreak
        return s <= 0 ? "Start your streak today" : "\(s)-day streak"
    }

    private var streakColor: Color {
        gameState.liveStreak > 0
            ? Color(red: 1.0, green: 0.55, blue: 0.2)
            : Color(white: 0.4)
    }

    // MARK: - Ladder

    private var ladder: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(1...cycleLength, id: \.self) { day in
                dayTile(day)
            }
        }
    }

    private func dayTile(_ day: Int) -> some View {
        let state    = tileState(forDay: day)
        let amount   = gameState.dailyReward(forDay: day)
        let isJackpot = day == cycleLength

        return VStack(spacing: 5) {
            Text("DAY \(day)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(captionColor(state))
                .tracking(0.5)

            ZStack {
                if state == .claimed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(red: 0.35, green: 0.78, blue: 0.45))
                } else {
                    CoinIcon(size: isJackpot ? 24 : 20)
                }
            }
            .frame(height: 26)

            Text("\(amount)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(amountColor(state))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tileBackground(state, jackpot: isJackpot))
        .scaleEffect(state == .today && celebrate ? 1.06 : 1)
    }

    /// Where each tile sits relative to today's claim within the current cycle.
    private func tileState(forDay day: Int) -> DayState {
        if gameState.dailyRewardAvailable {
            let target = gameState.nextDailyRewardDay        // 1…cycleLength
            if day < target  { return .claimed }
            if day == target { return .today }
            return .upcoming
        } else {
            // Already claimed today: tiles up to today's slot are done.
            let claimedToday = ((gameState.dailyStreak - 1) % cycleLength) + 1
            if day <= claimedToday      { return .claimed }
            if day == claimedToday + 1  { return .tomorrow }
            return .upcoming
        }
    }

    // MARK: - Footer (claim / claimed)

    @ViewBuilder
    private var footer: some View {
        if gameState.dailyRewardAvailable {
            Button(action: claim) {
                HStack(spacing: 8) {
                    CoinIcon(size: 20)
                    Text("Claim \(gameState.nextDailyRewardAmount) coins")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(Color(red: 1.0, green: 0.82, blue: 0.30)))
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color(red: 0.35, green: 0.78, blue: 0.45))
                    Text(celebrate ? "+\(lastAwarded) coins!" : "Claimed!  Come back tomorrow.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text("Tomorrow: \(gameState.nextDailyRewardAmount) coins")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.7))
                    .padding(.top, 2)
            }
        }
    }

    private func claim() {
        guard let amount = gameState.claimDailyReward() else { return }
        lastAwarded = amount
        if gameState.hapticsEnabled { Haptics.success() }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { celebrate = true }
    }

    // MARK: - Tile styling

    private func tileBackground(_ s: DayState, jackpot: Bool) -> some View {
        let fill: Color
        switch s {
        case .claimed:  fill = Color(red: 0.20, green: 0.42, blue: 0.28)
        case .today:    fill = jackpot ? Color(red: 0.42, green: 0.34, blue: 0.10) : Color(white: 0.22)
        case .tomorrow: fill = Color(white: 0.17)
        case .upcoming: fill = Color(white: 0.13)
        }
        let stroke: Color = s == .today
            ? Color(red: 1.0, green: 0.82, blue: 0.30)
            : (jackpot ? Color(red: 1.0, green: 0.82, blue: 0.30).opacity(0.4) : Color(white: 0.25))
        let width: CGFloat = s == .today ? 2 : 1
        return RoundedRectangle(cornerRadius: 12)
            .fill(fill.opacity(s == .upcoming ? 0.6 : 1))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(stroke, lineWidth: width))
    }

    private func captionColor(_ s: DayState) -> Color {
        switch s {
        case .today:   return Color(red: 1.0, green: 0.84, blue: 0.34)
        case .claimed: return Color(red: 0.55, green: 0.85, blue: 0.62)
        default:       return Color(white: 0.45)
        }
    }

    private func amountColor(_ s: DayState) -> Color {
        s == .upcoming ? Color(white: 0.55) : .white
    }
}

#Preview {
    DailyRewardView().environmentObject(GameState())
}
