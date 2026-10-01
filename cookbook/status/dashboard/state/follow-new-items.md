---
id: b0a16326-b88d-426d-a879-080284e541b4
title: Follow New Items
domain: agentictoolkit://cookbook/status/dashboard/state/follow-new-items
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Behavior that keeps a scrolling list pinned to its newest edge while the
  reader rests there, and holds their row in place once they scroll away.
platforms:
- typescript
- web
tags: []
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Follow New Items

## Overview

Follow New Items gives a scrolling list the classic "tail" behavior. While the viewport rests at the edge where the newest row is rendered (within `PIN_SLACK_PX` = 24 px), every change to the rendered list and every resize of the scroll container re-pins the viewport to that edge, so a newly inserted row stays in view wherever in the order it lands. Once the reader scrolls away from the edge they are left alone, and rows inserted above a scrolled-away viewport do not move the row they are reading: the behavior measures that row (the "anchor") and compensates the scroll offset by exactly the distance it shifted.

The concept also defines an at-edge predicate: a pure function that decides whether a container rests at a given edge. Follow New Items produces no return value; its only effects are writes to the scroll container's scroll offset. In the status board it is used by the activity panel and by the shared pane shell, which passes no keys when following is switched off.

## Behavioral Requirements

### The at-edge predicate

- **at-edge-signature**: The at-edge predicate MUST take a geometry snapshot with numeric content size, viewport size and scroll offset, an `edge` of `"top"` or `"bottom"`, and an optional `slack` in pixels, and MUST return a boolean.
- **at-edge-default-slack**: When `slack` is omitted, the predicate MUST use `PIN_SLACK_PX`, which is 24.
- **at-edge-bottom**: For `edge === "bottom"`, the predicate MUST return true exactly when `contentSize - viewportSize - scrollOffset <= slack`.
- **at-edge-top**: For `edge === "top"`, the predicate MUST return true exactly when `scrollOffset <= slack`.
- **at-edge-inclusive**: The slack comparison MUST be inclusive: a distance equal to `slack` counts as at the edge.
- **at-edge-purity**: The predicate MUST read only its arguments and MUST NOT touch the container or any other state.

### Behavior contract

- **hook-signature**: Follow New Items MUST accept a reference to the scroll container (or none), an `edge` of `"top"` or `"bottom"`, a `newestKey` (a string or none), an optional `oldestKey` (a string or none, defaulting to none) and an optional numeric `count` (defaulting to `0`).
- **hook-return**: Follow New Items MUST produce no return value; its only observable output is the container's scroll offset.
- **edge-meaning**: `edge` MUST name the edge at which the caller renders the NEWEST row: `"bottom"` for oldest-to-newest (chat-log) order, `"top"` for newest-first order.
- **head-key**: Follow New Items MUST treat `newestKey` as the key of the row at the top of the list when `edge` is `"top"`, and `oldestKey` as that key when `edge` is `"bottom"` (the "head key").
- **list-change-trigger**: The list-change pass MUST run after every update in which any of the container reference, `edge`, `newestKey`, `oldestKey`, the head key or `count` changed.
- **count-insert-trigger**: A change to `count` alone, with both keys unchanged, MUST trigger the list-change pass, so an insert in the middle of the list is followed.
- **null-container**: When the caller's container reference is none, both the listener setup and the list-change pass MUST do nothing.
- **row-order-precondition**: The container's direct children are the rows; per this concept's documentation the caller MUST render them stacked top-to-bottom in list order, so their bottom edges increase monotonically.

### Pinned state

- **pinned-initial**: The pinned state MUST start true on first attach, so a freshly attached list snaps to its edge on the first list-change pass.
- **pinned-on-scroll**: On every scroll change of the container, Follow New Items MUST set the pinned state to the at-edge predicate's result for that container and edge with the default 24 px slack.
- **scroll-listener-passive**: Monitoring scroll position MUST NOT interfere with or block the platform's own handling of the scroll.
- **scroll-reanchor**: On every scroll change, Follow New Items MUST re-measure the anchor.

### Anchor measurement

- **anchor-definition**: The anchor MUST be the first row in the container whose bounding box bottom is greater than the container's bounding box top, together with its offset (row top minus container top).
- **anchor-empty**: When no row satisfies that condition (no children, or no layout so every measurement is zero), the anchor MUST be none.
- **anchor-binary-search**: The anchor search MUST find the partition point by binary search over the rows, reading a logarithmic number of measurements, and MUST NOT write layout between reads.

