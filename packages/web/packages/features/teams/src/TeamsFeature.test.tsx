// @vitest-environment jsdom
//
// Component tests for TeamsFeature's HOST-SCOPING states — the seam this branch's reviews
// worked hardest on. Only the data subpaths (teams, ecosystems) and next/navigation are
// mocked; the list/rail wiring (useResourceList + ResourceExplorer + the rail-host
// publish path) runs for real inside the same minimal host harness the sibling features'
// tests use. ResourceExplorer's "New Team…" button rides the published resource level's own
// `onNew`/`search` — that list's own TOOLBAR — after the page-wide home bar it used to publish
// into was removed as clunky (Mike, 2026-09-24); the harness's `<Rail>` below renders each
// level's toolbar controls itself, scoped per level id.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor, within } from "@testing-library/react";
import { useMemo, useState, type ReactNode } from "react";
import {
  RailHostContext,
  type RailHostRegistry,
  type RegisteredLevels,
} from "@agentic-toolkit/resource";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
}));

vi.mock("@agentic-toolkit/data/teams", () => ({
  teamsApi: {
    list: vi.fn(),
    create: vi.fn(),
    delete: vi.fn(),
  },
  teamMembersApi: {
    counts: vi.fn(),
  },
}));

vi.mock("@agentic-toolkit/data/ecosystems", () => ({
  ecosystemsApi: {
    ecosystemIdForSlug: vi.fn(),
  },
}));

import { TeamsFeature } from "./TeamsFeature";
import { teamsApi, teamMembersApi, type Team } from "@agentic-toolkit/data/teams";
import { ecosystemsApi } from "@agentic-toolkit/data/ecosystems";

const listMock = vi.mocked(teamsApi.list);
const countsMock = vi.mocked(teamMembersApi.counts);
const idForSlugMock = vi.mocked(ecosystemsApi.ecosystemIdForSlug);

const TEAM: Team = {
  id: "t1",
  identifier: "team.acme.core",
  displayName: "Core Team",
  createdAt: "2026-07-01T00:00:00Z",
  updatedAt: "2026-07-01T00:00:00Z",
} as Team;

beforeEach(() => {
  vi.clearAllMocks();
  listMock.mockResolvedValue([structuredClone(TEAM)]);
  countsMock.mockResolvedValue(new Map());
  idForSlugMock.mockResolvedValue("eco1");
});

afterEach(cleanup);

function Rail({ levels }: { levels: TopicLevel[] }) {
  return (
    <div>
      {levels.map((l) => (
        <div key={l.id}>
          {/* The rail carries the empty label. It used to be read off the "All teams" card
              landing too; that landing is gone (docs/ui/fleet-ui-audit.md §1.5), so the rail
              is the only surface that states WHY a host has no teams. */}
          {l.items.length === 0 ? <p>{l.emptyLabel}</p> : null}
          {l.items.map((item) => (
            <button key={item.id} type="button" onClick={() => l.onSelect(item.id)}>
              {item.label}
            </button>
          ))}
          {/* Toolbar stand-in, scoped per level id (mirrors the real rail's `data-htd-toolbar`)
              so a test can tell "wired to THIS level" from "wired to some other one". */}
          <div data-testid={`toolbar-${l.id}`}>
            {l.onNew && (
              <button type="button" onClick={() => l.onNew?.()}>
                {l.newLabel}
              </button>
            )}
            {l.search && (
              <input
                type="search"
                aria-label={l.search.placeholder}
                value={l.search.query}
                onChange={(e) => l.search?.onQueryChange(e.target.value)}
              />
            )}
          </div>
        </div>
      ))}
    </div>
  );
}

