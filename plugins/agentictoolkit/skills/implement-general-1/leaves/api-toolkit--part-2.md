<!-- leaf: implement-general-1/api-toolkit--part-2 · source: api-toolkit.md -->

# ApiToolkit — continued (part 2)

**Rules** (cite as `implement-general-1/api-toolkit--part-2#<slug>`):

- `request-base` MUST
- `path-substitution` MUST
- `body-allowed` MUST
- `request-headers` MUST
- `mutating-methods` MUST
- `response-normalization` MUST
- `network-failure-propagation` MUST
- `endpoint-key` MUST
- `tag-index-caching` MUST
- `tag-ordering` MUST
- `endpoints-for-tag-ordering` MUST
- `highlighter-singleton` MUST
- `highlighter-dual-theme` MUST
- `highlighter-failure-recovery` MUST
- `pretty-json-fallback` MUST
- `ref-resolution-scope` MUST
- `example-cycle-safety` MUST
- `example-precedence` MUST
- `type-label-truncation` MUST
- `field-description-depth` MUST
- `slug-projection` MUST
- `slug-collision-detection` MUST
- `slug-lookup-miss` MUST
- `snippet-token-placeholder` MUST
- `snippet-body-inclusion` MUST
- `curl-snippet-escaping` MUST
- `method-tone-mapping` MUST
- `method-text-class-consistency` MUST
- `status-tone-mapping` MUST
- `server-entry-no-client-directive` MUST
- `client-barrel-excludes-metadata` MUST
- `shared-cache-via-package-path` MUST
- `server-managed-lock` MUST
- `override-precedence` MUST
- `relational-create-only` MUST
- `create-only-lock-on-edit` MUST
- `default-editable` MUST
- `hidden-columns` MUST
- `dirty-detection` MUST
- `draft-merge-immutability` MUST
- `presentation-only-gate` MUST
- `read-allowlist` MUST
- `write-allowlist` MUST
- `fail-closed-on-unknown-tier` MUST
- `order-preserving-filter` MUST
- `schema-allowlist-single-source` MUST

## Behavioral Requirements

### buildRequest.ts

- **request-base**: `API_BASE` MUST be the fixed string `/api`; every built
  request MUST be same-origin relative to this base, never an absolute
  cross-origin URL.
- **path-substitution**: `substitutePath` MUST replace each `{name}` path
  segment with the URL-encoded value from `pathValues` when present, and MUST
  leave a `{name}` segment visible, unencoded, in the resulting path when no
  matching value is supplied.
- **body-allowed**: `bodyAllowed` MUST return `true` only when the endpoint's
  method is one that accepts a body per its metadata; it MUST return `false`
  otherwise so `buildRequest` never attaches a body to a body-less method.
- **request-headers**: `buildRequest` MUST set `Content-Type: application/json`
  only when a body is actually attached, and MUST set
  `Authorization: Bearer <token>` only when a `token` argument is supplied;
  neither header MUST be present when its precondition is absent.
- **mutating-methods**: `isMutating` MUST return `true` for every HTTP method
  except `GET`, `HEAD`, and `OPTIONS`, and MUST return `false` for those three.
- **response-normalization**: `executeRequest` MUST resolve to an `ApiResult`
  for every HTTP status code, `2xx` through `5xx` inclusive, and MUST record
  the elapsed wall-clock duration (via `performance.now()`) on that result;
  it MUST NOT throw for a non-2xx HTTP response.
- **network-failure-propagation**: `executeRequest` MUST let a transport-level
  failure from `fetch` (offline, DNS failure, a CORS block) reject its promise
  rather than resolve to an `ApiResult`; its "never throws" contract covers
  only non-2xx statuses. `ApiEndpointDetail` catches the rejection and shows
  its message through `setError` (falling back to `'Request failed'`).
- **request-timeout**: neither `buildRequest` nor `executeRequest` attaches a
  timeout or an `AbortController` to the underlying `fetch`; a request that
  never resolves stays in flight until the browser gives up.

### getEndpoint.ts

