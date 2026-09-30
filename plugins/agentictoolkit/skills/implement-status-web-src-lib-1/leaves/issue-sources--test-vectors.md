<!-- leaf: implement-status-web-src-lib-1/issue-sources--test-vectors · source: status-web-src-lib-issue-sources.md -->

# Issue Sources

## Conformance Test Vectors

Vector 001 is traced to the assertions in `issue-sources.test.ts` ("includes dns as a first-class source with a label"). Vector 002 is traced to `row-model.test.ts` (the `cloudflare-pages` source-filter regression). The rest are traced to the declarations in `issue-sources.ts`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| issue-sources-001 | order-members, label-non-empty, label-values | `ISSUE_SOURCES.includes("dns")`; `SOURCE_LABEL.dns`; `SOURCE_LABEL[s]` for each s in `ISSUE_SOURCES` | `true`; `"DNS"`; every value truthy |
| issue-sources-002 | source-spelling, guard-true | `isIssueSource("cloudflare-pages")`; `new Set(ISSUE_SOURCES).has("cloudflare-pages")` | `true`; `true` |
| issue-sources-003 | order-canonical, order-members | Read `ISSUE_SOURCES` | `["dns", "http", "glitchtip", "vercel", "cloudflare-pages", "railway", "crunchy"]`, length 7 |
| issue-sources-004 | label-values, label-map-total | `Object.entries(SOURCE_LABEL)` | Exactly seven pairs: dns/"DNS", http/"HTTP", glitchtip/"GlitchTip", vercel/"Vercel", cloudflare-pages/"Cloudflare", railway/"Railway", crunchy/"Crunchy Bridge" |
| issue-sources-005 | guard-true, guard-order-source | `isIssueSource(s)` for each s in `ISSUE_SOURCES` | `true` for all seven |
| issue-sources-006 | guard-false, source-spelling | `isIssueSource("cloudflare")` | `false` |
| issue-sources-007 | guard-false, guard-no-normalization | `isIssueSource("DNS")`; `isIssueSource(" http")`; `isIssueSource("http ")` | `false` for all three |
| issue-sources-008 | guard-false, guard-no-throw | `isIssueSource("")`; `isIssueSource("deploy")` | `false`, `false`; no exception |
| issue-sources-009 | guard-signature | In a typed context, `const s: string = "railway"; if (isIssueSource(s)) { const k: IssueSource = s; }` | Compiles; `s` is narrowed to `IssueSource` inside the branch |
| issue-sources-010 | label-unguarded-index | `(SOURCE_LABEL as Record<string, string>)["netlify"]` | `undefined` |
| issue-sources-011 | label-map-total | Type-check a `SOURCE_LABEL` literal with the `crunchy` key removed | Type error: property `crunchy` is missing |
| issue-sources-012 | source-union | Type-check `const k: IssueSource = "cloudflare"` | Type error; `"cloudflare"` is not assignable to `IssueSource` |
| issue-sources-013 | stuck-threshold-value | Read `STUCK_DEPLOY_MS` | `1800000` |
| issue-sources-014 | mirror-union, mirror-labels, mirror-order, stuck-threshold-mirror | Compare the client exports with the server's `ISSUE_SOURCES`, `SOURCE_LABEL` and `STUCK_DEPLOY_MS` | Arrays deep-equal in order; label maps deep-equal; thresholds equal |
| issue-sources-015 | stuck-not-client-derived | Search status-web sources for readers of `STUCK_DEPLOY_MS` outside `issue-sources.ts` | None found |
