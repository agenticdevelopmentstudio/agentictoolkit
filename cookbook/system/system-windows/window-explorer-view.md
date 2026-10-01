---
id: 8aee173a-25e4-443e-a9ab-d629b58817e1
title: Window Explorer View
domain: agentictoolkit://cookbook/system/system-windows/window-explorer-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A reusable view listing running windows by app with selection checkboxes
  and Accessibility-permission handling.
platforms:
- swift
- macos
tags:
- window-explorer
- system-windows
- window-selection
depends-on: []
related:
- agentictoolkit://cookbook/ui/controls/badge
references: []
approved-by: ''
approved-date: ''
---

# Window Explorer View

## Overview

The window explorer is a reusable content view that lists
every running window, grouped into a section per owning application, each
with a selection checkbox. It is embedded by two callers that give it
different meanings: a discovery surface, where any visible window can be
checked, and a work-group direct-assignment surface, where windows already
belonging to the group being edited are toggled and windows owned by other
groups are shown but disabled. The view owns its own asynchronous window scan,
grouping, and Accessibility-based title enrichment; the caller only owns the
resulting set of selected window ids via a binding.

## Behavioral Requirements

- **header-bar**: The view MUST show a header row containing, in
  order, a magnifying-glass icon, the label "Windows", a flexible spacer, and
  a refresh button.
- **refresh-button-loading-state**: The refresh button MUST be disabled
  whenever a window scan is in progress (`isLoading == true`).
- **initial-refresh**: The view MUST start a window scan the first time
  it appears.
- **activation-refresh-when-accessibility-missing**: The view MUST
  start a new window scan whenever the app becomes active again, but only
  if the most recent scan left `needsAccessibility == true`.
- **external-notification-refresh**: When constructed with a configured
  `refreshNotification` name, the view MUST start a window scan whenever a
  notification with that name is posted; when no name is configured,
  this path MUST have no effect.
- **accessibility-banner-visibility**: The view MUST
  display a banner reading "Accessibility permission needed for window
  titles." with an "Open Settings" action whenever the most recent scan
  found running windows but no process's Accessibility window-list
  query succeeded (`needsAccessibility == true`, set from `axSucceeded ==
  false`). This depends on Accessibility *query* success per process, not on
  whether any window's title was actually matched and replaced — a query can
  succeed for a process without any of its windows matching a system-reported
  window closely enough to replace its title.
- **accessibility-banner-action**: Activating the banner's
  "Open Settings" action MUST request Accessibility permission.
- **loading-state**: While a scan is in progress, the view MUST show an
  indeterminate progress indicator and the text "Scanning windows..." in
  place of the window list.
- **empty-state**: When a completed scan produces no application
  groups, the view MUST show a "No windows found" message together with the
  hint "Make sure Accessibility permission is granted."
- **app-grouping**: Once loaded, the view MUST present windows as
  one section per owning application, with sections ordered
  case-insensitively ascending by application name.
- **app-section-header**: Each application section header MUST show
  that application's running icon (or a fallback generic application icon
  when no running icon is found), the application name, and a count of its
  windows in that section.
- **section-select-all-toggle**: Each application section
  header MUST include a toggle that, when turned on, adds every selectable
  window in that section to `selectedWindowIDs`, and, when turned off,
  removes every selectable window in that section from `selectedWindowIDs`.
- **select-all-toggle-partial-selection-state**: A section's select-all toggle
  MUST show the unchecked state unless the section has at least one
  selectable window and every selectable window in it is currently selected.
- **select-all-toggle-availability**: A section's select-all
  toggle MUST be disabled when that section has no selectable windows.
- **window-row**: Each window row MUST show a toggle bound to that
  window's membership in `selectedWindowIDs`, the window's title (or
  "(untitled)" when the title is empty) limited to one line with middle
  truncation, and the window's dimensions formatted as
  `"<width>x<height>"` using integer point values.
- **window-context-badge**: A window row MUST show a badge
  naming its owning context, colored from that context's stored color,
  whenever the window already belongs to a context and either no
  `activeGroupID` is set or that context differs from `activeGroupID`.
- **window-row-selectability-state**: A window row's toggle MUST be
  disabled, and its title MUST be drawn in the secondary text color instead
  of the primary text color, whenever the window is not selectable.
