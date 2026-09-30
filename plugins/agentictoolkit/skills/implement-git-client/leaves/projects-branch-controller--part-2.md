<!-- leaf: implement-git-client/projects-branch-controller--part-2 · source: git-client-projects-branch-controller.md -->

# BranchController — continued (part 2)

**Rules** (cite as `implement-git-client/projects-branch-controller--part-2#<slug>`):

- `winui-3` MUST — Port BranchController as a plain C# class holding ProjectCheckout Checkout, the injected git client and status …

## Localization

`BranchController.swift` produces its user-facing strings as Swift string
literals with no localization key or lookup mechanism:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal) | `Claude` | `tabPaneAgentName(_:)` placeholder agent name. |
| (none — literal) | `Refresh Status` | Command title. |
| (none — literal) | `Reveal in Finder` | Command title. |
| (none — literal) | `Copy Path` | Command title. |
| (none — literal) | `Branch — \(displayName)` | Command category, with the checkout's live name interpolated. |

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
