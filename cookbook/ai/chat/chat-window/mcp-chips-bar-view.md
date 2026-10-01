---
id: bea6525c-171f-4547-bbb3-7c709543552e
title: MCP Chips Bar View
domain: agentictoolkit://cookbook/ai/chat/chat-window/mcp-chips-bar-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Chat-window header bar for picking which configured MCP servers are active;
  built but not yet wired to a chat consumer.
platforms:
- swift
- macos
tags:
- mcp
- chat
- toggle
- popover
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# MCP Chips Bar View

## Overview

The MCP chips bar is a small header bar for an AI chat window: a server-rack
icon and a button reporting how many of the configured MCP servers are
currently active. Tapping the button opens a popover listing every available
server as a checkbox toggle, letting the user turn individual servers on or
off for the chat. The bar is not wired to any chat consumer yet — a separate
tool-loop component owns that integration, and the bar is retained for a
later phase when a consumer surfaces the registry selection UI again — so, as
shipped, it computes and reports active-server state faithfully but nothing
downstream currently reads that state (see Design Decisions).

## Behavioral Requirements

- **applies-theme-consistently**: The bar's content and the popover's content MUST both receive the app's active theme values (see Platform Notes for the mechanism).
- **fills-parent-bounds**: The bar MUST stretch to exactly fill the bounds of its containing element on every edge.
- **shares-one-view-model-between-bar-and-picker**: The bar's toggle button
  and the popover's server rows MUST reflect the same active-server state,
  backed by a single view model constructed at initialization from the given
  `registry` and `activeServerIds` binding — so toggling a row in the popover
  is immediately reflected in the bar's button label.
- **snapshots-active-ids-at-init**: The view model's `activeServerIds` MUST
  be set to the current value of the caller's `activeServerIds` binding at
  construction time, read exactly once.
- **subscribes-to-registry-clients**: The view model MUST subscribe to the
  registry's `clients` updates for its lifetime, so every update to
  `clients` is picked up without the caller re-observing manually (see
  Platform Notes for how the subscription is retained).
- **sorts-available-servers-by-name**: On every `clients` update,
  `availableServerIds` MUST be set to the clients' keys sorted by each
  client's `name`, ascending, using a locale-aware, case-insensitive
  comparison.
- **defaults-missing-name-to-empty-string-for-sort**: When comparing two ids
  for the sort in `sorts-available-servers-by-name`, a missing name lookup
  (`clients[id]?.name`) MUST be treated as `""`.
- **rebuilds-server-names-on-update**: On every `clients` update,
  `serverNames` MUST be replaced with a fresh mapping from each client id to
  that client's current `name`.
- **reports-active-membership**: `isActive(_:)` MUST return whether the
  given id is a member of `activeServerIds`.
- **toggles-membership-on-call**: `toggle(_:)` MUST remove the given id from
  `activeServerIds` if present, and MUST insert it if absent.
- **propagates-toggle-to-binding**: `toggle(_:)` MUST write the resulting
  `activeServerIds` set to the caller-supplied binding's value after every
  call.
- **renders-server-rack-icon**: The bar MUST display a server-rack icon,
  tinted with `theme.secondaryText`.
- **renders-toggle-button**: The bar MUST display one button whose label
  contains the computed button text followed by a chevron-down disclosure
  icon, both tinted with `theme.accent` and set in `theme.font(.caption)`.
- **computes-no-servers-label**: The button's text MUST read
  `"No MCP servers"` when `availableServerIds` is empty.
- **computes-none-active-label**: When `availableServerIds` is non-empty and
  the intersection of `activeServerIds` with `Set(availableServerIds)` is
  empty, the button's text MUST read `"MCP: none"`.
- **computes-count-active-label**: When that intersection is non-empty, the
  button's text MUST read `"MCP: {active} of {total}"`, where `active` is
  the intersection's count and `total` is `availableServerIds.count`.
- **uses-borderless-button-style**: The toggle button MUST use a borderless
  button style (see Platform Notes for the exact style name).
