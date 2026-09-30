<!-- leaf: implement-general-view-2/tab-pane-view--states · source: tab-pane-view.md -->

# TabPaneView

## States

| State | Appearance change |
|-------|------------------|
| Default (`stackDepth == 1`, before any caller sets it) | Behind — same as the "Behind, horizontal edge" or "Behind, vertical edge" row below, whichever edge this card is on. |
| Front (`stackDepth == 0`) | Background = `projectPaneBackdrop`, border = `projectPaneOutline`, `agentLabel` = `.accent`, `sessionLabel` = `.primaryText`, the other three labels and the close tint = `.secondaryText`; painted background overhangs the workspace-facing side by `1pt`; text inset = `recession(0)` = `0` — only the paint overhangs. |
| Behind, horizontal edge (`stackDepth > 0`, `.top`/`.bottom`) | Background = `windowBackground`, border = `border`, `agentLabel` = `.primaryText`, the rest and the close tint = `.tertiaryText`; card and text pulled in `4pt` on every side, flat regardless of depth. |
| Behind, vertical edge (`stackDepth` 1–3, `.left`/`.right`) | Same palette as "Behind" above; card and text pulled in `4pt` per step of depth, up to `12pt` at depth `3` and beyond, so deeper cards read visibly smaller and further back. |
| Depth transition (view in a window) | The recolor/reposition above animates over `0.16s` with an `easeOut` curve rather than jumping; off-screen (`window == nil`) it jumps. |
| Pressed | Not applicable: `TabPaneView` overrides no mouse-tracking method and defines no pressed appearance; a click is a hosting view's concern (`TabItemHostView`, documented in the `multi-tabbed-view-controller` recipe), not this view's. |
| Disabled | Not applicable: no `isEnabled`, disabled tint, or disabled appearance is defined anywhere in source; a tab card that exists is always drawn at full strength. |
| Focused | Not applicable: no custom focus-ring or focused appearance is defined; `closeButton`'s `focusRingType` is left at its AppKit default, and no other subview declares `acceptsFirstResponder`. |
| Loading | Not applicable: every operation in this file (`setStatusSymbols`, `reload`-driven property sets, depth changes) is synchronous; source defines no loading/pending indicator. |
