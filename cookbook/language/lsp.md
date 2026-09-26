---
id: eb7ece7f-746f-456f-ac0d-0a985dc9a94e
title: Language Services LSP
domain: agentictoolkit://cookbook/language/lsp
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Apple-platform LSP client stack: actor-based server sessions, a registry
  that reconciles configurations against running sessions, a per-session ordered document-sync
  pipeline, and a MainActor diagnostics store.'
platforms:
- apple
tags:
- lsp
- language-server
- diagnostics
- swift-concurrency
- actor
- document-sync
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Language/LSP/DiagnosticStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Language/LSP/DocumentSyncPipeline.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Language/LSP/LanguageServerChannel.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Language/LSP/LanguageServerConfiguration.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Language/LSP/LanguageServerDocumentSync.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Language/LSP/LanguageServerRegistry.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Language/LSP/LanguageServerSession.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Language/LSP/LanguageServerSettings.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitLanguageTests/DiagnosticStoreTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitLanguageTests/LanguageServerDocumentSyncScopeTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitLanguageTests/LanguageServerSessionRaceTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitLanguageTests/FakeLanguageServerSessionFidelityTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitLanguageTests/LanguageServerRegistryTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitLanguageTests/LanguageServerSessionTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitLanguageTests/LanguageServerDocumentSyncTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Language Services LSP

## Overview

`language-services-lsp` is the Apple-platform logic stack that speaks the
Language Server Protocol on behalf of the app: eight dependency-free Swift
files under `packages/apple/AgenticToolkit/Language/LSP/`
(`DiagnosticStore.swift`, `DocumentSyncPipeline.swift`,
`LanguageServerChannel.swift`, `LanguageServerConfiguration.swift`,
`LanguageServerDocumentSync.swift`, `LanguageServerRegistry.swift`,
`LanguageServerSession.swift`, `LanguageServerSettings.swift`). It has no UI
of its own. `LanguageServerSession` is an `actor` that owns one language
server subprocess end to end — spawn, `initialize` handshake, request/notify,
graceful-then-forced shutdown. `LanguageServerRegistry` is a `@MainActor`
`ObservableObject` that reconciles a desired set of server configurations
(built-in `SourceKit-LSP` plus user configurations) against the sessions
actually running, replacing or retiring them as configurations, secrets, or
enablement change. `DocumentSyncPipeline` is an `actor` holding one ordered
event queue per session that forwards `textDocument/didOpen|didChange
|didSave|didClose` according to the server's negotiated sync capability.
`LanguageServerDocumentSync` is a `@MainActor` coordinator that wires a
`TextDocumentStore` to the registry's sessions, scopes documents to the
workspace root, and replays already-open documents to newly connected
sessions. `DiagnosticStore` is a `@MainActor` `ObservableObject` that
consumes each session's `publishedDiagnostics` stream and holds the latest
diagnostics per document URI. `LanguageServerChannel` bridges a
`SubprocessChannel` onto a `JSONRPC.DataChannel`. `LanguageServerConfiguration`
and `LanguageServerSettings` describe how a server is launched and where its
non-secret settings and Keychain-routed secrets are stored.

## Behavioral Requirements

### Session Lifecycle

- **start-is-idempotent-and-joined**: `start()` MUST let a concurrent second
  caller join an in-flight start rather than spawn a second process, and
  every joined caller MUST observe the same outcome as the original caller
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.concurrentStartJoinsTheFirstRatherThanReturningEarly`).
- **start-after-stop-refused**: `start()` MUST throw
  `LanguageServerSessionError.sessionHasBeenStopped` rather than spawn a new
  process once `stop()` has been called
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.startAfterStopIsRefused`).
- **concurrent-start-propagates-shared-failure**: when a joined `start()`
  attempt fails, every joiner — the original caller and every later caller —
  MUST throw that same failure
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.concurrentStartPropagatesTheFailureToEveryCaller`).
- **capabilities-only-while-running**: `capabilities()` MUST return `nil`
  unless the session's state is `.running` and its server connection still
  exists; `LSPCompletionDelegate` relies on this as the only gate (`LanguageServerSession.swift`).
- **capabilities-go-nil-after-spontaneous-death**: once a running server dies
  on its own, `capabilities()` MUST answer `nil` on every subsequent call
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.capabilitiesGoesNilAfterARunningServerDiesOnItsOwn`).
- **outstanding-requests-block-teardown**: `teardown()` MUST wait, up to
  `outstandingRequestBudgetSeconds`, for every in-flight request tracked by
  `trackingOutstandingRequest` before shutting the server down (`LanguageServerSession.swift`).
