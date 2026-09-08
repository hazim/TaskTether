# Multi-list sync — design spec

Status: implemented 2026-09-04 (v1.2.0, build 8). Owner: orchestrator session. Target version 1.2.0 (build 8).

## Goal

Sync **every** Apple Reminders list with a Google Tasks list of the same name, in both
directions. A list created on one side is created on the other side. Renames propagate.
Tasks moved between lists on one side move on the other side. Today's single hardcoded
"TaskTether" list becomes just one pair among many.

## Decisions (do not re-litigate inside agent briefs)

| # | Decision | Why |
|---|----------|-----|
| D1 | Lists are paired by **stored IDs** (`ListPair`), persisted in UserDefaults. First pairing of two unpaired lists is by **title** (trimmed, case-insensitive). | Title matching only at pairing time makes renames safe. |
| D2 | **List deletion is never mirrored.** If one side of a pair disappears, the pair is *retired*: the survivor keeps its tasks and stops syncing. A retired survivor never triggers creation of a counterpart. If the missing side reappears by id, or an unpaired same-title list appears on the other side, the pair is revived / re-paired. | Deleting a whole list's tasks on the other side because EventKit or Google returned nothing once is unacceptable blast radius. |
| D3 | **Rename** detection uses the pair's last-synced `title`: the side whose title differs from it changed and wins. If both differ, Reminders wins. | Same three-way principle the task diff already uses. |
| D4 | **Task moves** between lists: for every linked (rid, gid) where the Reminders list's pair ≠ the Google list's pair, the side that still matches the previous snapshot's `listPairId` did *not* move, so the other side moved and is mirrored (Google `tasks.move?destinationTasklist=`, EventKit `reminder.calendar = …`). Unknown previous → Reminders wins. Moves run before per-pair diffs so a move is never mis-read as delete+create. | Without this a move would be seen as a deletion on one pair and a stray link on the other → data loss. |
| D5 | Reminders lists that are read-only (`allowsContentModifications == false`) or of type `.subscription` / `.birthday` are ignored. Every other Reminders list and every Google task list (including "My Tasks") participates. | User asked for all lists. |
| D6 | Inline "add task" from the panel targets the pair whose Reminders list is `EKEventStore.defaultCalendarForNewReminders()`; fallback: the first pair. | No UI for list choice this round. |
| D7 | IDStore refs stay **global** (Reminders `calendarItemIdentifier` and Google task ids are globally unique). Order is global, built by concatenating each pair's Google order in pair order. Snapshot rows and `TetherTask` gain `listPairId`. Suspicious-zero counters and delete-candidate sets become **per pair**. | Minimal change to the proven diff engine; per-pair guards because empty lists are now normal. |
| D8 | Migration: an old snapshot (rows without `listPairId`) forces one reconciliation sync (never deletes, repairs links by title). The old "TaskTether" lists pair by title automatically. | Reuses the existing safe path. |
| D9 | `todayTasks`/`overdueTasks`/stats stay cross-list. UI unchanged apart from strings. | Out of scope; noted as follow-up. |
| D10 | Managers no longer create or look up any list on setup. `GoogleTasksManager.setup()` proves connectivity by listing task lists. `RemindersManager.requestAccess()` no longer creates "TaskTether". | The engine owns list lifecycle. |
| D11 | **Parked links.** A linked (rid, gid) where either side sits outside the active pairs (retired survivor, ineligible list) is excluded from deletion and moves on both pairs. Retired pairs' Google lists are fetched tolerantly just to detect this. | Review 2026-09-04: moving a linked reminder into a retired list deleted its Google task two cycles later. |
| D12 | **A failed fetch aborts the cycle.** Google transport/HTTP/parse/auth failures and EventKit nil results throw; nothing in diff/apply runs that cycle. Only retired-pair fetches are tolerant. | Pre-existing: failures collapsed to `[]`, so three offline cycles deleted tasks. |

