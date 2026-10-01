---
id: c4375e0e-091f-4627-b3c9-e7d36221802f
title: Contributed Settings
domain: agentictoolkit://cookbook/workspace/extensions/manifest/contributed-settings
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure classifier turning one VS Code extension manifest's contributes.configuration
  into settings rows, storage names, and a note for every schema declaration it could
  not honour exactly.
platforms:
- swift
- macos
tags:
- extensions
- configuration
- settings
- manifest
- contribution-point
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Core/Extensions/ContributedSettings.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ExtensionManifest.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Extensions/ContributionPoint.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/ContributedSettingsBuilderTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/ConfigurationContributionPoint.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Contributed Settings

## Overview

Turns one VS Code extension manifest's `contributes.configuration` block
into the rows a settings panel can render, and every compromise that block
forced along the way. It defines the row's value shapes — an option, a
setting's kind (a six-kind control vocabulary: toggle, text, choice,
number, integer, json), a setting row, and a settings section — a note
record for every schema declaration this host could not honour exactly, a
three-outcome declaration distinguishing "no settings declared," "settings
declared but none survived classification," and "the schema itself could
not be read," and the pure classifying logic that produces them.

This classifier holds no state of its own: nothing in it reads or writes a
setting's stored value, opens a file, or touches a window. That is a
separate contribution point's job — a platform-specific piece that
remembers what was applied per extension and turns a declaration into
actual views. This recipe covers the classifier alone; the extension
manifest and that contribution point are collaborators consulted for
grounding but are out of this recipe's scope.

## Behavioral Requirements

- **entry-point-delegation**: Building sections for a manifest MUST
  delegate to the lower-level sections builder, passing the manifest's
  `contributes.configuration` (or an empty list when absent) as the
  configuration list, the manifest's identifier as the owning extension,
  the manifest's display name (or its bare name when no display name is
  declared) as the fallback title, and the manifest's recorded decoding
  failures (or an empty list when none) as the decoding-failures list.
- **undeclared-configuration**: when the configuration list is empty and
  the decoding-failures list contains no entry whose key equals
  `"contributes.configuration"`, building sections MUST return the
  undeclared outcome with no sections.
- **unreadable-configuration**: when the configuration list is empty and
  the decoding-failures list contains at least one entry whose key equals
  `"contributes.configuration"`, building sections MUST return the
  unreadable outcome carrying that first entry's reason, with no sections.
- **declared-when-nonempty-input**: when the configuration list is
  non-empty, the returned declaration MUST be the declared outcome, even
  when filtering removes every section and the resulting sections list is
  empty — a declared outcome with no sections and the undeclared outcome
  MUST remain distinguishable results.
- **empty-section-dropped**: a configuration entry whose declared
  properties are empty MUST produce no settings section and no note.
- **sorted-property-iteration**: within one section, properties MUST be
  visited and classified in ascending lexicographic order of key, never in
  whatever order the decoded properties happen to be stored in, because
  that order is not guaranteed stable and would otherwise leak into the
  notes list.
- **duplicate-key-first-wins**: when more than one section (processed in
  configuration-list order, keys within a section in sorted order)
  declares the same property key, only the first-encountered declaration
  MUST become a row; every later declaration of that key MUST be skipped
  and MUST produce a duplicate-key note for that key whose detail is
  exactly "already declared by an earlier section; this declaration is
  ignored".
- **section-emptied-by-duplicates-dropped**: a section every one of whose
  properties was claimed by an earlier section MUST produce no settings
  section, and MUST NOT produce a missing-section-title note, even when the
  section itself declared no title — the emptiness check MUST run before
  title resolution for exactly this reason.
- **section-title-resolution**: a surviving section's title MUST be its
  own declared title when that value is non-empty; otherwise it MUST be
  the fallback title, and a missing-section-title note MUST be recorded
  whose key is the resolved fallback title and whose detail is exactly
  "section {index} declared no title; using \"{fallbackTitle}\"", where
  index is the section's zero-based position in the decoded configuration
  list.
- **section-ordering**: the declaration's sections MUST be sorted so a
  section with a smaller declared order precedes one with a larger
  declared order; a section with a declared order MUST precede one with
  none; when neither rule distinguishes two sections, the one with the
  lexicographically smaller title MUST precede; when titles are equal too,
  the section that appeared earlier in the decoded configuration list MUST
  precede.
- **setting-ordering**: within one section, the settings MUST be sorted by
  the same rule applied to each setting's own declared order, with the
  final tiebreak being the setting's own key in ascending order rather
  than a title or list position, because keys are unique within one
  section.
