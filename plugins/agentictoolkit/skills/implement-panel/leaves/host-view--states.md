<!-- leaf: implement-panel/host-view--states · source: panel-host-view.md -->

# PanelHostView

## States

| State | Appearance change |
|-------|------------------|
| Help hidden (default) | Help button, if shown, displays the outlined `questionmark.circle` symbol tinted `secondaryTextColor`, tooltip `"Show Help"`. |
| Help visible | Help button displays the filled `questionmark.circle.fill` symbol tinted `accentColor`, tooltip `"Hide Help"`. |
| No presenter / button disabled | Help button is hidden entirely (`isHidden = true`) — see **help-button-visibility**. |
| Pressed | Not applicable: `PanelHostView.swift` defines no custom pressed-state styling for the help button; `NSButton` with `.momentaryChange` supplies AppKit's own built-in momentary highlight, which this source does not override. |
| Disabled | Not applicable: the source never sets `isEnabled` on the help button or on `PanelHostView` itself; there is no disabled-state path in this file. |
| Focused | Not applicable: the source configures no custom focus ring or focused-state appearance; `NSButton`'s default AppKit focus ring applies unmodified. |
| Loading | Not applicable: every operation in `PanelHostView.swift` (content swap, help toggling, theme repaint) is synchronous; the source defines no loading flag, spinner, or placeholder state. |
