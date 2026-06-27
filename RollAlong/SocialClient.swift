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

    /// Sync the minigame leaderboard stats (best Pinball score, total Zen
    /// seconds, best Gold Rush haul).  Client-trusted, like the climb stats.
    func syncMinigameStats(pinballBest: Int, zenSeconds: Int, goldrushBest: Int) async throws {
        let me = try requireSession()
        let body = MinigamePatch(pinball_best: pinballBest,
                                 zen_seconds: zenSeconds,
                                 goldrush_best: goldrushBest)
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
                 + "coins_collected,pinball_best,zen_seconds,goldrush_best,lives"
        let query = "select=\(cols)&order=\(order)&limit=\(limit)"
        let data = try await send(method: "GET", path: "players", query: query)
        return try decode([PlayerProfile].self, from: data)
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
    // Server-managed timestamps; present on reads, omitted on writes.
    var createdAt: String?
    var updatedAt: String?
    var lastSeenAt: String?
    // When the player last tapped "Ask for a life" (null = not asking). Optional
    // + decode-resilient like the stats above.
    var needsLivesAt: String?

    /// True when the player is currently asking clan-mates for lives.
    var isAskingForLives: Bool { (needsLivesAt?.isEmpty == false) }

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
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
        case lastSeenAt       = "last_seen_at"
        case needsLivesAt     = "needs_lives_at"
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
