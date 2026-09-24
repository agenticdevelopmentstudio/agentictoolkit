---
id: 7e0508b5-cf96-42da-9902-51fbe31b432f
title: 'Hub Domain: Invitations'
domain: agentictoolkit://recipes/hub-domain-invitations
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The Hub''s Invitations domain: three admin-facing topic providers (requests,
  pending users, sent invites) sharing one admin-notes sub-rail, plus the web
  client a recipient uses to preview, verify, accept, and register from an
  invite.'
platforms:
- swift
- macos
- ios
- typescript
- web
tags:
- hub
- invitations
- data-source
- forms
- crud
- notes
depends-on: []
related:
- agentictoolkit://recipes/htdv-engine
- agentictoolkit://recipes/hub-domain-ecosystems
- agentictoolkit://recipes/hub-domain-customers
- agentictoolkit://recipes/auth-client-authentication
references:
- packages/apple/AgenticToolkit/Hub/Features/Invitations/AdminNotesRail.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Invitations/InvitationsModels.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Invitations/InvitesTopic.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Invitations/PendingUsersTopic.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Invitations/RequestsTopic.swift (agentictoolkit)
- packages/web/packages/data/src/invitations/invitations.ts (agentictoolkit)
- packages/web/packages/data/src/invitations/wire.ts (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHubTests/InvitationsTopicsTests.swift (agentictoolkit)
approved-by: ""
approved-date: ""
---

# Hub Domain: Invitations

## Overview

This is a `logic`-root component with no visual surface of its own: it is
the Invitations domain's data shapes, its three admin-facing HTDV topic
providers, their shared admin-notes sub-rail, and the web data client a
registering recipient uses. The two sides describe two different actors
looking at the same domain, not two ports of one feature:

- **Apple (admin side)**: `RequestsTopic`, `PendingUsersTopic`, and
  `InvitesTopic` are `@MainActor` `EcosystemTopicProvider`s that let a Hub
  admin browse and act on `InvitationRequest`s (a prospective user asking to
  join), `PendingUser`s (an admin-created draft awaiting an invite send), and
  `Invite`s (an invite that has already been sent). All three attach the same
  `AdminNotesRail` — a shared per-subject notes sub-rail — as a child level,
  and all three read and write through one injected `InvitationsDataSource`.
- **Web (recipient side)**: `invitationsApi` (`invitations.ts`, with wire
  types in `wire.ts`) is the client a recipient's browser calls when they
  open an invite link: `preview` (what ecosystem, without authenticating),
  `verify` (is this specific code still valid), `accept` (an already
  signed-in user joins), and `registerWithInvite` (a new user creates an
  account from the invite in one call). Nothing here is admin-facing, and
  nothing here is a client for `InvitationsDataSource`'s admin operations —
  the two sides never call into each other.

## Behavioral Requirements

### Cross-cutting

- **main-actor-confinement**: `RequestsTopic`, `PendingUsersTopic`,
  `InvitesTopic` are `@MainActor final class` types, and `AdminNotesRail` is
  a `@MainActor public struct`; every method on all four runs on the main
  actor, and none of the four is `Sendable`, so the compiler keeps every
  instance confined to that actor's isolation domain.
- **data-source-is-class-bound**: `InvitationsDataSource` is declared
  `AnyObject`-constrained (a class-bound protocol), so an injected
  implementation is a reference type; all three topics and `AdminNotesRail`
  hold it as a `let` reference, never copy it.
- **missing-row-yields-empty**: For every one of the three topics, when
  `path.last` (via `RailPath.last`) does not match any row currently held by
  the topic's own last-loaded list, `detail(for:in:)` (or, for
  `PendingUsersTopic`, `inviteDetail(for:in:)`) returns `.empty` rather than
  throwing.
- **errors-wrap-through-hub-error**: Every `async throws` entry point on all
  three topics and on `AdminNotesRail` wraps a caught error with
  `HubError.wrap` before rethrowing or surfacing it as a form's save error,
  so a caller only ever observes `HubError` cases from this domain, never the
  underlying `InvitationsDataSource` error type directly.
