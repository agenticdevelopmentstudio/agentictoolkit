<!-- leaf: implement-general-1/invitation-panes--states · source: invitation-panes.md -->

# InvitationPanes

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Loading (`loading=true`) | Renders "Loading…" instead of the list |
| Populated | Renders `ListWithDetailsPane` with the pane's rows and columns |
| 0 rows selected | "Admin notes" (and, on Pending Users, "Send invitation") stay disabled via `requiresSelection`, per `ListWithDetailsPane`'s own contract |
| Notes modal open | `renderNotesModal` receives `open: true` only while `notesForId` still names a row present in `rows` |
| Send modal open (Pending Users only) | `SendInvitationModal` receives `open: true`, seeded emails/phones, and remounts (new `key`) on a new seed |
| Add modal open (Pending Users only) | `AddUsersModal` receives `open: true` |
| Pressed | Not applicable — traced. `invitation-panes.tsx` renders no button, link, or input directly; every pressable control belongs to a composed component. |
| Focused | Not applicable — traced, for the same reason: no focusable element originates in this file. |
| Disabled | Not applicable — traced. None of the three exports accepts a `disabled` prop or a whole-component disabled state; per-action disabling (`requiresSelection`) is configuration handed to `ListWithDetailsPane`, not a state this file enters itself. |
