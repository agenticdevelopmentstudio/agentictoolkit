---
id: ab6d7655-9476-4318-8c36-f431686e2d23
title: File Browser View Controller
domain: agentictoolkit://cookbook/macos/ui/view-controllers/file-browser/file-browser-view-controller
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'AppKit view controller: a directory tree plus an add/remove footer, one
  FileTreeManager per root, watched only while visible.'
platforms:
- swift
- macos
tags:
- file-browser
- tree-view
- view-controller
- macos
depends-on:
- agentictoolkit://cookbook/macos/ui/view-controllers/file-browser/views/file-tree-outline-view-controller
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# File Browser View Controller

## Overview

`FileBrowserViewController` is an `NSViewController` that shows a directory
tree (via a hosted `FileTreeOutlineViewController`) plus a footer strip with
`+`/`−` buttons for adding and removing extra root directories. It owns one
`FileTreeManager` per root directory shown (the primary root plus any the user
adds), starts and stops each manager's filesystem watching in step with the
view's appearance, and forwards selection and open-file events to a host
through injected shared objects (`FileBrowserSelection`,
`FileBrowserRestorationState`, `FileBrowserDirectories`) and closures
(`onOpenRequest`, `onPaneSelectionChange`). It can be dropped into any AppKit
container — a document pane, a sidebar, a window — with no assumptions about
what hosts it.

## Behavioral Requirements

- **tree-divider-footer-layout**: The component MUST arrange, top to
  bottom, the file tree, a one-point separator (`NSBox` with `boxType:
  .separator`), and the add/remove footer, each pinned to the container's
  leading and trailing edges, filling the container's bounds.
- **window-background-fill**: The component MUST fill its root
  container with the `.windowBackground` theme role.
- **footer-surface-fill**: The component MUST fill the footer strip with the
  `.surface` theme role.
- **one-manager-per-root**: The component MUST maintain exactly one
  `FileTreeManager` for every URL currently in `directories.all`.
- **primary-root-always-managed**: The component's `manager` property MUST
  always resolve to a valid `FileTreeManager` for `directories.primary`; this
  invariant MUST hold for the lifetime of the controller (enforced with a
  `preconditionFailure` if it is ever violated, rather than silently
  constructing a throwaway manager).
- **start-watching-on-appear**: The component MUST start filesystem watching
  on every current manager when the view appears (`viewWillAppear`), if
  watching is not already active.
- **stop-watching-on-disappear**: The component MUST stop filesystem watching
  on every manager when the view disappears (`viewDidDisappear`).
- **stop-watching-on-pane-teardown**: The component MUST stop filesystem
  watching on every manager when `paneContentWillBeDiscarded()` is called,
  independent of whether `viewDidDisappear` has fired.
- **load-initial-once**: The component MUST call `loadInitial()` on every
  manager exactly once — the first time the view appears — and MUST NOT call
  it again on a later appearance of the same view.
- **add-directory-opens-panel**: Invoking `addDirectory()` MUST present an
  `NSOpenPanel` configured to choose one or more directories and no files
  (`canChooseDirectories: true`, `canChooseFiles: false`,
  `allowsMultipleSelection: true`).
- **add-directory-cancel-noop**: If the open panel is dismissed without a
  choice (any response other than `.OK`), the component MUST NOT change
  `directories`.
- **add-directory-skips-duplicates**: If a chosen directory is already one of
  `directories.all`, the component MUST leave `directories` unchanged for
  that directory and MUST NOT present an error.
- **add-directory-selects-last-added**: After adding one or more chosen
  directories, if the last chosen directory is a removable root (i.e. it is
  now in `directories.additional`), the component MUST set
  `selection.selectedRoot` to that directory.
- **add-directory-preserves-panel-order**: When `addDirectory()` adds more
  than one chosen directory from a single panel response, the component MUST
  add each one not already present in `directories.all`, in the same order
  `NSOpenPanel.urls` returns them.
- **remove-directory-requires-selected-root**: Invoking
  `removeSelectedDirectory()` while `selection.selectedRoot` is `nil` MUST
  call `RefusalFeedback.announce()` and MUST NOT change `directories` or
  `selection`.
- **remove-directory-requires-removable-root**: Invoking
  `removeSelectedDirectory()` while `selection.selectedRoot` is set to a URL
  that is not one of `directories.additional` (i.e. it is the primary root or
  already gone) MUST call `RefusalFeedback.announce()` and MUST NOT change
  `directories` or `selection`.
