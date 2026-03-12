//
//  CompactView.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//

import SwiftUI

// MARK: - CompactView
// The minimal one-panel view shown when the Compact segment is selected.
// Layout (top to bottom):
//   1. Sync strip  — "Last sync" label + time, monospaced
//   2. Service row — Reminders and Google Tasks side by side as two columns
//   3. Sync button — always visible at the bottom
//
// All data is passed in from the parent view.
// This view contains no business logic — display only.

struct CompactView: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let remindersStatus:    ConnectionStatus
    let googleTasksStatus:  ConnectionStatus
    let lastSyncText:       String
    let isSyncing:          Bool
    let onSyncTapped:       () -> Void

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Sync Strip
            // Persistent status line — "Last sync" on the left, time on the right.
            HStack {
                Text(String(localized: "sync.strip.label"))
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(themeManager.textSecondary.opacity(0.75))
                    .kerning(0.6)

                Spacer()

                Text(lastSyncText)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(themeManager.success)
            }
            .padding(.horizontal, DesignTokens.paddingMd)
            .padding(.vertical, DesignTokens.paddingXs + 2)
            .background(themeManager.backgroundSecondary)

            Rectangle()
                .fill(themeManager.border)
                .frame(height: 1)

            // MARK: Service Columns
            // Two columns side by side — Reminders | Google Tasks.
            // Each column shows: dot, service name, status badge.
            HStack(spacing: 0) {
                ServiceColumn(
                    name:   String(localized: "service.reminders"),
                    status: remindersStatus
                )

                Rectangle()
                    .fill(themeManager.border)
                    .frame(width: 1)

                ServiceColumn(
                    name:   String(localized: "service.googletasks"),
                    status: googleTasksStatus
                )
            }
            .background(themeManager.backgroundPrimary)

            Rectangle()
                .fill(themeManager.border)
                .frame(height: 1)

            // MARK: Sync Button
            TetherButton(
                String(localized: "sync.button"),
                icon: "arrow.triangle.2.circlepath",
                isLoading: isSyncing,
                action: onSyncTapped
            )
            .padding(DesignTokens.paddingMd)
        }
    }
}

// MARK: - ServiceColumn
// A single service column inside the compact service row.
// Shows a status dot, service name, and a text badge.

private struct ServiceColumn: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let name:   String
    let status: ConnectionStatus

    var body: some View {
        VStack(spacing: DesignTokens.spacingXs + 1) {
            StatusDot(status: status)

            Text(name)
                .font(.system(size: DesignTokens.fontSm))
                .foregroundStyle(themeManager.textPrimary)

            Text(String(localized: String.LocalizationValue(status.labelKey)))
                .font(.system(size: DesignTokens.fontCaption))
                .foregroundStyle(statusBadgeColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.paddingSm + 2)
        .padding(.horizontal, DesignTokens.paddingSm)
    }

    private var statusBadgeColor: Color {
        switch status {
        case .connected: return themeManager.success
        case .syncing:   return themeManager.warning
        case .error:     return themeManager.danger
        }
    }
}

// MARK: - Localisation keys to add to Localizable.xcstrings
// sync.strip.label → "Last sync"

// MARK: - Preview
#Preview {
    CompactView(
        remindersStatus:   .connected,
        googleTasksStatus: .connected,
        lastSyncText:      "4 min ago",
        isSyncing:         false,
        onSyncTapped:      {}
    )
    .frame(width: DesignTokens.popoverWidth)
    .environmentObject(ThemeManager())
}
