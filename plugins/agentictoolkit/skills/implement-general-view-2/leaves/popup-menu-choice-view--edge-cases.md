<!-- leaf: implement-general-view-2/popup-menu-choice-view--edge-cases · source: popup-menu-choice-view.md -->

# PopupMenuChoiceView

**Rules** (cite as `implement-general-view-2/popup-menu-choice-view--edge-cases#<slug>`):

- `return-error-documented-ignores-unresolvable-selection-error` MUST — Error states: Not applicable — every operation in this file (menu item construction, the popup's target-action, and the …

## Edge Cases

- Null/empty input: `viewModel` (`ComposableSettings.ChoiceViewModel<Value>`)
  is a non-optional, typed constructor parameter; Swift's type system rules
  out `nil`. An empty `viewModel.choices` array is handled per
  **tolerates-empty-choices**: the component constructs without crashing,
  adds zero menu items, and `syncSelection`'s `firstIndex(where:)` finds no
  match, so no item is selected — the popup renders AppKit's native
  empty-menu appearance.
- Boundary values: Not applicable — `choices` is an ordered, arbitrary-length
  list of discrete label/value pairs with no numeric minimum or maximum to
  bound.
- Concurrent access: Not applicable — the class is declared `@MainActor`,
  so all construction and mutation is serialized to the main actor by the
  compiler (see **confines-to-main-actor**).
- Error states: Not applicable — every operation in this file (menu item
  construction, the popup's target-action, and the `settingObserver.value`
  write) is a synchronous, non-throwing call; no `try`, `Result`, or
  error-producing API appears in source. The one failure-shaped path —
  `representedObject as? Value` failing — is handled by a silent `guard`
  return, not an error, and is documented as **MUST**
  (**ignores-unresolvable-selection**), not as an error state.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ComposableSettings.ChoiceViewModel<Value>`.
- Non-matching current value: When `viewModel.value` does not equal any
  choice's `value`, `syncSelection`'s `firstIndex(where:)` returns `nil`
  and `selectItem(at:)` is never called — see **leaves-unmatched-selection**.
  The popup's displayed selection is left uncorrected: whatever item
  `NSPopUpButton` selects by default (its first added item), rather than
  being cleared or forced to a fallback.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `PopupMenuChoiceView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.syncSelection() }` — see
  **replaces-onchange-handler** and the corresponding Design Decision.
  Constructing a second `PopupMenuChoiceView` (or any other observer)
  against the same view model instance silently drops whatever handler was
  previously registered there.
