---
id: e711e689-78e6-403f-8f3c-ed9f29053e8e
title: HostLanguageVocabulary
domain: agentictoolkit://recipes/extension-host-vs-code-api-host-language-vocabulary
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The production ExtensionLanguageVocabulary conformer for vscode.languages.getLanguages():
  CodeEditLanguages'' built-in catalogue, built-ins first, followed by LanguageContributionPoint''s
  contributed identifiers.'
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- languages
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/HostLanguageVocabulary.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadLanguages.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/LanguageContributionPoint.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadLanguagesVocabularyTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# HostLanguageVocabulary

## Overview

`HostLanguageVocabulary` is `AgenticToolkitMacOS`'s production conformer of
the `ExtensionLanguageVocabulary` seam (`MainThreadLanguages.swift:522`),
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

## Appearance

Not applicable — this is a language-identifier vocabulary provider, not a
visual component.

## States

Not applicable — this is a language-identifier vocabulary provider, not a
visual component.

## Accessibility

Not applicable — this is a language-identifier vocabulary provider, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hlv-001 | contributed-deduplication | `LanguageContributionPoint` with one extension contributing `{ "id": "swift", "extensions": [".notswift"] }`; `HostLanguageVocabulary(contributionPoint:).languageIdentifiers` | `.filter { $0 == "swift" }.count == 1` — source: `HostLanguageVocabularyTests.aContributedBuiltInIdentifierIsNotDuplicated` |
| hlv-002 | default-language-inclusion | `LanguageContributionPoint` with no contributions; `HostLanguageVocabulary(contributionPoint:).languageIdentifiers` | `.contains(CodeLanguage.default.id.rawValue)` is `true` — source: `HostLanguageVocabularyTests.plainTextIsPresent` |
| hlv-003 | built-ins-first-ordering, contributed-order-preservation | `LanguageContributionPoint` with one extension contributing `{ "id": "cobol", "extensions": [".cob"] }`; the resulting `languageIdentifiers`' index of `python` versus its index of `cobol` | index of `python` is less than index of `cobol` — source: `HostLanguageVocabularyTests.mergesBuiltInAndContributedIdentifiersWithBuiltInsLeading` |
| hlv-004 | computed-not-cached | call `languageIdentifiers` twice on the same `HostLanguageVocabulary` instance with no mutation of `contributionPoint` between calls | both calls return equal arrays, and neither call is served from a stored field — traced to the source's "Computed, never cached" doc comment; no dedicated test |
| hlv-005 | contributed-order-preservation | `LanguageContributionPoint` with one extension contributing languages in the manifest order `["second", "first", "third"]` (none matching a built-in) | the tail of `languageIdentifiers` reads `["second", "first", "third"]`, matching `contributedLanguageIdentifiers`'s own manifest-order guarantee — traced to `LanguageContributionPointVocabularyTests.contributedIdentifiersPreserveManifestOrderWithinOneExtension`, composed through `HostLanguageVocabulary`; no dedicated `HostLanguageVocabularyTests` case |
| hlv-006 | tsname-exclusion | `LanguageContributionPoint` with no contributions; `HostLanguageVocabulary(contributionPoint:).languageIdentifiers` | contains `javascript`, `jsx`, `typescript`, and `tsx` as four distinct entries, none collapsed into a shared `tsName` — traced to the source's "Does not use `CodeLanguage.tsName`" doc comment; no dedicated test |
| hlv-007 | main-actor-isolation, non-sendable-declaration | a non-`@MainActor` call site reading `languageIdentifiers` on a `HostLanguageVocabulary` instance without an `await` hop | fails to compile — traced to the `@MainActor` declaration with no `Sendable` conformance; compiler-enforced, no dedicated runtime test |

## Edge Cases

- **Null/empty contributions**: when `contributionPoint.contributedLanguageIdentifiers`
  is empty (no extension has contributed a language), `languageIdentifiers`
  MUST still return the full built-in set plus the default identifier; it
  MUST NOT return an empty array (`default-language-inclusion`, `hlv-002`).
- **Boundary values**: MUST NOT apply a maximum length or count to
  `languageIdentifiers`; any number of contributed identifiers, including
  one that duplicates every built-in identifier, MUST be accepted and
  deduplicated the same way a single duplicate is (`contributed-deduplication`).
- **Concurrent access**: `HostLanguageVocabulary` is `@MainActor`, so every
  read of `languageIdentifiers` and every read of the stored
  `contributionPoint` executes serialized on the main actor; concurrent
  calls from other isolation domains MUST NOT compile without an `await`
  hop, and the type defines no additional locking because the actor
  already serializes access (`main-actor-isolation`, `non-sendable-declaration`).
- **Error states**: not applicable in the throwing or `Optional`-unwrapping
  sense — `languageIdentifiers` is a synchronous, non-throwing computed
  property with no failure path; every input it consumes
  (`CodeLanguage.allLanguages`, `CodeLanguage.default`,
  `contributionPoint.contributedLanguageIdentifiers`) is already a plain,
  non-optional `[String]` or `String` by the time this type reads it.
