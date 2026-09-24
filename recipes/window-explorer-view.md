---
id: 8aee173a-25e4-443e-a9ab-d629b58817e1
title: WindowExplorerView
domain: agentictoolkit://recipes/window-explorer-view
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Reusable macOS SwiftUI view listing running windows by app with selection
  checkboxes and Accessibility-permission handling.
platforms:
- swift
- macos
tags:
- window-explorer
- system-windows
- window-selection
- macos
- swiftui
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# WindowExplorerView

## Overview

`WindowExplorerView` (SwiftUI, macOS) is a reusable content view that lists
every running window, grouped into a section per owning application, each
with a selection checkbox. It is embedded by two callers that give it
different meanings: a discovery surface, where any visible window can be
checked, and a work-group direct-assignment surface, where windows already
belonging to the group being edited are toggled and windows owned by other
groups are shown but disabled. The view owns its own async window scan
(`refreshAsync()`), grouping, and Accessibility-based title enrichment; the
caller only owns the resulting `Set<UInt32>` of selected window ids via a
binding.

## Behavioral Requirements

- **renders-header-bar**: The view MUST show a header row containing, in
  order, a magnifying-glass icon, the label "Windows", a flexible spacer, and
  a refresh button.
- **disables-refresh-while-loading**: The refresh button MUST be disabled
  whenever a window scan is in progress (`isLoading == true`).
- **refreshes-on-appear**: The view MUST start a window scan the first time
  it appears (`.onAppear { refreshAsync() }`).
- **refreshes-on-app-activation-when-permission-missing**: The view MUST
  start a new window scan whenever the app receives
  `NSApplication.didBecomeActiveNotification`, but only if the most recent
  scan left `needsAccessibility == true`.
- **refreshes-on-external-notification**: When constructed with a non-nil
  `refreshNotification` name, the view MUST start a window scan whenever a
  notification with that name is posted; when `refreshNotification` is nil,
  this path MUST have no effect (`OptionalNotificationModifier`).
- **shows-accessibility-banner-when-permission-missing**: The view MUST
  display a banner reading "Accessibility permission needed for window
  titles." with an "Open Settings" action whenever the most recent scan
  found running windows but could not enrich any of them via Accessibility
  (`needsAccessibility == true`).
- **requests-accessibility-permission-from-banner**: Activating the banner's
  "Open Settings" action MUST invoke `SystemAccessibilityPermission.request()`.
- **shows-loading-state**: While a scan is in progress, the view MUST show an
  indeterminate progress indicator and the text "Scanning windows..." in
  place of the window list.
- **shows-empty-state**: When a completed scan produces no application
  groups, the view MUST show a "No windows found" message together with the
  hint "Make sure Accessibility permission is granted."
- **groups-windows-by-app**: Once loaded, the view MUST present windows as
  one section per owning application, with sections ordered
  case-insensitively ascending by application name.
- **shows-app-section-header**: Each application section header MUST show
  that application's running icon (or a fallback `app.fill` icon when no
  running icon is found), the application name, and a count of its windows
  in that section.
- **provides-select-all-toggle-per-section**: Each application section
  header MUST include a toggle that, when turned on, adds every selectable
  window in that section to `selectedWindowIDs`, and, when turned off,
  removes every selectable window in that section from `selectedWindowIDs`.
- **reflects-partial-selection-as-unchecked**: A section's select-all toggle
  MUST show the unchecked state unless the section has at least one
  selectable window and every selectable window in it is currently selected.
- **disables-select-all-when-nothing-selectable**: A section's select-all
  toggle MUST be disabled when that section has no selectable windows.
- **renders-window-row**: Each window row MUST show a toggle bound to that
  window's membership in `selectedWindowIDs`, the window's title (or
  "(untitled)" when the title is empty) limited to one line with middle
  truncation, and the window's dimensions formatted as
  `"<width>x<height>"` using integer point values.
- **shows-context-badge-on-owned-window**: A window row MUST show a badge
  naming its owning context, colored from that context's stored color,
  whenever the window already belongs to a context and either no
  `activeGroupID` is set or that context differs from `activeGroupID`.
- **disables-unselectable-window-row**: A window row's toggle MUST be
  disabled, and its title MUST be drawn in the secondary text color instead
  of the primary text color, whenever the window is not selectable.
- **determines-selectability-by-ownership**: A window MUST be selectable
  when it belongs to no context, or when it belongs to the context
  identified by `activeGroupID`; it MUST NOT be selectable when it belongs
  to any other context (`isSelectable(_:)`).
- **filters-scanned-windows**: A window scan MUST include only windows that
  belong to a regular running application (`activationPolicy == .regular`),
  are wider than 50 points, are taller than 50 points, are currently
  on-screen, whose owning application name is not in
  `appState.settings.hiddenApps`, and whose id is not in the view's
  `excludeWindowIDs`.
- **queries-accessibility-per-process**: A window scan MUST query the
  Accessibility (AX) window list of every distinct process id among the
  filtered windows (`AXUIElementCopyAttributeValue` with
  `kAXWindowsAttribute`), skipping any process for which that query does not
  succeed.
- **replaces-title-from-matched-accessibility-window**: A window scan MUST
  replace a window's title with an Accessibility window's title when that
  Accessibility window belongs to the same process and its position and size
  each differ from the CoreGraphics window's frame by less than 3 points on
  x, y, width, and height, and that Accessibility title is non-empty;
  otherwise the window's original title MUST be kept unchanged.
- **prunes-stale-selection-in-discovery-mode**: When `activeGroupID` is nil,
  completing a scan MUST remove from `selectedWindowIDs` any id that is not
  present among the windows the scan produced.
- **preserves-selection-in-assignment-mode**: When `activeGroupID` is
  non-nil, completing a scan MUST NOT remove any id from
  `selectedWindowIDs`, even if the window it identifies is not present among
  the windows the scan produced.

## Appearance

- **Corner radius**: Not applicable to the view's own chrome — no rounded
  rectangle is drawn directly; the window-count badge and the context badge
  are drawn with `Capsule()` (fully rounded ends), not a corner-radius
  value.
- **Padding**: Header row: 16pt horizontal, 8pt vertical
  (`.padding(.horizontal, 16).padding(.vertical, 8)`). Accessibility banner:
  the same 16pt horizontal / 8pt vertical. Section header content: 8pt
  spacing between icon, name, and count badge; the count badge additionally
  has 4pt horizontal padding. Window row content: 8pt spacing between the
  title/subtitle column and the trailing spacer; the title/subtitle `VStack`
  itself has 0pt spacing; the dimensions/badge row has 4pt spacing; the
  context badge has 4pt horizontal padding.
