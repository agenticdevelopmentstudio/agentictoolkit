---
id: bea6525c-171f-4547-bbb3-7c709543552e
title: MCPChipsBarView
domain: agentictoolkit://recipes/mcp-chips-bar-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
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
- appkit
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# MCPChipsBarView

## Overview

`MCPChipsBarView` is an `NSView` subclass that hosts a small SwiftUI header
bar for an AI chat window: a "server.rack" icon and a button reporting how
many of the configured MCP servers are currently active. Tapping the button
opens a popover listing every available server as a checkbox toggle, letting
the user turn individual servers on or off for the chat. Per the type's own
doc comment, the bar is "not wired to any chat consumer in Phase 1 — the MCP
tool loop lives in `MCPChatToolSource`. This bar is retained for Phase 2 when
a consumer surfaces the registry selection UI again" — so, as shipped, it
computes and reports active-server state faithfully but nothing downstream
currently reads that state (see Design Decisions).

## Behavioral Requirements

- **hosts-swiftui-content**: The view MUST host `MCPChipsBar` inside an
  `NSHostingView` added as its subview, with the app's theme environment
  values applied to that content (see Platform Notes for the mechanism).
- **disables-autoresizing-mask**: The view and its hosted `NSHostingView`
  MUST each set `translatesAutoresizingMaskIntoConstraints = false`.
- **fills-parent-bounds**: The hosted view's top, leading, trailing, and
  bottom anchors MUST be constrained equal to the parent view's
  corresponding anchors.
- **rejects-coder-initialization**: The view MUST NOT support
  `init(coder:)` and MUST fail fast (fatal error) if it is invoked.
- **shares-one-view-model-between-bar-and-picker**: The bar's toggle button
  and the popover's server rows MUST reflect the same active-server state,
  backed by a single view model constructed at initialization from the given
  `registry` and `activeServerIds` binding — so toggling a row in the popover
  is immediately reflected in the bar's button label.
- **snapshots-active-ids-at-init**: The view model's `activeServerIds` MUST
  be set to the wrapped value of the caller's `activeServerIds` binding at
  construction time, read exactly once.
- **subscribes-to-registry-clients**: The view model MUST subscribe to
  `registry.$clients` for its lifetime, so every update to `clients` is
  picked up without the caller re-observing manually (see Platform Notes for
  how the subscription is retained).
- **sorts-available-servers-by-name**: On every `clients` update,
  `availableServerIds` MUST be set to the clients' keys sorted by each
  client's `name`, ascending, using `localizedCaseInsensitiveCompare`.
- **defaults-missing-name-to-empty-string-for-sort**: When comparing two ids
  for the sort in `sorts-available-servers-by-name`, a missing name lookup
  (`clients[id]?.name`) MUST be treated as `""`.
- **rebuilds-server-names-on-update**: On every `clients` update,
  `serverNames` MUST be replaced with a fresh `[UUID: String]` mapping each
  client id to that client's current `name`.
- **reports-active-membership**: `isActive(_:)` MUST return whether the
  given id is a member of `activeServerIds`.
- **toggles-membership-on-call**: `toggle(_:)` MUST remove the given id from
  `activeServerIds` if present, and MUST insert it if absent.
- **propagates-toggle-to-binding**: `toggle(_:)` MUST write the resulting
  `activeServerIds` set to the caller-supplied binding's `wrappedValue`
  after every call.
- **renders-server-rack-icon**: The bar MUST display the SF Symbol
  `"server.rack"`, tinted with `theme.secondaryText`.
- **renders-toggle-button**: The bar MUST display one button whose label
  contains the computed button text followed by the SF Symbol
  `"chevron.down"`, both tinted with `theme.accent` and set in
  `theme.font(.caption)`.
- **computes-no-servers-label**: The button's text MUST read
  `"No MCP servers"` when `availableServerIds` is empty.
- **computes-none-active-label**: When `availableServerIds` is non-empty and
  the intersection of `activeServerIds` with `Set(availableServerIds)` is
  empty, the button's text MUST read `"MCP: none"`.
- **computes-count-active-label**: When that intersection is non-empty, the
  button's text MUST read `"MCP: {active} of {total}"`, where `active` is
  the intersection's count and `total` is `availableServerIds.count`.
- **uses-borderless-button-style**: The toggle button MUST use the
  `.borderless` button style.
- **toggles-picker-on-tap**: Tapping the button MUST toggle the
  `showingPicker` state.
