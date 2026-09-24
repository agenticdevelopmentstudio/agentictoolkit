---
id: ccb08e0d-f505-4195-adf8-d8ac9208b24c
title: GitClientScripting
domain: agentictoolkit://recipes/git-client-scripting
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'ProjectWindowManager''s Cocoa Scripting surface: enumerating and looking
  up open project windows, tabs and panes, and wiring each tab''s git branch into
  the scripting vocabulary.'
platforms:
- swift
- macos
tags:
- git
- projects
- scripting
- cocoa-scripting
- applescript
- composable-tabs
- appkit
- macos
depends-on:
- agentictoolkit://recipes/foundation-scripting
- agentictoolkit://recipes/composable-tabs-window-controller
- agentictoolkit://recipes/git-client-projects-project-controller
- agentictoolkit://recipes/git-client-projects-branch-controller
related:
- agentictoolkit://recipes/composable-tabs-pane-view-controller
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/Scripting/ProjectWindowManager+Scripting.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/Scripting/ScriptableProjectWindow.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/Scripting/ScriptableProjectTab.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/Scripting/ScriptablePane.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWindowManager.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsWindowController.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/BranchController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Scripting/MainActorScriptCommand.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/ComposableTabs/ProjectScriptingTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# GitClientScripting

## Overview

`ProjectWindowManager+Scripting.swift` is the extension on `ProjectWindowManager`
that answers everything Cocoa Scripting (AppleScript) asks about project
windows, tabs and panes: three enumerated arrays (`scriptableProjectWindows`,
`scriptableProjectTabs`, `scriptablePanes`) and three id-based lookups
(`scriptableProjectWindow(uniqueID:)`, `scriptableProjectTab(uniqueID:)`,
`scriptablePane(uniqueID:)`). It hangs off `ProjectWindowManager` rather than a
separate registry because that manager is already the answer to "which
project windows are open." Its one piece of domain logic beyond enumeration is
git: `scriptingTabs(of:)` resolves each tab's working directory to a live
branch name by reaching through `ProjectController.branchController(forDirectory:)`
into that checkout's `BranchController.currentBranch` — the "git client" a
project tab's `branch` property exposes to a script. The extension itself
constructs three `NSObject`-backed wrapper types it does not define —
`ScriptableProjectWindow`, `ScriptableProjectTab` and `ScriptablePane` — whose
own properties this recipe also specifies, because no other recipe yet owns
them.

## Behavioral Requirements

- **window-enumeration-order**: `scriptableProjectWindows` MUST map every
  controller in `openWindowControllers`, in that array's order, to one
  `ScriptableProjectWindow(controller:)` (`ProjectWindowManager+Scripting.swift`). `openWindowControllers` itself is `openOrder.compactMap {
  controllers[$0] }` — the order projects were opened in, not dictionary
  order (`ProjectWindowManager.swift` and its preceding comment).
- **window-enumeration-recomputed**: `scriptableProjectWindows` MUST be
  recomputed from `openWindowControllers` on every access; it is a computed
  property with no backing cache, so a window opened or closed between two
  reads MUST be reflected in the very next read (`ProjectWindowManager+Scripting.swift`).
- **window-lookup-short-circuits**: `scriptableProjectWindow(uniqueID:)` MUST
  search `openWindowControllers.lazy.map(ScriptableProjectWindow.init(controller:))`
  and stop at the first wrapper whose `uniqueID` equals the argument, so a
  match at position *n* MUST NOT cause a `ScriptableProjectWindow` to be
  constructed for any controller after it (`ProjectWindowManager+Scripting.swift`).
- **window-lookup-miss-returns-nil**: `scriptableProjectWindow(uniqueID:)`
  MUST return `nil` when no open window's `uniqueID` equals the argument,
  including when the argument is not a well-formed UUID string — the search
  is a plain string comparison, not a UUID parse, so it MUST NOT throw or
  crash on a malformed argument (`ProjectWindowManager+Scripting.swift`).
- **tab-enumeration-nests-by-window**: `scriptableProjectTabs` MUST flat-map
  `openWindowControllers` through `scriptingTabs(of:)`, so the result is
  every window's tabs, windows in `openWindowControllers` order and, within
  one window, in that window's own tab-group order
  (`ProjectWindowManager+Scripting.swift`).