- **toggles-picker-on-tap**: Tapping the button MUST toggle the
  `showingPicker` state.
- **presents-popover-below-button**: The bar MUST present a popover, bound
  to `showingPicker`, anchored below the button (see Platform Notes for the
  exact anchoring mechanism).
- **reapplies-theme-inside-popover**: The popover's content MUST re-apply
  the app's active theme to the server picker's content, independently of
  the bar's own application (see Platform Notes for the mechanism and why a
  second application is needed).
- **applies-bar-padding**: The bar's root layout container MUST use 8pt
  inter-item spacing and MUST be padded 12pt horizontally and 6pt
  vertically.
- **trails-with-spacer**: The bar's root layout container MUST end with a
  flexible spacer after the toggle button.
- **shows-picker-heading**: The popover MUST display the text
  `"Active MCP Servers"` in `theme.font(.heading)`.
- **shows-empty-state-message**: When `availableServerIds` is empty, the
  popover MUST display the text `"No connected servers.\nAdd one in
  Settings → MCP Servers."`, tinted with `theme.secondaryText` and set in
  `theme.font(.caption)`, in place of any server row.
- **lists-one-toggle-row-per-server**: When `availableServerIds` is
  non-empty, the popover MUST render exactly one toggle row per id, in
  `availableServerIds`'s order, and MUST NOT render the empty-state message.
- **row-label-falls-back-to-unknown**: Each row's label MUST read
  `serverNames[id]` when present, and `"Unknown"` otherwise.
- **row-toggle-reflects-active-state**: Each row's toggle MUST be bound so
  reading it returns `viewModel.isActive(id)`.
- **row-toggle-calls-view-model-toggle**: Setting a row's toggle (to
  either value) MUST call `viewModel.toggle(id)`.
- **uses-checkbox-toggle-style**: Every row toggle MUST use a checkbox
  toggle style (see Platform Notes for the exact style name).
- **applies-picker-padding-and-min-width**: The popover's root layout
  container MUST use 8pt spacing, MUST be padded 14pt on all sides, and MUST
  have a minimum width of 220pt.

## Appearance

- **Corner radius**: Not applicable — no corner radius or custom layer is
  set anywhere in source; any rounding on the popover's chrome comes from
  the platform's own default popover appearance.
- **Padding**: Bar row: 12pt horizontal / 6pt vertical, 8pt spacing
  between the icon, the button, and the trailing spacer. Button's inner
  row (label + chevron): 4pt spacing, no explicit padding. Picker
  column: 14pt on all sides, 8pt spacing between rows.
- **Font**: `theme.font(.caption)` for the bar button's label/chevron and
  for the picker's empty-state message; `theme.font(.heading)` for the
  picker's "Active MCP Servers" heading. The unmodified default styles for
  these roles are 11pt regular (caption) and 15pt semibold (heading), each
  additionally scaled by the active theme's size-scale factor (see Platform
  Notes for where these defaults are defined). Each server row's label and
  the checkbox's own title set no explicit font, so they render in the
  platform's default body text style.
- **Background**: Not set explicitly by this file; both roots (the bar
  and, separately, the server picker inside the popover) sit on whatever the
  shared theming mechanism paints — the active theme's window background —
  since each call site accepts that mechanism's default of painting a
  background (see Platform Notes).
- **Foreground/Text**: `theme.secondaryText` on the rack icon and the
  picker's empty-state message; `theme.accent` on the button's label and
  chevron; the heading and each row's label use the primary text color the
  shared theming mechanism applies at each host root, not a color this file
  sets itself.
- **Border**: Not applicable — no border is drawn or configured anywhere in
  source.
- **Shadow**: Not applicable — no shadow is drawn or configured in source;
  the popover's window shadow is the platform's own system chrome.
- **Min/Max size**: The bar itself has no fixed frame — it sizes to its
  content plus padding, and is stretched to fill whatever bounds its
  containing element gives it (see **fills-parent-bounds**). The picker has a
  minimum width of 220pt and no maximum; the popover otherwise sizes itself
  to that content's fitting size.

