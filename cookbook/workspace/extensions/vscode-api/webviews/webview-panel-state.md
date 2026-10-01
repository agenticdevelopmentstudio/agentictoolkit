---
id: b1a34260-3966-4309-ac58-6249752c95fb
title: Webview Panel State
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/webview-panel-state
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The single string a webview panel's viewType, title, page state, and
  options survive a quit as.
platforms:
- swift
- macos
tags:
- extensions
- webview
- pane
- persistence
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/vscode-api/webviews/webview-panel-view
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

# Webview Panel State

## Overview

This component is the encoding of everything needed to put an extension's
webview panel back after a quit, as the single, optional string value the
pane-state store holds per key. Per the source's own documentation, that
store holds one opaque string per key, so every caller wanting structure has
to encode its own JSON; this component is that encoding, written once rather
than re-derived at each call site, because getting it subtly wrong is how a
panel comes back with a value its owning extension never saved. The panel
view produces a value of this component from its own restoration-state value
and consumes one when restoring itself; the panel serializer is what
actually performs the encoding before a pane-state write and the decoding
after a pane-state read, but neither of those calls belongs to this
component's own contract, which is the encode/decode round trip and the four
fields it carries: `viewType`, `title`, `state`, and `options`.

## Behavioral Requirements

- **stored-shape**: This component MUST have exactly four fields: `viewType`
  (a string), `title` (a string), `state` (a string, optional), and `options`
  (a webview panel options value).
- **memberwise-construction**: Constructing this component from its four
  fields MUST assign each argument directly to its like-named field,
  performing no derivation, defaulting, or validation.
- **owning-extension-not-stored**: This component MUST NOT store the
  identifier of the extension that owns the panel; the owning extension is
  derivable from `viewType` (the activation event
  `onWebviewPanel:<viewType>`), and a second, independently-stored copy of a
  derivable fact is one that can disagree with the first.
- **sorted-key-encoding**: Encoding this component MUST produce its keys in a
  fixed, sorted order, so that an unchanged panel encodes to an unchanged
  string and a change-notifying store stays quiet when nothing actually
  changed.
- **utf8-encode-guarantee**: Encoding this component MUST construct its
  returned string from the encoded bytes interpreted as UTF-8, and MUST fail
  with a defined "encoded text is not UTF-8" error condition if that
  interpretation fails, rather than crashing on the conversion.
- **decode-entry-point**: Decoding this component from a stored string MUST
  decode it from that string's UTF-8 bytes, propagating whatever error
  decoding raises rather than catching or wrapping it.
- **round-trip-fidelity**: An instance of this component passed through
  encoding and then decoding MUST decode to a value equal to the original,
  for every combination of its four fields.
- **state-carried-verbatim**: the `state` field MUST be encoded and decoded
  as an opaque string value, never parsed, re-serialized, or otherwise
  interpreted as structured data by this component, so that whatever text
  the extension's page last passed to `setState` — including text that is
  itself JSON, contains escaped quotes, embedded newlines, non-ASCII
  characters, or a closing script-element sequence — round-trips byte for
  byte.
- **absent-state-omits-key**: Encoding this component MUST omit the `state`
  key entirely from the encoded data when `state` is absent, rather than
  encoding a null value — keeping "the page never called `setState`"
  distinct from "the page saved the text `null`".
- **missing-view-type-refused**: Decoding this component MUST require a
  `viewType` key, so that data with no `viewType` key fails to decode rather
  than decoding with a defaulted or empty value.
- **missing-title-defaults-empty**: Decoding this component MUST decode
  `title` as an empty string when the source data has no `title` key, rather
  than failing to decode.
- **missing-options-default-safe**: Decoding this component MUST decode
  `options` as the fully-absent safe posture — no scripts, no forms, the
  default resource roots — when the source data has no `options` key, rather
  than failing to decode or guessing a more permissive value.
- **unknown-fields-ignored**: Decoding this component MUST ignore any key not
  named `viewType`, `title`, `state`, or `options`, so that data written by a
  newer build with an additional field (for example a hypothetical
  `iconPath`) still decodes successfully in a build that does not know that
  field.
- **malformed-text-refused**: Decoding this component from a stored string
  MUST fail for input that is not an object containing at least a string
  `viewType` — including an empty string, non-JSON text, truncated JSON, an
  array, and a bare string literal.
- **fixed-coding-keys**: Encoding and decoding this component MUST both use
  the same fixed key set (`viewType`, `title`, `state`, `options`), so the
  field names and the wire key names never diverge independently of each
  other.
- **safe-for-concurrent-access**: Because this component holds no mutable
  stored state — every field is fixed once constructed, and each field's own
  type is itself safe for concurrent access — a value of this component MUST
  be safe to pass across concurrent execution contexts without additional
  synchronization.
