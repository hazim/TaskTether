//
//  GoogleTasksManager.swift
//  TaskTether
//
//  Created by Hazim Sami on 10/03/2026.
//

import Foundation
import Combine

class GoogleTasksManager: ObservableObject {
    
    @Published var isConnected = false
    @Published var errorMessage: String? = nil
    
    private let baseURL = "https://tasks.googleapis.com/tasks/v1"
    private let listName = "TaskTether"
    private var taskListId: String? = nil
    private var authManager: GoogleAuthManager
    
    init(authManager: GoogleAuthManager) {
        self.authManager = authManager
    }
    
    // MARK: - Setup
    
    private var hasSetup = false

    func setup() {
        guard !hasSetup else { return }
        hasSetup = true
        findOrCreateTaskTetherList()
    }
    
    // MARK: - Task List Management
    
    private func findOrCreateTaskTetherList() {
        guard let token = authManager.getAccessToken() else {
            #if DEBUG
            print("GoogleTasksManager: no access token found ❌")
            #endif
            errorMessage = String(localized: "error.tasks.notoken")
            isConnected = false
            return
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/users/@me/lists")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isConnected = false
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                DispatchQueue.main.async {
                    self.errorMessage = String(localized: "error.tasks.fetchlists")
                    self.isConnected = false
                }
                return
            }
            
            // Check if TaskTether list already exists
            if let existing = items.first(where: { $0["title"] as? String == self.listName }),
               let id = existing["id"] as? String {
                #if DEBUG
                print("TaskTether list already exists in Google Tasks: \(id)")
                #endif
                self.taskListId = id
                DispatchQueue.main.async {
                    self.isConnected = true
                }
            } else {
                // Create it
                self.createTaskTetherList(token: token)
            }
        }.resume()
    }
    
    private func createTaskTetherList(token: String) {
        var request = URLRequest(url: URL(string: "\(baseURL)/users/@me/lists")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["title": listName])
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isConnected = false
                }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String else {
                DispatchQueue.main.async {
                    self.errorMessage = String(localized: "error.tasks.createlist")
                    self.isConnected = false
                }
                return
            }
            
            #if DEBUG
            print("Created TaskTether list in Google Tasks: \(id)")
            #endif
            self.taskListId = id
            DispatchQueue.main.async {
                self.isConnected = true
            }
        }.resume()
    }
    
    // MARK: - Read Tasks

    // Two-pass fetch strategy:
    // Pass 1: orderBy=position — gives correct position order for incomplete tasks (IDs only)
    // Pass 2: showCompleted=true — gives COMPLETE field data for ALL tasks
    // Both passes are paginated — the Google Tasks API defaults to maxResults=20.
    // Without pagination, only the first 20 tasks are ever seen, causing tasks
    // beyond position 20 to appear absent and eventually be deleted from Reminders.
    func fetchTasks(completion: @escaping ([GoogleTask]) -> Void) {
        guard let token = authManager.getAccessToken(),
              let listId = taskListId else {
            completion([])
            return
        }

        let group       = DispatchGroup()
        var positionIds: [String]     = []
        var allTasks:    [GoogleTask] = []
        var needsRetry  = false

        // MARK: Pass 1 — position order (paginated)
        group.enter()
        fetchAllPages(
            baseURLString: "\(baseURL)/lists/\(listId)/tasks?showCompleted=false&orderBy=position&maxResults=100",
            token: token,
            accumulator: { items in
                positionIds.append(contentsOf: items.compactMap { $0["id"] as? String })
            },
            on401: { needsRetry = true },
            completion: { group.leave() }
        )

        // MARK: Pass 2 — full data (paginated)
        group.enter()
        fetchAllPages(
            baseURLString: "\(baseURL)/lists/\(listId)/tasks?showCompleted=true&showHidden=true&maxResults=100",
            token: token,
            accumulator: { items in
                allTasks.append(contentsOf: items.compactMap { GoogleTask(from: $0) })
            },
            on401: { needsRetry = true },
            completion: { group.leave() }
        )

        group.notify(queue: .global()) { [weak self] in
            if needsRetry {
                self?.authManager.refreshAccessToken { success in
                    if success { self?.fetchTasks(completion: completion) }
                    else { completion([]) }
                }
                return
            }
            let posMap     = Dictionary(uniqueKeysWithValues: positionIds.enumerated().map { ($1, $0) })
            let incomplete = allTasks.filter { !$0.isCompleted }
                .sorted { (posMap[$0.id] ?? 999) < (posMap[$1.id] ?? 999) }
            let completed  = allTasks.filter { $0.isCompleted }
            let merged     = incomplete + completed
            #if DEBUG
            print("GoogleTasksManager: fetched \(merged.count) task(s) (\(incomplete.count) active, \(completed.count) completed) ✅")
            #endif
            completion(merged)
        }
    }

    // Fetches all pages for a given Google Tasks list URL, calling accumulator
    // with each page's items array and completion when all pages are done.
    // Follows nextPageToken until no further pages remain.
    private func fetchAllPages(
        baseURLString: String,
        token:         String,
        accumulator:   @escaping ([[String: Any]]) -> Void,
        on401:         @escaping () -> Void,
        completion:    @escaping () -> Void
    ) {
        func fetchPage(urlString: String) {
            guard let url = URL(string: urlString) else { completion(); return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    on401()
                    completion()
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { completion(); return }

                let items = json["items"] as? [[String: Any]] ?? []
                accumulator(items)

                // Follow nextPageToken if present — more pages available
                if let nextToken = json["nextPageToken"] as? String,
                   let encoded = nextToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    fetchPage(urlString: "\(baseURLString)&pageToken=\(encoded)")
                } else {
                    completion()
                }
            }.resume()
        }

        fetchPage(urlString: baseURLString)
    }
    
    // MARK: - Write Tasks
    
    // Returns the Google Task ID on success so SyncEngine can stamp it immediately,
    // preventing duplicate creation on the next sync cycle.
    // Shared noon UTC helper — prevents timezone offset shifting the date
    static func utcNoonString(from date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let noon = cal.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: c.year, month: c.month, day: c.day, hour: 12
        )) ?? date
        let fmt = ISO8601DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: noon)
    }

    func createTask(
        title:      String,
        notes:      String?  = nil,
        dueDate:    Date?    = nil,
        url:        URL?     = nil,
        completion: ((String?) -> Void)? = nil
    ) {
        guard let token = authManager.getAccessToken(),
              let listId = taskListId else { completion?(nil); return }

        var taskData: [String: Any] = ["title": title]
        // Append URL to notes using separator so it can be parsed back out
        let notesWithURL: String?
        if let url = url {
            notesWithURL = (notes ?? "") + "\n---url---\n" + url.absoluteString
        } else {
            notesWithURL = notes
        }
        if let n = notesWithURL { taskData["notes"] = n }

        if let dueDate {
            taskData["due"] = Self.utcNoonString(from: dueDate)
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/lists/\(listId)/tasks")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: taskData)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                #if DEBUG
                print("GoogleTasksManager: createTask error — \(error.localizedDescription)")
                #endif
                completion?(nil)
                return
            }
            // Handle 401 — refresh token and retry once
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                self?.authManager.refreshAccessToken { success in
                    if success { self?.createTask(title: title, notes: notes, dueDate: dueDate, completion: completion) }
                    else { completion?(nil) }
                }
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id   = json["id"] as? String else {
                #if DEBUG
                print("GoogleTasksManager: createTask — unexpected response: \(String(data: data ?? Data(), encoding: .utf8) ?? "nil")")
                #endif
                completion?(nil)
                return
            }
            #if DEBUG
            print("Created task in Google Tasks: \(title) (id: \(id)) ✅")
            #endif
            completion?(id)
        }.resume()
    }
    
    func completeTask(taskId: String) {
        guard let token = authManager.getAccessToken(),
              let listId = taskListId else { return }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/lists/\(listId)/tasks/\(taskId)")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["status": "completed"])
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            #if DEBUG
            print("Completed task in Google Tasks: \(taskId)")
            #endif
        }.resume()
    }
    
    func updateTask(taskId: String, title: String, notes: String?, isCompleted: Bool, dueDate: Date?) {
        guard let token = authManager.getAccessToken(),
              let listId = taskListId else { return }

        // URL is intentionally NOT updated here. URLs in Google Tasks are either:
        // - Set by Google automatically in the links array (read-only)
        // - Written by us in notes at creation time (no need to re-write on update)
        // Writing URL on every update causes a feedback loop where notes change
        // on every sync cycle, triggering endless re-syncs.

        var taskData: [String: Any] = [
            "title":  title,
            "status": isCompleted ? "completed" : "needsAction"
        ]
        if let notes { taskData["notes"] = notes } else { taskData["notes"] = NSNull() }
        if let dueDate {
            taskData["due"] = Self.utcNoonString(from: dueDate)
        } else {
            // Explicitly clear the due date on Google's server.
            // Without this, omitting "due" from the PATCH body leaves the
            // existing value in place — causing the old date to bounce back
            // on the next sync cycle.
            taskData["due"] = NSNull()
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/lists/\(listId)/tasks/\(taskId)")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: taskData)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                #if DEBUG
                print("GoogleTasksManager: updateTask error — \(error.localizedDescription)")
                #endif
                return
            }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    self?.authManager.refreshAccessToken { success in
                        if success { self?.updateTask(taskId: taskId, title: title, notes: notes, isCompleted: isCompleted, dueDate: dueDate) }
                    }
                } else if http.statusCode == 200 {
                    #if DEBUG
                    print("Updated task in Google Tasks: \(title) ✅")
                    #endif
                } else {
                    #if DEBUG
                    print("GoogleTasksManager: updateTask HTTP \(http.statusCode) — \(String(data: data ?? Data(), encoding: .utf8) ?? "nil")")
                    #endif
                }
            }
        }.resume()
    }

    // Moves a task to a specific position in the list.
    // The Google Tasks API uses a "previous" task ID to position tasks:
    // nil = move to top, otherwise = move immediately after the given task.
    func moveTask(taskId: String, previousTaskId: String?) {
        guard let token = authManager.getAccessToken(),
              let listId = taskListId else { return }

        var urlString = "\(baseURL)/lists/\(listId)/tasks/\(taskId)/move"
        if let prev = previousTaskId {
            urlString += "?previous=\(prev)"
        }

        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error {
                #if DEBUG
                print("GoogleTasksManager: moveTask error — \(error.localizedDescription)")
                #endif
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                self?.authManager.refreshAccessToken { success in
                    if success { self?.moveTask(taskId: taskId, previousTaskId: previousTaskId) }
                }
            }
        }.resume()
    }

    func deleteTask(taskId: String) {
        guard let token = authManager.getAccessToken(),
              let listId = taskListId else { return }

        var request = URLRequest(url: URL(string: "\(baseURL)/lists/\(listId)/tasks/\(taskId)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error {
                #if DEBUG
                print("GoogleTasksManager: deleteTask error — \(error.localizedDescription)")
                #endif
                return
            }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    self?.authManager.refreshAccessToken { success in
                        if success { self?.deleteTask(taskId: taskId) }
                    }
                } else if http.statusCode == 204 {
                    #if DEBUG
                    print("Deleted task in Google Tasks: \(taskId) ✅")
                    #endif
                } else {
                    #if DEBUG
                    print("GoogleTasksManager: deleteTask HTTP \(http.statusCode)")
                    #endif
                }
            }
        }.resume()
    }
}

