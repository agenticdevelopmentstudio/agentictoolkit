<!-- leaf: implement-general-1/admin-notes-modal--part-2 · source: admin-notes-modal.md -->

# AdminNotesModal — continued (part 2)

## Privacy

- **Data collected**: Note text entered by the admin, staged only in React
  component state (the working list) while the dialog is open.
- **Storage**: The component itself persists nothing; it holds the working
  list in memory only. Durable storage is entirely the responsibility of the
  caller's `onSave` handler and backend, not observable in this file.
- **Transmission**: None performed by this component; `onSave` hands the
  `{id, content}` pairs to the caller, which decides whether/how to transmit
  them.
- **Retention**: The working list is discarded (reset to `notes`) whenever
  the dialog closes, whether via Cancel, Escape, close, or a caller-driven
  `open=false` after a successful save.

## Platform Notes

- **React/Web**: The block lives at
  `packages/web/packages/adh-ui/src/blocks/admin-notes-modal.tsx` and composes
  `Dialog`/`DialogContent`/`DialogHeader`/`DialogTitle`/`DialogFooter` and
  `Textarea` from `@agenticdevelopertoolkit/ui/components/dialog` and
  `@agenticdevelopertoolkit/ui/components/textarea`, `Button` from
  `@agenticdevelopertoolkit/ui/components/button`, `ListWithDetailsPane` and
  `DataTableColumn` from `@agenticdevelopertoolkit/ui/blocks/list-with-details-pane`
  and `@agenticdevelopertoolkit/ui/components/data-table`, and `AdminNote`
  from `../lib/invitations-types`. Two independent `Dialog` roots are
  controlled by `open` and `editorOpen` respectively.
- **SwiftUI**: Model the outer surface as a `.sheet(isPresented:)` and the
  note editor as a second, `.sheet(item:)`-keyed sheet (an enum for
  closed/new/editing an id) so both can be independently presented. Use a
  `NavigationSplitView` or a `List(selection:)` plus a detail `VStack` for the
  list/detail pane, and a `TextEditor` with `.accessibilityLabel("Note
  content")` for the note editor. Stage a `@State` working array reset in
  `.onChange(of: isPresented)`, mirroring the source's seed/re-seed effect;
  `Equatable` conformance on the note model gives the dirty check for free.
- **Compose**: Use an `AlertDialog`/`Dialog` composable for the outer surface
  and a second, independently controlled `Dialog` for the note editor. Use a
  two-pane `Row` (a `LazyColumn` list + inline detail `Column`) or a Material
  3 adaptive list-detail scaffold in place of `ListWithDetailsPane`, and an
  `OutlinedTextField(singleLine = false)` for the note editor. Hoist the
  working list as `remember { mutableStateOf(notes) }`, re-seeding it from a
  `LaunchedEffect(open, notes)` that reproduces the same "only when unedited"
  guard as the source.
- **AppKit/UIKit**: Present the outer surface as a sheet
  (`NSHostingController`/`UIHostingController`, or a native `NSPanel`) and the
  note editor as a second, independently presented sheet. Use an
  `NSTableView`/`UITableView` for the note list with a detail split, and an
  `NSTextView`/`UITextView` for the note editor, calling
  `setAccessibilityLabel("Note content")` (AppKit) or setting
  `accessibilityLabel` (UIKit) to match the source's `aria-label`.
- **WinUI 3**: Use a single `ContentDialog` whose content swaps, via a
  `Visibility` binding equivalent to `editingId !== null`, between the
  two-pane list/detail view (a `ListView` bound to the working collection plus
  a details `Grid`, laid out side by side or switched with an
  `AdaptiveTrigger`/`VisualState` at narrow widths) and the note editor pane
  (a `TextBox AcceptsReturn="True" TextWrapping="Wrap"
  AutomationProperties.Name="Note content"`). Avoid nesting a second
  `ContentDialog` for the editor — WinUI does not stack them cleanly — and
  instead swap content within the one dialog, keeping a separate "new vs.
  edit" title binding (`"New note"` / `"Edit note"`) on the `ContentDialog`'s
  `Title`. Bind the primary button's `IsEnabled` to a `Dirty && !Busy`
  view-model property for the list view and to `Draft.Trim().Length > 0` for
  the editor view, mirroring the source's `disabled={busy || !dirty}` and
  `disabled={draft.trim() === ""}`. Rely on `ContentDialog`'s default
  `CloseButtonCommand`/Escape handling for the no-confirmation discard path
  while in list-view content, matching the source's unconfirmed
  Cancel/Escape/close. Because both views share the one `ContentDialog`, that
  default Escape/`CloseButtonCommand` handling would dismiss the whole dialog
  when it fires in editor-view content — discarding the staged working list,
  not just the draft, which breaks **discards-draft-on-editor-cancel**.
  Override Escape/`CloseButtonCommand` while in editor-view content to return
  to list-view content (mirroring `cancelEditor`) instead of closing the
  `ContentDialog`; see the matching Design Decision below.

## Design Decisions

- **Decision**: Re-seed the staged working list from `notes` only when the
  dialog is closed, or when it is open and the working list still equals the
  value it was last seeded from.
  **Rationale**: A reopened dialog, or a background refetch landing on an
  untouched open dialog, must reflect the freshest loaded notes — but a
  background refetch must never silently overwrite an admin's in-progress
  edits. Comparing against the last-seeded value (rather than `notes`
  directly) is what lets the effect distinguish "the admin hasn't touched
  anything since the last seed" from "the incoming prop changed," per the
  source's own comment on this boundary.
  **Approved**: pending
- **Decision**: A concurrent edit made by another admin during a staged local
  session is dropped by outer Save and left unresolved by this component.
  **Rationale**: The source explicitly scopes this out as a data-merge problem,
  distinct from the save-gate problem this component solves, and calls a
  three-way merge here "a large, unreviewed behaviour change" to be
  addressed deliberately and separately, not incidentally.
  **Approved**: pending
- **Decision**: Both dialogs discard staged state on Cancel/Escape/close with no
  confirmation prompt.
  **Rationale**: Not explained beyond the discard-and-reset implementation
  itself; recorded here as the literal, observed contract rather than an
  endorsed ideal, so implementations on other platforms match it exactly
  instead of assuming a confirm step exists.
  **Approved**: pending
- **Decision**: `busy` disables only the outer Save control; it does not block
  dismissal and drives no spinner or other visual indicator.
  **Rationale**: Not explained in source; captured here as the literal contract
  so other-platform implementations do not add dismissal-blocking or a
  spinner that the source does not have.
  **Approved**: pending
- **Decision**: A new note's `id` is client-generated (`note-${Date.now()}`) and
  submitted to the caller inside the same `{id, content}` shape used for
  existing notes.
  **Rationale**: Keeps the outer Save payload uniform for new and existing
  notes; how the caller/backend treats a client-generated, not-yet-persisted
  id is outside this file and not observable here.
  **Approved**: pending
- **Decision**: On WinUI 3, where both list and editor views share one
  `ContentDialog`, Escape/`CloseButtonCommand` while in editor-view content
  must return to list-view content rather than close the `ContentDialog`.
  **Rationale**: The source's two-independent-dialogs structure lets Escape on
  the note editor discard only the draft (**discards-draft-on-editor-cancel**),
  leaving the outer working list untouched. A single shared `ContentDialog`
  has no second dialog to dismiss independently, so its default Escape/close
  handling would discard the whole working list instead — a structural
  divergence from the source that this override corrects.
  **Approved**: pending