## States

| State | Appearance change |
|-------|------------------|
| Default | Rack icon plus button showing the current computed label; no popover shown. |
| No servers configured | Button text reads "No MCP servers"; if opened, the popover shows the empty-state message instead of any row. |
| Servers configured, none active | Button text reads "MCP: none". |
| Servers configured, some or all active | Button text reads "MCP: {active} of {total}". |
| Picker open | `showingPicker == true`; a popover anchored below the button presents the server picker. |
| Picker closed | `showingPicker == false` (the initial value); no popover is shown. |
| Server row checked/unchecked | A row's toggle shows checked when `viewModel.isActive(id)` is true; tapping it calls `viewModel.toggle(id)`, flipping membership and writing the new set back to the caller's binding. |
| Pressed | Not applicable — the toggle button uses a borderless style with no additional pressed-state styling; any momentary highlight is the system borderless-button style's own, not authored here. |
| Disabled | Not applicable — no control in this component (the button or any row toggle) is ever explicitly disabled; every control is always interactive. |
| Focused | Not applicable — no custom focus-ring styling is applied; standard system focus-ring behavior for a button/toggle is inherited, not authored. |
| Loading | Not applicable — the server list delivers its current value synchronously on subscription; the component defines no loading/pending indicator. |

## Accessibility

- **Role/trait**: Not explicitly set anywhere in source — no explicit
  accessibility role override is applied in this file. The button, each
  toggle, each icon, and each text label carry the platform's own default
  role for their kind (button, switch/toggle, image, static text)
  automatically.
- **Label requirements**: The toggle button's accessible label comes from
  its visible label text, which is used as the default accessibility label;
  no separate label override is set. Neither the rack icon nor the
  chevron-down icon carries an explicit accessibility label or hidden flag
  in source; the platform supplies a system default description for each
  named icon, and the two icons are separate accessibility elements from the
  button rather than grouped into one. Each picker row's label comes from
  the server's name, falling back to "Unknown" when missing.
- **Announce state changes**: Not applicable beyond the platform's own
  default — source posts no explicit accessibility change notification when
  the button's label text or a row's toggle state changes; the button label
  and each toggle are standard framework controls whose accessible value
  updates are surfaced by the framework itself when their bound content
  changes, with no bespoke announcement code in this file either way.
- **Minimum tap target**: Not applicable — this targets pointer and
  trackpad input, not touch. Source sets no explicit minimum width or
  height on the button or on a picker row; the 44×44pt (iOS) / 48×48dp
  (Android) minimum described in Platform Notes applies to the touch-
  platform translations, not to this pointer-based control.
- **icon-grouping**: Neither the rack icon nor the chevron-down icon in the
  button's label is marked hidden from assistive technology or folded into
  the button's label as a single element, so each remains its own,
  separately-spoken image element to the screen reader.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| mcp-chips-bar-001 | applies-theme-consistently | Initialize the bar with a registry and an active-server binding, then open the popover | The bar's content and the popover's content both reflect the app's active theme values (see Platform Notes for the mechanism) |
