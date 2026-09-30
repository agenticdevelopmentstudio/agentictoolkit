<!-- leaf: implement-hub-domain-2/personas--edge-cases · source: hub-domain-personas.md -->

# Hub Domain: Personas

**Rules** (cite as `implement-hub-domain-2/personas--edge-cases#<slug>`):

- `13-declared-facets-resolve-fixed-unavailable-facet` MUST — A facet id present in topicsLevel's rail but outside supportedFacetIDs (8 of the 13 declared facets) MUST resolve to …
- `but-unknown-one-resolve-empty-via-same` MUST — A path whose facet id matches nothing in Self.facets (not merely an unsupported id, but an unknown one) MUST resolve to …
- `selection-service-switched-clear-model-nil-save` MUST — Selecting the "llm" facet's model for a service that does not actually offer that model id (stale selection, or the …
- `create-save-delete-propagate-huberror-never-swallowed` MUST — Any failure from the injected PersonasDataSource (e.g. .offline) on rootLevel(), child(for:), create, save, or delete …

## Edge Cases

- An empty persona list renders `rootLevel()`'s `emptyMessage`, `"No personas yet."`, rather than
  an empty items array with no explanation.
- A facet id present in `topicsLevel`'s rail but outside `supportedFacetIDs` (8 of the 13 declared
  facets) MUST resolve to the fixed unavailable-facet notice, never to a broken or partially-
  rendered form.
- A path whose facet id matches nothing in `Self.facets` (not merely an unsupported id, but an
  unknown one) MUST resolve to `.empty` via the same `guard let facet = ...` as an unknown persona
  id.
- Every blank optional text field on a facet save (`description`, `character`, `voice`,
  `examples`) is mapped to `nil` through `HubText.nonBlank`, never persisted as `""`.
- Selecting the `"llm"` facet's `model` for a service that does not actually offer that model id
  (stale selection, or the service was switched) MUST clear `model` to `nil` on save rather than
  persist a mismatched pair.
- Any failure from the injected `PersonasDataSource` (e.g. `.offline`) on `rootLevel()`, `child(for:)`,
  create, save, or delete MUST propagate as a `HubError`, never be swallowed.
- `canDemoChat` treats a raw config that is not an object at all (`"not even an object"`) the same
  as one that is well-formed but switched off: `false`, with no thrown error.
- `interestDocumentsApi.list` on a corpus with more than 500 documents silently returns only the
  first (oldest-id-first) 500; the caller receives no signal that more documents exist.
- `demoPreviewApi.play` called with a `history` longer than `MAX_PREVIEW_HISTORY_ENTRIES` is
  rejected by the server with a 400; this client sends the caller's history as given and applies
  no truncation of its own.
- `specialInterestsApi.update` given a patch that includes `personaId` or `bucketId` silently
  drops both from the outgoing request rather than sending (and having the server reject) them.
