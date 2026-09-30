<!-- leaf: implement-language/services-lsp · source: language-services-lsp.md -->

**Rules** (cite as `implement-language/services-lsp#<slug>`):

- `start-is-idempotent-and-joined` MUST
- `start-after-stop-refused` MUST
- `concurrent-start-propagates-shared-failure` MUST
- `capabilities-only-while-running` MUST
- `capabilities-go-nil-after-spontaneous-death` MUST
- `outstanding-requests-block-teardown` MUST
- `stop-idempotent` MUST
- `stop-after-spontaneous-death-skips-budget` MUST
- `stop-preserves-failed-state` MUST
- `stop-during-start-does-not-orphan` MUST
- `state-changes-terminal-ordering` MUST
- `published-diagnostics-independent-of-state-changes` MUST
- `stream-end-diagnosis-first-cause-wins` MUST
- `initialize-request-framed-once` MUST
- `initialize-response-round-trips` MUST
- `initialize-declares-only-honourable-capabilities` MUST
- `truncated-frame-fails-session` MUST
- `stderr-captured-on-failed-start` MUST
- `unasked-exit-is-a-failure` MUST

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

