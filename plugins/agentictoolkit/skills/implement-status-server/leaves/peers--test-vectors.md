<!-- leaf: implement-status-server/peers--test-vectors · source: status-server-peers.md -->

# Status Server Peers

## Conformance Test Vectors

| ID | Requirement(s) | Input | Expected | Trace |
|---|---|---|---|---|
| status-server-peers-001 | normalize-canonical-form, normalize-unparseable-fallback | `normalizePeerBaseUrl("  https://b.example.com/// ")` | `"https://b.example.com"` | peer-base-url.test.ts |
| status-server-peers-002 | normalize-canonical-form | `normalizePeerBaseUrl("HTTPS://B.Example.COM")`, `normalizePeerBaseUrl("https://b.example.com:443")`, `normalizePeerBaseUrl("https://b.example.com/?x=1#frag")` | all three equal `"https://b.example.com"` | peer-base-url.test.ts |
| status-server-peers-003 | normalize-canonical-form | `normalizePeerBaseUrl("http://localhost:3000/")`, `normalizePeerBaseUrl("https://b.example.com/status/")` | `"http://localhost:3000"`, `"https://b.example.com/status"` | peer-base-url.test.ts |
| status-server-peers-004 | normalize-unparseable-fallback | `normalizePeerBaseUrl("  b.example.com/ ")` | `"b.example.com"` | peer-base-url.test.ts |
| status-server-peers-005 | valid-base-url-scheme | `isValidPeerBaseUrl("https://b.example.com")`, `isValidPeerBaseUrl("  https://b.example.com/ ")`, `isValidPeerBaseUrl("http://localhost:3000")` | all `true` | peer-base-url.test.ts |
| status-server-peers-006 | valid-base-url-scheme | `isValidPeerBaseUrl` on `"b.example.com"`, `"/relative"`, `""`, `"ftp://b.example.com"`, `"javascript:alert(1)"`, `"file:///etc/passwd"` | all `false` | peer-base-url.test.ts |
| status-server-peers-007 | same-base-url-comparison | `isSamePeerBaseUrl("https://self.example.com", "https://SELF.example.com:443/")` vs `("https://self.example.com", "https://other.example.com")` vs `("https://self.example.com", "http://self.example.com")` | `true`, `false`, `false` | peer-base-url.test.ts |
| status-server-peers-008 | duplicate-error-detection | `isDuplicatePeerError({ code: "SQLITE_CONSTRAINT_UNIQUE" })`, `isDuplicatePeerError(new Error("UNIQUE constraint failed: peers.base_url"))`, an error whose `cause.code` is `"SQLITE_CONSTRAINT_UNIQUE"` | all `true` | peer-base-url.test.ts |
| status-server-peers-009 | duplicate-error-negative | `isDuplicatePeerError(new Error("SQLITE_CONSTRAINT_NOTNULL"))`, `isDuplicatePeerError(new Error("connection refused"))`, `isDuplicatePeerError(null)`, `isDuplicatePeerError(undefined)` | all `false` | peer-base-url.test.ts |
| status-server-peers-010 | duplicate-message-constant | `DUPLICATE_PEER_MESSAGE` | matches `/already exists/i` | base-url.ts |
| status-server-peers-011 | poll-success-upsert | one active peer `{label:"B", baseUrl:"https://b.example.com", token:"t"}`; fake fetch resolves 200 with `{overall:"healthy"}` | stored row has `reachable === true`, `overall === "healthy"` | peers-fetch.int.test.ts |
| status-server-peers-012 | poll-failure-upsert, poll-never-rejects | same peer, no token; fake fetch throws `Error("ECONNREFUSED")` | `fetchPeers` resolves; stored row has `reachable === false`, `error` contains `"ECONNREFUSED"` | peers-fetch.int.test.ts |
| status-server-peers-013 | poll-endpoint-and-auth | active peer with `token: null` | outbound request headers contain no `Authorization` key | fetch.ts |
| status-server-peers-014 | poll-http-error-becomes-failure | fake fetch resolves a `Response` with `ok: false`, `status: 502` | stored row has `reachable: false`, `error` containing `"HTTP 502"` | fetch.ts |
| status-server-peers-015 | fleet-member-order, fleet-self-member-shape | `assembleFleet(storage, { label: "lewis", snapshot: {status:"ok"}, overall: "healthy" })` with zero active peers | one-element array; element 0 has `self: true`, `baseUrl: null`, `reachable: true`, `label: "lewis"`, `overall: "healthy"`, `payload: {status:"ok"}` | fleet.ts |
| status-server-peers-016 | fleet-peer-member-defaults, fleet-inactive-peers-excluded | one active peer with no matching snapshot row, plus one inactive peer that has a stored snapshot | returned array has exactly 2 elements (self + the active peer); the active peer's member has `overall: null`, `reachable: false`, `fetchedAt` equal to `new Date(0).toISOString()`; the inactive peer never appears | fleet.ts |
| status-server-peers-017 | fleet-peer-member-lookup | two active peers `p1`, `p2`; a stored snapshot exists only for `p2` (`overall:"down"`, `reachable:true`) | `p1`'s member is the epoch default of status-server-peers-016; `p2`'s member reflects only `p2`'s own snapshot | fleet.ts |
| status-server-peers-018 | self-url-canonical-match, self-url-requires-known-public-base-url | `isSelfPeerUrl("https://lewis.example.com", { publicBaseUrl: "https://LEWIS.example.com:443/" })` then `isSelfPeerUrl("https://lewis.example.com", { publicBaseUrl: "" })` | `true`, then `false` | base-url.ts |
| status-server-peers-019 | peer-snapshot-payload-unvalidated | peer responds 200 with JSON body `{overall: 42}` | `fetchPeers` still resolves; stored row has `reachable: true`, `error: null`, and `overall` stored as the numeric value `42` unchanged | fetch.ts |
