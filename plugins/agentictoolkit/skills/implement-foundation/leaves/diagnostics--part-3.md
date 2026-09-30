<!-- leaf: implement-foundation/diagnostics--part-3 · source: foundation-diagnostics.md -->

# JITAvailability, UpstreamDivergence & UpstreamDivergenceLedger — continued (part 3)

**Rules** (cite as `implement-foundation/diagnostics--part-3#<slug>`):

- `ledger-publish-lock-ordering` MUST
- `ledger-logging-category` MUST

- **ledger-publish-lock-ordering**: `publish()` MUST take a second lock,
  `publishLock`, around taking its rows snapshot and sending it, so that two
  `publish()` calls racing on different threads MUST deliver to subscribers
  in the same order their respective row mutations actually committed, and
  MUST NOT deliver a stale snapshot after a newer one (per
  the type's own doc comment; not exercised by a dedicated
  ordering test — inferred from the documented purpose of the second lock).
- **ledger-logging-category**: `extension UpstreamDivergenceLedger:
  Loggable` MUST obtain its logger through `Loggable`'s default
  `makeLogger()`, giving it OSLog category `"UpstreamDivergenceLedger"`.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `JITAvailability.init(isHardenedRuntime:hasJITEntitlement:)` parameters | `Bool`, `Bool` | none — both required | Used directly only by `JITAvailabilityTests.swift`; production code reads `.current` or calls `.probe()` rather than constructing a value by hand. |
| `UpstreamDivergence.init(id:area:upstreamBehaviour:ourBehaviour:rationale:detection:)` parameters | `String` ×4, `Detection` | none — all six required | Used only to define the six `static let` catalogue entries in `UpstreamDivergence.swift`; the initializer is public, so an external caller MAY build an additional divergence, but no call site in this codebase does. |
| `UpstreamDivergenceLedger.record(_:detail:count:)` `count` | `Int` | `1` | The only defaulted parameter across either file; every other parameter in both types is required with no default. |
| `UpstreamDivergenceLedger` instance (injection seam) | `UpstreamDivergenceLedger` | `.shared`, at each consumer's own call site | Consumers depend on the concrete class rather than a protocol, but its `public init()` lets a test or an alternate host substitute an independent ledger, as `LanguageServerDocumentSync.init(ledger:)`'s `= .shared` default parameter does. |

Neither `JITAvailability.swift`, `UpstreamDivergence.swift`, nor
`UpstreamDivergenceLedger.swift` reads an environment variable or a settings
key of its own.

## Localization

