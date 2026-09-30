<!-- leaf: implement-status-web-hooks/use-edge-lock · source: status-web-hooks-use-edge-lock.md -->

**Rules** (cite as `implement-status-web-hooks/use-edge-lock#<slug>`):

- `signature` MUST
- `tracked-record` MUST
- `dist-bottom` MUST
- `dist-top` MUST
- `pin-bottom` MUST
- `pin-top` MUST
- `no-rendered-output` MUST
- `attach-per-render-check` MUST
- `attach-identity-guard` MUST
- `attach-replace` MUST
- `attach-null-element` MUST
- `scroll-listener-passive` MUST
- `fresh-element-pin` MUST
- `unmount-teardown` MUST
- `pure-scroll-records-dist` MUST
- `geometry-changed-scroll-keeps-dist` MUST
- `resize-observer-attach` MUST
- `resize-bottom-restores-dist` MUST
- `resize-top-no-write` MUST
- `resize-resync` MUST
- `resize-unconditional` MUST
- `resize-observer-absent` MUST
- `item-effect-timing` MUST
- `item-effect-identity-guard` MUST
- `item-follow-within-slack` MUST
- `item-leave-reader-put` MUST
- `item-resync` MUST
- `no-prepend-compensation` MUST
- `main-thread-only` MUST
- `mount-order` MUST
- `css-bottom-anchor` MUST
- `item-signal` MUST

# useEdgeLock

## Overview

`useEdgeLock` is a client-only React hook (`"use client"`) that keeps a scrolling list locked to one edge of its scroll container. Its doc comment names the use case: "a list that sits above a details pane", where whatever touches the locked edge rides that edge through every geometry change.

The hook handles two concerns, and both read and write one `Tracked` record:

- **Container resizes** (split-divider drags, collapse/expand, window resizes). The viewport's distance from the locked edge (`dist`) is kept exactly the same, every time, whether the list is resting on the edge or scrolled away from it.
- **Item changes** (`newestKey` / `count`). While the viewport is within `PIN_SLACK_PX` (24 px) of the locked edge, the list follows new content. A reader scrolled further away than that is left where they are.

The hook returns nothing. It works only through side effects on the element held in `ref`. In the repo, only its test file (`use-edge-lock.test.ts`) imports it. The doc comment mentions ActivityPanel's list pane as the model for the CSS contract.

## Behavioral Requirements

### Signature and data shape

- **signature**: The hook MUST be callable as `useEdgeLock(ref, edge, newestKey, count = 0)`. `ref` is a `RefObject<HTMLElement | null>`, `edge` is `"top" | "bottom"`, `newestKey` is `string | null`, and `count` is a number that defaults to `0`. It MUST return `void`.
- **tracked-record**: The hook MUST keep one mutable `Tracked` record per hook instance with the fields `el` (`HTMLElement | null`), `scrollHeight`, `clientHeight` and `dist`. The record MUST start as `{ el: null, scrollHeight: 0, clientHeight: 0, dist: 0 }`.
- **dist-bottom**: When `edge` is `"bottom"`, `measure` MUST compute `dist` as `scrollHeight - clientHeight - scrollTop`.
- **dist-top**: When `edge` is `"top"`, `measure` MUST compute `dist` as `scrollTop`.
- **pin-bottom**: When `edge` is `"bottom"`, `pinToEdge` MUST set `scrollTop` to `Math.max(0, scrollHeight - clientHeight)`.
- **pin-top**: When `edge` is `"top"`, `pinToEdge` MUST set `scrollTop` to `0`.
- **no-rendered-output**: The hook MUST NOT hold React state or cause re-renders. All of its bookkeeping lives in refs (`tracked`, `detach`).

### Attaching to the scroll element

- **attach-per-render-check**: The attach effect MUST run after every render (it has no dependency array).
- **attach-identity-guard**: The attach effect MUST return early without re-wiring when `ref.current` is the element already stored in `tracked.current.el` and a `detach` function exists.
- **attach-replace**: When `ref.current` differs from the tracked element, the attach effect MUST first call the previous `detach` function (if any), which removes the old scroll listener and disconnects the old `ResizeObserver`.
- **attach-null-element**: When `ref.current` is `null`, the attach effect MUST reset `tracked` to `{ el: null, scrollHeight: 0, clientHeight: 0, dist: 0 }` and attach nothing.
- **scroll-listener-passive**: The hook MUST add a `scroll` event listener to the element with `{ passive: true }`.
- **fresh-element-pin**: Once the listeners are attached to a new element, the hook MUST pin that element to its edge with `pinToEdge` and then set `tracked` to `measure(el, edge)`. This rests a fresh list on its edge and throws away any distance measured on a previous node.
- **unmount-teardown**: A separate effect with an empty dependency array MUST call `detach` exactly once, on unmount, and clear it. The attach effect itself returns no cleanup, so the hook never tears down while it is mounted.

