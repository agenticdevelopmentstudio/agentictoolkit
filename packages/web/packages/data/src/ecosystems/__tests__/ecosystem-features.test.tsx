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

import {
  ecosystemFeaturesApi,
  useApplyFeatureChange,
  FeatureRequiredError,
  removalLevels,
  type CatalogFeature,
} from "../ecosystem-features";
import { authedRequest, authedJson } from "../../http";
import { AuthHttpError } from "@agentic-toolkit/auth/client";

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

  // The backend's DELETE returns 409 `{ error: { code: "feature_required", message, neededBy } }`
  // when another active feature still needs this one (ecosystemFeatures.ts ~line 136). The picker
  // needs `neededBy` to name the blocking features, not just a generic failure message — so this
  // must surface as a typed FeatureRequiredError, not the plain AuthHttpError every other 4xx gets.
  it("maps a 409 feature_required response to a typed FeatureRequiredError", async () => {
    const body = {
      error: {
        code: "feature_required",
        message: "this feature is needed by Client Auth",
        neededBy: ["signin-apps"],
      },
    };
    mockedRequest.mockRejectedValueOnce(
      new AuthHttpError(409, body.error.message, body.error.code, body),
    );

    const rejection = ecosystemFeaturesApi.remove("eco-1", "users");
    await expect(rejection).rejects.toBeInstanceOf(FeatureRequiredError);
    await expect(rejection).rejects.toThrow("this feature is needed by Client Auth");
    await rejection.catch((err: FeatureRequiredError) => {
      expect(err.neededBy).toEqual(["signin-apps"]);
    });
  });

  // A 409 with a different code (or no structured body at all) is not a feature-requirement
  // conflict — it must pass through unchanged rather than being coerced into FeatureRequiredError.
  it("leaves a 409 with no feature_required body as a plain error", async () => {
    mockedRequest.mockRejectedValueOnce(new AuthHttpError(409, "some other conflict"));
    await expect(ecosystemFeaturesApi.remove("eco-1", "widgets")).rejects.not.toBeInstanceOf(
      FeatureRequiredError,
    );
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
        <div data-testid="required">{apply.error instanceof FeatureRequiredError ? "yes" : "no"}</div>
        <div data-testid="other-failures">
          {apply.error instanceof FeatureRequiredError ? apply.error.otherFailures.join(",") : ""}
        </div>
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

  // A race with another session: it added something, between the picker's confirm and this DELETE
  // landing, that now needs the key being removed. That is the ONE removal failure worth naming —
  // rethrown as the typed FeatureRequiredError itself, not folded into the generic "Couldn't
  // remove: b" every other failure gets, so the caller (ManageFeaturesDialog) can tell them apart.
  it("rethrows a FeatureRequiredError from a removal instead of the generic message", async () => {
    mockedRequest
      .mockResolvedValueOnce(undefined) // a
      .mockRejectedValueOnce(
        new AuthHttpError(409, "this feature is needed by Client Auth", "feature_required", {
          error: { code: "feature_required", message: "this feature is needed by Client Auth", neededBy: ["signin-apps"] },
        }),
      ) // b
      .mockResolvedValueOnce(undefined); // c

    mount();
    await act(async () => {
      screen.getByText("go").click();
    });

    expect(screen.getByTestId("status").textContent).toBe("error");
    expect(screen.getByTestId("required").textContent).toBe("yes");
    expect(screen.getByTestId("error").textContent).toBe("this feature is needed by Client Auth");
  });

  // Two removals fail in the same batch — "b" a FeatureRequiredError, "c" a plain 500. The old
  // code found the FeatureRequiredError and threw ONLY it, dropping "c" on the floor entirely:
  // the picker would say Users is needed by Client Auth and never mention that "c" also failed.
  // Nothing may be swallowed — "c" must still be named, on the thrown error itself.
  it("keeps every other failed key when a FeatureRequiredError is thrown, not just the first", async () => {
    mockedRequest
      .mockResolvedValueOnce(undefined) // a
      .mockRejectedValueOnce(
        new AuthHttpError(409, "this feature is needed by Client Auth", "feature_required", {
          error: { code: "feature_required", message: "this feature is needed by Client Auth", neededBy: ["signin-apps"] },
        }),
      ) // b
      .mockRejectedValueOnce(httpError(500)); // c

    mount();
    await act(async () => {
      screen.getByText("go").click();
    });

    expect(mockedRequest).toHaveBeenCalledTimes(3);
    expect(screen.getByTestId("status").textContent).toBe("error");
    expect(screen.getByTestId("required").textContent).toBe("yes");
    expect(screen.getByTestId("error").textContent).toBe("this feature is needed by Client Auth");
    expect(screen.getByTestId("other-failures").textContent).toBe("c");
  });
});

