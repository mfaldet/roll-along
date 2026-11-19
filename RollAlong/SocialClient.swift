import Foundation
import SwiftUI
import CryptoKit
import UIKit

// ===========================================================================
// SocialClient — authenticated calls to the Roll Along social backend.
//
// Counterpart to AnalyticsClient.  Where analytics is anonymous + insert-only,
// social is IDENTIFIED + read/write: profiles (the headline climb level next to
// a player's name), leaderboards, clans, friends, and the send-a-life economy.
//
// IDENTITY: Sign in with Apple → Supabase Auth.
//   After the player signs in, the auth layer hands this client the resulting
//   Supabase access token (a short-lived authenticated JWT) and the player's
//   user id via `setSession(accessToken:userId:)`.  Every request then sends:
//       apikey:        <publishable key>      (identifies the project)
//       Authorization: Bearer <access token>  (sets role=authenticated → RLS)
//   so Postgres RLS scopes writes to the player's own rows.  Talking to
//   PostgREST directly (no Supabase SDK dependency) keeps this dependency-free,
//   exactly like AnalyticsClient.
//
// SAFE BY CONSTRUCTION: this is a new, self-contained file.  It imports nothing
// from the game and changes no existing behavior; until the auth layer calls
// `setSession`, every method simply throws `.notSignedIn`.
//
// Server schema: see docs/social-schema.sql.
// ===========================================================================

final class SocialClient: @unchecked Sendable {
    static let shared = SocialClient()
    private init() {}

    // MARK: - Configuration

    private static let projectURL = "https://mhwpcwauzvmtmuphtajs.supabase.co"
    /// Publishable (client-safe) key sent as the `apikey` header on every
    /// request.  Like the anon key, it's safe to embed — RLS does the gating,
    /// and the authenticated role only comes from the per-user Bearer token.
    private static let apiKey = "sb_publishable_A1RRz_2m9qDAWikrVlyfnQ_M-YgOSaR"

    // MARK: - Session (set by the Sign-in-with-Apple auth layer)

    private struct Session { let token: String; let userId: UUID }
    private var session: Session?

    /// Install the authenticated session after a successful Sign in with Apple.
    func setSession(accessToken: String, userId: UUID) {
        session = Session(token: accessToken, userId: userId)
    }

    /// Tear down on sign-out / token loss.
    func clearSession() { session = nil }

    var isSignedIn: Bool { session != nil }

    /// The signed-in player's id, if any.
    var currentUserId: UUID? { session?.userId }

    // MARK: - Account deletion (App Store Guideline 5.1.1(v))

