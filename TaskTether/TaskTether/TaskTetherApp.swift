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

    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {

        // MARK: Menu Bar Popover
        MenuBarExtra("TaskTether", systemImage: "arrow.triangle.2.circlepath") {
            ContentView()
                .environmentObject(themeManager)
        }
        .menuBarExtraStyle(.window)

        // MARK: Settings Window
        // Opens via gear icon in the popover OR Cmd+, (standard macOS HIG).
        // SettingsView is injected with the same ThemeManager so changes are live.
        Settings {
            SettingsView()
                .environmentObject(themeManager)
        }
    }
}
