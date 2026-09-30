<!-- leaf: implement-general-2/rdid-picker--test-vectors · source: rdid-picker.md -->

# RdidPicker

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| T1 | renders-single-command-palette | mount with `open=true` | Exactly one `CommandPalette` rendered, receiving `open`, `onOpenChange`, `query`, `onQueryChange`, one group, `ariaLabel`, `placeholder`, `loading`, `error`, `emptyLabel` |
| T2 | resets-on-close | type "abc", let it resolve, then set `open=false` | `CommandPalette` receives `query===""`, `groups[0].items` equals `[]`, `error===null`, `loading===false` |
| T3 | skips-search-for-empty-query | `open=true`, `query=""` (also: `query="   "`) | `search` not called; `CommandPalette` receives `groups[0].items` equal to `[]`, `loading===false`, `error===null` |
| T4 | sets-loading-before-debounce-elapses | type "a"; inspect the props passed to `CommandPalette` before `debounceMs` elapses | `CommandPalette` receives `loading===true` |
| T5 | debounces-search-call | type "a", "ab", "abc" within `debounceMs`, then wait past it | `search` called exactly once, with `"abc"` |
| T6 | debounces-search-call | type `"  abc "` (leading and trailing whitespace) as the final value within `debounceMs`, then wait past it | `search` called exactly once, with `"abc"` (trimmed), never `"  abc "` |
| T7 | aborts-superseded-search | type "ab"; before `debounceMs` elapses, type "abc" | the "ab" debounce timer is cleared and never invokes `search`; `search` is ultimately invoked once, for "abc" |
| T8 | aborts-superseded-search | type "ab"; wait until its debounced call invokes `search` but before it settles; then type "abc" | the "ab" call's `AbortSignal.aborted===true` |
| T9 | ignores-aborted-search-results | resolve the aborted "ab" call's promise from T8 after "abc" is in flight | the `loading`/`error`/`groups[0].items` props passed to `CommandPalette` are unaffected by the "ab" settlement |
| T10 | populates-options-on-success | `search` resolves with `[{rdid:"r1",entityType:"ecosystem",entityId:"e1"}]` | `CommandPalette` receives `groups[0].items` containing one item with id `"r1"`, label `"r1"`, badge `"ecosystem"`; `error===null`; `loading===false` |
| T11 | surfaces-search-rejection | `search` rejects with `new Error("boom")` | `CommandPalette` receives `error==="boom"`; `groups[0].items` equal to `[]`; `loading===false` |
| T12 | surfaces-search-rejection | `search` rejects with a non-`Error` value | `CommandPalette` receives `error==="Search failed"` |
| T13 | calls-latest-search-implementation | re-render with a new `search` function identity, `query` unchanged, then let the pending call fire | the most recently supplied `search` function is the one invoked |
| T14 | passes-full-option-to-onPick | select the result `{rdid:"r1",entityType:"ecosystem",entityId:"e1"}` | `onPick` called with that whole object |
| T15 | closes-on-pick | select any result | `onOpenChange(false)` is called (by `CommandPalette`'s `run()`) before/independent of `onPick` handling; the picker closes |
| T16 | labels-group-by-entity-type | `entityTypeLabel="ecosystem"` | group label reads "ecosystem addresses" |
| T17 | labels-group-by-entity-type | no `entityTypeLabel` | group label reads "Addresses" |
| T18 | derives-default-placeholder | `entityTypeLabel="ecosystem"`, no `placeholder` | placeholder reads "Search ecosystem addresses…" |
| T19 | derives-default-placeholder | no `entityTypeLabel`, no `placeholder` | placeholder reads "Search addresses…" |
| T20 | derives-empty-label-from-query | `query=""` | `emptyLabel` reads "Start typing an address" |
| T21 | derives-empty-label-from-query | non-empty `query`, zero results | `emptyLabel` reads "No matching address" |
| T22 | defaults-title-and-aria-label | no `title` prop | `CommandPalette` receives `ariaLabel==="Choose an address"` |
| T23 | renders-each-result-by-rdid-with-badge | option `{rdid:"r1",entityType:"ecosystem",entityId:"e1"}` | rendered item id is "r1", label is "r1", badge is "ecosystem" |
| T24 | aborts-superseded-search, resets-on-close | open, type "ab", close before `debounceMs` elapses, then reopen before `debounceMs` (measured from the "ab" keystroke) elapses | `search` is never called with "ab"; no stale call from the first session reaches `search` in the reopened session |