    /// Permanently delete the signed-in player's account and all associated
    /// server data — profile, clan memberships, friendships, and life gifts —
    /// plus the underlying auth user.  A clan the player owns is transferred to
    /// another member (an officer if any, else the longest-standing member); a
    /// clan with no other members is deleted.  The cascade + clan hand-off runs
    /// in the `delete-account` Edge Function under elevated privileges; this
    /// just invokes it with the player's bearer token.  Clears the local
    /// session on success — sign the user out afterwards.
    ///
    /// `appleAuthorizationCode` is a fresh one-time code from Sign in with
    /// Apple (see `AppleAuthManager.requestAuthorizationCode`).  When present
    /// it is sent to the function so the server can revoke the player's Apple
    /// token; the account is deleted either way.
    func deleteMyAccount(appleAuthorizationCode: String? = nil) async throws {
        try Self.requireLiveServerAllowed()
        let session = try requireSession()
        guard let url = URL(string: "\(Self.projectURL)/functions/v1/delete-account") else {
            throw SocialError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",        forHTTPHeaderField: "Content-Type")
        req.setValue(Self.apiKey,               forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        if let appleAuthorizationCode {
            req.httpBody = try encoder.encode(["apple_authorization_code": appleAuthorizationCode])
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SocialError.http(status: -1, body: "no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SocialError.http(status: http.statusCode,
                                   body: String(data: data, encoding: .utf8) ?? "")
        }
        clearSession()
    }

    // MARK: - JSON

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let iso = ISO8601DateFormatter()

    // MARK: - Profiles

    /// Create-or-update the signed-in player's profile (PostgREST upsert).
    /// Returns the stored row.  Use this on first sign-in and whenever the
    /// player edits their display name.
    @discardableResult
    func upsertMyProfile(displayName: String,
                         climbLevel: Int,
                         highestUnlocked: Int,
                         totalStars: Int,
                         coinsCollected: Int,
                         lives: Int) async throws -> PlayerProfile {
        let me = try requireSession()
        let body = ProfileUpsert(id: me.userId,
                                 // Only a preset-format name is ever sent.
                                 display_name: PresetNames.shownNickname(displayName).isEmpty
                                     ? PresetNames.defaultNickname
                                     : PresetNames.shownNickname(displayName),
                                 climb_level: climbLevel,
                                 highest_unlocked: highestUnlocked,
                                 total_stars: totalStars,
                                 coins_collected: coinsCollected,
                                 lives: lives)
        let data = try await send(method: "POST", path: "players",
                                  bodyData: try encoder.encode([body]),
                                  prefer: "resolution=merge-duplicates,return=representation")
        let rows = try decode([PlayerProfile].self, from: data)
        guard let row = rows.first else { throw SocialError.emptyResponse }
        return row
    }

    private struct LookPatch: Encodable {
        let accent_hex: String
        let ball_skin: String
    }

    /// Send the player's accent color ("#RRGGBB") and equipped ball, so other
    /// players see them.  Best-effort and silent: before
    /// docs/social-schema-v5.sql (section 11) is applied the server refuses
    /// the unknown columns and nothing else is affected.
    func syncMyLook(accentHex: String, ballSkin: String) async {
        guard let me = currentUserId else { return }
        let hex = accentHex.hasPrefix("#") ? accentHex : "#" + accentHex
        guard let body = try? encoder.encode(LookPatch(accent_hex: hex.uppercased(), ball_skin: ballSkin)) else { return }
        _ = try? await send(method: "PATCH", path: "players",
                            query: "id=eq.\(me.uuidString)",
                            bodyData: body, prefer: "return=minimal")
    }

    /// Sync just the progression counters — the cheap, frequent write made when
    /// the player advances a level.  Patches the player's own row only.
    func syncProgress(climbLevel: Int, highestUnlocked: Int, totalStars: Int, coinsCollected: Int) async throws {
        let me = try requireSession()
        let body = ProgressPatch(climb_level: climbLevel,
                                 highest_unlocked: highestUnlocked,
                                 total_stars: totalStars,
                                 coins_collected: coinsCollected)
        _ = try await send(method: "PATCH", path: "players",
                           query: "id=eq.\(me.userId.uuidString)",
                           bodyData: try encoder.encode(body),
                           prefer: "return=minimal")
    }

    /// Sync the minigame + competitive leaderboard stats (best Pinball score,
    /// total Zen seconds, and every competitive mode's personal best + lifetime
    /// win tally).  Client-trusted, like the climb stats.
    func syncMinigameStats(pinballBest: Int, zenSeconds: Int,
                           goldrushBest: Int, goldrushWins: Int,
                           snakeBest: Int, snakeWins: Int,
                           sumoBest: Int, sumoWins: Int,
                           paintballBest: Int, paintballWins: Int,
                           marblecupBest: Int, marblecupWins: Int,
                           kothBest: Int, kothWins: Int,
                           rollupBest: Int, rollupBestSeconds: Int) async throws {
        let me = try requireSession()
        let body = MinigamePatch(pinball_best: pinballBest,
                                 zen_seconds: zenSeconds,
                                 goldrush_best: goldrushBest,
                                 snake_best: snakeBest,
                                 sumo_best: sumoBest,
                                 paintball_best: paintballBest,
                                 marblecup_best: marblecupBest,
                                 koth_best: kothBest,
                                 snake_wins: snakeWins,
                                 sumo_wins: sumoWins,
                                 paintball_wins: paintballWins,
                                 marblecup_wins: marblecupWins,
                                 koth_wins: kothWins,
                                 goldrush_wins: goldrushWins,
                                 rollup_best: rollupBest,
                                 rollup_best_seconds: rollupBestSeconds)
        _ = try await send(method: "PATCH", path: "players",
                           query: "id=eq.\(me.userId.uuidString)",
                           bodyData: try encoder.encode(body),
                           prefer: "return=minimal")
    }

    /// Fetch a single profile by id (e.g. to show a friend's climb level).
    // MARK: - Friend codes (docs/social-schema-v5.sql, section 10)

    private struct FriendCodeRow: Decodable {
        let code: String?
        enum CodingKeys: String, CodingKey { case code = "friend_code" }
    }

    /// The signed-in player's friend code ("AF3K7MXY"), or nil when signed
    /// out, offline, or before the database file that adds codes is run.
    func fetchMyFriendCode() async -> String? {
        guard let me = currentUserId,
              let data = try? await send(method: "GET", path: "players",
                                         query: "select=friend_code&id=eq.\(me.uuidString)&limit=1"),
              let rows = try? decode([FriendCodeRow].self, from: data) else { return nil }
        return rows.first?.code.flatMap(FriendCode.normalize)
    }

    /// The player with this friend code, or nil when there is none.  `code`
    /// must already be normalized (`FriendCode.normalize`).
    func findPlayer(friendCode code: String) async throws -> PlayerProfile? {
        _ = try requireSession()
        let found = try await getPlayers(
            columns: "id,display_name,climb_level,highest_unlocked,total_stars,lives",
            rest: "&friend_code=eq.\(code)&limit=1")
        return found.first
    }

    func fetchProfile(id: UUID) async throws -> PlayerProfile? {
        let data = try await send(method: "GET", path: "players",
                                  query: "id=eq.\(id.uuidString)&limit=1")
        return try decode([PlayerProfile].self, from: data).first
    }

    // MARK: - Leaderboard

    /// Leaderboard rows, ordered by `order` (a PostgREST order clause).  The
    /// default is the climb board; minigame boards pass e.g. "zen_seconds.desc".
    /// Boards kept per difficulty use `fetchMinigameDifficultyLeaderboard`.
    func fetchLeaderboard(order: String = "climb_level.desc,total_stars.desc",
                          limit: Int = 100) async throws -> [PlayerProfile] {
        let cols = "id,display_name,climb_level,highest_unlocked,total_stars,"
                 + "coins_collected,pinball_best,zen_seconds,goldrush_best,lives,"
                 + "snake_best,sumo_best,paintball_best,marblecup_best,koth_best,"
                 + "snake_wins,sumo_wins,paintball_wins,marblecup_wins,koth_wins,goldrush_wins,"
                 + "rollup_best,rollup_best_seconds"
        return try await getPlayers(columns: cols, rest: "&order=\(order)&limit=\(limit)",
                                    hideExcluded: true)
    }

    /// Columns added by docs/social-schema-v5.sql.  (The weekly-pace columns
    /// are no longer read; database step 12 removes them.)
    private static let v5PlayerColumns = ",lives_request_closed_at"
    /// Columns added by section 11 of docs/social-schema-v5.sql (a player's look).
    private static let lookColumns = ",accent_hex,ball_skin"

    /// Read `players` rows, asking for the v5 columns too.  Until
    /// docs/social-schema-v5.sql has been run the server answers 400 for a
    /// column it does not know, so this falls back to the older query — the
    /// lists keep working, just without the exclusion filter.
    /// `rest` is the remainder of the query string, starting with "&".
    private func getPlayers(columns: String, rest: String,
                            hideExcluded: Bool = false) async throws -> [PlayerProfile] {
        // Newest first: with a player's look (section 11), then without it
        // (sections 1–10 only), then the original columns (v5 not run).  A
        // column the server does not know makes it answer 400 for the whole
        // request, so each step drops only what may be missing.
        let filter = hideExcluded ? "&excluded=is.false" : ""
        let attempts = [
            "select=\(columns)\(Self.v5PlayerColumns)\(Self.lookColumns)" + filter + rest,
            "select=\(columns)\(Self.v5PlayerColumns)" + filter + rest,
            "select=\(columns)" + rest,
        ]
        var lastError: Error = SocialError.emptyResponse
        for query in attempts {
            do {
                let data = try await send(method: "GET", path: "players", query: query)
                return try decode([PlayerProfile].self, from: data)
            } catch SocialError.http(let status, let body) where status == 400 || status == 404 {
                lastError = SocialError.http(status: status, body: body)
            }
        }
        throw lastError
    }

    // MARK: - Per-difficulty minigame leaderboard (minigame_scores table)

    private struct MinigameScoreUpsert: Encodable {
        let player_id: String
        let game: String
        let difficulty: String
        let wins: Int
        let best: Int
        /// Disco Ball only: the best run's average time per crossing (ms).
        /// Left out of the request when nil (the competitive games).
        let best_avg_ms: Int?
    }

    /// Upsert this player's wins + best for one game at one difficulty
    /// (the six competitive games, and Disco Ball as game "disco" with
    /// `bestAvgMs`).  Best-effort; signed-in only (the caller wraps it in try?).
    func syncMinigameScore(game: String, difficulty: String,
                           wins: Int, best: Int, bestAvgMs: Int? = nil) async throws {
        let me = try requireSession()
        // Keep Disco Ball times inside the server's sanity rule
        // (docs/leaderboard-discoball.sql) so a real run is never refused.
        let avg = bestAvgMs.map { min(600_000, max(250, $0)) }
        let body = MinigameScoreUpsert(player_id: me.userId.uuidString, game: game,
                                       difficulty: difficulty,
                                       wins: max(0, wins), best: max(0, best),
                                       best_avg_ms: avg)
        _ = try await send(method: "POST", path: "minigame_scores",
                           query: "on_conflict=player_id,game,difficulty",
                           bodyData: try encoder.encode(body),
                           prefer: "resolution=merge-duplicates,return=minimal")
    }

    private struct MinigameScoreRow: Decodable {
        let player_id: UUID
        let wins: Int
        let best: Int
        let best_avg_ms: Int?
        let players: Embedded?
        struct Embedded: Decodable {
            let display_name: String?
            let climb_level: Int?
            let total_stars: Int?
            let highest_unlocked: Int?
            let lives: Int?
        }
    }

    /// Per-(game, difficulty) leaderboard rows.  Competitive games rank by
    /// wins, then best; Snacky Solo ("snake"/"solo") by best only (Solo has
    /// no wins); Disco Ball ("disco") by most crossings, then the
    /// faster average time per crossing (an unknown time last).  Mapped onto
    /// `PlayerProfile` with the chosen game's fields holding the
    /// per-difficulty values, so the leaderboard renders them like any board.
    func fetchMinigameDifficultyLeaderboard(game: String, difficulty: String,
                                            limit: Int = 100) async throws -> [PlayerProfile] {
        let isDisco = game == "disco"
        let sel = "player_id,wins,best" + (isDisco ? ",best_avg_ms" : "")
                + ",players(display_name,climb_level,total_stars,highest_unlocked,lives)"
        let order = isDisco ? "best.desc,best_avg_ms.asc.nullslast"
                  : (difficulty == "solo" ? "best.desc" : "wins.desc,best.desc")
        let query = "select=\(sel)&game=eq.\(game)&difficulty=eq.\(difficulty)"
                  + "&order=\(order)&limit=\(limit)"
        let data = try await send(method: "GET", path: "minigame_scores", query: query)
        let rows = try decode([MinigameScoreRow].self, from: data)
        return rows.map { row in
            let p = row.players
            var prof = PlayerProfile(id: row.player_id,
                                     displayName: p?.display_name ?? "",
                                     climbLevel: p?.climb_level ?? 1,
                                     highestUnlocked: p?.highest_unlocked ?? 1,
                                     totalStars: p?.total_stars ?? 0,
                                     lives: p?.lives ?? 0)
            switch game {
            case "snake":     prof.snakeWins = row.wins;     prof.snakeBest = row.best
            case "sumo":      prof.sumoWins = row.wins;      prof.sumoBest = row.best
            case "paintball": prof.paintballWins = row.wins; prof.paintballBest = row.best
            case "goldrush":  prof.goldrushWins = row.wins;  prof.goldrushBest = row.best
            case "marblecup": prof.marblecupWins = row.wins; prof.marblecupBest = row.best
            case "koth":      prof.kothWins = row.wins;      prof.kothBest = row.best
            case "disco":     prof.discoballBest = row.best; prof.discoballBestAvgMs = row.best_avg_ms
            default: break
            }
            return prof
        }
    }

    /// The player's rank (1-based) on every `LeaderboardBoard`, computed exactly
    /// like the on-screen leaderboard: position among players who have actually
    /// played that board.  Boards the player hasn't played are omitted from the
    /// result.  Fetches all boards concurrently; signed-in only (reads are
    /// authed).  Powers the profile "Player Ranks" section.
    func fetchAllRanks(for playerId: UUID, limit: Int = 500) async -> [String: Int] {
        await withTaskGroup(of: (String, Int?).self) { group in
            for board in LeaderboardBoard.allCases {
                group.addTask {
                    // Boards kept per difficulty are ranked by
                    // `fetchMinigameDifficultyRanks` instead.
                    if board.difficultyGameID != nil { return (board.rawValue, nil) }
                    let rows = (try? await self.fetchLeaderboard(order: board.order, limit: limit)) ?? []
                    let rank = rows.filter { board.hasPlayed($0) }
                                   .firstIndex { $0.id == playerId }
                                   .map { $0 + 1 }
                    return (board.rawValue, rank)
                }
            }
            var out: [String: Int] = [:]
            for await (key, rank) in group { if let rank { out[key] = rank } }
            return out
        }
    }

    private struct GameDifficultyKey: Decodable { let game: String; let difficulty: String }

    /// The player's rank on each per-difficulty board they actually appear on.
    /// First finds which (game,difficulty) rows they have in `minigame_scores`,
    /// then computes each rank concurrently.  Keyed "game|difficulty".  Drives
    /// the per-difficulty lines in the profile's Player Ranks section.
    func fetchMinigameDifficultyRanks(for playerId: UUID, limit: Int = 500) async -> [String: Int] {
        guard let data = try? await send(method: "GET", path: "minigame_scores",
                  query: "select=game,difficulty&player_id=eq.\(playerId.uuidString)"),
              let mine = try? decode([GameDifficultyKey].self, from: data), !mine.isEmpty
        else { return [:] }

        return await withTaskGroup(of: (String, Int?).self) { group in
            for gd in mine {
                group.addTask {
                    let rows = (try? await self.fetchMinigameDifficultyLeaderboard(
                        game: gd.game, difficulty: gd.difficulty, limit: limit)) ?? []
                    let rank = rows.firstIndex { $0.id == playerId }.map { $0 + 1 }
                    return ("\(gd.game)|\(gd.difficulty)", rank)
                }
            }
            var out: [String: Int] = [:]
            for await (key, rank) in group { if let rank { out[key] = rank } }
            return out
        }
    }

    // MARK: - Life gifts

    /// Send 1–5 lives to another player (caps enforced by RLS + table CHECKs).
    func sendLife(to recipient: UUID, amount: Int = 1) async throws {
        let me = try requireSession()
        let body = GiftInsert(sender_id: me.userId, recipient_id: recipient, amount: amount)
        _ = try await send(method: "POST", path: "life_gifts",
                           bodyData: try encoder.encode([body]),
                           prefer: "return=minimal")
    }

    /// Life gifts waiting to be claimed by the signed-in player.
    func fetchUnclaimedGifts() async throws -> [LifeGift] {
        let me = try requireSession()
        let query = "recipient_id=eq.\(me.userId.uuidString)"
            + "&claimed_at=is.null&order=created_at.asc"
        let data = try await send(method: "GET", path: "life_gifts", query: query)
        return try decode([LifeGift].self, from: data)
    }

    /// Mark a received gift claimed (credit the lives on-device after this).
    func claimGift(id: UUID) async throws {
        let body = ClaimPatch(claimed_at: Self.iso.string(from: Date()))
        _ = try await send(method: "PATCH", path: "life_gifts",
                           query: "id=eq.\(id.uuidString)",
                           bodyData: try encoder.encode(body),
                           prefer: "return=minimal")
    }

    // MARK: - Friends

    /// Find players whose display name contains `term` (case-insensitive),
    /// excluding yourself — powers the "add a friend" search box.  The search
    /// term is fully percent-escaped so the `*` wildcards stay literal while a
    /// stray `&`/`=`/space in the term can't corrupt the query string.
    func searchPlayers(matching term: String, limit: Int = 20) async throws -> [PlayerProfile] {
        let me = try requireSession()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? trimmed
        let cols = "id,display_name,climb_level,highest_unlocked,total_stars,lives"
        let query = "&display_name=ilike.*\(escaped)*"
            + "&id=neq.\(me.userId.uuidString)"
            + "&order=climb_level.desc&limit=\(limit)"
        return try await getPlayers(columns: cols, rest: query)
    }

    /// Resolve a set of player ids to their profiles (e.g. friends from edges).
    func fetchProfiles(ids: [UUID]) async throws -> [PlayerProfile] {
        guard !ids.isEmpty else { return [] }
        let list = ids.map { $0.uuidString }.joined(separator: ",")
        return try await getPlayers(
            columns: "id,display_name,climb_level,highest_unlocked,total_stars,lives,needs_lives_at",
            rest: "&id=in.(\(list))")
    }

    // MARK: - Clan life requests (give once per request)

    private struct RequestGiftRow: Decodable {
        let recipient: UUID
        let requestAt: String?
        enum CodingKeys: String, CodingKey {
            case recipient = "recipient_id"
            case requestAt = "request_at"
        }
    }

    /// Identifies one life request: the asker plus the moment they asked.
    static func requestKey(_ asker: UUID, _ askedAt: String) -> String {
        "\(asker.uuidString)|\(askedAt)"
    }

    /// The players the signed-in player has already sent an ORDINARY life gift
    /// to today (Eastern time) — "Send life" allows one per player per day.  Gifts that
    /// answered a clan request are not included.
    func fetchMyGiftsToday() async -> Set<UUID> {
        guard let me = currentUserId else { return [] }
        // The timestamp carries a "+" or "-" offset; percent-encode it so a
        // "+" is not read as a space.
        let since = SeasonCalendar.dayStartTimestamp()
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let query = "select=recipient_id,request_at&sender_id=eq.\(me.uuidString)"
            + "&request_at=is.null&created_at=gte.\(since)&limit=500"
        guard let data = try? await send(method: "GET", path: "life_gifts", query: query),
              let rows = try? decode([RequestGiftRow].self, from: data) else { return [] }
        return Set(rows.map { $0.recipient })
    }

    // MARK: - Settings kept on the server

    /// Read the player-facing numbers (member cap, request limits, season
    /// minimums) from the server into `SocialSettings.current`.  Keeps the
    /// built-in defaults when the read fails or v5 has not been run.
    func refreshSocialSettings() async {
        guard isSignedIn,
              let data = try? await send(method: "POST", path: "rpc/ra_social_settings",
                                         bodyData: Data("{}".utf8)),
              let values = try? decode([String: Int].self, from: data) else { return }
        var settings = SocialSettings(values)
        settings.loadedFromServer = true
        let loaded = settings
        await MainActor.run { SocialSettings.current = loaded }
    }

    // MARK: - Monthly clan battle

    /// One clan's standing (season score, wins, last finish), or nil when
    /// the rankings view is not available.
    func fetchClanStanding(id: UUID) async -> ClanRanking? {
        let rows = try? await getClanRows(ClanRanking.self, path: "clan_rankings",
                                          columns: Self.rankingColumns,
                                          rest: "&id=eq.\(id.uuidString)&limit=1")
        return rows?.first
    }

    private struct SeasonScoreRow: Decodable {
        let player: UUID
        let stars: Int
        enum CodingKeys: String, CodingKey { case player = "player_id"; case stars }
    }

    /// Each player's stars for this clan in the current season (month).
    /// Includes players who earned stars for the clan and have since left.
    func fetchSeasonContributions(clanId: UUID) async -> [UUID: Int] {
        let query = "select=player_id,stars&clan_id=eq.\(clanId.uuidString)"
            + "&season=eq.\(SeasonCalendar.seasonKey())"
        guard let data = try? await send(method: "GET", path: "clan_season_scores", query: query),
              let rows = try? decode([SeasonScoreRow].self, from: data) else { return [:] }
        var map: [UUID: Int] = [:]
        for row in rows { map[row.player] = row.stars }
        return map
    }

    /// The signed-in player's unclaimed season prizes, newest first.
    func fetchUnclaimedPrizes() async -> [SeasonPrize] {
        guard let me = currentUserId else { return [] }
        let query = "select=season,clan_name,clan_rank,clans_ranked,tier,contribution,coins"
            + "&player_id=eq.\(me.uuidString)&claimed_at=is.null&order=season.desc&limit=24"
        guard let data = try? await send(method: "GET", path: "clan_season_prizes", query: query),
              let rows = try? decode([SeasonPrize].self, from: data) else { return [] }
        return rows
    }

    private struct ClaimBody: Encodable { let p_season: String }

    /// Claim one prize on the server.  Returns the coins to credit on the
    /// device — 0 when it was already claimed.  Server first: a failed call
    /// must never credit coins.
    func claimSeasonPrize(season: String) async throws -> Int {
        let data = try await send(method: "POST", path: "rpc/ra_claim_season_prize",
                                  bodyData: try encoder.encode(ClaimBody(p_season: season)))
        return try decode(Int.self, from: data)
    }

    /// The life requests the signed-in player has ALREADY given to, as
    /// `requestKey`s.  Read from the server, so it survives closing the app.
    /// Empty when signed out, or before docs/social-schema-v5.sql is run.
    func fetchMyRequestGiftKeys() async -> Set<String> {
        guard let me = currentUserId else { return [] }
        let query = "select=recipient_id,request_at&sender_id=eq.\(me.uuidString)"
            + "&request_at=not.is.null&order=created_at.desc&limit=200"
        guard let data = try? await send(method: "GET", path: "life_gifts", query: query),
              let rows = try? decode([RequestGiftRow].self, from: data) else { return [] }
        var keys: Set<String> = []
        for row in rows {
            if let at = row.requestAt { keys.insert(Self.requestKey(row.recipient, at)) }
        }
        return keys
    }

    /// How many clanmates have an open life request the signed-in player has
    /// not given to yet — the number on the red badge.  0 when signed out or
    /// in no clan.  Four small reads.
    func countOpenClanRequests() async -> Int {
        guard let me = currentUserId,
              let membership = try? await fetchMyClanMembership(),
              let roster = try? await fetchClanRoster(clanId: membership.clanId) else { return 0 }
        let others = roster.map { $0.playerId }.filter { $0 != me }
        guard !others.isEmpty,
              let profiles = try? await fetchProfiles(ids: others) else { return 0 }
        let asking = profiles.filter { $0.isAskingForLives }
        guard !asking.isEmpty else { return 0 }
        let given = await fetchMyRequestGiftKeys()
        return asking.filter { !given.contains(Self.requestKey($0.id, $0.needsLivesAt ?? "")) }.count
    }

    /// Every friendship edge involving the signed-in player.  RLS already
    /// scopes this to rows where you are the requester or addressee, so the UI
    /// just splits them into incoming / outgoing / accepted.
    func fetchFriendships() async throws -> [Friendship] {
        _ = try requireSession()
        let query = "select=id,requester_id,addressee_id,status,created_at"
            + "&order=created_at.desc"
        let data = try await send(method: "GET", path: "friendships", query: query)
        return try decode([Friendship].self, from: data)
    }

    /// Send a friend request (status defaults to `pending`).  The unique
    /// (requester, addressee) constraint means re-sending throws; the UI avoids
    /// that by only offering "Add" when no edge exists yet.
    func sendFriendRequest(to addressee: UUID) async throws {
        let me = try requireSession()
        let body = FriendshipInsert(requester_id: me.userId,
                                    addressee_id: addressee,
                                    status: "pending")
        _ = try await send(method: "POST", path: "friendships",
                           bodyData: try encoder.encode([body]),
                           prefer: "return=minimal")
    }

    /// Accept a pending request (the addressee flips it to `accepted`).
    func acceptFriendRequest(id: UUID) async throws {
        let body = FriendStatusPatch(status: "accepted")
        _ = try await send(method: "PATCH", path: "friendships",
                           query: "id=eq.\(id.uuidString)",
                           bodyData: try encoder.encode(body),
                           prefer: "return=minimal")
    }

    /// Remove an edge — declining an incoming request OR unfriending.  RLS
    /// permits either participant to delete.
    func removeFriendship(id: UUID) async throws {
        _ = try await send(method: "DELETE", path: "friendships",
                           query: "id=eq.\(id.uuidString)",
                           prefer: "return=minimal")
    }

    // MARK: - Clans

    private static let clanColumns =
        "id,name,tag,description,owner_id,created_at,updated_at"
    /// Columns added by database step 13 (docs/social/clan-look.sql): the
    /// clan's preset icon and color.
    private static let clanLookColumns = ",icon,color"

    /// Read clans (from `clans` or the `clan_rankings` view), asking for the
    /// clan's icon and color too.  Until step 13 has been run the server
    /// answers 400 for those columns, so this falls back to the query
    /// without them and the app shows the default icon and color.
    /// `columns` is the select list without the look columns; `rest` starts
    /// with "&".
    private func getClanRows<Row: Decodable>(_ type: Row.Type, path: String,
                                             columns: String, rest: String) async throws -> [Row] {
        let attempts = [
            "select=\(columns)\(Self.clanLookColumns)" + rest,
            "select=\(columns)" + rest,
        ]
        var lastError: Error = SocialError.emptyResponse
        for query in attempts {
            do {
                let data = try await send(method: "GET", path: path, query: query)
                return try decode([Row].self, from: data)
            } catch SocialError.http(let status, let body) where status == 400 || status == 404 {
                lastError = SocialError.http(status: status, body: body)
            }
        }
        throw lastError
    }
    private static let memberColumns =
        "clan_id,player_id,role,joined_at"

    /// The signed-in player's clan membership, or nil if they're in none.
    /// (A player belongs to at most one clan — enforced by a unique index.)
    func fetchMyClanMembership() async throws -> ClanMember? {
        let me = try requireSession()
        let query = "select=\(Self.memberColumns)"
            + "&player_id=eq.\(me.userId.uuidString)&limit=1"
        let data = try await send(method: "GET", path: "clan_members", query: query)
        return try decode([ClanMember].self, from: data).first
    }

    /// A single clan by id (nil if it no longer exists, e.g. just disbanded).
    func fetchClan(id: UUID) async throws -> Clan? {
        _ = try requireSession()
        return try await getClanRows(Clan.self, path: "clans", columns: Self.clanColumns,
                                     rest: "&id=eq.\(id.uuidString)&limit=1").first
    }

    /// Recent clans to browse when not searching.
    func fetchClans(limit: Int = 30) async throws -> [Clan] {
        _ = try requireSession()
        return try await getClanRows(Clan.self, path: "clans", columns: Self.clanColumns,
                                     rest: "&order=created_at.desc&limit=\(limit)")
    }

    /// Find clans whose name contains `term` (case-insensitive).  Mirrors
    /// `searchPlayers`: the term is fully percent-escaped so the `*` wildcards
    /// stay literal and a stray `&`/`=` can't corrupt the query string.
    func searchClans(matching term: String, limit: Int = 30) async throws -> [Clan] {
        _ = try requireSession()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? trimmed
        return try await getClanRows(Clan.self, path: "clans", columns: Self.clanColumns,
                                     rest: "&name=ilike.*\(escaped)*&order=name.asc&limit=\(limit)")
    }

    private static let rankingColumns =
        "id,name,tag,description,owner_id,created_at,updated_at,"
        + "member_count,total_levels,total_stars,season_score,"
        + "season_wins,last_season,last_season_rank,last_season_clans,last_season_tier"

    /// Clans ranked by this season's score, total levels or total stars (the
    /// read-only `clan_rankings` view from docs/social-schema-v5.sql).  Throws
    /// until that file has been run.
    func fetchClanRankings(sort: ClanRankSort, limit: Int = 100) async throws -> [ClanRanking] {
        _ = try requireSession()
        return try await getClanRows(ClanRanking.self, path: "clan_rankings",
                                     columns: Self.rankingColumns,
                                     rest: "&order=\(sort.orderClause)&limit=\(limit)")
    }

    /// Every membership row for a clan (resolve player_ids to profiles via
    /// `fetchProfiles` to render the roster).
    func fetchClanRoster(clanId: UUID) async throws -> [ClanMember] {
        _ = try requireSession()
        let query = "select=\(Self.memberColumns)&clan_id=eq.\(clanId.uuidString)"
        let data = try await send(method: "GET", path: "clan_members", query: query)
        return try decode([ClanMember].self, from: data)
    }

    /// Create a clan (you become its owner) and join it as `owner`.  Two
    /// writes: insert the clan with `return=representation` to recover its
    /// generated id, then insert your owner membership row.
    /// The name and tag are built from a `PresetNames.Choice` and the
    /// description must be one of the preset options (anything else is sent
    /// as empty), so no free text can reach the server from here.
    func createClan(name choice: PresetNames.Choice, description: String) async throws -> Clan {
        let me = try requireSession()
        let insert = ClanInsert(name: PresetNames.clanName(choice),
                                tag: PresetNames.clanTag(choice),
                                description: PresetNames.isValidClanDescription(description) ? description : "",
                                owner_id: me.userId)
        let data = try await send(method: "POST", path: "clans",
                                  bodyData: try encoder.encode([insert]),
                                  prefer: "return=representation")
        guard let clan = try decode([Clan].self, from: data).first else {
            throw SocialError.emptyResponse
        }
        let membership = ClanMemberInsert(clan_id: clan.id,
                                          player_id: me.userId, role: "owner")
        _ = try await send(method: "POST", path: "clan_members",
                           bodyData: try encoder.encode([membership]),
                           prefer: "return=minimal")
        return clan
    }

    /// Join an existing clan as a `member`.  The one-clan-per-player unique
    /// index makes this throw if you're already in one, so the UI only offers
    /// Join when you have no membership.
    func joinClan(id: UUID) async throws {
        let me = try requireSession()
        let membership = ClanMemberInsert(clan_id: id,
                                          player_id: me.userId, role: "member")
        _ = try await send(method: "POST", path: "clan_members",
                           bodyData: try encoder.encode([membership]),
                           prefer: "return=minimal")
    }

    /// Leave a clan (deletes only your own membership row).
    func leaveClan(id: UUID) async throws {
        let me = try requireSession()
        let query = "clan_id=eq.\(id.uuidString)&player_id=eq.\(me.userId.uuidString)"
        _ = try await send(method: "DELETE", path: "clan_members",
                           query: query, prefer: "return=minimal")
    }

    /// Owner only: remove another member from the clan.  (The database's
    /// "leave or owner removes" rule refuses anyone else.)  The season stars
    /// the player already earned for the clan stay with the clan.
    func removeClanMember(clanId: UUID, playerId: UUID) async throws {
        _ = try requireSession()
        // Ask for the deleted row back: a delete the server refuses (the
        // caller is no longer the owner) answers "ok" with nothing removed,
        // and that must not be reported as a removal.
        let data = try await send(method: "DELETE", path: "clan_members",
                                  query: "clan_id=eq.\(clanId.uuidString)&player_id=eq.\(playerId.uuidString)",
                                  prefer: "return=representation")
        let removed = try decode([ClanMember].self, from: data)
        if removed.isEmpty { throw SocialError.emptyResponse }
    }

    private struct TransferBody: Encodable {
        let p_clan: UUID
        let p_new_owner: UUID
    }

    /// Owner only: hand the clan to another member.  The server swaps the two
    /// roles (docs/social-schema-v5.sql, `ra_transfer_clan_ownership`).
    func transferClanOwnership(clanId: UUID, to newOwner: UUID) async throws {
        _ = try await send(method: "POST", path: "rpc/ra_transfer_clan_ownership",
                           bodyData: try encoder.encode(TransferBody(p_clan: clanId, p_new_owner: newOwner)))
    }

    /// Disband a clan you own — deleting the row cascades every membership.
    /// RLS permits this only for the owner.
    func disbandClan(id: UUID) async throws {
        _ = try requireSession()
        _ = try await send(method: "DELETE", path: "clans",
                           query: "id=eq.\(id.uuidString)", prefer: "return=minimal")
    }

    /// Rename a clan — the first of the owner's personalization knobs (the RLS
    /// "clans update by owner" policy scopes the PATCH, so a non-owner's call
    /// matches zero rows).  The unique lower(name) index makes a taken name
    /// (or its derived tag) throw; surface it as "name taken".
    /// The new name is a `PresetNames.Choice`; the derived tag changes with it.
    func renameClan(id: UUID, name choice: PresetNames.Choice) async throws {
        _ = try requireSession()
        let body = ClanUpdatePatch(name: PresetNames.clanName(choice),
                                   tag: PresetNames.clanTag(choice))
        _ = try await send(method: "PATCH", path: "clans",
                           query: "id=eq.\(id.uuidString)",
                           bodyData: try encoder.encode(body),
                           prefer: "return=minimal")
    }

    private struct ClanLookPatch: Encodable {
        let icon: String
        let color: String
    }

    /// Owner only: set the clan's icon and color, both from the preset lists
    /// in `ClanLook` (the database checks them against the same lists, and
    /// the "clans update by owner" rule scopes the PATCH).  Throws when the
    /// server refused or changed nothing (not the owner, or step 13 not run).
    func setClanLook(id: UUID, icon: String, color: String) async throws {
        _ = try requireSession()
        guard ClanLook.icons.contains(icon), ClanLook.colorKeys.contains(color) else {
            throw SocialError.emptyResponse
        }
        let data = try await send(method: "PATCH", path: "clans",
                                  query: "id=eq.\(id.uuidString)",
                                  bodyData: try encoder.encode(ClanLookPatch(icon: icon, color: color)),
                                  prefer: "return=representation")
        let rows = try decode([Clan].self, from: data)
        if rows.isEmpty { throw SocialError.emptyResponse }
    }

    // MARK: - Ask for a life + clan activity feed  (schema v2)

    /// Flag yourself as needing lives ("Ask for a life") — clan-mates see it on
    /// the roster and can send.  Sets players.needs_lives_at = now().
    func askForLives() async throws {
        let me = try requireSession()
        let body = NeedsLivesPatch(needs_lives_at: Self.iso.string(from: Date()))
        _ = try await send(method: "PATCH", path: "players",
                           query: "id=eq.\(me.userId.uuidString)",
                           bodyData: try encoder.encode(body), prefer: "return=minimal")
    }

    /// Clear the needs-lives flag (topped up, or cancelled).
    func clearNeedsLives() async throws {
        let me = try requireSession()
        let body = NeedsLivesPatch(needs_lives_at: nil)
        _ = try await send(method: "PATCH", path: "players",
                           query: "id=eq.\(me.userId.uuidString)",
                           bodyData: try encoder.encode(body), prefer: "return=minimal")
    }

    /// Recent clan activity (newest first) — powers the activity feed.
    func fetchClanEvents(clanId: UUID, limit: Int = 40) async throws -> [ClanEvent] {
        _ = try requireSession()
        let query = "select=id,clan_id,actor_id,target_id,kind,created_at"
            + "&clan_id=eq.\(clanId.uuidString)&order=created_at.desc&limit=\(limit)"
        let data = try await send(method: "GET", path: "clan_events", query: query)
        return try decode([ClanEvent].self, from: data)
    }

    /// Post a clan activity event.  Kinds (see docs/social-schema-v3.sql):
    /// created / joined / left / sent_life / requested_life / thanked /
    /// requested_promotion / renamed, plus the premade quick-chat kinds
    /// (`chat_*`) — the chat text itself never leaves the device; the client
    /// maps each kind to a fixed string.
    func postClanEvent(clanId: UUID, kind: String, target: UUID? = nil) async throws {
        let me = try requireSession()
        let body = ClanEventInsert(clan_id: clanId, actor_id: me.userId,
                                   target_id: target, kind: kind)
        _ = try await send(method: "POST", path: "clan_events",
                           bodyData: try encoder.encode([body]), prefer: "return=minimal")
    }

    // MARK: - Networking core

    private func requireSession() throws -> Session {
        guard let session else { throw SocialError.notSignedIn }
        return session
    }

    /// The signed-in player's bearer token, for the trophy showcase push
    /// (S3-T3, `SocialTrophyBackend`). A thin accessor so `TrophySyncService`
    /// can drive the `player_trophies` REST call through its own backend seam
    /// (kept out of `SocialClient` to preserve its network-abstraction seam)
    /// without exposing the private `Session`. Throws `.notSignedIn` when
    /// signed out, so the signed-in push is a no-op until sign-in.
    func trophyAccessToken() throws -> String {
        try requireSession().token
    }

    /// Unit and UI test runs never touch the live server (RuntimeEnvironment
    /// in AnalyticsClient.swift): every request here fails fast instead.
    private static func requireLiveServerAllowed() throws {
        if RuntimeEnvironment.isRunningTests {
            throw SocialError.http(status: 0, body: "live server disabled during tests")
        }
    }

    private func send(method: String,
                      path: String,
                      query: String = "",
                      bodyData: Data? = nil,
                      prefer: String? = nil) async throws -> Data {
        try Self.requireLiveServerAllowed()
        let session = try requireSession()
        let urlString = "\(Self.projectURL)/rest/v1/\(path)"
            + (query.isEmpty ? "" : "?\(query)")
        guard let url = URL(string: urlString) else { throw SocialError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json",            forHTTPHeaderField: "Content-Type")
        req.setValue(Self.apiKey,                   forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.token)",     forHTTPHeaderField: "Authorization")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SocialError.http(status: -1, body: "no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SocialError.http(status: http.statusCode,
                                   body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(type, from: data) }
        catch { throw SocialError.decoding(error) }
    }
}

// ===========================================================================
// PresetNames — every player-visible name is ASSEMBLED FROM PRESET PARTS.
//
// Roll Along has no free-text fields that other players can see.  A nickname
// is  <word><word>  ("SwiftComet", no number, not unique — the player's
// Adventure level is shown beside it as part of the name); a clan name is
// <word> <plural word> <number>  ("Swift Rockets 42"); the clan tag is derived
// from the name ("SR42"); the clan description is one of a fixed list (or
// none).  Clan chat was already fixed phrases.
//
// The same lists are enforced on the server by docs/social-schema-v4.sql
// (GENERATED from the same source as this block — change both together), so
// a modified client cannot store free text either.  Anything that does not
// parse — e.g. a name saved before this rule existed — is never shown: the
// model accessors below fall back to an empty string and the views show
// their generic "Roller" / "Clan" placeholders.
//
// Kept in this file (not a new one) to avoid touching the Xcode project
// structure, like the Keychain helper in AppleAuthManager.swift.
// ===========================================================================
enum PresetNames {
    // Word lists are alphabetical so the picker wheels are easy to scan.
    // A stored name is the assembled TEXT, never an index, so reordering or
    // adding words never changes anyone's existing name.

    /// First word of a nickname (173 words, each <= 5 letters).
    static let adjectives: [String] = [
        "Able", "Agile", "Airy", "Alert", "Alpha", "Amber", "Aqua", "Astro",
        "Avid", "Azure", "Balmy", "Blue", "Bold", "Brave", "Brisk", "Busy",
        "Calm", "Chief", "Chill", "Clear", "Comfy", "Cool", "Coral", "Cozy",
        "Crisp", "Curly", "Cute", "Cyan", "Daily", "Dandy", "Deft", "Dewy",
        "Dizzy", "Dusty", "Eager", "Early", "Elite", "Epic", "Fair", "Fancy",
        "Fast", "Fiery", "Fine", "First", "Fizzy", "Fleet", "Foamy", "Fresh",
        "Funny", "Fuzzy", "Giant", "Giddy", "Glad", "Gold", "Goofy", "Grand",
        "Great", "Green", "Gutsy", "Handy", "Happy", "Hardy", "Hasty", "Hazel",
        "Hefty", "Hyper", "Icy", "Ideal", "Inky", "Iron", "Ivory", "Jade",
        "Jazzy", "Jolly", "Jumbo", "Jumpy", "Keen", "Kind", "Kooky", "Lanky",
        "Light", "Lilac", "Lime", "Lofty", "Loyal", "Lucid", "Lucky", "Lunar",
        "Magic", "Major", "Mega", "Merry", "Mild", "Mint", "Misty", "Mocha",
        "Mossy", "Neat", "Neon", "Nifty", "Noble", "Olive", "Onyx", "Opal",
        "Peach", "Peppy", "Pink", "Plum", "Plush", "Polar", "Prime", "Proud",
        "Pure", "Quick", "Quiet", "Rainy", "Rapid", "Regal", "Retro", "Rocky",
        "Rosy", "Rowdy", "Royal", "Ruby", "Rusty", "Sage", "Sandy", "Savvy",
        "Shiny", "Silky", "Silly", "Sleek", "Smart", "Snowy", "Snug", "Solar",
        "Solid", "Sonic", "Spry", "Stark", "Steel", "Stony", "Sunny", "Super",
        "Sweet", "Swift", "Tame", "Tangy", "Tawny", "Teal", "Tidy", "Tiny",
        "Topaz", "Tough", "Trim", "True", "Turbo", "Urban", "Vast", "Vital",
        "Vivid", "Wacky", "Warm", "Wavy", "Wild", "Windy", "Wise", "Witty",
        "Young", "Zany", "Zen", "Zesty", "Zippy",
    ]

    /// Second word of a nickname (206 words, each <= 5 letters).  Never the
    /// same word as a clan second word, in singular or plural (`clanNouns`).
    static let nouns: [String] = [
        "Acorn", "Aspen", "Atlas", "Bear", "Bee", "Bison", "Blaze", "Bloom",
        "Bolt", "Brook", "Bunny", "Calf", "Camel", "Cedar", "Chalk", "Charm",
        "Chime", "Cliff", "Cloud", "Coast", "Cobra", "Colt", "Comet", "Cove",
        "Crane", "Creek", "Crest", "Crow", "Cub", "Daisy", "Dart", "Dawn",
        "Deer", "Delta", "Dingo", "Dove", "Drake", "Drift", "Duck", "Dune",
        "Eagle", "Echo", "Egret", "Elk", "Elm", "Ember", "Emu", "Fable",
        "Fawn", "Fern", "Field", "Finch", "Fjord", "Flame", "Flare", "Flash",
        "Flint", "Foal", "Forge", "Fox", "Frog", "Frost", "Gale", "Gecko",
        "Gem", "Glade", "Glow", "Gnome", "Gnu", "Goose", "Grove", "Gull",
        "Gust", "Hail", "Hare", "Hawk", "Heath", "Heron", "Hippo", "Holly",
        "Horse", "Hound", "Ibex", "Ibis", "Inlet", "Iris", "Ivy", "Jay",
        "Jet", "Jewel", "Kite", "Kiwi", "Knoll", "Koala", "Koi", "Lake",
        "Lamb", "Lark", "Leaf", "Lemur", "Lily", "Lion", "Llama", "Lotus",
        "Lynx", "Macaw", "Mango", "Manta", "Maple", "Marsh", "Mesa", "Mink",
        "Mist", "Moon", "Moose", "Moss", "Moth", "Mouse", "Nest", "Newt",
        "Nova", "Oak", "Oasis", "Ocean", "Okapi", "Orb", "Orbit", "Orca",
        "Otter", "Owl", "Panda", "Peak", "Pearl", "Petal", "Pika", "Pilot",
        "Pine", "Pixel", "Plume", "Pluto", "Pony", "Poppy", "Prism", "Puma",
        "Pup", "Quail", "Quark", "Quest", "Quill", "Racer", "Radar", "Rain",
        "Raven", "Ray", "Reed", "Reef", "Rhino", "Ridge", "River", "Robin",
        "Rook", "Rover", "Sable", "Sail", "Shark", "Sky", "Sled", "Slope",
        "Sloth", "Snail", "Spark", "Squid", "Stag", "Star", "Stone", "Stork",
        "Storm", "Sun", "Surf", "Swan", "Tapir", "Tern", "Tetra", "Tide",
        "Tiger", "Torch", "Trail", "Trout", "Tulip", "Tuna", "Twig", "Vale",
        "Vapor", "Vine", "Viper", "Vole", "Wave", "Whale", "Wind", "Wing",
        "Wolf", "Wren", "Yak", "Yew", "Zebra", "Zebu",
    ]

    /// First word of a clan name (221 words: the nickname list plus longer ones).
    static let clanAdjectives: [String] = [
        "Able", "Agile", "Airy", "Alert", "Alpha", "Amber", "Ancient", "Aqua",
        "Arctic", "Astro", "Avid", "Azure", "Balmy", "Blazing", "Blue", "Bold",
        "Brave", "Brisk", "Bronze", "Busy", "Calm", "Chief", "Chill", "Clear",
        "Clever", "Cobalt", "Comfy", "Cool", "Copper", "Coral", "Cosmic", "Cozy",
        "Crimson", "Crisp", "Crystal", "Curly", "Cute", "Cyan", "Daily", "Dandy",
        "Daring", "Deft", "Dewy", "Dizzy", "Dusty", "Eager", "Early", "Electric",
        "Elite", "Emerald", "Endless", "Epic", "Eternal", "Fair", "Fancy", "Fast",
        "Fearless", "Fiery", "Fine", "First", "Fizzy", "Fleet", "Foamy", "Fresh",
        "Frosted", "Funny", "Fuzzy", "Galactic", "Gentle", "Giant", "Giddy", "Glad",
        "Gold", "Golden", "Goofy", "Grand", "Granite", "Great", "Green", "Gutsy",
        "Handy", "Happy", "Hardy", "Hasty", "Hazel", "Hefty", "Hidden", "Humble",
        "Hyper", "Icy", "Ideal", "Inky", "Iron", "Ivory", "Jade", "Jazzy",
        "Jolly", "Jumbo", "Jumpy", "Keen", "Kind", "Kooky", "Lanky", "Light",
        "Lightning", "Lilac", "Lime", "Lively", "Lofty", "Loyal", "Lucid", "Lucky",
        "Lunar", "Magic", "Major", "Marble", "Mega", "Mellow", "Merry", "Mighty",
        "Mild", "Mint", "Misty", "Mocha", "Modern", "Moonlit", "Mossy", "Neat",
        "Neon", "Nifty", "Nimble", "Noble", "Olive", "Onyx", "Opal", "Peach",
        "Peppy", "Pink", "Plum", "Plush", "Polar", "Prime", "Proud", "Pure",
        "Quick", "Quiet", "Radiant", "Rainbow", "Rainy", "Rapid", "Regal", "Retro",
        "Rising", "Roaring", "Rocky", "Rolling", "Rosy", "Rowdy", "Royal", "Ruby",
        "Rusty", "Sage", "Sandy", "Savvy", "Scarlet", "Shining", "Shiny", "Silky",
        "Silly", "Silver", "Sleek", "Smart", "Snowy", "Snug", "Soaring", "Solar",
        "Solid", "Sonic", "Spry", "Stark", "Steady", "Steel", "Stellar", "Stony",
        "Sunlit", "Sunny", "Super", "Sweet", "Swift", "Tame", "Tangy", "Tawny",
        "Teal", "Thunder", "Tidy", "Tiny", "Topaz", "Tough", "Trim", "True",
        "Tumbling", "Turbo", "Urban", "Valiant", "Vast", "Vibrant", "Vital", "Vivid",
        "Wacky", "Wandering", "Warm", "Wavy", "Wild", "Windy", "Wise", "Witty",
        "Young", "Zany", "Zen", "Zesty", "Zippy",
    ]

    /// Second word of a clan name (202 plural words).  None is the plural
    /// (or the same word) of a nickname second word: the two lists are separate.
    static let clanNouns: [String] = [
        "Acrobats", "Adventurers", "Albatrosses", "Alchemists", "Alligators", "Alpacas", "Anchors", "Antelopes",
        "Architects", "Armadillos", "Arrows", "Artists", "Astronauts", "Avalanches", "Aviators", "Badgers",
        "Banners", "Beacons", "Bells", "Blizzards", "Bobcats", "Boomerangs", "Boulders", "Breezes",
        "Buccaneers", "Buffaloes", "Builders", "Canyons", "Captains", "Caribou", "Cascades", "Champions",
        "Cheetahs", "Chinchillas", "Chipmunks", "Climbers", "Commanders", "Condors", "Craters", "Crickets",
        "Crowns", "Currents", "Cyclones", "Dalmatians", "Defenders", "Diamonds", "Dolphins", "Dragonflies",
        "Dragons", "Dreamers", "Drummers", "Eclipses", "Engineers", "Evergreens", "Explorers", "Falcons",
        "Feathers", "Ferrets", "Fireflies", "Fireworks", "Flags", "Flamingos", "Fountains", "Galaxies",
        "Gardens", "Gazelles", "Gears", "Geysers", "Gibbons", "Giraffes", "Glaciers", "Gorillas",
        "Griffins", "Grizzlies", "Guardians", "Hammers", "Hamsters", "Harbors", "Hedgehogs", "Helmets",
        "Hummingbirds", "Huskies", "Icebergs", "Inventors", "Islands", "Jackrabbits", "Jaguars", "Jesters",
        "Jugglers", "Jungles", "Kangaroos", "Kingfishers", "Ladybugs", "Lagoons", "Lanterns", "Legends",
        "Leopards", "Lighthouses", "Lobsters", "Magicians", "Magnets", "Mammoths", "Manatees", "Marbles",
        "Mariners", "Marmots", "Mavericks", "Meadows", "Medals", "Meerkats", "Meteors", "Mirrors",
        "Mongooses", "Mountains", "Mustangs", "Narwhals", "Navigators", "Nebulas", "Ninjas", "Nomads",
        "Ocelots", "Octopuses", "Orangutans", "Orchards", "Ospreys", "Ostriches", "Paddles", "Paladins",
        "Panthers", "Parrots", "Pebbles", "Pelicans", "Penguins", "Pennants", "Pheasants", "Pinwheels",
        "Pioneers", "Pirates", "Planets", "Platypuses", "Porcupines", "Prairies", "Puffins", "Puzzles",
        "Pythons", "Raccoons", "Rainbows", "Rangers", "Rascals", "Redwoods", "Ribbons", "Riders",
        "Roadrunners", "Rockets", "Runners", "Sailors", "Salamanders", "Saplings", "Sapphires", "Satellites",
        "Scouts", "Seekers", "Sentinels", "Sequoias", "Shields", "Skaters", "Skippers", "Snowflakes",
        "Sparrows", "Sprinters", "Sprockets", "Squirrels", "Starlings", "Strikers", "Summits", "Sunbeams",
        "Telescopes", "Tokens", "Tornadoes", "Tortoises", "Toucans", "Travelers", "Trekkers", "Trophies",
        "Trumpets", "Tumblers", "Turtles", "Unicorns", "Valleys", "Vikings", "Volcanoes", "Voyagers",
        "Wagons", "Walruses", "Wanderers", "Whistles", "Wildcats", "Willows", "Wizards", "Wolverines",
        "Yetis", "Zephyrs",
    ]

    /// The fixed clan descriptions a clan owner can pick from.
    static let clanDescriptions: [String] = [
        "Friendly clan. Everyone is welcome.",
        "Daily players who share lives.",
        "Casual players. No pressure.",
        "Chasing the top of the leaderboard.",
        "Minigame fans.",
        "Trophy hunters.",
        "Friends and family.",
        "New players welcome. We help each other out.",
    ]

    /// Numbers that are never offered or accepted.
    static let blockedNumbers: Set<Int> = [69, 88, 420, 666]
    /// Longest possible nickname, in characters (the longest first word plus
    /// the longest second word).  The database allows up to 24.
    static let nicknameMaxLength: Int =
        (adjectives.map(\.count).max() ?? 0) + (nouns.map(\.count).max() ?? 0)
    /// Clan numbers: 1...999 minus the blocked ones.
    static let clanNumbers: [Int] = (1...999).filter { !blockedNumbers.contains($0) }

    /// Stored for a signed-in player who has not picked a nickname yet.
    static let defaultNickname = "Roller"

    /// One selection: an index into the first-word list, an index into the
    /// second-word list, and a number.  Which lists depends on what is being
    /// named: `adjectives`/`nouns` for a nickname, `clanAdjectives`/
    /// `clanNouns` for a clan.  A NICKNAME HAS NO NUMBER: its `number` is
    /// always 0 and is never shown or stored.
    struct Choice: Equatable {
        var adjective: Int
        var noun: Int
        var number: Int
    }

    static func randomNicknameChoice() -> Choice {
        Choice(adjective: Int.random(in: 0..<adjectives.count),
               noun:      Int.random(in: 0..<nouns.count),
               number:    0)
    }

    static func randomClanChoice() -> Choice {
        Choice(adjective: Int.random(in: 0..<clanAdjectives.count),
               noun:      Int.random(in: 0..<clanNouns.count),
               number:    clanNumbers.randomElement() ?? 1)
    }

    // MARK: Build

    /// A nickname is the two words only ("SwiftComet").  The player's
    /// Adventure level is shown beside it everywhere (`PlayerNameLabel`), in
    /// the place a number used to occupy.  Nicknames are not unique.
    static func nickname(_ c: Choice) -> String {
        adjectives[c.adjective] + nouns[c.noun]
    }

    static func clanName(_ c: Choice) -> String {
        "\(clanAdjectives[c.adjective]) \(clanNouns[c.noun]) \(c.number)"
    }

    /// The clan tag is derived, never typed: the two initials + the number
    /// ("Swift Rockets 42" -> "SR42", 3-5 characters).
    static func clanTag(_ c: Choice) -> String {
        "\(clanAdjectives[c.adjective].prefix(1))\(clanNouns[c.noun].prefix(1))".uppercased()
            + String(c.number)
    }

    // MARK: Parse / validate

    private static func number(_ digits: String, upTo maximum: Int) -> Int? {
        guard !digits.isEmpty, digits.first != "0",
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let n = Int(digits), (1...maximum).contains(n),
              !blockedNumbers.contains(n) else { return nil }
        return n
    }

    /// The two words of a nickname, or nil when `s` is not exactly
    /// `<first word><second word>`.
    static func parseNickname(_ s: String) -> Choice? {
        for (ai, adj) in adjectives.enumerated() where s.hasPrefix(adj) {
            let rest = String(s.dropFirst(adj.count))
            if let ni = nouns.firstIndex(of: rest) {
                return Choice(adjective: ai, noun: ni, number: 0)
            }
        }
        return nil
    }

    /// A nickname in the format used before numbers were dropped
    /// (`<first word><second word><1…99>`, e.g. "SwiftComet42"): returns the
    /// two words.  Lets a name saved by an earlier build, or not yet
    /// rewritten by docs/social-schema-v4.sql, keep showing — without its
    /// number.
    static func parseLegacyNickname(_ s: String) -> Choice? {
        let digits = s.reversed().prefix { $0.isASCII && $0.isNumber }.count
        guard (1...2).contains(digits),
              number(String(s.suffix(digits)), upTo: 99) != nil else { return nil }
        return parseNickname(String(s.dropLast(digits)))
    }

    static func parseClanName(_ s: String) -> Choice? {
        let parts = s.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let ai = clanAdjectives.firstIndex(of: parts[0]),
              let ni = clanNouns.firstIndex(of: parts[1]),
              let n  = number(parts[2], upTo: 999) else { return nil }
        return Choice(adjective: ai, noun: ni, number: n)
    }

    static func isValidNickname(_ s: String) -> Bool {
        s == defaultNickname || parseNickname(s) != nil
    }

    static func isValidClanDescription(_ s: String) -> Bool {
        s.isEmpty || clanDescriptions.contains(s)
    }

    /// A nickname safe to show: the value itself when it is a preset name,
    /// the two words when it is an old-format name with a number, else ""
    /// (callers show their generic placeholder).
    static func shownNickname(_ raw: String) -> String {
        if isValidNickname(raw) { return raw }
        if let old = parseLegacyNickname(raw) { return nickname(old) }
        return ""
    }
}

// ===========================================================================
// Errors
// ===========================================================================
enum SocialError: Error {
    case notSignedIn
    case badURL
    case emptyResponse
    case http(status: Int, body: String)
    case decoding(Error)
}

// ===========================================================================
// Wire models — keys match docs/social-schema.sql column names.
// ===========================================================================

/// A player's public profile + game stats (no PII).
struct PlayerProfile: Codable, Identifiable, Hashable {
    let id: UUID
    /// The stored display name exactly as the server returned it.  Never show
    /// this directly — use `displayName`, which only passes preset names.
    private var rawDisplayName: String
    /// The name to show: the stored value when it is a preset-format name
    /// (see `PresetNames`), else "" so views fall back to "Roller".
    var displayName: String { PresetNames.shownNickname(rawDisplayName) }
    var climbLevel: Int
    var highestUnlocked: Int
    var totalStars: Int
    var lives: Int
    // Lifetime coins picked up across levels. Optional so reads still decode on
    // pre-migration rows / queries that don't select it (treated as 0).
    var coinsCollected: Int?
    // Minigame leaderboards (all optional / decode-resilient like coins):
    //   pinballBest  — best single Pinball score
    //   zenSeconds   — total seconds spent in Zen Garden
    //   goldrushBest — most coins caught in one Gold Rush match
    var pinballBest: Int?
    var zenSeconds: Int?
    var goldrushBest: Int?
    // Competitive-mode bests + lifetime win tallies (all optional /
    // decode-resilient like the stats above; absent → 0).  See competitiveBest /
    // competitiveWins for keyed lookups by GameMode id.
    var snakeBest: Int?
    var sumoBest: Int?
    var paintballBest: Int?
    var marblecupBest: Int?
    var kothBest: Int?
    var snakeWins: Int?
    var sumoWins: Int?
    var paintballWins: Int?
    var marblecupWins: Int?
    var kothWins: Int?
    var goldrushWins: Int?
    // Roll Up: best height (meters) + the duration (seconds) of that best run.
    var rollupBest: Int?
    var rollupBestSeconds: Int?
    // Disco Ball: most crossings in one run (any difficulty) and that run's
    // average time per crossing, in milliseconds.  Absent until
    // docs/leaderboard-discoball.sql is run, and only selected by the Disco
    // Ball board.
    var discoballBest: Int? = nil
    var discoballBestAvgMs: Int? = nil
    // Server-managed timestamps; present on reads, omitted on writes.
    var createdAt: String?
    var updatedAt: String?
    var lastSeenAt: String?
    // When the player last tapped "Ask for a life" (null = not asking). Optional
    // + decode-resilient like the stats above.
    var needsLivesAt: String?
    /// When this player's last life request closed (filled, expired or
    /// cancelled) — the wait before the next one counts from here.
    var livesRequestClosedAt: String? = nil
    /// The player's accent color ("#RRGGBB") and equipped ball id, as stored
    /// by docs/social-schema-v5.sql section 11.  Absent before that is
    /// applied, or for a player who has not opened the app since.
    var accentHex: String? = nil
    var ballSkinID: String? = nil

    /// This player's accent color, if they have one stored.
    var accentColor: Color? { accentHex.flatMap { Color(hexRGB: $0) } }
    /// This player's equipped ball, if stored and known to this build.
    var ballSkin: BallSkin? { ballSkinID.flatMap { BallSkin(rawValue: $0) } }

    /// Memberwise init with defaults — lets local code build a profile from
    /// GameState values for the profile "Player Ranks" readout.  (Codable's
    /// `init(from:)` is synthesized separately, so decoding is unaffected.)
    init(id: UUID, displayName: String = "", climbLevel: Int = 1,
         highestUnlocked: Int = 1, totalStars: Int = 0, lives: Int = 0,
         coinsCollected: Int? = nil, pinballBest: Int? = nil,
         zenSeconds: Int? = nil, goldrushBest: Int? = nil,
         snakeBest: Int? = nil, sumoBest: Int? = nil, paintballBest: Int? = nil,
         marblecupBest: Int? = nil, kothBest: Int? = nil,
         snakeWins: Int? = nil, sumoWins: Int? = nil, paintballWins: Int? = nil,
         marblecupWins: Int? = nil, kothWins: Int? = nil, goldrushWins: Int? = nil,
         rollupBest: Int? = nil, rollupBestSeconds: Int? = nil,
         discoballBest: Int? = nil, discoballBestAvgMs: Int? = nil,
         createdAt: String? = nil, updatedAt: String? = nil,
         lastSeenAt: String? = nil, needsLivesAt: String? = nil) {
        self.id = id; self.rawDisplayName = displayName; self.climbLevel = climbLevel
        self.highestUnlocked = highestUnlocked; self.totalStars = totalStars
        self.lives = lives; self.coinsCollected = coinsCollected
        self.pinballBest = pinballBest; self.zenSeconds = zenSeconds
        self.goldrushBest = goldrushBest; self.snakeBest = snakeBest
        self.sumoBest = sumoBest; self.paintballBest = paintballBest
        self.marblecupBest = marblecupBest; self.kothBest = kothBest
        self.snakeWins = snakeWins; self.sumoWins = sumoWins
        self.paintballWins = paintballWins; self.marblecupWins = marblecupWins
        self.kothWins = kothWins; self.goldrushWins = goldrushWins
        self.rollupBest = rollupBest; self.rollupBestSeconds = rollupBestSeconds
        self.discoballBest = discoballBest; self.discoballBestAvgMs = discoballBestAvgMs
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt; self.needsLivesAt = needsLivesAt
    }

    /// True when the player is currently asking clan-mates for lives.
    /// A request older than the limit (24 hours by default) has expired and
    /// no longer counts, even before the server has cleared it.
    var isAskingForLives: Bool {
        guard let at = needsLivesAt, !at.isEmpty else { return false }
        guard let opened = SeasonCalendar.parseTimestamp(at) else { return true }
        return Date().timeIntervalSince(opened) < Double(SocialSettings.current.requestHours) * 3600
    }

    /// Seconds until this player may open another life request (0 = now).
    func askWaitRemaining(now: Date = Date()) -> TimeInterval {
        var closedAt = livesRequestClosedAt.flatMap { SeasonCalendar.parseTimestamp($0) }
        // A request that ran out of time closed at that moment — the server
        // counts the wait from there even before it has cleared the request.
        if let at = needsLivesAt, !at.isEmpty, let opened = SeasonCalendar.parseTimestamp(at) {
            let expiry = opened.addingTimeInterval(Double(SocialSettings.current.requestHours) * 3600)
            if expiry <= now { closedAt = max(closedAt ?? expiry, expiry) }
        }
        guard let closed = closedAt else { return 0 }
        let ready = closed.addingTimeInterval(Double(SocialSettings.current.cooldownHours) * 3600)
        return max(0, ready.timeIntervalSince(now))
    }

    /// This player's best score in a competitive mode, keyed by GameMode id.
    func competitiveBest(_ modeID: String) -> Int {
        switch modeID {
        case "snake":     return snakeBest     ?? 0
        case "sumo":      return sumoBest      ?? 0
        case "paintball": return paintballBest ?? 0
        case "marblecup": return marblecupBest ?? 0
        case "koth":      return kothBest      ?? 0
        case "goldrush":  return goldrushBest  ?? 0
        default:          return 0
        }
    }

    /// This player's lifetime wins in a competitive mode, keyed by GameMode id.
    func competitiveWins(_ modeID: String) -> Int {
        switch modeID {
        case "snake":     return snakeWins     ?? 0
        case "sumo":      return sumoWins      ?? 0
        case "paintball": return paintballWins ?? 0
        case "marblecup": return marblecupWins ?? 0
        case "koth":      return kothWins      ?? 0
        case "goldrush":  return goldrushWins  ?? 0
        default:          return 0
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case rawDisplayName  = "display_name"
        case climbLevel       = "climb_level"
        case highestUnlocked  = "highest_unlocked"
        case totalStars       = "total_stars"
        case lives
        case coinsCollected   = "coins_collected"
        case pinballBest      = "pinball_best"
        case zenSeconds       = "zen_seconds"
        case goldrushBest     = "goldrush_best"
        case snakeBest        = "snake_best"
        case sumoBest         = "sumo_best"
        case paintballBest    = "paintball_best"
        case marblecupBest    = "marblecup_best"
        case kothBest         = "koth_best"
        case snakeWins        = "snake_wins"
        case sumoWins         = "sumo_wins"
        case paintballWins    = "paintball_wins"
        case marblecupWins    = "marblecup_wins"
        case kothWins         = "koth_wins"
        case goldrushWins     = "goldrush_wins"
        case rollupBest       = "rollup_best"
        case rollupBestSeconds = "rollup_best_seconds"
        case discoballBest      = "discoball_best"
        case discoballBestAvgMs = "discoball_best_avg_ms"
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
        case lastSeenAt       = "last_seen_at"
        case needsLivesAt     = "needs_lives_at"
        case livesRequestClosedAt = "lives_request_closed_at"
        case accentHex        = "accent_hex"
        case ballSkinID       = "ball_skin"
    }
}

// ===========================================================================
// LeaderboardBoard — one ranked list per Roll Along game/mode.
//
// The single source of truth for board identity, ranking order, and the
// "has this player played it?" test.  Shared by LeaderboardView (the board
// picker + per-row columns) and the profile "Player Ranks" section, so the two
// can never drift apart.  Pure data (Foundation only); the icon/colour mapping
// lives in the view layer.
// ===========================================================================
/// Groups the leaderboard boards for the game-filter picker.  Ordered: the
/// Adventure climb, the solo games, then the competitive games.
enum BoardCategory: Int, CaseIterable {
    case adventure, solo, competitive
    var title: String {
        switch self {
        case .adventure:   return "Adventure"
        case .solo:        return "Solo"
        case .competitive: return "Competitive"
        }
    }
}

enum LeaderboardBoard: String, CaseIterable, Identifiable {
    case rollAlong, zenGarden, rollUp, discoBall
    case snacky, sumo, paintBall, coinPit, marbleCup, kingOfHill
    var id: String { rawValue }

    /// Which category this board belongs to (drives the filter's grouping).
    var category: BoardCategory {
        switch self {
        case .rollAlong:                    return .adventure
        case .zenGarden, .rollUp, .discoBall: return .solo
        default:                            return .competitive   // the six competitive boards
        }
    }

    /// Player-facing board name.
    var title: String {
        switch self {
        case .rollAlong:  return "Roll Along"
        case .zenGarden:  return "Zen Garden"
        case .rollUp:     return "Roll Up"
        case .discoBall:  return "Disco Ball"
        case .snacky:     return "Snacky"
        case .sumo:       return "Sumo Survival"
        case .paintBall:  return "Paint Ball"
        case .coinPit:    return "Smash and Grab"   // board id stays `coinPit`; backs the `goldrush` mode
        case .marbleCup:  return "Marble Cup"
        case .kingOfHill: return "King of the Hill"
        }
    }

    /// The competitive GameMode id backing this board, or nil for the climb and
    /// the solo (Zen / Roll Up) boards.
    var competitiveModeID: String? {
        switch self {
        case .snacky:     return "snake"
        case .sumo:       return "sumo"
        case .paintBall:  return "paintball"
        case .coinPit:    return "goldrush"
        case .marbleCup:  return "marblecup"
        case .kingOfHill: return "koth"
        default:          return nil
        }
    }

    /// The game id in `minigame_scores` for a board kept PER DIFFICULTY (three
    /// tabs: Easy / Normal / Hard), or nil for a board with no difficulty
    /// levels (Adventure, Zen Garden, Roll Up).  The six competitive games and
    /// Disco Ball.  A run counts only on its own difficulty's board.
    var difficultyGameID: String? {
        if let mode = competitiveModeID { return mode }
        return self == .discoBall ? "disco" : nil
    }

    /// True for the board that also has a fourth "Solo" tab: Snacky's Solo
    /// mode (minigame_scores game "snake", difficulty "solo"; ranked by most
    /// orbs eaten).
    var hasSoloTab: Bool { self == .snacky }

    /// The tab label for a difficulty ("easy" / "normal" / "hard" / "solo") on this
    /// board — the game's own names: Disco Ball's hardest level is "Hardcore".
    func difficultyLabel(_ key: String) -> String {
        switch key {
        case "easy":   return "Easy"
        case "normal": return "Normal"
        case "hard":   return self == .discoBall ? "Hardcore" : "Hard"
        case "solo":   return "Solo"
        default:       return key.capitalized
        }
    }

    /// PostgREST order clause on `players` (boards without difficulty).  The
    /// per-difficulty boards are ordered by `fetchMinigameDifficultyLeaderboard`;
    /// their entries here are the old all-difficulty orders, no longer shown.
    var order: String {
        switch self {
        case .rollAlong:  return "climb_level.desc,total_stars.desc"
        case .zenGarden:  return "zen_seconds.desc"
        // Default (Height) order; LeaderboardView swaps in the Time order when
        // the Roll Up board's sort toggle is set to Time.
        case .rollUp:     return "rollup_best.desc,rollup_best_seconds.desc"
        // Per difficulty only (minigame_scores); never read from `players`.
        case .discoBall:  return "climb_level.desc"
        case .snacky:     return "snake_wins.desc,snake_best.desc"
        case .sumo:       return "sumo_wins.desc,sumo_best.desc"
        case .paintBall:  return "paintball_wins.desc,paintball_best.desc"
        case .coinPit:    return "goldrush_wins.desc,goldrush_best.desc"
        case .marbleCup:  return "marblecup_wins.desc,marblecup_best.desc"
        case .kingOfHill: return "koth_wins.desc,koth_best.desc"
        }
    }

    /// True once the player has any record on this board (hides players who
    /// haven't played the game yet, and drives "Unranked" in the profile).
    func hasPlayed(_ p: PlayerProfile) -> Bool {
        if let mode = competitiveModeID {
            return p.competitiveWins(mode) > 0 || p.competitiveBest(mode) > 0
        }
        switch self {
        case .rollAlong: return true                       // everyone has a climb level
        case .zenGarden: return (p.zenSeconds ?? 0) > 0
        case .rollUp:    return (p.rollupBest ?? 0) > 0
        case .discoBall: return (p.discoballBest ?? 0) > 0
        default:         return true
        }
    }

    /// A compact one-line summary of the player's stats on this board — every
    /// stat the board tracks (the profile shows them all, regardless of rank).
    func statText(_ p: PlayerProfile) -> String {
        if let mode = competitiveModeID {
            let w = p.competitiveWins(mode)
            return "\(w) win\(w == 1 ? "" : "s") · best \(Self.bestText(mode, p.competitiveBest(mode)))"
        }
        switch self {
        case .rollAlong: return "Lv \(p.climbLevel) · \(p.totalStars)★ · \(p.coinsCollected ?? 0) coins"
        case .zenGarden: return Self.zenText(p.zenSeconds ?? 0)
        case .rollUp:    return "\(p.rollupBest ?? 0) m · \(Self.rollUpTime(p.rollupBestSeconds ?? 0))"
        case .discoBall:
            let n = p.discoballBest ?? 0
            return "\(n) crossing\(n == 1 ? "" : "s") · \(Self.crossingTime(p.discoballBestAvgMs ?? 0)) each"
        default:         return ""
        }
    }

    // MARK: - Shared stat formatters (reused by LeaderboardView's row cells)

    /// Mode-specific formatting for a competitive "Best" value.
    static func bestText(_ modeID: String, _ v: Int) -> String {
        switch modeID {
        case "koth":      return holdText(v)   // hold seconds → "1m 20s"
        case "paintball": return "\(v)%"       // floor coverage
        default:          return v.formatted()
        }
    }
    /// Seconds → "1h 23m" / "45m" / "30s" (Zen — long durations).
    static func zenText(_ s: Int) -> String {
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        if s >= 60   { return "\(s / 60)m" }
        return "\(s)s"
    }
    /// Seconds → "1m 20s" / "45s" (KotH hold time — keeps the seconds).
    static func holdText(_ s: Int) -> String {
        s >= 60 ? "\(s / 60)m \(s % 60)s" : "\(s)s"
    }
    /// Milliseconds → "4.3 s" (Disco Ball average time per crossing);
    /// "—" when unknown.
    static func crossingTime(_ ms: Int) -> String {
        guard ms > 0 else { return "—" }
        return String(format: "%.1f s", Double(ms) / 1000)
    }
    /// Seconds → "m:ss" clock (Roll Up run duration), e.g. 125 → "2:05".
    static func rollUpTime(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A pending or claimed "send a life" gift.
struct LifeGift: Codable, Identifiable {
    let id: UUID
    let senderId: UUID
    let recipientId: UUID
    let amount: Int
    var claimedAt: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case senderId     = "sender_id"
        case recipientId  = "recipient_id"
        case amount
        case claimedAt    = "claimed_at"
        case createdAt    = "created_at"
    }
}

/// A friend-graph edge (independent of clans).  `status` ∈ pending|accepted|blocked.
struct Friendship: Codable, Identifiable {
    let id: UUID
    let requesterId: UUID
    let addresseeId: UUID
    var status: String
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case status
        case createdAt   = "created_at"
    }

    /// The participant who isn't `me`.
    func otherId(than me: UUID) -> UUID {
        requesterId == me ? addresseeId : requesterId
    }
    /// An unanswered request sent TO me (I can accept/decline).
    func isIncomingPending(for me: UUID) -> Bool {
        status == "pending" && addresseeId == me
    }
    /// My own request still awaiting their answer.
    func isOutgoingPending(for me: UUID) -> Bool {
        status == "pending" && requesterId == me
    }
}

/// A collaborative group.  `tag` is the short [TAG] shown beside member names.
struct Clan: Codable, Identifiable, Hashable {
    let id: UUID
    // Stored values exactly as the server returned them.  Never shown
    // directly — the accessors below only pass preset-format values (see
    // `PresetNames`), so a legacy or tampered row renders as a plain "Clan".
    private var rawName: String
    private var rawTag: String
    private var rawDescription: String
    let ownerId: UUID
    var createdAt: String?
    var updatedAt: String?
    /// The clan's preset icon and color (database step 13); nil before that
    /// step is run.
    private var rawIcon: String?
    private var rawColor: String?

    /// The clan's icon (an SF Symbol from `ClanLook.icons`), default shield.
    var icon: String { rawIcon.flatMap { ClanLook.icons.contains($0) ? $0 : nil } ?? ClanLook.defaultIcon }
    /// The clan's color key (from `ClanLook.colorKeys`), default blue.
    var colorKey: String { rawColor.flatMap { ClanLook.colorKeys.contains($0) ? $0 : nil } ?? ClanLook.defaultColor }

    /// The clan name when it is preset-format, else "".
    var name: String { PresetNames.parseClanName(rawName) != nil ? rawName : "" }
    /// The tag when it is the one derived from a preset-format name, else "".
    var tag: String {
        guard let c = PresetNames.parseClanName(rawName), PresetNames.clanTag(c) == rawTag else { return "" }
        return rawTag
    }
    /// The description when it is one of the preset options, else "".
    var description: String { PresetNames.isValidClanDescription(rawDescription) ? rawDescription : "" }

    enum CodingKeys: String, CodingKey {
        case id
        case rawName        = "name"
        case rawTag         = "tag"
        case rawDescription = "description"
        case ownerId   = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rawIcon   = "icon"
        case rawColor  = "color"
    }
}

/// A clan's look: one icon from a preset set of symbols and one color from a
/// preset palette, chosen by the owner (no typed text).  The lists must
/// match database step 13 (docs/social/clan-look.sql) — change both.
enum ClanLook {
    static let defaultIcon  = "shield.fill"
    static let defaultColor = "blue"

    /// SF Symbols, all available on iOS 17 and later.
    static let icons: [String] = [
        "shield.fill", "flame.fill", "bolt.fill", "star.fill",
        "crown.fill", "leaf.fill", "moon.stars.fill", "sun.max.fill",
        "snowflake", "drop.fill", "mountain.2.fill", "tree.fill",
        "pawprint.fill", "hare.fill", "tortoise.fill", "bird.fill",
        "fish.fill", "heart.fill", "diamond.fill", "trophy.fill",
        "flag.fill", "sparkles", "atom", "puzzlepiece.fill",
    ]

    /// Color keys and their colors, readable on the dark screens.
    struct Swatch {
        let key: String
        let name: String
        let red: Double, green: Double, blue: Double
        var color: Color { Color(red: red, green: green, blue: blue) }
    }
    static let palette: [Swatch] = [
        Swatch(key: "red",    name: "Red",    red: 0.94, green: 0.33, blue: 0.33),
        Swatch(key: "orange", name: "Orange", red: 0.98, green: 0.56, blue: 0.24),
        Swatch(key: "gold",   name: "Gold",   red: 1.00, green: 0.81, blue: 0.30),
        Swatch(key: "lime",   name: "Lime",   red: 0.62, green: 0.86, blue: 0.30),
        Swatch(key: "green",  name: "Green",  red: 0.30, green: 0.75, blue: 0.42),
        Swatch(key: "teal",   name: "Teal",   red: 0.22, green: 0.78, blue: 0.72),
        Swatch(key: "sky",    name: "Sky",    red: 0.40, green: 0.78, blue: 1.00),
        Swatch(key: "blue",   name: "Blue",   red: 0.33, green: 0.55, blue: 1.00),
        Swatch(key: "indigo", name: "Indigo", red: 0.52, green: 0.48, blue: 1.00),
        Swatch(key: "purple", name: "Purple", red: 0.72, green: 0.45, blue: 0.98),
        Swatch(key: "pink",   name: "Pink",   red: 0.98, green: 0.45, blue: 0.72),
        Swatch(key: "silver", name: "Silver", red: 0.72, green: 0.75, blue: 0.80),
    ]
    static let colorKeys: [String] = palette.map { $0.key }

    static func color(_ key: String) -> Color {
        (palette.first { $0.key == key } ?? palette.first { $0.key == defaultColor } ?? palette[0]).color
    }
}

/// The social numbers that live on the server (`ra_config` in
/// docs/social-schema-v5.sql) so they can change without an app update.
/// The values below are only the defaults used until the server answers.
struct SocialSettings {
    var memberCap = 12
    var requestSize = 6
    var requestHours = 24
    var cooldownHours = 6
    var giftsPerFriendPerDay = 1
    var seasonMinClanScore = 25
    var seasonMinMemberStars = 10
    /// First season (yyyymm) that awards coins; earlier ones are a rehearsal.
    var seasonPrizesFrom = 202701
    /// True once the server has answered — i.e. docs/social-schema-v5.sql is
    /// in place, including the rule that hands a clan on when its owner leaves.
    var loadedFromServer = false

    init() {}
    init(_ v: [String: Int]) {
        memberCap            = v["clan_member_cap"] ?? memberCap
        requestSize          = v["life_request_size"] ?? requestSize
        requestHours         = v["life_request_hours"] ?? requestHours
        cooldownHours        = v["life_request_cooldown_hours"] ?? cooldownHours
        giftsPerFriendPerDay = v["gift_per_friend_per_day"] ?? giftsPerFriendPerDay
        seasonMinClanScore   = v["season_min_clan_score"] ?? seasonMinClanScore
        seasonMinMemberStars = v["season_min_member_stars"] ?? seasonMinMemberStars
        seasonPrizesFrom     = v["season_prizes_from"] ?? seasonPrizesFrom
    }

    /// Read on the main thread by the views; replaced by
    /// `SocialClient.refreshSocialSettings()`.
    static var current = SocialSettings()
}

/// Friend codes: eight characters from an alphabet that is easy to read
/// aloud and to type, shown as "AF3K-7MXY".  The database assigns them
/// (docs/social-schema-v5.sql, section 10) — keep the alphabet the same.
enum FriendCode {
    /// A F H J K M R W X Y 3 4 6 7 9.  Left out: letters that rhyme when
    /// spoken (B C D E G P T V Z, and N next to M), letters that look like
    /// digits (I L O S), and digits that look like letters or words (0 1 2 5 8).
    static let alphabet = Set("AFHJKMRWXY34679")
    static let length = 8

    /// The code in its stored form (eight characters, upper case), or nil if
    /// `input` cannot be one.  Spaces and dashes are ignored, lower case is
    /// accepted, and the common mix-ups are forgiven: O and 0 have no meaning,
    /// so they are rejected rather than guessed.
    static func normalize(_ input: String) -> String? {
        let cleaned = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == length, cleaned.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return cleaned
    }

    /// "AF3K7MXY" → "AF3K-7MXY".
    static func display(_ code: String) -> String {
        guard code.count == length else { return code }
        return String(code.prefix(4)) + "-" + String(code.suffix(4))
    }

    /// Keeps only characters that can be part of a code (for the text field),
    /// upper-cased, at most eight.
    static func filterTyping(_ input: String) -> String {
        String(input.uppercased().filter { alphabet.contains($0) }.prefix(length))
    }
}

/// The game's social clock: Eastern time (America/New_York).  Seasons of the
/// monthly clan battle (calendar months, named by their first day
/// "2026-12-01" exactly as the database names them), the daily star cap,
/// the cosmetic calendar and the one-gift-per-friend-per-day limit all use it.
enum SeasonCalendar {
    /// The moment today began in Eastern time (midnight America/New_York), as
    /// a full timestamp with its offset ("2026-11-17T00:00:00-05:00"), ready
    /// to compare with server timestamps.
    static func dayStartTimestamp(_ date: Date = Date()) -> String {
        let start = eastern.startOfDay(for: date)
        let f = ISO8601DateFormatter()
        f.timeZone = eastern.timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: start)
    }

    /// The clock the monthly clan battle runs on: Eastern time, by its
    /// NAMED zone so daylight saving is handled.  The database uses the same
    /// name (`ra_season_now()` in docs/social-schema-v5.sql) — change both.
    static let seasonTimeZoneName = "America/New_York"
    private static var eastern: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: seasonTimeZoneName) ?? .gmt
        return cal
    }

    /// The season a date falls in: the first day of its month, Eastern time.
    static func seasonKey(_ date: Date = Date()) -> String {
        let c = eastern.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d-01", c.year ?? 0, c.month ?? 0)
    }

    /// The season before the one a date falls in.
    static func previousSeasonKey(_ date: Date = Date()) -> String {
        let cal = eastern
        // From the first of this month, so "one month back" can never skip
        // a short month.
        let monthStart = cal.dateInterval(of: .month, for: date)?.start ?? date
        let earlier = cal.date(byAdding: .month, value: -1, to: monthStart) ?? date
        return seasonKey(earlier)
    }

    /// Days left in the current season, counting today (1 on the last day).
    /// The season ends at midnight Eastern on the 1st of next month.
    static func daysRemaining(_ date: Date = Date()) -> Int {
        let cal = eastern
        guard let month = cal.dateInterval(of: .month, for: date) else { return 0 }
        let today = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: today, to: month.end).day ?? 1
        return max(1, days)
    }

