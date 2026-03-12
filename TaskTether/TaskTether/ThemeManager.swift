//
//  ThemeManager.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//

import SwiftUI
import Combine

// MARK: - Theme Model
// This is the Swift representation of one theme object in Themes.json.
// Every property maps directly to a key in the JSON file.

struct ThemeColors: Codable {
    let backgroundPrimary:   String
    let backgroundSecondary: String
    let surface:             String
    let surface2:            String
    let border:              String
    let accent:              String
    let accentForeground:    String
    let textPrimary:         String
    let textSecondary:       String
    let textTertiary:        String
    let success:             String
    let warning:             String
    let danger:              String
    let sparkline:           String
}

struct Theme: Codable, Identifiable {
    let id:         String
    let name:       String
    let appearance: String  // "light" or "dark"
    let colors:     ThemeColors
}

// A wrapper that matches the top-level { "themes": [...] } structure in Themes.json
private struct ThemesFile: Codable {
    let themes: [Theme]
}

// MARK: - Color Extension
// Converts a hex string like "#B07D4A" into a SwiftUI Color.
// Used by every view that reads a colour from the active theme.

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - ThemeManager
// This is the single source of truth for theming across the entire app.
// It is injected at the top level in TaskTetherApp.swift and accessed in
// any view via @EnvironmentObject var themeManager: ThemeManager.

class ThemeManager: ObservableObject {

    // The currently active theme. When this changes, every view using it re-renders.
    @Published private(set) var activeTheme: Theme

    // All themes loaded from Themes.json. Used to populate the Settings picker.
    @Published private(set) var availableThemes: [Theme] = []

    // The UserDefaults key we use to remember the user's last chosen theme.
    private let defaultsKey = "tasktether_active_theme_id"

    // The fallback theme ID if nothing is stored in UserDefaults yet,
    // or if the stored ID no longer exists (e.g. a theme was removed).
    private let fallbackThemeId = "sand"

    init() {
        // Load all themes from the bundled Themes.json file.
        let loaded = ThemeManager.loadThemes()
        self.availableThemes = loaded

        // Restore the last selected theme from UserDefaults.
        // If nothing is saved yet, or the saved ID doesn't match any loaded theme,
        // fall back to Sand.
        let savedId = UserDefaults.standard.string(forKey: "tasktether_active_theme_id")
        let resolved = loaded.first(where: { $0.id == savedId })
                    ?? loaded.first(where: { $0.id == "sand" })
                    ?? loaded[0]

        self.activeTheme = resolved
    }

    // MARK: - Set Theme
    // Call this from the Settings picker to switch themes instantly.
    // The change is published immediately (so the UI updates) and saved to UserDefaults.

    func setTheme(id: String) {
        guard let theme = availableThemes.first(where: { $0.id == id }) else { return }
        activeTheme = theme
        UserDefaults.standard.set(id, forKey: defaultsKey)
    }

    // MARK: - Load Themes from Bundle
    // Reads Themes.json from the app bundle and decodes it.
    // Returns an empty array and logs an error if anything goes wrong.

    private static func loadThemes() -> [Theme] {
        guard let url = Bundle.main.url(forResource: "Themes", withExtension: "json") else {
            print("ThemeManager: Themes.json not found in bundle ❌")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(ThemesFile.self, from: data)
            print("ThemeManager: Loaded \(file.themes.count) theme(s) ✅")
            return file.themes
        } catch {
            print("ThemeManager: Failed to decode Themes.json — \(error) ❌")
            return []
        }
    }

    // MARK: - Convenience Color Accessors
    // These let views write themeManager.accentColor instead of
    // Color(hex: themeManager.activeTheme.colors.accent) every time.

    var backgroundPrimary:   Color { Color(hex: activeTheme.colors.backgroundPrimary) }
    var backgroundSecondary: Color { Color(hex: activeTheme.colors.backgroundSecondary) }
    var surface:             Color { Color(hex: activeTheme.colors.surface) }
    var surface2:            Color { Color(hex: activeTheme.colors.surface2) }
    var border:              Color { Color(hex: activeTheme.colors.border) }
    var accent:              Color { Color(hex: activeTheme.colors.accent) }
    var accentForeground:    Color { Color(hex: activeTheme.colors.accentForeground) }
    var textPrimary:         Color { Color(hex: activeTheme.colors.textPrimary) }
    var textSecondary:       Color { Color(hex: activeTheme.colors.textSecondary) }
    var textTertiary:        Color { Color(hex: activeTheme.colors.textTertiary) }
    var success:             Color { Color(hex: activeTheme.colors.success) }
    var warning:             Color { Color(hex: activeTheme.colors.warning) }
    var danger:              Color { Color(hex: activeTheme.colors.danger) }
    var sparkline:           Color { Color(hex: activeTheme.colors.sparkline) }

    // The SwiftUI ColorScheme value derived from the theme's appearance string.
    // Used to force the correct light/dark mode for the active theme.
    var colorScheme: ColorScheme {
        activeTheme.appearance == "light" ? .light : .dark
    }
}