### Scroll tracking

- **pure-scroll-records-dist**: When a `scroll` event fires and the element's `scrollHeight` and `clientHeight` both equal the tracked values, the hook MUST replace `tracked` with a fresh `measure(el, edge)`, which records the user's new `dist`.
- **geometry-changed-scroll-keeps-dist**: When a `scroll` event fires and either `scrollHeight` or `clientHeight` differs from the tracked values, the hook MUST adopt the new `scrollHeight` and `clientHeight` but keep the previously tracked `dist`.

### Resize lock

- **resize-observer-attach**: When `ResizeObserver` exists in the global scope, the hook MUST create one and observe the scroll element.
- **resize-bottom-restores-dist**: On a `ResizeObserver` callback with `edge` `"bottom"`, the hook MUST set `scrollTop` to `Math.max(0, scrollHeight - clientHeight - tracked.dist)`.
- **resize-top-no-write**: On a `ResizeObserver` callback with `edge` `"top"`, the hook MUST NOT write `scrollTop`.
- **resize-resync**: After every `ResizeObserver` callback, the hook MUST set `tracked` to `measure(el, edge)`, so the tracked `dist` matches the position the browser actually allowed, including any clamping.
- **resize-unconditional**: The resize lock MUST apply whatever the current `dist` is. It has no slack threshold and no "only while pinned" condition.
- **resize-observer-absent**: When `ResizeObserver` is `undefined`, the hook MUST still attach the scroll listener and do the fresh-element pin, and MUST skip the resize lock.

### Item-change follow

- **item-effect-timing**: The item-change handler MUST run as a layout effect, synchronously after DOM mutation and before paint, whenever `ref`, `edge`, `newestKey` or `count` changes.
- **item-effect-identity-guard**: The item-change handler MUST do nothing when `ref.current` is `null` or is not the element stored in `tracked.current.el`.
- **item-follow-within-slack**: When the tracked `dist` is less than or equal to `PIN_SLACK_PX` (24), the item-change handler MUST call `pinToEdge(el, edge)`.
- **item-leave-reader-put**: When the tracked `dist` is greater than 24, the item-change handler MUST NOT change `scrollTop`.
- **item-resync**: After every item-change handler run that passes the identity guard, the hook MUST set `tracked` to `measure(el, edge)`.
- **no-prepend-compensation**: The hook MUST NOT shift `scrollTop` to make up for content inserted above the viewport. The source says there is "no prepend compensation" because the sole consumer is a fixed-window store, and a scroll delta applied to a filtered-list swap corrupted the reader's place.

### Ordering and concurrency

- **main-thread-only**: Every read and write happens on the browser's single JavaScript thread, inside React effects and DOM event or observer callbacks. Operations therefore never interleave, and the hook MUST NOT need locking.
- **mount-order**: On the render where an element first appears, the layout effect runs before the attach effect. The layout effect MUST skip, because the element is not tracked yet, and the attach effect MUST then pin the element.
- **edge-change-while-mounted**: `edge` is effectively fixed for the life of an element. The attach effect's scroll and `ResizeObserver` closures capture `edge` when they are wired and are re-wired only when the element identity changes, while the layout effect reads the current `edge`; if a caller changes `edge` while the same element stays mounted, the scroll and resize handlers keep measuring `dist` from the old edge. No consumer in the repository calls `useEdgeLock` outside its test, and none toggles `edge`. A port that needs a switchable edge re-wires the handlers when `edge` changes.

### Caller preconditions

- **css-bottom-anchor**: For a bottom-locked list, the caller MUST anchor short content to the bottom in layout (a flex column, with the row block wrapped in `margin-top: auto`). The doc comment states this as the CSS contract, because no scroll position can close the gap an underfull list leaves above the container's bottom edge.
- **item-signal**: To trigger item-change follow, the caller MUST change `newestKey` or `count`. A height change with neither of these and no container resize MUST NOT trigger a pin.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ref` | `RefObject<HTMLElement \| null>` | required | The scroll container. Its identity decides when listeners are re-wired. |
| `edge` | `"top" \| "bottom"` | required | The edge the list is locked to. |
| `newestKey` | `string \| null` | required | Key of the newest item. A change triggers the item-change handler. |
| `count` | `number` | `0` | Item count. A change triggers the item-change handler, so an insert anywhere in the list counts. |
| `PIN_SLACK_PX` | module constant | `24` | How far from the edge, in px, still counts as resting on it for item changes. Not configurable by the caller. |

No environment variables, settings keys or injected dependencies. The hook reads the global `ResizeObserver` if one exists.

