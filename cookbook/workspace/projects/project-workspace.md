---
id: 33086772-2d36-49f5-8e1d-725163d7ce8f
title: Project Workspace
domain: agentictoolkit://cookbook/workspace/projects/project-workspace
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The project a window opens: a repository, its persisted tabs, pane state, settings,
  directories, plus weakly-cached per-directory browser and git-status objects.'
platforms:
- swift
- macos
tags:
- git
- projects
- workspace
- tabs
- pane-state
- caching
depends-on: []
related:
- agentictoolkit://cookbook/workspace/projects/project-database
- agentictoolkit://cookbook/workspace/projects/project-database-layout
- agentictoolkit://cookbook/workspace/projects/git-repo
- agentictoolkit://cookbook/workspace/projects/project-checkout
- agentictoolkit://cookbook/workspace/projects/branch-controller
- agentictoolkit://cookbook/workspace/projects/project-controller
- agentictoolkit://cookbook/ui/layout/composable-tabs/tabs-window
- agentictoolkit://cookbook/foundation/git/git-client
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWorkspace.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectWorkspaceTabsTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase+Layout.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTabReconciler.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsLayout.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabLayoutSpec.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/LayoutNode.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/Edge.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/FileBrowserDirectories.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/Git/GitStatusProvider.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitClient.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Editor/ProjectLanguageServices.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWorkspace.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Project Workspace

## Overview

This is one open project: the repository it is, the database rows keyed
to that repository, and the tab/split arrangement its window shows. Per
its own doc comment, it is "what a document object used to be here,
minus the document" — there is no file to read, write, autosave, revert
or name, because a project is a repository row plus the rows keyed to it,
so every edit is already saved and a repository can move on disk without
the project noticing. It owns the project's stored tab tree (reading
stored tabs, computing initial tabs, persisting tabs), an untyped
per-pane and per-project string bag (pane state, project settings), the
project's extra file-browser roots (the file-browser-directories lookup,
persisting project directories), and two directory-keyed object caches —
one for file-browser roots and one for git status — that hold their
values weakly so exactly one instance exists for as long as anything
still needs it. It is confined to the UI's main execution context, and
every property and method is confined there by that declaration alone.

## Behavioral Requirements

- **main-thread-confinement**: The workspace MUST be confined to the
  UI's main execution context, with no thread-safety guarantee of its
  own, so every stored property and method is confined there by that
  declaration alone.
- **repo-identity**: `id` MUST be computed as the repository's own id,
  `displayName` MUST be computed as the repository's own name, and
  `directoryURL` MUST be computed as the repository's own directory, on
  every access rather than cached separately.
- **repo-mutation-exposed-read-only**: The repository MUST be exposed
  read-only, so only this workspace's own update operation may change
  it; every other reader sees it as read-only.
- **update-preserves-identity**: Updating the repository MUST replace the
  stored repository with the argument only when the argument's id equals
  the stored repository's id, and MUST leave the stored repository
  unchanged and return with no other effect when the ids differ.
- **pane-number-allocation-is-monotonic**: Allocating a pane number MUST
  return the current value of an internal counter that starts at `1` and
  MUST then increment that counter, so no two calls on one workspace
  instance ever return the same number and no released number is ever
  reused.
- **cache-directory-derivation**: The cache directory MUST be computed as
  a `caches/<repository id as a UUID string>/` subdirectory of the
  directory containing the database's own file, and reading it MUST NOT
  create that directory or any of its parents on disk.
- **stored-tabs-nil-when-empty-or-absent**: Reading stored tabs MUST
  return nothing both when loading tabs from the database throws and
  when it returns a tabs list that is empty, collapsing "nothing was
  ever persisted" and "the load failed" into the same result.
- **initial-tabs-default-when-nothing-stored**: When reading stored tabs
  returns nothing, computing the initial tabs MUST return exactly one
  tab record titled `"Tab 1"` with its root set to the layout's own
  blueprint, that tab's own id as the active tab id, and a single top
  edge as the enabled edges.
- **stored-tab-trees-repaired-against-current-spec**: When tabs are
  stored, computing the initial tabs MUST rewrite every tab's root by
  reconciling it against the layout's current spec before doing anything
  else with it, so a tree built under an earlier spec that no longer
  allows one of its panes is repaired on load.
