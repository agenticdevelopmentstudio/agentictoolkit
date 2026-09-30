<!-- leaf: implement-general-1/focused-topic-detail--edge-cases · source: focused-topic-detail.md -->

# Focused Topic Detail (FTD) View

## Edge Cases

- A stale or deleted `lastId` (no longer a live entity) resolves to the All view; the same fallback applies to a deep link built from a pre-rename rdid, since the resolver cannot distinguish "never existed" from "renamed away" (see **explicit-all-precedence**).
- `{basePath}/all` is the **explicit** All view and always shows All regardless of the stored id (**explicit-all-precedence**).
- Local storage is client-only; resolution happens after the list loads to avoid SSR hydration mismatch (**resolve-after-list-load**).
- `PATCH /registry/identifiers/{rdid}` returns 404 if the old rdid is unknown (**rename-unknown-rdid-404**) and 409 on collision (**surface-identifier-collision**); `GET /registry/identifiers/{rdid}/exists` supports inline availability checks (**identifier-availability-check**).
- The type-to-confirm match is exact (`===` rdid), case-sensitive, with no whitespace normalization; because the identifier is lowercased on input, the stored rdid — and so the value being matched against — is always already lowercase.
- The filter empty result shows "No {entities} match \"{query}\".".
