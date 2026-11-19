import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

// ===========================================================================
// AppleAuthManager — Sign in with Apple → Supabase Auth → SocialClient session.
//
// The identity bridge for Roll Along's social layer.  Flow:
//
//   1. Player taps "Sign in with Apple".  We launch the native
//      ASAuthorizationController with a one-time, SHA256-hashed nonce.
//   2. Apple returns an `identityToken` (a signed JWT) that embeds the
//      hashed nonce and the player's stable Apple user id.
//   3. We POST that token + the *raw* nonce to Supabase's id_token grant
//      (`/auth/v1/token?grant_type=id_token`).  Supabase verifies Apple's
//      signature, re-hashes our nonce to confirm it matches, and mints a
//      Supabase access token (role=authenticated) + a Supabase user id.
//   4. We hand both to `SocialClient.setSession(...)`, which from then on
//      attaches `Authorization: Bearer <token>` to every request so
//      Postgres RLS scopes writes to this player's own rows.
//
// SAFE BY CONSTRUCTION: self-contained, additive.  Nothing calls this until
// a UI surface invokes `startSignIn`.  Until then the social layer stays in
// its signed-out state (every SocialClient method throws `.notSignedIn`).
//
// NOTE: the "Sign in with Apple" entitlement requires a *paid* Apple
// Developer Program membership.  This code compiles on a free team but the
// system sheet will only present once the capability is added to the target.
// ===========================================================================

@MainActor
final class AppleAuthManager: NSObject, ObservableObject {
    static let shared = AppleAuthManager()
    // `nonisolated` so the static `shared` initializer (a nonisolated context)
    // can build it without a main-actor hop.  The body touches no isolated
    // state — it just chains to NSObject.init — so this is safe.
    private nonisolated override init() { super.init() }

    // MARK: - Published state (drive the sign-in button / UI)

    /// True once a Supabase session is installed on `SocialClient`.
    @Published private(set) var isSignedIn: Bool = false
    /// In-flight indicator so the button can disable + spin.
    @Published private(set) var isWorking: Bool = false
    /// Human-readable last error, for surfacing a toast/label.  Cleared on
    /// each new attempt.
    @Published private(set) var lastError: String?
    /// True when the saved sign-in could not be renewed (the server refused
    /// the refresh token).  Social screens then show "Please sign in again"
    /// with a sign-in button instead of a server error.  Cleared on sign-in.
    @Published private(set) var sessionExpired: Bool = false

    // MARK: - Config (mirrors SocialClient; both are client-safe values)

    private static let projectURL = "https://mhwpcwauzvmtmuphtajs.supabase.co"
    private static let apiKey = "sb_publishable_A1RRz_2m9qDAWikrVlyfnQ_M-YgOSaR"

    // MARK: - Per-attempt state

    /// Raw (un-hashed) nonce for the current attempt.  Apple embeds the
    /// hash in the returned token; Supabase re-hashes this raw value to
    /// verify, so we must keep and forward the raw form.
    private var currentNonce: String?

    /// Optional hook fired after a successful sign-in + session install,
    /// e.g. to upsert the player's profile with current game stats.  Set by
    /// the caller before invoking `startSignIn`.
    var onSignedIn: (() -> Void)?

    // MARK: - Public entry points

