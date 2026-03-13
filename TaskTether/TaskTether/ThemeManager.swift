//
//  ThemeManager.swift
//  TaskTether
//
//  Updated: 13/03/2026 · 19:00
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
// Single source of truth for theming across the entire app.
// Injected at the top level in TaskTetherApp and accessed via @EnvironmentObject.
//
// Theme resolution:
//   appearanceOverride == "system"  → watches macOS effective appearance live
//   appearanceOverride == "light"   → always uses lightThemeId slot
//   appearanceOverride == "dark"    → always uses darkThemeId slot

class ThemeManager: ObservableObject {

    // MARK: - Published State

    // The resolved active theme — the only property views need to read colours from.
    // Updated automatically whenever slots, override, or system appearance changes.
    @Published private(set) var activeTheme: Theme

    // All themes loaded from Themes.json plus any user-loaded custom themes.
    @Published private(set) var availableThemes: [Theme] = []

    // The two theme slots.
    @Published var lightThemeId: String {
        didSet {
            UserDefaults.standard.set(lightThemeId, forKey: lightThemeKey)
            // Defer to avoid "publishing changes from within view updates" warning.
            DispatchQueue.main.async { self.resolveActiveTheme() }
        }
    }
    @Published var darkThemeId: String {
        didSet {
            UserDefaults.standard.set(darkThemeId, forKey: darkThemeKey)
            DispatchQueue.main.async { self.resolveActiveTheme() }
        }
    }

    // Appearance override: "system", "light", or "dark".
    @Published var appearanceOverride: String {
        didSet {
            UserDefaults.standard.set(appearanceOverride, forKey: appearanceKey)
            DispatchQueue.main.async { self.resolveActiveTheme() }
        }
    }

    // Sync interval in minutes. Used by SyncEngine in Group 3.
    @Published var syncInterval: Int {
        didSet { UserDefaults.standard.set(syncInterval, forKey: syncIntervalKey) }
    }

    // MARK: - Private State

    // Tracks the current macOS dark mode state. Updated live via KVO.
    private var systemIsDark: Bool = false

    // KVO token — held for the lifetime of ThemeManager.
    private var appearanceObservation: NSKeyValueObservation?

    // MARK: - UserDefaults Keys

    private let lightThemeKey   = "tasktether_light_theme_id"
    private let darkThemeKey    = "tasktether_dark_theme_id"
    private let appearanceKey   = "tasktether_appearance_override"
    private let syncIntervalKey = "tasktether_sync_interval"

    // MARK: - Init

    init() {
        let loaded = ThemeManager.loadThemes()

        // Restore slots from UserDefaults, falling back to sensible defaults.
        let savedLight    = UserDefaults.standard.string(forKey: "tasktether_light_theme_id")
        let savedDark     = UserDefaults.standard.string(forKey: "tasktether_dark_theme_id")
        let savedMode     = UserDefaults.standard.string(forKey: "tasktether_appearance_override") ?? "system"
        let savedInterval = UserDefaults.standard.integer(forKey: "tasktether_sync_interval")

        self.availableThemes    = loaded
        self.lightThemeId       = savedLight ?? "sand"
        self.darkThemeId        = savedDark  ?? "midnight"
        self.appearanceOverride = savedMode
        self.syncInterval       = savedInterval > 0 ? savedInterval : 15

        // Determine initial system appearance before resolving the active theme.
        self.systemIsDark = NSApp.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Resolve the starting active theme.
        // Use local variables here — self cannot be referenced before all
        // stored properties are fully initialised.
        self.activeTheme = ThemeManager.resolve(
            lightId:      savedLight ?? "sand",
            darkId:       savedDark  ?? "midnight",
            override:     savedMode,
            systemIsDark: self.systemIsDark,
            themes:       loaded
        )

        // Observe macOS effective appearance changes so "System" mode reacts live.
        appearanceObservation = NSApp.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.systemIsDark = NSApp.effectiveAppearance
                    .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                self.resolveActiveTheme()
            }
        }
    }

    // MARK: - Theme Resolution

    // Resolves and publishes the correct active theme based on current state.
    private func resolveActiveTheme() {
        activeTheme = ThemeManager.resolve(
            lightId:      lightThemeId,
            darkId:       darkThemeId,
            override:     appearanceOverride,
            systemIsDark: systemIsDark,
            themes:       availableThemes
        )
    }

    // Pure static resolver — easy to unit test in isolation.
    private static func resolve(
        lightId:      String,
        darkId:       String,
        override:     String,
        systemIsDark: Bool,
        themes:       [Theme]
    ) -> Theme {
        let targetId: String
        switch override {
        case "light":  targetId = lightId
        case "dark":   targetId = darkId
        default:       targetId = systemIsDark ? darkId : lightId  // "system"
        }
        return themes.first(where: { $0.id == targetId })
            ?? themes.first(where: { $0.id == lightId })
            ?? themes.first!
    }

    // MARK: - Load Custom Theme from File
    // Decodes a Theme from a user-chosen JSON file, adds it to availableThemes
    // if not already present, then assigns it to the matching slot by appearance.
    // Returns an error string on failure, nil on success.

    @discardableResult
    func loadTheme(from url: URL) -> String? {
        do {
            let data  = try Data(contentsOf: url)
            let theme = try JSONDecoder().decode(Theme.self, from: data)
            if !availableThemes.contains(where: { $0.id == theme.id }) {
                availableThemes.append(theme)
            }
            if theme.appearance == "dark" {
                darkThemeId = theme.id
            } else {
                lightThemeId = theme.id
            }
            return nil
        } catch {
            return "Could not load theme: \(error.localizedDescription)"
        }
    }

    // MARK: - Load Themes from Bundle

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
    // Let views write themeManager.accent instead of
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
}