- **one-arrangement-per-project**: After that repair, computing the
  initial tabs MUST compute one shared arrangement over the repaired
  tabs and their active-tab id, and, when that computation produces one,
  MUST reshape every tab's root to match it, each tab getting its own
  fresh set of node ids.
- **stale-focused-node-cleared**: For every tab, computing the initial
  tabs MUST clear the focused node to none whenever that node's id is no
  longer present among the tab's (possibly just rewritten) root's leaf
  ids, following either rewrite above.
- **active-tab-fallback**: Computing the initial tabs MUST return the
  stored active-tab id as the active id when it names one of the
  returned tabs, and MUST otherwise fall back to the first returned
  tab's own id.
- **persist-tabs-swallows-failure**: Persisting tabs MUST save the given
  tabs, active-tab id, and enabled edges to the database, and on failure
  MUST log the error and MUST NOT throw, retry, or otherwise signal the
  failure to its caller.
- **pane-state-scoped-by-node-and-key**: Reading and writing pane state
  MUST read and write through the database's own pane-state accessors,
  scoped by this project's own repository id together with the given
  node id and key.
- **chrome-prefix-is-unenforced-convention**: A key beginning with
  `chrome.` is reserved for the pane-state store's own use; pane content
  reading or writing pane state MUST NOT use a key with that prefix, but
  the workspace performs no runtime check of this rule itself.
- **pane-state-failures-swallowed-and-logged-with-full-context**: Reading
  pane state, writing pane state, and pruning nested pane state MUST
  each catch any error the database throws, log it naming the verb, this
  project's repository id, the node id, and the key (`"*"` for pruning),
  and MUST NOT propagate it; reading pane state MUST return nothing on
  that path and writing/pruning MUST simply return.
- **pane-state-list-json-encoded**: Reading a pane-state list MUST decode
  the stored string as a JSON list of strings and MUST return an empty
  list when the key is unset, the stored string is not valid text, or
  JSON decoding fails. Writing a pane-state list MUST clear the key when
  the given list is empty, and MUST otherwise JSON-encode the list to a
  string and write it, doing nothing when either encoding step fails.
- **project-setting-scoped-by-repo**: Reading and writing a project
  setting MUST read and write through the database's own per-repository
  setting accessors, scoped to this project's own repository id, and
  MUST log and return nothing (for a read) or simply return (for a
  write) on failure rather than propagate it.
- **setting-nil-deletes-row**: Writing a project setting with no value
  MUST delete the underlying row rather than storing an empty or null
  value, so "never set" and "set back to the default" are the same
  state.
- **project-directories-load-failure-yields-empty**: Reading the
  project's extra directories MUST return an empty list and log the
  failure when loading them from the database throws, rather than
  propagate the error or return a stale cached value.
- **file-browser-directories-cached-per-resolved-primary**: The
  file-browser-directories lookup MUST resolve symlinks in its
  primary-directory argument before using it as a cache key, MUST return
  the cached value for that resolved key when one is still alive, and
  MUST otherwise construct a new value seeded with the project's extra
  directories, register the directory-change handler on it, cache it
  under the resolved key, and return it.
- **file-browser-directories-weakly-held**: The cache backing the
  file-browser-directories lookup and the git-status-provider lookup
  MUST hold its values weakly and MUST drop a key as soon as nothing
  outside the cache still holds the value stored under it, so a
  directory nothing is showing any more is forgotten rather than
  accumulated for the life of the project.
- **directory-addition-fans-out-to-every-live-sibling**: The
  directory-change handler MUST persist the merged directory list and
  then refresh every other still-live cached file-browser-directories
  value the cache currently holds (every live entry whose key is not the
  one that changed), so a directory added or removed through one
  directory's browser reaches every other open browser for the same
  project.
- **primary-is-re-added-if-stored-but-dropped**: Before persisting, the
  directory-change handler MUST re-add the changed value's own primary
  directory to the merged list when the previously stored list contained
  it but the incoming directory list does not, and MUST NOT add it
  otherwise — because a file-browser-directories value never lists its
  own primary among its additional roots.
- **git-status-provider-cached-per-resolved-directory**: The
  git-status-provider lookup MUST resolve symlinks in its directory
  argument before using it as a cache key, MUST return the cached value
  for that key when one is still alive, and MUST otherwise construct a
  new git-status provider over this project's own git client, cache it
  under the resolved key, and return it.
