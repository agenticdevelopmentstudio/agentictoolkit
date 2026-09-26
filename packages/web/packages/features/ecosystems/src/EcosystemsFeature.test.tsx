// @vitest-environment jsdom
//
// What EcosystemsFeature decides about its topic rows, through a real render: where a rename
// lands, and what a deep link draws while the ecosystem's features are still being read. The rules
// underneath (settingsLast, heldTopics) have unit tests of their own; these pin that the feature
// feeds them the right inputs.
//
// Harness as in ChildEcosystemsLevel.test.tsx: only the transport and the hooks that would reach it
// through the data module's OWN relative imports are replaced (vi.mock rewrites the
// "@agentic-toolkit/data/ecosystems" specifier, not those), so the mappers and types stay real.
import type { ReactNode } from "react";
import { describe, it, expect, vi, afterEach, beforeEach } from "vitest";
import { render, screen, cleanup, fireEvent, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { Ecosystem } from "@agentic-toolkit/data/ecosystems";

// Hoisted with the mock below, so the test can assert on the one `replace` every render's router
// hands out.
const { replace } = vi.hoisted(() => ({ replace: vi.fn() }));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace, prefetch: vi.fn() }),
}));

vi.mock("@agentic-toolkit/data/ecosystems", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/data/ecosystems")>()),
  ecosystemsApi: {
    list: vi.fn(),
    listChildren: vi.fn(),
    get: vi.fn(),
    ecosystemIdForSlug: vi.fn(),
    listForWorkspace: vi.fn(),
    delete: vi.fn(),
    update: vi.fn(),
  },
  useWorkspaceDefaultEcosystemId: vi.fn(() => ({
    ecosystemId: undefined,
    canManage: true,
    isPending: false,
    isError: false,
  })),
  useProvisionedFeatures: vi.fn(),
}));

// The real pane's rename runs a form, an availability probe and an update; all this file needs is
// the callback it ends on, so the stub offers that one action.
vi.mock("./EcosystemSettingsPane", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./EcosystemSettingsPane")>()),
  EcosystemSettingsPane: ({ onRenamed }: { onRenamed?: (newId: string) => void | Promise<void> }) => (
    <button type="button" onClick={() => void onRenamed?.("ecosystem.acme.gizmos")}>
      Rename to gizmos
    </button>
  ),
}));

import { EcosystemsFeature, IN_PACKAGE_TOPICS, type EcosystemsFeatureProps } from "./EcosystemsFeature";
import { ecosystemsApi, useProvisionedFeatures } from "@agentic-toolkit/data/ecosystems";

const ACME: Ecosystem = {
  id: "ecosystem.acme",
  identifier: "ecosystem.acme",
  slug: "acme",
  name: "Acme",
  description: "",
  region: "",
  domain: "",
  createdAt: "2026-01-01T00:00:00.000Z",
  updatedAt: "2026-01-01T00:00:00.000Z",
};

/** The provisioned read, answered: the ecosystem holds nothing. */
const HOLDS_NOTHING = { data: [], isPending: false, isError: false };
/** The provisioned read, not answered yet. */
const IN_FLIGHT = { data: undefined, isPending: true, isError: false };