### List-change pass

- **pass-timing**: The list-change pass MUST run synchronously after the rendered rows update and before the next paint.
- **repin-when-pinned**: While pinned, the pass MUST set the scroll offset to `contentSize` for `edge === "bottom"` and to `0` for `edge === "top"`.
- **repin-wins**: While pinned, re-pinning MUST take precedence over anchoring, even when a held anchor exists.
- **anchor-compensation**: While not pinned, when the held anchor row is still present and is still a descendant of the container, the pass MUST add to the scroll offset the anchor row's current offset from the container's top minus its recorded offset.
- **anchor-zero-shift**: When that shift is exactly 0, the pass MUST NOT write the scroll offset.
- **anchor-capped-list**: Anchor compensation MUST hold the reader's row even when a row arriving at the top is matched by a row leaving the bottom, so the container's total content size does not change.
- **fallback-growth**: While not pinned and with no usable anchor, the pass MUST add `contentSize - previousContentSize` to the scroll offset only when the head key is non-none, a previous head key has been recorded, and the head key differs from the previous one.
- **fallback-far-end**: When only the far-end key changes (the key that is not the head key), the fallback MUST NOT move the scroll offset.
- **fallback-first-pass**: On the first list-change pass after attach no previous head key exists, so the fallback MUST NOT fire.
- **pass-bookkeeping**: At the end of every pass that has a container, Follow New Items MUST record the current head key and content size as the previous values.
- **pass-reanchor**: At the end of every pass that has a container, Follow New Items MUST re-measure the anchor.

### Resize handling

- **resize-observer**: When resize notifications are available in the runtime, Follow New Items MUST observe the container for size changes.
- **resize-repin**: On a container resize while pinned, Follow New Items MUST set the scroll offset to `contentSize` for `"bottom"` or `0` for `"top"`.
- **resize-leave-unpinned**: On a container resize while not pinned, Follow New Items MUST NOT change the scroll offset.
- **resize-reanchor**: On every container resize, Follow New Items MUST re-measure the anchor.
- **resize-absent**: When resize notifications are unavailable, Follow New Items MUST skip resize handling and MUST NOT throw.

### Lifecycle and ordering

- **listener-deps**: The scroll listener and resize observation MUST be (re)attached whenever the container reference, `edge` or `count` changes, so the listeners attach once a conditionally rendered container appears.
- **listener-cleanup**: Before re-attaching and when the behavior is removed, Follow New Items MUST remove the scroll listener and disconnect the resize observation.
- **single-thread**: All reads and writes MUST happen on a single execution thread; scroll changes, resize notifications and the list-change pass cannot interleave, so their ordering is the order the runtime dispatches them.
- **no-persistence**: Follow New Items MUST keep pinned state, anchor, previous head key and previous content size in memory for the behavior's lifetime only, and MUST NOT persist any of them.
- **no-network**: Follow New Items MUST NOT perform network, storage, logging or timer side effects.

## Appearance

Not applicable — this is a scroll-behavior concept, not a visual component.

## States

Not applicable — this is a scroll-behavior concept, not a visual component.

## Accessibility

Not applicable — this is a scroll-behavior concept, not a visual component.

## Conformance Test Vectors

