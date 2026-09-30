<!-- leaf: implement-general-view-2/horizontal-stack-view--test-vectors · source: horizontal-stack-view.md -->

# Horizontal Stack View

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| horizontal-stack-view-001 | confines-to-main-actor | Attempt to construct or mutate a `HorizontalStackView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking. This is a static/compile-time check, not one a runtime conformance suite executes. |
| horizontal-stack-view-002 | disables-autoresizing-mask-translation | Any initialized `HorizontalStackView` | `view.translatesAutoresizingMaskIntoConstraints == false` |
| horizontal-stack-view-003 | wraps-a-horizontal-nsstackview | `let stack = view.subviews.first as? NSStackView` on any initialized `HorizontalStackView` (`stackView` is `private`, so this is how a test reaches it) | `stack?.orientation == .horizontal` |
| horizontal-stack-view-004 | group-spacing | `let stack = view.subviews.first as? NSStackView` on any initialized `HorizontalStackView` | `stack?.spacing == SettingsLayout.default[.groupSpacing]` |
| horizontal-stack-view-005 | inner-stack-constraints-only | `let stack = view.subviews.first as? NSStackView` on any initialized `HorizontalStackView` | `stack?.translatesAutoresizingMaskIntoConstraints == false` |
| horizontal-stack-view-006 | adds-stack-view-as-subview | Any initialized `HorizontalStackView` | `view.subviews.first is NSStackView` (the internal stack view is `view`'s only subview) |
| horizontal-stack-view-007 | pins-stack-view-to-container-edges | `let stack = view.subviews.first as? NSStackView` on any initialized `HorizontalStackView`, laid out in a window with a non-zero frame | `stack?.frame` exactly matches `view.bounds` (top/leading/trailing/bottom anchors resolve equal) |
| horizontal-stack-view-008 | ignores-explicit-frame | Construct via `HorizontalStackView(frame: NSRect(x: 10, y: 10, width: 200, height: 50))` | `view.frame == .zero` immediately after `init`, before any layout pass runs |
| horizontal-stack-view-009 | convenience-init-uses-zero-frame | Construct via `HorizontalStackView()` | No crash; behavior identical to `HorizontalStackView(frame: .zero)` |
| horizontal-stack-view-010 | rejects-coder-initializer | Construct via `HorizontalStackView(coder:)` with any `NSCoder` | Execution traps via `fatalError` (any trap message satisfies the requirement; the source's is `init(coder:) has not been implemented`, see Platform Notes) |
| horizontal-stack-view-011 | forwards-added-views-to-inner-stack-view | Construct a `HorizontalStackView`, obtain `let stack = view.subviews.first as? NSStackView`, then call `view.addArrangedSubview(childView)` | `childView` appears in `stack?.arrangedSubviews`, in the order it was added |
| horizontal-stack-view-012 | conforms-to-settings-view-protocol | Any initialized `HorizontalStackView` | `view is SettingsViewProtocol` is `true` |