    /// "December" for "2026-12-01" (and for today when no key is given).
    static func monthName(_ key: String? = nil) -> String {
        var month = eastern.component(.month, from: Date())
        if let key {
            let parts = key.split(separator: "-")
            if parts.count >= 2, let m = Int(parts[1]), (1...12).contains(m) { month = m }
        }
        let names = ["January", "February", "March", "April", "May", "June", "July",
                     "August", "September", "October", "November", "December"]
        return names[month - 1]
    }

    /// True when a season key (yyyy-MM-01) awards coins and counts wins.
    static func awardsPrizes(_ key: String) -> Bool {
        let parts = key.split(separator: "-")
        guard parts.count >= 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return true }
        return y * 100 + m >= SocialSettings.current.seasonPrizesFrom
    }

    /// Parse a server timestamp ("2026-11-15T12:00:00.123456+00:00").
    static func parseTimestamp(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// "1st", "2nd", "3rd", "4th" …
    static func ordinal(_ n: Int) -> String {
        let tens = (n / 10) % 10, ones = n % 10
        if tens == 1 { return "\(n)th" }
        switch ones {
        case 1:  return "\(n)st"
        case 2:  return "\(n)nd"
        case 3:  return "\(n)rd"
        default: return "\(n)th"
        }
    }

    /// "Diamond" for "diamond"; "" for anything unexpected.
    static func tierName(_ raw: String?) -> String {
        switch raw {
        case "diamond": return "Diamond"
        case "gold":    return "Gold"
        case "silver":  return "Silver"
        case "bronze":  return "Bronze"
        default:        return ""
        }
    }
}

