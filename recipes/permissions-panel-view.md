---
id: 07388a5c-901d-4cf3-b818-bf52c180be08
title: Permissions Panel View
domain: agentictoolkit://recipes/permissions-panel-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit NSView; stacks one PermissionRowView per permission and drives refresh
  on window attach, app activation, and after a grant action.
platforms:
- swift
- macos
tags:
- permissions
- settings
- macos
- appkit
depends-on: []
related: []
references:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
approved-by: ''
approved-date: ''
---

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

## Behavioral Requirements

- **one-row-per-permission-in-order**: The component MUST create exactly
  one `PermissionRowView` per entry in the `permissions` array passed to
  `init(permissions:checker:)`, in that array's order, and MUST NOT create
  a row for any permission not present in that array.
- **checker-injected-with-system-default**: The component MUST pass the
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
- **starts-observing-activation-on-window-attach**: The component MUST
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
- **presents-then-refreshes-after-action**: A row's action callback MUST
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
- **Font**: Not applicable. This file creates no text element of its own;
  all label fonts belong to `PermissionRowView`.
- **Background**: None set. `PermissionsPanelView` does not set
  `wantsLayer` or a background color; it is a transparent layout container.
- **Foreground/Text**: Not applicable. This file renders no text.
- **Border**: None set on the panel itself.
- **Shadow**: None specified in source.
- **Min/Max size**: None set. The panel's size is whatever its pinned
  stack view resolves to from its arranged rows.

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders one row per entry in `permissions`, in order, inside the full-bleed vertical stack described in Appearance. |
| Pressed | Not applicable: the panel itself has no pressable surface; each row's own action button owns its pressed state. |
| Disabled | Not applicable: source defines no enabled/disabled toggle or appearance for this component. |
| Focused | Not applicable: source sets no custom focus-ring or key-view-loop behavior on the panel; each row's own focusable button is that row's concern. |
| Loading | Not applicable at this component's level: the panel shows no loading indicator of its own; each row independently reflects its own in-flight refresh (`PermissionRowView`'s "Checking…" state), and the panel only orchestrates when those per-row refreshes are triggered. |

## Accessibility

- Role/trait: Not applicable at this component's level. `PermissionsPanelView`
  never calls `setAccessibilityElement` or overrides any accessibility
  role; it is a plain `NSView` container, and VoiceOver traverses directly
  into each row's own accessibility elements.
- Label requirements: Not applicable. This file creates no accessible
  label of its own; every row's title, description, and status text carry
  their own labeling, as does that row's action button.
- Announce state changes: Not applicable at this component's level. The
  panel issues no accessibility notification of its own when a refresh
  completes; a status change is reflected as an ordinary text/color update
  inside the affected row, which is `PermissionRowView`'s concern.
- Minimum tap target: Not applicable. The panel has no tappable surface of
  its own — the tap targets are each row's action button, sized by
  `PermissionRowView`.
- Keyboard navigation: Not applicable. `PermissionsPanelView.swift` sets no
  custom key-view loop, first responder, or key-equivalent; whatever tab
  order AppKit derives automatically from the arranged-subview hierarchy
  applies unmodified.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| permissions-panel-view-001 | one-row-per-permission-in-order | Construct with `permissions == [.accessibility, .microphone, .location]`. | Exactly 3 `PermissionRowView` instances are created, arranged in that same order. |
