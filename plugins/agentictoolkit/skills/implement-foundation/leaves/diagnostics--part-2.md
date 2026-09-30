<!-- leaf: implement-foundation/diagnostics--part-2 · source: foundation-diagnostics.md -->

# JITAvailability, UpstreamDivergence & UpstreamDivergenceLedger — continued (part 2)

**Rules** (cite as `implement-foundation/diagnostics--part-2#<slug>`):

- `jit-value-shape` MUST
- `jit-degraded-definition` MUST
- `jit-diagnosis-nil-when-healthy` MUST
- `jit-diagnosis-content` MUST
- `jit-current-memoized-once` MUST
- `jit-probe-live-each-call` MUST
- `jit-hardened-flag-read` MUST
- `jit-hardened-read-failure-is-false` MUST
- `jit-entitlement-read` MUST
- `jit-log-once-per-process` MUST
- `jit-no-log-when-healthy` MUST
- `jit-log-privacy` MUST
- `jit-logging-category` MUST
- `divergence-value-shape` MUST
- `divergence-detection-cases` MUST
- `divergence-public-init` MUST
- `divergence-known-catalogue` MUST
- `divergence-known-fixed-membership` MUST
- `divergence-ids-unique` MUST
- `divergence-fields-nonempty` MUST
- `divergence-detection-mix` MUST
- `hit-value-shape` MUST
- `hit-identity-key` MUST
- `ledger-unchecked-sendable-shared` MUST
- `ledger-record-noop-nonpositive` MUST
- `ledger-record-default-count-one` MUST
- `ledger-row-key-by-detail` MUST
- `ledger-row-accumulates` MUST
- `ledger-write-serialization` MUST
- `ledger-first-hit-logs-once` MUST
- `ledger-hits-sorted` MUST
- `ledger-hits-for-filters` MUST
- `ledger-publisher-current-value` MUST
- `ledger-every-mutation-publishes` MUST
- `ledger-clear-empties` MUST

## Behavioral Requirements

- **jit-value-shape**: `JITAvailability` MUST be a `Sendable`, `Hashable`
  struct with exactly two stored properties, `isHardenedRuntime: Bool` and
  `hasJITEntitlement: Bool`, and its public initializer MUST assign both
  parameters directly with no validation (`JITAvailability.swift`).
- **jit-degraded-definition**: `JITAvailability.isDegraded` MUST return
  `isHardenedRuntime && !hasJITEntitlement` — true only when the hardened
  runtime is enforcing and the JIT entitlement is absent, and false in every
  other combination, including the unhardened case where the entitlement is
  irrelevant.
- **jit-diagnosis-nil-when-healthy**: `JITAvailability.diagnosis` MUST return
  `nil` whenever `isDegraded` is false.
- **jit-diagnosis-content**: When `isDegraded` is true, `diagnosis` MUST
  return a fixed, non-nil sentence naming
  `com.apple.security.cs.allow-jit` as the missing entitlement, stating that
  extensions will run but every one of them interpreted, and naming
  `App.entitlements` as where the fix belongs.
- **jit-current-memoized-once**: `JITAvailability.current` MUST be a
  `static let` whose value is computed by calling `probe()` exactly once for
  the process, and MUST return that same value on every later read for the
  rest of the process's lifetime (doc comment).
- **jit-probe-live-each-call**: `JITAvailability.probe()` MUST perform a
  fresh call to `readHardenedRuntimeFlag()` and `readJITEntitlement()` on
  every invocation, independent of whatever `current` has already memoized.
- **jit-hardened-flag-read**: `readHardenedRuntimeFlag()` MUST derive its
  answer from this process's own code object — `SecCodeCopySelf`, then
  `SecCodeCopyStaticCode`, then `SecCodeCopySigningInformation` with the
  `kSecCSSigningInformation` flag — read the `kSecCodeInfoFlags` entry of the
  resulting dictionary as a `UInt32`, and test it against the literal mask
  `0x0001_0000` (`kSecCodeSignatureRuntime`, not exposed to Swift).
- **jit-hardened-read-failure-is-false**: `readHardenedRuntimeFlag()` MUST
  return `false`, never throw or crash, when any step of that chain fails —
  a non-success `OSStatus`, a nil code object, a signing-information
  dictionary that fails to cast, or a missing or mistyped flags entry (each a `guard ... else { return false }`).