- **remove-directory-clears-selection**: After `directories.remove(_:)`
  succeeds for `selection.selectedRoot`, the component MUST set
  `selection.selectedRoot` to `nil`.
- **remove-button-enablement**: The remove button MUST be enabled only while
  `selection.selectedRoot` is a removable root, and MUST be disabled at every
  other time (no root selected, or the selected root is the primary or an
  already-removed root).
- **remove-button-tooltip**: While the remove button is enabled, its tooltip
  MUST read `Remove "<name>" from this project`, where `<name>` is the
  selected root's last path component; while disabled, its tooltip MUST read
  `Select an added directory to remove it`.
- **footer-buttons-identified**: The add button MUST carry the accessibility
  identifier `file-browser.add-directory` and the remove button MUST carry
  `file-browser.remove-directory`.
- **teardown-clears-orphaned-node-selection**: When a root is dropped from
  `directories.all` across a rebuild, the component MUST clear
  `selection.selectedNode` to `nil` if the selected node's URL lies at or
  under that root's path.
- **teardown-clears-orphaned-root-selection**: When a root is dropped from
  `directories.all` across a rebuild, the component MUST clear
  `selection.selectedRoot` to `nil` if it equals that root.
- **multi-pane-consistency**: When multiple browser panes share the same
  `FileBrowserDirectories`/`FileBrowserSelection`/`FileBrowserRestorationState`
  and one pane adds or removes a root, every other pane observing those
  shared objects SHOULD rebuild its own managers and clear any of its own
  selection state that pointed under the added/removed root (see
  **teardown-clears-orphaned-node-selection** and
  **teardown-clears-orphaned-root-selection**).
- **late-added-root-loads-if-visible**: A manager created for a root added
  after the browser's own initial load has completed MUST have
  `loadInitial()` called on it as part of the same rebuild.
- **late-added-root-watches-if-visible**: A manager created for a root added
  while the browser is currently watching MUST have `startWatching()` called
  on it as part of the same rebuild.
- **git-status-provider-reuse**: When constructing a manager for a root, the
  component MUST pass the injected `gitStatusProvider` to that manager only
  when the provider's `repoRoot`, resolved with `resolvingSymlinksInPath()`,
  equals the new root resolved the same way; otherwise it MUST pass `nil`.
- **open-request-forwarding**: Reading or writing `onOpenRequest` on the
  component MUST read or write the hosted tree's own `onOpenRequest`
  directly — there MUST NOT be a second, independent copy of this closure.
- **reveal-forwarding**: `reveal(_:)` and `revealNothing()` MUST delegate
  directly to the hosted tree's `reveal(_:)` and `revealNothing()`.
- **pane-selection-change-notification**: The component MUST call
  `onPaneSelectionChange` whenever `selection.selectedNode` changes to a
  value different from its immediately preceding value, MUST NOT call it for
  the value already held at the time the observer was installed, and MUST
  NOT call it when `selection.selectedNode` is set to the value it already
  holds.
- **pane-selection-description**: `paneSelectionDescription` MUST return the
  selected node's `name` (not its path), or `nil` when nothing is selected.
- **coder-init-unavailable**: `init(coder:)` MUST be marked unavailable at
  compile time and MUST call `fatalError` if somehow invoked at runtime.
- **reuse-managers-across-rebuild**: When rebuilding the manager list, the
  component SHOULD reuse the existing `FileTreeManager` instance for any root
  that is still present in `directories.all`, rather than discarding and
  recreating it.
- **single-root-convenience-init**: The component MAY be constructed with the
  `rootURL:` convenience initializer, which builds a `FileBrowserDirectories`
  with that URL as the sole primary root and no additional roots.

## Appearance

