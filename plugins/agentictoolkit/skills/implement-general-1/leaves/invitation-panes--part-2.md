<!-- leaf: implement-general-1/invitation-panes--part-2 · source: invitation-panes.md -->

# InvitationPanes — continued (part 2)

## Accessibility

- `invitation-panes.tsx` introduces one semantic element of its own — the
  loading `<p>` — and otherwise delegates all interactive/semantic markup to
  `ListWithDetailsPane` (`role="toolbar"` + `ariaLabel`, per its own recipe),
  `SendInvitationModal`, and `AddUsersModal`.
- **passes-required-aria-label** (Behavioral Requirements) is this file's one
  direct accessibility contribution: `ariaLabel` is typed `required` on
  `ListWithDetailsPaneProps`, so each pane is forced to supply a real,
  human-readable name ("Invitation requests" / "Pending users" / "Sent
  invites") rather than omitting it.
- Toolbar action labels this file defines are all plain-text strings ("Admin
  notes", "Send invitation", "Add users"), not icon-only, so they read
  correctly through `ListWithDetailsPane`'s labeling.
- The swap between the loading paragraph and the populated `ListWithDetailsPane`
  carries no `aria-live` region or other announcement in this file; a screen
  reader is notified of the change only insofar as its own virtual-cursor
  behavior picks up the DOM replacement.
- Minimum tap target: Not applicable to this file directly — traced. No
  tappable element originates in `invitation-panes.tsx`; the toolbar buttons,
  row selection, and modal controls are each `ListWithDetailsPane`'s,
  `SendInvitationModal`'s, or `AddUsersModal`'s own tap-target contract.

## Configuration

### InvitationRequestsPane

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rows` | `InvitationRequest[]` | — | Rows to render. |
| `loading` | `boolean?` | falsy | Shows the loading placeholder instead of the list. |
| `onDelete` | `(ids: string[]) => void` | — | Forwarded to `ListWithDetailsPane`. |
| `paramKey` | `string?` | `undefined` | Forwarded to `ListWithDetailsPane` for URL-based selection deep-linking. |
| `renderNotesAndHistory` | `(s: { subjectTable, subjectId }) => ReactNode` | — | Fills the row detail panel below Source/Note. |
| `renderNotesModal` | `(s: { subjectTable, subjectId, open, onClose }) => ReactNode` | — | Supplies the admin-notes modal. |

### InvitationPendingUsersPane

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rows` | `PendingUser[]` | — | Rows to render. |
| `loading` | `boolean?` | falsy | Shows the loading placeholder instead of the list. |
| `onDelete` | `(ids: string[]) => void` | — | Forwarded to `ListWithDetailsPane`. |
| `onSend` | `(payload: InvitationSendPayload) => Promise<unknown>` | — | Called on Send; modal closes only on resolve. |
| `onAdd` | `(users: DraftUser[]) => void` | — | Forwarded to `AddUsersModal`'s `onAdd`. |
| `sendBusy` | `boolean?` | `undefined` | Forwarded to `SendInvitationModal`'s `busy`. |
| `addBusy` | `boolean?` | `undefined` | Forwarded to `AddUsersModal`'s `busy`. |
| `paramKey` | `string?` | `undefined` | Forwarded to `ListWithDetailsPane` for URL-based selection deep-linking. |
| `renderNotesAndHistory` | `(s: { subjectTable, subjectId }) => ReactNode` | — | Fills the row detail panel below Source/Note. |
| `renderNotesModal` | `(s: { subjectTable, subjectId, open, onClose }) => ReactNode` | — | Supplies the admin-notes modal. |

`SendInvitationModal` and `AddUsersModal` are mounted with no `title` override,
so each keeps its own component default ("Send invitation" / "Add users").

### InvitationInvitesPane

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rows` | `Invite[]` | — | Rows to render. |
| `loading` | `boolean?` | falsy | Shows the loading placeholder instead of the list. |
| `onDelete` | `(ids: string[]) => void` | — | Forwarded to `ListWithDetailsPane`. |
| `paramKey` | `string?` | `undefined` | Forwarded to `ListWithDetailsPane` for URL-based selection deep-linking. |
| `renderNotesAndHistory` | `(s: { subjectTable, subjectId }) => ReactNode` | — | Supplies the entire detail panel. |
| `renderNotesModal` | `(s: { subjectTable, subjectId, open, onClose }) => ReactNode` | — | Supplies the admin-notes modal. |

Shared types: `NotesSlots` (`renderNotesAndHistory`, `renderNotesModal`, used by
all three panes) and `InvitationSendPayload` (`SendInvitationPayload &
{ pendingUserIds: string[] }`, the shape `InvitationPendingUsersPane` hands to
`onSend`).

## Localization

The source hardcodes every user-facing string directly; there is no i18n key
or translation lookup anywhere in `invitation-panes.tsx`.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `loading-message` | "Loading…" | Loading placeholder (all panes) |
| `admin-notes-action` | "Admin notes" | Toolbar action label (all panes) |
| `send-invitation-action` | "Send invitation" | Toolbar action label (Pending Users only) |
| `add-users-action` | "Add users" | Toolbar action label (Pending Users only) |
| `requests-empty-label` | "No invitation requests." | `emptyLabel` (Requests) |
| `pending-empty-label` | "No pending users." | `emptyLabel` (Pending Users) |
| `invites-empty-label` | "No invites sent." | `emptyLabel` (Invites) |
| `requests-delete-confirm-title` | "Delete requests?" | `deleteConfirm.title` (Requests) |
| `requests-delete-confirm-description` | "This removes the selected invitation requests." | `deleteConfirm.description` (Requests) |
| `pending-delete-confirm-title` | "Delete pending users?" | `deleteConfirm.title` (Pending Users) |
| `pending-delete-confirm-description` | "This removes the selected pending users." | `deleteConfirm.description` (Pending Users) |
| `invites-delete-confirm-title` | "Delete invites?" | `deleteConfirm.title` (Invites) |
| `invites-delete-confirm-description` | "This removes the selected sent invites." | `deleteConfirm.description` (Invites) |
| `column-name` | "Name" | Column header, shared by all three panes |
| `column-phone` | "Phone" | Column header, shared by Requests and Pending Users |
| `column-email` | "Email" | Column header, shared by all three panes |
| `column-user-number` | "User #" | Column header (Requests only) |
| `column-requested` | "Requested" | Column header (Requests and Pending Users) |
| `column-invited` | "Invited" | Column header (Pending Users only) |
| `column-request-count` | "Requests" | Column header (Pending Users only) |
| `column-last-request` | "Last request" | Column header (Pending Users only) |
| `column-last-invite` | "Last invite" | Column header (Pending Users only) |
| `column-sent-by` | "Sent by" | Column header (Invites only) |
| `column-sent` | "Sent" | Column header (Invites only) |
| `requests-source-label` | "Source:" | Detail label, Requests (`r.source`) |
| `requests-note-label` | "Note to the team:" | Detail label, Requests (`r.note`) |
| `pending-source-label` | "Source:" | Detail label, Pending Users (`u.lastSource`) |
| `pending-note-label` | "Note from user:" | Detail label, Pending Users (`u.lastNote`) |
| `empty-value-dash` | "—" | Fallback text for a null/empty `lastRequestDate`, `lastInviteSentDate`, or `note`/`lastNote` (see Edge Cases for the two panes' differing fallback rule) |

## Accessibility Options

- **Reduce Motion**: Not applicable — traced. `invitation-panes.tsx` defines no
  animation or transition of its own; it renders a static loading paragraph or
  a delegated `ListWithDetailsPane`.
- **Increase Contrast**: Not applicable — traced. The file sets no color
  itself beyond the single neutral `text-apt-text-dim`/`text-apt-text`/
  `text-apt-text-muted` tokens on plain text; any contrast-sensitive UI is
  delegated to the composed components.
- **Differentiate Without Color**: Not applicable — traced. The file conveys no
  state through color alone; it has no color-coded status indicator of its own.

## Privacy

- **Data collected**: None collected by this file. It receives already-fetched
  rows — which include personal contact data (`name`, `phone`, `email`) — as
  props and renders them; it performs no data collection of its own.
- **Storage**: None persisted. The file holds only transient UI-selection
  state (`notesForId`, `sendOpen`, `sendSeed`, `addOpen`) in `React.useState`,
  which is discarded on unmount and never written to disk, `localStorage`, or a
  database by this file.
- **Transmission**: None initiated by this file. It calls no network API
  directly; `onDelete`, `onSend`, and `onAdd` are caller-supplied functions, so
  any transmission of the personal data it displays happens in the caller's
  implementation, not here.
- **Retention**: Not applicable — traced. This file retains no data beyond the
  current render's props and its own transient UI state.

