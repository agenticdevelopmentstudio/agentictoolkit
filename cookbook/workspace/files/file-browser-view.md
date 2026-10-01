---
id: ab6d7655-9476-4318-8c36-f431686e2d23
title: File Browser
domain: agentictoolkit://cookbook/workspace/files/file-browser-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'A directory tree plus an add/remove footer for extra root directories,
  managing one file tree manager per root, watched only while visible.'
platforms:
- swift
- macos
tags:
- file-browser
- tree-view
depends-on:
- agentictoolkit://cookbook/workspace/files/file-tree-view
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# File Browser

## Overview

The component shows a directory tree (via a hosted file tree) plus a footer
strip with add/remove controls for adding and removing extra root
directories. It owns one file tree manager per root directory shown (the
primary root plus any the user adds), starts and stops each manager's
filesystem watching in step with the component's own appearance, and forwards
selection and open-file events to a host through shared state (a directories
state, a selection state, a restoration state) and callbacks (an open-request
callback, a pane-selection-change callback). It can be embedded in any
container — a document pane, a sidebar, a window — with no assumptions about
what hosts it.

## Behavioral Requirements

- **tree-divider-footer-layout**: The component MUST arrange, top to
  bottom, the file tree, a one-point separator, and the add/remove footer,
  each pinned to the container's leading and trailing edges, filling the
  container's bounds.
- **window-background-fill**: The component MUST fill its root
  container with the window-background theme role.
- **footer-surface-fill**: The component MUST fill the footer strip with the
  surface theme role.
- **one-manager-per-root**: The component MUST maintain exactly one
  file tree manager for every root currently among the browsed roots.
- **primary-root-always-managed**: Looking up the primary root's manager MUST
  always resolve to a valid file tree manager; this invariant MUST hold for
  the lifetime of the component (enforced by failing immediately if it is
  ever violated, rather than silently constructing a throwaway manager).
- **start-watching-on-appear**: The component MUST start filesystem watching
  on every current manager when the component appears, if watching is not
  already active.
- **stop-watching-on-disappear**: The component MUST stop filesystem watching
  on every manager when the component disappears.
- **stop-watching-on-pane-teardown**: The component MUST stop filesystem
  watching on every manager when its pane content is about to be discarded,
  independent of whether the disappearance event has fired.
- **load-initial-once**: The component MUST perform the initial load on every
  manager exactly once — the first time the component appears — and MUST NOT
  perform it again on a later appearance of the same component.
- **add-directory-opens-panel**: Invoking the add-directory action MUST
  present a system directory picker configured to choose one or more
  directories and no files.
- **add-directory-cancel-noop**: If the picker is dismissed without a
  choice, the component MUST NOT change the browsed roots.
- **add-directory-skips-duplicates**: If a chosen directory is already one of
  the browsed roots, the component MUST leave the browsed roots unchanged for
  that directory and MUST NOT present an error.
- **add-directory-selects-last-added**: After adding one or more chosen
  directories, if the last chosen directory is a removable root (i.e. it is
  now one of the additional roots), the component MUST set the selected root
  to that directory.
- **add-directory-preserves-panel-order**: When the add-directory action adds
  more than one chosen directory from a single picker response, the component
  MUST add each one not already present among the browsed roots, in the same
  order the picker returned them.
- **remove-directory-requires-selected-root**: Invoking the remove-directory
  action while no root is selected MUST trigger refusal feedback and MUST NOT
  change the browsed roots or the selection.
- **remove-directory-requires-removable-root**: Invoking the remove-directory
  action while the selected root is not one of the additional roots (i.e. it
  is the primary root or already gone) MUST trigger refusal feedback and MUST
  NOT change the browsed roots or the selection.
- **remove-directory-clears-selection**: After a removal succeeds for the
  selected root, the component MUST clear the selected root to none.
- **remove-button-enablement**: The remove control MUST be enabled only while
  the selected root is a removable root, and MUST be disabled at every other
  time (no root selected, or the selected root is the primary or an
  already-removed root).