| permissions-panel-view-002 | checker-injected-with-system-default | Construct with a fake `PermissionChecking`; separately, construct via `init(permissions:)` with no checker argument. | Every row from the first construction holds the identical injected checker instance; the second construction's rows hold a `SystemPermissionChecker`. |
| permissions-panel-view-003 | rows-in-full-bleed-vertical-stack | Construct the view and inspect its subview and constraints. | The sole subview is a vertical `NSStackView` with `spacing == 8` and `alignment == .leading`, whose top/leading/trailing/bottom anchors equal the panel's own with a 0 constant. |
| permissions-panel-view-004 | row-width-pinned-to-stack | Construct with 2 permissions and inspect each row's active constraints. | Each row has an active constraint equating its `widthAnchor` to the stack's `widthAnchor`. |
| permissions-panel-view-005 | layout-built-once | Construct the view, then trigger several refreshes and an app activation. | The subview/row count and identities are unchanged after any of those events. |
| permissions-panel-view-006 | refreshes-serially-in-order | Inject a checker whose `status(_:)` records call order and yields before returning; call `refresh()`. | Calls to `checker.status` occur one at a time, in row order — the second call is not made until the first row's `refresh()` has completed. |
| permissions-panel-view-007 | refresh-aborts-on-cancellation | Start `refresh()` in a task; cancel that task after the first row's status resolves but before the second row's refresh begins. | No row after the first ever has `checker.status` called for it during that run. |
| permissions-panel-view-008 | starts-observing-activation-on-window-attach | Add the view to a window, remove it from that window, then add it to a window again; post one activation notification afterward. | Each row's `refresh()` is invoked exactly once for that single posted notification (no duplicate refresh from a doubly-registered observer). |
| permissions-panel-view-009 | schedules-refresh-on-window-attach | Add a view with rows to a window. | Each row's `refresh()` is invoked shortly after the attach. |
| permissions-panel-view-010 | schedules-refresh-on-app-activation | With the view already attached to a window, post `NSApplication.didBecomeActiveNotification`. | Each row's `refresh()` is invoked again. |
| permissions-panel-view-011 | latest-refresh-wins | Trigger a window attach and, before its refresh completes, immediately post an activation notification. | The first refresh's task is cancelled; only the second (activation-triggered) refresh's results are applied to the rows. |
| permissions-panel-view-012 | presents-then-refreshes-after-action | Simulate a row's action callback firing, with a `PermissionPresenter.present` stand-in that is slow to return. | `present` is awaited to completion before a new refresh is scheduled; the code path that schedules the refresh does not itself await that refresh's completion. |
| permissions-panel-view-013 | cancels-refresh-and-observer-on-deinit | Start a refresh, deallocate the view before it completes, then post an activation notification. | The in-flight refresh task is cancelled with no crash; the posted notification produces no further row update from the deallocated instance. |
| permissions-panel-view-014 | coder-init-unavailable | Attempt to construct the view via `NSCoder`-based decoding. | Compilation fails (the initializer is unavailable), or a runtime `fatalError` occurs if that is bypassed. |
| permissions-panel-view-015 | supports-direct-refresh | Call `refresh()` directly, with no window attach or activation event having occurred. | All rows' `refresh()` are invoked and the call returns only once every row's refresh has completed. |

## Edge Cases

- **Null/empty input** (MUST): `permissions` MUST be permitted to be an
  empty array. The component MUST then build zero rows, and `refresh()`
  MUST complete immediately with no row refreshed — both `buildLayout()`'s
  and `refresh()`'s `for` loops iterate the given collection with no
  special-casing for zero elements.