- **tab-branch-resolver-wiring**: `scriptingTabs(of:)` MUST look up
  `self.projectController(for: controller.project.id)` once per window, and
  MUST pass `scriptingTabs(branch:)` a closure that, for a tab's working
  directory `directory`, evaluates `projectController?.branchController(forDirectory:
  directory)?.currentBranch` (`ProjectWindowManager+Scripting.swift`).
- **tab-branch-nil-for-adopted-windows**: Because `projectController(for:)`
  returns `nil` for a window `adoptForScripting(_:)` registered rather than a
  window this manager opened (`ProjectWindowManager.swift` and
  their preceding comment), every tab belonging to an adopted-only window
  MUST resolve its branch closure to `nil`, which `ComposableTabsWindowController.scriptingTabs(branch:)`
  then reports as the empty string (see **tab-branch-empty-when-unresolved**).
- **tab-lookup-short-circuits**: `scriptableProjectTab(uniqueID:)` MUST walk
  `openWindowControllers.lazy.flatMap { self.scriptingTabs(of: $0) }` and stop
  at the first tab whose `uniqueID` equals the argument, so tabs in windows
  after the match MUST NOT be built (`ProjectWindowManager+Scripting.swift`).
- **tab-lookup-miss-returns-nil**: `scriptableProjectTab(uniqueID:)` MUST
  return `nil` when no open tab's `uniqueID` equals the argument
  (`ProjectWindowManager+Scripting.swift`).
- **pane-enumeration-tags-source-window**: `scriptablePanes` MUST flat-map
  `openWindowControllers`, and for each window MUST map every pane in that
  window's `allPanes()` to `ScriptablePane(pane:in: window)`, tagging each
  wrapper with the exact window it was enumerated from rather than leaving the
  wrapper to discover its own window (`ProjectWindowManager+Scripting.swift`).
- **pane-lookup-short-circuits**: `scriptablePane(uniqueID:)` MUST walk
  `openWindowControllers.lazy.flatMap { window in window.allPanes().lazy.map
  { ScriptablePane(pane: $0, in: window) } }` and stop at the first pane
  whose `uniqueID` equals the argument (`ProjectWindowManager+Scripting.swift`).
- **pane-lookup-miss-returns-nil**: `scriptablePane(uniqueID:)` MUST return
  `nil` when no open pane's `uniqueID` equals the argument
  (`ProjectWindowManager+Scripting.swift`).
- **main-actor-confinement**: Every member of this extension, and every
  member of `ScriptableProjectWindow`, `ScriptableProjectTab` and
  `ScriptablePane`, MUST run on the main actor: `ProjectWindowManager` is
  declared `@MainActor` (`ProjectWindowManager.swift`) with no
  `Sendable` conformance, and each of the three wrapper classes independently
  repeats the `@MainActor` declaration on itself (`ScriptableProjectWindow.swift`, `ScriptableProjectTab.swift`, `ScriptablePane.swift`). None of the four types MUST be called from a non-main-actor context.
- **window-id-is-project-id**: `ScriptableProjectWindow.uniqueID` MUST return
  `self.controller?.project.id.uuidString`, falling back to `""` when
  `controller` is `nil` — the persisted `git_repo.id`, so one window's id is
  always its project's id (`ScriptableProjectWindow.swift`).
- **window-degrades-when-controller-is-gone**: Because `controller` is held
  `weak`, every `ScriptableProjectWindow` property (`uniqueID`, `name`,
  `helpVisible`, `drawerTab`, `searchQuery`, `selectedTab`) MUST fall back to
  `""` (or `false` for `helpVisible`) rather than force-unwrap or crash once
  the underlying `ComposableTabsWindowController` has been deallocated
  (`ScriptableProjectWindow.swift`).
- **window-help-visible-round-trips**: `ScriptableProjectWindow.helpVisible`
  MUST get `controller.isHelpVisible` and MUST set through
  `controller.setHelpVisible(newValue)`, defaulting to `false` when
  `controller` is `nil` (`ScriptableProjectWindow.swift`).
