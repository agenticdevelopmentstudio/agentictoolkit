<!-- leaf: implement-status-web-hooks/use-env-filter--edge-cases · source: status-web-hooks-use-env-filter.md -->

# useEnvFilter

**Rules** (cite as `implement-status-web-hooks/use-env-filter--edge-cases#<slug>`):

- `missing-key` MUST — getItem returns null; the hook MUST keep the default (all selected).
- `empty-string-stored` MUST — "" is falsy; the hook MUST keep the default without parsing.
- `empty-array-stored` MUST — [] is a valid array; the hook MUST hydrate to an empty selection. A consumer that treats "none selected" as "show …
- `only-unknown-names-stored` MUST (for example after an environment is removed from `ENVIRONMENTS`) — the hook MUST hydrate to an empty selection, not the default.
- `non-array-json` MUST (`null`, a number, an object, a quoted string) — the hook MUST keep the default.
- `malformed-json` MUST — the parse exception MUST be caught and the default kept.
- `storage-unavailable` MUST (disabled cookies/site data, sandboxed frame, private mode that throws) — both the read and every write MUST be caught; the hook MUST keep working in memory only, and the choice is lost on …
- `quota-exceeded-on-write` MUST — the in-memory toggle MUST still apply; the stored value stays at its previous content.
- `unknown-environment-passed-to-toggle` MUST — the name MUST be accepted in memory and persisted, then dropped by the next hydration. While it is present, envs.size …
- `several-instances-mounted` MUST — each MUST keep its own selection; the last writer's value is what the next mount hydrates from.
- `another-tab-changes-the-value` SHOULD — the hook SHOULD NOT reflect it until remount, because it registers no storage listener (rationale in Design Decisions).
- `server-render` MUST — storage is never touched during render, so the hook MUST render the default on the server without referencing …

## Edge Cases

- **Missing key**: `getItem` returns `null`; the hook MUST keep the default (all selected).
- **Empty string stored**: `""` is falsy; the hook MUST keep the default without parsing.
- **Empty array stored**: `[]` is a valid array; the hook MUST hydrate to an empty selection. A consumer that treats "none selected" as "show nothing" shows nothing after reload.
- **Only unknown names stored** (for example after an environment is removed from `ENVIRONMENTS`): the hook MUST hydrate to an empty selection, not the default.
- **Non-array JSON** (`null`, a number, an object, a quoted string): the hook MUST keep the default.
- **Malformed JSON**: the parse exception MUST be caught and the default kept.
- **Storage unavailable** (disabled cookies/site data, sandboxed frame, private mode that throws): both the read and every write MUST be caught; the hook MUST keep working in memory only, and the choice is lost on reload.
- **Quota exceeded on write**: the in-memory toggle MUST still apply; the stored value stays at its previous content.
- **Unknown environment passed to `toggle`**: the name MUST be accepted in memory and persisted, then dropped by the next hydration. While it is present, `envs.size` can equal `all.length` without every environment being selected, which misleads a consumer's "unfiltered" check such as `OverviewTab`'s.
- **Toggle before hydration**: cannot occur in practice; React flushes the mount effect before handling a later user event, and all code is single-threaded.
- **Several instances mounted**: each MUST keep its own selection; the last writer's value is what the next mount hydrates from.
- **Another tab changes the value**: the hook SHOULD NOT reflect it until remount, because it registers no `storage` listener (rationale in Design Decisions).
- **Server render**: storage is never touched during render, so the hook MUST render the default on the server without referencing `localStorage`.
- **Timeouts, cancellation, network loss**: not applicable; the hook performs only synchronous `localStorage` calls and no network I/O.