- **window-selectability**: A window MUST be selectable
  when it belongs to no context, or when it belongs to the context
  identified by `activeGroupID`; it MUST NOT be selectable when it belongs
  to any other context.
- **scan-window-filter**: A window scan MUST include only windows that
  belong to a regular, user-visible running application, are wider than 50
  points, are taller than 50 points, are currently on-screen, whose owning
  application name is not in `appState.settings.hiddenApps`, and whose id is
  not in the view's `excludeWindowIDs`.
- **per-process-accessibility-query**: A window scan MUST query the
  Accessibility window list of every distinct process id among the
  filtered windows, skipping any process for which that query does not
  succeed.
- **accessibility-title-match**: A window scan MUST
  replace a window's title with an Accessibility window's title when that
  Accessibility window belongs to the same process and its position and size
  each differ from the system-reported window's frame by less than 3 points
  on x, y, width, and height, and that Accessibility title is non-empty;
  otherwise the window's original title MUST be kept unchanged.
- **discovery-mode-stale-selection-pruning**: When `activeGroupID` is nil,
  completing a scan MUST remove from `selectedWindowIDs` any id that is not
  present among the windows the scan produced.
- **assignment-mode-selection-preservation**: When `activeGroupID` is
  non-nil, completing a scan MUST NOT remove any id from
  `selectedWindowIDs`, even if the window it identifies is not present among
  the windows the scan produced.

## Appearance

- **Corner radius**: Not applicable to the view's own chrome — no rounded
  rectangle is drawn directly; the window-count badge and the context badge
  are drawn as fully rounded capsule shapes, not with a corner-radius value.
- **Padding**: Header row: 16pt horizontal, 8pt vertical.
  Accessibility banner: the same 16pt horizontal / 8pt vertical. Section
  header content: 8pt spacing between icon, name, and count badge; the
  count badge additionally has 4pt horizontal padding. Window row content:
  8pt spacing between the title/subtitle column and the trailing spacer;
  the title/subtitle column itself has 0pt spacing; the dimensions/badge
  row has 4pt spacing; the context badge has 4pt horizontal padding.
- **Font**: All fonts resolve through the theme's font-role mapping,
  wrapping the theme's typography per text role. Header icon and "Windows"
  label: `heading`. "Scanning windows..." and the "Open Settings" banner
  button: `caption`. Empty-state icon: `title`. Window title: `body`.
  Window dimensions: `code`. App name and both badges (count, context):
  `caption`, bolded (`bold`).
