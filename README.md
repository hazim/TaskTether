# TaskTether

> Two-way sync between Apple Reminders and Google Tasks. Runs silently on macOS.

TaskTether keeps your Apple Reminders and Google Tasks in sync automatically. Add a task in Reminders, and it appears in Google Tasks. Complete it in Google Tasks, and it updates in Reminders. No subscriptions, no cloud dependencies, no browser tabs — just a lightweight background service running quietly on your Mac.

---

## Why TaskTether?

Most sync solutions either require a cloud middleman, charge a subscription, or only support recent versions of macOS. TaskTether is built to run entirely on your machine — including older Macs running macOS 12 (Monterey) and later.

---

## Features

- **Two-way sync** — changes in either app reflect in the other
- **Conflict resolution** — most recently modified version wins
- **Menu bar app** — one click to open, always available
- **Today view** — see, complete, and manage today's tasks without leaving the menu bar
- **Productivity tracking** — daily score, yesterday's comparison, 7-day sparkline
- **Theming** — four built-in themes (Sand, Midnight, Dusk, Prolis) with custom JSON theme support
- **Private** — your tasks never touch a third-party server
- **macOS 12+** — supports Monterey and later, including older hardware

---

## How It Works

```
Apple Reminders  ◄──────────────►  Google Tasks
      │                                  │
      └──────────  TaskTether  ──────────┘
                 (runs locally)
```

TaskTether runs as a menu bar app on your Mac. On a configurable interval it compares your Reminders and Google Tasks lists, detects differences, and syncs changes in both directions using Apple's native EventKit framework and the Google Tasks API.

---

## Requirements

- macOS 12 (Monterey) or later
- macOS 26 (Tahoe) recommended for Liquid Glass effects
- A Google account with Google Tasks
- Xcode 16+ (for building from source)

---

## Installation

> ⚠️ TaskTether is currently in active development. Installation instructions will be added when the first release is ready.

---

## Build Status

| Group | Status |
|---|---|
| 0 — Foundation | ✅ Complete |
| 1 — Static UI Shell | ✅ Complete |
| 2 — Settings Panel | 🔜 Next |
| 3 — Sync Engine | ⬜ Planned |
| 4 — Live Data | ⬜ Planned |
| 5 — Polish & Distribution | ⬜ Planned |

---

## Roadmap

- [x] Menu bar app shell
- [x] Compact / Expanded / Today panel views
- [x] 7-day productivity sparkline
- [x] Task list with subtasks, completion, hover actions
- [x] Theme system (4 built-in themes + custom JSON)
- [ ] Settings panel — theme picker, sync interval, sign out
- [ ] Core two-way sync engine
- [ ] Conflict resolution (last-modified wins)
- [ ] Live Reminders + Google Tasks data
- [ ] Drag-to-reorder tasks
- [ ] First public release

---

## Contributing

TaskTether is open source, and contributions are welcome. If you find a bug or have a feature request, please open an issue.

---

## Licence

MIT — free to use, modify, and distribute. See [LICENSE](LICENSE) for details.

---

## Acknowledgements

Built to solve a real problem — reliable, private, local task sync for macOS users who use both Apple and Google ecosystems, without subscriptions or cloud dependencies.
