---
id: d4b4359e-e9c8-439c-abcf-309fcc419348
title: Window Matching Core System Windows
domain: agentictoolkit://cookbook/core/system-windows/core-system-windows
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Value types for window contexts: MatchStrategy, SystemWindowFingerprint,
  SystemWindowInfo, SystemWindowSnapshot and SystemWindowContext.'
platforms:
- swift
- macos
tags:
- window-management
- system-windows
- window-matching
- window-contexts
- foundation
depends-on: []
related:
- agentictoolkit://cookbook/macos/system-windows/ui/window-explorer-view
references:
- https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo
approved-by: ''
approved-date: ''
---

# Window Matching Core System Windows

## Overview

The core model of the AgenticToolkit "system window contexts" feature: five platform-neutral value types under `packages/apple/AgenticToolkit/Core/SystemWindows/`. They carry no behavior beyond in-memory collection edits; matching, persistence and window movement live in their consumers.

- `MatchStrategy.swift` declares `MatchStrategy`, a `String`-backed enum (`appAndTitleExact`, `appAndTitleSubstring`, `appAndTitleRegex`, `appOnly`) that says how strictly a fingerprint must match a live window, plus an English `displayName` per case.
- `SystemWindowFingerprint.swift` declares `SystemWindowFingerprint`, an immutable record (`app`, `titlePattern`, `matchStrategy`, `display`) that identifies a window across restarts, "even though the CGWindowID has changed".
- `SystemWindowInfo.swift` declares `SystemWindowInfo`, an immutable description of one live window "obtained from CGWindowListCopyWindowInfo" (`id`, `app`, `pid`, `title`, `frame`, `display`, `isOnScreen`, `layer`), with `withTitle(_:)` to backfill a title read through Accessibility.
- `SystemWindowSnapshot.swift` declares `SystemWindowSnapshot`, a window's stable identity and saved position inside a context: a stable `id` (not the CGWindowID), an optional live `windowID`, the `fingerprint`, `savedFrame`, `display`, `app`, `title` and `lastSeen`, with `isLive` derived from `windowID`.
- `SystemWindowContext.swift` declares `SystemWindowContext`, a named, colored group of snapshots ("a logical workspace — for example, 'iOS App', 'Backend API', or 'Docs'") with add, remove, look-up and in-place update operations and a `liveWindowCount`.

Consumers named for orientation: `SystemWindowMatcher` builds fingerprints (`fingerprint(window:)`) and scores live windows against them (`score(window:against:)`); `SystemWindowContextManager` owns the list of contexts and enforces cross-context rules; `SystemWindowContextStore` persists contexts as JSON files. Use this ingredient when an app needs a serializable model for grouping another app's windows into named workspaces that survive a restart of either app or the OS.

## Behavioral Requirements

### Shared conformances

- **value-semantics**: All five types MUST be value types (`struct` or `enum`); copying a value MUST NOT share mutable state with the original.
- **sendable**: All five types MUST conform to `Sendable`, so a value MAY cross any concurrency-domain boundary without synchronization.
- **codable**: All five types MUST conform to `Codable` using the compiler-synthesized implementation, so each stored property encodes under a key equal to its Swift name and no custom key mapping, versioning or default-on-missing logic exists.
- **equatable**: All five types MUST conform to `Equatable` using the synthesized implementation, so two values are equal if and only if every stored property is equal (including `lastSeen` and `createdAt` timestamps).
- **computed-not-encoded**: The computed members `MatchStrategy.displayName`, `SystemWindowSnapshot.isLive` and `SystemWindowContext.liveWindowCount` MUST NOT appear in encoded output.
- **optional-omitted**: An optional stored property whose value is `nil` (`SystemWindowSnapshot.windowID`, `SystemWindowContext.lastFocusedWindowID`) MUST be omitted from encoded output, and a missing key MUST decode as `nil` (synthesized `encodeIfPresent` / `decodeIfPresent`).
- **missing-key-throws**: Decoding any of the four struct types MUST throw a `DecodingError` when a non-optional stored property's key is absent; no field has a decode-time default.
- **frame-encoding**: `CGRect` fields (`SystemWindowInfo.frame`, `SystemWindowSnapshot.savedFrame`) MUST encode with CoreGraphics' own `Codable` form, a nested array `[[x, y], [width, height]]`.
- **no-side-effects**: No member of the five types MUST perform file I/O, network access, logging, process launches or notification posting; every operation is a pure computation or an in-memory mutation of the receiver.
- **no-errors**: No member MUST throw or return an error; lookups signal "not found" with `nil` or `false`.

