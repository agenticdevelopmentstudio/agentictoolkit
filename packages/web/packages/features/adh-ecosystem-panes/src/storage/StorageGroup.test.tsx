// @vitest-environment jsdom
import type { ReactNode } from "react";
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

// A workspace with no infrastructure ecosystem showed "Loading…" forever on All Data, and Buckets
// listed every bucket unscoped and opened rows from other ecosystems: both panes were handed an
// `undefined` ecosystem that meant "still asking" and "there is none" alike. The group now settles
// that itself, so these stand-ins only say what they were handed — the gate is the group's.
vi.mock("../schemas/SchemasPane", () => ({
  SchemasPane: ({ ecosystemId }: { ecosystemId?: string }) => (
    <p>{`Buckets pane for ${String(ecosystemId)}`}</p>
  ),
}));
vi.mock("./AllDataPane", () => ({
  AllDataPane: ({ ecosystemId }: { ecosystemId?: string }) => (
    <p>{`All Data pane for ${String(ecosystemId)}`}</p>
  ),
}));

import { RailHostContext } from "@agentic-toolkit/resource";
import type { RailHostRegistry } from "@agentic-toolkit/resource";
import { StorageGroup } from "./StorageGroup";
import type { EcosystemScopeResolution } from "./StorageGroup";

// A host that draws nothing: the member is chosen through `urlSelection`, so the rail the group
// publishes has nowhere it needs to go. Present only so the group's boundary passes through.
const HOST: RailHostRegistry = {
  registerLevels: () => {},
  unregisterLevels: () => {},
  registerExitGuard: () => {},
  popStack: () => {},
  reportMissing: () => {},
  reportBusy: () => {},
  toolbarSlot: null,
};

const IN_FLIGHT: EcosystemScopeResolution = { canManage: true, isError: false, isPending: true };
const NO_ECOSYSTEM: EcosystemScopeResolution = { canManage: true, isError: false, isPending: false };
const RESOLVED: EcosystemScopeResolution = {
  ecosystemId: "ecosystem.acme",
  canManage: true,
  isError: false,
  isPending: false,
};

function renderMember(
  memberId: string,
  scope: EcosystemScopeResolution,
  renderAllData?: (ecosystemId: string | undefined) => ReactNode,
) {
  return render(
    <RailHostContext.Provider value={HOST}>
      <StorageGroup
        scope={scope}
        workspaceSlug="acme"
        urlSelection={{ selectedId: memberId, onSelect: () => {} }}
        renderAllData={renderAllData}
      />
    </RailHostContext.Provider>,
  );
}

afterEach(cleanup);

describe("StorageGroup — Buckets and All Data mount only with a resolved ecosystem", () => {
  it.each(["buckets", "all-data"])("%s shows Loading… while the lookup is in flight", (member) => {
    const renderAllData = vi.fn();
    renderMember(member, IN_FLIGHT, renderAllData);
    expect(screen.getByText("Loading…")).toBeInTheDocument();
    expect(screen.queryByText(/pane for/)).not.toBeInTheDocument();
    expect(renderAllData).not.toHaveBeenCalled();
  });

  it.each(["buckets", "all-data"])(
    "%s says there is no ecosystem once the lookup settles without one",
    (member) => {
      const renderAllData = vi.fn();
      renderMember(member, NO_ECOSYSTEM, renderAllData);
      expect(screen.getByText("This workspace has no ecosystem yet.")).toBeInTheDocument();
      expect(screen.queryByText("Loading…")).not.toBeInTheDocument();
      expect(screen.queryByText(/pane for/)).not.toBeInTheDocument();
      expect(renderAllData).not.toHaveBeenCalled();
    },
  );

  it.each([
    ["buckets", "Buckets pane for ecosystem.acme"],
    ["all-data", "All Data pane for ecosystem.acme"],
  ])("%s mounts its pane scoped to the resolved ecosystem", (member, pane) => {
    renderMember(member, RESOLVED);
    expect(screen.getByText(pane)).toBeInTheDocument();
  });

  it("a host's own All Data is handed the resolved ecosystem", () => {
    const renderAllData = vi.fn((id: string | undefined) => <p>{`Host All Data for ${String(id)}`}</p>);
    renderMember("all-data", RESOLVED, renderAllData);
    expect(renderAllData).toHaveBeenCalledWith("ecosystem.acme");
    expect(screen.getByText("Host All Data for ecosystem.acme")).toBeInTheDocument();
  });

  it("a failed lookup still shows the retry surface, not the no-ecosystem notice", () => {
    // A failed lookup settles with no id and `isPending` false — the same shape as "no ecosystem",
    // which is why the error branch has to stay ahead of the members' gate.
    renderMember("all-data", { canManage: true, isError: true, isPending: false });
    expect(screen.getByText("Couldn't load this workspace")).toBeInTheDocument();
    expect(screen.queryByText("This workspace has no ecosystem yet.")).not.toBeInTheDocument();
  });

  it("a re-read failing behind a resolved ecosystem keeps the panes on it", () => {
    // react-query's `isError` stays true when a background refetch fails behind the answer on
    // screen. That is not a failed resolution: the id is still known and still right.
    const renderAllData = vi.fn((id: string | undefined) => <p>{`Host All Data for ${String(id)}`}</p>);
    renderMember("all-data", { ...RESOLVED, isError: true }, renderAllData);
    expect(screen.getByText("Host All Data for ecosystem.acme")).toBeInTheDocument();
    expect(screen.queryByText("Couldn't load this workspace")).not.toBeInTheDocument();
  });
});
