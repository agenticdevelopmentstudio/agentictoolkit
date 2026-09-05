// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { LiveServiceDTO } from "../lib/live-types";
import { StaleMonitorsBanner } from "./StaleMonitorsBanner";

const deleteEndpoint = vi.hoisted(() => vi.fn(async () => {}));
vi.mock("../api/monitored-sites", () => ({ deleteEndpoint }));

const services = vi.hoisted(() => ({ current: [] as LiveServiceDTO[] }));
vi.mock("../hooks/use-live-snapshot", () => ({
  useLiveSnapshot: () => ({ snapshot: { services: services.current } }),
}));

afterEach(() => {
  cleanup(); // no vitest globals → RTL's auto-cleanup never registers
  deleteEndpoint.mockClear();
  services.current = [];
});

// jsdom has no ResizeObserver; the Popover primitive observes its content size.
class ResizeObserverStub {
  observe(): void {}
  unobserve(): void {}
  disconnect(): void {}
}
(globalThis as { ResizeObserver?: unknown }).ResizeObserver ??= ResizeObserverStub;

const svc = (over: Partial<LiveServiceDTO> = {}): LiveServiceDTO => ({
  slug: "ep-1",
  group: "g",
  name: "docs.example.com",
  url: "https://docs.example.com",
  environment: "production",
  platform: null,
  deployProject: null,
  status: "down",
  responseTimeMs: null,
  statusCode: null,
  error: "HTTP 500",
  lastCheckedAt: null,
  dnsOk: true,
  downSince: new Date(Date.now() - 21 * 86_400_000).toISOString(),
  ...over,
});

function banner(list: LiveServiceDTO[]) {
  services.current = list;
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <StaleMonitorsBanner />
    </QueryClientProvider>,
  );
}

const open = () =>
  fireEvent.click(screen.getByRole("button", { name: "Review monitors that have been down long enough to retire" }));

// The no-auto-delete rule, pinned once. It is what separates the ambiguous case from the
// conclusive one: nothing offered here may be removed without the operator confirming THAT
// row, because nothing offered here is provably dead — a monitor that IS provably dead is
// deleted by the backend cycle and never reaches this component at all.
describe("StaleMonitorsBanner", () => {
  it("renders nothing when there is nothing to retire", () => {
    const { container } = banner([svc({ status: "healthy", downSince: null })]);
    expect(container.firstChild).toBeNull();
  });

  it("arms a confirm instead of deleting; only confirming calls the API", async () => {
    banner([svc()]);
    open();

    fireEvent.click(await screen.findByRole("button", { name: "Retire" }));
    expect(deleteEndpoint).not.toHaveBeenCalled(); // armed, not executed
    expect(screen.getByText("Retire the monitor for docs.example.com?")).toBeTruthy();

    // The modal's own Retire button (the row's is the other one).
    const buttons = screen.getAllByRole("button", { name: "Retire" });
    fireEvent.click(buttons[buttons.length - 1]!);
    await waitFor(() => expect(deleteEndpoint).toHaveBeenCalledWith("ep-1"));
  });

  it("Cancel closes the confirm without deleting", async () => {
    banner([svc()]);
    open();
    fireEvent.click(await screen.findByRole("button", { name: "Retire" }));

    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));

    expect(deleteEndpoint).not.toHaveBeenCalled();
    expect(screen.queryByText("Retire the monitor for docs.example.com?")).toBeNull();
  });

  it("renders the identical banner whether or not the host resolves", async () => {
    // The chip used to branch on DNS ("STILL RESOLVING" vs "NOTHING RESOLVES") because DNS
    // decided whether the backend would delete the row. It no longer does, so there is one
    // banner saying one thing: down this long, and nothing said it was deleted.
    for (const dnsOk of [true, false]) {
      banner([svc({ dnsOk, error: dnsOk ? "HTTP 500" : "DNS: does not resolve" })]);
      expect(screen.getByText(/🗑 RETIRE: 1 stale monitor down 7d\+/)).toBeTruthy();
      expect(screen.getByText(/nothing says it was deleted — only you know/)).toBeTruthy();
      open();
      expect(await screen.findByRole("button", { name: "Retire" })).toBeTruthy();
      cleanup();
    }
  });

  it("the confirm EXPLAINS the DNS result without claiming it decides anything", async () => {
    banner([svc()]);
    open();
    fireEvent.click(await screen.findByRole("button", { name: "Retire" }));
    expect(screen.getByText(/It still resolves, but has been down/)).toBeTruthy();
    cleanup();

    // A dead name is the operator's call too, and the copy has to say why: not resolving is
    // not proof the deployment is gone, and nothing is going to remove this row for them.
    banner([svc({ dnsOk: false, error: "DNS: does not resolve" })]);
    open();
    fireEvent.click(await screen.findByRole("button", { name: "Retire" }));
    expect(screen.getByText(/has not resolved for/)).toBeTruthy();
    expect(screen.getByText(/only removed automatically once no platform project claims it/)).toBeTruthy();
  });
});
