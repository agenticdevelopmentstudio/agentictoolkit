---
id: 92f11498-2cb2-4b04-92b9-560d9f2de6ee
title: BranchController
domain: agentictoolkit://recipes/git-client-projects-branch-controller
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Owns one project checkout: its live branch, its per-(tab, edge) tab panes,
  and the three checkout-namespaced commands a command palette and context menu act
  on it through.'
platforms:
- swift
- macos
tags:
- git
- tabs
- checkout
- branch
- command-palette
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/file-system-git
- agentictoolkit://recipes/tab-pane-view-controller
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/BranchController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectCheckout.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitClient.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabPane/TabPaneDataSource.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabPane/TabPaneDelegate.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/Edge.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabPane/TabPaneStatusSymbol.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/AppShell/AppCommand.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/AppShell/ClosureMenuItemTarget.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/BranchControllerTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# BranchController

## Overview

`BranchController` (`BranchController.swift`) owns one `ProjectCheckout`: its
`GitStatusProvider`, its live current branch, the tab panes that describe it,
and the three `AppCommand`s a command palette or a pane's context menu act on
it through. It is vended once per checkout by `ProjectController` and reused
across branch switches of that same directory; per its own doc comment, it
"never touches the window." It conforms to `TabPaneDataSource` (so a
`TabPaneViewController` can render the checkout's agent, session, directory,
branch and summary without computing any of it itself) and `TabPaneDelegate`
(so the same controller supplies the pane's context menu). It is `@MainActor`
and holds no `Sendable` conformance of its own — every property and method is
confined to the main actor by that declaration alone.

## Behavioral Requirements

- **checkout-ownership**: `BranchController` MUST hold exactly one
  `ProjectCheckout` (`checkout`), one `GitStatusProvider` (`statusProvider`),
  and the mutable `currentBranch: String?` for that checkout, and MUST NOT
  read or mutate any other checkout's state (`BranchController.swift` lines
  9-11).
- **main-actor-isolation**: `BranchController` MUST be declared `@MainActor`
  and MUST NOT declare `Sendable` conformance; every stored property
  (`checkout`, `statusProvider`, `currentBranch`, `gitClient`, `panes`) and
  every method is therefore confined to the main actor by that declaration,
  not by any lock the type defines itself (`BranchController.swift` line 7).
- **injected-dependencies-no-defaults**: `init(checkout:gitClient:statusProvider:)`
  MUST accept `checkout`, `gitClient`, and `statusProvider` as required
  parameters with no default value for any of them, and MUST NOT construct a
  `GitClient` or `GitStatusProvider` internally — per the doc comment, a
  provider minted inside this initializer "could never be the one" a
  checkout's panes were already given before the controller exists, which
  would leave one checkout served by two status providers
  (`BranchController.swift` lines 16-24).
- **initial-branch-from-checkout**: `init` MUST set `currentBranch` to
  `checkout.branch` at construction time, before any call to `refresh()`
  (`BranchController.swift` lines 25-28).
- **pane-identity-per-tab-per-edge**: `makeTabPane(edge:tabID:)` MUST return
  the same `TabPaneViewController` instance for every call made with the same
  `edge` and `tabID` pair on one controller, found by a linear scan of
  `panes.allObjects` matching both `edge` and `tabID`, and MUST call
  `reload()` on that existing pane before returning it
  (`BranchController.swift` lines 47-51).
- **pane-created-once-per-tab-per-edge**: `makeTabPane(edge:tabID:)` called
  with an `(edge, tabID)` pair not already in `panes` MUST construct exactly
  one new `TabPaneViewController(edge:tabID:)`, and a different `edge` or a
  different `tabID` MUST always be treated as a distinct pane
  (`BranchController.swift` lines 47, 52-57).
- **pane-registration-on-creation**: A newly constructed pane MUST have its
  `dataSource` and `delegate` both set to the owning `BranchController`, MUST
  be added to `panes`, and MUST have `reload()` called on it before
  `makeTabPane(edge:tabID:)` returns it (`BranchController.swift` lines
  52-57).
