// @vitest-environment jsdom
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { renderHook, cleanup } from "@testing-library/react";
import { atEdge, useFollowNewItems } from "./use-follow-new-items";

describe("atEdge", () => {
  it("bottom: true at the bottom and within the slack, false once scrolled away", () => {
    expect(atEdge({ scrollHeight: 1000, clientHeight: 400, scrollTop: 600 }, "bottom")).toBe(true); // exactly at bottom
    expect(atEdge({ scrollHeight: 1000, clientHeight: 400, scrollTop: 580 }, "bottom")).toBe(true); // 20px < 24 slack
    expect(atEdge({ scrollHeight: 1000, clientHeight: 400, scrollTop: 560 }, "bottom")).toBe(false); // 40px away
  });
  it("top: true at the top and within the slack, false once scrolled away", () => {
    expect(atEdge({ scrollHeight: 1000, clientHeight: 400, scrollTop: 0 }, "top")).toBe(true);
    expect(atEdge({ scrollHeight: 1000, clientHeight: 400, scrollTop: 20 }, "top")).toBe(true); // 20px < 24 slack
    expect(atEdge({ scrollHeight: 1000, clientHeight: 400, scrollTop: 40 }, "top")).toBe(false);
  });
  it("a non-overflowing list counts as at either edge", () => {
    expect(atEdge({ scrollHeight: 400, clientHeight: 400, scrollTop: 0 }, "bottom")).toBe(true);
    expect(atEdge({ scrollHeight: 400, clientHeight: 400, scrollTop: 0 }, "top")).toBe(true);
  });
  it("honors a custom slack", () => {
    expect(atEdge({ scrollHeight: 1000, clientHeight: 400, scrollTop: 560 }, "bottom", 40)).toBe(true);
    expect(atEdge({ scrollHeight: 1000, clientHeight: 400, scrollTop: 559 }, "bottom", 40)).toBe(false);
  });
});

