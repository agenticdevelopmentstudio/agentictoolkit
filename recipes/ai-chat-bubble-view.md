---
id: 24199c9b-53ce-41a7-9cce-3b914f0a424a
title: AIChatBubbleView
domain: agentictoolkit://recipes/ai-chat-bubble-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS chat message bubble with role/style-based theming, an optional inline
  timestamp, and line-limited truncation with an expand/collapse toggle.
platforms:
- swift
- macos
tags:
- chat
- messaging
- ui-component
depends-on: []
related:
- agentictoolkit://recipes/chat-day-banner-view
- agentictoolkit://recipes/chat-transcript-row-view
- agenticdevelopertoolkit://recipes/message-bubble
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

- **Corner radius**: 12pt in `.speaker` style; 6pt (`TerminalBoxStyle.cornerRadius`) in `.terminal` style
- **Padding**: 8pt vertical (top and bottom) × 12pt horizontal (leading and trailing) around the text; the expand toggle, when visible, sits an additional 2pt below the text
- **Font**: Message text and inline timestamp both use the app's resolved terminal font (default Menlo-Regular 13pt, themeable/user-configurable — see **terminal-font-for-text-and-timestamp**); the timestamp is scaled down from that font's point size by the theme's caption-to-body size ratio (11/13 ≈ 0.85 by default)
- **Background**: Role- and style-dependent fill. Default (undeclared-theme) fills: `.user` bubble is the window background blended 18% toward the accent color; `.assistant`/persona bubble is the window background blended 8% toward the foreground color; `.terminal`-style fill is the palette's `surface` color (background blended 6% toward foreground); `.error` is the danger color at 8% alpha; `.notice` is the secondary-text color at 10% alpha. A theme can override any named role (`userBubble`, `personaBubble`, `surface`, …) directly.
- **Foreground/Text**: Role- and style-dependent text color (`userText`/`personaText` resolve to the plain, undimmed foreground color by default), dimmed to `secondaryText` for assistant work output — see **work-output-text-dimmed**
- **Border**: 1pt when present. Default blends: `personaBubbleBorder` is background blended 16% toward foreground; `userBubbleBorder` is background blended 34% toward accent; the `.terminal` style's border is the palette's general `border` role (background blended 18% toward foreground). Themed for `.speaker` user/assistant roles (opt-in — see **themed-border-opt-in**), always present in the danger color for `.error`, never present for `.notice`; drawn at 1pt (`TerminalBoxStyle.borderWidth`) whenever any border is drawn
- **Shadow**: None. No shadow is set anywhere in the source.
- **Min/Max size**: Bubble width is capped at the caller-provided `maxWidth`; no minimum bubble width is enforced beyond whatever the (possibly empty) measured content and padding come to. The expand toggle, when visible, is a fixed 22×22pt; when hidden its height and width constraints collapse to 0.

## States

| State | Appearance change |
|-------|------------------|
| Default | Themed fill/text/border per role and style — see **role-based-fill-and-text**, **terminal-style-role-fill-override** |
| Assistant work output | Text color forced to `secondaryText` — see **work-output-text-dimmed** |
| Truncated (collapsed, over limit) | Text cut to `lineLimit` lines ending in "…"; expand toggle shown with the "Show the whole message" chevron — see **line-limit-truncation**, **expand-toggle-icon-and-label** |
| Expanded (over limit, `isExpanded == true`) | Full text shown; expand toggle shown with the "Show less" chevron — see **truncation-suppressed-when-not-needed** |
| Not expandable (`lineLimit` is `nil`, or the laid-out line count does not exceed it — see **expand-toggle-visibility**) | Expand toggle hidden entirely; full text shown regardless of `isExpanded` |
| Toggle disabled | `onToggleExpanded == nil`; toggle still visible when expandable, but `isEnabled == false` — see **expand-toggle-enablement** |
| Toggle pressed | Standard `NSButton` (`.momentaryChange`) pressed appearance, inherited from AppKit; the source applies no custom pressed styling |
| Filled-width (wrapped) | Bubble is exactly `maxWidth` wide instead of sized to content — see **fills-width-when-wrapped** |
| Focused | Not applicable to the bubble itself — the bubble is never itself a key/focused view; the transcript's row-selection focus ring belongs to its host, `ChatView` (see **Accessibility**) |
| Loading/streaming | Not applicable in this file. `ChatMessage` carries `isStreaming` (used elsewhere for a composing caret) and `delivery` (`.settled` / `.sending` / `.failed(String)`, used elsewhere for a delivery-failure line), but `AIChatBubbleView` reads neither field — it renders only `message.text`, `.role`, `.timestamp`, and `.isWorkOutput`. Unlike `AgenticDeveloperToolkit`'s `MessageBubbleView`, this component never shows a composing caret or a failure indicator of its own. |

