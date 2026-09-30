<!-- leaf: implement-general-view-1/disclosure-card-view--test-vectors-part-2 · source: disclosure-card-view.md -->

# DisclosureCardView — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| disclosure-card-047 | places-title-status-after-title | `init(..., titleTrailingStatus: StatusSymbol(symbolName: "checkmark.seal.fill", colorName: "green", accessibilityLabel: "Best"), ...)` | The title row holds an image view after the title text; its leading edge is at or after the title's trailing edge and less than 12pt from it (per `testTheSymbolAfterTheNameStandsRightAgainstIt`) |
| disclosure-card-048 | exposes-title-status-like-badge, colors-status-badge | `titleTrailingStatus: StatusSymbol(symbolName: "xmark.seal.fill", accessibilityLabel: "Out of quota", color: { _ in .systemPurple })` | The symbol's `alphaValue == 1`; `isAccessibilityElement() == true`; `accessibilityLabel() == "Out of quota"`; `toolTip == "Out of quota"`; `contentTintColor == .systemPurple` (per `testTheSymbolAfterTheNameIsSpokenAndTintedFromTheLivePalette`) |
| disclosure-card-049 | reserves-placeholder-room-silently | Two cards with a long title and 40pt content, one given the seal of vector 047 and one `.placeholder(sizedLike: "checkmark.seal.fill")` | Both cards' `fittingSize.width` are equal (±0.5); the placeholder's frame is as wide as the seal's; it is not hidden, its `alphaValue == 0`, it is no accessibility element, and its `toolTip == nil` (per `testAPlaceholderHoldsTheSymbolsRoomAndSaysNothing`) |
| disclosure-card-050 | asks-for-whole-point-title-width, floors-width-to-wider-of-open-or-folded-content | A card with a long title, no `summary`, and 40pt content, hosted at exactly its own `fittingSize.width` | The title text's laid-out width is at least its own `fittingSize.width − 0.5` — it is not truncated (per `testACardWithNoSummaryStillAsksForItsTitleWhole`) |

`color(named:)`'s name→role map (`"red"` → `dangerColor`, `"blue"` →
`accentColor`, and so on) is defined outside this file — see the AppKit
Platform Notes bullet below.
