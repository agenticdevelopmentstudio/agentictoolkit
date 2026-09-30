<!-- leaf: implement-status-web-hooks/use-status-user--part-2 · source: status-web-hooks-use-status-user.md -->

# useStatusUser — continued (part 2)

## Design Decisions

**Decision**: Keep a separate adapter that returns only `user`, rather than having every consumer call the session hook.
**Rationale**: The doc comment says one query function owns the `/api/auth/me` semantics, so role-gating consumers "can't drift". Consumers that need only the user get the simpler `StatusUser | null` shape, and those that need the loading flag use the session hook.
**Approved**: pending

**Decision**: Treat any non-OK `/auth/me` response as a thrown error, never as signed out.
**Rationale**: The `fetchStatusUser` doc comment says the backend never 401s this route, so a non-OK status means infrastructure trouble. Throwing lets React Query keep the last-known session and retry, which fixes "the 'visited the site and I was suddenly logged out' bug".
**Approved**: pending

**Decision**: Drop `isPending`, so loading, unknown and signed-out all return `null`.
**Rationale**: This is a deliberate lossy projection for role gates, which should hide admin affordances until a user is known. Callers that must not flash signed-out UI use the session hook's `isPending` instead.
**Approved**: pending

**Decision**: Use a 60 s stale time and 3 retries.
**Rationale**: Set in the session hook. The stale time limits `/auth/me` traffic across the many consumers. The retries ride out short backend restarts, and because a query error does not clear cached data, the header keeps showing the signed-in user in the meantime.
**Approved**: pending
