<!-- leaf: implement-status-server-monitor-2/webhook-verify--part-2 · source: status-server-monitor-webhook-verify.md -->

# Status Server Monitor Webhook Verify — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-2/webhook-verify--part-2#<slug>`):

- `decision` MUST — compare the hex-encoded digest against signature (and provided against secret) as raw UTF-8 byte representations via …

## Design Decisions

- **Decision**: guard for equal byte length before calling `node:crypto`'s `timingSafeEqual`, returning `false` immediately on a mismatch, rather than calling `timingSafeEqual` directly on both inputs.
  **Rationale**: stated in `safeEqual`'s own doc comment — "never throws on length mismatch." Node's `timingSafeEqual` throws a `RangeError` when given buffers of different lengths; guarding first turns what would otherwise be an uncaught exception into an ordinary rejected verification, so a malformed or short `x-vercel-signature` header (or shared-secret value) produces a clean `401` rather than crashing the request handler.
  **Approved**: pending
- **Decision**: `verifySharedSecret` returns `false`, never `true`, when the CONFIGURED `secret` parameter is the empty string — independent of whatever `provided` value is passed.
  **Rationale**: stated directly in the source doc comment — "An empty/unset configured secret never matches — so a misconfigured deployment fails closed rather than open." Without this guard, an operator who forgot to set `RAILWAY_WEBHOOK_SECRET` would inadvertently accept any (or no) value as valid, turning a missing-configuration bug into an open, unauthenticated webhook endpoint.
  **Approved**: pending
- **Decision**: compare the hex-encoded digest against `signature` (and `provided` against `secret`) as raw UTF-8 byte representations via `safeEqual`, not as decoded hex bytes or case-normalized values.
  **Rationale**: not stated in the source's comments; recorded here as an observed, deliberate fact. `createHmac(...).digest("hex")` always produces lowercase hex, and the comparison is a literal string/byte compare, so a signature header value in a different case would be rejected even though it decodes to the same bytes. This is the file's actual behavior, and a port MUST reproduce the case-sensitive comparison unless it also normalizes both sides identically before comparing.
  **Approved**: pending
- **Decision**: `verifyVercelSignature`'s contract checks only that the HMAC-SHA1 of the raw body matches — it carries no timestamp, nonce, or replay window of its own.
  **Rationale**: the function's own doc comment defines the complete contract — "`x-vercel-signature` is the hex HMAC-SHA1 of the RAW request body keyed by the webhook secret" — with no timestamp or nonce component described, because Vercel's own header carries none. There is nothing for this file to check that the upstream header does not itself carry; any replay protection would be a property of the provider's webhook design, not an omission in this function's stated contract.
  **Approved**: pending
