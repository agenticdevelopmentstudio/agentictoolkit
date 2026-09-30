<!-- leaf: implement-general-view-1/disclosure-card-view--states · source: disclosure-card-view.md -->

# DisclosureCardView

## States

| State | Appearance change |
|-------|------------------|
| Default (expanded, `isCollapsed: false`) | Titlebar strip and the full content area are drawn; subtitle text shown if `subtitle` is non-nil; summary line hidden; disclosure `state = .on`, tooltip/label "Hide details" |
| Collapsed (`isCollapsed: true`) | Content area hidden; subtitle text forced hidden regardless of `subtitle`; summary line shown, right-aligned, if `summary` is non-empty; if `summary` is also empty, the body section is entirely hidden and the card renders as exactly its titlebar; disclosure `state = .off`, tooltip/label "Show details" |
| Dimmed (`isDimmed: true`) | Whole view `alphaValue = 0.55`; no separate dimmed color set is used — every color the card draws is unchanged, only faded uniformly |
| Pressed | Not applicable beyond the embedded disclosure `NSButton`'s own native pressed bezel: `DisclosureCardView` itself has no target/action or tracking area of its own and draws no custom pressed appearance. |
| Focused | Not applicable: `DisclosureCardView` never overrides `acceptsFirstResponder` or focus-ring drawing; the only focusable subview is the disclosure `NSButton`, which gets AppKit's own standard focus ring. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |
