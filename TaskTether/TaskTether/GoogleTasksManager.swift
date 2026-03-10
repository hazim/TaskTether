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
        print("GoogleTasksManager: attempting to find/create list")
        guard let token = authManager.getAccessToken() else {
            print("GoogleTasksManager: no access token found ❌")
            errorMessage = "No access token"
            isConnected = false
            return
        }
        print("GoogleTasksManager: got token ✅ making API call...")
        
        var request = URLRequest(url: URL(string: "\(baseURL)/users/@me/lists")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("GoogleTasksManager: network error ❌ \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isConnected = false
                }
                return
            }
            
            if let data = data, let rawResponse = String(data: data, encoding: .utf8) {
                print("GoogleTasksManager: raw response → \(rawResponse)")
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
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                completion([])
                return
            }
            
            let tasks = items.compactMap { GoogleTask(from: $0) }
            completion(tasks)
        }.resume()
    }
    
    // MARK: - Write Tasks
    
    func createTask(title: String, notes: String? = nil, dueDate: Date? = nil) {
        guard let token = authManager.getAccessToken(),
              let listId = taskListId else { return }
        
        var taskData: [String: Any] = ["title": title]
        if let notes = notes { taskData["notes"] = notes }
        if let due = dueDate {
            let formatter = ISO8601DateFormatter()
            taskData["due"] = formatter.string(from: due)
        }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/lists/\(listId)/tasks")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: taskData)
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            print("Created task in Google Tasks: \(title)")
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
    
    func deleteTask(taskId: String) {
        guard let token = authManager.getAccessToken(),
              let listId = taskListId else { return }
        
        var request = URLRequest(url: URL(string: "\(baseURL)/lists/\(listId)/tasks/\(taskId)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            print("Deleted task in Google Tasks: \(taskId)")
        }.resume()
    }
}

// MARK: - Google Task Model

struct GoogleTask {
    let id: String
    let title: String
    let notes: String?
    let isCompleted: Bool
    let dueDate: Date?
    let links: [String]
    
    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let title = dict["title"] as? String else { return nil }
        self.id = id
        self.title = title
        self.notes = dict["notes"] as? String
        self.isCompleted = (dict["status"] as? String) == "completed"
        self.links = (dict["links"] as? [[String: Any]])?.compactMap { $0["link"] as? String } ?? []
        
        if let dueString = dict["due"] as? String {
            let formatter = ISO8601DateFormatter()
            self.dueDate = formatter.date(from: dueString)
        } else {
            self.dueDate = nil
        }
    }
}