- **notes-rail-shared-across-subjects**: `AdminNotesRail` is not itself an
  `EcosystemTopicProvider` — it is a value type each of the three topics
  constructs identically (same `dataSource`, same `ecosystemID`) and attaches
  as a child level keyed by an `AdminNoteSubject` case (`.request`, `.pendingUser`,
  or `.invite`) plus the subject's own id, so the same notes UI and the same
  create/edit/delete behavior back every subject kind without three separate
  implementations.

### InvitationsModels.swift — data shapes

- **invitation-request-shape**: `InvitationRequest` carries `id`, `name`,
  `email: String?`, `phone: String?`, `message: String?`, `requestedAt`,
  `status`, matching what `RequestsTopic` renders.
- **request-contact-derivation**: `InvitationRequest.contact` returns `email`
  if non-blank (via `HubText.nonBlank`), else `phone` if non-blank, else the
  literal string `"—"` — email is preferred over phone whenever both are
  present.
- **pending-user-shape**: `PendingUser` carries `id`, `name`, `email: String?`,
  `phone: String?`, `note: String?`, `createdAt`, `invitedAt: String?`.
- **pending-user-contact-derivation**: `PendingUser.contact` uses the same
  email-else-phone-else-`"—"` fallback as `InvitationRequest.contact`.
- **invite-shape**: `Invite` carries `id`, `name`, `channel` (a raw string,
  e.g. `"email"` or `"sms"`), `destination`, `sentAt`, `status`.
- **invite-channel-title-derivation**: `Invite.channelTitle` maps
  `channel == "email"` to `"Email"`, `channel == "sms"` to `"Text message"`,
  and any other raw value to that raw value unchanged — an unrecognized
  channel is displayed verbatim rather than mapped to a placeholder.
- **draft-user-shape**: `DraftUser` (the write-side counterpart of
  `PendingUser`) carries `name`, `email: String?`, `phone: String?`,
  `note: String?` and is the payload `addPendingUsers` accepts.
- **invitation-channel-note-shape**: `InvitationChannelNote` pairs a
  `channel` string with a `note: String?`, used inside `InvitationSend`.
- **invitation-send-shape**: `InvitationSend` carries `channels:
  [InvitationChannelNote]` (one entry per channel the admin chose to send
  on) and is the payload `sendInvitation` accepts.
- **admin-note-shape**: `AdminNote` carries `id`, `content`, `createdBy:
  String?`, `createdAt` — the read-side shape returned by
  `InvitationsDataSource.notes`.
- **admin-note-headline-derivation**: `AdminNote.headline` splits `content`
  on newlines and returns the first line that is not blank (via
  `HubText.nonBlank`), or the literal string `"(empty note)"` if every line
  is blank or `content` is empty.
- **admin-note-input-shape**: `AdminNoteInput` carries `id: String?`
  (defaulting to `nil` for a new note) and `content`, and is the payload
  `AdminNotesRail.rewrite` sends back to
  `InvitationsDataSource.replaceNotes`.
- **admin-note-to-input-projection**: `AdminNote.input` projects an
  `AdminNote` down to the `AdminNoteInput` `rewrite` needs to round-trip it
  (`id` and `content` only — `createdBy` and `createdAt` are dropped, since
  the write side never sets or changes who authored a note or when).
- **history-entry-shape**: `HistoryEntry` carries `id`, `actorId: String?`,
  `action`, `occurredAt`.
- **history-entry-line-derivation**: `AdminNotesRail.historyText(_:)` renders
  one line per `HistoryEntry` as `"<action> by <actor> on <date>"`, using
  `entry.actorId` if non-blank else the literal string `"system"` for
  `<actor>`, and `HubDates.display(entry.occurredAt)` for `<date>`; an empty
  history array renders as the single literal string `"No history."` rather
  than an empty string.
- **admin-note-subject-enum**: `AdminNoteSubject` is a `.request`,
  `.pendingUser`, or `.invite` case used to scope every `InvitationsDataSource`
  notes/history call and every `AdminNotesRail` HTDV path segment to the
  correct subject kind and id.