function Harness({ children }: { children: ReactNode }) {
  const [entries, setEntries] = useState<Map<string, RegisteredLevels>>(new Map());
  const registry: RailHostRegistry = useMemo(
    () => ({
      registerLevels: (id, entry) =>
        setEntries((m) => {
          const next = new Map(m);
          next.set(id, entry);
          return next;
        }),
      unregisterLevels: (id) =>
        setEntries((m) => {
          const next = new Map(m);
          next.delete(id);
          return next;
        }),
      registerExitGuard: () => {},
      popStack: () => {},
      reportMissing: () => {},
      reportBusy: () => {},
      toolbarSlot: null,
    }),
    [],
  );
  const mergedLevels = [...entries.values()]
    .sort((a, b) => a.depth - b.depth)
    .flatMap((e) => e.levels);
  return (
    <RailHostContext.Provider value={registry}>
      <Rail levels={mergedLevels} />
      {children}
    </RailHostContext.Provider>
  );
}

describe("TeamsFeature host-scoping states", () => {
  it("unscoped host (no workspaceSlug): defined empty state, creation suppressed, no data fetches", async () => {
    render(
      <Harness>
        <TeamsFeature basePath="/home" all />
      </Harness>,
    );
    // A DEFINED explanation — not an eternal spinner.
    expect(
      await screen.findByText(/teams aren't available on this site yet/i),
    ).toBeTruthy();
    // The create affordance is suppressed (its create could never succeed here).
    expect(screen.queryByText(/new team/i)).toBeNull();
    // The scoping posture is consistent: neither the list nor the workspace lookup fires.
    expect(listMock).not.toHaveBeenCalled();
    expect(idForSlugMock).not.toHaveBeenCalled();
    // Nothing decorates a card grid any more, so nothing reads the cross-team member counts —
    // the landing that needed them is gone (docs/ui/fleet-ui-audit.md §1.5).
    expect(countsMock).not.toHaveBeenCalled();
  });

  it("scoped host: resolves the workspace ecosystem, lists its teams, offers creation", async () => {
    render(
      <Harness>
        <TeamsFeature basePath="/acme/teams" workspaceSlug="acme" all />
      </Harness>,
    );
    // Renders as a published rail row — the one surface that lists the teams.
    expect((await screen.findAllByText("Core Team")).length).toBeGreaterThan(0);
    expect(idForSlugMock).toHaveBeenCalledWith("acme");
    await waitFor(() => expect(listMock).toHaveBeenCalledWith("eco1"));
    expect(screen.getByText(/new team/i)).toBeTruthy();
  });

  // The assertion above queries "new team" with an unscoped `screen.*`, which would pass whether
  // the control is wired to the resource level or floating disconnected somewhere else on the
  // page. This test scopes into the resource level's own toolbar, so it fails if the create
  // button and filter field ever stop being wired to that level.
  it("publishes the filter field and the New Team button onto the resource level's toolbar", async () => {
    render(
      <Harness>
        <TeamsFeature basePath="/acme/teams" workspaceSlug="acme" all />
      </Harness>,
    );
    expect((await screen.findAllByText("Core Team")).length).toBeGreaterThan(0);
    const toolbar = within(await screen.findByTestId("toolbar-resource"));
    expect(toolbar.getByRole("searchbox")).toBeTruthy();
    expect(toolbar.getByRole("button", { name: "New Team" })).toBeTruthy();
  });

  it("scoped host whose slug resolves to NO ecosystem: defined empty state, creation suppressed", async () => {
    idForSlugMock.mockResolvedValue(null);
    render(
      <Harness>
        <TeamsFeature basePath="/acme/teams" workspaceSlug="acme" all />
      </Harness>,
    );
    expect(
      await screen.findByText(/no ecosystem to hold teams yet/i),
    ).toBeTruthy();
    expect(screen.queryByText(/new team/i)).toBeNull();
    expect(listMock).not.toHaveBeenCalled();
  });

  it("scoped host whose lookup FAILS: defined retry message instead of an eternal spinner", async () => {
    idForSlugMock.mockRejectedValue(new Error("network"));
    render(
      <Harness>
        <TeamsFeature basePath="/acme/teams" workspaceSlug="acme" all />
      </Harness>,
    );
    expect(
      await screen.findByText(/couldn't load this workspace/i),
    ).toBeTruthy();
    expect(screen.queryByText(/new team/i)).toBeNull();
  });
});
