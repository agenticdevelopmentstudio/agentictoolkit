---
id: 68d182dc-3fc0-489c-ab04-ff4da25fc4df
title: Extension Manifest
domain: agentictoolkit://cookbook/workspace/extensions/manifest/extension-manifest
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Model of a VS Code package.json: strict identity, element-isolated lenient
  decoding of contributes.* entries, typed diagnostics for what one decode attempt
  had to drop.'
platforms:
- swift
- macos
tags:
- extensions
- manifest
- decoding
- package-json
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifest.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/ExtensionManifestTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Extension Manifest

## Overview

This component is the model of a VS Code `package.json` used by this host.
It has no visual surface of its own: it is a pure, synchronous decode/encode
layer — everything downstream that reads to install themes, snippets,
languages, commands, keybindings, menus, settings, views, view containers,
and (later) language-model tools comes from the contributions value this
component decodes. Its defining discipline is asymmetric strictness: the
extension's `name`, `version`, `engines.vscode`, and the `contributes`
block's own shape are the extension's non-negotiable identity, and a
manifest missing or misspelling any of them fails to decode entirely;
everything else — every `contributes.*` array element, every
keyed-dictionary location, every optional scalar field — is decoded with
element- or field-level isolation, so one malformed theme, command, or
configuration property never costs its siblings. A shared lenient-decoding
helper implements that isolation once, used by every `contributes.*`
collection, and a typed decoding-failure record — never itself re-encoded —
is how a caller learns what, if anything, one decode attempt had to drop.

## Behavioral Requirements

- **decodes-vscode-package-json-subset**: a manifest MUST decode as a
  subset of a VS Code `package.json`, using a standard JSON decoder with no
  custom key-decoding strategy, date-decoding strategy, or extra decode
  context.
- **top-level-identity-required**: decoding a manifest MUST fail entirely
  when `name`, `version`, or `engines.vscode` is missing or the wrong JSON
  type — each of these three is decoded as required, never treated as
  optional or leniently recovered.
- **identity-decoded-before-lenient-fields**: decoding a manifest MUST
  decode `name`, `publisher`, `version`, `displayName`, `description`,
  `engines`, `main`, and `browser` before attempting `activationEvents`,
  `extensionKind`, `capabilities`, or `contributes`, so the manifest's own
  name is always available before any field that can independently fail is
  attempted.
- **optional-descriptive-fields-decode-if-present**: `publisher`,
  `displayName`, `description`, `main`, and `browser` MUST decode leniently
  for absence — yielding an absent value when the key is absent or JSON
  `null` — but MUST fail the whole decode if the key is present with an
  incompatible JSON type.
- **engines-vscode-required**: the engines block MUST require a `vscode`
  string field; an `engines` object omitting `vscode`, or giving it a
  non-string value, MUST fail the whole manifest decode.
- **display-identifier-composition**: `displayIdentifier` MUST return
  `"<publisher>.<name>"` when `publisher` is present, and MUST return
  `name` unchanged when `publisher` is absent.
- **identifier-case-folding**: `identifier` MUST return `displayIdentifier`
  lowercased; two manifests whose `publisher`/`name` differ only in case
  MUST produce the same `identifier` while each keeps its own distinct
  `displayIdentifier`.
- **activation-events-defaults-empty**: `activationEvents` MUST default to
  an empty list, never an absent value, when the key is absent, because VS
  Code 1.74+ infers activation from `contributes` and an extension relying
  on that inference omits the key entirely.
- **activation-events-tolerant**: a present `activationEvents` value that
  is not an array of strings MUST NOT fail the manifest decode; it MUST
  resolve to an empty list and record exactly one decoding failure keyed
  `"activationEvents"`.
- **extension-kind-nil-means-absent**: `extensionKind` MUST be absent, not
  an empty list, when the key is absent or its value is unreadable — an
  empty list is reserved for a manifest that explicitly declares it runs in
  no extension host at all.
- **extension-kind-tolerant**: a present `extensionKind` value that is not
  an array of strings MUST NOT fail the manifest decode; it MUST resolve to
  absent and record exactly one decoding failure keyed `"extensionKind"`.
- **capabilities-tolerant**: a present `capabilities` value that fails to
  decode as the capabilities block MUST NOT fail the manifest decode; it
  MUST resolve to absent and record exactly one decoding failure keyed
  `"capabilities"`.
- **contributes-strict**: `contributes` MUST decode leniently only for
  absence, with no per-entry recovery of its own; a present `contributes`
  key whose shape cannot even begin to parse MUST fail and sink the entire
  manifest decode.
- **untrusted-workspaces-support-tri-form**: the untrusted-workspaces
  support value MUST decode JSON `true` as supported, JSON `false` as
  unsupported, and the JSON string `"limited"` as limited, and MUST fail
  for any other value; encoding MUST invert the same mapping exactly.
