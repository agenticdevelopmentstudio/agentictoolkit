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