## Accessibility

- **Role**: Generic `NSView` container; the source sets no custom accessibility role or `accessibilityElement` grouping on `AIChatBubbleView` itself.
- **Label**: The source sets no accessibility label on the bubble container. The message text reaches VoiceOver through the underlying `NSTextView`'s own default AppKit accessibility (an `NSTextView` exposes its string content automatically). The expand toggle is the only element the source labels explicitly: `setAccessibilityLabel` and the `NSImage`'s `accessibilityDescription` are both set to "Show the whole message" / "Show less" per **expand-toggle-icon-and-label**; it is also tagged with `accessibilityID("chat-bubble.more")` for UI-test identification, not for VoiceOver wording.
- **State announcement**: The toggle's label and icon swap when `isExpanded` changes, so VoiceOver reads the new label the next time it visits the button, but the source posts no explicit accessibility notification (no `NSAccessibility.post`) to announce the change proactively. No other state in this component (role, work-output dimming, border) is announced beyond what the color/text change itself implies.
- **Minimum tap target**: The 44×44pt minimum is an iOS/touch guideline; this is a macOS, pointer-driven control, where Apple's Human Interface Guidelines set no equivalent minimum. The expand toggle's actual click target is 22×22pt.
- **Color dependence**: In `.speaker` style, `.user` vs `.assistant` is distinguished only by the theme's bubble/text color roles — the component provides no non-color cue (icon, position, label) of its own. In `.terminal` style this is deliberate and total: per the `Style.terminal` doc comment, both conversational roles resolve to the *same* fill, text, and border, because the row that hosts a terminal-style bubble already states who is speaking in a header line above it; color is not how that style tells user from assistant.
- **Keyboard path (traced through the host)**: `AIChatBubbleView` itself has no keyboard path for `onSingleClick`/`onDoubleClick` — it overrides only `mouseDown(with:)` and does not override `acceptsFirstResponder` or any `keyDown(_:)` handling. In this component's actual usage, though, the gap is filled one level up: its host, `ChatView` (`packages/apple/AgenticToolkit/macOS/Features/AIChatWindow/ChatView.swift`), overrides `acceptsFirstResponder` (`true` when row selection is enabled) and `keyDown(with:)` to move a row-level selection with the arrow keys, invoke the same action as a double-click open (`rowActions.onOpen`) on Return, jump to the source conversation on Shift-Return, and — via `handleSelectionLetter` — invoke the same open/jump/expand-toggle actions on the bare letters "c"/"g"/"m". `ChatTranscriptRowView` wires `bubble.onSingleClick` to row selection and `bubble.onDoubleClick` to the same `onOpen` action `ChatView`'s Return key invokes. So a keyboard-only user reaches equivalent behavior through the transcript's row selection, not through this view in isolation.

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

## Edge Cases

