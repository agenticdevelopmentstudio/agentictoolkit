// @vitest-environment jsdom
//
// Component test for ProgramsPane — the layer ABOVE the boards as a master/detail topic.
//
// Only the api-client boundary is mocked, so the pane runs on the REAL master/detail substrate
// (published rail level, URL-driven selection, ButtonBar, delete confirm) and the real
// useResourceList. Three properties carry the weight, and each is a claim a screenshot cannot
// check:
//
//   1. A program belongs to the WORKSPACE, not to the board you reached it through. Every read is
//      asserted to carry the workspace and nothing else — the mirror image of MilestonesPane's
//      projectId assertion, and the first thing a well-meaning "programs are just big milestones"
//      change would break.
//   2. The member boards each wear their OWN health, and no rolled-up program verdict is invented
//      anywhere on the pane. That restraint is the API's own decision; a pane that quietly folded
//      four boards into one colour would be asserting a judgement nobody made.
//   3. "Nobody has reported" is the ABSENCE of a claim, so it reads as a sentence rather than as a
//      fourth badge tone — asserted structurally (`data-slot="badge"`), because the difference
//      between a grey pill and a grey sentence is exactly what a text-only check cannot see.
//
// The module-scope useResourceList cache is keyed by workspace (the pane's list) and by program id
// (the member boards) and OUTLIVES cleanup(), so every test below gets a fresh slug AND fresh
// program ids; the hook always refetches on mount, so a shared key would only affect a first
// paint, but the tests asserting on an empty or different list are the ones that would suffer it.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { useState } from "react";
import { render, screen, fireEvent, waitFor, cleanup, within } from "@testing-library/react";

vi.mock("@agentic-toolkit/data/projects", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@agentic-toolkit/data/projects")>()),
  projectProgramsApi: {
    list: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    remove: vi.fn(),
    // The member boards — a SECOND read, on its own cache key and its own scope.
    projects: vi.fn(),
  },
}));

import { ProgramsPane, programSublabel } from "./ProgramsPane";
import {
  projectProgramsApi,
  type Program,
  type Project,
} from "@agentic-toolkit/data/projects";
import { RailHostBoundary, type TopicLeaf } from "@agentic-toolkit/resource";

const list = vi.mocked(projectProgramsApi.list);
const create = vi.mocked(projectProgramsApi.create);
const update = vi.mocked(projectProgramsApi.update);
const remove = vi.mocked(projectProgramsApi.remove);
const memberBoards = vi.mocked(projectProgramsApi.projects);

function program(over: Partial<Program>): Program {
  return {
    id: "pg1",
    name: "Platform",
    description: "",
    color: "#007AFF",
    ownerKind: "customer",
    ownerId: "cust-1",
    startDate: "2026-07-01",
    targetDate: "2026-12-31",
    ecosystemId: "eco-1",
    createdAt: "2026-07-30T00:00:00Z",
    updatedAt: "2026-07-30T00:00:00Z",
    ...over,
  };
}

function board(over: Partial<Project>): Project {
  return {
    id: "p1",
    name: "Web",
    description: "",
    status: "active",
    color: "#007AFF",
    keyPrefix: "WEB",
    ecosystemId: "eco-1",
    archivedAt: null,
    estimateScale: "none",
    priorityScale: "standard",
    itemNoun: "work item",
    itemNounPlural: "work items",
    startDate: null,
    targetDate: null,
    leadKind: null,
    leadId: null,
    programId: "pg1",
    health: null,
    healthUpdatedAt: null,
    createdAt: "2026-07-30T00:00:00Z",
    updatedAt: "2026-07-30T00:00:00Z",
    ...over,
  };
}

/** A fresh workspace slug AND fresh program ids per test — see the cache note at the top. */
let n = 0;
let slug = "";
let PLATFORM: Program;
let LAUNCH: Program;