| mcp-chips-bar-003 | fills-parent-bounds | Initialize with the containing element at bounds `(0, 0, 300, 40)`, then resize the container to `(0, 0, 500, 60)` and let layout settle | The bar's bounds equal `(0, 0, 500, 60)`, matching the container's new bounds on all four edges |
| mcp-chips-bar-005 | shares-one-view-model-between-bar-and-picker | Initialize the view once, open the popover, then switch id1's row toggle | The bar's button label recomputes to reflect the new active count without re-initializing the view — the bar and the popover are driven by the same active-server state |
| mcp-chips-bar-006 | snapshots-active-ids-at-init | Construct with a binding whose value is `{A, B}`, then mutate the binding's external storage to `{C}` before any toggle | The view model's `activeServerIds` remains `{A, B}` |
| mcp-chips-bar-007 | subscribes-to-registry-clients, sorts-available-servers-by-name, rebuilds-server-names-on-update | Registry emits clients `[id1: "Bravo", id2: "alpha"]` | `availableServerIds == [id2, id1]` (case-insensitive "alpha" before "Bravo") and `serverNames == [id1: "Bravo", id2: "alpha"]` |
| mcp-chips-bar-008 | defaults-missing-name-to-empty-string-for-sort | Code inspection of the sort comparator in the view model's initializer (`clients[lhs]?.name ?? ""` / `clients[rhs]?.name ?? ""`) | The comparator falls back to `""` for a missing name instead of crashing or force-unwrapping; this branch is unreachable through the current call site, since the available ids are always sorted against that same clients dictionary, but the defensive default is present and correct if that ever changes |
| mcp-chips-bar-009 | reports-active-membership | `activeServerIds` contains id1 but not id2 | `isActive(id1) == true`, `isActive(id2) == false` |
| mcp-chips-bar-010 | toggles-membership-on-call, propagates-toggle-to-binding | `activeServerIds` does not contain id1; call `toggle(id1)` | `activeServerIds` now contains id1, and the caller's binding's value equals the new set |
| mcp-chips-bar-011 | toggles-membership-on-call, propagates-toggle-to-binding | `activeServerIds` contains id1; call `toggle(id1)` | `activeServerIds` no longer contains id1, and the caller's binding's value equals the new set |
| mcp-chips-bar-012 | renders-server-rack-icon | Render the bar | A server-rack icon is present, foreground-styled with `theme.secondaryText` |
| mcp-chips-bar-013 | computes-no-servers-label | `availableServerIds == []` | Button text reads exactly "No MCP servers" |
| mcp-chips-bar-014 | computes-none-active-label | `availableServerIds == [id1, id2]`, `activeServerIds == []` | Button text reads exactly "MCP: none" |
| mcp-chips-bar-015 | computes-count-active-label | `availableServerIds == [id1, id2, id3]`, `activeServerIds == {id1, id3}` | Button text reads exactly "MCP: 2 of 3" |
| mcp-chips-bar-016 | uses-borderless-button-style | Inspect the toggle button's style | A borderless button style is applied |
| mcp-chips-bar-017 | toggles-picker-on-tap | `showingPicker == false`; tap the button | `showingPicker == true` |
| mcp-chips-bar-018 | presents-popover-below-button | `showingPicker == true` | A popover is presented, anchored below the button |
| mcp-chips-bar-019 | reapplies-theme-inside-popover | Inspect the popover's content | The app's active theme is applied to the server picker's content independently of the bar's own application |
| mcp-chips-bar-020 | applies-bar-padding, trails-with-spacer | Inspect the bar's root layout container | 8pt spacing between children, 12pt horizontal / 6pt vertical padding on the container, and a flexible spacer as the final child |
| mcp-chips-bar-021 | shows-picker-heading | Render the server picker | "Active MCP Servers" is displayed in `theme.font(.heading)` |
| mcp-chips-bar-022 | shows-empty-state-message, lists-one-toggle-row-per-server | `availableServerIds == []` | The empty-state message "No connected servers.\nAdd one in Settings → MCP Servers." is shown and no toggle row is rendered |
| mcp-chips-bar-023 | lists-one-toggle-row-per-server, row-label-falls-back-to-unknown | `availableServerIds == [id1, id2]`, `serverNames == [id1: "Alpha"]` (id2 missing) | Exactly two rows render, in order id1 then id2, labeled "Alpha" and "Unknown" respectively |
| mcp-chips-bar-024 | row-toggle-reflects-active-state | id1 is a member of `activeServerIds` | id1's row toggle reads on (checked) |
| mcp-chips-bar-025 | row-toggle-calls-view-model-toggle | id1's row toggle is switched by the user | `viewModel.toggle(id1)` is invoked exactly once |
| mcp-chips-bar-026 | uses-checkbox-toggle-style | Inspect any rendered row toggle | A checkbox toggle style is applied |
| mcp-chips-bar-027 | applies-picker-padding-and-min-width | Inspect the server picker's root layout container | 8pt spacing, 14pt padding on all sides, and a minimum width of 220pt |

