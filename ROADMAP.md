# Roadmap

This is a living document. Items move between versions as priorities shift.

---

## v1.1.0 — Distribution & Polish

The focus is making it easier for people to get started and improving the first-run experience.

- [ ] **Binary release** — a build script (`scripts/build-release.sh`) now produces a signed, zipped `.zip`; still open: uploading it to GitHub Releases. Users still supply their own `GoogleCredentials.json`, either baked in via `--credentials` or via Show Package Contents
- [ ] **Screenshots and demo video** — README screenshot, setup walkthrough video for the Google Cloud steps
- [x] **Gatekeeper instructions** — restore Installation section in README for binary users (right-click → Open bypass)
- [ ] **Mac Mini testing** — verify TaskTether runs reliably as a background service on older Intel hardware (2014 Mac Mini, macOS via OpenCore Legacy Patcher)
- [ ] **Notification on sync error** — surface a macOS notification if sync fails repeatedly, rather than silently stopping

---

## v1.2.0 — App Store Path

Removes the App Store blockers identified in v1.0.

- [ ] **Replace LocalHTTPServer with ASWebAuthenticationSession** — requires creating an iOS-type OAuth client in Google Cloud Console to support the `tasktether://oauth` custom URL scheme (the listener already uses an ephemeral port, so the fixed-port collision is gone)
- [ ] **Remove localhost server dependency** — no open network port during sign-in
- [ ] **Notarisation** — requires Apple Developer account ($99/year). Removes Gatekeeper warning for binary users
- [ ] **App Store submission** — pending notarisation and OAuth fix

---

## Good to know

- **iOS / iPadOS** — Apple Reminders and Google Tasks both have native mobile apps that cover this well. TaskTether is focused on the Mac. That said, if someone from the community wants to take this in that direction, the door is open.
- **Windows / Linux** — TaskTether is built on EventKit and AppKit, both Apple-only frameworks. macOS only by design.

---

## Future — Unscheduled

Ideas that are on the radar but not yet prioritised.

- [ ] **More languages** — contributions welcome via LOCALISING.md
- [ ] **More themes** — contributions welcome via the custom theme JSON format
- [ ] **Due date editing** — change a task's due date from within TaskTether
- [x] **Multiple task lists** — shipped in 1.2.0: every editable Reminders list syncs with a Google Tasks list of the same name
- [x] **Overdue task indicator** — shipped in 1.1.1 (row flag only; overdue tasks are not listed in the popover)
- [x] **Menu bar badge** — shipped in 1.1.1, off by default since 1.2.1 (Settings → Show task count in menu bar)
- [ ] **iCloud sync for settings** — sync theme and preferences across Macs

