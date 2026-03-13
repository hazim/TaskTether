//
//  TodayView.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//  Updated: 13/03/2026 · 19:50
//

import SwiftUI
import UniformTypeIdentifiers

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
    let onEdit:          (String) -> Void
    let onCommit:        (String, String) -> Void   // (taskId, newTitle) — on Enter/blur
    let onLinkTapped:    (String, URL) -> Void
    let onSubtaskToggle: (String, String) -> Void
    let onMove:          (String, String) -> Void
    let onAddTask:       (String) -> Void      // called with the new task title on commit

    @State private var editingTaskId:  String?
    @State private var isAddingTask:   Bool   = false
    @State private var newTaskBuffer:  String = ""



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
        // Padding matches Zone 1 (AppTitleBar) exactly: top 14, bottom 13, horizontal 16
        // so the header bottom border aligns with Zone 1's bottom border when Today is open.
        .padding(.top, 14)
        .padding(.bottom, 13)
        .padding(.horizontal, DesignTokens.paddingMd)
        .background(themeManager.backgroundSecondary)
    }

    private var dateBadge: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(dayName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(themeManager.textPrimary)
                .kerning(-0.02 * 16)

            Text("·")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(themeManager.textTertiary)

            Text(shortDate)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(themeManager.textSecondary)
                .kerning(-0.02 * 16)
        }
    }

    private var addButton: some View {
        Button {
            editingTaskId  = nil
            newTaskBuffer  = ""
            isAddingTask   = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(themeManager.textSecondary)
                .frame(width: 28, height: 28)
                // Matches TitleBarIconButton style: transparent bg, surface2 on hover
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(themeManager.surface2.opacity(0))
                )
        }
        .buttonStyle(.plain)
        .help(String(localized: "today.add.tooltip"))
    }

    // MARK: Task Content

    @ViewBuilder
    private var taskContent: some View {
        if tasks.isEmpty && !isAddingTask {
            TodayEmptyState()
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {

                    // New task row — always at the top, only visible while adding
                    if isAddingTask {
                        AddTaskRow(
                            buffer:   $newTaskBuffer,
                            onCommit: {
                                let trimmed = newTaskBuffer.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty { onAddTask(trimmed) }
                                isAddingTask  = false
                                newTaskBuffer = ""
                            },
                            onCancel: {
                                isAddingTask  = false
                                newTaskBuffer = ""
                            }
                        )
                        if !tasks.isEmpty {
                            Rectangle()
                                .fill(themeManager.border.opacity(0.4))
                                .frame(height: 1)
                                .padding(.leading, DesignTokens.paddingMd)
                        }
                    }

                    ForEach(tasks) { task in
                        TaskRow(
                            task:            task,
                            isEditing:       editingTaskId == task.id,
                            onToggle:        { onToggle(task.id) },
                            onTomorrow:      { onTomorrow(task.id) },
                            onDelete:        { onDelete(task.id) },
                            onEdit:          {
                                                 onEdit(task.id)
                                                 editingTaskId = task.id
                                             },
                            onCommit:        { newTitle in
                                                 onCommit(task.id, newTitle)
                                                 editingTaskId = nil
                                             },
                            onCancel:        { editingTaskId = nil },
                            onLinkTapped:    task.url != nil ? { onLinkTapped(task.id, task.url!) } : nil,
                            onSubtaskToggle: { subtaskId in onSubtaskToggle(task.id, subtaskId) }
                        )
                        // Drag-to-reorder: deferred — .onDrag/.onDrop intercept
                        // button taps inside the row on macOS. Will be implemented
                        // with a custom DragGesture approach in a later pass.

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

// MARK: - TaskDropDelegate
// Handles drop events for drag-to-reorder in the Today panel.
// When a dragged row is dropped onto a target row, fires onMove(fromId, toId).

private struct TaskDropDelegate: DropDelegate {

    let targetId:   String
    @Binding var draggingId: String?
    let onMove:     (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let fromId = draggingId, fromId != targetId else { return }
        onMove(fromId, targetId)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool { true }
}

// MARK: - AddTaskRow
// Appears at the top of the task list when the + button is tapped.
// Styled to match a TaskRow in edit mode — unchecked placeholder circle + TextField.
// Return commits, Escape cancels, clicking outside commits if buffer is non-empty.

private struct AddTaskRow: View {

    @EnvironmentObject private var themeManager: ThemeManager

    @Binding var buffer:   String
    let onCommit:          () -> Void
    let onCancel:          () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DesignTokens.spacingSm - 1) {

            // Placeholder checkbox — matches CheckboxButton's 32×32 hit target
            // frame so AddTaskRow and TaskRow are identical heights.
            Circle()
                .strokeBorder(themeManager.border, lineWidth: 1.5)
                .frame(width: 16, height: 16)
                .frame(width: 32, height: 32)

            TextField(String(localized: "today.add.placeholder"), text: $buffer)
                .font(.system(size: DesignTokens.fontSm))
                .foregroundStyle(themeManager.textPrimary)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused($isFocused)
                .onSubmit { onCommit() }
                .onExitCommand { onCancel() }
        }
        .padding(.vertical, DesignTokens.paddingXs + 3)
        .padding(.leading, DesignTokens.paddingMd)
        .padding(.trailing, DesignTokens.paddingSm)
        .background(themeManager.surface)
        .onAppear {
            // MenuBarExtra windows are not always key on first appearance.
            // Make the window key explicitly before setting focus so the
            // TextField receives input without requiring a second click.
            NSApp.keyWindow?.makeKey()
            isFocused = true
        }
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
        onEdit:          { _ in },
        onCommit:        { _, _ in },
        onLinkTapped:    { _, _ in },
        onSubtaskToggle: { _, _ in },
        onMove:          { _, _ in },
        onAddTask:       { _ in }
    )
    .environmentObject(ThemeManager())
}
