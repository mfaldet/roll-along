//
//  TrophySyncService.swift
//  RollAlong
//
//  S3-T3 — Client trophy sync (docs/trophies/sprint-plan.md §2 S3-T3;
//  design.md §3/§4 Option C). Idempotent FULL-SNAPSHOT upsert of every
//  unlocked id, run on launch / foreground / sign-in whenever the engine's
//  `ra_trophySyncDirty` flag is armed. The proven codebase pattern
//  (internal-data-backend.md §7): a one-shot unlock event is converted into a
//  self-healing snapshot ("here are ALL my unlocked ids"), so there is no
//  fragile per-event outbox — a replay is always a no-op.
//
//  TWO PUSH PATHS (both must succeed before the flag clears):
//   1. ALL players — signed-in or not — push the full unlock set to the
//      anonymous `trophy_unlocks` rail, keyed by the install UUID (the SAME
//      anonymous UUID `events` uses — `ra_analytics_user_id` in UserDefaults,
//      no PII). Anon INSERT, `on_conflict` ignore-duplicates → replay-safe.
//      This is why a signed-OUT player still counts toward rarity. Deliberately
//      NOT routed through `AnalyticsClient` — its buffer is memory-only and
//      would drop the snapshot on a kill (the whole reason S1-T8 armed a
//      durable dirty flag instead).
//   2. Signed-in players ADDITIONALLY upsert `player_trophies` (the showcase
//      rail, FK → players, own-row write). A silent no-op until sign-in.
//
//  DIRTY-FLAG CONTRACT: `ra_trophySyncDirty` (armed by TrophyEngine on every
//  unlock) is drained via `engine.clearSyncDirty()` ONLY when every applicable
//  path succeeds. A partial failure (anon push ok, player push threw — or vice
//  versa) leaves the flag ARMED so the next launch/foreground retries — the
//  ratchet's deliver-at-least-once guarantee. Nothing here is a hydrate that
//  overwrites local state; server→local restore is S3-T5.
//
//  TESTABILITY: all network is behind the `TrophyBackend` protocol, so the
//  queue / idempotency / dirty-flag / signed-in-fan-out logic is unit-tested
//  against a mock with ZERO live Supabase calls (the S3 hard rule). The real
//  `SocialTrophyBackend` below mirrors SocialClient / AnalyticsClient's
//  dependency-free PostgREST shape.
//

import Foundation

// ===========================================================================
// Backend abstraction — the ONLY seam that touches the network.
// ===========================================================================

/// The two server writes S3-T3 performs. Injected into `TrophySyncService` so
/// the sync/queue/idempotency logic is provable against a mock. The real impl
/// is `SocialTrophyBackend`; tests use an in-memory double.
///
/// Both calls take the FULL unlock set (a snapshot, not a delta) and MUST be
/// idempotent server-side (`on_conflict … ignore-duplicates`), so replaying a
/// snapshot never duplicates a row. An empty set is a no-op (never a network
/// call — see the service).
protocol TrophyBackend: Sendable {
    /// Push the full unlock set to the anonymous `trophy_unlocks` rail keyed by
    /// `installID` (the anonymous analytics UUID). All players call this.
    /// Throws on any non-2xx / transport error so the caller keeps the flag
    /// armed.
    func upsertAnonUnlocks(installID: UUID, trophyIDs: [String]) async throws

    /// Push the full unlock set to the signed-in `player_trophies` showcase
    /// rail for `playerID` (own-row write). Only called when signed in.
    func upsertPlayerTrophies(playerID: UUID, trophyIDs: [String]) async throws

    /// Fetch every `player_trophies.trophy_id` for `playerID` — the ONLY
    /// server→local read in the whole trophy system (S3-T5's hydrate-on-sign-in;
    /// design.md §4 "Supabase restore for signed-in players"). Returns the raw
    /// id set; the caller UNIONS it into the local ledger (never subtracts).
    /// Reads the SIGNED-IN showcase rail (`player_trophies`), never the anonymous
    /// `trophy_unlocks` rail — that one is INSERT-only and never client-readable
    /// (docs/trophies/trophy-schema.sql RLS). Throws on any non-2xx / transport
    /// error so the caller leaves the local ledger untouched and retries later.
    func fetchPlayerTrophies(playerID: UUID) async throws -> [String]

    // --- S3-T9 curated public showcase (`player_showcase`) -----------------

