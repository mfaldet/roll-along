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
// • Best-effort: failed POSTs are silently retried on next flush.  If the
//   buffer overflows (1000 events) the oldest get dropped to bound memory.
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
        buffer.append(event)
        if buffer.count > Self.bufferCap {
            buffer.removeFirst(buffer.count - Self.bufferCap)
        }
        if buffer.count >= Self.flushThreshold {
            flush()
        }
    }

    /// Begin a fresh session — call when the app cold-starts or comes back
    /// from background after a long idle.
    func startNewSession() {
        sessionId = UUID()
    }

    /// Force a flush (e.g. when the app moves to background).
    func flush() {
        guard !isFlushing, !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll(keepingCapacity: true)
        isFlushing = true
        Task { [weak self] in
            await self?.post(batch: batch)
            self?.isFlushing = false
        }
    }

    // MARK: - Networking

    private func post(batch: [PendingEvent]) async {
        guard let url = URL(string: "\(Self.projectURL)/rest/v1/events") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",     forHTTPHeaderField: "Content-Type")
        req.setValue(Self.anonKey,           forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Self.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("return=minimal",       forHTTPHeaderField: "Prefer")

        do {
            req.httpBody = try JSONEncoder().encode(batch)
        } catch {
            // Encoding failed — drop the batch silently (best-effort).
            #if DEBUG
            print("[Analytics] encode failed: \(error)")
            #endif
            return
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                // Re-queue for next flush — most likely transient.  Bounded
                // by bufferCap so we don't grow unbounded.
                buffer.append(contentsOf: batch)
                #if DEBUG
                print("[Analytics] HTTP \(http.statusCode), re-queued \(batch.count) events")
                #endif
            }
        } catch {
            buffer.append(contentsOf: batch)
            #if DEBUG
            print("[Analytics] network error: \(error.localizedDescription)")
            #endif
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
// ---------------------------------------------------------------------------
private struct PendingEvent: Encodable {
    let userId:      UUID
    let sessionId:   UUID
    let eventName:   String
    let properties:  [String: AnyEncodable]
    let level:       Int?
    let appVersion:  String
    let iosVersion:  String
    let deviceModel: String

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
    static func double(_ v: Double)  -> AnyEncodable { .init(v) }
    static func string(_ v: String)  -> AnyEncodable { .init(v) }
    static func bool(_ v: Bool)      -> AnyEncodable { .init(v) }
}
