<!-- leaf: implement-general-1/invitation-panes--part-3 · source: invitation-panes.md -->

# InvitationPanes — continued (part 3)

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