    /// Upsert `playerID`'s CURATED public showcase row (per-grade counts + up to
    /// 3 ids). Own-row write; the projection is public-readable so it renders on
    /// another viewer's PublicProfileView. Throws on any non-2xx / transport
    /// error so the caller can retry. See docs/trophies/trophy-schema.sql
    /// `public.player_showcase`.
    func upsertShowcase(_ showcase: TrophyPublicShowcase, playerID: UUID) async throws

    /// DELETE `playerID`'s public showcase row — the server-side effect of
    /// toggling the showcase OFF (design.md §7 / D6). Removes ONLY the curated
    /// projection; the player's raw `player_trophies` unlock rows are untouched
    /// (rarity + restore still need them). Idempotent: deleting an absent row is
    /// a no-op. Throws on any non-2xx / transport error.
    func deleteShowcase(playerID: UUID) async throws

    /// Fetch `playerID`'s public showcase row (viewer → render), or nil when the
    /// player has no showcase (never set it, or toggled it off). Any client role
    /// (anon or authenticated) may read it. Throws on any non-2xx / transport
    /// error so the caller shows the placeholder rather than a stale strip.
    func fetchShowcase(playerID: UUID) async throws -> TrophyPublicShowcase?
}

// ===========================================================================
// TrophySyncService — orchestrates the drain. No networking of its own.
// ===========================================================================

/// Drains `TrophyEngine`'s dirty flag by pushing the full unlock snapshot to
/// the backend. Own type (not on GameState / the engine) so a sync never
/// re-renders gameplay and the network seam stays injectable.
///
/// Not an `ObservableObject` — nothing observes it; it is a fire-and-forget
/// service invoked at launch / foreground / sign-in. `@MainActor`-free like
/// the engine (S2 note): callers `await` it off the hot path.
final class TrophySyncService: @unchecked Sendable {

    static let shared = TrophySyncService()

    private let backend: TrophyBackend

    /// Resolves the anonymous install UUID — the SAME id the analytics rail
    /// uses (`ra_analytics_user_id`), so numerator (trophy_unlocks.install_id)
    /// and denominator (distinct events.user_id) share one rail and can never
    /// diverge. Read directly from UserDefaults with the analytics
    /// generate-if-absent semantics; NEVER routed through AnalyticsClient.
    private let installID: () -> UUID

    /// The signed-in player's id, or nil when signed out. Wraps
    /// `SocialClient.shared.currentUserId` in production; injectable for tests.
    private let currentPlayerID: () -> UUID?

    /// Serializes concurrent `sync` calls (launch + a fast foreground) so two
    /// drains never race on the same flag. A drain in flight makes the next
    /// call a no-op — the snapshot is idempotent, a second push is redundant.
    private var isSyncing = false
    private let lock = NSLock()

    init(backend: TrophyBackend = SocialTrophyBackend(),
         installID: @escaping () -> UUID = { TrophySyncService.resolveInstallID() },
         currentPlayerID: @escaping () -> UUID? = { SocialClient.shared.currentUserId }) {
        self.backend = backend
        self.installID = installID
        self.currentPlayerID = currentPlayerID
    }

    private convenience init() {
        self.init(backend: SocialTrophyBackend())
    }

    // MARK: - Drain

