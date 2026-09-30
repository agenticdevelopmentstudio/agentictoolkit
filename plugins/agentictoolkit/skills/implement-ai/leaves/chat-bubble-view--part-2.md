<!-- leaf: implement-ai/chat-bubble-view--part-2 · source: ai-chat-bubble-view.md -->

# AIChatBubbleView — continued (part 2)

## Appearance

- **Corner radius**: 12pt in `.speaker` style; 6pt (`TerminalBoxStyle.cornerRadius`) in `.terminal` style
- **Padding**: 8pt vertical (top and bottom) × 12pt horizontal (leading and trailing) around the text; the expand toggle, when visible, sits an additional 2pt below the text
- **Font**: Message text and inline timestamp both use the app's resolved terminal font (default Menlo-Regular 13pt, themeable/user-configurable — see **terminal-font-for-text-and-timestamp**); the timestamp is scaled down from that font's point size by the theme's caption-to-body size ratio (11/13 ≈ 0.85 by default)
- **Background**: Role- and style-dependent fill. Default (undeclared-theme) fills: `.user` bubble is the window background blended 18% toward the accent color; `.assistant`/persona bubble is the window background blended 8% toward the foreground color; `.terminal`-style fill is the palette's `surface` color (background blended 6% toward foreground); `.error` is the danger color at 8% alpha; `.notice` is the secondary-text color at 10% alpha. A theme can override any named role (`userBubble`, `personaBubble`, `surface`, …) directly.
- **Foreground/Text**: Role- and style-dependent text color (`userText`/`personaText` resolve to the plain, undimmed foreground color by default), dimmed to `secondaryText` for assistant work output — see **work-output-text-dimmed**
- **Border**: 1pt when present. Default blends: `personaBubbleBorder` is background blended 16% toward foreground; `userBubbleBorder` is background blended 34% toward accent; the `.terminal` style's border is the palette's general `border` role (background blended 18% toward foreground). Themed for `.speaker` user/assistant roles (opt-in — see **themed-border-opt-in**), always present in the danger color for `.error`, never present for `.notice`; drawn at 1pt (`TerminalBoxStyle.borderWidth`) whenever any border is drawn
- **Shadow**: None. No shadow is set anywhere in the source.
- **Min/Max size**: Bubble width is capped at the caller-provided `maxWidth`; no minimum bubble width is enforced beyond whatever the (possibly empty) measured content and padding come to. The expand toggle, when visible, is a fixed 22×22pt; when hidden its height and width constraints collapse to 0.

## Accessibility

