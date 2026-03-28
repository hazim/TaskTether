# Localising TaskTether

TaskTether uses Apple's String Catalog format (`Localizable.xcstrings` and `InfoPlist.xcstrings`). All UI strings are stored there as key/value pairs with translations for each supported language.

Current languages: **English** (source), **Magyar** (Hungarian), **العربية** (Arabic).

---

## Adding a new language

### 1. Register the language in Xcode

1. Open `TaskTether.xcodeproj` in Xcode
2. Click the **TaskTether project** in the file navigator (blue icon at the top)
3. Select the **TaskTether project** (not the target) → **Info** tab
4. Under **Localizations**, click **+** and choose your language
5. When prompted, tick both `Localizable.xcstrings` and `InfoPlist.xcstrings` and set **Reference Language** to **English**

### 2. Add translations to `Localizable.xcstrings`

Open `TaskTether/TaskTether/Localizable.xcstrings`. For each key, add a localisation block for your language code alongside the existing ones. Example — adding French (`fr`):

```json
"sync.button" : {
  "localizations" : {
    "ar" : { "stringUnit" : { "state" : "translated", "value" : "مزامنة الآن" } },
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Sync Now" } },
    "fr" : { "stringUnit" : { "state" : "translated", "value" : "Synchroniser" } },
    "hu" : { "stringUnit" : { "state" : "translated", "value" : "Szinkronizálás most" } }
  }
}
```

Repeat for every key in the file. Keys with no translation for your language will fall back to English automatically.

### 3. Add translations to `InfoPlist.xcstrings`

Open `TaskTether/TaskTether/InfoPlist.xcstrings` and add your language to the `NSRemindersUsageDescription` key. This is the text macOS shows in the Reminders permission dialog on first launch.

### 4. Add the language to the in-app picker

Open `TaskTether/TaskTether/SettingsView.swift` and add your language to the `supportedLanguages` array near the top of `GeneralSettingsTab`:

```swift
private let supportedLanguages: [(id: String, name: String)] = [
    ("system", "System Default"),
    ("en",     "English"),
    ("fr",     "Français"),   // ← add your entry here
    ("hu",     "Magyar"),
    ("ar",     "العربية"),
]
```

Use the native name of the language (e.g. `Français`, not `French`).

---

## Key naming conventions

Keys follow a dot-separated namespace pattern:

| Prefix | Used for |
|---|---|
| `settings.*` | Settings window strings |
| `sync.*` | Sync button and strip |
| `today.*` | Today tab |
| `expanded.*` | Expanded tab |
| `nav.*` | Segment nav labels |
| `service.*` | Service status labels |
| `status.*` | Connection status dot labels |
| `error.*` | Error messages |
| `general.*` | Shared strings (Quit, etc.) |
| `connect.*` | Google sign-in screen |
| `app.*` | App-level strings |
| `task.*` | Task row strings |
| `tooltip.*` | Hover tooltips |

---

## Notes

- String Catalog keys with `"extractionState" : "stale"` are intentional manual keys — they are used in code via `String(localized: "key.name")` and are not auto-extracted by Xcode. Do not remove them.
- Language names in the picker (`Magyar`, `العربية`) are intentionally left in their native script and are not localised — this is standard UX practice so users can find their own language regardless of the app's current language.
- If your language is right-to-left, macOS handles layout mirroring automatically. No code changes are needed.

---

## Submitting a translation

Open a pull request with your changes to `Localizable.xcstrings`, `InfoPlist.xcstrings`, and `SettingsView.swift`. Please include a note on which language you have added and whether it is a full or partial translation.
