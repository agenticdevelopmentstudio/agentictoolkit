<!-- leaf: implement-hub-domain-1/access--edge-cases · source: hub-domain-access.md -->

# Hub Domain Access Client

**Rules** (cite as `implement-hub-domain-1/access--edge-cases#<slug>`):

- `empty-grants-array` MUST — createRole/updateRole MUST send an empty grants: [] unchanged when the caller supplies one; no client-side check …

## Edge Cases

- **Null and empty input — `workspace`**: Not checked client-side. `workspace` is a typed `string` the caller supplies; an empty slug is sent to the server unchanged as `workspace=`. A non-empty customer or org slug is a caller precondition, per the module's top-of-file comment.
- **Null and empty input — assignment scope pairing**: `assignment-scope-pairing-validation` below.
- **Empty `grants` array**: `createRole`/`updateRole` MUST send an empty `grants: []` unchanged when the
  caller supplies one; no client-side check requires at least one grant — a role with zero grants is a
  valid, unvalidated request as far as this module is concerned.
- **Boundary values — grant verb strings**: `AccessGrantRow.itemVerbs`/`.subitemVerbs` are typed
  `string` with a doc-commented expected character set (a comma-letter subset of `C,R,U,D,M` and
  `C,R,U,D` respectively), but `createRole`/`updateRole` send whatever string the caller provides with
  no client-side charset or length check. This is a fact, not a gap: the sibling `ACCESS_FEATURES`
  comment documents that "every submitted grant is refined against it server-side," establishing that
  this client's job is to pass the value through, not police its shape.
- **Concurrent access — module state**: `accessApi` holds no shared mutable state between calls (the
  only module-level value besides the `BASE` constant is the read-only `ACCESS_FEATURES` array), so
  there is nothing for two concurrent calls to race on within this module.
- **Concurrent access — competing writes**: two concurrent `putAssignment` calls for the same subject
  and scope follow ordinary `PUT` semantics — last response received wins, with no client-side
  sequencing or optimistic-lock check in this file.
- **Error states — validation failure vs. HTTP failure**: `feature-row-shape-validated`'s thrown
  `Error` and an `AuthHttpError` are distinguishable only via `httpStatus()`'s duck-typed `.status`
  check (`http.ts`); the former has none, per `feature-validation-error-is-plain`.
- **Error states — 204 on a declared-void write**: `item-restrict-restore-parse-body` above; this is
  the one place in the file where a declared `Promise<void>` operation can throw on success-shaped
  input, depending on what the backend actually returns.
- **Offline or disconnected state**: none of the ten `accessApi` methods catches a network-level
  `fetch` rejection; a connectivity loss mid-call propagates as an unhandled promise rejection out of
  `accessApi` to the caller, with no retry, queuing, or offline-specific handling anywhere in this
  file.
- **No timeout**: no `accessApi` call sets a deadline or `AbortSignal`; a reachable-but-unresponsive
  backend leaves the call pending until the underlying `fetch` implementation's own limit, if any.
- **No cancellation**: no `accessApi` method accepts an `AbortSignal` parameter, so a caller cannot
  cancel an in-flight request through this module.
- **No retry beyond the 401 waterfall**: every `accessApi` call issues exactly one request (plus, on a
  `401`, the single inherited refresh-and-retry); nothing in this file retries a network failure or a
  non-401 error status.
- **assignment-scope-pairing-validation**: NEEDS REVIEW: Not implemented in source. `AccessAssignmentInput.feature`/`.itemId` are independently optional, but the field's own doc comment declares they must be provided together to scope a grant to one item and omitted together for a workspace-wide grant; `putAssignment` sends whatever partial combination the caller passes with no client-side check enforcing that pairing. Evidence that would settle it: the backend's handling of a `feature`-without-`itemId` (or the reverse) assignment write, which is not present in this checkout.
