<!-- leaf: implement-window/explorer-view · source: window-explorer-view.md -->

**Rules** (cite as `implement-window/explorer-view#<slug>`):

- `header-bar` MUST
- `refresh-button-loading-state` MUST
- `initial-refresh` MUST
- `activation-refresh-when-accessibility-missing` MUST
- `external-notification-refresh` MUST
- `accessibility-banner-visibility` MUST
- `accessibility-banner-action` MUST
- `loading-state` MUST
- `empty-state` MUST
- `app-grouping` MUST
- `app-section-header` MUST
- `section-select-all-toggle` MUST
- `select-all-toggle-partial-selection-state` MUST
- `select-all-toggle-availability` MUST
- `window-row` MUST
- `window-context-badge` MUST
- `window-row-selectability-state` MUST
- `window-selectability` MUST
- `scan-window-filter` MUST
- `per-process-accessibility-query` MUST
- `accessibility-title-match` MUST
- `discovery-mode-stale-selection-pruning` MUST
- `assignment-mode-selection-preservation` MUST

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

- **header-bar**: The view MUST show a header row containing, in
  order, a magnifying-glass icon, the label "Windows", a flexible spacer, and
  a refresh button.
- **refresh-button-loading-state**: The refresh button MUST be disabled
  whenever a window scan is in progress (`isLoading == true`).
- **initial-refresh**: The view MUST start a window scan the first time
  it appears (`.onAppear { refreshAsync() }`).
- **activation-refresh-when-accessibility-missing**: The view MUST
  start a new window scan whenever the app receives
  `NSApplication.didBecomeActiveNotification`, but only if the most recent
  scan left `needsAccessibility == true`.
- **external-notification-refresh**: When constructed with a non-nil
  `refreshNotification` name, the view MUST start a window scan whenever a
  notification with that name is posted; when `refreshNotification` is nil,
  this path MUST have no effect (`OptionalNotificationModifier`).
- **accessibility-banner-visibility**: The view MUST
  display a banner reading "Accessibility permission needed for window
  titles." with an "Open Settings" action whenever the most recent scan
  found running windows but no process's Accessibility (AX) window-list
  query succeeded (`needsAccessibility == true`, set from `axSucceeded ==
  false`). This depends on AX *query* success per process, not on whether
  any window's title was actually matched and replaced — a query can
  succeed for a process without any of its windows matching a CoreGraphics
  window closely enough to replace its title.
- **accessibility-banner-action**: Activating the banner's
  "Open Settings" action MUST invoke `SystemAccessibilityPermission.request()`.
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
  that application's running icon (or a fallback `app.fill` icon when no
  running icon is found), the application name, and a count of its windows
  in that section.
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
  to any other context (`isSelectable(_:)`).
- **scan-window-filter**: A window scan MUST include only windows that
  belong to a regular running application (`activationPolicy == .regular`),
  are wider than 50 points, are taller than 50 points, are currently
  on-screen, whose owning application name is not in
  `appState.settings.hiddenApps`, and whose id is not in the view's
  `excludeWindowIDs`.
- **per-process-accessibility-query**: A window scan MUST query the
  Accessibility (AX) window list of every distinct process id among the
  filtered windows (`AXUIElementCopyAttributeValue` with
  `kAXWindowsAttribute`), skipping any process for which that query does not
  succeed.
- **accessibility-title-match**: A window scan MUST
  replace a window's title with an Accessibility window's title when that
  Accessibility window belongs to the same process and its position and size
  each differ from the CoreGraphics window's frame by less than 3 points on
  x, y, width, and height, and that Accessibility title is non-empty;
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

