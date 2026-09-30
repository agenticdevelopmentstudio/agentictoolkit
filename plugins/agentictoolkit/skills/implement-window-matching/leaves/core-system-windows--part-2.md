<!-- leaf: implement-window-matching/core-system-windows--part-2 · source: window-matching-core-system-windows.md -->

# Window Matching Core System Windows — continued (part 2)

**Rules** (cite as `implement-window-matching/core-system-windows--part-2#<slug>`):

- `context-fields` MUST
- `context-immutable-identity` MUST
- `context-init-defaults` MUST
- `context-color-format` MUST
- `context-name-verbatim` MUST
- `add-window-append` MUST
- `add-window-replace` MUST
- `add-window-no-window-id-dedupe` MUST
- `add-window-keeps-focus` MUST
- `remove-by-id` MUST
- `remove-by-id-missing` MUST
- `remove-by-id-clears-focus` MUST
- `remove-by-window-id` MUST
- `remove-by-window-id-missing` MUST
- `remove-by-window-id-clears-focus` MUST
- `remove-discardable` MUST
- `snapshot-lookup` MUST
- `update-by-id` MUST
- `update-by-id-missing` MUST
- `update-by-window-id` MUST
- `update-scope` MUST
- `update-closure-synchronous` MUST
- `live-window-count` MUST
- `focus-not-validated` MUST
- `concurrency-by-value` MUST
- `persistence-external` MUST

### SystemWindowContext

- **context-fields**: `SystemWindowContext` MUST store `id: UUID`, `name: String`, `color: String`, `windowSnapshots: [SystemWindowSnapshot]`, `lastFocusedWindowID: UUID?` and `createdAt: Date`.
- **context-immutable-identity**: `id` and `createdAt` MUST be immutable (`let`); `name`, `color`, `windowSnapshots` and `lastFocusedWindowID` MUST be mutable (`var`).
- **context-init-defaults**: `init` MUST default `id` to a fresh `UUID`, `color` to `"#007AFF"`, `windowSnapshots` to `[]`, `lastFocusedWindowID` to `nil` and `createdAt` to the current date and time; `name` is required.
- **context-color-format**: `color` is a caller-supplied hex string that, per its doc comment, "Includes the leading '#'" (for example `"#FF5733"`); the type MUST store it verbatim without parsing or validating it.
- **context-name-verbatim**: `name` MUST be stored verbatim; the type MUST NOT reject an empty or duplicate name.
- **add-window-append**: `addWindow(_:)` MUST append the snapshot to the end of `windowSnapshots` when no existing snapshot has the same `id`.
- **add-window-replace**: `addWindow(_:)` MUST replace, at the same index, the first existing snapshot whose `id` equals the argument's `id`, leaving the array's count and order unchanged.
- **add-window-no-window-id-dedupe**: `addWindow(_:)` MUST NOT check `windowID`; two snapshots with different `id` values and the same `windowID` MAY coexist in one context. Uniqueness of a live window across and within contexts is enforced by the caller, `SystemWindowContextManager.addWindow(windowID:to:)`, which throws `windowAlreadyAssigned` for another context and updates the existing snapshot for the same one.
- **add-window-keeps-focus**: `addWindow(_:)` MUST NOT change `lastFocusedWindowID`.
- **remove-by-id**: `removeWindow(id:)` MUST remove the first snapshot whose `id` equals the argument and return it.
- **remove-by-id-missing**: `removeWindow(id:)` MUST return `nil` and leave the context unchanged when no snapshot has that `id`.
- **remove-by-id-clears-focus**: `removeWindow(id:)` MUST set `lastFocusedWindowID` to `nil` when it equals the removed snapshot's `id`, and MUST leave it unchanged otherwise.
- **remove-by-window-id**: `removeWindow(windowID:)` MUST remove the first snapshot (in array order) whose `windowID` equals the argument and return it; later snapshots with the same `windowID` MUST remain.
- **remove-by-window-id-missing**: `removeWindow(windowID:)` MUST return `nil` and leave the context unchanged when no snapshot has that `windowID`; a dormant snapshot (`windowID == nil`) MUST never match.
- **remove-by-window-id-clears-focus**: `removeWindow(windowID:)` MUST set `lastFocusedWindowID` to `nil` when it equals the removed snapshot's `id`.
- **remove-discardable**: Both `removeWindow` overloads MUST be callable without using the result (`@discardableResult`).
- **snapshot-lookup**: `snapshot(id:)` MUST return the first snapshot whose `id` equals the argument, or `nil` when none does, without mutating the context.
- **update-by-id**: `updateSnapshot(id:_:)` MUST invoke the closure exactly once with the first snapshot whose `id` matches, passed `inout`, write the closure's changes back in place, and return `true`.
- **update-by-id-missing**: `updateSnapshot(id:_:)` MUST return `false` without invoking the closure when no snapshot has that `id`.
- **update-by-window-id**: `updateSnapshot(windowID:_:)` MUST invoke the closure exactly once with the first snapshot whose `windowID` matches, write the changes back in place, and return `true`; it MUST return `false` without invoking the closure when none matches.
- **update-scope**: The update closure MUST be able to change only a snapshot's mutable fields (`windowID`, `savedFrame`, `display`, `title`, `lastSeen`); `id`, `fingerprint` and `app` are immutable, and `updateSnapshot` MUST NOT reorder `windowSnapshots` or touch `lastFocusedWindowID`.
- **update-closure-synchronous**: The update closure MUST be non-escaping and synchronous; it runs before `updateSnapshot` returns.
- **live-window-count**: `liveWindowCount` MUST return the number of snapshots whose `isLive` is `true`.
- **focus-not-validated**: The type MUST NOT check that `lastFocusedWindowID` names a snapshot in `windowSnapshots`; only the two `removeWindow` overloads clear it.

