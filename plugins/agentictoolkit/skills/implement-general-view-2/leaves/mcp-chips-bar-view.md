<!-- leaf: implement-general-view-2/mcp-chips-bar-view · source: mcp-chips-bar-view.md -->

**Rules** (cite as `implement-general-view-2/mcp-chips-bar-view#<slug>`):

- `hosts-swiftui-content` MUST
- `disables-autoresizing-mask` MUST
- `fills-parent-bounds` MUST
- `rejects-coder-initialization` MUST
- `shares-one-view-model-between-bar-and-picker` MUST
- `snapshots-active-ids-at-init` MUST
- `subscribes-to-registry-clients` MUST
- `sorts-available-servers-by-name` MUST
- `defaults-missing-name-to-empty-string-for-sort` MUST
- `rebuilds-server-names-on-update` MUST
- `reports-active-membership` MUST
- `toggles-membership-on-call` MUST
- `propagates-toggle-to-binding` MUST
- `renders-server-rack-icon` MUST
- `renders-toggle-button` MUST
- `computes-no-servers-label` MUST
- `computes-none-active-label` MUST
- `computes-count-active-label` MUST
- `uses-borderless-button-style` MUST
- `toggles-picker-on-tap` MUST
- `presents-popover-below-button` MUST
- `reapplies-theme-inside-popover` MUST
- `applies-bar-padding` MUST
- `trails-with-spacer` MUST
- `shows-picker-heading` MUST
- `shows-empty-state-message` MUST
- `lists-one-toggle-row-per-server` MUST
- `row-label-falls-back-to-unknown` MUST
- `row-toggle-reflects-active-state` MUST
- `row-toggle-calls-view-model-toggle` MUST
- `uses-checkbox-toggle-style` MUST
- `applies-picker-padding-and-min-width` MUST

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

