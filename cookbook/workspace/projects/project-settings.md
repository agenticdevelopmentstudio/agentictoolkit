---
id: 03a30e6b-8c8c-40d3-8135-078d4fd351ce
title: Project Settings
domain: agentictoolkit://cookbook/workspace/projects/project-settings
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Declares the Projects feature''s three persisted settings: repo-scan
  skip patterns, active-pane outline, and pointer-follows-focus.'
platforms:
- swift
- macos
tags:
- git
- projects
- settings
- storage-keys
depends-on: []
related:
- agentictoolkit://cookbook/workspace/projects/git-repo-scanner
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/UserSettings+Projects.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/UserSetting.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/StorableSetting.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/UserSettings.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStorageProviders/UserDefaultsSettingsStorageProvider.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepoScanner.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectsCoordinator.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsActivePane.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/SettingsStore/UserDefaultsSettingsStoreTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Project Settings

## Overview

This declares three persisted settings for the Projects feature: a list of
repo-scan skip patterns, stored under the key `projectScanSkipPatterns` and
defaulting to the scanner's own default root skip-pattern list; a flag that
highlights the active pane, stored under the key `highlight_active_pane`
and defaulting to `true`; and a flag that makes pane focus follow the
pointer, stored under the key `active_pane_follows_mouse` and defaulting
to `false`. Each is a plain settings declaration with no logic of its own
— no validation, no side effect beyond what the underlying settings
mechanism already provides.

This file declares no read, write, remove, or observe mechanics of its
own; a shared settings-storage layer supplies that behavior, and a shared
storage provider supplies the persistence mechanics. This recipe covers
those collaborators only for the contract they give these three settings —
their own general contract belongs to a collaborator's own recipe (the
[Git Repo Scanner](agentictoolkit://cookbook/workspace/projects/git-repo-scanner)
recipe already covers the scanner that consumes the skip-patterns
setting). The code that reads the skip-patterns setting and constructs a
scanner from it, the settings panel that edits all three, and the
per-project override that can supersede the active-pane-highlight setting
are likewise collaborators' own contracts, out of scope here except where
this file's own documentation makes a claim about them.

## Behavioral Requirements

- **skip-patterns-key**: the skip-patterns setting's name MUST equal the
  string `"projectScanSkipPatterns"`.
- **skip-patterns-default**: the skip-patterns setting's default value
  MUST equal the scanner's own default root skip-pattern list — the
  literal array `["Library", "Music", "Pictures", "Movies", "Dropbox",
  "* Dropbox", "Google Drive"]`.
- **highlight-active-pane-key**: the active-pane-highlight setting's name
  MUST equal the string `"highlight_active_pane"`.
- **highlight-active-pane-default**: the active-pane-highlight setting's
  default value MUST equal `true`.
- **follows-mouse-key**: the pointer-follows-focus setting's name MUST
  equal the string `"active_pane_follows_mouse"`.
- **follows-mouse-default**: the pointer-follows-focus setting's default
  value MUST equal `false`.
- **main-thread-confinement**: all three settings MUST be read and written
  only on the UI's main execution context; that confinement comes from the
  shared settings types these declarations extend, not from anything
  declared in this file itself.
- **value-round-trip**: for each of the three settings, reading its value
  MUST return the most recently written value for that key, and writing a
  new value MUST persist it so a later read returns it.
- **removal-reverts-to-default**: removing any of the three settings MUST
  cause a subsequent read of its value to return that setting's own
  default value.
- **existence-check**: an existence check MUST return `true` only once a
  value has been explicitly stored for that setting's key, and `false`
  before any write and again after removal.
- **array-setting-json-encoded**: because a list of strings is not one of
  the value types the storage provider stores natively (integer,
  floating-point, boolean, string, binary data, URL, and date types are), a
  write to the skip-patterns setting MUST be JSON-encoded and stored as
  binary data under its key, and a read MUST JSON-decode that data back
  into a list of strings.
- **bool-settings-natively-stored**: because a boolean is one of the value
  types the storage provider stores natively, a write to the
  active-pane-highlight or pointer-follows-focus settings MUST be stored
  directly as a native boolean value under that setting's key, with no
  JSON encoding.
