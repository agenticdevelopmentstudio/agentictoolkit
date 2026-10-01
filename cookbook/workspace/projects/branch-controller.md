---
id: 92f11498-2cb2-4b04-92b9-560d9f2de6ee
title: Branch Management
domain: agentictoolkit://cookbook/workspace/projects/branch-controller
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
depends-on: []
related:
- agentictoolkit://cookbook/workspace/files/git-status-provider
- agentictoolkit://cookbook/ui/layout/tabbed-view/tab-pane
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

# Branch Management

## Overview

Branch management owns one project checkout: its git status provider, its
live current branch, the tab panes that describe it, and the three
commands a command palette or a pane's context menu act on it through. It
is vended once per checkout and reused across branch switches of that same
directory; by design it "never touches the window." It is the tab pane's
data source (so the pane can render the checkout's agent, session,
directory, branch and summary without computing any of it itself) and its
context-menu provider (so the same component supplies the pane's context
menu). Every property and method is confined to a single execution context
(see Platform Notes).

## Behavioral Requirements

- **checkout-ownership**: Branch management MUST hold exactly one checkout,
  one git status provider, and the mutable current branch for that
  checkout, and MUST NOT read or mutate any other checkout's state.
- **injected-dependencies-no-defaults**: Construction MUST require the
  checkout, the git client, and the git status provider as parameters with
  no default value for any of them, and MUST NOT construct a git client or
  git status provider internally — a provider minted internally could
  never be the one a checkout's panes were already given before the
  component exists, which would leave one checkout served by two status
  providers.
- **initial-branch-from-checkout**: Construction MUST set the current
  branch to the checkout's branch at construction time, before any call to
  refresh.
- **pane-identity-per-tab-per-edge**: Requesting a tab pane for a given
  edge and tab MUST return the same tab pane instance for every call made
  with the same edge and tab pair on one component, found by a scan of its
  known panes matching both edge and tab, and MUST reload that existing
  pane before returning it.
- **pane-created-once-per-tab-per-edge**: Requesting a tab pane for an edge
  and tab pair not already known MUST construct exactly one new tab pane
  for that edge and tab, and a different edge or a different tab MUST
  always be treated as a distinct pane.
- **pane-registration-on-creation**: A newly constructed pane MUST have
  both its data source and its context-menu provider set to the owning
  branch management component, MUST be added to the known panes, and MUST
  be reloaded before being returned.
- **weak-pane-table**: The known panes MUST be held weakly, so a pane
  released by every other owner MUST be dropped from the known panes
  without branch management ever calling an explicit unregister method.
- **display-name-derivation**: The display name MUST return the current
  branch when it is non-nil, and otherwise MUST return the last component
  of the checkout's directory path, computed fresh from the live current
  branch on every access rather than from any value captured when the
  component was built.
- **refresh-updates-branch-on-success**: When reading the current branch
  from git for the checkout's directory succeeds, refresh MUST assign that
  result to the current branch, including replacing a non-nil current
  branch with nothing when the checkout is now a detached HEAD.
- **refresh-preserves-branch-on-failure**: When reading the current branch
  fails, refresh MUST leave the current branch at its previous value; the
  error MUST NOT be rethrown, logged, or otherwise surfaced by this
  operation.
- **refresh-always-reloads-panes**: refresh MUST reload every known pane
  after its branch-read attempt, regardless of whether that attempt
  succeeded, failed, or there were no panes to reload.
- **commands-computed-per-access**: The commands MUST be computed fresh on
  every access as a list of exactly three commands — Refresh Status,
  Reveal in Finder, Copy Path, in that order — rather than cached from a
  previous access.
- **command-id-namespacing**: Every command id MUST be
  `branch.action.<verb>.<checkout-identifier>` (`refreshStatus`,
  `revealInFinder`, or `copyPath`), so that two checkouts — including two
  worktrees of the same repository — MUST NOT produce colliding command
  ids.
