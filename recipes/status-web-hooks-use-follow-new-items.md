---
id: b0a16326-b88d-426d-a879-080284e541b4
title: useFollowNewItems
domain: agentictoolkit://recipes/status-web-hooks-use-follow-new-items
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook that keeps a scrolling list pinned to its newest edge while the
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

# useFollowNewItems

## Overview

`useFollowNewItems` gives a scrolling list the classic "tail" behavior. While the viewport rests at the edge where the newest row is rendered (within `PIN_SLACK_PX` = 24 px), every change to the rendered list and every resize of the scroll container re-pins the viewport to that edge, so a newly inserted row stays in view wherever in the order it lands. Once the reader scrolls away from the edge they are left alone, and rows inserted above a scrolled-away viewport do not move the row they are reading: the hook measures that row (the "anchor") and compensates `scrollTop` by exactly the distance it shifted.

The module also exports `atEdge`, the pure predicate that decides whether an element rests at a given edge. The hook returns nothing; its only effects are writes to the scroll container's `scrollTop`. In the status board it is used by `ActivityPanel` and by `PaneShell`, which passes `null` keys when following is switched off.

## Behavioral Requirements

### atEdge

- **at-edge-signature**: `atEdge(m, edge, slack)` MUST take a measurement object with numeric `scrollHeight`, `clientHeight` and `scrollTop`, an `edge` of `"top"` or `"bottom"`, and an optional `slack` in pixels, and MUST return a boolean.
- **at-edge-default-slack**: When `slack` is omitted, `atEdge` MUST use `PIN_SLACK_PX`, which is 24.
- **at-edge-bottom**: For `edge === "bottom"`, `atEdge` MUST return true exactly when `scrollHeight - clientHeight - scrollTop <= slack`.
- **at-edge-top**: For `edge === "top"`, `atEdge` MUST return true exactly when `scrollTop <= slack`.
- **at-edge-inclusive**: The slack comparison MUST be inclusive: a distance equal to `slack` counts as at the edge.
- **at-edge-purity**: `atEdge` MUST read only its arguments and MUST NOT touch the DOM or any other state.

### Hook contract

- **hook-signature**: `useFollowNewItems(ref, edge, newestKey, oldestKey, count)` MUST accept a ref to the scroll container (`RefObject<HTMLElement | null>`), an `edge` of `"top"` or `"bottom"`, a `newestKey` of type `string | null`, an optional `oldestKey` of type `string | null` (default `null`) and an optional numeric `count` (default `0`).
- **hook-return**: The hook MUST return `void`; its only observable output is the container's `scrollTop`.
- **edge-meaning**: `edge` MUST name the edge at which the caller renders the NEWEST row: `"bottom"` for oldest-to-newest (chat-log) order, `"top"` for newest-first order.
- **head-key**: The hook MUST treat `newestKey` as the key of the row at the top of the list when `edge` is `"top"`, and `oldestKey` as that key when `edge` is `"bottom"` (the "head key").
- **list-change-trigger**: The list-change pass MUST run after every render in which any of `ref`, `edge`, `newestKey`, `oldestKey`, the head key or `count` changed.
- **count-insert-trigger**: A change to `count` alone, with both keys unchanged, MUST trigger the list-change pass, so an insert in the middle of the list is followed.
- **null-container**: When `ref.current` is null, both the listener setup and the list-change pass MUST do nothing.
- **row-order-precondition**: The container's direct children are the rows; per the `measureAnchor` doc comment the caller MUST render them in document order in a block flow, so their bottom edges increase monotonically.

### Pinned state

- **pinned-initial**: The pinned state MUST start true on mount, so a freshly mounted list snaps to its edge on the first list-change pass.
- **pinned-on-scroll**: On every `scroll` event of the container, the hook MUST set the pinned state to `atEdge(container, edge)` with the default 24 px slack.
- **scroll-listener-passive**: The `scroll` listener MUST be registered as passive.
- **scroll-reanchor**: On every `scroll` event, the hook MUST re-measure the anchor.

### Anchor measurement