- **Corner radius**: None. The container, footer, and the add/remove buttons
  apply no corner radius in source (the buttons are plain `NSButton`s with
  `bezelStyle: .accessoryBar`, not the framework's rounded `ThemedButton`).
- **Padding**: Footer content stack: 8pt from the footer's leading edge, at
  most 8pt from its trailing edge (`lessThanOrEqualTo`), 4pt from its top,
  4pt from its bottom.
- **Font**: Not applicable to the footer buttons — both are constructed with
  an empty title (`title: ""`) and rendered as SF Symbol images only (`plus`,
  `minus`), so no font is set on them. No other text-bearing view is created
  directly by this file.
- **Background**: Root container — `.windowBackground` theme role. Footer —
  `.surface` theme role. Both fills are `ThemedBackgroundView` and repaint
  live on theme change.
- **Foreground/Text**: Not applicable. The footer buttons carry no title
  text, only a system symbol image; the theme role controls only the fills
  above, not any icon tint (the buttons' tint is left to AppKit's default for
  an accessory-bar bezel button).
- **Border**: A one-point `NSBox` separator (`boxType: .separator`) between
  the tree and the footer, using the system separator appearance (no
  `ThemedSeparatorView`/custom color is used here).
- **Shadow**: None specified in source.
- **Min/Max size**: The root container is given an initial frame of 260×400
  when built in `loadView()` (`NSRect(x: 0, y: 0, width: 260, height: 400)`);
  no width/height constraints are attached to the container itself, so the
  final size is whatever the host's Auto Layout gives it. This is a starting
  frame, not an enforced minimum or maximum.
- **Footer button spacing**: The add/remove buttons sit in an `NSStackView`
  with 2pt horizontal spacing between them.

## States

| State | Appearance change |
|-------|------------------|
| Default | Tree, separator, and footer laid out; add button enabled; remove button's enabled state follows `selection.selectedRoot` (see Disabled). |
| Pressed | Not applicable: the add/remove buttons are stock `NSButton`s with `bezelStyle: .accessoryBar` and no custom pressed-state styling in source — AppKit supplies the default bezel press feedback. |
| Disabled | Remove button is disabled (`isEnabled = false`) whenever `selection.selectedRoot` is `nil` or is not a removable (user-added) root; its tooltip reads "Select an added directory to remove it". |
| Focused | Not applicable: this file sets no custom focus-ring appearance on the tree, the buttons, or the container; whatever focus ring AppKit draws for a standard `NSButton`/hosted `NSOutlineView` is unmodified here. |
| Loading | Before the view's first `viewWillAppear`, `hasLoaded` is `false` and no manager has been asked to scan (`loadInitial()` not yet called); after the first appearance, `hasLoaded` becomes `true` and every current manager has had `loadInitial()` called once. |
| Watching | While the view is on screen — started at `viewWillAppear`, stopped at whichever of `viewDidDisappear` or `paneContentWillBeDiscarded` comes first — every current manager has `startWatching()` active; once stopped, every manager has `stopWatching()` called. |

## Accessibility

- The add button carries accessibility identifier `file-browser.add-directory`
  and the remove button carries `file-browser.remove-directory`
  (`NSView.accessibilityID(_:)`, which calls `setAccessibilityIdentifier`).
- Both footer buttons set a `toolTip` (static for add, dynamic for remove —
  see Behavioral Requirements); neither sets an explicit accessibility label
  or title, and both are built with `NSImage(systemSymbolName:
  accessibilityDescription: nil)` — the symbol image is explicitly given no
  accessibility description.
- Neither footer button has an explicit accessibility label or title: both
  have an empty `title`, an image built with `accessibilityDescription:
  nil`, and no `setAccessibilityLabel`/`setAccessibilityTitle` call anywhere
  in source — only `accessibilityID(_:)` is set (see above). VoiceOver
  therefore has no developer-supplied name to announce for either button,
  only whatever generic fallback AppKit's default bezel-button accessibility
  provides.
- Not applicable: the hosted tree's own accessibility (row roles, disclosure
  state announcements, selection announcements) belongs to
  `FileTreeOutlineViewController`, a separate component with its own recipe;
  this recipe covers only what `FileBrowserViewController` itself renders and
  wires (the footer and the container).
- Not applicable: minimum tap target. This is a pointer-driven macOS control,
  not a touch surface, so the template's 44×44pt touch-target guidance does
  not apply; source gives the footer buttons no explicit width/height — their
  size comes from AppKit's intrinsic size for an accessory-bar bezel button
  with an image.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| file-browser-001 | tree-divider-footer-layout | Load the view. | Tree view, then a 1pt separator, then the footer, stacked top to bottom and each pinned leading/trailing to the container. |