- **extension-workspace-roots-conformance**: The workspace MUST conform
  to the extension-workspace-roots interface, exposing its display name
  as the project's own display name and its workspace root directories
  as the project's own file-browser directories, primary first.
- **git-client-defaults-to-shared-injectable**: Construction MUST default
  the git client to the shared git client when the caller supplies none,
  and every operation that mints a per-directory object or vends git
  access (the file-browser-directories lookup, by way of caching; the
  git-status-provider lookup) MUST use this project's stored git client,
  never a client of its own.
- **layout-defaults-through-fallback-chain**: Construction MUST resolve
  an absent layout argument as the app-installed layout when one exists,
  or a placeholder-only layout otherwise.
- **stored-tabs-load-failure-signal**: NEEDS REVIEW: Not implemented in
  source. Reading stored tabs discards whatever error loading tabs from
  the database throws, with no log call and no other signal, unlike
  every other failing database access in this file — reading/writing a
  setting, reading the project's extra directories, persisting project
  directories, persisting tabs, and the three pane-state operations all
  log on their failure path. A database error while loading a project's
  tabs is therefore indistinguishable from a project that has simply
  never saved any, with zero diagnostic trail either way. Resolving this
  needs a decision from whoever owns this file: whether reading stored
  tabs should log like its siblings do, and whether computing the
  initial tabs' caller needs a way to tell "nothing stored" apart from
  "the load failed" at all.

## Appearance

Not applicable — this is a project's persisted-state and per-directory object
cache, not a visual component.

## States

Not applicable — this is a project's persisted-state and per-directory object
cache, not a visual component. Its only runtime state is the tab tree
(reading and computing stored/initial tabs) and the two weak object caches,
all covered under Behavioral Requirements, not here.

## Accessibility

