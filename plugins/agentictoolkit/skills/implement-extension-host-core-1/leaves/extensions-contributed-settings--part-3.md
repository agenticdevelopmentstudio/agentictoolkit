<!-- leaf: implement-extension-host-core-1/extensions-contributed-settings--part-3 · source: extension-host-core-extensions-contributed-settings.md -->

# ContributedSettings — continued (part 3)

**Rules** (cite as `implement-extension-host-core-1/extensions-contributed-settings--part-3#<slug>`):

- `mixed-union-fallback` MUST
- `no-type-inference` MUST
- `json-escape-hatch-text` MUST
- `deprecation-appended` MUST
- `explanation-source` MUST
- `setting-order-field` MUST
- `sendable-value-types` MUST
- `pure-no-side-effects` MUST

- **mixed-union-fallback**: when a property's declared `type` is a union whose non-null members do not collapse to exactly one name (so `effectiveType` is `nil`), classification MUST record a `ContributedSettingNote(kind: .mixedUnionType)` naming the union's members and MUST classify as `.json` using the declared default's JSON text (`ContributedSettings.swift`).
- **no-type-inference**: when a property declares no `type` at all (not a union, and `effectiveType` is `nil`), classification MUST be inferred from the JSON type of `default`: a boolean default classifies as `.toggle` with no note; a whole-number default classifies as `.integer` (bounds handled per `integer-bounds-rounding`); a non-whole-number default classifies as `.number`; a string default classifies as `.text` (honouring `editPresentation`); an array or object default classifies as `.json` with no note; a `null` default classifies as `.json` and records `.unrenderableType` ("no type, and a null default says nothing about one"); and an entirely absent default classifies as `.json` (rendering `"null"`) and records `.unrenderableType` ("no type, no enum and no default") (`ContributedSettings.swift`).
- **json-escape-hatch-text**: `jsonText(of:)` MUST render pretty-printed, key-sorted JSON with forward slashes left unescaped; a whole-number JSON value MUST render without a trailing `.0`; and a `nil` input MUST render as the JSON literal `null` (`ContributedSettings.swift`).
- **deprecation-appended**: when a property declares `deprecationMessage`, or, absent that, `markdownDeprecationMessage`, the resulting `ContributedSetting.explanation` MUST append that message after any `description`/`markdownDescription` body separated by one blank line, or stand alone when no body exists, and a `ContributedSettingNote(kind: .deprecated)` carrying that message as `detail` MUST be recorded, independent of what `ContributedSettingKind` the property classified as (`ContributedSettings.swift`, `655-666`).
- **explanation-source**: `explanation`'s body MUST be `description` when present, and otherwise `markdownDescription` treated as plain text — its Markdown syntax MUST NOT be rendered or stripped, only carried through verbatim, because nothing that displays this string renders Markdown (`ContributedSettings.swift`).
- **setting-order-field**: `ContributedSetting.order` MUST equal the property's own declared `order`, and that value MUST already have determined the setting's position within `settings` per `setting-ordering`.
- **sendable-value-types**: `ContributedSettingOption`, `ContributedSettingKind`, `ContributedSetting`, `ContributedSettingsSection`, `ContributedSettingNote`, and `ContributedSettingsDeclaration` MUST each be declared `Sendable` and `Equatable` value types, so a caller MAY pass any of them across an actor or `Task` boundary with no additional synchronization.
- **pure-no-side-effects**: `ContributedSettingsBuilder` MUST hold no mutable state of its own, and neither `sections(for:)` nor `storageName(forKey:ofExtension:)` MUST read a setting's stored value, write one, or perform any file, network, or window-system side effect — each call's only observable effect MUST be its return value.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `manifest` | `ExtensionManifest` | none (required) | The decoded `package.json` passed to the `sections(for: manifest:)` overload; supplies `configuration`, `identifier`, `displayName ?? name`, and `decodingFailures` to the lower-level overload. |
| `configuration` | `[ExtensionManifest.Configuration]` | none (required) | The decoded `contributes.configuration` array (already normalized from VS Code's single-object-or-array form upstream) passed to the lower-level `sections(for:ofExtension:fallbackTitle:decodingFailures:)` overload. |
| `identifier` (`ofExtension`) | `String` | none (required) | The extension's case-folded `publisher.name` (or bare `name`), used verbatim in every `storageName` and every `ContributedSettingNote.extensionIdentifier` this call produces. |
| `fallbackTitle` | `String` | none (required) | The title a titleless section borrows — `manifest.displayName ?? manifest.name` at the one production call site. |
| `decodingFailures` | `[DecodingFailure]` | `[]` | Failures the manifest decoder recorded; only an entry whose `key == "contributes.configuration"` affects this file's output, distinguishing `.unreadable` from `.undeclared`. |
| `key` (to `storageName(forKey:ofExtension:)`) | `String` | none (required) | The dotted property key a caller wants the storage name for. |

No environment variable, settings key of its own, or injected dependency is read by this file — it is a pure function of its parameters.

## Localization

`ContributedSettingNote.detail` and the raw-text fallbacks it quotes (via `rawText(of:)`, `ContributedSettings.swift`) are shown to a person rather than swallowed — the type's own doc comment says so directly (`ContributedSettings.swift`, "what was compromised is shown to a person rather than swallowed") — but every one of those strings is composed as a hardcoded English literal interpolated inline (e.g. `"enum has a member that is not a string; classifying on type instead"`, `"section \(index) declared no title; using \"\(fallbackTitle)\""`); none is looked up through a String Catalog, `NSLocalizedString`, or any other localization key. A `ContributedSettingOption.label` that falls back to a member's raw `value` (per `enum-label-positional`) is similarly whatever text the extension manifest happened to write, never localized by this file.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — no localization key exists) | e.g. `"already declared by an earlier section; this declaration is ignored"` | `ContributedSettingNote.detail`, composed inline in English at each `note(...)` call site inside `classify`, `choice`, `agreeing`, `clamped`, `boolean`, `string`, `number`, `integer`, and `inferred` |

