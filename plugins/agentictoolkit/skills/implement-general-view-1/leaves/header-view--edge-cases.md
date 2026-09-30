<!-- leaf: implement-general-view-1/header-view--edge-cases · source: header-view.md -->

# Header View

## Edge Cases

- **Null/empty input**: `title` is a required, non-optional `String` parameter with no default value. Passing `""` is valid and produces a `HeaderView` whose `titleLabel.stringValue == ""` — an empty-but-present label with a near-zero intrinsic width. The source has no guard against this and needs none, since a non-optional `String` cannot be null.
- **Boundary values**: Very long `title` strings. Because `titleLabel` sets `usesSingleLineMode = true` and `lineBreakMode = .byClipping` (`ThemedViews.swift`), a title too wide for its container is drawn clipped at the edge, not wrapped or truncated with an ellipsis; `HeaderView` activates no `widthAnchor` of its own, so the label's actual display width is bounded only by whatever ancestor view constrains `HeaderView`'s width.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`, so construction and every property mutation are serialized to the main actor by the Swift compiler.
- **Error states**: Not applicable — `HeaderView` has no dependency on network, database, or file-system access, and the source shows no error path of any kind.
- **Offline/disconnected state**: Not applicable — `HeaderView` performs no networking.