- **not-secure**: all three settings MUST be stored through the non-secure
  storage provider, never a credential-vault-backed secure provider. None
  of the three declarations opts into secure storage, so each defaults to
  the non-secure path, and the settings store dispatches on that flag to
  choose the provider.
- **corrupt-data-falls-back-to-default**: if the stored value for any of
  the three keys cannot be read back as that setting's declared type —
  undecodable data for the skip-patterns setting, or a value that fails to
  cast to boolean for the other two — a read MUST return that setting's
  default value rather than throwing or crashing.
- **change-notification**: a write to any of the three settings' value
  MUST update that setting's observable current-value projection
  synchronously, within the same call, before the write's assignment
  statement returns. The storage provider stores the value, then
  broadcasts the key name, delivered synchronously; each setting's own
  subscription filters for its own name and immediately re-reads and
  assigns its current value, with no queue hop.
- **no-pattern-validation**: the skip-patterns setting MUST accept and
  store any list of strings as its value, including empty strings,
  duplicate entries, and strings that are not valid glob syntax. The
  declaration performs no check of its own on the strings it stores; the
  documentation states the scanner is handed this list as a plain
  parameter specifically so its own walk logic — not this setting — can be
  tested independently of a settings store.
- **highlight-active-pane-override**: the active-pane-highlight setting's
  own documentation states that a per-project override supersedes it; the
  consumer that implements this precedence reads the override when
  present, falling back to this setting's value otherwise, confirming
  that, when present, the override MUST take precedence over this
  setting's value.

## Appearance

Not applicable — this is a persisted setting declaration, not a visual
component.

## States

Not applicable — this is a persisted setting declaration, not a visual
component.

## Accessibility

Not applicable — this is a persisted setting declaration, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-user-settings-projects-001 | skip-patterns-key | Read the skip-patterns setting's name | equals the string `"projectScanSkipPatterns"` |
| git-client-projects-user-settings-projects-002 | skip-patterns-default | Read the skip-patterns setting's default value | equals `["Library", "Music", "Pictures", "Movies", "Dropbox", "* Dropbox", "Google Drive"]` |
| git-client-projects-user-settings-projects-003 | highlight-active-pane-key, highlight-active-pane-default | Read the active-pane-highlight setting's name and default value | name equals `"highlight_active_pane"`; default value equals `true` |
| git-client-projects-user-settings-projects-004 | follows-mouse-key, follows-mouse-default | Read the pointer-follows-focus setting's name and default value | name equals `"active_pane_follows_mouse"`; default value equals `false` |
| git-client-projects-user-settings-projects-005 | value-round-trip | Set the skip-patterns setting's value to `["Archive*"]`, then read it back | equals `["Archive*"]` |
| git-client-projects-user-settings-projects-006 | value-round-trip | Set the active-pane-highlight setting's value to `false`, then read it back | equals `false` |
| git-client-projects-user-settings-projects-007 | array-setting-json-encoded | Set the skip-patterns setting's value to `["Foo"]`, then inspect the raw object the backing store holds under `"projectScanSkipPatterns"` | the stored object is binary data, not a native list; JSON-decoding that data as a list of strings yields `["Foo"]` |
| git-client-projects-user-settings-projects-008 | bool-settings-natively-stored | Set the active-pane-highlight setting's value to `false`, then inspect the raw object the backing store holds under `"highlight_active_pane"` | the stored object casts directly to boolean (`false`), not binary data |
| git-client-projects-user-settings-projects-009 | removal-reverts-to-default | Set the pointer-follows-focus setting's value to `true`, remove it, then read its value | equals `false` (its default value) |
| git-client-projects-user-settings-projects-010 | existence-check | Before any write, check whether the active-pane-highlight setting exists in the store; then set its value to `false` and check again | first check returns `false`; second check returns `true` |
| git-client-projects-user-settings-projects-011 | not-secure | Read the secure-storage flag on all three settings | each equals `false` |
| git-client-projects-user-settings-projects-012 | corrupt-data-falls-back-to-default | Store a JSON payload that does not decode as a list of strings (for example an encoded object, not an array) directly under `"projectScanSkipPatterns"` in the backing store, then read the setting's value | returns the skip-patterns setting's default value, with no thrown error |
| git-client-projects-user-settings-projects-013 | change-notification | Subscribe to the active-pane-highlight setting's observable current-value projection, then set its value to `false` | the subscriber observes `false` synchronously, before the statement that performed the write returns |
| git-client-projects-user-settings-projects-014 | no-pattern-validation | Set the skip-patterns setting's value to `["", "not [a valid glob", "dup", "dup"]` | all four entries are accepted and persisted verbatim, in order, with no filtering or deduplication |
| git-client-projects-user-settings-projects-015 | main-thread-confinement | From code compiled with strict concurrency checking, attempt to read the active-pane-highlight setting's value from a background execution context with no explicit hand-off to the main context | fails to compile, because a main-thread-confined member cannot be accessed synchronously off the main thread |

