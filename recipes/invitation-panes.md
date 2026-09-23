---
id: a9222936-8474-4073-8581-d314a258bf0a
title: InvitationPanes
domain: agentictoolkit://recipes/invitation-panes
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Three ListWithDetailsPane-based admin panes (Requests, Pending Users, Invites)
  with per-pane columns, admin notes, and Pending Users' Send/Add actions.
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
- agentictoolkit://recipes/send-invitation-modal
- agenticdevelopertoolkit://recipes/add-users-modal
related: []
references: []
approved-by: ''
approved-date: ''
---

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

## Behavioral Requirements

- **shows-loading-placeholder**: While `loading` is true, each pane MUST render
  the paragraph "Loading…" instead of `ListWithDetailsPane`.
- **delegates-list-rendering**: While `loading` is not true, each pane MUST
  render `ListWithDetailsPane` configured with that pane's fixed columns,
  `rows`, `getRowId`, `ariaLabel`, `emptyLabel`, and `storageKey` (see
  Appearance for the exact per-pane values).
- **forwards-param-key**: Each pane MUST forward its `paramKey` prop to
  `ListWithDetailsPane` unchanged.
- **forwards-delete-callback**: Each pane MUST forward its `onDelete` prop to
  `ListWithDetailsPane`'s `onDelete` unchanged.
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
- **requests-and-pending-show-source-and-note**: `InvitationRequestsPane`'s and
  `InvitationPendingUsersPane`'s detail panel MUST render a "Source:" line and a
  "Note…:" line above the `renderNotesAndHistory` output.
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

`invitation-panes.tsx` renders no styling of its own beyond the single loading
paragraph (`text-sm text-apt-text-dim`, a neutral Tailwind design token — no
raw hex, no `!important`). Everything else is delegated to `ListWithDetailsPane`,
`SendInvitationModal`, and `AddUsersModal`, each of which owns and documents its
own corner radius, padding, typography, color, border, shadow, and sizing. What
differs between the three panes is entirely the *data* each supplies to
`ListWithDetailsPane`:

| Pane | Columns (`key` — header, width, align, notes) | Empty label | `storageKey` | `ariaLabel` |
|---|---|---|---|---|
| InvitationRequestsPane | `userNumber` — "User #" 6rem; `name` — "Name"; `phone` — "Phone"; `email` — "Email"; `requestedDate` — "Requested" 9rem | "No invitation requests." | `adm-inv-requests` | "Invitation requests" |
| InvitationPendingUsersPane | `name` — "Name"; `phone` — "Phone"; `email` — "Email"; `invitedCount` — "Invited" 6rem, align end; `requestCount` — "Requests" 6rem, align end; `lastRequestDate` — "Last request" 9rem, renders `—` when null; `lastInviteSentDate` — "Last invite" 9rem, renders `—` when null; `requestedDate` — "Requested" 9rem | "No pending users." | `adm-inv-pending` | "Pending users" |
| InvitationInvitesPane | `name` — "Name"; `email` — "Email"; `sentBy` — "Sent by"; `sentDate` — "Sent" 9rem | "No invites sent." | `adm-inv-invites` | "Sent invites" |

- **Corner radius / Padding / Font / Background / Foreground / Border / Shadow /
  Min-Max size**: Not applicable — traced. `invitation-panes.tsx` sets none of
  these itself; the loading paragraph carries only a font-size/color utility
  class, and every other visible surface belongs to a composed component with
  its own recipe.

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
| invitation-panes-022 | remounts-send-modal-on-reseed | Open Send for selection A, close, open Send for a different selection B | `SendInvitationModal`'s `key` differs between the two opens |
| invitation-panes-023 | closes-send-modal-only-on-resolve | Caller's `onSend` promise resolves | `sendOpen` becomes `false` |
| invitation-panes-024 | keeps-send-modal-open-on-reject | Caller's `onSend` promise rejects | `sendOpen` remains `true`; no error is thrown out of the handler |
| invitation-panes-025 | add-action-has-divider | Inspect the "Add users" action | `dividerBefore` is `true` |
| invitation-panes-026 | add-action-opens-modal | Activate "Add users" | `addOpen` becomes `true` |
| invitation-panes-027 | forwards-onadd | `AddUsersModal` invokes `onAdd(users)` | The pane's `onAdd` prop is called with `users` |
| invitation-panes-028 | forwards-send-busy | Render `InvitationPendingUsersPane` with `sendBusy=true` | `SendInvitationModal` receives `busy=true` |
| invitation-panes-029 | forwards-add-busy | Render `InvitationPendingUsersPane` with `addBusy=true` | `AddUsersModal` receives `busy=true` |

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
- **Concurrent access**: Not applicable — traced. `notesForId`, `sendOpen`,
  `sendSeed`, and `addOpen` are single-writer `React.useState` values updated
  only from this component's own event handlers on the main thread; the file
  defines no shared or cross-session mutable state.
