<!-- leaf: implement-general-1/invitation-panes · source: invitation-panes.md -->

**Rules** (cite as `implement-general-1/invitation-panes#<slug>`):

- `shows-loading-placeholder` MUST
- `delegates-list-rendering` MUST
- `pending-null-dates-render-dash` MUST
- `forwards-param-key` MUST
- `forwards-delete-callback` MUST
- `shows-delete-confirm-copy` MUST
- `notes-action-requires-selection` MUST
- `notes-action-sets-first-selected-id` MUST
- `gates-notes-modal-on-existing-row` MUST
- `resets-notes-id-on-modal-close` MUST
- `passes-required-aria-label` MUST
- `requests-and-pending-show-source-and-note` MUST
- `invites-detail-is-notes-only` MUST
- `send-action-requires-selection` MUST
- `send-seed-filters-selected-rows` MUST
- `send-seed-collects-non-empty-emails` MUST
- `send-seed-collects-non-empty-phones` MUST
- `send-seed-carries-selected-ids` MUST
- `send-action-opens-modal` MUST
- `remounts-send-modal-on-reseed` MUST
- `closes-send-modal-only-on-resolve` MUST
- `keeps-send-modal-open-on-reject` MUST
- `reports-send-rejection-reason` SHOULD
- `add-action-has-divider` MUST
- `add-action-opens-modal` MUST
- `forwards-onadd` MUST
- `forwards-send-busy` MUST
- `forwards-add-busy` MUST

# InvitationPanes

## Overview

