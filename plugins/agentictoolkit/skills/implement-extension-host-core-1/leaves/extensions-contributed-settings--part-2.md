<!-- leaf: implement-extension-host-core-1/extensions-contributed-settings--part-2 · source: extension-host-core-extensions-contributed-settings.md -->

# ContributedSettings — continued (part 2)

**Rules** (cite as `implement-extension-host-core-1/extensions-contributed-settings--part-2#<slug>`):

- `entry-point-delegation` MUST
- `undeclared-configuration` MUST
- `unreadable-configuration` MUST
- `declared-when-nonempty-input` MUST
- `empty-section-dropped` MUST
- `sorted-property-iteration` MUST
- `duplicate-key-first-wins` MUST
- `section-emptied-by-duplicates-dropped` MUST
- `section-title-resolution` MUST
- `section-ordering` MUST
- `setting-ordering` MUST
- `storage-name-format` MUST
- `setting-key-verbatim` MUST
- `enum-string-choice` MUST
- `enum-label-positional` MUST
- `enum-null-member-dropped` MUST
- `enum-default-matches` MUST
- `enum-default-null` MUST
- `enum-default-not-member` MUST
- `enum-default-missing` MUST
- `enum-descriptions-dropped` MUST
- `enum-mixed-falls-to-type` MUST
- `boolean-classification` MUST
- `boolean-default-fallback` MUST
- `string-classification` MUST
- `string-default-fallback` MUST
- `number-classification` MUST
- `integer-classification` MUST
- `integer-bounds-rounding` MUST
- `bounds-contradiction-dropped` MUST
- `default-clamped-to-bounds` MUST
- `array-object-to-json` MUST
- `unrenderable-type-fallback` MUST

## Behavioral Requirements

