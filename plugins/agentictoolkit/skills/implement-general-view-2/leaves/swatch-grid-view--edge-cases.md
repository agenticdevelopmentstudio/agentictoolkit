<!-- leaf: implement-general-view-2/swatch-grid-view--edge-cases · source: swatch-grid-view.md -->

# SwatchGridView

**Rules** (cite as `implement-general-view-2/swatch-grid-view--edge-cases#<slug>`):

- `color-swatch-fill-remain-visually-stale-after` MUST — Dynamic/appearance-adaptive input color: makeSwatch(_:) sets the swatch's backgroundColor to color.cgColor once, at …

## Edge Cases

- Null/empty input: `colors` defaults to `[]` and is a non-optional
  `[NSColor]`. When empty, the row-building loop never executes, so the
  view ends up with zero rows and zero swatches — the **renders-empty-grid**
  requirement.
- Boundary values — colors count not evenly divisible by columns: the last
  row contains `colors.count % columns` swatches rather than a full
  `columns` — the **shortens-final-row** requirement, directly traceable to
  the row-building loop's bounds.
- Boundary values — `columns` exceeding `colors.count`: all colors render
  in a single row shorter than `columns` — the
  **single-row-when-columns-exceeds-count** requirement, following from
  the same loop bounds as above.
- Concurrent access: Not applicable — the class is `@MainActor`-isolated,
  so Swift's concurrency checker serializes all access to `colors`,
  `container`, and every mutating method; there is no code path by which
  two threads mutate the view simultaneously.
- Error states: Not applicable — every operation in `SwatchGridView.swift`
  (property assignment, layer configuration, constraint activation) is
  synchronous and non-throwing; no `try`, `Result`, or error-producing API
  appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only renders caller-supplied `NSColor` values.
- Dynamic/appearance-adaptive input color: `makeSwatch(_:)` sets the
  swatch's `backgroundColor` to `color.cgColor` once, at swatch-creation
  time, and never revisits that assignment. Only the swatch's *border*
  color is re-applied on a theme change, via `observeTheme`. If a caller
  passes a dynamic (appearance-adaptive) `NSColor` as a swatch color, the
  swatch's fill MAY remain visually stale after a system appearance change
  until the caller triggers a full rebuild by calling `setColors(_:)`
  again; this is current, source-traceable behavior — not a named MUST
  requirement — and is recorded as a documented quirk in Design Decisions
  rather than corrected here.
