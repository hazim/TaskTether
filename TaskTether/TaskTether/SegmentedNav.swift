//
//  SegmentedNav.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//

import SwiftUI

// MARK: - Panel
// The three view states of the TaskTether popover.
// This enum is the single source of truth for which panel is visible.

enum Panel: String, CaseIterable {
    case compact  = "compact"
    case expanded = "expanded"
    case today    = "today"

    // The label shown in the segmented control
    var labelKey: String {
        switch self {
        case .compact:  return "nav.compact"
        case .expanded: return "nav.expanded"
        case .today:    return "nav.today"
        }
    }
}

// MARK: - SegmentedNav
// The three-segment pill control that switches between Compact, Expanded, and Today.
// Uses a custom drawn control rather than the default NSSegmentedControl appearance
// so it matches the HTML preview exactly — a pill shape with a sliding indicator.
//
// Usage:
//   SegmentedNav(selection: $currentPanel)

struct SegmentedNav: View {

    @EnvironmentObject private var themeManager: ThemeManager
    @Binding var selection: Panel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Panel.allCases, id: \.self) { panel in
                segmentButton(for: panel)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.radiusXl)
                .fill(themeManager.surface2)
        )
    }

    // MARK: - Segment Button
    // Each individual segment in the control.

    @ViewBuilder
    private func segmentButton(for panel: Panel) -> some View {
        let isActive = selection == panel

        Button {
            withAnimation(.easeInOut(duration: DesignTokens.animFast)) {
                selection = panel
            }
        } label: {
            Text(String(localized: String.LocalizationValue(panel.labelKey)))
                .font(.system(
                    size: DesignTokens.fontSm,
                    weight: isActive ? .medium : .regular
                ))
                .foregroundStyle(
                    isActive
                        ? themeManager.textPrimary
                        : themeManager.textSecondary
                )
                .padding(.vertical, DesignTokens.paddingXs)
                .padding(.horizontal, DesignTokens.paddingSm)
                .frame(maxWidth: .infinity)
                .background(
                    Group {
                        if isActive {
                            if #available(macOS 26, *) {
                                // Liquid Glass — the active segment appears as a
                                // frosted glass pill sliding across the control.
                                RoundedRectangle(cornerRadius: DesignTokens.radiusXl - 2)
                                    .glassEffect(.regular)
                            } else {
                                // Fallback for macOS 12–25
                                RoundedRectangle(cornerRadius: DesignTokens.radiusXl - 2)
                                    .fill(.ultraThinMaterial)
                                    .shadow(
                                        color: Color.black.opacity(0.12),
                                        radius: 2,
                                        x: 0,
                                        y: 1
                                    )
                            }
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: DesignTokens.animFast), value: isActive)
    }
}

// MARK: - Localisation keys to add to Localizable.xcstrings
// nav.compact  → "Compact"
// nav.expanded → "Expanded"
// nav.today    → "Today"

// MARK: - Preview
#Preview {
    @Previewable @State var panel: Panel = .expanded

    VStack(spacing: DesignTokens.spacingMd) {
        SegmentedNav(selection: $panel)
        Text("Selected: \(panel.rawValue)")
            .font(.system(size: DesignTokens.fontSm))
            .foregroundStyle(Color(hex: "#7A6A58"))
    }
    .padding(DesignTokens.paddingMd)
    .frame(width: DesignTokens.popoverWidth)
    .environmentObject(ThemeManager())
}
