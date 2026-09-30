<!-- leaf: implement-general-1/markdown-core--edge-cases · source: markdown-core.md -->

# MarkdownCore

## Edge Cases

- `documents(marker:)` and `document(id:)` deliberately disagree on how an unreadable timestamp is handled — the list skips and logs the row, the single fetch throws — so a caller reading the same corrupt row through the two paths sees different behavior by design.
- `document(from: Row)` reads the tombstone-timestamp column through a lenient conversion that becomes `nil` on an unparseable value, unlike the required `createdAt`/`updatedAt` columns, which throw; every code path that reaches this conversion already filters to rows the write-time dual-flag invariant keeps non-tombstoned, so the lenient path has no reachable corrupt input in this component as given.
- `mutateDocument`'s merge closure may call back into the store without deadlocking, because the underlying database is reentrant, but a nested write's changes are silently overwritten by the enclosing whole-row write that follows it — the method's own doc comment calls this out as a hazard for the caller to avoid, not a defect in the method.
- `MarkdownRemoteWriter` has no implementation among these six files; its own doc comment states nothing implements it yet, since this component holds no adh credentials to send with.
- Calling `deleteDocument` twice for the same id, or once after the row has already been purged by `truncate`, succeeds both times rather than throwing on the second call.
- Purging `notes`, `docs`, or `papers` alone succeeds when each has no rows; purging `content.markdown` alone while any marker table still has rows is refused regardless of whether that table is empty of *unrelated* rows.