extension Clan {
    /// Most members a clan can hold.  Comes from the server
    /// (`clan_member_cap`), 12 until the server answers.
    static var memberCap: Int { SocialSettings.current.memberCap }
}

/// How the Rankings tab is ordered.
enum ClanRankSort: Hashable {
    case season, levels, stars

    var orderClause: String {
        switch self {
        case .season: return "season_score.desc,total_levels.desc"
        case .levels: return "total_levels.desc,total_stars.desc"
        case .stars:  return "total_stars.desc,total_levels.desc"
        }
    }
}

/// One row of the clan rankings: the clan plus its totals and standing,
/// computed by the server (`clan_rankings` view, docs/social-schema-v5.sql).
struct ClanRanking: Decodable, Identifiable {
    let clan: Clan
    let memberCount: Int
    let totalLevels: Int
    let totalStars: Int
    /// New Adventure stars earned for this clan this month.
    let seasonScore: Int
    /// Months this clan finished first.
    let seasonWins: Int
    let lastSeason: String?
    let lastSeasonRank: Int?
    let lastSeasonClans: Int?
    let lastSeasonTier: String?

    var id: UUID { clan.id }
    var isFull: Bool { memberCount >= Clan.memberCap }

    /// "Last month: 3rd of 40 · Gold" — nil unless the clan was ranked in
    /// the season that just ended.
    var lastMonthLine: String? {
        guard let lastSeason, lastSeason == SeasonCalendar.previousSeasonKey(),
              let rank = lastSeasonRank else { return nil }
        var line = "Last month: \(SeasonCalendar.ordinal(rank))"
        if let total = lastSeasonClans, total > 0 { line += " of \(total)" }
        let tier = SeasonCalendar.tierName(lastSeasonTier)
        if !tier.isEmpty { line += " · \(tier)" }
        return line
    }