- **Empty message text**: An empty `message.text` produces zero glyphs; the measurement's line-fragment walk never executes, so `lineCount` is `0`. `isExpandable` is `false` for any `lineLimit` (0 is never greater than a limit), so the toggle stays hidden and the bubble collapses to whatever the timestamp (if any) and padding come to.
- **`lineLimit = 0`**: The truncation walk's loop condition (`line < limit`) never executes when `limit` is `0`, so the walked `glyph` offset stays `0`; the truncation function's guard (`glyph > 0`) then fails and it returns `nil`. The net effect: `isExpandable` is `true` for any non-empty text (any positive `lineCount` exceeds `0`), so the toggle is shown, but the text is never actually cut down — the full message renders regardless of `isExpanded`. A caller passing `lineLimit = 0` gets a toggle that has nothing to expand.
- **Message text that is entirely whitespace/newlines and exceeds `lineLimit`**: The truncation function searches backward for the last non-whitespace character before appending the ellipsis; if the portion up to the cut point is all whitespace, that search returns "not found" and the function returns `nil`. As in the `lineLimit = 0` case, `isExpandable` is still `true` and the toggle still shows, but the text is displayed in full, untruncated, with no ellipsis.
- **A single unbroken run of characters wider than the text width**: No paragraph style or line-break mode is set on the attributed string; wrapping such a run falls to the layout manager's own default word-wrapping fallback, which force-breaks a word that cannot fit on a line of its own.
- **Degenerate `maxWidth`** (at or below `textInset * 2`, i.e. 24pt): the text width available for the container and measurement pass becomes zero or negative. The source performs no minimum-width guard on this caller-provided value; behavior at that point is whatever `NSTextContainer`/`NSLayoutManager` do with a non-positive width, which this file does not define further.
- **Boundary values**: `lineLimit` of exactly the message's laid-out line count is the `truncation-suppressed-when-not-needed` boundary — see chat-bubble-024. `isExpanded` toggling with no palette yet applied is a no-op — see chat-bubble-035.
- **Concurrent access**: Not applicable. `AIChatBubbleView` is an `NSView`; all of its mutable state (`isExpanded`, the last-applied theme palette, the layout constraints) is read and written only from AppKit's main-thread event handlers (`mouseDown`, the toggle's action, the theme observer's callback, and property `didSet`s). The source contains no locking or thread-safety code, which is correct for a view that is never touched off the main thread.
- **Error states**: Not applicable. The component has no dependency on a network, database, or file-system call; it renders only the `ChatMessage` and `SemanticPalette` values it is given.
- **Offline/disconnected state**: Not applicable, for the same reason — this view performs no networking of its own.
- **Message text mutated after construction**: `AIChatBubbleView` holds `message` as a `let` — a value-type snapshot taken at construction. `ChatMessage.text` is itself a `var` elsewhere in the codebase (mutated in place while a streaming assistant reply grows), but this component never observes that later mutation; a caller must construct (or a host row must rebuild) a new `AIChatBubbleView` to show updated text.

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

## Deep Linking

Not applicable: `AIChatBubbleView` is a subview embedded directly into a chat window by its host. The source contains no URL scheme, route, or deep-link handling.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | "Show the whole message" | `expandTitle`, the toggle's label/tooltip when collapsed; a private `String` literal in `AIChatBubbleView.swift`, not sourced from a resource file |
| (none — hardcoded) | "Show less" | `collapseTitle`, the toggle's label/tooltip when expanded; same as above |
| (none — hardcoded) | "…" | `ellipsis`, appended after truncated text; same as above |

NEEDS REVIEW: Not implemented in source. Behavior undefined. The two toggle
titles are private `String` literals assigned to AppKit (`toolTip` and the
accessibility label), so they are never looked up in a string table and
always render in English. Whether they should be localized, and under which
keys, is unresolved.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source contains no animation. The toggle's icon/label swap and every layout change `apply(_:)` makes happen instantly. |
| Increase Contrast | Not implemented directly in this component: it always renders whatever color the palette resolves for a given role. The palette's dimmed text roles (`secondaryText`, `timestampText`) do enforce a minimum contrast floor against the window background (`dimmed(towards:by:minContrast:)`), but nothing in this file or the palette verifies contrast between a bubble's own paired fill and text color (e.g. `userText` against `userBubble`) — that pairing is only as good as the active theme's own choices. |
| Differentiate Without Color | Not implemented in source. In `.speaker` style, role is told apart by fill/text/border color alone, with no icon, label, or positional cue from this component. In `.terminal` style the two conversational roles are made to look identical on purpose (see **terminal-style-role-fill-override**), so there is no color distinction to differentiate from in the first place. |

## Feature Flags

Not applicable: the source defines no feature-flag checks. Every behavior is controlled directly by the caller-provided initializer parameters.

## Analytics

Not applicable: the source contains no analytics or event-tracking calls.

## Privacy

Not applicable: the component renders a caller-supplied `ChatMessage` and `SemanticPalette`. It does not collect, store, or transmit any data itself.

## Logging

Not applicable: the source contains no logging calls (no `Logger`, `os_log`, or `print`).

## Platform Notes

