<!-- leaf: implement-general-view-1/conditional-view--test-vectors · source: conditional-view.md -->

# ConditionalView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| conditional-view-001 | adds-child-as-only-subview | Construct `ConditionalView` with any `setting`, `child`, `isVisible` | `child` is a subview of the constructed view; it is the only subview added by `ConditionalView` |
| conditional-view-002 | fills-container-with-child | Construct `ConditionalView` | `view.translatesAutoresizingMaskIntoConstraints == false` and `child.translatesAutoresizingMaskIntoConstraints == false` |
| conditional-view-003 | fills-container-with-child | Construct `ConditionalView` | Active constraints pin `child`'s top/leading/trailing/bottom anchors to the container's corresponding anchors, each with constant `0` |
| conditional-view-004 | evaluates-initial-visibility | Construct with `setting.currentValue` such that `isVisible(value) == false` | Immediately after `init` returns, `view.isHidden == true` — no change notification required |
| conditional-view-005 | evaluates-initial-visibility | Construct with `setting.currentValue` such that `isVisible(value) == true` | Immediately after `init` returns, `view.isHidden == false` |
| conditional-view-006 | reevaluates-visibility-on-setting-change | After construction, change the observed setting's value so `isVisible` now returns a different result, then spin the main run loop once (or await the next main-queue turn) so the observer's `onChange` delivers | `view.isHidden` reflects the new `isVisible` result after `onChange` fires |
| conditional-view-007 | hides-when-predicate-returns-false | Construct visible (`isHidden == false`), then change the setting to a value where `isVisible(value) == false`, then spin the main run loop once (or await the next main-queue turn) | After `onChange` delivers, `view.isHidden == true` |
| conditional-view-008 | shows-when-predicate-returns-true | Construct hidden (`isHidden == true`), then change the setting to a value where `isVisible(value) == true`, then spin the main run loop once (or await the next main-queue turn) | After `onChange` delivers, `view.isHidden == false` |
| conditional-view-009 | skips-redundant-visibility-writes | With `view.isHidden == true`, change the setting to a different value for which `isVisible(value)` is still `false`, then spin the main run loop once (or await the next main-queue turn) | `onVisibilityChange` is not called for this change, and — observed via a spy subclass overriding the `isHidden` property, or by counting `onVisibilityChange` invocations — `isHidden`'s setter is confirmed not invoked again |
| conditional-view-010 | notifies-visibility-change-once | Register `onVisibilityChange`, then change the setting so `isVisible(value)` flips from `true` to `false`, then spin the main run loop once (or await the next main-queue turn) | `onVisibilityChange` is called exactly once, after `view.isHidden` has already become `true` |
| conditional-view-011 | exposes-child-property | Construct the component, then read `.child` from outside the type | Returns the same `NSView` instance passed into the initializer |
| conditional-view-012 | exposes-visibility-change-callback | Assign a closure to `.onVisibilityChange` from outside the type, then trigger a visibility change | The assigned closure is the one invoked |
| conditional-view-013 | restricts-construction-to-designated-initializer | Attempt `ConditionalView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| conditional-view-014 | restricts-construction-to-designated-initializer | Attempt `ConditionalView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| conditional-view-015 | confines-to-main-actor | Static/build-time check, not a runtime assertion: attempt to construct or mutate a `ConditionalView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| conditional-view-016 | reflects-setting-change-asynchronously | Change the observed setting's value, then synchronously — in the same call frame, before the run loop spins — read `view.isHidden` | `view.isHidden` still reflects the pre-change visibility; only after the main run loop spins once (or the next main-queue turn) does `view.isHidden` reflect the new value |