`InvitationPanes` is the group of three sibling exports from
`packages/web/packages/adh-ui/src/blocks/invitation-panes.tsx` in
`@agentic-toolkit/adh-ui`: `InvitationRequestsPane`, `InvitationPendingUsersPane`,
and `InvitationInvitesPane`. Each renders one stage of the Invitations workflow
(incoming requests, pending users awaiting an invite, and sent invites) as a
`ListWithDetailsPane` (agenticdevelopertoolkit://recipes/list-with-details-pane)
configured with pane-specific columns, an empty label, a `storageKey`, and a
shared "Admin notes" toolbar action. `InvitationPendingUsersPane` additionally
offers "Send invitation" and "Add users" actions that open
`SendInvitationModal` (agentictoolkit://recipes/send-invitation-modal) and
`AddUsersModal` (agenticdevelopertoolkit://recipes/add-users-modal).

None of the three panes fetch data, persist anything, or own the notes/history
UI: rows, the delete/send/add callbacks, and the `NotesSlots` render props
(`renderNotesAndHistory`, `renderNotesModal`) are all supplied by the caller,
because — per the source's own doc comment — "the shared blocks never fetch."
This recipe documents only what `invitation-panes.tsx` itself does; the visual
chrome, keyboard behavior, and accessibility contract of `ListWithDetailsPane`,
`SendInvitationModal`, and `AddUsersModal` are each documented in their own
recipe and are not restated here.

Each pane calls `renderNotesAndHistory`/`renderNotesModal` with a fixed
`subjectTable`, one of the string constants imported from
`../lib/invitations-types.ts`: `"invitation_requests"`
(`TABLE_INVITATION_REQUESTS`, Requests), `"pending_users"`
(`TABLE_PENDING_USERS`, Pending Users), and `"invitations"`
(`TABLE_INVITATIONS`, Invites).

## Behavioral Requirements

- **shows-loading-placeholder**: While `loading` is true, each pane MUST render
  the paragraph "Loading…" instead of `ListWithDetailsPane`.
- **delegates-list-rendering**: While `loading` is not true, each pane MUST
  render `ListWithDetailsPane` configured with that pane's fixed columns,
  `rows`, `getRowId`, `ariaLabel`, `emptyLabel`, and `storageKey` (see
  Appearance for the exact per-pane values).
- **pending-null-dates-render-dash**: `InvitationPendingUsersPane`'s
  `lastRequestDate` and `lastInviteSentDate` columns MUST render "—" when the
  row's value for that field is `null`, and the raw value otherwise.
- **forwards-param-key**: Each pane MUST forward its `paramKey` prop to
  `ListWithDetailsPane` unchanged.
- **forwards-delete-callback**: Each pane MUST forward its `onDelete` prop to
  `ListWithDetailsPane`'s `onDelete` unchanged.
- **shows-delete-confirm-copy**: Each pane MUST forward a fixed
  `deleteConfirm` title/description to `ListWithDetailsPane`: Requests —
  "Delete requests?" / "This removes the selected invitation requests.";
  Pending Users — "Delete pending users?" / "This removes the selected pending
  users."; Invites — "Delete invites?" / "This removes the selected sent
  invites."
- **notes-action-requires-selection**: The "Admin notes" toolbar action MUST be
  configured with `requiresSelection: true`.
- **notes-action-sets-first-selected-id**: Activating "Admin notes" MUST set the
  pane's `notesForId` state to the first id in the action's `ids` argument, or
  `null` when `ids` is empty.
- **gates-notes-modal-on-existing-row**: `renderNotesModal`'s `open` argument
  MUST be `true` only while `rows.find(row => row.id === notesForId)` returns a
  row, and MUST be `false` otherwise (including while `notesForId` is `null`).
- **resets-notes-id-on-modal-close**: The notes modal's `onClose` MUST set
  `notesForId` to `null`.
- **passes-required-aria-label**: Each pane MUST pass a fixed, non-empty
  `ariaLabel` to `ListWithDetailsPane`: "Invitation requests" (Requests),
  "Pending users" (Pending Users), "Sent invites" (Invites).
- **requests-and-pending-show-source-and-note**: `InvitationRequestsPane`'s
  detail panel MUST render "Source:" followed by the row's `source` field, then
  "Note to the team:" followed by the row's `note` field, above the
  `renderNotesAndHistory` output. `InvitationPendingUsersPane`'s detail panel
  MUST render "Source:" followed by the row's `lastSource` field, then "Note
  from user:" followed by the row's `lastNote` field, above the
  `renderNotesAndHistory` output.
- **invites-detail-is-notes-only**: `InvitationInvitesPane`'s detail panel MUST
  render exactly the return value of `renderNotesAndHistory({ subjectTable:
  "invitations", subjectId })`, with no additional fields.
- **send-action-requires-selection**: `InvitationPendingUsersPane`'s "Send
  invitation" toolbar action MUST be configured with `requiresSelection: true`.
- **send-seed-filters-selected-rows**: Activating "Send invitation" MUST derive
  its seed from exactly the rows whose id is in the action's `ids` argument.
- **send-seed-collects-non-empty-emails**: The send seed's `emails` MUST be
  those selected rows' `email` values with falsy (empty-string) values removed.
- **send-seed-collects-non-empty-phones**: The send seed's `phones` MUST be
  those selected rows' `phone` values with falsy (empty-string) values removed.
- **send-seed-carries-selected-ids**: The send seed's `ids` MUST be exactly the
  `ids` argument passed to the action (not filtered against `rows`).
- **send-action-opens-modal**: Activating "Send invitation" MUST set `sendOpen`
  to `true`.
- **remounts-send-modal-on-reseed**: `SendInvitationModal` MUST be given a
  `key` built from the send seed's joined `emails` and `phones`, so a new seed
  remounts it.
- **closes-send-modal-only-on-resolve**: `InvitationPendingUsersPane`'s
  `onSend` handler MUST call the caller's `onSend` with the send payload plus
  `pendingUserIds: sendSeed.ids`, and MUST set `sendOpen` to `false` when that
  call's returned promise resolves.
- **keeps-send-modal-open-on-reject**: When the caller's `onSend` promise
  rejects, the handler MUST leave `sendOpen` unchanged (the modal stays open)
  and MUST NOT throw or propagate the rejection.
- **reports-send-rejection-reason**: When the caller's `onSend` promise
  rejects, the handler SHOULD surface the rejection reason — in the modal or
  back to the caller — rather than discarding it silently. The current
  implementation discards it via `() => undefined` (see Edge Cases and Design
  Decisions); this requirement stays unmet until that is settled.
- **add-action-has-divider**: `InvitationPendingUsersPane`'s "Add users"
  toolbar action MUST be configured with `dividerBefore: true`.
- **add-action-opens-modal**: Activating "Add users" MUST set `addOpen` to
  `true`.
- **forwards-onadd**: `InvitationPendingUsersPane` MUST forward its `onAdd`
  prop to `AddUsersModal`'s `onAdd` unchanged.
- **forwards-send-busy**: `InvitationPendingUsersPane` MUST forward its
  `sendBusy` prop to `SendInvitationModal`'s `busy` prop unchanged.
- **forwards-add-busy**: `InvitationPendingUsersPane` MUST forward its
  `addBusy` prop to `AddUsersModal`'s `busy` prop unchanged.

## Appearance

`invitation-panes.tsx` renders no corner radius, padding, background, border,
or shadow of its own. It does apply a small, fixed set of neutral Tailwind
typography/foreground-color utility classes directly — no raw hex, no
`!important`: the loading paragraph (`text-sm text-apt-text-dim`) and, in
`InvitationRequestsPane`'s and `InvitationPendingUsersPane`'s detail panels, a
wrapper `text-sm text-apt-text`, `text-apt-text-muted` on the "Source:"/"Note
…:" label spans, and `mt-1` top margin on the note line.
`InvitationInvitesPane`'s detail panel applies none of these — it renders
`renderNotesAndHistory`'s return value directly, with no wrapper. Everything
else is delegated to `ListWithDetailsPane`, `SendInvitationModal`, and
`AddUsersModal`, each of which owns and documents its own corner radius,
padding, typography, color, border, shadow, and sizing. What differs between
the three panes is entirely the *data* each supplies to `ListWithDetailsPane`:

| Pane | Columns (`key` — header, width, align, notes) | Empty label | `storageKey` | `ariaLabel` |
|---|---|---|---|---|
| InvitationRequestsPane | `userNumber` — "User #" 6rem; `name` — "Name"; `phone` — "Phone"; `email` — "Email"; `requestedDate` — "Requested" 9rem | "No invitation requests." | `adm-inv-requests` | "Invitation requests" |
| InvitationPendingUsersPane | `name` — "Name"; `phone` — "Phone"; `email` — "Email"; `invitedCount` — "Invited" 6rem, align end; `requestCount` — "Requests" 6rem, align end; `lastRequestDate` — "Last request" 9rem, renders `—` when null; `lastInviteSentDate` — "Last invite" 9rem, renders `—` when null; `requestedDate` — "Requested" 9rem | "No pending users." | `adm-inv-pending` | "Pending users" |
| InvitationInvitesPane | `name` — "Name"; `email` — "Email"; `sentBy` — "Sent by"; `sentDate` — "Sent" 9rem | "No invites sent." | `adm-inv-invites` | "Sent invites" |

Every date column (`requestedDate`, `sentDate`, `lastRequestDate`,
`lastInviteSentDate`) is rendered exactly as received in the row's string
field; `invitation-panes.tsx` applies no formatting, truncation, or locale
conversion of its own beyond the `— ` fallback for a `null` value (see
**pending-null-dates-render-dash**). The row types declare these fields as
already-formatted strings, so any date formatting happens upstream of this
file, not within it.

- **Corner radius / Padding / Background / Border / Shadow / Min-Max size**:
  Not applicable — traced. `invitation-panes.tsx` sets none of these itself;
  every such surface belongs to a composed component with its own recipe.
- **Font / Foreground**: traced. `invitation-panes.tsx` itself applies only
  the neutral Tailwind utility classes listed above — `text-sm`,
  `text-apt-text-dim`, `text-apt-text`, `text-apt-text-muted` — no raw hex, no
  `!important`. Every other font/color surface belongs to a composed component
  with its own recipe.