- **Background**: View background is not set explicitly (inherits the
  container's). Accessibility banner background: the `warning` theme color
  at 10% opacity. Count badge background: the `primaryText` theme color at
  6% opacity, inside a capsule shape. Context badge background: the
  context's stored color (or a fallback blue when it fails to parse) at 12%
  opacity, inside a capsule shape. The window list itself uses an inset
  style with alternating row backgrounds, which lets the platform draw
  those alternating backgrounds rather than any color this view supplies.
- **Foreground/Text**: The `secondaryText` theme color is used for the
  header icon, a disabled/unselectable row's title, "Scanning windows...",
  "No windows found", and the fallback generic section icon. The
  `tertiaryText` theme color is used for the empty-state icon, "Make sure
  Accessibility permission is granted.", window dimensions, and the
  count-badge number. The `primaryText` theme color is used for a
  selectable row's title. The `warning` theme color is used for the
  banner's exclamation-triangle icon. Context badge text/icon color is the
  context's stored color, or a hard-coded blue — not a theme color — when
  the stored hex fails to parse.
- **Border**: Not applicable — no border is drawn anywhere in the source.
- **Shadow**: Not applicable — no shadow is drawn anywhere in the source.
- **Min/Max size**: The loading and empty states each fill the available
  width with a minimum height of 200 points; no maximum size is set
  anywhere, and the populated list has no minimum-height constraint of its
  own.

## States

| State | Appearance change |
|-------|------------------|
| Default | Populated: header bar, divider, and a sectioned list of app groups and window rows. |
| Pressed | Not applicable — the view applies no custom pressed styling; toggle and button press feedback is the system's standard checkbox and button chrome. |
| Disabled | Refresh button disabled while `isLoading`; a section's select-all toggle disabled when it has no selectable windows; a row's toggle disabled, and its title colored with the secondary text color, when its window is not selectable. |
| Focused | Not applicable — no custom focus-ring styling appears in source; standard keyboard focus rendering on each toggle and button applies unmodified. |
| Loading | List content replaced by a centered progress indicator (scaled to 80% size) and the caption "Scanning windows...", in a frame with a minimum height of 200 points. |
| Empty | After a completed scan with no application groups: a centered generic-window icon, "No windows found", and the hint "Make sure Accessibility permission is granted.", in a frame with a minimum height of 200 points. |
| Accessibility banner shown | `needsAccessibility == true`: a warning-tinted banner is shown above whichever of Default, Loading, or Empty is otherwise active. |
| Section fully selected | Select-all toggle for that section shows checked. |
| Section partially or not selected | Select-all toggle for that section shows unchecked (covers both "some selected" and "none selected"). |
| Row's window owned by the active group | Toggle enabled, no context badge shown (the badge is suppressed when the owning context equals `activeGroupID`). |
| Row's window owned by a different context | Toggle disabled, title dimmed to the secondary text color, and a colored context-name badge is shown. |

## Accessibility

- Role/traits: standard platform controls only — a checkbox-styled toggle
  for every selection control (section select-all and per-window rows), a
  borderless button for refresh and a bordered button for "Open Settings",
  and a list with sections for the grouped content. No custom accessibility
  role or trait values are set anywhere in the file.
- Label requirements: each toggle's accessible label is its visible label
  content — the section header's icon/name/count row for the select-all
  toggle, and the title/dimensions/badge column for a row toggle — since
  no explicit accessibility label is set on either. The "Open Settings"
  button carries its own visible text as its label — see
  **refresh-button-label** for the refresh button.
- **refresh-button-label**: The refresh button is icon-only (a refresh-arrow icon) and sets no explicit accessibility label; the screen reader gets only the icon's implicit description plus a "Refresh window list" help tooltip, which is exposed as a tooltip and accessibility hint, not as the label.
- Announce state changes: the loading, empty, and populated states are
  distinct view trees that the framework swaps directly (no text or state
  is kept visible across the transition); no accessibility-trait update,
  announcement posting, or focus-move call accompanies any of these swaps,
  so a screen-reader user gets no explicit announcement and no
  accessibility-focus change when a scan finishes (loading to
  list/empty).
- Minimum control size: this is a pointer-driven surface with no mandated
  minimum touch-target size (unlike a touch platform); the view uses
  standard checkbox-style control sizing throughout — a small control size
  on the banner's "Open Settings" button, and the system default size
  everywhere else — consistent with this being a pointer/keyboard surface
  rather than a value this view decides on its own.
- Keyboard/focus: every interactive element (toggle, button) is a
  standard, keyboard-focusable platform control; no custom key
  handling or focus trapping is added in this file.
- Color/contrast: all text and background colors resolve through the shared
  theme palette, except the context badge's stored-color-or-fallback-blue
  color, which is not a palette color; contrast is a design-system-level
  concern outside this view's own decisions, per
  `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages`.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| window-explorer-view-001 | header-bar | Render the view | Header shows magnifying-glass icon, "Windows", spacer, refresh button, in that order. |
| window-explorer-view-002 | refresh-button-loading-state | `isLoading == true` | Refresh button `isEnabled == false`. |
| window-explorer-view-003 | initial-refresh | View appears for the first time | A window scan starts without user action. |
| window-explorer-view-004 | activation-refresh-when-accessibility-missing | `needsAccessibility == true`; the app becomes active again | A new scan starts. |
| window-explorer-view-004b | activation-refresh-when-accessibility-missing | `needsAccessibility == false`; the app becomes active again | No new scan starts. |
| window-explorer-view-005 | external-notification-refresh | Constructed with `refreshNotification = .foo`; `.foo` is posted | A new scan starts. |
| window-explorer-view-005b | external-notification-refresh | Constructed with no `refreshNotification`; any notification is posted | No scan starts from this path. |
| window-explorer-view-006 | accessibility-banner-visibility | Scan completes with `needsAccessibility == true` | Banner "Accessibility permission needed for window titles." with "Open Settings" is visible. |
| window-explorer-view-007 | accessibility-banner-action | Click "Open Settings" | Accessibility permission is requested. |
| window-explorer-view-008 | loading-state | `isLoading == true` | A progress indicator and "Scanning windows..." are shown; list content is hidden. |
| window-explorer-view-009 | empty-state | Scan completes with `appGroups.isEmpty == true` | "No windows found" and the Accessibility hint are shown. |
| window-explorer-view-010 | app-grouping | Windows from apps "beta" and "Alpha" | Sections render in order "Alpha", "beta". |
| window-explorer-view-011 | app-section-header | App "Xcode" with 3 windows, running with an icon | Header shows Xcode's running icon, "Xcode", and the count badge "3". |
| window-explorer-view-011b | app-section-header | App with no matching running-application icon | Header shows the fallback generic application icon. |
| window-explorer-view-012 | section-select-all-toggle | Section has 2 selectable windows, none selected; toggle select-all on | Both windows are added to `selectedWindowIDs`. |
| window-explorer-view-012b | section-select-all-toggle | Section has 2 selectable windows, both selected; toggle select-all off | Both windows are removed from `selectedWindowIDs`. |
| window-explorer-view-013 | select-all-toggle-partial-selection-state | Section has 2 selectable windows, 1 selected | Select-all toggle shows unchecked. |
| window-explorer-view-014 | select-all-toggle-availability | Section's only windows are all owned by a different context | Select-all toggle `isEnabled == false`. |
| window-explorer-view-015 | window-row | Window with title `""`, frame 800x600 | Row shows "(untitled)" and "800x600". |
| window-explorer-view-016 | window-context-badge | `activeGroupID == B`; window owned by context `A` | Row shows a badge reading context `A`'s name in `A`'s color. |
| window-explorer-view-016b | window-context-badge | `activeGroupID == A`; window owned by context `A` | No context badge is shown. |
| window-explorer-view-017 | window-row-selectability-state | Window owned by a context other than `activeGroupID` | Row toggle `isEnabled == false`; title color is the secondary text color. |
| window-explorer-view-018 | window-selectability | Window owned by no context | The window is selectable. |
| window-explorer-view-018b | window-selectability | Window owned by context `C`; `activeGroupID == nil` | The window is not selectable. |
| window-explorer-view-019 | scan-window-filter | One window 40x40 on-screen from a regular app; one window 200x200 from a background-only app | Both windows are excluded: the 40x40 window by size, the background-app window by its activation policy. |
| window-explorer-view-019b | scan-window-filter | Window's app name is in `appState.settings.hiddenApps` | Window is excluded from the scan result. |
| window-explorer-view-019c | scan-window-filter | Window's id is in `excludeWindowIDs` | Window is excluded from the scan result. |
| window-explorer-view-019d | scan-window-filter | Window exactly 50 points wide (and taller than 50 points), on-screen, from a regular app | Window is excluded (`> 50` is a strict boundary; exactly 50 does not qualify). |
| window-explorer-view-020 | per-process-accessibility-query | Two windows share one pid; the Accessibility window-list query fails for that pid | Both windows are skipped for Accessibility enrichment; scan proceeds using their original titles. |
| window-explorer-view-021 | accessibility-title-match | System-reported window frame `(0,0,100,100)`, empty title; Accessibility window frame `(1,1,101,101)`, title "Notes" | Window title becomes "Notes" (each axis differs by < 3pt). |
| window-explorer-view-021b | accessibility-title-match | System-reported window frame `(0,0,100,100)`; Accessibility window frame `(4,0,100,100)`, title "Notes" | Window title is unchanged (x differs by exactly 4pt, not < 3pt). |
| window-explorer-view-021c | accessibility-title-match | System-reported window frame `(0,0,100,100)`; Accessibility window frame `(3,0,100,100)`, title "Notes" | Window title is unchanged (x differs by exactly 3pt, which does not satisfy strict `< 3`). |
| window-explorer-view-022 | discovery-mode-stale-selection-pruning | `activeGroupID == nil`; `selectedWindowIDs` contains an id absent from the new scan | That id is removed from `selectedWindowIDs` after the scan completes. |
| window-explorer-view-023 | assignment-mode-selection-preservation | `activeGroupID != nil`; `selectedWindowIDs` contains an id absent from the new scan | That id remains in `selectedWindowIDs` after the scan completes. |

## Edge Cases

- **Null/empty input**: `excludeWindowIDs` defaults to an empty set (no
  windows excluded by id). `selectedWindowIDs` may start empty (no rows
  checked). A window whose `title` is the empty string MUST render
  "(untitled)" (`window-row`). An `appGroups` result of `[]` MUST
  show the empty state (`empty-state`).
- **Boundary values**: a window exactly 50 points wide or exactly 50 points
  tall MUST be excluded, because the filter uses strict `> 50` on both axes
  (`scan-window-filter`). An Accessibility-to-system frame difference of
  exactly 3 points on any one of x, y, width, or height MUST NOT count as a
  match, because the tolerance check uses strict `< 3`
  (`accessibility-title-match`).
- **Concurrent access**: a window scan has no guard against being invoked
  again while a previous scan is still running — it can be triggered
  independently by the view appearing, app activation, an external refresh
  notification, and the manual refresh button. Each invocation spawns its
  own independent background task and unconditionally overwrites
  `appGroups`, `needsAccessibility`, and `isLoading` on the main
  coordination context when it finishes; the source neither cancels an
  in-flight scan nor coalesces overlapping ones, so the last scan to
  complete determines the final state. No debounce or cancellation exists
  to change this — this is observed behavior of the current implementation,
  not a documented requirement, and overlapping scans racing to determine
  the final state is a likely source of surprising results rather than an
  intended contract.
- **Error states**: an Accessibility window-list query failing for a given
  process is handled by silently skipping that process (no error
  is surfaced to the caller or user). Whether the Accessibility banner
  appears at all depends on `axSucceeded`, which is set `true` if *any*
  process's Accessibility query succeeded during the scan — so if some
  processes succeed and others fail, the banner is never shown even though
  the windows belonging to the failed processes keep their unenriched,
  system-reported titles. This is a per-scan flag, not a per-app one, and is
  the current implementation's behavior rather than a designed requirement:
  a user with some processes failing Accessibility queries sees no
  indication that any titles are unenriched.
- **Offline/disconnected state**: Not applicable — the view performs no
  network requests; window enumeration and Accessibility queries are local
  system calls only.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `selectedWindowIDs` | two-way binding to a set of ids | required | The set of currently selected window ids; read and written by row and section-header toggles. |
| `excludeWindowIDs` | set of ids | `[]` | Window ids to omit entirely from the scan result. |
| `activeGroupID` | optional identifier | `nil` | When set, identifies the context whose windows are togglable instead of disabled, and whose selections a scan never prunes. |
| `refreshNotification` | optional notification name | `nil` | When set, a posted notification with this name triggers a new scan. |
| Contexts model (environment) | shared environment value | required | Supplies the full window list, per-window context ownership, and hidden-app settings. |
| Theme (environment) | theme palette | required environment value | Supplies every font and color role the view draws with. |

## Deep Linking

Not applicable: no URL-scheme or system-activity handling appears anywhere
in the source. The view is only ever instantiated directly
by its two host views.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `Windows` | Windows | Header title |
| `Refresh window list` | Refresh window list | Tooltip on the refresh button |
| `Scanning windows...` | Scanning windows... | Loading-state caption |
| `No windows found` | No windows found | Empty-state title |
| `Make sure Accessibility permission is granted.` | Make sure Accessibility permission is granted. | Empty-state hint |
| `Accessibility permission needed for window titles.` | Accessibility permission needed for window titles. | Accessibility banner text |
| `Open Settings` | Open Settings | Accessibility banner action button |
| `(untitled)` | (untitled) | Fallback for a window with an empty title — not localized (see below) |

Every string above is a literal passed to a text, button, or tooltip
control, each of which takes a localization key — per this cookbook's
localization convention, a literal there is itself the localization key,
so these are localizable as written. Values built from runtime data — the
app name, a window's title, a context's name, the window count, and the
dimensions string — are plain string values or string interpolations, not
localization keys, and correctly are not translated as UI strings since
they echo system or user data.

The `(untitled)` fallback is the exception among the literals: when the
title is empty, the view substitutes the literal string `"(untitled)"`
directly rather than through a localization key — as built, this behavior
is defined: the fallback always renders in English regardless of the
user's locale, and the source contains no branch that would localize it
instead.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no custom animated transition (movement, scaling, sliding, zooming, or pulsing) is implemented anywhere in this file; the only motion is the system-rendered indeterminate progress spinner, which this view does not implement or control. |
| Increase Contrast | Not applicable at this layer for most colors: every color other than the context badge's fallback blue is sourced from the shared theme palette; contrast handling for those is a design-system-level concern this view does not decide, per `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages`. The context badge's stored-color-or-fallback-blue (see **window-context-badge**) is the one exception: it is a fixed system color outside the theme, so Increase Contrast has no effect on it. |
| Differentiate Without Color | Handled: the context badge pairs its color with the context's name as text, not color alone; the Accessibility banner pairs its warning tint with an exclamation-triangle icon and explanatory text; and every selection state is shown by the checkbox glyph itself, not by color. |

## Feature Flags

Not applicable: no flag-gated behavior (feature flag, remote config, or
similar) appears anywhere in the source.

## Analytics

Not applicable: no analytics or event-logging call appears anywhere in
the source.

## Privacy

- **Data collected**: the view reads, but does not persist, information
  about currently running windows — application names, window titles
  (system-reported and, where matched, Accessibility-enriched), point
  frames, process ids, and on-screen/layer state — via the contexts
  model's window list and direct Accessibility and running-application
  queries. It also reads `appState.settings.hiddenApps` to filter the scan.
- **Storage**: none owned by this view. Scan results live only in
  local view state (`appGroups`, `isLoading`, `needsAccessibility`) for as
  long as the view exists; the selection set itself is owned by the caller
  through the `selectedWindowIDs` binding, so any persistence of a
  selection happens outside this component.
- **Transmission**: none. No networking import or call appears anywhere in
  this file; every API used (window enumeration, Accessibility queries,
  running-application queries) is a local, on-device system query.
- **Retention**: scan results are discarded and rebuilt on every
  window-scan call and are not retained once the view is deallocated.

## Logging

Not applicable: no logging call of any kind appears
anywhere in the source.

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
  running-application enumeration API to provide these. The activation-refresh
  path listens for `NSApplication.didBecomeActiveNotification`; the
  external-refresh path is driven by a custom `OptionalNotificationModifier`.
  The Accessibility window-list query is `AXUIElementCopyAttributeValue` with
  `kAXWindowsAttribute`, and requesting permission calls
  `SystemAccessibilityPermission.request()`. SF Symbols used are `app.fill`
  (fallback app icon), `macwindow.on.rectangle` (empty state), and
  `arrow.clockwise` (refresh), and the list uses
  `.listStyle(.inset(alternatesRowBackgrounds: true))` for its alternating
  row backgrounds.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemWindows/UI/WindowExplorerView.swift` |

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

**Decision** (SwiftUI): Fall back to the hard-coded `Color.blue` for a context badge when
`Color(hex: ctx.color)` returns `nil`, rather than a theme color.
**Rationale**: `Color(hex:)` returns `nil` only when the stored string is not a
valid 6-digit hex value, which should not occur for a color a context
stores through the app's own color picker; the fallback is a defensive
default for malformed data rather than an expected runtime path, which is
why it is a fixed system color rather than something drawn from the theme
palette.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | partial | Internationalization |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | partial | Internationalization |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy & Data |

`screen-reader-support` is partial because the refresh button has no explicit
`.accessibilityLabel` (see **refresh-button-label**);
`keyboard-navigable` passes because every interactive element is a standard,
keyboard-focusable `Toggle`/`Button`. `contrast-ratio` and
`no-hardcoded-strings`/`string-externalization` are partial for the same two
source-documented exceptions: the context badge's `Color(hex: ctx.color) ??
.blue` fallback sits outside the theme palette, and the `(untitled)` fallback
is routed through `Text`'s verbatim `String` initializer instead of a
localization key. `dynamic-type-support` is partial because the source
resolves every font through `theme.font(_:)` and this file cannot tell
whether that palette scales with the system text-size setting.
`data-minimization` passes because the Privacy section shows the view reads
only currently-running window data needed for display, filtered by
`appState.settings.hiddenApps`, and persists nothing.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to system/system-windows/. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed requirements to subject-only kebab-case; reformatted Design Decisions to the bolded form; linked `badge` under `related`; reworded the AX-banner requirement, boundary/garbled test vectors, and edge cases to match source behavior instead of implying a MUST; rebuilt Compliance against the real catalog; fixed the accessibility, localization, and privacy prose contradictions. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from `WindowExplorerView.swift`. |
