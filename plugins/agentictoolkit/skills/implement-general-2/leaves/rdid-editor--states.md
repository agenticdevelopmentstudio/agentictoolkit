<!-- leaf: implement-general-2/rdid-editor--states · source: rdid-editor.md -->

# RdidEditor

## States

| State | Appearance change |
|-------|------------------|
| Default (no prefix) | Label + full-width input; no footnote |
| Prefix mode | Static `<code>` prefix, `shrink-0`, before the input |
| Hint shown | Footnote renders `hint`, styled by the shared `FieldFootnote` component |
| Error shown | Footnote renders `error` in place of `hint`, styled by `FieldFootnote`; input gains `aria-invalid`, with its invalid border/ring supplied by the shared `Input` shell |
| Focused | Input gains its focus ring, supplied by the shared `Input` shell |
| Disabled | Input gains its disabled styling, supplied by the shared `Input` shell |
| Pressed | Not applicable: a text input has no discrete pressed visual state — pointer-down produces focus, not a press. |
| Loading | Not applicable: the source contains no async operation or loading flag; `RdidEditor` is a synchronous, controlled view. |
