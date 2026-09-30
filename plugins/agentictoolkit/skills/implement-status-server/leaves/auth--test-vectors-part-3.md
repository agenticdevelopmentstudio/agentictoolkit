<!-- leaf: implement-status-server/auth--test-vectors-part-3 · source: status-server-auth.md -->

# Status Server Auth — Conformance Test Vectors (part 3)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-auth-040 | violation-resolves-to-an-explicit-outcome | Every failure path exercised above (016, 017, 019, 025, 026, 027, 028) | Each resolves one specific status (`500`, `500`, `400`, `502`, `502`, `401`, `502`) — none resolves `200`/`302` |
