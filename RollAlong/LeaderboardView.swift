import SwiftUI

// ===========================================================================
// LeaderboardView — the global climb ranking.
//
// Reads the public `players` table via SocialClient.fetchLeaderboard (ordered
// climb_level desc, then total_stars desc) and renders a ranked list.  The
// signed-in player's own row is highlighted so they can spot themselves.
//
// Requires a Supabase session (Sign in with Apple).  When signed out it shows
// a friendly prompt rather than an empty list — the leaderboard is the
// competitive pillar's hook, so we explain the payoff and route to Settings.
//
// SAFE BY CONSTRUCTION: read-only.  It mutates no local state and writes
// nothing to the server; the worst case on a paused/unreachable backend is a
// retryable error banner.
// ===========================================================================

struct LeaderboardView: View {
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var nav:       Navigator
    @ObservedObject private var auth = AppleAuthManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var rows:      [PlayerProfile] = []
    @State private var isLoading  = false
    @State private var errorText: String?

    private var myId: UUID? { SocialClient.shared.currentUserId }

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            if !auth.isSignedIn {
                signedOutState
            } else {
                content
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Signed-in content

    @ViewBuilder
    private var content: some View {
        if isLoading && rows.isEmpty {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
        } else if let errorText, rows.isEmpty {
            errorState(errorText)
        } else if rows.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, profile in
                        leaderboardRow(rank: index + 1, profile: profile)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .refreshable { await load() }
        }
    }

    private func leaderboardRow(rank: Int, profile: PlayerProfile) -> some View {
        let isMe  = (profile.id == myId)
        let world = World.world(for: max(1, profile.climbLevel))

        return HStack(spacing: 14) {
            rankBadge(rank)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName.isEmpty ? "Climber" : profile.displayName)
                    .font(.system(.body, design: .rounded).weight(isMe ? .bold : .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(world.accent)
                        .frame(width: 7, height: 7)
                    Text(world.name)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(white: 0.5))
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("LVL \(profile.climbLevel)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 1.00, green: 0.84, blue: 0.30))
                    Text("\(profile.totalStars)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(white: 0.6))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isMe ? Color(red: 0.20, green: 0.50, blue: 0.96).opacity(0.18)
                           : Color(white: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isMe ? Color(red: 0.30, green: 0.58, blue: 0.98).opacity(0.7)
                                     : Color.clear,
                                lineWidth: 1.2)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Rank \(rank). \(profile.displayName.isEmpty ? "Climber" : profile.displayName), "
            + "level \(profile.climbLevel), \(profile.totalStars) stars."
            + (isMe ? " This is you." : "")
        )
    }

    /// Medal disc for the top 3, plain numeral otherwise.
    private func rankBadge(_ rank: Int) -> some View {
        let medal: Color? = {
            switch rank {
            case 1:  return Color(red: 1.00, green: 0.81, blue: 0.30)  // gold
            case 2:  return Color(red: 0.80, green: 0.83, blue: 0.88)  // silver
            case 3:  return Color(red: 0.80, green: 0.55, blue: 0.34)  // bronze
            default: return nil
            }
        }()

        return ZStack {
            Circle()
                .fill(medal ?? Color(white: 0.20))
                .frame(width: 34, height: 34)
            Text("\(rank)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(medal == nil ? Color(white: 0.7) : .black)
                .monospacedDigit()
        }
    }

    // MARK: - Empty / error / signed-out states

    private var emptyState: some View {
        messageBlock(
            icon: "trophy",
            title: "No climbers yet",
            message: "Be the first on the board — clear a level to post your rank.",
            actionTitle: nil,
            action: nil
        )
    }

    private func errorState(_ text: String) -> some View {
        messageBlock(
            icon: "wifi.exclamationmark",
            title: "Couldn't load the leaderboard",
            message: text,
            actionTitle: "Try Again",
            action: { Task { await load() } }
        )
    }

    private var signedOutState: some View {
        messageBlock(
            icon: "trophy.fill",
            title: "Climb the global board",
            message: "Sign in with Apple to see where you rank against climbers worldwide, join clans, and send friends extra lives. Your level progress is saved on this device either way.",
            actionTitle: "Sign in from Settings",
            action: { nav.goToSettings() }
        )
    }

    private func messageBlock(icon: String,
                              title: String,
                              message: String,
                              actionTitle: String?,
                              action: (() -> Void)?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Color(white: 0.4))
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color(white: 0.55))
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Color(red: 0.20, green: 0.50, blue: 0.96))
                        )
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Data

    private func load() async {
        guard auth.isSignedIn else { return }
        isLoading = true
        errorText = nil
        do {
            rows = try await SocialClient.shared.fetchLeaderboard()
        } catch {
            errorText = "The ranking server is unreachable right now. Pull to refresh or try again."
        }
        isLoading = false
    }
}
