<!-- leaf: implement-status-web-hooks/use-edge-lock--test-vectors · source: status-web-hooks-use-edge-lock.md -->

# useEdgeLock

## Conformance Test Vectors

Vectors 001–008 come from the assertions in `use-edge-lock.test.ts`. That test uses a mock `ResizeObserver` and an element whose `scrollTop` is clamped to `[0, scrollHeight - clientHeight]`. Vectors 009–012 are traced to the source directly.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| edge-lock-001 | fresh-element-pin, pin-bottom | Element with `scrollHeight` 1000 and `clientHeight` 400; mount with `edge` `"bottom"`, `newestKey` `"newest"`, `count` 3 | `scrollTop` is 600 |
| edge-lock-002 | resize-bottom-restores-dist, resize-unconditional | 001 mounted (dist 0); `clientHeight` set to 300; resize fired | `scrollTop` is 700 |
| edge-lock-003 | pure-scroll-records-dist, resize-bottom-restores-dist, resize-resync | 001 mounted; user scrolls to 100 (dist 500); `clientHeight` set to 300 and resize fired; then `clientHeight` set back to 400 and resize fired | `scrollTop` is 200 after the first resize and 100 after the second |
| edge-lock-004 | item-follow-within-slack | 001 mounted with `newestKey` `"a"`; user scrolls to 580 (dist 20); `scrollHeight` set to 1100; rerender with `newestKey` `"b"`, `count` 4 | `scrollTop` is 700 |
| edge-lock-005 | item-leave-reader-put | 001 mounted; user scrolls to 100 (dist 500); `scrollHeight` set to 1100; rerender with `newestKey` `"b"`, `count` 4 | `scrollTop` stays 100 |
| edge-lock-006 | no-prepend-compensation, item-leave-reader-put | Mounted with `newestKey` `"z"`, `count` 9; user scrolls to 100; `scrollHeight` set to 700; rerender with `newestKey` `"y"`, `count` 4 | `scrollTop` stays 100 |
| edge-lock-007 | geometry-changed-scroll-keeps-dist, pure-scroll-records-dist, item-signal | 001 mounted (`scrollTop` 600); `scrollHeight` set to 1100 with no event; user scrolls to 500, then to 200 (dist 500); `scrollHeight` set to 1200; rerender with `newestKey` `"b"`, `count` 4 | `scrollTop` stays 200 |
| edge-lock-008 | attach-replace, attach-null-element, fresh-element-pin | Mounted on element A (1000/400); user scrolls A to 100; `ref.current` set to `null` and rerendered; `ref.current` set to new element B (800/400) and rerendered | B's `scrollTop` is 400 |
| edge-lock-009 | pin-top, fresh-element-pin | Element with `scrollTop` 300; mount with `edge` `"top"` | `scrollTop` is 0; tracked `dist` is 0 |
| edge-lock-010 | resize-top-no-write, resize-resync | `edge` `"top"`, user scrolled to 150; resize fired | The hook does not write `scrollTop`; tracked `dist` equals the browser's `scrollTop` (150 unless the browser clamped it) |
| edge-lock-011 | resize-observer-absent | `ResizeObserver` undefined; mount a bottom-locked element (1000/400) | `scrollTop` is 600; no observer is created; a later resize changes nothing |
| edge-lock-012 | item-follow-within-slack | Bottom edge, dist exactly 24; rerender with a new `count` after `scrollHeight` grows by 100 | The element is pinned to the tail (24 is inside the slack, since the comparison is `<=`) |
