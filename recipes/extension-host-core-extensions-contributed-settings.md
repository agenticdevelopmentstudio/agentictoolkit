---
id: c4375e0e-091f-4627-b3c9-e7d36221802f
title: ContributedSettings
domain: agentictoolkit://recipes/extension-host-core-extensions-contributed-settings
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure Foundation classifier turning one VS Code extension manifest's contributes.configuration
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

# ContributedSettings

## Overview

`ContributedSettings.swift` (`packages/apple/AgenticToolkit/Core/Extensions/ContributedSettings.swift`) turns one VS Code extension manifest's `contributes.configuration` block into the rows a settings panel can render, and every compromise that block forced along the way. It defines the row value types — `ContributedSettingOption`, `ContributedSettingKind` (a six-case control vocabulary: `toggle`, `text`, `choice`, `number`, `integer`, `json`), `ContributedSetting`, and `ContributedSettingsSection` — a `ContributedSettingNote` record for every schema declaration this host could not honour exactly, a `ContributedSettingsDeclaration` distinguishing "no settings declared," "settings declared but none survived classification," and "the schema itself could not be read," and the pure static namespace `ContributedSettingsBuilder`, which does the classifying.

The file is Foundation-only and holds no state of its own: nothing in it reads or writes a setting's stored value, opens a file, or touches a window. That is `ConfigurationContributionPoint`'s job (`packages/apple/AgenticToolkit/macOS/Features/Extensions/ConfigurationContributionPoint.swift`, part of the macOS-only `AgenticToolkitMacOS`/`AgenticToolkitCore` split), the AppKit half that remembers what was applied per extension via `ContributionRegistrations` (`ContributionPoint.swift`) and turns a `ContributedSettingsDeclaration` into actual views. This recipe covers `ContributedSettings.swift` alone; `ExtensionManifest`, `ContributionPoint`, and `ConfigurationContributionPoint` are collaborators consulted for grounding but are out of this recipe's scope.

## Behavioral Requirements

