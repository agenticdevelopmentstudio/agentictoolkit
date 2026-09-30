<!-- leaf: implement-git-client/projects-git-repo--part-2 · source: git-client-projects-git-repo.md -->

# GitRepo — continued (part 2)

## Privacy

- **Data collected**: `GitRepo.path` (an absolute filesystem path, which on a
  typical macOS home directory includes the user's account name) and
  `GitRepo.remote`/`ScannedGitRepo.remote` (a git remote URL another
  component read out of `.git/config`, stored verbatim). Neither type in
  this file inspects, validates, or redacts the `remote` string, so if that
  URL happens to embed user-info credentials (as a bare `https://` remote
  URL sometimes does), this file stores that string exactly as given, with
  no special handling.
- **Storage**: None performed by this file — `GitRepo`, `ScannedGitRepo`,
  and `ProjectScanSummary` are plain in-memory value types with no
  persistence code of their own; whatever writes them to disk (e.g. a
  database component) is a separate source not given here.
- **Transmission**: None — this file makes no network call.
- **Retention**: Not defined here; a value's lifetime is entirely up to its
  caller.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift`, a
  plain Foundation file with no import beyond `Foundation` and no dependency
  on SwiftUI, AppKit, or UIKit at all — the three types are UI-framework-free
  and port unchanged into any Swift target.
- **Compose**: Model `GitRepo` as a Kotlin `data class` with a `UUID`
  (`java.util.UUID`) `id`, `String path`, `String name`, `String? remote`,
  and `java.time.Instant firstSeen`/`lastSeen`/`lastOpened?`; Kotlin's
  synthesized `equals`/`hashCode` on a `data class` already produce the same
  structural (not identity-only) equality this file's synthesized
  `Equatable` produces, so no extra work is needed to preserve that
  behavior. `ScannedGitRepo` and `ProjectScanSummary` port the same way,
  each as its own `data class`; `URL(fileURLWithPath:).lastPathComponent`
  becomes `java.io.File(path).name` (or `Path.of(path).fileName`).
- **React/Web**: A browser has no filesystem, so `path`/`url` have no direct
  analogue; if this pattern is ported into a Node-hosted process, represent
  `GitRepo` as a plain object or a small class with the same seven fields, an
  `id: string` (a UUID string or `crypto.randomUUID()`), and derive
  `defaultName`/`leafName` with `path.basename(p)` instead of
  `URL(fileURLWithPath:).lastPathComponent`. `summaryText`'s formatting logic
  ports as a pure function taking a plain `{added, moved, removed, unchanged,
  skipped}` object.
- **AppKit / UIKit**: Identical to the SwiftUI note — nothing in this file
  is tied to a UI framework; it ports unchanged to either.
- **WinUI 3**: Port `GitRepo` as an immutable-`Id` C# `record` (or a class
  with a `readonly Guid Id`) with mutable `string Path`, `string Name`,
  `string? Remote`, `DateTimeOffset FirstSeen`, `LastSeen`, and
  `DateTimeOffset? LastOpened` — a C# `record`'s synthesized value equality
  already compares every property, matching this file's synthesized
  `Equatable` (including timestamps) with no extra code. Default `Id` to
  `Guid.NewGuid()` and `FirstSeen`/`LastSeen` to `DateTimeOffset.Now` in the
  constructor, mirroring `init`'s defaults. Port `url` as a computed
  `System.IO.DirectoryInfo`/`Uri` built from `Path`, and
  `defaultName(forPath:)`/`leafName` as
  `System.IO.Path.GetFileName(path.TrimEnd('\\', '/'))` — note that
  `Path.GetFileName` behaves differently from `URL.lastPathComponent` on a
  path ending in a separator, so a faithful port trims the trailing
  separator first. Port `ProjectScanSummary` as a small mutable class or
  `record struct` with five `int` properties and a computed `Found`/
  `SummaryText`, using `ObservableCollection`/`INotifyPropertyChanged` only
  if a bound UI needs to react to the counts changing — nothing in this
  file requires that on its own.

## Design Decisions

**Decision**: `GitRepo`'s `Equatable` conformance is the compiler-synthesized
one over every stored property, including `firstSeen`, `lastSeen`, and
`lastOpened` — not a hand-written conformance that compares `id` alone.
**Rationale**: The type's header doc comment states "the identity is the
`id`, not the path" to justify using a `UUID` as the primary key rather than
the path, but that statement is about which field a *database row* is keyed
on; it does not extend to `==`. Because `firstSeen`/`lastSeen` default to
`Date()` at construction time, two values built independently for what a
caller considers "the same" repository will almost always compare unequal —
a quirk a port must preserve deliberately rather than "fix" into
identity-based equality, or callers that rely on `==` (e.g. `Set` membership,
diffing) will behave differently than the source.
**Approved**: pending

**Decision**: `ProjectScanSummary` declares an explicit, parameterless
`public init() {}` even though every stored property already has a default
value.
**Rationale**: Swift only synthesizes a memberwise (or default,
parameterless) initializer at the same access level as the type when the
type is not `public`; for a `public` struct, the compiler-synthesized
initializer is `internal`, so a caller outside this module could not
construct a `ProjectScanSummary` at all without this explicit `public init()`
— the same reason `GitRepo.init` and `ScannedGitRepo.init` are both written out explicitly rather than relied upon as
synthesized.
**Approved**: pending

**Decision**: `ProjectScanSummary.found` sums `added + moved + unchanged +
skipped` but excludes `removed`.
**Rationale**: The doc comment on `found` calls it "every project in the
registry once the scan has been applied" — a repository the scan
determined to be `removed` is, by definition, no longer in the registry, so
counting it in `found` would overstate what is actually there. `summaryText`
still names removals in its parts list because reporting "what changed"
and reporting "what remains" are different facts, matching this file's
general pattern of not conflating adjacent-but-distinct counts (see also
`unchanged` never appearing in `summaryText`'s parts, and `skipped` field
name vs. its "not scanned" wording).
**Approved**: pending

**Decision**: `ScannedGitRepo` is a distinct type from `GitRepo` rather than
`GitRepo` with an optional `id`, and its `remote` parameter has no default
(unlike `GitRepo.remote`, which defaults to `nil`).
**Rationale**: The doc comment states directly that "a scan result has no
identity yet: deciding whether it is a new repository, a moved one, or one
already known is the reconciler's job" — giving `ScannedGitRepo`
an `id` field (even an optional one) would let a caller construct a
scan result that already claims an identity, which is exactly the ambiguity
this type is designed to prevent until reconciliation happens elsewhere.
Requiring `remote` explicitly (rather than defaulting it to `nil` the way
`GitRepo` does) keeps every scan-result construction site stating plainly
whether a remote was found, since omitting the argument by habit is easy to
do at a `GitRepo` call site but is not possible here.
**Approved**: pending