- **remove-button-tooltip**: While the remove control is enabled, its tooltip
  MUST read `Remove "<name>" from this project`, where `<name>` is the
  selected root's last path component; while disabled, its tooltip MUST read
  `Select an added directory to remove it`.
- **footer-buttons-identified**: The add control MUST carry the accessibility
  identifier `file-browser.add-directory` and the remove control MUST carry
  `file-browser.remove-directory`.
- **teardown-clears-orphaned-node-selection**: When a root is dropped from
  the browsed roots across a rebuild, the component MUST clear the selected
  node to none if the selected node's location lies at or under that root's
  path.
- **teardown-clears-orphaned-root-selection**: When a root is dropped from
  the browsed roots across a rebuild, the component MUST clear the selected
  root to none if it equals that root.
- **multi-pane-consistency**: When multiple browser panes share the same
  directories/selection/restoration state and one pane adds or removes a
  root, every other pane observing that shared state SHOULD rebuild its own
  managers and clear any of its own selection state that pointed under the
  added/removed root (see **teardown-clears-orphaned-node-selection** and
  **teardown-clears-orphaned-root-selection**).
- **late-added-root-loads-if-visible**: A manager created for a root added
  after the browser's own initial load has completed MUST have its initial
  load performed as part of the same rebuild.
- **late-added-root-watches-if-visible**: A manager created for a root added
  while the browser is currently watching MUST have watching started on it
  as part of the same rebuild.
- **git-status-provider-reuse**: When constructing a manager for a root, the
  component MUST pass the injected git status provider to that manager only
  when the provider's repository root, resolved by following symlinks,
  equals the new root resolved the same way; otherwise it MUST pass none.
- **open-request-forwarding**: Reading or writing the component's
  open-request callback MUST read or write the hosted tree's own
  open-request callback directly — there MUST NOT be a second, independent
  copy of this callback.
- **reveal-forwarding**: Revealing a node, and revealing nothing, MUST
  delegate directly to the hosted tree's own reveal operations.
- **pane-selection-change-notification**: The component MUST call the
  pane-selection-change callback whenever the selected node changes to a
  value different from its immediately preceding value, MUST NOT call it for
  the value already held at the time the observer was installed, and MUST
  NOT call it when the selected node is set to the value it already holds.
- **pane-selection-description**: The pane's selection description MUST
  return the selected node's name (not its path), or none when nothing is
  selected.
- **reuse-managers-across-rebuild**: When rebuilding the manager list, the
  component SHOULD reuse the existing file tree manager instance for any root
  that is still present among the browsed roots, rather than discarding and
  recreating it.
- **single-root-convenience-init**: The component MAY be constructed with a
  single-root convenience form, which builds the directories state with that
  location as the sole primary root and no additional roots.

## Appearance

- **Corner radius**: None. The container, footer, and the add/remove
  controls apply no corner radius.
- **Padding**: Footer content: 8pt from the footer's leading edge, at
  most 8pt from its trailing edge, 4pt from its top, 4pt from its bottom.
- **Font**: Not applicable to the footer controls — both are constructed with
  no title text and rendered as an icon image only (a plus/minus glyph), so
  no font is set on them. No other text-bearing element is created directly
  by this component.
- **Background**: Root container — window-background theme role. Footer —
  surface theme role. Both fills repaint live on theme change.
- **Foreground/Text**: Not applicable. The footer controls carry no title
  text, only an icon image; the theme role controls only the fills above,
  not any icon tint (the controls' tint is left to the platform's default
  for an accessory-style control).
- **Border**: A one-point separator between the tree and the footer, using
  the platform's standard separator appearance (no custom color is used
  here).
- **Shadow**: None specified.
- **Min/Max size**: The root container is given an initial frame of 260×400
  when first built; no width/height constraints are attached to the
  container itself, so the final size is whatever the host's layout gives
  it. This is a starting frame, not an enforced minimum or maximum.
- **Footer button spacing**: The add/remove controls sit with 2pt horizontal
  spacing between them.

