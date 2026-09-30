<!-- leaf: implement-status-web-src-lib-1/endpoint-kinds--test-vectors · source: status-web-src-lib-endpoint-kinds.md -->

# Endpoint Kinds

## Conformance Test Vectors

No test file sits next to `endpoint-kinds.ts`. Vectors 001 to 009 are traced to the declarations in `endpoint-kinds.ts`. Vectors 010 and 011 are traced to the declaration of `NON_DEPLOY_KINDS` in `deploy-platform/src/engine/classify.ts` and to the assertions in `classify.test.ts` ("deploy-backed kinds need wiring" and "infra kinds do not").

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| endpoint-kinds-001 | kinds-members, kinds-order | Read `ENDPOINT_KINDS` | `["http", "frontend", "admin", "health", "custom", "dns"]`, length 6 |
| endpoint-kinds-002 | kinds-order | `ENDPOINT_KINDS[0]` | `"http"` |
| endpoint-kinds-003 | guard-true, guard-signature | `isEndpointKind(k)` for each k in `ENDPOINT_KINDS` | `true` for all six |
| endpoint-kinds-004 | guard-false | `isEndpointKind("tcp")`; `isEndpointKind("icmp")`; `isEndpointKind("mcp")` | `false` for all three |
| endpoint-kinds-005 | guard-false, guard-no-normalization | `isEndpointKind("HTTP")`; `isEndpointKind(" http")`; `isEndpointKind("http ")` | `false` for all three |
| endpoint-kinds-006 | guard-false, guard-no-throw | `isEndpointKind("")` | `false`, no exception |
| endpoint-kinds-007 | guard-signature | In a typed context, `const k: string = "dns"; if (isEndpointKind(k)) { const e: EndpointKind = k; }` | Compiles; `k` is narrowed to `EndpointKind` inside the branch |
| endpoint-kinds-008 | kinds-readonly | Type-check `ENDPOINT_KINDS.push("tcp")` | Type error (no `push` on a readonly tuple) |
| endpoint-kinds-009 | kind-type-derived | Type-check `const e: EndpointKind = "tcp"` | Type error; `"tcp"` is not assignable to `EndpointKind` |
| endpoint-kinds-010 | non-deploy-members, non-deploy-subset | `[...NON_DEPLOY_KINDS]` and `ENDPOINT_KINDS.includes(k)` for each member | `["health", "custom", "dns"]`; every member is in `ENDPOINT_KINDS` |
| endpoint-kinds-011 | non-deploy-ownership | Engine `endpointNeedsWiring(k)` for each k in `ENDPOINT_KINDS` | `true` for `http`, `frontend`, `admin`; `false` for `health`, `custom`, `dns` |
| endpoint-kinds-012 | non-deploy-reexport | Compare the `NON_DEPLOY_KINDS` imported from this module with the one imported from `@agentic-toolkit/deploy-platform/engine` | Same object (`Object.is` returns `true`) |
