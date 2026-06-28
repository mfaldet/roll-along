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
    func deleteMyAccount() async throws {
        let session = try requireSession()
        guard let url = URL(string: "\(Self.projectURL)/functions/v1/delete-account") else {
            throw SocialError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",        forHTTPHeaderField: "Content-Type")
        req.setValue(Self.apiKey,               forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

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
                                 display_name: displayName,
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
                           kothBest: Int, kothWins: Int) async throws {
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
                                 goldrush_wins: goldrushWins)
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
    /// default is the climb board; minigame boards pass e.g. "pinball_best.desc".
    func fetchLeaderboard(order: String = "climb_level.desc,total_stars.desc",
                          limit: Int = 100) async throws -> [PlayerProfile] {
        let cols = "id,display_name,climb_level,highest_unlocked,total_stars,"
                 + "coins_collected,pinball_best,zen_seconds,goldrush_best,lives,"
                 + "snake_best,sumo_best,paintball_best,marblecup_best,koth_best,"
                 + "snake_wins,sumo_wins,paintball_wins,marblecup_wins,koth_wins,goldrush_wins"
        let query = "select=\(cols)&order=\(order)&limit=\(limit)"
        let data = try await send(method: "GET", path: "players", query: query)
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
        let query = "select=id,display_name,climb_level,highest_unlocked,total_stars,lives"
            + "&display_name=ilike.*\(escaped)*"
            + "&id=neq.\(me.userId.uuidString)"
            + "&order=climb_level.desc&limit=\(limit)"
        let data = try await send(method: "GET", path: "players", query: query)
        return try decode([PlayerProfile].self, from: data)
    }

    /// Resolve a set of player ids to their profiles (e.g. friends from edges).
    func fetchProfiles(ids: [UUID]) async throws -> [PlayerProfile] {
        guard !ids.isEmpty else { return [] }
        let list = ids.map { $0.uuidString }.joined(separator: ",")
        let query = "select=id,display_name,climb_level,highest_unlocked,total_stars,lives,needs_lives_at"
            + "&id=in.(\(list))"
        let data = try await send(method: "GET", path: "players", query: query)
        return try decode([PlayerProfile].self, from: data)
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
    func createClan(name: String, tag: String, description: String) async throws -> Clan {
        let me = try requireSession()
        let insert = ClanInsert(name: name, tag: tag,
                                description: description, owner_id: me.userId)
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

    /// Disband a clan you own — deleting the row cascades every membership.
    /// RLS permits this only for the owner.
    func disbandClan(id: UUID) async throws {
        _ = try requireSession()
        _ = try await send(method: "DELETE", path: "clans",
                           query: "id=eq.\(id.uuidString)", prefer: "return=minimal")
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

    /// Post a clan activity event (joined / left / sent_life / requested_life / thanked).
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
    var displayName: String
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
    // Server-managed timestamps; present on reads, omitted on writes.
    var createdAt: String?
    var updatedAt: String?
    var lastSeenAt: String?
    // When the player last tapped "Ask for a life" (null = not asking). Optional
    // + decode-resilient like the stats above.
    var needsLivesAt: String?

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
         createdAt: String? = nil, updatedAt: String? = nil,
         lastSeenAt: String? = nil, needsLivesAt: String? = nil) {
        self.id = id; self.displayName = displayName; self.climbLevel = climbLevel
        self.highestUnlocked = highestUnlocked; self.totalStars = totalStars
        self.lives = lives; self.coinsCollected = coinsCollected
        self.pinballBest = pinballBest; self.zenSeconds = zenSeconds
        self.goldrushBest = goldrushBest; self.snakeBest = snakeBest
        self.sumoBest = sumoBest; self.paintballBest = paintballBest
        self.marblecupBest = marblecupBest; self.kothBest = kothBest
        self.snakeWins = snakeWins; self.sumoWins = sumoWins
        self.paintballWins = paintballWins; self.marblecupWins = marblecupWins
        self.kothWins = kothWins; self.goldrushWins = goldrushWins
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt; self.needsLivesAt = needsLivesAt
    }

    /// True when the player is currently asking clan-mates for lives.
    var isAskingForLives: Bool { (needsLivesAt?.isEmpty == false) }

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
        case displayName     = "display_name"
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
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
        case lastSeenAt       = "last_seen_at"
        case needsLivesAt     = "needs_lives_at"
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
enum LeaderboardBoard: String, CaseIterable, Identifiable {
    case rollAlong, pinball, zenGarden
    case cometClash, sumo, paintBall, coinPit, marbleCup, kingOfHill
    var id: String { rawValue }

    /// Player-facing board name.
    var title: String {
        switch self {
        case .rollAlong:  return "Roll Along"
        case .pinball:    return "Pinball"
        case .zenGarden:  return "Zen Garden"
        case .cometClash: return "Comet Clash"
        case .sumo:       return "Sumo Survival"
        case .paintBall:  return "Paint Ball"
        case .coinPit:    return "Coin Pit"
        case .marbleCup:  return "Marble Cup"
        case .kingOfHill: return "King of the Hill"
        }
    }

    /// The competitive GameMode id backing this board, or nil for the climb and
    /// the solo (Pinball / Zen) boards.
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
        case .pinball:    return "pinball_best.desc"
        case .zenGarden:  return "zen_seconds.desc"
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
        case .pinball:   return (p.pinballBest ?? 0) > 0
        case .zenGarden: return (p.zenSeconds ?? 0) > 0
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
        case .pinball:   return "\((p.pinballBest ?? 0).formatted()) pts"
        case .zenGarden: return Self.zenText(p.zenSeconds ?? 0)
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
    var name: String
    var tag: String
    var description: String
    let ownerId: UUID
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, tag, description
        case ownerId   = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