## States

| State | Appearance change |
|-------|------------------|
| Default | Tree, separator, and footer laid out; add control enabled; remove control's enabled state follows the selected root (see Disabled). |
| Pressed | Not applicable: the add/remove controls use the platform's standard control styling with no custom pressed-state styling defined here — the platform supplies its default press feedback. |
| Disabled | Remove control is disabled whenever the selected root is none or is not a removable (user-added) root; its tooltip reads "Select an added directory to remove it". |
| Focused | Not applicable: this component sets no custom focus-ring appearance on the tree, the controls, or the container; whatever focus indicator the platform draws by default for a standard control/hosted tree is unmodified here. |
| Loading | Before the component's first appearance, nothing has loaded and no manager has been asked to scan; after the first appearance, every current manager has had its initial load performed once. |
| Watching | While the component is on screen — started at first appearance, stopped at whichever of disappearance or pane teardown comes first — every current manager has watching active; once stopped, every manager has watching stopped. |

## Accessibility

- The add control carries accessibility identifier `file-browser.add-directory`
  and the remove control carries `file-browser.remove-directory`.
- Both footer controls set a tooltip (static for add, dynamic for remove —
  see Behavioral Requirements); neither sets an explicit accessibility label
  or title, and both are built with an icon image explicitly given no
  accessibility description.
- Neither footer control has an explicit accessibility label or title: both
  have no title text, an icon image with no accessibility description, and
  no accessibility label/title set anywhere — only the accessibility
  identifier is set (see above). A screen reader therefore has no
  developer-supplied name to announce for either control, only whatever
  generic fallback the platform's default control accessibility provides.
- Not applicable: the hosted tree's own accessibility (row roles, disclosure
  state announcements, selection announcements) belongs to the hosted file
  tree, a separate component with its own recipe; this recipe covers only
  what this component itself renders and wires (the footer and the
  container).
- Not applicable: minimum tap target. This is a pointer-driven desktop
  control, not a touch surface, so the template's 44×44pt touch-target
  guidance does not apply; the footer controls are given no explicit
  width/height — their size comes from the platform's intrinsic sizing for
  an accessory-style control with an icon.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| file-browser-001 | tree-divider-footer-layout | Load the component. | Tree, then a 1pt separator, then the footer, stacked top to bottom and each pinned leading/trailing to the container. |
