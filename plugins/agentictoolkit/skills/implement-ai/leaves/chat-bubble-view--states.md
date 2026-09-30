<!-- leaf: implement-ai/chat-bubble-view--states · source: ai-chat-bubble-view.md -->

# AIChatBubbleView

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
