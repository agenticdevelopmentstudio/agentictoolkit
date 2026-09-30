<!-- leaf: implement-general-1/badge--states · source: badge.md -->

# Badge

## States

| State | Appearance change |
|-------|------------------|
| Default (`style: .filled`, the default for both `init` and `update`) | Solid `color` background; border width 0; label text color computed by `computes-contrasting-text-color` |
| Outlined (`style: .outlined`) | Clear background; 1pt border in `color`; label text color equals `color` |
| Pressed | Not applicable: Badge is a plain `NSView` with no target/action, gesture recognizer, or tracking area in the source — it has no pressed interaction to represent. |
| Disabled | Not applicable: Badge exposes no enabled/disabled API; the source defines no `isEnabled` property or dimmed-appearance logic. |
| Focused | Not applicable: Badge never becomes key/first responder; the source overrides no responder-chain behavior, and `NSView`'s own default (`acceptsFirstResponder == false`) applies unmodified. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |
