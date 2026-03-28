//
//  SettingsView.swift
//  TaskTether
//
//  Created: 13/03/2026 · 18:10
//  Updated: 28/03/2026
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - SettingsView

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
        .frame(width: 460, height: 580)
        // Bring window to front when it opens
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - General Settings Tab

private struct GeneralSettingsTab: View {

    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var authManager:  GoogleAuthManager

    @State private var themeLoadError: String?
    @State private var showingThemeError = false

    // Available app languages — system default + supported localisations
    private let supportedLanguages: [(id: String, name: String)] = [
        ("system", "System Default"),
        ("en",     "English"),
        ("hu",     "Magyar"),
        ("ar",     "العربية"),
    ]

    // Reads and writes the app language override stored in UserDefaults.
    // Setting AppleLanguages forces the next launch to use the chosen language.
    @State private var selectedLanguage: String = {
        let stored = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        return stored?.first ?? "system"
    }()

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

                // MARK: Language
                Section(String(localized: "settings.section.language")) {
                    Picker(
                        String(localized: "settings.language.label"),
                        selection: $selectedLanguage
                    ) {
                        ForEach(supportedLanguages, id: \.id) { lang in
                            Text(lang.name).tag(lang.id)
                        }
                    }
                    .onChange(of: selectedLanguage) { _, newValue in
                        if newValue == "system" {
                            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                        } else {
                            UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                        }
                        UserDefaults.standard.synchronize()
                    }

                    Text(String(localized: "settings.language.restart_hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
                            authManager.signOut()
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
                            if let url = URL(string: "https://ko-fi.com/hazims") {
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
        .modifier(AlwaysScrollIndicators())
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

    private func loadCustomTheme() {
        let panel = NSOpenPanel()
        panel.title               = String(localized: "settings.customtheme.panel.title")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let error = themeManager.loadTheme(from: url) {
            themeLoadError    = error
            showingThemeError = true
        }
    }
}

// MARK: - ThemeSwatchRow

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

// MARK: - AlwaysScrollIndicators

private struct AlwaysScrollIndicators: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.scrollIndicatorsFlash(onAppear: true)
        } else {
            content
        }
    }
}

// MARK: - Preview
#Preview {
    SettingsView()
        .environmentObject(ThemeManager())
}
