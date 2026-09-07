# TaskTether

A free, open source macOS menu bar app that keeps Apple Reminders and Google Tasks in sync — automatically, in the background, without lifting a finger.

![TaskTether](docs/screenshot.png)

---

## Why TaskTether?

Most sync solutions either require a cloud middleman, charge a subscription, or only support recent versions of macOS. TaskTether runs entirely on your machine — including older Macs on macOS 12 (Monterey) and later. Your tasks never touch a third-party server.

---

## How it works

```
Apple Reminders  ◄──────────────►  Google Tasks
      │                                  │
      └──────────  TaskTether  ──────────┘
                 (runs locally)
```

TaskTether runs as a menu bar app on your Mac. On a configurable interval it compares your Reminders and Google Tasks lists, detects differences, and syncs changes in both directions using Apple's native EventKit framework and the Google Tasks API.

Every editable Reminders list is synced with a Google Tasks list of the same name — this includes the default "Reminders" list and Google's "My Tasks". A list created on either side is created on the other side automatically, and renaming a list on one side renames its counterpart. Moving a task from one list to another follows the same rule: the move happens on the other side too.

Lists are paired by name the first time they're seen; after that, the pairing tracks the list itself, so renaming it doesn't break the sync. Deleting a list is never mirrored — if you delete a list on one side, its counterpart on the other side simply stops syncing and keeps its tasks. If you want to stop a list from syncing entirely, delete it on one side; if you also want the tasks gone, delete the other side's list yourself.

---

## Features

- **Multi-list sync** — every Reminders list syncs with a Google Tasks list of the same name; lists created, renamed, or moved between on either side follow on the other
- **Two-way sync** — changes on either side propagate automatically
- **Conflict resolution** — most recently modified version wins
- **Subtask support** — subtasks from Google Tasks appear grouped under their parent
- **Completion sync** — marking a task done on either platform syncs the completion
- **Deletion sync** — deleting a task on either platform removes it from both
- **Expanded mode** — task list, productivity stats, and sync status in one full view
- **Compact mode** — minimal sync status at a glance, 300px footprint
- **Productivity stats** — daily score, yesterday's comparison, 7-day bar chart
- **Theming** — seven built-in themes (Sand, Glacier, Titan, Midnight, Dusk, Prolis, Ember) plus custom JSON theme support
- **Localisation** — English, Magyar, and العربية included; easy to add more
- **Private** — your tasks never touch a third-party server
- **macOS 12+** — supports Monterey and later, including older hardware

---

## Requirements

- macOS 12 (Monterey) or later
- A Google account with Google Tasks enabled
- Apple Reminders enabled

---

## Installation

**Pre-built binary** (from a teammate or GitHub Releases) — the easiest route is the `.pkg`: right-click it, choose **Open**, and click through the installer. TaskTether launches by itself when the installer finishes and appears in the menu bar. If you were given a `.dmg` instead: open the `.dmg`, drag `TaskTether.app` onto the `Applications` shortcut, then eject the disk image. On first launch, right-click (or Control-click) `TaskTether.app` in `/Applications` and choose **Open**. The app isn't notarised, so Gatekeeper will otherwise refuse to launch it; right-click → Open (or **System Settings → Privacy & Security → Open Anyway**) is a one-time step. If you were given a `.zip` instead, unzip it and drag `TaskTether.app` to `/Applications` before following the same first-launch step.

