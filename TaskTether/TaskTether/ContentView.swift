//
//  ContentView.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//  Refactored: 13/03/2026 · 19:30
//

import SwiftUI

// MARK: - ContentView

struct ContentView: View {

    @EnvironmentObject private var themeManager:       ThemeManager
    @EnvironmentObject private var authManager:         GoogleAuthManager
    @EnvironmentObject private var remindersManager:    RemindersManager
    @EnvironmentObject private var googleTasksManager:  GoogleTasksManager
    @EnvironmentObject private var syncEngine:          SyncEngine

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainContainerView(
                    authManager:        authManager,
                    remindersManager:   remindersManager,
                    googleTasksManager: googleTasksManager
                )
            } else {
                ConnectView(authManager: authManager)
            }
        }
        .onAppear {
            // Startup handled in MainContainerView.onAppear via SyncEngine.start()
        }
    }
}

// MARK: - ShellHeightKey
// PreferenceKey used to pass the shell's measured height up to the parent view.
private struct ShellHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - MainContainerView
//
// WINDOW ANCHOR FIX:
//   The window is ALWAYS 600px wide (popoverWidthToday).
//   The Today panel is always in the layout but slides in/out via OFFSET + OPACITY.
//   The window frame never changes → the window never repositions.
//   Today slides in from the left inside a clipped fixed container.
//
// DRAWER FIX:
//   The Shell is a static VStack that never redraws.
//   InsightPanel sits between Zone 4 and Zone 8.
//   It reveals by growing from height 0 → intrinsic height with .clipped().
//   Zone 8 (the drawer handle) naturally moves down as the drawer opens.
//   Nothing in the Shell above Zone 4 ever moves.

struct MainContainerView: View {

    @EnvironmentObject private var themeManager:       ThemeManager
    @EnvironmentObject private var syncEngine:          SyncEngine

    @ObservedObject var authManager:        GoogleAuthManager
    @ObservedObject var remindersManager:   RemindersManager
    @ObservedObject var googleTasksManager: GoogleTasksManager

    @State private var activePanel:      Panel         = .compact
    @State private var engineStarted:    Bool          = false
    // Captures the shell's intrinsic height so TodayView can be constrained to match.
    // Without this, TodayView's ScrollView reports 12-item content height to the HStack,
    // making the window far too tall even when Today is visually hidden at width=0.
    @State private var shellHeight:       CGFloat       = 0

    // Tracks whether the InsightPanel should be visible.
    // Persists when switching to Today so Expanded→Today keeps the taller shell height.
    // Compact→Today leaves it false so the shell stays at compact height.
    @State private var showInsightPanel: Bool          = false

    private var todayIsOpen: Bool { activePanel == .today }

    var body: some View {
        // MenuBarExtra (.menuBarExtraStyle(.window)) anchors to the menu bar icon
        // and grows LEFTWARD when content gets wider. So we just let content drive
        // the width — no offsets, no fixed frames, no constraint loops.
        //   Today closed: 300px (Shell only)
        //   Today open:   601px (TodayView + divider + Shell)
        // The right edge stays fixed. macOS handles the rest.
        HStack(spacing: 0) {

            // ── Today Panel (LEFT side) ──────────────────────────
            // Width animates 0 → 300. Clipped so content never bleeds.

            TodayView(
                tasks:    tasks,
                onToggle: { id in syncEngine.toggleTask(id: id) },
                onAdd:    { title in syncEngine.addTask(title: title) }
            )
            // Height is pinned to shellHeight so TodayView's ScrollView never drives
            // the HStack (and therefore the window) to a taller size than the shell.
            .frame(width: todayIsOpen ? DesignTokens.popoverWidth : 0,
                   height: shellHeight > 0 ? shellHeight : nil)
            .opacity(todayIsOpen ? 1 : 0)
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: todayIsOpen)
            .clipped()

            // Vertical divider — only while Today is open
            if todayIsOpen {
                Rectangle()
                    .fill(themeManager.border)
                    .frame(width: 1)
            }

            // ── Shell (RIGHT side) ───────────────────────────────
            // Always 300px. Measures its own height so TodayView can match it.
            shellContent
                .frame(width: DesignTokens.popoverWidth)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ShellHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .onPreferenceChange(ShellHeightKey.self) { height in
            if height > 0 { shellHeight = height }
        }
        .background(themeManager.backgroundPrimary)
        .preferredColorScheme(themeManager.activeTheme.appearance == "light" ? .light : .dark)
        .onAppear {
            guard !engineStarted else { return }
            engineStarted = true
            remindersManager.requestAccess()
            googleTasksManager.setup()
            syncEngine.start()
        }
        // Re-trigger sync the moment Google Tasks connects — start() fires
        // before isConnected is true so the initial sync guard fails silently.
        .onChange(of: googleTasksManager.isConnected) { _, connected in
            if connected { syncEngine.syncNow() }
        }
        .onChange(of: remindersManager.isAuthorised) { _, authorised in
            if authorised { syncEngine.syncNow() }
        }
        // No animation on the outer container — any implicit animation here
        // propagates to height changes and causes MenuBarExtra's constraint loop crash.
        // Animations are applied directly on the Today panel views below.
        .onChange(of: activePanel) { _, newPanel in
            // When switching to Today, preserve the current insight panel state
            // so Expanded→Today keeps the taller shell height.
            // When switching away from Today, update based on the new destination.
            if newPanel != .today {
                var t = Transaction(animation: nil)
                t.disablesAnimations = true
                withTransaction(t) {
                    showInsightPanel = (newPanel == .expanded)
                }
            }
            // If newPanel == .today, showInsightPanel is intentionally left unchanged.
        }
    }

