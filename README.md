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

---

## Features

- **Two-way sync** — changes on either side propagate automatically
- **Conflict resolution** — most recently modified version wins
- **Subtask support** — subtasks from Google Tasks appear grouped under their parent
- **Completion sync** — marking a task done on either platform syncs the completion
- **Deletion sync** — deleting a task on either platform removes it from both
- **Today view** — see, complete, and add tasks without leaving the menu bar
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

TaskTether is currently available as source only. See [Building from source](#building-from-source) below.

---

## Setup

Before TaskTether can talk to Google Tasks, you need to give it permission through Google's own system. This is a one-time setup that takes about 5 minutes. You are creating your own private connection to Google — your data never goes through any third-party server.

### Step 1 — Enable the Google Tasks API

1. Go to [console.cloud.google.com](https://console.cloud.google.com/) and sign in
2. Click **Select a project** at the top → **New Project** → name it anything (e.g. "TaskTether") → **Create**
3. With your project selected, go to **APIs & Services → Library**
4. Search for **Google Tasks API** and click **Enable**

### Step 2 — Create credentials

1. Go to **APIs & Services → Credentials**
2. Click **+ Create Credentials → OAuth 2.0 Client ID**
3. If prompted to configure a consent screen first:
   - Choose **External** → **Create**
   - Fill in App name: `TaskTether`, your email for support and developer contact
   - Skip the scopes page → **Save and Continue** through to the end
   - Go back to **Credentials** and click **+ Create Credentials → OAuth 2.0 Client ID**
4. Set **Application type** to **Desktop app**
5. Name: `TaskTether` → **Create**
6. Click **Download JSON** on the confirmation screen
7. Rename the downloaded file to exactly `GoogleCredentials.json`

### Step 3 — Add the credentials file to the app

1. Right-click `TaskTether.app` in your Applications folder → **Show Package Contents**
2. Open `Contents → Resources`
3. Copy `GoogleCredentials.json` into that folder

### Step 4 — Add your redirect URI

1. Back in Google Cloud Console, go to **APIs & Services → Credentials**
2. Click on your OAuth 2.0 Client ID to open it
3. Under **Authorised redirect URIs**, click **+ Add URI**
4. Enter `http://localhost:8080` → **Save**

### Step 5 — Connect your account

1. Open TaskTether from the menu bar
2. Click **Connect Google Account**
3. Your browser opens — sign in and click Allow
4. TaskTether is now connected and will start syncing

### Step 6 — Grant Reminders access

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
