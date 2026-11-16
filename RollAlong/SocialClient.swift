import Foundation

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
                                 display_name: PresetNames.isValidNickname(displayName)
                                     ? displayName : PresetNames.defaultNickname,
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
    func fetchProfile(id: UUID) async throws -> PlayerProfile? {
        let data = try await send(method: "GET", path: "players",
                                  query: "id=eq.\(id.uuidString)&limit=1")
        return try decode([PlayerProfile].self, from: data).first
    }

    // MARK: - Leaderboard

    /// Leaderboard rows, ordered by `order` (a PostgREST order clause).  The
    /// default is the climb board; minigame boards pass e.g. "zen_seconds.desc".
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

    /// Columns added by docs/social-schema-v5.sql (the weekly baseline).
    private static let v5PlayerColumns =
        ",week_start,week_start_level,week_start_stars,lives_request_closed_at"

    /// Read `players` rows, asking for the v5 columns too.  Until
    /// docs/social-schema-v5.sql has been run the server answers 400 for a
    /// column it does not know, so this falls back to the older query — the
    /// lists keep working, just without weekly pace or the exclusion filter.
    /// `rest` is the remainder of the query string, starting with "&".
    private func getPlayers(columns: String, rest: String,
                            hideExcluded: Bool = false) async throws -> [PlayerProfile] {
        let v5 = "select=\(columns)\(Self.v5PlayerColumns)"
               + (hideExcluded ? "&excluded=is.false" : "") + rest
        let data: Data
        do {
            data = try await send(method: "GET", path: "players", query: v5)
        } catch SocialError.http(let status, _) where status == 400 || status == 404 {
            data = try await send(method: "GET", path: "players", query: "select=\(columns)" + rest)
        }
        return try decode([PlayerProfile].self, from: data)
    }

    // MARK: - Per-difficulty minigame leaderboard (minigame_scores table)

    private struct MinigameScoreUpsert: Encodable {
        let player_id: String
        let game: String
        let difficulty: String
        let wins: Int
        let best: Int
    }

    /// Upsert this player's wins + best for one competitive game at one
    /// difficulty.  Best-effort; signed-in only (the caller wraps it in try?).
    func syncMinigameScore(game: String, difficulty: String,
                           wins: Int, best: Int) async throws {
        let me = try requireSession()
        let body = MinigameScoreUpsert(player_id: me.userId.uuidString, game: game,
                                       difficulty: difficulty, wins: wins, best: best)
        _ = try await send(method: "POST", path: "minigame_scores",
                           query: "on_conflict=player_id,game,difficulty",
                           bodyData: try encoder.encode(body),
                           prefer: "resolution=merge-duplicates,return=minimal")
    }

    private struct MinigameScoreRow: Decodable {
        let player_id: UUID
        let wins: Int
        let best: Int
        let players: Embedded?
        struct Embedded: Decodable {
            let display_name: String?
            let climb_level: Int?
            let total_stars: Int?
            let highest_unlocked: Int?
            let lives: Int?
        }
    }

    /// Per-(game, difficulty) leaderboard rows, ranked by wins then best.  Mapped
    /// onto `PlayerProfile` with the chosen game's wins/best fields holding the
    /// per-difficulty values, so the leaderboard renders them like any board.
    func fetchMinigameDifficultyLeaderboard(game: String, difficulty: String,
                                            limit: Int = 100) async throws -> [PlayerProfile] {
        let sel = "player_id,wins,best,players(display_name,climb_level,total_stars,highest_unlocked,lives)"
        let query = "select=\(sel)&game=eq.\(game)&difficulty=eq.\(difficulty)"
                  + "&order=wins.desc,best.desc&limit=\(limit)"
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
    /// to today (UTC) — "Send life" allows one per player per day.  Gifts that
    /// answered a clan request are not included.
    func fetchMyGiftsToday() async -> Set<UUID> {
        guard let me = currentUserId else { return [] }
        let today = SeasonCalendar.dayKey()
        let query = "select=recipient_id,request_at&sender_id=eq.\(me.uuidString)"
            + "&request_at=is.null&created_at=gte.\(today)&limit=500"
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
        let query = "select=\(Self.rankingColumns)&id=eq.\(id.uuidString)&limit=1"
        guard let data = try? await send(method: "GET", path: "clan_rankings", query: query),
              let rows = try? decode([ClanRanking].self, from: data) else { return nil }
        return rows.first
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
        let query = "select=\(Self.clanColumns)&id=eq.\(id.uuidString)&limit=1"
        let data = try await send(method: "GET", path: "clans", query: query)
        return try decode([Clan].self, from: data).first
    }

    /// Recent clans to browse when not searching.
    func fetchClans(limit: Int = 30) async throws -> [Clan] {
        _ = try requireSession()
        let query = "select=\(Self.clanColumns)&order=created_at.desc&limit=\(limit)"
        let data = try await send(method: "GET", path: "clans", query: query)
        return try decode([Clan].self, from: data)
    }

    /// Find clans whose name contains `term` (case-insensitive).  Mirrors
    /// `searchPlayers`: the term is fully percent-escaped so the `*` wildcards
    /// stay literal and a stray `&`/`=` can't corrupt the query string.
    func searchClans(matching term: String, limit: Int = 30) async throws -> [Clan] {
        _ = try requireSession()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? trimmed
        let query = "select=\(Self.clanColumns)"
            + "&name=ilike.*\(escaped)*"
            + "&order=name.asc&limit=\(limit)"
        let data = try await send(method: "GET", path: "clans", query: query)
        return try decode([Clan].self, from: data)
    }

    private static let rankingColumns =
        "id,name,tag,description,owner_id,created_at,updated_at,"
        + "member_count,total_levels,total_stars,week_levels,season_score,"
        + "season_wins,last_season,last_season_rank,last_season_clans,last_season_tier"

    /// Clans ranked by this season's score, total levels or total stars (the
    /// read-only `clan_rankings` view from docs/social-schema-v5.sql).  Throws
    /// until that file has been run.
    func fetchClanRankings(sort: ClanRankSort, limit: Int = 100) async throws -> [ClanRanking] {
        _ = try requireSession()
        let query = "select=\(Self.rankingColumns)&order=\(sort.orderClause)&limit=\(limit)"
        let data = try await send(method: "GET", path: "clan_rankings", query: query)
        return try decode([ClanRanking].self, from: data)
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

    private func send(method: String,
                      path: String,
                      query: String = "",
                      bodyData: Data? = nil,
                      prefer: String? = nil) async throws -> Data {
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
// is  <word><word><number>  ("SwiftComet42"); a clan name is
// <word> <plural word> <number>  ("Swift Comets 42"); the clan tag is derived
// from the name ("SC42"); the clan description is one of a fixed list (or
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

    /// First word of a nickname (117 words, each <= 5 letters).
    static let adjectives: [String] = [
        "Agile", "Alert", "Alpha", "Amber", "Aqua", "Avid", "Azure", "Blue",
        "Bold", "Brave", "Brisk", "Calm", "Chief", "Clear", "Cool", "Coral",
        "Cozy", "Crisp", "Cyan", "Daily", "Dandy", "Deft", "Dusty", "Eager",
        "Early", "Elite", "Epic", "Fair", "Fancy", "Fast", "Fiery", "Fine",
        "First", "Fleet", "Fresh", "Funny", "Giant", "Glad", "Gold", "Grand",
        "Great", "Green", "Handy", "Happy", "Hardy", "Hazel", "Icy", "Ideal",
        "Iron", "Ivory", "Jade", "Jazzy", "Jolly", "Jumbo", "Keen", "Kind",
        "Light", "Lilac", "Loyal", "Lucid", "Lucky", "Lunar", "Magic", "Major",
        "Mega", "Merry", "Mint", "Misty", "Neat", "Neon", "Nifty", "Noble",
        "Olive", "Onyx", "Opal", "Peppy", "Polar", "Prime", "Proud", "Quick",
        "Quiet", "Rapid", "Regal", "Rosy", "Royal", "Ruby", "Rusty", "Sage",
        "Sandy", "Shiny", "Sleek", "Smart", "Snowy", "Solar", "Solid", "Sonic",
        "Spry", "Sunny", "Super", "Swift", "Teal", "Tidy", "Topaz", "True",
        "Turbo", "Urban", "Vast", "Vivid", "Warm", "Wavy", "Wild", "Windy",
        "Wise", "Witty", "Zen", "Zesty", "Zippy",
    ]

    /// Second word of a nickname (129 words, each <= 5 letters).
    static let nouns: [String] = [
        "Acorn", "Aspen", "Atlas", "Bear", "Bison", "Blaze", "Bolt", "Brook",
        "Camel", "Cedar", "Cliff", "Cloud", "Cobra", "Comet", "Crane", "Creek",
        "Crow", "Cub", "Daisy", "Dawn", "Delta", "Dingo", "Dove", "Drake",
        "Drift", "Dune", "Eagle", "Ember", "Fern", "Finch", "Fjord", "Flame",
        "Flare", "Fox", "Frost", "Gale", "Gecko", "Gem", "Glade", "Glow",
        "Goose", "Grove", "Gull", "Hare", "Hawk", "Heath", "Heron", "Hippo",
        "Horse", "Ibis", "Jet", "Kite", "Koala", "Koi", "Lake", "Lark",
        "Leaf", "Lemur", "Llama", "Lotus", "Lynx", "Mango", "Maple", "Marsh",
        "Mesa", "Moon", "Moose", "Moth", "Mouse", "Newt", "Nova", "Oak",
        "Ocean", "Orb", "Orca", "Otter", "Owl", "Panda", "Peak", "Pearl",
        "Pilot", "Pine", "Pixel", "Plume", "Pony", "Prism", "Puma", "Quail",
        "Quest", "Quill", "Racer", "Raven", "Reef", "Rhino", "Ridge", "River",
        "Robin", "Rook", "Rover", "Sable", "Shark", "Sky", "Sloth", "Snail",
        "Spark", "Squid", "Stag", "Star", "Stone", "Stork", "Storm", "Sun",
        "Swan", "Tapir", "Tide", "Tiger", "Torch", "Trout", "Tulip", "Vale",
        "Viper", "Vole", "Wave", "Whale", "Wind", "Wolf", "Wren", "Yak",
        "Zebra",
    ]

    /// First word of a clan name (165 words: the nickname list plus longer ones).
    static let clanAdjectives: [String] = [
        "Agile", "Alert", "Alpha", "Amber", "Ancient", "Aqua",
        "Arctic", "Avid", "Azure", "Blazing", "Blue", "Bold",
        "Brave", "Brisk", "Bronze", "Calm", "Chief", "Clear",
        "Clever", "Cobalt", "Cool", "Copper", "Coral", "Cosmic",
        "Cozy", "Crimson", "Crisp", "Crystal", "Cyan", "Daily",
        "Dandy", "Daring", "Deft", "Dusty", "Eager", "Early",
        "Electric", "Elite", "Emerald", "Endless", "Epic", "Eternal",
        "Fair", "Fancy", "Fast", "Fearless", "Fiery", "Fine",
        "First", "Fleet", "Fresh", "Frosted", "Funny", "Galactic",
        "Gentle", "Giant", "Glad", "Gold", "Golden", "Grand",
        "Granite", "Great", "Green", "Handy", "Happy", "Hardy",
        "Hazel", "Hidden", "Humble", "Icy", "Ideal", "Iron",
        "Ivory", "Jade", "Jazzy", "Jolly", "Jumbo", "Keen",
        "Kind", "Light", "Lightning", "Lilac", "Lively", "Loyal",
        "Lucid", "Lucky", "Lunar", "Magic", "Major", "Marble",
        "Mega", "Mellow", "Merry", "Mighty", "Mint", "Misty",
        "Modern", "Moonlit", "Neat", "Neon", "Nifty", "Nimble",
        "Noble", "Olive", "Onyx", "Opal", "Peppy", "Polar",
        "Prime", "Proud", "Quick", "Quiet", "Radiant", "Rainbow",
        "Rapid", "Regal", "Rising", "Roaring", "Rolling", "Rosy",
        "Royal", "Ruby", "Rusty", "Sage", "Sandy", "Scarlet",
        "Shining", "Shiny", "Silver", "Sleek", "Smart", "Snowy",
        "Soaring", "Solar", "Solid", "Sonic", "Spry", "Steady",
        "Stellar", "Sunlit", "Sunny", "Super", "Swift", "Teal",
        "Thunder", "Tidy", "Topaz", "True", "Tumbling", "Turbo",
        "Urban", "Valiant", "Vast", "Vibrant", "Vivid", "Wandering",
        "Warm", "Wavy", "Wild", "Windy", "Wise", "Witty",
        "Zen", "Zesty", "Zippy",
    ]

    /// Second word of a clan name (199 plural words).
    static let clanNouns: [String] = [
        "Acorns", "Acrobats", "Anchors", "Aspens", "Atlases", "Aviators",
        "Badgers", "Bears", "Bison", "Blazes", "Bolts", "Breezes",
        "Brooks", "Builders", "Camels", "Canyons", "Captains", "Cedars",
        "Champions", "Chipmunks", "Cliffs", "Clouds", "Cobras", "Comets",
        "Cranes", "Creeks", "Crows", "Cubs", "Cyclones", "Daisies",
        "Dawns", "Deltas", "Dingoes", "Dolphins", "Doves", "Dragonflies",
        "Dragons", "Drakes", "Dreamers", "Drifts", "Dunes", "Eagles",
        "Embers", "Explorers", "Falcons", "Ferns", "Finches", "Fireflies",
        "Fjords", "Flames", "Flamingos", "Flares", "Foxes", "Frosts",
        "Galaxies", "Gales", "Geckos", "Geese", "Gems", "Glaciers",
        "Glades", "Glows", "Griffins", "Groves", "Guardians", "Gulls",
        "Hamsters", "Harbors", "Hares", "Hawks", "Heaths", "Hedgehogs",
        "Herons", "Hippos", "Horses", "Ibises", "Inventors", "Islands",
        "Jaguars", "Jets", "Kites", "Koalas", "Koi", "Lagoons",
        "Lakes", "Lanterns", "Larks", "Leaves", "Legends", "Lemurs",
        "Leopards", "Llamas", "Lotuses", "Lynxes", "Mammoths", "Mangoes",
        "Maples", "Marbles", "Marshes", "Mavericks", "Meadows", "Mesas",
        "Meteors", "Mice", "Moons", "Moose", "Moths", "Mustangs",
        "Narwhals", "Navigators", "Newts", "Nomads", "Novas", "Oaks",
        "Oceans", "Orbs", "Orcas", "Orchards", "Otters", "Owls",
        "Pandas", "Panthers", "Parrots", "Peaks", "Pearls", "Pelicans",
        "Penguins", "Pilots", "Pines", "Pioneers", "Pixels", "Planets",
        "Plumes", "Ponies", "Prisms", "Puffins", "Pumas", "Quail",
        "Quests", "Quills", "Raccoons", "Racers", "Rainbows", "Rangers",
        "Ravens", "Reefs", "Rhinos", "Ridges", "Rivers", "Robins",
        "Rockets", "Rollers", "Rooks", "Rovers", "Sables", "Sentinels",
        "Sharks", "Skies", "Sloths", "Snails", "Snowflakes", "Sparks",
        "Sparrows", "Squid", "Squirrels", "Stags", "Stars", "Stones",
        "Storks", "Storms", "Summits", "Sunbeams", "Suns", "Swans",
        "Tapirs", "Tides", "Tigers", "Torches", "Toucans", "Trout",
        "Tulips", "Tumblers", "Turtles", "Unicorns", "Vales", "Vipers",
        "Voles", "Voyagers", "Walruses", "Wanderers", "Waves", "Whales",
        "Winds", "Wizards", "Wolves", "Wrens", "Yaks", "Yetis",
        "Zebras",
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
    /// Nickname numbers: 1...99 minus the blocked ones (keeps a nickname
    /// within 12 characters).
    static let nicknameNumbers: [Int] = (1...99).filter { !blockedNumbers.contains($0) }
    /// Clan numbers: 1...999 minus the blocked ones.
    static let clanNumbers: [Int] = (1...999).filter { !blockedNumbers.contains($0) }

    /// Stored for a signed-in player who has not picked a nickname yet.
    static let defaultNickname = "Roller"

    /// One selection: an index into the first-word list, an index into the
    /// second-word list, and a number.  Which lists depends on what is being
    /// named: `adjectives`/`nouns` for a nickname, `clanAdjectives`/
    /// `clanNouns` for a clan.
    struct Choice: Equatable {
        var adjective: Int
        var noun: Int
        var number: Int
    }

    static func randomNicknameChoice() -> Choice {
        Choice(adjective: Int.random(in: 0..<adjectives.count),
               noun:      Int.random(in: 0..<nouns.count),
               number:    nicknameNumbers.randomElement() ?? 1)
    }

    static func randomClanChoice() -> Choice {
        Choice(adjective: Int.random(in: 0..<clanAdjectives.count),
               noun:      Int.random(in: 0..<clanNouns.count),
               number:    clanNumbers.randomElement() ?? 1)
    }

    // MARK: Build

    static func nickname(_ c: Choice) -> String {
        adjectives[c.adjective] + nouns[c.noun] + String(c.number)
    }

    static func clanName(_ c: Choice) -> String {
        "\(clanAdjectives[c.adjective]) \(clanNouns[c.noun]) \(c.number)"
    }

    /// The clan tag is derived, never typed: the two initials + the number
    /// ("Swift Comets 42" -> "SC42", 3-5 characters).
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

    static func parseNickname(_ s: String) -> Choice? {
        for (ai, adj) in adjectives.enumerated() where s.hasPrefix(adj) {
            let rest = String(s.dropFirst(adj.count))
            for (ni, noun) in nouns.enumerated() where rest.hasPrefix(noun) {
                if let n = number(String(rest.dropFirst(noun.count)), upTo: 99) {
                    return Choice(adjective: ai, noun: ni, number: n)
                }
            }
        }
        return nil
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
    /// else "" (callers show their generic placeholder).
    static func shownNickname(_ raw: String) -> String {
        isValidNickname(raw) ? raw : ""
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
    // Server-managed timestamps; present on reads, omitted on writes.
    var createdAt: String?
    var updatedAt: String?
    var lastSeenAt: String?
    // When the player last tapped "Ask for a life" (null = not asking). Optional
    // + decode-resilient like the stats above.
    var needsLivesAt: String?
    // Weekly baseline (docs/social-schema-v5.sql), kept by the server: the
    // Monday (UTC) the baseline belongs to, and the level / stars the player
    // had when that week began.  Absent before v5 → no weekly pace shown.
    var weekStart: String? = nil
    var weekStartLevel: Int? = nil
    var weekStartStars: Int? = nil
    /// When this player's last life request closed (filled, expired or
    /// cancelled) — the wait before the next one counts from here.
    var livesRequestClosedAt: String? = nil

    /// Levels gained since Monday 00:00 UTC ("+12 this week").  0 when the
    /// stored baseline is from an earlier week (the player has not played
    /// this week) or is absent.
    var levelsThisWeek: Int {
        guard let weekStart, let base = weekStartLevel,
              weekStart == Self.currentWeekStartUTC() else { return 0 }
        return max(0, climbLevel - base)
    }

    /// This week's Monday in UTC as "yyyy-MM-dd" — the same value the
    /// database computes with date_trunc('week', now() at time zone 'utc').
    static func currentWeekStartUTC(now: Date = Date()) -> String {
        var cal = Calendar(identifier: .iso8601)          // weeks start Monday
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let monday = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let c = cal.dateComponents([.year, .month, .day], from: monday)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

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
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
        case lastSeenAt       = "last_seen_at"
        case needsLivesAt     = "needs_lives_at"
        case weekStart        = "week_start"
        case weekStartLevel   = "week_start_level"
        case weekStartStars   = "week_start_stars"
        case livesRequestClosedAt = "lives_request_closed_at"
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
    case rollAlong, zenGarden, rollUp
    case cometClash, sumo, paintBall, coinPit, marbleCup, kingOfHill
    var id: String { rawValue }

    /// Which category this board belongs to (drives the filter's grouping).
    var category: BoardCategory {
        switch self {
        case .rollAlong:                    return .adventure
        case .zenGarden, .rollUp:           return .solo
        default:                            return .competitive   // the six competitive boards
        }
    }

    /// Player-facing board name.
    var title: String {
        switch self {
        case .rollAlong:  return "Roll Along"
        case .zenGarden:  return "Zen Garden"
        case .rollUp:     return "Roll Up"
        case .cometClash: return "Comet Clash"
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
        case .cometClash: return "snake"
        case .sumo:       return "sumo"
        case .paintBall:  return "paintball"
        case .coinPit:    return "goldrush"
        case .marbleCup:  return "marblecup"
        case .kingOfHill: return "koth"
        default:          return nil
        }
    }

    /// PostgREST order clause.  Competitive boards rank by wins, then best.
    var order: String {
        switch self {
        case .rollAlong:  return "climb_level.desc,total_stars.desc"
        case .zenGarden:  return "zen_seconds.desc"
        // Default (Height) order; LeaderboardView swaps in the Time order when
        // the Roll Up board's sort toggle is set to Time.
        case .rollUp:     return "rollup_best.desc,rollup_best_seconds.desc"
        case .cometClash: return "snake_wins.desc,snake_best.desc"
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

/// Dates for the monthly clan battle.  A season is a calendar month in
/// Eastern time (America/New_York), named by its first day ("2026-12-01")
/// exactly as the database names it.
enum SeasonCalendar {
    private static var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }

    /// "yyyy-MM-dd" for a date, in UTC.
    static func dayKey(_ date: Date = Date()) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
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
    let weekLevels: Int
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
        case weekLevels  = "week_levels"
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
        weekLevels  = try c.decodeIfPresent(Int.self, forKey: .weekLevels)  ?? 0
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