## Edge Cases

- Null/empty input (MUST): `registry` and `activeServerIds` are both
  required, non-optional parameters, so there is no absent/nil case for
  either. An empty `activeServerIds` value at construction (`{}`) is handled
  identically to any other set — no special-case branch exists for it. An
  empty registry (no clients) drives `computes-no-servers-label` and the
  picker's empty-state message.
- Boundary values (MUST): A registry with exactly one client is handled by
  the same sort/label logic as any other count (`"MCP: 1 of 1"` when that
  one server is active). No maximum server count is enforced anywhere in
  source.
- Concurrent access: Not applicable — both the bar and its view model
  confine every read and write of `availableServerIds`, `serverNames`, and
  `activeServerIds` to a single execution context (see Platform Notes for
  the mechanism); source provides no path for two threads to mutate this
  component's state simultaneously.
- Error states (MUST): the registry's client-list subscription has no
  failure case — its updates never complete with an error — so no
  error-handling branch exists or is needed in this file. No other
  operation in this file (sorting, dictionary construction, set membership)
  can throw.
- Offline/disconnected: Not applicable — this file never opens a network
  connection itself; it only reads the registry's already-resolved client
  list and each client's cached `name`. Whether a given server's underlying
  connection is up, down, or reconnecting is the registry's and the
  client's concern, entirely outside this file, and is not reflected in the
  bar's appearance.
- Stale active ids outlive their server (MUST): `activeServerIds` is only
  intersected with `Set(availableServerIds)` when computing the button's
  displayed count (`computes-count-active-label`); the underlying
  `activeServerIds` set — and the external binding it is written back to —
  keeps any id that the registry has since stopped reporting. If that same
  id's server later reappears in the registry's client list, it is
  immediately reported active again with no re-confirmation step, since
  `toggle(_:)`/`propagates-toggle-to-binding` is the only path that ever
  removes an id from the set (see the "Stale active ids" Design Decision).
- Picker opened with no available servers (MUST): Opening the popover while
  `availableServerIds == []` shows only the empty-state message; the
  `showingPicker` toggle and popover presentation are unaffected by whether
  any servers exist.
- Row toggle setter is not idempotent (MUST): Each row's toggle binding
  reads `viewModel.isActive(id)` and, on any set, ignores the new boolean
  value entirely and unconditionally calls `toggle(id)`, per
  **row-toggle-calls-view-model-toggle**. Setting a row to the value it
  already holds still flips membership, rather than leaving it unchanged.
  The platform's own toggle control only invokes a boolean binding's setter
  when the user's interaction actually changes the displayed value, so this
  does not manifest through normal use, but nothing in the setter itself
  guards against being invoked with a value equal to the current state.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `registry` | the server registry | — (required) | Supplies the live client list this bar and its popover observe for the available-server list and names. |
| `activeServerIds` | two-way binding to a set of ids | — (required) | Two-way link to the caller's active-server set. Its value is read once, at construction, for the initial snapshot (see **snapshots-active-ids-at-init**), and is written to — never re-read — every time the user toggles a server. |

## Deep Linking

Not applicable: this is an embedded chat-window header bar with no URL
scheme, route, or deep-link handler in source. Per the type's doc comment it
is intended to be hosted directly in the chat window's own view hierarchy,
not presented or navigated to via a link.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `Active MCP Servers` (translatable string) | Active MCP Servers | Popover heading |
| `No connected servers.\nAdd one in Settings → MCP Servers.` (translatable string) | No connected servers.\nAdd one in Settings → MCP Servers. | Popover empty-state message |
| — (not localized) | No MCP servers | Computed button label |
| — (not localized) | MCP: none | Computed button label |
| — (not localized) | MCP: {active} of {total} | Computed button label |
| — (not localized) | Unknown | Fallback row label when a server id is missing from the name lookup |

