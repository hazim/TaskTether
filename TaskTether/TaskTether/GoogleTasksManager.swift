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
            print("GoogleTasksManager: no access token found ❌")
            errorMessage = "No access token"
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
                    self.errorMessage = "Could not fetch task lists"
                    self.isConnected = false
                }
                return
            }
            
            // Check if TaskTether list already exists
            if let existing = items.first(where: { $0["title"] as? String == self.listName }),
               let id = existing["id"] as? String {
                print("TaskTether list already exists in Google Tasks: \(id)")
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
                    self.errorMessage = "Could not create TaskTether list"
                    self.isConnected = false
                }
                return
            }
            
            print("Created TaskTether list in Google Tasks: \(id)")
            self.taskListId = id
            DispatchQueue.main.async {
                self.isConnected = true
            }
        }.resume()
    }
    
    // MARK: - Read Tasks
    
    func fetchTasks(completion: @escaping ([GoogleTask]) -> Void) {
        guard let token = authManager.getAccessToken(),
              let listId = taskListId else {
            completion([])
            return
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/lists/\(listId)/tasks?showCompleted=true")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                print("GoogleTasksManager: fetchTasks error — \(error.localizedDescription)")
                completion([])
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                self?.authManager.refreshAccessToken { success in
                    if success { self?.fetchTasks(completion: completion) }
                    else { completion([]) }
                }
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("GoogleTasksManager: fetchTasks — bad response")
                completion([])
                return
            }
            let items = json["items"] as? [[String: Any]] ?? []
            let tasks = items.compactMap { GoogleTask(from: $0) }
            print("GoogleTasksManager: fetched \(tasks.count) task(s) ✅")
            completion(tasks)
        }.resume()
    }
    
    // MARK: - Write Tasks
    
    // Returns the Google Task ID on success so SyncEngine can stamp it immediately,
    // preventing duplicate creation on the next sync cycle.
    func createTask(
        title:      String,
        notes:      String?  = nil,
        dueDate:    Date?    = nil,
        completion: ((String?) -> Void)? = nil
    ) {
        guard let token = authManager.getAccessToken(),
              let listId = taskListId else { completion?(nil); return }

        var taskData: [String: Any] = ["title": title]
        if let notes   { taskData["notes"] = notes }
        if let dueDate {
            let formatter = ISO8601DateFormatter()
            taskData["due"] = formatter.string(from: dueDate)
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/lists/\(listId)/tasks")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: taskData)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                print("GoogleTasksManager: createTask error — \(error.localizedDescription)")
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
                print("GoogleTasksManager: createTask — unexpected response: \(String(data: data ?? Data(), encoding: .utf8) ?? "nil")")
                completion?(nil)
                return
            }
            print("Created task in Google Tasks: \(title) (id: \(id)) ✅")
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
            print("Completed task in Google Tasks: \(taskId)")
        }.resume()
    }
    
    func updateTask(taskId: String, title: String, notes: String?, isCompleted: Bool, dueDate: Date?) {
        guard let token = authManager.getAccessToken(),
              let listId = taskListId else { return }

        var taskData: [String: Any] = [
            "title":  title,
            "status": isCompleted ? "completed" : "needsAction"
        ]
        if let notes   { taskData["notes"] = notes }
        if let dueDate {
            let formatter = ISO8601DateFormatter()
            taskData["due"] = formatter.string(from: dueDate)
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/lists/\(listId)/tasks/\(taskId)")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: taskData)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                print("GoogleTasksManager: updateTask error — \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    self?.authManager.refreshAccessToken { success in
                        if success { self?.updateTask(taskId: taskId, title: title, notes: notes, isCompleted: isCompleted, dueDate: dueDate) }
                    }
                } else if http.statusCode == 200 {
                    print("Updated task in Google Tasks: \(title) ✅")
                } else {
                    print("GoogleTasksManager: updateTask HTTP \(http.statusCode) — \(String(data: data ?? Data(), encoding: .utf8) ?? "nil")")
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
                print("GoogleTasksManager: deleteTask error — \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    self?.authManager.refreshAccessToken { success in
                        if success { self?.deleteTask(taskId: taskId) }
                    }
                } else if http.statusCode == 204 {
                    print("Deleted task in Google Tasks: \(taskId) ✅")
                } else {
                    print("GoogleTasksManager: deleteTask HTTP \(http.statusCode)")
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
    let updatedDate: Date?    // "updated" field from Google Tasks API — used for conflict resolution
    let links:       [String]

    init?(from dict: [String: Any]) {
        guard let id    = dict["id"]    as? String,
              let title = dict["title"] as? String else { return nil }
        self.id          = id
        self.title       = title
        self.notes       = dict["notes"] as? String
        self.isCompleted = (dict["status"] as? String) == "completed"
        self.links       = (dict["links"] as? [[String: Any]])?.compactMap { $0["link"] as? String } ?? []

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        self.dueDate = (dict["due"] as? String).flatMap { formatter.date(from: $0) }
        self.updatedDate = (dict["updated"] as? String).flatMap { formatter.date(from: $0) }
    }
}