- **data-source-contract**: `InvitationsDataSource` declares eleven `async
  throws` methods: `requests`, `deleteRequest`, `pendingUsers`,
  `addPendingUsers`, `deletePendingUser`, `sendInvitation`, `invites`,
  `deleteInvite`, `notes`, `replaceNotes`, `history` — every one scoped by
  `ecosystemID` and, where applicable, by `AdminNoteSubject` and a subject id.

### AdminNotesRail.swift — shared admin-notes sub-rail

- **notes-rail-identity**: `AdminNotesRail.item` is a fixed `HTDVItem` (a
  constant "Notes" navigation entry) that all three topics attach identically
  as the notes child level under a subject's detail.
- **notes-level-shape**: The notes level lists every `AdminNote` for the
  subject via `dataSource.notes(...)`, rendering `note.headline` as each
  row's title, offers a `createAction` labeled `"New note"`, and shows the
  literal empty-state message `"No notes yet."` when the list is empty.
- **notes-detail-dispatch**: `AdminNotesRail.child(path:)` resolves the last
  path segment to a note id, looks that id up in the freshly-loaded notes
  list, and calls `noteDetail(_:)` on a match; on no match it returns
  `.empty` per **missing-row-yields-empty**.
- **notes-create-spec-shape**: The create `FormSpec` has one required
  text-area field keyed `"content"` (blank content produces the Forms
  built-in required-field error), and its save action appends a new
  `AdminNoteInput(id: nil, content: <value>)` to the subject's current notes
  via `rewrite`.
- **notes-detail-spec-shape**: The note-detail `FormSpec` has the same
  required `"content"` field pre-filled with the note's own content, plus a
  read-only `"author"` field showing `note.createdBy` for display only (the
  save action never sends `createdBy` back, so editing this field has no
  effect); saving maps every one of the subject's current notes through
  `rewrite`, replacing only the entry whose `id == note.id` with the edited
  content, and its delete action filters that one note out by id.
- **notes-rewrite-is-read-then-overwrite**: `AdminNotesRail.rewrite` is
  `nonisolated private static`, taking the data source, ecosystem id, subject,
  subject id, and a `@Sendable` transform closure as explicit parameters
  rather than capturing `self`; it fetches the subject's current notes
  (`dataSource.notes(...).map(\.input)`), applies the transform to build the
  full replacement list, and calls `dataSource.replaceNotes(...)` with that
  entire list — every write replaces the whole note collection for that
  subject, not just the one changed note.
- **notes-errors-wrapped**: Every `AdminNotesRail` entry point that can throw
  wraps the underlying error with `HubError.wrap` before it reaches the
  caller, per **errors-wrap-through-hub-error**.

### RequestsTopic.swift

- **requests-topic-identity**: `RequestsTopic` is an `EcosystemTopicProvider`
  constructed with an `InvitationsDataSource` and an `ecosystemID`, backing a
  rail that lists `InvitationRequest`s.
- **requests-list-shape**: The top-level list loads via
  `dataSource.requests(ecosystemID:)`, renders each row's `name` and
  `contact`, and offers no `createAction` — a request is created by the
  prospective user, not by an admin from this rail.
- **requests-detail-nav**: A request's detail level has two children: its
  own `FormDetails` (fields) and the shared `AdminNotesRail` notes level
  scoped to `.request` and the request's id.
- **requests-detail-shape**: The detail form renders read-only fields for
  `name`, `email` (or `"—"` if blank), `phone` (or `"—"` if blank), `message`
  (or `"—"` if blank), `requestedAt` via `HubDates.display`, `status`, and a
  `"history"` field rendering `AdminNotesRail.historyText` over
  `dataSource.history(...)` for `.request`.
- **requests-delete-shape**: The detail's `FormDeleteAction` asks for
  confirmation, then calls `dataSource.deleteRequest(ecosystemID:id:)`.
- **requests-errors-wrapped**: `RequestsTopic`'s list load, detail load, and
  delete all wrap thrown errors per **errors-wrap-through-hub-error**.

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

## Appearance

Not applicable — this is a data-access protocol, three HTDV topic providers,
a shared notes sub-rail, and a web HTTP client, not a visual component.

