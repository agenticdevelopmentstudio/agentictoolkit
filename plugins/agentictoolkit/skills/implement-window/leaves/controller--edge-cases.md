<!-- leaf: implement-window/controller--edge-cases · source: window-controller.md -->

# WindowController

**Rules** (cite as `implement-window/controller--edge-cases#<slug>`):

- `null-empty-input` MUST — contentViewController reassigned to nil after construction (it is a settable, inherited NSViewController? property) — …

## Edge Cases

- **Null/empty input**: `contentViewController` reassigned to `nil` after
  construction (it is a settable, inherited `NSViewController?` property) —
  `viewController` returns `nil` rather than crashing, per
  **returns-nil-for-non-matching-content-view-controller**. MUST.
- **Boundary values**: Not applicable — `ViewControllerType` and `ViewType`
  are reference-type generic constraints, not measured or bounded inputs.
- **Concurrent access**: `WindowController<ViewControllerType>` is
  `@MainActor`-isolated by inheritance from `SingleWindowController`'s
  explicit `@MainActor` (Swift's global-actor inheritance rule).
  `WindowContentViewController<ViewType>` declares no explicit `@MainActor`
  of its own, but `NSViewController` itself is `@MainActor`-isolated in the
  AppKit overlay, so the subclass inherits that isolation the same way.
  Neither type adds an additional concurrency guard of its own.
- **Error states**: Not applicable beyond the deliberate `fatalError` in
  `init?(coder:)` — no throwing or failable API exists in the component.
- **Offline/disconnected state**: Not applicable — the component has no
  network dependency.
