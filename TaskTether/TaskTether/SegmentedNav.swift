//
//  SegmentedNav.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//  Redesigned: 13/03/2026
//

import SwiftUI

// MARK: - Panel
// Single source of truth for which panel is active.

enum Panel: String, CaseIterable {
    case compact  = "compact"
    case expanded = "expanded"

    var labelKey: String {
        switch self {
        case .compact:  return "nav.compact"
        case .expanded: return "nav.expanded"
        }
    }
}

// MARK: - SegmentedNav
//
// Matches the HTML seg-pill exactly:
//   - Outer pill: rgba(0,0,0,0.08) rounded-8, padding 3px
//   - Active indicator: a single glass view that SLIDES between segments
//     using matchedGeometryEffect — never redraws, just moves
//   - Spring: response 0.3, dampingFraction 0.7 (overshoot feel)
//
// The key difference from the previous implementation:
//   Before: each button had its own background — entire button redrawn on switch
//   Now:    one shared indicator slides underneath all buttons — smooth glide

struct SegmentedNav: View {

    @EnvironmentObject private var themeManager: ThemeManager
    @Binding var selection: Panel
    @Namespace private var pillIndicator

    // Local state drives the pill animation independently from the binding.
    // The binding changes instantly (no animation) to keep window resize instant.
    // This state animates with a spring so the pill slides smoothly.
    @State private var animatedSelection: Panel = .expanded

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Panel.allCases, id: \.self) { panel in
                segmentButton(for: panel)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.08))
        )
        // When the binding changes, animate the local pill indicator with a spring.
        // This is safe because animatedSelection only affects position within the pill —
        // it never changes the window size.
        .onChange(of: selection) { _, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                animatedSelection = newValue
            }
        }
        .onAppear {
            animatedSelection = selection
        }
    }

    // MARK: - Segment Button

    @ViewBuilder
    private func segmentButton(for panel: Panel) -> some View {
        // isActive uses animatedSelection for the pill indicator and font weight,
        // but the tap changes the binding immediately with no animation.
        let isActive = animatedSelection == panel

        Button {
            // Change binding with NO animation — window resize must be instant
            // to avoid MenuBarExtra constraint loop crash.
            var t = Transaction(animation: nil)
            t.disablesAnimations = true
            withTransaction(t) { selection = panel }
        } label: {
            Text(String(localized: String.LocalizationValue(panel.labelKey)))
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? themeManager.textPrimary : themeManager.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .padding(.horizontal, 4)
                .background {
                    if isActive {
                        glassIndicator
                            .matchedGeometryEffect(id: "segIndicator", in: pillIndicator)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Glass Indicator
    // Single view that slides between segments.
    // macOS 26+: Liquid Glass
    // macOS 12–25: white frosted glass + ring — matches HTML rgba(255,255,255,0.55)
    //              with backdrop-filter blur and box-shadow

    @ViewBuilder
    private var glassIndicator: some View {
        if #available(macOS 26, *) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.clear)
                .glassEffect(.regular)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var panel: Panel = .compact

    VStack(spacing: 16) {
        SegmentedNav(selection: $panel)
        Text("Active: \(panel.rawValue)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(hex: "#7A6A58"))
    }
    .padding(14)
    .background(Color(hex: "#E8DDD0"))
    .frame(width: 300)
    .environmentObject(ThemeManager())
}
