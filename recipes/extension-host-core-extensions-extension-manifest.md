---
id: 68d182dc-3fc0-489c-ab04-ff4da25fc4df
title: ExtensionManifest
domain: agentictoolkit://recipes/extension-host-core-extensions-extension-manifest
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Codable model of a VS Code package.json: strict identity, element-isolated
  lenient decoding of contributes.* entries, typed DecodingFailure diagnostics.'
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

# ExtensionManifest

## Overview

`ExtensionManifest` is the `Codable` model of a VS Code `package.json` inside
`AgenticToolkitCore` (`packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifest.swift`,
a macOS-only framework target per `project.yml`). It has no visual surface of
its own: it is a pure, synchronous decode/encode layer — everything Stage 4c
and Stages 5-7 of the extension host read to install themes, snippets,
languages, commands, keybindings, menus, settings, views, view containers,
and (later) language-model tools comes from the `Contributions` value this
type decodes. Its defining discipline is asymmetric strictness: `name`,
`version`, `engines.vscode`, and `contributes`'s own shape are the
extension's non-negotiable identity, and a manifest missing or misspelling
any of them fails to decode entirely; everything else — every
`contributes.*` array element, every keyed-dictionary location, every
optional scalar field — is decoded with element- or field-level isolation,
so one malformed theme, command, or configuration property never costs its
siblings. A companion `LenientDecoding` helper implements that isolation
once, shared by every `contributes.*` collection, and a typed
`DecodingFailure` record — never itself re-encoded — is how a caller learns
what, if anything, one decode attempt had to drop.

## Behavioral Requirements

- **decodes-vscode-package-json-subset**: `ExtensionManifest` MUST decode as
  a `Codable` subset of a VS Code `package.json` using a plain
  `JSONDecoder()` with no custom `keyDecodingStrategy`, `dateDecodingStrategy`,
  or `userInfo`.
- **top-level-identity-required**: `init(from:)` MUST throw when `name`,
  `version`, or `engines.vscode` is missing or the wrong JSON type — each is
  decoded with `container.decode`, never `decodeIfPresent` or `try?` (206; `ExtensionManifestTests.missingNameFails`).
- **identity-decoded-before-lenient-fields**: `init(from:)` MUST decode
  `name`, `publisher`, `version`, `displayName`, `description`, `engines`,
  `main`, and `browser` before attempting `activationEvents`,
  `extensionKind`, `capabilities`, or `contributes`, so the manifest's own
  name is always available before any field that can independently fail is
  attempted.
- **optional-descriptive-fields-decode-if-present**: `publisher`,
  `displayName`, `description`, `main`, and `browser` MUST decode via
  `decodeIfPresent`, yielding `nil` when the key is absent or JSON `null`,
  and MUST throw — sinking the whole decode — if the key is present with an
  incompatible JSON type.
- **engines-vscode-required**: `Engines` MUST require a `vscode` string
  field; an `engines` object omitting `vscode`, or giving it a non-string
  value, MUST fail the whole manifest decode.
- **display-identifier-composition**: `displayIdentifier` MUST return
  `` "\(publisher).\(name)" `` when `publisher` is non-nil, and MUST return
  `name` unchanged when `publisher` is `nil`.
- **identifier-case-folding**: `identifier` MUST return
  `displayIdentifier.lowercased()`; two manifests whose `publisher`/`name`
  differ only in case MUST produce the same `identifier` while each keeps its
  own distinct `displayIdentifier` (`ExtensionManifestTests.identifierFoldsCase`).
- **activation-events-defaults-empty**: `activationEvents` MUST default to
  `[]`, never `nil`, when the key is absent, because VS Code 1.74+ infers
  activation from `contributes` and an extension relying on that inference
  omits the key entirely (`decodesMinimalManifest`).
- **activation-events-tolerant**: A present `activationEvents` value that is
  not an array of strings MUST NOT fail the manifest decode; it MUST resolve
  to `[]` and record exactly one `DecodingFailure` keyed `"activationEvents"`
  (`unreadableActivationEventsDoesNotSinkTheManifest`).
- **extension-kind-nil-means-absent**: `extensionKind` MUST be `nil`, not
  `[]`, when the key is absent or its value is unreadable — `[]` is reserved
  for a manifest that explicitly declares it runs in no extension host at
  all.
