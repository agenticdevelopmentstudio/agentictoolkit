<!-- leaf: implement-hub-domain-1/invitations--part-2 · source: hub-domain-invitations.md -->

# Hub Domain: Invitations — continued (part 2)

### PendingUsersTopic.swift

- **pending-users-topic-identity**: `PendingUsersTopic` is an
  `EcosystemTopicProvider` backing a rail that lists `PendingUser`s.
- **pending-users-list-shape**: The top-level list loads via
  `dataSource.pendingUsers(ecosystemID:)`, renders each row's `name` and
  `contact`, and offers a `createAction` labeled `"Add users"` that opens the
  add-users spec.
- **add-users-spec-contact-requirement**: The add-users `FormSpec` requires a
  non-blank `"name"` field (Forms' built-in required-field message), and its
  save action rejects the submission with `PendingUsersTopic.contactMessage`
  (the literal string `"Enter an email address or a phone number."`) unless
  at least one of `"email"` or `"phone"` is non-blank; when the check passes
  it calls `dataSource.addPendingUsers(ecosystemID:_:)` with one
  `DraftUser` built from the form's `name`, `email`, `phone`, and `note`
  values.
- **add-users-spec-shared-email-pattern**: The add-users spec's `"email"`
  field reuses `CustomersTopic.emailPattern` and `CustomersTopic.emailMessage`
  directly (from the Customers domain) rather than defining its own email
  pattern and message, so the two domains validate an email address
  identically.
- **pending-user-detail-nav**: A pending user's detail level has three
  children: its own `FormDetails`, an `"invite"` level that opens the
  send-invitation spec, and the shared `AdminNotesRail` notes level scoped to
  `.pendingUser` and the pending user's id.
- **pending-user-detail-shape**: The detail form renders read-only fields for
  `name`, `email` (or `"—"`), `phone` (or `"—"`), `note` (or `"—"`),
  `createdAt` via `HubDates.display`, and `invitedAt` via `HubDates.display`
  (or the fallback `"—"` when `invitedAt` is `nil`).
- **pending-user-delete-shape**: The detail's `FormDeleteAction` asks for
  confirmation, then calls
  `dataSource.deletePendingUser(ecosystemID:id:)`.
- **send-invitation-detail-defaults**: `PendingUsersTopic.inviteDetail(for:in:)`
  is synchronous and non-throwing (unlike every other detail accessor in this
  domain); its `FormSpec` offers one toggle per available channel (email,
  sms), each toggle defaulting to `true` exactly when the pending user's own
  `contact` supplies that channel (e.g. the sms toggle defaults to `true`
  only when `phone` is non-blank) and to `false` otherwise, plus a
  free-text `"note"` field per channel.
- **send-invitation-validation**: The send-invitation save action rejects the
  submission with the literal string `"Choose at least one channel."` if
  every toggle is off; if a toggle for a channel the user has no contact
  value for is turned on, it rejects with a channel-specific literal message
  (e.g. `"This user has no phone number."` for sms with no `phone`).
- **send-invitation-payload-shape**: On success, the save action builds an
  `InvitationSend` with one `InvitationChannelNote` per checked toggle
  (carrying that channel's note field, or `nil` if left blank) and calls
  `dataSource.sendInvitation(ecosystemID:_:)`.
- **pending-users-errors-wrapped**: `PendingUsersTopic`'s list load, detail
  load, and delete wrap thrown errors per
  **errors-wrap-through-hub-error**; `inviteDetail` itself cannot throw (it
  builds a form spec synchronously from data already in memory), so only its
  save action's own `dataSource.sendInvitation` call is subject to wrapping.

### InvitesTopic.swift

- **invites-topic-identity**: `InvitesTopic` is an `EcosystemTopicProvider`
  backing a rail that lists `Invite`s already sent.
- **invites-list-shape**: The top-level list loads via
  `dataSource.invites(ecosystemID:)`, renders each row's `name` and
  `channelTitle`, and offers no `createAction` — an invite is created by
  sending one from a pending user, not directly from this rail.
- **invite-detail-nav**: An invite's detail level has two children: its own
  `FormDetails` and the shared `AdminNotesRail` notes level scoped to
  `.invite` and the invite's id.
- **invite-detail-shape**: The detail form renders read-only fields for
  `name`, `channelTitle` (per **invite-channel-title-derivation**),
  `destination`, `sentAt` via `HubDates.display`, and `status`.
- **invite-delete-shape**: The detail's `FormDeleteAction` asks for
  confirmation, then calls `dataSource.deleteInvite(ecosystemID:id:)`.
- **invites-errors-wrapped**: `InvitesTopic`'s list load, detail load, and
  delete all wrap thrown errors per **errors-wrap-through-hub-error**.

### invitations.ts / wire.ts — recipient-facing acceptance client (web)

- **invitations-api-shape**: `invitationsApi` exposes four methods —
  `preview(token)`, `verify(token, code)`, `accept(token)`,
  `registerWithInvite(token, input)` — each returning a `Promise` of its own
  wire row type from `wire.ts`.
- **preview-is-anonymous-and-folds-failure**: `preview` issues an
  unauthenticated `fetch` (`cache: "no-store"`) to
  `/api/public/invitations/preview`, and its own doc comment states it
  "Never throws": on `!res.ok` it resolves to `{ state: "invalid",
  ecosystemName: null, maskedDestination: null }` rather than rejecting;
  only on a `res.ok` response does it parse and return the body as an
  `InvitePreview`.
- **preview-network-failure-handling**: NEEDS REVIEW: Not implemented in source. `preview`'s own doc comment declares it "Never throws," but the `fetch` call itself is not wrapped in a try/catch, so a network-level failure (offline, DNS failure, request timeout) rejects the returned promise instead of resolving to the documented `invalid` state; missing is either a catch that folds a network exception into the same `{ state: "invalid", ... }` result, or a narrower doc comment scoping "Never throws" to HTTP-status failures only. The open question is whether "Never throws" was meant to cover network failures or only HTTP-status failures.
- **verify-is-anonymous-and-throws-status-code**: `verify` issues an
  unauthenticated `fetch` POSTing `{ code }` to a token-scoped verify route;
  on `!res.ok` it throws `Error(String(res.status))` — the thrown message is
  the raw numeric HTTP status as a string, with no call to
  `extractErrorMessage` and no other message-extraction attempt.
- **accept-is-authenticated**: `accept` calls `authedJson` to POST `{
  token }` to an accept route as the signed-in caller, so its authentication,
  one-refresh-then-retry-on-401, and `AuthHttpError` behavior on failure are
  entirely `authedJson`'s (documented in `agentictoolkit://recipes/auth-client-authentication`),
  not redefined here.
- **register-with-invite-extracts-message**: `registerWithInvite` issues an
  unauthenticated `fetch` POSTing the full `RegisterWithInviteInput` (`email`,
  `password`, `name`, `invite`) to a registration route; on `!res.ok` it reads
  the response body and throws `Error(extractErrorMessage(body,
  \`Registration failed (${res.status})\`))`, so the thrown message favors a
  server-supplied `error`/`message`/RFC 9457 `detail` field and falls back to
  the literal template `"Registration failed (<status>)"` only when none is
  present.
- **wire-types-mirror-response-shape**: `InvitePreviewRow`, `VerifyResultRow`,
  `AcceptResultRow`, and `RegisterWithInviteResultRow` each declare exactly
  the fields their corresponding endpoint returns, with no client-side
  renaming or derived fields — the wire types are a direct typed mirror of
  the JSON each route sends.
- **user-row-reuses-me-row**: `wire.ts` defines `UserRow` as a type alias for
  `MeRow` (imported from `../personas/wire`) rather than declaring a second,
  separately-maintained shape for the user object embedded in
  `RegisterWithInviteResultRow`.
- **token-and-password-handling**: `RegisterWithInviteInput.password` and
  `RegisterWithInviteResultRow.token`/`refreshToken` pass through
  `invitations.ts` and `wire.ts` only as request/response payload fields —
  neither file persists, logs, or otherwise inspects any of the three
  values; both files hand the parsed response back to their caller
  unmodified, and it is that caller's own token store (not among these
  given sources) that decides how `token` and `refreshToken` are kept,
  how long they last, and how they are revoked.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` | `InvitationsDataSource` (apple) | none, required | Injected at each topic's and `AdminNotesRail`'s initializer; the source of every read and write in the Apple side of this domain. |
| `ecosystemID` | `String` (apple) | none, required | Scopes every `InvitationsDataSource` call to one ecosystem; passed at construction. |
| `path` | `[HTDVItem]` (apple) | n/a | Passed into each topic's `child(for:path:rail:)` and `AdminNotesRail.child(path:)` at navigation time; resolved via `RailPath.last`/`RailPath.id(at:in:)`. |
| `rail` | `EcosystemRail` (apple) | n/a | Passed into each topic's `child(for:path:rail:)` per the `EcosystemTopicProvider` contract; not read by any of the three topics' own logic in this domain. |
| `token` | `string` (web) | none, required | Passed to every one of `preview`, `verify`, `accept`, and `registerWithInvite`; identifies which invite the call concerns. Carried in the URL query string for `preview`, in the request body for the other three. |
| `code` | `string` (web) | none, required | Passed to `verify` alongside `token`; the recipient-entered verification code. |
| `input: RegisterWithInviteInput` (`email`, `password`, `name`, `invite`) | object (web) | none, required | Passed to `registerWithInvite`; forwarded to the backend verbatim with no client-side shaping. |
| Endpoint base path | implicit (web) | `/api/*` | Every `fetch`/`authedJson` call in `invitations.ts` targets a relative `/api/...` path; there is no injected base URL or client instance — the host application's own rewrite of `/api/*` onto the backend (noted in the source's own comment) determines where these requests actually land. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, hardcoded) | `"No history."` | `AdminNotesRail.historyText` empty-history fallback |
| (none — literal, hardcoded) | `"(empty note)"` | `AdminNote.headline` all-blank-content fallback |
| (none — literal, hardcoded) | `"New note"` | Notes level `createAction` label |
| (none — literal, hardcoded) | `"No notes yet."` | Notes level empty-state message |
| (none — literal, hardcoded) | `"Add users"` | Pending users list `createAction` label |
| (none — literal, hardcoded) | `"Enter an email address or a phone number."` | Add-users spec contact-requirement save error |
| (none — literal, hardcoded) | `"Choose at least one channel."` | Send-invitation spec no-channel save error |
| (none — literal, hardcoded) | `"This user has no phone number."` / `"This user has no email address."` | Send-invitation spec per-channel save error |
| (none — literal, hardcoded) | `"Email"` / `"Text message"` | `Invite.channelTitle` for `"email"`/`"sms"` |
| (none — literal, hardcoded) | `"—"` | Blank-field display fallback throughout |
| (none — literal, hardcoded) | `"Registration failed (<status>)"` (web, template) | `registerWithInvite`'s fallback error message when the backend supplies none |

Every one of these strings is a hardcoded English literal with no
localization key or lookup mechanism in any of the seven given sources; this
is stated as a plain fact of the current source, not a gap.

