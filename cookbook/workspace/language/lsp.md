---
id: eb7ece7f-746f-456f-ac0d-0a985dc9a94e
title: Language Server Protocol Client
domain: agentictoolkit://cookbook/workspace/language/lsp
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'A Language Server Protocol client stack: per-server sessions, a registry
  that reconciles configurations against running sessions, a per-session ordered document-sync
  pipeline, and a diagnostics store.'
platforms:
- apple
tags:
- lsp
- language-server
- diagnostics
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

# Language Server Protocol Client

## Overview

This is the logic stack that speaks the Language Server Protocol on behalf
of the app: eight dependency-free components. It has no UI of its own. The
server session owns one language server subprocess end to end — spawn,
`initialize` handshake, request/notify, graceful-then-forced shutdown. The
registry reconciles a desired set of server configurations (a built-in
SourceKit-LSP configuration plus user configurations) against the sessions
actually running, replacing or retiring them as configurations, secrets, or
enablement change. The document-sync pipeline holds one ordered event queue
per session that forwards `textDocument/didOpen|didChange|didSave|didClose`
according to the server's negotiated sync capability. The sync coordinator
wires the document store to the registry's sessions, scopes documents to the
workspace root, and replays already-open documents to newly connected
sessions. The diagnostics store consumes each session's published-diagnostics
stream and holds the latest diagnostics per document URI. The transport
channel bridges a subprocess's raw input/output onto the JSON-RPC framing the
protocol runs over. A server configuration and the persisted settings
describe how a server is launched and where its non-secret settings and its
secrets are stored.

## Behavioral Requirements

### Session Lifecycle

- **start-is-idempotent-and-joined**: starting the session MUST let a
  concurrent second caller join an in-flight start rather than spawn a
  second process, and every joined caller MUST observe the same outcome as
  the original caller.
- **start-after-stop-refused**: starting the session MUST throw a
  stopped-session error rather than spawn a new process once the session
  has been stopped.
- **concurrent-start-propagates-shared-failure**: when a joined start
  attempt fails, every joiner — the original caller and every later caller
  — MUST throw that same failure.
- **capabilities-only-while-running**: reading the session's capabilities
  MUST return nothing unless the session's state is running and its server
  connection still exists; the completion delegate relies on this as the
  only gate.
- **capabilities-go-nil-after-spontaneous-death**: once a running server
  dies on its own, reading the session's capabilities MUST answer nothing
  on every subsequent call.
- **outstanding-requests-block-teardown**: tearing the session down MUST
  wait, up to a fixed outstanding-request budget, for every in-flight
  request being tracked before shutting the server down.
- **stop-idempotent**: stopping the session MUST be safe to call more than
  once; a second call MUST NOT re-run teardown or overwrite a state the
  first call already reached.
- **stop-after-spontaneous-death-skips-budget**: stopping the session after
  a server has already died on its own MUST return without waiting out the
  graceful-shutdown budget.
- **stop-preserves-failed-state**: stopping the session MUST leave the
  state failed rather than overwrite it to stopped when the session had
  already failed before being stopped.
- **stop-during-start-does-not-orphan**: stopping the session while it is
  still spawning the process MUST NOT crash the process and MUST NOT leave
  the child process running.
- **state-changes-terminal-ordering**: the state-change stream MUST finish
  only after its terminal state value has been yielded, never before.
- **published-diagnostics-independent-of-state-changes**: the
  published-diagnostics stream MUST finish only via tearing the session
  down (or never, if the server dies without that happening) — unlike the
  state-change stream, reaching a terminal state does not by itself finish
  it.
- **stream-end-diagnosis-first-cause-wins**: when the channel ends,
  recording the end cause MUST record the first failure cause observed and
  MUST ignore later, redundant reports of the same end.
- **initialize-request-framed-once**: the `initialize` request MUST reach
  the server exactly once per session start.