- **window-drawer-tab-read-only**: `ScriptableProjectWindow.drawerTab` MUST
  expose `controller.helpDrawerTabID` as a read-only `String`, defaulting to
  `""`, and MUST NOT declare a setter — Help is documented as the only legal
  tab, so a setter would have exactly one legal value it could accept
  (`ScriptableProjectWindow.swift`).
- **window-search-query-round-trips**: `ScriptableProjectWindow.searchQuery`
  MUST get and set `controller.searchQuery` directly, so setting it MUST
  route through whatever `searchQuery`'s own setter on `ComposableTabsWindowController`
  does (routing the search), not merely record a string
  (`ScriptableProjectWindow.swift`).
- **window-selected-tab-round-trips**: `ScriptableProjectWindow.selectedTab`
  MUST get and set `controller.selectedTabIdentifier`, defaulting to `""`
  when `controller` is `nil` (`ScriptableProjectWindow.swift`).
- **window-object-specifier-key**: `ScriptableProjectWindow.objectSpecifier`
  MUST build its `NSScriptObjectSpecifier` via `applicationElementSpecifier(key:
  "projectWindows") { self.uniqueID }` (`ScriptableProjectWindow.swift`; see `agentictoolkit://recipes/foundation-scripting` for that
  helper's own contract).
- **tab-value-rebuilt-per-read**: `ScriptableProjectTab` MUST be constructed
  fresh on every `scriptingTabs`/`scriptableProjectTabs`/`scriptableProjectTab(uniqueID:)`
  call, with all six fields (`id`, `title`, `edges`, `project`,
  `workingDirectory`, `branch`) fixed at `init` and never mutated afterward —
  it is a value snapshot, not a cache that a later tab rename would have to
  invalidate (`ScriptableProjectTab.swift`).
- **tab-id-is-the-group-id**: `ScriptableProjectTab.uniqueID` MUST be the tab
  *group's* id (the persisted `project_tabs.group_id`), never a per-edge
  member row's id, because one project-level tab drawn on several edges is
  one tab to a script, not one per edge (`ScriptableProjectTab.swift`).
- **tab-edges-may-be-empty**: `ScriptableProjectTab.tabEdges` MUST report the
  current set of edges that tab group is drawn on, and an empty array MUST be
  a valid result when every edge the group could draw on has been disabled
  (`ScriptableProjectTab.swift`).
- **tab-branch-empty-when-unresolved**: `ComposableTabsWindowController.scriptingTabs(branch:)`
  (the direct caller of the closure this extension supplies) MUST fold a
  `nil` branch result to the empty string `""` on the `ScriptableProjectTab`
  it builds (`ComposableTabsWindowController.swift`'s `branch(directory)
  ?? ""`), so a directory that resolves to no `ProjectController`, no
  `BranchController` for that directory, or a `BranchController` whose
  checkout is on a detached HEAD (`currentBranch == nil`, see
  `agentictoolkit://recipes/git-client-projects-branch-controller`) all
  collapse to the same observable value: an empty string, never `nil`
  stringified and never a thrown error.
- **tab-object-specifier-key**: `ScriptableProjectTab.objectSpecifier` MUST
  build its `NSScriptObjectSpecifier` via `applicationElementSpecifier(key:
  "projectTabs") { self.uniqueID }` (`ScriptableProjectTab.swift`).
- **pane-requires-its-enumerating-window**: `ScriptablePane.init(pane:in:)`
  MUST take the `ComposableTabsWindowController` the pane was found in as a
  required, non-optional parameter — a pane behind a background tab has
  never been in a view hierarchy, so a wrapper left to discover its own
  window through the view would report an empty project and tab for most
  panes in a real window (`ScriptablePane.swift`).
- **pane-view-controller-held-strongly-window-held-weakly**: `ScriptablePane`
  MUST hold its wrapped `ComposableTabsPaneViewController` (`pane`) strongly
  and its enumerating `window` weakly — the opposite asymmetry from
  `ScriptableProjectWindow`, which holds its controller weakly
  (`ScriptablePane.swift`).
- **pane-project-and-tab-derived-live**: `ScriptablePane.paneProject` MUST
  return `self.window?.project.displayName ?? ""`, and `ScriptablePane.paneTab`
  MUST return `self.window?.tabGroup(containing: self.pane)?.title ?? ""`,
  both computed fresh from the tagged window on every access rather than
  captured once at enumeration time (`ScriptablePane.swift`).
- **pane-selection-empty-when-nothing-selected**: `ScriptablePane.paneSelection`
  MUST return `self.pane.selectionDescription ?? ""`, treating "nothing
  selected" as the empty string rather than a missing value
  (`ScriptablePane.swift`).
- **pane-minimized-is-edge-name-or-no**: `ScriptablePane.paneMinimized` MUST
  return `self.pane.minimizedEdge?.rawValue ?? "no"` — one string, not a
  boolean plus an edge, because "minimized" and "minimized where" are one
  fact that two separate properties could disagree about
  (`ScriptablePane.swift`).
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

## Appearance

Not applicable — this is a scripting-registry extension and three data
wrapper classes, not a visual component.

## States

Not applicable — this is a scripting-registry extension and three data
wrapper classes, not a visual component. The one state this file surfaces
that resembles a state machine — a tab's resolved git branch, including the
"no branch resolves" case — is covered under Behavioral Requirements
(**tab-branch-empty-when-unresolved**), not here.

## Accessibility

Not applicable — this is a scripting-registry extension and three data
wrapper classes with no view of their own; the panes, tabs and windows they
describe render through `ComposableTabsWindowController` and
`ComposableTabsPaneViewController`, neither of which this file draws.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-scripting-001 | window-enumeration-order, tab-enumeration-nests-by-window, pane-enumeration-tags-source-window | Adopt one controller with its default one-tab, one-edge, one-pane layout, then call `.setEdgeEnabled(.right, true)` (`testTheManagerListsWindowsTabsAndPanes`). | Before the edge change: `scriptableProjectWindows.count == 1`, `scriptableProjectTabs.count == 1`, `scriptablePanes.count == 1`. After enabling the second edge: `scriptableProjectTabs.count` is still `1` (one tab group drawn twice), `scriptablePanes.count == 2`. |
| git-client-scripting-002 | pane-lookup-short-circuits, pane-lookup-miss-returns-nil | Adopt a controller, take its one pane's `nodeID`, call `scriptablePane(uniqueID:)` with that id and then with `UUID().uuidString` (`testTheManagerFindsAPaneByItsID`). | The first call returns a wrapper whose `uniqueID` equals the pane's `nodeID.uuidString`; the second call returns `nil`. |
| git-client-scripting-003 | window-lookup-miss-returns-nil, tab-lookup-miss-returns-nil, window-id-is-project-id | Adopt a project named `"api-server"`; call `scriptableProjectWindow(uniqueID:)` with the project's id and with a random `UUID().uuidString`; call `scriptableProjectTab(uniqueID:)` with a real tab id and a random one (`testTheManagerFindsATabAndAWindowByID`). | The real-id calls return non-nil wrappers (`scriptableProjectWindow(uniqueID:)?.name == "api-server"`); both random-id calls return `nil`. |
| git-client-scripting-004 | tab-branch-resolver-wiring, tab-branch-empty-when-unresolved | Persist one tab with `workingDirectory` set to a fixture directory; call `controller.scriptingTabs(branch: { $0 == directory ? "feature" : nil })` (`testATabReportsItsWorkingDirectoryAndBranch`). | `tabs.map(\.tabBranch) == ["feature"]`; `tabs.map(\.tabWorkingDirectory) == [directory.path]`. |
| git-client-scripting-005 | tab-branch-empty-when-unresolved | Call `controller.scriptingTabs(branch: { _ in nil })` on the default single-tab project (`testATabWithNoBranchReportsAnEmptyString`). | `tabs.count == 1`; `tabs.map(\.tabBranch) == [""]`, never `nil` or a crash. |
| git-client-scripting-006 | tab-id-is-the-group-id, pane-project-and-tab-derived-live | Build a controller with two project tabs, adopt it for scripting, read `scriptablePanes` (`testAPaneOnABackgroundTabStillNamesItsProjectAndTab`). | `panes.count == 2`; `panes.map(\.paneProject) == ["api-server", "api-server"]`; `panes.map(\.paneTab) == ["Tab 1", "Tab 2"]` — including the pane on the tab that is not front-most. |
| git-client-scripting-007 | pane-minimized-is-edge-name-or-no | On a fresh pane, read `paneMinimized`; call `pane.setMinimized(to: .leading)` and read again; call `pane.setMinimized(to: nil)` and read again (`testMinimizedIsTheEdgeNameOrNo`). | Readings are `"no"`, then `"leading"`, then `"no"`. |
| git-client-scripting-008 | pane-unrecognized-edge-restores-rather-than-guesses | Minimize a pane `to: "leading"`, confirm `paneMinimized == "leading"`, then call `minimizePane(to: "sideways")` (`testAnUnknownEdgeNameRestoresRatherThanGuessing`). | After the unrecognized edge name, `paneMinimized == "no"` — the pane is restored, not left minimized to a guessed edge. |
| git-client-scripting-009 | pane-actions-delegate-to-host-and-may-be-declined | On a controller whose single tab has exactly one pane (the layout spec's last-pane veto applies), call `scriptable.closePane()` (`testAHostThatRefusesLeavesThePaneWhereItWas`, adapted: a single-pane tab's close request). | `controller.allPanes().count` is unchanged — the host declined the close, and `closePane()` itself raises no error for the decline. |
| git-client-scripting-010 | window-degrades-when-controller-is-gone | Construct a `ScriptableProjectWindow(controller:)`, then release every strong reference to that controller so the weak `controller` becomes `nil`, then read `uniqueID`, `name`, `helpVisible`, `drawerTab`, `searchQuery` and `selectedTab`. | Every property returns its documented fallback (`""` for the five string properties, `false` for `helpVisible`) with no crash; `ProjectScriptingTests.swift` exercises every other `ScriptableProjectWindow` property but not this deallocated-controller path (see Compliance, unit-test-coverage). |

## Edge Cases

- **Null and empty input**: No open project windows leaves `scriptableProjectWindows`,
  `scriptableProjectTabs` and `scriptablePanes` all empty arrays, and every
  `*(uniqueID:)` lookup returns `nil` (MUST; the enumerations and lookups are
  plain `map`/`flatMap`/`first` over `openWindowControllers`, which is itself
  `[]` when nothing is open). A `uniqueID` argument that is the empty string
  or any other non-matching string is handled by the same string-equality
  comparison as any other miss — it MUST return `nil`, never throw (MUST, see
  **window-lookup-miss-returns-nil**, **tab-lookup-miss-returns-nil**,
  **pane-lookup-miss-returns-nil**).
- **Boundary values**: A tab group MAY be drawn on zero edges
  (**tab-edges-may-be-empty**) after every edge is disabled, in which case
  `scriptablePanes` for that tab group's window contributes zero panes for
  that tab while `scriptableProjectTabs` still lists the tab itself (MUST).
  There is no maximum enforced on the number of open windows, tabs per
  window, or panes per tab in this file — enumeration is a linear walk with
  no capacity limit.
- **Concurrent access**: Every operation in this file, and on all three
  wrapper types, is confined to the main actor (MUST, see
  **main-actor-confinement**); Cocoa Scripting itself dispatches command
  handlers on the main thread (see `agentictoolkit://recipes/foundation-scripting`),
  so no two enumerations or lookups from this surface can interleave with
  each other or with a window opening or closing. There is no lock, queue, or
  actor state defined in this file itself — main-actor confinement is the
  entire concurrency story.
- **Error states**: This file defines no `throws` function and surfaces no
  `Error` type of its own. A branch that cannot be resolved — no
  `ProjectController` for the window, no `BranchController` for the
  directory, or a detached-HEAD checkout — is not an error condition here;
  it is folded to the empty string before it would ever reach this file's
  callers (MUST, see **tab-branch-empty-when-unresolved**). Any
  `GitClientError` a git subprocess could raise is fully absorbed inside
  `BranchController.refresh()` before `currentBranch` is ever read by this
  extension (see `agentictoolkit://recipes/git-client-projects-branch-controller`);
  none of it is observable through `ScriptableProjectTab.tabBranch`.
- **Offline or disconnected state**: Not applicable in the network sense —
  nothing in `ProjectWindowManager+Scripting.swift` makes a network call.
  Git itself is local-only, and even that local subprocess call happens one
  layer below this file, inside `BranchController`/`GitClient`; this
  extension only reads an already-resolved `currentBranch` snapshot.
- **A pane, tab or window that has closed between enumeration and use**: A
  `ScriptableProjectWindow`'s `weak var controller` MAY become `nil` between
  when a script is handed the wrapper and when it reads a property from it,
  because a script "can keep a reference to a window it then closes"
  (`ScriptableProjectWindow.swift`); every property degrades to its
  documented fallback rather than crashing (MUST, see
  **window-degrades-when-controller-is-gone**). `ScriptablePane.isInWindow`
  exists specifically because `closePane()`'s effect can be silently
  declined by the host, so "the request was delivered" and "the pane is
  gone" are answered by two different questions (MUST, see
  **pane-is-in-window-reasks-live-membership**).

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

## Deep Linking

Not applicable: `ProjectWindowManager+Scripting.swift` defines no URL scheme
or navigation route. The `uniqueID`-keyed `NSScriptObjectSpecifier` each
wrapper's `objectSpecifier` builds is a Cocoa Scripting (AppleScript) object
address, not an app deep link.

## Localization

Not applicable: `ProjectWindowManager+Scripting.swift` and the three wrapper
types produce no literal user-facing English string of their own. Every
fallback value (`""`, `false`, `"no"`) is an absence marker for a missing
controller, window, selection, or branch, not translatable text; the strings
these wrappers surface (a project's display name, a tab's title, a pane's
selection description) are already-localized (or user-authored) data owned
by other components.

## Accessibility Options

Not applicable: this file renders nothing itself. Reduce Motion, Increase
Contrast and Differentiate Without Color are concerns of the window, tab and
pane views this extension only describes, not of the extension or its three
data wrappers.

## Feature Flags

Not applicable: `ProjectWindowManager+Scripting.swift` contains no
feature-flag or build-configuration check.

## Analytics

Not applicable: `ProjectWindowManager+Scripting.swift` makes no analytics or
event-tracking call.

## Privacy

Not applicable: the data this file exposes — a project's display name and
persisted id, a tab's title, working-directory path and git branch name, and
a pane's selection description — is the same data already visible to the
user in the project window itself. This file reads, stores and transmits no
credential, token, or data the user has not already been shown; it makes no
network transmission at all.

## Logging

`ProjectWindowManager+Scripting.swift` and the three wrapper types make no
logging call — no `Logger`, `os.Logger`, or `print` appears in any of the
four files. A branch that fails to resolve is not logged here at all; any
underlying git failure is recorded once, upstream, in `GitCommandLog` via
`GitClient.execute` (see `agentictoolkit://recipes/git-client-projects-branch-controller`),
not a second time by this extension.

| Event | Level | Message |
|-------|-------|---------|
| (none) | — | This file and its three wrapper types emit no log messages. |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

Notes: separation-of-concerns passes because
`ProjectWindowManager+Scripting.swift` and its three wrapper types own only
enumeration, lookup, and Cocoa Scripting addressing; they delegate every
piece of domain behavior to a collaborator — git branch resolution to
`ProjectController`/`BranchController`, pane mutation to `pane.host`, window
mutation to `ComposableTabsWindowController` — and, per `ScriptablePane.swift`'s
own doc comment, exist as wrappers specifically so that "KVC scripting keys"
never get "pinned onto the view controller" itself. unit-test-coverage
is partial: `ProjectScriptingTests.swift` (30 test methods) exercises window,
tab and pane enumeration and lookup including unknown-id misses, branch
resolution both matching and unmatched, the one-tab-two-panes multi-edge
case, pane property reporting (name, selection, project, tab, minimized,
zoomed), the unrecognized-edge-name restore path, and a host-declined
minimize — but no test deallocates a `ScriptableProjectWindow`'s `controller`
and reads its properties afterward (see **window-degrades-when-controller-is-gone**),
so that specific fallback path is verified only by reading the source, not by
a passing test. graceful-degradation passes because every optional chain in
these four files — a deallocated window controller, a missing project
controller, a missing branch controller, a detached-HEAD branch, an unknown
lookup id, a malformed edge name — resolves to a documented default
(`""`, `false`, `"no"`, or `nil`) rather than crashing or propagating an
error.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
