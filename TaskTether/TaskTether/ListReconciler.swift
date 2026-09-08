//
//  ListReconciler.swift
//  TaskTether
//
//  Created: 04/09/2026
//

import Foundation

// MARK: - ListReconcilePlan
// The set of actions needed to bring stored pairs in line with the lists
// that actually exist right now. Pure data — SyncEngine executes it.
//
// Tuples are avoided in favour of small structs: an auto-synthesized
// Equatable conformance requires every stored property's type to itself
// conform to Equatable, and a tuple cannot conform to a protocol.

struct RenameChange: Equatable {
    let pair: ListPair
    let title: String
}

struct TitleMatch: Equatable {
    let reminders: ReminderList
    let google: GoogleTaskList
}

struct ListReconcilePlan: Equatable {
    var revive: [ListPair] = []                    // retired pair whose missing side is back by id
    var retire: [ListPair] = []                     // active pair with one (or both) sides missing
    var renameGoogle: [RenameChange] = []           // apply title to Google
    var renameReminders: [RenameChange] = []        // apply title to Reminders
    var pairByTitle: [TitleMatch] = []
    var createGoogle: [ReminderList] = []           // unpaired Reminders list → create Google list
    var createReminders: [GoogleTaskList] = []      // unpaired Google list → create Reminders list
}

// MARK: - ListLookup / ReconcileState
// Internal bookkeeping so the step functions below stay under the 3-argument
// guideline: one input list, one lookup table, one mutable accumulator.

private struct ListLookup {
    let remindersById: [String: ReminderList]
    let googleById: [String: GoogleTaskList]
}

private struct ReconcileState {
    var result = ListReconcilePlan()
    // Both sides accounted for by an active or revived pair — excluded
    // entirely from title-matching and creation.
    var claimedReminders = Set<String>()
    var claimedGoogle = Set<String>()
    // A lone surviving side of a pair that just went (or stayed) retired —
    // still eligible for a same-title match (D2), but never auto-created.
    var consumedReminders = Set<String>()
    var consumedGoogle = Set<String>()
}

// MARK: - ListReconciler
// Pure (no EventKit, no networking) so it can be exercised by a standalone
// `swift` script — see scratch/list-reconciler-test.swift.

enum ListReconciler {

    static func plan(pairs: [ListPair], retired: [ListPair],
                      reminders: [ReminderList], google: [GoogleTaskList]) -> ListReconcilePlan {
        let lookup = ListLookup(
            remindersById: Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) }),
            googleById: Dictionary(uniqueKeysWithValues: google.map { ($0.id, $0) })
        )
        var state = ReconcileState()
        processRetired(retired, lookup, &state)
        processActive(pairs, lookup, &state)
        planTitleMatches(reminders, google, &state)
        return state.result
    }

    // MARK: Rule 1 — retired pairs

    private static func processRetired(_ retired: [ListPair], _ lookup: ListLookup, _ state: inout ReconcileState) {
        for pair in retired {
            let hasReminders = lookup.remindersById[pair.remindersListId] != nil
            let hasGoogle = lookup.googleById[pair.googleListId] != nil
            if hasReminders && hasGoogle {
                state.result.revive.append(pair)
                state.claimedReminders.insert(pair.remindersListId)
                state.claimedGoogle.insert(pair.googleListId)
            } else if hasReminders {
                state.consumedReminders.insert(pair.remindersListId)
            } else if hasGoogle {
                state.consumedGoogle.insert(pair.googleListId)
            }
        }
    }

    // MARK: Rule 2 — active pairs

    private static func processActive(_ pairs: [ListPair], _ lookup: ListLookup, _ state: inout ReconcileState) {
        for pair in pairs {
            guard let r = lookup.remindersById[pair.remindersListId],
                  let g = lookup.googleById[pair.googleListId] else {
                retireActive(pair, lookup, &state)
                continue
            }
            state.claimedReminders.insert(pair.remindersListId)
            state.claimedGoogle.insert(pair.googleListId)
            planRename(pair, r.title, g.title, &state.result)
        }
    }

    // An active pair with one (or both) sides now missing: retire it, and
    // if one side survives, mark it consumed rather than claimed so it can
    // still be picked up by a same-title match this same pass.
    private static func retireActive(_ pair: ListPair, _ lookup: ListLookup, _ state: inout ReconcileState) {
        state.result.retire.append(pair)
        if lookup.remindersById[pair.remindersListId] != nil {
            state.consumedReminders.insert(pair.remindersListId)
        } else if lookup.googleById[pair.googleListId] != nil {
            state.consumedGoogle.insert(pair.googleListId)
        }
    }

    // MARK: Rule 2 — rename detection (D3)

    private static func planRename(_ pair: ListPair, _ remindersTitle: String, _ googleTitle: String,
                                    _ result: inout ListReconcilePlan) {
        let remindersChanged = remindersTitle != pair.title
        let googleChanged = googleTitle != pair.title
        guard remindersChanged || googleChanged else { return }
        if googleChanged && !remindersChanged {
            result.renameReminders.append(RenameChange(pair: pair, title: googleTitle))
        } else {
            // Reminders-only change, or both changed: Reminders wins.
            result.renameGoogle.append(RenameChange(pair: pair, title: remindersTitle))
        }
    }

    // MARK: Rules 4 & 5 — title matching, then leftovers become creates

    private static func planTitleMatches(_ reminders: [ReminderList], _ google: [GoogleTaskList],
                                          _ state: inout ReconcileState) {
        let reminderCandidates = reminders
            .filter { !state.claimedReminders.contains($0.id) }
            .sorted { ($0.title, $0.id) < ($1.title, $1.id) }
        var googleRemaining = google
            .filter { !state.claimedGoogle.contains($0.id) }
            .sorted { ($0.title, $0.id) < ($1.title, $1.id) }

        var matchedReminderIds = Set<String>()
        for r in reminderCandidates {
            guard let index = googleRemaining.firstIndex(where: { titlesMatch($0.title, r.title) }) else { continue }
            let g = googleRemaining.remove(at: index)
            state.result.pairByTitle.append(TitleMatch(reminders: r, google: g))
            matchedReminderIds.insert(r.id)
        }

        for r in reminderCandidates where !matchedReminderIds.contains(r.id) && !state.consumedReminders.contains(r.id) {
            state.result.createGoogle.append(r)
        }
        for g in googleRemaining where !state.consumedGoogle.contains(g.id) {
            state.result.createReminders.append(g)
        }
    }

    private static func titlesMatch(_ a: String, _ b: String) -> Bool {
        normalized(a) == normalized(b)
    }

    private static func normalized(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
