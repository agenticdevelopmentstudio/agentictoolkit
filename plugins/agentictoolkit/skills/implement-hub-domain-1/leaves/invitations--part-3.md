<!-- leaf: implement-hub-domain-1/invitations--part-3 · source: hub-domain-invitations.md -->

# Hub Domain: Invitations — continued (part 3)

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
