<!-- leaf: implement-general-view-1/header-view--test-vectors · source: header-view.md -->

# Header View

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| header-view-001 | confines-to-main-actor | Attempt to construct or mutate a `HeaderView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking (a static/compile-time check — not executable by a runtime conformance test runner; verify by confirming the `@MainActor` annotation on the declaration instead) |
| header-view-002 | exposes-title-label | Construct `HeaderView(title: "Section")` | `view.titleLabel` is accessible from outside the class and is a `ThemedLabel` instance |
| header-view-003 | conforms-to-settings-view-protocol | Any initialized `HeaderView` | `view is SettingsViewProtocol` is `true` |
| header-view-004 | disables-autoresizing-mask-translation | Any initialized `HeaderView` | `view.translatesAutoresizingMaskIntoConstraints == false` |
| header-view-005 | creates-title-label-with-secondary-caption-style | Construct `HeaderView(title: "Section")` | `view.titleLabel.role == .secondaryText` and `view.titleLabel.textRole == .caption` |
| header-view-006 | sets-title-label-initial-text | Construct `HeaderView(title: "General")` | `view.titleLabel.stringValue == "General"` |
| header-view-007 | pins-title-label-to-all-four-edges | Construct `HeaderView(title: "Section")`, add it to a window inside a fixed 200×20-point superview frame, and call `view.layoutSubtreeIfNeeded()` | `view.titleLabel.translatesAutoresizingMaskIntoConstraints == false`, `view.subviews.contains(view.titleLabel)` is `true`, and `view.titleLabel.frame` equals `view.bounds` exactly (top, leading, trailing, and bottom all at zero offset) |
| header-view-008 | rejects-frame-initializer | Construct via `HeaderView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))` | Execution traps via `fatalError`; the diagnostic message is the source's own malformed text (see **Design Decisions**) and is not asserted verbatim here |
| header-view-009 | rejects-coder-initializer | Construct via `HeaderView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |
