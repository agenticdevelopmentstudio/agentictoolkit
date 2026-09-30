<!-- leaf: implement-general-view-3/themed-terminal-view--states · source: themed-terminal-view.md -->

# Themed Terminal View (Hollow Caret)

## States

| State | Appearance change |
|-------|------------------|
| Default | On construction, `caretAppearance` is `CaretAppearance()` (`color`/`textColor` both `.white`, `isAlwaysHollow`/`marksActivePane` both `false`), which resolves to the Filled state below. |
| Pressed | Not applicable: `ThemedTerminalView` renders a text caret, not a pressable control, and defines no pressed-state handling of its own. |
| Disabled | Not applicable: the source never reads or sets an enabled/disabled flag on this view. |
| Focused | Not applicable as a first-responder concept: the caret's hollow/filled decision is driven by `isAlwaysHollow`/`marksActivePane` plus `ComposableTabsActivePane`, not by this view's own key/first-responder status directly. |
| Loading | Not applicable: `ThemedTerminalView` performs no asynchronous work of its own. |
| Filled (custom) | `caretColor == caretAppearance.color`, `caretTextColor == nil`, caret subview layer border width `0`. Reached when `isAlwaysHollow == false` and either `marksActivePane == false` or `isInActivePane(self) == true`. |
| Hollow — always (custom) | `caretColor == .clear`, `caretTextColor == caretAppearance.textColor`, caret subview layer border width `1` in `caretAppearance.color`. Reached whenever `isAlwaysHollow == true`. |
| Hollow — inactive pane (custom) | Same appearance as "Hollow — always". Reached when `isAlwaysHollow == false`, `marksActivePane == true`, and `isInActivePane(self) == false`. |