## States

Not applicable — this is a data-access protocol, three HTDV topic providers,
a shared notes sub-rail, and a web HTTP client, not a visual component; the
`preview` result's `state` discriminant (`"active" | "invalid" | ...`, per
`InvitePreviewRow`) is a data value returned to a caller, not a visual-state
table for this component itself.

## Accessibility

Not applicable — this is a data-access protocol, three HTDV topic providers,
a shared notes sub-rail, and a web HTTP client, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| invitations-001 | requests-list-shape, requests-detail-shape | `RequestsTopic` with one seeded `InvitationRequest`, no history seeded | List row shows `name`/`contact`; detail's `"history"` field is `"No history."` (per `testRequestsListAndDetail`) |
| invitations-002 | requests-errors-wrapped | `dataSource.requests` throws `.offline` | List load rethrows the same `HubError.offline` case (per `testRequestsListLoadFailureWraps`) |
| invitations-003 | history-entry-line-derivation | Two `HistoryEntry` values, one with `actorId: nil` | `historyText` renders one line per entry, the `actorId: nil` entry's actor rendered as `"system"` (per `testHistoryRendersOneLinePerEntry`) |
| invitations-004 | notes-level-shape, notes-create-spec-shape | Notes level for a subject with existing notes, then create with content `"Called them back"` | Level lists existing notes' headlines with a `"New note"` createAction; save appends `AdminNoteInput(id: nil, content: "Called them back")` (per `testNotesLevelListsAndCreates`) |
| invitations-005 | notes-detail-spec-shape | Note `n1` (`"Keep"`) and `n2` edited to `"Edited"` among two existing notes | Save replaces only `n2`'s content, producing `[AdminNoteInput(id: "n1", content: "Keep"), AdminNoteInput(id: "n2", content: "Edited")]` (per `testNoteDetailEditsAndDeletes`) |
| invitations-006 | notes-detail-spec-shape | Delete note `n2` from a two-note list | `rewrite` sends back the list with `n2` filtered out, `n1` unchanged (per `testNoteDetailEditsAndDeletes`) |
| invitations-007 | missing-row-yields-empty | `child(path:)` for a note id not present in the loaded notes list | Returns `.empty` (per `testUnknownNoteIsEmpty`) |
| invitations-008 | pending-users-list-shape, pending-user-detail-shape | `PendingUsersTopic` with one seeded `PendingUser` | List row shows `name`/`contact`, list createAction is `"Add users"`; detail fields render seeded values (per `testPendingUsersListAndDetail`) |
| invitations-009 | add-users-spec-contact-requirement | Save with blank `name` | Rejected with Forms' required-field message for `"name"` (per `testAddUsersSpecRequiresContact`) |
| invitations-010 | add-users-spec-contact-requirement | Save with non-blank `name`, both `email` and `phone` blank | Rejected with `"Enter an email address or a phone number."` (per `testAddUsersSpecRequiresContact`) |
| invitations-011 | add-users-spec-contact-requirement | Save with non-blank `name` and `email` set | Succeeds; `dataSource.addPendingUsers` called with one matching `DraftUser` (per `testAddUsersSpecRequiresContact`) |
| invitations-012 | send-invitation-detail-defaults | Pending user with both `email` and `phone` set | Send-invitation spec's email and sms toggles both default to `true` (per `testSendInvitationDefaultsToAvailableChannels`) |
| invitations-013 | send-invitation-payload-shape | Uncheck sms, add an sms note, save with email still checked | `dataSource.sendInvitation` called with an `InvitationSend` containing only the email channel (per `testSendInvitationDefaultsToAvailableChannels`) |
| invitations-014 | send-invitation-detail-defaults | Pending user with `phone` blank | Sms toggle defaults to `false` (per `testSendInvitationRejectsNoChannelAndMissingContact`) |
| invitations-015 | send-invitation-validation | Uncheck the only checked (email) toggle, save | Rejected with `"Choose at least one channel."` (per `testSendInvitationRejectsNoChannelAndMissingContact`) |
| invitations-016 | send-invitation-validation | Check the sms toggle on a pending user with no `phone` | Rejected with `"This user has no phone number."` (per `testSendInvitationRejectsNoChannelAndMissingContact`) |
| invitations-017 | invites-list-shape, invite-detail-shape | `InvitesTopic` with one seeded `Invite` whose `channel == "email"` | List row shows `name`/`channelTitle`; detail's `channelTitle` field renders `"Email"` (per `testInvitesListAndDetail`) |
| invitations-018 | missing-row-yields-empty | Detail lookup for an invite id not present in the loaded list | Returns `.empty` (per `testUnknownRowIsEmpty`) |
| invitations-019 | invite-channel-title-derivation | `Invite.channel == "push"` | `channelTitle` returns the raw string `"push"` unchanged (traced to `Invite.channelTitle`'s default case; no test covers an unrecognized channel) |
| invitations-020 | preview-is-anonymous-and-folds-failure | `preview(token)` where the backend responds non-2xx | Promise resolves to `{ state: "invalid", ecosystemName: null, maskedDestination: null }`, does not reject (traced to `invitations.ts`; no test file exists for this component) |
| invitations-021 | preview-network-failure-handling | `preview(token)` where the underlying `fetch` call itself rejects (e.g. offline) | Promise rejects with the network error rather than resolving to `{ state: "invalid", ... }` — the open question this recipe records (traced to `invitations.ts`) |
| invitations-022 | verify-is-anonymous-and-throws-status-code | `verify(token, code)` where the backend responds `410` | Throws `Error("410")` (traced to `invitations.ts`) |
| invitations-023 | register-with-invite-extracts-message | `registerWithInvite(token, input)` where the backend responds `403` with a body containing no recognizable `error`/`message`/`detail` field | Throws `Error("Registration failed (403)")` (traced to `invitations.ts`) |
| invitations-024 | register-with-invite-extracts-message | `registerWithInvite(token, input)` where the backend responds `409` with body `{ "error": "Email already registered" }` | Throws `Error("Email already registered")` (traced to `extractErrorMessage` in `client.ts`, applied by `invitations.ts`) |

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

## Deep Linking

Not applicable: none of the seven given sources define a URL scheme, route,
or deep-link handler. The Apple side navigates purely through in-memory
`HTDVItem`/`RailPath` values, not URLs. The web side's `token`/`code` values
are ordinary function parameters supplied by whatever page component owns
the actual `/join`-style route and its query parameters — that route is not
among these given sources.

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

## Accessibility Options

Not applicable: this is a data-access protocol, three HTDV topic providers, a
shared notes sub-rail, and a web HTTP client — none of the seven given
sources reads Reduce Motion, Increase Contrast, or Differentiate Without
Color, since none of them renders anything.

## Feature Flags

Not applicable: none of the seven given sources reads a feature-flag key.

## Analytics

Not applicable: none of the seven given sources calls an analytics or
telemetry API.

## Privacy

- **Data collected**: Apple side — a request's or pending user's `name`,
  `email`, `phone`, `message`/`note`; an admin's free-text note `content`
  and (display-only) `createdBy`; an invite's `channel` and `destination`.
  Web side — `email`, `password`, and `name` (via `registerWithInvite`), plus
  the `token`/`code` identifying the invite itself.
- **Storage**: None of the seven given sources persists anything locally.
  Apple's three topics and `AdminNotesRail` hold no state beyond the
  in-memory rows returned by the last `InvitationsDataSource` call, and every
  write is a pass-through to that injected data source (persistence, if any,
  is that implementation's concern, not given here). The web client's
  `password`, `token`, and `refreshToken` values are never written to
  storage by `invitations.ts` or `wire.ts` themselves — they are handed back
  to the caller unmodified, and it is that caller's own token store (not
  among these given sources) that decides whether and where `token`/
  `refreshToken` are persisted, per **token-and-password-handling**.
- **Transmission**: Apple's contact and note data travels only through the
  injected `InvitationsDataSource`'s own transport (not specified by these
  given sources). Web's `password` travels once, in the body of the single
  `registerWithInvite` POST; `token` travels in a URL query string for
  `preview` and in request bodies for `verify`/`accept`/`registerWithInvite`.
  Whether that transport is TLS-protected is an environment/deployment
  property outside these two files.