    /// "2 wins" / "1 win" / nil.
    var winsLine: String? {
        seasonWins > 0 ? "\(seasonWins) win\(seasonWins == 1 ? "" : "s")" : nil
    }

    private enum Keys: String, CodingKey {
        case memberCount = "member_count"
        case totalLevels = "total_levels"
        case totalStars  = "total_stars"
        case seasonScore = "season_score"
        case seasonWins  = "season_wins"
        case lastSeason  = "last_season"
        case lastSeasonRank  = "last_season_rank"
        case lastSeasonClans = "last_season_clans"
        case lastSeasonTier  = "last_season_tier"
    }

    init(from decoder: Decoder) throws {
        clan = try Clan(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        totalLevels = try c.decodeIfPresent(Int.self, forKey: .totalLevels) ?? 0
        totalStars  = try c.decodeIfPresent(Int.self, forKey: .totalStars)  ?? 0
        seasonScore = try c.decodeIfPresent(Int.self, forKey: .seasonScore) ?? 0
        seasonWins  = try c.decodeIfPresent(Int.self, forKey: .seasonWins)  ?? 0
        lastSeason      = try c.decodeIfPresent(String.self, forKey: .lastSeason)
        lastSeasonRank  = try c.decodeIfPresent(Int.self, forKey: .lastSeasonRank)
        lastSeasonClans = try c.decodeIfPresent(Int.self, forKey: .lastSeasonClans)
        lastSeasonTier  = try c.decodeIfPresent(String.self, forKey: .lastSeasonTier)
    }
}

/// A coin prize from a finished season, waiting to be claimed.
struct SeasonPrize: Decodable, Identifiable {
    let season: String
    private let rawClanName: String
    let clanRank: Int
    let clansRanked: Int
    let tier: String
    let contribution: Int
    let coins: Int