Not applicable — this is a project's persisted-state and per-directory object
cache, not a visual component. The accessibility of the panes it causes to
exist is the concern of whatever hosts a tab record's content (the branch
controller's pane view, the file browser), neither of which this file
renders itself.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-workspace-001 | stored-tabs-nil-when-empty-or-absent | Build a fresh workspace over an empty database and read its stored tabs. | reading stored tabs returns nothing — ProjectWorkspaceTabsTests.swift › testStoredTabsIsNilBeforeAnythingIsPersisted |
| git-client-projects-project-workspace-002 | persist-tabs-swallows-failure, stored-tabs-nil-when-empty-or-absent | Build one tab record on the workspace's own layout blueprint, persist it as the sole tab with itself as the active tab and a left edge enabled, then read stored tabs. | reading stored tabs returns a value; its tabs' ids equal the one record's id; its active-tab id equals the record's id; its enabled edges equal a single left edge — ProjectWorkspaceTabsTests.swift › testStoredTabsReturnsWhatWasPersisted |
| git-client-projects-project-workspace-003 | file-browser-directories-cached-per-resolved-primary | Call the file-browser-directories lookup twice with the same worktree directory. | both calls return the identical value; the first result's primary path equals the worktree directory's path; the project's own file-browser-directories value (for the project's own directory) is a distinct instance from the first — ProjectWorkspaceTabsTests.swift › testFileBrowserDirectoriesAreCachedPerPrimary |
| git-client-projects-project-workspace-004 | git-status-provider-cached-per-resolved-directory | Call the git-status-provider lookup twice with the same worktree directory, then once with a different, unrelated root directory. | the two worktree-directory calls return the identical value; the first result's repository root equals the worktree directory with symlinks resolved; the unrelated root's provider is a distinct instance from the first — ProjectWorkspaceTabsTests.swift › testGitStatusProvidersAreCachedPerDirectory |
| git-client-projects-project-workspace-005 | file-browser-directories-weakly-held | Take the file-browser-directories value and the git-status-provider value for the same worktree directory, inside a scope holding only weak references, confirm each is reference-identical to a second call made inside that scope, then let the scope end and call both lookups again. | both weak references become nothing once the scope ends; a fresh call afterward mints a working value whose primary path still equals the worktree directory with symlinks resolved, and a repeat of that fresh call again returns the identical instance — ProjectWorkspaceTabsTests.swift › testADirectoryNothingHoldsAnyMoreIsForgotten |
| git-client-projects-project-workspace-006 | directory-addition-fans-out-to-every-live-sibling | Take the file-browser-directories values for an unrelated root directory and for a worktree directory; add a directory to the unrelated root's value; then add a different directory to the worktree's value. | after the first addition, the worktree value's additional directories equal the one added directory, resolved; after the second addition, the project's own extra-directories list contains both added directories, and the two values' additional-directory lists are equal to each other — ProjectWorkspaceTabsTests.swift › testARootAddedInOneBrowserReachesTheOtherAndSurvivesItsNextSave |
| git-client-projects-project-workspace-007 | primary-is-re-added-if-stored-but-dropped | Take the same two file-browser-directories values as above; add the unrelated root directory itself to the worktree's value (adding the main checkout as a root of the worktree browser); then add a new directory to the unrelated-root value. | immediately after the first addition, the unrelated-root value's additional directories are empty (a browser never lists its own primary); after the second addition, the project's own extra-directories list still contains both the unrelated root directory and the newly added one — ProjectWorkspaceTabsTests.swift › testARootThatIsAnotherBrowsersPrimaryIsNotDroppedByThatBrowsersSave |
| git-client-projects-project-workspace-008 | initial-tabs-default-when-nothing-stored | Not present in the given test suite; synthesized from the source. Build a fresh workspace with nothing persisted; compute its initial tabs. | the returned tabs list has exactly one tab record titled `"Tab 1"` whose root equals the workspace's own layout blueprint; the active-tab id equals that tab's own id; the enabled edges equal a single top edge — synthesized, no dedicated test in the given suite |
| git-client-projects-project-workspace-009 | stored-tab-trees-repaired-against-current-spec, one-arrangement-per-project, stale-focused-node-cleared, active-tab-fallback | Not present in the given test suite; synthesized from the source. Persist two tab records built under a spec that later disallows one pane in the second tab's tree, with the second tab's focused node pointing at that now-disallowed pane; compute the initial tabs. | every returned tab's root is a spec-reconciled tree that also matches the one shared arrangement computed over the repaired tabs; the second tab's focused node is none; the active-tab id falls back to the first returned tab's own id when the stored active-tab id names no tab in the result — synthesized, no dedicated test in the given suite |
| git-client-projects-project-workspace-010 | update-preserves-identity | Build a workspace from a repository; update it with a repository that shares that id but has a new path and name; then update it again with a repository that has a different id but the original path and name. | after the first update, the workspace's own repository path and display name reflect the new values; after the second update, the workspace's repository is unchanged from the first update's result — the id mismatch made the second update a no-op |
| git-client-projects-project-workspace-011 | pane-number-allocation-is-monotonic | Call the pane-number allocation three times in a row on the same workspace. | the three calls return `1`, `2`, `3`, in that order, and no later call on the same instance ever returns a number already returned |
| git-client-projects-project-workspace-012 | pane-state-scoped-by-node-and-key, pane-state-failures-swallowed-and-logged-with-full-context | Write pane state for a node and key, then read it back; separately, read pane state for the same node and key against a repository the database has never recorded (an unpersisted repository, provoking a foreign-key failure). | the first pair round-trips the written value. The second read returns nothing, and one error-level log line is emitted naming the verb (`"load"`), the repository id, the node id, and the key |
| git-client-projects-project-workspace-013 | pane-state-list-json-encoded | Write a pane-state list for a node and key with two values, then read it back; then write an empty list for the same key and read it again; separately, read a pane-state list for a key that was never set. | the first read returns the two values. After writing an empty list, reading pane state for that key returns nothing and reading the list for it returns an empty list. The never-set key's list read also returns an empty list |
| git-client-projects-project-workspace-014 | project-setting-scoped-by-repo, setting-nil-deletes-row | Write a project setting to a value, then read it back; then write the same setting with no value and read it again. | the first read returns the written value. After writing no value, reading the setting returns nothing, and the underlying row for that setting no longer exists (matching "never set") |
| git-client-projects-project-workspace-015 | cache-directory-derivation | Build a workspace whose database file lives at a given path; read its cache directory without calling anything else, then check the filesystem. | the cache directory's path is a `caches/<repository id>` subdirectory of the database file's own directory; no directory exists on disk at that path yet, because reading the property performs no filesystem write |
| git-client-projects-project-workspace-016 | extension-workspace-roots-conformance | View the workspace through the extension-workspace-roots interface and read its display name and workspace root directories after adding one extra directory to the project's own file browser. | the display name equals the workspace's own display name; the workspace root directories equal the project's own file-browser directories, with the project's own directory first |
| git-client-projects-project-workspace-017 | git-client-defaults-to-shared-injectable, layout-defaults-through-fallback-chain | Construct a workspace with every optional parameter omitted. | its git client is the shared git client; its layout is the app-installed layout when one has been installed process-wide, or otherwise a placeholder-only layout of the same shape |
| git-client-projects-project-workspace-018 | stored-tabs-load-failure-signal | Not present in the given test suite; demonstrates the open question on stored-tabs-load-failure-signal. Force loading tabs from the database to throw (for example a corrupted database file or a repository id the schema rejects), capture the log for the duration, then read stored tabs. | reading stored tabs returns nothing, exactly as it would for a project that had never saved a tab — and the captured log contains no line attributable to this call, unlike vector -012's pane-state failure, which does log |

