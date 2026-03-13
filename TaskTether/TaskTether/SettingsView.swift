//
//  SettingsView.swift
//  TaskTether
//
//  Created: 13/03/2026 · 18:10
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - SettingsView
// Standard macOS Settings window. Opens via gear icon or Cmd+,
// Structured as a TabView with a single "General" tab for now.
// Additional tabs (Accounts, Advanced) can be added in later groups.

struct SettingsView: View {

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label(
                        String(localized: "settings.tab.general"),
                        systemImage: "gearshape"
                    )
                }
        }
        .frame(width: 460, height: 390)
    }
}

// MARK: - General Settings Tab

private struct GeneralSettingsTab: View {

    @EnvironmentObject private var themeManager: ThemeManager

    // Local state for the theme load error alert
    @State private var themeLoadError: String?
    @State private var showingThemeError = false

    // Wraps a ThemeManager keypath in a Binding that defers writes to the next
    // run loop tick. Prevents "Publishing changes from within view updates" warnings
    // caused by @Published properties firing objectWillChange mid-render.
    private func deferred<T>(_ keyPath: ReferenceWritableKeyPath<ThemeManager, T>) -> Binding<T> {
        Binding(
            get: { themeManager[keyPath: keyPath] },
            set: { value in DispatchQueue.main.async { themeManager[keyPath: keyPath] = value } }
        )
    }

    var body: some View {
        Form {

            // MARK: Theme
            Section(String(localized: "settings.section.theme")) {
                Picker(
                    String(localized: "settings.theme.light"),
                    selection: deferred(\.lightThemeId)
                ) {
                    ForEach(themeManager.availableThemes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }

                Picker(
                    String(localized: "settings.theme.dark"),
                    selection: deferred(\.darkThemeId)
                ) {
                    ForEach(themeManager.availableThemes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }

                // Colour swatches for the currently resolved active theme
                ThemeSwatchRow()
            }

            // MARK: Appearance
            Section(String(localized: "settings.section.appearance")) {
                Picker(
                    String(localized: "settings.appearance.label"),
                    selection: deferred(\.appearanceOverride)
                ) {
                    Text(String(localized: "settings.appearance.system")).tag("system")
                    Text(String(localized: "settings.appearance.light")).tag("light")
                    Text(String(localized: "settings.appearance.dark")).tag("dark")
                }
                .pickerStyle(.segmented)
            }

            // MARK: Sync
            Section(String(localized: "settings.section.sync")) {
                Picker(
                    String(localized: "settings.sync.interval"),
                    selection: deferred(\.syncInterval)
                ) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                        Text(
                            String(
                                format: String(localized: "settings.sync.interval.minutes"),
                                minutes
                            )
                        )
                        .tag(minutes)
                    }
                }
            }

            // MARK: Custom Themes
            Section(String(localized: "settings.section.customtheme")) {
                HStack {
                    Text(String(localized: "settings.customtheme.description"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "settings.customtheme.load")) {
                        loadCustomTheme()
                    }
                }
            }

            // MARK: Account
            Section(String(localized: "settings.section.account")) {
                HStack {
                    Text(String(localized: "settings.account.google"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "settings.signout"), role: .destructive) {
                        // Wired in Group 3 — GoogleAuthManager.signOut()
                    }
                }
            }

            // MARK: Support
            Section(String(localized: "settings.section.support")) {
                HStack {
                    Text(String(localized: "settings.support.description"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        if let url = URL(string: "https://ko-fi.com") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label(
                            String(localized: "settings.support.link"),
                            systemImage: "cup.and.saucer"
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .alert(
            String(localized: "settings.customtheme.error.title"),
            isPresented: $showingThemeError,
            presenting: themeLoadError
        ) { _ in
            Button(String(localized: "settings.alert.ok")) {}
        } message: { error in
            Text(error)
        }
    }

    // MARK: - Custom Theme Loader

    private func loadCustomTheme() {
        let panel = NSOpenPanel()
        panel.title               = String(localized: "settings.customtheme.panel.title")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let error = themeManager.loadTheme(from: url) {
            themeLoadError  = error
            showingThemeError = true
        }
    }
}

// MARK: - ThemeSwatchRow
// Displays five colour swatches from the active theme so the user can
// preview it without leaving the Settings window.

private struct ThemeSwatchRow: View {

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 6) {
            ForEach(swatches, id: \.0) { label, color in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: 28, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                    Text(label)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private var swatches: [(String, Color)] {[
        ("BG",      themeManager.backgroundPrimary),
        ("Surface", themeManager.surface),
        ("Accent",  themeManager.accent),
        ("Text",    themeManager.textPrimary),
        ("Spark",   themeManager.sparkline)
    ]}
}

// MARK: - Preview
#Preview {
    SettingsView()
        .environmentObject(ThemeManager())
}
