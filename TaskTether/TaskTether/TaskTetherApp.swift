//
//  TaskTetherApp.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//  Updated: 13/03/2026 · 18:10
//

import SwiftUI

@main
struct TaskTetherApp: App {

    @StateObject private var themeManager:       ThemeManager
    @StateObject private var authManager:         GoogleAuthManager
    @StateObject private var remindersManager:    RemindersManager
    @StateObject private var googleTasksManager:  GoogleTasksManager
    @StateObject private var syncEngine:          SyncEngine

    init() {
        let theme    = ThemeManager()
        let auth     = GoogleAuthManager()
        let remind   = RemindersManager()
        let google   = GoogleTasksManager(authManager: auth)
        let engine   = SyncEngine(
            remindersManager:   remind,
            googleTasksManager: google,
            authManager:        auth,
            themeManager:       theme
        )

        _themeManager      = StateObject(wrappedValue: theme)
        _authManager       = StateObject(wrappedValue: auth)
        _remindersManager  = StateObject(wrappedValue: remind)
        _googleTasksManager = StateObject(wrappedValue: google)
        _syncEngine        = StateObject(wrappedValue: engine)
    }

    var body: some Scene {

        // MARK: Menu Bar Popover
        MenuBarExtra("TaskTether", systemImage: "arrow.triangle.2.circlepath") {
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(authManager)
                .environmentObject(remindersManager)
                .environmentObject(googleTasksManager)
                .environmentObject(syncEngine)
        }
        .menuBarExtraStyle(.window)

        // MARK: Settings Window
        Settings {
            SettingsView()
                .environmentObject(themeManager)
                .environmentObject(authManager)
        }
    }
}
