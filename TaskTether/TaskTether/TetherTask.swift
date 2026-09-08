//
//  TetherTask.swift
//  TaskTether
//
//  Created: 13/03/2026 · 20:30
//

import Foundation
import EventKit

// MARK: - TetherTask
// The canonical in-memory representation of a synced task.
// Every task in the system is held as a TetherTask regardless of which side
// it originated from. SyncEngine maps EKReminder and GoogleTask into this
// model before diffing, and maps back out when writing changes.
//
// Identity rules:
//   - remindersId    — EKReminder.calendarItemIdentifier (nil if not yet in Reminders)
//   - googleTasksId  — Google Tasks API task ID (nil if not yet in Google Tasks)
//   - A task is considered the same on both sides when titles match and both IDs
//     are populated. In Group 4 this will be replaced by an explicit cross-ref
//     stored in the task notes field.

struct TetherTask: Identifiable, Equatable {

    // MARK: - Identity

    var id:            String          // Local UUID — stable across sync cycles
    var remindersId:   String?         // EKReminder.calendarItemIdentifier
    var googleTasksId: String?         // Google Tasks API id field
    var parentGoogleId: String?        // Google Tasks parent ID — nil for top-level tasks

    // Id of the ListPair this task belongs to (D7). Set by SyncEngine when a
    // task is attributed to a list pair; nil only for a task created
    // optimistically in the UI before it has been placed, and for rows read
    // from a pre-multi-list snapshot (which SnapshotStore rejects outright).
    var listPairId: String?

    // MARK: - Content

    var title:       String
    var notes:       String?
    var isCompleted: Bool
    var dueDate:     Date?
    var url:         URL?

    // MARK: - Sync Metadata

    // Last modification date — used for conflict resolution (last-modified wins).
    // If the platform doesn't provide one, we fall back to Date.distantPast so
    // the other side always wins the conflict.
    var lastModified: Date

    // Which platform this record was most recently fetched from.
    // Used in logging and conflict resolution tie-breaking.
    var source: TetherSource

    // MARK: - Equatable
    // Two TetherTasks are considered equal for diffing purposes when their
    // content fields match. ID and metadata are excluded intentionally.

    static func == (lhs: TetherTask, rhs: TetherTask) -> Bool {
        lhs.title       == rhs.title       &&
        lhs.notes       == rhs.notes       &&
        lhs.isCompleted == rhs.isCompleted &&
        lhs.dueDate     == rhs.dueDate
    }

    // MARK: - Overdue

    // True when the task has a due date that has already passed (relative to
    // the noon-UTC day boundary, see noonUTC(for:) below) and the task isn't
    // completed yet. Single source of truth — SyncEngine.overdueTasks and the
    // TaskRow display model both derive from this.
    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < TetherTask.noonUTC()
    }

    // Returns noon UTC for the LOCAL calendar date of the given time.
    // Critical: must use the LOCAL calendar to extract year/month/day,
    // not UTC — otherwise tasks appear on the wrong day for users east of UTC.
    // Example: 00:30 Budapest (UTC+1) = 23:30 UTC previous day.
    // UTC calendar gives yesterday; local calendar correctly gives today.
    static func noonUTC(for date: Date = Date()) -> Date {
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
}

// MARK: - TetherSource

enum TetherSource {
    case reminders
    case googleTasks
    case both          // Task exists on both sides with no conflict
}

// MARK: - EKReminder → TetherTask

extension TetherTask {

    init(from reminder: EKReminder) {
        self.id             = UUID().uuidString
        self.remindersId    = reminder.calendarItemIdentifier
        self.googleTasksId  = nil
        self.parentGoogleId = nil
        self.listPairId     = nil
        self.title          = reminder.title ?? ""
        self.isCompleted   = reminder.isCompleted

        // Parse URL: check native url property first, then scan notes for a URL.
        // The Reminders app shows link badges from notes text, not the url property.
        let nativeURL = reminder.url
        let notesText = reminder.notes ?? ""
        let detector  = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let notesURL  = detector?
            .matches(in: notesText, range: NSRange(notesText.startIndex..., in: notesText))
            .first
            .flatMap { $0.url }
        self.url   = nativeURL ?? notesURL
        // Normalise empty string to nil — EventKit returns "" for no notes
        // but we store nil in Google Tasks, causing a false diff every cycle.
        self.notes = (reminder.notes?.isEmpty == true) ? nil : reminder.notes
        self.lastModified  = reminder.lastModifiedDate ?? Date.distantPast
        self.source        = .reminders

        if let components = reminder.dueDateComponents,
           let year  = components.year,
           let month = components.month,
           let day   = components.day {
            // Normalise to noon UTC — same format as Google Tasks.
            // This ensures date equality works with simple == comparison
            // and avoids timezone offsets shifting the calendar day.
            var utcCal = Calendar(identifier: .gregorian)
            utcCal.timeZone = TimeZone(identifier: "UTC")!
            self.dueDate = utcCal.date(from: DateComponents(
                timeZone: TimeZone(identifier: "UTC"),
                year: year, month: month, day: day, hour: 12
            ))
        } else {
            self.dueDate = nil
        }
    }
}

// MARK: - GoogleTask → TetherTask

extension TetherTask {

    init(from googleTask: GoogleTask) {
        self.id             = UUID().uuidString
        self.remindersId    = nil
        self.googleTasksId  = googleTask.id
        self.parentGoogleId = googleTask.parentId
        self.listPairId     = nil
        self.title          = googleTask.title
        self.notes         = googleTask.notes
        self.isCompleted   = googleTask.isCompleted
        self.dueDate       = googleTask.dueDate
        self.lastModified  = googleTask.updatedDate ?? Date.distantPast
        self.source        = .googleTasks
        self.url           = googleTask.url
    }
}

// MARK: - TetherTask → TetherTaskItem (display model)
// Maps the sync model to the lightweight display model used by TaskRow / TodayView.

extension TetherTask {

    func toDisplayItem() -> TetherTaskItem {
        TetherTaskItem(
            id:          id,
            title:       title,
            isCompleted: isCompleted,
            isSubtask:   parentGoogleId != nil,
            url:         url,
            subtasks:    [],
            isOverdue:   isOverdue
        )
    }
}
