<!-- leaf: implement-git-client/projects-branch-controller · source: git-client-projects-branch-controller.md -->

**Rules** (cite as `implement-git-client/projects-branch-controller#<slug>`):

- `checkout-ownership` MUST
- `main-actor-isolation` MUST
- `injected-dependencies-no-defaults` MUST
- `initial-branch-from-checkout` MUST
- `pane-identity-per-tab-per-edge` MUST
- `pane-created-once-per-tab-per-edge` MUST
- `pane-registration-on-creation` MUST
- `weak-pane-table` MUST
- `display-name-derivation` MUST
- `refresh-updates-branch-on-success` MUST
- `refresh-preserves-branch-on-failure` MUST
- `refresh-always-reloads-panes` MUST
- `commands-computed-per-access` MUST
- `command-id-namespacing` MUST
- `command-category-carries-checkout-name` MUST
- `command-title-excludes-checkout-name` MUST
- `refresh-status-command-effect` MUST
- `reveal-in-finder-command-effect` MUST
- `copy-path-command-effect` MUST
- `captured-directory-outlives-controller` MUST
- `data-source-agent-name-fixed` MUST
- `data-source-model-name-nil` MUST
- `data-source-status-symbols-fixed` MUST
- `data-source-session-name-derivation` MUST
- `data-source-working-directory-fixed` MUST
- `data-source-branch-passthrough` MUST
- `data-source-summary-nil` MUST
- `context-menu-built-from-commands` MUST
- `context-menu-run-discards-arguments-and-result` MUST
- `context-menu-target-retention` MUST
- `context-menu-item-enablement-via-validation` MUST

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
  read or mutate any other checkout's state (`BranchController.swift`).
- **main-actor-isolation**: `BranchController` MUST be declared `@MainActor`
  and MUST NOT declare `Sendable` conformance; every stored property
  (`checkout`, `statusProvider`, `currentBranch`, `gitClient`, `panes`) and
  every method is therefore confined to the main actor by that declaration,
  not by any lock the type defines itself (`BranchController.swift`).
- **injected-dependencies-no-defaults**: `init(checkout:gitClient:statusProvider:)`
  MUST accept `checkout`, `gitClient`, and `statusProvider` as required
  parameters with no default value for any of them, and MUST NOT construct a
  `GitClient` or `GitStatusProvider` internally — per the doc comment, a
  provider minted inside this initializer "could never be the one" a
  checkout's panes were already given before the controller exists, which
  would leave one checkout served by two status providers
  (`BranchController.swift`).
- **initial-branch-from-checkout**: `init` MUST set `currentBranch` to
  `checkout.branch` at construction time, before any call to `refresh()`
  (`BranchController.swift`).
- **pane-identity-per-tab-per-edge**: `makeTabPane(edge:tabID:)` MUST return
  the same `TabPaneViewController` instance for every call made with the same
  `edge` and `tabID` pair on one controller, found by a linear scan of
  `panes.allObjects` matching both `edge` and `tabID`, and MUST call
  `reload()` on that existing pane before returning it
  (`BranchController.swift`).
- **pane-created-once-per-tab-per-edge**: `makeTabPane(edge:tabID:)` called
  with an `(edge, tabID)` pair not already in `panes` MUST construct exactly
  one new `TabPaneViewController(edge:tabID:)`, and a different `edge` or a
  different `tabID` MUST always be treated as a distinct pane
  (`BranchController.swift`).
- **pane-registration-on-creation**: A newly constructed pane MUST have its
  `dataSource` and `delegate` both set to the owning `BranchController`, MUST
  be added to `panes`, and MUST have `reload()` called on it before
  `makeTabPane(edge:tabID:)` returns it (`BranchController.swift`).
- **weak-pane-table**: `panes` MUST be an `NSHashTable<TabPaneViewController>`
  constructed with `.weakObjects()`, so a pane released by every other owner
  MUST be dropped from `panes` without `BranchController` ever calling an
  explicit unregister method (`BranchController.swift`).
- **display-name-derivation**: `displayName` MUST return `currentBranch` when
  it is non-nil, and otherwise MUST return `checkout.directory.lastPathComponent`,
  computed fresh from the live `currentBranch` on every access rather than
  from any value captured when the controller was built
  (`BranchController.swift`).
- **refresh-updates-branch-on-success**: When `gitClient.currentBranch(in:
  checkout.directory)` returns without throwing, `refresh()` MUST assign that
  result to `currentBranch`, including replacing a non-nil `currentBranch`
  with `nil` when the checkout is now a detached HEAD
  (`BranchController.swift`).
- **refresh-preserves-branch-on-failure**: When `gitClient.currentBranch(in:)`
  throws, `refresh()` MUST leave `currentBranch` at its previous value; the
  error MUST NOT be rethrown, logged, or otherwise surfaced by this method
  (`BranchController.swift`).
