<!-- leaf: implement-general-view-3/theme-preview-view--states · source: theme-preview-view.md -->

# ThemePreviewView

## States

| State | Appearance change |
|-------|------------------|
| Default | Before `show(_:)` is called, `container` is empty and `self` has no background paint (`empty-initial-state`). After `show(_:)`, the view fully repaints as described in Overview/Behavioral Requirements; calling `show(_:)` again with a different (or the same) theme tears down and rebuilds every card from that theme. |
| Pressed | Not applicable: no `NSControl`, target-action, or click-handling code exists anywhere in `ThemePreviewView.swift`; every element (boxes, pills, rows, badges, the caret) is a plain, non-interactive `NSView`/`NSStackView`/`NSTextField(labelWithString:)`. |
| Disabled | Not applicable: `isEnabled` is never referenced in source; the component has no notion of an enabled/disabled state. |
| Focused | Not applicable: the component overrides no focus-related property and contains no `NSControl`, so it never becomes first responder or shows a focus ring. |
| Loading | Not applicable: `show(_:)` and every `make*Sample` helper it calls are synchronous, non-throwing property assignments and view constructions; there is no asynchronous operation and no loading indicator anywhere in source. |
