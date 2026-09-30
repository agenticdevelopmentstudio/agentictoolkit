<!-- leaf: implement-composable-tabs/active-pane--part-3 · source: composable-tabs-active-pane.md -->

# ComposableTabsActivePane — continued (part 3)

**Rules** (cite as `implement-composable-tabs/active-pane--part-3#<slug>`):

- `an-attached-sheet-counts-the-window-as-focused` MUST
- `a-theme-override-takes-precedence-over-the-user-setting` MUST
- `the-fill-is-inset-from-the-backdrop-edges` MUST
- `the-fill-is-the-first-subview` MUST
- `a-window-change-reports-departure-before-arrival` MUST
- `the-backdrop-repaints-on-its-own-windows-activation-change` MUST
- `the-backdrop-repaints-on-any-key-window-change` MUST
- `the-backdrop-repaints-on-a-highlight-setting-change` MUST

- **an-attached-sheet-counts-the-window-as-focused**: `applyTheme(_:)` MUST
  treat the pane's window as focused when that window's attached sheet is the
  key window, even when the window itself is not key.
- **a-theme-override-takes-precedence-over-the-user-setting**: `applyTheme(_:)`
  MUST use the current theme's `project.highlightActivePane` override when the
  theme sets one, and MUST fall back to `UserSettings.highlightActivePane`
  only when the theme does not.
- **the-fill-is-inset-from-the-backdrop-edges**: The pane's fill subview MUST
  be constrained on all four edges to `ComposableTabsPaneBackgroundView.borderInset`
  (2 points) inside the backdrop's own bounds.
- **the-fill-is-the-first-subview**: The fill subview MUST be added to the
  backdrop before any other subview, so chrome added later renders above it.
- **a-window-change-reports-departure-before-arrival**: `viewDidMoveToWindow()`
  MUST report the backdrop's departure from its previous window, when it had
  one and it differs from the new one, before reporting its arrival in the
  new window.
- **the-backdrop-repaints-on-its-own-windows-activation-change**: The backdrop
  MUST reapply its theme when `didChangeNotification` is posted with its own
  window as the object, and MUST ignore that notification for any other
  window.
- **the-backdrop-repaints-on-any-key-window-change**: The backdrop MUST
  reapply its theme whenever any window becomes or resigns key, not only its
  own.
- **the-backdrop-repaints-on-a-highlight-setting-change**: The backdrop MUST
  reapply its theme when `UserSettings` publishes a change to
  `highlightActivePane`.
## Appearance

- **Corner radius**: None. The backdrop is a plain rectangular `NSView` layer
  with no `cornerRadius` set.
- **Padding**: Not applicable in the padding sense; the backdrop's fill
  subview is inset from the backdrop's own edges by `borderInset` (2pt) on
  all four sides, leaving that band for the border to draw in.
- **Font**: Not applicable. The component draws no text.
- **Background**: `palette.projectPaneBackdrop` (a theme-overridable role,
  falling back to the `elevatedSurface` role when the theme sets no
  `project.paneBackdrop` override — see `SemanticPalette.projectPaneBackdrop`)
  on the backdrop's layer; the fill subview inside it is a
  `ThemedBackgroundView` painted with the `.windowBackground` role.
- **Foreground/Text**: Not applicable. The component draws no text or icon.
- **Border**: 2 points wide on every pane, always. Color is
  `palette.projectActivePaneOutline` for the active pane in a focused window
  with highlighting enabled, and `palette.projectPaneOutline` otherwise.
- **Shadow**: None. The source sets no shadow on the backdrop's layer.
- **Min/Max size**: None imposed by this file. The backdrop is sized by its
  pane's own layout (auto-layout constraints applied by the surrounding pane
  view controller, not by this file).

## Accessibility

- **Role/traits**: Not applicable. `ComposableTabsPaneBackgroundView` sets no
  `accessibilityRole`, `accessibilityLabel`, or `accessibilityElement` value
  of its own anywhere in the source — it is a backdrop, not a control. Any
  role or label a pane's actual content needs belongs to that content's own
  view controller, which is out of scope for this file (see Overview).