## Edge Cases

- **Null and empty input**: setting the skip-patterns setting's value to
  an explicit empty list leaves a later read of its value returning an
  empty list; removing it instead leaves a later read returning the
  non-empty default skip-pattern list, because
  **removal-reverts-to-default** reverts to whatever the default value is,
  not to an empty list. The empty string is also accepted as an ordinary
  member of the list, with no special-case rejection
  (**no-pattern-validation**). MUST behave this way.
- **Boundary values**: no maximum is imposed on the number of entries in
  the skip-patterns setting or on the length of any one entry; a list with
  hundreds of patterns is JSON-encoded and stored as one binary blob the
  same way a single-entry list is (**array-setting-json-encoded**). MUST
  behave this way.
- **Concurrent access**: every read, write, and remove on all three
  settings is confined to the main execution context
  (**main-thread-confinement**), so two calls issued from different
  concurrent tasks MUST execute in some serialized order with no
  interleaving of the underlying storage access — that confinement, not
  this file, is what rules out a data race. MUST behave this way.
- **Error states**: an encoding failure during a write to the
  skip-patterns setting is swallowed — the storage provider attempts the
  encode and simply returns, sending no change notification, if it fails.
  Encoding an ordinary list of strings does not fail in practice, so this
  path is unreachable for this specific setting; it is documented here
  because it is a real, inherited behavior of the storage layer this
  setting depends on, not because it is expected to occur. SHOULD be
  understood as inherited, unreachable-for-this-type behavior, not a gap
  in this declaration.
- **Offline or disconnected state**: not applicable — this declaration
  performs no network call of any kind; the backing store is local,
  on-device storage with no connectivity dependency.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| skip-patterns storage key | string (fixed) | `"projectScanSkipPatterns"` | The literal name the setting is declared with; pinned per **skip-patterns-key**. |
| skip-patterns default | list of strings (fixed) | the scanner's own default root skip-pattern list | Returned whenever no value has been stored or a stored value cannot be decoded. |
| active-pane-highlight storage key | string (fixed) | `"highlight_active_pane"` | Pinned per **highlight-active-pane-key**. |
| active-pane-highlight default | boolean (fixed) | `true` | Returned whenever no value has been stored. |
| pointer-follows-focus storage key | string (fixed) | `"active_pane_follows_mouse"` | Pinned per **follows-mouse-key**. |
| pointer-follows-focus default | boolean (fixed) | `false` | Returned whenever no value has been stored. |
| secure-storage flag (all three) | boolean (fixed) | `false` | Not set explicitly at any of the three declarations, so the default applies, routing all three through the non-secure storage provider rather than a credential-vault-backed provider. |
| the shared settings store | singleton | the shared store | The store all three settings read and write through. A consuming app may replace the shared store before first access. |

No environment variable is read by this file — it is three plain settings
declarations with no parameters of their own; a separate coordinator is
the one caller that reads the skip-patterns setting's current value and
passes it into the scanner's own configuration, but that wiring lives
outside this component's own file and is not part of its contract.

## Deep Linking

Not applicable: this file defines no URL scheme, route, or navigation
destination.

## Localization

Not applicable: this file produces no user-facing string of its own. Its
three properties store a key name, a default value, and a way to read and
write that value — none of which is displayed text; the settings panel
that shows English labels for these values is a separate file with its
own recipe to write.

