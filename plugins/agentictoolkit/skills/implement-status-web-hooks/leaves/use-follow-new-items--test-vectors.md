<!-- leaf: implement-status-web-hooks/use-follow-new-items--test-vectors · source: status-web-hooks-use-follow-new-items.md -->

# useFollowNewItems

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
