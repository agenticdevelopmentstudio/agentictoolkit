<!-- leaf: implement-hub-domain-1/invitations · source: hub-domain-invitations.md -->

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

