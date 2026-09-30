<!-- leaf: implement-status-server-monitor-2/webhook-verify--edge-cases · source: status-server-monitor-webhook-verify.md -->

# Status Server Monitor Webhook Verify

**Rules** (cite as `implement-status-server-monitor-2/webhook-verify--edge-cases#<slug>`):

- `null-and-empty-input` MUST — signature of null, undefined, or '' MUST be rejected with no digest computed (missing-signature-rejected) — MUST. …
- `boundary-values` MUST — a byte-length mismatch between the two strings any comparison handles — the computed hex digest versus the signature …
- `concurrent-access` MUST — not applicable in the shared-mutable-state sense — the module declares no state of its own, so two or more concurrent …
- `error-states` MUST — this file has no external dependency of its own — no network call, no database, no file system — so a dependency being …

## Edge Cases

- **Null and empty input**: `signature` of `null`, `undefined`, or `''` MUST be rejected with no digest computed (missing-signature-rejected) — MUST. `provided` of `null`, `undefined`, or `''` MUST be rejected with no comparison (missing-provided-rejected) — MUST. `secret` of `''` for either function MUST reject regardless of the other argument, fail-closed rather than fail-open (missing-secret-rejected, missing-configured-secret-fails-closed) — MUST. An empty `rawBody` (`''`) is not specially guarded — it simply HMACs to the fixed digest that empty input produces for the given `secret`, like any other input.
- **Boundary values**: a byte-length mismatch between the two strings any comparison handles — the computed hex digest versus the `signature` header, or `provided` versus `secret` — MUST short-circuit to `false` inside `safeEqual` before `timingSafeEqual` is ever called (length-mismatch-short-circuits), avoiding the `RangeError` that function throws on mismatched-length buffers — MUST. A case difference between the (always-lowercase) computed hex digest and a differently-cased `signature` value is also treated as unequal, since the comparison is a literal UTF-8 byte compare rather than a decoded-hex compare (utf8-byte-comparison) — MUST.
- **Concurrent access**: not applicable in the shared-mutable-state sense — the module declares no state of its own, so two or more concurrent or overlapping calls to either function simply run independent, self-contained comparisons that cannot interact (independent-calls-no-shared-state) — MUST.
- **Error states**: this file has no external dependency of its own — no network call, no database, no file system — so a dependency being unavailable is a fact about the CALLER (e.g. `hooks.ts`'s raw-body read, or the configuration lookup that produces `secret`), external to this file's own contract; within this file, every input combination resolves to a `boolean` with no error state of its own (no-throw-contract) — MUST.
- **Offline / disconnected state**: not applicable — this file makes no network call and has no connectivity of its own to lose; that concern belongs entirely to whichever caller already fetched `rawBody`, `signature`, `provided`, and `secret` before invoking these functions.
