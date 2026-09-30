<!-- leaf: implement-ai/chat-bubble-view--test-vectors · source: ai-chat-bubble-view.md -->

# AIChatBubbleView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| chat-bubble-001 | corner-radius-by-style | `style = .speaker` | `layer.cornerRadius == 12` |
| chat-bubble-002 | corner-radius-by-style | `style = .terminal` | `layer.cornerRadius == 6` |
| chat-bubble-003 | role-based-fill-and-text | `style = .speaker`, `role = .user` | Fill uses `userBubble`, text uses `userText` |
| chat-bubble-004 | role-based-fill-and-text | `style = .speaker`, `role = .assistant` | Fill uses `personaBubble`, text uses `personaText` |
| chat-bubble-005 | role-based-fill-and-text | `style = .speaker`, `role = .error` | Fill is danger color at 8% alpha; text is danger color |
| chat-bubble-006 | role-based-fill-and-text | `style = .speaker`, `role = .notice` | Fill is secondary-text color at 10% alpha; text is secondary-text color |
| chat-bubble-007 | terminal-style-role-fill-override | `style = .terminal`, `role = .user` | Fill equals the palette's `surface` color; border equals the palette's `border` color, not `userBubble`/`userBubbleBorder` |
| chat-bubble-008 | terminal-style-role-fill-override | `style = .terminal`, `role = .assistant` | Fill and border identical to chat-bubble-007's result |
| chat-bubble-009 | work-output-text-dimmed | `role = .assistant`, `isWorkOutput = true`, `style = .speaker` | Text color is `secondaryText`, not `personaText` |
| chat-bubble-010 | work-output-text-dimmed | `role = .assistant`, `isWorkOutput = true`, `style = .terminal` | Text color is `secondaryText`, not the palette's plain `primaryText` |
| chat-bubble-011 | work-output-text-dimmed | `role = .user`, `isWorkOutput = true` | Text color is `userText` — `isWorkOutput` has no effect for `.user` |
| chat-bubble-012 | themed-border-opt-in | `style = .speaker`, `role = .assistant`, theme overrides `personaBubbleBorder` | 1pt border in the overridden color renders |
| chat-bubble-013 | themed-border-opt-in | `style = .speaker`, `role = .assistant`, theme does not override `personaBubbleBorder` | No border renders, even though the role still resolves to a derived color |
| chat-bubble-014 | error-notice-fixed-borders | `role = .error` | 1pt danger-color border renders regardless of theme declarations |
| chat-bubble-015 | error-notice-fixed-borders | `role = .notice` | No border renders |
| chat-bubble-016 | terminal-font-for-text-and-timestamp | Any role/style, `showsInlineTimestamp = true`, default settings | Message text renders in Menlo-Regular at 13pt; the timestamp renders in Menlo-Regular at (scaled) 11pt; neither uses the theme's general body font |
| chat-bubble-017 | inline-timestamp-format | `timestamp` = 2026-09-23T09:05:00, `showsInlineTimestamp = true`, `locale = en_US_POSIX` | Appended text reads `9:05 AM` (unpadded hour) |
| chat-bubble-018 | inline-timestamp-format | `timestamp` = 2026-09-23T14:30:00, `locale = en_US_POSIX` | Appended text reads `2:30 PM` |
| chat-bubble-019 | inline-timestamp-optional | `showsInlineTimestamp = false` | No timestamp text appears anywhere in the rendered string |
| chat-bubble-020 | timestamp-font-scaling | Default typography (caption 11pt / body 13pt), message font at 13pt | Timestamp font point size is exactly 11pt (`13 * (11/13)`) |
| chat-bubble-021 | timestamp-font-scaling | Theme's general body text size resolves to 0 | Timestamp renders in the unscaled message-text font |
| chat-bubble-022 | timestamp-color-token | Any role | Timestamp color is `timestampText`, independent of the surrounding text color |
| chat-bubble-023 | line-limit-truncation | `lineLimit = 3`, text lays out to 6 lines, `isExpanded = false` | Displayed text is the first 3 lines, trimmed of trailing whitespace, ending in "…" |
| chat-bubble-024 | truncation-suppressed-when-not-needed | `lineLimit = 3`, text lays out to 2 lines | Full text renders, no ellipsis |
| chat-bubble-025 | truncation-suppressed-when-not-needed | `lineLimit = 3`, text lays out to 6 lines, `isExpanded = true` | Full text renders, no ellipsis |
| chat-bubble-026 | truncation-suppressed-when-not-needed | `lineLimit = nil`, text lays out to 20 lines | Full text renders, no ellipsis, no toggle |
| chat-bubble-027 | expand-toggle-visibility | `lineLimit = 3`, text lays out to 6 lines | Toggle is visible (`isHidden == false`) |
| chat-bubble-028 | expand-toggle-visibility | `lineLimit = 3`, text lays out to 3 lines | Toggle is hidden |
| chat-bubble-029 | expand-toggle-icon-and-label | `isExpandable = true`, `isExpanded = false` | Toggle shows `chevron.down.circle.fill`, label/tooltip "Show the whole message", tint equals bubble text color |
| chat-bubble-030 | expand-toggle-icon-and-label | `isExpandable = true`, `isExpanded = true` | Toggle shows `chevron.up.circle.fill`, label/tooltip "Show less" |
| chat-bubble-031 | expand-toggle-invocation | Toggle activated, `onToggleExpanded` set | `onToggleExpanded` closure is called; `isExpanded` is unchanged by the component itself |
| chat-bubble-032 | expand-toggle-enablement | `onToggleExpanded = nil` | Toggle's `isEnabled == false` |
| chat-bubble-033 | expand-toggle-enablement | `onToggleExpanded` assigned a non-nil closure | Toggle's `isEnabled == true` |
| chat-bubble-034 | expanded-state-relayout | Palette already applied once; `isExpanded` flipped from `false` to `true` | Bubble re-measures and re-renders with the full text shown |
| chat-bubble-035 | expanded-state-relayout | No palette applied yet; `isExpanded` set at init time | No re-render occurs (nothing to re-apply) |
| chat-bubble-036 | bubble-width-bound-by-max-width | `maxWidth = 300`, short text, `fillsWidthWhenWrapped = false` | Bubble width equals measured content width + 24pt, and is ≤ 300 |
| chat-bubble-037 | fills-width-when-wrapped | `fillsWidthWhenWrapped = true`, text wraps to 3 lines, `maxWidth = 300` | Bubble width is exactly 300 |
| chat-bubble-038 | fills-width-when-wrapped | `fillsWidthWhenWrapped = true`, text does not wrap (1 line) | Bubble width equals measured content width + 24pt, not `maxWidth` |
| chat-bubble-039 | constraint-priority-relaxation-when-filling | `fillsWidthWhenWrapped = true` | `bubbleWidthConstraint.priority` and `textWidthConstraint.priority` both equal `.required - 1` |
| chat-bubble-040 | text-selectability | `isTextSelectable = true` | `textView.isSelectable == true` |
| chat-bubble-041 | text-selectability | `isTextSelectable = false` | `textView.isSelectable == false` |
| chat-bubble-042 | selection-and-cursor-colors | Palette applied | `selectedTextAttributes` background/foreground equal `selection`/`selectionText`; `insertionPointColor` equals `cursor` |
| chat-bubble-043 | double-click-interception | `onDoubleClick` set, double-click on bubble text | `onDoubleClick` is invoked; no word gets selected by the default double-click behavior |
| chat-bubble-044 | single-click-passthrough | `onSingleClick` set, single click on bubble text | `onSingleClick` is invoked, then a selection drag starts as usual on the text view |
| chat-bubble-045 | single-click-passthrough | `onDoubleClick = nil`, double-click on bubble text | `onSingleClick` is still invoked (the double-click short-circuit never triggers without a handler), then the text view's default double-click word-selection proceeds |
| chat-bubble-046 | single-click-passthrough | `isTextSelectable = true`, single click lands on the bubble's padding (outside the text view) | `onSingleClick` is invoked; the event is not forwarded to `super.mouseDown(_:)` |
| chat-bubble-047 | theme-change-reapplication | Bubble on screen, theme palette changes | Colors, fonts, and layout update in place on the same view instance |