- **Source (Apple/Swift)**: `AIChatBubbleView.swift` (`packages/apple/AgenticToolkit/macOS/Features/AIChatWindow`), an `NSView` subclass, macOS-only (`import AppKit`) with no iOS counterpart in this feature. It composes a private `BubbleTextView` (an `NSTextView` subclass that intercepts single/double clicks per **double-click-interception**/**single-click-passthrough**) and an `NSButton` expand toggle, measures text off-screen with a throwaway `NSTextStorage`/`NSLayoutManager`/`NSTextContainer` stack rather than the live text view, resolves its fill/border/font from `TerminalBoxStyle` (`packages/apple/AgenticToolkit/CoreMacOS/Theme/TerminalBoxStyle.swift`) and `TerminalAppearance` (`packages/apple/AgenticToolkit/macOS/Features/TerminalSession/TerminalAppearance.swift`), and observes theme changes through this toolkit's `observeTheme` helper (`AgenticToolkitCoreMacOS`) rather than KVO or `NotificationCenter` directly. Its own keyboard-accessibility gap is filled one level up, by `ChatView.swift` and `ChatTranscriptRowView.swift` in the same directory — see **Accessibility**. Internally the source names its own layout/state constants privately: the vertical text padding as `vPad` (8pt), the horizontal text padding as `textInset` (12pt), the toggle's gap below the text as `toggleGap` (2pt), the toggle's fixed size as `toggleSize` (22pt), and the last-applied palette as `appliedPalette`.
- **SwiftUI**: Build from a `ZStack`/`VStack` sized with `.frame(maxWidth:)`, backed by a shape (`RoundedRectangle(cornerRadius:)`) whose radius switches on the `style` enum. Conform to `AgenticDeveloperToolkit`'s `Themeable` protocol and observe palette changes with its `ThemePaletteObserver` (both declared in `external/agenticdevelopertoolkit/packages/apple/AgenticDeveloperToolkit/SourcesUI/Shared/Theme/ThemeBinding.swift`), mirroring `observeTheme` rather than reaching for an `@Themeable` property wrapper (SwiftUI has none). Measure text either with SwiftUI's own `Text` layout (a hidden `Text` plus `GeometryReader`, or `.lineLimit` combined with a `PreferenceKey` reporting truncation) or by sizing an `AttributedString`/`NSAttributedString` via `boundingRect`, matching the source's throwaway-layout-manager measurement approach. Drive the expand/collapse toggle from a `Button` with a `systemImage` chevron bound to `isExpanded`, invoking a caller closure rather than mutating local state, matching **expand-toggle-invocation**.
- **Compose** (Android/Kotlin): Build the bubble from a `Surface` or `Card` composable, switching its `shape` (`RoundedCornerShape`) on the style equivalent. Map the semantic `userBubble`/`personaBubble`/`userText`/`personaText`/`timestampText` roles onto Compose colors via a custom `CompositionLocal` holding the semantic palette (not Material 3's own color-role slots, which have no user/persona distinction). Measure text with `TextMeasurer` and a `maxLines` parameter on `Text` to reproduce **line-limit-truncation**, reading `TextLayoutResult.hasVisualOverflow` to decide whether to show the expand affordance. Use an `IconButton` with a chevron `ImageVector` for the toggle, and gate its enabled state on whether a callback lambda is non-null, matching **expand-toggle-enablement**.
- **AppKit / UIKit**: The source above is already AppKit; a UIKit (iOS) port would replace `NSView` with `UIView`, `NSTextView` with a non-editable `UITextView` (to keep native text selection) or `UILabel` with `numberOfLines` (losing selection), and `NSButton` with a `UIButton` configured with an SF Symbol image for the chevron. `NSLayoutManager`/`NSTextContainer` measurement carries over almost unchanged since UIKit shares the same text-layout classes; `UIView.layer.cornerRadius`/`borderWidth`/`borderColor` map directly from the AppKit calls. `mouseDown(with:)`'s single/double-click interception has no UIKit equivalent — a `UITapGestureRecognizer` plus a `UITapGestureRecognizer` with `numberOfTapsRequired = 2` and a `require(toFail:)` relationship would be the idiomatic replacement for **double-click-interception**/**single-click-passthrough**, rather than overriding `touchesBegan(_:with:)`. The keyboard-path gap this recipe notes under Accessibility would need re-solving on iOS too, since UIKit's own row-selection idiom (`UITableView`/`UICollectionView` cell selection plus VoiceOver's own swipe navigation) differs from `ChatView`'s macOS arrow-key/letter scheme.
- **WinUI 3** (Windows): Build the bubble as a `Border` (for `CornerRadius`, `Background`, `BorderBrush`, `BorderThickness`) wrapping a `StackPanel` that holds a `TextBlock` for the message text and, when expandable, a `Button` for the toggle. Set `TextBlock.TextWrapping="Wrap"` and, for the collapsed state, `TextBlock.MaxLines` bound to `lineLimit` with `TextTrimming="CharacterEllipsis"` — WinUI's `TextBlock` supports both properties natively, so no manual line-walking is needed to reproduce **line-limit-truncation**; read `TextBlock.IsTextTrimmed` after a layout pass to decide whether the expand toggle is needed, mirroring **expand-toggle-visibility**. Use a `FontIcon` with the Segoe Fluent chevron glyphs (`\uE70D` for the collapsed/down chevron, `\uE70E` for the expanded/up chevron) for the toggle's icon, bound to an `IsExpanded` property, and set `Button.IsEnabled` from whether a relay command is non-null to reproduce **expand-toggle-enablement**. Bind `Background`/`Foreground`/`BorderBrush` to `ThemeResource`s keyed by role (`UserBubbleBrush`, `PersonaBubbleBrush`, `SurfaceBrush`, `BorderBrush`, and so on) so a `.terminal`-equivalent visual state can swap them via `VisualStateManager` the way **terminal-style-role-fill-override** does, rather than branching in code-behind. Bind `Border.MaxWidth` to `maxWidth` and toggle `Border.HorizontalAlignment` between `"Stretch"` and `"Left"`/`"Right"` to reproduce **fills-width-when-wrapped** versus **bubble-width-bound-by-max-width**. Double-click interception (**double-click-interception**) has no built-in WinUI gesture; use `DoubleTapped` alongside `Tapped`, and suppress the single-tap handler's effect when a double-tap follows within the system double-click time, since WinUI raises both events independently rather than the single `mouseDown` callback this source relies on. For the keyboard path this recipe's Accessibility section notes as missing on this view alone, give the hosting list control (a `ListView`/`ItemsRepeater`) the same row-selection-plus-Enter/letter-key scheme `ChatView` implements, rather than adding key handling to the bubble control itself — this recipe exists as the reason to be concrete about that split.

