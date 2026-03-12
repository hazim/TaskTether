//
//  StatusDot.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//

import SwiftUI

// MARK: - ConnectionStatus
// The three possible states for a service connection.
// Each state maps to a theme colour and a localised label.

enum ConnectionStatus {
    case connected
    case syncing
    case error

    // The label is used for accessibility and tooltips.
    var labelKey: String {
        switch self {
        case .connected: return "status.connected"
        case .syncing:   return "status.syncing"
        case .error:     return "status.error"
        }
    }
}

// MARK: - StatusDot
// A three-layer glowing dot indicating connection status.
// Outer glow → mid glow → solid core.
// Colours come from the active theme via ThemeManager.
//
// Usage:
//   StatusDot(status: .connected)
//   StatusDot(status: remindersManager.isAuthorised ? .connected : .error)

struct StatusDot: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let status: ConnectionStatus

    var body: some View {
        ZStack {
            // Outer glow — very soft
            Circle()
                .fill(dotColor.opacity(0.15))
                .frame(
                    width:  DesignTokens.dotOuter,
                    height: DesignTokens.dotOuter
                )

            // Mid glow
            Circle()
                .fill(dotColor.opacity(0.30))
                .frame(
                    width:  DesignTokens.dotMid,
                    height: DesignTokens.dotMid
                )

            // Core dot
            Circle()
                .fill(dotColor)
                .frame(
                    width:  DesignTokens.dotCore,
                    height: DesignTokens.dotCore
                )
        }
        // Accessibility label so screen readers announce the status correctly
        .accessibilityLabel(String(localized: String.LocalizationValue(status.labelKey)))
    }

    // Resolves the correct theme colour for the current status
    private var dotColor: Color {
        switch status {
        case .connected: return themeManager.success
        case .syncing:   return themeManager.warning
        case .error:     return themeManager.danger
        }
    }
}

// MARK: - Preview
#Preview {
    HStack(spacing: DesignTokens.spacingLg) {
        StatusDot(status: .connected)
        StatusDot(status: .syncing)
        StatusDot(status: .error)
    }
    .padding(DesignTokens.paddingMd)
    .environmentObject(ThemeManager())
}
