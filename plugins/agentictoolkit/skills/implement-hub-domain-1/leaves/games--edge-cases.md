<!-- leaf: implement-hub-domain-1/games--edge-cases · source: hub-domain-games.md -->

# Hub Domain: Games

**Rules** (cite as `implement-hub-domain-1/games--edge-cases#<slug>`):

- `null-empty-input` MUST — An empty or whitespace-only description MUST write as the empty COLUMN (null), never an empty string in the column …
- `boundary-malformed-values` MUST — JSON text that fails JSON.parse MUST be refused with a 4xx clientRefusal rather than stored as a JSON string …

## Edge Cases

- **Null/empty input**: An empty or whitespace-only `description` MUST
  write as the empty COLUMN (`null`), never an empty string in the column
  (nullable-text-write, hub-domain-games-016). An empty or whitespace-only
  `engineConfig`/`data` MUST write as that column's own empty JSON value —
  `{}` for `engineConfig`, `null` for `data` — never as the other column's
  empty value (jsonb-empty-value-differs-by-column, hub-domain-games-020,
  -022). An empty catalog LIST resolves to `[]` for `gamesApi.list`/
  `childApi.list`, which `forEcosystem` further reduces to `null`
  (games-for-ecosystem-single-result, hub-domain-games-004).
- **Boundary/malformed values**: JSON text that fails `JSON.parse` MUST be
  refused with a 4xx `clientRefusal` rather than stored as a JSON string
  (jsonb-write-refuses-unparseable-text, hub-domain-games-024).
  `GameEffectInput.trigger`/`operation` of `""` (a caller precondition the
  type signature itself documents as a valid, if incomplete, draft state —
  see `game-effect-input-allows-blank-selection`) and a caller-supplied
  `eventRetentionDays` outside the schema's `> 0` check are both sent to
  the backend exactly as given; this client applies no client-side range
  or closed-set validation of its own to either field, relying entirely on
  the database `check` constraints the source's own comments document for
  `character_names`, `status`, `event_log`, `trigger`, `operation`, and
  `event_retention_days`.
- **Concurrent access**: This module is plain single-threaded JavaScript
  with no actor, lock, or queue of its own — every exported function is an
  independent `async` call, and nothing here serializes two calls made at
  once. Two closely-timed `gamesApi.create` calls for the same
  `(ecosystemId, slug)` are not deduplicated client-side; the backend's own
  unique constraint (the one `games-create-conflict-mapping` maps to a
  friendly message) is the actual guard. The same race against a
  definition/effect/mapping's uniqueness constraint (if the backend has
  one) is NOT given a friendly mapping at all, per
  `child-create-update-no-conflict-mapping` — it would surface as the raw
  backend message.
- **Error states**: Every request this module makes can reject with
  whatever `authedJson`/`authedRequest` (`@agentic-toolkit/auth`'s client)
  throws — an `AuthHttpError` carrying an HTTP status and a backend-derived
  message for a non-2xx response, or a plain rejected `Promise` for a
  network-level failure that never reached the server. `gamesApi.create`/
  `update` narrow exactly one case of that (a message matching
  `/already exists/i`) into a friendly, entity-named error and rethrow
  every other error unchanged; no other function in this module inspects
  or transforms a caught error at all — `gamesApi.list`/`forEcosystem`/
  `delete` and every `childApi` method let any rejection propagate
  untouched.
- **Offline/disconnected state**: This module has no offline cache, no
  queued-write mechanism, and no reconnection logic; every operation is a
  single live round trip that rejects outright when the network is
  unavailable, with no retry attempted by this module (the underlying
  `authedFetch`'s one-refresh-and-retry applies only to a `401`, an
  authentication concern documented in `auth-client`, not a network-outage
  retry of this domain's own operations).