- **stop-idempotent**: `stop()` MUST be safe to call more than once; a
  second call MUST NOT re-run teardown or overwrite a state the first call
  already reached (`LanguageServerSession.swift`).
- **stop-after-spontaneous-death-skips-budget**: `stop()` called after a
  server has already died on its own MUST return without waiting out the
  graceful-shutdown budget
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.stopAfterASpontaneousDeathDoesNotWaitOutTheBudget`).
- **stop-preserves-failed-state**: `stop()` MUST leave the state `.failed`
  rather than overwrite it to `.stopped` when the session had already
  failed before `stop()` was called (`LanguageServerSession.swift`).
- **stop-during-start-does-not-orphan**: `stop()` invoked while
  `performStart()` is still spawning the process MUST NOT crash the process
  and MUST NOT leave the child process running
  (`LanguageServerSession.swift`, `LanguageServerSessionRaceTests.stopDuringLaunchLeavesNoOrphan`, `.stopDuringStartIsNotFatal`).
- **state-changes-terminal-ordering**: the `stateChanges` stream MUST finish
  only after its terminal state value has been yielded, never before
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.stateChangesEmitsStartingThenRunningForASuccessfulStart`).
- **published-diagnostics-independent-of-state-changes**: the
  `publishedDiagnostics` stream MUST finish only via `teardown()` (or never,
  if the server dies without invoking it) — unlike `stateChanges`, reaching
  a terminal state does not by itself finish it (`LanguageServerSession.swift`).
- **stream-end-diagnosis-first-cause-wins**: when the channel ends,
  `diagnosedCause`/`fail(with:)` MUST record the first failure cause
  observed and MUST ignore later, redundant reports of the same end
  (`LanguageServerSession.swift`).
