<!-- leaf: implement-general-view-2/mcp-chips-bar-view--states · source: mcp-chips-bar-view.md -->

# MCPChipsBarView

## States

| State | Appearance change |
|-------|------------------|
| Default | Rack icon plus button showing the current computed label; no popover shown. |
| No servers configured | Button text reads "No MCP servers"; if opened, the popover shows the empty-state message instead of any row. |
| Servers configured, none active | Button text reads "MCP: none". |
| Servers configured, some or all active | Button text reads "MCP: {active} of {total}". |
| Picker open | `showingPicker == true`; a popover anchored below the button (`arrowEdge: .bottom`) presents `MCPServerPicker`. |
| Picker closed | `showingPicker == false` (the initial value); no popover is shown. |
| Server row checked/unchecked | A row's `Toggle` shows checked when `viewModel.isActive(id)` is true; tapping it calls `viewModel.toggle(id)`, flipping membership and writing the new set back to the caller's binding. |
| Pressed | Not applicable — `.buttonStyle(.borderless)` is used with no additional pressed-state modifier in source; any momentary highlight is the system borderless-button style's own, not authored here. |
| Disabled | Not applicable — no control in this file (the button or any `Toggle`) is ever given `.disabled(...)`; every control is always interactive. |
| Focused | Not applicable — no `.focused()`/`@FocusState` binding or custom focus-ring styling appears in source; standard system focus-ring behavior for `Button`/`Toggle` is inherited, not authored. |
| Loading | Not applicable — `registry.$clients` (an `@Published` property) delivers its current value synchronously to the `sink` on subscription; source defines no loading/pending indicator. |
