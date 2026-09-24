---
id: b1a34260-3966-4309-ac58-6249752c95fb
title: WebviewPanelState
domain: agentictoolkit://recipes/extension-host-core-extensions-webview-panel-state
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Codable value type: the single JSON string a webview panel''s viewType,
  title, page state and options survive a quit as.'
platforms:
- swift
- macos
tags:
- extensions
- webview
- pane
- persistence
- codable
depends-on: []
related:
- agentictoolkit://recipes/webview-panel-view-controller
references:
- packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelState.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/WebviewPanelStateTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelOptions.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Webview/WebviewPanelViewController.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Webview/WebviewPanelSerializer.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# WebviewPanelState

## Overview

`WebviewPanelState` is `AgenticToolkitCore`'s encoding of everything needed to
put an extension's webview panel back after a quit, as the single `String?`
value the pane-state store (`ProjectWorkspace.setPaneState(nodeID:key:value:)`)
holds per key. Per the source's own header comment, that store holds one
opaque string per key, so every caller wanting structure has to encode its own
JSON; this type is that encoding, written once rather than re-derived at each
call site (`dry`), because getting it subtly wrong is how a panel comes back
with a value its owning extension never saved. `WebviewPanelViewController`
produces a value of this type from its own `restorationState` computed
property and consumes one in `init(restoring:localResourceRoots:)`;
`WebviewPanelSerializer` is what actually calls `encoded()` before a
`ProjectWorkspace.setPaneState` write and `init(json:)` after a
`ProjectWorkspace.paneState(nodeID:key:)` read, but neither of those calls
belongs to this file's own contract, which is the encode/decode round trip
and the four fields it carries: `viewType`, `title`, `state`, and `options`.

## Behavioral Requirements

- **stored-shape**: `WebviewPanelState` MUST be declared as a `public struct`
  conforming to `Codable`, `Equatable`, and `Sendable`, with exactly four
  stored properties: `viewType: String`, `title: String`, `state: String?`,
  and `options: WebviewPanelOptions`.
- **memberwise-construction**: `init(viewType:title:state:options:)` MUST
  assign each of the four parameters directly to its like-named stored
  property, performing no derivation, defaulting, or validation.
- **owning-extension-not-stored**: `WebviewPanelState` MUST NOT store the
  identifier of the extension that owns the panel; per the source's own doc
  comment, the owning extension is derivable from `viewType` (the activation
  event `onWebviewPanel:<viewType>`), and a second, independently-stored copy
  of a derivable fact is one that can disagree with the first.
- **sorted-key-encoding**: `encoded()` MUST configure its `JSONEncoder` with
  `outputFormatting = .sortedKeys`, so that an unchanged panel encodes to an
  unchanged string and a change-notifying store stays quiet when nothing
  actually changed.
- **utf8-encode-guarantee**: `encoded()` MUST construct its returned string
  from the encoder's output bytes interpreted as UTF-8, and MUST throw
  `WebviewPanelStateError.encodedTextIsNotUTF8` if that interpretation fails,
  rather than force-unwrapping the conversion.
- **decode-entry-point**: `init(json:)` MUST decode `Self` from `json`'s UTF-8
  bytes using `JSONDecoder`, propagating whatever error the decoder throws
  rather than catching or wrapping it.
- **round-trip-fidelity**: a `WebviewPanelState` value passed through
  `encoded()` and then `init(json:)` MUST decode to a value equal (by
  `Equatable`) to the original, for every combination of its four fields
  observed in the source's test suite (source:
  `WebviewPanelStateTests.roundTripsThroughText`,
  `WebviewPanelStateTests.awkwardTitlesSurvive`).
- **state-carried-verbatim**: the `state` field MUST be encoded and decoded
  as an opaque JSON string value, never parsed, re-serialized, or otherwise
  interpreted as JSON by this type, so that whatever text the extension's
  page last passed to `setState` — including text that is itself JSON,
  contains escaped quotes, embedded newlines, non-ASCII characters, or a
  closing script-element sequence — round-trips byte for byte (source:
  `WebviewPanelStateTests.theExtensionsStateIsCarriedVerbatim`).
