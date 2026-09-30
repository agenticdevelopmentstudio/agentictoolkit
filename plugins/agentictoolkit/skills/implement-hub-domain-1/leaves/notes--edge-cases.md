<!-- leaf: implement-hub-domain-1/notes--edge-cases · source: hub-domain-notes.md -->

# Notes Client

**Rules** (cite as `implement-hub-domain-1/notes--edge-cases#<slug>`):

- `empty-filters-object` MUST — notesApi.list({}) MUST return every note-marked document in the (optionally workspace-scoped) corpus: q, category, and …
- `blank-string-filter-values` MUST — notesApi.list({ q: " " }) MUST behave identically to notesApi.list({}): listQuery trims each filter and omits it from …
- `empty-string-id` MUST — notesApi.get(""), .update("", ...), and .remove("") MUST encode the id via encodeURIComponent and send the resulting …
- `create-with-only-content` MUST — notesApi.create({ content: "x" }) MUST send a body with category and tags both absent (the caller's choice, not a …
- `boundary-exactly-200-matching-notes` MUST — notesApi.list MUST return all 200 rows in one call.
- `boundary-201st-matching-note` MUST — MUST be silently omitted from the result, per list-page-size-fixed.
- `re-creating-an-existing-category-under-the-same-parents` MUST — Per markdown.ts's comment on createCategory, this MUST succeed idempotently (no 409) when every parent requested is …
- `re-creating-an-existing-category-under-a-different-conflicting-set-of-parents` MUST — MUST reject with the mapped 409 message described in create-category-conflict-message.
- `concurrent-access-two-notesapi-create-calls-fired-without-awaiting-between-them` MUST — Per stateless-client and create-not-idempotent, each call MUST independently POST and MUST resolve to a distinct …
- `concurrent-access-taxonomyapi-removecategoryparent-racing-taxonomyapi-addcategoryparent-on-the-same-category` MUST — removeCategoryParent reads the category's current parent edges, then deletes the ones matching the given parentId, in …
- `error-state-backend-unreachable` MUST — Any notesApi operation's authedJson/authedRequest call rejecting with a network error MUST propagate that rejection …
- `error-state-non-2xx-status-other-than-the-mapped-409` MUST — A 403, 404, or 500 from any operation other than createCategory MUST propagate unmodified; no operation besides …
- `error-state-repeated-remove-on-an-already-removed-id` MUST — MUST send a second DELETE and MUST propagate whatever the backend returns for it (e.g. a 404); this client does not …
- `offline-or-disconnected-state` MUST — Every notesApi operation is a single network round trip with no built-in timeout, retry, backoff, or offline queue; a …

## Edge Cases

- **Empty filters object.** `notesApi.list({})` MUST return every note-marked document in the (optionally workspace-scoped) corpus: `q`, `category`, and `tag` are all omitted from the query string when absent, per `markdown.ts`'s `listQuery`.
- **Blank-string filter values.** `notesApi.list({ q: " " })` MUST behave identically to `notesApi.list({})`: `listQuery` trims each filter and omits it from the query string when the trimmed value is empty.
- **Empty-string id.** `notesApi.get("")`, `.update("", ...)`, and `.remove("")` MUST encode the id via `encodeURIComponent` and send the resulting request unchanged — this client performs no non-empty validation on `id` before building the URL; whatever status the backend returns for that malformed path MUST propagate per `errors-propagate-unmodified`.
- **Create with only `content`.** `notesApi.create({ content: "x" })` MUST send a body with `category` and `tags` both absent (the caller's choice, not a client default); if the backend's response also omits `tags`, the resolved `Note.tags` MUST still be `[]` per `tags-array-guaranteed`.
- **Boundary: exactly 200 matching notes.** `notesApi.list` MUST return all 200 rows in one call.
- **Boundary: 201st matching note.** MUST be silently omitted from the result, per `list-page-size-fixed`.
- **Re-creating an existing category under the same parents.** Per `markdown.ts`'s comment on `createCategory`, this MUST succeed idempotently (no 409) when every parent requested is already one of that category's current parents.
- **Re-creating an existing category under a different, conflicting set of parents.** MUST reject with the mapped 409 message described in `create-category-conflict-message`.
- **Concurrent access: two `notesApi.create` calls fired without awaiting between them.** Per `stateless-client` and `create-not-idempotent`, each call MUST independently POST and MUST resolve to a distinct document with its own id; neither call MUST observe or be blocked by the other.
- **Concurrent access: `taxonomyApi.removeCategoryParent` racing `taxonomyApi.addCategoryParent` on the same category.** `removeCategoryParent` reads the category's current parent edges, then deletes the ones matching the given `parentId`, in two separate requests; a parent link added by a concurrent `addCategoryParent` call after that read completes MUST NOT be included in the delete loop, because the read is a snapshot (documented in `taxonomy.ts`'s module comment on the same snapshot property for `addCategoryParent`).
- **Error state: backend unreachable.** Any `notesApi` operation's `authedJson`/`authedRequest` call rejecting with a network error MUST propagate that rejection unmodified, per `errors-propagate-unmodified` and `no-client-side-retry` — no retry is attempted.
- **Error state: non-2xx status other than the mapped 409.** A 403, 404, or 500 from any operation other than `createCategory` MUST propagate unmodified; no operation besides `createCategory` defines special-case status handling.
- **Error state: repeated `remove` on an already-removed id.** MUST send a second DELETE and MUST propagate whatever the backend returns for it (e.g. a 404); this client does not treat a repeat `remove` call as a guaranteed no-op.
- **Offline or disconnected state.** Every `notesApi` operation is a single network round trip with no built-in timeout, retry, backoff, or offline queue; a connectivity loss mid-request MUST surface as a rejected promise (an unmodified network error) with no automatic reconnection or replay.
