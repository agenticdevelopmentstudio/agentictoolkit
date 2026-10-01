---
id: 07388a5c-901d-4cf3-b818-bf52c180be08
title: Permissions Panel View
domain: agentictoolkit://cookbook/system/permissions/permissions-panel-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings panel that stacks one permission row per permission and drives
  a refresh on first appearance, on app activation, and after a grant action completes.
platforms:
- swift
- macos
tags:
- permissions
- settings
depends-on:
- agentictoolkit://cookbook/system/permissions/permission-row-view
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Permissions Panel View

## Overview

This component is a drop-in settings panel: it builds one permission row
per permission it is given, wires each row's grant action through a shared
presenter, and keeps every row's live status current by refreshing when
the panel first appears, whenever the host application reactivates (for
example, the user returning from system settings), and after a row's grant
action completes. It runs no polling timer of its own and is free of any
settings-framework dependency, so any app or window can host it.

## Behavioral Requirements

- **one-row-per-permission-in-order**: The component MUST create exactly
  one row per entry in the permissions list it is constructed with, in
  that list's order, and MUST NOT create a row for any permission not
  present in that list.
- **checker-default**: The component MUST pass the status checker it was
  constructed with to every row it creates and to its own action handling,
  and MUST default to a freshly constructed system-backed checker when the
  caller supplies none.
- **rows-in-full-bleed-vertical-stack**: The component MUST lay out its
  rows in a vertical stack with 8pt spacing and leading alignment, and
  MUST pin that stack's top, leading, trailing, and bottom edges to its own
  corresponding edges with no additional inset.
- **row-width-pinned-to-stack**: Each row's width MUST be constrained equal
  to the stack's width, so every row spans the full width of the panel.
- **layout-built-once**: The component MUST build its row layout exactly
  once, during construction, and MUST NOT add, remove, or rebuild rows
  afterward for the life of the instance.
- **refreshes-serially-in-order**: The component's refresh operation MUST
  re-read status by calling each row's own refresh in the same order the
  rows were created, and MUST await each row's refresh to complete before
  starting the next row's.
- **refresh-aborts-on-cancellation**: Refreshing MUST stop before
  refreshing any further row as soon as its underlying asynchronous work
  is cancelled, leaving any not-yet-reached row's displayed status
  unchanged.
- **activation-observer**: The component MUST begin observing the host
  application's activation event the first time it becomes attached to a
  window, and MUST NOT register that observer a second time on any
  subsequent attach.
- **schedules-refresh-on-window-attach**: Becoming attached to a window
  MUST schedule a refresh of every row.
- **schedules-refresh-on-app-activation**: The host application becoming
  active MUST schedule a refresh of every row.
- **latest-refresh-wins**: Scheduling a refresh MUST cancel any refresh
  already in flight before starting the new one, so that of any two
  refreshes that overlap, only the one scheduled last can apply its
  results to the rows.
- **action-refresh**: A row's action callback MUST first await the shared
  presenter's grant flow for that row's permission and displayed status,
  and MUST schedule (not await) a refresh only after that call returns.
- **cancels-refresh-and-observer-on-deinit**: Tearing down the component
  MUST cancel any in-flight refresh and MUST remove the component's
  activation observer.
- **supports-direct-refresh**: The component MUST expose a public refresh
  operation that awaits a full re-read of every row's status, independent
  of the window-attach and app-activation triggers.

## Appearance

