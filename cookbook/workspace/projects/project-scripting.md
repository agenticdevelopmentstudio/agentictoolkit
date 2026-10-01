---
id: ccb08e0d-f505-4195-adf8-d8ac9208b24c
title: Project Scripting
domain: agentictoolkit://cookbook/workspace/projects/project-scripting
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The scripting surface for project windows: enumerating and looking
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
depends-on:
- agentictoolkit://cookbook/system/scripting
- agentictoolkit://cookbook/ui/layout/composable-tabs/tabs-window
- agentictoolkit://cookbook/workspace/projects/project-controller
- agentictoolkit://cookbook/workspace/projects/branch-controller
related:
- agentictoolkit://cookbook/ui/layout/composable-tabs/leaf-pane-view
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

# Project Scripting

## Overview

This is the scripting surface that answers everything the AppleScript scripting layer
asks about project windows, tabs and panes: three enumerated
lists (scriptable project windows, scriptable project tabs, scriptable
panes) and three id-based lookups, one per kind. It hangs off the project
window manager rather than a separate registry because that manager is
already the answer to "which project windows are open." Its one piece of
domain logic beyond enumeration is git: resolving each tab's working
directory to a live branch name by reaching through the project
controller's branch controller for that directory — the branch a project
tab's `branch` property exposes to a script. The surface itself constructs
three wrapper values it does not define — a scriptable project window, a
scriptable project tab, and a scriptable pane — whose own properties this
recipe also specifies, because no other recipe yet owns them.

## Behavioral Requirements

The property and command names below — `uniqueID`, `name`, `helpVisible`,
`drawerTab`, `searchQuery`, `selectedTab`, `tabEdges`, `branch`,
`paneProject`, `paneTab`, `paneSelection`, `paneMinimized`, `closePane`,
`zoomPane`, `minimizePane(to:)` — and the specifier keys `projectWindows`,
`projectTabs`, `panes` are the AppleScript dictionary
vocabulary this surface implements; they are this concept's external
interface and are used throughout as such.

- **window-enumeration-order**: the window enumeration MUST map every open
  window, in the order those windows were opened (not any incidental
  storage order), to one scriptable-project-window wrapper.
- **window-enumeration-recomputed**: the window enumeration MUST be
  recomputed fresh on every access, with no backing cache, so a window
  opened or closed between two reads MUST be reflected in the very next
  read.
- **window-lookup-short-circuits**: the window lookup MUST search the open
  windows in order and stop at the first wrapper whose `uniqueID` equals
  the argument, so a match at position *n* MUST NOT cause a wrapper to be
  constructed for any window after it.
- **window-lookup-miss-returns-nil**: the window lookup MUST return no
  result when no open window's `uniqueID` equals the argument, including
  when the argument is not a well-formed identifier string — the search is
  a plain string comparison, not an identifier parse, so it MUST NOT throw
  or crash on a malformed argument.
- **tab-enumeration-nests-by-window**: the tab enumeration MUST flatten
  every window's tabs into one list, windows in open order and, within one
  window, in that window's own tab-group order.
- **tab-branch-resolver-wiring**: the tab enumeration for one window MUST
  look up that window's project controller once, and MUST resolve each
  tab's `branch` by evaluating, for that tab's working directory, the
  project controller's branch controller's current branch for that
  directory.
- **tab-branch-nil-for-adopted-windows**: because a window that was adopted
  for scripting rather than opened by this surface has no project
  controller, every tab belonging to an adopted-only window MUST resolve
  its `branch` to no result, which is then reported as the empty string
  (see **tab-branch-empty-when-unresolved**).
- **tab-lookup-short-circuits**: the tab lookup MUST walk every window's
  tabs in enumeration order and stop at the first tab whose `uniqueID`
  equals the argument, so tabs in windows after the match MUST NOT be
  built.
- **tab-lookup-miss-returns-nil**: the tab lookup MUST return no result
  when no open tab's `uniqueID` equals the argument.
- **pane-enumeration-tags-source-window**: the pane enumeration MUST
  flatten every window's panes into one list, and for each window MUST tag
  every pane's wrapper with the exact window it was enumerated from,
  rather than leaving the wrapper to discover its own window.
- **pane-lookup-short-circuits**: the pane lookup MUST walk every window's
  panes in enumeration order and stop at the first pane whose `uniqueID`
  equals the argument.
