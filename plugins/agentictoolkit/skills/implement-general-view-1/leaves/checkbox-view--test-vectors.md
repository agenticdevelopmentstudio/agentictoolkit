<!-- leaf: implement-general-view-1/checkbox-view--test-vectors · source: checkbox-view.md -->

# CheckboxView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| checkbox-view-001 | arranges-row-layout | Construct `CheckboxView` with any `viewModel` | `label` and `toggle` are both subviews of a single row view that is pinned to the component's edges; a flexible spacer sits between `label` and `toggle`, so `toggle` sits at the row's trailing edge; no other layout container appears |
| checkbox-view-002 | links-toggle-accessibility-title | Construct `CheckboxView` with any `viewModel` | `toggle`'s accessibility title UI element is `label` |
| checkbox-view-003 | initializes-from-view-model | `viewModel.title = "Enable Sync"`, `viewModel.value = true` | After init, `label.stringValue == "Enable Sync"` and `toggle.state == .on` |
| checkbox-view-004 | initializes-from-view-model | `viewModel.value = false` | After init, `toggle.state == .off` |
| checkbox-view-005 | commits-toggle-value | `viewModel.settingObserver.value = false`; set `toggle.state = .on` and invoke `toggleChanged(toggle)` | `viewModel.settingObserver.value == true` after the call |
| checkbox-view-006 | skips-redundant-commits | Wrap `viewModel.settingObserver.value`'s setter with a spy; set `viewModel.settingObserver.value = true`, then set `toggle.state = .on` (same value) and invoke `toggleChanged(toggle)` | The spy records zero calls: `viewModel.settingObserver.value`'s setter is not invoked, and `viewModel.settingObserver.value` remains `true` |
| checkbox-view-007 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue` and `toggle.state` both update to reflect the new `viewModel` state |
| checkbox-view-008 | exposes-constituent-views | Construct the component, then access `.label` and `.toggle` from outside the type | Both properties are accessible and return the same `NSTextField`/`NSSwitch` instances built during init |
| checkbox-view-009 | requires-designated-initializer | Attempt `CheckboxView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| checkbox-view-010 | rejects-frame-only-initialization | Attempt `CheckboxView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| checkbox-view-011 | confines-to-main-actor | Attempt to construct or mutate a `CheckboxView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| checkbox-view-012 | claims-sole-onchange-observer | Register an observer closure on `viewModel.onChange`, then construct a `CheckboxView` against that same `viewModel` | `viewModel.onChange` now points at `CheckboxView`'s own handler; invoking it no longer calls the previously registered closure |
| checkbox-view-013 | inherits-native-keyboard-focus | Construct `CheckboxView` in a running app, tab focus to `toggle`, then press Space | `toggle` receives keyboard focus in the window's tab order and its state flips on Space, per `NSSwitch`'s native `NSControl` behavior (unmodified by source) |