- **empty-view-type-validation**: NEEDS REVIEW: Not implemented in source. Decoding this component refuses data with no `viewType` key at all (**missing-view-type-refused**), but data whose `viewType` key is present with the value of an empty string decodes successfully, since requiring the key only requires a string, not a non-empty one. The source's own documentation gives the reason the missing case is refused — "a default would hand the panel to whichever provider happened to answer to the empty string" — and that same hazard applies to an explicit empty string exactly as much as to an absent key, but only the absent case is guarded. What would settle it: a decision from this toolkit's maintainers on whether decoding should also refuse an empty `viewType`, and whether a second, distinct error condition is needed for that refusal or the existing missing-key failure should be reused.

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
| whps-001 | round-trip-fidelity, sorted-key-encoding | Construct with `viewType: "markdown.preview", title: "Preview README.md", state: {"scrollTop":420} (as text), options: defaultOptions`, encode, then decode the result | the restored value equals the original |
| whps-002 | absent-state-omits-key | Construct with `viewType: "markdown.preview", title: "Preview", state` absent, `options: defaultOptions`, encode, then decode the result | the restored `state` is absent |
| whps-003 | state-carried-verbatim | Encode then decode a state value of `{"note":"line\nbreak \"quoted\" café"}` | the restored `state` equals that exact string, unchanged |
| whps-004 | state-carried-verbatim | Encode then decode a state value of the literal text `null` (a two-character string, not a JSON null) | the restored `state` equals the string `"null"`, distinct from an absent state |
| whps-005 | unknown-fields-ignored | Decode `{"viewType":"markdown.preview","title":"Preview","iconPath":"a.png"}` | decodes successfully; the restored `viewType` equals `"markdown.preview"` and `title` equals `"Preview"`; the unknown `iconPath` key causes no error |
| whps-006 | missing-view-type-refused | Decode `{"title":"Preview"}` | fails to decode |
| whps-007 | malformed-text-refused | Decode an empty string, the text `not json`, the truncated text `{`, an array `[]`, and the bare string literal `"markdown.preview"` | each fails to decode |
| whps-008 | round-trip-fidelity | Construct with `viewType: "vendor.view-type_2", title: Preview "a"b.md — café, state` absent, `options: defaultOptions`, then encode and decode | the restored value equals the original, including the quote and em-dash in the title |
| whps-009 | missing-options-default-safe, safe-for-concurrent-access | Construct with `options` built from as-declared values with `enableScripts: true, enableForms` absent, `localResourceRoots` absent, then encode and decode | the restored options' `enableScripts` equals `true` and `enableForms` equals `true` |
| whps-010 | round-trip-fidelity | Construct with `options` built from as-declared values with `enableScripts: true, enableForms` absent, `localResourceRoots: []` (an explicit empty-list declaration), then encode and decode | resolving the restored options' local resource roots returns an empty list — the renounced-file-access declaration is not decoded back into the default roots |
| whps-011 | round-trip-fidelity | Construct with `options` built from as-declared values with `localResourceRoots` holding two locations, then encode and decode | resolving the restored options' local resource roots returns exactly those two directories, in the same order |
| whps-012 | missing-options-default-safe | Decode `{"viewType":"markdown.preview","title":"Preview"}` (no `options` key at all) | the restored options' `enableScripts` equals `false`, `enableForms` equals `false`, and resolving local resource roots returns the extension directory followed by the workspace root |
| whps-013 | missing-title-defaults-empty | Decode `{"viewType":"v"}` (no `title` key) | decodes successfully with the restored `title` equal to an empty string |

## Edge Cases

- **Null and empty input**: decoding this component from an empty string
  MUST fail, as MUST decoding a `state` value that is present but is the
  empty string `""` — the latter decodes successfully and round-trips,
  since `state` is an opaque string with no defined "empty means absent"
  rule; only a genuinely absent `state` key means absent. MUST.
- **Boundary values — the four fields' "nothing supplied" cases**: `title`
  absent decodes to `""`; `state` absent decodes to absent; `options`
  absent decodes to the safe, no-scripts posture; `viewType` absent is the
  one boundary that is refused outright rather than defaulted, because
  nothing can safely stand in for the serializer identity it names. MUST.
- **Concurrent access**: this component and the webview panel options it
  carries are both immutable value types with no shared mutable storage, so
  encoding and decoding MAY be called concurrently, from any number of
  independent execution contexts, against any number of independent values,
  with no synchronization required. This is a property of the component's
  declared immutability, not a marker. MUST.
- **Error states**: the only two failure paths this component defines are
  encoding failing with the "encoded text is not UTF-8" error condition (the
  source's own documentation calls this case unreachable in practice, since
  the encoder's output is UTF-8 by definition of JSON, and states the
  alternative — crashing instead — as strictly worse) and decoding
  propagating whatever error decoding raises for malformed or
  under-specified data. Neither path is caught or swallowed inside this
  component; both are the caller's to handle. MUST.
- **Offline / disconnected state**: not applicable. This component performs
  no networking of any kind; it only encodes to and decodes from an
  in-memory string, so there is no connectivity state to lose
  mid-operation.