- **initialize-response-round-trips**: a framed `initialize` response MUST
  decode back into the session's capabilities unchanged.
- **initialize-declares-only-honourable-capabilities**: the declared client
  capabilities MUST declare `snippetSupport`, `commitCharactersSupport`,
  `overlappingTokenSupport`, and `multilineTokenSupport` as `false`,
  matching renderer limitations the client cannot actually honor.
- **truncated-frame-fails-session**: a transport error that truncates a
  response frame mid-body MUST fail the session's start with that
  transport error rather than hang or silently succeed.
- **stderr-captured-on-failed-start**: standard error text emitted by a
  server process that dies during start MUST be captured and exposed as
  part of the reported failure.
- **unasked-exit-is-a-failure**: a clean process exit not requested by
  stopping the session MUST be reported as failed, never treated as an
  ordinary shutdown.

### Registry and Configuration Reconciliation

- **user-config-replaces-not-merges-builtin**: computing the effective
  configuration set MUST replace a built-in configuration for a language id
  entirely with the user's configuration for that id, never merge fields
  between them.
- **unrelated-builtin-survives**: a user configuration for one language id
  MUST leave the built-in configuration for every other language id
  untouched.
- **builtin-sourcekit-lsp-fixed-identity**: the built-in configurations
  MUST ship a fixed-identifier (`1CE31A0E-0000-4000-A000-5357494654FF`)
  SourceKit-LSP configuration claiming `swift`, `objective-c`,
  `objective-cpp`, `c`, and `cpp`, with command `/usr/bin/sourcekit-lsp` and
  root markers `Package.swift`, `*.xcodeproj`, `*.xcworkspace`, `.git`.
- **root-marker-walk-innermost-first**: resolving the workspace root MUST
  walk upward from the starting path and stop at the nearest ancestor
  directory containing any marker, including glob-suffix markers like
  `*.xcodeproj`.
- **marker-order-does-not-affect-root**: the order markers are listed in
  MUST NOT change which directory the workspace-root resolution resolves
  to.
- **unmatched-marker-resolves-nil**: when no ancestor directory contains
  any marker, resolving the workspace root MUST resolve to nothing rather
  than loop indefinitely.
- **session-rooted-at-marker-not-workspace**: reconciling the desired
  sessions MUST root a session's working directory at the resolved marker
  directory, not at the outer workspace root.
- **reconcile-diffs-desired-vs-current**: reconciling the desired sessions
  MUST diff the desired session set against the current one by descriptor
  equality, starting only sessions whose descriptor changed and retiring
  only those superseded.
- **secret-change-triggers-replacement**: a change to a configuration's
  secrets MUST count as a descriptor change that replaces the running
  session, so the new secret reaches the replacement session's
  environment.
- **disabling-tears-down-session**: setting a configuration's enablement to
  disabled MUST tear down its running session.
- **command-change-replaces-session**: changing a configuration's launch
  command MUST replace its running session.
- **observe-state-refuses-second-observer**: observing a session's state
  MUST refuse (log at fault level, return failure) a second concurrent
  observation of the same session id rather than deliver a doubled stream.
- **retired-session-late-transition-cannot-overwrite**: a state transition
  delivered by a session after it has been retired and replaced MUST NOT
  overwrite the published session-state table's entry for the session that
  replaced it.
- **shutdown-is-terminal**: shutting the registry down MUST set its
  shut-down flag before its first suspension point and MUST stop every
  session concurrently.
- **shutdown-waits-for-retired-teardowns**: shutting the registry down MUST
  wait for a session that reconciliation had already begun retiring before
  shutdown started.
- **settings-write-during-shutdown-starts-nothing**: a configuration change
  delivered while shutdown is in flight MUST start no new session.
- **session-states-never-outruns-configurations**: the published
  session-state table MUST never hold an id whose configuration is not
  also present in the current configuration set.

### Document Sync

