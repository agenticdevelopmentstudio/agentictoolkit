<!-- leaf: implement-hub-domain-1/invitations--test-vectors · source: hub-domain-invitations.md -->

# Hub Domain: Invitations

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
