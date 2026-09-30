<!-- leaf: implement-general-view-1/button-view--edge-cases · source: button-view.md -->

# Button View

## Edge Cases

- **Null/empty input**: `viewModel.title` as an empty string produces a `button` with an empty title and no crash (see button-view-002). `viewModel.wasPressedCallback` as `nil` is the default, documented case (see **takes-no-action-without-callback**).
- **Boundary values**: Not applicable — the only enumerated input, `Placement`, is a closed three-case enum with no numeric range, so there is no minimum/maximum boundary to exercise.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`, so all construction and mutation is serialized to the main actor by the compiler (see **confines-to-main-actor**).
- **Error states**: Not applicable — `ButtonView` has no dependency on network, database, or file-system access. Its only external interaction is invoking `viewModel.wasPressedCallback`, whose error handling, if any, is the caller's responsibility inside that closure, not something `ButtonView` observes or handles.
- **Offline/disconnected state**: Not applicable — `ButtonView` performs no networking.
- **Very long title**: `ButtonView` sets no line-break or truncation mode on `button`; if `viewModel.title` is wider than the space the active `placement` leaves available, `NSButton`'s own default single-line truncation behavior applies unmodified by this component.