- **Role**: Generic `NSView` container; the source sets no custom accessibility role or `accessibilityElement` grouping on `AIChatBubbleView` itself.
- **Label**: The source sets no accessibility label on the bubble container. The message text reaches VoiceOver through the underlying `NSTextView`'s own default AppKit accessibility (an `NSTextView` exposes its string content automatically). The expand toggle is the only element the source labels explicitly: `setAccessibilityLabel` and the `NSImage`'s `accessibilityDescription` are both set to "Show the whole message" / "Show less" per **expand-toggle-icon-and-label**; it is also tagged with `accessibilityID("chat-bubble.more")` for UI-test identification, not for VoiceOver wording.
- **State announcement**: The toggle's label and icon swap when `isExpanded` changes, so VoiceOver reads the new label the next time it visits the button, but the source posts no explicit accessibility notification (no `NSAccessibility.post`) to announce the change proactively. No other state in this component (role, work-output dimming, border) is announced beyond what the color/text change itself implies.
- **Minimum tap target**: The 44×44pt minimum is an iOS/touch guideline; this is a macOS, pointer-driven control, where Apple's Human Interface Guidelines set no equivalent minimum. The expand toggle's actual click target is 22×22pt.
- **Color dependence**: In `.speaker` style, `.user` vs `.assistant` is distinguished only by the theme's bubble/text color roles — the component provides no non-color cue (icon, position, label) of its own. In `.terminal` style this is deliberate and total: per the `Style.terminal` doc comment, both conversational roles resolve to the *same* fill, text, and border, because the row that hosts a terminal-style bubble already states who is speaking in a header line above it; color is not how that style tells user from assistant.
- **Keyboard path (traced through the host)**: `AIChatBubbleView` itself has no keyboard path for `onSingleClick`/`onDoubleClick` — it overrides only `mouseDown(with:)` and does not override `acceptsFirstResponder` or any `keyDown(_:)` handling. In this component's actual usage, though, the gap is filled one level up: its host, `ChatView` (`packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/ChatView.swift`), overrides `acceptsFirstResponder` (`true` when row selection is enabled) and `keyDown(with:)` to move a row-level selection with the arrow keys, invoke the same action as a double-click open (`rowActions.onOpen`) on Return, jump to the source conversation on Shift-Return, and — via `handleSelectionLetter` — invoke the same open/jump/expand-toggle actions on the bare letters "c"/"g"/"m". `ChatTranscriptRowView` wires `bubble.onSingleClick` to row selection and `bubble.onDoubleClick` to the same `onOpen` action `ChatView`'s Return key invokes. So a keyboard-only user reaches equivalent behavior through the transcript's row selection, not through this view in isolation.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `message` | `ChatMessage` | required | The message to render: its `text`, `role`, `timestamp`, and `isWorkOutput` drive every other requirement above (`isStreaming` and `delivery` are not read — see States) |
| `maxWidth` | `CGFloat` | required | The bubble's maximum width — see **bubble-width-bound-by-max-width** |
| `style` | `Style` (`.speaker` / `.terminal`) | `.speaker` | Which of the two visual shapes to draw — see **corner-radius-by-style**, **terminal-style-role-fill-override** |
| `showsInlineTimestamp` | `Bool` | `true` | Whether the formatted timestamp trails the text — see **inline-timestamp-optional** |
| `isTextSelectable` | `Bool` | `true` | Whether the message text can be selected/copied — see **text-selectability** |
| `lineLimit` | `Int?` | `nil` | Maximum lines shown before offering to expand; `nil` never truncates — see **line-limit-truncation** |
| `fillsWidthWhenWrapped` | `Bool` | `false` | Whether a bubble whose text wraps stretches to `maxWidth` rather than its measured width — see **fills-width-when-wrapped** |
| `isExpanded` | `Bool` | `false` | Whether the bubble starts already showing everything it holds — see **expanded-state-relayout** |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | "Show the whole message" | `expandTitle`, the toggle's label/tooltip when collapsed; a private `String` literal in `AIChatBubbleView.swift`, not sourced from a resource file |
| (none — hardcoded) | "Show less" | `collapseTitle`, the toggle's label/tooltip when expanded; same as above |
| (none — hardcoded) | "…" | `ellipsis`, appended after truncated text; same as above |

The two toggle titles are private `String` literals (`expandTitle`, `collapseTitle`) assigned directly to AppKit (`NSImage`'s `accessibilityDescription`, `setAccessibilityLabel`, and `toolTip`); the source never looks either one up in a string table, so both always render in English regardless of the user's locale.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source contains no animation. The toggle's icon/label swap and every layout change `apply(_:)` makes happen instantly. |
| Increase Contrast | Not implemented directly in this component: it always renders whatever color the palette resolves for a given role. The palette's dimmed text roles (`secondaryText`, `timestampText`) do enforce a minimum contrast floor against the window background (`dimmed(towards:by:minContrast:)`), but nothing in this file or the palette verifies contrast between a bubble's own paired fill and text color (e.g. `userText` against `userBubble`) — that pairing is only as good as the active theme's own choices. |
| Differentiate Without Color | Not implemented in source. In `.speaker` style, role is told apart by fill/text/border color alone, with no icon, label, or positional cue from this component. In `.terminal` style the two conversational roles are made to look identical on purpose (see **terminal-style-role-fill-override**), so there is no color distinction to differentiate from in the first place. |