- **entry-point-delegation**: `ContributedSettingsBuilder.sections(for: manifest:)` MUST delegate to `sections(for: configuration: ofExtension: fallbackTitle: decodingFailures:)`, passing `manifest.contributes?.configuration ?? []` as `configuration`, `manifest.identifier` as `ofExtension`, `manifest.displayName ?? manifest.name` as `fallbackTitle`, and `manifest.contributes?.decodingFailures ?? []` as `decodingFailures` (`ContributedSettings.swift:182-190`).
- **undeclared-configuration**: when `configuration` is empty and `decodingFailures` contains no entry whose `key` equals `"contributes.configuration"`, the function MUST return `(.undeclared, [])` (`ContributedSettings.swift:229-233`).
- **unreadable-configuration**: when `configuration` is empty and `decodingFailures` contains at least one entry whose `key` equals `"contributes.configuration"`, the function MUST return `(.unreadable(reason: failure.reason), [])`, using the `reason` of the first such entry, with no notes.
- **declared-when-nonempty-input**: when `configuration` is non-empty, the returned `declaration` MUST be `.declared`, even when filtering removes every section and `sections` ends up empty — `.declared(sections: [])` and `.undeclared` MUST remain distinguishable results (`ContributedSettings.swift:152-161`).
- **empty-section-dropped**: a `Configuration` element whose `properties` is empty MUST produce no `ContributedSettingsSection` and no `ContributedSettingNote` (`ContributedSettings.swift:245-247`).
- **sorted-property-iteration**: within one section, properties MUST be visited and classified in ascending lexicographic order of key (`section.properties.keys.sorted()`), never in the section's `Dictionary` iteration order, because that order is not stable across launches and would otherwise leak into `notes` (`ContributedSettings.swift:250-253`).
- **duplicate-key-first-wins**: when more than one section (processed in `configuration` array order, keys within a section in sorted order) declares the same property key, only the first-encountered declaration MUST become a row; every later declaration of that key MUST be skipped and MUST produce a `ContributedSettingNote(kind: .duplicateKey)` for that key whose `detail` is exactly `"already declared by an earlier section; this declaration is ignored"` (`ContributedSettings.swift:255-263`).
- **section-emptied-by-duplicates-dropped**: a section every one of whose properties was claimed by an earlier section MUST produce no `ContributedSettingsSection`, and MUST NOT produce a `missingSectionTitle` note, even when the section itself declared no title — the `!settings.isEmpty` guard runs before title resolution for exactly this reason (`ContributedSettings.swift:280-285`).
- **section-title-resolution**: a surviving section's `title` MUST be its own declared `title` when that value is non-nil and non-empty; otherwise it MUST be `fallbackTitle`, and a `ContributedSettingNote(kind: .missingSectionTitle)` MUST be recorded whose `key` is the resolved fallback title and whose `detail` is exactly `"section \(index) declared no title; using \"\(fallbackTitle)\""`, where `index` is the section's zero-based position in the decoded `configuration` array (`ContributedSettings.swift:287-298`).
- **section-ordering**: `declaration.sections` MUST be sorted so a section with a smaller declared `order` precedes one with a larger declared `order`; a section with a declared `order` MUST precede one with none; when neither rule distinguishes two sections, the one with the lexicographically smaller `title` MUST precede; when titles are equal too, the section that appeared earlier in the decoded `configuration` array MUST precede (`ContributedSettings.swift:326-343`).
- **setting-ordering**: within one section, `settings` MUST be sorted by the same rule applied to each `ContributedSetting.order`, with the final tiebreak being the setting's own `key` in ascending order rather than a title or array index, because keys are unique within one section (`ContributedSettings.swift:344-354`).
- **storage-name-format**: `storageName(forKey:ofExtension:)` MUST return exactly the string `"extensions.\(identifier).\(key)"`, and `ContributedSetting.storageName` MUST equal the result of calling it with that setting's own `key` and the extension's identifier (`ContributedSettings.swift:317-319`).
- **setting-key-verbatim**: `ContributedSetting.key` MUST equal the manifest's dotted property key exactly as declared, with no namespace stripped and no case change.
- **enum-string-choice**: a property whose `enum` is declared, non-empty, and (after dropping any `null` members) contains only JSON string members MUST classify as `.choice` (`ContributedSettings.swift:434-460`).
- **enum-label-positional**: each produced `ContributedSettingOption.label` MUST be `enumItemLabels[i]` at the member's original, pre-null-filter index when that entry is present and non-nil, and MUST otherwise be the option's own `value`.
- **enum-null-member-dropped**: a `null` member of a declared `enum` MUST be omitted from the resulting options and MUST NOT by itself prevent the property from classifying as `.choice`.
- **enum-default-matches**: when `default` is a JSON string equal to one of the enum's retained, non-null string members, that value MUST be selected with no note recorded for the default.
- **enum-default-null**: when `default` is the JSON literal `null`, a `ContributedSettingNote(kind: .defaultTypeMismatch)` with detail `"default is null; the first member stands in"` MUST be recorded, and the first retained member MUST be selected.
- **enum-default-not-member**: when `default` is present, is not `null`, and either is not a JSON string or is a string absent from the enum's retained members, a `ContributedSettingNote(kind: .defaultNotInEnum)` MUST be recorded quoting the default's raw text, a new `ContributedSettingOption` whose `label` and `value` both equal that raw text MUST be inserted at index 0 of `options`, and it MUST be selected.
- **enum-default-missing**: when `enum` is declared and classifies as `.choice` but `default` is absent entirely, a `ContributedSettingNote(kind: .missingDefault)` with detail `"no default; the first member stands in"` MUST be recorded and the first retained member MUST be selected.
- **enum-descriptions-dropped**: when a property classifies as `.choice` and declares `enumDescriptions` or `markdownEnumDescriptions`, a `ContributedSettingNote(kind: .enumDescriptionsDropped)` MUST be recorded regardless of which default-resolution branch ran.
- **enum-mixed-falls-to-type**: when `enum` is declared and non-empty but at least one non-null member is not a JSON string, a `ContributedSettingNote(kind: .nonStringEnum)` MUST be recorded and classification MUST proceed using `effectiveType` (or default-based inference) instead of the enum (`ContributedSettings.swift:367-372`).
- **boolean-classification**: a property whose `effectiveType` is `"boolean"` MUST classify as `.toggle` (`ContributedSettings.swift:383-384`).
- **boolean-default-fallback**: for a `.toggle` classification, a missing `default` MUST record `ContributedSettingNote(kind: .missingDefault)` ("no default; false stands in") and use `false`; a `default` that is not a JSON boolean MUST record `ContributedSettingNote(kind: .defaultTypeMismatch)` and use `false` (`ContributedSettings.swift:585-598`).
- **string-classification**: a property whose `effectiveType` is `"string"` MUST classify as `.text`, with `multiline` `true` if and only if `editPresentation == "multilineText"` (`ContributedSettings.swift:385-388`).
- **string-default-fallback**: for a `.text` classification, a missing `default` MUST record `ContributedSettingNote(kind: .missingDefault)` ("no default; the empty string stands in") and use `""`; a `default` that is not a JSON string MUST record `ContributedSettingNote(kind: .defaultTypeMismatch)` and use `""` (`ContributedSettings.swift:600-613`).
- **number-classification**: a property whose `effectiveType` is `"number"` MUST classify as `.number`, carrying `minimum`/`maximum` through unmodified as `Double?` when declared, and inventing neither bound when absent (`ContributedSettings.swift:406-414`).
- **integer-classification**: a property whose `effectiveType` is `"integer"` MUST classify as `.integer`; a missing `default` MUST record `.missingDefault` and use `0`; a `default` that is not a whole JSON number MUST record `.defaultTypeMismatch` and use `0` (`ContributedSettings.swift:389-405`, `630-646`).
- **integer-bounds-rounding**: for an `"integer"` property, a declared `minimum` MUST be rounded up and a declared `maximum` MUST be rounded down to the nearest whole number before either is treated as a bound, because a bound that widened when rounded could let a clamp store a value the schema forbids (`ContributedSettings.swift:390-399`).
- **bounds-contradiction-dropped**: when both `minimum` and `maximum` are present for a `"number"` or `"integer"` property (after any integer rounding) and `minimum` exceeds `maximum`, both bounds MUST be dropped — treated as absent — and a `ContributedSettingNote(kind: .contradictoryBounds)` naming both values MUST be recorded (`ContributedSettings.swift:496-511`).
- **default-clamped-to-bounds**: when both bounds are present and agree, and the resolved default lies outside them, the default MUST be clamped to the nearer bound and a `ContributedSettingNote(kind: .defaultOutOfRange)` naming the original default and the bound used MUST be recorded; this clamp MUST run only after bounds have already been checked for agreement (`ContributedSettings.swift:521-537`).
- **array-object-to-json**: a property whose `effectiveType` is `"array"` or `"object"` MUST classify as `.json`, with `default` equal to the pretty-printed JSON text of the declared default, and MUST record no note for this classification — it is the type's intended destination, not a compromise (`ContributedSettings.swift:415-418`).
- **unrenderable-type-fallback**: a property whose `effectiveType` is any value other than `"boolean"`, `"string"`, `"integer"`, `"number"`, `"array"`, or `"object"` MUST classify as `.json` and MUST record a `ContributedSettingNote(kind: .unrenderableType)` naming the type (`ContributedSettings.swift:419-421`).
- **mixed-union-fallback**: when a property's declared `type` is a union whose non-null members do not collapse to exactly one name (so `effectiveType` is `nil`), classification MUST record a `ContributedSettingNote(kind: .mixedUnionType)` naming the union's members and MUST classify as `.json` using the declared default's JSON text (`ContributedSettings.swift:374-377`).
- **no-type-inference**: when a property declares no `type` at all (not a union, and `effectiveType` is `nil`), classification MUST be inferred from the JSON type of `default`: a boolean default classifies as `.toggle` with no note; a whole-number default classifies as `.integer` (bounds handled per `integer-bounds-rounding`); a non-whole-number default classifies as `.number`; a string default classifies as `.text` (honouring `editPresentation`); an array or object default classifies as `.json` with no note; a `null` default classifies as `.json` and records `.unrenderableType` ("no type, and a null default says nothing about one"); and an entirely absent default classifies as `.json` (rendering `"null"`) and records `.unrenderableType` ("no type, no enum and no default") (`ContributedSettings.swift:542-584`).
- **json-escape-hatch-text**: `jsonText(of:)` MUST render pretty-printed, key-sorted JSON with forward slashes left unescaped; a whole-number JSON value MUST render without a trailing `.0`; and a `nil` input MUST render as the JSON literal `null` (`ContributedSettings.swift:677-688`).
- **deprecation-appended**: when a property declares `deprecationMessage`, or, absent that, `markdownDeprecationMessage`, the resulting `ContributedSetting.explanation` MUST append that message after any `description`/`markdownDescription` body separated by one blank line, or stand alone when no body exists, and a `ContributedSettingNote(kind: .deprecated)` carrying that message as `detail` MUST be recorded, independent of what `ContributedSettingKind` the property classified as (`ContributedSettings.swift:266-269`, `655-666`).
- **explanation-source**: `explanation`'s body MUST be `description` when present, and otherwise `markdownDescription` treated as plain text — its Markdown syntax MUST NOT be rendered or stripped, only carried through verbatim, because nothing that displays this string renders Markdown (`ContributedSettings.swift:655-666`).
- **setting-order-field**: `ContributedSetting.order` MUST equal the property's own declared `order`, and that value MUST already have determined the setting's position within `settings` per `setting-ordering`.
- **sendable-value-types**: `ContributedSettingOption`, `ContributedSettingKind`, `ContributedSetting`, `ContributedSettingsSection`, `ContributedSettingNote`, and `ContributedSettingsDeclaration` MUST each be declared `Sendable` and `Equatable` value types, so a caller MAY pass any of them across an actor or `Task` boundary with no additional synchronization.
- **pure-no-side-effects**: `ContributedSettingsBuilder` MUST hold no mutable state of its own, and neither `sections(for:)` nor `storageName(forKey:ofExtension:)` MUST read a setting's stored value, write one, or perform any file, network, or window-system side effect — each call's only observable effect MUST be its return value.

