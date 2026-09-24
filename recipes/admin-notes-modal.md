---
id: 589babce-b66e-447f-8049-f81af380bbef
title: AdminNotesModal
domain: agentictoolkit://recipes/admin-notes-modal
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Prop-driven, staged Cancel/Save admin-notes editor: a controlled dialog
  over a note list-with-details pane, plus a nested new/edit note editor dialog.'
platforms:
- typescript
- web
tags:
- modal
- notes
- admin
- list-detail
depends-on:
- agenticdevelopertoolkit://recipes/dialog
- agenticdevelopertoolkit://recipes/list-with-details-pane
- agenticdevelopertoolkit://recipes/button
- agenticdevelopertoolkit://recipes/textarea
related: []
references: []
approved-by: ''
approved-date: ''
---

# AdminNotesModal

## Overview

`AdminNotesModal` is a controlled dialog in `@agentic-toolkit/adh-ui`
(`packages/web/packages/adh-ui/src/blocks/admin-notes-modal.tsx`) for reviewing
and editing an admin's freeform notes about some subject. The caller supplies
the already-loaded `notes` and an `onSave` callback; the component seeds a
private staged copy (`working`) from `notes`, lets the admin add, edit, and
delete notes against that staged copy through a `ListWithDetailsPane` and a
nested note editor, and only reports the result to the caller when Save is
activated. React-query and the actual persistence mutation live in the caller,
never in this component. The "New note" control is supplied to
`ListWithDetailsPane` via its `actions` prop
(`{ id: "new", label: "New note", onClick: openNewNote }`); `ListWithDetailsPane`
renders it and owns its placement — see
`agenticdevelopertoolkit://recipes/list-with-details-pane`.

`AdminNote` (imported from `../lib/invitations-types`, not defined in this
file) is used here with exactly seven fields: `id`, `content`, `author`,
`addedDate`, `modifiedDate`, `subjectTable`, and `subjectId`, all `string`.
`addedDate` and `modifiedDate` are ISO 8601 calendar dates in `YYYY-MM-DD`
form, produced by `new Date().toISOString().slice(0, 10)`.

## Behavioral Requirements

- **seeds-working-copy-on-mount**: The component MUST initialize its internal
  working note list from the `notes` prop.
- **discards-staged-edits-on-close**: When `open` transitions to `false`, the
  component MUST discard any staged edits and reset the working list to the
  current `notes` prop.
- **adopts-refreshed-notes-when-unedited**: While `open` is `true`, if the
  working list is unchanged from the value it was last seeded from and the
  `notes` prop changes, the component MUST adopt the new `notes` value into
  the working list.
- **preserves-staged-edits-across-refresh**: While `open` is `true`, if the
  working list diverges from the value it was last seeded from (the admin has
  staged an add, edit, or delete), a change to the `notes` prop MUST NOT
  overwrite the working list.
- **opens-new-note-editor-with-blank-draft**: Activating "New note" MUST open
  the note editor with an empty draft and no note selected for editing.
- **opens-edit-note-editor-seeded-with-content**: Activating "Edit" on a note
  MUST open the note editor with the draft seeded from that note's `content`.
- **rejects-blank-editor-save**: Activating Save in the note editor MUST have
  no effect on the working list and MUST leave the editor open when the
  trimmed draft is empty.
- **appends-new-note-on-editor-save**: Activating Save in the note editor
  while creating a note MUST append a new note to the working list with a
  generated `id`, the trimmed draft as `content`, the current `author` prop,
  empty `subjectTable`/`subjectId`, and `addedDate`/`modifiedDate` both set to
  the current date.
- **updates-existing-note-on-editor-save**: Activating Save in the note editor
  while editing an existing note MUST replace only that note's `content` and
  `modifiedDate` in the working list, leaving its `id`, `author`, `addedDate`,
  `subjectTable`, and `subjectId` unchanged.
- **closes-editor-on-successful-save**: A non-blank editor Save MUST close the
  note editor and clear the draft.
- **discards-draft-on-editor-cancel**: Activating Cancel in the note editor,
  or dismissing it via Escape or its close control, MUST close the editor and
  discard the draft without altering the working list, and MUST NOT present a
  confirmation prompt.
- **removes-deleted-notes-from-working**: Confirming deletion of one or more
  notes MUST remove exactly those notes, matched by `id`, from the working
  list.
- **disables-editor-save-when-draft-blank**: The note editor's Save control
  MUST be disabled whenever the trimmed draft is empty.
- **computes-dirty-by-structural-comparison**: The outer Save control's
  enabled state MUST be derived from a structural, order-sensitive comparison
  of the working list against the current `notes` prop, considering every
  `AdminNote` field (`id`, `content`, `author`, `addedDate`, `modifiedDate`,
  `subjectTable`, `subjectId`) of every note.