- **Boundary values** (MUST): Not applicable in the constrained-range sense
  — `permissions` has no minimum or maximum length enforced in source. A
  `permissions` array containing the same `Permission` value more than once
  (for example two `.accessibility` entries) MUST still produce one row per
  entry, including the duplicate: `buildLayout()`'s `for permission in
  permissions` performs no deduplication.
- **Concurrent access** (MUST): Every property and method in this file is
  `@MainActor`-isolated, so all mutation of `rows`, `refreshTask`, and
  `isObserving` is serialized onto the main actor. Window attach, app
  activation, and a completed grant action can all ask for a refresh in
  close succession; the component MUST resolve that through the
  cancel-and-replace pattern in `scheduleRefresh()` (see
  `latest-refresh-wins`), cancelling whatever task `refreshTask` already
  holds before assigning the new one.
- **Error states** (MUST): `PermissionChecking.status(_:)` and
  `.request(_:)` are non-throwing, so this file has no `catch` path and
  performs no error handling of its own. `PermissionStatus` has no
  "error" case, so a misbehaving checker implementation can only surface
  as `.granted`, `.denied`, or `.undetermined` — this component does not
  detect or separately report a failing checker.
- **Offline/disconnected state**: Not applicable. `PermissionsPanelView.swift`
  makes no network call directly; any network or cross-process dependency a
  particular permission's status check has is the injected `checker`'s
  concern, not this component's.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `permissions` | `[Permission]` | required (no default) | The permissions to show, one row per entry, in the given order; captured once at `init` and never re-read afterward. |
| `checker` | `any PermissionChecking` | `SystemPermissionChecker()` | Supplies live status reads and grant requests to every row and to the panel's own action handling. |

## Deep Linking

Not applicable: `PermissionsPanelView.swift` contains no URL-scheme or
route handling of its own. (Opening a System Settings pane by URL is
`PermissionPresenter`'s responsibility, driven by `Permission.settingsPaneURL`
— a separate file from this component.)

## Localization

Not applicable: `PermissionsPanelView.swift` defines no user-facing string
literal of its own. All row text — title, description, status, and action
button titles — originates from `PermissionRowView` and `Permission`, not
this file.

## Accessibility Options

- **Reduce Motion**: Not applicable. This file contains no animation,
  transition, or animator-proxy call; it changes constraints and reload
  state, not motion.
- **Increase Contrast**: Not applicable at this component's level.
  `PermissionsPanelView.swift` sets no color of its own; every color value
  used on screen belongs to `PermissionRowView`.
- **Differentiate Without Color**: Not applicable at this component's
  level, for the same reason — this file draws no color-conveyed state of
  its own for a "differentiate without color" setting to act on.

## Feature Flags

Not applicable: `PermissionsPanelView.swift` contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: `PermissionsPanelView.swift` contains no analytics or
event-tracking call.

## Privacy

- **Data collected**: None collected by this component itself. It holds
  the `permissions` array it was constructed with (which privacy
  permissions to display) and forwards status/request calls to the
  injected `checker`; it inspects no personal data itself.
- **Storage**: None. `PermissionsPanelView.swift` writes nothing to disk,
  `UserDefaults`, or the keychain. (Recording a remembered keychain grant
  is `SystemPermissionChecker`/`KeychainPermissionLedger`'s responsibility,
  in a different file.)
- **Transmission**: None directly. Any cross-process communication a
  status read or grant request needs (an Apple Event, a system consent
  dialog, a `CLLocationManager` round trip, etc.) happens inside the
  injected `checker`, not in this file.
- **Retention**: None beyond the life of the instance. The panel keeps its
  `permissions` array and its live `rows` in memory only; it persists
  nothing across launches.

## Logging

Not applicable: `PermissionsPanelView.swift` contains no `os_log`,
`Logger`, or other logging call.

## Platform Notes

- **SwiftUI**: A SwiftUI counterpart would be a `PermissionsPanel: View`
  holding `permissions: [Permission]` and a checker, laying out a
  `VStack(alignment: .leading, spacing: 8)` of one `PermissionRow` per
  permission (mirroring the `NSStackView` here). `viewDidMoveToWindow`'s
  refresh-on-appear maps to `.task { await refreshAll() }` on the stack;
  the app-activation refresh maps to observing `scenePhase` (or an
  `NSApplication.didBecomeActiveNotification` publisher on macOS) and
  re-running the same refresh; the cancel-and-replace "latest wins"
  pattern maps to reassigning a `Task` handle stored in state, cancelling
  the previous one before starting a new one, exactly as `scheduleRefresh()`
  does.
- **Compose**: Android's permission model has no per-item equivalent to
  Accessibility, Automation, or Keychain grants, so a literal port does not
  apply — treat this as guidance for whichever permissions do map. Lay out
  a `Column(verticalArrangement = Arrangement.spacedBy(8.dp))` of one
  permission-row composable per entry; drive the request flow through
  `rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission())`
  in place of `PermissionPresenter.present`; refresh on the composable
  entering composition (`LaunchedEffect(Unit)`) and again on resume via a
  `DisposableEffect` observing `Lifecycle.Event.ON_RESUME` — the Compose
  analog of the window-attach and app-activation triggers here — cancelling
  and relaunching the refresh coroutine the same way `scheduleRefresh()`
  cancels and reassigns `refreshTask`.
- **React/Web**: The permissions this component lists (Accessibility,
  Automation, Screen Capture, Keychain) have no web equivalent; only
  Notifications, Location, and Microphone map to the web Permissions API
  (`navigator.permissions.query`, `Notification.requestPermission`,
  `getUserMedia`). Render a flex column of permission rows with 8px gaps;
  refresh once on mount (`useEffect(() => { refreshAll() }, [])`, mirroring
  `viewDidMoveToWindow`) and again on a `visibilitychange` listener when
  the document becomes visible (mirroring app activation); the
  cancel-and-replace refresh pattern maps to an `AbortController` (or a
  ref holding the latest request id) that a new refresh call replaces
  before its own run starts.
- **AppKit / UIKit**: This is the source platform (AppKit, macOS):
  `PermissionsPanelView.swift` (this file — the container, layout, and
  refresh orchestration), `PermissionRowView.swift` (the per-permission
  card), `PermissionPresenter.swift` (the grant-flow dispatch this
  component's rows call into), and `PermissionChecking.swift`/
  `SystemPermissionChecker.swift` (the injected status/request provider).
  UIKit has no drop-in counterpart: iOS's permission set and its consent
  flows (App Tracking Transparency, `CLLocationManager`, etc.) differ
  enough from macOS's TCC permissions that this component's structure
  (one card per `Permission` case, refresh on appear/foreground) is the
  part worth porting to a `UICollectionView`/`UIStackView` layout, not a
  line-for-line translation of the permission set itself.
- **WinUI 3**: Model the vertical stack as a `StackPanel` with
  `Orientation="Vertical"` and `Spacing="8"` (or an `ItemsRepeater` bound
  to an `ObservableCollection` of row view models), hosting one custom
  `PermissionRow` `UserControl` per permission — WinUI's `StackPanel`
  stretches children cross-axis by default when the child's
  `HorizontalAlignment` is left at `Stretch`, so the explicit per-row
  width constraint this AppKit file needs (`row-width-pinned-to-stack`)
  has no direct WinUI analog and can usually be dropped rather than
  translated. Map the window-attach refresh to the panel's `Loaded` event
  and the app-activation refresh to the hosting `Window`'s `Activated`
  event (the WinUI analog of `NSApplication.didBecomeActiveNotification`);
  implement `latest-refresh-wins` with a `CancellationTokenSource` field
  that a `RefreshAsync()` method cancels and replaces before starting its
  new pass, mirroring `refreshTask?.cancel()` followed by a fresh `Task`
  assignment. A completed grant action awaits its own flow, then calls
  `RefreshAsync()` without awaiting it — matching
  `presents-then-refreshes-after-action` — and each row's own "open
  settings" affordance uses `Windows.System.Launcher.LaunchUriAsync` with
  an `ms-settings:` URI, the Windows analog of this component's
  `x-apple.systempreferences:` pane URLs (constructed in `Permission.swift`,
  not in this file).

## Design Decisions

Decision: Cancel any refresh already in flight before starting a new one
(`scheduleRefresh()`'s cancel-and-replace pattern), rather than letting
concurrent refreshes run to completion independently.
Rationale: source comments state that appearing, app reactivation, and a
finished grant action each ask for a refresh, and each row's status read
is a cross-process round trip they suspend on; left unserialized, whichever
refresh *resumed* last would win even if it was the older request — for
example landing a pre-grant snapshot after a post-grant one and leaving a
row reading "Not Granted" until the next activation. Cancelling the
in-flight refresh before starting a new one guarantees the most recently
requested refresh is the one that lands.
Approved: pending.

Decision: Schedule (not await) a refresh after `PermissionPresenter.present`
returns from a row's action.
Rationale: source comments state that returning from System Settings has
already fired a refresh through the activation notification, and the
action-triggered refresh — being requested later — is the one that should
land; scheduling rather than awaiting lets that later refresh cancel and
supersede the activation-triggered one via the same cancel-and-replace
pattern.
Approved: pending.

Decision: Pin each row's width explicitly to the stack's width, rather
than relying on the stack's own alignment.
Rationale: source comments state that a vertical `NSStackView` does not
stretch arranged subviews across its width — `alignment` governs cross-axis
*positioning*, not fill — so without this constraint each row would size
to its own intrinsic content width instead of spanning the panel.
Approved: pending.

Decision: Observe `NSApplication.didBecomeActiveNotification` rather than
`NSWorkspace.didActivateApplicationNotification`.
Rationale: source comments state the intent is to refresh when *this* app
becomes active (for example, the user returning from System Settings), not
on every app switch system-wide, which the `NSWorkspace` notification would
fire for.
Approved: pending.

Decision: Remove the notification observer explicitly in `deinit`, even
though selector-based observers have been auto-zeroed on dealloc since
macOS 10.11.
Rationale: source comments state this guards against a view deallocated
while still attached to a window leaving a dangling registration; the
explicit removal is defensive rather than strictly required by the current
minimum-deployment behavior.
Approved: pending.

## Compliance

No automated compliance checks have been run against this recipe yet. This
table will be populated by the cookbook's compliance tooling on review.

| Check | Status | Category |
|-------|--------|----------|

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