beforeEach(() => {
  vi.clearAllMocks();
  n += 1;
  slug = `acme-${n}`;
  PLATFORM = program({ id: `pg-${n}-1` });
  LAUNCH = program({
    id: `pg-${n}-2`,
    name: "Launch",
    startDate: null,
    targetDate: "2026-09-30",
  });
  list.mockResolvedValue([structuredClone(PLATFORM), structuredClone(LAUNCH)]);
  memberBoards.mockResolvedValue([]);
  create.mockImplementation((input) =>
    Promise.resolve(
      program({
        ...input,
        id: "pg-new",
        description: input.description ?? "",
        color: input.color ?? "#007AFF",
      }),
    ),
  );
  update.mockImplementation((id, patch) =>
    Promise.resolve(program({ ...structuredClone(PLATFORM), id, ...patch })),
  );
  remove.mockResolvedValue({ unassigned: 0 });
});

// The hub vitest config has no global afterEach — tear down each render explicitly.
afterEach(cleanup);

/** The pane's list is a published rail LEVEL, so the harness mounts a RailHostBoundary (with no
 *  host above it, that is the same standalone host a feature site gives the feature). A stateful
 *  leaf deep-links the open program the way ResourceExplorer's URL leaf would. */
function Harness({
  workspaceSlug,
  selected = null,
  onSelectSpy,
}: {
  workspaceSlug: string;
  selected?: string | null;
  onSelectSpy?: (id: string | null) => void;
}) {
  const [leafId, setLeafId] = useState<string | null>(selected);
  const leaf: TopicLeaf = {
    leafId,
    onSelect: (id) => {
      onSelectSpy?.(id);
      setLeafId(id);
    },
  };
  return (
    <RailHostBoundary>
      <ProgramsPane title="Programs" leaf={leaf} workspaceSlug={workspaceSlug} />
    </RailHostBoundary>
  );
}

