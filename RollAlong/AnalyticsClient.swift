import Foundation
import UIKit

// ---------------------------------------------------------------------------
// AnalyticsClient — fire-and-forget analytics over to Supabase.
//
// • Anonymous: identifies users by a UUID stored in UserDefaults (no PII).
// • Session-aware: a fresh UUID on each cold-start.
// • Buffered: events accumulate in memory and POST in small batches every
//   30s or when 8 events are queued, whichever first.  Reduces request
//   overhead and lets us survive brief network outages.
// • Best-effort: a batch that fails for a network reason or a server error
//   goes back to the FRONT of the buffer and is retried on the next flush.
//   A batch the server REJECTS (HTTP 400) is split in half and each half is
//   retried at once, down to single events; an event rejected on its own is
//   dropped and the reason logged, so one bad event never holds back the
//   rest.  If the buffer overflows (1000 events) the oldest are dropped.
// • Every event encodes the same keys (`level` is sent as null when there is
//   none): PostgREST refuses a bulk insert whose objects have different keys.
// • The buffer lives in memory only: events still waiting when the app is
//   closed are lost.
//
// Server schema: see docs/supabase-schema.sql.  Single `events` table with
// columns user_id, session_id, event_name, properties, level, app_version,
// ios_version, device_model.
// ---------------------------------------------------------------------------

final class AnalyticsClient: @unchecked Sendable {
    static let shared = AnalyticsClient()

    // MARK: - Configuration

    private static let projectURL = "https://mhwpcwauzvmtmuphtajs.supabase.co"
    /// Anon (public) JWT.  Safe to embed in the client — RLS only allows
    /// INSERT on the events table.
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1od3Bjd2F1enZtdG11cGh0YWpzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwMDI1MzMsImV4cCI6MjA5NTU3ODUzM30." +
        "dKtYkbLF43vLYiCMaxhurBT8rTqAMxuKuJ2z5mkXKsM"

    private static let flushInterval: TimeInterval = 30
    private static let flushThreshold:  Int        = 8
    private static let bufferCap:       Int        = 1000

    // MARK: - Identity

    private let userId:    UUID
    private(set) var sessionId: UUID

    private static let userIdKey = "ra_analytics_user_id"

    // MARK: - Device context

    private let appVersion:  String
    private let iosVersion:  String
    private let deviceModel: String

    // MARK: - Buffer

    /// Guards `buffer` and `isFlushing`: events are tracked from the main
    /// thread and from background tasks, and failed batches come back from
    /// the network task.
    private let lock = NSLock()
    private var buffer: [PendingEvent] = []
    private var isFlushing = false
    private var flushTimer: Timer?

    // MARK: - Init