- **per-session-ordered-queue**: the document-sync pipeline MUST maintain
  exactly one ordered event queue per session (not per document), and
  enqueueing an event MUST preserve the caller's emission order.
- **sync-capability-resolved-once**: running the pipeline MUST resolve the
  session's resolved sync capability exactly once per pipeline run, before
  forwarding any queued event.
- **open-close-defaults-true**: resolving the sync capability MUST default
  `openClose` to `true` when the server's capability omits it.
- **change-reopens-unopened-document**: forwarding a change MUST send
  `didOpen` for a document before forwarding a `didChange` for it, when the
  server has not yet been told the document is open.
- **saved-gating-is-asymmetric**: forwarding of save events MUST NOT be
  gated on the tracked open-URI set, unlike change and close events — a
  deliberate asymmetry documented in source, not an oversight.
- **incremental-sync-forwards-verbatim**: when the resolved sync kind is
  incremental, forwarding a change MUST forward the store's change array
  verbatim.
- **full-sync-forwards-whole-document**: when the resolved sync kind is
  full, each edit MUST be forwarded as exactly one whole-document
  `didChange`.
- **text-and-version-captured-together**: each `didChange` MUST carry the
  document's text as of the same version it reports, never a text/version
  pair captured across an intervening edit.
- **failed-start-pipeline-forwards-nothing**: a pipeline whose session
  start failed MUST NOT retry the start and MUST forward none of its
  queued events.
- **not-running-logged-as-debug**: logging a forwarding failure MUST log a
  not-running forwarding failure at debug level; every other forwarding
  failure MUST log at error level.
- **open-close-disabled-still-sends-change**: when the resolved capability
  disables `openClose`, the pipeline MUST send no `didOpen`/`didClose` but
  MUST still send `didChange`.
- **reconcile-retires-stale-before-adding**: reconciling pipelines with the
  current sessions MUST retire pipelines for sessions no longer present
  before starting pipelines for newly reconciled sessions.
- **addpipeline-joins-in-flight-registry-start**: adding a pipeline's own
  start call MUST join a registry-reconciliation-initiated start already
  in flight for the same session, rather than starting the session a
  second time.
- **replay-matches-claimed-language-only**: replaying already-open
  documents MUST seed a newly connected session only with already-open
  documents whose language id the session's configuration claims.
- **session-replacement-rebuilds-pipeline**: replacing a session MUST hand
  the new session the currently open documents and MUST send the old
  session's pipeline nothing further.
- **out-of-scope-documents-silently-excluded**: checking workspace scope
  MUST exclude a document outside the workspace root from being opened,
  changed, or replayed to any session, producing no server notification at
  all.
- **scope-check-resolves-symlinks**: checking workspace scope MUST resolve
  and standardize both the document path and the workspace root before
  comparing path components, so a symlinked root or a mismatched
  temp-directory alias does not misclassify an in-scope document as out of
  scope.
- **string-prefix-sibling-excluded**: a sibling directory whose path is a
  string prefix of the workspace root MUST be classified out of scope, not
  admitted by a naive prefix compare.
- **out-of-scope-replay-skipped**: replaying already-open documents MUST
  NOT replay a document already open outside the workspace root to a newly
  connected session.
- **out-of-scope-refusals-counted-once-per-batch**: recording an
  out-of-scope refusal MUST record refusals encountered while seeding a
  session in one ledger entry per seeding pass, not one entry per document.
- **clean-seeding-pass-records-nothing**: a seeding pass that refuses
  nothing MUST NOT write any entry to the divergence ledger.

### Diagnostics

- **observe-is-idempotent-per-session**: beginning to observe a session
  MUST be idempotent for a given session, keyed by object identity —
  calling it again for a session already observed MUST NOT start a second
  consumer of that session's single-consumer published-diagnostics stream.
- **stale-diagnostics-never-dropped**: diagnostics published with a
  missing or older version MUST still be stored and MUST NOT be discarded,
  even though the version field is optional and frequently absent.
