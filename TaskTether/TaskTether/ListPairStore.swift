//
//  ListPairStore.swift
//  TaskTether
//
//  Created: 04/09/2026
//

import Foundation

// MARK: - ListPairStore
// Persists the set of synced list pairs (D1) in UserDefaults, plus the
// retired set (D2: a pair whose other side disappeared, kept around so a
// reappearance-by-id can revive it instead of re-pairing by title).

final class ListPairStore {

    // MARK: - Keys

    private let pairsKey   = "tasktether_list_pairs"
    private let retiredKey = "tasktether_list_pairs_retired"
    private let defaults   = UserDefaults.standard

    // MARK: - Storage

    private(set) var pairs: [ListPair] {
        get { load(pairsKey) }
        set { save(newValue, pairsKey) }
    }

    private(set) var retired: [ListPair] {
        get { load(retiredKey) }
        set { save(newValue, retiredKey) }
    }

    private func load(_ key: String) -> [ListPair] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ListPair].self, from: data)
        else { return [] }
        return decoded
    }

    private func save(_ pairs: [ListPair], _ key: String) {
        guard let data = try? JSONEncoder().encode(pairs) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: - Mutation

    func add(_ pair: ListPair) {
        pairs.append(pair)
    }

    func update(_ pair: ListPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index] = pair
    }

    // Move an active pair to the retired set (D2).
    func retire(id: String) {
        guard let index = pairs.firstIndex(where: { $0.id == id }) else { return }
        let pair = pairs.remove(at: index)
        retired.append(pair)
    }

    // Move a retired pair back to the active set.
    func revive(id: String) {
        guard let index = retired.firstIndex(where: { $0.id == id }) else { return }
        let pair = retired.remove(at: index)
        pairs.append(pair)
    }

    // Remove a pair from either set entirely (e.g. re-paired by title).
    func remove(id: String) {
        pairs.removeAll { $0.id == id }
        retired.removeAll { $0.id == id }
    }

    // MARK: - Lookup

    func pair(forRemindersList id: String) -> ListPair? {
        pairs.first { $0.remindersListId == id }
    }

    func pair(forGoogleList id: String) -> ListPair? {
        pairs.first { $0.googleListId == id }
    }

    // MARK: - Reset

    func clear() {
        defaults.removeObject(forKey: pairsKey)
        defaults.removeObject(forKey: retiredKey)
    }
}
