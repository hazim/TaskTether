//
//  RemindersManager.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//

import Foundation
import EventKit
import Combine

class RemindersManager: ObservableObject {
    
    @Published var isAuthorised = false
    @Published var errorMessage: String? = nil
    
    private let store = EKEventStore()

    // Always store dates as noon UTC so no timezone offset shifts the day.
    // Hungary (UTC+1) local midnight = 23:00 prev day UTC without this fix.
    private func noonUTC(for date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return cal.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: comps.year, month: comps.month, day: comps.day, hour: 12
        )) ?? date
    }

    // Extract year/month/day in the user's LOCAL timezone, then package as
    // UTC-anchored DateComponents for storage. This is the correct pattern for
    // date-only due dates: the human calendar date is local, but EventKit
    // stores components without a time, so we pin them to UTC to avoid any
    // offset shifting the day on read-back.
    // Bug 1 root cause: using utcCal.dateComponents(from:) extracts the UTC
    // date, which at 00:18 Budapest (UTC+2) is still the previous calendar day.
    private func localDateComponents(from date: Date) -> DateComponents {
        let local = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        return DateComponents(
            calendar: utcCal,
            timeZone: TimeZone(identifier: "UTC"),
            year:  local.year,
            month: local.month,
            day:   local.day
        )
    }
    
    // MARK: - Permission
    
    private var hasRequestedAccess = false
    
    func requestAccess() {
        guard !hasRequestedAccess else { return }
        hasRequestedAccess = true

        if #available(macOS 14, *) {
            store.requestFullAccessToReminders { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        self.isAuthorised = true
                    } else {
                        self.isAuthorised = false
                        self.errorMessage = String(localized: "error.reminders.denied.v14")
                    }
                }
            }
        } else {
            store.requestAccess(to: .reminder) { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        self.isAuthorised = true
                    } else {
                        self.isAuthorised = false
                        self.errorMessage = String(localized: "error.reminders.denied.v12")
                    }
                }
            }
        }
    }

    // MARK: - Lists

    /// The Reminders list EventKit would use for a new reminder created outside
    /// TaskTether — used by SyncEngine to pick the default pair for inline "add task" (D6).
    var defaultListId: String? {
        store.defaultCalendarForNewReminders()?.calendarIdentifier
    }

    /// Whether a Reminders list is eligible for sync (D5): must allow content
    /// modifications, and must not be a subscription or birthday calendar.
    private func isEligibleList(_ calendar: EKCalendar) -> Bool {
        calendar.allowsContentModifications && calendar.type != .subscription && calendar.type != .birthday
    }

    /// All Reminders lists eligible for sync (D5).
    func fetchLists() -> [ReminderList] {
        store.calendars(for: .reminder)
            .filter(isEligibleList)
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title < $1.title }
    }

    /// Creates a new Reminders list. Mirrors the source-picking behaviour of
    /// the old createTaskTetherListIfNeeded, with a fallback for the case
    /// where there is no default calendar for new reminders yet — the
    /// fallback source must come from an eligible (D5) list, since a
    /// read-only/subscription/birthday source may reject new calendars.
    func createList(title: String) -> String? {
        guard let source = store.defaultCalendarForNewReminders()?.source
            ?? store.calendars(for: .reminder).first(where: isEligibleList)?.source
        else {
            DispatchQueue.main.async {
                self.errorMessage = String(format: String(localized: "error.reminders.createlist"), "no Reminders source available")
            }
            return nil
        }

        let newList = EKCalendar(for: .reminder, eventStore: store)
        newList.title = title
        newList.source = source

        do {
            try store.saveCalendar(newList, commit: true)
            #if DEBUG
            print("Created Reminders list: \(title)")
            #endif
            return newList.calendarIdentifier
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = String(format: String(localized: "error.reminders.createlist"), error.localizedDescription)
            }
            return nil
        }
    }

    func renameList(id: String, title: String) -> Bool {
        guard let calendar = store.calendar(withIdentifier: id) else { return false }
        calendar.title = title
        do {
            try store.saveCalendar(calendar, commit: true)
            return true
        } catch {
            #if DEBUG
            print("Failed to rename list: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Read Tasks

    // Returns nil when the fetch itself failed (not authorised, or EventKit
    // handed either completion a nil array) — distinct from a real empty
    // result. Callers must not treat nil as "no reminders": doing so lets a
    // transient EventKit failure look like every task was deleted.
    func fetchTasks() -> [EKReminder]? {
        guard isAuthorised else { return nil }

        // Fetch both incomplete AND completed reminders, across every
        // eligible list — passing nil fetches all reminder calendars.
        // Without completed reminders, deletions of completed tasks are
        // never detected by the diff. Callers read reminder.calendar.calendarIdentifier
        // to attribute each reminder to its list pair.
        let incompletePredicate = store.predicateForReminders(in: nil)
        let completedPredicate  = store.predicateForCompletedReminders(
            withCompletionDateStarting: nil,
            ending: nil,
            calendars: nil
        )

        var incomplete: [EKReminder]?
        var completed:  [EKReminder]?

        let sem1 = DispatchSemaphore(value: 0)
        store.fetchReminders(matching: incompletePredicate) { reminders in
            incomplete = reminders
            sem1.signal()
        }
        sem1.wait()

        let sem2 = DispatchSemaphore(value: 0)
        store.fetchReminders(matching: completedPredicate) { reminders in
            completed = reminders
            sem2.signal()
        }
        sem2.wait()

        guard let incomplete, let completed else { return nil }

        // Deduplicate by calendarItemIdentifier — EventKit can return the same
        // reminder in both the incomplete and completed predicates, which causes
        // a crash in Dictionary(uniqueKeysWithValues:) in SyncEngine.
        var seen  = Set<String>()
        var deduped: [EKReminder] = []
        for reminder in incomplete + completed {
            let id = reminder.calendarItemIdentifier
            if seen.insert(id).inserted {
                deduped.append(reminder)
            }
        }
        return deduped
    }
    
    // MARK: - Fetch by ID
    // Fetches a single EKReminder by calendarItemIdentifier.
    // Used by SyncEngine to retrieve the live object before updating or deleting.

    func fetchTask(by id: String) -> EKReminder? {
        return store.calendarItem(withIdentifier: id) as? EKReminder
    }

    // MARK: - Write Tasks

    func updateTask(
        _ reminder: EKReminder,
        title:       String,
        notes:       String?,
        isCompleted: Bool,
        dueDate:     Date?
    ) {
        reminder.title       = title
        reminder.isCompleted = isCompleted
        // Never touch reminder.url here — clearing it causes a diff loop.
        // URL is set only at createTask time.

        // Normalise empty string to nil before writing.
        // EventKit may return "" on read, which we normalise to nil in TetherTask.
        // Writing nil (not "") avoids a round-trip mismatch.
        let normalisedNotes = (notes?.isEmpty == true) ? nil : notes
        reminder.notes = normalisedNotes

        if let dueDate {
            // Store date-only components — no time so Reminders shows "Today"
            // not "Today, 13:00". Google Tasks handles its own UTC timestamp separately.
            // Use localDateComponents(from:) — extracts the LOCAL calendar day first,
            // then packages as UTC components. Using a UTC calendar directly gives the
            // wrong day for users east of UTC (e.g. Budapest at 00:18 is still the
            // previous UTC day).
            reminder.dueDateComponents = localDateComponents(from: dueDate)
        } else {
            reminder.dueDateComponents = nil
        }

        do {
            try store.save(reminder, commit: true)
            #if DEBUG
            print("Updated task in Reminders: \(title)")
            #endif
        } catch {
            #if DEBUG
            print("Failed to update task: \(error)")
            #endif
        }
    }

    // Returns the calendarItemIdentifier of the created reminder so SyncEngine
    // can immediately stamp the local TetherTask — preventing duplicate creation
    // on the next sync cycle.
    // Strips a URL line appended by Google Tasks sync from the notes field.
    private func stripURLFromNotes(_ notes: String) -> String {
        let separator = "\n---url---\n"
        if let range = notes.range(of: separator) {
            return String(notes[notes.startIndex..<range.lowerBound])
        }
        return notes
    }

    @discardableResult
    func createTask(title: String, dueDate: Date? = nil, notes: String? = nil, url: URL? = nil, listId: String) -> String? {
        guard isAuthorised else { return nil }

        guard let list = store.calendar(withIdentifier: listId) else {
            DispatchQueue.main.async {
                self.errorMessage = "Could not find Reminders list \(listId)"
            }
            return nil
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title    = title
        reminder.calendar = list
        reminder.notes    = notes
        reminder.url      = url

        if let dueDate {
            // Same fix as updateTask — extract LOCAL calendar day, store as UTC components.
            reminder.dueDateComponents = localDateComponents(from: dueDate)
        }

        do {
            try store.save(reminder, commit: true)
            #if DEBUG
            print("Created task in Reminders: \(title)")
            #endif
            return reminder.calendarItemIdentifier
        } catch {
            #if DEBUG
            print("Failed to create task: \(error)")
            #endif
            return nil
        }
    }
    
    func completeTask(_ reminder: EKReminder) {
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            #if DEBUG
            print("Completed task: \(reminder.title ?? "")")
            #endif
        } catch {
            #if DEBUG
            print("Failed to complete task: \(error)")
            #endif
        }
    }
    
    func deleteTask(_ reminder: EKReminder) {
        do {
            try store.remove(reminder, commit: true)
            #if DEBUG
            print("Deleted task: \(reminder.title ?? "")")
            #endif
        } catch {
            #if DEBUG
            print("Failed to delete task: \(error)")
            #endif
        }
    }

    /// Moves a reminder to a different list. Used by SyncEngine's move pass (D4)
    /// when a task's list changed on the Google side.
    @discardableResult
    func moveTask(_ reminder: EKReminder, toListId: String) -> Bool {
        guard let list = store.calendar(withIdentifier: toListId) else { return false }
        reminder.calendar = list
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            #if DEBUG
            print("Failed to move task: \(error)")
            #endif
            return false
        }
    }
}