- **Offline/disconnected**: not applicable — this component performs no
  networking and touches no filesystem; `CodeLanguage.allLanguages` is
  linked-in package data and `contributionPoint`'s contributions were
  already parsed and applied before this type reads them.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `contributionPoint` (init parameter) | `LanguageContributionPoint` | none (required) | The extension-contributed language source `languageIdentifiers` reads via `contributedLanguageIdentifiers`; the sole dependency `HostLanguageVocabulary` is constructed with. |

There are no environment variables or settings keys: `HostLanguageVocabulary`
reads only its injected `contributionPoint` and the linked-in
`CodeEditLanguages` package's `CodeLanguage.allLanguages`/`CodeLanguage.default`.

## Deep Linking

Not applicable: `HostLanguageVocabulary.swift` composes an in-process array
of language identifiers; it defines no URL scheme, route, or navigable
destination.

## Localization

Not applicable: `HostLanguageVocabulary.swift` produces no user-facing
string. The identifiers it returns (`python`, `cSharp`, `jsx`, and so on)
are protocol-level vocabulary consumed by extension JavaScript, not text
displayed to a person.

## Accessibility Options

Not applicable: this component has no visual or interactive surface for a
system accessibility display option to affect.

## Feature Flags

Not applicable: `HostLanguageVocabulary.swift` defines no feature flag,
build configuration check, or remote-config lookup; its output is fixed by
`CodeEditLanguages`' bundled catalogue and whatever `contributionPoint` has
already accepted.

## Analytics

Not applicable: this component emits no analytics event; it returns a
value to its one caller (`MainThreadLanguages.getLanguages`) and performs
no telemetry of its own.

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

## Logging

Not applicable: `HostLanguageVocabulary.swift` contains no logging call.

## Platform Notes

- **SwiftUI**: the source (`HostLanguageVocabulary.swift`, alongside
  `LanguageContributionPoint.swift` for the contributed half and
  `MainThreadLanguages.swift:522` for the `ExtensionLanguageVocabulary`
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

## Design Decisions

- **Decision**: built-in identifiers are listed before contributed
  identifiers, and the built-in loop's own duplicate guard is kept even
  though nothing in `CodeLanguage.allLanguages` can trigger it today.
  **Rationale**: the source's own doc comment states that an extension
  contributing an id CodeEditLanguages already has is adding a
  file-extension claim to an existing language, not declaring a new one,
  so the built-in entry — the one that was there first — must win the
  position; the guard costs one set insertion this code already pays for
  the later loops and guards against a future duplicate appearing in a
  third-party array this codebase does not control.
  **Approved**: pending
- **Decision**: `languageIdentifiers` is built from `CodeLanguage.id`,
  never `CodeLanguage.tsName`.
  **Rationale**: the source's doc comment states `tsName` names the
  tree-sitter grammar, not the language, and building on it would return
  duplicates while losing three languages `id` keeps distinct (JSX and
  JavaScript, TSX and TypeScript, an OCaml interface and OCaml each share
  one grammar).
  **Approved**: pending
- **Decision**: the returned identifiers are this host's own vocabulary
  (for example `cSharp`, `jsx`, `tsx`, `objc`, `bash`, `goMod`, `jsdoc`,
  `markdownInline`, `regex`), not a translation into whatever spelling a
  real VS Code installation uses for the same language.
  **Rationale**: the source's doc comment states upstream's push-and-cache
  design exists to amortize a process boundary this host does not have,
  not to translate vocabulary, and an extension asking what languages this
  editor knows wants this host's actual ids, not VS Code's.
  **Approved**: pending
- **Decision**: `languageIdentifiers` is a computed property, never cached
  behind a stored field.
  **Rationale**: `contributionPoint`'s contributions can change between
  calls as extensions load and unload, and the source's own doc comment
  ties this directly to "Ruling 16," which requires a fresh array on every
  call.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

`separation-of-concerns` passes because `HostLanguageVocabulary` does
exactly one thing — compose two already-deterministic identifier sources
into one deduplicated, ordered array behind a single computed property —
and delegates all decoding, manifest parsing, and JS/Swift bridging to
`LanguageContributionPoint` and `MainThreadLanguages` respectively
(`Overview`, `protocol-conformance`, `computed-not-cached`).
`unit-test-coverage` passes because `MainThreadLanguagesVocabularyTests.swift`'s
`HostLanguageVocabularyTests` suite exercises the production conformer
directly — never a double for either side — asserting the built-in/contributed
dedup, the presence of `CodeLanguage.default`'s identifier, and the
built-ins-first ordering (`hlv-001` through `hlv-003`).
`good-test-properties` passes because each test in that suite constructs
its own `LanguageContributionPoint` and `HostLanguageVocabulary`, asserts a
single concrete outcome with `#expect`/`#require`, and shares no mutable
fixture state across tests, so every test is fast, isolated, repeatable,
and self-validating.
`fault-tolerance` passes because the built-in loop's `seen.insert` guard
and the contributed loop's `where seen.insert(id).inserted` clause together
ensure that any number of duplicate or unexpected identifiers from either
source — including a contribution that names an existing built-in exactly —
are absorbed by deduplication rather than causing a crash or a corrupted
result (`built-in-deduplication`, `contributed-deduplication`, Edge Cases
— Boundary values).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
