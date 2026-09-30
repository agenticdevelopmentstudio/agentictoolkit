<!-- leaf: implement-general-2/notes-and-history--test-vectors · source: notes-and-history.md -->

# Notes and History

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| notes-and-history-001 | renders-notes-section, renders-history-section | `notes=[]`, `history=[]`, `notesLoading=false`, `historyLoading=false` | Both an "Admin notes" heading and a "History" heading render as sibling sections in one container |
| notes-and-history-002 | sections-load-independently, notes-loading-indicator | `notesLoading=true`; `history=[oneEntry]`, `historyLoading=false` | Notes section shows "Loading…"; History section shows its populated list, not "Loading…" |
| notes-and-history-003 | sections-load-independently, history-loading-indicator | `historyLoading=true`; `notes=[oneNote]`, `notesLoading=false` | History section shows "Loading…"; Notes section shows its populated list |
| notes-and-history-004 | notes-empty-message | `notesLoading=false`, `notes=[]` | Notes section renders "No admin notes." and no list |
| notes-and-history-005 | history-empty-message | `historyLoading=false`, `history=[]` | History section renders "No history." and no list |
| notes-and-history-006 | notes-list-rendering, preserves-source-order | `notes=[noteA(id:"1"), noteB(id:"2")]`, `notesLoading=false` | Two list items render in array order; the first shows `noteA.content` and "`noteA.author` · `noteA.modifiedDate`"; the second shows `noteB`'s fields |
| notes-and-history-007 | history-list-rendering, preserves-source-order | `history=[entryA(id:"1"), entryB(id:"2")]`, `historyLoading=false` | Two list items render in array order; each reads "`timestamp` — `actor` `action`" |
| notes-and-history-008 | no-internal-data-fetching | Stub `window.fetch` and `XMLHttpRequest` to throw if invoked, then render the component with any valid `notes`/`history`/loading props and re-render it with new props | Both the render and the re-render complete without throwing, and the `fetch`/`XMLHttpRequest` stubs are never called |
| notes-and-history-009 | loading-props-default-to-false | `notesLoading` and `historyLoading` both omitted (`undefined`); `notes=[]`, `history=[]` | Both sections render their empty messages ("No admin notes.", "No history."), not "Loading…" |
