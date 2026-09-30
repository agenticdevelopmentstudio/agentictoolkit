<!-- leaf: implement-status-web-src-lib-1/retired-storage--edge-cases · source: status-web-src-lib-retired-storage.md -->

# Retired Storage

**Rules** (cite as `implement-status-web-src-lib-1/retired-storage--edge-cases#<slug>`):

- `null-or-empty-input` MUST — The function takes no input. An empty storage area MUST give a silent no-op (retired-storage-003).
- `retired-key-absent` MUST — removeItem on a missing key does nothing. The purge MUST complete without error.
- `server-side-rendering` MUST — With no global window, the purge MUST return at once (retired-storage-005).
- `storage-disabled-or-denied` MUST — When removeItem, or the localStorage property read, throws, the purge MUST catch the exception, leave the blob and …
- `several-retired-keys-one-failing` MUST — Each key has its own try/catch, so a throw on one key MUST NOT skip the others. The list has one entry today.
- `large-blob` MUST — The retired value can be several hundred KB. Removing it MUST NOT read or parse the value. The purge only calls …
- `concurrent-tabs` MUST — Several tabs of one origin MAY run the purge at the same time. Removing a key is idempotent, so the end state MUST be …

## Edge Cases

- **Null or empty input**: The function takes no input. An empty storage area MUST give a silent no-op (retired-storage-003).
- **Retired key absent**: `removeItem` on a missing key does nothing. The purge MUST complete without error.
- **Server-side rendering**: With no global `window`, the purge MUST return at once (retired-storage-005).
- **Storage disabled or denied**: When `removeItem`, or the `localStorage` property read, throws, the purge MUST catch the exception, leave the blob and return normally (retired-storage-004, retired-storage-007). The exception is not reported anywhere. The doc comment makes this a deliberate contract, so it is a fact, not a gap.
- **Several retired keys, one failing**: Each key has its own `try`/`catch`, so a throw on one key MUST NOT skip the others. The list has one entry today.
- **Large blob**: The retired value can be several hundred KB. Removing it MUST NOT read or parse the value. The purge only calls `removeItem`.
- **Concurrent tabs**: Several tabs of one origin MAY run the purge at the same time. Removing a key is idempotent, so the end state MUST be that the key is gone (or still present if storage is denied).
- **Boundary values**: Not applicable. There are no numeric or length inputs.
- **Offline or disconnected state**: Not applicable. The purge makes no network calls.
- **Timeouts and cancellation**: The purge has no timeout and cannot be cancelled. It is a short synchronous loop.