## Appearance

Not applicable — this is a pure manifest-to-settings-row classifier, not a visual component.

## States

Not applicable — this is a pure manifest-to-settings-row classifier, not a visual component. Its only stateful concept, `ContributedSettingsDeclaration`'s three cases (`undeclared`, `declared`, `unreadable`), is a data-shape distinction covered under Behavioral Requirements, not a visual or lifecycle state.

## Accessibility

Not applicable — this is a pure manifest-to-settings-row classifier, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| contributed-settings-001 | undeclared-configuration | Decode an `ExtensionManifest` whose `contributes` declares no `configuration` key at all, then call `ContributedSettingsBuilder.sections(for:)` | `declaration == .undeclared` — mirrors `absentConfigurationStaysUndeclared`, `ContributedSettingsBuilderTests.swift:657` |
| contributed-settings-002 | unreadable-configuration | Decode a manifest whose `contributes.configuration` is the JSON string `"see the docs"` (neither an object nor an array), then call `sections(for:)` | `declaration` is `.unreadable`, not `.undeclared`, and `declaration.sections.isEmpty` — mirrors `unreadableConfigurationIsNotUndeclared`, line 644 |
| contributed-settings-003 | declared-when-nonempty-input, empty-section-dropped | Build with a single section `{ "title": "Empty", "properties": {} }` | `declaration == .declared(sections: [])` — mirrors the `onlyEmpty` case inside `emptySectionIsDropped`, line ~425 |
| contributed-settings-004 | empty-section-dropped | Build two sections, `{ "title": "Empty", "properties": {} }` and a second titled "Real" with one boolean property | `declaration.sections.map(\.title) == ["Real"]` — mirrors `emptySectionIsDropped`, line 414 |
| contributed-settings-005 | sorted-property-iteration, section-ordering, setting-ordering | Build the three-section fixture from `orderingIsOrderThenKey` (section `order`s 2/none/1; one section's four properties `order`d 1/2/none/none) | `sections.map(\.title) == ["Beta", "Zeta", "Alpha"]`; the "Zeta" section's `settings.map(\.key) == ["z.alpha", "a.beta", "b.delta", "m.gamma"]` — line 348 |
| contributed-settings-006 | duplicate-key-first-wins | Build two sections both declaring `acme.mode`: first `{ "type": "boolean", "default": false }`, second `{ "type": "string", "default": "auto" }` | one row only, `kind == .toggle(default: false)`; `notes` contains a `.duplicateKey` note keyed `"acme.mode"` — mirrors `aKeyDeclaredTwiceYieldsOneRow`, line 578 |
| contributed-settings-007 | storage-name-format, setting-key-verbatim | Declare the same key `python.pythonPath` (type `string`, default `"py"`) under two different extensions, `anysphere.pyright` and `ms-python.python` | `storageName`s are `"extensions.anysphere.pyright.python.pythonPath"` and `"extensions.ms-python.python.python.pythonPath"`; both rows' `key == "python.pythonPath"` — mirrors `storageNamesAreNamespacedPerExtension`, line 81 |
| contributed-settings-008 | section-title-resolution | Build one titleless section with one boolean property, manifest `displayName` set to "Sample Extension", then again with `displayName: nil` | first: `sections.map(\.title) == ["Sample Extension"]` and `notes == [.missingSectionTitle]` with `notes[0].key == "Sample Extension"`; second: title falls back to `"sample"` — mirrors `missingSectionTitleFallsBackToDisplayName`, line 375 |
| contributed-settings-009 | section-emptied-by-duplicates-dropped | Build two sections both declaring `acme.mode`, the second titled but with no other properties, so every one of its properties is a duplicate | the second section produces no `ContributedSettingsSection` and no `.missingSectionTitle` note, even if it declared no title — derived from the `!settings.isEmpty` guard at `ContributedSettings.swift:285`, run before title resolution |
| contributed-settings-010 | enum-string-choice, enum-label-positional, enum-default-matches | Classify `{ "type": "string", "enum": ["off","on","auto"], "enumItemLabels": ["Never","Always", null], "default": "on" }` | `.choice` with `options.map(\.label) == ["Never","Always","auto"]`, `options.map(\.value) == ["off","on","auto"]`, `selected == "on"` — mirrors `stringEnumBecomesChoice`, line 153 |
| contributed-settings-011 | enum-default-not-member | Classify `{ "type": "string", "enum": ["a","b"], "default": "legacy" }` | `.choice` with `options.map(\.value) == ["legacy","a","b"]`, `selected == "legacy"`, and a `.defaultNotInEnum` note — mirrors `defaultOutsideEnumIsPrepended`, line 172 |
| contributed-settings-012 | enum-default-null | Classify `{ "type": "string", "enum": ["a","b"], "default": null }` | `.choice` with `selected` equal to `"a"` (the first retained member) and a `.defaultTypeMismatch` note reading "default is null; the first member stands in" — derived from `ContributedSettings.swift:454-455` |
| contributed-settings-013 | enum-default-missing | Classify `{ "type": "string", "enum": ["a","b"] }` with no `default` key at all | `.choice` with `selected == "a"` and a `.missingDefault` note reading "no default; the first member stands in" — derived from `ContributedSettings.swift:457-458` |
| contributed-settings-014 | enum-mixed-falls-to-type | Classify `{ "type": "boolean", "enum": [true, "auto"], "default": true }` | `.toggle(default: true)` and a `.nonStringEnum` note — mirrors `nonStringEnumIgnoresTheEnum`, line 187 |
| contributed-settings-015 | enum-descriptions-dropped, sorted-property-iteration | Build the five-property "Notes" fixture from `notesFollowSortedKeyOrderNotDisplayOrder` (`e.five` declares `enumDescriptions`; each property's `order` reverses its key's alphabetical position) | `section.settings.map(\.key) == ["e.five","d.four","c.three","b.two","a.one"]` (display order by `order`); `notes.map(\.key) == ["a.one","b.two","c.three","d.four","e.five"]` (key-sorted note order); `notes.map(\.kind) == [.missingDefault, .unrenderableType, .mixedUnionType, .nonStringEnum, .enumDescriptionsDropped]` — line 444 |
| contributed-settings-016 | mixed-union-fallback | Classify `{ "type": ["boolean","string"], "default": true }` | `.json(default: "true")` and a `.mixedUnionType` note, `extensionIdentifier == "acme.sample"` — mirrors `mixedUnionFallsToJSON`, line 132 |
| contributed-settings-017 | number-classification | Classify `{ "type": "number", "default": 1.5 }` (no bounds) and `{ "type": "number", "default": 1.5, "minimum": 0.5, "maximum": 2.5 }` | first: `.number(default: 1.5, minimum: nil, maximum: nil)`; second: `.number(default: 1.5, minimum: 0.5, maximum: 2.5)` — mirrors `numberWithoutBoundsKeepsNilBounds` (line 203) and `numberWithBothBounds` (line 217) |
| contributed-settings-018 | boolean-default-fallback, string-default-fallback | Classify `{ "type": "string", "default": null }` and `{ "type": "boolean", "default": "yes" }` | first: `.text(default: "", multiline: false)` plus `.defaultTypeMismatch`; second: `.toggle(default: false)` plus `.defaultTypeMismatch` — mirrors `nullDefaultFallsToZeroValue` (line 233) and `mismatchedDefaultUsesTheDeclaredType` (line 248) |
| contributed-settings-019 | no-type-inference | Classify `{ "default": 3 }` and `{ "description": "nothing to go on" }` | first: `.integer(default: 3, minimum: nil, maximum: nil)` with no note; second: `.json(default: "null")` plus a `.unrenderableType` note — mirrors `noTypeInfersFromDefault`, line 264 |
| contributed-settings-020 | array-object-to-json, json-escape-hatch-text | Classify `{ "type": "object", "default": { "zebra": 1, "apple": [1,2] } }` and `{ "type": "array", "default": ["b","a"] }` | object case: `.json` text re-parses to the same value, `"apple"` occurs before `"zebra"`, the text spans more than one line, and contains no `.0`; array case: `.json` text re-parses to `["b","a"]` in that exact order — array elements are data, never sorted — mirrors `arrayAndObjectGetTheEscapeHatch`, line 292 |
| contributed-settings-021 | string-classification | Classify `{ "type": "string", "default": "hi", "editPresentation": "multilineText" }` | `.text(default: "hi", multiline: true)` — mirrors `multilineTextIsHonoured`, line 333 |
| contributed-settings-022 | deprecation-appended, explanation-source | Classify `{ "type": "boolean", "default": false, "description": "Turns the thing on.", "deprecationMessage": "Use a.new instead." }` | `explanation` equals the description body, a blank line, then the deprecation message; `notes == [.deprecated]` — mirrors `deprecationIsAppendedToTheExplanation`, line 393 |
| contributed-settings-023 | boolean-default-fallback, string-default-fallback | Classify `{ "type": "boolean" }` and `{ "type": "string" }`, each with no `default` key | `.toggle(default: false)` plus `.missingDefault`; `.text(default: "", multiline: false)` plus `.missingDefault` — mirrors `missingDefaultIsReported`, line 569 |
| contributed-settings-024 | sorted-property-iteration (upstream tolerance) | Build a section where one property spells `"order": "0"` (a string, not a number) alongside a sibling spelling `"order": 1`, and a second section where one property's JSON value is the bare string `"not an object"` alongside a well-formed sibling | first fixture: both properties survive as rows, `settings.map(\.key) == ["b.second","a.first"]`, `settings.map(\.order) == [1, nil]`; second fixture: only the well-formed sibling survives — mirrors `aMistypedFieldCostsOnlyThatField`, line 499 |
| contributed-settings-025 | bounds-contradiction-dropped, integer-bounds-rounding | Classify `{ "type": "number", "default": 5, "minimum": 10, "maximum": 1 }` and `{ "type": "integer", "default": 1, "minimum": 0.5, "maximum": 0.9 }` | first: `.number(default: 5, minimum: nil, maximum: nil)` plus a `.contradictoryBounds` note; second: `.integer(default: 1, minimum: nil, maximum: nil)` — `0.5` rounds up to `1`, `0.9` rounds down to `0`, and `1 > 0` inverts — mirrors `invertedBoundsAreDropped` (line 603) and `integerBoundsThatInvertAfterRoundingAreDropped` (line 618) |
| contributed-settings-026 | default-clamped-to-bounds | Classify `{ "type": "number", "default": 5, "minimum": 10, "maximum": 20 }` | `.number(default: 10, minimum: 10, maximum: 20)` and a `.defaultOutOfRange` note — mirrors `defaultOutsideItsBoundsIsClamped`, line 627 |
| contributed-settings-027 | entry-point-delegation | Decode a manifest whose `contributes.configuration` is the single-object form `{ "title": "One", "properties": {...} } }`, and separately the array form `[ {"title":"One",...}, {"title":"Two",...} ]`, then call `sections(for: manifest:)` | single-object form yields one section titled `"One"`; array form yields two sections titled `["One","Two"]` in that order — mirrors `singleObjectFormDecodes` (line 60) and `arrayFormDecodes` (line 68) |
| contributed-settings-028 | sendable-value-types, pure-no-side-effects | Round-trip an `ExtensionManifest.ConfigurationProperty` (union `type` included) through `JSONEncoder`/`JSONDecoder`; separately, capture a `ContributedSetting` value inside an async `Task` under `SWIFT_STRICT_CONCURRENCY: complete` | the round trip decodes back equal to the original — mirrors `propertyEncodingIsAFixedPoint`, line 530; the `Task` capture compiles with no Sendable diagnostic, since every public type in this file is declared `Sendable` |
| contributed-settings-029 | mixed-union-fallback | Classify `{ "type": ["number", null], "default": 1.5 }` and `{ "type": ["number", "null"], "default": 1.5 }` | both classify identically to `.number(default: 1.5, minimum: nil, maximum: nil)` — a JSON `null` member and the string `"null"` collapse to the same union result — mirrors `nullMemberInATypeUnionSurvives`, line 479 |

## Edge Cases

- **Null and empty input**: an extension manifest that declares no `contributes.configuration` key at all MUST classify as `.undeclared` (`undeclared-configuration`); a declared but empty `properties` dictionary within a section MUST drop that section entirely with no note (`empty-section-dropped`); a declared `enum` containing only `null` (no retained string member) MUST fail `choice(from:)` and fall through to type-based or default-based classification exactly like an enum with a non-string member.
- **Boundary values — bounds that invert**: a `minimum` greater than a `maximum` (before or, for `"integer"`, after inward rounding) MUST be treated as no bounds at all, with a `.contradictoryBounds` note, per `bounds-contradiction-dropped`.
- **Boundary values — default outside agreeing bounds**: MUST be clamped to the nearer bound with a `.defaultOutOfRange` note, per `default-clamped-to-bounds`.
- **integer-bound-overflow**: NEEDS REVIEW: Not implemented in source. `Int(exactly: $0.rounded(.up))`/`Int(exactly: $0.rounded(.down))` (`ContributedSettings.swift:397-398`) return `nil` for a `Double` bound with magnitude larger than `Int.max`, or for `.nan`/`.infinity`, and `.flatMap` then discards that bound silently — indistinguishable from a schema that declared no bound at all, and no `ContributedSettingNote` is recorded. Every other way a declared bound cannot be honoured (`contradictoryBounds`, a default outside the representable bounds) does produce a note; this path does not. What is missing: whether an out-of-`Int`-range `minimum`/`maximum` should record a note of its own, or is deliberately meant to be treated as absent. Evidence that would settle it: a ruling from whoever maintains `ContributedSettingsBuilder`'s corpus study (see the file's own doc comments citing corpus counts), or a corpus property that exercises this path.
- **Concurrent access**: not applicable as a hazard — `ContributedSettingsBuilder` is a stateless `enum` namespace of pure static functions over `Sendable` value types (`sendable-value-types`, `pure-no-side-effects`); concurrent calls from any thread or actor produce independent results with no shared mutable state to race.
- **Error states — a property that failed to decode at all**: not this file's concern. `ExtensionManifest.Configuration.init(from:)` decodes each property individually with `try?` (`ExtensionManifest.swift:760-771`), so a property whose JSON value is not an object (e.g. a bare string) never reaches `ContributedSettingsBuilder` at all — it is simply absent from `section.properties`, with no corresponding `ContributedSettingNote`; see `contributed-settings-024`.
- **Error states — `contributes.configuration` present but unreadable**: MUST classify as `.unreadable(reason:)`, not `.undeclared`, per `unreadable-configuration`.
- **Offline or disconnected state**: not applicable — `ContributedSettings.swift` performs no network call of any kind; it imports only `Foundation` and operates entirely over values already decoded into memory.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `manifest` | `ExtensionManifest` | none (required) | The decoded `package.json` passed to the `sections(for: manifest:)` overload; supplies `configuration`, `identifier`, `displayName ?? name`, and `decodingFailures` to the lower-level overload. |
| `configuration` | `[ExtensionManifest.Configuration]` | none (required) | The decoded `contributes.configuration` array (already normalized from VS Code's single-object-or-array form upstream) passed to the lower-level `sections(for:ofExtension:fallbackTitle:decodingFailures:)` overload. |
| `identifier` (`ofExtension`) | `String` | none (required) | The extension's case-folded `publisher.name` (or bare `name`), used verbatim in every `storageName` and every `ContributedSettingNote.extensionIdentifier` this call produces. |
| `fallbackTitle` | `String` | none (required) | The title a titleless section borrows — `manifest.displayName ?? manifest.name` at the one production call site. |
| `decodingFailures` | `[DecodingFailure]` | `[]` | Failures the manifest decoder recorded; only an entry whose `key == "contributes.configuration"` affects this file's output, distinguishing `.unreadable` from `.undeclared`. |
| `key` (to `storageName(forKey:ofExtension:)`) | `String` | none (required) | The dotted property key a caller wants the storage name for. |

No environment variable, settings key of its own, or injected dependency is read by this file — it is a pure function of its parameters.

## Deep Linking

Not applicable: `ContributedSettings.swift` defines no URL, route, or navigable destination — it is a manifest-to-row classifier with no navigation surface of its own.

## Localization

`ContributedSettingNote.detail` and the raw-text fallbacks it quotes (via `rawText(of:)`, `ContributedSettings.swift:690-706`) are shown to a person rather than swallowed — the type's own doc comment says so directly (`ContributedSettings.swift:100-105`, "what was compromised is shown to a person rather than swallowed") — but every one of those strings is composed as a hardcoded English literal interpolated inline (e.g. `"enum has a member that is not a string; classifying on type instead"`, `"section \(index) declared no title; using \"\(fallbackTitle)\""`); none is looked up through a String Catalog, `NSLocalizedString`, or any other localization key. A `ContributedSettingOption.label` that falls back to a member's raw `value` (per `enum-label-positional`) is similarly whatever text the extension manifest happened to write, never localized by this file.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — no localization key exists) | e.g. `"already declared by an earlier section; this declaration is ignored"` | `ContributedSettingNote.detail`, composed inline in English at each `note(...)` call site inside `classify`, `choice`, `agreeing`, `clamped`, `boolean`, `string`, `number`, `integer`, and `inferred` |

