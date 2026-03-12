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
    
    // MARK: - Write Tasks
    
    func createTask(title: String, dueDate: Date? = nil, notes: String? = nil) {
        guard isAuthorised else { return }
        
        let calendars = store.calendars(for: .reminder)
        guard let taskTetherList = calendars.first(where: { $0.title == listName }) else { return }
        
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = taskTetherList
        reminder.notes = notes
        
        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        
        do {
            try store.save(reminder, commit: true)
            print("Created task in Reminders: \(title)")
        } catch {
            print("Failed to create task: \(error)")
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
