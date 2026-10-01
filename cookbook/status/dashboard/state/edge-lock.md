---
id: 9f84dd73-abbf-4ad5-be6e-f3fb04f941c3
title: Edge Lock
domain: agentictoolkit://cookbook/status/dashboard/state/edge-lock
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Behavior that locks a scrolling list to its top or bottom edge through
  container resizes and follows new items within 24px of that edge.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/state/activity-history
references: []
approved-by: ''
approved-date: ''
---

# Edge Lock

## Overview

Edge Lock is a client-only behavior that keeps a scrolling list locked to one edge of its scroll container. Its documentation names the use case: "a list that sits above a details pane", where whatever touches the locked edge rides that edge through every geometry change.

The behavior handles two concerns, and both read and write one tracked geometry record:

- **Container resizes** (split-divider drags, collapse/expand, window resizes). The container's distance from the locked edge (`dist`) is kept exactly the same, every time, whether the list is resting on the edge or scrolled away from it.
- **Item changes** (`newestKey` / `count`). While the container is within `PIN_SLACK_PX` (24 px) of the locked edge, the list follows new content. A reader scrolled further away than that is left where they are.

Edge Lock produces no return value; it works only through side effects on the container element it is given.

## Behavioral Requirements

### Signature and data shape

- **signature**: Edge Lock MUST be callable with four inputs: a reference to a scroll container element (or none), `edge` (`"top" | "bottom"`), `newestKey` (a string or none), and `count` (a number that defaults to `0`). It MUST produce no return value.
- **tracked-record**: The behavior MUST keep one mutable tracked-geometry record per instance with the fields `element`, `contentSize` (the container's total scrollable size), `viewportSize` (the container's visible size), and `dist` (distance from the locked edge). The record MUST start as `{ element: none, contentSize: 0, viewportSize: 0, dist: 0 }`.
- **dist-bottom**: When `edge` is `"bottom"`, the measurement step MUST compute `dist` as `contentSize - viewportSize - scrollOffset`.
- **dist-top**: When `edge` is `"top"`, the measurement step MUST compute `dist` as `scrollOffset`.
- **pin-bottom**: When `edge` is `"bottom"`, the pin operation MUST set the scroll offset to `max(0, contentSize - viewportSize)`.
- **pin-top**: When `edge` is `"top"`, the pin operation MUST set the scroll offset to `0`.
- **no-rendered-output**: The behavior MUST NOT hold state that triggers a screen update on change; all of its bookkeeping lives in internally-held mutable fields (the tracked record and the current detach operation).

### Attaching to the scroll element

- **attach-per-render-check**: The attach step MUST re-check its target on every update, not only when specific inputs change.
- **attach-identity-guard**: The attach step MUST return early without re-wiring when the caller's current container element is the one already stored in the tracked record's `element` field and a detach operation exists.
- **attach-replace**: When the caller's current container element differs from the tracked element, the attach step MUST first run the previous detach operation (if any), which removes the old scroll listener and disconnects the old resize observer.
- **attach-null-element**: When the caller's current container element is none, the attach step MUST reset the tracked record to `{ element: none, contentSize: 0, viewportSize: 0, dist: 0 }` and attach nothing.
- **scroll-listener-passive**: The behavior MUST monitor scroll-position changes on the element without interfering with or blocking the platform's own handling of the scroll.
- **fresh-element-pin**: Once monitoring is attached to a new element, the behavior MUST pin that element to its edge with the pin operation and then set the tracked record from a fresh measurement. This rests a fresh list on its edge and throws away any distance measured on a previous element.
- **unmount-teardown**: A separate teardown step MUST run the detach operation exactly once, when the behavior is removed, and clear it. The attach step itself performs no cleanup on each run, so nothing is torn down while the behavior remains active.

### Scroll tracking

- **pure-scroll-records-dist**: When a scroll change is reported and the element's `contentSize` and `viewportSize` both equal the tracked values, the behavior MUST replace the tracked record with a fresh measurement, which records the user's new `dist`.
- **geometry-changed-scroll-keeps-dist**: When a scroll change is reported and either `contentSize` or `viewportSize` differs from the tracked values, the behavior MUST adopt the new `contentSize` and `viewportSize` but keep the previously tracked `dist`.