- **anchor-definition**: The anchor MUST be the first direct child of the container whose bounding-rect bottom is greater than the container's bounding-rect top, together with its offset (row top minus container top).
- **anchor-empty**: When no child satisfies that condition (no children, or no layout so every rect is zero), the anchor MUST be null.
- **anchor-binary-search**: The anchor search MUST find the partition point by binary search over the children, reading O(log n) rects, and MUST NOT write layout between reads.

### List-change pass (layout effect)

- **pass-timing**: The list-change pass MUST run synchronously after the DOM update and before the browser paints.
- **repin-when-pinned**: While pinned, the pass MUST set `scrollTop` to `scrollHeight` for `edge === "bottom"` and to `0` for `edge === "top"`.
- **repin-wins**: While pinned, re-pinning MUST take precedence over anchoring, even when a held anchor exists.
- **anchor-compensation**: While not pinned, when the held anchor row is still connected and is still a descendant of the container, the pass MUST add to `scrollTop` the anchor row's current offset from the container's top minus its recorded offset.
- **anchor-zero-shift**: When that shift is exactly 0, the pass MUST NOT write `scrollTop`.
- **anchor-capped-list**: Anchor compensation MUST hold the reader's row even when a row arriving at the top is matched by a row leaving the bottom, so the container's total height does not change.
- **fallback-growth**: While not pinned and with no usable anchor, the pass MUST add `scrollHeight - previousScrollHeight` to `scrollTop` only when the head key is non-null, a previous head key has been recorded, and the head key differs from the previous one.
- **fallback-far-end**: When only the far-end key changes (the key that is not the head key), the fallback MUST NOT move `scrollTop`.
- **fallback-first-pass**: On the first list-change pass after mount no previous head key exists, so the fallback MUST NOT fire.
- **pass-bookkeeping**: At the end of every pass that has a container, the hook MUST record the current head key and `scrollHeight` as the previous values.
- **pass-reanchor**: At the end of every pass that has a container, the hook MUST re-measure the anchor.

### Resize handling

- **resize-observer**: When `ResizeObserver` exists in the environment, the hook MUST observe the container for size changes.
- **resize-repin**: On a container resize while pinned, the hook MUST set `scrollTop` to `scrollHeight` for `"bottom"` or `0` for `"top"`.
- **resize-leave-unpinned**: On a container resize while not pinned, the hook MUST NOT change `scrollTop`.
- **resize-reanchor**: On every container resize, the hook MUST re-measure the anchor.
- **resize-absent**: When `ResizeObserver` is undefined, the hook MUST skip resize handling and MUST NOT throw.

### Lifecycle and ordering

- **listener-deps**: The scroll listener and resize observer MUST be (re)attached whenever `ref`, `edge` or `count` changes, so the listeners attach once a conditionally rendered container mounts.
- **listener-cleanup**: Before re-attaching and on unmount, the hook MUST remove the `scroll` listener and disconnect the resize observer.
- **single-thread**: All reads and writes MUST happen on the browser main thread; scroll events, resize callbacks and the layout effect cannot interleave, so their ordering is the order the browser dispatches them.
- **no-persistence**: The hook MUST keep pinned state, anchor, previous head key and previous height in memory for the component's lifetime only, and MUST NOT persist any of them.
- **no-network**: The hook MUST NOT perform network, storage, logging or timer side effects.

## Appearance

Not applicable — this is a scroll-behavior React hook, not a visual component.

## States

Not applicable — this is a scroll-behavior React hook, not a visual component.

## Accessibility

Not applicable — this is a scroll-behavior React hook, not a visual component.

## Conformance Test Vectors