// A resizable-split drag shrinks the list's scroll container without changing the
// rendered rows; these assert the hook keeps a bottom-tailing list pinned to its
// tail across such a resize (so the newest rows don't slide behind the growing pane),
// while still leaving a reader who has scrolled up to read history where they are.
describe("useFollowNewItems — re-pin on container resize", () => {
  let roCallbacks: ResizeObserverCallback[] = [];
  class MockResizeObserver {
    constructor(cb: ResizeObserverCallback) {
      roCallbacks.push(cb);
    }
    observe(): void {}
    unobserve(): void {}
    disconnect(): void {}
  }
  const fireResize = (): void => roCallbacks.forEach((cb) => cb([], {} as ResizeObserver));

  /** A scroll element with fixed scroll/client heights and a real settable scrollTop. */
  function makeEl(scrollHeight: number, clientHeight: number): HTMLElement {
    const el = document.createElement("div");
    Object.defineProperty(el, "scrollHeight", { configurable: true, value: scrollHeight });
    Object.defineProperty(el, "clientHeight", { configurable: true, value: clientHeight });
    let top = 0;
    Object.defineProperty(el, "scrollTop", {
      configurable: true,
      get: () => top,
      set: (v: number) => {
        top = v;
      },
    });
    document.body.appendChild(el);
    return el;
  }

  beforeEach(() => {
    roCallbacks = [];
    vi.stubGlobal("ResizeObserver", MockResizeObserver);
  });
  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    document.body.innerHTML = "";
  });

  it("re-pins the bottom-tailing list to the tail on resize while pinned", () => {
    const el = makeEl(1000, 400);
    const ref = { current: el };
    renderHook(() => useFollowNewItems(ref, "bottom", "newest", "oldest", 3));
    expect(el.scrollTop).toBe(1000); // mount pins to the tail

    // Pane shrinks: the browser leaves scrollTop put (no scroll event fires), so the
    // viewport is momentarily off the tail until the resize observer re-pins it.
    el.scrollTop = 600;
    fireResize();
    expect(el.scrollTop).toBe(1000);
  });

  it("leaves a reader who scrolled up in place on resize", () => {
    const el = makeEl(1000, 400);
    const ref = { current: el };
    renderHook(() => useFollowNewItems(ref, "bottom", "newest", "oldest", 3));

    // Reader scrolls up to read history — a scroll event marks them unpinned.
    el.scrollTop = 100;
    el.dispatchEvent(new Event("scroll"));

    // A subsequent resize must NOT yank them back down to the tail.
    fireResize();
    expect(el.scrollTop).toBe(100);
  });

  // The hook's "top" mode — for a caller that renders NEWEST-FIRST, so its newest row
  // is at the TOP. Recent Activity is not that caller (it sorts oldest-first and pins
  // to "bottom", covered above), but `edge` is part of the hook's contract and PaneShell
  // takes it from whoever mounts it, so both halves stay pinned by tests.
  it("re-pins a top-tailing list to the top on resize while pinned", () => {
    const el = makeEl(1000, 400);
    const ref = { current: el };
    renderHook(() => useFollowNewItems(ref, "top", "newest", "oldest", 3));
    expect(el.scrollTop).toBe(0); // mount pins to the top, where the newest row is

    el.scrollTop = 600;
    fireResize();
    expect(el.scrollTop).toBe(0);
  });

  it("a new row while pinned to the top keeps the viewport on the newest row", () => {
    const el = makeEl(1000, 400);
    const ref = { current: el };
    const { rerender } = renderHook(
      ({ newest, count }: { newest: string; count: number }) =>
        useFollowNewItems(ref, "top", newest, "oldest", count),
      { initialProps: { newest: "a", count: 3 } },
    );
    // Something (a filter click, a keyboard scrollIntoView) nudged it a few px —
    // still within PIN_SLACK_PX, so the reader still counts as parked at the top.
    el.scrollTop = 10;
    el.dispatchEvent(new Event("scroll"));

    rerender({ newest: "b", count: 4 });
    // Under the old edge ("bottom") this would have jumped to scrollHeight (1000) —
    // i.e. to the OLDEST row — instead of holding the newest one.
    expect(el.scrollTop).toBe(0);
  });

  // These two elements have NO children, so nothing has geometry to anchor on and the
  // hook takes its measurement-free FALLBACK path (total scrollHeight growth, gated on
  // the top row changing). That is what they cover — the anchored-row path they cannot
  // reach is covered by the DOM-geometry describe below.
  it("anchors a scrolled-away reader when rows are inserted above them (newest-first)", () => {
    const el = makeEl(1000, 400);
    const ref = { current: el };
    const { rerender } = renderHook(
      ({ newest, count }: { newest: string; count: number }) =>
        useFollowNewItems(ref, "top", newest, "oldest", count),
      { initialProps: { newest: "a", count: 3 } },
    );
    // Reader scrolls DOWN into the history — well past the slack, so unpinned.
    el.scrollTop = 500;
    el.dispatchEvent(new Event("scroll"));

    // A new deploy lands at the TOP and the content grows by 200px. Compensating
    // by the growth keeps the reader's rows under their eyes. (The mock element's
    // scrollHeight is fixed, so grow it explicitly to stand in for the new row.)
    Object.defineProperty(el, "scrollHeight", { configurable: true, value: 1200 });
    rerender({ newest: "b", count: 4 });
    expect(el.scrollTop).toBe(700);
  });

  it("does NOT anchor when the list grows at the far end from the top", () => {
    const el = makeEl(1000, 400);
    const ref = { current: el };
    const { rerender } = renderHook(
      ({ oldest, count }: { oldest: string; count: number }) =>
        useFollowNewItems(ref, "top", "newest", oldest, count),
      { initialProps: { oldest: "z", count: 3 } },
    );
    el.scrollTop = 500;
    el.dispatchEvent(new Event("scroll"));

    // Only the BOTTOM row changed (an older row aged in below the viewport) — nothing
    // moved above the reader, so their scrollTop must not be touched.
    Object.defineProperty(el, "scrollHeight", { configurable: true, value: 1200 });
    rerender({ oldest: "y", count: 4 });
    expect(el.scrollTop).toBe(500);
  });
});

