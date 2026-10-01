---
id: d4b4359e-e9c8-439c-abcf-309fcc419348
title: Window Context Model
domain: agentictoolkit://cookbook/system/system-windows/window-context-model
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The value types that model window contexts — match strategy, window
  fingerprint, window info, window snapshot and window context — and the
  operations they support for grouping windows into named workspaces that
  survive a restart.'
platforms:
- swift
- macos
tags:
- window-management
- system-windows
- window-matching
- window-contexts
depends-on: []
related:
- agentictoolkit://cookbook/system/system-windows/window-explorer-view
references:
- https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo
approved-by: ''
approved-date: ''
---

# Window Context Model

## Overview

The core data model of the system window contexts feature: five value types that carry no behavior beyond in-memory collection edits; matching, persistence and window movement live in their consumers.

- **Match strategy** is a string-backed set of named strategies (an exact app-and-title match, an app-and-title substring match, an app-and-title regular-expression match, and an app-only match) that says how strictly a fingerprint must match a live window, plus a display name for each strategy.
- **Window fingerprint** is an immutable record (app, title pattern, match strategy, display) that identifies a window across restarts, even though its live window identifier has changed.
- **Window info** is an immutable description of one live window obtained from the system's window list (id, app, process id, title, frame, display, on-screen flag, layer), with an operation to backfill a title read through the accessibility layer.
- **Window snapshot** is a window's stable identity and saved position inside a context: a stable id (not the live window identifier), an optional live window identifier, the fingerprint, saved frame, display, app, title and last-seen timestamp, with a live flag derived from the window identifier.
- **Window context** is a named, colored group of snapshots (a logical workspace — for example, "iOS App", "Backend API", or "Docs") with add, remove, look-up and in-place update operations and a live-window count.

Consumers named for orientation: the window matcher builds fingerprints and scores live windows against them; the context manager owns the list of contexts and enforces cross-context rules; the context store persists contexts as JSON files. Use this ingredient when an app needs a serializable model for grouping another app's windows into named workspaces that survive a restart of either app or the OS.

## Behavioral Requirements

### Shared conformances

- **value-semantics**: All five types MUST be value types; copying a value MUST NOT share mutable state with the original.
- **concurrency-safe-by-value**: All five types MUST be safe to pass across concurrent execution contexts without synchronization, since each is an immutable-or-copied value with no shared mutable state.
- **serializable-by-field-name**: All five types MUST be serializable to and from a structured format, with each stored field encoding under a key equal to its field name, and no custom key mapping, versioning or default-on-missing logic.
- **value-equality**: All five types MUST support equality comparison, such that two values are equal if and only if every stored field is equal (including the last-seen and created-at timestamps).
- **computed-not-encoded**: The derived values — the display name on match strategy, the live flag on window snapshot, and the live-window count on window context — MUST NOT appear in encoded output.
- **optional-omitted**: An optional stored field whose value is absent (the window identifier on window snapshot, the last-focused window identifier on window context) MUST be omitted from encoded output, and a missing key MUST decode as absent.
- **missing-key-throws**: Decoding any of the four record types MUST fail with a decoding error when a required field's key is absent; no field has a decode-time default.
- **frame-encoding**: Rectangle fields (the frame on window info, the saved frame on window snapshot) MUST encode as a nested array `[[x, y], [width, height]]`.
- **no-side-effects**: No operation of the five types MUST perform file I/O, network access, logging, process launches or notification posting; every operation is a pure computation or an in-memory mutation of the value itself.
- **no-errors**: No operation MUST throw or return an error; lookups signal "not found" with an absent value or `false`.

### Match Strategy

