<!-- leaf: implement-general-view-2/permissions-panel-view--part-2 · source: permissions-panel-view.md -->

# Permissions Panel View — continued (part 2)

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
  in place of `PermissionPresenter.present`; refresh on the composable
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
  `viewDidMoveToWindow`) and again on a `visibilitychange` listener when
  the document becomes visible (mirroring app activation); the
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
  registering the activation observer more than once. UIKit has no
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

**Decision**: Schedule (not await) a refresh after
`PermissionPresenter.present` returns from a row's action.
**Rationale**: Returning from System Settings has already fired a refresh
through the activation notification, and the action-triggered refresh —
being requested later — is the one that should land; scheduling rather
than awaiting lets that later refresh cancel and supersede the
activation-triggered one via the same cancel-and-replace pattern.
**Approved**: pending.

**Decision**: Pin each row's width explicitly to the stack's width,
rather than relying on the stack's own alignment.
**Rationale**: A vertical `NSStackView` does not stretch arranged
subviews across its width — `alignment` governs cross-axis *positioning*,
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
