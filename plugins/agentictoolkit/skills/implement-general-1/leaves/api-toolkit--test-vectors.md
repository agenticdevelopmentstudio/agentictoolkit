<!-- leaf: implement-general-1/api-toolkit--test-vectors · source: api-toolkit.md -->

# ApiToolkit

## Conformance Test Vectors

| # | Input | Expected output/effect | Source |
|---|---|---|---|
| 1 | `methodTextClass('GET')` | Equals `methodBadgeClass('GET').split(' ')[0]` for every method (GET/POST/PUT/PATCH/DELETE/TRACE) | `tone.ts`; asserted by `tone.test.ts` |
| 2 | `methodDotClass('TRACE')` (an unrecognized method) | Falls back to the neutral dot class rather than throwing or returning `undefined` | `tone.ts`; asserted by `tone.test.ts` |
| 3 | `canReadTable({ exposure: 'admin' }, false)` | `false` (admin-only table denied to a non-admin viewer) | `exposure.ts`; asserted by `exposure.test.ts` |
| 4 | `canWriteTable({ exposure: 'catalog' }, false)` | `false` (catalog is readable but not writable by a non-admin) | `exposure.ts`; asserted by `exposure.test.ts` |
| 5 | `isColumnEditable(relationalColumn, { [relationalColumn.name]: true }, 'edit')` | `false` — an override cannot force a relational column editable outside `create` | `editability.ts`; asserted by `editability.test.ts` |
| 6 | `isRowDirty(baseline, {})` then `isRowDirty(baseline, { name: baseline.name })` | `false` in both cases — no edits, and an edit typed back to the baseline value | `edits.ts`; asserted by `edits.test.ts` |
| 7 | `removeRow(meta, row)` against an endpoint that answers `204 No Content` | Resolves via `authedRequest` (body discarded); calling `authedJson` on the same response would throw | `useCrudResource.ts`; corroborated by `authedJson`'s documented 204 behavior in `auth/client.ts` |
| 8 | Two list calls issued in quick succession where the first (older `listSeq`) resolves after the second (newer `listSeq`) | Only the newer response's rows are written to state; the stale, later-arriving response is discarded | `useCrudResource.ts`; asserted by `useCrudResource.test.tsx` |
| 9 | `endpointSlug({ path: '/users/{id}', method: 'GET' })` | `'users-id-get'` — braces stripped, method lower-cased and appended | `slug.ts` (no dedicated test file found) |
| 10 | `buildRequest(meta, values)` with no `token` argument, versus the same call with a `token` | No `Authorization` header in the first case; `Authorization: Bearer <token>` present in the second | `buildRequest.ts` (no dedicated test file found) |
