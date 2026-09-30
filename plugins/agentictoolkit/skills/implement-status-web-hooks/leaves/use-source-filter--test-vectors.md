<!-- leaf: implement-status-web-hooks/use-source-filter--test-vectors · source: status-web-hooks-use-source-filter.md -->

# useSourceFilter

## Conformance Test Vectors

| ID | Requirements | Input / Precondition | Action | Expected |
|----|-------------|----------------------|--------|----------|
| source-filter-001 | signature, default-all-selected | Fresh mount | Render the hook and read the first result | `sources` equals `{dns, http, glitchtip, vercel, cloudflare-pages, railway, crunchy}` (size 7), iterating in that order. `toggleSource` is a function. |
| source-filter-002 | default-all-selected | Fresh mount | Check `sources.has("cloudflare-pages")` | `true`. This matches `row-model.test.ts`, which asserts "useSourceFilter's default seed selects every ISSUE_SOURCES member" via `new Set(ISSUE_SOURCES).has(...)`. |
| source-filter-003 | toggle-flip, sources-immutability | Default state | Call `toggleSource("http")` | `sources` has 6 members and no `http`. It is a different `Set` instance from before. |
| source-filter-004 | toggle-flip, toggle-order | State after source-filter-003 | Call `toggleSource("http")` | `sources` has 7 members and iterates `dns, glitchtip, vercel, cloudflare-pages, railway, crunchy, http`. |
| source-filter-005 | toggle-may-empty | Default state | Call `toggleSource` once for each of the 7 sources | `sources` is an empty `Set` (size 0). No error is thrown. |
| source-filter-006 | toggle-functional-update | Default state | Call `toggleSource("dns")` and `toggleSource("railway")` in one batched event handler | `sources` has 5 members, neither `dns` nor `railway`. |
| source-filter-007 | toggle-functional-update | Default state | Call `toggleSource("vercel")` twice in one batch | `sources` is back to all 7 members (the two toggles cancel). |
| source-filter-008 | seed-decoupled, lazy-seed | Default state | Call `toggleSource("dns")`, then read `ISSUE_SOURCES` | `ISSUE_SOURCES` still has 7 entries and includes `"dns"`. |
| source-filter-009 | per-instance-state | Two components mounted, each calling the hook | Call `toggleSource("glitchtip")` in the first | The first instance has 6 members. The second still has 7. |
| source-filter-010 | no-persistence | Instance toggled to `{dns}` only | Unmount and remount the component | `sources` is all 7 members again. Web Storage is never touched. |
| source-filter-011 | toggle-identity-unstable | Any state | Force a re-render and compare the returned `toggleSource` with the previous render's | Not reference-equal. `sources` IS reference-equal when no toggle occurred. |