| file-browser-002 | window-background-fill | Load the component, inspect the root container's background. | Background color equals the current theme's window-background role color. |
| file-browser-003 | footer-surface-fill | Load the component, inspect the footer's background. | Background color equals the current theme's surface role color. |
| file-browser-004 | one-manager-per-root | Construct with a primary root and two additional directories. | Exactly one manager backs each of the 3 roots (primary and both additional) — each root loads and can be watched independently (see file-browser-006 and file-browser-009), never sharing a manager with another root or going without one. |
| file-browser-005 | primary-root-always-managed | Look up the primary root's manager immediately after construction. | Returns a valid manager for the primary root, never absent and never a crash. |
| file-browser-006 | start-watching-on-appear | Trigger the component's appearance while it is not currently watching. | Every manager for a current root has watching started. |
| file-browser-007 | stop-watching-on-disappear | Trigger the component's disappearance while watching. | Every manager has watching stopped. |
| file-browser-008 | stop-watching-on-pane-teardown | Trigger pane teardown while watching, without a prior disappearance event. | Every manager has watching stopped. |
| file-browser-009 | load-initial-once | Trigger the component's appearance twice in a row. | The initial load runs on each manager exactly once (only on the first appearance). |
| file-browser-010 | add-directory-opens-panel | Invoke the add-directory action. | A system directory picker is shown configured to choose directories only (not files), allowing multiple selections. |
| file-browser-011 | add-directory-cancel-noop | Invoke the add-directory action, dismiss the picker without choosing. | The additional roots are unchanged before and after the call. |
| file-browser-012 | add-directory-skips-duplicates | Invoke the add-directory action, choose a directory already among the browsed roots. | The additional roots are unchanged; no error is presented. |
| file-browser-013 | add-directory-selects-last-added | Invoke the add-directory action, choose one new directory and confirm. | The selected root equals the chosen directory. |
| file-browser-014 | remove-directory-requires-selected-root | Clear the selected root, then invoke the remove-directory action. | Refusal feedback is triggered; the browsed roots are unchanged. |
| file-browser-015 | remove-directory-requires-removable-root | Set the selected root to the primary root, then invoke the remove-directory action. | Refusal feedback is triggered; the browsed roots are unchanged. |
| file-browser-016 | remove-directory-clears-selection | Set the selected root to a user-added root, then invoke the remove-directory action. | The root is removed from the additional roots; the selected root becomes none. |
| file-browser-017 | remove-button-enablement | Set the selected root to a user-added root, then to none. | The remove control is enabled, then disabled. |
| file-browser-018 | remove-button-tooltip | Set the selected root to a user-added directory named `Notes`. | The remove control's tooltip reads `Remove "Notes" from this project`. |
| file-browser-019 | footer-buttons-identified | Load the component, inspect the footer controls. | The add control's accessibility identifier is `file-browser.add-directory`; the remove control's is `file-browser.remove-directory`. |
| file-browser-020 | teardown-clears-orphaned-node-selection | Select a file under a user-added root, then remove that root from the browsed roots. | The selected node becomes none. |
| file-browser-021 | teardown-clears-orphaned-root-selection | Set the selected root to a user-added root, then remove that same root. | The selected root becomes none. |
| file-browser-022 | late-added-root-loads-if-visible | After the browser has completed its initial load, add a new directory. | The new root's manager has its initial load performed. |
| file-browser-023 | late-added-root-watches-if-visible | While the browser is actively watching, add a new directory. | The new root's manager has watching started. |
| file-browser-024 | git-status-provider-reuse | Inject a git status provider whose repository root (symlink-resolved) matches the primary root; construct the browser. | The primary root's manager is built with that provider. |
| file-browser-024b | git-status-provider-reuse | Inject a git status provider whose repository root does not match any root. | Every manager is built with no git status provider. |
| file-browser-025 | open-request-forwarding | Set the component's open-request callback to one that records its arguments, then have the hosted tree fire its own open-request callback (e.g. by triggering an open from the tree). | The recorded arguments match what the tree fired — the component's callback reads/writes the tree's callback directly, with no second copy (see **open-request-forwarding**). |
| file-browser-026 | reveal-forwarding | Invoke the component's reveal operation for a given location. | The hosted tree's own reveal operation is invoked for that location. |
| file-browser-027 | pane-selection-change-notification | Install the pane-selection-change callback, then change the selected node to a new value, then set it again to the same value. | The callback fires once, for the first change only. Because the notification is delivered asynchronously, the test must wait a turn (or await) after each change before asserting, rather than checking synchronously. |
| file-browser-028 | pane-selection-description | Select a node whose location is `/a/b/File.swift`. | The pane's selection description returns `"File.swift"`, not the full path. |
| file-browser-029 | reuse-managers-across-rebuild | Add a directory, capture the primary root's manager instance, then add a second directory. | The primary root's manager instance after the second add is the same instance as before (identity-equal). |
| file-browser-030 | single-root-convenience-init | Construct with the single-root convenience form. | The primary root equals the given location and the additional roots are empty. |
| file-browser-031 | add-directory-preserves-panel-order | Invoke the add-directory action, choose three new directories in a specific order (none yet among the browsed roots). | The additional roots gain all three, in the same order the picker returned them. |
| file-browser-032 | multi-pane-consistency | Construct two instances of the component sharing one directories/selection state; select a node under a user-added root in the first, then remove that root from the second. | The first component's selected node (and its selected root, if it equaled the removed root) become none, since both instances observe the same shared state. |
| file-browser-033 | reveal-forwarding | Invoke the component's reveal-nothing operation. | The hosted tree's own reveal-nothing operation is invoked. |
| file-browser-034 | remove-button-tooltip | Set the selected root to none. | The remove control's tooltip reads `Select an added directory to remove it`. |
| file-browser-035 | add-directory-selects-last-added | Invoke the add-directory action, choose three new directories in a single picker response and confirm. | The selected root equals only the last of the three chosen directories, not the first two. |
| file-browser-036 | git-status-provider-reuse | Inject a git status provider whose repository root (symlink-resolved) matches an *additional* root added via the add-directory action, not the primary root. | That additional root's manager is built with that provider, matched by resolving symlinks rather than a lexical comparison. |

