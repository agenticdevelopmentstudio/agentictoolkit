<!-- leaf: implement-general-2/notes-and-history · source: notes-and-history.md -->

**Rules** (cite as `implement-general-2/notes-and-history#<slug>`):

- `slice-10-notesandhistory-not-parse-reformat-re-localize` MUST — Date formatting: modifiedDate and timestamp arrive as plain YYYY-MM-DD strings, already formatted before this component …
- `renders-notes-section` MUST
- `renders-history-section` MUST
- `sections-load-independently` MUST
- `notes-loading-indicator` MUST
- `history-loading-indicator` MUST
- `notes-empty-message` MUST
- `history-empty-message` MUST
- `notes-list-rendering` MUST
- `history-list-rendering` MUST
- `preserves-source-order` MUST
- `no-internal-data-fetching` MUST
- `loading-props-default-to-false` MUST

# NotesAndHistory

## Overview

`NotesAndHistory` is a presentational detail-panel section that renders a
subject's admin notes and its history, stacked in a single container. It is
prop-driven: the caller fetches the data and passes it in — `NotesAndHistory`
itself never fetches anything. Notes and history are independent: each has its
own optional loading flag, so a slow history fetch never withholds
already-loaded notes, and vice versa.

## Types

- `AdminNote` (from `invitations-types.ts`): `{ id: string; content: string;
  author: string; addedDate: string; modifiedDate: string; subjectTable:
  string; subjectId: string }`. The component reads only `id`, `content`,
  `author`, and `modifiedDate`; `addedDate`, `subjectTable`, and `subjectId`
  exist on the type but are not rendered here.
- `HistoryEntry` (from `invitations-types.ts`): `{ id: string; actor: string;
  action: string; timestamp: string }`. The component reads all four fields.
- Date formatting: `modifiedDate` and `timestamp` arrive as plain `YYYY-MM-DD`
  strings, already formatted before this component ever sees them —
  `toAdminNote`/`toHistoryEntry` in `invitations-types.ts` produce them via
  `updatedAt.slice(0, 10)` / `createdAt.slice(0, 10)`. `NotesAndHistory` MUST
  NOT parse, reformat, or re-localize either field; it renders whatever
  string arrives on the prop.

## Behavioral Requirements

- **renders-notes-section**: The component MUST render an "Admin notes"
  section.
- **renders-history-section**: The component MUST render a "History" section.
- **sections-load-independently**: The component MUST evaluate the notes
  section's loading state from `notesLoading` and the history section's
  loading state from `historyLoading` independently, so a slow history fetch
  MUST NOT withhold already-loaded notes, and a slow notes fetch MUST NOT
  withhold already-loaded history.
- **notes-loading-indicator**: WHEN `notesLoading` is `true`, the component
  MUST render "Loading…" in place of the notes list or empty message.
- **history-loading-indicator**: WHEN `historyLoading` is `true`, the
  component MUST render "Loading…" in place of the history list or empty
  message.
- **notes-empty-message**: WHEN `notesLoading` is not `true` and `notes` is
  empty, the component MUST render "No admin notes." instead of a list.
- **history-empty-message**: WHEN `historyLoading` is not `true` and
  `history` is empty, the component MUST render "No history." instead of a
  list.
- **notes-list-rendering**: WHEN `notesLoading` is not `true` and `notes` is
  non-empty, the component MUST render one list item per entry in `notes`.
  Each item MUST display that note's `content` on its own line, followed by
  a line reading `author · modifiedDate` — the note's `author` and
  `modifiedDate` joined by a middle dot (`·`) with one space on each side.
- **history-list-rendering**: WHEN `historyLoading` is not `true` and
  `history` is non-empty, the component MUST render one list item per entry
  in `history`. Each item MUST read `timestamp — actor action` — the
  entry's `timestamp` set off by an em dash (`—`) with one space on each
  side, followed by `actor` and `action` separated by a single space.
- **preserves-source-order**: The component MUST render notes and history
  list items in the same order as the `notes`/`history` arrays supplied by
  the caller; it MUST NOT sort or otherwise reorder them.
- **no-internal-data-fetching**: The component MUST NOT issue a network
  request or otherwise fetch `notes`/`history` itself; it MUST render
  exclusively from the `notes`, `history`, `notesLoading`, and
  `historyLoading` props supplied by the caller.
