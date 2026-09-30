<!-- leaf: implement-general-1/api-toolkit--edge-cases · source: api-toolkit.md -->

# ApiToolkit

## Edge Cases

- **Unfilled path parameter**: `substitutePath` leaves an unmatched `{name}`
  segment visible, unencoded, in the built path rather than erroring or
  omitting the segment — a deliberate, documented rendering choice, not a
  gap.
- **Cyclic schema**: `schemaToExample`'s `seen`-set threading guarantees
  termination on a schema that refs itself directly or transitively.
- **Slug collision**: two endpoints that would project to the same slug
  cause `slug.ts`'s lazily-built index to throw at build time rather than
  silently aliasing one endpoint's reference page onto another's.
- **External (non-local) `$ref`**: `refName` only resolves local
  `#/components/schemas/` references; a schema containing a `$ref` outside
  that scope is not resolved by `refName` and falls through
  `schemaToExample`'s remaining precedence steps (this API's generated
  OpenAPI schemas are self-contained, so this scope limitation is a design
  decision — see Design Decisions — not a runtime failure mode).
- **Out-of-order network responses**: `useCrudResource`'s `listSeq` guard is
  the specified defense against a slow list response overwriting a newer
  one; a mutation (`createRow`/`updateRow`/`removeRow`) has no equivalent
  sequence guard because those calls are not re-issued concurrently against
  the same resource by the hook itself.
- **Concurrent access to `EDITABLE_OVERRIDES`**: this module-level object is
  empty (`{}`) by default and is intended as static, hand-populated
  configuration; production code never mutates it at runtime. Only test code
  mutates and restores it. Because JavaScript execution is single-threaded,
  this is not a concurrency hazard in practice — it is a fact about the
  module's intended use, not an unresolved gap.
- **Network-level failure of a built request**: an offline/DNS/CORS failure
  rejects `executeRequest`'s promise instead of producing an `ApiResult` (see
  `network-failure-propagation`); the caller turns it into an error message.
- **Hung request**: no timeout or `AbortController` bounds the request built by
  `buildRequest`/`executeRequest` (see `request-timeout`); a connection that
  never resolves keeps the request in flight.
