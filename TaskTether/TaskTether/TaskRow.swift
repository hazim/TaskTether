//
//  TaskRow.swift
//  TaskTether
//
//  Created by Hazim Sami on 12/03/2026.
//  Updated: 13/03/2026 · 19:30
//

import SwiftUI

// MARK: - TetherTaskItem
// A lightweight display model for a task row.
// This is not the sync model (TetherTask) — it's purely for rendering.
// In Group 4, real TetherTask objects will be mapped to this.

struct TetherTaskItem: Identifiable {
    let id:          String
    var title:       String
    var isCompleted: Bool
    var url:         URL?
    var subtasks:    [TetherSubtaskItem]
}

struct TetherSubtaskItem: Identifiable {
    let id:          String
    var title:       String
    var isCompleted: Bool
    var url:         URL?
}

// MARK: - TaskRow
// A single task row in the Today panel.
// Layout:
//   [ checkbox ] [ label ] [ link icon? ]   [ hover: edit | link? | tomorrow | delete | drag ]
//
// On hover, a blurred overlay fades in from the right with action buttons.
// Subtasks (if any) are always visible beneath the parent row, indented.
// Completed tasks show a strikethrough label and dimmed appearance.
//
// Callbacks are used for all actions — this view has no business logic.

struct TaskRow: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let task:            TetherTaskItem
    let isEditing:       Bool
    let onToggle:        () -> Void
    let onTomorrow:      () -> Void
    let onDelete:        () -> Void
    let onEdit:          () -> Void
    let onCommit:        (String) -> Void
    let onLinkTapped:    (() -> Void)?
    let onSubtaskToggle: (String) -> Void

    @State private var isHovered   = false
    @State private var dragOffset  = CGFloat.zero
    @State private var isDragging  = false
    @State private var editBuffer  = ""

    // How far right the user needs to drag to trigger "move to tomorrow"
    private let swipeThreshold: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Main Row
            ZStack(alignment: .trailing) {

                // Tomorrow hint — revealed behind the row as the user swipes right.
                // Fades in proportionally to drag distance.
                HStack {
                    Spacer()
                    HStack(spacing: DesignTokens.spacingXs) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: DesignTokens.fontSm, weight: .medium))
                        Text(String(localized: "task.tomorrow.hint"))
                            .font(.system(size: DesignTokens.fontSm, weight: .medium))
                    }
                    .foregroundStyle(themeManager.accent)
                    .padding(.trailing, DesignTokens.paddingMd)
                    .opacity(min(dragOffset / swipeThreshold, 1.0))
                }

                // Base row content — slides with the drag offset
                HStack(spacing: DesignTokens.spacingSm - 1) {

                    TaskCheckbox(isCompleted: task.isCompleted) {
                        onToggle()
                    }

                    if isEditing {
                        // MARK: Inline Edit TextField
                        TextField("", text: $editBuffer)
                            .font(.system(size: DesignTokens.fontSm))
                            .foregroundStyle(themeManager.textPrimary)
                            .textFieldStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onSubmit { commitEdit() }
                            .onExitCommand { cancelEdit() }
                            .onAppear { editBuffer = task.title }
                    } else {
                        Text(task.title)
                            .font(.system(size: DesignTokens.fontSm))
                            .foregroundStyle(
                                task.isCompleted
                                    ? themeManager.textTertiary
                                    : themeManager.textPrimary
                            )
                            .strikethrough(task.isCompleted, color: themeManager.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Persistent link icon — non-interactive visual indicator only
                        if task.url != nil {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 9))
                                .foregroundStyle(themeManager.accent.opacity(0.5))
                        }
                    }
                }
                .padding(.vertical, DesignTokens.paddingXs + 3)
                .padding(.leading, DesignTokens.paddingMd)
                .padding(.trailing, DesignTokens.paddingSm)
                .background(isHovered ? themeManager.surface : Color.clear)
                .offset(x: dragOffset)
                // highPriorityGesture wins over the ScrollView's scroll recogniser.
                // Without this, horizontal swipes are stolen by the vertical ScrollView on macOS.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            // Only respond to predominantly horizontal drags
                            let h = abs(value.translation.width)
                            let v = abs(value.translation.height)
                            guard value.translation.width > 0, h > v else { return }
                            isDragging = true
                            dragOffset = min(value.translation.width * 0.6, swipeThreshold * 1.4)
                        }
                        .onEnded { _ in
                            isDragging = false
                            if dragOffset >= swipeThreshold {
                                withAnimation(.easeIn(duration: DesignTokens.animFast)) {
                                    dragOffset = 300
                                }
                                DispatchQueue.main.asyncAfter(
                                    deadline: .now() + DesignTokens.animFast
                                ) { onTomorrow() }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )

                // MARK: Hover Action Overlay
                // Hidden while dragging or editing
                if isHovered && !isDragging && !isEditing {
                    HStack(spacing: 2) {
                        LinearGradient(
                            gradient: Gradient(colors: [Color.clear, themeManager.surface]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 20)

                        HStack(spacing: 2) {
                            if let onLink = onLinkTapped {
                                RowActionButton(
                                    icon: "arrow.up.forward.square",
                                    role: .normal,
                                    action: onLink
                                )
                            }
                            RowActionButton(icon: "square.and.pencil", role: .normal,  action: onEdit)
                            RowActionButton(icon: "arrow.right",   role: .normal,      action: onTomorrow)
                            RowActionButton(icon: "trash",         role: .destructive, action: onDelete)
                        }
                        .padding(.trailing, DesignTokens.paddingXs + 2)
                        .background(themeManager.surface)
                    }
                    .transition(.opacity.animation(.easeInOut(duration: DesignTokens.animFast)))
                }
            }
            // .contentShape ensures the full row width triggers hover, not just text.
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: DesignTokens.animFast)) {
                    isHovered = hovering
                }
            }
            .animation(.easeInOut(duration: DesignTokens.animFast), value: task.isCompleted)

            // MARK: Subtask Rows
            // Always visible if subtasks exist — indented beneath the parent.
            // When editing ends (isEditing goes false) commit if title changed.
            if !task.subtasks.isEmpty {
                ForEach(task.subtasks) { subtask in
                    SubtaskRow(
                        subtask:  subtask,
                        onToggle: { onSubtaskToggle(subtask.id) },
                        onDelete: { /* handled in Group 4 */ }
                    )
                }
            }
        }
        .onChange(of: isEditing) { editing in
            if !editing { commitEdit() }
        }
    }

    // MARK: - Edit Helpers

    private func commitEdit() {
        let trimmed = editBuffer.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { cancelEdit(); return }
        onCommit(trimmed)
    }

    private func cancelEdit() {
        // Notify with the original title so the parent clears editingTaskId
        // without changing the stored value.
        onCommit(task.title)
    }
}

