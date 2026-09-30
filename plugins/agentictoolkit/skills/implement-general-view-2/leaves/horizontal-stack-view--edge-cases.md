<!-- leaf: implement-general-view-2/horizontal-stack-view--edge-cases · source: horizontal-stack-view.md -->

# Horizontal Stack View

## Edge Cases

- **Null/empty input**: Not applicable — `addArrangedSubview(_:)`'s parameter is a non-optional `NSView`; Swift's type system rejects a `nil` argument at compile time. The parameterless `convenience init()` and the inherited `init(frame:)` (whose argument is discarded, see **ignores-explicit-frame**) leave no other caller-supplied value that could be null or empty. Calling `addArrangedSubview(_:)` zero times is a valid, un-special-cased path: the internal stack view's `arrangedSubviews` stays empty and the component collapses to whatever intrinsic size an empty `NSStackView` resolves to.
- **Boundary values**: `SettingsLayout.default[.groupSpacing]` (see **group-spacing**) is read exactly once, into `stackView.spacing`, at `init` time. `SettingsLayout` is `Observable`/`@Published`, but `HorizontalStackView` never subscribes to it, so if a caller mutates `SettingsLayout.default`'s underlying value after a `HorizontalStackView` instance already exists, that instance's spacing does not update — it stays at whatever `.groupSpacing` was when it was constructed. This is the same staleness pattern documented for the sibling `DividerView` and `VerticalStackView` wrappers.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`, so construction and every mutation path (`addArrangedSubview`) are serialized to the main actor by the Swift compiler.
- **Error states**: Not applicable — `HorizontalStackView` has no dependency on network, database, or file-system access, and the source shows no error path of any kind.
- **Offline/disconnected state**: Not applicable — `HorizontalStackView` performs no networking.
- **No removal API**: `addArrangedSubview(_:)` is the only mutation entry point the source exposes; there is no `removeArrangedSubview` or equivalent. Once a view is added, the source itself provides no supported way to remove it again through this wrapper — a caller would have to reach the internal stack view's `arrangedSubviews` directly (which it cannot, since `stackView` is `private`) or remove the child view from its superview.
