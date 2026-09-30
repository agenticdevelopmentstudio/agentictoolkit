<!-- leaf: implement-general-view-1/disclosure-card-view--part-6 · source: disclosure-card-view.md -->

# DisclosureCardView — continued (part 6)

## Design Decisions

- **Decision**: `disclosureTapped` only calls `onToggle`; it never mutates
  `content.isHidden`, `body.isHidden`, or the disclosure control's own
  tooltip/label.
  **Rationale**: Per the type's own doc comment, "a fold is applied by
  rebuilding, not by mutating" — the public `isCollapsed` is a `get`-only
  property backed by `content.isHidden`, fixed at `init`. The intended
  integration (`CardFoldMemory.setCollapsed`) records the new state and
  rebuilds the card on the next runloop turn, specifically because a
  synchronous rebuild would tear down the very button whose click is still
  dispatching.
  **Approved**: pending
- **Decision**: The width floor is computed as the wider of the open
  content's fitting width and the folded masthead's width, and is
  recomputed on every `layout()` pass regardless of the card's current
  fold state.
  **Rationale**: Per the type's own doc comment, "a card is exactly as wide
  folded as it is open" — a content-hugging window that re-derived its
  width from whichever state happened to be visible would jump sideways on
  every fold, which is what this fold-independent floor prevents.
  **Approved**: pending
- **Decision**: The status badge is centered on `cornerPeakInset`
  (`cornerRadius − cornerRadius/√2`), not on the frame's literal corner,
  and is added as a top-level sibling subview after `surface` rather than
  inside it.
  **Rationale**: Per the type's own doc comment, a rounded card has no ink
  at the square corner, so centering there would look like the badge
  "slipped off"; and a `CALayer` draws its own border above its sublayers,
  so the badge must live outside `surface`'s layer tree to paint above that
  border.
  **Approved**: pending
- **Decision**: Dimming is a single `alphaValue` applied to the whole view,
  not a second set of dimmed theme colors.
  **Rationale**: Per the type's own doc comment, this makes the card
  recede "complete — border, surface, content and all" while every color
  it draws keeps meaning exactly what it means on the live card.
  **Approved**: pending
- **Decision**: `titleAccessory` and `titlebarAccessory` are placed and
  measured but never styled, tinted, or given any accessibility
  configuration by `DisclosureCardView`.
  **Rationale**: Per the type's own doc comment, a host that passes a view
  has already decided its appearance and behavior; recoloring or otherwise
  opinionating on it would fight a caller that, for example, hands in a
  logo that is also a button.
  **Approved**: pending
- **Decision**: The symbol after the title is described by a `StatusSymbol`
  value, not handed in as a view, and `StatusSymbol.placeholder(sizedLike:)`
  holds the named symbol's room with nothing drawn, spoken, or explained.
  **Rationale**: Unlike `titleAccessory`, this mark is the card's own
  vocabulary: it must be sized to the title, tinted from the live palette
  on every theme change, and spoken exactly like the corner badge, so the
  card owns its rendering rather than trusting each host to repeat it. The
  placeholder exists because a stack of cards that marks only one of them
  would otherwise make that card — and so a content-hugging window — jump a
  symbol's width wider whenever the mark moved to another card or went
  away; handing every unmarked card the placeholder keeps each card's
  requested width independent of which card is marked.
  **Approved**: pending
- **Decision**: The masthead width floor (`asks-for-whole-point-title-width`
  and the title-plus-gap floor) applies to every card, with or without a
  summary.
  **Rationale**: A card with no summary still has a title that the
  content-hugging window must fit whole; limiting the floor to summarized
  cards let a long title truncate in the one card with nothing else to
  widen it.
  **Approved**: pending
- **Decision**: The disclosure control's `toolTip`/accessibility label
  strings (`"Show details"`, `"Hide details"`) are English literals with no
  localization key.
  **Rationale**: Documented here rather than idealized away — the source
  has no string-catalog or `NSLocalizedString` call for these two strings,
  unlike every other piece of text on the card, which is entirely
  caller-supplied.
  **Approved**: pending