## Edge Cases

- **Null and empty input**: Reading stored tabs treats a load result
  whose tabs list is empty the same as a thrown error — both produce
  nothing (**stored-tabs-nil-when-empty-or-absent**, MUST). Reading a
  pane-state list for an unset key, or for a key holding a string that
  is not valid text or not valid JSON, returns an empty list rather than
  throwing or crashing (**pane-state-list-json-encoded**, MUST). Writing
  a pane-state list with an empty values list clears the key instead of
  writing an empty-list literal (**pane-state-list-json-encoded**,
  MUST).
- **Boundary values**: Allocating a pane number's counter starts at `1`
  and has no declared upper bound; it is a plain integer, so the
  boundary this file defines no behavior for is integer overflow, which
  the language traps on rather than wrapping (MUST, by the language's
  own arithmetic semantics — not a case this file guards against
  itself). Computing the initial tabs' stored-tab path is only reached
  when the stored tabs list is non-empty, because reading stored tabs
  already filters the empty case out, so the first-tab fallback in
  **active-tab-fallback** never indexes an empty list.
- **Concurrent access**: Every property and method here is confined to
  the main execution context (**main-thread-confinement**), so no two
  calls on one workspace instance can interleave their mutations of the
  repository, the pane-number counter, or either weak cache. Two
  separate workspace instances built over the same repository id (a
  project opened in two windows) can still race at the database layer —
  persisting tabs, writing a setting, writing pane state, and persisting
  project directories from one instance are not serialized against
  calls from another — but ordering that race, when it matters, is the
  project controller's job (see
  `agentictoolkit://cookbook/workspace/projects/project-controller`),
  not this file's; the workspace itself makes no ordering claim across
  instances.
- **Error states**: Every database-backed operation except reading
  stored tabs catches its error, logs it, and returns a safe default —
  nothing, an empty list, or nothing at all — rather than propagating it
  (**persist-tabs-swallows-failure**,
  **pane-state-failures-swallowed-and-logged-with-full-context**,
  **project-setting-scoped-by-repo**,
  **project-directories-load-failure-yields-empty**, all MUST). The one
  exception, reading stored tabs' unlogged failure path, has no log
  signal at all — see **stored-tabs-load-failure-signal**.
- **Offline or disconnected state**: Not applicable in the network sense
  — every dependency this file reads or writes (the database, the
  filesystem paths it resolves symlinks against) is local. The
  git-status-provider lookup hands out an object built on the project's
  git client, but the git subprocess calls that object goes on to make
  are that object's own concern, not this file's (see
  `agentictoolkit://cookbook/foundation/git/git-client`).
- **Cancellation and timeouts**: No operation on the workspace is
  asynchronous; every operation here is a synchronous database call, a
  synchronous cache lookup, or a pure computation, so there is no
  cancellation token, timeout, or unit of concurrent work for this file
  to honor or ignore (MUST, by the absence of any asynchronous signature
  in the source).
- **Missing file or unreachable server**: A primary/directory argument
  that does not exist on disk is not distinguished from one that does —
  resolving symlinks on a nonexistent path returns the path unchanged,
  so the file-browser-directories lookup and the git-status-provider
  lookup still mint and cache an object keyed to it
  (**file-browser-directories-cached-per-resolved-primary**,
  **git-status-provider-cached-per-resolved-directory**, MUST, by the
  absence of any existence check in either method).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| repository | a repository reference | none — required | The repository this project is; supplies the id, display name, and directory. |
