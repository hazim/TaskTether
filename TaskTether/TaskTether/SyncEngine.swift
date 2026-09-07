//
//  SyncEngine.swift
//  TaskTether
//
//  Created: 13/03/2026 · 22:00
//  Updated: 04/09/2026 · multi-list sync
//

import Foundation
import Combine
import EventKit

// MARK: - SyncState

enum SyncState: Equatable {
    case idle
    case syncing
    case error(String)
}

// MARK: - SyncEngine
//
// Syncs every paired (Reminders list ↔ Google Tasks list) in both directions.
// The per-pair primitives (repairLinks, buildDiff, buildReconciliationDiff,
// buildMergedList) are the same proven three-way merge as before; sync() is
// now an orchestration over ListPairStore.pairs.

class SyncEngine: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state:      SyncState = .idle
    @Published private(set) var tasks:      [TetherTask] = []
    @Published private(set) var lastSyncAt: Date? = nil

    // MARK: - Dependencies

    private let remindersManager:   RemindersManager
    private let googleTasksManager: GoogleTasksManager
    private let authManager:        GoogleAuthManager
    private let themeManager:       ThemeManager
    let idStore:                    IDStore       = IDStore()
    let statsStore:                 StatsStore    = StatsStore()
    let listPairStore:              ListPairStore = ListPairStore()
    private let snapshotStore:      SnapshotStore = SnapshotStore()
    private let failureNotifier:    SyncFailureNotifier = SyncFailureNotifier()

    // MARK: - Internal State

    private var previousSnapshot:    [TetherTask] = []
    private var timer:               Timer?
    private var isSyncing            = false

    // True when the next sync must run in reconciliation mode — see init.
    // Cleared after the first successful sync writes a fresh baseline.
    private var needsReconciliation  = false

    // Gap after which the baseline is no longer trusted for deletions.
    // 24 hours: comfortably longer than any normal between-sync interval,
    // comfortably shorter than "I stopped using the app for weeks".
    private static let reconciliationGap: TimeInterval = 24 * 60 * 60

    // Suspicious-zero counters and delete-candidate sets, per list pair (D7).
    // Keyed by ListPair.id. An empty list is normal now that every Reminders
    // list participates, so these can never be global again.
    private var listStates: [String: ListSyncState] = [:]

    // Linked tasks whose two sides still sit in different pairs after the move
    // pass — i.e. a cross-list move that could not be executed (offline, API
    // error, permission). Neither pair may read them as a deletion: the source
    // pair sees a reminder with no Google counterpart and the destination pair
    // the mirror image, and after two such cycles the normal candidate system
    // would delete the user's task. Refreshed every cycle.
    private var unmovedRids: Set<String> = []
    private var unmovedGids: Set<String> = []

    // Google list ids seen by the last successful reconcileLists(). Used to
    // fetch the lists no active pair owns, tolerantly, when looking for
    // parked links (D11).
    private var lastKnownGoogleListIds: [String] = []

    // False when the last reconcileLists() could not trust its list fetch, so
    // the parked pool may be incomplete and no link may be called dead.
    private var lastListFetchSucceeded = false

    // MARK: - Init

    init(
        remindersManager:   RemindersManager,
        googleTasksManager: GoogleTasksManager,
        authManager:        GoogleAuthManager,
        themeManager:       ThemeManager
    ) {
        self.remindersManager   = remindersManager
        self.googleTasksManager = googleTasksManager
        self.authManager        = authManager
        self.themeManager       = themeManager

        // Restore the baseline from the previous session so the first sync
        // after a relaunch performs a real three-way merge instead of
        // starting blind. A snapshot written before multi-list sync has no
        // list attribution, so SnapshotStore.load() returns nil for it and
        // the first sync runs in reconciliation mode (D8) — never deleting.
        let restored          = snapshotStore.load()
        self.previousSnapshot = restored ?? []
        self.lastSyncAt       = snapshotStore.lastSyncAt

        // Seed the published list from the persisted baseline so the menu
        // bar badge and task list show immediately on cold launch, instead
        // of sitting blank until the first sync round-trip completes. Plain
        // assignment only — no stats recording, no persistBaseline() call.
        // The subsequent sync() reconciles as before and can revise this.
        if let restored {
            self.tasks = sortedByOrder(restored)
        }

        // Reconciliation is required when there is no baseline at all, or
        // the last sync is older than the gap threshold. In either case the
        // stored links may point at tasks that were deleted or re-created
        // while the app was off, so the first sync must not delete anything.
        let lastSync = snapshotStore.lastSyncAt
        self.needsReconciliation = restored == nil
            || lastSync == nil
            || Date().timeIntervalSince(lastSync!) > Self.reconciliationGap
    }

    // MARK: - Baseline Persistence

    // Called at every point previousSnapshot is reassigned so the on-disk
    // baseline can never drift from the in-memory one.
    private func persistBaseline() {
        snapshotStore.save(previousSnapshot)
        snapshotStore.lastSyncAt = lastSyncAt
    }

    // MARK: - Lifecycle

    func start() {
        scheduleTimer()
        scheduleMidnightRefresh()
        Task { await sync() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Timer

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(themeManager.syncInterval * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.rescheduleIfIntervalChanged()
            Task { await self?.sync() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func rescheduleIfIntervalChanged() {
        let expected = TimeInterval(themeManager.syncInterval * 60)
        guard let current = timer,
              abs(current.timeInterval - expected) > 1 else { return }
        scheduleTimer()
    }

    func syncNow() {
        Task { await sync() }
    }

    // MARK: - Per-Pair Buckets

    // One list pair's tasks for one fetch round. Every TetherTask in here
    // already carries listPairId.
    private struct PairBucket {
        var reminders: [TetherTask] = []
        var google:    [TetherTask] = []
    }

    // Everything one pair's diff needs. Bundled so the diff primitives keep
    // a single parameter instead of four positional arrays.
    private struct PairContext {
        let pair:      ListPair
        let reminders: [TetherTask]
        let google:    [TetherTask]
        let previous:  [TetherTask]
    }

    private struct DiffGuards {
        let googleSuspicious:    Bool
        let remindersSuspicious: Bool
    }

    private func syncState(for pairId: String) -> ListSyncState {
        if let existing = listStates[pairId] { return existing }
        let fresh = ListSyncState()
        listStates[pairId] = fresh
        return fresh
    }

    private func pair(withId id: String) -> ListPair? {
        listPairStore.pairs.first { $0.id == id }
    }

    // MARK: - Sync Cycle

    // Signed in but the initial list fetch failed (offline launch): ask
    // GoogleTasksManager to try again. setup() is a no-op while connected.
    @MainActor
    private func retryConnectionIfNeeded() {
        guard authManager.isAuthenticated, !googleTasksManager.isConnected else { return }
        googleTasksManager.setup()
    }

    @MainActor
    private func sync() async {
        guard !isSyncing,
              authManager.isAuthenticated,
              remindersManager.isAuthorised,
              googleTasksManager.isConnected else {
            if state == .syncing { state = .idle }
            retryConnectionIfNeeded()
            return
        }

        isSyncing = true
        state     = .syncing

        do {
            await reconcileLists()

            var round = try await fetchAllPairs()
            let survey = surveyLinks(round)
            dropDeadLinks(survey, round)
            round.buckets = await applyMoves(survey.moves, round.buckets)
            recordSuppressedLinks(round)

            var diffs: [String: SyncDiff] = [:]
            for pair in listPairStore.pairs {
                guard let bucket = round.buckets[pair.id] else { continue }
                let diff = diffPair(pair, bucket)
                await applyDiff(diff, pair: pair)
                diffs[pair.id] = diff
            }

            // Re-fetch both sides after applying diffs so order and merge
            // reflect any tasks that were created during applyDiff.
            let fresh = try await fetchAllPairs()
            finish(fresh: fresh.buckets, diffs: diffs)

        } catch {
            state = .error(error.localizedDescription)
            failureNotifier.recordFailure(error.localizedDescription)
        }

        isSyncing = false
    }

    // Chooses reconciliation or normal diffing for one pair (D8 / D7).
    @MainActor
    private func diffPair(_ pair: ListPair, _ bucket: PairBucket) -> SyncDiff {
        let ctx = PairContext(
            pair:      pair,
            reminders: bucket.reminders,
            google:    bucket.google,
            previous:  previousSnapshot.filter { $0.listPairId == pair.id }
        )
        guard needsReconciliation else { return buildDiff(ctx) }
        #if DEBUG
        print("SyncEngine: reconciliation sync for '\(pair.title)' — links repaired, no deletions")
        #endif
        repairLinks(ctx)
        return buildReconciliationDiff(ctx)
    }

    // MARK: - List Reconciliation (D1, D2, D3)

    // Brings ListPairStore in line with the lists that actually exist, then
    // creates/renames the missing counterparts. A pair whose side vanished is
    // RETIRED, never removed, and no task is ever deleted here.
    @MainActor
    private func reconcileLists() async {
        lastListFetchSucceeded = false
        let reminders = remindersManager.fetchLists()
        guard let google = await fetchGoogleLists(),
              listFetchLooksSane(reminders: reminders, google: google) else { return }
        lastListFetchSucceeded = true

        // Kept so the parked pool (D11) can look inside Google lists that no
        // active pair owns — retired ones, and any whose pairing failed.
        lastKnownGoogleListIds = google.map { $0.id }

        let plan = ListReconciler.plan(
            pairs:     listPairStore.pairs,
            retired:   listPairStore.retired,
            reminders: reminders,
            google:    google
        )
        executeRevives(plan.revive)
        executeRetires(plan.retire)
        await executeRenames(plan)
        // Deliberately inline (rather than a helper taking the element type):
        // the plan's match element may be a tuple or a small struct depending
        // on Equatable synthesis, and inference keeps this working either way.
        for match in plan.pairByTitle {
            adoptTitleMatch(reminders: match.reminders, google: match.google)
        }
        await executeCreations(plan)
    }

    // An empty side while pairs exist means a failed/flickering fetch far more
    // often than "the user deleted every list", and acting on it would retire
    // everything. Skip the whole reconciliation pass instead.
    private func listFetchLooksSane(reminders: [ReminderList], google: [GoogleTaskList]) -> Bool {
        guard !listPairStore.pairs.isEmpty else { return true }
        return !reminders.isEmpty && !google.isEmpty
    }

    private func executeRevives(_ pairs: [ListPair]) {
        for pair in pairs { listPairStore.revive(id: pair.id) }
    }

    // Retiring keeps the pair (and every task on the surviving side) intact —
    // it only stops syncing it. The per-pair guard state goes with it so a
    // later revive starts from a clean slate.
    private func executeRetires(_ pairs: [ListPair]) {
        for pair in pairs {
            listPairStore.retire(id: pair.id)
            listStates[pair.id] = nil
            #if DEBUG
            print("SyncEngine: retired list pair '\(pair.title)' — tasks kept, syncing stopped")
            #endif
        }
    }

    @MainActor
    private func executeRenames(_ plan: ListReconcilePlan) async {
        for item in plan.renameGoogle {
            guard await renameGoogleList(id: item.pair.googleListId, title: item.title) else { continue }
            updateTitle(of: item.pair, to: item.title)
        }
        for item in plan.renameReminders {
            guard remindersManager.renameList(id: item.pair.remindersListId, title: item.title) else { continue }
            updateTitle(of: item.pair, to: item.title)
        }
    }

    private func updateTitle(of pair: ListPair, to title: String) {
        var updated = pair
        updated.title = title
        listPairStore.update(updated)
    }

    // A retired pair whose survivor is being re-paired by title is superseded
    // by the new pair (spec rule 1) — otherwise a later revive would resurrect
    // a duplicate link to the same list. Removing the retired record never
    // touches a task; the survivor keeps everything and simply joins a new pair.
    private func adoptTitleMatch(reminders: ReminderList, google: GoogleTaskList) {
        for retired in listPairStore.retired
        where retired.remindersListId == reminders.id
           || retired.googleListId    == google.id {
            listPairStore.remove(id: retired.id)
        }
        listPairStore.add(ListPair(
            id:              UUID().uuidString,
            remindersListId: reminders.id,
            googleListId:    google.id,
            title:           reminders.title
        ))
    }

    // A failed create logs and skips that list; it never aborts the sync.
    @MainActor
    private func executeCreations(_ plan: ListReconcilePlan) async {
        for list in plan.createGoogle {
            guard let created = await createGoogleList(title: list.title) else { continue }
            listPairStore.add(ListPair(
                id: UUID().uuidString, remindersListId: list.id,
                googleListId: created.id, title: list.title
            ))
        }
        for list in plan.createReminders {
            guard let remindersListId = remindersManager.createList(title: list.title) else { continue }
            listPairStore.add(ListPair(
                id: UUID().uuidString, remindersListId: remindersListId,
                googleListId: list.id, title: list.title
            ))
        }
    }

    // MARK: - Google List Bridges

    @MainActor
    private func fetchGoogleLists() async -> [GoogleTaskList]? {
        await withCheckedContinuation { continuation in
            googleTasksManager.fetchTaskLists { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    @MainActor
    private func createGoogleList(title: String) async -> GoogleTaskList? {
        await withCheckedContinuation { continuation in
            googleTasksManager.createTaskList(title: title) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    @MainActor
    private func renameGoogleList(id: String, title: String) async -> Bool {
        await withCheckedContinuation { continuation in
            googleTasksManager.renameTaskList(id: id, title: title) { result in
                continuation.resume(returning: (try? result.get()) != nil)
            }
        }
    }

    // MARK: - Fetch

    // Tasks that are linked but live outside every active pair: reminders in
    // an unpaired or ineligible calendar, Google tasks in a retired pair's
    // list. They are never synced — they exist only so surveyLinks can tell
    // "moved somewhere we don't sync" apart from "deleted" (D11).
    private struct ParkedPool {
        var reminders: [TetherTask] = []
        var google:    [TetherTask] = []
    }

    private struct FetchRound {
        var buckets: [String: PairBucket] = [:]
        var parked:  ParkedPool           = ParkedPool()
        // True when the parked pool may be incomplete. "Found nowhere" is then
        // not trustworthy, so no link may be dropped as dead this cycle.
        var parkedFetchFailed             = false
    }

    // Fetches every active pair's two sides, plus the parked pool. Reminders
    // are fetched ONCE for all lists and grouped by calendar; Google is
    // fetched per pair. Any failure on an ACTIVE pair throws (D12).
    @MainActor
    private func fetchAllPairs() async throws -> FetchRound {
        let remindersByList = try await fetchRemindersByList()
        var round = FetchRound()
        for pair in listPairStore.pairs {
            let google = try await fetchGoogleTasks(listId: pair.googleListId)
            round.buckets[pair.id] = PairBucket(
                reminders: tagged(remindersByList[pair.remindersListId] ?? [], pair.id),
                google:    tagged(google, pair.id)
            )
        }
        (round.parked, round.parkedFetchFailed) = await fetchParkedPool(remindersByList)
        return round
    }

    @MainActor
    private func fetchParkedPool(_ remindersByList: [String: [TetherTask]]) async -> (ParkedPool, Bool) {
        let activeCalendars = Set(listPairStore.pairs.map { $0.remindersListId })
        var pool   = ParkedPool()
        var failed = !lastListFetchSucceeded
        for (listId, tasks) in remindersByList where !activeCalendars.contains(listId) {
            pool.reminders += tasks
        }
        for listId in unpairedGoogleListIds() {
            switch await googleTasksResult(listId: listId) {
            case .success(let googleTasks): pool.google += googleTasks.map { TetherTask(from: $0) }
            case .failure:                  failed = true
            }
        }
        return (pool, failed)
    }

    // Only lists Google itself named in this cycle's reconcile. A retired
    // pair whose list was deleted is not fetched at all — nothing can be
    // parked in a list that no longer exists, and skipping it keeps expected
    // 404s from permanently setting the parked-failure flag.
    private func unpairedGoogleListIds() -> [String] {
        let active = Set(listPairStore.pairs.map { $0.googleListId })
        return Array(Set(lastKnownGoogleListIds).subtracting(active))
    }

    private func tagged(_ tasks: [TetherTask], _ pairId: String) -> [TetherTask] {
        tasks.map { task in
            var copy = task
            copy.listPairId = pairId
            return copy
        }
    }

    // nil from EventKit means the fetch FAILED (not authorised, store error) —
    // NOT "every list is empty". Collapsing the two is how an offline stretch
    // used to delete real tasks, so this throws and the cycle aborts (D12).
    @MainActor
    private func fetchRemindersByList() async throws -> [String: [TetherTask]] {
        let grouped: [String: [TetherTask]]? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let reminders = self.remindersManager.fetchTasks() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.groupByCalendar(reminders))
            }
        }
        guard let grouped else { throw SyncFetchError.reminders(remindersManager.errorMessage) }
        return grouped
    }

    private static func groupByCalendar(_ reminders: [EKReminder]) -> [String: [TetherTask]] {
        var grouped: [String: [TetherTask]] = [:]
        for reminder in reminders {
            guard let listId = reminder.calendar?.calendarIdentifier else { continue }
            grouped[listId, default: []].append(TetherTask(from: reminder))
        }
        return grouped
    }

    // Active-pair fetch: any transport/HTTP/parse/auth failure aborts the
    // cycle rather than presenting the list as empty (D12).
    @MainActor
    private func fetchGoogleTasks(listId: String) async throws -> [TetherTask] {
        switch await googleTasksResult(listId: listId) {
        case .success(let googleTasks): return googleTasks.map { TetherTask(from: $0) }
        case .failure(let error):       throw SyncFetchError.google(listId, error)
        }
    }

    @MainActor
    private func googleTasksResult(listId: String) async -> Result<[GoogleTask], Error> {
        await withCheckedContinuation { continuation in
            googleTasksManager.fetchTasks(listId: listId) { continuation.resume(returning: $0) }
        }
    }

    // MARK: - Move Pass (D4)
    //
    // Runs BEFORE any per-pair diff. A task dragged to another list on one
    // side is present in pair A's fetch and absent from pair B's; without
    // this pass pair B would read it as a deletion and pair A as a stray
    // link, and the next cycle would delete the user's task.

    // Pure: given where a linked task sat at the last sync and where each
    // side sits now, decide which side moved. The side still matching the
    // previous pair did NOT move, so the other one did. Unknown previous →
    // Reminders wins.
    static func moveDecision(
        previousPairId:  String?,
        remindersPairId: String,
        googlePairId:    String
    ) -> MoveDecision {
        if remindersPairId == googlePairId { return .none }
        if previousPairId == remindersPairId { return .moveReminders(to: googlePairId) }
        return .moveGoogle(to: remindersPairId)
    }

    private struct PendingMove {
        let remindersId:     String
        let googleId:        String
        let remindersPairId: String
        let googlePairId:    String
        let decision:        MoveDecision
    }

    // Where a bucket entry has to be re-filed after a successful move.
    private struct BucketMove {
        let oldId: String
        let newId: String
        let from:  String   // pair id
        let to:    String   // pair id
    }

    // Pure: what may be done with a link, given where its two sides were found.
    // A side that is PARKED — present, but in a list no active pair owns — is
    // the case that used to lose data: the other pair saw only "my counterpart
    // is gone" and deleted it two cycles later. Parking suppresses both the
    // deletion and any move (D11).
    static func linkDisposition(
        reminders: SideLocation,
        google:    SideLocation,
        newPairIds: Set<String>
    ) -> LinkDisposition {
        if reminders == .parked || google == .parked { return .park }
        if case .pair(let remindersPairId) = reminders {
            if case .pair(let googlePairId) = google {
                return .evaluate(remindersPairId: remindersPairId, googlePairId: googlePairId)
            }
            // Surviving side in a pair with no baseline, counterpart found
            // nowhere: the link points at something that no longer exists and
            // no baseline can speak for it. Drop it so the task is re-created.
            return newPairIds.contains(remindersPairId) ? .dropLink : .ignore
        }
        if case .pair(let googlePairId) = google {
            return newPairIds.contains(googlePairId) ? .dropLink : .ignore
        }
        return .ignore
    }

    private struct LinkSurvey {
        var moves:      [PendingMove] = []
        var parkedRids: Set<String>   = []
        var parkedGids: Set<String>   = []
        var deadRids:   Set<String>   = []   // links to unlink (keyed by remindersId)
    }

    private struct LinkLocations {
        var reminders: [String: SideLocation] = [:]
        var google:    [String: SideLocation] = [:]
    }

    // Classifies every stored link once: park it, plan a move for it, or leave
    // it to the normal per-pair diff.
    @MainActor
    private func surveyLinks(_ round: FetchRound) -> LinkSurvey {
        let locations         = linkLocations(round)
        let previousPairByRid = previousPairIds()
        let newPairIds        = emptyBaselinePairIds()
        var survey = LinkSurvey()

        for (rid, gid) in idStore.refs {
            switch Self.linkDisposition(reminders:  locations.reminders[rid] ?? .missing,
                                        google:     locations.google[gid]    ?? .missing,
                                        newPairIds: newPairIds) {
            case .ignore:
                continue
            case .dropLink:
                survey.deadRids.insert(rid)
            case .park:
                survey.parkedRids.insert(rid)
                survey.parkedGids.insert(gid)
            case .evaluate(let remindersPairId, let googlePairId):
                let decision = Self.moveDecision(previousPairId:  previousPairByRid[rid],
                                                 remindersPairId: remindersPairId,
                                                 googlePairId:    googlePairId)
                guard decision != .none else { continue }
                survey.moves.append(PendingMove(remindersId: rid, googleId: gid,
                                                remindersPairId: remindersPairId,
                                                googlePairId: googlePairId, decision: decision))
            }
        }
        return survey
    }

    // Pairs the baseline says nothing about: created this cycle, or re-created
    // after a retire. The two-cycle deletion logic has no evidence there, which
    // is exactly why the dead-link drop is confined to them.
    private func emptyBaselinePairIds() -> Set<String> {
        let withBaseline = Set(previousSnapshot.compactMap { $0.listPairId })
        return Set(listPairStore.pairs.map { $0.id }).subtracting(withBaseline)
    }

    // Unlinks provably dead links so the normal diff re-creates the survivor on
    // the other side. Skipped whenever the parked pool may be incomplete —
    // "found nowhere" would then be a guess, and unlinking a live task creates
    // a duplicate.
    @MainActor
    private func dropDeadLinks(_ survey: LinkSurvey, _ round: FetchRound) {
        guard !round.parkedFetchFailed, !survey.deadRids.isEmpty else { return }
        for rid in survey.deadRids {
            idStore.unlink(remindersId: rid)
        }
        #if DEBUG
        print("SyncEngine: dropped \(survey.deadRids.count) dead link(s) in newly-baselined pairs")
        #endif
    }

    private func linkLocations(_ round: FetchRound) -> LinkLocations {
        var locations = LinkLocations()
        for (pairId, bucket) in round.buckets {
            for task in bucket.reminders {
                if let rid = task.remindersId { locations.reminders[rid] = .pair(pairId) }
            }
            for task in bucket.google {
                if let gid = task.googleTasksId { locations.google[gid] = .pair(pairId) }
            }
        }
        for task in round.parked.reminders {
            if let rid = task.remindersId { locations.reminders[rid] = .parked }
        }
        for task in round.parked.google {
            if let gid = task.googleTasksId { locations.google[gid] = .parked }
        }
        return locations
    }

    @MainActor
    private func applyMoves(_ moves: [PendingMove], _ buckets: [String: PairBucket]) async -> [String: PairBucket] {
        guard !moves.isEmpty else { return buckets }
        var result = buckets
        for move in moves {
            result = await execute(move, in: result)
        }
        return result
    }

    // Re-surveys after the moves ran. Anything still mismatched did not move,
    // and anything parked stays parked; both are excluded from every pair's
    // diff so neither side can be read as a deletion.
    @MainActor
    private func recordSuppressedLinks(_ round: FetchRound) {
        let survey = surveyLinks(round)
        unmovedRids = survey.parkedRids.union(survey.moves.map { $0.remindersId })
        unmovedGids = survey.parkedGids.union(survey.moves.map { $0.googleId })
        #if DEBUG
        if !unmovedRids.isEmpty {
            print("SyncEngine: \(survey.moves.count) unresolved move(s), \(survey.parkedRids.count) parked link(s) — deletions suppressed")
        }
        #endif
    }

    private func previousPairIds() -> [String: String] {
        previousSnapshot.reduce(into: [String: String]()) { result, task in
            guard let rid = task.remindersId, let pairId = task.listPairId else { return }
            result[rid] = pairId
        }
    }

    @MainActor
    private func execute(_ move: PendingMove, in buckets: [String: PairBucket]) async -> [String: PairBucket] {
        switch move.decision {
        case .none:
            return buckets
        case .moveGoogle(let target):
            guard let to   = pair(withId: target)?.googleListId,
                  let from = pair(withId: move.googlePairId)?.googleListId,
                  let newId = await moveGoogleTask(move.googleId, from: from, to: to)
            else { return buckets }
            return refileGoogle(BucketMove(oldId: move.googleId, newId: newId,
                                           from: move.googlePairId, to: target), buckets)
        case .moveReminders(let target):
            guard let to = pair(withId: target)?.remindersListId,
                  moveReminder(move.remindersId, toListId: to) else { return buckets }
            return refileReminder(BucketMove(oldId: move.remindersId, newId: move.remindersId,
                                             from: move.remindersPairId, to: target), buckets)
        }
    }

    @MainActor
    private func moveGoogleTask(_ googleId: String, from: String, to: String) async -> String? {
        await withCheckedContinuation { continuation in
            googleTasksManager.moveTaskToList(taskId: googleId, from: from, to: to) { result in
                guard let moved = try? result.get() else {
                    continuation.resume(returning: nil)
                    return
                }
                self.relinkMovedGoogleTask(googleId, to: moved.id)
                continuation.resume(returning: moved.id)
            }
        }
    }

    // Google normally preserves the task id across a cross-list move, but the
    // API returns the moved resource, so honour whatever id came back.
    private func relinkMovedGoogleTask(_ oldId: String, to newId: String) {
        guard oldId != newId, let rid = idStore.remindersId(for: oldId) else { return }
        idStore.link(remindersId: rid, googleId: newId)
    }

    @MainActor
    private func moveReminder(_ remindersId: String, toListId: String) -> Bool {
        guard let reminder = remindersManager.fetchTask(by: remindersId) else { return false }
        return remindersManager.moveTask(reminder, toListId: toListId)
    }

    private func refileGoogle(_ move: BucketMove, _ buckets: [String: PairBucket]) -> [String: PairBucket] {
        var result = buckets
        guard let index = result[move.from]?.google.firstIndex(where: { $0.googleTasksId == move.oldId })
        else { return result }
        var task = result[move.from]!.google.remove(at: index)
        task.googleTasksId = move.newId
        task.listPairId    = move.to
        result[move.to, default: PairBucket()].google.append(task)
        return result
    }

    private func refileReminder(_ move: BucketMove, _ buckets: [String: PairBucket]) -> [String: PairBucket] {
        var result = buckets
        guard let index = result[move.from]?.reminders.firstIndex(where: { $0.remindersId == move.oldId })
        else { return result }
        var task = result[move.from]!.reminders.remove(at: index)
        task.listPairId = move.to
        result[move.to, default: PairBucket()].reminders.append(task)
        return result
    }

    // MARK: - Diff

    private struct SyncDiff {
        var addToReminders:                [TetherTask] = []
        var addToGoogle:                   [TetherTask] = []
        var updateInGoogle:                [TetherTask] = []
        var updateInReminders:             [TetherTask] = []
        var deleteFromReminders:           [String]     = []
        var deleteFromGoogle:              [String]     = []
        var addToRemindersDeleteCandidates: Set<String>  = []
        var addToGoogleDeleteCandidates:    Set<String>  = []
    }

    @MainActor
    private func buildDiff(_ ctx: PairContext) -> SyncDiff {
        let guards = DiffGuards(
            googleSuspicious:    updateGoogleZeroGuard(ctx),
            remindersSuspicious: updateRemindersZeroGuard(ctx)
        )
        var diff = SyncDiff()
        let processedGids = diffRemindersSide(ctx, guards, into: &diff)
        diffGoogleSide(ctx, guards, skipping: processedGids, into: &diff)
        return diff
    }

    // Safety valve, per pair: Google returning 0 tasks could be a network
    // failure. We treat it as suspicious on the FIRST zero cycle only. If
    // Google returns 0 for TWO consecutive cycles, it's genuine — allow
    // deletions. This handles the case where the user deletes the last task.
    //
    // The guard only ever fires when this pair's own baseline had tasks, so a
    // list that is simply empty on both sides (normal now) never suppresses
    // anything and never marks a delete candidate.
    @MainActor
    private func updateGoogleZeroGuard(_ ctx: PairContext) -> Bool {
        let listState = syncState(for: ctx.pair.id)
        listState.consecutiveGoogleZero = ctx.google.isEmpty ? listState.consecutiveGoogleZero + 1 : 0
        let suspicious = ctx.google.isEmpty && !ctx.previous.isEmpty && listState.consecutiveGoogleZero < 2
        #if DEBUG
        if suspicious {
            print("SyncEngine: '\(ctx.pair.title)' Google returned 0 tasks (cycle \(listState.consecutiveGoogleZero)/2) — skipping deletions")
        }
        #endif
        return suspicious
    }

    // Symmetric safety valve: Reminders returning 0 items for this list could
    // be a transient EventKit glitch (authorisation flicker, calendar
    // momentarily missing) rather than the user deleting everything.
    // RemindersManager.fetchTasks() never throws — every failure mode
    // surfaces as an empty array, so an empty fetch is the only signal we
    // have and must be treated the way a Google zero-fetch is.
    @MainActor
    private func updateRemindersZeroGuard(_ ctx: PairContext) -> Bool {
        let listState = syncState(for: ctx.pair.id)
        listState.consecutiveRemindersZero = ctx.reminders.isEmpty ? listState.consecutiveRemindersZero + 1 : 0
        let suspicious = ctx.reminders.isEmpty && !ctx.previous.isEmpty && listState.consecutiveRemindersZero < 2
        #if DEBUG
        if suspicious {
            print("SyncEngine: '\(ctx.pair.title)' Reminders returned 0 tasks (cycle \(listState.consecutiveRemindersZero)/2) — skipping deletions")
        }
        #endif
        return suspicious
    }

    // Walks this pair's reminders. Returns the Google ids it handled, so the
    // Google pass only processes unlinked tasks.
    @MainActor
    private func diffRemindersSide(
        _ ctx:    PairContext,
        _ guards: DiffGuards,
        into diff: inout SyncDiff
    ) -> Set<String> {
        let googleByGid = Dictionary(uniqueKeysWithValues:
            ctx.google.compactMap { t in t.googleTasksId.map { ($0, t) } })
        // reduce (not uniqueKeysWithValues) so a duplicate cannot crash us.
        let prevByRid: [String: TetherTask] = ctx.previous
            .compactMap { t in t.remindersId.map { ($0, t) } }
            .reduce(into: [:]) { $0[$1.0] = $1.1 }

        var processedGids = Set<String>()
        for rTask in ctx.reminders {
            guard let rid = rTask.remindersId, !unmovedRids.contains(rid) else { continue }
            guard let gid = idStore.googleId(for: rid) else {
                diff.addToGoogle.append(rTask)
                continue
            }
            processedGids.insert(gid)
            if let gTask = googleByGid[gid] {
                mergeLinkedPair(rTask, gTask, previous: prevByRid[rid], into: &diff)
            } else if prevByRid[rid] != nil {
                resolveMissingGoogleSide(rTask, ctx, guards, into: &diff)
            }
        }
        return processedGids
    }

    // Both sides present: three-way merge against the baseline.
    @MainActor
    private func mergeLinkedPair(
        _ rTask: TetherTask,
        _ gTask: TetherTask,
        previous: TetherTask?,
        into diff: inout SyncDiff
    ) {
        // No previous snapshot for this task yet — happens on the first cycle
        // after a task is linked. Small metadata differences (notes
        // normalisation, date precision) would cause spurious writes. Safe to
        // skip: the next cycle has a proper baseline.
        guard let prev = previous else { return }

        let rChanged = differs(rTask, from: prev)
        let gChanged = differs(gTask, from: prev)

        if rChanged && !gChanged {
            diff.updateInGoogle.append(rTask)              // only Reminders changed
        } else if gChanged && !rChanged {
            diff.updateInReminders.append(gTask)           // only Google changed
        } else if rChanged && gChanged {
            // Both changed → last-modified wins.
            if rTask.lastModified >= gTask.lastModified {
                diff.updateInGoogle.append(rTask)
            } else {
                diff.updateInReminders.append(gTask)
            }
        }
    }

    private func differs(_ task: TetherTask, from previous: TetherTask) -> Bool {
        task.isCompleted != previous.isCompleted
            || task.title   != previous.title
            || task.notes   != previous.notes
            || task.dueDate != previous.dueDate
    }

    // A linked reminder whose Google counterpart is gone from this pair.
    @MainActor
    private func resolveMissingGoogleSide(
        _ rTask:  TetherTask,
        _ ctx:    PairContext,
        _ guards: DiffGuards,
        into diff: inout SyncDiff
    ) {
        guard let rid = rTask.remindersId else { return }
        let listState = syncState(for: ctx.pair.id)

        if rTask.isCompleted {
            // Completed task absent from Google — always intentional.
            // Completed tasks don't vanish due to network failures, so this
            // bypasses googleSuspicious entirely.
            diff.deleteFromReminders.append(rid)
        } else if listState.remindersDeleteCandidates.contains(rid) && !guards.googleSuspicious {
            // Already a candidate AND Google not suspicious → fire deletion.
            diff.deleteFromReminders.append(rid)
        } else {
            // First absence OR Google suspicious → become/stay a candidate.
            // Always added regardless of googleSuspicious so the deletion
            // fires on the very next non-suspicious cycle.
            diff.addToRemindersDeleteCandidates.insert(rid)
        }
    }

    @MainActor
    private func diffGoogleSide(
        _ ctx:    PairContext,
        _ guards: DiffGuards,
        skipping processedGids: Set<String>,
        into diff: inout SyncDiff
    ) {
        let remindersByRid = Dictionary(uniqueKeysWithValues:
            ctx.reminders.compactMap { t in t.remindersId.map { ($0, t) } })
        let prevRids = Set(ctx.previous.compactMap { $0.remindersId })

        for gTask in ctx.google {
            guard let gid = gTask.googleTasksId,
                  !processedGids.contains(gid),
                  !unmovedGids.contains(gid) else { continue }
            guard let rid = idStore.remindersId(for: gid) else {
                // Never create a completed task in Reminders — it was
                // intentionally removed there when done, and re-creating it
                // would undo the user's completion.
                if !gTask.isCompleted { diff.addToReminders.append(gTask) }
                continue
            }
            guard remindersByRid[rid] == nil, !guards.remindersSuspicious else { continue }
            resolveMissingRemindersSide(gTask, ctx, hadBaseline: prevRids.contains(rid), into: &diff)
        }
    }

    // A linked Google task whose reminder is gone from this pair.
    //
    // remindersSuspicious guards the whole caller branch and is deliberately
    // STRICTER than googleSuspicious: googleSuspicious only gates firing an
    // already-confirmed delete candidate, but a suspicious Reminders cycle
    // also blocks adding new candidates AND the completed-task fast path.
    // Rationale: when this list just returned 0 items and its baseline had
    // tasks, a "missing" reminder is indistinguishable from a transient
    // EventKit glitch — data safety wins over parity with the Google side.
    // Consequence: a genuine "all reminders deleted" takes 3 cycles to
    // propagate to Google instead of 2.
    @MainActor
    private func resolveMissingRemindersSide(
        _ gTask: TetherTask,
        _ ctx:   PairContext,
        hadBaseline: Bool,
        into diff: inout SyncDiff
    ) {
        guard let gid = gTask.googleTasksId else { return }
        let listState = syncState(for: ctx.pair.id)

        if listState.googleDeleteCandidates.contains(gid) {
            diff.deleteFromGoogle.append(gid)          // confirmed last cycle
        } else if gTask.isCompleted {
            diff.deleteFromGoogle.append(gid)          // intentional, no guard needed
        } else if hadBaseline {
            diff.addToGoogleDeleteCandidates.insert(gid)
        }
    }

    // MARK: - Reconciliation
    //
    // Runs as the FIRST sync when the app has been off long enough that the
    // stored links can no longer be trusted (baseline missing or unusable,
    // or last sync older than reconciliationGap). Rules:
    //
    //   1. NO deletions on either side, ever. A task absent from one side
    //      might have been deleted intentionally weeks ago — but it might
    //      also be a re-created duplicate or a transient fetch gap. Genuine
    //      deletions still propagate, one cycle later, via the normal
    //      candidate system once a fresh baseline exists.
    //   2. Links whose Google side vanished are re-pointed at an unlinked
    //      Google task with the same title when one exists — this heals the
    //      common "deleted and re-typed while rearranging" case without
    //      creating duplicates.
    //   3. Linked pairs whose content differs are resolved by real
    //      modification timestamps — newer side wins, regardless of platform.
    //   4. Everything unlinked is merged additively.
    //
    // Worst case after a very long gap is a resurrected or duplicated task
    // the user deletes once by hand — never silent data loss.

    // Re-points links whose Google side no longer exists at an unlinked
    // Google task with an identical title and completion state, when
    // available. Mutates IDStore directly. Scoped to one pair.
    @MainActor
    private func repairLinks(_ ctx: PairContext) {
        let googleByGid = Dictionary(uniqueKeysWithValues:
            ctx.google.compactMap { t in t.googleTasksId.map { ($0, t) } })

        var unmatchedGoogle = ctx.google.filter { gTask in
            guard let gid = gTask.googleTasksId else { return false }
            return idStore.remindersId(for: gid) == nil
        }

        for rTask in ctx.reminders {
            guard let rid = rTask.remindersId else { continue }
            // Only repair dead links — a link is dead when its Google task is
            // absent from the fetch. Live links are left untouched.
            if let gid = idStore.googleId(for: rid), googleByGid[gid] != nil { continue }
            guard let matchIdx = unmatchedGoogle.firstIndex(where: {
                $0.title == rTask.title && $0.isCompleted == rTask.isCompleted
            }) else { continue }

            let match = unmatchedGoogle.remove(at: matchIdx)
            guard let newGid = match.googleTasksId else { continue }
            idStore.link(remindersId: rid, googleId: newGid)
            #if DEBUG
            print("SyncEngine: re-linked '\(rTask.title)' to re-created Google task")
            #endif
        }
    }

    // Builds a deletion-free diff: timestamp conflict resolution for linked
    // pairs, additive merge for everything else. Run after repairLinks.
    @MainActor
    private func buildReconciliationDiff(_ ctx: PairContext) -> SyncDiff {
        var diff = SyncDiff()

        let googleByGid = Dictionary(uniqueKeysWithValues:
            ctx.google.compactMap { t in t.googleTasksId.map { ($0, t) } })
        var linkedGids = Set<String>()

        for rTask in ctx.reminders {
            // Same unresolved-move skip as buildDiff. Reconciliation never
            // deletes, so this is not a safety guard here — it just avoids
            // writing content onto a task whose two sides are mid-move and
            // temporarily disagree about which list they live in.
            guard let rid = rTask.remindersId, !unmovedRids.contains(rid) else { continue }
            guard let gid = idStore.googleId(for: rid) else {
                diff.addToGoogle.append(rTask)       // never linked → push to Google
                continue
            }
            linkedGids.insert(gid)
            // Dead link with no re-created match: leave both the task and the
            // link alone. If the other side was deliberately deleted, the
            // normal candidate system propagates it safely over the next
            // cycles — with a fresh baseline behind it.
            guard let gTask = googleByGid[gid], rTask != gTask else { continue }
            if rTask.lastModified >= gTask.lastModified {
                diff.updateInGoogle.append(rTask)
            } else {
                diff.updateInReminders.append(gTask)
            }
        }

        for gTask in ctx.google {
            guard let gid = gTask.googleTasksId,
                  !linkedGids.contains(gid),
                  idStore.remindersId(for: gid) == nil else { continue }
            // Unlinked Google task — mirror to Reminders unless completed
            // (re-creating a finished task would undo the user's action).
            if !gTask.isCompleted { diff.addToReminders.append(gTask) }
        }

        return diff
    }

    // MARK: - Apply Diff

    @MainActor
    private func applyDiff(_ diff: SyncDiff, pair: ListPair) async {
        applyAddsToReminders(diff, pair: pair)
        await applyAddsToGoogle(diff, pair: pair)
        applyUpdatesToGoogle(diff, pair: pair)
        applyUpdatesToReminders(diff)
        applyDeletes(diff, pair: pair)
    }

    @MainActor
    private func applyAddsToReminders(_ diff: SyncDiff, pair: ListPair) {
        for task in diff.addToReminders {
            let remindersId = remindersManager.createTask(
                title:   task.title,
                dueDate: task.dueDate,
                notes:   task.notes,
                url:     task.url,
                listId:  pair.remindersListId
            )
            guard let remindersId, let gid = task.googleTasksId else { continue }
            idStore.link(remindersId: remindersId, googleId: gid)
        }
    }

    @MainActor
    private func applyAddsToGoogle(_ diff: SyncDiff, pair: ListPair) async {
        for task in diff.addToGoogle {
            guard let rid = task.remindersId else { continue }
            await withCheckedContinuation { continuation in
                googleTasksManager.createTask(
                    listId:  pair.googleListId,
                    title:   task.title,
                    notes:   task.notes,
                    dueDate: task.dueDate,
                    url:     task.url
                ) { [weak self] gid in
                    if let gid { self?.idStore.link(remindersId: rid, googleId: gid) }
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func applyUpdatesToGoogle(_ diff: SyncDiff, pair: ListPair) {
        for task in diff.updateInGoogle {
            guard let rid = task.remindersId,
                  let gid = idStore.googleId(for: rid) else { continue }
            googleTasksManager.updateTask(
                listId:      pair.googleListId,
                taskId:      gid,
                title:       task.title,
                notes:       task.notes,
                isCompleted: task.isCompleted,
                dueDate:     task.dueDate
            )
            guard let reminder = remindersManager.fetchTask(by: rid),
                  reminder.isCompleted != task.isCompleted else { continue }
            remindersManager.updateTask(
                reminder,
                title:       task.title,
                notes:       task.notes,
                isCompleted: task.isCompleted,
                dueDate:     task.dueDate
            )
        }
    }

    // Change originated in Google Tasks.
    @MainActor
    private func applyUpdatesToReminders(_ diff: SyncDiff) {
        for gTask in diff.updateInReminders {
            guard let gid = gTask.googleTasksId,
                  let rid = idStore.remindersId(for: gid),
                  let reminder = remindersManager.fetchTask(by: rid) else { continue }
            remindersManager.updateTask(
                reminder,
                title:       gTask.title,
                notes:       gTask.notes,
                isCompleted: gTask.isCompleted,
                dueDate:     gTask.dueDate
            )
        }
    }

    @MainActor
    private func applyDeletes(_ diff: SyncDiff, pair: ListPair) {
        for rid in diff.deleteFromReminders {
            if let reminder = remindersManager.fetchTask(by: rid) {
                remindersManager.deleteTask(reminder)
            }
            idStore.unlink(remindersId: rid)
        }
        for gid in diff.deleteFromGoogle {
            googleTasksManager.deleteTask(listId: pair.googleListId, taskId: gid)
            if let rid = idStore.remindersId(for: gid) {
                idStore.unlink(remindersId: rid)
            }
        }
    }

    // MARK: - Finish Cycle

    @MainActor
    private func finish(fresh: [String: PairBucket], diffs: [String: SyncDiff]) {
        var merged: [TetherTask] = []
        var order:  [String]     = []

        for pair in listPairStore.pairs {
            guard let bucket = fresh[pair.id] else { continue }
            let pairTasks = buildMergedList(remindersTasks: bucket.reminders, googleTasks: bucket.google)
            merged += pairTasks
            order  += orderedRids(pairTasks, google: bucket.google)
            updateCandidates(pair: pair, bucket: bucket, diff: diffs[pair.id] ?? SyncDiff())
        }

        if !order.isEmpty { idStore.setOrder(order) }

        tasks            = sortedByOrder(merged)
        previousSnapshot = tasks
        lastSyncAt       = Date()
        state            = .idle
        failureNotifier.recordSuccess()
        persistBaseline()
        // A fresh baseline now exists — normal diffing (including deletion
        // detection) is safe from the next cycle onwards.
        needsReconciliation = false
        recordTodayStats()
    }

    // Google Tasks returns items in position order when orderBy=position is
    // set, so the fresh Google fetch is the order for this pair. Tasks that
    // exist only in Reminders (not yet linked) go at the end of the pair.
    @MainActor
    private func orderedRids(_ merged: [TetherTask], google: [TetherTask]) -> [String] {
        let googleRids = google.compactMap { gTask -> String? in
            guard let gid = gTask.googleTasksId else { return nil }
            return idStore.remindersId(for: gid)
        }
        let seen = Set(googleRids)
        let remindersOnly = merged.compactMap { $0.remindersId }.filter { !seen.contains($0) }
        return googleRids + remindersOnly
    }

    // A candidate is cleared only when the task RETURNS to the platform it was
    // deleted from — meaning the deletion was a transient failure. We never
    // clear a candidate just because the task is still present on the OTHER
    // platform.
    @MainActor
    private func updateCandidates(pair: ListPair, bucket: PairBucket, diff: SyncDiff) {
        let listState   = syncState(for: pair.id)
        let presentRids = Set(bucket.reminders.compactMap { $0.remindersId })
        let presentGids = Set(bucket.google.compactMap { $0.googleTasksId })

        let returnedToGoogle = listState.remindersDeleteCandidates.filter { rid in
            guard let gid = idStore.googleId(for: rid) else { return false }
            return presentGids.contains(gid)
        }
        listState.remindersDeleteCandidates = listState.remindersDeleteCandidates
            .union(diff.addToRemindersDeleteCandidates)
            .subtracting(returnedToGoogle)

        let returnedToReminders = listState.googleDeleteCandidates.filter { gid in
            guard let rid = idStore.remindersId(for: gid) else { return false }
            return presentRids.contains(rid)
        }
        listState.googleDeleteCandidates = listState.googleDeleteCandidates
            .union(diff.addToGoogleDeleteCandidates)
            .subtracting(returnedToReminders)
    }

    // Clear today's entry when there are no tasks so stale data from a
    // previous session doesn't show a false score.
    @MainActor
    private func recordTodayStats() {
        let todayAll = todayTasks
        statsStore.record(
            total:     todayAll.count,
            completed: todayAll.filter { $0.isCompleted }.count
        )
        if todayAll.isEmpty { statsStore.clearToday() }
    }

    // MARK: - Merge & Sort

    @MainActor
    private func buildMergedList(
        remindersTasks: [TetherTask],
        googleTasks:    [TetherTask]
    ) -> [TetherTask] {
        let googleByGid = Dictionary(uniqueKeysWithValues:
            googleTasks.compactMap { t in t.googleTasksId.map { ($0, t) } })

        var result: [TetherTask] = []
        for var rTask in remindersTasks {
            guard let rid = rTask.remindersId else { continue }
            if let gid = idStore.googleId(for: rid),
               let gTask = googleByGid[gid] {
                rTask.googleTasksId  = gid
                rTask.parentGoogleId = gTask.parentGoogleId
                rTask.url            = rTask.url ?? gTask.url
                rTask.source         = .both
            }
            result.append(rTask)
        }
        return result
    }

    // Identifies a parent task. Google task ids are unique per list, so the
    // pair id has to be part of the key — without it a subtask could latch
    // onto a same-id parent in another list.
    private struct ParentKey: Hashable {
        let googleId: String
        let pairId:   String?
    }

    // A subtask whose parent is not in the list (deleted, in another pair, or
    // filtered out) is promoted to a top-level task rather than dangling —
    // otherwise it renders as an indented child of nothing.
    private func promoteOrphans(_ tasks: [TetherTask]) -> [TetherTask] {
        let parentKeys = Set(tasks.filter { $0.parentGoogleId == nil }.compactMap { task in
            task.googleTasksId.map { ParentKey(googleId: $0, pairId: task.listPairId) }
        })
        return tasks.map { task in
            guard let parentId = task.parentGoogleId,
                  !parentKeys.contains(ParentKey(googleId: parentId, pairId: task.listPairId))
            else { return task }
            var promoted = task
            promoted.parentGoogleId = nil
            return promoted
        }
    }

    private func isChild(_ task: TetherTask, of parent: TetherTask) -> Bool {
        task.parentGoogleId == parent.googleTasksId && task.listPairId == parent.listPairId
    }

    @MainActor
    private func sortedByOrder(_ tasks: [TetherTask]) -> [TetherTask] {
        func pos(_ t: TetherTask) -> Int {
            t.remindersId.map { idStore.position(of: $0) } ?? Int.max
        }

        // Promote first, so every remaining subtask has a real parent here.
        let promoted = promoteOrphans(tasks)
        let parents  = promoted.filter { $0.parentGoogleId == nil }
        let subtasks = promoted.filter { $0.parentGoogleId != nil }

        // Sort parents: incomplete first by position, completed last
        let incompleteParents = parents.filter { !$0.isCompleted }.sorted { pos($0) < pos($1) }
        let completedParents  = parents.filter {  $0.isCompleted }.sorted { pos($0) < pos($1) }

        // Build result: each parent followed immediately by its subtasks
        var result: [TetherTask] = []
        for parent in incompleteParents + completedParents {
            result.append(parent)
            let children = subtasks.filter { isChild($0, of: parent) }
            let incompleteChildren = children.filter { !$0.isCompleted }
            let completedChildren  = children.filter {  $0.isCompleted }
            result.append(contentsOf: incompleteChildren + completedChildren)
        }

        return result
    }

    // MARK: - Order Sync

    // Pushes the current display order of one pair to Google Tasks using the
    // move endpoint. Google Tasks positions tasks by reference to the previous
    // task ID, so we walk the incomplete tasks in order and move each one
    // after the previous.
    @MainActor
    private func pushOrderToGoogle(tasks: [TetherTask], listId: String) async {
        let incomplete = tasks.filter { !$0.isCompleted }
        var previousGoogleId: String? = nil

        for task in incomplete {
            guard let rid = task.remindersId,
                  let gid = idStore.googleId(for: rid) else { continue }
            googleTasksManager.moveTask(listId: listId, taskId: gid, previousTaskId: previousGoogleId)
            previousGoogleId = gid
            // Small delay to avoid rate limiting
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
    }

    // MARK: - Date Helper

    // Forwards to the single source of truth on TetherTask so SyncEngine and
    // the display model can never drift apart on what "today" means.
    private func noonUTC(for date: Date = Date()) -> Date {
        TetherTask.noonUTC(for: date)
    }

    // Schedules a sync at the next local midnight so todayTasks re-evaluates
    // when the calendar day rolls over, without waiting for the next timer tick.
    private func scheduleMidnightRefresh() {
        let cal   = Calendar.current
        guard let tomorrow  = cal.date(byAdding: .day, value: 1, to: Date()),
              let midnight  = cal.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow)
        else { return }
        let delay = midnight.timeIntervalSinceNow
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { await self?.sync() }
            self?.scheduleMidnightRefresh()  // Reschedule for next midnight
        }
    }

    // MARK: - Pair Resolution for UI Actions

    // The pair an inline "add task" targets (D6): whichever pair owns the
    // system default Reminders list, else the first pair.
    @MainActor
    private func defaultPair() -> ListPair? {
        if let listId = remindersManager.defaultListId,
           let match  = listPairStore.pair(forRemindersList: listId) { return match }
        return listPairStore.pairs.first
    }

    // The Google list a already-synced task lives in, resolved via its pair.
    private func googleListId(for task: TetherTask) -> String? {
        guard let pairId = task.listPairId else { return nil }
        return pair(withId: pairId)?.googleListId
    }

    // MARK: - Instant UI Updates

    @MainActor
    func toggleTask(id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].isCompleted.toggle()
        tasks[idx].lastModified = Date()
        let task      = tasks[idx]
        let completed = task.isCompleted
        guard let rid = task.remindersId else { return }

        let completedIds = Set(tasks.filter { $0.isCompleted }.compactMap { $0.remindersId })
        if completed {
            idStore.moveToEnd(remindersId: rid)
        } else {
            idStore.moveBeforeCompleted(remindersId: rid, completedIds: completedIds)
        }

        tasks            = sortedByOrder(tasks)
        previousSnapshot = tasks
        persistBaseline()

        // Update stats immediately so InsightPanel reflects the toggle without
        // waiting for the next sync cycle.
        recordTodayStats()

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let reminder = remindersManager.fetchTask(by: rid) {
                remindersManager.updateTask(
                    reminder,
                    title:       task.title,
                    notes:       task.notes,
                    isCompleted: completed,
                    dueDate:     task.dueDate
                )
            }
            guard let listId = googleListId(for: task),
                  let gid    = idStore.googleId(for: rid) else { return }
            googleTasksManager.updateTask(
                listId:      listId,
                taskId:      gid,
                title:       task.title,
                notes:       task.notes,
                isCompleted: completed,
                dueDate:     task.dueDate
            )
        }
    }

    @MainActor
    func addTask(title: String) {
        guard let pair = defaultPair() else {
            #if DEBUG
            print("SyncEngine: addTask ignored — no synced list pairs yet")
            #endif
            return
        }

        let dueDate = noonUTC()
        let tempId  = UUID().uuidString

        let task = TetherTask(
            id:            tempId,
            remindersId:   nil,
            googleTasksId: nil,
            listPairId:    pair.id,
            title:         title,
            notes:         nil,
            isCompleted:   false,
            dueDate:       dueDate,
            url:           nil,
            lastModified:  Date(),
            source:        .both
        )
        tasks.insert(task, at: 0)
        previousSnapshot = tasks
        persistBaseline()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await createTaskOnBothSides(title: title, dueDate: dueDate, tempId: tempId, pair: pair)
        }
    }

    @MainActor
    private func createTaskOnBothSides(
        title:   String,
        dueDate: Date,
        tempId:  String,
        pair:    ListPair
    ) async {
        guard let remindersId = remindersManager.createTask(
            title: title, dueDate: dueDate, notes: nil, url: nil, listId: pair.remindersListId
        ) else { return }

        if let idx = tasks.firstIndex(where: { $0.id == tempId }) {
            tasks[idx].remindersId = remindersId
        }
        idStore.insertAtTop(remindersId: remindersId, completedIds: [])

        await withCheckedContinuation { continuation in
            googleTasksManager.createTask(
                listId: pair.googleListId, title: title, notes: nil, dueDate: dueDate, url: nil
            ) { [weak self] gid in
                guard let self, let gid else { continuation.resume(); return }
                idStore.link(remindersId: remindersId, googleId: gid)
                if let idx = tasks.firstIndex(where: { $0.id == tempId }) {
                    tasks[idx].googleTasksId = gid
                }
                continuation.resume()
            }
        }

        previousSnapshot = tasks
        persistBaseline()
    }

    @MainActor
    func deleteTask(id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let task = tasks.remove(at: idx)
        previousSnapshot = tasks
        persistBaseline()
        recordTodayStats()

        Task { @MainActor [weak self] in
            guard let self, let rid = task.remindersId else { return }
            if let reminder = remindersManager.fetchTask(by: rid) {
                remindersManager.deleteTask(reminder)
            }
            if let listId = googleListId(for: task), let gid = idStore.googleId(for: rid) {
                googleTasksManager.deleteTask(listId: listId, taskId: gid)
            }
            idStore.unlink(remindersId: rid)
        }
    }

    // MARK: - Today Filter

    var todayTasks: [TetherTask] {
        let todayNoon = noonUTC()
        let tomorrow  = todayNoon + 86400
        return tasks.filter { task in
            guard let due = task.dueDate else { return false }
            // Only show tasks due today — completed or incomplete.
            // Overdue incomplete tasks are excluded (they are in the past).
            return due >= todayNoon && due < tomorrow
        }
    }

    // Incomplete tasks whose due date is before today's noon-UTC boundary.
    // Completed tasks are never overdue regardless of their original due
    // date. `tasks` is already kept sorted (sortedByOrder runs after every
    // mutation), so filtering it preserves that order without re-sorting —
    // same pattern as todayTasks above. Intentionally excluded from stats:
    // only todayTasks feeds StatsStore, so surfacing these here does not
    // affect the productivity score.
    var overdueTasks: [TetherTask] {
        tasks.filter { $0.isOverdue }
    }

    // MARK: - Last Sync Text

    var lastSyncText: String {
        guard let date = lastSyncAt else {
            return String(localized: "sync.last.never")
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
