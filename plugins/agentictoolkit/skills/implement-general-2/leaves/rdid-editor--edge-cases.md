<!-- leaf: implement-general-2/rdid-editor--edge-cases · source: rdid-editor.md -->

# RdidEditor

**Rules** (cite as `implement-general-2/rdid-editor--edge-cases#<slug>`):

- `empty-value` MUST (`value=""`) — renders the input empty; this is an ordinary controlled-value state, not a special case in the source (MUST, per …
- `empty-prefix` MUST (`prefix=""`) — renders one full-width input with the whole rdid editable, per the component's own doc comment ("An empty string …
- `boundary-values` MUST — not enforced by this component. RdidEditor imports neither SEGMENT_RE nor IDENTIFIER_MAX_LENGTH from rdid.ts; it relies …
- `mixed-case-paste` MUST — pasting ACME-Org into the input fires the same onChange handler as typing, so the full pasted value is lowercased …

## Edge Cases

- **Empty `value`** (`value=""`): renders the input empty; this is an ordinary
  controlled-value state, not a special case in the source (MUST, per
  `displays-controlled-value`).
- **Empty `prefix`** (`prefix=""`): renders one full-width input with the whole
  rdid editable, per the component's own doc comment ("An empty string renders a
  single full-width input") (MUST, per `renders-single-input-without-prefix`).
- **Boundary values (leaf length/character set)**: not enforced by this
  component. `RdidEditor` imports neither `SEGMENT_RE` nor
  `IDENTIFIER_MAX_LENGTH` from `rdid.ts`; it relies entirely on the
  caller-supplied `error` (typically derived externally via `validateLeaf`) to
  signal an invalid or over-length leaf (MUST, per `shows-error-in-place-of-hint`
  — the component's only lever over invalid input is displaying what it is
  told).
- **Mixed-case paste**: pasting `ACME-Org` into the input fires the same
  `onChange` handler as typing, so the full pasted value is lowercased before
  `onChange` is called, not just newly typed characters (MUST, per
  `lowercases-input-on-change`).
- **Uppercase character typed mid-value**: typing an uppercase letter in the
  middle of an already-lowercase value (e.g. inserting `A` into `acme` to get
  `aAcme`) still lowercases the whole value on the same `onChange` event (per
  `lowercases-input-on-change`); because the resulting controlled value differs
  from what the browser just wrote into the DOM, React resyncs the input's DOM
  value on the next render and the caret moves to the end of the field rather
  than staying at the edit point.
- **Concurrent access**: not applicable — `RdidEditor` is a stateless, purely
  controlled view. It holds no value state of its own and performs no I/O, so
  there is no shared state for concurrent renders or events to race on.
- **Error states (dependency/network failure)**: not applicable — the source
  makes no network or storage calls; its only "error" is the caller-supplied
  `error` prop, which is a display concern already covered under Behavioral
  Requirements, not a failure of a dependency this component owns.
- **Offline/disconnected state**: not applicable — the component performs no
  network operation of its own.
- **Caller-supplied `id` collision**: if a caller passes an `id` that collides
  with another element's `id` elsewhere in the DOM, the component does not
  detect or guard against it — no such check exists in the source. Avoiding
  collisions is the caller's responsibility.