describe("useApplyFeatureChange — removal order", () => {
  afterEach(() => {
    mockedJson.mockReset();
    mockedRequest.mockReset();
  });

  // `signin-apps` requires `users`: the backend refuses DELETE users with a 409 while signin-apps
  // is still active, so a picker visit that removes BOTH must send signin-apps first and let it
  // settle before users goes out. Sent in parallel, the users DELETE could land first and fail.
  const CATALOG = {
    features: [
      { key: "users", label: "Users", description: "", subscriptionTier: "Free" },
      {
        key: "signin-apps",
        label: "Client Auth",
        description: "",
        subscriptionTier: "Free",
        requiresFeatures: ["users"],
      },
    ],
  };

  function Probe({ remove }: { remove: string[] }): ReactElement {
    const apply = useApplyFeatureChange("eco-1");
    return (
      <div>
        <button onClick={() => apply.mutate({ add: [], remove })}>go</button>
        <div data-testid="status">{apply.status}</div>
      </div>
    );
  }

  it("sends a dependent's DELETE and lets it settle before the DELETE of what it requires", async () => {
    mockedJson.mockImplementation(async (url: string) => {
      if (url.endsWith("/catalog")) return CATALOG;
      throw new Error(`unexpected GET ${url}`);
    });
    const calls: string[] = [];
    let settleSigninApps: () => void = () => undefined;
    mockedRequest.mockImplementation((url: string) => {
      calls.push(url);
      if (url.endsWith("/signin-apps")) {
        return new Promise<void>((resolve) => {
          settleSigninApps = () => resolve();
        });
      }
      return Promise.resolve();
    });

    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <Probe remove={["users", "signin-apps"]} />
      </QueryClientProvider>,
    );
    await act(async () => {
      screen.getByText("go").click();
    });

    // signin-apps is in flight; users must not have been sent yet.
    expect(calls).toEqual(["/api/ecosystem/features/eco-1/signin-apps"]);

    await act(async () => {
      settleSigninApps();
    });

    expect(calls).toEqual([
      "/api/ecosystem/features/eco-1/signin-apps",
      "/api/ecosystem/features/eco-1/users",
    ]);
    expect(screen.getByTestId("status").textContent).toBe("success");
  });

  it("orders by the listed catalog: a key whose included feature needs another goes first", async () => {
    // Applications requires nothing itself, but Client Auth comes with it and needs Users.
    mockedJson.mockImplementation(async (url: string) => {
      if (url.endsWith("/catalog")) {
        return {
          features: [
            { key: "users", label: "Users", description: "", subscriptionTier: "Free" },
            { key: "applications", label: "Applications", description: "", subscriptionTier: "Free" },
            {
              key: "client-auth",
              label: "Client Auth",
              description: "",
              subscriptionTier: "Free",
              requiresFeatures: ["users"],
              includedWith: "applications",
            },
          ],
        };
      }
      throw new Error(`unexpected GET ${url}`);
    });
    const calls: string[] = [];
    let settleApplications: () => void = () => undefined;
    mockedRequest.mockImplementation((url: string) => {
      calls.push(url);
      if (url.endsWith("/applications")) {
        return new Promise<void>((resolve) => {
          settleApplications = () => resolve();
        });
      }
      return Promise.resolve();
    });

    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <Probe remove={["users", "applications"]} />
      </QueryClientProvider>,
    );
    await act(async () => {
      screen.getByText("go").click();
    });

    expect(calls).toEqual(["/api/ecosystem/features/eco-1/applications"]);
    await act(async () => {
      settleApplications();
    });
    expect(calls).toEqual([
      "/api/ecosystem/features/eco-1/applications",
      "/api/ecosystem/features/eco-1/users",
    ]);
  });

  it("still sends the required key after its dependent failed, and reports both by the usual rules", async () => {
    mockedJson.mockImplementation(async (url: string) => {
      if (url.endsWith("/catalog")) return CATALOG;
      throw new Error(`unexpected GET ${url}`);
    });
    const calls: string[] = [];
    mockedRequest.mockImplementation((url: string) => {
      calls.push(url);
      return Promise.reject(httpError(500));
    });

    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <Probe remove={["users", "signin-apps"]} />
      </QueryClientProvider>,
    );
    await act(async () => {
      screen.getByText("go").click();
    });

    expect(calls).toEqual([
      "/api/ecosystem/features/eco-1/signin-apps",
      "/api/ecosystem/features/eco-1/users",
    ]);
    expect(screen.getByTestId("status").textContent).toBe("error");
  });
});

describe("removalLevels", () => {
  const f = (key: string, requiresFeatures?: string[]): CatalogFeature => ({
    key,
    label: key,
    description: "",
    subscriptionTier: "Free",
    ...(requiresFeatures ? { requiresFeatures } : {}),
  });
  const catalog = [
    f("users"),
    f("user-authentication", ["users"]),
    f("signin-apps", ["users", "user-authentication"]),
    f("notes"),
  ];

  it("puts dependents before what they require, one level per step", () => {
    expect(removalLevels(["users", "user-authentication", "signin-apps"], catalog)).toEqual([
      ["signin-apps"],
      ["user-authentication"],
      ["users"],
    ]);
  });

  it("keeps independent keys in one parallel level, in the caller's order", () => {
    expect(removalLevels(["notes", "signin-apps", "users"], catalog)).toEqual([["notes", "signin-apps"], ["users"]]);
  });

  it("follows requirements transitively through a key that is not in the batch", () => {
    const chain = [f("a", ["b"]), f("b", ["c"]), f("c")];
    expect(removalLevels(["c", "a"], chain)).toEqual([["a"], ["c"]]);
  });

  it("treats a key the catalog does not know as requiring nothing", () => {
    expect(removalLevels(["mystery", "users"], catalog)).toEqual([["mystery", "users"]]);
  });

  it("terminates on a cycle", () => {
    const loop = [f("x", ["y"]), f("y", ["x"])];
    expect(removalLevels(["x", "y"], loop).flat().sort()).toEqual(["x", "y"]);
  });
});