    /// Begin the native Sign in with Apple flow.  Results land in
    /// `isSignedIn` / `lastError`; `onSignedIn` fires on success.
    func startSignIn() {
        lastError = nil
        isWorking = true

        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request  = provider.createRequest()
        // Ask Apple for NOTHING beyond the sign-in itself: the game never uses
        // a real name or an email address (App Review Guideline 5.1.1(iii),
        // data minimization).  The public name is the preset nickname.
        request.requestedScopes = []
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    /// Forget the local session.  (Apple has no programmatic sign-out; this
    /// just drops our Supabase token so the social layer goes quiet again.)
    func signOut() {
        renewalTask?.cancel()
        renewalTask = nil
        SocialClient.shared.clearSession()
        KeychainSessionStore.shared.clear()
        Task { await SessionManager.shared.clear() }
        isSignedIn = false
        sessionExpired = false
    }

    // MARK: - Fresh authorization code (account deletion)

    /// Outcome of asking Apple for a one-time authorization code.
    enum AuthorizationCodeResult {
        case code(String)   // Apple returned a fresh code
        case cancelled      // the player dismissed Apple's sheet
        case unavailable    // Apple returned no code / the request failed
    }

    private var codeContinuation: CheckedContinuation<AuthorizationCodeResult, Never>?

    /// Ask Apple for a fresh, single-use authorization code by re-confirming
    /// Sign in with Apple.  Used only by Delete Account: the server trades the
    /// code for an Apple token and revokes it (Apple's account-deletion
    /// guidance for apps that use Sign in with Apple), so the app also
    /// disappears from the player's "Sign in with Apple" list.
    func requestAuthorizationCode() async -> AuthorizationCodeResult {
        guard codeContinuation == nil else { return .unavailable }
        return await withCheckedContinuation { continuation in
            codeContinuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = []
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    /// Finish a pending `requestAuthorizationCode()`.  Returns true when a
    /// request was pending (so the normal sign-in handling must be skipped).
    private func finishCodeRequest(_ result: AuthorizationCodeResult) -> Bool {
        guard let continuation = codeContinuation else { return false }
        codeContinuation = nil
        continuation.resume(returning: result)
        return true
    }

    // MARK: - Supabase id_token exchange

    private func exchangeWithSupabase(idToken: String, rawNonce: String) async {
        do {
            if RuntimeEnvironment.isRunningTests {
                throw AuthError.message("Sign-in is disabled during test runs.")
            }
            let url = URL(string: "\(Self.projectURL)/auth/v1/token?grant_type=id_token")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(Self.apiKey,        forHTTPHeaderField: "apikey")

            let body = IdTokenGrant(provider: "apple", id_token: idToken, nonce: rawNonce)
            req.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw AuthError.message("No HTTP response from auth server.")
            }
            guard (200...299).contains(http.statusCode) else {
                let detail = String(data: data, encoding: .utf8) ?? ""
                throw AuthError.message("Auth exchange failed (\(http.statusCode)). \(detail)")
            }

            let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
            try await install(session)
            onSignedIn?()
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: - Session persistence and renewal
    //
    // The access token lives one hour.  `SessionManager` (below) holds it,
    // renews it with the saved refresh token, and is the ONLY place any
    // signed-in request gets a token from.  This class drives renewal:
    //   • at launch (`restoreSession`),
    //   • when the app comes back to the foreground (`renewIfNeeded`),
    //   • on a timer five minutes before the token expires,
    // and every signed-in request also renews once and retries once if the
    // server says the token has expired (`SessionManager.perform`).

    /// Fires `renewIfNeeded` shortly before the current token expires.
    private var renewalTask: Task<Void, Never>?
    private var observingSession = false

    /// Hear about renewals (to re-arm the timer) and refused refresh tokens
    /// (to show "Please sign in again") from any caller of the session.
    private func ensureSessionObserver() async {
        guard !observingSession else { return }
        observingSession = true
        await SessionManager.shared.setObserver { event in
            Task { @MainActor in AppleAuthManager.shared.handle(event) }
        }
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .renewed(let expiresAt, let userId):
            SocialClient.shared.setSession(userId: userId)
            isSignedIn = true
            sessionExpired = false
            scheduleRenewal(expiresAt: expiresAt)
        case .needsSignIn:
            renewalTask?.cancel()
            renewalTask = nil
            SocialClient.shared.clearSession()
            isSignedIn = false
            sessionExpired = true
        }
    }

    private func scheduleRenewal(expiresAt: Date) {
        renewalTask?.cancel()
        let delay = max(30, expiresAt.timeIntervalSinceNow - SessionManager.refreshLeeway)
        renewalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.renewIfNeeded()
        }
    }

    /// Restore a signed-in session on launch from the saved refresh token.
    /// A refused refresh token shows "Please sign in again"; a network failure
    /// keeps the saved sign-in so the next attempt can renew it.
    func restoreSession() async {
        // Test runs never call the live auth server and never touch the
        // player's saved sign-in (tests run inside the app on the same phone).
        guard !RuntimeEnvironment.isRunningTests else { return }
        await ensureSessionObserver()
        if isSignedIn { await renewIfNeeded(); return }
        let store = KeychainSessionStore.shared
        guard store.refreshToken != nil else { return }
        // Signed in from the saved account straight away (requests renew the
        // token themselves), so an offline launch isn't shown as signed out.
        if let saved = store.userId.flatMap(UUID.init(uuidString:)) {
            SocialClient.shared.setSession(userId: saved)
            isSignedIn = true
        }
        do {
            // Posts `.renewed`.  Deliberately no `onSignedIn`: a restore must
            // never overwrite the server profile with this device's stats.
            _ = try await SessionManager.shared.refresh()
        } catch {
            // `.needsSignIn` is handled by the observer; anything else (no
            // connection, a server hiccup) keeps the saved sign-in.
        }
    }

    /// Renew the token if it is missing or expires within five minutes.
    /// Called on foreground and by the expiry timer.
    func renewIfNeeded() async {
        guard !RuntimeEnvironment.isRunningTests else { return }
        await ensureSessionObserver()
        guard isSignedIn else {
            if !sessionExpired { await restoreSession() }
            return
        }
        _ = try? await SessionManager.shared.validAccessToken()
    }

    /// Install a freshly minted session from the Apple sign-in exchange.
    private func install(_ session: SupabaseSession) async throws {
        guard let userId = UUID(uuidString: session.user.id) else {
            throw AuthError.message("Auth server returned an unreadable user id.")
        }
        await ensureSessionObserver()
        let expiresAt = await SessionManager.shared.install(session, userId: userId)
        SocialClient.shared.setSession(userId: userId)
        isSignedIn = true
        isWorking  = false
        sessionExpired = false
        scheduleRenewal(expiresAt: expiresAt)
    }

    private func fail(_ message: String) {
        lastError = message
        isWorking = false
        isSignedIn = SocialClient.shared.isSignedIn
    }

    // MARK: - Nonce helpers (Apple-recommended pattern)

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                // Fallback — still random enough for a one-time nonce.
                randoms = (0..<16).map { _ in UInt8.random(in: 0...255) }
            }
            for random in randoms where remaining > 0 {
                if Int(random) < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

// ===========================================================================
// Delegate + presentation
// ===========================================================================
extension AppleAuthManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential
        // One-time authorization code — only used by the Delete Account flow.
        let authorizationCode: String? = appleCredential?.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
        let idToken: String? = appleCredential?.identityToken
            .flatMap { String(data: $0, encoding: .utf8) }
        Task { @MainActor in
            // A pending Delete Account code request takes this result.
            let codeResult: AuthorizationCodeResult =
                authorizationCode.map { .code($0) } ?? .unavailable
            if self.finishCodeRequest(codeResult) { return }

            guard let idToken else {
                self.fail("Apple did not return an identity token.")
                return
            }
            guard let nonce = self.currentNonce else {
                self.fail("Missing sign-in nonce; please try again.")
                return
            }
            await self.exchangeWithSupabase(idToken: idToken, rawNonce: nonce)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let wasCancelled = (error as? ASAuthorizationError)?.code == .canceled
        Task { @MainActor in
            // A pending Delete Account code request takes this result.
            if self.finishCodeRequest(wasCancelled ? .cancelled : .unavailable) { return }
            // User cancellation isn't a real error — keep it quiet.
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                self.isWorking = false
                return
            }
            self.fail(error.localizedDescription)
        }
    }
}

extension AppleAuthManager: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        // UIKit always calls this back on the main thread, so it's safe to
        // assert main-actor isolation here.  Doing so lets us read the
        // main-actor-isolated UIApplication scene/window APIs without warnings.
        MainActor.assumeIsolated {
            // Find the active foreground window to anchor the system sheet.
            let scenes = UIApplication.shared.connectedScenes
            let window = scenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            return window ?? ASPresentationAnchor()
        }
    }
}