- **weak-pane-table**: `panes` MUST be an `NSHashTable<TabPaneViewController>`
  constructed with `.weakObjects()`, so a pane released by every other owner
  MUST be dropped from `panes` without `BranchController` ever calling an
  explicit unregister method (`BranchController.swift` line 14).
- **display-name-derivation**: `displayName` MUST return `currentBranch` when
  it is non-nil, and otherwise MUST return `checkout.directory.lastPathComponent`,
  computed fresh from the live `currentBranch` on every access rather than
  from any value captured when the controller was built
  (`BranchController.swift` lines 70-72).
- **refresh-updates-branch-on-success**: When `gitClient.currentBranch(in:
  checkout.directory)` returns without throwing, `refresh()` MUST assign that
  result to `currentBranch`, including replacing a non-nil `currentBranch`
  with `nil` when the checkout is now a detached HEAD
  (`BranchController.swift` lines 83-85).
- **refresh-preserves-branch-on-failure**: When `gitClient.currentBranch(in:)`
  throws, `refresh()` MUST leave `currentBranch` at its previous value; the
  error MUST NOT be rethrown, logged, or otherwise surfaced by this method
  (`BranchController.swift` lines 83-88).
- **refresh-always-reloads-panes**: `refresh()` MUST call `reload()` on every
  pane in `panes.allObjects` after its branch-read attempt, regardless of
  whether that attempt succeeded, threw, or `panes` was empty
  (`BranchController.swift` lines 89-91).
- **commands-computed-per-access**: `commands` MUST be computed fresh on
  every access as an array of exactly three `AppCommand` values — Refresh
  Status, Reveal in Finder, Copy Path, in that order — rather than cached
  from a previous access (`BranchController.swift` lines 111-146).
- **command-id-namespacing**: Every command id MUST be
  `"branch.action.<verb>.\(checkout.identifier)"` (`refreshStatus`,
  `revealInFinder`, or `copyPath`), so that two checkouts — including two
  worktrees of the same repository — MUST NOT produce colliding command ids
  (`BranchController.swift` lines 112, 117, 131, 138).
- **command-category-carries-checkout-name**: Every command's `category`
  MUST be `"Branch — \(displayName)"`, evaluated at the time `commands` is
  accessed, so a palette listing commands from multiple checkouts MUST show
  each checkout's live name (`BranchController.swift` lines 114, 119, 133,
  140).
- **command-title-excludes-checkout-name**: A command's `title` (`"Refresh
  Status"`, `"Reveal in Finder"`, `"Copy Path"`) MUST NOT include the
  checkout's name or branch; per the doc comment, the title is what a
  per-pane context menu renders alone, where the pane itself already
  identifies the checkout (`BranchController.swift` lines 99-106, 118, 132,
  139).
- **refresh-status-command-effect**: Invoking the Refresh Status command
  MUST call `statusProvider.refresh()` without awaiting or otherwise
  observing its effect, and MUST separately start an unstructured `Task`
  that awaits `self?.refresh()`; both calls MUST capture `self` weakly
  (`BranchController.swift` lines 120, 127-128).
- **reveal-in-finder-command-effect**: Invoking the Reveal in Finder command
  MUST call `NSWorkspace.shared.activateFileViewerSelecting([directory])`,
  where `directory` is `checkout.directory` captured by value when `commands`
  was accessed, not read through `self` at invocation time
  (`BranchController.swift` lines 113, 130-136).
- **copy-path-command-effect**: Invoking the Copy Path command MUST call
  `NSPasteboard.general.clearContents()` and then
  `NSPasteboard.general.setString(directory.path, forType: .string)`, using
  the same value-captured `directory` (`BranchController.swift` lines 113,
  137-144).
- **captured-directory-outlives-controller**: Because Reveal in Finder and
  Copy Path capture `directory` by value rather than through `self`, MUST NOT
  fail or act on the wrong directory when invoked after the owning
  `BranchController` has been deallocated or its commands unregistered — per
  the doc comment this is deliberate, "so an unregister that races a menu
  already on screen still does the right thing rather than silently nothing"
  (`BranchController.swift` lines 108-110, 113, 130-144).
