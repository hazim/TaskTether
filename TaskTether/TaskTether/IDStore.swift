//
//  IDStore.swift
//  TaskTether
//
//  Created: 13/03/2026 · 22:00
//

import Foundation

// MARK: - IDStore
// Persists two things in UserDefaults:
//   1. Cross-reference: remindersId → googleTasksId
//   2. Display order:   ordered array of remindersIds
//
// This is the single source of truth for which Reminder maps to which
// Google Task. Without it, the sync engine would have to match by title,
// which breaks on any rename and creates duplicates.

final class IDStore {

    // MARK: - Keys

    private let refsKey  = "tasktether_id_refs"
    private let orderKey = "tasktether_task_order"
    private let defaults = UserDefaults.standard

    // MARK: - Cross Reference

    // All stored links: remindersId → googleTasksId
    private(set) var refs: [String: String] {
        get { defaults.dictionary(forKey: refsKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: refsKey) }
    }

    // Link a Reminders task to a Google Task.
    func link(remindersId: String, googleId: String) {
        var current = refs
        current[remindersId] = googleId
        refs = current
        // Add to order if not already tracked.
        if !order.contains(remindersId) {
            var currentOrder = order
            currentOrder.append(remindersId)
            order = currentOrder
        }
    }

    // Look up the Google Task ID for a given Reminders ID.
    func googleId(for remindersId: String) -> String? {
        refs[remindersId]
    }

    // Look up the Reminders ID for a given Google Task ID.
    func remindersId(for googleId: String) -> String? {
        refs.first(where: { $0.value == googleId })?.key
    }

    // Whether a Reminders task is linked to a Google Task.
    func isLinked(remindersId: String) -> Bool {
        refs[remindersId] != nil
    }

    // Remove all cross-references for a Reminders ID (e.g. on deletion).
    func unlink(remindersId: String) {
        var current = refs
        current.removeValue(forKey: remindersId)
        refs = current
        var currentOrder = order
        currentOrder.removeAll { $0 == remindersId }
        order = currentOrder
    }

    // Total number of linked task pairs.
    var linkedCount: Int { refs.count }

    // MARK: - Display Order

    // Ordered array of remindersIds — drives the display order in TaskTether
    // and is pushed to Google Tasks via the move endpoint after any reorder.
    var order: [String] {
        get { defaults.array(forKey: orderKey) as? [String] ?? [] }
        set { defaults.set(newValue, forKey: orderKey) }
    }

    // Position (0-based) of a task in the display order.
    func position(of remindersId: String) -> Int {
        order.firstIndex(of: remindersId) ?? order.count
    }

    // Replace the full order — called after a drag-to-reorder gesture.
    func setOrder(_ remindersIds: [String]) {
        order = remindersIds
    }

    // Append a newly added task at the top of the incomplete group.
    // completedIds: set of remindersIds that are currently completed.
    func insertAtTop(remindersId: String, completedIds: Set<String>) {
        var currentOrder = order.filter { $0 != remindersId }
        let firstCompleted = currentOrder.firstIndex(where: { completedIds.contains($0) })
            ?? currentOrder.count
        currentOrder.insert(remindersId, at: firstCompleted > 0 ? 0 : 0)
        order = currentOrder
    }

    // Move a completed task to the end of the order array.
    func moveToEnd(remindersId: String) {
        var currentOrder = order.filter { $0 != remindersId }
        currentOrder.append(remindersId)
        order = currentOrder
    }

    // Move a task back before the first completed task (un-completing).
    func moveBeforeCompleted(remindersId: String, completedIds: Set<String>) {
        var currentOrder = order.filter { $0 != remindersId }
        let insertAt = currentOrder.firstIndex(where: { completedIds.contains($0) })
            ?? currentOrder.count
        currentOrder.insert(remindersId, at: insertAt)
        order = currentOrder
    }

    // MARK: - Debug

    #if DEBUG
    func dump() {
        print("IDStore refs (\(refs.count)): \(refs)")
        print("IDStore order (\(order.count)): \(order)")
    }
    #endif
}
