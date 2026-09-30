<!-- leaf: implement-extension-host-vs-1/code-api-host-language-vocabulary · source: extension-host-vs-code-api-host-language-vocabulary.md -->

**Rules** (cite as `implement-extension-host-vs-1/code-api-host-language-vocabulary#<slug>`):

- `protocol-conformance` MUST
- `built-ins-first-ordering` MUST
- `built-in-deduplication` MUST
- `default-language-inclusion` MUST
- `default-language-position` MUST
- `contributed-deduplication` MUST
- `contributed-order-preservation` MUST
- `tsname-exclusion` MUST
- `host-vocabulary-fidelity` MUST
- `computed-not-cached` MUST
- `main-actor-isolation` MUST
- `init-dependency` MUST
- `non-sendable-declaration` MUST

# HostLanguageVocabulary

## Overview

`HostLanguageVocabulary` is `AgenticToolkitMacOS`'s production conformer of
the `ExtensionLanguageVocabulary` seam (`MainThreadLanguages.swift`),
which `MainThreadLanguages.getLanguages` calls to answer
`vscode.languages.getLanguages()`. It composes two already-deterministic
halves into one deterministic list: every built-in identifier from the
third-party `CodeEditLanguages` package's `CodeLanguage.allLanguages`, in
that array's own order, with `CodeLanguage.default`'s id appended, followed
by every identifier `LanguageContributionPoint.contributedLanguageIdentifiers`
reports that is not already present. Built-ins lead deliberately: per the
source's own doc comment, an extension contributing an id CodeEditLanguages
already has is adding a file-extension claim to an existing language, not
declaring a new one, and the built-in entry is the one that was there first.
The identifiers this type returns are this host's own vocabulary, not a
translation into VS Code's spellings.

## Behavioral Requirements

- **protocol-conformance**: `HostLanguageVocabulary` MUST conform to
  `ExtensionLanguageVocabulary`, exposing exactly one member,
  `languageIdentifiers: [String]`.
- **built-ins-first-ordering**: `languageIdentifiers` MUST list every
  identifier drawn from `CodeLanguage.allLanguages` (via `language.id.rawValue`)
  before any identifier drawn from `contributionPoint.contributedLanguageIdentifiers`,
  in `CodeLanguage.allLanguages`'s own array order.
- **built-in-deduplication**: while building the built-in portion, an
  identifier already added from an earlier entry in `CodeLanguage.allLanguages`
  MUST NOT be appended again; this loop MUST track seen identifiers in a
  `Set<String>` and append only when insertion into that set reports a new
  member.
- **default-language-inclusion**: `languageIdentifiers` MUST include
  `CodeLanguage.default.id.rawValue`, even though `CodeLanguage.allLanguages`
  does not itself contain `CodeLanguage.default`.
- **default-language-position**: the default identifier MUST be appended
  immediately after the built-in loop completes and before any contributed
  identifier is considered, and MUST be skipped if it was already added
  (e.g. because a future `CodeEditLanguages` release includes it in
  `allLanguages`), using the same seen-set the built-in loop populated.
- **contributed-deduplication**: an identifier from
  `contributionPoint.contributedLanguageIdentifiers` that duplicates an
  identifier already added from the built-in or default portion MUST NOT be
  appended a second time; it MUST appear only once, at its earlier
  (built-in or default) position.
- **contributed-order-preservation**: contributed identifiers that are not
  already present MUST be appended in exactly the order
  `contributionPoint.contributedLanguageIdentifiers` returns them, with no
  re-sorting or re-grouping performed by `HostLanguageVocabulary` itself.
- **tsname-exclusion**: `languageIdentifiers` MUST be built from
  `CodeLanguage.id`, never from `CodeLanguage.tsName`; `id` values are used
  because `tsName` names a shared tree-sitter grammar rather than a
  language, and several distinct languages (JSX and JavaScript, TSX and
  TypeScript, an OCaml interface and OCaml) share one `tsName` while each
  keeps its own `id`.
- **host-vocabulary-fidelity**: `languageIdentifiers` MUST return this
  host's own identifiers as `CodeLanguage.id` and
  `LanguageContributionPoint.contributedLanguageIdentifiers` define them
  (for example `cSharp`, `jsx`, `tsx`, `objc`, `bash`, `goMod`, `jsdoc`,
  `markdownInline`, `regex`) rather than identifiers translated into
  whatever spelling `vscode.d.ts` or a real VS Code installation would use
  for the same language.
- **computed-not-cached**: `languageIdentifiers` MUST be a computed
  property that rebuilds its result from `CodeLanguage.allLanguages`,
  `CodeLanguage.default`, and `contributionPoint.contributedLanguageIdentifiers`
  on every access; it MUST NOT read from or write to any stored, cached
  copy of the result, because `contributionPoint`'s contributions can
  change between calls as extensions load and unload.