// ===========================================================================
// Wire models
// ===========================================================================
private struct IdTokenGrant: Encodable {
    let provider: String
    let id_token: String
    let nonce: String
}

private struct RefreshGrant: Encodable {
    let refresh_token: String
}

private struct SupabaseSession: Decodable {
    let access_token: String
    let refresh_token: String?
    /// Seconds the access token lives (Supabase: 3600).
    let expires_in: Double?
    /// Unix time the access token expires.
    let expires_at: Double?
    let user: SupabaseUser
}

private struct SupabaseUser: Decodable {
    let id: String
}

private enum AuthError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

// ===========================================================================
// Keychain — minimal secure string store for the Supabase refresh token.
// Kept here (not a new file) to avoid touching the Xcode project structure.
// ===========================================================================
private enum Keychain {
    static func save(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String]      = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// ===========================================================================
// Saved sign-in: the Supabase refresh token and the account id, in the
// Keychain.  A protocol so tests can use an in-memory store.
// ===========================================================================
protocol SessionTokenStore: AnyObject, Sendable {
    var refreshToken: String? { get set }
    var userId: String? { get set }
}

extension SessionTokenStore {
    func clear() { refreshToken = nil; userId = nil }
}

final class KeychainSessionStore: SessionTokenStore, @unchecked Sendable {
    static let shared = KeychainSessionStore()
    /// Same key as earlier builds, so an existing saved sign-in still restores.
    private static let refreshKey = "ra_supabase_refresh_token"
    private static let userKey    = "ra_supabase_user_id"

