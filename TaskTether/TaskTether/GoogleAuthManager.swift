
//
//  GoogleAuthManager.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//

import Foundation
import Combine
import AppKit
import CryptoKit

class GoogleAuthManager: ObservableObject {

    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var errorMessage: String? = nil

    private var clientId: String = ""
    private var clientSecret: String = ""
    private var accessToken: String? = nil
    private var refreshToken: String? = nil

    // Built per sign-in attempt from the ephemeral port the local listener
    // reports — see LocalHTTPServer.start. Also used by the token exchange,
    // which must send the exact redirect_uri the auth request used.
    private var redirectURI = ""
    private let scope = "https://www.googleapis.com/auth/tasks"
    private let server = LocalHTTPServer()

    // CSRF/PKCE material for the in-flight sign-in attempt only. Set at the
    // start of signIn(), consumed exactly once by handleCallback(), and
    // cleared immediately after — a captured or replayed redirect can't be
    // used to exchange a code a second time.
    private var pendingState: String?
    private var pendingCodeVerifier: String?

    init() {
        loadCredentials()
        loadTokensFromKeychain()
    }

    // MARK: - Setup

    private func loadCredentials() {
        guard let credentialsURL = Bundle.main.url(forResource: "GoogleCredentials", withExtension: "json"),
              let data = try? Data(contentsOf: credentialsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let installed = json["installed"] as? [String: Any],
              let id = installed["client_id"] as? String,
              let secret = installed["client_secret"] as? String else {
            errorMessage = String(localized: "error.credentials")
            return
        }
        clientId = id
        clientSecret = secret
    }

    // MARK: - Sign In

    func signIn() {
        isAuthenticating = true
        errorMessage = nil

        // Tear down any stale listener from a previous abandoned attempt
        // before starting a new one — otherwise the port stays locked.
        server.stop()

        let state = randomBase64URLToken()
        let verifier = randomBase64URLToken()
        pendingState = state
        pendingCodeVerifier = verifier
        let challenge = codeChallenge(for: verifier)

        // Start the local listener on an ephemeral port. The browser is only
        // opened AFTER the listener reports it is ready — opening it earlier
        // (as the old fixed-port code did) let the user approve access while
        // nothing of ours was listening, silently losing the auth code.
        server.start(
            onResult: { [weak self] result in
                DispatchQueue.main.async {
                    self?.handleCallback(result)
                }
            },
            onReady: { [weak self] port in
                DispatchQueue.main.async {
                    self?.openAuthURL(port: port, state: state, codeChallenge: challenge)
                }
            }
        )
    }

    private func openAuthURL(port: UInt16?, state: String, codeChallenge: String) {
        guard let port else {
            errorMessage = String(localized: "error.auth.port")
            isAuthenticating = false
            server.stop()
            clearPendingAuthState()
            return
        }

        // 127.0.0.1, not "localhost" — the listener binds the loopback
        // IPv4 address only, and some browsers resolve "localhost" to ::1
        // first, which would never reach it. Google's desktop OAuth clients
        // explicitly support (and recommend) a literal loopback IP here.
        redirectURI = "http://127.0.0.1:\(port)"

        // Build the Google auth URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authURL = components.url else {
            errorMessage = String(localized: "error.auth.url")
            isAuthenticating = false
            server.stop()
            clearPendingAuthState()
            return
        }

        // Open in the user's default browser
        NSWorkspace.shared.open(authURL)
    }

    // MARK: - Callback Handling

    /// Handles the local server's result: an access-denied redirect, a
    /// malformed/CSRF-suspect one (missing or non-matching `state`), or a
    /// valid code+state pair ready for token exchange.
    private func handleCallback(_ result: Result<AuthCallback, Error>) {
        switch result {
        case .success(let callback):
            guard let verifier = pendingCodeVerifier, stateMatches(callback.state) else {
                clearPendingAuthState()
                DispatchQueue.main.async {
                    self.isAuthenticating = false
                    self.errorMessage = String(localized: "error.auth.token")
                }
                return
            }
            clearPendingAuthState()
            exchangeCodeForTokens(code: callback.code, codeVerifier: verifier)
        case .failure:
            clearPendingAuthState()
            DispatchQueue.main.async {
                self.isAuthenticating = false
                self.errorMessage = String(localized: "error.auth.token")
            }
        }
    }

