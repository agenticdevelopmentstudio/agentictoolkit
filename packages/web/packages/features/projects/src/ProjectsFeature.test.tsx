// @vitest-environment jsdom
//
// Component test for ProjectsFeature — the Projects workspace feature built on the shared
// ResourceExplorer recipe. This package's vitest config is jsdom (see vitest.config.ts) and
// drives React with @testing-library/react. Only the data domain boundary
// (@agentic-toolkit/data/projects) plus the Next navigation/link hooks are mocked, so the
// rail → create → topic wiring is exercised, not the transport.
//
// ResourceExplorer PUBLISHES its resource + topic rail levels into a rail HOST (via
// StackLevels) rather than rendering them itself, so a tiny <Rail> harness backed by the
// toolkit's RailHostContext renders the published rows the same way the hub's workspace shell
// would. The filter field and the "New Project" button are NOT rendered by this harness's own
// generic level loop — they ride the resource level's `search`/`onNew`, i.e. that list's own
// TOOLBAR (the row under a rail's title; see `topic-detail.tsx`'s `data-htd-toolbar`), after the
// page-wide home bar they used to publish into was removed as clunky (Mike, 2026-09-24). The
// harness's <Rail> below renders each level's toolbar controls itself, scoped per level id, so
// a test can tell "wired to this level" from "wired to some other one". Selection is driven by
// props (the URL state the route shell would supply), since navigation is mocked.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup, within } from "@testing-library/react";
import { useMemo, useState, type ReactNode } from "react";
import {
  RailHostContext,
  type RailHostRegistry,
  type RegisteredLevels,
} from "@agentic-toolkit/resource";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";

// ResourceExplorer uses next/navigation's useRouter internally. `push` is a shared spy, not a
// throwaway: with the "All" card landing gone (docs/ui/fleet-ui-audit.md §1.5) the rail row IS
// the only way into a project, so the route it builds is what has to be asserted. `vi.hoisted`
// because the factory runs before the module body's consts initialize.
const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push, replace: vi.fn(), prefetch: vi.fn() }),
}));

// next/link pulls the App Router context in; a plain anchor is enough for these render/label
// assertions (selection is prop-driven, not click-driven).
vi.mock("next/link", () => ({
  default: ({ children, href }: { children: ReactNode; href: string }) => (
    <a href={href}>{children}</a>
  ),
}));

vi.mock("@agentic-toolkit/data/projects", () => ({
  projectsApi: {
    list: vi.fn(),
    get: vi.fn(),
    create: vi.fn(),
    // The Overview topic renders ProjectOverviewPane, which summarises five lists it does not
    // own — stub every one, or the pane's reads reject on an undefined client and the topic
    // renders its zero states for a reason that has nothing to do with this file.
    statuses: { list: vi.fn().mockResolvedValue([]) },
    participants: { list: vi.fn().mockResolvedValue([]) },
  },
  projectWorkItemsApi: { listForProject: vi.fn().mockResolvedValue([]) },
  projectArtifactsApi: { list: vi.fn().mockResolvedValue([]) },
  projectActivityApi: {
    projectActivity: vi.fn().mockResolvedValue({ rows: [], nextBefore: null }),
  },
  projectProgramsApi: { list: vi.fn().mockResolvedValue([]) },
  // Plain data, but `./vocabulary` imports them from this module — a whole-module mock that omits
  // them breaks the import chain, not just the value.
  DEFAULT_ITEM_NOUN: "work item",
  DEFAULT_ITEM_NOUN_PLURAL: "work items",
  // The board's live wake (useBoardLive). Stubbed to a no-op: it opens an EventSource, which jsdom
  // does not have, and what it does when it fires is `revalidateResources`' contract, tested in
  // @agentic-toolkit/data. Here it would only add a connection to every render.
  useProjectLive: vi.fn(),
}));

import { ProjectsFeature } from "./ProjectsFeature";
import { projectsApi, type Project } from "@agentic-toolkit/data/projects";

const list = vi.mocked(projectsApi.list);
const get = vi.mocked(projectsApi.get);
const create = vi.mocked(projectsApi.create);

