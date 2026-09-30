<!-- leaf: implement-general-1/auth-client--part-7 · source: auth-client.md -->

# Auth Client — continued (part 7)

## Design Decisions

**Decision**: The refresh token from a backend response is never read or
persisted by this package — `tokensFromResponse` always writes
`refreshToken: ''` regardless of what the response body contains.
**Rationale**: Refresh and revoke are cookie-first against an HttpOnly
refresh cookie the server sets and reads; keeping the refresh token out of
`localStorage` means it is never exposed to any script running on the page,
which is the strongest defense a client-side store can offer against a
successful XSS. The `AuthTokens` shape still requires the field (for
interface compatibility), so it is blanked rather than omitted.
**Approved**: pending

**Decision**: `refreshAccessToken()` is single-flight (deduped via a
module-scoped `inFlight` promise) and guarded by a `generation` counter that
`invalidateRefresh()` bumps on every login/logout.
**Rationale**: Without dedup, N concurrently-401ing requests would each kick
off their own refresh POST, racing to rotate the same one-time refresh
cookie against each other. The generation guard exists because a refresh
that started before a fresh login or logout must not be allowed to write
stale tokens (or clear fresh ones) once it resolves — the source's own
comment calls this "a refresh racing a fresh login can't clobber the tokens
that login just adopted, nor clear them on logout."
**Approved**: pending

**Decision**: A losing concurrent refresh (a `401` on the rotated cookie)
waits exactly 300ms (`LOSER_RECHECK_DELAY_MS`) and re-reads storage once
before deciding whether to clear the session.
**Rationale**: Two uncoordinated single-flight mutexes (this copy of the
client plus a toolkit twin elsewhere in the fleet) can race over one rotated
refresh cookie; without the wait, the loser would clear a session the winner
is about to (or just did) successfully refresh. 300ms is documented in the
source as long enough for the winner's `writeTokens` to land in the common
case, chosen empirically rather than derived from a protocol constant.
**Approved**: pending

**Decision**: `exchangeSsoCode` retries its network POST exactly once, after
a 750ms pause, and only on a network-level failure (never on an HTTP error
response).
**Rationale**: The one-time exchange code is consumed only if a request
actually reaches the backend; a `fetch` that rejects (dropped connection,
offline blip) means the code was never consumed and a retry can still redeem
it. An HTTP error response means the code was already read and rejected (or
already spent) — retrying would only reproduce the same failure, never
improve the outcome. 750ms is chosen to survive a brief connection drop
without making the callback page feel hung, and stays well inside the
exchange code's server-side TTL.
**Approved**: pending

**Decision**: `preflightSsoReturn` fails closed to `false` on any ambiguous
outcome — a non-200, a thrown/rejected fetch, a wrong-shaped body, or a
timeout after 2000ms (`PREFLIGHT_TIMEOUT_MS`) — never defaulting to `true`.
**Rationale**: The preflight exists specifically to make the silent
cold-load SSO probe safe to run on any route, including a public landing
page: its one failure mode is a top-level navigation that strands the
visitor on the central login page. Failing closed costs an avatar (the
visitor stays anonymous, exactly as before); failing open costs the visitor
the page they asked for. 2000ms is chosen because the answer is a small,
uncached, single-row JSON read — long enough to absorb ordinary latency,
short enough that a wedged AS does not hang the page's loading state
indefinitely.
**Approved**: pending

**Decision**: `centralLoginStep` throws immediately, before any network
call, when no AS base is configured — it does not fall back to the
same-origin `/api` proxy the way `asEndpoint`'s other callers do.
**Rationale**: A relayed central login's `Set-Cookie` for the central
session is host-only on the AS host; routed through this site's own proxy,
that cookie would land on the brand site instead of the AS, appearing to
succeed (a session is minted, the header fills in) while establishing no
central session at all — silently degrading a cross-site login into a
site-only one, which is exactly the defect central login exists to remove.
Refusing loudly is the lesser harm: a misconfigured build fails visibly
instead of shipping a login that works once, on one site.
**Approved**: pending

**Decision**: `beginLinkProvider` stashes an unguessable CSRF nonce in
sessionStorage before navigating, and refuses to navigate at all (returns
`false`) if the nonce cannot be stashed.
**Rationale**: The link-mode OAuth round-trip's completion is later proven
to have been started by this same browser only by that nonce matching; a
forged `#link_code` URL a user is lured to carries no matching nonce and is
refused by the completing consumer. If the nonce cannot even be stashed
(storage blocked), the completion check is guaranteed to fail closed anyway,
so sending the user through the round-trip regardless would only spend a
navigation on a foregone failure.
**Approved**: pending

**Decision**: `isCrossApex`/`registrableDomain` compares only the last two
dot-separated labels of a hostname to decide apex equality, with no Public
Suffix List.
**Rationale**: This is correct for every domain the fleet currently uses —
all single-label TLDs (`.com`, `.ai`, `.studio`, `.today`, …) — and the
source comment explicitly flags the known limitation: a multi-label public
suffix (e.g. `example.co.uk`) would resolve to `co.uk` and mis-compare. This
is documented technical debt with a stated remediation path (switch to a
Public Suffix List) if such a domain is ever added, not an unresolved gap.
**Approved**: pending

**Decision**: `reportUnexpectedAuthError` duck-types a numeric `.status` off
any thrown `Error`, rather than checking `instanceof AuthHttpError`.
**Rationale**: A host that layers its own auth client on top of this package
can define its own, distinct `AuthHttpError`-shaped class; an `instanceof`
check would fail to recognize that class's 4xx errors as expected and would
report them as noise. Duck-typing the shape both classes share (a numeric
`status` field) is what lets one dedupe/gate implementation serve both.
**Approved**: pending

**Decision**: This recipe carries roughly 115 behavioral requirements across
eleven source files, deliberately more than a typical `ingredient` recipe.
**Rationale**: The component genuinely spans five distinct sub-contracts —
token storage/cache-scoping, single-flight cookie refresh, the Bearer-authed
fetch/error layer, cross-site SSO and central-login navigation (including
silent restore and provider linking), and self-serve MFA/WebAuthn enrollment
— each with its own exported operations, error paths, and (for four of the
five) dedicated test files. Per the cross-recipe-consistency guideline, this
depth is warranted by that count of distinct behaviors and error conditions,
not by a lack of scoping discipline; there is no sibling `auth`-family
recipe yet against which to check terminology or tag-vocabulary
consistency.
**Approved**: pending
