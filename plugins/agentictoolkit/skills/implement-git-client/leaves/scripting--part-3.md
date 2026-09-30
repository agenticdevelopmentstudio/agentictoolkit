<!-- leaf: implement-git-client/scripting--part-3 · source: git-client-scripting.md -->

# GitClientScripting — continued (part 3)

**Rules** (cite as `implement-git-client/scripting--part-3#<slug>`):

- `pane-unrecognized-edge-restores-rather-than-guesses` MUST
- `pane-actions-delegate-to-host-and-may-be-declined` MUST
- `pane-is-in-window-reasks-live-membership` MUST
- `pane-object-specifier-key` MUST

- **pane-unrecognized-edge-restores-rather-than-guesses**: `ScriptablePane.minimizePane(to:)`
  MUST parse `edgeName` with `PaneEdge(rawValue:)`; when that parse fails, it
  MUST call `self.pane.host?.paneDidRequestRestore(self.pane)` rather than
  guess an edge, and when it succeeds it MUST call
  `self.pane.host?.paneDidRequestMinimize(self.pane, to: edge)`
  (`ScriptablePane.swift`).
- **pane-actions-delegate-to-host-and-may-be-declined**: `closePane()`,
  `zoomPane()` and `minimizePane(to:)` MUST each forward to `self.pane.host?`
  (`paneDidRequestClose`, `paneDidRequestZoom`, `paneDidRequestMinimize`/`paneDidRequestRestore`
  respectively) and MUST NOT implement any part of that effect themselves —
  a script closing or minimizing a pane goes through exactly the path the
  close button or the title-bar arrow takes, and that host MAY decline the
  request (`ScriptablePane.swift`).
- **pane-is-in-window-reasks-live-membership**: `ScriptablePane.isInWindow`
  MUST return `false` when the tagged `window` has been deallocated, and
  otherwise MUST return `window.allPanes().contains { $0 === self.pane }` —
  asking that one window's current pane list by identity, not re-running
  `ProjectWindowManager.shared.scriptablePane(uniqueID:)` across every open
  project, because a pane cannot have moved to a *different* window between
  a request and this question (`ScriptablePane.swift`).
- **pane-object-specifier-key**: `ScriptablePane.objectSpecifier` MUST build
  its `NSScriptObjectSpecifier` via `applicationElementSpecifier(key: "panes")
  { self.uniqueID }` (`ScriptablePane.swift`).
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `uniqueID` (parameter to `scriptableProjectWindow(uniqueID:)`, `scriptableProjectTab(uniqueID:)`, `scriptablePane(uniqueID:)`) | `String` | none — required | The id a script is asking for; compared by plain string equality against each wrapper's `uniqueID`, with no UUID validation of the argument itself. |
| `edgeName` (parameter to `ScriptablePane.minimizePane(to:)`) | `String` | none — required | Parsed with `PaneEdge(rawValue:)`; any string that is not a recognized `PaneEdge` case name is treated as a restore request, not an error. |
| `ProjectWindowManager.shared` (ambient) | singleton | `ProjectWindowManager.shared` | The sole registry this extension reads (`openWindowControllers`, `projectController(for:)`); no dependency is injected into any method here. |
| branch-resolution closure (internal to `scriptingTabs(of:)`) | `(URL) -> String?` | `{ directory in projectController?.branchController(forDirectory: directory)?.currentBranch }` | Not caller-configurable — this exact closure is what `ProjectWindowManager+Scripting.swift` supplies to `ComposableTabsWindowController.scriptingTabs(branch:)` on every call. |

