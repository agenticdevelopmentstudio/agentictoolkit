<!-- leaf: implement-extension-host-core-1/extensions-extension-manifest--part-3 · source: extension-host-core-extensions-extension-manifest.md -->

# ExtensionManifest — continued (part 3)

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-manifest--part-3#<slug>`):

- `decoding-failure-text-type-mismatch-unnamed` MUST
- `decoding-failure-text-value-not-found` MUST
- `decoding-failure-text-data-corrupted` MUST
- `decoding-failure-text-non-decoding-error` MUST
- `decoding-failure-subject-empty-path` MUST
- `json-value-shape` MUST
- `json-value-nested-not-top-level` MUST
- `theme-strict-shape` MUST
- `snippet-strict-shape` MUST
- `language-optional-fields` MUST
- `command-icon-string-form-only` MUST
- `keybinding-args-not-carried` MUST
- `menu-item-strict-shape` MUST
- `configuration-title-id-order-independently-tolerant` MUST
- `configuration-properties-per-property-isolation` MUST
- `configuration-property-type-single-or-union` MUST
- `configuration-property-effective-type-collapse` MUST
- `configuration-property-every-field-independently-tolerant` MUST
- `configuration-property-enum-item-labels-nullable-elements` MUST
- `view-identity-strict-decorations-tolerant` MUST
- `view-unreadable-keys-recorded-per-field` MUST
- `view-explicit-null-treated-as-withdrawn` MUST
- `view-unreadable-keys-not-encoded` MUST
- `view-container-strict-identity-tolerant-decorations` MUST
- `language-model-tool-plain-shape` MUST
- `manifest-and-contributions-are-sendable-value-types` MUST

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

