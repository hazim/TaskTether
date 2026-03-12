//
//  TetherMaterial.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//

import SwiftUI

// MARK: - TetherMaterial
// This is the only place in the entire codebase where the macOS version check
// for Liquid Glass lives. Every view that needs a material background applies
// .tetherMaterial() — nothing else needs to know about version availability.
//
// macOS 26+  → Liquid Glass (.glassEffect)
// macOS 12–25 → .ultraThinMaterial (the standard translucent system material)

struct TetherMaterialModifier: ViewModifier {

    @EnvironmentObject private var themeManager: ThemeManager

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            // Liquid Glass — the new material introduced at WWDC 2025.
            // .interactive allows the glass to respond to content behind it.
            content
                .glassEffect(.regular.interactive())
        } else {
            // Fallback for macOS 12–25.
            // ultraThinMaterial gives a translucent frosted appearance
            // that blends with the system desktop behind the popover.
            content
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.radiusLg)
                        .fill(.ultraThinMaterial)
                )
                .background(
                    // A subtle tint from the active theme sits behind the material,
                    // so each theme still feels distinct even with the fallback.
                    RoundedRectangle(cornerRadius: DesignTokens.radiusLg)
                        .fill(themeManager.backgroundPrimary.opacity(0.85))
                )
        }
    }
}

// MARK: - View Extension
// This is what views actually call. Instead of writing the modifier directly,
// any view can just do: .tetherMaterial()

extension View {
    func tetherMaterial() -> some View {
        self.modifier(TetherMaterialModifier())
    }
}
