//
//  SyncEngine.swift
//  TaskTether
//
//  Created: 13/03/2026 · 20:30
//

import Foundation
import Combine

// MARK: - SyncState

enum SyncState: Equatable {
    case idle
    case syncing
    case error(String)
}

// MARK: - SyncEngine
// Orchestrates two-way sync between Apple Reminders and Google Tasks.
//
// Sync cycle:
//   1. Fetch all tasks from both platforms concurrently
//   2. Match tasks across platforms by title (Group 4: replace with stored cross-ref IDs)
//   3. Diff against last known snapshot to detect additions, changes, and deletions
//   4. Resolve conflicts — last-modified wins
//   5. Write changes back to the appropriate platform
//   6. Publish the merged task list for the UI
//
// The timer interval is read from ThemeManager.syncInterval at each cycle start,
// so changes in Settings take effect on the next tick without restarting the engine.

class SyncEngine: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state:      SyncState = .idle
    @Published private(set) var tasks:      [TetherTask] = []
    @Published private(set) var lastSyncAt: Date? = nil

    // MARK: - Dependencies

    private let remindersManager:   RemindersManager
    private let googleTasksManager: GoogleTasksManager
    private let authManager:        GoogleAuthManager
    private let themeManager:       ThemeManager

    // MARK: - Internal State

    // Snapshot from the previous sync cycle — used to detect deletions.
    private var previousSnapshot: [TetherTask] = []

    // Timer driving automatic sync cycles.
    private var timer: Timer?

    // Prevent overlapping sync cycles.
    private var isSyncing = false

    // MARK: - Init

    init(
        remindersManager:   RemindersManager,
        googleTasksManager: GoogleTasksManager,
        authManager:        GoogleAuthManager,
        themeManager:       ThemeManager
    ) {
        self.remindersManager   = remindersManager
        self.googleTasksManager = googleTasksManager
        self.authManager        = authManager
        self.themeManager       = themeManager
    }

    // MARK: - Lifecycle

    // Call once after the app is ready and both services are authorised.
    func start() {
        scheduleTimer()
        // Run an immediate sync on launch.
        Task { await sync() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Timer

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(themeManager.syncInterval * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            // Re-read syncInterval each tick so Settings changes take effect immediately.
            self?.rescheduleIfIntervalChanged()
            Task { await self?.sync() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func rescheduleIfIntervalChanged() {
        let expected = TimeInterval(themeManager.syncInterval * 60)
        guard let current = timer, abs(current.timeInterval - expected) > 1 else { return }
        scheduleTimer()
    }

    // MARK: - Manual Trigger

    func syncNow() {
        Task { await sync() }
    }

    // MARK: - Sync Cycle

    @MainActor
    private func sync() async {
        guard !isSyncing,
              authManager.isAuthenticated,
              remindersManager.isAuthorised else { return }

        isSyncing = true
        state = .syncing

        do {
            // 1. Fetch from both platforms concurrently.
            async let remindersFetch  = fetchReminders()
            async let googleTasksFetch = fetchGoogleTasks()

            let (reminderTasks, googleTasks) = try await (remindersFetch, googleTasksFetch)

            // 2. Match and merge into a unified list.
            let merged = merge(reminders: reminderTasks, google: googleTasks)

            // 3. Diff against previous snapshot to detect deletions and changes.
            let diff = buildDiff(merged: merged, previous: previousSnapshot)

            // 4. Write changes back to each platform.
            await applyDiff(diff)

            // 5. Commit new state.
            previousSnapshot = merged
            tasks            = merged
            lastSyncAt       = Date()
            state            = .idle

        } catch {
            state = .error(error.localizedDescription)
        }

        isSyncing = false
    }

    // MARK: - Fetch

    private func fetchReminders() async throws -> [TetherTask] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let reminders = self.remindersManager.fetchTasks()
                let tasks = reminders.map { TetherTask(from: $0) }
                continuation.resume(returning: tasks)
            }
        }
    }

    private func fetchGoogleTasks() async throws -> [TetherTask] {
        try await withCheckedThrowingContinuation { continuation in
            self.googleTasksManager.fetchTasks { googleTasks in
                let tasks = googleTasks.map { TetherTask(from: $0) }
                continuation.resume(returning: tasks)
            }
        }
    }

    // MARK: - Merge
    // Matches tasks across platforms by title (temporary — Group 4 replaces with
    // stored cross-reference IDs). Conflict resolution: last-modified wins.

    private func merge(reminders: [TetherTask], google: [TetherTask]) -> [TetherTask] {
        var result: [TetherTask] = []
        var unmatchedGoogle = google

        for var reminderTask in reminders {
            // Try to find a matching Google Tasks task by title.
            if let googleIndex = unmatchedGoogle.firstIndex(where: {
                $0.title.lowercased() == reminderTask.title.lowercased()
            }) {
                let googleTask = unmatchedGoogle.remove(at: googleIndex)

                // Both sides have this task — resolve conflict.
                if reminderTask == googleTask {
                    // No conflict — use Reminders version (authoritative for IDs).
                    reminderTask.googleTasksId = googleTask.googleTasksId
                    reminderTask.source        = .both
                    result.append(reminderTask)
                } else {
                    // Conflict — last-modified wins.
                    var winner = reminderTask.lastModified >= googleTask.lastModified
                        ? reminderTask
                        : googleTask
                    // Preserve both platform IDs on the winner.
                    winner.remindersId   = reminderTask.remindersId
                    winner.googleTasksId = googleTask.googleTasksId
                    winner.source        = .both
                    result.append(winner)
                }
            } else {
                // Only in Reminders — add as-is.
                result.append(reminderTask)
            }
        }

        // Any remaining Google tasks don't exist in Reminders yet — add them.
        result.append(contentsOf: unmatchedGoogle)

        return result
    }

    // MARK: - Diff
    // Compares the merged list against the previous snapshot.
    // Returns three sets: tasks to add, tasks to update, and tasks to delete
    // on each platform.

    private struct SyncDiff {
        var addToReminders:     [TetherTask] = []
        var updateInReminders:  [TetherTask] = []
        var deleteFromReminders:[String]     = []  // remindersId values

        var addToGoogle:        [TetherTask] = []
        var updateInGoogle:     [TetherTask] = []
        var deleteFromGoogle:   [String]     = []  // googleTasksId values
    }

    private func buildDiff(merged: [TetherTask], previous: [TetherTask]) -> SyncDiff {
        var diff = SyncDiff()

        // Additions and updates
        for task in merged {
            let prev = previous.first(where: { $0.id == task.id })

            // Needs to exist in Reminders
            if task.remindersId == nil {
                diff.addToReminders.append(task)
            } else if let prev, prev != task, task.source != .reminders {
                diff.updateInReminders.append(task)
            }

            // Needs to exist in Google Tasks
            if task.googleTasksId == nil {
                diff.addToGoogle.append(task)
            } else if let prev, prev != task, task.source != .googleTasks {
                diff.updateInGoogle.append(task)
            }
        }

        // Deletions — tasks in previous snapshot that are gone from merged
        let mergedIds = Set(merged.map { $0.id })
        for task in previous where !mergedIds.contains(task.id) {
            if let remindersId = task.remindersId {
                diff.deleteFromReminders.append(remindersId)
            }
            if let googleTasksId = task.googleTasksId {
                diff.deleteFromGoogle.append(googleTasksId)
            }
        }

        return diff
    }

    // MARK: - Apply Diff

    private func applyDiff(_ diff: SyncDiff) async {
        // Reminders writes
        for task in diff.addToReminders {
            remindersManager.createTask(
                title:   task.title,
                dueDate: task.dueDate,
                notes:   task.notes
            )
        }
        for task in diff.updateInReminders {
            // EKReminder updates require the live EKReminder object.
            // In Group 4 we'll fetch by remindersId. For now, log intent.
            print("SyncEngine: Would update Reminders task '\(task.title)'")
        }
        for remindersId in diff.deleteFromReminders {
            // Requires live EKReminder fetch by ID — wired fully in Group 4.
            print("SyncEngine: Would delete Reminders task \(remindersId)")
        }

        // Google Tasks writes
        for task in diff.addToGoogle {
            googleTasksManager.createTask(
                title:   task.title,
                notes:   task.notes,
                dueDate: task.dueDate
            )
        }
        for task in diff.updateInGoogle {
            guard let googleId = task.googleTasksId else { continue }
            googleTasksManager.updateTask(
                taskId:      googleId,
                title:       task.title,
                notes:       task.notes,
                isCompleted: task.isCompleted,
                dueDate:     task.dueDate
            )
        }
        for googleId in diff.deleteFromGoogle {
            googleTasksManager.deleteTask(taskId: googleId)
        }
    }

    // MARK: - Formatted Last Sync Time

    var lastSyncText: String {
        guard let date = lastSyncAt else {
            return String(localized: "sync.last.never")
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