| file-browser-002 | window-background-fill | Load the view, inspect the root container's layer background. | Background color equals the current theme's `.windowBackground` role color. |
| file-browser-003 | footer-surface-fill | Load the view, inspect the footer view's layer background. | Background color equals the current theme's `.surface` role color. |
| file-browser-004 | one-manager-per-root | Construct with a primary root and two additional directories. | Exactly one manager backs each of the 3 roots (primary and both additional) — each root loads and can be watched independently (see file-browser-006 and file-browser-009), never sharing a manager with another root or going without one. |
| file-browser-005 | primary-root-always-managed | Read `manager` immediately after construction. | Returns the `FileTreeManager` for `directories.primary`, never `nil` and never a crash. |
| file-browser-006 | start-watching-on-appear | Call `viewWillAppear()` on a controller not currently watching. | Every manager for a current root receives `startWatching()`. |
| file-browser-007 | stop-watching-on-disappear | Call `viewDidDisappear()` while watching. | Every manager receives `stopWatching()`. |
| file-browser-008 | stop-watching-on-pane-teardown | Call `paneContentWillBeDiscarded()` while watching, without a prior `viewDidDisappear()`. | Every manager receives `stopWatching()`. |
| file-browser-009 | load-initial-once | Call `viewWillAppear()` twice in a row. | `loadInitial()` is called on each manager exactly once (only on the first call). |
| file-browser-010 | add-directory-opens-panel | Call `addDirectory()`. | An `NSOpenPanel` is shown with `canChooseDirectories == true`, `canChooseFiles == false`, `allowsMultipleSelection == true`. |
| file-browser-011 | add-directory-cancel-noop | Call `addDirectory()`, dismiss the panel with Cancel. | `directories.additional` is unchanged before and after the call. |
| file-browser-012 | add-directory-skips-duplicates | Call `addDirectory()`, choose a directory already in `directories.all`. | `directories.additional` is unchanged; no error is presented. |
| file-browser-013 | add-directory-selects-last-added | Call `addDirectory()`, choose one new directory and confirm. | `selection.selectedRoot` equals the chosen directory. |
| file-browser-014 | remove-directory-requires-selected-root | Set `selection.selectedRoot = nil`, call `removeSelectedDirectory()`. | `RefusalFeedback.announce()` is invoked; `directories` is unchanged. |
| file-browser-015 | remove-directory-requires-removable-root | Set `selection.selectedRoot` to `directories.primary`, call `removeSelectedDirectory()`. | `RefusalFeedback.announce()` is invoked; `directories` is unchanged. |
| file-browser-016 | remove-directory-clears-selection | Set `selection.selectedRoot` to a user-added root, call `removeSelectedDirectory()`. | The root is removed from `directories.additional`; `selection.selectedRoot` becomes `nil`. |
| file-browser-017 | remove-button-enablement | Set `selection.selectedRoot` to a user-added root, then to `nil`. | Remove button's `isEnabled` is `true`, then `false`. |
| file-browser-018 | remove-button-tooltip | Set `selection.selectedRoot` to a user-added directory named `Notes`. | Remove button's tooltip reads `Remove "Notes" from this project`. |
| file-browser-019 | footer-buttons-identified | Load the view, inspect the footer buttons. | Add button's accessibility identifier is `file-browser.add-directory`; remove button's is `file-browser.remove-directory`. |
| file-browser-020 | teardown-clears-orphaned-node-selection | Select a file under a user-added root, then remove that root from `directories`. | `selection.selectedNode` becomes `nil`. |
| file-browser-021 | teardown-clears-orphaned-root-selection | Set `selection.selectedRoot` to a user-added root, then remove that same root. | `selection.selectedRoot` becomes `nil`. |
| file-browser-022 | late-added-root-loads-if-visible | After the browser has completed its initial load, add a new directory. | The new root's manager has `loadInitial()` called on it. |
| file-browser-023 | late-added-root-watches-if-visible | While the browser is actively watching, add a new directory. | The new root's manager has `startWatching()` called on it. |
| file-browser-024 | git-status-provider-reuse | Inject a `GitStatusProvider` whose `repoRoot` (symlink-resolved) matches the primary root; construct the browser. | The primary root's manager is built with that provider. |
| file-browser-024b | git-status-provider-reuse | Inject a `GitStatusProvider` whose `repoRoot` does not match any root. | Every manager is built with `nil` for `gitStatusProvider`. |
| file-browser-025 | open-request-forwarding | Set `controller.onOpenRequest` to a closure that records its arguments, then have the hosted tree fire its own `onOpenRequest` (e.g. by triggering an open from the tree). | The recorded arguments match what the tree fired — `controller.onOpenRequest` reads/writes `tree.onOpenRequest` directly, with no second copy of the closure (see **open-request-forwarding**). |
| file-browser-026 | reveal-forwarding | Call `controller.reveal(someURL)`. | The hosted tree's `reveal(_:)` is invoked with `someURL`. |
| file-browser-027 | pane-selection-change-notification | Install `onPaneSelectionChange`, then set `selection.selectedNode` to a new value, then set it again to the same value. | Callback fires once, for the first change only. Because the forwarding hops through `RunLoop.main`, the test must drain the run loop (or await) after each `selectedNode` assignment before asserting, rather than checking synchronously. |
| file-browser-028 | pane-selection-description | Select a node whose `url` is `/a/b/File.swift`. | `paneSelectionDescription` returns `"File.swift"`, not the full path. |
| file-browser-029 | coder-init-unavailable | Inspect `init(coder:)`'s declaration (a static/API-surface check, not a runtime-executable test). | It is marked `@available(*, unavailable)`, so any call site invoking it fails to compile; a runtime `fatalError` fires only if that unavailability is bypassed. |
| file-browser-030 | reuse-managers-across-rebuild | Add a directory, capture the primary root's manager instance, then add a second directory. | The primary root's manager instance after the second add is the same instance as before (identity-equal). |
| file-browser-031 | single-root-convenience-init | Construct with `init(rootURL:excludedURL:documentStore:)`. | `directories.primary == rootURL` and `directories.additional` is empty. |
| file-browser-032 | add-directory-preserves-panel-order | Call `addDirectory()`, choose three new directories in a specific order (none yet in `directories.all`). | `directories.additional` gains all three, in the same order `NSOpenPanel.urls` returned them. |
| file-browser-033 | multi-pane-consistency | Construct two `FileBrowserViewController`s sharing one `FileBrowserDirectories`/`FileBrowserSelection`; select a node under a user-added root in the first, then remove that root from the second. | The first controller's `selection.selectedNode` (and `selection.selectedRoot`, if it equaled the removed root) become `nil`, since both controllers observe the same shared objects. |
| file-browser-034 | reveal-forwarding | Call `controller.revealNothing()`. | The hosted tree's `revealNothing()` is invoked. |
| file-browser-035 | remove-button-tooltip | Set `selection.selectedRoot` to `nil`. | Remove button's tooltip reads `Select an added directory to remove it`. |
| file-browser-036 | add-directory-selects-last-added | Call `addDirectory()`, choose three new directories in a single panel response and confirm. | `selection.selectedRoot` equals only the last of the three chosen directories, not the first two. |
| file-browser-037 | git-status-provider-reuse | Inject a `GitStatusProvider` whose `repoRoot` (symlink-resolved) matches an *additional* root added via `addDirectory()`, not the primary root. | That additional root's manager is built with that provider, matched through `resolvingSymlinksInPath()` rather than a lexical comparison. |

