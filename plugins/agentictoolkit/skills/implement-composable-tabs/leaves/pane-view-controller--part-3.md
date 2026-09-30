<!-- leaf: implement-composable-tabs/pane-view-controller--part-3 · source: composable-tabs-pane-view-controller.md -->

# ComposableTabsPaneViewController — continued (part 3)

**Rules** (cite as `implement-composable-tabs/pane-view-controller--part-3#<slug>`):

- `removal-notifies-content-teardown` MUST
- `state-owner-retargets-store` MUST
- `contains-first-responder-unloaded` MUST
- `contains-first-responder-hierarchy-walk` MUST
- `title-bar-bottom-constant` MUST

### Teardown & state

- **removal-notifies-content-teardown**: `paneWillBeRemoved()` MUST remove the arrange overlay and MUST notify content implementing the teardown capability that its content will be discarded.
- **state-owner-retargets-store**: Setting `stateOwnerNodeID` MUST retarget the pane's `ProjectPaneStateStore`'s `ownerNodeID` to the new value.
- **contains-first-responder-unloaded**: `containsFirstResponder` MUST report `false` without loading the pane's view when the view has not yet been loaded.
- **contains-first-responder-hierarchy-walk**: When the view is loaded, `containsFirstResponder` MUST report `true` exactly when the window's first responder is the pane's view or a descendant of it.
- **title-bar-bottom-constant**: `titleBarBottom` MUST equal the border inset (see **content-inset-matches-border**) plus the title bar's fixed 26pt height (28pt total).

### Appearance fact

- **active-pane-cue-is-color-only**: As built, the pane's backdrop distinguishes the active pane from an inactive one by border color alone (`projectActivePaneOutline` vs. `projectPaneOutline`), with a constant 2pt border width in both states. This describes the current implementation; it is not a constraint against adding a secondary cue — see Differentiate Without Color in Accessibility Options, which records that no such cue is implemented.

## Appearance

- **Corner radius**: None on the pane's own backdrop or title bar. The arrange-mode toolbar (`ComposableTabsArrangeOverlayView.buildToolbar`) uses an 8pt corner radius.
- **Padding**: Content and title bar are held off the container's edges by the border inset (`contentInset` = `ComposableTabsPaneBackgroundView.borderInset`, 2pt — see **content-inset-matches-border**). The arrange overlay is inset from the pane by that same border inset on every side. Inside the overlay's toolbar, the button stack is inset 8pt on every side and the buttons are spaced 8pt apart; the pane-name label and the toolbar are stacked with 10pt spacing between them.
- **Font**: Not set directly in this file. The overlay's pane-name label uses `ThemedLabel(role: .primaryText, textRole: .heading)` — a semantic heading style resolved by the theme system, not a literal point size.
- **Background**: The pane's own fill is `ThemedBackgroundView(role: .windowBackground)`, drawn inside `ComposableTabsPaneBackgroundView`. While arranging, the scrim's background is `windowBackground` at 72% alpha (dims content toward the window background rather than toward black, so a light theme stays light); the toolbar's background is the `elevatedSurface` semantic color.
- **Foreground/Text**: The overlay's pane-name label uses the `primaryText` semantic role. Border colors are theme-resolved semantic tokens, not literal values: `projectActivePaneOutline` for the active pane, `projectPaneOutline` otherwise.
- **Border**: The pane backdrop draws a constant 2pt border (`layer.borderWidth = 2`) on every pane, colored per the active-pane rule above. The arrange toolbar draws a 1pt border in the `border` semantic color.
- **Shadow**: None. No shadow is drawn on the container, the arrange overlay, or its toolbar anywhere in these sources.
- **Min/Max size**: The overlay's pane-name label is constrained to at most (overlay width − 16pt), so a long name is clipped rather than widening the pane. No other min/max size is set by this file; the pane's own bounds are governed by the enclosing split, which is out of scope here.

## Accessibility

