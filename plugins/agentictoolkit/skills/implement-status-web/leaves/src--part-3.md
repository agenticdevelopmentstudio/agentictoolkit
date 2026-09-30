<!-- leaf: implement-status-web/src--part-3 · source: status-web-src.md -->

# Status Web Src — continued (part 3)

## Design Decisions

**Decision**: `fetchStatusUser` throws on every non-OK response instead of mapping 401/403 to signed-out.
**Rationale**: the doc comment states the backend never answers `/auth/me` with a 401 — signed-out is a definitive 200 `{ user: null }` — so a non-OK is infrastructure trouble; throwing lets React Query keep the last-known session and retry instead of flashing the signed-out header at a logged-in user (the "suddenly logged out" bug).
**Approved**: pending

**Decision**: one React-Query key, `["status-auth-me"]`, is the only session cache, shared by header, board gate and landing page.
**Rationale**: the doc comment on `useStatusUser` states the single key dedupes across every consumer; the doc comment on `STATUS_AUTH_QUERY_KEY` makes login/signup responsible for invalidating it.
**Approved**: pending

**Decision**: `fetchStatusUser` resolves its URL through `api.url` but sends through its own `fetchImpl` (default global `fetch`), not `api.fetch`.
**Rationale**: the doc comment says `fetchImpl` stays injectable for tests while "the URL itself is always resolved through the caller's `StatusApiClient`". The consequence is that a client-level `fetch` override does not reach the session read, while `onLogout` does use `api.fetch`.
**Approved**: pending

**Decision**: `StatusHeaderAuthState` is declared in this package rather than imported from a header package.
**Rationale**: the doc comment states the package carries no dependency on any site's chrome; the shape is the common subset every header auth slot takes.
**Approved**: pending

**Decision**: logout navigates with a full-page `window.location.href = "/"` in `.finally`, without checking the response or invalidating the query.
**Rationale**: a full reload discards the React-Query cache and re-reads `/auth/me`, so the post-logout state always reflects the backend's truth; the source accepts an unhandled rejection when the POST itself fails.
**Approved**: pending

**Decision**: no `resolveSwitchHref` is supplied to the host header.
**Rationale**: the doc comment states a silent adh-SSO redirect is wrong for this non-adh local session, so the site switcher navigates straight to siblings.
**Approved**: pending

**Decision**: `DeploymentDTO.tier` is computed server-side and the client holds no copy of the derivation.
**Rationale**: the field's doc comment says to render `tier`, never `environment` (which reads "production" for every Vercel project), and that the client deliberately owns no copy of `deployEnv`.
**Approved**: pending
