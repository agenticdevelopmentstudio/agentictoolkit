<!-- leaf: implement-general-view-2/permissions-panel-view--edge-cases · source: permissions-panel-view.md -->

# Permissions Panel View

**Rules** (cite as `implement-general-view-2/permissions-panel-view--edge-cases#<slug>`):

- `null-empty-input` MUST (MUST) — permissions MUST be permitted to be an empty array. The component MUST then build zero rows, and refresh() MUST …
- `duplicate-values` MUST (MUST) — A permissions array containing the same Permission value more than once (for example two .accessibility entries) MUST …
- `concurrent-access` MUST (MUST) — Every property and operation of the component is @MainActor-isolated, so its internal state is serialized onto the main …
- `error-states` MUST (MUST) — PermissionChecking.status(_:) and .request(_:) are non-throwing, so the component has no catch path and performs no …

## Edge Cases

- **Null/empty input** (MUST): `permissions` MUST be permitted to be an
  empty array. The component MUST then build zero rows, and `refresh()`
  MUST complete immediately with no row refreshed — both the
  row-construction step and `refresh()` iterate the given collection with
  no special-casing for zero elements.
- **Duplicate values** (MUST): A `permissions` array containing the same
  `Permission` value more than once (for example two `.accessibility`
  entries) MUST still produce one row per entry, including the duplicate;
  the component performs no deduplication when building rows.
- **Concurrent access** (MUST): Every property and operation of the
  component is `@MainActor`-isolated, so its internal state is serialized
  onto the main actor. Window attach, app activation, and a completed
  grant action can all ask for a refresh in close succession; the
  component MUST resolve that through the cancel-and-replace pattern
  named in **latest-refresh-wins**, cancelling whatever refresh is already
  in flight before starting the new one.
- **Error states** (MUST): `PermissionChecking.status(_:)` and
  `.request(_:)` are non-throwing, so the component has no `catch` path
  and performs no error handling of its own. `PermissionStatus` has no
  "error" case, so a misbehaving checker implementation can only surface
  as `.granted`, `.denied`, or `.undetermined` — this component does not
  detect or separately report a failing checker.
- **Offline/disconnected state**: Not applicable. The component makes no
  network call directly; any network or cross-process dependency a
  particular permission's status check has is the injected `checker`'s
  concern, not this component's.