### Resize lock

- **resize-observer-attach**: When resize notifications are available in the runtime, the behavior MUST subscribe to them for the scroll element.
- **resize-bottom-restores-dist**: On a resize notification with `edge` `"bottom"`, the behavior MUST set the scroll offset to `max(0, contentSize - viewportSize - tracked dist)`.
- **resize-top-no-write**: On a resize notification with `edge` `"top"`, the behavior MUST NOT write the scroll offset.
- **resize-resync**: After every resize notification, the behavior MUST set the tracked record from a fresh measurement, so the tracked `dist` matches the position the platform actually allowed, including any clamping.
- **resize-unconditional**: The resize lock MUST apply whatever the current `dist` is. It has no slack threshold and no "only while pinned" condition.
- **resize-observer-absent**: When resize notifications are unavailable, the behavior MUST still attach the scroll listener and do the fresh-element pin, and MUST skip the resize lock.

### Item-change follow

- **item-effect-timing**: The item-change handler MUST run synchronously after the container updates for that change and before the next paint, whenever the container reference, `edge`, `newestKey` or `count` changes.
- **item-effect-identity-guard**: The item-change handler MUST do nothing when the caller's current container element is none or is not the element stored in the tracked record.
- **item-follow-within-slack**: When the tracked `dist` is less than or equal to `PIN_SLACK_PX` (24), the item-change handler MUST run the pin operation.
- **item-leave-reader-put**: When the tracked `dist` is greater than 24, the item-change handler MUST NOT change the scroll offset.
- **item-resync**: After every item-change handler run that passes the identity guard, the behavior MUST set the tracked record from a fresh measurement.
- **no-prepend-compensation**: The behavior MUST NOT shift the scroll offset to make up for content inserted above the visible area. This concept's guidance notes there is "no prepend compensation" because the sole consumer is a fixed-window store, and a scroll delta applied to a filtered-list swap corrupted the reader's place.

### Ordering and concurrency

- **main-thread-only**: Every read and write happens on a single execution thread, inside the behavior's own callbacks. Operations therefore never interleave, and the behavior MUST NOT need locking.
- **mount-order**: On the update where an element first appears, the item-change handler runs before the attach step. The item-change handler MUST skip, because the element is not tracked yet, and the attach step MUST then pin the element.
- **edge-change-while-mounted**: `edge` is effectively fixed for the life of an element. The scroll and resize monitoring capture `edge` when they are wired and are re-wired only when the element identity changes, while the item-change handler reads the current `edge`; if a caller changes `edge` while the same element stays mounted, the scroll and resize handling keep measuring `dist` from the old edge. No consumer in the reference implementation uses Edge Lock outside its test, and none toggles `edge`. A port that needs a switchable edge re-wires the handlers when `edge` changes.

### Caller preconditions

- **css-bottom-anchor**: For a bottom-locked list, the caller MUST anchor short content to the bottom in layout (a flex column, with the row block pushed to the end). This concept's guidance states this as the layout contract, because no scroll position can close the gap an underfull list leaves above the container's bottom edge.
- **item-signal**: To trigger item-change follow, the caller MUST change `newestKey` or `count`. A height change with neither of these and no container resize MUST NOT trigger a pin.

## Appearance

Not applicable — this is a non-visual scroll-behavior concept, not a visual component.

## States

Not applicable — this is a non-visual scroll-behavior concept, not a visual component.

## Accessibility

Not applicable — this is a non-visual scroll-behavior concept, not a visual component.

## Conformance Test Vectors