- **publishes-land-in-send-order**: two publishes for the same URI MUST
  leave the store holding the second (most recently sent), reflecting send
  order regardless of version.
- **empty-diagnostics-clears-not-ignored**: an empty diagnostics array
  published for a URI MUST clear that URI's stored diagnostics, not be
  treated as a no-op.
- **document-diagnostics-pruned-on-close**: observing documents in a
  project MUST forget a document's stored diagnostics once its last editor
  closes it (a close event with the document's reference count reaching
  zero).
- **shutdown-idempotent-preserves-diagnostics**: shutting the diagnostics
  store down MUST be safe to call more than once and MUST leave
  already-stored diagnostics intact — it stops observation, it does not
  clear state.
- **retired-session-does-not-block-later-observation**: once a session's
  stream ends, a later session MUST still be observed normally.
- **publishes-in-send-order-across-n**: N publishes for a session MUST
  arrive at the store in the order they were sent.
- **published-stream-finish-is-observed**: the store MUST recognize that a
  session's published-diagnostics stream has finished, both when the
  session stops cleanly and when it fails to start.

### Transport

- **stream-end-handler-called-exactly-once**: the stream-end handler MUST
  be invoked exactly once per channel, with nothing denoting a clean end.
- **drain-called-after-terminate**: callers MUST drain the channel only
  after terminating the underlying subprocess channel, never before.

### Security

- **secrets-keyed-by-id-then-env-var**: the per-server secrets store MUST
  key each server's secret values first by the configuration's id, then by
  environment-variable name.
- **secrets-stored-in-keychain-not-plain-settings**: the persisted secrets
  setting MUST be declared secure, routing stored secret values through
  the platform's secure credential storage rather than the plain settings
  provider used for the persisted server-configurations setting.
- **secrets-merged-into-environment-only-at-session-start**: a server's
  secret environment values MUST be merged into the subprocess environment
  only when a session starts, never persisted anywhere else in plaintext
  by this component.
- **command-path-not-validated**: an absolute launch command is a caller
  precondition the configuration's own documentation states (the host
  application's own PATH differs from a terminal's). The component does
  not check it before spawning the process, so a relative or bare-name
  value resolves against the subprocess's inherited working directory.

## Appearance

Not applicable — this is a headless language-server client stack, not a visual component.

## States

Not applicable — this is a headless language-server client stack, not a visual component.

## Accessibility

