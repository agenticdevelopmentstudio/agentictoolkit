---
id: ab6d7655-9476-4318-8c36-f431686e2d23
title: File Browser View Controller
domain: agentictoolkit://recipes/file-browser-view-controller
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
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
depends-on: []
related: []
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
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

- **renders-tree-divider-footer-layout**: The component MUST arrange, top to
  bottom, the file tree, a one-point separator (`NSBox` with `boxType:
  .separator`), and the add/remove footer, each pinned to the container's
  leading and trailing edges, filling the container's bounds.
- **windowbackground-container-fill**: The component MUST fill its root
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
- **late-added-root-loads-if-visible**: A manager created for a root added
  after the browser's own initial load has completed (`hasLoaded == true`)
  MUST have `loadInitial()` called on it as part of the same rebuild.
- **late-added-root-watches-if-visible**: A manager created for a root added
  while the browser is currently watching (`isWatching == true`) MUST have
  `startWatching()` called on it as part of the same rebuild.
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
| Watching | While the view is on screen (between `viewWillAppear`/`paneContentWillBeDiscarded` boundaries), `isWatching` is `true` and every current manager has `startWatching()` active; while off screen, `isWatching` is `false` and every manager has `stopWatching()` called. |

## Accessibility

- The add button carries accessibility identifier `file-browser.add-directory`
  and the remove button carries `file-browser.remove-directory`
  (`NSView.accessibilityID(_:)`, which calls `setAccessibilityIdentifier`).
- Both footer buttons set a `toolTip` (static for add, dynamic for remove —
  see Behavioral Requirements); neither sets an explicit accessibility label
  or title, and both are built with `NSImage(systemSymbolName:
  accessibilityDescription: nil)` — the symbol image is explicitly given no
  accessibility description.
- NEEDS REVIEW: Not implemented in source. Behavior undefined. Because both
  buttons have an empty `title`, an image with `accessibilityDescription:
  nil`, and no explicit `setAccessibilityLabel`/`setAccessibilityTitle` call,
  it cannot be determined from source alone whether VoiceOver announces any
  name for them (AppKit's fallback behavior for an untitled, undescribed
  bezel button is not decidable by reading this file). This would be settled
  by a VoiceOver pass over the running footer, or by adding an explicit
  accessibility label in source.
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
| file-browser-001 | renders-tree-divider-footer-layout | Load the view. | Tree view, then a 1pt separator, then the footer, stacked top to bottom and each pinned leading/trailing to the container. |
| file-browser-002 | windowbackground-container-fill | Load the view, inspect the root container's layer background. | Background color equals the current theme's `.windowBackground` role color. |
| file-browser-003 | footer-surface-fill | Load the view, inspect the footer view's layer background. | Background color equals the current theme's `.surface` role color. |
| file-browser-004 | one-manager-per-root | Construct with a primary root and two additional directories. | `managersByRoot` contains exactly 3 entries, one per root. |
| file-browser-005 | primary-root-always-managed | Read `manager` immediately after construction. | Returns the `FileTreeManager` for `directories.primary`, never `nil` and never a crash. |
| file-browser-006 | start-watching-on-appear | Call `viewWillAppear()` on a controller not currently watching. | Every manager in `managersByRoot` receives `startWatching()`. |
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
| file-browser-025 | open-request-forwarding | Set `controller.onOpenRequest = { _, _ in }`, then read `tree.onOpenRequest`. | The two closures are identical (same underlying storage). |
| file-browser-026 | reveal-forwarding | Call `controller.reveal(someURL)`. | The hosted tree's `reveal(_:)` is invoked with `someURL`. |
| file-browser-027 | pane-selection-change-notification | Install `onPaneSelectionChange`, then set `selection.selectedNode` to a new value, then set it again to the same value. | Callback fires once, for the first change only. |
| file-browser-028 | pane-selection-description | Select a node whose `url` is `/a/b/File.swift`. | `paneSelectionDescription` returns `"File.swift"`, not the full path. |
| file-browser-029 | coder-init-unavailable | Attempt to build the controller via `NSCoder`-based decoding (e.g. from a storyboard/XIB). | Compilation fails (unavailable), or a runtime `fatalError` occurs if the unavailability is bypassed. |
| file-browser-030 | reuse-managers-across-rebuild | Add a directory, capture the primary root's manager instance, then add a second directory. | The primary root's manager instance after the second add is the same instance as before (identity-equal). |
| file-browser-031 | single-root-convenience-init | Construct with `init(rootURL:excludedURL:documentStore:)`. | `directories.primary == rootURL` and `directories.additional` is empty. |

## Edge Cases

- **Null/empty input**: Calling `addDirectory()` and confirming the panel
  with zero URLs selected is not reachable through `NSOpenPanel` (it requires
  at least one choice to return `.OK`); `directories.all` is unaffected in
  that case. Calling `removeSelectedDirectory()` with no selection (`nil`)
  MUST refuse via `RefusalFeedback.announce()` (see
  `remove-directory-requires-selected-root`).
