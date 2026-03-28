# Roadmap

This is a living document. Items move between versions as priorities shift.

---

## v1.1.0 — Distribution & Polish

The focus is making it easier for people to get started and improving the first-run experience.

- [ ] **Binary release** — pre-built `.zip` on GitHub Releases so non-developers can install without Xcode. Users still supply their own `GoogleCredentials.json` via Show Package Contents
- [ ] **Screenshots and demo video** — README screenshot, setup walkthrough video for the Google Cloud steps
- [ ] **Gatekeeper instructions** — restore Installation section in README for binary users (right-click → Open bypass)
- [ ] **Mac Mini testing** — verify TaskTether runs reliably as a background service on older Intel hardware (2014 Mac Mini, macOS via OpenCore Legacy Patcher)
- [ ] **Notification on sync error** — surface a macOS notification if sync fails repeatedly, rather than silently stopping

---

## v1.2.0 — App Store Path

Removes the App Store blockers identified in v1.0.

- [ ] **Replace LocalHTTPServer with ASWebAuthenticationSession** — requires creating an iOS-type OAuth client in Google Cloud Console to support the `tasktether://oauth` custom URL scheme
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
- [ ] **Multiple task lists** — currently syncs the TaskTether list only
- [ ] **Overdue task indicator** — visual flag for tasks past their due date
- [ ] **Menu bar badge** — show incomplete task count on the menu bar icon
- [ ] **iCloud sync for settings** — sync theme and preferences across Macs