- **data-source-agent-name-fixed**: `tabPaneAgentName(_:)` MUST always
  return the literal string `"Claude"`, regardless of the pane or the
  checkout — a placeholder documented as pending "the document-model work
  that follows the vsc-plugins branch" (`BranchController.swift` lines
  150-153).
- **data-source-model-name-nil**: `tabPaneModelName(_:)` MUST always return
  `nil` (`BranchController.swift` line 154).
- **data-source-status-symbols-fixed**: `tabPaneStatusSymbols(_:)` MUST
  always return `[.idle]` (`BranchController.swift` line 155).
- **data-source-session-name-derivation**: `tabPaneSessionName(_:)` MUST
  return `displayName` (`BranchController.swift` line 156).
- **data-source-working-directory-fixed**: `tabPaneWorkingDirectory(_:)`
  MUST return `checkout.directory` unchanged for the controller's lifetime
  (`BranchController.swift` line 157).
- **data-source-branch-passthrough**: `tabPaneBranch(_:)` MUST return the
  live `currentBranch` (`BranchController.swift` line 158).
- **data-source-summary-nil**: `tabPaneSummary(_:)` MUST always return `nil`
  (`BranchController.swift` line 159).
- **context-menu-built-from-commands**: `tabPane(_:contextMenuFor:)` MUST
  build one `NSMenuItem` per entry in `commands`, in the same order, each
  titled with that command's `title` (`BranchController.swift` lines 173-193).
- **context-menu-run-discards-arguments-and-result**: Each menu item's action
  MUST invoke the corresponding command's `run` with an empty argument array
  (`command.run([])`) and MUST discard the returned value
  (`BranchController.swift` lines 176-181).
- **context-menu-target-retention**: Each menu item's `target` MUST be a
  `ClosureMenuItemTarget` wrapping that command, and that same target MUST
  also be assigned to the item's `representedObject`, so it stays retained
  for the item's lifetime despite `NSMenuItem.target` being a weak reference
  (`BranchController.swift` lines 163-172, 180-190).
- **context-menu-item-enablement-via-validation**: Each menu item's enabled
  state MUST be governed by the wrapped command's `isEnabled` through
  `ClosureMenuItemTarget.validateMenuItem(_:)` — the path AppKit's
  `NSMenu.autoenablesItems` consults — MUST NOT be set directly on
  `NSMenuItem.isEnabled` (`BranchController.swift` lines 163-167, 182).

## Appearance

Not applicable — this is a checkout-owning controller, not a visual
component.

## States

Not applicable — this is a checkout-owning controller, not a visual
component. Its one runtime state machine — a checkout's live branch, tracked
in `currentBranch` and re-read by `refresh()` — is covered under Behavioral
Requirements (**refresh-updates-branch-on-success**,
**refresh-preserves-branch-on-failure**), not here.

## Accessibility

