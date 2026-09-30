<!-- leaf: implement-general-2/networking--edge-cases · source: networking.md -->

# Bounded Body Loader

**Rules** (cite as `implement-general-2/networking--edge-cases#<slug>`):

- `empty-body` MUST — A response with a zero-byte body MUST succeed under any limit >= 0, returning empty Data paired with the response — the …
- `zero-or-negative-limit` MUST — A limit of 0 or less MUST cause the transfer to be refused as Failure.tooLarge as soon as either the header check …
- `exact-boundary-body` MUST — A body of exactly limit bytes MUST be accepted in full; a body of limit + 1 bytes, with no Content-Length header to …
- `concurrent-transfers-on-one-loader` MUST — Multiple simultaneous calls to body(at:limit:) on the same BoundedBodyLoader instance MUST each receive independent …
- `unreachable-host-dns-or-tls-failure` MUST — When the underlying connection never succeeds, URLSession reports the failure via didCompleteWithError, and the loader …
- `connectivity-lost-mid-transfer` MUST — If the network drops after some chunks arrived but before completion, and the running total had not yet crossed limit, …
- `a-cancellation-racing-an-overflow` MUST — If the calling Task is cancelled at the same moment the running check would have overflowed, either outcome …
- `deallocation-with-a-transfer-in-flight` MUST — If the loader is deallocated while a transfer is outstanding, deinit's finishTasksAndInvalidate() MUST let that …

## Edge Cases

- **Empty body**: A response with a zero-byte body MUST succeed under any
  `limit >= 0`, returning empty `Data` paired with the response — the
  running total (0) never exceeds a non-negative limit. MUST.
- **Zero or negative `limit`**: A `limit` of `0` or less MUST cause the
  transfer to be refused as `Failure.tooLarge` as soon as either the header
  check (`expectedContentLength > Int64(limit)`, true for almost any
  declared length once `limit` is non-positive) or the first non-empty
  chunk pushes the running total past that ceiling; a response that sends
  no bytes and declares no length would still succeed as an empty body.
  MUST.
- **Exact-boundary body**: A body of exactly `limit` bytes MUST be accepted
  in full; a body of `limit + 1` bytes, with no `Content-Length` header to
  short-circuit the header check, MUST be refused by the running check
  alone. MUST.
- **Concurrent transfers on one loader**: Multiple simultaneous calls to
  `body(at:limit:)` on the same `BoundedBodyLoader` instance MUST each
  receive independent bookkeeping keyed by their own task's
  `taskIdentifier` under the shared lock; one transfer overflowing its
  `limit` MUST NOT affect another concurrent transfer's buffer, limit, or
  outcome. MUST.
- **Unreachable host / DNS or TLS failure**: When the underlying connection
  never succeeds, `URLSession` reports the failure via
  `didCompleteWithError`, and the loader MUST rethrow that `URLError`
  unchanged rather than reporting it as `Failure.tooLarge` or swallowing it.
  MUST.
- **Connectivity lost mid-transfer (offline/disconnected)**: If the network
  drops after some chunks arrived but before completion, and the running
  total had not yet crossed `limit`, the loader MUST rethrow the resulting
  transport error (e.g. `URLError(.networkConnectionLost)`) and MUST NOT
  return the partial `Data` collected so far — a transfer that does not
  finish MUST NOT hand back a partial result. MUST.
- **A cancellation racing an overflow**: If the calling `Task` is cancelled
  at the same moment the running check would have overflowed, either
  outcome (cancellation error or `Failure.tooLarge`) is acceptable; the
  source does not order the two, and `finish` is only ever invoked once per
  transfer, so exactly one of them MUST reach the caller — not both, and
  not neither. MUST.
- **Deallocation with a transfer in flight**: If the loader is deallocated
  while a transfer is outstanding, `deinit`'s
  `finishTasksAndInvalidate()` MUST let that transfer's task run to
  completion and resume its continuation normally, since the `Delegate` and
  `State` objects the session still needs are retained by the session
  itself, independent of the loader. MUST.