Vectors 001–008 exercise the at-edge predicate; 009–020 exercise the full behavior (a mock element with fixed sizes for the fallback path; modelled 100 px rows in a 400 px viewport for the anchored path).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| follow-001 | at-edge-bottom, at-edge-inclusive | Content size 1000, viewport size 400, scroll offset 600, edge `"bottom"` | `true` |
| follow-002 | at-edge-bottom, at-edge-default-slack | Content size 1000, viewport size 400, scroll offset 580, edge `"bottom"` | `true` (20 px within 24) |
| follow-003 | at-edge-bottom | Content size 1000, viewport size 400, scroll offset 560, edge `"bottom"` | `false` (40 px away) |
| follow-004 | at-edge-top | Scroll offset 0, then 20, then 40, edge `"top"` | `true`, `true`, `false` |
| follow-005 | at-edge-bottom, at-edge-top | Content size 400, viewport size 400, scroll offset 0, checked for both edges | `true` for both |
| follow-006 | at-edge-signature, at-edge-inclusive | Content size 1000, viewport size 400, scroll offset 560, edge `"bottom"`, slack 40 | `true` |
| follow-007 | at-edge-signature | Content size 1000, viewport size 400, scroll offset 559, edge `"bottom"`, slack 40 | `false` |
| follow-008 | at-edge-purity | Evaluate the predicate against a plain geometry snapshot with no live container | Returns a boolean; no container access |
| follow-009 | pinned-initial, repin-when-pinned | Attach with `edge "bottom"`, element 1000/400 | Scroll offset is 1000 |
| follow-010 | resize-repin | After 009, set scroll offset to 600 with no scroll change reported, then resize | Scroll offset is 1000 |
| follow-011 | pinned-on-scroll, resize-leave-unpinned | Attach `"bottom"`, set scroll offset 100, report scroll, then resize | Scroll offset stays 100 |
| follow-012 | pinned-initial, resize-repin | Attach with `edge "top"`; then set scroll offset 600 and resize | 0 after attach; 0 after resize |
| follow-013 | repin-when-pinned, head-key | `"top"`, scroll offset 10 plus a scroll report (within slack), update `newest "a"` to `"b"`, `count` 3 to 4 | Scroll offset is 0 |
| follow-014 | fallback-growth | `"top"`, no children, scroll offset 500 plus a scroll report, content size 1000 to 1200, update `newest "a"` to `"b"` | Scroll offset is 700 |
| follow-015 | fallback-far-end | `"top"`, no children, scroll offset 500 plus a scroll report, content size 1000 to 1200, update `oldest "z"` to `"y"` | Scroll offset stays 500 |
| follow-016 | anchor-compensation, anchor-capped-list | 10 rows, `"top"`, scroll offset 500 plus a scroll report (reader on k5); prepend a row and remove the last (content size stays 1000); update `newest "new"`, `count` 10 | Scroll offset is 600; reader still on k5 |
| follow-017 | anchor-compensation | Same as 016 without removing a row; update `count` 11 | Scroll offset is 600; reader on k5 |
| follow-018 | anchor-zero-shift | 10 rows, `"top"`, scroll offset 500 plus a scroll report; append a row at the bottom; update `count` 11 | Scroll offset stays 500; reader on k5 |
| follow-019 | repin-wins | 10 rows, `"top"`, scroll offset 10 plus a scroll report; prepend a row and remove the last; update | Scroll offset is 0; reader on the new row |
| follow-020 | null-container | Attach with the container reference as none | No error; no listener attached; nothing written |
| follow-021 | resize-absent | Attach with resize notifications unavailable, element 1000/400 `"bottom"` | Attach still sets scroll offset 1000; no throw |
| follow-022 | fallback-first-pass, pass-bookkeeping | `"top"`, no children, `newest "a"`, content size 1000; after attach report a scroll at offset 500, then update with the same keys and `count` | Scroll offset stays 500: the head key equals the one recorded on the first pass, so no growth is added |
| follow-023 | count-insert-trigger | Pinned `"bottom"`, update with same keys and `count` 3 to 4 after content size grows to 1200 | Scroll offset is 1200 |
| follow-024 | listener-cleanup | Remove the behavior | Scroll listener removed; resize observation disconnected; later scroll reports do not change pinned state |

## Edge Cases

