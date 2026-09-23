---
id: 96bc198e-c726-476a-bc4a-ddc1d5c0c2f8
title: DeleteEntitySection
domain: agentictoolkit://recipes/delete-entity-section
type: recipe
version: 1.2.0
status: review
language: en
created: '2026-07-03'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The Danger-zone disclosure for an entity's settings pane — neutral until disclosed, red once open, and a two-phase (acknowledge then type-to-confirm) delete."
platforms:
- typescript
- web
tags:
- forms
- destructive
- confirmation
- disclosure
- settings
ingredients:
- agenticdevelopertoolkit://recipes/disclosure
- agenticdevelopertoolkit://recipes/button
- agenticdevelopertoolkit://recipes/dialog
depends-on: []
related:
- agenticdevelopertoolkit://recipes/field-group
- agentictoolkit://recipes/focused-topic-detail
references: []
approved-by: ""
approved-date: ""
---

# DeleteEntitySection

## Overview

The shared `DeleteEntitySection` in `@agentic-toolkit/adh-ui` — the "Danger Zone" that closes
an entity's own settings pane (every focused-topic-detail route reuses it). It is a
`Disclosure` that is **collapsed and neutral by default**, so a settings pane does
not shout its most destructive action; the `apt-red` accent appears **only once the
section is disclosed**, keeping least-astonishment for the closed state.

Once open, the section reveals a description of what the delete cascades through and
a destructive Delete button. Deleting is gated behind a **two-phase confirm dialog**:

1. **Acknowledge** — "Delete {entity}?" states that the delete removes all the
   entity's data (including the named `childEntities`) and asks "Do you wish to
   proceed?" (Cancel / Yes).
2. **Type-to-confirm** — the user must type the entity's exact identifier
   (`confirmValue`, the rdid) into an input; the "Permanently Delete" button enables
   **only** on an exact, case-sensitive, untrimmed match before the delete runs.

While the delete is in flight the dialog cannot be dismissed, and a thrown error
surfaces inline without closing the dialog. It composes `Disclosure`, `Button`, and
`Dialog` plus the shared `Input`/`Label` primitives.

## Ingredients

| Name | Domain | Role | Required | Configuration |
|---|---|---|---|---|
| Disclosure | agenticdevelopertoolkit://recipes/disclosure | The collapsed-by-default Danger-zone container; controlled `open`/`onOpenChange` so the red accent tracks the open state | yes | `open={disclosed}`; red `className` + `text-apt-red` title only when disclosed; `TriangleAlert` glyph in the title |
| Button | agenticdevelopertoolkit://recipes/button | The disclosed Delete trigger (`destructive-ghost`), the dialog's Cancel/Yes/Permanently-Delete actions | yes | `variant` per action: `destructive-ghost` for Delete + Yes, `ghost` for Cancel, `destructive` for the final Permanently Delete |
| Dialog | agenticdevelopertoolkit://recipes/dialog | The modal that carries the two-phase confirm (warn → type-to-confirm) | yes | `open`/`onOpenChange`; `DialogContent showClose={!busy}`; `DialogHeader`/`Title`/`Description`/`Footer` |

Composed shared primitives without their own recipe domains: `Input` (the
type-to-confirm field, `autoFocus`, `autoComplete="off"`, `spellCheck={false}`),
`Label` (`sr-only` label for that input), and the `lucide-react` `Trash2` /
`TriangleAlert` glyphs.

## Integration Requirements

- **collapse-by-default**: The section MUST render its `Disclosure` collapsed
  on first render, so the destructive affordance is opt-in rather than always
  present.
- **accent-red-only-when-disclosed**: The section MUST apply the `apt-red`
  accent (red title text and red border/background) only while the disclosure is
  open, and MUST stay neutral while it is closed.
- **keep-warning-glyph-gold**: The section MUST render the warning
  (`TriangleAlert`) glyph in `apt-gold` in both the closed and open states.
- **open-warn-phase-first**: Activating the Delete button MUST open the confirm
  dialog on the acknowledge ("warn") phase, describing the cascade through
  `childEntities` and asking whether to proceed.
