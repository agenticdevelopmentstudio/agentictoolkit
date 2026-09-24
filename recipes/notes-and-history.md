---
id: b2c3bfad-cfd1-4a0f-bfbf-89f5d3712700
title: Notes and History
domain: agentictoolkit://recipes/notes-and-history
type: ingredient
version: 1.1.1
status: review
language: en
created: 2026-09-23
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Presentational detail-panel section rendering a subject's admin notes and
  history, each with independent loading, empty, and populated states.
platforms:
- typescript
- web
tags:
- component
- notes
- history
- detail-panel
- ui
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Notes: Loading (`notesLoading=true`) | Notes section shows only "Loading…" (`text-apt-text-dim`); no list is rendered regardless of `notes` contents |
| Notes: Empty (`notesLoading` false/omitted, `notes.length===0`) | Notes section shows "No admin notes." (`text-apt-text-dim`); no list is rendered |
| Notes: Populated (`notesLoading` false/omitted, `notes.length>0`) | Notes section renders a bordered/background card per note, in array order |
| History: Loading (`historyLoading=true`) | History section shows only "Loading…"; no list is rendered regardless of `history` contents |
| History: Empty (`historyLoading` false/omitted, `history.length===0`) | History section shows "No history."; no list is rendered |
| History: Populated (`historyLoading` false/omitted, `history.length>0`) | History section renders a plain text line per entry, in array order |
| Pressed | Not applicable: the component renders no button, link, or other pressable control. |
| Disabled | Not applicable: the component exposes no `disabled` prop and no control capable of being disabled. |
| Focused | Not applicable: the component renders no focusable element — no interactive control and no `tabIndex` appears in source. |

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

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| notes-and-history-001 | renders-notes-section, renders-history-section | `notes=[]`, `history=[]`, `notesLoading=false`, `historyLoading=false` | Both an "Admin notes" heading and a "History" heading render as sibling sections in one container |
| notes-and-history-002 | sections-load-independently, notes-loading-indicator | `notesLoading=true`; `history=[oneEntry]`, `historyLoading=false` | Notes section shows "Loading…"; History section shows its populated list, not "Loading…" |
| notes-and-history-003 | sections-load-independently, history-loading-indicator | `historyLoading=true`; `notes=[oneNote]`, `notesLoading=false` | History section shows "Loading…"; Notes section shows its populated list |
| notes-and-history-004 | notes-empty-message | `notesLoading=false`, `notes=[]` | Notes section renders "No admin notes." and no list |
| notes-and-history-005 | history-empty-message | `historyLoading=false`, `history=[]` | History section renders "No history." and no list |
| notes-and-history-006 | notes-list-rendering, preserves-source-order | `notes=[noteA(id:"1"), noteB(id:"2")]`, `notesLoading=false` | Two list items render in array order; the first shows `noteA.content` and "`noteA.author` · `noteA.modifiedDate`"; the second shows `noteB`'s fields |
| notes-and-history-007 | history-list-rendering, preserves-source-order | `history=[entryA(id:"1"), entryB(id:"2")]`, `historyLoading=false` | Two list items render in array order; each reads "`timestamp` — `actor` `action`" |
| notes-and-history-008 | no-internal-data-fetching | Stub `window.fetch` and `XMLHttpRequest` to throw if invoked, then render the component with any valid `notes`/`history`/loading props and re-render it with new props | Both the render and the re-render complete without throwing, and the `fetch`/`XMLHttpRequest` stubs are never called |
| notes-and-history-009 | loading-props-default-to-false | `notesLoading` and `historyLoading` both omitted (`undefined`); `notes=[]`, `history=[]` | Both sections render their empty messages ("No admin notes.", "No history."), not "Loading…" |

## Edge Cases

- Null and empty input: `notes` and `history` are required, typed as
  `AdminNote[]`/`HistoryEntry[]`, so the type system rules out `null`/
  `undefined` arrays; the component's only check is array length (see
  notes-empty-message, history-empty-message). This handles the empty-array
  case; it is a MUST.
- Boundary values: Source contains no `.slice`, pagination, or
  virtualization — `.map` runs over the full array. The component MUST
  render every element of `notes`/`history` with no cap, however large the
  array.
- Concurrent access: Not applicable — this is a stateless, pure
  presentational function component with no internal mutable state; there
  is nothing for concurrent access to race.
- Error states: Not implemented. The `notesLoading`/`historyLoading` props
  imply an underlying async fetch, but the component declares no error
  prop and no rendering branch for a failed fetch — only loading, empty,
  and populated are handled. A caller whose fetch rejects gets no distinct
  error message (e.g. one separate from "No admin notes.") from this
  component; error handling is fully owned by the caller.
- Offline/disconnected: Not applicable — the component performs no
  networking itself (see no-internal-data-fetching); connectivity loss is
  entirely the caller's concern, surfaced (if at all) before `notes`/
  `history`/the loading flags reach this component.
- Duplicate `id` values: Source keys each list item by `id`
  (`key={n.id}`/`key={h.id}`) with no uniqueness check or de-duplication.
  Unique `id`s within `notes` and within `history` are a caller
  precondition, not something this component validates. WHEN that
  precondition is violated, the component still performs no de-duplication;
  implementations SHOULD emit a dev-mode-only warning when they detect a
  duplicate `id` (mirroring React's own duplicate-key warning) rather than
  silently rendering whatever a keyed-list collision resolves to on that
  platform.
- Empty-string field values: An `AdminNote` with `content: ""` or a
  `HistoryEntry` with `action: ""` still counts as populated (array length
  `> 0`) and MUST render as a list item with a blank content/action
  segment, since the empty-state check inspects only array length, not
  field values.
- Long text: No `truncate`/`line-clamp` class appears in source. The
  component MUST NOT truncate `content` or `action` text; long strings wrap
  naturally within the container's width.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `notes` | `AdminNote[]` | — (required) | Admin notes for the subject; rendered as a card list in array order. |
| `history` | `HistoryEntry[]` | — (required) | History entries for the subject; rendered as a line list in array order. |
| `notesLoading` | `boolean` | `false` (omission treated as `false`) | When `true`, replaces the notes list/empty message with "Loading…". |
| `historyLoading` | `boolean` | `false` (omission treated as `false`) | When `true`, replaces the history list/empty message with "Loading…". |

## Deep Linking

Not applicable: `NotesAndHistory` is a presentational sub-section rendered
inside a parent detail panel, not a standalone screen — source defines no
route, scheme handler, or URL of its own (no router or link usage anywhere
in `notes-and-history.tsx`).

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

## Accessibility Options

Not applicable: source applies no motion/transition classes, no
color-only-encoded state, and no custom contrast-sensitive styling beyond
the shared `apt-*` tokens — there is nothing for Reduce Motion, Increase
Contrast, or Differentiate Without Color to change.

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate (e.g. a flag
check) appears anywhere in `notes-and-history.tsx`; the component always
renders once its props are available.

## Analytics

Not applicable: `notes-and-history.tsx` contains no analytics or telemetry
call (no `track()`, `logEvent()`, or similar); it is a pure function of its
props with no side effects.

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

## Logging

Not applicable: `notes-and-history.tsx` contains no logging call (no
`console.*`, no logger); it renders synchronously from props with no side
effect to log.

## Platform Notes

- **SwiftUI**: A `VStack(alignment: .leading, spacing: 16)` holding two
  child `VStack`s (one per section), each starting with a small,
  semibold, uppercase `Text` header. Within each child, switch on
  (loading, isEmpty) the same way the source's ternary does: a literal
  "Loading…" `Text` for the loading case, a muted "No admin notes."/"No
  history." `Text` for the empty case, and otherwise a `ForEach` over
  `Identifiable` note/history models rendering each item's fields — use a
  plain `ForEach` inside the `VStack`, not `List`, to avoid `List`'s row
  chrome and keep history rows as flat, unstyled lines like the source.
- **Compose**: A `Column(verticalArrangement = Arrangement.spacedBy(16.dp))`
  with a nested `Column` per section, each headed by a small, semibold,
  uppercase `Text`. Mirror the source's three-way branch with a `when` on
  (loading, list.isEmpty()): a "Loading…" `Text`, a "No admin notes."/"No
  history." `Text`, or a `Column` (or `LazyColumn` for very large lists)
  built with `items(notes)`/`items(history)` rendering each row.
- **React/Web**: Source file
  `packages/web/packages/adh-ui/src/blocks/notes-and-history.tsx`. A plain
  function component (`ReactElement`, no `"use client"` directive, no
  hooks) that consumes `AdminNote`/`HistoryEntry` from `../lib/
  invitations-types`. Two sibling `<section>`s in a `flex flex-col gap-4`
  container; each section is a ternary chain (`loading ? … : empty ? … :
  list`) styled with Tailwind utilities and the `apt-*` design-token
  vocabulary — no CSS modules, no styled-components.
- **AppKit/UIKit**: A vertical `UIStackView` (spacing 16) with two child
  stack views, each headed by a `UILabel` styled as small, semibold,
  uppercase (UIKit has no built-in `text-transform`, so uppercase the
  string directly or via `NSAttributedString`). Body content mirrors the
  source's flat, unvirtualized rendering: build a child `UIStackView` of
  one row view per note/history entry (a bordered/background view for
  notes, a plain `UILabel` line for history) rather than a `UITableView`,
  since the source never recycles rows or lazily loads.
- **WinUI 3** (the reason this recipe exists): Root `StackPanel
  Orientation="Vertical" Spacing="16"` with two child `StackPanel`s, each
  headed by a `TextBlock` using `Style="{StaticResource
  CaptionTextBlockStyle}"` plus `Foreground="{ThemeResource
  TextFillColorSecondaryBrush}"` — uppercase the header string in
  code-behind/x:Bind converter, since XAML has no CSS-style text
  transform. Bind an `ItemsRepeater` (not `ListView`, to avoid selection
  and virtualization chrome the source never has) to the notes/history
  collection inside each `StackPanel`; give each `StackPanel`/
  `ItemsRepeater` pair two independent `VisualStateGroup`s
  ("NotesState"/"HistoryState" with states "Loading"/"Empty"/"Populated"),
  driven by two independent `bool` `x:Bind` properties (`NotesLoading`,
  `HistoryLoading`) — mirroring the source's two separate loading flags
  rather than one shared loading state. Loading and empty `TextBlock`s use
  `Foreground="{ThemeResource TextFillColorTertiaryBrush}"` (mapping the
  source's dim `apt-text-dim`), and body-content `TextBlock`s use
  `Foreground="{ThemeResource TextFillColorPrimaryBrush}"` (mapping
  `apt-text`). Note item template: a `Border CornerRadius="6"
  BorderThickness="1" Padding="8"
  BorderBrush="{ThemeResource CardStrokeColorDefaultBrush}"
  Background="{ThemeResource CardBackgroundFillColorSecondaryBrush}"`
  wrapping a `StackPanel` with the content `TextBlock`
  (`TextFillColorPrimaryBrush`) and a secondary, muted `TextBlock`
  (`TextFillColorSecondaryBrush`, mapping `apt-text-muted`) reading
  "author · modifiedDate". History item template: a single `TextBlock`
  with a muted (`TextFillColorSecondaryBrush`) inline `Run` for the
  timestamp followed by a plain (`TextFillColorPrimaryBrush`) run reading
  " — actor action" — no `Border`, matching the source's unstyled history
  rows.

## Design Decisions

- **Decision**: Give notes and history independent loading flags
  (`notesLoading`, `historyLoading`) rather than one combined loading
  flag.
  **Rationale**: The source comment states each section "has its own loading
  flag — a slow history fetch never withholds already-loaded notes." A
  single shared flag would force both sections to wait on the slower of
  the two fetches.
  **Approved**: pending
- **Decision**: Keep the component purely presentational, with no internal
  data fetching, caching, or state management.
  **Rationale**: The source comment states "the caller fetches the data
  (react-query lives in the app, never here)." This keeps the block reusable
  by any caller regardless of its data-fetching strategy.
  **Approved**: pending
- **Decision**: Render admin notes as bordered/background cards
  (`rounded-md border ... bg-apt-surface-2/40 p-2`) while history entries
  render as plain, unstyled text lines.
  **Rationale**: Notes carry free-form, user-authored content that benefits
  from a visually distinct container; history entries are terse, uniform
  log lines that read better as a compact, unadorned list.
  **Approved**: pending
- **Decision**: Fix each section's heading at `<h4>` rather than exposing a
  configurable heading-level prop.
  **Rationale**: Source hardcodes `<h4>` for both "Admin notes" and
  "History" with no prop controlling it; `NotesAndHistory` is always
  composed as a sub-section of a larger detail panel, so its heading depth
  is assumed rather than negotiated with the caller. Accessibility
  tradeoff: a caller whose surrounding structure doesn't already place an
  `<h3>` (or shallower) immediately above this block will produce a
  skipped heading level for assistive-technology heading navigation — see
  **renders-notes-section**/**renders-history-section**.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | Platform Compliance |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [semantic-markup](agenticdevelopercookbook://compliance/accessibility#semantic-markup) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [locale-aware-formatting](agenticdevelopercookbook://compliance/internationalization#locale-aware-formatting) | partial | Internationalization |

`platform-theming`/`separation-of-concerns` pass on every color in source
using the `apt-*` token vocabulary with no raw hex value or `!important`,
and on the component containing no data-fetching, caching, or
state-management code (see Design Decisions). The three accessibility
checks are `partial`: source uses relative-unit Tailwind text utilities and
semantic `<section>`/`<h4>` markup with no incorrect ARIA, but neither
Dynamic Type behavior nor token contrast ratios are verifiable from source
alone, and the missing `aria-live` wiring for the loading-to-populated
transition (see Accessibility: Announce state changes) is a real gap.
`string-externalization`/`no-hardcoded-strings` fail because all five
strings are English JSX literals with no translation call;
`locale-aware-formatting` is `partial` because `modifiedDate`/`timestamp`
arrive pre-formatted from `invitations-types.ts` (see Types) and the
component itself performs no formatting of its own.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial ingredient recipe for NotesAndHistory, covering independent per-section loading/empty/populated states, source-fidelity edge cases, and two open accessibility/error-handling questions for review. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: retitled to a human-readable form; added a Types section documenting `AdminNote`/`HistoryEntry` fields and date-formatting ownership; tied the notes/history list-rendering requirements and test vectors to their exact separators; reworded the duplicate-`id` edge case as a caller precondition instead of a MUST NOT; externalized the five hardcoded strings as localization keys; made test vector 008 a concrete fetch/XHR stub; reordered Platform Notes and filled in WinUI padding, border, and token mappings; bolded Design Decision labels and added one for the fixed heading level; replaced the Compliance table's non-catalog check citations with real cookbook compliance checks and sourced statuses; and switched `created`/`modified` to bare ISO dates. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
