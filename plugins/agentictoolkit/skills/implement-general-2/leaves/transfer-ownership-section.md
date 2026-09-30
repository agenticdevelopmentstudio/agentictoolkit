<!-- leaf: implement-general-2/transfer-ownership-section · source: transfer-ownership-section.md -->

**Rules** (cite as `implement-general-2/transfer-ownership-section#<slug>`):

- `collapsed-by-default` MUST
- `root-section-labeled` MUST
- `disclosure-labeled-transfer-ownership` MUST
- `describes-transfer-effect` MUST
- `trigger-button-labeled-distinctly` MUST
- `renders-nested-targets-as-submenu` MUST
- `renders-leaf-targets-as-items` MUST
- `disables-current-target` MUST
- `current-target-not-selectable` MUST
- `selecting-target-opens-dialog-and-runs-preview` MUST
- `preview-populates-dialog` MUST
- `preview-error-shown-inline` MUST
- `stale-preview-ignored` MUST
- `dialog-title-names-destination` MUST
- `dialog-shows-checking-state` MUST
- `shows-revoked-token-count` MUST
- `lists-revoked-principals` MUST
- `shows-no-access-revoked` MUST
- `confirm-gate-hidden-until-preview` MUST
- `confirm-target-is-trimmed-label` MUST
- `confirm-requires-nonempty-target` MUST
- `confirm-match-ignores-edge-whitespace` MUST
- `transfer-button-disabled-until-armed` MUST
- `transfer-button-not-destructive-styled` MUST
- `transfer-invokes-onconfirm-once` MUST
- `transfer-label-reflects-progress` MUST
- `dialog-locks-during-transfer` MUST
- `preview-does-not-lock-dialog` MUST
- `transfer-error-shown-inline-dialog-stays-open` MUST
- `transfer-success-resets-state` MUST
- `cancel-resets-and-closes` MUST
- `reset-orphans-inflight-preview` MUST
- `switching-target-clears-typed-and-error` MUST
- `wider-dialog-for-long-identifiers` MUST

# TransferOwnershipSection

## Overview

