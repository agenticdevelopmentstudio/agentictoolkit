/// <reference types="@testing-library/jest-dom/vitest" />
//
// THE RESOLVER SAYS WHEN IT IS READING, NOT ONLY WHEN IT HAS NOTHING.
//
// `isPending` answers "is there an answer yet", so it is false on every mount after the first —
// the resolution is cached. A host wired to it reports the very first visit and then goes quiet
// forever, even on the mounts that DO re-read behind the copy already on screen: the ones whose
// cached entry has gone stale, which is every mount after a write or after the client's freshness
// window passes.
// `isFetching` is the wider flag, and the second mount below is the case that separates them: an
// id and a read in flight at the same moment.
import type { ReactElement } from "react";
import { render, screen, cleanup, act } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { QueryClientProvider, notifyManager } from "@tanstack/react-query";

// Only the transport, so the hook, its key and its cache are all the real ones.
vi.mock("../../http", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../http")>()),
  authedJson: vi.fn(),
}));

import { useWorkspaceDefaultEcosystemId } from "../use-workspace-default-ecosystem";
import { getToolkitQueryClient } from "../../query";
import { authedJson } from "../../http";

// Notify observers SYNCHRONOUSLY. react-query's default scheduler is a real `setTimeout(fn, 0)`,
// and "a read is in flight" is a state these tests stand in rather than a frame they wait for —
// with the default scheduler each assertion below would have to become a `waitFor`, which also
// passes on the value already rendered and so cannot tell a started read from an unstarted one.
notifyManager.setScheduler((cb) => cb());

const mockedJson = vi.mocked(authedJson);

/** The one infrastructure row the resolver reads `id` and `canManage` off. */
const ROW = [{ id: "eco-1", canManage: true }];

/** The app's own client, not one made here: the hook passes `getToolkitQueryClient()` to
 *  `useQuery` explicitly, so a client handed down through a provider is never the one it reads —
 *  a local client would leave these assertions describing a cache the hook does not use. It is a
 *  module-scope singleton, which is also what makes the second mount below a CACHED visit: the
 *  entry outlives the first one, exactly as it does in a tab. */
const qc = getToolkitQueryClient();

function Probe(): ReactElement {
  const { ecosystemId, isPending, isFetching } = useWorkspaceDefaultEcosystemId("acme");
  return (
    <div data-testid="probe" data-pending={isPending} data-fetching={isFetching}>
      {ecosystemId ?? "none"}
    </div>
  );
}

const mount = () =>
  render(
    <QueryClientProvider client={qc}>
      <Probe />
    </QueryClientProvider>,
  );

const probe = () => screen.getByTestId("probe");

/** Holds the next read open and hands back the lever that lands it, so the in-flight moment is
 *  a place to make assertions from instead of a race. */
function heldRead(): () => Promise<void> {
  let land: () => void = () => {
    throw new Error("the resolution was never requested");
  };
  mockedJson.mockImplementation(
    () => new Promise<unknown>((resolve) => (land = () => resolve(ROW))),
  );
  return async () => {
    await act(async () => {
      land();
    });
  };
}

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe("useWorkspaceDefaultEcosystemId", () => {
  it("reports a read in flight on a CACHED mount, where there is nothing pending", async () => {
    const landFirst = heldRead();
    mount();

    // The first visit: no answer yet, so both flags agree.
    expect(probe().dataset.pending).toBe("true");
    expect(probe().dataset.fetching).toBe("true");
    await landFirst();
    expect(probe().textContent).toBe("eco-1");
    expect(probe().dataset.fetching).toBe("false");
    cleanup();

    // Age the entry. The toolkit client holds a resolution FRESH for five minutes, so a remount
    // inside that window is served from cache and starts no read at all — which is the caching
    // working, not a case worth asserting. Invalidating with nothing mounted marks the entry
    // stale without fetching (`refetchType: "active"`, and there is no active observer), so the
    // mount below is the real case: a cached answer AND a re-read, the way it looks after a write
    // or once the window has passed.
    await qc.invalidateQueries({ queryKey: ["workspace-default-ecosystem"] });

    // The second visit. The id is served from cache with no gap, and the re-read behind it is
    // the whole reason `isFetching` exists here: `isPending` is false throughout.
    const landSecond = heldRead();
    mount();
    expect(probe().textContent).toBe("eco-1");
    expect(probe().dataset.pending).toBe("false");
    expect(probe().dataset.fetching).toBe("true");

    await landSecond();
    expect(probe().dataset.fetching).toBe("false");
  });
});

// A failed re-read behind an answer already in hand is not a failed resolution. A gate on
// `isError` replaced a working pane with "couldn't resolve" the moment a background refetch
// hiccupped; `isLoadingError` is true only when the failure left NO answer.
function ErrorProbe({ slug }: { slug: string }): ReactElement {
  const { ecosystemId, isError, isLoadingError } = useWorkspaceDefaultEcosystemId(slug);
  return (
    <div data-testid="err" data-error={isError} data-loading-error={isLoadingError}>
      {ecosystemId ?? "none"}
    </div>
  );
}

const mountErr = (slug: string) =>
  render(
    <QueryClientProvider client={qc}>
      <ErrorProbe slug={slug} />
    </QueryClientProvider>,
  );

describe("useWorkspaceDefaultEcosystemId failures", () => {
  it("reports a failed FIRST read as a loading error", async () => {
    mockedJson.mockRejectedValue(new Error("boom"));
    mountErr("first-fails");
    await act(async () => {});
    const el = screen.getByTestId("err");
    expect(el.textContent).toBe("none");
    expect(el.dataset.error).toBe("true");
    expect(el.dataset.loadingError).toBe("true");
  });

  it("keeps the answer, and no loading error, when a re-read fails behind it", async () => {
    mockedJson.mockResolvedValue(ROW);
    mountErr("refetch-fails");
    await act(async () => {});
    expect(screen.getByTestId("err").textContent).toBe("eco-1");

    mockedJson.mockRejectedValue(new Error("boom"));
    await act(async () => {
      await qc.refetchQueries({ queryKey: ["workspace-default-ecosystem"] });
    });
    const el = screen.getByTestId("err");
    expect(el.textContent).toBe("eco-1");
    expect(el.dataset.error).toBe("true");
    expect(el.dataset.loadingError).toBe("false");
  });
});
