<!-- leaf: implement-general-2/transfer-ownership-section--edge-cases · source: transfer-ownership-section.md -->

# TransferOwnershipSection

**Rules** (cite as `implement-general-2/transfer-ownership-section--edge-cases#<slug>`):

- `entitylabel-confirm-gate-stay-permanently-disabled-because` MUST — Empty or all-whitespace entityLabel: the confirm gate MUST stay permanently disabled because the trimmed label's length …
- `dropdown-menu-content-render-items-since-targets` MUST — targets = []: the dropdown menu content MUST render with no items, since targets.map(...) over an empty array produces …
- `nested-children-rendertarget-recurse-through-level-nesting` MUST — Deeply nested children: renderTarget MUST recurse through every level of nesting present, with no depth limit enforced …
- `deduplication-so-callers-supply-unique-kind-slug` MUST — Duplicate (kind, slug) pairs across targets: targetKey is used as the React list key for both the item and the …
- `settled-onpreview-call-check-still-owns-current` MUST — Concurrent selection (rapid re-choice): the previewSeq ref is the sole guard against a superseded preflight's …
- `chosen-target-choose-run-again-from-scratch` MUST — Re-selecting the currently chosen target: choose MUST run again from scratch — clearing typed, restarting the …
- `currenttarget-undefined-iscurrenttarget-return-false-candidate-current` MUST — currentTarget undefined: isCurrentTarget MUST return false for every candidate (the !current short-circuit), so no menu …
- `undefined-vice-versa-fall-back-slug-only` MUST — currentTarget.kind defined but a candidate target.kind undefined (or vice versa): MUST fall back to a slug-only match …

## Edge Cases

- Empty or all-whitespace `entityLabel`: the confirm gate MUST stay permanently disabled because
  the trimmed label's length check fails — no input can arm the Transfer button.
- `targets = []`: the dropdown menu content MUST render with no items, since `targets.map(...)`
  over an empty array produces none.
- Deeply nested `children`: `renderTarget` MUST recurse through every level of nesting present,
  with no depth limit enforced in source.
- Duplicate `(kind, slug)` pairs across `targets`: `targetKey` is used as the React list
  key for both the item and the "(current)" match; source performs no deduplication, so callers
  MUST supply unique `(kind, slug)` pairs — duplicates produce a React key collision.
- Concurrent selection (rapid re-choice): the `previewSeq` ref is the sole guard against
  a superseded preflight's resolution overwriting newer state; every settled `onPreview` call MUST
  check it still owns the current sequence number before touching state.
- Re-selecting the currently `chosen` target: `choose` MUST run again from scratch — clearing
  `typed`, restarting the preflight, and bumping `previewSeq` — since source has no memoized
  short-circuit for choosing the same target twice.
- `currentTarget` undefined: `isCurrentTarget` MUST return `false` for every candidate (the
  `!current` short-circuit), so no menu item is marked current/disabled from that guard alone.
- `currentTarget.kind` defined but a candidate `target.kind` undefined (or vice versa): MUST fall
  back to a slug-only match and treat the two as the same current target — the pre-`kind` legacy
  behavior kept for targets that carry no `kind` (a nested Product).
- Error states: `onPreview` and `onConfirm` rejections are both covered under
  `preview-error-shown-inline` and `transfer-error-shown-inline-dialog-stays-open` above, including
  the non-`Error` rejection fallback text.
- Offline/disconnected state: this component performs no network call of its own; `onPreview` and
  `onConfirm` are caller-supplied `Promise`-returning functions, and a connectivity failure surfaces
  through their rejection exactly like any other error — no behavior beyond the generic error
  handling above is defined or needed at this layer.