## Accessibility Options

Not applicable: this file renders nothing and reads no accessibility
display setting (Reduce Motion, Increase Contrast, Differentiate Without
Color) — it has no UI surface of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no
conditional feature-gating logic — all three declarations are
unconditional.

## Analytics

Not applicable: the source contains no analytics or event-emission call of
any kind.

## Privacy

- **Data collected**: the skip-patterns setting stores folder-name and
  glob-pattern strings the user has typed or accepted, which can reveal
  something about how the user organizes their home directory; the
  active-pane-highlight and pointer-follows-focus settings store two
  boolean UI preferences with no descriptive content of their own.
- **Storage**: all three values live in local storage only. The
  secure-storage flag is not set at any of the three declarations and
  defaults to `false`, so none of the three is routed to a credential
  vault (**not-secure**).
- **Transmission**: none — this file makes no network call and transmits
  nothing.
- **Retention**: each value persists until explicitly overwritten, removed,
  or the app's local storage domain is deleted; the file itself defines no
  expiry or automatic cleanup.

## Logging

Not applicable: this file makes no logging call of its own.

## Platform Notes

- **SwiftUI**: the source is `packages/apple/AgenticToolkit/macOS/Features/Projects/UserSettings+Projects.swift`,
  part of the macOS-only `AgenticToolkitMacOS` target (`project.yml`),
  importing `AgenticToolkitCore` for `UserSettings`/`UserSetting` and
  referring to its target-mate `GitRepoScanner.defaultRootSkipPatterns`
  with no import needed. The isolation described in
  **main-thread-confinement** comes from the extended type's own primary
  declaration and from the settings-value class itself, both declared
  `@MainActor`, with no `@MainActor` attribute repeated on these three
  properties themselves. Nothing here is SwiftUI-specific — the three
  properties have no view and no state beyond what `UserSetting` already
  provides; a SwiftUI consumer would bind to them through the
  `@ObservedSetting` property wrapper (`Core/SettingStorage/UserSetting.swift`).
- **AppKit / UIKit**: this is the source. The file imports only
  `Foundation` and `AgenticToolkitCore` — no AppKit or UIKit type appears
  in it, so it would compile unchanged behind a UIKit consumer if the
  target were extended to iOS. Its first setting's default, however,
  reaches into `GitRepoScanner.defaultRootSkipPatterns`, and that
  scanner's own recipe records that an iOS port would need a different
  filesystem-access model (a user-picked folder or a security-scoped
  bookmark) rather than the Home-directory scan this default list assumes.
- **Compose**: model the three properties as members of a Kotlin `object`
  backed by Jetpack `DataStore<Preferences>`. `booleanPreferencesKey("highlight_active_pane")`
  and `booleanPreferencesKey("active_pane_follows_mouse")` map directly
  onto the two boolean settings. `DataStore`'s native
  `stringSetPreferencesKey` stores an unordered `Set<String>`, which would
  silently drop the order-preserving, duplicate-permitting semantics
  **no-pattern-validation** and **array-setting-json-encoded** describe
  for the skip-patterns setting — use a JSON-serialized
  `stringPreferencesKey("projectScanSkipPatterns")` instead, and
  decode/encode a `List<String>` at the boundary, to preserve those
  semantics. Mirror the get/set/remove/exists surface with `DataStore`'s
  `Flow`-based read and `edit { }` write.
- **React/Web**: model the three properties as a small typed wrapper over
  `localStorage`, since a browser has no direct filesystem-scanning use
  for the skip-patterns setting but the setting itself is just a stored
  list. Store the skip-patterns setting as a JSON-serialized array under
  the key `"projectScanSkipPatterns"`, and the two booleans as JSON
  `"true"`/`"false"` strings under `"highlight_active_pane"` and
  `"active_pane_follows_mouse"`, parsing at the read boundary since
  `localStorage` only stores strings natively. Use the browser's
  `storage` event for cross-tab change notification in place of the
  synchronous update this file's dependency provides.
