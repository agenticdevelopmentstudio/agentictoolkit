<!-- leaf: implement-general-1/delete-entity-section--edge-cases · source: delete-entity-section.md -->

# DeleteEntitySection

## Edge Cases

- Empty `confirmValue` guard: because the enable check requires `confirmValue.length
  > 0`, an empty identifier never matches the initially-empty input and never arms
  the delete.
- Match is exact and untrimmed: leading/trailing whitespace or a case difference in
  the typed value keeps the delete disabled — the user must type the identifier
  verbatim.
- Mid-delete dismissal: `onOpenChange` ignores close requests while `busy`, and
  `DialogContent` hides its close (`showClose={!busy}`), so the user cannot abandon a
  running delete. The CTA and Cancel buttons are also disabled while `busy` (see
  disable-actions-while-busy), so a double-click cannot fire a second call.
- Failure path: a rejected `onConfirm` sets an inline error, clears `busy`, and
  leaves the typed value and open dialog intact so the user can retry without
  re-typing from the warn phase. Editing the input afterward does not itself clear
  the stale error — it persists until the next `onConfirm` attempt (see
  reset-on-cancel-or-success).
- Success path: `onConfirm` typically navigates the parent away; the section still
  resets defensively so a re-mounted pane starts closed and empty. This reset never
  collapses the `Disclosure` — `disclosed` is independent state (see
  reset-on-cancel-or-success).
- `entityNoun` article: see select-article-from-first-letter — the warn copy picks
  "an" vs "a" purely from the noun's first letter, so it also misreads phonetic
  exceptions like "user" or "hour".
- Optional `description` overrides only the disclosed-section blurb; the dialog copy
  is derived from `entityNoun`/`childEntities`/`confirmValue`.