// MARK: - Google Task Model

struct GoogleTask {
    let id:          String
    let title:       String
    let notes:       String?
    let isCompleted: Bool
    let dueDate:     Date?
    let updatedDate: Date?
    let links:       [String]
    let url:         URL?     // Parsed from notes separator or links array
    let parentId:    String?  // Google Tasks parent task ID — nil for top-level tasks

    init?(from dict: [String: Any]) {
        guard let id    = dict["id"]    as? String,
              let title = dict["title"] as? String else { return nil }
        self.id          = id
        self.title       = title
        self.isCompleted = (dict["status"] as? String) == "completed"
        self.parentId    = dict["parent"] as? String
        self.links       = (dict["links"] as? [[String: Any]])?.compactMap { $0["link"] as? String } ?? []

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Normalise due date to noon UTC regardless of what time Google returns.
        // Google Tasks API returns midnight UTC (00:00:00Z) but we store noon UTC
        // in the snapshot. Without this normalisation the diff sees a difference
        // every single cycle causing an infinite update loop.
        if let dueDateString = dict["due"] as? String,
           let parsed = formatter.date(from: dueDateString) {
            var utcCal = Calendar(identifier: .gregorian)
            utcCal.timeZone = TimeZone(identifier: "UTC")!
            let c = utcCal.dateComponents([.year, .month, .day], from: parsed)
            self.dueDate = utcCal.date(from: DateComponents(
                timeZone: TimeZone(identifier: "UTC"),
                year: c.year, month: c.month, day: c.day, hour: 12
            ))
        } else {
            self.dueDate = nil
        }
        self.updatedDate = (dict["updated"] as? String).flatMap { formatter.date(from: $0) }

        // Treat empty string notes as nil — Google Tasks returns "" for no notes
        // but we store nil in the snapshot, causing a false diff every cycle.
        let rawNotes = (dict["notes"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let separator = "\n---url---\n"
        if let raw = rawNotes, let range = raw.range(of: separator) {
            self.notes = String(raw[raw.startIndex..<range.lowerBound])
            let urlString = String(raw[range.upperBound...])
            self.url = URL(string: urlString)
        } else {
            self.notes = rawNotes
            self.url   = (dict["links"] as? [[String: Any]])?
                .compactMap { $0["link"] as? String }
                .first
                .flatMap { URL(string: $0) }
        }
    }
}
