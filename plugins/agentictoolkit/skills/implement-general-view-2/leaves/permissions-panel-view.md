<!-- leaf: implement-general-view-2/permissions-panel-view · source: permissions-panel-view.md -->

**Rules** (cite as `implement-general-view-2/permissions-panel-view#<slug>`):

- `imports-both-modules-spell-component-permission-type` MUST — Because AgenticDeveloperToolkit also exports a type named Permission, a caller whose target imports both modules MUST …
- `one-row-per-permission-in-order` MUST
- `checker-default` MUST
- `rows-in-full-bleed-vertical-stack` MUST
- `row-width-pinned-to-stack` MUST
- `layout-built-once` MUST
- `refreshes-serially-in-order` MUST
- `refresh-aborts-on-cancellation` MUST
- `activation-observer` MUST
- `schedules-refresh-on-window-attach` MUST
- `schedules-refresh-on-app-activation` MUST
- `latest-refresh-wins` MUST
- `action-refresh` MUST
- `cancels-refresh-and-observer-on-deinit` MUST
- `coder-init-unavailable` MUST
- `supports-direct-refresh` MUST

# Permissions Panel View

## Overview

`PermissionsPanelView` is a drop-in `NSView` settings panel: it builds one
`PermissionRowView` card per `Permission` it is given, wires each row's grant
action through `PermissionPresenter`, and keeps every row's live status
current by refreshing when the view first appears, whenever the host
application reactivates (for example, the user returning from System
Settings), and after a row's grant action completes. It runs no polling
timer of its own and is free of any settings-framework dependency, so any
app or window can host it.

Because `AgenticDeveloperToolkit` also exports a type named `Permission`,
a caller whose target imports both modules MUST spell this component's
permission type `AgenticToolkitPermissions.Permission` to resolve the
ambiguity.

## Behavioral Requirements

- **one-row-per-permission-in-order**: The component MUST create exactly
  one `PermissionRowView` per entry in the `permissions` array passed to
  `init(permissions:checker:)`, in that array's order, and MUST NOT create
  a row for any permission not present in that array.
- **checker-default**: The component MUST pass the
  `checker` supplied to `init(permissions:checker:)` to every row it
  creates and to its own action handling, and MUST default `checker` to a
  freshly constructed `SystemPermissionChecker()` when the caller supplies
  none.
- **rows-in-full-bleed-vertical-stack**: The component MUST lay out its
  rows in a vertical `NSStackView` with 8pt spacing and `.leading`
  alignment, and MUST pin that stack's top, leading, trailing, and bottom
  edges to its own corresponding edges with no additional inset.
- **row-width-pinned-to-stack**: Each row's width MUST be constrained equal
  to the stack's width, so every row spans the full width of the panel.
- **layout-built-once**: The component MUST build its row layout exactly
  once, during initialization, and MUST NOT add, remove, or rebuild rows
  afterward for the life of the instance.
- **refreshes-serially-in-order**: The component's `refresh()` operation
  MUST re-read status by calling each row's own `refresh()` in the same
  order the rows were created, and MUST await each row's refresh to
  complete before starting the next row's.
- **refresh-aborts-on-cancellation**: `refresh()` MUST stop before
  refreshing any further row as soon as its enclosing task is cancelled,
  leaving any not-yet-reached row's displayed status unchanged.
- **activation-observer**: The component MUST
  begin observing `NSApplication.didBecomeActiveNotification` the first
  time it moves to a non-nil window, and MUST NOT register that observer a
  second time on any subsequent move to a non-nil window.
- **schedules-refresh-on-window-attach**: Moving to a non-nil window MUST
  schedule a refresh of every row.
- **schedules-refresh-on-app-activation**: The host application becoming
  active MUST schedule a refresh of every row.
- **latest-refresh-wins**: Scheduling a refresh MUST cancel any refresh
  already in flight before starting the new one, so that of any two
  refreshes that overlap, only the one scheduled last can apply its
  results to the rows.
- **action-refresh**: A row's action callback MUST
  first await `PermissionPresenter.present(_:shownAs:using:)` for that
  row's permission and displayed status, and MUST schedule (not await) a
  refresh only after that call returns.