Not applicable — this is a headless language-server client stack, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| language-services-lsp-001 | start-is-idempotent-and-joined | Two concurrent starts of an idle session | Exactly one process spawn; both callers see the same outcome |
| language-services-lsp-002 | start-after-stop-refused | Starting the session after stopping it has completed | Throws a stopped-session error |
| language-services-lsp-003 | concurrent-start-propagates-shared-failure | Two concurrent starts where the shared attempt fails | Both callers throw the same reported failure |
| language-services-lsp-004 | capabilities-only-while-running | Reading the session's capabilities while its state is starting | Returns nothing |
| language-services-lsp-005 | capabilities-go-nil-after-spontaneous-death | Reading the session's capabilities after a running server exits on its own | Returns nothing |
| language-services-lsp-006 | stop-idempotent | Stopping the session twice in a row while it is running | Second call is a no-op; teardown runs exactly once |
| language-services-lsp-007 | stop-preserves-failed-state | Stopping a session already in the failed state | State remains failed, not stopped |
| language-services-lsp-008 | initialize-request-framed-once | A session start against a scripted server | Exactly one `initialize` request frame is sent |
| language-services-lsp-009 | initialize-declares-only-honourable-capabilities | Inspect the declared client capabilities' semantic-token/completion flags | `snippetSupport`, `commitCharactersSupport`, `overlappingTokenSupport`, `multilineTokenSupport` are all `false` |
| language-services-lsp-010 | truncated-frame-fails-session | A scripted server that truncates its response mid-body | Session start fails with the transport/framing error |
| language-services-lsp-011 | unasked-exit-is-a-failure | A scripted server that exits cleanly without stopping being called for | Session state becomes failed, not stopped |
| language-services-lsp-012 | stop-during-start-does-not-orphan | Stopping the session while it is still spawning | Call returns without crashing; no orphaned child process remains |
| language-services-lsp-013 | user-config-replaces-not-merges-builtin | A user configuration for `swift` alongside the built-in SourceKit-LSP | Effective configuration for `swift` is the user's, wholesale |
| language-services-lsp-014 | unrelated-builtin-survives | A user configuration for `python` only | Built-in `swift`/`objective-c`/`c`/`cpp` configuration is untouched |
| language-services-lsp-015 | root-marker-walk-innermost-first | A file two directories below a `.git`-marked root that is itself below another `.git` | Walk resolves to the nearer (innermost) marker directory |
| language-services-lsp-016 | marker-order-does-not-affect-root | `["*.xcodeproj", ".git"]` vs `[".git", "*.xcodeproj"]` on the same tree | Both orders resolve to the same root directory |
| language-services-lsp-017 | unmatched-marker-resolves-nil | Markers that exist nowhere on the ancestor chain | The workspace root resolves to nothing |
| language-services-lsp-018 | secret-change-triggers-replacement | A settings write changing one server's secret env value | Its session is torn down and restarted with the new secret in its environment |
| language-services-lsp-019 | disabling-tears-down-session | Enablement flipped from `true` to `false` for a configuration | Its running session is stopped and removed |
| language-services-lsp-020 | observe-state-refuses-second-observer | Observing a session's state twice for the same live session id | Second call logs at fault level and returns failure |
| language-services-lsp-021 | retired-session-late-transition-cannot-overwrite | A retired session emits a late state transition after its replacement is running | The published session-state table still reflects the replacement, unchanged |
| language-services-lsp-022 | settings-write-during-shutdown-starts-nothing | A configuration change delivered mid-shutdown | No new session is started |
| language-services-lsp-023 | per-session-ordered-queue | Enqueueing opened, edited, saved, closed events in that order | Server receives the four notifications in the same order |
| language-services-lsp-024 | open-close-defaults-true | A server capability response omitting `openClose` | The resolved sync capability's `openClose` resolves to `true` |
| language-services-lsp-025 | change-reopens-unopened-document | `didChange` forwarded for a document the server was never told is open | `didOpen` is sent first, then the `didChange` |
| language-services-lsp-026 | incremental-sync-forwards-verbatim | Resolved sync kind incremental, an edit with a 2-element change array | Server receives the same 2-element change array |
| language-services-lsp-027 | full-sync-forwards-whole-document | Resolved sync kind full, an edit to one line of a multi-line document | Server receives one `didChange` carrying the whole document text |
| language-services-lsp-028 | failed-start-pipeline-forwards-nothing | A pipeline whose session start throws | No `didOpen`/`didChange`/`didSave`/`didClose` reaches the server |
| language-services-lsp-029 | open-close-disabled-still-sends-change | Resolved capability with `openClose == false`, one edit | No `didOpen`/`didClose` sent; `didChange` is still sent |
| language-services-lsp-030 | replay-matches-claimed-language-only | A newly connected `swift`-only session with one open `swift` and one open `python` document | Only the `swift` document is replayed |
| language-services-lsp-031 | out-of-scope-documents-silently-excluded | An edit to a document outside the workspace root | No `didOpen`/`didChange` notification is sent to any session |
| language-services-lsp-032 | scope-check-resolves-symlinks | A workspace root reached only through a symlink, and a document under its resolved path | Document is classified in scope |
| language-services-lsp-033 | string-prefix-sibling-excluded | Root `/work/App` and document under `/work/AppOther/file.swift` | Document is classified out of scope |
| language-services-lsp-034 | out-of-scope-refusals-counted-once-per-batch | A seeding pass refusing 3 out-of-scope documents | Exactly one divergence-ledger entry recording the count |
| language-services-lsp-035 | observe-is-idempotent-per-session | Beginning to observe the same session twice | Only one consumer of that session's published-diagnostics stream is started |
| language-services-lsp-036 | stale-diagnostics-never-dropped | A diagnostics publish with `version: nil` | Diagnostics for that URI are stored, not discarded |
| language-services-lsp-037 | empty-diagnostics-clears-not-ignored | An empty diagnostics array published for a URI already holding diagnostics | Stored diagnostics for that URI become empty |
| language-services-lsp-038 | document-diagnostics-pruned-on-close | A close event dropping a document's reference count to zero in the document store | Stored diagnostics for that URI are removed |
| language-services-lsp-039 | shutdown-idempotent-preserves-diagnostics | Shutting the diagnostics store down twice while it holds diagnostics | Second call is a no-op; diagnostics remain readable |
| language-services-lsp-040 | secrets-stored-in-keychain-not-plain-settings | Inspect the persisted secrets setting's declared provider | Declared secure, routed to the platform's secure credential storage |
| language-services-lsp-041 | stream-end-handler-called-exactly-once | A channel whose underlying process exits | The stream-end handler fires exactly once, with the exit condition |