- **presents-popover-below-button**: The bar MUST present a popover, bound
  to `showingPicker`, anchored with `arrowEdge: .bottom`.
- **reapplies-theme-inside-popover**: The popover's content MUST wrap
  `MCPServerPicker` in its own `.themedRoot()` call.
- **applies-bar-padding**: The bar's root `HStack` MUST use 8pt inter-item
  spacing and MUST be padded 12pt horizontally and 6pt vertically.
- **trails-with-spacer**: The bar's root `HStack` MUST end with a `Spacer()`
  after the toggle button.
- **shows-picker-heading**: The popover MUST display the text
  `"Active MCP Servers"` in `theme.font(.heading)`.
- **shows-empty-state-message**: When `availableServerIds` is empty, the
  popover MUST display the text `"No connected servers.\nAdd one in
  Settings → MCP Servers."`, tinted with `theme.secondaryText` and set in
  `theme.font(.caption)`, in place of any server row.
- **lists-one-toggle-row-per-server**: When `availableServerIds` is
  non-empty, the popover MUST render exactly one `Toggle` row per id, in
  `availableServerIds`'s order, and MUST NOT render the empty-state message.
- **row-label-falls-back-to-unknown**: Each row's label MUST read
  `serverNames[id]` when present, and `"Unknown"` otherwise.
- **row-toggle-reflects-active-state**: Each row's `Toggle` MUST be bound so
  reading it returns `viewModel.isActive(id)`.
- **row-toggle-calls-view-model-toggle**: Setting a row's `Toggle` (to
  either value) MUST call `viewModel.toggle(id)`.
- **uses-checkbox-toggle-style**: Every row `Toggle` MUST use the
  `.checkbox` toggle style.
- **applies-picker-padding-and-min-width**: The popover's root `VStack` MUST
  use 8pt spacing, MUST be padded 14pt on all sides, and MUST have a minimum
  width of 220pt.

## Appearance

- **Corner radius**: Not applicable — no corner radius or custom layer is
  set anywhere in source; any rounding on the popover's chrome comes from
  `NSPopover`'s own default appearance.
- **Padding**: Bar `HStack`: 12pt horizontal / 6pt vertical, 8pt spacing
  between the icon, the button, and the trailing `Spacer()`. Button's inner
  `HStack` (label + chevron): 4pt spacing, no explicit padding. Picker
  `VStack`: 14pt on all sides, 8pt spacing between rows.
- **Font**: `theme.font(.caption)` for the bar button's label/chevron and
  for the picker's empty-state message; `theme.font(.heading)` for the
  picker's "Active MCP Servers" heading. Per
  `ThemeTypography.defaultStyle(_:)` in
  `external/agenticdevelopertoolkit/packages/apple/AgenticDeveloperToolkit/Sources/Theme/ThemeTypography.swift`,
  the
  unmodified system defaults for these roles are 11pt regular (`.caption`)
  and 15pt semibold (`.heading`), each additionally scaled by the active
  theme's `sizeScale`. Each server row's `Text` label and the checkbox's own
  title set no explicit font, so they render in SwiftUI's default `.body`
  text style.
- **Background**: Not set explicitly by this file; both roots
  (`MCPChipsBar` and, separately, `MCPServerPicker` inside the popover) sit
  on whatever `.themedRoot()` paints — the active theme's window background
  — since each call site accepts `themedRoot()`'s `paintsBackground: true`
  default.
- **Foreground/Text**: `theme.secondaryText` on the rack icon and the
  picker's empty-state message; `theme.accent` on the button's label and
  chevron; the heading and each row's label use the primary text color
  `.themedRoot()` applies at each host root, not a color this file sets
  itself.
- **Border**: Not applicable — no border modifier or `NSView` border
  appears anywhere in source.
- **Shadow**: Not applicable — no shadow is drawn or configured in source;
  the popover's window shadow is `NSPopover`'s own system chrome.
- **Min/Max size**: The bar itself has no fixed frame — it sizes to its
  content plus padding, and is stretched to fill whatever bounds the
  `NSHostingView`'s edge constraints give it inside the parent `NSView`.
  `MCPServerPicker` has a minimum width of 220pt and no maximum; `NSPopover`
  otherwise sizes the popover to that content's fitting size.

## States

