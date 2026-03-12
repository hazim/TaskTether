//
//  ContentView.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//  Refactored: 13/03/2026
//

import SwiftUI

// MARK: - ContentView
// Root view. Routes between ConnectView (unauthenticated) and MainContainerView (authenticated).

struct ContentView: View {

    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var remindersManager   = RemindersManager()
    @StateObject private var authManager        = GoogleAuthManager()
    @StateObject private var googleTasksManager: GoogleTasksManager

    init() {
        let auth = GoogleAuthManager()
        _authManager         = StateObject(wrappedValue: auth)
        _googleTasksManager  = StateObject(wrappedValue: GoogleTasksManager(authManager: auth))
    }

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
            remindersManager.requestAccess()
            if authManager.isAuthenticated {
                googleTasksManager.setup()
            }
        }
    }
}

// MARK: - MainContainerView
// The authenticated shell.
//
// Panel layout:
//   [ SegmentedNav pill ]          ← always visible at top, sits in the VStack
//   [ SectionDivider ]
//   [ TodayView (slides left) | CompactView or ExpandedView ]
//   [ BottomBar ]
//
// When Today is closed: total width = 300px
// When Today is open:   total width = 600px (TodayView 300 + main panel 300)
// The window width animates with a spring.

struct MainContainerView: View {

    @EnvironmentObject private var themeManager: ThemeManager

    @ObservedObject var authManager:        GoogleAuthManager
    @ObservedObject var remindersManager:   RemindersManager
    @ObservedObject var googleTasksManager: GoogleTasksManager

    @State private var activePanel: Panel = .compact

    private var todayIsOpen: Bool { activePanel == .today }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Nav Pill — sits at the top inside the content area
            SegmentedNav(selection: $activePanel)
                .padding(.horizontal, DesignTokens.paddingMd)
                .padding(.top, DesignTokens.paddingSm + 2)
                .padding(.bottom, DesignTokens.paddingSm)

            SectionDivider()

            // MARK: Panel Row
            // TodayView slides in from the left; main panel always visible on the right.
            HStack(spacing: 0) {

                // Today panel — zero width when closed, 300px when open
                TodayView(
                    tasks:           placeholderTasks,
                    onToggle:        { _ in },
                    onTomorrow:      { _ in },
                    onDelete:        { _ in },
                    onLinkTapped:    { _, _ in },
                    onSubtaskToggle: { _, _ in },
                    onAddTask:       {}
                )
                .frame(width: todayIsOpen ? DesignTokens.popoverWidth : 0)
                .opacity(todayIsOpen ? 1 : 0)
                .clipped()

                // Divider between Today and main panel (only visible when Today is open)
                if todayIsOpen {
                    Rectangle()
                        .fill(themeManager.border)
                        .frame(width: 1)
                        .transition(.opacity)
                }

                // Main panel — Compact or Expanded, animated vertically
                mainPanel
                    .frame(width: DesignTokens.popoverWidth)
            }

            SectionDivider()

            // MARK: Bottom Bar — gear + quit
            BottomBar(authManager: authManager)
        }
        .frame(width: todayIsOpen ? DesignTokens.popoverWidthToday : DesignTokens.popoverWidth)
        .background(themeManager.backgroundPrimary)
        .preferredColorScheme(themeManager.colorScheme)
        .animation(
            .spring(response: 0.42, dampingFraction: 0.78),
            value: todayIsOpen
        )
    }

    // MARK: Main Panel
    // Switches between CompactView and ExpandedView with a vertical spring animation.

    @ViewBuilder
    private var mainPanel: some View {
        if activePanel == .compact || activePanel == .today {
            CompactView(
                remindersStatus:   remindersStatus,
                googleTasksStatus: googleTasksStatus,
                lastSyncText:      String(localized: "sync.last.never"),
                isSyncing:         false,
                onSyncTapped:      {}
            )
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal:   .move(edge: .top).combined(with: .opacity)
            ))
        } else {
            ExpandedView(
                remindersStatus:    remindersStatus,
                googleTasksStatus:  googleTasksStatus,
                lastSyncText:       String(localized: "sync.last.never"),
                isSyncing:          false,
                todayScore:         74,
                todayCompleted:     6,
                todayTotal:         8,
                yesterdayScore:     62,
                yesterdayCompleted: 5,
                yesterdayTotal:     8,
                deltaValue:         12,
                sparklineScores:    [48, 55, 62, 58, 70, 62, 74],
                onSyncTapped:       {}
            )
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal:   .move(edge: .bottom).combined(with: .opacity)
            ))
        }
    }

    // MARK: Helpers

    private var remindersStatus: ConnectionStatus {
        remindersManager.isAuthorised ? .connected : .error
    }

    private var googleTasksStatus: ConnectionStatus {
        googleTasksManager.isConnected ? .connected : .error
    }

    // Placeholder tasks — replaced with live data in Group 4
    private var placeholderTasks: [TetherTaskItem] {[
        TetherTaskItem(id: "1", title: "Review pull request #42",
                       isCompleted: true, url: nil, subtasks: []),
        TetherTaskItem(id: "2", title: "Write unit tests for auth module",
                       isCompleted: false, url: URL(string: "https://example.com"),
                       subtasks: [
                           TetherSubtaskItem(id: "2a", title: "Write login tests",         isCompleted: true,  url: nil),
                           TetherSubtaskItem(id: "2b", title: "Write token refresh tests", isCompleted: false, url: nil)
                       ]),
        TetherTaskItem(id: "3", title: "Call with client re: scope",
                       isCompleted: false, url: nil, subtasks: [])
    ]}
}

// MARK: - BottomBar
// Settings and Quit — pinned to the bottom of the popover.

private struct BottomBar: View {

    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject var authManager: GoogleAuthManager

    var body: some View {
        HStack {
            TetherButton(icon: "gear", style: .secondary) {
                // Opens Settings — wired in Group 2
            }
            .help(String(localized: "tooltip.settings"))

            Spacer()

            TetherButton(
                icon: "rectangle.portrait.and.arrow.right",
                style: .secondary
            ) {
                NSApplication.shared.terminate(nil)
            }
            .help(String(localized: "tooltip.quit"))
        }
        .padding(.horizontal, DesignTokens.paddingMd)
        .padding(.vertical, DesignTokens.paddingXs + 2)
    }
}

// MARK: - ConnectView
// Shown when the user has not yet authenticated with Google.

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
                    : "connect.button.idle"
                ),
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
        .preferredColorScheme(themeManager.colorScheme)
    }
}