- **Downgrade and forward compatibility**: data written by a newer build
  that added a field this build does not know about MUST still decode
  (**unknown-fields-ignored**), and data written by an older build that
  predates `options` MUST decode to the safe posture rather than failing
  (**missing-options-default-safe**) — both are read-time recovery from a
  schema older or newer than the reader's, stated here because neither is a
  null/empty/boundary case in the ordinary sense. MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewType` | a string | none (required) | The view type its serializer is registered under and the activation event name (`onWebviewPanel:<viewType>`) that identifies the owning extension; given when constructing this component from its four fields. |
| `title` | a string | none (required when constructing directly; `""` when a key is absent during decode) | The panel's title at the moment it was stored. |
| `state` | a string (optional) | none (required when constructing directly; absent when a key is absent during decode) | The JSON text the page last passed to `setState`, carried as opaque text. |
| `options` | a webview panel options value | none (required when constructing directly; the safe no-scripts posture when absent during decode) | What the panel was created with — `enableScripts`, `enableForms`, and any declared `localResourceRoots`. |
| `json` | a string | none (required) | The previously-encoded text passed to the decoding operation to reconstruct a value. |

There are no environment variables, settings keys, or injected dependencies:
every input arrives as a plain argument, and every output is a plain return
value or a raised error.

## Deep Linking

Not applicable: this component is an in-memory value and its string
encoding; it defines no URL scheme, route, or navigable destination.

## Localization

Not applicable: the source defines no user-facing string of its own — its
defined error condition carries no localized description. The `title` and
`state` fields hold text the extension's own page supplied; this component
stores that text verbatim and originates none of it.

## Accessibility Options

Not applicable: this component has no visual or interactive surface for a
system accessibility display option to affect.

## Feature Flags

Not applicable: this component defines no feature flag, build configuration
check, or remote-config lookup; every operation's behavior is fixed entirely
by its arguments.

## Analytics

Not applicable: this component emits no analytics event; it returns a value,
a string, or a raised error to its caller and performs no telemetry of its
own.

## Privacy

- **Data collected**: not device- or user-identifying telemetry, but this
  component is the exact shape of what a webview panel persists across a
  quit: the panel's `title` and whatever opaque `state` string the
  extension's page last passed to `setState`. What that `state` string
  contains is entirely up to the extension's page — it could be as
  innocuous as a scroll position or as sensitive as a form draft — and this
  component has no visibility into which, since it is carried as opaque
  text and never parsed.
- **Storage**: this component itself holds its four fields only in memory;
  it writes nothing to disk directly. Its encoded result is what a caller
  (the panel serializer) passes to the pane-state store for actual
  persistence, which is outside this component's own contract.
- **Transmission**: none performed by this component — it does no
  networking.
- **Retention**: for as long as whichever caller holds the decoded value or
  its encoded string; this component itself retains nothing once a call to
  encode or decode returns.

## Logging

Not applicable: this component contains no logging call; a failure is
communicated to its caller exclusively through a raised error, never
written to a log by this component.

## Platform Notes

- **SwiftUI**: the source (`WebviewPanelState.swift`) is plain
  `Foundation` — `JSONEncoder`, `JSONDecoder`, `Data`, `String` — with no
  dependency on SwiftUI or any view-layer framework. It sits in
  `AgenticToolkitCore`, alongside its sibling `WebviewPanelOptions`, and is
  consumed by the `macOS`-tier `WebviewPanelViewController` and
  `WebviewPanelSerializer`. A port that keeps this type in Swift needs
  nothing beyond `Foundation` and `Codable`. `WebviewPanelState` is a
  `public struct` conforming to `Codable`, `Equatable`, and `Sendable`, with
  exactly the four stored properties named above (`viewType: String`,
  `title: String`, `state: String?`, `options: WebviewPanelOptions`);
  "constructing this component from its four fields" above is
  `init(viewType:title:state:options:)`. "Encoding this component" above is
  `encoded()`, which configures its `JSONEncoder` with
  `outputFormatting = .sortedKeys` to reproduce **sorted-key-encoding**, and
  fails with `WebviewPanelStateError.encodedTextIsNotUTF8` rather than
  force-unwrapping the UTF-8 conversion. "Decoding this component from a
  stored string" is `init(json:)`, which decodes `Self` from the string's
  UTF-8 bytes via `JSONDecoder`. `encode(to:)` uses `encodeIfPresent` for
  `state` (reproducing **absent-state-omits-key**); `init(from:)` decodes
  `viewType` with `decode(String.self, forKey: .viewType)` (not
  `decodeIfPresent`, reproducing **missing-view-type-refused**), `title`
  with `decodeIfPresent(String.self, forKey: .title) ?? ""`, and `options`
  with `decodeIfPresent(WebviewPanelOptions.self, forKey: .options) ??
  WebviewPanelOptions(enableScripts: nil, enableForms: nil,
  localResourceRoots: nil)`. Both methods key their container on the same
  `CodingKeys` case set (`viewType`, `title`, `state`, `options`), giving
  **fixed-coding-keys** and, by `Codable`'s own contract, **unknown-fields-ignored**
  for free. **safe-for-concurrent-access** above follows from
  `WebviewPanelState`'s explicit `Sendable` conformance: every stored
  property (`String`, `String?`, `WebviewPanelOptions`, itself `Sendable`)
  is immutable (`let`) and itself `Sendable`.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelState.swift` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/webviews/. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
