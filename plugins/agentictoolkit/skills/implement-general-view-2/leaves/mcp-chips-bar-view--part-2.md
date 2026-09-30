<!-- leaf: implement-general-view-2/mcp-chips-bar-view--part-2 · source: mcp-chips-bar-view.md -->

# MCPChipsBarView — continued (part 2)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `registry` | `MCPServerRegistry` | — (required) | Supplies the live `$clients` publisher this bar and its popover observe for the available-server list and names. |
| `activeServerIds` | `Binding<Set<UUID>>` | — (required) | Two-way link to the caller's active-server set. Its `wrappedValue` is read once, at construction, for the initial snapshot (see **snapshots-active-ids-at-init**), and is written to — never re-read — every time the user toggles a server. |

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
