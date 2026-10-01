---
id: a9222936-8474-4073-8581-d314a258bf0a
title: Invitation Panes
domain: agentictoolkit://cookbook/adh/hub/invitations/invitation-panes
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Three master-detail admin panes (Requests, Pending Users, Invites) with
  per-pane columns, admin notes, and Pending Users' Send/Add actions.
platforms:
- typescript
- web
tags:
- master-detail
- table
- invitations
- users
depends-on:
- agenticdevelopertoolkit://recipes/list-with-details-pane
- agentictoolkit://cookbook/adh/hub/invitations/send-invitation-modal
- agenticdevelopertoolkit://recipes/add-users-modal
related: []
references: []
approved-by: ''
approved-date: ''
---

# Invitation Panes

## Overview

This is the group of three sibling panes covering one stage each of the Invitations
workflow: incoming requests, pending users awaiting an invite, and sent invites (the
Requests pane, the Pending Users pane, and the Invites pane, respectively). Each is
built on a shared master-detail list-with-details layout
(agenticdevelopertoolkit://recipes/list-with-details-pane) configured with pane-specific
columns, an empty label, a storage key, and a shared "Admin notes" toolbar action. The
Pending Users pane additionally offers "Send invitation" and "Add users" actions that
open the send-invitation modal
(agentictoolkit://cookbook/adh/hub/invitations/send-invitation-modal) and the add-users
modal (agenticdevelopertoolkit://recipes/add-users-modal).

None of the three panes fetch data, persist anything, or own the notes/history UI:
rows, the delete/send/add callbacks, and the notes render-prop slots (a
notes-and-history renderer and a notes-modal renderer) are all supplied by the caller,
because — per the source's own doc comment — "the shared blocks never fetch." This
recipe documents only what these three panes themselves do; the visual chrome,
keyboard behavior, and accessibility contract of the list-with-details layout, the
send-invitation modal, and the add-users modal are each documented in their own recipe
and are not restated here.

Each pane calls its notes renderers with a fixed subject-table identifier, one of
three string constants: `"invitation_requests"` (Requests), `"pending_users"`
(Pending Users), and `"invitations"` (Invites).

## Behavioral Requirements

- **shows-loading-placeholder**: While the loading flag is true, each pane MUST
  render the text "Loading…" instead of the list-with-details layout.
- **delegates-list-rendering**: While the loading flag is not true, each pane MUST
  render the list-with-details layout configured with that pane's fixed columns,
  rows, row-id accessor, accessible name, empty label, and storage key (see
  Appearance for the exact per-pane values).
- **pending-null-dates-render-dash**: The Pending Users pane's "Last request" and
  "Last invite" columns MUST render "—" when the row's value for that field is
  `null`, and the raw value otherwise.
- **forwards-param-key**: Each pane MUST forward its deep-linking selection key
  unchanged to the list-with-details layout.
- **forwards-delete-callback**: Each pane MUST forward its delete callback to the
  list-with-details layout's delete handling unchanged.
- **shows-delete-confirm-copy**: Each pane MUST show a fixed delete-confirmation
  title/description in the list-with-details layout's delete confirmation:
  Requests — "Delete requests?" / "This removes the selected invitation requests.";
  Pending Users — "Delete pending users?" / "This removes the selected pending
  users."; Invites — "Delete invites?" / "This removes the selected sent invites."
- **notes-action-requires-selection**: The "Admin notes" toolbar action MUST
  require a non-empty selection.
- **notes-action-sets-first-selected-id**: Activating "Admin notes" MUST set the
  pane's admin-notes target id to the first id among the ids the action was
  activated with, or to none when there were no selected ids.
- **gates-notes-modal-on-existing-row**: The notes modal MUST be shown open only
  while a row whose id matches the admin-notes target id is still present among
  the pane's rows, and MUST be shown closed otherwise (including while no target
  id is set).
- **resets-notes-id-on-modal-close**: Closing the notes modal MUST clear the
  admin-notes target id.
- **passes-required-aria-label**: Each pane MUST give the list-with-details layout
  a fixed, non-empty accessible name: "Invitation requests" (Requests), "Pending
  users" (Pending Users), "Sent invites" (Invites).
- **requests-and-pending-show-source-and-note**: The Requests pane's detail panel
  MUST render "Source:" followed by the row's `source` field, then "Note to the
  team:" followed by the row's `note` field, above the notes/history content. The
  Pending Users pane's detail panel MUST render "Source:" followed by the row's
  `lastSource` field, then "Note from user:" followed by the row's `lastNote`
  field, above the notes/history content.
- **invites-detail-is-notes-only**: The Invites pane's detail panel MUST render
  exactly the notes/history content for that row's subject, with no additional
  fields.
- **send-action-requires-selection**: The Pending Users pane's "Send invitation"
  toolbar action MUST require a non-empty selection.
- **send-seed-filters-selected-rows**: Activating "Send invitation" MUST derive
  its seed from exactly the rows whose id is among the ids the action was
  activated with.
- **send-seed-collects-non-empty-emails**: The send seed's email list MUST be
  those selected rows' email values with empty-string values removed.
- **send-seed-collects-non-empty-phones**: The send seed's phone list MUST be
  those selected rows' phone values with empty-string values removed.
- **send-seed-carries-selected-ids**: The send seed's id list MUST be exactly the
  ids the action was activated with (not filtered against the pane's current
  rows).
- **send-action-opens-modal**: Activating "Send invitation" MUST open the
  send-invitation modal.
- **remounts-send-modal-on-reseed**: The send-invitation modal MUST be treated as
  a fresh instance whenever the send seed's joined email and phone lists change,
  resetting any in-progress edits.
- **closes-send-modal-only-on-resolve**: The Pending Users pane's send handling
  MUST call the caller's send callback with the send payload plus the seed's id
  list, and MUST close the send-invitation modal only when that call's returned
  promise resolves.
- **keeps-send-modal-open-on-reject**: When the caller's send callback's promise
  rejects, the handler MUST leave the send-invitation modal's open state
  unchanged (it stays open) and MUST NOT throw or propagate the rejection.
- **reports-send-rejection-reason**: When the caller's send callback's promise
  rejects, the handler SHOULD surface the rejection reason — in the modal or back
  to the caller — rather than discarding it silently. The current implementation
  discards it (see Edge Cases and Design Decisions); this requirement stays unmet
  until that is settled.
- **add-action-has-divider**: The Pending Users pane's "Add users" toolbar action
  MUST render with a divider before it.
- **add-action-opens-modal**: Activating "Add users" MUST open the add-users
  modal.
- **forwards-onadd**: The Pending Users pane MUST forward its add callback to the
  add-users modal's add handling unchanged.
- **forwards-send-busy**: The Pending Users pane MUST forward its send-busy
  indicator to the send-invitation modal's busy state unchanged.
- **forwards-add-busy**: The Pending Users pane MUST forward its add-busy
  indicator to the add-users modal's busy state unchanged.

## Appearance

This component renders no corner radius, padding, background, border, or shadow of
its own. It does apply a small, fixed set of neutral typography/foreground-color
roles directly — no raw hex values, no important-tagged overrides: the loading text
uses a small font size and the dimmed-text color role; the Requests and Pending Users
panes' detail panels wrap their Source/Note lines in a small-font-size block using the
default text color role, with the muted-text color role on the "Source:"/"Note …:"
label spans, and a small top margin above the note line. The Invites pane's detail
panel applies none of these — it renders the notes/history content directly, with no
wrapper. Everything else is delegated to the list-with-details layout, the
send-invitation modal, and the add-users modal, each of which owns and documents its
own corner radius, padding, typography, color, border, shadow, and sizing. What
differs between the three panes is entirely the *data* each supplies to the
list-with-details layout:

| Pane | Columns (`key` — header, width, align, notes) | Empty label | `storageKey` | Accessible name |
|---|---|---|---|---|
| Requests | `userNumber` — "User #" 6rem; `name` — "Name"; `phone` — "Phone"; `email` — "Email"; `requestedDate` — "Requested" 9rem | "No invitation requests." | `adm-inv-requests` | "Invitation requests" |
| Pending Users | `name` — "Name"; `phone` — "Phone"; `email` — "Email"; `invitedCount` — "Invited" 6rem, align end; `requestCount` — "Requests" 6rem, align end; `lastRequestDate` — "Last request" 9rem, renders `—` when null; `lastInviteSentDate` — "Last invite" 9rem, renders `—` when null; `requestedDate` — "Requested" 9rem | "No pending users." | `adm-inv-pending` | "Pending users" |
| Invites | `name` — "Name"; `email` — "Email"; `sentBy` — "Sent by"; `sentDate` — "Sent" 9rem | "No invites sent." | `adm-inv-invites` | "Sent invites" |

Every date column (`requestedDate`, `sentDate`, `lastRequestDate`,
`lastInviteSentDate`) is rendered exactly as received in the row's string field; this
component applies no formatting, truncation, or locale conversion of its own beyond
the dash fallback for a null value (see **pending-null-dates-render-dash**). The row
types declare these fields as already-formatted strings, so any date formatting
happens upstream of this component, not within it.

- **Corner radius / Padding / Background / Border / Shadow / Min-Max size**: Not
  applicable — traced. This component sets none of these itself; every such
  surface belongs to a composed component with its own recipe.
- **Font / Foreground**: traced. This component itself applies only the neutral
  typography/color roles listed above — small font size, dimmed-text,
  default-text, and muted-text color roles — no raw hex, no important-tagged
  overrides. Every other font/color surface belongs to a composed component with
  its own recipe.

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Loading | Renders "Loading…" instead of the list |
| Populated | Renders the list-with-details layout with the pane's rows and columns |
| 0 rows selected | "Admin notes" (and, on Pending Users, "Send invitation") stay disabled, per the list-with-details layout's own selection-required contract |
| Notes modal open | The notes modal is shown open only while the admin-notes target id still names a row present in the pane's rows |
| Send modal open (Pending Users only) | The send-invitation modal opens, seeded with emails/phones, and is treated as a fresh instance on a new seed |
| Add modal open (Pending Users only) | The add-users modal opens |
| Pressed | Not applicable — traced. This component renders no button, link, or input directly; every pressable control belongs to a composed component. |
| Focused | Not applicable — traced, for the same reason: no focusable element originates in this component. |
| Disabled | Not applicable — traced. None of the three panes accepts a whole-component disabled state; per-action disabling (the selection requirement) is configuration handed to the list-with-details layout, not a state this component enters itself. |

## Accessibility

- This component introduces one semantic element of its own — the loading text —
  and otherwise delegates all interactive/semantic markup to the list-with-details
  layout (a toolbar role plus its accessible name, per its own recipe), the
  send-invitation modal, and the add-users modal.
- **passes-required-aria-label** (Behavioral Requirements) is this component's one
  direct accessibility contribution: the accessible name is a required setting on
  the list-with-details layout, so each pane is forced to supply a real,
  human-readable name ("Invitation requests" / "Pending users" / "Sent invites")
  rather than omitting it.
- Toolbar action labels this component defines are all plain-text strings ("Admin
  notes", "Send invitation", "Add users"), not icon-only, so they read correctly
  through the list-with-details layout's labeling.
- The swap between the loading text and the populated list-with-details layout
  carries no live-region announcement in this component; a screen reader is
  notified of the change only insofar as its own virtual-cursor behavior picks up
  the content replacement.
- Minimum tap target: Not applicable to this component directly — traced. No
  tappable element originates here; the toolbar buttons, row selection, and modal
  controls are each the list-with-details layout's, the send-invitation modal's,
  or the add-users modal's own tap-target contract.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| invitation-panes-001 | shows-loading-placeholder | Render any of the three panes with the loading flag true | Output is the "Loading…" text; the list-with-details layout is not rendered |
| invitation-panes-002 | delegates-list-rendering | Render the Requests pane with the loading flag false/absent and a set of rows | The list-with-details layout receives the Requests columns, empty label "No invitation requests.", storage key "adm-inv-requests" |
| invitation-panes-003 | delegates-list-rendering | Render the Pending Users pane with rows | The list-with-details layout receives the Pending Users columns, empty label "No pending users.", storage key "adm-inv-pending" |
| invitation-panes-004 | delegates-list-rendering | Render the Invites pane with rows | The list-with-details layout receives the Invites columns, empty label "No invites sent.", storage key "adm-inv-invites" |
| invitation-panes-005 | forwards-param-key | Render any pane with a deep-linking selection key of "sel" | The list-with-details layout receives that same selection key |
| invitation-panes-006 | forwards-delete-callback | Confirm delete on any pane with rows selected | The pane's delete callback is invoked with the selected ids |
| invitation-panes-007 | notes-action-requires-selection | Render any pane with 0 rows selected | The "Admin notes" action requires a non-empty selection (delegated disabling per the list-with-details layout) |
| invitation-panes-008 | notes-action-sets-first-selected-id | Activate "Admin notes" with rows "a","b" selected | The admin-notes target id becomes "a" |
| invitation-panes-009 | notes-action-sets-first-selected-id | Activate "Admin notes" with no rows selected | The admin-notes target id becomes unset |
| invitation-panes-010 | gates-notes-modal-on-existing-row | Set the admin-notes target id to an id present in the pane's rows | The notes modal is shown open |
| invitation-panes-011 | gates-notes-modal-on-existing-row | Set the admin-notes target id to an id, then that row leaves the pane's rows | The notes modal is shown closed |
| invitation-panes-012 | resets-notes-id-on-modal-close | Close the notes modal | The admin-notes target id becomes unset |
| invitation-panes-013 | passes-required-aria-label | Render the Pending Users pane | The list-with-details layout receives the accessible name "Pending users" |
| invitation-panes-014 | requests-and-pending-show-source-and-note | Select a request row with source "web", note "urgent" | Detail shows "Source: web" and "Note to the team: urgent" above the notes/history content |
| invitation-panes-015 | invites-detail-is-notes-only | Select an invite row | Detail is exactly the notes/history content; no "Source:"/"Note:" lines appear |
| invitation-panes-016 | send-action-requires-selection | Render the Pending Users pane with 0 rows selected | "Send invitation" action requires a non-empty selection |
| invitation-panes-017 | send-seed-filters-selected-rows | Activate Send with ids "u1","u2" | The seed is built only from the rows whose id is u1 or u2 |
| invitation-panes-018 | send-seed-collects-non-empty-emails | Selected rows have emails "a@x.io", "" | Seed emails is ["a@x.io"] |
| invitation-panes-019 | send-seed-collects-non-empty-phones | Selected rows have phones "", "+15550100" | Seed phones is ["+15550100"] |
| invitation-panes-020 | send-seed-carries-selected-ids | Activate Send with ids "u1","u2" | Seed ids is exactly ["u1","u2"] |
| invitation-panes-021 | send-action-opens-modal | Activate "Send invitation" | The send-invitation modal opens |
| invitation-panes-022 | remounts-send-modal-on-reseed | Open Send for selection A (ids ["u1"], email a@x.io), close, open Send for selection B with different contacts (ids ["u2"], email b@x.io) | The send-invitation modal is treated as a fresh instance between the two opens |
| invitation-panes-023 | closes-send-modal-only-on-resolve | Caller's send callback's promise resolves | The send-invitation modal closes |
| invitation-panes-024 | keeps-send-modal-open-on-reject | Caller's send callback's promise rejects | The send-invitation modal remains open; no error is thrown out of the handler |
| invitation-panes-025 | add-action-has-divider | Inspect the "Add users" action | It renders with a divider before it |
| invitation-panes-026 | add-action-opens-modal | Activate "Add users" | The add-users modal opens |
| invitation-panes-027 | forwards-onadd | The add-users modal invokes its add handling with a list of users | The pane's add callback is called with that same list |
| invitation-panes-028 | forwards-send-busy | Render the Pending Users pane with its send-busy indicator true | The send-invitation modal receives a busy state of true |
| invitation-panes-029 | forwards-add-busy | Render the Pending Users pane with its add-busy indicator true | The add-users modal receives a busy state of true |
| invitation-panes-030 | shows-delete-confirm-copy | Inspect the Requests pane's delete-confirmation copy | title "Delete requests?", description "This removes the selected invitation requests." |
| invitation-panes-031 | shows-delete-confirm-copy | Inspect the Pending Users pane's delete-confirmation copy | title "Delete pending users?", description "This removes the selected pending users." |
| invitation-panes-032 | shows-delete-confirm-copy | Inspect the Invites pane's delete-confirmation copy | title "Delete invites?", description "This removes the selected sent invites." |
| invitation-panes-033 | requests-and-pending-show-source-and-note | Select a pending-user row with lastSource "referral", lastNote "thanks" | Detail shows "Source: referral" and "Note from user: thanks" above the notes/history content |
| invitation-panes-034 | pending-null-dates-render-dash | Render the Pending Users pane with a row whose "Last request" and "Last invite" values are both null | Both columns render "—" |

## Edge Cases

- **Null/empty input**: An empty row list on any pane is passed straight through to
  the list-with-details layout, which shows the pane's empty label; this component
  adds no special-casing of its own for an empty list. Activating "Send invitation"
  with no selected ids (only reachable by bypassing the selection requirement) seeds
  an empty email list, empty phone list, and empty id list and still opens the
  modal — the source places no additional guard on opening Send itself.
- **Boundary values**: Selecting more than one row and activating "Admin notes"
  still opens notes for only the first selected id; the remaining selected ids are
  silently ignored by that handler (Delete and Send instead act on the whole
  selected-id list).
- **Note-fallback quirk**: The Requests pane's note line uses an empty-or-falsy
  check, so an empty-string note renders "—". The Pending Users pane's note line
  uses a null-only check, so an empty-string note renders as blank, not "—" — the
  two panes are NOT symmetric here even though their detail layout looks the same.
- **Remount-key collision**: the send-invitation modal's fresh-instance identity is
  built from the seed's joined email and phone lists
  (**remounts-send-modal-on-reseed**). Two different selections that resolve to
  the same email/phone set — or two selections that both have no email and no
  phone at all — produce the same identity, so the modal does not reset between
  them and stale edits from the first selection can leak into the second; the
  source places no additional disambiguator (e.g. the seed's id list) in that
  identity.
- **Error states**: The one error path the source defines is the send callback
  rejecting: the rejection reason is discarded entirely — no error message, log,
  or re-throw — and only leaves the modal open (see
  **keeps-send-modal-open-on-reject**, **reports-send-rejection-reason**, and
  Design Decisions). The delete and add callbacks are synchronous callbacks with
  no return value in this component; it performs no error handling around them,
  so any failure handling for those two happens in the caller's own
  implementation, outside this component.
- **Concurrent access**: Not applicable — traced. The admin-notes target id, the
  send-modal and add-modal open flags, and the send seed are single-writer state
  values updated only from this component's own event handlers on the main
  thread; this component defines no shared or cross-session mutable state.
- **Offline/disconnected state**: Not applicable — traced. This component performs
  no network access itself (per its own doc comment, "the shared blocks never
  fetch"); rows and the delete/send/add callbacks are all caller-supplied, so
  connectivity handling belongs entirely to the caller.

## Configuration

### Requests Pane

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rows` | list of request records | — | Rows to render. |
| `loading` | boolean, optional | falsy | Shows the loading placeholder instead of the list. |
| `onDelete` | callback taking the array of selected ids | — | Forwarded to the list-with-details layout's delete handling. |
| `paramKey` | string, optional | none | Forwarded to the list-with-details layout for URL-based selection deep-linking. |
| `renderNotesAndHistory` | callback taking the subject table and id, returning renderable content | — | Fills the row detail panel below Source/Note. |
| `renderNotesModal` | callback taking the subject table, id, open flag, and a close handler, returning renderable content | — | Supplies the admin-notes modal. |

### Pending Users Pane

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rows` | list of pending-user records | — | Rows to render. |
| `loading` | boolean, optional | falsy | Shows the loading placeholder instead of the list. |
| `onDelete` | callback taking the array of selected ids | — | Forwarded to the list-with-details layout's delete handling. |
| `onSend` | callback taking the send payload, returning a promise | — | Called on Send; modal closes only on resolve. |
| `onAdd` | callback taking the list of drafted users | — | Forwarded to the add-users modal's add handling. |
| `sendBusy` | boolean, optional | none | Forwarded to the send-invitation modal's busy state. |
| `addBusy` | boolean, optional | none | Forwarded to the add-users modal's busy state. |
| `paramKey` | string, optional | none | Forwarded to the list-with-details layout for URL-based selection deep-linking. |
| `renderNotesAndHistory` | callback taking the subject table and id, returning renderable content | — | Fills the row detail panel below Source/Note. |
| `renderNotesModal` | callback taking the subject table, id, open flag, and a close handler, returning renderable content | — | Supplies the admin-notes modal. |

The send-invitation modal and the add-users modal are mounted with no title
override, so each keeps its own default ("Send invitation" / "Add users").

### Invites Pane

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rows` | list of invite records | — | Rows to render. |
| `loading` | boolean, optional | falsy | Shows the loading placeholder instead of the list. |
| `onDelete` | callback taking the array of selected ids | — | Forwarded to the list-with-details layout's delete handling. |
| `paramKey` | string, optional | none | Forwarded to the list-with-details layout for URL-based selection deep-linking. |
| `renderNotesAndHistory` | callback taking the subject table and id, returning renderable content | — | Supplies the entire detail panel. |
| `renderNotesModal` | callback taking the subject table, id, open flag, and a close handler, returning renderable content | — | Supplies the admin-notes modal. |

Shared shapes: the notes render-prop slots (`renderNotesAndHistory`,
`renderNotesModal`, used by all three panes) and the send payload (the shared
send-invitation payload shape extended with the selected pending-user ids), the shape
the Pending Users pane hands to its send callback.

## Deep Linking

Not applicable — traced. This component defines no route or URL scheme of its own.
Each pane accepts an optional deep-linking selection key, forwarded unchanged to the
list-with-details layout, that lets the host page bind row selection to a URL search
parameter (per the source's own comment: "Optional URL search-param key for
deep-linking the selected row"); the deep-link target itself, if any, belongs to
whatever page mounts the pane, not to this component.

## Localization

The source hardcodes every user-facing string directly; there is no i18n key or
translation lookup anywhere in this component's source.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `loading-message` | "Loading…" | Loading placeholder (all panes) |
| `admin-notes-action` | "Admin notes" | Toolbar action label (all panes) |
| `send-invitation-action` | "Send invitation" | Toolbar action label (Pending Users only) |
| `add-users-action` | "Add users" | Toolbar action label (Pending Users only) |
| `requests-empty-label` | "No invitation requests." | Empty label (Requests) |
| `pending-empty-label` | "No pending users." | Empty label (Pending Users) |
| `invites-empty-label` | "No invites sent." | Empty label (Invites) |
| `requests-delete-confirm-title` | "Delete requests?" | Delete-confirmation title (Requests) |
| `requests-delete-confirm-description` | "This removes the selected invitation requests." | Delete-confirmation description (Requests) |
| `pending-delete-confirm-title` | "Delete pending users?" | Delete-confirmation title (Pending Users) |
| `pending-delete-confirm-description` | "This removes the selected pending users." | Delete-confirmation description (Pending Users) |
| `invites-delete-confirm-title` | "Delete invites?" | Delete-confirmation title (Invites) |
| `invites-delete-confirm-description` | "This removes the selected sent invites." | Delete-confirmation description (Invites) |
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
| `requests-source-label` | "Source:" | Detail label, Requests (`source`) |
| `requests-note-label` | "Note to the team:" | Detail label, Requests (`note`) |
| `pending-source-label` | "Source:" | Detail label, Pending Users (`lastSource`) |
| `pending-note-label` | "Note from user:" | Detail label, Pending Users (`lastNote`) |
| `empty-value-dash` | "—" | Fallback text for a null/empty `lastRequestDate`, `lastInviteSentDate`, or `note`/`lastNote` (see Edge Cases for the two panes' differing fallback rule) |

## Accessibility Options

- **Reduce Motion**: Not applicable — traced. This component defines no animation
  or transition of its own; it renders a static loading text or a delegated
  list-with-details layout.
- **Increase Contrast**: Not applicable — traced. This component sets no color
  itself beyond the single neutral dimmed-text/default-text/muted-text color
  roles on plain text; any contrast-sensitive UI is delegated to the composed
  components.
- **Differentiate Without Color**: Not applicable — traced. This component
  conveys no state through color alone; it has no color-coded status indicator
  of its own.

## Feature Flags

Not applicable — traced. This component contains no feature-flag check; every pane
renders unconditionally from its inputs (the loading flag, rows, etc.) and gates
nothing behind a flag.

## Analytics

Not applicable — traced. No analytics or telemetry call (e.g. no tracking or
event-emission call) appears anywhere in this component. Any view/interaction
telemetry is the caller's responsibility, inside its own
delete/send/add/notes-renderer implementations.

## Privacy

- **Data collected**: None collected by this component. It receives already-fetched
  rows — which include personal contact data (name, phone, email) — as inputs and
  renders them; it performs no data collection of its own.
- **Storage**: None persisted. This component holds only transient UI-selection
  state (the admin-notes target id, the send-modal and add-modal open flags, the
  send seed), which is discarded on unmount and never written to disk, browser
  storage, or a database by this component.
- **Transmission**: None initiated by this component. It calls no network API
  directly; the delete, send, and add callbacks are caller-supplied functions, so
  any transmission of the personal data it displays happens in the caller's
  implementation, not here.
- **Retention**: Not applicable — traced. This component retains no data beyond
  the current render's inputs and its own transient UI state.

## Logging

Not applicable — traced. This component contains no logging call of any kind. In
particular, the rejected send-callback promise path is explicitly discarded, not
logged (see Design Decisions).

## Platform Notes

- **SwiftUI**: Model each pane as a view built on `NavigationSplitView` (or a
  `List` plus a `.sheet`-presented detail) — the list/detail chrome itself maps
  to `ListWithDetailsPane`'s own SwiftUI notes, not to this file. The three
  panes here become three thin views (or one generic view parameterized over
  row type, mirroring the source's TypeScript generics) that each supply their
  own columns, empty text, and detail closure; the `NotesSlots` render props
  become `@ViewBuilder` closures passed in by the caller. The Pending-only
  Send/Add flows become `.sheet(item:)` presentations keyed by an
  `Identifiable` seed struct, to reproduce the source's remount-on-reseed
  behavior, and close only in the success branch of the `async` send call.
- **Compose**: Analogous to SwiftUI — an adaptive list-detail scaffold (Material
  3's `ListDetailPaneScaffold`) per row type, with the notes slots as
  `@Composable` lambdas supplied by the caller. The Send/Add flows become
  `AlertDialog`/`ModalBottomSheet` state hoisted in the parent composable, keyed
  by the selection (e.g. `key(selectionKey) { ... }`) so a new selection resets
  the dialog's internal state — the same remount-on-reseed effect the source
  gets from React's `key`.
- **React/Web (TypeScript)**: This is the source platform.
  `packages/web/packages/adh-ui/src/blocks/invitation-panes.tsx` in
  `@agentic-toolkit/adh-ui`, exported through the package's `./blocks` barrel
  (`src/blocks/index.ts`) alongside `SendInvitationModal`. It is a `"use
  client"` Next.js client component that composes `ListWithDetailsPane` and
  `AddUsersModal` from `@agenticdevelopertoolkit/ui/blocks/*`, the
  package-local `SendInvitationModal`, and the row types and table-name
  constants from `../lib/invitations-types.ts`.
- **AppKit/UIKit**: Build each pane on `NSTableView`/`UITableView` inside an
  `NSSplitViewController`/`UISplitViewController` for the master-detail layout,
  with an `NSToolbar`/`UIToolbar` (or nav-bar button items) reproducing the
  "Admin notes" / "Send invitation" / "Add users" actions, each enabled only
  with a non-empty selection. The notes/send/add modals become panels or
  modally presented view controllers. Considerably more manual wiring than the
  SwiftUI/Compose path, since there is no built-in adaptive list-detail
  scaffold to lean on.
- **WinUI 3**: Model each pane as a page or `UserControl` hosting a `ListView`
  (or the Community Toolkit's `DataGrid`) bound to an
  `ObservableCollection<Row>`, with the master/detail split via `TwoPaneView`
  (mirroring the peer layout of `ResizableSplit`,
  agenticdevelopertoolkit://recipes/resizable-split) or the `ListDetailsView`
  control's built-in adaptive behavior. Reproduce the toolbar with a
  `CommandBar`'s
  `AppBarButton`s for "Admin notes" / "Send invitation" / "Add users", each
  `IsEnabled` bound to `SelectedItems.Count > 0` (visual state via
  `VisualStateManager`, e.g. `SelectionEmpty`/`SelectionNonEmpty` states) to
  match `requiresSelection`. The Send/Add flows become `ContentDialog`s shown
  via `ShowAsync()`; because a `ContentDialog` is not naturally re-created the
  way a keyed React element is, reproduce `remounts-send-modal-on-reseed` by
  explicitly re-initializing the dialog's view-model fields from the current
  selection every time it is shown, and reproduce
  `closes-send-modal-only-on-resolve`/`keeps-send-modal-open-on-reject` by
  closing the dialog only in the `await SendAsync()` call's success branch and
  leaving it open (with its primary button re-enabled) in the `catch`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/adh-ui/src/blocks/invitation-panes.tsx` |

## Design Decisions

Decision: `SendInvitationModal` closes only when the caller's `onSend` promise
resolves; on rejection it stays open and the rejection reason is discarded.
Rationale: per the source's own comment, this keeps the failure visible to the
admin (the modal does not vanish) and keeps the send retryable, at the cost of
not surfacing the actual error to the admin or to any log.
Approved: pending

Decision: `SendInvitationModal` is remounted via a `key` built from the joined
seed emails and phones, rather than reseeded through props alone.
Rationale: forces the modal's internal recipient/note state to reset whenever a
new selection opens Send, instead of leaking a stale selection's edits into the
next one.
Approved: pending

Decision: the "Admin notes" modal's `open` is derived from
`rows.find(row => row.id === notesForId) != null` rather than from
`notesForId != null` directly.
Rationale: prevents the modal from opening for a `notesForId` that no longer
names a row present in `rows` — e.g. the row was deleted or filtered out
between selecting notes and the modal's render.
Approved: pending

Decision: `InvitationInvitesPane`'s detail panel renders only
`renderNotesAndHistory`, while `InvitationRequestsPane`'s and
`InvitationPendingUsersPane`'s detail panels prepend their own Source/Note
fields.
Rationale: traced directly to the source — a sent invite's row already exposes
name/email/sentBy/sentDate as table columns, leaving nothing pane-specific for
the detail panel beyond notes/history, unlike a request or pending user, which
carry a `source`/note field that is not itself a table column.
Approved: pending

Decision: `InvitationRequestsPane`'s note fallback uses `r.note || "—"` while
`InvitationPendingUsersPane`'s uses `u.lastNote ?? "—"`.
Rationale: not stated in the source; this reads as an inconsistency between two
otherwise parallel detail panels rather than a deliberate design choice (see
Edge Cases, "Note-fallback quirk"). Documented here as a known discrepancy
rather than idealized away.
Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy & Data |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy & Data |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |

Statuses rest on this file's own sections: Accessibility documents that
`passes-required-aria-label` is this file's one direct, forced contribution
while every other interactive/semantic element is delegated (partial); Privacy
and Logging show the file collects, stores, transmits, and logs nothing of its
own (passed); Localization shows every user-facing string is hardcoded with no
i18n key or lookup (failed); Overview shows data-fetching, persistence, and the
notes/history UI are all pushed to the caller, leaving this file pure
presentation (passed); and Edge Cases/Design Decisions show the `onSend`
rejection reason is discarded via `() => undefined` with no log or rethrow
(failed, see `reports-send-rejection-reason`).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from `invitation-panes.tsx` (InvitationRequestsPane, InvitationPendingUsersPane, InvitationInvitesPane). |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: named the exact per-pane Source/Note labels and fields, added delete-confirm-copy and null-date-dash requirements plus a SHOULD requirement for reporting the send-rejection reason, added a remount-key-collision edge case and tightened vector 022, added missing test vectors, reconciled Appearance's class list with Accessibility Options, filled in Localization string keys and the shared Name/Phone/Email row, linked the WinUI 3 ResizableSplit mention, stated date columns render as received, and replaced the Compliance table with real catalog checks. |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/invitations/. |