- **strategy-cases**: Match strategy MUST declare exactly four values, in this order: `appAndTitleExact`, `appAndTitleSubstring`, `appAndTitleRegex`, `appOnly`.
- **strategy-raw-values**: Each value MUST use its name as its string raw form (`"appAndTitleExact"`, `"appAndTitleSubstring"`, `"appAndTitleRegex"`, `"appOnly"`), and MUST encode and decode as that string.
- **strategy-value-list**: The complete list of match-strategy values MUST contain exactly 4 elements, in declaration order.
- **strategy-unknown-raw**: Decoding a string that is not one of the four raw values MUST fail with a data-corrupted decoding error; constructing a match-strategy value from such a string MUST return no value.
- **display-name-exact**: The display name for `appAndTitleExact` MUST be `"Exact"`.
- **display-name-substring**: The display name for `appAndTitleSubstring` MUST be `"Substring"`.
- **display-name-regex**: The display name for `appAndTitleRegex` MUST be `"Regex"`.
- **display-name-app-only**: The display name for `appOnly` MUST be `"App Only"`.
- **strategy-semantics-declared**: Each value's meaning is a contract implemented by the window matcher's scoring operation: `appAndTitleExact` is app plus exact title match, `appAndTitleSubstring` is app plus title containment, `appAndTitleRegex` is app plus a regular-expression test of the live title, and `appOnly` is app alone, ignoring the title. Match strategy itself MUST NOT perform any matching.

### Window Fingerprint

- **fingerprint-fields**: Window fingerprint MUST store exactly `app`, `titlePattern`, `matchStrategy` and `display`, respectively an app name, a title pattern, a match strategy and a display identifier.
- **fingerprint-immutable**: Every stored field of window fingerprint MUST be immutable; a changed fingerprint is a new value.
- **fingerprint-init-verbatim**: Constructing a window fingerprint MUST store each argument unchanged, with no trimming, case folding or validation; all four fields are required and have no defaults.
- **title-pattern-meaning**: `titlePattern` MUST hold the pattern a heuristic extracted from the title (for example `"MyProject"` from `"MyProject — Notes.md"`) or, when no heuristic applies, the full title; for the `appAndTitleRegex` strategy it MUST hold the regular-expression source, not a captured value.
- **regex-not-validated**: A `titlePattern` that is not a compilable regular expression is a value the fingerprint MUST accept; compiling and rejecting it belongs to the window matcher, which logs the compile error and scores the window 0.
- **display-tie-breaker**: `display` MUST hold the display identifier the window was on when fingerprinted; it is a tie-breaker when multiple candidate windows match (the window matcher adds a 10-point bonus when a live window's `display` equals it).

### Window Info

- **info-fields**: Window info MUST store exactly `id` (the window identifier assigned by the system), `app`, `pid` (the owning process identifier), `title`, `frame`, `display`, `isOnScreen` and `layer`, all immutable.
- **info-identity**: Window info's `id` MUST serve as its identity, so two info values for the same window share an `id` even when other fields differ.
- **info-init-verbatim**: Constructing a window info value MUST store each argument unchanged; all eight fields are required.
- **info-empty-title**: `title` MUST accept an empty string; the title may be empty for some windows.
- **with-title-copy**: The title-backfill operation MUST return a new window info value whose `title` is the argument and whose other seven fields equal the original's.
- **with-title-non-mutating**: The title-backfill operation MUST NOT modify the original value.
- **with-title-purpose**: The title-backfill operation exists to backfill titles obtained through the accessibility layer when the system's window list omits them because the screen-capture permission has not been granted; it MUST accept any string, including an empty one, without validation.

### Window Snapshot

- **snapshot-fields**: Window snapshot MUST store `id` (a unique identifier), `windowID` (an optional live window identifier), `fingerprint`, `savedFrame`, `display`, `app`, `title` and `lastSeen`.
- **snapshot-immutable-identity**: `id`, `fingerprint` and `app` MUST be immutable; `windowID`, `savedFrame`, `display`, `title` and `lastSeen` MUST be mutable.
- **snapshot-stable-id**: `id` MUST be a stable identifier that is not the live window identifier and persists across restarts.
- **snapshot-id-default**: Constructing a window snapshot MUST generate a fresh random unique identifier for `id` when the caller omits it.
- **snapshot-window-id-default**: Constructing a window snapshot MUST default `windowID` to absent when the caller omits it.
- **snapshot-last-seen-default**: Constructing a window snapshot MUST default `lastSeen` to the current date and time when the caller omits it.
- **snapshot-is-live**: The live flag MUST be `true` if and only if `windowID` is present.
- **snapshot-dormant**: A snapshot with `windowID` absent MUST represent the dormant state: the window has been closed or the app has quit.
- **snapshot-display-independent**: `display` (the restore target) and the fingerprint's own `display` (the display at fingerprint time) MUST be stored independently; changing the snapshot's `display` MUST NOT change the fingerprint's `display`.
- **snapshot-app-duplicated**: `app` and the fingerprint's own `app` MUST be stored independently; construction MUST NOT check that they are equal (the context manager passes the same live window's `app` to both).

