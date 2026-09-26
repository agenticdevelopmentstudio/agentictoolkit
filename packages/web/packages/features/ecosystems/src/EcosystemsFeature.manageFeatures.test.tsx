// @vitest-environment jsdom
//
// The Manage features dialog outlives the rail toolbar its button sits in.
//
// ResourceExplorer draws `topicsTitleActions` inside the topics rail, and HierarchicalTopicDetail's
// narrow, minimized and covered stacks are different component types — a window crossing a
// breakpoint remounts the rail. The dialog used to be owned by the button, so that remount closed
// it under the user: the pending ticks went, and an apply in flight lost the only thing that would
// report it. EcosystemsFeature owns it now.
//
// ResourceExplorer is replaced by a stand-in whose toolbar can be remounted on demand — a real
// breakpoint crossing is a layout jsdom does not do — and which reports the heading it was handed.
import { useState, type ReactNode } from "react";
import { describe, it, expect, vi, afterEach, beforeEach } from "vitest";
import { render, screen, cleanup, fireEvent } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { Ecosystem } from "@agentic-toolkit/data/ecosystems";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
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
    isLoadingError: false,
  })),
  useProvisionedFeatures: vi.fn(() => ({ data: [], isPending: false, isError: false })),
}));

vi.mock("@agentic-toolkit/resource", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/resource")>()),
  ResourceExplorer: function StandInExplorer({
    activeId,
    topicsTitle,
    topicsTitleActions,
  }: {
    activeId?: string;
    topicsTitle?: string;
    topicsTitleActions?: (id: string) => ReactNode;
  }) {
    const [generation, setGeneration] = useState(0);
    return (
      <div>
        <p>heading: {topicsTitle ?? "(entity name)"}</p>
        <button type="button" onClick={() => setGeneration((g) => g + 1)}>
          cross a breakpoint
        </button>
        {/* A new key is a new toolbar: everything under it unmounts and mounts fresh. */}
        <div key={generation}>{activeId && topicsTitleActions?.(activeId)}</div>
      </div>
    );
  },
}));

// The dialog's own reads are not the point; its STATE is. A tick counter stands in for the
// pending selection: if the dialog remounts, it is back to zero.
vi.mock("./ManageFeaturesDialog", () => ({
  ManageFeaturesDialog: function StandInDialog({
    ecosystemId,
    onClose,
  }: {
    ecosystemId: string;
    onClose: () => void;
  }) {
    const [ticks, setTicks] = useState(0);
    return (
      <div role="dialog" aria-label={`manage ${ecosystemId}`}>
        <button type="button" onClick={() => setTicks((n) => n + 1)}>
          tick
        </button>
        <span>ticks: {ticks}</span>
        <button type="button" onClick={onClose}>
          close
        </button>
      </div>
    );
  },
}));

import { EcosystemsFeature, IN_PACKAGE_TOPICS, type EcosystemsFeatureProps } from "./EcosystemsFeature";
import { ecosystemsApi } from "@agentic-toolkit/data/ecosystems";

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

const FEATURE_ROW = { id: "integrations", label: "Integrations", icon: null, features: ["integrations"] };

beforeEach(() => {
  vi.mocked(ecosystemsApi.list).mockResolvedValue([ACME]);
  vi.mocked(ecosystemsApi.listForWorkspace).mockResolvedValue([ACME]);
  vi.mocked(ecosystemsApi.listChildren).mockResolvedValue([]);
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

function renderFeature(props: Partial<EcosystemsFeatureProps>) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <EcosystemsFeature basePath="/ecosystems" activeEcoId={ACME.id} topics={IN_PACKAGE_TOPICS} {...props} />
    </QueryClientProvider>,
  );
}

describe("the Manage features dialog", () => {
  it("stays open, with its pending state, when the rail toolbar remounts", async () => {
    renderFeature({ topics: [FEATURE_ROW, ...IN_PACKAGE_TOPICS] });
    fireEvent.click(await screen.findByRole("button", { name: "Manage ecosystem features" }));
    expect(screen.getByRole("dialog", { name: "manage ecosystem.acme" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "tick" }));
    fireEvent.click(screen.getByRole("button", { name: "tick" }));

    fireEvent.click(screen.getByRole("button", { name: "cross a breakpoint" }));

    expect(screen.getByRole("dialog", { name: "manage ecosystem.acme" })).toBeInTheDocument();
    expect(screen.getByText("ticks: 2")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "close" }));
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("is also owned by the feature in the list-first (Products) layout", async () => {
    renderFeature({ listFirst: true, workspaceSlug: "acme", topics: [FEATURE_ROW, ...IN_PACKAGE_TOPICS] });
    fireEvent.click(await screen.findByRole("button", { name: "Manage ecosystem features" }));
    fireEvent.click(screen.getByRole("button", { name: "tick" }));
    fireEvent.click(screen.getByRole("button", { name: "cross a breakpoint" }));
    expect(screen.getByText("ticks: 1")).toBeInTheDocument();
  });
});

describe("the list-first topics heading", () => {
  it("is 'Features' when the rows are features", async () => {
    renderFeature({ listFirst: true, workspaceSlug: "acme", topics: [FEATURE_ROW, ...IN_PACKAGE_TOPICS] });
    expect(await screen.findByText("heading: Features")).toBeInTheDocument();
  });

  // Games and Gamification list their own topics, none of them a catalog feature.
  it("is the entity's name, with no Manage action, when no row is a feature", async () => {
    renderFeature({ listFirst: true, workspaceSlug: "acme", topics: IN_PACKAGE_TOPICS });
    expect(await screen.findByText("heading: (entity name)")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Manage ecosystem features" })).toBeNull();
  });
});
