<!-- leaf: implement-general-1/admin-notes-modal · source: admin-notes-modal.md -->

**Rules** (cite as `implement-general-1/admin-notes-modal#<slug>`):

- `seeds-working-copy-on-mount` MUST
- `discards-staged-edits-on-close` MUST
- `adopts-refreshed-notes-when-unedited` MUST
- `preserves-staged-edits-across-refresh` MUST
- `opens-new-note-editor-with-blank-draft` MUST
- `opens-edit-note-editor-seeded-with-content` MUST
- `rejects-blank-editor-save` MUST
- `appends-new-note-on-editor-save` MUST
- `updates-existing-note-on-editor-save` MUST
- `closes-editor-on-successful-save` MUST
- `discards-draft-on-editor-cancel` MUST
- `removes-deleted-notes-from-working` MUST
- `disables-editor-save-when-draft-blank` MUST
- `computes-dirty-by-structural-comparison` MUST
- `disables-outer-save-when-not-dirty-or-busy` MUST
- `submits-id-and-content-only` MUST
- `closes-without-confirmation` MUST
- `ignores-busy-for-dismissal` MUST
- `renders-note-list-columns` MUST
- `renders-selected-note-detail` MUST
- `labels-outer-dialog-title` MUST
- `labels-editor-title-by-mode` MUST
- `supplies-note-list-aria-label` MUST
- `labels-note-content-field` MUST
- `accepts-optional-busy-prop` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `open` | `boolean` | — (required) | Controls whether the outer dialog is shown. |
| `onClose` | `() => void` | — (required) | Invoked when Cancel, Escape, or the close control dismiss the outer dialog. |
| `author` | `string` | — (required) | Recorded as the `author` field of any note created during this session. |
| `notes` | `AdminNote[]` | — (required) | The already-loaded notes; seeds, and conditionally re-seeds, the working list. |
| `onSave` | `(notes: { id?: string; content: string }[]) => void` | — (required) | Invoked with the working list's id/content pairs when outer Save is activated. |
| `busy` | `boolean` | `false` | Disables the outer Save control while `true`; has no other effect. |

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