### Window Context

- **context-fields**: Window context MUST store `id`, `name`, `color`, `windowSnapshots` (a list of window snapshots), `lastFocusedWindowID` (an optional identifier) and `createdAt`.
- **context-immutable-identity**: `id` and `createdAt` MUST be immutable; `name`, `color`, `windowSnapshots` and `lastFocusedWindowID` MUST be mutable.
- **context-init-defaults**: Constructing a window context MUST default `id` to a fresh unique identifier, `color` to `"#007AFF"`, `windowSnapshots` to an empty list, `lastFocusedWindowID` to absent and `createdAt` to the current date and time; `name` is required.
- **context-color-format**: `color` is a caller-supplied hex string that includes the leading `#` (for example `"#FF5733"`); window context MUST store it verbatim without parsing or validating it.
- **context-name-verbatim**: `name` MUST be stored verbatim; window context MUST NOT reject an empty or duplicate name.
- **add-window-append**: Adding a window snapshot MUST append it to the end of `windowSnapshots` when no existing snapshot has the same `id`.
- **add-window-replace**: Adding a window snapshot MUST replace, at the same position, the first existing snapshot whose `id` equals the new one's `id`, leaving the list's count and order unchanged.
- **add-window-no-window-id-dedupe**: Adding a window snapshot MUST NOT check `windowID`; two snapshots with different `id` values and the same `windowID` MAY coexist in one context. Uniqueness of a live window across and within contexts is enforced by the caller, the context manager's add-window operation, which reports an already-assigned error for another context and updates the existing snapshot for the same one.
- **add-window-keeps-focus**: Adding a window snapshot MUST NOT change `lastFocusedWindowID`.
- **remove-by-id**: Removing a window snapshot by `id` MUST remove the first snapshot whose `id` equals the argument and return it.
- **remove-by-id-missing**: Removing a window snapshot by `id` MUST return no value and leave the context unchanged when no snapshot has that `id`.
- **remove-by-id-clears-focus**: Removing a window snapshot by `id` MUST clear `lastFocusedWindowID` when it equals the removed snapshot's `id`, and MUST leave it unchanged otherwise.
- **remove-by-window-id**: Removing a window snapshot by `windowID` MUST remove the first snapshot (in list order) whose `windowID` equals the argument and return it; later snapshots with the same `windowID` MUST remain.
- **remove-by-window-id-missing**: Removing a window snapshot by `windowID` MUST return no value and leave the context unchanged when no snapshot has that `windowID`; a dormant snapshot (`windowID` absent) MUST never match.
- **remove-by-window-id-clears-focus**: Removing a window snapshot by `windowID` MUST clear `lastFocusedWindowID` when it equals the removed snapshot's `id`.
- **remove-discardable**: Both remove operations MUST be usable without the caller using the returned value.
- **snapshot-lookup**: Looking up a snapshot by `id` MUST return the first snapshot whose `id` equals the argument, or no value when none does, without mutating the context.
- **update-by-id**: Updating a snapshot by `id` MUST invoke the update closure exactly once with the first snapshot whose `id` matches, allow it to modify that snapshot directly, write the changes back in place, and return `true`.
- **update-by-id-missing**: Updating a snapshot by `id` MUST return `false` without invoking the update closure when no snapshot has that `id`.
- **update-by-window-id**: Updating a snapshot by `windowID` MUST invoke the update closure exactly once with the first snapshot whose `windowID` matches, write the changes back in place, and return `true`; it MUST return `false` without invoking the closure when none matches.
- **update-scope**: The update closure MUST be able to change only a snapshot's mutable fields (`windowID`, `savedFrame`, `display`, `title`, `lastSeen`); `id`, `fingerprint` and `app` are immutable, and updating a snapshot MUST NOT reorder `windowSnapshots` or touch `lastFocusedWindowID`.
- **update-closure-synchronous**: The update closure MUST run synchronously; it completes before the update operation returns.
- **live-window-count**: The live-window count MUST return the number of snapshots whose live flag is `true`.
- **focus-not-validated**: Window context MUST NOT check that `lastFocusedWindowID` names a snapshot in `windowSnapshots`; only the two remove operations clear it.