The button's label and the row's fallback label are computed as plain,
unlocalized strings rather than translation keys, and render verbatim with
no string-table lookup, even though their possible values ("No MCP
servers", "MCP: none", "MCP: {n} of {m}", "Unknown") are authored as
English literals. None of these four strings goes through localization in
source.

## Accessibility Options

- **Reduce Motion**: Not applicable — no animation or transition is
  triggered anywhere in source; the popover's presentation and dismissal
  transition is the platform's own system chrome, not custom motion
  authored by this file.
- **Increase Contrast**: Not applicable — every color used here
  (`theme.secondaryText`, `theme.accent`, and the primary text/background
  colors inherited from the shared theming mechanism) resolves through the
  shared theme palette; any Increase Contrast adaptation is that shared
  palette's responsibility, not a color this file hardcodes.
- **Differentiate Without Color**: Satisfied — the active-server count and
  the "none"/"No MCP servers" states are conveyed through text, and each
  row's active state is conveyed by the checkbox toggle's checkmark glyph,
  not by color alone.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
source. Per the type's own doc comment this bar is simply "retained for
Phase 2" as ordinary, unconditionally-constructed code; nothing in this file
gates whether it renders behind a flag.

## Analytics

Not applicable: source contains no analytics or telemetry call of any kind.

## Privacy

- **Data collected**: None beyond what the caller already holds — the bar
  and picker only display server ids/names and active-membership state
  already exposed by the caller-supplied registry and `activeServerIds`
  binding.
- **Storage**: In-memory only, for the view model's lifetime
  (`availableServerIds`, `serverNames`, `activeServerIds`); this file writes
  nothing to disk or any other persistent store. Any persistence of server
  configuration is the registry's responsibility, outside this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source; connecting to a configured MCP server is the registry's and the
  client's responsibility, not this file's.
- **Retention**: None beyond the hosting element's and view model's
  lifetime; state is discarded when the view is deallocated.

## Logging

Not applicable: source contains no logging call (no `print`, `os_log`, or
`Logger` reference anywhere in this file).

## Platform Notes

- **SwiftUI**: `MCPChipsBar` and `MCPServerPicker` are already SwiftUI; a
  fully SwiftUI rebuild would drop the outer `NSView`/`NSHostingView` shell
  and host `MCPChipsBar` directly wherever the chat window's own view tree
  needs it, applying `.themedRoot()` once at that call site exactly as this
  file does. Keep `theme.font(.caption)`/`.heading` and `theme.accent`/
  `.secondaryText` unchanged, and keep reapplying `.themedRoot()` inside the
  `.popover` content — the source comment's "a popover is its own window"
  reasoning holds regardless of whether the presenting view is itself
  AppKit-hosted, because this app injects its custom `\.theme` environment
  value per hosting root rather than once at a single top-level SwiftUI
  `App` scene.
- **Compose**: Render the bar as a `Row` with an `Icon` (Material's closest
  server-rack glyph, or a custom vector asset) and a borderless `TextButton`
  showing the same three-branch label text, opening a `DropdownMenu`
  anchored to the button. List one `Row(Checkbox(checked = isActive(id)) {
  Text(name) })` per sorted server id inside the menu — Compose's ambient
  `MaterialTheme`/`CompositionLocal`s flow into a `DropdownMenu` without
  needing a manual reapply step, unlike `themedRoot()` here. Since each row
  has no fixed height in source, give the `TextButton` and each menu `Row` a
  minimum touch target of 48×48dp, matching Android's platform minimum (see
  **Minimum tap target** under Accessibility).