- **extension-kind-tolerant**: A present `extensionKind` value that is not an
  array of strings MUST NOT fail the manifest decode; it MUST resolve to
  `nil` and record exactly one `DecodingFailure` keyed `"extensionKind"`
  (`unreadableExtensionKindDoesNotSinkTheManifest`).
- **capabilities-tolerant**: A present `capabilities` value that fails to
  decode as `Capabilities` MUST NOT fail the manifest decode; it MUST
  resolve to `nil` and record exactly one `DecodingFailure` keyed
  `"capabilities"` (`unreadableCapabilitiesDoesNotSinkTheManifest`
  (marked `F09`)).
- **contributes-strict**: `contributes` MUST decode via
  `decodeIfPresent(Contributions.self, ...)` with no `LenientDecoding`
  wrapper; a present `contributes` key whose shape `Contributions.init(from:)`
  cannot even begin to parse MUST throw and sink the entire manifest decode.
- **untrusted-workspaces-support-tri-form**: `Capabilities.UntrustedWorkspaces.Support`
  MUST decode JSON `true` as `.supported`, JSON `false` as `.unsupported`,
  and the JSON string `"limited"` as `.limited`, and MUST throw for any other
  value; `encode(to:)` MUST invert the same mapping exactly (`untrustedWorkspacesRoundTrips`).
- **decoding-failures-not-encoded**: `ExtensionManifest.decodingFailures` and
  `Contributions.decodingFailures` MUST NOT appear in either type's
  `CodingKeys` and MUST NOT round-trip through `encode(to:)` — they describe
  one decode attempt, not manifest content.
- **contributions-empty-static-value**: `Contributions.empty` MUST be a
  static value with every array `[]`, every dictionary `[:]`, and
  `decodingFailures` `[]`.
- **contributions-absent-vs-empty-equivalence**: A manifest whose
  `contributes` key is entirely absent and a `Contributions` whose own keys
  are all absent MUST be treated as the same statement — "this extension
  declares nothing" — which is what makes `Contributions.empty` a reusable
  stand-in for either case.
- **contributions-arrays-default-empty**: Each of `themes`, `snippets`,
  `languages`, `commands`, `keybindings`, `configuration`, and
  `languageModelTools` MUST default to `[]` when its manifest key is absent
  (271; `decodesMinimalManifest`).
- **contributions-dictionaries-default-empty**: Each of `menus`, `views`,
  and `viewsContainers` MUST default to `[:]` when its manifest key is
  absent (269-270; `decodesMinimalManifest`).
- **contributions-encode-lossy**: `Contributions.encode(to:)` MUST NOT be a
  faithful round-trip of the manifest that was decoded — it MUST omit
  `decodingFailures` (per **decoding-failures-not-encoded**) and MUST omit
  every `contributes.*` entry that failed to decode, since `Contributions`
  never held those entries to begin with.
- **lenient-array-absent-key-returns-empty**: `LenientDecoding.array` MUST
  return `[]` without recording a `DecodingFailure` when
  `container.contains(key)` is `false`.
- **lenient-array-strict-fast-path**: `LenientDecoding.array` MUST first
  attempt `container.decode([Element].self, forKey: key)` and return that
  result directly when it succeeds, without building any `JSONValue`
  intermediate.
- **lenient-array-single-object-tolerance**: When the strict array decode
  fails, `LenientDecoding.array` MUST accept a single JSON object in place of
  a one-element array — decoded as one `JSONValue.object` and treated as a
  one-element array — for every array-shaped `contributes` key, including
  ones (`commands`, `themes`) whose own VS Code schema requires strictly an
  array (`singleObjectConfigurationDecodes`).
- **lenient-array-non-array-non-object-failure**: When the manifest value
  for the key is neither an array nor a single JSON object,
  `LenientDecoding.array` MUST return `[]` and record exactly one
  `DecodingFailure` for that key with `index: nil` and
  `reason: "expected an array"`.
- **lenient-array-element-isolation**: Once the array is obtained (strictly,
  or via the recovery path), each element MUST be decoded independently by
  round-tripping it through one shared `JSONEncoder`/`JSONDecoder` pair
  created once for the whole call; an element that fails to decode as
  `Element` MUST be dropped from the result and recorded as one
  `DecodingFailure` carrying that element's `index`, while every other
  element in the same array MUST still decode (`malformedThemeIsIsolated`).
- **lenient-array-strict-first-perf-rationale**: The whole-array strict
  decode attempt MUST run before the per-element recovery path, and the
  recovery path MUST run only when the strict attempt throws — measured at
  ~275ms of main-actor CPU for the recovery path against ~4ms of file I/O on
  a 100-synthetic-extension benchmark (`ExtensionRegistryTests`' `F52`), so a
  well-formed manifest MUST NOT pay the per-element round-trip cost.
- **lenient-dictionary-absent-key-returns-empty**: `LenientDecoding.dictionary`
  MUST return `[:]` without recording a `DecodingFailure` when
  `container.contains(key)` is `false`.
- **lenient-dictionary-strict-fast-path**: `LenientDecoding.dictionary` MUST
  first attempt `container.decode([String: [Element]].self, forKey: key)`
  and return it directly when it succeeds.
- **lenient-dictionary-whole-value-failure**: When the manifest value for the
  key cannot decode as `[String: JSONValue]` at all,
  `LenientDecoding.dictionary` MUST return `[:]` and record exactly one
  `DecodingFailure` for the bare `manifestKeyPrefix`, with `index: nil` and
  `reason: "expected an object"`.
- **lenient-dictionary-location-isolation**: For each location key in the
  decoded `[String: JSONValue]`, a value that is not itself a JSON array
  MUST be skipped and recorded as one `DecodingFailure` keyed
  `` "\(manifestKeyPrefix).\(location)" `` with `index: nil`, while every
  other location in the same dictionary MUST still decode (`keyedLocationThatIsNotAnArrayIsIsolated`).
- **lenient-dictionary-element-isolation**: Within one location's array, each
  element MUST decode independently the same way `LenientDecoding.array`
  does; an element that fails MUST be recorded as one `DecodingFailure` keyed
  `` "\(manifestKeyPrefix).\(location)" `` with that element's `index`, while
  sibling elements in the same location MUST still decode (`malformedElementInsideAKeyedLocationIsIsolated`).
- **lenient-value-absent-vs-unreadable**: `LenientDecoding.value` MUST return
  `nil` without recording a `DecodingFailure` when the key is absent, and
  MUST return `nil` while recording exactly one `DecodingFailure` when the
  key is present but the value's own decode throws.
- **decoding-failure-text-key-not-found**: `describe(_:)` MUST render a
  `DecodingError.keyNotFound(key, _)` as `` no “<key>” `` using the missing
  key's `stringValue`.
- **decoding-failure-text-type-mismatch-named**: `describe(_:)` MUST render
  a `DecodingError.typeMismatch(type, context)` as `` <subject> is not
  <name> `` when `jsonName(of:)` resolves a JSON noun for `type` (`malformedThemeIsIsolated`'s `` "uiTheme" is not text ``, and
  `aThemesEntryThatIsNotAnObjectNamesItself`'s `` this entry is not an
  object ``).
- **decoding-failure-text-type-mismatch-unnamed**: `describe(_:)` MUST
  render a `DecodingError.typeMismatch` for a type outside `jsonName(of:)`'s
  table (a first-party `Decodable` with its own `init(from:)`) as
  `` <subject> is the wrong kind of value ``, never interpolating the Swift
  type name.
- **decoding-failure-text-value-not-found**: `describe(_:)` MUST render a
  `DecodingError.valueNotFound` as `` <subject> is null ``.
- **decoding-failure-text-data-corrupted**: `describe(_:)` MUST render a
  `DecodingError.dataCorrupted(context)` as `context.debugDescription`
  verbatim.
- **decoding-failure-text-non-decoding-error**: `describe(_:)` MUST render
  any `Error` that is not a `DecodingError` — including
  `DecodingError.@unknown default` — as `error.localizedDescription`.
- **decoding-failure-subject-empty-path**: `subject(of:)` MUST return the
  literal `this entry` when `context.codingPath` is empty, and MUST
  otherwise return the dot-joined coding path wrapped in curly quotes.
- **json-value-shape**: `JSONValue` MUST decode and encode exactly the six
  JSON value kinds — `null`, `bool`, `number` (as `Double`), `string`,
  `array`, and `object` (`[String: JSONValue]`) — trying each case in order
  on decode and throwing only if none match.
- **json-value-nested-not-top-level**: `JSONValue` MUST be declared nested as
  `ExtensionManifest.JSONValue`, never as a bare top-level type, because a
  bare top-level `public enum JSONValue` in this module is flagged
  `duplicate_name` by `abstractr check --content-file` against the sibling
  foundation tier `AgenticToolkitSync`'s own top-level `JSONValue`.
- **theme-strict-shape**: `Theme` MUST require `label`, `uiTheme`, and `path`
  as strings, with no per-field leniency of its own — a malformed field MUST
  fail only that array element, via **lenient-array-element-isolation**,
  never the whole manifest.
- **snippet-strict-shape**: `Snippet` MUST require `language` and `path` as
  strings.
- **language-optional-fields**: `Language` MUST require `id` as a string and
  MUST treat `aliases`, `extensions`, `filenames`, `filenamePatterns`,
  `firstLine`, `mimetypes`, `configuration`, and `icon` as ordinary optional
  `Codable` fields with no per-field tolerance beyond synthesized `Codable`. `mimetypes` MUST be carried even though nothing in this
  host maps a file by MIME type, so an entry that declared only `mimetypes`
  stays distinguishable from one that declared nothing.
- **command-icon-string-form-only**: `Command.icon` MUST decode a plain
  string icon path, and MUST decode to `nil` — dropping the icon with no
  `DecodingFailure` recorded anywhere — when the manifest supplies VS Code's
  object form (`{ light, dark }`) instead, so a themed icon never costs the
  command its `command`, `title`, `category`, or `enablement` (`objectFormCommandIconKeepsTheCommand`).
- **keybinding-args-not-carried**: `Keybinding` MUST expose only `command`,
  `key`, `mac`, and `when`; it MUST NOT carry a manifest's `args` field,
  because nothing in the extension host's command dispatch
  (`CommandRegistry.execute`) accepts arguments today.
- **menu-item-strict-shape**: `MenuItem` MUST require `command` as a string
  and MUST treat `when`, `group`, and `alt` as ordinary optional fields.
- **configuration-title-id-order-independently-tolerant**:
  `Configuration.title`, `.id`, and `.order` MUST each decode via an
  independent `try?`, so a wrong-typed value in any one of the three (e.g.
  `order` spelled as the string `"0"`) MUST resolve only that field to
  `nil`, never prevent the other two fields or `properties` from decoding.
- **configuration-properties-per-property-isolation**:
  `Configuration.properties` MUST decode each property key one at a time
  from a nested keyed container using an independent `try?` per property; a
  property whose value cannot decode as `ConfigurationProperty` MUST be
  dropped from the dictionary while every sibling property in the same
  section MUST still decode.
- **configuration-property-type-single-or-union**:
  `ConfigurationProperty.PropertyType` MUST decode a single JSON Schema type
  name as `.single(name)`, and MUST decode a JSON array of type names as
  `.union(members)` with every non-string member dropped from `members`.
- **configuration-property-effective-type-collapse**:
  `ConfigurationProperty.effectiveType` MUST return the single non-`"null"`
  member of a `.union` when exactly one distinct such member exists, and
  MUST return `nil` when zero or more than one distinct non-`"null"` member
  remains; for `.single(name)` it MUST return `name` unchanged, and for a
  `nil` `type` it MUST return `nil`.
- **configuration-property-every-field-independently-tolerant**: Every one
  of `ConfigurationProperty`'s decoded fields (`type`, `default`,
  `description`, `markdownDescription`, `enum`, `enumDescriptions`,
  `markdownEnumDescriptions`, `enumItemLabels`, `scope`, `order`, `minimum`,
  `maximum`, `deprecationMessage`, `markdownDeprecationMessage`,
  `editPresentation`) MUST decode via its own independent `try?`, so a
  wrong-typed value in any one field MUST resolve only that field to `nil`,
  never fail the property or its section.