    /// Push the engine's full unlock snapshot to the backend when the dirty
    /// flag is armed, clearing the flag ONLY on full success.
    ///
    /// Fire-and-forget from the caller's view (launch/foreground/sign-in);
    /// swallows all errors so a signed-out or offline player never sees a
    /// trophy-sync failure in the UI. Returns whether a full sync completed
    /// (drained the flag) — used by tests, ignored by production call sites.
    ///
    /// Contract:
    ///  • flag clear (dirty) → no-op, no network.
    ///  • empty unlock set   → clears the flag with no network (nothing to push).
    ///  • path (1) anon always; path (2) player only when signed in.
    ///  • flag drains ONLY when every applicable path succeeded; any throw
    ///    leaves it armed for the next launch/foreground.
    @discardableResult
    func sync(engine: TrophyEngine) async -> Bool {
        // Read the flag + snapshot up front. `isSyncDirty` and `unlockedIDs`
        // are the engine's own state; we never mutate the engine except the
        // final `clearSyncDirty()` drain.
        guard engine.isSyncDirty else { return false }

        // Reentrancy guard: coalesce a launch + foreground double-fire. The
        // lock is taken/released ENTIRELY within synchronous helpers (never
        // held across an `await`), so the drain below can't overlap itself.
        guard beginSyncing() else { return false }
        defer { endSyncing() }

        // Sorted for a stable, deterministic request body (test-friendly; the
        // server ignores order). A `Set` → `[String]` snapshot taken once.
        let ids = engine.unlockedIDs.sorted()

        // Nothing to push (dirty but no unlocks — e.g. a flag armed then the
        // sole unlock proved to be an unknown-catalog id that still counts):
        // clear the flag, no network. `unlockedIDs` empty is the only case.
        guard !ids.isEmpty else {
            await MainActor.run { engine.clearSyncDirty() }
            return true
        }

        do {
            // Path 1 — anonymous rail, EVERY player. Must succeed.
            try await backend.upsertAnonUnlocks(installID: installID(), trophyIDs: ids)

            // Path 2 — signed-in showcase rail. Only when signed in; a
            // signed-out player's flag still drains on path 1 alone.
            if let playerID = currentPlayerID() {
                try await backend.upsertPlayerTrophies(playerID: playerID, trophyIDs: ids)
            }
        } catch {
            // Partial or total failure → leave the flag ARMED for next time.
            // Deliberately silent: trophy sync never surfaces into the UI.
            return false
        }

        // Full success across every applicable path → drain the flag. The
        // engine sends its own objectWillChange for this (clearSyncDirty),
        // which must happen on the main actor like every other @Published-
        // adjacent mutation.
        await MainActor.run { engine.clearSyncDirty() }
        return true
    }

    // MARK: - Hydrate on sign-in (server → local, the app's FIRST such path)

    /// Restore a signed-in player's trophies from the server into the local
    /// ledger — S3-T5 / design.md §4 "Supabase restore for signed-in players"
    /// (design decision #8, ruled yes 2026-07-07). This is the app's FIRST
    /// hydrate-from-server path, and it is deliberately trophies-only: the ledger
    /// is a pure ratchet, so a UNION can only ADD unlocks and can never clobber
    /// local state (unlike the general `players` save-restore problem, which is
    /// why nothing else hydrates from the server yet).
    ///
    /// Contract (a pure max-merge UNION — NEVER subtraction or overwrite):
    ///  • signed out → no-op, no network (nothing to restore for an anon rail
    ///    that is INSERT-only and never client-readable).
    ///  • fetch the player's `player_trophies` ids, then
    ///    `engine.mergeUnlocks(ids:)`: server ∪ local. Server-only unlocks are
    ///    ADDED locally; local-only unlocks are UNTOUCHED (and the merge arms the
    ///    dirty flag so they push UP on the next `sync`, closing the loop).
    ///  • a fetch failure is silent (like `sync`): the local ledger is left
    ///    exactly as it was and the next sign-in / launch retries. A hydrate
    ///    never removes a local unlock even when the server read fails.
    ///
    /// Idempotent and convergent: re-hydrating with a server set that is already
    /// a subset of local latches nothing (`mergeUnlocks` returns []). Fire-and-
    /// forget from the caller's view (invoke on sign-in / on a restored session);
    /// returns the ids this hydrate newly latched locally — used by tests and any
    /// caller that wants to react (e.g. a coalesced "welcome back" reveal),
    /// ignored by plain wiring.
    ///
    /// NOTE: hydrate (server→local restore) and `sync` (local→server push) are
    /// separate, complementary passes. A sign-in flow runs hydrate FIRST (so the
    /// server's unlocks land locally and the union arms the flag), then `sync`
    /// (so the unioned local snapshot — server ∪ local — pushes back up to both
    /// rails). Order is not load-bearing for correctness (both are pure unions),
    /// only for promptness.
    @discardableResult
    func hydrateOnSignIn(engine: TrophyEngine) async -> [String] {
        // Signed out → nothing to restore. The anonymous rail is INSERT-only and
        // never readable, so there is no server set to union in for an anon
        // player; their reinstall coverage is iCloud KV (S3-T8), not this path.
        guard let playerID = currentPlayerID() else { return [] }

        let serverIDs: [String]
        do {
            serverIDs = try await backend.fetchPlayerTrophies(playerID: playerID)
        } catch {
            // Silent, like `sync`: a failed restore leaves the local ledger
            // exactly as it was (never subtracts) and the next sign-in retries.
            return []
        }

        // Empty server set → nothing to union; mergeUnlocks would no-op anyway,
        // but skip the merge (and its potential main-actor hop) entirely.
        guard !serverIDs.isEmpty else { return [] }

        // The ONE union: server ∪ local. Runs on the main actor because
        // `mergeUnlocks` mutates the engine's @Published `unlockedIDs` (and may
        // arm the not-@Published dirty flag) — same discipline as `sync`'s
        // `clearSyncDirty()`. A pure ratchet: never removes, never overwrites.
        return await MainActor.run { engine.mergeUnlocks(ids: Set(serverIDs)) }
    }