- **Error states**: The one error path the source defines is `onSend`
  rejecting: `.then(() => setSendOpen(false), () => undefined)` discards the
  rejection reason entirely — no error message, log, or re-throw — and only
  leaves the modal open (see `keeps-send-modal-open-on-reject` and Design
  Decisions). `onDelete` and `onAdd` are synchronous `void` callbacks in this
  file; it performs no error handling around them, so any failure handling for
  those two happens in the caller's own implementation, outside this file.
- **Offline/disconnected state**: Not applicable — traced. The file performs no
  network access itself (per its own doc comment, "the shared blocks never
  fetch"); `rows`, `onDelete`, `onSend`, and `onAdd` are all caller-supplied, so
  connectivity handling belongs entirely to the caller.

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

## Deep Linking

Not applicable — traced. `invitation-panes.tsx` defines no route or URL scheme
of its own. Each pane accepts an optional `paramKey` prop, forwarded unchanged
to `ListWithDetailsPane`, that lets the host page bind row selection to a URL
search parameter (per the source's own comment: "Optional URL search-param key
for deep-linking the selected row"); the deep-link target itself, if any,
belongs to whatever page mounts the pane, not to this file.

## Localization

The source hardcodes every user-facing string directly; there is no i18n key
or translation lookup anywhere in `invitation-panes.tsx`.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — | "Loading…" | Loading placeholder (all panes) |
| — | "Admin notes" | Toolbar action label (all panes) |
| — | "Send invitation" | Toolbar action label (Pending Users only) |
| — | "Add users" | Toolbar action label (Pending Users only) |
| — | "No invitation requests." | `emptyLabel` (Requests) |
| — | "No pending users." | `emptyLabel` (Pending Users) |
| — | "No invites sent." | `emptyLabel` (Invites) |
| — | "Delete requests?" / "This removes the selected invitation requests." | `deleteConfirm` title/description (Requests) |
| — | "Delete pending users?" / "This removes the selected pending users." | `deleteConfirm` title/description (Pending Users) |
| — | "Delete invites?" / "This removes the selected sent invites." | `deleteConfirm` title/description (Invites) |
| — | "User #", "Requested" | Requests-only column headers (Name/Phone/Email are shared) |
| — | "Invited", "Requests", "Last request", "Last invite" | Pending-Users-only column headers |
| — | "Sent by", "Sent" | Invites-only column headers |
| — | "Source:", "Note to the team:" | Requests detail labels |
| — | "Source:", "Note from user:" | Pending Users detail labels |
| — | "—" | Fallback text for a null/empty `lastRequestDate`, `lastInviteSentDate`, or `note`/`lastNote` (see Edge Cases for the two panes' differing fallback rule) |

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

## Feature Flags

Not applicable — traced. `invitation-panes.tsx` contains no feature-flag
check; every pane renders unconditionally from its props (`loading`, `rows`,
etc.) and gates nothing behind a flag.

## Analytics

Not applicable — traced. No analytics or telemetry call (e.g. no `track(...)`
or `analytics.*` call) appears anywhere in `invitation-panes.tsx`. Any
view/interaction telemetry is the caller's responsibility, inside its own
`onDelete`/`onSend`/`onAdd`/`renderNotesAndHistory` implementations.

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

## Logging

Not applicable — traced. `invitation-panes.tsx` contains no logging call of
any kind. In particular, the rejected `onSend` promise path is explicitly
discarded with `() => undefined`, not logged (see Design Decisions).

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
  (mirroring `ResizableSplit`'s peer layout) or the `ListDetailsView` control's
  built-in adaptive behavior. Reproduce the toolbar with a `CommandBar`'s
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
| [artifact-formatting](agenticdevelopercookbook://compliance/recipe-quality#artifact-formatting) | passed | recipe-quality |
| [no-raw-hex-no-important](agenticdevelopercookbook://compliance/ui-guidelines#no-raw-hex-no-important) | passed | ui-guidelines |
| [composes-shared-primitives-only](agenticdevelopercookbook://compliance/ui-guidelines#composes-shared-primitives-only) | passed | ui-guidelines |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from `invitation-panes.tsx` (InvitationRequestsPane, InvitationPendingUsersPane, InvitationInvitesPane). |