- **Empty list**: With no rows the anchor MUST be none, so a scrolled-away reader gets only the fallback (gated on the head key changing); a pinned reader MUST still be re-pinned.
- **Container not yet available**: When the list starts empty and its container is rendered conditionally, the container reference is none on the first run; both effects MUST return without work, and the listener setup MUST attach once `count` changes after the container appears.
- **No keys**: When the head key is none (for example the pane shell with following off), the fallback MUST NOT fire; re-pinning while pinned and anchor compensation still MUST apply on passes that run.
- **Non-overflowing list**: A list shorter than its viewport MUST count as at both edges (follow-005), so it stays pinned.
- **Overscroll**: A negative distance to the edge (for example elastic overscroll) MUST count as at the edge, since the comparison is `<= slack`.
- **Anchor row removed**: When the held anchor row is disconnected or no longer inside the container, Follow New Items MUST fall back to total content-size growth gated on the head key; that fallback MUST be accepted as understating the insert when rows also left the far end in the same update, as this concept's documentation states it is correct only "whenever nothing left the far end".
- **No layout available**: With every measurement zero, the anchor MUST be none and only the fallback path MUST run.
- **Change entirely below the reader**: The anchored row's shift is 0, so the scroll offset MUST NOT be written (follow-018).
- **Programmatic re-pin**: A scroll-offset write by the behavior triggers a scroll report that MUST re-evaluate pinned state like any user scroll; a re-pin to the edge leaves the reader pinned.
- **Resize without resize notifications**: Resizes MUST go unhandled; the reader MAY see tail rows slide out of view until the next list change.
- **Edge changed mid-life**: A new `edge` MUST re-attach listeners and re-run the pass; the pinned flag MUST carry over and be re-evaluated on the next scroll report.
- **Concurrent access**: Follow New Items runs on a single execution thread; scroll, resize and list-change-pass callbacks MUST NOT interleave.
- **Errors and offline state**: Follow New Items performs no I/O and raises no errors, so dependency failure and connectivity loss do not apply to it.
- **Cancellation and timeouts**: Follow New Items starts no asynchronous work; removal MUST remove the listener and disconnect the observation, and no timeout exists.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ref` (container reference) | reference to an element, or none | required | The scroll container; its direct children are the rows. |
| `edge` | `"top" \| "bottom"` | required | The edge at which the newest row is rendered. |
| `newestKey` | string or none | required | Key of the newest rendered row; the head key when `edge` is `"top"`. |
| `oldestKey` | string or none | `none` | Key of the oldest rendered row; the head key when `edge` is `"bottom"`. |
| `count` | number | `0` | Number of rendered rows; a change re-runs both effects. |
| `slack` (on the at-edge predicate) | number | `PIN_SLACK_PX` (24) | Pixels from the edge that still count as pinned. |
| `PIN_SLACK_PX` | constant | `24` | Module constant; not configurable from the behavior. |
| Resize notifications facility | runtime global | optional | Enables resize re-pinning when present. |

## Deep Linking

Not applicable: Follow New Items only adjusts a scroll container's offset and has no URL or route.

## Localization

Not applicable: Follow New Items contains no user-facing strings.

## Accessibility Options

Not applicable: Follow New Items reads no reduce-motion, contrast or color preference; its scroll-offset writes are instant jumps, not animations.

## Feature Flags

Not applicable: Follow New Items reads no feature flag; callers such as the shared pane shell switch following off by passing no keys.

## Analytics

Not applicable: Follow New Items emits no analytics events.

## Privacy

Not applicable: Follow New Items reads only element geometry and row keys, and stores or transmits nothing.

## Logging

Not applicable: Follow New Items makes no logging calls.

## Platform Notes

- **SwiftUI**: Start from `ScrollView` with `ScrollViewReader` / `scrollTo(_:anchor:)` or, on macOS 26 / iOS 26, `scrollPosition(id:anchor:)` plus `defaultScrollAnchor(.bottom)`. Pinned state comes from `onScrollGeometryChange` (content size, container size, offset) fed into a port of the at-edge predicate. Holding a scrolled-away row maps to `scrollPosition(id:)` bound to the anchor row's id, which SwiftUI keeps stable across inserts; there is no layout effect, so compensation happens in the scroll-position binding rather than by measuring rects.
- **Compose**: Start from `LazyColumn` with `LazyListState`. Pinned state is `!canScrollForward` (or `firstVisibleItemIndex == 0 && firstVisibleItemScrollOffset <= slack` for a top edge) read in `snapshotFlow`. Re-pin with `scrollToItem`. `LazyColumn` already keeps the first visible item stable across inserts when items carry keys, which replaces the manual anchor math; `reverseLayout = true` is the idiomatic chat-log tail.
- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-follow-new-items.ts`, a `"use client"` hook `useFollowNewItems(ref, edge, newestKey, oldestKey, count)` with `ref: RefObject<HTMLElement | null>`, using `useRef` for pinned/anchor/previous values, `useEffect` for the passive `scroll` listener (`{ passive: true }`) and `ResizeObserver`, and `useLayoutEffect` for the pre-paint compensation. The module also exports the at-edge predicate as `atEdge(m, edge, slack)`, taking a measurement object with numeric `scrollHeight`, `clientHeight` and `scrollTop`. The geometry-snapshot fields used throughout the normative text (`contentSize`, `viewportSize`, `scrollOffset`) correspond to `scrollHeight`, `clientHeight` and `scrollTop`. CSS `overflow-anchor` is an alternative the source does not use; its explicit anchoring works for both edge orders and under capped lists.
- **AppKit / UIKit**: Start from `NSScrollView` observing `NSView.boundsDidChangeNotification` on the clip view, or `UIScrollViewDelegate.scrollViewDidScroll` on `UITableView`/`UICollectionView`. Record the first visible row (`indexPathsForVisibleRows` / `rows(in:)`) and its offset before a reload, then restore `contentOffset` after `layoutIfNeeded()`; that is the equivalent of the list-change pass. Resize re-pinning goes in `viewDidLayoutSubviews` or `NSView.frameDidChangeNotification`.
- **WinUI 3**: Start from a `ScrollViewer` (or `ItemsRepeater` inside one, or a `ListView`) bound to an `ObservableCollection<T>`. Track pinned state in the `ScrollViewer.ViewChanged` handler using `VerticalOffset`, `ExtentHeight` and `ViewportHeight` (the port of scroll offset, content size, viewport size). Re-pin with `ChangeView(null, ScrollableHeight, null, disableAnimation: true)` or `ChangeView(null, 0, ...)`; there is no pre-paint layout effect, so do it in `LayoutUpdated` or after `UpdateLayout()` following the `CollectionChanged` event. For held-row anchoring, `ItemsStackPanel.ItemsUpdatingScrollMode` (`KeepItemsInView`, `KeepLastItemInView`, `KeepScrollOffset`) and `ScrollViewer.VerticalAnchorRatio` / `UIElement.CanBeScrollAnchor` cover the uncapped cases natively; for the capped-list case, record the first realized container (`ContainerFromIndex`) and its `TransformToVisual(scrollViewer)` offset, then correct by its shift. Replace the resize observer with the `SizeChanged` event. Everything runs on the UI thread's `DispatcherQueue`, matching the single-threaded source.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-follow-new-items.ts` |

