<!-- leaf: implement-extension-host-core-1/extensions-extension-manifest--part-4 · source: extension-host-core-extensions-extension-manifest.md -->

# ExtensionManifest — continued (part 4)

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-manifest--part-4#<slug>`):

- `platform-i18n-layer-decide-design-choice-outside` MUST — Every string above is hardcoded English with no lookup table, ICU message, or locale parameter anywhere in …

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
