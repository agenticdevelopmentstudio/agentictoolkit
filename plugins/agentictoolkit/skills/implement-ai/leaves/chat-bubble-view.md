<!-- leaf: implement-ai/chat-bubble-view · source: ai-chat-bubble-view.md -->

**Rules** (cite as `implement-ai/chat-bubble-view#<slug>`):

- `corner-radius-by-style` MUST
- `role-based-fill-and-text` MUST
- `terminal-style-role-fill-override` MUST
- `work-output-text-dimmed` MUST
- `themed-border-opt-in` MUST
- `error-notice-fixed-borders` MUST
- `terminal-font-for-text-and-timestamp` MUST
- `inline-timestamp-format` MUST
- `inline-timestamp-optional` MUST
- `timestamp-font-scaling` MUST
- `timestamp-color-token` MUST
- `line-limit-truncation` MUST
- `truncation-suppressed-when-not-needed` MUST
- `expand-toggle-visibility` MUST
- `expand-toggle-icon-and-label` MUST
- `expand-toggle-invocation` MUST
- `expand-toggle-enablement` MUST
- `expanded-state-relayout` MUST
- `bubble-width-bound-by-max-width` MUST
- `fills-width-when-wrapped` MUST
- `constraint-priority-relaxation-when-filling` MUST
- `text-selectability` MUST
- `selection-and-cursor-colors` MUST
- `double-click-interception` MUST
- `single-click-passthrough` MUST
- `theme-change-reapplication` MUST

# AIChatBubbleView

## Overview

`AIChatBubbleView` is an `NSView` that renders a single chat message — its text and, optionally, a trailing timestamp — as a themed bubble. It supports two visual shapes chosen by the caller (`.speaker`, a rounded speech bubble colored by the message's role, and `.terminal`, a small-radius inset panel matching the Sessions window's output box), an optional per-message line limit with an expand/collapse toggle for long messages, selectable or non-selectable text, and single/double-click callbacks. It repaints itself in place whenever the observed theme palette changes. It is distinct from `AgenticDeveloperToolkit`'s `MessageBubbleView` (re-exported into this framework, under the same Swift type name, from `AgenticDeveloperToolkitUI` via `@_exported import`); it exists only inside this app's `AIChatWindow` feature, under a deliberately non-colliding name (`packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/AIChatBubbleView.swift`).

## Behavioral Requirements