Not applicable — this is a checkout-owning controller, not a visual
component. The accessibility of the panes and menu items it supplies content
to is the concern of `TabPaneViewController` and AppKit's `NSMenu`, neither
of which this file renders itself.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-branch-controller-001 | pane-registration-on-creation, data-source-agent-name-fixed, data-source-model-name-nil, data-source-session-name-derivation, data-source-working-directory-fixed, data-source-branch-passthrough, data-source-summary-nil, display-name-derivation | `makeTabPane(edge: .left, tabID: UUID())` on a controller built from `ProjectCheckout(directory: tempRoot, branch: "main", isMain: true)`, then `pane.reload()` (`testAVendedPaneShowsThePlaceholdersAndTheCheckout`). | `agentLabel` reads `"Claude"`; `sessionLabel` and `branchLabel` read `"main"`; `directoryLabel` ends with `tempRoot`'s last path component; `summaryLabel.isHidden` is `true`; `pane.dataSource === controller` and `pane.delegate === controller`. |
| git-client-projects-branch-controller-002 | pane-identity-per-tab-per-edge, pane-created-once-per-tab-per-edge | Call `makeTabPane(edge: .left, tabID: tab)` twice with the same `tab`, then once more with `edge: .right, tabID: tab` and once with `edge: .left, tabID: UUID()` (`testAskingTwiceForTheSameTabsPaneGivesBackTheSameOne`). | The first two calls return the identical instance (`first === second`); the `.right`-edge call and the new-`tabID` call each return a different instance from `first`. |
| git-client-projects-branch-controller-003 | initial-branch-from-checkout, refresh-updates-branch-on-success, refresh-always-reloads-panes, data-source-branch-passthrough | Init a git repo on branch `feature` with one commit; build a controller with `checkout.branch == nil`; make a pane; call `await controller.refresh()` (`testRefreshReadsTheBranchFromGitAndReloadsPanes`). | `controller.currentBranch == "feature"`; the pane's `branchLabel` and `sessionLabel` both read `"feature"`. |
| git-client-projects-branch-controller-004 | command-id-namespacing, command-category-carries-checkout-name | Read `controller.commands.map(\.id)` and `.category` for a checkout with `branch: "main"` and `identifier == suffix` (`testCommandsAreNamespacedByCheckout`). | Ids equal `["branch.action.refreshStatus.\(suffix)", "branch.action.revealInFinder.\(suffix)", "branch.action.copyPath.\(suffix)"]`; every command's `category` equals `"Branch — main"`. |
| git-client-projects-branch-controller-005 | command-id-namespacing, command-category-carries-checkout-name, command-title-excludes-checkout-name | Build two controllers on two checkouts (`main`/`tempRoot`, `feature`/`otherRoot`); combine `main.commands + feature.commands` into `"\(title)\t\(category)"` rows (`testCommandRowsAreDistinctAcrossTwoCheckouts`). | All 6 rows are pairwise distinct (`Set(rows).count == 6`); `main`'s three rows all carry category `"Branch — main"` and `feature`'s all carry `"Branch — feature"`. |
| git-client-projects-branch-controller-006 | context-menu-built-from-commands, context-menu-target-retention | Call `controller.tabPane(pane, contextMenuFor: rightMouseDownEvent)` (`testTheContextMenuListsTheCommands`). | `menu.items.map(\.title) == ["Refresh Status", "Reveal in Finder", "Copy Path"]`; every item's `target` is non-nil after the call returns (surviving past the point `NSMenuItem.target`'s weak reference would otherwise have released it). |
| git-client-projects-branch-controller-007 | refresh-preserves-branch-on-failure | Construct a controller whose `checkout.directory` does not exist (so `gitClient.currentBranch(in:)` throws `GitClientError.launchFailed` or `.commandFailed`); set `currentBranch` to `"main"` beforehand; call `await refresh()`. | `currentBranch` is still `"main"`; no error propagates out of `refresh()`. |
| git-client-projects-branch-controller-008 | injected-dependencies-no-defaults, checkout-ownership | Construct `BranchController(checkout:gitClient:statusProvider:)` twice with two distinct, pre-built `GitStatusProvider` instances. | `controller.statusProvider` is reference-identical to the exact instance passed to that controller's initializer, never a new one built internally. |
| git-client-projects-branch-controller-009 | weak-pane-table | Call `makeTabPane(edge:tabID:)`, let the returned pane go out of scope with no other strong reference held, then trigger a call that iterates `panes.allObjects` (e.g. `refresh()`). | The released pane's `reload()` is not invoked; `panes.allObjects.count` no longer includes it. |
| git-client-projects-branch-controller-010 | commands-computed-per-access, refresh-status-command-effect | Register a fake `statusProvider` and invoke the Refresh Status command's `run([])`. | `statusProvider.refresh()` is called synchronously (before `run` returns), and `controller.refresh()` is additionally invoked asynchronously via the started `Task`. |
| git-client-projects-branch-controller-011 | reveal-in-finder-command-effect, copy-path-command-effect, captured-directory-outlives-controller | Read `commands`, discard the strong reference to the `BranchController`, then invoke the captured Reveal in Finder and Copy Path closures. | `NSWorkspace.shared.activateFileViewerSelecting([directory])` and the pasteboard write both still target the original `checkout.directory`, even though the controller that vended the commands is gone. |
| git-client-projects-branch-controller-012 | context-menu-run-discards-arguments-and-result, context-menu-item-enablement-via-validation | Build the context menu for a checkout whose Refresh Status command has `isEnabled: { false }`; invoke `validateMenuItem` on that item. | `validateMenuItem` returns `false` for that item and `true` for the other two; invoking the item's action still calls `command.run([])` with an empty array (menu construction does not gate on `isEnabled` itself). |