- **absent-state-omits-key**: `encode(to:)` MUST use `encodeIfPresent` for
  `state`, so that a `nil` state omits the `"state"` key from the encoded
  JSON entirely, rather than encoding a JSON `null` — keeping "the page never
  called `setState`" distinct from "the page saved the text `null`" (source:
  `WebviewPanelStateTests.absentStateStaysAbsent`).
- **missing-view-type-refused**: `init(from:)` MUST decode `viewType` with
  `decode(String.self, forKey: .viewType)` (not `decodeIfPresent`), so that
  JSON with no `viewType` key throws rather than decoding with a defaulted or
  empty value (source: `WebviewPanelStateTests.aMissingViewTypeIsRefused`).
- **missing-title-defaults-empty**: `init(from:)` MUST decode `title` with
  `decodeIfPresent(String.self, forKey: .title) ?? ""`, so that JSON with no
  `title` key decodes successfully with an empty title rather than throwing.
- **missing-options-default-safe**: `init(from:)` MUST decode `options` with
  `decodeIfPresent(WebviewPanelOptions.self, forKey: .options) ??
  WebviewPanelOptions(enableScripts: nil, enableForms: nil,
  localResourceRoots: nil)`, so that JSON stored before `options` existed
  decodes to the safe posture — no scripts, no forms, the default resource
  roots — rather than throwing or guessing a more permissive value (source:
  `WebviewPanelStateTests.absentOptionsDecodeToTheSafePosture`).
- **unknown-fields-ignored**: decoding MUST ignore any JSON key not named by
  `CodingKeys` (`viewType`, `title`, `state`, `options`), so that JSON written
  by a newer build with an additional field (for example a hypothetical
  `iconPath`) still decodes successfully in a build that does not know that
  field (source: `WebviewPanelStateTests.unknownFieldsAreIgnored`).
- **malformed-text-refused**: `init(json:)` MUST throw for `json` values that
  are not a JSON object containing at least a string `viewType` — including
  an empty string, non-JSON text, truncated JSON, a JSON array, and a bare
  JSON string literal (source:
  `WebviewPanelStateTests.malformedTextIsRefused`).
- **fixed-coding-keys**: `encode(to:)` and `init(from:)` MUST both key their
  container on the same `CodingKeys` case set (`viewType`, `title`, `state`,
  `options`), so the property names in Swift and the JSON key names on disk
  never diverge independently of each other.
- **sendable-value-type**: `WebviewPanelState` MUST declare `Sendable`
  conformance; because every stored property (`String`, `String?`,
  `WebviewPanelOptions`, itself `Sendable`) is immutable (`let`) and itself
  `Sendable`, a value of this type MUST be safe to pass across actor and
  thread boundaries without additional synchronization.
- **empty-view-type-validation**: NEEDS REVIEW: Not implemented in source. `init(from:)` refuses JSON with no `viewType` key at all (`missing-view-type-refused`), but a JSON object whose `viewType` key is present with the value of an empty string decodes successfully, since `decode(String.self, forKey:)` only requires a string, not a non-empty one. The source's own doc comment gives the reason the missing case is refused — "a default would hand the panel to whichever provider happened to answer to the empty string" — and that same hazard applies to an explicit empty string exactly as much as to an absent key, but only the absent case is guarded. What would settle it: a decision from the `AgenticToolkit` maintainers on whether `init(from:)` should also refuse an empty `viewType`, and whether `WebviewPanelStateError` needs a second case for that refusal or should reuse the decoder's own missing-key error shape.

## Appearance

Not applicable — this is a persisted-state value type, not a visual
component.

## States

Not applicable — this is a persisted-state value type, not a visual
component.

## Accessibility