    var id: String { season }
    /// The clan's name when it is preset-format, else a neutral phrase.
    var clanName: String { PresetNames.parseClanName(rawClanName) != nil ? rawClanName : "Your clan" }

    enum CodingKeys: String, CodingKey {
        case season
        case rawClanName  = "clan_name"
        case clanRank     = "clan_rank"
        case clansRanked  = "clans_ranked"
        case tier, contribution, coins
    }
}

/// One player's membership in a clan.  Identified by `playerId` (unique within
/// a roster) so it can drive a `ForEach` directly.
struct ClanMember: Codable, Identifiable {
    let clanId: UUID
    let playerId: UUID
    var role: String
    var joinedAt: String?

    var id: UUID { playerId }
    var isOwner: Bool { role == "owner" }

    enum CodingKeys: String, CodingKey {
        case clanId   = "clan_id"
        case playerId = "player_id"
        case role
        case joinedAt = "joined_at"
    }
}

/// A clan activity-feed entry (schema v2).  `targetId` is the other player for
/// pair events (sent_life / thanked).
struct ClanEvent: Codable, Identifiable {
    let id: UUID
    let clanId: UUID
    let actorId: UUID
    let targetId: UUID?
    let kind: String
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case clanId    = "clan_id"
        case actorId   = "actor_id"
        case targetId  = "target_id"
        case kind
        case createdAt = "created_at"
    }
}