## Edge Cases

- **Null and empty input**: A checkout constructed with `branch: nil` (a
  detached-HEAD or newly discovered worktree) leaves `currentBranch` `nil`
  until the first successful `refresh()`; `displayName` falls back to
  `checkout.directory.lastPathComponent` for exactly that period (MUST, see
  **initial-branch-from-checkout**, **display-name-derivation**).
  `makeTabPane(edge:tabID:)` called before any pane exists always takes the
  "create" branch — there is no null/empty case to special-case, since
  `panes.allObjects` starts empty and the `first(where:)` scan simply finds
  nothing (MUST, see **pane-created-once-per-tab-per-edge**).
- **Boundary values**: `commands` always returns exactly three entries, never
  zero or a variable count — there is no configuration that adds or removes
  a command (MUST, see **commands-computed-per-access**). `panes` may hold
  zero entries (a checkout with no open tab yet); `refresh()`'s
  `for pane in panes.allObjects` loop over zero entries is not an error, it
  simply reloads nothing (MUST, see **refresh-always-reloads-panes**).
- **Concurrent access**: Every mutation of `currentBranch` and `panes` is
  confined to the main actor by `@MainActor`, so no interleaving can observe
  a torn write (MUST, see **main-actor-isolation**). `BranchController.refresh()`
  itself has no coalescing, generation counter, or in-flight guard of any
  kind — unlike its sibling `GitStatusProvider.refresh()` (see
  `agentictoolkit://recipes/file-system-git`), which explicitly coalesces
  overlapping calls into at most one queued follow-up and discards a stale
  response with a generation check. Two overlapping
  `BranchController.refresh()` calls (for example, two rapid Refresh Status
  invocations) each independently `await gitClient.currentBranch(in:)` and
  each independently assign `currentBranch` and reload every pane on
  completion; whichever call's git subprocess returns last wins, with no
  rule preferring the call that was *started* last over one that merely
  finished last; see the open question on refresh-ordering.
- **refresh-ordering**: NEEDS REVIEW: Not implemented in source. There is no ordering or coalescing rule for overlapping `refresh()` calls on one `BranchController`: whichever call's `gitClient.currentBranch(in:)` returns last sets `currentBranch` and reloads the panes, even if it was started first. `BranchControllerTests.swift` exercises only a single `refresh()` call; the app's worktree-scan and command-dispatch call sites, or a stress test issuing overlapping `refresh()` calls, would settle whether this is reachable in practice.
- **Error states**: `GitClientError.executableNotFound`, `.launchFailed`,
  `.timedOut`, and `.commandFailed` are not distinguished from one another
  by `refresh()`; every one is caught by the same unqualified `catch` and
  produces the same outcome — `currentBranch` unchanged, every pane still
  reloaded (MUST, see **refresh-preserves-branch-on-failure**,
  **refresh-always-reloads-panes**). The caller of the Refresh Status
  command has no way to learn that the branch read specifically failed,
  as distinct from succeeding with an unchanged value; the failure's only
  record is `GitCommandLog`, written by `GitClient.execute` (a collaborator,
  not this file — see `agentictoolkit://recipes/file-system-git`'s sibling
  `GitClient.swift`).
- **Offline or disconnected state**: Not applicable in the network sense —
  `gitClient.currentBranch(in:)` runs `git rev-parse --abbrev-ref HEAD`
  against the local working tree only; it makes no request to a remote and
  has no notion of connectivity. An unreadable or removed local `checkout.directory`
  is handled identically to any other `GitClientError` above.
- **Cancellation and timeouts**: The `Task { [weak self] in await
  self?.refresh() }` started by the Refresh Status command is unstructured;
  its handle is discarded, so nothing can cancel it once started
  (`BranchController.swift` line 128). If `self` has already been
  deallocated by the time that task runs, `self?.refresh()` is a no-op; if
  `self` is still alive, the weak-to-strong promotion inside the `await`
  expression keeps the controller alive for the duration of that one call
  (MUST, see **refresh-status-command-effect**). `GitClientError.timedOut`
  reaches `refresh()` through the same generic catch as every other error
  (see Error states above); `BranchController` applies no timeout of its
  own.