- **pane-lookup-miss-returns-nil**: the pane lookup MUST return no result
  when no open pane's `uniqueID` equals the argument.
- **main-thread-confinement**: every operation in this surface, and every
  member of the three wrapper types, MUST run on the UI's main execution
  context; none of the four types MUST be called from any other execution
  context.
- **window-id-is-project-id**: the scriptable window's `uniqueID` MUST
  return its underlying window's project id, falling back to the empty
  string when the underlying window no longer exists — the persisted
  `git_repo.id`, so one window's id is always its project's id.
- **window-degrades-when-controller-is-gone**: because the wrapper holds
  its underlying window only weakly, every scriptable-window property
  (`uniqueID`, `name`, `helpVisible`, `drawerTab`, `searchQuery`,
  `selectedTab`) MUST fall back to the empty string (or to `false` for
  `helpVisible`) rather than crash once the underlying window has been
  deallocated.
- **window-help-visible-round-trips**: the scriptable window's
  `helpVisible` MUST read and write the underlying window's
  help-visibility state directly, defaulting to `false` when the
  underlying window no longer exists.
- **window-drawer-tab-read-only**: the scriptable window's `drawerTab` MUST
  expose the underlying window's help-drawer tab identifier as read-only,
  defaulting to the empty string, and MUST NOT accept a new value — Help
  is documented as the only legal tab, so accepting a value would have
  exactly one legal value it could accept.
- **window-search-query-round-trips**: the scriptable window's
  `searchQuery` MUST read and write the underlying window's search query
  directly, so setting it MUST route through whatever the underlying
  window's own search-query update does (routing the search), not merely
  record a string.
- **window-selected-tab-round-trips**: the scriptable window's
  `selectedTab` MUST read and write the underlying window's selected-tab
  identifier, defaulting to the empty string when the underlying window no
  longer exists.
