<!-- leaf: implement-extension-host-core-1/extensions-open-vsx-catalog--part-2 · source: extension-host-core-extensions-open-vsx-catalog.md -->

# OpenVSXCatalog — continued (part 2)

## Platform Notes

- **Swift (source)**: This file targets macOS today, via the
  `AgenticToolkitCore` framework target (`project.yml`); nothing in it —
  plain `Codable`/`Sendable` structs and enums over Foundation's
  `JSONDecoder` and `URL` — depends on `AppKit`, `UIKit`, or any other
  platform framework, so the same source would decode identically if the
  target grew an iOS platform tomorrow.
- **React/Web/TypeScript**: A hand-rolled parser or a schema library such as
  `zod`/`io-ts` replaces `Codable`; URL-shaped fields are typed `string` and
  parsed lazily with the global `URL` constructor (or a `try`/`catch`
  wrapper around it) only inside the equivalent of `iconURL`/`sha256URL`,
  never eagerly at the top-level parse, to preserve the
  **url-shaped-fields-decoded-as-string** isolation; `installability` is a
  plain function returning a discriminated union
  (`{ kind: "installable" } | { kind: "engineIncompatible"; range } | ...`)
  rather than a class hierarchy.
- **Compose/Android (Kotlin)**: `kotlinx.serialization` with a `data class`
  per response shape replaces `Codable`; a `sealed interface` with
  `data class`/`data object` cases is the equivalent of
  `OpenVSXInstallability`, and `installability` becomes a plain `fun`
  returning that sealed type — a `when` expression over it, rather than a
  `Boolean`, is how a caller renders each refusal distinctly.
- **WinUI 3 (C#)**: `System.Text.Json` (`JsonSerializer`, `JsonDocument`)
  replaces `Codable`, with URL-shaped registry fields typed `string`
  properties, never `System.Uri`, and parsed on demand inside computed
  properties (`Uri.TryCreate`, never the throwing `Uri` constructor) to
  preserve the same per-accessor isolation. `installability`'s required
  fields — the equivalent of `namespace`, `name`, and `version` failing the
  whole decode — need the C# `required` keyword on those three properties
  (or a custom `JsonConverter<T>` that checks for their presence explicitly)
  because `System.Text.Json` otherwise leaves a missing non-nullable
  `string` property at its default rather than throwing, which would
  silently drop **search-page-array-decode-is-all-or-nothing**'s "throws for
  the whole page" behavior. A `SemanticVersion`-equivalent `readonly record
  struct` and a ported `VSCodeEngineRange` parser stand in for the two
  Swift helper types this file depends on; `OpenVSXInstallability` itself
  becomes a `record`-per-case discriminated union (an `abstract record` base
  with one `sealed record` per case, or a single `record` with an `enum Kind`
  discriminant plus optional payload fields) rather than an
  `ObservableCollection<T>` or `INotifyPropertyChanged` type, since nothing
  in this contract needs mutation notification — the verdict is a one-shot,
  immutable computation.

## Design Decisions

**Decision**: `OpenVSXSearchEntry.files`, `OpenVSXExtensionDetail.downloads`,
and `OpenVSXExtensionDetail.files` decode every URL-shaped value as `String`,
never as `URL`, with each computed accessor (`iconURL`, `sha256URL`,
`universalDownloadURL`, and the rest) parsing its own key lazily.
**Rationale**: The source's own top-of-file doc comment states the reason
directly: `URL`'s `Decodable` conformance throws on a string it cannot
parse, which would mean one extension with a malformed icon URL takes down
the decode of the whole search page it appeared in. Decoding as `String`
and parsing per-accessor means a bad URL costs exactly the accessor that
reads it.
**Approved**: pending

**Decision**: That per-accessor URL isolation does not extend to
`OpenVSXSearchPage.extensions` as a whole — a search entry missing a
required field still sinks the entire page's decode, with no per-element
recovery of the kind `ExtensionManifest`'s `LenientDecoding` implements for
`contributes.*` collections.
**Rationale**: The source's stated protection is scoped to URL-shaped
fields specifically, via computed accessors; the array itself is decoded
through `Decodable`'s ordinary synthesis with no custom `init(from:)`
anywhere in `OpenVSXSearchEntry` or `OpenVSXSearchPage`. This is a real,
narrower guarantee than a reader might infer from the doc comment's framing
around "one row's bad icon URL does not take the page with it" — that
sentence is true only for the icon URL and its siblings, not for a
structurally malformed entry.
**Approved**: pending

**Decision**: `installability(forHostVersion:)` checks `targetPlatform`
before checking whether a universal download exists, and checks download
existence before the engine-range gate.
**Rationale**: The source's own doc comment states the check runs "before
the download rather than after, because every refusal here is knowable from
metadata alone and a user who is going to be told 'no' should be told before
several megabytes cross the network." `OpenVSXCatalogTests`'
`platformSpecificRefusesFirst` pins the platform-first ordering explicitly,
noting a platform-specific build "refuses before the engine is even read" —
this is a tested contract, not incidental code order.
**Approved**: pending

**Decision**: `OpenVSXInstallability` is a `Sendable`, `Equatable` enum with
one named case per refusal reason, rather than a `Bool` paired with a
freeform message string.
**Rationale**: The source's own doc comment names the reason: a settings UI
"has to say which wall an extension hit" — "needs VS Code 1.140" and "ships
a macOS binary" are different situations with different answers — and a
reason assembled as prose at the point of refusal "cannot be tested or
localized." The comment names this explicit-over-implicit.
**Approved**: pending

**Decision**: `OpenVSXExtensionDetail.engineRange` collapses "no
`engines.vscode` key" and "an `engines.vscode` value that fails to parse"
into the same `nil`, even though `installability(forHostVersion:)` treats
those two situations differently (ungated vs. `.engineRangeUnreadable`).
**Rationale**: The property's own doc comment states plainly that "an
extension with no `engines.vscode` is not gated — see
`installability(forHostVersion:)`," pointing the reader at the one place
that does draw the distinction. `engineRange` is a convenience accessor for
callers that only need the parsed range when one exists; the
absent-vs-unreadable distinction is deliberately implemented once, inside
`installability(forHostVersion:)`, rather than duplicated at this property.
**Approved**: pending