### Concurrency and persistence

- **concurrency-by-value**: The types MUST NOT carry actor isolation or locks; a `SystemWindowContext` is mutated through `mutating` methods on a single owner's copy, and concurrent mutation of one stored value is prevented by Swift's exclusivity rules, not by the type.
- **persistence-external**: The types MUST NOT persist themselves. `SystemWindowContextStore` encodes a context with a `JSONEncoder` configured with `.prettyPrinted`, `.sortedKeys` and `.iso8601` dates, and decodes with a matching `.iso8601` `JSONDecoder`; with a default coder, `Date` fields encode as seconds since 2001-01-01 instead.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SystemWindowContext.init` `id` | `UUID` | `UUID()` | Context identity; supply one to rebuild a known context. |
| `SystemWindowContext.init` `name` | `String` | required | User-visible context name. |
| `SystemWindowContext.init` `color` | `String` | `"#007AFF"` | `#`-prefixed hex color shown in the menu bar and context list. |
| `SystemWindowContext.init` `windowSnapshots` | `[SystemWindowSnapshot]` | `[]` | Initial snapshots, stored as given. |
| `SystemWindowContext.init` `lastFocusedWindowID` | `UUID?` | `nil` | Snapshot ID to refocus when the context is switched back to. |
| `SystemWindowContext.init` `createdAt` | `Date` | `Date()` | Creation timestamp; injectable for tests. |
| `SystemWindowSnapshot.init` `id` | `UUID` | `UUID()` | Stable snapshot identity across restarts. |
| `SystemWindowSnapshot.init` `windowID` | `UInt32?` | `nil` | Current CGWindowID; `nil` means dormant. |
| `SystemWindowSnapshot.init` `lastSeen` | `Date` | `Date()` | Last time the snapshot had a live window; injectable for tests. |
| `SystemWindowSnapshot.init` `fingerprint`, `savedFrame`, `display`, `app`, `title` | various | required | Identity and restore data, stored verbatim. |
| `SystemWindowFingerprint.init` all parameters | various | required | No defaults. |
| `SystemWindowInfo.init` all parameters | various | required | No defaults. |
| Coder date strategy | `JSONEncoder` / `JSONDecoder` | caller's choice | The types impose none; `SystemWindowContextStore` uses `.iso8601`. |

## Localization

`MatchStrategy.displayName` returns hardcoded English literals with no string-catalog lookup; its doc comment places it beside the enum so "any host rendering a strategy picker reads the label from the model".

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `Exact` | `displayName` for `appAndTitleExact`, a strategy-picker label |
| (none; literal) | `Substring` | `displayName` for `appAndTitleSubstring` |
| (none; literal) | `Regex` | `displayName` for `appAndTitleRegex` |
| (none; literal) | `App Only` | `displayName` for `appOnly` |

The example context names in doc comments ("iOS App", "Backend API", "Docs") are documentation, not strings the code emits.

## Privacy

- **Data collected**: The types hold window metadata about other apps: owning app name, process ID, window title, frame and display. Window titles can contain document names, web page titles or message subjects, so they are potentially personal.
- **Storage**: The types store nothing themselves; in memory only. `SystemWindowContextStore` persists contexts, including each snapshot's `title` and `fingerprint.titlePattern`, as JSON files on local disk.
- **Transmission**: The types never transmit data; no member performs network access.
- **Retention**: A snapshot's `title` and fingerprint stay in the context until `removeWindow` removes the snapshot; dormant snapshots are kept, not expired, and nothing in these types deletes data by age.

