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
                         lives: Int) async throws -> PlayerProfile {
        let me = try requireSession()
        let body = ProfileUpsert(id: me.userId,
                                 display_name: displayName,
                                 climb_level: climbLevel,
                                 highest_unlocked: highestUnlocked,
                                 total_stars: totalStars,
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
    func syncProgress(climbLevel: Int, highestUnlocked: Int, totalStars: Int) async throws {
        let me = try requireSession()
        let body = ProgressPatch(climb_level: climbLevel,
                                 highest_unlocked: highestUnlocked,
                                 total_stars: totalStars)
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

    /// Top climbers, highest first.  Ties broken by stars.
    func fetchLeaderboard(limit: Int = 100) async throws -> [PlayerProfile] {
        let query = "select=id,display_name,climb_level,highest_unlocked,total_stars,lives"
            + "&order=climb_level.desc,total_stars.desc"
            + "&limit=\(limit)"
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
struct PlayerProfile: Codable, Identifiable {
    let id: UUID
    var displayName: String
    var climbLevel: Int
    var highestUnlocked: Int
    var totalStars: Int
    var lives: Int
    // Server-managed timestamps; present on reads, omitted on writes.
    var createdAt: String?
    var updatedAt: String?
    var lastSeenAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName     = "display_name"
        case climbLevel       = "climb_level"
        case highestUnlocked  = "highest_unlocked"
        case totalStars       = "total_stars"
        case lives
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
        case lastSeenAt       = "last_seen_at"
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

// ---------------------------------------------------------------------------
// Private write payloads — snake_case property names map straight to columns.
// ---------------------------------------------------------------------------
private struct ProfileUpsert: Encodable {
    let id: UUID
    let display_name: String
    let climb_level: Int
    let highest_unlocked: Int
    let total_stars: Int
    let lives: Int
}

private struct ProgressPatch: Encodable {
    let climb_level: Int
    let highest_unlocked: Int
    let total_stars: Int
}

private struct GiftInsert: Encodable {
    let sender_id: UUID
    let recipient_id: UUID
    let amount: Int
}

private struct ClaimPatch: Encodable {
    let claimed_at: String
}