- **storage-name-format**: computing a setting's storage name MUST return
  exactly the string `"extensions.{identifier}.{key}"`, and a setting
  row's own storage name MUST equal the result of that computation for
  that setting's own key and the owning extension's identifier.
- **setting-key-verbatim**: a setting row's key MUST equal the manifest's
  dotted property key exactly as declared, with no namespace stripped and
  no case change.
- **enum-string-choice**: a property whose `enum` is declared, non-empty,
  and (after dropping any `null` members) contains only JSON string
  members MUST classify as the choice kind.
- **enum-label-positional**: each produced option's label MUST be the
  corresponding `enumItemLabels` entry at the member's original,
  pre-null-filter index when that entry is present and non-null, and MUST
  otherwise be the option's own value.
- **enum-null-member-dropped**: a `null` member of a declared `enum` MUST
  be omitted from the resulting options and MUST NOT by itself prevent the
  property from classifying as the choice kind.
- **enum-default-matches**: when `default` is a JSON string equal to one
  of the enum's retained, non-null string members, that value MUST be
  selected with no note recorded for the default.
- **enum-default-null**: when `default` is the JSON literal `null`, a
  default-type-mismatch note with detail "default is null; the first
  member stands in" MUST be recorded, and the first retained member MUST
  be selected.
- **enum-default-not-member**: when `default` is present, is not `null`,
  and either is not a JSON string or is a string absent from the enum's
  retained members, a default-not-in-enum note MUST be recorded quoting
  the default's raw text, a new option whose label and value both equal
  that raw text MUST be inserted at the front of the options list, and it
  MUST be selected.
- **enum-default-missing**: when `enum` is declared and classifies as the
  choice kind but `default` is absent entirely, a missing-default note
  with detail "no default; the first member stands in" MUST be recorded
  and the first retained member MUST be selected.
- **enum-descriptions-dropped**: when a property classifies as the choice
  kind and declares `enumDescriptions` or `markdownEnumDescriptions`, an
  enum-descriptions-dropped note MUST be recorded regardless of which
  default-resolution branch ran.
- **enum-mixed-falls-to-type**: when `enum` is declared and non-empty but
  at least one non-null member is not a JSON string, a non-string-enum
  note MUST be recorded and classification MUST proceed using the
  property's effective type (or default-based inference) instead of the
  enum.
- **boolean-classification**: a property whose effective type is
  `"boolean"` MUST classify as the toggle kind.