## Edge Cases

- **Null/empty input**: The diagnostics store publishing an empty
  diagnostics array for a URI MUST clear it rather than be ignored
  (empty-diagnostics-clears-not-ignored). A diagnostics publish with a
  missing version MUST still be stored (stale-diagnostics-never-dropped).
- **Boundary/malformed values**: A workspace-root marker list containing a
  glob-suffix marker (`*.xcodeproj`) with no literal match on disk MUST
  fall through to the next marker in the walk rather than throw
  (root-marker-walk-innermost-first). A truncated protocol frame mid-body
  MUST fail the session start with the transport error rather than hang
  (truncated-frame-fails-session).
- **Concurrent access**: Two concurrent starts MUST join into one process
  spawn (start-is-idempotent-and-joined). Stopping the session while it is
  still spawning MUST NOT leave an orphaned child process
  (stop-during-start-does-not-orphan). A retired session's late state
  transition MUST NOT overwrite its replacement's entry in the published
  session-state table (retired-session-late-transition-cannot-overwrite).
  A second concurrent observation of the same session's state MUST be
  refused, not doubled (observe-state-refuses-second-observer).
- **Error states**: A clean, unrequested process exit MUST be reported as
  failed, never as an ordinary stopped shutdown (unasked-exit-is-a-failure).
  Reading the session's capabilities MUST answer nothing once a running
  server has died on its own, even though the last observed state was
  running (capabilities-go-nil-after-spontaneous-death). A pipeline whose
  session failed to start MUST forward none of its queued events and MUST
  NOT retry the start (failed-start-pipeline-forwards-nothing).
- **Workspace-scope boundary**: A document whose path is a string prefix
  collision with the workspace root (a sibling directory, not a true
  descendant) MUST be classified out of scope
  (string-prefix-sibling-excluded); a document reached only through a
  symlinked root MUST still be classified in scope after path resolution
  (scope-check-resolves-symlinks).
- **Shutdown races**: A configuration/settings write delivered while the
  registry's shutdown is in flight MUST start no new session
  (settings-write-during-shutdown-starts-nothing); shutting the registry
  down MUST still wait for a session reconciliation had already begun
  retiring before shutdown started (shutdown-waits-for-retired-teardowns).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `command` | string | none (caller-supplied) | Absolute path to the server executable, e.g. `/usr/bin/sourcekit-lsp` |
