<!-- leaf: implement-general-controller/pane-view-controller--part-3 · source: pane-view-controller.md -->

# PaneViewController — continued (part 3)

**Rules** (cite as `implement-general-controller/pane-view-controller--part-3#<slug>`):

- `minimize-edge-persisted` MUST
- `zoom-persisted` MUST
- `state-restored-on-load` MUST
- `unparseable-stored-edge-ignored` MUST
- `search-reaches-searchable-content-only` MUST
- `selection-description-reported` MUST
- `selection-change-forwarded` MUST
- `minimized-thickness-formula` MUST

### Persistence

- **minimize-edge-persisted**: `setMinimized(to:)` MUST write the edge's raw value to the state store under `PaneStateKey.minimizeEdge`, or delete that key when set to `nil`.
- **zoom-persisted**: `setZoomed(_:)` MUST write `"1"` to the state store under `PaneStateKey.zoomed` when `true`, or delete that key when `false`.
- **state-restored-on-load**: `viewDidLoad` MUST restore `minimizedEdge` and `isZoomed` from the state store via `restorePersistedState()`.
- **unparseable-stored-edge-ignored**: A stored minimize-edge value that does not match a `PaneEdge` raw value MUST be treated as absent — the pane opens whole — rather than crashing or raising an error.

### Search and selection

- **search-reaches-searchable-content-only**: `isSearchable` MUST be `true` exactly when the content implements `PaneSearchable`; `search(for:)` MUST forward to the content when searchable and MUST be a no-op otherwise.
- **selection-description-reported**: `selectionDescription` MUST equal `(contentViewController as? PaneSelectionDescribing)?.paneSelectionDescription`, or `nil` when the content does not implement the protocol.
- **selection-change-forwarded**: The pane MUST install its own closure into the content's `onPaneSelectionChange` (when implemented) and MUST call its own `onSelectionChange` whenever that fires.

### Sizing for the host

- **minimized-thickness-formula**: `minimizedThickness(for:)` MUST return `PaneMinimizedStripView.thickness + contentInset * 2` for a horizontal edge and `PaneTitleBarView.height + contentInset * 2` for a vertical edge.

## Appearance

- **Corner radius**: None drawn by this class. The default container, `ThemedBackgroundView(role: .windowBackground)`, is a plain rectangle; a subclass overriding `makeContainerView()` may add one, out of scope here.
- **Padding**: `contentInset` (default `0`pt) holds both the title bar and the content off the container's edges. The title bar is a fixed `PaneTitleBarView.height` = 26pt tall. A minimized-to-a-side rail is a fixed `PaneMinimizedStripView.thickness` = 28pt thick.
- **Font**: Not set directly in this file; the title bar's own label typography belongs to `PaneTitleBarView` (`depends-on`), out of this recipe's scope.
- **Background**: The pane's own fill is whatever `makeContainerView()` returns; the default is `ThemedBackgroundView(role: .windowBackground)`.
- **Foreground/Text**: Not set directly in this file; delegated to the title bar and to the content.
- **Border**: None drawn by this class anywhere in this file.
- **Shadow**: None drawn by this class anywhere in this file.
- **Min/Max size**: None set by this class. The container view is given an explicit `NSRect(x: 0, y: 0, width: 300, height: 200)` frame at `loadView()`, before Auto Layout resolves its real size from the constraints installed immediately after; no min/max width or height constraint is authored anywhere in this file.
- **Gear button**: Built by `WindowOptionsDialog.makeGearButton(tooltip: "Pane options")` — borderless, `.accessoryBarAction` bezel, the `gearshape` SF Symbol shown image-only, tinted with the theme's secondary-text color.

## Accessibility