| database | a database reference | none — required | The one shared database every persisted read/write in this file goes through, scoped by the repository's id. |
| layout | a layout reference (optional) | absent → the app-installed layout, or a placeholder-only layout otherwise | Which views this project may show and which arrangements of them are legal. |
| language services | a language-services reference (optional) | absent | This project's language servers; absent disables language-service support for the project. Lifecycle owned by the project window manager, not by this file. |
| git client | a git client reference | the shared git client | The git client the git-status-provider lookup builds every provider on. |

This file reads no environment variable and no settings key of its own;
the project-scoped setting/read-setting pair is a caller-defined
key/value bag this file only routes to the database, not a source of
configuration for the workspace itself.

## Deep Linking

Not applicable: this file defines no URL scheme, route, or navigation
destination.

## Localization

This file contains exactly one user-facing string literal: the default
tab title computing the initial tabs returns, hardcoded as English with
no localization mechanism.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, not looked up) | `Tab 1` | Title of the single default tab computing the initial tabs returns for a project that has never persisted any tabs. |

## Accessibility Options

Not applicable: this file renders nothing itself. It vends tab records
and per-directory model objects (the file-browser-directories value, the
git-status provider) that other view controllers render; Reduce Motion,
Increase Contrast, and Differentiate Without Color are those rendering
layers' concern.

## Feature Flags

Not applicable: this file contains no feature-flag or build-configuration
check.

## Analytics

Not applicable: this file makes no analytics or event-tracking call.

## Privacy

- **Data collected**: Local filesystem paths (the repository's own path,
  its directory, every primary/directory this file is asked to resolve
  and cache), the repository's id, and whatever a pane or the project
  window itself chooses to store under pane state and project settings —
  per the source's own documentation, the lists panes remember through
  this interface "are file paths". No credential, token, or
  network-identity data passes through this file.
- **Storage**: Everything persisted here (tabs, pane state, project
  settings, extra directories) is written to the one database this
  project was constructed with, scoped by the repository's id; see
  `agentictoolkit://cookbook/workspace/projects/project-database` and
  `agentictoolkit://cookbook/workspace/projects/project-database-layout`
  for that store's own durability guarantees. The cache directory names,
  but does not itself populate, a filesystem location beside the
  database.
- **Transmission**: This file makes no network call and sends nothing
  off the local machine; the git-status-provider lookup hands out a
  collaborator that may run local git subprocesses, not a network
  client.
- **Retention**: Data persisted through this file survives until
  explicitly overwritten or deleted through the same accessor (writing a
  setting with no value deletes rather than storing an empty value, per
  **setting-nil-deletes-row**) or until the underlying repository row
  itself is deleted, which is outside this file's own methods.

## Logging

Subsystem defaults to the app's own bundle identifier; category is this
component's name.

| Event | Level | Message |
|-------|-------|---------|
| Persisting tabs fails | error | `Failed to save project tabs: <error description>` |
| Reading pane state fails (logged as "load") | error | `Failed to load pane state (repo <repo id>, node <node id>, key <key>): <error description>` |
| Writing pane state fails (logged as "save") | error | `Failed to save pane state (repo <repo id>, node <node id>, key <key>): <error description>` |
| Pruning nested pane state fails (logged as "prune", key `"*"`) | error | `Failed to prune pane state (repo <repo id>, node <node id>, key *): <error description>` |
| Reading a project setting fails | error | `Failed to load project setting: <error description>` |
| Writing a project setting fails | error | `Failed to save project setting: <error description>` |
| Reading the project's extra directories fails | error | `Failed to load project directories: <error description>` |
| Writing the project's extra directories fails | error | `Failed to save project directories: <error description>` |