Vectors 001–008 come from the reference implementation's test assertions, using a mock resize observer and an element whose scroll offset is clamped to `[0, contentSize - viewportSize]`. Vectors 009–012 are traced to the source directly.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| edge-lock-001 | fresh-element-pin, pin-bottom | Element with `contentSize` 1000 and `viewportSize` 400; mount with `edge` `"bottom"`, `newestKey` `"newest"`, `count` 3 | Scroll offset is 600 |
| edge-lock-002 | resize-bottom-restores-dist, resize-unconditional | 001 mounted (dist 0); `viewportSize` set to 300; resize reported | Scroll offset is 700 |
| edge-lock-003 | pure-scroll-records-dist, resize-bottom-restores-dist, resize-resync | 001 mounted; user scrolls to 100 (dist 500); `viewportSize` set to 300 and resize reported; then `viewportSize` set back to 400 and resize reported | Scroll offset is 200 after the first resize and 100 after the second |
| edge-lock-004 | item-follow-within-slack | 001 mounted with `newestKey` `"a"`; user scrolls to 580 (dist 20); `contentSize` set to 1100; update with `newestKey` `"b"`, `count` 4 | Scroll offset is 700 |
| edge-lock-005 | item-leave-reader-put | 001 mounted; user scrolls to 100 (dist 500); `contentSize` set to 1100; update with `newestKey` `"b"`, `count` 4 | Scroll offset stays 100 |
| edge-lock-006 | no-prepend-compensation, item-leave-reader-put | Mounted with `newestKey` `"z"`, `count` 9; user scrolls to 100; `contentSize` set to 700; update with `newestKey` `"y"`, `count` 4 | Scroll offset stays 100 |
| edge-lock-007 | geometry-changed-scroll-keeps-dist, pure-scroll-records-dist, item-signal | 001 mounted (scroll offset 600); `contentSize` set to 1100 with no scroll change reported; user scrolls to 500, then to 200 (dist 500); `contentSize` set to 1200; update with `newestKey` `"b"`, `count` 4 | Scroll offset stays 200 |
| edge-lock-008 | attach-replace, attach-null-element, fresh-element-pin | Mounted on element A (1000/400); user scrolls A to 100; container reference set to none and updated; container reference set to new element B (800/400) and updated | B's scroll offset is 400 |
| edge-lock-009 | pin-top, fresh-element-pin | Element with scroll offset 300; mount with `edge` `"top"` | Scroll offset is 0; tracked `dist` is 0 |
| edge-lock-010 | resize-top-no-write, resize-resync | `edge` `"top"`, user scrolled to 150; resize reported | The behavior does not write the scroll offset; tracked `dist` equals the platform's scroll offset (150 unless the platform clamped it) |
| edge-lock-011 | resize-observer-absent | Resize notifications unavailable; mount a bottom-locked element (1000/400) | Scroll offset is 600; no observer is created; a later resize changes nothing |
| edge-lock-012 | item-follow-within-slack | Bottom edge, dist exactly 24; update with a new `count` after `contentSize` grows by 100 | The element is pinned to the tail (24 is inside the slack, since the comparison is `<=`) |

## Edge Cases

