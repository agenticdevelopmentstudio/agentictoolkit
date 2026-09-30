<!-- leaf: implement-general-view-1/dismissible-hint-view--states · source: dismissible-hint-view.md -->

# DismissibleHintView

## States

| State | Appearance change |
|-------|------------------|
| Default | `textLabel` and `dismissButton` are added inside the pinned stack; `isHidden` is set from `observer.value` before the view is ever displayed, so there is no unevaluated frame. |
| Visible (not yet dismissed) | `isHidden == false`. |
| Hidden (dismissed) | `isHidden == true`, set once the observed setting's value becomes `true` and is delivered through `onChange`; `onVisibilityChange` fires once on the transition. |
| Pressed | Not applicable to the composite view: `dismissButton`'s own pressed-bezel highlight is `NSButton`'s default system behavior, not custom-drawn by `DismissibleHintView`. |
| Disabled | Not implemented in `DismissibleHintView`; `isEnabled` is never read or set anywhere in source. |
| Focused | Not styled by `DismissibleHintView`; any focus ring belongs to `dismissButton`'s own default first-responder appearance — no custom focus handling appears in source. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator in source. |
