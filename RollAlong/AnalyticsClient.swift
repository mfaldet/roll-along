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
// • During unit and UI test runs (RuntimeEnvironment.isRunningTests) nothing
//   is tracked, buffered or sent: test runs must never reach the live table.
//
// Server schema: see docs/supabase-schema.sql.  Single `events` table with
// columns user_id, session_id, event_name, properties, level, app_version,
// ios_version, device_model.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// RuntimeEnvironment — "is this process a test run?"
//
// One shared switch that every Supabase entry point checks so unit and UI
// test runs never send anything to the LIVE server (analytics, trophy sync,
// profile/social/leaderboard reads and writes, auth token calls, the
// delete-account function).  Test doubles injected by unit tests are not
// affected: only the real network clients consult it.
//
// Detected when ANY of these is true:
//   • Unit tests (the app is the test host): Xcode sets
//     XCTestConfigurationFilePath / XCTestBundlePath / XCTestSessionIdentifier
//     in the host process's environment, and the XCTest framework is loaded
//     into it (NSClassFromString("XCTestCase") != nil).
//   • UI tests (the app is a SEPARATE process that does NOT inherit XCTest's
//     environment): the runner launches it with the `--uitesting` argument
//     and the RA_NO_LIVE_SERVER=1 launch-environment key
//     (RollAlongUITests/SmokeTests.swift).
// Computed once per process; a normal launch from the Home Screen or from
// Xcode's Run (Cmd-R) has none of these.
// ---------------------------------------------------------------------------

enum RuntimeEnvironment {
    /// Launch-environment key UI tests set to switch the live server off.
    static let noLiveServerKey = "RA_NO_LIVE_SERVER"

    static let isRunningTests: Bool = detect(
        environment: ProcessInfo.processInfo.environment,
        arguments: ProcessInfo.processInfo.arguments,
        xcTestLoaded: NSClassFromString("XCTestCase") != nil
    )

    /// Pure detection rule (unit-testable without faking the process).
    static func detect(environment: [String: String],
                       arguments: [String],
                       xcTestLoaded: Bool) -> Bool {
        if xcTestLoaded { return true }
        let xcTestKeys = ["XCTestConfigurationFilePath",
                          "XCTestBundlePath",
                          "XCTestSessionIdentifier"]
        if xcTestKeys.contains(where: { environment[$0] != nil }) { return true }
        if environment[noLiveServerKey] == "1" { return true }
        if arguments.contains("--uitesting") { return true }
        return false
    }
}

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
    /// How many HTTP requests this client has started (guarded by `lock`).
    /// Read by the unit test proving a test run sends nothing.
    private var requestsStarted = 0

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
        // No timer at all during test runs (nothing is ever sent then).
        guard !RuntimeEnvironment.isRunningTests else { return }
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
        // Test runs never reach the live events table: drop at the door.
        guard !RuntimeEnvironment.isRunningTests else { return }
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
        guard !RuntimeEnvironment.isRunningTests else { return }
        lock.lock()
        guard !isFlushing, !buffer.isEmpty else { lock.unlock(); return }
        let batch = buffer
        buffer.removeAll(keepingCapacity: true)
        isFlushing = true
        lock.unlock()
        Task { [weak self] in
            await self?.sendInChunks(batch)
            self?.endFlushing()
        }
    }

    /// Number of HTTP requests started since launch (test observability).
    var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requestsStarted
    }

    /// Number of events waiting in the buffer (test observability).
    var bufferedEventCount: Int {
        lock.lock(); defer { lock.unlock() }
        return buffer.count
    }

    /// Counts one started request.  Synchronous (see `endFlushing`).
    private func noteRequestStarted() {
        lock.lock()
        requestsStarted += 1
        lock.unlock()
    }

    /// Releases the in-flight slot.  Synchronous: NSLock's lock()/unlock()
    /// are unavailable from async contexts (a warning in Swift 5 mode).
    private func endFlushing() {
        lock.lock()
        isFlushing = false
        lock.unlock()
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
    /// Most events in one POST, and most refused POSTs one flush may make
    /// while splitting.  Together they bound the requests a flush can make
    /// even if the server refuses every event (a missing column, say): past
    /// the budget the rest of the refused events are dropped with one log
    /// line instead of each being tried on its own.
    private static let maxEventsPerPost = 50
    private static let rejectedPostBudget = 24

    /// Send a flushed batch in chunks of `maxEventsPerPost`, in order.  If a
    /// chunk has to wait (network or server trouble), it and every later
    /// chunk go back to the buffer together, oldest first.
    private func sendInChunks(_ batch: [PendingEvent]) async {
        var budget = Self.rejectedPostBudget
        var start = 0
        while start < batch.count {
            let end = min(start + Self.maxEventsPerPost, batch.count)
            let waiting = await send(Array(batch[start..<end]), budget: &budget)
            if !waiting.isEmpty {
                requeue(waiting + Array(batch[end...]))
                return
            }
            start = end
        }
    }

    /// Deliver one chunk.  Returns the events that must wait for the next
    /// flush (network or server trouble), in their original order.
    private func send(_ batch: [PendingEvent], budget: inout Int) async -> [PendingEvent] {
        guard !batch.isEmpty else { return [] }
        switch await post(batch) {
        case .sent:
            return []
        case .retryLater(let why):
            debugLog("[Analytics] \(why), re-queued \(batch.count) events")
            return batch
        case .rejected(let status, let reason):
            budget -= 1
            if batch.count == 1 {
                debugLog("[Analytics] dropped event \(batch[0].eventName): HTTP \(status) \(reason)")
                return []
            }
            if budget <= 0 {
                debugLog("[Analytics] dropped \(batch.count) events after repeated rejections: HTTP \(status) \(reason)")
                return []
            }
            let mid = batch.count / 2
            let left = await send(Array(batch[..<mid]), budget: &budget)
            if !left.isEmpty {
                // The network went away part-way: keep the rest, in order.
                return left + Array(batch[mid...])
            }
            return await send(Array(batch[mid...]), budget: &budget)
        }
    }

    /// Prints in DEBUG builds only.  A function rather than `#if DEBUG` at
    /// the call site so the values bound for the message (`why`, `status`,
    /// `reason`) still count as used in Release builds.
    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }

    private func post(_ batch: [PendingEvent]) async -> PostOutcome {
        // Belt and braces: nothing reaches here during tests (track/flush
        // already refuse), but never let a test run touch the live server.
        if RuntimeEnvironment.isRunningTests {
            return .rejected(status: 0, reason: "live server disabled during tests")
        }
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
            noteRequestStarted()
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