- **entry-point-delegation**: `ContributedSettingsBuilder.sections(for: manifest:)` MUST delegate to `sections(for: configuration: ofExtension: fallbackTitle: decodingFailures:)`, passing `manifest.contributes?.configuration ?? []` as `configuration`, `manifest.identifier` as `ofExtension`, `manifest.displayName ?? manifest.name` as `fallbackTitle`, and `manifest.contributes?.decodingFailures ?? []` as `decodingFailures` (`ContributedSettings.swift`).
- **undeclared-configuration**: when `configuration` is empty and `decodingFailures` contains no entry whose `key` equals `"contributes.configuration"`, the function MUST return `(.undeclared, [])` (`ContributedSettings.swift`).
- **unreadable-configuration**: when `configuration` is empty and `decodingFailures` contains at least one entry whose `key` equals `"contributes.configuration"`, the function MUST return `(.unreadable(reason: failure.reason), [])`, using the `reason` of the first such entry, with no notes.
- **declared-when-nonempty-input**: when `configuration` is non-empty, the returned `declaration` MUST be `.declared`, even when filtering removes every section and `sections` ends up empty — `.declared(sections: [])` and `.undeclared` MUST remain distinguishable results (`ContributedSettings.swift`).
- **empty-section-dropped**: a `Configuration` element whose `properties` is empty MUST produce no `ContributedSettingsSection` and no `ContributedSettingNote` (`ContributedSettings.swift`).
- **sorted-property-iteration**: within one section, properties MUST be visited and classified in ascending lexicographic order of key (`section.properties.keys.sorted()`), never in the section's `Dictionary` iteration order, because that order is not stable across launches and would otherwise leak into `notes` (`ContributedSettings.swift`).
- **duplicate-key-first-wins**: when more than one section (processed in `configuration` array order, keys within a section in sorted order) declares the same property key, only the first-encountered declaration MUST become a row; every later declaration of that key MUST be skipped and MUST produce a `ContributedSettingNote(kind: .duplicateKey)` for that key whose `detail` is exactly `"already declared by an earlier section; this declaration is ignored"` (`ContributedSettings.swift`).
- **section-emptied-by-duplicates-dropped**: a section every one of whose properties was claimed by an earlier section MUST produce no `ContributedSettingsSection`, and MUST NOT produce a `missingSectionTitle` note, even when the section itself declared no title — the `!settings.isEmpty` guard runs before title resolution for exactly this reason (`ContributedSettings.swift`).
- **section-title-resolution**: a surviving section's `title` MUST be its own declared `title` when that value is non-nil and non-empty; otherwise it MUST be `fallbackTitle`, and a `ContributedSettingNote(kind: .missingSectionTitle)` MUST be recorded whose `key` is the resolved fallback title and whose `detail` is exactly `"section \(index) declared no title; using \"\(fallbackTitle)\""`, where `index` is the section's zero-based position in the decoded `configuration` array (`ContributedSettings.swift`).
- **section-ordering**: `declaration.sections` MUST be sorted so a section with a smaller declared `order` precedes one with a larger declared `order`; a section with a declared `order` MUST precede one with none; when neither rule distinguishes two sections, the one with the lexicographically smaller `title` MUST precede; when titles are equal too, the section that appeared earlier in the decoded `configuration` array MUST precede (`ContributedSettings.swift`).
- **setting-ordering**: within one section, `settings` MUST be sorted by the same rule applied to each `ContributedSetting.order`, with the final tiebreak being the setting's own `key` in ascending order rather than a title or array index, because keys are unique within one section (`ContributedSettings.swift`).
- **storage-name-format**: `storageName(forKey:ofExtension:)` MUST return exactly the string `"extensions.\(identifier).\(key)"`, and `ContributedSetting.storageName` MUST equal the result of calling it with that setting's own `key` and the extension's identifier (`ContributedSettings.swift`).
- **setting-key-verbatim**: `ContributedSetting.key` MUST equal the manifest's dotted property key exactly as declared, with no namespace stripped and no case change.
- **enum-string-choice**: a property whose `enum` is declared, non-empty, and (after dropping any `null` members) contains only JSON string members MUST classify as `.choice` (`ContributedSettings.swift`).
- **enum-label-positional**: each produced `ContributedSettingOption.label` MUST be `enumItemLabels[i]` at the member's original, pre-null-filter index when that entry is present and non-nil, and MUST otherwise be the option's own `value`.
- **enum-null-member-dropped**: a `null` member of a declared `enum` MUST be omitted from the resulting options and MUST NOT by itself prevent the property from classifying as `.choice`.
- **enum-default-matches**: when `default` is a JSON string equal to one of the enum's retained, non-null string members, that value MUST be selected with no note recorded for the default.
- **enum-default-null**: when `default` is the JSON literal `null`, a `ContributedSettingNote(kind: .defaultTypeMismatch)` with detail `"default is null; the first member stands in"` MUST be recorded, and the first retained member MUST be selected.
- **enum-default-not-member**: when `default` is present, is not `null`, and either is not a JSON string or is a string absent from the enum's retained members, a `ContributedSettingNote(kind: .defaultNotInEnum)` MUST be recorded quoting the default's raw text, a new `ContributedSettingOption` whose `label` and `value` both equal that raw text MUST be inserted at index 0 of `options`, and it MUST be selected.
- **enum-default-missing**: when `enum` is declared and classifies as `.choice` but `default` is absent entirely, a `ContributedSettingNote(kind: .missingDefault)` with detail `"no default; the first member stands in"` MUST be recorded and the first retained member MUST be selected.
- **enum-descriptions-dropped**: when a property classifies as `.choice` and declares `enumDescriptions` or `markdownEnumDescriptions`, a `ContributedSettingNote(kind: .enumDescriptionsDropped)` MUST be recorded regardless of which default-resolution branch ran.
- **enum-mixed-falls-to-type**: when `enum` is declared and non-empty but at least one non-null member is not a JSON string, a `ContributedSettingNote(kind: .nonStringEnum)` MUST be recorded and classification MUST proceed using `effectiveType` (or default-based inference) instead of the enum (`ContributedSettings.swift`).
- **boolean-classification**: a property whose `effectiveType` is `"boolean"` MUST classify as `.toggle` (`ContributedSettings.swift`).
- **boolean-default-fallback**: for a `.toggle` classification, a missing `default` MUST record `ContributedSettingNote(kind: .missingDefault)` ("no default; false stands in") and use `false`; a `default` that is not a JSON boolean MUST record `ContributedSettingNote(kind: .defaultTypeMismatch)` and use `false` (`ContributedSettings.swift`).
- **string-classification**: a property whose `effectiveType` is `"string"` MUST classify as `.text`, with `multiline` `true` if and only if `editPresentation == "multilineText"` (`ContributedSettings.swift`).
- **string-default-fallback**: for a `.text` classification, a missing `default` MUST record `ContributedSettingNote(kind: .missingDefault)` ("no default; the empty string stands in") and use `""`; a `default` that is not a JSON string MUST record `ContributedSettingNote(kind: .defaultTypeMismatch)` and use `""` (`ContributedSettings.swift`).
- **number-classification**: a property whose `effectiveType` is `"number"` MUST classify as `.number`, carrying `minimum`/`maximum` through unmodified as `Double?` when declared, and inventing neither bound when absent (`ContributedSettings.swift`).
- **integer-classification**: a property whose `effectiveType` is `"integer"` MUST classify as `.integer`; a missing `default` MUST record `.missingDefault` and use `0`; a `default` that is not a whole JSON number MUST record `.defaultTypeMismatch` and use `0` (`ContributedSettings.swift`, `630-646`).
- **integer-bounds-rounding**: for an `"integer"` property, a declared `minimum` MUST be rounded up and a declared `maximum` MUST be rounded down to the nearest whole number before either is treated as a bound, because a bound that widened when rounded could let a clamp store a value the schema forbids (`ContributedSettings.swift`).
- **bounds-contradiction-dropped**: when both `minimum` and `maximum` are present for a `"number"` or `"integer"` property (after any integer rounding) and `minimum` exceeds `maximum`, both bounds MUST be dropped — treated as absent — and a `ContributedSettingNote(kind: .contradictoryBounds)` naming both values MUST be recorded (`ContributedSettings.swift`).
- **default-clamped-to-bounds**: when both bounds are present and agree, and the resolved default lies outside them, the default MUST be clamped to the nearer bound and a `ContributedSettingNote(kind: .defaultOutOfRange)` naming the original default and the bound used MUST be recorded; this clamp MUST run only after bounds have already been checked for agreement (`ContributedSettings.swift`).
- **array-object-to-json**: a property whose `effectiveType` is `"array"` or `"object"` MUST classify as `.json`, with `default` equal to the pretty-printed JSON text of the declared default, and MUST record no note for this classification — it is the type's intended destination, not a compromise (`ContributedSettings.swift`).
- **unrenderable-type-fallback**: a property whose `effectiveType` is any value other than `"boolean"`, `"string"`, `"integer"`, `"number"`, `"array"`, or `"object"` MUST classify as `.json` and MUST record a `ContributedSettingNote(kind: .unrenderableType)` naming the type (`ContributedSettings.swift`).