## Design Decisions

**Decision**: Message text and the inline timestamp are always set in the app's resolved terminal font (Menlo-Regular 13pt by default, via `TerminalAppearance.resolvedFont(theme:)`), never the theme's general body-text font, in both `.speaker` and `.terminal` styles.
**Rationale**: These bubbles are a written-down terminal conversation — the feed's rows are literally transcripts of sessions running in a terminal — so text set in a different face than the terminal it came from would read as a different program's output. The face is chosen once, for the terminal, and both bubble styles follow it. A consequence traced in this recipe (see Compliance) is that the message text does not scale with the app's general typography size control the way theme body/caption text elsewhere does — only the separate Terminal font-size setting affects it.
**Approved: pending**

**Decision**: In `.terminal` style, `.user` and `.assistant` resolve to the identical fill (the palette's `surface` color) and border (the palette's `border` color), rather than keeping the role-based coloring `.speaker` style uses.
**Rationale**: A one-to-one chat has two speakers and no other way to tell them apart, so coloring by role there *is* the attribution. A merged feed already states who is talking in a header line above every row, so coloring by role again there would spend the window's whole palette repeating a fact already said in words, right beside a session list drawn as inset boxes on the window's surface — which is the shape `.terminal` reuses.
**Approved: pending**

**Decision**: A theme's bubble border role is applied only when the theme explicitly overrides it (`theme.roleOverrides[role.rawValue] != nil`), never merely because the role's default derivation would produce some color.
**Rationale**: Every role resolves to *some* color when a theme leaves it undeclared, so checking the resolved color alone would draw a hairline border around every bubble in every theme. Checking for an explicit override instead limits the border to themes that opted in.
**Approved: pending**

**Decision**: `.error` and `.notice` roles keep their fixed border behavior (always bordered / never bordered) even in `.terminal` style, since **terminal-style-role-fill-override** only applies to `.user` and `.assistant`.
**Rationale**: `.error` and `.notice` are not conversation — they carry no speaker to disambiguate — so they stay on the general semantic danger/secondary-text treatment in every style rather than being folded into the terminal panel's speaker-neutral look.
**Approved: pending**

**Decision**: The expand toggle is a chevron symbol (`chevron.down.circle.fill` / `chevron.up.circle.fill`) rather than words, sized at 22pt, and sits in the bubble's lower-right corner under everything rather than immediately after the point where the text was cut.
**Rationale**: Words would compete with the message they sit under, reading as one more line of the reply; a symbol is recognized rather than read, and at this size is a target hit without aiming. Putting it in a fixed lower-right position, rather than trailing the cut point, means it is the same control in the same place whether the message is cut short or laid out whole, rather than moving to wherever the text happened to stop.
**Approved: pending**