- **WinUI 3**: the reason this recipe exists. Model the three properties
  as static members of a settings class backed by
  `Windows.Storage.ApplicationData.Current.LocalSettings.Values`, keyed
  `"projectScanSkipPatterns"`, `"highlight_active_pane"`, and
  `"active_pane_follows_mouse"`. `ApplicationDataContainer.Values` stores a
  `Boolean` natively, so the two flag settings map directly; it does not
  store a `List<string>` directly, so serialize the skip-patterns setting
  with `System.Text.Json.JsonSerializer.Serialize`/`Deserialize` into a
  stored `string` value — the same fallback-to-encoded-payload shape this
  file's dependency uses for binary data. Expose each property through a
  member that raises `INotifyPropertyChanged`, firing synchronously on the
  UI thread, in place of the observable current-value projection. C# has
  no direct equivalent to Swift's compiler-enforced `@MainActor` isolation
  for a static member; document the class as UI-thread-affine by
  convention, or assert `DispatcherQueue.HasThreadAccess` at each entry
  point. Model the active-pane-highlight override relationship with a
  nullable `bool?` on the per-project options type and the same
  precedence C#'s null-coalescing operator expresses directly:
  `options?.HighlightActivePane ?? Settings.HighlightActivePane`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/UserSettings+Projects.swift` |

## Design Decisions

**Decision**: `activePaneFollowsMouse` defaults to `false`.
**Rationale**: the source's own doc comment states this directly: focus that moves without being asked to is a preference people hold strongly in both directions, and having keys go somewhere the user did not put them is "the wrong default" (`UserSettings+Projects.swift`).
**Approved**: pending

**Decision**: `GitRepoScanner` receives `projectScanSkipPatterns` as a constructor parameter rather than reading the setting itself.
**Rationale**: the source's own doc comment states the reasoning directly — the scanner runs off the main actor, and a pure walk that is told what to skip is testable without a settings store (`UserSettings+Projects.swift`).
**Approved**: pending

**Decision**: `highlightActivePane` lives alongside the other project settings, and a per-project `ThemeProjectOptions.highlightActivePane` can override it.
**Rationale**: the source's own doc comment states the setting belongs here rather than with the appearance settings because it concerns a project window's panes specifically, and names the override directly (`UserSettings+Projects.swift`); the precedence is confirmed in the consumer, `ComposableTabsActivePane.swift`.
**Approved**: pending

**Decision**: the three storage keys use two different naming conventions — `projectScanSkipPatterns` is camelCase, while `highlight_active_pane` and `active_pane_follows_mouse` are snake_case.
**Rationale**: not stated in the source. The doc comments explain each setting's behavior and default but give no reason for the differing key format between the three (`UserSettings+Projects.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | failed | Reliability |

`separation-of-concerns` passes because `UserSettings+Projects.swift` declares only each setting's identity, type, and default; the read/write/remove/observe mechanics live in `UserSetting`/`SettingsStore`, the persistence mechanics live in `UserDefaultsSettingsStorageProvider`, the scan logic that consumes `projectScanSkipPatterns` lives in `GitRepoScanner`, and the panel that edits all three lives in `ProjectsSettingsPanelViewController` — none of that logic is duplicated here. `unit-test-coverage` is partial because no test file asserts any of this file's own three facts — the pinned key strings, the two defaults, or the documented `highlightActivePane`/`ThemeProjectOptions` override relationship — even though the generic mechanism these properties rely on is well covered elsewhere, by `UserDefaultsSettingsStoreTests.swift`'s Bool round-trip, string-array round-trip, empty-array round-trip, and corrupted-data-fallback tests. `explicit-error-handling` is partial because a decode failure on `projectScanSkipPatterns`'s stored `Data`, and an encode failure on a write to it, both fall back silently to a default value or a no-op with no signal surfaced to the caller — safe, but not surfaced, and that behavior is inherited from `UserDefaultsSettingsStorageProvider` rather than handled explicitly by this file. `data-integrity` fails because neither a corrupted `Data` payload under `"projectScanSkipPatterns"` nor an unexpectedly-typed object under either Bool key is ever detected or reported as corrupt; both cases resolve silently to `defaultValue`, indistinguishable from the key never having been set at all.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
