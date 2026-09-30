<!-- leaf: implement-extension-host-vs-1/code-api-extension-tree-data-source--edge-cases · source: extension-host-vs-code-api-extension-tree-data-source.md -->

# ExtensionTreeDataSource

**Rules** (cite as `implement-extension-host-vs-1/code-api-extension-tree-data-source--edge-cases#<slug>`):

- `null-empty-input` MUST — parent == nil on children(of:) MUST be read as "give me the roots," not as an error or an empty request (MUST, per …
- `null-empty-input-2` MUST — title == nil and message == nil are both meaningful, non-error values — nil title means "use the manifest name" and nil …
- `concurrent-access` MUST — @MainActor isolation serializes entry into every property access and method call on a conforming instance, but does not …
- `error-states` MUST — no method in this protocol is declared throws; children(of:)'s only channel for any failure is the empty-array answer …

## Edge Cases

- **Null/empty input**: `parent == nil` on `children(of:)` MUST be read as "give me the roots," not as an error or an empty request (MUST, per **children-signature**).
- **Null/empty input**: `title == nil` and `message == nil` are both meaningful, non-error values — `nil` title means "use the manifest name" and `nil` message means "show no banner" — neither MUST be treated as an unset/error state by the caller (MUST, per **title-fallback-semantics**, **message-is-supplementary-banner**).
- **Boundary values**: `children(of:)` answering an empty array for a genuinely childless branch is indistinguishable, at this protocol's boundary, from every failure case in **children-empty-on-failure** — the source documents this as deliberate (see Design Decisions), not a boundary the caller can resolve by inspecting the answer alone.
- **Concurrent access**: `@MainActor` isolation serializes entry into every property access and method call on a conforming instance, but does not serialize the `async` work inside `children(of:)` itself — two concurrent `children(of:)` calls for different parents against the same instance MAY have their underlying provider work interleave, and the protocol declares no de-duplication for two concurrent calls against the *same* parent (a caller that wants that guarantee, as `ExtensionTreeViewController` does, MUST implement it itself; see `agentictoolkit://recipes/extension-tree-view-controller`).
- **Concurrent access**: a `children(of:)` call already awaiting an answer from the outgoing instance when `onProviderReplaced` fires has no protocol-level ordering; its outcome is the conformer's, per `in-flight-request-during-replacement`.
- **Error states**: no method in this protocol is declared `throws`; `children(of:)`'s only channel for any failure is the empty-array answer in **children-empty-on-failure**, and none of `activate(_:)`, `selectionDidChange(to:)`, `visibilityDidChange(to:)`, `didExpand(_:)`, or `didCollapse(_:)` has any failure channel at all — each is a plain, non-throwing notification (MUST, as declared).
- **Offline or disconnected state**: not applicable to this file directly. `children(of:)` is `async` specifically because a provider commonly performs I/O (reading a file, running a process) to answer it, but that I/O happens on the far side of this seam, inside the extension's own `TreeDataProvider` implementation — this protocol declares no network call, no timeout, and no retry of its own; any bound on how long a caller waits is imposed by the caller (`ExtensionTreeViewController`'s 30-second `childrenBudget`, out of this recipe's scope).
