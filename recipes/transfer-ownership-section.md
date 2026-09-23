---
id: da441eaa-795d-4447-99b1-356186855921
title: TransferOwnershipSection
domain: agentictoolkit://recipes/transfer-ownership-section
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Disclosure-gated destination picker (with nested workspace submenus) that
  runs a server preflight and gates a type-to-confirm dialog before transferring ownership
  of an object.
platforms:
- typescript
- web
tags:
- confirmation
- disclosure
- settings
- transfer
depends-on: []
related:
- agentictoolkit://recipes/delete-entity-section
references: []
approved-by: ''
approved-date: ''
---

# TransferOwnershipSection

## Overview

`TransferOwnershipSection` (`packages/web/packages/adh-ui/src/blocks/transfer-ownership-section.tsx`)
is a settings-pane section that moves an owned object to a different destination workspace, or a
nested Product beneath one. It renders as a `Disclosure` labeled "Transfer Ownership" that is
collapsed by default; opening it reveals a short explanation of what a transfer does and a dropdown
of candidate destinations (`targets`), where a destination with `children` renders as a nested
submenu (a workspace's own Products) (lines 40-50, 229-250, 253-285). Picking a non-current
destination runs a caller-supplied server preflight (`onPreview`) and opens a confirmation dialog
that names every principal who will lose access before the transfer runs (lines 120-131, 194-214).
The final Transfer action stays disabled until the user retypes the object's own `entityLabel`
(edge whitespace forgiven, everything else exact) (lines 151-166, 339-376). The component's own
doc comment names it a sibling of `DeleteEntitySection`, whose confirm vocabulary and type-to-
confirm gate this follows (lines 127-130).

## Behavioral Requirements

- **collapsed-by-default**: The section MUST render its `Disclosure` collapsed on initial render
  (`useState(false)` for `disclosed`, line 141).
- **root-section-labeled**: The component MUST render a `<section>` with
  `aria-label="Transfer Ownership"` (line 253).
- **disclosure-labeled-transfer-ownership**: The `Disclosure` trigger MUST show an `ArrowRightLeft`
  icon followed by the text "Transfer Ownership" (lines 257-262).
- **describes-transfer-effect**: When the disclosure is open, the section MUST show text stating
  that the object's address changes, everything beneath it is re-addressed with it, and access
  granted in the current workspace does not follow (lines 264-268).
- **trigger-button-labeled-distinctly**: The dropdown's trigger button MUST show "Transfer
  {entityNoun}" — a label distinct from the Disclosure's "Transfer Ownership" trigger, so the two
  buttons do not share one accessible name (lines 271-278).
- **renders-nested-targets-as-submenu**: A `TransferTarget` whose `children` array is non-empty
  MUST render as a `DropdownMenuSub` labeled with the target's `name`, and its `children` MUST
  render recursively inside the corresponding `DropdownMenuSubContent` (lines 229-238).
- **renders-leaf-targets-as-items**: A `TransferTarget` with no `children` MUST render as a single
  `DropdownMenuItem` labeled with the target's `name` (lines 240-249).
- **disables-current-target**: A `TransferTarget` that matches `currentTarget` (by `slug`, and by
  `kind` when both sides define one) MUST render its `DropdownMenuItem` disabled and MUST append
  " (current)" to its label (lines 71-75, 240-249).
- **current-target-not-selectable**: Activating an item rendered as "(current)" MUST NOT invoke
  `choose` — its `onClick` is `undefined` (line 245).
- **selecting-target-opens-dialog-and-runs-preview**: Activating a non-current, non-submenu target
  MUST close the dropdown menu, set it as `chosen` (which opens the confirmation dialog), clear any
  prior `preview`/`typed`/`error`, and invoke `onPreview(target)` (lines 194-205, 287).
- **preview-populates-dialog**: When `onPreview` resolves for the current selection, its
  `TransferPreviewResult` MUST populate the confirmation dialog (lines 205-207).
- **preview-error-shown-inline**: When `onPreview` rejects, the section MUST show an inline error —
  the rejection's `message` when it is an `Error`, otherwise "Could not check this transfer." — and
  MUST leave the dialog open (lines 208-210, 333).
- **stale-preview-ignored**: A settled `onPreview` promise whose sequence number no longer matches
  the current selection (because the user cancelled or chose a different target while it was
  pending) MUST NOT update `preview`, `error`, or `busy` (lines 183, 194-213).
- **dialog-title-names-destination**: The dialog title MUST read "Transfer this {entityNoun} to
  {chosen.name}?" (lines 294-296).
- **dialog-shows-checking-state**: While a request is pending and no `preview` has arrived yet, the
  dialog body MUST show "Checking…" (line 304).
- **shows-revoked-token-count**: When the resolved `preview.tokens` is greater than zero, the
  dialog MUST show the count of API tokens that will be revoked, using the singular "token" only
  when the count is exactly 1 (lines 307-313).
- **lists-revoked-principals**: When `preview.revoking` is non-empty, the dialog MUST list each
  entry's `name`, followed by its `via` alone when `kind` is `"user"`, or `"{kind}, {via}"`
  otherwise (lines 314-327).
- **shows-no-access-revoked**: When `preview.revoking` is empty, the dialog MUST show "No access is
  revoked." (lines 328-330).
- **confirm-gate-hidden-until-preview**: The type-to-confirm label and input MUST NOT render until
  `preview` is populated (lines 336-359).
- **confirm-target-is-trimmed-label**: The value the user must type to arm the Transfer button MUST
  be `entityLabel` with leading and trailing whitespace removed (line 165).
- **confirm-requires-nonempty-target**: The Transfer button MUST stay disabled whenever the trimmed
  `entityLabel` is empty, regardless of what is typed (line 166).
- **confirm-match-ignores-edge-whitespace**: The typed value MUST arm the Transfer button only when
  its own leading/trailing whitespace, once trimmed, equals the trimmed `entityLabel` exactly — an
  interior or case difference MUST NOT match (line 166).
- **transfer-button-disabled-until-armed**: The Transfer button MUST stay disabled while a request
  is in flight (`busy`), while no `preview` has arrived, or while the typed value does not confirm
  (line 372).
- **transfer-button-not-destructive-styled**: The Transfer button MUST use the `"warning"` visual
  variant rather than a destructive one (lines 365-370).
- **transfer-invokes-onconfirm-once**: Activating the enabled Transfer button MUST call
  `onConfirm(chosen)` exactly once for that confirmation (lines 216-227).
- **transfer-label-reflects-progress**: While the confirmed transfer is pending, the Transfer
  button MUST read "Transferring…"; otherwise it MUST read "Transfer" (line 374).
- **dialog-locks-during-transfer**: While the confirmed transfer (`onConfirm`) is pending, the
  dialog's close control MUST be hidden and the Cancel button MUST be disabled (lines 175, 292,
  362).