- **jit-entitlement-read**: `readJITEntitlement()` MUST read
  `com.apple.security.cs.allow-jit` off this process's own task via
  `SecTaskCreateFromSelf(nil)` and `SecTaskCopyValueForEntitlement`, and MUST
  return `false` when `SecTaskCreateFromSelf` returns `nil` or the
  entitlement value does not cast to `Bool`.
- **jit-log-once-per-process**: `JITAvailability.logIfDegraded()` MUST cause
  the process to write `current.diagnosis` to the OSLog error level at most
  once for the process's entire lifetime, however many times or from however
  many call sites it is invoked, by forcing evaluation of the private
  `static let hasLogged` closure — a Swift static stored property that runs
  its initializer exactly once regardless of concurrent first callers.
- **jit-no-log-when-healthy**: `logIfDegraded()` MUST NOT write anything to
  the log when `current.diagnosis` is `nil` — `hasLogged`'s closure returns
  `true` immediately in that case without calling `logger.error`.
- **jit-log-privacy**: The one log line `logIfDegraded()` can produce MUST
  mark the diagnosis string `privacy: .public` in the `OSLog` call.
- **jit-logging-category**: `extension JITAvailability: Loggable` MUST
  obtain its logger through `Loggable`'s default `makeLogger()`, which gives
  it OSLog category `"JITAvailability"` (the conforming type's own name) and
  subsystem `Bundle.main.bundleIdentifier` (`JITAvailability.swift`; `Loggable.swift`).
- **divergence-value-shape**: `UpstreamDivergence` MUST be a `Sendable`,
  `Hashable`, `Identifiable`, `Codable` struct with exactly the six stored
  properties `id`, `area`, `upstreamBehaviour`, `ourBehaviour`, `rationale`,
  and `detection: Detection` (`UpstreamDivergence.swift`).
- **divergence-detection-cases**: `UpstreamDivergence.Detection` MUST be a
  `String`-backed, `Sendable`, `Hashable`, `Codable` enum with exactly two
  cases, `counted` and `declared`.
- **divergence-public-init**: `UpstreamDivergence.init(id:area:
  upstreamBehaviour:ourBehaviour:rationale:detection:)` MUST be public and
  MUST assign every one of the six parameters directly, with no validation,
  normalization, or default value.
- **divergence-known-catalogue**: `UpstreamDivergence.known` MUST be the
  single list a consumer iterates to enumerate "every divergence this app
  knows about" — a `static let` divergence defined elsewhere in the file but
  omitted from `known` MUST remain individually addressable but MUST NOT
  appear to any caller that iterates `known` (doc comment).
- **divergence-known-fixed-membership**: `UpstreamDivergence.known` MUST
  contain exactly six entries in this fixed order: `documentOutsideWorkspaceScope`,
  `semanticTokenLineOutOfRange`, `semanticTokenModifiersIgnored`,
  `semanticTokenMultilineUnsupported`, `semanticTokenOverlapDropped`,
  `semanticTokenTypeUnmapped`.
- **divergence-ids-unique**: Every entry in `UpstreamDivergence.known` MUST
  have a distinct `id` string (confirmed by
  `UpstreamDivergenceCatalogueTests.idsAreUnique`).
- **divergence-fields-nonempty**: Every entry in `UpstreamDivergence.known`
  MUST have a non-empty `id`, `area`, `upstreamBehaviour`, `ourBehaviour`,
  and `rationale` (confirmed by
  `UpstreamDivergenceCatalogueTests.everyEntryIsDescribed`).
- **divergence-detection-mix**: `UpstreamDivergence.known` MUST contain at
  least one entry of each `Detection` case, and the number of `.counted`
  entries MUST be greater than or equal to the number of `.declared` entries
  (221 give five `.counted` entries
  and one `.declared` entry; confirmed by
  `UpstreamDivergenceCatalogueTests.bothDetectionKindsArePresent`).
- **hit-value-shape**: `UpstreamDivergenceHit` MUST be a `Sendable`,
  `Hashable`, `Identifiable` struct with exactly the five stored properties
  `divergence: UpstreamDivergence`, `detail: String`, `firstSeen: Date`,
  `lastSeen: Date`, and `count: Int` (`UpstreamDivergenceLedger.swift`).
- **hit-identity-key**: `UpstreamDivergenceHit.id` MUST be computed as
  `divergence.id` and `detail` joined by the ASCII unit-separator character
  `\u{1F}` — never a UUID or other synthesized identifier.
- **ledger-unchecked-sendable-shared**: `UpstreamDivergenceLedger` MUST be
  declared `final class UpstreamDivergenceLedger: @unchecked Sendable`, MUST
  expose one process-wide `static let shared` instance, and MUST also leave
  its own `public init()` available so a caller (a test, or another host)
  MAY construct an independent ledger instead of using `shared`.
- **ledger-record-noop-nonpositive**: `record(_:detail:count:)` MUST perform
  no row write, no log write, and no publish when `count <= 0` (confirmed by
  `UpstreamDivergenceLedgerTests.nonPositiveCountsAreIgnored`).
- **ledger-record-default-count-one**: `record(_:detail:)` called with
  `count` omitted MUST record exactly one occurrence, per the parameter's
  `count: Int = 1` default.
- **ledger-row-key-by-detail**: A ledger row MUST be keyed by the pair of
  the divergence's `id` and the caller-supplied `detail` string — two
  `record` calls for the same divergence but different `detail` values MUST
  produce two independent rows, never merged into one (confirmed by `UpstreamDivergenceLedgerTests.detailsAreSeparateRows`).
- **ledger-row-accumulates**: A second `record(_:detail:count:)` call for a
  key that already has a row MUST add its `count` to the existing row's
  `count`, MUST replace `lastSeen` with the current time, and MUST leave
  `firstSeen` unchanged from the row's original creation (confirmed by `UpstreamDivergenceLedgerTests.secondRecordAccumulates` and
  `.firstSeenIsPinnedAndLastSeenMoves`).
- **ledger-write-serialization**: Every read and every write of the ledger's
  `rows` dictionary MUST occur while holding `lock` (an `NSLock`), so that
  concurrent `record`, `clear`, `hits`, and `hits(for:)` calls from different
  threads MUST NOT corrupt the dictionary or lose an update (confirmed by
  `UpstreamDivergenceLedgerTests.concurrentRecordingIsTotalled`, which
  records 200 concurrent hits for one key and observes all 200 counted).
- **ledger-first-hit-logs-once**: `record(_:detail:count:)` MUST write an
  OSLog info-level line containing the divergence's `id` and its
  `ourBehaviour` text, marked `privacy: .public`, only on the call where
  `existing == nil` (the key's first-ever hit); every later `record` call
  for that same key MUST NOT log again.
- **ledger-hits-sorted**: Both `hits` and `hits(for:)` MUST return their
  rows sorted by the tuple `(divergence.id, detail)`, never in insertion or
  arrival order (confirmed by
  `UpstreamDivergenceLedgerTests.rowsAreSortedForReading`).
- **ledger-hits-for-filters**: `hits(for:)` MUST return only the rows whose
  key's `divergenceID` equals the given divergence's `id` (confirmed by `UpstreamDivergenceLedgerTests.hitsForOneSite`).
- **ledger-publisher-current-value**: `hitsPublisher` MUST be backed by a
  `CurrentValueSubject`, so a subscriber MUST receive the ledger's rows as
  they stand at the moment of subscription, even if no `record` or `clear`
  call happens afterward (confirmed by
  `UpstreamDivergenceLedgerTests.publisherCarriesTheRows`).
- **ledger-every-mutation-publishes**: Both `record(_:detail:count:)` (when
  `count > 0`) and `clear()` MUST call `publish()` exactly once per call,
  each sending a fresh snapshot of the current rows to every subscriber.
- **ledger-clear-empties**: `clear()` MUST remove every row from the ledger
  and then publish an empty array to subscribers; it MUST NOT touch
  `firstSeen`/`lastSeen` bookkeeping for any row, because it discards the
  rows themselves rather than resetting a per-row field (confirmed by `UpstreamDivergenceLedgerTests.clearEmptiesAndPublishes`).