- **Role/trait**: The container view carries an accessibility identifier equal to `paneAccessibilityIdentifier` (set by the base class's `loadView()`); it is a plain `NSView` with no explicit AX role override in this file. The gear's "Move" menu item carries the identifier `pane.options.move`; each of its four submenu items carries `pane.options.move.<direction-name-lowercased>` (`left`, `right`, `up`, `down`). The arrange overlay's own controls (`composable-tabs.arrange.*`) are identified inside `ComposableTabsArrangeOverlayView`, which this class installs but does not itself label.
- **Label requirements**: Each move-menu item's image carries `accessibilityDescription` equal to the direction's movement name ("Left", "Right", "Up", "Down"), from `ComposableTabsMoveMenu.makeItems`. The overlay's Add/Remove/Done buttons carry `accessibilityDescription`s equal to their titles ("Add", "Remove", "Done"), from `ComposableTabsArrangeOverlayView.makeButton`. The gear button's own "Pane Options" label is set by the inherited `PaneViewController`, not by this subclass.
- **Announce state changes**: The only explicit state-change announcement this component performs is `RefusalFeedback.announce()` (default: a system beep) on every refused action — a blocked move, an Add with no choices, a Remove that is not currently legal. Neither an active-pane change (`ComposableTabsActivePane.activate(nodeID:in:)`) nor arrange mode turning on or off posts an `NSAccessibility` notification (e.g. `.layoutChanged` or an announcement), so a VoiceOver user has no non-visual cue that the active pane changed or that arrange mode started or stopped.
- **Minimum tap target**: Not overridden in this file. The gear button and the overlay's Add/Remove/Move/Done buttons are standard `NSButton`s with a `.rounded` bezel, sized by AppKit's intrinsic content size; macOS's pointer-driven HIG does not carry the 44×44pt minimum that applies to iOS touch targets, and this source sets no explicit minimum of its own.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewID` | `ComposableTabsViewID` | required at init | Which registered content kind this pane hosts. |
| `paneNumber` | `Int` | required at init | Identifying number passed through to the registry when building content. |
| `workingDirectory` | `URL` | required at init | The directory this pane's content is rooted in; shared by every pane in the same split tree. |
| `layoutOverride` | `ComposableTabsLayout?` | `nil` | Overrides the project's own layout (and its registry) when resolving this pane's content and display name; set by the enclosing split when it is itself overridden, e.g. a pane nested inside another pane's tree. |
| `stateOwnerNodeID` | `UUID?` | `nil` | Redirects the pane's persisted chrome state to another layout node's row family, for a pane nested inside another pane's content. |
| `thicknessFraction` | `CGFloat?` | `nil` | The fraction of the enclosing split's thickness this pane should occupy; read by the enclosing split, not consulted within this file. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal string) | "Move" | Title of the gear-menu submenu built by `makeMenuItems()`. |
| (none — literal string) | "Left" / "Right" / "Up" / "Down" | Move-submenu item titles and `accessibilityDescription`s, from `Direction.movementName`. |
| (none — literal string) | "Add" / "Remove" / "Done" | Arrange-overlay button titles and `accessibilityDescription`s. |
| (none — literal string) | "Remove this pane?" | Confirmation alert title in `confirmAndRemove()`. |
| (none — literal string) | "Remove" / "Cancel" | Confirmation alert button titles. |

No localization key or `String(localized:)`/`.strings`-catalog mechanism exists for any user-facing string in this file or its `ComposableTabsMoveMenu` / `ComposableTabsArrangeOverlayView` collaborators — every string above is a hardcoded English literal.

## Accessibility Options

Document which accessibility display options this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: overlay install/removal and content dim/undim are immediate `NSView` add/remove calls; no `NSAnimationContext`, layer animation, or transition appears anywhere in this file. |
| Increase Contrast | Not observed in this file: pane border and fill colors are resolved through `SemanticPalette`/theme lookup (e.g. `NSColor(palette.projectActivePaneOutline)`), so any contrast adaptation belongs to the theme system, out of this ingredient's scope. |
| Differentiate Without Color | Not implemented: the active/inactive distinction is carried by border color alone (`projectActivePaneOutline` vs. `projectPaneOutline`; see the `active-pane-cue-is-color-only` requirement), with no accompanying change in border width, shape, or label, and the source never queries `NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor`. |

## Privacy

- **Data collected**: This subclass introduces no new data collection. It contributes the pane's chrome state (minimize edge, zoomed flag — persisted by the inherited `PaneViewController`) and, when `stateOwnerNodeID` is set, redirects which layout node that state is attributed to. No personal or sensitive data is read or written by this file.
- **Storage**: Local only, via the project's own database, through `ProjectWorkspace`/`ProjectPaneStateStore`. This file holds no storage of its own.
- **Transmission**: None. No network call appears anywhere in this file or its immediate collaborators.
- **Retention**: Tied to the owning layout node's lifetime — `ProjectPaneStateStore` documents that a sweep deletes every `pane_state` row whose `node_id` is no longer a layout node, so a closed pane's (or its owner's) state is deleted with it; this class does not manage that lifetime itself.

