<!-- leaf: implement-general-view-2/progress-view--test-vectors · source: progress-view.md -->

# ProgressView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| progress-view-001 | constructs-progress-indicator-at-regular-control-size | `ProgressView(viewModel: vm)` | `view.progressIndicator.controlSize == .regular` |
| progress-view-002 | exposes-progress-indicator-publicly | Any initialized `ProgressView` | `view.progressIndicator` is externally accessible and is the same `NSProgressIndicator` instance added as its subview |
| progress-view-003 | uses-constraint-based-layout | Any initialized `ProgressView` | `view.translatesAutoresizingMaskIntoConstraints == false` and `view.progressIndicator.translatesAutoresizingMaskIntoConstraints == false` |
| progress-view-004 | adds-progress-indicator-as-subview | Any initialized `ProgressView` | `view.subviews` contains `view.progressIndicator` |
| progress-view-005 | pins-progress-indicator-to-edges | Host view laid out at a fixed frame, e.g. 200×20 | `progressIndicator`'s resolved frame equals the host view's frame exactly, with zero inset on all four edges |
| progress-view-006 | reflects-initial-progress-value | `ProgressViewModel(title: "T", progress: 0.5)` | Immediately after `init`, `progressIndicator.isIndeterminate == false` and `progressIndicator.doubleValue == 0.5` |
| progress-view-007 | reflects-initial-progress-value | `ProgressViewModel(title: "T")` (default `progress: nil`) | Immediately after `init`, `progressIndicator.isIndeterminate == true` |
| progress-view-008 | tracks-progress-changes | Construct with `progress: 0.2`, then set `viewModel.progress = 0.9` | `progressIndicator.doubleValue` becomes `0.9`; `isIndeterminate` remains `false` |
| progress-view-009 | tracks-progress-changes | Construct with `progress: 0.2`, then set `viewModel.progress = nil` | `progressIndicator.isIndeterminate` becomes `true` |
| progress-view-010 | shows-determinate-bar-for-non-nil-progress | Set `viewModel.progress = 42.0` | `progressIndicator.isIndeterminate == false`; `progressIndicator.doubleValue == 42.0`; the indicator's animation is stopped |
| progress-view-011 | shows-indeterminate-animation-for-nil-progress | Set `viewModel.progress = nil` | `progressIndicator.isIndeterminate == true`; the indicator's animation is running |
| progress-view-012 | continues-updates-while-retained | Construct the view, keep no external reference to its Combine subscription, then set `viewModel.progress` to three different values in turn | `progressIndicator` updates on every one of the three changes |
| progress-view-013 | rejects-frame-initializer | Construct via `ProgressView(frame: .zero)` | Execution traps via `fatalError` with message `init(frame frameRect: NSRect` |
| progress-view-014 | rejects-coder-initializer | Construct via `ProgressView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |
| progress-view-015 | confines-to-main-actor | Attempt to construct or mutate a `ProgressView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |

progress-view-006, -008, and -009 use progress values in a 0–1-normalized
range (0.5, 0.2, 0.9) while progress-view-010 uses the source's native 0–100
range (42.0); `ProgressView` passes `viewModel.progress` through to
`progressIndicator.doubleValue` unmodified regardless of scale — the consumer
chooses the scale (see the Design Decision on `minValue`/`maxValue` below).
progress-view-015 is a static, compile-time check: `@MainActor` isolation is
enforced by the Swift compiler and verified by the build, not by a runtime
assertion.
