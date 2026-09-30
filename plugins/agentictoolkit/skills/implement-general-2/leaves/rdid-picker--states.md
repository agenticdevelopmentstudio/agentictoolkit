<!-- leaf: implement-general-2/rdid-picker--states · source: rdid-picker.md -->

# RdidPicker

## States

| State | Appearance change |
|-------|------------------|
| Closed (`open=false`) | `CommandPalette` not shown; internal `query`/`options`/`error`/`loading` are reset |
| Open, query empty | `emptyLabel` reads "Start typing an address"; `loading=false`, `error=null`, `options=[]` |
| Open, query non-empty, debounce/search pending | `loading=true` passed to `CommandPalette` (shown beside any still-displayed prior `options`, per `CommandPalette`'s own loading treatment) |
| Open, search resolved with results | `options` populated; each renders as a group item keyed by `rdid` |
| Open, search resolved with zero results | `options=[]`; `emptyLabel` reads "No matching address" |
| Open, search rejected | `error` set to the rejection message (or "Search failed"); `options=[]`; `loading=false` |