- **Missing file or unreachable server**: A `checkout.directory` that has
  been deleted (for example by `git worktree remove` running concurrently
  with a pending refresh) surfaces only as whatever `GitClientError`
  `gitClient.currentBranch(in:)` produces for a missing directory, handled
  identically to Error states above (MUST). Neither
  **reveal-in-finder-command-effect** nor **copy-path-command-effect**
  checks that `directory` still exists before acting on it; a stale Reveal
  in Finder or Copy Path invocation is forwarded to AppKit/the pasteboard
  unchanged (MUST, see **captured-directory-outlives-controller**) — it is
  `ProjectController`'s job, not this file's, to unregister a checkout's
  commands once its directory is gone (`ProjectController.swift`'s
  `syncBranchControllers()`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `checkout` (parameter to `init`) | `ProjectCheckout` | none — required | The checkout this controller owns; fixed for the instance's lifetime, though the checkout it names may switch branches without a new controller being built. |
| `gitClient` (parameter to `init`) | `GitClient` | none — required, no internal fallback | Injected by the caller (`ProjectController.workspace.gitClient`); `BranchController` never falls back to `GitClient.shared` itself. |
| `statusProvider` (parameter to `init`) | `GitStatusProvider` | none — required, no internal fallback | Injected by the caller via `ProjectWorkspace.gitStatusProvider(forDirectory:)`, so every consumer of one checkout's status shares one provider. |

`BranchController.swift` reads no environment variable and no settings key
directly; git executable path, timeout, and submodule handling are
`GitClientConfiguration` concerns reached only indirectly through the
injected `gitClient`.

## Deep Linking

Not applicable: `BranchController.swift` defines no URL scheme, route, or
navigation destination.

## Localization

`BranchController.swift` produces its user-facing strings as Swift string
literals with no localization key or lookup mechanism:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal) | `Claude` | `tabPaneAgentName(_:)` placeholder agent name (line 153). |
| (none — literal) | `Refresh Status` | Command title (line 118). |
| (none — literal) | `Reveal in Finder` | Command title (line 132). |
| (none — literal) | `Copy Path` | Command title (line 139). |
| (none — literal) | `Branch — \(displayName)` | Command category, with the checkout's live name interpolated (line 114). |

## Accessibility Options

Not applicable: `BranchController.swift` renders nothing itself — it hands
labels, symbols, and menu items to `TabPaneViewController` and AppKit's
`NSMenu`. Reduce Motion, Increase Contrast, and Differentiate Without Color
are concerns of those rendering layers, with nothing in this file to opt
into or out of.

## Feature Flags

Not applicable: `BranchController.swift` contains no feature-flag or
build-configuration check.

## Analytics

Not applicable: `BranchController.swift` makes no analytics or
event-tracking call.

## Privacy

Not applicable: the only data this file touches is a local filesystem path
(`checkout.directory`) and a git branch name, both already visible to the
user in the project window and command palette; it reads, stores, or
transmits no credential, token, or personal data.

## Logging

