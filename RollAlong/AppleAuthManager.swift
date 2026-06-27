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
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    /// Forget the local session.  (Apple has no programmatic sign-out; this
    /// just drops our Supabase token so the social layer goes quiet again.)
    func signOut() {
        SocialClient.shared.clearSession()
        Keychain.delete(Self.refreshTokenKey)
        isSignedIn = false
    }

    // MARK: - Supabase id_token exchange

    private func exchangeWithSupabase(idToken: String, rawNonce: String) async {
        do {
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
            try install(session)
            onSignedIn?()
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: - Session persistence (stay signed in across launches)

    /// Keychain key for the Supabase refresh token.
    private static let refreshTokenKey = "ra_supabase_refresh_token"

    /// Restore a signed-in session on launch by trading the persisted refresh
    /// token for a fresh access token.  No-op (stays signed out) when there's
    /// no stored token or it has expired / been revoked.  Call once at launch.
    func restoreSession() async {
        guard !isSignedIn, let token = Keychain.read(Self.refreshTokenKey) else { return }
        do {
            let session = try await refreshSession(refreshToken: token)
            try install(session)
            onSignedIn?()
        } catch {
            // Expired / revoked / invalid — drop it; the user can sign in again.
            Keychain.delete(Self.refreshTokenKey)
        }
    }

    /// Exchange a refresh token for a fresh Supabase session.  Supabase rotates
    /// the refresh token on each use, so `install` persists the new one.
    private func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        let url = URL(string: "\(Self.projectURL)/auth/v1/token?grant_type=refresh_token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.apiKey,        forHTTPHeaderField: "apikey")
        req.httpBody = try JSONEncoder().encode(RefreshGrant(refresh_token: refreshToken))

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            throw AuthError.message("Token refresh failed (\(status)).")
        }
        return try JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    /// Install a freshly-minted session: hand the access token to
    /// `SocialClient`, persist the (rotated) refresh token for next launch, and
    /// flip the published flags.
    private func install(_ session: SupabaseSession) throws {
        guard let userId = UUID(uuidString: session.user.id) else {
            throw AuthError.message("Auth server returned an unreadable user id.")
        }
        SocialClient.shared.setSession(accessToken: session.access_token, userId: userId)
        if let refresh = session.refresh_token {
            Keychain.save(refresh, for: Self.refreshTokenKey)
        }
        isSignedIn = true
        isWorking  = false
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
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData  = credential.identityToken,
            let idToken    = String(data: tokenData, encoding: .utf8)
        else {
            Task { @MainActor in self.fail("Apple did not return an identity token.") }
            return
        }
        Task { @MainActor in
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
        Task { @MainActor in
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
