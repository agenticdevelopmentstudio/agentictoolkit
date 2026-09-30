<!-- leaf: implement-status-web-hooks/use-integrations--part-2 · source: status-web-hooks-use-integrations.md -->

# useIntegrations — continued (part 2)

**Rules** (cite as `implement-status-web-hooks/use-integrations--part-2#<slug>`):

- `rationale` SHOULD — The source picks the raw method and throws its own short status <status> message. That drops the server's error detail, …

## Design Decisions

**Decision**: The hook fetches through `api.fetch` and checks `ok` itself instead of calling `api.json`.

**Rationale**: The source picks the raw method and throws its own short `status <status>` message. That drops the server's error detail, gives a message that does not name the endpoint, and treats a 204 as a parse failure. All three follow from that one choice and are recorded here so ports keep them. A port SHOULD keep the message format so logs match across platforms. It MAY add the endpoint name only if every sibling hook's port does the same.

**Approved**: pending

---

**Decision**: The query refetches on window focus, and its periodic refresh is left to `useRefreshAll`.

**Rationale**: The integration self-check is the monitor's own health, which `OverviewTab` shows on the default wallboard "so a broken monitor can't hide". The hook turns on `refetchOnWindowFocus` so a returning viewer sees a current verdict. It sets no `refetchInterval` because `useRefreshAll` refreshes all supporting queries together, "so the dashboard never shows a mix of fresh + stale datasets".

**Approved**: pending

---

**Decision**: Staleness, cache lifetime and retry policy are left to the host `QueryClient`.

**Rationale**: The hook sets only `queryKey`, `queryFn` and `refetchOnWindowFocus`. Tests in the package build their `QueryClient` with `retry: false`, and production hosts supply their own defaults. A port gets retry and staleness from the equivalent app-level policy.

**Approved**: pending