Vectors 001–008 come from the `atEdge` cases in `use-follow-new-items.test.ts`; 009–020 come from its hook cases (a mock element with fixed heights for the fallback path; modelled 100 px rows in a 400 px viewport for the anchored path).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| follow-001 | at-edge-bottom, at-edge-inclusive | `atEdge({scrollHeight: 1000, clientHeight: 400, scrollTop: 600}, "bottom")` | `true` |
| follow-002 | at-edge-bottom, at-edge-default-slack | `atEdge({scrollHeight: 1000, clientHeight: 400, scrollTop: 580}, "bottom")` | `true` (20 px within 24) |
| follow-003 | at-edge-bottom | `atEdge({scrollHeight: 1000, clientHeight: 400, scrollTop: 560}, "bottom")` | `false` (40 px away) |
| follow-004 | at-edge-top | `atEdge` with `scrollTop` 0, then 20, then 40, edge `"top"` | `true`, `true`, `false` |
| follow-005 | at-edge-bottom, at-edge-top | `atEdge({scrollHeight: 400, clientHeight: 400, scrollTop: 0}, e)` for `e` = `"bottom"` and `"top"` | `true` for both |
| follow-006 | at-edge-signature, at-edge-inclusive | `atEdge({scrollHeight: 1000, clientHeight: 400, scrollTop: 560}, "bottom", 40)` | `true` |
| follow-007 | at-edge-signature | `atEdge({scrollHeight: 1000, clientHeight: 400, scrollTop: 559}, "bottom", 40)` | `false` |
| follow-008 | at-edge-purity | Call `atEdge` with a plain object (no DOM) | Returns a boolean; no DOM access |
| follow-009 | pinned-initial, repin-when-pinned | Mount with `edge "bottom"`, element 1000/400 | `scrollTop` is 1000 |
| follow-010 | resize-repin | After 009, set `scrollTop` to 600 with no scroll event, fire resize | `scrollTop` is 1000 |
| follow-011 | pinned-on-scroll, resize-leave-unpinned | Mount `"bottom"`, set `scrollTop` 100, dispatch `scroll`, fire resize | `scrollTop` stays 100 |
| follow-012 | pinned-initial, resize-repin | Mount with `edge "top"`; then set `scrollTop` 600 and fire resize | 0 after mount; 0 after resize |
| follow-013 | repin-when-pinned, head-key | `"top"`, `scrollTop` 10 plus `scroll` event (within slack), rerender `newest "a"` to `"b"`, `count` 3 to 4 | `scrollTop` is 0 |
| follow-014 | fallback-growth | `"top"`, no children, `scrollTop` 500 plus `scroll`, `scrollHeight` 1000 to 1200, rerender `newest "a"` to `"b"` | `scrollTop` is 700 |
| follow-015 | fallback-far-end | `"top"`, no children, `scrollTop` 500 plus `scroll`, `scrollHeight` 1000 to 1200, rerender `oldest "z"` to `"y"` | `scrollTop` stays 500 |
| follow-016 | anchor-compensation, anchor-capped-list | 10 rows, `"top"`, `scrollTop` 500 plus `scroll` (reader on k5); prepend a row and remove the last (height stays 1000); rerender `newest "new"`, `count` 10 | `scrollTop` is 600; reader still on k5 |
| follow-017 | anchor-compensation | Same as 016 without removing a row; rerender `count` 11 | `scrollTop` is 600; reader on k5 |
| follow-018 | anchor-zero-shift | 10 rows, `"top"`, `scrollTop` 500 plus `scroll`; append a row at the bottom; rerender `count` 11 | `scrollTop` stays 500; reader on k5 |
| follow-019 | repin-wins | 10 rows, `"top"`, `scrollTop` 10 plus `scroll`; prepend a row and remove the last; rerender | `scrollTop` is 0; reader on the new row |
| follow-020 | null-container | Mount with `ref.current = null` | No error; no listener attached; nothing written |
| follow-021 | resize-absent | Mount with `ResizeObserver` undefined, element 1000/400 `"bottom"` | Mount still sets `scrollTop` 1000; no throw |
| follow-022 | fallback-first-pass, pass-bookkeeping | `"top"`, no children, `newest "a"`, `scrollHeight` 1000; after mount dispatch `scroll` at `scrollTop` 500, then rerender with the same keys and `count` | `scrollTop` stays 500: the head key equals the one recorded on the first pass, so no growth is added |
| follow-023 | count-insert-trigger | Pinned `"bottom"`, rerender with same keys and `count` 3 to 4 after `scrollHeight` grows to 1200 | `scrollTop` is 1200 |
| follow-024 | listener-cleanup | Unmount the hook | `scroll` listener removed; resize observer disconnected; later scroll events do not change pinned state |

