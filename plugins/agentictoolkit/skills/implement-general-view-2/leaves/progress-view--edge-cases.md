<!-- leaf: implement-general-view-2/progress-view--edge-cases · source: progress-view.md -->

# ProgressView

## Edge Cases

- **Null/empty input**: `viewModel.progress` is `Double?`; `nil` is the
  documented indeterminate case, not an error (per `ProgressViewModel`'s own
  doc comment). `viewModel.title` is a non-optional, non-empty-guarded
  `String`; an empty string has no observable effect on `ProgressView`
  itself, since the view never reads `title` (see Design Decisions).
- **Boundary values**: `progressIndicator`'s `minValue`/`maxValue` are never
  set by `ProgressView`, leaving `NSProgressIndicator`'s default 0–100
  range in effect. `ProgressView` neither validates nor clamps `progress`
  before assigning it to `doubleValue`; a value at exactly `0.0` or `100.0`
  renders as fully empty or fully filled, and a value outside that range
  (negative, or greater than `100.0`) is passed through to
  `progressIndicator.doubleValue` unmodified — any resulting clamp or
  visual boundary is `NSProgressIndicator`'s own native display behavior,
  not something `ProgressView` governs.
- **Concurrent access**: Not applicable — both
  `ComposableSettings.ProgressView` and `ComposableSettings.ProgressViewModel`
  are `@MainActor`-isolated (**confines-to-main-actor**); the Swift compiler
  enforces that isolation at compile time, and the main actor serializes
  construction, subscription delivery, and `progress` mutation at runtime.
- **Error states**: Not applicable — `ProgressView` performs no network,
  database, or file-system access of its own. It only reflects whatever
  value `viewModel.progress` reports; any error signaling for the
  underlying operation the progress represents is the caller's
  responsibility, outside this component.
- **Offline/disconnected state**: Not applicable — `ProgressView` performs
  no networking.
- **View deallocated mid-progress**: `cancellable` is a stored instance
  property with no explicit `deinit` override in `ProgressView.swift`; when
  the view is deallocated, ARC releases `cancellable`, which cancels the
  Combine subscription through `AnyCancellable`'s own default deinit
  behavior — not custom code in this component.
- **Rapid successive progress updates**: `viewModel.$progress.sink` delivers
  each published value synchronously, in order, on the actor `progress` is
  mutated from (the main actor, per `@MainActor` isolation); `progressIndicator`
  is updated once per published value, with no debouncing, throttling, or
  coalescing in source.