- **Retention**: Not defined in any of the seven given sources; retention of
  requests, pending users, invites, notes, and any issued token/refreshToken
  is entirely the concern of the injected `InvitationsDataSource`
  implementation (Apple) or the caller's own token store (web), neither of
  which is among these given sources.

## Logging

Not applicable: none of the seven given sources contains a logging,
`print`, or `console.*` call.

## Platform Notes

- **SwiftUI**: The five Apple files here are model/data/logic types with no
  SwiftUI of their own; a SwiftUI host renders the `HTDVItem`/`FormSpec`
  trees these topics and `AdminNotesRail` produce, exactly as the sibling
  `htdv-engine` and `hub-domain-customers` recipes describe for their own
  topics.
- **Compose**: A Kotlin/Compose port would model `InvitationRequest`,
  `PendingUser`, `Invite`, `AdminNote`, `HistoryEntry`, and the write-side
  `DraftUser`/`AdminNoteInput`/`InvitationSend` as `data class`es, expose
  `InvitationsDataSource` as a `suspend`-fun interface, and drive Compose
  state from a `ViewModel`'s `StateFlow` rather than an `@MainActor` class;
  the notes rewrite-and-replace pattern (per
  **notes-rewrite-is-read-then-overwrite**) ports unchanged as a `suspend`
  function taking an explicit transform lambda.
