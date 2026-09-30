// @vitest-environment jsdom
//
// Component test for WorkItemsSurface — the 4e work-items view switcher. The surface
// loads the shared query ONCE (items + statuses + participants) and owns the two
// shared concerns: the WorkItemEditor (opened from any view via onOpenItem / the New
// action) and the optimistic-with-revert status move (BoardView calls onMove). The
// hub's vitest config is node-only, so this file opts into jsdom via the docblock.
// The api-client boundaries are mocked, so the load-once + switch + editor + move
// wiring is exercised, not the transport. A stateful `leaf` harness makes the
// switcher deep-link the active view the way ResourceExplorer's URL leaf would.
import { describe, it, expect, vi, beforeEach, afterEach, onTestFinished } from "vitest";
import { useState } from "react";
import { render, screen, fireEvent, waitFor, cleanup, within, act } from "@testing-library/react";

// The three former hub modules (@/api/{projects,project-work-items,project-activity}) now ship in
// ONE domain barrel (@agentic-toolkit/data/projects), so their stubs merge into a single mock: the
// work-items + projects clients the surface reads, plus the two clients the edit-mode editor's
// lower sections load on mount — comments and the activity trail (empty replies keep them quiet
// without touching the network). The mock is PARTIAL (importOriginal-spread) because those panes
// also use pure folds from the same barrel — `threadOf` — which have nothing to stub.
vi.mock("@agentic-toolkit/data/projects", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/data/projects")>()),
  projectWorkItemsApi: {
    listForProject: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    get: vi.fn(),
  },
  projectsApi: {
    statuses: { list: vi.fn() },
    participants: { list: vi.fn() },
    labels: vi.fn(),
    // The surface reads the project's OWN record for one field — its estimate scale.
    get: vi.fn(),
    savedViews: { list: vi.fn(), create: vi.fn(), update: vi.fn(), remove: vi.fn() },
  },
  // The pickers' template options (participants/iterations/milestones' sibling axis). Stubbed for
  // the same reason those are: unstubbed it reaches the network from every mount here.
  projectTemplatesApi: { list: vi.fn() },
  // The workspace's time-boxes, which the editor's iteration picker offers.
  projectIterationsApi: { list: vi.fn() },
  // The BOARD's plan, which the milestone picker, column and filter axis offer. Stubbed for the
  // same reason the iterations are: unstubbed it reaches the network from every mount here.
  projectMilestonesApi: { list: vi.fn() },
  projectActivityApi: {
    workItemActivity: vi.fn().mockResolvedValue({ rows: [], nextBefore: null }),
  },
  projectCommentsApi: {
    list: vi.fn().mockResolvedValue([]),
    add: vi.fn(),
    edit: vi.fn(),
    remove: vi.fn(),
  },
}));

// The comments pane batches its thread's reactions on the same mount.
vi.mock("@agentic-toolkit/data/reactions", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/data/reactions")>()),
  reactionsApi: { list: vi.fn().mockResolvedValue([]), add: vi.fn(), remove: vi.fn() },
}));

import { WorkItemsSurface } from "./WorkItemsSurface";
import { resetViewMemory } from "./view-memory";
import { projectWorkItemsApi, type WorkItem } from "@agentic-toolkit/data/projects";
import {
  projectIterationsApi,
  projectMilestonesApi,
  projectTemplatesApi,
  projectsApi,
  type Iteration,
  type Milestone,
  type Project,
  type ProjectStatus,
  type ProjectParticipant,
  type SavedView,
} from "@agentic-toolkit/data/projects";
import { RailHostBoundary, RecordAffordanceContext, type TopicLeaf } from "@agentic-toolkit/resource";

const listForProject = vi.mocked(projectWorkItemsApi.listForProject);
const create = vi.mocked(projectWorkItemsApi.create);
const update = vi.mocked(projectWorkItemsApi.update);
const get = vi.mocked(projectWorkItemsApi.get);
const statusesList = vi.mocked(projectsApi.statuses.list);
const participantsList = vi.mocked(projectsApi.participants.list);
const labelsList = vi.mocked(projectsApi.labels);
const projectGet = vi.mocked(projectsApi.get);
const iterationsList = vi.mocked(projectIterationsApi.list);
const milestonesList = vi.mocked(projectMilestonesApi.list);
const templatesList = vi.mocked(projectTemplatesApi.list);
const savedViewsList = vi.mocked(projectsApi.savedViews.list);
const savedViewsCreate = vi.mocked(projectsApi.savedViews.create);
const savedViewsUpdate = vi.mocked(projectsApi.savedViews.update);
const savedViewsRemove = vi.mocked(projectsApi.savedViews.remove);

function status(over: Partial<ProjectStatus>): ProjectStatus {
  return {
    id: "s",
    projectId: "p1",
    key: "k",
    label: "L",
    category: "todo",
    position: 0,
    createdAt: "2026-07-03T00:00:00Z",
    ...over,
  };
}

function item(over: Partial<WorkItem>): WorkItem {
  return {
    id: "w",
    projectId: "p1",
    itemKey: "",
    title: "T",
    description: "",
    statusId: "s1",
    assigneeKind: null,
    assigneeId: null,
    priority: 0,
    startDate: null,
    dueDate: null,
    labels: [],
    parentId: null,
    iterationId: null,
    milestoneId: null,
    estimate: null,
    rank: "V0",
    createdAt: "2026-07-03T00:00:00Z",
    updatedAt: "2026-07-03T00:00:00Z",
    ...over,
  };
}

const TODO_COL = status({ id: "s1", key: "todo", label: "To do", category: "todo", position: 0 });
const DOING = status({ id: "s2", key: "doing", label: "In progress", category: "in_progress", position: 1 });
const DONE = status({ id: "s3", key: "done", label: "Done", category: "done", position: 2 });

