<!-- leaf: implement-status-server-monitor-1/endpoint-kinds--test-vectors · source: status-server-monitor-endpoint-kinds.md -->

# Status Server Monitor Endpoint Kinds

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-endpoint-kinds-001 | endpoint-kind-vocabulary | Read `ENDPOINT_KINDS` | `.length === 6`; `.join(',') === 'http,frontend,admin,health,custom,dns'` |
| status-server-monitor-endpoint-kinds-002 | endpoint-kind-type | `const k: EndpointKind = 'http'`; `const bad: EndpointKind = 'staging'` | The first assignment compiles; the second fails to type-check because `'staging'` is not a member of `EndpointKind` |
| status-server-monitor-endpoint-kinds-003 | compile-time-immutability | `(ENDPOINT_KINDS as unknown as string[]).push('extra')`, then read `ENDPOINT_KINDS.length` | The direct call `ENDPOINT_KINDS.push('extra')` fails to type-check (`push` does not exist on the readonly tuple type); the cast version compiles, and `ENDPOINT_KINDS.length` is `7` afterward, confirming the underlying array is not frozen at runtime |
| status-server-monitor-endpoint-kinds-004 | type-guard-membership | `isEndpointKind('dns')`; `isEndpointKind('http')` | Both resolve `true` |
| status-server-monitor-endpoint-kinds-005 | type-guard-membership | `isEndpointKind('DNS')`; `isEndpointKind('')`; `isEndpointKind('unknown')` | All resolve `false` |
| status-server-monitor-endpoint-kinds-006 | type-guard-membership | `isEndpointKind('httpz')`; `isEndpointKind('adminx')` | Both resolve `false` — a superstring of a valid kind is not itself a valid kind |
| status-server-monitor-endpoint-kinds-007 | type-guard-narrowing | `const k: string = 'admin'; if (isEndpointKind(k)) { const narrowed: EndpointKind = k; }` | The assignment to `narrowed` compiles only inside the `if` branch; assigning the still-`string`-typed `k` to an `EndpointKind` outside that branch fails to type-check |
| status-server-monitor-endpoint-kinds-008 | non-deploy-kinds-reexport | Import `NON_DEPLOY_KINDS` from this file and separately from `@agentic-toolkit/deploy-platform/engine`, compare with `===`; then check `.has('health')`, `.has('custom')`, `.has('dns')`, `.has('http')`, `.has('frontend')`, `.has('admin')` | The two imports are reference-equal (the same `Set` object); the first three checks resolve `true` and the last three resolve `false` — the same six kinds `classify.test.ts`'s `endpointNeedsWiring` cases exercise against the identical `NON_DEPLOY_KINDS` |
| status-server-monitor-endpoint-kinds-009 | no-side-effects | Import the module with global `fetch`, `console.*`, and `fs` spied, then call `isEndpointKind` several times | Zero recorded calls on any spy, both at import time and after every `isEndpointKind` call |