- **preview-does-not-lock-dialog**: While only the preflight (`onPreview`) is pending, the dialog's
  close control MUST remain shown, the Cancel button MUST remain enabled, and dismissing the dialog
  (Escape, outside click, close, or Cancel) MUST reset it (lines 168-175, 287, 292, 362).
- **transfer-error-shown-inline-dialog-stays-open**: When `onConfirm` rejects, the section MUST
  show an inline error — the rejection's `message` when it is an `Error`, otherwise "Failed to
  transfer {noun}." — clear the busy state, and MUST NOT close the dialog (lines 223-226).
- **transfer-success-resets-state**: When `onConfirm` resolves, the section MUST reset `chosen`,
  `preview`, `typed`, `busy`, and `error`, which closes the dialog (lines 185-192, 220-222).
- **cancel-resets-and-closes**: Activating Cancel, or otherwise closing the dialog while not
  `confirming`, MUST reset the same state and close the dialog (lines 185-192, 287, 362).
- **reset-orphans-inflight-preview**: Resetting MUST invalidate any in-flight preflight so its
  eventual resolution can no longer change state (`previewSeq` increment, line 186).
- **switching-target-clears-typed-and-error**: Choosing a different destination while the dialog is
  already open MUST clear the previously typed confirmation text and any inline error (lines
  199-202).