- **No container element at mount**: If the caller's container reference is none, the behavior MUST attach nothing, MUST keep the tracked record at its zero values, and the item-change handler MUST do nothing. Nothing is thrown.
- **Element swapped for an empty-state node and back**: Detaching when the element becomes none, then wiring the new element and pinning it, MUST rest the new element on its own edge without carrying over the old distance (edge-lock-008).
- **Underfull list, bottom edge**: When `contentSize <= viewportSize`, the pin operation MUST set the scroll offset to 0 (the zero floor). Any visual bottom alignment is the caller's layout job (css-bottom-anchor).
- **Resize grows past the remaining scroll range**: When restoring `dist` asks for a negative scroll offset, the behavior MUST write 0 and then re-measure. The smaller `dist` the platform allowed becomes the value the next resize restores.
- **Content grows in place with no scroll or resize**: The tracked geometry goes stale until the next scroll change. That change MUST adopt the new geometry and keep `dist` (geometry-changed-scroll-keeps-dist), so later scrolls are recorded again (edge-lock-007).
- **Platform clamps scroll during a resize**: A scroll change caused by a clamp arrives with changed geometry. It MUST NOT overwrite `dist`. The resize notification re-asserts `dist`.
- **Slack boundary**: `dist` of 24 MUST follow new items. `dist` of 25 MUST NOT.
- **Negative dist**: If the scroll offset goes past its valid range, `dist` can come out negative. That is still `<= 24`, so the list follows. The behavior does not clamp `dist`.
- **Frequent `count` ticks (poll/stream)**: An update that only changes `count` MUST cost one identity check in the attach step (no re-wiring). It MUST run the item-change handler once.
- **Resize notifications unavailable (older runtime, server-side rendering)**: The resize lock is skipped entirely (resize-observer-absent). Scroll tracking and item follow still work.
- **Concurrent access**: Not applicable. Everything runs on a single execution thread (main-thread-only).
- **Errors and offline**: Not applicable. The behavior does no I/O, network or storage work, and none of its geometry reads or writes throw on a valid element.
- **Cancellation and timeouts**: The behavior starts no asynchronous work, so nothing needs cancelling. Unmount teardown removes the listener and disconnects the observer (unmount-teardown).
- **`edge` changed mid-life**: The scroll and resize handling keep the old edge until the element changes; see `edge-change-while-mounted`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ref` (container reference) | reference to an element, or none | required | The scroll container. Its identity decides when listeners are re-wired. |
| `edge` | `"top" \| "bottom"` | required | The edge the list is locked to. |
| `newestKey` | string or none | required | Key of the newest item. A change triggers the item-change handler. |
| `count` | number | `0` | Item count. A change triggers the item-change handler, so an insert anywhere in the list counts. |
| `PIN_SLACK_PX` | constant | `24` | How far from the edge, in px, still counts as resting on it for item changes. Not configurable by the caller. |

No environment variables, settings keys or injected dependencies. The behavior reads the runtime's resize-notification facility if one exists.

## Deep Linking

Not applicable: the behavior only adjusts scroll position on a caller-supplied element and defines no routes or URLs.

## Localization

Not applicable: the behavior has no user-facing strings.

## Accessibility Options

Not applicable: the behavior reads no reduce-motion, contrast or color preference, and its scroll-offset writes are instant assignments, not animations.

## Feature Flags

Not applicable: the behavior reads no flags. It is always on for any caller that uses it.

## Analytics

Not applicable: the behavior emits no events.

## Privacy

Not applicable: the behavior reads only element scroll geometry and does not collect, store or send any data.

## Logging

Not applicable: the behavior has no log calls. No code path in it logs, throws or reports anything.

## Platform Notes

- **SwiftUI**: Start from `ScrollView` with `ScrollPosition` / `.defaultScrollAnchor(.bottom)` and `onScrollGeometryChange(for:)` to track `contentSize.height - containerSize.height - contentOffset.y` as `dist`. `onGeometryChange` covers the container-resize lock. SwiftUI's bottom anchor handles resizes for you, but the 24 pt follow-slack rule and the "leave a scrolled-away reader put" rule still have to be written by hand.
- **Compose**: Start from `LazyColumn` with `LazyListState` (or `Modifier.verticalScroll(ScrollState)`). `reverseLayout = true` gives a bottom-anchored list. Get `dist` from `layoutInfo` / `ScrollState.maxValue - value`. Follow new items in a `LaunchedEffect(newestKey, count)` that calls `scrollToItem` when `dist <= 24.dp`. `onSizeChanged` replaces the resize observer.
- **React/Web**: This is the source, `packages/web/packages/status-web/src/hooks/use-edge-lock.ts`, with its test file `use-edge-lock.test.ts` next to it. It is a client-only React hook (`"use client"`), callable as `useEdgeLock(ref, edge, newestKey, count = 0)` where `ref` is `RefObject<HTMLElement | null>`. Web specifics: a passive `scroll` event listener (`{ passive: true }`), `ResizeObserver` guarded by `typeof` for server-side rendering, `useLayoutEffect` so the item pin happens before paint, a per-render identity-check attach effect with no dependency array instead of one, and the CSS `margin-top: auto` bottom-anchor contract. The tracked record's DOM-facing fields are `el` (`HTMLElement | null`), `scrollHeight` (content size), `clientHeight` (viewport size) and `dist`; `scrollTop` is the scroll offset. All bookkeeping lives in refs (`tracked`, `detach`) rather than component state, so nothing here causes a re-render. Only its test file imports it in the reference repository.
- **AppKit / UIKit**: Start from `NSScrollView` (observe `NSView.boundsDidChangeNotification` on the `contentView`, with `postsBoundsChangedNotifications = true`) or `UIScrollView` with `scrollViewDidScroll`. Put the resize lock in `layout()` / `layoutSubviews()` or `viewDidLayoutSubviews`. Remember AppKit's flipped coordinates when working out bottom distance. UIKit uses `contentSize.height - bounds.height - contentOffset.y`.
- **WinUI 3**: Start from `ScrollViewer` (or the newer `ScrollView`) wrapping an `ItemsRepeater` / `ListView` bound to an `ObservableCollection<T>`. Compute `dist` as `ScrollableHeight - VerticalOffset` for the bottom edge and `VerticalOffset` for the top. Handle `ViewChanged` for scroll tracking (`IsIntermediate` separates in-flight from settled scrolls), and `SizeChanged` on the `ScrollViewer` for the resize lock, restoring with `ChangeView(null, ScrollableHeight - dist, null, disableAnimation: true)`. Follow new items from `CollectionChanged` (or `ItemsRepeater.ElementPrepared`), deferring the pin with `DispatcherQueue.TryEnqueue` or `LayoutUpdated` so it runs after layout, which stands in for `useLayoutEffect`. `ListView` has `ItemsStackPanel.ItemsUpdatingScrollMode="KeepLastItemInView"`, which gives unconditional tail-follow. It has no 24 px slack and does not leave a scrolled-away reader put, so write the slack rule by hand. Bottom-anchor underfull content with `VerticalAlignment="Bottom"` on the items host. Everything runs on the UI thread, as in the source. No `Task`/`async` is needed.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-edge-lock.ts` |

