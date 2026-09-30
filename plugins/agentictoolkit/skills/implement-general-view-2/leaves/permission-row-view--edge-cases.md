<!-- leaf: implement-general-view-2/permission-row-view--edge-cases · source: permission-row-view.md -->

# PermissionRowView

**Rules** (cite as `implement-general-view-2/permission-row-view--edge-cases#<slug>`):

- `null-empty-input` MUST (MUST) — .automation(targetBundleID: "") — NSWorkspace.urlForApplication(withBundleIdentifier: "") returns nil for the empty …
- `boundary-values` MUST (MUST) — an unusually long explanation string MUST wrap across multiple lines in descLabel (a wrappingLabelWithString: field …
- `concurrent-access` SHOULD (SHOULD) — two overlapping calls to refresh() on the same row, neither cancelling the other — the view performs no internal …

## Edge Cases

- **Null/empty input** (MUST): `.automation(targetBundleID: "")` —
  `NSWorkspace.urlForApplication(withBundleIdentifier: "")` returns `nil`
  for the empty string, so `applicationName(for:)`'s guard fails and it
  falls back to returning the bundle id string itself (here, empty). The
  title MUST render as `"Automation — "` and the Automation sentence in the
  description MUST render with an empty target name, rather than crashing.
  Traced to `applicationName(for:)`'s guard-let/return-bundleID fallback.
  `.keychain(service: "")` takes a different path: `rowTitle(for:)` only
  special-cases `.automation`, so the title MUST still render as plain
  `"Keychain"` (`permission.displayName`), unaffected by the empty service;
  the description MUST render as the literal sentence with an empty quoted
  service name (`Lets this app read the "" item in your keychain directly,
  instead of asking another tool for it.`, from
  `explanation(namingAutomationTarget:)`'s `.keychain` case), rather than
  crashing or omitting the quotes.
- **Boundary values** (MUST): an unusually long `explanation` string MUST
  wrap across multiple lines in `descLabel` (a `wrappingLabelWithString:`
  field with no line limit set), and the row MUST grow taller than the 72pt
  floor to fit it, since `heightAnchor` is a `greaterThanOrEqualToConstant`,
  not a fixed height.
- **Concurrent access** (SHOULD): two overlapping calls to `refresh()` on
  the same row, neither cancelling the other — the view performs no
  internal serialization of overlapping refreshes, so which call's
  `checker.status(permission)` await resolves last, and therefore which
  result the displayed state ends up showing, is left undefined by
  `PermissionRowView` itself; each `apply(status:)` call simply overwrites
  whatever the previous one set. Coordinating that ordering SHOULD be the
  caller's responsibility (as `PermissionsPanelView` does with its own
  single `refreshTask`), not `PermissionRowView`'s.
- **Error states**: Not applicable — `PermissionChecking.status(_:)` is
  declared non-throwing and returns a `PermissionStatus` directly;
  `.undetermined` already exists to mean "can't currently tell" (for
  example, an Automation target that isn't running), so there is no
  separate failure/error path for `PermissionRowView` to render beyond the
  three states already specified.
- **Offline/disconnected state**: Not applicable — `PermissionRowView` and
  `PermissionChecking` read only local macOS system authorization state
  (TCC / Apple Events); `PermissionRowView.swift` makes no network call, so
  connectivity has no defined effect on this component.
