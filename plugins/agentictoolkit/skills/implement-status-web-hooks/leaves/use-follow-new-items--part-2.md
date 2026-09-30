<!-- leaf: implement-status-web-hooks/use-follow-new-items--part-2 · source: status-web-hooks-use-follow-new-items.md -->

# useFollowNewItems — continued (part 2)

## Platform Notes

- **SwiftUI**: Start from `ScrollView` with `ScrollViewReader` / `scrollTo(_:anchor:)` or, on macOS 26 / iOS 26, `scrollPosition(id:anchor:)` plus `defaultScrollAnchor(.bottom)`. Pinned state comes from `onScrollGeometryChange` (content size, container size, offset) fed into a port of `atEdge`. Holding a scrolled-away row maps to `scrollPosition(id:)` bound to the anchor row's id, which SwiftUI keeps stable across inserts; there is no layout effect, so compensation happens in the scroll-position binding rather than by measuring rects.
- **Compose**: Start from `LazyColumn` with `LazyListState`. Pinned state is `!canScrollForward` (or `firstVisibleItemIndex == 0 && firstVisibleItemScrollOffset <= slack` for a top edge) read in `snapshotFlow`. Re-pin with `scrollToItem`. `LazyColumn` already keeps the first visible item stable across inserts when items carry `key`s, which replaces the manual anchor math; `reverseLayout = true` is the idiomatic chat-log tail.
- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-follow-new-items.ts`, a `"use client"` hook using `useRef` for pinned/anchor/previous values, `useEffect` for the passive `scroll` listener and `ResizeObserver`, and `useLayoutEffect` for the pre-paint compensation. CSS `overflow-anchor` is an alternative the source does not use; its explicit anchoring works for both edge orders and under capped lists.
- **AppKit / UIKit**: Start from `NSScrollView` observing `NSView.boundsDidChangeNotification` on the clip view, or `UIScrollViewDelegate.scrollViewDidScroll` on `UITableView`/`UICollectionView`. Record the first visible row (`indexPathsForVisibleRows` / `rows(in:)`) and its offset before a reload, then restore `contentOffset` after `layoutIfNeeded()`; that is the equivalent of the layout effect. Resize re-pinning goes in `viewDidLayoutSubviews` or `NSView.frameDidChangeNotification`.
- **WinUI 3**: Start from a `ScrollViewer` (or `ItemsRepeater` inside one, or a `ListView`) bound to an `ObservableCollection<T>`. Track pinned state in the `ScrollViewer.ViewChanged` handler using `VerticalOffset`, `ExtentHeight` and `ViewportHeight` (the port of `scrollTop`, `scrollHeight`, `clientHeight`). Re-pin with `ChangeView(null, ScrollableHeight, null, disableAnimation: true)` or `ChangeView(null, 0, ...)`; there is no pre-paint layout effect, so do it in `LayoutUpdated` or after `UpdateLayout()` following the `CollectionChanged` event. For held-row anchoring, `ItemsStackPanel.ItemsUpdatingScrollMode` (`KeepItemsInView`, `KeepLastItemInView`, `KeepScrollOffset`) and `ScrollViewer.VerticalAnchorRatio` / `UIElement.CanBeScrollAnchor` cover the uncapped cases natively; for the capped-list case, record the first realized container (`ContainerFromIndex`) and its `TransformToVisual(scrollViewer)` offset, then correct by its shift. Replace `ResizeObserver` with the `SizeChanged` event. Everything runs on the UI thread's `DispatcherQueue`, matching the single-threaded source.

## Design Decisions

**Decision**: Compensate a scrolled-away reader by the anchored row's own shift, not by the container's total height growth.

**Rationale**: Activity is server-capped at `MAX_ACTIVITY_ROWS`, so on a full list each row arriving at the top drops one off the bottom; the total delta then reads about 0 while a whole row was inserted above the reader, sliding them up by a row every update.

**Approved**: pending

---

**Decision**: Keep a measurement-free fallback (total `scrollHeight` growth, gated on the head key changing).

**Rationale**: When the reader's row has left the list, or the environment does no layout (jsdom), there is no row to measure; total growth is correct whenever nothing left the far end, and the head-key gate stops growth at the far end from moving anyone.

**Approved**: pending

---

**Decision**: Choose the head key from `edge` rather than always watching `oldestKey`.

**Rationale**: Only growth at the top of the list moves a scrolled-away reader; for a newest-first list the top row is the newest, so hard-coding `oldestKey` watched the bottom row, whose growth needs no compensation.

**Approved**: pending

---

**Decision**: Re-run on `count` as well as the end keys.

**Rationale**: An insert in the middle (a completed deploy next to an in-flight build) changes neither end; `count` changing is what makes the tail follow it, and it also re-attaches listeners once a conditionally rendered container mounts, since refs do not re-trigger effects.

**Approved**: pending

---

**Decision**: Find the anchor by binary search.

**Rationale**: With history pages loaded above the live page, the row count is unbounded; a linear scan cost thousands of forced-layout reads per scroll event, while the rows' monotonic bottoms make the first row past the top a partition point found in O(log n) reads from one layout.

**Approved**: pending

---

**Decision**: Re-pin on container resize while pinned, using `ResizeObserver`.

**Rationale**: Dragging a surrounding split changes the viewport without changing the rendered list, so the list-change pass never runs and the browser leaves `scrollTop` put, sliding the tail rows out of view.

**Approved**: pending

---

**Decision**: A 24 px slack (`PIN_SLACK_PX`) counts as pinned.

**Rationale**: Small nudges (a filter click, a keyboard `scrollIntoView`) move the viewport a few pixels; within the slack the list keeps tailing, and only a deliberate scroll further away leaves the reader in place.

**Approved**: pending