| State | Appearance change |
|-------|------------------|
| Default | Rack icon plus button showing the current computed label; no popover shown. |
| No servers configured | Button text reads "No MCP servers"; if opened, the popover shows the empty-state message instead of any row. |
| Servers configured, none active | Button text reads "MCP: none". |
| Servers configured, some or all active | Button text reads "MCP: {active} of {total}". |
| Picker open | `showingPicker == true`; a popover anchored below the button (`arrowEdge: .bottom`) presents `MCPServerPicker`. |
| Picker closed | `showingPicker == false` (the initial value); no popover is shown. |
| Server row checked/unchecked | A row's `Toggle` shows checked when `viewModel.isActive(id)` is true; tapping it calls `viewModel.toggle(id)`, flipping membership and writing the new set back to the caller's binding. |
| Pressed | Not applicable — `.buttonStyle(.borderless)` is used with no additional pressed-state modifier in source; any momentary highlight is the system borderless-button style's own, not authored here. |
| Disabled | Not applicable — no control in this file (the button or any `Toggle`) is ever given `.disabled(...)`; every control is always interactive. |
| Focused | Not applicable — no `.focused()`/`@FocusState` binding or custom focus-ring styling appears in source; standard system focus-ring behavior for `Button`/`Toggle` is inherited, not authored. |
| Loading | Not applicable — `registry.$clients` (an `@Published` property) delivers its current value synchronously to the `sink` on subscription; source defines no loading/pending indicator. |

## Accessibility

- **Role/trait**: Not explicitly set anywhere in source — no
  `.accessibilityElement`/`.accessibilityAddTraits`/`.accessibilityRole`
  call appears in this file. `Button`, `Toggle`, `Text`, and `Image` each
  carry SwiftUI's own default role for their kind (button, switch/toggle,
  static text, image) automatically.
- **Label requirements**: The toggle button's accessible label comes from
  its visible `Text(buttonLabel)` content, which SwiftUI buttons use as
  their default accessibility label; no separate `.accessibilityLabel` is
  set. Neither the `"server.rack"` nor the `"chevron.down"` SF Symbol image
  carries an explicit `.accessibilityLabel`/`.accessibilityHidden` in
  source; SwiftUI supplies a system default description for named SF
  Symbols, and the two images are separate accessibility elements from the
  button rather than grouped into one (no `.accessibilityElement(children:
  .combine)` is used). Each picker row's label comes from
  `Text(serverNames[id] ?? "Unknown")`.
- **Announce state changes**: Not applicable beyond the platform's own
  default — source posts no explicit accessibility notification (no
  `NSAccessibility.post`/similar) when the button's label text or a row's
  toggle state changes; `Text` and `Toggle` are standard SwiftUI controls
  whose accessible value updates are surfaced by the framework itself when
  their bound content changes, with no bespoke announcement code in this
  file either way.
- **Minimum tap target**: Not applicable — this targets macOS pointer and
  trackpad input, not touch. Source sets no explicit minimum width or
  height on the button or on a picker row; the 44×44pt (iOS) / 48×48dp
  (Android) minimum described in Platform Notes applies to the touch-
  platform translations, not to this AppKit-hosted SwiftUI control.