- **Corner radius**: None set by this component itself; it draws no
  background or border of its own. (Each row's own 8pt card corner radius
  is that row component's concern.)
- **Padding**: 0pt on all sides — the stack is pinned to the panel's own
  edges with no constant (see **rows-in-full-bleed-vertical-stack**).
  Between rows, the vertical stack applies 8pt of spacing.
- **Font**: Not applicable. The component creates no text element of its
  own; all label fonts belong to the row component.
- **Background**: None set. The component draws no background of its own;
  it is a transparent layout container.
- **Foreground/Text**: Not applicable. The component renders no text of
  its own.
- **Border**: None set on the panel itself.
- **Shadow**: None specified in source.
- **Min/Max size**: None set. The panel's size is whatever its pinned
  stack resolves to from its arranged rows.

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders one row per entry in the permissions list, in order, inside the full-bleed vertical stack described in Appearance. |
| Pressed | Not applicable: the panel itself has no pressable surface; each row's own action button owns its pressed state. |
| Disabled | Not applicable: source defines no enabled/disabled toggle or appearance for this component. |
| Focused | Not applicable: source sets no custom focus-ring or key-view-loop behavior on the panel; each row's own focusable button is that row's concern. |
| Loading | Not applicable at this component's level: the panel shows no loading indicator of its own; each row independently reflects its own in-flight refresh (the row component's "Checking…" state), and the panel only orchestrates when those per-row refreshes are triggered. |

## Accessibility

- Role/trait: Not applicable at this component's level. The component
  never marks itself as an accessibility element or overrides any
  accessibility role; it is a plain layout container, and assistive
  technology traverses directly into each row's own accessibility
  elements.
- Label requirements: Not applicable. The component creates no accessible
  label of its own; every row's title, description, and status text carry
  their own labeling, as does that row's action button.
- Announce state changes: Not applicable at this component's level. The
  component issues no accessibility notification of its own when a
  refresh completes; a status change is reflected as an ordinary
  text/color update inside the affected row, which is that row
  component's concern.
- Minimum tap target: Not applicable. The component has no tappable
  surface of its own — the tap targets are each row's action button,
  sized by the row component.
- Keyboard navigation: Not applicable. The component sets no custom
  key-view loop, first responder, or key-equivalent; whatever tab order
  the platform derives automatically from the arranged-subview hierarchy
  applies unmodified.

- Grouping: The component calls no accessibility-grouping operation of its
  own on itself, so assistive technology gets no grouping cue for the row
  list beyond the plain view hierarchy and traverses straight into each
  row's own accessibility elements.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| permissions-panel-view-001 | one-row-per-permission-in-order | Construct with permissions set to Accessibility, Microphone, and Location, in that order. | Exactly 3 rows are created, arranged in that same order. |