`TransferOwnershipSection` (`packages/web/packages/adh-ui/src/blocks/transfer-ownership-section.tsx`)
is a settings-pane section that moves an owned object to a different destination workspace, or a
nested Product beneath one. It renders as a `Disclosure` labeled "Transfer Ownership" that is
collapsed by default; opening it reveals a short explanation of what a transfer does and a dropdown
of candidate destinations (`targets`), where a destination with `children` renders as a nested
submenu (a workspace's own Products). Picking a non-current
destination runs a caller-supplied server preflight (`onPreview`) and opens a confirmation dialog
that names every principal who will lose access before the transfer runs.
The final Transfer action stays disabled until the user retypes the object's own `entityLabel`
(edge whitespace forgiven, everything else exact). The component's own
doc comment names it a sibling of `DeleteEntitySection`, whose confirm vocabulary and type-to-
confirm gate this follows.

## Behavioral Requirements

- **collapsed-by-default**: The section MUST render its `Disclosure` collapsed on initial render
  (`useState(false)` for `disclosed`).
- **root-section-labeled**: The component MUST render a `<section>` with
  `aria-label="Transfer Ownership"`.
- **disclosure-labeled-transfer-ownership**: The `Disclosure` trigger MUST show an `ArrowRightLeft`
  icon followed by the text "Transfer Ownership".
- **describes-transfer-effect**: When the disclosure is open, the section MUST show text stating
  that the object's address changes, everything beneath it is re-addressed with it, and access
  granted in the current workspace does not follow.
- **trigger-button-labeled-distinctly**: The dropdown's trigger button MUST show "Transfer
  {entityNoun}" — a label distinct from the Disclosure's "Transfer Ownership" trigger, so the two
  buttons do not share one accessible name.
- **renders-nested-targets-as-submenu**: A `TransferTarget` whose `children` array is non-empty
  MUST render as a `DropdownMenuSub` labeled with the target's `name`, and its `children` MUST
  render recursively inside the corresponding `DropdownMenuSubContent`.
- **renders-leaf-targets-as-items**: A `TransferTarget` with no `children` MUST render as a single
  `DropdownMenuItem` labeled with the target's `name`.
- **disables-current-target**: A `TransferTarget` that matches `currentTarget` (by `slug`, and by
  `kind` when both sides define one) MUST render its `DropdownMenuItem` disabled and MUST append
  " (current)" to its label.
- **current-target-not-selectable**: Activating an item rendered as "(current)" MUST NOT invoke
  `choose` — its `onClick` is `undefined`.
- **selecting-target-opens-dialog-and-runs-preview**: Activating a non-current, non-submenu target
  MUST close the dropdown menu, set it as `chosen` (which opens the confirmation dialog), clear any
  prior `preview`/`typed`/`error`, and invoke `onPreview(target)`.
- **preview-populates-dialog**: When `onPreview` resolves for the current selection, its
  `TransferPreviewResult` MUST populate the confirmation dialog.
- **preview-error-shown-inline**: When `onPreview` rejects, the section MUST show an inline error —
  the rejection's `message` when it is an `Error`, otherwise "Could not check this transfer." — and
  MUST leave the dialog open.
- **stale-preview-ignored**: A settled `onPreview` promise whose sequence number no longer matches
  the current selection (because the user cancelled or chose a different target while it was
  pending) MUST NOT update `preview`, `error`, or `busy`.
- **dialog-title-names-destination**: The dialog title MUST read "Transfer this {entityNoun} to
  {chosen.name}?".
- **dialog-shows-checking-state**: While a request is pending and no `preview` has arrived yet, the
  dialog body MUST show "Checking…".
- **shows-revoked-token-count**: When the resolved `preview.tokens` is greater than zero, the
  dialog MUST show the count of API tokens that will be revoked, using the singular "token" only
  when the count is exactly 1.
- **lists-revoked-principals**: When `preview.revoking` is non-empty, the dialog MUST list each
  entry's `name`, followed by its `via` alone when `kind` is `"user"`, or `"{kind}, {via}"`
  otherwise.
- **shows-no-access-revoked**: When `preview.revoking` is empty, the dialog MUST show "No access is
  revoked.".
- **confirm-gate-hidden-until-preview**: The type-to-confirm label and input MUST NOT render until
  `preview` is populated.
- **confirm-target-is-trimmed-label**: The value the user must type to arm the Transfer button MUST
  be `entityLabel` with leading and trailing whitespace removed.
- **confirm-requires-nonempty-target**: The Transfer button MUST stay disabled whenever the trimmed
  `entityLabel` is empty, regardless of what is typed.
- **confirm-match-ignores-edge-whitespace**: The typed value MUST arm the Transfer button only when
  its own leading/trailing whitespace, once trimmed, equals the trimmed `entityLabel` exactly — an
  interior or case difference MUST NOT match.
- **transfer-button-disabled-until-armed**: The Transfer button MUST stay disabled while a request
  is in flight (`busy`), while no `preview` has arrived, or while the typed value does not confirm.
- **transfer-button-not-destructive-styled**: The Transfer button MUST use the `"warning"` visual
  variant rather than a destructive one.
- **transfer-invokes-onconfirm-once**: Activating the enabled Transfer button MUST call
  `onConfirm(chosen)` exactly once for that confirmation.
- **transfer-label-reflects-progress**: While the confirmed transfer is pending, the Transfer
  button MUST read "Transferring…"; otherwise it MUST read "Transfer".
- **dialog-locks-during-transfer**: While the confirmed transfer (`onConfirm`) is pending, the
  dialog's close control MUST be hidden and the Cancel button MUST be disabled.
- **preview-does-not-lock-dialog**: While only the preflight (`onPreview`) is pending, the dialog's
  close control MUST remain shown, the Cancel button MUST remain enabled, and dismissing the dialog
  (Escape, outside click, close, or Cancel) MUST reset it.
- **transfer-error-shown-inline-dialog-stays-open**: When `onConfirm` rejects, the section MUST
  show an inline error — the rejection's `message` when it is an `Error`, otherwise "Failed to
  transfer {noun}." — clear the busy state, and MUST NOT close the dialog.
- **transfer-success-resets-state**: When `onConfirm` resolves, the section MUST reset `chosen`,
  `preview`, `typed`, `busy`, and `error`, which closes the dialog.
- **cancel-resets-and-closes**: Activating Cancel, or otherwise closing the dialog while not
  `confirming`, MUST reset the same state and close the dialog.
- **reset-orphans-inflight-preview**: Resetting MUST invalidate any in-flight preflight so its
  eventual resolution can no longer change state (`previewSeq` increment).
- **switching-target-clears-typed-and-error**: `choose` MUST clear any previously typed confirmation
  text and inline error before starting the new target's preflight, regardless of what was already
  in flight or on screen for the prior target. This is a property of `choose` itself, verified at
  the unit level: the open confirmation `Dialog` currently covers the destination dropdown, so a
  second `choose` call cannot be reached through pointer interaction while the first target's
  dialog is still open.
- **wider-dialog-for-long-identifiers**: The dialog content MUST use the wider `max-w-xl` layout
  rather than the platform's default dialog width.

## Appearance

- **Corner radius**: Not applicable at this component's own level — no `border-radius`/rounded
  utility class is set on any element this file renders directly; corner treatment belongs to the
  composed `Disclosure`/`Dialog`/`Button`/`Input` components, each out of scope for this recipe.
- **Padding**: The disclosed body is a `flex flex-col gap-3` column; the dialog's
  status/preview area is a `flex flex-col gap-2 text-sm` column; the confirm-gate group
  is `flex flex-col gap-2`. No independent padding value is set beyond these gaps —
  interior padding is the composed `Dialog`/`Input`/`Button` components' own.
- **Font**: Body copy and dialog copy use `text-sm`; the object's identifier
  and the value the user must type back are rendered `font-mono`.
- **Background**: Not set at this component's own level — inherited from the `Disclosure` and
  `Dialog` containers, which are out of scope for this recipe.
- **Foreground/Text**: `text-apt-text-muted` for descriptive copy, the "these will lose access"
  heading, and the parenthetical `via`/`kind` text;
  `text-apt-text` for the object's identifier and each revoked-principal's name; `text-apt-gold` for the token-revocation warning icon.
- **Border**: Not applicable — no border is set on any element this file renders directly.
- **Shadow**: Not applicable — no shadow is set on any element this file renders directly.
- **Min/Max size**: `DialogContent` is `max-w-xl`, wider than the platform's default `max-w-md`
  dialog width, because a mid-length identifier wraps confusingly inside itself at the default
  width.

