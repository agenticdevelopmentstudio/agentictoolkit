<!-- leaf: implement-hub-domain-1/organizations--test-vectors-part-2 · source: hub-domain-organizations.md -->

# Hub Domain: Organizations — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-organizations-027 | no-client-side-cache, module-holds-no-mutable-state | Call `organizationsApi.list("acme")` twice in succession against a fetch mock that counts invocations | The mock records exactly two HTTP requests, one per call — no shared cache or memoized result short-circuits the second call — no dedicated test; derived directly from the absence of any cache/state field in either module |
| hub-domain-organizations-028 | auth-delegated-to-shared-client | Inspect every exported method's implementation | Every one calls `authedJson` or `authedRequest`; neither module attaches an `Authorization` header or reads a token itself — derived directly from source; no dedicated test |
| hub-domain-organizations-029 | errors-carry-status-and-code | Backend responds 403 to `archive` with body `{"error":{"message":"forbidden","code":"not_site_admin"}}` | The thrown `AuthHttpError` has `status: 403` and `code: "not_site_admin"` — traced to `extractErrorCode`/`extractErrorMessage` in `auth/src/client.ts`; no dedicated test in this checkout |
