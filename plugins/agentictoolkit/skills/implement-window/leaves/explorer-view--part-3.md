<!-- leaf: implement-window/explorer-view--part-3 · source: window-explorer-view.md -->

# WindowExplorerView — continued (part 3)

**Rules** (cite as `implement-window/explorer-view--part-3#<slug>`):

- `decision` MUST — Prune stale ids from selectedWindowIDs after a scan only when activeGroupID == nil; never prune when it is non-nil. …

## Platform Notes

- **SwiftUI**: this is the source form. File:
  `packages/apple/AgenticToolkit/macOS/SystemWindows/UI/WindowExplorerView.swift`.
  It reads `@EnvironmentObject private var appState: SystemWindowContextsModel`
  and a custom `@Environment(\.theme)` palette, builds its list with
  `List`/`Section`/`ForEach` and `.toggleStyle(.checkbox)` — a macOS-only
  `ToggleStyle` with no UIKit/iOS equivalent — and runs its scan on
  `Task.detached` with `MainActor.run` hops for both reading app state and
  writing the result back, a concurrency pattern that itself has direct
  UIKit/iOS equivalents. The macOS-only surface is the `.checkbox` toggle
  style, the `ApplicationServices`-level `AXUIElement*` calls used for title
  enrichment, and the `AppKit`-only `NSRunningApplication`/`NSWorkspace`
  icon and bundle-id lookups — iOS has no cross-app Accessibility tree or
  running-application enumeration API to provide these.
- **Compose (Android/Desktop)**: there is no cross-app window-enumeration
  API on Android (apps are sandboxed from one another), so this recipe has
  no Android analog; on Compose for Desktop, the closest shape is a
  `LazyColumn` with sticky group headers per application, each header a
  `Checkbox` computing the same "all selectable windows in this group are
  selected" tri-state logic, each row a `Checkbox` + `Text` pair, backed by
  a `ViewModel` that performs the window enumeration on a background
  `CoroutineDispatcher` and posts results back on the main dispatcher, the
  same split this view achieves with `Task.detached` + `MainActor.run`.
- **React/Web**: browsers have no API to enumerate windows belonging to
  other applications, so a faithful port only exists inside an Electron (or
  similar desktop-web) shell using `desktopCapturer`/native window-listing
  APIs; render as a virtualized list grouped by app, each row an
  `<input type="checkbox">` bound to a shared selection `Set` in a
  store (Redux/Zustand), with a per-group header checkbox computing the
  same all-selected/some-selected logic and a `<button>` in place of the
  Accessibility banner's "Open Settings" action (Screen-Recording/
  Accessibility-style OS permission prompts have no direct web equivalent).
- **AppKit / UIKit**: a pure-AppKit rebuild would replace `List`/`Section`
  with an `NSOutlineView` (or a grouped `NSTableView`) — a group row per
  application (with its own `NSButton` checkbox styled `.checkbox` for
  select-all) and a leaf row per window, each leaf hosting an `NSButton`
  checkbox plus title/subtitle text fields in place of the SwiftUI `Toggle`
  labels. There is no UIKit/iOS counterpart: iOS apps cannot enumerate other
  apps' windows or query their Accessibility trees, so this component is
  macOS-only by platform capability, not merely by current implementation.
- **WinUI 3**: model the grouped list as a `ListView` bound to a
  `CollectionViewSource` with `IsSourceGrouped="True"`; each group's
  `GroupStyle.HeaderTemplate` holds a `CheckBox` (bound the same way as the
  select-all toggle here) plus the app's icon — retrieved via
  `AppDiagnosticInfo`/Shell icon extraction, since there is no
  `NSRunningApplication.icon` equivalent — and an `InfoBadge` for the window
  count. Each item template is a `CheckBox` whose content is a `StackPanel`
  with a `TextBlock` for the title (WinUI's built-in `TextTrimming` only
  truncates at the end, not the middle, so matching `.truncationMode(.middle)`
  needs a small value-converter that truncates the string itself before
  binding) and a second `TextBlock` for the `"<width>x<height>"` subtitle,
  plus an optional `Border` + `TextBlock` styled with `CornerRadius="8"` as
  the Capsule-equivalent context badge, `Background` bound to the same hex
  color with a `SolidColorBrush` opacity of 0.12. The Accessibility banner
  maps to an `InfoBar` with `Severity="Warning"` and an action `Button` —
  but Windows has no runtime accessibility-permission gate analogous to
  `AXIsProcessTrustedWithOptions`; window enumeration and title reads are
  not gated behind a user-grantable permission on Windows, so the banner
  and the permission check driving it (`needsAccessibility`) would have no
  real trigger condition on this platform and should be omitted rather than
  simulated with a fake permission state.

## Design Decisions

**Decision**: Prune stale ids from `selectedWindowIDs` after a scan only when
`activeGroupID == nil`; never prune when it is non-nil.
**Rationale**: in discovery mode the binding represents "windows currently
checked on screen," so an id for a window that vanished (closed, minimized,
now off-screen) is meaningless and MUST be dropped; in direct-assignment
mode the same binding instead represents persistent group membership, and a
member window that is merely not visible in *this* scan (e.g., a different
space, temporarily hidden) MUST NOT be silently unassigned from the group —
per the source comment directly above the prune.
**Approved**: pending

**Decision**: Fall back to the hard-coded `Color.blue` for a context badge when
`Color(hex: ctx.color)` returns `nil`, rather than a theme color.
**Rationale**: `Color(hex:)` returns `nil` only when the stored string is not a
valid 6-digit hex value, which should not occur for a color a context
stores through the app's own color picker; the fallback is a defensive
default for malformed data rather than an expected runtime path, which is
why it is a fixed system color rather than something drawn from the theme
palette.
**Approved**: pending
