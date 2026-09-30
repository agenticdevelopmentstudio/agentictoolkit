<!-- leaf: implement-extension-host-core-1/extensions-extension-manifest--part-2 · source: extension-host-core-extensions-extension-manifest.md -->

# ExtensionManifest — continued (part 2)

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-manifest--part-2#<slug>`):

- `decodes-vscode-package-json-subset` MUST
- `top-level-identity-required` MUST
- `identity-decoded-before-lenient-fields` MUST
- `optional-descriptive-fields-decode-if-present` MUST
- `engines-vscode-required` MUST
- `display-identifier-composition` MUST
- `identifier-case-folding` MUST
- `activation-events-defaults-empty` MUST
- `activation-events-tolerant` MUST
- `extension-kind-nil-means-absent` MUST
- `extension-kind-tolerant` MUST
- `capabilities-tolerant` MUST
- `contributes-strict` MUST
- `untrusted-workspaces-support-tri-form` MUST
- `decoding-failures-not-encoded` MUST
- `contributions-empty-static-value` MUST
- `contributions-absent-vs-empty-equivalence` MUST
- `contributions-arrays-default-empty` MUST
- `contributions-dictionaries-default-empty` MUST
- `contributions-encode-lossy` MUST
- `lenient-array-absent-key-returns-empty` MUST
- `lenient-array-strict-fast-path` MUST
- `lenient-array-single-object-tolerance` MUST
- `lenient-array-non-array-non-object-failure` MUST
- `lenient-array-element-isolation` MUST
- `lenient-array-strict-first-perf-rationale` MUST
- `lenient-dictionary-absent-key-returns-empty` MUST
- `lenient-dictionary-strict-fast-path` MUST
- `lenient-dictionary-whole-value-failure` MUST
- `lenient-dictionary-location-isolation` MUST
- `lenient-dictionary-element-isolation` MUST
- `lenient-value-absent-vs-unreadable` MUST
- `decoding-failure-text-key-not-found` MUST
- `decoding-failure-text-type-mismatch-named` MUST

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
