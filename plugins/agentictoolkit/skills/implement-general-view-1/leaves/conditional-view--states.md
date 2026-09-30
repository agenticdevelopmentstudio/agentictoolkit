<!-- leaf: implement-general-view-1/conditional-view--states · source: conditional-view.md -->

# ConditionalView

## States

| State | Appearance change |
|-------|------------------|
| Default | `child` is added as the only subview and pinned to edges; `isHidden` is set from `applyVisibility(for: observer.value)` before the view is ever displayed, so there is no unevaluated frame. |
| Visible | `isHidden == false`; set whenever `isVisible(value)` returns `true` for the setting's current value. `onVisibilityChange` fires once on a transition into this state from Hidden — never during the initial evaluation in `init`, because no caller has had the chance to assign `onVisibilityChange` at that point. |
| Hidden | `isHidden == true`; set whenever `isVisible(value)` returns `false` for the setting's current value. `onVisibilityChange` fires once on a transition into this state from Visible, for the same reason the Visible row's initial-evaluation exception applies. |
| Pressed | Not applicable: `ConditionalView` is a plain container view — it defines no target/action and receives no press interaction of its own. |
| Disabled | Not implemented in `ConditionalView`; `isEnabled` is never read or set anywhere in source. |
| Focused | Not styled by `ConditionalView`; any focus ring belongs to `child`, not to this container. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator in source. |
