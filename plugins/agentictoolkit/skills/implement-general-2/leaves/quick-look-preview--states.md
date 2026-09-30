<!-- leaf: implement-general-2/quick-look-preview--states · source: quick-look-preview.md -->

# Quick Look Preview

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders `QLPreviewView`'s live preview of `url`; if the file's type has no QuickLook generator, `QLPreviewView` itself draws its native "no preview available" state (per the source's doc comment) — this file contains no code for that fallback. |
| Pressed | Not applicable: the source wires no target/action, gesture recognizer, or click handling of its own; any pointer interaction (zoom, scroll, page navigation) is `QLPreviewView`'s own native behavior. |
| Disabled | Not applicable: the source never reads or sets `isEnabled` or any dimmed-appearance property — `QuickLookPreview` has no enabled/disabled concept. |
| Focused | Not applicable: the source never overrides `acceptsFirstResponder` or manages first-responder status; it cannot become focused through code in this file. |
| Loading | Not applicable in this file: `view.autostarts = true` (see **enables-autostart**) tells `QLPreviewView` to begin generating a preview immediately, but any generation-in-progress indicator is `QLPreviewView`'s own native behavior, not code defined here. |
