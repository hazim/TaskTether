//
//  SettingsView.swift
//  TaskTether
//
//  Created: 13/03/2026 · 18:10
//  Updated: 12/07/2026 — two layout paths sharing the same rows:
//           macOS 13+ uses the native grouped Form (System Settings look);
//           macOS 12 has no grouped form API and renders a plain columnar
//           Form, so it gets a hand-built card layout instead.
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
        .frame(width: 500, height: 640)
        // Grabs this view's own NSWindow and forces it to the front —
        // reliable on every macOS version and every open path, unlike
        // searching NSApp.windows by title.
        .background(SettingsWindowLifter())
        .onAppear {
            // Close the menu panel — its window level (.popUpMenu) sits
            // above normal windows and would cover the Settings window.
            NotificationCenter.default.post(name: .taskTetherHidePanel, object: nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - SettingsWindowLifter
// Accessory (no-Dock) apps may be refused activation on macOS 14+, leaving
// the Settings window open but BEHIND other apps with nothing visible to
// click. viewDidMoveToWindow guarantees a window reference, and
// orderFrontRegardless works even when the app is not active.

private struct SettingsWindowLifter: NSViewRepresentable {

    func makeNSView(context: Context) -> LifterView { LifterView() }
    func updateNSView(_ nsView: LifterView, context: Context) {}

    final class LifterView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
}

// MARK: - General Settings Tab

private struct GeneralSettingsTab: View {

    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var authManager:  GoogleAuthManager

    @State private var themeLoadError: String?
    @State private var showingThemeError = false
    @State private var showingRestartPrompt = false

    // Available app languages — system default + supported localisations
    private let supportedLanguages: [(id: String, name: String)] = [
        ("system", "System Default"),
        ("en",     "English"),
        ("hu",     "Magyar"),
        ("ar",     "العربية"),
    ]

    // The stored AppleLanguages override. macOS pre-fills AppleLanguages with
    // the system language list (e.g. ["en-GB", "hu-HU"]) even when the app has
    // never set an override — so only an exact match for one of our override
    // ids counts. Anything else means "no override" and must display as
    // System Default, not as a blank picker.
    @State private var selectedLanguage: String = {
        guard let stored = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
              let first  = stored.first,
              ["en", "hu", "ar"].contains(first)
        else { return "system" }
        return first
    }()

    // Reads and writes the dock visibility preference stored in UserDefaults.
    // Applied on next launch via NSApp.setActivationPolicy in TaskTetherApp.init().
    @State private var showInDock: Bool = UserDefaults.standard.bool(forKey: "showInDock")

    // Reads and writes the menu bar badge preference stored in UserDefaults.
    // Defaults to false (hidden) when the key has never been set: with every
    // list syncing the count is in the hundreds and reads as noise.
    @State private var showMenuBarBadge: Bool =
        UserDefaults.standard.object(forKey: "showMenuBarBadge") as? Bool ?? false

    // Reads and writes the launch-at-login preference. Defaults to true
    // (matching the first-launch behaviour in AppDelegate) when the key has
    // never been set. Unsupported pre-macOS 13 — see LoginItemManager.
    @State private var launchAtLogin: Bool =
        UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true

    // Set when SMAppService register()/unregister() throws; shown as a small
    // footnote under the toggle and cleared on the next successful change.
    @State private var launchAtLoginError: String?

    // Guards against onChange re-firing when setLaunchAtLogin reverts
    // `launchAtLogin` after a failed register()/unregister() — without this
    // the revert itself triggers another setLaunchAtLogin call, which
    // clears launchAtLoginError right after it was set.
    @State private var isRevertingLaunchAtLogin = false

    private func deferred<T>(_ keyPath: ReferenceWritableKeyPath<ThemeManager, T>) -> Binding<T> {
        Binding(
            get: { themeManager[keyPath: keyPath] },
            set: { value in DispatchQueue.main.async { themeManager[keyPath: keyPath] = value } }
        )
    }

    var body: some View {
        Group {
            if #available(macOS 13, *) {
                groupedForm
            } else {
                legacyCards
            }
        }
        .onAppear {
            reconcileLaunchAtLogin()
        }
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

    // MARK: Layout — macOS 13+ native grouped form

    @available(macOS 13, *)
    private var groupedForm: some View {
        Form {
            Section {
                themeRows
            } header: {
                Text(String(localized: "settings.section.theme"))
            }

            Section {
                appearanceRow
            } header: {
                Text(String(localized: "settings.section.appearance"))
            }

            Section {
                languageRow
            } header: {
                Text(String(localized: "settings.section.language"))
            } footer: {
                SettingsFooterText(String(localized: "settings.language.restart_hint"))
            }

            Section {
                dockRow
            } header: {
                Text(String(localized: "settings.section.dock"))
            } footer: {
                SettingsFooterText(String(localized: "settings.dock.restart_hint"))
            }

            Section {
                badgeRow
                launchAtLoginRow
            } header: {
                Text(String(localized: "settings.section.badge"))
            } footer: {
                if !LoginItemManager.isSupported {
                    SettingsFooterText(String(localized: "settings.launchAtLogin.unsupported"))
                }
            }

            Section {
                syncRow
            } header: {
                Text(String(localized: "settings.section.sync"))
            }

            Section {
                customThemeRow
            } header: {
                Text(String(localized: "settings.section.customtheme"))
            }

            Section {
                accountRow
            } header: {
                Text(String(localized: "settings.section.account"))
            }

            Section {
                aboutRow
            } header: {
                Text(String(localized: "settings.section.about"))
            }

            Section {
                supportRow
            } header: {
                Text(String(localized: "settings.section.support"))
            }
        }
        .formStyle(.grouped)
        .modifier(AlwaysScrollIndicators())
    }

    // MARK: Layout — macOS 12 card fallback
    // macOS 12 has no formStyle(.grouped); a plain Form renders the old
    // columnar preferences layout with section titles as stray text rows.
    // These hand-built cards give Monterey the same visual structure the
    // grouped form gives newer systems.

    private var legacyCards: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LegacySection(title: String(localized: "settings.section.theme")) {
                    themeRows
                }
                LegacySection(title: String(localized: "settings.section.appearance")) {
                    appearanceRow
                }
                LegacySection(
                    title:  String(localized: "settings.section.language"),
                    footer: String(localized: "settings.language.restart_hint")
                ) {
                    languageRow
                }
                LegacySection(
                    title:  String(localized: "settings.section.dock"),
                    footer: String(localized: "settings.dock.restart_hint")
                ) {
                    dockRow
                }
                LegacySection(
                    title:  String(localized: "settings.section.badge"),
                    footer: LoginItemManager.isSupported
                        ? nil
                        : String(localized: "settings.launchAtLogin.unsupported")
                ) {
                    badgeRow
                    launchAtLoginRow
                }
                LegacySection(title: String(localized: "settings.section.sync")) {
                    syncRow
                }
                LegacySection(title: String(localized: "settings.section.customtheme")) {
                    customThemeRow
                }
                LegacySection(title: String(localized: "settings.section.account")) {
                    accountRow
                }
                LegacySection(title: String(localized: "settings.section.about")) {
                    aboutRow
                }
                LegacySection(title: String(localized: "settings.section.support")) {
                    supportRow
                }
            }
            .padding(16)
        }
    }

    // MARK: Rows — shared by both layouts

    @ViewBuilder
    private var themeRows: some View {
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

    // The section header names the setting, so the picker's own label is
    // hidden — a visible "Mode" label crammed next to three segments is
    // what made this row feel cluttered.
    private var appearanceRow: some View {
        Picker(
            String(localized: "settings.appearance.label"),
            selection: deferred(\.appearanceOverride)
        ) {
            Text(String(localized: "settings.appearance.system")).tag("system")
            Text(String(localized: "settings.appearance.light")).tag("light")
            Text(String(localized: "settings.appearance.dark")).tag("dark")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var languageRow: some View {
        Picker(
            String(localized: "settings.language.label"),
            selection: $selectedLanguage
        ) {
            ForEach(supportedLanguages, id: \.id) { lang in
                Text(lang.name).tag(lang.id)
            }
        }
        .onChange(of: selectedLanguage) { newValue in
            if newValue == "system" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
            }
            UserDefaults.standard.synchronize()
            // The language is only read at process launch, and a menu bar
            // app gives no visible cue that it is still running — so offer
            // the relaunch instead of hoping the user finds Quit.
            showingRestartPrompt = true
        }
        .alert(
            String(localized: "settings.language.restart.title"),
            isPresented: $showingRestartPrompt
        ) {
            Button(String(localized: "settings.language.restart.now")) {
                relaunchApp()
            }
            Button(String(localized: "settings.language.restart.later"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.language.restart.message"))
        }
    }

    // Launches a fresh instance of the app, then terminates this one.
    private func relaunchApp() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: config
        ) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private var dockRow: some View {
        Toggle(String(localized: "settings.dock.label"), isOn: $showInDock)
            .onChange(of: showInDock) { newValue in
                UserDefaults.standard.set(newValue, forKey: "showInDock")
            }
    }

    // Takes effect immediately — onChange notifies the AppDelegate, which
    // recomputes the badge without needing a relaunch.
    private var badgeRow: some View {
        Toggle(String(localized: "settings.badge.label"), isOn: $showMenuBarBadge)
            .onChange(of: showMenuBarBadge) { newValue in
                UserDefaults.standard.set(newValue, forKey: "showMenuBarBadge")
                NotificationCenter.default.post(name: .taskTetherBadgeSettingChanged, object: nil)
            }
    }

    // Disabled with no interaction pre-macOS 13 — the section footer explains
    // why. When enabled, a failed register()/unregister() reverts the toggle
    // and surfaces the error inline rather than changing the stored default.
    @ViewBuilder
    private var launchAtLoginRow: some View {
        if LoginItemManager.isSupported {
            Toggle(String(localized: "settings.launchAtLogin.label"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    guard !isRevertingLaunchAtLogin else {
                        isRevertingLaunchAtLogin = false
                        return
                    }
                    setLaunchAtLogin(newValue)
                }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        } else {
            Toggle(String(localized: "settings.launchAtLogin.label"), isOn: .constant(false))
                .disabled(true)
        }
    }

    private func setLaunchAtLogin(_ newValue: Bool) {
        UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
        do {
            try LoginItemManager.setEnabled(newValue)
            launchAtLoginError = nil
        } catch {
            isRevertingLaunchAtLogin = true
            launchAtLogin = !newValue
            UserDefaults.standard.set(!newValue, forKey: "launchAtLogin")
            launchAtLoginError = error.localizedDescription
        }
    }

    // Reconciles the toggle with the system's actual registration state
    // (macOS 13+ only — LoginItemManager.isEnabled is always false pre-13).
    // Run on every settings appearance so removing the item via
    // System Settings → Login Items shows as OFF here instead of a stale ON.
    // Skipped from an ephemeral bundle path (DMG mount / translocation): the
    // app never registers from there, so isEnabled would read false and
    // permanently stomp the stored preference before the app is even
    // installed to its real location.
    private func reconcileLaunchAtLogin() {
        guard LoginItemManager.isSupported,
              !LoginItemManager.isRunningFromEphemeralLocation else { return }
        let actual = LoginItemManager.isEnabled
        launchAtLogin = actual
        UserDefaults.standard.set(actual, forKey: "launchAtLogin")
    }

    private var syncRow: some View {
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

    private var customThemeRow: some View {
        HStack(alignment: .center) {
            Text(String(localized: "settings.customtheme.description"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: "settings.customtheme.load")) {
                loadCustomTheme()
            }
        }
    }

    private var accountRow: some View {
        HStack {
            Text(String(localized: "settings.account.google"))
            Spacer()
            Button(String(localized: "settings.signout"), role: .destructive) {
                authManager.signOut()
            }
        }
    }

    // Version is read live from the bundle (set by MARKETING_VERSION and
    // CURRENT_PROJECT_VERSION in the Xcode project) so what the user sees
    // can never drift from what was actually built.
    private var aboutRow: some View {
        HStack {
            Text(String(localized: "settings.about.version"))
            Spacer()
            Text(appVersionText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var supportRow: some View {
        HStack(alignment: .center) {
            Text(String(localized: "settings.support.description"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Link(destination: URL(string: "https://ko-fi.com/hazims")!) {
                Image("kofi_button")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Helpers

    // "1.1.0 (4)" — marketing version plus build number from the bundle.
    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build   = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
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

// MARK: - LegacySection
// Card-style section for the macOS 12 layout: uppercase header, rounded
// card around the rows, optional footer hint below.

private struct LegacySection<Content: View>: View {

    let title:  String
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
            }
        }
    }
}

// MARK: - SettingsFooterText
// Footer hint styling for the grouped form path.

private struct SettingsFooterText: View {
    private let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
