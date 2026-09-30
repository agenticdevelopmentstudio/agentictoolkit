<!-- leaf: implement-language/services-lsp--part-3 · source: language-services-lsp.md -->

# Language Services LSP — continued (part 3)

**Rules** (cite as `implement-language/services-lsp--part-3#<slug>`):

- `per-session-ordered-queue` MUST
- `sync-capability-resolved-once` MUST
- `open-close-defaults-true` MUST
- `change-reopens-unopened-document` MUST
- `saved-gating-is-asymmetric` MUST
- `incremental-sync-forwards-verbatim` MUST
- `full-sync-forwards-whole-document` MUST
- `text-and-version-captured-together` MUST
- `failed-start-pipeline-forwards-nothing` MUST
- `not-running-logged-as-debug` MUST
- `open-close-disabled-still-sends-change` MUST
- `reconcile-retires-stale-before-adding` MUST
- `addpipeline-joins-in-flight-registry-start` MUST
- `replay-matches-claimed-language-only` MUST
- `session-replacement-rebuilds-pipeline` MUST
- `out-of-scope-documents-silently-excluded` MUST
- `scope-check-resolves-symlinks` MUST
- `string-prefix-sibling-excluded` MUST
- `out-of-scope-replay-skipped` MUST
- `out-of-scope-refusals-counted-once-per-batch` MUST
- `clean-seeding-pass-records-nothing` MUST
- `observe-is-idempotent-per-session` MUST
- `stale-diagnostics-never-dropped` MUST
- `publishes-land-in-send-order` MUST
- `empty-diagnostics-clears-not-ignored` MUST
- `document-diagnostics-pruned-on-close` MUST
- `shutdown-idempotent-preserves-diagnostics` MUST
- `retired-session-does-not-block-later-observation` MUST
- `publishes-in-send-order-across-n` MUST
- `published-stream-finish-is-observed` MUST
- `stream-end-handler-called-exactly-once` MUST
- `drain-called-after-terminate` MUST
- `secrets-keyed-by-id-then-env-var` MUST
- `secrets-stored-in-keychain-not-plain-settings` MUST
- `secrets-merged-into-environment-only-at-session-start` MUST

### Document Sync

- **per-session-ordered-queue**: `DocumentSyncPipeline` MUST maintain
  exactly one ordered event queue per session (not per document), and
  `enqueue(_:)` MUST preserve the caller's emission order
  (`DocumentSyncPipeline.swift`, `LanguageServerDocumentSyncTests.forwardsInEmissionOrder`).
- **sync-capability-resolved-once**: `run(startFailure:)` MUST resolve the
  session's `ResolvedTextDocumentSync` capability exactly once per pipeline
  run, before forwarding any queued event (`DocumentSyncPipeline.swift`).
- **open-close-defaults-true**: `ResolvedTextDocumentSync.resolve` MUST
  default `openClose` to `true` when the server's capability omits it
  (`DocumentSyncPipeline.swift`, `LanguageServerDocumentSyncTests.resolveTable`).
- **change-reopens-unopened-document**: `sendDidChange` MUST send `didOpen`
  for a document before forwarding a `didChange` for it, when the server
  has not yet been told the document is open
  (`DocumentSyncPipeline.swift`, `LanguageServerDocumentSyncTests.changeReopensAfterAFailedOpen`).
- **saved-gating-is-asymmetric**: forwarding of `.saved` events MUST NOT be
  gated on `openURIs.contains`, unlike `.changed`/`.closed` — a deliberate
  asymmetry documented in source, not an oversight (`DocumentSyncPipeline.swift`).
- **incremental-sync-forwards-verbatim**: when the resolved sync kind is
  incremental, `didChange` MUST forward the store's change array verbatim
  (`DocumentSyncPipeline.swift`, `LanguageServerDocumentSyncTests.incrementalForwardsChangesVerbatim`).
- **full-sync-forwards-whole-document**: when the resolved sync kind is
  full, each edit MUST be forwarded as exactly one whole-document
  `didChange`
  (`DocumentSyncPipeline.swift`, `LanguageServerDocumentSyncTests.fullForwardsWholeDocument`).