Not applicable — this is a persisted-state value type, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| whps-001 | round-trip-fidelity, sorted-key-encoding | `WebviewPanelState(viewType: "markdown.preview", title: "Preview README.md", state: #"{"scrollTop":420}"#, options: defaultOptions).encoded()`, then `init(json:)` on the result | the restored value equals the original (source: `roundTripsThroughText`) |
| whps-002 | absent-state-omits-key | `WebviewPanelState(viewType: "markdown.preview", title: "Preview", state: nil, options: defaultOptions).encoded()`, then `init(json:)` on the result | `restored.state == nil` (source: `absentStateStaysAbsent`) |
| whps-003 | state-carried-verbatim | encode then decode a state value of `{"note":"line\nbreak \"quoted\" café"}` | `restored.state` equals that exact string, unchanged (source: `theExtensionsStateIsCarriedVerbatim`) |
| whps-004 | state-carried-verbatim | encode then decode a state value of the literal text `null` (a two-character string, not JSON `null`) | `restored.state == "null"` as a string value, distinct from an absent state (source: `theExtensionsStateIsCarriedVerbatim`) |
| whps-005 | unknown-fields-ignored | `init(json: #"{"viewType":"markdown.preview","title":"Preview","iconPath":"a.png"}"#)` | decodes successfully; `restored.viewType == "markdown.preview"` and `restored.title == "Preview"`; the unknown `iconPath` key causes no error (source: `unknownFieldsAreIgnored`) |
| whps-006 | missing-view-type-refused | `init(json: #"{"title":"Preview"}"#)` | throws (source: `aMissingViewTypeIsRefused`) |
| whps-007 | malformed-text-refused | `init(json: "")`, `init(json: "not json")`, `init(json: "{")`, `init(json: "[]")`, `init(json: #""markdown.preview""#)` | each call throws (source: `malformedTextIsRefused`) |
| whps-008 | round-trip-fidelity | `WebviewPanelState(viewType: "vendor.view-type_2", title: #"Preview "a"b.md — café"#, state: nil, options: defaultOptions)` encoded then decoded | the restored value equals the original, including the quote and em-dash in the title (source: `awkwardTitlesSurvive`) |
| whps-009 | missing-options-default-safe, sendable-value-type | `options: WebviewPanelOptions(enableScripts: true, enableForms: nil, localResourceRoots: nil)` encoded then decoded | `restored.options.enableScripts == true` and `restored.options.enableForms == true` (source: `scriptsSurviveTheRoundTrip`) |
| whps-010 | round-trip-fidelity | `options: WebviewPanelOptions(enableScripts: true, enableForms: nil, localResourceRoots: [])` (an explicit empty-array declaration) encoded then decoded | `restored.options.resourceRoots(extensionDirectory:workspaceRoots:)` returns an empty array — the renounced-file-access declaration is not decoded back into the default roots (source: `anEmptyRootDeclarationSurvives`) |
| whps-011 | round-trip-fidelity | `options: WebviewPanelOptions(enableScripts: nil, enableForms: nil, localResourceRoots: [<two URLs>])` encoded then decoded | `restored.options.resourceRoots(...)` returns exactly those two directories, in the same order (source: `declaredRootsSurvive`) |
| whps-012 | missing-options-default-safe | `init(json: #"{"viewType":"markdown.preview","title":"Preview"}"#)` (no `options` key at all) | `restored.options.enableScripts == false`, `restored.options.enableForms == false`, and `resourceRoots(extensionDirectory:workspaceRoots:)` returns the extension directory followed by the workspace root (source: `absentOptionsDecodeToTheSafePosture`) |
| whps-013 | missing-title-defaults-empty | `init(json: #"{"viewType":"v"}"#)` (no `title` key) | decodes successfully with `restored.title == ""` (traced to the `decodeIfPresent(String.self, forKey: .title) ?? ""` line; not a named test in the source) |

## Edge Cases

- **Null and empty input**: an empty string passed to `init(json:)` MUST
  throw, as MUST a `state` value that is present but is the empty string
  `""` — the latter decodes successfully and round-trips, since `state` is
  an opaque string with no defined "empty means absent" rule; only a
  genuinely absent `state` key means absent. MUST.