## Edge Cases

- **Null/empty input**: Invoking the add-directory action and confirming the
  picker with zero locations selected is not reachable through the picker
  (it requires at least one choice to confirm); the browsed roots are
  unaffected in that case. Invoking the remove-directory action with no
  selection MUST refuse via refusal feedback (see
  `remove-directory-requires-selected-root`).
- **Boundary values**: Selecting many directories at once in the picker
  MUST add every one not already present, in the order the picker returns
  them (per `add-directory-preserves-panel-order`), and MUST select only the
  last one (per `add-directory-selects-last-added`) even when several are
  added in a single call.
- **Concurrent access**: Changes to the additional roots are observed and
  applied on the component's own execution context before triggering a
  manager rebuild, and the directories/selection state is confined to that
  same context (see Platform Notes for the mechanism used on Apple
  platforms). Multiple browser panes of the same project can share one
  directories/selection/restoration state; when one pane adds or removes a
  root, every other pane observing the same state rebuilds its own managers
  and clears any of its own selection state that pointed under the removed
  root (`teardown-clears-orphaned-node-selection`,
  `teardown-clears-orphaned-root-selection`). This is stated as
  `multi-pane-consistency`, a SHOULD-level guarantee for multi-pane hosts:
  it is documented as the reason those two clears exist, but no explicit
  test in the given source exercises two live components at once.
- **Error states**: The picker being dismissed without a choice is treated
  as a no-op, not an error — no dialog is shown. A directory the user
  already added is likewise treated as a no-op, not an error. Removing a
  non-removable or unselected root produces refusal feedback (an audible
  cue, by default), not a modal error. If the injected git status
  provider's repository root fails to match a new root, the component does
  not raise an error; it simply omits the provider
  (`git-status-provider-reuse`), leaving whatever the manager does with no
  provider (constructing its own) out of this component's scope.
- **Offline/disconnected state**: Not applicable. This component reads and
  watches the local filesystem only; it makes no network requests, so there
  is no connectivity-loss behavior to define here. (Git status refreshes are
  the concern of the injected/constructed git status provider, a separate
  component.)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `directories` | directories state | required (no default) | The primary root plus any additional roots this browser shows. |
| `excludedURL` | location | required | A directory excluded from both the tree and the watcher (e.g. a hosting document's own package). |
| `config` | tree display configuration | default configuration | Opaque-package extensions/display names and the persisted-settings key for custom file-type mappings. |
| `ignorePatterns` | list of patterns | empty | Wildcard filename patterns left out of the tree. |
| `selection` | selection state | a new, private instance | The shared selection state; supply one to let a host read or drive it. |
| `restoration` | restoration state | a new, private instance | Persisted expanded/selected state; supply one to restore or persist it. |
| `documentStore` | document store | required | App-wide open-document registry, threaded to the tree for its dirty indicator. |
| `gitStatusProvider` | git status provider (optional) | none | A provider to reuse for whichever root it belongs to; none lets each root build its own. |
| `rootURL` (single-root convenience form) | location | n/a | Shorthand that builds the directories state with that location as the sole primary root and no additional roots. |

## Deep Linking

Not applicable: the component contains no URL-scheme or route handling. It
opens directories through a user-driven system picker and forwards file-open
requests through the open-request callback, not through any app-URL routing.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none defined in source) | `Add a directory to this project` | Add control's tooltip. |
| (none defined in source) | `Add` | Directory picker's confirm-action label. |
| (none defined in source) | `Choose directories to show in this project's file browser.` | Directory picker's message. |
| (none defined in source) | `Remove "<name>" from this project` | Remove control's tooltip when enabled; `<name>` is the selected root's last path component. |
| (none defined in source) | `Select an added directory to remove it` | Remove control's tooltip when disabled. |

