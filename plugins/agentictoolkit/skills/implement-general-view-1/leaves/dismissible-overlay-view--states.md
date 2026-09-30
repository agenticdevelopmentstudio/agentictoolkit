<!-- leaf: implement-general-view-1/dismissible-overlay-view--states · source: dismissible-overlay-view.md -->

# DismissibleOverlayView

## States

| State | Appearance change |
|-------|------------------|
| Default (idle, fully presented) | `alphaValue == 1`; backdrop fully applies its `material`; `isDismissing == false` |
| Presenting (during `present(in:)`) | `alphaValue` animates from 0 to 1 over `fadeDuration` (0.2s) |
| Dismissing (from the first `dismiss()` call) | `isDismissing == true`; `alphaValue` animates from its current value to 0 over `fadeDuration` (0.2s); the view remains in the hierarchy, still swallowing an unclaimed click or dismiss key, until the fade completes |
| Removed (after fade-out completes) | The view has been removed from its superview and no longer draws or receives events |
| Pressed | Not applicable: the source defines no separate pressed-state styling; a press either reaches `mouseDown` (triggering dismissal, not a visual change) or is claimed by a subview's own control. |
| Disabled | Not applicable: the source exposes no `isEnabled` property or disabled-state styling. |
| Focused | Not applicable: per the source doc comment on `performKeyEquivalent(with:)` (see `key-equivalent-subview-priority`), the overlay deliberately never becomes first responder — `performKeyEquivalent` catches Escape/Return without requiring key/focus status, so it defines no focused appearance. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |
