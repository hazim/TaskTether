//
//  TodayView.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//

import SwiftUI

// MARK: - TodayView
// The Today panel. Slides out to the left of the main popover.
// Width: 300px. Height matches the active main panel (Compact or Expanded).
//
// Layout:
//   1. Header  — day name · date + add button
//   2. Content — scrollable task list, or empty state

struct TodayView: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let tasks:           [TetherTaskItem]
    let onToggle:        (String) -> Void
    let onTomorrow:      (String) -> Void
    let onDelete:        (String) -> Void
    let onLinkTapped:    (String, URL) -> Void
    let onSubtaskToggle: (String, String) -> Void
    let onAddTask:       () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Rectangle()
                .fill(themeManager.border)
                .frame(height: 1)
            taskContent
        }
        .frame(width: DesignTokens.popoverWidth)
        .background(themeManager.backgroundPrimary)
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            dateBadge
            Spacer()
            addButton
        }
        .padding(.horizontal, DesignTokens.paddingMd)
        .padding(.vertical, DesignTokens.paddingMd - 2)
        .background(themeManager.backgroundSecondary)
    }

    private var dateBadge: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(dayName)
                .font(.system(size: DesignTokens.fontMd, weight: .semibold))
                .foregroundStyle(themeManager.textPrimary)
                .kerning(-0.02 * DesignTokens.fontMd)

            Text("·")
                .font(.system(size: DesignTokens.fontMd))
                .foregroundStyle(themeManager.textTertiary)

            Text(shortDate)
                .font(.system(size: DesignTokens.fontMd, weight: .semibold))
                .foregroundStyle(themeManager.textSecondary)
                .kerning(-0.02 * DesignTokens.fontMd)
        }
    }

    private var addButton: some View {
        Button(action: onAddTask) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(themeManager.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(themeManager.surface2))
        }
        .buttonStyle(.plain)
        .help(String(localized: "today.add.tooltip"))
    }

    // MARK: Task Content

    @ViewBuilder
    private var taskContent: some View {
        if tasks.isEmpty {
            TodayEmptyState()
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(tasks) { task in
                        TaskRow(
                            task:            task,
                            onToggle:        { onToggle(task.id) },
                            onTomorrow:      { onTomorrow(task.id) },
                            onDelete:        { onDelete(task.id) },
                            onLinkTapped:    task.url != nil ? { onLinkTapped(task.id, task.url!) } : nil,
                            onSubtaskToggle: { subtaskId in onSubtaskToggle(task.id, subtaskId) }
                        )

                        if task.id != tasks.last?.id {
                            Rectangle()
                                .fill(themeManager.border.opacity(0.4))
                                .frame(height: 1)
                                .padding(.leading, DesignTokens.paddingMd)
                        }
                    }
                }
            }
        }
    }

    // MARK: Date Helpers

    private var dayName: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    private var shortDate: String {
        let f = DateFormatter()
        f.dateFormat = "d MMMM"
        return f.string(from: Date())
    }
}

// MARK: - TodayEmptyState

private struct TodayEmptyState: View {

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: DesignTokens.spacingMd) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: DesignTokens.iconLg, weight: .thin))
                .foregroundStyle(themeManager.textTertiary)

            VStack(spacing: DesignTokens.spacingXs) {
                Text(String(localized: "today.empty.title"))
                    .font(.system(size: DesignTokens.fontSm, weight: .medium))
                    .foregroundStyle(themeManager.textSecondary)

                Text(String(localized: "today.empty.subtitle"))
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundStyle(themeManager.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.paddingLg)
    }
}

// MARK: - Localisation keys to add to Localizable.xcstrings
// today.add.tooltip    → "Add task"
// today.empty.title    → "You're all caught up."
// today.empty.subtitle → "Nothing due in your TaskTether list today."

// MARK: - Preview

#Preview {
    TodayView(
        tasks: [
            TetherTaskItem(
                id: "1",
                title: "Review pull request #42",
                isCompleted: true,
                url: nil,
                subtasks: []
            ),
            TetherTaskItem(
                id: "2",
                title: "Write unit tests for auth module",
                isCompleted: false,
                url: URL(string: "https://example.com"),
                subtasks: [
                    TetherSubtaskItem(id: "2a", title: "Write login tests",          isCompleted: true,  url: nil),
                    TetherSubtaskItem(id: "2b", title: "Write token refresh tests",  isCompleted: false, url: nil)
                ]
            ),
            TetherTaskItem(
                id: "3",
                title: "Call with client re: scope",
                isCompleted: false,
                url: URL(string: "https://example.com"),
                subtasks: []
            ),
            TetherTaskItem(
                id: "4",
                title: "Refactor settings panel",
                isCompleted: false,
                url: nil,
                subtasks: [
                    TetherSubtaskItem(id: "4a", title: "Extract theme component",  isCompleted: false, url: nil),
                    TetherSubtaskItem(id: "4b", title: "Add sync interval picker", isCompleted: false, url: nil),
                    TetherSubtaskItem(id: "4c", title: "Wire up save button",      isCompleted: false, url: nil)
                ]
            )
        ],
        onToggle:        { _ in },
        onTomorrow:      { _ in },
        onDelete:        { _ in },
        onLinkTapped:    { _, _ in },
        onSubtaskToggle: { _, _ in },
        onAddTask:       {}
    )
    .environmentObject(ThemeManager())
}