- **Boundary values — the four fields' "nothing supplied" cases**: `title`
  absent decodes to `""`; `state` absent decodes to `nil`; `options` absent
  decodes to the safe, no-scripts posture; `viewType` absent is the one
  boundary that is refused outright rather than defaulted, because nothing
  can safely stand in for the serializer identity it names. MUST.
- **Concurrent access**: `WebviewPanelState` and `WebviewPanelOptions` are
  both immutable, `Sendable` value types with no shared mutable storage, so
  `encoded()` and `init(json:)` MAY be called concurrently, from any number
  of threads or tasks, against any number of independent values, with no
  synchronization required. This is a property of the type's declared
  immutability, not a marker. MUST.
- **Error states**: the only two failure paths this file defines are
  `encoded()` throwing `WebviewPanelStateError.encodedTextIsNotUTF8` (the
  source's own comment calls this case unreachable in practice, since
  `JSONEncoder` output is UTF-8 by definition of JSON, and states the
  alternative — a force-unwrap — as strictly worse) and `init(json:)`
  propagating whatever `JSONDecoder` throws for malformed or
  under-specified JSON. Neither path is caught or swallowed inside this
  file; both are the caller's to handle. MUST.
- **Offline / disconnected state**: not applicable. This type performs no
  networking of any kind; it only encodes to and decodes from an in-memory
  `String`, so there is no connectivity state to lose mid-operation.
