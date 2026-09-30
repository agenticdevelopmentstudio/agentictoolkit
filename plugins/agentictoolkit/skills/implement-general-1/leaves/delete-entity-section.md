<!-- leaf: implement-general-1/delete-entity-section · source: delete-entity-section.md -->

**Rules** (cite as `implement-general-1/delete-entity-section#<slug>`):

- `collapse-by-default` MUST
- `accent-red-only-when-disclosed` MUST
- `keep-warning-glyph-gold` MUST
- `open-warn-phase-first` MUST
- `select-article-from-first-letter` MUST
- `advance-to-confirm-on-yes` MUST
- `require-exact-identifier` MUST
- `reject-empty-confirm-value` MUST
- `call-onconfirm-once-enabled` MUST
- `lock-dialog-while-busy` MUST
- `disable-actions-while-busy` MUST
- `surface-error-inline` MUST
- `reset-on-cancel-or-success` MUST
- `avoid-permanence-claims-when-reversible` MUST
- `swap-trigger-glyph-when-reversible` MUST

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
   (`confirmValue`, the entity's unique identifier) into an input; the "Permanently Delete" button enables
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

The frontmatter `ingredients` field points to `agenticdevelopertoolkit://recipes/…`
domains rather than `ingredients/…` domains because Disclosure, Button, and
Dialog are each documented as their own recipe in that toolkit, not as bare
ingredients — this recipe composes those recipes, it doesn't restate them as
ingredients of its own.

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
- **select-article-from-first-letter**: The warn-phase body MUST prefix the
  lowercased `entityNoun` with "an" when `entityNoun`'s first character (after
  trimming) is a vowel (case-insensitive `/^[aeiou]/i`), and "a" otherwise —
  e.g. "an ecosystem", "a bucket". This is a literal first-letter check, not a
  phonetic one, so it also reads "an user" for `entityNoun="User"` and "a hour"
  for `entityNoun="Hour"`.
- **advance-to-confirm-on-yes**: Choosing "Yes" on the acknowledge phase MUST
  advance the dialog to the type-to-confirm phase and MUST NOT delete yet.
- **require-exact-identifier**: The final delete button MUST remain disabled
  until the typed text exactly equals `confirmValue` — case-sensitive and untrimmed.
- **reject-empty-confirm-value**: When `confirmValue` is empty the final delete
  button MUST stay disabled even with an empty input, so a blank identifier never
  arms the delete.
- **call-onconfirm-once-enabled**: Activating the enabled confirm button MUST
  call `onConfirm` exactly once and MUST show a busy state built from
  `actionVerb.gerund` + "…" (e.g. "Deleting…", or "Archiving…" when
  `actionVerb.reversible` is `true`) while it is pending.
- **lock-dialog-while-busy**: While `onConfirm` is pending, the section MUST NOT
  allow the dialog to be dismissed (no close button, no Escape/outside close) until
  it settles.
- **disable-actions-while-busy**: While `onConfirm` is pending, the confirm-phase
  CTA and the Cancel button MUST both be disabled, so a double-click on the CTA
  cannot fire a second `onConfirm` call and Cancel cannot abandon an in-flight
  delete.
- **surface-error-inline**: If `onConfirm` rejects, the section MUST show the
  error message inside the dialog, clear the busy state, and keep the dialog open so
  the user can retry. When the rejection is not an `Error` instance (so no
  `.message` is available), the section MUST fall back to "Failed to {imperative}
  {noun}." built from `actionVerb.imperative` and `entityNoun`, both lowercased —
  e.g. "Failed to archive organization."
- **reset-on-cancel-or-success**: Cancelling, or a successful delete, MUST reset
  the dialog back to a closed, empty, warn-phase state. This reset is scoped to
  the dialog only — it MUST NOT collapse the `Disclosure`, whose `disclosed` state
  is independent of the dialog's outcome. A stale error from a previous failed
  attempt MUST persist while the user edits the confirm input; only the next
  `onConfirm` attempt clears it, per surface-error-inline.
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
│  [ 🗑 Delete {entityNoun} ]      ← destructive-ghost                     │
└─────────────────────────────────────────────────────────────────────┘

Dialog · phase "warn"                    Dialog · phase "confirm"
┌───────────────────────────┐            ┌────────────────────────────────┐
│ Delete {entityNoun}?      │            │ Permanently delete this {entityNoun}│
│ …deletes all data,        │            │ Enter "{confirmValue}" below.  │
│ including {childEntities}.│    Yes →   │ [ type the exact identifier…  ] │
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
│  [ 📦 Archive {entityNoun} ]  ← destructive-ghost; Archive glyph, not 🗑│
└─────────────────────────────────────────────────────────────────────┘

Dialog · phase "warn"                    Dialog · phase "confirm"
┌───────────────────────────┐            ┌────────────────────────────────┐
│ Archive {entityNoun}?     │            │ Archive this {entityNoun}      │
│ …affects {childEntities}. │    Yes →   │ Enter "{confirmValue}" below.  │
│ Do you wish to proceed?   │            │ [ type the exact identifier…  ] │
│        [Cancel] [Yes]     │            │   [Cancel] [Archive {entityNoun}]│
└───────────────────────────┘            └────────────────────────────────┘
                                          Archive {entityNoun}: disabled until
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