`ProjectWindowManager+Scripting.swift` reads no environment variable and no
settings key of its own; the underlying window/tab/pane state it enumerates
is populated by `openProject(_:)` and `adoptForScripting(_:)`, neither of
which is a concern of this file.

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/macOS/Features/Projects/Scripting/ProjectWindowManager+Scripting.swift`,
  plus the three wrapper types under `macOS/UI/ViewControllers/ComposableTabs/Scripting/`,
  all built on `AppKit` (`NSObject`, `NSScriptObjectSpecifier`) and
  `AgenticToolkitCore`/`AgenticToolkitMacOS` (`ProjectWindowManager`,
  `ComposableTabsWindowController`, `ProjectController`, `BranchController`).
  None of the four files uses SwiftUI; a SwiftUI-hosted project window would
  still need this same `NSObject`-based Cocoa Scripting bridge, since
  `NSScriptCommand`/`NSScriptObjectSpecifier` are AppKit/Foundation types
  with no SwiftUI equivalent.
- **Compose**: There is no Cocoa Scripting (AppleScript) equivalent on
  Android, so a Compose port would drop the `NSObject`/`@objc`/`objectSpecifier`
  machinery entirely and keep only the enumeration and git-branch-resolution
  logic: a plain function or repository method that maps open project
  windows to a `List` of view models, each carrying the same fields
  (`uniqueID`, `name`, tab list, branch), with the weak/strong holding
  distinctions replaced by whatever lifecycle scoping (`ViewModel`,
  `remember`) Compose already uses to avoid keeping a closed screen's data
  alive.
- **React/Web**: There is no OS-level scripting bridge on the web either; a
  browser port would expose the same three enumerations and lookups as a
  small internal API (or a debugging/automation endpoint) returning plain
  JSON objects with the same field names, and would resolve a tab's branch
  by asking a server-side git service rather than a local `BranchController`.
- **AppKit / UIKit**: The source already is AppKit. iOS has no
  `NSScriptCommand`/Cocoa Scripting equivalent at all (no AppleScript on
  iOS), so a UIKit port would keep only the enumeration/lookup/branch-resolution
  logic as a plain Swift type for use by, for example, a debug menu or a
  Shortcuts (App Intents) integration — `objectSpecifier` and the
  `applicationElementSpecifier`-keyed addressing have no iOS analogue.
- **WinUI 3**: There is no AppleScript/Cocoa Scripting equivalent on
  Windows; the nearest analogue for "let external automation enumerate and
  address open windows, tabs and panes" is exposing a small COM Automation
  or Windows App SDK scripting surface, or simply a public API other in-process
  code calls directly. Port the three enumerations as plain C# properties
  (`IReadOnlyList<ScriptableProjectWindow>` etc.) computed fresh on every
  access from whatever collection tracks open project windows (mirror
  `openWindowControllers`'s already-recorded open-order list rather than a
  `Dictionary`'s enumeration order, which .NET does not guarantee stable
  either). Port the three id-based lookups as `FirstOrDefault` over a LINQ
  `SelectMany`, which is lazy by default and so preserves the short-circuit
  behavior of **window-lookup-short-circuits**/**tab-lookup-short-circuits**/**pane-lookup-short-circuits**
  without extra effort. Mirror the weak-vs-strong asymmetry with
  `WeakReference<ComposableTabsWindowController>` for the window a
  `ScriptableProjectWindow`-equivalent holds and a plain strong reference for
  the pane view model a `ScriptablePane`-equivalent holds. Resolve the git
  branch through the same `GitClient`/`BranchController` port this family's
  siblings already define (see
  `agentictoolkit://recipes/git-client-projects-branch-controller`), folding
  a `null` result to `string.Empty` at the same point `ComposableTabsWindowController.scriptingTabs(branch:)`
  does, and enforce main-thread confinement with `DispatcherQueue` in place
  of `@MainActor`.

## Design Decisions

**Decision**: `scriptableProjectWindow(uniqueID:)`, `scriptableProjectTab(uniqueID:)`
and `scriptablePane(uniqueID:)` each search a `.lazy` sequence and stop at the
first match, rather than building the full `scriptableProjectWindows`/`scriptableProjectTabs`/`scriptablePanes`
array and filtering it.
**Rationale**: The doc comment on `scriptableProjectWindow(uniqueID:)` states
the cost this avoids directly: building the full array first would construct
a wrapper "for the windows after the answer" that "are made and thrown away,"
and there is one wrapper per open project, tab, or pane
(`ProjectWindowManager+Scripting.swift`).
**Approved**: pending

**Decision**: `ScriptableProjectWindow` holds its `ComposableTabsWindowController`
weakly, while `ScriptablePane` holds its `ComposableTabsPaneViewController`
strongly (and its window weakly).
**Rationale**: `ScriptableProjectWindow.swift`'s doc comment explains the
window side: "a script can keep a reference to a window it then closes, and
a wrapper is not a reason to keep a window's whole object graph — and its
database handle — alive". `ScriptablePane.swift`'s doc comment
explains the opposite choice for its pane: the wrapper "is made fresh on
every read," Cocoa Scripting "re-resolves a specifier through `panes` rather
than holding a wrapper between events," so "nothing outlives the reply it
was built for" and a strong reference is safe for exactly that long.
**Approved**: pending

**Decision**: A tab's branch that cannot be resolved — no `ProjectController`,
no matching `BranchController`, or a detached HEAD — is reported as the
empty string, never `nil` or a thrown error.
**Rationale**: `ComposableTabsWindowController.scriptingTabs(branch:)`'s doc
comment states this is deliberate: a caller with no branch controller "passes
`{ _ in nil }`, which `ScriptableProjectTab` reports as an empty string"
(`ComposableTabsWindowController.swift`) — matching
`BranchController`'s own policy that a detached HEAD is "an answer,"
documented in `agentictoolkit://recipes/git-client-projects-branch-controller`.
**Approved**: pending

**Decision**: `ScriptableProjectTab.uniqueID` is the tab *group's* id, not
any per-edge member row's id.
**Rationale**: The type's doc comment states a project-level tab is "drawn
once on every enabled edge under one shared title," so exposing a per-edge
id "would be seeing an implementation detail rather than what is on screen"
(`ScriptableProjectTab.swift`).
**Approved**: pending

**Decision**: `ScriptablePane.init(pane:in:)` requires its enumerating
window as a parameter rather than letting the pane discover its own window.
**Rationale**: The doc comment is explicit: a pane behind a background tab
"has never been in a window's view hierarchy," so a wrapper that asked
`view.window` "names no project and no tab — for most of the panes in a real
window," while enumeration "always knows which window it is walking"
(`ScriptablePane.swift`; corroborated by the sibling doc comment
on `scriptablePanes` itself, `ProjectWindowManager+Scripting.swift`).
**Approved**: pending

**Decision**: `ScriptablePane.isInWindow` re-asks its own tagged window's
current `allPanes()` rather than re-running
`ProjectWindowManager.shared.scriptablePane(uniqueID:)`.
**Rationale**: The doc comment reasons that "a pane cannot have moved to a
*different* window between the request and this question, so one window's
walk is a complete answer, where the manager's lookup would walk every open
project to reach the same one" (`ScriptablePane.swift`).
**Approved**: pending