    // MARK: Shell — never redraws as a unit

    @ViewBuilder
    private var shellContent: some View {
        VStack(spacing: 0) {

            // Zone 1 — TitleBar
            AppTitleBar()

            // Zone 2 — NavPill
            shellDivider
            SegmentedNav(selection: $activePanel)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 9)
                .frame(maxWidth: .infinity)
                .background(themeManager.backgroundSecondary)

            // Zone 3 — SyncStrip
            shellDivider
            SyncStripRow(lastSyncText: syncEngine.lastSyncText)

            // Zone 4 — ServiceColumns
            shellDivider
            ServiceColumnsRow(
                remindersStatus:   remindersStatus,
                googleTasksStatus: googleTasksStatus
            )
            // fixedSize prevents Zone 4 from stretching when the window is taller
            // than compact height (e.g. coming back from Expanded or Today+Expanded).
            .fixedSize(horizontal: false, vertical: true)

            // Zones 5–7 — InsightPanel
            // MenuBarExtra cannot animate height changes without crashing (constraint loop).
            // Window height snaps instantly; content fades in/out with opacity.
            // The pill slide in Zone 2 provides the visual transition feel.
            if showInsightPanel {
                shellDivider
                InsightPanelView(
                    todayScore:         74,
                    todayCompleted:     6,
                    todayTotal:         8,
                    yesterdayScore:     62,
                    yesterdayCompleted: 5,
                    yesterdayTotal:     8,
                    deltaValue:         12,
                    sparklineScores:    [48, 55, 62, 58, 70, 62, 74]
                )
                // No transition — instant height change is the only safe option in MenuBarExtra
            }

            // Zone 8 — SyncButton (the drawer handle — moves down as drawer opens)
            shellDivider
            SyncButtonRow(isSyncing: syncEngine.state == .syncing, onSyncTapped: { syncEngine.syncNow() })
        }
        .background(themeManager.backgroundPrimary)
    }

    // A divider that carries the correct background on both sides.
    // Using a ZStack to ensure no bleed from the parent container.
    private var shellDivider: some View {
        ZStack {
            themeManager.backgroundPrimary
            themeManager.border
                .frame(height: 1)
        }
        .frame(height: 1)
    }

    // MARK: Helpers

    private var remindersStatus: ConnectionStatus {
        remindersManager.isAuthorised ? .connected : .error
    }

    private var googleTasksStatus: ConnectionStatus {
        googleTasksManager.isConnected ? .connected : .error
    }

    // MARK: - Live Task State

    private var tasks: [TetherTaskItem] {
        syncEngine.todayTasks.map { $0.toDisplayItem() }
    }


}

// MARK: - Zone 1: AppTitleBar
// background: backgroundSecondary (= header-bg)
// padding: top 14, leading 16, trailing 12, bottom 13