- **refresh-always-reloads-panes**: `refresh()` MUST call `reload()` on every
  pane in `panes.allObjects` after its branch-read attempt, regardless of
  whether that attempt succeeded, threw, or `panes` was empty
  (`BranchController.swift`).
- **commands-computed-per-access**: `commands` MUST be computed fresh on
  every access as an array of exactly three `AppCommand` values — Refresh
  Status, Reveal in Finder, Copy Path, in that order — rather than cached
  from a previous access (`BranchController.swift`).
- **command-id-namespacing**: Every command id MUST be
  `"branch.action.<verb>.\(checkout.identifier)"` (`refreshStatus`,
  `revealInFinder`, or `copyPath`), so that two checkouts — including two
  worktrees of the same repository — MUST NOT produce colliding command ids
  (`BranchController.swift`).
- **command-category-carries-checkout-name**: Every command's `category`
  MUST be `"Branch — \(displayName)"`, evaluated at the time `commands` is
  accessed, so a palette listing commands from multiple checkouts MUST show
  each checkout's live name (`BranchController.swift`).
- **command-title-excludes-checkout-name**: A command's `title` (`"Refresh
  Status"`, `"Reveal in Finder"`, `"Copy Path"`) MUST NOT include the
  checkout's name or branch; per the doc comment, the title is what a
  per-pane context menu renders alone, where the pane itself already
  identifies the checkout (`BranchController.swift`).
- **refresh-status-command-effect**: Invoking the Refresh Status command
  MUST call `statusProvider.refresh()` without awaiting or otherwise
  observing its effect, and MUST separately start an unstructured `Task`
  that awaits `self?.refresh()`; both calls MUST capture `self` weakly
  (`BranchController.swift`).
- **reveal-in-finder-command-effect**: Invoking the Reveal in Finder command
  MUST call `NSWorkspace.shared.activateFileViewerSelecting([directory])`,
  where `directory` is `checkout.directory` captured by value when `commands`
  was accessed, not read through `self` at invocation time
  (`BranchController.swift`).
- **copy-path-command-effect**: Invoking the Copy Path command MUST call
  `NSPasteboard.general.clearContents()` and then
  `NSPasteboard.general.setString(directory.path, forType: .string)`, using
  the same value-captured `directory` (`BranchController.swift`).
- **captured-directory-outlives-controller**: Because Reveal in Finder and
  Copy Path capture `directory` by value rather than through `self`, MUST NOT
  fail or act on the wrong directory when invoked after the owning
  `BranchController` has been deallocated or its commands unregistered — per
  the doc comment this is deliberate, "so an unregister that races a menu
  already on screen still does the right thing rather than silently nothing"
  (`BranchController.swift`).
- **data-source-agent-name-fixed**: `tabPaneAgentName(_:)` MUST always
  return the literal string `"Claude"`, regardless of the pane or the
  checkout — a placeholder documented as pending "the document-model work
  that follows the vsc-plugins branch" (`BranchController.swift`).
- **data-source-model-name-nil**: `tabPaneModelName(_:)` MUST always return
  `nil` (`BranchController.swift`).
- **data-source-status-symbols-fixed**: `tabPaneStatusSymbols(_:)` MUST
  always return `[.idle]` (`BranchController.swift`).
- **data-source-session-name-derivation**: `tabPaneSessionName(_:)` MUST
  return `displayName` (`BranchController.swift`).
- **data-source-working-directory-fixed**: `tabPaneWorkingDirectory(_:)`
  MUST return `checkout.directory` unchanged for the controller's lifetime
  (`BranchController.swift`).
- **data-source-branch-passthrough**: `tabPaneBranch(_:)` MUST return the
  live `currentBranch` (`BranchController.swift`).
- **data-source-summary-nil**: `tabPaneSummary(_:)` MUST always return `nil`
  (`BranchController.swift`).
- **context-menu-built-from-commands**: `tabPane(_:contextMenuFor:)` MUST
  build one `NSMenuItem` per entry in `commands`, in the same order, each
  titled with that command's `title` (`BranchController.swift`).
- **context-menu-run-discards-arguments-and-result**: Each menu item's action
  MUST invoke the corresponding command's `run` with an empty argument array
  (`command.run([])`) and MUST discard the returned value
  (`BranchController.swift`).
- **context-menu-target-retention**: Each menu item's `target` MUST be a
  `ClosureMenuItemTarget` wrapping that command, and that same target MUST
  also be assigned to the item's `representedObject`, so it stays retained
  for the item's lifetime despite `NSMenuItem.target` being a weak reference
  (`BranchController.swift`).
- **context-menu-item-enablement-via-validation**: Each menu item's enabled
  state MUST be governed by the wrapped command's `isEnabled` through
  `ClosureMenuItemTarget.validateMenuItem(_:)` — the path AppKit's
  `NSMenu.autoenablesItems` consults — MUST NOT be set directly on
  `NSMenuItem.isEnabled` (`BranchController.swift`).

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