- **decoding-failures-not-encoded**: a manifest's recorded decoding
  failures, and the contributions value's recorded decoding failures, MUST
  NOT be included when either value is encoded back to JSON — they
  describe one decode attempt, not manifest content.
- **contributions-empty-static-value**: the empty contributions value MUST
  have every list empty, every dictionary empty, and no recorded decoding
  failures.
- **contributions-absent-vs-empty-equivalence**: a manifest whose
  `contributes` key is entirely absent and a contributions value whose own
  keys are all absent MUST be treated as the same statement — "this
  extension declares nothing" — which is what makes the empty contributions
  value a reusable stand-in for either case.
- **contributions-arrays-default-empty**: each of `themes`, `snippets`,
  `languages`, `commands`, `keybindings`, `configuration`, and
  `languageModelTools` MUST default to an empty list when its manifest key
  is absent.
- **contributions-dictionaries-default-empty**: each of `menus`, `views`,
  and `viewsContainers` MUST default to an empty dictionary when its
  manifest key is absent.
- **contributions-encode-lossy**: encoding the contributions value back to
  JSON MUST NOT be a faithful round-trip of the manifest that was decoded —
  it MUST omit the recorded decoding failures (per
  `decoding-failures-not-encoded`) and MUST omit every `contributes.*`
  entry that failed to decode, since the contributions value never held
  those entries to begin with.
- **lenient-array-absent-key-returns-empty**: the shared array-decoding
  helper MUST return an empty list without recording a decoding failure
  when the key is absent from the manifest.
- **lenient-array-strict-fast-path**: the shared array-decoding helper MUST
  first attempt to decode the key's value directly as an array of the
  expected element type, and return that result directly when it succeeds,
  without building any intermediate generic-JSON representation.
- **lenient-array-single-object-tolerance**: when the direct array decode
  fails, the shared array-decoding helper MUST accept a single JSON object
  in place of a one-element array — treated as a one-element array — for
  every array-shaped `contributes` key, including ones (`commands`,
  `themes`) whose own VS Code schema requires strictly an array.
- **lenient-array-non-array-non-object-failure**: when the manifest value
  for the key is neither an array nor a single JSON object, the shared
  array-decoding helper MUST return an empty list and record exactly one
  decoding failure for that key with no index and reason `"expected an
  array"`.
- **lenient-array-element-isolation**: once the array is obtained
  (directly, or via the single-object recovery path), each element MUST be
  decoded independently; an element that fails to decode as its expected
  type MUST be dropped from the result and recorded as one decoding
  failure carrying that element's index, while every other element in the
  same array MUST still decode.
- **lenient-array-strict-first-perf-rationale**: the whole-array
  direct-decode attempt MUST run before the per-element recovery path, and
  the recovery path MUST run only when the direct attempt fails — measured
  at roughly 275ms of CPU time for the recovery path against roughly 4ms of
  file I/O on a 100-synthetic-extension benchmark, so a well-formed
  manifest MUST NOT pay the per-element round-trip cost.
- **lenient-dictionary-absent-key-returns-empty**: the shared
  dictionary-decoding helper MUST return an empty dictionary without
  recording a decoding failure when the key is absent from the manifest.
- **lenient-dictionary-strict-fast-path**: the shared dictionary-decoding
  helper MUST first attempt to decode the key's value directly as a
  dictionary of string to a list of the expected element type, and return
  it directly when it succeeds.
- **lenient-dictionary-whole-value-failure**: when the manifest value for
  the key cannot decode as a generic string-keyed JSON object at all, the
  shared dictionary-decoding helper MUST return an empty dictionary and
  record exactly one decoding failure for the bare key, with no index and
  reason `"expected an object"`.
- **lenient-dictionary-location-isolation**: for each location key in the
  decoded string-keyed object, a value that is not itself a JSON array MUST
  be skipped and recorded as one decoding failure keyed
  `"<key>.<location>"` with no index, while every other location in the
  same dictionary MUST still decode.
- **lenient-dictionary-element-isolation**: within one location's array,
  each element MUST decode independently the same way the shared
  array-decoding helper does; an element that fails MUST be recorded as one
  decoding failure keyed `"<key>.<location>"` with that element's index,
  while sibling elements in the same location MUST still decode.
- **lenient-value-absent-vs-unreadable**: the shared value-decoding helper
  MUST return absent without recording a decoding failure when the key is
  absent, and MUST return absent while recording exactly one decoding
  failure when the key is present but the value's own decode fails.
- **decoding-failure-text-key-not-found**: the failure-text renderer MUST
  render a missing-key failure as `no "<key>"` using the missing key's
  name.
- **decoding-failure-text-type-mismatch-named**: the failure-text renderer
  MUST render a type-mismatch failure as `<subject> is not <name>` when a
  JSON noun is known for the expected type.
