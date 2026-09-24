/// <reference types="@testing-library/jest-dom/vitest" />
import type { ReactElement } from "react";
import { render, screen, cleanup, act } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { QueryClient, QueryClientProvider, notifyManager } from "@tanstack/react-query";

// Only the transport, so the client, its query keys and its cache are all the real ones.
vi.mock("../../http", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../http")>()),
  authedRequest: vi.fn(),
  authedJson: vi.fn(),
}));

import { ecosystemFeaturesApi, useApplyFeatureChange } from "../ecosystem-features";
import { authedRequest, authedJson } from "../../http";

// Notify observers synchronously — react-query's default scheduler batches into a macrotask,
// and these tests read mutation state right after `act`, not through a `waitFor`.
notifyManager.setScheduler((cb) => cb());

const mockedRequest = vi.mocked(authedRequest);
const mockedJson = vi.mocked(authedJson);

/** A status-carrying HTTP error, the shape `isNotFound` duck-types on. */
const httpError = (status: number) => Object.assign(new Error(`HTTP ${status}`), { status });

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe("ecosystemFeaturesApi.remove", () => {
  // A double-click, a stale list, or a second tab racing the same removal all land here: the row
  // is already gone, which is the caller's goal either way, so a 404 must resolve, not throw.
  it("treats a 404 as success — the row is already gone", async () => {
    mockedRequest.mockRejectedValueOnce(httpError(404));
    await expect(ecosystemFeaturesApi.remove("eco-1", "widgets")).resolves.toBeUndefined();
  });

  it("still throws on a real failure", async () => {
    mockedRequest.mockRejectedValueOnce(httpError(500));
    await expect(ecosystemFeaturesApi.remove("eco-1", "widgets")).rejects.toThrow("HTTP 500");
  });

  it("resolves normally when the DELETE succeeds outright", async () => {
    mockedRequest.mockResolvedValueOnce(undefined);
    await expect(ecosystemFeaturesApi.remove("eco-1", "widgets")).resolves.toBeUndefined();
  });
});

describe("useApplyFeatureChange", () => {
  function Probe({ ecosystemId }: { ecosystemId: string }): ReactElement {
    const apply = useApplyFeatureChange(ecosystemId);
    return (
      <div>
        <button onClick={() => apply.mutate({ add: [], remove: ["a", "b", "c"] })}>go</button>
        <div data-testid="status">{apply.status}</div>
        <div data-testid="error">{apply.error instanceof Error ? apply.error.message : ""}</div>
      </div>
    );
  }

  function mount() {
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <Probe ecosystemId="eco-1" />
      </QueryClientProvider>,
    );
  }

  // Sequential `for … await` removal would abort on the first rejection and never attempt "c".
  // `Promise.allSettled` must let every removal run, then fail loudly by name for the ones that
  // didn't make it — not silently drop them.
  it("runs every removal even when one fails, and names the failed keys", async () => {
    mockedJson.mockResolvedValueOnce({ features: [] }); // no adds requested, but guard anyway
    mockedRequest
      .mockResolvedValueOnce(undefined) // a
      .mockRejectedValueOnce(httpError(500)) // b
      .mockResolvedValueOnce(undefined); // c

    mount();
    await act(async () => {
      screen.getByText("go").click();
    });

    // All three DELETEs were issued despite "b" failing.
    expect(mockedRequest).toHaveBeenCalledTimes(3);
    expect(screen.getByTestId("status").textContent).toBe("error");
    expect(screen.getByTestId("error").textContent).toBe("Couldn't remove: b");
  });

  it("succeeds when every removal succeeds (or is a 404, already-gone)", async () => {
    mockedRequest
      .mockResolvedValueOnce(undefined) // a
      .mockRejectedValueOnce(httpError(404)) // b — already gone, counts as success
      .mockResolvedValueOnce(undefined); // c

    mount();
    await act(async () => {
      screen.getByText("go").click();
    });

    expect(screen.getByTestId("status").textContent).toBe("success");
    expect(screen.getByTestId("error").textContent).toBe("");
  });
});