    // MARK: - Public showcase (S3-T9 — the curated public projection)

    /// The outcome of a showcase sync — surfaced for tests / callers; production
    /// wiring ignores it (fire-and-forget).
    enum ShowcaseSyncResult: Equatable {
        /// Pushed a curated showcase to `player_showcase` (enabled + signed-in +
        /// something earned).
        case pushed(TrophyPublicShowcase)
        /// Deleted the showcase server-side (toggle OFF, or enabled-but-empty).
        case deleted
        /// No network happened — signed out (no public profile to show on).
        case skippedSignedOut
        /// A network error; the caller may retry. The local toggle is unaffected.
        case failed
    }

    /// Reconcile the signed-in player's CURATED public showcase with the server
    /// (design.md §7 / decision #10, D6 ruled 2026-07-07: on for signed-in, with
    /// a Settings toggle).
    ///
    /// - `enabled == true`  → upsert the curated showcase (per-grade counts + up
    ///   to 3 rarest-earned ids by default, or the player's chosen order). An
    ///   enabled-but-EMPTY ledger deletes any stale row (nothing to show).
    /// - `enabled == false` → DELETE the showcase row server-side, so toggling
    ///   off actually removes the public projection (NOT just a local hide —
    ///   S3-T9 acceptance). The raw `player_trophies` unlock rows are untouched
    ///   (rarity + restore still need them).
    ///
    /// Signed out → no-op, no network (there is no public profile to project
    /// onto). Fire-and-forget from the caller: swallows network errors (returns
    /// `.failed`) so a toggle flip never throws into the UI; the next call
    /// retries. Invoke on the Settings toggle change AND after a `sync` so the
    /// public counts track new unlocks.
    @discardableResult
    func syncShowcase(engine: TrophyEngine,
                      enabled: Bool,
                      chosenIDs: [String] = []) async -> ShowcaseSyncResult {
        // No public profile without a signed-in player id.
        guard let playerID = currentPlayerID() else { return .skippedSignedOut }

        // Toggle OFF → remove the public projection server-side.
        if !enabled {
            do {
                try await backend.deleteShowcase(playerID: playerID)
                return .deleted
            } catch {
                return .failed
            }
        }

        // Toggle ON → build the curated projection from the local ledger.
        let showcase = TrophyPublicShowcase(engine: engine, chosenIDs: chosenIDs)

        // Enabled but nothing earned yet → ensure no stale row lingers, but
        // don't publish an empty showcase.
        guard !showcase.isEmpty else {
            do {
                try await backend.deleteShowcase(playerID: playerID)
                return .deleted
            } catch {
                return .failed
            }
        }

        do {
            try await backend.upsertShowcase(showcase, playerID: playerID)
            return .pushed(showcase)
        } catch {
            return .failed
        }
    }

    /// Fetch another player's public showcase for rendering (viewer side —
    /// PublicProfileView). Reads the public `player_showcase` projection, never
    /// the VIEWER's local ledger (that would paint the viewer's own trophies on
    /// someone else's profile). Returns nil on any error OR when the player has
    /// no showcase (never set / toggled off), so the caller shows the honest
    /// placeholder. Never throws into the UI.
    func fetchShowcase(for playerID: UUID) async -> TrophyPublicShowcase? {
        try? await backend.fetchShowcase(playerID: playerID)
    }

    /// Claims the single in-flight slot; false when a drain is already running.
    /// Synchronous (the lock is never held across an await).
    private func beginSyncing() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isSyncing { return false }
        isSyncing = true
        return true
    }

    /// Releases the in-flight slot. Synchronous.
    private func endSyncing() {
        lock.lock(); isSyncing = false; lock.unlock()
    }

    // MARK: - Install UUID (anonymous rail key)

    private static let installIDKey = "ra_analytics_user_id"

    /// The anonymous device-install UUID — read from the SAME UserDefaults key
    /// the analytics rail persists (`ra_analytics_user_id`), with the same
    /// generate-and-store-if-absent semantics, so trophy_unlocks.install_id ==
    /// events.user_id for this install. NOT routed through AnalyticsClient (its
    /// buffer is memory-only); this only touches the durable UserDefaults key.
    static func resolveInstallID(_ defaults: UserDefaults = .standard) -> UUID {
        if let stored = defaults.string(forKey: installIDKey),
           let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let new = UUID()
        defaults.set(new.uuidString, forKey: installIDKey)
        return new
    }
}

