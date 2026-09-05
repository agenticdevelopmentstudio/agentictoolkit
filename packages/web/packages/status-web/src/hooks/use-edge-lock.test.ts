// @vitest-environment jsdom
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { renderHook, cleanup } from "@testing-library/react";
import { useEdgeLock } from "./use-edge-lock";

// The lock's contract: whatever touches the locked edge RIDES that edge through
// every container resize (a split-divider drag, a collapse, a window resize) —
// unconditionally, pinned to the tail or scrolled away. The pinned-within-slack
// heuristic applies only to ITEM changes (follow new rows vs. leave a reader put).
describe("useEdgeLock", () => {
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

  /** A scroll element with mutable scroll/client heights and a scrollTop that
   *  clamps into the valid range, like a real browser's. */
  function makeEl(
    scrollHeight: number,
    clientHeight: number,
  ): {
    el: HTMLElement;
    setScrollHeight: (v: number) => void;
    setClientHeight: (v: number) => void;
    scrollTo: (v: number) => void;
  } {
    const el = document.createElement("div");
    let sh = scrollHeight;
    let ch = clientHeight;
    let top = 0;
    const clamp = (v: number): number => Math.max(0, Math.min(v, Math.max(0, sh - ch)));
    Object.defineProperty(el, "scrollHeight", { configurable: true, get: () => sh });
    Object.defineProperty(el, "clientHeight", { configurable: true, get: () => ch });
    Object.defineProperty(el, "scrollTop", {
      configurable: true,
      get: () => top,
      set: (v: number) => {
        top = clamp(v);
      },
    });
    document.body.appendChild(el);
    return {
      el,
      setScrollHeight: (v: number) => {
        sh = v;
      },
      setClientHeight: (v: number) => {
        ch = v;
      },
      // Simulate a user scroll: move scrollTop and fire the event the browser would.
      scrollTo: (v: number) => {
        top = clamp(v);
        el.dispatchEvent(new Event("scroll"));
      },
    };
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

  it("mounts a bottom-locked list resting on its tail", () => {
    const { el } = makeEl(1000, 400);
    renderHook(() => useEdgeLock({ current: el }, "bottom", "newest", 3));
    expect(el.scrollTop).toBe(600); // scrollHeight - clientHeight: the tail edge
  });

  it("keeps the tail on the edge across a resize (dist 0 stays 0)", () => {
    const { el, setClientHeight } = makeEl(1000, 400);
    renderHook(() => useEdgeLock({ current: el }, "bottom", "newest", 3));

    // Pane shrinks (details dragged up): the browser leaves scrollTop put, so the
    // viewport is momentarily off the tail until the resize lock re-asserts it.
    setClientHeight(300);
    fireResize();
    expect(el.scrollTop).toBe(700); // 1000 - 300 - 0: still on the tail
  });

  it("preserves a scrolled-up reader's distance from the edge across a resize", () => {
    const { el, setClientHeight, scrollTo } = makeEl(1000, 400);
    renderHook(() => useEdgeLock({ current: el }, "bottom", "newest", 3));

    // Reader scrolls up to read history: dist = 1000 - 400 - 100 = 500.
    scrollTo(100);

    // Pane shrinks: the row that was touching the details bar must stay touching
    // it (dist stays 500), so the viewport slides — rows leave at the TOP.
    setClientHeight(300);
    fireResize();
    expect(el.scrollTop).toBe(200); // 1000 - 300 - 500

    // And back out: the same row still rides the bar.
    setClientHeight(400);
    fireResize();
    expect(el.scrollTop).toBe(100); // 1000 - 400 - 500
  });

  it("follows a new item when resting within slack of the edge", () => {
    const { el, setScrollHeight, scrollTo } = makeEl(1000, 400);
    const { rerender } = renderHook(({ newest, count }) => useEdgeLock({ current: el }, "bottom", newest, count), {
      initialProps: { newest: "a", count: 3 },
    });

    // Nudge to 20px off the tail — still within the 24px slack.
    scrollTo(580);

    setScrollHeight(1100); // a new row lands at the bottom
    rerender({ newest: "b", count: 4 });
    expect(el.scrollTop).toBe(700); // snapped back onto the tail
  });

  it("leaves a scrolled-up reader put when a new item lands at the tail", () => {
    const { el, setScrollHeight, scrollTo } = makeEl(1000, 400);
    const { rerender } = renderHook(({ newest, count }) => useEdgeLock({ current: el }, "bottom", newest, count), {
      initialProps: { newest: "a", count: 3 },
    });

    scrollTo(100); // dist 500 — reading history
    setScrollHeight(1100);
    rerender({ newest: "b", count: 4 });
    expect(el.scrollTop).toBe(100); // not yanked to the tail
  });

  // Regression: a filter narrowing/clearing the list is an item change, NOT a
  // prepend of older history — it must never shift a scrolled-up reader's place.
  it("leaves a scrolled-up reader put when the list is filtered under them", () => {
    const { el, setScrollHeight, scrollTo } = makeEl(1000, 400);
    const { rerender } = renderHook(({ newest, count }) => useEdgeLock({ current: el }, "bottom", newest, count), {
      initialProps: { newest: "z", count: 9 },
    });

    scrollTo(100); // dist 500 — reading history

    // Filter narrows the list: fewer rows, shorter content, a different newest key.
    setScrollHeight(700);
    rerender({ newest: "y", count: 4 });
    expect(el.scrollTop).toBe(100); // stays put — no prepend delta applied
  });

  // Regression (EL-1): a content-driven height change with no scroll event used to
  // wedge the tracker so every later scroll was dropped and dist froze — letting a
  // new item yank a scrolled-up reader to the bottom. Geometry must re-sync.
  it("still records the reader's position after content grows in place", () => {
    const { el, setScrollHeight, scrollTo } = makeEl(1000, 400);
    const { rerender } = renderHook(({ newest, count }) => useEdgeLock({ current: el }, "bottom", newest, count), {
      initialProps: { newest: "a", count: 3 },
    });
    expect(el.scrollTop).toBe(600); // at the tail

    // A row grows in place: scrollHeight changes with NO scroll event and NO
    // container resize (the item-keyed effect and the ResizeObserver both stay put).
    setScrollHeight(1100);

    // The reader scrolls up twice. The first event carries the changed geometry
    // (adopted, distance kept); the second is a clean scroll that records dist.
    scrollTo(500);
    scrollTo(200); // dist = 1100 - 400 - 200 = 500 — well outside the slack

    // A new item arrives: the reader must be left where they are, not yanked down.
    setScrollHeight(1200);
    rerender({ newest: "b", count: 4 });
    expect(el.scrollTop).toBe(200);
  });

  // Regression (EL-2): the scroll element unmounts when a filter empties the list
  // (the caller swaps in an empty-state node) and remounts on clear. The fresh
  // node must rest on its own edge, never inherit the dead node's distance.
  it("resets to the fresh-list edge when the scroll element is replaced", () => {
    const first = makeEl(1000, 400);
    const ref: { current: HTMLElement | null } = { current: first.el };
    const { rerender } = renderHook(() => useEdgeLock(ref, "bottom", "newest", 3));

    first.scrollTo(100); // scrolled up on the old node (dist 500)

    // Filter empties → the container unmounts.
    ref.current = null;
    rerender();

    // Filter cleared → a brand-new, shorter container mounts.
    const second = makeEl(800, 400);
    ref.current = second.el;
    rerender();

    expect(second.el.scrollTop).toBe(400); // 800 - 400: its OWN tail, not a cross-node jump
  });
});
