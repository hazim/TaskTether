# Changelog

All notable changes to TaskTether are documented here.

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