- **window-object-specifier-key**: the scriptable window's object
  specifier MUST be built under the `projectWindows` collection key,
  addressed by its `uniqueID` (see `agentictoolkit://cookbook/system/scripting`
  for that mechanism's own contract).
- **tab-value-rebuilt-per-read**: the scriptable tab MUST be constructed
  fresh on every enumeration or lookup call, with all six fields (`id`,
  `title`, `edges`, `project`, `workingDirectory`, `branch`) fixed at
  construction and never mutated afterward — it is a value snapshot, not a
  cache that a later tab rename would have to invalidate.
- **tab-id-is-the-group-id**: the scriptable tab's `uniqueID` MUST be the
  tab group's id (the persisted `project_tabs.group_id`), never a per-edge
  member row's id, because one project-level tab drawn on several edges is
  one tab to a script, not one per edge.
- **tab-edges-may-be-empty**: the scriptable tab's `tabEdges` MUST report
  the current set of edges that tab group is drawn on, and an empty list
  MUST be a valid result when every edge the group could draw on has been
  disabled.
- **tab-branch-empty-when-unresolved**: the tab-branch resolution MUST fold
  a missing branch result to the empty string on the scriptable tab it
  builds, so a directory that resolves to no project controller, no branch
  controller for that directory, or a branch controller whose checkout is
  on a detached HEAD (no current branch, see
  `agentictoolkit://cookbook/workspace/projects/branch-controller`) all
  collapse to the same observable value: an empty string, never a null
  stringified and never a thrown error.
- **tab-object-specifier-key**: the scriptable tab's object specifier MUST
  be built under the `projectTabs` collection key, addressed by its
  `uniqueID`.
- **pane-requires-its-enumerating-window**: constructing a scriptable pane
  MUST take the window it was found in as a required parameter — a pane
  behind a background tab has never been part of a rendered view
  hierarchy, so a wrapper left to discover its own window through the view
  would report an empty project and tab for most panes in a real window.
- **pane-view-controller-held-strongly-window-held-weakly**: the scriptable
  pane MUST hold its wrapped pane strongly and its enumerating window
  weakly — the opposite asymmetry from the scriptable window, which holds
  its underlying window weakly.
- **pane-project-and-tab-derived-live**: the scriptable pane's
  `paneProject` MUST return its tagged window's project display name,
  falling back to the empty string, and `paneTab` MUST return the title of
  the tab group containing that pane, falling back to the empty string,
  both computed fresh from the tagged window on every access rather than
  captured once at enumeration time.
- **pane-selection-empty-when-nothing-selected**: the scriptable pane's
  `paneSelection` MUST return the pane's selection description, treating
  "nothing selected" as the empty string rather than a missing value.
- **pane-minimized-is-edge-name-or-no**: the scriptable pane's
  `paneMinimized` MUST return the name of the edge it is minimized to, or
  "no" — one string, not a flag plus an edge, because "minimized" and
  "minimized where" are one fact that two separate properties could
  disagree about.
- **pane-unrecognized-edge-restores-rather-than-guesses**: the scriptable
  pane's `minimizePane(to:)` MUST parse the edge name it is given; when
  that parse fails, it MUST request the pane be restored rather than guess
  an edge, and when it succeeds it MUST request the pane be minimized to
  that edge.
- **pane-actions-delegate-to-host-and-may-be-declined**: `closePane()`,
  `zoomPane()` and `minimizePane(to:)` MUST each forward the request to
  the pane's host and MUST NOT implement any part of that effect
  themselves — a script closing or minimizing a pane goes through exactly
  the path the close button or the title-bar arrow takes, and that host
  MAY decline the request.
- **pane-is-in-window-reasks-live-membership**: the scriptable pane's
  `isInWindow` MUST return `false` when the tagged window no longer
  exists, and otherwise MUST return whether that one window's current pane
  list still contains this pane by identity — asking that one window's
  current pane list, not re-running the pane lookup across every open
  project, because a pane cannot have moved to a different window between
  a request and this question.
- **pane-object-specifier-key**: the scriptable pane's object specifier
  MUST be built under the `panes` collection key, addressed by its
  `uniqueID`.

## Appearance

Not applicable — this is a scripting surface and three data wrapper types,
not a visual component.

## States

Not applicable — this is a scripting surface and three data wrapper types,
not a visual component. The one state this surface exposes that resembles
a state machine — a tab's resolved git branch, including the "no branch
resolves" case — is covered under Behavioral Requirements
(**tab-branch-empty-when-unresolved**), not here.

## Accessibility

Not applicable — this is a scripting surface and three data wrapper types
with no view of their own; the panes, tabs and windows they describe
render through the tabs window controller and its pane view controller,
neither of which this surface draws.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-scripting-001 | window-enumeration-order, tab-enumeration-nests-by-window, pane-enumeration-tags-source-window | Adopt one controller with its default one-tab, one-edge, one-pane layout, then enable a second edge. | Before the edge change: one scriptable window, one scriptable tab, one scriptable pane. After enabling the second edge: still one scriptable tab (one tab group drawn twice), but two scriptable panes — ProjectScriptingTests.swift › testTheManagerListsWindowsTabsAndPanes |
| git-client-scripting-002 | pane-lookup-short-circuits, pane-lookup-miss-returns-nil | Adopt a controller, take its one pane's identifier, look up a scriptable pane by that id and then by a random, unused id. | The first lookup returns a wrapper whose `uniqueID` equals the pane's identifier; the second lookup returns no result — ProjectScriptingTests.swift › testTheManagerFindsAPaneByItsID |
| git-client-scripting-003 | window-lookup-miss-returns-nil, tab-lookup-miss-returns-nil, window-id-is-project-id | Adopt a project named `api-server`; look up a scriptable window by the project's id and by a random, unused id; look up a scriptable tab by a real tab id and by a random, unused id. | The real-id lookups return non-empty wrappers (the window's `name` equals `api-server`); both random-id lookups return no result — ProjectScriptingTests.swift › testTheManagerFindsATabAndAWindowByID |
| git-client-scripting-004 | tab-branch-resolver-wiring, tab-branch-empty-when-unresolved | Persist one tab with its working directory set to a fixture directory; resolve branches so that directory alone reports `feature`. | The tab's `branch` is `feature`; the tab's working directory matches the fixture directory — ProjectScriptingTests.swift › testATabReportsItsWorkingDirectoryAndBranch |
| git-client-scripting-005 | tab-branch-empty-when-unresolved | Resolve every branch to no result on the default single-tab project. | There is exactly one tab, and its `branch` is the empty string, never a null result or a crash — ProjectScriptingTests.swift › testATabWithNoBranchReportsAnEmptyString |
| git-client-scripting-006 | tab-id-is-the-group-id, pane-project-and-tab-derived-live | Build a controller with two project tabs, adopt it for scripting, read the scriptable panes. | There are two panes; both report `paneProject` as `api-server`; `paneTab` reads `Tab 1` and `Tab 2` respectively — including the pane on the tab that is not front-most — ProjectScriptingTests.swift › testAPaneOnABackgroundTabStillNamesItsProjectAndTab |
| git-client-scripting-007 | pane-minimized-is-edge-name-or-no | On a fresh pane, read `paneMinimized`; minimize it to the leading edge and read again; restore it and read again. | Readings are `no`, then `leading`, then `no` — ProjectScriptingTests.swift › testMinimizedIsTheEdgeNameOrNo |
| git-client-scripting-008 | pane-unrecognized-edge-restores-rather-than-guesses | Minimize a pane to the leading edge, confirm `paneMinimized` reads `leading`, then request minimizing to an unrecognized edge name. | After the unrecognized edge name, `paneMinimized` reads `no` — the pane is restored, not left minimized to a guessed edge — ProjectScriptingTests.swift › testAnUnknownEdgeNameRestoresRatherThanGuessing |
| git-client-scripting-009 | pane-actions-delegate-to-host-and-may-be-declined | On a controller whose single tab has exactly one pane (the layout's last-pane veto applies), request that the pane close. | The pane count is unchanged — the host declined the close, and the close request itself raises no error for the decline — ProjectScriptingTests.swift › testAHostThatRefusesLeavesThePaneWhereItWas (adapted for a single-pane tab's close request) |
| git-client-scripting-010 | window-degrades-when-controller-is-gone | Construct a scriptable window, then release every reference to its underlying window so the weak reference resolves to nothing, then read `uniqueID`, `name`, `helpVisible`, `drawerTab`, `searchQuery` and `selectedTab`. | Every property returns its documented fallback (the empty string for the five string properties, `false` for `helpVisible`) with no crash; ProjectScriptingTests.swift exercises every other scriptable-window property but not this deallocated-window path (see Compliance, unit-test-coverage). |