// ---------------------------------------------------------------------------
// Private write payloads — snake_case property names map straight to columns.
// ---------------------------------------------------------------------------
private struct ProfileUpsert: Encodable {
    let id: UUID
    let display_name: String
    let climb_level: Int
    let highest_unlocked: Int
    let total_stars: Int
    let coins_collected: Int
    let lives: Int
}

private struct ProgressPatch: Encodable {
    let climb_level: Int
    let highest_unlocked: Int
    let total_stars: Int
    let coins_collected: Int
}

private struct MinigamePatch: Encodable {
    let pinball_best: Int
    let zen_seconds: Int
    let goldrush_best: Int
    // Competitive-mode bests + lifetime win tallies.
    let snake_best: Int
    let sumo_best: Int
    let paintball_best: Int
    let marblecup_best: Int
    let koth_best: Int
    let snake_wins: Int
    let sumo_wins: Int
    let paintball_wins: Int
    let marblecup_wins: Int
    let koth_wins: Int
    let goldrush_wins: Int
    let rollup_best: Int
    let rollup_best_seconds: Int
}

private struct GiftInsert: Encodable {
    let sender_id: UUID
    let recipient_id: UUID
    let amount: Int
}

private struct ClaimPatch: Encodable {
    let claimed_at: String
}

private struct FriendshipInsert: Encodable {
    let requester_id: UUID
    let addressee_id: UUID
    let status: String
}

