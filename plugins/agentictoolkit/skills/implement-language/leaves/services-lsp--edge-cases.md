<!-- leaf: implement-language/services-lsp--edge-cases · source: language-services-lsp.md -->

# Language Services LSP

**Rules** (cite as `implement-language/services-lsp--edge-cases#<slug>`):

- `null-empty-input` MUST — DiagnosticStore publishing an empty diagnostics array for a URI MUST clear it rather than be ignored …
- `boundary-malformed-values` MUST — A workspace-root marker list containing a glob suffix marker (*.xcodeproj) with no literal match on disk MUST fall …
- `concurrent-access` MUST — Two concurrent start() calls MUST join into one process spawn (start-is-idempotent-and-joined). stop() invoked while …
- `error-states` MUST — A clean, unrequested process exit MUST be reported as .failed, never as an ordinary .stopped shutdown …
- `workspace-scope-boundary` MUST — A document whose path is a string prefix collision with the workspace root (a sibling directory, not a true descendant) …
- `shutdown-races` MUST — A configuration/settings write delivered while LanguageServerRegistry.shutdown() is in flight MUST start no new session …

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