- **wider-dialog-for-long-identifiers**: The dialog content MUST use the wider `max-w-xl` layout
  rather than the platform's default dialog width (lines 288-292).

## Appearance

- **Corner radius**: Not applicable at this component's own level — no `border-radius`/rounded
  utility class is set on any element this file renders directly; corner treatment belongs to the
  composed `Disclosure`/`Dialog`/`Button`/`Input` components, each out of scope for this recipe.
- **Padding**: The disclosed body is a `flex flex-col gap-3` column (line 264); the dialog's
  status/preview area is a `flex flex-col gap-2 text-sm` column (line 303); the confirm-gate group
  is `flex flex-col gap-2` (line 340). No independent padding value is set beyond these gaps —
  interior padding is the composed `Dialog`/`Input`/`Button` components' own.
- **Font**: Body copy and dialog copy use `text-sm` (lines 265, 303, 344); the object's identifier
  and the value the user must type back are rendered `font-mono` (lines 298, 345).
- **Background**: Not set at this component's own level — inherited from the `Disclosure` and
  `Dialog` containers, which are out of scope for this recipe.
- **Foreground/Text**: `text-apt-text-muted` for descriptive copy, the "these will lose access"
  heading, and the parenthetical `via`/`kind` text (lines 265, 308, 316, 321, 329, 344);
  `text-apt-text` for the object's identifier and each revoked-principal's name (lines 298, 319,
  345); `text-apt-gold` for the token-revocation warning icon (line 309).
- **Border**: Not applicable — no border is set on any element this file renders directly.
- **Shadow**: Not applicable — no shadow is set on any element this file renders directly.
- **Min/Max size**: `DialogContent` is `max-w-xl`, wider than the platform's default `max-w-md`
  dialog width, because a mid-length identifier wraps confusingly inside itself at the default
  width (lines 288-292).

## States

| State | Appearance change |
|-------|------------------|
| Default (collapsed) | `Disclosure` closed; nothing else renders (line 141) |
| Disclosed | Explanatory body text and the destination dropdown trigger become visible (lines 264-284) |
| Dropdown open | Menu of `targets` visible; entries with `children` render as nested submenus (lines 270-282) |
| Menu item — current target | Disabled; label reads "{name} (current)" (lines 240-249) |
| Target chosen, preflight pending | Dialog opens; body shows "Checking…" (lines 287, 304) |
| Preview loaded, `tokens > 0` | Token-revocation warning line shown with the `TriangleAlert` icon (lines 307-313) |
| Preview loaded, `revoking.length > 0` | "These will lose access:" list shown (lines 314-327) |
| Preview loaded, `revoking.length === 0` | "No access is revoked." shown (lines 328-330) |
| Confirm gate armed (`confirmed === true`) | Transfer button enabled, `warning` variant (lines 166, 365-372) |
| Confirming (transfer in flight) | Dialog close control hidden, Cancel disabled, Input disabled, Transfer button reads "Transferring…" (lines 175, 292, 355, 362, 374) |
| Preview error | Inline error shown via `ErrorText`; dialog stays open (lines 208-210, 333) |
| Transfer error | Inline error shown via `ErrorText`; dialog stays open; busy state clears (lines 223-226, 333) |

## Accessibility

- Root element is a `<section aria-label="Transfer Ownership">`; every interactive control is a
  native, focusable element via the shared `Button`, `DropdownMenuTrigger`/`DropdownMenuItem`, and
  `Input` components this file composes — no bespoke non-semantic clickable element is used (lines
  253, 275-278, 240-249, 348-357).
