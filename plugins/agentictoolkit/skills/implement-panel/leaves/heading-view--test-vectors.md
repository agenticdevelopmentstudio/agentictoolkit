<!-- leaf: implement-panel/heading-view--test-vectors · source: panel-heading-view.md -->

# PanelHeadingView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-heading-view-001 | confines-to-main-actor | Attempt to construct or mutate a `PanelHeadingView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| panel-heading-view-002 | exposes-title-label | Construct `PanelHeadingView(title: "Section")` | `view.titleLabel` is accessible from outside the class and is a `ThemedLabel` instance |
| panel-heading-view-003 | exposes-caption-label | Construct `PanelHeadingView(title: "Section", caption: "Some blurb")` | `view.captionLabel` is non-`nil` and equals the constructed `captionView`'s `label` |
| panel-heading-view-004 | exposes-caption-label | Construct `PanelHeadingView(title: "Section")` (no `caption` argument) | `view.captionLabel` is `nil` |
| panel-heading-view-005 | styles-title-as-primary-heading | Construct `PanelHeadingView(title: "Section")` | `view.titleLabel.role == .primaryText` and `view.titleLabel.textRole == .heading` |
| panel-heading-view-006 | sets-title-text-from-caller | Construct `PanelHeadingView(title: "General")` | `view.titleLabel.stringValue == "General"` |
| panel-heading-view-007 | creates-caption-view-when-caption-given | Construct `PanelHeadingView(title: "Section", caption: "Some blurb")` | The stack's arranged subviews include an `ExplanationView` whose `label.stringValue == "Some blurb"` |
| panel-heading-view-008 | omits-caption-view-when-caption-nil | Construct `PanelHeadingView(title: "Section")` with `caption` defaulted to `nil` | The stack's arranged subviews contain no `ExplanationView`; `view.captionLabel == nil` |
| panel-heading-view-009 | stacks-title-and-caption-vertically-leading-aligned | Construct `PanelHeadingView(title: "Section", caption: "Some blurb")` | The internal stack's `orientation == .vertical`, `alignment == .leading`, and `arrangedSubviews == [titleLabel, captionView]` in that order |
| panel-heading-view-010 | spaces-title-from-caption | Construct the component (with or without a caption) | The internal stack's `spacing == SettingsLayout.default[.captionSpacing]` (currently 6.0) |
| panel-heading-view-011 | matches-caption-width-to-stack | Construct `PanelHeadingView(title: "Section", caption: "Some blurb")` | An active constraint equates `captionView`'s width to the stack's `widthAnchor`; no equivalent constraint exists for `titleLabel` |
| panel-heading-view-012 | fills-bounds-with-zero-inset | Construct the component | Active constraints pin the stack's top/leading/trailing/bottom anchors to the view's corresponding anchors, each with constant `0` |
| panel-heading-view-013 | uses-auto-layout-exclusively | Construct the component | `translatesAutoresizingMaskIntoConstraints == false` on the view, the internal stack, and `titleLabel` |
| panel-heading-view-014 | conforms-to-settings-view-protocol | Any initialized `PanelHeadingView` | `view is SettingsViewProtocol` is `true` |
| panel-heading-view-015 | rejects-frame-initializer | Construct via `PanelHeadingView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))` | Execution traps via `fatalError` with message `init(frame frameRect: NSRect)` |
| panel-heading-view-016 | rejects-coder-initializer | Construct via `PanelHeadingView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |

Vectors 001, 015, and 016 are compile-time or fatal-error trap checks, not
conventional runtime unit tests: 001 verifies a compiler rejection under
`@MainActor` isolation, and 015/016 verify an unconditional `fatalError` trap;
run each as the static or trap check it is.