- **text-and-version-captured-together**: each `didChange` MUST carry the
  document's text as of the same version it reports, never a text/version
  pair captured across an intervening edit
  (`DocumentSyncPipeline.swift`, `LanguageServerDocumentSyncTests.textAndVersionAreCapturedTogether`).
- **failed-start-pipeline-forwards-nothing**: a pipeline whose session
  start failed MUST NOT retry the start and MUST forward none of its
  queued events
  (`DocumentSyncPipeline.swift`, `LanguageServerDocumentSyncTests.failedStartIsNotRetried`).
- **not-running-logged-as-debug**: `record(_:operation:uri:)` MUST log a
  `.notRunning` forwarding failure at debug level; every other forwarding
  failure MUST log at error level (`DocumentSyncPipeline.swift`).
- **open-close-disabled-still-sends-change**: when the resolved capability
  disables `openClose`, the pipeline MUST send no `didOpen`/`didClose` but
  MUST still send `didChange`
  (`DocumentSyncPipeline.swift`, `LanguageServerDocumentSyncTests.openCloseDisabled`).
- **reconcile-retires-stale-before-adding**: `reconcilePipelines(with:)`
  MUST retire pipelines for sessions no longer present before starting
  pipelines for newly reconciled sessions (`LanguageServerDocumentSync.swift`).
- **addpipeline-joins-in-flight-registry-start**: `addPipeline`'s own
  `start()` call MUST join a `LanguageServerRegistry.reconcile`-initiated
  start already in flight for the same session, rather than starting the
  session a second time (`LanguageServerDocumentSync.swift`).
- **replay-matches-claimed-language-only**: `replayOpenDocuments` MUST seed
  a newly connected session only with already-open documents whose language
  id the session's configuration claims
  (`LanguageServerDocumentSync.swift`, `LanguageServerDocumentSyncTests.replaysOpenDocumentsForTheClaimedLanguage`).
- **session-replacement-rebuilds-pipeline**: replacing a session MUST hand
  the new session the currently open documents and MUST send the old
  session's pipeline nothing further
  (`LanguageServerDocumentSync.swift`, `LanguageServerDocumentSyncTests.sessionReplacementRebuildsThePipeline`).
- **out-of-scope-documents-silently-excluded**: `isInWorkspaceScope(_:)`
  MUST exclude a document outside the workspace root from being opened,
  changed, or replayed to any session, producing no server notification at
  all
  (`LanguageServerDocumentSync.swift`, `LanguageServerDocumentSyncScopeTests.outOfScopeDocumentIsSilent`).
- **scope-check-resolves-symlinks**: `isInWorkspaceScope(_:)` MUST resolve
  and standardize both the document path and the workspace root before
  comparing path components, so a symlinked root or a `/tmp` vs
  `/private/tmp` mismatch does not misclassify an in-scope document as out
  of scope
  (`LanguageServerDocumentSync.swift`, `LanguageServerDocumentSyncScopeTests.symlinkedRootAdmitsResolvedPaths`, `.missingFileUnderSymlinkedRootIsInScope`).
- **string-prefix-sibling-excluded**: a sibling directory whose path is a
  string prefix of the workspace root MUST be classified out of scope, not
  admitted by a naive prefix compare
  (`LanguageServerDocumentSync.swift`, `LanguageServerDocumentSyncScopeTests.siblingSharingAStringPrefixIsOutOfScope`).
- **out-of-scope-replay-skipped**: `replayOpenDocuments` MUST NOT replay a
  document already open outside the workspace root to a newly connected
  session
  (`LanguageServerDocumentSync.swift`, `LanguageServerDocumentSyncScopeTests.replaySkipsOutOfScopeDocuments`).
- **out-of-scope-refusals-counted-once-per-batch**: `recordOutOfScope(count:)`
  MUST record refusals encountered while seeding a session in one ledger
  entry per seeding pass, not one entry per document
  (`LanguageServerDocumentSync.swift`, `LanguageServerDocumentSyncScopeTests.seededRefusalsAreCountedInOneEntry`).
- **clean-seeding-pass-records-nothing**: a seeding pass that refuses
  nothing MUST NOT write any entry to `UpstreamDivergenceLedger`
  (`LanguageServerDocumentSync.swift`, `LanguageServerDocumentSyncScopeTests.aCleanSeedingPassRecordsNothing`).

