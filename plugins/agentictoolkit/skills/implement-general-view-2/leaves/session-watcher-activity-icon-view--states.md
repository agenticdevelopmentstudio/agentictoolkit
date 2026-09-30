<!-- leaf: implement-general-view-2/session-watcher-activity-icon-view--states · source: session-watcher-activity-icon-view.md -->

# SessionWatcherActivityIconView

## States

| State | Appearance change |
|-------|------------------|
| Idle, not summarizing (`activity: .idle, isSummarizing: false`) | View is hidden (`isHidden = true`); no glyph is drawn and no animation runs. |
| Working, not summarizing (`activity: .working, isSummarizing: false`) | Visible; `arrow.triangle.2.circlepath` tinted with the theme's accent color; spins one full clockwise turn every 1.1s, indefinitely. |
| Waiting, not summarizing (`activity: .waiting, isSummarizing: false`) | Visible; `exclamationmark.circle.fill` tinted with the theme's warning color; opacity pulses 1.0→0.25 and back, 0.7s each way (1.4s full cycle), indefinitely. |
| Summarizing (`isSummarizing: true`, any `activity`) | Visible; `sparkles` tinted with the theme's accent color; opacity pulses 1.0→0.25 and back, 0.7s each way (1.4s full cycle), indefinitely — the same pulse as Waiting, regardless of the underlying `activity`. |
| Pressed | Not applicable: the source defines no target/action, gesture recognizer, or tracking area — this is a purely visual, non-interactive display element with no pressed state to represent. |
| Disabled | Not applicable: the source defines no `isEnabled` property or dimmed-appearance branch. |
| Focused | Not applicable: the view never becomes key/first responder; the source does not override `acceptsFirstResponder`, so `NSView`'s default (`false`) applies unmodified. |
| Loading | Not applicable: the view performs no asynchronous operation of its own and defines no loading flag; the "Working"/"Waiting" rows above are externally supplied state this view renders, not a loading operation this view performs. |