- **React/Web**: `invitations.ts`/`wire.ts` are already the web
  implementation of the recipient-facing half of this domain; a port of the
  Apple admin-facing half to a web admin console would model
  `InvitationsDataSource` as a set of `fetch`/`authedJson` calls analogous
  to `invitations.ts`'s own shape, and would need to decide, for
  consistency, on one single error-surfacing strategy rather than the three
  different ones `invitations.ts` itself uses today (per the **Error
  states** edge case).
- **AppKit / UIKit**: Neither framework is used by any of the five Apple
  files here; they are UI-framework-agnostic and are consumed the same way
  regardless of whether the host screen is AppKit, UIKit, or SwiftUI, same
  as the sibling `hub-domain-customers` recipe's own topics.
- **WinUI 3**: `InvitationRequest`, `PendingUser`, `Invite`, `DraftUser`,
  `InvitationChannelNote`, `InvitationSend`, `AdminNote`, `AdminNoteInput`,
  and `HistoryEntry` map to plain C# records or classes (no
  `INotifyPropertyChanged` needed, since none of them are bound directly to
  XAML controls); `InvitationsDataSource`'s eleven `async throws` methods map
  to a C# interface of `Task`-returning methods, each caller awaiting and
  catching a typed exception in place of Swift's `throws`/`HubError`. The
  admin-notes read-then-overwrite pattern in
  **notes-rewrite-is-read-then-overwrite** ports directly as a method that
  awaits the current list, applies a `Func<List<AdminNoteInput>,
  List<AdminNoteInput>>` transform, and awaits the replace call — .NET has
  no `nonisolated`/`@Sendable` distinction to preserve, since a plain
  `async` method already carries no actor affinity. For the recipient-facing
  web-equivalent flow, `System.Net.Http.HttpClient` with
  `System.Text.Json` replaces `fetch`/`authedJson`; a WinUI 3 registration
  page collecting `email`/`password`/`name` should route those three fields
  through `PasswordBox`/`Windows.Storage` conventions for the password field
  specifically, never a plain bound string, mirroring the same "never store
  the password" boundary this recipe records in **Privacy**.

## Design Decisions

**Decision**: Document the Apple admin-facing topics and the web
recipient-facing client in one recipe, framed as two actors' views into one
domain rather than as two ports of one feature.
**Rationale**: `RequestsTopic`/`PendingUsersTopic`/`InvitesTopic` and
`invitationsApi` share no code, no data shapes, and no consumer — an admin
never calls `preview`/`verify`/`accept`/`registerWithInvite`, and a
recipient never sees an `InvitationRequest` or an `AdminNote`. Splitting them
into two recipes would hide that they are nonetheless the same domain from
two sides of one invite's lifecycle (a request or pending user becomes an
invite; an invite is what a recipient previews, verifies, and accepts or
registers from).
**Approved**: pending

