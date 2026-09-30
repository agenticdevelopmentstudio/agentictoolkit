<!-- leaf: implement-status-web-hooks/use-edge-lock--part-2 · source: status-web-hooks-use-edge-lock.md -->

# useEdgeLock — continued (part 2)

## Platform Notes

- **SwiftUI**: Start from `ScrollView` with `ScrollPosition` / `.defaultScrollAnchor(.bottom)` and `onScrollGeometryChange(for:)` to track `contentSize.height - containerSize.height - contentOffset.y` as `dist`. `onGeometryChange` covers the container-resize lock. SwiftUI's bottom anchor handles resizes for you, but the 24 pt follow-slack rule and the "leave a scrolled-away reader put" rule still have to be written by hand.
- **Compose**: Start from `LazyColumn` with `LazyListState` (or `Modifier.verticalScroll(ScrollState)`). `reverseLayout = true` gives a bottom-anchored list. Get `dist` from `layoutInfo` / `ScrollState.maxValue - value`. Follow new items in a `LaunchedEffect(newestKey, count)` that calls `scrollToItem` when `dist <= 24.dp`. `onSizeChanged` replaces `ResizeObserver`.
- **React/Web**: This is the source, `packages/web/packages/status-web/src/hooks/use-edge-lock.ts`, with its test file `use-edge-lock.test.ts` next to it. Web specifics: a passive `scroll` listener, `ResizeObserver` guarded by `typeof` for SSR, `useLayoutEffect` so the item pin happens before paint, a per-render identity-check attach effect instead of a dependency array, and the CSS `margin-top: auto` bottom-anchor contract.
- **AppKit / UIKit**: Start from `NSScrollView` (observe `NSView.boundsDidChangeNotification` on the `contentView`, with `postsBoundsChangedNotifications = true`) or `UIScrollView` with `scrollViewDidScroll`. Put the resize lock in `layout()` / `layoutSubviews()` or `viewDidLayoutSubviews`. Remember AppKit's flipped coordinates when working out bottom distance. UIKit uses `contentSize.height - bounds.height - contentOffset.y`.
- **WinUI 3**: Start from `ScrollViewer` (or the newer `ScrollView`) wrapping an `ItemsRepeater` / `ListView` bound to an `ObservableCollection<T>`. Compute `dist` as `ScrollableHeight - VerticalOffset` for the bottom edge and `VerticalOffset` for the top. Handle `ViewChanged` for scroll tracking (`IsIntermediate` separates in-flight from settled scrolls), and `SizeChanged` on the `ScrollViewer` for the resize lock, restoring with `ChangeView(null, ScrollableHeight - dist, null, disableAnimation: true)`. Follow new items from `CollectionChanged` (or `ItemsRepeater.ElementPrepared`), deferring the pin with `DispatcherQueue.TryEnqueue` or `LayoutUpdated` so it runs after layout, which stands in for `useLayoutEffect`. `ListView` has `ItemsStackPanel.ItemsUpdatingScrollMode="KeepLastItemInView"`, which gives unconditional tail-follow. It has no 24 px slack and does not leave a scrolled-away reader put, so write the slack rule by hand. Bottom-anchor underfull content with `VerticalAlignment="Bottom"` on the items host. Everything runs on the UI thread, as in the source. No `Task`/`async` is needed.

## Design Decisions

**Decision**: The resize lock keeps `dist` exactly and unconditionally, with no pinned flag.
**Rationale**: The doc comment says this replaced an earlier "re-pin only while pinned" rule. That rule's hidden flag was cleared by any wheel notch or keyboard-nav `scrollIntoView`, so the lock held only some of the time.
**Approved**: pending

**Decision**: Item-change follow uses a 24 px slack (`PIN_SLACK_PX`), and the resize lock uses none.
**Rationale**: For item changes, "resting on the edge" needs some tolerance so that small nudges still tail new content. For resizes, the exact distance is the contract, so the row at the edge stays at the edge.
**Approved**: pending

**Decision**: A scroll event with changed geometry adopts the new geometry but keeps `dist`, instead of being dropped.
**Rationale**: The source comment and regression test EL-1 say that dropping these events "permanently wedged the tracker" after any content-height change with no scroll event, which let new items yank a scrolled-up reader to the bottom.
**Approved**: pending

**Decision**: `Tracked` is tagged with the element it was measured on, and every new element is pinned fresh.
**Rationale**: Regression test EL-2 covers this. When a filter empties the list, the caller swaps in an empty-state node. The remounted list has to rest on its own edge, not apply the dead node's distance.
**Approved**: pending

**Decision**: The attach effect has no dependency array and returns early on the same element.
**Rationale**: The source comment says a poll/SSE tick that only bumps `count` should cost one ref comparison, instead of rebuilding the observer, whose fresh `observe()` would rewrite `scrollTop` for no reason.
**Approved**: pending

**Decision**: No prepend compensation.
**Rationale**: The sole consumer is a fixed-window store that never pages older history in above the reader. Applying a scroll delta on a filtered-list swap corrupted the reader's place (regression test "filtered under them").
**Approved**: pending
