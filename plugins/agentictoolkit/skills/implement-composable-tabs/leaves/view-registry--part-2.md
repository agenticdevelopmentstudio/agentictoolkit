<!-- leaf: implement-composable-tabs/view-registry--part-2 · source: composable-tabs-view-registry.md -->

# ComposableTabsViewRegistry — continued (part 2)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `displayName` | `String` | (required) | What the Split menu calls this view. |
| `symbolName` | `String?` | `nil` | Optional SF Symbol shown alongside menu items for this view. |
| `preferredAxis` | `ComposableTabsAxis` | `.horizontal` | The axis the Split menu proposes first for a new pane of this kind; does not forbid the other axis. |
| `minimumThickness` | `CGFloat` | `120` | Minimum width or height of the pane, in points. |
| `preferredThicknessFraction` | `CGFloat?` | `nil` | Share of the enclosing split this pane asks for on first layout; `nil` divides evenly. |
| `isCollapsible` | `Bool` | `false` | Whether AppKit may collapse the pane to nothing. |
| `holdingPriority` | `NSLayoutConstraint.Priority?` | `nil` | Explicit resize-resistance priority; `nil` derives it via `resolvedHoldingPriority`. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — inline string literal) | `Pane \(paneNumber)` | `PlaceholderPaneViewController`'s title, shown for `.placeholder` and for any unregistered view id. |
| (none — inline string literal) | "Placeholder" | `ComposableTabsViewDescriptor.placeholder.displayName`, the name the Split menu shows. |
| (none — inline string literal) | "Unknown" | `ComposableTabsViewDescriptor.unknown.displayName`, shown for an unregistered view id. |

The source contains no localization mechanism for this string — no
`NSLocalizedString`, string catalog lookup, or similar — so it renders as the
literal English text "Pane N" regardless of the device's locale.

`"Pane \(paneNumber)"` (ComposableTabsViewRegistry.swift) and the
`"Placeholder"`/`"Unknown"` display names (:114, :118) are plain `String`
literals, none routed through `String(localized:)` or `NSLocalizedString`,
so none reaches a string catalog.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the placeholder's tint and layout are set once, synchronously, with no animation or transition; there is no motion for this setting to reduce. |
| Increase Contrast | Not applicable as a distinct code path: the source performs no Increase-Contrast-specific branching of its own; all color comes from theme tokens whose actual values live outside this file (see Accessibility > Contrast). |
| Differentiate Without Color | Satisfied without a marker: each placeholder's identity is not conveyed by tint color alone — its title label always shows the pane's number, which is the primary identifying cue; the color tint is a secondary reinforcement, per **placeholder-pane-number** and **placeholder-series-tint**. |

## Privacy

- **Data collected**: None. The registry holds only in-process configuration
  (descriptors and factory closures) supplied by the app itself, and the
  placeholder displays only a pane number computed by its caller — no user
  content or identifier.
- **Storage**: In-memory only, in the registry's private `entries` dictionary,
  for the life of the registry instance; nothing in this file writes to disk,
  `UserDefaults`, or a database.
- **Transmission**: None. Nothing in this file makes a network call or sends
  its state outside the process.
- **Retention**: Entries live only as long as the registry instance that
  holds them (per project, per `ComposableTabsLayout`); nothing here persists
  across a relaunch.

## Platform Notes

- **SwiftUI**: There is no `NSViewController`-returning factory pattern in
  SwiftUI; model the registry as a small `@MainActor` class holding
  `[ComposableTabsViewID: (ComposableTabsViewDescriptor, (ComposableTabsViewContext) -> AnyView)]`
  and expose it via `.environmentObject` or an `@Environment` key, so a pane
  host resolves content with `registry.makeContent(for:context:)` returning
  `AnyView` instead of a view controller. The placeholder becomes a plain
  `View`: a `ZStack` with a `.background(color.opacity(0.15))` modifier and a
  centered `Text("Pane \(paneNumber)")` with its font resolved from the
  environment's theme — `.font(theme.font(for: .heading))`, read via an
  `@Environment` theme key — never a hardcoded `.font(.title)`, so it stays
  the SwiftUI analogue of the source's theme-token-only `.heading` role;
  retinting happens automatically when the environment's theme value changes
  rather than through an explicit `observeTheme` call.
