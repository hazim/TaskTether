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
    private var authManager: GoogleAuthManager

    init(authManager: GoogleAuthManager) {
        self.authManager = authManager
    }

    // MARK: - URL Building

    enum GoogleTasksError: Error {
        case invalidURL
        case notAuthenticated
        case unauthorized
        case invalidResponse
        case transport(Error)
        case httpStatus(Int)
    }

    /// Builds a Google Tasks API URL for a task list, optionally a specific task
    /// and/or trailing action (e.g. "move"), percent-encoding IDs via URLComponents
    /// so an unexpected character in an API-returned ID can never crash the app via
    /// a force-unwrapped `URL(string:)`.
    private func tasksURL(
        listId: String,
        taskId: String? = nil,
        action: String? = nil,
        query: [URLQueryItem] = []
    ) throws -> URL {
        guard var components = URLComponents(string: baseURL) else {
            throw GoogleTasksError.invalidURL
        }
        var segments = [components.percentEncodedPath, "lists", encodedPathSegment(listId), "tasks"]
        if let taskId { segments.append(encodedPathSegment(taskId)) }
        if let action { segments.append(action) }
        components.percentEncodedPath = segments.joined(separator: "/")
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw GoogleTasksError.invalidURL
        }
        return url
    }

    /// Builds a Google Tasks API URL for the task-lists collection, optionally a
    /// specific list, using the same URLComponents + percent-encoding approach as
    /// `tasksURL` so an API-returned list ID can never crash the app via a
    /// force-unwrapped `URL(string:)`.
    private func taskListsURL(id: String? = nil, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: baseURL) else {
            throw GoogleTasksError.invalidURL
        }
        var segments = [components.percentEncodedPath, "users", "@me", "lists"]
        if let id { segments.append(encodedPathSegment(id)) }
        components.percentEncodedPath = segments.joined(separator: "/")
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw GoogleTasksError.invalidURL
        }
        return url
    }

    private func encodedPathSegment(_ raw: String) -> String {
        // RFC 3986 unreserved characters only. .urlPathAllowed leaves "/",
        // "+", "=", and "&" unescaped, but Google Tasks IDs are standard
        // base64 and may contain any of those — an unescaped "/" would
        // split the path into extra segments, corrupting the request URL.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return raw.addingPercentEncoding(withAllowedCharacters: unreserved) ?? raw
    }

    // MARK: - Setup

    // Cleared again when the first list fetch fails so a later setup() call
    // (SyncEngine retries on every timer tick while disconnected) gets
    // another attempt — an offline launch must not pin the connection off.
    private var hasSetup = false

    func setup() {
        guard !hasSetup else { return }
        hasSetup = true

        guard authManager.getAccessToken() != nil else {
            #if DEBUG
            print("GoogleTasksManager: no access token found ❌")
            #endif
            errorMessage = String(localized: "error.tasks.notoken")
            isConnected = false
            return
        }

        fetchTaskLists { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.isConnected = true
                case .failure:
                    self?.errorMessage = String(localized: "error.tasks.fetchlists")
                    self?.isConnected = false
                    self?.hasSetup = false
                }
            }
        }
    }

    // MARK: - Task List Management

    /// Fetches every Google Tasks list for the signed-in account, paginated.
    func fetchTaskLists(completion: @escaping (Result<[GoogleTaskList], Error>) -> Void) {
        guard let token = authManager.getAccessToken() else {
            completion(.failure(GoogleTasksError.notAuthenticated))
            return
        }
        guard let requestURL = try? taskListsURL(query: [URLQueryItem(name: "maxResults", value: "100")]) else {
            completion(.failure(GoogleTasksError.invalidURL))
            return
        }

        var lists: [GoogleTaskList] = []
        var needsRetry = false

        fetchAllPages(
            baseURLString: requestURL.absoluteString,
            token: token,
            accumulator: { items in
                lists.append(contentsOf: items.compactMap { dict in
                    guard let id = dict["id"] as? String,
                          let title = dict["title"] as? String else { return nil }
                    return GoogleTaskList(id: id, title: title)
                })
            },
            on401: { needsRetry = true },
            completion: { [weak self] error in
                if needsRetry {
                    self?.authManager.refreshAccessToken { success in
                        if success { self?.fetchTaskLists(completion: completion) }
                        else { completion(.failure(GoogleTasksError.unauthorized)) }
                    }
                    return
                }
                if let error {
                    #if DEBUG
                    print("GoogleTasksManager: fetchTaskLists failed — \(error)")
                    #endif
                    completion(.failure(error))
                    return
                }
                #if DEBUG
                print("GoogleTasksManager: fetched \(lists.count) task list(s) ✅")
                #endif
                completion(.success(lists))
            }
        )
    }

    /// Creates a new Google Tasks list with the given title.
    func createTaskList(title: String, completion: @escaping (Result<GoogleTaskList, Error>) -> Void) {
        guard let token = authManager.getAccessToken() else {
            completion(.failure(GoogleTasksError.notAuthenticated))
            return
        }
        guard let requestURL = try? taskListsURL() else {
            completion(.failure(GoogleTasksError.invalidURL))
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["title": title])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                self?.authManager.refreshAccessToken { success in
                    if success { self?.createTaskList(title: title, completion: completion) }
                    else { completion(.failure(GoogleTasksError.unauthorized)) }
                }
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String,
                  let returnedTitle = json["title"] as? String else {
                completion(.failure(GoogleTasksError.invalidResponse))
                return
            }
            #if DEBUG
            print("Created Google Tasks list: \(returnedTitle) (id: \(id)) ✅")
            #endif
            completion(.success(GoogleTaskList(id: id, title: returnedTitle)))
        }.resume()
    }

    /// Renames an existing Google Tasks list.
    func renameTaskList(id: String, title: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let token = authManager.getAccessToken() else {
            completion(.failure(GoogleTasksError.notAuthenticated))
            return
        }
        guard let requestURL = try? taskListsURL(id: id) else {
            completion(.failure(GoogleTasksError.invalidURL))
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["title": title])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(GoogleTasksError.invalidResponse))
                return
            }
            if http.statusCode == 401 {
                self?.authManager.refreshAccessToken { success in
                    if success { self?.renameTaskList(id: id, title: title, completion: completion) }
                    else { completion(.failure(GoogleTasksError.unauthorized)) }
                }
                return
            }
            guard http.statusCode == 200 else {
                #if DEBUG
                print("GoogleTasksManager: renameTaskList HTTP \(http.statusCode) — \(String(data: data ?? Data(), encoding: .utf8) ?? "nil")")
                #endif
                completion(.failure(GoogleTasksError.invalidResponse))
                return
            }
            #if DEBUG
            print("Renamed Google Tasks list \(id) to \(title) ✅")
            #endif
            completion(.success(()))
        }.resume()
    }

    /// Moves a task from one Google Tasks list to another. Returns the moved
    /// task (with its updated `listId`) on success.
    func moveTaskToList(taskId: String, from: String, to: String, completion: @escaping (Result<GoogleTask, Error>) -> Void) {
        guard let token = authManager.getAccessToken() else {
            completion(.failure(GoogleTasksError.notAuthenticated))
            return
        }
        let query = [URLQueryItem(name: "destinationTasklist", value: to)]
        guard let requestURL = try? tasksURL(listId: from, taskId: taskId, action: "move", query: query) else {
            completion(.failure(GoogleTasksError.invalidURL))
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                self?.authManager.refreshAccessToken { success in
                    if success { self?.moveTaskToList(taskId: taskId, from: from, to: to, completion: completion) }
                    else { completion(.failure(GoogleTasksError.unauthorized)) }
                }
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let moved = GoogleTask(from: json, listId: to) else {
                completion(.failure(GoogleTasksError.invalidResponse))
                return
            }
            #if DEBUG
            print("Moved task \(taskId) from \(from) to \(to) ✅")
            #endif
            completion(.success(moved))
        }.resume()
    }

    // MARK: - Read Tasks

    // Two-pass fetch strategy:
    // Pass 1: orderBy=position — gives correct position order for incomplete tasks (IDs only)
    // Pass 2: showCompleted=true — gives COMPLETE field data for ALL tasks
    // Both passes are paginated — the Google Tasks API defaults to maxResults=20.
    // Without pagination, only the first 20 tasks are ever seen, causing tasks
    // beyond position 20 to appear absent and eventually be deleted from Reminders.
    func fetchTasks(listId: String, completion: @escaping (Result<[GoogleTask], Error>) -> Void) {
        guard let token = authManager.getAccessToken() else {
            completion(.failure(GoogleTasksError.notAuthenticated))
            return
        }

        guard let positionURL = try? tasksURL(listId: listId, query: [
                  URLQueryItem(name: "showCompleted", value: "false"),
                  URLQueryItem(name: "orderBy", value: "position"),
                  URLQueryItem(name: "maxResults", value: "100")
              ]),
              let fullDataURL = try? tasksURL(listId: listId, query: [
                  URLQueryItem(name: "showCompleted", value: "true"),
                  URLQueryItem(name: "showHidden", value: "true"),
                  URLQueryItem(name: "maxResults", value: "100")
              ]) else {
            #if DEBUG
            print("GoogleTasksManager: fetchTasks — failed to build URL for list \(listId)")
            #endif
            completion(.failure(GoogleTasksError.invalidURL))
            return
        }

        let group       = DispatchGroup()
        var positionIds: [String]     = []
        var allTasks:    [GoogleTask] = []
        var needsRetry  = false
        var fetchError: Error?

        // MARK: Pass 1 — position order (paginated)
        group.enter()
        fetchAllPages(
            baseURLString: positionURL.absoluteString,
            token: token,
            accumulator: { items in
                positionIds.append(contentsOf: items.compactMap { $0["id"] as? String })
            },
            on401: { needsRetry = true },
            completion: { error in
                if fetchError == nil { fetchError = error }
                group.leave()
            }
        )

        // MARK: Pass 2 — full data (paginated)
        group.enter()
        fetchAllPages(
            baseURLString: fullDataURL.absoluteString,
            token: token,
            accumulator: { items in
                allTasks.append(contentsOf: items.compactMap { GoogleTask(from: $0, listId: listId) })
            },
            on401: { needsRetry = true },
            completion: { error in
                if fetchError == nil { fetchError = error }
                group.leave()
            }
        )

        group.notify(queue: .global()) { [weak self] in
            if needsRetry {
                self?.authManager.refreshAccessToken { success in
                    if success { self?.fetchTasks(listId: listId, completion: completion) }
                    else { completion(.failure(GoogleTasksError.unauthorized)) }
                }
                return
            }
            if let fetchError {
                #if DEBUG
                print("GoogleTasksManager: fetchTasks failed for list \(listId) — \(fetchError)")
                #endif
                completion(.failure(fetchError))
                return
            }
            let posMap     = Dictionary(uniqueKeysWithValues: positionIds.enumerated().map { ($1, $0) })
            let incomplete = allTasks.filter { !$0.isCompleted }
                .sorted { (posMap[$0.id] ?? 999) < (posMap[$1.id] ?? 999) }
            let completed  = allTasks.filter { $0.isCompleted }
            let merged     = incomplete + completed
            #if DEBUG
            print("GoogleTasksManager: fetched \(merged.count) task(s) in list \(listId) (\(incomplete.count) active, \(completed.count) completed) ✅")
            #endif
            completion(.success(merged))
        }
    }

    // Fetches all pages for a given Google Tasks list URL, calling accumulator
    // with each page's items array and completion when all pages are done.
    // Follows nextPageToken until no further pages remain.
    // `completion` receives nil on success (or a 401, which `on401` also signals
    // separately so the caller can trigger a token-refresh retry) and a
    // `GoogleTasksError` on any other failure — transport error, non-2xx status,
    // or an unparseable body. Callers must treat a non-nil error as the whole
    // fetch having failed, never as "no items".
    private func fetchAllPages(
        baseURLString: String,
        token:         String,
        accumulator:   @escaping ([[String: Any]]) -> Void,
        on401:         @escaping () -> Void,
        completion:    @escaping (Error?) -> Void
    ) {
        func fetchPage(urlString: String) {
            guard let url = URL(string: urlString) else {
                completion(GoogleTasksError.invalidURL)
                return
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(GoogleTasksError.transport(error))
                    return
                }
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 401 {
                        on401()
                        completion(nil)
                        return
                    }
                    guard (200...299).contains(http.statusCode) else {
                        completion(GoogleTasksError.httpStatus(http.statusCode))
                        return
                    }
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    completion(GoogleTasksError.invalidResponse)
                    return
                }

                let items = json["items"] as? [[String: Any]] ?? []
                accumulator(items)

                // Follow nextPageToken if present — more pages available
                if let nextToken = json["nextPageToken"] as? String,
                   let encoded = nextToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    fetchPage(urlString: "\(baseURLString)&pageToken=\(encoded)")
                } else {
                    completion(nil)
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
        listId:     String,
        title:      String,
        notes:      String?  = nil,
        dueDate:    Date?    = nil,
        url:        URL?     = nil,
        completion: ((String?) -> Void)? = nil
    ) {
        guard let token = authManager.getAccessToken() else { completion?(nil); return }

        var taskData: [String: Any] = ["title": title]
        // Google Tasks has no writable URL field — the `links` array is read-only.
        // Embedding the URL in notes with a separator (---url---) caused visible
        // marker text to appear in the Google Tasks UI. The URL already lives
        // natively in EKReminder.url on the Reminders side, so nothing is lost
        // by not mirroring it here. Parsing of the old separator is kept in
        // GoogleTask.init for backward compatibility with existing tasks.
        if let n = notes { taskData["notes"] = n }

        if let dueDate {
            taskData["due"] = Self.utcNoonString(from: dueDate)
        }

        guard let requestURL = try? tasksURL(listId: listId) else { completion?(nil); return }
        var request = URLRequest(url: requestURL)
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
                    if success { self?.createTask(listId: listId, title: title, notes: notes, dueDate: dueDate, url: url, completion: completion) }
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

    func completeTask(listId: String, taskId: String) {
        guard let token = authManager.getAccessToken() else { return }

        guard let requestURL = try? tasksURL(listId: listId, taskId: taskId) else { return }
        var request = URLRequest(url: requestURL)
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

    func updateTask(listId: String, taskId: String, title: String, notes: String?, isCompleted: Bool, dueDate: Date?) {
        guard let token = authManager.getAccessToken() else { return }

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

        guard let requestURL = try? tasksURL(listId: listId, taskId: taskId) else { return }
        var request = URLRequest(url: requestURL)
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
                        if success { self?.updateTask(listId: listId, taskId: taskId, title: title, notes: notes, isCompleted: isCompleted, dueDate: dueDate) }
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
    func moveTask(listId: String, taskId: String, previousTaskId: String?) {
        guard let token = authManager.getAccessToken() else { return }

        var queryItems: [URLQueryItem] = []
        if let prev = previousTaskId {
            queryItems.append(URLQueryItem(name: "previous", value: prev))
        }
        guard let requestURL = try? tasksURL(listId: listId, taskId: taskId, action: "move", query: queryItems) else { return }

        var request = URLRequest(url: requestURL)
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
                    if success { self?.moveTask(listId: listId, taskId: taskId, previousTaskId: previousTaskId) }
                }
            }
        }.resume()
    }

    func deleteTask(listId: String, taskId: String) {
        guard let token = authManager.getAccessToken() else { return }

        guard let requestURL = try? tasksURL(listId: listId, taskId: taskId) else { return }
        var request = URLRequest(url: requestURL)
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
                        if success { self?.deleteTask(listId: listId, taskId: taskId) }
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
    let listId:      String   // The Google Tasks list this task belongs to

    init?(from dict: [String: Any], listId: String) {
        guard let id    = dict["id"]    as? String,
              let title = dict["title"] as? String else { return nil }
        self.id          = id
        self.listId      = listId
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
