<!-- leaf: implement-panel/host-view--part-2 · source: panel-host-view.md -->

# PanelHostView — continued (part 2)

## Accessibility

- **Role/trait**: `PanelHostView` itself sets no accessibility role — it
  is a plain container `NSView` with default view semantics. The help
  button is a stock `NSButton`, exposed to assistive technology with
  AppKit's default push-button role; `PanelHostView.swift` does not
  override it.
- **Keyboard / assistive technology navigation**: Satisfied — see
  **help-button-keyboard-focusable**. `PanelHostView.swift` neither
  removes the help button from the key-view loop nor overrides
  `acceptsFirstResponder`, `keyDown`, or `performClick`, so Tab/Shift-Tab
  focus traversal and Space/Return activation remain exactly `NSButton`'s
  unmodified default behavior.
- **Label requirements**: Satisfied for the help button — its
  accessibility label is always the literal string `"Help"`
  (**help-button-accessibility-label-fixed**), and both symbol variants
  are constructed with `accessibilityDescription: "Help"`.
  `PanelHostView` sets no label on the content container; whatever
  content is installed via `setContent(_:)` is responsible for its own
  labeling.
- **Announce state changes (e.g., loading, disabled)**: Not satisfied.
  `updateHelpButton()` changes the button's image, `contentTintColor`, and
  `toolTip` when help is disclosed or dismissed, but the accessibility
  label stays the fixed string `"Help"` for both states, and no
  `NSAccessibility.post(element:notification:)` call appears anywhere in
  `PanelHostView.swift` — VoiceOver is told nothing beyond whatever
  AppKit's default image-change handling surfaces on its own.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. `contentTintColor` is set from `palette.accentColor` or `palette.secondaryTextColor` with neither color's contrast against whatever the button is drawn over computed or enforced in `PanelHostView.swift`; whether either color reaches WCAG AA's 3:1 non-text contrast minimum for every theme this component ships with depends on each theme's concrete color values and needs auditing per theme.
- **Minimum tap target**: Not applicable in the iOS 44×44pt sense —
  `PanelHostView` targets macOS only, where controls are pointer-operated,
  and Apple's Human Interface Guidelines do not set a single numeric
  minimum hit-target size for a pointer-driven AppKit control the way
  they do for an iOS touch target. The help button's actual click area is
  not set explicitly in source; it takes its size from `NSButton`'s
  default cell sizing for a borderless, image-only, momentary-change
  button showing a 15pt symbol, which `PanelHostView.swift` neither
  overrides nor measures.

## Configuration

`PanelHostView`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHostView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `helpPresenter` | `(any SettingsHelpPresenting)?` | `nil` | Where this view's help button opens and closes help, and reports visibility changes back. `nil` hides the help button entirely. |
| `showsHelpButton` | `Bool` | `true` | Whether this view draws its own `?` button. Set `false` for a window whose toolbar supplies help instead. |
| `onHelpVisibilityChange` | `(() -> Void)?` | `nil` | Callback fired after help is disclosed or dismissed, for chrome outside this view (e.g. a toolbar button) that needs to mirror the same state. |

```swift
public init()
public func setContent(_ view: NSView?)
public func setHelp(_ help: PanelHelp?)
public func toggleHelp()
public var isHelpVisible: Bool { get }
```

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (hardcoded literal, no key) | `Help` | Help button's accessibility label, set once in `configureHelpButton()` via `setAccessibilityLabel("Help")` |
| — (hardcoded literal, no key) | `Help` | Passed as `accessibilityDescription` to `NSImage(systemSymbolName:accessibilityDescription:)` for both help-button glyph variants |
| — (hardcoded literal, no key) | `Show Help` | Help button's `toolTip` while help is not visible |
| — (hardcoded literal, no key) | `Hide Help` | Help button's `toolTip` while help is visible |

All four strings above are set as plain `String` literals through AppKit
APIs (`setAccessibilityLabel`, `NSImage`'s `accessibilityDescription:`
parameter, and `toolTip`) — none of these is a SwiftUI
`Text`/`LocalizedStringKey` position, so a literal here is not
automatically localizable the way SwiftUI's is. No `NSLocalizedString`
call or string-catalog reference appears anywhere in `PanelHostView.swift`.

## Accessibility Options

- **Reduce Motion**: Not applicable — `PanelHostView.swift` contains no
  animation, transition, or `NSAnimationContext`/`CATransaction` call.
  Content swapping and help-button refresh are both synchronous property
  and subview assignments, not a motion effect.
- **Increase Contrast**: Not applicable in this file — the help button's
  colors come entirely from the active `SemanticPalette`
  (`accentColor`/`secondaryTextColor`); if Increase Contrast should raise
  either color's contrast, that is the palette/theme system's
  responsibility, not `PanelHostView`'s. Whether these colors reach an
  adequate ratio is the open question on minimum-contrast-ratio, tracked
  once under Accessibility above.
- **Differentiate Without Color**: Supported — the help-visible and
  help-hidden states are distinguished by both the button's symbol shape
  (`questionmark.circle.fill` vs. `questionmark.circle`) and its tint
  color (**help-button-icon-reflects-visibility**,
  **help-button-tint-reflects-visibility**), so color is never the sole
  signal.

## Privacy

- **Data collected**: None — `PanelHostView` holds only the `PanelHelp?`
  content and the presenter/content-view references handed to it by its
  caller; it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind. (Whether help-visibility is remembered across launches is decided
  by the assigned `helpPresenter`, e.g. `HelpDrawerController`'s
  `UserSettings`-backed preference — outside `PanelHostView.swift`.)
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: The currently installed content view and the most
  recently set `help` value are held in memory as private stored
  properties for the view's own lifetime, and are replaced (not appended
  to) on every subsequent `setContent(_:)`/`setHelp(_:)` call; nothing
  persists past deallocation.