## Edge Cases

- **Null/empty input**: Calling `addDirectory()` and confirming the panel
  with zero URLs selected is not reachable through `NSOpenPanel` (it requires
  at least one choice to return `.OK`); `directories.all` is unaffected in
  that case. Calling `removeSelectedDirectory()` with no selection (`nil`)
  MUST refuse via `RefusalFeedback.announce()` (see
  `remove-directory-requires-selected-root`).
- **Boundary values**: Selecting many directories at once in the open panel
  (`allowsMultipleSelection: true`) MUST add every one not already present,
  in the order the panel returns them (per
  `add-directory-preserves-panel-order`), and MUST select only the last one
  (per `add-directory-selects-last-added`) even when several are added in a
  single call.
- **Concurrent access**: `directories.$additional` is observed on the main
  queue (`receive(on: DispatchQueue.main)`) before triggering
  `rebuildManagers()`, and `FileBrowserDirectories`/`FileBrowserSelection`
  are `@MainActor`-isolated `ObservableObject`s. Multiple browser panes of
  the same project can share one `FileBrowserDirectories`/
  `FileBrowserSelection`/`FileBrowserRestorationState`; when one pane adds or
  removes a root, every other pane observing the same objects rebuilds its
  own managers and clears any of its own selection state that pointed under
  the removed root (`teardown-clears-orphaned-node-selection`,
  `teardown-clears-orphaned-root-selection`). This is stated as
  `multi-pane-consistency`, a SHOULD-level guarantee for multi-pane hosts:
  the source comments describe it as the reason those two clears exist, but
  no explicit test in the given source exercises two live controllers at
  once.