## New shared models — `TaskTether/TaskTether/ListModels.swift` (owner: agent A, written first)

```swift
import Foundation

/// A Reminders list (EKCalendar for .reminder) as seen by the sync engine.
struct ReminderList: Equatable, Hashable {
    let id: String        // EKCalendar.calendarIdentifier
    let title: String
}

/// A Google Tasks task list.
struct GoogleTaskList: Equatable, Hashable {
    let id: String
    let title: String
}

/// A synced pair of lists. `title` is the title as of the last successful sync (rename baseline).
struct ListPair: Codable, Equatable, Identifiable {
    let id: String              // UUID string, stable for the life of the pair
    var remindersListId: String
    var googleListId: String
    var title: String
}
```

## Agent A — `ListModels.swift`, `ListPairStore.swift`, `ListReconciler.swift` (new files)

`ListPairStore` (UserDefaults keys `tasktether_list_pairs`, `tasktether_list_pairs_retired`, JSON-encoded `[ListPair]`):

```swift
final class ListPairStore {
    private(set) var pairs: [ListPair]
    private(set) var retired: [ListPair]
    func add(_ pair: ListPair)
    func update(_ pair: ListPair)               // by id
    func retire(id: String)                     // move pairs → retired
    func revive(id: String)                     // move retired → pairs
    func remove(id: String)                     // from either
    func pair(forRemindersList id: String) -> ListPair?
    func pair(forGoogleList id: String) -> ListPair?
    func clear()
}
```

`ListReconciler` is **pure** (no EventKit, no networking), so it can be tested with a
standalone `swift` script:

```swift
struct ListReconcilePlan: Equatable {
    var revive: [ListPair] = []                 // retired pair whose missing side is back by id
    var retire: [ListPair] = []                 // active pair with one side missing
    var renameGoogle: [(pair: ListPair, title: String)] = []      // apply title to Google
    var renameReminders: [(pair: ListPair, title: String)] = []   // apply title to Reminders
    var pairByTitle: [(reminders: ReminderList, google: GoogleTaskList)] = []
    var createGoogle: [ReminderList] = []       // unpaired Reminders list → create Google list
    var createReminders: [GoogleTaskList] = []  // unpaired Google list → create Reminders list
}
enum ListReconciler {
    static func plan(pairs: [ListPair], retired: [ListPair],
                     reminders: [ReminderList], google: [GoogleTaskList]) -> ListReconcilePlan
}
```
(Use small structs instead of tuples if `Equatable` synthesis needs it.)

Rules, in order:
1. For each **retired** pair: if both sides now exist by id → `revive`. If exactly one side exists, keep retired and mark that surviving list as *consumed* (it must not appear in `createGoogle` / `createReminders`, but it MAY be title-matched in step 4, in which case the retired pair is removed by the executor and a new pair is created).
2. For each **active** pair: both sides present → rename check (D3): Reminders title ≠ pair.title and Google title == pair.title → `renameGoogle`; Google ≠ and Reminders == → `renameReminders`; both ≠ → `renameGoogle` (Reminders wins). Exactly one side missing → `retire`. Both missing → `retire` too (executor keeps it retired; harmless).
3. Collect unpaired lists on each side (not in any active pair, not consumed by rule 1 unless title-matched below).
4. Title-match unpaired Reminders × unpaired Google (trimmed, case-insensitive, each list used at most once, stable order = sorted by title then id) → `pairByTitle`.
5. Leftover unpaired Reminders → `createGoogle`; leftover unpaired Google → `createReminders`. Exclude consumed retired survivors here.

Proof artefact: a standalone script `scratch/list-reconciler-test.swift` (copy the reconciler + models into it, since the project uses MainActor default isolation) asserting at least: fresh start with TaskTether on both sides pairs by title; new Reminders list → createGoogle; new Google list → createReminders; rename on Reminders side → renameGoogle; rename both → renameGoogle; Reminders side deleted → retire and survivor NOT in createReminders; deleted side reappears by id → revive; retired survivor + new same-title list on other side → pairByTitle. Run with `swift scratch/list-reconciler-test.swift` and paste the output.