- **command-category-carries-checkout-name**: Every command's category
  MUST be `Branch — <display name>`, evaluated at the time the commands
  are read, so a palette listing commands from multiple checkouts MUST
  show each checkout's live name.
- **command-title-excludes-checkout-name**: A command's title (`Refresh
  Status`, `Reveal in Finder`, `Copy Path`) MUST NOT include the
  checkout's name or branch; the title is what a per-pane context menu
  renders alone, where the pane itself already identifies the checkout.
- **refresh-status-command-effect**: Invoking the Refresh Status command
  MUST trigger a status refresh without waiting for or otherwise observing
  its effect, and MUST separately begin an independent, asynchronous
  branch refresh that does not block the invoking call; neither reference
  to the branch management component MUST keep it alive beyond what that
  outstanding work needs.
- **reveal-in-finder-command-effect**: Invoking the Reveal in Finder
  command MUST reveal the checkout's directory in the system file browser,
  using the directory captured by value at the time the commands were
  read, not read again through live state at invocation time (see Platform
  Notes).
- **copy-path-command-effect**: Invoking the Copy Path command MUST
  replace the system clipboard's contents with the path of that same
  value-captured directory (see Platform Notes).
- **captured-directory-outlives-controller**: Because Reveal in Finder and
  Copy Path capture the directory by value rather than through live state,
  they MUST NOT fail or act on the wrong directory when invoked after the
  owning branch management component has been released or its commands
  unregistered — this is deliberate, so an unregister that races a menu
  already on screen still does the right thing rather than silently
  nothing.
- **data-source-agent-name-fixed**: Reading the pane's agent name MUST
  always return the literal string `Claude`, regardless of the pane or the
  checkout — a placeholder pending later work.
- **data-source-model-name-nil**: Reading the pane's model name MUST always
  return no value.
- **data-source-status-symbols-fixed**: Reading the pane's status symbols
  MUST always return a single idle symbol.
- **data-source-session-name-derivation**: Reading the pane's session name
  MUST return the display name.
- **data-source-working-directory-fixed**: Reading the pane's working
  directory MUST return the checkout's directory unchanged for the
  component's lifetime.
- **data-source-branch-passthrough**: Reading the pane's branch MUST
  return the live current branch.
- **data-source-summary-nil**: Reading the pane's summary MUST always
  return no value.
- **context-menu-built-from-commands**: Building the pane's context menu
  MUST create one menu item per command, in the same order, each titled
  with that command's title.
- **context-menu-run-discards-arguments-and-result**: Each menu item's
  action MUST invoke the corresponding command's run operation with an
  empty argument list and MUST discard the returned value.
- **context-menu-target-retention**: Each menu item MUST retain a strong,
  independent reference to its wrapped command for the item's whole
  lifetime, so the command keeps working even though nothing else in the
  application continues to hold it (see Platform Notes for the mechanism
  this needs on this platform).
- **context-menu-item-enablement-via-validation**: Each menu item's enabled
  state MUST be governed dynamically by the wrapped command's enabled state
  at the moment the menu is shown, and MUST NOT be fixed once when the menu
  item is built (see Platform Notes for the platform mechanism that
  provides this).

## Appearance

Not applicable — this is a checkout-owning component, not a visual
component.

## States

Not applicable — this is a checkout-owning component, not a visual
component. Its one runtime state machine — a checkout's live branch,
tracked and re-read on refresh — is covered under Behavioral Requirements
(**refresh-updates-branch-on-success**,
**refresh-preserves-branch-on-failure**), not here.

## Accessibility

Not applicable — this is a checkout-owning component, not a visual
component. The accessibility of the panes and menu items it supplies
content to is the concern of the tab pane view and the platform's menu
system, neither of which this component renders itself.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-branch-controller-001 | pane-registration-on-creation, data-source-agent-name-fixed, data-source-model-name-nil, data-source-session-name-derivation, data-source-working-directory-fixed, data-source-branch-passthrough, data-source-summary-nil, display-name-derivation | Request a tab pane for the left edge and a new tab id, from a component built for a checkout with a temporary directory, branch `main`, marked as the main checkout, then reload that pane. | The agent label reads `Claude`; the session and branch labels read `main`; the directory label ends with the checkout directory's last path component; the summary label is hidden; the pane's data source and context-menu provider are both the branch management component. |
| git-client-projects-branch-controller-002 | pane-identity-per-tab-per-edge, pane-created-once-per-tab-per-edge | Request a tab pane for the left edge and a given tab id twice, then once more for the right edge with the same tab id, and once for the left edge with a new tab id. | The first two requests return the identical pane instance; the right-edge request and the new-tab-id request each return a different instance from the first. |
| git-client-projects-branch-controller-003 | initial-branch-from-checkout, refresh-updates-branch-on-success, refresh-always-reloads-panes, data-source-branch-passthrough | Initialize a git repository on branch `feature` with one commit; build a component for a checkout with no branch recorded; request a pane; refresh. | The current branch reads `feature`; the pane's branch and session labels both read `feature`. |
| git-client-projects-branch-controller-004 | command-id-namespacing, command-category-carries-checkout-name | Read the commands' ids and categories for a checkout with branch `main` and a given identifier suffix. | Ids equal `branch.action.refreshStatus.<suffix>`, `branch.action.revealInFinder.<suffix>`, `branch.action.copyPath.<suffix>`; every command's category equals `Branch — main`. |
| git-client-projects-branch-controller-005 | command-id-namespacing, command-category-carries-checkout-name, command-title-excludes-checkout-name | Build two components for two checkouts (`main`/one directory, `feature`/another); combine both sets of commands into title/category rows. | All 6 rows are pairwise distinct; the first checkout's three rows all carry category `Branch — main` and the second's all carry `Branch — feature`. |
| git-client-projects-branch-controller-006 | context-menu-built-from-commands, context-menu-target-retention | Build the pane's context menu for a secondary-click event. | The item titles read `Refresh Status`, `Reveal in Finder`, `Copy Path`; every item's command reference is still valid after the call returns, surviving past the point a default weak reference would otherwise have released it. |
| git-client-projects-branch-controller-007 | refresh-preserves-branch-on-failure | Construct a component whose checkout directory does not exist (so reading the current branch fails); set the current branch to `main` beforehand; refresh. | The current branch is still `main`; no error propagates out of refresh. |
| git-client-projects-branch-controller-008 | injected-dependencies-no-defaults, checkout-ownership | Construct the branch management component twice with two distinct, pre-built git status providers. | Each component's git status provider is the exact instance passed to its construction, never a new one built internally. |
| git-client-projects-branch-controller-009 | weak-pane-table | Request a tab pane, let the returned pane go out of scope with no other strong reference held, then trigger an operation that iterates the known panes (e.g. refresh). | The released pane is not reloaded; the known panes no longer include it. |
| git-client-projects-branch-controller-010 | commands-computed-per-access, refresh-status-command-effect | Register a fake git status provider and invoke the Refresh Status command. | The status provider's refresh is called synchronously, before the invocation returns, and the component's own refresh is additionally triggered asynchronously. |
| git-client-projects-branch-controller-011 | reveal-in-finder-command-effect, copy-path-command-effect, captured-directory-outlives-controller | Read the commands, discard the strong reference to the branch management component, then invoke the captured Reveal in Finder and Copy Path actions. | Revealing the directory in the system file browser, and the clipboard write, both still target the original checkout directory, even though the component that vended the commands is gone. |
| git-client-projects-branch-controller-012 | context-menu-run-discards-arguments-and-result, context-menu-item-enablement-via-validation | Build the context menu for a checkout whose Refresh Status command reports itself disabled, then check that item's enabled state. | The disabled item's enabled check reads false and the other two read true; invoking the item's action still calls the command's run operation with an empty argument list — menu construction does not gate on the enabled state itself. |

## Edge Cases

- **Null and empty input**: A checkout constructed with no branch recorded
  (a detached-HEAD or newly discovered worktree) leaves the current branch
  unset until the first successful refresh; the display name falls back to
  the checkout directory's last path component for exactly that period
  (MUST, see **initial-branch-from-checkout**, **display-name-derivation**).
  Requesting a tab pane before any pane exists always takes the "create"
  path — there is no null/empty case to special-case, since the known
  panes start empty and the scan simply finds nothing (MUST, see
  **pane-created-once-per-tab-per-edge**).
- **Boundary values**: The commands always number exactly three, never
  zero or a variable count — there is no configuration that adds or
  removes a command (MUST, see **commands-computed-per-access**). The
  known panes may hold zero entries (a checkout with no open tab yet);
  reloading zero panes on refresh is not an error, it simply reloads
  nothing (MUST, see **refresh-always-reloads-panes**).
- **Concurrent access**: Every mutation of the current branch and the
  known panes is confined to a single execution context (see Platform
  Notes), so no interleaving can observe a torn write. Refresh itself has
  no coalescing, generation counter, or in-flight guard of any kind —
  unlike its sibling git status provider (see
  `agentictoolkit://cookbook/workspace/files/git-status-provider`), which
  explicitly coalesces overlapping calls into at most one queued follow-up
  and discards a stale response with a generation check. Two overlapping
  refresh calls (for example, two rapid Refresh Status invocations) each
  independently read the current branch and each independently assign it
  and reload every pane on completion; whichever call's read returns last
  wins, with no rule preferring the call that was *started* last over one
  that merely finished last; see the open question on refresh-ordering.