- **icon-grouping**: Neither the `"server.rack"` icon (`MCPChipsBarView.swift`) nor the `"chevron.down"` icon in the button's label (`MCPChipsBarView.swift`) is marked `.accessibilityHidden(true)` or folded into the button's label via `.accessibilityElement(children: .combine)`, so each remains its own, separately-spoken image element to VoiceOver.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| mcp-chips-bar-001 | hosts-swiftui-content | Initialize `MCPChipsBarView(registry:activeServerIds:)` | Its subview tree contains exactly one `NSHostingView` whose root view is `MCPChipsBar`, and reading `\.theme` from that root view's environment returns the app's active theme (see Platform Notes for the mechanism) |
| mcp-chips-bar-002 | disables-autoresizing-mask | Inspect the view and its hosted subview after init | Both report `translatesAutoresizingMaskIntoConstraints == false` |
| mcp-chips-bar-003 | fills-parent-bounds | Initialize with the parent view at frame `(0, 0, 300, 40)`, then resize the parent to `(0, 0, 500, 60)` and force a layout pass (`layoutSubtreeIfNeeded()`) | The hosted view's frame equals `(0, 0, 500, 60)`, matching the parent's new bounds on all four edges |
| mcp-chips-bar-004 | rejects-coder-initialization | Attempt `MCPChipsBarView(coder:)` | The call traps with a fatal error; no instance is returned |
| mcp-chips-bar-005 | shares-one-view-model-between-bar-and-picker | Initialize the view once, open the popover, then switch id1's row `Toggle` | The bar's button label recomputes to reflect the new active count without re-initializing the view — the bar and the popover are driven by the same active-server state |
| mcp-chips-bar-006 | snapshots-active-ids-at-init | Construct with a binding whose `wrappedValue` is `{A, B}`, then mutate the binding's external storage to `{C}` before any toggle | The view model's `activeServerIds` remains `{A, B}` |
| mcp-chips-bar-007 | subscribes-to-registry-clients, sorts-available-servers-by-name, rebuilds-server-names-on-update | Registry emits clients `[id1: "Bravo", id2: "alpha"]` | `availableServerIds == [id2, id1]` (case-insensitive "alpha" before "Bravo") and `serverNames == [id1: "Bravo", id2: "alpha"]` |
| mcp-chips-bar-008 | defaults-missing-name-to-empty-string-for-sort | Code inspection of the sort comparator in `MCPChipsBarViewModel.init` (`clients[lhs]?.name ?? ""` / `clients[rhs]?.name ?? ""`) | The comparator falls back to `""` for a missing name instead of crashing or force-unwrapping; this branch is unreachable through the current call site, since `Array(clients.keys)` is always sorted against that same `clients` dictionary, but the defensive default is present and correct if that ever changes |
| mcp-chips-bar-009 | reports-active-membership | `activeServerIds` contains id1 but not id2 | `isActive(id1) == true`, `isActive(id2) == false` |
| mcp-chips-bar-010 | toggles-membership-on-call, propagates-toggle-to-binding | `activeServerIds` does not contain id1; call `toggle(id1)` | `activeServerIds` now contains id1, and the caller's binding's `wrappedValue` equals the new set |
| mcp-chips-bar-011 | toggles-membership-on-call, propagates-toggle-to-binding | `activeServerIds` contains id1; call `toggle(id1)` | `activeServerIds` no longer contains id1, and the caller's binding's `wrappedValue` equals the new set |
| mcp-chips-bar-012 | renders-server-rack-icon | Render `MCPChipsBar` | An `Image(systemName: "server.rack")` is present, foreground-styled with `theme.secondaryText` |
| mcp-chips-bar-013 | computes-no-servers-label | `availableServerIds == []` | Button text reads exactly "No MCP servers" |
| mcp-chips-bar-014 | computes-none-active-label | `availableServerIds == [id1, id2]`, `activeServerIds == []` | Button text reads exactly "MCP: none" |
| mcp-chips-bar-015 | computes-count-active-label | `availableServerIds == [id1, id2, id3]`, `activeServerIds == {id1, id3}` | Button text reads exactly "MCP: 2 of 3" |
| mcp-chips-bar-016 | uses-borderless-button-style | Inspect the toggle button's style | `.borderless` button style is applied |
| mcp-chips-bar-017 | toggles-picker-on-tap | `showingPicker == false`; tap the button | `showingPicker == true` |
| mcp-chips-bar-018 | presents-popover-below-button | `showingPicker == true` | A popover is presented with `arrowEdge == .bottom` |
| mcp-chips-bar-019 | reapplies-theme-inside-popover | Inspect the popover's content view | `MCPServerPicker` is wrapped in its own `.themedRoot()` call, distinct from the bar's |
| mcp-chips-bar-020 | applies-bar-padding, trails-with-spacer | Inspect the bar's root `HStack` | 8pt spacing between children, 12pt horizontal / 6pt vertical padding on the stack, and a `Spacer()` as the final child |
| mcp-chips-bar-021 | shows-picker-heading | Render `MCPServerPicker` | "Active MCP Servers" is displayed in `theme.font(.heading)` |
| mcp-chips-bar-022 | shows-empty-state-message, lists-one-toggle-row-per-server | `availableServerIds == []` | The empty-state message "No connected servers.\nAdd one in Settings → MCP Servers." is shown and no `Toggle` row is rendered |
| mcp-chips-bar-023 | lists-one-toggle-row-per-server, row-label-falls-back-to-unknown | `availableServerIds == [id1, id2]`, `serverNames == [id1: "Alpha"]` (id2 missing) | Exactly two rows render, in order id1 then id2, labeled "Alpha" and "Unknown" respectively |
| mcp-chips-bar-024 | row-toggle-reflects-active-state | id1 is a member of `activeServerIds` | id1's row `Toggle` reads on (checked) |
| mcp-chips-bar-025 | row-toggle-calls-view-model-toggle | id1's row `Toggle` is switched by the user | `viewModel.toggle(id1)` is invoked exactly once |
| mcp-chips-bar-026 | uses-checkbox-toggle-style | Inspect any rendered row `Toggle` | `.checkbox` toggle style is applied |
| mcp-chips-bar-027 | applies-picker-padding-and-min-width | Inspect `MCPServerPicker`'s root `VStack` | 8pt spacing, 14pt padding on all sides, and a minimum width of 220pt |

