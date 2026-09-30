<!-- leaf: implement-general-1/badge--part-2 · source: badge.md -->

# Badge — continued (part 2)

**Rules** (cite as `implement-general-1/badge--part-2#<slug>`):

- `decision` MUST — update's style parameter defaults to .filled independently of the badge's current, already-stored style. Rationale: …

## Platform Notes

- **SwiftUI**: Start from a small container view (or `ViewModifier`) wrapping
  a `Text`, applying `.padding(.horizontal, 6).padding(.vertical, 2)` and
  `.background(color, in: RoundedRectangle(cornerRadius: 5))` for the
  `.filled` background — `.clipShape(RoundedRectangle(cornerRadius: 5))`
  alone only clips, it paints no fill — or `.overlay(RoundedRectangle(cornerRadius: 5).stroke(color,
  lineWidth: 1))` for `.outlined`. SwiftUI has no built-in equivalent of
  `contrastingTextColor(on:)`, so port the same luminance formula as a small
  helper function, and reconcile the caption font with SwiftUI's Dynamic Type
  system rather than a raw `.caption` font size.
- **Compose**: Start from a `Box`/`Surface` with `shape =
  RoundedCornerShape(5.dp)` and a centered `Text` inset by
  `Modifier.padding(horizontal = 6.dp, vertical = 2.dp)`. Material 3's
  `AssistChip`/`SuggestionChip` are the nearest built-in analogs but carry
  interaction states (ripple, enabled/disabled) that Badge does not have, so a
  plain `Box` + `Text` composition matches Badge's non-interactive nature more
  faithfully. Reimplement the luminance-based text-color choice, since
  Compose's `contentColorFor` derives from the Material color scheme rather
  than computing per-arbitrary-color contrast.
- **React/Web**: Use an inline-block `<span>` with `border-radius: 5px`,
  `padding: 2px 6px`, background/border/color driven by the equivalent style
  prop, and a `getContrastingTextColor` helper reimplementing the same
  0.299/0.587/0.114 luminance weights and 0.6 threshold. The sibling web
  Badge recipe (`agentictoolkit://recipes/badge`) already implements
  this on the web; reuse its formula so filled-style contrast decisions agree
  across platforms rather than re-deriving a possibly different threshold.
- **AppKit / UIKit**: Source at
  `packages/apple/AgenticToolkit/macOS/UI/Badge/Badge.swift` (this recipe's
  source): an `NSView` subclass owning an `NSTextField(labelWithString:)`,
  styled via `CALayer` (`cornerRadius`, `backgroundColor`, `borderWidth`,
  `borderColor`) and `NSColor`. A UIKit port replaces `NSView`/`NSTextField`/
  `NSColor` with `UIView`/`UILabel`/`UIColor`, uses `layer.cornerRadius` the
  same way, and must re-derive the `.caption`-equivalent font from whatever
  theme abstraction the iOS app uses, since this source's `observeTheme`
  extension is macOS-only (`AgenticToolkitCoreMacOS`). The
  Interface-Builder-rejecting `init?(coder:)` pattern carries over unchanged.
- **WinUI 3**: Start from a `Border` wrapping a `TextBlock`, since WinUI 3 has
  no single control offering both filled and outlined chip states for
  arbitrary text (`InfoBadge` is numeric/dot-only and cannot host a text label
  like `"dev"` or `"stopped"`). Set `Border.CornerRadius="5"` to match the 5px
  radius and `Border.Padding="6,2,6,2"` to match the leading/trailing-6,
  top/bottom-2 padding. Bind `Border.Background`, `Border.BorderBrush`,
  `Border.BorderThickness`, and the inner `TextBlock.Foreground` to the same
  two branches `applyStyle()` switches on: filled sets `Background=color`,
  `BorderThickness=0`, `TextBlock.Foreground` to the computed black/white;
  outlined sets `Background=Transparent`, `BorderThickness=1`,
  `BorderBrush=color`, `TextBlock.Foreground=color`. WinUI 3 has no built-in
  API for computing contrasting text color from an arbitrary `Color`, so port
  `contrastingTextColor(on:)` as a small static helper using the same
  0.299/0.587/0.114 weights and 0.6 threshold. Give the `Border`
  `HorizontalAlignment="Left"` (or wrap it in a `StackPanel`) so it hugs its
  content instead of stretching, matching Badge's required horizontal
  content-hugging (`sizes-to-fit-content`).

## Design Decisions

- **Decision**: `update`'s `style` parameter defaults to `.filled`
  independently of the badge's current, already-stored style.
  **Rationale**: This is documented here because it produces a surprising
  reset: a caller that calls `update(text:color:)` on a previously
  `.outlined` badge, intending only to change its text or color, silently
  flips it back to `.filled`. There is no state read-back in `update` to
  preserve the existing style, so callers that want to keep `.outlined` MUST
  pass `style: .outlined` explicitly on every `update` call.
  **Approved**: pending
- **Decision**: `contrastingTextColor(on:)` returns white, rather than
  throwing or reusing the current text color, when the background cannot be
  converted to sRGB.
  **Rationale**: Keeps Badge always renderable for any `NSColor` a caller
  passes in (never crashes on an exotic color space, such as a pattern
  image), at the cost of a potentially poor contrast choice for those
  unusual colors.
  **Approved**: pending
- **Decision**: The caller supplies `color` directly instead of Badge
  deriving it from a semantic status enum of its own.
  **Rationale**: Per the type's own doc comment, Badge is "theme-agnostic:
  the caller supplies the color... and the badge owns the pill shape,
  padding, and text styling" — this keeps Badge reusable across apps with
  different `SemanticPalette`s rather than baking one app's status vocabulary
  into the shared component.
  **Approved**: pending
- **Decision**: `contrastingTextColor(on:)` picks black or white using the
  perceptual-luminance formula `0.299·R + 0.587·G + 0.114·B` (the ITU-R
  BT.601 luma weights) against a 0.6 threshold, rather than the WCAG 2.x
  relative-luminance formula (which linearizes sRGB and weights channels
  0.2126/0.7152/0.0722) or a full WCAG contrast-ratio computation.
  **Rationale**: The BT.601 weights are a cheap, well-known heuristic for
  perceived brightness that needs no gamma-linearization step, so a black/
  white choice can be computed inline for any arbitrary caller-supplied
  color. The tradeoff is that, unlike a WCAG contrast-ratio check, this
  heuristic makes no guarantee about a specific minimum numeric contrast
  ratio against the chosen color — see the open question on
  minimum-contrast-ratio.
  **Approved**: pending
- **Decision**: Badge exposes no accessibility role or label context beyond
  AppKit's default static-text exposure of its `NSTextField` label — there is
  no code in the source that would let VoiceOver announce, for example, that
  a badge reading "3" is a count versus a badge reading "dev" being a status.
  **Rationale**: Badge is a plain, non-interactive label; the surrounding
  call site (e.g. a list row's other accessible elements) is expected to
  supply that context, consistent with Badge owning only pill shape, padding,
  and text styling and not caller semantics.
  **Approved**: pending