## Accessibility Options

Not applicable: `ContributedSettings.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; classification always runs the same way for any non-empty `configuration` input.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

Not applicable: `ContributedSettingsBuilder` classifies only a manifest's own *declared default* values — the schema an extension author wrote into `package.json` — never a user's actually-configured setting value; reading, storing, or transmitting a live setting value happens elsewhere (`ConfigurationContributionPoint` and its consumers), outside this file. Nothing here is a credential, token, or personally identifying value.

## Logging

Not applicable: `ContributedSettings.swift` makes no logging call of its own (no `Logger`, `os_log`, or `print`). Every compromise it makes is recorded as a `ContributedSettingNote` value for a caller to log or display, per `duplicate-key-first-wins`, `section-title-resolution`, and the classification requirements above — this file surfaces the information some other way rather than logging it itself.

## Platform Notes

- **SwiftUI**: not a dependency of this file — `ContributedSettings.swift` imports only `Foundation`. A SwiftUI settings screen would switch over `ContributedSettingKind` per row (`Toggle` for `.toggle`, `TextField`/multiline `TextEditor` for `.text`, `Picker` for `.choice`, a bounded `Slider`/`TextField` for `.number`/`.integer`, and a plain `TextEditor` for the `.json` escape hatch), grouped by `ContributedSettingsSection.title` in a `Form` with `Section` headers, with no additional state management needed since `sections(for:)` is a one-shot, non-observed call.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/Core/Extensions/ContributedSettings.swift`, part of the macOS-only `AgenticToolkitCore` framework target (`project.yml` declares `platform: macOS` for `AgenticToolkitCore`; there is no iOS target in this repository today). It is consumed by `ConfigurationContributionPoint` (`macOS/Features/Extensions/ConfigurationContributionPoint.swift`), the `AgenticToolkitMacOS`-side `ContributionPoint` that turns a `ContributedSettingsDeclaration` into AppKit views; neither AppKit nor UIKit is imported by `ContributedSettings.swift` itself, so the classifier would work unchanged behind a UIKit consumer.
- **Compose**: model `ContributedSettingKind` as a Kotlin `sealed class` (`Toggle`, `Text`, `Choice`, `Number`, `Integer`, `Json`, each a `data class` mirroring the Swift case's associated values) and `ContributedSettingsBuilder` as a Kotlin `object` of pure functions over a `kotlinx.serialization.json.JsonElement`-based manifest model in place of `ExtensionManifest.JSONValue`; keep the classifier in a plain Kotlin module with no Android framework import, mirroring this file's Foundation-only isolation, so it stays unit-testable off the main thread.
- **React/Web**: model `ContributedSettingKind` as a discriminated union, e.g. `{ kind: "toggle", default: boolean } | { kind: "text", default: string, multiline: boolean } | { kind: "choice", options: ContributedSettingOption[], default: string } | { kind: "number", default: number, minimum?: number, maximum?: number } | { kind: "integer", default: number, minimum?: number, maximum?: number } | { kind: "json", default: string }`; classify with a pure function over a parsed `package.json`-shaped object (`unknown` in place of `JSONValue`), and render each case through a component switch; sort sections and settings with `Array.prototype.sort` using the same two-level comparator this file's `precedes` functions apply.
- **WinUI 3**: the reason this recipe exists. Model `ContributedSettingKind` as a C# discriminated union — an abstract `record ContributedSettingKind` with `sealed record ToggleKind(bool Default)`, `TextKind(string Default, bool Multiline)`, `ChoiceKind(IReadOnlyList<ContributedSettingOption> Options, string Default)`, `NumberKind(double Default, double? Minimum, double? Maximum)`, `IntegerKind(int Default, int? Minimum, int? Maximum)`, and `JsonKind(string Default)` — each an immutable value type standing in for the Swift `enum` case's `Sendable` guarantee. Reimplement `ContributedSettingsBuilder` as a static class (`ContributedSettingsBuilder.Sections(ExtensionManifest manifest)`), classifying over `System.Text.Json.JsonElement`/`JsonDocument` in place of `ExtensionManifest.JSONValue` — `JsonElement.ValueKind` gives the same open-type dispatch the Swift `switch` over `JSONValue` does. Bind a settings panel's rows to WinUI controls per kind: `ToggleSwitch` for `ToggleKind`, `TextBox` (`AcceptsReturn = true` when `Multiline`) for `TextKind`, `ComboBox` for `ChoiceKind`, `NumberBox` (with `Minimum`/`Maximum` bound when present) for `NumberKind`/`IntegerKind`, and a plain multiline `TextBox` for `JsonKind`. Reproduce `jsonText(of:)`'s pretty-printed, key-sorted output with `System.Text.Json.JsonSerializerOptions { WriteIndented = true }` plus a `SortedDictionary`-backed intermediate or a custom `JsonConverter`, since `WriteIndented` alone does not sort keys. Reproduce the two Swift `precedes` comparators (order-ascending-with-nils-last, then title or key) with chained `OrderBy`/`ThenBy` calls over the same tiebreak sequence. `Sendable` has no direct C# equivalent; document the record types as immutable to carry the same intent, and note that C# offers no compiler-enforced analog to `pure-no-side-effects` — reviewers must verify by inspection that a WinUI 3 port makes the same no-I/O guarantee.

## Design Decisions

**Decision**: `storageName(forKey:ofExtension:)` builds a slot per *extension*, `"extensions.<identifier>.<key>"`, rather than storing directly under the manifest's own dotted key.
**Rationale**: the source's own doc comment records that 389 keys in the corpus this classifier was built against are declared by more than one extension, 18 of them disagreeing on `(type, default)` — one flat slot provably cannot hold both, and withdrawal (removing one extension's settings without touching another's) has to be able to name exactly what one extension owns (`ContributedSettings.swift:52-58`).
**Approved**: pending

**Decision**: `ContributedSetting.key` is kept as the manifest's full dotted key, never a namespace-stripped leaf.
**Rationale**: the source's own doc comment reports that the first dotted segment matches the extension's own name only 84% of the time in the Open VSX corpus studied (`anysphere.pyright` declares `python.pythonPath`), so stripping a namespace would strip the one token that says which setting a row actually is — VS Code's own settings UI shows the full key for the same reason (`ContributedSettings.swift:44-50`).
**Approved**: pending

**Decision**: an `enum` option's `label` is looked up positionally against the *declared* member index, before any `null` member is dropped, rather than against the filtered `values` array's index.
**Rationale**: `enumItemLabels` is indexed against the manifest's own `enum` array (`ContributedSettings.swift:432-433`, `450-452`); reindexing after dropping `null` members would silently mislabel every option that follows a dropped `null`, so the code deliberately looks up `members[index]`'s label before filtering, not after.
**Approved**: pending

**Decision**: a default that is present but does not match any retained enum member (`enum-default-not-member`) is inserted as a brand-new option at index 0, rather than being discarded in favor of the first declared member.
**Rationale**: the source's own comment states the stored value has to be representable, or the popup would silently rewrite it out from under the user (`ContributedSettings.swift:445-447`); inventing an option that carries the actual stored value forward is the only way a `.choice` control can round-trip a value the schema's own `enum` does not otherwise allow.
**Approved**: pending

**Decision**: `"integer"` bounds round `minimum` up and `maximum` down (rounding inward) rather than to the nearest whole number, and the inversion check for `bounds-contradiction-dropped` runs *after* that rounding.
**Rationale**: the source's own comment explains that a bound which widened when rounded — e.g. a `minimum` of `0.5` rounding down to `0` — is the one direction that could let a clamp store a value the declared schema forbids; and because `minimum: 1.2, maximum: 1.8` does not invert as written but does invert to `2...1` after inward rounding, the contradiction check has to run on the rounded values, not the raw ones (`ContributedSettings.swift:390-395`).
**Approved**: pending

**Decision**: `"array"` and `"object"` types classify straight to `.json` with no `ContributedSettingNote`, while every other unrenderable path (`unrenderable-type-fallback`, `mixed-union-fallback`, the `nil`-default/no-type case in `no-type-inference`) records one.
**Rationale**: the source's own inline comment states this directly — `array`/`object` are "where a structured value is *supposed* to land, not a compromise" (`ContributedSettings.swift:416-417`) — distinguishing an intended destination for the JSON escape hatch from every case where the escape hatch is a fallback for something this classifier could not otherwise render.
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