- The Disclosure trigger ("Transfer Ownership") and the dropdown trigger ("Transfer {entityNoun}")
  MUST carry distinct accessible names, per `trigger-button-labeled-distinctly`, so two buttons in
  the same section are not ambiguous to assistive technology (lines 271-278).
- The type-to-confirm `Input` is labeled by an explicit `<Label htmlFor={inputId}>` tied to the
  input via `React.useId()`, not a placeholder alone (lines 140, 344-357).
- Keyboard and assistive-technology navigation for the disclosure trigger, the dropdown menu
  (including nested submenus), the dialog, and the input all come from the shared `Disclosure`,
  `DropdownMenu`/`DropdownMenuSub`, `Dialog`, and `Input`/`Button` primitives this file composes —
  no custom key handling (`onKeyDown`, `tabIndex` override) appears in this source, so keyboard
  behavior is that component's own recipe's concern, not this one's.
- Minimum tap target sizing is likewise owned by the shared `Button`, `DropdownMenuItem`, and
  `Input` components this section composes (all `size="sm"` or their defaults); no local
  min-width/min-height override appears in source.
- Contrast is governed by the `apt-*` semantic color tokens this component consumes (`apt-text`,
  `apt-text-muted`, `apt-gold`); no raw hex value or component-specific contrast override appears
  in source (lines 265, 298, 309, 319).
- NEEDS REVIEW: Not implemented in source. The dialog body's transition from "Checking…" to the
  resolved preview content (or an inline error) carries no `aria-live`/`role="status"` region in
  this file (lines 303-334), so an assistive-technology user who already opened the dialog has no
  signal that the content changed without re-reading it. What is missing: an explicit live region
  around the status/preview block. What would settle it: whether the shared `Dialog`/`DialogContent`
  primitive itself establishes a live region for its body (out of scope for this recipe) — confirm
  by inspecting `@agenticdevelopertoolkit/ui/components/dialog`.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| transfer-ownership-section-001 | collapsed-by-default, root-section-labeled, disclosure-labeled-transfer-ownership | Initial render | `<section aria-label="Transfer Ownership">`; `Disclosure` closed; trigger shows the `ArrowRightLeft` icon + "Transfer Ownership" |
