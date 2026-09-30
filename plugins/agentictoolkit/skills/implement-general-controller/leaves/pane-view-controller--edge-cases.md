<!-- leaf: implement-general-controller/pane-view-controller--edge-cases · source: pane-view-controller.md -->

# PaneViewController

**Rules** (cite as `implement-general-controller/pane-view-controller--edge-cases#<slug>`):

- `null-empty-input` MUST (MUST) — makeContentViewController() returning nil results in a working, empty pane rather than a failure …
- `boundary-values` MUST (MUST) — A stored spacing override outside the 0...40 range — written by an older build, or edited by hand — is clamped back …
- `concurrent-access` MUST (MUST) — This class is @MainActor-isolated, and every piece of mutable state it owns is read and written only on the main actor, …
- `error-states` MUST (MUST) — A JSONEncoder/JSONDecoder failure while persisting or reading the spacing override is silently ignored — the write or …

## Edge Cases

- **Null/empty input** (MUST): `makeContentViewController()` returning `nil` results in a working, empty pane rather than a failure (`no-content-is-supported`). A spacing-override JSON string that fails to decode (`spacing-decode-failure-is-absent`), or a minimize-edge string that fails to parse as a `PaneEdge` (`unparseable-stored-edge-ignored`), is treated as absent rather than as an error.
- **Boundary values** (MUST): A stored spacing override outside the `0...40` range — written by an older build, or edited by hand — is clamped back into range on read, never rejected outright (`spacing-clamped-on-read`). `contentInset` of `0`, the default, means `minimizedThickness(for:)` reduces to exactly the docked chrome's own thickness (26pt for a vertical edge, 28pt for a horizontal one) with no border allowance added.
- **Concurrent access** (MUST): This class is `@MainActor`-isolated, and every piece of mutable state it owns is read and written only on the main actor, so there is no concurrent-access hazard by construction. The one timing subtlety is `PaneSpacingOverride`'s 300ms coalescing timer for persisted spacing writes: it still fires on the main queue, not a background thread, so it introduces no data race — only a bounded lag between a drag gesture and its write reaching the store (see Design Decisions).
- **Error states** (MUST): A `JSONEncoder`/`JSONDecoder` failure while persisting or reading the spacing override is silently ignored — the write or read simply does not happen, with no error surfaced to the caller or the user. This is the source's actual behavior, described as-is rather than as an idealized richer error path; `PaneStateStore`'s two methods return no error value at all, so there is no channel for this class to report through even if it wanted to.
- **Offline or disconnected state**: Not applicable. This component makes no network request of any kind; its only persistence goes through the injected `PaneStateStore`, and nothing in this file references a network resource.