All five user-facing strings above are assigned directly as literal text
rather than through any localization key or lookup mechanism, so these are
genuinely unlocalized; no string-key scheme is defined for this component
(see Platform Notes for why). (A failure-trap message naming the primary
root's path is a programmer-error trap surfaced only in a crash log, not
user-facing text, and is excluded from this table.)

## Accessibility Options

- **Reduce Motion**: Not applicable. This component contains no
  animation — layout and the footer update run entirely through immediate
  constraint/property assignment; there is no transition or motion effect
  to reduce.
- **Increase Contrast**: Not applicable at this component's level. The
  container and footer delegate all color to the semantic theme roles
  (window-background, surface); neither this component nor the shared
  themed-background mechanism branches on an increase-contrast setting, so
  any contrast adaptation would live in the theme/palette system, not here.
- **Differentiate Without Color**: Not applicable. This component itself
  renders no state that is conveyed by color alone — the only color fills
  are the plain background roles above. Git-status coloring in the file
  tree is rendered by the hosted file tree, a separate component with its
  own recipe.

## Feature Flags

Not applicable: this component contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: this component contains no analytics or event-tracking
calls.

## Privacy

- **Data collected**: Directory locations the user explicitly chooses
  through the system directory picker when adding a root, plus the
  location/selection state the user creates by clicking in the tree (held
  in the selection state). Nothing is collected automatically or without a
  user action.
- **Storage**: This component does not itself write anything to persistent
  storage. Changes flow out through change callbacks on the directories
  state and the restoration state, which a host supplies and which decide
  whether and where to persist them; the tree display configuration
  separately names a persisted-settings key that a different component
  (custom file-type mappings) owns, not this one.
- **Transmission**: None. This component makes no network calls.
- **Retention**: Determined entirely by the host through the change
  callbacks above; this component keeps the roots and selection only in
  memory for as long as the component and its injected state live.

## Logging

Not applicable: this component contains no logging calls.

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
- **AppKit / UIKit**: This is the source platform (AppKit/macOS). The
  container is an `NSViewController`; the divider is an `NSBox` with
  `boxType: .separator`; the footer sits in an `NSStackView` with 2pt
  horizontal spacing between two plain `NSButton`s (`bezelStyle:
  .accessoryBar`, not the framework's rounded `ThemedButton`), each with an
  empty title and rendered as an SF Symbol image only (`plus`, `minus`) with
  `accessibilityDescription: nil`, and no explicit accessibility label/title
  beyond `NSView.accessibilityID(_:)`. The root/footer fills use
  `ThemedBackgroundView` for the `.windowBackground`/`.surface` roles.
  Directory selection uses `NSOpenPanel` (`canChooseDirectories: true`,
  `canChooseFiles: false`, `allowsMultipleSelection: true`); refusal
  feedback is `RefusalFeedback.announce()`, by default `NSSound.beep()`.
  Constructing the component from decoded/serialized state (`init(coder:)`)
  is marked `@available(*, unavailable)` and calls `fatalError` if somehow
  invoked at runtime — AppKit requires this initializer to exist on an
  `NSViewController` subclass even though this component is never built from
  a storyboard/nib. The directories/selection/restoration state are
  `@MainActor`-isolated Combine `ObservableObject`s; changes to the
  additional roots are received on the main queue (`receive(on:
  DispatchQueue.main)`) before triggering a manager rebuild. AppKit does not
  localize `toolTip`/`NSOpenPanel.prompt`/`NSOpenPanel.message` the way
  SwiftUI's `Text` localizes a literal, so the five user-facing strings are
  genuinely unlocalized literals with no key scheme. On iOS,
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
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/files/. |
