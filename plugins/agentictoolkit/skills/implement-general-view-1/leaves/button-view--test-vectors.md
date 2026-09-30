<!-- leaf: implement-general-view-1/button-view--test-vectors · source: button-view.md -->

# Button View

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| button-view-001 | creates-button-with-viewmodel-title | `ButtonViewModel(title: "Save")` | `button.title == "Save"` |
| button-view-002 | creates-button-with-viewmodel-title | `ButtonViewModel(title: "")` | `button.title == ""`; no crash |
| button-view-003 | exposes-button-publicly | Any initialized `ButtonView` | `view.button` is externally accessible and is the same `NSButton` instance added as its subview |
| button-view-004 | disables-autoresizing-mask-translation | Any initialized `ButtonView` | `view.translatesAutoresizingMaskIntoConstraints == false` and `view.button.translatesAutoresizingMaskIntoConstraints == false` |
| button-view-005 | adds-button-as-subview | Any initialized `ButtonView` | `view.subviews` contains `view.button` |
| button-view-006 | defaults-placement-to-fill | `ButtonView(viewModel: vm)` with no `placement` argument | Resulting layout matches the `.fill` behavior in button-view-007 |
| button-view-007 | fills-view-in-fill-placement | `placement: .fill`, host view laid out at 200×40 | `button`'s frame equals (0, 0, 200, 40) |
| button-view-008 | constrains-vertical-edges-in-non-fill-placement | `placement: .leading`, host view laid out at 200×40 | `button`'s top and bottom edges equal the host view's top and bottom edges (button height == 40) |
| button-view-009 | caps-trailing-edge-in-non-fill-placement | `placement: .leading`, `viewModel.title`'s intrinsic width exceeds the host view's width | `button`'s trailing edge does not exceed the host view's trailing edge |
| button-view-010 | aligns-leading-edge-in-leading-placement | `placement: .leading` | `button`'s leading edge equals the host view's leading edge |
| button-view-011 | floors-leading-edge-in-centered-placement | `placement: .centered`, host view wider than `button`'s intrinsic width | `button`'s leading edge is greater than or equal to the host view's leading edge |
| button-view-012 | centers-button-in-centered-placement | `placement: .centered`, host view laid out at 200×40 | `button`'s horizontal center equals the host view's horizontal center (x == 100) |
| button-view-013 | wires-button-action | Any initialized `ButtonView` | `button.target === view`; `button.action == Selector("buttonWasPressed:")` |
| button-view-014 | invokes-pressed-callback | `viewModel.wasPressedCallback` set to a closure that flips a flag; simulate a click on `button` | The flag is `true` after the click |
| button-view-015 | takes-no-action-without-callback | `viewModel.wasPressedCallback == nil`; simulate a click on `button` | No exception is thrown; `button.target` and `button.action` are unchanged from **wires-button-action**; no call is observed on a spy substituted for any other collaborator |
| button-view-016 | rejects-frame-initializer | Construct via `ButtonView(frame: .zero)` | Execution traps via `fatalError` with message `init(frame frameRect: NSRect` |
| button-view-017 | rejects-coder-initializer | Construct via `ButtonView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |
| button-view-018 | confines-to-main-actor | Attempt to construct or mutate a `ButtonView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| button-view-019 | placement-fixed-at-init | Any initialized `ButtonView` | `ButtonView`'s public interface exposes no property or method that reads or changes `placement`; the only code that consults `placement` runs once, inside `init` |
| button-view-020 | reads-title-once-at-init | Any initialized `ButtonView` | `button.title` was set from `viewModel.title` during `init` and by no other code path; `ButtonViewModel.title` is `let`, so no later value could exist for the component to re-read |
| button-view-021 | retains-view-model-strongly | Construct `let view = ButtonView(viewModel: ButtonViewModel(title: "Save") { flag = true })` in a scope where no other strong reference to the view model is kept; after the scope exits (only `view` remains reachable), simulate a click on `view.button` | The callback still fires and `flag` becomes `true`, showing `view` alone kept `viewModel` (and its closure) alive after every other reference was dropped |

`button-view-018` and `button-view-019` are static, code-inspection checks
(Swift's `@MainActor` isolation checking rejects an off-actor call at compile
time; `placement` having no reachable getter/setter is a fact about the
type's public interface), not vectors observed by running the program; a
port on a platform without the equivalent compile-time enforcement should
verify these as build-verification or API-surface review notes rather than
runtime tests.