/** The project's own record. Only the board SETTINGS are read here — the rest is what a Project
 *  is. All three are at their defaults, which is also the shape `toProject` guarantees. */
const PROJECT: Project = {
  id: "p1",
  name: "Website",
  description: "",
  status: "active",
  color: "#007AFF",
  keyPrefix: "",
  ecosystemId: "eco-1",
  archivedAt: null,
  estimateScale: "none",
  priorityScale: "standard",
  itemNoun: "work item",
  itemNounPlural: "work items",
  createdAt: "2026-07-03T00:00:00Z",
  updatedAt: "2026-07-03T00:00:00Z",
};

/** A workspace cycle. `state` is DERIVED by the backend from the dates, so a fixture states it. */
const CYCLE: Iteration = {
  id: "it1",
  name: "Sprint 7",
  description: "",
  startDate: "2026-07-01",
  endDate: "2026-07-14",
  state: "active",
  ownerKind: "customer",
  ownerId: "cust-1",
  ecosystemId: "eco-1",
  createdAt: "2026-06-30T00:00:00Z",
  updatedAt: "2026-06-30T00:00:00Z",
};

/** One point in THIS board's plan. Scoped to the project, where CYCLE above is the workspace's —
 *  the difference the two load-scope tests below exist to hold. */
const MILESTONE: Milestone = {
  id: "ms1",
  projectId: "p1",
  name: "Beta",
  description: "",
  targetDate: "2026-08-15",
  counts: { backlog: 0, todo: 0, in_progress: 0, done: 0, canceled: 0 },
  ecosystemId: "eco-1",
  createdAt: "2026-06-30T00:00:00Z",
  updatedAt: "2026-06-30T00:00:00Z",
};

const PARTICIPANT: ProjectParticipant = {
  id: "pp1",
  projectId: "p1",
  participantKind: "customer",
  participantId: "cust-1",
  role: "member",
  addedBy: null,
  addedAt: "2026-07-03T00:00:00Z",
};

// w1 in To do (High, assigned to the participant), w2 in In progress.
const W1 = item({
  id: "w1",
  title: "Design the landing page",
  statusId: "s1",
  priority: 3,
  assigneeKind: "customer",
  assigneeId: "cust-1",
  dueDate: "2026-08-01",
});
const W2 = item({ id: "w2", title: "Write the copy", statusId: "s2", priority: 1 });

beforeEach(() => {
  vi.clearAllMocks();
  // The surface's narrowing lives at MODULE scope so it survives the remount a view switch
  // performs (see `useViewMemory`). Module scope also outlives `cleanup()`, so a filter one case
  // sets would still be narrowing the board in the next one.
  resetViewMemory();
  // The OPEN ITEM is the URL's `?item=` (see work-item-link.ts), and jsdom keeps one document per
  // test FILE — so a case that opened a card would leave the next one mounting straight into that
  // card's editor instead of the list. Same class of survivor as the view memory above.
  window.history.replaceState(null, "", "/");
  savedViewsList.mockResolvedValue([]);
  listForProject.mockResolvedValue([structuredClone(W1), structuredClone(W2)]);
  statusesList.mockResolvedValue([DONE, TODO_COL, DOING].map((s) => structuredClone(s))); // unsorted
  participantsList.mockResolvedValue([structuredClone(PARTICIPANT)]);
  labelsList.mockResolvedValue([]);
  projectGet.mockResolvedValue(structuredClone(PROJECT));
  iterationsList.mockResolvedValue([]);
  milestonesList.mockResolvedValue([]);
  templatesList.mockResolvedValue([]);
  create.mockImplementation((_projectId, input) =>
    Promise.resolve({ ...structuredClone(W1), ...input, id: "w3" } as WorkItem),
  );
  update.mockImplementation((id, patch) =>
    Promise.resolve({ ...structuredClone(W1), id, ...patch } as WorkItem),
  );
  // A failed move's catch reconciles against the server's authoritative row. Default: the
  // server never actually changed the item (no PATCH persisted), so `get` returns it unmoved —
  // the correct baseline for every failed-move test below unless a test overrides it.
  get.mockImplementation((id: string) =>
    Promise.resolve(
      id === W1.id ? structuredClone(W1) : id === W2.id ? structuredClone(W2) : null,
    ),
  );
});

// The hub vitest config has no global afterEach — tear down each render explicitly.
afterEach(cleanup);

/** The List view has loaded: its title cell is an INLINE EDITOR, so the title is an input value. */
const listLoaded = () => screen.findByDisplayValue("Design the landing page");

// The five views are a "Work Items" LEVEL published into the enclosing hierarchical stack, so the
// harness mounts a RailHostBoundary — which, with no host above it, becomes the same standalone host a
// feature site gives the feature — so the
// level renders as a real rail whose rows are the views. A stateful leaf deep-links the active view
// the way ResourceExplorer's URL leaf would; `onSelectSpy` records the chosen view id.
//
// `view` seeds that leaf. It defaults to "list" because most tests below are about the editor and
// the optimistic move and just need SOME view on screen — the stack itself never auto-selects one
// (the first test asserts exactly that).
function Harness({
  onSelectSpy,
  view = "list",
  workspaceSlug,
}: {
  onSelectSpy?: (leafId: string | null, opts?: { replace?: boolean }) => void;
  view?: string | null;
  /** The workspace whose ITERATIONS the surface offers; the hosts always supply one. */
  workspaceSlug?: string;
}) {
  const [leafId, setLeafId] = useState<string | null>(view);
  const leaf: TopicLeaf = {
    leafId,
    // The spy records the OPTIONS too: a real leaf routes, so whether the stack asked to replace
    // or to push is part of what this surface must forward, not an implementation detail.
    onSelect: (id, opts) => {
      onSelectSpy?.(id, opts);
      setLeafId(id);
    },
  };
  return (
    <RailHostBoundary>
      <WorkItemsSurface
        projectId="p1"
        title="Work Items"
        leaf={leaf}
        workspaceSlug={workspaceSlug}
      />
    </RailHostBoundary>
  );
}

