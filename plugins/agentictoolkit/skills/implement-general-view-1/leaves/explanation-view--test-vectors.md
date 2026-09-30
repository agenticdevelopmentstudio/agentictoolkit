<!-- leaf: implement-general-view-1/explanation-view--test-vectors · source: explanation-view.md -->

# ExplanationView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| explanation-view-001 | renders-caller-text | `ExplanationView(withText: "Some text")` | `label.stringValue == "Some text"` |
| explanation-view-002 | wraps-across-lines | Construct the view | `label.cell?.wraps == true`; `label.cell?.usesSingleLineMode == false`; `label.lineBreakMode == .byWordWrapping`; `label.maximumNumberOfLines == 0` |
| explanation-view-003 | compresses-and-hugs-loosely-horizontally | Construct the view | `label.contentCompressionResistancePriority(for: .horizontal) == .defaultLow`; `label.contentHuggingPriority(for: .horizontal) == .defaultLow` |
| explanation-view-004 | resists-vertical-compression | Construct the view | `label.contentCompressionResistancePriority(for: .vertical) == .required` |
| explanation-view-005 | fills-view-edge-to-edge | Construct the view, then lay it out inside a fixed-size superview | The label's resolved frame has zero inset from `ExplanationView`'s frame on all four edges |
| explanation-view-006 | exposes-label-property | Construct the view, then access `.label` from outside the type | The property is accessible and returns the same `NSTextField` instance built during init |
| explanation-view-007 | styles-as-secondary-caption | Construct the view | `label.font` equals the active theme's `.caption` font; `label.textColor` equals the active theme's `.secondaryText` color |
| explanation-view-008 | requires-text-at-construction | Attempt `ExplanationView(frame: .zero)` | The call traps with a fatal error; no instance is returned. Unavailable as a normal in-process assertion — XCTest cannot catch a Swift `fatalError`; this requires a crash-test harness or a compile-time/unavailable check instead. |
| explanation-view-009 | requires-text-at-construction | Attempt `ExplanationView(coder: someCoder)` | The call traps with a fatal error; no instance is returned. Unavailable as a normal in-process assertion — XCTest cannot catch a Swift `fatalError`; this requires a crash-test harness or a compile-time/unavailable check instead. |