- **Error states**: The open panel returning anything other than `.OK`
  (Cancel) is treated as a no-op, not an error — no dialog is shown. A
  directory the user already added is likewise treated as a no-op, not an
  error. Removing a non-removable or unselected root produces a
  `RefusalFeedback.announce()` (by default, `NSSound.beep()`), not a modal
  error. If `injectedGitStatusProvider`'s `repoRoot` fails to match a new
  root, the component does not raise an error; it simply omits the provider
  (`git-status-provider-reuse`), leaving whatever the manager does with
  `nil` (constructing its own) out of this component's scope.
- **Offline/disconnected state**: Not applicable. This component reads and
  watches the local filesystem only; it makes no network requests, so there
  is no connectivity-loss behavior to define here. (Git status refreshes are
  the concern of the injected/constructed `GitStatusProvider`, a separate
  component.)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `directories` | `FileBrowserDirectories` | required (no default on the designated initializer) | The primary root plus any additional roots this browser shows. |
| `excludedURL` | `URL` | required | A directory excluded from both the tree and the watcher (e.g. a hosting document's own package). |
| `config` | `FileTreeConfig` | `.default` | Opaque-package extensions/display names and the `UserDefaults` key for custom file-type mappings. |
| `ignorePatterns` | `[String]` | `[]` | Wildcard filename patterns left out of the tree. |
| `selection` | `FileBrowserSelection` | a new, private `FileBrowserSelection()` | The shared selection object; supply one to let a host read or drive it. |
| `restoration` | `FileBrowserRestorationState` | a new, private `FileBrowserRestorationState()` | Persisted expanded/selected state; supply one to restore or persist it. |
| `documentStore` | `TextDocumentStore` | required | App-wide open-document registry, threaded to the tree for its dirty indicator. |
| `gitStatusProvider` | `GitStatusProvider?` | `nil` | A provider to reuse for whichever root it belongs to; `nil` lets each root build its own. |
| `rootURL` (convenience init) | `URL` | n/a | Shorthand that builds `FileBrowserDirectories(primary: rootURL)` with no additional roots. |

## Deep Linking

Not applicable: `FileBrowserViewController.swift` contains no URL-scheme or
route handling. It opens directories through `NSOpenPanel` (a user-driven
system picker) and forwards file-open requests through the `onOpenRequest`
closure, not through any app-URL routing.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none defined in source) | `Add a directory to this project` | Add button tooltip, set as a literal `String` on `NSButton.toolTip`. |
| (none defined in source) | `Add` | `NSOpenPanel.prompt`, a literal `String`. |
| (none defined in source) | `Choose directories to show in this project's file browser.` | `NSOpenPanel.message`, a literal `String`. |
| (none defined in source) | `Remove "<name>" from this project` | Remove button tooltip when enabled; `<name>` is the selected root's last path component, interpolated into a literal `String`. |
| (none defined in source) | `Select an added directory to remove it` | Remove button tooltip when disabled, a literal `String`. |

All five user-facing strings above are assigned directly as `String`
literals to AppKit properties (`NSButton.toolTip`, `NSOpenPanel.prompt`,
`NSOpenPanel.message`) rather than through any localization key or
`NSLocalizedString` call — AppKit does not localize `toolTip`/`prompt`/
`message` the way SwiftUI's `Text` localizes a literal, so these are
genuinely unlocalized; no string-key scheme is defined for this component in
source. (The `preconditionFailure` message naming the primary root's path is
a programmer-error trap surfaced only in a crash log, not user-facing text,
and is excluded from this table.)

## Accessibility Options

- **Reduce Motion**: Not applicable. Source contains no animation —
  `loadView()`, `viewDidLoad()`, and the footer update run entirely through
  Auto Layout constraints and immediate property assignment; there is no
  `NSAnimationContext`, transition, or motion effect to reduce.
- **Increase Contrast**: Not applicable at this component's level. The
  container and footer delegate all color to `ThemedBackgroundView`'s
  semantic theme roles (`.windowBackground`, `.surface`); neither
  `FileBrowserViewController.swift` nor `ThemedViews.swift` branches on
  `NSWorkspace.accessibilityDisplayShouldIncreaseContrast`, so any contrast
  adaptation would live in the theme/palette system, not here.
- **Differentiate Without Color**: Not applicable. This view controller
  itself renders no state that is conveyed by color alone — the only color
  fills are the plain background roles above. Git-status coloring in the
  file tree is rendered by `FileTreeOutlineViewController`, a separate
  component with its own recipe.

## Feature Flags

Not applicable: `FileBrowserViewController.swift` contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: `FileBrowserViewController.swift` contains no analytics or
event-tracking calls.

## Privacy