| `languageIds` | array of strings | none (caller-supplied) | LSP language ids this server serves, e.g. `["swift"]` |
| `arguments` | array of strings | `[]` | Process arguments passed to `command` |
| `environment` | key-value map | `{}` | Non-secret environment overrides merged over the parent environment |
| `rootMarkers` | array of strings | `[".git"]` | File/directory names, most specific first, that mark a workspace root; supports glob-suffix markers like `*.xcodeproj` |
| `isEnabled` | boolean | `true` | Whether the registry starts/keeps a session for this configuration |
| Persisted server-configurations list | array of configurations | `[]` | Persisted key `languageServer.serverConfigurations` |
| Persisted server-secrets store | secrets map, routed through secure storage | `{}` | Persisted key `languageServer.serverSecrets`, keyed by the configuration's id then env-var name |
| Handshake budget | seconds | `30` | Wall-clock budget for the `initialize` handshake |
| Graceful-shutdown budget | seconds | `2` | Wall-clock budget for the graceful shutdown/exit round trip |
| Abandoned-start budget | seconds | `1` | Wall-clock budget teardown waits for an in-flight start to abandon |
| Outstanding-request budget | seconds | `2` | Wall-clock budget teardown waits for outstanding requests to finish |
| Exit-status budget | seconds | `1` | Wall-clock budget teardown waits for the process exit status |
| Built-in configurations | one fixed entry | SourceKit-LSP, fixed identifier `1CE31A0E-0000-4000-A000-5357494654FF` | Ships regardless of user configuration; overridden per-language by a matching user configuration |

## Deep Linking

Not applicable: this component defines no URL scheme, universal link, or
app-intent entry point of its own; it is invoked only through in-process
calls from the app's editor and settings layers.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `LanguageServerSessionError.serverExited` | The language server exited with status {status}. | Session failure description |
| `LanguageServerSessionError.sessionHasBeenStopped` | The language server session has been stopped. | Session failure description |
| `LanguageServerSessionError.notRunning` | The language server is not running. | Session failure description |

Every string above is hardcoded English with no lookup table, ICU message,
or locale parameter anywhere in this component — this is a plain fact about
the source, not a gap: these are structured, localizable failure
descriptions surfaced in developer-facing logs/failure states, and a port to
a platform with an i18n layer MUST decide, as a design choice outside this
contract, whether and how to route them through it.

## Accessibility Options

Not applicable: this module renders no UI and defines no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color behavior. Those display
options act on whatever editor UI a host renders around diagnostics and
completions, not on this headless module.

## Feature Flags

- **per-server-enablement**: a configuration's enablement flag is a
  genuine per-server, user-controlled flag: the registry starts a session
  for a configuration only while it is enabled, and tears it down the
  moment it is disabled.

## Analytics

Not applicable: no part of this component emits a client-side analytics or
product-telemetry event. The divergence ledger's record operation (used
when recording an out-of-scope refusal) is a diagnostic ledger for an
internal-consistency signal (documents refused for being outside workspace
scope), not a product-analytics event stream.

## Privacy

- **Data collected**: Per-server secret environment values (e.g. API keys a
  language server needs), stored in the persisted secrets setting, keyed by
  the configuration's id then environment-variable name
  (secrets-keyed-by-id-then-env-var). Non-secret configuration (command,
  arguments, non-secret environment, root markers) is not sensitive and is
  stored via the regular settings provider.
- **Storage**: Secrets are routed through secure storage, never the plain
  settings file (secrets-stored-in-keychain-not-plain-settings).
  Diagnostics held by the diagnostics store are in-memory only, keyed by
  document URI, and are never persisted to disk by this component.
- **Transmission**: A server's secret environment values are merged into
  its subprocess environment only at session start; this component never
  transmits them over the protocol channel itself — only the spawned
  process sees them, as environment variables
  (secrets-merged-into-environment-only-at-session-start).
- **Retention**: Diagnostics for a document are retained until the document
  is closed by its last editor (document-diagnostics-pruned-on-close) or
  until they are explicitly cleared or the store is shut down; secrets
  persist in secure storage until the user removes the configuration or
  changes the secret value.