## Edge Cases

- Null/empty input (MUST): `registry` and `activeServerIds` are
  non-optional, non-failable-typed initializer parameters, so Swift's type
  system rules out `nil` for either. An empty `activeServerIds.wrappedValue`
  at construction (`{}`) is handled identically to any other set — no
  special-case branch exists for it. An empty registry (`clients == [:]`)
  drives `computes-no-servers-label` and the picker's empty-state message.
- Boundary values (MUST): A registry with exactly one client is handled by
  the same sort/label logic as any other count (`"MCP: 1 of 1"` when that
  one server is active). No maximum server count is enforced anywhere in
  source.
- Concurrent access: Not applicable — both `MCPChipsBarView` and
  `MCPChipsBarViewModel` are declared `@MainActor`, so Swift's concurrency
  checker confines every read and write of `availableServerIds`,
  `serverNames`, and `activeServerIds` to the main actor; source provides no
  path for two threads to mutate this component's state simultaneously.
- Error states (MUST): `registry.$clients`' `sink` closure has no failure
  case — `@Published`'s publisher never completes with an error — so no
  error-handling branch exists or is needed in this file. No other
  operation in this file (sorting, dictionary construction, set membership)
  can throw.
- Offline/disconnected: Not applicable — this file never opens a network
  connection itself; it only reads `registry.$clients`' already-resolved
  client list and each client's cached `name`. Whether a given server's
  underlying connection is up, down, or reconnecting is `MCPServerRegistry`'s
  and `MCPClient`'s concern, entirely outside this file, and is not
  reflected in the bar's appearance.
- Stale active ids outlive their server (MUST): `activeServerIds` is only
  intersected with `Set(availableServerIds)` when computing the button's
  displayed count (`computes-count-active-label`); the underlying
  `activeServerIds` set — and the external binding it is written back to —
  keeps any id that the registry has since stopped reporting. If that same
  id's server later reappears in `registry.$clients`, it is immediately
  reported active again with no re-confirmation step, since
  `toggle(_:)`/`propagates-toggle-to-binding` is the only path that ever
  removes an id from the set (see the "Stale active ids" Design Decision).
- Picker opened with no available servers (MUST): Opening the popover while
  `availableServerIds == []` shows only the empty-state message; the
  `showingPicker` toggle and popover presentation are unaffected by whether
  any servers exist.
- Row toggle setter is not idempotent (MUST): Each row's `Toggle` binding is
  `Binding(get: { viewModel.isActive(id) }, set: { _ in viewModel.toggle(id)
  })` — the setter ignores the new boolean value entirely and unconditionally
  calls `toggle(id)`, per **row-toggle-calls-view-model-toggle**. Setting a
  row to the value it already holds still flips membership, rather than
  leaving it unchanged. SwiftUI's own `Toggle` only invokes a boolean
  binding's setter when the user's interaction actually changes the
  displayed value, so this does not manifest through normal use, but nothing
  in the setter itself guards against being invoked with a value equal to
  the current state.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `registry` | `MCPServerRegistry` | — (required) | Supplies the live `$clients` publisher this bar and its popover observe for the available-server list and names. |
| `activeServerIds` | `Binding<Set<UUID>>` | — (required) | Two-way link to the caller's active-server set. Its `wrappedValue` is read once, at construction, for the initial snapshot (see **snapshots-active-ids-at-init**), and is written to — never re-read — every time the user toggles a server. |

## Deep Linking