- **decoding-failure-text-type-mismatch-unnamed**: the failure-text
  renderer MUST render a type-mismatch failure for a type with no known
  JSON noun (a first-party type with its own custom decoding) as
  `<subject> is the wrong kind of value`, never interpolating the type's
  own name.
- **decoding-failure-text-value-not-found**: the failure-text renderer
  MUST render a missing-value failure as `<subject> is null`.
- **decoding-failure-text-data-corrupted**: the failure-text renderer MUST
  render a corrupted-data failure as its underlying description verbatim.
- **decoding-failure-text-non-decoding-error**: the failure-text renderer
  MUST render any failure that is not one of the four decoding-failure
  shapes above — including an unrecognized future case — as that failure's
  own localized description.
- **decoding-failure-subject-empty-path**: resolving a failure's subject
  MUST return the literal `this entry` when the failure's location path is
  empty, and MUST otherwise return the dot-joined path wrapped in curly
  quotes.
- **json-value-shape**: a generic JSON value MUST decode and encode
  exactly the six JSON value kinds — null, boolean, number, string, array,
  and object — trying each case in order on decode and failing only if
  none match.
- **theme-strict-shape**: a theme entry MUST require `label`, `uiTheme`,
  and `path` as strings, with no per-field leniency of its own — a
  malformed field MUST fail only that array element, via
  `lenient-array-element-isolation`, never the whole manifest.
- **snippet-strict-shape**: a snippet entry MUST require `language` and
  `path` as strings.
- **language-optional-fields**: a language entry MUST require `id` as a
  string and MUST treat `aliases`, `extensions`, `filenames`,
  `filenamePatterns`, `firstLine`, `mimetypes`, `configuration`, and `icon`
  as ordinary optional fields with no per-field tolerance beyond the
  standard optional-field handling. `mimetypes` MUST be carried even though
  nothing in this host maps a file by MIME type, so an entry that declared
  only `mimetypes` stays distinguishable from one that declared nothing.
- **command-icon-string-form-only**: a command entry's `icon` MUST decode a
  plain string icon path, and MUST decode to absent — dropping the icon
  with no decoding failure recorded anywhere — when the manifest supplies
  VS Code's object form (`{ light, dark }`) instead, so a themed icon never
  costs the command its `command`, `title`, `category`, or `enablement`.
- **keybinding-args-not-carried**: a keybinding entry MUST expose only
  `command`, `key`, `mac`, and `when`; it MUST NOT carry a manifest's
  `args` field, because nothing in the extension host's command dispatch
  accepts arguments today.
- **menu-item-strict-shape**: a menu item entry MUST require `command` as
  a string and MUST treat `when`, `group`, and `alt` as ordinary optional
  fields.
- **configuration-title-id-order-independently-tolerant**: a configuration
  section's `title`, `id`, and `order` MUST each decode independently and
  tolerantly, so a wrong-typed value in any one of the three (e.g. `order`
  spelled as the string `"0"`) MUST resolve only that field to absent,
  never prevent the other two fields or `properties` from decoding.
- **configuration-properties-per-property-isolation**: a configuration
  section's `properties` MUST decode each property key independently and
  tolerantly; a property whose value cannot decode as a configuration
  property MUST be dropped from the dictionary while every sibling property
  in the same section MUST still decode.
- **configuration-property-type-single-or-union**: a configuration
  property's declared type MUST decode a single JSON Schema type name as a
  single-type value, and MUST decode a JSON array of type names as a union
  of type names with every non-string member dropped.
- **configuration-property-effective-type-collapse**: a configuration
  property's effective type MUST return the single non-`"null"` member of
  a union when exactly one distinct such member exists, and MUST return
  absent when zero or more than one distinct non-`"null"` member remains;
  for a single-type value it MUST return that name unchanged, and for an
  absent declared type it MUST return absent.
- **configuration-property-every-field-independently-tolerant**: every one
  of a configuration property's decoded fields (`type`, `default`,
  `description`, `markdownDescription`, `enum`, `enumDescriptions`,
  `markdownEnumDescriptions`, `enumItemLabels`, `scope`, `order`,
  `minimum`, `maximum`, `deprecationMessage`, `markdownDeprecationMessage`,
  `editPresentation`) MUST decode independently and tolerantly, so a
  wrong-typed value in any one field MUST resolve only that field to
  absent, never fail the property or its section.
- **configuration-property-enum-item-labels-nullable-elements**: a
  configuration property's `enumItemLabels`, when present, MUST decode as a
  list of optional strings — an individual element may be JSON `null`,
  preserved as absent at that position, rather than failing the whole
  list.
- **view-identity-strict-decorations-tolerant**: a view entry's `id` and
  `.name` MUST decode strictly — a view missing either MUST fail that array
  element, via `lenient-dictionary-element-isolation`; its `when`, `type`,
  `icon`, `contextualTitle`, `visibility`, and `initialSize` MUST each
  decode independently and tolerantly of a wrong type.
