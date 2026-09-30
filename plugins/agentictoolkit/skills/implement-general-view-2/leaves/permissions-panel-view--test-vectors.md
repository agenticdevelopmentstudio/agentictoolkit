<!-- leaf: implement-general-view-2/permissions-panel-view--test-vectors · source: permissions-panel-view.md -->

# Permissions Panel View

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| permissions-panel-view-001 | one-row-per-permission-in-order | Construct with `permissions == [.accessibility, .microphone, .location]`. | Exactly 3 `PermissionRowView` instances are created, arranged in that same order. |
| permissions-panel-view-002 | checker-default | Construct with a fake `PermissionChecking`; separately, construct via `init(permissions:)` with no checker argument. | Every row from the first construction holds the identical injected checker instance; the second construction's rows hold a `SystemPermissionChecker`. |
| permissions-panel-view-003 | rows-in-full-bleed-vertical-stack | Construct the view and inspect its subview and constraints. | The sole subview is a vertical `NSStackView` with `spacing == 8` and `alignment == .leading`, whose top/leading/trailing/bottom anchors equal the panel's own with a 0 constant. |
| permissions-panel-view-004 | row-width-pinned-to-stack | Construct with 2 permissions and inspect each row's active constraints. | Each row has an active constraint equating its `widthAnchor` to the stack's `widthAnchor`. |
| permissions-panel-view-005 | layout-built-once | Construct the view, then trigger several refreshes and an app activation. | The subview/row count and identities are unchanged after any of those events. |
| permissions-panel-view-006 | refreshes-serially-in-order | Inject a checker whose `status(_:)` records call order and yields before returning; call `refresh()`. | Calls to `checker.status` occur one at a time, in row order — the second call is not made until the first row's `refresh()` has completed. |
| permissions-panel-view-007 | refresh-aborts-on-cancellation | Start `refresh()` in a task; cancel that task after the first row's status resolves but before the second row's refresh begins. | No row after the first ever has `checker.status` called for it during that run. |
| permissions-panel-view-008 | activation-observer | Add the view to a window, remove it from that window, then add it to a window again; post one activation notification afterward. | Each row's `refresh()` is invoked exactly once for that single posted notification (no duplicate refresh from a doubly-registered observer). |
| permissions-panel-view-009 | schedules-refresh-on-window-attach | Add a view with rows to a window. | Each row's `refresh()` is invoked shortly after the attach. |
| permissions-panel-view-010 | schedules-refresh-on-app-activation | With the view already attached to a window, post `NSApplication.didBecomeActiveNotification`. | Each row's `refresh()` is invoked again. |
| permissions-panel-view-011 | latest-refresh-wins | Inject a checker whose `status(_:)` returns `.undetermined` on its first call and `.granted` on its second call for the same permission; trigger a window attach and, before its refresh completes, immediately post an activation notification. | Every row's displayed status ends up `.granted` (the second call's result); no row is left showing `.undetermined` (the first call's result). |
| permissions-panel-view-012 | action-refresh | Simulate a row's action callback firing, with a `PermissionPresenter.present` stand-in that appends `"present"` to a shared call-order log before returning (slow to return), and a checker whose `status(_:)` appends `"status"` to that same log. | The log records `present` before any `status` entry, and the action callback's own asynchronous work returns control to its caller before the first `status` entry is appended — showing the resulting refresh runs as a separate, unawaited task. |
| permissions-panel-view-013 | cancels-refresh-and-observer-on-deinit | Start a refresh, deallocate the view before it completes, then post an activation notification. | The in-flight refresh task is cancelled with no crash; the posted notification produces no further row update from the deallocated instance. |
| permissions-panel-view-015 | supports-direct-refresh | Call `refresh()` directly, with no window attach or activation event having occurred. | All rows' `refresh()` are invoked and the call returns only once every row's refresh has completed. |

`coder-init-unavailable` is a compile-time guarantee (`@available(*, unavailable)` on `init(coder:)`) rather than something a runtime test vector observes; conformance is a build that fails to compile a call to it, or a runtime `fatalError` if that unavailability is bypassed (for example through Objective-C bridging).
