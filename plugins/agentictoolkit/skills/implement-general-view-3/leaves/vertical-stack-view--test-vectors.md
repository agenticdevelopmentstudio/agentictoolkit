<!-- leaf: implement-general-view-3/vertical-stack-view--test-vectors · source: vertical-stack-view.md -->

# Vertical Stack View

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| vertical-stack-view-001 | confines-to-main-actor | Static check (not a runtime test): inspect the `VerticalStackView` class declaration | `class VerticalStackView` carries the `@MainActor` attribute, which the Swift compiler then enforces at compile time for every construct/mutate call from off the main actor |
| vertical-stack-view-002 | disables-autoresizing-mask-translation | Any initialized `VerticalStackView` | `view.translatesAutoresizingMaskIntoConstraints == false` |
| vertical-stack-view-003 | wraps-a-vertical-nsstackview | Any initialized `VerticalStackView` | `view.stackView.orientation == .vertical` |
| vertical-stack-view-004 | sets-arranged-subview-spacing-from-group-spacing-token | Any initialized `VerticalStackView` | `view.stackView.spacing == SettingsLayout.default[.groupSpacing]` |
| vertical-stack-view-005 | disables-autoresizing-mask-translation-on-inner-stack-view | Any initialized `VerticalStackView` | `view.stackView.translatesAutoresizingMaskIntoConstraints == false` |
| vertical-stack-view-006 | adds-stack-view-as-subview | Any initialized `VerticalStackView` | `view.stackView` is present in `view.subviews` |
| vertical-stack-view-007 | pins-stack-view-to-container-edges | Any initialized `VerticalStackView`, laid out in a window with a non-zero frame | `view.constraints` contains four active constraints linking `view.stackView`'s top/leading/trailing/bottom anchors to the corresponding anchors of `view`, and (after layout) `view.stackView`'s frame exactly matches `view.bounds` |
| vertical-stack-view-008 | exposes-stack-view-as-public-property | From outside the type, read `view.stackView` | The property compiles and is accessible (public access level), and returns the same `NSStackView` instance that `addArrangedSubview(_:)` forwards to |
| vertical-stack-view-009 | ignores-explicit-frame | Construct via `VerticalStackView(frame: NSRect(x: 10, y: 10, width: 200, height: 50))` | `view.frame == .zero` immediately after `init(frame:)` returns, before any layout pass runs |
| vertical-stack-view-010 | convenience-init-uses-zero-frame | Construct via `VerticalStackView()` | No crash; behavior identical to `VerticalStackView(frame: .zero)` |
| vertical-stack-view-011 | rejects-coder-initializer | Construct via `VerticalStackView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |
| vertical-stack-view-012 | forwards-added-views-to-inner-stack-view | Construct a `VerticalStackView`, then call `addArrangedSubview(childView)` | `childView` appears in `view.stackView.arrangedSubviews`, in the order it was added |
| vertical-stack-view-013 | conforms-to-settings-view-protocol | Any initialized `VerticalStackView` | `view is SettingsViewProtocol` is `true` |