Not applicable: this is an embedded chat-window header bar with no URL
scheme, route, or deep-link handler in source. Per the type's doc comment it
is intended to be hosted directly in the chat window's own view hierarchy,
not presented or navigated to via a link.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `Active MCP Servers` (SwiftUI `Text` literal, a `LocalizedStringKey`) | Active MCP Servers | Popover heading |
| `No connected servers.\nAdd one in Settings → MCP Servers.` (SwiftUI `Text` literal, a `LocalizedStringKey`) | No connected servers.\nAdd one in Settings → MCP Servers. | Popover empty-state message |
| — (unlocalized `String` value, no key) | No MCP servers | Button label computed by `buttonLabel`, passed to `Text` as a `String` variable |
| — (unlocalized `String` value, no key) | MCP: none | Button label computed by `buttonLabel`, passed to `Text` as a `String` variable |
| — (unlocalized `String` value, no key) | MCP: {active} of {total} | Button label computed by `buttonLabel`, passed to `Text` as a `String` variable |
| — (unlocalized `String` value, no key) | Unknown | Fallback row label when a server id is missing from `serverNames`, passed to `Text` as a `String` expression |

`buttonLabel` is declared `private var buttonLabel: String`, so
`Text(buttonLabel)` always receives a `String` value rather than a
`LocalizedStringKey`, and SwiftUI renders it verbatim with no string-table
lookup, even though its three possible values ("No MCP servers", "MCP:
none", "MCP: {n} of {m}") are authored as English literals inside that
computed property. The same is true of
`Text(viewModel.serverNames[id] ?? "Unknown")`, whose `??` expression is
typed `String`. None of these four strings goes through localization in
source.

## Accessibility Options

- **Reduce Motion**: Not applicable — no animation, transition, or
  `withAnimation` call appears anywhere in source; the popover's
  presentation and dismissal transition is SwiftUI/AppKit's own system
  chrome, not custom motion authored by this file.
- **Increase Contrast**: Not applicable — every color used here
  (`theme.secondaryText`, `theme.accent`, and the primary text/background
  colors inherited from `.themedRoot()`) resolves through the shared
  `SemanticPalette`/`ThemeObservable`; any Increase Contrast adaptation is
  that shared palette's responsibility, not a color this file hardcodes.
- **Differentiate Without Color**: Satisfied — the active-server count and
  the "none"/"No MCP servers" states are conveyed through text, and each
  row's active state is conveyed by the checkbox toggle's checkmark glyph
  (`.toggleStyle(.checkbox)`), not by color alone.

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
  already exposed by the caller-supplied `MCPServerRegistry` and
  `activeServerIds` binding.
- **Storage**: In-memory only, for the view model's lifetime
  (`availableServerIds`, `serverNames`, `activeServerIds`); this file writes
  nothing to disk, `UserDefaults`, or any other persistent store. Any
  persistence of server configuration is `MCPServerRegistry`'s
  responsibility, outside this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source; connecting to a configured MCP server is `MCPServerRegistry`'s/
  `MCPClient`'s responsibility, not this file's.
- **Retention**: None beyond the hosting `NSView`'s and view model's
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
  The app's `\.theme` environment value is applied to that content via the
  shared `.themedRoot()` helper (once on `MCPChipsBar`'s root, and again on
  `MCPServerPicker` inside the popover, since a popover is its own window —
  see **reapplies-theme-inside-popover**); the view model retains its
  `registry.$clients` subscription in a `Set<AnyCancellable>` property for
  its lifetime. There is no UIKit code path in source; a UIKit port would
  keep the SwiftUI content but host it with `UIHostingController`, replace
  the `.popover` with a `UIPopoverPresentationController` (iPad) or a sheet
  (iPhone) — and, since Toggle rows have no fixed height in source, would
  need to give each row at least a 44pt touch target, since AppKit's
  `.checkbox` toggle style carries no such minimum.
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

## Design Decisions

**Decision**: Read `activeServerIds.wrappedValue` once at construction into
the view model's own `@Published activeServerIds`, rather than observing
the binding for later external changes.
**Rationale**: Traceable to `MCPChipsBarViewModel.init`, which assigns
`self.activeServerIds = activeServerIds.wrappedValue` with no Combine
subscription on the binding's source; only `toggle(_:)` ever updates the
binding afterward (one-way, out). This keeps the model's published state
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
**Rationale**: Per the inline source comment, "A popover is its own window,
so it is outside this view's environment and needs the palette injected
again." Reapplying it is a workaround for a limitation in how this app's
custom `\.theme` environment value propagates into `NSPopover`-backed
content, not a change in visual intent between the bar and the picker.
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