- **initialize-request-framed-once**: the `initialize` request MUST reach
  the server exactly once per session start
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.initializeRequestIsFramedExactlyOnce`).
- **initialize-response-round-trips**: a framed `initialize` response MUST
  decode back into the session's `ServerCapabilities` unchanged
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.framedInitializeResponseRoundTrips`).
- **initialize-declares-only-honourable-capabilities**: `clientCapabilities`
  MUST declare `snippetSupport`, `commitCharactersSupport`,
  `overlappingTokenSupport`, and `multilineTokenSupport` as `false`,
  matching renderer limitations the client cannot actually honor
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.initializeRequestDeclaresSemanticTokenCapabilities`).
- **truncated-frame-fails-session**: a transport error that truncates a
  response frame mid-body MUST fail the session's start with that transport
  error rather than hang or silently succeed
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.truncatedFrameFailsTheSessionWithTheTransportError`).
- **stderr-captured-on-failed-start**: standard error text emitted by a
  server process that dies during start MUST be captured and exposed via
  `standardErrorText()`/`LanguageServerFailure`
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.standardErrorIsCapturedOnAFailedStart`).
- **unasked-exit-is-a-failure**: a clean process exit not requested by
  `stop()` MUST be reported as `.failed`, never treated as an ordinary
  shutdown
  (`LanguageServerSession.swift`, `LanguageServerSessionTests.unaskedCleanExitFailsTheSession`).

### Registry and Configuration Reconciliation

- **user-config-replaces-not-merges-builtin**: `effectiveConfigurations(builtIn:user:)`
  MUST replace a built-in configuration for a language id entirely with the
  user's configuration for that id, never merge fields between them
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.userConfigurationReplacesTheBuiltIn`).
- **unrelated-builtin-survives**: a user configuration for one language id
  MUST leave the built-in configuration for every other language id
  untouched
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.unrelatedUserConfigurationLeavesTheBuiltInAlone`).
- **builtin-sourcekit-lsp-fixed-identity**: `builtInConfigurations` MUST
  ship a fixed-UUID (`1CE31A0E-0000-4000-A000-5357494654FF`) SourceKit-LSP
  configuration claiming `swift`, `objective-c`, `objective-cpp`, `c`, and
  `cpp`, with command `/usr/bin/sourcekit-lsp` and root markers
  `Package.swift`, `*.xcodeproj`, `*.xcworkspace`, `.git` (`LanguageServerRegistry.swift`).
- **root-marker-walk-innermost-first**: `workspaceRoot(startingAt:markers:fileManager:)`
  MUST walk upward from the starting path and stop at the nearest ancestor
  directory containing any marker, including glob-suffix markers like
  `*.xcodeproj`
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.rootMarkerWalkFindsTheNearestMarker`, `.rootMarkerWalkSupportsGlobSuffixes`).
- **marker-order-does-not-affect-root**: the order markers are listed in
  MUST NOT change which directory `workspaceRoot` resolves to
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.rootMarkerOrderDoesNotChangeTheRoot`).
- **unmatched-marker-resolves-nil**: when no ancestor directory contains any
  marker, `workspaceRoot` MUST resolve to `nil` rather than loop
  indefinitely
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.rootMarkerWalkReturnsNilWhenNothingMatches`).
- **session-rooted-at-marker-not-workspace**: `reconcile` MUST root a
  session's working directory at the resolved marker directory, not at the
  outer workspace root
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.reconcileResolvesTheRootFromMarkers`).
- **reconcile-diffs-desired-vs-current**: `reconcile(userConfigurations:secrets:)`
  MUST diff the desired session set against the current one by
  `SessionDescriptor` equality, starting only sessions whose descriptor
  changed and retiring only those superseded
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.unrelatedSettingsChangeKeepsTheSession`).
- **secret-change-triggers-replacement**: a change to a configuration's
  secrets MUST count as a descriptor change that replaces the running
  session, so the new secret reaches the replacement session's environment
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.secretsReachTheSessionAndTriggerAReplacement`).
- **disabling-tears-down-session**: setting `isEnabled` to `false` for a
  configuration MUST tear down its running session
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.disablingAConfigurationStopsItsSession`).
- **command-change-replaces-session**: changing a configuration's `command`
  MUST replace its running session
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.changingACommandReplacesTheSession`).
- **observe-state-refuses-second-observer**: `observeState(of:id:)` MUST
  refuse (log `.fault`, return `false`) a second concurrent observation of
  the same session id rather than deliver a doubled stream
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.aSecondObservationOfALiveSessionIsRefused`).
- **retired-session-late-transition-cannot-overwrite**: a state transition
  delivered by a session after it has been retired and replaced MUST NOT
  overwrite `sessionStates`' entry for the session that replaced it
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.aRetiredSessionsLateTransitionCannotOverwriteItsReplacement`).
- **shutdown-is-terminal**: `shutdown()` MUST set `isShutDown` before its
  first suspension point and MUST stop every session concurrently
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.shutdownStopsEverySession`).
- **shutdown-waits-for-retired-teardowns**: `shutdown()` MUST wait for a
  session that `reconcile` had already begun retiring before shutdown
  started
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.shutdownWaitsForARetiredSessionsTeardown`).
- **settings-write-during-shutdown-starts-nothing**: a configuration change
  delivered while `shutdown()` is in flight MUST start no new session
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.aSettingsWriteDuringShutdownStartsNothing`).
- **session-states-never-outruns-configurations**: `sessionStates` MUST
  never hold an id whose configuration is not also present in
  `configurations`
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.statesAreAlwaysASubsetOfConfigurations`).

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

## Appearance

Not applicable — this is a headless language-server client stack, not a visual component.

## States

Not applicable — this is a headless language-server client stack, not a visual component.

## Accessibility

Not applicable — this is a headless language-server client stack, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| language-services-lsp-001 | start-is-idempotent-and-joined | Two concurrent `start()` calls on an idle session | Exactly one process spawn; both callers see the same outcome |
| language-services-lsp-002 | start-after-stop-refused | `start()` called after `stop()` has completed | Throws `LanguageServerSessionError.sessionHasBeenStopped` |
| language-services-lsp-003 | concurrent-start-propagates-shared-failure | Two concurrent `start()` calls where the shared attempt fails | Both callers throw the same `LanguageServerFailure` |
| language-services-lsp-004 | capabilities-only-while-running | `capabilities()` called while state is `.starting` | Returns `nil` |
| language-services-lsp-005 | capabilities-go-nil-after-spontaneous-death | `capabilities()` called after a running server exits on its own | Returns `nil` |
| language-services-lsp-006 | stop-idempotent | `stop()` called twice in a row on a running session | Second call is a no-op; teardown runs exactly once |
| language-services-lsp-007 | stop-preserves-failed-state | `stop()` called on a session already in `.failed` | State remains `.failed`, not `.stopped` |
| language-services-lsp-008 | initialize-request-framed-once | A session start against a scripted server | Exactly one `initialize` request frame is sent |
| language-services-lsp-009 | initialize-declares-only-honourable-capabilities | Inspect `makeInitializeParams()`'s semantic-token/completion flags | `snippetSupport`, `commitCharactersSupport`, `overlappingTokenSupport`, `multilineTokenSupport` are all `false` |
| language-services-lsp-010 | truncated-frame-fails-session | A scripted server that truncates its response mid-body | Session start fails with the transport/framing error |
| language-services-lsp-011 | unasked-clean-exit-fails-session | A scripted server that exits 0 without `stop()` being called | Session state becomes `.failed`, not `.stopped` |
| language-services-lsp-012 | stop-during-start-does-not-orphan | `stop()` called while `performStart()` is still spawning | Call returns without crashing; no orphaned child process remains |
| language-services-lsp-013 | user-config-replaces-not-merges-builtin | A user configuration for `swift` alongside the built-in SourceKit-LSP | Effective configuration for `swift` is the user's, wholesale |
| language-services-lsp-014 | unrelated-builtin-survives | A user configuration for `python` only | Built-in `swift`/`objective-c`/`c`/`cpp` configuration is untouched |
| language-services-lsp-015 | root-marker-walk-innermost-first | A file two directories below a `.git`-marked root that is itself below another `.git` | Walk resolves to the nearer (innermost) marker directory |
| language-services-lsp-016 | marker-order-does-not-affect-root | `["*.xcodeproj", ".git"]` vs `[".git", "*.xcodeproj"]` on the same tree | Both orders resolve to the same root directory |
| language-services-lsp-017 | unmatched-marker-resolves-nil | Markers that exist nowhere on the ancestor chain | `workspaceRoot` resolves to `nil` |
| language-services-lsp-018 | secret-change-triggers-replacement | A settings write changing one server's secret env value | Its session is torn down and restarted with the new secret in its environment |
| language-services-lsp-019 | disabling-tears-down-session | `isEnabled` flipped from `true` to `false` for a configuration | Its running session is stopped and removed |
| language-services-lsp-020 | observe-state-refuses-second-observer | `observeState(of:id:)` called twice for the same live session id | Second call logs `.fault` and returns `false` |
| language-services-lsp-021 | retired-session-late-transition-cannot-overwrite | A retired session emits a late state transition after its replacement is running | `sessionStates` still reflects the replacement, unchanged |
| language-services-lsp-022 | settings-write-during-shutdown-starts-nothing | A configuration change delivered mid-`shutdown()` | No new session is started |
| language-services-lsp-023 | per-session-ordered-queue | `enqueue` called with opened, edited, saved, closed in that order | Server receives the four notifications in the same order |
| language-services-lsp-024 | open-close-defaults-true | A server capability response omitting `openClose` | `ResolvedTextDocumentSync.openClose` resolves to `true` |
| language-services-lsp-025 | change-reopens-unopened-document | `didChange` forwarded for a document the server was never told is open | `didOpen` is sent first, then the `didChange` |
| language-services-lsp-026 | incremental-sync-forwards-verbatim | Resolved sync kind `.incremental`, an edit with a 2-element change array | Server receives the same 2-element change array |
| language-services-lsp-027 | full-sync-forwards-whole-document | Resolved sync kind `.full`, an edit to one line of a multi-line document | Server receives one `didChange` carrying the whole document text |
| language-services-lsp-028 | failed-start-pipeline-forwards-nothing | A pipeline whose session start throws | No `didOpen`/`didChange`/`didSave`/`didClose` reaches the server |
| language-services-lsp-029 | open-close-disabled-still-sends-change | Resolved capability with `openClose == false`, one edit | No `didOpen`/`didClose` sent; `didChange` is still sent |
| language-services-lsp-030 | replay-matches-claimed-language-only | A newly connected `swift`-only session with one open `swift` and one open `python` document | Only the `swift` document is replayed |
| language-services-lsp-031 | out-of-scope-documents-silently-excluded | An edit to a document outside the workspace root | No `didOpen`/`didChange` notification is sent to any session |
| language-services-lsp-032 | scope-check-resolves-symlinks | A workspace root reached only through a symlink, and a document under its resolved path | Document is classified in scope |
| language-services-lsp-033 | string-prefix-sibling-excluded | Root `/work/App` and document under `/work/AppOther/file.swift` | Document is classified out of scope |
| language-services-lsp-034 | out-of-scope-refusals-counted-once-per-batch | A seeding pass refusing 3 out-of-scope documents | Exactly one `UpstreamDivergenceLedger` entry recording the count |
| language-services-lsp-035 | observe-is-idempotent-per-session | `DiagnosticStore.observe(session)` called twice for the same session | Only one consumer of that session's `publishedDiagnostics` is started |
| language-services-lsp-036 | stale-diagnostics-never-dropped | `PublishDiagnosticsParams` with `version: nil` | Diagnostics for that URI are stored, not discarded |
| language-services-lsp-037 | empty-diagnostics-clears-not-ignored | An empty diagnostics array published for a URI already holding diagnostics | Stored diagnostics for that URI become empty |
| language-services-lsp-038 | document-diagnostics-pruned-on-close | A `.closed` `TextDocumentStore` event dropping a document's refcount to 0 | Stored diagnostics for that URI are removed |
| language-services-lsp-039 | shutdown-idempotent-preserves-diagnostics | `shutdown()` called twice on a store holding diagnostics | Second call is a no-op; diagnostics remain readable |
| language-services-lsp-040 | secrets-stored-in-keychain-not-plain-settings | Inspect `UserSettings.languageServerSecrets`'s declared provider | `isSecure: true`, routed to the Keychain provider |
| language-services-lsp-041 | stream-end-handler-called-exactly-once | A channel whose underlying process exits | `StreamEndHandler` fires exactly once, with the exit condition |

## Edge Cases

- **Null/empty input**: `DiagnosticStore` publishing an empty diagnostics
  array for a URI MUST clear it rather than be ignored
  (empty-diagnostics-clears-not-ignored). A `PublishDiagnosticsParams` with
  a `nil` `version` MUST still be stored (stale-diagnostics-never-dropped).
- **Boundary/malformed values**: A workspace-root marker list containing a
  glob suffix marker (`*.xcodeproj`) with no literal match on disk MUST
  fall through to the next marker in the walk rather than throw
  (root-marker-walk-innermost-first). A truncated JSON-RPC frame mid-body
  MUST fail the session start with the transport error rather than hang
  (truncated-frame-fails-session).
- **Concurrent access**: Two concurrent `start()` calls MUST join into one
  process spawn (start-is-idempotent-and-joined). `stop()` invoked while
  `performStart()` is still spawning MUST NOT leave an orphaned child
  process (stop-during-start-does-not-orphan). A retired session's late
  state transition MUST NOT overwrite its replacement's entry in
  `sessionStates` (retired-session-late-transition-cannot-overwrite). A
  second concurrent `observeState(of:id:)` for the same session id MUST be
  refused, not doubled (observe-state-refuses-second-observer).
- **Error states**: A clean, unrequested process exit MUST be reported as
  `.failed`, never as an ordinary `.stopped` shutdown
  (unasked-exit-is-a-failure). `capabilities()` MUST answer `nil` once a
  running server has died on its own, even though the last observed state
  was `.running` (capabilities-go-nil-after-spontaneous-death). A pipeline
  whose session failed to start MUST forward none of its queued events and
  MUST NOT retry the start (failed-start-pipeline-forwards-nothing).
- **Workspace-scope boundary**: A document whose path is a string prefix
  collision with the workspace root (a sibling directory, not a true
  descendant) MUST be classified out of scope
  (string-prefix-sibling-excluded); a document reached only through a
  symlinked root MUST still be classified in scope after path resolution
  (scope-check-resolves-symlinks).
- **Shutdown races**: A configuration/settings write delivered while
  `LanguageServerRegistry.shutdown()` is in flight MUST start no new
  session (settings-write-during-shutdown-starts-nothing); `shutdown()`
  MUST still wait for a session `reconcile` had already begun retiring
  before shutdown started (shutdown-waits-for-retired-teardowns).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `LanguageServerConfiguration.command` | `String` | none (caller-supplied) | Absolute path to the server executable, e.g. `/usr/bin/sourcekit-lsp` |
| `LanguageServerConfiguration.languageIds` | `[String]` | none (caller-supplied) | LSP language ids this server serves, e.g. `["swift"]` |
| `LanguageServerConfiguration.arguments` | `[String]` | `[]` | Process arguments passed to `command` |
| `LanguageServerConfiguration.environment` | `[String: String]` | `[:]` | Non-secret environment overrides merged over the parent environment |
| `LanguageServerConfiguration.rootMarkers` | `[String]` | `[".git"]` | File/directory names, most specific first, that mark a workspace root; supports glob-suffix markers like `*.xcodeproj` |
| `LanguageServerConfiguration.isEnabled` | `Bool` | `true` | Whether the registry starts/keeps a session for this configuration |
| `UserSettings.languageServerConfigurations` | `[LanguageServerConfiguration]` (regular provider) | `[]` | Persisted key `languageServer.serverConfigurations` |
| `UserSettings.languageServerSecrets` | `LanguageServerSecrets` (`isSecure: true`, Keychain) | `[:]` | Persisted key `languageServer.serverSecrets`, keyed by `id.uuidString` then env-var name |
| `LanguageServerSession.Configuration.initializeBudgetSeconds` | `TimeInterval` | `30` | Wall-clock budget for the `initialize` handshake |
| `LanguageServerSession.Configuration.shutdownBudgetSeconds` | `TimeInterval` | `2` | Wall-clock budget for the graceful `shutdown`/`exit` round trip |
| `LanguageServerSession.Configuration.abandonedStartBudgetSeconds` | `TimeInterval` | `1` | Wall-clock budget teardown waits for an in-flight start to abandon |
| `LanguageServerSession.Configuration.outstandingRequestBudgetSeconds` | `TimeInterval` | `2` | Wall-clock budget teardown waits for outstanding requests to finish |
| `LanguageServerSession.Configuration.exitStatusBudgetSeconds` | `TimeInterval` | `1` | Wall-clock budget teardown waits for the process exit status |
| `LanguageServerRegistry.builtInConfigurations` | static `[LanguageServerConfiguration]` | one entry (SourceKit-LSP, fixed UUID `1CE31A0E-0000-4000-A000-5357494654FF`) | Ships regardless of user configuration; overridden per-language by a matching user configuration |

## Deep Linking

Not applicable: this component defines no URL scheme, universal link, or
app-intent entry point of its own; it is invoked only through in-process
calls from the app's editor and settings layers.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `LanguageServerSessionError.serverExited` | The language server exited with status {status}. | `LanguageServerSessionError.errorDescription` (`LanguageServerSession.swift`) |
| `LanguageServerSessionError.sessionHasBeenStopped` | The language server session has been stopped. | `LanguageServerSessionError.errorDescription` (`LanguageServerSession.swift`) |
| `LanguageServerSessionError.notRunning` | The language server is not running. | `LanguageServerSessionError.errorDescription` (`LanguageServerSession.swift`) |

Every string above is hardcoded English with no lookup table, ICU message,
or locale parameter anywhere in these eight files — this is a plain fact
about the source, not a gap: these are `LocalizedError` descriptions
surfaced in developer-facing logs/failure states, and a port to a platform
with an i18n layer MUST decide, as a design choice outside this contract,
whether and how to route them through it.

## Accessibility Options

Not applicable: this module renders no UI and defines no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color behavior. Those display
options act on whatever editor UI a host renders around diagnostics and
completions, not on this headless module.

## Feature Flags

- **per-server-enablement**: `LanguageServerConfiguration.isEnabled` is a
  genuine per-server, user-controlled flag: the registry starts a session
  for a configuration only while it is `true`, and tears it down the moment
  it flips to `false` (`LanguageServerRegistry.swift`).

## Analytics

Not applicable: no file in this component emits a client-side analytics or
product-telemetry event. `UpstreamDivergenceLedger.record` (used by
`LanguageServerDocumentSync.recordOutOfScope`) is a diagnostic ledger for an
internal-consistency signal (documents refused for being outside workspace
scope), not a product-analytics event stream.

## Privacy

- **Data collected**: Per-server secret environment values (e.g. API keys a
  language server needs), stored under `UserSettings.languageServerSecrets`,
  keyed by `configuration.id.uuidString` then environment-variable name
  (secrets-keyed-by-id-then-env-var). Non-secret configuration (command,
  arguments, non-secret environment, root markers) is not sensitive and is
  stored via the regular settings provider.
- **Storage**: Secrets are routed through `isSecure: true`, i.e. the
  Keychain, never the plain settings file
  (secrets-stored-in-keychain-not-plain-settings). Diagnostics held by
  `DiagnosticStore` are in-memory only, keyed by document URI, and are never
  persisted to disk by this component.
- **Transmission**: A server's secret environment values are merged into
  its subprocess environment only at session start; this component never
  transmits them over the JSON-RPC channel itself — only the spawned
  process sees them, as environment variables
  (secrets-merged-into-environment-only-at-session-start).
- **Retention**: Diagnostics for a document are retained until the document
  is closed by its last editor (document-diagnostics-pruned-on-close) or
  until `DiagnosticStore.clear(uri:)`/`shutdown()` is called; secrets persist
  in the Keychain until the user removes the configuration or changes the
  secret value.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via the `Loggable` protocol's
default) | Category: the conforming type's name

| Event | Level | Message |
|-------|-------|---------|
| Diagnostic/document forwarding failure while the session is not running | debug | `.notRunning` operation failure (`DocumentSyncPipeline.swift`) |
| Any other diagnostic/document forwarding failure | error | `record(_:operation:uri:)`'s default path (`DocumentSyncPipeline.swift`) |
| Channel forwarding-task failure | error | `LanguageServerChannel`'s stream-end handling (`LanguageServerChannel.swift`) |
| A second concurrent observation of a live session's state | fault | `observeState(of:id:)`'s refusal (`LanguageServerRegistry.swift`) |
| Session start/stop/teardown failures | error | `LanguageServerSession`'s failure-diagnosis pipeline (`LanguageServerSession.swift`) |

`DiagnosticStore.swift` and `LanguageServerDocumentSync.swift` conform to no
logging protocol and emit no log calls of their own — a plain fact about
these two files, not a gap; their failure signal is a ledger write
(`UpstreamDivergenceLedger`) or the observable state they publish, not a
log line.

## Platform Notes

- **SwiftUI/AppKit/UIKit**: This is the reference implementation.
  `Foundation.Process` (via `SubprocessChannel`) launches the server;
  `JSONRPC`/`LanguageServerProtocol`/`LanguageClient` frame and type the
  protocol; Swift `actor`s (`LanguageServerSession`, `DocumentSyncPipeline`)
  and `@MainActor` `ObservableObject`s (`DiagnosticStore`,
  `LanguageServerRegistry`, `LanguageServerDocumentSync`) provide isolation;
  `AsyncStream` carries `publishedDiagnostics`/`stateChanges`; the Keychain
  (via `isSecure: true` settings) stores secrets.
- **Compose/Android**: `ProcessBuilder`/`Runtime.exec` replaces
  `Foundation.Process`; a hand-rolled or third-party JSON-RPC/LSP client
  library replaces `JSONRPC`/`LanguageServerProtocol`; Kotlin coroutines with
  a `Mutex`-guarded class replace an `actor`; `StateFlow`/`SharedFlow`
  replace `AsyncStream`; the Android Keystore (via `EncryptedSharedPreferences`
  or Jetpack Security) replaces the Keychain for secrets.
- **React/Web**: There is no direct browser analog for spawning a local
  subprocess; a web-hosted port would need a companion native/host process
  (e.g. a desktop shell's IPC bridge) to launch the language server, with
  `postMessage`/WebSocket framing standing in for the JSON-RPC channel;
  secrets would need to live in the host's secure storage, never in web
  `localStorage`.
- **WinUI 3**: `System.Diagnostics.Process` replaces `Foundation.Process`
  for spawning the server; `System.IO.Pipes` or the process's redirected
  standard streams carry the JSON-RPC frames, with `System.Text.Json`
  replacing `Foundation.JSONDecoder`/`JSONEncoder` for every LSP message.
  `Task`/`async`-`await` with a `SemaphoreSlim`-guarded class is the
  idiomatic equivalent of an `actor` for `LanguageServerSession` and
  `DocumentSyncPipeline`; an `ObservableCollection`/`INotifyPropertyChanged`-backed
  class, or a C# `event`, replaces the `@Published` properties on
  `LanguageServerRegistry`/`DiagnosticStore`; a `System.Threading.Channels.Channel<T>`
  replaces `AsyncStream` for `publishedDiagnostics`/`stateChanges`.
  `Windows.Security.Credentials.PasswordVault` replaces the Keychain for
  routing per-server secret environment values.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Language/LSP/` |