## Edge Cases

- **Empty list**: With no rows the anchor MUST be null, so a scrolled-away reader gets only the fallback (gated on the head key changing); a pinned reader MUST still be re-pinned.
- **Container not yet mounted**: When the list starts empty and its container is rendered conditionally, `ref.current` is null on the first run; both effects MUST return without work, and the listener effect MUST attach once `count` changes after the container mounts.
- **Null keys**: When the head key is null (for example `PaneShell` with following off), the fallback MUST NOT fire; re-pinning while pinned and anchor compensation still MUST apply on passes that run.
- **Non-overflowing list**: A list shorter than its viewport MUST count as at both edges (follow-005), so it stays pinned.
- **Overscroll**: A negative distance to the edge (for example elastic overscroll) MUST count as at the edge, since the comparison is `<= slack`.
- **Anchor row removed**: When the held anchor row is disconnected or no longer inside the container, the hook MUST fall back to total `scrollHeight` growth gated on the head key; that fallback MUST be accepted as understating the insert when rows also left the far end in the same update, as the source comment states it is correct only "whenever nothing left the far end".
- **No layout (jsdom)**: With every rect zero, the anchor MUST be null and only the fallback path MUST run.
- **Change entirely below the reader**: The anchored row's shift is 0, so `scrollTop` MUST NOT be written (follow-018).
- **Programmatic re-pin**: A `scrollTop` write by the hook dispatches a `scroll` event that MUST re-evaluate pinned state like any user scroll; a re-pin to the edge leaves the reader pinned.
- **Resize without `ResizeObserver`**: Resizes MUST go unhandled; the reader MAY see tail rows slide out of view until the next list change.
- **Edge changed mid-life**: A new `edge` MUST re-attach listeners and re-run the pass; the pinned flag MUST carry over and be re-evaluated on the next scroll event.
- **Concurrent access**: The hook runs on the single-threaded browser main thread; scroll, resize and layout-effect callbacks MUST NOT interleave.
- **Errors and offline state**: The hook performs no I/O and raises no errors, so dependency failure and connectivity loss do not apply to it.
- **Cancellation and timeouts**: The hook starts no asynchronous work; unmount MUST remove the listener and disconnect the observer, and no timeout exists.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ref` | `RefObject<HTMLElement \| null>` | required | The scroll container; its direct children are the rows. |
| `edge` | `"top" \| "bottom"` | required | The edge at which the newest row is rendered. |
| `newestKey` | `string \| null` | required | Key of the newest rendered row; the head key when `edge` is `"top"`. |
| `oldestKey` | `string \| null` | `null` | Key of the oldest rendered row; the head key when `edge` is `"bottom"`. |
| `count` | `number` | `0` | Number of rendered rows; a change re-runs both effects. |
| `slack` (on `atEdge`) | `number` | `PIN_SLACK_PX` (24) | Pixels from the edge that still count as pinned. |
| `PIN_SLACK_PX` | constant | `24` | Module constant; not configurable from the hook. |
| `ResizeObserver` | environment global | optional | Enables resize re-pinning when present. |

## Deep Linking

Not applicable: the hook only adjusts a scroll container's `scrollTop` and has no URL or route.

## Localization

Not applicable: the hook contains no user-facing strings.

## Accessibility Options

Not applicable: the hook reads no reduce-motion, contrast or color preference; its `scrollTop` writes are instant jumps, not animations.

## Feature Flags

Not applicable: the hook reads no feature flag; callers such as `PaneShell` switch following off by passing `null` keys.

## Analytics

Not applicable: the hook emits no analytics events.

## Privacy

Not applicable: the hook reads only element geometry and row keys, and stores or transmits nothing.

## Logging

Not applicable: the hook makes no logging calls.

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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
