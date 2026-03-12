//
//  SectionDivider.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//

import SwiftUI

// MARK: - SectionDivider
// A thin horizontal line used to separate sections within a panel.
// Replaces all plain Divider() calls in the app.
// Colour comes from the active theme's border token.
//
// Usage:
//   SectionDivider()

struct SectionDivider: View {

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Rectangle()
            .fill(themeManager.border)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .padding(.vertical, DesignTokens.paddingXs)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 0) {
        Text("Above the divider")
            .font(.system(size: DesignTokens.fontSm))
            .foregroundStyle(Color(hex: "#2C2017"))

        SectionDivider()

        Text("Below the divider")
            .font(.system(size: DesignTokens.fontSm))
            .foregroundStyle(Color(hex: "#2C2017"))
    }
    .padding(DesignTokens.paddingMd)
    .frame(width: DesignTokens.popoverWidth)
    .environmentObject(ThemeManager())
}
