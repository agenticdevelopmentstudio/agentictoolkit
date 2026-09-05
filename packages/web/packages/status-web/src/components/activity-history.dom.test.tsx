// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { ActivityPanel, type ActivityPanelProps } from "./ActivityPanel";
import type { Row } from "../lib/row-model";

// This project doesn't enable vitest's `test.globals` (vitest.config.ts), so
// @testing-library/react's own auto-cleanup — which only registers when it finds a
// GLOBAL `afterEach` — never fires. Without this, every `render()` below would pile up
// in `document.body` across tests and `getByTestId`/`getByText` would start throwing
// "found multiple elements" once a second test rendered a second activity-list.
afterEach(cleanup);

// ActivityPanel takes a long list of props most tests here don't care about — this
// helper fills every REQUIRED one with a plausible default and lets each test
// override only what it's actually exercising.
function makeRows(n: number): Row[] {
  const baseMs = Date.UTC(2026, 7, 17, 12, 0, 0);
  return Array.from({ length: n }, (_, i) => ({
    key: `activity:${i}`,
    source: "vercel",
    platform: "vercel",
    name: `project-${i}`,
    environment: "production",
    statusWord: "deployed",
    tone: "good" as const,
    sha: null,
    commitUrl: null,
    message: null,
    detail: null,
    at: new Date(baseMs - i * 60_000).toISOString(),
    sourceUrl: null,
    liveUrl: null,
  }));
}

function activityProps(overrides: Partial<ActivityPanelProps> = {}): ActivityPanelProps {
  return {
    kind: "activity",
    icon: null,
    title: "Recent Activity",
    // Enough rows that the list actually renders the scrollable body — an empty `rows`
    // makes ActivityPanel render its centered empty state instead, which has no
    // `activity-list`/`problems-list` test id at all.
    rows: makeRows(40),
    envs: new Set(["production"]),
    allEnvs: ["production"],
    onToggleEnv: () => {},
    allSources: [],
    envFiltered: false,
    ...overrides,
  };
}