### MatchStrategy

- **strategy-cases**: `MatchStrategy` MUST declare exactly four cases, in this order: `appAndTitleExact`, `appAndTitleSubstring`, `appAndTitleRegex`, `appOnly`.
- **strategy-raw-values**: Each case MUST use its case name as its `String` raw value (`"appAndTitleExact"`, `"appAndTitleSubstring"`, `"appAndTitleRegex"`, `"appOnly"`), and MUST encode and decode as that string.
- **strategy-case-iterable**: `MatchStrategy.allCases` MUST contain exactly 4 elements in declaration order.
- **strategy-unknown-raw**: Decoding a string that is not one of the four raw values MUST throw a `DecodingError.dataCorrupted`; `MatchStrategy(rawValue:)` with such a string MUST return `nil`.
- **display-name-exact**: `displayName` on `appAndTitleExact` MUST return `"Exact"`.
- **display-name-substring**: `displayName` on `appAndTitleSubstring` MUST return `"Substring"`.
- **display-name-regex**: `displayName` on `appAndTitleRegex` MUST return `"Regex"`.
- **display-name-app-only**: `displayName` on `appOnly` MUST return `"App Only"`.
- **strategy-semantics-declared**: Each case's meaning is the contract its doc comment declares, implemented by the consumer `SystemWindowMatcher.score(window:against:)`: `appAndTitleExact` is app plus exact title match, `appAndTitleSubstring` is app plus title containment, `appAndTitleRegex` is app plus a regular-expression test of the live title, and `appOnly` is app alone, ignoring the title. The enum itself MUST NOT perform any matching.

### SystemWindowFingerprint

