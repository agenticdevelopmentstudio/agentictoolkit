<!-- leaf: implement-status-web-src-lib-1/endpoint-kinds--edge-cases · source: status-web-src-lib-endpoint-kinds.md -->

# Endpoint Kinds

**Rules** (cite as `implement-status-web-src-lib-1/endpoint-kinds--edge-cases#<slug>`):

- `empty-string` MUST — isEndpointKind("") MUST return false. The list has no empty member.
- `case-and-whitespace-variants` MUST — "Http", "HTTP" and " http" MUST return false. The guard does no normalization, so a caller that accepts user-typed …
- `kinds-from-another-vocabulary` MUST — The shared data package (@agentic-toolkit/data/monitored-sites) declares a different ENDPOINT_KINDS of ["http", "tcp", …
- `non-string-input-at-runtime` MUST — The signature takes string. A JavaScript caller that passes undefined, null or a number MUST get false, because …

## Edge Cases

- **Empty string**: `isEndpointKind("")` MUST return `false`. The list has no empty member.
- **Case and whitespace variants**: `"Http"`, `"HTTP"` and `" http"` MUST return `false`. The guard does no normalization, so a caller that accepts user-typed kinds has to normalize first.
- **Kinds from another vocabulary**: The shared data package (`@agentic-toolkit/data/monitored-sites`) declares a different `ENDPOINT_KINDS` of `["http", "tcp", "icmp"]`, which the dashboards feature's `EndpointsEditor` uses. `isEndpointKind("tcp")` and `isEndpointKind("icmp")` MUST return `false` here. Only `"http"` is shared between the two vocabularies.
- **A kind added to the engine but not to this list**: If the engine's `NON_DEPLOY_KINDS` gains a member that `ENDPOINT_KINDS` lacks, the `non-deploy-subset` invariant breaks silently. No type or test ties the two lists together; the engine's comment assigns ownership of the set to the classifier.
- **Drift from the status server's copy**: `status-server/src/monitor/endpoint-kinds.ts` restates the same six members rather than importing them. Its comment says it is "kept in step" with this file. No parity test enforces this, so an edit to one file alone would let the editor offer a kind the server's validator rejects, or the reverse. Validation of kinds on write belongs to the status server's endpoints routes, not to this module.
- **Non-string input at runtime**: The signature takes `string`. A JavaScript caller that passes `undefined`, `null` or a number MUST get `false`, because `Array.prototype.includes` does not throw and no member is equal to a non-string.
- **Null, boundary and error states**: There are no numeric bounds and no I/O. The module cannot fail at runtime except by being imported without its engine dependency, which is a build error.
- **Concurrent access**: Not applicable. The module holds no mutable state and runs on single-threaded JavaScript.
- **Offline or disconnected**: Not applicable. The module performs no network access.