private struct FriendStatusPatch: Encodable {
    let status: String
}

private struct ClanInsert: Encodable {
    let name: String
    let tag: String
    let description: String
    let owner_id: UUID
}

private struct ClanMemberInsert: Encodable {
    let clan_id: UUID
    let player_id: UUID
    let role: String
}

/// Owner-only clan edits (renameClan today; future personalization columns —
/// description, tag, colors — become optional fields here).
private struct ClanUpdatePatch: Encodable {
    let name: String
    let tag: String
}

private struct ClanEventInsert: Encodable {
    let clan_id: UUID
    let actor_id: UUID
    let target_id: UUID?   // nil → omitted → column null (fine for solo events)
    let kind: String
}

/// PATCH payload that forces `needs_lives_at` to a value OR explicit null (so
/// clearing actually nulls the column instead of omitting the key).
private struct NeedsLivesPatch: Encodable {
    let needs_lives_at: String?
    enum CodingKeys: String, CodingKey { case needs_lives_at }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let v = needs_lives_at { try c.encode(v, forKey: .needs_lives_at) }
        else { try c.encodeNil(forKey: .needs_lives_at) }
    }
}

// ===========================================================================
// Send Feedback (Settings → Send Feedback)
//
// A player picks Bug, Idea or Complaint and writes up to 1,000 characters.
// The app quietly adds the app version, iOS version, phone model, the screen
// they came from and — only when signed in — their player id (taken by the
// SERVER from the sign-in token, never from the request body). For rate
// limiting it also sends a one-way SHA-256 hash of the random install ID, so
// feedback cannot be matched to analytics events by that ID.
//
// Stored through the `submit_feedback` function (docs/feedback/feedback-schema.sql).
// The `feedback` table is write-only for players: nobody can read it from the
// app, including their own messages. Only the dashboard can.
//
// Offline or on a server/network error, the message stays in a small queue in
// UserDefaults and is retried at launch and whenever the app comes back.
// Limits: 5 per phone per rolling 24 hours here, and the same on the server.
// Never sends during unit or UI tests (RuntimeEnvironment).
// ===========================================================================

enum FeedbackKind: String, Codable, CaseIterable, Identifiable {
    case bug, idea, complaint
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bug:       return "Bug"
        case .idea:      return "Idea"
        case .complaint: return "Complaint"
        }
    }
}

/// One queued message, exactly as it will be sent (minus the player id,
/// which the server reads from the sign-in token).
struct FeedbackItem: Codable, Equatable {
    var clientID: UUID          // makes a retried send land only once
    var kind: FeedbackKind
    var message: String
    var appVersion: String
    var iosVersion: String
    var deviceModel: String
    var source: String
    var createdAt: Date
}

/// Transport, swappable in tests.
protocol FeedbackSending {
    /// Throws `FeedbackSendError.permanent` when the server refused the item
    /// for good (bad input, rate limited): it is dropped, not retried.
    func send(_ item: FeedbackItem, installHash: String) async throws
}

enum FeedbackSendError: Error {
    case permanent(status: Int, body: String)
    case retryLater(String)
}

final class FeedbackOutbox: @unchecked Sendable {
    static let shared = FeedbackOutbox()

    static let maxLength       = 1_000
    static let maxPerDay       = 5
    static let maxQueued       = 10
    static let window: TimeInterval = 24 * 60 * 60

    private static let queueKey = "ra_feedback_queue_v1"
    private static let sentKey  = "ra_feedback_sent_times_v1"

    private let defaults: UserDefaults
    private let sender: FeedbackSending
    private let installHash: String
    private let liveAllowed: Bool
    private let now: () -> Date
    /// Try to send right after `submit` (off in unit tests, which flush by hand).
    private let autoFlush: Bool
    private let lock = NSLock()
    private var isFlushing = false

    init(defaults: UserDefaults = .standard,
         sender: FeedbackSending = SupabaseFeedbackSender(),
         installID: UUID = AnalyticsClient.shared.installID,
         liveAllowed: Bool = !RuntimeEnvironment.isRunningTests,
         now: @escaping () -> Date = Date.init,
         autoFlush: Bool = true) {
        self.defaults = defaults
        self.autoFlush = autoFlush
        self.sender = sender
        self.installHash = Self.hash(installID)
        self.liveAllowed = liveAllowed
        self.now = now
    }

    /// One-way hash of the install ID ("feedback:" salt), 64 hex characters.
    static func hash(_ id: UUID) -> String {
        let digest = SHA256.hash(data: Data("feedback:\(id.uuidString)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Limits

    /// Messages accepted on this phone in the last 24 hours (sent or queued).
    var usedToday: Int {
        lock.lock(); defer { lock.unlock() }
        return recentTimesLocked().count
    }

    var canSubmit: Bool { usedToday < Self.maxPerDay }

    var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return loadQueueLocked().count
    }

    enum SubmitResult: Equatable { case queued, limitReached, empty }

    /// Validates, counts against the daily limit, queues, then tries to send.
    @discardableResult
    func submit(kind: FeedbackKind, message: String, source: String) -> SubmitResult {
        var text = String(message.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.maxLength))
        // The server counts code points (char_length), not Characters: one
        // emoji (flag, family) is several. Trim so it is never refused.
        while text.unicodeScalars.count > Self.maxLength { text.removeLast() }
        guard !text.isEmpty else { return .empty }

        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        let item = FeedbackItem(clientID: UUID(),
                                kind: kind,
                                message: text,
                                appVersion: "\(version) (\(build))",
                                iosVersion: { let v = ProcessInfo.processInfo.operatingSystemVersion; return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" }(),
                                deviceModel: AnalyticsClient.deviceIdentifier(),
                                source: String(source.prefix(60)),
                                createdAt: now())

        lock.lock()
        var times = recentTimesLocked()
        guard times.count < Self.maxPerDay else {
            lock.unlock()
            return .limitReached
        }
        var queue = loadQueueLocked()
        queue.append(item)
        if queue.count > Self.maxQueued { queue.removeFirst(queue.count - Self.maxQueued) }
        saveQueueLocked(queue)
        times.append(now())
        defaults.set(times.map(\.timeIntervalSince1970), forKey: Self.sentKey)
        lock.unlock()

        if autoFlush { Task { await self.flush() } }
        return .queued
    }

    // MARK: Sending

    /// Sends everything queued, oldest first. Stops at the first network or
    /// server error and keeps the rest for next time. Safe to call often.
    func flush() async {
        guard liveAllowed else { return }
        guard let queue = beginFlush() else { return }
        defer { endFlush() }

        for item in queue {
            do {
                try await sender.send(item, installHash: installHash)
                remove(item.clientID)
            } catch FeedbackSendError.permanent(let status, let body) {
                #if DEBUG
                print("[Feedback] refused (\(status)), dropped: \(body)")
                #endif
                remove(item.clientID)
            } catch {
                #if DEBUG
                print("[Feedback] send failed, kept for later: \(error)")
                #endif
                return
            }
        }
    }

    /// Returns the queue to send, or nil when a flush is already running.
    private func beginFlush() -> [FeedbackItem]? {
        lock.lock(); defer { lock.unlock() }
        if isFlushing { return nil }
        isFlushing = true
        return loadQueueLocked()
    }

    private func endFlush() {
        lock.lock(); defer { lock.unlock() }
        isFlushing = false
    }

    private func remove(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        saveQueueLocked(loadQueueLocked().filter { $0.clientID != id })
    }

    // MARK: Storage (call with lock held)

    private func recentTimesLocked() -> [Date] {
        let raw = defaults.array(forKey: Self.sentKey) as? [Double] ?? []
        let cutoff = now().addingTimeInterval(-Self.window)
        return raw.map(Date.init(timeIntervalSince1970:)).filter { $0 > cutoff }
    }

    private func loadQueueLocked() -> [FeedbackItem] {
        guard let data = defaults.data(forKey: Self.queueKey),
              let items = try? JSONDecoder().decode([FeedbackItem].self, from: data)
        else { return [] }
        return items
    }

    private func saveQueueLocked(_ items: [FeedbackItem]) {
        if items.isEmpty { defaults.removeObject(forKey: Self.queueKey); return }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.queueKey)
        }
    }
}

/// Live transport: POST /rest/v1/rpc/submit_feedback. Signed-in players send
/// their sign-in token so the server can record their player id; everyone
/// else sends the public anon key.
struct SupabaseFeedbackSender: FeedbackSending {
    private static let projectURL = "https://mhwpcwauzvmtmuphtajs.supabase.co"
    /// Anon (public) JWT, the same one analytics uses. The function is the
    /// only way in; the table itself cannot be read or written directly.
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1od3Bjd2F1enZtdG11cGh0YWpzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwMDI1MzMsImV4cCI6MjA5NTU3ODUzM30." +
        "dKtYkbLF43vLYiCMaxhurBT8rTqAMxuKuJ2z5mkXKsM"

    private struct Body: Encodable {
        let p_client_id: String
        let p_kind: String
        let p_message: String
        let p_app_version: String
        let p_os_version: String
        let p_device_model: String
        let p_source: String
        let p_install_hash: String
    }

    func send(_ item: FeedbackItem, installHash: String) async throws {
        if RuntimeEnvironment.isRunningTests {
            throw FeedbackSendError.retryLater("live server disabled during tests")
        }
        guard let url = URL(string: "\(Self.projectURL)/rest/v1/rpc/submit_feedback") else {
            throw FeedbackSendError.permanent(status: 0, body: "bad URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        let token = try? SocialClient.shared.trophyAccessToken()
        req.setValue("Bearer \(token ?? Self.anonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(Body(
            p_client_id: item.clientID.uuidString,
            p_kind: item.kind.rawValue,
            p_message: item.message,
            p_app_version: item.appVersion,
            p_os_version: item.iosVersion,
            p_device_model: item.deviceModel,
            p_source: item.source,
            p_install_hash: installHash))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw FeedbackSendError.retryLater(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackSendError.retryLater("no HTTP response")
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        switch http.statusCode {
        case 200...299:
            return
        case 401 where token != nil:
            // Expired sign-in token: keep it and retry after the token
            // refreshes, rather than drop the message.
            throw FeedbackSendError.retryLater("sign-in token refused")
        case 400...499:
            throw FeedbackSendError.permanent(status: http.statusCode, body: body)
        default:
            throw FeedbackSendError.retryLater("HTTP \(http.statusCode)")
        }
    }
}