| transfer-ownership-section-002 | describes-transfer-effect, trigger-button-labeled-distinctly | Open the disclosure | Body text about the address change and no carried-over access is shown; dropdown trigger reads "Transfer {entityNoun}", distinct from "Transfer Ownership" |
| transfer-ownership-section-003 | renders-nested-targets-as-submenu | `targets` includes an entry with non-empty `children` | That entry renders as a submenu trigger; opening it shows its `children` as items |
| transfer-ownership-section-004 | renders-leaf-targets-as-items | `targets` includes an entry with no `children` | Renders as a single menu item labeled with `target.name` |
| transfer-ownership-section-005 | disables-current-target, current-target-not-selectable | `currentTarget` matches one target's `slug` (+`kind`) | That item is disabled and labeled "{name} (current)"; clicking it does not open the dialog |
| transfer-ownership-section-006 | selecting-target-opens-dialog-and-runs-preview | Click a non-current, non-submenu target | Menu closes; dialog opens; `onPreview(target)` called once |
| transfer-ownership-section-007 | preview-populates-dialog, dialog-shows-checking-state | `onPreview` pending, then resolves | "Checking…" shown first, then the dialog reflects the resolved `TransferPreviewResult` |
| transfer-ownership-section-008 | preview-error-shown-inline | `onPreview` rejects with `new Error("X")` | Inline error reads "X"; dialog remains open |
| transfer-ownership-section-009 | preview-error-shown-inline | `onPreview` rejects with a non-`Error` value | Inline error reads "Could not check this transfer." |
| transfer-ownership-section-010 | stale-preview-ignored | Choose target A (preflight pending), choose target B before A resolves, then A's `onPreview` resolves | Dialog reflects only B's state; A's late resolution changes nothing |
| transfer-ownership-section-011 | dialog-title-names-destination | `chosen.name === "Acme"`, `entityNoun === "Persona"` | Dialog title reads "Transfer this Persona to Acme?" |
| transfer-ownership-section-012 | shows-revoked-token-count | `preview.tokens === 1` | Text reads "1 API token bound to this {noun} will be revoked." |
| transfer-ownership-section-013 | shows-revoked-token-count | `preview.tokens === 3` | Text reads "3 API tokens bound to this {noun} will be revoked." |
| transfer-ownership-section-014 | lists-revoked-principals | `preview.revoking` = one `kind: "user"` entry and one `kind: "team"` entry | List shows "{name} (direct)" for the user entry and "{name} (team, {via})" for the team entry |
| transfer-ownership-section-015 | shows-no-access-revoked | `preview.revoking === []` | "No access is revoked." shown |
| transfer-ownership-section-016 | confirm-gate-hidden-until-preview | `preview === null` (still "Checking…") | No confirm `Label`/`Input` renders |
| transfer-ownership-section-017 | confirm-target-is-trimmed-label, confirm-match-ignores-edge-whitespace | `entityLabel = " acme-x "`, typed `"acme-x"` | Transfer button enables (both sides trimmed match) |
| transfer-ownership-section-018 | confirm-match-ignores-edge-whitespace | `entityLabel = "acme-x"`, typed `"Acme-X"` | Transfer button stays disabled (case differs) |
| transfer-ownership-section-019 | confirm-requires-nonempty-target | `entityLabel = "   "` (blank after trim) | Transfer button stays disabled regardless of typed input |
| transfer-ownership-section-020 | transfer-button-disabled-until-armed, transfer-button-not-destructive-styled | `preview` loaded, `confirmed === true` | Transfer button enabled, `warning` variant |
| transfer-ownership-section-021 | transfer-invokes-onconfirm-once, transfer-label-reflects-progress, dialog-locks-during-transfer | Click the enabled Transfer button | `onConfirm(chosen)` called once; label reads "Transferring…"; close control hidden; Cancel disabled |
| transfer-ownership-section-022 | preview-does-not-lock-dialog | Preflight still pending (`busy && !preview`) | Cancel enabled; close control shown; dialog dismissible |
| transfer-ownership-section-023 | transfer-error-shown-inline-dialog-stays-open | `onConfirm` rejects with `new Error("boom")` | Inline error reads "boom"; dialog stays open; busy clears |
| transfer-ownership-section-024 | transfer-error-shown-inline-dialog-stays-open | `onConfirm` rejects with a non-`Error` value, `entityNoun === "Persona"` | Inline error reads "Failed to transfer persona." |
| transfer-ownership-section-025 | transfer-success-resets-state | `onConfirm` resolves | Dialog closes; `chosen`/`preview`/`typed`/`busy`/`error` all reset |
| transfer-ownership-section-026 | cancel-resets-and-closes, reset-orphans-inflight-preview | Click Cancel while a preflight is still pending, then let that preflight resolve | Dialog closes and state resets immediately; the later preflight resolution changes nothing |
| transfer-ownership-section-027 | switching-target-clears-typed-and-error | Type a partial confirm value under target A, then choose target B | Typed input clears; any prior inline error clears |
| transfer-ownership-section-028 | wider-dialog-for-long-identifiers | Dialog open | `DialogContent` uses `max-w-xl`, not the platform default `max-w-md` |

## Edge Cases

- Empty or all-whitespace `entityLabel`: the confirm gate MUST stay permanently disabled because
  the trimmed label's length check fails — no input can arm the Transfer button (line 166).
- `targets = []`: the dropdown menu content MUST render with no items, since `targets.map(...)`
  over an empty array produces none (line 280).
- Deeply nested `children`: `renderTarget` MUST recurse through every level of nesting present,
  with no depth limit enforced in source (lines 229-238).