- **Compose**: Hold the registry as a plain Kotlin class mapping a view id to
  a descriptor plus a `@Composable (ComposableTabsViewContext) -> Unit`
  factory (Compose has no view-controller-owning-child concept, so a
  composable function fills the factory's role directly). The placeholder
  becomes a `Box(Modifier.fillMaxSize().background(seriesColor.copy(alpha = 0.15f)))`
  with a centered `Text("Pane $paneNumber", style = MaterialTheme.typography.headlineSmall)`;
  teardown moves from an adopted protocol to a `DisposableEffect`'s `onDispose`
  block on the pane's composable, and confirmation-before-removal becomes a
  plain nullable-string-returning function called before dismissal.
- **React/Web**: Model the registry as a plain object or `Map` from a string
  view id to `{ descriptor, factory }`, where `factory` is a component
  constructor or render function (a component registry / plugin-map pattern,
  common in extensible web apps). The placeholder becomes a functional
  component rendering a `div` sized by its flex/grid pane, with
  `backgroundColor` set to the series color at 15% alpha via CSS
  `color-mix()` or an rgba string, and a centered `<span>Pane {n}</span>`
  styled from the app's heading token; teardown maps to a `useEffect` cleanup
  function in place of `PaneContentTeardown`, and removal confirmation to a
  plain callback prop returning a string or `undefined`.
- **AppKit/UIKit**: This is the source platform; see
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsViewRegistry.swift`.
  It is macOS/AppKit-only: `NSViewController`, `NSColor`,
  `NSLayoutConstraint.Priority`, and the `Factory` typealias's `NSViewController`
  return type have no UIKit equivalent as written. A UIKit port would change
  `Factory` to return `UIViewController`, swap `NSColor` for `UIColor` and
  `NSLayoutConstraint.Priority` for `UILayoutPriority`, and would need its own
  container-view-controller embedding (`addChild`/`didMove(toParent:)`) in
  place of whatever AppKit-specific embedding `ComposableTabsPaneViewController`
  performs outside this file.
- **WinUI 3**: Model
  `ComposableTabsViewRegistry` as a C# class holding a
  `Dictionary<string, (ComposableTabsViewDescriptor Descriptor, Func<ComposableTabsViewContext, UserControl> Factory)>`
  (the `Factory` typealias becomes a `Func<...>` returning a `UserControl` or
  `Page`, since WinUI panes host XAML content rather than a
  `NSViewController`); `Register`, `Unregister` (refusing the placeholder key
  exactly as `placeholder-protection` requires), `RegisteredViewIds`
  (sorted with `OrderBy(id => id, StringComparer.Ordinal)`), `IsRegistered`,
  `Descriptor`, and `MakeContentView` mirror the six public members 1:1.
  `ComposableTabsViewDescriptor` becomes a C# record with `DisplayName`,
  `IconSource` (a `SymbolIconSource`/`FontIconSource` in place of an SF Symbol
  name), `PreferredAxis`, `MinimumThickness` (bound to a `GridSplitter`
  pane's `MinWidth`/`MinHeight`), `PreferredThicknessFraction` (mapped to a
  `GridLength` star value on the hosting `Grid.ColumnDefinitions`/`RowDefinitions`),
  `IsCollapsible`, and `HoldingPriority`; XAML's `Grid` has no holding-priority
  construct comparable to Auto Layout's, so `ResolvedHoldingPriority` has no
  direct WinUI analogue — the nearest equivalent is choosing which column gets
  a fixed `GridLength` versus a `*`-weighted one, which is a layout-time
  decision rather than a runtime priority value, and is the one part of this
  recipe with no 1:1 WinUI mapping. The placeholder becomes a `UserControl`
  with a `Border` whose `Background` is a `SolidColorBrush` built from the
  theme's chart-series brush resource at 15% `Opacity` (mirroring
  `withAlphaComponent(0.15)`), containing a `TextBlock`
  `HorizontalAlignment="Center" VerticalAlignment="Center"` bound via
  `x:Bind PaneNumber` and styled `Style="{StaticResource TitleTextBlockStyle}"`
  (the Fluent 2 analogue of the `.heading` `TextRole`); since the control has
  no interactive states, no `VisualStateGroup` beyond the default
  `CommonStates.Normal` is needed. Retinting on theme change replaces the
  source's `observeTheme` associated-object mechanism with `{ThemeResource}`
  brush bindings plus a handler on the app's own theme-store change event —
  the `observeTheme` analogue — rather than
  `FrameworkElement.ActualThemeChanged`, which only fires when the system
  switches between light and dark and would miss an in-app `SemanticPalette`
  theme change. Logging replaces `Loggable`/`OSLog` with
  `Microsoft.Extensions.Logging.ILogger<ComposableTabsViewRegistry>`, using
  the same category-equals-type-name convention.

