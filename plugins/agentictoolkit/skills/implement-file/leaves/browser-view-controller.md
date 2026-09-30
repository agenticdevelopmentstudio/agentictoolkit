<!-- leaf: implement-file/browser-view-controller · source: file-browser-view-controller.md -->

**Rules** (cite as `implement-file/browser-view-controller#<slug>`):

- `tree-divider-footer-layout` MUST
- `window-background-fill` MUST
- `footer-surface-fill` MUST
- `one-manager-per-root` MUST
- `primary-root-always-managed` MUST
- `start-watching-on-appear` MUST
- `stop-watching-on-disappear` MUST
- `stop-watching-on-pane-teardown` MUST
- `load-initial-once` MUST
- `add-directory-opens-panel` MUST
- `add-directory-cancel-noop` MUST
- `add-directory-skips-duplicates` MUST
- `add-directory-selects-last-added` MUST
- `add-directory-preserves-panel-order` MUST
- `remove-directory-requires-selected-root` MUST
- `remove-directory-requires-removable-root` MUST
- `remove-directory-clears-selection` MUST
- `remove-button-enablement` MUST
- `remove-button-tooltip` MUST
- `footer-buttons-identified` MUST
- `teardown-clears-orphaned-node-selection` MUST
- `teardown-clears-orphaned-root-selection` MUST
- `multi-pane-consistency` SHOULD
- `late-added-root-loads-if-visible` MUST
- `late-added-root-watches-if-visible` MUST
- `git-status-provider-reuse` MUST
- `open-request-forwarding` MUST
- `reveal-forwarding` MUST
- `pane-selection-change-notification` MUST
- `pane-selection-description` MUST
- `coder-init-unavailable` MUST
- `reuse-managers-across-rebuild` SHOULD
- `single-root-convenience-init` MAY

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

