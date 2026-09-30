<!-- leaf: implement-extension-host-core-2/extensions-webview-panel-state--edge-cases · source: extension-host-core-extensions-webview-panel-state.md -->

# WebviewPanelState

**Rules** (cite as `implement-extension-host-core-2/extensions-webview-panel-state--edge-cases#<slug>`):

- `null-and-empty-input` MUST — an empty string passed to init(json:) MUST throw, as MUST a state value that is present but is the empty string "" — …
- `boundary-values-the-four-fields-nothing-supplied-cases` MUST — title absent decodes to ""; state absent decodes to nil; options absent decodes to the safe, no-scripts posture; …
- `concurrent-access` MUST — WebviewPanelState and WebviewPanelOptions are both immutable, Sendable value types with no shared mutable storage, so …
- `error-states` MUST — the only two failure paths this file defines are encoded() throwing WebviewPanelStateError.encodedTextIsNotUTF8 (the …
- `downgrade-and-forward-compatibility` MUST — a JSON string written by a newer build that added a field this build does not know about MUST still decode …

## Edge Cases

- **Null and empty input**: an empty string passed to `init(json:)` MUST
  throw, as MUST a `state` value that is present but is the empty string
  `""` — the latter decodes successfully and round-trips, since `state` is
  an opaque string with no defined "empty means absent" rule; only a
  genuinely absent `state` key means absent. MUST.
- **Boundary values — the four fields' "nothing supplied" cases**: `title`
  absent decodes to `""`; `state` absent decodes to `nil`; `options` absent
  decodes to the safe, no-scripts posture; `viewType` absent is the one
  boundary that is refused outright rather than defaulted, because nothing
  can safely stand in for the serializer identity it names. MUST.
- **Concurrent access**: `WebviewPanelState` and `WebviewPanelOptions` are
  both immutable, `Sendable` value types with no shared mutable storage, so
  `encoded()` and `init(json:)` MAY be called concurrently, from any number
  of threads or tasks, against any number of independent values, with no
  synchronization required. This is a property of the type's declared
  immutability, not a marker. MUST.
- **Error states**: the only two failure paths this file defines are
  `encoded()` throwing `WebviewPanelStateError.encodedTextIsNotUTF8` (the
  source's own comment calls this case unreachable in practice, since
  `JSONEncoder` output is UTF-8 by definition of JSON, and states the
  alternative — a force-unwrap — as strictly worse) and `init(json:)`
  propagating whatever `JSONDecoder` throws for malformed or
  under-specified JSON. Neither path is caught or swallowed inside this
  file; both are the caller's to handle. MUST.
- **Offline / disconnected state**: not applicable. This type performs no
  networking of any kind; it only encodes to and decodes from an in-memory
  `String`, so there is no connectivity state to lose mid-operation.
- **Downgrade and forward compatibility**: a JSON string written by a newer
  build that added a field this build does not know about MUST still decode
  (`unknown-fields-ignored`), and a JSON string written by an older build
  that predates `options` MUST decode to the safe posture rather than
  throwing (`missing-options-default-safe`) — both are read-time recovery
  from a schema older or newer than the reader's, stated here because
  neither is a null/empty/boundary case in the ordinary sense. MUST.