- **boolean-default-fallback**: for a toggle classification, a missing
  `default` MUST record a missing-default note ("no default; false stands
  in") and use `false`; a `default` that is not a JSON boolean MUST record
  a default-type-mismatch note and use `false`.
- **string-classification**: a property whose effective type is `"string"`
  MUST classify as the text kind, with multiline true if and only if
  `editPresentation` equals `"multilineText"`.
- **string-default-fallback**: for a text classification, a missing
  `default` MUST record a missing-default note ("no default; the empty
  string stands in") and use the empty string; a `default` that is not a
  JSON string MUST record a default-type-mismatch note and use the empty
  string.
- **number-classification**: a property whose effective type is `"number"`
  MUST classify as the number kind, carrying `minimum`/`maximum` through
  unmodified when declared, and inventing neither bound when absent.
- **integer-classification**: a property whose effective type is
  `"integer"` MUST classify as the integer kind; a missing `default` MUST
  record a missing-default note and use `0`; a `default` that is not a
  whole JSON number MUST record a default-type-mismatch note and use `0`.
- **integer-bounds-rounding**: for an `"integer"` property, a declared
  `minimum` MUST be rounded up and a declared `maximum` MUST be rounded
  down to the nearest whole number before either is treated as a bound,
  because a bound that widened when rounded could let a clamp store a
  value the schema forbids.
- **bounds-contradiction-dropped**: when both `minimum` and `maximum` are
  present for a `"number"` or `"integer"` property (after any integer
  rounding) and `minimum` exceeds `maximum`, both bounds MUST be dropped —
  treated as absent — and a contradictory-bounds note naming both values
  MUST be recorded.
- **default-clamped-to-bounds**: when both bounds are present and agree,
  and the resolved default lies outside them, the default MUST be clamped
  to the nearer bound and a default-out-of-range note naming the original
  default and the bound used MUST be recorded; this clamp MUST run only
  after bounds have already been checked for agreement.
- **array-object-to-json**: a property whose effective type is `"array"`
  or `"object"` MUST classify as the json kind, with default equal to the
  pretty-printed JSON text of the declared default, and MUST record no
  note for this classification — it is the type's intended destination,
  not a compromise.
- **unrenderable-type-fallback**: a property whose effective type is any
  value other than `"boolean"`, `"string"`, `"integer"`, `"number"`,
  `"array"`, or `"object"` MUST classify as the json kind and MUST record
  an unrenderable-type note naming the type.
- **mixed-union-fallback**: when a property's declared `type` is a union
  whose non-null members do not collapse to exactly one name (so the
  effective type is absent), classification MUST record a
  mixed-union-type note naming the union's members and MUST classify as
  the json kind using the declared default's JSON text.
- **no-type-inference**: when a property declares no `type` at all (not a
  union, and the effective type is absent), classification MUST be
  inferred from the JSON type of `default`: a boolean default classifies
  as toggle with no note; a whole-number default classifies as integer
  (bounds handled per `integer-bounds-rounding`); a non-whole-number
  default classifies as number; a string default classifies as text
  (honouring `editPresentation`); an array or object default classifies as
  json with no note; a `null` default classifies as json and records an
  unrenderable-type note ("no type, and a null default says nothing about
  one"); and an entirely absent default classifies as json (rendering
  `"null"`) and records an unrenderable-type note ("no type, no enum and
  no default").
- **json-escape-hatch-text**: rendering a value's JSON text MUST produce
  pretty-printed, key-sorted JSON with forward slashes left unescaped; a
  whole-number JSON value MUST render without a trailing `.0`; and an
  absent input MUST render as the JSON literal `null`.
- **deprecation-appended**: when a property declares `deprecationMessage`,
  or, absent that, `markdownDeprecationMessage`, the resulting setting
  row's explanation MUST append that message after any
  `description`/`markdownDescription` body separated by one blank line, or
  stand alone when no body exists, and a deprecated note carrying that
  message as its detail MUST be recorded, independent of what kind the
  property classified as.
- **explanation-source**: a setting row's explanation body MUST be
  `description` when present, and otherwise `markdownDescription` treated
  as plain text — its Markdown syntax MUST NOT be rendered or stripped,
  only carried through verbatim, because nothing that displays this string
  renders Markdown.
- **setting-order-field**: a setting row's order MUST equal the property's
  own declared `order`, and that value MUST already have determined the
  setting's position within its section's settings list per
  `setting-ordering`.
- **thread-safe-value-types**: an option, a setting's kind, a setting row,
  a settings section, a note, and the declaration MUST each be immutable,
  comparable values usable safely from any thread, so a caller MAY pass
  any of them across a concurrency boundary with no additional
  synchronization.
- **pure-no-side-effects**: classification MUST hold no mutable state of
  its own, and neither building sections nor computing a storage name MUST
  read a setting's stored value, write one, or perform any file, network,
  or window-system side effect — each call's only observable effect MUST
  be its return value.

## Appearance

Not applicable — this is a pure manifest-to-settings-row classifier, not a visual component.

## States

Not applicable — this is a pure manifest-to-settings-row classifier, not a visual component. Its only stateful concept, the declaration's three outcomes (undeclared, declared, unreadable), is a data-shape distinction covered under Behavioral Requirements, not a visual or lifecycle state.

## Accessibility

Not applicable — this is a pure manifest-to-settings-row classifier, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| contributed-settings-001 | undeclared-configuration | An extension manifest whose `contributes` declares no `configuration` key at all; build sections for it. | The declaration is undeclared. |
| contributed-settings-002 | unreadable-configuration | A manifest whose `contributes.configuration` is the JSON string `"see the docs"` (neither an object nor an array); build sections for it. | The declaration is unreadable, not undeclared, and its sections list is empty. |
| contributed-settings-003 | declared-when-nonempty-input, empty-section-dropped | Build sections from a single section `{ "title": "Empty", "properties": {} }`. | The declaration is declared, with an empty sections list. |
| contributed-settings-004 | empty-section-dropped | Build sections from two sections, `{ "title": "Empty", "properties": {} }` and a second titled "Real" with one boolean property. | The sections list's titles are `["Real"]`. |
| contributed-settings-005 | sorted-property-iteration, section-ordering, setting-ordering | Build sections from a three-section fixture (section orders 2/none/1; one section's four properties ordered 1/2/none/none). | Sections' titles are `["Beta", "Zeta", "Alpha"]`; the "Zeta" section's settings' keys are `["z.alpha", "a.beta", "b.delta", "m.gamma"]`. |
| contributed-settings-006 | duplicate-key-first-wins | Build sections from two sections both declaring `acme.mode`: first `{ "type": "boolean", "default": false }`, second `{ "type": "string", "default": "auto" }`. | One row only, kind is toggle with default `false`; the notes list contains a duplicate-key note keyed `"acme.mode"`. |
| contributed-settings-007 | storage-name-format, setting-key-verbatim | Declare the same key `python.pythonPath` (type `string`, default `"py"`) under two different extensions, `anysphere.pyright` and `ms-python.python`. | Storage names are `"extensions.anysphere.pyright.python.pythonPath"` and `"extensions.ms-python.python.python.pythonPath"`; both rows' keys are `"python.pythonPath"`. |
| contributed-settings-008 | section-title-resolution | Build sections from one titleless section with one boolean property, manifest display name set to "Sample Extension", then again with no display name. | First: sections' titles are `["Sample Extension"]` and the notes list is one missing-section-title note whose key is `"Sample Extension"`; second: title falls back to `"sample"`. |
| contributed-settings-009 | section-emptied-by-duplicates-dropped | Build sections from two sections both declaring `acme.mode`, the second titled but with no other properties, so every one of its properties is a duplicate. | The second section produces no settings section and no missing-section-title note, even though it declared no title. |
| contributed-settings-010 | enum-string-choice, enum-label-positional, enum-default-matches | Classify `{ "type": "string", "enum": ["off","on","auto"], "enumItemLabels": ["Never","Always", null], "default": "on" }`. | Choice kind with option labels `["Never","Always","auto"]`, option values `["off","on","auto"]`, selected value `"on"`. |
| contributed-settings-011 | enum-default-not-member | Classify `{ "type": "string", "enum": ["a","b"], "default": "legacy" }`. | Choice kind with option values `["legacy","a","b"]`, selected value `"legacy"`, and a default-not-in-enum note. |
| contributed-settings-012 | enum-default-null | Classify `{ "type": "string", "enum": ["a","b"], "default": null }`. | Choice kind with selected value `"a"` (the first retained member) and a default-type-mismatch note reading "default is null; the first member stands in". |
| contributed-settings-013 | enum-default-missing | Classify `{ "type": "string", "enum": ["a","b"] }` with no `default` key at all. | Choice kind with selected value `"a"` and a missing-default note reading "no default; the first member stands in". |
| contributed-settings-014 | enum-mixed-falls-to-type | Classify `{ "type": "boolean", "enum": [true, "auto"], "default": true }`. | Toggle kind with default `true`, and a non-string-enum note. |
| contributed-settings-015 | enum-descriptions-dropped, sorted-property-iteration | Build sections from a five-property section fixture (`e.five` declares `enumDescriptions`; each property's `order` reverses its key's alphabetical position). | The section's settings' keys are `["e.five","d.four","c.three","b.two","a.one"]` (display order by declared order); the notes list's keys are `["a.one","b.two","c.three","d.four","e.five"]` (key-sorted note order); the notes list's kinds are `[missing-default, unrenderable-type, mixed-union-type, non-string-enum, enum-descriptions-dropped]`. |
| contributed-settings-016 | mixed-union-fallback | Classify `{ "type": ["boolean","string"], "default": true }`. | Json kind with default text `"true"` and a mixed-union-type note; the owning extension identifier is `"acme.sample"`. |
| contributed-settings-017 | number-classification | Classify `{ "type": "number", "default": 1.5 }` (no bounds), and `{ "type": "number", "default": 1.5, "minimum": 0.5, "maximum": 2.5 }`. | First: number kind, default `1.5`, no bounds; second: number kind, default `1.5`, minimum `0.5`, maximum `2.5`. |
| contributed-settings-018 | boolean-default-fallback, string-default-fallback | Classify `{ "type": "string", "default": null }` and `{ "type": "boolean", "default": "yes" }`. | First: text kind, default empty string, plus a default-type-mismatch note; second: toggle kind, default `false`, plus a default-type-mismatch note. |
| contributed-settings-019 | no-type-inference | Classify `{ "default": 3 }` and `{ "description": "nothing to go on" }`. | First: integer kind, default `3`, no bounds, with no note; second: json kind, default text `"null"`, plus an unrenderable-type note. |
| contributed-settings-020 | array-object-to-json, json-escape-hatch-text | Classify `{ "type": "object", "default": { "zebra": 1, "apple": [1,2] } }` and `{ "type": "array", "default": ["b","a"] }`. | Object case: the json text re-parses to the same value, `"apple"` occurs before `"zebra"`, the text spans more than one line, and contains no `.0`; array case: the json text re-parses to `["b","a"]` in that exact order — list elements are data, never sorted. |
| contributed-settings-021 | string-classification | Classify `{ "type": "string", "default": "hi", "editPresentation": "multilineText" }`. | Text kind, default `"hi"`, multiline true. |
| contributed-settings-022 | deprecation-appended, explanation-source | Classify `{ "type": "boolean", "default": false, "description": "Turns the thing on.", "deprecationMessage": "Use a.new instead." }`. | The explanation equals the description body, a blank line, then the deprecation message; the notes list is one deprecated note. |
| contributed-settings-023 | boolean-default-fallback, string-default-fallback | Classify `{ "type": "boolean" }` and `{ "type": "string" }`, each with no `default` key. | Toggle kind, default `false`, plus a missing-default note; text kind, default empty string, plus a missing-default note. |
| contributed-settings-024 | sorted-property-iteration (upstream tolerance) | Build a section where one property spells `"order": "0"` (a string, not a number) alongside a sibling spelling `"order": 1`, and a second section where one property's JSON value is the bare string `"not an object"` alongside a well-formed sibling. | First fixture: both properties survive as rows, settings' keys are `["b.second","a.first"]`, settings' orders are `[1, absent]`; second fixture: only the well-formed sibling survives. |
| contributed-settings-025 | bounds-contradiction-dropped, integer-bounds-rounding | Classify `{ "type": "number", "default": 5, "minimum": 10, "maximum": 1 }` and `{ "type": "integer", "default": 1, "minimum": 0.5, "maximum": 0.9 }`. | First: number kind, default `5`, no bounds, plus a contradictory-bounds note; second: integer kind, default `1`, no bounds — `0.5` rounds up to `1`, `0.9` rounds down to `0`, and `1 > 0` inverts. |
| contributed-settings-026 | default-clamped-to-bounds | Classify `{ "type": "number", "default": 5, "minimum": 10, "maximum": 20 }`. | Number kind, default `10`, minimum `10`, maximum `20`, plus a default-out-of-range note. |
| contributed-settings-027 | entry-point-delegation | Decode a manifest whose `contributes.configuration` is the single-object form `{ "title": "One", "properties": {...} }`, and separately the array form `[ {"title":"One",...}, {"title":"Two",...} ]`, then build sections for the manifest. | The single-object form yields one section titled "One"; the array form yields two sections titled `["One","Two"]` in that order. |
| contributed-settings-028 | thread-safe-value-types, pure-no-side-effects | Round-trip a configuration property's decoded shape (union `type` included) through encoding and decoding; separately, pass a setting row value across a concurrency boundary. | The round trip decodes back equal to the original; passing the value across the boundary requires no additional synchronization, since every value type here is safe to share across threads. |
| contributed-settings-029 | mixed-union-fallback | Classify `{ "type": ["number", null], "default": 1.5 }` and `{ "type": ["number", "null"], "default": 1.5 }`. | Both classify identically to number kind, default `1.5`, no bounds — a JSON `null` member and the string `"null"` collapse to the same union result. |

## Edge Cases

- **Null and empty input**: an extension manifest that declares no `contributes.configuration` key at all MUST classify as undeclared (`undeclared-configuration`); a declared but empty properties object within a section MUST drop that section entirely with no note (`empty-section-dropped`); a declared `enum` containing only `null` (no retained string member) MUST fail the choice classification and fall through to type-based or default-based classification exactly like an enum with a non-string member.
- **Boundary values — bounds that invert**: a `minimum` greater than a `maximum` (before or, for `"integer"`, after inward rounding) MUST be treated as no bounds at all, with a contradictory-bounds note, per `bounds-contradiction-dropped`.
- **Boundary values — default outside agreeing bounds**: MUST be clamped to the nearer bound with a default-out-of-range note, per `default-clamped-to-bounds`.
- **integer-bound-overflow**: NEEDS REVIEW: Not implemented in source. Converting a bound with magnitude larger than the platform's whole-number range, or a bound that is not-a-number or infinite, into a whole-number bound fails silently and the bound is then discarded — indistinguishable from a schema that declared no bound at all, and no note is recorded. Every other way a declared bound cannot be honoured (contradictory bounds, a default outside the representable bounds) does produce a note; this path does not. What is missing: whether an out-of-range `minimum`/`maximum` should record a note of its own, or is deliberately meant to be treated as absent. Evidence that would settle it: a ruling from whoever maintains the settings builder's corpus study (see the source's own doc comments citing corpus counts), or a corpus property that exercises this path (Platform Notes — the exact conversion mechanism).
- **Concurrent access**: not applicable as a hazard — classification is a stateless collection of pure functions over immutable, thread-safe values (`thread-safe-value-types`, `pure-no-side-effects`); concurrent calls from any thread produce independent results with no shared mutable state to race.
- **Error states — a property that failed to decode at all**: not this component's concern. The manifest decoder decodes each property individually and tolerates a per-property decoding failure, so a property whose JSON value is not an object (e.g. a bare string) never reaches classification at all — it is simply absent from the section's properties, with no corresponding note; see contributed-settings-024.
- **Error states — `contributes.configuration` present but unreadable**: MUST classify as unreadable, not undeclared, per `unreadable-configuration`.
- **Offline or disconnected state**: not applicable — this component performs no network call of any kind; it operates entirely over values already decoded into memory.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| manifest | extension manifest | none (required) | The decoded manifest passed to the top-level sections builder; supplies the configuration list, identifier, display name (or bare name), and decoding failures to the lower-level builder. |
| configuration | list of configuration entries | none (required) | The decoded `contributes.configuration` list (already normalized from VS Code's single-object-or-array form upstream) passed to the lower-level sections builder. |
| identifier (owning extension) | string | none (required) | The extension's case-folded `publisher.name` (or bare `name`), used verbatim in every storage name and every note's extension identifier this call produces. |
| fallbackTitle | string | none (required) | The title a titleless section borrows — the manifest's display name, or its bare name, at the one production call site. |
| decodingFailures | list of decoding failures | empty list | Failures the manifest decoder recorded; only an entry whose key equals `"contributes.configuration"` affects this component's output, distinguishing unreadable from undeclared. |
| key (to computing a storage name) | string | none (required) | The dotted property key a caller wants the storage name for. |

No environment variable, settings key of its own, or injected dependency is read by this component — it is a pure function of its parameters.

## Deep Linking

Not applicable: this component defines no URL, route, or navigable destination — it is a manifest-to-row classifier with no navigation surface of its own.

## Localization

A note's detail, and the raw-text fallbacks it quotes, are shown to a
person rather than swallowed — this component's own documented intent
says so directly ("what was compromised is shown to a person rather than
swallowed") — but every one of those strings is composed as a hardcoded
English literal (e.g. "already declared by an earlier section; this
declaration is ignored", "section {index} declared no title; using
\"{fallbackTitle}\""); none is looked up through a localization catalog or
key. An option's label that falls back to a member's raw value (per
`enum-label-positional`) is similarly whatever text the extension manifest
happened to write, never localized by this component.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — no localization key exists) | e.g. "already declared by an earlier section; this declaration is ignored" | A note's detail, composed inline in English at each point classification records one |

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: this component declares no feature-flag key and contains no conditional feature-gating logic; classification always runs the same way for any non-empty configuration input.

## Analytics

Not applicable: this component contains no analytics or event-emission call of any kind.

## Privacy

Not applicable: this component classifies only a manifest's own *declared default* values — the schema an extension author wrote into the manifest — never a user's actually-configured setting value; reading, storing, or transmitting a live setting value happens elsewhere (a separate contribution point and its consumers), outside this component. Nothing here is a credential, token, or personally identifying value.

## Logging

Not applicable: this component makes no logging call of its own. Every compromise it makes is recorded as a note value for a caller to log or display, per `duplicate-key-first-wins`, `section-title-resolution`, and the classification requirements above — this component surfaces the information some other way rather than logging it itself.

## Platform Notes

- **SwiftUI**: not a dependency of this file — `ContributedSettings.swift` imports only `Foundation`. A SwiftUI settings screen would switch over `ContributedSettingKind` per row (`Toggle` for `.toggle`, `TextField`/multiline `TextEditor` for `.text`, `Picker` for `.choice`, a bounded `Slider`/`TextField` for `.number`/`.integer`, and a plain `TextEditor` for the `.json` escape hatch), grouped by `ContributedSettingsSection.title` in a `Form` with `Section` headers, with no additional state management needed since `sections(for:)` is a one-shot, non-observed call.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/Core/Extensions/ContributedSettings.swift`, part of the macOS-only `AgenticToolkitCore` framework target (`project.yml` declares `platform: macOS` for `AgenticToolkitCore`; there is no iOS target in this repository today). It is consumed by `ConfigurationContributionPoint` (`macOS/Features/Extensions/ConfigurationContributionPoint.swift`), the `AgenticToolkitMacOS`-side `ContributionPoint` that turns a `ContributedSettingsDeclaration` into AppKit views; neither AppKit nor UIKit is imported by `ContributedSettings.swift` itself, so the classifier would work unchanged behind a UIKit consumer. Every public value type here — `ContributedSettingOption`, `ContributedSettingKind`, `ContributedSetting`, `ContributedSettingsSection`, `ContributedSettingNote`, and `ContributedSettingsDeclaration` — is declared `Sendable` and `Equatable`. `ExtensionManifest.Configuration.init(from:)` decodes each property individually with `try?`, so one malformed property is dropped rather than failing the whole section. Integer bound conversion uses `Int(exactly: $0.rounded(.up))`/`Int(exactly: $0.rounded(.down))`, discarding the bound via `flatMap` when the conversion fails (see the integer-bound-overflow edge case).
- **Compose**: model `ContributedSettingKind` as a Kotlin `sealed class` (`Toggle`, `Text`, `Choice`, `Number`, `Integer`, `Json`, each a `data class` mirroring the Swift case's associated values) and `ContributedSettingsBuilder` as a Kotlin `object` of pure functions over a `kotlinx.serialization.json.JsonElement`-based manifest model in place of `ExtensionManifest.JSONValue`; keep the classifier in a plain Kotlin module with no Android framework import, mirroring this file's Foundation-only isolation, so it stays unit-testable off the main thread.
- **React/Web**: model `ContributedSettingKind` as a discriminated union, e.g. `{ kind: "toggle", default: boolean } | { kind: "text", default: string, multiline: boolean } | { kind: "choice", options: ContributedSettingOption[], default: string } | { kind: "number", default: number, minimum?: number, maximum?: number } | { kind: "integer", default: number, minimum?: number, maximum?: number } | { kind: "json", default: string }`; classify with a pure function over a parsed `package.json`-shaped object (`unknown` in place of `JSONValue`), and render each case through a component switch; sort sections and settings with `Array.prototype.sort` using the same two-level comparator this file's `precedes` functions apply.
- **WinUI 3**: the reason this recipe exists. Model `ContributedSettingKind` as a C# discriminated union — an abstract `record ContributedSettingKind` with `sealed record ToggleKind(bool Default)`, `TextKind(string Default, bool Multiline)`, `ChoiceKind(IReadOnlyList<ContributedSettingOption> Options, string Default)`, `NumberKind(double Default, double? Minimum, double? Maximum)`, `IntegerKind(int Default, int? Minimum, int? Maximum)`, and `JsonKind(string Default)` — each an immutable value type standing in for the Swift `enum` case's `Sendable` guarantee. Reimplement `ContributedSettingsBuilder` as a static class (`ContributedSettingsBuilder.Sections(ExtensionManifest manifest)`), classifying over `System.Text.Json.JsonElement`/`JsonDocument` in place of `ExtensionManifest.JSONValue` — `JsonElement.ValueKind` gives the same open-type dispatch the Swift `switch` over `JSONValue` does. Bind a settings panel's rows to WinUI controls per kind: `ToggleSwitch` for `ToggleKind`, `TextBox` (`AcceptsReturn = true` when `Multiline`) for `TextKind`, `ComboBox` for `ChoiceKind`, `NumberBox` (with `Minimum`/`Maximum` bound when present) for `NumberKind`/`IntegerKind`, and a plain multiline `TextBox` for `JsonKind`. Reproduce `jsonText(of:)`'s pretty-printed, key-sorted output with `System.Text.Json.JsonSerializerOptions { WriteIndented = true }` plus a `SortedDictionary`-backed intermediate or a custom `JsonConverter`, since `WriteIndented` alone does not sort keys. Reproduce the two Swift `precedes` comparators (order-ascending-with-nils-last, then title or key) with chained `OrderBy`/`ThenBy` calls over the same tiebreak sequence. `Sendable` has no direct C# equivalent; document the record types as immutable to carry the same intent, and note that C# offers no compiler-enforced analog to `pure-no-side-effects` — reviewers must verify by inspection that a WinUI 3 port makes the same no-I/O guarantee.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/ContributedSettings.swift` |

## Design Decisions

**Decision**: `storageName(forKey:ofExtension:)` builds a slot per *extension*, `"extensions.<identifier>.<key>"`, rather than storing directly under the manifest's own dotted key.
**Rationale**: the source's own doc comment records that 389 keys in the corpus this classifier was built against are declared by more than one extension, 18 of them disagreeing on `(type, default)` — one flat slot provably cannot hold both, and withdrawal (removing one extension's settings without touching another's) has to be able to name exactly what one extension owns (`ContributedSettings.swift`).
**Approved**: pending

**Decision**: `ContributedSetting.key` is kept as the manifest's full dotted key, never a namespace-stripped leaf.
**Rationale**: the source's own doc comment reports that the first dotted segment matches the extension's own name only 84% of the time in the Open VSX corpus studied (`anysphere.pyright` declares `python.pythonPath`), so stripping a namespace would strip the one token that says which setting a row actually is — VS Code's own settings UI shows the full key for the same reason (`ContributedSettings.swift`).
**Approved**: pending

**Decision**: an `enum` option's `label` is looked up positionally against the *declared* member index, before any `null` member is dropped, rather than against the filtered `values` array's index.
**Rationale**: `enumItemLabels` is indexed against the manifest's own `enum` array (`ContributedSettings.swift`); reindexing after dropping `null` members would silently mislabel every option that follows a dropped `null`, so the code deliberately looks up `members[index]`'s label before filtering, not after.
**Approved**: pending

**Decision**: a default that is present but does not match any retained enum member (`enum-default-not-member`) is inserted as a brand-new option at index 0, rather than being discarded in favor of the first declared member.
**Rationale**: the source's own comment states the stored value has to be representable, or the popup would silently rewrite it out from under the user (`ContributedSettings.swift`); inventing an option that carries the actual stored value forward is the only way a `.choice` control can round-trip a value the schema's own `enum` does not otherwise allow.
**Approved**: pending

**Decision**: `"integer"` bounds round `minimum` up and `maximum` down (rounding inward) rather than to the nearest whole number, and the inversion check for `bounds-contradiction-dropped` runs *after* that rounding.
**Rationale**: the source's own comment explains that a bound which widened when rounded — e.g. a `minimum` of `0.5` rounding down to `0` — is the one direction that could let a clamp store a value the declared schema forbids; and because `minimum: 1.2, maximum: 1.8` does not invert as written but does invert to `2...1` after inward rounding, the contradiction check has to run on the rounded values, not the raw ones (`ContributedSettings.swift`).
**Approved**: pending

**Decision**: `"array"` and `"object"` types classify straight to `.json` with no `ContributedSettingNote`, while every other unrenderable path (`unrenderable-type-fallback`, `mixed-union-fallback`, the `nil`-default/no-type case in `no-type-inference`) records one.
**Rationale**: the source's own inline comment states this directly — `array`/`object` are "where a structured value is *supposed* to land, not a compromise" (`ContributedSettings.swift`) — distinguishing an intended destination for the JSON escape hatch from every case where the escape hatch is a fallback for something this classifier could not otherwise render.
**Approved**: pending

**Decision**: an out-of-`Int`-range `"integer"` `minimum`/`maximum` is silently dropped with no `ContributedSettingNote` (see the open question on integer-bound-overflow), unlike every other bound anomaly this file handles.
**Rationale**: recorded here as observed technical debt affecting behavioral correctness, per Source Fidelity, rather than corrected — fixing it would mean adding a new `ContributedSettingNote.Kind` case, a decision outside this recipe's authority to make on the maintainer's behalf.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [safe-defaults](agenticdevelopercookbook://compliance/user-safety#safe-defaults) | passed | User Safety |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because classification is entirely isolated in this Foundation-only file, with the AppKit rendering and persistence left to `ConfigurationContributionPoint`, exactly the split the type's own doc comment describes. `graceful-degradation` passes because a malformed or ambiguous property — a duplicate key, a mixed union, a default of the wrong JSON type, an inverted bound — never sinks its section or its siblings; each degrades to a safe fallback (the JSON escape hatch, a zero-value default, a dropped bound) with a recorded note. `safe-defaults` passes because every classification path that cannot resolve a real default lands on a defined, harmless value (`false`, `""`, `0`, `"null"`) rather than crashing or leaving the field undefined. `unit-test-coverage` passes because `ContributedSettingsBuilderTests.swift` exercises every classification branch, every note kind, and both ordering rules. `explicit-error-handling` is partial because most compromises are surfaced through `ContributedSettingNote`, but the out-of-`Int`-range integer-bound case documented under Edge Cases loses a declared constraint with no note at all. `no-hardcoded-strings` fails because every `ContributedSettingNote.detail` string — text the source's own doc comment says is shown to a person — is a literal, unlocalized English string with no lookup key, per the Localization section above.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/manifest/. |