### Concurrency and persistence

- **concurrency-by-value**: The types MUST NOT carry any built-in synchronization mechanism (locks or similar); a window context is mutated by producing an updated copy held by a single owner, and preventing concurrent mutation of one stored value is the caller's and the platform's responsibility, not the type's.
- **persistence-external**: The types MUST NOT persist themselves. The context store encodes a context as pretty-printed JSON with keys in sorted order and dates in ISO-8601 form, and decodes with a matching ISO-8601 date format; without that configuration, date fields would encode as a platform-specific numeric offset instead.

## Appearance

Not applicable — this is a set of serializable model value types, not a visual component.

## States

Not applicable — this is a set of serializable model value types, not a visual component.

## Accessibility

Not applicable — this is a set of serializable model value types, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wmcsw-001 | strategy-cases, strategy-value-list | The complete list of match-strategy values | `appAndTitleExact`, `appAndTitleSubstring`, `appAndTitleRegex`, `appOnly`, in that order; count 4 |
| wmcsw-002 | strategy-raw-values | Encode the match-strategy value `appOnly` to JSON; decode the JSON string `"appAndTitleRegex"` | `"appOnly"`; the `appAndTitleRegex` value |
| wmcsw-003 | strategy-unknown-raw | Decode the JSON string `"fuzzy"` as a match-strategy value; construct a match-strategy value from the raw string `"fuzzy"` | Fails with a data-corrupted decoding error; no value |
| wmcsw-004 | display-name-exact, display-name-substring, display-name-regex, display-name-app-only | The display name of each match-strategy value, in declaration order | `"Exact"`, `"Substring"`, `"Regex"`, `"App Only"` |
| wmcsw-005 | fingerprint-init-verbatim, fingerprint-fields | Construct a window fingerprint with `app: "Xcode"`, `titlePattern: " Proj "`, `matchStrategy: appAndTitleExact`, `display: 2` | `app` is `"Xcode"`, `titlePattern` is `" Proj "` (untrimmed), `matchStrategy` is `appAndTitleExact`, `display` is `2` |
| wmcsw-006 | regex-not-validated, strategy-semantics-declared | Fingerprint with `titlePattern: "JIRA-\\d+"`, `appAndTitleRegex`; score against window app `"TestApp"`, title `"JIRA-1234 details"`, different display | Fingerprint constructs; the window matcher's score returns 80 |
| wmcsw-007 | regex-not-validated | Fingerprint with `titlePattern: "("`, `appAndTitleRegex` | Fingerprint constructs without error; the matcher scores it 0 and logs the compile error |
| wmcsw-008 | display-tie-breaker | Fingerprint `appOnly`, app `"Terminal"`, `display: 7`; window app `"Terminal"`, `display: 7` | The window matcher's score returns 90 (80 + 10 display bonus) |
| wmcsw-009 | with-title-copy, with-title-non-mutating | A window info value with `id: 5`, `app: "Mail"`, `pid: 42`, `title: ""`, `frame: [[1,2],[3,4]]`, `display: 1`, `isOnScreen: true`, `layer: 0`; back-fill its title with `"Inbox"` | The result's `title` is `"Inbox"`; its `id`, `pid`, `frame`, `display`, `isOnScreen` and `layer` equal the original's; the original's `title` remains `""` |
| wmcsw-010 | info-identity, value-equality | The window info value from wmcsw-009 and its title-backfilled copy with `"x"` | Same `id`; the two values are not equal |
| wmcsw-011 | snapshot-id-default, snapshot-window-id-default, snapshot-is-live | Construct a window snapshot with `fingerprint: fp`, `savedFrame` zero, `display: 0`, `app: "Mail"`, `title: ""`, twice | Two different `id` values; `windowID` absent; live flag `false` |
| wmcsw-012 | snapshot-is-live | Snapshot with `windowID: 9`; then set `windowID` to absent | Live flag `true`, then `false` |
| wmcsw-013 | snapshot-display-independent | Snapshot with fingerprint `display` `1`, snapshot `display: 1`; set snapshot `display = 3` | Snapshot `display` is `3`; fingerprint `display` remains `1` |
| wmcsw-014 | context-init-defaults | Construct a window context with `name: "Docs"` | `color` is `"#007AFF"`, `windowSnapshots` is empty, `lastFocusedWindowID` is absent, `createdAt` within 1 s of now, a present `id` |
| wmcsw-015 | add-window-append | Empty context; add snapshot `a`, then add snapshot `b` (distinct `id`s) | `windowSnapshots`' ids, in order, are `[a.id, b.id]` |
| wmcsw-016 | add-window-replace, add-window-keeps-focus | Context `[a, b]`, `lastFocusedWindowID` is `a.id`; add an updated snapshot `a'` whose `id` equals `a.id` and whose `title` is `"new"` | Count 2, order `[a', b]`, first snapshot's `title` is `"new"`, `lastFocusedWindowID` remains `a.id` |
| wmcsw-017 | add-window-no-window-id-dedupe | Empty context; add `a` and `b` with distinct `id`s, both `windowID: 7` | Count 2 |
| wmcsw-018 | remove-by-id, remove-by-id-clears-focus | Context `[a, b]`, `lastFocusedWindowID` is `a.id`; remove the snapshot with `id: a.id` | Returns `a`; `windowSnapshots` is `[b]`; `lastFocusedWindowID` is absent |
| wmcsw-019 | remove-by-id-missing | Context `[a]`, `lastFocusedWindowID` is `a.id`; remove the snapshot with a freshly generated `id` not in the context | Returns no value; context unchanged |
| wmcsw-020 | remove-by-id-clears-focus | Context `[a, b]`, `lastFocusedWindowID` is `b.id`; remove the snapshot with `id: a.id` | `lastFocusedWindowID` remains `b.id` |
| wmcsw-021 | remove-by-window-id, remove-by-window-id-clears-focus | Context `[a (windowID 7), b (windowID 7)]`, `lastFocusedWindowID` is `a.id`; remove the snapshot with `windowID: 7` | Returns `a`; `windowSnapshots` is `[b]`; `lastFocusedWindowID` is absent |
| wmcsw-022 | remove-by-window-id-missing | Context `[a (windowID absent)]`; remove the snapshot with `windowID: 0` | Returns no value; context unchanged |
| wmcsw-023 | snapshot-lookup | Context `[a, b]`; look up the snapshot with `id: b.id`; look up the snapshot with a freshly generated `id` not in the context | `b`; no value |
| wmcsw-024 | update-by-id, update-scope | Context `[a]`; update the snapshot with `id: a.id`, setting `title` to `"T"` and `windowID` to `3` | Returns `true`; the updated snapshot's `title` is `"T"`, `windowID` is `3`, `id` remains `a.id` |
| wmcsw-025 | update-by-id-missing | Context `[a]`; update the snapshot with a freshly generated `id` not in the context, recording whether the update ran | Returns `false`; the update never ran |
| wmcsw-026 | update-by-window-id | Context `[a (windowID 4)]`; update the snapshot with `windowID: 4`, setting `savedFrame` to `[[0,0],[10,10]]`; then update the snapshot with `windowID: 5` | First returns `true` with the frame updated; second returns `false` |
| wmcsw-027 | live-window-count | Context with snapshots whose `windowID`s are `1`, absent, `2` | Live-window count is `2` |
| wmcsw-028 | serializable-by-field-name, optional-omitted, computed-not-encoded | Encode a snapshot whose `windowID` is absent, with keys in sorted order | Keys are `app`, `display`, `fingerprint`, `id`, `lastSeen`, `savedFrame`, `title`; no `windowID` key and no live-flag key |
| wmcsw-029 | frame-encoding | Encode a window info value whose frame has origin `(1, 2)` and size `(3, 4)` | `"frame":[[1,2],[3,4]]` |
| wmcsw-030 | missing-key-throws | Decode a window fingerprint from `{"app":"Xcode","titlePattern":"P","matchStrategy":"appOnly"}` | Fails with a key-not-found decoding error for `display` |
| wmcsw-031 | serializable-by-field-name, value-equality | Encode then decode a window context with two snapshots, using the same date format both ways | Decoded value equals the original (dates at a precision the format preserves) |
| wmcsw-032 | no-side-effects, no-errors | Call every public operation of the five types | None throws; no file, network, log or process activity |