- **view-unreadable-keys-recorded-per-field**: a view entry's set of
  unreadable keys MUST list the name of every optional field that was
  present in the manifest but could not be decoded to its declared type; a
  key that was absent entirely MUST NOT appear in that set.
- **view-explicit-null-treated-as-withdrawn**: a view entry's
  tolerant-field decoding MUST treat an explicit JSON `null` for an
  optional field as the field being withdrawn — resolving to absent and NOT
  adding the key to the unreadable-keys set — distinct from a
  present-and-unreadable value, which resolves to absent AND adds the key.
- **view-unreadable-keys-not-encoded**: a view entry's set of unreadable
  keys MUST NOT be included when the view is encoded back to JSON.
- **view-container-strict-identity-tolerant-decorations**: a view
  container entry's `id` and `.title` MUST decode strictly; its `icon` and
  `when` MUST each decode independently and tolerantly, resolving to
  absent on a type mismatch without failing the container and with no
  tracking equivalent to a view's unreadable-keys set.
- **language-model-tool-plain-shape**: a language-model-tool entry MUST
  decode `name`, `displayName`, `modelDescription`, `toolReferenceName`,
  `inputSchema`, `tags`, and `canBeReferencedInPrompt` with no custom
  per-field recovery of its own; a malformed field anywhere in one tool
  entry MUST fail only that entry's array element, via
  `lenient-array-element-isolation`, never a sibling tool.
- **manifest-and-contributions-are-thread-safe**: a manifest, its
  contributions value, and every nested type MUST each be immutable,
  comparable values safe to use across any concurrency boundary; decoding
  MUST be a synchronous, side-effect-free function of the decoder handed to
  it, with no file, network, or process access anywhere in this component,
  so a decoded value MAY be passed freely across concurrency domains and
  MAY be decoded concurrently by independent callers without coordination.

## Appearance

Not applicable — this is a manifest decoder, not a visual component.

## States

Not applicable — this is a manifest decoder, not a visual component.

## Accessibility

