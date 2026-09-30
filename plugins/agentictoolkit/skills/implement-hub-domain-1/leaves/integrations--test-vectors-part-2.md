<!-- leaf: implement-hub-domain-1/integrations--test-vectors-part-2 · source: hub-domain-integrations.md -->

# Hub Domain: Integrations — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-integrations-043 | no-client-side-cache, stateless-module | `listProviders()` called twice in a row | Two separate HTTP requests are issued; the second call is not served from any in-module cache |
| hub-domain-integrations-044 | errors-propagate-except-not-found-lookups | `getProviderConfig("eco-1", "github")` against a `500` response | The `500` propagates as a thrown `AuthHttpError`; it is not converted to `null` (unlike a `404`) |
| hub-domain-integrations-045 | secrets-are-write-only | `listProviderConfigs("eco-1")` response body | No element of the resolved array has a `clientSecret` field; each has only `hasSecret: boolean` |
| hub-domain-integrations-046 | ecosystem-scoping-authorized-server-side | `listConnections("eco-2")` called by a caller who does not own `eco-2` | The call rejects with `AuthHttpError`, `status: 403` |
| hub-domain-integrations-047 | session-refresh-waterfall | Any `integrationsApi` call's first response is `401`; `refreshAccessToken()` resolves a new token | The request is retried once with the new token; a `401` on that retry throws `AuthHttpError` with `status: 401` — traced to `authedFetch` in `auth/src/client.ts`, exercised only indirectly through `integrationsApi` |