- **disables-outer-save-when-not-dirty-or-busy**: The outer Save control MUST
  be disabled when the working list is not dirty relative to `notes`, or when
  `busy` is `true`.
- **submits-id-and-content-only**: Activating the outer Save control MUST call
  `onSave` with one entry per note in the working list, each entry containing
  only that note's `id` and `content`. `onSave`'s type declares `id` optional,
  but every entry this component submits always carries one: existing notes
  keep their loaded `id`, and notes created during this session carry the
  client-generated `note-`-prefixed `id` (see
  **appends-new-note-on-editor-save**). A caller distinguishes an unpersisted
  note from an existing one by testing for that `note-` prefix; the optional
  type exists only to accommodate callers, not a case this component itself
  produces.
- **closes-without-confirmation**: Activating outer Cancel, or dismissing the
  outer dialog via Escape or its close control, MUST discard the staged
  working list and invoke `onClose`, regardless of whether the working list is
  dirty, and MUST NOT present a confirmation prompt.
- **ignores-busy-for-dismissal**: The `busy` prop MUST NOT block Cancel,
  Escape, or close-control dismissal of the outer dialog; it MUST only disable
  the outer Save control.
- **renders-note-list-columns**: The note list MUST display each note's
  `author`, `addedDate`, and `modifiedDate` as columns headed "Author",
  "Added", and "Modified".
- **renders-selected-note-detail**: Selecting a single note MUST display its
  `content` and an "Edit" action that opens the note editor for that note.
- **labels-outer-dialog-title**: The outer dialog MUST display the title
  "Admin notes".
- **labels-editor-title-by-mode**: The note editor MUST display the title
  "New note" when creating a note and "Edit note" when editing an existing
  note.
- **supplies-note-list-aria-label**: The component MUST supply "Admin notes"
  as the note list's accessible label.
- **labels-note-content-field**: The note editor's text field MUST carry an
  accessible label of "Note content".
- **accepts-optional-busy-prop**: The `busy` prop MAY be omitted; when
  omitted the component MUST behave as though it were `false`.

## Appearance

- **Corner radius**: Inherited unmodified from the shared `Dialog` ingredient
  (`rounded-xl`) on both the outer dialog and the note editor.
- **Padding**: Inherited unmodified from `Dialog` (`p-5`) on both dialogs.
- **Font**: Titles use `Dialog`'s default `text-base font-semibold`; the note
  content in the detail pane renders as `whitespace-pre-wrap text-sm`.
- **Background**: Inherited unmodified from `Dialog` (`bg-apt-surface`).
- **Foreground/Text**: Both dialog titles override `Dialog`'s default
  `text-apt-text` with `text-apt-gold`; the note content in the detail pane
  is `text-apt-text`.
- **Border**: Inherited unmodified from `Dialog` (`border-apt-border`).
- **Shadow**: Inherited unmodified from `Dialog` (`shadow-xl`).
- **Min/Max size**: Outer dialog overrides `Dialog`'s default `max-w-md` with
  `max-w-3xl`; the note-list host is a fixed `h-[420px]` container; the note
  editor dialog uses `max-w-lg`; the editor's text field uses `min-h-32`.

## States

| State | Appearance change |
|-------|--------------------|
| Closed | Nothing rendered (`open=false`); working list reset to `notes`. |
| Open, notes present | Note list shows Author/Added/Modified columns via `ListWithDetailsPane`. |
| Open, zero notes | List shows "No admin notes yet." instead of rows. |
| Row selected | Detail pane shows the note's content and an "Edit" action. |
| No row selected | Detail pane shows "Select a note to read it." |
| Note editor open, new | Editor titled "New note"; blank text field; editor Save disabled until non-blank input. |
| Note editor open, edit | Editor titled "Edit note"; text field pre-filled with the note's content. |
| Working list dirty | Outer Save enabled (unless `busy`). |
| Working list not dirty | Outer Save disabled. |
| `busy=true` | Outer Save disabled regardless of dirty state; Cancel, Escape, and close remain active. |

## Accessibility

- Role and keyboard/focus-trap behavior for both dialogs (outer and note
  editor) come unmodified from the shared `Dialog` ingredient; see
  `agenticdevelopertoolkit://recipes/dialog` rather than restating it here.
- The note list carries the accessible label "Admin notes" (the `ariaLabel`
  the component supplies to `ListWithDetailsPane`); how that label is applied
  internally is `ListWithDetailsPane`'s own concern — see
  `agenticdevelopertoolkit://recipes/list-with-details-pane`.
- The note editor's text field carries an accessible label of "Note content".
- Cancel/Save (outer) and Cancel/Save/Edit (editor and detail pane) are all
  instances of the shared `Button`, with visible text labels and native
  keyboard activation; see `agenticdevelopertoolkit://recipes/button`.
