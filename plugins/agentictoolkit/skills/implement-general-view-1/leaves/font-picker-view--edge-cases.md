<!-- leaf: implement-general-view-1/font-picker-view--edge-cases · source: font-picker-view.md -->

# FontPickerView

## Edge Cases

- **Null/empty input**: `viewModel` (`FontViewModel`) is a non-optional,
  non-escaping-typed constructor parameter; Swift's type system rules out
  `nil`. The component provides, and needs, no nil-handling path for its
  one initializer parameter.
- **Boundary values**: Neither `FontPickerView.swift` nor `FontViewModel.swift`
  clamps or validates `sizeObserver.value` (a plain `Double` persisted via
  `UserSetting<Double>`) before constructing `NSFont(name:size:)` in
  `FontViewModel.font`. An arbitrary stored size (including zero, negative,
  or extremely large values) is passed straight through with no validation
  in either file. If `NSFont(name:size:)` returns `nil` for that
  combination, `FontViewModel.font` falls back to
  `.monospacedSystemFont(ofSize:weight: .regular)` - the same fallback path
  used for an uninstalled font name (see next item). That fallback is
  `FontViewModel.font`'s responsibility, not `FontPickerView`'s -
  `FontPickerView.sync()` reads `viewModel.font` unconditionally and passes
  it straight to `button.show(_:title:)`. See
  **delegates-font-resolution-fallback**.
- **Concurrent access**: Not applicable - the class is `@MainActor`-isolated,
  so Swift's concurrency checker serializes all access to the main actor;
  there is no code path by which two threads can mutate the view
  simultaneously.
- **Error states**: Not applicable - every operation in
  `FontPickerView.swift` (the button's target-action, `viewModel.setFont`,
  and the `sync()` reads) is a synchronous, non-throwing call; no `try`,
  `Result`, or error-producing API appears in source.
- **Offline/disconnected**: Not applicable - the component performs no
  networking of its own; it only reads from and writes to an in-process
  `FontViewModel`.
- **Overwritten external observer**: `viewModel.onChange` is a single
  closure property. `FontPickerView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.sync() }`, replacing
  whatever handler (if any) was previously registered on that
  `FontViewModel` instance (see **overwrites-existing-view-model-observer**).
- **Repeated sync after a single font pick**: Picking a font that changes
  both the stored name and size fires `sync()` more than once for one user
  action. `button.onChange`'s closure calls `viewModel.setFont(font)` then
  `self.sync()` synchronously. `FontViewModel.setFont(_:)` writes
  `nameObserver.value` and `sizeObserver.value` only when each differs from
  its current value; each write that actually occurs independently triggers
  that observer's `UserSettingObserver.onChange` on the *next main-queue
  turn* (the `.receive(on: DispatchQueue.main)` hop documented in
  `UserSetting.swift`), which calls `FontViewModel.onChange?(self.font)`,
  i.e. `FontPickerView`'s `sync()`-calling closure, again. So picking a
  font that changes both name and size results in one synchronous `sync()`
  call plus up to two further asynchronous `sync()` calls; picking the
  exact font already stored (both guards fail) results in exactly one
  `sync()` call. The component performs no debouncing or deduplication of
  these repeated calls; because `sync()` always re-reads current state
  rather than accumulating it, the redundant calls are observably
  idempotent (see **resyncs-synchronously-after-a-pick**).
- **Reassigning an unchanged label**: `sync()` unconditionally reassigns
  `label.stringValue = viewModel.title` on every call, even though
  `viewModel.title` is a `let` on `AbstractViewModel` and can never change
  after construction. The component performs no early-exit/equality check
  before this reassignment (see **redraws-label-text-on-every-sync**).
- **Toggling `isEnabled` to its current value**: `isEnabled`'s `didSet`
  reassigns `button.isEnabled` and `label.alphaValue` on every assignment,
  including a reassignment to the value `isEnabled` already holds; Swift's
  `didSet` carries no built-in equality guard, and source adds none (see
  **dims-and-disables-the-row**).