**Decision**: The timestamp uses a fixed `h:mm a` (12-hour, unpadded hour) pattern rather than a locale-derived hour-cycle template.
**Rationale**: The class comment documents this as an intentional glance-legibility choice shared with `ChatTranscriptRowView`'s own timestamp, not an oversight. This is a real divergence from `AgenticDeveloperToolkit`'s `MessageBubbleView`, which derives its timestamp pattern from the locale's own hour-cycle template — `AIChatBubbleView` does not follow that convention, and a reader in a 24-hour-clock locale will still see a 12-hour timestamp here.
**Approved: pending**

**Decision**: `AIChatBubbleView.mouseDown(with:)`, when `isTextSelectable` is `true`, consumes a click on the bubble's own padding without ever calling `super.mouseDown(with:)`; when `isTextSelectable` is `false`, it does call `super.mouseDown(with:)`.
**Rationale**: The text view already keeps presses that land on the text itself. Letting a press on the surrounding padding fall through to the superview would mean a click two points from a word a reader was about to select could dismiss something else entirely — the same gesture, two different outcomes, decided by a couple of points. Consuming it here keeps that from happening only when the bubble is meant to support text selection; a non-selectable bubble has no selection to protect, so it lets the default behavior proceed.
**Approved: pending**

**Decision**: `BubbleTextView.mouseDown(with:)` still calls `onSingleClick` even on a double-click, whenever no `onDoubleClick` handler is registered, because the double-click short-circuit only fires when a handler exists.
**Rationale**: A double-click means "select this word" and, in a feed with a handler wired up, also means "open this conversation." Only one of those can have the gesture; where no handler is waiting for it, the click falls through as an ordinary click (invoking `onSingleClick` and the text view's own default handling), so a reader without that handler wired up still gets ordinary double-click word selection.
**Approved: pending**

**Decision**: `measure(_:width:)`'s line-counting walk stops early if it encounters a zero-length effective range, and `trimming(_:within:width:)` stops removing characters once the remaining string is no longer longer than the ellipsis itself.
**Rationale**: Both are defensive guards against a degenerate text-layout result producing an infinite loop, rather than a claim about how many lines or characters the result is guaranteed to have. They trade a possibly-imprecise line count or an ellipsis-only string for a function call that is guaranteed to return.
**Approved: pending**

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | failed | Accessibility |
| [locale-aware-formatting](agenticdevelopercookbook://compliance/internationalization#locale-aware-formatting) | failed | Internationalization |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | Internationalization |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [text-expansion-tolerance](agenticdevelopercookbook://compliance/internationalization#text-expansion-tolerance) | passed | Internationalization |

Statuses rest on: the expand toggle's explicit accessibility label versus the bubble container having no label or grouping of its own (screen-reader-support); the bubble itself having no `keyDown`/`acceptsFirstResponder`, with the equivalent path supplied only by its host `ChatView`'s row-selection keyboard handling, which this recipe traces but which this component alone does not provide (keyboard-navigable — see Accessibility); the palette's dimmed text roles (`secondaryText`, `timestampText`) enforcing a minimum contrast floor against the window background while nothing verifies contrast between a role's own paired fill and text color, e.g. `userText` against `userBubble` (contrast-ratio); the message text being pinned to the separate Terminal font-size setting rather than the app's general typography scale (`SemanticPalette.size(_:)`/`scaled(by:)`) that the "Text Size" reader control and other UI use — increasing that control changes nothing in this bubble's message text (dynamic-type-support); the fixed `h:mm a` pattern ignoring the user's locale hour-cycle preference, unlike `AgenticDeveloperToolkit`'s `MessageBubbleView` (locale-aware-formatting); the component rendering arbitrary caller-provided Unicode text via `NSAttributedString`/`NSTextView` without special-casing (unicode-support); the "Show the whole message" / "Show less" / "…" strings being Swift string literals in `AIChatBubbleView.swift` rather than sourced from a resource table (string-externalization, no-hardcoded-strings); and the bubble measuring and sizing to whatever text it is given, up to `maxWidth`, rather than assuming a fixed width for a fixed string length (text-expansion-tolerance).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude Sonnet 5 | Initial creation from AIChatBubbleView.swift and its TerminalBoxStyle/TerminalAppearance/SemanticPalette dependencies |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: moved private source identifiers (vPad, textInset, toggleGap, toggleSize, appliedPalette) into Platform Notes, defined the isExpandable condition inline in States, pinned locale and gave exact values in the timestamp test vectors, added WinUI chevron code points, cited Themeable/ThemePaletteObserver's source file, and corrected MessageBubbleView's toolkit attribution throughout |