- **refresh-ordering**: NEEDS REVIEW: Not implemented. There is no
  ordering or coalescing rule for overlapping refresh calls on one branch
  management component: whichever call's branch read returns last sets the
  current branch and reloads the panes, even if it was started first.
  Existing tests exercise only a single refresh call; the app's
  worktree-scan and command-dispatch call sites, or a stress test issuing
  overlapping refresh calls, would settle whether this is reachable in
  practice.
- **Error states**: A missing git executable, a failed process launch, a
  timed-out git call, and a failed git command are not distinguished from
  one another by refresh; every one produces the same outcome — the
  current branch unchanged, every pane still reloaded (MUST, see
  **refresh-preserves-branch-on-failure**, **refresh-always-reloads-panes**).
  The caller of the Refresh Status command has no way to learn that the
  branch read specifically failed, as distinct from succeeding with an
  unchanged value; the failure's only record is the git command log kept
  by the injected git client (a collaborator, not this component — see
  `agentictoolkit://cookbook/workspace/files/git-status-provider`'s sibling
  git client entry).
- **Offline or disconnected state**: Not applicable in the network sense —
  reading the current branch runs a local git command against the local
  working tree only; it makes no request to a remote and has no notion of
  connectivity. An unreadable or removed local checkout directory is
  handled identically to any other failure above.
