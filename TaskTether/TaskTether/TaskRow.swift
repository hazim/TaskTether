//
//  TaskRow.swift
//  TaskTether
//
//  Created: 10/03/2026
//  Updated: 13/03/2026 · 22:00
//

import SwiftUI

// MARK: - TetherTaskItem (Display Model)

struct TetherTaskItem: Identifiable, Equatable {
    let id:          String
    var title:       String
    var isCompleted: Bool
    var isSubtask:   Bool
    var url:         URL?
    var subtasks:    [TetherSubtaskItem]
}

struct TetherSubtaskItem: Identifiable, Equatable {
    let id:          String
    var title:       String
    var isCompleted: Bool
    var url:         URL?
}

// MARK: - TaskRow
// Displays a single task: checkbox, title, optional link icon.
// No hover overlay, no edit mode, no swipe gestures.

struct TaskRow: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let task:     TetherTaskItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.spacingSm - 1) {

            // Subtask indent — adds leading space to align under parent's text
            if task.isSubtask {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(themeManager.textTertiary)
                    .padding(.leading, 8)
            }

            TaskCheckbox(isCompleted: task.isCompleted, action: onToggle)

            Text(task.title)
                .font(.system(size: DesignTokens.fontSm))
                .foregroundStyle(
                    task.isCompleted
                        ? themeManager.textTertiary
                        : themeManager.textPrimary
                )
                .strikethrough(task.isCompleted, color: themeManager.textTertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if task.url != nil {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(themeManager.textTertiary)
            }
        }
        .padding(.vertical, DesignTokens.paddingXs + 1)
        .padding(.leading, DesignTokens.paddingMd)
        .padding(.trailing, DesignTokens.paddingSm)
    }
}

// MARK: - TaskCheckbox

private enum CheckboxSize { case normal, small }

private struct TaskCheckbox: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let isCompleted: Bool
    var size: CheckboxSize = .normal
    let action: () -> Void

    private var diameter: CGFloat { size == .normal ? 16 : 12 }
    private var tickSize: CGFloat  { size == .normal ? 8  : 6  }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isCompleted ? themeManager.accent : themeManager.border,
                        lineWidth: 1.5
                    )
                    .background(
                        Circle().fill(isCompleted ? themeManager.accent : Color.clear)
                    )
                    .frame(width: diameter, height: diameter)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: tickSize, weight: .bold))
                        .foregroundStyle(themeManager.accentForeground)
                }
            }
            .frame(width: max(diameter, 32), height: max(diameter, 32))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: DesignTokens.animFast), value: isCompleted)
    }
}

// MARK: - Preview

#Preview("Incomplete") {
    TaskRow(
        task: TetherTaskItem(id: "1", title: "Review pull request #42",
                             isCompleted: false, isSubtask: false, url: nil, subtasks: []),
        onToggle: {}
    )
    .environmentObject(ThemeManager())
    .frame(width: 300)
}

#Preview("Completed") {
    TaskRow(
        task: TetherTaskItem(id: "2", title: "Write unit tests",
                             isCompleted: true, isSubtask: false, url: nil, subtasks: []),
        onToggle: {}
    )
    .environmentObject(ThemeManager())
    .frame(width: 300)
}

#Preview("With Link") {
    TaskRow(
        task: TetherTaskItem(id: "3", title: "Read the RFC",
                             isCompleted: false, isSubtask: false, url: URL(string: "https://example.com"), subtasks: []),
        onToggle: {}
    )
    .environmentObject(ThemeManager())
    .frame(width: 300)
}