- **Role/trait**: The container view carries the accessibility identifier `paneAccessibilityIdentifier` returns (`"pane"` by default), set by `loadView()`. It is a plain view with no explicit AX role override in this file. The gear button carries identifier `pane.options`; the "Settings…" menu item carries `pane.options.settings`; the spacing control carries `pane.options.spacing`; the spacing reset button carries `pane.options.spacing.reset`. The close/minimize/zoom buttons, the minimize picker, the minimized rail, and the options dialog's own controls carry their identifiers inside their own components, each with its own recipe (see `depends-on`/`related`) — out of scope here.
- **Label requirements**: The gear button's `accessibilityDescription` and `toolTip` are both "Pane options"; its accessibility label is set separately to "Pane Options". The "Settings…" menu item's image carries `accessibilityDescription`: "Settings". The spacing reset button's accessibility label is "Use Default Spacing", distinct from its visible title "Use Default".
- **Announce state changes**: No `NSAccessibility` notification is posted anywhere in this file when the title changes, when the pane minimizes, restores, or zooms — every one of those is a silent property assignment. A VoiceOver user has no non-visual cue that any of these four things happened.
- **Minimum tap target**: Not overridden in this file. The gear button and the spacing reset button are standard `NSButton`s sized by AppKit's intrinsic content size; macOS's pointer-driven HIG does not carry the 44×44pt minimum that applies to iOS touch targets, and this source sets no explicit minimum of its own.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stateStore` | `PaneStateStore` | `EphemeralPaneStateStore()` | Where the pane persists its minimize edge, zoomed flag, and spacing override; injected at construction. |
| `host` | `PaneHost?` (weak) | `nil` | The container the pane sends close/minimize/zoom/restore requests to and asks for available minimize edges and close permission. |
| `clampsToContainer` | `Bool` | `false` | When `true`, yields the title bar's — and any later-installed chrome's — width demand to the container instead of asking for its own; one-way once set. |
| `onSelectionChange` | `(() -> Void)?` | `nil` | Called when the content's selection description changes, for a host that shows a display path. |
| `onTitleChange` | `(() -> Void)?` | `nil` | Called when `resolvedTitle` would now answer differently, for a host that names the pane elsewhere (e.g. a window footer). |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal string) | "Pane" | `fallbackTitle`'s default value. |
| (none — literal string) | "Pane options" | Gear button's tooltip and `accessibilityDescription`. |
| (none — literal string) | "Pane Options" | Gear button's separately-set accessibility label. |
| (none — literal string) | "Settings…" | Title of the gear menu's final item. |
| (none — literal string) | "Settings" | `accessibilityDescription` on that item's image. |
| (none — literal string) | "Use Default" | Title of the spacing reset button. |
| (none — literal string) | "Use Default Spacing" | Accessibility label of the spacing reset button. |

This file is AppKit, not SwiftUI: every string above is set through a plain `String`-typed property (`toolTip`, `title`, `setAccessibilityLabel`, `accessibilityDescription`), none of which resolve against a `.strings` catalog or `NSLocalizedString` automatically. Every one is a hardcoded English literal with no localization key.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: every appearance change in this file — minimize, restore, zoom, clamping — is an immediate property assignment (`isHidden`, constraint activation/deactivation, image swap); no `NSAnimationContext`, layer animation, or transition appears anywhere in this file. |
| Increase Contrast | Not observed in this file: colors are resolved through the theme system (`ThemedBackgroundView`, and `WindowOptionsDialog.makeGearButton`'s `observeTheme` tinting); any contrast adaptation belongs to that system, out of this ingredient's scope. |
| Differentiate Without Color | Not applicable: this class draws no state distinction using color alone anywhere in this file. Its container's fill comes entirely from `makeContainerView()`, which a subclass with a color-only cue (e.g. an active/inactive border) may override — that is `ComposableTabsPaneViewController`'s concern, documented in its own recipe, not this one's. |

## Privacy

- **Data collected**: Only this pane's own chrome state — minimize edge, zoomed flag, and spacing override — written through the injected `PaneStateStore`. No personal or otherwise sensitive data is read or written by this file.
- **Storage**: Whatever the injected `PaneStateStore` implements. `EphemeralPaneStateStore`, the default, keeps values in memory only, for exactly as long as the pane exists. A persistent store is the caller's own choice and out of this recipe's scope.
- **Transmission**: None. No network call appears anywhere in this file.
- **Retention**: Governed entirely by whichever `PaneStateStore` is injected; this class defines no retention policy of its own.