Loading tabs from the database throwing inside reading stored tabs
produces no log line at all — see the open question on
stored-tabs-load-failure-signal.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWorkspace.swift`,
  importing `AppKit`, `AgenticToolkitCore`, `AgenticToolkitCoreUI`,
  `AgenticToolkitCoreMacOS`, and `os`. It calls no AppKit UI API directly —
  it is a plain `@MainActor` model object holding a `GitRepo`, a
  `ProjectDatabase`, a `ComposableTabsLayout`, and two weak object caches. A
  SwiftUI host would still need this exact object feeding a tab-bar view, as
  an `@Observable`/`ObservableObject`-wrapped dependency, not a `View` or
  `Scene` itself. `ProjectWorkspace` is declared `@MainActor` and declares
  no `Sendable` conformance of its own, so every stored property and method
  is confined to the main actor by that declaration alone.
- **Compose**: Model `ProjectWorkspace` as a plain class confined to a single
  coroutine dispatcher (Compose's main-thread dispatcher, mirroring
  `@MainActor`), holding `repo` and `layout` as `MutableState` so dependent
  composables recompose on `update(repo:)`. Reproduce the two `WeakCache`s
  with a `WeakHashMap`/`java.lang.ref.WeakReference`-backed map keyed by the
  resolved directory path, evicted the same way — lazily, on next lookup,
  rather than by an explicit listener. Route every persisted read/write
  (`storedTabs`, `paneState`, `setting`, `projectDirectories`) through a
  coroutine-based `ProjectDatabase` port that mirrors this file's
  swallow-and-log convention on every path except the one this recipe flags
  as an open question.
- **React/Web**: There is no local filesystem worktree or SQLite file to
  scope this object to on the web; a browser-hosted project workspace would
  keep `repo`/tabs/pane-state/settings as component state populated from and
  persisted through a server-side API standing in for `ProjectDatabase` (see
  `agentictoolkit://cookbook/workspace/projects/project-database`), and would
  reproduce the two weak, directory-keyed caches with a JavaScript `WeakMap`
  (optionally paired with `FinalizationRegistry` to detect eviction) keyed by
  a normalized directory identifier, since JavaScript has no
  `resolvingSymlinksInPath()` equivalent of its own.
- **AppKit / UIKit**: The source already is this tier — a plain
  `@MainActor`-confined `NSObject`-free model class with no `NSViewController`
  of its own. A UIKit (iOS) port carries the tab-tree, pane-state, settings,
  and directory-cache logic unchanged; it would still need its own
  `FileBrowserDirectories`/`GitStatusProvider`-equivalent collaborators, and,
  per the multi-checkout note in
  `agentictoolkit://cookbook/workspace/projects/project-controller`, iOS
  sandboxing makes exposing more than one linked worktree under one project
  an unusual arrangement to design a browser for.