describe("ActivityPanel scroll-back", () => {
  it("requests an older page when scrolled near the top", () => {
    const onLoadOlder = vi.fn();
    render(<ActivityPanel {...activityProps({ onLoadOlder })} />);
    const body = screen.getByTestId("activity-list");
    Object.defineProperty(body, "scrollTop", { value: 10, writable: true });
    fireEvent.scroll(body);
    expect(onLoadOlder).toHaveBeenCalled();
  });

  it("does not request an older page from the middle of the list", () => {
    const onLoadOlder = vi.fn();
    render(<ActivityPanel {...activityProps({ onLoadOlder })} />);
    const body = screen.getByTestId("activity-list");
    Object.defineProperty(body, "scrollTop", { value: 9999, writable: true });
    fireEvent.scroll(body);
    expect(onLoadOlder).not.toHaveBeenCalled();
  });

  it("resets the auto-page budget only on the edge into the threshold zone, not on every scroll inside it", () => {
    const onScrollGesture = vi.fn();
    // `onLoadOlder` is REQUIRED here, not decoration: `canPageBack` is
    // `kind === "activity" && onLoadOlder != null`, and without it `handleScroll` returns
    // before it can reach `onScrollGesture` — the assertion below could never pass.
    render(<ActivityPanel {...activityProps({ onScrollGesture, onLoadOlder: vi.fn() })} />);
    const body = screen.getByTestId("activity-list");
    Object.defineProperty(body, "scrollTop", { value: 10, writable: true });
    fireEvent.scroll(body); // false -> true edge: fires
    fireEvent.scroll(body); // still inside the zone: must NOT fire again
    fireEvent.scroll(body);
    expect(onScrollGesture).toHaveBeenCalledTimes(1);
  });

  it("re-arms the budget on a wheel inside the zone, which a bare scroll event does not", () => {
    const onScrollGesture = vi.fn();
    render(<ActivityPanel {...activityProps({ onScrollGesture, onLoadOlder: vi.fn() })} />);
    const body = screen.getByTestId("activity-list");
    Object.defineProperty(body, "scrollTop", { value: 0, writable: true });
    fireEvent.scroll(body); // the one edge grant
    fireEvent.scroll(body); // parked at the top: no further grant from scrolling alone
    expect(onScrollGesture).toHaveBeenCalledTimes(1);
    // A reader pinned at scrollTop 0 still pushing. Without this the "scroll again to load
    // more history" line names a gesture that cannot be performed.
    fireEvent.wheel(body, { deltaY: -20 });
    expect(onScrollGesture).toHaveBeenCalledTimes(2);
  });

  it("does not re-arm the budget on a wheel from the middle of the list", () => {
    const onScrollGesture = vi.fn();
    render(<ActivityPanel {...activityProps({ onScrollGesture, onLoadOlder: vi.fn() })} />);
    const body = screen.getByTestId("activity-list");
    Object.defineProperty(body, "scrollTop", { value: 9999, writable: true });
    fireEvent.wheel(body, { deltaY: -20 });
    expect(onScrollGesture).not.toHaveBeenCalled();
  });

  it("ignores a DOWNWARD wheel — older is upward", () => {
    // Wheeling down is the reader moving forward through the page that just arrived.
    const onScrollGesture = vi.fn();
    const onLoadOlder = vi.fn();
    render(<ActivityPanel {...activityProps({ onScrollGesture, onLoadOlder })} />);
    const body = screen.getByTestId("activity-list");
    Object.defineProperty(body, "scrollTop", { value: 0, writable: true });
    fireEvent.wheel(body, { deltaY: 20 });
    expect(onScrollGesture).not.toHaveBeenCalled();
    expect(onLoadOlder).not.toHaveBeenCalled();
  });

  it("collapses one wheel BURST into a single budget grant", () => {
    // A trackpad flick is dozens of wheel events (inertia keeps them coming after the
    // finger lifts). One grant each would make MAX_AUTOPAGE_FETCHES unenforceable on the
    // primary input device — the budget would never bind at all.
    const onScrollGesture = vi.fn();
    render(<ActivityPanel {...activityProps({ onScrollGesture, onLoadOlder: vi.fn() })} />);
    const body = screen.getByTestId("activity-list");
    Object.defineProperty(body, "scrollTop", { value: 0, writable: true });
    for (let i = 0; i < 30; i++) fireEvent.wheel(body, { deltaY: -8 });
    expect(onScrollGesture).toHaveBeenCalledTimes(1);
  });

  it("lets a scrollbar drag re-arm a spent budget", () => {
    // Keyboard and scrollbar readers are already parked inside the zone, so the scroll
    // EDGE never fires for them and wheel/touch are devices they aren't using. Without a
    // path of their own, "scroll again to load more history" names a gesture they cannot
    // perform.
    const onScrollGesture = vi.fn();
    render(<ActivityPanel {...activityProps({ onScrollGesture, onLoadOlder: vi.fn() })} />);
    const body = screen.getByTestId("activity-list");
    Object.defineProperty(body, "scrollTop", { value: 0, writable: true });
    fireEvent.mouseDown(body);
    expect(onScrollGesture).toHaveBeenCalledTimes(1);
  });

  it("keeps the scroll container mounted when every row is filtered out", () => {
    // The empty state used to replace the whole list pane, taking the scroll container,
    // the gesture handlers and the status line with it — leaving a reader whose filter
    // emptied the pane no way to reach another page.
    render(
      <ActivityPanel
        {...activityProps({ rows: [], onLoadOlder: vi.fn(), historyExhausted: true })}
      />,
    );
    expect(screen.getByTestId("activity-list")).toBeTruthy();
    expect(screen.getByText(/beginning of recorded activity/i)).toBeTruthy();
  });

  it("says why scroll-back is off when age-out is not never", () => {
    render(<ActivityPanel {...activityProps({ historyDisabledReason: "age-out" as const })} />);
    expect(screen.getByText(/set it to .never. to scroll further back/i)).toBeTruthy();
  });

  it("names CLEARED as its own reason, never the age-out one", () => {
    // The two are one tri-state, and they are not interchangeable copy: telling a reader
    // who just pressed Clear to change their age-out setting sends them to a control that
    // would not help.
    render(<ActivityPanel {...activityProps({ historyDisabledReason: "cleared" as const })} />);
    expect(screen.getByText(/activity was cleared/i)).toBeTruthy();
    expect(screen.queryByText(/set it to .never./i)).toBeNull();
  });

  it("reports a failed page as a failure, never as the beginning of history", () => {
    render(<ActivityPanel {...activityProps({ onLoadOlder: vi.fn(), historyError: true })} />);
    expect(screen.getByText(/couldn't load older activity/i)).toBeTruthy();
    expect(screen.queryByText(/beginning of recorded activity/i)).toBeNull();
  });

  it("pulls another page while the FILTERED list is shorter than the fill threshold", () => {
    const onLoadOlder = vi.fn();
    // The caller cannot see this: `q`/the source filter are panel-local, so a rule keyed
    // on the caller's own row count would think the pane was full.
    render(<ActivityPanel {...activityProps({ rows: makeRows(3), onLoadOlder })} />);
    expect(onLoadOlder).toHaveBeenCalled();
  });

  it("does not pull another page once the pane is filled", () => {
    const onLoadOlder = vi.fn();
    render(<ActivityPanel {...activityProps({ rows: makeRows(40), onLoadOlder })} />);
    expect(onLoadOlder).not.toHaveBeenCalled();
  });

  it("shows the beginning-of-history affordance only when exhausted", () => {
    const { rerender } = render(<ActivityPanel {...activityProps({ historyExhausted: false })} />);
    expect(screen.queryByText(/beginning of recorded activity/i)).toBeNull();
    rerender(<ActivityPanel {...activityProps({ historyExhausted: true })} />);
    expect(screen.getByText(/beginning of recorded activity/i)).toBeTruthy();
  });

  it("shows the budget-spent affordance when the budget is spent and history isn't exhausted", () => {
    render(<ActivityPanel {...activityProps({ historyBudgetSpent: true, historyExhausted: false })} />);
    expect(screen.getByText(/scroll again to load more history/i)).toBeTruthy();
  });

  it("prefers the exhausted line over the budget-spent line when both are true", () => {
    render(<ActivityPanel {...activityProps({ historyBudgetSpent: true, historyExhausted: true })} />);
    expect(screen.getByText(/beginning of recorded activity/i)).toBeTruthy();
    expect(screen.queryByText(/scroll again to load more history/i)).toBeNull();
  });

  it("never offers scroll-back on the Problems pane", () => {
    const onLoadOlder = vi.fn();
    render(<ActivityPanel {...activityProps({ kind: "problems", onLoadOlder })} />);
    const body = screen.getByTestId("problems-list");
    Object.defineProperty(body, "scrollTop", { value: 0, writable: true });
    fireEvent.scroll(body);
    expect(onLoadOlder).not.toHaveBeenCalled();
  });
});
