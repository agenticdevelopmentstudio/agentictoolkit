// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

const resolution = vi.fn();
vi.mock("@agentic-toolkit/data/ecosystems", () => ({
  useWorkspaceDefaultEcosystemId: (slug: string | undefined) => resolution(slug),
}));

import { WorkspaceKnowledgeBases } from "./WorkspaceKnowledgeBases";

afterEach(cleanup);

const settled = {
  canManage: true,
  isError: false,
  isLoadingError: false,
  isPending: false,
  isFetching: false,
};

function show() {
  render(
    <WorkspaceKnowledgeBases workspaceSlug="acme">
      {(ecosystemId) => <div>scoped:{ecosystemId}</div>}
    </WorkspaceKnowledgeBases>,
  );
}

describe("WorkspaceKnowledgeBases", () => {
  beforeEach(() => resolution.mockReset());

  // Unscoped, every workspace showed ecosystem zero's rows (Mike, 2026-09-25).
  it("hands the workspace's own ecosystem to the feature", () => {
    resolution.mockReturnValue({ ...settled, ecosystemId: "eco-acme" });
    show();
    expect(resolution).toHaveBeenCalledWith("acme");
    expect(screen.getByText("scoped:eco-acme")).toBeInTheDocument();
  });

  it("mounts nothing unscoped while the ecosystem is still being asked for", () => {
    resolution.mockReturnValue({ ...settled, isPending: true });
    show();
    expect(screen.getByText("Loading…")).toBeInTheDocument();
    expect(screen.queryByText(/^scoped:/)).toBeNull();
  });

  it("says so when the workspace has no ecosystem", () => {
    resolution.mockReturnValue({ ...settled });
    show();
    expect(screen.getByText("This workspace has no ecosystem yet.")).toBeInTheDocument();
    expect(screen.queryByText(/^scoped:/)).toBeNull();
  });

  it("a failed resolution is an error, not an empty workspace", () => {
    resolution.mockReturnValue({ ...settled, isError: true, isLoadingError: true });
    show();
    expect(screen.queryByText("This workspace has no ecosystem yet.")).toBeNull();
    expect(screen.queryByText(/^scoped:/)).toBeNull();
  });

  // A background re-read that fails behind a resolution already in hand is not a failed
  // resolution: the pane keeps working on the answer it has.
  it("keeps the pane when a re-read fails behind a resolved ecosystem", () => {
    resolution.mockReturnValue({ ...settled, ecosystemId: "eco-acme", isError: true });
    show();
    expect(screen.getByText("scoped:eco-acme")).toBeInTheDocument();
  });

  // The backend refuses an ecosystem scope the caller cannot manage.
  it("a member who cannot manage the ecosystem gets the notice, not a pane of 403s", () => {
    resolution.mockReturnValue({ ...settled, ecosystemId: "eco-acme", canManage: false });
    show();
    expect(screen.queryByText(/^scoped:/)).toBeNull();
  });
});