- **Data collected**: Directory URLs the user explicitly chooses through the
  system `NSOpenPanel` when adding a root, plus the URL/selection state the
  user creates by clicking in the tree (held in `FileBrowserSelection`).
  Nothing is collected automatically or without a user action.
- **Storage**: This component does not itself write anything to disk or
  `UserDefaults`. Changes flow out through `FileBrowserDirectories.onChange`
  and `FileBrowserRestorationState.onChange` closures, which a host supplies
  and which decide whether and where to persist them; `FileTreeConfig`
  separately names a `UserDefaults` key (`customMappingsDefaultsKey`) that a
  different component (`CustomFileTypeMappings`) owns, not this one.
- **Transmission**: None. `FileBrowserViewController.swift` makes no network
  calls.
- **Retention**: Determined entirely by the host through the `onChange`
  closures above; this component keeps the roots and selection only in
  memory for as long as the controller and its injected objects live.

## Logging

Not applicable: `FileBrowserViewController.swift` contains no `os_log`,
`Logger`, or other logging calls.

## Platform Notes

- **SwiftUI**: The source is pure AppKit (`NSViewController`), not SwiftUI.
  A SwiftUI port would replace `loadView()`'s manual `NSStackView`/
  `NSLayoutConstraint` footer with a `VStack` (tree, `Divider()`, footer
  `HStack`), replace the two `NSButton`s with `Button` views driving the same
  `addDirectory()`/`removeSelectedDirectory()` logic, and replace
  `FileBrowserSelection`/`FileBrowserDirectories` (already `Combine`
  `ObservableObject`s) with `@ObservedObject`/`@StateObject` wrappers — they
  need no redesign, only new call sites.
- **Compose**: Start from a `Column` with the tree composable, an
  `HorizontalDivider`, and a `Row` footer holding two `IconButton`s (add/
  remove) bound to the same enablement rule
  (`remove-button-enablement`). `FileBrowserDirectories`/
  `FileBrowserSelection` become a `ViewModel` exposing `StateFlow`s; the
  watch-on-appear/stop-on-disappear lifecycle maps to `DisposableEffect`
  keyed on composition entering/leaving.
- **React/Web**: The tree becomes a virtualized list/tree component; the
  footer becomes a flex row with two icon buttons calling the same add/
  remove handlers, disabling the remove button by the same rule. FSEvents
  watching has no direct web equivalent — `start-watching-on-appear`/
  `stop-watching-on-disappear` would map to subscribing/unsubscribing a
  polling or server-push channel when the component mounts/unmounts
  (`useEffect` cleanup).
- **AppKit / UIKit**: This is the source platform (AppKit/macOS). On iOS,
  `NSViewController` becomes `UIViewController`, `NSOpenPanel` becomes a
  `UIDocumentPickerViewController` configured for directories, `NSButton`
  becomes `UIButton`, and `NSStackView`/`NSBox` become `UIStackView`/a
  hairline `UIView`; the FSEvents-backed watch/stop lifecycle would need to
  move to `viewWillAppear(_:)`/`viewDidDisappear(_:)` on `UIViewController`,
  matching this file's `viewWillAppear()`/`viewDidDisappear()` exactly.
  Internally, the source tracks these per-root managers in a private
  `managersByRoot: [URL: FileTreeManager]` dictionary and gates the
  once-only load and the watch/stop toggle on private `hasLoaded`/
  `isWatching` booleans — implementation detail a conforming reimplementation
  is free to represent differently; the requirements and test vectors above
  describe only the observable load/watch behavior, never these names.