    private func stateMatches(_ received: String?) -> Bool {
        guard let expected = pendingState, let received, expected == received else { return false }
        return true
    }

    private func clearPendingAuthState() {
        pendingState = nil
        pendingCodeVerifier = nil
    }

    // MARK: - PKCE / State

    /// 32 random bytes, base64url-encoded (no padding) — 43 characters,
    /// suitable for both the OAuth `state` parameter and a PKCE
    /// `code_verifier` (RFC 7636 requires 43-128 characters).
    private func randomBase64URLToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes).base64URLEncodedString()
    }

    private func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, codeVerifier: String) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                DispatchQueue.main.async {
                    self.isAuthenticating = false
                    self.errorMessage = String(localized: "error.auth.token")
                }
                return
            }

            self.accessToken = accessToken
            self.refreshToken = json["refresh_token"] as? String
            self.saveTokensToKeychain()

            DispatchQueue.main.async {
                self.isAuthenticating = false
                self.isAuthenticated = true
            }
        }.resume()
    }

    // MARK: - Sign Out

    func signOut() {
        accessToken  = nil
        refreshToken = nil
        clearTokensFromKeychain()
        server.stop()
        clearPendingAuthState()

        DispatchQueue.main.async {
            self.isAuthenticated = false
            // Close any open Settings window so ContentView immediately
            // shows ConnectView — without this the user has no visual
            // confirmation that sign out happened.
            NSApp.windows
                .filter { $0.title.contains("Settings") || $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
                .forEach { $0.close() }
        }
    }

    // MARK: - Token Access

    func getAccessToken() -> String? {
        return accessToken
    }

    // MARK: - Token Refresh
    // Called by GoogleTasksManager when a request returns 401, and once at
    // launch. Only a definitive rejection from Google — invalid_grant, the
    // refresh token was revoked or expired — signs the user out. Everything
    // else (no network, DNS failure, a Google 5xx, a malformed reply) is
    // transient: the stored tokens are kept and the caller simply retries
    // on a later cycle. Wiping tokens on transient failures is what used
    // to force a fresh Google sign-in after an offline launch or a reinstall.

    func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let refresh = refreshToken else {
            // Nothing to refresh with. Show ConnectView but leave the
            // keychain alone — a denied keychain read is not a revocation.
            DispatchQueue.main.async { self.isAuthenticated = false }
            completion(false)
            return
        }
        URLSession.shared.dataTask(with: refreshRequest(refreshToken: refresh)) { data, _, _ in
            let outcome = Self.refreshOutcome(from: data)
            self.apply(outcome)
            completion(outcome.isRefreshed)
        }.resume()
    }

    private enum RefreshOutcome {
        case refreshed(String)
        case revoked
        case transient

        var isRefreshed: Bool {
            if case .refreshed = self { return true }
            return false
        }

        // For logging: never the token itself.
        var label: String {
            switch self {
            case .refreshed: return "refreshed"
            case .revoked:   return "revoked"
            case .transient: return "transient"
            }
        }
    }

    private func refreshRequest(refreshToken: String) -> URLRequest {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "client_id":     clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type":    "refresh_token"
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        return request
    }

    // Google answers a dead refresh token with HTTP 400 {"error":"invalid_grant"}.
    private static func refreshOutcome(from data: Data?) -> RefreshOutcome {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .transient
        }
        if let token = json["access_token"] as? String { return .refreshed(token) }
        if json["error"] as? String == "invalid_grant" { return .revoked }
        return .transient
    }

    private func apply(_ outcome: RefreshOutcome) {
        #if DEBUG
        print("GoogleAuthManager: refresh outcome — \(outcome.label)")
        #endif
        switch outcome {
        case .refreshed(let token):
            accessToken = token
            saveTokensToKeychain()
        case .revoked:
            DispatchQueue.main.async { self.signOut() }
        case .transient:
            break
        }
    }

    private var tokenEndpoint: URL {
        #if DEBUG
        // Test hook: `TaskTether.app/Contents/MacOS/TaskTether -TaskTetherTokenEndpoint http://127.0.0.1:1/`
        // makes every refresh fail as if offline, to exercise the transient path.
        if let override = UserDefaults.standard.string(forKey: "TaskTetherTokenEndpoint"),
           let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: "https://oauth2.googleapis.com/token")!
    }

    // MARK: - Keychain

    private func saveTokensToKeychain() {
        if let access = accessToken {
            saveToKeychain(key: "tasktether_access_token", value: access)
        }
        if let refresh = refreshToken {
            saveToKeychain(key: "tasktether_refresh_token", value: refresh)
        }
    }

    private func loadTokensFromKeychain() {
        // Migrate any tokens saved without kSecAttrService (pre-fix builds).
        // Reads the old-style entry, re-saves with service key, deletes the old one.
        // Safe to call on every launch — no-op if already migrated.
        migrateKeychainEntryIfNeeded(key: "tasktether_access_token")
        migrateKeychainEntryIfNeeded(key: "tasktether_refresh_token")

        #if DEBUG
        // Test hook: `-TaskTetherSeedRefreshToken <value>` writes throwaway
        // tokens into the keychain as this app (so later launches can read
        // them back without an ACL prompt). Used with -TaskTetherTokenEndpoint
        // to exercise the refresh paths without a real Google account.
        if let seed = UserDefaults.standard.string(forKey: "TaskTetherSeedRefreshToken") {
            accessToken  = "seeded-access"
            refreshToken = seed
            saveTokensToKeychain()
            print("GoogleAuthManager: seeded test tokens into keychain")
        }
        #endif

        accessToken  = loadFromKeychain(key: "tasktether_access_token")
        refreshToken = loadFromKeychain(key: "tasktether_refresh_token")

        // The refresh token is what makes the account "connected": the
        // access token it mints is short-lived and replaced on the first
        // 401. So the app starts signed in whenever a refresh token is on
        // hand, and the proactive refresh below can only downgrade that —
        // and only when Google itself says the token is dead. An offline
        // launch stays connected and syncs once the network is back.
        #if DEBUG
        print("GoogleAuthManager: keychain load — access:\(accessToken != nil) refresh:\(refreshToken != nil)")
        #endif
        guard refreshToken != nil else { return }
        isAuthenticated = true
        refreshAccessToken { _ in }
    }

    private func clearTokensFromKeychain() {
        deleteFromKeychain(key: "tasktether_access_token")
        deleteFromKeychain(key: "tasktether_refresh_token")
    }

    // Reads a token stored without kSecAttrService (pre-fix builds),
    // re-saves it with the service key, then deletes the legacy entry.
    private func migrateKeychainEntryIfNeeded(key: String) {
        // Once the service-keyed entry exists there is nothing to migrate.
        // This guard is load-bearing: the legacy query below matches on
        // account name alone, so without it the current entry is "found",
        // re-saved, and then deleted by the cleanup — wiping the tokens on
        // every launch after the first sign-in.
        guard loadFromKeychain(key: key) == nil else { return }

        // Try reading the legacy entry (no service key)
        let legacyQuery: [String: Any] = [
            kSecClass as String:      kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return }

        // Delete the legacy entry *before* re-saving: the query matches on
        // account alone, so done afterwards it would take the new entry too.
        // The guard above ensures only legacy entries exist at this point.
        SecItemDelete(legacyQuery as CFDictionary)

        // Re-save with service key
        saveToKeychain(key: key, value: value)

        #if DEBUG
        print("GoogleAuthManager: migrated keychain entry '\(key)' ✅")
        #endif
    }

    private func saveToKeychain(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let search: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: "com.hazim.TaskTether",
            kSecAttrAccount as String: key
        ]
        let query = search.merging([kSecValueData as String: data]) { $1 }
        SecItemDelete(search as CFDictionary)
        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // The delete above was refused (keychain ACL) — overwrite instead.
            status = SecItemUpdate(search as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        #if DEBUG
        if status != errSecSuccess {
            print("GoogleAuthManager: keychain save failed for '\(key)' — status \(status)")
        }
        #endif
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: "com.hazim.TaskTether",
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        #if DEBUG
        if status != errSecSuccess && status != errSecItemNotFound {
            print("GoogleAuthManager: keychain read failed for '\(key)' — status \(status)")
        }
        #endif
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: "com.hazim.TaskTether",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private extension Data {
    /// RFC 4648 base64url, unpadded — used for the OAuth `state` value and
    /// PKCE `code_verifier`/`code_challenge`.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

