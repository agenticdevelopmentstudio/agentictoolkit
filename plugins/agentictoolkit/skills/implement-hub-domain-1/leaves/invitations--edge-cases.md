<!-- leaf: implement-hub-domain-1/invitations--edge-cases · source: hub-domain-invitations.md -->

# Hub Domain: Invitations

## Edge Cases

- **Null/empty input**: `HubText.nonBlank` collapses every blank optional
  contact/message/note field to a uniform `nil`/`"—"` fallback across
  `InvitationRequest.contact`, `PendingUser.contact`, and every
  read-only detail field in this domain. `AdminNotesRail`'s create and
  detail specs reject blank `"content"` via Forms' built-in required-field
  check. `PendingUsersTopic`'s add-users spec rejects a blank `"name"`, and
  separately rejects when both `"email"` and `"phone"` are blank, per
  **add-users-spec-contact-requirement**. On the web side, `verify` and
  `registerWithInvite` perform no client-side check on `token`, `code`,
  `email`, `password`, or `name` before sending — an empty string in any of
  those fields is forwarded to the backend exactly as given, and it is the
  backend's response (and, for `registerWithInvite`, `extractErrorMessage`'s
  parsing of that response) that determines the resulting behavior.
- **Boundary values**: None of the seven given sources impose a length,
  count, or range constraint of their own — no maximum note length, no
  maximum number of notes per subject, no maximum channel count in an
  `InvitationSend`, no length constraint on `email`/`password`/`name` in
  `registerWithInvite`. Any such limit is enforced elsewhere (the backend or
  a caller not among these given sources), and this fact is a plain
  statement of scope, not a marker.
- **Concurrent access**: `AdminNotesRail.rewrite` (per
  **notes-rewrite-is-read-then-overwrite**) reads the full notes list, then
  writes back a full replacement list, with no version check or optimistic
  concurrency guard between the two calls; two overlapping edits (or an edit
  overlapping a delete) on the same subject's notes race, and the later
  `replaceNotes` call wins outright, silently discarding whichever edit lost
  the race. This mirrors the same unmitigated create-race already documented
  as a design fact (not a marker) in the sibling `hub-domain-customers`
  recipe: nothing here is silently swallowed and no declared contract is
  violated — `rewrite`'s own doc comment describes exactly this
  read-then-overwrite shape — so it is recorded as a fact rather than as
  the open question this recipe raises elsewhere. All three topics and `AdminNotesRail` are
  `@MainActor`-confined (per **main-actor-confinement**), so within one
  process their own method calls cannot interleave; the race above is only
  across two separate calls (e.g. two devices, or two overlapping requests
  to the same backend), not within one actor's own serialized execution. The
  web client's four methods share no in-memory state across calls, so
  concurrent calls to `preview`/`verify`/`accept`/`registerWithInvite` from
  the same caller raise no concurrency concern within `invitations.ts`
  itself.
- **Error states**: Every Apple-side `async throws` entry point wraps its
  thrown error with `HubError.wrap` per **errors-wrap-through-hub-error**,
  so a caller always observes one of `HubError`'s cases
  (`.unauthorized`, `.forbidden`, `.notFound`, `.offline`, `.conflict`,
  `.validation`, `.transport`, `.unexpected`). The web side has three
  different error-surfacing strategies across its four methods: `preview`
  folds an HTTP failure into a normal `invalid`-state result rather than an
  error (per **preview-is-anonymous-and-folds-failure**); `verify` throws
  the bare numeric status code as its message (per
  **verify-is-anonymous-and-throws-status-code**); `registerWithInvite`
  throws a server-message-first, template-fallback message (per
  **register-with-invite-extracts-message**); `accept` throws whatever
  `authedJson` throws, including its own `AuthHttpError`. This is a genuine
  cross-method inconsistency in how failure is surfaced, but each behavior
  is individually deliberate and documented in its own source, so it is
  recorded here and in Compliance as a fact, not as an open question.
- **Offline/disconnected state**: None of the seven given sources implement
  a timeout, retry, or backoff of their own. On the Apple side, a network
  failure surfaces as whatever `HubError` case the injected
  `InvitationsDataSource` implementation wraps it into (out of scope of
  these given sources). On the web side, `preview`, `verify`, and
  `registerWithInvite` each make exactly one unauthenticated `fetch` call
  with no retry; `accept` inherits `authedJson`'s one-refresh-then-retry
  behavior on a `401` only (documented in
  `agentictoolkit://recipes/auth-client-authentication`), not a general
  offline retry. `preview`'s specific gap for a raw network failure (as
  opposed to an HTTP-status failure) is recorded under
  **preview-network-failure-handling**.