- **configuration-property-enum-item-labels-nullable-elements**:
  `ConfigurationProperty.enumItemLabels`, when present, MUST decode as
  `[String?]` — an individual element may be JSON `null`, preserved as `nil`
  at that position, rather than failing the whole array.
- **view-identity-strict-decorations-tolerant**: `View.id` and `.name` MUST
  decode strictly — a `View` missing either MUST fail that array element,
  via **lenient-dictionary-element-isolation**; `.when`, `.type`, `.icon`,
  `.contextualTitle`, `.visibility`, and `.initialSize` MUST each decode
  through the local `read()` helper, independently tolerant of a wrong type.
- **view-unreadable-keys-recorded-per-field**: `View.unreadableKeys` MUST
  list the `CodingKeys` name of every optional field that was present in the
  manifest but could not be decoded to its declared type; a key that was
  absent entirely MUST NOT appear in `unreadableKeys` (985-1004;
  `unreadableKeysAreNotEncoded`).
- **view-explicit-null-treated-as-withdrawn**: `View`'s `read()` helper MUST
  treat an explicit JSON `null` for an optional field as the field being
  withdrawn — resolving to `nil` and NOT appending the key to
  `unreadableKeys` — distinct from a present-and-unreadable value, which
  resolves to `nil` AND appends the key.