- **Downgrade and forward compatibility**: a JSON string written by a newer
  build that added a field this build does not know about MUST still decode
  (`unknown-fields-ignored`), and a JSON string written by an older build
  that predates `options` MUST decode to the safe posture rather than
  throwing (`missing-options-default-safe`) — both are read-time recovery
  from a schema older or newer than the reader's, stated here because
  neither is a null/empty/boundary case in the ordinary sense. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewType` | `String` | none (required) | The view type its serializer is registered under and the activation event name (`onWebviewPanel:<viewType>`) that identifies the owning extension; passed to `init(viewType:title:state:options:)`. |
| `title` | `String` | none (required in the memberwise initializer; `""` when a key is absent during decode) | The panel's title at the moment it was stored. |
| `state` | `String?` | none (required in the memberwise initializer; `nil` when a key is absent during decode) | The JSON text the page last passed to `setState`, carried as opaque text. |
| `options` | `WebviewPanelOptions` | none (required in the memberwise initializer; the safe no-scripts posture when absent during decode) | What the panel was created with — `enableScripts`, `enableForms`, and any declared `localResourceRoots`. |
| `json` | `String` | none (required) | The previously-`encoded()` text passed to `init(json:)` to reconstruct a value. |

There are no environment variables, settings keys, or injected dependencies:
every input arrives as a plain initializer or function argument, and every
output is a plain return value or thrown error.

## Deep Linking

Not applicable: `WebviewPanelState` is an in-memory value type and its
`String` encoding; it defines no URL scheme, route, or navigable destination.

## Localization

Not applicable: the source defines no user-facing string of its own —
`WebviewPanelStateError` conforms only to `Error` and `Equatable`, not
`LocalizedError`, and has no `errorDescription`. The `title` and `state`
fields hold text the extension's own page supplied; this file stores that
text verbatim and originates none of it.

## Accessibility Options

Not applicable: this component has no visual or interactive surface for a
system accessibility display option to affect.

## Feature Flags

Not applicable: `WebviewPanelState.swift` defines no feature flag, build
configuration check, or remote-config lookup; every operation's behavior is
fixed entirely by its arguments.

## Analytics

Not applicable: this component emits no analytics event; it returns a value,
a `String`, or a thrown error to its caller and performs no telemetry of its
own.

## Privacy

- **Data collected**: not device- or user-identifying telemetry, but this
  type is the exact shape of what a webview panel persists across a quit:
  the panel's `title` and whatever opaque `state` string the extension's page
  last passed to `setState` (traced to the doc comments on both stored
  properties). What that `state` string contains is entirely up to the
  extension's page — it could be as innocuous as a scroll position or as
  sensitive as a form draft — and this file has no visibility into which,
  since it is carried as opaque text and never parsed.
- **Storage**: `WebviewPanelState` itself holds its four fields only in
  memory; it writes nothing to disk directly. Its `encoded()` result is what
  a caller (`WebviewPanelSerializer`, in the sources referenced above)
  passes to `ProjectWorkspace.setPaneState(nodeID:key:value:)` for actual
  persistence, which is outside this file's own contract.
- **Transmission**: none performed by this file — it does no networking.
- **Retention**: for as long as whichever caller holds the decoded value or
  its encoded `String`; this file itself retains nothing once a call to
  `encoded()` or `init(json:)` returns.

## Logging

Not applicable: `WebviewPanelState.swift` imports no logging framework and
contains no logging call; a failure is communicated to its caller
exclusively through a thrown error, never written to a log by this file.

## Platform Notes

- **SwiftUI**: the source (`WebviewPanelState.swift`) is plain
  `Foundation` — `JSONEncoder`, `JSONDecoder`, `Data`, `String` — with no
  dependency on SwiftUI or any view-layer framework. It sits in
  `AgenticToolkitCore`, alongside its sibling `WebviewPanelOptions`, and is
  consumed by the `macOS`-tier `WebviewPanelViewController` and
  `WebviewPanelSerializer`. A port that keeps this type in Swift needs
  nothing beyond `Foundation` and `Codable`.
- **Compose**: model `WebviewPanelState` as a Kotlin `data class` with the
  same four properties, and use `kotlinx.serialization`'s `@Serializable`
  with an explicit sorted-key JSON configuration (or sort the resulting
  `JsonObject`'s keys before serializing to text, since `kotlinx.serialization`
  does not sort keys by default) to reproduce `sorted-key-encoding`.
  `viewType` as a non-optional, non-defaulted constructor parameter
  reproduces `missing-view-type-refused` automatically, since
  `kotlinx.serialization` throws on a missing required field; `title`,
  `state`, and `options` need explicit default values or
  `@EncodeDefault`/nullable handling to reproduce the other three fields'
  defaulting behavior.
- **React/Web**: represent the shape as a plain TypeScript interface with
  `viewType: string`, `title: string`, `state: string | null`, and
  `options: WebviewPanelOptions`. `JSON.stringify` does not sort object keys,
  so reproducing `sorted-key-encoding` needs an explicit
  `Object.keys(value).sort()` replacer function passed to `JSON.stringify`.
  `JSON.parse` on the stored text, followed by manual field-by-field
  validation (throwing when `viewType` is missing or not a string,
  defaulting `title` to `""` and `options` to the safe posture when absent)
  reproduces the decode-side behavior, since there is no built-in decoder
  that enforces per-field presence the way Swift's `Codable` does.
- **AppKit / UIKit**: identical to the SwiftUI note — the type depends on
  neither AppKit nor UIKit, so a macOS host consumes the same
  `AgenticToolkitCore` type directly with no translation needed. (The panel
  that actually renders from a restored value, `WebviewPanelViewController`,
  is AppKit and is out of this file's own scope.)
- **WinUI 3**: use `System.Text.Json` with a `JsonSerializerOptions` whose
  `PropertyNamingPolicy` is left alone (the field names already match) and
  whose writer is configured, or whose properties are alphabetized before
  serialization, to reproduce `sorted-key-encoding` — `System.Text.Json` does
  not sort properties by declaration order by default, so an explicit
  ordering step is needed. Model `state` as a nullable `string?` mapped with
  `JsonIgnoreCondition.WhenWritingNull` on the property so a `null` state
  omits the key exactly as `encodeIfPresent` does, reproducing
  `absent-state-omits-key`. Make `viewType` a required constructor parameter
  (a C# 11 `required` property, or a positional record parameter with no
  default) so `System.Text.Json` throws `JsonException` on missing JSON
  rather than defaulting it, reproducing `missing-view-type-refused`; give
  `title` and `options` explicit fallback values in the deserializing
  constructor to reproduce their defaulting behavior. `HttpClient`,
  `Windows.Storage`, `Task`/`async`, `ObservableCollection`, and
  `INotifyPropertyChanged` all have no role here: every operation in the
  source is synchronous, non-networked, and returns a value rather than
  raising a change notification.

## Design Decisions

- **Decision**: the extension's `state` text is stored and returned exactly
  as given, never parsed as JSON or re-serialized by this type.
  **Rationale**: the source's own doc comment states that this value "goes
  straight back into a `<script>` element on restore," so re-encoding it
  would reorder keys and re-escape characters — a different value than the
  one the extension saved, produced by a layer that the doc comment states
  "has no business reading it at all."
  **Approved**: pending
- **Decision**: the owning extension's identifier is not a stored field,
  even though every caller that has one available when constructing a
  `WebviewPanelState` could easily store it.
  **Rationale**: the source's doc comment states the identifier is
  derivable from `viewType` via the `onWebviewPanel:<viewType>` activation
  event, and a second copy of a derivable fact is one that can disagree with
  the first.
  **Approved**: pending
- **Decision**: a missing `viewType` key throws rather than decoding to an
  empty string or another placeholder, while a missing `title` or `options`
  key decodes to a defined default instead of throwing.
  **Rationale**: the source's doc comment on `init(from:)` draws this
  distinction explicitly — "a missing title is survivable — an untitled tab
  is still the user's tab. A missing view type is not: it names the
  serializer that knows how to rebuild this panel, and a default would hand
  the panel to whichever provider happened to answer to the empty string."
  This is also the reasoning behind the open question on
  `empty-view-type-validation`: it applies to a `viewType` key that is
  present but empty exactly as it does to one that is absent, and only the
  absent case is currently guarded.
  **Approved**: pending
- **Decision**: options absent from stored JSON decode to the safe,
  no-scripts, no-forms, default-roots posture rather than to whatever the
  most commonly-used options happen to be.
  **Rationale**: the source's doc comment states that an entry written
  before `options` existed is still a panel the user had open and must come
  back, "but what it must not do is come back with capabilities nobody
  recorded it having" — defaulting toward permissiveness would silently
  grant a restored panel scripting or file access its extension never
  declared.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |

`separation-of-concerns` passes because this file only encodes and decodes
one value's four fields; it does not resolve resource roots (that is
`WebviewPanelOptions`), build a `WKWebViewConfiguration`, or write to the
pane-state store (both `WebviewPanelViewController`'s and
`WebviewPanelSerializer`'s concerns) (`stored-shape`,
`memberwise-construction`). `explicit-error-handling` passes because both
failure paths this file defines — `encoded()`'s UTF-8 guard and
`init(json:)`'s decode — throw rather than swallow, and neither is caught
inside this file (`utf8-encode-guarantee`, `decode-entry-point`).
`unit-test-coverage` passes: `WebviewPanelStateTests.swift` exercises the
round trip, the state-carried-verbatim guarantee over seven distinct
strings, unknown-field tolerance, the missing-view-type refusal, five
distinct malformed-text inputs, and every options-defaulting path
(`round-trip-fidelity`, `state-carried-verbatim`,
`missing-options-default-safe`). `state-recovery` passes because a value of
this type is exactly what lets `WebviewPanelSerializer` rebuild a panel
after the app quits and relaunches, and the source's own tests confirm the
restored value matches what was stored, including through two schema-drift
directions (`round-trip-fidelity`, `unknown-fields-ignored`,
`missing-options-default-safe`). `data-integrity` passes because
`init(json:)` refuses to produce a value from JSON it cannot make sense of —
an empty string, non-JSON text, truncated JSON, a JSON array, a bare string
literal, or JSON missing the one field with no safe default — rather than
returning a partially-populated or best-guess value (`malformed-text-refused`,
`missing-view-type-refused`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