- **Keyboard/assistive-technology navigation**: This is the file's central
  accessibility-relevant behavior. Every pointer-driven pane switch (gated by
  `activePaneFollowsMouse`) is paired with an ordinary `NSResponder`
  first-responder change, using the same `makeFirstResponder` mechanism a
  click already uses (see **mouse-moved-takes-focus-before-activating**,
  **focus-walk-proceeds-innermost-to-outermost**, and
  **focus-refusal-blocks-mouse-moved-activation**). Because focus moves
  through the standard responder chain rather than a private mechanism,
  VoiceOver's own focus-follows-first-responder behavior applies without
  anything further from this file; the component defines no separate
  accessibility-notification call of its own (no
  `NSAccessibility.post(element:notification:)` appears anywhere in the
  source), and none is required, because the underlying focus change is
  already the standard, observable one.
- **Minimum tap target**: Not applicable. `ComposableTabsPaneBackgroundView`
  is a full-bleed backdrop sized by its enclosing pane's own layout; it is
  not a discrete tappable control with an independently sized hit target, and
  the source treats it as neither a button nor a control.
- **contrast**: NEEDS REVIEW: Not implemented in source. `palette.projectPaneBackdrop`, `palette.projectPaneOutline`, and `palette.projectActivePaneOutline` are theme-overridable roles whose actual color values are chosen per theme (see the Theme Editor's Project topic, `ThemeProjectTopicPanel`), not fixed in this source file, so the contrast between the active border and its adjacent backdrop cannot be computed from `ComposableTabsActivePane.swift` alone; resolvable only by whoever audits each shipped theme's actual token values against a numeric contrast threshold (e.g. WCAG 1.4.11 non-text contrast, 3:1) for this border-against-backdrop pairing.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `UserSettings.activePaneFollowsMouse` | `UserSetting<Bool>` | `false` | Whether pointer movement, not just clicks, can change the active pane and hand it the keyboard. |
| `UserSettings.highlightActivePane` | `UserSetting<Bool>` | `true` | Whether the active pane's border is drawn in the accent color at all, unless overridden per theme. |
| Theme's `project.highlightActivePane` | `Bool?` (per-theme override) | `nil` (falls through to `UserSettings.highlightActivePane`) | A theme's own override of the same highlight toggle, edited in the Theme Editor's Project topic. |
| `ComposableTabsPaneBackgroundView.borderInset` | `CGFloat` (public static constant) | `2` | How far the pane's own fill is held off the backdrop's edge, in points, leaving room for the border. |

## Accessibility Options

- **Reduce Motion**: Not applicable — `applyTheme(_:)` sets colors directly
  with no animation or transition of any kind; there is no motion for this
  setting to reduce.
- **Increase Contrast**: Not applicable in the sense of a distinct code path
  — the component performs no Increase-Contrast-specific branching of its
  own; all color comes from theme tokens whose values are outside this file
  (see Accessibility > the open question on contrast).
- **Differentiate Without Color**: The active/inactive distinction is
  conveyed by outline color alone (`projectActivePaneOutline` vs.
  `projectPaneOutline`); the source defines no secondary, non-color cue
  (outline width, an icon, a pattern, a label) and does not read the
  Differentiate Without Color setting. A non-color cue, if one is added, is
  a change to `applyTheme(_:)`'s drawing, not to the tracking logic this
  ingredient otherwise specifies.

## Privacy

- **Data collected**: No user content. The only data held is each open
  window's currently active pane `UUID` — a value assigned by the pane's own
  view controller when it is created, not derived from anything the user
  types or enters.
- **Storage**: In-memory only, in three private collections
  (`activeByWindow`, `paneWindows`, `paneViews`) that live only as long as
  the app process; nothing in this file writes to disk, `UserDefaults`, or
  any database.
- **Transmission**: None. Nothing in this file makes a network call or
  passes its state outside the process.
- **Retention**: A window's active-id entry is removed when its active pane
  departs with no survivor (**departure-clears-active-id-when-no-pane-survives**)
  or when the window closes (**window-close-clears-active-id-silently**).
  Nothing here is persisted across an app relaunch — which pane a window was
  last active in is not restored automatically by this component.