`BranchController.swift` makes no logging call of its own — no `Logger`,
`os.Logger`, or `print` appears anywhere in the file. The one error this
file swallows (`refresh()`'s `catch`, line 87) is recorded by a different
component, `GitCommandLog` via `GitClient.execute`'s unconditional recording
(see `agentictoolkit://recipes/file-system-git`'s sibling `GitClient.swift`),
not logged a second time here.

| Event | Level | Message |
|-------|-------|---------|
| (none) | — | This file emits no log messages. |

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/BranchController.swift`,
  built on `AppKit` (`NSHashTable`, `NSMenu`, `NSMenuItem`, `NSWorkspace`,
  `NSPasteboard`) and `AgenticToolkitCore` (`ProjectCheckout`, `GitClient`,
  `GitStatusProvider`, `AppCommand`, `TabPaneDataSource`/`TabPaneDelegate`,
  `Edge`, `TabPaneStatusSymbol`, `ClosureMenuItemTarget`). It uses no
  SwiftUI API; a SwiftUI-hosted pane would still need an `NSViewController`
  bridge (or its own `TabPaneDataSource`-equivalent) to reach this
  controller's data.
- **Compose**: Model `BranchController` as a plain class (or, given its
  `@MainActor` confinement, a class annotated for Compose's main-thread
  dispatcher) holding `checkout`, `gitClient`, `statusProvider`, and a
  mutable `currentBranch` `State`/`MutableState`. Replace the weak
  `NSHashTable` of panes with a `MutableList` of weakly-held pane view
  models (Kotlin has no built-in weak collection; a `WeakHashMap`-backed
  wrapper is the closer match) keyed by `(edge, tabID)`. Represent the three
  commands as a `List` of a small `AppCommand`-equivalent data class, and
  build a context menu (`DropdownMenu`) from that list the same way.
- **React/Web**: There is no filesystem worktree or native context menu on
  the web, so this component has no direct web port; a browser-hosted
  equivalent (a project-switcher panel backed by a server-side git service)
  would model `checkout`/`currentBranch` as component state, `commands` as
  an array of `{ id, title, category, run }` objects rendered into a
  context-menu component, and `refresh()` as an async function that awaits
  a server call rather than a local subprocess.
- **AppKit / UIKit**: The source already is AppKit; a UIKit (iOS) port has
  no direct equivalent for `NSMenu`-based context menus (`UIMenu` is the
  closer analogue) or for `NSWorkspace.activateFileViewerSelecting` (no
  Finder-equivalent exists on iOS) or `NSPasteboard` (`UIPasteboard`
  instead); the branch-tracking and pane-identity behavior ports unchanged.
- **WinUI 3**: Port `BranchController` as a plain C# class holding
  `ProjectCheckout Checkout`, the injected git client and status provider,
  and a `string? CurrentBranch` property, with no interface requiring
  thread-affinity of its own — mirror `@MainActor` confinement by only ever
  touching this object from the UI thread (`DispatcherQueue`), the same
  discipline `GitStatusProvider`'s WinUI port already assumes (see
  `agentictoolkit://recipes/file-system-git`). Replace `NSHashTable<TabPaneViewController>.weakObjects()`
  with a `List<WeakReference<TabPaneViewController>>` (or a
  `ConditionalWeakTable`), pruning dead entries on each scan since .NET has
  no automatic weak-collection eviction. Represent the three commands as
  `ICommand` (or a small `AppCommand`-equivalent record with `Id`, `Title`,
  `Category`, `Func<Task> Run`) and build the pane's context menu from a
  `MenuFlyout` populated the same way `tabPane(_:contextMenuFor:)` populates
  an `NSMenu` — no `ClosureMenuItemTarget`/weak-`target` retention concern
  exists in WinUI, since a `MenuFlyoutItem.Command` is strongly held by the
  flyout. Use `Windows.ApplicationModel.DataTransfer.Clipboard.SetContent`
  for Copy Path and `Windows.Storage.Pickers` or `Process.Start("explorer.exe",
  "/select,\"" + path + "\"")` for the Reveal-in-Finder equivalent. Read the
  current branch with `HttpClient`-free process invocation
  (`System.Diagnostics.Process` running `git`) via the same single-door
  client `GitClient`'s WinUI port already centralizes, and mirror the
  detached-HEAD-vs-error distinction exactly: a successful call that
  resolves to no branch name MUST clear `CurrentBranch`, while a thrown
  exception MUST leave it untouched.

## Design Decisions

**Decision**: `displayName` reads from `currentBranch`, which is re-read on
every `refresh()`, rather than from the `checkout` snapshot the controller
was constructed with.
**Rationale**: Per the doc comment, `checkout` is a `let` that "never
moves" — `identifier` depends on that being true, so a checkout keeps its
identity across branch switches — but a label read off that frozen snapshot
would go on naming whichever branch was checked out when the window opened.
Everything the user reads (the command palette's category, a pane's session
name) needs the live value instead (`BranchController.swift` lines 60-72).
**Approved**: pending

**Decision**: `refresh()` treats a successful call that resolves to `nil`
(detached HEAD) as replacing `currentBranch`, but treats a thrown error as
leaving `currentBranch` untouched — the two are not folded into one `try?`.
**Rationale**: The doc comment states this directly: "a detached HEAD is an
*answer*... a thrown error is not an answer — git could not be asked, so the
last known branch stays put," matching the policy `GitStatusProvider` applies
to a failed status; folding both into `try?` "kept a stale branch name on
screen forever, because the two cases are indistinguishable once the error
is discarded" (`BranchController.swift` lines 74-88).
**Approved**: pending

**Decision**: `makeTabPane(edge:tabID:)` returns the existing pane for a
given `(edge, tabID)` rather than minting a new `TabPaneViewController` on
every call.
**Rationale**: The doc comment explains the cost this avoids: "asking twice
for the same tab's item is asking the same question," and
`refreshTabItems()` asks for every tab on every checkout scan and every
branch refresh — a fresh controller per ask "built and threw away a view
controller per tab per edge per scan," leaving discards in `panes` until
AppKit released them (`BranchController.swift` lines 33-46).
**Approved**: pending

**Decision**: A checkout's live `displayName` is placed in each command's
`category`, never in its `title`.
**Rationale**: The doc comment gives the concrete failure this avoids: with
a bare `"Branch"` category, a two-worktree project offered six palette rows
all reading `"Refresh Status — Branch"`, and picking one was "a coin flip
over which directory it acted on." The title is what the per-pane context
menu renders alone, inside a pane that already identifies its checkout, so
repeating the name there would be redundant (`BranchController.swift` lines
96-106).
**Approved**: pending

**Decision**: `revealInFinder` and `copyPath` capture `directory` by value
in a local `let` rather than reaching through `self.checkout.directory` at
invocation time.
**Rationale**: The doc comment states the reason plainly: "so an unregister
that races a menu already on screen still does the right thing rather than
silently nothing" — a menu already built and shown holds closures that keep
working correctly even if the controller that built them has since been torn
down (`BranchController.swift` lines 108-113).
**Approved**: pending

**Decision**: The context menu's `ClosureMenuItemTarget` is assigned to both
`item.target` and `item.representedObject`.
**Rationale**: `NSMenuItem.target` is a weak reference; without a second,
strong retention the target would be deallocated before the menu is ever
shown, and "every item silently inert once its target is deallocated" —
`representedObject` is the retention point chosen to prevent that
(`BranchController.swift` lines 169-172, 189-190).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | partial | Reliability |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |

Notes: separation-of-concerns passes because `BranchController` owns exactly
one checkout's status provider, branch, panes, and commands, delegates all
git work to the injected `GitClient`, delegates status broadcast entirely to
the injected `GitStatusProvider`, and — per its own doc comment — "never
touches the window"; command registration and unregistration with
`CommandRegistry` is `ProjectController`'s responsibility, not this file's.
unit-test-coverage is partial because `BranchControllerTests.swift` exercises
pane reuse and edge/tabID distinctness, a successful branch refresh reloading
panes, checkout-namespaced and cross-checkout-distinct command ids and
categories, and context-menu construction with target retention, but has no
test for `refresh()`'s failure path (see
**refresh-preserves-branch-on-failure**), for overlapping `refresh()` calls
(the open question on refresh-ordering), or for the
weak-pane-table eviction (**weak-pane-table**). explicit-error-handling is
partial because `refresh()`'s `catch` block does nothing beyond a comment
explaining why (the failure is recorded in `GitCommandLog` by `GitClient`,
not by this file) — the error is not silently lost system-wide, but this
file's own handling of it is a deliberate no-op rather than an explicit
mapping onto a result the caller can inspect. graceful-degradation passes
because a failed branch read leaves the last-known branch and still reloads
every pane, rather than crashing or blanking the display.
error-recovery is partial because `BranchController` performs no retry or
backoff of its own after a failed `refresh()` — recovery depends entirely on
some caller invoking `refresh()` again (a worktree rescan, another Refresh
Status command). main-thread-freedom passes because every git subprocess
call reaches this controller through `await gitClient.currentBranch(in:)`,
an async suspension point that does not block the main actor while the
subprocess runs.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