## Edge Cases

- **Null and empty input**: No open project windows leaves the window,
  tab, and pane enumerations all empty, and every id-based lookup returns
  no result (MUST; the enumerations and lookups are plain walks over the
  open windows, which is itself empty when nothing is open). A `uniqueID`
  argument that is the empty string or any other non-matching string is
  handled by the same string-equality comparison as any other miss — it
  MUST return no result, never throw (MUST, see
  **window-lookup-miss-returns-nil**, **tab-lookup-miss-returns-nil**,
  **pane-lookup-miss-returns-nil**).
- **Boundary values**: A tab group MAY be drawn on zero edges
  (**tab-edges-may-be-empty**) after every edge is disabled, in which case
  the pane enumeration for that tab group's window contributes zero panes
  for that tab while the tab enumeration still lists the tab itself
  (MUST). There is no maximum enforced on the number of open windows, tabs
  per window, or panes per tab — enumeration is a linear walk with no
  capacity limit.
- **Concurrent access**: Every operation in this surface, and on all three
  wrapper types, is confined to the UI's main execution context (MUST, see
  **main-thread-confinement**); the AppleScript scripting layer itself dispatches command
  handlers on the main thread (see
  `agentictoolkit://cookbook/system/scripting`), so no two enumerations or
  lookups from this surface can interleave with each other or with a
  window opening or closing. There is no lock, queue, or independent
  concurrency state defined here — main-thread confinement is the entire
  concurrency story.
- **Error states**: This surface defines no throwing operation and
  surfaces no error type of its own. A branch that cannot be resolved — no
  project controller for the window, no branch controller for the
  directory, or a detached-HEAD checkout — is not an error condition here;
  it is folded to the empty string before it would ever reach a caller
  (MUST, see **tab-branch-empty-when-unresolved**). Any error a git
  subprocess could raise is fully absorbed inside the branch controller's
  own refresh operation before its current branch is ever read by this
  surface (see `agentictoolkit://cookbook/workspace/projects/branch-controller`);
  none of it is observable through the scriptable tab's `branch`.
- **Offline or disconnected state**: Not applicable in the network sense —
  nothing here makes a network call. Git itself is local-only, and even
  that local subprocess call happens one layer below this surface, inside
  the branch controller; this surface only reads an already-resolved
  current-branch snapshot.