- Touch/click target sizing for every control in this component is the shared
  `Button` ingredient's concern (all instances use `size="sm"`) and is not
  restated here.
- The source defines no `aria-live` region and no visual indicator tied to
  `busy` beyond disabling the outer Save control; per the component's own
  documentation the caller owns the save mutation and decides when to close
  the dialog, so this component has no failure state of its own to announce
  (see Edge Cases > Error states, and Design Decisions).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| T1 | seeds-working-copy-on-mount | Mount with `notes=[a,b]` | Note list shows rows `a`, `b` |
| T2 | discards-staged-edits-on-close | Stage an edit, then flip `open` to `false` | Working list resets to `notes`; reopening (same instance) shows the unedited list |
| T3 | adopts-refreshed-notes-when-unedited | Open, stage nothing, caller supplies a new `notes` array | Note list updates to the new `notes` |
| T4 | preserves-staged-edits-across-refresh | Open, stage an edit, caller supplies a new `notes` array | Staged edit remains visible; new `notes` is not adopted |
| T5 | opens-new-note-editor-with-blank-draft | Click "New note" | Editor opens titled "New note" with an empty text field |
| T6 | opens-edit-note-editor-seeded-with-content | Select a note, click "Edit" | Editor opens titled "Edit note" with the text field containing that note's content |
| T7 | rejects-blank-editor-save | In the new-note editor, leave the field blank, click Save | Editor stays open; working list unchanged |
| T8 | appends-new-note-on-editor-save | In the new-note editor, type "Hello", click Save | Working list gains one note with `content="Hello"`, `author` = the `author` prop, `addedDate`/`modifiedDate` = today, `subjectTable`/`subjectId` = `""` |
| T8b | appends-new-note-on-editor-save | Open the new-note editor, wait, then click Save | The new note's `id` is generated at the moment Save is clicked, not when the editor was opened |
| T9 | updates-existing-note-on-editor-save | Edit an existing note's content, click Save | That note's `content` and `modifiedDate` change; `id`, `author`, `addedDate`, `subjectTable`, `subjectId` are unchanged |
| T10 | closes-editor-on-successful-save | Complete T8 or T9 | Editor closes; draft clears |
| T11 | discards-draft-on-editor-cancel | Type into the editor, click Cancel | Editor closes; working list unchanged; no confirmation prompt appears |
| T11b | discards-draft-on-editor-cancel | Type into the editor, dismiss via Escape or its close control | Editor closes; working list unchanged; no confirmation prompt appears |
| T12 | removes-deleted-notes-from-working | Select a note, confirm delete | That note is absent from the working list |
| T13 | disables-editor-save-when-draft-blank | Editor open, field empty or whitespace-only | Editor Save is disabled |
| T14 | computes-dirty-by-structural-comparison | Stage an edit, then revert it back to the original value | Outer Save is disabled again (matches `notes`) |
| T15 | disables-outer-save-when-not-dirty-or-busy | Working list unchanged from `notes` | Outer Save is disabled |
| T15b | disables-outer-save-when-not-dirty-or-busy | Working list dirty, `busy=true` | Outer Save is disabled |
| T16 | submits-id-and-content-only | Stage an add and an edit, click outer Save | `onSave` is called with an array of `{id, content}` entries only, one per working-list note |
| T16b | submits-id-and-content-only | Add a new note, click outer Save | The new note's submitted `id` carries the `note-` prefix; a pre-existing note's submitted `id` is unchanged from its loaded value |
| T17 | closes-without-confirmation | Stage edits, click outer Cancel | Working list resets to `notes`; `onClose` is called; no confirmation prompt appears |
| T18 | ignores-busy-for-dismissal | `busy=true`, press Escape | Outer dialog closes via the normal discard path |
| T18b | ignores-busy-for-dismissal | `busy=true`, click outer Cancel or the outer dialog's close control | Outer dialog closes via the normal discard path |
| T19 | renders-note-list-columns | Any non-empty `notes` | Columns headed "Author", "Added", "Modified" are present |
| T20 | renders-selected-note-detail | Select one note | Detail pane shows that note's content and an "Edit" button |
| T21 | labels-outer-dialog-title | Open the modal | Title text reads "Admin notes" |
| T22 | labels-editor-title-by-mode | Open new-note vs. edit-note editor | Title reads "New note" / "Edit note" respectively |
| T23 | supplies-note-list-aria-label | Inspect the note list's accessible name | Reads "Admin notes" |
| T24 | labels-note-content-field | Inspect the editor field's accessible name | Reads "Note content" |
| T25 | accepts-optional-busy-prop | Render without passing `busy` | Outer Save behaves as `busy=false` |

## Edge Cases

- Null/empty input: `notes=[]` MUST render the list's "No admin notes yet."
  empty label instead of a table.
