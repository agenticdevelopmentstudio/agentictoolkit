<!-- leaf: implement-general-1/badge--edge-cases · source: badge.md -->

# Badge

## Edge Cases

- **Empty `text`** (`""`): renders an empty label; the badge still lays out
  with its fixed 6pt/2pt padding around a zero-width label, producing a small
  pill (see `#requirements/displays-caller-text` — the source has no guard
  against an empty string).
- **Very long `text`**: no maximum width, line-wrap mode, or truncation is
  configured in the source. Because both the label and the badge carry
  required horizontal content-hugging, the badge grows to fit the full string
  unless a caller externally constrains its width (e.g. inside a stack view)
  (see `#requirements/sizes-to-fit-content`).
- **Non-sRGB-convertible `color`** (e.g. a pattern-image `NSColor`, or one
  from a color space `usingColorSpace(.sRGB)` cannot represent):
  `contrastingTextColor(on:)` falls back to white in `.filled` style; in
  `.outlined` style the same color is still assigned directly to the border
  and text regardless of convertibility, since that path never calls
  `usingColorSpace(.sRGB)` (see
  `#requirements/falls-back-to-white-on-unconvertible-color` and
  `#requirements/paints-outlined-appearance`).
- **Repeated `update` calls**: each call fully re-evaluates `applyStyle()`
  from the just-assigned `color`/`style`, so no stale visual state persists
  between calls (see `#requirements/supports-in-place-restyle`).
- **Omitting `style` on `update`**: silently resets a previously `.outlined`
  badge back to `.filled` (see
  `#requirements/resets-style-to-filled-by-default-on-update`) — see also
  Design Decisions.
- **Concurrent access**: not applicable — `Badge` is `@MainActor`-isolated;
  the Swift compiler rejects construction or mutation from off the main
  actor, so there is no concurrent-access surface for this component to
  define behavior for.
- **Error states (dependency/network failure)**: not applicable — the source
  performs no I/O, network call, or dependency lookup of any kind.
- **Offline/disconnected state**: not applicable — Badge performs no network
  operation of its own.
- **Boundary values**: not applicable in the numeric-input sense — Badge's
  only inputs are a caller-supplied string and color. Its fixed constants
  (5pt radius, 6pt/2pt padding) are literals in the source, not
  caller-configurable ranges with a boundary to test.