| permissions-panel-view-002 | checker-default | Construct with a fake status checker; separately, construct with no checker argument. | Every row from the first construction holds the identical injected checker instance; the second construction's rows hold a freshly constructed system-backed checker. |
| permissions-panel-view-003 | rows-in-full-bleed-vertical-stack | Construct the panel and inspect its layout. | The sole child is a vertical stack with 8pt spacing and leading alignment, whose top/leading/trailing/bottom edges equal the panel's own with no inset. |
| permissions-panel-view-004 | row-width-pinned-to-stack | Construct with 2 permissions and inspect each row's layout constraints. | Each row is constrained to the same width as the stack. |
| permissions-panel-view-005 | layout-built-once | Construct the panel, then trigger several refreshes and an app activation. | The row count and identities are unchanged after any of those events. |
| permissions-panel-view-006 | refreshes-serially-in-order | Inject a checker whose status operation records call order and yields before returning; call refresh. | Calls to the checker's status operation occur one at a time, in row order — the second call is not made until the first row's refresh has completed. |
| permissions-panel-view-007 | refresh-aborts-on-cancellation | Start a refresh as cancellable asynchronous work; cancel it after the first row's status resolves but before the second row's refresh begins. | No row after the first ever has its status read for it during that run. |
| permissions-panel-view-008 | activation-observer | Attach the panel to a window, detach it, then attach it to a window again; post one activation notification afterward. | Each row's refresh is invoked exactly once for that single posted notification (no duplicate refresh from a doubly-registered observer). |
| permissions-panel-view-009 | schedules-refresh-on-window-attach | Attach a panel with rows to a window. | Each row's refresh is invoked shortly after the attach. |
| permissions-panel-view-010 | schedules-refresh-on-app-activation | With the panel already attached to a window, post the app-activation notification. | Each row's refresh is invoked again. |
| permissions-panel-view-011 | latest-refresh-wins | Inject a checker whose status operation returns undetermined on its first call and granted on its second call for the same permission; trigger a window attach and, before its refresh completes, immediately post an activation notification. | Every row's displayed status ends up granted (the second call's result); no row is left showing undetermined (the first call's result). |
| permissions-panel-view-012 | action-refresh | Simulate a row's action callback firing, with a presenter stand-in that appends `"present"` to a shared call-order log before returning (slow to return), and a checker whose status operation appends `"status"` to that same log. | The log records `present` before any `status` entry, and the action callback's own asynchronous work returns control to its caller before the first `status` entry is appended — showing the resulting refresh runs as a separate, unawaited task. |
| permissions-panel-view-013 | cancels-refresh-and-observer-on-deinit | Start a refresh, tear down the panel before it completes, then post an activation notification. | The in-flight refresh is cancelled with no crash; the posted notification produces no further row update from the torn-down instance. |
| permissions-panel-view-015 | supports-direct-refresh | Call refresh directly, with no window attach or activation event having occurred. | All rows' refresh operations are invoked and the call returns only once every row's refresh has completed. |

## Edge Cases

- **Null/empty input** (MUST): the permissions list MUST be permitted to
  be empty. The component MUST then build zero rows, and refreshing MUST
  complete immediately with no row refreshed — both the row-construction
  step and the refresh operation iterate the given collection with no
  special-casing for zero elements.
- **Duplicate values** (MUST): a permissions list containing the same
  permission value more than once (for example two Accessibility entries)
  MUST still produce one row per entry, including the duplicate; the
  component performs no deduplication when building rows.
- **Concurrent access** (MUST): every property and operation of the
  component is confined to a single execution context, so its internal
  state is serialized. Window attach, app activation, and a completed
  grant action can all ask for a refresh in close succession; the
  component MUST resolve that through the cancel-and-replace pattern named
  in **latest-refresh-wins**, cancelling whatever refresh is already in
  flight before starting the new one.
- **Error states** (MUST): the status-checking and request operations are
  non-throwing, so the component has no failure path and performs no
  error handling of its own. The status value has no "error" case, so a
  misbehaving checker implementation can only surface as granted, denied,
  or undetermined — this component does not detect or separately report a
  failing checker.
- **Offline/disconnected state**: Not applicable. The component makes no
  network call directly; any network or cross-process dependency a
  particular permission's status check has is the injected checker's
  concern, not this component's.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| permissions | a list of permission values | required (no default) | The permissions to show, one row per entry, in the given order; captured once at construction and never re-read afterward. |
| checker | a status-checking dependency | a freshly constructed system-backed checker | Supplies live status reads and grant requests to every row and to the panel's own action handling. |

## Deep Linking

Not applicable: the component contains no URL-scheme or route handling of
its own. (Opening a system settings pane by URL is the shared presenter's
responsibility, driven by the permission's own settings-pane location, a
different component's concern.)

## Localization

Not applicable: the component defines no user-facing string literal of its
own. All row text — title, description, status, and action button titles
— originates from the row component and the permission model, not this
component.

## Accessibility Options

- **Reduce Motion**: Not applicable. The component makes no layout changes
  after construction (see **layout-built-once**) and contains no
  animation, transition, or animator-proxy call.
- **Increase Contrast**: Not applicable at this component's level. The
  component sets no color of its own; every color value used on screen
  belongs to the row component.
- **Differentiate Without Color**: Not applicable at this component's
  level, for the same reason — the component draws no color-conveyed
  state of its own for a "differentiate without color" setting to act on.

## Feature Flags

Not applicable: the component contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: the component contains no analytics or event-tracking
call.

## Privacy

- **Data collected**: None collected by this component itself. It holds
  the permissions list it was constructed with (which privacy permissions
  to display) and forwards status/request calls to the injected checker;
  it inspects no personal data itself.
- **Storage**: None. The component writes nothing to disk or to any
  persisted store. (Recording a remembered keychain grant is the status
  checker's own concern, a different component's responsibility.)
- **Transmission**: None directly. Any cross-process communication a
  status read or grant request needs (a system event, a system consent
  dialog, a location-service round trip, etc.) happens inside the injected
  checker, not in the component itself.
- **Retention**: None beyond the life of the instance. The panel keeps its
  permissions list and its live rows in memory only; it persists nothing
  across launches.

## Logging

Not applicable: the component contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: A SwiftUI counterpart would be a `PermissionsPanel: View`
  holding `permissions: [Permission]` and a checker, laying out a
  `VStack(alignment: .leading, spacing: 8)` of one `PermissionRow` per
  permission (mirroring the `NSStackView` here). `viewDidMoveToWindow`'s
  refresh-on-appear maps to `.task { await refreshAll() }` on the stack;
  the app-activation refresh maps to observing `scenePhase` (or an
  `NSApplication.didBecomeActiveNotification` publisher on macOS) and
  re-running the same refresh; the cancel-and-replace pattern named in
  **latest-refresh-wins** maps to reassigning a `Task` handle stored in
  state, cancelling the previous one before starting a new one.
- **Compose**: Android's permission model has no per-item equivalent to
  Accessibility, Automation, or Keychain grants, so a literal port does not
  apply — treat this as guidance for whichever permissions do map. Lay out
  a `Column(verticalArrangement = Arrangement.spacedBy(8.dp))` of one
  permission-row composable per entry; drive the request flow through
  `rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission())`
  in place of the shared presenter's grant flow; refresh on the composable
  entering composition (`LaunchedEffect(Unit)`) and again on resume via a
  `DisposableEffect` observing `Lifecycle.Event.ON_RESUME` — the Compose
  analog of the window-attach and app-activation triggers here — cancelling
  and relaunching the refresh coroutine the same way the source's
  cancel-and-replace pattern (**latest-refresh-wins**) does.
- **React/Web**: The permissions this component lists (Accessibility,
  Automation, Screen Capture, Keychain) have no web equivalent; only
  Notifications, Location, and Microphone map to the web Permissions API
  (`navigator.permissions.query`, `Notification.requestPermission`,
  `getUserMedia`). Render a flex column of permission rows with 8px gaps;
  refresh once on mount (`useEffect(() => { refreshAll() }, [])`, mirroring
  the window-attach trigger) and again on a `visibilitychange` listener
  when the document becomes visible (mirroring app activation); the
  cancel-and-replace refresh pattern maps to an `AbortController` (or a
  ref holding the latest request id) that a new refresh call replaces
  before its own run starts.
- **AppKit / UIKit**: This is the source platform (AppKit, macOS):
  `PermissionsPanelView.swift` (the container, layout, and refresh
  orchestration), `PermissionRowView.swift` (the per-permission card),
  `PermissionPresenter.swift` (the grant-flow dispatch this component's
  rows call into), and `PermissionChecking.swift`/
  `SystemPermissionChecker.swift` (the injected status/request provider).
  Internally, `PermissionsPanelView.swift`'s private `buildLayout()`
  constructs the row hierarchy once from `init`; its private
  `scheduleRefresh()` implements the cancel-and-replace pattern by
  cancelling and reassigning the private `refreshTask` field; and its
  private `isObserving` flag guards `startObservingActivation()` against
  registering the activation observer more than once. Because
  `AgenticDeveloperToolkit` also exports a type named `Permission`, a
  caller whose target imports both modules must spell this component's
  permission type `AgenticToolkitPermissions.Permission` to resolve the
  ambiguity. `PermissionsPanelView.init(coder:)` is marked
  `@available(*, unavailable)` at compile time and calls `fatalError` if
  invoked at runtime, since this component is never instantiated from a
  storyboard or nib; conformance for that guarantee is a build that fails
  to compile a call to it, or a runtime `fatalError` if that unavailability
  is bypassed (for example through Objective-C bridging). UIKit has no
  drop-in counterpart: iOS's permission set and its consent flows (App
  Tracking Transparency, `CLLocationManager`, etc.) differ enough from
  macOS's TCC permissions that this component's structure (one card per
  `Permission` case, refresh on appear/foreground) is the part worth
  porting to a `UICollectionView`/`UIStackView` layout, not a
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
  new pass, mirroring the source's own cancel-and-replace pattern. A
  completed grant action awaits its own flow, then calls
  `RefreshAsync()` without awaiting it — matching **action-refresh** — and
  each row's own "open settings" affordance uses
  `Windows.System.Launcher.LaunchUriAsync` with an `ms-settings:` URI, the
  Windows analog of this component's `x-apple.systempreferences:` pane
  URLs (constructed in `Permission.swift`, a different component's
  concern).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/PermissionsUI/PermissionsPanelView.swift` |

## Design Decisions

**Decision**: Cancel any refresh already in flight before starting a new
one (the cancel-and-replace pattern named in **latest-refresh-wins**),
rather than letting concurrent refreshes run to completion independently.
**Rationale**: Appearing, app reactivation, and a finished grant action
each ask for a refresh, and each row's status read is a cross-process
round trip they suspend on; left unserialized, whichever refresh *resumed*
last would win even if it was the older request — for example landing a
pre-grant snapshot after a post-grant one and leaving a row reading "Not
Granted" until the next activation. Cancelling the in-flight refresh
before starting a new one guarantees the most recently requested refresh
is the one that lands.
**Approved**: pending.

**Decision**: Schedule (not await) a refresh after the shared presenter's
grant flow returns from a row's action.
**Rationale**: Returning from system settings has already fired a refresh
through the activation notification, and the action-triggered refresh —
being requested later — is the one that should land; scheduling rather
than awaiting lets that later refresh cancel and supersede the
activation-triggered one via the same cancel-and-replace pattern.
**Approved**: pending.

**Decision**: Pin each row's width explicitly to the stack's width,
rather than relying on the stack's own alignment.
**Rationale**: A vertical stack does not stretch arranged subviews across
its width on this platform — alignment governs cross-axis *positioning*,
not fill — so without this constraint each row would size to its own
intrinsic content width instead of spanning the panel.
**Approved**: pending.

**Decision**: Observe `NSApplication.didBecomeActiveNotification` rather
than `NSWorkspace.didActivateApplicationNotification`.
**Rationale**: The intent is to refresh when *this* app becomes active
(for example, the user returning from System Settings), not on every app
switch system-wide, which the `NSWorkspace` notification would fire for.
**Approved**: pending.

**Decision**: Remove the notification observer explicitly in `deinit`,
even though the `NotificationCenter.addObserver(_:selector:name:object:)`
registration this component uses has been auto-zeroed on dealloc since
macOS 10.11.
**Rationale**: This guards against a view deallocated while still
attached to a window leaving a dangling registration; because the
observer is registered through the selector-based API rather than a
block-based one, removal here is defensive rather than strictly required
by the current minimum-deployment behavior.
**Approved**: pending.

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |

`screen-reader-support` is partial because the component registers no
accessibility-grouping role for its row list (see Accessibility);
`keyboard-navigable` passed because the source overrides
no key-view loop, first responder, or key-equivalent, leaving AppKit's
automatic tab order across the arranged rows intact.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reworded file-centric phrasing ("this file", `PermissionsPanelView.swift`, "source comments state") to describe the component's observable behavior and moved private identifiers (`buildLayout()`, `scheduleRefresh()`, `refreshTask`, `isObserving`) into the AppKit/UIKit Platform Notes bullet; noted the `AgenticToolkitPermissions.Permission` module-qualification needed alongside ADT; added `permission-row-view` to `depends-on`; moved the platform-design-languages guideline from `references` to `related`; renamed the `checker-injected-with-system-default`, `starts-observing-activation-on-window-attach`, and `presents-then-refreshes-after-action` requirements to subject-only names (`checker-default`, `activation-observer`, `action-refresh`) and updated their citations; reworded the duplicate-permissions edge case to drop its "Not applicable" lead-in; rewrote vectors 011 and 012 to assert observable outcomes through a fake checker and a call-order log, and moved vector 014 (a compile-time check) to a note; corrected the Reduce Motion note that contradicted `layout-built-once`; flagged the panel's missing VoiceOver grouping role as an open question; bolded the Design Decisions labels and named the exact `NotificationCenter` observer API; and filled in the Compliance table. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to system/permissions/. |