beforeEach(() => {
  // ACME must be in `list()`'s answer, or the feature takes its hidden-default side quest.
  vi.mocked(ecosystemsApi.list).mockResolvedValue([ACME]);
  vi.mocked(ecosystemsApi.listChildren).mockResolvedValue([]);
  vi.mocked(useProvisionedFeatures).mockReturnValue(HOLDS_NOTHING as never);
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

function renderFeature(props: Pick<EcosystemsFeatureProps, "topics" | "activeTopic" | "renderTopicPane">) {
  // A fresh client per test: the feature's own queries read react-query through context.
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <EcosystemsFeature basePath="/ecosystems" activeEcoId={ACME.id} {...props} />
    </QueryClientProvider>,
  );
}

describe("renaming from Settings", () => {
  // It used to go to the list's FIRST row, and settingsLast puts Settings at the end: a rename
  // took the user off the pane they were editing, onto Child Ecosystems.
  it("lands back on Settings, under the new id", async () => {
    renderFeature({ topics: IN_PACKAGE_TOPICS, activeTopic: "settings" });
    fireEvent.click(await screen.findByRole("button", { name: "Rename to gizmos" }));
    await waitFor(() =>
      expect(replace).toHaveBeenCalledWith("/ecosystems/ecosystem.acme.gizmos/settings", {
        scroll: false,
      }),
    );
  });
});

describe("a deep link to a feature row, while the provisioned read is in flight", () => {
  const INTEGRATIONS = { id: "integrations", label: "Integrations", icon: null, features: ["integrations"] };
  // A pane the host owns; "integrations" is not a group, so its row renders it directly.
  const renderTopicPane = (id: string): ReactNode =>
    id === "integrations" ? <p>the integrations pane</p> : null;

  // Keyed rows are withheld until the read lands, and the routed one used to be too — the deep
  // link drew "Select a topic to view." beside a list holding only Settings.
  it("draws the routed feature's pane", async () => {
    vi.mocked(useProvisionedFeatures).mockReturnValue(IN_FLIGHT as never);
    renderFeature({ topics: [INTEGRATIONS, ...IN_PACKAGE_TOPICS], activeTopic: "integrations", renderTopicPane });
    expect(await screen.findByText("the integrations pane")).toBeInTheDocument();
    expect(screen.queryByText("Select a topic to view.")).toBeNull();
  });
});

const INTEGRATIONS_ROW = { id: "integrations", label: "Integrations", icon: null, features: ["integrations"] };
const integrationsPane = (id: string): ReactNode =>
  id === "integrations" ? <p>the integrations pane</p> : null;

// `isError` is also true when a REFRESH fails behind an answer already in hand. Reading it showed
// every product topic, held or not, the moment a background refetch hiccupped.
describe("a failed provisioned read", () => {
  it("keeps the rows its last answer held when only a refresh failed", async () => {
    vi.mocked(useProvisionedFeatures).mockReturnValue({
      data: [],
      isPending: false,
      isError: true,
      isLoadingError: false,
    } as never);
    renderFeature({ topics: [INTEGRATIONS_ROW, ...IN_PACKAGE_TOPICS], activeTopic: "settings" });
    expect(await screen.findByRole("button", { name: "Rename to gizmos" })).toBeInTheDocument();
    expect(screen.queryByText("Integrations")).toBeNull();
  });

  it("shows every row when the read failed with no answer at all", async () => {
    vi.mocked(useProvisionedFeatures).mockReturnValue({
      data: undefined,
      isPending: false,
      isError: true,
      isLoadingError: true,
    } as never);
    renderFeature({ topics: [INTEGRATIONS_ROW, ...IN_PACKAGE_TOPICS], activeTopic: "settings" });
    expect(await screen.findByText("Integrations")).toBeInTheDocument();
  });
});

// A feature stuck in `provisioning` was ticked in Manage features and nowhere in this list.
describe("a feature still provisioning", () => {
  it("is listed, marked, and opens onto a notice instead of its pane", async () => {
    vi.mocked(useProvisionedFeatures).mockReturnValue({
      data: [{ featureKey: "integrations", state: "provisioning", provisionedAt: "", provisionedBy: null }],
      isPending: false,
      isError: false,
      isLoadingError: false,
    } as never);
    renderFeature({
      topics: [INTEGRATIONS_ROW, ...IN_PACKAGE_TOPICS],
      activeTopic: "integrations",
      renderTopicPane: integrationsPane,
    });
    expect(await screen.findByText("Integrations is still being set up")).toBeInTheDocument();
    expect(screen.getByText("Provisioning…")).toBeInTheDocument();
    expect(screen.queryByText("the integrations pane")).toBeNull();
  });
});

// The default-ecosystem lookup: a refetch that fails behind a resolved id is not "didn't resolve".
describe("a failed re-read of the workspace's default ecosystem", () => {
  it("keeps the resolved ecosystem instead of the couldn't-load notice", async () => {
    vi.mocked(ecosystemsApi.ecosystemIdForSlug).mockRejectedValue(new Error("boom"));
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    // A resolution already in hand, stale, so the mount re-reads it — and that read fails.
    qc.setQueryData(["ecosystem-id-for-slug", "acme"], ACME.id);
    render(
      <QueryClientProvider client={qc}>
        <EcosystemsFeature basePath="/ecosystems" workspaceSlug="acme" topics={IN_PACKAGE_TOPICS} activeTopic="settings" />
      </QueryClientProvider>,
    );
    await waitFor(() => expect(ecosystemsApi.ecosystemIdForSlug).toHaveBeenCalled());
    expect(await screen.findByRole("button", { name: "Rename to gizmos" })).toBeInTheDocument();
    expect(screen.queryByText("Couldn't load this workspace")).toBeNull();
  });

  it("still says so when the FIRST read fails", async () => {
    vi.mocked(ecosystemsApi.ecosystemIdForSlug).mockRejectedValue(new Error("boom"));
    const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={qc}>
        <EcosystemsFeature basePath="/ecosystems" workspaceSlug="acme" topics={IN_PACKAGE_TOPICS} />
      </QueryClientProvider>,
    );
    expect(await screen.findByText("Couldn't load this workspace")).toBeInTheDocument();
  });
});

// Manage features and the Features heading belong to a list whose rows ARE features.
describe("the Manage features action", () => {
  it("is offered when some row is a catalog feature", async () => {
    renderFeature({ topics: [INTEGRATIONS_ROW, ...IN_PACKAGE_TOPICS], activeTopic: "settings" });
    expect(await screen.findByRole("button", { name: "Manage ecosystem features" })).toBeInTheDocument();
  });

  it("is not offered when no row is (Games, Gamification)", async () => {
    renderFeature({ topics: IN_PACKAGE_TOPICS, activeTopic: "settings" });
    expect(await screen.findByRole("button", { name: "Rename to gizmos" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Manage ecosystem features" })).toBeNull();
  });
});