- **cancels-refresh-and-observer-on-deinit**: Deinitialization MUST cancel
  any in-flight refresh task and MUST remove the component's notification
  observer.
- **coder-init-unavailable**: `init(coder:)` MUST be marked unavailable at
  compile time and MUST call `fatalError` if invoked at runtime.
- **supports-direct-refresh**: The component MUST expose a public
  `refresh()` operation that awaits a full re-read of every row's status,
  independent of the window-attach and app-activation triggers.

## Appearance

- **Corner radius**: None set by this component itself; `PermissionsPanelView`
  draws no background or border of its own. (Each row's own 8pt card corner
  radius is `PermissionRowView`'s concern.)
- **Padding**: 0pt on all sides — the stack view is pinned to the panel's
  own edges with no constant (see `rows-in-full-bleed-vertical-stack`).
  Between rows, the vertical stack applies 8pt of spacing.
- **Font**: Not applicable. The component creates no text element of its
  own; all label fonts belong to `PermissionRowView`.
- **Background**: None set. `PermissionsPanelView` does not set
  `wantsLayer` or a background color; it is a transparent layout container.
- **Foreground/Text**: Not applicable. The component renders no text of
  its own.
- **Border**: None set on the panel itself.
- **Shadow**: None specified in source.
- **Min/Max size**: None set. The panel's size is whatever its pinned
  stack view resolves to from its arranged rows.

## Accessibility

- Role/trait: Not applicable at this component's level. The component
  never calls `setAccessibilityElement` or overrides any accessibility
  role; it is a plain `NSView` container, and VoiceOver traverses directly
  into each row's own accessibility elements.
- Label requirements: Not applicable. The component creates no accessible
  label of its own; every row's title, description, and status text carry
  their own labeling, as does that row's action button.
- Announce state changes: Not applicable at this component's level. The
  component issues no accessibility notification of its own when a
  refresh completes; a status change is reflected as an ordinary
  text/color update inside the affected row, which is
  `PermissionRowView`'s concern.
- Minimum tap target: Not applicable. The component has no tappable
  surface of its own — the tap targets are each row's action button,
  sized by `PermissionRowView`.
- Keyboard navigation: Not applicable. The component sets no custom
  key-view loop, first responder, or key-equivalent; whatever tab order
  AppKit derives automatically from the arranged-subview hierarchy
  applies unmodified.

- Grouping: The component calls no accessibility-grouping API of its own
  (no `setAccessibilityElement`, `setAccessibilityRole`, or
  `setAccessibilityLabel`) on itself, so VoiceOver gets no grouping cue for
  the row list beyond the plain view hierarchy and traverses straight into
  each row's own accessibility elements (`buildLayout()`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `permissions` | `[Permission]` | required (no default) | The permissions to show, one row per entry, in the given order; captured once at `init` and never re-read afterward. |
| `checker` | `any PermissionChecking` | `SystemPermissionChecker()` | Supplies live status reads and grant requests to every row and to the panel's own action handling. |

## Accessibility Options

- **Reduce Motion**: Not applicable. The component makes no layout
  changes after initialization (see **layout-built-once**) and contains
  no animation, transition, or animator-proxy call.
- **Increase Contrast**: Not applicable at this component's level. The
  component sets no color of its own; every color value used on screen
  belongs to `PermissionRowView`.
- **Differentiate Without Color**: Not applicable at this component's
  level, for the same reason — the component draws no color-conveyed
  state of its own for a "differentiate without color" setting to act on.

## Privacy

- **Data collected**: None collected by this component itself. It holds
  the `permissions` array it was constructed with (which privacy
  permissions to display) and forwards status/request calls to the
  injected `checker`; it inspects no personal data itself.
- **Storage**: None. The component writes nothing to disk, `UserDefaults`,
  or the keychain. (Recording a remembered keychain grant is
  `SystemPermissionChecker`/`KeychainPermissionLedger`'s responsibility, a
  different component's concern.)
- **Transmission**: None directly. Any cross-process communication a
  status read or grant request needs (an Apple Event, a system consent
  dialog, a `CLLocationManager` round trip, etc.) happens inside the
  injected `checker`, not in the component itself.
- **Retention**: None beyond the life of the instance. The panel keeps its
  `permissions` array and its live `rows` in memory only; it persists
  nothing across launches.

