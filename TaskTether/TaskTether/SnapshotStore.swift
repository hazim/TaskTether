//
//  SnapshotStore.swift
//  TaskTether
//
//  Created: 10/07/2026
//

import Foundation

// MARK: - SnapshotTask
// Persisted form of one task's last-synced state.
// Only the fields the diff compares are stored — together they are the
// baseline a three-way merge needs to tell "changed in Reminders" apart
// from "changed in Google" after a relaunch.

struct SnapshotTask: Codable {
    let remindersId:   String?
    let googleTasksId: String?
    // Nil only in a snapshot written before multi-list sync. load() treats a
    // single such row as "no usable baseline" and returns nil, which forces
    // one reconciliation sync (D8) — the path that never deletes.
    let listPairId:    String?
    let title:         String
    let notes:         String?
    let isCompleted:   Bool
    let dueDate:       Date?
}

// MARK: - SnapshotStore
// Persists the post-sync snapshot in UserDefaults so SyncEngine keeps its
// baseline across app restarts. Without this, previousSnapshot starts empty
// on every launch: the engine cannot attribute offline changes to the right
// side, Google silently wins every conflict, and stale ID links replay
// old deletions as if they just happened.

final class SnapshotStore {

    private let snapshotKey = "tasktether_sync_snapshot"
    private let lastSyncKey = "tasktether_last_sync_at"
    private let defaults    = UserDefaults.standard

    // MARK: - Read

    // Returns nil when no snapshot has ever been saved (first run) or the
    // stored data cannot be decoded. Callers must treat nil differently from
    // an empty list: nil means "no baseline exists — do not trust deletions".
    func load() -> [TetherTask]? {
        guard let data = defaults.data(forKey: snapshotKey),
              let decoded = try? JSONDecoder().decode([SnapshotTask].self, from: data)
        else { return nil }

        // Pre-multi-list rows carry no list attribution, so the per-pair diff
        // could not tell which pair they belonged to and would read every one
        // of them as "deleted from this list". Reject the whole snapshot
        // instead — the caller then runs a reconciliation sync (D8).
        guard !decoded.contains(where: { $0.listPairId == nil }) else { return nil }

        return decoded.map { snap in
            TetherTask(
                id:            UUID().uuidString,
                remindersId:   snap.remindersId,
                googleTasksId: snap.googleTasksId,
                listPairId:    snap.listPairId,
                title:         snap.title,
                notes:         snap.notes,
                isCompleted:   snap.isCompleted,
                dueDate:       snap.dueDate,
                lastModified:  .distantPast,
                source:        .both
            )
        }
    }

    // MARK: - Write

    func save(_ tasks: [TetherTask]) {
        let snaps = tasks.map { task in
            SnapshotTask(
                remindersId:   task.remindersId,
                googleTasksId: task.googleTasksId,
                listPairId:    task.listPairId,
                title:         task.title,
                notes:         task.notes,
                isCompleted:   task.isCompleted,
                dueDate:       task.dueDate
            )
        }
        if let data = try? JSONEncoder().encode(snaps) {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    // MARK: - Last Sync

    // Persisted alongside the snapshot — the reconciliation logic uses the
    // age of the last sync to decide whether deletions can be trusted.
    var lastSyncAt: Date? {
        get { defaults.object(forKey: lastSyncKey) as? Date }
        set { defaults.set(newValue, forKey: lastSyncKey) }
    }

    // MARK: - Reset

    func clear() {
        defaults.removeObject(forKey: snapshotKey)
        defaults.removeObject(forKey: lastSyncKey)
    }
}