- **corner-radius-by-style**: The component MUST apply a 12pt corner radius (`layer.cornerRadius`) when `style` is `.speaker`, and MUST apply a 6pt corner radius (`TerminalBoxStyle.cornerRadius`) when `style` is `.terminal`.
- **role-based-fill-and-text**: In `.speaker` style, the component MUST derive the bubble's fill and text color from `message.role`: `.user` MUST use the `userBubble` fill and `userText` text color; `.assistant` MUST use the `personaBubble` fill and `personaText` text color; `.error` MUST use the danger color at 8% alpha for fill and the danger color for text; `.notice` MUST use the secondary-text color at 10% alpha for fill and the secondary-text color for text.
- **terminal-style-role-fill-override**: When `style` is `.terminal` and `message.role` is `.user` or `.assistant`, the component MUST use the palette's `surface` color for the bubble's fill and its `border` color for the bubble's border, instead of the role-specific bubble/border roles, so the two conversational roles render identically in that style.
- **work-output-text-dimmed**: When `message.isWorkOutput` is `true` and `message.role` is `.assistant`, the component MUST render the message text in the palette's `secondaryText` color instead of the role's normal text color (`personaText` in `.speaker`, the palette's plain, undimmed `primaryText` in `.terminal`), in both styles.
- **themed-border-opt-in**: In `.speaker` style, for `.user` and `.assistant` roles, the component MUST apply a 1pt border in the theme's declared border role (`userBubbleBorder` / `personaBubbleBorder`) only when the active theme explicitly overrides that role (`palette.declares(role)`, i.e. the theme's `roleOverrides` dictionary contains an entry for it); it MUST NOT synthesize a border from that role's resolved color when the theme leaves the role to its default derivation.
- **error-notice-fixed-borders**: For `.error` role, the component MUST always render a 1pt border in the danger color, regardless of what the theme declares; for `.notice` role, it MUST NOT render a border.
- **terminal-font-for-text-and-timestamp**: The component MUST render the message text, and the inline timestamp when shown, in the font the app's terminal settings resolve to for the active theme (the theme's own terminal-font override if it has one, otherwise the Terminal settings panel's font — "Menlo-Regular" at 13pt by default, falling back to the system monospaced font at that size if the named font cannot be loaded), not the theme's general body-text font, in both `.speaker` and `.terminal` styles.
- **inline-timestamp-format**: When shown, the component MUST format the message's timestamp with the fixed pattern `h:mm a` (12-hour clock, unpadded hour, locale-supplied AM/PM text) and append it after the message text, separated by two spaces.
- **inline-timestamp-optional**: The component MUST append the formatted timestamp when `showsInlineTimestamp` is `true`, and MUST NOT render any timestamp when it is `false`.
- **timestamp-font-scaling**: When shown, the component MUST render the timestamp in a font built from the message-text font's descriptor at a size equal to that font's point size multiplied by the ratio of the theme's general caption text size to its general body text size (11pt/13pt by default, i.e. a ratio of about 0.85, independent of the terminal-font size the ratio is applied to), and MUST fall back to the unscaled message-text font when that body size is 0.
- **timestamp-color-token**: When shown, the component MUST render the timestamp in the palette's `timestampText` color, independent of the surrounding message text's color.
- **line-limit-truncation**: When `lineLimit` is non-nil and the message text, laid out at the bubble's text width, spans more lines than `lineLimit`, and the bubble is not expanded (`isExpanded == false`), the component MUST display only the first `lineLimit` lines of the text, trimmed back to the last non-whitespace character and followed by a single ellipsis character ("…").
- **truncation-suppressed-when-not-needed**: The component MUST display the full message text, with no ellipsis, when `lineLimit` is `nil`, when the laid-out line count is at or under `lineLimit`, or when `isExpanded` is `true`.
- **expand-toggle-visibility**: The component MUST show the expand/collapse toggle only when the message's laid-out line count, measured before any truncation, exceeds `lineLimit`, and MUST hide it otherwise, including whenever `lineLimit` is `nil`.
- **expand-toggle-icon-and-label**: The toggle MUST display the `chevron.down.circle.fill` symbol with the accessibility label and tooltip "Show the whole message" when `isExpanded` is `false`, and `chevron.up.circle.fill` with "Show less" when `isExpanded` is `true`, and MUST tint the icon with the bubble's own current text color.
- **expand-toggle-invocation**: Activating the toggle MUST invoke `onToggleExpanded`; the component itself MUST NOT change `isExpanded` when the toggle is activated.
- **expand-toggle-enablement**: The component MUST disable the toggle whenever `onToggleExpanded` is `nil`, and enable it whenever a non-nil handler is assigned.
- **expanded-state-relayout**: Setting `isExpanded` to a different value MUST re-apply the current theme palette — re-measuring and re-rendering the bubble — whenever a palette has already been applied at least once, and MUST have no visible effect if no palette has been applied yet.
- **bubble-width-bound-by-max-width**: The bubble's width MUST NOT exceed `maxWidth`; when `fillsWidthWhenWrapped` is `false`, or the text does not wrap to more than one line, the bubble's width MUST equal its measured content width plus 24pt of horizontal padding, capped at `maxWidth`.
- **fills-width-when-wrapped**: When `fillsWidthWhenWrapped` is `true` and the message text wraps to more than one laid-out line, the bubble's width MUST equal `maxWidth` exactly, rather than its measured content width.
- **constraint-priority-relaxation-when-filling**: When `fillsWidthWhenWrapped` is `true`, the component MUST set the bubble-width and text-width layout constraints to a priority one point below `.required`, rather than `.required`, so a host row narrower than `maxWidth` can override them without producing an unsatisfiable-constraint conflict.
- **text-selectability**: The component MUST make the message text selectable when `isTextSelectable` is `true`, and non-selectable when it is `false`.
- **selection-and-cursor-colors**: Whenever a palette is applied, the component MUST set the text view's selected-text background to the palette's `selection` color, its selected-text foreground to `selectionText`, and its insertion-point color to `cursor` — each of these three roles is an author-chosen theme color, not one algorithmically derived from the background/foreground pair the way the bubble fill/border roles are.
- **double-click-interception**: When `onDoubleClick` is set, a click with `clickCount >= 2` anywhere on the bubble, including its text, MUST invoke `onDoubleClick` and MUST NOT trigger the text view's default double-click word-selection.
- **single-click-passthrough**: A click not intercepted by **double-click-interception** (a single click, or a double click while `onDoubleClick` is `nil`) MUST invoke `onSingleClick` if one is set. On the text view itself, the component MUST then still perform the text view's own default mouse-down handling (starting a selection drag). For a click landing on the bubble's own padding (outside the text view) while `isTextSelectable` is `true`, the component MUST consume the event itself and MUST NOT forward it to `super.mouseDown(_:)`.
- **theme-change-reapplication**: The component MUST re-derive colors, fonts, measurements, and layout for the current message whenever the observed theme palette changes.

