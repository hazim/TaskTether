//
//  TaskTetherApp.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//

import SwiftUI

@main
struct TaskTetherApp: App {
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        MenuBarExtra("TaskTether", systemImage: "arrow.triangle.2.circlepath") {
            ContentView()
                .environmentObject(themeManager)
        }
        .menuBarExtraStyle(.window)
    }
}