private struct AppTitleBar: View {

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 0) {
            Text(String(localized: "app.name"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(themeManager.textPrimary)
                .kerning(-0.02 * 16)

            Spacer()

            HStack(spacing: 2) {
                SettingsGearButton()

                TitleBarIconButton(
                    icon:    "rectangle.portrait.and.arrow.right",
                    tooltip: String(localized: "tooltip.quit")
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.top, 14)
        .padding(.bottom, 13)
        .background(themeManager.backgroundSecondary)
    }
}

private struct TitleBarIconButton: View {

    @EnvironmentObject private var themeManager: ThemeManager
    @State private var isHovered = false

    let icon:    String
    let tooltip: String
    let action:  () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isHovered ? themeManager.textPrimary : themeManager.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovered ? themeManager.surface2 : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Settings Gear Button
// SettingsLink is the correct SwiftUI way to open the Settings scene.
// It is wrapped here to match the TitleBarIconButton visual style.

private struct SettingsGearButton: View {

    @EnvironmentObject private var themeManager: ThemeManager
    @State private var isHovered = false

    var body: some View {
        SettingsLink {
            Image(systemName: "gear")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isHovered ? themeManager.textPrimary : themeManager.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovered ? themeManager.surface2 : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(String(localized: "tooltip.settings"))
        .onHover { isHovered = $0 }
    }
}

// MARK: - Zone 3: SyncStripRow
// background: backgroundSecondary (= header-bg)
// padding: top 6, horizontal 16, bottom 5

private struct SyncStripRow: View {

    @EnvironmentObject private var themeManager: ThemeManager
    let lastSyncText: String

    var body: some View {
        HStack {
            Text(String(localized: "sync.strip.label"))
                .font(.system(size: 9.5, design: .monospaced))
                .textCase(.uppercase)
                .tracking(0.06 * 9.5)
                .foregroundStyle(themeManager.textSecondary.opacity(0.75))

            Spacer()

            Text(lastSyncText)
                .font(.system(size: 9.5, design: .monospaced).weight(.medium))
                .foregroundStyle(themeManager.success)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 5)
        .background(themeManager.backgroundSecondary)
    }
}

// MARK: - Zone 4: ServiceColumnsRow

private struct ServiceColumnsRow: View {

    @EnvironmentObject private var themeManager: ThemeManager
    let remindersStatus:   ConnectionStatus
    let googleTasksStatus: ConnectionStatus

    var body: some View {
        HStack(spacing: 0) {
            ServiceColumn(name: String(localized: "service.reminders"),   status: remindersStatus)

            Rectangle()
                .fill(themeManager.border)
                .frame(width: 1)

            ServiceColumn(name: String(localized: "service.googletasks"), status: googleTasksStatus)
        }
        .background(themeManager.backgroundPrimary)
    }
}

private struct ServiceColumn: View {

    @EnvironmentObject private var themeManager: ThemeManager
    let name:   String
    let status: ConnectionStatus

    var body: some View {
        VStack(spacing: 5) {
            StatusDot(status: status)

            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(themeManager.textPrimary)
                .multilineTextAlignment(.center)

            Text(String(localized: String.LocalizationValue(status.labelKey)))
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.04 * 9)
                .foregroundStyle(themeManager.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(themeManager.backgroundPrimary)
    }
}

// MARK: - Zones 5–7: InsightPanelView
// Padding matches HTML prod-zone: top 12, horizontal 14, bottom 14.

private struct InsightPanelView: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let todayScore:         Int
    let todayCompleted:     Int
    let todayTotal:         Int
    let yesterdayScore:     Int
    let yesterdayCompleted: Int
    let yesterdayTotal:     Int
    let deltaValue:         Int
    let sparklineScores:    [Double]

    private var deltaPositive: Bool { deltaValue >= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            todaySection
            prodDivider
            yesterdaySection
            prodDivider.padding(.top, 10)
            weekSection
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.backgroundPrimary)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "expanded.label.today"))
                    .font(.system(size: 9.5, design: .monospaced).weight(.medium))
                    .textCase(.uppercase)
                    .tracking(0.10 * 9.5)
                    .foregroundStyle(themeManager.textTertiary)
                Spacer()
                Text("\(deltaPositive ? "↑" : "↓") \(deltaPositive ? "+" : "")\(deltaValue)% vs yesterday")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(deltaPositive ? themeManager.success : themeManager.danger)
            }
            .padding(.bottom, 8)

            HStack(alignment: .bottom, spacing: 8) {
                HStack(alignment: .bottom, spacing: 2) {
                    Text("\(todayScore)")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(themeManager.accent)
                        .kerning(-0.05 * 52)
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 22, weight: .light).italic())
                        .foregroundStyle(themeManager.accent.opacity(0.65))
                        .padding(.bottom, 5)
                }
                Spacer()
                Text("\(todayCompleted) / \(todayTotal) \(String(localized: "expanded.tasks.done"))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(themeManager.textTertiary)
                    .multilineTextAlignment(.trailing)
                    .padding(.bottom, 6)
            }
        }
    }

    private var yesterdaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "expanded.label.yesterday"))
                .font(.system(size: 9.5, design: .monospaced).weight(.medium))
                .textCase(.uppercase)
                .tracking(0.10 * 9.5)
                .foregroundStyle(themeManager.textTertiary)
                .padding(.top, 10)
                .padding(.bottom, 8)

            HStack(alignment: .bottom, spacing: 8) {
                HStack(alignment: .bottom, spacing: 2) {
                    Text("\(yesterdayScore)")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(themeManager.accent.opacity(0.5))
                        .kerning(-0.05 * 30)
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 14, weight: .light).italic())
                        .foregroundStyle(themeManager.accent.opacity(0.4))
                        .padding(.bottom, 3)
                }
                Spacer()
                Text("\(yesterdayCompleted) / \(yesterdayTotal) \(String(localized: "expanded.tasks.done"))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(themeManager.textTertiary.opacity(0.55))
                    .multilineTextAlignment(.trailing)
                    .padding(.bottom, 3)
            }
        }
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "expanded.label.last7days"))
                .font(.system(size: 9.5, design: .monospaced).weight(.medium))
                .textCase(.uppercase)
                .tracking(0.10 * 9.5)
                .foregroundStyle(themeManager.textTertiary)
                .padding(.top, 10)

            SparklineView(scores: sparklineScores)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
    }

    private var prodDivider: some View {
        Rectangle()
            .fill(themeManager.border.opacity(0.6))
            .frame(height: 1)
            .padding(.top, 4)
    }
}