- **Cancellation and timeouts**: The asynchronous refresh started by the
  Refresh Status command is independent of the invocation; once started,
  nothing can cancel it. If the branch management component has already
  been released by the time that work runs, the refresh is a no-op; if it
  is still alive, the reference is promoted for the duration of that one
  call, keeping the component alive just long enough to finish it (MUST,
  see **refresh-status-command-effect**). A timed-out git call reaches
  refresh through the same generic failure path as every other error (see
  Error states above); this component applies no timeout of its own.
- **Missing file or unreachable server**: A checkout directory that has
  been deleted (for example by a worktree removal running concurrently
  with a pending refresh) surfaces only as whatever failure reading the
  current branch produces for a missing directory, handled identically to
  Error states above (MUST). Neither **reveal-in-finder-command-effect**
  nor **copy-path-command-effect** checks that the directory still exists
  before acting on it; a stale Reveal in Finder or Copy Path invocation is
  forwarded to the platform's file browser or clipboard unchanged (MUST,
  see **captured-directory-outlives-controller**) — it is the owning
  project management component's job, not this one's, to unregister a
  checkout's commands once its directory is gone.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| checkout (construction parameter) | the checkout | none — required | The checkout this component owns; fixed for the instance's lifetime, though the checkout it names may switch branches without a new component being built. |