**Decision**: Take `AdminNotesRail.rewrite`'s dependencies (`dataSource`,
`ecosystemID`, subject, subject id, transform) as explicit `Sendable`
parameters on a `nonisolated static` function rather than capturing `self`
on an instance method.
**Rationale**: The source's own doc comment on `rewrite` explains this
directly: capturing `self` (a `@MainActor` struct) inside a closure that must
itself be `@Sendable` (because `FormAction`/`FormDeleteAction.perform`
require a `@Sendable` closure) would force `AdminNotesRail` itself to be
`Sendable`, which it is not; taking every dependency as an explicit,
already-`Sendable` parameter avoids that requirement entirely.
**Approved**: pending

**Decision**: Reuse `CustomersTopic.emailPattern`/`emailMessage` in the
add-users spec rather than defining a second email pattern/message local to
`PendingUsersTopic`.
**Rationale**: Both domains validate the same shape of value (an email
address) for the same reason (a contact field with the same required-format
semantics); reusing the Customers domain's own constants keeps the two
domains' email validation identical and keeps the pattern/message defined in
exactly one place.
**Approved**: pending

**Decision**: Keep three different error-surfacing strategies across
`preview`, `verify`, `accept`, and `registerWithInvite` rather than
unifying them into one.
**Rationale**: This recipe documents each strategy as the given source
defines it (per **Error states**) rather than silently normalizing them or
treating the divergence as a defect this recipe should paper over; a
reviewer deciding whether to unify these four methods' error handling is a
product/API decision outside the scope of describing the code as it is.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | security |
| [token-lifecycle](agenticdevelopercookbook://compliance/security#token-lifecycle) | partial | security |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | privacy-and-data |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | privacy-and-data |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | access-patterns |

Each of the five Apple files has one clear responsibility (data shapes,
shared notes sub-rail, and three thin per-collection topic providers that
each only render/dispatch and delegate persistence to the injected
`InvitationsDataSource`), and the web side splits wire types from the
request-shaping client the same way — **separation-of-concerns** passes.
**unit-test-coverage** is partial: `InvitationsTopicsTests.swift` exercises
all three Apple topics and the shared notes rail with twelve test methods,
but no test file exists anywhere in this repo for `invitations.ts`/`wire.ts`,
and grepping the repo turns up no consumer of `invitationsApi` either — its
own consumer, and any tests for it, live outside this repo.
**explicit-error-handling** is partial: the Apple side wraps every error
uniformly through `HubError.wrap`, and three of the web side's four methods
handle their own failure path explicitly, but `preview`'s bare `fetch` call
is not guarded against a network-level failure despite the source's own
"Never throws" doc comment — the open question on
**preview-network-failure-handling**. **secure-storage** passes: neither
`invitations.ts` nor `wire.ts` stores the `password`, `token`, or
`refreshToken` values they handle — they are forwarded and returned only,
per **token-and-password-handling** — so this component itself never needs,
and never uses, platform secure storage. **token-lifecycle** is partial: the
web client receives a `token`/`refreshToken` pair from `accept` and
`registerWithInvite`, but neither issues, refreshes, nor rotates them
itself, and lifetime/rotation policy is not defined anywhere in these two
given files — that responsibility belongs to the caller's own token store.
**no-pii-in-logs** passes trivially: none of the seven given sources
contains a single logging call, so no PII can leak through logging here.
**data-minimization** passes: every DTO and form on both platforms carries
only the fields its own screen or endpoint needs (contact fields, note
content, or the four `registerWithInvite` fields), with no superfluous data
collected. **error-response-handling** is partial: the Apple side handles
every `InvitationsDataSource` failure identically via `HubError`, but the
three divergent web strategies documented under **Error states** mean a
caller of `invitations.ts` cannot assume one uniform error shape across its
four methods.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
