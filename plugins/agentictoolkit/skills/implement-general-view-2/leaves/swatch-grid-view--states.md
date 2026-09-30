<!-- leaf: implement-general-view-2/swatch-grid-view--states · source: swatch-grid-view.md -->

# SwatchGridView

## States

| State | Appearance change |
|-------|------------------|
| Default | Swatches render in rows per `colors`/`columns`; empty `colors` renders zero rows. |
| Pressed | Not applicable: no `NSControl`, target-action, or click-handling code exists anywhere in `SwatchGridView.swift`; swatches and rows are plain, non-interactive `NSView`/`NSStackView` instances. |
| Disabled | Not applicable: `isEnabled` is never referenced in source; the component has no notion of an enabled/disabled state. |
| Focused | Not applicable: the component overrides no focus-related property and contains no `NSControl`, so it never becomes first responder or shows a focus ring. |
| Loading | Not applicable: every operation in source (`rebuild()`, `makeSwatch(_:)`, `setColors(_:)`) is a synchronous property assignment; there is no asynchronous operation and no loading indicator. |
