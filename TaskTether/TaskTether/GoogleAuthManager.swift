
//
//  GoogleAuthManager.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//

import Foundation
import Combine
import AppKit

class GoogleAuthManager: ObservableObject {

    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var errorMessage: String? = nil

    private var clientId: String = ""
    private var clientSecret: String = ""
    private var accessToken: String? = nil
    private var refreshToken: String? = nil

    private let redirectURI = "http://localhost:8080"
    private let scope = "https://www.googleapis.com/auth/tasks"
    private let server = LocalHTTPServer()

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
            errorMessage = "Could not load credentials"
            return
        }
        clientId = id
        clientSecret = secret
    }

    // MARK: - Sign In

    func signIn() {
        isAuthenticating = true
        errorMessage = nil

        // Start local server to catch the redirect
        server.start { [weak self] code in
            self?.exchangeCodeForTokens(code: code)
        }

        // Build the Google auth URL
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            errorMessage = "Could not build auth URL"
            isAuthenticating = false
            server.stop()
            return
        }

        // Open in the user's default browser
        NSWorkspace.shared.open(authURL)
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                DispatchQueue.main.async {
                    self.isAuthenticating = false
                    self.errorMessage = "Token exchange failed"
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
        accessToken = nil
        refreshToken = nil
        clearTokensFromKeychain()
        isAuthenticated = false
    }

    func getAccessToken() -> String? {
        return accessToken
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
        accessToken = loadFromKeychain(key: "tasktether_access_token")
        refreshToken = loadFromKeychain(key: "tasktether_refresh_token")
        if accessToken != nil {
            isAuthenticated = true
            print("GoogleAuthManager: loaded token from keychain ✅")
        } else {
            print("GoogleAuthManager: no token in keychain ❌")
        }
    }

    private func clearTokensFromKeychain() {
        deleteFromKeychain(key: "tasktether_access_token")
        deleteFromKeychain(key: "tasktether_refresh_token")
    }

    private func saveToKeychain(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
