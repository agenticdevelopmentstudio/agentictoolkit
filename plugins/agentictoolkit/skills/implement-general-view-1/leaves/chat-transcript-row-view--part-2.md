<!-- leaf: implement-general-view-1/chat-transcript-row-view--part-2 · source: chat-transcript-row-view.md -->

# Chat Transcript Row View — continued (part 2)

## Accessibility

- **Role**: The row itself sets no explicit accessibility role or `isAccessibilityElement` value; it is a generic `NSView` container. Its subviews carry their own accessibility: the header (`headerView.setAccessibilityLabel(attribution.headerLine)`, `accessibilityID("chat-row.header")`) and the app icon (`accessibilityID("chat-row.jump")` always; a target, tooltip ("Go to this conversation" or "Go to this conversation in \(appIdentity)"), and accessibility label ("Go to \(attribution.headerLine)") only when `actions.onJump` is non-nil). The bubble's own accessibility is that component's concern — see `agentictoolkit://recipes/ai-chat-bubble-view`.
- **Label requirements**: See **icon-wired-only-when-jump-provided** and **renders-header-line** above; both header and (wired) icon carry meaningful labels traceable to `attribution.headerLine`.
- **Announce state changes**: Theme changes repaint live (**reflect-theme-live**); no other state change in this view posts an accessibility notification.
- **Minimum tap target**: The app icon is 28×28pt, short of the 44×44pt Apple default this ingredient's touch-target concern is measured against. The source's own comment explains the choice (see Design Decisions); whether 28pt is acceptable for this control is not something the source settles.
  - **minimum-tap-target**: NEEDS REVIEW: Not implemented in source. Whether the app icon's 28×28pt hit area is an acceptable deviation from the 44×44pt default, given it is a real, always-clickable-when-wired control (not decorative), is a design call the source does not make — `SessionHeaderView` constrains the icon button's width and height to exactly `spec.side` with no additional hit-area inset around the artwork, and the `PointingHandButton`/`InertIconButton` classes it uses have a cursor rect and tracking area that are both just `bounds`, so there is no existing padding technique in this codebase to reuse. Resolve by having the accessibility/design owner confirm whether 28pt is acceptable here or whether the icon's tappable area should be padded to 44×44pt independent of its 28×28pt artwork.
- **Keyboard path for the open gesture**: `open-on-double-click` is reachable only via a two-click mouse gesture; there is no `keyDown` override, no `accessibilityPerformPress`, and no other method in this file by which a keyboard or switch-control user can trigger the same action. The source's own doc comment says selecting a row via `onSelect` "gives the arrow keys, Return and Shift-Return something to act on," and the enclosing container confirms it: `ChatView.swift` (`packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/ChatView.swift`), which owns `Actions.onSelect`/`isSelected` when `isRowSelectionEnabled` is on, overrides `keyDown` and, on Return/Enter (`keyCode` 36 or 76) with a row selected, invokes `rowActions.onOpen?(message)` directly — the same callback this row's own double click invokes — with Shift-Return invoking `onJump` instead. A keyboard-only user does have an equivalent to `open-on-double-click`, supplied by that container rather than by this file, whenever the host wires row selection on.
- **Selection state announcement**: `isSelected` changes the row's visual border but posts no `NSAccessibility` notification and sets no accessibility "selected" trait; a screen reader user navigating the merged transcript by keyboard has no way to hear which row is currently selected, since selection is communicated only by that visual border.
- **Color dependence**: The Hovered state (see States) is communicated by a background fill alone, with no accompanying border or icon change; the Selected state adds a border shape in addition to (rather than instead of) color, so selection is not color-only, but hover is.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `message` | `ChatMessage` | (required) | The message this row displays; supplies role, attribution, delivery status, and timestamp |
| `maxBubbleWidth` | `CGFloat` | (required) | Upper bound passed to the embedded bubble and to the failure label's wrap width; callers typically derive this per-row via the static `maxBubbleWidth(forRowWidth:)` helper, but the initializer takes it as a plain parameter |
| `actions` | `Actions` | (required) | Bundle of the row's four interaction callbacks: `onOpen`, `onJump`, `onToggleExpanded`, `onSelect` |
| `lineLimit` | `Int?` | `nil` | How many lines of the message the bubble shows before truncating and offering to expand (forwarded to `AIChatBubbleView`) |
| `bubbleStyle` | `AIChatBubbleView.Style` | `.speaker` | Which shape the bubble is drawn in (forwarded to `AIChatBubbleView`; see its own recipe) |
| `isExpanded` | `Bool` | `false` | Whether the row starts out showing the whole message rather than truncated |

## Localization

The three user-facing strings in this file are hardcoded English literals with no override option today; the table lists them as built.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a (literal) | "Go to this conversation" | Tooltip on the app icon when `attribution.appIdentity` is empty |
| n/a (literal) | "Go to this conversation in {appIdentity}" | Tooltip on the app icon when `attribution.appIdentity` is non-empty |
| n/a (literal) | "Go to {attribution.headerLine}" | Accessibility label on the app icon, set only when `actions.onJump` is wired |

None of the three literals — the two app-icon tooltips or `setAccessibilityLabel("Go to \(attribution.headerLine)")` (`ChatTranscriptRowView.swift`–`343`) — is routed through `String(localized:)` or `NSLocalizedString`, so none reaches a string catalog.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: this file animates nothing of its own — the hover fill and selection border are set as instantaneous `CALayer` property writes, not `CABasicAnimation`s or `.animator()` proxies. The embedded `TypingIndicatorView`'s own animation is that component's concern; see `agentictoolkit://recipes/typing-indicator-view`. |
| Increase Contrast | Not implemented in source: this view sets no independent high-contrast styling. All colors (`.selection`, `.timestampText`, `.danger`) are read from the active `SemanticPalette`; whatever contrast increase that palette provides on request is inherited automatically, and this file does nothing further. |
| Differentiate Without Color | Selection is differentiated by shape (a border), not color alone (see Accessibility, "Color dependence"); hover is differentiated by color alone, with no accompanying shape or icon change — the source provides no alternative cue for hover. |

## Privacy

- **Data collected**: None. The view holds the `ChatMessage` and its `attribution` it was constructed with, purely to render them; it does not read, copy, or forward that data anywhere beyond drawing it and the caller-supplied `Actions` closures.
- **Storage**: None. All state (`message`, `attribution`, `isHovered`, `isSelected`) is held in memory only, for as long as the `NSView` instance exists.
- **Transmission**: None. This view performs no networking; whatever happens after `onOpen`/`onJump`/`onSelect` fire is the caller's responsibility.
- **Retention**: None beyond the view's own lifetime — the message data is released when the row view is deallocated or replaced.

