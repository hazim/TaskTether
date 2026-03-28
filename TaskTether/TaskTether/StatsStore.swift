//
//  StatsStore.swift
//  TaskTether
//
//  Created: 28/03/2026
//

import Foundation

// MARK: - DayStats

struct DayStats: Codable {
    let total:     Int
    let completed: Int

    var percentage: Int? {
        guard total > 0 else { return nil }
        return Int(Double(completed) / Double(total) * 100)
    }
}

// MARK: - StatsStore
// Persists daily completion stats in UserDefaults.
// Keyed by "yyyy-MM-dd" in the user's local timezone.
// Updated on every sync cycle by SyncEngine.
//
// Three bar states in the chart:
//   nil      → no bar      (no tasks were tracked that day)
//   0%       → short bar   (tasks existed, none were completed — bad day)
//   1–100%   → full bar    (normal completion)

final class StatsStore {

    private let key = "tasktether_daily_stats"
    private let calendar = Calendar.current

    // MARK: - Read

    private var all: [String: DayStats] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([String: DayStats].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    func stats(for date: Date = Date()) -> DayStats? {
        all[dayKey(date)]
    }

    func percentage(for date: Date = Date()) -> Int? {
        stats(for: date)?.percentage
    }

    // Returns 7 entries oldest → newest, today last.
    // nil = no data for that day.
    func weekStats(endingToday today: Date = Date()) -> [DayStats?] {
        (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - 6, to: today)!
            return stats(for: date)
        }
    }

    func weekPercentages(endingToday today: Date = Date()) -> [Int?] {
        weekStats(endingToday: today).map { $0?.percentage }
    }

    // MARK: - Write

    // Called by SyncEngine after every sync cycle.
    // Only records days where tasks exist — zero-task days produce no data.
    func record(total: Int, completed: Int, for date: Date = Date()) {
        guard total > 0 else { return }
        var current = all
        current[dayKey(date)] = DayStats(total: total, completed: completed)
        all = current
    }

    // Removes today's entry — called when todayTasks is empty so stale
    // data from a previous session doesn't show a false completion score.
    func clearToday() {
        var current = all
        current.removeValue(forKey: dayKey(Date()))
        all = current
    }

    // MARK: - Computed Stats

    var todayStats: DayStats? { stats(for: Date()) }
    var todayTotal:     Int { todayStats?.total     ?? 0 }
    var todayCompleted: Int { todayStats?.completed ?? 0 }
    var todayScore:     Int { todayStats?.percentage ?? 0 }

    var yesterdayStats: DayStats? {
        stats(for: calendar.date(byAdding: .day, value: -1, to: Date())!)
    }
    var yesterdayTotal:     Int { yesterdayStats?.total     ?? 0 }
    var yesterdayCompleted: Int { yesterdayStats?.completed ?? 0 }
    var yesterdayScore:     Int { yesterdayStats?.percentage ?? 0 }

    var delta: Int {
        guard let t = todayStats?.percentage,
              let y = yesterdayStats?.percentage
        else { return 0 }
        return t - y
    }

    // MARK: - Helpers

    private func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar   = calendar
        return f.string(from: date)
    }
}