| git client (construction parameter) | the git client | none — required, no internal fallback | Injected by the caller; branch management never falls back to a shared default itself. |
| git status provider (construction parameter) | the git status provider | none — required, no internal fallback | Injected by the caller via the project workspace's per-directory status-provider lookup, so every consumer of one checkout's status shares one provider. |

This component reads no environment variable and no settings key directly;
git executable path, timeout, and submodule handling are git client
configuration concerns reached only indirectly through the injected git
client.

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigation
destination.

## Localization

This component produces its user-facing strings as literals with no
localization key or lookup mechanism:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal) | `Claude` | Placeholder agent name shown by the pane. |
| (none — literal) | `Refresh Status` | Command title. |
| (none — literal) | `Reveal in Finder` | Command title. |
| (none — literal) | `Copy Path` | Command title. |
| (none — literal) | `Branch — <display name>` | Command category, with the checkout's live name interpolated. |

## Accessibility Options

Not applicable: this component renders nothing itself — it hands labels,
symbols, and menu items to the tab pane view and the platform's menu
system. Reduce Motion, Increase Contrast, and Differentiate Without Color
are concerns of those rendering layers, with nothing in this component to
opt into or out of.

## Feature Flags

Not applicable: this component contains no feature-flag or
build-configuration check.

## Analytics

Not applicable: this component makes no analytics or event-tracking call.

## Privacy