- Duplicate `(kind, slug)` pairs across `targets`: `targetKey` (line 60) is used as the React list
  key for both the item and the "(current)" match; source performs no deduplication, so callers
  MUST supply unique `(kind, slug)` pairs — duplicates produce a React key collision.
- Concurrent selection (rapid re-choice): the `previewSeq` ref (line 183) is the sole guard against
  a superseded preflight's resolution overwriting newer state; every settled `onPreview` call MUST
  check it still owns the current sequence number before touching state (lines 194-213).
- Re-selecting the currently `chosen` target: `choose` MUST run again from scratch — clearing
  `typed`, restarting the preflight, and bumping `previewSeq` — since source has no memoized
  short-circuit for choosing the same target twice (lines 194-205).
- `currentTarget` undefined: `isCurrentTarget` MUST return `false` for every candidate (the
  `!current` short-circuit), so no menu item is marked current/disabled from that guard alone
  (line 72).
- `currentTarget.kind` defined but a candidate `target.kind` undefined (or vice versa): MUST fall
  back to a slug-only match and treat the two as the same current target — the pre-`kind` legacy
  behavior kept for targets that carry no `kind` (a nested Product) (lines 73-74).
- Error states: `onPreview` and `onConfirm` rejections are both covered under
  `preview-error-shown-inline` and `transfer-error-shown-inline-dialog-stays-open` above, including
  the non-`Error` rejection fallback text (lines 208-210, 223-226).
- Offline/disconnected state: this component performs no network call of its own; `onPreview` and
  `onConfirm` are caller-supplied `Promise`-returning functions, and a connectivity failure surfaces
  through their rejection exactly like any other error — no behavior beyond the generic error
  handling above is defined or needed at this layer (lines 194-227).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `entityNoun` | `string` | — | Singular entity noun (e.g. "Persona"), used in the button and copy (line 101-102) |
| `entityLabel` | `string` | — | The object's own identifier; shown in the dialog and retyped (trimmed) to arm the Transfer button (lines 103-109) |
| `targets` | `TransferTarget[]` | — | Candidate destinations; team workspaces must already be filtered out by the caller (line 110) |
| `currentTarget` | `TransferTargetRef` (optional) | `undefined` | The destination the object already lives in; shown disabled in the menu (lines 112-113) |
| `onPreview` | `(target: TransferTarget) => Promise<TransferPreviewResult>` | — | Server preflight; its result populates the dialog, a throw shows an inline error (lines 114-115) |
| `onConfirm` | `(target: TransferTarget) => Promise<void>` | — | Performs the transfer; a throw shows an inline error and keeps the dialog open (lines 116-117) |

## Deep Linking

Not applicable: no URL scheme, route, or navigation call appears anywhere in
`transfer-ownership-section.tsx`.

## Localization

Not applicable: the source contains no i18n library import, translation-function call, or
string-table lookup; every user-facing string (disclosure title, body copy, dialog title/
description, button labels, error fallbacks) is a literal JS/JSX string or template literal
(e.g. lines 260-268, 294-330, 374).

## Accessibility Options

Document which accessibility display options (Rule 15) this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no transition, animation, or motion effect is defined in this file; any open/close motion belongs to the composed `Disclosure`/`Dialog`/`DropdownMenu` components, out of scope here. |
| Increase Contrast | Not applicable: the component uses only semantic `apt-*` color tokens (`apt-text`, `apt-text-muted`, `apt-gold`) and defines no raw hex or opacity-based color of its own that would need a distinct high-contrast variant (lines 265, 298, 309, 319). |
| Differentiate Without Color | Resolved from source: every state that carries meaning pairs color with text or an icon, never color alone — the token-revocation warning pairs the `TriangleAlert` icon with count text (lines 307-313), the current/disabled item appends the text "(current)" rather than relying on a muted color (lines 240-249), and the Transfer action's non-destructive nature is conveyed by its label and `warning` variant rather than a red/neutral color distinction alone (lines 365-372). |