- **React/Web**: Render the bar as a flex row with an icon and a button
  (`aria-haspopup="true"`, `aria-expanded={showingPicker}`) that opens a
  popover component anchored below it (e.g. a Radix/Headless UI popover),
  listing one `<label><input type="checkbox" checked={isActive(id)} />
  {name}</label>` row per sorted server id, computed with the same
  three-branch label logic. If the popover implementation renders into a
  portal outside the bar's DOM subtree, verify CSS custom properties/theme
  context still reach it — the web analog of the `themedRoot()`-inside-the-
  popover quirk this source works around.
- **AppKit / UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/MCPChipsBarView.swift`.
  A `@MainActor`, `final` `NSView` that hosts SwiftUI content
  (`MCPChipsBar`/`MCPServerPicker`) via `NSHostingView`, pinned to its own
  bounds with Auto Layout, rather than being built as raw AppKit controls.
  Both the host view and its hosted subview set
  `translatesAutoresizingMaskIntoConstraints = false` and rely on Auto
  Layout constraints, pinned to the parent's edges, for
  **fills-parent-bounds** rather than autoresizing masks. The host view does
  not implement `init(coder:)` — a storyboard/xib instantiation attempt
  traps with a fatal error, since this view is only ever constructed
  programmatically. The rack icon is the SF Symbol `"server.rack"`; the
  disclosure chevron in the button's label is the SF Symbol
  `"chevron.down"`. The popover for **presents-popover-below-button** is
  presented with `arrowEdge: .bottom`. The unmodified default type sizes
  cited under Appearance's **Font** entry come from
  `ThemeTypography.defaultStyle(_:)` in
  `external/agenticdevelopertoolkit/packages/apple/AgenticDeveloperToolkit/Sources/Theme/ThemeTypography.swift`.
  The app's `\.theme` environment value is applied to that content via the
  shared `.themedRoot()` helper (once on `MCPChipsBar`'s root, and again on
  `MCPServerPicker` inside the popover, since a popover is its own window —
  see **reapplies-theme-inside-popover**); the view model retains its
  `registry.$clients` subscription in a `Set<AnyCancellable>` property for
  its lifetime. Declaring both `MCPChipsBarView` and `MCPChipsBarViewModel`
  `@MainActor` is what confines every read and write of
  `availableServerIds`, `serverNames`, and `activeServerIds` to a single
  execution context (see the Edge Cases "Concurrent access" entry). There is
  no UIKit code path in source; a UIKit port would keep the SwiftUI content
  but host it with `UIHostingController`, replace the `.popover` with a
  `UIPopoverPresentationController` (iPad) or a sheet (iPhone) — and, since
  Toggle rows have no fixed height in source, would need to give each row at
  least a 44pt touch target, since AppKit's `.checkbox` toggle style carries
  no such minimum.
- **WinUI 3**: Build the bar as a `StackPanel`
  (`Orientation="Horizontal"`, `Spacing="8"`) holding a `FontIcon` using a
  Segoe Fluent Icons server glyph in place of `"server.rack"`, and a
  borderless `Button` (`Style="{StaticResource TextBlockButtonStyle}"` or
  equivalent, mirroring `.buttonStyle(.borderless)`) whose `Content` is the
  same three-branch label text plus a `FontIcon` chevron-down glyph, with a
  `Flyout` attached via `Button.Flyout` — the direct analog of `.popover` —
  set to `Placement="Bottom"` to mirror `arrowEdge: .bottom`. Inside the
  `Flyout`, use a `StackPanel` (`Spacing="8"`, `Padding="14"`, `MinWidth="220"`)
  containing a `TextBlock` heading ("Active MCP Servers") and either a
  two-line `TextBlock` empty-state message or one `CheckBox` per sorted
  server id (`IsChecked` bound to `isActive(id)`, `Content` bound to
  `name`), mirroring `lists-one-toggle-row-per-server` and
  `row-label-falls-back-to-unknown`. WinUI resource/`ThemeResource` lookups
  flow into a `Flyout`'s content automatically since it shares the visual
  tree's resource dictionaries, so — unlike this source's
  `reapplies-theme-inside-popover` requirement — no manual theme-reapply
  step is needed; call this out to implementors as a deliberate platform
  difference.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/MCPChipsBarView.swift` |

