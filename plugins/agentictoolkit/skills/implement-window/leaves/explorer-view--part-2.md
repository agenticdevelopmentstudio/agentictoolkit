<!-- leaf: implement-window/explorer-view--part-2 · source: window-explorer-view.md -->

# WindowExplorerView — continued (part 2)

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
  button carries its own visible text as its label — see
  **refresh-button-label** for the refresh button.
- **refresh-button-label**: The refresh button is icon-only (`Image(systemName: "arrow.clockwise")`) and sets no explicit `.accessibilityLabel`; VoiceOver gets only the SF Symbol's implicit description plus `.help("Refresh window list")`, which SwiftUI exposes as a tooltip and accessibility hint, not as the label.
- Announce state changes: the loading, empty, and populated states are
  distinct view trees that SwiftUI swaps directly (no `Text`/state is kept
  visible across the transition); no `.accessibilityAddTraits`,
  UIAccessibility/NSAccessibility posting, or focus-move call accompanies
  any of these swaps, so a VoiceOver user gets no explicit announcement and
  no accessibility-focus change when a scan finishes (loading to
  list/empty).
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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `selectedWindowIDs` | `Binding<Set<UInt32>>` | required | The set of currently selected window ids; read and written by row and section-header toggles. |
| `excludeWindowIDs` | `Set<UInt32>` | `[]` | Window ids to omit entirely from the scan result. |
| `activeGroupID` | `UUID?` | `nil` | When set, identifies the context whose windows are togglable instead of disabled, and whose selections a scan never prunes. |
| `refreshNotification` | `Notification.Name?` | `nil` | When set, a posted notification with this name triggers a new scan. |
| `appState` (environment) | `SystemWindowContextsModel` | required `@EnvironmentObject` | Supplies `listAllWindows()`, per-window context ownership (`context(forWindowID:)`), and `settings.hiddenApps`. |
| `theme` (environment) | theme palette (`\.theme`) | required environment value | Supplies every font and color role the view draws with. |

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
`Text(window.title.isEmpty ? "(untitled)" : window.title)` resolves the
ternary to a `String`, so `Text` takes its verbatim `String` initializer and
the literal is never looked up as a localization key — as built, this
behavior is defined: the fallback always renders in English regardless of
the user's locale, and the source contains no branch to a second `Text`
view or `String(localized:)` wrapping that would localize it instead.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no custom animated transition (movement, scaling, sliding, zooming, or pulsing) is implemented anywhere in this file; the only motion is `ProgressView`'s system-rendered indeterminate spinner, which this view does not implement or control. |
| Increase Contrast | Not applicable at this layer for most colors: every color other than the context badge's `.blue` fallback is sourced from the shared theme palette (`theme.<role>`); contrast handling for those is a design-system-level concern this view does not decide, per `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages`. The context badge's `Color(hex: ctx.color) ?? .blue` fallback (see **window-context-badge**) is the one exception: it is a fixed system color outside the theme, so Increase Contrast has no effect on it. |
| Differentiate Without Color | Handled: the context badge pairs its color with the context's name as text, not color alone; the Accessibility banner pairs its warning tint with an exclamation-triangle icon and explanatory text; and every selection state is shown by the checkbox glyph itself, not by color. |

## Privacy

- **Data collected**: the view reads, but does not persist, information
  about currently running windows — application names, window titles
  (CoreGraphics and, where matched, Accessibility-enriched), point frames,
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