## Agent B — `GoogleTasksManager.swift`

Remove `listName`, `taskListId`, `findOrCreateTaskTetherList`, `createTaskTetherList`. `setup()` keeps the token check and sets `isConnected` from a successful `fetchTaskLists`.

Add/replace public API (keep each existing method's completion / async style; `listId` becomes the first parameter):

```swift
func fetchTaskLists(completion: @escaping (Result<[GoogleTaskList], Error>) -> Void)   // GET /users/@me/lists, paginated via fetchAllPages, maxResults=100
func createTaskList(title: String, completion: @escaping (Result<GoogleTaskList, Error>) -> Void)   // POST /users/@me/lists {"title"}
func renameTaskList(id: String, title: String, completion: @escaping (Result<Void, Error>) -> Void) // PATCH /users/@me/lists/{id} {"title"}
func fetchTasks(listId: String, completion: …)      // GoogleTask.listId is set on every result
func createTask(listId: String, title:notes:dueDate:url:completion:)
func completeTask(listId: String, taskId: String …)
func updateTask(listId: String, taskId: String, title:notes:isCompleted:dueDate: …)
func moveTask(listId: String, taskId: String, previousTaskId: …)   // existing in-list reorder
func moveTaskToList(taskId: String, from: String, to: String, completion: @escaping (Result<GoogleTask, Error>) -> Void)
    // POST /lists/{from}/tasks/{taskId}/move?destinationTasklist={to}
func deleteTask(listId: String, taskId: String …)
```
`GoogleTask` gains `let listId: String`. Existing 401/refresh handling and `tasksURL` stay. Base URL `https://tasks.googleapis.com/tasks/v1`. Do not touch any other file; SyncEngine call sites are agent D's job, so expect SyncEngine compile errors until D lands.

## Agent C — `RemindersManager.swift`

Remove `listName` and `createTaskTetherListIfNeeded` (and its call in `requestAccess`). Add/replace:

```swift
var defaultListId: String?                       // store.defaultCalendarForNewReminders()?.calendarIdentifier
func fetchLists() -> [ReminderList]              // calendars(for: .reminder) filtered per D5, sorted by title
func createList(title: String) -> String?        // source = defaultCalendarForNewReminders()?.source ?? first source whose reminder calendars are non-empty; saveCalendar(commit: true); returns calendarIdentifier; sets errorMessage on failure
func renameList(id: String, title: String) -> Bool
func fetchTasks() -> [EKReminder]                // ALL reminder calendars: predicateForReminders(in: nil) + predicateForCompletedReminders(…, calendars: nil); same dedupe; caller reads reminder.calendar.calendarIdentifier
func fetchTask(by id: String) -> EKReminder?     // may use store.calendarItem(withIdentifier:) as? EKReminder
func createTask(title: String, dueDate: Date?, notes: String?, url: URL?, listId: String) -> String?   // reminder.calendar = store.calendar(withIdentifier: listId); return nil + errorMessage if missing
func moveTask(_ reminder: EKReminder, toListId: String) -> Bool   // set .calendar, save(commit: true)
```
Existing `updateTask`, `completeTask`, `deleteTask`, date helpers unchanged. Only this file.

## Agent D — `SyncEngine.swift`, `TetherTask.swift`, `SnapshotStore.swift`, `IDStore.swift` (+ `ListSyncState` may live in SyncEngine)

Builds against the signatures above (A, B, C run concurrently; retry the build after 60 s up to 3× if the only errors are in files you do not own, then report blocked — never work around).

1. `TetherTask` gains `var listPairId: String?`. `SnapshotTask` gains `listPairId: String?`; `SnapshotStore.load()` returns `nil` (→ reconciliation, D8) if any row lacks it.
2. `SyncEngine` owns a `ListPairStore` and, per pair id, a `ListSyncState { consecutiveGoogleZero, consecutiveRemindersZero, remindersDeleteCandidates, googleDeleteCandidates }` (move the existing globals in).
3. `sync()` becomes:
   1. `reconcileLists()`: `remindersManager.fetchLists()` + `googleTasksManager.fetchTaskLists()` → `ListReconciler.plan` → execute: revive/retire/remove in store; renames via managers, then `pair.title` updated; `pairByTitle` → new `ListPair(id: UUID().uuidString, …, title: reminders.title)`; `createGoogle` → `createTaskList(title:)` then pair; `createReminders` → `createList(title:)` then pair. A failed create/rename logs and skips that list; it does not abort the sync.
   2. Fetch: all reminders once, grouped by `reminder.calendar.calendarIdentifier` → pair; Google tasks per active pair (concurrently is fine). Reminders in lists with no active pair are ignored. Every `TetherTask` gets `listPairId`.
   3. Move pass (D4). Execute moves, then update the in-memory attribution (no refetch needed).
   4. Per active pair: existing `repairLinks` + `buildReconciliationDiff` when `needsReconciliation`, else `buildDiff(remindersTasks:googleTasks:previous:)` with `previous` filtered to that pair. Suspicious guards read/write that pair's `ListSyncState`. `applyDiff(diff, pair)` passes `pair.remindersListId` / `pair.googleListId` to the managers.
   5. Refetch, `buildMergedList` per pair, order = concatenation of per-pair Google order in `store.pairs` order, `tasks` = concatenation, snapshot with `listPairId`, stats unchanged.
4. `addTask(title:)` picks the pair per D6 (no-op with a DEBUG print if there are no pairs). `toggleTask` / `deleteTask` resolve `pair.googleListId` from the task's `listPairId`.
5. Remove every remaining reference to a single list. `grep -n "taskListId\|listName\|TaskTether list" TaskTether/TaskTether/*.swift` must return nothing outside Localizable strings.

Proof artefacts: (a) `scratch/move-detection-test.swift` — standalone copy of the move-decision function with cases: Reminders moved, Google moved, both unchanged, unknown previous; (b) Debug and Release builds green once B and C have landed; (c) the grep above.

## Agent E — strings, docs, version (after D)

- `Localizable.xcstrings`: `today.empty.subtitle` → en "Nothing due today." (hu/ar: leave a matching English string and mark `"state": "needs_review"`); `error.reminders.createlist` → "Could not create Reminders list: %@"; `error.tasks.createlist` → "Could not create Google Tasks list". Validate JSON.
- `Info.plist` `NSRemindersUsageDescription` → "TaskTether needs access to Reminders to sync your lists with Google Tasks."
- README: replace the "TaskTether list" description with all-lists behaviour, pairing by name, creation on either side, no list deletion mirroring, how to stop a list syncing (delete one side; the other keeps its tasks).
- CHANGELOG `[1.2.0]` entry; `MARKETING_VERSION = 1.2.0`, `CURRENT_PROJECT_VERSION = 8` in both configs.

## Verification set (orchestrator, every phase)

1. `xcodebuild … -configuration Debug … build CODE_SIGNING_ALLOWED=NO` and Release, both green.
2. Read personally: the retire/no-delete path, the move-decision function, the per-pair suspicious guard — these carry the data-loss invariant.
3. Run both standalone scripts.
4. `scripts/build-release.sh --credentials TaskTether/TaskTether/GoogleCredentials.json` → DMG for the user's manual test on the real accounts.

## Follow-ups (not this round)

- Show the list name on task rows / group Today by list.
- Per-list statistics.
- Settings toggle to exclude specific lists from sync.
- `NSRemindersFullAccessUsageDescription` key for macOS 14+ (currently only the legacy key is present).
