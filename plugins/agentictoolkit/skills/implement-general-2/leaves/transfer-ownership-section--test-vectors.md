<!-- leaf: implement-general-2/transfer-ownership-section--test-vectors · source: transfer-ownership-section.md -->

# TransferOwnershipSection

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
| transfer-ownership-section-014 | lists-revoked-principals | `preview.revoking` = `[{id:"u1",name:"Ann",kind:"user",via:"direct"}, {id:"t1",name:"Ops",kind:"team",via:"Acme"}]` | List shows "Ann (direct)" for the first entry and "Ops (team, Acme)" for the second |
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
| transfer-ownership-section-027 | switching-target-clears-typed-and-error | Unit-level: call `choose(A)`, set `typed` to a partial value and `error` to a message, then call `choose(B)` directly | `typed` and `error` are both reset before `onPreview(B)` is invoked |
| transfer-ownership-section-028 | wider-dialog-for-long-identifiers | Dialog open | `DialogContent` uses `max-w-xl`, not the platform default `max-w-md` |