- Null/empty input: An editor Save with a draft that is empty or entirely
  whitespace MUST be rejected — no note is added or changed, and the editor
  stays open.
- Boundary values: The note editor's text field imposes no maximum length;
  the component MUST NOT truncate or otherwise limit note content itself.
- Boundary values: The generated `id` (`note-${Date.now()}`) MUST be assigned
  once, at editor-Save time, not at editor-open time — two notes started in
  the same session but saved at different times get distinct ids. Because the
  id is derived from `Date.now()` (millisecond resolution), two saves landing
  in the same millisecond collide on the same id; this is a known,
  pre-existing limitation of the source's id-generation scheme, not a
  behavior another port needs to reproduce exactly.
- Concurrent access: If another admin adds a note to the same subject while
  this dialog is open and the local admin has staged edits, outer Save drops
  that concurrently added note — the working list only ever contains what was
  staged locally plus the seed it started from. This is a documented,
  deliberate limitation in the source, not an oversight: it is a data-merge
  problem the component's author explicitly scoped out of the
  staged-copy/save-gate design and left as a known, pre-existing gap rather
  than papering over it with an unreviewed merge. See the matching Design
  Decision below ("A concurrent edit made by another admin...").
- Error states: The component defines no error prop and no failure UI of its
  own. Per its own documentation, the caller performs the save mutation and
  is responsible for closing the dialog only on success; this component's
  only role during a save attempt is disabling the outer Save control while
  `busy` is `true`. A save failure MUST NOT be assumed to be surfaced by this
  component — that responsibility remains with the caller.
- Offline/disconnected: Not applicable. The component makes no network calls
  of its own; connectivity handling belongs entirely to the caller's `onSave`
  implementation and is not observable in this file.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `open` | `boolean` | — (required) | Controls whether the outer dialog is shown. |
| `onClose` | `() => void` | — (required) | Invoked when Cancel, Escape, or the close control dismiss the outer dialog. |
| `author` | `string` | — (required) | Recorded as the `author` field of any note created during this session. |
| `notes` | `AdminNote[]` | — (required) | The already-loaded notes; seeds, and conditionally re-seeds, the working list. |
| `onSave` | `(notes: { id?: string; content: string }[]) => void` | — (required) | Invoked with the working list's id/content pairs when outer Save is activated. |
| `busy` | `boolean` | `false` | Disables the outer Save control while `true`; has no other effect. |

## Deep Linking

Not applicable: the component takes no route or URL prop and performs no
history/URL manipulation; visibility is driven entirely by the caller's
`open` boolean. (Contrast `ListWithDetailsPane`'s own optional `paramKey`
deep-linking feature, which this component does not pass through.)

## Localization

Not applicable: every user-facing string ("Admin notes", "New note", "Edit
note", "Cancel", "Save", "Edit", "Note content", "No admin notes yet.",
"Select a note to read it.", "Author", "Added", "Modified") is a hardcoded
English literal in the source; no i18n/translation mechanism is referenced.

## Accessibility Options

- **Reduce Motion**: Not applicable — the source applies no animation or
  transition classes to either dialog's entry/exit; there is no motion for
  this setting to reduce.
- **Increase Contrast**: Not applicable — all color comes from `apt-*` theme
  tokens inherited from `Dialog`/`Button`/`Textarea`; the component performs
  no contrast-specific branching of its own.
- **Differentiate Without Color**: Not applicable — the component conveys no
  state through color alone; note selection and the Edit action are
  identified by content and text labels, not color.

## Feature Flags

Not applicable: the source contains no feature-flag check.

## Analytics

Not applicable: the source contains no analytics or telemetry call.

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

## Logging

Not applicable: the source contains no logging call.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | passed | accessibility |

The source shows no override of `Dialog`'s default focus-trap/dismissal
handling on either dialog (no custom keydown handling, no manual `.focus()`
calls), so `focus-management` passes on the strength of `Dialog`'s
own unmodified behavior.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from source. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: rewrote the concurrent-access edge case as a non-normative documented limitation, clarified the `onSave` id contract and the id-collision risk, added the `AdminNote` shape and `New note` control location, listed all `AdminNote` fields in the dirty comparison, added a WinUI 3 Escape/close override for the shared-`ContentDialog` structure with a matching Design Decision, reformatted Design Decisions to the bold three-line form, added `textarea` to `depends-on`, completed the Localization string list, fixed the `modal-dismissal-and-focus` compliance status, and added test vectors for editor Escape/close dismissal, busy+dismissal, submitted-id-prefix, and Save-time id assignment. |
| 1.1.1 | 2026-09-23 | Mike Fullerton | Compliance: removed rows for checks absent from the cookbook catalog, remapped modal-dismissal-and-focus to focus-management |