`JITAvailability.diagnosis` and every `UpstreamDivergence`
entry's `area`, `upstreamBehaviour`, `ourBehaviour`, and `rationale` text are hardcoded English prose with no localization mechanism —
no `String(localized:)`, no string-catalog key, no `Bundle` lookup. Both
surfaces are read by a person: `diagnosis`'s own doc comment says it is
written as prose because it reaches "the log and the Extensions settings
panel," and `UpstreamDivergence`'s fields are rendered by the Language
Servers settings panel (`LanguageServersPanelViewController.swift`, outside
this recipe's sources). Neither file offers a second language.

## Privacy

- **Data collected**: Neither type collects data on its own initiative.
  `UpstreamDivergenceLedger.record(_:detail:count:)` accepts a
  caller-supplied `detail: String` that becomes part of a logged and
  published row; the type's own doc comment states the constraint on that
  string explicitly: "a document URI or a server name is the useful thing,
  never anything drawn from the file's contents" (`UpstreamDivergenceHit`
  doc comment). Enforcing that constraint is the caller's
  responsibility — every current call site passes a document URI or a
  token-type name (`SemanticTokenHighlightProvider.swift`,
  `LanguageServerDocumentSync.swift`, outside this recipe's sources), never
  document text.
- **Storage**: In-memory only. `UpstreamDivergenceLedger.rows` is a plain
  Swift dictionary with no disk, database, or `UserDefaults` persistence of
  any kind.
- **Transmission**: None. Neither type makes a network call; `hitsPublisher`
  delivers rows only to in-process Combine subscribers.
- **Retention**: A row persists only until the process exits or an explicit
  `clear()` call empties the ledger; nothing in either file
  writes a row to persistent storage, so no data survives a relaunch.

## Platform Notes

- **SwiftUI**: The sources are
  `packages/apple/AgenticToolkit/Core/Diagnostics/JITAvailability.swift`,
  `UpstreamDivergence.swift`, and `UpstreamDivergenceLedger.swift`, part of
  the `AgenticToolkitCore` target. `JITAvailability` uses `Security`
  framework APIs (`SecCode`, `SecTask`) to read this process's own
  code-signing flags and entitlements; `UpstreamDivergence` is a plain
  `Codable` value catalogue; `UpstreamDivergenceLedger` uses `NSLock` for
  mutual exclusion and `Combine`'s `CurrentValueSubject` for its live
  publisher. Nothing here is SwiftUI-specific — any host consumes it
  identically.
- **Compose**: There is no Android analogue to macOS's hardened runtime or
  to a per-entitlement JIT gate — ART's own JIT/AOT compilation strategy is
  a system-level decision, not an app-declared capability, so
  `JITAvailability` has no Kotlin equivalent to port; a port would document
  the absence rather than translate it. `UpstreamDivergence` and
  `UpstreamDivergenceHit` translate directly to Kotlin `data class`es. For
  `UpstreamDivergenceLedger`, a `synchronized` block or `kotlinx.atomicfu`
  lock stands in for `NSLock`, `kotlinx.coroutines.flow.MutableStateFlow`
  stands in for `CurrentValueSubject` (both deliver their current value
  immediately to a new collector), and a plain Kotlin `object` singleton
  stands in for `UpstreamDivergenceLedger.shared`.
- **React/Web**: Browsers need no entitlement to let a JavaScript engine
  compile code, so `JITAvailability` has no web equivalent to port; the
  nearest analogous gate is a page's Content-Security-Policy
  `script-src` directive controlling `unsafe-eval`/WebAssembly compilation,
  which is a page-level policy, not a per-process code-signature reading, so
  it does not map onto this type's contract. `UpstreamDivergence` translates
  to a `readonly` TypeScript interface array; `UpstreamDivergenceLedger`
  translates to a class wrapping a `Map` (in place of the `Key`-keyed
  dictionary) and an RxJS `BehaviorSubject` (the direct analogue of
  `CurrentValueSubject`, since both replay their latest value to a new
  subscriber) in place of manual lock-guarded state, since JavaScript's
  single-threaded event loop needs no `NSLock` equivalent at all.
- **AppKit / UIKit**: Identical to the SwiftUI note — none of the three
  types is UI-framework-specific; only the host application embedding
  `AgenticToolkitCore` differs, never this contract. (`JITAvailability`'s
  own consumer, `ExtensionHost.swift`, happens to be an AppKit-hosted,
  macOS-only feature, but that is a fact about the caller, not this
  component.)
- **WinUI 3**: Windows has no direct analogue to
  `com.apple.security.cs.allow-jit` or the hardened runtime flag — code
  integrity on Windows is governed by Authenticode signing and, for packaged
  apps, MSIX package capabilities and WDAC/AppLocker policy, none of which
  expose a single per-app "is JIT allowed" bit the way a macOS entitlement
  does; a Windows port has no established source of truth to read in
  `JITAvailability`'s place and would need a new decision, not a
  translation. Model `UpstreamDivergence` as a C# `record` implementing
  `IEquatable<T>` with a nested `enum Detection { Counted, Declared }`, and
  `UpstreamDivergenceHit` the same way. Model `UpstreamDivergenceLedger` as
  a class backed by a `lock`-guarded `Dictionary<(string, string),
  UpstreamDivergenceHit>` (or a `ConcurrentDictionary` if lock-free reads are
  wanted instead), exposing its live rows through `System.Reactive.Subjects.BehaviorSubject<IReadOnlyList<UpstreamDivergenceHit>>`
  (Rx.NET's direct analogue of `CurrentValueSubject`) rather than
  `ObservableCollection`, since what is needed is "replay the latest full
  snapshot to a new subscriber," not incremental collection-changed
  notifications. Use `Microsoft.Extensions.Logging.ILogger<T>`, categorized
  by type the way `Loggable` categorizes by `type(of: self)`, in place of
  `OSLog`'s subsystem/category pair.