## Feature Flags

Not applicable: no feature-flag key or conditional gate appears anywhere in
`transfer-ownership-section.tsx`.

## Analytics

Not applicable: no analytics or event-tracking call appears anywhere in
`transfer-ownership-section.tsx`.

## Privacy

- **Data collected**: The typed confirmation text (`typed`), which the user re-enters as a copy of
  the caller-supplied `entityLabel`; no other input is captured by this component itself
  (line 145).
- **Storage**: None — `chosen`/`preview`/`typed`/`busy`/`error` all live in transient in-memory
  React state (`useState`) and are cleared by `reset()` or on unmount; nothing is written to
  `localStorage`, a cookie, or any persistent store (lines 141-147, 185-192).
- **Transmission**: The component transmits nothing itself; it invokes the caller-supplied
  `onPreview`/`onConfirm` functions with the chosen `TransferTarget`, and any network transmission
  those functions perform is outside this file (lines 114-117, 205, 221).
- **Retention**: None beyond the component's own lifetime, or until `reset()` runs — see Storage
  above.

## Logging

Not applicable: no `console.*` call or logger reference appears anywhere in
`transfer-ownership-section.tsx`.

## Platform Notes

- **SwiftUI**: Start from a `DisclosureGroup` for the collapsed/expanded "Transfer Ownership"
  section, a `Menu` with nested `Menu` sub-items for the workspace tree (mirroring
  `DropdownMenuSub`), and a `.sheet`/custom modal for the two-stage (preview then type-to-confirm)
  flow. Drive the confirm gate with a `TextField` bound to `@State` text compared, trimmed, against
  the object's identifier, and use a generation counter alongside the preflight `Task` to discard a
  stale preview the way `previewSeq` does here, since a plain `async` call has no built-in
  "supersede this in-flight request" primitive.
- **Compose**: Use an expand/collapse composable (e.g. driven by `AnimatedVisibility`) for the
  Disclosure equivalent, a `DropdownMenu` with a nested `DropdownMenu` for submenu targets — Compose
  has no native infinitely-nested submenu primitive, so the nested case needs a custom recursive
  composable exactly as this source does — and an `AlertDialog` for the confirm flow. Gate the
  confirm button from a `mutableStateOf` string compared via `.trim()`, and cancel a stale preflight
  `Job` (from a `CoroutineScope`) when a new target is chosen, mirroring the sequence guard here.
- **React/Web**: This is the source. See
  `packages/web/packages/adh-ui/src/blocks/transfer-ownership-section.tsx`, which composes
  `@agenticdevelopertoolkit/ui`'s `Disclosure`, `Button`, `Input`, `Label`, `ErrorText`, the
  `DropdownMenu` family (including `DropdownMenuSub`), and the `Dialog` family. State is plain
  `React.useState`/`useRef`; the async preview-race guard is a manually incremented `previewSeq`
  ref rather than an `AbortController` (no cancellation primitive is used).
- **AppKit/UIKit**: Use an `NSDisclosureButton`/custom expand-collapse `NSView` (AppKit) or a
  collapsible `UITableView` section header (UIKit) for the Disclosure equivalent, and an `NSMenu`/
  `UIMenu` with a nested submenu (`NSMenuItem.submenu`/nested `UIMenu`) for the workspace tree —
  both platforms support native nested submenus, unlike Compose. Use an `NSAlert`/
  `UIAlertController`, or a small custom sheet/panel given the richer body content here, for the
  two-phase confirm; gate the confirm control from a text-field delegate callback compared with
  `.trimmingCharacters(in: .whitespaces)`, and track the in-flight preflight with a generation
  counter checked when its completion handler returns.
