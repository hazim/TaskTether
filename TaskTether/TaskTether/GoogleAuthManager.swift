//
//  GoogleAuthManager.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//

import Foundation
import Combine
import OAuth2

class GoogleAuthManager: ObservableObject {

    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var errorMessage: String? = nil

    private var oauth2: OAuth2CodeGrant?

    init() {
        setupOAuth()
    }

    private func setupOAuth() {
        guard let credentialsURL = Bundle.main.url(forResource: "GoogleCredentials", withExtension: "json"),
              let credentialsData = try? Data(contentsOf: credentialsURL),
              let credentials = try? JSONSerialization.jsonObject(with: credentialsData) as? [String: Any],
              let installed = credentials["installed"] as? [String: Any],
              let clientId = installed["client_id"] as? String,
              let clientSecret = installed["client_secret"] as? String else {
            errorMessage = "Could not load Google credentials"
            return
        }

        oauth2 = OAuth2CodeGrant(settings: [
            "client_id": clientId,
            "client_secret": clientSecret,
            "authorize_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "scope": "https://www.googleapis.com/auth/tasks",
            "redirect_uris": ["urn:ietf:wg:oauth:2.0:oob"],
            "keychain": true,
            "keychain_account_for_client_credentials": "TaskTether"
        ] as OAuth2JSON)

        if oauth2?.hasUnexpiredAccessToken() == true {
            isAuthenticated = true
        }
    }

    func signIn() {
        guard let oauth2 = oauth2 else {
            errorMessage = "OAuth not configured"
            return
        }

        isAuthenticating = true
        errorMessage = nil

        oauth2.authorize { authParameters, error in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    self.isAuthenticated = false
                } else {
                    self.isAuthenticated = true
                }
            }
        }
    }

    func signOut() {
        oauth2?.forgetTokens()
        isAuthenticated = false
    }

    func getAccessToken() -> String? {
        return oauth2?.accessToken
    }
}
