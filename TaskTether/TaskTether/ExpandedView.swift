//
//  ExpandedView.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//

import SwiftUI

// MARK: - ExpandedView
// The full productivity panel shown when the Expanded segment is selected.
// Layout (top to bottom):
//   1. Sync strip      — same as CompactView
//   2. Service columns — same as CompactView
//   3. Productivity zone:
//        a. Today score — big bold number, delta vs yesterday, tasks count
//        b. Divider
//        c. Yesterday score — dimmed, smaller
//        d. Divider
//        e. 7-day ECG sparkline
//   4. Sync button
//
// All data is passed in from the parent view.
// This view contains no business logic — display only.

struct ExpandedView: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let remindersStatus:   ConnectionStatus
    let googleTasksStatus: ConnectionStatus
    let lastSyncText:      String
    let isSyncing:         Bool

    // Today's score — 0 to 100
    let todayScore:        Int
    let todayCompleted:    Int
    let todayTotal:        Int

    // Yesterday's score — 0 to 100
    let yesterdayScore:    Int
    let yesterdayCompleted: Int
    let yesterdayTotal:    Int

    // Delta direction and value — e.g. "+12% vs yesterday"
    let deltaValue:        Int   // positive = up, negative = down, 0 = no change

    // 7 completion percentages oldest→newest, nil = no data
    let weekPercentages:   [Int?]

    let onSyncTapped:      () -> Void

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Sync Strip
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
            HStack(spacing: 0) {
                ServiceColumnExpanded(
                    name:   String(localized: "service.reminders"),
                    status: remindersStatus
                )

                Rectangle()
                    .fill(themeManager.border)
                    .frame(width: 1)

                ServiceColumnExpanded(
                    name:   String(localized: "service.googletasks"),
                    status: googleTasksStatus
                )
            }
            .background(themeManager.backgroundPrimary)

            Rectangle()
                .fill(themeManager.border)
                .frame(height: 1)

            // MARK: Productivity Zone
            VStack(spacing: 0) {

                // TODAY
                ProductivitySection(
                    label:     String(localized: "expanded.label.today"),
                    score:     todayScore,
                    completed: todayCompleted,
                    total:     todayTotal,
                    dimmed:    false,
                    delta:     deltaValue
                )

                // Divider
                Rectangle()
                    .fill(themeManager.border.opacity(0.6))
                    .frame(height: 1)
                    .padding(.vertical, DesignTokens.paddingXs)

                // YESTERDAY
                ProductivitySection(
                    label:     String(localized: "expanded.label.yesterday"),
                    score:     yesterdayScore,
                    completed: yesterdayCompleted,
                    total:     yesterdayTotal,
                    dimmed:    true,
                    delta:     nil
                )

                // Divider
                Rectangle()
                    .fill(themeManager.border.opacity(0.6))
                    .frame(height: 1)
                    .padding(.vertical, DesignTokens.paddingXs)

                // 7-DAY BAR CHART
                VStack(alignment: .leading, spacing: DesignTokens.spacingXs) {
                    Text(String(localized: "expanded.label.last7days"))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(themeManager.textTertiary)
                        .textCase(.uppercase)
                        .kerning(1.0)

                    BarChartView(percentages: weekPercentages)
                        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                }
                .padding(.top, DesignTokens.paddingXs)

            }
            .padding(.horizontal, DesignTokens.paddingMd)
            .padding(.vertical, DesignTokens.paddingSm + 2)
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

// MARK: - ServiceColumnExpanded
// Reused from CompactView — identical layout.

private struct ServiceColumnExpanded: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let name:   String
    let status: ConnectionStatus

    var body: some View {
        VStack(spacing: DesignTokens.spacingXs + 1) {
            StatusDot(status: status)

            Text(name)
                .font(.system(size: DesignTokens.fontSm, weight: .medium))
                .foregroundStyle(themeManager.textPrimary)

            Text(String(localized: String.LocalizationValue(status.labelKey)))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(statusColor)
                .kerning(0.4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.paddingSm + 2)
        .padding(.horizontal, DesignTokens.paddingSm)
    }

    private var statusColor: Color {
        switch status {
        case .connected: return themeManager.success
        case .syncing:   return themeManager.warning
        case .error:     return themeManager.danger
        }
    }
}

// MARK: - ProductivitySection
// The score block for Today and Yesterday.
// When dimmed = true, the score is rendered smaller and at reduced opacity.
// delta is only shown for Today (pass nil for Yesterday).

private struct ProductivitySection: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let label:     String
    let score:     Int
    let completed: Int
    let total:     Int
    let dimmed:    Bool
    let delta:     Int?   // nil = don't show delta

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXs) {

            // Row: label + delta
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(themeManager.textTertiary)
                    .textCase(.uppercase)
                    .kerning(1.0)

                Spacer()

                if let delta = delta, delta != 0 {
                    Text(deltaText(delta))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(delta > 0 ? themeManager.success : themeManager.danger)
                        .kerning(0.3)
                }
            }

            // Score block: big number + % + task count
            HStack(alignment: .bottom, spacing: DesignTokens.spacingSm) {

                // Big score number
                HStack(alignment: .bottom, spacing: 1) {
                    Text("\(score)")
                        .font(.system(
                            size: dimmed ? 30 : DesignTokens.fontScoreLabel,
                            weight: .semibold,
                            design: .default
                        ))
                        .foregroundStyle(themeManager.accent.opacity(dimmed ? 0.5 : 1.0))
                        .kerning(-0.05 * (dimmed ? 30 : DesignTokens.fontScoreLabel))
                        .monospacedDigit()

                    Text("%")
                        .font(.system(
                            size: dimmed ? 14 : 22,
                            weight: .light
                        ))
                        .italic()
                        .foregroundStyle(themeManager.accent.opacity(dimmed ? 0.4 : 0.65))
                        .padding(.bottom, dimmed ? 2 : 5)
                }

                Spacer()

                // Task count — bottom right
                Text("\(completed) / \(total) \(String(localized: "expanded.tasks.done"))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(themeManager.textTertiary.opacity(dimmed ? 0.55 : 1.0))
                    .padding(.bottom, dimmed ? 2 : 6)
            }
        }
        .padding(.vertical, DesignTokens.paddingXs + 2)
    }

    private func deltaText(_ value: Int) -> String {
        if value > 0 {
            return String(format: String(localized: "expanded.delta.up"), value)
        } else {
            return String(format: String(localized: "expanded.delta.down"), value)
        }
    }
}

// MARK: - Localisation keys to add to Localizable.xcstrings
// expanded.label.today      → "Today"
// expanded.label.yesterday  → "Yesterday"
// expanded.label.last7days  → "Last 7 Days"
// expanded.tasks.done       → "tasks done"

// MARK: - Preview
#Preview {
    ExpandedView(
        remindersStatus:    .connected,
        googleTasksStatus:  .connected,
        lastSyncText:       "4 min ago",
        isSyncing:          false,
        todayScore:         74,
        todayCompleted:     6,
        todayTotal:         8,
        yesterdayScore:     62,
        yesterdayCompleted: 5,
        yesterdayTotal:     8,
        deltaValue:         12,
        weekPercentages:    [100, nil, 0, 60, nil, 45, 74],
        onSyncTapped:       {}
    )
    .frame(width: DesignTokens.popoverWidth)
    .environmentObject(ThemeManager())
}