Not applicable — this is a manifest decoder, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-manifest-001 | top-level-identity-required | An empty JSON object `{}` decoded as a manifest | Fails to decode |
| extension-manifest-002 | decodes-vscode-package-json-subset, identity-decoded-before-lenient-fields | Full manifest fixture with every top-level field present | Decodes successfully; every field is populated matching the fixture |
| extension-manifest-003 | activation-events-defaults-empty, extension-kind-nil-means-absent, contributions-arrays-default-empty, contributions-dictionaries-default-empty | Minimal manifest of only `name`, `version`, `engines` | `activationEvents` is empty; `extensionKind` is absent; every contributions collection is empty |
| extension-manifest-004 | identifier-case-folding, display-identifier-composition | `publisher: "Acme"`/`name: "Kitchen-Sink"` vs `publisher: "acme"`/`name: "kitchen-sink"` | Both produce the same `identifier`, `"acme.kitchen-sink"`; each keeps its own distinct `displayIdentifier` |
| extension-manifest-005 | untrusted-workspaces-support-tri-form | `untrustedWorkspaces.supported` as JSON `true`, `false`, `"limited"` | Decodes to supported, unsupported, and limited respectively; each re-encodes to the same JSON form |
| extension-manifest-006 | view-unreadable-keys-recorded-per-field, view-unreadable-keys-not-encoded | A view entry with `initialSize` spelled as the JSON string `"2"` | `initialSize` is absent; the unreadable-keys set is `["initialSize"]`; the re-encoded JSON has no unreadable-keys entry |
| extension-manifest-007 | lenient-array-element-isolation, decoding-failure-text-type-mismatch-named | `themes: [{ label: "Night", uiTheme: 123, path: "night.json" }]` (`uiTheme` wrong type) | That theme entry is dropped; one decoding failure is recorded, keyed `"contributes.themes"`, index `0`; the manifest still decodes |
| extension-manifest-008 | lenient-array-element-isolation, decoding-failure-subject-empty-path, decoding-failure-text-type-mismatch-named | `themes: ["night.json"]` (element is a bare string, not an object) | That element is dropped; one decoding failure is recorded, keyed `"contributes.themes"`, index `0`, reason `"this entry is not an object"` |
| extension-manifest-009 | command-icon-string-form-only | `commands: [{ command: "c", title: "T", icon: { light: "l.svg", dark: "d.svg" } }]` | The command entry decodes with `icon` absent; no decoding failure is recorded for it; `command`/`title` are intact |
| extension-manifest-010 | lenient-array-single-object-tolerance | `configuration: { title: "T", properties: { "x.y": { type: "string" } } }` (single object, not an array) | Decodes as a one-element list of configuration sections |
| extension-manifest-011 | lenient-dictionary-location-isolation | `menus: { commandPalette: [...], "bad.location": "not-an-array" }` | `"bad.location"` is skipped, with one decoding failure keyed `"contributes.menus.bad.location"`, no index, reason `"expected an array"`; `commandPalette` still decodes |
| extension-manifest-012 | lenient-dictionary-element-isolation | `menus: { commandPalette: [{ command: "a" }, { when: 123 }] }` (second element malformed) | The first element decodes; the second is dropped, with a decoding failure at index `1` |
| extension-manifest-013 | capabilities-tolerant | `capabilities: "not-an-object"` | The manifest still decodes; `capabilities` is absent; a decoding failure keyed `"capabilities"` is recorded |
| extension-manifest-014 | extension-kind-tolerant | `extensionKind: "not-an-array"` | The manifest still decodes; `extensionKind` is absent; a decoding failure keyed `"extensionKind"` is recorded |
| extension-manifest-015 | activation-events-tolerant | `activationEvents: { not: "an array" }` | The manifest still decodes; `activationEvents` is empty; a decoding failure keyed `"activationEvents"` is recorded |
| extension-manifest-016 | contributes-strict | `contributes: "not-an-object"` | The whole manifest decode fails |
| extension-manifest-017 | lenient-array-absent-key-returns-empty, lenient-dictionary-absent-key-returns-empty | `contributes: {}` (no keys at all) | Every list field is empty, every dictionary field is empty, and no decoding failures are recorded |
| extension-manifest-018 | json-value-shape | Raw JSON `null`, `true`, `42`, `"s"`, `[1,2]`, `{"a":1}` each decoded as a generic JSON value | Decodes to the null, boolean-true, number-42, string-"s", array, and object kinds respectively |
| extension-manifest-019 | configuration-title-id-order-independently-tolerant | `configuration: [{ title: "T", order: "0", properties: {} }]` (`order` spelled as a string) | The section decodes with `order` absent; `title` is `"T"` intact; `properties` is still populated |
| extension-manifest-020 | configuration-properties-per-property-isolation | `properties: { "a.b": { type: "string" }, "c.d": 123 }` (second property is a bare number) | The `"a.b"` property decodes; the `"c.d"` property is absent from the dictionary, with no failure recorded |
| extension-manifest-021 | configuration-property-type-single-or-union | `type: "string"` and `type: ["number", "null"]` | Decodes to a single type name `"string"`, and a union of type names `["number"]`, respectively |
| extension-manifest-022 | configuration-property-effective-type-collapse | `type: ["number", null]` (a literal JSON null member, not the string `"null"`) | Decodes to a union of type names `["number"]` after dropping the non-string member; the effective type is `"number"` |
| extension-manifest-023 | configuration-property-enum-item-labels-nullable-elements | `enumItemLabels: [null, null, null, "Custom"]` | Decodes as `[absent, absent, absent, "Custom"]` without failing |
| extension-manifest-024 | view-explicit-null-treated-as-withdrawn | A view entry with `"when": null` | `when` is absent; `"when"` does NOT appear in the unreadable-keys set (contrast with extension-manifest-006) |
| extension-manifest-025 | view-container-strict-identity-tolerant-decorations | A view container entry with `icon: 42` | Decodes with `id`/`title` intact and `icon` absent; no tracking equivalent to a view's unreadable-keys set exists for a view container |
| extension-manifest-026 | language-model-tool-plain-shape, lenient-array-element-isolation | `languageModelTools: [{ name: "a" }, { name: 123 }]` (second entry's `name` wrong type) | The first tool entry decodes; the second is dropped, with a decoding failure at index `1` |
| extension-manifest-027 | contributions-encode-lossy, decoding-failures-not-encoded | A manifest decoded with one malformed theme (extension-manifest-007), then re-encoded | The re-encoded `themes` list holds only the surviving entries; no decoding-failures field appears anywhere in the output |
| extension-manifest-028 | manifest-and-contributions-are-thread-safe | Two independent decodes of identical manifest bytes, compared for equality | The two results are equal; both values are safe to use across any concurrency boundary |

## Edge Cases

- **Null/empty input**: an empty JSON object `{}` decoded as a manifest MUST
  fail (extension-manifest-001). A manifest with no `contributes` key at
  all MUST behave identically to the empty contributions value
  (**contributions-absent-vs-empty-equivalence**). `enumItemLabels: []`
  (present but empty, not absent) MUST decode to an empty list, not
  absent.
- **Boundary/malformed values**: `activationEvents`/`extensionKind`/`capabilities`
  of the wrong JSON type MUST be tolerated (extension-manifest-013/014/015).
  A `themes`/`commands`/... entry that is a single JSON object rather than
  an array MUST be accepted as a one-element array (extension-manifest-010).
  A configuration property that spells nullability as `[X, null]` instead
  of `[X, "null"]` MUST collapse identically to the string form
  (extension-manifest-022). Deeply nested/recursive generic-JSON input has
  no depth guard anywhere in this component — a pathologically deep
  manifest MAY recurse as far as the JSON itself nests, bounded only by the
  underlying decoder's own container-decoding limits, not by any check this
  component adds.
- **Concurrent access**: a manifest, its contributions value, and every
  nested type are immutable, side-effect-free values; decoding a manifest
  allocates its own encode/decode pair per call and touches no shared
  mutable state, so concurrent, independent decode calls on independent
  inputs MUST NOT require external synchronization.
- **Error states**: A malformed `name`, `version`, `engines.vscode`, or
  `contributes` shape MUST sink the entire decode
  (**top-level-identity-required**, **contributes-strict**); every other
  malformed field MUST instead resolve to its type's absence value
  (absent/empty list/empty dictionary) — with a recorded decoding failure
  for most of them, but silently and with no decoding failure at all for a
  command entry's `icon`, every configuration property field, and a view
  container's `icon`/`when` (see Design Decisions).
- **Offline/disconnected state**: Not applicable — this component performs
  no network or file I/O of its own; decoding a manifest operates purely on
  the input its caller already obtained, with no network, file-system, or
  process call anywhere in this component.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| JSON payload | the manifest's raw JSON bytes | none — required | The sole input. A caller constructs its own JSON decoder and decodes it as a manifest; this component defines no custom key-decoding strategy, date-decoding strategy, or extra decode context of its own. |

No environment variable, settings key, or injected dependency exists
anywhere in this component. The lenient array/dictionary/value helpers'
key arguments (e.g. the literal string `"contributes.themes"`) are fixed
at each call site, not runtime configuration a caller can vary.

## Deep Linking

Not applicable: this component defines no URL scheme, universal link, or
intent handling of any kind — it decodes and encodes in-memory JSON values
only.

## Localization

| String | Text | Source |
|--------|------|--------|
| missing-key reason | `no "<key>"` | the failure-text renderer |
| type-mismatch reason, named type | `<subject> is not <name>` | the failure-text renderer |
| type-mismatch reason, unnamed type | `<subject> is the wrong kind of value` | the failure-text renderer |
| missing-value reason | `<subject> is null` | the failure-text renderer |
| corrupted-data reason | the underlying decoder's own description text | the failure-text renderer |
| array-shape guard | `expected an array` | the lenient array/dictionary helper |
| object-shape guard | `expected an object` | the lenient array/dictionary helper |
| empty-path subject | `this entry` | the subject resolver |
| non-empty-path subject | `"<path>"` | the subject resolver |
| JSON noun: text | `text` | the JSON-noun lookup |
| JSON noun: boolean | `true or false` | the JSON-noun lookup |
| JSON noun: floating-point number | `a number` | the JSON-noun lookup |
| JSON noun: whole number | `a whole number` | the JSON-noun lookup |
| JSON noun: object | `an object` | the JSON-noun lookup |
| JSON noun: array | `a list` | the JSON-noun lookup |

Every string above is hardcoded English with no lookup table, ICU message,
or locale parameter anywhere in this component — there is no localization
mechanism in this component at all. This is a plain fact about the source,
not a gap: the failure reason is rendered verbatim by a separate,
out-of-scope component (the source's own doc comment names "the settings
panel's Decisions group"), and a port to a platform with an i18n layer MUST
decide, as a design choice outside this contract, whether and how to route
these strings through it.

## Accessibility Options

Not applicable: this component renders no UI and reads no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color signal anywhere — those
act on whatever UI a host later builds from a decoded manifest, not on this
decoder.

## Feature Flags

Not applicable: no field, function, or comment in this component reads a
feature-flag key — every leniency/strictness decision in this component is
a fixed, compile-time choice, never a runtime flag.

## Analytics

Not applicable: no part of this component emits a client-side analytics or
telemetry event — a decoding failure is diagnostic data this component
returns to its caller, not an event it fires (see Logging).

## Privacy

Not applicable: every value this component decodes or encodes is
extension-authored manifest metadata (`name`, `publisher`, `version`,
declared contributions, and decode-failure text) — no credential, token, or
end-user PII is read, stored, or transmitted by any part of this component.

## Logging

Not applicable: no logging call of any kind appears anywhere in this
component. The recorded decoding failures are structured data this
component returns to its caller rather than logs — the source's own doc
comment states the failure reason is rendered verbatim by "the settings
panel's Decisions group," a separate component outside this component's
scope that may do its own logging or presentation; this component itself
writes no log line.

## Platform Notes

- **Swift (source)**: This component targets macOS today, via the
  `AgenticToolkitCore` framework target (`project.yml`); nothing in it —
  plain `Codable`/`Sendable` structs and enums over Foundation's
  `JSONDecoder`/`JSONEncoder` — depends on `AppKit`, `UIKit`, or any other
  platform framework, so the same source would decode identically if the
  target grew an iOS platform tomorrow. Every field and value type in this
  file is `Codable`; the top-level identity fields (`name`, `version`,
  `engines.vscode`, `contributes`) are decoded with `container.decode`/`decodeIfPresent`
  with no `try?`, while every other optional or per-element field is
  decoded via `try?` (or the equivalent per-element `LenientDecoding.array`/`.dictionary`/`.value`
  helpers), which is the Swift mechanism behind every "independently
  tolerant" requirement above. `JSONValue` is declared nested as
  `ExtensionManifest.JSONValue` rather than as a bare top-level type,
  because a bare top-level `public enum JSONValue` in this module is
  flagged `duplicate_name` by `abstractr check --content-file` against the
  sibling foundation tier `AgenticToolkitSync`'s own top-level `JSONValue`.
  `describe(_:)` switches on the four `DecodingError` cases (`.keyNotFound`,
  `.typeMismatch`, `.valueNotFound`, `.dataCorrupted`) plus a catch-all for
  `DecodingError.@unknown default` and any non-`DecodingError` `Error`,
  rendering `error.localizedDescription` for the latter.
  `decodingFailures`/`Contributions.decodingFailures` are excluded from
  `CodingKeys` so `Encodable` synthesis never emits them. `ExtensionManifest`,
  `Contributions`, and every nested type are declared `Sendable` and
  `Equatable` with no `actor` or `@MainActor` isolation, matching
  `manifest-and-contributions-are-thread-safe`. The ~275ms-per-100-extension
  recovery-path cost cited in `lenient-array-strict-first-perf-rationale`
  was measured as main-actor CPU time in `ExtensionRegistryTests`' `F52`
  benchmark.
- **React/Web/TypeScript**: A hand-rolled parser, or a schema library such
  as `zod`/`io-ts`, replaces `Codable`; the same per-element try/catch-and-continue
  loop `LenientDecoding.array`/`.dictionary` implement is idiomatic
  TypeScript (a `for` loop wrapping each element's `schema.parse` in its own
  `try { } catch { }`), and a discriminated union is the equivalent of
  `PropertyType`.
- **Compose/Android (Kotlin)**: `kotlinx.serialization` with a custom
  `KSerializer`, or Moshi/Gson with a custom `JsonAdapter`, replaces
  `Codable`; a `sealed interface` with `data class`/`object` cases is the
  equivalent of `JSONValue`, and the same strict-first/per-element-fallback
  pattern is implemented by catching `SerializationException` around each
  array element's own `Json.decodeFromJsonElement` call.
- **WinUI 3 (C#)**: `System.Text.Json` (`JsonSerializer`, `JsonDocument`,
  `JsonElement`) replaces `Codable`; `System.Text.Json.Nodes.JsonNode` is the
  equivalent of `JSONValue`. A custom `JsonConverter<T>` per contribution
  type, reading via `Utf8JsonReader`/`JsonElement` and wrapping each
  element's conversion in its own `try`/`catch (JsonException)`, is the
  equivalent of `LenientDecoding.array`/`.dictionary`'s per-element
  isolation; a `record` with nullable properties plays the role of this
  file's `try?`-decoded optional fields, and an immutable `record` — never
  an `ObservableCollection<T>`, which nothing in this file's contract needs
  — is the equivalent of the `Sendable`, value-type `Contributions`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifest.swift` |

## Design Decisions

**Decision**: Silent-drop tolerance for optional fields is not uniform
across this file — `Command.icon`'s object-form fallback and every
`ConfigurationProperty` field drop a wrong-typed value with no
`DecodingFailure` recorded anywhere; `View`'s equivalent fields (`when`,
`type`, `icon`, `contextualTitle`, `visibility`, `initialSize`) drop the
value into the primary field's `nil` AND separately append the field's
`CodingKeys` name to `unreadableKeys`; `ViewContainer.icon`/`.when` drop
silently with no tracking of any kind.
**Rationale**: Each tier is justified separately in the source's own doc
comments by a different cost/benefit: `Command.icon` because the dropped
decoration is "the smaller loss, and the only one this host can act on";
`ConfigurationProperty` because a corpus of 7,464 properties showed only
`order` and `markdownDescription` ever fail strict decoding, so per-field
failure tracking would buy nothing measurable; `View` because "a view
becomes a registered, always-offered pane" whose dropped declarations are
worth surfacing; `ViewContainer` explicitly because "nothing renders a
container yet... adding it now would be a property with no reader." This
asymmetry sits in real tension with `DecodingFailure`'s own top-of-file doc
comment claim that the manifest "never drops the failure silently either" — that claim holds for every `contributes.*` array/dictionary
entry, which is what `DecodingFailure` exists to describe, but not for every
optional scalar field inside a surviving entry, which this file treats as a
different, cheaper class of loss.
**Approved**: pending

**Decision**: `LenientDecoding.array`/`.dictionary` always attempt one
whole-value strict decode before falling back to the per-element `JSONValue`
round-trip recovery path.
**Rationale**: Measured on a 100-extension synthetic benchmark
(`ExtensionRegistryTests`' `F52`; 4 themes/12 commands/20 configuration
properties each), the per-element recovery path costs ~275ms of main-actor
CPU against ~4ms of file I/O — the launch stall `F52` exists to describe.
Trying strict first means a well-formed manifest, which is nearly every
manifest, never pays that cost; the recovery path exists purely to isolate
the manifest that does fail, and runs if and only if the strict attempt
throws.
**Approved**: pending

**Decision**: `JSONValue` is declared nested as `ExtensionManifest.JSONValue`
rather than as a bare top-level type.
**Rationale**: A bare top-level `public enum JSONValue` in this module is
flagged `duplicate_name` by `abstractr check --content-file` against the
sibling foundation tier `AgenticToolkitSync`'s own top-level `JSONValue` —
`apple-sync` and `apple-core` are declared sibling foundation tiers in
`.abstractr.json`, not a tier/sub-tier pair, so nesting rather than renaming
resolves the collision without introducing a downward dependency between
them.
**Approved**: pending

**Decision**: `Keybinding` does not model VS Code's `args` field.
**Rationale**: `CommandRegistry.execute` accepts no arguments today, so
carrying `args` would be a field this host cannot honor. The source's own
trailing comment states this plainly: "carrying a field this host cannot
honour is worse than not carrying it. This was a decision, not an
oversight; revisit when a consumer needs it."
**Approved**: pending

**Decision**: `contributes` decodes strictly, even though every field inside
the `Contributions` it produces is itself lenient.
**Rationale**: The source names a pinned test guarding this exact boundary
— the question of what should happen when a manifest's `contributes`
key is present but the wrong JSON shape entirely (not one malformed entry,
but a `contributes` that is, say, a bare string) is closed by that test,
which the source's comment states exists "to forbid" treating such a
manifest as though it declared nothing. Leniency is reserved for entries
within a well-shaped `contributes` object, not for the object's own shape.
**Approved**: pending

**Decision**: `Language.mimetypes` and `Configuration.id` are carried even
though nothing in this host currently acts on either.
**Rationale**: Both fields' doc comments give the same justification:
dropping them would make an entry that declared one indistinguishable from
an entry that declared nothing at all, and a future reader should be able
to tell "not carried" apart from "carried, not yet acted on" without
re-deriving the answer from the manifest bytes.
**Approved**: pending

**Decision**: `View.unreadableKeys` is covered by `View`'s synthesized
`Equatable` conformance even though it is excluded from `CodingKeys` and
therefore from `Encodable`.
**Rationale**: Swift's `Equatable` synthesis is not selective the way
`Encodable`'s `CodingKeys`-driven synthesis is — there is no mechanism to
exclude one stored property from a synthesized `==` while keeping the rest.
The consequence, stated in the source itself, is that "`View` equality is no
longer a statement about manifest content alone": two `View` values decoded
from byte-identical JSON under different decode conditions could compare
unequal purely on `unreadableKeys`, not on any field a caller would call
"the view's content."
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`explicit-error-handling` is **partial**: every `contributes.*` array/dictionary
entry failure is recorded as a typed `DecodingFailure` the caller can act on,
but `Command.icon`'s object-form fallback and every `ConfigurationProperty`
field drop a wrong-typed value with no `DecodingFailure` recorded anywhere
— a real, documented gap between `DecodingFailure`'s own doc comment claim
and its leaf-type behavior (see Design Decisions). `fault-tolerance`
**passed**: `LenientDecoding.array`/`.dictionary`/`.value` isolate failures
at array-element, keyed-location, and single-field granularity throughout,
so one malformed entry never sinks a sibling. `data-integrity` is
**partial**: `Contributions.encode(to:)` is deliberately lossy — it omits
`decodingFailures` and every entry that failed to decode — so a round-trip
through this type is not a faithful copy of the manifest that was decoded
(**contributions-encode-lossy**). `idempotent-operations` **passed**:
decoding is a pure function of its input `Data`; two decodes of
byte-identical JSON produce `Equatable`-equal values.
`separation-of-concerns` **passed**: the element/location-isolation logic
lives once in `LenientDecoding`, shared by both `ExtensionManifest.init(from:)`
and `Contributions.init(from:)`, rather than duplicated per contribution
type. `unit-test-coverage` **passed**: `ExtensionManifestTests.swift`
exercises identity strictness, every lenient top-level field, single-object
tolerance, per-element and per-location isolation, the tri-state capability
decode, case-folded identifiers, and the `unreadableKeys` encode exclusion.
`no-hardcoded-strings` **failed**: every `describe(_:)`/`jsonName(of:)`
string is hardcoded English with no lookup table or locale parameter
anywhere in this file (see Localization) — a plain, honestly-reported gap in
the source, not a hidden one.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/manifest/. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
