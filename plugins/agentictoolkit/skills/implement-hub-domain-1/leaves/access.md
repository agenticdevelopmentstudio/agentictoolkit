<!-- leaf: implement-hub-domain-1/access · source: hub-domain-access.md -->

**Rules** (cite as `implement-hub-domain-1/access#<slug>`):

- `feature-list-scoped-by-workspace` MUST
- `feature-list-unwraps-envelope` MUST
- `feature-row-shape-validated` MUST
- `feature-order-preserved` MUST
- `fallback-features-not-invoked-automatically` MUST
- `fallback-features-fixed-set` MUST
- `role-list-scoped-by-workspace` MUST
- `role-create-request-shape` MUST
- `role-update-excludes-slug` MUST
- `role-update-request-shape` MUST
- `role-delete-request-shape` MUST
- `assignment-list-workspace-wide` MUST
- `assignment-list-item-scoped` MUST
- `assignment-put-upserts-one-per-scope` MUST
- `assignment-delete-request-shape` MUST
- `item-restrict-request-shape` MUST
- `item-restore-request-shape` MUST
- `item-restrict-restore-parse-body` MUST
- `effective-request-shape` MUST
- `effective-response-shape` MUST
- `every-call-url-encodes-identifiers` MUST
- `no-compact-on-write-bodies` MUST
- `no-client-side-cache` MUST
- `stateless-module` MUST
- `auth-delegated-to-shared-client` MUST
- `session-refresh-waterfall` MUST
- `errors-carry-status-and-code` MUST
- `authorization-enforced-server-side` MUST

# Hub Domain Access Client

## Overview

`access.ts` and `wire.ts`, re-exported by `index.ts`, are the public surface of the workspace roles
& permissions data domain — the client for the gated `/api/access` surface the source calls out in
its own top-of-file comment. Every operation names the workspace by slug (a personal workspace's
customer slug or an org slug); reads answer `404` to non-members, role definition is admin-only, and
assignment/restriction writes need the `M` (manage-access) verb at the target scope, all enforced by
the backend. `wire.ts` holds the wire shapes (`AccessFeatureRow`, `AccessGrantRow`, `AccessRoleRow`,
`AccessAssignmentRow`, `EffectiveAccessRow`); `access.ts` exports the `ACCESS_FEATURES` fallback
constant, the `AccessRoleInput`/`AccessAssignmentInput` write shapes, and the `accessApi` object of
ten methods, each a thin request builder over the shared `authedJson`/`authedRequest` helpers from
`@agentic-toolkit/auth/client` (re-exported through `./http`). It is a headless **logic** module — no
visual surface — so this recipe marks Appearance, States, and Accessibility not applicable and carries
the runtime contract entirely in Behavioral Requirements, per the non-UI component guidance this
recipe was authored under.

## Behavioral Requirements

**Feature areas (`listFeatures`, `ACCESS_FEATURES`)**

- **feature-list-scoped-by-workspace**: `listFeatures` MUST send `GET {BASE}/features` with a
  `workspace=<enc(workspace)>` query parameter, where `BASE` is the fixed constant `/api/access`.
- **feature-list-unwraps-envelope**: `listFeatures` MUST return the bare `features` array unwrapped
  from the `{ features }` response envelope, not the envelope itself.
- **feature-row-shape-validated**: `listFeatures` MUST throw a plain `Error` with the message
  `GET /access/features returned a malformed feature list` when `features` is not an array, or when
  any element is not an object whose `key` and `label` are both non-empty strings.
- **feature-order-preserved**: `listFeatures` MUST return rows in the order the backend sent them; it
  performs no client-side sort or reorder.
- **fallback-features-not-invoked-automatically**: `ACCESS_FEATURES` MUST NOT be substituted
  automatically by `listFeatures` on any failure — it is exported for a caller's own catch block, and
  no code path inside `listFeatures` reads or returns it.
- **fallback-features-fixed-set**: `ACCESS_FEATURES` MUST be exactly the two-entry, order-preserving
  array `[{key:"projects",label:"Projects"},{key:"personas",label:"Personas"}]`.

**Roles (`listRoles`, `createRole`, `updateRole`, `deleteRole`)**

- **role-list-scoped-by-workspace**: `listRoles` MUST send `GET {BASE}/roles?workspace=<enc(workspace)>`
  and return `body.roles` unwrapped and unvalidated — unlike `listFeatures`, no runtime shape check is
  applied to this response.
- **role-create-request-shape**: `createRole` MUST send `POST {BASE}/roles?workspace=<enc(workspace)>`
  with `AccessRoleInput` (`slug`, `name`, `description?`, `defaultFor?`, `grants`) JSON-serialized
  verbatim as the body, and MUST return `body.role`.
- **role-update-excludes-slug**: `updateRole`'s `patch` parameter is typed
  `Partial<Omit<AccessRoleInput,"slug">>`; a role's `slug` MUST NOT be changeable through this
  operation.
- **role-update-request-shape**: `updateRole` MUST send `PATCH {BASE}/roles/<enc(id)>?workspace=<enc(workspace)>`
  with the patch object JSON-serialized verbatim as the body, and MUST return `body.role`.
- **role-delete-request-shape**: `deleteRole` MUST send `DELETE {BASE}/roles/<enc(id)>?workspace=<enc(workspace)>`
  and MUST resolve with no value, discarding whatever body the response carries.

**Assignments (`listAssignments`, `putAssignment`, `deleteAssignment`)**

- **assignment-list-workspace-wide**: `listAssignments` called with no `scope` argument MUST send
  `GET {BASE}/assignments?workspace=<enc(workspace)>` with no `feature`/`itemId` query parameters, and
  MUST return the `{ assignments, restricted? }` body verbatim.
