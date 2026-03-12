//
//  TetherButton.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//

import SwiftUI

// MARK: - Button Style
// Two styles are available throughout the app.
// primary  — filled accent colour background, used for main actions.
// secondary — plain, no background, used for supporting actions and footer icons.

enum TetherButtonStyle {
    case primary
    case secondary
}

// MARK: - TetherButton
// The single reusable button component for the entire app.
// Always uses theme colours and design tokens — no hardcoded values.
//
// Usage examples:
//   TetherButton("Sync Now", icon: "arrow.triangle.2.circlepath") { }
//   TetherButton("Quit", icon: "rectangle.portrait.and.arrow.right", style: .secondary) { }
//   TetherButton(icon: "gear", style: .secondary) { }  ← icon only, no label

struct TetherButton: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let label:   String?
    let icon:    String?
    let style:   TetherButtonStyle
    let isLoading: Bool
    let action:  () -> Void

    // Full init — all parameters available
    init(
        _ label: String? = nil,
        icon: String? = nil,
        style: TetherButtonStyle = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label     = label
        self.icon      = icon
        self.style     = style
        self.isLoading = isLoading
        self.action    = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.spacingXs) {

                // Loading spinner — replaces icon when isLoading is true
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: DesignTokens.iconSm, height: DesignTokens.iconSm)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: DesignTokens.iconSm))
                }

                if let label = label {
                    Text(label)
                        .font(.system(size: DesignTokens.fontSm, weight: style == .primary ? .medium : .regular))
                }
            }
            .frame(maxWidth: style == .primary ? .infinity : nil)
            .padding(.vertical, style == .primary ? DesignTokens.paddingXs : 0)
        }
        .buttonStyle(TetherNativeButtonStyle(
            style: style,
            themeManager: themeManager
        ))
    }
}

// MARK: - Native Button Style
// Applies the correct colours and hover behaviour depending on the button style.
// Built on top of Apple's ButtonStyle protocol for full HIG compliance.

private struct TetherNativeButtonStyle: ButtonStyle {

    let style:        TetherButtonStyle
    let themeManager: ThemeManager

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor(pressed: configuration.isPressed))
            .background(
                Group {
                    if style == .primary {
                        RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                            .fill(backgroundColor(pressed: configuration.isPressed))
                    }
                }
            )
            .opacity(configuration.isPressed && style == .secondary ? 0.6 : 1.0)
            .animation(.easeInOut(duration: DesignTokens.animFast), value: configuration.isPressed)
    }

    private func foregroundColor(pressed: Bool) -> Color {
        switch style {
        case .primary:
            return themeManager.accentForeground
        case .secondary:
            return themeManager.textSecondary
        }
    }

    private func backgroundColor(pressed: Bool) -> Color {
        pressed
            ? themeManager.accent.opacity(0.8)
            : themeManager.accent
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: DesignTokens.spacingMd) {
        TetherButton("Connect Google Account", icon: "person.crop.circle.badge.plus") { }
        TetherButton("Sync Now", icon: "arrow.triangle.2.circlepath") { }
        TetherButton("Connecting...", icon: "arrow.triangle.2.circlepath", isLoading: true) { }
        TetherButton("Quit", icon: "rectangle.portrait.and.arrow.right", style: .secondary) { }
        TetherButton(icon: "gear", style: .secondary) { }
    }
    .padding(DesignTokens.paddingMd)
    .frame(width: DesignTokens.popoverWidth)
    .environmentObject(ThemeManager())
}