// ===========================================================================
// SocialTrophyBackend — the real PostgREST implementation.
//
// Mirrors SocialClient / AnalyticsClient: talks to PostgREST directly, no
// Supabase SDK. The anon push uses the ANON key (like AnalyticsClient); the
// signed-in push uses the player's Bearer token (like SocialClient). Server
// schema: docs/trophies/trophy-schema.sql.
// ===========================================================================

struct SocialTrophyBackend: TrophyBackend {

    // Same project + client-safe keys as the existing clients.
    private static let projectURL = "https://mhwpcwauzvmtmuphtajs.supabase.co"

    /// Anon (public) JWT — safe to embed; RLS allows only INSERT on
    /// `trophy_unlocks` and never SELECT (docs/trophies/trophy-schema.sql).
    /// Identical to AnalyticsClient.anonKey (the anonymous events rail).
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1od3Bjd2F1enZtdG11cGh0YWpzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwMDI1MzMsImV4cCI6MjA5NTU3ODUzM30." +
        "dKtYkbLF43vLYiCMaxhurBT8rTqAMxuKuJ2z5mkXKsM"

    private let encoder = JSONEncoder()

    // MARK: - Path 1: anonymous trophy_unlocks (all players)

    func upsertAnonUnlocks(installID: UUID, trophyIDs: [String]) async throws {
        guard !trophyIDs.isEmpty else { return }
        let rows = trophyIDs.map {
            AnonUnlockRow(install_id: installID.uuidString, trophy_id: $0)
        }
        // on_conflict ignore-duplicates → the UNIQUE (install_id, trophy_id)
        // constraint makes a replay a no-op and preserves the server-side
        // unlocked_at (client clocks ignored). return=minimal keeps it cheap.
        try await postAnon(
            path: "trophy_unlocks",
            query: "on_conflict=install_id,trophy_id",
            body: try encoder.encode(rows),
            prefer: "resolution=ignore-duplicates,return=minimal"
        )
    }

    // MARK: - Path 2: signed-in player_trophies (showcase rail)

    func upsertPlayerTrophies(playerID: UUID, trophyIDs: [String]) async throws {
        guard !trophyIDs.isEmpty else { return }
        let token = try SocialClient.shared.trophyAccessToken()
        let rows = trophyIDs.map {
            PlayerTrophyRow(player_id: playerID.uuidString, trophy_id: $0)
        }
        // PK (player_id, trophy_id); ignore-duplicates → own-row idempotent
        // upsert. RLS scopes the write to the player's own rows.
        try await postAuthed(
            path: "player_trophies",
            query: "on_conflict=player_id,trophy_id",
            body: try encoder.encode(rows),
            token: token,
            prefer: "resolution=ignore-duplicates,return=minimal"
        )
    }

    // MARK: - Hydrate: read own player_trophies (S3-T5 sign-in restore)

    func fetchPlayerTrophies(playerID: UUID) async throws -> [String] {
        let token = try SocialClient.shared.trophyAccessToken()
        // GET only this player's rows, selecting just the id column — the
        // server→local restore never needs timestamps (the engine keeps its own
        // first-unlock stamp; a merged id adopts `now()`). Filtering to
        // player_id=eq.<self> keeps the payload to the player's own set even
        // though RLS lets authenticated read all rows (the showcase read path).
        let query = "select=trophy_id&player_id=eq.\(playerID.uuidString)"
        let data = try await getAuthed(path: "player_trophies", query: query, token: token)
        let rows = try JSONDecoder().decode([PlayerTrophyIDRow].self, from: data)
        return rows.map(\.trophy_id)
    }

    // MARK: - S3-T9 curated public showcase (player_showcase table)

