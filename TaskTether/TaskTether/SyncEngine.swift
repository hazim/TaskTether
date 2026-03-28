//
//  SyncEngine.swift
//  TaskTether
//
//  Created: 13/03/2026 · 22:00
//  Updated: 13/03/2026 · 22:00
//

import Foundation
import Combine
import EventKit

// MARK: - SyncState

enum SyncState: Equatable {
    case idle
    case syncing
    case error(String)
}

// MARK: - SyncEngine

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
    let idStore:                    IDStore    = IDStore()
    let statsStore:                 StatsStore = StatsStore()

    // MARK: - Internal State

    private var previousSnapshot:    [TetherTask] = []
    private var timer:               Timer?
    private var isSyncing            = false

    // Deletion candidates from the previous sync cycle.
    // A task must be absent from Google for TWO consecutive cycles before
    // we delete it from Reminders — guards against transient fetch failures.
    private var remindersDeleteCandidates: Set<String> = []  // remindersIds
    private var googleDeleteCandidates:    Set<String> = []  // googleIds

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

    func start() {
        scheduleTimer()
        scheduleMidnightRefresh()
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
            self?.rescheduleIfIntervalChanged()
            Task { await self?.sync() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func rescheduleIfIntervalChanged() {
        let expected = TimeInterval(themeManager.syncInterval * 60)
        guard let current = timer,
              abs(current.timeInterval - expected) > 1 else { return }
        scheduleTimer()
    }

    func syncNow() {
        Task { await sync() }
    }

    // MARK: - Sync Cycle

    @MainActor
    private func sync() async {
        guard !isSyncing,
              authManager.isAuthenticated,
              remindersManager.isAuthorised,
              googleTasksManager.isConnected else {
            if state == .syncing { state = .idle }
            return
        }

        isSyncing = true
        state     = .syncing

        do {
            async let remindersFetch   = fetchReminders()
            async let googleTasksFetch = fetchGoogleTasks()
            let (reminderTasks, googleTasks) = try await (remindersFetch, googleTasksFetch)

            let diff = buildDiff(
                remindersTasks: reminderTasks,
                googleTasks:    googleTasks,
                previous:       previousSnapshot
            )

            await applyDiff(diff)

            // Re-fetch both sides after applying diff so order and merge
            // reflect any tasks that were created during applyDiff.
            async let freshRemindersFetch   = fetchReminders()
            async let freshGoogleTasksFetch = fetchGoogleTasks()
            let (freshReminders, freshGoogleTasks) = try await (freshRemindersFetch, freshGoogleTasksFetch)

            let merged = await buildMergedList(
                remindersTasks: freshReminders,
                googleTasks:    freshGoogleTasks
            )

            // Update IDStore order from fresh Google fetch order.
            // Google Tasks returns items in position order when orderBy=position is set.
            let googleOrderedRids = freshGoogleTasks.compactMap { gTask -> String? in
                guard let gid = gTask.googleTasksId else { return nil }
                return idStore.remindersId(for: gid)
            }
            if !googleOrderedRids.isEmpty {
                // Reminders-only tasks (not yet linked) go at the end
                let remindersOnlyRids = merged.compactMap { $0.remindersId }
                    .filter { !googleOrderedRids.contains($0) }
                idStore.setOrder(googleOrderedRids + remindersOnlyRids)
            }

            // Update deletion candidate sets for next cycle.
            // Tasks absent this cycle but not in candidates → add to candidates.
            // Tasks present this cycle → remove from candidates.
            let presentRids = Set(freshReminders.compactMap { $0.remindersId })
            let presentGids = Set(freshGoogleTasks.compactMap { $0.googleTasksId })
            remindersDeleteCandidates = remindersDeleteCandidates
                .union(diff.addToRemindersDeleteCandidates)
                .subtracting(presentRids)
            googleDeleteCandidates = googleDeleteCandidates
                .union(diff.addToGoogleDeleteCandidates)
                .subtracting(presentGids)

            tasks            = sortedByOrder(merged)
            previousSnapshot = tasks
            lastSyncAt       = Date()
            state            = .idle

            // Record today's stats — done after sort so todayTasks is accurate
            let todayAll = todayTasks
            statsStore.record(
                total:     todayAll.count,
                completed: todayAll.filter { $0.isCompleted }.count
            )

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

    // MARK: - Diff

    private struct SyncDiff {
        var addToReminders:                [TetherTask] = []
        var addToGoogle:                   [TetherTask] = []
        var updateInGoogle:                [TetherTask] = []
        var updateInReminders:             [TetherTask] = []
        var deleteFromReminders:           [String]     = []
        var deleteFromGoogle:              [String]     = []
        var addToRemindersDeleteCandidates: Set<String>  = []
        var addToGoogleDeleteCandidates:    Set<String>  = []
    }

    @MainActor
    private func buildDiff(
        remindersTasks: [TetherTask],
        googleTasks:    [TetherTask],
        previous:       [TetherTask]
    ) -> SyncDiff {
        var diff = SyncDiff()

        let remindersByRid = Dictionary(uniqueKeysWithValues:
            remindersTasks.compactMap { t in t.remindersId.map { ($0, t) } })
        let googleByGid    = Dictionary(uniqueKeysWithValues:
            googleTasks.compactMap { t in t.googleTasksId.map { ($0, t) } })
        let prevByRid      = Dictionary(uniqueKeysWithValues:
            previous.compactMap { t in t.remindersId.map { ($0, t) } })

        let linkedCount = idStore.linkedCount

        let googleSuspicious    = googleTasks.isEmpty    && linkedCount > 0
        let remindersSuspicious = remindersTasks.isEmpty && linkedCount > 0

        if googleSuspicious {
            print("SyncEngine: Google returned 0 tasks with \(linkedCount) known links — skipping deletions")
        }
        if remindersSuspicious {
            print("SyncEngine: Reminders returned 0 tasks with \(linkedCount) known links — skipping deletions")
        }

        // Track which Google IDs are handled in the Reminders loop
        // so the Google loop only processes unlinked tasks.
        var processedGids = Set<String>()

        for rTask in remindersTasks {
            guard let rid = rTask.remindersId else { continue }
            if let gid = idStore.googleId(for: rid) {
                processedGids.insert(gid)
                if let gTask = googleByGid[gid] {
                    let prev = prevByRid[rid]

                    if let prev {
                        let rChanged = rTask.isCompleted != prev.isCompleted
                                    || rTask.title       != prev.title
                                    || rTask.notes       != prev.notes
                                    || rTask.dueDate     != prev.dueDate
                        let gChanged = gTask.isCompleted != prev.isCompleted
                                    || gTask.title       != prev.title
                                    || gTask.notes       != prev.notes
                                    || gTask.dueDate     != prev.dueDate

                        if rChanged && !gChanged {
                            // Only Reminders changed → push to Google
                            diff.updateInGoogle.append(rTask)
                        } else if gChanged && !rChanged {
                            // Only Google changed → push to Reminders
                            diff.updateInReminders.append(gTask)
                        } else if rChanged && gChanged {
                            // Both changed → last-modified wins
                            if rTask.lastModified >= gTask.lastModified {
                                diff.updateInGoogle.append(rTask)
                            } else {
                                diff.updateInReminders.append(gTask)
                            }
                        }
                        // Neither changed → no-op
                    } else {
                        // No previous snapshot for this task yet.
                        // This happens on the first sync cycle after a task is linked.
                        // Small metadata differences (notes normalisation, date precision)
                        // between platforms cause spurious writes here.
                        // Safe to skip — the next cycle will have a proper prev
                        // and handle any genuine differences correctly.
                    }
                } else if !googleSuspicious, prevByRid[rid] != nil {
                    // Only delete if absent in previous cycle too (two-cycle guard)
                    if remindersDeleteCandidates.contains(rid) {
                        diff.deleteFromReminders.append(rid)
                    } else {
                        diff.addToRemindersDeleteCandidates.insert(rid)
                    }
                }
            } else {
                diff.addToGoogle.append(rTask)
            }
        }

        for gTask in googleTasks {
            guard let gid = gTask.googleTasksId else { continue }
            if processedGids.contains(gid) { continue }  // Already handled above
            if let rid = idStore.remindersId(for: gid) {
                if remindersByRid[rid] == nil,
                   !remindersSuspicious,
                   prevByRid[rid] != nil {
                    // Two-cycle guard for Google deletions too
                    if googleDeleteCandidates.contains(gid) {
                        diff.deleteFromGoogle.append(gid)
                    } else {
                        diff.addToGoogleDeleteCandidates.insert(gid)
                    }
                }
            } else {
                // Never create a completed task in Reminders.
                // Completed tasks were intentionally removed from Reminders when done.
                // Re-creating them would undo the user's completion action.
                if !gTask.isCompleted {
                    diff.addToReminders.append(gTask)
                }
            }
        }

        return diff
    }

    // MARK: - Apply Diff

    @MainActor
    private func applyDiff(_ diff: SyncDiff) async {
        for task in diff.addToReminders {
            let remindersId = remindersManager.createTask(
                title:   task.title,
                dueDate: task.dueDate,
                notes:   task.notes,
                url:     task.url
            )
            if let remindersId, let gid = task.googleTasksId {
                idStore.link(remindersId: remindersId, googleId: gid)
            }
        }

        for task in diff.addToGoogle {
            guard let rid = task.remindersId else { continue }
            await withCheckedContinuation { continuation in
                googleTasksManager.createTask(
                    title:   task.title,
                    notes:   task.notes,
                    dueDate: task.dueDate,
                    url:     task.url
                ) { [weak self] gid in
                    if let gid { self?.idStore.link(remindersId: rid, googleId: gid) }
                    continuation.resume()
                }
            }
        }

        for task in diff.updateInGoogle {
            guard let rid = task.remindersId,
                  let gid = idStore.googleId(for: rid) else { continue }
            googleTasksManager.updateTask(
                taskId:      gid,
                title:       task.title,
                notes:       task.notes,
                isCompleted: task.isCompleted,
                dueDate:     task.dueDate
            )
            if let reminder = remindersManager.fetchTask(by: rid),
               reminder.isCompleted != task.isCompleted {
                remindersManager.updateTask(
                    reminder,
                    title:       task.title,
                    notes:       task.notes,
                    isCompleted: task.isCompleted,
                    dueDate:     task.dueDate
                )
            }
        }

        // Update in Reminders (change originated in Google Tasks)
        for gTask in diff.updateInReminders {
            guard let gid = gTask.googleTasksId,
                  let rid = idStore.remindersId(for: gid),
                  let reminder = remindersManager.fetchTask(by: rid) else { continue }
            remindersManager.updateTask(
                reminder,
                title:       gTask.title,
                notes:       gTask.notes,
                isCompleted: gTask.isCompleted,
                dueDate:     gTask.dueDate
            )
        }

        for rid in diff.deleteFromReminders {
            if let reminder = remindersManager.fetchTask(by: rid) {
                remindersManager.deleteTask(reminder)
            }
            idStore.unlink(remindersId: rid)
        }

        for gid in diff.deleteFromGoogle {
            googleTasksManager.deleteTask(taskId: gid)
            if let rid = idStore.remindersId(for: gid) {
                idStore.unlink(remindersId: rid)
            }
        }
    }

    // MARK: - Merge & Sort

    @MainActor
    private func buildMergedList(
        remindersTasks: [TetherTask],
        googleTasks:    [TetherTask]
    ) async -> [TetherTask] {
        let googleByGid = Dictionary(uniqueKeysWithValues:
            googleTasks.compactMap { t in t.googleTasksId.map { ($0, t) } })

        var result: [TetherTask] = []
        for var rTask in remindersTasks {
            guard let rid = rTask.remindersId else { continue }
            if let gid = idStore.googleId(for: rid),
               let gTask = googleByGid[gid] {
                rTask.googleTasksId  = gid
                rTask.parentGoogleId = gTask.parentGoogleId
                rTask.url            = rTask.url ?? gTask.url
                rTask.source         = .both
            }
            result.append(rTask)
        }
        return result
    }

    @MainActor
    private func sortedByOrder(_ tasks: [TetherTask]) -> [TetherTask] {
        func pos(_ t: TetherTask) -> Int {
            t.remindersId.map { idStore.position(of: $0) } ?? Int.max
        }

        // Separate top-level tasks from subtasks
        let parents  = tasks.filter { $0.parentGoogleId == nil }
        let subtasks = tasks.filter { $0.parentGoogleId != nil }

        // Sort parents: incomplete first by position, completed last
        let incompleteParents = parents.filter { !$0.isCompleted }.sorted { pos($0) < pos($1) }
        let completedParents  = parents.filter {  $0.isCompleted }.sorted { pos($0) < pos($1) }

        // Build result: each parent followed immediately by its subtasks
        var result: [TetherTask] = []
        for parent in incompleteParents + completedParents {
            result.append(parent)
            let children = subtasks.filter { $0.parentGoogleId == parent.googleTasksId }
            let incompleteChildren = children.filter { !$0.isCompleted }
            let completedChildren  = children.filter {  $0.isCompleted }
            result.append(contentsOf: incompleteChildren + completedChildren)
        }

        // Orphaned subtasks (parent not in list) go at the end
        let knownParentIds = Set(parents.compactMap { $0.googleTasksId })
        let orphans = subtasks.filter {
            guard let pid = $0.parentGoogleId else { return false }
            return !knownParentIds.contains(pid)
        }
        result.append(contentsOf: orphans)

        return result
    }

    // MARK: - Order Sync

    // Pushes the current display order to Google Tasks using the move endpoint.
    // Google Tasks positions tasks by reference to the previous task ID,
    // so we walk the incomplete tasks in order and move each one after the previous.
    @MainActor
    private func pushOrderToGoogle(tasks: [TetherTask]) async {
        let incomplete = tasks.filter { !$0.isCompleted }
        var previousGoogleId: String? = nil

        for task in incomplete {
            guard let rid = task.remindersId,
                  let gid = idStore.googleId(for: rid) else { continue }
            googleTasksManager.moveTask(taskId: gid, previousTaskId: previousGoogleId)
            previousGoogleId = gid
            // Small delay to avoid rate limiting
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
    }

    // MARK: - Date Helper

    // Returns noon UTC for the LOCAL calendar date of the given time.
    // Critical: must use the LOCAL calendar to extract year/month/day,
    // not UTC — otherwise tasks appear on the wrong day for users east of UTC.
    // Example: 00:30 Budapest (UTC+1) = 23:30 UTC previous day.
    // UTC calendar gives yesterday; local calendar correctly gives today.
    private func noonUTC(for date: Date = Date()) -> Date {
        // Extract date components in the user's local timezone
        let local = Calendar.current.dateComponents([.year, .month, .day], from: date)
        // Store as noon UTC for consistent cross-platform comparison
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        return utcCal.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: local.year, month: local.month, day: local.day, hour: 12
        )) ?? date
    }

    // Schedules a sync at the next local midnight so todayTasks re-evaluates
    // when the calendar day rolls over, without waiting for the next timer tick.
    private func scheduleMidnightRefresh() {
        let cal   = Calendar.current
        guard let tomorrow  = cal.date(byAdding: .day, value: 1, to: Date()),
              let midnight  = cal.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow)
        else { return }
        let delay = midnight.timeIntervalSinceNow
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { await self?.sync() }
            self?.scheduleMidnightRefresh()  // Reschedule for next midnight
        }
    }

    // MARK: - Instant UI Updates

    @MainActor
    func toggleTask(id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].isCompleted.toggle()
        tasks[idx].lastModified = Date()
        let task      = tasks[idx]
        let completed = task.isCompleted
        guard let rid = task.remindersId else { return }

        let completedIds = Set(tasks.filter { $0.isCompleted }.compactMap { $0.remindersId })
        if completed {
            idStore.moveToEnd(remindersId: rid)
        } else {
            idStore.moveBeforeCompleted(remindersId: rid, completedIds: completedIds)
        }

        tasks            = sortedByOrder(tasks)
        previousSnapshot = tasks

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let reminder = remindersManager.fetchTask(by: rid) {
                remindersManager.updateTask(
                    reminder,
                    title:       task.title,
                    notes:       task.notes,
                    isCompleted: completed,
                    dueDate:     task.dueDate
                )
            }
            if let gid = idStore.googleId(for: rid) {
                googleTasksManager.updateTask(
                    taskId:      gid,
                    title:       task.title,
                    notes:       task.notes,
                    isCompleted: completed,
                    dueDate:     task.dueDate
                )
            }
        }
    }

    @MainActor
    func addTask(title: String) {
        let dueDate = noonUTC()
        let tempId  = UUID().uuidString

        let task = TetherTask(
            id:            tempId,
            remindersId:   nil,
            googleTasksId: nil,
            title:         title,
            notes:         nil,
            isCompleted:   false,
            dueDate:       dueDate,
            url:           nil,
            lastModified:  Date(),
            source:        .both
        )
        tasks.insert(task, at: 0)
        previousSnapshot = tasks

        Task { @MainActor [weak self] in
            guard let self else { return }

            let remindersId = await Task { @MainActor in
                self.remindersManager.createTask(
                    title:   title,
                    dueDate: dueDate,
                    notes:   nil
                )
            }.value

            guard let remindersId else { return }

            if let idx = tasks.firstIndex(where: { $0.id == tempId }) {
                tasks[idx].remindersId = remindersId
            }
            idStore.insertAtTop(remindersId: remindersId, completedIds: [])

            await withCheckedContinuation { continuation in
                self.googleTasksManager.createTask(
                    title:   title,
                    notes:   nil,
                    dueDate: dueDate,
                    url:     nil
                ) { [weak self] gid in
                    if let gid {
                        self?.idStore.link(remindersId: remindersId, googleId: gid)
                        Task { @MainActor in
                            if let idx = self?.tasks.firstIndex(where: { $0.id == tempId }) {
                                self?.tasks[idx].googleTasksId = gid
                            }
                        }
                    }
                    continuation.resume()
                }
            }

            previousSnapshot = tasks
        }
    }

    @MainActor
    func deleteTask(id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let task = tasks.remove(at: idx)
        previousSnapshot = tasks

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let rid = task.remindersId {
                if let reminder = remindersManager.fetchTask(by: rid) {
                    remindersManager.deleteTask(reminder)
                }
                if let gid = idStore.googleId(for: rid) {
                    googleTasksManager.deleteTask(taskId: gid)
                }
                idStore.unlink(remindersId: rid)
            }
        }
    }

    // MARK: - Today Filter

    var todayTasks: [TetherTask] {
        let todayNoon = noonUTC()
        let tomorrow  = todayNoon + 86400
        return tasks.filter { task in
            guard let due = task.dueDate else { return false }
            // Only show tasks due today — completed or incomplete.
            // Overdue incomplete tasks are excluded (they are in the past).
            return due >= todayNoon && due < tomorrow
        }
    }

    // MARK: - Last Sync Text

    var lastSyncText: String {
        guard let date = lastSyncAt else {
            return String(localized: "sync.last.never")
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