- **Boundary values**: Selecting many directories at once in the open panel
  (`allowsMultipleSelection: true`) MUST add every one not already present,
  in the order the panel returns them, and MUST select only the last one
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
  `teardown-clears-orphaned-root-selection`). This is a SHOULD-level
  consistency guarantee for multi-pane hosts, since the source comments
  describe it as the reason those two clears exist, but no explicit test in
  the given source exercises two live controllers at once.
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

NEEDS REVIEW: Not implemented in source. Behavior undefined. All five
user-facing strings above are assigned directly as `String` literals to
AppKit properties (`NSButton.toolTip`, `NSOpenPanel.prompt`,
`NSOpenPanel.message`) rather than through any localization key or
`NSLocalizedString` call — AppKit does not localize `toolTip`/`prompt`/
`message` the way SwiftUI's `Text` localizes a literal, so these are
genuinely unlocalized. What is missing is a defined string-key scheme for
this component; it would be settled by the host app's localization owner
choosing keys and wiring them in. (The `preconditionFailure` message
naming the primary root's path is a programmer-error trap surfaced only in
a crash log, not user-facing text, and is excluded from this table.)

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
- **WinUI 3**: Model the tree as a `TreeView` (or `NavigationView` with a
  `TreeView` in its pane) hosted in a `Grid` with two `RowDefinition`s: the
  tree's row set to `*`, and a fixed-height footer row below a
  `<MenuFlyoutSeparator>`-style `Border` acting as the divider. The footer is
  a horizontal `StackPanel` with two `Button`s carrying `FontIcon`s (Segoe
  Fluent `` for add/plus, `` or `` for remove/minus) in
  place of the SF Symbols; each button's `AutomationProperties.Name` should
  carry the same text the source puts in `toolTip`, since WinUI has no
  tooltip-as-accessible-name fallback to rely on the way this recipe's
  Accessibility section flags as unresolved for AppKit. Directory selection
  uses `Windows.Storage.Pickers.FolderPicker` in place of `NSOpenPanel`,
  with `Multiple` not directly supported (WinUI's `FolderPicker` returns one
  folder per call, so `allowsMultipleSelection` becomes a loop over repeated
  picker invocations, or `PickMultipleFilesAsync`-style handling is not
  available for folders — call this out to implementers rather than silently
  serializing multiple picks). The remove button's enabled/disabled pair
  maps to a `VisualStateManager` state pair (`Enabled`/`Disabled`) toggled
  from the same `selection.selectedRoot` rule, with the `IsEnabled` binding
  driving `Button.IsEnabled` and a `ToolTipService.ToolTip` binding driving
  the dynamic message. `FileTreeManager`'s FSEvents watch has no 1:1 WinUI
  primitive; use a `Windows.Storage.Search.StorageFolderQueryResult` with a
  `ContentsChanged` handler started/stopped from the page's
  `Loaded`/`Unloaded` events, mirroring `start-watching-on-appear`/
  `stop-watching-on-disappear`.

## Design Decisions

Decision: Reuse an existing `FileTreeManager` for any root still present
across a `rebuildManagers()` call, rather than discarding and rebuilding
every manager from scratch.
Rationale: the source comment on `rebuildManagers()` states a scanned tree
should not be rescanned "because a *different* directory appeared" — a full
rebuild would re-run a filesystem scan and restart FSEvents watching for
every root, including ones that did not change.
Approved: pending.

Decision: Forward selection changes to `onPaneSelectionChange` through
`removeDuplicates().dropFirst().receive(on: RunLoop.main)` rather than a
plain synchronous `sink`.
Rationale: the source comment explains `@Published` publishes from
`willSet`, so a synchronous `sink` would read the *previous* selected node;
hopping to the run loop lets the store finish updating first,
`removeDuplicates` stops a re-click on the same row from re-firing, and
`dropFirst` discards the value `@Published` replays at subscription time so
a host is not told about a "change" that happened before it installed the
callback.
Approved: pending.

Decision: Normalize every root and every `GitStatusProvider.repoRoot`
comparison with `resolvingSymlinksInPath()`, not `standardizedFileURL`.
Rationale: the source comment (citing `ProjectCheckout.swift:12`) states an
injected provider's `repoRoot` is a resolved checkout directory while a root
handed to this controller may be an unresolved path the user picked; a
lexical comparison would silently fail whenever a symlink stands between
them, causing the pane to build a second, uninstrumented `GitStatusProvider`
without any visible error.
Approved: pending.

Decision: Look up the primary root's manager with a `preconditionFailure` on
miss, rather than an optional return or a freshly constructed fallback
manager.
Rationale: the source comment states `rebuildManagers()` runs in `init` and
always inserts the primary root, so a missing entry means an invariant broke
elsewhere; failing fast surfaces that bug immediately instead of papering
over it with a manager nothing else expects to exist.
Approved: pending.

## Compliance

No automated compliance checks have been run against this recipe yet. This
table will be populated by the cookbook's compliance tooling on review.

| Check | Status | Category |
|-------|--------|----------|

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
