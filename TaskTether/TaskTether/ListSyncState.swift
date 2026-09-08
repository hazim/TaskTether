//
//  ListSyncState.swift
//  TaskTether
//
//  Created: 04/09/2026
//

import Foundation

// MARK: - ListSyncState
// Per-pair sync guards (D7). Before multi-list these were four globals on
// SyncEngine. They must be per pair now: an empty list is normal once every
// Reminders list participates, so a global "Google returned zero tasks"
// counter would either fire constantly or mask a genuine wipe on one pair.
//
// A reference type on purpose — SyncEngine keeps these in a dictionary and
// mutates them in place during a cycle, so value semantics would need a
// write-back on every touch.

final class ListSyncState {

    // Consecutive cycles in which this pair's Google list returned 0 tasks.
    var consecutiveGoogleZero: Int = 0

    // Consecutive cycles in which this pair's Reminders list returned 0 items.
    var consecutiveRemindersZero: Int = 0

    // Tasks that were absent from the other side last cycle. A task must be
    // absent for TWO consecutive cycles before it is deleted — this guards
    // against transient fetch failures.
    var remindersDeleteCandidates: Set<String> = []   // remindersIds
    var googleDeleteCandidates:    Set<String> = []   // googleIds
}

// MARK: - MoveDecision
// Result of the cross-list move check (D4). The associated value is always
// the id of the ListPair the lagging side must be moved into.

enum MoveDecision: Equatable {
    case none
    case moveGoogle(to: String)      // mirror a Reminders-side move onto Google
    case moveReminders(to: String)   // mirror a Google-side move onto Reminders
}

// MARK: - SideLocation / LinkDisposition (D11)
// Where one side of a linked (remindersId, googleTasksId) pair was found in
// this cycle's fetch.

enum SideLocation: Equatable {
    case pair(String)   // inside the active pair with this id
    case parked         // present, but outside every active pair
    case missing        // not seen at all this cycle
}

// What the engine is allowed to do with a link, given where its two sides sit.
enum LinkDisposition: Equatable {
    case park                                                   // suppress deletes and moves
    case evaluate(remindersPairId: String, googlePairId: String) // normal move check
    case dropLink                                               // provably dead — unlink and re-create
    case ignore                                                 // nothing to decide here
}

// MARK: - SyncFetchError (D12)
// A fetch that fails must abort the cycle rather than collapse to an empty
// list — an empty list is indistinguishable from "the user deleted everything",
// and three such cycles used to be enough to delete real tasks.

enum SyncFetchError: LocalizedError {
    case reminders(String?)        // detail from RemindersManager, when it has one
    case google(String, Error)     // Google list id, underlying transport/HTTP/parse error

    var errorDescription: String? {
        switch self {
        case .reminders(let detail):
            return String(format: String(localized: "error.sync.fetch.reminders"),
                          detail ?? "")
        case .google(let listId, let underlying):
            return String(format: String(localized: "error.sync.fetch.google"),
                          listId, underlying.localizedDescription)
        }
    }
}
