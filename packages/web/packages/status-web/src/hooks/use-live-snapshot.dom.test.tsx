// @vitest-environment jsdom
import { describe, it, expect, beforeEach, afterEach, vi, type Mock } from "vitest";
import { type ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, render, waitFor } from "@testing-library/react";
import { useLiveSnapshot, __resetStoreForTests, type LiveSnapshotStore } from "./use-live-snapshot";
import { liveSnapshot } from "../lib/live-snapshot.fixture";

// --- a controllable EventSource stand-in (jsdom has none) ---------------------
class MockEventSource {
  static instances: MockEventSource[] = [];
  static readonly CONNECTING = 0;
  static readonly OPEN = 1;
  static readonly CLOSED = 2;
  readonly CONNECTING = 0;
  readonly OPEN = 1;
  readonly CLOSED = 2;
  url: string;
  readyState = 0;
  private handlers: Record<string, Array<(e: MessageEvent) => void>> = {};
  constructor(url: string) {
    this.url = url;
    MockEventSource.instances.push(this);
  }
  addEventListener(type: string, cb: (e: MessageEvent) => void): void {
    (this.handlers[type] ||= []).push(cb);
  }
  removeEventListener(): void {}
  close(): void {
    this.readyState = 2;
  }
  // test drivers
  fire(type: string, data?: string): void {
    for (const cb of this.handlers[type] ?? []) cb({ data } as MessageEvent);
  }
  open(): void {
    this.readyState = 1;
    this.fire("open");
  }
  fail(closed: boolean): void {
    if (closed) this.readyState = 2;
    this.fire("error");
  }
}

function installFetch(opts: { liveHangs?: boolean; liveRejects?: boolean; checkRan?: boolean } = {}): Mock {
  const json = (body: unknown) =>
    new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
  const fn = vi.fn(async (input: RequestInfo | URL) => {
    const url = String(input);
    if (url.includes("/api/live/check")) return json({ ok: true, ran: opts.checkRan ?? true });
    if (opts.liveRejects) throw new Error("network");
    if (opts.liveHangs) return new Promise<Response>(() => {}); // never resolves
    return json(liveSnapshot({ generatedAt: "2026-01-01T00:00:00.000Z" }));
  });
  globalThis.fetch = fn as unknown as typeof fetch;
  return fn;
}

function mountStore() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  );
  const ref: { current: LiveSnapshotStore | null } = { current: null };
  function Probe(): null {
    ref.current = useLiveSnapshot();
    return null;
  }
  const view = render(<Probe />, { wrapper });
  return { ref, unmount: view.unmount };
}

const stream = () => MockEventSource.instances.at(-1)!;

