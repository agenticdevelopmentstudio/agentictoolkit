<!-- leaf: implement-general-1/api-toolkit--part-4 · source: api-toolkit.md -->

# ApiToolkit — continued (part 4)

## Design Decisions

### Client-side exposure gate is presentation-only

**Decision**: `canReadTable`/`canWriteTable`/`readableTables` in `exposure.ts`
are documented and implemented as presentation-only filters; they are never
treated as the authorization boundary.

**Rationale**: The server independently re-checks every request regardless
of what the client renders, so duplicating that enforcement client-side would
create a second source of truth that could drift from the real one.

**Approved**: pending

### Deliberate duplication of the shiki singleton

**Decision**: `highlight.ts` maintains its own module-level `highlighterPromise`
cache rather than sharing `@agenticdevelopertoolkit/markdown`'s existing shiki
singleton.

**Rationale**: The source's own doc comment states this is a deliberate,
acknowledged non-DRY choice rather than an oversight, avoiding a cross-package
coupling between `api-explorer` and the markdown package's internal caching
lifecycle.

**Approved**: pending

### Server-only vs client-only barrel split

**Decision**: `server.ts` (no `'use client'`) and `index.ts` (`'use client'`)
are kept as two separate entry points, with `index.ts` deliberately excluding
`getEndpoint`/`API_ENDPOINTS`.

**Rationale**: This prevents the large generated endpoint metadata map from
being pulled into the initial client bundle of any consumer that only needs a
button component, while still letting server-rendered pages reach the full
metadata.

**Approved**: pending

### Package-path imports to share module-level cache state

**Decision**: `server.ts` imports `allTags`, `endpointsForTag`, `getEndpoint`,
and `endpointKey` via the package path
(`@agentic-toolkit/api-explorer/lib/getEndpoint`) rather than a relative
import.

**Rationale**: The server entry and the client barrel are two separate build
chunk graphs; importing via the package path ensures both resolve to the same
module instance and therefore the same cached `_byTag`/`_tags` state, instead
of each accidentally forking its own copy of the cache.

**Approved**: pending

### Non-live token placeholder in generated snippets

**Decision**: `snippets.ts` always substitutes `TOKEN_PLACEHOLDER`
(`'YOUR_TOKEN'`) for any real bearer token in a generated cURL/JavaScript
snippet.

**Rationale**: A generated snippet is commonly copied to the clipboard or
pasted into a shared document; embedding a live token there would be a
credential leak vector, so the source trades away snippet convenience
(the caller must substitute a real token before running it) for that safety.

**Approved**: pending