- **view-unreadable-keys-not-encoded**: `View.unreadableKeys` MUST have no
  `CodingKeys` case and MUST NOT appear in the JSON produced by
  `View.encode(to:)` (960-963; `unreadableKeysAreNotEncoded`).
- **view-container-strict-identity-tolerant-decorations**:
  `ViewContainer.id` and `.title` MUST decode strictly; `.icon` and `.when`
  MUST each decode via an independent `try?`, resolving to `nil` on a type
  mismatch without failing the container and with no tracking equivalent to
  `View.unreadableKeys`.
- **language-model-tool-plain-shape**: `LanguageModelTool` MUST decode
  `name`, `displayName`, `modelDescription`, `toolReferenceName`,
  `inputSchema` (`JSONValue?`), `tags` (`[String]?`), and
  `canBeReferencedInPrompt` (`Bool?`) via synthesized `Codable` with no
  custom `init(from:)`; a malformed field anywhere in one tool entry MUST
  fail only that entry's array element, via
  **lenient-array-element-isolation**, never a sibling tool.
- **manifest-and-contributions-are-sendable-value-types**:
  `ExtensionManifest`, `Contributions`, and every nested type MUST be
  declared `Sendable` and `Equatable` value types with no `actor` or
  `@MainActor` isolation; decoding MUST be a synchronous, side-effect-free
  function of the `Decoder` handed to it, with no file, network, or process
  access anywhere in this file, so a decoded value MAY be passed freely
  across concurrency domains and MAY be decoded concurrently by independent
  callers without coordination (every type declaration in the file).

## Appearance

Not applicable — this is a manifest decoder, not a visual component.

## States

Not applicable — this is a manifest decoder, not a visual component.

## Accessibility