- **WinUI 3**: Port `ProjectWorkspace` as a plain C# class with no interface
  requiring thread-affinity of its own, touched only from the UI thread
  (`DispatcherQueue`) by convention — the same discipline
  `agentictoolkit://cookbook/workspace/projects/branch-controller`'s WinUI
  port assumes for `@MainActor`. Reproduce the two `WeakCache`s with a
  `Dictionary<string, WeakReference<T>>` (or `ConditionalWeakTable`) keyed by
  a normalized, reparse-point-resolved path (`Path.GetFullPath`/
  `FileInfo.FullName`, mirroring `resolvingSymlinksInPath()`), pruning dead
  entries the same way — lazily, on the next lookup for any key, not on a
  timer. Reproduce **directory-addition-fans-out-to-every-live-sibling** by
  iterating every live entry in that table and calling an equivalent
  `ReplaceAdditional` on each, and reproduce
  **pane-state-list-json-encoded** with `System.Text.Json` in place of
  `JSONEncoder`/`JSONDecoder`. Route every persisted accessor
  (`storedTabs`/`saveTabs`, `paneState`/`setPaneState`, `setting`/
  `setSetting`, `loadProjectDirectories`/`saveProjectDirectories`) through
  the same SQLite-backed port `agentictoolkit://cookbook/workspace/projects/project-database`
  and `agentictoolkit://cookbook/workspace/projects/project-database-layout`
  describe, keeping this file's swallow-and-log convention on every path
  except the one flagged as an open question above.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWorkspace.swift` |

## Design Decisions

**Decision**: `fileBrowserDirectoriesByPrimary` and `gitStatusProvidersByRoot`
hold their values weakly (`WeakCache`) instead of strongly.
**Rationale**: The doc comment on `WeakCache` states the failure mode this
avoids directly: holding values strongly meant a project "accumulated one
`FileBrowserDirectories` and one `GitStatusProvider` for every directory
anything had *ever* asked about — every worktree visited, every checkout
opened and closed again — for as long as the project stayed open," each one
"still observing a directory with nothing left on screen to show for it."
Weak values end an entry with its last holder without weakening the
invariant the cache exists for (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `gitStatusProvider(forDirectory:)` mints and caches its
`GitStatusProvider`s on `ProjectWorkspace`, not on `BranchController`.
**Rationale**: The doc comment explains the ordering bug this sidesteps: a
pane is built while the window installs its stored tabs, "before the first
`git worktree list` has returned and so before any `BranchController`
exists"; a provider resolved through the branch controllers "therefore
answered `nil` for every pane the window opened with," and because
`FileBrowserViewController` "latches what it is handed at init and never asks
again," those panes ran a private provider of their own for the rest of the
session while the `Refresh Status` command reached a different object.
Minting at the project level removes the ordering question rather than
moving it (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `projectDirectoriesDidChange(_:from:)` refreshes every other
live `FileBrowserDirectories` before returning, rather than letting each
browser reload lazily on its own next save.
**Rationale**: The doc comment states the bug this closes: each browser used
to write "the *whole* list back on any change," from its own stale snapshot,
so "the second one to save wrote its stale copy over the first one's addition
and the folder vanished from disk with no error." Refreshing every sibling
immediately, before anything else can save, keeps every open browser's copy
of the one project-wide list current (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `projectDirectoriesDidChange(_:from:)` re-adds `primary` to the
merged list when the stored list names it but the browser's own `urls` do
not.
**Rationale**: The doc comment explains why this merge is necessary: "an
object cannot represent its own primary" — a `FileBrowserDirectories` filters
its own primary out of `additional` because it is already shown and not
removable. If a user added a worktree's folder as an extra root of the main
checkout and then opened that worktree in its own tab, the worktree's own
browser would otherwise silently delete that entry on its next save
(`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `cacheDirectoryURL` is a pure computation that never creates the
directory it names.
**Rationale**: The doc comment states the reasoning directly: every caller so
far only names the folder (the file browser excludes it from the tree), and
"a getter that quietly makes a directory on disk … for every project, whether
or not anything ever caches into it … is a side effect nobody reading
`project.cacheDirectoryURL` would expect." Whoever writes there first creates
it (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: The `chrome.` prefix on `paneState`/`setPaneState` keys is
reserved by documentation only; `ProjectWorkspace` adds no runtime check that
a caller's key avoids it.
**Rationale**: The doc comment gives the reasoning: "Nothing checks this: the
prefix is what keeps chrome off content's keys, and this sentence is what
keeps content off chrome's. A check would have to let the one caller that is
*supposed* to write the prefix through, which buys less than the sentence
does." (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `setSetting(_:to:)` treats a `nil` value as a delete rather than
storing an empty or null row.
**Rationale**: The doc comment states this directly: "so 'never set' and 'set
back to the default' are the same state and neither accumulates"
(`ProjectWorkspace.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | partial | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | partial | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

Notes: separation-of-concerns passes because `ProjectWorkspace` owns exactly
the tab tree, the pane-state/setting bag, the extra-directory list, and the
lifecycle of its two per-directory object caches, while delegating every
actual read and write to `ProjectDatabase`, all tab-arithmetic to
`ComposableTabsLayout.spec` and `ProjectTabReconciler`, and all rendering to
whatever hosts a `TabRecord` — it constructs no view of its own. unit-test-
coverage is partial because `ProjectWorkspaceTabsTests.swift` exercises
`storedTabs()`'s nil-before-persist and round-trip paths, both weak caches'
per-key identity and eviction, and the directory-addition fan-out and
primary-re-add merges — but has no test for `initialTabs()`'s spec-repair,
arrangement-reshape, or stale-focus-clearing paths, for `update(repo:)`'s id
guard, for `allocatePaneNumber()`, or for any pane-state/setting failure path
(vectors -008 through -014 and -016 through -018 above are synthesized to
describe what such tests would assert). explicit-error-handling is partial
because every failing database call except `storedTabs()` is caught and
logged; `storedTabs()`'s bare `try?` lets its error vanish with no log line
at all (the open question on stored-tabs-load-failure-signal).
graceful-degradation passes because every failure path here degrades to a
safe, documented default — `nil`, `[]`, or the previous cache value — rather
than crashing or propagating. state-recovery is partial for the same reason
explicit-error-handling is: `initialTabs()` is this project's state-recovery
path after a restart, and a transient `loadTabs` failure on that path is
currently indistinguishable from a project that never saved anything, so
recovery silently resets to one default tab instead of surfacing the
failure. data-integrity is partial because `paneStateList` treats an unset
key and a key holding corrupt JSON identically (both `[]`), so corrupt pane
state is never detected or reported as such, only masked as "unset."

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