- **Font**: All fonts resolve through `theme.font(_:)`
  (`SwiftUIPalette.font(_:)` in `SemanticPalette+SwiftUI.swift`, wrapping the
  theme's typography as a SwiftUI `Font` per `TextRole`). Header icon and
  "Windows" label: `.heading`. "Scanning windows..." and the "Open Settings"
  banner button: `.caption`. Empty-state icon: `.title`. Window title:
  `.body`. Window dimensions: `.code`. App name and both badges (count,
  context): `.caption`, bolded (`.bold()`).
- **Background**: View background is not set explicitly (inherits the
  container's). Accessibility banner background: `theme.warning.opacity(0.1)`.
  Count badge background: `theme.primaryText.opacity(0.06)` inside a
  `Capsule()`. Context badge background: `(Color(hex: ctx.color) ??
  .blue).opacity(0.12)` inside a `Capsule()`. The window list itself uses
  `.listStyle(.inset(alternatesRowBackgrounds: true))`, which lets AppKit
  draw the alternating row backgrounds rather than any color this view
  supplies.
- **Foreground/Text**: `theme.secondaryText` for the header icon, a
  disabled/unselectable row's title, "Scanning windows...", "No windows
  found", and the fallback `app.fill` section icon. `theme.tertiaryText` for
  the empty-state icon, "Make sure Accessibility permission is granted.",
  window dimensions, and the count-badge number. `theme.primaryText` for a
  selectable row's title. `theme.warning` for the banner's exclamation-
  triangle icon. Context badge text/icon color is `Color(hex: ctx.color) ??
  .blue` — a hard-coded system blue, not a theme color, when the stored hex
  fails to parse.
- **Border**: Not applicable — no border is drawn anywhere in the source.
- **Shadow**: Not applicable — no shadow is drawn anywhere in the source.
- **Min/Max size**: The loading and empty states each set
  `.frame(maxWidth: .infinity, minHeight: 200)`; no maximum size is set
  anywhere, and the populated list has no minimum-height constraint of its
  own.

## States

| State | Appearance change |
|-------|------------------|
| Default | Populated: header bar, divider, and a sectioned list of app groups and window rows. |
| Pressed | Not applicable — the view applies no custom pressed styling; toggle and button press feedback is the system `.checkbox`/`.borderless`/`.bordered` chrome. |
| Disabled | Refresh button disabled while `isLoading`; a section's select-all toggle disabled when it has no selectable windows; a row's toggle disabled, and its title colored `theme.secondaryText`, when its window is not selectable. |
| Focused | Not applicable — no `.focused()`/custom focus-ring styling appears in source; standard keyboard focus rendering on each `Toggle`/`Button` applies unmodified. |
| Loading | List content replaced by a centered `ProgressView` (`.scaleEffect(0.8)`) and the caption "Scanning windows...", in a `minHeight: 200` frame. |
| Empty | After a completed scan with no application groups: a centered `macwindow.on.rectangle` icon, "No windows found", and the hint "Make sure Accessibility permission is granted.", in a `minHeight: 200` frame. |
| Accessibility banner shown | `needsAccessibility == true`: a warning-tinted banner is shown above whichever of Default, Loading, or Empty is otherwise active. |
| Section fully selected | Select-all toggle for that section shows checked. |
| Section partially or not selected | Select-all toggle for that section shows unchecked (covers both "some selected" and "none selected"). |
| Row's window owned by the active group | Toggle enabled, no context badge shown (the badge is suppressed when the owning context equals `activeGroupID`). |
| Row's window owned by a different context | Toggle disabled, title dimmed to `theme.secondaryText`, and a colored context-name badge is shown. |

## Accessibility

- Role/traits: standard SwiftUI/AppKit-backed controls only — `Toggle` with
  `.toggleStyle(.checkbox)` for every selection control (section select-all
  and per-window rows), `Button` with `.buttonStyle(.borderless)` for
  refresh and `.buttonStyle(.bordered)` for "Open Settings", and a `List`
  with `Section`s for the grouped content. No custom `accessibilityRole` or
  `accessibilityTraits` values are set anywhere in the file.
- Label requirements: each `Toggle`'s accessible label is its SwiftUI label
  view — the section header's icon/name/count `HStack` for the select-all
  toggle, and the title/dimensions/badge `VStack` for a row toggle — since
  no explicit `.accessibilityLabel` is set on either. The "Open Settings"
  button carries its own visible text as its label. **NEEDS REVIEW: the
  refresh button is icon-only (`Image(systemName: "arrow.clockwise")`) with
  no `.accessibilityLabel` set; it relies on the SF Symbol's implicit
  accessibility description plus `.help("Refresh window list")` (a tooltip
  hint, not a guaranteed VoiceOver label) to convey its purpose. Confirm
  with a VoiceOver pass on iOS/macOS whether the announced label clearly
  reads as "Refresh" before treating this as sufficient — resolvable by the
  toolkit's accessibility reviewer running VoiceOver over this button.**
- Announce state changes: the loading, empty, and populated states are
  distinct view trees that SwiftUI swaps directly (no `Text`/state is kept
  visible across the transition), and no `.accessibilityAddTraits`,
  UIAccessibility/NSAccessibility posting, or focus-move call accompanies
  any of these swaps. **NEEDS REVIEW: whether a VoiceOver user is reliably
  notified when a scan finishes (loading to list/empty) is not addressed in
  source — no explicit announcement or accessibility-focus change is made
  on that transition. Resolvable by a VoiceOver test of `refreshAsync()`'s
  completion, or by the toolkit's accessibility reviewer.**
- Minimum control size: macOS is a pointer-driven platform with no mandated
  minimum touch-target size (unlike iOS); the view uses standard
  `NSButton`/checkbox-style control sizing throughout — `.controlSize(.small)`
  on the banner's "Open Settings" button, and the system default size
  everywhere else — consistent with this being a pointer/keyboard surface
  rather than a value this view decides on its own.
- Keyboard/focus: every interactive element (`Toggle`, `Button`) is a
  standard, keyboard-focusable AppKit-backed control; no custom key
  handling or focus trapping is added in this file.
- Color/contrast: all text and background colors resolve through the shared
  theme palette (`theme.font(_:)` / `theme.<role>`), except the context
  badge's `Color(hex: ctx.color) ?? .blue` fallback, which is not a palette
  color; contrast is a design-system-level concern outside this view's own
  decisions, per
  `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages`.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| window-explorer-view-001 | renders-header-bar | Render the view | Header shows magnifying-glass icon, "Windows", spacer, refresh button, in that order. |
| window-explorer-view-002 | disables-refresh-while-loading | `isLoading == true` | Refresh button `isEnabled == false`. |
| window-explorer-view-003 | refreshes-on-appear | View appears for the first time | `refreshAsync()` is invoked without user action. |
| window-explorer-view-004 | refreshes-on-app-activation-when-permission-missing | `needsAccessibility == true`; app posts `didBecomeActiveNotification` | A new scan starts. |
| window-explorer-view-004b | refreshes-on-app-activation-when-permission-missing | `needsAccessibility == false`; app posts `didBecomeActiveNotification` | No new scan starts. |
| window-explorer-view-005 | refreshes-on-external-notification | Constructed with `refreshNotification = .foo`; `.foo` is posted | A new scan starts. |
| window-explorer-view-005b | refreshes-on-external-notification | Constructed with `refreshNotification = nil`; any notification is posted | No scan starts from this path. |
| window-explorer-view-006 | shows-accessibility-banner-when-permission-missing | Scan completes with `needsAccessibility == true` | Banner "Accessibility permission needed for window titles." with "Open Settings" is visible. |
| window-explorer-view-007 | requests-accessibility-permission-from-banner | Tap "Open Settings" | `SystemAccessibilityPermission.request()` is called. |
| window-explorer-view-008 | shows-loading-state | `isLoading == true` | `ProgressView` and "Scanning windows..." are shown; list content is hidden. |
| window-explorer-view-009 | shows-empty-state | Scan completes with `appGroups.isEmpty == true` | "No windows found" and the Accessibility hint are shown. |
| window-explorer-view-010 | groups-windows-by-app | Windows from apps "beta" and "Alpha" | Sections render in order "Alpha", "beta". |
| window-explorer-view-011 | shows-app-section-header | App "Xcode" with 3 windows, running with an icon | Header shows Xcode's running icon, "Xcode", and the count badge "3". |
| window-explorer-view-011b | shows-app-section-header | App with no matching `NSRunningApplication` icon | Header shows the fallback `app.fill` icon. |
| window-explorer-view-012 | provides-select-all-toggle-per-section | Section has 2 selectable windows, none selected; toggle select-all on | Both windows are added to `selectedWindowIDs`. |
| window-explorer-view-012b | provides-select-all-toggle-per-section | Section has 2 selectable windows, both selected; toggle select-all off | Both windows are removed from `selectedWindowIDs`. |
| window-explorer-view-013 | reflects-partial-selection-as-unchecked | Section has 2 selectable windows, 1 selected | Select-all toggle shows unchecked. |
| window-explorer-view-014 | disables-select-all-when-nothing-selectable | Section's only windows are all owned by a different context | Select-all toggle `isEnabled == false`. |
| window-explorer-view-015 | renders-window-row | Window with title `""`, frame 800x600 | Row shows "(untitled)" and "800x600". |
| window-explorer-view-016 | shows-context-badge-on-owned-window | `activeGroupID == B`; window owned by context `A` | Row shows a badge reading context `A`'s name in `A`'s color. |
| window-explorer-view-016b | shows-context-badge-on-owned-window | `activeGroupID == A`; window owned by context `A` | No context badge is shown. |
| window-explorer-view-017 | disables-unselectable-window-row | Window owned by a context other than `activeGroupID` | Row toggle `isEnabled == false`; title color is `theme.secondaryText`. |
| window-explorer-view-018 | determines-selectability-by-ownership | Window owned by no context | `isSelectable(window) == true`. |
| window-explorer-view-018b | determines-selectability-by-ownership | Window owned by context `C`; `activeGroupID == nil` | `isSelectable(window) == false`. |
| window-explorer-view-019 | filters-scanned-windows | One window 40x40 on-screen from a regular app; one window 200x200 from a background-only app | Only neither is excluded solely by size for the second, but the 40x40 window is excluded (fails `> 50` on both axes) and the background-app window is excluded (fails `activationPolicy == .regular`). |
| window-explorer-view-019b | filters-scanned-windows | Window's app name is in `appState.settings.hiddenApps` | Window is excluded from the scan result. |
| window-explorer-view-019c | filters-scanned-windows | Window's id is in `excludeWindowIDs` | Window is excluded from the scan result. |
| window-explorer-view-020 | queries-accessibility-per-process | Two windows share one pid; `AXUIElementCopyAttributeValue` fails for that pid | Both windows are skipped for AX enrichment; scan proceeds using their original titles. |
| window-explorer-view-021 | replaces-title-from-matched-accessibility-window | CG window frame `(0,0,100,100)`, empty title; AX window frame `(1,1,101,101)`, title "Notes" | Window title becomes "Notes" (each axis differs by < 3pt). |
| window-explorer-view-021b | replaces-title-from-matched-accessibility-window | CG window frame `(0,0,100,100)`; AX window frame `(4,0,100,100)`, title "Notes" | Window title is unchanged (x differs by exactly 4pt, not < 3pt). |
| window-explorer-view-022 | prunes-stale-selection-in-discovery-mode | `activeGroupID == nil`; `selectedWindowIDs` contains an id absent from the new scan | That id is removed from `selectedWindowIDs` after the scan completes. |
| window-explorer-view-023 | preserves-selection-in-assignment-mode | `activeGroupID != nil`; `selectedWindowIDs` contains an id absent from the new scan | That id remains in `selectedWindowIDs` after the scan completes. |

## Edge Cases

- **Null/empty input**: `excludeWindowIDs` defaults to an empty set (no
  windows excluded by id). `selectedWindowIDs` may start empty (no rows
  checked). A window whose `title` is the empty string MUST render
  "(untitled)" (`renders-window-row`). An `appGroups` result of `[]` MUST
  show the empty state (`shows-empty-state`).
- **Boundary values**: a window exactly 50 points wide or exactly 50 points
  tall MUST be excluded, because the filter uses strict `> 50` on both axes
  (`filters-scanned-windows`). An AX-to-CG frame difference of exactly 3
  points on any one of x, y, width, or height MUST NOT count as a match,
  because the tolerance check uses strict `< 3`
  (`replaces-title-from-matched-accessibility-window`).
- **Concurrent access**: `refreshAsync()` has no guard against being invoked
  again while a previous scan is still running — it can be triggered
  independently by `.onAppear`, app activation, an external
  `refreshNotification`, and the manual refresh button. Each invocation
  spawns its own `Task.detached` and unconditionally overwrites `appGroups`,
  `needsAccessibility`, and `isLoading` on the main actor when it finishes;
  the source neither cancels an in-flight scan nor coalesces overlapping
  ones, so the last scan to complete determines the final state (MUST, as
  implemented — no debounce or cancellation exists to change this).
- **Error states**: `AXUIElementCopyAttributeValue` failing for a given
  process is handled by silently `continue`-ing past that process (no error
  is surfaced to the caller or user). Whether the Accessibility banner
  appears at all depends on `axSucceeded`, which is set `true` if *any*
  process's AX query succeeded during the scan — so if some processes
  succeed and others fail, the banner is never shown even though the
  windows belonging to the failed processes keep their unenriched
  CoreGraphics titles (MUST, as implemented; this is a per-scan flag, not a
  per-app one).
- **Offline/disconnected state**: Not applicable — the view performs no
  network requests; window enumeration and Accessibility queries are local
  system calls only.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `selectedWindowIDs` | `Binding<Set<UInt32>>` | required | The set of currently selected window ids; read and written by row and section-header toggles. |
| `excludeWindowIDs` | `Set<UInt32>` | `[]` | Window ids to omit entirely from the scan result. |
| `activeGroupID` | `UUID?` | `nil` | When set, identifies the context whose windows are togglable instead of disabled, and whose selections a scan never prunes. |
| `refreshNotification` | `Notification.Name?` | `nil` | When set, a posted notification with this name triggers a new scan. |
| `appState` (environment) | `SystemWindowContextsModel` | required `@EnvironmentObject` | Supplies `listAllWindows()`, per-window context ownership (`context(forWindowID:)`), and `settings.hiddenApps`. |
| `theme` (environment) | theme palette (`\.theme`) | required environment value | Supplies every font and color role the view draws with. |

## Deep Linking

Not applicable: no URL-scheme or `NSUserActivity` handling appears anywhere
in `WindowExplorerView.swift`. The view is only ever instantiated directly
by its two host views.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `Windows` | Windows | Header title |
| `Refresh window list` | Refresh window list | `.help(_:)` tooltip on the refresh button |
| `Scanning windows...` | Scanning windows... | Loading-state caption |
| `No windows found` | No windows found | Empty-state title |
| `Make sure Accessibility permission is granted.` | Make sure Accessibility permission is granted. | Empty-state hint |
| `Accessibility permission needed for window titles.` | Accessibility permission needed for window titles. | Accessibility banner text |
| `Open Settings` | Open Settings | Accessibility banner action button |
| `(untitled)` | (untitled) | Fallback for a window with an empty title — not localized (see below) |

Every string above is a literal passed to `Text`, `Button`, or `.help(_:)`,
each of which takes a `LocalizedStringKey` — per this cookbook's SwiftUI
localization convention, a literal there is itself the localization key, so
these are localizable as written. Values built from runtime data — the app
name (`Text(app)`), a window's title (`Text(window.title...)`), a context's
name (`Text(ctx.name)`), the window count (`Text("\(windows.count)")`), and
the dimensions string (`Text("\(Int(...))x\(Int(...))")`) — are `String`
values or string interpolations, not localization keys, and correctly are
not translated as UI strings since they echo system or user data.

The `(untitled)` fallback is the exception among the literals:
`Text(window.title.isEmpty ? "(untitled)" : window.title)` (line 213) resolves
the ternary to a `String`, so `Text` takes its verbatim `String` initializer
and the literal is never looked up as a localization key. NEEDS REVIEW: Not
implemented in source. Behavior undefined. Whether `(untitled)` should be
localized (for example by branching to two `Text` views, or wrapping the
literal in `String(localized:)`) is unresolved; as built it always renders in
English.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no custom animated transition (movement, scaling, sliding, zooming, or pulsing) is implemented anywhere in this file; the only motion is `ProgressView`'s system-rendered indeterminate spinner, which this view does not implement or control. |
| Increase Contrast | Not applicable at this layer: every color is sourced from the shared theme palette (`theme.<role>`); contrast handling is a design-system-level concern this view does not decide, per `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages`. |
| Differentiate Without Color | Handled: the context badge pairs its color with the context's name as text, not color alone; the Accessibility banner pairs its warning tint with an exclamation-triangle icon and explanatory text; and every selection state is shown by the checkbox glyph itself, not by color. |

## Feature Flags

Not applicable: no flag-gated behavior (`FeatureFlag`, remote config, or
similar) appears anywhere in `WindowExplorerView.swift`.

## Analytics

Not applicable: no analytics or event-logging call appears anywhere in
`WindowExplorerView.swift`.

## Privacy

- **Data collected**: the view reads, but does not persist, information
  about currently running windows — application names, window titles
  (CoreGraphics and, where matched, Accessibility-enriched), pixel frames,
  process ids, and on-screen/layer state — via `appState.listAllWindows()`
  and direct `AXUIElementCopyAttributeValue`/`NSWorkspace` queries. It also
  reads `appState.settings.hiddenApps` to filter the scan.
- **Storage**: none owned by this view. Scan results live only in
  `@State` (`appGroups`, `isLoading`, `needsAccessibility`) for as long as
  the view exists; the selection set itself is owned by the caller through
  `@Binding var selectedWindowIDs`, so any persistence of a selection
  happens outside this file.
- **Transmission**: none. No networking import or call appears anywhere in
  this file; every API used (`CGWindowListCopyWindowInfo` via
  `listAllWindows()`, `AXUIElementCopyAttributeValue`, `NSWorkspace`) is a
  local, on-device system query.
- **Retention**: scan results are discarded and rebuilt on every
  `refreshAsync()` call and are not retained once the view is deallocated.

## Logging

Not applicable: no `Logger`/`os_log`/`print`-based logging call appears
anywhere in `WindowExplorerView.swift`.

## Platform Notes

- **SwiftUI**: this is the source form. File:
  `packages/apple/AgenticToolkit/macOS/SystemWindows/UI/WindowExplorerView.swift`.
  It reads `@EnvironmentObject private var appState: SystemWindowContextsModel`
  and a custom `@Environment(\.theme)` palette, builds its list with
  `List`/`Section`/`ForEach` and `.toggleStyle(.checkbox)` (a macOS-only
  `ToggleStyle`), and runs its scan on `Task.detached` with `MainActor.run`
  hops for both reading app state and writing the result back — none of
  which has a UIKit/iOS equivalent, since the file also imports `AppKit`
  directly for `NSRunningApplication`/`NSWorkspace` icon and bundle-id
  lookups and `ApplicationServices`-level `AXUIElement*` calls for title
  enrichment.
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

Decision: Prune stale ids from `selectedWindowIDs` after a scan only when
`activeGroupID == nil`; never prune when it is non-nil.
Rationale: in discovery mode the binding represents "windows currently
checked on screen," so an id for a window that vanished (closed, minimized,
now off-screen) is meaningless and MUST be dropped; in direct-assignment
mode the same binding instead represents persistent group membership, and a
member window that is merely not visible in *this* scan (e.g., a different
space, temporarily hidden) MUST NOT be silently unassigned from the group —
per the source comment directly above the prune.
Approved: pending

Decision: Fall back to the hard-coded `Color.blue` for a context badge when
`Color(hex: ctx.color)` returns `nil`, rather than a theme color.
Rationale: `Color(hex:)` returns `nil` only when the stored string is not a
valid 6-digit hex value, which should not occur for a color a context
stores through the app's own color picker; the fallback is a defensive
default for malformed data rather than an expected runtime path, which is
why it is a fixed system color rather than something drawn from the theme
palette.
Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [template-conformance](agenticdevelopercookbook://compliance/recipe-quality#template-conformance) | passed | recipe-quality |
| [behavioral-requirements](agenticdevelopercookbook://compliance/recipe-quality#behavioral-requirements) | passed | recipe-quality |
| [completeness](agenticdevelopercookbook://compliance/recipe-quality#completeness) | passed | recipe-quality |
| [cookbook-compliance](agenticdevelopercookbook://compliance/recipe-quality#cookbook-compliance) | passed | recipe-quality |
| [cross-recipe-consistency](agenticdevelopercookbook://compliance/recipe-quality#cross-recipe-consistency) | passed | recipe-quality |
| [source-fidelity](agenticdevelopercookbook://compliance/recipe-quality#source-fidelity) | passed | recipe-quality |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from `WindowExplorerView.swift`. |