- **main-actor-isolation**: `HostLanguageVocabulary` MUST be declared
  `@MainActor`, so every access to `languageIdentifiers` and to the stored
  `contributionPoint` executes on the main actor.
- **init-dependency**: `init(contributionPoint:)` MUST take a
  `LanguageContributionPoint` as `HostLanguageVocabulary`'s sole
  constructor argument and MUST store it for the instance's lifetime as
  the only source `languageIdentifiers` consults for contributed
  identifiers.
- **non-sendable-declaration**: `HostLanguageVocabulary` MUST NOT declare
  conformance to `Sendable`; as a `public final class` with no `Sendable`
  conformance, isolated only by its `@MainActor` annotation, the compiler
  MUST confine every instance to the main actor's isolation domain and
  reject an attempt to use it from another isolation domain without an
  `await` hop.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `contributionPoint` (init parameter) | `LanguageContributionPoint` | none (required) | The extension-contributed language source `languageIdentifiers` reads via `contributedLanguageIdentifiers`; the sole dependency `HostLanguageVocabulary` is constructed with. |

There are no environment variables or settings keys: `HostLanguageVocabulary`
reads only its injected `contributionPoint` and the linked-in
`CodeEditLanguages` package's `CodeLanguage.allLanguages`/`CodeLanguage.default`.

## Privacy

- **Data collected**: none beyond what `contributionPoint` already holds.
  The only data `HostLanguageVocabulary` reads is language identifiers —
  either CodeEditLanguages' bundled catalogue or identifiers already
  extracted from installed extensions' manifests — never device- or
  user-identifying data.
- **Storage**: none. `HostLanguageVocabulary` stores only a reference to
  the `LanguageContributionPoint` it was constructed with; it writes
  nothing to disk itself.
- **Transmission**: none. This component performs no networking.
- **Retention**: for the lifetime of the `HostLanguageVocabulary` instance
  and the `contributionPoint` reference it holds; releasing either
  releases the data with it.

## Platform Notes

- **SwiftUI**: the source (`HostLanguageVocabulary.swift`, alongside
  `LanguageContributionPoint.swift` for the contributed half and
  `MainThreadLanguages.swift` for the `ExtensionLanguageVocabulary`
  protocol it conforms to) is a plain `@MainActor` Foundation type with no
  dependency on SwiftUI or any view-layer framework; it imports only
  `CodeEditLanguages` and `Foundation`. A port that keeps this component in
  Swift needs nothing beyond those two imports plus whatever type stands
  in for `LanguageContributionPoint`.
- **Compose**: no JVM equivalent of CodeEditLanguages' bundled tree-sitter
  language catalogue exists as a drop-in dependency; model the built-in
  half as a locally maintained, ordered list of language ids standing in
  for `CodeLanguage.allLanguages`, deduplicate it with a `LinkedHashSet`
  exactly as the Swift `seen: Set<String>` guard does, then append a
  contribution source's own ordered list the same way. Confine the
  composing function or class to Android's main thread, mirroring
  `@MainActor`, since nothing here needs to run off it.
- **React/Web**: model `languageIdentifiers` as a plain function (or a
  getter with no memoization) that rebuilds its result on every call,
  never a cached value, backed by a JS `Set` for the same seen-before
  dedup a `for` loop with `.has()`/`.add()` gives. There is no actor
  concept in a single-threaded JS runtime, so `main-actor-isolation`
  collapses to "call this only from the execution context that owns the
  contribution registry."
- **AppKit / UIKit**: identical to the SwiftUI note — the component
  depends on neither AppKit nor UIKit. It lives under this codebase's
  `macOS` target today, but nothing about it is macOS-specific; the same
  type would compile unchanged linked into an iOS host with a
  CodeEditLanguages-compatible catalogue and a compatible contribution
  point.
- **WinUI 3**: no Windows App SDK or .NET type maps to CodeEditLanguages'
  bundled tree-sitter grammar catalogue, so the built-in half needs a
  locally maintained ordered table of language ids rather than an existing
  library. Port `HostLanguageVocabulary` as a plain C# class exposing an
  `IReadOnlyList<string> LanguageIdentifiers` computed property (a getter,
  never a cached field, mirroring `computed-not-cached`) that concatenates
  that table with the contribution point's own `ContributedLanguageIdentifiers`,
  deduplicating both halves with a `HashSet<string>` the way `Set<String>`
  does here. There is no `@MainActor` in .NET, so confine access with the
  same UI-thread affinity `LanguageContributionPoint`'s own C# port
  already requires (dispatch through the WinUI 3 dispatcher queue, not a
  bare lock). `HttpClient`, `System.Text.Json`, `Windows.Storage`, `Task`/
  `async`, `ObservableCollection`, and `INotifyPropertyChanged` have no
  role: this component performs no networking, serialization, or
  persistence, is entirely synchronous, and nothing here is bound to a UI
  or mutated in place — each read produces an independent, freshly built
  list.

