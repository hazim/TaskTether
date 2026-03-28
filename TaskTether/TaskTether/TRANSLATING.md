# Translating TaskTether

TaskTether uses Apple's `.xcstrings` format for localisation. All strings live in a single file:

```
TaskTether/TaskTether/Localizable.xcstrings
```

## Currently supported languages

| Code | Language |
|------|----------|
| `en` | English (base) |
| `hu` | Magyar (Hungarian) |
| `ar` | العربية (Arabic) |

## Adding a new language

1. Open `Localizable.xcstrings` in a text editor or Xcode's string catalog editor
2. For each key, add a new entry under `localizations` with your language code:

```json
"today.add.placeholder": {
  "localizations": {
    "en": {
      "stringUnit": { "state": "translated", "value": "New task…" }
    },
    "fr": {
      "stringUnit": { "state": "translated", "value": "Nouvelle tâche…" }
    }
  }
}
```

3. Use your language's [BCP 47 code](https://www.iana.org/assignments/language-subtag-registry) (e.g. `fr` for French, `de` for German, `ja` for Japanese)
4. Translate all 74 keys — untranslated keys fall back to English automatically
5. Add your language to the picker in `SettingsView.swift`:

```swift
private let supportedLanguages: [(id: String, name: String)] = [
    ("system", "System Default"),
    ("en",     "English"),
    ("hu",     "Magyar"),
    ("ar",     "العربية"),
    ("fr",     "Français"),   // ← add your language here
]
```

## Key naming convention

Keys follow a `section.subsection.element` pattern:

| Prefix | Used for |
|--------|----------|
| `settings.*` | Settings window strings |
| `nav.*` | Navigation tab labels |
| `sync.*` | Sync status and button labels |
| `today.*` | Today panel strings |
| `service.*` | Service name labels |
| `status.*` | Connection status labels |
| `error.*` | Error messages |
| `tooltip.*` | Hover tooltips |
| `expanded.*` | Expanded stats panel |

## Testing your translation

1. Open TaskTether Settings → Language → select your language
2. Restart the app
3. All UI strings should appear in your language
4. Check that long strings don't overflow their containers — test in both Compact and Expanded views

## Format strings

Some keys contain format specifiers. Preserve them exactly:

| Specifier | Meaning |
|-----------|---------|
| `%d` | Integer (e.g. number of minutes) |
| `%@` | String placeholder |
| `%1$@`, `%2$@` | Ordered string placeholders |
| `%1$lld`, `%3$lld` | Ordered integer placeholders |

## RTL languages

Arabic and other right-to-left languages are handled automatically by SwiftUI. No layout changes are needed — just provide the translated strings.

## Submitting a translation

Open a pull request with your changes to `Localizable.xcstrings` and the `SettingsView.swift` language picker update. Please include your name or handle so we can credit you in the README.