- **WinUI 3**: Model the tree as a `TreeView` (or `NavigationView` with a
  `TreeView` in its pane) hosted in a `Grid` with two `RowDefinition`s: the
  tree's row set to `*`, and a fixed-height footer row below a
  `<MenuFlyoutSeparator>`-style `Border` acting as the divider. The footer is
  a horizontal `StackPanel` with two `Button`s carrying `FontIcon`s — Segoe
  Fluent glyphs written as escaped code points rather than raw glyph
  characters, for example `\uE710` for add/plus and `\uE738` for
  remove/minus — in place of the SF Symbols; each button's
  `AutomationProperties.Name` should carry the same text the source puts in
  `toolTip`, since WinUI has no tooltip-as-accessible-name fallback to rely
  on the way this recipe's Accessibility section flags as unresolved for
  AppKit. Directory selection uses `Windows.Storage.Pickers.FolderPicker` in
  place of `NSOpenPanel`; unlike `NSOpenPanel`'s `allowsMultipleSelection`,
  `FolderPicker` returns exactly one folder per call, so multi-directory
  selection must be emulated with a loop of repeated
  `PickSingleFolderAsync()` calls, each shown to the user in turn, and the
  UI should say so explicitly (e.g. "Add another?") rather than silently
  serializing multiple picks behind what looks like one dialog. The remove button's enabled/disabled pair
  maps to a `VisualStateManager` state pair (`Enabled`/`Disabled`) toggled
  from the same `selection.selectedRoot` rule, with the `IsEnabled` binding
  driving `Button.IsEnabled` and a `ToolTipService.ToolTip` binding driving
  the dynamic message. `FileTreeManager`'s FSEvents watch has no 1:1 WinUI
  primitive; use a `Windows.Storage.Search.StorageFolderQueryResult` with a
  `ContentsChanged` handler started/stopped from the page's
  `Loaded`/`Unloaded` events, mirroring `start-watching-on-appear`/
  `stop-watching-on-disappear`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/FileBrowserViewController.swift` |

## Design Decisions

**Decision**: Reuse an existing `FileTreeManager` for any root still present
across a `rebuildManagers()` call, rather than discarding and rebuilding
every manager from scratch.
**Rationale**: the source comment on `rebuildManagers()` states a scanned tree
should not be rescanned "because a *different* directory appeared" — a full
rebuild would re-run a filesystem scan and restart FSEvents watching for
every root, including ones that did not change.
**Approved**: pending.

**Decision**: Forward selection changes to `onPaneSelectionChange` through
`removeDuplicates().dropFirst().receive(on: RunLoop.main)` rather than a
plain synchronous `sink`.
**Rationale**: the source comment explains `@Published` publishes from
`willSet`, so a synchronous `sink` would read the *previous* selected node;
hopping to the run loop lets the store finish updating first,
`removeDuplicates` stops a re-click on the same row from re-firing, and
`dropFirst` discards the value `@Published` replays at subscription time so
a host is not told about a "change" that happened before it installed the
callback.
**Approved**: pending.

**Decision**: Normalize every root and every `GitStatusProvider.repoRoot`
comparison with `resolvingSymlinksInPath()`, not `standardizedFileURL`.
**Rationale**: the source comment (citing `ProjectCheckout.swift`) states an
injected provider's `repoRoot` is a resolved checkout directory while a root
handed to this controller may be an unresolved path the user picked; a
lexical comparison would silently fail whenever a symlink stands between
them, causing the pane to build a second, uninstrumented `GitStatusProvider`
without any visible error.
**Approved**: pending.

**Decision**: Look up the primary root's manager with a `preconditionFailure` on
miss, rather than an optional return or a freshly constructed fallback
manager.
**Rationale**: the source comment states `rebuildManagers()` runs in `init` and
always inserts the primary root, so a missing entry means an invariant broke
elsewhere; failing fast surfaces that bug immediately instead of papering
over it with a manager nothing else expects to exist.
**Approved**: pending.

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [rtl-layout-support](agenticdevelopercookbook://compliance/internationalization#rtl-layout-support) | passed | Internationalization |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |

`screen-reader-support` is partial because both footer buttons have an empty
title and an image built with `accessibilityDescription: nil`, with no
explicit accessibility label set in source (see Accessibility);
`keyboard-navigable` passes because both are stock `NSButton`s with no
override disabling AppKit's default keyboard focus/activation.
`string-externalization` and `no-hardcoded-strings` fail because all five
user-facing strings are literal `String`s assigned to `toolTip`/`prompt`/
`message` (see Localization); `rtl-layout-support` passes because the layout
uses only `leadingAnchor`/`trailingAnchor` constraints, which AppKit mirrors
automatically for right-to-left locales. `data-minimization` passes because
`directories`/`selection` change only in response to an explicit user action
(the open panel, or a click in the tree), never automatically (see Privacy).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed two requirements to subject-only naming; added named requirements and vectors for panel-order preservation and multi-pane consistency; removed private-state coupling from test vectors 004/006 and from the late-added-root requirements; fixed test vectors 025/027/029's assertions; added vectors for `revealNothing()`, the disabled remove-button tooltip, multi-select's last-only selection, and a non-primary symlinked git root; rewrote the WinUI 3 icon glyphs and `FolderPicker` guidance; listed all three watching transitions in States; reformatted Design Decisions to the bold form; populated Compliance; moved the cross-repo guideline reference into `related` and added `depends-on` for the hosted tree |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
