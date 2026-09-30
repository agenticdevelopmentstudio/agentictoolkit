<!-- leaf: implement-hub-domain-2/reactions--edge-cases · source: hub-domain-reactions.md -->

# Hub Domain: Reactions

**Rules** (cite as `implement-hub-domain-2/reactions--edge-cases#<slug>`):

- `empty-targetids-array` MUST — list resolves [] with no request issued. MUST (list-empty-input-short-circuits).
- `all-falsy-targetids` MUST — .filter(Boolean) removes every entry, leaving an empty set, so the same no-request short-circuit applies as an …
- `empty-emoji-string-passed-to-add` MUST — reactions.ts performs no client-side check of emoji's shape or non-emptiness before POSTing; the value is sent to the …
- `viewerid-as-an-empty-string` MUST — tally's guard is viewerId && ..., so "" is treated exactly like null — every mine comes back null, not merely "no match …
- `exactly-max-target-ids-target-ids` MUST — list issues exactly one request; the boundary case one id below the cap must not trigger a second chunk. MUST.
- `one-id-past-the-cap` MUST — list issues exactly two requests, 200 ids then 1, per reactions-005. MUST.
- `concurrent-calls-to-list-add-or-remove` MUST — reactionsApi holds no shared state between calls (stateless-module); two concurrent calls — even the same operation …
- `one-chunk-of-a-multi-chunk-list-rejects` MUST — Promise.all rejects as soon as any one chunk's authedJson call rejects; the rows from any OTHER chunk that already …
- `network-unreachable` MUST — a fetch failure (no connectivity) rejects before any Response exists; per error-propagation-unmodified, the calling …
- `non-2xx-response` MUST — per authedFetch (in @agentic-toolkit/auth/client.ts, outside these two given files but read to resolve this contract), …
- `offline-or-disconnected-mid-request` MUST — none of list, add, or remove registers a retry, timeout, or an abort signal of its own; a request that never settles …
- `malformed-list-response-body` MUST — list calls p.items.map(toReaction) unconditionally on each resolved page; a page missing items throws a TypeError from …
- `add-called-twice-with-the-same` MUST — per the module's own comment, the second call resolves with the SAME existing reaction row rather than rejecting with a …

## Edge Cases

- **Empty `targetIds` array**: `list` resolves `[]` with no request issued. MUST (`list-empty-input-short-circuits`).
- **All-falsy `targetIds` (e.g. `["", "", ""]`)**: `.filter(Boolean)` removes every entry, leaving an empty set, so the same no-request short-circuit applies as an all-empty array. MUST.
- **Empty `emoji` string passed to `add`**: `reactions.ts` performs no client-side check of `emoji`'s shape or non-emptiness before POSTing; the value is sent to the backend verbatim, and any rejection (documented or not) surfaces unmodified per `error-propagation-unmodified`. MUST.
- **`viewerId` as an empty string**: `tally`'s guard is `viewerId && ...`, so `""` is treated exactly like `null` — every `mine` comes back `null`, not merely "no match found." MUST (`tally-null-viewer-honest-rendering`).
- **Exactly `MAX_TARGET_IDS` (200) target ids**: `list` issues exactly one request; the boundary case one id below the cap must not trigger a second chunk. MUST.
- **One id past the cap (201)**: `list` issues exactly two requests, 200 ids then 1, per `reactions-005`. MUST.
- **Concurrent calls to `list`, `add`, or `remove`**: `reactionsApi` holds no shared state between calls (`stateless-module`); two concurrent calls — even the same operation against the same subject — MUST NOT be serialized, deduplicated, or coalesced by this module; each fires its own independent request whose relative completion order depends on the network, not this file. MUST.
- **One chunk of a multi-chunk `list` rejects**: `Promise.all` rejects as soon as any one chunk's `authedJson` call rejects; the rows from any OTHER chunk that already resolved are discarded — `list` never returns a partial result, per `error-propagation-unmodified`. MUST.
- **Network unreachable**: a `fetch` failure (no connectivity) rejects before any `Response` exists; per `error-propagation-unmodified`, the calling method's promise rejects with that same underlying error, uncaught. MUST.
- **Non-2xx response**: per `authedFetch` (in `@agentic-toolkit/auth/client.ts`, outside these two given files but read to resolve this contract), a non-ok response becomes an `AuthHttpError` carrying the response's status and an extracted message; exactly one `401` triggers one token-refresh-and-retry before this conversion. MUST.
- **Offline or disconnected mid-request**: none of `list`, `add`, or `remove` registers a retry, timeout, or an abort signal of its own; a request that never settles leaves the returned promise pending for as long as the underlying `fetch` call takes to settle. MUST.
- **Malformed `list` response body (missing `items` key)**: `list` calls `p.items.map(toReaction)` unconditionally on each resolved page; a page missing `items` throws a `TypeError` from inside the `.then`/`await` chain, rejecting `list`'s promise rather than being caught. MUST.
- **`add` called twice with the same `(actor, target, emoji)`**: per the module's own comment, the second call resolves with the SAME existing reaction row rather than rejecting with a 409 — this is the documented idempotency contract, not a race. MUST.
- **repeat-remove-behavior**: a repeat `remove` against an already-removed id issues another `DELETE content/reactions/:id` exactly like the first; the client adds no de-duplication, and whatever the backend returns (success or an error status) surfaces to the caller unchanged. Unlike `add`, no comment documents a repeat `remove` as idempotent.
