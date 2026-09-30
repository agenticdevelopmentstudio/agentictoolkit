<!-- leaf: implement-general-view-1/group-view--states · source: group-view.md -->

# GroupView

## States

| State | Appearance change |
|-------|------------------|
| Default | The header and `cardView` are added to `outerStack`; `rowStack` starts empty until `addSettingSubview` is called — no rows, no separators. |
| Row added (`.row` style) | A `CardRow` is appended with 9pt padding above and below its content and 14pt padding on each side; whether it also shows a leading hairline is decided separately by `updateSeparators`. |
| Row added (`.continuation` style) | A `CardRow` is appended with 0pt top padding (tucked against the row above) and the same 9pt bottom / 14pt horizontal padding; it never shows a separator. |
| Separator shown | A `.row`-style row with a not-hidden predecessor: `line.isHidden == false`, separator band height = 1pt (`dividerThickness`), inset 14pt from the leading edge. |
| Separator collapsed | The first row in the card, any `.continuation`-style row, or a `.row`-style row with no not-hidden predecessor: `line.isHidden == true`, separator band height = 0pt. |
| Row content hidden | A row's own `isHidden` mirrors its content's `isHidden` (`syncVisibility`); `NSStackView` omits its space, and `updateSeparators` may then collapse the separator on the row that follows it. |
| Pressed | Not applicable: `GroupView`, `cardView`, and `CardRow` define no target/action and receive no press interaction of their own — any pressed styling belongs to a row's caller-supplied content. |
| Disabled | Not implemented in `GroupView.swift`; `isEnabled` is never read or set anywhere in source. |
| Focused | Not styled by `GroupView`; any focus ring belongs to a row's own content, not to the container. |
| Loading | Not applicable: `GroupView` performs no asynchronous operation and shows no loading indicator in source. |