const PROJECT: Project = {
  id: "p1",
  name: "Website relaunch",
  description: "Rework the marketing site.",
  status: "active",
  // A board-accent string; kept non-hex so the fixture doesn't trip the UI color gate.
  color: "blue",
  keyPrefix: "WEB",
  ecosystemId: "eco1",
  archivedAt: null,
  // The three board settings, each at its default. Always present on a Project — `toProject`
  // fills them in — so a fixture without them is a shape the client never hands out.
  estimateScale: "none",
  priorityScale: "standard",
  itemNoun: "work item",
  itemNounPlural: "work items",
  createdAt: "2026-07-03T00:00:00Z",
  updatedAt: "2026-07-03T00:00:00Z",
};

beforeEach(() => {
  vi.clearAllMocks();
  list.mockResolvedValue([structuredClone(PROJECT)]);
  get.mockResolvedValue(structuredClone(PROJECT));
  create.mockResolvedValue(structuredClone(PROJECT));
});

// Explicit and redundant, deliberately: this package's vitest runs with `globals: true`
// (packages/web/packages/features/vitest.preset.ts:16), so RTL 16.3.2's own shipped
// `afterEach(cleanup)` DOES register (@testing-library/react/dist/index.js:23-30), and cleanup
// is idempotent. An earlier version of this comment asserted the opposite — no global afterEach,
// auto-cleanup never registers — and both halves were false. Keep the call if you like it as a
// local statement of intent; do not "fix" the config to match the claim that was here.
afterEach(cleanup);

/** Renders the published rail — its rows, its empty label, and each level's own toolbar (the
 *  `+` and the pop-over search) — the way the workspace shell would. The rows matter since the
 *  "All" card landing was removed: the rail is now the only surface listing the projects. Each
 *  level's toolbar controls render inside a `data-testid={\`toolbar-${l.id}\`}` wrapper so a test
 *  can scope into ONE level's controls rather than trusting that nothing else on the page could
 *  satisfy an unscoped query — mirrors the real rail's `data-htd-toolbar` (`topic-detail.tsx`),
 *  standing in for it since this harness draws its own minimal rail rather than the real one. */
function Rail({ levels }: { levels: TopicLevel[] }) {
  return (
    <div>
      {levels.map((l) => (
        <div key={l.id}>
          {l.items.length === 0 ? <p>{l.emptyLabel}</p> : null}
          {l.items.map((item) => (
            <button key={item.id} type="button" onClick={() => l.onSelect(item.id)}>
              {item.label}
            </button>
          ))}
          <div data-testid={`toolbar-${l.id}`}>
            {l.onNew ? (
              <button type="button" onClick={() => l.onNew?.()}>
                {l.newLabel}
              </button>
            ) : null}
            {l.search ? (
              <input
                type="search"
                aria-label={l.search.placeholder}
                value={l.search.query}
                onChange={(e) => l.search?.onQueryChange?.(e.target.value)}
              />
            ) : null}
          </div>
        </div>
      ))}
    </div>
  );
}

/** A minimal rail HOST: it registers ResourceExplorer's published levels and exposes the merged
 *  stack the way the hub's workspace shell would (the shell owns `mergedLevels`; this package owns
 *  only the RailHostContext contract). Stands in for the host so the rail rows are drivable.
 *
 *  No `HomeBarHost` here any more: ResourceExplorer's filter field and its "New Project" button
 *  ride the resource level's own `search`/`onNew` now, so the harness's `<Rail>` above is the
 *  whole story — there is no separate page-wide strip left to stand a host in for. */
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

describe("ProjectsFeature", () => {
  it("lists projects from projectsApi.list into the published rail", async () => {
    render(
      <Harness>
        <ProjectsFeature basePath="/w1/projects" all />
      </Harness>,
    );

    expect(await screen.findByText("Website relaunch")).not.toBeNull();
    expect(list).toHaveBeenCalled();
  });

  // No other test in this file queries the filter field, and the two "creates a project…" tests
  // below query the "New Project" button with an unscoped `screen.*`, which would pass whether
  // the control is wired to the resource level or floating disconnected somewhere else on the
  // page. This test is the one that can tell: it scopes into the resource level's OWN toolbar.
  it("publishes the filter field and the New Project button onto the resource level's toolbar", async () => {
    render(
      <Harness>
        <ProjectsFeature basePath="/w1/projects" all />
      </Harness>,
    );

    expect(await screen.findByText("Website relaunch")).not.toBeNull();
    const toolbar = within(await screen.findByTestId("toolbar-resource"));
    expect(toolbar.getByRole("searchbox")).toBeTruthy();
    expect(toolbar.getByRole("button", { name: "New Project" })).toBeTruthy();
  });

  it("creates a project through the New Project dialog", async () => {
    render(
      <Harness>
        <ProjectsFeature basePath="/w1/projects" all />
      </Harness>,
    );

    // Open the create dialog from the published rail affordance.
    fireEvent.click(await screen.findByRole("button", { name: "New Project" }));

    // Fill the name and save.
    const dialog = await screen.findByRole("dialog", { name: "New project" });
    fireEvent.change(screen.getByLabelText("Name"), {
      target: { value: "Mobile app" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Save" }));

    await waitFor(() =>
      expect(create).toHaveBeenCalledWith(
        { name: "Mobile app", description: undefined },
        // No workspaceSlug prop in this harness → creator-owned (workspace undefined).
        { workspace: undefined },
      ),
    );
  });

  it("renders the Overview topic for the selected project", async () => {
    render(
      <Harness>
        <ProjectsFeature basePath="/w1/projects" activeProjectId="p1" activeTopic="overview" />
      </Harness>,
    );

    // Overview fetches the single project and leads with what it IS — its description and its
    // lifecycle status, read-only. (The editable name/status fields are still there, but behind
    // a closed "Project settings" disclosure; ProjectOverviewPane.test.tsx owns that form.)
    expect(await screen.findByText("Rework the marketing site.")).not.toBeNull();
    expect(screen.getByText("active")).not.toBeNull();
    await waitFor(() => expect(get).toHaveBeenCalledWith("p1"));
  });

  it("scopes the list to the workspace prop, which is now the shell's to supply", async () => {
    render(
      <Harness>
        <ProjectsFeature basePath="/home/mine" workspaceSlug="mine" all />
      </Harness>,
    );

    // The site's shape after the refactor: basePath already carries the workspace, and the
    // slug arrives as a prop — no leading Workspaces level, no waiting on a list the feature
    // fetches itself. Previously this call was gated behind `scopePending`.
    expect(await screen.findByText("Website relaunch")).not.toBeNull();
    await waitFor(() => expect(list).toHaveBeenCalledWith({ workspace: "mine" }));
  });

  it("links a project at /home/<ws>/<id>, not just /home/<id>", async () => {
    render(
      <Harness>
        <ProjectsFeature basePath="/home/mine" workspaceSlug="mine" all />
      </Harness>,
    );

    // The rail row's route is built from `basePath` (ResourceExplorer's level `onSelect`), so
    // this pins that `basePath` is the FULL base — workspace included — rather than a bare
    // `/home` a caller might pass by mistake. A wrong base here means a project click resolves
    // to the wrong workspace segment and SiteHomeShell bounces the user back to their default
    // workspace.
    fireEvent.click(await screen.findByRole("button", { name: "Website relaunch" }));
    expect(push).toHaveBeenCalledWith("/home/mine/p1", { scroll: false });
  });

  it("creates a project scoped to the given workspace, not the creator", async () => {
    render(
      <Harness>
        <ProjectsFeature basePath="/home/acme" workspaceSlug="acme" all />
      </Harness>,
    );

    fireEvent.click(await screen.findByRole("button", { name: "New Project" }));
    const dialog = await screen.findByRole("dialog", { name: "New project" });
    fireEvent.change(screen.getByLabelText("Name"), {
      target: { value: "Mobile app" },
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Save" }));

    // Distinct from the no-slug case above: an org workspace's create must carry
    // that org's slug, or the project is created creator-owned and invisible to
    // the rest of the org.
    await waitFor(() =>
      expect(create).toHaveBeenCalledWith(
        { name: "Mobile app", description: undefined },
        { workspace: "acme" },
      ),
    );
  });
});
