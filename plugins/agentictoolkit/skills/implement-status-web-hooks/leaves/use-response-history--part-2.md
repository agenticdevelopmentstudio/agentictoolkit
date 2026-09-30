<!-- leaf: implement-status-web-hooks/use-response-history--part-2 · source: status-web-hooks-use-response-history.md -->

# useResponseHistory — continued (part 2)

## Design Decisions

**Decision**: The hook polls every 60 seconds with a hard-coded `refetchInterval`.

**Rationale**: The overview graph is a live portfolio summary; the source fixes the period at `60_000` ms in the hook rather than taking it from the caller, so every window length refreshes at the same rate.

**Approved**: pending

---

**Decision**: The hook fetches through `api.fetch` and checks `ok` itself instead of calling `api.json`.

**Rationale**: The source chooses the raw method and throws its own short `response-history <status>` message. As a result it drops the server's error detail and treats a 204 as a parse failure; both follow from that choice, and it matches the sibling `useHistory` hook.

**Approved**: pending

---

**Decision**: The hook sends only `hours` and leaves the bucket count to the backend.

**Rationale**: The backend route accepts `hours` and `buckets`, but the hook sends no `buckets`, so the series length is a backend decision and the consumer draws whatever length arrives.

**Approved**: pending

---

**Decision**: `hours` is passed through without validation.

**Rationale**: The parameter is typed `number` and its only caller supplies fixed constants from `SPANS` (24, 168, 720, 2160). Rejecting out-of-range values is left to the backend route.

**Approved**: pending