**Building from source** — see [Building from source](#building-from-source) below.

---

## Setup

Before TaskTether can talk to Google Tasks, you need to give it permission through Google's own system. This is a one-time setup that takes about 5 minutes. You are creating your own private connection to Google — your data never goes through any third-party server.

### Step 1 — Enable the Google Tasks API

1. Go to [console.cloud.google.com](https://console.cloud.google.com/) and sign in
2. Click **Select a project** at the top → **New Project** → name it anything (e.g. "TaskTether") → **Create**
3. With your project selected, go to **APIs & Services → Library**
4. Search for **Google Tasks API** and click **Enable**

### Step 2 — Create credentials

Follow Google's official guide to create an OAuth 2.0 Client ID:
[developers.google.com/workspace/guides/create-credentials](https://developers.google.com/workspace/guides/create-credentials)

When prompted for application type, choose **Desktop app** and name it `TaskTether`. Once created, download the JSON file and rename it to exactly `GoogleCredentials.json`.

### Step 3 — Add the credentials file to the app

1. Right-click `TaskTether.app` in your Applications folder → **Show Package Contents**
2. Open `Contents → Resources`
3. Copy `GoogleCredentials.json` into that folder

> No redirect URI registration needed — TaskTether is a Desktop app OAuth client, so Google accepts any loopback address. TaskTether picks a free `localhost` port automatically each time it signs in.

### Step 4 — Connect your account

1. Open TaskTether from the menu bar
2. Click **Connect Google Account**
3. Your browser opens — sign in and click Allow
4. TaskTether is now connected and will start syncing

### Step 5 — Grant Reminders access

The first time TaskTether accesses Reminders, macOS will ask for permission. Click **Allow**.

If you accidentally denied it: **System Settings → Privacy & Security → Reminders** → enable TaskTether.

---

## Building from source

```bash
git clone https://github.com/hazim/TaskTether.git
cd TaskTether
```

1. Add your `GoogleCredentials.json` to `TaskTether/TaskTether/` inside the Xcode project
2. Open `TaskTether/TaskTether.xcodeproj` in Xcode
3. Select your Mac as the run destination
4. Press **Cmd+R** to build and run

Requires Xcode 15 or later.

### Building a distributable .zip

`scripts/build-release.sh` builds, signs, and packages the app for sharing:

```bash
scripts/build-release.sh --team <TEAMID> --credentials /path/to/GoogleCredentials.json
```

The signed app lands in `dist/TaskTether-<version>.pkg` (an installer that launches the app once it is installed — recommended), `dist/TaskTether-<version>.dmg` (a classic drag-to-Applications disk image) and `dist/TaskTether-<version>.zip`. The app, zip and dmg are signed with an Apple Development certificate; the pkg is unsigned (that would need a separate Developer ID Installer certificate). Nothing is notarised — recipients still need the right-click → Open step above, on the pkg or on the app.

- `--team <TEAMID>` selects the signing certificate: the ID shown in parentheses by `security find-identity -v -p codesigning`. Required unless `--adhoc` is passed; `DEVELOPMENT_TEAM` in the environment works too.
- `--credentials <path>` bakes `GoogleCredentials.json` into the app bundle before signing, so the recipient can skip the Google Cloud setup entirely. This is the recommended way to share a build with a teammate. Everyone using that build shares one OAuth client, which is fine for a small team — each person still signs in with their own Google account.
- `--adhoc` signs ad-hoc instead, for building on a machine without the team's signing certificate.
- `--no-dmg` skips building the `.dmg`.
- `--no-pkg` skips building the `.pkg`.

---

## Contributing

Pull requests are welcome. Please open an issue first for significant changes so we can discuss the approach.

### Adding a translation

See [LOCALISING.md](LOCALISING.md) for instructions on adding a new language. All strings are in `TaskTether/TaskTether/Localizable.xcstrings`.

### Custom themes

Themes are JSON files. See `Themes.json` for the format. Load a custom theme from **Settings → Custom Themes → Load theme from file**.

---

## Privacy

TaskTether runs entirely on your device. No data is sent to any server other than the Google Tasks API using your own credentials. No analytics, no telemetry, no ads.

---

## Roadmap & Changelog

See [ROADMAP.md](ROADMAP.md) for what's coming next and [CHANGELOG.md](CHANGELOG.md) for what's in each release.

---

## Licence

MIT — see [LICENSE](LICENSE)

---

## Support

TaskTether is free and open source. If it saves you time, consider buying me a coffee.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/hazims)