    var refreshToken: String? {
        get { Keychain.read(Self.refreshKey) }
        set {
            if let newValue { Keychain.save(newValue, for: Self.refreshKey) }
            else { Keychain.delete(Self.refreshKey) }
        }
    }
    var userId: String? {
        get { Keychain.read(Self.userKey) }
        set {
            if let newValue { Keychain.save(newValue, for: Self.userKey) }
            else { Keychain.delete(Self.userKey) }
        }
    }
}

/// What can go wrong getting a usable sign-in.
enum SessionError: Error, Equatable {
    /// No saved sign-in at all.
    case notSignedIn
    /// The server refused the saved refresh token: the player must sign in again.
    case needsSignIn
    /// The auth server could not be reached (no connection, timeout).
    case unreachable
    /// The auth server answered with an unexpected status (kept signed in).
    case refreshFailed(status: Int)
    /// Test runs never touch the live server.
    case liveServerDisabled
}

enum SessionEvent: Sendable {
    case renewed(expiresAt: Date, userId: UUID)
    case needsSignIn
}

/// Sends a request: `URLSession.shared` in the app, a fake in unit tests.
typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

// ===========================================================================
// SessionManager — the one source of truth for the signed-in token.
//
// Every signed-in request (SocialClient, trophy sync, feedback, account
// deletion) gets its token here:
//   • `validAccessToken()` renews first when the token expires within five
//     minutes (or is missing after a relaunch);
//   • `perform(_:)` sends a request and, if the server says the token is
//     expired or invalid (401, PGRST301/PGRST303, "JWT expired"), renews once
//     and retries once — never more;
//   • renewals are single-flight: concurrent callers share one refresh, so a
//     rotated refresh token is never used twice;
//   • the rotated refresh token is saved immediately after every renewal.
// A refused refresh token (400/401/403) clears the saved sign-in and posts
// `.needsSignIn`; a network failure keeps it and throws `.unreachable`.
// ===========================================================================
actor SessionManager {
    static let shared = SessionManager(
        transport: { try await URLSession.shared.data(for: $0) },
        store: KeychainSessionStore.shared,
        liveAllowed: !RuntimeEnvironment.isRunningTests)

    /// Renew this long before the token expires.
    static let refreshLeeway: TimeInterval = 5 * 60

    private static let projectURL = "https://mhwpcwauzvmtmuphtajs.supabase.co"
    private static let apiKey = "sb_publishable_A1RRz_2m9qDAWikrVlyfnQ_M-YgOSaR"

    private struct Current { let accessToken: String; let expiresAt: Date; let userId: UUID }

    private let transport: HTTPTransport
    private let store: SessionTokenStore
    private let now: @Sendable () -> Date
    let liveAllowed: Bool

    private var current: Current?
    private var inFlight: Task<String, Error>?
    private var observer: (@Sendable (SessionEvent) -> Void)?
    /// Bumped by `clear()`, so a renewal still in flight at sign-out cannot
    /// reinstall the session it started with.
    private var generation = 0

    init(transport: @escaping HTTPTransport,
         store: SessionTokenStore,
         now: @escaping @Sendable () -> Date = { Date() },
         liveAllowed: Bool) {
        self.transport = transport
        self.store = store
        self.now = now
        self.liveAllowed = liveAllowed
    }

    func setObserver(_ observer: @escaping @Sendable (SessionEvent) -> Void) {
        self.observer = observer
    }

    var currentUserId: UUID? { current?.userId }
    var currentExpiry: Date? { current?.expiresAt }

    /// Forget the session (sign-out).  Clears the saved sign-in too.
    func clear() {
        generation += 1
        current = nil
        store.clear()
    }

    /// Install a session from the Apple sign-in exchange.  Returns its expiry.
    @discardableResult
    fileprivate func install(_ session: SupabaseSession, userId: UUID) -> Date {
        let expiresAt = Self.expiry(of: session, now: now())
        current = Current(accessToken: session.access_token, expiresAt: expiresAt, userId: userId)
        if let refresh = session.refresh_token { store.refreshToken = refresh }
        store.userId = userId.uuidString
        return expiresAt
    }

    /// Test seam: install a session from raw values.
    func install(accessToken: String, refreshToken: String?, expiresAt: Date, userId: UUID) {
        current = Current(accessToken: accessToken, expiresAt: expiresAt, userId: userId)
        if let refreshToken { store.refreshToken = refreshToken }
        store.userId = userId.uuidString
    }

    /// A token good for at least five more minutes, renewing first if needed.
    func validAccessToken() async throws -> String {
        if let c = current, c.expiresAt.timeIntervalSince(now()) > Self.refreshLeeway {
            return c.accessToken
        }
        guard current != nil || store.refreshToken != nil else { throw SessionError.notSignedIn }
        return try await refresh()
    }

    /// Renew because the server refused `rejected`.  If another request has
    /// already renewed since, the newer token is returned without a second
    /// refresh.
    func forceRefresh(rejecting rejected: String) async throws -> String {
        if let c = current, c.accessToken != rejected { return c.accessToken }
        return try await refresh()
    }

    /// Renew now.  Concurrent callers share one refresh.
    func refresh() async throws -> String {
        if let running = inFlight { return try await running.value }
        let task = Task { try await self.performRefresh() }
        inFlight = task
        do {
            let token = try await task.value
            inFlight = nil
            return token
        } catch {
            inFlight = nil
            throw error
        }
    }

    private func performRefresh() async throws -> String {
        guard liveAllowed else { throw SessionError.liveServerDisabled }
        guard let refreshToken = store.refreshToken else {
            if current != nil { expire(); throw SessionError.needsSignIn }
            throw SessionError.notSignedIn
        }
        guard let url = URL(string: "\(Self.projectURL)/auth/v1/token?grant_type=refresh_token") else {
            throw SessionError.refreshFailed(status: -1)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.apiKey,        forHTTPHeaderField: "apikey")
        req.httpBody = try JSONEncoder().encode(RefreshGrant(refresh_token: refreshToken))
        let startedGeneration = generation

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(req)
        } catch {
            // No answer at all: keep the saved sign-in and try again later.
            throw SessionError.unreachable
        }
        // Signed out while the renewal was in flight: drop its answer.
        guard startedGeneration == generation else { throw SessionError.notSignedIn }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        switch status {
        case 200...299:
            let session: SupabaseSession
            do { session = try JSONDecoder().decode(SupabaseSession.self, from: data) }
            catch { throw SessionError.refreshFailed(status: status) }
            guard let userId = UUID(uuidString: session.user.id) else {
                throw SessionError.refreshFailed(status: status)
            }
            let expiresAt = install(session, userId: userId)
            observer?(.renewed(expiresAt: expiresAt, userId: userId))
            return session.access_token
        case 400, 401, 403:
            // invalid_grant: the refresh token was revoked, already used, or
            // not found.  Only a new sign-in can fix this.
            expire()
            throw SessionError.needsSignIn
        default:
            throw SessionError.refreshFailed(status: status)
        }
    }

