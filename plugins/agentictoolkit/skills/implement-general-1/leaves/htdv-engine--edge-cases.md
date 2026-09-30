<!-- leaf: implement-general-1/htdv-engine--edge-cases · source: htdv-engine.md -->

# HTDV Engine

**Rules** (cite as `implement-general-1/htdv-engine--edge-cases#<slug>`):

- `null-and-empty-input` MUST — HTDVController.select(itemID:atLevel:) MUST no-op on an itemID absent from the given level's items (MUST, see …
- `boundary-values` MUST — A number field's value exactly equal to minimum or maximum MUST pass validation — the comparisons are strict </>, not …
- `concurrent-access` MUST — HTDVController and FormState are each @MainActor-confined with no Sendable conformance of their own, so all of their …
- `error-states` MUST — A thrown error from HTDVDataSource.rootLevel() or .child(for:) MUST populate HTDVController.error with the failing …

## Edge Cases

- **Null and empty input**: `HTDVController.select(itemID:atLevel:)` MUST
  no-op on an `itemID` absent from the given level's items (MUST, see
  `select-validates-membership`). `FormState.set(_:for:)` MUST no-op on a
  `key` absent from the spec's fields (MUST, `testSetUnknownKeyIsIgnored`).
  A required `.text`/`.textArea`/`.markdown` field with an empty or
  whitespace-only value MUST fail validation with an "is required" message;
  the same field, when optional, MUST pass with `nil` (MUST, see
  `text-required-and-trims`). An empty `.stringSet` MUST fail validation
  only when `isRequired` is `true` (MUST, see `string-set-required`).
- **Boundary values**: A number field's value exactly equal to `minimum` or
  `maximum` MUST pass validation — the comparisons are strict `<`/`>`, not
  `<=`/`>=` (MUST, see `number-required-bounds-and-integer`,
  `testNumberBoundsAndInteger`). `HTDVLayoutEngine.layout` with
  `levelCount == 0` MUST return an empty `visibleRails` range, while any
  `levelCount > 0` MUST return at least one visible rail (MUST, see
  `zero-levels-shape`, `at-least-one-rail-when-levels-exist`). A `railWidth`
  of `0` or negative (settable after construction despite the `init`
  precondition) MUST be clamped to a divisor of at least `1` rather than
  dividing by zero or a negative number (MUST, see
  `rail-width-divisor-clamp`). `HTDVController.popToLevel(_:)` MUST treat
  `-1` as "clear everything" and anything below `-1`, or at/above the
  current depth, as a no-op (MUST, see `pop-to-level-contract`).
- **Concurrent access**: `HTDVController` and `FormState` are each
  `@MainActor`-confined with no `Sendable` conformance of their own, so all
  of their mutable state is serialized onto the main actor and cannot be
  touched concurrently from another isolation domain without an `await` hop
  (MUST, see `main-actor-confinement`, `form-state-main-actor-confinement`).
  Overlapping asynchronous fetches on the same `HTDVController` (a second
  `select`/`reload`/`load` starting before an earlier one resolves) are not
  prevented outright; instead, each fetch's result is validated against the
  `generation` counter captured when it began, and a result whose
  generation is stale is silently dropped rather than applied out of order
  (MUST, see `stale-response-dropped`, `testStaleResultIsDropped`). A
  `set(_:for:)` call landing on `FormState` while its own `save()` is
  in flight is not blocked; it mutates `values` immediately, and the
  in-flight save's already-captured value snapshot is unaffected, which
  MUST leave the form dirty even after that save later succeeds (MUST, see
  `concurrent-edit-during-save-stays-dirty`).
- **Error states**: A thrown error from `HTDVDataSource.rootLevel()` or
  `.child(for:)` MUST populate `HTDVController.error` with the failing
  level index and a message derived from the error (or MUST be dropped
  silently if a newer request has since started) — it is never left
  unreported to a still-current caller (MUST, see `error-shape`). A thrown
  error from a `FormAction.perform` (the save action) MUST populate
  `FormState.saveError` with a derived message and MUST leave `isDirty ==
  true` (MUST, see `save-failure-preserves-dirty-state`). `HTDVCreateAction.perform`
  and `FormDeleteAction.perform`/`FormActions.extra` entries have no
  channel of their own for the engine to observe or record a failure — see
  **create-action-error-path** below and
  `delete-and-extra-actions-are-outside-the-save-lifecycle`.
- **Offline or disconnected state**: None of the nine given sources make a
  network call directly; `HTDVDataSource.rootLevel()`/`.child(for:)` are
  the only points where a network-backed implementation could fail, and
  that failure surfaces to `HTDVController` exactly like any other thrown
  error (see Error states above) — the engine defines no timeout, retry, or
  connectivity-aware behavior of its own around those calls (fact, not a
  gap: an absent feature, not a swallowed signal — the failure is not lost,
  it is reported as `error`, just without a time bound).

- **create-action-error-path**: `HTDVCreateAction.perform` is declared `@MainActor @Sendable (PlatformViewController) async -> Void` — non-throwing, with no return value — so the engine defines no path for a creation failure to reach `HTDVController.error` or trigger a `reload`. The signature makes it the closure's precondition to present and recover from its own failures without engine involvement.