## Design Decisions

**Decision**: Compensate a scrolled-away reader by the anchored row's own shift, not by the container's total content-size growth.

**Rationale**: Activity is server-capped at `MAX_ACTIVITY_ROWS`, so on a full list each row arriving at the top drops one off the bottom; the total delta then reads about 0 while a whole row was inserted above the reader, sliding them up by a row every update.

**Approved**: pending

---

**Decision**: Keep a measurement-free fallback (total content-size growth, gated on the head key changing).

**Rationale**: When the reader's row has left the list, or the environment does no layout, there is no row to measure; total growth is correct whenever nothing left the far end, and the head-key gate stops growth at the far end from moving anyone.

**Approved**: pending

---

**Decision**: Choose the head key from `edge` rather than always watching `oldestKey`.

**Rationale**: Only growth at the top of the list moves a scrolled-away reader; for a newest-first list the top row is the newest, so hard-coding `oldestKey` watched the bottom row, whose growth needs no compensation.

**Approved**: pending

---

**Decision**: Re-run on `count` as well as the end keys.

**Rationale**: An insert in the middle (a completed deploy next to an in-flight build) changes neither end; `count` changing is what makes the tail follow it, and it also re-attaches listeners once a conditionally rendered container appears, since a reference alone does not re-trigger effects.

**Approved**: pending

---

**Decision**: Find the anchor by binary search.

**Rationale**: With history pages loaded above the live page, the row count is unbounded; a linear scan cost thousands of forced-layout reads per scroll event, while the rows' monotonic bottoms make the first row past the top a partition point found in a logarithmic number of reads from one layout.

**Approved**: pending

---

**Decision**: Re-pin on container resize while pinned, using resize notifications.

**Rationale**: Dragging a surrounding split changes the viewport without changing the rendered list, so the list-change pass never runs and the platform leaves the scroll offset put, sliding the tail rows out of view.

**Approved**: pending

---

**Decision**: A 24 px slack (`PIN_SLACK_PX`) counts as pinned.

**Rationale**: Small nudges (a filter click, a keyboard-driven scroll-into-view) move the viewport a few pixels; within the slack the list keeps tailing, and only a deliberate scroll further away leaves the reader in place.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | performance |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | passed | performance |

The hook owns one concern, scroll following, and splits the pure edge test (`atEdge`) from DOM work so it can be tested alone. `use-follow-new-items.test.ts` covers `atEdge` at and around the slack, resize re-pinning for both edges, the fallback path, and the anchored path including the capped-list rollover. The hook has no failure paths to handle: a missing container or a missing `ResizeObserver` is checked and skipped. The scroll listener is passive, the anchor search reads O(log n) rects without interleaved writes, and all listeners are removed on cleanup, so the hook does no work while the list is idle.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
</content>