Not applicable: the only data this component touches is a local
filesystem path (the checkout's directory) and a git branch name, both
already visible to the user in the project window and command palette; it
reads, stores, or transmits no credential, token, or personal data.

## Logging

This component makes no logging call of its own. The one error it
swallows (refresh's failure path) is recorded by a different component,
the git command log kept by the injected git client's unconditional
recording (see `agentictoolkit://cookbook/workspace/files/git-status-provider`'s
sibling git client entry), not logged a second time here.

| Event | Level | Message |
|-------|-------|---------|
| (none) | — | This component emits no log messages. |

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/BranchController.swift`,
  built on `AppKit` (`NSHashTable`, `NSMenu`, `NSMenuItem`, `NSWorkspace`,
  `NSPasteboard`) and `AgenticToolkitCore` (`ProjectCheckout`, `GitClient`,
  `GitStatusProvider`, `AppCommand`, `TabPaneDataSource`/`TabPaneDelegate`,
  `Edge`, `TabPaneStatusSymbol`, `ClosureMenuItemTarget`). It uses no
  SwiftUI API; a SwiftUI-hosted pane would still need an `NSViewController`
  bridge (or its own `TabPaneDataSource`-equivalent) to reach this
  component's data. It is declared `@MainActor` and holds no `Sendable`
  conformance of its own, so every stored property and method is confined
  to the main actor by that declaration alone, not by any lock the type
  defines itself. Because `NSMenuItem.target` is a weak reference, each
  context menu item's `ClosureMenuItemTarget` is also assigned to the
  item's `representedObject` so it stays retained for the item's lifetime;
  enablement is likewise routed through
  `ClosureMenuItemTarget.validateMenuItem(_:)`, the path
  `NSMenu.autoenablesItems` consults, rather than set once on
  `NSMenuItem.isEnabled`.
- **Compose**: Model this component as a plain class (or, given its
  main-thread confinement, a class annotated for Compose's main-thread
  dispatcher) holding `checkout`, `gitClient`, `statusProvider`, and a
  mutable `currentBranch` `State`/`MutableState`. Replace the weak
  `NSHashTable` of panes with a `MutableList` of weakly-held pane view
  models (Kotlin has no built-in weak collection; a `WeakHashMap`-backed
  wrapper is the closer match) keyed by `(edge, tabID)`. Represent the
  three commands as a `List` of a small `AppCommand`-equivalent data class,
  and build a context menu (`DropdownMenu`) from that list the same way.
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
- **WinUI 3**: Port this component as a plain C# class holding
  `ProjectCheckout Checkout`, the injected git client and status provider,
  and a `string? CurrentBranch` property, with no interface requiring
  thread-affinity of its own — mirror the main-thread confinement by only
  ever touching this object from the UI thread (`DispatcherQueue`), the
  same discipline the git status provider's WinUI port already assumes
  (see `agentictoolkit://cookbook/workspace/files/git-status-provider`).
  Replace `NSHashTable<TabPaneViewController>.weakObjects()` with a
  `List<WeakReference<TabPaneViewController>>` (or a
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/BranchController.swift` |

## Design Decisions

**Decision**: `displayName` reads from `currentBranch`, which is re-read on
every `refresh()`, rather than from the `checkout` snapshot the controller
was constructed with.
**Rationale**: Per the doc comment, `checkout` is a `let` that "never
moves" — `identifier` depends on that being true, so a checkout keeps its
identity across branch switches — but a label read off that frozen snapshot
would go on naming whichever branch was checked out when the window opened.
Everything the user reads (the command palette's category, a pane's session
name) needs the live value instead (`BranchController.swift`).
**Approved**: pending

**Decision**: `refresh()` treats a successful call that resolves to `nil`
(detached HEAD) as replacing `currentBranch`, but treats a thrown error as
leaving `currentBranch` untouched — the two are not folded into one `try?`.
**Rationale**: The doc comment states this directly: "a detached HEAD is an
*answer*... a thrown error is not an answer — git could not be asked, so the
last known branch stays put," matching the policy `GitStatusProvider` applies
to a failed status; folding both into `try?` "kept a stale branch name on
screen forever, because the two cases are indistinguishable once the error
is discarded" (`BranchController.swift`).
**Approved**: pending

**Decision**: `makeTabPane(edge:tabID:)` returns the existing pane for a
given `(edge, tabID)` rather than minting a new `TabPaneViewController` on
every call.
**Rationale**: The doc comment explains the cost this avoids: "asking twice
for the same tab's item is asking the same question," and
`refreshTabItems()` asks for every tab on every checkout scan and every
branch refresh — a fresh controller per ask "built and threw away a view
controller per tab per edge per scan," leaving discards in `panes` until
AppKit released them (`BranchController.swift`).
**Approved**: pending

**Decision**: A checkout's live `displayName` is placed in each command's
`category`, never in its `title`.
**Rationale**: The doc comment gives the concrete failure this avoids: with
a bare `"Branch"` category, a two-worktree project offered six palette rows
all reading `"Refresh Status — Branch"`, and picking one was "a coin flip
over which directory it acted on." The title is what the per-pane context
menu renders alone, inside a pane that already identifies its checkout, so
repeating the name there would be redundant (`BranchController.swift`).
**Approved**: pending

**Decision**: `revealInFinder` and `copyPath` capture `directory` by value
in a local `let` rather than reaching through `self.checkout.directory` at
invocation time.
**Rationale**: The doc comment states the reason plainly: "so an unregister
that races a menu already on screen still does the right thing rather than
silently nothing" — a menu already built and shown holds closures that keep
working correctly even if the controller that built them has since been torn
down (`BranchController.swift`).
**Approved**: pending

**Decision**: The context menu's `ClosureMenuItemTarget` is assigned to both
`item.target` and `item.representedObject`.
**Rationale**: `NSMenuItem.target` is a weak reference; without a second,
strong retention the target would be deallocated before the menu is ever
shown, and "every item silently inert once its target is deallocated" —
`representedObject` is the retention point chosen to prevent that
(`BranchController.swift`).
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
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
