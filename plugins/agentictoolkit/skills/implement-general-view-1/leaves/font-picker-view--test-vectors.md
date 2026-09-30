<!-- leaf: implement-general-view-1/font-picker-view--test-vectors · source: font-picker-view.md -->

# FontPickerView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| font-picker-view-001 | arranges-row-layout | Construct `FontPickerView` with any `viewModel` | `label` and `button` are arranged (with an internal spacer) in a single row view that is pinned to the component's edges; no other layout container appears |
| font-picker-view-002 | initializes-label-from-view-model-title | `viewModel.title = "Terminal Font"` | After init, `label.stringValue == "Terminal Font"` |
| font-picker-view-003 | initializes-button-without-fixed-width | Construct `FontPickerView` | `button` has no width constraint added by `FontPickerView` itself (it is built via `FontChooserButton()`, not `FontChooserButton(width:)`) |
| font-picker-view-004 | tags-button-with-a-fixed-accessibility-identifier | Construct `FontPickerView` | `button`'s accessibility identifier equals `"settings.font-picker.choose"` |
| font-picker-view-005 | commits-picked-font-through-view-model | Invoke `button.onChange(newFont)` | `viewModel.setFont(newFont)` is called |
| font-picker-view-006 | resyncs-synchronously-after-a-pick | Invoke `button.onChange(newFont)` where `newFont`'s name and size equal the view model's current stored values | `label.stringValue` and `button`'s displayed sample/title are re-set synchronously to match `viewModel`'s state, with no dependency on any later asynchronous callback |
| font-picker-view-007 | observes-external-view-model-changes | After construction, directly invoke the closure assigned to `viewModel.onChange` with an arbitrary font argument | `label.stringValue` and `button`'s displayed sample/title update to reflect `viewModel.title`/`viewModel.font` as they currently stand, independent of the argument passed |
| font-picker-view-008 | overwrites-existing-view-model-observer | Assign a closure to `viewModel.onChange`, then construct `FontPickerView(viewModel:)` against that same `viewModel`, then invoke `viewModel.onChange` | Only `FontPickerView`'s sync-calling closure runs; the original closure does not run |
| font-picker-view-009 | syncs-once-at-construction | Construct `FontPickerView` | `label.stringValue` and `button`'s displayed title already reflect `viewModel.title`/`viewModel.font` immediately after `init` returns, with no further call needed |
| font-picker-view-010 | redraws-label-text-on-every-sync | Trigger `sync()` twice (once via construction, once via `button.onChange` or `viewModel.onChange`) | `label.stringValue` is reassigned to `viewModel.title` on both occasions (verifiable via a spy on the label's `stringValue` setter recording at least two invocations) |
| font-picker-view-011 | updates-button-sample-on-every-sync | Trigger `sync()` | `button.show(_:title:)` is called with `viewModel.font` and `describe(viewModel.font, installed: viewModel.isInstalled)` |
| font-picker-view-012 | describes-font-name-and-rounded-point-size | Construct `FontPickerView` with a `viewModel` whose `font` resolves to `NSFont(name: "Menlo-Regular", size: 14.4)!` and whose `isInstalled == true` | `button.show(_:title:)`'s title equals `"\(font.displayName ?? font.fontName) — 14 pt"` — an em dash separator and the point size rounded to the nearest integer, with no `(not installed)` suffix |
| font-picker-view-013 | flags-an-uninstalled-font-in-its-title | Construct `FontPickerView` with a `viewModel` whose `isInstalled == false` | `button.show(_:title:)`'s title ends with the literal suffix `" (not installed)"` |
| font-picker-view-014 | dims-and-disables-the-row | Set `isEnabled = false`, then `isEnabled = true` | After `false`: `button.isEnabled == false`, `label.alphaValue == 0.4`. After `true`: `button.isEnabled == true`, `label.alphaValue == 1.0` |
| font-picker-view-015 | defaults-to-enabled | Construct `FontPickerView` | `isEnabled == true`, `button.isEnabled == true`, `label.alphaValue == 1.0`, before any explicit assignment |
| font-picker-view-016 | exposes-constituent-views | Construct the component, then access `.label` and `.button` from outside the type | Both properties are accessible and return the same `NSTextField`/`FontChooserButton` instances built during init (`label` is a `ThemedLabel` instance, declared as `NSTextField`) |
| font-picker-view-017 | requires-designated-initializer | Attempt `FontPickerView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| font-picker-view-018 | rejects-frame-only-initialization | Attempt `FontPickerView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| font-picker-view-019 | delegates-font-resolution-fallback | Construct `viewModel` whose stored font name/size combination is invalid (so `FontViewModel.font` falls back to `.monospacedSystemFont(ofSize:weight: .regular)`), then trigger `sync()` | `button.show(_:title:)` is called with exactly the `NSFont` that `viewModel.font` returns (the fallback font); `FontPickerView` performs no validation, clamping, or substitution of its own on this value |