describe("WorkItemsSurface", () => {
  it("publishes the five views as a topic list and lands on List", async () => {
    // The stack applies a level's default only once it KNOWS it is wide — a measured container
    // width. jsdom measures every element at 0, which reads as "not yet laid out", so the default
    // would never fire. State a desktop width for this test (as ServicesSection.test.tsx does).
    const realWidth = Object.getOwnPropertyDescriptor(HTMLElement.prototype, "clientWidth");
    Object.defineProperty(HTMLElement.prototype, "clientWidth", { configurable: true, get: () => 1400 });
    onTestFinished(() => {
      if (realWidth) Object.defineProperty(HTMLElement.prototype, "clientWidth", realWidth);
      else delete (HTMLElement.prototype as unknown as Record<string, unknown>).clientWidth;
    });
    const onSelectSpy = vi.fn();
    render(<Harness view={null} onSelectSpy={onSelectSpy} />);

    // The views are rows of a published rail — a LEVEL of the one stack — not a tab bar in the leaf.
    const rail = await screen.findByRole("complementary", { name: "Topic list" });
    for (const label of ["List", "Board", "Table", "Timeline", "Calendar"]) {
      expect(within(rail).getByRole("button", { name: label })).not.toBeNull();
    }

    // The level names List as its `defaultSelectedId`, so opening Work Items lands there instead of
    // on a pane asking which view you want. It arrives as a NORMAL selection — the leaf is routed
    // through `leaf.onSelect`, exactly as if the row had been clicked — except that it asks to
    // REPLACE: the bare topic it supersedes was never a state the user chose or saw, so leaving a
    // Back stop on it would make one click cost two Back presses.
    expect(onSelectSpy).toHaveBeenCalledWith("list", { replace: true });
    expect(await screen.findByRole("grid", { name: "Work items" })).not.toBeNull();
    expect(screen.queryByText(/select a view/i)).toBeNull();
    expect(within(rail).getByRole("button", { name: "List" })).toHaveAttribute(
      "aria-current",
      "true",
    );
  });

  it("switches to the Board view from the rail row, calling leaf.onSelect('board')", async () => {
    const onSelectSpy = vi.fn();
    render(<Harness onSelectSpy={onSelectSpy} />);
    await listLoaded();

    fireEvent.click(screen.getByRole("button", { name: "Board" }));

    // A CLICK carries no options — it is a state the user asked for, so it earns its own history
    // entry. Only the stack's own auto-applied default asks to replace.
    expect(onSelectSpy).toHaveBeenCalledWith("board", undefined);

    // The Board columns are now rendered (in position order), the List grid gone. Scoped to the
    // board: the rail's own rows are <li>s too, so an unscoped listitem query would sweep them in.
    const board = await screen.findByRole("list", { name: "Board columns" });
    const cols = within(board).getAllByRole("listitem");
    expect(cols.map((c) => c.getAttribute("aria-label"))).toEqual([
      "To do",
      "In progress",
      "Done",
    ]);
    expect(screen.queryByRole("grid", { name: "Work items" })).toBeNull();
  });

  // ── The filter ──────────────────────────────────────────────────────────────
  // The bar's own axes are unit-tested against the filter model (filters.test.ts). What only a
  // surface test can show is the WIRING: that the narrowing reaches every view, that it survives
  // a view switch, that the count says so, and — the one that would be silently wrong — that the
  // writes still address the whole board rather than the slice on screen.
  it("narrows every view from one filter, and says so in the count", async () => {
    render(<Harness />);
    await listLoaded();
    expect(screen.getByText("2 work items")).not.toBeNull();

    fireEvent.change(screen.getByRole("searchbox", { name: "Search work items" }), {
      target: { value: "copy" },
    });

    // The List no longer holds w1…
    await waitFor(() => expect(screen.queryByDisplayValue("Design the landing page")).toBeNull());
    expect(screen.getByDisplayValue("Write the copy")).not.toBeNull();
    // …and the count reports BOTH numbers, so a board of two is not mistaken for a board of ten.
    expect(screen.getByText("1 of 2 work items")).not.toBeNull();

    // The same subset on the Board — one filter, five views.
    fireEvent.click(screen.getByRole("button", { name: "Board" }));
    const board = await screen.findByRole("list", { name: "Board columns" });
    expect(within(board).getByText("Write the copy")).not.toBeNull();
    expect(within(board).queryByText("Design the landing page")).toBeNull();
  });

  it("keeps the filter across a view switch, and clears it on demand", async () => {
    render(<Harness />);
    await listLoaded();

    fireEvent.change(screen.getByRole("searchbox", { name: "Search work items" }), {
      target: { value: "copy" },
    });
    await waitFor(() => expect(screen.getByText("1 of 2 work items")).not.toBeNull());

    // Switching views remounts the pane's children; the filter lives above them, so it holds.
    fireEvent.click(screen.getByRole("button", { name: "Board" }));
    await screen.findByRole("list", { name: "Board columns" });
    expect(screen.getByText("1 of 2 work items")).not.toBeNull();
    expect((screen.getByRole("searchbox", { name: "Search work items" }) as HTMLInputElement).value).toBe(
      "copy",
    );

    fireEvent.click(screen.getByRole("button", { name: "Clear filters" }));
    await waitFor(() => expect(screen.getByText("2 work items")).not.toBeNull());
  });

  it("filters by status through the column's NAME while storing its id", async () => {
    render(<Harness />);
    await listLoaded();

    const axis = screen.getByRole("combobox", { name: "Filter by status" });
    // The option a user picks reads as the column; what the filter stores is the status id.
    expect((within(axis).getByRole("option", { name: "In progress" }) as HTMLOptionElement).value).toBe(
      "s2",
    );
    fireEvent.change(axis, { target: { value: "s2" } });

    await waitFor(() => expect(screen.queryByDisplayValue("Design the landing page")).toBeNull());
    expect(screen.getByDisplayValue("Write the copy")).not.toBeNull();
  });

  it("offers 'Unassigned' as an answer, not as the absence of one", async () => {
    render(<Harness />);
    await listLoaded();

    // Scoped to the typeahead's own listbox: the List view's inline assignee column has an
    // "Unassigned" option too, and it is a different control answering a different question.
    fireEvent.click(screen.getByRole("button", { name: "Filter by assignee" }));
    const options = () => within(screen.getByRole("listbox", { name: "Filter by assignee" }));
    fireEvent.click(await options().findByRole("option", { name: "Unassigned" }));

    // w1 has an assignee, w2 does not — "Unassigned" keeps w2 alone, where "Anyone" keeps both.
    await waitFor(() => expect(screen.getByText("1 of 2 work items")).not.toBeNull());
    expect(screen.getByDisplayValue("Write the copy")).not.toBeNull();
    expect(screen.queryByDisplayValue("Design the landing page")).toBeNull();

    // "Anyone" is an entry in the same list — a typeahead with no way back to "all" is a trap.
    fireEvent.click(screen.getByRole("button", { name: "Filter by assignee" }));
    fireEvent.click(await options().findByRole("option", { name: "Anyone" }));
    await waitFor(() => expect(screen.getByText("2 work items")).not.toBeNull());
  });

  it("still edits a card that the filter is hiding the rest of the board from", async () => {
    // The trap this guards: if the surface handed the FILTERED list to its writers and its
    // editor, a narrowed board would lose its parent/relation candidates and a move would look
    // up a card that is no longer in the list it searches. The views see the subset; the writes
    // see the board.
    render(<Harness view="table" />);
    await screen.findByText("Design the landing page");

    fireEvent.change(screen.getByRole("searchbox", { name: "Search work items" }), {
      target: { value: "landing" },
    });
    await waitFor(() => expect(screen.getByText("1 of 2 work items")).not.toBeNull());
    expect(screen.queryByText("Write the copy")).toBeNull();

    // Table opens the editor on a double-click (a single click selects).
    fireEvent.doubleClick(screen.getByText("Design the landing page"));
    await screen.findByRole("button", { name: "Save changes" });

    // The editor opened on the still-visible card, and its parent picker still offers the card
    // the filter is hiding — the board's candidates are the board's, not the view's. The option
    // is unambiguous precisely because the filter removed that card from everywhere else.
    const parentOption = await screen.findByRole("option", { name: /Write the copy/ });
    expect((parentOption as HTMLOptionElement).value).toBe("w2");
  });

  it("loads the shared query only ONCE across a view switch", async () => {
    render(<Harness />);
    await listLoaded();

    fireEvent.click(screen.getByRole("button", { name: "Board" }));
    await screen.findByRole("listitem", { name: "To do" });

    // The items are owned by the surface and keyed on projectId, so switching the VIEW does not
    // re-fetch: exactly one listForProject across the switch.
    expect(listForProject).toHaveBeenCalledTimes(1);
    expect(listForProject).toHaveBeenCalledWith("p1");
  });

  it("spins the list header while the cards are being read, and stops when they land", async () => {
    // Held open, so the in-flight moment is a state to stand in rather than a frame to catch.
    let land = (_rows: WorkItem[]) => {};
    listForProject.mockReturnValue(
      new Promise<WorkItem[]>((resolve) => {
        land = resolve;
      }),
    );
    render(<Harness />);

    // The real rail is mounted, so this is the spinner the user sees. What it reports is NOT this
    // level's rows — the five views are static and always on screen — but the BODY behind the row
    // that is selected, which is the same cards for every one of them. That is why one flag
    // covers five rows rather than needing five.
    const rail = await screen.findByRole("complementary", { name: "Topic list" });
    // The read is announced by ONE always-mounted live region whose TEXT changes, so the
    // assertion is on what that region CONTAINS: a region inserted at the same instant it fills
    // announces nothing, since assistive tech reads a live region's mutations and not its arrival.
    // `role="status"` also takes its name from the author and never from its content, so there is
    // no accessible name to match on either.
    expect(within(rail).getByRole("status").textContent).toBe("Loading");
    for (const label of ["List", "Board", "Table", "Timeline", "Calendar"]) {
      expect(within(rail).getByRole("button", { name: label })).not.toBeNull();
    }

    land([structuredClone(W1), structuredClone(W2)]);
    await listLoaded();
    expect(within(rail).getByRole("status").textContent).toBe("");
  });

  // The three PLANNING values the surface loads for its views: the WORKSPACE's cycles (one list
  // answers every board its owner runs), the BOARD's milestones (a plan belongs to one board), and
  // the PROJECT's estimate scale (what a size means here). The first two are loaded at DIFFERENT
  // scopes on purpose, which is the thing worth pinning — wiring either to the other's scope
  // offers a reader points, or cycles, from somewhere else.
  it("asks for the WORKSPACE's iterations, not the project's", async () => {
    render(<Harness workspaceSlug="acme" />);
    await listLoaded();

    await waitFor(() => expect(iterationsList).toHaveBeenCalledWith({ workspace: "acme" }));
  });

  it("asks for the PROJECT's milestones, not the workspace's", async () => {
    render(<Harness workspaceSlug="acme" />);
    await listLoaded();

    await waitFor(() => expect(milestonesList).toHaveBeenCalledWith("p1"));
  });

  it("offers the board's plan in the editor's milestone picker", async () => {
    milestonesList.mockResolvedValue([structuredClone(MILESTONE)]);

    render(<Harness view="table" workspaceSlug="acme" />);
    fireEvent.doubleClick(await screen.findByText("Design the landing page"));
    await screen.findByRole("button", { name: "Save changes" });

    const milestone = (await screen.findByLabelText("Milestone")) as HTMLSelectElement;
    expect(within(milestone).getByRole("option", { name: /Beta/ })).not.toBeNull();
    // The card counts toward nothing, so the picker sits on "No milestone" rather than aiming it.
    expect(milestone.value).toBe("");
  });

  it("has no milestone field on a board with no plan", async () => {
    render(<Harness view="table" workspaceSlug="acme" />);
    fireEvent.doubleClick(await screen.findByText("Design the landing page"));
    await screen.findByRole("button", { name: "Save changes" });

    expect(screen.queryByLabelText("Milestone")).toBeNull();
  });

  it("offers the workspace's cycles and the project's scale in the editor", async () => {
    iterationsList.mockResolvedValue([structuredClone(CYCLE)]);
    projectGet.mockResolvedValue({ ...structuredClone(PROJECT), estimateScale: "fibonacci" });

    render(<Harness view="table" workspaceSlug="acme" />);
    // Table opens the editor on a double-click (a single click selects).
    fireEvent.doubleClick(await screen.findByText("Design the landing page"));
    await screen.findByRole("button", { name: "Save changes" });

    const iteration = (await screen.findByLabelText("Iteration")) as HTMLSelectElement;
    expect(within(iteration).getByRole("option", { name: /Sprint 7/ })).not.toBeNull();
    // The card is uncommitted, so the picker sits on the backlog rather than inventing a cycle.
    expect(iteration.value).toBe("");

    // The scale came from the project's own record — a `none` project has no such field at all.
    expect(await screen.findByLabelText("Estimate")).not.toBeNull();
  });

  it("has no estimate field on a project that does not estimate", async () => {
    render(<Harness view="table" workspaceSlug="acme" />);
    fireEvent.doubleClick(await screen.findByText("Design the landing page"));
    await screen.findByRole("button", { name: "Save changes" });

    expect(screen.queryByLabelText("Estimate")).toBeNull();
  });

  it("creates via a MODAL from the list header's +, then opens the new item's detail", async () => {
    render(<Harness />);
    await listLoaded();

    // The `+` on the Work Items list header opens a modal — the stack's create metaphor. The leaf is
    // NOT swapped for a blank editor: a detail always shows a real, selected record.
    fireEvent.click(screen.getByRole("button", { name: /new work item/i }));
    const modal = await screen.findByRole("dialog", { name: "New work item" });

    // The List view is still behind the modal (the leaf was never replaced).
    expect(screen.getByRole("grid", { name: "Work items" })).not.toBeNull();

    // The modal asks only for what PLACES the record; the rest belongs to its detail.
    fireEvent.change(within(modal).getByLabelText("Title"), {
      target: { value: "Ship the beta" },
    });
    // The save reloads the list from the server, which now HAS the row (the create persisted it) —
    // that reload is what puts the new item in the views.
    listForProject.mockResolvedValue([
      structuredClone(W1),
      structuredClone(W2),
      item({ id: "w3", title: "Ship the beta", statusId: "s1" }),
    ]);
    fireEvent.click(within(modal).getByRole("button", { name: /^(Create|Save)$/ }));

    await waitFor(() =>
      expect(create).toHaveBeenCalledWith(
        "p1",
        expect.objectContaining({ title: "Ship the beta" }),
      ),
    );

    // The created record now HAS a detail, so it opens — the rest of the fields live there.
    expect(await screen.findByRole("button", { name: "Save changes" })).not.toBeNull();
  });

  it("clears the assignee IN PLACE from the List row, committing update(null, null)", async () => {
    // The List view is a list-with-details and edits rows in place — it no longer hands off to the
    // editor. Emptying the assignee must still send an EXPLICIT null pair (a clear), not omit it.
    render(<Harness />);
    await listLoaded();

    fireEvent.change(
      screen.getByRole("combobox", { name: "Assignee — Design the landing page" }),
      { target: { value: "" } },
    );
    // The row went dirty, so its commit pair appeared; ✓ writes the patch.
    fireEvent.click(
      screen.getByRole("button", { name: "Save changes work item Design the landing page" }),
    );

    await waitFor(() =>
      expect(update).toHaveBeenCalledWith(
        "w1",
        expect.objectContaining({ assigneeKind: null, assigneeId: null }),
      ),
    );
  });

  it("moves a card to another status (optimistic) and repaints it under the new column", async () => {
    render(<Harness view="board" />);
    await screen.findByRole("listitem", { name: "To do" });

    fireEvent.change(screen.getByRole("combobox", { name: "Move Design the landing page" }), {
      target: { value: "s2" },
    });

    await waitFor(() => expect(update).toHaveBeenCalledWith("w1", { statusId: "s2" }));

    // The shared items updated, so the card now sits under In progress…
    within(screen.getByRole("listitem", { name: "In progress" })).getByText(
      "Design the landing page",
    );
    // …and no longer under To do.
    expect(
      within(screen.getByRole("listitem", { name: "To do" })).queryByText(
        "Design the landing page",
      ),
    ).toBeNull();
  });

  it("reverts the card and shows an error when the move fails", async () => {
    update.mockRejectedValueOnce(new Error("boom"));
    render(<Harness view="board" />);
    await screen.findByRole("listitem", { name: "To do" });

    fireEvent.change(screen.getByRole("combobox", { name: "Move Design the landing page" }), {
      target: { value: "s2" },
    });

    await waitFor(() => expect(update).toHaveBeenCalledWith("w1", { statusId: "s2" }));

    // Reverted to the source column…
    await waitFor(() =>
      within(screen.getByRole("listitem", { name: "To do" })).getByText(
        "Design the landing page",
      ),
    );
    // …no longer under In progress…
    expect(
      within(screen.getByRole("listitem", { name: "In progress" })).queryByText(
        "Design the landing page",
      ),
    ).toBeNull();
    // …and the failure surfaces inline.
    await screen.findByText("boom");
  });

  it("a stale FAILED move never clobbers a newer move on the same card", async () => {
    // update #1 (the first move) will REJECT; update #2 (the newer move) will RESOLVE.
    let rejectMove1!: (e: Error) => void;
    let resolveMove2!: () => void;
    let calls = 0;
    update.mockImplementation((id, patch) => {
      calls += 1;
      if (calls === 1) {
        return new Promise<WorkItem>((_res, rej) => {
          rejectMove1 = rej;
        });
      }
      return new Promise<WorkItem>((res) => {
        resolveMove2 = () => res({ ...structuredClone(W1), id, ...patch } as WorkItem);
      });
    });

    render(<Harness view="board" />);
    await screen.findByRole("listitem", { name: "To do" });

    const combo = () => screen.getByRole("combobox", { name: "Move Design the landing page" });

    // Move 1: To do → In progress (update #1 in flight).
    fireEvent.change(combo(), { target: { value: "s2" } });
    await waitFor(() =>
      within(screen.getByRole("listitem", { name: "In progress" })).getByText(
        "Design the landing page",
      ),
    );

    // Move 2: In progress → Done (update #2 in flight), BEFORE move 1 has settled.
    fireEvent.change(combo(), { target: { value: "s3" } });
    await waitFor(() =>
      within(screen.getByRole("listitem", { name: "Done" })).getByText(
        "Design the landing page",
      ),
    );

    // The STALE move 1 now fails. Its guarded revert must be a NO-OP — the card sits at
    // the newer target (Done), not move 1's target (In progress), so it is not reverted.
    await act(async () => {
      rejectMove1(new Error("stale boom"));
    });
    within(screen.getByRole("listitem", { name: "Done" })).getByText("Design the landing page");
    expect(
      within(screen.getByRole("listitem", { name: "To do" })).queryByText(
        "Design the landing page",
      ),
    ).toBeNull();

    // Move 2 then resolves and reconciles cleanly — the card stays under Done.
    await act(async () => {
      resolveMove2();
    });
    within(screen.getByRole("listitem", { name: "Done" })).getByText("Design the landing page");
  });

  it("a both-failed overlapping move reconciles to the server's true status, not the stale intermediate", async () => {
    // update #1 (move A→B) and update #2 (move B→C) BOTH reject.
    let rejectMove1!: (e: Error) => void;
    let rejectMove2!: (e: Error) => void;
    let calls = 0;
    update.mockImplementation(() => {
      calls += 1;
      if (calls === 1) {
        return new Promise<WorkItem>((_res, rej) => {
          rejectMove1 = rej;
        });
      }
      return new Promise<WorkItem>((_res, rej) => {
        rejectMove2 = rej;
      });
    });
    // The server's authoritative row for the card never actually moved (both PATCHes
    // failed) — get() keeps returning the original To-do row throughout.
    get.mockResolvedValue(structuredClone(W1));

    render(<Harness view="board" />);
    await screen.findByRole("listitem", { name: "To do" });

    const combo = () => screen.getByRole("combobox", { name: "Move Design the landing page" });

    // Move 1: To do → In progress (update #1 in flight).
    fireEvent.change(combo(), { target: { value: "s2" } });
    await waitFor(() =>
      within(screen.getByRole("listitem", { name: "In progress" })).getByText(
        "Design the landing page",
      ),
    );

    // Move 2: In progress → Done (update #2 in flight), BEFORE move 1 has settled.
    fireEvent.change(combo(), { target: { value: "s3" } });
    await waitFor(() =>
      within(screen.getByRole("listitem", { name: "Done" })).getByText(
        "Design the landing page",
      ),
    );

    // The STALE move 1 fails first. Its guarded reconcile is a no-op — the card no longer
    // sits at move 1's target ("In progress") — so it stays at Done for now.
    await act(async () => {
      rejectMove1(new Error("move1 failed"));
    });
    within(screen.getByRole("listitem", { name: "Done" })).getByText("Design the landing page");

    // Move 2 (the newer move) ALSO fails. Both PATCHes are now settled and BOTH failed, so
    // the card must land on the SERVER's true status (To do) — NOT move 1's stale
    // intermediate optimistic value ("In progress"), which the server never persisted.
    await act(async () => {
      rejectMove2(new Error("move2 failed"));
    });
    await waitFor(() =>
      within(screen.getByRole("listitem", { name: "To do" })).getByText(
        "Design the landing page",
      ),
    );
    expect(
      within(screen.getByRole("listitem", { name: "In progress" })).queryByText(
        "Design the landing page",
      ),
    ).toBeNull();
    expect(
      within(screen.getByRole("listitem", { name: "Done" })).queryByText(
        "Design the landing page",
      ),
    ).toBeNull();
  });

  /* ── Saved views ──────────────────────────────────────────────────────────
   * The bar is the surface's, not a view's: what it saves is the whole configuration — the
   * narrowing, the Table's column sort, and WHICH view — so every case below goes through the
   * real hook and the real chooser rather than a stubbed controller. */
  describe("saved views", () => {
    /** A stored view as the API answers it: `config` is opaque jsonb, so it comes back as the
     *  sparse object `encodeViewConfig` wrote — not a full `WorkItemViewConfig`. */
    function savedView(over: Partial<SavedView> & { config: unknown }): SavedView {
      return {
        id: "v1",
        projectId: "p1",
        name: "My view",
        createdBy: "cust-1",
        createdAt: "2026-08-01T00:00:00.000Z",
        updatedAt: "2026-08-01T00:00:00.000Z",
        ...over,
      };
    }

    /** The bar, scoped: the List view below it has a "Delete" of its own, aimed at work items. */
    const bar = () => within(screen.getByRole("group", { name: "Saved views" }));

    /** Open the chooser and type into its one field. */
    async function openChooser(text?: string): Promise<HTMLInputElement> {
      fireEvent.click(screen.getByRole("button", { name: "Saved view" }));
      const input = (await screen.findByRole("combobox", {
        name: "Find a view, or name this one",
      })) as HTMLInputElement;
      if (text !== undefined) fireEvent.change(input, { target: { value: text } });
      return input;
    }

    it("saves what the board is showing under a name typed into the chooser", async () => {
      savedViewsCreate.mockResolvedValue(
        savedView({ name: "Copy work", config: { view: "list", filter: { text: "copy" } } }),
      );
      render(<Harness />);
      await listLoaded();

      fireEvent.change(screen.getByRole("searchbox", { name: "Search work items" }), {
        target: { value: "copy" },
      });
      await waitFor(() => expect(screen.getByText("1 of 2 work items")).not.toBeNull());

      await openChooser("Copy work");
      fireEvent.click(await screen.findByRole("option", { name: /Save this view as/ }));

      // The stored config is the SPARSE encoding: the view, and only the axes actually set.
      await waitFor(() =>
        expect(savedViewsCreate).toHaveBeenCalledWith("p1", {
          name: "Copy work",
          config: { view: "list", filter: { text: "copy" } },
        }),
      );
      // Saving names what is already on screen — it must not re-narrow or repaint anything.
      expect(screen.getByText("1 of 2 work items")).not.toBeNull();
    });

    it("applies a view's narrowing AND opens the view it was saved on", async () => {
      savedViewsList.mockResolvedValue([
        savedView({ name: "Copy on the board", config: { view: "board", filter: { text: "copy" } } }),
      ]);
      const onSelectSpy = vi.fn();
      render(<Harness onSelectSpy={onSelectSpy} />);
      await listLoaded();

      await openChooser();
      fireEvent.click(await screen.findByRole("option", { name: "Copy on the board" }));

      // Which of the five views to open in is part of what a saved view saves, so applying one
      // routes — the same call the rail's own row makes, so history and the URL agree.
      await waitFor(() => expect(onSelectSpy).toHaveBeenCalledWith("board", undefined));
      await screen.findByRole("list", { name: "Board columns" });
      expect(screen.getByText("1 of 2 work items")).not.toBeNull();
      expect(
        (screen.getByRole("searchbox", { name: "Search work items" }) as HTMLInputElement).value,
      ).toBe("copy");
    });

    it("says MODIFIED once the board drifts, and Save re-points the view at it", async () => {
      savedViewsList.mockResolvedValue([
        savedView({ name: "Copy work", config: { view: "list", filter: { text: "copy" } } }),
      ]);
      savedViewsUpdate.mockImplementation((_p, _v, patch) =>
        Promise.resolve(savedView({ name: "Copy work", config: {}, ...patch })),
      );
      render(<Harness />);
      await listLoaded();

      await openChooser();
      fireEvent.click(await screen.findByRole("option", { name: "Copy work" }));
      await waitFor(() => expect(screen.getByText("1 of 2 work items")).not.toBeNull());
      // Applied and matching: nothing has drifted, so there is nothing to save.
      expect(screen.queryByText("Modified")).toBeNull();
      expect(screen.queryByRole("button", { name: "Save" })).toBeNull();

      fireEvent.change(screen.getByRole("searchbox", { name: "Search work items" }), {
        target: { value: "landing" },
      });
      expect(await screen.findByText("Modified")).not.toBeNull();

      fireEvent.click(screen.getByRole("button", { name: "Save" }));
      await waitFor(() =>
        expect(savedViewsUpdate).toHaveBeenCalledWith("p1", "v1", {
          config: { view: "list", filter: { text: "landing" } },
        }),
      );
    });

    it("carries the Table's column sort into the view, and back out of it", async () => {
      savedViewsCreate.mockResolvedValue(savedView({ config: {} }));
      render(<Harness view="table" />);
      await screen.findByRole("button", { name: /^Title/ });

      fireEvent.click(screen.getByRole("button", { name: /^Title/ }));

      await openChooser("By title");
      fireEvent.click(await screen.findByRole("option", { name: /Save this view as/ }));

      // The sort is the Table's, but it is the SURFACE that stores it — a sort locked inside the
      // view could not be saved, and a saved view that forgot it would open in a different order
      // than the one that was named.
      await waitFor(() =>
        expect(savedViewsCreate).toHaveBeenCalledWith("p1", {
          name: "By title",
          config: { view: "table", sort: { key: "title", dir: "asc" } },
        }),
      );
    });

    it("widens to everything through the all-pass row, without changing view", async () => {
      savedViewsList.mockResolvedValue([
        savedView({ name: "Copy work", config: { view: "list", filter: { text: "copy" } } }),
      ]);
      const onSelectSpy = vi.fn();
      render(<Harness onSelectSpy={onSelectSpy} />);
      await listLoaded();

      await openChooser();
      fireEvent.click(await screen.findByRole("option", { name: "Copy work" }));
      await waitFor(() => expect(screen.getByText("1 of 2 work items")).not.toBeNull());
      onSelectSpy.mockClear();

      await openChooser();
      fireEvent.click(await screen.findByRole("option", { name: "All work items" }));

      // Widened, and still on the List: the all-pass answers "stop narrowing", which is not the
      // same request as "take me somewhere else".
      await waitFor(() => expect(screen.getByText("2 work items")).not.toBeNull());
      expect(onSelectSpy).not.toHaveBeenCalled();
      expect(bar().queryByRole("button", { name: "Delete" })).toBeNull();
    });

    it("deletes the applied view behind a confirm, leaving the board exactly as it is", async () => {
      savedViewsList.mockResolvedValue([
        savedView({ name: "Copy work", config: { view: "list", filter: { text: "copy" } } }),
      ]);
      savedViewsRemove.mockResolvedValue(undefined);
      render(<Harness />);
      await listLoaded();

      await openChooser();
      fireEvent.click(await screen.findByRole("option", { name: "Copy work" }));
      await waitFor(() => expect(screen.getByText("1 of 2 work items")).not.toBeNull());

      savedViewsList.mockResolvedValue([]);
      fireEvent.click(bar().getByRole("button", { name: "Delete" }));
      fireEvent.click(await screen.findByRole("button", { name: "Delete view" }));

      await waitFor(() => expect(savedViewsRemove).toHaveBeenCalledWith("p1", "v1"));
      // Deleting a name is not an instruction to change the subject: the narrowing stands, and
      // only the affordances that need a view to act on go away.
      await waitFor(() => expect(bar().queryByRole("button", { name: "Rename…" })).toBeNull());
      expect(screen.getByText("1 of 2 work items")).not.toBeNull();
    });

    it("renames the applied view from the dialog, and refuses an unchanged name", async () => {
      savedViewsList.mockResolvedValue([savedView({ name: "Copy work", config: {} })]);
      savedViewsUpdate.mockResolvedValue(savedView({ name: "Copy, everywhere", config: {} }));
      render(<Harness />);
      await listLoaded();

      await openChooser();
      fireEvent.click(await screen.findByRole("option", { name: "Copy work" }));
      fireEvent.click(await screen.findByRole("button", { name: "Rename…" }));

      const field = (await screen.findByRole("textbox", { name: "View name" })) as HTMLInputElement;
      expect(field.value).toBe("Copy work");
      // A rename to the same name is a write that says nothing.
      expect(screen.getByRole("button", { name: "Rename" })).toHaveProperty("disabled", true);

      fireEvent.change(field, { target: { value: "Copy, everywhere" } });
      fireEvent.click(screen.getByRole("button", { name: "Rename" }));

      await waitFor(() =>
        expect(savedViewsUpdate).toHaveBeenCalledWith("p1", "v1", { name: "Copy, everywhere" }),
      );
      await waitFor(() => expect(screen.queryByRole("textbox", { name: "View name" })).toBeNull());
    });

    it("shows the failure rather than pretending the view was saved", async () => {
      savedViewsCreate.mockRejectedValue(new Error("A view named that already exists."));
      render(<Harness />);
      await listLoaded();

      await openChooser("Copy work");
      fireEvent.click(await screen.findByRole("option", { name: /Save this view as/ }));

      expect(await screen.findByText("A view named that already exists.")).not.toBeNull();
    });
  });

  // ── The header's API slot ──────────────────────────────────────────────────
  // The editor used to draw its own API button in the body, beside ItemKey (`useRecordAffordance`);
  // it now lives once, in this surface's FeatureTitle header — disabled while browsing (no single
  // record is in view) and pointed at the OPEN item once the editor is showing.
  describe("the header's API affordance", () => {
    /** Wraps Harness with a host renderer so the live/disabled distinction is observable: with no
     *  provider, HeaderApiButton always falls back to the disabled button regardless of `api`. */
    function HarnessWithHost(props: Parameters<typeof Harness>[0]) {
      const render = (p: { path: string; pathValues: Record<string, string | null | undefined> }) => (
        <button type="button" aria-label={`Live API ${p.path}`}>
          API
        </button>
      );
      return (
        <RecordAffordanceContext.Provider value={render}>
          <Harness {...props} />
        </RecordAffordanceContext.Provider>
      );
    }

    it("shows the disabled API button while browsing the list — no single record is open", async () => {
      render(<HarnessWithHost />);
      await listLoaded();

      expect(
        screen.getByRole("button", { name: "API — This view has no API endpoint" }),
      ).not.toBeNull();
      expect(screen.queryByRole("button", { name: /^Live API/ })).toBeNull();
    });

    it("points the header's API button at the open item once the editor is showing", async () => {
      render(<HarnessWithHost view="table" />);
      fireEvent.doubleClick(await screen.findByText("Design the landing page"));
      await screen.findByRole("button", { name: "Save changes" });

      // The header now carries a LIVE button for w1's own endpoint…
      expect(
        screen.getByRole("button", { name: "Live API /project/work-items/{id}" }),
      ).not.toBeNull();
      // …the disabled fallback is gone…
      expect(screen.queryByRole("button", { name: "API — This view has no API endpoint" })).toBeNull();
      // …and it is the ONLY API affordance on screen — the editor body draws none of its own.
      expect(screen.getAllByRole("button", { name: /API/ })).toHaveLength(1);
    });
  });
});
