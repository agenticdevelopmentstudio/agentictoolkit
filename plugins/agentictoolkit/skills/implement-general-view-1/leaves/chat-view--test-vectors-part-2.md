<!-- leaf: implement-general-view-1/chat-view--test-vectors-part-2 · source: chat-view.md -->

# ChatView — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| chat-view-048 | toggle-expansion-in-place | `m` pressed on an expandable, selected row | That row's `isExpanded` flips without the transcript stack being torn down and rebuilt |
| chat-view-049 | bubble-style-uniform | `bubbleStyle` changed from `.speaker` to `.terminal` with an existing transcript on screen | Every bubble/row in the transcript re-renders in the new style after one rebuild |
| chat-view-050 | background-fill-toggle | `drawsBackground = true`, then `false` | The view's layer background is the theme's chat-surface color, then transparent |
| chat-view-051 | accessibility-identifiers | Any constructed `ChatView` | The four named subviews carry exactly the four specified accessibility identifiers |
| chat-view-052 | theme-responsive-controls | The active theme changes | Composer field colors/font, prompt/status label colors/fonts, send-button tint, and background fill all update without the view being re-created |
| chat-view-054 | letter-shortcuts-unmodified-only | A row selected; `g` pressed plain, then Cmd-G | Plain `g` invokes `onJump`; Cmd-G is not intercepted (handed to the system) |
| chat-view-055 | letter-shortcuts-unmodified-only, letter-m-requires-expandable | A row selected whose message exceeds the line limit; `m` pressed with Option held | The modified `m` is not intercepted as the expansion shortcut (handed to the system); no expansion toggle occurs |