Not applicable — this is a manifest decoder, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-manifest-001 | top-level-identity-required | `{}` decoded as `ExtensionManifest` | Throws (`missingNameFails`) |
| extension-manifest-002 | decodes-vscode-package-json-subset, identity-decoded-before-lenient-fields | Full manifest fixture with every top-level field present | Decodes without throwing; every field populated matching the fixture (`decodesFullManifest`) |
| extension-manifest-003 | activation-events-defaults-empty, extension-kind-nil-means-absent, contributions-arrays-default-empty, contributions-dictionaries-default-empty | Minimal manifest of only `name`, `version`, `engines` | `activationEvents == []`; `extensionKind == nil`; every `Contributions` collection empty (`decodesMinimalManifest`) |
| extension-manifest-004 | identifier-case-folding, display-identifier-composition | `publisher: "Acme"`/`name: "Kitchen-Sink"` vs `publisher: "acme"`/`name: "kitchen-sink"` | Both produce `identifier == "acme.kitchen-sink"`; each keeps its own distinct `displayIdentifier` (`identifierFoldsCase`, marked `F39`) |
| extension-manifest-005 | untrusted-workspaces-support-tri-form | `untrustedWorkspaces.supported` as JSON `true`, `false`, `"limited"` | Decodes to `.supported`, `.unsupported`, `.limited`; re-encodes to the same JSON form (`untrustedWorkspacesRoundTrips`) |
| extension-manifest-006 | view-unreadable-keys-recorded-per-field, view-unreadable-keys-not-encoded | A `View` entry with `initialSize` spelled as the JSON string `"2"` | `initialSize == nil`; `unreadableKeys == ["initialSize"]`; re-encoded JSON has no `unreadableKeys` key (`unreadableKeysAreNotEncoded`) |
| extension-manifest-007 | lenient-array-element-isolation, decoding-failure-text-type-mismatch-named | `themes: [{ label: "Night", uiTheme: 123, path: "night.json" }]` (`uiTheme` wrong type) | That theme dropped; one `DecodingFailure(key: "contributes.themes", index: 0, reason: ...)`; manifest still decodes (`malformedThemeIsIsolated`) |
| extension-manifest-008 | lenient-array-element-isolation, decoding-failure-subject-empty-path, decoding-failure-text-type-mismatch-named | `themes: ["night.json"]` (element is a bare string, not an object) | That element dropped; `DecodingFailure(key: "contributes.themes", index: 0, reason: "this entry is not an object")` (`aThemesEntryThatIsNotAnObjectNamesItself`) |
| extension-manifest-009 | command-icon-string-form-only | `commands: [{ command: "c", title: "T", icon: { light: "l.svg", dark: "d.svg" } }]` | Command decodes with `icon == nil`; no `DecodingFailure` recorded for it; `command`/`title` intact (`objectFormCommandIconKeepsTheCommand`) |
| extension-manifest-010 | lenient-array-single-object-tolerance | `configuration: { title: "T", properties: { "x.y": { type: "string" } } }` (single object, not an array) | Decodes as a one-element `[Configuration]` (`singleObjectConfigurationDecodes`) |
| extension-manifest-011 | lenient-dictionary-location-isolation | `menus: { commandPalette: [...], "bad.location": "not-an-array" }` | `"bad.location"` skipped with `DecodingFailure(key: "contributes.menus.bad.location", index: nil, reason: "expected an array")`; `commandPalette` still decodes (`keyedLocationThatIsNotAnArrayIsIsolated`) |
| extension-manifest-012 | lenient-dictionary-element-isolation | `menus: { commandPalette: [{ command: "a" }, { when: 123 }] }` (second element malformed) | First element decodes; second dropped with a `DecodingFailure` at `index: 1` (`malformedElementInsideAKeyedLocationIsIsolated`) |
| extension-manifest-013 | capabilities-tolerant | `capabilities: "not-an-object"` | Manifest still decodes; `capabilities == nil`; `DecodingFailure(key: "capabilities", ...)` recorded (`unreadableCapabilitiesDoesNotSinkTheManifest`, marked `F09`) |
| extension-manifest-014 | extension-kind-tolerant | `extensionKind: "not-an-array"` | Manifest still decodes; `extensionKind == nil`; `DecodingFailure(key: "extensionKind", ...)` recorded (`unreadableExtensionKindDoesNotSinkTheManifest`) |
| extension-manifest-015 | activation-events-tolerant | `activationEvents: { not: "an array" }` | Manifest still decodes; `activationEvents == []`; `DecodingFailure(key: "activationEvents", ...)` recorded (`unreadableActivationEventsDoesNotSinkTheManifest`) |
| extension-manifest-016 | contributes-strict | `contributes: "not-an-object"` | Whole manifest decode throws (derived from the strict `decodeIfPresent` call and its adjoining comment naming a pinned test) |
| extension-manifest-017 | lenient-array-absent-key-returns-empty, lenient-dictionary-absent-key-returns-empty | `contributes: {}` (no keys at all) | Every array field `[]`, every dictionary field `[:]`, `decodingFailures == []` (derived from `Contributions.init(from:)`'s guards) |
| extension-manifest-018 | json-value-shape | Raw JSON `null`, `true`, `42`, `"s"`, `[1,2]`, `{"a":1}` each decoded as `JSONValue` | `.null`, `.bool(true)`, `.number(42)`, `.string("s")`, `.array([...])`, `.object([...])` respectively (derived from `JSONValue.init(from:)`) |
| extension-manifest-019 | configuration-title-id-order-independently-tolerant | `configuration: [{ title: "T", order: "0", properties: {} }]` (`order` spelled as a string) | Section decodes with `order == nil`; `title == "T"` intact; `properties` still populated (derived from the source's own corpus example) |
| extension-manifest-020 | configuration-properties-per-property-isolation | `properties: { "a.b": { type: "string" }, "c.d": 123 }` (second property is a bare number) | `properties["a.b"]` decodes; `properties["c.d"]` absent from the dictionary, no failure recorded |
| extension-manifest-021 | configuration-property-type-single-or-union | `type: "string"` and `type: ["number", "null"]` | `.single("string")` and `.union(["number"])` respectively |
| extension-manifest-022 | configuration-property-effective-type-collapse | `type: ["number", null]` (a literal JSON null member, not the string `"null"`) | `.union(["number"])` after dropping the non-string member; `effectiveType == "number"` (derived from the source's own corpus example) |
| extension-manifest-023 | configuration-property-enum-item-labels-nullable-elements | `enumItemLabels: [null, null, null, "Custom"]` | Decodes as `[nil, nil, nil, "Custom"]` without throwing |
| extension-manifest-024 | view-explicit-null-treated-as-withdrawn | A `View` entry with `"when": null` | `when == nil`; `"when"` does NOT appear in `unreadableKeys` (contrast with extension-manifest-006) |
| extension-manifest-025 | view-container-strict-identity-tolerant-decorations | A `ViewContainer` entry with `icon: 42` | Decodes with `id`/`title` intact and `icon == nil`; no tracking equivalent to `unreadableKeys` exists for it |
| extension-manifest-026 | language-model-tool-plain-shape, lenient-array-element-isolation | `languageModelTools: [{ name: "a" }, { name: 123 }]` (second entry's `name` wrong type) | First tool decodes; second dropped with a `DecodingFailure` at `index: 1` |
| extension-manifest-027 | contributions-encode-lossy, decoding-failures-not-encoded | A manifest decoded with one malformed theme (extension-manifest-007), then re-encoded via `Contributions.encode(to:)` | Re-encoded `themes` array holds only the surviving entries; no `decodingFailures` key appears anywhere in the output |
| extension-manifest-028 | manifest-and-contributions-are-sendable-value-types | Two independent `JSONDecoder().decode(ExtensionManifest.self, from:)` calls on identical `Data`, compared with `==` | Equal, via synthesized `Equatable`; both values freely `Sendable` |

## Edge Cases

- **Null/empty input**: `{}` decoded as `ExtensionManifest` MUST throw
  (extension-manifest-001). A manifest with no `contributes` key at all MUST
  behave identically to `Contributions.empty` (**contributions-absent-vs-empty-equivalence**).
  `enumItemLabels: []` (present but empty, not absent) MUST decode to `[]`,
  not `nil`.
- **Boundary/malformed values**: `activationEvents`/`extensionKind`/`capabilities`
  of the wrong JSON type MUST be tolerated (extension-manifest-013/014/015).
  A `themes`/`commands`/... entry that is a single JSON object rather than
  an array MUST be accepted as a one-element array (extension-manifest-010).
  A `contributes.configuration` property that spells nullability as
  `[X, null]` instead of `[X, "null"]` MUST collapse identically to the
  string form (extension-manifest-022). Deeply nested/recursive `JSONValue`
  input has no depth guard anywhere in this file — a pathologically deep
  manifest MAY recurse as far as the JSON itself nests, bounded only by
  `JSONDecoder`'s own container-decoding limits, not by any check this file
  adds.
- **Concurrent access**: `ExtensionManifest`/`Contributions`/every nested
  type is a `Sendable`, side-effect-free value type; `init(from:)` allocates
  its own `JSONEncoder`/`JSONDecoder` pair per call
  and touches no shared mutable state, so concurrent, independent decode
  calls on independent `Decoder`s MUST NOT require external synchronization.
- **Error states**: A malformed `name`, `version`, `engines.vscode`, or
  `contributes` shape MUST sink the entire decode
  (**top-level-identity-required**, **contributes-strict**); every other
  malformed field MUST instead resolve to its type's absence value
  (`nil`/`[]`/`[:]`) — with a recorded `DecodingFailure` for most of them,
  but silently and with no `DecodingFailure` at all for `Command.icon`,
  every `ConfigurationProperty` field, and `ViewContainer.icon`/`.when` (see
  Design Decisions).
- **Offline/disconnected state**: Not applicable — this file performs no
  network or file I/O of its own; `init(from:)` operates purely on the
  `Decoder` its caller already obtained, with no `URLSession`,
  `FileManager`, or process call anywhere in `ExtensionManifest.swift`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| JSON payload | `Data` (via a `Decoder`) | none — required | The sole input. A caller constructs its own `JSONDecoder()` and calls `.decode(ExtensionManifest.self, from:)`; this file defines no `keyDecodingStrategy`, `dateDecodingStrategy`, or `userInfo` of its own. |

No environment variable, settings key, or injected dependency exists
anywhere in this file. `LenientDecoding.array`/`.dictionary`/`.value`'s
`manifestKey`/`manifestKeyPrefix` arguments (e.g. the literal string
`"contributes.themes"`) are compile-time literals fixed at each call site
inside `Contributions.init(from:)`, not runtime configuration a caller can
vary.

## Deep Linking

Not applicable: this file defines no URL scheme, universal link, or intent
handling of any kind — it decodes and encodes in-memory JSON values only.

## Localization

| String | Text | Source |
|--------|------|--------|
| `keyNotFound` reason | `` no “<key>” `` | `describe(_:)` |
| `typeMismatch` reason, named type | `` <subject> is not <name> `` | `describe(_:)` |
| `typeMismatch` reason, unnamed type | `` <subject> is the wrong kind of value `` | `describe(_:)` |
| `valueNotFound` reason | `` <subject> is null `` | `describe(_:)` |
| `dataCorrupted` reason | Foundation's own `context.debugDescription` text | `describe(_:)` |
| array-shape guard | `expected an array` | `LenientDecoding.array`/`.dictionary` |
| object-shape guard | `expected an object` | `LenientDecoding.dictionary` |
| empty-path subject | `this entry` | `subject(of:)` |
| non-empty-path subject | `` “<path>” `` | `subject(of:)` |
| `jsonName` noun: `String` | `text` | `jsonName(of:)` |
| `jsonName` noun: `Bool` | `true or false` | `jsonName(of:)` |
| `jsonName` noun: `Double`/`Float` | `a number` | `jsonName(of:)` |
| `jsonName` noun: `FixedWidthInteger` | `a whole number` | `jsonName(of:)` |
| `jsonName` noun: `[String: Any]` | `an object` | `jsonName(of:)` |
| `jsonName` noun: `[Any]` | `a list` | `jsonName(of:)` |

Every string above is hardcoded English with no lookup table, ICU message,
or locale parameter anywhere in `ExtensionManifest.swift` — there is no
localization mechanism in this file at all. This is a plain fact about the
source, not a gap: `reason` is rendered verbatim by a separate, out-of-scope
component (the source's own doc comment names "the settings
panel's Decisions group"), and a port to a platform with an i18n layer MUST
decide, as a design choice outside this contract, whether and how to route
these strings through it.

## Accessibility Options

Not applicable: this file renders no UI and reads no Reduce Motion, Increase
Contrast, or Differentiate-Without-Color signal anywhere — those act on
whatever UI a host later builds from a decoded manifest, not on this
decoder.

## Feature Flags

Not applicable: no field, function, or comment in `ExtensionManifest.swift`
reads a feature-flag key — every leniency/strictness decision in this file
is a fixed, compile-time choice, never a runtime flag.

## Analytics

Not applicable: no file in this component emits a client-side analytics or
telemetry event — `DecodingFailure` is diagnostic data this file returns to
its caller, not an event it fires (see Logging).

## Privacy

Not applicable: every value this file decodes or encodes is
extension-authored manifest metadata (`name`, `publisher`, `version`,
declared contributions, and decode-failure text) — no credential, token, or
end-user PII is read, stored, or transmitted by any type in
`ExtensionManifest.swift`.

## Logging

Not applicable: no `print`, `os_log`, `Logger`, or `NSLog` call appears
anywhere in `ExtensionManifest.swift`. `decodingFailures`/`DecodingFailure`
is structured data this file returns to its caller rather than logs — the
source's own doc comment states `reason` is rendered
verbatim by "the settings panel's Decisions group," a separate component
outside this file's scope that may do its own logging or presentation; this
file itself writes no log line.

## Platform Notes

- **Swift (source)**: This file targets macOS today, via the
  `AgenticToolkitCore` framework target (`project.yml`); nothing in it —
  plain `Codable`/`Sendable` structs and enums over Foundation's
  `JSONDecoder`/`JSONEncoder` — depends on `AppKit`, `UIKit`, or any other
  platform framework, so the same source would decode identically if the
  target grew an iOS platform tomorrow.
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
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