    private init() {
        // user id — persisted across launches
        if let stored = UserDefaults.standard.string(forKey: Self.userIdKey),
           let uuid   = UUID(uuidString: stored) {
            userId = uuid
        } else {
            let new = UUID()
            UserDefaults.standard.set(new.uuidString, forKey: Self.userIdKey)
            userId = new
        }
        // session id — fresh each cold-start
        sessionId = UUID()

        // Device + app context
        appVersion  = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        iosVersion  = UIDevice.current.systemVersion
        deviceModel = Self.deviceIdentifier()

        // Periodic flush timer — Timer.scheduledTimer fires on the main
        // runloop, so calling flush() here is safe.
        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.flushInterval,
                                          repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    // MARK: - Public API

    /// Track an event.  Fire-and-forget — buffered, batched, sent in the
    /// background.  Safe to call from any user-facing event site.
    func track(_ name: String,
               properties: [String: AnyEncodable] = [:],
               level: Int? = nil) {
        let event = PendingEvent(
            userId:       userId,
            sessionId:    sessionId,
            eventName:    name,
            properties:   properties,
            level:        level,
            appVersion:   appVersion,
            iosVersion:   iosVersion,
            deviceModel:  deviceModel
        )
        lock.lock()
        buffer.append(event)
        trimToCapLocked()
        let shouldFlush = buffer.count >= Self.flushThreshold
        lock.unlock()
        if shouldFlush { flush() }
    }

    /// Begin a fresh session — call when the app cold-starts or comes back
    /// from background after a long idle.
    func startNewSession() {
        sessionId = UUID()
    }

    /// Force a flush (e.g. when the app moves to background).
    func flush() {
        lock.lock()
        guard !isFlushing, !buffer.isEmpty else { lock.unlock(); return }
        let batch = buffer
        buffer.removeAll(keepingCapacity: true)
        isFlushing = true
        lock.unlock()
        Task { [weak self] in
            await self?.send(batch)
            self?.lock.lock()
            self?.isFlushing = false
            self?.lock.unlock()
        }
    }

    /// Put a batch that could not be delivered back at the FRONT of the
    /// buffer (it is older than anything tracked since), then enforce the cap.
    private func requeue(_ batch: [PendingEvent]) {
        lock.lock()
        buffer.insert(contentsOf: batch, at: 0)
        trimToCapLocked()
        lock.unlock()
    }

    /// Drop the oldest events beyond `bufferCap`.  Caller holds `lock`.
    private func trimToCapLocked() {
        let over = buffer.count - Self.bufferCap
        guard over > 0 else { return }
        buffer.removeFirst(over)
        #if DEBUG
        print("[Analytics] buffer full, dropped the \(over) oldest events")
        #endif
    }

    // MARK: - Networking

    /// What happened to one POST.
    enum PostOutcome: Equatable {
        case sent
        case rejected(status: Int, reason: String)   // the server refused this content
        case retryLater(String)                      // network or server trouble
    }

    /// Deliver a batch.  A rejected batch is split and the halves sent at
    /// once, so a bad event cannot hold back the rest; an event rejected on
    /// its own is dropped with the reason logged.  Anything that fails for a
    /// network or server reason goes back to the buffer for the next flush.
    private func send(_ batch: [PendingEvent]) async {
        guard !batch.isEmpty else { return }
        switch await post(batch) {
        case .sent:
            return
        case .retryLater(let why):
            requeue(batch)
            #if DEBUG
            print("[Analytics] \(why), re-queued \(batch.count) events")
            #endif
        case .rejected(let status, let reason):
            if batch.count == 1 {
                #if DEBUG
                print("[Analytics] dropped event \(batch[0].eventName): HTTP \(status) \(reason)")
                #endif
                return
            }
            let mid = batch.count / 2
            await send(Array(batch[..<mid]))
            await send(Array(batch[mid...]))
        }
    }

    private func post(_ batch: [PendingEvent]) async -> PostOutcome {
        guard let url = URL(string: "\(Self.projectURL)/rest/v1/events") else {
            return .rejected(status: 0, reason: "bad URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",     forHTTPHeaderField: "Content-Type")
        req.setValue(Self.anonKey,           forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Self.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("return=minimal",       forHTTPHeaderField: "Prefer")

        do {
            req.httpBody = try PendingEvent.encodeBatch(batch)
        } catch {
            // Cannot happen with the guards in PendingEvent/AnyEncodable, but
            // treat it like a rejection so the split finds the culprit.
            return .rejected(status: 0, reason: "encode failed: \(error)")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .retryLater("no HTTP response") }
            switch http.statusCode {
            case 200...299:
                return .sent
            case 400, 404, 409, 413, 422:
                // The content was refused (bad keys, a constraint, too big).
                // Sending it again unchanged would fail again.
                let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return .rejected(status: http.statusCode, reason: body)
            default:
                // 401/403 (key), 408/429 (slow down), 5xx: try again later.
                return .retryLater("HTTP \(http.statusCode)")
            }
        } catch {
            return .retryLater("network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Device identifier

    /// Returns a string like "iPhone17,1" for the host device, or a
    /// simulator name when running under the simulator.  Useful for
    /// segmenting analytics by hardware.
    private static func deviceIdentifier() -> String {
        var sys = utsname()
        uname(&sys)
        let raw = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "?"
            }
        }
        return raw
    }
}

// ---------------------------------------------------------------------------
// PendingEvent — wire format for the events table.  Keys match the SQL
// schema column names (snake_case) so PostgREST can insert directly.
//
// EVERY event encodes the SAME eight keys.  `level` is written as null when
// there is none — never left out — because PostgREST refuses a bulk insert
// whose objects have different keys ("All object keys must match", HTTP 400).
// Text fields are cut to the table's limits so no event can break them.
// ---------------------------------------------------------------------------
struct PendingEvent: Encodable {
    /// Column limits on the events table (characters).
    static let maxEventName = 64
    static let maxVersion   = 32
    static let maxDevice    = 64

    let userId:      UUID
    let sessionId:   UUID
    let eventName:   String
    let properties:  [String: AnyEncodable]
    let level:       Int?
    let appVersion:  String
    let iosVersion:  String
    let deviceModel: String

    init(userId: UUID, sessionId: UUID, eventName: String,
         properties: [String: AnyEncodable], level: Int?,
         appVersion: String, iosVersion: String, deviceModel: String) {
        self.userId      = userId
        self.sessionId   = sessionId
        self.eventName   = Self.clip(eventName,   to: Self.maxEventName)
        self.properties  = properties
        self.level       = level
        self.appVersion  = Self.clip(appVersion,  to: Self.maxVersion)
        self.iosVersion  = Self.clip(iosVersion,  to: Self.maxVersion)
        self.deviceModel = Self.clip(deviceModel, to: Self.maxDevice)
    }

    /// Cut to at most `limit` characters as Postgres counts them (Unicode
    /// code points), never splitting one.
    static func clip(_ s: String, to limit: Int) -> String {
        guard s.unicodeScalars.count > limit else { return s }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.prefix(limit))
        return String(scalars)
    }

    enum CodingKeys: String, CodingKey {
        case userId       = "user_id"
        case sessionId    = "session_id"
        case eventName    = "event_name"
        case properties
        case level
        case appVersion   = "app_version"
        case iosVersion   = "ios_version"
        case deviceModel  = "device_model"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userId,      forKey: .userId)
        try c.encode(sessionId,   forKey: .sessionId)
        try c.encode(eventName,   forKey: .eventName)
        try c.encode(properties,  forKey: .properties)
        if let level { try c.encode(level, forKey: .level) } else { try c.encodeNil(forKey: .level) }
        try c.encode(appVersion,  forKey: .appVersion)
        try c.encode(iosVersion,  forKey: .iosVersion)
        try c.encode(deviceModel, forKey: .deviceModel)
    }

    /// The request body for a batch.
    static func encodeBatch(_ batch: [PendingEvent]) throws -> Data {
        try JSONEncoder().encode(batch)
    }
}

// ---------------------------------------------------------------------------
// AnyEncodable — type-erased Encodable wrapper so call sites can pass
// heterogeneous property dictionaries without ceremony:
//
//     AnalyticsClient.shared.track(
//         "level_complete",
//         properties: [
//             "stars":       .int(3),
//             "time":        .double(elapsed),
//             "coins_picked": .int(picked.count),
//         ]
//     )
//
// Conversion helpers (.int, .string, etc.) are below so call sites stay
// short.  Anything you can encode as JSON is fair game.
// ---------------------------------------------------------------------------
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        self._encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }

    static func int(_ v: Int)        -> AnyEncodable { .init(v) }
    /// A non-finite number (NaN or infinity) has no JSON form and would make
    /// the whole batch fail to encode, so it is sent as null.
    static func double(_ v: Double)  -> AnyEncodable {
        v.isFinite ? .init(v) : .init(Optional<Double>.none)
    }
    static func string(_ v: String)  -> AnyEncodable { .init(v) }
    static func bool(_ v: Bool)      -> AnyEncodable { .init(v) }
}