## Edge Cases

- **Empty title**: a window with `title` equal to `""` — window info MUST accept it (info-empty-title); the window matcher's fallback fingerprint then uses `appOnly` with an empty `titlePattern`.
- **Empty or whitespace pattern**: `titlePattern` of `""` or `" "` — window fingerprint MUST store it verbatim; whether it matches is the matcher's decision (an empty regex scores 0, a pattern shorter than the minimum substring length scores 0 unless it is an exact match).
- **Invalid regex source**: `titlePattern` that does not compile, with `appAndTitleRegex` — the fingerprint MUST accept it; the matcher logs the error and returns no match, so the error is reported, not swallowed.
- **Empty context**: `windowSnapshots` is empty — the live-window count MUST return `0`, looking up a snapshot by `id` MUST return no value, both remove operations MUST return no value, and both update operations MUST return `false`.
- **All dormant**: every snapshot has `windowID` absent — the live-window count MUST return `0` and the remove-by-`windowID` and update-by-`windowID` operations MUST match nothing for any argument.
- **Duplicate live window IDs in one context**: reachable only by adding window snapshots directly with distinct `id`s — the by-`windowID` operations MUST act on the first match in list order only (remove-by-window-id); the managing layer prevents this state.
- **Duplicate snapshot IDs**: reachable only by constructing `windowSnapshots` directly — adding a snapshot, removing by `id`, looking up by `id` and updating by `id` MUST act on the first match only.
- **Stale focus**: `lastFocusedWindowID` set to an ID not in `windowSnapshots` — window context MUST keep it (focus-not-validated); consumers resolving it get no value from looking up by `id`.
- **Focus cleared only by removal**: replacing the focused snapshot by adding a window snapshot, or making it dormant through an update, MUST leave `lastFocusedWindowID` unchanged.
- **Boundary values**: window and display identifiers at their minimum and maximum representable values, a `pid` of `0` or negative, `layer` at any representable value, and a zero- or negative-size frame MUST be stored unchanged; none of the types range-checks numeric fields.
- **Malformed color**: `color` of `""`, `"red"` or `"#GGG"` MUST be stored verbatim; interpreting it is the renderer's job, and the field's documented `#`-prefixed hex form is only the caller's precondition.
- **Unknown strategy on disk**: persisted JSON with a `matchStrategy` string not among the four raw values — decoding MUST fail, failing the whole enclosing context's decode (strategy-unknown-raw); the context store wraps that failure in its "Failed to decode data at <path>" error.
- **Older or newer schema**: JSON missing a required key MUST fail to decode (missing-key-throws); extra unknown keys MUST be ignored by the decoder.
- **Concurrent access**: all types are safe to use across concurrent execution contexts, with no shared mutable state; each mutation acts on the caller's own copy, and it is the platform's and caller's responsibility, not the type's, to prevent simultaneous access to one variable.
- **Error states**: none of the operations can fail; "not found" is reported as an absent value or `false` and the only throwing paths are serialization decoding, which surfaces a decoding error to the caller.
- **Cancellation and timeouts**: not applicable; every operation is a synchronous in-memory computation with nothing to cancel.
- **Offline or disconnected state**: not applicable; the types perform no network access.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Window context: `id` | unique identifier | freshly generated | Context identity; supply one to rebuild a known context. |
| Window context: `name` | string | required | User-visible context name. |
| Window context: `color` | string | `"#007AFF"` | `#`-prefixed hex color shown in the menu bar and context list. |
| Window context: `windowSnapshots` | list of window snapshots | empty | Initial snapshots, stored as given. |
| Window context: `lastFocusedWindowID` | optional identifier | absent | Snapshot ID to refocus when the context is switched back to. |
| Window context: `createdAt` | timestamp | current date and time | Creation timestamp; injectable for tests. |
| Window snapshot: `id` | unique identifier | freshly generated | Stable snapshot identity across restarts. |
| Window snapshot: `windowID` | optional window identifier | absent | Current live window identifier; absent means dormant. |
| Window snapshot: `lastSeen` | timestamp | current date and time | Last time the snapshot had a live window; injectable for tests. |
| Window snapshot: `fingerprint`, `savedFrame`, `display`, `app`, `title` | various | required | Identity and restore data, stored verbatim. |
| Window fingerprint: all fields | various | required | No defaults. |
| Window info: all fields | various | required | No defaults. |
| Serialization date format | encoder/decoder configuration | caller's choice | The types impose none; the context store uses ISO-8601. |