// MARK: - Zone 8: SyncButtonRow
// padding: top 10, horizontal 14, bottom 14

private struct SyncButtonRow: View {

    @EnvironmentObject private var themeManager: ThemeManager
    let isSyncing:    Bool
    let onSyncTapped: () -> Void

    var body: some View {
        Button(action: onSyncTapped) {
            HStack(spacing: 6) {
                // Fixed frame keeps both states the same size so the button
                // never changes height when isSyncing toggles.
                ZStack {
                    if isSyncing {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .frame(width: 14, height: 14)
                Text(String(localized: isSyncing ? "sync.button.loading" : "sync.button"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(themeManager.accent))
        }
        .buttonStyle(.plain)
        .disabled(isSyncing)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(themeManager.backgroundPrimary)
    }
}

// MARK: - ConnectView

struct ConnectView: View {

    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject var authManager: GoogleAuthManager

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingMd) {
            Text(String(localized: "app.name"))
                .font(.system(size: DesignTokens.fontMd, weight: .semibold))
                .foregroundStyle(themeManager.textPrimary)

            SectionDivider()

            Text(String(localized: "connect.description"))
                .font(.system(size: DesignTokens.fontSm))
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = authManager.errorMessage {
                Text(error)
                    .font(.system(size: DesignTokens.fontSm))
                    .foregroundStyle(themeManager.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TetherButton(
                String(localized: authManager.isAuthenticating
                    ? "connect.button.loading"
                    : "connect.button.idle"),
                icon: authManager.isAuthenticating ? nil : "person.crop.circle.badge.plus",
                isLoading: authManager.isAuthenticating
            ) {
                authManager.signIn()
            }
            .disabled(authManager.isAuthenticating)

            SectionDivider()

            TetherButton(
                String(localized: "general.quit"),
                icon: "rectangle.portrait.and.arrow.right",
                style: .secondary
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(DesignTokens.paddingMd)
        .frame(width: DesignTokens.popoverWidth)
        .background(themeManager.backgroundPrimary)
        .preferredColorScheme(themeManager.activeTheme.appearance == "light" ? .light : .dark)
    }
}

// No new localisation keys required — all keys in this file already exist.