- **assignment-list-item-scoped**: `listAssignments` called with a `scope` argument MUST append
  `&feature=<enc(scope.feature)>&itemId=<enc(scope.itemId)>` to that same URL; unlike
  `AccessAssignmentInput`, `listAssignments`' `scope` type requires `feature` and `itemId` together —
  there is no way to supply only one.
- **assignment-put-upserts-one-per-scope**: `putAssignment` MUST send
  `PUT {BASE}/assignments?workspace=<enc(workspace)>` with `AccessAssignmentInput` JSON-serialized
  verbatim as the body, and MUST return `body.assignment`; per the source's own comment, this grants or
  replaces the one role a given subject holds at a given scope.
- **assignment-delete-request-shape**: `deleteAssignment` MUST send
  `DELETE {BASE}/assignments/<enc(id)>?workspace=<enc(workspace)>` and MUST resolve with no value.

**Item restriction (`restrictItem`, `restoreItem`)**

- **item-restrict-request-shape**: `restrictItem` MUST send
  `POST {BASE}/items/restrict?workspace=<enc(workspace)>` with a `{ feature, itemId }` JSON body.
- **item-restore-request-shape**: `restoreItem` MUST send
  `POST {BASE}/items/restore?workspace=<enc(workspace)>` with a `{ feature, itemId }` JSON body.
- **item-restrict-restore-parse-body**: `restrictItem` and `restoreItem` both call `authedJson`, not
  `authedRequest`, despite declaring `Promise<void>`; each MUST throw the same "unexpected empty
  response" `Error` that `authedJson` throws whenever the backend answers with HTTP 204, rather than
  resolving.

**Effective access (`effective`)**

- **effective-request-shape**: `effective` MUST send
  `GET {BASE}/effective?workspace=<enc(workspace)>&feature=<enc(q.feature)>&subjectKind=<q.subjectKind>&subjectId=<enc(q.subjectId)>`,
  appending `&itemId=<enc(q.itemId)>` only when `q.itemId` is given, and MUST omit that segment from
  the query string entirely (not send `itemId=`) when it is not.
- **effective-response-shape**: `effective` MUST return the parsed body verbatim as an
  `EffectiveAccessRow`, applying no transformation.
- **restricted-flag-shared-meaning**: `EffectiveAccessRow.restricted` and the optional `restricted` on
  `listAssignments`' item-scoped response both describe the same fact — whether the target item was
  marked restricted via `restrictItem` — but `listAssignments`' flag is present only for an item-scoped
  query while `effective`'s is always present.

**Cross-cutting**

- **every-call-url-encodes-identifiers**: every `accessApi` method MUST percent-encode `workspace` and
  any of `id`/`feature`/`itemId`/`subjectId` it places in a URL, via `enc` (`encodeURIComponent`
  aliased in `client-helpers.ts`); `subjectKind` on `effective` is interpolated unescaped because it is
  a closed string-literal union, never caller-supplied free text.
- **no-compact-on-write-bodies**: `createRole`, `updateRole`, and `putAssignment` MUST NOT call
  `compact()` from `client-helpers.ts` on their input before serializing it; they rely on
  `JSON.stringify`'s built-in omission of `undefined`-valued keys, which is sufficient for a plain
  object literal with optional fields.
- **no-client-side-cache**: `accessApi` MUST NOT cache or memoize any response; every call issues
  exactly one HTTP request.
- **stateless-module**: `accessApi` MUST hold no mutable module-level state across calls; the only
  module-level value besides the `BASE` string constant is `ACCESS_FEATURES`, a fixed, read-only array.

### Security

This is a security-relevant recipe: it is the client for a role/permission (authorization) surface.
It carries no secret of its own — the bearer credential lives in `@agentic-toolkit/auth/client`,
which this module composes rather than reimplements — and it performs no client-side authorization
check of its own, deferring entirely to the backend.

- **auth-delegated-to-shared-client**: every `accessApi` network call MUST go through `authedJson` or
  `authedRequest` (re-exported from `@agentic-toolkit/auth/client` via `./http`), which attaches
  `Authorization: Bearer <token>` from `readAccessToken()`; this module MUST NOT read, store, or attach
  a token itself.
- **session-refresh-waterfall**: a `401` response to any `accessApi` call MUST trigger exactly one
  token refresh and one retried request, inherited unconditionally from `authedFetch`; a second `401`
  on the retried request MUST propagate as a thrown `AuthHttpError` with `status: 401`. This module
  defines no refresh or retry logic of its own.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST cause the
  call to throw `AuthHttpError`, carrying the response's HTTP status and, when the body supplies one, a
  machine-readable `code`.
- **feature-validation-error-is-plain**: the `Error` `feature-row-shape-validated` throws carries no
  `status`, so `httpStatus()` (the duck-typed helper in `http.ts`) returns `undefined` for it,
  distinguishing "the backend answered but the body was malformed" from any HTTP-level failure.
- **authorization-enforced-server-side**: `accessApi` MUST NOT perform any client-side permission
  check before sending a request. Per the module's own top-of-file comment, workspace membership, the
  admin-only gate on role definition, and the `M`-verb requirement on assignment and restriction writes
  are enforced entirely by the backend, which answers a non-member's read with `404` rather than `403`
  — so a non-member cannot distinguish "this workspace has no such resource" from "you may not see it."
- **no-escalation-is-a-server-guarantee**: the source's own comment states that the server enforces
  no-escalation on assignment and restriction writes; this file contains no code that checks or blocks
  a self-escalating grant — the guarantee is external to it, not implemented here.

