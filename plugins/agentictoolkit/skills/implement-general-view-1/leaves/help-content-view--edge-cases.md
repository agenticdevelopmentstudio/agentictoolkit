<!-- leaf: implement-general-view-1/help-content-view--edge-cases · source: help-content-view.md -->

# HelpContentView

**Rules** (cite as `implement-general-view-1/help-content-view--edge-cases#<slug>`):

- `null-empty-input` MUST — setHelp(nil) and setHelp(HelpContent(topics: [])) both MUST produce the identical single-group empty state (see …

## Edge Cases

- **Null/empty input**: `setHelp(nil)` and `setHelp(HelpContent(topics: []))`
  both MUST produce the identical single-group empty state (see
  **empty-state**; help-content-view-004,
  help-content-view-005) — `content?.topics ?? []` treats a `nil` content
  and an empty `topics` array as the same case.
- **Boundary values**: Not applicable in the numeric-input sense — the
  source enforces no minimum or maximum topic count. A `HelpContent` with
  one topic and one with a hundred topics both render every topic
  (**topic-groups**); the scroll view grows to fit any
  count rather than clipping it.
- **Concurrent access**: Not applicable — the class is `@MainActor`-isolated;
  the Swift compiler rejects construction or mutation of `self`/`content`
  from off the main actor, so there is no concurrent-access surface to
  define behavior for.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no I/O, network call, or dependency lookup of any kind.
- **Offline/disconnected state**: Not applicable — `HelpContentView`
  performs no network operation of its own.
- **Rapid, repeated `setHelp(_:)` calls**: Each call independently tears
  down and rebuilds the panel (**wholesale-replacement**);
  the source contains no debouncing, coalescing, or in-flight guard, so N
  calls in quick succession perform N full rebuilds.
- **`setHelp(_:)` called with an unchanged, equal `HelpContent`**: The
  source performs no equality check against the previously stored
  `content` before rebuilding — even though `HelpContent` is `Equatable` —
  so passing back the same value still discards and rebuilds every group
  and explanation view (**wholesale-replacement**).
- **Very long single topic body**: `ExplanationView` wraps and grows
  vertically with no line limit (per its own recipe), so a very long body
  makes its `GroupView` taller and pushes later groups further down the
  scrollable content; nothing in `HelpContentView.swift` truncates or
  limits it.
- **Constructing via `init(frame:)`**: Not possible. `HelpContentView`
  declares its own designated initializer, `public init()`, and overrides
  none of `NSView`'s designated initializers, so under Swift's initializer
  inheritance rules it inherits neither `init(frame:)` nor `init(coder:)`;
  `HelpContentView(frame:)` does not compile. Unlike sibling
  `ComposableSettings` row views (e.g. `ExplanationView`,
  `DisclosureCardView`), it needs no fatal-error override to block that path —
  `init()` is the only way to build one, and it always installs the title
  label, scroll view, and theme observer.