- **advance-to-confirm-on-yes**: Choosing "Yes" on the acknowledge phase MUST
  advance the dialog to the type-to-confirm phase and MUST NOT delete yet.
- **require-exact-identifier**: The final delete button MUST remain disabled
  until the typed text exactly equals `confirmValue` — case-sensitive and untrimmed.
- **reject-empty-confirm-value**: When `confirmValue` is empty the final delete
  button MUST stay disabled even with an empty input, so a blank identifier never
  arms the delete.
- **call-onconfirm-once-enabled**: Activating the enabled "Permanently Delete"
  button MUST call `onConfirm` exactly once and MUST show a busy ("Deleting…") state
  while it is pending.
- **lock-dialog-while-busy**: While `onConfirm` is pending, the section MUST NOT
  allow the dialog to be dismissed (no close button, no Escape/outside close) until
  it settles.
- **surface-error-inline**: If `onConfirm` rejects, the section MUST show the
  error message inside the dialog, clear the busy state, and keep the dialog open so
  the user can retry.
- **reset-on-cancel-or-success**: Cancelling, or a successful delete, MUST reset
  the dialog back to a closed, empty, warn-phase state.
- **avoid-permanence-claims-when-reversible**: When `actionVerb.reversible` is
  `true`, the blurb, the warn phase, and the confirm phase MUST NOT render
  "Permanently", "cannot be undone", or "deletion" anywhere — every phrase that
  otherwise asserts permanence or data destruction swaps to non-destructive wording
  built from `actionVerb.imperative`/`gerund` instead (e.g. "Archive this
  organization. This can be undone later."). This holds even when the caller passes
  no `description` override — the built-in fallback blurb must itself be
  reversible-safe, not merely the caller-supplied copy.
- **swap-trigger-glyph-when-reversible**: When `actionVerb.reversible` is
  `true`, the disclosed trigger button MUST render the `Archive` glyph instead of
  `Trash2`. The Danger Zone's red palette (border, tint, title accent) does NOT
  change with reversibility — only the glyph and the copy do (see
  accent-red-only-when-disclosed, which is unconditional).

## Layout

```
┌ Disclosure — closed (neutral) ─────────────────────────────────────┐
│ ▸  ⚠ Danger Zone                                                    │  ⚠ = apt-gold glyph
└─────────────────────────────────────────────────────────────────────┘

┌ Disclosure — open (apt-red border + tint) ─────────────────────────┐
│ ▾  ⚠ Danger Zone            ← title text turns apt-red when open     │
│                                                                     │
│  Permanently delete this {noun} and all of its data. Cannot be undone.
│  [ 🗑 Delete {Entity} ]      ← destructive-ghost                     │
└─────────────────────────────────────────────────────────────────────┘

Dialog · phase "warn"                    Dialog · phase "confirm"
┌───────────────────────────┐            ┌────────────────────────────────┐
│ Delete {Entity}?          │            │ Permanently delete this {Entity}│
│ …deletes all data,        │            │ Enter "{confirmValue}" below.  │
│ including {childEntities}.│    Yes →   │ [ type the exact rdid…       ] │
│ Do you wish to proceed?   │            │ (inline error, if any)         │
│        [Cancel] [Yes]     │            │   [Cancel] [Permanently Delete]│
└───────────────────────────┘            └────────────────────────────────┘
                                          Permanently Delete: disabled until
                                          typed === confirmValue (exact); shows
                                          "Deleting…" while busy.
```

The two blocks above are the **default** copy (no `actionVerb`, or `reversible: false`).
Passing `actionVerb={{ imperative: "Archive", gerund: "Archiving", reversible: true }}`
keeps the same red palette and the same two-phase ceremony — only the trigger glyph and
every permanence-asserting phrase change:

```
┌ Disclosure — open (apt-red border + tint) ─────────────────────────┐
│ ▾  ⚠ Danger Zone            ← still turns apt-red when open          │
│                                                                     │
│  Archive this {noun}. This can be undone later.
│  [ 📦 Archive {Entity} ]     ← destructive-ghost; Archive glyph, not 🗑│
└─────────────────────────────────────────────────────────────────────┘

Dialog · phase "warn"                    Dialog · phase "confirm"
┌───────────────────────────┐            ┌────────────────────────────────┐
│ Archive {Entity}?         │            │ Archive this {Entity}          │
│ …affects {childEntities}. │    Yes →   │ Enter "{confirmValue}" below.  │
│ Do you wish to proceed?   │            │ [ type the exact rdid…       ] │
│        [Cancel] [Yes]     │            │   [Cancel] [Archive {Entity}]  │
└───────────────────────────┘            └────────────────────────────────┘
                                          Archive {Entity}: disabled until
                                          typed === confirmValue (exact); shows
                                          "Archiving…" while busy. No "Permanently" /
                                          "cannot be undone" / "deletion" anywhere,
                                          including the collapsed-section blurb above.
```

- Section root: `section` with `aria-label="Danger Zone"`.
- Disclosure: neutral when closed; `border-apt-red/40 bg-apt-red/5` and a
  `text-apt-red` title when open; the `TriangleAlert` glyph is `text-apt-gold`
  throughout.
- Dialog description highlights `confirmValue` in `font-mono text-apt-text`; the
  input placeholder is `confirmValue`; inline error text is `text-apt-red`.
- No raw hex; no `!important`; every color is an `apt-*` token.

## Shared State

| State | Source | Consumer | Direction | Mechanism |
|---|---|---|---|---|
| `disclosed` (open/closed) | DeleteEntitySection | Disclosure open + red-accent styling | Down | `useState`, controlled `open`/`onOpenChange` |
| `open` (dialog) | DeleteEntitySection | Dialog `open`/`onOpenChange` | Down | `useState` |
| `phase` (`warn`/`confirm`) | DeleteEntitySection | Which dialog body renders | Internal | `useState` |
| `typed` | Input `onChange` | `confirmEnabled` gate | Up then down | `useState`; compared exactly to `confirmValue` |
| `busy` | `handleConfirm` | Button label + dialog lock + close suppression | Down | `useState` |
| `error` | rejected `onConfirm` | Inline error line + `aria-invalid` on the input | Up then down | `useState<string \| null>` |
| delete effect | DeleteEntitySection | Caller `onConfirm` (performs delete + navigation) | Up | `async` callback prop |

## Integration Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | collapse-by-default, accent-red-only-when-disclosed, keep-warning-glyph-gold | Initial render | Disclosure closed, neutral (no red); the ⚠ glyph is gold |
| T2 | accent-red-only-when-disclosed | Open the disclosure | Red border/tint appears and the title text turns red; the ⚠ glyph stays gold |
| T3 | open-warn-phase-first | Click "Delete {Entity}" | Dialog opens on the warn phase naming the `childEntities` cascade and asking to proceed |
| T4 | advance-to-confirm-on-yes | Click "Yes" on the warn phase | Dialog advances to type-to-confirm; `onConfirm` not yet called |
| T5 | require-exact-identifier | Type a near-match (wrong case / trailing space) | "Permanently Delete" stays disabled |
| T6 | require-exact-identifier, call-onconfirm-once-enabled | Type the exact `confirmValue`, click Permanently Delete | Button enables; `onConfirm` called once; label shows "Deleting…" |
| T7 | reject-empty-confirm-value | `confirmValue=""`, empty input, reach confirm phase | "Permanently Delete" stays disabled |
| T8 | lock-dialog-while-busy | While `onConfirm` pending, try Escape / close / outside | Dialog stays open; no close affordance is shown |
| T9 | surface-error-inline | `onConfirm` rejects | Error message shows inside the dialog; busy clears; dialog stays open for retry |
| T10 | reset-on-cancel-or-success | Cancel, or resolve `onConfirm` | Dialog closes and resets to empty, warn-phase state |
| T11 | avoid-permanence-claims-when-reversible | `actionVerb={{ imperative: "Archive", gerund: "Archiving", reversible: true }}` with a caller `description`; open, click Yes | Blurb, warn body, and confirm-phase copy all read "Archive"/"Archiving"; no "delete", "permanently", or "cannot be undone" anywhere in the flow |
| T12 | avoid-permanence-claims-when-reversible | Same reversible `actionVerb`, no `description` override | The built-in fallback blurb itself reads "Archive this organization. This can be undone later." — no "permanently" or "cannot be undone"; confirm phase shows "Type {confirmValue} to confirm" (no "deletion") |
| T13 | swap-trigger-glyph-when-reversible | Reversible `actionVerb`; open the disclosure | Trigger button renders the `Archive` glyph (`svg.lucide-archive`); no `Trash2` glyph present |
| T14 | swap-trigger-glyph-when-reversible | Default (no `actionVerb`); open the disclosure | Trigger button renders the `Trash2` glyph (`svg.lucide-trash-2`); no `Archive` glyph present |
| T15 | call-onconfirm-once-enabled | Reversible `actionVerb`; reach confirm phase, type the exact `confirmValue`, click the CTA while `onConfirm` is pending | Busy label reads "Archiving…" (from `actionVerb.gerund`), never "Deleting…" |
| T16 | surface-error-inline | Reversible `actionVerb`; `onConfirm` rejects a non-`Error` value | Inline error falls back to "Failed to archive organization." (lowercase `actionVerb.imperative`), since `e.message` never runs for a non-`Error` rejection |

## Edge Cases

- Empty `confirmValue` guard: because the enable check requires `confirmValue.length
  > 0`, an empty rdid never matches the initially-empty input and never arms the
  delete.
- Match is exact and untrimmed: leading/trailing whitespace or a case difference in
  the typed value keeps the delete disabled — the user must type the identifier
  verbatim.
- Mid-delete dismissal: `onOpenChange` ignores close requests while `busy`, and
  `DialogContent` hides its close (`showClose={!busy}`), so the user cannot abandon a
  running delete.
- Failure path: a rejected `onConfirm` sets an inline error, clears `busy`, and
  leaves the typed value and open dialog intact so the user can retry without
  re-typing from the warn phase.
- Success path: `onConfirm` typically navigates the parent away; the section still
  resets defensively so a re-mounted pane starts closed and empty.
- `entityNoun` article: the warn copy picks "an" vs "a" from the noun's first letter
  (e.g. "an Ecosystem", "a Bucket").
- Optional `description` overrides only the disclosed-section blurb; the dialog copy
  is derived from `entityNoun`/`childEntities`/`confirmValue`.

## Platform Notes

- **SwiftUI**: Build the collapsed Danger Zone from a `DisclosureGroup(isExpanded:)`
  bound to a `@State` flag equivalent to `disclosed`; recolor only the group's
  label `Text` with `.foregroundStyle(.red)` while `isExpanded` is `true` (the
  `Image(systemName: "exclamationmark.triangle")` warning glyph keeps a fixed gold
  `Color` in both states — see accent-red-only-when-disclosed and
  keep-warning-glyph-gold). Model the two dialog phases as an enum driving
  `.alert(item:)`/`.sheet(item:)` rather than one dialog whose body swaps: the warn
  phase is a plain `.alert` with Cancel/Yes actions, the confirm phase is a
  `.sheet` containing a `TextField` bound to `@State var typed`, with the
  destructive `Button`'s `.disabled(typed != confirmValue || confirmValue.isEmpty)`
  computed as the exact, untrimmed comparison the source uses. Set
  `.interactiveDismissDisabled(busy)` on the confirm sheet to reproduce
  lock-dialog-while-busy, and swap `Image(systemName: "trash")` for
  `"archivebox"` when `actionVerb.reversible` is `true`.
- **Compose**: Use a `Card` with a header `Row` that toggles a
  `rememberSaveable { mutableStateOf(false) }` expanded flag, wrapping the body in
  `AnimatedVisibility`; recolor only the header `Text` with
  `MaterialTheme.colorScheme.error` while expanded, keeping the
  `Icons.Filled.Warning` `Icon` tinted with a fixed gold color in both states.
  Drive the two-phase confirm with two `AlertDialog`s selected by a `phase`
  enum held in `remember` (or a `ViewModel`); the second `AlertDialog`'s
  `confirmButton` sets `enabled = typed.isNotEmpty() && typed == confirmValue`,
  matching the source's exact, untrimmed comparison. While `busy` is `true`, pass
  `onDismissRequest = {}` and omit the dismiss button on the second dialog to
  block dismissal, and swap `Icons.Filled.Delete` for `Icons.Filled.Archive` when
  `actionVerb.reversible` is `true`.
- **React/Web**: `packages/web/packages/adh-ui/src/blocks/delete-entity-section.tsx`
  (`"use client"`), exported via `@agentic-toolkit/adh-ui/blocks/delete-entity-section`.
  Composes `Disclosure`, `Button`, `Dialog` (+ `DialogHeader`/`Title`/`Description`/
  `Footer`), `Input`, and `Label`, with the `Trash2`/`TriangleAlert`/`Archive`
  glyphs from `lucide-react`. Props: `entityNoun`, `confirmValue`, `childEntities`,
  `onConfirm: () => Promise<void>`, optional `description`, and optional
  `actionVerb: { imperative, gerund, reversible? }` (default `{ imperative:
  "Delete", gerund: "Deleting", reversible: false }`, which reproduces today's
  wording byte-for-byte). Demo lives in the `ui-showcase` Topic
  `delete-entity-section` (regenerate `sources.generated.ts` via
  `gen-sources.py` after source changes); verify responsively via Playwright at
  375 / 768 / 1440. Shared across every focused-topic-detail settings route
  (`agentictoolkit://recipes/focused-topic-detail`), usually as the final
  group in a settings pane below the `FieldGroup`s.
- **AppKit/UIKit**: On macOS, build the disclosure from an `NSDisclosureButton`
  (or a custom bezel-style `NSButton`) toggling a subview's `isHidden`,
  recoloring only the title `NSTextField` with `NSColor.systemRed` while
  expanded; chain two `NSAlert`s for the two phases, the second carrying an
  accessory `NSTextField` whose delegate (`controlTextDidChange`) enables the
  alert's default `NSButton` only on an exact `String` equality against
  `confirmValue`. On iOS, use a collapsible `UIStackView` section and two
  chained `UIAlertController` (`.alert`) instances, the second built with
  `addTextField` and a `.textDidChangeNotification` observer that gates the
  confirm `UIAlertAction`'s `isEnabled` the same way. Block dismissal while busy
  by setting `isModalInPresentation = true` (iOS) or ignoring the sheet's close
  control (macOS) until the async delete settles, and swap the trash
  `UIImage`/`NSImage` (`systemName: "trash"`) for `"archivebox"` when
  `actionVerb.reversible` is `true`.
- **WinUI 3**: Use an `Expander` (`IsExpanded="{x:Bind Disclosed, Mode=TwoWay}"`)
  for the Danger Zone, collapsed by default. Bind the `Header` `TextBlock`'s
  `Foreground` to a `SolidColorBrush` resource selected by a
  `VisualStateManager` state (`Disclosed` / `Collapsed`) so the red accent brush
  applies only while expanded — never a converter on the warning icon, whose
  `FontIcon.Foreground` stays a fixed gold brush in both states (see
  accent-red-only-when-disclosed and keep-warning-glyph-gold). Trigger a
  `ContentDialog` for the acknowledge phase (`PrimaryButtonText="Yes"`,
  `CloseButtonText="Cancel"`), then a second `ContentDialog` with a `TextBox`
  whose `TextChanged` handler sets `IsPrimaryButtonEnabled` from
  `string.Equals(textBox.Text, confirmValue, StringComparison.Ordinal) &&
  confirmValue.Length > 0` (reproducing require-exact-identifier and
  reject-empty-confirm-value). In the `PrimaryButtonClick` handler, call
  `args.GetDeferral()` before awaiting the delete, set
  `IsPrimaryButtonEnabled = false` and swap the button content for a
  `ProgressRing` plus "Deleting…" text while the call is pending, and call
  `deferral.Complete()` only once the awaited call settles — a `ContentDialog`
  otherwise stays light-dismissible during an async `PrimaryButtonClick`, so the
  deferral is what reproduces lock-dialog-while-busy. On failure, bind a
  `TextBlock` to the caught message and make it visible instead of completing
  the deferral, leaving the dialog open for retry (surface-error-inline). Swap
  the `FontIcon` glyph from the Segoe Fluent Icons trash glyph (`\uE74D`) to the
  archive glyph (`\uE7B8`) when `actionVerb.reversible` is `true`.

## Design Decisions

**Decision**: Collapse the section and stay neutral until disclosed; show
`apt-red` only when open.
**Rationale**: Least-astonishment — a closed settings pane should not shout its
most destructive control; the red accent is earned by the user opening it.
**Approved**: pending

**Decision**: Two phases — acknowledge, then type-to-confirm.
**Rationale**: The first phase communicates the blast radius (the
`childEntities` cascade); the second forces deliberate intent, so an accidental
double-click can never delete.
**Approved**: pending

**Decision**: Require an exact, case-sensitive, untrimmed match of the rdid.
**Rationale**: The identifier is unique and unambiguous; a fuzzy match would
weaken the guard, and guarding the empty-`confirmValue` case prevents arming
with no input at all.
**Approved**: pending

**Decision**: Lock the dialog while the delete is in flight and surface
failures inline.
**Rationale**: A destructive operation must not be abandoned half-way or fail
silently; keeping the dialog open on error lets the user retry without
re-typing.
**Approved**: pending

**Decision**: Keep the warning glyph `apt-gold` in both states.
**Rationale**: The glyph marks the zone as sensitive even while closed, without
recruiting the red destructive accent before the user commits.
**Approved**: pending

## Compliance

| Check | Status | Category |
|---|---|---|
| [recipe-formatting](agenticdevelopercookbook://compliance/artifact-formatting/recipe-formatting#recipe-formatting) | passed | Artifact Formatting |
| [no-raw-hex-or-important](agenticdevelopercookbook://compliance/project-guidelines/ui#no-raw-hex-or-important) | passed | Project Guidelines UI |
| [shared-components-only](agenticdevelopercookbook://compliance/project-guidelines/ui#shared-components-only) | passed | Project Guidelines UI |
| [destructive-double-gated](agenticdevelopercookbook://compliance/safety/destructive-actions#destructive-double-gated) | passed | Safety |
| [confirm-input-labeled](agenticdevelopercookbook://compliance/accessibility/forms#confirm-input-labeled) | passed | Accessibility |

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.2.0 | 2026-09-23 | Mike Fullerton | Migrated `domain` to `agentictoolkit://` and added `approved-by`/`approved-date`; set `status: review` (no unresolved gaps); renamed requirement identifiers to subject-only kebab-case (dropped the `must-` prefix) across Integration Requirements and Integration Test Vectors; filled in all five Platform Notes bullets (SwiftUI, Compose, React/Web, AppKit/UIKit, WinUI 3), including concrete `Expander`/`ContentDialog`/deferral guidance for WinUI 3; reformatted Design Decisions into Decision/Rationale/Approved lines and Compliance checks into linked `agenticdevelopercookbook://compliance/...` IDs. |
| 1.1.0 | 2026-08-04 | Mike Fullerton | Documented the `actionVerb.reversible` copy variant (Archive-style, non-destructive wording) across Integration Requirements, Layout, and Test Vectors T11-T16; fixed the stale `websites/shared/ui/...` source path in Platform Notes to `packages/web/packages/ui/...`. |
| 1.0.0 | 2026-07-03 | Mike Fullerton | Initial recipe for the Danger-zone DeleteEntitySection with two-phase confirm. |
