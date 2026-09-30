<!-- leaf: implement-extension-host-core-1/extensions-activation-event-matcher--part-3 · source: extension-host-core-extensions-activation-event-matcher.md -->

# ActivationEventMatcher — continued (part 3)

**Rules** (cite as `implement-extension-host-core-1/extensions-activation-event-matcher--part-3#<slug>`):

- `single-matcher-trigger-factory` MAY

- **single-matcher-trigger-factory**: `ActivationTrigger.workspaceScanned(relativePaths:)`
  MAY be used by a caller that has exactly one matcher to ask (a test, or a
  replay for a single extension with no prepared scan to hand); the
  `workspace-scan-reuse` requirement's prohibition applies only to a caller
  with more than one matcher.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `manifest` | `ExtensionManifest` | none (required) | Supplies `activationEvents`, `engines.vscode`, and `contributes.commands` to `ActivationEventMatcher.init(manifest:)`; there is no default manifest. |
| `trigger` | `ActivationTrigger` | none (required) | The event `matches(_:)` is asked about; one of `.startupFinished`, `.documentOpened(languageID:)`, `.commandInvoked(_:)`, `.webviewPanelRestored(viewType:)`, `.viewShown(viewID:)`, `.workspaceScanned(_:)`. |
| `relativePaths` | `[String]` | none (required, when using `WorkspaceScan`) | Workspace-relative paths, `/`-separated with no leading slash, that a caller's directory walk produced; supplied once per scan via `WorkspaceScan.init(relativePaths:)` or the `ActivationTrigger.workspaceScanned(relativePaths:)` convenience factory. |

There are no environment variables, settings keys, or injected dependencies:
`ActivationEventMatcher` and its supporting types take every input as a
plain constructor or method argument and read no ambient state.

## Privacy

- **Data collected**: none. `ActivationEventMatcher` reads only the
  `activationEvents`, `engines.vscode`, and `contributes.commands` fields
  of a caller-supplied `ExtensionManifest`, and the `relativePaths` of a
  caller-supplied `WorkspaceScan`; none of this is device- or user-identifying
  data, and the component collects nothing beyond what its caller already
  handed it.
- **Storage**: none. Every value is held only in the in-memory
  `ActivationEventMatcher`/`WorkspaceScan` instance for the duration the
  caller keeps it; nothing is written to disk by this component.
- **Transmission**: none. This component performs no networking.
- **Retention**: for the lifetime of the `ActivationEventMatcher` or
  `WorkspaceScan` value the caller holds; releasing the value releases the
  data with it.

## Platform Notes

- **SwiftUI**: the source (`ActivationEventMatcher.swift`,
  `ExtensionManifest.swift`, `VSCodeEngineRange.swift`,
  `SemanticVersion.swift`) is plain Foundation logic — value types, string
  parsing, and a hand-rolled backtracking matcher — with no dependency on
  SwiftUI or any view-layer framework. A port that keeps this component in
  Swift needs nothing beyond `Foundation`.
- **Compose**: start from Kotlin `data class`/`sealed interface` for
  `ActivationEvent`/`ActivationTrigger` (a `sealed interface` models the
  `Kind`/`Trigger` enums with associated payloads more directly than a
  Kotlin `enum class`), plain `String` parsing for the prefix matching, and
  a hand-written recursive matcher for the glob logic — Kotlin's
  `Regex`/`glob` support does not implement VS Code's specific `**`
  whole-segment rule or its brace-alternation syntax, so translating glob
  to a JVM regex has the same escaping hazard the source's own doc comment
  gives for avoiding `NSRegularExpression`. Memoize with a plain
  `HashMap` keyed on the same `(tokenIndex, pathIndex)`/`(branchId,
  branchIndex, pathIndex)` shapes.
- **React/Web**: model `ActivationEvent`/`ActivationTrigger` as discriminated
  union types (a `kind` or `type` string field plus payload), parse
  `activationEvents` with the same ordered `if`/`else if` chain over
  `String.prototype.startsWith`, and port the glob matcher as a small
  recursive function over an array of tokens — `minimatch`/`micromatch`
  exist on npm but neither one, out of the box, restricts a bare `**` to
  crossing directories only when it is a whole path segment while treating
  every other `**` as a single `*`; that VS Code-specific rule (and the
  rejection of `[...]` classes and leading `!`) needs the same custom
  tokenizer the source implements, not a general-purpose glob library.
- **AppKit / UIKit**: identical to the SwiftUI note — the component depends
  on neither AppKit nor UIKit, so a macOS or iOS host consumes the same
  `AgenticToolkitCore` type directly with no translation.
- **WinUI 3**: there is no .NET or Windows App SDK type that already
  implements VS Code's `activationEvents` grammar or its `engines.vscode`
  range grammar, so both need a direct C# port rather than an existing
  library. Model `ActivationEvent`/`ActivationTrigger` as C# records with a
  discriminated `Kind`/`Trigger` (a base `abstract record` with derived
  records per case, or a single record carrying a `Kind` enum plus a
  nullable payload string) rather than reaching for `System.Text.Json`'s
  polymorphic serialization, since these values are constructed from
  parsed strings, not deserialized JSON. Port `VSCodeEngineRange` and
  `SemanticVersion` as plain C# `readonly struct`s with the same
  three-base/must-equal-flag representation — resist the temptation to
  reach for NuGet's `Semver` or `NuGet.Versioning` packages, since both
  implement npm/NuGet semver ranges, which is precisely the grammar the
  source's own doc comment says VS Code's `engines.vscode` is not. Port
  `GlobPattern` as a private nested class inside the equivalent of
  `ActivationEventMatcher` (mirroring the source's file-local placement)
  with its two memoization tables as `Dictionary<TKey, bool>` locals scoped
  to one `Matches` call, matching over a `char[]` (note: a C# `char` is a
  UTF-16 code unit, not a grapheme cluster the way a Swift `Character` is,
  so a path containing a combining-character sequence could tokenize
  differently between a Swift host and a WinUI 3 host — call this out in
  the port's own tests rather than assuming parity). `Task`/`async` and
  `ObservableCollection`/`INotifyPropertyChanged` have no role here: every
  operation is synchronous and returns a value rather than notifying of a
  change.