// Fix Round 2 item C6. Recent Activity is server-capped at MAX_ACTIVITY_ROWS (300), so
// once the list is full every row that arrives at the top drops one off the bottom and
// the container's TOTAL height doesn't change — which is exactly the number the old
// compensation added. The reader therefore slid up by about a row on every update, the
// drift the compensation exists to prevent. Compensating by the ANCHORED ROW's own
// shift is immune to what happens at the far end.
//
// jsdom does no layout (every rect is 0), so geometry is modelled explicitly here:
// fixed-height rows stacked from the top of the content and translated by scrollTop.
// That is the whole reason these cases can't be written against the bare mock element
// the describe above uses — with no children there is no anchor to measure, and the
// hook's fallback path is all those cases can reach.
describe("useFollowNewItems — the reader holds their row when the capped list rolls over", () => {
  const ROW_H = 100;
  const VIEW_H = 400;

  function rect(top: number, height: number): DOMRect {
    return { top, bottom: top + height, height, y: top, x: 0, left: 0, right: 0, width: 0, toJSON: () => ({}) } as DOMRect;
  }

  /** A scroll container whose rows have real, controllable geometry. */
  function makeList(keys: string[]) {
    const el = document.createElement("div");
    let top = 0;
    Object.defineProperty(el, "clientHeight", { configurable: true, value: VIEW_H });
    Object.defineProperty(el, "scrollHeight", { configurable: true, get: () => el.children.length * ROW_H });
    Object.defineProperty(el, "scrollTop", {
      configurable: true,
      get: () => top,
      set: (v: number) => {
        top = v;
      },
    });
    // The container's own box is the viewport: rows are positioned relative to it.
    el.getBoundingClientRect = () => rect(0, VIEW_H);

    const addRow = (key: string, where: "top" | "bottom"): void => {
      const row = document.createElement("div");
      row.dataset.key = key;
      row.getBoundingClientRect = () => {
        const i = Array.prototype.indexOf.call(el.children, row);
        return rect(i * ROW_H - el.scrollTop, ROW_H);
      };
      if (where === "top") el.prepend(row);
      else el.append(row);
    };
    keys.forEach((k) => addRow(k, "bottom"));
    document.body.appendChild(el);

    /** The key of the row at the viewport's top edge — what the reader is looking at.
     *  THIS is the thing that must not move; scrollTop is only how it's achieved. */
    const readerRow = (): string | undefined => {
      const hit = Array.from(el.children).find((c) => c.getBoundingClientRect().bottom > 0);
      return (hit as HTMLElement | undefined)?.dataset.key;
    };
    return { el, addRow, readerRow };
  }

  const TEN = Array.from({ length: 10 }, (_, i) => `k${i}`); // 10 rows × 100px = 1000px

  afterEach(() => {
    cleanup();
    document.body.innerHTML = "";
  });

  function mount(el: HTMLElement, newest: string, count: number) {
    const ref = { current: el };
    return renderHook(
      (p: { newest: string; count: number }) => useFollowNewItems(ref, "top", p.newest, "k9", p.count),
      { initialProps: { newest, count } },
    );
  }

  it("holds the reader's row when a row arrives at the top and one drops off the capped bottom", () => {
    const { el, addRow, readerRow } = makeList(TEN);
    const { rerender } = mount(el, "k0", 10);

    // Reader scrolls down into the history — unpinned, resting exactly on k5.
    el.scrollTop = 500;
    el.dispatchEvent(new Event("scroll"));
    expect(readerRow()).toBe("k5");

    // A new deploy lands at the top and the oldest row falls off the cap.
    addRow("new", "top");
    el.removeChild(el.lastElementChild!);
    // The tell: the container did not grow at all, so the old total-delta compensation
    // contributed ZERO and left the reader looking at k4 — one row up from where they were.
    expect(el.scrollHeight).toBe(1000);

    rerender({ newest: "new", count: 10 });

    expect(readerRow()).toBe("k5");
    expect(el.scrollTop).toBe(600);
  });

  it("still compensates a plain insert above the reader (nothing drops off)", () => {
    const { el, addRow, readerRow } = makeList(TEN);
    const { rerender } = mount(el, "k0", 10);

    el.scrollTop = 500;
    el.dispatchEvent(new Event("scroll"));

    addRow("new", "top");
    rerender({ newest: "new", count: 11 });

    // Total growth and the anchored row's shift agree here (100px) — this is the case
    // the old code got right, kept so the fix isn't a trade.
    expect(readerRow()).toBe("k5");
    expect(el.scrollTop).toBe(600);
  });

  it("leaves the reader alone when the list changes only below them", () => {
    const { el, addRow, readerRow } = makeList(TEN);
    const { rerender } = mount(el, "k0", 10);

    el.scrollTop = 500;
    el.dispatchEvent(new Event("scroll"));

    // An older row ages in at the far end: the list grows by 100px, but nothing above
    // the reader moved, so compensating by the total would shove them down a row.
    addRow("older", "bottom");
    rerender({ newest: "k0", count: 11 });

    expect(readerRow()).toBe("k5");
    expect(el.scrollTop).toBe(500);
  });

  it("re-pins a reader who is still parked at the top, rather than anchoring them", () => {
    const { el, addRow, readerRow } = makeList(TEN);
    const { rerender } = mount(el, "k0", 10);

    // Nudged a few px — still inside PIN_SLACK_PX, so they count as parked at the tail.
    el.scrollTop = 10;
    el.dispatchEvent(new Event("scroll"));

    addRow("new", "top");
    el.removeChild(el.lastElementChild!);
    rerender({ newest: "new", count: 10 });

    // Following the tail wins over holding a row: the newest row is the point.
    expect(el.scrollTop).toBe(0);
    expect(readerRow()).toBe("new");
  });
});
