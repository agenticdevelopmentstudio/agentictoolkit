<!-- leaf: implement-general-1/font-chooser-button--states · source: font-chooser-button.md -->

# FontChooserButton

## States

| State | Appearance change |
|-------|------------------|
| Default | Draws `title` in `font` (the current selection converted to `sampleSize`, or the system font if none is chosen). |
| Pressed | Not styled by `FontChooserButton` itself beyond `NSButton`'s native `.momentaryPushIn` bezel feedback; on release, `openFontPanel(_:)` runs and the system font panel opens (see #requirements/font-panel-trigger). |
| Disabled | Not implemented: source never reads or sets `isEnabled`. A caller may set it directly through the inherited `NSButton` property, at which point `NSButton`'s native disabled dimming applies. |
| Focused | Not styled by `FontChooserButton`; any focus ring is `NSButton`'s own native focus appearance. |
| Loading | Not applicable: the component performs no asynchronous work of its own and defines no loading state. |
