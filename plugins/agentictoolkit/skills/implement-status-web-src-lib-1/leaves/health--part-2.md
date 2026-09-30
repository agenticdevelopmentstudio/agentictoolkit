<!-- leaf: implement-status-web-src-lib-1/health--part-2 · source: status-web-src-lib-health.md -->

# Health Classification (status-web) — continued (part 2)

## Design Decisions

**Decision**: A health-kind endpoint returning 2xx is down unless its JSON `status` reads `"ok"`.
**Rationale**: A health endpoint can answer 200 while reporting itself unhealthy (`{"status":"degraded"}`, `{"status":"down","ok":false}`). Only the `status` key is read, so a sibling `"ok"` token cannot trip the check (per the test named 'not tripped by the "ok" token').
**Approved**: pending

**Decision**: An unparseable or unknown-shape health body falls through instead of failing down.
**Rationale**: The source comment says a non-JSON body such as an HTML page falls through to the marker and latency checks. A health-kind URL serving HTML is judged by status, marker and latency, not treated as an outage.
**Approved**: pending

**Decision**: A missing `expectBody` marker makes any success candidate down.
**Rationale**: The source comment says "A success status serving the WRONG content (broken shell, takeover page, empty app) is an outage the status code can't see — the marker can." It applies to custom `expectedStatus` matches too.
**Approved**: pending

**Decision**: `expectedStatus` widens the success gate rather than replacing the 2xx rule.
**Rationale**: The gate is `is2xx || statusCode === expectedStatus`. An endpoint expected to return 401 or 403 (an auth-walled page) can be healthy, while any 2xx stays a success candidate for every endpoint.
**Approved**: pending

**Decision**: Latency degrades only above 2 000 ms, using a strict comparison.
**Rationale**: `responseTimeMs > DEGRADED_THRESHOLD_MS`, and the test uses `DEGRADED_THRESHOLD_MS + 1` as the first degraded value. Latency never makes an endpoint down. Down comes only from status, body or marker.
**Approved**: pending

**Decision**: Keep a vendored copy of the server's `health.ts` in status-web instead of importing it.
**Rationale**: status-web is the server's embedded web app and mirrors server vocabularies locally, as it does for `deploy-status` and `board-types`. Unlike those two, this copy has no parity test.
**Approved**: pending