## Logging

Subsystem: the host app's bundle identifier (via the shared logging
protocol's default) | Category: the logging component's own name

| Event | Level | Message |
|-------|-------|---------|
| Diagnostic/document forwarding failure while the session is not running | debug | A not-running operation failure |
| Any other diagnostic/document forwarding failure | error | The default forwarding-failure path |
| Channel forwarding-task failure | error | The transport channel's stream-end handling |
| A second concurrent observation of a live session's state | fault | The refusal to observe a session a second time |
| Session start/stop/teardown failures | error | The session's failure-diagnosis pipeline |

The diagnostics store and the sync coordinator conform to no logging
protocol and emit no log calls of their own — a plain fact about this
component, not a gap; their failure signal is a ledger write (the
divergence ledger) or the observable state they publish, not a log line.

## Platform Notes

- **SwiftUI/AppKit/UIKit**: This is the reference implementation.
  `Foundation.Process` (via `SubprocessChannel`) launches the server;
  `JSONRPC`/`LanguageServerProtocol`/`LanguageClient` frame and type the
  protocol; Swift `actor`s (`LanguageServerSession`, `DocumentSyncPipeline`)
  and `@MainActor` `ObservableObject`s (`DiagnosticStore`,
  `LanguageServerRegistry`, `LanguageServerDocumentSync`) provide isolation;
  `AsyncStream` carries `publishedDiagnostics`/`stateChanges`; the Keychain
  (via `isSecure: true` settings) stores secrets. Failure descriptions
  conform to `LocalizedError`; logging goes through the `Loggable`
  protocol's default subsystem (`Bundle.main.bundleIdentifier`) and a
  per-type category. The command's absolute-path precondition is stated in
  `LanguageServerConfiguration.command`'s doc comment because a sandboxed
  app's `PATH` differs from a terminal's; the component does not enforce it
  before spawning the process.
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

**Decision**: A diagnostics publish with a missing or stale `version` is
never dropped by the diagnostics store — the store always keeps the most
recently published diagnostics for a URI regardless of version.
**Rationale**: Many language servers omit `version` on published
diagnostics or publish out of band with the document's own edit stream;
treating an unversioned or older-versioned publish as untrustworthy would
mean silently losing diagnostics for those servers rather than showing
something. Overwriting on send order, not version order, keeps the store
simple and matches what LSP servers actually send in practice.
**Approved**: pending

**Decision**: Forwarding in the document-sync pipeline gates change and
close events on the tracked open-URI set, but deliberately does not gate
save events the same way.
**Rationale**: The source's own comment asks that this asymmetry not be
"fixed" — a save event for a document the pipeline does not believe is
open is forwarded anyway, because some server integrations rely on
receiving `didSave` even across an open-tracking edge case that would
otherwise suppress it; unifying the gating would silently drop those saves.
**Approved**: pending

**Decision**: A user configuration for a language id replaces the built-in
configuration for that id wholesale when computing the effective
configuration set, rather than merging fields (e.g. keeping the built-in's
root markers while taking the user's command).
**Rationale**: Partial merging would require a field-by-field precedence
rule that has no natural default (should a user's arguments merge with or
replace the built-in's?); replacing wholesale is unambiguous and matches
the mental model of "I am supplying my own server for this language,"
consistent with how this codebase's MCP server configuration makes the
same choice.
**Approved**: pending

**Decision**: Stopping a session preserves a failed state rather than
overwriting it with stopped, and skips the graceful-shutdown budget
entirely when the server has already died on its own.
**Rationale**: Once a server has died, there is nothing left to negotiate a
graceful shutdown/exit with, so waiting out that budget would only delay
stopping for no benefit; and reporting stopped over a genuine failed state
would hide from callers (and from the session-state observers) that the
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/language/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
