<!-- leaf: implement-git-client/projects-project-workspace--edge-cases · source: git-client-projects-project-workspace.md -->

# ProjectWorkspace

**Rules** (cite as `implement-git-client/projects-project-workspace--edge-cases#<slug>`):

- `null-and-empty-input` MUST — storedTabs() treats a loadTabs result whose tabs array is empty the same as a thrown error — both produce nil …
- `boundary-values` MUST — allocatePaneNumber()'s counter starts at 1 and has no declared upper bound; it is a plain Int, so the boundary this …
- `error-states` MUST — Every database-backed method except storedTabs() catches its error, logs it through Self.logger.error (or …
- `cancellation-and-timeouts` MUST — No method on ProjectWorkspace is async; every operation here is a synchronous database call, a synchronous cache …
- `missing-file-or-unreachable-server` MUST — A primary/directory argument that does not exist on disk is not distinguished from one that does — …

## Edge Cases

- **Null and empty input**: `storedTabs()` treats a `loadTabs` result whose
  `tabs` array is empty the same as a thrown error — both produce `nil`
  (**stored-tabs-nil-when-empty-or-absent**, MUST). `paneStateList` for an
  unset key, or for a key holding a string that is not valid UTF-8 or not
  valid JSON, returns `[]` rather than throwing or crashing
  (**pane-state-list-json-encoded**, MUST). `setPaneStateList` with an empty
  `values` array clears the key instead of writing `"[]"`
  (**pane-state-list-json-encoded**, MUST).
- **Boundary values**: `allocatePaneNumber()`'s counter starts at `1` and has
  no declared upper bound; it is a plain `Int`, so the boundary this file
  defines no behavior for is `Int.max` overflow, which Swift traps on rather
  than wrapping (MUST, by the language's own arithmetic semantics — not a
  case this file guards against itself). `initialTabs()`'s stored-tab path is
  only reached when `stored.tabs` is non-empty, because `storedTabs()` already
  filters the empty case out, so the `shared[0].id` fallback in
  **active-tab-fallback** never indexes an empty array.
- **Concurrent access**: Every property and method here is confined to the
  main actor (**main-actor-isolation**), so no two calls on one
  `ProjectWorkspace` instance can interleave their mutations of `repo`,
  `nextPaneNumber`, or either `WeakCache`. Two separate `ProjectWorkspace`
  instances built over the same `repo.id` (a project opened in two windows)
  can still race at the `ProjectDatabase` layer — `persistTabs`, `setSetting`,
  `setPaneState`, and `persistProjectDirectories` from one instance are not
  serialized against calls from another — but ordering that race, when it
  matters, is `ProjectController`'s job (see
  `agentictoolkit://recipes/git-client-projects-project-controller`), not
  this file's; `ProjectWorkspace` itself makes no ordering claim across
  instances.
- **Error states**: Every database-backed method except `storedTabs()` catches
  its error, logs it through `Self.logger.error` (or `logPaneStateFailure`),
  and returns a safe default — `nil`, `[]`, or nothing — rather than
  propagating it (**persist-tabs-swallows-failure**,
  **pane-state-failures-swallowed-and-logged-with-full-context**,
  **project-setting-scoped-by-repo**,
  **project-directories-load-failure-yields-empty**, all MUST). The one
  exception, `storedTabs()`'s bare `try?`, has no log signal at all — see
  **stored-tabs-load-failure-signal**.
- **Offline or disconnected state**: Not applicable in the network sense —
  every dependency this file reads or writes (`ProjectDatabase`, the
  filesystem paths it resolves symlinks against) is local. `gitStatusProvider
  (forDirectory:)` hands out an object built on `gitClient`, but the git
  subprocess calls that object goes on to make are that object's own concern,
  not this file's (see `agentictoolkit://recipes/git-client`).
- **Cancellation and timeouts**: No method on `ProjectWorkspace` is `async`;
  every operation here is a synchronous database call, a synchronous cache
  lookup, or a pure computation, so there is no cancellation token, timeout,
  or `Task` for this file to honor or ignore (MUST, by the absence of any
  `async` signature in `ProjectWorkspace.swift`).
- **Missing file or unreachable server**: A `primary`/`directory` argument
  that does not exist on disk is not distinguished from one that does —
  `resolvingSymlinksInPath()` on a nonexistent path returns the path
  unchanged, so `fileBrowserDirectories(primary:)` and `gitStatusProvider
  (forDirectory:)` still mint and cache an object keyed to it
  (**file-browser-directories-cached-per-resolved-primary**,
  **git-status-provider-cached-per-resolved-directory**, MUST, by the absence
  of any existence check in either method).