describe("useLiveSnapshot — SSE wiring (jsdom + mock EventSource)", () => {
  beforeEach(() => {
    MockEventSource.instances = [];
    (globalThis as unknown as { EventSource: unknown }).EventSource = MockEventSource;
    window.localStorage?.clear(); // jsdom may not provide localStorage; the hook tolerates its absence
    installFetch({ liveHangs: true }); // isolate SSE from the poll unless a test says otherwise
  });
  afterEach(() => {
    __resetStoreForTests();
    vi.useRealTimers();
  });

  it("opens the stream and folds a pushed snapshot into the store", async () => {
    const { ref } = mountStore();
    expect(stream().url).toBe("/api/live/stream");

    const pushed = liveSnapshot({
      generatedAt: "2030-01-01T00:00:00.000Z",
      services: [
        // a real DTO so the snapshot is non-trivial; only the marker is asserted
        { slug: "s", group: "G", name: "Svc", environment: "production", status: "healthy", responseTimeMs: 12, statusCode: 200, url: "https://x", error: null, dnsOk: true, downSince: null },
      ] as never,
    });
    act(() => {
      stream().open();
      stream().fire("snapshot", JSON.stringify(pushed));
    });

    await waitFor(() => expect(ref.current!.snapshot?.generatedAt).toBe("2030-01-01T00:00:00.000Z"));
    expect(ref.current!.snapshot?.services).toHaveLength(1);
  });

  it("drives the countdown off the backend schedule frame", async () => {
    const { ref } = mountStore();
    act(() => {
      stream().open();
      stream().fire("schedule", JSON.stringify({ nextCheckAt: "2030-06-01T00:00:00.000Z" }));
    });
    await waitFor(() => expect(ref.current!.nextPollAt).toBe(Date.parse("2030-06-01T00:00:00.000Z")));
  });

  it("refresh() POSTs /api/live/check and shows the spinner until a fresh snapshot lands", async () => {
    const fetchMock = installFetch({ checkRan: true }); // poll resolves so isFetching settles
    const { ref } = mountStore();
    act(() => stream().open());
    await waitFor(() => expect(ref.current!.polling).toBe(false)); // initial poll settled, nothing pending

    act(() => {
      ref.current!.refresh();
    });
    // The POST fires synchronously before the IIFE's first await.
    expect(fetchMock).toHaveBeenCalledWith("/api/live/check", { method: "POST" });
    expect(ref.current!.polling).toBe(true); // spinner on while awaiting the check's result

    // A snapshot built AFTER the click clears the spinner; an earlier one would not.
    act(() => stream().fire("snapshot", JSON.stringify(liveSnapshot({ generatedAt: new Date(Date.now() + 5_000).toISOString() }))));
    await waitFor(() => expect(ref.current!.polling).toBe(false));
  });

  it("keeps the spinner up for the WHOLE detached cycle, not just 12s", async () => {
    // POST /api/live/check now returns as soon as the cycle STARTS (runNowDetached);
    // the fresh snapshot arrives later, over SSE. The safety backstop must therefore
    // outlast a real manual full sync (the backend's cycle budget is ~2-3 min) —
    // at the old 12s it fired on every check, telling the user "done" while the
    // providers were still being polled.
    installFetch({ checkRan: true });
    const { ref } = mountStore();
    act(() => stream().open());
    await waitFor(() => expect(ref.current!.polling).toBe(false)); // initial poll settled

    // Fake timers BEFORE the click, so the safety timeout refresh() schedules is the
    // one we advance (installing them afterwards would leave it on the real clock and
    // make this assertion vacuous). Microtasks still run, so the POST settles.
    vi.useFakeTimers();
    try {
      act(() => {
        ref.current!.refresh();
      });
      await act(async () => {
        await Promise.resolve();
        await Promise.resolve();
      });
      expect(ref.current!.polling).toBe(true);

      act(() => {
        vi.advanceTimersByTime(60_000); // a minute into a cycle that legitimately runs longer
      });
      expect(ref.current!.polling).toBe(true); // still checking — do NOT claim it finished

      // The cycle completes and pushes its snapshot: THAT is what ends the check.
      act(() => stream().fire("snapshot", JSON.stringify(liveSnapshot({ generatedAt: new Date(Date.now() + 90_000).toISOString() }))));
      expect(ref.current!.polling).toBe(false);
    } finally {
      vi.useRealTimers();
    }
  });

  it("does not slam a stale /live refetch the instant the detached check is accepted", async () => {
    // Pre-detach, the POST resolved only after the cycle finished, so an immediate
    // refetch was guaranteed fresh. Now it would fetch the PRE-cycle snapshot —
    // pure waste that can't advance the check. The fallback client re-reads on its
    // own cadence (and via the safety backstop) instead.
    const fetchMock = installFetch({ checkRan: true });
    const { ref } = mountStore();
    // No stream opened: this is the polling-fallback client.
    await waitFor(() => expect(ref.current!.polling).toBe(false));
    fetchMock.mockClear();

    act(() => {
      ref.current!.refresh();
    });
    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/api/live/check", { method: "POST" }));
    await act(async () => {
      await Promise.resolve();
    });

    const liveCalls = fetchMock.mock.calls.filter((c) => String(c[0]).includes("/api/live") && !String(c[0]).includes("/check"));
    expect(liveCalls).toHaveLength(0);
  });

  it("recreates the EventSource after a PERMANENT (readyState CLOSED) failure", () => {
    vi.useFakeTimers();
    mountStore();
    expect(MockEventSource.instances).toHaveLength(1);

    act(() => stream().fail(true)); // non-200 → CLOSED, browser would NOT auto-retry
    act(() => {
      vi.advanceTimersByTime(3_000); // STREAM_REOPEN_MS
    });
    expect(MockEventSource.instances).toHaveLength(2); // we recreated it ourselves
  });

  it("does NOT recreate on a transient (CONNECTING) error — the browser auto-retries", () => {
    vi.useFakeTimers();
    mountStore();
    act(() => stream().fail(false)); // readyState stays CONNECTING
    act(() => {
      vi.advanceTimersByTime(10_000);
    });
    expect(MockEventSource.instances).toHaveLength(1); // no extra connection created
  });
});
