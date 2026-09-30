<!-- leaf: implement-extension-host-core-1/extensions-extension-manifest--edge-cases · source: extension-host-core-extensions-extension-manifest.md -->

# ExtensionManifest

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-manifest--edge-cases#<slug>`):

- `null-empty-input` MUST — {} decoded as ExtensionManifest MUST throw (extension-manifest-001). A manifest with no contributes key at all MUST …
- `boundary-malformed-values` MUST — activationEvents/extensionKind/capabilities of the wrong JSON type MUST be tolerated (extension-manifest-013/014/015). …
- `concurrent-access` MUST — ExtensionManifest/Contributions/every nested type is a Sendable, side-effect-free value type; init(from:) allocates its …
- `error-states` MUST — A malformed name, version, engines.vscode, or contributes shape MUST sink the entire decode …

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