- **WinUI 3**: Use an `Expander` (`IsExpanded="False"` by default) for the Disclosure equivalent,
  with its `Header` a horizontal `StackPanel` of a `FontIcon`/`SymbolIcon` (for `ArrowRightLeft`)
  plus a `TextBlock` reading "Transfer Ownership". Inside, a `Button` opens a `MenuFlyout` whose
  `MenuFlyoutItem`s render the leaf targets and whose nested destinations use `MenuFlyoutSubItem` —
  WinUI 3's native nested-submenu control, directly matching `DropdownMenuSub` — with the current
  item's `MenuFlyoutItem.IsEnabled` set `False` and its text carrying " (current)". Model the
  confirmation flow as a `ContentDialog` with `PrimaryButtonText="Transfer"`, binding
  `IsPrimaryButtonEnabled` to the trimmed-match comparison from a `TextBox.TextChanged` handler, and
  suppress dismissal while transferring by handling the dialog's `Closing` event and setting
  `args.Cancel = true` whenever a `confirming` flag is set — the WinUI analogue of the
  `onOpenChange` guard here (line 287). Render the "Checking…" text, the token-count warning, and
  the revoked-principal list as conditionally visible `TextBlock`/`ItemsRepeater` content inside the
  `ContentDialog` body, and style the Transfer button with a custom `Style` tinted for the Fluent
  "Caution"/warning system color rather than the built-in destructive/red button style, matching the
  source's `warning`-not-`destructive` choice (lines 365-370).

## Design Decisions

- Decision: Trim both sides of the confirm comparison (`entityLabel` and the typed value) instead
  of an exact match.
  Rationale: `entityLabel` here can be a user-editable display name, not always a machine
  identifier, so trailing whitespace would render identically to its absence; a strict compare
  would leave the button permanently un-armable with nothing on screen to explain why (lines
  151-166).
  Approved: pending
- Decision: Seal the dialog against dismissal only while the final transfer (`onConfirm`) is
  pending, never while the preflight (`onPreview`) is pending.
  Rationale: `onPreview` performs no server write, so a slow or hung preflight has no correctness
  claim on the user's ability to back out; sealing it too would trap them behind "Checking…" with
  no exit (lines 168-175).
  Approved: pending
- Decision: Style the Transfer button `warning`, not `destructive`.
  Rationale: a transfer moves the object and drops other principals' access to it, but nothing is
  destroyed and the move can be made again in the other direction; the red destructive treatment is
  reserved for what cannot be undone (lines 365-370).
  Approved: pending
- Decision: Guard the async preflight race with a monotonically incrementing `previewSeq` ref
  rather than cancelling the `onPreview` promise itself.
  Rationale: `onPreview` is a caller-supplied `Promise` with no cancellation contract; a sequence
  number lets a late resolution be detected and ignored without requiring the caller to support
  `AbortController`-style cancellation (lines 177-183).
  Approved: pending
- Decision: Widen the confirmation dialog to `max-w-xl`.
  Rationale: every load-bearing line of text in the dialog is an identifier, and at the platform's
  default `max-w-md` a mid-length one wraps confusingly inside itself (lines 288-292).
  Approved: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| Raw hex colors / arbitrary opacity values | passed | agenticdevelopercookbook://compliance/ui#no-raw-colors |
| Bespoke UI components (must compose shared `@agenticdevelopertoolkit/ui` primitives) | passed | agenticdevelopercookbook://compliance/ui#shared-components |
| Interactive controls carry distinct, meaningful accessible names | passed | agenticdevelopercookbook://compliance/accessibility#distinct-labels |
| Destructive-adjacent action double-gated (server preview + type-to-confirm) | passed | agenticdevelopercookbook://compliance/safety#confirmation-gating |
| Async status change announced to assistive technology | flagged | agenticdevelopercookbook://compliance/accessibility#live-region-announcements |

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial recipe extracted from `transfer-ownership-section.tsx`: disclosure-gated destination menu with nested submenu targets, a server preflight race-guarded against stale results, and a type-to-confirm transfer dialog. |