## Deep Linking

Not applicable: none of the five types defines a URL scheme, route or navigation entry point; they are model types only.

## Localization

The display name for each match-strategy value returns hardcoded English literals with no string-catalog lookup; it is placed beside the model so any host rendering a strategy picker reads the label from the model.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `Exact` | The display name for `appAndTitleExact`, a strategy-picker label |
| (none; literal) | `Substring` | The display name for `appAndTitleSubstring` |
| (none; literal) | `Regex` | The display name for `appAndTitleRegex` |
| (none; literal) | `App Only` | The display name for `appOnly` |

The example context names ("iOS App", "Backend API", "Docs") used to illustrate the type are documentation, not strings the code emits.

## Accessibility Options

Not applicable: the types have no visual surface, so they respond to no Reduce Motion, Increase Contrast or Differentiate Without Color setting.

## Feature Flags

Not applicable: the source declares no feature-flag key and gates no behavior on one.

## Analytics

Not applicable: none of the five types emits analytics events.

## Privacy

- **Data collected**: The types hold window metadata about other apps: owning app name, process ID, window title, frame and display. Window titles can contain document names, web page titles or message subjects, so they are potentially personal.
- **Storage**: The types store nothing themselves; in memory only. The context store persists contexts, including each snapshot's `title` and the fingerprint's `titlePattern`, as JSON files on local disk.
- **Transmission**: The types never transmit data; no operation performs network access.
- **Retention**: A snapshot's `title` and fingerprint stay in the context until the remove operation removes the snapshot; dormant snapshots are kept, not expired, and nothing in these types deletes data by age.

