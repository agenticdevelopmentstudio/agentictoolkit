<!-- leaf: implement-general-2/rdid-picker--edge-cases · source: rdid-picker.md -->

# RdidPicker

## Edge Cases

- **Null/empty input**: an empty or whitespace-only `query` is treated
  identically — trimmed to `""` and no `search` call is made (see
  skips-search-for-empty-query, T3). A non-empty query with surrounding
  whitespace is trimmed before it reaches `search`, never passed raw (see
  debounces-search-call, T6). `entityTypeLabel` and `placeholder` are
  optional props; their absence falls through to the derived defaults rather
  than any null-handling logic.
- **Boundary values**: `debounceMs=0` still schedules via `setTimeout(fn, 0)`
  — the call is deferred to the next macrotask, never synchronous. Source
  performs no clamping or validation on `debounceMs`; a very large value
  simply delays longer. A `search` resolving with `[]` is a normal success
  (renders the "No matching address" empty label), not an error.
- **Concurrent access**: rapid retyping produces overlapping `search` calls;
  each query change aborts whatever call was still pending and starts a new
  debounce (aborts-superseded-search, T7/T8). The component's state is local
  `React.useState` owned by one mounted instance, so there is no shared
  mutable state across instances to race on. Closing and reopening before an
  earlier debounce timer elapses does not let that stale timer reach
  `search` in the new session (T24).
- **Error states**: a `search` rejection — whether an `Error` or any other
  rejected value — surfaces as `error` and clears `options`
  (surfaces-search-rejection, T11/T12). Source contains no retry or backoff
  loop of its own: a failed search is not retried automatically; the user
  retrigger is another keystroke, which starts a fresh debounced call.
- **Offline / disconnected**: the component makes no network call directly —
  `search` is a caller-supplied function, and its transport, timeout, and
  retry behavior are the caller's responsibility, not `rdid-picker.tsx`'s.
  Whatever that function's promise rejects with (network failure, timeout, or
  otherwise) is handled identically and generically as any other rejection;
  the source has no online/offline detection of its own.
- A rejection that settles after the picker has since closed (and possibly
  reopened) is already aborted by the close-triggered effect cleanup, so it
  is ignored rather than corrupting the fresh session's state (see
  resets-on-close and ignores-aborted-search-results, and T24 for the
  reopen-before-elapsed case directly).
