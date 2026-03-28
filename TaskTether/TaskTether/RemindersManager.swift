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
    private let listName = "TaskTether"

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
                        self.createTaskTetherListIfNeeded()
                    } else {
                        self.isAuthorised = false
                        self.errorMessage = "Reminders access denied. Please enable in System Settings → Privacy → Reminders."
                    }
                }
            }
        } else {
            store.requestAccess(to: .reminder) { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        self.isAuthorised = true
                        self.createTaskTetherListIfNeeded()
                    } else {
                        self.isAuthorised = false
                        self.errorMessage = "Reminders access denied. Please enable in System Preferences → Security & Privacy → Reminders."
                    }
                }
            }
        }
    }
    
    // MARK: - TaskTether List
    
    private func createTaskTetherListIfNeeded() {
        let calendars = store.calendars(for: .reminder)
        
        // Check if TaskTether list already exists
        if calendars.first(where: { $0.title == listName }) != nil {
            print("TaskTether list already exists in Reminders")
            return
        }
        
        // Create it
        let newList = EKCalendar(for: .reminder, eventStore: store)
        newList.title = listName
        newList.source = store.defaultCalendarForNewReminders()?.source
        
        do {
            try store.saveCalendar(newList, commit: true)
            print("Created TaskTether list in Reminders")
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Could not create TaskTether list: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Read Tasks
    
    func fetchTasks() -> [EKReminder] {
        guard isAuthorised else { return [] }
        
        let calendars = store.calendars(for: .reminder)
        guard let taskTetherList = calendars.first(where: { $0.title == listName }) else {
            return []
        }
        
        let predicate = store.predicateForReminders(in: [taskTetherList])
        var results: [EKReminder] = []
        
        let semaphore = DispatchSemaphore(value: 0)
        store.fetchReminders(matching: predicate) { reminders in
            results = reminders ?? []
            semaphore.signal()
        }
        semaphore.wait()
        
        return results
    }
    
    // MARK: - Fetch by ID
    // Fetches a single EKReminder by calendarItemIdentifier.
    // Used by SyncEngine to retrieve the live object before updating or deleting.

    func fetchTask(by id: String) -> EKReminder? {
        return fetchTasks().first { $0.calendarItemIdentifier == id }
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
            var utcCal = Calendar(identifier: .gregorian)
            utcCal.timeZone = TimeZone(identifier: "UTC")!
            reminder.dueDateComponents = utcCal.dateComponents(
                [.year, .month, .day],
                from: dueDate
            )
        } else {
            reminder.dueDateComponents = nil
        }

        do {
            try store.save(reminder, commit: true)
            print("Updated task in Reminders: \(title)")
        } catch {
            print("Failed to update task: \(error)")
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
    func createTask(title: String, dueDate: Date? = nil, notes: String? = nil, url: URL? = nil) -> String? {
        guard isAuthorised else { return nil }

        let calendars = store.calendars(for: .reminder)
        guard let taskTetherList = calendars.first(where: { $0.title == listName }) else { return nil }

        let reminder = EKReminder(eventStore: store)
        reminder.title    = title
        reminder.calendar = taskTetherList
        reminder.notes    = notes
        reminder.url      = url

        if let dueDate {
            var utcCal = Calendar(identifier: .gregorian)
            utcCal.timeZone = TimeZone(identifier: "UTC")!
            reminder.dueDateComponents = utcCal.dateComponents(
                [.year, .month, .day],
                from: dueDate
            )
        }

        do {
            try store.save(reminder, commit: true)
            print("Created task in Reminders: \(title)")
            return reminder.calendarItemIdentifier
        } catch {
            print("Failed to create task: \(error)")
            return nil
        }
    }
    
    func completeTask(_ reminder: EKReminder) {
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            print("Completed task: \(reminder.title ?? "")")
        } catch {
            print("Failed to complete task: \(error)")
        }
    }
    
    func deleteTask(_ reminder: EKReminder) {
        do {
            try store.remove(reminder, commit: true)
            print("Deleted task: \(reminder.title ?? "")")
        } catch {
            print("Failed to delete task: \(error)")
        }
    }
}