## Design Decisions

**Decision**: `PublishDiagnosticsParams` with a `nil` or stale `version` is
never dropped by `DiagnosticStore` — the store always keeps the most
recently published diagnostics for a URI regardless of version.
**Rationale**: Many language servers omit `version` on published
diagnostics or publish out of band with the document's own edit stream;
treating an unversioned or older-versioned publish as untrustworthy would
mean silently losing diagnostics for those servers rather than showing
something. Overwriting on send order, not version order, keeps the store
simple and matches what LSP servers actually send in practice.
**Approved**: pending

**Decision**: `DocumentSyncPipeline.forward(_:sync:)` gates `.changed` and
`.closed` events on `openURIs.contains(uri)` but deliberately does not gate
`.saved` the same way.
**Rationale**: The source's own comment asks that this asymmetry not be
"fixed" — a `.saved` event for a document the pipeline does not believe is
open is forwarded anyway, because some server integrations rely on
receiving `didSave` even across an open-tracking edge case that would
otherwise suppress it; unifying the gating would silently drop those saves.
**Approved**: pending

**Decision**: A user configuration for a language id replaces the built-in
configuration for that id wholesale in `effectiveConfigurations`, rather
than merging fields (e.g. keeping the built-in's `rootMarkers` while taking
the user's `command`).
**Rationale**: Partial merging would require a field-by-field precedence
rule that has no natural default (should a user's `arguments` merge with or
replace the built-in's?); replacing wholesale is unambiguous and matches
the mental model of "I am supplying my own server for this language,"
consistent with how `MCPServerConfiguration` in this codebase makes the
same choice.
**Approved**: pending

**Decision**: `LanguageServerSession.stop()` preserves a `.failed` state
rather than overwriting it with `.stopped`, and skips the graceful-shutdown
budget entirely when the server has already died on its own.
**Rationale**: Once a server has died, there is nothing left to negotiate a
graceful `shutdown`/`exit` with, so waiting out that budget would only delay
`stop()` for no benefit; and reporting `.stopped` over a genuine `.failed`
would hide from callers (and from `sessionStates` observers) that the
process died unexpectedly rather than being asked to stop.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | Reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | passed | Reliability |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |

`separation-of-concerns` **passed**: each of the eight files owns one
concern — process/transport (`LanguageServerChannel`), one server's
lifecycle (`LanguageServerSession`), fleet reconciliation
(`LanguageServerRegistry`), per-session document forwarding
(`DocumentSyncPipeline`), workspace-scope/replay coordination
(`LanguageServerDocumentSync`), diagnostics aggregation (`DiagnosticStore`),
and configuration/settings shape (`LanguageServerConfiguration`,
`LanguageServerSettings`) — with dependencies pointing one way, from session
up through registry and document sync. `unit-test-coverage` **passed**:
every file has a dedicated test file (`DiagnosticStoreTests`,
`LanguageServerSessionTests`, `LanguageServerSessionRaceTests`,
`LanguageServerRegistryTests`, `LanguageServerDocumentSyncTests`,
`LanguageServerDocumentSyncScopeTests`,
`FakeLanguageServerSessionFidelityTests`) covering ordering, concurrency,
and failure paths, not just the happy path. `explicit-error-handling`
**passed**: every failure path surfaces a typed `LanguageServerSessionError`/`LanguageServerFailure`
or is logged with an explicit level (debug for `.notRunning`, error
otherwise) — no path silently swallows a primary operation's failure.
`error-recovery` **passed**: `start()`'s join-in-flight behavior, the
first-cause-wins failure diagnosis, and `reconcile`'s diff-and-replace
model all exist specifically to keep concurrent and transient failures from
corrupting session or registry state. `timeout-handling` **passed**: every
teardown step (abandoned-start, outstanding-request, graceful-shutdown,
exit-status) runs under an explicit wall-clock budget rather than waiting
indefinitely. `secure-storage` **passed**: per-server secrets are declared
`isSecure: true` and routed to the Keychain, never the plain settings
provider. `input-sanitization` is **partial**: workspace-scope checks
(`isInWorkspaceScope`) validate document paths against the resolved
workspace root, but `LanguageServerConfiguration.command` itself is not
validated to be an absolute path before being handed to the process spawn
(see `command-path-not-validated` above) — an accepted gap in the source,
not a hidden one.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
