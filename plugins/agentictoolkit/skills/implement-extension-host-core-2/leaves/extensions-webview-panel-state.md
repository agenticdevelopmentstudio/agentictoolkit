<!-- leaf: implement-extension-host-core-2/extensions-webview-panel-state · source: extension-host-core-extensions-webview-panel-state.md -->

**Rules** (cite as `implement-extension-host-core-2/extensions-webview-panel-state#<slug>`):

- `stored-shape` MUST
- `memberwise-construction` MUST
- `owning-extension-not-stored` MUST
- `sorted-key-encoding` MUST
- `utf8-encode-guarantee` MUST
- `decode-entry-point` MUST
- `round-trip-fidelity` MUST
- `state-carried-verbatim` MUST
- `absent-state-omits-key` MUST
- `missing-view-type-refused` MUST
- `missing-title-defaults-empty` MUST
- `missing-options-default-safe` MUST
- `unknown-fields-ignored` MUST
- `malformed-text-refused` MUST
- `fixed-coding-keys` MUST
- `sendable-value-type` MUST

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