describe("ProgramsPane", () => {
  it("publishes the WORKSPACE's programs as a rail level, spanned by their dates", async () => {
    render(<Harness workspaceSlug={slug} />);

    const rail = await screen.findByRole("complementary", { name: "Topic list" });
    const row = await within(rail).findByRole("button", { name: /Platform/ });
    expect(row.textContent).toContain("Jul 1, 2026 → Dec 31, 2026");

    // Pinned to the WORKSPACE, where the milestones pane pins to the board. That difference IS the
    // feature: a program spans several boards, so narrowing this list to the board it was reached
    // through would turn a workspace-wide roll-up into a per-board label.
    expect(list).toHaveBeenCalledWith({ workspace: slug });
  });

  it("opens the selected program in the editor, seeded from the record", async () => {
    render(<Harness workspaceSlug={slug} selected={PLATFORM.id} />);

    expect(await screen.findByDisplayValue("Platform")).not.toBeNull();
    expect(screen.getByDisplayValue("2026-07-01")).not.toBeNull();
    expect(screen.getByDisplayValue("2026-12-31")).not.toBeNull();
    expect(screen.getByDisplayValue("#007AFF")).not.toBeNull();
  });

  it("seeds a row that carries no accent with the platform's own, not with blank", async () => {
    // The column is `min(1)`, so an empty accent is refused on the next save — a row from before
    // the default existed would otherwise be unsaveable for a reason the form never states.
    list.mockResolvedValue([program({ id: PLATFORM.id, color: "" })]);
    render(<Harness workspaceSlug={slug} selected={PLATFORM.id} />);

    expect(await screen.findByDisplayValue("#007AFF")).not.toBeNull();
  });

  it("lists the member boards, each wearing its OWN health", async () => {
    memberBoards.mockResolvedValue([
      board({ id: "p1", name: "Web", health: "on_track", targetDate: "2026-10-01" }),
      board({ id: "p2", name: "API", health: "at_risk" }),
      board({ id: "p3", name: "Docs", health: null }),
    ]);
    render(<Harness workspaceSlug={slug} selected={PLATFORM.id} />);

    expect(await screen.findByText("Web")).not.toBeNull();
    // The board named API, not the header's API button.
    expect(screen.getByText("API", { ignore: 'button, script, style' })).not.toBeNull();
    expect(screen.getByText("Docs")).not.toBeNull();
    expect(screen.getByText("3 boards")).not.toBeNull();
    expect(screen.getByText("Oct 1, 2026")).not.toBeNull();

    // The boards are read by PROGRAM, not by workspace: this is the roll-up's membership, and it
    // is the one read on the pane that is scoped to a single record.
    expect(memberBoards).toHaveBeenCalledWith(PLATFORM.id);

    // No rolled-up verdict anywhere. A fold over {on track, at risk, nobody said} would land on
    // "At risk" — so a second one appearing is the signal that someone invented the summary this
    // pane and the API both refuse to make.
    expect(screen.getAllByText("At risk")).toHaveLength(1);
    expect(screen.getAllByText("On track")).toHaveLength(1);
  });

  it("says nobody has reported as a SENTENCE, not as a fourth badge tone", async () => {
    // Structural, not textual: the defect this guards against is a grey pill sitting beside two
    // coloured ones, which reads as a third claim rather than as the absence of one. Only the
    // element's shape can tell those apart.
    memberBoards.mockResolvedValue([
      board({ id: "p1", name: "Web", health: "on_track" }),
      board({ id: "p2", name: "Docs", health: null }),
    ]);
    render(<Harness workspaceSlug={slug} selected={PLATFORM.id} />);

    const said = await screen.findByText("No health reported");
    expect(said.getAttribute("data-slot")).toBeNull();
    expect(screen.getByText("On track").getAttribute("data-slot")).toBe("badge");
  });

  it("names where a membership is edited when the program has no boards", async () => {
    // A membership is a fact about the BOARD (`project.programId`), so it is written where the
    // board is. Without that sentence the empty state is a dead end: nothing on this pane adds a
    // board, and there is no reason a reader would guess why.
    render(<Harness workspaceSlug={slug} selected={PLATFORM.id} />);

    expect(await screen.findByText("No boards in this program yet.")).not.toBeNull();
    expect(
      screen.getByText(
        "A board joins a program from its own Project settings — a membership is a fact about the board.",
      ),
    ).not.toBeNull();
  });

  it("saves an edit as a PATCH carrying the form's fields", async () => {
    render(<Harness workspaceSlug={slug} selected={PLATFORM.id} />);

    fireEvent.change(await screen.findByDisplayValue("Platform"), {
      target: { value: "Platform 2027" },
    });
    fireEvent.change(screen.getByDisplayValue("2026-12-31"), { target: { value: "2027-03-31" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    // No workspace argument on the update: the program already exists and addresses itself by id.
    // Passing one would invite the reading that a program can be MOVED between workspaces, which
    // the backend does not allow.
    await waitFor(() =>
      expect(update).toHaveBeenCalledWith(PLATFORM.id, {
        name: "Platform 2027",
        description: "",
        color: "#007AFF",
        startDate: "2026-07-01",
        targetDate: "2027-03-31",
      }),
    );
  });

  it("clears an end as an explicit null", async () => {
    // "" is the form's unset; null is the wire's. An omitted field would leave the date it was
    // being cleared of — and a standing program with no ends is an ordinary state, not an error.
    render(<Harness workspaceSlug={slug} selected={PLATFORM.id} />);

    fireEvent.change(await screen.findByDisplayValue("2026-07-01"), { target: { value: "" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() =>
      expect(update).toHaveBeenCalledWith(PLATFORM.id, {
        name: "Platform",
        description: "",
        color: "#007AFF",
        startDate: null,
        targetDate: "2026-12-31",
      }),
    );
  });

  it("refuses a target that precedes the start, before the round trip", async () => {
    render(<Harness workspaceSlug={slug} selected={PLATFORM.id} />);

    fireEvent.change(await screen.findByDisplayValue("2026-07-01"), {
      target: { value: "2027-01-15" },
    });

    // The backend's own rule, restated so the reason arrives without a 400. The two ends are
    // independent — either may be absent — so this is the ONLY thing that relates them.
    expect(await screen.findByText("The target date is before the start date.")).not.toBeNull();
  });

  it("refuses a name another live program in the WORKSPACE already has", async () => {
    render(<Harness workspaceSlug={slug} selected={PLATFORM.id} />);

    fireEvent.change(await screen.findByDisplayValue("Platform"), { target: { value: "launch" } });

    // Case-insensitively, which is stricter than the database's exact-match uniqueness: this can
    // only warn early, never permit something the server would refuse with a 409. Scoped to the
    // workspace — where a milestone's is scoped to its board — because a program spans boards, so
    // the same name under two boards' shared owner really is a collision.
    expect(
      await screen.findByText('A program named "launch" already exists in this workspace.'),
    ).not.toBeNull();
  });

  it("says what deleting a program does to its boards", async () => {
    render(<Harness workspaceSlug={slug} selected={PLATFORM.id} />);

    // Wait for the PROGRAM, not for the button: the bar is on screen from the first paint with
    // Delete disabled, so a click issued before the list lands is dropped on a disabled control
    // and the confirm never opens. What makes Delete live is having a row to delete.
    await screen.findByDisplayValue("Platform");
    fireEvent.click(screen.getByRole("button", { name: "Delete" }));

    // The sentence that makes this delete safe, and the reason it never refuses: "in no program"
    // is an ordinary state for a board, so the sweep always has a defined outcome.
    expect(
      await screen.findByText(
        'Delete "Platform"? Its boards are not deleted — they stop rolling up into any program.',
      ),
    ).not.toBeNull();
  });

  it("creates through a MODAL, in the workspace the pane was opened for", async () => {
    const onSelectSpy = vi.fn();
    render(<Harness workspaceSlug={slug} onSelectSpy={onSelectSpy} />);

    // The level's own "+" affordance, not a button in the leaf: creating belongs to the LIST.
    await screen.findByRole("complementary", { name: "Topic list" });
    fireEvent.click(screen.getByRole("button", { name: "New program" }));

    const dialog = await screen.findByRole("dialog", { name: "New program" });
    fireEvent.change(within(dialog).getByLabelText("Name"), { target: { value: "Mobile" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Save" }));

    // Undated at both ends, and each travels as an explicit null — a standing program is the
    // ordinary case, so the modal must not require a date to get past it. The workspace rides
    // along because a program has to be created IN one; it is not inferred from anything on
    // screen.
    await waitFor(() =>
      expect(create).toHaveBeenCalledWith(
        {
          name: "Mobile",
          description: "",
          color: "#007AFF",
          startDate: null,
          targetDate: null,
        },
        { workspace: slug },
      ),
    );
    await waitFor(() => expect(onSelectSpy).toHaveBeenCalledWith("pg-new"));
  });
});

// The rail row's second line. A pure fold, so it is tested directly rather than through four
// renders — what matters is that all four shapes have a reading, because both ends are optional
// AND independent and a blank line reads as data that failed to load.
describe("programSublabel", () => {
  it("reads a bounded program as a span", () => {
    expect(programSublabel(program({}))).toBe("Jul 1, 2026 → Dec 31, 2026");
  });

  it("leads with the target when only the end is known", () => {
    // The ordinary shape for a delivery program: everyone agrees on the date long before anyone
    // commits to starting.
    expect(programSublabel(program({ startDate: null }))).toBe("Due Dec 31, 2026");
  });

  it("reads an open-ended program as running FROM its start", () => {
    expect(programSublabel(program({ targetDate: null }))).toBe("From Jul 1, 2026");
  });

  it("says a standing program has no dates rather than leaving the line empty", () => {
    expect(programSublabel(program({ startDate: null, targetDate: null }))).toBe("No dates");
  });
});