- **endpoint-key**: `endpointKey` MUST derive a unique key from an endpoint's
  method and path such that `getEndpoint` can look up the same endpoint by
  that key.
- **tag-index-caching**: `index()` MUST build the tag-to-endpoints index
  (`_byTag`/`_tags`) lazily, on first use, and MUST reuse the cached result on
  every subsequent call rather than rebuilding it.
- **tag-ordering**: `allTags()` MUST return tags in sorted order.
- **endpoints-for-tag-ordering**: `endpointsForTag(tag)` MUST return that
  tag's endpoints sorted first by path, then by the fixed `METHOD_ORDER`
  ranking for endpoints sharing a path.

### highlight.ts

- **highlighter-singleton**: `highlighterPromise` MUST be created at most once
  per process (module-level cache) and MUST be reused by every subsequent call
  to `highlightToHtml` rather than re-importing/re-initializing shiki.
- **highlighter-dual-theme**: the cached highlighter MUST support both the
  `github-light` and `github-dark` themes and the `json`, `bash`, and
  `javascript` languages.
- **highlighter-failure-recovery**: if highlighter initialization rejects,
  the module MUST reset `highlighterPromise` back to `null` so a subsequent
  call retries initialization rather than being permanently disabled by one
  transient failure.
- **pretty-json-fallback**: `prettyJson` MUST return the original input text
  unchanged when `JSON.parse` fails, and MUST return an empty string for
  blank input; it MUST NOT throw.

### schema.ts

- **ref-resolution-scope**: `refName` MUST resolve only local
  `#/components/schemas/` references; a `$ref` outside that local scope MUST
  NOT be treated as resolved.
- **example-cycle-safety**: `schemaToExample` MUST thread a `seen` set through
  every recursive call so that a cyclic schema (a schema that refs itself,
  directly or transitively) terminates rather than recursing indefinitely.
- **example-precedence**: `schemaToExample` MUST resolve an example value by
  trying, in order: `$ref` resolution, `anyOf`/`oneOf` variant selection,
  `allOf` merge, an explicit `example`, an explicit `default`, the first
  `enum` value, then a type-driven default — stopping at the first
  applicable step.
- **type-label-truncation**: `typeLabel` MUST append a `?` suffix for a
  nullable type, MUST render a union of variants, and MUST truncate an enum
  preview beyond its fourth value with `…` rather than listing every value.
- **field-description-depth**: `describeFields` MUST describe fields exactly
  one level deep (name, type, required, description) after
  `unwrapToObject` has dereferenced/unwrapped `$ref`, array `items`, a
  null-union, and merged `allOf`.

### slug.ts

- **slug-projection**: `endpointSlug(meta)` MUST strip `{param}` braces from
  every path segment and MUST append the method, lower-cased, as the final
  slug segment.
- **slug-collision-detection**: the lazily-built `_slugToKey` index MUST throw
  when two distinct endpoints project to the same slug, rather than silently
  letting the second endpoint alias or shadow the first.
- **slug-lookup-miss**: `endpointForSlug(slug)` MUST return `undefined`, not
  throw, when no endpoint maps to the given slug.

### snippets.ts

- **snippet-token-placeholder**: every generated snippet MUST embed
  `TOKEN_PLACEHOLDER` (the literal string `YOUR_TOKEN`) in place of any real
  bearer token; a generated snippet MUST NOT embed a live, caller-supplied
  token.
- **snippet-body-inclusion**: `bodyText` MUST include a request body in the
  generated snippet only when `meta.requestBody` is non-null and the supplied
  body, once trimmed, is non-empty.
- **curl-snippet-escaping**: `curlSnippet` MUST single-quote an embedded JSON
  body and MUST shell-escape any single quote that occurs inside that body.

### tone.ts

- **method-tone-mapping**: `methodBadgeClass`/`methodDotClass` MUST map each
  of `GET`, `POST`, `PUT`, `PATCH`, `DELETE` to that method's fixed badge/dot
  classes, and MUST fall back to the neutral class for any other method.
- **method-text-class-consistency**: `methodTextClass(method)` MUST always
  equal the first space-delimited token of `methodBadgeClass(method)` for
  every method, so the badge and the text-only rendering can never drift onto
  different palettes.