## Logging

Not applicable: none of the five types performs logging; the only related log line is the window matcher's error for an invalid regex `titlePattern`.

## Platform Notes

- **SwiftUI**: No SwiftUI code in the source. A SwiftUI host keeps an array of `SystemWindowContext` in an `@Observable` model and drives a strategy `Picker` from `MatchStrategy.allCases` with `displayName` labels; mutations go through the same `mutating` methods on the model's stored copy.
- **Compose**: Port each struct to a Kotlin `data class` (immutable `val` for the Swift `let` fields; `copy(...)` stands in for both `withTitle` and `mutating` updates) and `MatchStrategy` to an `enum class` with a `displayName` property sourced from `strings.xml`. Use `kotlinx.serialization` with `@Serializable`, `java.util.UUID` or a `String` ID, `kotlinx.datetime.Instant` for dates, and a small `@Serializable` rect class encoded as `[[x,y],[w,h]]` to stay wire-compatible. Android has no API to enumerate other apps' windows, so `SystemWindowInfo` is only meaningful as a data model there.
- **React/Web**: Model the enum as a string-literal union `'appAndTitleExact' | 'appAndTitleSubstring' | 'appAndTitleRegex' | 'appOnly'` and the structs as readonly TypeScript interfaces, with context operations as pure functions returning a new context (for example `addWindow(ctx, snap): SystemWindowContext`) so the "first match by id, replace in place" rule is explicit. Use `crypto.randomUUID()` for IDs, ISO strings for dates, and validate on `JSON.parse` with a schema library (for example zod) to reproduce missing-key-throws and strategy-unknown-raw. Browsers cannot list OS windows.
- **AppKit / UIKit**: This is the source, in `packages/apple/AgenticToolkit/Core/SystemWindows/`: `MatchStrategy.swift`, `SystemWindowFingerprint.swift`, `SystemWindowInfo.swift`, `SystemWindowSnapshot.swift` and `SystemWindowContext.swift`. They import only Foundation and CoreGraphics (for `CGRect`) and build for macOS and iOS; the CGWindowID and display ID values come from macOS `CGWindowListCopyWindowInfo` and `CGDirectDisplayID` in the macOS-only consumers, so on iOS the types are data models only. All five types are Swift `struct`/`enum` values conforming to `Sendable`, `Codable` (compiler-synthesized, keyed by property name) and `Equatable` (synthesized, comparing every stored property); `MatchStrategy` also conforms to `CaseIterable`, so `allCases` is compiler-generated in declaration order. `CGRect` fields encode using CoreGraphics' own `Codable` conformance as `[[x,y],[width,height]]`. Concurrent-mutation safety comes from Swift's value semantics and exclusivity checking, not from actor isolation or locks: a `SystemWindowContext` is mutated through `mutating` methods on a single owner's copy. Without the context store's `.iso8601` date strategy, a default `JSONEncoder`/`JSONDecoder` would encode `Date` fields as seconds since the Cocoa reference date (2001-01-01) instead. The update closures passed to `updateSnapshot` are declared non-escaping, so they cannot be stored or called after the method returns; the two `removeWindow` overloads are marked `@discardableResult`. `SystemWindowInfo.withTitle(_:)` exists because `CGWindowListCopyWindowInfo` omits window titles when the process lacks the Screen Recording permission; the Accessibility API is used to backfill them.
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

**Decision** (Apple platforms): A snapshot's stable `id` is a `UUID` separate from the CGWindowID, and the CGWindowID is optional.
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

**Decision** (Apple platforms): `MatchStrategy.displayName` lives on the model and returns English literals.
**Rationale**: The doc comment keeps it beside the enum, like `CustomMatchMode.displayName`, so hosts read labels without reaching into the macOS UI layer; the strings are not externalized, which is recorded as a failed check under Compliance.
**Approved**: pending

**Decision** (Apple platforms): The types rely on synthesized `Codable` with no versioning.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to system/system-windows/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
