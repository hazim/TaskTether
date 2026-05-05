# Changelog

All notable changes to TaskTether are documented here.

---

## [1.0.3] — 2026-05-05

### Fixed
- **Clearing notes in Reminders now propagates to Google Tasks** — removing notes from a task in Reminders was not clearing them in Google Tasks. The sync engine omitted the `notes` field from the PATCH request when nil, so Google kept the old value and wrote it back on the next sync. Now explicitly sends `null` to clear the field, matching the existing behaviour for due dates.
- **OAuth retry no longer silently fails after closing the browser** — if the browser was closed without completing the Google sign-in flow, port 8080 remained locked. A second attempt to connect would fail silently because the new listener could not bind to the already-open port. `LocalHTTPServer.stop()` is now called at the start of each sign-in attempt to tear down any stale listener first.
- **Sync error state now shown in red** — the last-sync timestamp in the status strip was always displayed in green regardless of sync state. It now switches to red when the sync engine is in an error state, giving a clear visual signal that something has gone wrong.

### Changed
- **Simplified navigation — two modes instead of three** — the Today panel is now always visible when in Expanded mode, eliminating the separate Today nav option. The app now has two distinct states: Expanded (task list + productivity stats, 600px) and Compact (sync status only, 300px). Expanded is the default on first launch.

### Added
- **Ko-fi button in Settings** — the Support section now shows the official Ko-fi branded button instead of a plain icon, linking to [ko-fi.com/hazims](https://ko-fi.com/hazims).

---

## [1.0.2] — 2026-04-04

### Fixed
- **Keychain inconsistency between Debug and Release builds** — tokens were stored without a `kSecAttrService` key, causing macOS to scope them to the signing identity. Switching between Debug and Release binaries made previously stored tokens unreadable, forcing reconnection after every rebuild. All Keychain operations now include a stable service identifier (`com.hazim.TaskTether`) so tokens persist correctly across all build types.
- **Automatic migration of existing tokens** — on first launch after this update, any tokens stored in the old format are automatically migrated. No manual reconnection required.
- **Sign out did not show Connect screen** — clicking Sign Out in Settings cleared the token but left the Settings window open with no visual confirmation. Sign out now closes the Settings window immediately so the Connect screen appears automatically.

---

## [1.0.1] — 2026-04-02

### Fixed
- **Google Tasks fetch capped at 20 items** — the Google Tasks API defaults to returning a maximum of 20 tasks per request. TaskTether was not setting `maxResults` or handling pagination via `nextPageToken`, so any tasks beyond the first 20 were completely invisible to the sync engine. This caused tasks to appear absent from Google when they were not, triggering false deletions from Reminders, and prevented future-dated and undated tasks from ever syncing across. Both fetch passes are now fully paginated with `maxResults=100` per page, supporting up to hundreds of tasks correctly.
- **Date boundary bug** — tasks created or updated after local midnight (e.g. Budapest at 00:18) were written to Reminders using a UTC calendar, causing them to be stored with the previous day's date. They would then disappear from the Today view on the next sync and cause the productivity score to show a false 100%. Due dates are now extracted using the local calendar before being stored, so the correct calendar day is always written regardless of timezone.
- **Due date removal not propagating to Google Tasks** — removing a due date from a task in Reminders was not clearing it in Google Tasks. The sync engine omitted the `due` field from the PATCH request when the date was nil, so Google kept the old value and it bounced back on the next sync. Now explicitly sends `null` to clear the field server-side.

### Added
- **Dock visibility setting** — Settings → Dock → Show icon in Dock. Off by default. Takes effect after restarting TaskTether.

### Docs
- Replaced the manual credentials walkthrough in README with a link to Google's official OAuth credentials guide.

### Notes
- Task display order in TaskTether and the dashboard reflects the Google Tasks API position order (`orderBy=position`). This does not match any of the sort options available in the Google Tasks UI — this is a deliberate limitation of the Google Tasks API, which does not expose the "My order" UI sort through its API.

---

## [1.0.0] — 2026-03-28 — Initial public release

### Core sync
- Two-way sync between Apple Reminders and Google Tasks
- Automatic sync on a configurable interval (5, 10, 15, 30, 60 minutes)
- Manual sync via Sync Now button
- Conflict resolution — most recently modified version wins
- Deletion sync in both directions
- Completion sync — marking done on either platform propagates to the other
- Subtask support — Google Tasks subtasks appear grouped under their parent in the UI
- Two-pass fetch to correctly detect deletions of completed tasks

### UI
- macOS menu bar app — three views: Compact, Expanded, Today
- Today view — see, complete, and add tasks without leaving the menu bar
- Compact view — live service status dots, last sync time, Sync Now button
- Expanded view — today productivity score, yesterday comparison, delta indicator, 7-day bar chart
- Inline task creation with due date set to today
- Subtask visual grouping with indent indicator

### Theming
- Seven built-in themes: Sand, Glacier, Titan (light) · Midnight, Dusk, Prolis, Ember (dark)
- Light and dark theme slots — assign a theme to each independently
- Appearance override: System / Always Light / Always Dark
- Custom theme support — load any community JSON theme from Settings
- Custom themes persist across app restarts

### Localisation
- English, Magyar (Hungarian), العربية (Arabic)
- Full localisation of all UI strings, error messages, and the macOS Reminders permission prompt
- Day labels in bar chart auto-localise via DateFormatter
- Contributor guide: LOCALISING.md

### Settings
- Sync interval picker
- Theme slot pickers with colour swatches
- Appearance override
- Language picker (takes effect after restart)
- Custom theme loader
- Google account sign-out

### Technical
- Google OAuth 2.0 via localhost redirect — no third-party server involved
- Tokens stored in macOS Keychain
- Token refresh on launch — no mid-session sign-out
- Apple EventKit for Reminders read/write
- Google Tasks REST API
- StatsStore — daily productivity tracking persisted in UserDefaults
- IDStore — bidirectional ID mapping between Reminders and Google Tasks
- SyncEngine two-cycle deletion guard to prevent false deletions on first sync
- #if DEBUG guards on all print statements — release builds are silent
- macOS 12 (Monterey) and later