- **status-tone-mapping**: `statusTone` MUST map `200`–`299` to the green
  tone, `400`–`499` to the orange tone, `500` and above to the red tone, and
  any other status to the muted tone.

### server.ts / index.ts (barrel split)

- **server-entry-no-client-directive**: `server.ts` MUST NOT carry a
  `'use client'` directive, so it can be imported from server-only code
  without pulling client component bundling requirements with it.
- **client-barrel-excludes-metadata**: `index.ts` (the client barrel) MUST
  NOT re-export `getEndpoint`/`API_ENDPOINTS`; a component imported from the
  client barrel MUST NOT bundle the generated endpoint metadata as a
  transitive dependency.
- **shared-cache-via-package-path**: `server.ts` MUST import `allTags`,
  `endpointsForTag`, `getEndpoint`, and `endpointKey` via the package path
  (`@agentic-toolkit/api-explorer/lib/getEndpoint`), not a relative path, so
  that the server entry and the client barrel — two separate build chunk
  graphs — observe the same module-level cache instance rather than each
  forking its own copy.

### editability.ts

- **server-managed-lock**: a column with `serverManaged: true` MUST NOT be
  editable in any mode, regardless of any override.
- **override-precedence**: `EDITABLE_OVERRIDES` MUST take effect only for a
  non-relational, non-server-managed column; an override MUST NOT make a
  relational (primary-key or foreign-key-shaped) column, nor a
  server-managed column, editable.
- **relational-create-only**: a relational column (a `pkParams` member, an
  exact `ID_REF_NAMES` match, or a match against the `ID_REF_SUFFIX` pattern
  `/(Id|_id|Rdid|_rdid)$/`) MUST be editable only when the mode is `create`,
  never in `edit` mode.
- **create-only-lock-on-edit**: a column marked `createOnly` MUST NOT be
  editable once the mode is `edit`.
- **default-editable**: a column that is not server-managed, not relational,
  and not locked by `createOnly` in edit mode MUST be editable by default.
- **hidden-columns**: `isColumnHidden` MUST return `true` only for a
  server-managed column.

### edits.ts

- **dirty-detection**: `isRowDirty(baseline, edits)` MUST return `true` if
  and only if at least one key present in `edits` has a value that is
  strictly (`!==`) different from the same key's value in `baseline`; because
  `edits` MUST carry only the columns that were actually changed, iterating
  its keys MUST be sufficient — `isRowDirty` MUST NOT need to inspect any key
  absent from `edits`.
- **draft-merge-immutability**: `mergeDraft(baseline, edits)` MUST return a
  new object overlaying `edits` onto `baseline`, and MUST NOT mutate either
  `baseline` or `edits`.

### exposure.ts

- **presentation-only-gate**: `canReadTable`/`canWriteTable` MUST be
  documented and treated as presentation-only; they MUST NOT be relied upon
  as the authorization boundary — the server MUST independently re-check
  every request regardless of what the client renders.
- **read-allowlist**: `canReadTable` MUST return `true` for `owner` and
  `catalog` exposure for any viewer, and MUST return `true` for `admin`
  exposure only when `isAdminViewer` is `true`.
- **write-allowlist**: `canWriteTable` MUST return `true` for `owner`
  exposure for any viewer, and MUST return `true` for `catalog` or `admin`
  exposure only when `isAdminViewer` is `true`.
- **fail-closed-on-unknown-tier**: a table whose exposure tier is missing or
  unrecognized MUST be denied both read and write for a non-admin viewer;
  `readableTables` MUST exclude such a table from its filtered result for a
  non-admin viewer.
- **order-preserving-filter**: `readableTables(tables, isAdminViewer)` MUST
  preserve the input order of the tables it retains.

### schemas.ts

- **schema-allowlist-single-source**: `CRUD_SCHEMAS` MUST be computed exactly
  once, at module load, from the generated `CRUD_TABLES`, and MUST serve as
  the single source of truth consulted by both halves of the
  allowlist-to-feature lockstep check.

