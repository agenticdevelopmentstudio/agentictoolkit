<!-- leaf: implement-status-web-src-lib-1/project-key--test-vectors · source: status-web-src-lib-project-key.md -->

# Project Key

## Conformance Test Vectors

No test file exercises `project-key.ts`; these vectors are derived from the function bodies.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| project-key-001 | key-format | `projectKeyOf({ platform: "railway", projectName: "api" })` | `"railway\|api"` |
| project-key-002 | key-raw-platform, key-no-trimming | `projectKeyOf({ platform: "Railway", projectName: " api " })` | `"Railway\| api "` (case and spaces preserved) |
| project-key-003 | key-input-shape | `projectKeyOf({ platform: "vercel", projectName: "web", domain: "x.app", env: "prod" })` | `"vercel\|web"` |
| project-key-004 | key-format | `projectKeyOf({ platform: "", projectName: "" })` | `"\|"` |
| project-key-005 | unique-first-seen-wins, unique-identity-preserved | `[A={railway,api,env:"production"}, B={railway,api,env:"staging"}, C={railway,api,env:"testing"}]` | `[A]` (same object as A) |
| project-key-006 | unique-order-preserved, unique-key-equality | `[X={vercel,web}, Y={railway,api}, Z={vercel,web}, W={railway,db}]` | `[X, Y, W]` |
| project-key-007 | unique-new-array | Input array `[X]`, call `uniqueByProject` | Result `!==` input; input still has length 1 and identical contents |
| project-key-008 | key-raw-platform, unique-key-equality | `[{platform:"railway",projectName:"api"}, {platform:"Railway",projectName:"api"}]` | Both entries kept (keys differ by case) |
| project-key-009 | unique-generic-element | `uniqueByProject([])` | `[]` |
| project-key-010 | per-call-state | Call `uniqueByProject([X])` twice | Each call returns `[X]` |
| project-key-011 | key-determinism | Two calls with `{platform:"fly",projectName:"svc"}` | Both return `"fly\|svc"` |
| project-key-012 | pure-functions, no-errors-raised | Any well-typed input to either function | Returns a value without throwing; no network, storage or console activity observed |
| project-key-013 | key-single-source | Review modal checks project P (adds `projectKeyOf(P)` to the ignore set); provider filters pending entries by `ignoreKeys.has(projectKeyOf(p))` | Every per-environment entry of P matches the filter |
| project-key-014 | unique-production-representative | `[S={railway,api,env:"staging"}, P={railway,api,env:"production"}]` | `[S]` (no reordering toward production) |
