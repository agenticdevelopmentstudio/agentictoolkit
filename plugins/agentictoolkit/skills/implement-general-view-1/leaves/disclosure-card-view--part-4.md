<!-- leaf: implement-general-view-1/disclosure-card-view--part-4 · source: disclosure-card-view.md -->

# DisclosureCardView — continued (part 4)

**Rules** (cite as `implement-general-view-1/disclosure-card-view--part-4#<slug>`):

- `callers-supply-color-closure-resolves` SHOULD — Callers SHOULD supply color as a closure that resolves against the live SemanticPalette each time it is called (or use …

## Configuration

`DisclosureCardView` (`packages/apple/AgenticToolkit/macOS/UI/Cards/DisclosureCardView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | `String` | — (required) | Text shown in the titlebar |
| `titleIsAccent` | `Bool` | — (required) | Colors `title` with `accentColor` when `true`, `primaryTextColor` when `false` |
| `titleAccessory` | `NSView?` | `nil` | View placed before the title, e.g. a host's logo mark |
| `titleTrailingStatus` | `StatusSymbol?` | `nil` | Symbol drawn right after the title, at the title's size, e.g. a seal on the one card in a stack worth acting on; a stack that marks only some cards hands the rest `StatusSymbol.placeholder(sizedLike:)` so every card asks for the same width |
| `titlebarAccessory` | `NSView?` | `nil` | View placed before the disclosure control, e.g. a per-card menu |
| `subtitle` | `String?` | `nil` | One quiet line under the masthead; hidden whenever the card is collapsed |
| `summary` | `[SummaryPart]` | `[]` | Readings shown on their own right-aligned line only while the card is collapsed |
| `status` | `StatusSymbol?` | `nil` | Symbol stamped on the card's top-right corner |
| `isCollapsed` | `Bool` | `false` | Whether the card is constructed folded; fixed for the instance's lifetime |
| `isDimmed` | `Bool` | `false` | Whether the whole card renders at reduced (0.55) alpha |
| `scaledSize` | `CGFloat` | — (required) | The text size driving every scaled inset, font, and badge dimension |
| `onToggle` | `((Bool) -> Void)?` | `nil` | Called with the requested new collapsed state when the disclosure control is tapped |

`SummaryPart`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | `String` | — (required) | The reading's label, e.g. `"5H"` |
| `value` | `String` | — (required) | The reading's value, e.g. `"23%"` |
| `color` | `(SemanticPalette) -> NSColor?` | — (required, or derived from `colorName`) | Resolves the value's color against the live palette each time it is called |
| `colorName` (convenience `init`) | `String?` | — | Looked up via `palette.color(named:)` in place of a custom `color` closure |

Callers SHOULD supply `color` as a closure that resolves against the live
`SemanticPalette` each time it is called (or use the `colorName` convenience
`init`, which does this automatically), rather than capturing a static
`NSColor` at construction time — a captured static color will not update on
a theme change. This is caller-side guidance: `DisclosureCardView` has no way
to enforce it and no observable behavior distinguishes a dynamic `color`
closure from a static one, so it has no requirement or test vector of its
own.

`StatusSymbol`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `symbolName` | `String` | — (required) | SF Symbol name rendered in the corner badge or after the title |
| `color` | `(SemanticPalette) -> NSColor?` | — (required, or derived from `colorName`) | Resolves the symbol's tint against the live palette on every theme application; `nil` falls back to `secondaryTextColor` |
| `colorName` (convenience `init`) | `String?` | — | Looked up via `palette.color(named:)` in place of a custom `color` closure |
| `accessibilityLabel` | `String` | — (required) | Used as both the symbol's accessibility label and its tooltip |
| `isPlaceholder` | `Bool` | `false` (read-only) | `true` only for `StatusSymbol.placeholder(sizedLike:)`, which holds the named symbol's room with nothing drawn, spoken, or explained |

Public API beyond `init`:

```swift
public func addContent(_ view: NSView)
public var contentSpacing: CGFloat { get set }
public var isCollapsed: Bool { get }
```

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `Show details` | Disclosure control's `toolTip` and accessibility label when constructed `isCollapsed: true` |
| (none — hardcoded literal) | `Hide details` | Disclosure control's `toolTip` and accessibility label when constructed `isCollapsed: false` |

`title`, `subtitle`, `summary`'s `name`/`value` strings,
`status.accessibilityLabel`, and `titleTrailingStatus.accessibilityLabel`
are all caller-supplied at the call site — the
component defines no string literals of its own for them. The two disclosure
strings above ARE component-owned literals, and the source assigns them
directly (`"Show details"`/`"Hide details"`) with no `NSLocalizedString` or
string-catalog key — a real localization gap for a component intended to
ship in a localized app, documented here rather than smoothed over.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source performs no animation, transition, or `NSAnimationContext`/`CATransaction` call anywhere — every state change (theme colors, fonts, the width floor) is an instantaneous property or constraint-constant assignment. |
| Increase Contrast | Not applicable to this component directly: the source reads no system contrast setting; every color it draws comes from the active `SemanticPalette`, and whether the resulting contrast is sufficient is tracked once under Accessibility above, not duplicated here. |
| Differentiate Without Color | Satisfied: the disclosure state is communicated by the triangle's own orientation plus its tooltip/label text, not color; the status badge and the title status symbol each pair their tint with an SF Symbol shape and an `accessibilityLabel`; and every summary value is always paired with its `name` text label (`formats-summary-parts`) rather than color alone. |

## Privacy

- **Data collected**: None — the component holds only the `title`,
  `subtitle`, `summary`, `status`, `titleTrailingStatus`, and accessory
  values passed to it by the caller; it originates no data of its own.
- **Storage**: Not applicable — `DisclosureCardView` performs no
  persistence of any kind. (The companion `CardFoldMemory` type persists
  which cards are folded, but that is a separate file the host wires in;
  it is not part of this source.)
- **Transmission**: Not applicable — the source performs no network I/O.
- **Retention**: Not applicable — the view retains only its own subviews
  and the caller-supplied values for its own instance lifetime.