    private func expire() {
        current = nil
        store.clear()
        observer?(.needsSignIn)
    }

    // MARK: Signed-in requests

    /// Send one signed-in request.  `make` builds it with the given token.
    /// On an expired or invalid token: renew once and retry once.
    nonisolated func perform(_ make: (String) throws -> URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard liveAllowed else { throw SessionError.liveServerDisabled }
        let first = try await validAccessToken()
        let (data, http) = try await send(try make(first))
        guard Self.isRejectedSignIn(status: http.statusCode, body: data) else { return (data, http) }
        let second = try await forceRefresh(rejecting: first)
        return try await send(try make(second))
    }

    private nonisolated func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await transport(req)
        guard let http = response as? HTTPURLResponse else {
            throw SocialError.http(status: -1, body: "no HTTP response")
        }
        return (data, http)
    }

    /// True when the server refused the request because of the sign-in token.
    static func isRejectedSignIn(status: Int, body: Data) -> Bool {
        if (200...299).contains(status) { return false }
        if status == 401 { return true }
        let text = String(decoding: body.prefix(2048), as: UTF8.self).lowercased()
        return text.contains("jwt expired") || text.contains("pgrst301")
            || text.contains("pgrst303") || text.contains("invalid jwt")
            || text.contains("bad_jwt")
    }

    // MARK: Expiry

    private static func expiry(of session: SupabaseSession, now: Date) -> Date {
        if let at = session.expires_at { return Date(timeIntervalSince1970: at) }
        if let inSeconds = session.expires_in { return now.addingTimeInterval(inSeconds) }
        if let exp = jwtExpiry(session.access_token) { return exp }
        return now.addingTimeInterval(3600)
    }

    /// The `exp` claim of a JWT, if readable.
    static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = obj["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
