<!-- leaf: implement-general-1/invitation-panes--edge-cases · source: invitation-panes.md -->

# InvitationPanes

## Edge Cases

- **Null/empty input**: `rows=[]` on any pane is passed straight through to
  `ListWithDetailsPane`, which shows the pane's `emptyLabel`; this file adds no
  special-casing of its own for an empty list. Activating "Send invitation"
  with `ids=[]` (only reachable by bypassing `requiresSelection`) seeds
  `{emails: [], phones: [], ids: []}` and still opens the modal — the source
  places no additional guard on `openSend` itself.
- **Boundary values**: Selecting more than one row and activating "Admin
  notes" still opens notes for only `ids[0]`; the remaining selected ids are
  silently ignored by that handler (Delete and Send instead act on the whole
  `ids` array).
- **Note-fallback quirk**: `InvitationRequestsPane`'s note line uses
  `r.note || "—"` (falsy check), so an empty-string note renders `—`.
  `InvitationPendingUsersPane`'s note line uses `u.lastNote ?? "—"` (nullish
  check only), so an empty-string `lastNote` renders as blank, not `—` — the
  two panes are NOT symmetric here even though their detail layout looks the
  same.
- **Remount-key collision**: `SendInvitationModal`'s `key` is built from the
  seed's joined `emails` and `phones` (`remounts-send-modal-on-reseed`). Two
  different selections that resolve to the same email/phone set — or two
  selections that both have no email and no phone at all — produce the same
  key, so the modal does not remount between them and stale edits from the
  first selection can leak into the second; the source places no additional
  disambiguator (e.g. the seed's `ids`) on the key.
- **Error states**: The one error path the source defines is `onSend`
  rejecting: `.then(() => setSendOpen(false), () => undefined)` discards the
  rejection reason entirely — no error message, log, or re-throw — and only
  leaves the modal open (see `keeps-send-modal-open-on-reject`,
  `reports-send-rejection-reason`, and Design Decisions). `onDelete` and
  `onAdd` are synchronous `void` callbacks in this file; it performs no error
  handling around them, so any failure handling for those two happens in the
  caller's own implementation, outside this file.
- **Concurrent access**: Not applicable — traced. `notesForId`, `sendOpen`,
  `sendSeed`, and `addOpen` are single-writer `React.useState` values updated
  only from this component's own event handlers on the main thread; the file
  defines no shared or cross-session mutable state.
- **Offline/disconnected state**: Not applicable — traced. The file performs no
  network access itself (per its own doc comment, "the shared blocks never
  fetch"); `rows`, `onDelete`, `onSend`, and `onAdd` are all caller-supplied, so
  connectivity handling belongs entirely to the caller.
