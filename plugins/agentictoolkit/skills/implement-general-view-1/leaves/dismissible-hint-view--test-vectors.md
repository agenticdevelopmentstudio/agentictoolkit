<!-- leaf: implement-general-view-1/dismissible-hint-view--test-vectors · source: dismissible-hint-view.md -->

# DismissibleHintView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| dismissible-hint-view-001 | text-label | `DismissibleHintView(text: "Enable launch at login", dismissedSetting: setting)` | `textLabel.stringValue == "Enable launch at login"`; `textLabel` wraps rather than truncates |
| dismissible-hint-view-002 | #platforms/swift | Construct the component, then read `.textLabel` from outside the type | Returns the same `NSTextField` instance the view displays |
| dismissible-hint-view-003 | text-label-theming | Construct the component, then trigger a theme change | `textLabel.textColor` and `textLabel.font` update to the new theme's secondary-text color and `.caption` font, both immediately at construction and again after the change |
| dismissible-hint-view-004 | dismiss-button-title | `DismissibleHintView(text: "…", dismissedSetting: setting, buttonTitle: "Dismiss")` | `dismissButton.title == "Dismiss"` |
| dismissible-hint-view-005 | dismiss-button-title-default | `DismissibleHintView(text: "…", dismissedSetting: setting)` (no `buttonTitle`) | `dismissButton.title == "Got It"` |
| dismissible-hint-view-006 | #platforms/swift | Construct the component, then read `.dismissButton` from outside the type | Returns the same `NSButton` instance the view displays |
| dismissible-hint-view-007 | dismiss-button-style | Construct the component | `dismissButton.bezelStyle == .rounded`; `dismissButton.controlSize == .small` |
| dismissible-hint-view-008 | dismiss-button-action | Construct the component, then simulate a click on `dismissButton` | The dismiss handler runs (verified by `dismiss-persistence`'s effect) |
| dismissible-hint-view-009 | stack-arrangement | Construct the component | The internal stack's `orientation == .vertical`, `alignment == .leading`, with `textLabel` before `dismissButton` in `arrangedSubviews` |
| dismissible-hint-view-010 | stack-spacing | Construct the component | The internal stack's `spacing == SettingsLayout.default[.rowSpacing]` (8pt) |
| dismissible-hint-view-011 | #platforms/swift | Construct the component | Active constraints pin the stack's top/leading/trailing/bottom anchors to the view's corresponding anchors, each with constant `0` |
| dismissible-hint-view-012 | #platforms/swift | Construct the component | `view.translatesAutoresizingMaskIntoConstraints == false` and the internal stack's is also `false` |
| dismissible-hint-view-013 | dismissed-setting-observation | Construct with a given `dismissedSetting` | The view's internal observer wraps that exact `UserSetting<Bool>` instance |
| dismissible-hint-view-014 | initial-visibility | Construct with `dismissedSetting.currentValue == true` | Immediately after `init` returns, `view.isHidden == true`, with no `onVisibilityChange` call |
| dismissible-hint-view-015 | initial-visibility | Construct with `dismissedSetting.currentValue == false` | Immediately after `init` returns, `view.isHidden == false` |
| dismissible-hint-view-016 | visibility-update | After construction with `isHidden == false`, change the setting's value to `true` and allow `onChange` to deliver | `view.isHidden == true` after delivery |
| dismissible-hint-view-017 | visibility-write-guard | With `view.isHidden == true` and a KVO observer registered on `isHidden`, cause `onChange` to redeliver `true` again | The KVO observer receives zero notifications for this delivery, and `onVisibilityChange`'s call count stays at zero |
| dismissible-hint-view-018 | visibility-change-notification | Register `onVisibilityChange`, then change the setting from `false` to `true` | `onVisibilityChange` is called exactly once, after `view.isHidden` has already become `true` |
| dismissible-hint-view-019 | visibility-change-callback | Assign a closure to `.onVisibilityChange` from outside the type, then trigger a visibility change | The assigned closure is the one invoked |
| dismissible-hint-view-020 | dismiss-persistence | Click `dismissButton` | `dismissedSetting`'s persisted value becomes `true` |
| dismissible-hint-view-021 | #platforms/swift | Attempt `DismissibleHintView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| dismissible-hint-view-022 | #platforms/swift | Attempt `DismissibleHintView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| dismissible-hint-view-023 | main-actor-confinement | Attempt to construct or mutate a `DismissibleHintView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| dismissible-hint-view-024 | self-hiding-conformance | Construct the component, then inspect its static type | `DismissibleHintView` conforms to both `SelfHidingSettingsView` and `SettingsViewProtocol` |

Vector `dismissible-hint-view-023` is a static/compile-time type check (Swift's
`@MainActor` isolation checking), not a runtime conformance assertion; vector
`dismissible-hint-view-024` is likewise a static/type-check vector (protocol
conformance), not a runtime behavior assertion.
