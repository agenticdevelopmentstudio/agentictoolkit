<!-- leaf: implement-general-1/invitation-panes--test-vectors · source: invitation-panes.md -->

# InvitationPanes

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| invitation-panes-001 | shows-loading-placeholder | Render any of the three panes with `loading=true` | Output is the "Loading…" paragraph; `ListWithDetailsPane` is not rendered |
| invitation-panes-002 | delegates-list-rendering | Render `InvitationRequestsPane` with `loading` false/absent, `rows=[...]` | `ListWithDetailsPane` receives `columns=REQUEST_COLS`, `emptyLabel="No invitation requests."`, `storageKey="adm-inv-requests"` |
| invitation-panes-003 | delegates-list-rendering | Render `InvitationPendingUsersPane` with rows | `ListWithDetailsPane` receives the Pending Users columns, `emptyLabel="No pending users."`, `storageKey="adm-inv-pending"` |
| invitation-panes-004 | delegates-list-rendering | Render `InvitationInvitesPane` with rows | `ListWithDetailsPane` receives the Invites columns, `emptyLabel="No invites sent."`, `storageKey="adm-inv-invites"` |
| invitation-panes-005 | forwards-param-key | Render any pane with `paramKey="sel"` | `ListWithDetailsPane` receives `paramKey="sel"` |
| invitation-panes-006 | forwards-delete-callback | Confirm delete on any pane with rows selected | The pane's `onDelete` prop is invoked with the selected ids |
| invitation-panes-007 | notes-action-requires-selection | Render any pane with 0 rows selected | The "Admin notes" action's `requiresSelection` is `true` (delegated disabling per `ListWithDetailsPane`) |
| invitation-panes-008 | notes-action-sets-first-selected-id | Activate "Admin notes" with rows `["a","b"]` selected | `notesForId` becomes `"a"` |
| invitation-panes-009 | notes-action-sets-first-selected-id | Activate "Admin notes" with `[]` selected | `notesForId` becomes `null` |
| invitation-panes-010 | gates-notes-modal-on-existing-row | Set `notesForId` to an id present in `rows` | `renderNotesModal` is called with `open: true` |
| invitation-panes-011 | gates-notes-modal-on-existing-row | Set `notesForId` to an id, then that row leaves `rows` | `renderNotesModal` is called with `open: false` |
| invitation-panes-012 | resets-notes-id-on-modal-close | Invoke the notes modal's `onClose` | `notesForId` becomes `null` |
| invitation-panes-013 | passes-required-aria-label | Render `InvitationPendingUsersPane` | `ListWithDetailsPane` receives `ariaLabel="Pending users"` |
| invitation-panes-014 | requests-and-pending-show-source-and-note | Select a request row with `source="web"`, `note="urgent"` | Detail shows "Source: web" and "Note to the team: urgent" above the notes/history output |
| invitation-panes-015 | invites-detail-is-notes-only | Select an invite row | Detail is exactly the `renderNotesAndHistory` output; no "Source:"/"Note:" lines appear |
| invitation-panes-016 | send-action-requires-selection | Render `InvitationPendingUsersPane` with 0 rows selected | "Send invitation" action's `requiresSelection` is `true` |
| invitation-panes-017 | send-seed-filters-selected-rows | Activate Send with ids `["u1","u2"]` | The seed is built only from the rows whose id is `u1` or `u2` |
| invitation-panes-018 | send-seed-collects-non-empty-emails | Selected rows have emails `["a@x.io", ""]` | Seed `emails` is `["a@x.io"]` |
| invitation-panes-019 | send-seed-collects-non-empty-phones | Selected rows have phones `["", "+15550100"]` | Seed `phones` is `["+15550100"]` |
| invitation-panes-020 | send-seed-carries-selected-ids | Activate Send with ids `["u1","u2"]` | Seed `ids` is exactly `["u1","u2"]` |
| invitation-panes-021 | send-action-opens-modal | Activate "Send invitation" | `sendOpen` becomes `true` |
| invitation-panes-022 | remounts-send-modal-on-reseed | Open Send for selection A (`ids=["u1"]`, email `a@x.io`), close, open Send for selection B with different contacts (`ids=["u2"]`, email `b@x.io`) | `SendInvitationModal`'s `key` differs between the two opens |
| invitation-panes-023 | closes-send-modal-only-on-resolve | Caller's `onSend` promise resolves | `sendOpen` becomes `false` |
| invitation-panes-024 | keeps-send-modal-open-on-reject | Caller's `onSend` promise rejects | `sendOpen` remains `true`; no error is thrown out of the handler |
| invitation-panes-025 | add-action-has-divider | Inspect the "Add users" action | `dividerBefore` is `true` |
| invitation-panes-026 | add-action-opens-modal | Activate "Add users" | `addOpen` becomes `true` |
| invitation-panes-027 | forwards-onadd | `AddUsersModal` invokes `onAdd(users)` | The pane's `onAdd` prop is called with `users` |
| invitation-panes-028 | forwards-send-busy | Render `InvitationPendingUsersPane` with `sendBusy=true` | `SendInvitationModal` receives `busy=true` |
| invitation-panes-029 | forwards-add-busy | Render `InvitationPendingUsersPane` with `addBusy=true` | `AddUsersModal` receives `busy=true` |
| invitation-panes-030 | shows-delete-confirm-copy | Inspect `InvitationRequestsPane`'s `deleteConfirm` | `{ title: "Delete requests?", description: "This removes the selected invitation requests." }` |
| invitation-panes-031 | shows-delete-confirm-copy | Inspect `InvitationPendingUsersPane`'s `deleteConfirm` | `{ title: "Delete pending users?", description: "This removes the selected pending users." }` |
| invitation-panes-032 | shows-delete-confirm-copy | Inspect `InvitationInvitesPane`'s `deleteConfirm` | `{ title: "Delete invites?", description: "This removes the selected sent invites." }` |
| invitation-panes-033 | requests-and-pending-show-source-and-note | Select a pending-user row with `lastSource="referral"`, `lastNote="thanks"` | Detail shows "Source: referral" and "Note from user: thanks" above the notes/history output |
| invitation-panes-034 | pending-null-dates-render-dash | Render `InvitationPendingUsersPane` with a row whose `lastRequestDate` and `lastInviteSentDate` are both `null` | Both columns render "—" |
