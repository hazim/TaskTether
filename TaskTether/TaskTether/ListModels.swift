//
//  ListModels.swift
//  TaskTether
//
//  Created: 04/09/2026
//

import Foundation

// MARK: - ReminderList
// A Reminders list (EKCalendar for .reminder) as seen by the sync engine.

struct ReminderList: Equatable, Hashable {
    let id: String        // EKCalendar.calendarIdentifier
    let title: String
}

// MARK: - GoogleTaskList
// A Google Tasks task list.

struct GoogleTaskList: Equatable, Hashable {
    let id: String
    let title: String
}

// MARK: - ListPair
// A synced pair of lists. `title` is the title as of the last successful
// sync — the rename baseline used to detect which side changed (D3).

struct ListPair: Codable, Equatable, Identifiable {
    let id: String              // UUID string, stable for the life of the pair
    var remindersListId: String
    var googleListId: String
    var title: String
}