- **fingerprint-fields**: `SystemWindowFingerprint` MUST store exactly `app: String`, `titlePattern: String`, `matchStrategy: MatchStrategy` and `display: UInt32`.
- **fingerprint-immutable**: Every stored property of `SystemWindowFingerprint` MUST be immutable (`let`); a changed fingerprint is a new value.
- **fingerprint-init-verbatim**: `init(app:titlePattern:matchStrategy:display:)` MUST store each argument unchanged, with no trimming, case folding or validation; all four parameters are required and have no defaults.
- **title-pattern-meaning**: `titlePattern` MUST hold the pattern a heuristic extracted from the title (for example `"MyProject"` from `"MyProject — ContentView.swift"`) or, when no heuristic applies, the full title; per the `appAndTitleRegex` doc comment, for that strategy it MUST hold "the regex source (not a captured value)".
- **regex-not-validated**: A `titlePattern` that is not a compilable regular expression is a value the fingerprint MUST accept; compiling and rejecting it belongs to `SystemWindowMatcher`, which logs the compile error and scores the window 0.
- **display-tie-breaker**: `display` MUST hold the display ID the window was on when fingerprinted; per its doc comment it is "a tie-breaker when multiple candidate windows match" (the consumer adds a 10-point bonus when a live window's `display` equals it).

### SystemWindowInfo

- **info-fields**: `SystemWindowInfo` MUST store exactly `id: UInt32` (the CGWindowID), `app: String`, `pid: Int32`, `title: String`, `frame: CGRect`, `display: UInt32`, `isOnScreen: Bool` and `layer: Int32`, all immutable (`let`).
- **info-identifiable**: `SystemWindowInfo.id` MUST be the `Identifiable` identity, so two infos for the same CGWindowID share an `id` even when other fields differ.
- **info-init-verbatim**: `init(id:app:pid:title:frame:display:isOnScreen:layer:)` MUST store each argument unchanged; all eight parameters are required.
- **info-empty-title**: `title` MUST accept an empty string; per its doc comment the title "may be empty for some windows".
- **with-title-copy**: `withTitle(_:)` MUST return a new `SystemWindowInfo` whose `title` is the argument and whose other seven fields equal the receiver's.
- **with-title-non-mutating**: `withTitle(_:)` MUST NOT modify the receiver.
- **with-title-purpose**: `withTitle(_:)` exists to "backfill titles obtained via Accessibility when CGWindowListCopyWindowInfo omits them (no Screen Recording permission)"; it MUST accept any string, including an empty one, without validation.

### SystemWindowSnapshot

- **snapshot-fields**: `SystemWindowSnapshot` MUST store `id: UUID`, `windowID: UInt32?`, `fingerprint: SystemWindowFingerprint`, `savedFrame: CGRect`, `display: UInt32`, `app: String`, `title: String` and `lastSeen: Date`.
- **snapshot-immutable-identity**: `id`, `fingerprint` and `app` MUST be immutable (`let`); `windowID`, `savedFrame`, `display`, `title` and `lastSeen` MUST be mutable (`var`).
- **snapshot-stable-id**: `id` MUST be a stable identifier that is NOT the CGWindowID and persists across restarts.
- **snapshot-id-default**: `init` MUST generate a fresh random `UUID` for `id` when the caller omits it.
- **snapshot-window-id-default**: `init` MUST default `windowID` to `nil` when the caller omits it.
- **snapshot-last-seen-default**: `init` MUST default `lastSeen` to the current date and time when the caller omits it.
- **snapshot-is-live**: `isLive` MUST return `true` if and only if `windowID` is non-nil.
- **snapshot-dormant**: A snapshot with `windowID == nil` MUST represent the dormant state: per the doc comment, the window "has been closed or the app has been quit".
- **snapshot-display-independent**: `display` (the restore target) and `fingerprint.display` (the display at fingerprint time) MUST be stored independently; changing `display` MUST NOT change `fingerprint.display`.
- **snapshot-app-duplicated**: `app` and `fingerprint.app` MUST be stored independently; the initializer MUST NOT check that they are equal (`SystemWindowContextManager` passes the same live window's `app` to both).

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

## Appearance

Not applicable — this is a set of serializable model value types, not a visual component.

## States

Not applicable — this is a set of serializable model value types, not a visual component.

## Accessibility

Not applicable — this is a set of serializable model value types, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wmcsw-001 | strategy-cases, strategy-case-iterable | `MatchStrategy.allCases` | `[.appAndTitleExact, .appAndTitleSubstring, .appAndTitleRegex, .appOnly]`, count 4 |
| wmcsw-002 | strategy-raw-values | JSON-encode `MatchStrategy.appOnly`; decode `"appAndTitleRegex"` | `"appOnly"`; `.appAndTitleRegex` |
| wmcsw-003 | strategy-unknown-raw | Decode the JSON string `"fuzzy"` as `MatchStrategy`; `MatchStrategy(rawValue: "fuzzy")` | Throws `DecodingError.dataCorrupted`; `nil` |
| wmcsw-004 | display-name-exact, display-name-substring, display-name-regex, display-name-app-only | `displayName` of each case in declaration order | `"Exact"`, `"Substring"`, `"Regex"`, `"App Only"` |
| wmcsw-005 | fingerprint-init-verbatim, fingerprint-fields | `SystemWindowFingerprint(app: "Xcode", titlePattern: " Proj ", matchStrategy: .appAndTitleExact, display: 2)` | `app == "Xcode"`, `titlePattern == " Proj "` (untrimmed), `matchStrategy == .appAndTitleExact`, `display == 2` |
| wmcsw-006 | regex-not-validated, strategy-semantics-declared | Fingerprint with `titlePattern: "JIRA-\\d+"`, `.appAndTitleRegex`; score against window app `"TestApp"`, title `"JIRA-1234 details"`, different display | Fingerprint constructs; `SystemWindowMatcher().score` returns 80 (`SystemWindowMatcherTests.regexFamily`) |
| wmcsw-007 | regex-not-validated | Fingerprint with `titlePattern: "("`, `.appAndTitleRegex` | Fingerprint constructs without error; the matcher scores it 0 and logs the compile error |
| wmcsw-008 | display-tie-breaker | Fingerprint `.appOnly`, app `"Terminal"`, `display: 7`; window app `"Terminal"`, `display: 7` | `SystemWindowMatcher().score` returns 90 (80 + 10 display bonus) (`SystemWindowMatcherTests.displayBonus`) |
| wmcsw-009 | with-title-copy, with-title-non-mutating | `info = SystemWindowInfo(id: 5, app: "Mail", pid: 42, title: "", frame: CGRect(x: 1, y: 2, width: 3, height: 4), display: 1, isOnScreen: true, layer: 0)`; `copy = info.withTitle("Inbox")` | `copy.title == "Inbox"`; `copy.id == 5`, `pid == 42`, `frame`, `display`, `isOnScreen`, `layer` equal `info`'s; `info.title == ""` |
| wmcsw-010 | info-identifiable, equatable | `info` and `info.withTitle("x")` from wmcsw-009 | Same `id`; `info == info.withTitle("x")` is `false` |
| wmcsw-011 | snapshot-id-default, snapshot-window-id-default, snapshot-is-live | `SystemWindowSnapshot(fingerprint: fp, savedFrame: .zero, display: 0, app: "Mail", title: "")` twice | Two different `id` values; `windowID == nil`; `isLive == false` |
| wmcsw-012 | snapshot-is-live | Snapshot with `windowID: 9`; then set `windowID = nil` | `isLive == true`, then `false` |
| wmcsw-013 | snapshot-display-independent | Snapshot with `fingerprint.display == 1`, `display: 1`; set `display = 3` | `display == 3`; `fingerprint.display == 1` |
| wmcsw-014 | context-init-defaults | `SystemWindowContext(name: "Docs")` | `color == "#007AFF"`, `windowSnapshots.isEmpty`, `lastFocusedWindowID == nil`, `createdAt` within 1 s of now, non-nil `id` |
| wmcsw-015 | add-window-append | Empty context; `addWindow(a)`, `addWindow(b)` (distinct `id`s) | `windowSnapshots.map(\.id) == [a.id, b.id]` |
| wmcsw-016 | add-window-replace, add-window-keeps-focus | Context `[a, b]`, `lastFocusedWindowID = a.id`; `addWindow(a')` where `a'.id == a.id`, `a'.title == "new"` | Count 2, order `[a', b]`, `windowSnapshots[0].title == "new"`, `lastFocusedWindowID == a.id` |
| wmcsw-017 | add-window-no-window-id-dedupe | Empty context; add `a` and `b` with distinct `id`s, both `windowID: 7` | Count 2 |
| wmcsw-018 | remove-by-id, remove-by-id-clears-focus | Context `[a, b]`, `lastFocusedWindowID = a.id`; `removeWindow(id: a.id)` | Returns `a`; `windowSnapshots == [b]`; `lastFocusedWindowID == nil` |
| wmcsw-019 | remove-by-id-missing | Context `[a]`, `lastFocusedWindowID = a.id`; `removeWindow(id: UUID())` | Returns `nil`; context unchanged |
| wmcsw-020 | remove-by-id-clears-focus | Context `[a, b]`, `lastFocusedWindowID = b.id`; `removeWindow(id: a.id)` | `lastFocusedWindowID == b.id` |
| wmcsw-021 | remove-by-window-id, remove-by-window-id-clears-focus | Context `[a (windowID 7), b (windowID 7)]`, `lastFocusedWindowID = a.id`; `removeWindow(windowID: 7)` | Returns `a`; `windowSnapshots == [b]`; `lastFocusedWindowID == nil` |
| wmcsw-022 | remove-by-window-id-missing | Context `[a (windowID nil)]`; `removeWindow(windowID: 0)` | Returns `nil`; context unchanged |
| wmcsw-023 | snapshot-lookup | Context `[a, b]`; `snapshot(id: b.id)`; `snapshot(id: UUID())` | `b`; `nil` |
| wmcsw-024 | update-by-id, update-scope | Context `[a]`; `updateSnapshot(id: a.id) { $0.title = "T"; $0.windowID = 3 }` | Returns `true`; `windowSnapshots[0].title == "T"`, `windowID == 3`, `id == a.id` |
| wmcsw-025 | update-by-id-missing | Context `[a]`; `updateSnapshot(id: UUID()) { _ in called = true }` | Returns `false`; `called == false` |
| wmcsw-026 | update-by-window-id | Context `[a (windowID 4)]`; `updateSnapshot(windowID: 4) { $0.savedFrame = CGRect(x: 0, y: 0, width: 10, height: 10) }`; then `updateSnapshot(windowID: 5) { _ in }` | `true` and frame updated; then `false` |
| wmcsw-027 | live-window-count | Context with snapshots whose `windowID`s are `1`, `nil`, `2` | `liveWindowCount == 2` |
| wmcsw-028 | codable, optional-omitted, computed-not-encoded | Encode a snapshot with `windowID == nil` using a `.sortedKeys` `JSONEncoder` | Keys are `app`, `display`, `fingerprint`, `id`, `lastSeen`, `savedFrame`, `title`; no `windowID` and no `isLive` key |
| wmcsw-029 | frame-encoding | Encode `SystemWindowInfo` with `frame: CGRect(x: 1, y: 2, width: 3, height: 4)` | `"frame":[[1,2],[3,4]]` |
| wmcsw-030 | missing-key-throws | Decode `SystemWindowFingerprint` from `{"app":"Xcode","titlePattern":"P","matchStrategy":"appOnly"}` | Throws `DecodingError.keyNotFound` for `display` |
| wmcsw-031 | codable, equatable | Encode then decode a `SystemWindowContext` with two snapshots using the same date strategy both ways | Decoded value `==` original (dates at a precision the strategy preserves) |
| wmcsw-032 | no-side-effects, no-errors | Call every public member of the five types | None throws; no file, network, log or process activity |

## Edge Cases

- **Empty title**: a window with `title == ""` — `SystemWindowInfo` MUST accept it (info-empty-title); the consumer's fallback fingerprint then uses `.appOnly` with an empty `titlePattern`, as `SystemWindowMatcher.fingerprint(window:)` does.
- **Empty or whitespace pattern**: `titlePattern` of `""` or `" "` — `SystemWindowFingerprint` MUST store it verbatim; whether it matches is the matcher's decision (an empty regex scores 0, a pattern shorter than the minimum substring length scores 0 unless it is an exact match).
- **Invalid regex source**: `titlePattern` that does not compile, with `.appAndTitleRegex` — the fingerprint MUST accept it; the matcher logs the error and returns no match, so the error is reported, not swallowed.
- **Empty context**: `windowSnapshots == []` — `liveWindowCount` MUST return `0`, `snapshot(id:)` MUST return `nil`, both `removeWindow` overloads MUST return `nil`, and both `updateSnapshot` overloads MUST return `false`.
- **All dormant**: every snapshot has `windowID == nil` — `liveWindowCount` MUST return `0` and `removeWindow(windowID:)` / `updateSnapshot(windowID:)` MUST match nothing for any argument.
- **Duplicate live window IDs in one context**: reachable only by calling `addWindow(_:)` directly with distinct snapshot `id`s — the by-`windowID` operations MUST act on the first match in array order only (remove-by-window-id); the managing layer prevents this state.
- **Duplicate snapshot IDs**: reachable only by constructing `windowSnapshots` directly through `init` or the mutable property — `addWindow`, `removeWindow(id:)`, `snapshot(id:)` and `updateSnapshot(id:)` MUST act on the first match only.
- **Stale focus**: `lastFocusedWindowID` set to an ID not in `windowSnapshots` — the type MUST keep it (focus-not-validated); consumers resolving it get `nil` from `snapshot(id:)`.
- **Focus cleared only by removal**: replacing the focused snapshot through `addWindow(_:)` or making it dormant through `updateSnapshot` MUST leave `lastFocusedWindowID` unchanged.
- **Boundary values**: `UInt32` window and display IDs of `0` and `UInt32.max`, `pid` of `0` or negative, `layer` of any `Int32` and a zero or negative-size `CGRect` MUST be stored unchanged; none of the types range-checks numeric fields.
- **Malformed color**: `color` of `""`, `"red"` or `"#GGG"` MUST be stored verbatim; interpreting it is the renderer's job, and the doc comment documents the expected `#`-prefixed hex form as the caller's precondition.
- **Unknown strategy on disk**: persisted JSON with a `matchStrategy` string not among the four raw values — decoding MUST throw, failing the whole enclosing context's decode (strategy-unknown-raw); `SystemWindowContextStore` wraps that failure in its "Failed to decode data at <path>" error.
- **Older or newer schema**: JSON missing a non-optional key MUST fail to decode (missing-key-throws); extra unknown keys MUST be ignored by the synthesized decoder.
- **Concurrent access**: all types are `Sendable` values with no shared mutable state; each mutation acts on the caller's own copy, and simultaneous access to one variable is an exclusivity violation caught by Swift, not a data race the type must order.
- **Error states**: none of the operations can fail; "not found" is reported as `nil` or `false` and the only throwing paths are `Codable` decoding, which surfaces the `DecodingError` to the caller.
- **Cancellation and timeouts**: not applicable; every operation is a synchronous in-memory computation with nothing to cancel.
- **Offline or disconnected state**: not applicable; the types perform no network access.

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

## Deep Linking

Not applicable: none of the five files defines a URL scheme, route or navigation entry point; they are model types only.

## Localization

`MatchStrategy.displayName` returns hardcoded English literals with no string-catalog lookup; its doc comment places it beside the enum so "any host rendering a strategy picker reads the label from the model".

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `Exact` | `displayName` for `appAndTitleExact`, a strategy-picker label |
| (none; literal) | `Substring` | `displayName` for `appAndTitleSubstring` |
| (none; literal) | `Regex` | `displayName` for `appAndTitleRegex` |
| (none; literal) | `App Only` | `displayName` for `appOnly` |

The example context names in doc comments ("iOS App", "Backend API", "Docs") are documentation, not strings the code emits.

## Accessibility Options

Not applicable: the types have no visual surface, so they respond to no Reduce Motion, Increase Contrast or Differentiate Without Color setting.

## Feature Flags

Not applicable: the source declares no feature-flag key and gates no behavior on one.

## Analytics

Not applicable: none of the five files emits analytics events.

## Privacy

- **Data collected**: The types hold window metadata about other apps: owning app name, process ID, window title, frame and display. Window titles can contain document names, web page titles or message subjects, so they are potentially personal.
- **Storage**: The types store nothing themselves; in memory only. `SystemWindowContextStore` persists contexts, including each snapshot's `title` and `fingerprint.titlePattern`, as JSON files on local disk.
- **Transmission**: The types never transmit data; no member performs network access.
- **Retention**: A snapshot's `title` and fingerprint stay in the context until `removeWindow` removes the snapshot; dormant snapshots are kept, not expired, and nothing in these types deletes data by age.

## Logging

Not applicable: none of the five files contains a `Logger`, `os_log` or `print` call; the only related log line is the consumer `SystemWindowMatcher`'s error for an invalid regex `titlePattern`.

## Platform Notes

- **SwiftUI**: No SwiftUI code in the source. A SwiftUI host keeps an array of `SystemWindowContext` in an `@Observable` model and drives a strategy `Picker` from `MatchStrategy.allCases` with `displayName` labels; mutations go through the same `mutating` methods on the model's stored copy.
- **Compose**: Port each struct to a Kotlin `data class` (immutable `val` for the Swift `let` fields; `copy(...)` stands in for both `withTitle` and `mutating` updates) and `MatchStrategy` to an `enum class` with a `displayName` property sourced from `strings.xml`. Use `kotlinx.serialization` with `@Serializable`, `java.util.UUID` or a `String` ID, `kotlinx.datetime.Instant` for dates, and a small `@Serializable` rect class encoded as `[[x,y],[w,h]]` to stay wire-compatible. Android has no API to enumerate other apps' windows, so `SystemWindowInfo` is only meaningful as a data model there.
- **React/Web**: Model the enum as a string-literal union `'appAndTitleExact' | 'appAndTitleSubstring' | 'appAndTitleRegex' | 'appOnly'` and the structs as readonly TypeScript interfaces, with context operations as pure functions returning a new context (for example `addWindow(ctx, snap): SystemWindowContext`) so the "first match by id, replace in place" rule is explicit. Use `crypto.randomUUID()` for IDs, ISO strings for dates, and validate on `JSON.parse` with a schema library (for example zod) to reproduce missing-key-throws and strategy-unknown-raw. Browsers cannot list OS windows.
- **AppKit / UIKit**: This is the source, in `packages/apple/AgenticToolkit/Core/SystemWindows/`: `MatchStrategy.swift`, `SystemWindowFingerprint.swift`, `SystemWindowInfo.swift`, `SystemWindowSnapshot.swift` and `SystemWindowContext.swift`. They import only Foundation and CoreGraphics (for `CGRect`) and build for macOS and iOS; the CGWindowID and display ID values come from macOS `CGWindowListCopyWindowInfo` and `CGDirectDisplayID` in the macOS-only consumers, so on iOS the types are data models only.
- **WinUI 3**: Port each struct to a C# `record` (or `readonly record struct` for `SystemWindowFingerprint` and `SystemWindowInfo`) with `init`-only properties for the Swift `let` fields; `withTitle` becomes a `with { Title = newTitle }` expression. Map `id: UInt32` to the window's `HWND` (store as `long`/`nint` from `EnumWindows`), `app` to the process name from `Process.GetProcessById(pid)`, `title` to `GetWindowText`, `frame` to `GetWindowRect` as a `Windows.Foundation.Rect` or `RECT`, `display` to the `HMONITOR` from `MonitorFromWindow`, and `isOnScreen` to `IsWindowVisible` plus not `IsIconic`; Windows windows have no layer number, so `layer` needs a stand-in (Z-order index or `WS_EX_TOPMOST`). `MatchStrategy` becomes a C# `enum` serialized with `JsonStringEnumConverter` so names match the Swift raw values, and `displayName` moves to `.resw` resources through `ResourceLoader`. Serialize with `System.Text.Json`, setting `JsonIgnoreCondition.WhenWritingNull` to match optional-omitted and `required` members or `JsonRequired` to match missing-key-throws; write a custom `JsonConverter<Rect>` for the `[[x,y],[w,h]]` form. `SystemWindowContext` holds its snapshots in a `List<T>` (or `ObservableCollection<T>` when bound to UI) and becomes a class raising `INotifyPropertyChanged`; that is a reference type, so copy it explicitly where Swift relies on value semantics, and marshal edits to the UI thread through `DispatcherQueue` instead of relying on `Sendable`. Store files under `Windows.Storage.ApplicationData.Current.LocalFolder` in a packaged app, or under `%LOCALAPPDATA%` when unpackaged.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/SystemWindows/MatchStrategy.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SystemWindows/SystemWindowContext.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SystemWindows/SystemWindowFingerprint.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SystemWindows/SystemWindowInfo.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SystemWindows/SystemWindowSnapshot.swift` |

## Design Decisions

**Decision**: A snapshot's stable `id` is a `UUID` separate from the CGWindowID, and the CGWindowID is optional.
**Rationale**: Per the `SystemWindowSnapshot` doc comment, the CGWindowID "may become stale after restart"; a separate stable ID lets a context keep a dormant snapshot and re-attach a new live window to it through the fingerprint.
**Approved**: pending

**Decision**: `SystemWindowFingerprint.titlePattern` holds regex source, not a captured value, for `appAndTitleRegex`.
**Rationale**: Per the `MatchStrategy.appAndTitleRegex` doc comment, storing the source means "every title in the same family re-matches after restart" (for example every `JIRA-<n>` window).
**Approved**: pending

**Decision**: The snapshot stores `display` and `app` beside the fingerprint's own copies.
**Rationale**: `display` is the restore target and changes when the user moves the window, while `fingerprint.display` records where it was first seen for tie-breaking; `app` is duplicated for direct access and nothing enforces equality.
**Approved**: pending

**Decision**: `SystemWindowContext` does not enforce unique `windowID`s or a valid `lastFocusedWindowID`.
**Rationale**: The value type stays a plain container; cross-context rules (a window in at most one context) need the whole context list, so `SystemWindowContextManager` enforces them.
**Approved**: pending

**Decision**: `MatchStrategy.displayName` lives on the model and returns English literals.
**Rationale**: The doc comment keeps it beside the enum, like `CustomMatchMode.displayName`, so hosts read labels without reaching into the macOS UI layer; the strings are not externalized, which is recorded as a failed check under Compliance.
**Approved**: pending

**Decision**: The types rely on synthesized `Codable` with no versioning.
**Rationale**: Synthesis keeps the wire format equal to the Swift property names; the cost is that a missing key or unknown strategy fails the whole decode, which the store reports as a decode error.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

`separation-of-concerns` passes because the five files hold only data shapes and in-memory collection edits, while fingerprinting and scoring live in `SystemWindowMatcher`, cross-context rules in `SystemWindowContextManager` and file persistence in `SystemWindowContextStore`. `unit-test-coverage` is partial: `SystemWindowMatcherTests` constructs `SystemWindowInfo`, `SystemWindowFingerprint` and `SystemWindowSnapshot` and exercises every `MatchStrategy` through the matcher, and `SystemWindowContextManagerTests` exercises contexts through the manager, but no test targets `SystemWindowContext`'s add, remove, update and focus-clearing operations, `withTitle(_:)`, `displayName` or the `Codable` round trip directly. `no-hardcoded-strings` fails because `displayName` returns English literals meant for a picker. `data-integrity` is partial because decoding is strict (a missing key or unknown strategy throws rather than silently defaulting), but the context accepts duplicate `windowID`s, a stale `lastFocusedWindowID` and an unparsed `color` string, leaving those invariants to the managing layer.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