## Design Decisions

**Decision**: Read `activeServerIds.wrappedValue` once at construction into
the view model's own `@Published activeServerIds`, rather than observing
the binding for later external changes.
**Rationale**: In the Swift/AppKit implementation, traceable to
`MCPChipsBarViewModel.init`, which assigns `self.activeServerIds =
activeServerIds.wrappedValue` with no Combine subscription on the binding's
source; only `toggle(_:)` ever updates the binding afterward (one-way, out). This keeps the model's published state
the single source of truth for rendering after init, at the cost of the
bar not reflecting an external change to the active set made through some
other UI while this bar is visible. Until this decision is approved,
**snapshots-active-ids-at-init** and the "Stale active ids outlive their
server" edge case describe the current, accepted behavior — not
necessarily the final design.
**Approved**: pending

**Decision**: Ship the bar fully functional but retained, unwired to any chat
consumer.
**Rationale**: Per the type's doc comment, "Not wired to any chat consumer in
Phase 1 — the MCP tool loop lives in `MCPChatToolSource`. This bar is
retained for Phase 2 when a consumer surfaces the registry selection UI
again." The component computes and reports active-server state correctly,
but no other file currently reads `activeServerIds` or observes changes
written through the binding.
**Approved**: pending

**Decision**: Apply `.themedRoot()` twice — once to `MCPChipsBar`'s root, and
again to `MCPServerPicker` inside the `.popover` content — instead of
once for the whole component.
**Rationale**: In the Swift/AppKit implementation, per the inline source
comment, "A popover is its own window, so it is outside this view's
environment and needs the palette injected again." Reapplying it is a
workaround for a limitation in how this app's custom `\.theme` environment
value propagates into `NSPopover`-backed content, not a change in visual
intent between the bar and the picker.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | Platform Compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |

Native-controls-preference and platform-design-language pass because the bar
composes standard SwiftUI controls (`Button`, `Toggle`, `Text`, `Image`) with
system styles (`.borderless`, `.checkbox`) and a system `.popover`, rather
than custom-drawn chrome. Keyboard-navigable is partial: these are standard,
framework-provided controls, but the toggle button uses `.buttonStyle(.borderless)`,
and a borderless SwiftUI button on macOS is only Tab-reachable when Full
Keyboard Access is enabled; no keyboard-navigation test of this bar exists in
source. Screen-reader-support is partial: button and row labels come from visible
`Text` content with no explicit override, but the "server.rack" icon is a
separate, ungrouped accessibility element next to the button (see **Label
requirements** under Accessibility, and **icon-grouping**)
and no explicit announcement accompanies a label or toggle-state change.
String-externalization is failed because the button's three label strings
and the "Unknown" row fallback are unlocalized `String` values with no
string-table lookup (see Localization). Separation-of-concerns passes because
`MCPChipsBarViewModel` owns all registry/binding logic, leaving
`MCPChipsBar` and `MCPServerPicker` as plain rendering of that model's
published state.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude Sonnet 5 | Initial ingredient recipe for MCPChipsBarView, covering the bar/picker view pair, the view model's sort/label/toggle logic, the one-time active-ids snapshot and stale-id quirks, and one open localization question (unlocalized computed label strings) for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reworded two requirements and the `cancellables`-touching one to state observable behavior instead of private identifiers, moving those identifiers into Platform Notes; added an open-question note for the ungrouped rack/chevron icons; added an edge case for the non-idempotent row-toggle setter; corrected the keyboard-navigable compliance status and the ThemeTypography citation; reformatted Design Decisions to the bold three-line form and noted two MUSTs as accepted-pending-approval behavior; tightened three underspecified test vectors; dropped a redundant tag; converted Compliance categories to display names and removed the invented `main-actor-confined` and `differentiate-without-color` checks via the compliance-catalog fixer. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/chat/chat-window/. |