## Design Decisions

**Decision**: The resize lock keeps `dist` exactly and unconditionally, with no pinned flag.
**Rationale**: This concept's guidance says this replaced an earlier "re-pin only while pinned" rule. That rule's hidden flag was cleared by any wheel notch or keyboard-nav scroll-into-view, so the lock held only some of the time.
**Approved**: pending

**Decision**: Item-change follow uses a 24 px slack (`PIN_SLACK_PX`), and the resize lock uses none.
**Rationale**: For item changes, "resting on the edge" needs some tolerance so that small nudges still tail new content. For resizes, the exact distance is the contract, so the row at the edge stays at the edge.
**Approved**: pending

**Decision**: A scroll change with changed geometry adopts the new geometry but keeps `dist`, instead of being dropped.
**Rationale**: The source comment and regression test EL-1 say that dropping these events "permanently wedged the tracker" after any content-height change with no scroll event, which let new items yank a scrolled-up reader to the bottom.
**Approved**: pending

**Decision**: The tracked record is tagged with the element it was measured on, and every new element is pinned fresh.
**Rationale**: Regression test EL-2 covers this. When a filter empties the list, the caller swaps in an empty-state node. The remounted list has to rest on its own edge, not apply the dead node's distance.
**Approved**: pending

**Decision**: The attach step (web platform: the attach effect) has no dependency array and returns early on the same element.
**Rationale**: The source comment says a poll/stream tick that only bumps `count` should cost one identity comparison, instead of rebuilding the observer, whose fresh subscription would rewrite the scroll offset for no reason.
**Approved**: pending

**Decision**: No prepend compensation.
**Rationale**: The sole consumer is a fixed-window store that never pages older history in above the reader. Applying a scroll delta on a filtered-list swap corrupted the reader's place (regression test "filtered under them").
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | passed | performance |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | partial | reliability |

The hook does one job, scroll-edge locking, and it touches only the DOM element it is given. `use-edge-lock.test.ts` covers mount, both resize directions, follow within the slack, leaving a reader put, the filtered-list regression, and both EL-1 and EL-2. It degrades gracefully when `ResizeObserver` is absent. It avoids re-wiring on every render and removes its listeners on unmount. State recovery is partial: element swaps reset cleanly, but a change to `edge` while the same element stays mounted leaves the scroll and resize handlers measuring from the old edge. That residual is described in `edge-change-while-mounted`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
</content>
