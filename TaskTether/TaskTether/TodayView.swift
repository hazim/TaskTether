//
//  TodayView.swift
//  TaskTether
//
//  Created: 10/03/2026
//  Updated: 13/03/2026 · 22:00
//

import SwiftUI

// MARK: - TodayView

struct TodayView: View {

    @EnvironmentObject private var themeManager: ThemeManager

    let tasks:    [TetherTaskItem]
    let onToggle: (String) -> Void
    let onAdd:    (String) -> Void

    @State private var newTaskText = ""
    @FocusState private var inputFocused: Bool

    private var showPlaceholder: Bool { newTaskText.isEmpty }

    var body: some View {
        VStack(spacing: 0) {

            // ── Persistent add field ─────────────────────────────────────
            // Always visible at the top. Clicking it gives immediate focus.
            // Enter commits and re-focuses so the next task can be typed
            // without an extra click.

            HStack(spacing: DesignTokens.spacingSm - 1) {

                // Placeholder circle matching TaskRow checkbox hit target
                Circle()
                    .strokeBorder(themeManager.border.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                    .frame(width: 32, height: 32)

                ZStack(alignment: .leading) {
                    // Explicit placeholder so it respects the active theme colour.
                    // SwiftUI's built-in placeholder ignores foregroundStyle.
                    if showPlaceholder {
                        Text(String(localized: "today.add.placeholder"))
                            .font(.system(size: DesignTokens.fontSm))
                            .foregroundStyle(themeManager.textTertiary)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $newTaskText)
                        .font(.system(size: DesignTokens.fontSm))
                        .foregroundStyle(themeManager.textPrimary)
                        .textFieldStyle(.plain)
                        .focused($inputFocused)
                        .onSubmit {
                            let trimmed = newTaskText.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            onAdd(trimmed)
                            newTaskText = ""
                            DispatchQueue.main.async { inputFocused = true }
                        }
                }
            }
            .padding(.vertical, DesignTokens.paddingXs + 1)
            .padding(.leading, DesignTokens.paddingMd)
            .padding(.trailing, DesignTokens.paddingSm)
            .background(themeManager.surface)
            .contentShape(Rectangle())
            .onTapGesture { inputFocused = true }

            Rectangle()
                .fill(themeManager.border.opacity(0.4))
                .frame(height: 1)

            // ── Task list ────────────────────────────────────────────────

            if tasks.isEmpty {
                TodayEmptyState()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.paddingLg)
            } else {
                // showsIndicators: true — scrollbar appears when content
                // exceeds the available height in both Compact and Expanded Today.
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(tasks) { task in
                            TaskRow(task: task, onToggle: { onToggle(task.id) })
                            if task.id != tasks.last?.id {
                                Rectangle()
                                    .fill(themeManager.border.opacity(0.4))
                                    .frame(height: 1)
                                    .padding(.leading, DesignTokens.paddingMd + 32)
                            }
                        }
                    }
                }
                // Tint scrollbar to match theme
                .scrollIndicatorsFlash(onAppear: false)
            }
        }
    }
}

// MARK: - TodayEmptyState

private struct TodayEmptyState: View {

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: DesignTokens.spacingSm) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(themeManager.textTertiary)
            Text(String(localized: "today.empty.title"))
                .font(.system(size: DesignTokens.fontSm, weight: .medium))
                .foregroundStyle(themeManager.textSecondary)
            Text(String(localized: "today.empty.subtitle"))
                .font(.system(size: DesignTokens.fontCaption))
                .foregroundStyle(themeManager.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, DesignTokens.paddingMd)
    }
}

// MARK: - Preview

#Preview {
    TodayView(
        tasks: [
            TetherTaskItem(id: "1", title: "Review PR #42", isCompleted: false, isSubtask: false,
                          url: nil, subtasks: []),
            TetherTaskItem(id: "2", title: "Write tests",   isCompleted: false, isSubtask: false,
                          url: URL(string: "https://example.com"), subtasks: []),
            TetherTaskItem(id: "3", title: "Done task",     isCompleted: true, isSubtask: false,
                          url: nil, subtasks: [])
        ],
        onToggle: { _ in },
        onAdd:    { _ in }
    )
    .environmentObject(ThemeManager())
    .frame(width: 300)
}
