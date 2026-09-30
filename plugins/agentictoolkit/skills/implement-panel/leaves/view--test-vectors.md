<!-- leaf: implement-panel/view--test-vectors · source: panel-view.md -->

# PanelView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-view-001 | settings-view-conformance | Construct `PanelView()` | `view is SettingsViewProtocol` is `true` |
| panel-view-002 | main-actor-confinement | (Static/compile-time check) Attempt to construct or mutate a `PanelView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| panel-view-003 | zero-argument-convenience-initializer | Construct `PanelView()` | Succeeds and produces a fully initialized view with its internal stack view and theme observer set up |
| panel-view-004 | see Design Decisions | Construct `PanelView(frame: NSRect(x: 10, y: 10, width: 300, height: 300))`, checked immediately after `init` returns, before layout | The resulting view's frame is `.zero`, not the supplied rect |
| panel-view-005 | self-autoresizing-mask | Construct the component | `view.translatesAutoresizingMaskIntoConstraints == false` |
| panel-view-006 | layer-backing | Construct the component | `view.wantsLayer == true` and `view.layer` is non-nil |
| panel-view-007 | vertical-leading-stack-alignment | Construct the component | The internal stack's `orientation == .vertical`, `alignment == .leading` |
| panel-view-008 | group-spacing | Construct the component | The internal stack's `spacing == 20.0` |
| panel-view-009 | stack-autoresizing-mask | Construct the component | The internal stack's `translatesAutoresizingMaskIntoConstraints == false` |
| panel-view-010 | top-leading-trailing-inset | Construct the component | Active constraints pin the stack's top/leading/trailing anchors to the view's corresponding anchors, each with constant `20.0` inward |
| panel-view-011 | bottom-inset-inequality | Inspect the component's active constraints | A `lessThanOrEqualTo` constraint relates the stack's bottom anchor to the view's bottom anchor with constant `-20.0`; no equality constraint exists between them |
| panel-view-012 | construction-time-background-paint | Construct the component under a known theme | `layer?.backgroundColor` equals that theme's `windowBackgroundColor.cgColor` immediately after `init` returns |
| panel-view-013 | theme-change-background-repaint | Construct the component, then switch the active theme | `layer?.backgroundColor` updates to the new theme's `windowBackgroundColor.cgColor` |
| panel-view-014 | theme-observer-retention | Construct the component, trigger a theme change some time later | The background still repaints (proving the observer was not deallocated between construction and the change) |
| panel-view-015 | coder-initializer-rejection | Construct via `PanelView(coder: someCoder)` | Execution traps via `fatalError`; the source's current message text is `not overridden` (not required by this requirement — see Design Decisions) |
| panel-view-016 | group-arranged-subview-append | `addGroup(someGroupView)` | `someGroupView` is an arranged subview of the internal stack, at the end |
| panel-view-017 | heading-construction | `addHeading("Section", caption: "Some blurb")` | A `PanelHeadingView` is constructed with `title == "Section"` and `caption == "Some blurb"` forwarded to its initializer (see the panel-heading-view recipe for how these values render) |
| panel-view-018 | heading-caption-default | `addHeading("Section")` with no `caption` argument | The constructed `PanelHeadingView` receives `caption == nil` (see the panel-heading-view recipe for its own nil-caption behavior) |
| panel-view-019 | heading-gap | `addGroup(someGroupView)` then `addHeading("Section")` | The stack's custom spacing after `someGroupView` is `30.0` |
| panel-view-020 | empty-stack-spacing-skip | `addHeading("Section")` as the first call on a freshly constructed component | No custom spacing is set (the stack has no prior arranged subview); no crash occurs |
| panel-view-021 | heading-arranged-subview-append | `addHeading("Section")` | The returned `PanelHeadingView` is an arranged subview of the internal stack, at the end |
| panel-view-022 | heading-width-match | `addHeading("Section")` | An active constraint equates the returned heading's `widthAnchor` to the internal stack's `widthAnchor` |
| panel-view-023 | heading-return | `let heading = addHeading("Section")` | `heading` is the same `PanelHeadingView` instance added to the stack; the caller can ignore the return value with no compiler warning |