### Diagnostics

- **observe-is-idempotent-per-session**: `observe(_:)` MUST be idempotent
  for a given session, keyed by `ObjectIdentifier` — calling it again for a
  session already observed MUST NOT start a second consumer of that
  session's single-consumer `publishedDiagnostics` stream (`DiagnosticStore.swift`).
- **stale-diagnostics-never-dropped**: diagnostics published with a `nil`
  or older `version` MUST still be stored and MUST NOT be discarded, even
  though `PublishDiagnosticsParams.version` is optional and frequently
  absent (`DiagnosticStore.swift`).
- **publishes-land-in-send-order**: two publishes for the same URI MUST
  leave the store holding the second (most recently sent), reflecting send
  order regardless of version
  (`DiagnosticStore.swift`, `DiagnosticStoreTests` "two publishes for one URI leave the second set, in send order").
- **empty-diagnostics-clears-not-ignored**: an empty diagnostics array
  published for a URI MUST clear that URI's stored diagnostics, not be
  treated as a no-op
  (`DiagnosticStore.swift`, `DiagnosticStoreTests` "an empty diagnostics array clears the URI rather than being ignored").
- **document-diagnostics-pruned-on-close**: `observeDocuments(in:)` MUST
  forget a document's stored diagnostics once its last editor closes it (a
  `.closed` `TextDocumentStore` event with the document's refcount reaching
  zero)
  (`DiagnosticStore.swift`, `DiagnosticStoreTests` "a document's diagnostics are forgotten when its last editor closes").
- **shutdown-idempotent-preserves-diagnostics**: `shutdown()` MUST be safe
  to call more than once and MUST leave already-stored diagnostics intact —
  it stops observation, it does not clear state
  (`DiagnosticStore.swift`, `DiagnosticStoreTests` "shutdown stops observation and is idempotent").
- **retired-session-does-not-block-later-observation**: once a session's
  stream ends, a later session MUST still be observed normally
  (`DiagnosticStore.swift`, `DiagnosticStoreTests` "a session whose stream ends is retired, so a later session is still observed").
- **publishes-in-send-order-across-n**: N publishes for a session MUST
  arrive at the store in the order they were sent
  (`DiagnosticStore.swift`, `DiagnosticStoreTests` "N publishes arrive in the order they were sent").
- **published-stream-finish-is-observed**: the store MUST recognize that a
  session's `publishedDiagnostics` stream has finished, both when the
  session stops cleanly and when it fails to start
  (`DiagnosticStore.swift`, `DiagnosticStoreTests` "the published-diagnostics stream finishes when the session stops", "the published-diagnostics stream finishes when the session fails to start").

### Transport

- **stream-end-handler-called-exactly-once**: the `StreamEndHandler` MUST be
  invoked exactly once per channel, with `nil` denoting a clean end
  (`LanguageServerChannel.swift`).
- **drain-called-after-terminate**: callers MUST call `drain()` only after
  calling `SubprocessChannel.terminate()`, never before (`LanguageServerChannel.swift`).

### Security

- **secrets-keyed-by-id-then-env-var**: `LanguageServerSecrets` MUST key
  each server's secret values first by `configuration.id.uuidString`, then
  by environment-variable name (`LanguageServerConfiguration.swift`).
- **secrets-stored-in-keychain-not-plain-settings**: `UserSettings.languageServerSecrets`
  MUST be declared `isSecure: true`, routing stored secret values through
  the Keychain rather than the plain settings provider used for
  `languageServerConfigurations` (`LanguageServerSettings.swift`).
- **secrets-merged-into-environment-only-at-session-start**: a server's
  secret environment values MUST be merged into the subprocess environment
  only when a session starts (via `reconcile`/`performStart`), never
  persisted anywhere else in plaintext by this component
  (`LanguageServerRegistry.swift`, `LanguageServerSession.swift`).
- **command-path-not-validated**: an absolute `command` is a caller precondition that `LanguageServerConfiguration.command`'s doc comment states (the sandboxed app's `PATH` differs from a terminal's). The component does not check it before `performStart()` spawns the process, so a relative or bare-name value resolves against the subprocess's inherited working directory (`LanguageServerConfiguration.swift`, `LanguageServerSession.swift`).