- **A pane, tab or window that has closed between enumeration and use**: A
  scriptable window's underlying window MAY become unavailable between
  when a script is handed the wrapper and when it reads a property from
  it, because a script "can keep a reference to a window it then closes";
  every property degrades to its documented fallback rather than crashing
  (MUST, see **window-degrades-when-controller-is-gone**). The scriptable
  pane's `isInWindow` exists specifically because a close request's effect
  can be silently declined by the host, so "the request was delivered"
  and "the pane is gone" are answered by two different questions (MUST,
  see **pane-is-in-window-reasks-live-membership**).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `uniqueID` (lookup argument, shared by the window, tab, and pane lookups) | string | none — required | The id a script is asking for; compared by plain string equality against each wrapper's `uniqueID`, with no identifier-format validation of the argument itself. |
| `edgeName` (argument to the scriptable pane's `minimizePane(to:)`) | string | none — required | Parsed against the recognized edge names; any string that is not a recognized edge name is treated as a restore request, not an error. |
| the shared project window registry (ambient) | singleton | the shared registry | The sole registry this surface reads (the set of open windows, and each window's project controller); no dependency is injected into any operation here. |
| branch-resolution function (internal to the tab enumeration) | directory-to-branch-name function | resolves a tab's working directory through its window's project controller's branch controller | Not caller-configurable — this exact resolution is what this surface supplies to the tab-building step on every call. |

This surface reads no environment variable and no settings key of its own;
the underlying window/tab/pane state it enumerates is populated elsewhere,
by opening a project and by adopting a window for scripting, neither of
which is a concern of this recipe.

## Deep Linking

Not applicable: this surface defines no URL scheme or navigation route.
The `uniqueID`-keyed object specifier each wrapper's `objectSpecifier`
builds is an AppleScript object address, not an app deep
link.

## Localization

Not applicable: this surface and the three wrapper types produce no
literal user-facing English string of their own. Every fallback value (the
empty string, `false`, `"no"`) is an absence marker for a missing window,
selection, or branch, not translatable text; the strings these wrappers
surface (a project's display name, a tab's title, a pane's selection
description) are already-localized (or user-authored) data owned by other
components.

## Accessibility Options

Not applicable: nothing here renders anything itself. Reduce Motion,
Increase Contrast and Differentiate Without Color are concerns of the
window, tab and pane views this surface only describes, not of the surface
or its three data wrappers.

## Feature Flags

Not applicable: this surface contains no feature-flag or
build-configuration check.

## Analytics

Not applicable: this surface makes no analytics or event-tracking call.

## Privacy

Not applicable: the data this surface exposes — a project's display name
and persisted id, a tab's title, working-directory path and git branch
name, and a pane's selection description — is the same data already
visible to the user in the project window itself. This surface reads,
stores and transmits no credential, token, or data the user has not
already been shown; it makes no network transmission at all.

## Logging

This surface and the three wrapper types make no logging call. A branch
that fails to resolve is not logged here at all; any underlying git
failure is recorded once, upstream, by the git command log (see
`agentictoolkit://cookbook/workspace/projects/branch-controller`), not a
second time by this surface.

| Event | Level | Message |
|-------|-------|---------|
| (none) | — | This surface and its three wrapper types emit no log messages. |

## Platform Notes

- **SwiftUI**: The source is `packages/apple/AgenticToolkit/macOS/Features/Projects/Scripting/ProjectWindowManager+Scripting.swift`,
  plus the three wrapper types under `macOS/UI/ViewControllers/ComposableTabs/Scripting/`,
  all built on `AppKit` (`NSObject`, `NSScriptObjectSpecifier`) and
  `AgenticToolkitCore`/`AgenticToolkitMacOS` (`ProjectWindowManager`,
  `ComposableTabsWindowController`, `ProjectController`, `BranchController`).
  `ProjectWindowManager` is declared `@MainActor` with no `Sendable`
  conformance, and each of the three wrapper classes independently repeats
  the `@MainActor` declaration on itself, enforcing main-thread
  confinement at compile time. None of the four files uses SwiftUI; a
  SwiftUI-hosted project window would still need this same
  `NSObject`-based Cocoa Scripting bridge, since
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
  `agentictoolkit://cookbook/workspace/projects/branch-controller`), folding
  a `null` result to `string.Empty` at the same point `ComposableTabsWindowController.scriptingTabs(branch:)`
  does, and enforce main-thread confinement with `DispatcherQueue` in place
  of `@MainActor`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/Scripting/ProjectWindowManager+Scripting.swift` |

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
documented in `agentictoolkit://cookbook/workspace/projects/branch-controller`.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