- **loading-props-default-to-false**: WHEN `notesLoading` or
  `historyLoading` is omitted, the component MUST treat the omitted flag as
  `false` — i.e. it MUST evaluate the corresponding empty/populated branch
  rather than the loading branch.

## Appearance

- **Corner radius**: Notes-list items: `rounded-md` (6px). History-list
  items: none — flat text lines with no container.
- **Padding**: Root container: `mt-4` (16px top margin), `gap-4` (16px
  between the two sections). Notes-list items: `p-2` (8px all sides); notes
  `<ul>`: `mt-1` (4px top margin), `gap-2` (8px between items). History
  `<ul>`: `mt-1` (4px top margin), `gap-1` (4px between items).
- **Font**: Section headings (`<h4>`): `text-xs` (12px), `font-semibold`,
  `uppercase`, `tracking-wide`. Loading/empty messages and list content:
  `text-sm` (14px). Note author/date line and history timestamp: `text-xs`
  (12px).
- **Background**: Notes-list items: `bg-apt-surface-2/40` (the
  `apt-surface-2` token at 40% opacity). History-list items and the root
  container: transparent (no background class).
- **Foreground/Text**: Section headings: `text-apt-text-muted`. Note content
  and history line text: `text-apt-text`. Note author/date and history
  timestamp: `text-apt-text-muted`. Loading and empty messages:
  `text-apt-text-dim`.
- **Border**: Notes-list items: `border border-apt-border` (1px, the
  `apt-border` token color). History-list items: none.
- **Shadow**: None — no shadow class appears anywhere in source.
- **Min/Max size**: None — no width/height constraint appears in source; the
  section grows to fit its content.

## Accessibility

- **Role/trait**: No ARIA role is set anywhere in source. Each subject area
  is a plain `<section>` headed by a native `<h4>` ("Admin notes",
  "History"), so assistive-technology heading navigation exposes both
  section titles even though the `<section>` elements carry no accessible
  name of their own (no `aria-label`/`aria-labelledby`).
- **Label requirements**: Not applicable in the form-control sense: the
  component renders no input, button, or other labelable control. The only
  labels present are the two `<h4>` section headings, which are plain text
  requiring no separate accessible-name wiring.
- **Announce state changes (e.g., loading, disabled)**: Not implemented.
  Source renders the loading-to-populated/empty transition as a plain text
  swap with no `aria-live`/`role="status"` wrapper, so a screen-reader user
  is not proactively notified when a section's content resolves (WCAG
  4.1.3 Status Messages).
- **Minimum tap target**: Not applicable: the component renders no
  interactive element anywhere in its output (no button, link, or input),
  so there is no tap target to size.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `notes` | `AdminNote[]` | — (required) | Admin notes for the subject; rendered as a card list in array order. |
| `history` | `HistoryEntry[]` | — (required) | History entries for the subject; rendered as a line list in array order. |
| `notesLoading` | `boolean` | `false` (omission treated as `false`) | When `true`, replaces the notes list/empty message with "Loading…". |
| `historyLoading` | `boolean` | `false` (omission treated as `false`) | When `true`, replaces the history list/empty message with "Loading…". |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `notes-and-history.admin-notes-heading` | Admin notes | `<h4>` heading above the notes section |
| `notes-and-history.loading` | Loading… | Shown in place of either section's list/empty message while that section's loading flag is `true` |
| `notes-and-history.no-admin-notes` | No admin notes. | Shown when `notesLoading` is not `true` and `notes` is empty |
| `notes-and-history.history-heading` | History | `<h4>` heading above the history section |
| `notes-and-history.no-history` | No history. | Shown when `historyLoading` is not `true` and `history` is empty |

Source hardcodes all five strings as English JSX literals with no
translation call (no `t()`, `useTranslation`, or `FormattedMessage`); the
keys above are what an implementation would externalize them to.

## Privacy

- **Data collected**: Not applicable: the component collects no data of its
  own; `content`, `author`, `actor`, and other fields it displays are
  already-fetched props supplied by the caller.
- **Storage**: Not applicable: source performs no read/write to any
  storage — it holds no state beyond what React needs to render its props.
- **Transmission**: Not applicable: source issues no network request (see
  no-internal-data-fetching); nothing leaves the device from this
  component.
- **Retention**: Not applicable: the component retains nothing after it
  unmounts or re-renders with new props.

