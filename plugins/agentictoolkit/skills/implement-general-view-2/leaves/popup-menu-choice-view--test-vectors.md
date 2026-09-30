<!-- leaf: implement-general-view-2/popup-menu-choice-view--test-vectors · source: popup-menu-choice-view.md -->

# PopupMenuChoiceView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| popup-menu-choice-view-001 | arranges-row-layout | Construct `PopupMenuChoiceView` with any `viewModel` | The row view (an `NSStackView` from `makeRow`) is pinned to the component's edges; its subviews are exactly `[label, spacer, popUpButton]`, in that order; no other nested layout container appears within the row |
| popup-menu-choice-view-002 | populates-menu-items-from-choices | `viewModel.choices = [Choice(label: "A", value: .a), Choice(label: "B", value: .b)]` | After init, `popUpButton.itemArray.map(\.title) == ["A", "B"]` in that order |
| popup-menu-choice-view-003 | attaches-choice-value-to-item | Same `choices` as above | `popUpButton.item(at: 0)?.representedObject as? Value == .a`; `popUpButton.item(at: 1)?.representedObject as? Value == .b` |
| popup-menu-choice-view-004 | attaches-choice-image | `choices = [Choice(label: "A", value: .a, imageSystemName: "gearshape")]` | After init, `popUpButton.item(at: 0)?.image` is non-`nil` |
| popup-menu-choice-view-005 | omits-choice-image-when-absent | `choices = [Choice(label: "A", value: .a, imageSystemName: nil)]` | After init, `popUpButton.item(at: 0)?.image == nil` |
| popup-menu-choice-view-006 | suppresses-popup-bezel | Any initialized `PopupMenuChoiceView` | `popUpButton.isBordered == false` |
| popup-menu-choice-view-007 | resists-popup-stretch | Any initialized `PopupMenuChoiceView` | `popUpButton.contentHuggingPriority(for: .horizontal) == .defaultHigh` |
| popup-menu-choice-view-008 | links-popup-accessibility-title | Construct `PopupMenuChoiceView` with any `viewModel` | `popUpButton`'s accessibility title UI element is `label` |
| popup-menu-choice-view-009 | wires-popup-action | Any initialized `PopupMenuChoiceView` | `popUpButton.target === view`; `popUpButton.action == Selector("popupChanged:")` |
| popup-menu-choice-view-010 | initializes-from-view-model | `viewModel.title = "Theme"`, `viewModel.choices = [Choice(label: "Light", value: .light), Choice(label: "Dark", value: .dark)]`, `viewModel.value = .dark` | After init, `label.stringValue == "Theme"` and `popUpButton.indexOfSelectedItem == 1` |
| popup-menu-choice-view-011 | commits-selection-value | `viewModel.settingObserver.value = .light`; select the item whose `representedObject == .dark` and invoke `popupChanged(popUpButton)` | `viewModel.settingObserver.value == .dark` after the call |
| popup-menu-choice-view-012 | ignores-unresolvable-selection | Select an item whose `representedObject` is not of type `Value` (or with no item selected), then invoke `popupChanged(popUpButton)` | `viewModel.settingObserver.value`'s setter is not invoked; the value is unchanged |
| popup-menu-choice-view-013 | skips-redundant-commits | `viewModel.settingObserver.value = .dark`; select the item whose `representedObject == .dark` (same value) and invoke `popupChanged(popUpButton)` | `viewModel.settingObserver.value`'s setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| popup-menu-choice-view-014 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value` to a different choice, then invoke `viewModel.onChange(newValue)` | `label.stringValue` and `popUpButton.indexOfSelectedItem` both update to reflect the new `viewModel` state |
| popup-menu-choice-view-015 | exposes-constituent-views | Construct the component, then access `.label` and `.popUpButton` from outside the type | Both properties are accessible and return the same `NSTextField`/`NSPopUpButton` instances built during init |
| popup-menu-choice-view-016 | fixes-choice-set-at-construction | Construct `PopupMenuChoiceView` with a fixed `choices` array, then invoke `popupChanged(_:)` with a selection change and `viewModel.onChange` with an external change | The component itself never mutates `popUpButton`'s items after `init`: `popUpButton.numberOfItems` immediately after construction equals its value after both invocations. (A caller may still mutate `popUpButton`'s items directly through the public `popUpButton` property — see **exposes-constituent-views** — this vector covers only the component's own code.) |
| popup-menu-choice-view-017 | requires-designated-initializer | Attempt `PopupMenuChoiceView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| popup-menu-choice-view-018 | rejects-frame-only-initialization | Attempt `PopupMenuChoiceView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| popup-menu-choice-view-019 | confines-to-main-actor | Static/compile-time check, not a runtime vector: attempt to construct or mutate a `PopupMenuChoiceView` from off the main actor | The compiler rejects the call at compile time under Swift's `@MainActor` isolation checking; no runtime test applies |
| popup-menu-choice-view-020 | tolerates-empty-choices | `viewModel.choices = []` | Construction does not throw or trap; `popUpButton.numberOfItems == 0`; `popUpButton.indexOfSelectedItem == -1` (no item selected) |
| popup-menu-choice-view-021 | leaves-unmatched-selection | `viewModel.choices = [Choice(label: "A", value: .a)]`, `viewModel.value` set to a value matching no choice | After init, `popUpButton`'s selection is left as whatever `NSPopUpButton` selects by default (its first added item); no `selectItem(at:)` call clears or overrides it |
| popup-menu-choice-view-022 | replaces-onchange-handler | Register a closure on `viewModel.onChange`, then construct `PopupMenuChoiceView(viewModel: viewModel)` | After construction, invoking `viewModel.onChange` runs only the component's `syncSelection` handler; the previously registered closure is not invoked |