    func upsertShowcase(_ showcase: TrophyPublicShowcase, playerID: UUID) async throws {
        let token = try SocialClient.shared.trophyAccessToken()
        // One row per player (PK player_id). merge-duplicates so a re-push
        // OVERWRITES the counts/ids (unlike the ignore-duplicates unlock rails,
        // the showcase is a mutable snapshot that must reflect the latest set).
        try await postAuthed(
            path: "player_showcase",
            query: "on_conflict=player_id",
            body: try encoder.encode([showcase.row(playerID: playerID)]),
            token: token,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func deleteShowcase(playerID: UUID) async throws {
        let token = try SocialClient.shared.trophyAccessToken()
        // RLS also scopes delete to the caller's own row; the explicit filter
        // keeps the request well-formed (PostgREST requires a filter to delete).
        try await deleteAuthed(
            path: "player_showcase",
            query: "player_id=eq.\(playerID.uuidString)",
            token: token
        )
    }

    func fetchShowcase(playerID: UUID) async throws -> TrophyPublicShowcase? {
        // Public read — but authenticate when we can (the app is usually signed
        // in when viewing profiles). Falls back to the anon key for a signed-out
        // viewer so a deep-link visitor still sees the showcase.
        let query = "player_id=eq.\(playerID.uuidString)&limit=1"
        let data: Data
        if let token = try? SocialClient.shared.trophyAccessToken() {
            data = try await getAuthed(path: "player_showcase", query: query, token: token)
        } else {
            data = try await getAnon(path: "player_showcase", query: query)
        }
        let rows = try JSONDecoder().decode([TrophyPublicShowcase.Row].self, from: data)
        guard let row = rows.first else { return nil }
        return TrophyPublicShowcase(row: row)
    }

    // MARK: - REST core (mirrors SocialClient.send / AnalyticsClient.flush)

    private func postAnon(path: String, query: String, body: Data, prefer: String) async throws {
        var req = try request(path: path, query: query, body: body, prefer: prefer)
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Self.anonKey)", forHTTPHeaderField: "Authorization")
        try await run(req)
    }

    private func postAuthed(path: String, query: String, body: Data, token: String, prefer: String) async throws {
        var req = try request(path: path, query: query, body: body, prefer: prefer)
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        try await run(req)
    }

    /// Authenticated GET returning the response body (the hydrate read). Mirrors
    /// SocialClient.send's GET shape: anon apikey header + the player's Bearer
    /// token, no body/Prefer. Throws on any non-2xx so the caller leaves the
    /// local ledger untouched.
    private func getAuthed(path: String, query: String, token: String) async throws -> Data {
        let urlString = "\(Self.projectURL)/rest/v1/\(path)"
            + (query.isEmpty ? "" : "?\(query)")
        guard let url = URL(string: urlString) else { throw SocialError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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

    /// Anonymous GET returning the response body (the signed-out showcase read).
    /// Uses the anon key so a deep-link visitor with no session still renders a
    /// public showcase (RLS grants anon SELECT on `player_showcase`).
    private func getAnon(path: String, query: String) async throws -> Data {
        let urlString = "\(Self.projectURL)/rest/v1/\(path)"
            + (query.isEmpty ? "" : "?\(query)")
        guard let url = URL(string: urlString) else { throw SocialError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Self.anonKey)", forHTTPHeaderField: "Authorization")
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

    /// Authenticated DELETE (the showcase toggle-off). Mirrors the authed shape:
    /// anon apikey header + the player's Bearer token, a PostgREST filter in the
    /// query. Throws on any non-2xx so the caller can retry.
    private func deleteAuthed(path: String, query: String, token: String) async throws {
        let urlString = "\(Self.projectURL)/rest/v1/\(path)"
            + (query.isEmpty ? "" : "?\(query)")
        guard let url = URL(string: urlString) else { throw SocialError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        try await run(req)
    }

    private func request(path: String, query: String, body: Data, prefer: String) throws -> URLRequest {
        let urlString = "\(Self.projectURL)/rest/v1/\(path)"
            + (query.isEmpty ? "" : "?\(query)")
        guard let url = URL(string: urlString) else { throw SocialError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(prefer, forHTTPHeaderField: "Prefer")
        req.httpBody = body
        return req
    }

    private func run(_ req: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SocialError.http(status: -1, body: "no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw SocialError.http(status: http.statusCode,
                                   body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Wire rows (keys match docs/trophies/trophy-schema.sql columns)

    private struct AnonUnlockRow: Encodable {
        let install_id: String
        let trophy_id: String
    }

    private struct PlayerTrophyRow: Encodable {
        let player_id: String
        let trophy_id: String
    }

    /// The hydrate read's row shape — just the id column (select=trophy_id).
    private struct PlayerTrophyIDRow: Decodable {
        let trophy_id: String
    }
}