// MARK: - SubtaskRow
// A subtask row — indented version of TaskRow without the tomorrow arrow.

private struct SubtaskRow: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let subtask:  TetherSubtaskItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .trailing) {

            HStack(spacing: DesignTokens.spacingSm - 1) {
                // Indent
                Color.clear.frame(width: DesignTokens.paddingMd)

                // Smaller checkbox for subtasks
                TaskCheckbox(isCompleted: subtask.isCompleted, size: .small) {
                    onToggle()
                }

                Text(subtask.title)
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundStyle(
                        subtask.isCompleted
                            ? themeManager.textTertiary
                            : themeManager.textSecondary
                    )
                    .strikethrough(subtask.isCompleted, color: themeManager.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if subtask.url != nil {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 8))
                        .foregroundStyle(themeManager.accent.opacity(0.5))
                }
            }
            .padding(.vertical, DesignTokens.paddingXs + 1)
            .padding(.trailing, DesignTokens.paddingSm)
            .background(
                isHovered ? themeManager.surface : Color.clear
            )

            // Hover actions for subtask — link + delete only (no tomorrow arrow)
            if isHovered {
                HStack(spacing: 2) {
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, themeManager.surface]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 20)

                    HStack(spacing: 2) {
                        if subtask.url != nil {
                            RowActionButton(icon: "arrow.up.forward.square", role: .normal, action: {})
                        }
                        RowActionButton(icon: "trash", role: .destructive, action: onDelete)
                    }
                    .padding(.trailing, DesignTokens.paddingXs + 2)
                    .background(themeManager.surface)
                }
                .transition(.opacity.animation(.easeInOut(duration: DesignTokens.animFast)))
            }
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignTokens.animFast)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - TaskCheckbox
// The circular checkbox used for both tasks and subtasks.
// Size enum controls whether it renders at task or subtask scale.

enum CheckboxSize { case normal, small }

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
                        Circle()
                            .fill(isCompleted ? themeManager.accent : Color.clear)
                    )
                    .frame(width: diameter, height: diameter)

                // Checkmark — SF Symbol, only visible when completed
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: tickSize, weight: .bold))
                        .foregroundStyle(themeManager.accentForeground)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: DesignTokens.animFast), value: isCompleted)
    }
}

// MARK: - RowActionButton
// A small circular action button used in the hover overlay.
// Normal role: surface2 background on hover, textSecondary icon.
// Destructive role: danger background on hover, white icon.

enum RowActionRole { case normal, destructive }

private struct RowActionButton: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let icon:   String
    let role:   RowActionRole
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(
                    role == .destructive && isHovered
                        ? Color.white
                        : themeManager.textSecondary
                )
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(buttonBackground)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: DesignTokens.animFast)) {
                isHovered = hovering
            }
        }
    }

    private var buttonBackground: Color {
        guard isHovered else { return Color.clear }
        return role == .destructive ? themeManager.danger : themeManager.surface2
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 0) {
        TaskRow(
            task: TetherTaskItem(
                id: "1",
                title: "Review pull request #42",
                isCompleted: true,
                url: nil,
                subtasks: []
            ),
            isEditing: false,
            onToggle: {}, onTomorrow: {}, onDelete: {}, onEdit: {}, onCommit: { _ in },
            onLinkTapped: nil, onSubtaskToggle: { _ in }
        )

        TaskRow(
            task: TetherTaskItem(
                id: "2",
                title: "Write unit tests for auth module",
                isCompleted: false,
                url: URL(string: "https://example.com"),
                subtasks: [
                    TetherSubtaskItem(id: "2a", title: "Write login tests", isCompleted: true, url: nil),
                    TetherSubtaskItem(id: "2b", title: "Write token refresh tests", isCompleted: false, url: nil)
                ]
            ),
            isEditing: false,
            onToggle: {}, onTomorrow: {}, onDelete: {}, onEdit: {}, onCommit: { _ in },
            onLinkTapped: {}, onSubtaskToggle: { _ in }
        )

        TaskRow(
            task: TetherTaskItem(
                id: "3",
                title: "Call with client re: scope",
                isCompleted: false,
                url: URL(string: "https://example.com"),
                subtasks: []
            ),
            isEditing: true,
            onToggle: {}, onTomorrow: {}, onDelete: {}, onEdit: {}, onCommit: { _ in },
            onLinkTapped: {}, onSubtaskToggle: { _ in }
        )
    }
    .frame(width: DesignTokens.popoverWidth)
    .environmentObject(ThemeManager())
}
